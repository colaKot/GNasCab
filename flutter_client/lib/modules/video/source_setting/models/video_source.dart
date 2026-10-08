import 'package:get/get.dart';

class VideoSource {
  final int id;
  final String path;
  final bool exists;
  final String mediaType;
  final int matchNfo;
  final int scanWhenStart;
  final int scanWhenChange;
  final int isShow;
  final String? ctime;
  final int scanInterval;
  final int scanIntervalMs;
  final String? scanIntervalConfig;
  final int lastScanTime;

  /// 所属影视库：创建时选定，之后不可修改
  final int libraryId;
  final String libraryName;
  final String libraryNameKey;
  final String libraryType;
  final bool libraryIsDefault;

  /// 列表里展示的影视库名：内置库走多语言键，改名后 name_key 为空则用名字
  String get libraryDisplayName {
    final k = libraryNameKey.trim();
    if (k.isNotEmpty) {
      final translated = k.tr;
      if (translated.isNotEmpty && translated != k) return translated;
    }
    final n = libraryName.trim();
    if (n.isNotEmpty) return n;
    return k;
  }

  const VideoSource({
    required this.id,
    required this.path,
    required this.exists,
    required this.mediaType,
    required this.matchNfo,
    required this.scanWhenStart,
    required this.scanWhenChange,
    required this.isShow,
    required this.ctime,
    required this.scanInterval,
    required this.scanIntervalMs,
    required this.scanIntervalConfig,
    required this.lastScanTime,
    this.libraryId = 0,
    this.libraryName = '',
    this.libraryNameKey = '',
    this.libraryType = '',
    this.libraryIsDefault = false,
  });

  factory VideoSource.fromJson(Map<String, dynamic> json) {
    final rawDefault = json['library_is_default'];
    return VideoSource(
      id: (json['id'] as num?)?.toInt() ?? 0,
      path: (json['path'] as String?) ?? '',
      exists: (json['exists'] as bool?) ?? true,
      mediaType: (json['media_type'] as String?) ?? '',
      matchNfo: (json['match_nfo'] as num?)?.toInt() ?? 0,
      scanWhenStart: (json['scan_when_start'] as num?)?.toInt() ?? 0,
      scanWhenChange: (json['scan_when_change'] as num?)?.toInt() ?? 1,
      isShow: (json['is_show'] as num?)?.toInt() ?? 1,
      ctime: json['ctime']?.toString(),
      scanInterval: (json['scan_interval'] as num?)?.toInt() ?? 0,
      scanIntervalMs: (json['scan_interval_ms'] as num?)?.toInt() ?? 0,
      scanIntervalConfig: json['scan_interval_config']?.toString(),
      lastScanTime: (json['last_scan_time'] as num?)?.toInt() ?? 0,
      libraryId: (json['library_id'] as num?)?.toInt() ?? 0,
      libraryName: (json['library_name']?.toString() ?? '').trim(),
      libraryNameKey: (json['library_name_key']?.toString() ?? '').trim(),
      libraryType: (json['library_type']?.toString() ?? '').trim(),
      libraryIsDefault:
          rawDefault == true || rawDefault == 1 || rawDefault == '1',
    );
  }

  VideoSource copyWith({
    String? mediaType,
    int? matchNfo,
    int? scanWhenStart,
    int? scanWhenChange,
    int? isShow,
    int? scanInterval,
    int? scanIntervalMs,
    String? scanIntervalConfig,
    int? lastScanTime,
  }) {
    return VideoSource(
      id: id,
      path: path,
      exists: exists,
      mediaType: mediaType ?? this.mediaType,
      matchNfo: matchNfo ?? this.matchNfo,
      scanWhenStart: scanWhenStart ?? this.scanWhenStart,
      scanWhenChange: scanWhenChange ?? this.scanWhenChange,
      isShow: isShow ?? this.isShow,
      ctime: ctime,
      scanInterval: scanInterval ?? this.scanInterval,
      scanIntervalMs: scanIntervalMs ?? this.scanIntervalMs,
      scanIntervalConfig: scanIntervalConfig ?? this.scanIntervalConfig,
      lastScanTime: lastScanTime ?? this.lastScanTime,
      libraryId: libraryId,
      libraryName: libraryName,
      libraryNameKey: libraryNameKey,
      libraryType: libraryType,
      libraryIsDefault: libraryIsDefault,
    );
  }
}
