'use strict';

const fs = require('fs');
const path = require('path');
const Logger = require('../../utils/logger');
const FileUtil = require('../../utils/fileUtil');
const dbUtil = require('../../db/dbUtil');
const knexUtil = require('../../db/knexUtil');
const { walkVideoEntries } = require('./videoIndexUtil');
const videoIndexIndexUtil = require('./videoIndexIndexUtil');

class VideoIndexWorker {
  constructor() {
    this.init();
  }

  async init() {
    try {
      await knexUtil.init(dbUtil.DB_PATHS.VIDEO_DB);

      await this.runUntilEmpty();
      process.exit(0);
    } catch (err) {
      Logger.error('❌ video index worker init failed:', err);
      process.exit(1);
    }
  }

  async runUntilEmpty() {
    while (true) {
      const task = await this.getNextTask();
      if (!task) {
        Logger.info('✅ No pending video scan tasks, worker exiting');
        return;
      }
      try {
        await this.runTask(task);
      } catch (err) {
        Logger.error('❌ Video scan task failed:', err);
        await this.deleteTask(task);
      }
    }
  }

  async getNextTask() {
    const knex = knexUtil.getInstance(dbUtil.DB_PATHS.VIDEO_DB);
    const tasks = await knex('video_scan_task').orderBy('create_time', 'asc').limit(1);
    if (!tasks || tasks.length === 0) return null;
    return tasks[0];
  }

