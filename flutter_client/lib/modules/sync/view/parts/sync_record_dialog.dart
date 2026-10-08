part of '../sync_main_view.dart';

/// 同步运行记录弹窗
class _SyncRecordDialog extends StatefulWidget {
  final SyncTaskListController ctrl;
  final SyncTask task;

  const _SyncRecordDialog({required this.ctrl, required this.task});

  @override
  State<_SyncRecordDialog> createState() => _SyncRecordDialogState();
}

class _SyncRecordDialogState extends State<_SyncRecordDialog> {
  late Future<List<SyncRecord>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<SyncRecord>> _load() async {
    final data = await widget.ctrl.fetchRecords(taskId: widget.task.id);
    final items = data == null ? const [] : (data['items'] ?? const []);
    if (items is! List) return <SyncRecord>[];
    return items
        .whereType<Map>()
        .map((e) => SyncRecord.fromMap(Map<String, dynamic>.from(e)))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DialogUtil.createAlertDialog(
      title: Text('${'sync_records'.tr} · ${widget.task.name}'),
      constraints: const BoxConstraints(maxWidth: 640, minWidth: 360),
      content: SizedBox(
        width: 640,
        height: 420,
        child: FutureBuilder<List<SyncRecord>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final records = snapshot.data ?? const <SyncRecord>[];
            if (records.isEmpty) {
              return CustomNoData(
                text: 'sync_no_records'.tr,
                imageWidth: 100,
                imageHeight: 100,
              );
            }
            return ListView.separated(
              itemCount: records.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final r = records[index];
                final ok = r.isSuccess;
                final color = ok ? theme.colorScheme.primary : theme.colorScheme.error;
                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant
                          .withValues(alpha: 0.5),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            ok ? Icons.check_circle_outline : Icons.error_outline,
                            size: 16,
                            color: color,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            ok ? 'sync_record_success'.tr : 'sync_record_failed'.tr,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: color,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            formatTimeMs(r.startTime),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.6),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 12,
                        runSpacing: 4,
                        children: [
                          _stat(theme, 'sync_stat_upload', r.uploadCount),
                          _stat(theme, 'sync_stat_download', r.downloadCount),
                          _stat(theme, 'sync_stat_delete', r.deleteCount),
                          _stat(theme, 'sync_stat_skip', r.skipCount),
                          _stat(
                            theme,
                            'sync_stat_fail',
                            r.failCount,
                            danger: r.failCount > 0,
                          ),
                          _stat(
                            theme,
                            'sync_stat_bytes',
                            null,
                            text: formatBytes(r.bytesTransferred),
                          ),
                        ],
                      ),
                      if (r.errorList.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.errorContainer
                                .withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            r.errorList.take(5).join('\n'),
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(onPressed: () => Get.back(), child: Text('ok'.tr)),
      ],
    );
  }

  Widget _stat(
    ThemeData theme,
    String labelKey,
    int? value, {
    String? text,
    bool danger = false,
  }) {
    final color = danger
        ? theme.colorScheme.error
        : theme.colorScheme.onSurface.withValues(alpha: 0.75);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${labelKey.tr} ',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
          ),
        ),
        Text(
          text ?? (value ?? 0).toString(),
          style: theme.textTheme.bodySmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
