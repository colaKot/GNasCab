import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_color_schemes.dart';
import '../../../core/theme/theme_apply_service.dart';
import '../../../core/theme/theme_manager.dart';

/// 配色方案选择网格（2026-10-08）
///
/// 设置页「主题 → 配色方案」用。**24 套 flex 内置配色**，每项带三色预览。
/// 点选即`Get.changeTheme` 立即生效 + 持久化，不用重启。
class ThemeSchemeGrid extends StatelessWidget {
  /// 选完是否关闭弹窗；作为页面内嵌时传 false
  final bool closeAfterPick;

  /// 选完回调（让弹窗的选中勾能刷新）
  final VoidCallback? onPicked;

  const ThemeSchemeGrid({
    super.key,
    this.closeAfterPick = true,
    this.onPicked,
  });

  @override
  Widget build(BuildContext context) {
    final current = ThemeManager().getColorScheme();
    final theme = Theme.of(context);

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: 12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        // PC 上排 4列，窄屏自动降到 2–3 列
        maxCrossAxisExtent: 200,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 2.4,
      ),
      itemCount: AppColorSchemes.all.length,
      itemBuilder: (context, index) {
        final item = AppColorSchemes.all[index];
        return _SchemeTile(
          item: item,
          selected: item.scheme == current,
          accentColor: theme.colorScheme.primary,
          onTap: () async {
            await ThemeApplyService.instance.applyScheme(item.scheme);
            // 选完刷新外层（弹窗的选中勾靠这个回调重绘）
            onPicked?.call();
            // closeAfterPick=false（设置页弹窗内嵌）⇒ 不关，让用户直接看到效果
            if (closeAfterPick &&
                Navigator.of(Get.context!).canPop()) {
              Get.back<void>();
            }
          },
        );
      },
    );
  }
}

class _SchemeTile extends StatelessWidget {
  final AppColorScheme item;
  final bool selected;
  final Color accentColor;
  final VoidCallback onTap;

  const _SchemeTile({
    required this.item,
    required this.selected,
    required this.accentColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = item.labelKey.tr;

    return Material(
      color: selected
          ? accentColor.withValues(alpha: 0.10)
          : theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? accentColor : theme.dividerColor,
              width: selected ? 2 : 0.5,
            ),
          ),
          child: Row(
            children: [
              // 三色预览色板
              SizedBox(
                width: 34,
                height: 20,
                child: Row(
                  children: [
                    for (final c in item.preview)
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: c,
                            borderRadius: BorderRadius.horizontal(
                              left: c == item.preview.first
                                  ? const Radius.circular(4)
                                  : Radius.zero,
                              right: c == item.preview.last
                                  ? const Radius.circular(4)
                                  : Radius.zero,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: theme.colorScheme.onSurface,
                    fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
                  ),
                ),
              ),
              if (selected)
                Icon(Icons.check_circle, size: 16, color: accentColor),
            ],
          ),
        ),
      ),
    );
  }
}