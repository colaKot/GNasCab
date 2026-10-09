import 'package:flutter/material.dart';

import '../../../core/theme/app_skin.dart';
import '../../../core/theme/skin_presets.dart';

/// 图标适配层（2026-10-09 换肤）
///
/// 按当前 [AppSkin.iconVariant] 在「实心 / 线性 / 圆角」三种图标里挑一个：
/// - 调用方通过 [outlinedIcon] / [roundedIcon] 提供对应变体；
/// - 没提供就回退到 [icon] 本身（不崩、也不会显示错误图标）。
/// - 尺寸默认取皮肤全局 [AppSkin.iconSize]（显式传 [size] 时以 [size] 为准）。
///
/// ⚠️ 只对**走本组件**的图标生效；直接写 `Icon(...)` 的老代码保持 Material 默认，
/// 但其字号会经 `IconTheme` 统一吃到皮肤值。线/面风格只对本组件生效。
///
/// 用法：
/// ```dart
/// AppIcon(Icons.settings, outlinedIcon: Icons.settings_outlined)
/// ```
class AppIcon extends StatelessWidget {
  const AppIcon(
    this.icon, {
    super.key,
    this.outlinedIcon,
    this.roundedIcon,
    this.size,
    this.color,
    this.semanticLabel,
  });

  final IconData icon;
  final IconData? outlinedIcon;
  final IconData? roundedIcon;
  final double? size;
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final skin =
        Theme.of(context).extension<AppSkin>() ?? SkinPresets.defaultSkin;
    final data = switch (skin.iconVariant) {
      AppIconVariant.outlined => outlinedIcon ?? icon,
      AppIconVariant.rounded => roundedIcon ?? icon,
      AppIconVariant.filled => icon,
    };
    return Icon(
      data,
      size: size ?? skin.iconSize,
      color: color,
      semanticLabel: semanticLabel,
    );
  }
}