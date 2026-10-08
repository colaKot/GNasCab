import 'dart:io';

import 'sync_models.dart';

class SyncScanResult {
  final List<LocalFileEntry> files;
  final int skipped;
  final bool truncated;

  const SyncScanResult({
    required this.files,
    required this.skipped,
    required this.truncated,
  });
}

/// 本地目录扫描器
///
/// 过滤规则与服务端 syncUtil.isExcluded 保持同一套语义，
/// 客户端先过滤可以减少上报体积，服务端仍会兜底过滤一次。
class SyncLocalScanner {
  /// 系统始终过滤的扩展名
  static const List<String> systemExcludedExtensions = ['tmp', 'temp'];

  /// 系统始终过滤的文件名
  static const List<String> systemExcludedNames = [
    '.DS_Store',
    'Thumbs.db',
    'desktop.ini',
  ];

  static int unitToBytes(int value, String unit) {
    final idx = kSizeUnits.indexOf(unit.toUpperCase());
    if (idx < 0) return value;
    var result = value;
    for (var i = 0; i < idx; i++) {
      result *= 1024;
    }
    return result;
  }

  /// 是否应被过滤（true 表示排除）
  static bool isExcluded(String relPath, int size, SyncFilterConfig filter) {
    final rel = relPath.replaceAll('\\', '/');
    if (rel.isEmpty) return false;

    final segments = rel.split('/').where((e) => e.isNotEmpty).toList();
    if (segments.isEmpty) return false;
    final baseName = segments.last;
    final lowerBase = baseName.toLowerCase();

    if (systemExcludedNames.contains(lowerBase)) return true;

    final dotIndex = lowerBase.lastIndexOf('.');
    final ext = dotIndex > 0 ? lowerBase.substring(dotIndex + 1) : '';
    if (ext.isNotEmpty && systemExcludedExtensions.contains(ext)) return true;

    if (filter.excludeHidden) {
      final hasHidden = segments.any(
        (seg) => seg.startsWith('.') && seg != '.' && seg != '..',
      );
      if (hasHidden) return true;
    }

    if (filter.excludeExtensionEnabled &&
        ext.isNotEmpty &&
        filter.excludeExtensions.contains(ext)) {
      return true;
    }

    if (size > 0) {
      if (filter.excludeSmallEnabled) {
        final min = unitToBytes(filter.excludeSmallSize, filter.excludeSmallUnit);
        if (min > 0 && size < min) return true;
      }
      if (filter.excludeLargeEnabled) {
        final max = unitToBytes(filter.excludeLargeSize, filter.excludeLargeUnit);
        if (max > 0 && size > max) return true;
      }
    }

    return false;
  }

  /// 递归扫描目录，返回相对路径为 POSIX 风格的文件清单
  static Future<SyncScanResult> scan(
    String rootDir,
    SyncFilterConfig filter, {
    int maxFiles = 200000,
    int maxDepth = 64,
  }) async {
    final files = <LocalFileEntry>[];
    var skipped = 0;
    var truncated = false;

    final root = Directory(rootDir);
    if (!await root.exists()) {
      return const SyncScanResult(files: [], skipped: 0, truncated: false);
    }

    Future<void> walk(Directory dir, String prefix, int depth) async {
      if (truncated) return;
      if (depth > maxDepth) {
        skipped++;
        return;
      }

      List<FileSystemEntity> entries;
      try {
        entries = await dir.list(followLinks: false).toList();
      } catch (e) {
        skipped++;
        return;
      }

      for (final entity in entries) {
        if (truncated) return;
        final safeName = entity.path.split(RegExp(r'[\\/]')).last;
        if (safeName.isEmpty) {
          skipped++;
          continue;
        }
        final rel = prefix.isEmpty ? safeName : '$prefix/$safeName';

        if (entity is Directory) {
          if (isExcluded(rel, 0, filter)) {
            skipped++;
            continue;
          }
          await walk(entity, rel, depth + 1);
          continue;
        }

        if (entity is! File) {
          skipped++;
          continue;
        }

        FileStat stat;
        try {
          stat = await entity.stat();
        } catch (e) {
          skipped++;
          continue;
        }

        final size = stat.size;
        if (isExcluded(rel, size, filter)) {
          skipped++;
          continue;
        }

        if (files.length >= maxFiles) {
          truncated = true;
          return;
        }

        files.add(LocalFileEntry(
          relPath: rel,
          size: size,
          mtimeMs: stat.modified.millisecondsSinceEpoch,
        ));
      }
    }

    await walk(root, '', 0);
    return SyncScanResult(files: files, skipped: skipped, truncated: truncated);
  }
}
