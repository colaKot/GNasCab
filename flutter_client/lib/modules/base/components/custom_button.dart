import 'package:flutter/material.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/app_skin.dart';
import '../../../core/theme/skin_presets.dart';

/// 自定义按钮组件
/// 提供统一的按钮样式，支持PC和App的通用性
///
/// ⭐ 2026-10-09 换肤：圆角 / 最小高度跟随 [AppSkin]（默认皮肤 = 换肤前外观，
/// 老用户无感）。显式传入 [style] 时以 [style] 为准，不受皮肤影响。
class CustomButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final ButtonStyle? style;
  final bool isPrimary;
  final bool isDisabled;
  final double? width;
  final double? height;
  final Widget? icon;

  const CustomButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.style,
    this.isPrimary = true,
    this.isDisabled = false,
    this.width,
    this.height,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final skin =
        Theme.of(context).extension<AppSkin>() ?? SkinPresets.defaultSkin;
    // ⚠️ 2026-10-09 修：禁用态原来写死 `Colors.white`(38%) + 灰 12% 底，
    // 亮色模式下 = 白字压近白白底 ⇒ 禁用按钮的文字/图标直接看不见。
    // 改成从 ColorScheme 派生：亮色下是深灰字 + 极浅底，暗色下自动反过来。
    ButtonStyle defaultStyle = ElevatedButton.styleFrom(
      disabledForegroundColor: theme.colorScheme.onSurface.withValues(
        alpha: 0.38,
      ),
      disabledBackgroundColor: theme.colorScheme.onSurface.withValues(
        alpha: 0.12,
      ),
      // padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      textStyle: const TextStyle(fontWeight: FontWeight.w500),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(skin.buttonRadius),
      ),
      minimumSize: Size(
        width ?? AppSize.buttonMinWidth,
        height ?? skin.buttonHeight,
      ),
    );

    return SizedBox(
      width: width,
      height: height,
      child: icon != null
          ? ElevatedButton.icon(
              onPressed: isDisabled ? null : onPressed,
              icon: icon!,
              label: Text(text),
              style: style ?? defaultStyle,
            )
          : ElevatedButton(
              onPressed: isDisabled ? null : onPressed,
              style: style ?? defaultStyle,
              child: Text(text),
            ),
    );
  }
}
