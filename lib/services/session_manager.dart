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

  /// 登录成功后调用。
  static Future<void> persist(LoginResult result) async {
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
  /// NovelRuntime 会在 HTTP 401 时使用它并自动重试原请求；多个并发请求
  /// 会共享同一个 Future，避免同时打爆 /sms/refresh。
  static Future<String?> refreshAccessToken() {
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
      await logout();
      return null;
    }

    try {
      final newAccessToken = await AuthApi.refreshAccessToken(refreshToken);
      if (newAccessToken.trim().isEmpty) {
        throw const ApiException('刷新接口未返回 access_token');
      }
      await TokenStorage.updateAccessToken(newAccessToken);
      ApiClient.instance.setAccessToken(newAccessToken);
      return newAccessToken;
    } on ApiException catch (error) {
      // 只有明确的凭证失效才清空本地会话；5xx / 临时网络问题不误登出。
      if (error.statusCode == 400 ||
          error.statusCode == 401 ||
          error.statusCode == 403) {
        await logout();
        return null;
      }
      rethrow;
    }
  }

  /// App 启动时调用。
  ///
  /// 返回 null 表示未登录、登录已失效，或本次网络无法验证登录态。
  static Future<UserSession?> restore() async {
    // 冷启动时先清空内存状态，避免意外复用旧身份。
    ApiClient.instance.setAccessToken(null);
    ApiClient.instance.setUserId(null);

    final refreshToken = await TokenStorage.readRefreshToken();
    if (refreshToken == null || refreshToken.trim().isEmpty) {
      return null;
    }

    final profile = await TokenStorage.readProfile();
    final savedUserId = profile?['user_id']?.toString().trim() ?? '';
    ApiClient.instance.setUserId(savedUserId);

    try {
      final newAccessToken = await AuthApi.refreshAccessToken(refreshToken);

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
      ApiClient.instance.setAccessToken(null);
      ApiClient.instance.setUserId(null);
      // 只有 refresh token 明确失效时删除持久化会话。
      // 服务端 5xx 等临时故障保留 refresh token，下次启动仍可恢复。
      if (error.statusCode == 400 ||
          error.statusCode == 401 ||
          error.statusCode == 403) {
        await TokenStorage.clear();
      }
      return null;
    } catch (error) {
      // 暂时断网时不删除本地 refresh token，下次启动仍可重试。
      debugPrint('会话恢复时网络异常：$error');
      ApiClient.instance.setAccessToken(null);
      ApiClient.instance.setUserId(null);
      return null;
    }
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
