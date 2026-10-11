const ResponseUtil = require('../../../apiUtils/responseUtil');
const { getUserLanguage } = require('../../../../utils/i18nUtil');
const AppAiService = require('./appAiService');
const photoTimeLineService = require('../timeline/photoTimeLineService');
const userUtil = require('../../../../utils/userUtil');

class AppAiController {
  async overview(req, res) {
    try {
      const locale = getUserLanguage(req);
      let validPaths;
      // 按归属隔离：所有用户（含管理员）都只能看到自己源目录下的照片。
      // 不要再加 isAdmin 例外 —— 隐私设计要求超管也只看自己的。
      if (req.user) {
        const validPathsRaw = await photoTimeLineService.getValidPaths(req.user);
        validPaths = (validPathsRaw || []).map(p => (p ? String(p) : '')).filter(Boolean);
      }
      const service = new AppAiService(req.dbPhoto);
      const result = await service.getOverview({
        locale,
        ...(req.body || {}),
        ...(validPaths !== undefined ? { validPaths } : {}),
      });
      return ResponseUtil.success(req, res, result, 'common.SUCCESS', 200);
    } catch (_) {
      return ResponseUtil.error(req, res, 'common.ERROR', 500);
    }
  }
}

module.exports = new AppAiController();
