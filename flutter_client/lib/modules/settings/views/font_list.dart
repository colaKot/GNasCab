import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_fonts.dart';
import '../../../core/theme/theme_apply_service.dart';
import '../../../core/theme/theme_manager.dart';

/// 界面字体选择列表（2026-10-09 换肤系统）
///
/// 设置页「主题 → 界面字体」用。点选即 `Get.changeTheme` 立即生效 + 持久化。
class ThemeFontList extends StatelessWidget {
  /// 选完回调（让外层弹窗的选中勾刷新）
  final VoidCallback? onPicked;

  const ThemeFontList({super.key, this.onPicked});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = ThemeManager().getFontFamily();

    return Column(
      children: [
        for (final f in AppFonts.all)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(f.labelKey.tr),
            subtitle: f.family == null
                ? null
                : Text(
                    f.family!,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
            trailing: current == f.family
                ? const Icon(Icons.check_outlined)
                : null,
            onTap: () async {
              await ThemeApplyService.instance.applyFontFamily(f.family);
              onPicked?.call();
            },
          ),
      ],
    );
  }
}