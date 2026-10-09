const tableUser = require('../db/table/tableUser');
const tableUserPermission = require('../db/table/tableUserPermission');
const path = require('path');
const userShareFolderUtil = require('./userShareFolderUtil');
const { normalizePathItem } = require('./appAccessScopeUtil');

function parseAnyOrArray(text) {
  if (text === undefined || text === null) return 'ANY';
  if (text === 'ANY') return 'ANY';
  if (Array.isArray(text)) {
    const list = text.map(v => String(v || '').trim()).filter(Boolean);
    return list.length > 0 ? list : 'ANY';
  }
  const raw = String(text || '').trim();
  if (!raw) return 'ANY';
  if (raw === 'ANY') return 'ANY';
  try {
    const parsed = JSON.parse(raw);
    if (Array.isArray(parsed)) {
      const list = parsed.map(v => String(v || '').trim()).filter(Boolean);
      return list.length > 0 ? list : 'ANY';
    }
  } catch (_) {}
  return [raw];
}

function matchApi(allowedList, reqApi) {
  if (allowedList === 'ANY') return true;
  if (!Array.isArray(allowedList)) return true;
  const api = String(reqApi || '').trim();
  if (!api) return false;
  for (const a of allowedList) {
    const rule = String(a || '').trim();
    if (!rule) continue;
    if (api === rule) return true;
    if (api.startsWith(rule.endsWith('/') ? rule : `${rule}/`)) return true;
  }
  return false;
}

/**
 * 统一权限校验工具函数
 * @param {object} knex - Knex实例（主库）
 * @param {{userId:number, type:string}} user - 当前登录用户信息
 * @param {string|string[]} action - 操作动作（view/download/update/delete/modify）
 * @param {string} resPath - 资源路径（绝对/规范化路径）
 * @param {string} resType - 资源类型（默认：file）
 * @returns {Promise<boolean>} 是否有权限
 */
/**
 * scoped token 的 `allow_path` 边界检查（**单向下沉**：目标必须在授权目录之内）。
 *
 * 只有 `tokenRecord.type === 'scoped'` 的受限令牌才会带上 `allow_path`
 * （`authMiddleware.js:59-61`）—— 这是令牌的核心安全边界，任何接口都不该绕过。
 *
 * 抽成独立函数是为了让「影视详情」在改用与列表页统一的可见性口径时，
 * **仍然保留这条边界**（原来的 hasPermission 里它和第 4 步的权限表匹配是耦合的，
 * 而权限表匹配用的单向下沉正是「列表能看、详情 403」的成因）。
 *
 * 未设置 allow_path ⇒ 返回 true（不限制），与 hasPermission 原语义一致。
 */
function isWithinAllowPath(user, resPath) {
  const allowPathRaw = user && (user.allow_path ?? user.allowPath ?? user.token_allow_path);
  const allowPath = parseAnyOrArray(allowPathRaw);
  if (allowPath === 'ANY') return true;
  if (!Array.isArray(allowPath)) return true;

  const normalizedPath = typeof resPath === 'string' && resPath.trim() ? normalizePathItem(resPath.trim()) : '';
  if (!normalizedPath) return false;

  for (const p of allowPath) {
    const rulePath = typeof p === 'string' && p.trim() ? normalizePathItem(p.trim()) : '';
    if (!rulePath) continue;
    if (normalizedPath === rulePath || normalizedPath.startsWith(rulePath.endsWith(path.sep) ? rulePath : rulePath + path.sep)) {
      return true;
    }
  }
  return false;
}

async function hasPermission(knex, user, action, resPath, resType = tableUserPermission.RES_TYPES.FILE) {
  if (!knex) return false;
  if (!user) return false;
  const normalizedPath = typeof resPath === 'string' && resPath.trim() ? normalizePathItem(resPath.trim()) : '';
  if (!normalizedPath) return false;

  // ① scoped token 的 allow_path 边界（单向下沉，先收范围）
  if (!isWithinAllowPath(user, normalizedPath)) return false;

  const userType = typeof user.type === 'string' ? user.type.toLowerCase() : '';
  if (userType === tableUser.TYPE_SUPER_ADMIN || userType === tableUser.TYPE_ADMIN) return true;

  const uidRaw = user.id ?? user.userId ?? user.uid ?? user.user_id;
  const uid = Number(uidRaw);
  if (!Number.isFinite(uid) || uid <= 0) return false;

  const normalizedResType = typeof resType === 'string' && resType.trim() ? resType.trim() : tableUserPermission.RES_TYPES.FILE;

  const actions = Array.isArray(action) ? action.map(a => String(a || '').trim()).filter(Boolean) : [String(action || '').trim()].filter(Boolean);
  if (actions.length === 0) return false;

  const lowerActions = actions.map(a => a.toLowerCase());
  const isReadOnlyActions = lowerActions.every(a => a === 'view' || a === 'download');
  if (isReadOnlyActions) {
    const isUserShare = await userShareFolderUtil.isUserSharePath(normalizedPath);
    if (isUserShare) {
      if (lowerActions.includes('view')) return true;
      if (lowerActions.includes('download')) {
        const allowed = await userShareFolderUtil.isUserShareDownloadAllowed(normalizedPath);
        if (allowed) return true;
        return false;
      }
      return false;
    }
  }

  const query = knex('user_permission').where({
    uid,
    res_type: normalizedResType,
  });

  if (actions.length > 1) {
    query.whereIn('action', actions);
  } else {
    query.where({ action: actions[0] });
  }

  const rows = await query.select('res_path');

  for (const row of rows) {
    const rowPath = row && typeof row.res_path === 'string' && row.res_path.trim() ? normalizePathItem(row.res_path.trim()) : '';
    if (!rowPath) continue;

    if (normalizedPath === rowPath || normalizedPath.startsWith(rowPath.endsWith(path.sep) ? rowPath : rowPath + path.sep)) {
      return true;
    }
  }
  return false;
}

module.exports = {
  hasPermission,
  isWithinAllowPath,
  parseAnyOrArray,
  matchApi,
};
