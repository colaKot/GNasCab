import 'package:get/get.dart';
import '../../../../core/api/base_api_service.dart';
import '../../base/beans/video_item_bean.dart';

class VideoHomeApiService extends BaseApiService {
  static VideoHomeApiService get instance =>
      Get.isRegistered<VideoHomeApiService>()
      ? Get.find<VideoHomeApiService>()
      : VideoHomeApiService();

  Future<ApiResponse<VideoHomeData>> getHomeData({
    int recommendLimit = 11,
    int recentPlayLimit = 20,
    int recentAddLimit = 20,
    bool showLoading = false,
  }) async {
    final res = await apiPost<Map<String, dynamic>>(
      '/api/video/home/data',
      body: {
        'recommend_limit': recommendLimit,
        'recent_play_limit': recentPlayLimit,
        'recent_add_limit': recentAddLimit,
      },
      showLoading: showLoading,
    );

    if (!res.success) {
      return ApiResponse.failure(res.message ?? 'request_failed');
    }
    final data = res.data ?? <String, dynamic>{};
    return ApiResponse.success(VideoHomeData.fromJson(data));
  }
}

class VideoHomeData {
  final List<Map<String, dynamic>> sourceList;
  final List<VideoHomeItemBean> recommend;
  final List<VideoHomeItemBean> recentPlay;

  /// 按影视库分组的最近添加：只含勾选了「主页显示」的库
  final List<VideoHomeLibraryGroup> recentAddByLib;

  const VideoHomeData({
    required this.sourceList,
    required this.recommend,
    required this.recentPlay,
    required this.recentAddByLib,
  });

  const VideoHomeData.empty()
    : sourceList = const <Map<String, dynamic>>[],
      recommend = const <VideoHomeItemBean>[],
      recentPlay = const <VideoHomeItemBean>[],
      recentAddByLib = const <VideoHomeLibraryGroup>[];

  factory VideoHomeData.fromJson(Map<String, dynamic> json) {
    List<Map<String, dynamic>> parseMapList(dynamic v) {
      final list = v is List ? v : const <dynamic>[];
      return list
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList(growable: false);
    }

    List<VideoHomeItemBean> parseList(dynamic v) {
      final list = v is List ? v : const <dynamic>[];
      return list
          .whereType<Map>()
          .map((e) => VideoHomeItemBean.fromJson(e.cast<String, dynamic>()))
          .where((e) => e.id > 0)
          .toList();
    }

    final groupRaw = json['recentAddByLib'] ?? json['recent_add_by_lib'];
    final groups = groupRaw is List ? groupRaw : const <dynamic>[];

    return VideoHomeData(
      sourceList: parseMapList(json['sourceList'] ?? json['source_list']),
      recommend: parseList(json['recommend']),
      recentPlay: parseList(json['recentPlay'] ?? json['recent_play']),
      recentAddByLib: groups
          .whereType<Map>()
          .map((e) => VideoHomeLibraryGroup.fromJson(e.cast<String, dynamic>()))
          .where((e) => e.libraryId > 0 && e.items.isNotEmpty)
          .toList(),
    );
  }
}

/// 主页上一个影视库分类的最近添加分组
class VideoHomeLibraryGroup {
  final int libraryId;
  final String libraryName;
  final String libType;
  final List<VideoHomeItemBean> items;

  /// 是否在影视主页显示该库分类（服务端按show_in_home=1 过滤）
  final bool showInHome;

  const VideoHomeLibraryGroup({
    required this.libraryId,
    required this.libraryName,
    required this.libType,
    required this.items,
    this.showInHome = true,
  });

  factory VideoHomeLibraryGroup.fromJson(Map<String, dynamic> json) {
    int asInt(dynamic v) =>
        v is num ? v.toInt() : int.tryParse(v?.toString() ?? '') ?? 0;

    final itemsRaw = json['items'];
    final items = (itemsRaw is List ? itemsRaw : const <dynamic>[])
        .whereType<Map>()
        .map((e) => VideoHomeItemBean.fromJson(e.cast<String, dynamic>()))
        .where((e) => e.id > 0)
        .toList();

    // ⭐ 服务端已按 show_in_home=1 过滤；这里再兜一层，
    // 避免刚关掉开关时主页还因缓存显示出旧分组（2026-10-09）。
    final showRaw = json['showInHome'] ?? json['show_in_home'];
    final showInHome = showRaw == null
        ? true
        : (showRaw == true || showRaw == 1 || showRaw == '1');

    return VideoHomeLibraryGroup(
      libraryId: asInt(json['libraryId'] ?? json['library_id']),
      libraryName:
          (json['libraryName'] ?? json['library_name'] ?? '').toString(),
      libType: (json['libType'] ?? json['lib_type'] ?? 'movie').toString(),
      items: items,
      showInHome: showInHome,
    );
  }

  /// ⭐ 客户端兜底过滤：丢掉没开「在主页显示」的分组。
  /// 服务端已过滤，这里防的是缓存/竞态；逻辑单点维护，别在各 view 里各写一遍。
  static List<VideoHomeLibraryGroup> filterHomeVisible(
    List<VideoHomeLibraryGroup> groups,
  ) {
    return groups
        .where((g) => g.showInHome && g.libraryId > 0 && g.items.isNotEmpty)
        .toList(growable: false);
  }
}
