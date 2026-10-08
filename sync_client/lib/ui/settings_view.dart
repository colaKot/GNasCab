import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:nascab_sync_core/nascab_sync_core.dart';

import '../core/session.dart';
import '../desktop/autostart.dart';
import '../sync/sync_controller.dart';

/// 与 pubspec.yaml 的 version 保持一致
const String kAppVersion = '1.0.0';

/// 设置页：开机自启、账号信息、退出登录。
class SettingsView extends StatefulWidget {
  const SettingsView({super.key});

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  bool _autoStart = false;
  bool _autoStartBusy = false;

  @override
  void initState() {
    super.initState();
    Future<void>(() async {
      final enabled = await AutoStart.isEnabled();
      if (mounted) setState(() => _autoStart = enabled);
    });
  }

  Future<void> _toggleAutoStart(bool value) async {
    if (_autoStartBusy) return;
    setState(() => _autoStartBusy = true);
    final ok = await AutoStart.setEnabled(value);
    if (!mounted) return;
    setState(() {
      _autoStartBusy = false;
      if (ok) {
        _autoStart = value;
      }
    });
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('auto_start_failed'.tr)),
      );
    }
  }

  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('logout'.tr),
        content: Text('logout_confirm'.tr),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('cancel'.tr),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('logout'.tr),
          ),
        ],
      ),
    );
    if (ok != true) return;

    // 停止自动同步 → 清掉本地基线与进度 → 清空登录态
    SyncScheduler.instance.stop();
    try {
      await SyncLocalStore.instance.clearAll();
    } catch (_) {}
    SyncController.instance.tasks.clear();
    for (final id in SyncEngine.instance.progressMap.keys.toList()) {
      SyncEngine.instance.clearProgress(id);
    }
    await SessionController.instance.logout();

    if (!mounted) return;
    Get.offAllNamed('/login');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = SessionController.instance;

    return Scaffold(
      appBar: AppBar(title: Text('settings'.tr)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: [
          _GroupTitle(text: 'settings_general'.tr),
          _Tile(
            icon: Icons.power_settings_new,
            title: 'auto_start'.tr,
            subtitle: 'auto_start_desc'.tr,
            trailing: _autoStartBusy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Switch(
                    value: _autoStart,
                    onChanged: _toggleAutoStart,
                  ),
          ),
          const SizedBox(height: 18),
          _GroupTitle(text: 'settings_account'.tr),
          _Tile(
            icon: Icons.dns_outlined,
            title: 'settings_server'.tr,
            subtitle: Obx(
              () => Text(
                session.baseUrl.value.isEmpty
                    ? '-'
                    : session.baseUrl.value,
              ),
            ),
          ),
          _Tile(
            icon: Icons.person_outline,
            title: 'current_account'.tr,
            subtitle: Obx(
              () => Text(
                session.username.value.isEmpty
                    ? '-'
                    : session.username.value,
              ),
            ),
          ),
          const SizedBox(height: 22),
          OutlinedButton.icon(
            onPressed: _logout,
            icon: const Icon(Icons.logout, size: 18),
            label: Text('logout'.tr),
            style: OutlinedButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
              side: BorderSide(
                color: theme.colorScheme.error.withOpacity(0.5),
              ),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
          const SizedBox(height: 28),
          _GroupTitle(text: 'settings_about'.tr),
          _Tile(
            icon: Icons.info_outline,
            title: 'app_name'.tr,
            subtitle: Text('${'settings_version'.tr} $kAppVersion'),
          ),
        ],
      ),
    );
  }
}

class _GroupTitle extends StatelessWidget {
  const _GroupTitle({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final Widget? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon, size: 20),
        title: Text(title),
        subtitle: subtitle,
        trailing: trailing,
        dense: true,
      ),
    );
  }
}
