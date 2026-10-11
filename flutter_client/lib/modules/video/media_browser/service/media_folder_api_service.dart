import 'package:get/get.dart';

import '../../../../core/api/base_api_service.dart';
import '../bean/media_folder_item.dart';

/// 图片库 / 混合库的文件夹层级接口。
///
/// ⚠️ 与 `VideoListApiService.listPaged` 分工不同：
///   * 本服务只负责「这一层有哪些子文件夹」；
///   * 「这一层有哪些文件」仍然走 `listPaged(folderMode: 'exact')`。
class MediaFolderApiService extends BaseApiService {
  static MediaFolderApiService get instance =>
      Get.isRegistered<MediaFolderApiService>()
      ? Get.find<MediaFolderApiService>()
      : MediaFolderApiService();

  Future<MediaFolderLevel> listFolders({
    required int libraryId,
    String folderPath = '',
  }) async {
    final res = await apiPost<Map<String, dynamic>>(
      '/api/video/image/folders',
      body: {
        'library_id': libraryId,
        // 空串 = 库根。这里刻意**总是带上** folderPath：服务端对空串
        // 走「各来源根自身」的分支，和「没传」不是一回事。
        'folderPath': folderPath.trim(),
      },
      showLoading: false,
    );

    if (!res.success) return MediaFolderLevel.empty(folderPath.trim());
    return MediaFolderLevel.fromJson(res.data ?? <String, dynamic>{});
  }
}
