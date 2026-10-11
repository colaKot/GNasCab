const os = require('os');
const tableConfig = require('../../../../db/table/tableConfig');
const config = require('../../../../config/config');
const ResponseUtil = require('../../../apiUtils/responseUtil');
const networkProxyUtil = require('../../../../utils/networkProxyUtil');

function _parseBoolTo01(v) {
  return v === 1 || v === '1' || v === true ? 1 : 0;
}

class ApiSettingController {
  async get(req, res) {
    try {
      const rawHttp = await tableConfig.getConfigByKey(tableConfig.KEY_API_PORT_HTTP, 0);
      const rawHttps = await tableConfig.getConfigByKey(tableConfig.KEY_API_PORT_HTTPS, 0);
      const rawCount = await tableConfig.getConfigByKey(tableConfig.KEY_EXPRESS_API_COUNT, 0);
      const rawWelcomeText = await tableConfig.getConfigByKey(tableConfig.KEY_LOGIN_WELCOME_TEXT, 0);
      const rawCustomHostname = await tableConfig.getConfigByKey(tableConfig.KEY_CUSTOM_HOSTNAME, 0);
      const rawProxyEnable = await tableConfig.getConfigByKey(tableConfig.KEY_GLOBAL_PROXY_ENABLE, 0);
      const rawProxyUrl = await tableConfig.getConfigByKey(tableConfig.KEY_GLOBAL_PROXY_URL, 0);
      const rawJavFallback = await tableConfig.getConfigByKey(tableConfig.KEY_JAV_FALLBACK_ENABLE, 0);

      const httpPort = this._toNullablePort(rawHttp) ?? this._toNullablePort(config?.app?.port) ?? 9000;
      const httpsPort = this._toNullablePort(rawHttps) ?? this._toNullablePort(config?.app?.httpsPort) ?? 9443;

      const cpuCores = Math.max(1, (os.cpus() || []).length);
      const desiredCount = this._toNullableInt(rawCount) ?? 2;
      const expressApiCount = Math.max(2, Math.min(cpuCores, desiredCount));
      const welcomeText = typeof rawWelcomeText === 'string' && rawWelcomeText.trim().length > 0 ? rawWelcomeText.trim() : null;
      const customHostname =
        typeof rawCustomHostname === 'string' && rawCustomHostname.trim().length > 0
          ? rawCustomHostname.trim()
          : null;
      const globalProxyEnable = _parseBoolTo01(rawProxyEnable);
      const globalProxyUrl = typeof rawProxyUrl === 'string' ? rawProxyUrl.trim() : '';
      const javFallbackEnable = _parseBoolTo01(rawJavFallback);

      return ResponseUtil.success(
        req,
        res,
        {
          httpPort,
          httpsPort,
          expressApiCount,
          cpuCores,
          welcomeText,
          customHostname,
          globalProxyEnable,
          globalProxyUrl,
          javFallbackEnable,
        },
        'apiSetting.FETCH_SUCCESS'
      );
    } catch (e) {
      return ResponseUtil.error(req, res, 'apiSetting.FETCH_FAILED', 500, e);
    }
  }

  async loginConfig(req, res) {
    try {
      const rawWelcomeText = await tableConfig.getConfigByKey(tableConfig.KEY_LOGIN_WELCOME_TEXT, 0);
      const welcomeText = typeof rawWelcomeText === 'string' && rawWelcomeText.trim().length > 0 ? rawWelcomeText.trim() : null;
      return ResponseUtil.success(req, res, { welcomeText }, 'apiSetting.FETCH_SUCCESS');
    } catch (e) {
      return ResponseUtil.error(req, res, 'apiSetting.FETCH_FAILED', 500, e);
    }
  }

  /**
   * 保存全局网络代理。开启时必须给出一个合法的 http/https 代理地址。
   */
  async saveProxy(req, res) {
    try {
      const body = req.body || {};
      const enable = _parseBoolTo01(body.enable ?? body.globalProxyEnable ?? body.proxyEnable);
      const rawUrl = typeof (body.proxyUrl ?? body.globalProxyUrl) === 'string'
        ? String(body.proxyUrl ?? body.globalProxyUrl).trim()
        : '';

      // 关闭时也保留一份合法地址，方便用户之后直接再开启；非法地址一律存空串。
      const proxyUrl = networkProxyUtil.parseHttpProxyUrlOrEmpty(rawUrl);
      if (enable === 1 && !proxyUrl) {
        return ResponseUtil.error(req, res, 'video.TMDB_PROXY_INVALID', 400);
      }

      const okEnable = await tableConfig.setConfigByKey(tableConfig.KEY_GLOBAL_PROXY_ENABLE, String(enable));
      const okUrl = await tableConfig.setConfigByKey(tableConfig.KEY_GLOBAL_PROXY_URL, proxyUrl);
      if (!okEnable || !okUrl) {
        return ResponseUtil.error(req, res, 'apiSetting.SAVE_FAILED', 500);
      }
      return ResponseUtil.success(req, res, { globalProxyEnable: enable, globalProxyUrl: proxyUrl }, 'apiSetting.SAVE_SUCCESS');
    } catch (e) {
      return ResponseUtil.error(req, res, 'apiSetting.SAVE_FAILED', 500, e);
    }
  }

