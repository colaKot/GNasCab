import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../base/components/custom_hover_select_menu.dart';
import '../../../../base/components/custom_bordered_icon_button.dart';
import '../../../../base/components/custom_expandable_search_bar.dart';
import '../../../../home/views/pc_components/pc_app_window.dart';
import '../../../../../core/user/current_user_controller.dart';
import '../../controller/ai_faces_controller.dart';

class AiFacesTopBar extends StatelessWidget {
  final AiFacesController controller;
  const AiFacesTopBar({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final isAdmin = CurrentUserController.instance.isAdmin;
    // ⭐ 右侧给窗口按钮组让位（2026-10-09）：刷新/搜索按钮贴最右
    final ctrlW = PcWindowScope.of(context)?.titleBarControlsWidth ?? 0;
    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16 + ctrlW, 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final filter = Obx(() {
            final v = controller.statusFilter.value;
            return CustomHoverSelectMenu<String>(
              value: v,
              height: 44,
              buttonIcon: Icons.filter_alt_outlined,
              items: [
                CustomHoverSelectMenuItem(
                  value: 'visiable',
                  label: 'face_filter_visible'.tr,
                  icon: Icons.visibility,
                ),
                CustomHoverSelectMenuItem(
                  value: 'hide',
                  label: 'face_filter_hidden'.tr,
                  icon: Icons.visibility_off,
                ),
                CustomHoverSelectMenuItem(
                  value: 'all',
                  label: 'all'.tr,
                  icon: Icons.filter_alt_outlined,
                ),
              ],
              onSelected: controller.setStatusFilter,
            );
          });

          final buttons = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isAdmin)
                CustomBorderedIconButton(
                  icon: Icons.settings,
                  tooltip: 'setting'.tr,
                  onTap: controller.openAutoHideSettings,
                ),
              const SizedBox(width: 6),
              if (isAdmin)
                CustomBorderedIconButton(
                  icon: Icons.clear_all,
                  tooltip: 'reset'.tr,
                  onTap: controller.confirmAndResetFaces,
                ),
              const SizedBox(width: 6),
              CustomBorderedIconButton(
                icon: Icons.refresh,
                tooltip: 'refresh'.tr,
                onTap: controller.refreshFaces,
              ),
              const SizedBox(width: 6),
              CustomExpandableSearchBar(
                controller: controller.searchController,
                hintText: 'face_search_hint'.tr,
                onChanged: controller.updateKeyword,
                onClear: controller.clearKeyword,
              ),
            ],
          );

          return Row(children: [filter, const Spacer(), buttons]);
        },
      ),
    );
  }
}
