#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
把「写死的颜色」统一改成从 ColorScheme 派生（2026-10-09，铁柱批准）。

原则：压在 `primary` 上 → onPrimary；压在 `error` 上 → onError；
      压在 `primaryContainer` 上 → onPrimaryContainer；进度条轨道 → dividerColor。
每处都用「行号 + 期望的原始内容」双重校验，错位就立刻中止，绝不盲改。
"""
import os
import sys

ROOT = r'G:\work\nascab\flutter_client\lib'

# 单行替换： (行号, 期望原始 strip, 新内容 strip)
EDITS = {
    r'modules\photo\photo_main\view\app_photo_main_view.dart': [
        (288, 'color: selected ? Colors.white : theme.colorScheme.onSurface,',
              'color: selected ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface,'),
    ],
    r'modules\book\book_main\view\app_book_main_view.dart': [
        (321, 'color: selected ? Colors.white : theme.colorScheme.onSurface,',
              'color: selected ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface,'),
    ],
    r'modules\video\video_main\view\app_video_main_view.dart': [
        (60, 'color: selected ? Colors.white : theme.colorScheme.onSurface,',
             'color: selected ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface,'),
    ],
    r'modules\notes\view\parts\notes_note_list.dart': [
        (167, 'final primaryText = selected ? Colors.white : scheme.onSurface;',
              'final primaryText = selected ? scheme.onPrimary : scheme.onSurface;'),
        (169, '? Colors.white.withValues(alpha: 0.84)',
              '? scheme.onPrimary.withValues(alpha: 0.84)'),
        (172, '? Colors.white.withValues(alpha: 0.9)',
              '? scheme.onPrimary.withValues(alpha: 0.9)'),
        (175, '? Colors.white.withValues(alpha: 0.92)',
              '? scheme.onPrimary.withValues(alpha: 0.92)'),
        (226, 'color: Colors.white.withValues(alpha: 0.92),',
              'color: scheme.onPrimary.withValues(alpha: 0.92),'),
        (253, 'color: selected ? Colors.white : scheme.primary,',
              'color: selected ? scheme.onPrimary : scheme.primary,'),
        (329, '? Colors.white.withValues(alpha: 0.84)',
              '? scheme.onPrimary.withValues(alpha: 0.84)'),
    ],
    # 302 那处所在闭包没有 scheme 变量（同层用的是 Theme.of(context)）⇒ 就地取
    r'modules\notes\view\parts\notes_sidebar.dart': [
        (302, '? Colors.white.withValues(alpha: 0.92)',
              '? Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.92)'),
        (329, 'final fg = selected ? Colors.white : scheme.onSurface;',
              'final fg = selected ? scheme.onPrimary : scheme.onSurface;'),
        (410, '? Colors.white.withValues(alpha: 0.18)',
              '? scheme.onPrimary.withValues(alpha: 0.18)'),
    ],
    r'modules\notes\view\parts\notes_notebook_chooser.dart': [
        (30, 'const Icon(Icons.menu_book_rounded, size: 64, color: Color(0xFF4F6AF2)),',
             'Icon(Icons.menu_book_rounded, size: 64, color: theme.colorScheme.primary),'),
        (45, 'icon: const Icon(Icons.folder_open_rounded, color: Colors.white),',
             'icon: const Icon(Icons.folder_open_rounded),'),
        (48, 'style: const TextStyle(fontSize: 14, color: Colors.white),',
             'style: const TextStyle(fontSize: 14),'),
    ],
    r'modules\docker\view\parts\docker_dialogs.dart': [
        (1431, '? Colors.white', '? theme.colorScheme.onPrimary'),
        (1441, '? Colors.white', '? theme.colorScheme.onPrimary'),
        (1593, 'Icon(Icons.add, size: 18, color: Colors.white),',
               'Icon(Icons.add, size: 18, color: theme.colorScheme.onPrimary),'),
        (1598, 'color: Colors.white,', 'color: theme.colorScheme.onPrimary,'),
    ],
    r'modules\docker\view\parts\docker_shared_widgets.dart': [
        (188, 'const Icon(Icons.error_outline, color: Colors.white),',
              'Icon(\n            Icons.error_outline,\n'
              '            color: Theme.of(context).colorScheme.onError,\n          ),'),
        (195, ').textTheme.bodyMedium?.copyWith(color: Colors.white),',
              ').textTheme.bodyMedium?.copyWith(\n                color: Theme.of(context).colorScheme.onError,\n              ),'),
    ],
    r'modules\message\views\message_center_view.dart': [
        (473, 'foregroundColor: Colors.white,',
              'foregroundColor: theme.colorScheme.onError,'),
    ],
    r'modules\video\detail\view\parts\video_detail_actions_section.dart': [
        (158, 'backgroundColor: Colors.blue.shade800,',
              'backgroundColor: theme.colorScheme.primary,'),
        (159, 'foregroundColor: Colors.white,',
              'foregroundColor: theme.colorScheme.onPrimary,'),
    ],
    r'modules\home\views\pc_components\pc_wallpaper_picker_view.dart': [
        (258, 'foregroundColor: Colors.white,', 'foregroundColor: theme.colorScheme.onError,'),
        (373, "child: Text('home_wallpaper_apply'.tr, style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white)),",
              "child: Text('home_wallpaper_apply'.tr),"),
        (475, 'child: const Icon(', 'child: Icon('),
        (478, 'color: Colors.white,', 'color: theme.colorScheme.onPrimary,'),
    ],
    r'modules\home\views\app_components\app_wallpaper_picker_view.dart': [
        (548, 'child: const Icon(', 'child: Icon('),
        (551, 'color: Colors.white,', 'color: theme.colorScheme.onPrimary,'),
    ],
    r'modules\home\views\components\user_info_dialog.dart': [
        (240, 'foregroundColor: Colors.white,', 'foregroundColor: theme.colorScheme.onPrimary,'),
    ],
    r'modules\service\account\view\service_contact_us_view.dart': [
        (127, 'colorText: Colors.white,', 'colorText: Get.theme.colorScheme.onPrimary,'),
    ],
    r'modules\transmission\transmission_view.dart': [
        (862, 'final completedAccent = isLight', 'final completedAccent = theme.colorScheme.tertiary;'),
        (863, '? const Color(0xFF2E7D32)', None),
        (864, ': theme.colorScheme.tertiary;', None),
        (917, 'color: isLight', 'color: Color.lerp(cardBase, completedAccent, 0.18),'),
        (918, '? const Color(0xFFE8F5E9)', None),
        (919, ': Color.lerp(cardBase, completedAccent, 0.18),', None),
    ],
    r'modules\transfer\views\file_log\file_log_item.dart': [
        (164, 'backgroundColor: Colors.grey[200],', 'backgroundColor: theme.dividerColor,'),
    ],
}

# 整块删除：notes_mobile_view 的 FilledButton 显式前景（默认就是 onPrimary）
DELETES = {
    r'modules\notes\view\parts\notes_mobile_view.dart': [
        (416, 'style: FilledButton.styleFrom('),
        (417, 'foregroundColor: Colors.white,'),
        (418, 'iconColor: Colors.white,'),
        (419, '),'),
    ],
}


def apply(path, edits):
    parts = open(path, encoding='utf-8', newline='').read().split('\n')
    drops = set()
    for lineno, expect, new in edits:
        raw = parts[lineno - 1]
        body = raw.rstrip('\r')
        if body.strip() != expect:
            raise SystemExit('%s:%d 期望不匹配\n  期望: %r\n  实际: %r'
                             % (os.path.basename(path), lineno, expect, body.strip()))
        if new is None:
            drops.add(lineno)
            continue
        indent = body[:len(body) - len(body.lstrip())]
        trailing = '\r' if raw.endswith('\r') else ''
        parts[lineno - 1] = indent + new + trailing
    out = [p for i, p in enumerate(parts, 1) if i not in drops]
    with open(path, 'w', encoding='utf-8', newline='') as f:
        f.write('\n'.join(out))
    return len(edits)


total = 0
for rel, edits in EDITS.items():
    n = apply(os.path.join(ROOT, rel), edits)
    total += n
    print('%-58s %d 处' % (rel, n))
for rel, edits in DELETES.items():
    n = apply(os.path.join(ROOT, rel), edits)
    total += n
    print('%-58s %d 行删除' % (rel, n))
print('共 %d 处' % total)
