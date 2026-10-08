import 'package:get/get.dart';
import 'package:GNasCab/modules/video/library_setting/models/video_library.dart';
import 'package:GNasCab/modules/video/library_setting/service/video_library_api_service.dart';
import 'package:GNasCab/modules/video/video_main/controller/video_main_controller.dart';
import 'package:GNasCab/utils/dialog_util.dart';
import 'package:GNasCab/utils/toast_util.dart';

class VideoLibrarySettingsController extends GetxController {
  final RxList<VideoLibrary> libraries = <VideoLibrary>[].obs;
  final RxBool loading = false.obs;

  @override
  void onInit() {
    super.onInit();
    fetchLibraries();
  }

  Future<void> fetchLibraries({bool showLoading = false}) async {
    if (loading.value) return;
    loading.value = true;
    try {
      final list = await VideoLibraryApiService.instance.listLibraries(
        showLoading: showLoading,
      );
      libraries.assignAll(list);
    } finally {
      loading.value = false;
    }
  }

  /// 影视库变动后，左侧栏的栏目列表要同步刷新
  void _notifySidebar() {
    if (Get.isRegistered<VideoMainController>()) {
      Get.find<VideoMainController>().fetchLibraries();
    }
  }

  Future<bool> addLibrary(String name, String libType) async {
    final n = name.trim();
    if (n.isEmpty) {
      ToastUtil.show('video_library_name_required'.tr);
      return false;
    }
    if (!kVideoLibTypes.contains(libType)) return false;

    DialogUtil.showLoading(message: 'loading'.tr);
    try {
      final res = await VideoLibraryApiService.instance.addLibrary(
        n,
        libType: libType,
        showLoading: false,
      );
      DialogUtil.dismissLoading();
      if (!res.success) {
        ToastUtil.show(res.message ?? 'operation_failed'.tr);
        return false;
      }
      await fetchLibraries();
      _notifySidebar();
      ToastUtil.show('operation_success'.tr);
      return true;
    } catch (_) {
      DialogUtil.dismissLoading();
      ToastUtil.show('operation_failed'.tr);
      return false;
    }
  }

  Future<bool> renameLibrary(VideoLibrary library, String name) async {
    final n = name.trim();
    if (n.isEmpty) {
      ToastUtil.show('video_library_name_required'.tr);
      return false;
    }
    if (n == library.displayName) return false;

    DialogUtil.showLoading(message: 'loading'.tr);
    try {
      final res = await VideoLibraryApiService.instance.renameLibrary(
        library.id,
        n,
        showLoading: false,
      );
      DialogUtil.dismissLoading();
      if (!res.success) {
        ToastUtil.show(res.message ?? 'operation_failed'.tr);
        return false;
      }
      await fetchLibraries();
      _notifySidebar();
      ToastUtil.show('operation_success'.tr);
      return true;
    } catch (_) {
      DialogUtil.dismissLoading();
      ToastUtil.show('operation_failed'.tr);
      return false;
    }
  }

  /// 内置库、仍有来源的库由服务端拦截，这里只负责把失败原因透出
  Future<void> deleteLibrary(VideoLibrary library) async {
    final confirmed = await DialogUtil.showConfirmDialog(
      title: 'need_confirm'.tr,
      content: 'video_library_delete_confirm'.trParams({
        'name': library.displayName,
      }),
      confirmText: 'confirm'.tr,
      cancelText: 'cancel'.tr,
    );
    if (confirmed != true) return;

    DialogUtil.showLoading(message: 'loading'.tr);
    try {
      final res = await VideoLibraryApiService.instance.deleteLibrary(
        library.id,
        showLoading: false,
      );
      DialogUtil.dismissLoading();
      if (!res.success) {
        ToastUtil.show(res.message ?? 'operation_failed'.tr);
        return;
      }
      await fetchLibraries();
      _notifySidebar();
      ToastUtil.show('operation_success'.tr);
    } catch (_) {
      DialogUtil.dismissLoading();
      ToastUtil.show('operation_failed'.tr);
    }
  }
}
