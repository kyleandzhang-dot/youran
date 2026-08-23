// lib/login_sheet.dart
//
// YO RAN 登录页 - 融入背景简洁版
// 图片资源仅保留：
//   assets/images/login_logo.png
//   assets/images/login_background.png
//
// 新增：登录前必须勾选同意《用户协议》《隐私政策》《内容须知》

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'api/api_client.dart';
import 'api/auth_api.dart';
import 'app_shared.dart';

class LoginSheet extends StatefulWidget {
  const LoginSheet({
    super.key,
    required this.onLoginSuccess,
    this.initialErrorText,
  });

  final FutureOr<void> Function(LoginResult) onLoginSuccess;
  final String? initialErrorText;

  static void show(
    BuildContext context, {
    required FutureOr<void> Function(LoginResult) onLoginSuccess,
    String? initialErrorText,
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
            child: LoginSheet(
              onLoginSuccess: onLoginSuccess,
              initialErrorText: initialErrorText,
            ),
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

  /// 是否已勾选同意协议与内容须知
  bool _agreed = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialErrorText?.trim() ?? '';
    _errorText = initial.isEmpty ? null : initial;
  }

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

    if (!_agreed) {
      setState(() => _errorText = '请先阅读并勾选同意用户协议与内容须知');
      return;
    }

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

  /// 弹出内容须知 / 用户协议 / 隐私政策对话框
  void _showNoticeDialog({
    required String title,
    required String content,
  }) {
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            title,
            style: const TextStyle(
              color: _ink,
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
          content: SingleChildScrollView(
            child: Text(
              content,
              style: TextStyle(
                color: _ink.withOpacity(.85),
                fontSize: 13.5,
                height: 1.55,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text(
                '我知道了',
                style: TextStyle(
                  color: Color(0xFF55B84A),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // 内容须知（App Store 合规相关提示，面向用户）
  static const String _contentNotice = '''
【内容须知】（使用前请仔细阅读）

1. AI 生成内容说明
本应用使用人工智能实时生成无限剧情与对话。生成内容可能存在虚构、不准确或不符合预期的情况，请理性对待，仅作娱乐用途。

2. 禁止的内容
严禁生成、传播或引导以下内容：
• 色情、露骨性描写或色情服务
• 真实暴力、仇恨、歧视、恐吓或欺凌
• 违法、自伤、恐怖主义或任何危害公共安全的内容
• 侵犯他人知识产权、肖像权或隐私的内容

系统会自动过滤部分不当内容。若发现违规，我们有权限制或终止账号。

3. 用户责任
您应对自己输入的指令和生成的故事负责。请勿利用本服务制作或传播违法违规内容。多次违规可能导致账号被永久封禁。

4. 年龄要求
本应用包含可能不适合未成年人的内容（部分剧情可能涉及成熟主题）。请确认您已年满 13 周岁（或当地法律要求的最低年龄）。未成年人请在监护人指导下使用。

5. 举报与反馈
如发现不当内容，请通过应用内举报功能或联系客服反馈，我们会及时处理。

继续使用即表示您已阅读并同意以上内容须知，以及《用户协议》与《隐私政策》。
''';

  static const String _userAgreement = '''
【用户协议】（摘要）

欢迎使用 YO RAN。

1. 服务说明
本应用提供 AI 驱动的互动文字剧情体验。我们保留随时调整、暂停或终止服务的权利。

2. 账号
使用邮箱验证码登录后自动创建账号。您应妥善保管账号信息，不得将账号转让或出借给他人。

3. 使用规范
您同意遵守《内容须知》，不得利用本服务从事任何违法或侵权活动。我们有权对违规行为采取警告、限制功能或封禁账号等措施。

4. 知识产权
应用内由我们提供的内容、界面、代码等归我们所有。用户生成的故事内容在法律允许范围内由用户享有相应权利，但您授权我们用于服务改进与内容审核。

5. 免责声明
AI 生成内容仅供娱乐，我们不对内容的准确性、完整性或适用性作任何保证。因使用本服务产生的任何直接或间接损失，我们在法律允许范围内免责。

6. 协议变更
我们可能不时更新本协议。继续使用即视为接受更新后的协议。

完整版本请以正式上线后的用户协议页面为准。
''';

  static const String _privacyPolicy = '''
【隐私政策】（摘要）

我们重视您的隐私。

1. 我们收集的信息
• 登录邮箱（用于账号识别与验证码发送）
• 设备与使用日志（用于服务稳定性与安全）
• 您主动输入的故事指令与生成记录（用于提供服务及内容审核）

2. AI 相关数据处理
若使用云端 AI 服务，您的部分输入文本可能被发送至第三方模型提供商以生成回复。我们会在首次使用相关功能前征得您的明确同意，并尽量减少不必要的数据传输。优先采用本地处理以保护隐私。

3. 信息使用
仅用于提供服务、账号管理、内容安全审核、改进产品体验及法律要求。

4. 信息共享
除法律法规要求或获得您明确同意外，我们不会向第三方出售或共享您的个人信息。

5. 数据安全与保留
我们采取合理技术措施保护数据安全。账号注销后，我们将按法律规定删除或匿名化相关数据。

6. 您的权利
您可联系我们查询、更正或删除个人信息，或注销账号。

完整版本请以正式上线后的隐私政策页面为准。如有疑问，请通过应用内联系我们。
''';

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
                        // 缩小最大宽度，让输入框不会太长
                        constraints:
                            const BoxConstraints(
                          maxWidth: 320,
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
                color: Colors.white.withOpacity(.55),
                alignment: Alignment.center,
                child: Icon(
                  LucideIcons.image,
                  size: 26,
                  color: _muted.withOpacity(.52),
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
            // 字号整体调小，显得更精致
            fontSize: narrow
                ? 24
                : compact
                    ? 26
                    : 28,
            height: 1.05,
            // 减轻字重，去除“太粗”的感觉
            fontWeight: FontWeight.w400,
            letterSpacing: narrow ? 3.2 : 4.2,
          ),
        ),
        const SizedBox(height: 13),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 36,
              height: 1,
              color: const Color(0xFFC9C0A4).withOpacity(.72),
            ),
            const SizedBox(width: 8),
            Transform.rotate(
              angle: .785398,
              child: Container(
                width: 6,
                height: 6,
                color: const Color(0xFFB8AD8C).withOpacity(.82),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 36,
              height: 1,
              color: const Color(0xFFC9C0A4).withOpacity(.72),
            ),
          ],
        ),
        const SizedBox(height: 15),
        Text(
          // 改为“专属世界”
          '进入你的专属世界',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _ink.withOpacity(.72),
            fontSize: narrow ? 12 : 13,
            fontWeight: FontWeight.w500,
            letterSpacing: 1.5,
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

          // ========== 协议勾选区域 ==========
          _buildAgreementRow(),

          const SizedBox(height: 16),

          _LoginPrimaryButton(
            isLoading: _submitting,
            label: '登录',
            // 必须勾选协议后才能点击登录
            onTap: (_submitting || !_agreed)
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

  /// 协议勾选行 + 可点击的协议链接
  Widget _buildAgreementRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 22,
          height: 22,
          child: Checkbox(
            value: _agreed,
            onChanged: (value) {
              setState(() {
                _agreed = value ?? false;
                if (_agreed && _errorText == '请先阅读并勾选同意用户协议与内容须知') {
                  _errorText = null;
                }
              });
            },
            activeColor: const Color(0xFF55B84A),
            checkColor: Colors.white,
            side: BorderSide(
              color: _muted.withOpacity(.55),
              width: 1.4,
            ),
            materialTapTargetSize:
                MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text.rich(
              TextSpan(
                style: TextStyle(
                  color: _muted.withOpacity(.9),
                  fontSize: 11.5,
                  height: 1.45,
                ),
                children: [
                  const TextSpan(text: '我已阅读并同意'),
                  TextSpan(
                    text: '《用户协议》',
                    style: const TextStyle(
                      color: Color(0xFF55B84A),
                      fontWeight: FontWeight.w600,
                    ),
                    recognizer: TapGestureRecognizer()
                      ..onTap = () {
                        _showNoticeDialog(
                          title: '用户协议',
                          content: _userAgreement,
                        );
                      },
                  ),
                  const TextSpan(text: '、'),
                  TextSpan(
                    text: '《隐私政策》',
                    style: const TextStyle(
                      color: Color(0xFF55B84A),
                      fontWeight: FontWeight.w600,
                    ),
                    recognizer: TapGestureRecognizer()
                      ..onTap = () {
                        _showNoticeDialog(
                          title: '隐私政策',
                          content: _privacyPolicy,
                        );
                      },
                  ),
                  const TextSpan(text: '与'),
                  TextSpan(
                    text: '《内容须知》',
                    style: const TextStyle(
                      color: Color(0xFF55B84A),
                      fontWeight: FontWeight.w600,
                    ),
                    recognizer: TapGestureRecognizer()
                      ..onTap = () {
                        _showNoticeDialog(
                          title: '内容须知',
                          content: _contentNotice,
                        );
                      },
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
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
          duration: const Duration(milliseconds: 160),
          // 稍微调高一点，从 44 增加到 48
          height: 48,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(
              color: focused
                  ? const Color(0xFF9EC89A)
                  : const Color(0xFFE1E5DF),
              width: 1,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: <Widget>[
              const SizedBox(width: 15),
              Icon(
                icon,
                size: 17,
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
                  textInputAction: textInputAction,
                  autofillHints: autofillHints,
                  cursorColor: const Color(0xFF55A84A),
                  onChanged: onChanged,
                  onSubmitted: onSubmitted,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    hintText: hintText,
                    hintStyle: TextStyle(
                      color: _muted.withOpacity(.66),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
              if (trailing != null) ...<Widget>[
                Container(
                  width: 1,
                  height: 20,
                  color: Colors.black.withOpacity(.07),
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
      duration: const Duration(milliseconds: 150),
      opacity: enabled ? 1 : .68,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Ink(
            // 高度同步从 44 调整为 48
            height: 48,
            decoration: BoxDecoration(
              color: _LoginSheetState._accent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _LoginSheetState._ink,
                      ),
                    )
                  : Text(
                      label,
                      style: const TextStyle(
                        color: _LoginSheetState._ink,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.5,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
