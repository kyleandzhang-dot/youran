// lib/services/token_storage.dart

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TokenStorage {
  TokenStorage._();

  static const _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
  );

  static const _kAccessToken = 'access_token';
  static const _kRefreshToken = 'refresh_token';
  static const _kProfile = 'user_profile_snapshot';

  // 内存兜底缓存。写入时始终同步一份，不能只在 SecureStorage 写失败时才填充；
  // 否则后续一次偶发读取异常就会把“已有 token”误判成 null。
  static final Map<String, String> _memoryCache = <String, String>{};

  static Future<void> save({
    required String accessToken,
    required String refreshToken,
  }) async {
    _memoryCache[_kAccessToken] = accessToken;
    _memoryCache[_kRefreshToken] = refreshToken;

    try {
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_kAccessToken, accessToken);
        await prefs.setString(_kRefreshToken, refreshToken);
      } else {
        await _secureStorage.write(key: _kAccessToken, value: accessToken);
        await _secureStorage.write(key: _kRefreshToken, value: refreshToken);
      }
    } catch (e) {
      debugPrint('Storage Write Error: $e');
    }
  }

  static Future<void> updateAccessToken(String accessToken) async {
    _memoryCache[_kAccessToken] = accessToken;

    try {
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_kAccessToken, accessToken);
      } else {
        await _secureStorage.write(key: _kAccessToken, value: accessToken);
      }
    } catch (e) {
      debugPrint('Storage Update Error: $e');
    }
  }

  static Future<String?> readAccessToken() async {
    try {
      final String? value;
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        value = prefs.getString(_kAccessToken);
      } else {
        value = await _secureStorage.read(key: _kAccessToken);
      }

      if (value != null && value.isNotEmpty) {
        _memoryCache[_kAccessToken] = value;
        return value;
      }
      return _memoryCache[_kAccessToken];
    } catch (e) {
      debugPrint('Storage Read Error: $e');
      return _memoryCache[_kAccessToken];
    }
  }

  static Future<String?> readRefreshToken() async {
    try {
      final String? value;
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        value = prefs.getString(_kRefreshToken);
      } else {
        value = await _secureStorage.read(key: _kRefreshToken);
      }

      if (value != null && value.isNotEmpty) {
        _memoryCache[_kRefreshToken] = value;
        return value;
      }
      return _memoryCache[_kRefreshToken];
    } catch (e) {
      debugPrint('Storage Read Error: $e');
      return _memoryCache[_kRefreshToken];
    }
  }

  static Future<void> saveProfile({
    required String userId,
    required String username,
    required int tokenBalance,
  }) async {
    final payload = jsonEncode({
      'user_id': userId,
      'username': username,
      'token_balance': tokenBalance,
    });

    _memoryCache[_kProfile] = payload;

    try {
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_kProfile, payload);
      } else {
        await _secureStorage.write(key: _kProfile, value: payload);
      }
    } catch (e) {
      debugPrint('Storage SaveProfile Error: $e');
    }
  }

  static Future<Map<String, dynamic>?> readProfile() async {
    String? raw;
    try {
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        raw = prefs.getString(_kProfile);
      } else {
        raw = await _secureStorage.read(key: _kProfile);
      }

      if (raw != null && raw.isNotEmpty) {
        _memoryCache[_kProfile] = raw;
      } else {
        raw = _memoryCache[_kProfile];
      }
    } catch (e) {
      debugPrint('Storage ReadProfile Error: $e');
      raw = _memoryCache[_kProfile];
    }

    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear() async {
    try {
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_kAccessToken);
        await prefs.remove(_kRefreshToken);
        await prefs.remove(_kProfile);
      } else {
        await _secureStorage.delete(key: _kAccessToken);
        await _secureStorage.delete(key: _kRefreshToken);
        await _secureStorage.delete(key: _kProfile);
      }
    } catch (e) {
      debugPrint('Storage Clear Error: $e');
    } finally {
      _memoryCache.clear();
    }
  }
}
