// lib/login_sheet.dart
//
// YO RAN 登录页 - 融入背景简洁版
// 图片资源仅保留：
//   assets/images/login_logo.png
//   assets/images/login_background.png

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'api/api_client.dart';
import 'api/auth_api.dart';
import 'app_shared.dart';

class LoginSheet extends StatefulWidget {
  const LoginSheet({super.key, required this.onLoginSuccess});

  final FutureOr<void> Function(LoginResult) onLoginSuccess;

  static void show(
    BuildContext context, {
    required FutureOr<void> Function(LoginResult) onLoginSuccess,
  }) {
    // 登录页只负责验证账号。验证成功后先完整关闭 root 登录路由，
    // 再执行外部登录成功回调，避免回调中的页面跳转与登录页 pop 互相竞争。
    Navigator.of(context, rootNavigator: true)
        .push<LoginResult>(
      PageRouteBuilder<LoginResult>(
        opaque: true,
        barrierDismissible: false,
        transitionDuration: const Duration(milliseconds: 240),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (_, __, ___) {
          return PopScope(
            canPop: false,
            child: LoginSheet(onLoginSuccess: onLoginSuccess),
          );
        },
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            ),
            child: child,
          );
        },
      ),
    )
        .then((result) async {
      if (result == null) return;
      try {
        await onLoginSuccess(result);
      } catch (error, stackTrace) {
        debugPrint('登录成功后的状态处理失败: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
    });
  }

  @override
  State<LoginSheet> createState() => _LoginSheetState();
}

class _LoginSheetState extends State<LoginSheet> {
  static const String _logoAsset = 'assets/images/login_logo.png';
  static const String _backgroundAsset =
      'assets/images/login_background.png';

  static const Color _accent =
      Color.fromARGB(255, 129, 246, 112);
  static const Color _ink = Color(0xFF273026);
  static const Color _muted = Color(0xFF8B918A);

  final TextEditingController _emailController =
      TextEditingController();
  final TextEditingController _codeController =
      TextEditingController();
  final FocusNode _emailFocusNode = FocusNode();
  final FocusNode _codeFocusNode = FocusNode();

  Timer? _countdownTimer;
  int _countdown = 0;
  bool _sendingCode = false;
  bool _submitting = false;
  String? _errorText;

  bool get _emailValid {
    final email = _emailController.text.trim();
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
        .hasMatch(email);
  }

