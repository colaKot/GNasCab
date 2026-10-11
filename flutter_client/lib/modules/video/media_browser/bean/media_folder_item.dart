import 'package:WaterNasOS/modules/video/base/beans/video_item_bean.dart';

/// 文件夹层级里的一个「子文件夹」条目。
///
/// 由服务端 `POST /api/video/image/folders` 返回 —— 服务端先按目录
/// `GROUP BY path` 把整棵子树压成「一行一目录」，再上卷成直接子文件夹，
/// 所以这里的 `count` 是该文件夹**整棵子树**的量级。
class MediaFolderItem {
  final String name;

  /// 完整绝对路径，原样带回去请求下一层（服务端靠它做越权校验）
  final String path;

  /// 子树的图片 + 视频总数
  final int count;
  final int imageCount;
  final int videoCount;

  /// 封面：服务端从该子树里挑一张图返回，结构与列表项同构；
  /// 纯视频文件夹会是视频条目（前端按 poster/fanart 取图）。
  final VideoHomeItemBean? cover;

  const MediaFolderItem({
    required this.name,
    required this.path,
    required this.count,
    required this.imageCount,
    required this.videoCount,
    this.cover,
  });

  factory MediaFolderItem.fromJson(Map<String, dynamic> json) {
    final rawCover = json['cover'];
    VideoHomeItemBean? cover;
    if (rawCover is Map) {
      try {
        cover = VideoHomeItemBean.fromJson(Map<String, dynamic>.from(rawCover));
      } catch (_) {
        cover = null;
      }
    }
    return MediaFolderItem(
      name: (json['name']?.toString() ?? '').trim(),
      path: (json['path']?.toString() ?? '').trim(),
      count: (json['count'] as num?)?.toInt() ?? 0,
      imageCount: (json['imageCount'] as num?)?.toInt() ?? 0,
      videoCount: (json['videoCount'] as num?)?.toInt() ?? 0,
      cover: cover,
    );
  }
}

/// 面包屑的一段
class MediaFolderSegment {
  final String name;
  final String path;

  const MediaFolderSegment({required this.name, required this.path});

  factory MediaFolderSegment.fromJson(Map<String, dynamic> json) {
    return MediaFolderSegment(
      name: (json['name']?.toString() ?? '').trim(),
      path: (json['path']?.toString() ?? '').trim(),
    );
  }
}

/// 某一个目录的层级信息
class MediaFolderLevel {
  /// 当前目录（空串 = 库根）
  final String path;

  /// 上一级目录；库根 / 来源根为 null（前端据此决定要不要画"返回上一级"）
  final String? parentPath;

  /// 从所属来源根走到当前目录的每一段（库根时为空）
  final List<MediaFolderSegment> segments;

  /// 该库的可见来源根列表
  final List<String> roots;

  /// 直接子文件夹（排除只存在于更深层的目录）
  final List<MediaFolderItem> folders;

  /// 直接躺在**当前目录自身**（不含子目录）里的文件数
  final int selfCount;
  final int selfImageCount;
  final int selfVideoCount;

  bool get hasSubFolders => folders.isNotEmpty;

  const MediaFolderLevel({
    required this.path,
    required this.parentPath,
    required this.segments,
    required this.roots,
    required this.folders,
    required this.selfCount,
    required this.selfImageCount,
    required this.selfVideoCount,
  });

  /// 请求失败 / 非图片库时用的空结果：**hasSubFolders=false** ⇒
  /// 前端会直接退化成「本级文件（瀑布流）」，不会卡在空文件夹页
  factory MediaFolderLevel.empty([String path = '']) {
    return MediaFolderLevel(
      path: path,
      parentPath: null,
      segments: const <MediaFolderSegment>[],
      roots: const <String>[],
      folders: const <MediaFolderItem>[],
      selfCount: 0,
      selfImageCount: 0,
      selfVideoCount: 0,
    );
  }

  factory MediaFolderLevel.fromJson(Map<String, dynamic> json) {
    final rawFolders = json['folders'];
    final folders = <MediaFolderItem>[];
    if (rawFolders is List) {
      for (final e in rawFolders) {
        if (e is Map) {
          folders.add(MediaFolderItem.fromJson(Map<String, dynamic>.from(e)));
        }
      }
    }
    final rawSegments = json['segments'];
    final segments = <MediaFolderSegment>[];
    if (rawSegments is List) {
      for (final e in rawSegments) {
        if (e is Map) {
          segments.add(
            MediaFolderSegment.fromJson(Map<String, dynamic>.from(e)),
          );
        }
      }
    }
    final rawRoots = json['roots'];
    final roots = <String>[];
    if (rawRoots is List) {
      for (final e in rawRoots) {
        final s = e?.toString().trim() ?? '';
        if (s.isNotEmpty) roots.add(s);
      }
    }
    final rawParent = json['parentPath'];
    final parentPath = rawParent?.toString().trim() ?? '';
    return MediaFolderLevel(
      path: (json['path']?.toString() ?? '').trim(),
      parentPath: parentPath.isEmpty ? null : parentPath,
      segments: segments,
      roots: roots,
      folders: folders,
      selfCount: (json['selfCount'] as num?)?.toInt() ?? 0,
      selfImageCount: (json['selfImageCount'] as num?)?.toInt() ?? 0,
      selfVideoCount: (json['selfVideoCount'] as num?)?.toInt() ?? 0,
    );
  }
}
