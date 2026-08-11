import 'package:flutter/material.dart';

import 'app_shared.dart';

/// 剧情行类型。
///
/// 互动游戏不采用传统聊天气泡，而是把剧情作为画面上的字幕层：
/// - narration：旁白；
/// - dialogue：角色对白；
/// - player：玩家行动；
/// - system：章节、时间或系统提示。
enum StoryLineType { narration, dialogue, player, system }

/// 一条可展示的剧情内容。
class StoryLine {
  const StoryLine({
    required this.text,
    this.speaker,
    this.type = StoryLineType.narration,
    this.id,
  });

  final String? id;
  final String text;
  final String? speaker;
  final StoryLineType type;
}

/// 沉浸式剧情字幕层。
///
/// 这个组件应嵌入 HomePage，而不是单独 push 成一个新路由页面。
/// HomePage 负责背景和 HUD，StoryStage 只负责剧情内容展示。
class StoryStage extends StatefulWidget {
  const StoryStage({
    super.key,
    required this.lines,
    this.emptyText = '故事将在这里展开',
    this.maxContentWidth = 720,
  });

  final List<StoryLine> lines;
  final String emptyText;
  final double maxContentWidth;

  @override
  State<StoryStage> createState() => _StoryStageState();
}

class _StoryStageState extends State<StoryStage> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollToLatest(jump: true);
  }

  @override
  void didUpdateWidget(covariant StoryStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lines.length != widget.lines.length ||
        oldWidget.lines.lastOrNull?.text != widget.lines.lastOrNull?.text) {
      _scrollToLatest();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToLatest({bool jump = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;

      final target = _scrollController.position.maxScrollExtent;
      if (jump) {
        _scrollController.jumpTo(target);
      } else {
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 360),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.lines.isEmpty) {
      return _EmptyStoryStage(text: widget.emptyText);
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        const IgnorePointer(child: _StoryReadabilityGradient()),
        Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: widget.maxContentWidth),
            child: ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (bounds) {
                return const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0.0, 0.10, 0.86, 1.0],
                  colors: [
                    Colors.transparent,
                    Colors.white,
                    Colors.white,
                    Colors.transparent,
                  ],
                ).createShader(bounds);
              },
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(8, 44, 8, 34),
                physics: const BouncingScrollPhysics(),
                itemCount: widget.lines.length,
                itemBuilder: (context, index) {
                  final distanceFromLatest = widget.lines.length - 1 - index;
                  return _StoryLineView(
                    line: widget.lines[index],
                    distanceFromLatest: distanceFromLatest,
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _StoryReadabilityGradient extends StatelessWidget {
  const _StoryReadabilityGradient();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: [0.0, 0.20, 0.62, 1.0],
          colors: [
            Color(0x00000000),
            Color(0x08000000),
            Color(0x2B000000),
            Color(0x70000000),
          ],
        ),
      ),
    );
  }
}

class _StoryLineView extends StatelessWidget {
  const _StoryLineView({
    required this.line,
    required this.distanceFromLatest,
  });

  final StoryLine line;
  final int distanceFromLatest;

  double get _opacity {
    if (distanceFromLatest == 0) return 1.0;
    if (distanceFromLatest == 1) return 0.78;
    if (distanceFromLatest == 2) return 0.58;
    if (distanceFromLatest == 3) return 0.40;
    return 0.26;
  }

  bool get _isLatest => distanceFromLatest == 0;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _opacity,
      duration: const Duration(milliseconds: 220),
      child: Padding(
        padding: EdgeInsets.only(
          left: 4,
          right: 4,
          bottom: _isLatest ? 18 : 14,
        ),
        child: switch (line.type) {
          StoryLineType.dialogue => _DialogueLine(
              line: line,
              emphasized: _isLatest,
            ),
          StoryLineType.player => _PlayerActionLine(
              line: line,
              emphasized: _isLatest,
            ),
          StoryLineType.system => _SystemLine(line: line),
          StoryLineType.narration => _NarrationLine(
              line: line,
              emphasized: _isLatest,
            ),
        },
      ),
    );
  }
}

class _NarrationLine extends StatelessWidget {
  const _NarrationLine({
    required this.line,
    required this.emphasized,
  });

  final StoryLine line;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Text(
          line.text,
          style: TextStyle(
            color: const Color(0xFFF2F0E9),
            fontSize: emphasized ? 15.8 : 14.5,
            height: 1.72,
            fontWeight: emphasized ? FontWeight.w500 : FontWeight.w400,
            letterSpacing: 0.16,
            shadows: const [
              Shadow(
                color: Color(0xCC000000),
                blurRadius: 12,
                offset: Offset(0, 2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DialogueLine extends StatelessWidget {
  const _DialogueLine({
    required this.line,
    required this.emphasized,
  });

  final StoryLine line;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final speaker = line.speaker?.trim();

    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 650),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (speaker != null && speaker.isNotEmpty) ...[
              Text(
                speaker,
                style: TextStyle(
                  color: AppColors.accent,
                  fontSize: 11.5,
                  height: 1,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                  shadows: [
                    Shadow(
                      color: AppColors.accent.withOpacity(0.22),
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
            Text(
              line.text,
              style: TextStyle(
                color: const Color(0xFFF8F6F0),
                fontSize: emphasized ? 16.4 : 15.0,
                height: 1.66,
                fontWeight: emphasized ? FontWeight.w500 : FontWeight.w400,
                letterSpacing: 0.12,
                shadows: const [
                  Shadow(
                    color: Color(0xD9000000),
                    blurRadius: 13,
                    offset: Offset(0, 2),
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

class _PlayerActionLine extends StatelessWidget {
  const _PlayerActionLine({
    required this.line,
    required this.emphasized,
  });

  final StoryLine line;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Container(
                width: 12,
                height: 1,
                color: AppColors.accent.withOpacity(0.72),
              ),
            ),
            const SizedBox(width: 9),
            Flexible(
              child: Text(
                line.text,
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: AppColors.accent.withOpacity(0.92),
                  fontSize: emphasized ? 14.4 : 13.5,
                  height: 1.55,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.15,
                  shadows: [
                    Shadow(
                      color: AppColors.accent.withOpacity(0.16),
                      blurRadius: 8,
                    ),
                    const Shadow(
                      color: Color(0xB3000000),
                      blurRadius: 10,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SystemLine extends StatelessWidget {
  const _SystemLine({required this.line});

  final StoryLine line;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        line.text.toUpperCase(),
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white.withOpacity(0.46),
          fontSize: 9.5,
          height: 1.4,
          fontWeight: FontWeight.w600,
          letterSpacing: 2.2,
          shadows: const [
            Shadow(color: Color(0xA6000000), blurRadius: 8),
          ],
        ),
      ),
    );
  }
}

class _EmptyStoryStage extends StatelessWidget {
  const _EmptyStoryStage({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const IgnorePointer(child: _StoryReadabilityGradient()),
        Align(
          alignment: const Alignment(-1, 0.70),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 18,
                  height: 1,
                  color: AppColors.accent.withOpacity(0.55),
                ),
                const SizedBox(width: 10),
                Text(
                  text,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.42),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 1.0,
                    shadows: const [
                      Shadow(color: Color(0xA6000000), blurRadius: 8),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

extension<T> on List<T> {
  T? get lastOrNull => isEmpty ? null : last;
}
