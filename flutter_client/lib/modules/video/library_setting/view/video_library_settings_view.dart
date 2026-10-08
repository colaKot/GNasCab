import 'package:GNasCab/core/theme/custom_colors.dart';
import 'package:GNasCab/modules/base/components/custom_bordered_icon_button.dart';
import 'package:GNasCab/modules/base/components/custom_glass_card.dart';
import 'package:GNasCab/utils/device_utils.dart';
import 'package:GNasCab/utils/dialog_util.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:GNasCab/modules/video/library_setting/controller/video_library_settings_controller.dart';
import 'package:GNasCab/modules/video/library_setting/models/video_library.dart';

const double _kBaseCardWidth = 360;
const double _kCardHeight = 210;

/// 「影视库」管理页：每个影视库对应左侧栏的一个栏目
class VideoLibrarySettingsView extends StatelessWidget {
  const VideoLibrarySettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final customColors = theme.extension<CustomColors>();
    final isNarrow = DeviceUtils.isMobile;

    return GetBuilder<VideoLibrarySettingsController>(
      init: VideoLibrarySettingsController(),
      builder: (ctrl) {
        return Container(
          color: customColors?.mainContentBgColor,
          child: isNarrow
              ? Obx(() {
                  final items = ctrl.libraries.toList();
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    children: [
                      Text(
                        'video_library_manage_title'.tr,
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'video_library_manage_desc'.tr,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.6,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      for (final lib in items) ...[
                        _LibraryCard(library: lib),
                        const SizedBox(height: 12),
                      ],
                      _MobileAddLibraryCard(
                        onTap: () => _showAddDialog(context, ctrl),
                      ),
                    ],
                  );
                })
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                      child: Row(
                        children: [
                          Text(
                            'video_library_manage_title'.tr,
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'video_library_manage_desc'.tr,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface.withValues(
                                  alpha: 0.6,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Obx(() {
                        final items = ctrl.libraries.toList();
                        return LayoutBuilder(
                          builder: (context, constraints) {
                            const paddingX = 16.0;
                            const spacing = 8.0;
                            final availableWidth =
                                (constraints.maxWidth - paddingX * 2).clamp(
                                  0,
                                  99999,
                                );
                            final count =
                                (((availableWidth + spacing) /
                                            (_kBaseCardWidth + spacing))
                                        .floor())
                                    .clamp(1, 99);

                            return GridView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: count,
                                    crossAxisSpacing: spacing,
                                    mainAxisSpacing: spacing,
                                    mainAxisExtent: _kCardHeight,
                                  ),
                              itemCount: items.length + 1,
                              itemBuilder: (context, index) {
                                if (index < items.length) {
                                  return _LibraryCard(library: items[index]);
                                }
                                return _AddLibraryCard(
                                  onTap: () => _showAddDialog(context, ctrl),
                                );
                              },
                            );
                          },
                        );
                      }),
                    ),
                  ],
                ),
        );
      },
    );
  }
}

/// 新建影视库：分类创建后不可修改
Future<void> _showAddDialog(
  BuildContext context,
  VideoLibrarySettingsController ctrl,
) async {
  final theme = Theme.of(context);
  final nameCtrl = TextEditingController();
  String libType = 'movie';

  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (ctx, setState) {
          return DialogUtil.createAlertDialog(
            title: Text('video_library_add_title'.tr),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameCtrl,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: 'video_library_name_label'.tr,
                      hintText: 'video_library_name_hint'.tr,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'video_library_type_label'.tr,
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'video_library_type_immutable'.tr,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final t in kVideoLibTypes)
                    RadioListTile<String>(
                      value: t,
                      groupValue: libType,
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      title: Text(libTypeLabelKey(t).tr),
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() => libType = v);
                      },
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text('cancel'.tr),
              ),
              ElevatedButton(
                onPressed: () async {
                  final name = nameCtrl.text.trim();
                  if (name.isEmpty) {
                    DialogUtil.showInfoDialog(
                      title: 'tip'.tr,
                      content: 'video_library_name_required'.tr,
                      buttonText: 'ok'.tr,
                    );
                    return;
                  }
                  Navigator.of(dialogContext).pop();
                  await ctrl.addLibrary(name, libType);
                },
                child: Text('video_library_add'.tr),
              ),
            ],
          );
        },
      );
    },
  );
}

Future<void> _showRenameDialog(
  VideoLibrarySettingsController ctrl,
  VideoLibrary library,
) async {
  final name = await DialogUtil.showInputDialog(
    title: 'video_library_rename_title'.tr,
    content: 'video_library_name_label'.tr,
    initialValue: library.displayName,
    confirmText: 'confirm'.tr,
    cancelText: 'cancel'.tr,
    validator: (v) => (v ?? '').trim().isEmpty
        ? 'video_library_name_required'.tr
        : null,
  );
  if (name == null) return;
  await ctrl.renameLibrary(library, name);
}

class _MobileAddLibraryCard extends StatelessWidget {
  final VoidCallback onTap;

  const _MobileAddLibraryCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CustomGlassCard(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.add_circle_outline,
              size: 20,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Text('video_library_add'.tr, style: theme.textTheme.titleSmall),
          ],
        ),
      ),
    );
  }
}

class _AddLibraryCard extends StatelessWidget {
  final VoidCallback onTap;

  const _AddLibraryCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CustomGlassCard(
      onTap: onTap,
      child: SizedBox.expand(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.add_circle_outline,
                size: 38,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 10),
              Text(
                'video_library_add'.tr,
                style: theme.textTheme.titleSmall,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LibraryCard extends StatelessWidget {
  final VideoLibrary library;

  const _LibraryCard({required this.library});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ctrl = Get.find<VideoLibrarySettingsController>();
    final sourceLabel =
        '${'video_library_source_count'.tr} ${library.sourceCount} · '
        '${library.totalCount} ${'video_library_item_count'.tr}';

    return CustomGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                libTypeIcon(library.libType),
                size: 22,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  library.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (library.isDefault)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'video_library_builtin'.tr,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            libTypeLabelKey(library.libType).tr,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            sourceLabel,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
          const Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              CustomBorderedIconButton(
                icon: Icons.edit_outlined,
                tooltip: 'video_library_rename_title'.tr,
                onTap: () => _showRenameDialog(ctrl, library),
              ),
              if (!library.isDefault) ...[
                const SizedBox(width: 8),
                CustomBorderedIconButton(
                  icon: Icons.delete_outline,
                  tooltip: 'delete'.tr,
                  onTap: () => ctrl.deleteLibrary(library),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
