'use strict';

/**
 * 番号（DVD ID / CID）识别。
 *
 * 思路参考 JavSP 的 avid 模块（从文件名里抠出番号、并判断属于哪种类型），
 * 但这里的实现是重新组织的：用一组「规则对象」按优先级依次尝试，
 * 便于阅读与增删，而不是把十几条正则硬编码在一个大 if/else 里。
 *
 * 对外只暴露三个方法：
 *   - extractAvId(text)      从一段文本（文件名 / 文件夹名）中提取番号，失败返回 ''
 *   - extractCid(text)       尝试把文本识别成 CID（FANZA 的数字内容编号），失败返回 ''
 *   - guessAvType(avid)      判断番号所属分类：normal / fc2 / getchu / gyutto / cid
 */

// 文件名里常见的「非番号」噪声词，匹配前先抹掉，减少误判。
const NOISE_WORDS = [
  'uncensored',
  'leak',
  'leaked',
  'hack',
  'reduced',
  'reduc',
  'no-?watermark',
  '水印',
  '無修正',
  '无码',
  '破解',
  '中文字幕',
  '中字',
  '-c$',
  'hd',
  'fhd',
  'uhd',
  '4k',
  '8k',
  '2160p',
  '1080p',
  '720p',
  '480p',
  'h264',
  'h265',
  'hevc',
  'avc',
  'aac',
  'x264',
  'x265',
  '10bit',
  '8bit',
];

const NOISE_RE = new RegExp(NOISE_WORDS.join('|'), 'gi');

/** 去掉噪声词并转大写，作为后续匹配用的标准文本。 */
function normalizeForMatch(text) {
  return String(text || '')
    .replace(NOISE_RE, '')
    .toUpperCase()
    .trim();
}

/** 巧克力糖式的小工具：逐个规则跑，命中即返回。*/
function firstMatch(text, rules) {
  for (const rule of rules) {
    const m = text.match(rule.re);
    if (m) return rule.pick(m);
  }
  return '';
}

/** 把形如 "ABC" + "001" 的片段拼成番号 "ABC-001"（保留数字段原始写法）。 */
function joinCode(prefix, num) {
  return `${prefix}-${num}`;
}

/**
 * 特殊厂商 / 特殊格式的番号规则（不区分大小写）。
 * 这些格式和普通「字母-数字」差别较大，必须先于普通规则匹配。
 */
const SPECIAL_RULES = [
  // FC2：编号为 5~7 位数字，可能夹着 PPV 之类的字样
  {
    re: /FC2[^A-Z\d]{0,5}(?:PPV[^A-Z\d]{0,5})?(\d{5,7})/i,
    pick: m => `FC2-${m[1]}`,
  },
  // HEYDOUGA：三段式编号
  {
    re: /(HEYDOUGA)[-_]*(\d{4})[-_]0?(\d{3,5})/i,
    pick: m => `${m[1].toUpperCase()}-${m[2]}-${m[3]}`,
  },
  // GETCHU
  {
    re: /GETCHU[-_]*(\d+)/i,
    pick: m => `GETCHU-${m[1]}`,
  },
  // GYUTTO
  {
    re: /GYUTTO-(\d+)/i,
    pick: m => `GYUTTO-${m[1]}`,
  },
  // 259LUXU 这种数字开头的特殊系列
  {
    re: /259LUXU-(\d+)/i,
    pick: m => `259LUXU-${m[1]}`,
  },
];

/** HEY 是 HEYDOUGA 的缩写写法 */
const HEY_SHORTHAND_RULE = {
  re: /(?:HEY)[-_]*(\d{4})[-_]0?(\d{3,5})/i,
  pick: m => `heydouga-${m[1]}-${m[2]}`,
};

/** 片商 MUGEN 的乱序番号（要先于普通规则匹配） */
const MUGEN_RULE = {
  re: /(MKB?D)[-_]*(S\d{2,3})|(MK3D2DBD|S2M|S2MBD)[-_]*(\d{2,3})/i,
  pick: m => (m[1] != null ? `${m[1].toUpperCase()}-${m[2].toUpperCase()}` : `${m[3].toUpperCase()}-${m[4]}`),
};

/** IBW 系列带 z 后缀 */
const IBW_RULE = {
  re: /(IBW)[-_](\d{2,5}z)/i,
  pick: m => `${m[1].toUpperCase()}-${m[2]}`,
};

/** 带分隔符的普通番号：ABC-123 */
const NORMAL_DASH_RULE = {
  re: /([A-Z]{2,10})[-_](\d{2,5})/,
  pick: m => joinCode(m[1], m[2]),
};