  async runTask(task) {
    const scanPath = task && task.scan_path ? String(task.scan_path) : '';
    if (!scanPath) {
      await this.deleteTask(task);
      return;
    }

    let stat;
    try {
      stat = await fs.promises.stat(scanPath);
    } catch {
      Logger.info('Scan path no longer exists', scanPath);
      await this.deleteTask(task);
      return;
    }
    if (!stat.isDirectory()) {
      Logger.info('Scan path is not a directory', scanPath);
      await this.deleteTask(task);
      return;
    }

    const start = Date.now();
    Logger.info('Video library: start scan', scanPath);

    const knex = knexUtil.getInstance(dbUtil.DB_PATHS.VIDEO_DB);
    const source = await this.getMatchedSourceByScanPath(scanPath);
    if (!source) {
      Logger.info('Video library: source missing, cancel scan', scanPath);
      await this.deleteTask(task);
      return;
    }

    const sourceId = Number(source.id || 0) || 0;
    // 影视库类型决定扫描内容：movie/tv 影视，image 仅图片，mixed 图片+影视
    const libType = await this.resolveLibraryType(source);
    const isTvSource = libType === 'tv';
    const indexImages = libType === 'image' || libType === 'mixed';
    const indexVideos = libType !== 'image';

    await knex('video_source')
      .where({ id: sourceId })
      .update({ last_scan_time: Date.now() })
      .catch(() => {});

    await videoIndexIndexUtil.deleteMissingIndexes({ knex, scanPath });

    // ⭐ 图片索引（image_index）扫描期状态：
    //   ① 先把该来源已有的 (path||filename) -> file_mtime 载入内存（约 7 万条 ≈ 7MB）
    //   ② 扫描时逐条比对，**只有文件真的变了才写库** —— 避免 7 万张图逐行 fsync
    //   ③ 攒够 500 条一个事务批量 upsert
    //   ④ 扫完把「库里还在、本次没走到」的行删掉（文件被外部删除）
    const imageMtimeMap = indexImages
      ? await videoIndexIndexUtil.loadImageIndexMtimeMap({ knex, sourceId })
      : new Map();
    const imageSeenKeys = new Set();
    let imagePendingRows = [];
    let imageSkippedCount = 0;

    const flushImageRows = async () => {
      if (imagePendingRows.length === 0) return;
      const batch = imagePendingRows;
      imagePendingRows = [];
      await videoIndexIndexUtil.upsertImageIndexBatch(knex, batch);
    };

    const showStats = new Map();
    const seasonStats = new Map();
    const showSeasons = new Map();
    const dirtyShowKeys = new Set();
    const dirtySeasonKeys = new Set();

    let indexedCount = 0;
    let aborted = false;
    let processedVideoCount = 0;

    const flushTvFolderIndexes = async () => {
      if (!isTvSource) return;

      for (const showKey of Array.from(dirtyShowKeys)) {
        const s = showStats.get(showKey);
        if (!s) continue;
        const seasons = showSeasons.get(showKey);
        const seasonCount = seasons ? seasons.size : 0;
        await videoIndexIndexUtil.indexTvShowFolder({
          knex,
          showFolder: s.showFolder,
          seasonCount,
          episodCount: s.episodeCount,
        });
      }
      for (const seasonKey of Array.from(dirtySeasonKeys)) {
        const s = seasonStats.get(seasonKey);
        if (!s) continue;
        await videoIndexIndexUtil.indexSeasonFolder({
          knex,
          seasonFolder: s.seasonFolder,
          episodCount: s.episodeCount,
        });
      }

      dirtyShowKeys.clear();
      dirtySeasonKeys.clear();
    };

    const completed = await walkVideoEntries(scanPath, {
      onDirectory: async () => {
        const stillExists = await this.isSourceStillExists(sourceId);
        if (!stillExists) {
          aborted = true;
          return false;
        }
        return true;
      },
      onDiscFolder: async entry => {
        const stillExists = await this.isSourceStillExists(sourceId);
        if (!stillExists) {
          aborted = true;
          return false;
        }
        if (isTvSource || !indexVideos) return true;
        const mediaType = entry && entry.mediaType ? String(entry.mediaType) : '';
        const ok = mediaType === 'video_ts'
          ? await videoIndexIndexUtil.indexVideoTsFolder({ knex, ...entry })
          : await videoIndexIndexUtil.indexBdmvFolder({ knex, ...entry });
        if (ok) {
          indexedCount += 1;
          processedVideoCount += 1;
        }
        return true;
      },
      onImageFile: async entry => {
        const stillExists = await this.isSourceStillExists(sourceId);
        if (!stillExists) {
          aborted = true;
          return false;
        }
        const imgName = entry && entry.filename ? String(entry.filename) : '';
        if (FileUtil.shouldSkipIndexingFilename(imgName)) {
          return true;
        }

        const imgKey = `${entry && entry.dirPath ? entry.dirPath : ''}||${imgName}`;
        imageSeenKeys.add(imgKey);

        const row = await videoIndexIndexUtil.buildImageIndexRow({
          ...entry,
          libraryId: Number(source.library_id) || 0,
          sourceId,
        });
        if (!row) return true;

        // 文件 mtime 没变 ⇒ 整行跳过，完全不碰数据库
        const prevMtime = imageMtimeMap.get(imgKey);
        if (prevMtime !== undefined && prevMtime === row.file_mtime) {
          imageSkippedCount += 1;
          return true;
        }

        imagePendingRows.push(row);
        imageMtimeMap.set(imgKey, row.file_mtime);
        indexedCount += 1;
        processedVideoCount += 1;

        if (imagePendingRows.length >= 500) await flushImageRows();
        return true;
      },
      includeImages: indexImages,
      onVideoFile: async entry => {
        const stillExists = await this.isSourceStillExists(sourceId);
        if (!stillExists) {
          aborted = true;
          return false;
        }
        if (!indexVideos) return true;
        if (FileUtil.shouldSkipIndexingFilename(entry && entry.filename ? String(entry.filename) : '')) {
          return true;
        }

        // 根据 Jellyfin 约定：Sample 文件夹下的样片跳过索引
        const parentFolderName = path.basename(path.dirname(String(entry.fullPath || '')));
        if (String(parentFolderName || '').toLowerCase() === 'sample') {
          return true;
        }

        processedVideoCount += 1;

        if (isTvSource) {
          const { showFolder, seasonFolder } = videoIndexIndexUtil.getTvFoldersFromEpisode({ fullPath: entry.fullPath });

          const showKey = videoIndexIndexUtil.buildShowKey(showFolder);
          const prevShow = showStats.get(showKey) || { showFolder, episodeCount: 0 };
          prevShow.episodeCount += 1;
          showStats.set(showKey, prevShow);
          dirtyShowKeys.add(showKey);

          if (!showSeasons.has(showKey)) showSeasons.set(showKey, new Set());
          if (seasonFolder) {
            showSeasons.get(showKey).add(path.resolve(seasonFolder));
            const seasonKey = videoIndexIndexUtil.buildSeasonKey(seasonFolder);
            const prevSeason = seasonStats.get(seasonKey) || { seasonFolder, episodeCount: 0 };
            prevSeason.episodeCount += 1;
            seasonStats.set(seasonKey, prevSeason);
            dirtySeasonKeys.add(seasonKey);
          }

          const ok = await videoIndexIndexUtil.indexEpisodeFile({ knex, ...entry });
          if (ok) indexedCount += 1;
        } else {
          const ok = await videoIndexIndexUtil.indexMovieFile({ knex, ...entry });
          if (ok) indexedCount += 1;
        }

        // 扫描过程中分批生成“剧/季”索引，避免全部文件结束后才生成
        if (isTvSource && processedVideoCount % 50 === 0) {
          await flushTvFolderIndexes();
        }
        return true;
      },
    });
    if (completed === false) aborted = true;

    await flushTvFolderIndexes();

    // 图片索引收尾：先落盘剩余批次，再清理「本次没扫到」的陈旧行。
    // ⚠️ aborted（来源被删/中途退出）时不能清理 —— 那会把还没扫到的行误删。
    if (indexImages) {
      await flushImageRows();
      if (!aborted) {
        const staleCount = await videoIndexIndexUtil.deleteImageIndexesNotSeen({
          knex,
          libraryId: Number(source.library_id) || 0,
          sourceId,
          seenKeys: imageSeenKeys,
        });
        if (staleCount > 0) {
          Logger.info('Video library: removed stale image indexes', { scanPath, staleCount });
        }
      }
      Logger.info('Video library: image scan summary', {
        scanPath,
        seen: imageSeenKeys.size,
        written: indexedCount,
        skippedUnchanged: imageSkippedCount,
      });
    }

    Logger.info('Video library: scan done ' + scanPath, 'elapsedMs:', Date.now() - start, 'files:', indexedCount);

    if (process.send) {
      try {
        process.send({ type: 'videoIndexingFinished', data: { scanPath, indexedCount, aborted } });
      } catch (_) {}
    }

    await this.deleteTask(task);
  }

