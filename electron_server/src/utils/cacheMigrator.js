'use strict';
// 缓存目录搬迁引擎（中文注释）
//
// 设计目标：
//  1) 用户修改「自定义缓存目录」后，把整个 nascabos_cache 搬到新位置；
//  2) 搬迁只在服务对外提供 API 之前执行 —— 此时 Express worker 还没 fork，
//     客户端连不上，等价于「搬数据期间不能操作」，不会出现「边写边搬」的数据竞争；
//  3) 全程可中断：状态实时落盘，中途关闭服务后重新打开会自动接着搬（按文件大小比对跳过已完成的）；
//  4) 任何一步失败都只降级、不破坏：旧目录保持原样，服务照常用旧缓存启动。
const fs = require('fs');
const path = require('path');
const Logger = require('./logger');
const config = require('../config/config');

const STATE_FILE = 'cache_migration.json';
// 进度落盘频率：每 200 个文件或每 1.5 秒写一次，断电最多重做这一小批
const PROGRESS_FLUSH_FILES = 200;
const PROGRESS_FLUSH_MS = 1500;

// 明显不该作为缓存父目录的位置（避免用户误选系统盘根 / 系统目录）
const BLOCKED_SEGMENTS = [
  'windows',
  'system32',
  'syswow64',
  'program files',
  'program files (x86)',
  'programdata',
  'system',
  'usr',
  'bin',
];

let cachedState = null;
let running = false;

function getStateFilePath() {
  return path.join(config.getUserDataPath(), STATE_FILE);
}

function readStateFromDisk() {
  try {
    const p = getStateFilePath();
    if (!fs.existsSync(p)) return null;
    const raw = fs.readFileSync(p, 'utf8');
    if (!raw || !raw.trim()) return null;
    const json = JSON.parse(raw);
    if (!json || typeof json !== 'object') return null;
    return {
      version: 1,
      state: String(json.state || ''),
      phase: String(json.phase || ''),
      src: String(json.src || ''),
      dest: String(json.dest || ''),
      totalFiles: Number(json.totalFiles) || 0,
      doneFiles: Number(json.doneFiles) || 0,
      totalBytes: Number(json.totalBytes) || 0,
      doneBytes: Number(json.doneBytes) || 0,
      startedAt: Number(json.startedAt) || 0,
      updatedAt: Number(json.updatedAt) || 0,
      lastError: json.lastError ? String(json.lastError) : null,
    };
  } catch (_) {
    return null;
  }
}

function writeState(state) {
  cachedState = state;
  try {
    const p = getStateFilePath();
    const tmp = `${p}.tmp`;
    fs.writeFileSync(tmp, JSON.stringify(state, null, 2), 'utf8');
    fs.renameSync(tmp, p);
  } catch (_) {}
}

function clearState() {
  cachedState = null;
  try {
    fs.unlinkSync(getStateFilePath());
  } catch (_) {}
}

function getMigrationState() {
  if (!cachedState) cachedState = readStateFromDisk();
  return cachedState;
}

/**
 * 计算搬迁计划。src 取「当前进程实际生效的缓存根」，dest 取「用户配置期望的父目录」。
 */
function getPlan() {
  const defaultParent = path.resolve(config.getUserDataPath());
  const fromParent = path.resolve(config.getEffectiveCacheParent());
  const toParent = path.resolve(config.getConfiguredCacheParent());
  const src = path.resolve(process.env.PATH_CACHE || path.join(fromParent, config.getCacheFolderName()));
  const dest = path.resolve(path.join(toParent, config.getCacheFolderName()));
  return {
    src,
    dest,
    fromParent,
    toParent,
    defaultParent,
    required: src !== dest,
  };
}

function isSubPath(candidate, base) {
  const rel = path.relative(base, candidate);
  return !!rel && !rel.startsWith('..') && !path.isAbsolute(rel);
}

function isDangerousParent(abs) {
  if (abs === path.parse(abs).root) return true;
  const segs = abs
    .split(/[\\/]+/)
    .filter(Boolean)
    .map(s => s.toLowerCase());
  return segs.some(s => BLOCKED_SEGMENTS.includes(s));
}

/**
 * 校验用户选择的缓存父目录是否可用（供 IPC 调用，失败时返回 i18n key 后缀）
 */
