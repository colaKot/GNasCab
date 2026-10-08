import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../utils/toast_util.dart';

/// 目录授权档位
enum AccessLevel { read, write }

/// 「只可访问」：能浏览、能在影视/音乐/相册里看到并播放、能看缩略图、能下载
const List<String> kReadOnlyActions = ['view', 'download'];

/// 「可修改」：在只读基础上再加 增（upload）/ 删（delete）/ 改（update）
const List<String> kReadWriteActions = [
  'view',
  'download',
  'update',
  'delete',
  'upload',
];

/// 子账号访问策略编辑器
/// - 可用应用白名单（不限制 / 只允许选中的几个应用）
/// - 目录授权：每个目录二选一「只可访问 / 可修改」
class CustomAccessPolicyEditor extends StatefulWidget {
  final List<String>? initialAllowedApps;
  final List<Map<String, dynamic>> initialPermissions;
  final List<String> availableApps;
  final Future<bool> Function(
    List<String>? allowedApps,
    List<Map<String, dynamic>> permissions,
  )
  onSave;
  final Future<void> Function(void Function(String path) onSelected)
  onPickDirectory;

  const CustomAccessPolicyEditor({
    super.key,
    required this.initialAllowedApps,
    required this.initialPermissions,
    required this.availableApps,
    required this.onSave,
    required this.onPickDirectory,
  });

  @override
  State<CustomAccessPolicyEditor> createState() =>
      _CustomAccessPolicyEditorState();
}

class _CustomAccessPolicyEditorState extends State<CustomAccessPolicyEditor> {
  late bool _restrictApps;
  late List<String> _allowedApps;
  late final Map<String, AccessLevel> _levels;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _restrictApps = widget.initialAllowedApps != null;
    _allowedApps = List<String>.from(widget.initialAllowedApps ?? const []);
    _levels = _parseLevels(widget.initialPermissions);
  }

  Map<String, AccessLevel> _parseLevels(List<Map<String, dynamic>> perms) {
    final map = <String, AccessLevel>{};
    for (final p in perms) {
      final path = (p['res_path'] ?? '').toString().trim();
      if (path.isEmpty) continue;
      final action = (p['action'] ?? '').toString();
      final isWrite =
          action == 'update' || action == 'delete' || action == 'upload';
      final next = isWrite ? AccessLevel.write : AccessLevel.read;
      final cur = map[path];
      if (cur == null || next == AccessLevel.write) map[path] = next;
    }
    return map;
  }

  List<Map<String, dynamic>> _buildPermissions() {
    // 同一个 action 下父子路径不能并存：按路径长度升序处理，
    // 父路径先入列，其下的子路径在同一 action 上直接跳过。
    final paths = _levels.keys.toList()
      ..sort((a, b) => a.length.compareTo(b.length));
    final out = <Map<String, dynamic>>[];
    final claimed = <String, List<String>>{};
    for (final path in paths) {
      final level = _levels[path] ?? AccessLevel.read;
      final actions =
          level == AccessLevel.write ? kReadWriteActions : kReadOnlyActions;
      for (final a in actions) {
        final roots = claimed.putIfAbsent(a, () => <String>[]);
        if (roots.any((root) => _isPathUnder(path, root))) continue;
        roots.add(path);
        out.add({'res_type': 'file', 'res_path': path, 'action': a});
      }
    }
    return out;
  }

  /// 判断 [path] 是否位于 [root] 之下（含自身）。
  /// 带分隔符边界，避免 '\Media' 被当成 '\MediaBackup' 的父目录。
  static bool _isPathUnder(String path, String root) {
    final c = path.replaceAll('\\', '/').replaceAll(RegExp(r'/+$'), '');
    final r = root.replaceAll('\\', '/').replaceAll(RegExp(r'/+$'), '');
    if (c.isEmpty || r.isEmpty) return false;
    if (c == r) return true;
    return c.startsWith('$r/');
  }

  void _addPath(String path) {
    final p = path.trim();
    if (p.isEmpty) return;
    setState(() {
      _levels.putIfAbsent(p, () => AccessLevel.read);
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    // ⚠️ 「限制应用」开启后必须至少选一个：
    //    空数组的语义是「一个都不允许」，null 的语义是「不限制」，二者相反。
    //    若把空选兜底成 null，管理员以为已禁用全部应用，实际反而是全放开。
    if (_restrictApps && _allowedApps.isEmpty) {
      ToastUtil.show('user_mgmt_restrict_apps_empty'.tr);
      return;
    }
    setState(() => _saving = true);
    try {
      final apps = _restrictApps ? List<String>.from(_allowedApps) : null;
      final ok = await widget.onSave(apps, _buildPermissions());
      if (!mounted) return;
      if (ok) {
        ToastUtil.show('user_mgmt_permission_saved'.tr);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final paths = _levels.keys.toList();

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(8),
            children: [
              _buildAppSection(theme),
              const SizedBox(height: 8),
              _buildAddDirCard(theme),
              ...paths.map((p) => _buildPathCard(theme, p)),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text('save'.tr),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAppSection(ThemeData theme) {
    final apps = widget.availableApps;
    return Card(
      color: theme.cardColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            dense: true,
            title: Text(
              'user_mgmt_restrict_apps'.tr,
              style: const TextStyle(fontSize: 14),
            ),
            subtitle: Text(
              'user_mgmt_restrict_apps_hint'.tr,
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            value: _restrictApps,
            onChanged: (v) {
              setState(() => _restrictApps = v);
            },
          ),
          if (_restrictApps)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: apps.map((app) {
                  final selected = _allowedApps.contains(app);
                  return FilterChip(
                    selected: selected,
                    label: Text(
                      'app_$app'.tr,
                      style: const TextStyle(fontSize: 12),
                    ),
                    onSelected: (_) {
                      setState(() {
                        if (selected) {
                          _allowedApps.remove(app);
                        } else {
                          _allowedApps.add(app);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
            ),
          if (_restrictApps && _allowedApps.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Text(
                'user_mgmt_restrict_apps_empty'.tr,
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.error,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAddDirCard(ThemeData theme) {
    return Card(
      color: theme.cardColor,
      child: ListTile(
        leading: const Icon(Icons.add),
        title: Text('user_mgmt_add_auth_dir'.tr),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'user_mgmt_add_auth_dir_alert'.tr,
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            Text(
              'user_mgmt_add_auth_dir_hint'.tr,
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
        onTap: () async {
          await widget.onPickDirectory(_addPath);
        },
      ),
    );
  }

  Widget _buildPathCard(ThemeData theme, String path) {
    final level = _levels[path] ?? AccessLevel.read;
    return Card(
      color: theme.cardColor,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  iconSize: 20,
                  padding: EdgeInsets.zero,
                  onPressed: () => setState(() => _levels.remove(path)),
                ),
                Expanded(
                  child: Text(
                    path,
                    style: TextStyle(
                      color: theme.colorScheme.onSurface,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    selected: level == AccessLevel.read,
                    label: Text(
                      'user_mgmt_perm_readonly'.tr,
                      style: const TextStyle(fontSize: 11),
                    ),
                    onSelected: (_) =>
                        setState(() => _levels[path] = AccessLevel.read),
                  ),
                  ChoiceChip(
                    selected: level == AccessLevel.write,
                    label: Text(
                      'user_mgmt_perm_readwrite'.tr,
                      style: const TextStyle(fontSize: 11),
                    ),
                    onSelected: (_) =>
                        setState(() => _levels[path] = AccessLevel.write),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
