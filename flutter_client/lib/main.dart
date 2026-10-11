import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'utils/cache_manager.dart';
import 'core/theme/theme_manager.dart';
import 'utils/device_utils.dart';
import 'core/languages/language_service.dart';
import 'core/theme/theme_apply_service.dart'; // ⭐ 统一的主题应用入口（含配色切换）
import 'package:get/get.dart';
import 'core/routes/app_routes.dart';
import 'core/api/api_controller.dart';
import 'core/api/io_self_signed_http_overrides.dart';
import 'core/bootstrap/app_launch.dart';
import 'core/notification/transfer_work_notification_hub.dart';
import 'modules/auth/service/auth_api_service.dart';
import 'modules/home/service/appearance_api_service.dart';
import 'core/bg/background_controller.dart';
import 'core/user/current_user_controller.dart';
import 'core/bg_task/hw_metrics_controller.dart';
import 'package:flutter_fullscreen/flutter_fullscreen.dart';
import 'modules/music/play_service/controller/music_play_service_controller.dart';
import 'modules/fileBackup/localBackup/local_backup_controller.dart';
import 'modules/sync/controller/sync_task_list_controller.dart';
import 'modules/sync/service/sync_api_service.dart';
import 'modules/sync/service/sync_host_impl.dart';
import 'modules/photoBackup/controller/photo_backup_controller.dart';
import 'modules/video_player/controllers/platform/video_platform.dart';
import 'desktop/desktop_tray.dart';
import 'package:nascab_sync_core/nascab_sync_core.dart';
import 'package:photo_manager/photo_manager.dart' as pm;

import 'core/web/context_menu_stub.dart'
    if (dart.library.html) 'core/web/context_menu_web.dart';

const double _scrollbarThickness = 8;

// 滚动条空闲时半透明，交互时实色
final WidgetStateProperty<double> _scrollbarThicknessState =
    WidgetStateProperty.all(_scrollbarThickness);

WidgetStateProperty<Color> _scrollbarThumbColorState(Color base) {
  return WidgetStateProperty.resolveWith((states) {
    if (states.contains(WidgetState.hovered) ||
        states.contains(WidgetState.dragged)) {
      return base.withValues(alpha: 0.8);
    }
    return base.withValues(alpha: 0.3);
  });
}

WidgetStateProperty<Color> _scrollbarTrackColorState(Color base) {
  return WidgetStateProperty.resolveWith((states) {
    if (states.contains(WidgetState.hovered) ||
        states.contains(WidgetState.dragged)) {
      return base.withValues(alpha: 0.3);
    }
    return base.withValues(alpha: 0.1);
  });
}

// 设备信息检测工具类
Future<void> main() => runWaterNasOSApp();

