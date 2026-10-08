const tableSyncTask = require('../../../db/table/tableSyncTask');
const tableSyncRecord = require('../../../db/table/tableSyncRecord');
const syncUtil = require('./syncUtil');

function safeJsonParse(text) {
  if (!text) return null;
  try {
    return JSON.parse(text);
  } catch (_) {
    return null;
  }
}

function normalizeString(v) {
  if (v === undefined || v === null) return '';
  return String(v).trim();
}

class SyncService {
  constructor(knexMain) {
    this.knexMain = knexMain;
    this.tableName = 'sync_task';
    this.recordTableName = 'sync_record';
  }

  _mapRow(row) {
    if (!row) return row;
    const filter = safeJsonParse(row.filter_config);
    const syncConfig = safeJsonParse(row.sync_config);
    let progress = null;
    const rawProgress = safeJsonParse(row.progress);
    if (rawProgress && typeof rawProgress === 'object') progress = rawProgress;
    return {
      ...row,
      filter_config: syncUtil.normalizeFilterConfig(filter),
      sync_config: syncUtil.normalizeSyncConfig(syncConfig),
      progress,
    };
  }

  async list({ uid, page, pageSize, status, mode, keyword, sortBy, sortOrder } = {}) {
    const uidNum = Number(uid) || 0;
    const pageNum = Number(page || 1) || 1;
    const hasPageSize = pageSize !== undefined && pageSize !== null;
    const limit = hasPageSize ? Number(pageSize || 20) || 20 : null;
    const offset = limit === null ? 0 : (pageNum - 1) * limit;

    const sortCol = ['id', 'create_time', 'update_time', 'last_sync_time', 'name', 'status'].includes(String(sortBy || 'id')) ? String(sortBy || 'id') : 'id';
    const sortDir = String(sortOrder || 'desc').toLowerCase() === 'asc' ? 'asc' : 'desc';

    let q = this.knexMain(this.tableName).select('*').where({ uid: uidNum });
    let countQ = this.knexMain(this.tableName).count({ c: '*' }).where({ uid: uidNum });

    if (status !== undefined && status !== null && String(status).trim()) {
      q = q.where({ status: String(status).trim() });
      countQ = countQ.where({ status: String(status).trim() });
    }
    if (mode !== undefined && mode !== null && String(mode).trim()) {
      q = q.where({ mode: String(mode).trim() });
      countQ = countQ.where({ mode: String(mode).trim() });
    }

    const kw = normalizeString(keyword);
    if (kw) {
      const like = `%${kw}%`;
      q = q.andWhere(builder => {
        builder.orWhere('name', 'like', like).orWhere('local_dir', 'like', like).orWhere('remote_dir', 'like', like);
      });
      countQ = countQ.andWhere(builder => {
        builder.orWhere('name', 'like', like).orWhere('local_dir', 'like', like).orWhere('remote_dir', 'like', like);
      });
    }

    const countRows = await countQ;
    const total = Number((countRows && countRows[0] && (countRows[0].c ?? countRows[0]['count(*)'])) || 0) || 0;

    const ordered = q.orderBy(sortCol, sortDir);
    const rows = limit === null ? await ordered : await ordered.limit(limit).offset(offset);

    return {
      page: limit === null ? 1 : pageNum,
      pageSize: limit === null ? total : limit,
      total,
      items: rows.map(r => this._mapRow(r)),
    };
  }

  async get({ id, uid }) {
    const idNum = Number(id);
    if (!Number.isFinite(idNum) || idNum <= 0) throw syncUtil.buildHttpError('validation.ID_INVALID', 400);
    const row = await this.knexMain(this.tableName).where({ id: idNum, uid: Number(uid) || 0 }).first();
    if (!row) throw syncUtil.buildHttpError('common.NOT_FOUND', 404);
    return this._mapRow(row);
  }

