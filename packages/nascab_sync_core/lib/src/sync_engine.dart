import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart' as dio;
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'sync_host.dart';
import 'sync_local_scanner.dart';
import 'sync_local_store.dart';
import 'sync_models.dart';

/// 同步阶段
class SyncPhase {
  static const String scanning = 'scanning';
  static const String planning = 'planning';
  static const String transferring = 'transferring';
  static const String cleaning = 'cleaning';
  static const String reporting = 'reporting';
  static const String done = 'done';
  static const String failed = 'failed';

  static String labelKey(String phase) {
    switch (phase) {
      case scanning:
        return 'sync_phase_scanning';
      case planning:
        return 'sync_phase_planning';
      case transferring:
        return 'sync_phase_transferring';
      case cleaning:
        return 'sync_phase_cleaning';
      case reporting:
        return 'sync_phase_reporting';
      case failed:
        return 'sync_phase_failed';
      case done:
      default:
        return 'sync_phase_done';
    }
  }
}

/// 单个任务的运行进度
class SyncProgress {
  final String phase;
  final int total;
  final int done;
  final int bytesDone;
  final int bytesTotal;
  final String currentRelPath;
  final String? error;

  const SyncProgress({
    this.phase = SyncPhase.scanning,
    this.total = 0,
    this.done = 0,
    this.bytesDone = 0,
    this.bytesTotal = 0,
    this.currentRelPath = '',
    this.error,
  });

  bool get isFinished => phase == SyncPhase.done || phase == SyncPhase.failed;

  double get percent {
    if (bytesTotal > 0) {
      final v = bytesDone / bytesTotal;
      return v.clamp(0.0, 1.0);
    }
    if (total > 0) {
      final v = done / total;
      return v.clamp(0.0, 1.0);
    }
    return 0;
  }

  SyncProgress copyWith({
    String? phase,
    int? total,
    int? done,
    int? bytesDone,
    int? bytesTotal,
    String? currentRelPath,
    String? error,
  }) {
    return SyncProgress(
      phase: phase ?? this.phase,
      total: total ?? this.total,
      done: done ?? this.done,
      bytesDone: bytesDone ?? this.bytesDone,
      bytesTotal: bytesTotal ?? this.bytesTotal,
      currentRelPath: currentRelPath ?? this.currentRelPath,
      error: error ?? this.error,
    );
  }
}

/// 一轮同步的结果统计
class SyncRunResult {
  final bool ok;
  final String? error;
  final int uploadCount;
  final int downloadCount;
  final int deleteCount;
  final int skipCount;
  final int failCount;
  final int bytesTransferred;
  final List<String> errors;

  const SyncRunResult({
    required this.ok,
    this.error,
    this.uploadCount = 0,
    this.downloadCount = 0,
    this.deleteCount = 0,
    this.skipCount = 0,
    this.failCount = 0,
    this.bytesTransferred = 0,
    this.errors = const [],
  });
}

/// 同步执行引擎
///
/// 运行在客户端（主动连接 NAS），服务端负责扫描 NAS 目录并给出同步计划。
/// 关键约定：上传与下载都要保留文件修改时间，使两端 mtime 对齐，
/// 否则下一轮比对会把「时间戳不同」误判为「内容被修改」，导致反复传输。
class SyncEngine {
  static final SyncEngine instance = SyncEngine._();
  SyncEngine._();

  static const int _md5ThresholdBytes = 50 * 1024 * 1024;

  final RxMap<int, SyncProgress> progressMap = <int, SyncProgress>{}.obs;

  final Set<int> _runningTaskIds = <int>{};
  final Map<int, dio.CancelToken> _cancelTokens = <int, dio.CancelToken>{};

  dio.Dio? _dio;

  dio.Dio get _client {
    if (_dio != null) return _dio!;
    _dio = dio.Dio(
      dio.BaseOptions(
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(minutes: 30),
        sendTimeout: const Duration(minutes: 30),
        validateStatus: (_) => true,
      ),
    );
    return _dio!;
  }

  bool isRunning(int taskId) => _runningTaskIds.contains(taskId);

  SyncProgress? progressOf(int taskId) => progressMap[taskId];

  void cancel(int taskId) {
    _cancelTokens[taskId]?.cancel('user_cancel');
    _cancelTokens.remove(taskId);
  }

  void _setProgress(int taskId, SyncProgress value) {
    progressMap[taskId] = value;
  }

  void clearProgress(int taskId) {
    progressMap.remove(taskId);
  }

  /// 宿主能力入口。鉴权、上传、下载通道、协议调用全部由宿主实现，
  /// 引擎本身不 import 任何客户端代码。
  SyncHost get _host => SyncHostHolder.instance;

