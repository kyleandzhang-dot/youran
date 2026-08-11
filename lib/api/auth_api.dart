// lib/api/auth_api.dart
//
// 对接后端 api/routes/email_auth.py 的两个接口：
//   POST /email/send   发送验证码
//   POST /email/verify 登录/注册
//
// 这一层只关心"业务动作"，不关心 http 细节（细节都在 ApiClient 里）。

import 'api_client.dart';

class LoginResult {
  LoginResult({
    required this.accessToken,
    required this.refreshToken,
    required this.userId,
    required this.shortId,
    required this.username,
    required this.email,
    required this.tokenBalance,
    required this.isNew,
  });

  final String accessToken;
  final String refreshToken;
  final String userId;

  /// 后端 email_auth.py /email/verify 里叫 short_id，是给用户看的短 UID，
  /// 之前这里没解析，导致抽屉里的 UID 一直是写死的占位符。
  final String shortId;
  final String username;
  final String email;
  final double tokenBalance;
  final bool isNew;

  factory LoginResult.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>;
    return LoginResult(
      accessToken: data['access_token'] as String,
      refreshToken: data['refresh_token'] as String,
      userId: data['user_id'] as String,
      shortId: (data['short_id'] as num?)?.toString() ??
          data['short_id'] as String? ??
          '',
      username: data['username'] as String,
      email: data['email'] as String? ?? '',
      tokenBalance: (data['token_balance'] as num).toDouble(),
      isNew: (json['message'] as String?) == '注册成功',
    );
  }
}

class AuthApi {
  AuthApi._();

  /// 发送邮箱验证码。成功不返回内容，失败会抛出 ApiException
  /// （ApiException.message 就是后端 detail，比如"发送过于频繁，请 42 秒后再试"）。
  static Future<void> sendEmailCode(String email) async {
    await ApiClient.instance.post('/email/send', body: {'email': email});
  }

  /// 邮箱验证码登录/注册。返回双 token + 用户信息。
  static Future<LoginResult> verifyEmailLogin({
    required String email,
    required String code,
  }) async {
    final json = await ApiClient.instance.post(
      '/email/verify',
      body: {'email': email, 'code': code},
    );
    return LoginResult.fromJson(json);
  }

  /// 用 refresh token 换新的 access token。
  /// 注意：这个接口挂在 /sms/refresh 下（sms_auth.py 里定义），
  /// 但登录方式（短信/邮箱）不影响 refresh 逻辑本身，两边共用同一个接口即可。
  static Future<String> refreshAccessToken(String refreshToken) async {
    final json = await ApiClient.instance.post(
      '/sms/refresh',
      body: {'refresh_token': refreshToken},
    );
    return json['data']['access_token'] as String;
  }
}