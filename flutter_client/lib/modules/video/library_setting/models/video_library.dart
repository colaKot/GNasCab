import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// 影视库类型（创建后不可修改）
/// movie 电影 / tv 影视剧 / image 图片 / mixed 图片与影视混合
const List<String> kVideoLibTypes = <String>['movie', 'tv', 'image', 'mixed'];

class VideoLibrary {
  final int id;
  final String name;
  final String nameKey;
  final String libType;
  final bool isDefault;
  final int sort;
  final int sourceCount;
  final int movieCount;
  final int tvCount;
  final int imageCount;
  final int totalCount;

  const VideoLibrary({
    required this.id,
    required this.name,
    required this.nameKey,
    required this.libType,
    required this.isDefault,
    required this.sort,
    required this.sourceCount,
    required this.movieCount,
    required this.tvCount,
    required this.imageCount,
    required this.totalCount,
  });

  /// 内置库（未改名时）优先用多语言名，改名后 name_key 置空则用用户填的名字
  String get displayName {
    final k = nameKey.trim();
    if (k.isNotEmpty) {
      final translated = k.tr;
      if (translated.isNotEmpty && translated != k) return translated;
    }
    final n = name.trim();
    if (n.isNotEmpty) return n;
    return k;
  }

  bool get isImageOnly => libType == 'image';

  /// 图片与影视混合：列表里同时有图片和视频
  bool get isMixed => libType == 'mixed';

  /// 图片库和混合库都用「网格 + 竖向全屏浏览」的展示方式
  bool get isMediaGridLib => isImageOnly || isMixed;

  bool get isVideoLib => libType == 'movie' || libType == 'tv';

  factory VideoLibrary.fromJson(Map<String, dynamic> json) {
    final countsRaw = json['counts'];
    final counts = countsRaw is Map
        ? countsRaw.cast<String, dynamic>()
        : const <String, dynamic>{};
    int asInt(dynamic v) =>
        v is num ? v.toInt() : int.tryParse(v?.toString() ?? '') ?? 0;

    final isDefaultRaw = json['is_default'];
    final isDefault =
        isDefaultRaw == true || isDefaultRaw == 1 || isDefaultRaw == '1';

    return VideoLibrary(
      id: asInt(json['id']),
      name: (json['name']?.toString() ?? '').trim(),
      nameKey: (json['name_key']?.toString() ?? '').trim(),
      libType: (json['lib_type']?.toString() ?? 'movie').trim(),
      isDefault: isDefault,
      sort: asInt(json['sort']),
      sourceCount: asInt(json['source_count']),
      movieCount: asInt(counts['movie']),
      tvCount: asInt(counts['tv']),
      imageCount: asInt(counts['image']),
      totalCount: asInt(counts['total']),
    );
  }
}

/// 影视库类型的展示名与图标由 UI 层按 key 翻译：[libTypeLabelKey]
String libTypeLabelKey(String libType) {
  switch (libType) {
    case 'tv':
      return 'video_library_type_tv';
    case 'image':
      return 'video_library_type_image';
    case 'mixed':
      return 'video_library_type_mixed';
    case 'movie':
    default:
      return 'video_library_type_movie';
  }
}

/// 左侧栏栏目图标
IconData libTypeIcon(String libType) {
  switch (libType) {
    case 'tv':
      return Icons.tv_outlined;
    case 'image':
      return Icons.image_outlined;
    case 'mixed':
      return Icons.collections_outlined;
    case 'movie':
    default:
      return Icons.movie_filter_outlined;
  }
}