  void _throwIfCancelled(dio.CancelToken? token) {
    if (token != null && token.isCancelled) {
      throw dio.DioException(
        requestOptions: dio.RequestOptions(path: ''),
        type: dio.DioExceptionType.cancel,
      );
    }
  }

  /// 执行一轮同步
  Future<SyncRunResult> run(SyncTask task) async {
    if (_runningTaskIds.contains(task.id)) {
      return const SyncRunResult(ok: false, error: 'sync_already_running');
    }
    _runningTaskIds.add(task.id);
    final cancelToken = dio.CancelToken();
    _cancelTokens[task.id] = cancelToken;

    final startedAt = DateTime.now().millisecondsSinceEpoch;
    var uploadCount = 0;
    var downloadCount = 0;
    var deleteCount = 0;
    var skipCount = 0;
    var failCount = 0;
    var bytesTransferred = 0;
    final errors = <String>[];

    try {
      _setProgress(task.id, const SyncProgress(phase: SyncPhase.scanning));

      // 1. 扫描本地目录
      final scan = await SyncLocalScanner.scan(task.localDir, task.filterConfig);
      final localFiles = scan.files;
      _throwIfCancelled(cancelToken);

      // 2. 读取基线（上一次同步结束时的本地状态）
      final baseline = await SyncLocalStore.instance.loadBaseline(task.id);

      // 3. 请求同步计划
      _setProgress(
        task.id,
        SyncProgress(phase: SyncPhase.planning, total: localFiles.length),
      );
      final planResp = await _host.plan(
        id: task.id,
        localFiles: localFiles,
        baselineFiles: baseline,
      );
      if (!planResp.success || planResp.data == null) {
        final msg = planResp.message ?? _host.message('sync_plan_failed');
        _setProgress(
          task.id,
          SyncProgress(phase: SyncPhase.failed, error: msg),
        );
        await _report(
          task: task,
          startedAt: startedAt,
          status: 'failed',
          failCount: 1,
          errors: [msg],
        );
        return SyncRunResult(ok: false, error: msg, failCount: 1);
      }

      final plan = SyncPlan.fromMap(planResp.data!);
      skipCount = plan.count('skip');

      final bytesTotal = plan.count('uploadBytes') + plan.count('downloadBytes');
      var bytesDone = 0;
      final totalActions = plan.totalActions;
      var doneActions = 0;

      void bumpBytes(int delta) => bytesDone += delta;

      final remoteRoot = plan.remoteDir.isNotEmpty ? plan.remoteDir : task.remoteDir;

      // 4. 上传
      for (final item in plan.upload) {
        _throwIfCancelled(cancelToken);
        _setProgress(
          task.id,
          SyncProgress(
            phase: SyncPhase.transferring,
            total: totalActions,
            done: doneActions,
            bytesTotal: bytesTotal,
            bytesDone: bytesDone,
            currentRelPath: item.relPath,
          ),
        );
        try {
          final localPath = _safeLocalPath(task.localDir, item.relPath);
          if (localPath == null) {
            failCount++;
            errors.add('${item.relPath}: invalid_path');
            doneActions++;
            continue;
          }
          final file = File(localPath);
          if (!await file.exists()) {
            skipCount++;
            continue;
          }
          final stat = await file.stat();
          final hash = sha256
              .convert(utf8.encode(
                  '${task.id}|${item.relPath}|${stat.size}|${stat.modified.millisecondsSinceEpoch}'))
              .toString();

          await _host.uploadFile(
            dioClient: _client,
            filePath: localPath,
            relPath: item.relPath,
            remoteRoot: remoteRoot,
            fileSize: stat.size,
            fileMtimeMs: stat.modified.millisecondsSinceEpoch,
            fileHash: hash,
            cancelToken: cancelToken,
            onProgress: (increment) {
              bumpBytes(increment);
              _setProgress(
                task.id,
                SyncProgress(
                  phase: SyncPhase.transferring,
                  total: totalActions,
                  done: doneActions,
                  bytesTotal: bytesTotal,
                  bytesDone: bytesDone,
                  currentRelPath: item.relPath,
                ),
              );
            },
          );
          uploadCount++;
          bytesTransferred += stat.size;
        } catch (e) {
          failCount++;
          errors.add('${item.relPath}: $e');
          if (_isCancelError(e)) _throwIfCancelled(cancelToken);
        }
        doneActions++;
      }

      // 5. 下载
      for (final item in plan.download) {
        _throwIfCancelled(cancelToken);
        _setProgress(
          task.id,
          SyncProgress(
            phase: SyncPhase.transferring,
            total: totalActions,
            done: doneActions,
            bytesTotal: bytesTotal,
            bytesDone: bytesDone,
            currentRelPath: item.relPath,
          ),
        );
        try {
          final localPath = _safeLocalPath(task.localDir, item.relPath);
          if (localPath == null) {
            failCount++;
            errors.add('${item.relPath}: invalid_path');
            doneActions++;
            continue;
          }
          final remotePath = p.posix.join(remoteRoot, item.relPath);
          final bytesBeforeDownload = bytesDone;
          final received = await _downloadFile(
            remotePath: remotePath,
            localFullPath: localPath,
            cancelToken: cancelToken,
            remoteMtimeMs: item.mtimeMs,
            onProgress: (receivedNow) {
              bytesDone = bytesBeforeDownload + receivedNow;
              _setProgress(
                task.id,
                SyncProgress(
                  phase: SyncPhase.transferring,
                  total: totalActions,
                  done: doneActions,
                  bytesTotal: bytesTotal,
                  bytesDone: bytesDone,
                  currentRelPath: item.relPath,
                ),
              );
            },
          );
          downloadCount++;
          bytesTransferred += received;
        } catch (e) {
          failCount++;
          errors.add('${item.relPath}: $e');
          if (_isCancelError(e)) _throwIfCancelled(cancelToken);
        }
        doneActions++;
      }

      // 6. 清理（删除传播）
      if (plan.deleteRemote.isNotEmpty || plan.deleteLocal.isNotEmpty) {
        _setProgress(
          task.id,
          SyncProgress(
            phase: SyncPhase.cleaning,
            total: totalActions,
            done: doneActions,
            bytesTotal: bytesTotal,
            bytesDone: bytesDone,
          ),
        );
      }

      for (final rel in plan.deleteLocal) {
        try {
          final localPath = _safeLocalPath(task.localDir, rel);
          if (localPath == null) {
            failCount++;
            errors.add('$rel: invalid_path');
            continue;
          }
          final file = File(localPath);
          if (await file.exists()) {
            await file.delete();
            deleteCount++;
          }
        } catch (e) {
          failCount++;
          errors.add('$rel: $e');
        }
      }

      if (plan.deleteRemote.isNotEmpty) {
        try {
          final resp =
              await _host.deleteRemote(id: task.id, relPaths: plan.deleteRemote);
          if (resp.success && resp.data != null) {
            final deleted = int.tryParse(resp.data!['deleted']?.toString() ?? '') ?? 0;
            deleteCount += deleted;
            final failed = resp.data!['failed'];
            if (failed is List && failed.isNotEmpty) {
              failCount += failed.length;
            }
          } else {
            failCount += plan.deleteRemote.length;
            errors.add(resp.message ?? _host.message('sync_delete_remote_failed'));
          }
        } catch (e) {
          failCount += plan.deleteRemote.length;
          errors.add('$e');
        }
      }

      // 7. 回写结果
      _setProgress(
        task.id,
        SyncProgress(
          phase: SyncPhase.reporting,
          total: totalActions,
          done: totalActions,
          bytesTotal: bytesTotal,
          bytesDone: bytesDone,
        ),
      );
      final status = failCount > 0 ? 'failed' : 'success';
      await _report(
        task: task,
        startedAt: startedAt,
        status: status,
        uploadCount: uploadCount,
        downloadCount: downloadCount,
        deleteCount: deleteCount,
        skipCount: skipCount,
        failCount: failCount,
        bytesTransferred: bytesTransferred,
        errors: errors,
      );

      // 8. 重新扫描本地，保存为新基线
      final rescan = await SyncLocalScanner.scan(task.localDir, task.filterConfig);
      await SyncLocalStore.instance.saveBaseline(task.id, rescan.files);

      _setProgress(
        task.id,
        SyncProgress(
          phase: SyncPhase.done,
          total: totalActions,
          done: totalActions,
          bytesTotal: bytesTotal,
          bytesDone: bytesDone,
        ),
      );

      return SyncRunResult(
        ok: failCount == 0,
        uploadCount: uploadCount,
        downloadCount: downloadCount,
        deleteCount: deleteCount,
        skipCount: skipCount,
        failCount: failCount,
        bytesTransferred: bytesTransferred,
        errors: errors,
      );
    } catch (e) {
      final cancelled = _isCancelError(e);
      final msg = cancelled ? _host.message('sync_cancelled') : e.toString();
      _setProgress(task.id, SyncProgress(phase: SyncPhase.failed, error: msg));
      try {
        await _report(
          task: task,
          startedAt: startedAt,
          status: 'stopped',
          uploadCount: uploadCount,
          downloadCount: downloadCount,
          deleteCount: deleteCount,
          skipCount: skipCount,
          failCount: failCount + 1,
          bytesTransferred: bytesTransferred,
          errors: [msg],
        );
      } catch (_) {}
      return SyncRunResult(
        ok: false,
        error: msg,
        uploadCount: uploadCount,
        downloadCount: downloadCount,
        deleteCount: deleteCount,
        failCount: failCount + 1,
      );
    } finally {
      _runningTaskIds.remove(task.id);
      _cancelTokens.remove(task.id);
    }
  }

