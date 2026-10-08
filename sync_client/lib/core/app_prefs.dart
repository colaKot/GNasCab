import 'dart:io';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// 应用级偏好 + 本机设备标识。
///
/// 同步任务在服务端按「设备」登记，独立客户端需要稳定上报同一个 device_id，
/// 否则每次运行都会被当成一台新电脑。
class AppPrefs {
  AppPrefs._();

  static const String _kAutoStart = 'nascab_sync.auto_start';
  static const String _kAutoSyncPaused = 'nascab_sync.auto_sync_paused';
  static const String _kDeviceId = 'nascab_sync.device_id';
  static const String _kDeviceName = 'nascab_sync.device_name';

  static SharedPreferences? _prefs;

  static Future<SharedPreferences> _sp() async =>
      _prefs ??= await SharedPreferences.getInstance();

  // ── 开机自启 ──

  static Future<bool> getAutoStart() async {
    final sp = await _sp();
    return sp.getBool(_kAutoStart) ?? false;
  }

  static Future<void> setAutoStart(bool value) async {
    final sp = await _sp();
    await sp.setBool(_kAutoStart, value);
  }

  // ── 全局暂停（托盘菜单控制） ──

  static Future<bool> getAutoSyncPaused() async {
    final sp = await _sp();
    return sp.getBool(_kAutoSyncPaused) ?? false;
  }

  static Future<void> setAutoSyncPaused(bool value) async {
    final sp = await _sp();
    await sp.setBool(_kAutoSyncPaused, value);
  }

  // ── 设备标识 ──

  /// 设备 ID：首次生成后持久化，形如 `sync-3f2a91c4`
  static Future<String> getDeviceId() async {
    final sp = await _sp();
    final cached = sp.getString(_kDeviceId);
    if (cached != null && cached.isNotEmpty) return cached;

    final rand = Random();
    final buf = StringBuffer('sync-');
    const hex = '0123456789abcdef';
    for (var i = 0; i < 12; i++) {
      buf.write(hex[rand.nextInt(16)]);
    }
    final id = buf.toString();
    await sp.setString(_kDeviceId, id);
    return id;
  }

  /// 设备名：默认取本机主机名
  static Future<String> getDeviceName() async {
    final sp = await _sp();
    final cached = sp.getString(_kDeviceName);
    if (cached != null && cached.isNotEmpty) return cached;

    String name;
    try {
      name = Platform.localHostname;
    } catch (_) {
      name = 'Windows 电脑';
    }
    if (name.trim().isEmpty) name = 'Windows 电脑';
    await sp.setString(_kDeviceName, name);
    return name;
  }

  static Future<void> setDeviceName(String name) async {
    final sp = await _sp();
    await sp.setString(_kDeviceName, name.trim());
  }
}