  /**
   * 保存「日本片识别兜底」开关。默认关闭（保守设计）。
   */
  async saveJavFallback(req, res) {
    try {
      const body = req.body || {};
      const enable = _parseBoolTo01(body.enable ?? body.javFallbackEnable);
      const ok = await tableConfig.setConfigByKey(tableConfig.KEY_JAV_FALLBACK_ENABLE, String(enable));
      if (!ok) {
        return ResponseUtil.error(req, res, 'apiSetting.SAVE_FAILED', 500);
      }
      return ResponseUtil.success(req, res, { javFallbackEnable: enable }, 'apiSetting.SAVE_SUCCESS');
    } catch (e) {
      return ResponseUtil.error(req, res, 'apiSetting.SAVE_FAILED', 500, e);
    }
  }

  async saveWelcome(req, res) {
    try {
      const welcomeText = typeof req.body?.welcomeText === 'string' ? req.body.welcomeText.trim() : '';
      const ok = await tableConfig.setConfigByKey(tableConfig.KEY_LOGIN_WELCOME_TEXT, welcomeText);
      if (!ok) {
        return ResponseUtil.error(req, res, 'apiSetting.SAVE_FAILED', 500);
      }
      return ResponseUtil.success(req, res, null, 'apiSetting.SAVE_SUCCESS');
    } catch (e) {
      return ResponseUtil.error(req, res, 'apiSetting.SAVE_FAILED', 500, e);
    }
  }

  async save(req, res) {
    try {
      const httpPort = this._toNullablePort(req.body?.httpPort);
      const httpsPort = this._toNullablePort(req.body?.httpsPort);
      const expressApiCount = this._toNullableInt(req.body?.expressApiCount);

      if (httpPort === null || httpsPort === null || expressApiCount === null) {
        return ResponseUtil.error(req, res, 'apiSetting.INVALID_PARAMS', 400);
      }

      const forbidden = new Set((config && config.forbiddenPorts) || []);
      if (forbidden.has(httpPort) || forbidden.has(httpsPort)) {
        return ResponseUtil.error(req, res, 'apiSetting.PORT_FORBIDDEN', 400);
      }

      const cpuCores = Math.max(1, (os.cpus() || []).length);
      if (expressApiCount < 2) {
        return ResponseUtil.error(req, res, 'apiSetting.API_COUNT_TOO_LOW', 400);
      }
      if (expressApiCount > cpuCores) {
        return ResponseUtil.error(req, res, 'apiSetting.API_COUNT_TOO_HIGH', 400, null, [cpuCores]);
      }

      const okHttp = await tableConfig.setConfigByKey(tableConfig.KEY_API_PORT_HTTP, String(httpPort));
      const okHttps = await tableConfig.setConfigByKey(tableConfig.KEY_API_PORT_HTTPS, String(httpsPort));
      const okCount = await tableConfig.setConfigByKey(tableConfig.KEY_EXPRESS_API_COUNT, String(expressApiCount));

      if (!okHttp || !okHttps || !okCount) {
        return ResponseUtil.error(req, res, 'apiSetting.SAVE_FAILED', 500);
      }

      return ResponseUtil.success(req, res, null, 'apiSetting.SAVE_SUCCESS');
    } catch (e) {
      return ResponseUtil.error(req, res, 'apiSetting.SAVE_FAILED', 500, e);
    }
  }

  async restartService(req, res) {
    try {
      if (typeof process.send === 'function') {
        process.send({
          type: 'requestAppRestart',
          data: {
            userId: req.user?.id ?? null,
            ts: Date.now(),
          },
        });
      }
      return ResponseUtil.success(req, res, { restarting: true }, 'common.SUCCESS');
    } catch (e) {
      return ResponseUtil.error(req, res, 'common.FAILED', 500, e);
    }
  }

  _toNullablePort(v) {
    const n = this._toNullableInt(v);
    if (n === null) return null;
    if (n <= 0 || n > 65535) return null;
    return n;
  }

  _toNullableInt(v) {
    if (typeof v === 'number' && Number.isFinite(v)) {
      return Math.trunc(v);
    }
    if (typeof v === 'string') {
      const s = v.trim();
      if (s.length === 0) return null;
      const n = parseInt(s, 10);
      if (!Number.isFinite(n)) return null;
      return n;
    }
    return null;
  }
}

module.exports = new ApiSettingController();
