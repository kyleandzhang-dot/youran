import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'api/api_client.dart';
import 'app_shared.dart';

class CreateWorldDialog extends StatefulWidget {
  const CreateWorldDialog({
    super.key,
    this.generatePath = defaultGeneratePath,
    this.onTaskSubmitted,
  });

  static const String defaultGeneratePath =
      '/chat/ai/generate-scenario/submit';

  final String generatePath;
  final ValueChanged<String>? onTaskSubmitted;

  /// 提交任务后先通知外层立即显示真实生成进度，再播放“收进左下角”的交接动画。
  static Future<String?> show(
    BuildContext context, {
    String generatePath = defaultGeneratePath,
    ValueChanged<String>? onTaskSubmitted,
  }) {
    return showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '创建世界',
      barrierColor: Colors.black.withOpacity(0.16),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (context, animation, secondaryAnimation) {
        return CreateWorldDialog(
          generatePath: generatePath,
          onTaskSubmitted: onTaskSubmitted,
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.98, end: 1.0).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            ),
            child: child,
          ),
        );
      },
    );
  }

  @override
  State<CreateWorldDialog> createState() => _CreateWorldDialogState();
}

class _CreateWorldDialogState extends State<CreateWorldDialog>
    with TickerProviderStateMixin {
  static const String _selectedMode = 'novel';
  static const String _qualityMode = 'standard';

  static const Color _background = Color(0xFFFCFDFB);
  static const Color _fieldBackground = Color(0xFFF4F6F2);
  static const Color _textPrimary = Color(0xFF303730);
  static const Color _textSecondary = Color(0xFF70786F);
  static const Color _textMuted = Color(0xFFA3AAA2);
  static const Color _themeGreen = Color.fromARGB(255, 129, 246, 112);

  final TextEditingController _controller = TextEditingController();

  bool _isLoading = false;
  bool _showError = false;
  bool _handoffActive = false;
  String? _requestError;

  late final AnimationController _shakeController;
  late final AnimationController _handoffController;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _handoffController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 720),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _shakeController.dispose();
    _handoffController.dispose();
    super.dispose();
  }

  Future<void> _handleCreate() async {
    final idea = _controller.text.trim();
    if (idea.isEmpty) {
      setState(() {
        _showError = true;
        _requestError = null;
      });
      _shakeController.forward(from: 0.0);
      return;
    }

    if (_isLoading || _handoffActive) return;

    if (ApiClient.instance.accessToken == null ||
        ApiClient.instance.accessToken!.trim().isEmpty) {
      _showRequestError('请先登录');
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _showError = false;
      _requestError = null;
      _isLoading = true;
    });

    try {
      if (ApiClient.instance.userId == null ||
          ApiClient.instance.userId!.trim().isEmpty) {
        throw ApiException('当前登录状态缺少用户ID，请重新登录');
      }

      final submitResponse = await ApiClient.instance.post(
        widget.generatePath,
        body: <String, dynamic>{
          'idea': idea,
          'mode': _selectedMode,
          'quality_mode': _qualityMode,
          'enable_refinement': false,
        },
      );

      if (!mounted) return;

      final data =
          submitResponse is Map ? submitResponse['data'] ?? submitResponse : {};
      final taskId = data['task_id']?.toString().trim();

      if (taskId == null || taskId.isEmpty) {
        throw ApiException('生成任务提交成功，但后端没有返回 task_id');
      }

      // 先把真实任务交给 GameShell：左下角进度立即开始，不等弹窗消失。
      widget.onTaskSubmitted?.call(taskId);

      setState(() {
        _isLoading = false;
        _handoffActive = true;
      });

      // 给用户一个很短的“已接收”确认，再把卡片收进左下角进度区。
      await Future<void>.delayed(const Duration(milliseconds: 260));
      if (!mounted) return;
      await _handoffController.forward(from: 0);
      if (!mounted) return;
      Navigator.of(context).pop(taskId);
    } on ApiException catch (error) {
      if (!mounted) return;
      _showRequestError(error.message);
    } catch (error) {
      if (!mounted) return;
      _showRequestError('生成失败：$error');
    } finally {
      if (mounted && !_handoffActive) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showRequestError(String message) {
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _requestError = message;
    });
  }

  void _triggerShake() {
    setState(() => _showError = true);
    _shakeController.forward(from: 0.0);
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final keyboard = media.viewInsets.bottom;

    return PopScope(
      canPop: !_isLoading && !_handoffActive,
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          child: AnimatedPadding(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.fromLTRB(18, 20, 18, 20 + keyboard),
            child: Center(
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                child: AnimatedBuilder(
                  animation: _handoffController,
                  builder: (context, handoffChild) {
                    final raw = _handoffController.value;
                    final t = Curves.easeInOutCubic.transform(raw);
                    final screen = MediaQuery.sizeOf(context);
                    final targetX = -(screen.width * 0.5 - 92);
                    final targetY = screen.height * 0.5 - 92;
                    final scale = 1.0 - 0.78 * t;
                    final opacity =
                        (1.0 - 0.88 * t).clamp(0.0, 1.0).toDouble();

                    return Transform.translate(
                      offset: Offset(targetX * t, targetY * t),
                      child: Transform.scale(
                        scale: scale,
                        child: Opacity(opacity: opacity, child: handoffChild),
                      ),
                    );
                  },
                  child: AnimatedBuilder(
                    animation: _shakeController,
                    builder: (context, child) {
                      final t = _shakeController.value;
                      final offset = _showError
                          ? math.sin(t * math.pi * 6) * 5 * (1 - t)
                          : 0.0;
                      return Transform.translate(
                        offset: Offset(offset, 0),
                        child: child,
                      );
                    },
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Container(
                        width: media.size.width * 0.90,
                        padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
                        decoration: BoxDecoration(
                          color: _background,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.08),
                              blurRadius: 24,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 180),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          child: _handoffActive
                              ? _buildHandoffView()
                              : _buildInputView(),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHandoffView() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 10),
      child: Column(
        key: ValueKey<String>('handoff'),
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            '世界已开始生成',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: 7),
          Text(
            '生成进度将在左下角继续显示',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _textSecondary,
              fontSize: 12,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputView() {
    return Column(
      key: const ValueKey<String>('input'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(),
        const SizedBox(height: 18),
        _buildInputArea(),
        if (_requestError != null) ...[
          const SizedBox(height: 10),
          Text(
            _requestError!,
            style: const TextStyle(
              color: Color(0xFFC86760),
              fontSize: 11.5,
              height: 1.4,
            ),
          ),
        ],
        const SizedBox(height: 16),
        _buildSubmitButton(),
      ],
    );
  }

  Widget _buildHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '创建世界',
                style: TextStyle(
                  color: _textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: 5),
              Text(
                '告诉我想要玩什么样的世界',
                style: TextStyle(
                  color: _textSecondary,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        TextButton(
          onPressed: (_isLoading || _handoffActive)
              ? null
              : () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(
            foregroundColor: _textSecondary,
            disabledForegroundColor: _textMuted.withOpacity(0.5),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text(
            '关闭',
            style: TextStyle(fontSize: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 10),
      decoration: BoxDecoration(
        color: _showError
            ? const Color(0xFFFFF6F5)
            : _fieldBackground,
        borderRadius: BorderRadius.circular(8),
        border: _showError
            ? Border.all(color: const Color(0xFFE9A6A1), width: 1)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _controller,
            maxLines: 6,
            minLines: 4,
            textInputAction: TextInputAction.newline,
            cursorColor: _themeGreen,
            style: const TextStyle(
              color: _textPrimary,
              fontSize: 13.5,
              height: 1.5,
            ),
            onChanged: (text) {
              if (_showError && text.trim().isNotEmpty) {
                setState(() => _showError = false);
              }
              if (_requestError != null) {
                setState(() => _requestError = null);
              }
            },
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.zero,
              hintText: '例如：我是张三，男，25岁，这是近未来城市中，人类与仿生人共同生活……',
              hintStyle: TextStyle(
                color: _textMuted,
                fontSize: 13,
                height: 1.5,
              ),
              border: InputBorder.none,
            ),
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _controller,
            builder: (context, value, child) {
              final len = value.text.length;
              if (len == 0 && _showError) {
                return const Text(
                  '请输入设定内容',
                  style: TextStyle(
                    color: Color(0xFFC86760),
                    fontSize: 11,
                  ),
                  textAlign: TextAlign.right,
                );
              }
              return Text(
                len > 0 ? '$len 字' : '描述越具体，生成结果越稳定',
                style: const TextStyle(
                  color: _textMuted,
                  fontSize: 11,
                ),
                textAlign: TextAlign.right,
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSubmitButton() {
    final disabled = _isLoading || _handoffActive;

    return Material(
      color: disabled ? _themeGreen.withOpacity(0.46) : _themeGreen,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: disabled
            ? null
            : () {
                if (_controller.text.trim().isEmpty) {
                  _triggerShake();
                  return;
                }
                _handleCreate();
              },
        child: SizedBox(
          height: 48,
          child: Center(
            child: _isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF303730),
                    ),
                  )
                : const Text(
                    '创建',
                    style: TextStyle(
                      color: _textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
