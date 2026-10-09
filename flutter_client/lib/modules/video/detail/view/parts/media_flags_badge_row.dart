import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// 影视详情的媒体特性徽章行：4K / 1080P + HDR10 / HDR10+ / HLG / 杜比视界 / 杜比全景声。
///
/// 数据来自 `/video/detail` 的 `media_flags`（服务端按 `file_hash` 关联扫描时写入的
/// ffprobe streams 解析出来的，不需要重扫库）。**不要**在客户端重新判断 HDR/杜比：
/// 判定规则依赖 color_transfer / side_data 等字段，散到多处一定会和扫描端走偏。
///
/// 展示规则：
/// - HDR10+ 与 HDR10 不会同时出现 —— 命中 HDR10+ 就只显示 HDR10+，避免「HDR10+ HDR10」这种冗余组合
/// - 杜比视界与 HDR 互相独立（实测 dv_profile=8 的片子同时带 smpte2084），两者都要标出来
/// - `leadingLabel` 传分辨率文字（如 4K/1080P）时排在最前面；为空则不渲染分辨率
/// - 一项都没命中且 `leadingLabel` 为空时，整行返回空 Widget（不留空白间距）
class MediaFlagsBadgeRow extends StatelessWidget {
  final Map<String, dynamic>? flags;
  final String? leadingLabel;
  final double fontSize;
  final EdgeInsets padding;
  final Color? foreground;
  final Color? background;

  const MediaFlagsBadgeRow({
    super.key,
    this.flags,
    this.leadingLabel,
    this.fontSize = 14,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    this.foreground,
    this.background,
  });

  static bool _on(Map<String, dynamic>? f, String key) =>
      f != null && f[key] == true;

  /// 算出要显示哪些徽章（顺序即展示顺序）。纯函数，视图和「要不要渲染」判断共用同一份逻辑。
  static List<String> labelsFor(
    Map<String, dynamic>? flags, {
    String? leadingLabel,
  }) {
    final labels = <String>[];
    final res = (leadingLabel ?? '').trim();
    if (res.isNotEmpty) labels.add(res);
    if (_on(flags, 'hdr10plus')) {
      labels.add('video_badge_hdr10plus'.tr);
    } else if (_on(flags, 'hdr10')) {
      // HDR10 是通用技术名词，各语言写法一致，不需要多语言键
      labels.add('HDR10');
    }
    if (_on(flags, 'hlg')) labels.add('video_badge_hlg'.tr);
    if (_on(flags, 'dolbyVision')) labels.add('video_badge_dolby_vision'.tr);
    if (_on(flags, 'dolbyAtmos')) labels.add('video_badge_dolby_atmos'.tr);
    return labels;
  }

  /// 是否有任何徽章要显示（含 leadingLabel）。
  static bool willRender(Map<String, dynamic>? flags, {String? leadingLabel}) =>
      labelsFor(flags, leadingLabel: leadingLabel).isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final labels = labelsFor(flags, leadingLabel: leadingLabel);
    if (labels.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final fg = foreground ?? Colors.white;
    final bg = background ?? Colors.black.withValues(alpha: 0.45);

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final label in labels)
          Container(
            padding: padding,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: fg.withValues(alpha: 0.22)),
            ),
            child: Text(
              label,
              style: theme.textTheme.titleSmall?.copyWith(
                color: fg,
                fontWeight: FontWeight.w800,
                fontSize: fontSize,
              ),
            ),
          ),
      ],
    );
  }
}