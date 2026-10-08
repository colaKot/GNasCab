import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// 创建 HTTP 客户端。
///
/// NAS 常用自签名证书的 HTTPS，这里放开校验，行为与主客户端一致。
http.Client createSyncHttpClient() {
  final ioClient = HttpClient();
  ioClient.badCertificateCallback =
      (X509Certificate cert, String host, int port) => true;
  ioClient.connectionTimeout = const Duration(seconds: 15);
  return IOClient(ioClient);
}

/// 统一响应结构，与服务端 `{ success, message, data }` 对齐。
class ApiResponse<T> {
  final bool success;
  final T? data;
  final String? message;
  final int? code;
  final String? apiErrorKey;

  ApiResponse({
    required this.success,
    this.data,
    this.message,
    this.code,
    this.apiErrorKey,
  });

  factory ApiResponse.failure(
    String message, {
    int? code,
    String? apiErrorKey,
  }) =>
      ApiResponse<T>(
        success: false,
        message: message,
        code: code,
        apiErrorKey: apiErrorKey,
      );

  factory ApiResponse.fromJson(
    int httpStatus,
    Map<String, dynamic> json, {
    T Function(Map<String, dynamic>)? dataParser,
  }) {
    final rawSuccess = json['success'];
    final success = rawSuccess == true ||
        rawSuccess == 'true' ||
        json['code'] == 0 ||
        json['code'] == '0';

    String? apiErrorKey;
    final rawBizCode = json['code'];
    if (rawBizCode is String && rawBizCode.isNotEmpty) {
      apiErrorKey = rawBizCode;
    }

    T? data;
    if (success && dataParser != null) {
      try {
        data = dataParser(
          json['data'] is Map
              ? Map<String, dynamic>.from(json['data'] as Map)
              : <String, dynamic>{},
        );
      } catch (e) {
        return ApiResponse.failure(
          '数据解析失败：$e',
          code: httpStatus,
          apiErrorKey: apiErrorKey,
        );
      }
    } else {
      final raw = json['data'];
      if (raw is T) {
        data = raw;
      }
    }

    return ApiResponse<T>(
      success: success,
      data: data,
      message: _localizeMessage(apiErrorKey, json['message']?.toString()),
      code: httpStatus,
      apiErrorKey: apiErrorKey,
    );
  }
}

/// 服务端的 `message` 是 i18n key，这里做一层中文兜底。
String? _localizeMessage(String? key, String? serverMessage) {
  if (key != null && key.isNotEmpty) {
    final hit = _errorMessages[key];
    if (hit != null) return hit;
  }
  if (serverMessage != null && serverMessage.trim().isNotEmpty) {
    final s = serverMessage.trim();
    final hit = _errorMessages[s];
    if (hit != null) return hit;
    return s;
  }
  return null;
}

const Map<String, String> _errorMessages = {
  // 鉴权
  'auth.LOGIN_FAILED': '账号或密码错误',
  'auth.USER_NOT_FOUND': '账号不存在',
  'auth.PASSWORD_ERROR': '密码错误',
  'auth.INVALID_TOKEN': '登录状态无效，请重新登录',
  'auth.TOKEN_EXPIRED': '登录已过期，请重新登录',
  'auth.ACCOUNT_DISABLED': '账号已被禁用',
  'auth.REFRESH_TOKEN_REQUIRED': '登录状态已失效，请重新登录',
  'USERNAME_REQUIRED': '请输入账号',
  'PASSWORD_REQUIRED': '请输入密码',
  // 同步
  'sync.REMOTE_DIR_REQUIRED': '请先选择 NAS 目录',
  'sync.REMOTE_DIR_INVALID': 'NAS 目录路径不合法',
  'sync.REMOTE_DIR_NOT_FOUND': 'NAS 目录不存在',
  'sync.REMOTE_DIR_NOT_DIRECTORY': '选中的 NAS 路径不是文件夹',
  'sync.REL_PATH_INVALID': '文件相对路径不合法',
  'sync.TASK_NOT_FOUND': '同步任务不存在',
  'sync.TASK_REQUIRED': '请先补全任务信息',
  // 通用
  'validation.VALIDATION_ERROR': '请求参数不合法',
  'common.ERROR': '服务器内部错误',
};

/// 极简 HTTP 封装：只做 JSON POST + Bearer 鉴权 + 401 自动刷新重试。
///
/// 不引入主客户端那套弹窗 / 2FA / 路由跳转逻辑，因为独立同步客户端
/// 是无人值守的托盘程序，出错只落日志并向上抛。
class SyncHttp {
  SyncHttp._();

