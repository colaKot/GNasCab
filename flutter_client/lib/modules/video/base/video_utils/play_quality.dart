import 'package:get/get.dart';

/// 「播放画质」档位的**唯一**定义。
///
/// ⚠️ 顺序与命名必须与服务端
/// `electron_server/src/api/modules/video/config/videoConfigController.js` 里的
/// `PLAY_QUALITY_OPTIONS` 完全一致 —— 服务端会按这份白名单校验入库的默认值，
/// 对不上的档位会被判为非法（400）。要增删档位，两边必须同一次改完。
///
/// 键格式固定为 `<分辨率>_<码率>`（如 `1080p_5m`）；`original` 表示原画、不转码。
class PlayQuality {
  const PlayQuality._();

  static const String original = 'original';

  /// 「原画视频 + 仅转音频」：Web 端音轨编码不受支持时使用。
  ///
  /// 视频保持原画不重新编码（服务端 `-c:v copy`），只把音轨转成 AAC，
  /// 避免因为音频问题就把整片降成低码率档位。**不进入 [options]**——
  /// 它不是用户可选画质，只是播放器内部的转码形态。
  static const String originalAudio = 'original_audio';

  static const List<String> options = [
    'original',
    '4k_20m',
    '4k_15m',
    '4k_10m',
    '1080p_8m',
    '1080p_5m',
    '1080p_3m',
    '1080p_2m',
    '720p_3m',
    '720p_2m',
    '720p_1m',
    '480p_1m',
  ];

  /// 档位 → 转码目标宽度。null 表示该档位不限定宽度。
  static const Map<String, int> _widths = {
    '4k': 3840,
    '1080p': 1920,
    '720p': 1280,
    '480p': 854,
  };

  /// 档位 → 界面短标签。original 走多语言，其余是「分辨率 + 码率」，各语言写法一致。
  static const Map<String, String> shortLabels = {
    '4k_20m': '4K 20M',
    '4k_15m': '4K 15M',
    '4k_10m': '4K 10M',
    '1080p_8m': '1080P 8M',
    '1080p_5m': '1080P 5M',
    '1080p_3m': '1080P 3M',
    '1080p_2m': '1080P 2M',
    '720p_3m': '720P 3M',
    '720p_2m': '720P 2M',
    '720p_1m': '720P 1M',
    '480p_1m': '480P 1M',
  };

  static String label(String quality) {
    // 「仅转音频」视频仍是原画，界面沿用「原画」文案，不暴露内部转码形态
    if (quality == original || quality == originalAudio) {
      return 'video_play_quality_original'.tr;
    }
    return shortLabels[quality] ?? quality;
  }

  /// 档位 → 转码目标宽度（发给 transcode 接口的 `width`）。原画/非法档位返回 null。
  static int? widthOf(String quality) {
    if (quality == original || quality == originalAudio) return null;
    final parts = quality.split('_');
    if (parts.length < 2) return null;
    return _widths[parts[0].toLowerCase()];
  }

  /// 档位 → 转码目标码率（bps）。原画/非法档位返回 null。
  ///
  /// 这是发往 `/api/videoPlayer/transcode` 的 `bitrate` 的**唯一**换算处，
  /// 详情抽屉显示「转码码率」时也走这里，避免两处正则各写一份走偏。
  static int? bitrateBpsOf(String quality) {
    if (quality == original || quality == originalAudio) return null;
    final parts = quality.split('_');
    if (parts.length < 2) return null;
    final m = RegExp(r'^(\d+)(m|k)$').firstMatch(parts[1].toLowerCase());
    if (m == null) return null;
    final n = int.tryParse(m.group(1) ?? '');
    if (n == null || n <= 0) return null;
    return m.group(2) == 'm' ? n * 1000000 : n * 1000;
  }

  /// bps → 可读文本。Mbps/kbps 是通用单位，不需要走多语言。
  static String formatBitrate(int bps) {
    if (bps <= 0) return '';
    if (bps >= 1000000) {
      final v = bps / 1000000;
      return '${v.toStringAsFixed(v >= 100 ? 0 : 1)} Mbps';
    }
    return '${(bps / 1000).round()} kbps';
  }
}