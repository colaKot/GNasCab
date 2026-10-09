part of '../sync_main_view.dart';

/// 同步任务列表面板
class _SyncTaskListPanel extends StatefulWidget {
  final SyncTaskListController ctrl;
  final bool showHeader;
  final VoidCallback? onCreate;

  const _SyncTaskListPanel({
    required this.ctrl,
    this.showHeader = true,
    this.onCreate,
  });

  @override
  State<_SyncTaskListPanel> createState() => _SyncTaskListPanelState();
}

class _SyncTaskListPanelState extends State<_SyncTaskListPanel> {
  late final TextEditingController _searchCtrl;

  @override
  void initState() {
    super.initState();
    _searchCtrl = TextEditingController(text: widget.ctrl.keyword.value);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compact = DeviceUtils.isPhone(context);

    return Container(
      color: theme.scaffoldBackgroundColor,
      child: Column(
        children: [
          if (widget.showHeader) _buildHeader(context),
          Expanded(
            child: Obx(() {
              final ctrl = widget.ctrl;
              if (ctrl.isLoading.value && ctrl.tasks.isEmpty) {
                return const Center(child: CircularProgressIndicator());
              }
              if (ctrl.errorText.value.isNotEmpty && ctrl.tasks.isEmpty) {
                return CustomNoData(
                  text: ctrl.errorText.value,
                  imageWidth: 100,
                  imageHeight: 100,
                );
              }
              if (ctrl.tasks.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CustomNoData(
                        text: 'sync_no_tasks'.tr,
                        imageWidth: 120,
                        imageHeight: 120,
                      ),
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        onPressed: widget.onCreate,
                        icon: const Icon(Icons.add, size: 18),
                        label: Text('sync_create_task'.tr),
                      ),
                    ],
                  ),
                );
              }
              return RefreshIndicator(
                onRefresh: () => ctrl.refreshList(showLoading: false),
                child: ListView.builder(
                  padding: EdgeInsets.symmetric(
                    horizontal: compact ? 8 : 16,
                    vertical: 12,
                  ),
                  itemCount: ctrl.tasks.length,
                  itemBuilder: (context, index) {
                    final task = ctrl.tasks[index];
                    return _SyncTaskCard(
                      ctrl: ctrl,
                      task: task,
                      onEdit: () => _openCreateWizard(
                        context,
                        ctrl,
                        editing: task,
                      ),
                      onShowRecords: () =>
                          _showSyncRecordsDialog(context, ctrl, task),
                    );
                  },
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    return CustomGlassCard(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'sync_menu_tasks'.tr,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Obx(
                  () => Text(
                    'sync_task_count'.trParams({
                      'count': widget.ctrl.tasks.length.toString(),
                    }),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 200,
            child: CustomTextField(
              controller: _searchCtrl,
              hintText: 'search'.tr,
              prefixIcon: const Icon(Icons.search, size: 18),
              onChanged: (v) => widget.ctrl.setKeyword(v),
            ),
          ),
          const SizedBox(width: 8),
          CustomIconButton(
            icon: Icons.refresh_outlined,
            tooltip: 'refresh'.tr,
            onPressed: () => widget.ctrl.refreshList(showLoading: true),
          ),
          const SizedBox(width: 8),
          // ⭐「创建任务」在右上角，让位窗口按钮组（2026-10-09）
          Padding(
            padding: EdgeInsets.only(
              right: PcWindowScope.of(context)?.titleBarControlsWidth ?? 0,
            ),
            child: FilledButton.icon(
              onPressed: widget.onCreate,
              icon: const Icon(Icons.add, size: 18),
              label: Text('sync_create_task'.tr),
            ),
          ),
        ],
      ),
    );
  }
}
