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
      // ⭐ 只显示「有内容」的影视库（2026-10-09）：
      //   ① 库本身没内容（还没扫描 / 没配来源）
      //   ② 子账号对该库的**所有来源都没有权限**
      //      —— 服务端 counts 是按「用户可见路径」统计的，无权时天然就是 0
      //   两种情况都表现为 totalCount == 0，所以一个条件就够。
      //   ⚠️ 不要用 sourceCount 判断：它只表示「该库配了几个来源」，
      //      子账号没有权限时它依然 > 0，判不出来。
      //   ⛔ 这里**不做「全空则回退显示全部」的兜底**：那会在子账号对本模块所有库
      //      都无权限时，把全部库（含无权库）重新放出来 —— 正是本需求要避免的行为。
      //      库列表全空时左侧栏仍有「首页 / 历史 / 收藏 / 文件浏览」可用，不会整栏空白。
      final visibleLibs = controller.libraries
          .where((l) => l.totalCount > 0)
          .toList();

      // 首页 + 动态影视库栏目 + 历史 / 收藏 / 文件
      final libraryItems = <TwoLevelSideMenuItem>[
        TwoLevelSideMenuItem(
          title: 'video_menu_library_home'.tr,
          key: 'library.home',
          icon: Icons.home_outlined,
        ),
        // 左侧栏按「有内容 + 有权限」过滤，但**不受「主页显示」开关影响**
        // （2026-10-09 铁柱纠正：左侧栏不管有没有开主页显示都要显示）。
        for (final lib in visibleLibs)
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
