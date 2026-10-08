import 'dart:async';

import 'package:get/get.dart';
import 'package:nascab_sync_core/nascab_sync_core.dart';

import '../core/app_prefs.dart';
import '../core/session.dart';
import 'sync_api_service.dart';

/// 同步任务控制器：列表、执行、增删改，以及调度器绑定。
class SyncController extends GetxController {
  static SyncController get instance => Get.find<SyncController>();

  final RxList<SyncTask> tasks = <SyncTask>[].obs;
  final RxBool loading = false.obs;
  final RxString errorText = ''.obs;

  /// 全局暂停自动同步（托盘菜单可切换）
  final RxBool autoPaused = false.obs;

  Timer? _refreshTimer;

  @override
  void onInit() {
    super.onInit();
    SyncScheduler.instance.onTrigger = (task) => runTask(task);
    Future<void>(() async {
      try {
        autoPaused.value = await AppPrefs.getAutoSyncPaused();
        if (autoPaused.value) SyncScheduler.instance.pause();
      } catch (_) {}
      // 未登录时不去请求，避免无意义的失败（登录成功后由界面触发刷新）
      if (SessionController.instance.loggedIn.value) {
        await refreshTasks();
      }
    });
    // 定时对齐服务端任务列表（其它端可能改了配置）
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (SessionController.instance.loggedIn.value) {
        refreshTasks();
      }
    });
  }

  @override
  void onClose() {
    _refreshTimer?.cancel();
    SyncScheduler.instance.stop();
    super.onClose();
  }

  bool isRunning(int taskId) => SyncEngine.instance.isRunning(taskId);

  SyncProgress? progressOf(int taskId) => SyncEngine.instance.progressOf(taskId);

  /// 拉取任务列表并同步给调度器
  Future<void> refreshTasks({bool showLoading = false}) async {
    if (showLoading) loading.value = true;
    errorText.value = '';
    try {
      final res = await SyncApiService.instance.list(page: 1, pageSize: 200);
      if (!res.success) {
        errorText.value = res.message ?? 'operation_failed'.tr;
        return;
      }
      final items = (res.data ?? const <String, dynamic>{})['items'];
      final list = (items is List ? items : const [])
          .whereType<Map>()
          .map((e) => SyncTask.fromMap(Map<String, dynamic>.from(e)))
          .toList();
      tasks.assignAll(list);
      SyncScheduler.instance.syncTasks(list);
    } catch (e) {
      errorText.value = 'operation_failed'.tr;
    } finally {
      loading.value = false;
    }
  }

  /// 执行单个任务，返回结果供界面提示
  Future<SyncRunResult?> runTask(SyncTask task) async {
    if (SyncEngine.instance.isRunning(task.id)) {
      return null;
    }
    SyncScheduler.instance.markRan(task.id);
    try {
      await SyncApiService.instance
          .updateStatus(id: task.id, status: SyncStatus.running);
    } catch (_) {}

    final result = await SyncEngine.instance.run(task);

    try {
      await SyncApiService.instance.updateStatus(
        id: task.id,
        status: result.ok ? SyncStatus.idle : SyncStatus.error,
        lastError: result.ok ? '' : (result.error ?? ''),
      );
    } catch (_) {}

    unawaited(refreshTasks());
    return result;
  }

  /// 依次执行全部任务（不并发，避免把带宽打满）
  Future<void> runAllTasks() async {
    for (final task in tasks.toList()) {
      await runTask(task);
    }
  }

  void cancelTask(int taskId) {
    SyncEngine.instance.cancel(taskId);
  }

  /// 切换全局自动同步暂停
  Future<void> setAutoPaused(bool value) async {
    autoPaused.value = value;
    if (value) {
      SyncScheduler.instance.pause();
    } else {
      SyncScheduler.instance.resume();
    }
    await AppPrefs.setAutoSyncPaused(value);
  }

  Future<String?> createOrUpdate({
    int? id,
    required String name,
    required String mode,
    required String localDir,
    required String remoteDir,
    required SyncFilterConfig filterConfig,
    required SyncConfig syncConfig,
  }) async {
    final deviceId = await AppPrefs.getDeviceId();
    final deviceName = await AppPrefs.getDeviceName();

    final res = await SyncApiService.instance.upsert(
      id: id,
      name: name,
      mode: mode,
      localDir: localDir,
      remoteDir: remoteDir,
      filterConfig: filterConfig,
      syncConfig: syncConfig,
      deviceId: deviceId,
      deviceName: deviceName,
    );

    if (!res.success) return res.message ?? 'operation_failed'.tr;
    await refreshTasks();
    return null;
  }

  Future<String?> removeTask(int id) async {
    final res = await SyncApiService.instance.delete(id: id);
    if (!res.success) return res.message ?? 'operation_failed'.tr;
    SyncEngine.instance.clearProgress(id);
    await refreshTasks();
    return null;
  }

  /// 取单个任务的最新详情
  Future<SyncTask?> getTask(int id) async {
    final res = await SyncApiService.instance.get(id: id);
    if (!res.success || res.data == null) return null;
    final raw = res.data!['item'] ?? res.data!['task'] ?? res.data!;
    if (raw is Map) {
      return SyncTask.fromMap(Map<String, dynamic>.from(raw));
    }
    return null;
  }

  /// 取同步记录
  Future<List<SyncRecord>> loadRecords(int taskId) async {
    final res = await SyncApiService.instance.listRecords(taskId: taskId);
    if (!res.success) return const [];
    final items = (res.data ?? const <String, dynamic>{})['items'];
    return (items is List ? items : const [])
        .whereType<Map>()
        .map((e) => SyncRecord.fromMap(Map<String, dynamic>.from(e)))
        .toList();
  }
}
