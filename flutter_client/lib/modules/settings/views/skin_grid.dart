import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_skin.dart';
import '../../../core/theme/skin_presets.dart';
import '../../../core/theme/theme_apply_service.dart';
import '../../../core/theme/theme_manager.dart';

/// 外观皮肤选择网格（2026-10-09 换肤系统）
///
/// 设置页「主题 → 外观皮肤」用。**4 套皮肤**，每项带窗口/标题栏/控件造型预览。
/// 点选即 `Get.changeTheme` 立即生效 + 持久化，不用重启。
///
/// ⚠️ 皮肤只管**结构**（圆角/尺寸/造型），颜色仍由当前配色决定 ⇒ 与配色方案正交。
class ThemeSkinGrid extends StatelessWidget {
  /// 选完是否关闭弹窗；作为页面内嵌时传 false
  final bool closeAfterPick;

  /// 选完回调（让弹窗的选中勾能刷新）
  final VoidCallback? onPicked;

  const ThemeSkinGrid({
    super.key,
    this.closeAfterPick = true,
    this.onPicked,
  });

  @override
  Widget build(BuildContext context) {
    final currentId = ThemeManager().getSkinId();
    final theme = Theme.of(context);

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: 12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 2.4,
      ),
      itemCount: SkinPresets.all.length,
      itemBuilder: (context, index) {
        final item = SkinPresets.all[index];
        return _SkinTile(
          item: item,
          selected: item.id == currentId,
          accentColor: theme.colorScheme.primary,
          onTap: () async {
            await ThemeApplyService.instance.applySkin(item.id);
            onPicked?.call();
            if (closeAfterPick && Navigator.of(Get.context!).canPop()) {
              Get.back<void>();
            }
          },
        );
      },
    );
  }
}

class _SkinTile extends StatelessWidget {
  final AppSkinPreset item;
  final bool selected;
  final Color accentColor;
  final VoidCallback onTap;

  const _SkinTile({
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
              _SkinPreview(
                skin: item.skin,
                accent: accentColor,
                surface: theme.colorScheme.surfaceContainerLowest,
                outline: theme.colorScheme.outlineVariant,
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

/// 迷你窗口预览：窗口圆角 + 标题栏按钮造型 + 控件圆角，一眼看出皮肤差异。
class _SkinPreview extends StatelessWidget {
  final AppSkin skin;
  final Color accent;
  final Color surface;
  final Color outline;

  const _SkinPreview({
    required this.skin,
    required this.accent,
    required this.surface,
    required this.outline,
  });

  @override
  Widget build(BuildContext context) {
    // 预览按 1/2 缩放，避免小尺寸下圆角看起来失真
    final radius = (skin.windowRadius * 0.5).clamp(2.0, 14.0);
    return SizedBox(
      width: 46,
      height: 34,
      child: Container(
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: outline, width: 0.8),
        ),
        child: Column(
          children: [
            // 标题栏（含右上角按钮）
            Container(
              height: 12,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: _dots(),
              ),
            ),
            // 内容区：一个按钮 + 一个开关，示意控件圆角 / 开关造型
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  children: [
                    Container(
                      width: 14,
                      height: 7,
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: BorderRadius.circular(
                          (skin.buttonRadius * 0.5).clamp(1.0, 4.0),
                        ),
                      ),
                    ),
                    const Spacer(),
                    _switchPreview(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _dots() {
    const gap = 2.0;
    switch (skin.titleBarButtonStyle) {
      case AppTitleBarButtonStyle.macos:
        return [
          for (var i = 0; i < 3; i++) ...[
            if (i > 0) const SizedBox(width: gap),
            Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                color: outline,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ];
      case AppTitleBarButtonStyle.minimal:
        return [
          for (var i = 0; i < 3; i++) ...[
            if (i > 0) const SizedBox(width: gap),
            Container(width: 4, height: 4, color: outline),
          ],
        ];
      case AppTitleBarButtonStyle.windows:
        return [
          for (var i = 0; i < 3; i++) ...[
            if (i > 0) const SizedBox(width: gap),
            Container(
              width: 5,
              height: 3,
              decoration: BoxDecoration(
                color: outline,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ],
        ];
    }
  }

  Widget _switchPreview() {
    switch (skin.switchStyle) {
      case AppSwitchStyle.square:
        return Container(
          width: 12,
          height: 7,
          padding: const EdgeInsets.all(1),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(1),
          ),
          alignment: Alignment.centerRight,
          child: Container(width: 5, height: 5, color: accent),
        );
      case AppSwitchStyle.cupertino:
      case AppSwitchStyle.material:
        return Container(
          width: 12,
          height: 7,
          padding: const EdgeInsets.all(1),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(4),
          ),
          alignment: Alignment.centerRight,
          child: Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
          ),
        );
    }
  }
}