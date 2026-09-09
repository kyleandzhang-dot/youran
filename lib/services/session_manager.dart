// lib/services/session_manager.dart
//
// 登录成功后保存 token 和用户快照；
// App 冷启动时使用 refresh token 恢复登录状态。
// ApiClient 是全项目唯一的内存 access token 来源。

import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../api/auth_api.dart';
import 'token_storage.dart';

class UserSession {
  UserSession({
    required this.userId,
    required this.username,
    required this.tokenBalance,
    required this.accessToken,
  });

  final String userId;
  final String username;
  final int tokenBalance;
  final String accessToken;
}

class SessionManager {
  SessionManager._();

  // 多个 401 同时发生时只刷新一次，等价于 Vue request.js 的 failedQueue。
  static Future<String?>? _refreshingAccessToken;

  // 仅用于告诉 UI：这次回到登录页是“身份过期”，不是普通未登录。
  static bool _sessionExpiredNoticePending = false;

  static void _configureApiClient() {
    ApiClient.instance.setUnauthorizedRefreshHandler(refreshAccessToken);
  }

  /// 读取并消费一次“身份已过期”提示。
  static bool consumeSessionExpiredNotice() {
    final pending = _sessionExpiredNoticePending;
    _sessionExpiredNoticePending = false;
    return pending;
  }

  /// 服务端明确判定凭证失效时调用。
  /// 与普通 logout() 分开，避免用户主动退出也显示“身份已过期”。
  static Future<void> expireSession() async {
    _sessionExpiredNoticePending = true;
    await logout();
  }

  /// 登录成功后调用。
  static Future<void> persist(LoginResult result) async {
    _configureApiClient();

    // 新登录成功后，清掉可能残留的“身份过期”提示。
    _sessionExpiredNoticePending = false;

    // 服务端已经确认登录成功后，先让当前运行时身份立即生效。
    // 后续页面即使马上发请求，也能立刻带上 Authorization / X-User-ID。
    ApiClient.instance.setAccessToken(result.accessToken);
    ApiClient.instance.setUserId(result.userId);

    // 再持久化到本地；存储速度不再阻塞运行时登录态生效。
    await TokenStorage.save(
      accessToken: result.accessToken,
      refreshToken: result.refreshToken,
    );

    await TokenStorage.saveProfile(
      userId: result.userId,
      username: result.username,
      tokenBalance: result.tokenBalance.toInt(),
    );
  }

  /// 运行中 access token 过期时调用。
  ///
  /// ApiClient 会在所有普通 HTTP 401 时使用它并自动重试原请求；多个并发请求
  /// 会共享同一个 Future，避免同时打爆 refresh 接口。
  static Future<String?> refreshAccessToken() {
    _configureApiClient();

    final running = _refreshingAccessToken;
    if (running != null) return running;
    final future = _refreshAccessTokenInternal();
    _refreshingAccessToken = future;
    return future.whenComplete(() {
      if (identical(_refreshingAccessToken, future)) {
        _refreshingAccessToken = null;
      }
    });
  }

  static Future<String?> _refreshAccessTokenInternal() async {
    final refreshToken = await TokenStorage.readRefreshToken();
    if (refreshToken == null || refreshToken.trim().isEmpty) {
      await expireSession();
      return null;
    }

    try {
      // refresh 请求本身如果返回 401，必须直接交给这里处理，不能再次触发
      // ApiClient 的 401 自动刷新，否则会形成 refresh 等待自己的死锁。
      final newAccessToken = await ApiClient.instance.withoutUnauthorizedRefresh(
        () => AuthApi.refreshAccessToken(refreshToken),
      );
      if (newAccessToken.trim().isEmpty) {
        throw const ApiException('刷新接口未返回 access_token');
      }
      await TokenStorage.updateAccessToken(newAccessToken);
      ApiClient.instance.setAccessToken(newAccessToken);
      return newAccessToken;
    } on ApiException catch (error) {
      // 只有明确的凭证失效才清空本地会话；5xx / 临时网络问题不误登出。
      if (_isCredentialRejected(error.statusCode)) {
        await expireSession();
        return null;
      }
      rethrow;
    }
  }

  /// App 启动时调用。
  ///
  /// refresh token 明确失效时返回 null 并清空登录态；
  /// 临时断网/5xx 时优先保留本地会话，不再把用户误送回登录页。
  static Future<UserSession?> restore() async {
    _configureApiClient();

    final refreshToken = await TokenStorage.readRefreshToken();
    if (refreshToken == null || refreshToken.trim().isEmpty) {
      ApiClient.instance.setAccessToken(null);
      ApiClient.instance.setUserId(null);
      return null;
    }

    final profile = await TokenStorage.readProfile();
    final savedUserId = profile?['user_id']?.toString().trim() ?? '';
    final cachedAccessToken = await TokenStorage.readAccessToken();

    // 先恢复本地快照。真正的 refresh 仍会立即执行；这样临时断网/5xx 时
    // 不会因为 restore() 返回 null 而把已有用户瞬间踢回登录页。
    ApiClient.instance.setUserId(savedUserId);
    ApiClient.instance.setAccessToken(cachedAccessToken);

    try {
      final newAccessToken = await ApiClient.instance.withoutUnauthorizedRefresh(
        () => AuthApi.refreshAccessToken(refreshToken),
      );
      if (newAccessToken.trim().isEmpty) {
        throw const ApiException('刷新接口未返回 access_token');
      }

      await TokenStorage.updateAccessToken(newAccessToken);
      ApiClient.instance.setAccessToken(newAccessToken);

      return UserSession(
        userId: savedUserId,
        username: profile?['username'] as String? ?? '',
        tokenBalance: _readTokenBalance(profile?['token_balance']),
        accessToken: newAccessToken,
      );
    } on ApiException catch (error) {
      debugPrint('会话恢复失败：${error.message}');

      if (_isCredentialRejected(error.statusCode)) {
        await expireSession();
        return null;
      }

      // 服务端 5xx 等临时错误：保留 refresh token 与本地身份，后续任意 API
      // 真遇到 401 时会再次走统一 refresh。不要把临时故障误判成退出登录。
      return _cachedSession(
        profile: profile,
        accessToken: cachedAccessToken,
      );
    } catch (error) {
      // 暂时断网时同样保留本地会话；恢复网络后由 ApiClient 自动刷新。
      debugPrint('会话恢复时网络异常：$error');
      return _cachedSession(
        profile: profile,
        accessToken: cachedAccessToken,
      );
    }
  }

  static UserSession? _cachedSession({
    required Map<String, dynamic>? profile,
    required String? accessToken,
  }) {
    final token = accessToken?.trim() ?? '';
    final userId = profile?['user_id']?.toString().trim() ?? '';
    if (token.isEmpty || userId.isEmpty) return null;

    ApiClient.instance.setAccessToken(token);
    ApiClient.instance.setUserId(userId);

    return UserSession(
      userId: userId,
      username: profile?['username'] as String? ?? '',
      tokenBalance: _readTokenBalance(profile?['token_balance']),
      accessToken: token,
    );
  }

  static bool _isCredentialRejected(int? statusCode) {
    return statusCode == 400 || statusCode == 401 || statusCode == 403;
  }

  static int _readTokenBalance(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static Future<void> logout() async {
    ApiClient.instance.setAccessToken(null);
    ApiClient.instance.setUserId(null);
    await TokenStorage.clear();
  }
}