/// 共享启动入口。
///
/// 主客户端（WaterNasOS 完整版）走 `main()`（等价于 `full`）；
/// 派生的独立程序（photo_client / music_client）通过 `path:` 依赖本工程，
/// 在各自的 `main()` 里调用 `runWaterNasOSApp(launchMode: ...)` 即可，
/// **不复制任何业务代码**。
Future<void> runWaterNasOSApp({
  AppLaunchMode launchMode = AppLaunchMode.full,
}) async {
  AppLaunch.mode = launchMode;
  // 确保Flutter绑定已初始化
  WidgetsFlutterBinding.ensureInitialized();
  applyIoSelfSignedHttpOverridesIfNeeded();
  await FullScreen.ensureInitialized();

  // 手机端固定竖屏，禁止自动横屏（视频播放器内可手动横屏）
  if (DeviceUtils.isMobile && !DeviceUtils.isWeb) {
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  }

  // 初始化缓存管理器
  await CacheManager().init();

  // 初始化主题管理器
  await ThemeManager().init();

  // 初始化 GetX 依赖注入
  await Get.putAsync(() => LanguageService().init());

  if (DeviceUtils.isAndroid) {
    unawaited(TransferWorkNotificationHub.instance.ensureInitialized());
  }

  // iOS：启动时清理 photo_manager 文件缓存 + 过期临时导出文件（兜底处理异常退出/强杀残留）。
  if (!DeviceUtils.isWeb && (DeviceUtils.isIOS || DeviceUtils.isAndroid)) {
    unawaited(pm.PhotoManager.clearFileCache());
    // unawaited(
    //   UploadTempFileCleaner.instance.sweepStaleFiles(
    //     maxAge: const Duration(hours: 24),
    //     includeCache: false,
    //     includeSupport: false,
    //   ),
    // );
  }

  // 注册API控制器
  Get.put<ApiController>(ApiController(), permanent: true);
  // 注册AuthApiService
  Get.lazyPut<AuthApiService>(() => AuthApiService(), fenix: true);
  // 注册AppearanceApiService
  Get.lazyPut<AppearanceApiService>(() => AppearanceApiService(), fenix: true);
  // 注册背景图片控制器
  Get.lazyPut<BackgroundController>(() => BackgroundController(), fenix: true);
  // 注册当前用户控制器
  Get.lazyPut<CurrentUserController>(
    () => CurrentUserController(),
    fenix: true,
  );
  // 注册硬件信息轮训获取控制器
  Get.lazyPut<HwMetricsController>(() => HwMetricsController(), fenix: true);
  Get.put(MusicPlayServiceController(), permanent: true);
  // 注册目录同步接口服务（电脑 <-> NAS）
  Get.lazyPut<SyncApiService>(() => SyncApiService(), fenix: true);
  // 装配共享同步核心（nascab_sync_core）的宿主实现：
  // 同步引擎在 PC 端与 Windows 独立客户端之间共用，这里注入 PC 端专属的
  // 鉴权、上传实现与下载通道（直连 / P2P）。
  SyncHostHolder.instance = FlutterSyncHost.instance;

  // 桌面端：本地备份控制器常驻后台，登入/登出时在此单例上启停实时监控
  if (!DeviceUtils.isWeb && DeviceUtils.isDesktop) {
    Get.put(LocalBackupController(), permanent: true);
    // 桌面端：目录同步控制器常驻后台，用于按需同步与定时同步
    Get.put(SyncTaskListController(), permanent: true);
  }
  if (!DeviceUtils.isWeb && DeviceUtils.isMobile) {
    Get.put(PhotoBackupController(), permanent: true);
  }

  if (!DeviceUtils.isWeb && DeviceUtils.isDesktop) {
    await DesktopTray.init();
  }

  if (DeviceUtils.isWeb) {
    print('检测到Web平台');
    disableDefaultContextMenu();
    registerFvp();
    final initialThemeMode = ThemeManager().getThemeMode();
    _runNasCabApp(
      initialThemeMode: initialThemeMode,
      initialRoute: AppRoutes.login,
    );
  } else {
    print('检测到${DeviceUtils.platformName}平台，使用原生main.dart');
    final initialThemeMode = ThemeManager().getThemeMode();
    _runNasCabApp(
      initialThemeMode: initialThemeMode,
      initialRoute: AppRoutes.serverList,
    );
  }
}

void _runNasCabApp({
  required ThemeMode initialThemeMode,
  required String initialRoute,
}) {
  // ⭐ 配色方案 / 外观皮肤 / 字体都从持久化读取（2026-10-09 换肤系统）。
  // 启动与设置页切换走同一个 ThemeApplyService，避免两处逻辑不一致。
  final persisted = ThemeApplyService.instance.readPersisted();
  // 滚动条粗细沿用用户设置（静态成员，只能类名访问）
  ThemeApplyService.scrollbarThicknessProvider = () =>
      _scrollbarThicknessState;

  runApp(
    GetMaterialApp(
      navigatorKey: Get.key,
      title: AppLaunch.appTitle,
      // 亮/暗两套都按当前「配色 + 皮肤 + 字体」现场构建；滚动条底色取主题 outline
      // （换配色自动跟随），粗细与悬停态仍由用户设置控制（功能，不是风格）。
      theme: ThemeApplyService.instance.lightFor(
        persisted.scheme,
        skin: persisted.skin,
        fontFamily: persisted.fontFamily,
      ),
      darkTheme: ThemeApplyService.instance.darkFor(
        persisted.scheme,
        skin: persisted.skin,
        fontFamily: persisted.fontFamily,
      ),
      themeMode: initialThemeMode,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        FlutterQuillLocalizations.delegate,
      ],
      supportedLocales: LanguageService.supportedLocales.keys.map((code) {
        final parts = code.split('_');
        if (parts.length == 2) return Locale(parts[0], parts[1]);
        return Locale(parts[0]);
      }).toList(),
      translations: LanguageService.to,
      locale: Get.locale,
      fallbackLocale: const Locale('zh', 'CN'),
      initialRoute: initialRoute,
      getPages: AppRoutes.getPages,
    ),
  );
}
