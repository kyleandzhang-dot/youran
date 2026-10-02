// lib/services/auth_redirect.dart
//
// 全局“回到登录页”入口。main.dart 启动时注册真正的实现，
// SessionManager / GameShell 通过它触发跳转，避免反向 import main.dart。

class AuthRedirect {
  const AuthRedirect._();

  static Future<void> Function({String? message, bool expire})? _handler;

  static void register(
    Future<void> Function({String? message, bool expire}) handler,
  ) =>
      _handler = handler;

  /// [message]：登录页顶部提示；null 表示使用“身份已过期”默认文案，'' 表示不提示。
  /// [expire]：是否在跳转前调用 SessionManager.expireSession()。
  static Future<void> go({String? message, bool expire = true}) async =>
      _handler?.call(message: message, expire: expire);
}