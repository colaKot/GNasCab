import 'package:cross_file/cross_file.dart';
import 'package:dio/dio.dart' as dio;
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:nascab_sync_core/nascab_sync_core.dart';
import 'package:path/path.dart' as p;

import '../../../core/api/api_controller.dart';
import '../../../core/api/base_api_service.dart' show ApiResponse;
import '../../../core/api/http_client_factory.dart'
    if (dart.library.html) '../../../core/api/http_client_factory_web.dart'
    if (dart.library.io) '../../../core/api/http_client_factory_io.dart';
import '../../transfer/controllers/upload_parts/upload_core.dart';
import 'sync_api_service.dart';

/// PC 主客户端对共享同步核心的宿主实现。
///
/// 同步模块所有「客户端专属」的能力都收在这里：鉴权、上传实现、
/// 下载通道（直连 / P2P）、协议调用、文案翻译。引擎本身在
/// package:nascab_sync_core 里，与 Windows 独立同步客户端共用同一份代码。
///
/// 修改这里之前先想清楚：能放进共享包的逻辑就不要放进来。
class FlutterSyncHost implements SyncHost {
  FlutterSyncHost._();

  static final FlutterSyncHost instance = FlutterSyncHost._();

  @override
  String get baseUrl => ApiController.instance.baseUrl.trim();

  bool get _isP2pMode => baseUrl == ApiController.p2pBaseUrl;

  @override
  Future<String> resolveAccessToken() async {
    final api = ApiController.instance;
    if (api.isTokenExpiringSoon) {
      await api.refreshAuthToken();
    }
    final token = api.accessToken?.trim() ?? '';
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
    await UploadCore.processFile(
      dioClient: dioClient,
      baseUrl: baseUrl,
      token: await resolveAccessToken(),
      fileRef: XFile(filePath),
      fileName: p.basename(relPath),
      fileSize: fileSize,
      remotePath: remoteRoot,
      nameStrategy: 'overwrite',
      fileHash: fileHash,
      cancelToken: cancelToken,
      relativePath: relPath,
      fileMtimeMs: fileMtimeMs,
      onProgress: onProgress,
      onCompleted: (_) {},
    );
  }

  @override
  Future<SyncDownloadStream> sendDownload(
    http.Request request, {
    required Duration timeout,
    Future<void>? cancelFuture,
  }) async {
    // P2P 通道下由 ApiController 代发；直连时自建客户端（支持自签证书）。
    if (_isP2pMode) {
      final streamed = await ApiController.instance.sendP2pRequest(
        request,
        timeout: timeout,
        cancelFuture: cancelFuture,
      );
      return SyncDownloadStream(streamed);
    }
    final client = createHttpClient();
    try {
      final streamed = await client.send(request);
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
