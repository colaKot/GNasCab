import 'package:flutter/material.dart';

/// 登录前页面（登录 / 服务器列表 / 添加服务器 / 创建管理员 / 找回密码）的统一背景。
///
/// ⭐ 2026-10-09：以前这些页面**写死压一张深蓝色照片**（`assets/home/login_bg.jpg`）
/// ⇒ 换任何配色、切亮/暗，背景永远是那张深蓝图，于是「登录按钮（跟随配色）」
/// 和「背景（固定深蓝）」永远不搭（铁柱：「登录按钮的颜色和背景不同」）。
///
/// 现在改成**完全从当前 `ColorScheme` 派生**的柔和渐变：
/// - 换配色 ⇒ 渐变跟着换色相（换绿色方案就是淡绿 → 浅灰）
/// - 切亮/暗 ⇒ 亮色下浅、暗色下深
/// - 卡片本身用 `scaffoldBackgroundColor.withValues(alpha: 0.6)`，压在渐变上仍有层次
///
/// ⚠️ 不要退回写死的图片或色值；要变只能从 `cs` 里派生。
class AuthThemeBackground extends StatelessWidget {
  const AuthThemeBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[cs.primaryContainer, cs.surfaceContainerHighest],
        ),
      ),
      child: child,
    );
  }
}
