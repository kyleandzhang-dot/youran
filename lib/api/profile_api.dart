// lib/api/profile_api.dart
// 对应 Vue 的 profile.js / MinePage 用户资料读取逻辑。

import 'api_client.dart';

int _intValue(dynamic value, [int fallback = 0]) {
  if (value is int) return value;
  return int.tryParse('${value ?? ''}') ?? fallback;
}

bool _boolValue(dynamic value, [bool fallback = false]) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  final text = value?.toString().toLowerCase();
  if (text == 'true' || text == '1') return true;
  if (text == 'false' || text == '0') return false;
  return fallback;
}

String _stringValue(dynamic value, [String fallback = '']) {
  if (value == null) return fallback;
  final text = value.toString();
  return text == 'null' ? fallback : text;
}

Map<String, dynamic> _unwrapData(Map<String, dynamic> json) {
  final data = json['data'];
  if (data is Map<String, dynamic>) return data;
  if (data is Map) {
    return data.map((key, value) => MapEntry(key.toString(), value));
  }
  return json;
}

class UserProfile {
  const UserProfile({
    required this.userId,
    required this.name,
    required this.avatarUrl,
    required this.isVip,
    required this.isGuest,
    required this.tokenBalance,
    required this.unreadNotifications,
    this.shortId,
    this.personaName,
    this.personaDesc,
    this.raw = const <String, dynamic>{},
  });

  final String userId;
  final String name;
  final String avatarUrl;
  final bool isVip;
  final bool isGuest;
  final int tokenBalance;
  final int unreadNotifications;
  final String? shortId;
  final String? personaName;
  final String? personaDesc;
  final Map<String, dynamic> raw;

  UserProfile copyWith({
    String? name,
    String? avatarUrl,
    int? tokenBalance,
    int? unreadNotifications,
  }) {
    return UserProfile(
      userId: userId,
      name: name ?? this.name,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      isVip: isVip,
      isGuest: isGuest,
      tokenBalance: tokenBalance ?? this.tokenBalance,
      unreadNotifications: unreadNotifications ?? this.unreadNotifications,
      shortId: shortId,
      personaName: personaName,
      personaDesc: personaDesc,
      raw: raw,
    );
  }

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    final data = _unwrapData(json);
    return UserProfile(
      userId: _stringValue(data['user_id'] ?? data['id']),
      name: _stringValue(
        data['name'] ?? data['username'] ?? data['nickname'],
        '用户',
      ),
      avatarUrl: _stringValue(data['avatar_url'] ?? data['avatar']),
      isVip: _boolValue(data['is_vip']),
      isGuest: _boolValue(data['is_guest']),
      tokenBalance: _intValue(
        data['token_balance'] ?? data['points'] ?? data['balance'],
      ),
      unreadNotifications: _intValue(data['unread_notifications']),
      shortId: (data['short_id'] ?? data['uid'])?.toString(),
      personaName: data['persona_name']?.toString(),
      personaDesc: data['persona_desc']?.toString(),
      raw: data,
    );
  }
}

class ProfileApi {
  ProfileApi._();

  /// Vue: getUserProfile() -> GET /user/profile
  static Future<UserProfile> getUserProfile() async {
    final json = await ApiClient.instance.get('/user/profile');
    return UserProfile.fromJson(json);
  }

  /// Vue: updateUserName(name) -> PUT /user/name
  static Future<Map<String, dynamic>> updateUserName(String name) {
    return ApiClient.instance.put(
      '/user/name',
      body: <String, dynamic>{'name': name},
    );
  }

  /// Vue: updateUserAvatar(avatar_url) -> PUT /user/avatar
  /// 图片上传到 R2/OSS 的步骤仍由上层上传组件负责，这里只提交 URL。
  static Future<Map<String, dynamic>> updateUserAvatar(String avatarUrl) {
    return ApiClient.instance.put(
      '/user/avatar',
      body: <String, dynamic>{'avatar_url': avatarUrl},
    );
  }
}
