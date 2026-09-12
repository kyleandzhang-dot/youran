import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../game_shell.dart';
import '../../api/user_api.dart';
import 'novel_ending_page.dart';
import 'novel_backend.dart';
import 'novel_game_controller.dart';
import 'novel_display_mode.dart';
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
  static const List<Duration> _sceneRecoveryBackoff = <Duration>[
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 4),
  ];
  static const String _displayModePreferenceKey =
      'novel_display_mode_preference';
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
  Timer? _sceneRecoveryTimer;
  bool _sceneRecoveryInFlight = false;
  bool _sceneRecoveryExhausted = false;
  int _sceneRecoveryAttempt = 0;
  String _sceneRecoveryOriginalError = '';
  bool _isAdmin = false;
  NovelWeatherEffect? _weatherPreviewOverride;
  String? _backgroundPreviewOverride;
  Uint8List? _backgroundPreviewBytes;
  String? _backgroundPreviewFileName;
  int _backgroundPreviewVersion = 0;
  double _backgroundParallaxStrength = 1.5;
  NovelTimePeriod? _timePreviewOverride;
  String _lastWeatherSyncToken = '';
  Timer? _sceneArrivalTimer;
  String _lastSceneArrivalToken = '';
  // 首次从历史记录恢复时，当前地点只是已有状态，不是一次新的抵达。
  // 先用历史中的当前位置给 arrival token 做基线，避免每次刷新都误播“新地点”。
  bool _sceneArrivalHydrated = false;
  bool _sceneArrivalActive = false;
  String? _sceneArrivalPreviewTitle;
  String? _sceneArrivalPreviewSubtitle;
  int _sceneArrivalRunId = 0;
  List<NovelSceneBark> _sceneBarks = const <NovelSceneBark>[];
  List<NovelSceneBarkActor> _talkTargets = const <NovelSceneBarkActor>[];
  NovelSceneBarkActor? _targetSceneActor;
  String _sceneBarkRefreshToken = '';
  int _sceneBarkRefreshRequestId = 0;
  Timer? _sceneBarkRefreshTimer;
  bool _lastGeneratingForBarks = false;

  NovelGameController get controller => widget.controller;

  // 角色输入/创建阶段进入沉浸输入模式，减少同时显示的信息。
  bool get _immersiveInputMode => _characterSetupOpen;

  bool get _isNativeMobilePlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<void> _applyDisplayModeOrientation(bool desktopMode) async {
    if (!_isNativeMobilePlatform) return;
    try {
      await SystemChrome.setPreferredOrientations(
        desktopMode
            ? const <DeviceOrientation>[
                DeviceOrientation.landscapeLeft,
                DeviceOrientation.landscapeRight,
              ]
            : const <DeviceOrientation>[
                DeviceOrientation.portraitUp,
              ],
      );
    } catch (_) {
      // 某些平台会忽略方向锁定；布局模式本身仍继续生效。
    }
  }

  Future<void> _restoreDisplayModePreference() async {
    bool? savedDesktop;
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_displayModePreferenceKey)?.trim();
      if (saved == 'desktop') {
        savedDesktop = true;
      } else if (saved == 'mobile') {
        savedDesktop = false;
      }
    } catch (error) {
      debugPrint('读取小说显示模式失败：$error');
    }

    if (!mounted) return;

    // 没有本地记录时沿用当前全局默认；有记录时以玩家上一次手动选择为准。
    final targetDesktop = savedDesktop ?? controller.desktopMode;
    if (controller.desktopMode != targetDesktop) {
      controller.setDisplayMode(
        targetDesktop ? NovelDisplayMode.desktop : NovelDisplayMode.mobile,
      );
    }
    await _applyDisplayModeOrientation(targetDesktop);
  }

  Future<void> _saveDisplayModePreference(bool desktopMode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _displayModePreferenceKey,
        desktopMode ? 'desktop' : 'mobile',
      );
    } catch (error) {
      // 本地偏好写入失败不应该阻断当前模式切换。
      debugPrint('保存小说显示模式失败：$error');
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    controller.addListener(_onControllerChanged);

    // 先恢复玩家上一次手动选择的显示模式，再让原生手机方向跟随。
    // 没有保存记录时才沿用当前全局默认；切换剧本也会读取同一份偏好。
    unawaited(_restoreDisplayModePreference());

    unawaited(_loadAdminStatus());
    unawaited(_initializeGame());
  }

  Future<void> _loadAdminStatus() async {
    try {
      final profile = await UserApi.getProfile();
      if (!mounted) return;
      setState(() => _isAdmin = profile.isAdmin);
    } catch (_) {
      // 权限状态无法确认时按普通用户处理，绝不默认开放开发者入口。
      if (!mounted) return;
      setState(() => _isAdmin = false);
    }
  }

  Future<void> _initializeGame() async {
    await controller.initialize();
    if (!mounted) return;

    _syncSceneArrival();
    _syncSceneRecovery();

    // 初始化失败时由页面自动打开菜单，不再继续预加载剧情音频。
    if (!controller.isInitialized) return;

    _scheduleSceneBarkRefresh(force: true);

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
      // 如果运行中已经进入自动恢复流程，就把待执行的退避重试提前到现在，
      // 避免与 recoverAfterResume() 再并发发起一套重复恢复请求。
      if (_sceneRecoveryInFlight) {
        // 当前恢复请求已经在跑，等待它自行收敛。
      } else if (_sceneRecoveryOriginalError.isNotEmpty ||
          controller.lastError.trim().isNotEmpty) {
        _sceneRecoveryTimer?.cancel();
        _sceneRecoveryTimer = null;
        _syncSceneRecovery(immediate: true);
      } else {
        // 没有已知错误时仍执行原有的前台权威状态刷新。
        unawaited(controller.recoverAfterResume());
      }
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
    _syncSceneRecovery();
    _syncSceneBarksAfterControllerChange();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _processOverlayRequests();
      unawaited(_syncActiveWeatherAudio());
    });
  }

  bool get _sceneRecoveryActive => _sceneRecoveryOriginalError.isNotEmpty;

  String get _sceneRecoveryStatusMessage {
    final total = _sceneRecoveryBackoff.length;
    if (_sceneRecoveryExhausted) {
      return '场景自动重连失败，请返回首页后重试';
    }
    if (_sceneRecoveryInFlight) {
      final attempt = _sceneRecoveryAttempt.clamp(1, total);
      return '场景连接异常，正在自动恢复（$attempt/$total）…';
    }
    if (_sceneRecoveryTimer != null) {
      final nextAttempt = (_sceneRecoveryAttempt + 1).clamp(1, total);
      return '场景连接异常，将自动重连（$nextAttempt/$total）…';
    }
    return '场景载入异常，正在自动恢复…';
  }

  void _clearSceneRecoveryState({bool cancelTimer = true}) {
    if (cancelTimer) {
      _sceneRecoveryTimer?.cancel();
      _sceneRecoveryTimer = null;
    }
    _sceneRecoveryExhausted = false;
    _sceneRecoveryAttempt = 0;
    _sceneRecoveryOriginalError = '';
  }

  void _dismissSceneRecoveryStatus() {
    _sceneRecoveryTimer?.cancel();
    if (mounted) {
      setState(() {
        _sceneRecoveryTimer = null;
        _sceneRecoveryExhausted = false;
        _sceneRecoveryAttempt = 0;
        _sceneRecoveryOriginalError = '';
      });
    } else {
      _sceneRecoveryTimer = null;
      _sceneRecoveryExhausted = false;
      _sceneRecoveryAttempt = 0;
      _sceneRecoveryOriginalError = '';
    }
    controller.clearMessages();
  }

  void _syncSceneRecovery({bool immediate = false}) {
    if (!mounted) return;

    final error = controller.lastError.trim();

    // 初始化阶段的失败继续交给 _handleLoadFailure()；这里只接管已经成功
    // 进入世界之后发生的瞬时网络/场景同步错误。
    if (!controller.isInitialized || controller.isInitializing) {
      if (!_sceneRecoveryInFlight) {
        _clearSceneRecoveryState();
      }
      return;
    }

    if (_sceneRecoveryInFlight) return;

    // 错误已经被其他成功请求清掉，说明无需继续等待下一次退避重试。
    if (error.isEmpty) {
      if (_sceneRecoveryActive) {
        _clearSceneRecoveryState();
      }
      return;
    }

    if (!_sceneRecoveryActive) {
      _sceneRecoveryOriginalError = error;
      _sceneRecoveryAttempt = 0;
      _sceneRecoveryExhausted = false;
    }

    if (_sceneRecoveryExhausted || _sceneRecoveryTimer != null) return;
    _scheduleSceneRecovery(immediate: immediate);
  }

  void _scheduleSceneRecovery({bool immediate = false}) {
    if (!mounted ||
        !_sceneRecoveryActive ||
        _sceneRecoveryInFlight ||
        _sceneRecoveryTimer != null ||
        _sceneRecoveryExhausted) {
      return;
    }

    if (_sceneRecoveryAttempt >= _sceneRecoveryBackoff.length) {
      setState(() => _sceneRecoveryExhausted = true);
      return;
    }

    final delay = immediate
        ? Duration.zero
        : _sceneRecoveryBackoff[_sceneRecoveryAttempt];
    _sceneRecoveryTimer = Timer(delay, () {
      _sceneRecoveryTimer = null;
      unawaited(_attemptSceneRecovery());
    });
  }

  Future<void> _attemptSceneRecovery() async {
    if (!mounted ||
        !_sceneRecoveryActive ||
        _sceneRecoveryInFlight ||
        !controller.isInitialized) {
      return;
    }

    setState(() {
      _sceneRecoveryInFlight = true;
      _sceneRecoveryAttempt++;
    });

    // lastError 是上一次失败留下的旧状态。先清掉它，之后即可用
    // recoverAfterResume() 是否重新写入 lastError 来判断本轮恢复是否成功。
    controller.clearMessages();

    Object? thrownError;
    StackTrace? thrownStack;
    try {
      await controller.recoverAfterResume();
    } catch (error, stackTrace) {
      thrownError = error;
      thrownStack = stackTrace;
    }

    if (!mounted) return;

    _sceneRecoveryInFlight = false;

    // 用户可能在请求期间主动关闭了错误提示，此时不再继续自动重试。
    if (!_sceneRecoveryActive) {
      setState(() {});
      return;
    }

    final failed = thrownError != null ||
        !controller.isInitialized ||
        controller.lastError.trim().isNotEmpty;

    if (!failed) {
      setState(() {
        _clearSceneRecoveryState();
      });
      return;
    }

    if (thrownError != null) {
      debugPrint('场景自动恢复失败：$thrownError');
      if (kDebugMode && thrownStack != null) {
        debugPrintStack(stackTrace: thrownStack);
      }
    }

    if (_sceneRecoveryAttempt >= _sceneRecoveryBackoff.length) {
      setState(() => _sceneRecoveryExhausted = true);
      return;
    }

    setState(() {
      _scheduleSceneRecovery();
    });
  }

  void _syncSceneArrival() {
    final title = controller.locationTitle.trim();
    final subtitle = controller.locationSubtitle.trim();

    if (!controller.isInitialized || title.isEmpty) return;

    final token = '$title\u0000$subtitle';

    // 初始化完成后的第一次同步只是“恢复当前世界”。
    // 如果已经存在历史 AI 消息，就把当前位置登记成基线，不播放抵达动画。
    // 真正的新开局此时 storyStarted=false，之后第一次实际进入/移动仍会正常触发。
    if (!_sceneArrivalHydrated) {
      _sceneArrivalHydrated = true;
      if (controller.storyStarted && controller.lastAssistantMessage != null) {
        _lastSceneArrivalToken = token;
        return;
      }
    }

    // 回看旧页时不播放；只有停在最新剧情并且地点真的变化才触发。
    if (!controller.storyStarted || controller.hasNext) return;
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

  void _syncSceneBarksAfterControllerChange() {
    final wasGenerating = _lastGeneratingForBarks;
    _lastGeneratingForBarks = controller.isGenerating;

    if (!controller.isInitialized ||
        !controller.storyStarted ||
        controller.isGenerating) {
      return;
    }

    final token = _sceneBarkToken();
    if (token.isEmpty) return;
    if (token != _sceneBarkRefreshToken || wasGenerating) {
      _scheduleSceneBarkRefresh(force: wasGenerating);
    }
  }

  String _sceneBarkToken() {
    final sessionId = controller.sessionId.trim();
    if (sessionId.isEmpty) return '';
    return <String>[
      sessionId,
      controller.locationTitle.trim(),
      controller.locationSubtitle.trim(),
    ].join('\u0001');
  }

  void _scheduleSceneBarkRefresh({bool force = false}) {
    _sceneBarkRefreshTimer?.cancel();
    _sceneBarkRefreshTimer = Timer(
      force ? Duration.zero : const Duration(milliseconds: 280),
      () => unawaited(_refreshSceneBarks(force: force)),
    );
  }

  Future<void> _refreshSceneBarks({bool force = false}) async {
    if (!mounted || !controller.isInitialized || !controller.storyStarted) {
      return;
    }
    final token = _sceneBarkToken();
    if (token.isEmpty) return;
    if (!force &&
        token == _sceneBarkRefreshToken &&
        (_sceneBarks.isNotEmpty || _talkTargets.isNotEmpty)) {
      return;
    }

    final requestId = ++_sceneBarkRefreshRequestId;
    _sceneBarkRefreshToken = token;
    try {
      final payload = await controller.backend.fetchSceneMap(controller.sessionId);
      if (!mounted || requestId != _sceneBarkRefreshRequestId) return;
      final nextBarks = NovelSceneBark.listFromSceneMap(payload);
      final nextTargets = NovelSceneBarkActor.talkTargetsFromSceneMap(payload);
      setState(() {
        _sceneBarks = nextBarks;
        _talkTargets = nextTargets;
        if (_targetSceneActor != null &&
            !nextTargets.any((actor) => actor.id == _targetSceneActor!.id) &&
            !nextBarks.any((bark) => bark.clickable && bark.actor.id == _targetSceneActor!.id)) {
          _targetSceneActor = null;
        }
      });
    } catch (error) {
      // 场景气泡只是氛围层，拉取失败不应该打断剧情阅读。
      debugPrint('刷新场景气泡失败：$error');
    }
  }

  void _handleSceneBarkTap(NovelSceneBark bark) {
    if (!bark.clickable || bark.actor.cleanName.isEmpty) return;
    setState(() => _targetSceneActor = bark.actor);
    _inputFocusNode.requestFocus();
  }

  void _handleTalkTargetTap(NovelSceneBarkActor actor) {
    if (actor.cleanName.isEmpty) return;
    setState(() => _targetSceneActor = actor);
    _inputFocusNode.requestFocus();
  }

  void _clearTargetSceneActor() {
    if (_targetSceneActor == null) return;
    setState(() => _targetSceneActor = null);
  }

  void _sendStoryInput(String text) {
    controller.goLatest();
    final target = _targetSceneActor;
    final cleanText = text.trim();
    if (target != null && target.cleanName.isNotEmpty) {
      setState(() => _targetSceneActor = null);
      unawaited(controller.sendPlayerMessage('对${target.cleanName}说：$cleanText'));
      return;
    }
    unawaited(controller.sendPlayerMessage(cleanText));
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
    // 不要在 dispose() 里改屏幕方向。切换世界时旧 NovelGamePage 的 dispose
    // 可能晚于新页面 initState 执行，若这里强制 portraitUp，会把新页面已经
    // 恢复好的横屏模式再次覆盖。真正离开小说模块时，应由外层导航页决定方向。
    WidgetsBinding.instance.removeObserver(this);
    controller.removeListener(_onControllerChanged);
    _sceneArrivalTimer?.cancel();
    _sceneBarkRefreshTimer?.cancel();
    _sceneRecoveryTimer?.cancel();
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
        backgroundPreviewName: () => _backgroundPreviewFileName,
        parallaxStrength: () => _backgroundParallaxStrength,
        setWeatherOverride: _setWeatherPreviewOverride,
        setTimeOverride: _setTimePreviewOverride,
        setParallaxStrength: _setBackgroundParallaxStrength,
        setBackgroundPreview: _setBackgroundPreview,
        clearBackgroundPreview: _clearBackgroundPreview,
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
        previewExploration: _previewExploration,
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

  void _setBackgroundParallaxStrength(double value) {
    if (!mounted) return;
    setState(() {
      _backgroundParallaxStrength = value.clamp(.15, 2.5).toDouble();
    });
  }

  void _setBackgroundPreview(Uint8List bytes, String fileName) {
    if (!mounted || bytes.isEmpty) return;
    setState(() {
      _backgroundPreviewVersion++;
      _backgroundPreviewBytes = bytes;
      _backgroundPreviewFileName =
          fileName.trim().isEmpty ? '本地背景' : fileName.trim();
      // 本地预览优先；同时清掉“背景过渡”测试 URL，避免恢复时跳回随机图。
      _backgroundPreviewOverride = null;
    });
  }

  void _clearBackgroundPreview() {
    if (!mounted) return;
    setState(() {
      _backgroundPreviewBytes = null;
      _backgroundPreviewFileName = null;
      _backgroundPreviewOverride = null;
    });
  }

  Future<void> _setReadingMode(bool immersiveMode) async {
    _inputFocusNode.unfocus();
    FocusManager.instance.primaryFocus?.unfocus();

    if (controller.desktopMode == immersiveMode) return;

    // 阅读模式只改变剧情布局语义：标准=竖屏，沉浸=横屏。
    // 底层继续复用既有 mobile / desktop 布局状态，避免牵动整套响应式实现。
    controller.setDisplayMode(
      immersiveMode ? NovelDisplayMode.desktop : NovelDisplayMode.mobile,
    );
    await Future.wait<void>(<Future<void>>[
      _applyDisplayModeOrientation(immersiveMode),
      _saveDisplayModePreference(immersiveMode),
    ]);

    if (!mounted) return;
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

  Future<void> _previewExploration() async {
    if (!mounted) return;
    FocusManager.instance.primaryFocus?.unfocus();

    final initialSceneName = controller.locationTitle.trim().isNotEmpty
        ? controller.locationTitle.trim()
        : '斗破苍穹 乌坦城萧家坊市';

    await Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => NovelExplorationPage(
          backend: controller.backend,
          sessionId: controller.sessionId,
          initialSceneName: initialSceneName,
        ),
      ),
    );
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
    // 百分比威力制：开发者探索预览与正式后端保持同一基准。
    // 普通敌人以 65% 为基础威力，再由探索品质/装备评估得到 attackRatio。
    final basicAttackPowerPercent =
        (65 * attackRatio).round().clamp(35, 220).toInt();
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
      basicAttackPowerPercent: basicAttackPowerPercent,
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
      _backgroundPreviewBytes = null;
      _backgroundPreviewFileName = null;
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

  String _characterArchiveKey(NovelCharacter character) =>
      character.id.trim().isNotEmpty
          ? character.id.trim()
          : character.name.trim();

  void _focusCharacterInArchive(NovelCharacter character) {
    final key = _characterArchiveKey(character);
    if (key.isEmpty) return;

    FocusManager.instance.primaryFocus?.unfocus();
    unawaited(controller.bgm.stopTypingSound());

    setState(() {
      // 主角 / NPC 统一进入“人物”主页面，只改变当前聚焦角色。
      // focusRequestId 保证即使已经停留在人物页，再点一次头像也会重新聚焦。
      _characterFocusKey = key;
      _characterFocusRequestId++;
      _primaryTab = _NovelPrimaryTab.characters;
      _mountedPrimaryTabs.add(_NovelPrimaryTab.characters);
    });
  }

  void _openHostCharacterArchive() {
    final host = controller.protagonist;
    if (host == null) {
      _selectPrimaryTab(_NovelPrimaryTab.characters);
      return;
    }
    _focusCharacterInArchive(host);
  }

  Future<void> _openCurrentSpeakerProfile() async {
    final character = controller.currentSpeakerCharacter;
    if (character == null || !mounted) return;
    _focusCharacterInArchive(character);
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
  Widget build(BuildContext context) {
    return GameShell(
      activeScenarioId: controller.scenarioId,
      resizeToAvoidBottomInset: false,
      backgroundColor: controller.settings.backgroundColor,
      builder: (context, openDrawer) {
        return AnimatedBuilder(
          animation: Listenable.merge(<Listenable>[
            controller,
            controller.settings,
            novelDisplayMode,
          ]),
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
            final hasRuntimeSceneError = !loadFailed &&
                (controller.lastError.isNotEmpty || _sceneRecoveryActive);

            if (controller.isInitialized) {
              _loadFailureHandled = false;
            } else if (loadFailed) {
              _handleLoadFailure(openDrawer);
            }

            final rootMedia = MediaQuery.of(context);
            // 第一次进入时根据平台 / 窗口给默认值；之后完全以玩家手动选择为准。
            novelDisplayMode.ensureInitialized(
              viewportWidth: rootMedia.size.width,
              nativeMobile: _isNativeMobilePlatform,
            );
            final desktopMode = controller.desktopMode;

            // PC/Web 的“手机模式”不再只把宽度硬压到 430，而是按现代 iPhone
            // 的长屏比例模拟完整画布，并补上接近真机的顶部/底部安全区。
            // 这样在电脑上调出的手机版，与真机的纵向空间分配会非常接近。
            final previewingPhoneOnDesktop = !desktopMode &&
                !_isNativeMobilePlatform &&
                rootMedia.size.width > 600;
            const referencePhoneSize = Size(430, 932);
            final previewHeight = previewingPhoneOnDesktop
                ? math.min(referencePhoneSize.height, rootMedia.size.height)
                : rootMedia.size.height;
            final previewWidth = previewingPhoneOnDesktop
                ? math.min(
                    referencePhoneSize.width,
                    previewHeight *
                        referencePhoneSize.width /
                        referencePhoneSize.height,
                  )
                : rootMedia.size.width;
            final mobilePreviewSize = Size(previewWidth, previewHeight);
            final previewScale = previewingPhoneOnDesktop
                ? previewHeight / referencePhoneSize.height
                : 1.0;
            final simulatedPhoneSafeArea = EdgeInsets.only(
              top: 47.0 * previewScale,
              bottom: 34.0 * previewScale,
            );
            final effectiveMedia = previewingPhoneOnDesktop
                ? rootMedia.copyWith(
                    size: mobilePreviewSize,
                    padding: simulatedPhoneSafeArea,
                    viewPadding: simulatedPhoneSafeArea,
                    viewInsets: EdgeInsets.zero,
                  )
                : rootMedia.copyWith(size: mobilePreviewSize);
            final isCompactWidth = mobilePreviewSize.width <= 600;
            final keyboardInset = rootMedia.viewInsets.bottom;
            final keyboardActive = isCompactWidth && keyboardInset > 0;
            
            final showBottomNav = !_immersiveInputMode &&
                controller.storyStarted &&
                !controller.isCinematic &&
                !_endingOpen &&
                !_battleOpen &&
                _primaryTab != _NovelPrimaryTab.surroundings &&
                (controller.hasNext || controller.isGenerating) &&
                !keyboardActive;

            final gameScaffold = Scaffold(
              resizeToAvoidBottomInset: false,
              backgroundColor: controller.settings.backgroundColor,
              body: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  RepaintBoundary(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 360),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      child: NovelWorldBackground(
                        url: _backgroundPreviewBytes == null ? background : '',
                        memoryBytes: _backgroundPreviewBytes,
                        memoryCacheKey: _backgroundPreviewBytes == null
                            ? ''
                            : 'developer-background|$_backgroundPreviewVersion|${_backgroundPreviewFileName ?? ''}|${_backgroundPreviewBytes!.lengthInBytes}',
                        parallaxStrength: _backgroundParallaxStrength,
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
                  ),
                  SafeArea(
                    minimum: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final viewport = NovelViewportMetrics.of(
                          context,
                          desktopMode: desktopMode,
                        );
                        final compact = viewport.compactChrome;
                        final shortWide = viewport.shortWide;
                        // 当前 Stack 位于 SafeArea(minimum: 左右14) 内。
                        // 底部探索需要视觉上横向铺满整个屏幕，所以单独向两侧越过这层 inset。
                        final screenPadding = MediaQuery.paddingOf(context);
                        final inlineEdgeLeft = math.max(14.0, screenPadding.left);
                        final inlineEdgeRight = math.max(14.0, screenPadding.right);
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

                        // 底部整块探索舞台先隐藏，但保留实现，后续需要时可直接重新开启。
                        // 当前只恢复输入框上方的轻量“探索周围”入口，避免场景底部被大块 UI 占满。
                        const showInlineSurroundingsDock = false;
                        final inlineSurroundingsVisible =
                            showInlineSurroundingsDock &&
                            _primaryTab == _NovelPrimaryTab.story &&
                            controller.storyStarted &&
                            !controller.isCinematic &&
                            !keyboardActive &&
                            !controller.hasNext &&
                            !controller.isGenerating &&
                            !_sceneArrivalActive &&
                            !_battleOpen &&
                            !_endingOpen;
                        final inlineFullWidth = constraints.maxWidth +
                            inlineEdgeLeft +
                            inlineEdgeRight;
                        final inlineSurroundingsHeight = inlineSurroundingsVisible
                            ? (inlineFullWidth / (compact ? 1.82 : 2.05))
                                .clamp(
                                  compact ? 172.0 : 188.0,
                                  compact ? 222.0 : 250.0,
                                )
                                .toDouble()
                            : 0.0;
                        final inlineSurroundingsEnabled =
                            inlineSurroundingsVisible &&
                            !controller.isSurroundingsLoading;
                        final storyClock = controller.storyClock;
                        final storyDayLabel = storyClock.enabled
                            ? (storyClock.dayLabel.trim().isNotEmpty
                                ? storyClock.dayLabel.trim()
                                : '第${storyClock.dayIndex < 1 ? 1 : storyClock.dayIndex}天')
                            : '';
                        final storyPeriodLabel = storyClock.enabled
                            ? (storyClock.timeDescription.trim().isNotEmpty
                                ? storyClock.timeDescription.trim()
                                : switch (storyClock.periodKey) {
                                    'morning' => '早晨',
                                    'noon' => '中午',
                                    'afternoon' => '下午',
                                    'evening' => '傍晚',
                                    'night' => '夜晚',
                                    'midnight' => '深夜',
                                    _ => '',
                                  })
                            : '';
                        final rightSceneExploreVisible =
                            !showInlineSurroundingsDock &&
                            _primaryTab == _NovelPrimaryTab.story &&
                            controller.storyStarted &&
                            !controller.isCinematic &&
                            !keyboardActive &&
                            !controller.hasNext &&
                            !controller.isGenerating &&
                            !_sceneArrivalActive &&
                            !_battleOpen &&
                            !_endingOpen &&
                            controller.surroundingsActionLabel
                                .trim()
                                .isNotEmpty;

                        return Stack(
                          // 允许底部探索区单独越过 SafeArea 的左右 14px，
                          // 做成真正贴屏的连续横版场景。
                          clipBehavior: Clip.none,
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
                                onOpenProfile: _openHostCharacterArchive,
                                onOpenStore: () =>
                                    showNovelStoreSheet(context, controller),
                                onOpenSettings: () => showNovelSettingsSheet(
                                  context,
                                  controller,
                                  immersiveMode: desktopMode,
                                  onReadingModeChanged: _setReadingMode,
                                  isAdmin: _isAdmin,
                                  developerPreview:
                                      _isAdmin ? _developerPreviewActions : null,
                                ),
                              ),
                            ),

                            // 故事时间属于“场景信息”，不再挤在顶部系统工具栏。
                            // 它始终停在右侧场景轴上；最后一页时附近角色会从它下方接入。
                            if (!_immersiveInputMode &&
                                controller.storyStarted &&
                                !controller.isCinematic &&
                                !keyboardActive &&
                                !_battleOpen &&
                                !_endingOpen &&
                                storyDayLabel.isNotEmpty)
                              Positioned(
                                right: compact ? 10 : 18,
                                top: shortWide ? 48 : 66,
                                child: _NovelSceneTimeStamp(
                                  dayLabel: storyDayLabel,
                                  periodLabel: storyPeriodLabel,
                                  compact: compact,
                                  shortWide: shortWide,
                                ),
                              ),

                            // 完美左对齐 + 高度紧凑优化：把位置和目标包在一个 Column 里
                            if (!_immersiveInputMode && controller.storyStarted && !keyboardActive)
                              Positioned(
                                left: 0,
                                top: shortWide ? 48 : 56, // 横屏矮屏进一步压缩顶部占用
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
                                top: shortWide ? 48 : 56,
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
                                // Stack 前后会动态插入/移除地点标题、右侧人物和气泡层。
                                // 顶层稳定 Key 保证这些兄弟节点变化时 Reader State 不会被卸载重建，
                                // 否则 NovelDialogPanel.initState() 会再次启动逐字动画。
                                key: const ValueKey<String>('novel-story-reader-stage'),
                                alignment: Alignment.bottomCenter,
                                child: Padding(
                                  // 剧情区域始终保持左右对称，不为右侧悬浮按钮预留宽度。
                                  padding: EdgeInsets.zero,
                                  // 手机仍保持原来的 720px 阅读舞台；电脑模式则把
                                  // 整个角色/对白舞台真正放开到当前窗口宽度。否则 reader
                                  // 里的 left: 0 只会贴到“居中的 720px 小舞台”左边。
                                  child: SizedBox(
                                    width: desktopMode
                                        ? constraints.maxWidth
                                        : math.min(720.0, constraints.maxWidth),
                                    child: NovelChoiceDockActionScope(
                                      // 探索入口属于剧情阅读舞台，不再塞进附近角色列表。
                                      // 只在最后一页由 Reader 放到正文右上方。
                                      visible: rightSceneExploreVisible,
                                      label: controller.surroundingsActionLabel,
                                      attention: controller.surroundingsNeedsAttention,
                                      loading: controller.isSurroundingsLoading,
                                      onTap: () => _selectPrimaryTab(
                                        _NovelPrimaryTab.surroundings,
                                      ),
                                      child: NovelDialogPanel(
                                      controller: controller,
                                      bottomReservedHeight: inlineSurroundingsHeight,
                                      active: _primaryTab == _NovelPrimaryTab.story,
                                      textController: _inputController,
                                      focusNode: _inputFocusNode,
                                      onSend: _sendStoryInput,
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
                                      targetActorName:
                                          _targetSceneActor?.cleanName ?? '',
                                      targetActorAvatarUrl:
                                          _targetSceneActor?.avatarUrl ?? '',
                                      targetActorPlaceholder:
                                          _targetSceneActor?.inputPlaceholder ?? '',
                                      onClearTargetActor: _clearTargetSceneActor,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            if (_primaryTab == _NovelPrimaryTab.story &&
                                controller.storyStarted &&
                                !controller.isCinematic &&
                                !keyboardActive &&
                                !showBottomNav &&
                                !controller.hasNext &&
                                !controller.isGenerating &&
                                !_sceneArrivalActive &&
                                !_battleOpen &&
                                !_endingOpen &&
                                _talkTargets.isNotEmpty)
                              Positioned(
                                right: compact ? 6 : 14,
                                // 时间牌改为上下两层后高度更高；人物/探索从它下方留出呼吸感。
                                top: shortWide ? 106 : 136,
                                bottom: shortWide ? 84 : 212,
                                child: NovelRightSceneDock(
                                  targets: _talkTargets,
                                  selectedActorId: _targetSceneActor?.id ?? '',
                                  onSelected: _handleTalkTargetTap,
                                  onClear: _clearTargetSceneActor,
                                  // 探索入口已经移入剧情正文舞台；右侧 Dock 只负责附近角色。
                                  exploreVisible: false,
                                  exploreLabel: '',
                                  exploreAttention:
                                      controller.surroundingsNeedsAttention,
                                  exploreLoading:
                                      controller.isSurroundingsLoading,
                                  onExplore: () => _selectPrimaryTab(
                                    _NovelPrimaryTab.surroundings,
                                  ),
                                ),
                              ),
                            if (_primaryTab == _NovelPrimaryTab.story &&
                                controller.storyStarted &&
                                !controller.isCinematic &&
                                !keyboardActive &&
                                !controller.isGenerating &&
                                !_sceneArrivalActive &&
                                !_battleOpen &&
                                !_endingOpen &&
                                _sceneBarks.isNotEmpty)
                              Positioned.fill(
                                child: NovelSceneBarkLayer(
                                  barks: _sceneBarks,
                                  // 群众/摊贩气泡是场景常驻氛围层；选中对话对象后也不隐藏。
                                  enabled: true,
                                  bottomReserve: inlineSurroundingsHeight,
                                  onBarkTap: _handleSceneBarkTap,
                                ),
                              ),
                            if (inlineSurroundingsVisible)
                              Positioned(
                                // 只让探索区越过 SafeArea 的左右安全边距，
                                // 正文、HUD 仍保持原来的 14px 阅读安全区。
                                left: -inlineEdgeLeft,
                                right: -inlineEdgeRight,
                                bottom: 0,
                                height: inlineSurroundingsHeight,
                                child: RepaintBoundary(
                                  child: NovelSurroundingsInlineDock(
                                    key: ValueKey<String>(
                                      'inline-surroundings|${controller.locationTitle}|${controller.locationSubtitle}',
                                    ),
                                    controller: controller,
                                    enabled: inlineSurroundingsEnabled,
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

                  // 右侧一级导航使用中等强度的窄暗带。
                  // 保持遮罩范围收敛，但提高核心暗度，让图标和文字在亮背景上仍然清楚。
                  if (showBottomNav)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      width: desktopMode ? 126.0 : 104.0,
                      height: desktopMode ? 520.0 : 432.0,
                      child: IgnorePointer(
                        child: ShaderMask(
                          blendMode: BlendMode.dstIn,
                          shaderCallback: (bounds) => const LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: <Color>[
                              Colors.white,
                              Colors.white,
                              Color(0xD9FFFFFF),
                              Color(0x66FFFFFF),
                              Color(0x00FFFFFF),
                            ],
                            stops: <double>[0, .52, .70, .88, 1],
                          ).createShader(bounds),
                          child: const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.centerRight,
                                end: Alignment.centerLeft,
                                colors: <Color>[
                                  Color(0x78000000),
                                  Color(0x56000000),
                                  Color(0x30000000),
                                  Color(0x12000000),
                                  Color(0x00000000),
                                ],
                                stops: <double>[0, .22, .48, .74, 1],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                  // 底部导航栏（实际为右下竖向六按钮）
                  if (showBottomNav)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: SafeArea(
                        top: false,
                        child: NovelBottomArchiveBar(
                          desktopMode: desktopMode,
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
                      message: hasRuntimeSceneError
                          ? _sceneRecoveryStatusMessage
                          : controller.infoMessage,
                      isError: hasRuntimeSceneError,
                      onDismiss: hasRuntimeSceneError
                          ? _dismissSceneRecoveryStatus
                          : controller.clearMessages,
                    ),
                ],
              ),
            );

            final sizedGame = MediaQuery(
              data: effectiveMedia,
              child: gameScaffold,
            );

            // PC/Web 手机预览保持真实长屏比例；桌面模式继续使用完整窗口。
            if (previewingPhoneOnDesktop) {
              return ColoredBox(
                color: controller.settings.backgroundColor,
                child: Center(
                  child: SizedBox(
                    width: mobilePreviewSize.width,
                    height: mobilePreviewSize.height,
                    child: ClipRect(child: sizedGame),
                  ),
                ),
              );
            }
            return sizedGame;
          },
        );
      },
    );
  }
}

class _NovelSceneTimeStamp extends StatelessWidget {
  const _NovelSceneTimeStamp({
    required this.dayLabel,
    required this.periodLabel,
    required this.compact,
    required this.shortWide,
  });

  final String dayLabel;
  final String periodLabel;
  final bool compact;
  final bool shortWide;

  @override
  Widget build(BuildContext context) {
    final day = dayLabel.trim();
    final period = periodLabel.trim();
    if (day.isEmpty) return const SizedBox.shrink();

    // 时间只做“场景字幕”，不再使用卡片、遮罩或边框。
    // 两行排版保留主次层级：天数是主信息，时段是轻量副信息。
    return IgnorePointer(
      child: Semantics(
        label: period.isEmpty ? '故事时间 $day' : '故事时间 $day $period',
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: shortWide ? 2 : 3,
            vertical: 2,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text(
                day,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: Colors.white.withOpacity(.92),
                  fontFamily: 'WenJinMinchoP0',
                  fontSize: shortWide ? 10.4 : (compact ? 11.0 : 11.7),
                  height: 1.05,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .48,
                  shadows: const <Shadow>[
                    Shadow(
                      color: Color(0xA8000000),
                      blurRadius: 6,
                      offset: Offset(0, 1),
                    ),
                    Shadow(
                      color: Color(0x52000000),
                      blurRadius: 12,
                    ),
                  ],
                ),
              ),
              if (period.isNotEmpty) ...<Widget>[
                SizedBox(height: shortWide ? 4 : 5),
                Text(
                  period,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: Colors.white.withOpacity(.62),
                    fontFamily: 'WenJinMinchoP0',
                    fontSize: shortWide ? 8.5 : (compact ? 9.0 : 9.5),
                    height: 1.0,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 1.18,
                    shadows: const <Shadow>[
                      Shadow(
                        color: Color(0x98000000),
                        blurRadius: 5,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
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




