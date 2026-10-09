import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';

/// 单套配色的元数据（展示名 + 预览色板）
class AppColorScheme {
  final FlexScheme scheme;
  final String labelKey;

  /// 预览色板：主色、辅色、表面色（用于设置页的小圆点预览）
  final List<Color> preview;

  const AppColorScheme({
    required this.scheme,
    required this.labelKey,
    required this.preview,
  });
}

/// 可选配色方案登记表（2026-10-08）
///
/// ⭐ **为什么不用全部 67 套**：flex 内置 67 个 `FlexScheme`，但很多是同色系微调
/// （如 `blue`/`brandBlue`/`deepBlue`/`indigo`/`indigoM3`/`blueM3` 六套都是蓝），
/// 全列出来设置页会变成调色盘，反而不像「主题」。这里精选 **24 套**
/// 覆盖冷/暖/明/暗/中性/高饱和，够用且好选。
///
/// ⭐ 挑色原则：色相分散、明度层次清楚、名字好记。
/// `shad*` 系列是 shadcn 风格的中性色，最「素」；
/// `*M3` 系列饱和度高，最「艳」。
class AppColorSchemes {
  const AppColorSchemes._();

  /// ⭐ 默认配色（也是 2026-10-08 换肤落地时选的那套）
  static const FlexScheme defaultScheme = FlexScheme.shadBlue;

