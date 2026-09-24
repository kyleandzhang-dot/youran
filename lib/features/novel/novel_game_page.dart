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
  static const bool _showLegacyLocationHud = true;

  final TextEditingController _inputController = TextEditingController();
  final FocusNode _inputFocusNode = FocusNode();

  _NovelPrimaryTab _primaryTab = _NovelPrimaryTab.story;
  final Set<_NovelPrimaryTab> _mountedPrimaryTabs = <_NovelPrimaryTab>{
    _NovelPrimaryTab.story,
  };
  String _characterFocusKey = '';
  int _characterFocusRequestId = 0;

  bool _characterOpenedFromAvatar = false;
  bool _characterSetupOpen = false;
  
  // 🌟 摇杆信号与探索状态控制
  final ValueNotifier<Offset> _joystickIntent = ValueNotifier(Offset.zero);
  final ValueNotifier<bool> _joystickActive = ValueNotifier(false);
  bool _joystickTouched = false;

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
      debugPrint('保存小说显示模式失败：$error');
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    controller.addListener(_onControllerChanged);

    // 🌟 监听输入框，聚焦或有文字时自动退出探索模式
    _inputFocusNode.addListener(_onExplorationExitCheck);
    _inputController.addListener(_onExplorationExitCheck);

    unawaited(_restoreDisplayModePreference());
    unawaited(_loadAdminStatus());
    unawaited(_initializeGame());
  }

  void _onExplorationExitCheck() {
    if (!mounted || !_joystickTouched) return;
    if (_inputFocusNode.hasFocus || _inputController.text.isNotEmpty) {
      setState(() => _joystickTouched = false);
    }
  }

  Future<void> _loadAdminStatus() async {
    try {
      final profile = await UserApi.getProfile();
      if (!mounted) return;
      setState(() => _isAdmin = profile.isAdmin);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isAdmin = false);
    }
  }

  Future<void> _initializeGame() async {
    await controller.initialize();
    if (!mounted) return;

    _syncSceneArrival();
    _syncSceneRecovery();

    if (!controller.isInitialized) return;

    _scheduleSceneBarkRefresh(force: true);

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
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !controller.isInitialized) return;
        final route = ModalRoute.of(context);
        if (route == null || !route.isCurrent) return;

        if (_sceneRecoveryInFlight) {
        } else if (_sceneRecoveryOriginalError.isNotEmpty ||
            controller.lastError.trim().isNotEmpty) {
          _sceneRecoveryTimer?.cancel();
          _sceneRecoveryTimer = null;
          _syncSceneRecovery(immediate: true);
        } else {
          unawaited(controller.recoverAfterResume());
        }
        unawaited(controller.bgm.init(
          controller.bgm.currentIntensity,
          controller.bgm.currentSceneMode,
        ));
        unawaited(_syncActiveWeatherAudio(force: true));
      });
    }
  }

  void _onControllerChanged() {
    if (!mounted) return;

    final generationNotice = controller.takeGenerationNotice();
    if (generationNotice != null) {
      _lastGeneratingForBarks = controller.isGenerating;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _showGenerationNotice(generationNotice);
      });
      return;
    }

    _syncSceneArrival();
    _syncSceneRecovery();
    _syncSceneBarksAfterControllerChange();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _processOverlayRequests();
      unawaited(_syncActiveWeatherAudio());
    });
  }

  void _showGenerationNotice(JsonMap notice) {
    if (!mounted) return;
    final message = stringValue(notice['message']).trim();
    if (message.isEmpty) return;

    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(milliseconds: 3200),
        ),
      );
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

    if (!controller.isInitialized || controller.isInitializing) {
      if (!_sceneRecoveryInFlight) {
        _clearSceneRecoveryState();
      }
      return;
    }

    if (_sceneRecoveryInFlight) return;

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

    if (!_sceneArrivalHydrated) {
      _sceneArrivalHydrated = true;
      if (controller.storyStarted && controller.lastAssistantMessage != null) {
        _lastSceneArrivalToken = token;
        return;
      }
    }

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

  NovelCharacter? _characterForSceneActor(NovelSceneBarkActor actor) {
    final characters = controller.scenario?.characters;
    if (characters == null || characters.isEmpty) return null;

    final actorId = actor.id.trim();
    final actorName = actor.cleanName.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    NovelCharacter? nameMatch;

    for (final entry in characters.entries) {
      final character = entry.value;
      if (character.isMain) continue;

      final entryId = entry.key.trim();
      final characterId = character.id.trim();
      if (actorId.isNotEmpty &&
          ((entryId.isNotEmpty && entryId == actorId) ||
              (characterId.isNotEmpty && characterId == actorId))) {
        return character;
      }

      if (actorName.isNotEmpty) {
        final characterName =
            character.name.trim().replaceAll(RegExp(r'\s+'), '').toLowerCase();
        if (characterName == actorName) {
          nameMatch ??= character;
        }
      }
    }

    return nameMatch;
  }

  NovelSceneBarkActor _resolveSceneActorVisuals(NovelSceneBarkActor actor) {
    final character = _characterForSceneActor(actor);
    if (character == null) return actor;

    final gameAvatar = character.avatarUrl.trim();
    final gamePortrait = character.portraitUrl.trim();
    final resolvedAvatar =
        gameAvatar.isNotEmpty ? gameAvatar : actor.avatarUrl.trim();
    final resolvedPortrait =
        gamePortrait.isNotEmpty ? gamePortrait : actor.portraitUrl.trim();

    if (resolvedAvatar == actor.avatarUrl.trim() &&
        resolvedPortrait == actor.portraitUrl.trim()) {
      return actor;
    }

    return NovelSceneBarkActor(
      id: actor.id,
      name: actor.name,
      kind: actor.kind,
      role: actor.role,
      avatarUrl: resolvedAvatar,
      portraitUrl: resolvedPortrait,
      priority: actor.priority,
      source: actor.source,
      ephemeral: actor.ephemeral,
    );
  }

  List<NovelSceneBarkActor> get _resolvedTalkTargets => _talkTargets
      .map(_resolveSceneActorVisuals)
      .toList(growable: false);

  NovelSceneBarkActor? get _resolvedTargetSceneActor {
    final actor = _targetSceneActor;
    return actor == null ? null : _resolveSceneActorVisuals(actor);
  }

  String get _resolvedTargetSceneActorImageSource {
    final actor = _resolvedTargetSceneActor;
    if (actor == null) return '';

    final avatar = actor.avatarUrl.trim();
    final portrait = actor.portraitUrl.trim();
    if (avatar.isEmpty && portrait.isEmpty) return '';
    return 'novel-target\u001F$avatar\u001F$portrait';
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
      debugPrint('刷新场景气泡失败：$error');
    }
  }

  void _requestStoryInputFocusAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _primaryTab != _NovelPrimaryTab.story ||
          !controller.storyStarted ||
          controller.isCinematic ||
          _battleOpen ||
          _endingOpen) {
        return;
      }
      _inputFocusNode.requestFocus();
    });
  }

  void _handleSceneBarkTap(NovelSceneBark bark) {
    if (!bark.clickable || bark.actor.cleanName.isEmpty) return;
    setState(() => _targetSceneActor = _resolveSceneActorVisuals(bark.actor));
  }

  void _handleTalkTargetTap(NovelSceneBarkActor actor) {
    if (actor.cleanName.isEmpty) return;
    setState(() => _targetSceneActor = _resolveSceneActorVisuals(actor));
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
    if (!controller.isInitialized || controller.isInitializing) return;

    if (_characterSetupOpen) return;

    if (controller.showCharacterSetup) {
      _characterSetupOpen = true;
      final started = await showNovelCharacterSetupDialog(context, controller);
      _characterSetupOpen = false;
      if (!mounted) return;

      if (started) {
        await Future<void>.delayed(const Duration(milliseconds: 90));
        if (mounted) {
          await _processOverlayRequests();
        }
      } else {
        await _returnToWorldMenuAfterCharacterSetupDismissed();
      }
      return;
    }
    if (controller.showOpening && !_openingOpen) {
      _openingOpen = true;
      final result = await showNovelOpeningDialog(context, controller);
      _openingOpen = false;
      if (!mounted) return;

      if (result == NovelOpeningResult.worldMenu) {
        await _returnToWorldMenuAfterCharacterSetupDismissed();
      } else {
        await controller.startNarrative();
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
    _sceneBarkRefreshTimer?.cancel();
    _sceneRecoveryTimer?.cancel();
    _inputFocusNode.removeListener(_onExplorationExitCheck);
    _inputController.removeListener(_onExplorationExitCheck);
    _inputController.dispose();
    _inputFocusNode.dispose();
    
    // 🌟 销毁摇杆控制器
    _joystickIntent.dispose();
    _joystickActive.dispose();
    
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
    await showNovelOpeningDialog(context, controller);
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
        const choiceBottomGap = 2.0;
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
          controller: controller,
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

  JsonMap _battleCompanionStateWithPortraitAvatar(JsonMap raw) {
    final normalized = <String, dynamic>{...raw};
    final portrait = stringValue(
      raw['portrait_url'] ??
          raw['portraitUrl'] ??
          raw['portrait'] ??
          raw['tachie'] ??
          raw['image_url'],
    ).trim();

    if (portrait.isNotEmpty) {
      normalized['avatar_url'] = portrait;
      normalized['avatarUrl'] = portrait;
      normalized['avatar'] = portrait;
    }
    return normalized;
  }

  JsonMap _battlePayloadWithPortraitAvatars(JsonMap payload) {
    final normalized = <String, dynamic>{...payload};

    dynamic normalizeList(dynamic value) {
      if (value is! List) return value;
      return value.map((item) {
        if (item is Map<String, dynamic>) {
          return _battleCompanionStateWithPortraitAvatar(item);
        }
        if (item is Map) {
          return _battleCompanionStateWithPortraitAvatar(
            item.map<String, dynamic>(
              (key, value) => MapEntry<String, dynamic>('$key', value),
            ),
          );
        }
        return item;
      }).toList(growable: false);
    }

    for (final key in <String>[
      'companions',
      'battle_companions',
      'deployed_companions',
      'allies',
      'party',
    ]) {
      if (normalized.containsKey(key)) {
        normalized[key] = normalizeList(normalized[key]);
      }
    }

    final player = asJsonMap(normalized['player']);
    if (player.isNotEmpty) {
      normalized['player'] = _battleCompanionStateWithPortraitAvatar(player);
    }

    return normalized;
  }

  List<YoranBattleCompanion> _currentBattleCompanions() {
    final result = <YoranBattleCompanion>[];
    final seen = <String>{};
    for (final raw in controller.novelCharacterRoster.values) {
      if (!boolValue(raw['deployed'])) continue;
      final companion = YoranBattleCompanion.fromState(
        _battleCompanionStateWithPortraitAvatar(raw),
      );
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
      battleId: setup.battleId,
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
    final playerScaledAttack =
        ratio * attackMultiplier / math.max(.5, incomingMultiplier);
    final attackRatio = ratio * .70 + playerScaledAttack * .30;
    final maxHp = (100 * ratio * .70 + playerMaxHp * ratio * .30)
        .round()
        .clamp(12, 1000)
        .toInt();
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
            YoranGeneratedBattleSetup.fromJson(
              _battlePayloadWithPortraitAvatars(response),
            ),
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
      onRetryBattle: () {
        return backend.retryBattleWithCatEyeStone(
          sessionId: controller.sessionId,
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
          final setup = YoranGeneratedBattleSetup.fromJson(
              _battlePayloadWithPortraitAvatars(response),
            );

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
      onRetryBattle: () {
        return controller.backend.retryBattleWithCatEyeStone(
          sessionId: controller.sessionId,
        );
      },
    );

    if (!mounted) return;
    if (outcome == null) {
      controller.abandonBattleStart(request.optionId);
      return;
    }

    if (request.fromSurroundings) {
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
      final setup = YoranGeneratedBattleSetup.fromJson(
              _battlePayloadWithPortraitAvatars(response),
            );
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
        battleId: battleId,
        onSettleItems: (consumptions, result) {
          return controller.settleStoryBattle(
            battleId: battleId,
            outcome: result.name,
            consumptions: consumptions
                .map((item) => item.toJson())
                .toList(growable: false),
          );
        },
        onRetryBattle: () {
          return controller.backend.retryBattleWithCatEyeStone(
            sessionId: controller.sessionId,
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

    try {
      await Future.wait<void>(<Future<void>>[
        controller.refreshCharacterStatus(notify: false),
        controller.refreshNovelCharacterRoster(notify: false),
      ]);
    } catch (_) {
    }
    if (!mounted) return;

    final protagonist = controller.protagonist;
    final battleSkills = _currentPreviewBattleSkills();
    final battleCompanions = _currentBattleCompanions();
    final battleInventory = _battleInventorySnapshot();

    await showYoranBattlePage(
      context,
      playerName: protagonist?.name.trim().isNotEmpty == true
          ? protagonist!.name.trim()
          : controller.protagonistName,
      playerAvatar: protagonist?.avatarUrl.trim() ?? '',
      playerPortrait: protagonist?.portraitUrl.trim() ?? '',
      skills: battleSkills,
      companions: battleCompanions,
      items: battleInventory,
      equipment: battleInventory,
      enemyName: '赛诺',
      enemyPortrait: 'assets/images/red_wolf.png',
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
      _backgroundPreviewFileName = '背景过渡测试';
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

      controller.clearMessages();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('场景载入异常，已自动为您返回首页'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );

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

  void _selectPrimaryTab(_NovelPrimaryTab tab) {
    if (_primaryTab == tab) {
      if (_characterOpenedFromAvatar) {
        setState(() => _characterOpenedFromAvatar = false);
      }
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();

    if (tab != _NovelPrimaryTab.story) {
      unawaited(controller.bgm.stopTypingSound());
    }
    setState(() {
      _characterOpenedFromAvatar = false;
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
      _characterFocusKey = key;
      _characterFocusRequestId++;
      _characterOpenedFromAvatar = true;
      _primaryTab = _NovelPrimaryTab.characters;
      _mountedPrimaryTabs.add(_NovelPrimaryTab.characters);
    });
  }

  void _openHostCharacterArchive() {
    final host = controller.protagonist;
    if (host == null) {
      FocusManager.instance.primaryFocus?.unfocus();
      unawaited(controller.bgm.stopTypingSound());
      setState(() {
        _characterOpenedFromAvatar = true;
        _primaryTab = _NovelPrimaryTab.characters;
        _mountedPrimaryTabs.add(_NovelPrimaryTab.characters);
      });
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
          onBackToStory: _characterOpenedFromAvatar
              ? () => _selectPrimaryTab(_NovelPrimaryTab.story)
              : null,
        ),
      _NovelPrimaryTab.team =>
        NovelTeamTab(controller: controller),
      _NovelPrimaryTab.inventory =>
        NovelInventoryTab(controller: controller),
      _NovelPrimaryTab.journey =>
        NovelJourneyTab(controller: controller),
      _NovelPrimaryTab.world =>                           
        NovelWorldMapTab(
          controller: controller,
          onMoveStarted: () => _selectPrimaryTab(_NovelPrimaryTab.story),
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
            
            // ✅ 将代码粘贴到这里：现在它们处于 AnimatedBuilder 内部
            // 这样每次文字打完、状态改变时，这里都会重新计算并实时显示摇杆
            final canExitStory = !controller.isGenerating &&
                                 !controller.isReaderRevealing &&
                                 !controller.hasNext;

            final isExploring = canExitStory && _joystickTouched;

            if (!canExitStory && _joystickTouched) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && _joystickTouched) {
                  setState(() => _joystickTouched = false);
                }
              });
            }
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
            novelDisplayMode.ensureInitialized(
              viewportWidth: rootMedia.size.width,
              nativeMobile: _isNativeMobilePlatform,
            );
            final desktopMode = controller.desktopMode;

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
                !keyboardActive;

            final gameScaffold = Scaffold(
              resizeToAvoidBottomInset: false,
              backgroundColor: controller.settings.backgroundColor,
              body: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  NovelExplorationPage(
                    backend: controller.backend,
                    controller: controller,
                    sessionId: controller.sessionId,
                    initialSceneName: controller.locationTitle.isNotEmpty 
                        ? controller.locationTitle 
                        : '斗破苍穹 乌坦城萧家坊市',
                    asLayer: true, 
                    canExitStory: canExitStory,
                    joystickIntent: _joystickIntent, 
                    joystickActive: _joystickActive, 
                    onExitStoryTriggered: () {
                      FocusManager.instance.primaryFocus?.unfocus();
                      if (!_joystickTouched) {
                        setState(() => _joystickTouched = true);
                      }
                    },
                  ),
                  
                  IgnorePointer(
                    ignoring: isExploring,
                    child: AnimatedOpacity(
                      opacity: isExploring ? 0.0 : 1.0,
                      duration: const Duration(milliseconds: 400),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                        child: Container(color: Colors.black.withOpacity(0.55)),
                      ),
                    ),
                  ),

                  RepaintBoundary(
                    child: AnimatedOpacity(
                      opacity: isExploring ? 0.0 : 1.0,
                      duration: const Duration(milliseconds: 300),
                      child: _NovelStoryboardStage(
                        controller: controller,
                        fallbackAsset: widget.fallbackBackgroundAsset.trim().isNotEmpty
                            ? widget.fallbackBackgroundAsset.trim()
                            : 'assets/images/background_home.png',
                        weatherEffect: (_weatherPreviewOverride != null ||
                                controller.settings.weatherEffectsEnabled)
                            ? _activeWeatherEffect
                            : NovelWeatherEffect.none,
                        timePeriod: _activeTimePeriod,
                        parallaxStrength: _backgroundParallaxStrength,
                        backgroundPreviewBytes: _backgroundPreviewBytes,
                        backgroundPreviewUrl: _backgroundPreviewOverride ?? '',
                        backgroundPreviewCacheKey:
                            'developer-background-$_backgroundPreviewVersion',
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
                        return Stack(
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

                            if (!_immersiveInputMode &&
                                !desktopMode &&
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

                            if (!_immersiveInputMode && controller.storyStarted && !keyboardActive)
                              Positioned(
                                left: 0,
                                top: shortWide ? 48 : 56, 
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
                                          const SizedBox(height: 6),
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
                                key: const ValueKey<String>('novel-story-reader-stage'),
                                alignment: Alignment.bottomCenter,
                                child: Padding(
                                  padding: EdgeInsets.zero,
                                  child: SizedBox(
                                    width: desktopMode
                                        ? constraints.maxWidth
                                        : math.min(720.0, constraints.maxWidth),
                                    child: NovelChoiceDockActionScope(
                                      visible: false,
                                      label: '',
                                      attention: false,
                                      loading: false,
                                      onTap: () {},
                                      child: NovelDialogPanel(
                                        controller: controller,
                                        isExploring: isExploring, 
                                        bottomReservedHeight: 0,
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
                                            _resolvedTargetSceneActorImageSource,
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
                                !controller.hasNext &&
                                !controller.isGenerating &&
                                !controller.forcedBattlePending &&
                                !_sceneArrivalActive &&
                                !_battleOpen &&
                                !_endingOpen &&
                                _talkTargets.isNotEmpty)
                              Positioned(
                                // 【修改这里】：加大右边距，把附近角色头像往左推，避开右侧垂直按钮
                                right: shortWide ? 84.0 : (compact ? 56.0 : 64.0), // 原来是 (compact ? 6.0 : 14.0)
                                top: shortWide ? 106 : 136,
                                bottom: shortWide ? 84 : 212,
                                child: Transform.scale(
                                  scale: shortWide
                                      ? 1.30
                                      : (compact ? 1.26 : 1.10),
                                  alignment: Alignment.topRight,
                                  child: NovelRightSceneDock(
                                    targets: _resolvedTalkTargets,
                                    selectedActorId:
                                        _resolvedTargetSceneActor?.id ?? '',
                                    onSelected: _handleTalkTargetTap,
                                    onClear: _clearTargetSceneActor,
                                    exploreVisible: false,
                                    exploreLabel: '',
                                    exploreAttention:
                                        false,
                                    exploreLoading:
                                        false,
                                    onExplore: () {},
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
                                  enabled: true,
                                  bottomReserve: 0,
                                  onBarkTap: _handleSceneBarkTap,
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

                  if (showBottomNav)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: SafeArea(
                        top: false,
                        child: NovelBottomArchiveBar(
                          desktopMode: desktopMode,
                          selectedIndex: switch (_primaryTab) {
                            _NovelPrimaryTab.characters => 1,
                            _NovelPrimaryTab.team => 2,
                            _NovelPrimaryTab.inventory => 3,
                            _NovelPrimaryTab.journey => 4,
                            _NovelPrimaryTab.world => 5,
                            _ => 0, 
                          },
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

                  // 最顶层的公共摇杆，与剧情和输入框完全共存
                  if (canExitStory)
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOutCubic,
                      left: 24,
                      bottom: MediaQuery.sizeOf(context).height * 0.32,
                      child: AnimatedOpacity(
                        opacity: 1.0,
                        duration: const Duration(milliseconds: 250),
                        child: NovelExplorationJoystick(
                          onChanged: (val) {
                            _joystickIntent.value = val;
                            if (val != Offset.zero && !_joystickTouched) {
                              setState(() => _joystickTouched = true);
                              FocusManager.instance.primaryFocus?.unfocus();
                            }
                          },
                          onActiveChanged: (val) {
                            _joystickActive.value = val;
                            if (val && !_joystickTouched) {
                              setState(() => _joystickTouched = true);
                              FocusManager.instance.primaryFocus?.unfocus();
                            }
                          },
                        ),
                      ),
                    ),

                  if (_primaryTab == _NovelPrimaryTab.story &&
                      controller.showStoryBrewing)
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

class _NovelStoryboardStage extends StatefulWidget {
  const _NovelStoryboardStage({
    required this.controller,
    required this.fallbackAsset,
    required this.weatherEffect,
    required this.timePeriod,
    required this.parallaxStrength,
    this.backgroundPreviewBytes,
    this.backgroundPreviewUrl = '',
    this.backgroundPreviewCacheKey = '',
  });

  final NovelGameController controller;
  final String fallbackAsset;
  final NovelWeatherEffect weatherEffect;
  final NovelTimePeriod timePeriod;
  final double parallaxStrength;
  final Uint8List? backgroundPreviewBytes;
  final String backgroundPreviewUrl;
  final String backgroundPreviewCacheKey;

  @override
  State<_NovelStoryboardStage> createState() => _NovelStoryboardStageState();
}

class _NovelStoryboardStageState extends State<_NovelStoryboardStage> {
  final Set<String> _preloadedUrls = <String>{};

  Set<String>? _preloadingUrlsStore;
  String? _displayedStoryboardUrlStore;
  String? _displayedStoryboardTurnIdStore;
  String? _lastLocationKeyStore;
  String? _lastWorldBackgroundUrlStore;
  bool? _awaitingSceneBackgroundStore;
  int? _promoteTokenStore;
  String? _promotingUrlStore;
  Map<String, int>? _promoteFailureCountsStore;

  Map<String, int> get _promoteFailureCounts =>
      _promoteFailureCountsStore ??= <String, int>{};

  Set<String> get _preloadingUrls =>
      _preloadingUrlsStore ??= <String>{};

  String get _displayedStoryboardUrl =>
      _displayedStoryboardUrlStore?.trim() ?? '';
  set _displayedStoryboardUrl(String value) =>
      _displayedStoryboardUrlStore = value;

  String get _displayedStoryboardTurnId =>
      _displayedStoryboardTurnIdStore?.trim() ?? '';
  set _displayedStoryboardTurnId(String value) =>
      _displayedStoryboardTurnIdStore = value;

  String get _lastLocationKey => _lastLocationKeyStore?.trim() ?? '';
  set _lastLocationKey(String value) => _lastLocationKeyStore = value;

  String get _lastWorldBackgroundUrl =>
      _lastWorldBackgroundUrlStore?.trim() ?? '';
  set _lastWorldBackgroundUrl(String value) =>
      _lastWorldBackgroundUrlStore = value;

  bool get _awaitingSceneBackground => _awaitingSceneBackgroundStore ?? false;
  set _awaitingSceneBackground(bool value) =>
      _awaitingSceneBackgroundStore = value;

  int get _promoteToken => _promoteTokenStore ?? 0;
  set _promoteToken(int value) => _promoteTokenStore = value;

  String get _promotingUrl => _promotingUrlStore?.trim() ?? '';
  set _promotingUrl(String value) => _promotingUrlStore = value;

  String get _sessionKey => widget.controller.sessionId.trim();

  String _permanentSceneBackgroundUrl() {
    final sceneUrl = widget.controller.currentSceneBackdropUrl.trim();
    return sceneUrl.isNotEmpty
        ? sceneUrl
        : widget.controller.world.backgroundUrl.trim();
  }

  String _locationKey() => <String>[
        widget.controller.locationTitle.trim(),
        widget.controller.locationSubtitle.trim(),
      ].join('\u0001');

  @override
  void initState() {
    super.initState();
    _lastLocationKey = _locationKey();
    _lastWorldBackgroundUrl = _permanentSceneBackgroundUrl();
    _displayedStoryboardTurnId = widget.controller.currentStoryboardTurnId;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scheduleVisualSync();
  }

  @override
  void didUpdateWidget(covariant _NovelStoryboardStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldSession = oldWidget.controller.sessionId.trim();
    if (oldSession != _sessionKey) {
      _promoteToken += 1;
      _displayedStoryboardUrl = '';
      _displayedStoryboardTurnId = widget.controller.currentStoryboardTurnId;
      _lastLocationKey = _locationKey();
      _lastWorldBackgroundUrl = _permanentSceneBackgroundUrl();
      _awaitingSceneBackground = false;
    }
    _scheduleVisualSync();
  }

  ImageProvider _providerFor(String source) {
    final value = source.trim();
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return NetworkImage(value);
    }
    return AssetImage(value);
  }

  void _scheduleVisualSync() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncVisualState();
    });
  }

  void _syncVisualState() {
    final controller = widget.controller;
    if (controller.isGenerating) {
      if (_displayedStoryboardUrl.isNotEmpty || _promotingUrl.isNotEmpty) {
        _promoteToken += 1;
        _promotingUrl = '';
      }
      if (_displayedStoryboardUrl.isNotEmpty) {
        setState(() => _displayedStoryboardUrl = '');
      }
      return;
    }
    final currentTurnId = controller.currentStoryboardTurnId.trim();
    if (_displayedStoryboardTurnId != currentTurnId) {
      _promoteToken += 1;
      _promotingUrl = '';
      _displayedStoryboardTurnId = currentTurnId;
      if (_displayedStoryboardUrl.isNotEmpty) {
        setState(() => _displayedStoryboardUrl = '');
      }
    }
    final nextLocation = _locationKey();
    final nextWorldBackground = _permanentSceneBackgroundUrl();
    final locationChanged = _lastLocationKey.isNotEmpty &&
        nextLocation.isNotEmpty &&
        nextLocation != _lastLocationKey;
    if (locationChanged) {
      _awaitingSceneBackground = true;
    }
    _lastLocationKey = nextLocation;

    if (_awaitingSceneBackground &&
        nextWorldBackground.isNotEmpty &&
        nextWorldBackground != _lastWorldBackgroundUrl) {
      _lastWorldBackgroundUrl = nextWorldBackground;
      _awaitingSceneBackground = false;
      if (_displayedStoryboardUrl.isNotEmpty) {
        _releaseStoryboardAfterSceneBackground(nextWorldBackground, nextLocation);
        return;
      }
    }

    if (!_awaitingSceneBackground && nextWorldBackground.isNotEmpty) {
      _lastWorldBackgroundUrl = nextWorldBackground;
    }

    final currentCandidate = controller.currentStoryboardDisplayCandidateUrl.trim();
    final currentReadyImage = controller.currentStoryboardReadyImageUrl.trim();
    final hasTimeline = controller.currentStoryboardShots.isNotEmpty;
    final currentSheetUrls = controller.currentStoryboardSheetUrls;
    final singleReadyCurrentTurn =
        currentSheetUrls.length == 1 && currentReadyImage.isNotEmpty;

    final preferredCandidate = currentCandidate.isNotEmpty
        ? currentCandidate
        : ((!hasTimeline || (!controller.hasNext && singleReadyCurrentTurn))
            ? currentReadyImage
            : '');
    if (preferredCandidate.isNotEmpty &&
        preferredCandidate != _displayedStoryboardUrl) {
      unawaited(_promoteStoryboard(preferredCandidate));
      return;
    }

    _schedulePreload();
  }

  Future<void> _releaseStoryboardAfterSceneBackground(
    String backgroundUrl,
    String expectedLocation,
  ) async {
    final token = ++_promoteToken;
    try {
      await precacheImage(_providerFor(backgroundUrl), context);
    } catch (_) {
      return;
    }
    if (!mounted || token != _promoteToken || _locationKey() != expectedLocation) {
      return;
    }
    setState(() {
      _displayedStoryboardUrl = '';
    });
    _scheduleVisualSync();
  }

  Future<void> _promoteStoryboard(String url) async {
    final clean = url.trim();
    if (clean.isEmpty ||
        clean == _displayedStoryboardUrl ||
        clean == _promotingUrl) {
      return;
    }

    _promotingUrl = clean;
    final token = ++_promoteToken;
    try {
      await precacheImage(NetworkImage(clean), context);
    } catch (error) {
      if (_promotingUrl == clean) _promotingUrl = '';
      final attempt = (_promoteFailureCounts[clean] ?? 0) + 1;
      _promoteFailureCounts[clean] = attempt;
      debugPrint(
        '[StoryboardStage] preload failed; keep previous. next=$clean attempt=$attempt error=$error',
      );
      if (attempt <= 2) {
        Future<void>.delayed(const Duration(milliseconds: 900), () {
          if (!mounted || _displayedStoryboardUrl == clean) return;
          final current = widget.controller.currentStoryboardDisplayCandidateUrl.trim();
          final ready = widget.controller.currentStoryboardReadyImageUrl.trim();
          if (current == clean || ready == clean) _scheduleVisualSync();
        });
      }
      return;
    }
    if (!mounted || token != _promoteToken) {
      if (_promotingUrl == clean) _promotingUrl = '';
      return;
    }

    if (_promotingUrl == clean) _promotingUrl = '';
    _promoteFailureCounts.remove(clean);
    _preloadedUrls.add(clean);
    _preloadingUrls.remove(clean);
    setState(() {
      _displayedStoryboardUrl = clean;
      _displayedStoryboardTurnId = widget.controller.currentStoryboardTurnId.trim();
    });
  }

  void _schedulePreload() {
    final urls = <String>{
      ...widget.controller.currentStoryboardSheetUrls,
      widget.controller.currentStoryboardDisplayCandidateUrl,
    }..removeWhere((url) => url.trim().isEmpty);
    if (urls.isEmpty) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final rawUrl in urls) {
        final url = rawUrl.trim();
        if (url.isEmpty ||
            _preloadedUrls.contains(url) ||
            !_preloadingUrls.add(url)) {
          continue;
        }
        precacheImage(NetworkImage(url), context).then((_) {
          _preloadingUrls.remove(url);
          _preloadedUrls.add(url);
        }).catchError((_) {
          _preloadingUrls.remove(url);
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final previewBytes = widget.backgroundPreviewBytes;
    final hasMemoryPreview = previewBytes != null && previewBytes.isNotEmpty;
    final previewUrl = widget.backgroundPreviewUrl.trim();
    final displayedStoryboardUrl = _displayedStoryboardUrl;
    final worldBackgroundUrl = _permanentSceneBackgroundUrl();

    final selectedUrl = previewUrl.isNotEmpty
        ? previewUrl
        : displayedStoryboardUrl.isNotEmpty
            ? displayedStoryboardUrl
            : worldBackgroundUrl;

    final Widget visual = hasMemoryPreview || selectedUrl.isNotEmpty
        ? NovelWorldBackground(
            url: hasMemoryPreview ? '' : selectedUrl,
            memoryBytes: hasMemoryPreview ? previewBytes : null,
            memoryCacheKey:
                hasMemoryPreview ? widget.backgroundPreviewCacheKey : '',
            parallaxStrength: widget.parallaxStrength,
            fallbackAsset: widget.fallbackAsset,
            storyboardMode: false,
            characterPresent: false,
            isGenerating: controller.isGenerating,
            weatherEffect: widget.weatherEffect,
            timePeriod: widget.timePeriod,
          )
        : _NovelStoryboardPlaceholder(fallbackAsset: widget.fallbackAsset);

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        visual,
        IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[
                  Colors.black.withOpacity(.10),
                  Colors.transparent,
                  Colors.black.withOpacity(.10),
                ],
                stops: const <double>[0, .56, 1],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _NovelStoryboardPlaceholder extends StatelessWidget {
  const _NovelStoryboardPlaceholder({
    super.key,
    required this.fallbackAsset,
  });

  final String fallbackAsset;

  @override
  Widget build(BuildContext context) {
    final asset = fallbackAsset.trim();
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        const ColoredBox(color: Color(0xFF090A0C)),
        if (asset.isNotEmpty)
          Opacity(
            opacity: .16,
            child: Image.asset(
              asset,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
      ],
    );
  }
}
