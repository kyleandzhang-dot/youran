part of '../novel_widgets.dart';

// Novel Widgets · 剧情反馈动画
// 对外入口：NovelBrewingOverlay / NovelDamageFeedbackOverlay / NovelDiceOverlay / NovelTimeSkipOverlay / NovelStatusBanner
// 内部实现：生成中、伤势、骰子、时间跳转等覆盖层。

class NovelBrewingOverlay extends StatefulWidget {
  const NovelBrewingOverlay({super.key});

  @override
  State<NovelBrewingOverlay> createState() => _NovelBrewingOverlayState();
}

class _NovelBrewingOverlayState extends State<NovelBrewingOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          ColoredBox(color: Colors.black.withOpacity(.18)),
          Center(
            child: Transform.translate(
              offset: const Offset(0, -18),
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  final progress = reduceMotion ? .5 : _controller.value;

                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      SizedBox(
                        width: 116,
                        height: 8,
                        child: Stack(
                          alignment: Alignment.center,
                          clipBehavior: Clip.none,
                          children: <Widget>[
                            Container(
                              height: 1,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: <Color>[
                                    Colors.transparent,
                                    NovelPalette.text.withOpacity(.18),
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                            ),
                            Align(
                              alignment: Alignment(
                                -1.25 + progress * 2.5,
                                0,
                              ),
                              child: Container(
                                width: 30,
                                height: 1.4,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: <Color>[
                                      Colors.transparent,
                                      NovelPalette.accentSoft.withOpacity(.92),
                                      Colors.transparent,
                                    ],
                                  ),
                                  boxShadow: <BoxShadow>[
                                    BoxShadow(
                                      color: NovelPalette.accent.withOpacity(.32),
                                      blurRadius: 8,
                                      spreadRadius: 1,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '故事正在展开',
                        style: TextStyle(
                          color: NovelPalette.text.withOpacity(.78),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 2.8,
                          shadows: const <Shadow>[
                            Shadow(
                              color: Color(0x66000000),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
/// 主角伤势状态的屏幕级反馈。
///
/// 屏幕边缘长期跟随当前伤势等级：轻伤琥珀黄、重伤红、濒危紫红；
/// 状态越严重，呼吸越快、侵入视野越深。真实掉血时再额外叠加一次短促冲击。
class NovelDamageFeedbackOverlay extends StatefulWidget {
  const NovelDamageFeedbackOverlay({
    super.key,
    required this.hp,
  });

  final int hp;

  @override
  State<NovelDamageFeedbackOverlay> createState() =>
      _NovelDamageFeedbackOverlayState();
}

class _NovelDamageFeedbackOverlayState
    extends State<NovelDamageFeedbackOverlay> with TickerProviderStateMixin {
  late final AnimationController _hitController;
  late final AnimationController _breathController;
  late final Animation<double> _hitOpacity;
  late final Animation<double> _breathPhase;

  @override
  void initState() {
    super.initState();
    _hitController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 820),
    );
    _hitOpacity = TweenSequence<double>(<TweenSequenceItem<double>>[
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: 0, end: 1)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 12,
      ),
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: 1, end: 0)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 88,
      ),
    ]).animate(_hitController);

    _breathController = AnimationController(
      vsync: this,
      duration: _breathDuration,
    );
    _breathPhase = CurvedAnimation(
      parent: _breathController,
      curve: Curves.easeInOutSine,
    );
    _syncBreathing();
  }

  @override
  void didUpdateWidget(covariant NovelDamageFeedbackOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);

    // 只有真实掉血才触发一次“受击冲击”；常驻边缘效果由当前伤势等级决定。
    if (widget.hp < oldWidget.hp) {
      _hitController.forward(from: 0);
    }

    if (widget.hp != oldWidget.hp) {
      _syncBreathing();
    }
  }

  Duration get _breathDuration {
    // 手机端只让重伤 / 濒危持续呼吸：轻伤保持静态边缘，避免无意义常驻刷新。
    if (widget.hp <= 15) return const Duration(milliseconds: 1650); // 濒危：明显但不过快
    if (widget.hp <= 40) return const Duration(milliseconds: 2800); // 重伤：缓慢压迫
    return const Duration(milliseconds: 3000);
  }

  void _syncBreathing() {
    if (widget.hp <= 40) {
      // 只有重伤 / 濒危持续动画；轻伤及健康状态完全停止 ticker。
      final currentValue = _breathController.value;
      _breathController
        ..stop()
        ..duration = _breathDuration
        ..value = currentValue
        ..repeat(reverse: true);
    } else {
      _breathController
        ..stop()
        ..value = 0;
    }
  }

  /// 与头像光圈 / HP 条完全使用同一套状态色：
  /// 健康=绿（不显示边缘），轻伤=琥珀黄，重伤=红，濒危=紫红。
  Color get _stateColor {
    if (widget.hp <= 15) return const Color(0xFFC15CFF);
    if (widget.hp <= 40) return const Color(0xFFEF5D5D);
    if (widget.hp <= 75) return const Color(0xFFF2B648);
    return NovelPalette.accent;
  }

  double get _baseEdgeOpacity {
    if (widget.hp <= 15) return .16;
    if (widget.hp <= 40) return .095;
    if (widget.hp <= 75) return .072;
    return 0;
  }

  double get _breathEdgeOpacity {
    if (widget.hp <= 15) return .14;
    if (widget.hp <= 40) return .055;
    return 0;
  }

  double get _hitStrength {
    if (widget.hp <= 15) return .30;
    if (widget.hp <= 40) return .27;
    if (widget.hp <= 75) return .22;
    return .18;
  }

  double get _darkVignetteStrength {
    if (widget.hp <= 15) return .14;
    if (widget.hp <= 40) return .055;
    return 0;
  }

  @override
  void dispose() {
    _hitController.dispose();
    _breathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: Listenable.merge(<Listenable>[
          _breathController,
          _hitController,
        ]),
        builder: (context, _) {
          if (widget.hp > 75 && !_hitController.isAnimating) {
            return const SizedBox.shrink();
          }

          final breath = widget.hp <= 40 ? _breathPhase.value : 0.0;
          final hit = _hitOpacity.value;
          final color = _stateColor;

          // 常驻状态 + 呼吸变化 + 刚掉血时的一次冲击。
          final edgeOpacity = (_baseEdgeOpacity +
                  breath * _breathEdgeOpacity +
                  hit * _hitStrength)
              .clamp(0.0, .58)
              .toDouble();
          final flashOpacity = (hit * (widget.hp <= 40 ? .075 : .045))
              .clamp(0.0, .085)
              .toDouble();
          final darkOpacity = (_darkVignetteStrength * (.55 + breath * .45))
              .clamp(0.0, .18)
              .toDouble();

          // 按实际屏幕尺寸计算侵入深度，避免固定像素在不同手机 / 平板 / 横屏下失真。
          // 这里使用当前根页面的 MediaQuery 尺寸；Overlay 本身由根 Stack 的 Positioned.fill 约束。
          final screenSize = MediaQuery.sizeOf(context);
          final verticalRatio = widget.hp <= 15
              ? .18
              : widget.hp <= 40
                  ? .145
                  : .135;
          final horizontalRatio = widget.hp <= 15
              ? .105
              : widget.hp <= 40
                  ? .082
                  : .078;
          final verticalDepth = (screenSize.height * verticalRatio)
              .clamp(72.0, 220.0)
              .toDouble();
          final horizontalDepth = (screenSize.width * horizontalRatio)
              .clamp(32.0, 120.0)
              .toDouble();

          return Stack(
            fit: StackFit.expand,
            children: <Widget>[
              // 掉血瞬间轻闪一下当前伤势颜色，作为“命中反馈”。
              if (flashOpacity > 0)
                ColoredBox(color: color.withOpacity(flashOpacity)),

              // 重伤 / 濒危时增加暗角压迫，但不遮正文。
              if (darkOpacity > 0)
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment.center,
                      radius: .86,
                      colors: <Color>[
                        Colors.transparent,
                        Colors.transparent,
                        Colors.black.withOpacity(darkOpacity),
                      ],
                      stops: const <double>[0, .64, 1],
                    ),
                  ),
                ),

              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: verticalDepth,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: <Color>[
                        color.withOpacity(edgeOpacity),
                        color.withOpacity(edgeOpacity * .34),
                        Colors.transparent,
                      ],
                      stops: const <double>[0, .38, 1],
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                height: verticalDepth * 1.08,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: <Color>[
                        color.withOpacity(edgeOpacity),
                        color.withOpacity(edgeOpacity * .36),
                        Colors.transparent,
                      ],
                      stops: const <double>[0, .40, 1],
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 0,
                bottom: 0,
                left: 0,
                width: horizontalDepth,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: <Color>[
                        color.withOpacity(edgeOpacity * .96),
                        color.withOpacity(edgeOpacity * .28),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 0,
                bottom: 0,
                right: 0,
                width: horizontalDepth,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerRight,
                      end: Alignment.centerLeft,
                      colors: <Color>[
                        color.withOpacity(edgeOpacity * .96),
                        color.withOpacity(edgeOpacity * .28),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class NovelDiceOverlay extends StatelessWidget {
  const NovelDiceOverlay({super.key, required this.roll});

  final NovelDiceRoll roll;

  Color get _glowColor {
    return switch (roll.effect) {
      'critical' => const Color(0xFFF4C542),
      'fumble' => const Color(0xFFB38AE3),
      'fail' => const Color(0xFFE77A72),
      'partial' => const Color(0xFFE8C58B),
      _ => const Color(0xFF91D5A7),
    };
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
        child: _AdaptiveBackdropBlur(
            sigma: 7,
            child: ColoredBox(
                color: Colors.black.withOpacity(.34),
                child: Center(
                    child: Transform.translate(
                        offset: const Offset(0, -42),
                        child: TweenAnimationBuilder<double>(
                            duration: const Duration(milliseconds: 680),
                            tween: Tween<double>(begin: 0, end: 1),
                            curve: Curves.easeOutBack,
                            builder: (context, value, child) {
                              return Opacity(opacity: value.clamp(0.0, 1.0).toDouble(), child: Transform.scale(scale: .78 + value * .22, child: child));
                            },
                            child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
                              Icon(
                                Icons.auto_awesome, 
                                size: 36, 
                                color: Colors.white.withOpacity(.94), 
                                shadows: <Shadow>[Shadow(color: _glowColor.withOpacity(.85), blurRadius: 20)]
                              ),
                              const SizedBox(height: 14),
                              Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                                Container(width: 34, height: 1, color: _glowColor.withOpacity(.36)),
                                const SizedBox(width: 14),
                                Text('命运判定', style: TextStyle(color: Colors.white.withOpacity(.70), fontSize: 11.5, fontWeight: FontWeight.w600, letterSpacing: 3.0)),
                                const SizedBox(width: 14),
                                Container(width: 34, height: 1, color: _glowColor.withOpacity(.36)),
                              ]),
                              const SizedBox(height: 18),
                              Text('${roll.roll}', style: TextStyle(color: Colors.white, fontSize: 72, height: .95, fontWeight: FontWeight.w900, shadows: <Shadow>[Shadow(color: _glowColor.withOpacity(.90), blurRadius: 18), Shadow(color: _glowColor.withOpacity(.46), blurRadius: 42)])),
                              const SizedBox(height: 13),
                              Text(roll.label, style: const TextStyle(color: NovelPalette.text, fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: .8)),
                              if (roll.skill.isNotEmpty || roll.dc > 0) ...<Widget>[
                                const SizedBox(height: 8),
                                Text('${roll.skill}${roll.dc > 0 ? '  ·  DC ${roll.dc}' : ''}', style: TextStyle(color: Colors.white.withOpacity(.48), fontSize: 11, letterSpacing: .4)),
                              ]
                            ])))))));
  }
}

class NovelTimeSkipOverlay extends StatefulWidget {
  const NovelTimeSkipOverlay({
    super.key,
    required this.label,
    required this.onDismiss,
  });

  final String label;
  final VoidCallback onDismiss;

  @override
  State<NovelTimeSkipOverlay> createState() => _NovelTimeSkipOverlayState();
}

class _NovelTimeSkipOverlayState extends State<NovelTimeSkipOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<double> _scale;
  late final Animation<double> _lift;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    );

    _opacity = TweenSequence<double>(<TweenSequenceItem<double>>[
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: 0, end: 1)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 18,
      ),
      TweenSequenceItem<double>(
        tween: ConstantTween<double>(1),
        weight: 60,
      ),
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: 1, end: 0)
            .chain(CurveTween(curve: Curves.easeInCubic)),
        weight: 22,
      ),
    ]).animate(_controller);

    _scale = Tween<double>(begin: .985, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0, .28, curve: Curves.easeOutCubic),
      ),
    );
    _lift = Tween<double>(begin: 8, end: 0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0, .28, curve: Curves.easeOutCubic),
      ),
    );

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) _dismiss();
    });
    _controller.forward();
  }

  void _dismiss() {
    if (_dismissed) return;
    _dismissed = true;
    widget.onDismiss();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final compact = NovelViewportMetrics.of(context).compactContent;
    final cleanLabel = widget.label.trim();
    final labelLength = cleanLabel.runes.length;
    final letterSpacing = labelLength <= 4 ? 7.0 : (labelLength <= 8 ? 4.0 : 2.0);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _dismiss,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final opacity = _opacity.value.clamp(0.0, 1.0).toDouble();
          final scale = reduceMotion ? 1.0 : _scale.value;
          final lift = reduceMotion ? 0.0 : _lift.value;

          return Opacity(
            opacity: opacity,
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                ColoredBox(
                  color: Colors.black.withOpacity(.64),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0, -.06),
                      radius: .78,
                      colors: <Color>[
                        Colors.white.withOpacity(.018),
                        Colors.transparent,
                        Colors.black.withOpacity(.14),
                      ],
                      stops: const <double>[0, .54, 1],
                    ),
                  ),
                ),
                Center(
                  child: Transform.translate(
                    offset: Offset(0, lift),
                    child: Transform.scale(
                      scale: scale,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Text(
                          cleanLabel,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.fade,
                          style: TextStyle(
                            color: Colors.white.withOpacity(.94),
                            fontSize: compact ? 25 : 30,
                            height: 1.35,
                            fontWeight: FontWeight.w400,
                            letterSpacing: letterSpacing,
                            shadows: <Shadow>[
                              Shadow(
                                color: Colors.black.withOpacity(.42),
                                blurRadius: 18,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class NovelStatusBanner extends StatelessWidget {
  const NovelStatusBanner({
    super.key,
    required this.message,
    required this.isError,
    required this.onDismiss,
  });

  final String message;
  final bool isError;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    if (message.isEmpty) return const SizedBox.shrink();
    return SafeArea(
        child: Align(
      alignment: Alignment.topCenter,
      child: Padding(
          padding: const EdgeInsets.only(top: 64, left: 24, right: 24),
          child: GestureDetector(
            onTap: onDismiss,
            child: _GlassSurface(
                radius: 13,
                child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                    child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                      Icon(isError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded, color: isError ? NovelPalette.danger : NovelPalette.accent, size: 17),
                      const SizedBox(width: 9),
                      Flexible(child: Text(message, style: const TextStyle(color: NovelPalette.text, fontSize: 12))),
                    ]))),
          )),
    ));
  }
}
