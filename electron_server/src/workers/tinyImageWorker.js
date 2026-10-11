'use strict';

const fs = require('fs');
const path = require('path');
const os = require('os');

const Logger = require('../utils/logger');
const config = require('../config/config');
const dbUtil = require('../db/dbUtil');
const knexUtil = require('../db/knexUtil');
const tableConfig = require('../db/table/tableConfig');
const fileService = require('../api/modules/file/core/fileService');
const { withHardTimeout, pathAccessible } = require('../utils/asyncTimeoutUtil');

const TINY_PATH_CHECK_MS = 8000;
const TINY_IMAGE_GEN_MS = 90 * 1000;
const TINY_VIDEO_GEN_MS = 3 * 60 * 1000;

/* ============================================================================
 * 并发与限速（2026-10-10 重构）
 *
 * 背景：原来图片根本进不了这个队列（`getOneVideo` 只认视频扩展名），于是
 * 网格里每张图都走 `/api/file/tiny` **在 HTTP 线程里同步 sharp 解码** ——
 * 前端一次并发 30 个请求 = 30 个 sharp 同时解码 9504×6336 的原图，
 * CPU 直接打满。这是"一打开图片库 CPU 就 100%"的真正原因。
 *
 * 现在：
 *   * 图片进队列，在**独立 worker 进程**里生成（不占 HTTP 线程）
 *   * 用户正在看的图（wait 队列）用较高并发，尽快出图
 *   * 后台全量补图用**单并发 + 每张之间歇一下**，避免持续满载
 * ==========================================================================*/
const CPU_COUNT = Math.max(1, ((os.cpus && os.cpus()) || []).length || 1);
// 用户请求（wait_gen_tiny）：越快越好，但最多 4 路，别把机器吃满
const FOREGROUND_CONCURRENCY = Math.max(1, Math.min(4, Math.floor(CPU_COUNT / 2) || 1));
// 后台补图：1 路 + 间隔，长期占用控制在单核以内
const BACKGROUND_CONCURRENCY = 1;
const BACKGROUND_THROTTLE_MS = 60;
// 全空闲时的轮询间隔。见 startLoop 末尾：worker **常驻不退出**，
// 这样浏览器发来的 202 请求能立刻被处理，不必等唤醒 + 重新初始化。
const IDLE_POLL_MS = 1500;
// 后台预生成开关的复查间隔（允许运行时热切换，不必重启 worker）
const PREGEN_FLAG_TTL_MS = 30 * 1000;

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

function tinyGenTimeoutMs(filePath) {
  const ext = path.extname(String(filePath || '')).toLowerCase();
  const videoTypes = Array.isArray(config.videoTypeList) ? config.videoTypeList : [];
  return videoTypes.includes(ext) ? TINY_VIDEO_GEN_MS : TINY_IMAGE_GEN_MS;
}

async function generateTinyWithTimeout(fullPath) {
  const ms = tinyGenTimeoutMs(fullPath);
  return withHardTimeout(
    fileService.getTinyImgByPath(fullPath, undefined, {
      deferLargeVideo: false,
      deferSlowIo: false,
      // ⚠️ worker 自己就是生成方，必须关掉图片 defer，否则会「入队 → 又入队」死循环
      deferImages: false,
    }),
    ms,
    'file.TINY_TIMEOUT'
  );
}

class TinyImageWorker {
  constructor() {
    this.isRunning = false;
    this.init();
  }