  async deleteTask(task) {
    if (!task || !task.id) return;
    const knex = knexUtil.getInstance(dbUtil.DB_PATHS.VIDEO_DB);
    await knex('video_scan_task')
      .where({ id: task.id })
      .delete()
      .catch(() => {});
  }

  async isSourceStillExists(sourceId) {
    const id = Number(sourceId || 0) || 0;
    if (!id) return false;
    const knex = knexUtil.getInstance(dbUtil.DB_PATHS.VIDEO_DB);
    const row = await knex('video_source').where({ id }).first('id');
    return !!(row && row.id);
  }

  async getMatchedSourceByScanPath(scanPath) {
    const resolvedScan = scanPath ? path.resolve(String(scanPath)) : '';
    if (!resolvedScan) return null;

    const knex = knexUtil.getInstance(dbUtil.DB_PATHS.VIDEO_DB);
    const rows = await knex('video_source')
      .select('id', 'path', 'media_type', 'library_id')
      .catch(() => []);

    let best = null;
    for (const r of rows || []) {
      const root = r && r.path ? path.resolve(String(r.path)) : '';
      if (!root) continue;
      const prefix = root.endsWith(path.sep) ? root : `${root}${path.sep}`;
      if (resolvedScan !== root && !resolvedScan.startsWith(prefix)) continue;
      if (!best || root.length > path.resolve(String(best.path || '')).length) best = r;
    }
    return best;
  }

  // 来源所属影视库的类型；库缺失时回退到来源自身的 media_type
  async resolveLibraryType(source) {
    const fallbackRaw = source && source.media_type ? String(source.media_type).trim().toLowerCase() : '';
    const fallback = ['movie', 'tv', 'image', 'mixed'].includes(fallbackRaw) ? fallbackRaw : 'movie';

    const libraryId = Number(source && source.library_id) || 0;
    if (!libraryId) return fallback;

    const knex = knexUtil.getInstance(dbUtil.DB_PATHS.VIDEO_DB);
    const row = await knex('video_library').where({ id: libraryId }).first('lib_type').catch(() => null);
    const libType = row && row.lib_type ? String(row.lib_type).trim().toLowerCase() : '';
    return ['movie', 'tv', 'image', 'mixed'].includes(libType) ? libType : fallback;
  }
}

new VideoIndexWorker();

process.on('message', message => {
  if (message && message.type === 'stop') {
    process.exit(0);
  }
});

process.on('uncaughtException', err => {
  Logger.error('❌ videoIndex worker uncaughtException', err);
  process.exit(0);
});

process.on('unhandledRejection', reason => {
  Logger.error('❌ videoIndex worker unhandledRejection', reason);
  process.exit(0);
});
