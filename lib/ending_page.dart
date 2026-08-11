import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'app_shared.dart';

/// 角色羁绊数据结构。
///
/// [avatarUrl]、[relationship] 都是可选字段，旧调用方式不需要修改。
class CharacterBond {
  const CharacterBond({
    required this.name,
    required this.affection,
    this.avatarUrl,
    this.relationship,
  });

  final String name;
  final int affection;
  final String? avatarUrl;
  final String? relationship;
}

/// 更偏叙事感的终章结算页。
///
/// 兼容原有必传参数，同时新增了一组可选配置：
/// - [backgroundImageUrl]：结局 CG / 当前场景背景图。
/// - [endingTitle]：具体结局名称，例如「向黎明而行」。
/// - [endingSubtitle]：结局副标题。
/// - [endingCode]：结局编号，例如「结局 07」。
/// - [onReplay]：重新体验本章。
/// - [onArchive]：保存 / 查看结局档案。
class EndingPage extends StatefulWidget {
  const EndingPage({
    super.key,
    required this.text,
    required this.charsMap,
    required this.milestones,
    required this.triggered_events,
    required this.onClose,
    this.backgroundImageUrl,
    this.endingTitle = '故事终章',
    this.endingSubtitle = '你的每一次选择，最终都在这一页落笔。',
    this.endingCode = '结局',
    this.onReplay,
    this.onArchive,
  });

  final String text;
  final Map<String, CharacterBond> charsMap;
  final List<String> milestones;

  // ignore: non_constant_identifier_names
  final List<String> triggered_events;

  final VoidCallback onClose;
  final String? backgroundImageUrl;
  final String endingTitle;
  final String endingSubtitle;
  final String endingCode;
  final VoidCallback? onReplay;
  final VoidCallback? onArchive;

  @override
  State<EndingPage> createState() => _EndingPageState();
}

