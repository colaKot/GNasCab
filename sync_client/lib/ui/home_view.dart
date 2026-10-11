import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:nascab_sync_core/nascab_sync_core.dart';

import '../sync/sync_controller.dart';

/// 主页：同步任务列表。
class HomeView extends StatelessWidget {
  const HomeView({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = SyncController.instance;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: Obx(
          () => Row(
            children: [
              Image.asset(
                'assets/sync.webp',
                width: 22,
                height: 22,
                errorBuilder: (_, __, ___) => const Icon(Icons.sync, size: 20),
              ),
              const SizedBox(width: 10),
              const Text('WaterNasOS 同步'),
              const SizedBox(width: 12),
              if (ctrl.tasks.isNotEmpty)
                Text(
                  'sync_task_count'.trParams({'count': '${ctrl.tasks.length}'}),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
        ),
        actions: [
          Obx(
            () => Tooltip(
              message: ctrl.autoPaused.value
                  ? 'tray_resume_auto'.tr
                  : 'tray_pause_auto'.tr,
              child: IconButton(
                icon: Icon(
                  ctrl.autoPaused.value
                      ? Icons.play_circle_outline
                      : Icons.pause_circle_outline,
                ),
                onPressed: () async {
                  final next = !ctrl.autoPaused.value;
                  await ctrl.setAutoPaused(next);
                  Get.snackbar(
                    'app_name'.tr,
                    next ? 'sync_paused_all'.tr : 'sync_resumed_all'.tr,
                    snackPosition: SnackPosition.BOTTOM,
                    duration: const Duration(seconds: 2),
                  );
                },
              ),
            ),
          ),
          IconButton(
            tooltip: 'refresh'.tr,
            icon: const Icon(Icons.refresh),
            onPressed: () => ctrl.refreshTasks(showLoading: true),
          ),
          IconButton(
            tooltip: 'settings'.tr,
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Get.toNamed('/settings'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Obx(() {
        if (ctrl.loading.value && ctrl.tasks.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        if (ctrl.errorText.value.isNotEmpty && ctrl.tasks.isEmpty) {
          return _ErrorState(
            message: ctrl.errorText.value,
            onRetry: () => ctrl.refreshTasks(showLoading: true),
          );
        }
        if (ctrl.tasks.isEmpty) {
          return const _EmptyState();
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          itemCount: ctrl.tasks.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) =>
              _TaskCard(task: ctrl.tasks[index]),
        );
      }),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Get.toNamed('/task_edit'),
        icon: const Icon(Icons.add),
        label: Text('sync_create_task'.tr),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.cloud_sync_outlined,
            size: 56,
            color: theme.disabledColor,
          ),
          const SizedBox(height: 14),
          Text('sync_no_tasks'.tr, style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            'sync_no_tasks_desc'.tr,
            style: theme.textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined, size: 48, color: theme.disabledColor),
            const SizedBox(height: 14),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text('retry'.tr),
            ),
          ],
        ),
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({required this.task});

  final SyncTask task;

  Future<void> _run(BuildContext context) async {
    final result = await SyncController.instance.runTask(task);
    if (!context.mounted || result == null) return;
    final msg = result.ok
        ? 'sync_result_line'.trParams({
            'up': '${result.uploadCount}',
            'down': '${result.downloadCount}',
            'del': '${result.deleteCount}',
            'skip': '${result.skipCount}',
            'fail': '${result.failCount}',
          })
        : (result.error ?? 'sync_phase_failed'.tr);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _delete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('sync_delete_confirm'.tr),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('cancel'.tr),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('delete'.tr),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final err = await SyncController.instance.removeTask(task.id);
    if (!context.mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(err)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.dividerColor.withOpacity(0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
        child: Obx(() {
          final engine = SyncEngine.instance;
          final running = engine.isRunning(task.id);
          final progress = engine.progressOf(task.id);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      task.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _ModeChip(mode: task.mode),
                  const SizedBox(width: 6),
                  _StatusChip(running: running, status: task.status),
                ],
              ),
              const SizedBox(height: 10),
              _PathLine(
                icon: Icons.computer_outlined,
                text: task.localDir,
              ),
              const SizedBox(height: 4),
              _PathLine(
                icon: Icons.storage_outlined,
                text: task.remoteDir,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.schedule,
                    size: 13,
                    color: theme.textTheme.bodySmall?.color,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    task.lastSyncTime == null
                        ? 'sync_never_synced'.tr
                        : '${'sync_last_sync'.tr} ${formatTimeMs(task.lastSyncTime)}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
              if (running) ...[
                const SizedBox(height: 12),
                _ProgressBlock(progress: progress),
              ],
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () => Get.dialog(
                      _RecordsDialog(taskId: task.id, taskName: task.name),
                    ),
                    icon: const Icon(Icons.history, size: 17),
                    label: Text('sync_records'.tr),
                  ),
                  const Spacer(),
                  if (running)
                    TextButton.icon(
                      onPressed: () =>
                          SyncController.instance.cancelTask(task.id),
                      icon: const Icon(Icons.stop_circle_outlined, size: 17),
                      label: Text('sync_stop'.tr),
                    )
                  else
                    FilledButton.tonalIcon(
                      onPressed: () => _run(context),
                      icon: const Icon(Icons.play_arrow, size: 17),
                      label: Text('sync_start_now'.tr),
                    ),
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: 'edit'.tr,
                    icon: const Icon(Icons.edit_outlined, size: 19),
                    onPressed: () =>
                        Get.toNamed('/task_edit', arguments: task),
                  ),
                  IconButton(
                    tooltip: 'delete'.tr,
                    icon: const Icon(Icons.delete_outline, size: 19),
                    onPressed: () => _delete(context),
                  ),
                ],
              ),
            ],
          );
        }),
      ),
    );
  }
}