function validateTargetParent(parent) {
  const raw = parent === null || parent === undefined ? '' : String(parent).trim();
  if (!raw) return { ok: true, parent: '' }; // 空 = 恢复默认
  if (!path.isAbsolute(raw)) return { ok: false, error: 'notAbsolute' };

  const abs = path.resolve(raw);
  const plan = getPlan();
  const targetRoot = path.resolve(path.join(abs, config.getCacheFolderName()));

  if (targetRoot === plan.src) return { ok: false, error: 'same' };
  if (isSubPath(targetRoot, plan.src)) return { ok: false, error: 'insideSource' };
  if (isSubPath(plan.src, targetRoot)) return { ok: false, error: 'containsSource' };
  if (isDangerousParent(abs)) return { ok: false, error: 'dangerous' };
  // 目标缓存根已被同名文件占用（而不是目录）：提前拦下，避免搬迁到一半才失败
  try {
    if (fs.existsSync(targetRoot) && !fs.statSync(targetRoot).isDirectory()) {
      return { ok: false, error: 'occupied' };
    }
  } catch (_) {}

  return { ok: true, parent: abs, cacheRoot: targetRoot };
}

async function collectFiles(root) {
  const out = [];
  const stack = [root];
  while (stack.length) {
    const dir = stack.pop();
    let entries;
    try {
      entries = await fs.promises.readdir(dir, { withFileTypes: true });
    } catch (_) {
      continue;
    }
    for (const entry of entries) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) {
        stack.push(full);
      } else if (entry.isFile()) {
        try {
          const stat = await fs.promises.stat(full);
          out.push({ rel: path.relative(root, full), size: stat.size });
        } catch (_) {}
      }
    }
  }
  return out;
}

async function isSameSize(filePath, size) {
  try {
    const stat = await fs.promises.stat(filePath);
    return stat.isFile() && stat.size === size;
  } catch (_) {
    return false;
  }
}

function isDirMissingOrEmpty(dir) {
  try {
    return fs.readdirSync(dir).length === 0;
  } catch (_) {
    return true;
  }
}

function buildState(plan, patch) {
  const prev = readStateFromDisk();
  return Object.assign(
    {
      version: 1,
      state: 'running',
      phase: 'copy',
      src: plan.src,
      dest: plan.dest,
      totalFiles: 0,
      doneFiles: 0,
      totalBytes: 0,
      doneBytes: 0,
      startedAt: Date.now(),
      updatedAt: Date.now(),
      lastError: null,
    },
    prev ? { startedAt: prev.startedAt || Date.now() } : null,
    patch
  );
}

function emit(onProgress, state) {
  if (typeof onProgress !== 'function' || !state) return;
  try {
    onProgress(publicState(state));
  } catch (_) {}
}

function publicState(state) {
  if (!state) return null;
  const total = state.totalBytes > 0 ? state.totalBytes : state.totalFiles;
  const done = state.totalBytes > 0 ? state.doneBytes : state.doneFiles;
  return {
    state: state.state,
    phase: state.phase,
    src: state.src,
    dest: state.dest,
    totalFiles: state.totalFiles,
    doneFiles: state.doneFiles,
    totalBytes: state.totalBytes,
    doneBytes: state.doneBytes,
    progress: total > 0 ? Math.min(100, Math.round((done / total) * 100)) : 0,
    lastError: state.lastError,
    updatedAt: state.updatedAt,
  };
}

/**
 * 搬迁成功收尾：更新 effectiveParent 与进程级缓存路径。
 * 之后 fork 的 Express worker / 各个 worker 都会继承新的 PATH_CACHE。
 */
function commitSwitch(plan) {
  config.setCacheEffectiveParent(plan.toParent);
  process.env.PATH_CACHE = plan.dest;
  process.env.NASCAB_CACHE_PARENT = plan.toParent;
  Logger.info('[cacheMigrator] 缓存目录已切换', { cachePath: plan.dest });
}

function failState(plan, message) {
  const state = buildState(plan, {
    state: 'failed',
    phase: 'error',
    lastError: message,
    updatedAt: Date.now(),
  });
  writeState(state);
  return state;
}