  async init() {
    try {
      await knexUtil.init(dbUtil.DB_PATHS.PHOTO_DB);
      await knexUtil.init(dbUtil.DB_PATHS.VIDEO_DB);
      // MAIN_DB 只为读「后台预生成」开关，读不到不影响按需生成
      await knexUtil.init(dbUtil.DB_PATHS.MAIN_DB).catch(() => {});

      this.photoKnex = knexUtil.getInstance(dbUtil.DB_PATHS.PHOTO_DB);
      this.videoKnex = knexUtil.getInstance(dbUtil.DB_PATHS.VIDEO_DB);
      this.isRunning = true;

      // 「后台全量预生成」开关。默认 false = 按需生成（浏览器请求谁才生成谁）。
      this._pregenCache = { enabled: false, fetchedAt: 0 };
      await this._refreshPregenFlag(true);

      // 来源目录缓存，5 秒刷新一次，避免频繁查库
      this._sourceDirsCache = { dirs: new Set(), fetchedAt: 0 };
      await this._refreshSourceDirs();

      await this.startLoop();
    } catch (err) {
      Logger.error('❌ TinyImage Worker init failed:', err);
      process.exit(1);
    }
  }

  /**
   * 读「后台全量预生成」开关（带 TTL 缓存，支持运行时热切换）。
   * @param {boolean} force 忽略缓存强制读
   */
  async _refreshPregenFlag(force = false) {
    const now = Date.now();
    if (!force && now - this._pregenCache.fetchedAt < PREGEN_FLAG_TTL_MS) {
      return this._pregenCache.enabled;
    }
    let enabled = false;
    try {
      enabled = await tableConfig.getTinyPregenEnabled();
    } catch (err) {
      // 读不到就按「按需生成」处理：这是 CPU 更安全的一侧
      enabled = false;
    }
    const changed = enabled !== this._pregenCache.enabled || force;
    this._pregenCache = { enabled: !!enabled, fetchedAt: now };
    if (changed && !force) {
      Logger.info(`🔁 缩略图后台预生成开关 → ${enabled ? '开' : '关'}`);
    }
    return this._pregenCache.enabled;
  }

  async _refreshSourceDirs() {
    try {
      const photoRows = await this.photoKnex('photo_source')
        .select('path')
        .catch(() => []);
      const videoRows = await this.videoKnex('video_source')
        .select('path')
        .catch(() => []);

      const dirs = new Set();
      for (const row of photoRows || []) {
        const p = row && row.path ? path.resolve(String(row.path)) : '';
        if (p) dirs.add(p);
      }
      for (const row of videoRows || []) {
        const p = row && row.path ? path.resolve(String(row.path)) : '';
        if (p) dirs.add(p);
      }

      this._sourceDirsCache = { dirs, fetchedAt: Date.now() };
    } catch (err) {
      Logger.warn('⚠️ refresh source dirs failed:', err);
    }
  }

  async _ensureSourceDirsFresh() {
    if (Date.now() - this._sourceDirsCache.fetchedAt > 3000) {
      await this._refreshSourceDirs();
    }
  }

  /**
   * 检查文件所在父目录是否属于任一配置的来源目录
   */
  _isUnderSourceDir(fullPath) {
    if (!fullPath) return false;
    const targetDir = path.resolve(path.dirname(fullPath));
    for (const srcDir of this._sourceDirsCache.dirs) {
      if (targetDir === srcDir) return true;
      if (targetDir.startsWith(srcDir + path.sep)) return true;
    }
    return false;
  }

