import '../../../../core/api/api_controller.dart';
import '../beans/video_item_bean.dart';

class VideoUtils {
  static String getPosterUrl(VideoHomeItemBean item, {int? size}) {
    final posterPath = item.posterPath.trim();
    size ??= 500;
    if (posterPath.isNotEmpty) {
      return ApiController.instance.getTinyUrl(posterPath, size: size);
    }

    final fallbackFilePath = item.firstFilePath.isNotEmpty
        ? item.firstFilePath
        : item.fullPath;
    if (fallbackFilePath.trim().isEmpty) return '';
    return ApiController.instance.getTinyUrl(fallbackFilePath, size: size);
  }

  /// 列表网格用的**横版**图（2026-10-10，配合「缩略图」显示模式）。
  ///
  /// ⚠️ 这里**不能**用 [getFanartUrl] —— 那个走 `getRawFileUrl` 取原图，
  /// 详情页 / 首页大图用得，网格里几十上百张会拖垮加载。统一走 tiny 缩略图服务。
  ///
  /// 没有 fanart 的条目退回封面图（会被 16:9 的框裁掉上下，属预期行为）。
  static String getFanartThumbUrl(VideoHomeItemBean item, {int size = 500}) {
    final fanartPath = item.fanartPath.trim();
    if (fanartPath.isNotEmpty) {
      return ApiController.instance.getTinyUrl(fanartPath, size: size);
    }
    return getPosterUrl(item, size: size);
  }

  static String getFanartUrl(VideoHomeItemBean item, {int? size}) {
    size ??= 1600;
    final fanartPath = item.fanartPath.trim();
    if (fanartPath.isNotEmpty) {
      return ApiController.instance.getRawFileUrl(fanartPath);
    }
    // 没有 fanart 时回退到 poster，用 rawFile 避免加载 tiny 缩略图
    final posterPath = item.posterPath.trim();
    if (posterPath.isNotEmpty) {
      return ApiController.instance.getRawFileUrl(posterPath);
    }
    return getPosterUrl(item, size: size);
  }
}