  /// 将服务端返回的相对路径安全地拼接到本地根目录，阻断目录穿越
  String? _safeLocalPath(String rootDir, String relPath) {
    final rel = relPath.replaceAll('\\', '/').trim();
    if (rel.isEmpty) return null;
    final parts = rel.split('/');
    for (final seg in parts) {
      if (seg.isEmpty || seg == '.' || seg == '..') return null;
    }
    return p.joinAll([rootDir, ...parts]);
  }

  bool _isCancelError(Object e) {
    if (e is dio.DioException) {
      return e.type == dio.DioExceptionType.cancel;
    }
    final s = e.toString().toLowerCase();
    return s.contains('cancel');
  }

  Future<void> _report({
    required SyncTask task,
    required int startedAt,
    required String status,
    int uploadCount = 0,
    int downloadCount = 0,
    int deleteCount = 0,
    int skipCount = 0,
    int failCount = 0,
    int bytesTransferred = 0,
    List<String> errors = const [],
  }) async {
    try {
      await _host.report(
        id: task.id,
        startTime: startedAt,
        endTime: DateTime.now().millisecondsSinceEpoch,
        status: status,
        uploadCount: uploadCount,
        downloadCount: downloadCount,
        deleteCount: deleteCount,
        skipCount: skipCount,
        failCount: failCount,
        bytesTransferred: bytesTransferred,
        errorList: errors.take(200).toList(),
      );
    } catch (e) {
      print('回写同步结果失败: $e');
    }
  }

