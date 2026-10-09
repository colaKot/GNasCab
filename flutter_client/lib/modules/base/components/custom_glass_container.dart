import 'package:flutter/material.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/custom_colors.dart';

/// 扁平容器（原苹果风格液态玻璃）：**不透明底色 + 细边框，无模糊无渐变**
/// Windows 风格：直角、靠边框分层。保留 `blur` / `gradient*` 参数以兼容旧调用点（值被忽略）。
class CustomGlassContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final double blur;
  final double borderOpacity;
  final double gradientStartOpacity;
  final double gradientEndOpacity;

  const CustomGlassContainer({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.borderRadius = AppRadius.control,
    this.blur = 0,
    this.borderOpacity = 0.18,
    this.gradientStartOpacity = 0.20,
    this.gradientEndOpacity = 0.06,
  });

  /// 返回扁平风格的 [BoxDecoration]，供 [ContextMenu] 等场景使用。
  /// 边框走主题的 hairlineBorderColor；背景不透明。
  static BoxDecoration glassBoxDecoration({
    required BuildContext context,
    double borderRadius = AppRadius.control,
    double borderOpacity = 0.18,
    double gradientStartOpacity = 0.22,
    double gradientEndOpacity = 0.08,
  }) {
    final theme = Theme.of(context);
    final custom = theme.extension<CustomColors>();
    return BoxDecoration(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(
        color: custom?.hairlineBorderColor ?? const Color(0x1F000000),
        width: 0.5,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final flat = Container(
      padding: padding,
      decoration: glassBoxDecoration(
        context: context,
        borderRadius: borderRadius,
        borderOpacity: borderOpacity,
      ),
      child: child,
    );

    if (margin != null) {
      return Padding(padding: margin!, child: flat);
    }
    return flat;
  }
}
