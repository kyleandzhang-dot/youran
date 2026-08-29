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
    if (oldWidget.scope.visible != widget.scope.visible ||
        oldWidget.scope.loading != widget.scope.loading) {
      _syncPulse();
    }
  }

  void _syncPulse() {
    // 入口只要可用就让绿点持续轻呼吸，不再依赖后端 needs_attention。
    // needs_attention 仍保留在 Scope 中供后续状态语义使用，但不决定提示动画。
    if (widget.scope.visible && !widget.scope.loading) {
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
    final pulseActive = scope.visible && !scope.loading;
    final displayLabel =
        scope.label.trim() == '探索周围' ? '探索附近' : scope.label;

    return Semantics(
      button: true,
      label: displayLabel,
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
                SizedBox(
                  width: 19,
                  height: 18,
                  child: scope.loading
                      ? Center(
                          child: SizedBox(
                            width: 11,
                            height: 11,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.25,
                              color: Colors.white.withOpacity(.58),
                            ),
                          ),
                        )
                      : AnimatedBuilder(
                          animation: _pulse,
                          builder: (context, _) {
                            final value = pulseActive ? _pulse.value : 0.0;
                            return Stack(
                              clipBehavior: Clip.none,
                              children: <Widget>[
                                Center(
                                  child: Icon(
                                    Icons.radar_rounded,
                                    size: 15.5,
                                    color: Colors.white.withOpacity(.76),
                                  ),
                                ),
                                Positioned(
                                  right: 0,
                                  top: 0,
                                  child: Transform.scale(
                                    scale: .86 + value * .22,
                                    child: Container(
                                      width: 5,
                                      height: 5,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF6FD35F)
                                            .withOpacity(.78 + value * .22),
                                        shape: BoxShape.circle,
                                        boxShadow: <BoxShadow>[
                                          BoxShadow(
                                            color: const Color(0xFF6FD35F)
                                                .withOpacity(.24 + value * .52),
                                            blurRadius: 3.5 + value * 5.5,
                                            spreadRadius: .15 + value * .95,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                ),
                const SizedBox(width: 5),
                Text(
                  displayLabel,
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
    required this.choices,
    required this.onSelected,
  });

  final List<NovelChoice> choices;
  final ValueChanged<NovelChoice> onSelected;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width <= 600;
    final surroundingsAction = NovelChoiceDockActionScope.maybeOf(context);

    // 参考图：标题浮在场景上；卡片与底部自由输入框同宽。
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

/// 选择卡片：透明玻璃感，不使用暖棕色底。
class _ChoiceColors {
  static const Color line = Color(0xE6F3EEE9);
  static const Color cardTop = Color(0x20FFFFFF);
  static const Color cardMiddle = Color(0x15FFFFFF);
  static const Color cardBottom = Color(0x0FFFFFFF);

  // 整个选项框只用一圈较浅的白色描边。
  // 对比度明显低于自由输入框，避免抢正文。
  static const Color border = Color(0x33FFFFFF);

  // 编号保持轻透明玻璃底；边框只比主外框略清晰。
  static const Color numberBg = Color(0x14FFFFFF);
  static const Color numberBorder = Color(0x66FFFFFF);
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
              borderRadius: BorderRadius.circular(3),
              child: _AdaptiveBackdropBlur(
                sigma: 18,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => onSelected(choice),
                    borderRadius: BorderRadius.circular(3),
                    splashColor: Colors.white.withOpacity(.06),
                    highlightColor: Colors.white.withOpacity(.025),
                    child: Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(minHeight: 48),
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(
                          color: _ChoiceColors.border,
                          width: .55,
                        ),
                        gradient: const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: <Color>[
                            _ChoiceColors.cardTop,
                            _ChoiceColors.cardMiddle,
                            _ChoiceColors.cardBottom,
                          ],
                        ),
                        boxShadow: const <BoxShadow>[
                          BoxShadow(
                            color: Color(0x26000000),
                            blurRadius: 14,
                            offset: Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: <Widget>[
                          // 左侧只保留“编号 + 类型 icon”。
                          // icon 直接替代旧的“行动”文字标签，并且三种选项统一显示。
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

                          // 左侧给“编号 + 大 icon”预留空间；右侧只保留正常安全边距。
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
    // 输入栏已经由外层 Positioned 抬到键盘上沿；键盘出现时不再额外叠加
    // home indicator 的安全区高度，避免输入框被抬得过头。
    final safeBottom = keyboardVisible
        ? 0.0
        : MediaQuery.viewPaddingOf(context).bottom;

    return AnimatedSize(
      duration: const Duration(milliseconds: 170),
      curve: Curves.easeOutCubic,
      alignment: Alignment.bottomCenter,
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
            SizedBox(height: compact ? 4 : 6),
          ],
          // 一级导航已经移到右侧，这里只避开系统底部安全区。
          SizedBox(height: safeBottom),
        ],
      ),
    );
  }
}

// 主页面当前一级 Tab。0=剧情；积分星星只允许在剧情 Tab 出现。
final ValueNotifier<int> _novelPrimaryTabIndex = ValueNotifier<int>(0);

/// 右侧一级导航：放在积分下方，保持游戏 HUD 感。
/// 无底板、无卡片、无发光，只使用线性 icon + 小文字。
class NovelSideArchiveBar extends StatelessWidget {
  const NovelSideArchiveBar({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  static const List<String> _labels = <String>[
    '剧情',
    '角色',
    '背包',
    '经历',
  ];

  // 右侧只保留长期档案/页面入口；当前地点的“周围探索”已移到场景 HUD。
  static const List<String> _iconAssets = <String>[
    'assets/images/novel/nav_story.png',
    'assets/images/novel/nav_character.png',
    'assets/images/novel/nav_inventory.png',
    'assets/images/novel/nav_journey.png',
  ];

  static const List<IconData> _fallbackIcons = <IconData>[
    Icons.circle_outlined,
    Icons.circle_outlined,
    Icons.circle_outlined,
    Icons.circle_outlined,
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

    // 剧情页是深色场景，档案页是浅色背景；只切换前景色，不增加任何底板。
    final lightArchive = activeIndex != 0;

    return SizedBox(
      width: compact ? 62 : 68,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (var i = 0; i < _labels.length; i++) ...<Widget>[
            if (i > 0)
              SizedBox(height: compact ? 5 : 7),
            _MinimalSideNavAction(
              semanticLabel: _labels[i],
              iconAsset: _iconAssets[i],
              fallbackIcon: _fallbackIcons[i],
              selected: i == activeIndex,
              lightTheme: lightArchive,
              compact: compact,
              onTap: () {
                if (_novelPrimaryTabIndex.value != i) {
                  _novelPrimaryTabIndex.value = i;
                }
                onSelected(i);
              },
            ),
          ],
        ],
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
    required this.lightTheme,
    required this.compact,
    required this.onTap,
  });

  final String semanticLabel;
  final String iconAsset;
  final IconData fallbackIcon;
  final bool selected;
  final bool lightTheme;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // nav PNG 始终保持素材自身原色；四个入口不再提供任何视觉选中态。
    // selected 只保留给 Semantics，视觉上所有入口完全一致。
    final color = lightTheme
        ? const Color(0xE61D231E)
        : const Color(0xF0F5F7F4);

    return Semantics(
      button: true,
      selected: selected,
      label: semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: compact ? 60 : 66,
          height: compact ? 70 : 76,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              SizedBox(
                width: compact ? 44 : 48,
                height: compact ? 44 : 48,
                child: iconAsset.isEmpty
                    ? Icon(
                        fallbackIcon,
                        size: compact ? 36 : 40,
                        color: color,
                      )
                    : Image.asset(
                        iconAsset,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.medium,
                        // nav_*.png 保持素材自身原色；选中状态绝不再给 icon 染色。
                        errorBuilder: (_, __, ___) => Icon(
                          fallbackIcon,
                          size: compact ? 40 : 44,
                          color: color,
                        ),
                      ),
              ),
              SizedBox(height: compact ? 3 : 4),
              Text(
                semanticLabel,
                maxLines: 1,
                style: TextStyle(
                  color: color,
                  fontFamily: 'WenJinMinchoP0',
                  fontSize: compact ? 10.8 : 11.4,
                  height: 1,
                  fontWeight: FontWeight.w600,
                  letterSpacing: .20,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 自由输入框语音按钮：纯白圆形承载层，中间用透明镂空绘制简洁声波。
/// 不再使用旧版向右扩散的弧线，改成 5 根对称圆角波形柱，视觉更干净。
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

    // 五段对称声波：短 / 中 / 长 / 中 / 短。
    // speaking 时只轻微放大波幅，不改变整体图形语言。
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
                // 右侧入口必须始终可读：图标美术不动，只提高文字识别度。
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
    // 只有在回溯历史时才显示，保证最新剧情的极致干净。
    if (!isBrowsingHistory || totalCount <= 1) {
      return const SizedBox.shrink();
    }

    // 段与段之间的间距：格子越多，间距越窄，避免拥挤。
    final gap = totalCount > 24 ? 1.5 : totalCount > 12 ? 2.0 : 3.0;

    // 进度不要铺满整条底部：收成一条较短的“剧情刻度”，视觉会轻很多。
    final locatorWidth = (MediaQuery.sizeOf(context).width * .58)
        .clamp(150.0, 320.0)
        .toDouble();

    return IgnorePointer(
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 250),
        opacity: isBrowsingHistory ? 1.0 : 0.0,
        curve: Curves.easeOutCubic,
        child: Center(
          child: SizedBox(
            width: locatorWidth,
            child: Row(
              children: List<Widget>.generate(totalCount, (index) {
                final active = index == currentIndex;
                return Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    height: active ? 2.4 : 1.6,
                    margin: EdgeInsets.symmetric(horizontal: gap / 2),
                    decoration: BoxDecoration(
                      // 剧情回溯底部进度仅改为白色，其它 UI 不动。
                      color: Colors.white.withOpacity(active ? .88 : .18),
                      borderRadius: BorderRadius.circular(2),
                      boxShadow: active
                          ? <BoxShadow>[
                              BoxShadow(
                                color: Colors.white.withOpacity(.18),
                                blurRadius: 4,
                              ),
                            ]
                          : null,
                    ),
                  ),
                );
              }),
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
    // 左右来回轻推 + 明暗呼吸，靠动画把注意力吸引过来，
    // 静态小字太容易被忽略了。
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
  // 与普通剧情一致：用户主动跳过当前句后，后续流式补字保持全文直出且静音。
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

  /// 电影模式与普通剧情使用同一套原则：
  /// - 新句从 0 开始逐字显示并播放打字声；
  /// - SSE 只是补长当前句时，不把已经显示的文字清零；
  /// - 回退后再次看到已经展示过的句子，不重复播放音效。
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
                  padding: EdgeInsets.symmetric(horizontal: MediaQuery.sizeOf(context).width < 480 ? 30 : 64),
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

