import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'app_color_schemes.dart';
import 'app_tokens.dart';
import 'custom_colors.dart';

/// ⭐⭐ 暗色主题构建入口（2026-10-08 从常量改为函数，支撑设置页运行时切配色）
///
/// 配套 [buildLightTheme]：同一个 [scheme] 同时决定亮/暗两套，
/// flex 会自动配对（不是简单反色，暗色里强调色更亮、surface 带主色调）。
///
/// ⚠️ 与亮色侧同样的坑：`CustomColors` 必须从当前配色的 ColorScheme 派生，
/// 否则换配色后暗色侧栏/卡片还是死灰。
ThemeData buildDarkTheme(FlexScheme scheme) {
  final base = FlexThemeData.dark(
    scheme: scheme,
    useMaterial3: true,
    appBarElevation: 0,
    // 关掉 M3 色调叠加层，保持纯色分层
    applyElevationOverlayColor: false,
    subThemesData: const FlexSubThemesData(
      defaultRadius: AppRadius.control,
      thinBorderWidth: 1,
    ),
  );
  final cs = base.colorScheme;
  return base.copyWith(
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
    ],
  );
}

/// 默认暗色主题（`AppColorSchemes.defaultScheme`）。
/// 运行时切换请走 [buildDarkTheme]。
final ThemeData darkTheme = buildDarkTheme(AppColorSchemes.defaultScheme);