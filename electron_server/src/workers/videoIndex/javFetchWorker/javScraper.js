'use strict';

/**
 * 日本片信息抓取器。
 *
 * 参考 JavSP 的 web 抓取层思路（按番号去站点详情页抠标题 / 封面 / 演员 / 分类，
 * 并且允许走代理），但实现完全重写：
 *   - 统一用 axios 发请求，代理通过 networkProxyUtil 构造的 CONNECT Agent 注入；
 *   - 站点解析用一组防御式正则（站点改版时只是「抓不到」而不会崩），
 *     失败即返回 null，交给调用方决定要不要换下一个站点；
 *   - 每个站点只负责把自己的 HTML 解析成统一的 meta 结构。
 *
 * 目前支持的站点：
 *   - javbus（有码，信息最全）
 *   - avsox（无码 / javbus 抓不到时的兜底）
 *   - fc2（FC2 PPV）
 */

const axios = require('axios');
const networkProxyUtil = require('../../../utils/networkProxyUtil');
const { guessAvType } = require('./avIdExtractor');

const DEFAULT_TIMEOUT_MS = 15000;

const SITE_BASE = {
  javbus: 'https://www.javbus.com',
  avsox: 'https://avsox.click',
  fc2: 'https://adult.contents.fc2.com',
};

const HEADERS = {
  'User-Agent':
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/115.0.0.0 Safari/537.36',
  Accept: 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
  'Accept-Language': 'zh-CN,zh;q=0.9,ja;q=0.8,en;q=0.7',
};

/* ------------------------------ HTML 小工具 ------------------------------ */

const BASIC_ENTITIES = {
  amp: '&',
  lt: '<',
  gt: '>',
  quot: '"',
  apos: "'",
  nbsp: ' ',
};

/** 解码 HTML 实体（含数字实体）。 */
function decodeEntities(input) {
  return String(input || '').replace(/&(#x[0-9a-f]+|#\d+|[a-z]+);/gi, (full, body) => {
    if (body[0] === '#') {
      const isHex = body[1] === 'x' || body[1] === 'X';
      const code = isHex ? parseInt(body.slice(2), 16) : parseInt(body.slice(1), 10);
      return Number.isFinite(code) ? String.fromCodePoint(code) : full;
    }
    const key = body.toLowerCase();
    return Object.prototype.hasOwnProperty.call(BASIC_ENTITIES, key) ? BASIC_ENTITIES[key] : full;
  });
}

/** 去掉标签、解码实体、压缩空白。 */
function stripTags(input) {
  const text = String(input || '').replace(/<[^>]*>/g, '');
  return decodeEntities(text).replace(/\s+/g, ' ').trim();
}

/** 从标签字符串里取属性值（兼容单/双引号）。 */
function attrOf(tag, name) {
  if (!tag) return '';
  const doubleQuoted = new RegExp(`${name}\\s*=\\s*"([^"]*)"`, 'i').exec(tag);
  if (doubleQuoted) return decodeEntities(doubleQuoted[1]).trim();
  const singleQuoted = new RegExp(`${name}\\s*=\\s*'([^']*)'`, 'i').exec(tag);
  return singleQuoted ? decodeEntities(singleQuoted[1]).trim() : '';
}

