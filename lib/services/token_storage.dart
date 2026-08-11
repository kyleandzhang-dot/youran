// lib/services/token_storage.dart
//
// Token 不应该用 shared_preferences 明文存（会被 root/越狱设备直接读走），
// 标准做法是用系统级安全存储：Android Keystore / iOS Keychain。
// flutter_secure_storage 就是对这两者的统一封装。
//
// 除了 token，这里也顺带存一份「用户信息快照」（user_id/username/积分），
// 这样 app 冷启动时可以先用快照秒开界面，再在后台用 refresh token 悄悄校验，
// 不用等接口返回才能显示用户名 —— 这是主流 app（微信/小红书那类）都在用的模式。

import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TokenStorage {
  TokenStorage._();
  static const _storage = FlutterSecureStorage();

  static const _kAccessToken = 'access_token';
  static const _kRefreshToken = 'refresh_token';
  static const _kProfile = 'user_profile_snapshot';

  static Future<void> save({
    required String accessToken,
    required String refreshToken,
  }) async {
    await _storage.write(key: _kAccessToken, value: accessToken);
    await _storage.write(key: _kRefreshToken, value: refreshToken);
  }

  /// 只更新 access token（refresh 成功后调用，refresh token 本身不变）
  static Future<void> updateAccessToken(String accessToken) async {
    await _storage.write(key: _kAccessToken, value: accessToken);
  }

  static Future<String?> readAccessToken() => _storage.read(key: _kAccessToken);
  static Future<String?> readRefreshToken() => _storage.read(key: _kRefreshToken);

  static Future<void> saveProfile({
    required String userId,
    required String username,
    required int tokenBalance,
  }) async {
    await _storage.write(
      key: _kProfile,
      value: jsonEncode({
        'user_id': userId,
        'username': username,
        'token_balance': tokenBalance,
      }),
    );
  }

  static Future<Map<String, dynamic>?> readProfile() async {
    final raw = await _storage.read(key: _kProfile);
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear() async {
    await _storage.delete(key: _kAccessToken);
    await _storage.delete(key: _kRefreshToken);
    await _storage.delete(key: _kProfile);
  }
}