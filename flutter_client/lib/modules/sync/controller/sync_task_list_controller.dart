import 'dart:async';

import 'package:get/get.dart';
import 'package:nascab_sync_core/nascab_sync_core.dart';

import '../../../core/api/api_controller.dart';
import '../../../utils/dialog_util.dart';
import '../../../utils/device_utils.dart';
import '../../../utils/toast_util.dart';
import '../service/sync_api_service.dart';

class SyncTaskListController extends GetxController {
  final _api = SyncApiService();

  final RxString currentPageKey = 'sync.tasks'.obs;
  final RxDouble leftWidth = 180.0.obs;
  final RxBool sidebarCollapsed = false.obs;

  final RxList<SyncTask> tasks = <SyncTask>[].obs;
  final RxBool isLoading = false.obs;
  final RxString errorText = ''.obs;
  final RxString keyword = ''.obs;

  final opLoadingById = <int, bool>{}.obs;

  Timer? _pollTimer;
  Completer<void>? _refreshCompleter;

  SyncEngine get engine => SyncEngine.instance;

  /// 当前电脑名称，用于「同步设备」一步展示
  String get deviceName => DeviceUtils.platformName;

  /// 已登录的 NAS 地址
  String get serverLabel {
    final base = ApiController.instance.baseUrl.trim();
    if (base.isEmpty) return '-';
    try {
      final uri = Uri.parse(base);
      if (uri.host.isNotEmpty) return uri.host;
    } catch (_) {}
    return base;
  }

  String get serverId => ApiController.instance.state.serverId;

  @override
  void onInit() {
    super.onInit();
    // 自动同步（按需监听 + 定时）触发后静默执行，不弹任何提示
    SyncScheduler.instance.onTrigger = _autoSync;
    SyncScheduler.instance.start();
    refreshList(showLoading: false, clearOnFail: true, waitIfBusy: false);
    _startPolling();
  }

  @override
  void onClose() {
    _stopPolling();
    SyncScheduler.instance.onTrigger = null;
    SyncScheduler.instance.stop();
    super.onClose();
  }

  /// 由调度器触发的自动同步
  Future<void> _autoSync(SyncTask task) async {
    if (engine.isRunning(task.id)) return;
    await engine.run(task);
    await refreshList(
      showLoading: false,
      clearOnFail: false,
      waitIfBusy: false,
    );
  }

  void selectPage(String key) {
    currentPageKey.value = key;
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      refreshList(showLoading: false, clearOnFail: false, waitIfBusy: false);
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> refreshList({
    bool showLoading = true,
    bool clearOnFail = true,
    bool waitIfBusy = true,
  }) async {
    final inflight = _refreshCompleter;
    if (inflight != null && !inflight.isCompleted) {
      if (!waitIfBusy) return;
      await inflight.future;
    }
    _refreshCompleter = Completer<void>();
    isLoading.value = true;
    errorText.value = '';
    try {
      if (showLoading) DialogUtil.showLoading(message: 'loading'.tr);
      final res = await _api.list(
        page: 1,
        keyword: keyword.value.trim().isEmpty ? null : keyword.value.trim(),
      );
      if (!res.success) {
        errorText.value = res.message ?? 'operation_failed'.tr;
        if (clearOnFail) tasks.assignAll(const []);
        return;
      }
      final items = (res.data ?? const <String, dynamic>{})['items'];
      final list = (items is List ? items : const [])
          .whereType<Map>()
          .map((e) => SyncTask.fromMap(Map<String, dynamic>.from(e)))
          .toList();
      tasks.assignAll(list);
      SyncScheduler.instance.syncTasks(list);
    } catch (_) {
      errorText.value = 'operation_failed'.tr;
      if (clearOnFail) tasks.assignAll(const []);
    } finally {
      if (showLoading) DialogUtil.dismissLoading(force: true);
      isLoading.value = false;
      if (_refreshCompleter != null && !_refreshCompleter!.isCompleted) {
        _refreshCompleter!.complete();
      }
    }
  }

  Future<bool> upsert({
    int? id,
    required String name,
    required String mode,
    required String localDir,
    required String remoteDir,
    required SyncFilterConfig filterConfig,
    required SyncConfig syncConfig,
  }) async {
    final taskName = name.trim();
    if (taskName.isEmpty ||
        taskName.length > 32 ||
        localDir.trim().isEmpty ||
        remoteDir.trim().isEmpty) {
      ToastUtil.show('sync_required'.tr);
      return false;
    }
    if (!SyncMode.all.contains(mode)) {
      ToastUtil.show('operation_failed'.tr);
      return false;
    }

    final res = await _api.upsert(
      id: id,
      name: taskName,
      mode: mode,
      localDir: localDir.trim(),
      remoteDir: remoteDir.trim(),
      filterConfig: filterConfig,
      syncConfig: syncConfig,
      deviceId: serverId,
      deviceName: deviceName,
    );
    if (!res.success) {
      ToastUtil.show(res.message ?? 'operation_failed'.tr);
      return false;
    }
    await refreshList(showLoading: false, clearOnFail: true, waitIfBusy: true);
    ToastUtil.show('operation_success'.tr);
    return true;
  }

  Future<bool> remove({required int id}) async {
    final confirmed = await DialogUtil.showConfirmDialog(
      title: 'need_confirm'.tr,
      content: 'sync_delete_confirm'.tr,
      confirmText: 'ok'.tr,
      cancelText: 'cancel'.tr,
    );
    if (confirmed != true) return false;

    final res = await _api.delete(id: id);
    if (!res.success) {
      ToastUtil.show(res.message ?? 'delete_failed'.tr);
      return false;
    }
    await SyncLocalStore.instance.clearBaseline(id);
    SyncEngine.instance.clearProgress(id);
    await refreshList(showLoading: false, clearOnFail: true, waitIfBusy: true);
    ToastUtil.show('delete_success'.tr);
    return true;
  }

  /// 手动触发一次同步
  Future<void> startSync(SyncTask task) async {
    if (engine.isRunning(task.id)) {
      ToastUtil.show('sync_already_running'.tr);
      return;
    }
    opLoadingById[task.id] = true;
    opLoadingById.refresh();
    SyncScheduler.instance.markRan(task.id);
    try {
      final result = await engine.run(task);
      if (!mounted) return;
      if (result.ok) {
        if (result.uploadCount == 0 &&
            result.downloadCount == 0 &&
            result.deleteCount == 0) {
          ToastUtil.show('sync_up_to_date'.tr);
        } else {
          ToastUtil.show('sync_completed'.tr);
        }
      } else {
        ToastUtil.show(result.error ?? 'operation_failed'.tr);
      }
    } finally {
      opLoadingById[task.id] = false;
      opLoadingById.refresh();
      await refreshList(
        showLoading: false,
        clearOnFail: false,
        waitIfBusy: true,
      );
    }
  }

  /// 停止正在运行的同步
  Future<void> stopSync(int taskId) async {
    engine.cancel(taskId);
    ToastUtil.show('sync_stopping'.tr);
  }

  Future<Map<String, dynamic>?> fetchRecords({
    required int taskId,
    int page = 1,
    int pageSize = 50,
  }) async {
    final res = await _api.listRecords(
      taskId: taskId,
      page: page,
      pageSize: pageSize,
    );
    if (!res.success) return null;
    return res.data;
  }

  Future<void> setKeyword(String value) async {
    keyword.value = value;
    await refreshList(showLoading: false, clearOnFail: false, waitIfBusy: true);
  }
}