  async upsert({ id, uid, name, mode, localDir, remoteDir, filterConfig, syncConfig, deviceId, deviceName } = {}) {
    const uidNum = Number(uid) || 0;
    if (!uidNum) throw syncUtil.buildHttpError('common.UNAUTHORIZED', 401);

    const idNum = id === undefined || id === null ? null : Number(id);
    const hasId = Number.isFinite(idNum) && idNum > 0;

    const taskName = normalizeString(name);
    const m = normalizeString(mode) || tableSyncTask.MODE_BIDIRECTIONAL;
    const remote = normalizeString(remoteDir);
    const local = normalizeString(localDir);

    if (!taskName || taskName.length > 32) throw syncUtil.buildHttpError('sync.TASK_NAME_INVALID', 400);
    if (!tableSyncTask.MODES.includes(m)) throw syncUtil.buildHttpError('sync.MODE_INVALID', 400);
    if (!remote) throw syncUtil.buildHttpError('sync.REMOTE_DIR_REQUIRED', 400);
    if (!local) throw syncUtil.buildHttpError('sync.LOCAL_DIR_REQUIRED', 400);

    const remoteAbs = await syncUtil.resolveRemoteDir(remote, { requireExists: hasId ? false : true });

    const filterText = JSON.stringify(syncUtil.normalizeFilterConfig(filterConfig));
    const syncText = JSON.stringify(syncUtil.normalizeSyncConfig(syncConfig));
    const devId = normalizeString(deviceId);
    const devName = normalizeString(deviceName);

    if (hasId) {
      const existed = await this.knexMain(this.tableName).where({ id: idNum, uid: uidNum }).first();
      if (!existed) throw syncUtil.buildHttpError('common.NOT_FOUND', 404);

      await this.knexMain(this.tableName)
        .where({ id: idNum })
        .update({
          name: taskName,
          mode: m,
          local_dir: local,
          remote_dir: remoteAbs,
          filter_config: filterText,
          sync_config: syncText,
          device_id: devId || existed.device_id,
          device_name: devName || existed.device_name,
          update_time: new Date(),
        });
      return { id: idNum };
    }

    const [newId] = await this.knexMain(this.tableName).insert({
      uid: uidNum,
      name: taskName,
      device_id: devId,
      device_name: devName,
      mode: m,
      local_dir: local,
      remote_dir: remoteAbs,
      filter_config: filterText,
      sync_config: syncText,
      status: tableSyncTask.STATUS_IDLE,
      progress: '',
      last_sync_time: null,
      last_error: null,
      create_time: new Date(),
      update_time: new Date(),
    });
    return { id: newId };
  }

  async remove({ id, uid }) {
    const idNum = Number(id);
    if (!Number.isFinite(idNum) || idNum <= 0) throw syncUtil.buildHttpError('validation.ID_INVALID', 400);
    const existed = await this.knexMain(this.tableName).where({ id: idNum, uid: Number(uid) || 0 }).first();
    if (!existed) throw syncUtil.buildHttpError('common.NOT_FOUND', 404);
    await this.knexMain(this.tableName).where({ id: idNum }).del();
    await this.knexMain(this.recordTableName).where({ task_id: idNum }).del();
    return { ok: true };
  }

  async updateStatus({ id, uid, status, progress, lastError, lastSyncTime }) {
    const idNum = Number(id);
    if (!Number.isFinite(idNum) || idNum <= 0) throw syncUtil.buildHttpError('validation.ID_INVALID', 400);

    // uid 必填。漏传会让 WHERE 退化成只按 id 命中，等于任何登录用户都能
    // 改写别人的同步任务状态（该漏洞此前一直被 addRecord 先抛 404 挡着）。
    const uidNum = Number(uid);
    if (!Number.isFinite(uidNum) || uidNum <= 0) throw syncUtil.buildHttpError('common.UNAUTHORIZED', 401);

    const where = { id: idNum, uid: uidNum };

    const data = { update_time: new Date() };
    if (status !== undefined && status !== null && String(status).trim()) {
      const st = String(status).trim();
      if (!tableSyncTask.STATUSES.includes(st)) throw syncUtil.buildHttpError('sync.STATUS_INVALID', 400);
      data.status = st;
    }
    if (progress !== undefined) {
      data.progress = progress && typeof progress === 'object' ? JSON.stringify(progress) : normalizeString(progress);
    }
    if (lastError !== undefined) data.last_error = lastError === null ? null : normalizeString(lastError);
    if (lastSyncTime !== undefined && lastSyncTime !== null) data.last_sync_time = new Date(Number(lastSyncTime) || Date.now());

    const affected = await this.knexMain(this.tableName).where(where).update(data);
    if (!affected) throw syncUtil.buildHttpError('common.NOT_FOUND', 404);
    return { ok: true };
  }

