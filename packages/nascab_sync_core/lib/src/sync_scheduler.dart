import 'dart:async';
import 'dart:io';

import 'sync_models.dart';
import 'sync_engine.dart';

/// 同步调度器
///
/// 两种自动触发来源：
/// 1. 按需同步：监听本地目录变化，防抖后触发；
/// 2. 定时同步：按任务配置的间隔定期触发。
///
/// 手动同步由界面直接调用 [SyncEngine.run]，不经过这里。
class SyncScheduler {
  SyncScheduler._();
  static final SyncScheduler instance = SyncScheduler._();

  /// 文件变化后的防抖时长
  static const Duration _fsDebounce = Duration(seconds: 20);

  /// 同一任务两次自动触发的最小间隔
  static const int _minTriggerGapMs = 30 * 1000;

  final Map<int, StreamSubscription<FileSystemEvent>> _watchers = {};
  final Map<int, Timer> _debounceTimers = {};
  final Map<int, int> _lastRunMs = {};

  List<SyncTask> _tasks = const [];
  Timer? _tickTimer;
  bool _running = false;

  /// 由控制器注入：真正执行同步的回调
  Future<void> Function(SyncTask task)? onTrigger;

  bool get isActive => _running;

  /// 全局暂停自动同步（手动同步不受影响）。
  ///
  /// 独立客户端在托盘菜单里可以让用户临时停掉自动同步，
  /// 主客户端目前未使用，但保留在共享层以便两边行为一致。
  bool _paused = false;
  bool get isPaused => _paused;

  void pause() {
    _paused = true;
    for (final t in _debounceTimers.values) {
      t.cancel();
    }
    _debounceTimers.clear();
  }

  void resume() {
    _paused = false;
  }

  void start() {
    if (_running) return;
    _running = true;
    _tickTimer = Timer.periodic(const Duration(seconds: 60), (_) => _tick());
  }

  void stop() {
    _running = false;
    _tickTimer?.cancel();
    _tickTimer = null;
    for (final sub in _watchers.values) {
      sub.cancel();
    }
    _watchers.clear();
    for (final t in _debounceTimers.values) {
      t.cancel();
    }
    _debounceTimers.clear();
    _tasks = const [];
  }

  /// 任务列表刷新后调用，同步调度状态（幂等）
  void syncTasks(List<SyncTask> tasks) {
    _tasks = List<SyncTask>.from(tasks);
    if (_tasks.isEmpty) return;
    start();

    final aliveIds = tasks.map((e) => e.id).toSet();

    // 清理已被删除的任务
    for (final id in _watchers.keys.toList()) {
      if (!aliveIds.contains(id)) {
        _watchers.remove(id)?.cancel();
        _debounceTimers.remove(id)?.cancel();
        _lastRunMs.remove(id);
      }
    }

    for (final task in tasks) {
      final last = task.lastSyncTime;
      _lastRunMs.putIfAbsent(
        task.id,
        () => (last != null && last > 0)
            ? last
            : DateTime.now().millisecondsSinceEpoch,
      );
      if (task.syncConfig.realtime) {
        _ensureWatcher(task);
      } else {
        _watchers.remove(task.id)?.cancel();
      }
    }
  }

  void _ensureWatcher(SyncTask task) {
    if (_watchers.containsKey(task.id)) return;
    if (task.localDir.trim().isEmpty) return;
    try {
      final dir = Directory(task.localDir);
      if (!dir.existsSync()) return;
      final sub = dir.watch(recursive: true).listen(
        (_) => _onFsChanged(task),
        onError: (_) {},
        cancelOnError: false,
      );
      _watchers[task.id] = sub;
    } catch (_) {
      // 某些平台或网络盘不支持递归监听，退化为只依赖定时同步
    }
  }

  void _onFsChanged(SyncTask task) {
    if (_paused) return;
    _debounceTimers.remove(task.id)?.cancel();
    _debounceTimers[task.id] = Timer(_fsDebounce, () {
      _debounceTimers.remove(task.id);
      _trigger(task);
    });
  }

  void _tick() {
    if (_paused) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final task in _tasks) {
      final interval = task.syncConfig.intervalMinutes;
      if (interval <= 0) continue;
      final last = _lastRunMs[task.id] ?? task.lastSyncTime ?? now;
      if (now - last >= interval * 60 * 1000) {
        _trigger(task);
      }
    }
  }

  Future<void> _trigger(SyncTask task) async {
    if (SyncEngine.instance.isRunning(task.id)) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final last = _lastRunMs[task.id] ?? 0;
    if (now - last < _minTriggerGapMs) return;
    _lastRunMs[task.id] = now;
    try {
      await onTrigger?.call(task);
    } catch (_) {}
  }

  /// 任务被手动同步后同步节流时间，避免立刻又被自动触发
  void markRan(int taskId) {
    _lastRunMs[taskId] = DateTime.now().millisecondsSinceEpoch;
  }
}
