import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../base/components/custom_container.dart';
import '../../base/components/custom_divider.dart';
import '../../base/components/custom_title_bar.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/theme_apply_service.dart';
import '../../../core/theme/theme_manager.dart';
import 'color_scheme_grid.dart';

class ThemeSelectorView extends StatelessWidget {
  const ThemeSelectorView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: CustomTitleBar(title: 'settings_theme'.tr, showBackButton: true),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpace.page),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'settings_theme_title'.tr,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
              ),
            ),
            SizedBox(height: AppSpace.section),
            CustomContainer(
              child: Column(
                children: [
                  _buildThemeOption(
                    context,
                    'settings_theme_light_mode'.tr,
                    Icons.light_mode_outlined,
                    ThemeMode.light,
                  ),
                  const CustomDivider(),
                  _buildThemeOption(
                    context,
                    'settings_theme_dark_mode'.tr,
                    Icons.dark_mode_outlined,
                    ThemeMode.dark,
                  ),
                  const CustomDivider(),
                  _buildThemeOption(
                    context,
                    'settings_theme_system_mode'.tr,
                    Icons.brightness_auto_outlined,
                    ThemeMode.system,
                  ),
                ],
              ),
            ),
            SizedBox(height: AppSpace.section),
            Text(
              'settings_theme_color_scheme'.tr,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
              ),
            ),
            SizedBox(height: AppSpace.xs),
            Text(
              'settings_theme_color_scheme_desc'.tr,
              style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
            ),
            // 页面内嵌⇒ 不关页面，且无需外部刷新勾（下一行本来就随主题重建）
            const ThemeSchemeGrid(closeAfterPick: false),
          ],
        ),
      ),
    );
  }

  Widget _buildThemeOption(
    BuildContext context,
    String title,
    IconData icon,
    ThemeMode mode,
  ) {
    final theme = Theme.of(context);
    final currentThemeMode = ThemeManager().getThemeMode();
    final isSelected = currentThemeMode == mode;

    return ListTile(
      leading: Icon(icon),
      title: Text(
        title,
        style: TextStyle(
          color: theme.colorScheme.onSurface,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      trailing: isSelected ? Icon(Icons.check_circle_outlined) : null,
      // ⭐ 走统一入口：切模式 + 持久化 + 重刷当前主题（配色不变）
      onTap: () => ThemeApplyService.instance.applyMode(mode),
    );
  }
}