async function copyTree(plan, onProgress) {
  const prev = readStateFromDisk();
  let state;
  if (
    prev &&
    prev.state !== 'done' &&
    path.resolve(prev.src) === plan.src &&
    path.resolve(prev.dest) === plan.dest
  ) {
    // 上次没搬完（进程被关闭 / 断电），继续
    state = buildState(plan, {
      state: 'running',
      phase: 'copy',
      src: plan.src,
      dest: plan.dest,
      totalFiles: prev.totalFiles,
      doneFiles: 0,
      totalBytes: prev.totalBytes,
      doneBytes: 0,
      startedAt: prev.startedAt || Date.now(),
    });
    Logger.info('[cacheMigrator] 检测到未完成的搬迁，继续执行', {
      doneFilesBefore: prev.doneFiles,
      totalFiles: prev.totalFiles,
    });
  } else {
    state = buildState(plan, { state: 'running', phase: 'copy' });
    Logger.info('[cacheMigrator] 开始搬迁缓存目录', { from: plan.src, to: plan.dest });
  }
  writeState(state);
  emit(onProgress, state);

  let files;
  try {
    files = await collectFiles(plan.src);
  } catch (err) {
    const message = `扫描源缓存目录失败：${err && err.message ? err.message : String(err)}`;
    Logger.error('[cacheMigrator] ' + message);
    const failed = failState(plan, message);
    emit(onProgress, failed);
    return { ok: false, error: message, plan, state: failed };
  }

  state = buildState(plan, {
    state: 'running',
    phase: 'copy',
    src: plan.src,
    dest: plan.dest,
    totalFiles: files.length,
    doneFiles: 0,
    totalBytes: files.reduce((acc, f) => acc + f.size, 0),
    doneBytes: 0,
    startedAt: state.startedAt,
  });
  writeState(state);
  emit(onProgress, state);

  let lastFlush = Date.now();
  let sinceFlush = 0;

  for (const file of files) {
    const sourceFile = path.join(plan.src, file.rel);
    const destFile = path.join(plan.dest, file.rel);
    try {
      // 大小一致即视为已复制 —— 这就是断点续传的判据
      if (!(await isSameSize(destFile, file.size))) {
        await fs.promises.mkdir(path.dirname(destFile), { recursive: true });
        await fs.promises.copyFile(sourceFile, destFile);
        if (!(await isSameSize(destFile, file.size))) {
          throw new Error('复制后文件大小不一致');
        }
      }
    } catch (err) {
      const message = `复制失败：${file.rel}（${err && err.message ? err.message : String(err)}）`;
      Logger.error('[cacheMigrator] ' + message);
      const failed = buildState(plan, {
        state: 'failed',
        phase: 'error',
        src: plan.src,
        dest: plan.dest,
        totalFiles: files.length,
        doneFiles: state.doneFiles,
        totalBytes: state.totalBytes,
        doneBytes: state.doneBytes,
        startedAt: state.startedAt,
        lastError: message,
      });
      writeState(failed);
      emit(onProgress, failed);
      return { ok: false, error: message, plan, state: failed };
    }

    state.doneFiles += 1;
    state.doneBytes += file.size;

    sinceFlush += 1;
    const now = Date.now();
    if (sinceFlush >= PROGRESS_FLUSH_FILES || now - lastFlush >= PROGRESS_FLUSH_MS) {
      state.updatedAt = now;
      writeState(state);
      emit(onProgress, state);
      sinceFlush = 0;
      lastFlush = now;
    }
  }

  // 全部复制完成 -> 清理旧目录
  state.phase = 'cleanup';
  state.updatedAt = Date.now();
  writeState(state);
  emit(onProgress, state);
  Logger.info('[cacheMigrator] 文件复制完成，准备清理旧缓存目录', { src: plan.src });

  try {
    fs.rmSync(plan.src, { recursive: true, force: true, maxRetries: 3 });
  } catch (err) {
    // 删除失败不影响切换（新目录数据已完整），只是多占一份空间
    Logger.warn('[cacheMigrator] 旧缓存目录删除失败，可稍后手动清理', {
      src: plan.src,
      message: err && err.message ? err.message : String(err),
    });
  }

  commitSwitch(plan);

  state = buildState(plan, {
    state: 'done',
    phase: 'done',
    src: plan.src,
    dest: plan.dest,
    totalFiles: files.length,
    doneFiles: files.length,
    totalBytes: state.totalBytes,
    doneBytes: state.totalBytes,
    startedAt: state.startedAt,
    lastError: null,
  });
  writeState(state);
  emit(onProgress, state);
  Logger.info('[cacheMigrator] 缓存搬迁完成', { dest: plan.dest, files: files.length });
  return { ok: true, plan, state, migrated: true, cachePath: plan.dest };
}

/**
 * 启动阶段执行搬迁。必须在本进程 fork Express worker 之前调用。
 * @returns {Promise<{ok:boolean, skipped?:boolean, error?:string, cachePath?:string, plan:object}>}
 */
