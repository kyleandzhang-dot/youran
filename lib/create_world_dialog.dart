import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'api/api_client.dart';
import 'app_shared.dart';

class CreateWorldDialog extends StatefulWidget {
  const CreateWorldDialog({
    super.key,
    this.generatePath = defaultGeneratePath,
  });

  static const String defaultGeneratePath =
      '/chat/ai/generate-scenario/submit';

  final String generatePath;

  /// 现在只负责提交任务，成功后返回 taskId 给外层页面去异步轮询
  static Future<String?> show(
    BuildContext context, {
    String generatePath = defaultGeneratePath,
  }) {
    return showGeneralDialog<String>(
      context: context,
      barrierDismissible: true, // 允许点击外部遮罩关闭
      barrierLabel: 'Create world',
      barrierColor: Colors.black.withOpacity(0.68),
      transitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Center(
          child: CreateWorldDialog(
            generatePath: generatePath,
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
    with SingleTickerProviderStateMixin {
  static const String _selectedMode = 'novel';
  static const String _qualityMode = 'standard';

  final TextEditingController _controller = TextEditingController();

  bool _isLoading = false;
  bool _showError = false;
  String? _requestError;

  late final AnimationController _shakeController;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _shakeController.dispose();
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

    if (_isLoading) return;

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

      // 提交成功，直接关闭弹窗并返回 taskId
      Navigator.of(context).pop(taskId);

    } on ApiException catch (error) {
      if (!mounted) return;
      _showRequestError(error.message);
    } catch (error) {
      if (!mounted) return;
      _showRequestError('生成失败：$error');
    } finally {
      if (mounted) {
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
      canPop: !_isLoading,
      child: Material(
        color: Colors.transparent,
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
              child: _buildInputView(),
            ),
          ),
        ),
      ),
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
          onTap: () => Navigator.of(context).pop(),
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