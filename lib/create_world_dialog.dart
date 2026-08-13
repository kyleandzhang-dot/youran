import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

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
      barrierDismissible: true, // 允许点击外部遮罩关闭
      barrierLabel: '创建世界',
      barrierColor: Colors.black.withOpacity(0.68),
      transitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Center(
          child: CreateWorldDialog(
            generatePath: generatePath,
            onTaskSubmitted: onTaskSubmitted,
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.95, end: 1.0).animate(
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

      final data = submitResponse is Map ? submitResponse['data'] ?? submitResponse : {};
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
    return PopScope(
      canPop: !_isLoading && !_handoffActive,
      child: Material(
        color: Colors.transparent,
        child: AnimatedBuilder(
          animation: _handoffController,
          builder: (context, handoffChild) {
            final raw = _handoffController.value;
            final t = Curves.easeInOutCubic.transform(raw);
            final screen = MediaQuery.sizeOf(context);
            final targetX = -(screen.width * 0.5 - 92);
            final targetY = screen.height * 0.5 - 92;
            final scale = 1.0 - 0.78 * t;
            final opacity = (1.0 - 0.88 * t).clamp(0.0, 1.0).toDouble();

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
              constraints: const BoxConstraints(maxWidth: 380),
              child: Container(
                width: MediaQuery.sizeOf(context).width * 0.88,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF161616),
                  borderRadius: BorderRadius.zero,
                  border: Border.all(
                    color: Colors.white.withOpacity(0.12),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.5),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  child: _handoffActive ? _buildHandoffView() : _buildInputView(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHandoffView() {
    return const Column(
      key: ValueKey<String>('handoff'),
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SizedBox(
          width: 42,
          height: 42,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Color(0x1F81F670),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.check_rounded,
              size: 22,
              color: AppColors.accent,
            ),
          ),
        ),
        SizedBox(height: 14),
        Text(
          '世界已开始生成',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.textOnDark,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        SizedBox(height: 6),
        Text(
          '生成进度将移到左下角继续显示',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.textOnDarkMuted,
            fontSize: 11.5,
            height: 1.45,
          ),
        ),
      ],
    );
  }

  Widget _buildInputView() {
    return Column(
      key: const ValueKey<String>('input'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(),
        const SizedBox(height: 18),
        _buildInputArea(),
        if (_requestError != null) ...[
          const SizedBox(height: 10),
          Text(
            _requestError!,
            style: const TextStyle(
              color: Color(0xFFE7685E),
              fontSize: 11.5,
              height: 1.4,
            ),
          ),
        ],
        const SizedBox(height: 20),
        _buildSubmitButton(),
      ],
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '创建世界',
              style: TextStyle(
                color: AppColors.textOnDark,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
            SizedBox(height: 4),
            Text(
              '小说模式',
              style: TextStyle(
                color: AppColors.textOnDarkMuted,
                fontSize: 11,
              ),
            ),
          ],
        ),
        GestureDetector(
          onTap: (_isLoading || _handoffActive)
              ? null
              : () => Navigator.of(context).pop(),
          child: Container(
            padding: const EdgeInsets.all(4),
            color: Colors.transparent,
            child: const Icon(
              LucideIcons.x,
              size: 18,
              color: AppColors.textOnDarkMuted,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInputArea() {
    return Container(
      decoration: BoxDecoration(
        color: _showError
            ? const Color(0xFFE0554A).withOpacity(0.08)
            : Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.zero,
        border: Border.all(
          color: _showError
              ? const Color(0xFFE0554A).withOpacity(0.6)
              : Colors.white.withOpacity(0.1),
          width: 1,
        ),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _controller,
            maxLines: 6,
            minLines: 4,
            textInputAction: TextInputAction.newline,
            style: const TextStyle(
              color: AppColors.textOnDark,
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
              hintText: '输入小说背景、设定或世界观描述...',
              hintStyle: TextStyle(
                color: AppColors.textOnDarkMuted,
                fontSize: 13,
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
                  '请输入设定内容后创建',
                  style: TextStyle(
                    color: Color(0xFFE0554A),
                    fontSize: 11,
                  ),
                  textAlign: TextAlign.right,
                );
              }
              return Text(
                len > 0 ? '$len 字' : '描述越具体，生成结果越稳定',
                style: const TextStyle(
                  color: AppColors.textOnDarkMuted,
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
    return Material(
      color: AppColors.accent,
      child: InkWell(
        onTap: () {
          if (_controller.text.trim().isEmpty) {
            _triggerShake();
            return;
          }
          _handleCreate();
        },
        child: Container(
          height: 48,
          alignment: Alignment.center,
          // 去除多余图标，维持干净面板
          child: _isLoading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color.fromARGB(255, 12, 12, 12),
                  ),
                )
              : const Text(
                  '创建',
                  style: TextStyle(
                    color: Color.fromARGB(255, 12, 12, 12),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
        ),
      ),
    );
  }
}