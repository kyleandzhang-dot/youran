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

class _NovelChoiceDockSurroundingsAction extends StatefulWidget {
  const _NovelChoiceDockSurroundingsAction({required this.scope});

  final NovelChoiceDockActionScope scope;

  @override
  State<_NovelChoiceDockSurroundingsAction> createState() =>
      _NovelChoiceDockSurroundingsActionState();
}

class _NovelChoiceDockSurroundingsActionState
    extends State<_NovelChoiceDockSurroundingsAction>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1650),
      lowerBound: 0,
      upperBound: 1,
    );
    _syncPulse();
  }

  @override
  void didUpdateWidget(covariant _NovelChoiceDockSurroundingsAction oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scope.attention != widget.scope.attention ||
        oldWidget.scope.loading != widget.scope.loading) {
      _syncPulse();
    }
  }

  void _syncPulse() {
    if (widget.scope.attention && !widget.scope.loading) {
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
    } else {
      _pulse
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = widget.scope;

    return Semantics(
      button: true,
      label: scope.label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: scope.loading ? null : scope.onTap,
          splashColor: Colors.white.withOpacity(.05),
          highlightColor: Colors.white.withOpacity(.025),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 3, 1, 3),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (scope.loading)
                  SizedBox(
                    width: 9,
                    height: 9,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.2,
                      color: Colors.white.withOpacity(.52),
                    ),
                  )
                else
                  AnimatedBuilder(
                    animation: _pulse,
                    builder: (context, _) {
                      final value = scope.attention ? _pulse.value : 0.0;
                      return Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: const Color(0xFF6FD35F).withOpacity(
                            scope.attention ? .72 + value * .28 : .58,
                          ),
                          shape: BoxShape.circle,
                          boxShadow: scope.attention
                              ? <BoxShadow>[
                                  BoxShadow(
                                    color: const Color(0xFF6FD35F)
                                        .withOpacity(.14 + value * .28),
                                    blurRadius: 2 + value * 4,
                                    spreadRadius: value * .65,
                                  ),
                                ]
                              : const <BoxShadow>[],
                        ),
                      );
                    },
                  ),
                const SizedBox(width: 6),
                Text(
                  scope.label,
                  style: TextStyle(
                    color: const Color(0xFFF7F2EA).withOpacity(.72),
                    fontSize: 11.5,
                    height: 1,
                    fontWeight: FontWeight.w600,
                    letterSpacing: .28,
                  ),
                ),
                const SizedBox(width: 1),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 14,
                  color: Colors.white.withOpacity(.28),
                ),
              ],
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
    final compact = MediaQuery.sizeOf(context).width <= 600;
    final surroundingsAction = NovelChoiceDockActionScope.maybeOf(context);

    // 移除了多余的 safeBottom 计算，避免与底层 DialogPanel 重复叠加导致留空过大
    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
                    const Text(
                      '请做出你的选择',
                      style: TextStyle(
                        color: Color(0xFFF7F2EA),
                        fontSize: 16.5,
                        height: 1.15,
                        fontWeight: FontWeight.w700,
                        letterSpacing: .45,
                        shadows: <Shadow>[
                          Shadow(
                            color: Color(0xCC000000),
                            blurRadius: 8,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                    if (surroundingsAction?.visible == true) ...<Widget>[
                      const Spacer(),
                      _NovelChoiceDockSurroundingsAction(
                        scope: surroundingsAction!,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Transform.rotate(
                      angle: .7853981633974483,
                      child: Container(
                        width: 5,
                        height: 5,
                        color: _ChoiceColors.line.withOpacity(.58),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      width: compact ? 108 : 138,
                      height: 1,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: <Color>[
                            _ChoiceColors.line.withOpacity(.30),
                            _ChoiceColors.line.withOpacity(0),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(height: compact ? 7 : 8),
          _InlineNovelChoices(
            choices: choices,
            onSelected: onSelected,
            onCustomInput: () {},
            onContinue: () {},
          ),
        ],
      ),
    );
  }
}

class _ChoiceColors {
  static const Color line = Color(0xE6F3EEE9);
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
    final size = compact ? 30.0 : 32.0;
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
          size: size - 1,
          color: Colors.white.withOpacity(.68),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width <= 600;

    return Column(
      children: <Widget>[
        ...choices.asMap().entries.map((entry) {
          final choice = entry.value;
          final isLast = entry.key == choices.length - 1;

          return Padding(
            padding: EdgeInsets.only(
              bottom: isLast ? 0 : (compact ? 5 : 6),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.zero,
              child: _AdaptiveBackdropBlur(
                sigma: 15,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => onSelected(choice),
                    borderRadius: BorderRadius.zero,
                    splashColor: Colors.white.withOpacity(.075),
                    highlightColor: Colors.white.withOpacity(.035),
                    child: Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(minHeight: 48),
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      decoration: BoxDecoration(
                        color: _ChoiceColors.card,
                        borderRadius: BorderRadius.zero,
                        border: Border.all(
                          color: _ChoiceColors.border,
                          width: .65,
                        ),
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: <Widget>[
                          Positioned(
                            left: compact ? 10 : 12,
                            top: 0,
                            bottom: 0,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Container(
                                  width: 23,
                                  height: 23,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: _ChoiceColors.numberBg,
                                    borderRadius: BorderRadius.circular(2),
                                    border: Border.all(
                                      color: _ChoiceColors.numberBorder,
                                      width: .65,
                                    ),
                                  ),
                                  child: Text(
                                    '${entry.key + 1}',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(.76),
                                      fontSize: 11.5,
                                      height: 1,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                SizedBox(width: compact ? 8 : 9),
                                Opacity(
                                  opacity: .90,
                                  child: _buildChoiceIcon(
                                    choice,
                                    compact: compact,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: EdgeInsets.only(
                              left: compact ? 88 : 96,
                              right: compact ? 18 : 22,
                            ),
                            child: Center(
                              child: Text(
                                choice.text,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(.80),
                                  fontSize: compact ? 13.5 : 14,
                                  height: 1.25,
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: .08,
                                  shadows: const <Shadow>[
                                    Shadow(
                                      color: Color(0x99000000),
                                      blurRadius: 4,
                                      offset: Offset(0, 1),
                                    ),
                                  ],
                                ),
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
          );
        }),
      ],
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
    final compact = MediaQuery.sizeOf(context).width <= 600;
    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
    final safeBottom = keyboardVisible
        ? 0.0
        : MediaQuery.viewPaddingOf(context).bottom;

    // 核心逻辑：精准判断右侧导航栏是否显示
    final showBottomNav = controller.storyStarted && 
                          !controller.isCinematic && 
                          (controller.hasNext || controller.isGenerating) && 
                          !keyboardVisible;
    
    // 计算右侧需要避让的宽度（导航图标宽度 + 间距）
    final navOffsetRight = showBottomNav ? (compact ? 56.0 : 64.0) : 0.0;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      // 底部永远贴底，通过 right 让出右侧导航栏的空间
      padding: EdgeInsets.only(
        bottom: safeBottom + 8.0, 
        right: navOffsetRight, 
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
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final VoidCallback? onWorld;

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
    final compact = MediaQuery.sizeOf(context).width <= 600;
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
          right: compact ? 12.0 : 16.0,
          bottom: compact ? 40.0 : 56.0, // 距离底部稍微高一点，避开输入框
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
                SizedBox(height: compact ? 18.0 : 22.0), 
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
            child: const SizedBox(width: 42, height: 44, child: Center(child: _GameContinueGlyph(size: 32))),
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
