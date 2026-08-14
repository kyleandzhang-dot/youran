import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';

// import 'app_shared.dart'; // 请按需保留你的全局引入

enum AppNoticeTone {
  success,
  info,
  error,
}

/// 全局顶部轻提示（基于 Overlay，完全不挤占画布空间）
class AppNotice {
  AppNotice._();

  static OverlayEntry? _currentEntry;

  static void success(
    BuildContext context,
    String message, {
    Duration duration = const Duration(milliseconds: 2200),
  }) {
    _show(context, message, tone: AppNoticeTone.success, duration: duration);
  }

  static void info(
    BuildContext context,
    String message, {
    Duration duration = const Duration(milliseconds: 2200),
  }) {
    _show(context, message, tone: AppNoticeTone.info, duration: duration);
  }

  static void error(
    BuildContext context,
    String message, {
    Duration duration = const Duration(milliseconds: 2600),
  }) {
    _show(context, message, tone: AppNoticeTone.error, duration: duration);
  }

  static void _show(
    BuildContext context,
    String message, {
    required AppNoticeTone tone,
    required Duration duration,
  }) {
    final value = message.trim();
    if (value.isEmpty) return;

    hide();

    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;

    final entry = OverlayEntry(
      builder: (context) => _NoticeOverlayWidget(
        message: value,
        tone: tone,
        duration: duration,
        onDismissed: hide,
      ),
    );

    _currentEntry = entry;
    overlay.insert(entry);
  }

  static void hide() {
    if (_currentEntry != null) {
      _currentEntry?.remove();
      _currentEntry = null;
    }
  }
}

class _NoticeOverlayWidget extends StatefulWidget {
  const _NoticeOverlayWidget({
    required this.message,
    required this.tone,
    required this.duration,
    required this.onDismissed,
  });

  final String message;
  final AppNoticeTone tone;
  final Duration duration;
  final VoidCallback onDismissed;

  @override
  State<_NoticeOverlayWidget> createState() => _NoticeOverlayWidgetState();
}

class _NoticeOverlayWidgetState extends State<_NoticeOverlayWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -0.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));

    _controller.forward();

    _timer = Timer(widget.duration, () {
      if (mounted) {
        _controller.reverse().then((_) => widget.onDismissed());
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final IconData icon;
    final Color iconColor;
    final Color iconBackground;

    switch (widget.tone) {
      case AppNoticeTone.success:
        icon = Icons.check_rounded;
        iconColor = const Color(0xFF76B900); // 英伟达绿
        iconBackground = const Color(0xFF76B900).withOpacity(0.15);
        break;
      case AppNoticeTone.error:
        icon = Icons.close_rounded;
        iconColor = const Color(0xFFC45B54);
        iconBackground = const Color(0xFFFFEEEC);
        break;
      case AppNoticeTone.info:
        icon = Icons.info_outline_rounded;
        iconColor = const Color(0xFF697069);
        iconBackground = const Color(0xFFF0F2EF);
        break;
    }

    return Positioned(
      top: MediaQuery.paddingOf(context).top + 16,
      left: 0,
      right: 0,
      child: Material(
        color: Colors.transparent,
        child: SlideTransition(
          position: _slideAnimation,
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: Center(
              child: Container(
                constraints: const BoxConstraints(
                  maxWidth: 280,
                  minHeight: 42,
                ),
                decoration: BoxDecoration(
                  // 外层微圆角
                  borderRadius: BorderRadius.circular(12),
                  // 极弱的弥散阴影
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x0C000000),
                      blurRadius: 14,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                // 必须通过 ClipRRect 严格裁剪，防止内部 BackdropFilter 和颜色溢出导致直角
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(11, 8, 16, 8),
                      decoration: BoxDecoration(
                        // 偏白的明亮底色
                        color: const Color(0xFFFFFFFF).withOpacity(0.9),
                        border: Border.all(
                          color: const Color(0xFFE8EBE6),
                          width: 0.8,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 22,
                            height: 22,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: iconBackground,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              icon,
                              size: 14,
                              color: iconColor,
                            ),
                          ),
                          const SizedBox(width: 9),
                          Flexible(
                            child: Text(
                              widget.message,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF252925),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                height: 1.2,
                              ),
                            ),
                          ),
                        ],
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
}