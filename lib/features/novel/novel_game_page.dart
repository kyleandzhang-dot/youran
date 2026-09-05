import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../game_shell.dart';
import 'novel_ending_page.dart';
import 'novel_backend.dart';
import 'novel_game_controller.dart';
import 'http_novel_backend.dart';
import 'novel_models.dart';
import 'novel_sheets.dart';
import 'novel_widgets.dart';
import 'novel_battle_page.dart';

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

enum _NovelPrimaryTab {
  story,
  characters,
  team,
  inventory,
  journey,
  world,
  surroundings,
}

class _NovelGamePageState extends State<NovelGamePage>
    with WidgetsBindingObserver {
  static const Duration _sceneArrivalDuration =
      Duration(milliseconds: 2800);
  // 世界地图已有右侧独立入口，主页左上角旧地图 / 地点面板先隐藏。
  static const bool _showLegacyLocationHud = true;

  final TextEditingController _inputController = TextEditingController();
  final FocusNode _inputFocusNode = FocusNode();

  _NovelPrimaryTab _primaryTab = _NovelPrimaryTab.story;
  final Set<_NovelPrimaryTab> _mountedPrimaryTabs = <_NovelPrimaryTab>{
    _NovelPrimaryTab.story,
  };
  String _characterFocusKey = '';
  int _characterFocusRequestId = 0;

  bool _characterSetupOpen = false;
  bool _openingOpen = false;
  bool _fateOpen = false;
  bool _endingOpen = false;
  bool _balanceOpen = false;
  bool _battleOpen = false;
  bool _loadFailureHandled = false;
  NovelWeatherEffect? _weatherPreviewOverride;
  String? _backgroundPreviewOverride;
  NovelTimePeriod? _timePreviewOverride;
  String _lastWeatherSyncToken = '';
  Timer? _sceneArrivalTimer;
  String _lastSceneArrivalToken = '';
  bool _sceneArrivalActive = false;
  String? _sceneArrivalPreviewTitle;
  String? _sceneArrivalPreviewSubtitle;
  int _sceneArrivalRunId = 0;

  NovelGameController get controller => widget.controller;

  // 角色输入/创建阶段进入沉浸输入模式，减少同时显示的信息。
  bool get _immersiveInputMode => _characterSetupOpen;

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

    _syncSceneArrival();

    // 初始化失败时由页面自动打开菜单，不再继续预加载剧情音频。
    if (!controller.isInitialized) return;

    // 进入剧情后先生成并预热内存打字音，避免第一段流式文字到来时
    // Android / iOS 才初始化播放器池而丢失前几个 tick。
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
      // 恢复前台时不能只重连 WebSocket；后台期间可能错过任意推送。
      // 统一通过 HTTP 重读剧情、目标、场景、调查资格和背包权威状态。
      unawaited(controller.recoverAfterResume());
      unawaited(controller.bgm.init(
        controller.bgm.currentIntensity,
        controller.bgm.currentSceneMode,
      ));
      unawaited(_syncActiveWeatherAudio(force: true));
    }
  }

  void _onControllerChanged() {
    if (!mounted) return;
    _syncSceneArrival();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _processOverlayRequests();
      unawaited(_syncActiveWeatherAudio());
    });
  }

  void _syncSceneArrival() {
    final title = controller.locationTitle.trim();
    final subtitle = controller.locationSubtitle.trim();

    // 回看历史时不重复播放场景揭示；只有抵达最新剧情中的新地点才触发。
    if (!controller.storyStarted || title.isEmpty || controller.hasNext) return;

    final token = '$title\u0000$subtitle';
    if (token == _lastSceneArrivalToken) return;
    _lastSceneArrivalToken = token;

    _startSceneArrival();
  }

  void _startSceneArrival({
    String? previewTitle,
    String? previewSubtitle,
  }) {
    _sceneArrivalTimer?.cancel();
    setState(() {
      _sceneArrivalActive = true;
      _sceneArrivalPreviewTitle = previewTitle;
      _sceneArrivalPreviewSubtitle = previewSubtitle;
      _sceneArrivalRunId++;
    });
    _sceneArrivalTimer = Timer(_sceneArrivalDuration, () {
      if (!mounted) return;
      setState(() {
        _sceneArrivalActive = false;
        _sceneArrivalPreviewTitle = null;
        _sceneArrivalPreviewSubtitle = null;
      });
    });
  }

  Future<void> _openSceneMap() async {
    _inputFocusNode.unfocus();
    await showNovelSceneMapSheet(context, controller);
  }

  Future<void> _processOverlayRequests() async {
    // 角色确认弹窗尚未完全退出时，禁止再 push 开场/其他覆盖层。
    // submitCharacterSetup() 成功后会 notify，并把 showOpening 设为 true；
    // 如果这里不拦截，就会出现两个 Dialog 同时操作 Navigator 的 assertion。
    if (_characterSetupOpen) return;

    if (controller.showCharacterSetup) {
      _characterSetupOpen = true;
      final started = await showNovelCharacterSetupDialog(context, controller);
      _characterSetupOpen = false;
      if (!mounted) return;

      if (started) {
        // 等角色弹窗的 reverse transition 完成，再打开开场。
        await Future<void>.delayed(const Duration(milliseconds: 90));
        if (mounted) {
          await _processOverlayRequests();
        }
      } else {
        // 首次角色尚未确认时，当前游戏页本身没有可继续展示的剧情。
        // 关闭确认框就等于放弃本次进入：回到空 Shell，并自动展开世界列表。
        // 这样不会留下白屏；玩家再次点击同一世界时也会重新走 setActiveScenario，
        // 从而重新获得 session 并再次出现角色确认框。
        await _returnToWorldMenuAfterCharacterSetupDismissed();
      }
      return;
    }
    if (controller.showOpening && !_openingOpen) {
      _openingOpen = true;
      final openMenuRequested =
          await showNovelOpeningDialog(context, controller);
      _openingOpen = false;
      if (!mounted) return;

      if (openMenuRequested) {
        // 与首次“确认角色”返回保持同一行为：不留在空剧情页，
        // 直接回到世界 Shell 并自动展开左侧菜单。
        await _returnToWorldMenuAfterCharacterSetupDismissed();
      }
      return;
    }
    if (!_battleOpen) {
      final pendingBattleStart = controller.consumePendingBattleStart();
      if (pendingBattleStart != null) {
        _battleOpen = true;
        await _openPendingStoryBattle(pendingBattleStart);
        _battleOpen = false;
        return;
      }

      // 旧流程兼容：如果某处已经直接塞入完整 battle payload，仍照常进入。
      final battlePayload = controller.consumePendingBattle();
      if (battlePayload != null) {
        _battleOpen = true;
        await _openStoryBattle(battlePayload);
        _battleOpen = false;
        return;
      }
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

  Future<void> _returnToWorldMenuAfterCharacterSetupDismissed() async {
    // showGeneralDialog 返回时反向动画可能还在收尾，稍等一帧再替换根路由，
    // 避免 Dialog 与页面路由同时操作 Navigator。
    await Future<void>.delayed(const Duration(milliseconds: 100));
    if (!mounted) return;

    Navigator.of(context, rootNavigator: true).pushReplacement<void, void>(
      MaterialPageRoute<void>(
        builder: (_) => const GameShellPage(autoOpenDrawer: true),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller.removeListener(_onControllerChanged);
    _sceneArrivalTimer?.cancel();
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
        previewSceneArrival: _previewSceneArrival,
        previewStoryBrewing: _previewStoryBrewing,
        previewLoading: _previewLoading,
        previewFailure: _previewFailure,
        previewFateRevert: _previewFateRevert,
        previewBalance: _previewBalance,
        previewDice: _previewDice,
        previewChoices: _previewChoices,
        previewSurroundings: _previewSurroundings,
        previewWorldMap: _previewWorldMap,
        previewBattle: _previewBattle,
        previewTimeSkip: _previewTimeSkip,
        previewEndingIntro: _previewEndingIntro,
        previewEnding: _previewEnding,
        previewImageTransition: _previewImageTransition,
        previewAffectionUp: () async => controller.previewDeveloperFeedback('affection_up'),
        previewAffectionDown: () async => controller.previewDeveloperFeedback('affection_down'),
        previewItemObtained: () async => controller.previewDeveloperFeedback('item_obtained'),
        previewScoreGain: () async => controller.previewDeveloperFeedback('score_gain'),
        previewGoalRefresh: () async => controller.previewDeveloperFeedback('goal_refresh'),
        previewGoalSuccess: () async => controller.previewDeveloperFeedback('goal_completed'),
        previewGoalFailure: () async => controller.previewDeveloperFeedback('goal_failed'),
        previewDamageLight: () async => controller.previewDeveloperFeedback('damage_light'),
        previewDamage: () async => controller.previewDeveloperFeedback('damage'),
        previewDamageCritical: () async => controller.previewDeveloperFeedback('damage_critical'),
        previewRecovery: () async => controller.previewDeveloperFeedback('recovery'),
        previewRisk: () async => controller.previewDeveloperFeedback('risk'),
        previewNarrationStyles: _previewNarrationStyles,
        recognizeAndAcquireContent:
            controller.recognizeAndAcquireDeveloperContent,
        testGeneratedOpponent: _previewGeneratedOpponent,
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

  Future<void> _previewSceneArrival() async {
    if (!mounted) return;
    _startSceneArrival(
      previewTitle: '雾隐长街',
      previewSubtitle: '夜雨 · 南城旧区',
    );
  }

  Future<void> _previewStoryBrewing() async {
    if (!mounted) return;
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '关闭故事加载预览',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 120),
      pageBuilder: (dialogContext, _, __) {
        return Material(
          color: Colors.transparent,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(dialogContext).pop(),
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                const NovelBrewingOverlay(),
                SafeArea(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 18),
                      child: Text(
                        '轻触任意位置结束预览',
                        style: TextStyle(
                          color: NovelPalette.text.withOpacity(.46),
                          fontSize: 10.5,
                          letterSpacing: .8,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
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
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xB3FFFFFF),
                      ),
                    ),
                    SizedBox(height: 14),
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

  Future<void> _previewChoices() async {
    if (!mounted) return;
    const previewChoices = <NovelChoice>[
      NovelChoice(
        text: '询问她究竟发生了什么',
        type: 'dialogue',
      ),
      NovelChoice(
        text: '冒险穿过正在坍塌的回廊',
        type: 'action',
        dice: true,
      ),
      NovelChoice(
        text: '迎战挡在前方的对手',
        type: 'battle',
      ),
    ];

    // 开发者预览直接复用剧情页真正的选择组件。
    // 不再经过 showNovelChoicesSheet / _ActionTile 那套独立 Sheet UI，
    // 因此真实选择框今后的边框、磨砂、字号、间距等改动会自动同步到这里。
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '关闭选择框预览',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 120),
      pageBuilder: (dialogContext, _, __) {
        final media = MediaQuery.of(dialogContext);
        final compact = media.size.width <= 600;
        final footerBaseHeight = compact ? 52.0 : 54.0;
        final footerOuterGap = compact ? 4.0 : 6.0;
        final choiceBottomGap = compact ? 4.0 : 5.0;
        final bottom = media.viewPadding.bottom +
            footerBaseHeight +
            footerOuterGap +
            choiceBottomGap;

        return Material(
          color: Colors.transparent,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(dialogContext).pop(),
                child: const SizedBox.expand(),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: bottom,
                child: NovelChoiceDock(
                  choices: previewChoices,
                  // 预览只展示真实组件与按压反馈，不触发任何剧情。
                  onSelected: (_) {},
                ),
              ),
            ],
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(opacity: animation, child: child);
      },
    );
  }

  Future<void> _previewSurroundings() async {
    if (!mounted) return;
    await showNovelSurroundingsDeveloperPreview(
      context,
      controller,
      previewBattleLauncher: _openDeveloperSurroundingsBattle,
    );
  }

  Future<void> _previewWorldMap() async {
    if (!mounted) return;
    await showNovelSceneMapDeveloperPreview(context, controller);
  }

  List<YoranBattleSkill> _currentPreviewBattleSkills() {
    final rawSkills = controller.protagonist?.status['skills'];
    final learnedSkills = <YoranBattleSkill>[];
    final seenSkillNames = <String>{'普通攻击'};
    if (rawSkills is List) {
      for (final raw in rawSkills) {
        final skill = YoranBattleSkill.fromState(raw);
        if (skill == null) continue;
        final key = skill.name.replaceAll(RegExp(r'\s+'), '').toLowerCase();
        if (key.isNotEmpty && seenSkillNames.add(key)) {
          learnedSkills.add(skill);
        }
      }
    }
    return learnedSkills.isEmpty
        ? yoranDefaultBattleSkills
        : <YoranBattleSkill>[
            yoranDefaultBattleSkills.first,
            ...learnedSkills,
          ];
  }

  List<YoranBattleCompanion> _currentBattleCompanions() {
    final result = <YoranBattleCompanion>[];
    final seen = <String>{};
    for (final raw in controller.novelCharacterRoster.values) {
      if (!boolValue(raw['deployed'])) continue;
      final companion = YoranBattleCompanion.fromState(raw);
      if (companion == null ||
          companion.skills.isEmpty ||
          !seen.add(companion.id)) {
        continue;
      }
      result.add(companion);
      if (result.length >= 3) break;
    }
    return result;
  }

  YoranGeneratedBattleSetup _withLocalCompanionFallback(
    YoranGeneratedBattleSetup setup,
  ) {
    if (setup.companions.isNotEmpty) return setup;
    final companions = _currentBattleCompanions();
    if (companions.isEmpty) return setup;
    return YoranGeneratedBattleSetup(
      playerName: setup.playerName,
      playerAvatar: setup.playerAvatar,
      playerPortrait: setup.playerPortrait,
      playerSkills: setup.playerSkills,
      companions: companions,
      playerItems: setup.playerItems,
      playerEquipment: setup.playerEquipment,
      enemy: setup.enemy,
      difficultyLabel: setup.difficultyLabel,
      openingEstimate: setup.openingEstimate,
    );
  }

  YoranBattleEnemy _developerSurroundingsEnemy({
    required String name,
    required int quality,
    required bool elite,
    required List<dynamic> equipment,
  }) {
    final normalizedQuality = quality.clamp(1, 6).toInt();
    final equipped = equipment
        .map(YoranBattleEquipment.fromState)
        .whereType<YoranBattleEquipment>()
        .toList(growable: false);

    int slotQuality(String slot) {
      var value = 0;
      for (final item in equipped) {
        if (item.slot == slot) value = math.max(value, item.quality);
      }
      return value.clamp(0, 10).toInt();
    }

    int affixTotal(String key, int cap) {
      var value = 0;
      for (final item in equipped) {
        value += item.affixes[key] ?? 0;
      }
      return value.clamp(0, cap).toInt();
    }

    final upper = slotQuality('upper');
    final face = slotQuality('face');
    final handheld = slotQuality('handheld');
    final lower = slotQuality('lower');
    final playerMaxHp = (100 *
            (1 + upper * .10 +
                affixTotal('max_hp_percent', 40) / 100))
        .round();
    final playerMaxEnergy = (100 *
            (1 + face * .10 +
                affixTotal('max_energy_percent', 40) / 100))
        .round();
    final attackMultiplier = 1 +
        handheld * .10 +
        affixTotal('attack_percent', 40) / 100;
    final incomingMultiplier = (1 -
            lower * .05 -
            affixTotal('defense_percent', 15) / 100)
        .clamp(.35, 1.0)
        .toDouble();

    final ratio = switch (normalizedQuality) {
      1 => .50,
      2 => .70,
      3 => 1.00,
      4 => 1.50,
      5 => 2.00,
      _ => 3.00,
    };
    // 与后端探索规则一致：70%来自品质基准，30%参考玩家当前装备。
    final playerScaledAttack =
        ratio * attackMultiplier / math.max(.5, incomingMultiplier);
    final attackRatio = ratio * .70 + playerScaledAttack * .30;
    final maxHp = (100 * ratio * .70 + playerMaxHp * ratio * .30)
        .round()
        .clamp(12, 1000)
        .toInt();
    final basicMin = (5 * attackRatio).round().clamp(1, 25).toInt();
    final basicMax = math
        .max(basicMin, (8 * attackRatio).round())
        .clamp(1, 25)
        .toInt();
    final difficulty = switch (normalizedQuality) {
      1 => ('轻松', '约为玩家当前战力的50%'),
      2 => ('略弱', '约为玩家当前战力的70%'),
      3 => ('均衡', '约为玩家当前战力的100%'),
      4 => ('危险', '约为玩家当前战力的150%'),
      5 => ('高危', '约为玩家当前战力的200%'),
      _ => ('极危', '约为玩家当前战力的300%'),
    };

    return YoranBattleEnemy(
      name: name.trim().isEmpty ? '测试敌人' : name.trim(),
      maxHp: maxHp,
      currentEnergy: (playerMaxEnergy * ratio)
          .round()
          .clamp(20, 100)
          .toInt(),
      condition: elite ? '高度警戒' : '警戒',
      realm: '探索品质 $normalizedQuality',
      difficultyLabel: difficulty.$1,
      openingEstimate: difficulty.$2,
      basicAttackMin: basicMin,
      basicAttackMax: basicMax,
      hitBonus: (4 + normalizedQuality ~/ 2 + (elite ? 1 : 0))
          .clamp(2, 10)
          .toInt(),
      allowInstantDefeat: normalizedQuality >= 6,
      // 开发者探索只测试品质数值，不为 NPC 请求或生成专属技能。
      skills: const <YoranBattleSkill>[],
    );
  }

  Future<String?> _openDeveloperSurroundingsBattle({
    required String enemyName,
    required int quality,
    required bool elite,
  }) async {
    if (!mounted) return null;
    FocusManager.instance.primaryFocus?.unfocus();

    final protagonist = controller.protagonist;
    final inventory = _battleInventorySnapshot();
    final enemy = _developerSurroundingsEnemy(
      name: enemyName,
      quality: quality,
      elite: elite,
      equipment: inventory,
    );
    final outcome = await showYoranBattlePage(
      context,
      playerName: protagonist?.name.trim().isNotEmpty == true
          ? protagonist!.name.trim()
          : controller.protagonistName,
      playerAvatar: protagonist?.avatarUrl.trim() ?? '',
      playerPortrait: protagonist?.portraitUrl.trim() ?? '',
      skills: _currentPreviewBattleSkills(),
      companions: _currentBattleCompanions(),
      items: inventory,
      equipment: inventory,
      enemyName: enemy.name,
      enemies: <YoranBattleEnemy>[enemy],
      sceneBackground: controller.world.backgroundUrl.trim(),
      sceneTitle: '探索测试 · 海滩边缘',
      sceneSubtitle:
          '${elite ? '高级敌人' : '普通敌人'} · 品质 ${quality.clamp(1, 6)}',
      socketService: controller.socket,
      // 开发者探索不传结算回调：不扣真实道具，也不写入正式战斗状态。
    );
    return outcome?.name;
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

  Future<void> _previewGeneratedOpponent(
    String opponentName,
    String description,
  ) async {
    if (!mounted) return;
    FocusManager.instance.primaryFocus?.unfocus();

    final backend = controller.backend;
    if (backend is! HttpNovelBackend) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('当前后端不支持开发者对手生成接口')),
        );
      return;
    }

    final localPlayer = controller.protagonist;
    final localAvatar = localPlayer?.avatarUrl.trim() ?? '';
    final localPortrait = localPlayer?.portraitUrl.trim() ?? '';
    final localPlayerName = localPlayer?.name.trim().isNotEmpty == true
        ? localPlayer!.name.trim()
        : controller.protagonistName;

    try {
      await controller.refreshNovelCharacterRoster(notify: false);
    } catch (_) {
      // 测试入口允许使用当前缓存；接口响应仍是队伍数据的第一优先级。
    }
    if (!mounted) return;

    await showYoranGeneratedBattlePage(
      context,
      playerName: localPlayerName,
      playerAvatar: localAvatar,
      playerPortrait: localPortrait,
      enemyName: opponentName,
      sceneBackground: controller.world.backgroundUrl.trim(),
      sceneTitle: controller.locationTitle,
      sceneSubtitle: controller.locationSubtitle.trim(),
      socketService: controller.socket,
      setupLoader: () async {
        try {
          final response = await backend.createDeveloperBattleOpponent(
            sessionId: controller.sessionId,
            name: opponentName,
            description: description,
          );
          return _withLocalCompanionFallback(
            YoranGeneratedBattleSetup.fromJson(response),
          );
        } on NovelBackendException catch (error) {
          throw Exception(error.message);
        } on FormatException catch (error) {
          throw Exception(error.message.toString());
        }
      },
      onSettleItems: (consumptions, outcome) async {
        return backend.settleBattleItems(
          sessionId: controller.sessionId,
          consumptions: consumptions
              .map((item) => item.toJson())
              .toList(growable: false),
          outcome: outcome.name,
        );
      },
    );
  }


  Future<void> _openPendingStoryBattle(
    NovelPendingBattleStart request,
  ) async {
    if (!mounted) return;
    FocusManager.instance.primaryFocus?.unfocus();

    final localPlayer = controller.protagonist;
    final localAvatar = localPlayer?.avatarUrl.trim() ?? '';
    final localPortrait = localPlayer?.portraitUrl.trim() ?? '';
    final localPlayerName = localPlayer?.name.trim().isNotEmpty == true
        ? localPlayer!.name.trim()
        : controller.protagonistName;

    var battleId = '';
    var targetName = request.targetName.trim();
    var battleMode = request.battleMode.trim().isEmpty
        ? 'hostile'
        : request.battleMode.trim().toLowerCase();

    final outcome = await showYoranGeneratedBattlePage(
      context,
      playerName: localPlayerName,
      playerAvatar: localAvatar,
      playerPortrait: localPortrait,
      enemyName: targetName,
      sceneBackground: controller.world.backgroundUrl.trim(),
      sceneTitle: controller.locationTitle,
      sceneSubtitle: controller.locationSubtitle.trim(),
      socketService: controller.socket,
      setupLoader: () async {
        try {
          final response = await request.loadPayload();
          final setup = YoranGeneratedBattleSetup.fromJson(response);

          battleId = stringValue(response['battle_id']).trim();
          if (battleId.isEmpty) {
            throw const FormatException('后端没有返回有效的 battle_id');
          }

          final target = asJsonMap(response['target']);
          final design = asJsonMap(response['battle_opponent']);
          final resolvedTargetName =
              stringValue(target['name'], setup.enemy.name).trim();
          if (resolvedTargetName.isNotEmpty) {
            targetName = resolvedTargetName;
          }
          battleMode = stringValue(
            design['battle_mode'],
            battleMode,
          ).trim().toLowerCase();

          return setup;
        } on NovelBackendException catch (error) {
          throw Exception(error.message);
        } on FormatException catch (error) {
          throw Exception(error.message.toString());
        }
      },
      onSettleItems: (consumptions, result) {
        return controller.settleStoryBattle(
          battleId: battleId,
          outcome: result.name,
          consumptions: consumptions
              .map((item) => item.toJson())
              .toList(growable: false),
        );
      },
    );

    if (!mounted) return;
    if (outcome == null) {
      // 用户在生成失败/加载阶段主动返回，不消费原战斗选项。
      controller.abandonBattleStart(request.optionId);
      return;
    }

    if (request.fromSurroundings) {
      // 探索遭遇只刷新背包与调查图，不让剧情 LLM 再复述/重判同一场战斗。
      await controller.finishSurroundingsBattle();
      return;
    }

    await controller.continueAfterStoryBattle(
      targetName: targetName,
      battleMode: battleMode,
      outcome: outcome.name,
    );
  }

  Future<void> _openStoryBattle(JsonMap response) async {
    if (!mounted) return;
    FocusManager.instance.primaryFocus?.unfocus();
    try {
      final setup = YoranGeneratedBattleSetup.fromJson(response);
      final battleId = stringValue(response['battle_id']).trim();
      final target = asJsonMap(response['target']);
      final design = asJsonMap(response['battle_opponent']);
      final targetName = stringValue(target['name'], setup.enemy.name).trim();
      final battleMode = stringValue(design['battle_mode'], 'hostile')
          .trim()
          .toLowerCase();
      if (battleId.isEmpty) {
        throw const FormatException('后端没有返回有效的 battle_id');
      }

      final localPlayer = controller.protagonist;
      final localAvatar = localPlayer?.avatarUrl.trim() ?? '';
      final localPortrait = localPlayer?.portraitUrl.trim() ?? '';
      final subtitleParts = <String>[
        if (controller.locationSubtitle.trim().isNotEmpty)
          controller.locationSubtitle.trim(),
        if (setup.difficultyLabel.trim().isNotEmpty)
          setup.difficultyLabel.trim(),
      ];
      final outcome = await showYoranBattlePage(
        context,
        playerName: setup.playerName,
        playerAvatar: setup.playerAvatar.trim().isNotEmpty
            ? setup.playerAvatar.trim()
            : localAvatar,
        playerPortrait: setup.playerPortrait.trim().isNotEmpty
            ? setup.playerPortrait.trim()
            : localPortrait,
        skills: setup.playerSkills,
        companions: setup.companions,
        items: setup.playerItems,
        equipment: setup.playerEquipment,
        onSettleItems: (consumptions, result) {
          return controller.settleStoryBattle(
            battleId: battleId,
            outcome: result.name,
            consumptions: consumptions
                .map((item) => item.toJson())
                .toList(growable: false),
          );
        },
        enemyName: setup.enemy.name,
        enemyPortrait: setup.enemy.portrait,
        enemies: <YoranBattleEnemy>[setup.enemy],
        sceneBackground: controller.world.backgroundUrl.trim(),
        sceneTitle: controller.locationTitle,
        sceneSubtitle: subtitleParts.join(' · '),
        socketService: controller.socket,
      );
      if (!mounted || outcome == null) return;
      await controller.continueAfterStoryBattle(
        targetName: targetName,
        battleMode: battleMode,
        outcome: outcome.name,
      );
    } catch (error) {
      if (!mounted) return;
      final message = error is NovelBackendException
          ? error.message
          : error is FormatException
              ? error.message.toString()
              : '进入战斗失败，请稍后重试。';
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Map<String, dynamic> _battleInventoryState(NovelInventoryItem item) {
    final raw = item.raw.map<String, dynamic>(
      (key, value) => MapEntry<String, dynamic>('$key', value),
    );
    return <String, dynamic>{
      ...raw,
      'id': item.id,
      'name': item.name,
      'type': item.itemType,
      'quantity': item.quantity,
      'description': item.description,
      'equipped': item.isEquipped,
    };
  }

  List<Map<String, dynamic>> _battleInventorySnapshot() {
    final data = controller.inventory;
    final result = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (final item in <NovelInventoryItem>[
      ...data.storyItems,
      ...data.consumables,
    ]) {
      final key = item.id.trim().isNotEmpty
          ? 'id:${item.id.trim()}'
          : '${item.itemType.trim()}:${item.name.trim()}';
      if (seen.add(key)) result.add(_battleInventoryState(item));
    }
    return result;
  }

  Future<void> _previewBattle() async {
    if (!mounted) return;
    FocusManager.instance.primaryFocus?.unfocus();

    // 开战前主动刷新一次角色权威状态，避免刚通过开发者工具加入的技能
    // 仍停留在旧的本地快照中。
    try {
      await Future.wait<void>(<Future<void>>[
        controller.refreshCharacterStatus(notify: false),
        // 角色列表刷新会同时读取协同出战状态、NPC 技能和背包。
        controller.refreshNovelCharacterRoster(notify: false),
      ]);
    } catch (_) {
      // 预览入口允许在离线状态继续打开，下面会使用当前已有快照。
    }
    if (!mounted) return;

    final protagonist = controller.protagonist;
    final battleSkills = _currentPreviewBattleSkills();
    final battleCompanions = _currentBattleCompanions();
    final battleInventory = _battleInventorySnapshot();

    await showYoranBattlePage(
      context,

      // 主角名称、头像、立绘和技能均读取当前角色状态。
      playerName: protagonist?.name.trim().isNotEmpty == true
          ? protagonist!.name.trim()
          : controller.protagonistName,
      playerAvatar: protagonist?.avatarUrl.trim() ?? '',
      playerPortrait: protagonist?.portraitUrl.trim() ?? '',
      skills: battleSkills,
      companions: battleCompanions,
      items: battleInventory,
      equipment: battleInventory,

      // 敌人立绘
      enemyName: '赛诺',
      enemyPortrait: 'assets/images/red_wolf.png',

      // 自动使用当前剧情背景，不要改
      sceneBackground: controller.world.backgroundUrl.trim(),
      sceneTitle: controller.locationTitle,
      sceneSubtitle: controller.locationSubtitle,
      socketService: controller.socket,
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

  Future<void> _previewImageTransition() async {
    if (!mounted) return;
    
    final randomTimestamp = DateTime.now().millisecondsSinceEpoch;
    final testUrl = 'https://picsum.photos/1080/1920?random=$randomTimestamp';

    setState(() {
      _backgroundPreviewOverride = testUrl; 
    });
  }

  Future<void> _previewNarrationStyles() async {
    if (!mounted) return;
    await NovelNarrationStylePreview.show(context);
  }

  void _handleLoadFailure(VoidCallback openDrawer) {
    if (_loadFailureHandled) return;
    _loadFailureHandled = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      // 1. 清空控制器的原本报错信息
      controller.clearMessages();

      // 2. 屏幕下方弹出一个干净友好的提示
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('场景载入异常，已自动为您返回首页'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );

      // 3. 自动返回首页
      final callback = widget.onBack;
      if (callback != null) {
        callback();
      } else {
        openDrawer(); // 展开菜单/返回
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

  void _selectPrimaryTab(_NovelPrimaryTab tab) {
    if (_primaryTab == tab) return;
    FocusManager.instance.primaryFocus?.unfocus();

    // 切离剧情页时先立即掐掉连续打字声；NovelDialogPanel.active 随后会
    // 在同一帧停止逐字 Timer，避免面板盖上后还有一个尾音/下一字符重新续命。
    if (tab != _NovelPrimaryTab.story) {
      unawaited(controller.bgm.stopTypingSound());
    }
    if (tab == _NovelPrimaryTab.surroundings) {
      // 真正点开时才生成；场景到达与入口发光只读取轻量可用性。
      unawaited(controller.loadSurroundings());
    }

    setState(() {
      _primaryTab = tab;
      _mountedPrimaryTabs.add(tab);
    });
  }

  Future<void> _openCurrentSpeakerProfile() async {
    final character = controller.currentSpeakerCharacter;
    if (character == null) return;

    final key = character.id.trim().isNotEmpty
        ? character.id.trim()
        : character.name.trim();
    if (key.isEmpty) return;

    FocusManager.instance.primaryFocus?.unfocus();
    await controller.bgm.stopTypingSound();
    if (!mounted) return;

    if (character.isMain) {
      await showNovelHostProfileSheet(context, controller);
      return;
    }
    await showNovelNpcProfileSheet(context, controller, character);
  }


  Widget _buildPrimaryArchiveTab(_NovelPrimaryTab tab) {
    return switch (tab) {
      _NovelPrimaryTab.characters =>
        NovelCharactersTab(
          controller: controller,
          focusCharacterKey: _characterFocusKey,
          focusRequestId: _characterFocusRequestId,
        ),
      _NovelPrimaryTab.team =>
        NovelTeamTab(controller: controller),
      _NovelPrimaryTab.inventory =>
        NovelInventoryTab(controller: controller),
      _NovelPrimaryTab.journey =>
        NovelJourneyTab(controller: controller),
      _NovelPrimaryTab.world =>                           // 新增这一段
        NovelWorldMapTab(controller: controller),         // 新增这一段
      _NovelPrimaryTab.surroundings =>
        NovelSurroundingsTab(
          controller: controller,
          onClose: () => _selectPrimaryTab(_NovelPrimaryTab.story),
        ),
      _NovelPrimaryTab.story => const SizedBox.shrink(),
    };
  }

  @override
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
            final rawBackground = _backgroundPreviewOverride ?? controller.world.backgroundUrl.trim();
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

            final isCompactWidth = MediaQuery.sizeOf(context).width <= 600;
            final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
            final keyboardActive = isCompactWidth && keyboardInset > 0;
            
            final showBottomNav = !_immersiveInputMode &&
                controller.storyStarted &&
                !controller.isCinematic &&
                !_endingOpen &&
                !_battleOpen &&
                _primaryTab != _NovelPrimaryTab.surroundings &&
                (controller.hasNext || controller.isGenerating) &&
                !keyboardActive;

            return Scaffold(
              resizeToAvoidBottomInset: false,
              backgroundColor: controller.settings.backgroundColor,
              body: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  RepaintBoundary(
                    child: NovelWorldBackground(
                      url: background,
                      fallbackAsset: 'assets/images/background_home.png',
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
                  SafeArea(
                    minimum: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final compact = constraints.maxWidth < 430;
                        final sceneArrivalTitle =
                            _sceneArrivalPreviewTitle ?? controller.locationTitle;
                        final sceneArrivalSubtitle =
                            _sceneArrivalPreviewSubtitle ??
                                controller.locationSubtitle;
                        final rawLocationSubtitle =
                            controller.locationSubtitle.trim();
                        final worldTimeLabel =
                            controller.world.timeDescription.trim();
                        final worldMapHudTitle = rawLocationSubtitle.isNotEmpty &&
                                rawLocationSubtitle != worldTimeLabel
                            ? rawLocationSubtitle.split(' · ').first
                            : controller.locationTitle;
                        final worldMapHudSubtitle =
                            worldMapHudTitle != controller.locationTitle
                                ? '当前位置 · ${controller.locationTitle}'
                                : rawLocationSubtitle;
                        final sceneHudTransitionDuration = _sceneArrivalActive
                            ? const Duration(milliseconds: 180)
                            : const Duration(milliseconds: 620);

                        return Stack(
                          children: <Widget>[
                            if (controller.storyStarted && controller.isCinematic)
                              Positioned.fill(
                                child: NovelCinematicControls(
                                  controller: controller,
                                  text: controller.currentSentence?.readerText ?? '',
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
                                onOpenStore: () =>
                                    showNovelStoreSheet(context, controller),
                                onOpenSettings: () => showNovelSettingsSheet(
                                  context,
                                  controller,
                                  developerPreview: _developerPreviewActions,
                                ),
                              ),
                            ),
                            
                            // 完美左对齐 + 高度紧凑优化：把位置和目标包在一个 Column 里
                            if (!_immersiveInputMode && controller.storyStarted && !keyboardActive)
                              Positioned(
                                left: 0,
                                top: 56, // 统一锁定在顶部起点
                                child: AnimatedSlide(
                                  duration: sceneHudTransitionDuration,
                                  curve: Curves.easeOutCubic,
                                  offset: _sceneArrivalActive
                                      ? const Offset(-.04, 0)
                                      : Offset.zero,
                                  child: AnimatedOpacity(
                                    duration: sceneHudTransitionDuration,
                                    curve: Curves.easeOutCubic,
                                    opacity: _sceneArrivalActive ? 0 : 1,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (_showLegacyLocationHud)
                                          NovelLocationHud(
                                            title: worldMapHudTitle,
                                            subtitle: worldMapHudSubtitle,
                                            loading: false,
                                            onTap: null,
                                          ),
                                        if (_showLegacyLocationHud)
                                          const SizedBox(height: 6), // 舒适又紧凑的间距
                                        NovelGoalHud(
                                          text: controller.currentGoal,
                                          feedbackEvent: controller.hudEvent,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),

                            if (controller.storyStarted &&
                                !keyboardActive &&
                                _sceneArrivalActive)
                              Positioned(
                                left: compact ? 12 : 16,
                                right: compact
                                    ? 50
                                    : constraints.maxWidth * .28,
                                top: 56,
                                child: IgnorePointer(
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: 620,
                                      ),
                                      child: NovelSceneArrivalTitle(
                                        key: ValueKey<int>(_sceneArrivalRunId),
                                        title: sceneArrivalTitle,
                                        subtitle: sceneArrivalSubtitle,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            if (controller.storyStarted && !controller.isCinematic)
                              Align(
                                alignment: Alignment.bottomCenter,
                                child: Padding(
                                  // 剧情区域始终保持左右对称，不为右侧悬浮按钮预留宽度。
                                  padding: EdgeInsets.zero,
                                  child: ConstrainedBox(
                                    constraints:
                                        const BoxConstraints(maxWidth: 720),
                                    child: NovelChoiceDockActionScope(
                                      visible: controller.shouldShowSurroundingsAction,
                                      label: controller.surroundingsActionLabel,
                                      attention: controller.surroundingsNeedsAttention,
                                      loading: controller.isSurroundingsLoading,
                                      onTap: () => _selectPrimaryTab(
                                        _NovelPrimaryTab.surroundings,
                                      ),
                                      child: NovelDialogPanel(
                                      controller: controller,
                                      active: _primaryTab == _NovelPrimaryTab.story,
                                      textController: _inputController,
                                      focusNode: _inputFocusNode,
                                      onSend: (text) {
                                        controller.goLatest();
                                        unawaited(controller.sendPlayerMessage(text));
                                      },
                                      onContinue: controller.continueStory,
                                      onForceContinue: controller.forceContinue,
                                      onOpenChoices: () =>
                                          showNovelChoicesSheet(context, controller),
                                      onOpenInventory: () => _selectPrimaryTab(
                                        _NovelPrimaryTab.inventory,
                                      ),
                                      onOpenCharacters: () => _selectPrimaryTab(
                                        _NovelPrimaryTab.characters,
                                      ),
                                      onOpenJourney: () => _selectPrimaryTab(
                                        _NovelPrimaryTab.journey,
                                      ),
                                      onRevert: () =>
                                          showNovelRevertDialog(context, controller),
                                      onOpenPortrait:
                                          controller.currentSpeakerCharacter == null
                                              ? null
                                              : _openCurrentSpeakerProfile,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ),

                  if (_primaryTab == _NovelPrimaryTab.story &&
                      controller.storyStarted &&
                      !controller.isCinematic)
                    Positioned.fill(
                      child: RepaintBoundary(
                        child: NovelDamageFeedbackOverlay(
                          hp: controller.protagonistHp,
                        ),
                      ),
                    ),

                  if (controller.storyStarted && !controller.isCinematic)
                    for (final tab in const <_NovelPrimaryTab>[
                      _NovelPrimaryTab.characters,
                      _NovelPrimaryTab.team,
                      _NovelPrimaryTab.inventory,
                      _NovelPrimaryTab.journey,
                      _NovelPrimaryTab.world,
                      _NovelPrimaryTab.surroundings,
                    ])
                      if (_mountedPrimaryTabs.contains(tab))
                        Positioned.fill(
                          key: ValueKey<String>('novel-primary-${tab.name}'),
                          child: Offstage(
                            offstage: _primaryTab != tab,
                            child: TickerMode(
                              enabled: _primaryTab == tab,
                              child: _buildPrimaryArchiveTab(tab),
                            ),
                          ),
                        ),

                  // 底部导航栏
                  if (showBottomNav)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: SafeArea(
                        top: false,
                        child: NovelBottomArchiveBar(
                          // 因为加入了 surroundings，索引不再是一一对应，需要精准映射
                          selectedIndex: switch (_primaryTab) {
                            _NovelPrimaryTab.characters => 1,
                            _NovelPrimaryTab.team => 2,
                            _NovelPrimaryTab.inventory => 3,
                            _NovelPrimaryTab.journey => 4,
                            _NovelPrimaryTab.world => 5,
                            _ => 0, 
                          },
                          // 注意：删掉了 onWorld 属性
                          onSelected: (index) {
                            final tab = switch(index) {
                              1 => _NovelPrimaryTab.characters,
                              2 => _NovelPrimaryTab.team,
                              3 => _NovelPrimaryTab.inventory,
                              4 => _NovelPrimaryTab.journey,
                              5 => _NovelPrimaryTab.world,
                              _ => _NovelPrimaryTab.story,
                            };
                            _selectPrimaryTab(tab);
                          },
                        ),
                      ),
                    ),

                  if (_primaryTab == _NovelPrimaryTab.story &&
                      controller.storyStarted &&
                      controller.isGenerating &&
                      (controller.currentSentence?.readerText.trim().isEmpty ?? true) &&
                      !controller.showDice)
                    const NovelBrewingOverlay(),

                  if (_primaryTab == _NovelPrimaryTab.story &&
                      controller.storyStarted &&
                      controller.hudEvent != null &&
                      controller.hudEvent!.kind != 'affection' &&
                      controller.hudEvent!.kind != 'score' &&
                      !(controller.hudEvent!.kind == 'milestone' &&
                          controller.hudEvent!.title.trim() == '目标更新'))
                    KeyedSubtree(
                      key: ValueKey<int>(controller.hudEvent!.id),
                      child: NovelHudEventOverlay(event: controller.hudEvent!),
                    ),

                  if (controller.isInitializing)
                    ColoredBox(
                      color: Colors.black.withOpacity(.58),
                      child: const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xB3FFFFFF),
                              ),
                            ),
                            SizedBox(height: 14),
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
                          ? '场景载入异常，请返回首页' 
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
