import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'app_skin.dart';
import 'dark_theme.dart';
import 'light_theme.dart';
import 'skin_presets.dart';
import 'theme_manager.dart';

/// ⭐⭐ 主题应用入口（2026-10-08 新增，2026-10-09 扩展为「换肤」）
///
/// **为什么要单独抽一个 service**：`lightTheme` / `darkTheme` 现在是
/// 「按 [FlexScheme] + [AppSkin] 构建」的了，而设置页要**运行时**切换配色 / 皮肤 /
/// 字体。启动首帧（`main.dart`）和设置页切换必须走**同一套逻辑**，
/// 否则会出现「启动读的是 A、设置页切成了 B，重启又变回 A」这类不一致。
///
/// 三条正交的轴：**配色方案**（颜色） × **外观皮肤**（窗口/控件造型） × **字体**。
/// 全部经由 [_refresh] 统一重刷，无需重启。
///
/// 用法：
/// ```dart
/// await ThemeApplyService.instance.applyScheme(FlexScheme.mandyRed);
/// await ThemeApplyService.instance.applySkin(AppSkinId.macos);
/// await ThemeApplyService.instance.applyMode(ThemeMode.dark);
/// await ThemeApplyService.instance.applyFontFamily('RobotoMono');
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

  /// 当前皮肤（读持久化，读不到回默认）
  AppSkin currentSkin() =>
      SkinPresets.byId(ThemeManager().getSkinId()).skin;

  /// 构建亮色主题（带滚动条设置）
  ThemeData lightFor(
    FlexScheme scheme, {
    AppSkin? skin,
    String? fontFamily,
  }) {
    final sk = skin ?? currentSkin();
    final ff = fontFamily ?? ThemeManager().getFontFamily();
    final t = buildLightTheme(scheme, skin: sk, fontFamily: ff);
    return _withScrollbar(t, isDark: false);
  }

  /// 构建暗色主题（带滚动条设置）
  ThemeData darkFor(
    FlexScheme scheme, {
    AppSkin? skin,
    String? fontFamily,
  }) {
    final sk = skin ?? currentSkin();
    final ff = fontFamily ?? ThemeManager().getFontFamily();
    final t = buildDarkTheme(scheme, skin: sk, fontFamily: ff);
    return _withScrollbar(t, isDark: true);
  }

  /// 认证 / 登录 / 服务器列表等**登录前**页面的主题。
  ///
  /// ⚠️⚠️ **这里曾经有个 `authTheme()`，2026-10-09 已删除，别再往回加。**
  /// 历史：这些页面以前写死 `Theme(data: darkTheme)`（编译期常量 = 默认 `shadBlue`）
  /// ⇒ 换任何配色登录页都还是那一套蓝。第一次修成 `authTheme()`（= `darkFor(当前配色)`），
  /// 亮度仍固定暗色——因为当时背景是写死的**深蓝色照片**。
  /// 铁柱随后要求「背景也按主题走」，背景已换成 `AuthThemeBackground`（主题派生渐变），
  /// 于是**亮度也必须跟随用户的亮/暗设置**，否则亮色模式会出现深色文字压在深色卡片上。
  ///
  /// ⇒ 结论：登录前页面**不需要任何覆盖**，直接沿用 App 主题即可
  /// （`GetMaterialApp` 已经按当前配色 + 皮肤 + 字体 + `themeMode` 解析好了亮度）。
  /// 各视图里保留的 `Theme(data: Theme.of(context), ...)` 是个**显式 no-op**，
  /// 用来标记「这里不覆盖」并保住原有的 `Builder` 结构。


  ThemeData _withScrollbar(ThemeData t, {required bool isDark}) {
    final thickness = scrollbarThicknessProvider?.call();
    if (thickness == null) return t;
    final base = scrollbarBaseColorOverride?.call(isDark);
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
    _refresh();
  }

  /// ⭐ 切换外观皮肤并持久化（窗口 / 控件造型）。
  Future<void> applySkin(AppSkinId id) async {
    await ThemeManager().saveSkin(id);
    _refresh();
  }

  /// ⭐ 切换界面字体并持久化（null = 系统默认）。
  Future<void> applyFontFamily(String? family) async {
    await ThemeManager().saveFontFamily(family);
    _refresh();
  }

  /// 切换亮/暗/跟随系统并持久化。
  Future<void> applyMode(ThemeMode mode) async {
    await ThemeManager().saveThemeMode(mode);
    _refresh();
  }

  /// 统一重刷：按当前「配色 + 皮肤 + 字体 + 亮暗」现场构建，写入 GetX 的亮/暗两个槽。
  ///
  /// ⚠️ **为什么不用 `Get.changeTheme`**：GetX 的 `setTheme` 只在 `darkTheme` 已非空时
  /// 才按 brightness 分流到暗色槽，而 GetX 自己从不给 `darkTheme` 赋初值 ⇒
  /// 暗色槽会永远停在启动时那一份，「暗色下换配色/皮肤」不生效。
  /// 这里直接写 `Get.rootController` 的 `theme` / `darkTheme`，两套一起刷，
  /// system 模式下跟随系统亮度切换也不会用到旧主题。
  void _refresh() {
    final mode = ThemeManager().getThemeMode();
    final scheme = ThemeManager().getColorScheme();
    final skin = currentSkin();
    final font = ThemeManager().getFontFamily();
    final ctrl = Get.rootController;
    ctrl.theme = lightFor(scheme, skin: skin, fontFamily: font);
    ctrl.darkTheme = darkFor(scheme, skin: skin, fontFamily: font);
    ctrl.setThemeMode(mode);
  }

  /// 启动时读取（`main.dart` 用）
  ({
    ThemeMode mode,
    FlexScheme scheme,
    AppSkin skin,
    String? fontFamily,
  })
  readPersisted() {
    final mgr = ThemeManager();
    return (
      mode: mgr.getThemeMode(),
      scheme: mgr.getColorScheme(),
      skin: currentSkin(),
      fontFamily: mgr.getFontFamily(),
    );
  }
}