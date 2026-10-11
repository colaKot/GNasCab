/// 独立客户端启动模式。
///
/// 主客户端（WaterNasOS 完整版）恒为 [AppLaunchMode.full]。
/// 派生的独立程序（photo_client / music_client）**不复制任何业务代码**，
/// 而是通过 `path:` 依赖主客户端工程，在各自 `main()` 里设置启动模式，
/// 复用同一份代码，仅在「可见应用范围」与「启动后自动进入的应用」上收敛。
///
/// 详见 `docs/相册同步MD5去重与独立App方案.md`。
enum AppLaunchMode {
  /// 完整客户端：首页展示服务端下发的全部应用。
  full,

  /// 相册独立端：只保留相册（照片）入口，启动后自动进入。
  photo,

  /// 音乐独立端：只保留音乐入口，启动后自动进入。
  music,
}

/// 进程级启动参数（由独立端的 `main()` 在 `runApp` 之前设置）。
class AppLaunch {
  AppLaunch._();

  /// 相册应用 appKey（服务端 `defaultApps` 中的 `photo`）。
  static const String appKeyPhoto = 'photo';

  /// 音乐应用 appKey（服务端 `defaultApps` 中的 `music`）。
  static const String appKeyMusic = 'music';

  /// 启动模式。独立端在 `runWaterNasOSApp(launchMode: ...)` 中设置。
  static AppLaunchMode mode = AppLaunchMode.full;

  /// 应用标题（窗口标题 / MaterialApp title）。
  static String get appTitle {
    switch (mode) {
      case AppLaunchMode.full:
        return 'WaterNasOS';
      case AppLaunchMode.photo:
        return 'WaterNasOS 相册';
      case AppLaunchMode.music:
        return 'WaterNasOS 音乐';
    }
  }

  /// 可见应用的 appKey 白名单；返回 `null` 表示不限制（完整版）。
  static Set<String>? get allowedAppKeys {
    switch (mode) {
      case AppLaunchMode.full:
        return null;
      case AppLaunchMode.photo:
        return const <String>{appKeyPhoto};
      case AppLaunchMode.music:
        return const <String>{appKeyMusic};
    }
  }

  /// 该应用在当前模式下是否可见。
  static bool isAppAllowed(String appKey) {
    final allowed = allowedAppKeys;
    return allowed == null || allowed.contains(appKey);
  }

  /// 启动后自动打开的应用 appKey；`null` 表示停留在首页（完整版行为）。
  static String? get autoOpenAppKey {
    switch (mode) {
      case AppLaunchMode.full:
        return null;
      case AppLaunchMode.photo:
        return appKeyPhoto;
      case AppLaunchMode.music:
        return appKeyMusic;
    }
  }
}
