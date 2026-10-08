import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';

/// 登录态与服务器连接信息。
///
/// 负责把 accessToken / refreshToken 注入 [SyncHttp]，
/// 并在 401 时自动刷新；刷新失败则踢回登录页。
class SessionController extends GetxController {
  static SessionController get instance => Get.find<SessionController>();

  static const String _kBaseUrl = 'nascab_sync.base_url';
  static const String _kAccessToken = 'nascab_sync.access_token';
  static const String _kRefreshToken = 'nascab_sync.refresh_token';
  static const String _kUsername = 'nascab_sync.username';
  static const String _kUserId = 'nascab_sync.user_id';

  final RxBool loggedIn = false.obs;
  final RxString baseUrl = ''.obs;
  final RxString username = ''.obs;
  final RxInt userId = 0.obs;

  /// 当前 accessToken（供同步引擎发起上传/下载时使用）
  String? get accessToken => _accessToken;

  /// 会话失效回调（由 App 层挂载，用于回登录页并停止同步）
  void Function()? onSessionExpired;

  String? _accessToken;
  String? _refreshToken;
  bool _refreshing = false;
  SharedPreferences? _prefs;

  Future<SharedPreferences> get _sp async =>
      _prefs ??= await SharedPreferences.getInstance();

  @override
  void onInit() {
    super.onInit();
    _bindHttp();
  }

  /// 恢复上次的登录态。
  ///
  /// 由 [main] 在创建控制器后显式 await，保证首屏路由能正确决定进登录页还是主页。
  Future<void> restore() async {
    try {
      await _restore();
    } catch (_) {}
  }

  void _bindHttp() {
    SyncHttp.tokenProvider = () async => _accessToken;
    SyncHttp.tokenRefresher = refresh;
    SyncHttp.onUnauthorized = () {
      onSessionExpired?.call();
    };
  }

  /// 归一化服务器地址：补协议、去掉结尾斜杠
  static String normalizeServer(String input) {
    var s = input.trim();
    if (s.isEmpty) return s;
    if (!s.startsWith('http://') && !s.startsWith('https://')) {
      s = 'http://$s';
    }
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }

  Future<void> _restore() async {
    final sp = await _sp;
    final url = sp.getString(_kBaseUrl) ?? '';
    final at = sp.getString(_kAccessToken);
    final rt = sp.getString(_kRefreshToken);
    final name = sp.getString(_kUsername) ?? '';
    final uid = sp.getInt(_kUserId) ?? 0;

    _accessToken = at;
    _refreshToken = rt;
    baseUrl.value = url;
    username.value = name;
    userId.value = uid;
    SyncHttp.baseUrl = url;

    // 有 token 就先进主界面，后续请求若 401 会自动刷新；
    // 真的失效了再由 onUnauthorized 踢回登录页。
    loggedIn.value = (at != null && at.isNotEmpty && url.isNotEmpty);
  }

  /// 登录，成功返回 null，失败返回错误文案
  Future<String?> login({
    required String server,
    required String user,
    required String pass,
  }) async {
    final normalized = normalizeServer(server);
    if (normalized.isEmpty) return '请输入服务器地址';
    if (user.trim().isEmpty) return '请输入账号';
    if (pass.isEmpty) return '请输入密码';

    SyncHttp.baseUrl = normalized;
    final resp = await SyncHttp.post(
      '/api/auth/login',
      body: {'username': user.trim(), 'password': pass},
      maxRetries: 0,
    );

    if (!resp.success) {
      return resp.message ?? '登录失败';
    }

    final data = resp.data;
    final at = data?['accessToken']?.toString() ?? '';
    final rt = data?['refreshToken']?.toString() ?? '';
    if (at.isEmpty) return '登录失败：服务器未返回令牌';

    final userMap =
        data?['user'] is Map ? Map<String, dynamic>.from(data!['user'] as Map) : <String, dynamic>{};

    _accessToken = at;
    _refreshToken = rt.isEmpty ? null : rt;
    baseUrl.value = normalized;
    username.value = userMap['username']?.toString() ?? user.trim();
    userId.value = int.tryParse(userMap['id']?.toString() ?? '') ?? 0;

    final sp = await _sp;
    await sp.setString(_kBaseUrl, normalized);
    await sp.setString(_kAccessToken, at);
    if (_refreshToken != null) {
      await sp.setString(_kRefreshToken, _refreshToken!);
    } else {
      await sp.remove(_kRefreshToken);
    }
    await sp.setString(_kUsername, username.value);
    await sp.setInt(_kUserId, userId.value);

    loggedIn.value = true;
    return null;
  }

  /// 刷新 accessToken，成功返回 true
  Future<bool> refresh() async {
    if (_refreshing) return false;
    final rt = _refreshToken;
    if (rt == null || rt.isEmpty) return false;

    _refreshing = true;
    try {
      final resp = await SyncHttp.post(
        '/api/auth/refreshJwt',
        body: {'refreshToken': rt},
        maxRetries: 0,
        allowRefresh: false,
      );
      if (!resp.success) return false;

      final data = resp.data;
      final at = data?['accessToken']?.toString() ?? '';
      if (at.isEmpty) return false;

      _accessToken = at;
      final nextRt = data?['refreshToken']?.toString() ?? '';
      if (nextRt.isNotEmpty) _refreshToken = nextRt;

      final sp = await _sp;
      await sp.setString(_kAccessToken, at);
      if (_refreshToken != null) {
        await sp.setString(_kRefreshToken, _refreshToken!);
      }
      return true;
    } catch (_) {
      return false;
    } finally {
      _refreshing = false;
    }
  }

  /// 退出登录。清空本地凭证；[_clearLocalData] 用于换服务器时清掉同步基线。
  Future<void> logout({bool clearLocalData = false}) async {
    _accessToken = null;
    _refreshToken = null;
    loggedIn.value = false;
    username.value = '';
    userId.value = 0;

    final sp = await _sp;
    await sp.remove(_kAccessToken);
    await sp.remove(_kRefreshToken);
    await sp.remove(_kUsername);
    await sp.remove(_kUserId);
    // 保留 _kBaseUrl，方便用户重新登录时不用再输地址

    if (clearLocalData) {
      SyncHttp.baseUrl = '';
      baseUrl.value = '';
      await sp.remove(_kBaseUrl);
    }
  }
}
