'use strict';

/**
 * 影视模块「路径可见性」统一口径工具。
 *
 * ⚠️ 为什么需要这个文件：
 * 之前同一个「这个视频对当前用户可见吗」的问题，三处实现**各不相同**：
 *   1. 列表页   `list/videoListService._applyVideoIndexPathPrefixFilter`
 *      → 前缀匹配（带分隔符边界）**+ 目录行特判**
 *   2. 库计数   `library/videoLibraryService._applyIndexPathFilter`
 *      → 只有前缀匹配，**没有目录行特判**；而且上游用 `validSet.has(p)` 精确比对
 *   3. 详情鉴权 `detail/detailController._ensureIndexAccess`
 *      → 走 `permissionUtil.hasPermission`，单向下沉 + 独立动作集
 *
 * 口径不一致造成的真实后果：
 *   - **子账号「列表能看、点详情 403」**：授权 `E:\Media\TV\BreakingBad`、来源 `E:\Media\TV` 时，
 *     `getValidPaths` 取较长者 → 可见根 = `...\BreakingBad`；列表靠「目录行特判」命中
 *     容器行（path=父目录, filename=剧名）所以能显示，详情却拿 `path=E:\Media\TV`
 *     去比对，`E:\Media\TV`.startsWith(`...\BreakingBad\`) === false → 403。
 *   - **库计数虚低**：可见来源路径比授权路径短时，`validSet.has()` 精确比对匹配不上 → 算成 0，
 *     左侧栏出现「列表里有片子但库显示 0」。
 *
 * 这里把「一组可见路径 → 索引行是否可见」收敛成一份实现，三方共用。
 */

const path = require('path');

/**
 * LIKE 通配符转义。
 *
 * ⚠️⚠️ 这里踩过一个真实的坑，别再改回去：
 * 仓库里其它模块（book/music 等）的 `_escapeLikeValue` 会**把反斜杠也翻倍**：
 *     `.replaceAll('\\', '\\\\')`
 * 但 **SQLite 的 LIKE 默认不认识 `\` 转义**（没有 ESCAPE 子句时 `\` 就是普通字符）。
 * 实测（sqlite 内存库）：
 *     'E:\Media\sub' LIKE 'E:\Media\%'      -> 1   ✅ 未转义
 *     'E:\Media\sub' LIKE 'E:\\Media\\%'    -> 0   ❌ 反斜杠翻倍后反而不匹配
 * Windows 路径全是反斜杠 ⇒ 只要照抄那份实现，**所有前缀匹配都会静默失效**
 * （库计数会因为只有「精确匹配」那一半生效而严重偏低，表现为「列表里有片子、库却显示 0」）。
 *
 * 所以：只转义 LIKE 自己的两个通配符 `%` `_`，并且**必须配合 ESCAPE 子句**一起用
 * （见 `LIKE_ESCAPE` / `applyVisibleIndexFilter`）。逃逸字符选 `^` 而不是 `\`，
 * 避免和路径分隔符打架。
 */
const LIKE_ESCAPE = '^';

function escapeLikeValue(input) {
  return String(input || '')
    .replaceAll(LIKE_ESCAPE, LIKE_ESCAPE + LIKE_ESCAPE)
    .replaceAll('%', LIKE_ESCAPE + '%')
    .replaceAll('_', LIKE_ESCAPE + '_');
}

/**
 * 某个具体路径是否被「可见路径集合」覆盖（单个值判断，用于详情鉴权这种已知行的场景）。
 *
 * 采用**双向**包含，与 `videoSourceService.getValidPaths` 内部一致：
 * 授权路径可能是来源目录的**子目录**（授权 `...\TV\BreakingBad`、来源 `...\TV`），
 * 也可能是来源目录的**父目录**。两种方向都要算可见，否则就会出现「列表能看、详情 403」。
 */
function isPathVisibleTo(targetPath, validPaths) {
  const t = String(targetPath || '').trim();
  if (!t) return false;
  const list = Array.isArray(validPaths) ? validPaths : [];
  const sep = path.sep;
  for (const raw of list) {
    const s = String(raw || '').trim();
    if (!s) continue;
    if (t === s) return true;
    if (t.startsWith(s.endsWith(sep) ? s : s + sep)) return true;
    if (s.startsWith(t.endsWith(sep) ? t : t + sep)) return true;
  }
  return false;
}

/**
 * 把「索引行对用户可见」的条件套到 knex query 上。**列表页 / 库计数 / 详情三方共用**。
 *
 * 条件（与列表页原实现保持一致）：
 *   1. `path` 等于某可见路径，或位于其下（带分隔符边界）
 *   2. **目录行特判**：`is_file = 0` 且 `path = 父目录` 且 `filename = 子目录名`
 *      —— 电视剧库的「剧集文件夹」就是这种容器行，代表整部剧；
 *      它的 `path` 只是父目录，不特判就会整个库看不见。
 *
 * @param {*} query knex query builder（需已 from 好表或带别名）
 * @param {string[]} validPaths 用户可见路径（来自 videoSourceService.getValidPaths）
 * @param {{alias?: string}} [opts] alias 为表别名（有 join 时必传，如 'v'；单表可省略）
 */
function applyVisibleIndexFilter(query, validPaths, opts = {}) {
  const list = Array.isArray(validPaths)
    ? validPaths.map(p => String(p || '').trim()).filter(Boolean)
    : [];

  if (list.length === 0) {
    // 没有任何可见路径 ⇒ 什么都不该看到（不能退化成「不过滤」，那会越权）
    query.whereRaw('1 = 0');
    return query;
  }

  const alias = opts && opts.alias ? String(opts.alias) : '';
  const col = name => (alias ? `${alias}.${name}` : name);
  const sep = path.sep;

  // 目录行特判只对「看起来像目录」的路径生效（无扩展名）
  const folderExactPairs = [];
  for (const raw of list) {
    const p = raw.endsWith(sep) ? raw.slice(0, -1) : raw;
    if (!p) continue;
    if (path.extname(p)) continue;
    const parent = path.dirname(p);
    const name = path.basename(p);
    if (!parent || !name || parent === p) continue;
    folderExactPairs.push({ parent, name });
  }

  query.where(builder => {
    for (const p of list) {
      const prefix = p.endsWith(sep) ? p : `${p}${sep}`;
      builder.orWhere(function () {
        // ⚠️ 必须用 whereRaw + ESCAPE 传转义字符；knex 的 (col,'like',pattern) 形式
        // 不支持 ESCAPE 子句，直接用会变成上面注释里那个「反斜杠翻倍匹配不上」的坑。
        // ?? = 标识符占位（防注入）、? = 值占位。
        this.where(col('path'), p).orWhereRaw('?? LIKE ? ESCAPE ?', [
          col('path'),
          `${escapeLikeValue(prefix)}%`,
          LIKE_ESCAPE,
        ]);
      });
    }
    for (const pair of folderExactPairs) {
      builder.orWhere(function () {
        this.where(col('is_file'), 0).andWhere(col('path'), pair.parent).andWhere(col('filename'), pair.name);
      });
    }
  });

  return query;
}

module.exports = {
  LIKE_ESCAPE,
  escapeLikeValue,
  isPathVisibleTo,
  applyVisibleIndexFilter,
};
