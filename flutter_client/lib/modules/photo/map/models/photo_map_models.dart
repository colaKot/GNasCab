class PhotoMapTileServer {
  final String name;
  final String server;
  final String coordinate;
  final int maxLevel;
  final bool isDefault;
  final bool isCustom;
  final bool isCurrent;

  const PhotoMapTileServer({
    required this.name,
    required this.server,
    required this.coordinate,
    required this.maxLevel,
    required this.isDefault,
    required this.isCustom,
    required this.isCurrent,
  });

  factory PhotoMapTileServer.fromJson(Map<String, dynamic> json) {
    return PhotoMapTileServer(
      name: (json['name'] ?? '').toString(),
      server: (json['server'] ?? '').toString(),
      coordinate: (json['coordinate'] ?? 'WGS-84').toString(),
      maxLevel: int.tryParse((json['maxLevel'] ?? 18).toString()) ?? 18,
      isDefault: json['isDefault'] == true || json['isDefault'] == 1,
      isCustom: json['isCustom'] == true || json['isCustom'] == 1,
      isCurrent: json['current'] == true || json['current'] == 1,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'server': server,
      'coordinate': coordinate,
      'maxLevel': maxLevel,
      'isDefault': isDefault ? 1 : 0,
    };
  }
}

class PhotoMapZoomInfo {
  final int minZoom;
  final int maxZoom;

  const PhotoMapZoomInfo({required this.minZoom, required this.maxZoom});

  factory PhotoMapZoomInfo.fromJson(Map<String, dynamic> json) {
    return PhotoMapZoomInfo(
      minZoom: int.tryParse((json['minZoom'] ?? 2).toString()) ?? 2,
      maxZoom: int.tryParse((json['maxZoom'] ?? 18).toString()) ?? 18,
    );
  }
}

class PhotoMapIndexItem {
  final int id;

  /// 代表照片坐标（该网格内 id 最大的一张）。
  /// 优先用 [cellLat]/[cellLng]（网格中心），为空才回退到这里的原始坐标。
  final double latitude;
  final double longitude;

  /// 该 marker 代表的几何中心（服务端算好的 geohash 格心）。
  /// 落在格心而不是某张照片上，缩放换挡时位置才不会跳。
  final double? cellLat;
  final double? cellLng;

  /// ⭐ 该网格内的照片数量。>1 表示这是一个聚合点，UI 应显示数字角标。
  /// 之前服务端根本没返回这个字段，marker 也无法区分「单张」和「一簇」。
  /// 声明成可空：老服务端响应/ 缓存数据里没有这个 key。
  final int? photoCount;

  /// ⭐ 该 marker 的 geohash 精度档位（2~6，null/0 = 未知）。
  /// 点开反查时必须用同一档位，否则会出现「marker 代表很大范围、点开只列很少照片」。
  final int? cellPrecision;

  final String? geohash;
  final int? originalTime;
  final String? fullpath;
  final String? type;
  final num? duration;

  const PhotoMapIndexItem({
    required this.id,
    required this.latitude,
    required this.longitude,
    this.cellLat,
    this.cellLng,
    this.photoCount,
    this.cellPrecision,
    this.geohash,
    this.originalTime,
    this.fullpath,
    this.type,
    this.duration,
  });

  /// 是否为聚合点（含多张照片）。字段缺失时按单张处理。
  bool get isCluster => (photoCount ?? 1) > 1;

  factory PhotoMapIndexItem.fromJson(Map<String, dynamic> json) {
    final count = int.tryParse((json['photo_count'] ?? 1).toString()) ?? 1;
    final precision = int.tryParse((json['cell_precision'] ?? 0).toString()) ?? 0;
    return PhotoMapIndexItem(
      id: int.tryParse((json['id'] ?? 0).toString()) ?? 0,
      latitude: double.tryParse((json['latitude'] ?? 0).toString()) ?? 0,
      longitude: double.tryParse((json['longitude'] ?? 0).toString()) ?? 0,
      cellLat: double.tryParse((json['cell_lat'] ?? '').toString()),
      cellLng: double.tryParse((json['cell_lng'] ?? '').toString()),
      photoCount: count > 0 ? count : 1,
      // 0 / 解析失败都视为「未知档位」，由调用方回退到旧的 nearbyRangeKm 逻辑
      cellPrecision: precision >= 2 && precision <= 6 ? precision : null,
      geohash: json['geohash']?.toString(),
      originalTime: int.tryParse((json['original_time'] ?? '').toString()),
      fullpath: json['fullpath']?.toString(),
      type: json['type']?.toString(),
      duration: json['duration'] as num?,
    );
  }
}
