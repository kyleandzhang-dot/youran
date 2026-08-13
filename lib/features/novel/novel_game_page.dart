import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../game_shell.dart';
import 'novel_game_controller.dart';
import 'novel_models.dart';
import 'novel_sheets.dart';
import 'novel_widgets.dart';

typedef NovelEndingBuilder = Widget Function(
  BuildContext context,
  NovelGameController controller,
  NovelEnding ending,
);

class NovelGamePage extends StatefulWidget {
  const NovelGamePage({
    super.key,
    required this.controller,
    this.fallbackBackgroundAsset = 'assets/images/home_background.jpg',
    this.onBack,
    this.endingBuilder,
    this.disposeController = true,
  });

  final NovelGameController controller;
  final String fallbackBackgroundAsset;
  final VoidCallback? onBack;
  final NovelEndingBuilder? endingBuilder;
  final bool disposeController;

  @override
  State<NovelGamePage> createState() => _NovelGamePageState();
}

class _NovelGamePageState extends State<NovelGamePage>
    with WidgetsBindingObserver {
  final TextEditingController _inputController = TextEditingController();
  final FocusNode _inputFocusNode = FocusNode();

  bool _characterSetupOpen = false;
  bool _characterSetupDismissed = false;
  bool _openingOpen = false;
  bool _fateOpen = false;
  bool _endingOpen = false;
  bool _balanceOpen = false;
  NovelWeatherEffect _weatherPreview = NovelWeatherEffect.none;
  String _lastWeatherAudioKey = '';
  bool? _lastWeatherEffectsEnabled;

  NovelGameController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    controller.addListener(_onControllerChanged);
    unawaited(controller.initialize());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_syncWeatherAmbient(force: true));
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      unawaited(controller.bgm.stop());
      return;
    }
    if (state == AppLifecycleState.resumed && controller.isInitialized) {
      unawaited(controller.socket.connect(controller.sessionId));
      unawaited(controller.bgm.init(
        controller.bgm.currentIntensity,
        controller.bgm.currentSceneMode,
      ));
      unawaited(_syncWeatherAmbient(force: true));
    }
  }

  void _onControllerChanged() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _processOverlayRequests();
      unawaited(_syncWeatherAmbient());
    });
  }

  Future<void> _processOverlayRequests() async {
    // 角色确认弹窗尚未完全退出时，禁止再 push 开场/其他覆盖层。
    // submitCharacterSetup() 成功后会 notify，并把 showOpening 设为 true；
    // 如果这里不拦截，就会出现两个 Dialog 同时操作 Navigator 的 assertion。
    if (_characterSetupOpen) return;

    if (controller.showCharacterSetup && !_characterSetupDismissed) {
      _characterSetupOpen = true;
      final started = await showNovelCharacterSetupDialog(context, controller);
      _characterSetupOpen = false;
      if (!mounted) return;

      if (started) {
        _characterSetupDismissed = false;
        // 等角色弹窗的 reverse transition 完成，再打开开场。
        await Future<void>.delayed(const Duration(milliseconds: 90));
        if (mounted) {
          await _processOverlayRequests();
        }
      } else {
        // 用户主动关闭：本次停留不再强制弹出。重新进入世界后 State 重建，仍会再次出现。
        _characterSetupDismissed = true;
      }
      return;
    }
    if (controller.showOpening && !_openingOpen) {
      _openingOpen = true;
      await showNovelOpeningDialog(context, controller);
      _openingOpen = false;
      return;
    }
    if (controller.showFateRevert && !_fateOpen) {
      _fateOpen = true;
      await showNovelFateRevertDialog(context, controller);
      controller.showFateRevert = false;
      controller.clearMessages();
      _fateOpen = false;
      return;
    }
    if (controller.showEnding && !_endingOpen) {
      _endingOpen = true;
      controller.showEnding = false;
      controller.clearMessages();
      if (widget.endingBuilder != null) {
        await Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (context) => widget.endingBuilder!(context, controller, controller.ending),
          ),
        );
      } else {
        await showDefaultNovelEnding(context, controller);
      }
      _endingOpen = false;
      return;
    }
    if (controller.insufficientBalance && !_balanceOpen) {
      _balanceOpen = true;
      await showGeneralDialog<void>(
        context: context,
        barrierDismissible: true,
        barrierLabel: '关闭余额提示',
        barrierColor: Colors.black.withOpacity(.80),
        transitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (dialogContext, _, __) {
          return Material(
            color: Colors.transparent,
            child: SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 360),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                          decoration: BoxDecoration(
                            color: NovelPalette.panel,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: Colors.white.withOpacity(.08),
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              const Text(
                                '余额不足',
                                style: TextStyle(
                                  color: NovelPalette.text,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 10),
                              const Text(
                                '当前余额不足，无法继续生成剧情。',
                                style: TextStyle(
                                  color: NovelPalette.muted,
                                  fontSize: 11.5,
                                  height: 1.55,
                                ),
                              ),
                              const SizedBox(height: 18),
                              SizedBox(
                                height: 42,
                                child: FilledButton(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: NovelPalette.accent,
                                    foregroundColor: NovelPalette.accentDark,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(5),
                                    ),
                                  ),
                                  onPressed: () =>
                                      Navigator.of(dialogContext).pop(),
                                  child: const Text('知道了'),
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
            ),
          );
        },
        transitionBuilder: (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: ScaleTransition(
              scale: Tween<double>(begin: .97, end: 1).animate(curved),
              child: child,
            ),
          );
        },
      );
      controller.insufficientBalance = false;
      controller.clearMessages();
      _balanceOpen = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller.removeListener(_onControllerChanged);
    _inputController.dispose();
    _inputFocusNode.dispose();
    if (widget.disposeController) controller.dispose();
    super.dispose();
  }


  String get _weatherAudioKey {
    return switch (_weatherPreview) {
      NovelWeatherEffect.rain => 'rain',
      NovelWeatherEffect.snow => 'snow',
      NovelWeatherEffect.thunderstorm => 'thunderstorm',
      NovelWeatherEffect.none => 'none',
    };
  }

  Future<void> _syncWeatherAmbient({bool force = false}) async {
    final effectsEnabled = controller.settings.weatherEffectsEnabled;
    final key = effectsEnabled ? _weatherAudioKey : 'none';
    if (!force &&
        _lastWeatherAudioKey == key &&
        _lastWeatherEffectsEnabled == effectsEnabled) {
      return;
    }

    _lastWeatherAudioKey = key;
    _lastWeatherEffectsEnabled = effectsEnabled;
    await controller.bgm.setWeatherAmbient(
      key,
      effectsEnabled: effectsEnabled,
      force: force,
    );
  }

  void _cycleWeatherPreview() {
    setState(() {
      _weatherPreview = switch (_weatherPreview) {
        NovelWeatherEffect.none => NovelWeatherEffect.rain,
        NovelWeatherEffect.rain => NovelWeatherEffect.snow,
        NovelWeatherEffect.snow => NovelWeatherEffect.thunderstorm,
        NovelWeatherEffect.thunderstorm => NovelWeatherEffect.none,
      };
    });
    unawaited(_syncWeatherAmbient(force: true));
  }

  void _back() {
    final callback = widget.onBack;
    if (callback != null) {
      callback();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GameShell(
      activeScenarioId: controller.scenarioId,
      resizeToAvoidBottomInset: false,
      backgroundColor: controller.settings.backgroundColor,
      builder: (context, openDrawer) {
        return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final customBackground = controller.settings.customBackground;
        final background = customBackground.isNotEmpty
            ? customBackground
            : controller.world.backgroundUrl;
        final weatherEffectsEnabled =
            controller.settings.weatherEffectsEnabled;
        return Scaffold(
          resizeToAvoidBottomInset: true,
          backgroundColor: controller.settings.backgroundColor,
          body: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              RepaintBoundary(
                child: NovelWorldBackground(
                  url: background,
                  fallbackAsset: widget.fallbackBackgroundAsset,
                  // 背景单独成层：流式文字/爱心动画更新时尽量复用已栅格化背景。
                  characterPresent: controller.storyStarted &&
                      controller.currentSpeakerName.isNotEmpty &&
                      !controller.isCinematic,
                  isGenerating: controller.isGenerating,
                  weatherEffect: weatherEffectsEnabled
                      ? _weatherPreview
                      : NovelWeatherEffect.none,
                ),
              ),
              // 角色立绘由 NovelDialogPanel 内部统一绘制。
              // 不在这里再画第二层，避免重复立绘或两套 visible 条件互相打架。
              SafeArea(
                minimum: const EdgeInsets.fromLTRB(14, 10, 14, 15),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 430;
                    return Stack(
                      children: <Widget>[
                        // 电影模式是全屏交互层，但放在 HUD 下面，
                        // 对齐 Vue NarrativeControls(z45) < NovelTopHeader(z50) 的层级关系。
                        if (controller.storyStarted && controller.isCinematic)
                          Positioned.fill(
                            child: NovelCinematicControls(
                              text: controller.currentSentence?.text ?? '',
                              speakerName: controller.currentSpeakerName,
                              isGenerating: controller.isGenerating,
                              isFirst: !controller.hasPrevious,
                              isLast: !controller.hasNext,
                              fontFamily: controller.settings.fontFamily,
                              fontSize: controller.settings.fontSize,
                              onRevert: () => showNovelRevertDialog(context, controller),
                              onPrevious: controller.goPrevious,
                              onNext: controller.goNext,
                              onContinue: controller.hasNext || controller.pendingFateRevert
                                  ? controller.goNext
                                  : controller.continueStory,
                            ),
                          ),
                        Align(
                          alignment: Alignment.topCenter,
                          child: NovelTopHud(
                            controller: controller,
                            onMenu: widget.onBack ?? openDrawer,
                            onOpenProfile: () => showNovelHostProfileSheet(context, controller),
                            onOpenSettings: () => showNovelSettingsSheet(context, controller),
                          ),
                        ),
                        if (controller.storyStarted)
                          Positioned(
                            left: compact ? 7 : 19,
                            right: compact ? 50 : constraints.maxWidth * .28,
                            // 场景转场标题稍微上提，避免压到人物/正文区域。
                            // NovelSceneArrivalTitle 内部同时放宽了中文行高，解决上下笔画被切的问题。
                            top: constraints.maxHeight * (compact ? .13 : .15),
                            child: IgnorePointer(
                              child: NovelSceneArrivalTitle(
                                title: controller.locationTitle,
                                subtitle: controller.locationSubtitle,
                              ),
                            ),
                          ),
                        if (controller.storyStarted && !controller.isGenerating)
                          Positioned(
                            top: 57,
                            right: 3,
                            child: NovelScoreChip(
                              score: controller.score,
                              onTap: () => showNovelStoreSheet(context, controller),
                            ),
                          ),

                        // 角色 / 经历 / 背包从底部移到积分下方。
                        // 一行一个，不加整块面板背景，保持当前 HUD 的轻盈风格。
                        if (controller.storyStarted && !controller.isGenerating)
                          Positioned(
                            top: 90,
                            right: 3,
                            child: NovelArchiveRail(
                              onCharacters: () =>
                                  showNovelCharactersSheet(context, controller),
                              onJourney: () =>
                                  showNovelJourneySheet(context, controller),
                              onInventory: () =>
                                  showNovelInventorySheet(context, controller),
                            ),
                          ),

                        if (controller.storyStarted &&
                            !controller.isGenerating &&
                            weatherEffectsEnabled)
                          Positioned(
                            top: compact ? 248 : 260,
                            right: 3,
                            child: _NovelWeatherTestButton(
                              effect: _weatherPreview,
                              onTap: _cycleWeatherPreview,
                            ),
                          ),
                        if (controller.storyStarted && !controller.isCinematic)
                          Align(
                            alignment: Alignment.bottomCenter,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 720),
                              child: NovelDialogPanel(
                                controller: controller,
                                textController: _inputController,
                                focusNode: _inputFocusNode,
                                onSend: (text) {
                                  controller.goLatest();
                                  unawaited(controller.sendPlayerMessage(text));
                                },
                                onContinue: controller.continueStory,
                                onForceContinue: controller.forceContinue,
                                onOpenChoices: () => showNovelChoicesSheet(context, controller),
                                onOpenInventory: () => showNovelInventorySheet(context, controller),
                                onOpenCharacters: () => showNovelCharactersSheet(context, controller),
                                onOpenJourney: () => showNovelJourneySheet(context, controller),
                                onRevert: () => showNovelRevertDialog(context, controller),
                                onOpenPortrait: controller.currentSpeakerCharacter == null
                                    ? null
                                    : () => showNovelPortraitSheet(context, controller),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
              // 保留氛围型反馈：AI 尚未开始输出正文时显示“故事酝酿中”。
              if (controller.storyStarted &&
                  controller.isGenerating &&
                  (controller.currentSentence?.text.trim().isEmpty ?? true) &&
                  !controller.showDice)
                const NovelBrewingOverlay(),

              // 保留受伤时屏幕周边的呼吸/泛红反馈。
              // 详细伤势文字 HUD 已在 Controller 中关闭，不会再弹窗。
              if (controller.storyStarted)
                NovelDamageFeedbackOverlay(hp: controller.protagonistHp),

              if (controller.isInitializing)
                ColoredBox(
                  color: Colors.black.withOpacity(.58),
                  child: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        CircularProgressIndicator(color: NovelPalette.accent),
                        SizedBox(height: 18),
                        Text('正在载入世界…', style: TextStyle(color: NovelPalette.text, letterSpacing: 2)),
                      ],
                    ),
                  ),
                ),
              if (!controller.isInitializing &&
                  !controller.isInitialized &&
                  controller.lastError.isNotEmpty)
                _FatalError(
                  message: controller.lastError,
                  onRetry: controller.initialize,
                  onBack: widget.onBack ?? openDrawer,
                ),
              if (controller.showDice && controller.diceRoll != null)
                IgnorePointer(child: NovelDiceOverlay(roll: controller.diceRoll!)),
              if (controller.timeSkipLabel.isNotEmpty)
                NovelTimeSkipOverlay(
                  label: controller.timeSkipLabel,
                  onDismiss: controller.dismissTimeSkip,
                ),
              if (controller.showEndingIntro)
                GestureDetector(
                  onTap: () {
                    controller.showEndingIntro = false;
                    controller.clearMessages();
                  },
                  child: const ColoredBox(
                    color: Colors.black,
                    child: Center(
                      child: Text(
                        '故事走向终章',
                        style: TextStyle(
                          color: NovelPalette.text,
                          fontSize: 18,
                          letterSpacing: 5,
                        ),
                      ),
                    ),
                  ),
                ),
              NovelStatusBanner(
                message: controller.lastError.isNotEmpty
                    ? controller.lastError
                    : controller.infoMessage,
                isError: controller.lastError.isNotEmpty,
                onDismiss: controller.clearMessages,
              ),
            ],
          ),
        );
      },
    );
      },
    );
  }
}

