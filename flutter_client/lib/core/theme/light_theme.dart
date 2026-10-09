import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'app_color_schemes.dart';
import 'app_tokens.dart';
import 'custom_colors.dart';

/// ⭐⭐ 亮色主题构建入口（2026-10-08 从常量改为函数，支撑设置页运行时切配色）
///
/// **为什么从 `final ThemeData lightTheme` 改成函数**：原来是编译期常量，
/// 换配色必须改代码重编译。现在按传入的 [scheme] 现场构建，
/// 设置页选完立刻 `Get.changeTheme(...)` 生效，不用重启。
///
/// **[theme] 统一走 flex_color_scheme 8.4.0**（BSD-3-Clause，商用闭源无限制）：
/// - 配色：`scheme` 参数（67 套内置，登记表见 `AppColorSchemes.all`，精选 24 套）
/// - 组件子主题：`subThemesData` 统一圆角与分隔线，不必逐组件手写
///
/// ⚠️ **CustomColors 的灰阶全部从 `ColorScheme` 派生**，不写死 Windows 灰 ——
/// 否则换了绿色/紫色配色，侧栏还是冷灰，跟主色打架（用户需求：
/// "所有涉及主题的都以主题为主"）。
///
/// ⚠️ flex 8.x 参数名易错（照官方 9.x tutorial 抄会编译失败）：
/// - `defaultRadius` 是 **double?**，不是 Radius
/// - 关色调叠加是 **`applyElevationOverlayColor`**，没有 `elevationOverlayEnabled`
/// - 分隔线宽度是 **`thinBorderWidth`**，没有 `dividerThickness`
ThemeData buildLightTheme(FlexScheme scheme) {
  final base = FlexThemeData.light(
    scheme: scheme,
    useMaterial3: true,
    appBarElevation: 0, // Windows 标题栏不投影
    // 关掉 M3 色调叠加层，保持纯色分层（参数名在 8.x 是 applyElevationOverlayColor）
    applyElevationOverlayColor: false,
    subThemesData: const FlexSubThemesData(
      // 全局圆角统一走 token（控件档 = 4，与 Fluent 对齐）
      defaultRadius: AppRadius.control,
      // Fluent 的分隔线很细
      thinBorderWidth: 1,
    ),
  );
  final cs = base.colorScheme;
  return base.copyWith(
    scaffoldBackgroundColor: cs.surface,
    extensions: <ThemeExtension<dynamic>>[
      // ⚠️ 业务色槽：116 个文件依赖，**只加不改名**。
      // 颜色全部取自当前配色的 ColorScheme ⇒ 换配色自动跟随。
      CustomColors(
        nestedCardColor: cs.surfaceContainerLowest, // 嵌套卡片：最浅
        emptyCardColor: cs.surfaceContainerLow, // 空卡片
        leftTreeBgColor: cs.surfaceContainer, // 左侧栏：比底色略深
        mainContentBgColor: cs.surface, // 主内容
        oprationBarBgColor: cs.surfaceContainerLow, // 操作栏
        hairlineBorderColor: cs.outlineVariant, // 卡片细边框
      ),
    ],
  );
}

/// 默认亮色主题（`AppColorSchemes.defaultScheme`）。
/// 保留这个变量是为了兼容既有引用与「启动时首帧」——
/// 运行时切换请走 [buildLightTheme]。
final ThemeData lightTheme = buildLightTheme(
  AppColorSchemes.defaultScheme,
);