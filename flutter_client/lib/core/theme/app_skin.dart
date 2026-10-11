import 'package:flutter/material.dart';

/// 窗口右上角按钮造型（2026-10-09 换肤系统新增）
///
/// ⚠️ 只改**形状/尺寸**，不改颜色 —— 按钮底色是中性透明色，按亮/暗模式取深淡，
/// 与配色方案无关（2026-10-10：原先的红黄绿语义色已按需求取消）。
enum AppTitleBarButtonStyle {
  /// Windows 11：方形圆角方块（默认，40×40）
  windows,

  /// macOS：圆形
  macos,

  /// 极简：更小更方的方块
  minimal,
}

/// 开关造型
enum AppSwitchStyle {
  /// Material 3（默认）
  material,

  /// iOS 风格（CupertinoSwitch）
  cupertino,

  /// 方形紧凑（自绘）
  square,
}

/// 图标线面风格。仅对走 [AppIcon] 适配层的图标生效（旧图标保持 Material 默认）。
enum AppIconVariant { filled, outlined, rounded }

/// ⭐⭐ 外观皮肤（2026-10-09 新增）—— 与「配色方案」正交的第二条轴。
///
/// **为什么单独抽一层**：现有 `flex_color_scheme` 只管**颜色**（ColorScheme）；
/// 窗口圆角、标题栏高度、右上角按钮造型、控件圆角、开关造型、图标尺寸、字体
/// 这些**结构型**差异无处安放。这里用 `ThemeExtension` 把它们收成一套可切换的皮肤，
/// 颜色仍全部从当前 ColorScheme 派生 ⇒ 皮肤 × 配色 自由组合，互不打架。
///
/// 用法：
/// ```dart
/// final skin = Theme.of(context).extension<AppSkin>() ?? SkinPresets.defaultSkin;
/// borderRadius: BorderRadius.circular(skin.windowRadius)
/// ```
///
/// ⚠️ 默认皮肤（`SkinPresets.windows11`）的取值**必须与换肤前完全一致**，
/// 否则不改设置的老用户会看到默认外观被改掉。
@immutable
class AppSkin extends ThemeExtension<AppSkin> {
  // ────────────── 窗口 ──────────────
  /// 窗口外圆角（PC 虚拟窗口）
  final double windowRadius;

  /// 窗口外边框宽度
  final double windowBorderWidth;

  /// 标题栏（拖拽区）高度，也是各 app 顶栏垂直让位的依据
  final double titleBarHeight;

  // ────────────── 右上角窗口按钮 ──────────────
  final AppTitleBarButtonStyle titleBarButtonStyle;
  final double titleBarButtonWidth;
  final double titleBarButtonHeight;
  final double titleBarButtonSpacing;
  final double titleBarButtonIconSize;

  // ────────────── 控件 ──────────────
  /// 控件圆角：驱动 flex 的 `defaultRadius`（按钮/输入框/卡片/对话框等子主题）
  final double controlRadius;

  /// 主按钮（Elevated / Filled）圆角，供 `CustomButton` 等封装读取
  final double buttonRadius;

  /// 主按钮最小高度
  final double buttonHeight;

  final AppSwitchStyle switchStyle;

  // ────────────── 图标 / 字体 ──────────────
  final AppIconVariant iconVariant;

  /// 全局图标尺寸（写入 IconTheme；24 = Material 默认，等于不改）
  final double iconSize;

  /// 字体族。null = 系统默认；只允许工程已打包的字体（零下载铁律）
  final String? fontFamily;

  const AppSkin({
    required this.windowRadius,
    required this.windowBorderWidth,
    required this.titleBarHeight,
    required this.titleBarButtonStyle,
    required this.titleBarButtonWidth,
    required this.titleBarButtonHeight,
    required this.titleBarButtonSpacing,
    required this.titleBarButtonIconSize,
    required this.controlRadius,
    required this.buttonRadius,
    required this.buttonHeight,
    required this.switchStyle,
    required this.iconVariant,
    required this.iconSize,
    this.fontFamily,
  });

  /// 右上角按钮组占用的总宽度（含右侧留白）。
  /// 各 app 顶栏据此做**水平让位**，见 `PcWindowScope.titleBarControlsWidth`。
  double get titleBarControlsWidth =>
      titleBarButtonWidth * 3 + titleBarButtonSpacing * 2 + 12;