  /// 当前服务器地址，由 [SessionController] 注入
  static String baseUrl = '';

  /// 取当前 accessToken
  static Future<String?> Function()? tokenProvider;

  /// 刷新 token，返回是否成功
  static Future<bool> Function()? tokenRefresher;

  /// 刷新失败时回调（用于触发重新登录）
  static void Function()? onUnauthorized;

  static const Duration _defaultTimeout = Duration(seconds: 30);

  static Future<ApiResponse<Map<String, dynamic>>> post(
    String endpoint, {
    Map<String, dynamic>? body,
    Duration? timeout,
    int maxRetries = 1,
    bool allowRefresh = true,
  }) async {
    if (baseUrl.trim().isEmpty) {
      return ApiResponse.failure('未配置服务器地址');
    }

    final uri = Uri.parse('${baseUrl.trim()}$endpoint');
    Exception? lastError;

    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        final resp = await _send(uri, body, timeout ?? _defaultTimeout);

        if (resp.statusCode == 401 && allowRefresh && tokenRefresher != null) {
          final ok = await tokenRefresher!.call();
          if (!ok) {
            onUnauthorized?.call();
            return ApiResponse.failure(
              '登录已过期，请重新登录',
              code: 401,
              apiErrorKey: 'auth.TOKEN_EXPIRED',
            );
          }
          // 刷新成功，重放一次（不再允许二次刷新，避免死循环）
          return post(
            endpoint,
            body: body,
            timeout: timeout,
            maxRetries: maxRetries,
            allowRefresh: false,
          );
        }

        final decoded = _decode(resp);
        if (decoded == null) {
          return ApiResponse.failure('服务器返回内容无法解析', code: resp.statusCode);
        }
        return ApiResponse.fromJson(resp.statusCode, decoded);
      } catch (e) {
        lastError = e is Exception ? e : Exception(e.toString());
        if (attempt < maxRetries) {
          await Future<void>.delayed(Duration(milliseconds: 400 * (attempt + 1)));
          continue;
        }
      }
    }

    return ApiResponse.failure(_describeError(lastError));
  }

  /// 直接取原始响应，供需要自行读字节的场景使用
  static Future<http.Response> rawGet(
    String endpoint, {
    Duration? timeout,
  }) async {
    final uri = Uri.parse('${baseUrl.trim()}$endpoint');
    final req = http.Request('GET', uri);
    final token = await tokenProvider?.call();
    if (token != null && token.isNotEmpty) {
      req.headers['Authorization'] = 'Bearer $token';
    }
    final client = createSyncHttpClient();
    try {
      final streamed =
          await client.send(req).timeout(timeout ?? _defaultTimeout);
      return await http.Response.fromStream(streamed);
    } finally {
      client.close();
    }
  }

  static Future<http.Response> _send(
    Uri uri,
    Map<String, dynamic>? body,
    Duration timeout,
  ) async {
    final req = http.Request('POST', uri);
    req.headers['Content-Type'] = 'application/json; charset=utf-8';
    req.headers['Accept'] = 'application/json';
    req.headers['Accept-Language'] = 'zh-CN';

    final token = await tokenProvider?.call();
    if (token != null && token.isNotEmpty) {
      req.headers['Authorization'] = 'Bearer $token';
    }
    req.body = jsonEncode(body ?? const <String, dynamic>{});

    final client = createSyncHttpClient();
    try {
      final streamed = await client.send(req).timeout(timeout);
      return await http.Response.fromStream(streamed);
    } finally {
      client.close();
    }
  }

  static Map<String, dynamic>? _decode(http.Response resp) {
    try {
      final text = utf8.decode(resp.bodyBytes, allowMalformed: true).trim();
      if (text.isEmpty) return null;
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return null;
    } catch (_) {
      return null;
    }
  }

  static String _describeError(Exception? e) {
    if (e == null) return '网络请求失败';
    if (e is TimeoutException) return '请求超时，请检查网络或服务器状态';
    if (e is SocketException) return '无法连接服务器：${e.message}';
    final s = e.toString();
    if (s.contains('Connection refused')) return '服务器拒绝连接，请确认服务已启动';
    if (s.contains('Failed host lookup')) return '无法解析服务器地址';
    return '网络请求失败：$s';
  }
}