  /// 全部可选配色。**顺序即设置页展示顺序**，按色相排的，不是字母序。
  static const List<AppColorScheme> all = [
    // ── 冷色（蓝 / 青）──
    AppColorScheme(
      scheme: FlexScheme.shadBlue,
      labelKey: 'theme_scheme_shad_blue',
      preview: [Color(0xFF3B82F6), Color(0xFF60A5FA), Color(0xFFF1F5F9)],
    ),
    AppColorScheme(
      scheme: FlexScheme.blue,
      labelKey: 'theme_scheme_blue',
      preview: [Color(0xFF2196F3), Color(0xFF64B5F6), Color(0xFFF3F8FD)],
    ),
    AppColorScheme(
      scheme: FlexScheme.deepBlue,
      labelKey: 'theme_scheme_deep_blue',
      preview: [Color(0xFF1565C0), Color(0xFF42A5F5), Color(0xFFEDF3FA)],
    ),
    AppColorScheme(
      scheme: FlexScheme.bahamaBlue,
      labelKey: 'theme_scheme_bahama_blue',
      preview: [Color(0xFF00A9CE), Color(0xFF4DD0E1), Color(0xFFE6F9FC)],
    ),
    AppColorScheme(
      scheme: FlexScheme.hippieBlue,
      labelKey: 'theme_scheme_hippie_blue',
      preview: [Color(0xFF386FA4), Color(0xFF6FA8C9), Color(0xFFEFF6F9)],
    ),
    AppColorScheme(
      scheme: FlexScheme.outerSpace,
      labelKey: 'theme_scheme_outer_space',
      preview: [Color(0xFF3F51B5), Color(0xFF7986CB), Color(0xFFF0F1FA)],
    ),
    AppColorScheme(
      scheme: FlexScheme.blueWhale,
      labelKey: 'theme_scheme_blue_whale',
      preview: [Color(0xFF1E88E5), Color(0xFF64B5F6), Color(0xFF0F2027)],
    ),

    // ── 绿/ 青绿──
    AppColorScheme(
      scheme: FlexScheme.shadGreen,
      labelKey: 'theme_scheme_shad_green',
      preview: [Color(0xFF10B981), Color(0xFF6EE7B7), Color(0xFFF3FBF7)],
    ),
    AppColorScheme(
      scheme: FlexScheme.green,
      labelKey: 'theme_scheme_green',
      preview: [Color(0xFF4CAF50), Color(0xFF81C784), Color(0xFFF2F9F3)],
    ),
    AppColorScheme(
      scheme: FlexScheme.wasabi,
      labelKey: 'theme_scheme_wasabi',
      preview: [Color(0xFF7CB342), Color(0xFFAED581), Color(0xFFF5F9EF)],
    ),
    AppColorScheme(
      scheme: FlexScheme.jungle,
      labelKey: 'theme_scheme_jungle',
      preview: [Color(0xFF2E7D32), Color(0xFF66BB6A), Color(0xFFF1F8F2)],
    ),
    AppColorScheme(
      scheme: FlexScheme.mallardGreen,
      labelKey: 'theme_scheme_mallard_green',
      preview: [Color(0xFF00897B), Color(0xFF4DB6AC), Color(0xFFEAF6F5)],
    ),

    // ── 紫 / 粉 ──
    AppColorScheme(
      scheme: FlexScheme.deepPurple,
      labelKey: 'theme_scheme_deep_purple',
      preview: [Color(0xFF5E35B1), Color(0xFF9575CD), Color(0xFFF3F0FB)],
    ),
    AppColorScheme(
      scheme: FlexScheme.shadViolet,
      labelKey: 'theme_scheme_shad_violet',
      preview: [Color(0xFF8B5CF6), Color(0xFFC4B5FD), Color(0xFFF6F4FE)],
    ),
    AppColorScheme(
      scheme: FlexScheme.indigo,
      labelKey: 'theme_scheme_indigo',
      preview: [Color(0xFF3F51B5), Color(0xFF9FA8DA), Color(0xFFEEF0FA)],
    ),
    AppColorScheme(
      scheme: FlexScheme.pinkM3,
      labelKey: 'theme_scheme_pink_m3',
      preview: [Color(0xFFD81B60), Color(0xFFF06292), Color(0xFFFDF0F5)],
    ),
    AppColorScheme(
      scheme: FlexScheme.sakura,
      labelKey: 'theme_scheme_sakura',
      preview: [Color(0xFFEF6C9B), Color(0xFFF5A8C4), Color(0xFFFDF2F6)],
    ),

    // ── 暖色（橙 / 红 / 黄）──
    AppColorScheme(
      scheme: FlexScheme.mango,
      labelKey: 'theme_scheme_mango',
      preview: [Color(0xFFFF9800), Color(0xFFFFB74D), Color(0xFFFFF8F0)],
    ),
    AppColorScheme(
      scheme: FlexScheme.shadOrange,
      labelKey: 'theme_scheme_shad_orange',
      preview: [Color(0xFFF97316), Color(0xFFFB923C), Color(0xFFFFF7ED)],
    ),
    AppColorScheme(
      scheme: FlexScheme.amber,
      labelKey: 'theme_scheme_amber',
      preview: [Color(0xFFFFB300), Color(0xFFFFCA28), Color(0xFFFFF9EC)],
    ),
    AppColorScheme(
      scheme: FlexScheme.mandyRed,
      labelKey: 'theme_scheme_mandy_red',
      preview: [Color(0xFFFF5252), Color(0xFFFF8A80), Color(0xFFFFF1F1)],
    ),

    // ── 中性 / 素色 ──
    AppColorScheme(
      scheme: FlexScheme.shadGray,
      labelKey: 'theme_scheme_shad_gray',
      preview: [Color(0xFF6B7280), Color(0xFF9CA3AF), Color(0xFFF5F5F5)],
    ),
    AppColorScheme(
      scheme: FlexScheme.shadSlate,
      labelKey: 'theme_scheme_shad_slate',
      preview: [Color(0xFF475569), Color(0xFF94A3B8), Color(0xFFF4F6F8)],
    ),
    AppColorScheme(
      scheme: FlexScheme.greys,
      labelKey: 'theme_scheme_greys',
      preview: [Color(0xFF616161), Color(0xFF9E9E9E), Color(0xFFF5F5F5)],
    ),
    AppColorScheme(
      scheme: FlexScheme.sepia,
      labelKey: 'theme_scheme_sepia',
      preview: [Color(0xFF8D6E63), Color(0xFFBCAAA4), Color(0xFFF7F3F1)],
    ),
  ];

  /// 按枚举值查元数据；不在表里（将来 flex 加了新配色）时返回 null。
  static AppColorScheme? byScheme(FlexScheme s) {
    for (final e in all) {
      if (e.scheme == s) return e;
    }
    return null;
  }

  /// 枚举名 → 元数据。用于从 SharedPreferences 读回字符串。
  static AppColorScheme? byName(String name) {
    for (final e in all) {
      if (e.scheme.name == name) return e;
    }
    return null;
  }
}