import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'app_color_schemes.dart';
import 'app_skin.dart';
import 'custom_colors.dart';
import 'skin_presets.dart';

/// ⭐⭐ 暗色主题构建入口（2026-10-08 从常量改为函数，支撑设置页运行时切配色）
///
/// 配套 [buildLightTheme]：同一个 [scheme] 同时决定亮/暗两套，
/// flex 会自动配对（不是简单反色，暗色里强调色更亮、surface 带主色调）。
///
/// ⭐ 2026-10-09 换肤系统：同样接收 [skin] / [fontFamily]，与亮色侧保持一致。
///
/// ⚠️ 与亮色侧同样的坑：`CustomColors` 必须从当前配色的 ColorScheme 派生，
/// 否则换配色后暗色侧栏/卡片还是死灰。
ThemeData buildDarkTheme(
  FlexScheme scheme, {
  AppSkin? skin,
  String? fontFamily,
}) {
  final sk = skin ?? SkinPresets.defaultSkin;
  final base = FlexThemeData.dark(
    scheme: scheme,
    useMaterial3: true,
    fontFamily: fontFamily,
    appBarElevation: 0,
    // 关掉 M3 色调叠加层，保持纯色分层
    applyElevationOverlayColor: false,
    subThemesData: FlexSubThemesData(
      defaultRadius: sk.controlRadius,
      thinBorderWidth: 1,
    ),
  );
  final cs = base.colorScheme;
  return sk.applyTo(
    base.copyWith(
      scaffoldBackgroundColor: cs.surface,
      extensions: <ThemeExtension<dynamic>>[
        CustomColors(
          nestedCardColor: cs.surfaceContainerLow, // 暗色下"最浅"= surfaceContainerLow
          emptyCardColor: cs.surfaceContainer, // ⚠️ ColorScheme 没有 surfaceContainerLower
          leftTreeBgColor: cs.surfaceContainerHigh,
          mainContentBgColor: cs.surface,
          oprationBarBgColor: cs.surfaceContainerLow,
          hairlineBorderColor: cs.outlineVariant,
        ),
        // ⭐ 外观皮肤（窗口/控件造型）也挂进 extensions，供控件读取
        sk,
      ],
    ),
  );
}

/// 默认暗色主题（`AppColorSchemes.defaultScheme`）。
/// 运行时切换请走 [buildDarkTheme]。
final ThemeData darkTheme = buildDarkTheme(AppColorSchemes.defaultScheme);