  /// 打开下载流。
  ///
  /// 只有「怎么把请求发出去」属于宿主（直连还是 P2P 通道、用哪个 http client），
  /// 落盘、临时文件、修改时间对齐等逻辑全部在这里共享。
  Future<SyncDownloadStream> _openDownloadStream(
    String remotePath,
    dio.CancelToken cancelToken,
  ) async {
    final token = await _host.resolveAccessToken();
    _throwIfCancelled(cancelToken);
    final uri = Uri.parse('${_host.baseUrl}/api/file/download')
        .replace(queryParameters: {'path': remotePath});
    final req = http.Request('GET', uri);
    req.headers['authorization'] = 'Bearer $token';
    req.headers['accept'] = '*/*';
    return _host.sendDownload(
      req,
      timeout: const Duration(minutes: 30),
      cancelFuture: cancelToken.whenCancel,
    );
  }

  /// 下载单个文件，并保留远端修改时间
  Future<int> _downloadFile({
    required String remotePath,
    required String localFullPath,
    required dio.CancelToken cancelToken,
    required int remoteMtimeMs,
    required void Function(int received) onProgress,
  }) async {
    final target = File(localFullPath);
    await target.parent.create(recursive: true);
    final tmp = File('$localFullPath.synctmp');
    if (await tmp.exists()) {
      await tmp.delete();
    }

    final sink = tmp.openWrite();
    var received = 0;
    SyncDownloadStream? stream;
    try {
      stream = await _openDownloadStream(remotePath, cancelToken);
      final streamed = stream.response;

      if (streamed.statusCode != 200) {
        throw Exception('HTTP ${streamed.statusCode}');
      }

      await for (final chunk in streamed.stream) {
        if (cancelToken.isCancelled) {
          throw dio.DioException(
            requestOptions: dio.RequestOptions(path: ''),
            type: dio.DioExceptionType.cancel,
          );
        }
        sink.add(chunk);
        received += chunk.length;
        onProgress(received);
      }
    } catch (e) {
      await sink.flush().catchError((_) {});
      await sink.close().catchError((_) {});
      if (await tmp.exists()) {
        await tmp.delete().catchError((_) => tmp);
      }
      rethrow;
    } finally {
      stream?.dispose?.call();
    }

    await sink.flush();
    await sink.close();

    if (await target.exists()) {
      await target.delete();
    }
    await tmp.rename(localFullPath);

    if (remoteMtimeMs > 0) {
      try {
        await File(localFullPath).setLastModified(
          DateTime.fromMillisecondsSinceEpoch(remoteMtimeMs),
        );
      } catch (e) {
        print('设置本地文件修改时间失败: $e');
      }
    }

    return received;
  }
}
