part of '../novel_widgets.dart';

// Novel Widgets · 剧情控制
// 对外入口：NovelChoiceDock / NovelSideArchiveBar / NovelCinematicControls
// 内部实现：行内选项、底部控制、剧情进度、滑动回看与电影模式。

class NovelChoiceDockActionScope extends InheritedWidget {
  const NovelChoiceDockActionScope({
    super.key,
    required this.visible,
    required this.label,
    required this.attention,
    required this.loading,
    required this.onTap,
    required super.child,
  });

  final bool visible;
  final String label;
  final bool attention;
  final bool loading;
  final VoidCallback onTap;

  static NovelChoiceDockActionScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<NovelChoiceDockActionScope>();
  }

  @override
  bool updateShouldNotify(NovelChoiceDockActionScope oldWidget) {
    return visible != oldWidget.visible ||
        label != oldWidget.label ||
        attention != oldWidget.attention ||
        loading != oldWidget.loading ||
        onTap != oldWidget.onTap;
  }
}

class _NovelFloatingSurroundingsAction extends StatefulWidget {
  const _NovelFloatingSurroundingsAction({
    required this.scope,
    this.compact = false,
  });

  final NovelChoiceDockActionScope scope;
  final bool compact;

  @override
  State<_NovelFloatingSurroundingsAction> createState() =>
      _NovelFloatingSurroundingsActionState();
}

