import 'package:get/get.dart';
import 'package:GNasCab/core/api/base_api_service.dart';
import 'package:GNasCab/modules/video/library_setting/models/video_library.dart';

class VideoLibraryApiService extends BaseApiService {
  static VideoLibraryApiService get instance =>
      Get.isRegistered<VideoLibraryApiService>()
      ? Get.find<VideoLibraryApiService>()
      : VideoLibraryApiService();

  /// 影视库列表（所有登录用户可读，左侧栏也需要）
  Future<List<VideoLibrary>> listLibraries({bool showLoading = false}) async {
    final res = await apiPost<List<dynamic>>(
      '/api/video/library/list',
      body: {},
      showLoading: showLoading,
    );
    if (!res.success) return <VideoLibrary>[];

    final raw = res.data ?? <dynamic>[];
    return raw
        .whereType<Map>()
        .map((e) => VideoLibrary.fromJson(e.cast<String, dynamic>()))
        .where((e) => e.id > 0)
        .toList();
  }

  /// 新建影视库；[libType] 创建后不可修改
  Future<ApiResponse<Map<String, dynamic>>> addLibrary(
    String name, {
    required String libType,
    bool showLoading = true,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/video/library/add',
      body: {'name': name, 'lib_type': libType},
      showLoading: showLoading,
    );
  }

  /// 重命名影视库（只改名字，类型不变）
  Future<ApiResponse<Map<String, dynamic>>> renameLibrary(
    int id,
    String name, {
    bool showLoading = true,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/video/library/rename/$id',
      body: {'name': name},
      showLoading: showLoading,
    );
  }

  /// 删除影视库：内置库与仍有来源的库会被服务端拒绝
  Future<ApiResponse<Map<String, dynamic>>> deleteLibrary(
    int id, {
    bool showLoading = true,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/video/library/delete/$id',
      body: {},
      showLoading: showLoading,
    );
  }
}
