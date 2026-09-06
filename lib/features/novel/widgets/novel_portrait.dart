part of '../novel_widgets.dart';

// Novel Widgets · 剧情舞台 / 立绘
// 对外入口：NovelSceneArrivalTitle / NovelPortraitStage
// 内部实现：立绘微动态、入场与说话状态动画。

class _NovelPortraitMotion extends StatefulWidget {
  const _NovelPortraitMotion({
    super.key,
    required this.speaking,
    required this.alignRight,
    required this.child,
  });

  final bool speaking;
  final bool alignRight;
  final Widget child;

  @override
  State<_NovelPortraitMotion> createState() => _NovelPortraitMotionState();
}

class _NovelPortraitMotionState extends State<_NovelPortraitMotion>
    with TickerProviderStateMixin {
  late final AnimationController _idleController;
  late final AnimationController _speechController;
  bool _animationsDisabled = false;

  @override
  void initState() {
    super.initState();
    _idleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5200),
    );
    _speechController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 620),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final disabled = MediaQuery.of(context).disableAnimations;
    if (disabled == _animationsDisabled && _idleController.isAnimating) return;

    _animationsDisabled = disabled;
    if (disabled) {
      _idleController.stop();
      _idleController.value = 0;
      _speechController.stop();
      _speechController.value = 0;
    } else if (!_idleController.isAnimating) {
      _idleController.repeat();
    }
    // 少数情况下新角色会在对白首字已经可见时直接挂载，仍应补上
    // 第一次开口的轻微反馈；已经完成过的控制器不会在依赖刷新时重播。
    if (!disabled &&
        widget.speaking &&
        _speechController.value == 0 &&
        !_speechController.isAnimating) {
      _speechController.forward();
    }
  }

  @override
  void didUpdateWidget(covariant _NovelPortraitMotion oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 逐字进度第一次进入对白时只触发一次，不跟着每个字反复跳动。
    if (!_animationsDisabled && !oldWidget.speaking && widget.speaking) {
      _speechController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _idleController.dispose();
    _speechController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_animationsDisabled) return widget.child;

    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        _idleController,
        _speechController,
      ]),
      child: widget.child,
      builder: (context, child) {
        // 从静止开始完成一次完整呼吸循环，避免循环衔接处出现顿挫。
        final idlePhase = _idleController.value * math.pi * 2;
        final breath = (1 - math.cos(idlePhase)) * .5;

        // sin(0..pi) 让对白反馈自然前倾并回到原位，而不是停在放大状态。
        final speech = math.sin(_speechController.value * math.pi)
            .clamp(0.0, 1.0)
            .toDouble();

        final scale = 1.0 + breath * .0035 + speech * .0055;
        final dy = -(breath * 2.1 + speech * 3.8);
        final dx = (widget.alignRight ? -1.0 : 1.0) * speech * 1.6;

        return Transform.translate(
          offset: Offset(dx, dy),
          child: Transform.scale(
            scale: scale,
            alignment: Alignment.bottomCenter,
            child: child,
          ),
        );
      },
    );
  }
}

