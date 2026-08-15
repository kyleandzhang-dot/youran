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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // 极致纯黑
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          // 背景层只保留极其微弱的残影
          Opacity(
            opacity: 0.35,
            child: NovelWorldBackground(
              url: ending.backgroundUrl.isEmpty
                  ? controller.world.backgroundUrl
                  : ending.backgroundUrl,
            ),
          ),
          
          // 深度模糊与大面积黑幕覆盖，抹除所有杂乱感
          ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 32, sigmaY: 32),
              child: const ColoredBox(color: Colors.black87),
            ),
          ),

          // 主体文字内容，采用电影 Credit Roll 式留白排版
          SafeArea(
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: <Widget>[
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(42, 160, 42, 120),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate(<Widget>[
                      
                      // 结局标题 (极致拉开字间距)
                      Text(
                        ending.title,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.95),
                          fontSize: 28,
                          fontWeight: FontWeight.w400,
                          letterSpacing: 12.0, // 超大字间距营造电影感
                        ),
                      ),
                      const SizedBox(height: 72),

                      // 结局正文
                      Text(
                        ending.text,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.65),
                          fontSize: 14,
                          height: 2.6, // 超大行高
                          letterSpacing: 2.0,
                        ),
                      ),

                      const SizedBox(height: 120),

                      // 共同记忆 (像电影谢幕字幕一样排列)
                      if (ending.milestones.isNotEmpty) ...[
                        Text(
                          '共 同 记 忆',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.25),
                            fontSize: 10,
                            letterSpacing: 16.0,
                          ),
                        ),
                        const SizedBox(height: 36),
                        ...ending.milestones.map((item) => Padding(
                          padding: const EdgeInsets.only(bottom: 20),
                          child: Text(
                            item,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.55),
                              height: 1.8,
                              fontSize: 12,
                              letterSpacing: 2.0,
                            ),
                          ),
                        )),
                        const SizedBox(height: 80),
                      ],

                      // 命运轨迹
                      if (ending.triggeredEvents.isNotEmpty) ...[
                        Text(
                          '命 运 轨 迹',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.25),
                            fontSize: 10,
                            letterSpacing: 16.0,
                          ),
                        ),
                        const SizedBox(height: 36),
                        ...ending.triggeredEvents.map((item) => Padding(
                          padding: const EdgeInsets.only(bottom: 20),
                          child: Text(
                            item,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.55),
                              height: 1.8,
                              fontSize: 12,
                              letterSpacing: 2.0,
                            ),
                          ),
                        )),
                      ],

                      const SizedBox(height: 140),

                      // 底部按钮也融入黑暗
                      Center(
                        child: _ImmersiveGhostButton(
                          label: '返 回 世 界',
                          onTap: () => Navigator.of(context).pop(),
                        ),
                      ),
                      
                    ]),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 极其克制的幽灵按钮
class _ImmersiveGhostButton extends StatelessWidget {
  const _ImmersiveGhostButton({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashColor: Colors.white.withOpacity(.05),
        highlightColor: Colors.transparent,
        child: Container(
          width: 200,
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            color: Colors.transparent, // 全透底
            border: Border.all(color: Colors.white.withOpacity(.12), width: 0.5), // 极细极暗的边框
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withOpacity(.6),
              fontSize: 11,
              fontWeight: FontWeight.w400,
              letterSpacing: 8.0, 
            ),
          ),
        ),
      ),
    );
  }
}

/// 统一打开结局页
Future<void> showNovelEndingPage(
  BuildContext context,
  NovelGameController controller, {
  NovelEnding? endingOverride,
}) async {
  final ending = endingOverride ?? controller.ending;

  await Navigator.of(context).push<void>(
    PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 2400), // 转场时间极度拉长，模拟电影谢幕的黑场
      pageBuilder: (_, animation, secondaryAnimation) => NovelEndingPage(
        controller: controller,
        ending: ending,
      ),
      transitionsBuilder: (_, animation, __, child) {
        // 缓慢的浮现效果
        final curve = CurvedAnimation(parent: animation, curve: Curves.easeOutSine);
        return FadeTransition(
          opacity: curve,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.03),
              end: Offset.zero,
            ).animate(curve),
            child: child,
          ),
        );
      },
    ),
  );
}