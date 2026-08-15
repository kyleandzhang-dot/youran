import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../game_shell.dart';
import 'novel_ending_page.dart';
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
    this.fallbackBackgroundAsset = '',
    this.onBack,
    this.endingBuilder,
    this.disposeController = true,
  });

  final NovelGameController controller;
  final String fallbackBackgroundAsset;
  final VoidCallback? onBack;
  /// 旧版本自定义结局构建器，仅保留接口兼容；当前结局统一使用 NovelEndingPage。
  @Deprecated('结局页面已统一为 NovelEndingPage，此参数不再生效。')
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
  bool _loadFailureHandled = false;
  NovelWeatherEffect? _weatherPreviewOverride;
  NovelTimePeriod? _timePreviewOverride;
  String _lastWeatherSyncToken = '';

  NovelGameController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    controller.addListener(_onControllerChanged);
    unawaited(_initializeGame());
  }

  Future<void> _initializeGame() async {
    await controller.initialize();
    if (!mounted) return;

    // 初始化失败时由页面自动打开菜单，不再继续预加载剧情音频。
    if (!controller.isInitialized) return;

    // 进入剧情后先把短打字音效送进原生播放器，避免第一段流式文字到来时
    // Android / iOS 才临时 setAsset，导致初始化和高频 tick 撞在一起而听不到声音。
    await controller.bgm.preloadTypingSfx();
    if (!mounted) return;

    await controller.bgm.preloadWeatherAmbient();
    await _syncActiveWeatherAudio(force: true);
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
      unawaited(_syncActiveWeatherAudio(force: true));
    }
  }

  void _onControllerChanged() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _processOverlayRequests();
      unawaited(_syncActiveWeatherAudio());
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
      // 正式剧情结局统一进入独立的 NovelEndingPage。
      // endingBuilder 仅保留为旧调用兼容，不再参与实际结局 UI 选择。
      await showNovelEndingPage(context, controller);
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


  NovelWeatherEffect get _backendWeatherEffect =>
      novelWeatherEffectFromKey(controller.world.weather);

  NovelTimePeriod get _backendTimePeriod =>
      novelTimePeriodFromKey(controller.effectiveWorldTimePeriodKey);

  NovelWeatherEffect get _activeWeatherEffect =>
      _weatherPreviewOverride ?? _backendWeatherEffect;

  NovelTimePeriod get _activeTimePeriod =>
      _timePreviewOverride ?? _backendTimePeriod;

  String _weatherAudioKey(NovelWeatherEffect effect) {
    return switch (effect) {
      NovelWeatherEffect.rain || NovelWeatherEffect.heavyRain => 'rain',
      NovelWeatherEffect.snow || NovelWeatherEffect.blizzard => 'snow',
      NovelWeatherEffect.thunderstorm => 'thunderstorm',
      _ => 'none',
    };
  }

  Future<void> _syncActiveWeatherAudio({bool force = false}) async {
    if (!controller.isInitialized) return;
    final effect = _activeWeatherEffect;
    final key = _weatherAudioKey(effect);
    final enabled = _weatherPreviewOverride != null ||
        controller.settings.weatherEffectsEnabled;
    final token = '$key:$enabled:${_weatherPreviewOverride == null ? 'auto' : 'preview'}';
    if (!force && token == _lastWeatherSyncToken) return;
    _lastWeatherSyncToken = token;
    await controller.bgm.setWeatherAmbient(
      key,
      effectsEnabled: enabled,
      force: true,
    );
  }

  Future<void> _cycleWeatherPreview() async {
    final next = switch (_weatherPreviewOverride) {
      null => NovelWeatherEffect.none,
      NovelWeatherEffect.none => NovelWeatherEffect.cloudy,
      NovelWeatherEffect.cloudy => NovelWeatherEffect.rain,
      NovelWeatherEffect.rain => NovelWeatherEffect.heavyRain,
      NovelWeatherEffect.heavyRain => NovelWeatherEffect.thunderstorm,
      NovelWeatherEffect.thunderstorm => NovelWeatherEffect.snow,
      NovelWeatherEffect.snow => NovelWeatherEffect.blizzard,
      NovelWeatherEffect.blizzard => null,
    };
    if (mounted) setState(() => _weatherPreviewOverride = next);
    _lastWeatherSyncToken = '';
    await _syncActiveWeatherAudio(force: true);
  }

  void _cycleTimePreview() {
    final next = switch (_timePreviewOverride) {
      null => NovelTimePeriod.morning,
      NovelTimePeriod.morning => NovelTimePeriod.noon,
      NovelTimePeriod.noon => NovelTimePeriod.afternoon,
      NovelTimePeriod.afternoon => NovelTimePeriod.evening,
      NovelTimePeriod.evening => NovelTimePeriod.night,
      NovelTimePeriod.night => NovelTimePeriod.midnight,
      NovelTimePeriod.midnight => null,
    };
    if (mounted) setState(() => _timePreviewOverride = next);
  }


  NovelDeveloperPreviewActions get _developerPreviewActions =>
      NovelDeveloperPreviewActions(
        weatherOverride: () => _weatherPreviewOverride,
        timeOverride: () => _timePreviewOverride,
        setWeatherOverride: _setWeatherPreviewOverride,
        setTimeOverride: _setTimePreviewOverride,
        previewCharacterSetup: _previewCharacterSetup,
        previewOpening: _previewOpening,
        previewLoading: _previewLoading,
        previewFailure: _previewFailure,
        previewFateRevert: _previewFateRevert,
        previewBalance: _previewBalance,
        previewDice: _previewDice,
        previewTimeSkip: _previewTimeSkip,
        previewEndingIntro: _previewEndingIntro,
        previewEnding: _previewEnding,
      );

  Future<void> _setWeatherPreviewOverride(NovelWeatherEffect? effect) async {
    if (!mounted) return;
    setState(() => _weatherPreviewOverride = effect);
    _lastWeatherSyncToken = '';
    await _syncActiveWeatherAudio(force: true);
  }

  void _setTimePreviewOverride(NovelTimePeriod? period) {
    if (!mounted) return;
    setState(() => _timePreviewOverride = period);
  }

  Future<void> _previewCharacterSetup() async {
    if (!mounted) return;
    await showNovelCharacterSetupDialog(
      context,
      controller,
      previewOnly: true,
    );
  }

  Future<void> _previewOpening() async {
    if (!mounted) return;
    await showNovelOpeningDialog(
      context,
      controller,
      previewOnly: true,
    );
  }

  Future<void> _previewLoading() async {
    if (!mounted) return;
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: '关闭载入预览',
      barrierColor: Colors.black,
      transitionDuration: const Duration(milliseconds: 160),
      pageBuilder: (dialogContext, _, __) {
        return Material(
          color: Colors.transparent,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(dialogContext).pop(),
            child: ColoredBox(
              color: Colors.black.withOpacity(.58),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    CircularProgressIndicator(color: NovelPalette.accent),
                    SizedBox(height: 18),
                    Text(
                      '正在载入世界…',
                      style: TextStyle(
                        color: NovelPalette.text,
                        letterSpacing: 2,
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
  }

  Future<void> _previewFailure() async {
    if (!mounted) return;
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '关闭失败预览',
      barrierColor: Colors.black.withOpacity(.82),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (dialogContext, _, __) {
        return Material(
          color: Colors.transparent,
          child: _FatalError(
            message: '开发者预览：模拟场景详情或历史记录请求失败。',
            onRetry: () async => Navigator.of(dialogContext).pop(),
            onBack: () => Navigator.of(dialogContext).pop(),
          ),
        );
      },
    );
  }

  Future<void> _previewFateRevert() async {
    if (!mounted) return;
    await showNovelFateRevertDialog(
      context,
      controller,
      previewOnly: true,
      previewData: const FateRevertData(
        deathCount: 2,
        scoreDeduct: 10,
        totalScore: 90,
        message: '你的意识在黑暗中重新聚拢，命运允许你回到仍可改变的转折点。',
        deathSceneContent: '雨声淹没了最后一句话。',
      ),
    );
  }

  Future<void> _previewBalance() async {
    if (!mounted) return;
    controller.insufficientBalance = true;
    controller.clearMessages();
  }

  Future<void> _previewDice() async {
    if (!mounted) return;
    const previewRoll = NovelDiceRoll(
      roll: 18,
      dc: 15,
      skill: '洞察',
      grade: 'success',
      label: '成功',
      effect: 'success',
      narration: '你捕捉到了对方神情里一闪而过的迟疑。',
    );
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: '关闭判定预览',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 120),
      pageBuilder: (dialogContext, _, __) {
        return Material(
          color: Colors.transparent,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(dialogContext).pop(),
            child: const NovelDiceOverlay(roll: previewRoll),
          ),
        );
      },
    );
  }

  Future<void> _previewTimeSkip() async {
    if (!mounted) return;
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: '关闭时间跳转预览',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 160),
      pageBuilder: (dialogContext, _, __) {
        return Material(
          color: Colors.transparent,
          child: NovelTimeSkipOverlay(
            label: '三日后',
            onDismiss: () => Navigator.of(dialogContext).pop(),
          ),
        );
      },
    );
  }

  Future<void> _previewEndingIntro() async {
    if (!mounted) return;
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: '关闭终章转场预览',
      barrierColor: Colors.black,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (dialogContext, _, __) {
        return Material(
          color: Colors.black,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(dialogContext).pop(),
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
        );
      },
    );
  }

  Future<void> _previewEnding() async {
    if (!mounted) return;
    const previewEnding = NovelEnding(
      title: '风停在黎明之前',
      code: 'ENDING  ·  01',
      text: '漫长的夜终于退去。你回头望向走过的路，那些选择、失去与相逢，都在晨光里有了新的意义。',
      milestones: <String>[
        '第一次并肩走过雨夜',
        '在最危险的时刻选择相信彼此',
        '兑现了最初的约定',
      ],
      triggeredEvents: <String>[
        '隐藏线索被完整揭开',
        '关键角色关系达到最终阶段',
      ],
      affection: 86,
      romance: 72,
    );

    // 开发者预览与正式剧情共用同一个 NovelEndingPage，
    // 仅替换为本地测试结局数据，不触发真实剧情副作用。
    await showNovelEndingPage(
      context,
      controller,
      endingOverride: previewEnding,
    );
  }

  void _handleLoadFailure(VoidCallback openDrawer) {
    if (_loadFailureHandled) return;
    _loadFailureHandled = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      // 普通用户不展示“世界暂时无法载入”等技术失败页。
      // 保留日志方便开发排查，然后直接执行原“打开菜单”动作。
      debugPrint('剧情初始化失败，已自动打开菜单：${controller.lastError}');
      controller.clearMessages();

      final callback = widget.onBack;
      if (callback != null) {
        callback();
      } else {
        openDrawer();
      }
    });
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
      animation: Listenable.merge(<Listenable>[controller, controller.settings]),
      builder: (context, _) {
        // 剧情背景只认后端剧情状态返回的 world.backgroundUrl。
        // 不使用 APP 主页背景，也不让本地 customBackground 覆盖剧情场景。
        final rawBackground = controller.world.backgroundUrl.trim();
        final normalizedBackground = rawBackground.replaceAll('\\', '/').toLowerCase();
        final isHomeBackground =
            normalizedBackground.endsWith('/home_background.jpg') ||
            normalizedBackground.endsWith('home_background.jpg') ||
            normalizedBackground.endsWith('/background_home.png') ||
            normalizedBackground.endsWith('background_home.png');
        final background = isHomeBackground ? '' : rawBackground;
        final activeWeather = _activeWeatherEffect;
        final activeTime = _activeTimePeriod;
        final loadFailed = !controller.isInitializing &&
            !controller.isInitialized &&
            controller.lastError.isNotEmpty;

        if (controller.isInitialized) {
          _loadFailureHandled = false;
        } else if (loadFailed) {
          _handleLoadFailure(openDrawer);
        }

        return Scaffold(
          resizeToAvoidBottomInset: true,
          backgroundColor: controller.settings.backgroundColor,
          body: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              RepaintBoundary(
                child: NovelWorldBackground(
                  url: background,
                  fallbackAsset: '', // 强制禁用主页背景兜底
                  // 背景单独成层：流式文字/爱心动画更新时尽量复用已栅格化背景。
                  characterPresent: controller.storyStarted &&
                      controller.currentSpeakerName.isNotEmpty &&
                      !controller.isCinematic,
                  isGenerating: controller.isGenerating,
                  weatherEffect: _weatherPreviewOverride != null
                      ? activeWeather
                      : (controller.settings.weatherEffectsEnabled
                          ? activeWeather
                          : NovelWeatherEffect.none),
                  timePeriod: activeTime,
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
                              controller: controller,
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
                            onOpenSettings: () => showNovelSettingsSheet(
                              context,
                              controller,
                              developerPreview: _developerPreviewActions,
                            ),
                          ),
                        ),
                        if (controller.storyStarted)
                          Positioned(
                            left: 0,
                            top: 56,
                            child: NovelLocationHud(
                              title: controller.locationTitle,
                              subtitle: controller.locationSubtitle,
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
              if (!loadFailed)
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
    required this.isAuto,
    required this.onTap,
  });

  final NovelWeatherEffect effect;
  final bool isAuto;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _NovelPreviewButton(
      tooltip: '天气预览：自动 / 晴 / 阴 / 小雨 / 大雨 / 雷暴雨 / 雪 / 暴雪',
      icon: isAuto ? Icons.sync_rounded : effect.icon,
      label: isAuto ? '天气·自动' : '天气·${effect.label}',
      onTap: onTap,
    );
  }
}

class _NovelTimeTestButton extends StatelessWidget {
  const _NovelTimeTestButton({
    required this.period,
    required this.isAuto,
    required this.onTap,
  });

  final NovelTimePeriod period;
  final bool isAuto;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _NovelPreviewButton(
      tooltip: '时间预览：自动 / 早晨 / 中午 / 下午 / 傍晚 / 夜晚 / 深夜',
      icon: isAuto ? Icons.schedule_rounded : period.icon,
      label: isAuto ? '时间·自动' : '时间·${period.label}',
      onTap: onTap,
    );
  }
}

class _NovelPreviewButton extends StatelessWidget {
  const _NovelPreviewButton({
    required this.tooltip,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            constraints: const BoxConstraints(minWidth: 52),
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
                Icon(icon, size: 17, color: Colors.white.withOpacity(.94)),
                const SizedBox(height: 3),
                Text(
                  label,
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

