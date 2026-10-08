import 'package:dio/dio.dart' as dio;
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:nascab_sync_core/nascab_sync_core.dart';
import 'package:path/path.dart' as p;

import '../core/api.dart';
import '../core/session.dart';
import 'sync_api_service.dart';
import 'sync_uploader.dart';

/// Windows 独立同步客户端对共享同步核心的宿主实现。
///
/// 对端是 flutter_client 里的 `FlutterSyncHost`：同一个 [SyncHost] 接口，
/// 两份不同的宿主实现。同步引擎、模型、扫描、基线、调度、协议定义
/// 全部来自 package:nascab_sync_core，这里只保留真正平台相关的部分。
class DesktopSyncHost implements SyncHost {
  DesktopSyncHost._();

  static final DesktopSyncHost instance = DesktopSyncHost._();

  @override
  String get baseUrl => SyncHttp.baseUrl.trim();

  @override
  Future<String> resolveAccessToken() async {
    final session = Get.find<SessionController>();
    var token = session.accessToken?.trim() ?? '';
    if (token.isEmpty) {
      // 独立客户端无人值守，token 失效就地刷新，刷新失败才抛错
      final ok = await session.refresh();
      if (!ok) throw Exception('session_expired'.tr);
      token = session.accessToken?.trim() ?? '';
    }
    if (token.isEmpty) throw Exception('network_failure'.tr);
    return token;
  }

  @override
  String message(String key) => key.tr;

  @override
  Future<void> uploadFile({
    required dio.Dio dioClient,
    required String filePath,
    required String relPath,
    required String remoteRoot,
    required int fileSize,
    required int fileMtimeMs,
    required String fileHash,
    required dio.CancelToken cancelToken,
    required void Function(int increment) onProgress,
  }) async {
    await SyncUploader.upload(
      client: dioClient,
      baseUrl: baseUrl,
      token: await resolveAccessToken(),
      localPath: filePath,
      fileName: p.basename(relPath),
      fileSize: fileSize,
      remoteDir: remoteRoot,
      relPath: relPath,
      fileHash: fileHash,
      fileMtimeMs: fileMtimeMs,
      cancelToken: cancelToken,
      onProgress: onProgress,
    );
  }

  @override
  Future<SyncDownloadStream> sendDownload(
    http.Request request, {
    required Duration timeout,
    Future<void>? cancelFuture,
  }) async {
    // 独立客户端只走直连：桌面程序没有 P2P 通道，
    // 请求中途取消由引擎侧检查 cancelToken 完成（http 包不支持中断已发请求）。
    final client = createSyncHttpClient();
    try {
      final streamed = await client.send(request).timeout(timeout);
      return SyncDownloadStream(streamed, client.close);
    } catch (_) {
      client.close();
      rethrow;
    }
  }

  @override
  Future<SyncApiResult> plan({
    required int id,
    required List<LocalFileEntry> localFiles,
    required List<LocalFileEntry> baselineFiles,
    int? maxListPerType,
  }) async {
    final r = await SyncApiService.instance.plan(
      id: id,
      localFiles: localFiles,
      baselineFiles: baselineFiles,
      maxListPerType: maxListPerType,
    );
    return _wrap(r);
  }

  @override
  Future<SyncApiResult> deleteRemote({
    required int id,
    required List<String> relPaths,
  }) async {
    final r =
        await SyncApiService.instance.deleteRemote(id: id, relPaths: relPaths);
    return _wrap(r);
  }

  @override
  Future<SyncApiResult> report({
    required int id,
    required int startTime,
    required int endTime,
    required String status,
    int uploadCount = 0,
    int downloadCount = 0,
    int deleteCount = 0,
    int skipCount = 0,
    int failCount = 0,
    int bytesTransferred = 0,
    List<String> errorList = const [],
  }) async {
    final r = await SyncApiService.instance.report(
      id: id,
      startTime: startTime,
      endTime: endTime,
      status: status,
      uploadCount: uploadCount,
      downloadCount: downloadCount,
      deleteCount: deleteCount,
      skipCount: skipCount,
      failCount: failCount,
      bytesTransferred: bytesTransferred,
      errorList: errorList,
    );
    return _wrap(r);
  }

  SyncApiResult _wrap(ApiResponse<Map<String, dynamic>> r) => SyncApiResult(
        success: r.success,
        message: r.message,
        data: r.data,
      );
}
