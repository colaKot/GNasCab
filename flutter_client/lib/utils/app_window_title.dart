import '../core/bootstrap/app_launch.dart';
import 'app_window_title_impl_stub.dart'
    if (dart.library.html) 'app_window_title_impl_web.dart'
    if (dart.library.io) 'app_window_title_impl_io.dart'
    as app_window_title_impl;

/// 浏览器标签页 / 桌面主窗口标题（登录会话与用户信息弹窗期间切换）
class AppWindowTitle {
  AppWindowTitle._();

  /// 默认标题：完整版为 `WaterNasOS`，独立端为 `WaterNasOS 相册` / `WaterNasOS 音乐`。
  static String get defaultTitle => AppLaunch.appTitle;

  static void setTitle(String title) {
    app_window_title_impl.appWindowTitleSetImpl(title);
  }

  static void applyDefault() => setTitle(defaultTitle);

  static void applyForSession(String? customHostname) {
    final t = (customHostname ?? '').trim();
    setTitle(t.isNotEmpty ? t : defaultTitle);
  }
}
