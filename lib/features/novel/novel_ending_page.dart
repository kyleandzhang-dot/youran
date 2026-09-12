import 'dart:ui';

import 'package:flutter/material.dart';

import 'novel_game_controller.dart';
import 'novel_models.dart';
import 'novel_widgets.dart';

/// 唯一的小说结局页面入口。
class NovelEndingPage extends StatelessWidget {
  const NovelEndingPage({
    super.key,
    required this.controller,
    required this.ending,
  });

  final NovelGameController controller;
  final NovelEnding ending;

  double _titleLetterSpacing(String title, bool compact) {
    final length = title.runes.length;
    if (length <= 4) return compact ? 5.0 : 8.0;
    if (length <= 7) return compact ? 3.8 : 6.0;
    if (length <= 10) return compact ? 2.6 : 4.2;
    return compact ? 1.6 : 2.4;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          final compact = size.width < 600;
          final landscape = size.width > size.height;
          final veryWide = size.width >= 980;
          final code = ending.code.trim();
          final title = ending.title.trim();
          final bodyText = ending.text.trim();

          final horizontalPadding = compact ? 22.0 : (veryWide ? 56.0 : 38.0);
          final topPadding = landscape
              ? (size.height < 500 ? 58.0 : 86.0)
              : (compact ? 92.0 : 126.0);
          final bottomPadding = compact ? 78.0 : 104.0;

          return Stack(
            fit: StackFit.expand,
            children: <Widget>[
              // 只让结局背景留下朦胧残影；使用 ImageFiltered 而不是整页
              // BackdropFilter，避免对前景正文重复做高成本模糊。
              Positioned.fill(
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: Transform.scale(
                    scale: 1.08,
                    child: Opacity(
                      opacity: .28,
                      child: NovelWorldBackground(
                        url: ending.backgroundUrl.isEmpty
                            ? controller.world.backgroundUrl
                            : ending.backgroundUrl,
                      ),
                    ),
                  ),
                ),
              ),
              const Positioned.fill(
                child: ColoredBox(color: Color(0xD9000000)),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0, -.20),
                      radius: 1.05,
                      colors: <Color>[
                        Colors.white.withOpacity(.035),
                        Colors.transparent,
                        Colors.black.withOpacity(.34),
                      ],
                      stops: const <double>[0, .50, 1],
                    ),
                  ),
                ),
              ),

              SafeArea(
                child: CustomScrollView(
                  physics: const BouncingScrollPhysics(),
                  slivers: <Widget>[
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                        horizontalPadding,
                        topPadding,
                        horizontalPadding,
                        bottomPadding,
                      ),
                      sliver: SliverToBoxAdapter(
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 820),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: <Widget>[
                                if (code.isNotEmpty) ...<Widget>[
                                  Text(
                                    code.toUpperCase(),
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(.34),
                                      fontSize: compact ? 9.5 : 10.5,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: compact ? 2.6 : 3.4,
                                    ),
                                  ),
                                  SizedBox(height: compact ? 18 : 22),
                                ],

                                Center(
                                  child: Container(
                                    width: compact ? 28 : 34,
                                    height: 1,
                                    color: Colors.white.withOpacity(.26),
                                  ),
                                ),
                                SizedBox(height: compact ? 24 : 30),

                                Text(
                                  title.isEmpty ? '故事终章' : title,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(.96),
                                    fontFamily: 'WenJinMinchoP0',
                                    fontSize: compact ? 30 : (veryWide ? 39 : 35),
                                    height: 1.28,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: _titleLetterSpacing(
                                      title.isEmpty ? '故事终章' : title,
                                      compact,
                                    ),
                                    shadows: const <Shadow>[
                                      Shadow(
                                        color: Color(0x66000000),
                                        blurRadius: 18,
                                        offset: Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                ),

                                SizedBox(height: compact ? 42 : 56),

                                if (bodyText.isNotEmpty)
                                  Center(
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(maxWidth: 680),
                                      child: Text(
                                        bodyText,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: Colors.white.withOpacity(.74),
                                          fontSize: compact ? 13.5 : 15,
                                          height: compact ? 2.0 : 2.1,
                                          fontWeight: FontWeight.w400,
                                          letterSpacing: compact ? .7 : 1.0,
                                        ),
                                      ),
                                    ),
                                  ),

                                SizedBox(height: compact ? 66 : 86),

                                if (ending.milestones.isNotEmpty)
                                  _EndingSection(
                                    title: '共 同 记 忆',
                                    subtitle: 'MEMORIES',
                                    items: ending.milestones,
                                    compact: compact,
                                  ),

                                if (ending.milestones.isNotEmpty &&
                                    ending.triggeredEvents.isNotEmpty)
                                  SizedBox(height: compact ? 54 : 72),

                                if (ending.triggeredEvents.isNotEmpty)
                                  _EndingSection(
                                    title: '命 运 轨 迹',
                                    subtitle: 'FATE TRACE',
                                    items: ending.triggeredEvents,
                                    compact: compact,
                                  ),

                                SizedBox(
                                  height: ending.milestones.isEmpty &&
                                          ending.triggeredEvents.isEmpty
                                      ? (compact ? 30 : 42)
                                      : (compact ? 78 : 104),
                                ),

                                Center(
                                  child: _EndingPrimaryButton(
                                    compact: compact,
                                    label: '返 回 世 界',
                                    onTap: () => Navigator.of(context).pop(),
                                  ),
                                ),

                                SizedBox(height: compact ? 24 : 30),
                                Text(
                                  '故事已抵达此刻的终点',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(.22),
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w400,
                                    letterSpacing: 1.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _EndingSection extends StatelessWidget {
  const _EndingSection({
    required this.title,
    required this.subtitle,
    required this.items,
    required this.compact,
  });

  final String title;
  final String subtitle;
  final List<String> items;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final visibleItems = items
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    if (visibleItems.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Container(height: 1, color: Colors.white.withOpacity(.075)),
            ),
            SizedBox(width: compact ? 14 : 18),
            Column(
              children: <Widget>[
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withOpacity(.58),
                    fontSize: compact ? 10 : 10.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: compact ? 4.0 : 5.0,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withOpacity(.20),
                    fontSize: 7.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.8,
                  ),
                ),
              ],
            ),
            SizedBox(width: compact ? 14 : 18),
            Expanded(
              child: Container(height: 1, color: Colors.white.withOpacity(.075)),
            ),
          ],
        ),
        SizedBox(height: compact ? 28 : 34),
        ...List<Widget>.generate(visibleItems.length, (index) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: index == visibleItems.length - 1
                  ? 0
                  : (compact ? 15 : 18),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  width: compact ? 26 : 30,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '${index + 1}'.padLeft(2, '0'),
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: Colors.white.withOpacity(.20),
                        fontSize: 8.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: .5,
                      ),
                    ),
                  ),
                ),
                SizedBox(width: compact ? 12 : 15),
                Expanded(
                  child: Text(
                    visibleItems[index],
                    style: TextStyle(
                      color: Colors.white.withOpacity(.61),
                      fontSize: compact ? 11.8 : 12.5,
                      height: 1.75,
                      fontWeight: FontWeight.w400,
                      letterSpacing: compact ? .45 : .65,
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

class _EndingPrimaryButton extends StatelessWidget {
  const _EndingPrimaryButton({
    required this.label,
    required this.onTap,
    required this.compact,
  });

  final String label;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashColor: Colors.black.withOpacity(.08),
        highlightColor: Colors.black.withOpacity(.04),
        child: Container(
          width: compact ? 176 : 196,
          height: compact ? 46 : 50,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(.95),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.white.withOpacity(.08),
                blurRadius: 22,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(
                Icons.keyboard_return_rounded,
                size: compact ? 15 : 16,
                color: Colors.black.withOpacity(.80),
              ),
              const SizedBox(width: 12),
              Text(
                label,
                style: TextStyle(
                  color: Colors.black.withOpacity(.88),
                  fontSize: compact ? 11.5 : 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: compact ? 3.0 : 3.6,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 统一打开结局页。
Future<void> showNovelEndingPage(
  BuildContext context,
  NovelGameController controller, {
  NovelEnding? endingOverride,
}) async {
  final ending = endingOverride ?? controller.ending;

  await Navigator.of(context).push<void>(
    PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 1800),
      pageBuilder: (_, animation, secondaryAnimation) => NovelEndingPage(
        controller: controller,
        ending: ending,
      ),
      transitionsBuilder: (_, animation, __, child) {
        final curve = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutSine,
        );
        return FadeTransition(
          opacity: curve,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, .018),
              end: Offset.zero,
            ).animate(curve),
            child: child,
          ),
        );
      },
    ),
  );
}
