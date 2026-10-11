'use strict';

const fs = require('fs');
const path = require('path');
const axios = require('axios');
const sharp = require('../../../utils/sharpConfigured');

const networkProxyUtil = require('../../../utils/networkProxyUtil');
const { extractAvId } = require('./avIdExtractor');
const { scrapeByDvdId } = require('./javScraper');

/** 从扩展名去掉后缀。 */
function stripExt(name) {
  return String(name || '').replace(/\.[^.\\/]+$/, '');
}

/**
 * 从一条索引记录里推断番号：文件名 -> nfo_name -> 所在文件夹名，依次尝试。
 * @param {{filename?: string, path?: string, nfoName?: string, nfo_name?: string}} row
 * @returns {string} 番号，失败返回空串
 */
function extractAvIdFromRow(row) {
  const r = row && typeof row === 'object' ? row : {};
  const candidates = [stripExt(r.filename), stripExt(r.nfoName || r.nfo_name), path.basename(String(r.path || ''))];
  for (const c of candidates) {
    if (!c) continue;
    const id = extractAvId(c);
    if (id) return id;
  }
  return '';
}

/** 从发布日期里取年份。 */
function pickYear(dateStr) {
  const m = String(dateStr || '').match(/\b(19|20)\d{2}\b/);
  const y = m ? Number(m[0]) : 0;
  return y >= 1900 && y <= 2100 ? y : 0;
}

/**
 * 把抓取到的 meta 映射成 jellyfinNfo.buildMovieNfo 需要的结构。
 * 日文站点的信息偏少：没有剧情简介、没有评分，这里如实留空，不做编造。
 */
function buildJavNfoData(meta) {
  const m = meta && typeof meta === 'object' ? meta : {};
  const genres = Array.isArray(m.genres) ? m.genres.filter(Boolean) : [];
  const tags = [m.producer, m.publisher, m.serial].map(s => String(s || '').trim()).filter(Boolean);
  const actors = (Array.isArray(m.actresses) ? m.actresses : [])
    .filter(Boolean)
    .map(name => ({ name: String(name).trim(), role: '', thumb: '', tmdbId: '' }));
  const directors = m.director ? [{ name: String(m.director).trim(), thumb: '', tmdbId: '' }] : [];

  return {
    title: String(m.title || '').trim(),
    originalTitle: '',
    sortTitle: '',
    year: pickYear(m.publishDate),
    premiered: m.publishDate || '',
    plot: '',
    rating: 0,
    genres,
    tags,
    countries: ['Japan'],
    languages: ['Japanese'],
    tmdbId: '',
    imdbId: '',
    actors,
    directors,
  };
}

/**
 * 下载封面并转成 jpg。目标文件已存在则跳过。
 * @param {{url: string, targetPath: string, proxyUrl?: string, timeoutMs?: number}} params
 * @returns {Promise<boolean>}
 */
async function downloadCoverToJpeg({ url, targetPath, proxyUrl = '', timeoutMs = 20000 }) {
  const src = String(url || '').trim();
  const out = String(targetPath || '').trim();
  if (!src || !out) return false;

  try {
    if (fs.existsSync(out) && fs.statSync(out).isFile()) return false;
  } catch (_) {}

  const agent = proxyUrl ? networkProxyUtil.createHttpsProxyAgent(proxyUrl) : null;
  let buffer = null;
  try {
    const res = await axios.get(src, {
      responseType: 'arraybuffer',
      timeout: timeoutMs,
      maxRedirects: 5,
      decompress: true,
      proxy: false,
      headers: {
        'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/115.0.0.0 Safari/537.36',
        Referer: `${new URL(src).origin}/`,
      },
      ...(agent ? { httpsAgent: agent, httpAgent: agent } : {}),
    });
    buffer = Buffer.from(res.data);
  } catch (_) {
    return false;
  }
  if (!buffer || buffer.length === 0) return false;

  const tmp = `${out}.${Date.now()}.tmp`;
  try {
    await fs.promises.writeFile(tmp, buffer);
    await sharp(tmp).jpeg({ quality: 85 }).toFile(out);
    try {
      fs.unlinkSync(tmp);
    } catch (_) {}
    return true;
  } catch (_) {
    try {
      fs.unlinkSync(tmp);
    } catch (_) {}
    try {
      fs.unlinkSync(out);
    } catch (_) {}
    return false;
  }
}

/**
 * 走「日本片兜底识别」：提取番号 -> 抓取 -> 返回 meta。
 * 找不到番号或所有站点都抓不到时返回 null。
 */
async function fetchJavMeta({ filename, folderName, nfoName, proxyUrl = '', timeoutMs } = {}) {
  const dvdid = extractAvIdFromRow({ filename, path: folderName, nfoName });
  if (!dvdid) return null;
  const meta = await scrapeByDvdId(dvdid, { proxyUrl, timeoutMs }).catch(() => null);
  if (!meta) return null;
  return meta;
}

module.exports = {
  extractAvIdFromRow,
  buildJavNfoData,
  downloadCoverToJpeg,
  fetchJavMeta,
};
