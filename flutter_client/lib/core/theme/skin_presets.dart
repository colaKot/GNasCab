import 'package:flutter/material.dart';

import 'app_skin.dart';

/// 皮肤 ID。**存字符串（`name`）而不是下标** —— 将来增删皮肤，老用户设置不会错位。
enum AppSkinId { windows11, macos, material3, compact }

/// 单套皮肤的元数据（ID + 展示名 key + 皮肤本体）
class AppSkinPreset {
  final AppSkinId id;
  final String labelKey;
  final AppSkin skin;

  const AppSkinPreset({
    required this.id,
    required this.labelKey,
    required this.skin,
  });
}

/// 皮肤登记表（2026-10-09）
///
/// ⭐ **默认皮肤 `windows11` = 当前发布外观**，改它等于改所有老用户的默认观感，
/// 非必要不动。2026-10-10 按需求改过一次：右上角按钮从「24×16 红黄绿小圆点」
/// 改为「40×40 方形圆角透明底 + 图标常显」，标题栏相应 40 → 48（上下各 4 让位）。
///
/// 每套皮肤只描述**结构差异**；颜色一律从当前配色派生。
class SkinPresets {
  const SkinPresets._();

  /// 默认皮肤（也是首次安装 / 读取失败时的兜底）
  static const AppSkinId defaultId = AppSkinId.windows11;

  static const AppSkinPreset windows11 = AppSkinPreset(
    id: AppSkinId.windows11,
    labelKey: 'theme_skin_windows11',
    skin: AppSkin(
      windowRadius: 16,
      windowBorderWidth: 0.5,
      // ⭐ 48 = 40×40 按钮 + 上下各 4 让位（2026-10-10：按钮改大方块后不再顶边）
      titleBarHeight: 48,
      titleBarButtonStyle: AppTitleBarButtonStyle.windows,
      titleBarButtonWidth: 40,
      titleBarButtonHeight: 40,
      titleBarButtonSpacing: 8,
      titleBarButtonIconSize: 18,
      controlRadius: 4,
      buttonRadius: 10,
      buttonHeight: 40,
      switchStyle: AppSwitchStyle.material,
      iconVariant: AppIconVariant.filled,
      iconSize: 24,
    ),
  );

  static const AppSkinPreset macos = AppSkinPreset(
    id: AppSkinId.macos,
    labelKey: 'theme_skin_macos',
    skin: AppSkin(
      windowRadius: 10,
      windowBorderWidth: 0.5,
      // ⭐ 2026-10-10：窗口按钮改为「全皮肤统一 40×40 方块 + 透明底」，故各皮肤的
      //    按钮度量全部对齐 windows11；标题栏同步 48 保证上下各留 4（否则 40 高的按钮会溢出）
      titleBarHeight: 48,
      titleBarButtonStyle: AppTitleBarButtonStyle.windows,
      titleBarButtonWidth: 40,
      titleBarButtonHeight: 40,
      titleBarButtonSpacing: 8,
      titleBarButtonIconSize: 18,
      controlRadius: 8,
      buttonRadius: 8,
      buttonHeight: 40,
      switchStyle: AppSwitchStyle.cupertino,
      iconVariant: AppIconVariant.filled,
      iconSize: 24,
    ),
  );

  static const AppSkinPreset material3 = AppSkinPreset(
    id: AppSkinId.material3,
    labelKey: 'theme_skin_material3',
    skin: AppSkin(
      windowRadius: 28,
      windowBorderWidth: 0,
      // ⭐ 2026-10-10：窗口按钮全皮肤统一 40×40 方块（详见 windows11 处注释）
      titleBarHeight: 48,
      titleBarButtonStyle: AppTitleBarButtonStyle.windows,
      titleBarButtonWidth: 40,
      titleBarButtonHeight: 40,
      titleBarButtonSpacing: 8,
      titleBarButtonIconSize: 18,
      controlRadius: 12,
      buttonRadius: 12,
      buttonHeight: 40,
      switchStyle: AppSwitchStyle.material,
      iconVariant: AppIconVariant.outlined,
      iconSize: 24,
    ),
  );

  static const AppSkinPreset compact = AppSkinPreset(
    id: AppSkinId.compact,
    labelKey: 'theme_skin_compact',
    skin: AppSkin(
      windowRadius: 8,
      windowBorderWidth: 0.5,
      // ⭐ 2026-10-10：窗口按钮全皮肤统一 40×40 方块 ⇒ 标题栏不能再压到 34（会溢出），
      //    「紧凑」皮肤现在只通过圆角/控件高度/图标风格体现紧凑感
      titleBarHeight: 48,
      titleBarButtonStyle: AppTitleBarButtonStyle.windows,
      titleBarButtonWidth: 40,
      titleBarButtonHeight: 40,
      titleBarButtonSpacing: 8,
      titleBarButtonIconSize: 18,
      controlRadius: 2,
      buttonRadius: 2,
      buttonHeight: 32,
      switchStyle: AppSwitchStyle.square,
      iconVariant: AppIconVariant.filled,
      iconSize: 20,
    ),
  );

  /// 全部可选皮肤。**顺序即设置页展示顺序**。
  static const List<AppSkinPreset> all = [
    windows11,
    macos,
    material3,
    compact,
  ];

  static AppSkinPreset byId(AppSkinId id) {
    for (final e in all) {
      if (e.id == id) return e;
    }
    return windows11;
  }

  /// 枚举名 → 元数据。用于从 SharedPreferences 读回字符串（读不到回默认，不崩）。
  static AppSkinPreset byName(String? name) {
    if (name != null) {
      for (final e in all) {
        if (e.id.name == name) return e;
      }
    }
    return windows11;
  }

  /// 默认皮肤本体（无 context 时的兜底，如 `pc_app_window` 的静态常量）
  static AppSkin get defaultSkin => windows11.skin;
}