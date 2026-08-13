// lib/login_sheet.dart

import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'api/api_client.dart';
import 'api/auth_api.dart';
import 'app_shared.dart'; 

class LoginSheet extends StatefulWidget {
  const LoginSheet({super.key, required this.onLoginSuccess});

  /// 支持异步回调，确保 Token 保存完成后再决定是否关闭弹窗
  final FutureOr<void> Function(LoginResult) onLoginSuccess;

  static void show(
    BuildContext context, {
    required FutureOr<void> Function(LoginResult) onLoginSuccess,
  }) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      barrierColor: Colors.black54,
      
      // 强制登录：禁止点击蒙层关闭、禁止下滑手势关闭
      isDismissible: false,
      enableDrag: false,
      useSafeArea: true,

      builder: (sheetContext) {
        // 拦截物理/手势返回键，防止绕过登录
        return PopScope(
          canPop: false,
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
            ),
            child: LoginSheet(onLoginSuccess: onLoginSuccess),
          ),
        );
      },
    );
  }

  @override
  State<LoginSheet> createState() => _LoginSheetState();
}

class _LoginSheetState extends State<LoginSheet> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();

  Timer? _countdownTimer;
  int _countdown = 0;
  bool _sendingCode = false;
  bool _submitting = false;
  String? _errorText;

  bool get _emailValid {
    final email = _emailController.text.trim();
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _emailController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _handleSendCode() async {
    if (!_emailValid) {
      setState(() => _errorText = '请输入正确的邮箱地址');
      return;
    }

    setState(() {
      _errorText = null;
      _sendingCode = true;
    });

    try {
      await AuthApi.sendEmailCode(_emailController.text.trim());
      _startCountdown();
    } on ApiException catch (error) {
      if (mounted) setState(() => _errorText = error.message);
    } catch (e) {
      if (mounted) setState(() => _errorText = '发送失败，请稍后再试');
    } finally {
      if (mounted) setState(() => _sendingCode = false);
    }
  }

  void _startCountdown() {
    setState(() => _countdown = 60);
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (_countdown <= 1) {
        timer.cancel();
        setState(() => _countdown = 0);
      } else {
        setState(() => _countdown -= 1);
      }
    });
  }

  Future<void> _handleSubmit() async {
    if (!_emailValid) {
      setState(() => _errorText = '请输入正确的邮箱地址');
      return;
    }

    if (_codeController.text.trim().isEmpty) {
      setState(() => _errorText = '请输入验证码');
      return;
    }

    setState(() {
      _errorText = null;
      _submitting = true;
    });

    try {
      final result = await AuthApi.verifyEmailLogin(
        email: _emailController.text.trim(),
        code: _codeController.text.trim(),
      );

      if (mounted) {
        // ★ 核心修改：先等待外部 SessionManager.persist 保存完成
        await widget.onLoginSuccess(result);

        // 只有保存阶段没有抛出任何异常，才真正关闭弹窗
        if (mounted) {
          Navigator.pop(context);
        }
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _errorText = error.message);
    } catch (e) {
      debugPrint('登录或本地保存失败: $e');
      if (mounted) {
        setState(() => _errorText = '登录状态保存失败，请检查存储配置');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
        child: Container(
          padding: const EdgeInsets.only(top: 14),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.24),
            border: Border(
              top: BorderSide(
                color: Colors.white.withOpacity(0.12),
                width: 1,
              ),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Align(
                        child: Container(
                          width: 34,
                          height: 1,
                          color: Colors.white.withOpacity(0.22),
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        '登录 / 注册',
                        style: TextStyle(
                          color: AppColors.textOnDark,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        '未注册邮箱验证后将自动创建账号',
                        style: TextStyle(
                          color: AppColors.textOnDarkMuted,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Divider(
                        height: 1,
                        color: Colors.white.withOpacity(0.13),
                      ),
                      const SizedBox(height: 16),
                      _buildInputField(
                        controller: _emailController,
                        icon: LucideIcons.mail,
                        hintText: '输入邮箱地址',
                        keyboardType: TextInputType.emailAddress,
                      ),
                      const SizedBox(height: 12),
                      _buildInputField(
                        controller: _codeController,
                        icon: LucideIcons.shieldCheck,
                        hintText: '输入 6 位验证码',
                        keyboardType: TextInputType.number,
                        trailing: GestureDetector(
                          onTap: _countdown == 0 && !_sendingCode ? _handleSendCode : null,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            margin: const EdgeInsets.only(right: 4),
                            decoration: BoxDecoration(
                              color: _countdown == 0 && _emailValid
                                  ? AppColors.accent.withOpacity(0.15)
                                  : Colors.white.withOpacity(0.03),
                              borderRadius: BorderRadius.circular(2),
                            ),
                            child: _sendingCode
                                ? const SizedBox(
                                    width: 12,
                                    height: 12,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 1.5,
                                      color: AppColors.accent,
                                    ),
                                  )
                                : Text(
                                    _countdown == 0 ? '获取验证码' : '${_countdown}s',
                                    style: TextStyle(
                                      color: _countdown == 0
                                          ? (_emailValid ? AppColors.accent : AppColors.textOnDarkMuted)
                                          : AppColors.textOnDarkMuted,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: _errorText != null
                            ? Container(
                                key: ValueKey(_errorText),
                                margin: const EdgeInsets.only(top: 12),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE0554A).withOpacity(0.15),
                                  border: Border.all(color: const Color(0xFFE0554A).withOpacity(0.3)),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(LucideIcons.alertCircle, size: 14, color: Color(0xFFE0554A)),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _errorText!,
                                        style: const TextStyle(
                                          color: Color(0xFFE0554A),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 32),
                
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  child: Widget_BottomActionButton(
                    isLoading: _submitting,
                    label: '验证并登录',
                    onTap: _submitting ? null : _handleSubmit,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required IconData icon,
    required String hintText,
    required TextInputType keyboardType,
    Widget? trailing,
  }) {
    return Container(
      height: 50,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.018),
        border: Border.all(
          color: Colors.white.withOpacity(0.13),
          width: 1,
        ),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Row(
        children: [
          const SizedBox(width: 14),
          Icon(icon, size: 16, color: AppColors.textOnDarkMuted),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: keyboardType,
              cursorColor: AppColors.accent,
              style: const TextStyle(
                color: AppColors.textOnDark,
                fontSize: 14,
              ),
              decoration: InputDecoration(
                hintText: hintText,
                hintStyle: TextStyle(
                  color: AppColors.textOnDarkMuted.withOpacity(0.6),
                  fontSize: 13,
                ),
                border: InputBorder.none,
                isCollapsed: true,
              ),
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }
}

class Widget_BottomActionButton extends StatelessWidget {
  const Widget_BottomActionButton({
    super.key,
    required this.label,
    required this.onTap,
    this.isLoading = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: onTap != null ? AppColors.accent : AppColors.accent.withOpacity(0.2),
      borderRadius: BorderRadius.circular(3),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 52,
          alignment: Alignment.center,
          child: isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Color.fromARGB(255, 12, 12, 12), 
                  ),
                )
              : Text(
                  label,
                  style: const TextStyle(
                    color: Color.fromARGB(255, 12, 12, 12),
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0, 
                  ),
                ),
        ),
      ),
    );
  }
}