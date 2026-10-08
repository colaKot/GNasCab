part of '../sync_main_view.dart';

/// 单个同步任务卡片
class _SyncTaskCard extends StatelessWidget {
  final SyncTaskListController ctrl;
  final SyncTask task;
  final VoidCallback onEdit;
  final VoidCallback onShowRecords;

  const _SyncTaskCard({
    required this.ctrl,
    required this.task,
    required this.onEdit,
    required this.onShowRecords,
  });

  Color _statusColor(ThemeData theme) {
    switch (task.status) {
      case SyncStatus.running:
        return theme.colorScheme.primary;
      case SyncStatus.error:
        return theme.colorScheme.error;
      case SyncStatus.paused:
        return theme.colorScheme.tertiary;
      default:
        return theme.colorScheme.onSurface.withValues(alpha: 0.55);
    }
  }

  Color _modeColor(ThemeData theme) {
    switch (task.mode) {
      case SyncMode.downloadOnly:
        return theme.colorScheme.tertiary;
      case SyncMode.uploadOnly:
        return theme.colorScheme.secondary;
      default:
        return theme.colorScheme.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final opLoading = ctrl.opLoadingById[task.id] == true;

    return Obx(() {
      final engineRunning = ctrl.engine.isRunning(task.id);
      final progress = ctrl.engine.progressOf(task.id);
      final running = engineRunning ||
          (progress != null && !progress.isFinished) ||
          task.status == SyncStatus.running;

      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: CustomGlassCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.sync, size: 20, color: _modeColor(theme)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      task.name,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  _chip(
                    context,
                    text: SyncMode.labelKey(task.mode).tr,
                    color: _modeColor(theme),
                  ),
                  const SizedBox(width: 6),
                  _chip(
                    context,
                    text: SyncStatus.labelKey(task.status).tr,
                    color: _statusColor(theme),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _pathRow(
                context,
                icon: Icons.computer_outlined,
                label: 'sync_local_dir'.tr,
                value: task.localDir,
              ),
              const SizedBox(height: 6),
              _pathRow(
                context,
                icon: Icons.dns_outlined,
                label: 'sync_remote_dir'.tr,
                value: task.remoteDir,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(
                    Icons.schedule,
                    size: 14,
                    color: scheme.onSurface.withValues(alpha: 0.55),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${'sync_last_sync'.tr}: ${formatTimeMs(task.lastSyncTime)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  const Spacer(),
                  if (task.lastError.trim().isNotEmpty)
                    Flexible(
                      child: Text(
                        task.lastError.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.error,
                        ),
                      ),
                    ),
                ],
              ),
              if (running) ...[
                const SizedBox(height: 12),
                _buildProgress(context, progress),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _syncConfigSummary(task),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.55),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (running)
                    TextButton.icon(
                      onPressed: () => ctrl.stopSync(task.id),
                      icon: const Icon(Icons.stop_circle_outlined, size: 18),
                      label: Text('sync_stop'.tr),
                    )
                  else
                    FilledButton.tonalIcon(
                      onPressed: opLoading ? null : () => ctrl.startSync(task),
                      icon: opLoading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.play_arrow, size: 18),
                      label: Text('sync_start_now'.tr),
                    ),
                  const SizedBox(width: 4),
                  CustomIconButton(
                    icon: Icons.history,
                    tooltip: 'sync_records'.tr,
                    onPressed: onShowRecords,
                    buttonSize: 36,
                    iconSize: 18,
                  ),
                  CustomIconButton(
                    icon: Icons.edit_outlined,
                    tooltip: 'edit'.tr,
                    onPressed: running ? null : onEdit,
                    buttonSize: 36,
                    iconSize: 18,
                  ),
                  CustomIconButton(
                    icon: Icons.delete_outline,
                    tooltip: 'delete'.tr,
                    onPressed: running ? null : () => ctrl.remove(id: task.id),
                    buttonSize: 36,
                    iconSize: 18,
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    });
  }

  Widget _buildProgress(BuildContext context, SyncProgress? progress) {
    final theme = Theme.of(context);
    final phase = progress?.phase ?? SyncPhase.scanning;
    final percent = progress?.percent ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: percent > 0 ? percent : null,
            minHeight: 6,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Text(
                SyncPhase.labelKey(phase).tr,
                style: theme.textTheme.bodySmall,
              ),
            ),
            if ((progress?.currentRelPath ?? '').isNotEmpty)
              Flexible(
                child: Text(
                  progress!.currentRelPath,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color:
                        theme.colorScheme.onSurface.withValues(alpha: 0.55),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _pathRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
  }) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(
          icon,
          size: 14,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 78,
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
            ),
          ),
        ),
        Expanded(
          child: Tooltip(
            message: value,
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ),
      ],
    );
  }

  Widget _chip(
    BuildContext context, {
    required String text,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: color, fontWeight: FontWeight.w500),
      ),
    );
  }

  /// 同步策略摘要，例如「按需同步 · 每30分钟」
  String _syncConfigSummary(SyncTask task) {
    final parts = <String>[];
    if (task.syncConfig.realtime) {
      parts.add('sync_realtime'.tr);
    }
    if (task.syncConfig.intervalMinutes > 0) {
      parts.add(
        'sync_interval_every'.trParams({
          'minutes': task.syncConfig.intervalMinutes.toString(),
        }),
      );
    }
    if (task.syncConfig.deleteExtra && task.mode == SyncMode.bidirectional) {
      parts.add('sync_delete_extra'.tr);
    }
    if (parts.isEmpty) parts.add('sync_manual_only'.tr);
    return parts.join(' · ');
  }
}