  async addRecord({ taskId, uid, startTime, endTime, status, uploadCount, downloadCount, deleteCount, skipCount, failCount, bytesTransferred, errorList, durationMs }) {
    const taskIdNum = Number(taskId);
    if (!Number.isFinite(taskIdNum) || taskIdNum <= 0) throw syncUtil.buildHttpError('validation.ID_INVALID', 400);

    const taskRow = await this.knexMain(this.tableName).where({ id: taskIdNum, uid: Number(uid) || 0 }).first();
    if (!taskRow) throw syncUtil.buildHttpError('common.NOT_FOUND', 404);

    const start = Number(startTime) || Date.now();
    const end = Number(endTime) || Date.now();
    const st = String(status || '').trim();
    const recordStatus = [tableSyncRecord.STATUS_SUCCESS, tableSyncRecord.STATUS_FAILED, tableSyncRecord.STATUS_STOPPED].includes(st)
      ? st
      : tableSyncRecord.STATUS_SUCCESS;

    const errors = Array.isArray(errorList) ? errorList.slice(0, 200).map(e => String(e || '')) : [];
    const safeInt = v => {
      const n = Number(v);
      return Number.isFinite(n) && n > 0 ? Math.floor(n) : 0;
    };

    const [recordId] = await this.knexMain(this.recordTableName).insert({
      task_id: taskIdNum,
      start_time: new Date(start),
      end_time: new Date(end),
      status: recordStatus,
      upload_count: safeInt(uploadCount),
      download_count: safeInt(downloadCount),
      delete_count: safeInt(deleteCount),
      skip_count: safeInt(skipCount),
      fail_count: safeInt(failCount),
      bytes_transferred: safeInt(bytesTransferred),
      error_list: JSON.stringify(errors),
      duration_ms: Math.max(0, Math.floor(end - start)),
    });

    await this.knexMain(this.tableName).where({ id: taskIdNum, uid: Number(uid) || 0 }).update({ last_sync_time: new Date(start), update_time: new Date() });

    await this._pruneRecords(taskIdNum);
    return { id: recordId };
  }

  async _pruneRecords(taskIdNum) {
    const max = tableSyncRecord.MAX_ROWS_PER_TASK;
    const rows = await this.knexMain(this.recordTableName).where({ task_id: taskIdNum }).orderBy('id', 'desc').limit(1).offset(max - 1);
    if (!rows || rows.length === 0) return;
    const thresholdId = rows[0].id;
    await this.knexMain(this.recordTableName).where({ task_id: taskIdNum }).andWhere('id', '<=', thresholdId).del();
  }

  _mapRecordRow(row) {
    if (!row) return row;
    const errors = safeJsonParse(row.error_list);
    return { ...row, error_list: Array.isArray(errors) ? errors : [] };
  }

  async listRecords({ taskId, uid, page, pageSize } = {}) {
    const taskIdNum = Number(taskId);
    if (!Number.isFinite(taskIdNum) || taskIdNum <= 0) throw syncUtil.buildHttpError('validation.ID_INVALID', 400);
    const taskRow = await this.knexMain(this.tableName).where({ id: taskIdNum, uid: Number(uid) || 0 }).first();
    if (!taskRow) throw syncUtil.buildHttpError('common.NOT_FOUND', 404);

    const pageNum = Number(page || 1) || 1;
    const limit = Math.min(100, Math.max(1, Number(pageSize || 20) || 20));
    const offset = (pageNum - 1) * limit;

    const countRows = await this.knexMain(this.recordTableName).where({ task_id: taskIdNum }).count({ c: '*' });
    const total = Number((countRows && countRows[0] && (countRows[0].c ?? countRows[0]['count(*)'])) || 0) || 0;

    const rows = await this.knexMain(this.recordTableName).where({ task_id: taskIdNum }).orderBy('id', 'desc').limit(limit).offset(offset);

    return {
      page: pageNum,
      pageSize: limit,
      total,
      max_kept_per_task: tableSyncRecord.MAX_ROWS_PER_TASK,
      items: rows.map(r => this._mapRecordRow(r)),
    };
  }

  /** 统计某用户的任务概况，供客户端首屏展示 */
  async summary({ uid } = {}) {
    const uidNum = Number(uid) || 0;
    const rows = await this.knexMain(this.tableName).select('status').where({ uid: uidNum });
    const result = { total: rows.length, idle: 0, running: 0, paused: 0, error: 0 };
    for (const r of rows) {
      const st = String(r.status || '');
      if (Object.prototype.hasOwnProperty.call(result, st)) result[st] += 1;
    }
    return result;
  }
}

module.exports = { SyncService };
