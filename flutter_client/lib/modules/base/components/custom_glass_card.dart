import 'package:flutter/material.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/custom_colors.dart';

/// 扁平卡片：纯色背景 + 0.5px 细边框，**无阴影、无毛玻璃**
/// Windows 风格：直角（radius 4）、不投影、靠边框而不是阴影分层。
class CustomGlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final BoxBorder? border;
  final double borderRadius;

  /// 保留以兼容旧调用点，但**扁平卡片不再做模糊**，值被忽略
  final double blur;

  /// 保留以兼容旧调用点，但**扁平卡片始终不透明**，值被忽略
  final double opacity;

  final VoidCallback? onTap;

  const CustomGlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpace.page),
    this.margin,
    this.border,
    this.borderRadius = 4.0,
    this.blur = 0.0,
    this.opacity = 1.0,
    this.onTap,
  });

  /// 细边框：走主题的 hairlineBorderColor（浅色中性灰 / 深色半透白）
  Border _defaultBorder(ThemeData theme) {
    final custom = theme.extension<CustomColors>();
    return Border.all(
      color: custom?.hairlineBorderColor ?? const Color(0x1F000000),
      width: 0.5,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radius = BorderRadius.circular(borderRadius);

    final content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: radius,
        border: border ?? _defaultBorder(theme),
      ),
      child: child,
    );

    Widget card = content;

    if (onTap != null) {
      card = Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: content,
        ),
      );
    }

    if (margin != null) {
      return Padding(padding: margin!, child: card);
    }

    return card;
  }
}