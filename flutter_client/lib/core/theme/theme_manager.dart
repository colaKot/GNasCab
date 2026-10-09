import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_color_schemes.dart';

/// 主题管理器 - 负责主题设置（亮/暗模式 + 配色方案）的持久化保存和读取
///
/// 2026-10-08 新增配色方案持久化（配合设置页的配色切换）。
/// ⚠️ 存的是 `FlexScheme` 的**枚举名字符串**而不是下标 ——
/// 将来 flex 加/减内置配色、登记表调整顺序，已存的用户设置都不会错位。
class ThemeManager {
  static const String _themeModeKey = 'app_theme_mode';
  static const String _colorSchemeKey = 'app_color_scheme';

  static final ThemeManager _instance = ThemeManager._internal();

  factory ThemeManager() {
    return _instance;
  }

  ThemeManager._internal();

  late SharedPreferences _prefs;

  /// 初始化主题管理器
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  /// 保存主题模式
  Future<bool> saveThemeMode(ThemeMode themeMode) async {
    try {
      final themeValue = _themeModeToInt(themeMode);
      return await _prefs.setInt(_themeModeKey, themeValue);
    } catch (e) {
      print('保存主题模式失败: $e');
      return false;
    }
  }

  /// 获取保存的主题模式，如果没有保存则返回默认的浅色模式
  ThemeMode getThemeMode() {
    try {
      final themeValue = _prefs.getInt(_themeModeKey);
      if (themeValue != null) {
        return _intToThemeMode(themeValue);
      }
    } catch (e) {
      print('获取主题模式失败: $e');
    }

    // 如果没有找到缓存，默认使用浅色模式
    return ThemeMode.light;
  }

  // ────────────── 配色方案（2026-10-08 新增）──────────────

  /// 保存配色方案（存枚举名，非下标）
  Future<bool> saveColorScheme(FlexScheme scheme) async {
    try {
      return await _prefs.setString(_colorSchemeKey, scheme.name);
    } catch (e) {
      print('保存配色方案失败: $e');
      return false;
    }
  }

  /// 读取配色方案。
  /// 读不到 / 读到的名字不在 [AppColorSchemes] 登记表里（例如旧版本残留、
  /// 或 flex 升级改了枚举名）⇒ 回落到默认，**不崩**。
  FlexScheme getColorScheme() {
    try {
      final name = _prefs.getString(_colorSchemeKey);
      if (name != null) {
        final meta = AppColorSchemes.byName(name);
        if (meta != null) return meta.scheme;
        // 名字不认识了：可能是 flex 版本差异，兜底回默认
        return AppColorSchemes.defaultScheme;
      }
    } catch (e) {
      print('获取配色方案失败: $e');
    }
    return AppColorSchemes.defaultScheme;
  }

  /// 当前配色方案的元数据（设置页展示用）
  AppColorScheme getColorSchemeMeta() {
    final s = getColorScheme();
    return AppColorSchemes.byScheme(s) ??
        AppColorSchemes.byScheme(AppColorSchemes.defaultScheme)!;
  }

  /// 将ThemeMode转换为整数存储
  int _themeModeToInt(ThemeMode themeMode) {
    switch (themeMode) {
      case ThemeMode.light:
        return 0;
      case ThemeMode.dark:
        return 1;
      case ThemeMode.system:
        return 2;
    }
  }

  /// 将整数转换为ThemeMode
  ThemeMode _intToThemeMode(int value) {
    switch (value) {
      case 0:
        return ThemeMode.light;
      case 1:
        return ThemeMode.dark;
      case 2:
        return ThemeMode.system;
      default:
        return ThemeMode.light; // 默认值
    }
  }

  /// 清除主题设置（含配色方案）
  Future<bool> clearThemeMode() async {
    try {
      await _prefs.remove(_colorSchemeKey);
      return await _prefs.remove(_themeModeKey);
    } catch (e) {
      print('清除主题模式失败: $e');
      return false;
    }
  }
}