/** 把相对地址补成绝对地址。 */
function absoluteUrl(base, url) {
  const u = String(url || '').trim();
  if (!u) return '';
  if (/^https?:\/\//i.test(u)) return u;
  if (u.startsWith('//')) return `https:${u}`;
  return `${base.replace(/\/+$/, '')}/${u.replace(/^\/+/, '')}`;
}

/** 截取某个标签之后、到最近的块级结束标签之前的内容。 */
function cutBlock(rest) {
  const stops = ['</p>', '</div>', '</li>', '<br'];
  let end = rest.length;
  for (const stop of stops) {
    const i = rest.indexOf(stop);
    if (i !== -1 && i < end) end = i;
  }
  return rest.slice(0, end);
}

/** 取「标签: 值」结构里标签后面的值（值可能是纯文本，也可能包在 span/a 里）。 */
function fieldAfterLabel(html, label) {
  const idx = html.indexOf(label);
  if (idx === -1) return '';
  return stripTags(cutBlock(html.slice(idx + label.length)));
}

/** 取第一个 `<h3>` 的文本。 */
function firstH3Text(html) {
  const m = /<h3[^>]*>([\s\S]*?)<\/h3>/i.exec(html);
  return m ? stripTags(m[1]) : '';
}

/** 解析 javbus / avsox 详情页里的分类标签（class="genre" 下的链接）。 */
function parseGenreLinks(html) {
  const out = [];
  const re = /<span[^>]*class="[^"]*genre[^"]*"[^>]*>[\s\S]*?<a[^>]*>([\s\S]*?)<\/a>/gi;
  let m;
  while ((m = re.exec(html))) {
    const g = stripTags(m[1]);
    if (g && !out.includes(g)) out.push(g);
  }
  return out;
}

/** 解析 javbus / avsox 详情页里的演员（avatar-box）。 */
function parseAvatarActresses(html) {
  const out = [];
  const re = /<a[^>]*class="[^"]*avatar-box[^"]*"[^>]*>([\s\S]*?)<\/a>/gi;
  let m;
  while ((m = re.exec(html))) {
    const imgTag = /<img[^>]*>/i.exec(m[1]);
    const nameFromImg = imgTag ? attrOf(imgTag[0], 'title') : '';
    const name = nameFromImg || stripTags(m[1]);
    const pic = imgTag ? attrOf(imgTag[0], 'src') : '';
    if (!name) continue;
    out.push({
      name,
      pic: pic && !/nowprinting\.gif$/i.test(pic) ? pic : '',
    });
  }
  return out;
}

/** 从「数字 分钟 / hh:mm:ss」这类文本里解析时长（分钟）。 */
function parseDurationMinutes(text) {
  const s = String(text || '').trim();
  if (!s) return 0;
  const hms = /(\d{1,2}):(\d{1,2}):(\d{2})/.exec(s);
  if (hms) {
    return Math.round(Number(hms[1]) * 60 + Number(hms[2]) + Number(hms[3]) / 60);
  }
  const min = /(\d{1,4})\s*(?:分|min|minutes?)/i.exec(s);
  if (min) return Number(min[1]) || 0;
  const bare = /^(\d{1,4})$/.exec(s);
  return bare ? Number(bare[1]) : 0;
}

/* ------------------------------ HTTP ------------------------------ */

/**
 * 发起 GET 请求。传了 proxyUrl 就走代理（HTTP CONNECT 隧道）。
 * @returns {Promise<string|null>} 响应正文；请求失败返回 null
 */
async function httpGetText(url, { proxyUrl = '', timeoutMs = DEFAULT_TIMEOUT_MS } = {}) {
  const agent = proxyUrl ? networkProxyUtil.createHttpsProxyAgent(proxyUrl) : null;
  try {
    const res = await axios.get(url, {
      headers: HEADERS,
      timeout: timeoutMs,
      maxRedirects: 5,
      decompress: true,
      responseType: 'text',
      transformResponse: [d => d],
      validateStatus: status => status >= 200 && status < 400,
      proxy: false,
      ...(agent ? { httpsAgent: agent, httpAgent: agent } : {}),
    });
    return typeof res.data === 'string' ? res.data : String(res.data ?? '');
  } catch (_) {
    return null;
  }
}

/* ------------------------------ 站点解析 ------------------------------ */

/** javbus：有码，信息最全。 */
async function scrapeJavbus(avid, opts) {
  const base = SITE_BASE.javbus;
  const html = await httpGetText(`${base}/${encodeURIComponent(avid)}`, opts);
  if (!html) return null;

  const pageTitle = stripTags((/<title[^>]*>([\s\S]*?)<\/title>/i.exec(html) || [])[1] || '');
  if (/404 Page Not Found/i.test(pageTitle)) return null;

  const title = firstH3Text(html);
  const coverTag = /<a[^>]*class="[^"]*bigImage[^"]*"[^>]*>[\s\S]*?<img[^>]*>/i.exec(html);
  const coverRaw = coverTag ? attrOf(coverTag[0].match(/<img[^>]*>/i)[0], 'src') : '';
  const cover = absoluteUrl(base, coverRaw);
  if (!title && !cover) return null;

  const dvdid = fieldAfterLabel(html, '識別碼:') || avid;
  const publishDate = fieldAfterLabel(html, '發行日期:');
  const duration = parseDurationMinutes(fieldAfterLabel(html, '長度:'));
  const actresses = parseAvatarActresses(html);

  return {
    source: 'javbus',
    dvdid,
    title: title.replace(dvdid, '').trim() || title,
    coverUrl: cover,
    publishDate: /^\d{4}-\d{2}-\d{2}$/.test(publishDate) ? publishDate : '',
    durationMinutes: duration,
    director: fieldAfterLabel(html, '導演:'),
    producer: fieldAfterLabel(html, '製作商:'),
    publisher: fieldAfterLabel(html, '發行商:'),
    serial: fieldAfterLabel(html, '系列:'),
    genres: parseGenreLinks(html),
    actresses: actresses.map(a => a.name),
    actressPics: actresses.reduce((acc, a) => (a.pic ? { ...acc, [a.name]: a.pic } : acc), {}),
    siteUrl: `${base}/${avid}`,
  };
}

/** avsox：无码 / javbus 兜底。avsox 不能直达详情页，要先搜索再取匹配项。 */
async function scrapeAvsox(avid, opts) {
  const base = SITE_BASE.avsox;
  const searchId = avid.replace(/^FC2-/i, 'FC2-PPV-');
  const searchHtml = await httpGetText(`${base}/cn/search/${encodeURIComponent(searchId)}`, opts);
  if (!searchHtml) return null;

  // 搜索结果：成对的「详情链接」与「番号」。按出现顺序对齐。
  const urls = [];
  const ids = [];
  const linkRe = /<a[^>]*class="[^"]*movie-box[^"]*"[^>]*href="([^"]+)"/gi;
  let m;
  while ((m = linkRe.exec(searchHtml))) urls.push(m[1]);
  const idRe = /<date[^>]*>([\s\S]*?)<\/date>/gi;
  while ((m = idRe.exec(searchHtml))) ids.push(stripTags(m[1]));

  const target = searchId.toLowerCase();
  let detailUrl = '';
  for (let i = 0; i < ids.length; i += 1) {
    if (String(ids[i]).toLowerCase() === target && urls[i]) {
      detailUrl = urls[i];
      break;
    }
  }
  if (!detailUrl) return null;

  const html = await httpGetText(absoluteUrl(base, detailUrl), opts);
  if (!html) return null;

  const title = firstH3Text(html);
  const coverTag = /<a[^>]*class="[^"]*bigImage[^"]*"[^>]*>/i.exec(html);
  const cover = coverTag ? absoluteUrl(base, attrOf(coverTag[0], 'href')) : '';
  if (!title && !cover) return null;

  const publishDate = fieldAfterLabel(html, '发行时间:');
  const producer = fieldAfterLabel(html, '制作商:');
  const serial = fieldAfterLabel(html, '系列:');
  const actresses = parseAvatarActresses(html);

  return {
    source: 'avsox',
    dvdid: avid,
    title: title.replace(avid, '').trim() || title,
    coverUrl: cover,
    publishDate: /^\d{4}-\d{2}-\d{2}$/.test(publishDate) ? publishDate : '',
    durationMinutes: parseDurationMinutes(fieldAfterLabel(html, '长度:')),
    director: '',
    producer: /^FC2-/i.test(avid) ? serial : producer,
    publisher: '',
    serial: /^FC2-/i.test(avid) ? '' : serial,
    genres: parseGenreLinks(html),
    actresses: actresses.map(a => a.name),
    actressPics: actresses.reduce((acc, a) => (a.pic ? { ...acc, [a.name]: a.pic } : acc), {}),
    siteUrl: absoluteUrl(base, detailUrl),
  };
}

