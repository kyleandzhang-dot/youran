part of '../novel_sheets.dart'; // 或者是 novel_pages.dart，根据你的项目结构调整

import 'package:flutter/material.dart';
import 'dart:ui';

/// 统一游戏页：地图探索层 + 剧情对话层的合并容器。
///
/// 设计原则（对齐 novel_game_page.dart 里已经跑通的做法）：
/// - 地图层直接复用 [NovelExplorationPage]（它已经内置资产加载/生成/碰撞逻辑，
///   构造函数本身就预留了 `asLayer` 用于图层嵌入），不要在这里重新手搓画布。
/// - 是否处于"剧情态"只用一个纯派生值 [_canExitStory] 驱动，每次 build 重新
///   计算，不再额外维护一份 `setState` 缓存的布尔状态机，避免两套状态互相
///   打架导致地图卡死出不来的问题。
class NovelUnifiedGamePage extends StatefulWidget {
  const NovelUnifiedGamePage({
    super.key,
    // 剧情相关依赖
    required this.gameController,
    required this.textController,
    required this.focusNode,
    // 地图相关依赖
    required this.backend,
    this.sessionId,
    this.initialSceneName = '斗破苍穹 乌坦城萧家坊市',

    required this.onSend,
    required this.onContinue,
  });

  final NovelGameController gameController;
  final TextEditingController textController;
  final FocusNode focusNode;
  final NovelBackend backend;
  final String? sessionId;
  final String initialSceneName;
  final ValueChanged<String> onSend;
  final VoidCallback onContinue;

  @override
  State<NovelUnifiedGamePage> createState() => _NovelUnifiedGamePageState();
}

class _NovelUnifiedGamePageState extends State<NovelUnifiedGamePage> {
  @override
  void initState() {
    super.initState();
    // 只需要在 controller / 输入框状态变化时重建一次，让 canExitStory 重新求值。
    widget.gameController.addListener(_onControllerChanged);
    widget.focusNode.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    widget.gameController.removeListener(_onControllerChanged);
    widget.focusNode.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  /// 唯一的真相来源：是否允许退出剧情、回到地图自由探索。
  /// 与 novel_game_page.dart 中的判定条件保持完全一致。
  bool get _canExitStory {
    final controller = widget.gameController;
    return !controller.isGenerating &&
        controller.choices.isEmpty &&
        !controller.isReaderRevealing &&
        novelIsActualLastSentence(controller);
  }

  void _exitStoryMode() {
    if (widget.focusNode.hasFocus) {
      widget.focusNode.unfocus(); // 收起键盘
    }
    // 不需要额外 setState：_canExitStory 已经是 true，下一帧地图层会自动淡入。
  }

  void _handleEntityTap(JsonMap entity) {
    // TODO: 触发与该 NPC/实体的对话逻辑，例如：
    // widget.gameController.talkToEntity(entity);
    //
    // 一旦后端开始生成/产生选项，controller 的监听器会把 canExitStory
    // 自动带回 false，剧情面板会自然淡入——不需要在这里手动切换任何状态。
  }

  @override
  Widget build(BuildContext context) {
    final canExitStory = _canExitStory;

    return Scaffold(
      backgroundColor: const Color(0xFF111315),
      resizeToAvoidBottomInset: false, // 键盘弹出不挤压底层地图
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          // ---------------------------------------------------
          // 1. 最底层：大地图探索层
          // 直接复用完整的 NovelExplorationPage（内置资产加载 / 场景生成 /
          // 碰撞与摇杆逻辑），不要在这里重新拼装 _SceneAssetCanvas。
          // ---------------------------------------------------
          NovelExplorationPage(
            backend: widget.backend,
            sessionId: widget.sessionId,
            initialSceneName: widget.initialSceneName,
            asLayer: true,
            canExitStory: canExitStory,
            onEntityTap: _handleEntityTap,
            onExitStoryTriggered: _exitStoryMode,
          ),

          // ---------------------------------------------------
          // 2. 状态过渡层：进入剧情时，地图变暗并起雾（毛玻璃）
          // ---------------------------------------------------
          IgnorePointer(
            child: AnimatedOpacity(
              opacity: canExitStory ? 0.0 : 1.0,
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOutCubic,
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                child: Container(
                  color: Colors.black.withOpacity(0.55),
                ),
              ),
            ),
          ),

          // ---------------------------------------------------
          // 3. 剧情图层：分镜大图 + 对话面板
          // ---------------------------------------------------
          AnimatedOpacity(
            opacity: canExitStory ? 0.0 : 1.0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            child: IgnorePointer(
              ignoring: canExitStory, // 退出剧情态时禁止点击面板
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // A. 分镜大图（如果有的话，比如全屏 CG）。
                  // 路边日常对话可以不返回图，这里透明即可，只显示带毛玻璃的地图背景。
                  // if (widget.gameController.currentBackgroundImage.isNotEmpty)
                  //   NovelWorldBackground(...),

                  NovelDialogPanel(
                    controller: widget.gameController,
                    textController: widget.textController,
                    focusNode: widget.focusNode,
                    active: !canExitStory,
                    onSend: widget.onSend,
                    onContinue: widget.onContinue,
                    onForceContinue: widget.gameController.forceContinue,
                    onOpenChoices: () {},
                    onOpenInventory: () {},
                    onOpenCharacters: () {},
                    onOpenJourney: () {},
                    onRevert: () {},
                  ),

                  // 点击面板空白处：只有真的允许退出时才生效。
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: () {
                        if (canExitStory && !widget.focusNode.hasFocus) {
                          _exitStoryMode();
                        }
                      },
                      child: const SizedBox.expand(),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ---------------------------------------------------
          // 4. 顶部 HUD（返回等）
          // ---------------------------------------------------
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.maybePop(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}