class _FatalError extends StatelessWidget {
  const _FatalError({
    required this.message,
    required this.onRetry,
    required this.onBack,
  });

  final String message;
  final Future<void> Function() onRetry;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xE8090A09),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.cloud_off_rounded, color: NovelPalette.danger, size: 40),
                const SizedBox(height: 18),
                const Text(
                  '世界暂时无法载入',
                  style: TextStyle(color: NovelPalette.text, fontSize: 21, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: NovelPalette.muted, height: 1.6),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    TextButton(onPressed: onBack, child: const Text('打开菜单')),
                    const SizedBox(width: 10),
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: NovelPalette.accent, foregroundColor: NovelPalette.accentDark),
                      onPressed: onRetry,
                      child: const Text('重新载入'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NovelWeatherTestButton extends StatelessWidget {
  const _NovelWeatherTestButton({
    required this.effect,
    required this.onTap,
  });

  final NovelWeatherEffect effect;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '测试天气：点击切换 无 / 雨 / 雪 / 雷雨',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            constraints: const BoxConstraints(minWidth: 48),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0xB51A1C20),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(.14)),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Color(0x4A000000),
                  blurRadius: 12,
                  offset: Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  effect.icon,
                  size: 17,
                  color: Colors.white.withOpacity(.94),
                ),
                const SizedBox(height: 3),
                Text(
                  '天气·${effect.label}',
                  style: TextStyle(
                    color: Colors.white.withOpacity(.90),
                    fontSize: 9.2,
                    fontWeight: FontWeight.w700,
                    letterSpacing: .15,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