/** fc2：FC2 PPV 专用。 */
async function scrapeFc2(avid, opts) {
  const idNum = String(avid).replace(/^FC2-/i, '').trim();
  if (!/^\d{5,7}$/.test(idNum)) return null;
  const base = SITE_BASE.fc2;
  const url = `${base}/article/${idNum}/`;
  const html = await httpGetText(url, opts);
  if (!html) return null;
  if (/id\.fc2\.com/i.test(html)) return null;

  const titleMatch = /<div[^>]*class="[^"]*items_article_headerInfo[^"]*"[^>]*>[\s\S]*?<h3[^>]*>([\s\S]*?)<\/h3>/i.exec(html);
  const title = titleMatch ? stripTags(titleMatch[1].replace(/<[^>]*>/g, '')) : firstH3Text(html);

  const thumbRank = /<div[^>]*class="[^"]*items_article_MainitemThumb[^"]*"[^>]*>([\s\S]*?)<\/div>/i.exec(html);
  const thumbBlock = thumbRank ? thumbRank[1] : '';
  const thumbImgTag = /<img[^>]*>/i.exec(thumbBlock);
  const thumb = thumbImgTag ? attrOf(thumbImgTag[0], 'src') : '';

  const previews = [];
  const sampleBlock = /data-feed="sample-images"[\s\S]*?<\/ul>/i.exec(html);
  if (sampleBlock) {
    let pm;
    const sre = /<a[^>]*href="([^"]+)"/gi;
    while ((pm = sre.exec(sampleBlock[0]))) previews.push(pm[1]);
  }

  const dateText = stripTags((/items_article_Releasedate[^>]*>[\s\S]*?<p[^>]*>([\s\S]*?)<\/p>/i.exec(html) || [])[1] || '');
  const publishDate = (dateText.match(/(\d{4})[/-](\d{1,2})[/-](\d{1,2})/) || [])
    .slice(1)
    .map((v, i) => (i === 0 ? v.padStart(4, '0') : v.padStart(2, '0')))
    .join('-');

  const producer = fieldAfterLabel(html, 'by ');

  const genres = [];
  const genreRe = /<a[^>]*class="[^"]*tagTag[^"]*"[^>]*>([\s\S]*?)<\/a>/gi;
  let gm;
  while ((gm = genreRe.exec(html))) {
    const g = stripTags(gm[1]);
    if (g && !genres.includes(g)) genres.push(g);
  }

  if (!title && !thumb) return null;

  return {
    source: 'fc2',
    dvdid: `FC2-${idNum}`,
    title,
    coverUrl: previews.length > 0 ? previews[0] : thumb,
    publishDate: /^\d{4}-\d{2}-\d{2}$/.test(publishDate) ? publishDate : '',
    durationMinutes: parseDurationMinutes(stripTags(thumbBlock)),
    director: '',
    producer,
    publisher: '',
    serial: '',
    genres,
    actresses: [],
    actressPics: {},
    siteUrl: url,
  };
}

/**
 * 根据番号类型挑选站点顺序，依次尝试，返回第一个成功的结果。
 * @param {string} dvdid 番号
 * @param {{proxyUrl?: string, timeoutMs?: number}} [options]
 * @returns {Promise<object|null>}
 */
async function scrapeByDvdId(dvdid, options = {}) {
  const id = String(dvdid || '').trim();
  if (!id) return null;

  const type = guessAvType(id);
  // fc2 先走 FC2 官网，其它（含无码 / 普通）都从 javbus 开始
  const order = type === 'fc2' ? [scrapeFc2, scrapeAvsox, scrapeJavbus] : [scrapeJavbus, scrapeAvsox];

  for (const scraper of order) {
    const result = await scraper(id, options).catch(() => null);
    if (result && (result.title || result.coverUrl)) return result;
  }
  return null;
}

module.exports = {
  scrapeByDvdId,
  parseDurationMinutes,
};