  bool get _canSendCode =>
      _countdown == 0 && !_sendingCode && _emailValid;

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _emailController.dispose();
    _codeController.dispose();
    _emailFocusNode.dispose();
    _codeFocusNode.dispose();
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
      await AuthApi.sendEmailCode(
        _emailController.text.trim(),
      );
      _startCountdown();
      if (mounted) {
        _codeFocusNode.requestFocus();
      }
    } on ApiException catch (error) {
      if (mounted) {
        setState(() => _errorText = error.message);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _errorText = '发送失败，请稍后再试');
      }
    } finally {
      if (mounted) {
        setState(() => _sendingCode = false);
      }
    }
  }

  void _startCountdown() {
    setState(() => _countdown = 60);
    _countdownTimer?.cancel();

    _countdownTimer =
        Timer.periodic(const Duration(seconds: 1), (timer) {
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
    if (_submitting) return;

    if (!_emailValid) {
      setState(() => _errorText = '请输入正确的邮箱地址');
      return;
    }

    final code = _codeController.text.trim();
    if (code.isEmpty) {
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
        code: code,
      );

      if (!mounted) return;

      // 只把登录结果交给 root 路由；show() 会在登录页完整退出后
      // 再调用 onLoginSuccess，彻底消除导航时序竞争。
      Navigator.of(context, rootNavigator: true).pop<LoginResult>(result);
    } on ApiException catch (error) {
      if (mounted) {
        setState(() => _errorText = error.message);
      }
    } catch (error) {
      debugPrint('登录请求失败: $error');
      if (mounted) {
        setState(() => _errorText = '登录失败，请稍后再试');
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 600;
    final narrow = size.width < 390;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: Colors.white,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          const _LoginBackground(
            asset: _backgroundAsset,
          ),

          // 只做极轻的统一提亮，不给页面再盖一层“白卡片”。
          IgnorePointer(
            child: Container(
              color: Colors.white.withOpacity(.08),
            ),
          ),

          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior
                          .onDrag,
                  physics:
                      const BouncingScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(
                    compact ? 22 : 34,
                    compact ? 18 : 24,
                    compact ? 22 : 34,
                    compact ? 24 : 30,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight:
                          constraints.maxHeight -
                              (compact ? 56 : 80),
                    ),
                    child: Align(
                      alignment: compact
                          ? const Alignment(0, -0.34)
                          : const Alignment(0, -0.28),
                      child: ConstrainedBox(
                        constraints:
                            const BoxConstraints(
                          maxWidth: 420,
                        ),
                        child: Column(
                          mainAxisSize:
                              MainAxisSize.min,
                          children: <Widget>[
                            _buildBrand(
                              compact: compact,
                              narrow: narrow,
                            ),
                            SizedBox(
                              height:
                                  compact ? 28 : 34,
                            ),
                            _buildForm(),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBrand({
    required bool compact,
    required bool narrow,
  }) {
    final logoSize = narrow
        ? 70.0
        : compact
            ? 82.0
            : 92.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: logoSize,
          height: logoSize,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(
              logoSize * .24,
            ),
          ),
          child: Image.asset(
            _logoAsset,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.high,
            errorBuilder: (_, __, ___) {
              return Container(
                color:
                    Colors.white.withOpacity(.55),
                alignment: Alignment.center,
                child: Icon(
                  LucideIcons.image,
                  size: 26,
                  color:
                      _muted.withOpacity(.52),
                ),
              );
            },
          ),
        ),
        SizedBox(
          height: compact ? 22 : 26,
        ),
        Text(
          'YO RAN',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _ink.withOpacity(.92),
            fontSize: narrow
                ? 28
                : compact
                    ? 31
                    : 34,
            height: 1.05,
            fontWeight: FontWeight.w600,
            letterSpacing:
                narrow ? 3.2 : 4.2,
          ),
        ),
        const SizedBox(height: 13),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 36,
              height: 1,
              color: const Color(0xFFC9C0A4)
                  .withOpacity(.72),
            ),
            const SizedBox(width: 8),
            Transform.rotate(
              angle: .785398,
              child: Container(
                width: 6,
                height: 6,
                color: const Color(0xFFB8AD8C)
                    .withOpacity(.82),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 36,
              height: 1,
              color: const Color(0xFFC9C0A4)
                  .withOpacity(.72),
            ),
          ],
        ),
        const SizedBox(height: 15),
        Text(
          '进入你的 AI 剧情世界',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _ink.withOpacity(.72),
            fontSize: narrow ? 13.5 : 15,
            fontWeight: FontWeight.w500,
            letterSpacing: 1.9,
          ),
        ),
      ],
    );
  }

  Widget _buildForm() {
    return AutofillGroup(
      child: Column(
        children: <Widget>[
          _buildInputField(
            controller: _emailController,
            focusNode: _emailFocusNode,
            icon: LucideIcons.mail,
            hintText: '邮箱地址',
            keyboardType:
                TextInputType.emailAddress,
            textInputAction:
                TextInputAction.next,
            autofillHints: const <String>[
              AutofillHints.email,
            ],
            onChanged: (_) {
              if (mounted) setState(() {});
            },
            onSubmitted: (_) {
              _codeFocusNode.requestFocus();
            },
          ),
          const SizedBox(height: 10),
          _buildInputField(
            controller: _codeController,
            focusNode: _codeFocusNode,
            icon: LucideIcons.shieldCheck,
            hintText: '验证码',
            keyboardType:
                TextInputType.number,
            textInputAction:
                TextInputAction.done,
            autofillHints: const <String>[
              AutofillHints.oneTimeCode,
            ],
            onSubmitted: (_) {
              if (!_submitting) {
                _handleSubmit();
              }
            },
            trailing: _buildCodeAction(),
          ),

          AnimatedSwitcher(
            duration:
                const Duration(milliseconds: 170),
            child: _errorText == null
                ? const SizedBox.shrink()
                : _buildErrorMessage(
                    _errorText!,
                  ),
          ),

          const SizedBox(height: 14),

          _LoginPrimaryButton(
            isLoading: _submitting,
            label: '登录',
            onTap: _submitting
                ? null
                : _handleSubmit,
          ),

          const SizedBox(height: 10),

          Text(
            '未注册邮箱验证后将自动创建账号',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _muted.withOpacity(.86),
              fontSize: 11.5,
              height: 1.4,
              fontWeight: FontWeight.w500,
              shadows: <Shadow>[
                Shadow(
                  color:
                      Colors.white.withOpacity(.9),
                  blurRadius: 6,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCodeAction() {
    if (_sendingCode) {
      return const Padding(
        padding: EdgeInsets.only(right: 14),
        child: SizedBox(
          width: 15,
          height: 15,
          child: CircularProgressIndicator(
            strokeWidth: 1.8,
            color: _accent,
          ),
        ),
      );
    }

    final enabled = _canSendCode;

    return Padding(
      padding: const EdgeInsets.only(right: 5),
      child: TextButton(
        onPressed:
            enabled ? _handleSendCode : null,
        style: TextButton.styleFrom(
          foregroundColor:
              const Color(0xFF55B84A),
          disabledForegroundColor:
              _muted.withOpacity(.42),
          padding: const EdgeInsets.symmetric(
            horizontal: 11,
          ),
          minimumSize: const Size(0, 38),
          tapTargetSize:
              MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(
          _countdown == 0
              ? '获取验证码'
              : '${_countdown}s',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required IconData icon,
    required String hintText,
    required TextInputType keyboardType,
    required TextInputAction textInputAction,
    List<String>? autofillHints,
    ValueChanged<String>? onChanged,
    ValueChanged<String>? onSubmitted,
    Widget? trailing,
  }) {
    return AnimatedBuilder(
      animation: focusNode,
      builder: (context, _) {
        final focused = focusNode.hasFocus;

        return AnimatedContainer(
          duration:
              const Duration(milliseconds: 160),
          height: 50,
          decoration: BoxDecoration(
            // 实白输入框：不透明、不悬浮，直接融入背景。
            color: Colors.white,
            border: Border.all(
              color: focused
                  ? const Color(0xFF9EC89A)
                  : const Color(0xFFDADFD8),
              width: 1,
            ),
            borderRadius: BorderRadius.zero,
          ),
          child: Row(
            children: <Widget>[
              const SizedBox(width: 15),
              Icon(
                icon,
                size: 18,
                color: focused
                    ? const Color(0xFF589D4F)
                    : _muted.withOpacity(.76),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  keyboardType: keyboardType,
                  textInputAction:
                      textInputAction,
                  autofillHints: autofillHints,
                  cursorColor:
                      const Color(0xFF55A84A),
                  onChanged: onChanged,
                  onSubmitted: onSubmitted,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                  ),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    hintText: hintText,
                    hintStyle: TextStyle(
                      color:
                          _muted.withOpacity(.66),
                      fontSize: 13.5,
                      fontWeight:
                          FontWeight.w500,
                    ),
                  ),
                ),
              ),
              if (trailing != null) ...<Widget>[
                Container(
                  width: 1,
                  height: 21,
                  color: Colors.black
                      .withOpacity(.07),
                ),
                trailing,
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildErrorMessage(String text) {
    return Container(
      key: ValueKey<String>(text),
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.symmetric(
        horizontal: 13,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFFDF3F1)
            .withOpacity(.82),
        borderRadius:
            BorderRadius.circular(14),
      ),
      child: Row(
        children: <Widget>[
          const Icon(
            LucideIcons.circleAlert,
            size: 15,
            color: Color(0xFFD65D53),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Color(0xFFD65D53),
                fontSize: 11.5,
                height: 1.4,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoginBackground extends StatelessWidget {
  const _LoginBackground({
    required this.asset,
  });

  final String asset;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFFBFCFA),
      child: Image.asset(
        asset,
        fit: BoxFit.cover,
        alignment: Alignment.center,
        filterQuality: FilterQuality.high,
        errorBuilder: (_, __, ___) {
          return const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[
                  Color(0xFFFFFFFF),
                  Color(0xFFF7F9F5),
                  Color(0xFFFFFFFF),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _LoginPrimaryButton extends StatelessWidget {
  const _LoginPrimaryButton({
    required this.isLoading,
    required this.label,
    required this.onTap,
  });

  final bool isLoading;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;

    return AnimatedOpacity(
      duration:
          const Duration(milliseconds: 150),
      opacity: enabled ? 1 : .68,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.zero,
          child: Ink(
            height: 50,
            decoration: const BoxDecoration(
              color: _LoginSheetState._accent,
              borderRadius: BorderRadius.zero,
            ),
            child: Center(
              child: isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child:
                          CircularProgressIndicator(
                        strokeWidth: 2,
                        color:
                            _LoginSheetState._ink,
                      ),
                    )
                  : Text(
                      label,
                      style: const TextStyle(
                        color:
                            _LoginSheetState._ink,
                        fontSize: 15.5,
                        fontWeight:
                            FontWeight.w700,
                        letterSpacing: 2,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