class _NovelFloatingSurroundingsActionState
    extends State<_NovelFloatingSurroundingsAction>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  bool _animationsDisabled = false;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
      lowerBound: 0,
      upperBound: 1,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _animationsDisabled = MediaQuery.of(context).disableAnimations;
    _syncPulse();
  }

  @override
  void didUpdateWidget(covariant _NovelFloatingSurroundingsAction oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scope.attention != widget.scope.attention ||
        oldWidget.scope.loading != widget.scope.loading ||
        oldWidget.scope.visible != widget.scope.visible) {
      _syncPulse();
    }
  }

  void _syncPulse() {
    if (_animationsDisabled || widget.scope.loading || !widget.scope.visible) {
      _pulse
        ..stop()
        ..value = .35;
      return;
    }
    if (!_pulse.isAnimating) _pulse.repeat();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = widget.scope;
    final compact = widget.compact;
    final haloSize = compact ? 44.0 : 50.0;
    final coreSize = compact ? 34.0 : 39.0;
    final accent = Theme.of(context).colorScheme.primary;
    final semanticLabel =
        scope.label.trim().isEmpty ? '探索周围' : scope.label.trim();

    Widget fadingRing(double phase, double emphasis) {
      final progress = Curves.easeOutCubic.transform(phase);
      final opacity = ((1.0 - phase) * (scope.attention ? .52 : .34) * emphasis)
          .clamp(0.0, 1.0)
          .toDouble();
      final scale = .82 + progress * .52;

      return Transform.scale(
        scale: scale,
        child: Container(
          width: haloSize,
          height: haloSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: accent.withOpacity(opacity),
              width: .9,
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: accent.withOpacity(opacity * .42),
                blurRadius: 5 + progress * 8,
                spreadRadius: .1 + progress * .45,
              ),
            ],
          ),
        ),
      );
    }

    return Semantics(
      button: true,
      enabled: !scope.loading,
      label: semanticLabel,
      child: Tooltip(
        message: semanticLabel,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: scope.loading ? null : scope.onTap,
          child: SizedBox(
            width: compact ? 62 : 70,
            height: compact ? 68 : 78,
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: _pulse,
                builder: (context, _) {
                  final phaseA = _animationsDisabled ? .38 : _pulse.value;
                  final phaseB = (phaseA + .5) % 1.0;
                  final wave =
                      (math.sin(phaseA * math.pi * 2) + 1.0) * .5;
                  final emphasis = scope.attention ? 1.0 : .72;

                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      SizedBox(
                        width: haloSize,
                        height: haloSize,
                        child: Stack(
                          alignment: Alignment.center,
                          clipBehavior: Clip.none,
                          children: <Widget>[
                            if (!scope.loading) fadingRing(phaseA, emphasis),
                            if (!scope.loading) fadingRing(phaseB, emphasis * .86),
                            Container(
                              width: coreSize,
                              height: coreSize,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(0xB0181C1A),
                                border: Border.all(
                                  color: accent.withOpacity(
                                    scope.attention ? .72 : .52,
                                  ),
                                  width: .85,
                                ),
                                boxShadow: <BoxShadow>[
                                  BoxShadow(
                                    color: const Color(0xCC000000)
                                        .withOpacity(.32),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                  BoxShadow(
                                    color: accent.withOpacity(
                                      (.08 + wave * .10) * emphasis,
                                    ),
                                    blurRadius: 7 + wave * 4,
                                  ),
                                ],
                              ),
                              alignment: Alignment.center,
                              child: scope.loading
                                  ? SizedBox.square(
                                      dimension: compact ? 14 : 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 1.35,
                                        color: accent.withOpacity(.90),
                                      ),
                                    )
                                  : Icon(
                                      Icons.explore_outlined,
                                      size: compact ? 20 : 23,
                                      color: accent.withOpacity(.98),
                                      shadows: <Shadow>[
                                        Shadow(
                                          color: accent.withOpacity(
                                            (.18 + wave * .12) * emphasis,
                                          ),
                                          blurRadius: 5 + wave * 3,
                                        ),
                                        const Shadow(
                                          color: Color(0xCC000000),
                                          blurRadius: 4,
                                          offset: Offset(0, 1),
                                        ),
                                      ],
                                    ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: compact ? 3 : 4),
                      Text(
                        scope.loading ? '探索中' : '可探索',
                        maxLines: 1,
                        style: TextStyle(
                          color: Colors.white.withOpacity(
                            scope.loading ? .62 : .94,
                          ),
                          fontFamily: 'WenJinMinchoP0',
                          fontSize: compact ? 9.5 : 10.4,
                          height: 1,
                          fontWeight: FontWeight.w700,
                          letterSpacing: compact ? .8 : 1.0,
                          shadows: <Shadow>[
                            Shadow(
                              color: accent.withOpacity(
                                (.10 + wave * .08) * emphasis,
                              ),
                              blurRadius: 4 + wave * 2,
                            ),
                            const Shadow(
                              color: Color(0xE0000000),
                              blurRadius: 5,
                              offset: Offset(0, 1),
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
        ),
      ),
    );
  }
}

class NovelChoiceDock extends StatelessWidget {
  const NovelChoiceDock({
    super.key,
    required this.choices,
    required this.onSelected,
  });

  final List<NovelChoice> choices;
  final ValueChanged<NovelChoice> onSelected;

  @override
  Widget build(BuildContext context) {
    final viewport = NovelViewportMetrics.of(context);
    final compact = viewport.narrowWidth;
    final shortViewport = viewport.shortViewport;

    // 选择区改成输入框上方的一条轻量横向操作带：
    // 不再显示“请做出你的选择”标题、菱形和装饰线，避免抢剧情画面。
    return SizedBox(
      width: double.infinity,
      height: shortViewport ? 38 : (compact ? 42 : 44),
      child: _InlineNovelChoices(
        choices: choices,
        onSelected: onSelected,
        onCustomInput: () {},
        onContinue: () {},
      ),
    );
  }
}

class _ChoiceColors {
  static const Color card = Color(0x0AFFFFFF);
  static const Color border = Color(0x1AFFFFFF);
  static const Color numberBg = Color(0x0AFFFFFF);
  static const Color numberBorder = Color(0x38FFFFFF);
}

class _InlineNovelChoices extends StatelessWidget {
  const _InlineNovelChoices({
    required this.choices,
    required this.onSelected,
    required this.onCustomInput,
    required this.onContinue,
  });

  final List<NovelChoice> choices;
  final ValueChanged<NovelChoice> onSelected;
  final VoidCallback onCustomInput;
  final VoidCallback onContinue;

  IconData _fallbackIconFor(NovelChoice choice) {
    if (choice.isBattle) return Icons.flash_on_rounded;
    if (choice.isAction) return Icons.casino_outlined;
    return Icons.chat_bubble_outline_rounded;
  }

  Widget _buildChoiceIcon(NovelChoice choice, {required bool compact}) {
    final size = compact ? 18.0 : 20.0;
    return SizedBox(
      width: size,
      height: size,
      child: Image.asset(
        choice.iconPath,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => Icon(
          _fallbackIconFor(choice),
          size: size,
          color: Colors.white.withOpacity(.62),
        ),
      ),
    );
  }

  double _choiceWidth({
    required double availableWidth,
    required int count,
    required bool compact,
  }) {
    // 选择条与底部输入框共用同一条左边界，不再额外缩进。
    // 右侧只留很小的滑动呼吸区，避免最后一张贴死屏幕边缘。
    final rightPadding = compact ? 7.0 : 9.0;
    final gap = compact ? 6.0 : 7.0;
    final viewport = math.max(0.0, availableWidth - rightPadding);

    // 1~2 个选择时尽量并排填满，但保持“轻量按钮”而不是大卡片。
    if (count == 1) {
      return (viewport * (compact ? .64 : .48))
          .clamp(compact ? 172.0 : 190.0, compact ? 238.0 : 280.0)
          .toDouble();
    }
    if (count == 2) {
      return ((viewport - gap) / 2)
          .clamp(compact ? 142.0 : 158.0, compact ? 210.0 : 250.0)
          .toDouble();
    }

    // 3 个及以上固定为“一排横滑”，刻意露出下一张的一部分，提示用户可左右滑动。
    return (viewport * (compact ? .46 : .31))
        .clamp(compact ? 146.0 : 166.0, compact ? 188.0 : 210.0)
        .toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final viewport = NovelViewportMetrics.of(context);
    final compact = viewport.narrowWidth;
    final shortViewport = viewport.shortViewport;
    final shortWide = viewport.shortWide;
    final cardHeight = shortViewport ? 38.0 : (compact ? 42.0 : 44.0);
    final gap = shortViewport ? 5.0 : (compact ? 6.0 : 7.0);
    final rightPadding = shortViewport ? 6.0 : (compact ? 7.0 : 9.0);

    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = _choiceWidth(
          availableWidth: constraints.maxWidth,
          count: choices.length,
          compact: compact,
        );

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          clipBehavior: Clip.none,
          // 左侧 0：和下方输入框严格对齐。
          padding: EdgeInsets.only(right: rightPadding),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (final entry in choices.asMap().entries) ...<Widget>[
                if (entry.key > 0) SizedBox(width: gap),
                SizedBox(
                  width: cardWidth,
                  height: cardHeight,
                  child: ClipRRect(
                    borderRadius: BorderRadius.zero,
                    child: _AdaptiveBackdropBlur(
                      sigma: 12,
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => onSelected(entry.value),
                          borderRadius: BorderRadius.zero,
                          splashColor: Colors.white.withOpacity(.07),
                          highlightColor: Colors.white.withOpacity(.03),
                          child: Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: compact ? 9 : 11,
                            ),
                            decoration: BoxDecoration(
                              color: _ChoiceColors.card,
                              borderRadius: BorderRadius.zero,
                              border: Border.all(
                                color: shortWide
                                    ? Colors.white.withOpacity(.24)
                                    : _ChoiceColors.border,
                                width: shortWide ? .85 : .65,
                              ),
                            ),
                            child: Row(
                              children: <Widget>[
                                Container(
                                  width: compact ? 20 : 21,
                                  height: compact ? 20 : 21,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: _ChoiceColors.numberBg,
                                    borderRadius: BorderRadius.circular(2),
                                    border: Border.all(
                                      color: shortWide
                                          ? Colors.white.withOpacity(.34)
                                          : _ChoiceColors.numberBorder,
                                      width: shortWide ? .8 : .65,
                                    ),
                                  ),
                                  child: Text(
                                    '${entry.key + 1}',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(.72),
                                      fontSize: compact ? 10.5 : 11,
                                      height: 1,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                SizedBox(width: compact ? 6 : 7),
                                Opacity(
                                  opacity: .82,
                                  child: _buildChoiceIcon(
                                    entry.value,
                                    compact: compact,
                                  ),
                                ),
                                SizedBox(width: compact ? 6 : 7),
                                Expanded(
                                  child: Text(
                                    entry.value.text,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.left,
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(.80),
                                      fontSize: compact ? 12.2 : 12.8,
                                      height: 1.15,
                                      fontWeight: FontWeight.w500,
                                      letterSpacing: .02,
                                      shadows: const <Shadow>[
                                        Shadow(
                                          color: Color(0x88000000),
                                          blurRadius: 3,
                                          offset: Offset(0, 1),
                                        ),
                                      ],
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
              ],
            ],
          ),
        );
      },
    );
  }
}

class _NovelDialogFooter extends StatelessWidget {
  const _NovelDialogFooter({
    required this.controller,
    required this.choicesAvailable,
    required this.inputEnabled,
    required this.showComposer,
    required this.textController,
    required this.focusNode,
    required this.onSend,
    required this.onOpenInventory,
    required this.onOpenCharacters,
    required this.onOpenJourney,
    required this.onContinue,
  });

  final NovelGameController controller;
  final bool choicesAvailable;
  final bool inputEnabled;
  final bool showComposer;
  final TextEditingController textController;
  final FocusNode focusNode;
  final ValueChanged<String> onSend;
  final VoidCallback onOpenInventory;
  final VoidCallback onOpenCharacters;
  final VoidCallback onOpenJourney;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final viewport = NovelViewportMetrics.fromMediaQuery(
      media,
      desktopMode: controller.desktopMode,
    );
    final compact = viewport.compactContent;
    final shortViewport = viewport.shortViewport;
    final shortWide = viewport.shortWide;
    final wideDialogueLayout = viewport.useDesktopDialogue;
    final keyboardVisible = media.viewInsets.bottom > 0;

    // NovelDialogPanel 本身已经位于 NovelGamePage 的 SafeArea 内。
    // 这里不能再次叠加 viewPadding.bottom，否则 iPhone Home Indicator
    // 会被重复预留两次甚至三次，真机可用高度会明显少于电脑预览。
    const safeBottom = 0.0;

    // 核心逻辑：精准判断右侧导航栏是否显示
    final showBottomNav = controller.storyStarted && 
                          !controller.isCinematic && 
                          (controller.hasNext || controller.isGenerating) && 
                          !keyboardVisible;
    
    // 计算右侧需要避让的宽度（导航图标宽度 + 间距）
    // PC 输入区本身已经居中并限制宽度，不需要再为了最右侧 HUD 整体左移。
    final navOffsetRight = showBottomNav && !wideDialogueLayout
        ? (shortViewport ? 52.0 : (compact ? 56.0 : 64.0))
        : 0.0;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      // 底部永远贴底，通过 right 让出右侧导航栏的空间
      padding: EdgeInsets.only(
        bottom: safeBottom + (shortViewport ? 4.0 : 8.0),
        right: navOffsetRight, 
      ),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: wideDialogueLayout
                ? 920.0
                : (viewport.shortWide
                    ? math.min(720.0, media.size.width)
                    : media.size.width),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (showComposer) ...<Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                if (!choicesAvailable) ...<Widget>[
                  _GameContinueButton(onTap: onContinue),
                  const SizedBox(width: 9),
                ],
                Expanded(
                  child: NovelInputBar(
                    controller: textController,
                    focusNode: focusNode,
                    gameController: controller,
                    socketService: controller.socket,
                    enabled: inputEnabled,
                    luckyCardActive: controller.luckyCardActive,
                    luckyCardCount: controller.luckyCardCount,
                    onToggleLuckyCard: controller.toggleLuckyCard,
                    onSend: onSend,
                  ),
                ),
              ],
            ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

final ValueNotifier<int> _novelPrimaryTabIndex = ValueNotifier<int>(0);

/// 右侧悬浮一级导航：【无界渐变】沉浸式设计
/// 已由原先的底部横向改为右侧竖向排列，彻底释放底部文本与立绘空间。
class NovelBottomArchiveBar extends StatelessWidget {
  const NovelBottomArchiveBar({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    this.onWorld,
    this.desktopMode = false,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final VoidCallback? onWorld;
  final bool desktopMode;

  static const List<String> _labels = <String>[
    '剧情',
    '人物',
    '队伍',
    '背包',
    '经历',
    '地图',
  ];

  static const List<String> _iconAssets = <String>[
    'assets/images/novel/nav_story.png',
    'assets/images/novel/nav_character.png',
    'assets/images/novel/nav_character_bond.png',
    'assets/images/novel/nav_inventory.png',
    'assets/images/novel/nav_journey.png',
    'assets/images/novel/nav_world.png',
  ];

  static const List<IconData> _fallbackIcons = <IconData>[
    Icons.auto_stories_rounded,
    Icons.person_outline_rounded,
    Icons.groups_rounded,
    Icons.backpack_outlined,
    Icons.explore_outlined,
    Icons.public_outlined,
  ];

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final viewport = NovelViewportMetrics.fromMediaQuery(
      media,
      desktopMode: desktopMode,
    );
    final shortViewport = viewport.shortViewport;
    final ultraShortViewport = viewport.ultraShortViewport;
    // 导航的“紧凑”只描述 chrome 密度，不再把宽度等同于设备类型。
    final compact = viewport.compactChrome;
    final activeIndex = selectedIndex.clamp(0, _labels.length - 1).toInt();
    
    if (_novelPrimaryTabIndex.value != activeIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_novelPrimaryTabIndex.value != activeIndex) {
          _novelPrimaryTabIndex.value = activeIndex;
        }
      });
    }

    // 核心修改：使用 Align 固定在右下角
    return Align(
      alignment: Alignment.bottomRight,
      child: Padding(
        // 留出与屏幕右侧和底部的安全距离，避免阻挡文字或被手势误触
        padding: EdgeInsets.only(
          right: desktopMode && !shortViewport
              ? 20.0
              : (compact ? 8.0 : 16.0),
          bottom: desktopMode && !shortViewport
              ? 48.0
              : (ultraShortViewport ? 4.0 : (compact ? 8.0 : 40.0)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min, // 紧凑包裹
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            for (var i = 0; i < _labels.length; i++) ...[
              _MinimalSideNavAction(
                semanticLabel: _labels[i],
                iconAsset: _iconAssets[i],
                fallbackIcon: _fallbackIcons[i],
                selected: i == activeIndex,
                compact: compact,
                onTap: () {
                  if (_novelPrimaryTabIndex.value != i) {
                    _novelPrimaryTabIndex.value = i;
                  }
                  onSelected(i);
                }
              ),
              // 添加竖向排列时的图标间距
              if (i < _labels.length - 1)
                SizedBox(
                  height: desktopMode && !shortViewport
                      ? 20.0
                      : (ultraShortViewport ? 3.0 : (compact ? 6.0 : 18.0)),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MinimalSideNavAction extends StatelessWidget {
  const _MinimalSideNavAction({
    required this.semanticLabel,
    required this.iconAsset,
    this.fallbackIcon = Icons.circle_outlined,
    required this.selected,
    required this.compact,
    required this.onTap,
  });

  final String semanticLabel;
  final String iconAsset;
  final IconData fallbackIcon;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // 保留透明图片原色，仅通过整体透明度区分选中状态。
    final opacity = selected ? .88 : .62;
    final color = Colors.white.withOpacity(opacity);

    return Semantics(
      button: true,
      selected: selected,
      label: semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            AnimatedScale(
              scale: selected ? 1.12 : 1.0,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutBack,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 250),
                opacity: opacity,
                child: SizedBox(
                  width: compact ? 28 : 32,
                  height: compact ? 28 : 32,
                  child: iconAsset.isEmpty
                      ? Icon(
                          fallbackIcon,
                          size: compact ? 26 : 30,
                          color: Colors.white,
                        )
                      : Image.asset(
                          iconAsset,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.medium,
                          errorBuilder: (_, __, ___) => Icon(
                            fallbackIcon,
                            size: compact ? 26 : 30,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
            ),
            SizedBox(height: compact ? 4 : 6),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 250),
              style: TextStyle(
                color: color,
                fontFamily: 'WenJinMinchoP0',
                fontSize: compact ? 10.5 : 11.2,
                height: 1,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                letterSpacing: 0.35,
              ),
              child: Text(semanticLabel, maxLines: 1),
            ),
          ],
        ),
      ),
    );
  }
}

class _CutoutVoiceWavePainter extends CustomPainter {
  const _CutoutVoiceWavePainter({required this.speaking});

  final bool speaking;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.saveLayer(rect, Paint());

    final center = rect.center;
    final radius = math.min(size.width, size.height) / 2;
    canvas.drawCircle(center, radius, Paint()..color = Colors.white);

    final clearPaint = Paint()
      ..blendMode = BlendMode.clear
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = speaking ? 2.55 : 2.35;

    final boost = speaking ? 1.08 : 1.0;
    final heights = <double>[.18, .34, .50, .34, .18];
    final spacing = size.width * .105;
    final startX = center.dx - spacing * 2;

    for (var i = 0; i < heights.length; i++) {
      final half = size.height * heights[i] * .5 * boost;
      final x = startX + spacing * i;
      canvas.drawLine(
        Offset(x, center.dy - half),
        Offset(x, center.dy + half),
        clearPaint,
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CutoutVoiceWavePainter oldDelegate) =>
      oldDelegate.speaking != speaking;
}

class _StoryImageAction extends StatelessWidget {
  const _StoryImageAction({
    required this.asset,
    required this.label,
    required this.compact,
    required this.onTap,
  });

  final String asset;
  final String label;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final imageSize = compact ? 28.0 : 31.0;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(5),
      splashColor: Colors.white.withOpacity(.05),
      highlightColor: Colors.white.withOpacity(.025),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SizedBox(
                width: imageSize,
                height: imageSize,
                child: NovelArtwork(
                  assetCandidates: <String>[asset],
                  fit: BoxFit.contain,
                  fallbackText: label,
                )),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: NovelPalette.text.withOpacity(.94),
                fontSize: 9.8,
                fontWeight: FontWeight.w700,
                letterSpacing: .20,
                shadows: const <Shadow>[
                  Shadow(
                    color: Color(0xD9000000),
                    blurRadius: 6,
                    offset: Offset(0, 1),
                  ),
                  Shadow(
                    color: Color(0x99000000),
                    blurRadius: 12,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GameContinueButton extends StatelessWidget {
  const _GameContinueButton({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final shortViewport = NovelViewportMetrics.of(context).shortViewport;
    return Tooltip(
      message: '继续剧情',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          splashColor: Colors.white.withOpacity(.05),
          highlightColor: Colors.transparent,
          child: Opacity(
            opacity: onTap == null ? .25 : 1,
            child: SizedBox(
                width: shortViewport ? 38 : 42,
                height: shortViewport ? 40 : 44,
                child: Center(
                  child: _GameContinueGlyph(size: shortViewport ? 28 : 32),
                ),
              ),
          ),
        ),
      ),
    );
  }
}

class _StoryProgressLocator extends StatelessWidget {
  const _StoryProgressLocator({
    required this.currentIndex,
    required this.totalCount,
    required this.isBrowsingHistory,
  });

  final int currentIndex;
  final int totalCount;
  final bool isBrowsingHistory;

  @override
  Widget build(BuildContext context) {
    if (!isBrowsingHistory || totalCount <= 1) {
      return const SizedBox.shrink();
    }

    // 当历史记录极其多时，优雅降级为文字显示，避免圆点溢出屏幕
    final useDots = totalCount <= 40;

    return IgnorePointer(
      // 核心修复：将进度条对齐到父组件（对话框）的【顶部】，而不是底部！
      // 这样它会永远贴着对话面板的最上沿，无论下方的正文长到几行，都绝对不会重叠。
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.only(top: 14.0), // 距离对话面板顶边预留出呼吸空间
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 250),
            opacity: isBrowsingHistory ? 1.0 : 0.0,
            curve: Curves.easeOutCubic,
            child: useDots
                ? Row(
                    mainAxisSize: MainAxisSize.min, // 紧凑居中排列，不再霸占整行
                    children: List<Widget>.generate(totalCount, (index) {
                      final active = index == currentIndex;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 260),
                        curve: Curves.easeOutBack,
                        width: active ? 14.0 : 4.0,
                        height: 4.0,
                        margin: const EdgeInsets.symmetric(horizontal: 2.5),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(active ? 0.95 : 0.25),
                          borderRadius: BorderRadius.circular(2.0),
                        ),
                      );
                    }),
                  )
                : Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${currentIndex + 1} / $totalCount',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.65),
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _LuxurySwipeHint extends StatefulWidget {
  const _LuxurySwipeHint();

  @override
  State<_LuxurySwipeHint> createState() => _LuxurySwipeHintState();
}

class _LuxurySwipeHintState extends State<_LuxurySwipeHint>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _shift;
  late final Animation<double> _glow;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _shift = Tween<double>(begin: -5, end: 5).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    _glow = Tween<double>(begin: .35, end: .95).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Transform.translate(
                offset: Offset(-_shift.value, 0),
                child: Icon(
                  Icons.chevron_left_rounded,
                  size: 18,
                  color: Colors.white.withOpacity(_glow.value),
                ),
              ),
              const SizedBox(width: 3),
              Text(
                '左右滑动回看剧情',
                style: TextStyle(
                  color: Colors.white.withOpacity(_glow.value),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                  shadows: const <Shadow>[
                    Shadow(color: Color(0xCC000000), blurRadius: 6),
                  ],
                ),
              ),
              const SizedBox(width: 3),
              Transform.translate(
                offset: Offset(_shift.value, 0),
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: Colors.white.withOpacity(_glow.value),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class NovelCinematicControls extends StatefulWidget {
  const NovelCinematicControls({
    super.key,
    required this.controller,
    required this.text,
    required this.speakerName,
    required this.isGenerating,
    required this.isFirst,
    required this.isLast,
    required this.fontFamily,
    required this.fontSize,
    required this.onRevert,
    required this.onPrevious,
    required this.onNext,
    required this.onContinue,
  });

  final NovelGameController controller;
  final String text;
  final String speakerName;
  final bool isGenerating;
  final bool isFirst;
  final bool isLast;
  final String? fontFamily;
  final double fontSize;
  final VoidCallback onRevert;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onContinue;

  @override
  State<NovelCinematicControls> createState() => _NovelCinematicControlsState();
}

class _NovelCinematicControlsState extends State<NovelCinematicControls> {
  Timer? _typingTimer;
  int _visibleLength = 0;
  String _lastRevealKey = '';
  String _skippedRevealKey = '';
  String _lastSafeText = '';
  List<int> _lastSafeRunes = const <int>[];
  bool _revealing = false;
  bool _typingSoundForReveal = false;
  final Set<String> _typingSoundVisited = <String>{};
  bool _animationsDisabled = false;
  int _lastTextSpeedCps = -1;

  NovelGameController get controller => widget.controller;

  String get _currentAssistantMessageKey {
    final message = controller.lastAssistantMessage;
    final timestamp = message?.timestamp ?? 0;
    if (timestamp > 0) return 'timestamp:$timestamp';
    final id = message?.id.trim() ?? '';
    if (id.isNotEmpty) return id;
    return 'assistant-message';
  }

  String get _currentRevealKey =>
      '$_currentAssistantMessageKey|${controller.currentSentenceIndex}|${widget.speakerName}';

  @override
  void initState() {
    super.initState();
    _lastTextSpeedCps = widget.controller.settings.textSpeedCps;
    widget.controller.settings.addListener(_handleRevealSettingsChanged);
    _syncReveal(force: true);
  }

  @override
  void didUpdateWidget(covariant NovelCinematicControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller.settings != widget.controller.settings) {
      oldWidget.controller.settings.removeListener(_handleRevealSettingsChanged);
      _lastTextSpeedCps = widget.controller.settings.textSpeedCps;
      widget.controller.settings.addListener(_handleRevealSettingsChanged);
    }
    _syncReveal();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = MediaQuery.of(context).disableAnimations;
    if (next != _animationsDisabled) {
      _animationsDisabled = next;
      _syncReveal(force: true);
    }
  }

  bool get _revealInstantly =>
      _animationsDisabled || controller.settings.textSpeedCps <= 0;

  void _handleRevealSettingsChanged() {
    if (!mounted) return;
    final nextSpeed = controller.settings.textSpeedCps;
    if (nextSpeed == _lastTextSpeedCps) return;
    _lastTextSpeedCps = nextSpeed;
    if (_revealInstantly) {
      _typingSoundForReveal = false;
      _finishReveal(revealAll: true);
      unawaited(controller.bgm.stopTypingSound());
      return;
    }
    if (_revealing) _scheduleReveal();
  }

  void _syncReveal({bool force = false}) {
    final safeText = _sanitizeNovelStreamingText(widget.text);
    final revealKey = _currentRevealKey;

    if (force || revealKey != _lastRevealKey) {
      _typingTimer?.cancel();
      _typingTimer = null;
      _lastRevealKey = revealKey;
      _lastSafeText = safeText;
      _lastSafeRunes = safeText.runes.toList(growable: false);
      _visibleLength = 0;

      if (_revealInstantly || _skippedRevealKey == revealKey) {
        _visibleLength = _lastSafeRunes.length;
        _revealing = false;
        _typingSoundForReveal = false;
        if (!force && mounted) setState(() {});
        return;
      }

      _typingSoundForReveal = _typingSoundVisited.add(revealKey);

      _revealing = safeText.isNotEmpty;
      _scheduleReveal();
      if (!force && mounted) setState(() {});
      return;
    }

    if (safeText != _lastSafeText) {
      final previousLength = _lastSafeRunes.length;
      final nextRunes = safeText.runes.toList(growable: false);
      final nextLength = nextRunes.length;
      _lastSafeText = safeText;
      _lastSafeRunes = nextRunes;

      if (_revealInstantly || _skippedRevealKey == revealKey) {
        _typingTimer?.cancel();
        _typingTimer = null;
        _visibleLength = nextLength;
        _typingSoundForReveal = false;
        if (_revealing && mounted) setState(() => _revealing = false);
        return;
      }

      if (_visibleLength > nextLength) {
        _visibleLength = nextLength;
        if (mounted) setState(() {});
      }

      if (nextLength > previousLength &&
          _visibleLength < nextLength &&
          _typingTimer == null) {
        _revealing = true;
        _scheduleReveal();
      }
    }
  }

  void _scheduleReveal({String afterCharacter = ''}) {
    _typingTimer?.cancel();
    final runes = _lastSafeRunes;
    final skippedByUser = _skippedRevealKey == _lastRevealKey;
    if (_revealInstantly || skippedByUser) {
      _visibleLength = runes.length;
      _typingTimer = null;
      _revealing = false;
      _typingSoundForReveal = false;
      if (mounted) setState(() {});
      if (skippedByUser || !controller.isGenerating) {
        unawaited(controller.bgm.stopTypingSound());
      }
      return;
    }
    if (!mounted || _visibleLength >= runes.length) {
      _typingTimer = null;
      _revealing = false;
      if (!controller.isGenerating) {
        unawaited(controller.bgm.stopTypingSound());
      }
      return;
    }

    var delay =
        _novelRevealDelay(controller.settings.textSpeedCps, afterCharacter);
    if (controller.isGenerating &&
        _visibleLength == 0 &&
        afterCharacter.isEmpty &&
        delay < const Duration(milliseconds: 72)) {
      delay = const Duration(milliseconds: 72);
    }

    _typingTimer = Timer(delay, () {
      if (!mounted) return;
      final latestRunes = _lastSafeRunes;
      if (latestRunes.isEmpty || _visibleLength >= latestRunes.length) {
        _finishReveal();
        return;
      }

      final current = String.fromCharCode(
        latestRunes[_visibleLength.clamp(0, latestRunes.length - 1)],
      );
      _visibleLength = (_visibleLength + 1).clamp(0, latestRunes.length);

      if (controller.settings.typingSoundEnabled &&
          _typingSoundForReveal &&
          _shouldPlayNovelTypingTick(
            visibleLength: _visibleLength,
            currentCharacter: current,
          )) {
        controller.bgm.playTypingTick();
      }

      if (mounted) setState(() {});
      if (_visibleLength >= latestRunes.length) {
        _finishReveal();
      } else {
        _scheduleReveal(afterCharacter: current);
      }
    });
  }

  void _finishReveal({bool revealAll = false}) {
    _typingTimer?.cancel();
    _typingTimer = null;
    if (revealAll) {
      _visibleLength = _lastSafeRunes.length;
    }
    _revealing = false;
    if (mounted) setState(() {});
    if (!controller.isGenerating) {
      unawaited(controller.bgm.stopTypingSound());
    }
  }

  void _handleScreenTap() {
    if (_revealing || widget.isGenerating) {
      _skippedRevealKey = _lastRevealKey;
      _typingSoundForReveal = false;
      _finishReveal(revealAll: true);
      unawaited(controller.bgm.stopTypingSound());
      return;
    }
    if (!widget.isGenerating || !widget.isLast) {
      unawaited(_navigateAfterTypingStops(widget.onContinue));
    }
  }

  void _handlePrevious() {
    unawaited(_navigateAfterTypingStops(widget.onPrevious));
  }

  void _handleNext() {
    unawaited(_navigateAfterTypingStops(widget.onNext));
  }

  Future<void> _navigateAfterTypingStops(VoidCallback navigate) async {
    await controller.bgm.stopTypingSound();
    if (!mounted) return;
    navigate();
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    unawaited(controller.bgm.stopTypingSound());
    widget.controller.settings.removeListener(_handleRevealSettingsChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 1. 获取屏幕宽度，判断是否为小屏设备
    final screenWidth = MediaQuery.sizeOf(context).width;
    final compact = screenWidth < 480;
    
    // 电影模式不显示右侧剧情按钮，正文使用完全对称的左右边距。
    final basePadding = compact ? 30.0 : 64.0;

    final safeText = _lastSafeText;
    final safeLength = _visibleLength.clamp(0, _lastSafeRunes.length);
    final displayText = safeLength >= _lastSafeRunes.length
        ? safeText
        : String.fromCharCodes(_lastSafeRunes.take(safeLength));
    final narration = widget.speakerName.trim().isEmpty;
    
    return GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _handleScreenTap,
        onHorizontalDragEnd: (details) {
          final velocity = details.primaryVelocity ?? 0;
          if (velocity.abs() < 260) return;
          if (velocity < 0 && !widget.isLast) {
            _handleNext();
          } else if (velocity > 0 && !widget.isFirst) {
            _handlePrevious();
          }
        },
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Align(
                alignment: narration ? const Alignment(0, -.02) : const Alignment(0, .36),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: basePadding),
                  child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 880),
                      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: narration ? CrossAxisAlignment.center : CrossAxisAlignment.start, children: <Widget>[
                        if (!narration) ...<Widget>[
                          Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(.32),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(color: Colors.white.withOpacity(.18)),
                              ),
                              child: Text(
                                '「 ${widget.speakerName} 」',
                                style: const TextStyle(
                                  color: Color(0xFFF9FAFC),
                                  fontFamily: 'WenJinMinchoP0',
                                  fontSize: 13.0,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: .8,
                                  shadows: <Shadow>[
                                    Shadow(
                                      color: Color(0xE6000000),
                                      blurRadius: 7,
                                      offset: Offset(0, 2),
                                    ),
                                  ],
                                ),
                              )),
                          const SizedBox(height: 14),
                        ],
                        Text(displayText.isEmpty && !widget.isGenerating ? '等待故事继续…' : displayText,
                            textAlign: narration ? TextAlign.center : TextAlign.left,
                            style: TextStyle(color: NovelPalette.text, fontFamily: widget.fontFamily, fontSize: widget.fontSize + (narration ? 3 : 2), height: narration ? 1.95 : 1.8, fontWeight: narration ? FontWeight.w500 : FontWeight.w400, letterSpacing: narration ? .7 : .25, shadows: const <Shadow>[Shadow(color: Color(0x24000000), blurRadius: 2, offset: Offset(0, 1))])),
                      ])),
                )),
            Align(
                alignment: Alignment.bottomCenter,
                child: IgnorePointer(
                    child: Container(
                  height: 210,
                  decoration: BoxDecoration(
                      gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: <Color>[Colors.transparent, Colors.black.withOpacity(.74), Colors.black.withOpacity(.92)])),
                ))),
            Align(
                alignment: Alignment.bottomCenter,
                child: SafeArea(
                    minimum: const EdgeInsets.fromLTRB(18, 0, 18, 20),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: Row(
                        children: <Widget>[
                          const SizedBox(width: 38),
                          const Spacer(),
                          _GameContinueButton(
                            onTap: _revealing ||
                                    !widget.isGenerating ||
                                    !widget.isLast
                                ? _handleScreenTap
                                : null,
                          ),
                          const Spacer(),
                          if (widget.isFirst && widget.isLast)
                            const SizedBox(width: 132)
                          else
                            const IgnorePointer(child: _LuxurySwipeHint()),
                        ],
                      ),
                    ))),
          ],
        ));
  }
}
