import 'package:GNasCab/core/bootstrap/app_launch.dart';

/// 构建与平台形态相关的全局配置。
class AppBuildConfig {
  const AppBuildConfig._();

  /// Android applicationId
  ///
  /// 必须与各自 `android/app/build.gradle.kts` 里的 `applicationId` 一致
  /// （完整版 com.nascabos.mobile / 相册端 com.nascabos.photo / 音乐端 com.nascabos.music）。
  static String get androidApplicationId {
    switch (AppLaunch.mode) {
      case AppLaunchMode.full:
        return 'com.nascabos.mobile';
      case AppLaunchMode.photo:
        return 'com.nascabos.photo';
      case AppLaunchMode.music:
        return 'com.nascabos.music';
    }
  }

  /// Apple bundle id（iOS）
  static const String appleBundleId = 'com.nascabos.ios';
}
