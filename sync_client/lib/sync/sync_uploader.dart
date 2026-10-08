import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart' as dio;

/// 上传结果
class SyncUploadResult {
  /// 服务端已存在同名文件（nameStrategy=overwrite 时通常不会走到这里）
  final bool skipped;

  /// 本次实际传输的字节数
  final int bytes;

  const SyncUploadResult({this.skipped = false, this.bytes = 0});
}

/// 同步上传器（桌面版精简实现）
///
/// 只保留主客户端 `UploadCore` 的「桌面 + 直连」一支：
/// 其余 P2P 中继、Web XHR 分支与独立同步客户端无关，一并去掉。
/// 协议与主客户端完全一致：`/api/file/upload/check` + `/api/file/upload/chunk`。
class SyncUploader {
  SyncUploader._();

  static const int _maxRetries = 3;

  /// 固定覆盖同名文件：同步语义下 relPath 就是唯一身份
  static const String _nameStrategy = 'overwrite';

  /// 按文件大小选择分块大小，与主客户端 `UploadTransferHelper.calculateChunkSize` 一致。
  ///
  /// 分块大小会参与服务端上传会话的 hash，两端必须一致，否则断点续传会失效。
  static int chunkSizeFor(int fileSize) {
    if (fileSize < 200 * 1024 * 1024) return 5 * 1024 * 1024;
    if (fileSize < 500 * 1024 * 1024) return 10 * 1024 * 1024;
    if (fileSize < 1000 * 1024 * 1024) return 15 * 1024 * 1024;
    if (fileSize < 2000 * 1024 * 1024) return 20 * 1024 * 1024;
    if (fileSize < 3000 * 1024 * 1024) return 25 * 1024 * 1024;
    return 30 * 1024 * 1024;
  }

  static bool _containsTraversal(String raw) {
    final s = raw.trim().replaceAll('\\', '/');
    if (s.isEmpty) return false;
    for (final seg in s.split('/')) {
      if (seg == '..') return true;
    }
    return false;
  }

  static void _validate({
    required String remoteDir,
    required String fileName,
    required String relPath,
  }) {
    if (remoteDir.trim().isEmpty) throw Exception('NAS 目录为空');
    if (remoteDir.contains('\u0000') || _containsTraversal(remoteDir)) {
      throw Exception('NAS 目录不合法');
    }
    if (fileName.trim().isEmpty ||
        fileName.contains('/') ||
        fileName.contains('\\') ||
        fileName.contains('\u0000')) {
      throw Exception('文件名不合法');
    }
    final rel = relPath.trim();
    if (rel.isEmpty) throw Exception('文件相对路径为空');
    if (rel.contains('\u0000') || _containsTraversal(rel)) {
      throw Exception('文件相对路径不合法');
    }
    if (rel.startsWith('/') || RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(rel)) {
      throw Exception('文件相对路径不合法');
    }
  }

  static List<int> _readUploadedChunks(dynamic raw) {
    final data = raw is Map ? raw['data'] : null;
    final list = data is Map ? data['uploadedChunks'] : null;
    if (list is List) {
      return list.map((e) => int.tryParse(e.toString()) ?? -1).where((e) => e >= 0).toList();
    }
    return const <int>[];
  }

  /// 判断是否属于「文件已存在」类错误（服务端可能用 409 或 code 里的 EXIST 表达）
  static bool _isFileExists(dio.DioException e) {
    if (e.response?.statusCode == 409) return true;
    final data = e.response?.data;
    final code = data is Map ? data['code']?.toString() ?? '' : '';
    return code.toUpperCase().contains('EXIST');
  }

  /// 上传单个文件。
  ///
  /// 返回结果里 [SyncUploadResult.bytes] 是本次真实传输的字节数（不含已存在的分块）。
  static Future<SyncUploadResult> upload({
    required dio.Dio client,
    required String baseUrl,
    required String token,
    required String localPath,
    required String fileName,
    required int fileSize,
    required String remoteDir,
    required String relPath,
    required String fileHash,
    required int fileMtimeMs,
    dio.CancelToken? cancelToken,
    void Function(int increment)? onProgress,
  }) async {
    _validate(remoteDir: remoteDir, fileName: fileName, relPath: relPath);

    final chunkSize = chunkSizeFor(fileSize);
    final sessionHash = '${fileHash}_$chunkSize';
    final totalChunks = (fileSize / chunkSize).ceil();
    final authHeader = {'Authorization': 'Bearer $token'};

    // ── 1. 询问服务端已收到哪些分块（断点续传） ──
    List<int> uploaded = const <int>[];
    try {
      final checkResp = await client.post(
        '$baseUrl/api/file/upload/check',
        data: {
          'hash': sessionHash,
          'targetDir': remoteDir,
          'chunkSize': chunkSize,
          'fileName': fileName,
          'relativePath': relPath,
          'nameStrategy': _nameStrategy,
          'totalChunks': totalChunks,
          'mtimeMs': fileMtimeMs,
        },
        options: dio.Options(headers: authHeader),
        cancelToken: cancelToken,
      );
      uploaded = _readUploadedChunks(checkResp.data);
    } on dio.DioException catch (e) {
      if (_isFileExists(e)) return const SyncUploadResult(skipped: true);
      rethrow;
    }

    // ── 2. 逐块上传 ──
    final file = File(localPath);
    var processed = uploaded.length * chunkSize;
    if (processed > fileSize) processed = fileSize;

    for (var i = 0; i < totalChunks; i++) {
      if (cancelToken != null && cancelToken.isCancelled) {
        throw dio.DioException(
          requestOptions: dio.RequestOptions(path: ''),
          type: dio.DioExceptionType.cancel,
        );
      }
      if (uploaded.contains(i)) continue;

      final start = i * chunkSize;
      final end = (start + chunkSize > fileSize) ? fileSize : start + chunkSize;
      final length = end - start;
      if (length <= 0) continue;

      final formData = dio.FormData.fromMap({
        'hash': sessionHash,
        'targetDir': remoteDir,
        'chunkSize': chunkSize,
        'fileName': fileName,
        'relativePath': relPath,
        'totalChunks': totalChunks,
        'nameStrategy': _nameStrategy,
        'index': i,
        'mtimeMs': fileMtimeMs,
        'file': dio.MultipartFile.fromStream(
          () => file.openRead(start, end),
          length,
          filename: 'chunk',
        ),
      });

      var attempt = 0;
      while (true) {
        try {
          await client.post(
            '$baseUrl/api/file/upload/chunk',
            data: formData,
            options: dio.Options(headers: authHeader),
            cancelToken: cancelToken,
          );
          break;
        } on dio.DioException catch (e) {
          if (e.type == dio.DioExceptionType.cancel) rethrow;
          if (_isFileExists(e)) {
            return SyncUploadResult(skipped: true, bytes: processed);
          }
          attempt++;
          if (attempt >= _maxRetries) rethrow;
          await Future<void>.delayed(Duration(seconds: 2 * attempt));
        }
      }

      onProgress?.call(length);
      processed += length;
      // 让出事件循环，避免大批量上传时界面卡顿
      await Future<void>.delayed(Duration.zero);
    }

    return SyncUploadResult(bytes: processed);
  }
}
