const ResponseUtil = require('../../../apiUtils/responseUtil');
const VideoDetailService = require('./detailService');
const fs = require('fs');
const path = require('path');
const { hasPermission } = require('../../../../utils/permissionUtil');

class VideoDetailController {
  /**
   * 路径级鉴权：按 video_index 记录的源目录判断当前用户是否有权访问。
   * 详情/剧集/播放信息/光盘内容都会返回绝对文件路径与 NFO 元数据，
   * index_id 是自增整数可枚举，不校验的话知道 id 即可越权读取无权目录的媒体信息。
   */
  async _ensureIndexAccess(req, indexId) {
    const id = Number(indexId);
    if (!Number.isFinite(id) || id <= 0) {
      return { ok: false, statusCode: 400, message: 'common.PARAM_ERROR' };
    }
    const row = await req.dbVideo('video_index').where({ id }).first('path').catch(() => null);
    const dirPath = row && row.path ? String(row.path) : '';
    if (!dirPath) {
      return { ok: false, statusCode: 404, message: 'common.PARAM_ERROR' };
    }
    const ok = await hasPermission(req.dbMain, req.user, ['download', 'view'], dirPath, 'file').catch(() => false);
    if (!ok) {
      return { ok: false, statusCode: 403, message: 'auth.PERMISSION_DENIED' };
    }
    return { ok: true };
  }

  async getDetail(req, res) {
    try {
      const uid = req.user && req.user.id ? Number(req.user.id) : 0;
      if (!uid) return ResponseUtil.unauthorized(req, res);

      const q = req.query || {};
      const indexId = Number(q.index_id ?? q.indexId ?? 0) || 0;
      const guard = await this._ensureIndexAccess(req, indexId);
      if (!guard.ok) return ResponseUtil.error(req, res, guard.message, guard.statusCode);

      const service = new VideoDetailService(req.dbVideo);
      const data = await service.getDetail({ uid, indexId });
      return ResponseUtil.success(req, res, data, 'common.SUCCESS', 200);
    } catch (e) {
      const msgKey = e && e.message ? e.message : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 500;
      return ResponseUtil.error(req, res, msgKey, statusCode);
    }
  }

  async getEpisodes(req, res) {
    try {
      const uid = req.user && req.user.id ? Number(req.user.id) : 0;
      if (!uid) return ResponseUtil.unauthorized(req, res);

      const q = req.query || {};
      const indexId = Number(q.index_id ?? q.indexId ?? 0) || 0;
      const page = Number(q.page ?? 1) || 1;
      const pageSize = Number(q.page_size ?? q.pageSize ?? 50) || 50;
      const sortOrder = String(q.sort_order ?? q.sortOrder ?? 'asc');

      const guard = await this._ensureIndexAccess(req, indexId);
      if (!guard.ok) return ResponseUtil.error(req, res, guard.message, guard.statusCode);

      const service = new VideoDetailService(req.dbVideo);
      const data = await service.getEpisodesPaged({
        indexId,
        page,
        pageSize,
        sortOrder,
      });
      return ResponseUtil.success(req, res, data, 'common.SUCCESS', 200);
    } catch (e) {
      const msgKey = e && e.message ? e.message : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 500;
      return ResponseUtil.error(req, res, msgKey, statusCode);
    }
  }

  async getTvPlayInfo(req, res) {
    try {
      const uid = req.user && req.user.id ? Number(req.user.id) : 0;
      if (!uid) return ResponseUtil.unauthorized(req, res);

      const q = req.query || {};
      const indexId = Number(q.index_id ?? q.indexId ?? 0) || 0;

      const guard = await this._ensureIndexAccess(req, indexId);
      if (!guard.ok) return ResponseUtil.error(req, res, guard.message, guard.statusCode);

      const service = new VideoDetailService(req.dbVideo);
      const data = await service.getTvPlayInfo({ uid, indexId });
      return ResponseUtil.success(req, res, data, 'common.SUCCESS', 200);
    } catch (e) {
      const msgKey = e && e.message ? e.message : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 500;
      return ResponseUtil.error(req, res, msgKey, statusCode);
    }
  }

  async getDiscContents(req, res) {
    try {
      const uid = req.user && req.user.id ? Number(req.user.id) : 0;
      if (!uid) return ResponseUtil.unauthorized(req, res);

      const q = req.query || {};
      const indexId = Number(q.index_id ?? q.indexId ?? 0) || 0;

      const guard = await this._ensureIndexAccess(req, indexId);
      if (!guard.ok) return ResponseUtil.error(req, res, guard.message, guard.statusCode);

      const service = new VideoDetailService(req.dbVideo);
      const data = await service.getDiscContents({ indexId });
      return ResponseUtil.success(req, res, data, 'common.SUCCESS', 200);
    } catch (e) {
      const msgKey = e && e.message ? e.message : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 500;
      return ResponseUtil.error(req, res, msgKey, statusCode);
    }
  }