  async startLoop() {
    Logger.info(
      `TinyImage Worker startLoop (cpu=${CPU_COUNT}, fg=${FOREGROUND_CONCURRENCY}, bg=${BACKGROUND_CONCURRENCY}, ` +
        `后台预生成=${this._pregenCache.enabled ? '开' : '关(按需)'})`
    );
    let processedCount = 0;
    let updatedCount = 0;
    let failedCount = 0;

    const runBatch = async (rows, handler) => {
      if (!rows || rows.length === 0) return 0;
      const results = await Promise.all(
        rows.map(async row => {
          try {
            return await handler(row);
          } catch (err) {
            Logger.error('❌ tiny batch item failed:', err && err.message ? err.message : err);
            return false;
          }
        })
      );
      for (const ok of results) {
        processedCount++;
        if (ok) updatedCount++;
        else failedCount++;
      }
      return results.length;
    };

    while (this.isRunning) {
      try {
        // 优先级 1：用户正在浏览的图（wait_gen_tiny）—— 高并发，尽快出图
        const waitRows = await this.getWaitBatch(FOREGROUND_CONCURRENCY);
        if (waitRows.length > 0) {
          await runBatch(waitRows, r => this.processOneWait(r));
          continue;
        }

        // 优先级 2~4：后台补图 —— 单并发 + 限速，避免长时间吃满 CPU
        //
        // ⭐ 默认**关闭**（tableConfig.tinyPregenEnabled = '0'）：
        //   几十万张图绝大多数一辈子不会被点开，全量预生成纯属烧 CPU。
        //   关掉后只保留优先级 1（浏览器真的在看的图），体验上「滚到哪生成到哪」。
        //   想恢复全量预生成，把 tinyPregenEnabled 设为 '1' 即可（30s 内热生效）。
        if (await this._refreshPregenFlag()) {
          let didBackground = false;
          for (const [fetcher, handler] of [
            [() => this.getPhotoBatch(BACKGROUND_CONCURRENCY), r => this.processOnePhoto(r)],
            [() => this.getImageBatch(BACKGROUND_CONCURRENCY), r => this.processOneImage(r)],
            [() => this.getVideoBatch(BACKGROUND_CONCURRENCY), r => this.processOneVideo(r)],
          ]) {
            const rows = await fetcher();
            if (rows && rows.length > 0) {
              await runBatch(rows, handler);
              didBackground = true;
              break;
            }
          }
          if (didBackground) {
            await sleep(BACKGROUND_THROTTLE_MS);
            continue;
          }
        }

        // ⭐ 全空闲：**不退出**，改为轮询等待新任务（2026-10-10 修）。
        //
        // 原来这里是 break → process.exit(0)：worker 跑完队列就没了。
        // 之后浏览器请求缩略图时，`_deferTinyToWorker` 只能入队 + 发
        // `ensureTinyImageWorker` 唤醒；而唤醒要经过主进程转发、worker 重新
        // 初始化（连库 + 刷新来源目录），这几秒里前端拿到的全是 202，
        // 5 次重试（15.5s）一过就放弃 ⇒ 网格一片空白（实测就是这个现象）。
        //
        // 之所以敢常驻：空闲时每 IDLE_POLL_MS 才查一次库，CPU 占用可忽略；
        // 收到 stop 消息会立刻走 isRunning=false 正常退出。
        await sleep(IDLE_POLL_MS);
        continue;
      } catch (err) {
        Logger.error('❌ TinyImage Worker loop error:', err);
        await new Promise(r => setTimeout(r, 1000));
      }
    }

    Logger.info(`✅ TinyImage Worker stopped: processed=${processedCount}, updated=${updatedCount}, failed=${failedCount}`);
    process.exit(0);
  }

  /* ------------------------------ 队列取数 ------------------------------ */

  async getWaitBatch(limit) {
    return await this.photoKnex('wait_gen_tiny')
      .select('id', 'source_path')
      .orderBy('id', 'desc')
      .limit(limit)
      .catch(() => []) || [];
  }

  async getPhotoBatch(limit) {
    return await this.photoKnex('photo_index')
      .select('id', 'path', 'filename', 'type')
      .where({ is_file: 1, in_trash: 0 })
      .andWhere(qb => {
        qb.where('gen_tiny', 0).orWhereNull('gen_tiny');
      })
      .whereIn('type', [1, 2])
      .orderBy('id', 'asc')
      .limit(limit)
      .catch(() => []) || [];
  }

  /**
   * ⭐ 影视库里的图片（独立表 image_index）。
   * 走部分索引 idx_image_index_pending_tiny (id) WHERE gen_tiny = 0 ⇒ 取队列 O(log n)。
   */
  async getImageBatch(limit) {
    return await this.videoKnex('image_index')
      .select('id', 'path', 'filename', 'ext')
      .where('gen_tiny', 0)
      .orderBy('id', 'asc')
      .limit(limit)
      .catch(() => []) || [];
  }

