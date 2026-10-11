const ResponseUtil = require('../../../apiUtils/responseUtil');
const VideoListService = require('./videoListService');
const Logger = require('../../../../utils/logger');

class VideoListController {
  async list(req, res) {
    const body = (req && req.body) || {};
    try {
      const user = req.user;
      const uid = user && user.id ? Number(user.id) : 0;
      if (!uid) return ResponseUtil.unauthorized(req, res);

      const service = new VideoListService(req.dbVideo);
      const data = await service.listPaged(body, user);

      // 诊断日志：图片库/混合库「只显示数量、列表空白」这类问题需要看到真实入参。
      // 只记关键字段，避免刷屏。
      try {
        const items = Array.isArray(data && data.items) ? data.items : [];
        Logger.info('[video/list]', {
          library_id: body.library_id ?? body.libraryId ?? null,
          media_type: body.media_type ?? body.mediaType ?? null,
          page: body.page,
          page_size: body.page_size ?? body.pageSize,
          sort_by: body.sort_by ?? body.sortBy ?? null,
          listType: body.listType ?? body.list_type ?? null,
          sourceList: Array.isArray(body.sourceList) ? body.sourceList.length : (body.sourceList ?? null),
          returned: items.length,
          total: (data && data.pagination && data.pagination.total) ?? null,
          firstId: items[0] ? items[0].id : null,
        });
      } catch (_) {}

      return ResponseUtil.success(req, res, data, 'video.VIDEO_LIST_FETCH_SUCCESS', 200);
    } catch (e) {
      // ⚠️ 原来这里是 console.log(e)：错误只进 stdout，不会落盘到 error.log，
      // 排查时日志里什么都看不到。改为写 logger。
      Logger.error('❌ [video/list] failed', {
        message: e && e.message,
        stack: e && e.stack,
        body,
      });
      const msgKey = e && e.message ? e.message : 'video.VIDEO_LIST_FETCH_FAILED';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 500;
      return ResponseUtil.error(req, res, msgKey === 'common.ERROR' ? 'video.VIDEO_LIST_FETCH_FAILED' : msgKey, statusCode);
    }
  }

  async count(req, res) {
    try {
      const user = req.user;
      const uid = user && user.id ? Number(user.id) : 0;
      if (!uid) return ResponseUtil.unauthorized(req, res);

      const body = req.body || {};
      const service = new VideoListService(req.dbVideo);
      const data = await service.getVisibleIndexCounts(body, user);
      return ResponseUtil.success(req, res, data, 'common.SUCCESS', 200);
    } catch (e) {
      console.log(e);
      const msgKey = e && e.message ? e.message : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 500;
      return ResponseUtil.error(req, res, msgKey === 'common.ERROR' ? 'common.ERROR' : msgKey, statusCode);
    }
  }

  async historyList(req, res) {
    try {
      const user = req.user;
      const uid = user && user.id ? Number(user.id) : 0;
      if (!uid) return ResponseUtil.unauthorized(req, res);

      const service = new VideoListService(req.dbVideo);
      const data = await service.listHistory(user);
      return ResponseUtil.success(req, res, data, 'common.SUCCESS', 200);
    } catch (e) {
      console.log(e);
      const msgKey = e && e.message ? e.message : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 500;
      return ResponseUtil.error(req, res, msgKey === 'common.ERROR' ? 'common.ERROR' : msgKey, statusCode);
    }
  }

  async clearHistory(req, res) {
    try {
      const user = req.user;
      const uid = user && user.id ? Number(user.id) : 0;
      if (!uid) return ResponseUtil.unauthorized(req, res);

      const service = new VideoListService(req.dbVideo);
      const data = await service.clearHistory(user);
      return ResponseUtil.success(req, res, data, 'common.SUCCESS', 200);
    } catch (e) {
      console.log(e);
      const msgKey = e && e.message ? e.message : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 500;
      return ResponseUtil.error(req, res, msgKey === 'common.ERROR' ? 'common.ERROR' : msgKey, statusCode);
    }
  }

  /** 图片库 / 混合库的文件夹层级（直接子文件夹 + 封面 + 数量）。
   *
   *  ⚠️ 必须写成**箭头函数属性**：路由是裸引用注册的
   *     （`videoRouter.js` 里 `videoListController.imageFolders`），
   *     类体严格模式下普通方法的 `this === undefined`，
   *     只要方法体里用了一次 `this` 就会 500。 */
  imageFolders = async (req, res) => {
    const body = (req && req.body) || {};
    try {
      const user = req.user;
      const uid = user && user.id ? Number(user.id) : 0;
      if (!uid) return ResponseUtil.unauthorized(req, res);

      const service = new VideoListService(req.dbVideo);
      const data = await service.listImageFolders(body, user);

      // 诊断日志：文件夹层级「进不去 / 数量不对」时需要看真实入参
      try {
        Logger.info('[video/image/folders]', {
          library_id: body.library_id ?? body.libraryId ?? null,
          folderPath: body.folderPath ?? body.folder_path ?? '',
          folderCount: Array.isArray(data && data.folders) ? data.folders.length : 0,
          selfCount: (data && data.selfCount) ?? 0,
        });
      } catch (_) {}

      return ResponseUtil.success(req, res, data, 'common.SUCCESS', 200);
    } catch (e) {
      Logger.error('❌ [video/image/folders] failed', {
        message: e && e.message,
        stack: e && e.stack,
        body,
      });
      const msgKey = e && e.message ? e.message : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 500;
      return ResponseUtil.error(req, res, msgKey, statusCode);
    }
  };
}

module.exports = new VideoListController();