  async getDiscContentThumb(req, res) {
    try {
      const uid = req.user && req.user.id ? Number(req.user.id) : 0;
      if (!uid) return res.status(401).end();

      const q = req.query || {};
      const indexId = Number(q.index_id ?? q.indexId ?? 0) || 0;
      const internalPath = String(q.internal_path ?? q.internalPath ?? '').trim();
      const size = Math.max(1, Number(q.size ?? 320) || 320);

      const guard = await this._ensureIndexAccess(req, indexId);
      if (!guard.ok) return res.status(guard.statusCode || 403).end();

      const service = new VideoDetailService(req.dbVideo);
      const tinyPath = await service.getDiscContentThumbPath({
        indexId,
        internalPath,
        size,
      });
      if (!tinyPath) return res.status(404).end();

      res.set('Content-Type', 'image/webp');
      return res.sendFile(tinyPath);
    } catch (_) {
      return res.status(404).end();
    }
  }

  async setOpenSkip(req, res) {
    try {
      const uid = req.user && req.user.id ? Number(req.user.id) : 0;
      if (!uid) return ResponseUtil.unauthorized(req, res);

      const body = req.body || {};
      const indexId = Number(body.index_id ?? body.indexId ?? 0) || 0;
      const openSkipStartSec = body.open_skip_start_sec ?? body.openSkipStartSec ?? 0;
      const openSkipEndSec = body.open_skip_end_sec ?? body.openSkipEndSec ?? 0;

      const service = new VideoDetailService(req.dbVideo);
      const data = await service.setOpenSkip({
        indexId,
        openSkipStartSec,
        openSkipEndSec,
      });
      return ResponseUtil.success(req, res, data, 'common.SUCCESS', 200);
    } catch (e) {
      const msgKey = e && e.message ? e.message : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 500;
      return ResponseUtil.error(req, res, msgKey, statusCode);
    }
  }

  async getPersonImage(req, res) {
    try {
      const uid = req.user && req.user.id ? Number(req.user.id) : 0;
      if (!uid) return res.status(401).end();

      const q = req.query || {};
      const tmdbId = String(q.tmdb_id ?? q.tmdbId ?? '').trim();
      if (!tmdbId) return res.status(400).end();

      const size = 500;
      const thumb = String(q.thumb ?? '').trim();

      const service = new VideoDetailService(req.dbVideo);
      const info = await service.getPersonJpegCacheInfo({
        tmdbId,
        size,
        thumbUrl: thumb,
      });
      if (!info || !info.filePath) return res.status(404).end();

      const filePath = String(info.filePath || '').trim();
      const url = String(info.url || '').trim();
      if (!filePath) return res.status(404).end();

      if (info.exists) {
        res.set('Content-Type', 'image/jpeg');
        return res.sendFile(filePath);
      }

      if (!url) return res.status(404).end();
      try {
        if (typeof process.send === 'function') {
          process.send({ type: 'downloadUrlToFile', data: { url, targetPath: filePath, timeoutMs: 30000, allowProxy: true } });
        }
      } catch (_) {}

      res.set('Content-Type', 'image/jpeg');
      const deadlineAt = Date.now() + 15000;
      while (Date.now() < deadlineAt) {
        if (req.aborted) return;
        try {
          const st = await fs.promises.stat(filePath);
          if (st && st.isFile() && Number(st.size || 0) > 0) {
            return res.sendFile(filePath);
          }
        } catch (_) {}
        await new Promise(resolve => setTimeout(resolve, 1000));
      }
      return res.status(404).end();
    } catch (_) {
      return res.status(404).end();
    }
  }

  async getPosterImage(req, res) {
    try {
      const uid = req.user && req.user.id ? Number(req.user.id) : 0;
      if (!uid) return res.status(401).end();

      const q = req.query || {};
      const tmdbId = String(q.tmdb_id ?? q.tmdbId ?? '').trim();
      const mediaType = String(q.media_type ?? q.mediaType ?? '')
        .trim()
        .toLowerCase();
      if (!tmdbId) return res.status(400).end();
      if (mediaType !== 'movie' && mediaType !== 'tv') return res.status(400).end();

      const size = Math.max(1, Number(q.size ?? 342) || 342);
      const thumb = String(q.thumb ?? '').trim();

      const service = new VideoDetailService(req.dbVideo);
      const info = await service.getPosterJpegCacheInfo({
        tmdbId,
        mediaType,
        size,
        thumbUrl: thumb,
      });
      if (!info || !info.filePath) return res.status(404).end();

      const filePath = String(info.filePath || '').trim();
      const url = String(info.url || '').trim();
      if (!filePath) return res.status(404).end();

      if (info.exists) {
        res.set('Content-Type', 'image/jpeg');
        return res.sendFile(filePath);
      }

      if (!url) return res.status(404).end();
      try {
        await fs.promises.mkdir(path.dirname(filePath), { recursive: true });
      } catch (_) {}

      try {
        if (typeof process.send === 'function') {
          process.send({ type: 'downloadUrlToFile', data: { url, targetPath: filePath, timeoutMs: 30000, allowProxy: true } });
        }
      } catch (_) {}

      res.set('Content-Type', 'image/jpeg');
      const deadlineAt = Date.now() + 15000;
      while (Date.now() < deadlineAt) {
        if (req.aborted) return;
        try {
          const st = await fs.promises.stat(filePath);
          if (st && st.isFile() && Number(st.size || 0) > 0) {
            return res.sendFile(filePath);
          }
        } catch (_) {}
        await new Promise(resolve => setTimeout(resolve, 1000));
      }
      return res.status(404).end();
    } catch (_) {
      return res.status(404).end();
    }
  }
}

module.exports = new VideoDetailController();