class NovelSceneArrivalTitle extends StatelessWidget {
  const NovelSceneArrivalTitle({
    super.key,
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 430;
    final cleanSubtitle = subtitle.trim();
    return TweenAnimationBuilder<double>(
      key: ValueKey<String>('$title|$subtitle'),
      duration: const Duration(milliseconds: 2800),
      tween: Tween<double>(begin: 0, end: 1),
      builder: (context, value, child) {
        final opacity = value < .18
            ? value / .18
            : value > .72
                ? (1 - value) / .28
                : 1.0;
        return Opacity(
          opacity: opacity.clamp(0.0, 1.0).toDouble(),
          child: Transform.translate(
            offset: Offset(
              0,
              6.0 *
                  (1.0 - value.clamp(0.0, .3).toDouble() / .3),
            ),
            child: child,
          ),
        );
      },
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 430),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 4 : 6,
            vertical: 8,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withOpacity(.98),
                  fontFamily: 'WenJinMinchoP0',
                  fontSize: compact ? 23 : 26,
                  height: 1.12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: compact ? 2 : 2.6,
                  shadows: <Shadow>[
                    Shadow(
                      color: Colors.white.withOpacity(.72),
                      blurRadius: 8,
                    ),
                    Shadow(
                      color: Colors.white.withOpacity(.28),
                      blurRadius: 18,
                    ),
                  ],
                ),
              ),
              if (cleanSubtitle.isNotEmpty) ...<Widget>[
                const SizedBox(height: 5),
                Text(
                  cleanSubtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withOpacity(.62),
                    fontSize: compact ? 10.5 : 11.5,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 1,
                    shadows: <Shadow>[
                      Shadow(
                        color: Colors.white.withOpacity(.20),
                        blurRadius: 7,
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class NovelPortraitStage extends StatelessWidget {
  const NovelPortraitStage({
    super.key,
    required this.url,
    required this.visible,
    required this.isSpeaking,
    this.alignRight = false,
    this.gender = '',
  });

  final String url;
  final bool visible;
  final bool isSpeaking;
  final bool alignRight;
  final String gender;

  String get _defaultPortraitAsset {
    final normalized = gender.trim().toLowerCase();
    if (normalized == '男' || normalized == 'male' || normalized == 'm') {
      return 'assets/images/portrait_male.png';
    }
    return 'assets/images/portrait_female.png';
  }

  Widget _defaultPortrait() {
    return Image.asset(
      _defaultPortraitAsset,
      // 500×800 的角色图统一按“半身窗口”裁剪，而不是完整缩小。
      fit: BoxFit.cover,
      alignment: Alignment.topCenter,
      filterQuality: FilterQuality.medium,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
    );
  }

  Widget _portraitImage() {
    final value = url.trim();
    if (value.startsWith('data:image/')) {
      try {
        return Image.memory(
          base64Decode(value.split(',').last),
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
          filterQuality: FilterQuality.medium,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => _defaultPortrait(),
        );
      } catch (_) {
        return _defaultPortrait();
      }
    }
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return Image.network(
        value,
        fit: BoxFit.cover,
        alignment: Alignment.topCenter,
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => _defaultPortrait(),
      );
    }
    if (value.isNotEmpty) {
      return Image.asset(
        value,
        fit: BoxFit.cover,
        alignment: Alignment.topCenter,
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => _defaultPortrait(),
      );
    }
    return _defaultPortrait();
  }

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();

    final screen = MediaQuery.sizeOf(context);
    final compact = screen.width < 520;

    // NPC 靠左，玩家/主角靠右。
    final alignment = alignRight ? Alignment.bottomRight : Alignment.bottomLeft;
    final beginOffset =
        alignRight ? const Offset(.055, .018) : const Offset(-.055, .018);

    // 这里是以后最常调的两个参数：
    // widthFactor 越大，人物越大；aspectRatio 越大，纵向裁剪越狠。
    // 500×800 立绘用接近 1:1 的裁剪窗口，大约保留上方 60%～65%，
    // 会得到头部到腰/大腿附近的视觉小说半身构图。
    final widthFactor = compact ? .86 : .62;
    final cropAspectRatio = compact ? .98 : 1.02;

    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 360),
        curve: Curves.easeOutCubic,
        child: Padding(
          padding: EdgeInsets.only(
            left: alignRight ? 0 : (compact ? 4 : 24),
            right: alignRight ? (compact ? 4 : 24) : 0,
          ),
          child: Align(
            alignment: alignment,
            child: FractionallySizedBox(
              widthFactor: widthFactor,
              alignment: alignment,
              child: AspectRatio(
                aspectRatio: cropAspectRatio,
                child: ClipRect(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 430),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) {
                      final slide = Tween<Offset>(
                        begin: beginOffset,
                        end: Offset.zero,
                      ).animate(
                        CurvedAnimation(
                          parent: animation,
                          curve: Curves.easeOutCubic,
                        ),
                      );
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: slide,
                          child: child,
                        ),
                      );
                    },
                    child: AnimatedScale(
                      key: ValueKey<String>('${url.trim()}|${gender.trim()}'),
                      // 说话时只给非常轻微的呼吸感，不再额外把人物放大一圈。
                      scale: isSpeaking ? 1.006 : 1,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.topCenter,
                      child: SizedBox.expand(
                        child: _portraitImage(),
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