class _PathLine extends StatelessWidget {
  const _PathLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: theme.disabledColor),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text.isEmpty ? '-' : text,
            style: theme.textTheme.bodyMedium,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({required this.mode});

  final String mode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = mode == SyncMode.bidirectional
        ? theme.colorScheme.primary
        : theme.colorScheme.tertiary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        SyncMode.labelKey(mode).tr,
        style: TextStyle(fontSize: 11.5, color: color),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.running, required this.status});

  final bool running;
  final String status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final key = running ? SyncStatus.running : status;
    Color color;
    switch (key) {
      case SyncStatus.running:
        color = theme.colorScheme.primary;
        break;
      case SyncStatus.error:
        color = theme.colorScheme.error;
        break;
      case SyncStatus.paused:
        color = theme.colorScheme.tertiary;
        break;
      default:
        color = theme.disabledColor;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        SyncStatus.labelKey(key).tr,
        style: TextStyle(fontSize: 11.5, color: color),
      ),
    );
  }
}

class _ProgressBlock extends StatelessWidget {
  const _ProgressBlock({required this.progress});

  final SyncProgress? progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = progress;
    final percent = p?.percent ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                p == null ? '' : SyncPhase.labelKey(p.phase).tr,
                style: theme.textTheme.bodySmall,
              ),
            ),
            Text(
              '${(percent * 100).toStringAsFixed(0)}%',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: percent <= 0 ? null : percent,
            minHeight: 5,
          ),
        ),
        if (p != null && p.currentRelPath.isNotEmpty) ...[
          const SizedBox(height: 5),
          Text(
            p.currentRelPath,
            style: theme.textTheme.bodySmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }
}

class _RecordsDialog extends StatefulWidget {
  const _RecordsDialog({required this.taskId, required this.taskName});

  final int taskId;
  final String taskName;

  @override
  State<_RecordsDialog> createState() => _RecordsDialogState();
}

class _RecordsDialogState extends State<_RecordsDialog> {
  List<SyncRecord>? _records;

  @override
  void initState() {
    super.initState();
    Future<void>(() async {
      final list =
          await SyncController.instance.loadRecords(widget.taskId);
      if (mounted) setState(() => _records = list);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text('${widget.taskName} · ${'sync_records'.tr}'),
      content: SizedBox(
        width: 460,
        height: 320,
        child: _records == null
            ? const Center(child: CircularProgressIndicator())
            : _records!.isEmpty
                ? Center(child: Text('sync_no_records'.tr))
                : ListView.separated(
                    itemCount: _records!.length,
                    separatorBuilder: (_, __) => const Divider(height: 18),
                    itemBuilder: (context, i) {
                      final r = _records![i];
                      final ok = r.isSuccess;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                ok
                                    ? Icons.check_circle_outline
                                    : Icons.error_outline,
                                size: 16,
                                color: ok
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.error,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                ok
                                    ? 'sync_record_success'.tr
                                    : (r.status == 'stopped'
                                        ? 'sync_record_stopped'.tr
                                        : 'sync_record_failed'.tr),
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                formatTimeMs(r.startTime),
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'sync_result_line'.trParams({
                              'up': '${r.uploadCount}',
                              'down': '${r.downloadCount}',
                              'del': '${r.deleteCount}',
                              'skip': '${r.skipCount}',
                              'fail': '${r.failCount}',
                            }),
                            style: theme.textTheme.bodySmall,
                          ),
                          if (r.bytesTransferred > 0)
                            Text(
                              '${'sync_bytes'.tr} ${formatBytes(r.bytesTransferred)}',
                              style: theme.textTheme.bodySmall,
                            ),
                        ],
                      );
                    },
                  ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('close'.tr),
        ),
      ],
    );
  }
}
