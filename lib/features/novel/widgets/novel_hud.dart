part of '../novel_widgets.dart';

// Novel Widgets · HUD / 导航
// 对外入口：NovelTopHud / NovelGoalHud / NovelLocationHud / NovelActionRail / NovelArchiveRail / NovelScoreChip / NovelTaskBadge / NovelHudEventOverlay
// 内部实现：顶部按钮、状态头像、健康条、侧栏按钮与 HUD 动画。

class NovelTopHud extends StatelessWidget {
  const NovelTopHud({
    super.key,
    required this.controller,
    required this.onMenu,
    required this.onOpenProfile,
    required this.onOpenStore,
    required this.onOpenSettings,
  });

  final NovelGameController controller;
  final VoidCallback onMenu;
  final VoidCallback onOpenProfile;
  final VoidCallback onOpenStore;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final generating = controller.isGenerating;
    final viewport = NovelViewportMetrics.of(
      context,
      desktopMode: controller.desktopMode,
    );
    final compact = viewport.compactChrome;
    final shortWide = viewport.shortWide;
    final avatarSize = shortWide ? 32.0 : (compact ? 35.0 : 38.0);
    final buttonDimension = shortWide ? 34.0 : (compact ? 36.0 : 38.0);

    return AnimatedOpacity(
      opacity: generating ? .42 : 1,
      duration: const Duration(milliseconds: 420),
      child: SizedBox(
        height: viewport.topHudHeight,
        child: Row(
          children: <Widget>[
            Expanded(
              child: Row(
                children: <Widget>[
                  _TopIconButton(
                    tooltip: '菜单',
                    icon: Icons.menu_rounded,
                    assetPath: 'assets/images/icons/menu.png',
                    onTap: onMenu,
                    size: shortWide ? 19 : 21,
                    dimension: buttonDimension,
                  ),
                  SizedBox(width: shortWide ? 1 : 4),
                  Flexible(
                    child: InkWell(
                      onTap: onOpenProfile,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: shortWide ? 1 : 2,
                          vertical: 4,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            _ConditionAvatar(
                              gender: controller.protagonist?.gender ?? '',
                              size: avatarSize,
                            ),
                            SizedBox(width: shortWide ? 6 : 8),
                            Flexible(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    controller.protagonistName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: NovelPalette.text,
                                      fontSize: shortWide ? 11.5 : (compact ? 12.2 : 12.8),
                                      height: 1,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: .35,
                                    ),
                                  ),
                                  SizedBox(height: shortWide ? 4 : 5),
                                  _HealthBar(
                                    progress: controller.protagonistHp / 100,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: shortWide ? 2 : 6),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                NovelScoreChip(
                  score: controller.score,
                  onTap: onOpenStore,
                  compact: compact,
                ),
                SizedBox(width: shortWide ? 0 : 2),
                _TopIconButton(
                  tooltip: '设置',
                  icon: Icons.settings_outlined,
                  assetPath: 'assets/images/icons/settings.png',
                  onTap: onOpenSettings,
                  size: shortWide ? 18 : 20,
                  dimension: buttonDimension,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class NovelGoalHud extends StatefulWidget {
  const NovelGoalHud({
    super.key,
    required this.text,
    this.feedbackEvent,
  });

  final String text;
  final NovelHudEvent? feedbackEvent;

  @override
  State<NovelGoalHud> createState() => _NovelGoalHudState();
}

class _NovelGoalHudState extends State<NovelGoalHud> {
  String _displayText = '';
  String _status = 'normal';
  bool _visible = false;
  double _scale = 1;
  int _lastFeedbackId = -1;
  int _animationToken = 0;

  @override
  void initState() {
    super.initState();
    _displayText = widget.text.trim();
    _visible = _displayText.isNotEmpty;
  }

  bool _isGoalFeedback(NovelHudEvent? event) {
    return event != null &&
        (event.kind == 'goal_completed' || event.kind == 'goal_failed');
  }

  @override
  void didUpdateWidget(covariant NovelGoalHud oldWidget) {
    super.didUpdateWidget(oldWidget);

    final event = widget.feedbackEvent;
    if (_isGoalFeedback(event) && event!.id != _lastFeedbackId) {
      _lastFeedbackId = event.id;
      unawaited(_playGoalFeedback(event));
      return;
    }

    final next = widget.text.trim();
    if (_status == 'normal' && next != _displayText) {
      unawaited(_swapGoal(next));
    }
  }

  Future<void> _swapGoal(String next) async {
    final token = ++_animationToken;

    if (_displayText.isNotEmpty) {
      setState(() {
        _visible = false;
        _scale = 1;
      });
      await Future<void>.delayed(const Duration(milliseconds: 190));
      if (!mounted || token != _animationToken) return;
    }

    setState(() {
      _status = 'normal';
      _displayText = next;
      _visible = next.isNotEmpty;
      _scale = 1;
    });
  }

  Future<void> _playGoalFeedback(NovelHudEvent event) async {
    final token = ++_animationToken;
    final feedbackText = event.detail.trim().isNotEmpty
        ? event.detail.trim()
        : (_displayText.isNotEmpty ? _displayText : widget.text.trim());

    setState(() {
      _status = event.kind == 'goal_failed' ? 'failed' : 'completed';
      _displayText = feedbackText;
      _visible = feedbackText.isNotEmpty;
      _scale = 1.15; // ⬅️ 从 1.045 改为 1.15，放大冲击力
    });

    await Future<void>.delayed(const Duration(milliseconds: 300)); // ⬅️ 从 220 延长到 300 毫秒
    if (!mounted || token != _animationToken) return;
    setState(() => _scale = 1);

    // 延长成功/失败状态的停留时间，让玩家有充足时间看清楚左上角的变化
    await Future<void>.delayed(const Duration(milliseconds: 1400)); // ⬅️ 从 650 延长到 1400 毫秒
    if (!mounted || token != _animationToken) return;
    setState(() => _visible = false);

    await Future<void>.delayed(const Duration(milliseconds: 270));
    if (!mounted || token != _animationToken) return;

    final next = widget.text.trim();
    setState(() {
      _status = 'normal';
      _displayText = next;
      _visible = next.isNotEmpty;
      _scale = 1;
    });
  }

  @override
  void dispose() {
    _animationToken++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final compact = NovelViewportMetrics.of(context).compactChrome;
    final completed = _status == 'completed';
    final failed = _status == 'failed';
    final maxGoalWidth = math.min(
      compact ? 286.0 : 372.0,
      media.size.width * .5,
    );

    final feedbackLabel = completed ? '目标完成' : '目标失败';
    final feedbackAccent = failed ? NovelPalette.danger : NovelPalette.accent;
    final feedbackIcon = failed ? Icons.close_rounded : Icons.check_rounded;
    const activeGoalGold = Color(0xFFF1C36A);

    return IgnorePointer(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxGoalWidth),
        child: Padding(
          padding: EdgeInsets.only(left: compact ? 10 : 14),
          child: AnimatedOpacity(
            opacity: _visible ? 1 : 0,
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            child: AnimatedScale(
              scale: _scale,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              alignment: Alignment.centerLeft,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (completed || failed) ...<Widget>[
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(
                          feedbackIcon,
                          size: compact ? 13 : 14,
                          color: feedbackAccent,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          feedbackLabel,
                          style: TextStyle(
                            color: feedbackAccent,
                            fontFamily: 'MiSans',
                            fontSize: compact ? 9.2 : 9.6,
                            height: 1,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.15,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                  ],
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      if (!completed && !failed) ...<Widget>[
                        Padding(
                          padding: const EdgeInsets.only(top: 1.2),
                          child: Text(
                            '✦',
                            style: TextStyle(
                              color: activeGoalGold,
                              fontSize: compact ? 10.8 : 11.6,
                              height: 1.25,
                              fontWeight: FontWeight.w800,
                              shadows: const <Shadow>[
                                Shadow(
                                  color: Color(0xB8F1C36A),
                                  blurRadius: 7,
                                ),
                                Shadow(
                                  color: Color(0x66FFE7A1),
                                  blurRadius: 13,
                                ),
                              ],
                            ),
                          ),
                        ),
                        SizedBox(width: compact ? 6 : 7),
                      ],
                      Flexible(
                        child: Text(
                          _displayText,
                          maxLines: compact ? 3 : 2,
                          softWrap: true,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.left,
                          style: TextStyle(
                            color: Colors.white.withOpacity(
                              completed || failed ? .86 : .94,
                            ),
                            fontFamily: 'MiSans',
                            fontSize: compact ? 11.4 : 12.0,
                            height: 1.42,
                            fontWeight: FontWeight.w600,
                            letterSpacing: .12,
                            shadows: const <Shadow>[
                              Shadow(
                                color: Color(0xB0000000),
                                blurRadius: 5,
                                offset: Offset(0, 1),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class NovelLocationHud extends StatelessWidget {
  const NovelLocationHud({
    super.key,
    required this.title,
    this.subtitle = '',
    this.onTap,
    this.loading = false,
    this.showMapGlyph = false,
  });

  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool loading;
  final bool showMapGlyph;

  @override
  Widget build(BuildContext context) {
    if (title.trim().isEmpty && subtitle.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    final compact = NovelViewportMetrics.of(context).compactChrome;
    final hasSubtitle = subtitle.trim().isNotEmpty;
    final maxWidth = compact ? 286.0 : 372.0;

    final content = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          compact ? 8 : 10,
          compact ? 6 : 7,
          compact ? 16 : 20,
          compact ? 6 : 7,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        '当前位置',
                        style: TextStyle(
                          color: Colors.white.withOpacity(.46),
                          fontSize: compact ? 8.0 : 8.4,
                          height: 1,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 1.35,
                        ),
                      ),
                      const SizedBox(width: 7),
                      Container(
                        width: compact ? 54 : 72,
                        height: .7,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: <Color>[
                              Colors.white.withOpacity(.34),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withOpacity(.97),
                      fontFamily: 'WenJinMinchoP0',
                      fontSize: compact ? 14.6 : 15.6,
                      height: 1.08,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.10,
                    ),
                  ),
                  if (hasSubtitle) ...<Widget>[
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withOpacity(.61),
                        fontSize: compact ? 8.2 : 8.7,
                        height: 1,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );

    // 这里只展示场景名称，不再承担世界地图入口。
    // onTap / showMapGlyph 保留为兼容参数，避免旧调用处编译报错。
    return Semantics(
      label: '当前位置$title',
      child: content,
    );
  }
}

class _NovelLocationMapGlyphPainter extends CustomPainter {
  const _NovelLocationMapGlyphPainter();

  @override
  void paint(Canvas canvas, Size size) {
    // 小地图本身直接绘制在场景之上，再用径向 alpha 遮罩让圆周自然消散。
    // 不画圆形底板、硬边框或阴影。
    final layerBounds = Offset.zero & size;
    canvas.saveLayer(layerBounds, Paint());

    // 浅色剧情背景上也要看得清，但只在圆心保留一层很轻的主题深蓝，
    // 到圆周完全透明，不形成黑色卡片或可见硬边。
    canvas.drawRect(
      layerBounds,
      Paint()
        ..shader = RadialGradient(
          center: Alignment.center,
          radius: .74,
          colors: const <Color>[
            Color(0x7010172A),
            Color(0x4810172A),
            Color(0x1610172A),
            Color(0x0010172A),
          ],
          stops: const <double>[0, .46, .76, 1],
        ).createShader(layerBounds),
    );

    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withOpacity(.76);
    final faint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .75
      ..color = Colors.white.withOpacity(.34);
    final glow = Paint()
      ..color = NovelPalette.accent.withOpacity(.92);

    final bounds = Rect.fromLTWH(
      size.width * .19,
      size.height * .20,
      size.width * .62,
      size.height * .56,
    );
    final land = Path()
      ..moveTo(bounds.left, bounds.top + bounds.height * .38)
      ..cubicTo(
        bounds.left + bounds.width * .16,
        bounds.top,
        bounds.left + bounds.width * .40,
        bounds.top + bounds.height * .10,
        bounds.left + bounds.width * .52,
        bounds.top + bounds.height * .05,
      )
      ..cubicTo(
        bounds.right,
        bounds.top + bounds.height * .04,
        bounds.right,
        bounds.top + bounds.height * .48,
        bounds.right - bounds.width * .08,
        bounds.top + bounds.height * .62,
      )
      ..cubicTo(
        bounds.right - bounds.width * .20,
        bounds.bottom,
        bounds.left + bounds.width * .28,
        bounds.bottom,
        bounds.left + bounds.width * .10,
        bounds.bottom - bounds.height * .17,
      )
      ..cubicTo(
        bounds.left - bounds.width * .04,
        bounds.top + bounds.height * .68,
        bounds.left + bounds.width * .04,
        bounds.top + bounds.height * .52,
        bounds.left,
        bounds.top + bounds.height * .38,
      )
      ..close();
    canvas.drawPath(land, line);
    canvas.drawOval(
      Rect.fromCenter(
        center: bounds.center + const Offset(-3, 2),
        width: bounds.width * .45,
        height: bounds.height * .20,
      ),
      faint,
    );
    canvas.drawCircle(
      Offset(bounds.right - bounds.width * .25, bounds.top + bounds.height * .38),
      2.2,
      glow,
    );
    canvas.drawCircle(
      Offset(bounds.left + bounds.width * .24, bounds.bottom - bounds.height * .26),
      1.6,
      Paint()..color = Colors.white.withOpacity(.52),
    );

    canvas.drawRect(
      layerBounds,
      Paint()
        ..blendMode = BlendMode.dstIn
        ..shader = RadialGradient(
          center: Alignment.center,
          radius: .72,
          colors: const <Color>[
            Color(0xFFFFFFFF),
            Color(0xE8FFFFFF),
            Color(0x78FFFFFF),
            Color(0x00FFFFFF),
          ],
          stops: const <double>[0, .46, .72, 1],
        ).createShader(layerBounds),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _NovelLocationMapGlyphPainter oldDelegate) =>
      false;
}

class _TopIconButton extends StatelessWidget {
  const _TopIconButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
    this.assetPath = '',
    this.size = 20,
    this.dimension = 38,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;
  final String assetPath;
  final double size;
  final double dimension;

  Widget _fallbackIcon() {
    return Icon(
      icon,
      size: size,
      color: Colors.white,
      shadows: const <Shadow>[
        Shadow(color: Color(0xAA000000), blurRadius: 8),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cleanAssetPath = assetPath.trim();
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: SizedBox(
            width: dimension,
            height: dimension,
            child: Center(
              child: cleanAssetPath.isEmpty
                  ? _fallbackIcon()
                  : Image.asset(
                      cleanAssetPath,
                      width: size,
                      height: size,
                      fit: BoxFit.contain,
                      color: Colors.white,
                      colorBlendMode: BlendMode.srcIn,
                      filterQuality: FilterQuality.high,
                      gaplessPlayback: true,
                      errorBuilder: (_, __, ___) => _fallbackIcon(),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}



class _ConditionAvatar extends StatelessWidget {
  const _ConditionAvatar({
    required this.gender,
    this.size = 38,
  });

  final String gender;
  final double size;

  bool get _isFemale {
    final value = gender.trim().toLowerCase();
    return value == 'female' ||
        value == '女' ||
        value == '女性' ||
        value == 'woman' ||
        value == 'girl';
  }

  @override
  Widget build(BuildContext context) {
    final fallbackAsset = _isFemale
        ? 'assets/images/female.webp'
        : 'assets/images/male.webp';

    // 左上角固定使用项目内置头像，不读取用户或主角上传的头像地址。
    return SizedBox(
      width: size,
      height: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: NovelArtwork(
          url: '',
          assetCandidates: <String>[fallbackAsset],
          fit: BoxFit.cover,
          alignment: Alignment.center,
          fallbackText: '',
          filterQuality: FilterQuality.medium,
        ),
      ),
    );
  }
}

/// 剧情舞台立绘的克制微动态。
///
/// 单张静态立绘不适合模拟复杂的眨眼或嘴型，否则很容易产生整张图片
/// 被拉扯的廉价感。这里仅做视觉小说常见的三种整体运动：
/// 1. 很慢、幅度极小的待机呼吸；
/// 2. 对白真正开始时的一次轻微前倾；
/// 3. 动画结束后准确回到原位，避免人物持续漂浮。
class NovelActionRail extends StatelessWidget {
  const NovelActionRail({
    super.key,
    required this.onStore,
    required this.onInventory,
    required this.onCharacters,
    required this.onJourney,
  });

  final VoidCallback onStore;
  final VoidCallback onInventory;
  final VoidCallback onCharacters;
  final VoidCallback onJourney;

  @override
  Widget build(BuildContext context) {
    return _GlassSurface(
        radius: 14,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
            Tooltip(
              message: '积分兑换',
              child: InkResponse(
                onTap: onStore,
                radius: 24,
                child: SizedBox(
                  width: 43, 
                  height: 42, 
                  child: Center(
                    child: Image.asset(
                      'assets/images/xing.webp', 
                      width: 19, 
                      height: 19,
                    ),
                  ),
                ),
              ),
            ),
            _RailButton(icon: Icons.inventory_2_outlined, label: '背包', onTap: onInventory),
            _RailButton(icon: Icons.people_outline_rounded, label: '人物', onTap: onCharacters),
            _RailButton(icon: Icons.menu_book_outlined, label: '旅程', onTap: onJourney),
          ]),
        ));
  }
}


class NovelArchiveRail extends StatelessWidget {
  const NovelArchiveRail({
    super.key,
    required this.onCharacters,
    required this.onJourney,
    required this.onInventory,
    // 兼容旧调用；“世界”入口已统一交给 NovelSideArchiveBar，避免重复显示。
    this.onWorld,
  });

  final VoidCallback onCharacters;
  final VoidCallback onJourney;
  final VoidCallback onInventory;
  final VoidCallback? onWorld;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 390;

    // 完全复用原来底部的 _StoryImageAction 美术：
    // 原图片、原尺寸、原文字、原透明度、原点击效果都不改。
    // 唯一变化只是从“底部横排”移动到“右侧竖排”。
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        _StoryImageAction(
          asset: 'assets/images/relation.webp',
          label: '人物',
          compact: compact,
          onTap: onCharacters,
        ),
        SizedBox(height: compact ? 5 : 7),
        _StoryImageAction(
          asset: 'assets/images/journey.webp',
          label: '经历',
          compact: compact,
          onTap: onJourney,
        ),
        SizedBox(height: compact ? 5 : 7),
        _StoryImageAction(
          asset: 'assets/images/inventory.webp',
          label: '背包',
          compact: compact,
          onTap: onInventory,
        ),
      ],
    );
  }
}

class NovelScoreChip extends StatefulWidget {
  const NovelScoreChip({
    super.key,
    required this.score,
    this.onTap,
    this.compact = false,
  });

  final NovelScore score;
  final VoidCallback? onTap;
  final bool compact;

  @override
  State<NovelScoreChip> createState() => _NovelScoreChipState();
}

class _NovelScoreChipState extends State<NovelScoreChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 760),
    );
    _scale = TweenSequence<double>(<TweenSequenceItem<double>>[
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: 1, end: 1.28)
            .chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 34,
      ),
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: 1.28, end: 1)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 66,
      ),
    ]).animate(_controller);

    // 积分条重新挂载时如果仍带着 delta，也补播一次原位变化。
    if (widget.score.delta != 0) {
      _controller.forward();
    }
  }

  @override
  void didUpdateWidget(covariant NovelScoreChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.score.total != oldWidget.score.total) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: _novelPrimaryTabIndex,
      builder: (context, tabIndex, _) {
        if (tabIndex != 0) return const SizedBox.shrink();

        return AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final animating = _controller.isAnimating;

            return Transform.scale(
              scale: animating ? _scale.value : 1,
              alignment: Alignment.centerRight,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: widget.onTap,
                  borderRadius: BorderRadius.circular(20),
                  splashColor: Colors.white.withOpacity(.04),
                  highlightColor: Colors.white.withOpacity(.02),
                  child: Container(
                    // 极简风的微透玻璃底，不再死黑
                    margin: EdgeInsets.symmetric(
                      horizontal: widget.compact ? 2 : 4,
                      vertical: widget.compact ? 4 : 5,
                    ),
                    padding: EdgeInsets.fromLTRB(
                      widget.compact ? 3 : 4,
                      3,
                      widget.compact ? 7 : 10,
                      3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(.18), // 非常清透的底色，若隐若现
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withOpacity(.12), // 极细的微白高光边，模拟玻璃折射
                        width: 0.5,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        // 1. 星块图标（尺寸收敛一点，显得更精致）
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          width: animating
                              ? (widget.compact ? 18.5 : 21.0)
                              : (widget.compact ? 17.0 : 19.0),
                          height: animating
                              ? (widget.compact ? 18.5 : 21.0)
                              : (widget.compact ? 17.0 : 19.0),
                          child: Image.asset(
                            'assets/images/xing.webp',
                            fit: BoxFit.contain,
                          ),
                        ),
                        
                        const SizedBox(width: 4),
                        
                        // 2. 纯白极简字体，去掉所有浮夸的颜色和阴影
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 180),
                          transitionBuilder: (child, animation) => FadeTransition(
                            opacity: animation,
                            child: ScaleTransition(
                              scale: Tween<double>(begin: .86, end: 1).animate(animation),
                              child: child,
                            ),
                          ),
                          child: Text(
                            '${widget.score.total}',
                            key: ValueKey<int>(widget.score.total),
                            style: TextStyle(
                              color: Colors.white.withOpacity(.92), // 纯净的白色
                              fontSize: animating
                                  ? (widget.compact ? 13.2 : 14.5)
                                  : (widget.compact ? 12.6 : 14),
                              height: 1.1,
                              fontWeight: FontWeight.w600, // 字重调得秀气一点
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
class NovelTaskBadge extends StatelessWidget {
  const NovelTaskBadge({
    super.key,
    required this.task,
    required this.completed,
  });

  final NovelTask? task;
  final bool completed;

  @override
  Widget build(BuildContext context) {
    final text = completed ? '任务完成' : task?.display ?? '';
    if (text.isEmpty) return const SizedBox.shrink();
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 420),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(position: Tween<Offset>(begin: const Offset(-.08, 0), end: Offset.zero).animate(animation), child: child),
      ),
      child: Container(
        key: ValueKey<String>('$completed|$text'),
        constraints: const BoxConstraints(maxWidth: 250),
        padding: const EdgeInsets.fromLTRB(9, 7, 12, 7),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(.22),
          borderRadius: BorderRadius.circular(5),
          border: Border(left: BorderSide(color: completed ? Colors.white24 : const Color(0xFFF1C36A), width: 2)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
          Text(completed ? '✓' : '✦', style: TextStyle(color: completed ? Colors.white30 : const Color(0xFFF1C36A), fontSize: 11, fontWeight: FontWeight.w800)),
          const SizedBox(width: 7),
          Flexible(
              child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: completed ? Colors.white38 : Colors.white.withOpacity(.84), fontSize: 10.5, height: 1.2, fontWeight: FontWeight.w600, decoration: completed ? TextDecoration.lineThrough : TextDecoration.none),
          )),
        ]),
      ),
    );
  }
}

class NovelHudEventOverlay extends StatefulWidget {
  const NovelHudEventOverlay({
    super.key,
    required this.event,
  });

  final NovelHudEvent event;

  @override
  State<NovelHudEventOverlay> createState() => _NovelHudEventOverlayState();
}

class _NovelHudEventOverlayState extends State<NovelHudEventOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<double> _slide;
  late final Animation<double> _scale;

  bool get _isGoal =>
      widget.event.kind == 'goal_completed' ||
      widget.event.kind == 'goal_failed';

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1900),
    )..forward();

    _opacity = TweenSequence<double>(<TweenSequenceItem<double>>[
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: 0, end: 1)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 16,
      ),
      TweenSequenceItem<double>(
        tween: ConstantTween<double>(1),
        weight: 58,
      ),
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: 1, end: 0)
            .chain(CurveTween(curve: Curves.easeInCubic)),
        weight: 26,
      ),
    ]).animate(_controller);

    _slide = Tween<double>(
      begin: _isGoal ? 14 : 9,
      end: -8,
    ).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );

    _scale = TweenSequence<double>(<TweenSequenceItem<double>>[
      TweenSequenceItem<double>(
        tween: Tween<double>(
          begin: _isGoal ? .88 : .96,
          end: _isGoal ? 1.06 : 1.015,
        ).chain(CurveTween(curve: Curves.easeOutBack)),
        weight: _isGoal ? 32 : 26,
      ),
      TweenSequenceItem<double>(
        tween: Tween<double>(
          begin: _isGoal ? 1.06 : 1.015,
          end: 1,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: _isGoal ? 68 : 74,
      ),
    ]).animate(_controller);
  }

  Color get _accent {
    return switch (widget.event.tone) {
      'rose' => const Color(0xFFFF9FBA),
      'danger' => const Color(0xFFFF7A75),
      'critical' => const Color(0xFFD58AFF),
      'warning' => const Color(0xFFF2C268),
      'gold' => const Color(0xFFF0CB76),
      'violet' => const Color(0xFFC4ACE4),
      'accent' => NovelPalette.accent,
      _ => Colors.white.withOpacity(.86),
    };
  }

  IconData get _goalIcon => widget.event.kind == 'goal_failed'
      ? Icons.close_rounded
      : Icons.check_rounded;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _buildPlainFeedback(Color accent) {
    final title = widget.event.title.trim();
    final detail = widget.event.detail.trim();
    final text = <String>[
      if (title.isNotEmpty) title,
      if (detail.isNotEmpty) detail,
    ].join('  ·  ');

    return Text(
      text,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: widget.event.kind == 'inventory'
            ? Colors.white.withOpacity(.94)
            : accent.withOpacity(.96),
        fontSize: 11.5,
        height: 1.5,
        fontWeight: FontWeight.w700,
        letterSpacing: .35,
        shadows: const <Shadow>[
          Shadow(
            color: Color(0xF0000000),
            blurRadius: 5,
            offset: Offset(0, 2),
          ),
          Shadow(
            color: Color(0xB0000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
    );
  }

  Widget _buildGoalFeedback(Color accent) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 430),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(_goalIcon, color: accent, size: 18),
              const SizedBox(width: 7),
              Text(
                widget.event.title,
                style: TextStyle(
                  color: accent,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  shadows: const <Shadow>[
                    Shadow(
                      color: Color(0xF0000000),
                      blurRadius: 7,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (widget.event.detail.trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: 5),
            Text(
              widget.event.detail,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(.78),
                fontSize: 10.4,
                height: 1.45,
                fontWeight: FontWeight.w600,
                shadows: const <Shadow>[
                  Shadow(
                    color: Color(0xE6000000),
                    blurRadius: 6,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = _accent;

    return IgnorePointer(
      child: SafeArea(
        child: Align(
          alignment: Alignment(0, _isGoal ? -.34 : -.52),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final failed = widget.event.kind == 'goal_failed';
                final shakeX = failed
                    ? math.sin(_controller.value * math.pi * 8) *
                        (1 - _controller.value) *
                        6
                    : 0.0;

                return Opacity(
                  opacity: _opacity.value,
                  child: Transform.translate(
                    offset: Offset(shakeX, _slide.value),
                    child: Transform.scale(
                      scale: _scale.value,
                      child: _isGoal
                          ? _buildGoalFeedback(accent)
                          : _buildPlainFeedback(accent),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _HealthBar extends StatelessWidget {
  const _HealthBar({required this.progress});
  final double progress;

  Color get _healthColor {
    final p = progress.clamp(0.0, 1.0).toDouble();
    if (p <= .15) return const Color(0xFFC15CFF); // 濒危：紫红
    if (p <= .40) return const Color(0xFFEF5D5D); // 重伤：红
    if (p <= .75) return const Color(0xFFF2B648); // 受损：琥珀
    return NovelPalette.accent; // 健康：统一使用主题主色绿
  }

  @override
  Widget build(BuildContext context) {
    final p = progress.clamp(0.0, 1.0).toDouble();
    final color = _healthColor;
    return SizedBox(
        // HP 条只作为角色状态提示，不需要占据姓名下方整块宽度。
        // 68 -> 48，缩短约 29%，在手机 HUD 上更轻巧。
        width: 48,
        height: 3,
        child: Stack(alignment: Alignment.centerLeft, children: <Widget>[
          Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(color: Colors.black.withOpacity(.36), borderRadius: BorderRadius.circular(20)))),
          FractionallySizedBox(
              widthFactor: p,
              alignment: Alignment.centerLeft,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 420),
                curve: Curves.easeOutCubic,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: color.withOpacity(.72),
                      blurRadius: 10,
                      spreadRadius: .45,
                    ),
                    BoxShadow(
                      color: color.withOpacity(.28),
                      blurRadius: 18,
                      spreadRadius: .8,
                    ),
                  ],
                ),
              )),
        ]));
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({required this.icon, required this.label, required this.onTap, this.color});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
        message: label,
        child: InkResponse(
          onTap: onTap,
          radius: 24,
          child: SizedBox(width: 43, height: 42, child: Icon(icon, color: color ?? Colors.white.withOpacity(.58), size: 19)),
        ));
  }
}

class _GlassSurface extends StatelessWidget {
  const _GlassSurface({
    required this.child,
    this.radius = 16,
    this.blur = 18,
    this.color = const Color(0x73191B19),
  });

  final Widget child;
  final double radius;
  final double blur;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: _AdaptiveBackdropBlur(
            sigma: blur,
            child: DecoratedBox(
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(radius), border: Border.all(color: Colors.white.withOpacity(.08)), boxShadow: const <BoxShadow>[BoxShadow(color: Color(0x45000000), blurRadius: 22, offset: Offset(0, 8))]),
              child: child,
            )));
  }
}
/// 选择面板 —— 去掉了闪电/体力消耗徽标，改为反光毛玻璃卡片，
/// 三个选项自然贴底部展示，标题“请做出你的选择”置于选项上方。
/// 用法：NovelChoicePanel(options: ['借势反咬…', '正大光明…', '偷看系统…'], onSelect: (text) {...})