class _EndingPageState extends State<EndingPage>
    with TickerProviderStateMixin {
  final GlobalKey _archiveKey = GlobalKey();

  late final AnimationController _entranceController;
  late final AnimationController _ambientController;

  late final Animation<double> _heroAnimation;
  late final Animation<double> _storyAnimation;
  late final Animation<double> _bondAnimation;
  late final Animation<double> _memoryAnimation;
  late final Animation<double> _timelineAnimation;
  late final Animation<double> _actionAnimation;

  @override
  void initState() {
    super.initState();

    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1380),
    );

    _ambientController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    )..repeat(reverse: true);

    _heroAnimation = _interval(0.00, 0.34);
    _storyAnimation = _interval(0.18, 0.52);
    _bondAnimation = _interval(0.30, 0.64);
    _memoryAnimation = _interval(0.42, 0.76);
    _timelineAnimation = _interval(0.54, 0.88);
    _actionAnimation = _interval(0.66, 1.00);

    _entranceController.forward();
  }

  Animation<double> _interval(double begin, double end) {
    return CurvedAnimation(
      parent: _entranceController,
      curve: Interval(begin, end, curve: Curves.easeOutCubic),
    );
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _ambientController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final screenSize = media.size;
    final compact = screenSize.width < 620;
    final contentWidth = math.min(screenSize.width - (compact ? 32 : 64), 780.0);
    final usableHeight = screenSize.height - media.padding.top;
    final heroMinHeight = compact
        ? math.min(math.max(usableHeight * 0.55, 420.0), 510.0)
        : math.min(math.max(usableHeight * 0.58, 480.0), 600.0);

    return Scaffold(
      backgroundColor: const Color(0xFF090A0D),
      body: Stack(
        fit: StackFit.expand,
        children: [
          _EndingBackground(
            imageUrl: widget.backgroundImageUrl,
            animation: _ambientController,
          ),
          CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: SafeArea(
                  bottom: false,
                  child: Center(
                    child: SizedBox(
                      width: contentWidth,
                      child: _animatedEntrance(
                        animation: _heroAnimation,
                        offsetY: 28,
                        child: _buildHero(
                          context,
                          minHeight: heroMinHeight,
                          compact: compact,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Container(
                  key: _archiveKey,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        const Color(0xFF0D0E12).withOpacity(0.86),
                        const Color(0xFF090A0D),
                      ],
                    ),
                  ),
                  child: Center(
                    child: SizedBox(
                      width: contentWidth,
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          0,
                          compact ? 24 : 34,
                          0,
                          media.padding.bottom + 38,
                        ),
                        child: Column(
                          children: [
                            _animatedEntrance(
                              animation: _storyAnimation,
                              child: _buildStorySection(),
                            ),
                            if (widget.charsMap.isNotEmpty) ...[
                              const SizedBox(height: 42),
                              _animatedEntrance(
                                animation: _bondAnimation,
                                child: _buildBondSection(compact),
                              ),
                            ],
                            if (widget.milestones.isNotEmpty) ...[
                              const SizedBox(height: 42),
                              _animatedEntrance(
                                animation: _memoryAnimation,
                                child: _buildMemorySection(),
                              ),
                            ],
                            if (widget.triggered_events.isNotEmpty) ...[
                              const SizedBox(height: 42),
                              _animatedEntrance(
                                animation: _timelineAnimation,
                                child: _buildTimelineSection(),
                              ),
                            ],
                            const SizedBox(height: 48),
                            _animatedEntrance(
                              animation: _actionAnimation,
                              child: _buildActions(compact),
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
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.only(top: 10, right: 14),
                child: _TopCloseButton(onTap: widget.onClose),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHero(
    BuildContext context, {
    required double minHeight,
    required bool compact,
  }) {
    final averageAffection = _averageAffection;

    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: minHeight),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          compact ? 4 : 10,
          compact ? 46 : 64,
          compact ? 4 : 10,
          compact ? 22 : 28,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    color: AppColors.accent,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '终章已至',
                  style: TextStyle(
                    color: AppColors.textOnDarkMuted,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2.0,
                  ),
                ),
                const Spacer(),
                Text(
                  widget.endingCode,
                  style: TextStyle(
                    color: AppColors.textOnDarkMuted,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
            SizedBox(height: compact ? 68 : 92),
            Container(
              constraints: const BoxConstraints(maxWidth: 120),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.04),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: Text(
                '故事结局',
                style: TextStyle(
                  color: AppColors.textOnDark.withOpacity(0.82),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.0,
                ),
              ),
            ),
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: Text(
                widget.endingTitle,
                style: TextStyle(
                  color: AppColors.textOnDark,
                  fontSize: compact ? 40 : 58,
                  height: 1.08,
                  fontWeight: FontWeight.w800,
                  letterSpacing: compact ? -1.2 : -1.8,
                  shadows: const [
                    Shadow(
                      color: Color(0x80000000),
                      blurRadius: 24,
                      offset: Offset(0, 10),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Text(
                widget.endingSubtitle,
                style: TextStyle(
                  color: AppColors.textOnDark.withOpacity(0.72),
                  fontSize: compact ? 14 : 16,
                  height: 1.8,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: 26),
            _HeroQuote(text: _buildQuoteText()),
            const SizedBox(height: 26),
            _HeroSummary(
              characterCount: widget.charsMap.length,
              memoryCount: widget.milestones.length,
              eventCount: widget.triggered_events.length,
              averageAffection: averageAffection,
              compact: compact,
            ),
            SizedBox(height: compact ? 24 : 30),
            AnimatedBuilder(
              animation: _ambientController,
              builder: (context, child) {
                return Transform.translate(
                  offset: Offset(0, 2.5 * _ambientController.value),
                  child: Opacity(
                    opacity: 0.66 + (_ambientController.value * 0.22),
                    child: child,
                  ),
                );
              },
              child: Align(
                alignment: Alignment.centerLeft,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _scrollToArchive,
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 2,
                        vertical: 10,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            LucideIcons.chevronDown,
                            size: 16,
                            color: AppColors.textOnDarkMuted,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '展开旅程档案',
                            style: TextStyle(
                              color: AppColors.textOnDarkMuted,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.3,
                            ),
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
      ),
    );
  }

  String _buildQuoteText() {
    if (widget.milestones.isNotEmpty) {
      return '你记住了「${widget.milestones.first}」，而故事也因此记住了你。';
    }
    if (widget.triggered_events.isNotEmpty) {
      return '你所走过的每一步，最终都通向了这一页的结尾。';
    }
    return '故事已经落幕，但它留下的回声，还会在你心里停留一阵子。';
  }

  Future<void> _scrollToArchive() async {
    final archiveContext = _archiveKey.currentContext;
    if (archiveContext == null) return;

    await Scrollable.ensureVisible(
      archiveContext,
      duration: const Duration(milliseconds: 620),
      curve: Curves.easeInOutCubic,
      alignment: 0.02,
    );
  }

  Widget _buildStorySection() {
    return _ArchiveSection(
      index: '壹',
      eyebrow: '终章叙事',
      title: '这一页的答案',
      subtitle: '不是统计意义上的结果，而是这段旅程真正留下的情绪。',
      child: _PaperGlassPanel(
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 24),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 2,
              height: 62,
              color: AppColors.accent.withOpacity(0.85),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: SelectableText(
                widget.text,
                textAlign: TextAlign.justify,
                style: TextStyle(
                  color: AppColors.textOnDark.withOpacity(0.84),
                  fontSize: 15.5,
                  height: 2.0,
                  fontWeight: FontWeight.w400,
                  letterSpacing: 0.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBondSection(bool compact) {
    final bonds = widget.charsMap.values.toList()
      ..sort((a, b) => b.affection.compareTo(a.affection));

    return _ArchiveSection(
      index: '贰',
      eyebrow: '人物小传',
      title: '角色羁绊',
      subtitle: '有人陪你走得更远，有人只停留片刻，但他们都写进了这次结局。',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = !compact && constraints.maxWidth >= 680 ? 2 : 1;
          final spacing = 12.0;
          final itemWidth = columns == 1
              ? constraints.maxWidth
              : (constraints.maxWidth - spacing) / 2;

          return Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: bonds
                .map(
                  (bond) => SizedBox(
                    width: itemWidth,
                    child: _BondCard(bond: bond),
                  ),
                )
                .toList(),
          );
        },
      ),
    );
  }

  Widget _buildMemorySection() {
    return _ArchiveSection(
      index: '叁',
      eyebrow: '回忆摘录',
      title: '共同记忆',
      subtitle: '这些片段不会改变结局，却让这一次的结局有了独一无二的气味。',
      child: _PaperGlassPanel(
        padding: const EdgeInsets.all(18),
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: widget.milestones.asMap().entries.map((entry) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.032),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '片段 ${(entry.key + 1).toString().padLeft(2, '0')}',
                    style: const TextStyle(
                      color: AppColors.accent,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    entry.value,
                    style: TextStyle(
                      color: AppColors.textOnDark.withOpacity(0.84),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildTimelineSection() {
    return _ArchiveSection(
      index: '肆',
      eyebrow: '命运轨迹',
      title: '你走过的路',
      subtitle: '那些做出选择的瞬间，如今成为你抵达此处的证词。',
      child: _PaperGlassPanel(
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 8),
        child: Column(
          children: List.generate(widget.triggered_events.length, (index) {
            final isLast = index == widget.triggered_events.length - 1;
            return _TimelineItem(
              index: index,
              text: widget.triggered_events[index],
              isLast: isLast,
            );
          }),
        ),
      ),
    );
  }

  Widget _buildActions(bool compact) {
    final secondaryActions = <Widget>[];

    if (widget.onReplay != null) {
      secondaryActions.add(
        _SecondaryActionButton(
          icon: LucideIcons.rotateCcw,
          label: '重温本章',
          onTap: widget.onReplay!,
        ),
      );
    }

    if (widget.onArchive != null) {
      secondaryActions.add(
        _SecondaryActionButton(
          icon: LucideIcons.bookOpen,
          label: '结局图鉴',
          onTap: widget.onArchive!,
        ),
      );
    }

    final primary = _PrimaryActionButton(
      icon: LucideIcons.arrowRight,
      label: '返回世界',
      onTap: widget.onClose,
    );

    if (compact) {
      return Column(
        children: [
          if (secondaryActions.isNotEmpty)
            Row(
              children: [
                for (var i = 0; i < secondaryActions.length; i++) ...[
                  if (i > 0) const SizedBox(width: 10),
                  Expanded(child: secondaryActions[i]),
                ],
              ],
            ),
          if (secondaryActions.isNotEmpty) const SizedBox(height: 10),
          SizedBox(width: double.infinity, child: primary),
          const SizedBox(height: 16),
          _buildEndMark(),
        ],
      );
    }

    return Column(
      children: [
        Row(
          children: [
            ...secondaryActions.expand(
              (button) => [
                SizedBox(width: 170, child: button),
                const SizedBox(width: 10),
              ],
            ),
            const Spacer(),
            SizedBox(width: 220, child: primary),
          ],
        ),
        const SizedBox(height: 20),
        _buildEndMark(),
      ],
    );
  }

  Widget _buildEndMark() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(width: 28, height: 1, color: Colors.white.withOpacity(0.10)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(
            '故事暂告一段落',
            style: TextStyle(
              color: AppColors.textOnDarkMuted.withOpacity(0.62),
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
            ),
          ),
        ),
        Container(width: 28, height: 1, color: Colors.white.withOpacity(0.10)),
      ],
    );
  }

  Widget _animatedEntrance({
    required Animation<double> animation,
    required Widget child,
    double offsetY = 18,
  }) {
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final value = animation.value.clamp(0.0, 1.0);
        return Transform.translate(
          offset: Offset(0, offsetY * (1 - value)),
          child: Opacity(opacity: value, child: child),
        );
      },
    );
  }

  int get _averageAffection {
    if (widget.charsMap.isEmpty) return 0;
    final total = widget.charsMap.values.fold<int>(
      0,
      (sum, bond) => sum + bond.affection,
    );
    return (total / widget.charsMap.length).round();
  }
}

class _EndingBackground extends StatelessWidget {
  const _EndingBackground({
    required this.imageUrl,
    required this.animation,
  });

  final String? imageUrl;
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    final hasImage = imageUrl != null && imageUrl!.trim().isNotEmpty;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (hasImage)
          Image.network(
            imageUrl!,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const _FallbackBackdrop(),
          )
        else
          const _FallbackBackdrop(),
        BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: hasImage ? 2.0 : 0.0,
            sigmaY: hasImage ? 2.0 : 0.0,
          ),
          child: const SizedBox.expand(),
        ),
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0.0, 0.30, 0.64, 1.0],
              colors: [
                const Color(0xFF050609).withOpacity(0.20),
                const Color(0xFF08090C).withOpacity(0.44),
                const Color(0xFF090A0D).withOpacity(0.86),
                const Color(0xFF090A0D),
              ],
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(-0.15, -0.35),
              radius: 0.90,
              colors: [
                Colors.transparent,
                const Color(0xFF050608).withOpacity(0.10),
                const Color(0xFF050608).withOpacity(0.82),
              ],
              stops: const [0.0, 0.62, 1.0],
            ),
          ),
        ),
        IgnorePointer(
          child: AnimatedBuilder(
            animation: animation,
            builder: (context, _) {
              return Stack(
                children: [
                  Align(
                    alignment: Alignment(
                      -0.72 + animation.value * 0.05,
                      -0.38 + animation.value * 0.03,
                    ),
                    child: Container(
                      width: 260,
                      height: 260,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            AppColors.accent.withOpacity(0.060),
                            AppColors.accent.withOpacity(0.0),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment(
                      0.58 - animation.value * 0.03,
                      -0.18,
                    ),
                    child: Container(
                      width: 180,
                      height: 180,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            Colors.white.withOpacity(0.035),
                            Colors.white.withOpacity(0.0),
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
      ],
    );
  }
}

class _FallbackBackdrop extends StatelessWidget {
  const _FallbackBackdrop();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF15171D),
            Color(0xFF0F1015),
            Color(0xFF090A0D),
          ],
        ),
      ),
      child: CustomPaint(painter: _BackdropDustPainter()),
    );
  }
}

class _BackdropDustPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = Colors.white.withOpacity(0.018)
      ..strokeWidth = 1;

    for (double y = 68; y < size.height; y += 78) {
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y + 18),
        linePaint,
      );
    }

    final dustPaint = Paint()..color = Colors.white.withOpacity(0.038);
    final points = <Offset>[
      Offset(size.width * 0.18, size.height * 0.22),
      Offset(size.width * 0.28, size.height * 0.36),
      Offset(size.width * 0.72, size.height * 0.20),
      Offset(size.width * 0.64, size.height * 0.46),
      Offset(size.width * 0.84, size.height * 0.34),
      Offset(size.width * 0.22, size.height * 0.62),
      Offset(size.width * 0.56, size.height * 0.74),
    ];

    for (final point in points) {
      canvas.drawCircle(point, 1.2, dustPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _HeroQuote extends StatelessWidget {
  const _HeroQuote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 620),
      padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '“',
            style: TextStyle(
              color: AppColors.accent.withOpacity(0.95),
              fontSize: 22,
              fontWeight: FontWeight.w700,
              height: 1.0,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: AppColors.textOnDark.withOpacity(0.72),
                fontSize: 12.8,
                height: 1.8,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroSummary extends StatelessWidget {
  const _HeroSummary({
    required this.characterCount,
    required this.memoryCount,
    required this.eventCount,
    required this.averageAffection,
    required this.compact,
  });

  final int characterCount;
  final int memoryCount;
  final int eventCount;
  final int averageAffection;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final items = [
      _SummaryData(label: '相遇角色', value: '$characterCount'),
      _SummaryData(label: '记住的片段', value: '$memoryCount'),
      _SummaryData(label: '命运节点', value: '$eventCount'),
      if (characterCount > 0)
        _SummaryData(label: '平均羁绊', value: '$averageAffection'),
    ];

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: const Color(0xFFFDFDFD).withOpacity(0.048),
            border: Border.all(color: Colors.white.withOpacity(0.09)),
          ),
          child: compact
              ? Wrap(
                  children: List.generate(items.length, (index) {
                    return SizedBox(
                      width: items.length > 3 ? 150 : 120,
                      child: _SummaryItem(data: items[index]),
                    );
                  }),
                )
              : Row(
                  children: List.generate(items.length, (index) {
                    return Expanded(child: _SummaryItem(data: items[index]));
                  }),
                ),
        ),
      ),
    );
  }
}

class _SummaryData {
  const _SummaryData({required this.label, required this.value});

  final String label;
  final String value;
}

class _SummaryItem extends StatelessWidget {
  const _SummaryItem({required this.data});

  final _SummaryData data;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            data.value,
            style: const TextStyle(
              color: AppColors.textOnDark,
              fontSize: 17,
              height: 1,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            data.label,
            style: TextStyle(
              color: AppColors.textOnDarkMuted,
              fontSize: 10.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _ArchiveSection extends StatelessWidget {
  const _ArchiveSection({
    required this.index,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String index;
  final String eyebrow;
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                index,
                style: const TextStyle(
                  color: AppColors.accent,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Container(
              width: 1,
              height: 54,
              color: Colors.white.withOpacity(0.10),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    eyebrow,
                    style: TextStyle(
                      color: AppColors.textOnDarkMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    title,
                    style: const TextStyle(
                      color: AppColors.textOnDark,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.only(left: 30),
          child: Text(
            subtitle,
            style: TextStyle(
              color: AppColors.textOnDarkMuted,
              fontSize: 12.5,
              height: 1.65,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(height: 20),
        child,
      ],
    );
  }
}

class _PaperGlassPanel extends StatelessWidget {
  const _PaperGlassPanel({required this.child, this.padding = EdgeInsets.zero});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          width: double.infinity,
          padding: padding,
          decoration: BoxDecoration(
            color: const Color(0xFFFDFDFD).withOpacity(0.042),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withOpacity(0.035),
                Colors.white.withOpacity(0.018),
              ],
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _BondCard extends StatelessWidget {
  const _BondCard({required this.bond});

  final CharacterBond bond;

  @override
  Widget build(BuildContext context) {
    final normalized = (bond.affection.clamp(0, 100)) / 100.0;

    return _PaperGlassPanel(
      padding: const EdgeInsets.all(15),
      child: Row(
        children: [
          _BondAvatar(bond: bond),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        bond.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textOnDark,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '${bond.affection}',
                      style: const TextStyle(
                        color: AppColors.accent,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  bond.relationship?.trim().isNotEmpty == true
                      ? bond.relationship!
                      : _bondLabel(bond.affection),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textOnDarkMuted,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 11),
                ClipRRect(
                  borderRadius: BorderRadius.circular(1),
                  child: LinearProgressIndicator(
                    value: normalized,
                    minHeight: 3,
                    backgroundColor: Colors.white.withOpacity(0.07),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      AppColors.accent,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _bondLabel(int affection) {
    if (affection >= 90) return '命运相连';
    if (affection >= 75) return '心意相通';
    if (affection >= 55) return '彼此信任';
    if (affection >= 30) return '留下印记';
    return '故事相逢';
  }
}

class _BondAvatar extends StatelessWidget {
  const _BondAvatar({required this.bond});

  final CharacterBond bond;

  @override
  Widget build(BuildContext context) {
    final avatarUrl = bond.avatarUrl;
    final hasAvatar = avatarUrl != null && avatarUrl.trim().isNotEmpty;

    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white.withOpacity(0.10)),
      ),
      child: hasAvatar
          ? Image.network(
              avatarUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _fallback(),
            )
          : _fallback(),
    );
  }

  Widget _fallback() {
    final initial = bond.name.trim().isEmpty ? '?' : bond.name.trim()[0];
    return Container(
      alignment: Alignment.center,
      color: Colors.white.withOpacity(0.04),
      child: Text(
        initial,
        style: TextStyle(
          color: AppColors.textOnDark.withOpacity(0.76),
          fontSize: 17,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _TimelineItem extends StatelessWidget {
  const _TimelineItem({
    required this.index,
    required this.text,
    required this.isLast,
  });

  final int index;
  final String text;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 38,
            child: Column(
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: index == 0
                        ? AppColors.accent
                        : const Color(0xFF2A2D34),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: index == 0
                          ? AppColors.accent
                          : Colors.white.withOpacity(0.16),
                    ),
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 1,
                      margin: const EdgeInsets.symmetric(vertical: 5),
                      color: Colors.white.withOpacity(0.08),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 14 : 23),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '节点 ${(index + 1).toString().padLeft(2, '0')}',
                    style: TextStyle(
                      color: AppColors.textOnDarkMuted.withOpacity(0.72),
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.9,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    text,
                    style: TextStyle(
                      color: AppColors.textOnDark.withOpacity(0.78),
                      fontSize: 13.5,
                      height: 1.65,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopCloseButton extends StatelessWidget {
  const _TopCloseButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.18),
                border: Border.all(color: Colors.white.withOpacity(0.11)),
              ),
              child: Icon(
                LucideIcons.x,
                size: 18,
                color: AppColors.textOnDark.withOpacity(0.82),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PrimaryActionButton extends StatelessWidget {
  const _PrimaryActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.accent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xFF0B0B0C),
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(width: 10),
              Icon(icon, size: 17, color: const Color(0xFF0B0B0C)),
            ],
          ),
        ),
      ),
    );
  }
}

class _SecondaryActionButton extends StatelessWidget {
  const _SecondaryActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.025),
            border: Border.all(color: Colors.white.withOpacity(0.10)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: AppColors.textOnDarkMuted),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: AppColors.textOnDark.withOpacity(0.78),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