  async getVideoBatch(limit) {
    return await this.videoKnex('video_index')
      .select('id', 'path', 'filename', 'ext')
      .where({ is_file: 1 })
      .whereIn('ext', Array.isArray(config.videoTypeList) ? config.videoTypeList : [])
      .andWhere(qb => {
        qb.where('gen_tiny', 0).orWhereNull('gen_tiny');
      })
      .orderBy('id', 'asc')
      .limit(limit)
      .catch(() => []) || [];
  }

  /* ------------------------------ 单条处理 ------------------------------ */

  async processOnePhoto(row) {
    const id = row && row.id ? Number(row.id) : 0;
    if (!id) return false;

    const fullPath = path.join(String(row.path || ''), String(row.filename || ''));

    // 来源目录不存在则跳过
    await this._ensureSourceDirsFresh();
    if (!this._isUnderSourceDir(fullPath)) {
      await this.photoKnex('photo_index').where({ id }).update({ gen_tiny: 1 });
      return false;
    }

    if (!fullPath || !(await pathAccessible(fullPath, TINY_PATH_CHECK_MS))) return false;

    try {
      const tinyPath = await generateTinyWithTimeout(fullPath);
      if (!tinyPath) return false;
      await this.photoKnex('photo_index').where({ id }).update({ gen_tiny: 1 });
      return true;
    } catch (err) {
      const msg = err && err.message ? String(err.message) : '';
      if (msg === 'file.TINY_TIMEOUT') {
        Logger.warn(`⏱ thumbnail gen timed out: ${fullPath}`);
      } else {
        Logger.error(`❌ thumbnail gen failed: ${fullPath}`, err);
      }
      // 失败也标记为已处理，避免同一条无限重试把队列卡死
      await this.photoKnex('photo_index').where({ id }).update({ gen_tiny: 1 });
      return false;
    }
  }

  /** 影视库图片（image_index）：写回 gen_tiny 用 videoKnex */
  async processOneImage(row) {
    const id = row && row.id ? Number(row.id) : 0;
    if (!id) return false;

    const fullPath = path.join(String(row.path || ''), String(row.filename || ''));

    await this._ensureSourceDirsFresh();
    if (!this._isUnderSourceDir(fullPath)) {
      await this.videoKnex('image_index').where({ id }).update({ gen_tiny: 1 });
      return false;
    }

    if (!fullPath || !(await pathAccessible(fullPath, TINY_PATH_CHECK_MS))) return false;

    try {
      const tinyPath = await generateTinyWithTimeout(fullPath);
      if (!tinyPath) return false;
      await this.videoKnex('image_index').where({ id }).update({ gen_tiny: 1 });
      return true;
    } catch (err) {
      const msg = err && err.message ? String(err.message) : '';
      if (msg === 'file.TINY_TIMEOUT') {
        Logger.warn(`⏱ image thumbnail gen timed out: ${fullPath}`);
      } else {
        Logger.error(`❌ image thumb gen failed: ${fullPath}`, err);
      }
      await this.videoKnex('image_index').where({ id }).update({ gen_tiny: 1 });
      return false;
    }
  }

  async processOneVideo(row) {
    const id = row && row.id ? Number(row.id) : 0;
    if (!id) return false;

    const fullPath = path.join(String(row.path || ''), String(row.filename || ''));

    // 来源目录不存在则跳过
    await this._ensureSourceDirsFresh();
    if (!this._isUnderSourceDir(fullPath)) {
      await this.videoKnex('video_index').where({ id }).update({ gen_tiny: 1 });
      return false;
    }

    if (!fullPath || !(await pathAccessible(fullPath, TINY_PATH_CHECK_MS))) return false;

    try {
      const tinyPath = await generateTinyWithTimeout(fullPath);
      if (!tinyPath) return false;
      await this.videoKnex('video_index').where({ id }).update({ gen_tiny: 1 });
      return true;
    } catch (err) {
      const msg = err && err.message ? String(err.message) : '';
      if (msg === 'file.TINY_TIMEOUT') {
        Logger.warn(`⏱ video thumbnail gen timed out: ${fullPath}`);
      } else {
        Logger.error(`❌ video thumb gen failed: ${fullPath}`, err);
      }
      await this.videoKnex('video_index').where({ id }).update({ gen_tiny: 1 });
      return false;
    }
  }

