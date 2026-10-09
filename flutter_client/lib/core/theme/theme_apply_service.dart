import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'dark_theme.dart';
import 'light_theme.dart';
import 'theme_manager.dart';

/// ⭐⭐ 主题应用入口（2026-10-08 新增）
///
/// **为什么要单独抽一个 service**：`lightTheme` / `darkTheme` 现在是
/// 「按 [FlexScheme] 构建」的了，而设置页要**运行时**切换配色。
/// 启动首帧（`main.dart`）和设置页切换必须走**同一套逻辑**，
/// 否则会出现「启动读的是 A、设置页切成了 B，重启又变回 A」这类不一致。
///
/// 用法：
/// ```dart
/// await ThemeApplyService.instance.applyScheme(FlexScheme.mandyRed);
/// await ThemeApplyService.instance.applyMode(ThemeMode.dark);
/// ```
class ThemeApplyService {
  ThemeApplyService._();

  static final ThemeApplyService instance = ThemeApplyService._();

  /// 用户在设置里调过的滚动条粗细。
  /// ⚠️ 由 `main.dart` 注入；切换配色时必须沿用，否则设置会被重置。
  /// （未注入时返回 null ⇒ 不覆盖滚动条主题）
  static WidgetStateProperty<double>? Function()? scrollbarThicknessProvider;

  /// 用户自定义的滚动条底色（默认取主题 outline，跟随配色）。
  static Color? Function(bool isDark)? scrollbarBaseColorOverride;

  /// 构建亮色主题（带滚动条设置）
  ThemeData lightFor(FlexScheme scheme) {
    final t = buildLightTheme(scheme);
    final thickness = scrollbarThicknessProvider?.call();
    if (thickness == null) return t;
    final base = scrollbarBaseColorOverride?.call(false);
    final colorBase = base ?? t.colorScheme.outline;
    return t.copyWith(
      scrollbarTheme: t.scrollbarTheme.copyWith(
        thickness: thickness,
        thumbColor: _thumbColor(colorBase),
        trackColor: _trackColor(colorBase),
      ),
    );
  }

  /// 构建暗色主题（带滚动条设置）
  ThemeData darkFor(FlexScheme scheme) {
    final t = buildDarkTheme(scheme);
    final thickness = scrollbarThicknessProvider?.call();
    if (thickness == null) return t;
    final base = scrollbarBaseColorOverride?.call(true);
    final colorBase = base ?? t.colorScheme.outline;
    return t.copyWith(
      scrollbarTheme: t.scrollbarTheme.copyWith(
        thickness: thickness,
        thumbColor: _thumbColor(colorBase),
        trackColor: _trackColor(colorBase),
      ),
    );
  }

  WidgetStateProperty<Color> _thumbColor(Color base) {
    return WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.hovered) ||
          states.contains(WidgetState.dragged)) {
        return base.withValues(alpha: 0.8);
      }
      return base.withValues(alpha: 0.3);
    });
  }

  WidgetStateProperty<Color> _trackColor(Color base) {
    return WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.hovered) ||
          states.contains(WidgetState.dragged)) {
        return base.withValues(alpha: 0.3);
      }
      return base.withValues(alpha: 0.1);
    });
  }

  /// ⭐ 切换配色并持久化。设置页用这个。
  Future<void> applyScheme(FlexScheme scheme) async {
    await ThemeManager().saveColorScheme(scheme);
    final mode = ThemeManager().getThemeMode();
    Get.changeTheme(mode == ThemeMode.dark ? darkFor(scheme) : lightFor(scheme));
    Get.changeThemeMode(mode);
  }

  /// 切换亮/暗/跟随系统并持久化。
  Future<void> applyMode(ThemeMode mode) async {
    await ThemeManager().saveThemeMode(mode);
    Get.changeThemeMode(mode);
    // 配色不变，但 system 模式下当前解析出的亮暗可能变了 ⇒ 重刷一次当前主题
    final scheme = ThemeManager().getColorScheme();
    final effective = _effectiveMode(mode);
    Get.changeTheme(effective == ThemeMode.dark ? darkFor(scheme) : lightFor(scheme));
  }

  ThemeMode _effectiveMode(ThemeMode mode) {
    if (mode != ThemeMode.system) return mode;
    return MediaQuery.platformBrightnessOf(Get.context!) == Brightness.dark
        ? ThemeMode.dark
        : ThemeMode.light;
  }

  /// 启动时读取（`main.dart` 用）
  ({ThemeMode mode, FlexScheme scheme}) readPersisted() {
    return (
      mode: ThemeManager().getThemeMode(),
      scheme: ThemeManager().getColorScheme(),
    );
  }
}