  @override
  AppSkin copyWith({
    double? windowRadius,
    double? windowBorderWidth,
    double? titleBarHeight,
    AppTitleBarButtonStyle? titleBarButtonStyle,
    double? titleBarButtonWidth,
    double? titleBarButtonHeight,
    double? titleBarButtonSpacing,
    double? titleBarButtonIconSize,
    double? controlRadius,
    double? buttonRadius,
    double? buttonHeight,
    AppSwitchStyle? switchStyle,
    AppIconVariant? iconVariant,
    double? iconSize,
    String? fontFamily,
  }) {
    return AppSkin(
      windowRadius: windowRadius ?? this.windowRadius,
      windowBorderWidth: windowBorderWidth ?? this.windowBorderWidth,
      titleBarHeight: titleBarHeight ?? this.titleBarHeight,
      titleBarButtonStyle: titleBarButtonStyle ?? this.titleBarButtonStyle,
      titleBarButtonWidth: titleBarButtonWidth ?? this.titleBarButtonWidth,
      titleBarButtonHeight: titleBarButtonHeight ?? this.titleBarButtonHeight,
      titleBarButtonSpacing: titleBarButtonSpacing ?? this.titleBarButtonSpacing,
      titleBarButtonIconSize:
          titleBarButtonIconSize ?? this.titleBarButtonIconSize,
      controlRadius: controlRadius ?? this.controlRadius,
      buttonRadius: buttonRadius ?? this.buttonRadius,
      buttonHeight: buttonHeight ?? this.buttonHeight,
      switchStyle: switchStyle ?? this.switchStyle,
      iconVariant: iconVariant ?? this.iconVariant,
      iconSize: iconSize ?? this.iconSize,
      fontFamily: fontFamily ?? this.fontFamily,
    );
  }

  @override
  AppSkin lerp(covariant AppSkin? other, double t) {
    if (other == null) return this;
    return AppSkin(
      windowRadius: _lerp(windowRadius, other.windowRadius, t),
      windowBorderWidth: _lerp(windowBorderWidth, other.windowBorderWidth, t),
      titleBarHeight: _lerp(titleBarHeight, other.titleBarHeight, t),
      titleBarButtonStyle: t < 0.5
          ? titleBarButtonStyle
          : other.titleBarButtonStyle,
      titleBarButtonWidth:
          _lerp(titleBarButtonWidth, other.titleBarButtonWidth, t),
      titleBarButtonHeight:
          _lerp(titleBarButtonHeight, other.titleBarButtonHeight, t),
      titleBarButtonSpacing:
          _lerp(titleBarButtonSpacing, other.titleBarButtonSpacing, t),
      titleBarButtonIconSize:
          _lerp(titleBarButtonIconSize, other.titleBarButtonIconSize, t),
      controlRadius: _lerp(controlRadius, other.controlRadius, t),
      buttonRadius: _lerp(buttonRadius, other.buttonRadius, t),
      buttonHeight: _lerp(buttonHeight, other.buttonHeight, t),
      switchStyle: t < 0.5 ? switchStyle : other.switchStyle,
      iconVariant: t < 0.5 ? iconVariant : other.iconVariant,
      iconSize: _lerp(iconSize, other.iconSize, t),
      fontFamily: t < 0.5 ? fontFamily : other.fontFamily,
    );
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  /// 把皮肤里「能由 ThemeData 表达」的部分应用到 [base]。
  ///
  /// ⚠️ 只压**尺寸/形状**，颜色一律沿用 [base] 的 ColorScheme ⇒ 换配色自动跟随。
  /// 开关造型、窗口/标题栏按钮、图标线面风格属于「控件自绘」，不在这里处理。
  ThemeData applyTo(ThemeData base) {
    return base.copyWith(
      iconTheme: base.iconTheme.copyWith(size: iconSize),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: _buttonStyle(base.elevatedButtonTheme.style),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: _buttonStyle(base.filledButtonTheme.style),
      ),
    );
  }

  ButtonStyle _buttonStyle(ButtonStyle? base) {
    final minSize = WidgetStatePropertyAll<Size>(Size(0, buttonHeight));
    if (base == null) return ButtonStyle(minimumSize: minSize);
    return base.copyWith(minimumSize: minSize);
  }
}