/** 东热 red / sky / ex 三个无分隔符系列（范围收紧降低误判） */
const TOKYO_HOT_RULE = {
  re: /(RED[01]\d\d|SKY[0-3]\d\d|EX00[01]\d)/,
  pick: m => m[1],
};

/** 视作丢了分隔符的普通番号：ABC123 */
const NORMAL_GLUED_RULE = {
  re: /([A-Z]{2,})(\d{2,5})/,
  pick: m => joinCode(m[1], m[2]),
};

/** TMA 家很乱的番号：T28-557 */
const TMA_RULE = { re: /(T[23]8[-_]\d{3})/, pick: m => m[1] };
/** 东热 n / k 系列 */
const N_OR_K_RULE = { re: /(N\d{4}|K\d{4})/i, pick: m => m[1].toUpperCase() };
/** R18-XXX */
const R18_RULE = { re: /(R18-?\d{3})/i, pick: m => m[1].toUpperCase() };
/** 纯数字无码番号：123456-789 */
const BARE_NUMBER_RULE = { re: /(\d{6}[-_]\d{2,3})/, pick: m => m[1] };

const DOMAIN_RE = /\w{3,10}\.(COM|NET|APP|XYZ)/gi;

/**
 * 从一段文本里提取番号。
 * @param {string} text 文件名（可带扩展名）或文件夹名
 * @returns {string} 提取到的番号，失败返回空串
 */
function extractAvId(text) {
  const norm = normalizeForMatch(text);
  if (!norm) return '';

  // 1) 特殊系列优先
  const special = firstMatch(norm, SPECIAL_RULES);
  if (special) return special;

  // 2) 先剔除可疑域名，再去掉扩展名残留后再试一次
  const noDomain = norm.replace(DOMAIN_RE, '');
  if (noDomain !== norm) {
    const inner = extractAvId(noDomain);
    if (inner) return inner;
  }

  // 3) 普通系列：带分隔符 -> 东热 -> 无分隔符
  const normal = firstMatch(noDomain, [
    HEY_SHORTHAND_RULE,
    MUGEN_RULE,
    IBW_RULE,
    NORMAL_DASH_RULE,
    TOKYO_HOT_RULE,
    NORMAL_GLUED_RULE,
  ]);
  if (normal) return normal;

  // 4) 其他零散格式
  const other = firstMatch(noDomain, [TMA_RULE, N_OR_K_RULE, R18_RULE, BARE_NUMBER_RULE]);
  if (other) return other;

  // 5) 少数影片用 ")(" 当分隔符
  if (noDomain.includes(')(')) {
    const fixed = extractAvId(noDomain.replace(/\)\(/g, '-'));
    if (fixed) return fixed;
  }

  return '';
}

/** 去掉文件名末尾的 CD 分段后缀（-1 / _2 / cd3）。 */
function stripCdSuffix(basename) {
  return String(basename || '').replace(/([-_]\w|cd\d)$/i, '');
}

/**
 * 尝试把文本识别成 CID（FANZA 的内容编号）。识别不了返回空串。
 * @param {string} text
 * @returns {string}
 */
function extractCid(text) {
  const base = stripCdSuffix(String(text || '').replace(/\.[^.\\/]+$/, ''));
  if (!/^[a-z\d_]+$/.test(base)) return '';

  if (!base.includes('_')) {
    // 绝大多数 cid 长度在 7~19 之间
    return /^[a-z\d]{7,19}$/.test(base) ? base : '';
  }

  // 含下划线的 cid：覆盖几种主流形态
  const patterns = [
    /^h_\d{3,4}[a-z]{1,10}\d{2,5}[a-z\d]{0,8}$/,
    /^\d{3}_\d{4,5}$/,
    /^402[a-z]{3,6}\d*_[a-z]{3,8}\d{5,6}$/,
    /^h_\d{3,4}wvr\d\w\d{4,5}[a-z\d]{0,8}$/,
  ];
  return patterns.some(re => re.test(base)) ? base : '';
}

/**
 * 判断番号类型。
 * @param {string} avid
 * @returns {'normal'|'fc2'|'getchu'|'gyutto'|'cid'}
 */
function guessAvType(avid) {
  const s = String(avid || '').trim();
  if (/^FC2-\d{5,7}$/i.test(s)) return 'fc2';
  if (/^GETCHU-\d+/i.test(s)) return 'getchu';
  if (/^GYUTTO-\d+/i.test(s)) return 'gyutto';
  if (extractCid(s) === s) return 'cid';
  return 'normal';
}

module.exports = {
  extractAvId,
  extractCid,
  guessAvType,
};
