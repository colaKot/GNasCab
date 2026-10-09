import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_skin.dart';
import '../../../core/theme/skin_presets.dart';

/// 自定义开关组件（2026-10-09 换肤：跟随 [AppSkin.switchStyle]）
///
/// 三种造型：
/// - [AppSwitchStyle.material]：Material 3 药丸开关（默认）
/// - [AppSwitchStyle.cupertino]：iOS 圆形开关
/// - [AppSwitchStyle.square]：自绘方形紧凑开关
///
/// ⚠️ 只改**造型**，颜色一律从当前 ColorScheme / 传入的覆盖色派生 ⇒ 换配色自动跟随。
class CustomSwitch extends StatelessWidget {
  const CustomSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.activeColor,
    this.activeTrackColor,
    this.inactiveThumbColor,
    this.inactiveTrackColor,
    this.materialTapTargetSize,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final Color? activeColor;
  final Color? activeTrackColor;
  final Color? inactiveThumbColor;
  final Color? inactiveTrackColor;
  final MaterialTapTargetSize? materialTapTargetSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final skin = theme.extension<AppSkin>() ?? SkinPresets.defaultSkin;

    final active = activeColor ?? theme.colorScheme.primary;
    final activeTrack =
        activeTrackColor ?? theme.colorScheme.primary.withValues(alpha: 0.35);
    final inactiveThumb =
        inactiveThumbColor ??
        theme.colorScheme.outline.withValues(alpha: 0.9);
    final inactiveTrack =
        inactiveTrackColor ??
        theme.colorScheme.outline.withValues(alpha: 0.25);

    switch (skin.switchStyle) {
      case AppSwitchStyle.cupertino:
        return CupertinoSwitch(
          value: value,
          onChanged: onChanged,
          activeTrackColor: active,
          inactiveTrackColor: inactiveTrack,
        );
      case AppSwitchStyle.square:
        return _SquareSwitch(
          value: value,
          onChanged: onChanged,
          activeColor: active,
          activeTrackColor: activeTrack,
          inactiveThumbColor: inactiveThumb,
          inactiveTrackColor: inactiveTrack,
        );
      case AppSwitchStyle.material:
        return Transform.scale(
          scale: 0.9,
          child: Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: active,
            activeTrackColor: activeTrack,
            inactiveThumbColor: inactiveThumb,
            inactiveTrackColor: inactiveTrack,
            materialTapTargetSize:
                materialTapTargetSize ?? MaterialTapTargetSize.shrinkWrap,
          ),
        );
    }
  }
}

/// 方形紧凑开关（自绘）。轨道为小圆角矩形，滑块为方块。
class _SquareSwitch extends StatelessWidget {
  const _SquareSwitch({
    required this.value,
    required this.onChanged,
    required this.activeColor,
    required this.activeTrackColor,
    required this.inactiveThumbColor,
    required this.inactiveTrackColor,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final Color activeColor;
  final Color activeTrackColor;
  final Color inactiveThumbColor;
  final Color inactiveTrackColor;

  static const double _width = 40;
  static const double _height = 22;
  // ⚠️ Container 会把 decoration.border 的宽度叠加到 padding 上，
  // 所以显式 padding 取 2（+ 1px 边框 = 有效 3），保证 16 的滑块正好放下。
  static const double _pad = 2;
  static const double _thumb = 16;

  @override
  Widget build(BuildContext context) {
    final disabled = onChanged == null;
    final trackColor = value ? activeTrackColor : inactiveTrackColor;
    final thumbColor = value ? activeColor : inactiveThumbColor;

    return Semantics(
      toggled: value,
      enabled: !disabled,
      child: GestureDetector(
        onTap: disabled ? null : () => onChanged!(!value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          width: _width,
          height: _height,
          padding: const EdgeInsets.all(_pad),
          decoration: BoxDecoration(
            color: disabled
                ? trackColor.withValues(alpha: 0.5)
                : trackColor,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: thumbColor.withValues(alpha: 0.5),
              width: 1,
            ),
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: _thumb,
              height: _thumb,
              decoration: BoxDecoration(
                color: disabled ? thumbColor.withValues(alpha: 0.6) : thumbColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}