  /**
   * 按路径把「已生成缩略图」回写到索引表。
   *
   * ⚠️ 为什么需要：`wait_gen_tiny` 是**按需请求**队列（浏览器请求时写入），
   * 它只带 source_path，不带表/行 id。如果处理完不回写 gen_tiny，
   * 这些图之后又会被后台补图（getImageBatch/getVideoBatch）挑中重复生成一遍。
   * 三张表都试一下，各自独立 catch（相册图在 photo_index，影视图在 image_index/video_index）。
   */
  async _markTinyGenerated(fullPath) {
    if (!fullPath) return;
    const dir = path.dirname(fullPath);
    const name = path.basename(fullPath);
    const targets = [
      ['photo_index', this.photoKnex],
      ['image_index', this.videoKnex],
      ['video_index', this.videoKnex],
    ];
    for (const [table, k] of targets) {
      if (!k) {
        Logger.warn(`⚠️ _markTinyGenerated: ${table} 的连接未初始化`);
        continue;
      }
      try {
        await k(table).where({ path: dir, filename: name }).update({ gen_tiny: 1 });
      } catch (err) {
        // ⚠️ 不要静默吞：这里失败会导致后台反复重做同一张图
        Logger.warn(`⚠️ _markTinyGenerated ${table} 失败: ${err && err.message} | ${dir} | ${name}`);
      }
    }
  }

  async processOneWait(row) {
    const id = row && row.id ? Number(row.id) : 0;
    if (!id) return false;

    const sourcePath = row && row.source_path ? String(row.source_path || '') : '';
    const fullPath = sourcePath ? path.resolve(sourcePath) : '';

    // 来源目录不存在则跳过并删除记录
    await this._ensureSourceDirsFresh();
    if (!this._isUnderSourceDir(fullPath)) {
      await this.photoKnex('wait_gen_tiny').where({ id }).del();
      return false;
    }

    if (!fullPath || !(await pathAccessible(fullPath, TINY_PATH_CHECK_MS))) {
      await this.photoKnex('wait_gen_tiny').where({ id }).del();
      return false;
    }

    try {
      const tinyPath = await generateTinyWithTimeout(fullPath);
      await this.photoKnex('wait_gen_tiny').where({ id }).del();
      // 回写 gen_tiny，避免后台补图重复生成同一张
      if (tinyPath) await this._markTinyGenerated(fullPath);
      return !!tinyPath;
    } catch (err) {
      const msg = err && err.message ? String(err.message) : '';
      if (msg === 'file.TINY_TIMEOUT') {
        Logger.warn(`⏱ pending thumbnail gen timed out: ${fullPath}`);
      } else {
        Logger.error(`❌ pending thumbnail gen failed: ${fullPath}`, err);
      }
      await this.photoKnex('wait_gen_tiny').where({ id }).del();
      return false;
    }
  }

  stop() {
    this.isRunning = false;
  }
}

const worker = new TinyImageWorker();

process.on('message', message => {
  if (!message || !message.type) return;
  if (message.type === 'stop') worker.stop();
});

process.on('uncaughtException', err => {
  Logger.error('❌ tinyImage worker uncaughtException', err);
  process.exit(0);
});

process.on('unhandledRejection', reason => {
  Logger.error('❌ tinyImage worker unhandledRejection', reason);
  process.exit(0);
});