async function runStartupMigration(options) {
  const onProgress = options && typeof options.onProgress === 'function' ? options.onProgress : null;
  if (running) return { ok: true, skipped: true, plan: getPlan() };

  const plan = getPlan();
  if (!plan.required) {
    // 期望位置与实际位置一致：同步一次 effectiveParent（兼容手工改过配置的场景）
    const cfg = config.readCacheLocationConfig();
    if (cfg && cfg.parent && cfg.effectiveParent !== cfg.parent) {
      config.setCacheEffectiveParent(cfg.parent);
    }
    return { ok: true, skipped: true, plan };
  }

  running = true;
  try {
    Logger.info('[cacheMigrator] 检测到缓存目录变更，准备搬迁', {
      from: plan.src,
      to: plan.dest,
      note: '搬迁期间服务不对外提供 API，客户端将无法操作',
    });

    const validated = validateTargetParent(plan.toParent);
    if (!validated.ok) {
      const message = `目标缓存目录不合法（${validated.error}）`;
      Logger.error('[cacheMigrator] ' + message, { toParent: plan.toParent });
      const failed = failState(plan, message);
      emit(onProgress, failed);
      return { ok: false, error: message, plan, state: failed };
    }

    // 目标父目录必须可写
    const destParent = path.dirname(plan.dest);
    try {
      fs.mkdirSync(destParent, { recursive: true });
      const probe = path.join(destParent, `.nascab_write_test_${process.pid}`);
      fs.writeFileSync(probe, 'ok');
      fs.unlinkSync(probe);
    } catch (err) {
      const message = `目标缓存目录不可写：${destParent}（${err && err.message ? err.message : String(err)}）`;
      Logger.error('[cacheMigrator] ' + message);
      const failed = failState(plan, message);
      emit(onProgress, failed);
      return { ok: false, error: message, plan, state: failed };
    }

    // 目标位置已被同名文件占用（不是目录）：提前失败，避免产生半截状态
    try {
      if (fs.existsSync(plan.dest) && !fs.statSync(plan.dest).isDirectory()) {
        const message = `目标位置已被同名文件占用：${plan.dest}`;
        Logger.error('[cacheMigrator] ' + message);
        const failed = failState(plan, message);
        emit(onProgress, failed);
        return { ok: false, error: message, plan, state: failed };
      }
    } catch (_) {}

    // 源目录不存在或为空：没有内容要搬，直接切换
    if (!fs.existsSync(plan.src) || isDirMissingOrEmpty(plan.src)) {
      Logger.info('[cacheMigrator] 源缓存目录不存在或为空，直接切换缓存位置');
      commitSwitch(plan);
      clearState();
      return { ok: true, plan, cachePath: plan.dest, switched: true };
    }

    // 同盘且目标尚不存在：直接重命名，瞬时完成（原子操作，天然可重入）
    if (!fs.existsSync(plan.dest)) {
      try {
        await fs.promises.rename(plan.src, plan.dest);
        Logger.info('[cacheMigrator] 同盘重命名完成', { from: plan.src, to: plan.dest });
        commitSwitch(plan);
        clearState();
        return { ok: true, plan, cachePath: plan.dest, moved: true };
      } catch (err) {
        Logger.info('[cacheMigrator] 无法直接重命名，改用逐文件复制', {
          code: err && err.code,
          message: err && err.message ? err.message : String(err),
        });
      }
    }

    const result = await copyTree(plan, onProgress);
    if (result.ok) {
      clearState();
      return { ok: true, plan, cachePath: plan.dest, migrated: true };
    }
    return result;
  } finally {
    running = false;
  }
}

/**
 * 供 UI 展示的搬迁状态
 */
function getStatusForUi() {
  const plan = getPlan();
  const state = getMigrationState();
  const base = plan.required
    ? state
      ? publicState(state)
      : {
          state: 'pending',
          phase: '',
          src: plan.src,
          dest: plan.dest,
          totalFiles: 0,
          doneFiles: 0,
          totalBytes: 0,
          doneBytes: 0,
          progress: 0,
          lastError: null,
          updatedAt: 0,
        }
    : {
        state: state && state.state === 'failed' ? 'failed' : 'idle',
        phase: state ? state.phase : '',
        src: plan.src,
        dest: plan.dest,
        totalFiles: state ? state.totalFiles : 0,
        doneFiles: state ? state.doneFiles : 0,
        totalBytes: state ? state.totalBytes : 0,
        doneBytes: state ? state.doneBytes : 0,
        progress: 0,
        lastError: state ? state.lastError : null,
        updatedAt: state ? state.updatedAt : 0,
      };
  return Object.assign({ required: plan.required, running }, base);
}

module.exports = {
  getPlan,
  getStatusForUi,
  getMigrationState,
  runStartupMigration,
  validateTargetParent,
  clearState,
};
