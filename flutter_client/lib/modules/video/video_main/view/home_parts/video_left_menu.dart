import 'package:GNasCab/core/user/current_user_controller.dart';
import 'package:GNasCab/modules/base/components/side_menu_two_level.dart';
import 'package:GNasCab/modules/video/library_setting/models/video_library.dart';
import 'package:GNasCab/modules/video/video_main/controller/video_main_controller.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class VideoLeftMenu extends StatelessWidget {
  final VideoMainController controller;
  final bool collapsed;
  final VoidCallback? onToggleCollapse;

  const VideoLeftMenu({
    super.key,
    required this.controller,
    this.collapsed = false,
    this.onToggleCollapse,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isAdmin = CurrentUserController.instance.isAdmin;

    return Obx(() {
      // 首页 + 动态影视库栏目 + 历史 / 收藏 / 文件
      final libraryItems = <TwoLevelSideMenuItem>[
        TwoLevelSideMenuItem(
          title: 'video_menu_library_home'.tr,
          key: 'library.home',
          icon: Icons.home_outlined,
        ),
        // ⭐ 左侧栏显示**全部**影视库，不按「主页显示」过滤（2026-10-09 铁柱纠正）
        for (final lib in controller.libraries)
          TwoLevelSideMenuItem(
            title: lib.displayName,
            key: VideoMainController.libraryKeyOf(lib.id),
            icon: libTypeIcon(lib.libType),
          ),
        TwoLevelSideMenuItem(
          title: 'video_menu_library_history'.tr,
          key: 'library.history',
          icon: Icons.history,
        ),
        TwoLevelSideMenuItem(
          title: 'favorites'.tr,
          key: 'library.favorites',
          icon: Icons.favorite_outline,
        ),
        TwoLevelSideMenuItem(
          title: 'photo_menu_all_file_view'.tr,
          key: 'library.file_view',
          icon: Icons.folder_outlined,
        ),
      ];

      final groups = <SideMenuTwoLevelGroup>[
        SideMenuTwoLevelGroup(
          title: 'video_menu_library'.tr,
          icon: Icons.movie_outlined,
          expanded: controller.isLibraryExpanded,
          items: libraryItems,
        ),
        SideMenuTwoLevelGroup(
          title: 'video_menu_albums'.tr,
          icon: Icons.collections_bookmark_outlined,
          expanded: controller.isAlbumExpanded,
          items: [
            TwoLevelSideMenuItem(
              title: 'video_custom_album_title'.tr,
              key: 'albums.album',
              icon: Icons.video_collection_outlined,
            ),
            TwoLevelSideMenuItem(
              title: 'video_smart_album_title'.tr,
              key: 'albums.smart',
              icon: Icons.auto_awesome_outlined,
            ),
            TwoLevelSideMenuItem(
              title: 'video_collection_title'.tr,
              key: 'albums.collection',
              icon: Icons.collections_bookmark_outlined,
            ),
          ],
        ),
        if (isAdmin)
          SideMenuTwoLevelGroup(
            title: 'setting'.tr,
            icon: Icons.settings_outlined,
            expanded: controller.isSettingsExpanded,
            items: [
              TwoLevelSideMenuItem(
                title: 'settings_video_library'.tr,
                key: 'settings.library',
                icon: Icons.video_library_outlined,
              ),
              TwoLevelSideMenuItem(
                title: 'settings_source'.tr,
                key: 'settings.source',
                icon: Icons.folder_special_outlined,
              ),
              TwoLevelSideMenuItem(
                title: 'video_menu_settings_other'.tr,
                key: 'settings.other',
                icon: Icons.tune_outlined,
              ),
            ],
          ),
      ];

      return TwoLevelSideMenu(
        currentKey: controller.currentPageKey,
        onSelect: controller.selectPage,
        groups: groups,
        collapsed: collapsed,
        onToggleCollapse: onToggleCollapse,
        toggleExpandTooltip: 'sidebar_expand'.tr,
        toggleCollapseTooltip: 'sidebar_collapse'.tr,
        topPlaceholderHeight: 30,
        headerTrailing: Align(
          alignment: Alignment.centerLeft,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${'video_home_type_movie'.tr}:${controller.movieCount.value}',
                style: _headerStyle(theme),
                textAlign: TextAlign.right,
              ),
              Text(
                '${'video_home_type_tv'.tr}:${controller.tvCount.value}',
                style: _headerStyle(theme),
                textAlign: TextAlign.right,
              ),
            ],
          ),
        ),
      );
    });
  }

  TextStyle? _headerStyle(ThemeData theme) => theme.textTheme.bodySmall
      ?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6));
}
