import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../api/message_api.dart';
import 'novel_backend.dart';
import 'novel_bgm_service.dart';
import 'novel_models.dart';
import 'novel_settings_service.dart';
import 'novel_socket_service.dart';
import 'novel_text_parser.dart';

RegExp _buildNovelReadableCharacterPattern() {
  try {
    // 优先按 Unicode 字母/数字判断，兼容中文、英文及其它语言。
    return RegExp(r'[\p{L}\p{N}]', unicode: true);
  } on FormatException {
    // 兼容少数较旧、尚不支持 Unicode property escapes 的 Dart 运行时。
    return RegExp(
      r'[A-Za-z0-9\u00C0-\u02AF\u0370-\u052F\u0531-\u058F'
      r'\u05D0-\u05EA\u0620-\u06FF\u0900-\u097F\u0E00-\u0E7F'
      r'\u3040-\u30FF\u3400-\u9FFF\uAC00-\uD7AF]',
      unicode: true,
    );
  }
}

final RegExp _novelReadableCharacterPattern =
    _buildNovelReadableCharacterPattern();

/// 一行至少包含一个字母或数字，才算真正的剧情内容。
/// 纯空白、纯标点、纯装饰符号（例如“……”“---”“【】”）不应占据正文行。
bool novelTextHasReadableContent(String value) {
  return value.isNotEmpty && _novelReadableCharacterPattern.hasMatch(value);
}

/// 删除正文中没有任何文字/数字的整行。
/// 正常的单换行必须保留；空行、纯空格行或纯符号行被移除后，
/// 相邻正文之间只留下一个换行，避免出现双换行空白。
String novelTextWithoutSymbolOnlyLines(String value) {
  if (value.isEmpty) return value;
  // sentenceItems 偶尔会把换行保留成字面量 "\\n"；显示前统一还原。
  // 流式正文通常已经是真换行，这几步对它没有副作用。
  final normalized = value
      .replaceAll(r'\r\n', '\n')
      .replaceAll(r'\n', '\n')
      .replaceAll(r'\r', '\n')
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .replaceAll('\u2028', '\n')
      .replaceAll('\u2029', '\n');
  return normalized
      .split('\n')
      // 只清理行尾无意义空格；保留有效正文原本的行首排版。
      .map((line) => line.trimRight())
      .where(novelTextHasReadableContent)
      .join('\n');
}

typedef NovelSceneMapLoader = Future<Map<String, dynamic>> Function(
  String sessionId,
);

typedef NovelSceneMoveIntentCreator = Future<Map<String, dynamic>> Function(
  String sessionId,
  String targetSceneId,
);

typedef NovelNavigationStreamSender = Stream<NovelStreamEvent> Function(
  NovelSendRequest request,
  Map<String, dynamic> navigationAction,
);

typedef NovelDeveloperSkillAdder = Future<Map<String, dynamic>> Function(
  String sessionId,
  String skillName,
);

typedef NovelBattleStarter = Future<JsonMap> Function(
  String sessionId,
  String battleOptionId,
);


class NovelPendingBattleStart {
  const NovelPendingBattleStart({
    required this.optionId,
    required this.targetName,
    required this.battleMode,
    required this.loadPayload,
    this.fromSurroundings = false,
  });

  final String optionId;
  final String targetName;
  final String battleMode;
  final bool fromSurroundings;

  /// 每次调用都重新发起一次后端战斗生成请求，供 Battle 加载页失败后原地重试。
  final Future<JsonMap> Function() loadPayload;
}

typedef NovelBattleSettler = Future<JsonMap> Function(
  String sessionId,
  String battleId,
  String outcome,
  List<JsonMap> consumptions,
);

Map<String, dynamic> _sceneJsonMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map<String, dynamic>(
      (key, item) => MapEntry<String, dynamic>('$key', item),
    );
  }
  return <String, dynamic>{};
}

String _sceneString(dynamic value) => value?.toString().trim() ?? '';

bool _sceneBool(dynamic value, {bool fallback = false}) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  final normalized = _sceneString(value).toLowerCase();
  if (normalized == 'true' || normalized == '1' || normalized == 'yes') {
    return true;
  }
  if (normalized == 'false' || normalized == '0' || normalized == 'no') {
    return false;
  }
  return fallback;
}

String _sceneAssetImageUrl(JsonMap asset) {
  final package = _sceneJsonMap(asset['asset_package']);
  final floor = _sceneJsonMap(package['floor']);
  return _sceneString(
    asset['backdrop_url'] ??
        asset['scene_image_url'] ??
        floor['url'],
  );
}

/// 节点既可来自一跳导航目标，也可来自“已发现的大场景”列表；未来节点不会下发。
class NovelSceneMapNode {
  const NovelSceneMapNode({
    this.sceneId = '',
    this.name = '',
    this.regionId = '',
    this.imageUrl = '',
    this.description = '',
    this.connectionId = '',
    this.exitName = '',
    this.moveState = 'locked',
    this.reason = '',
    this.requiresCheck = false,
    this.discovered = false,
    this.visited = false,
    this.unlocked = false,
    this.presentNpcs = const <String>[],
    this.sceneScope = 'major',
    this.parentSceneId = '',
    this.routeKind = '',
    this.destinationSpawn = '',
    this.navigationTrigger = const <String, dynamic>{},
    this.sceneAsset = const <String, dynamic>{},
  });

  final String sceneId;
  final String name;
  final String regionId;
  /// 世界地图方形板块使用的场景图片；支持网络 URL 与 Flutter asset 路径。
  final String imageUrl;
  final String description;
  final String connectionId;
  final String exitName;
  final String moveState;
  final String reason;
  final bool requiresCheck;
  final bool discovered;
  final bool visited;
  final bool unlocked;
  final List<String> presentNpcs;
  final String sceneScope;
  final String parentSceneId;
  final String routeKind;
  final String destinationSpawn;
  final JsonMap navigationTrigger;
  final JsonMap sceneAsset;

  bool get isAvailable => moveState == 'available';
  bool get isRisky => moveState == 'risky';
  bool get isLocked => !isAvailable && !isRisky;
  bool get isUnlocked => unlocked || visited || isAvailable || isRisky;
  bool get isMajorScene => sceneScope == 'major';
  String get triggerType => _sceneString(navigationTrigger['type']).toLowerCase();
  String get triggerSide => _sceneString(navigationTrigger['side']).toLowerCase();
  String get triggerObjectId => _sceneString(
        navigationTrigger['scene_object_id'] ?? navigationTrigger['object_id'],
      );

  factory NovelSceneMapNode.fromDynamic(dynamic value) {
    final data = _sceneJsonMap(value);
    final rawNpcs = data['present_npcs'];
    final sceneAsset = _sceneJsonMap(data['scene_asset']);
    final directImage = _sceneString(
      data['map_tile_url'] ??
          data['world_map_image_url'] ??
          data['image_url'] ??
          data['scene_image_url'] ??
          data['image'],
    );
    return NovelSceneMapNode(
      sceneId: _sceneString(data['scene_id']),
      name: _sceneString(data['name']),
      regionId: _sceneString(data['region_id']),
      imageUrl: directImage.isNotEmpty
          ? directImage
          : _sceneAssetImageUrl(sceneAsset),
      description: _sceneString(data['description']),
      connectionId: _sceneString(data['connection_id']),
      exitName: _sceneString(data['exit_name']),
      moveState: _sceneString(data['move_state']).toLowerCase().isEmpty
          ? 'locked'
          : _sceneString(data['move_state']).toLowerCase(),
      reason: _sceneString(data['reason']),
      requiresCheck: _sceneBool(data['requires_check']),
      discovered: _sceneBool(data['discovered'], fallback: true),
      visited: _sceneBool(data['visited']),
      unlocked: data.containsKey('unlocked')
          ? _sceneBool(data['unlocked'])
          : const <String>{'available', 'risky'}.contains(
              _sceneString(data['move_state']).toLowerCase(),
            ),
      presentNpcs: rawNpcs is List
          ? rawNpcs
              .map(_sceneString)
              .where((item) => item.isNotEmpty)
              .toList(growable: false)
          : const <String>[],
      sceneScope: _sceneString(data['scene_scope']).isEmpty
          ? 'major'
          : _sceneString(data['scene_scope']).toLowerCase(),
      parentSceneId: _sceneString(data['parent_scene_id']),
      routeKind: _sceneString(data['route_kind']).toLowerCase(),
      destinationSpawn: _sceneString(data['destination_spawn']),
      navigationTrigger: _sceneJsonMap(data['navigation_trigger']),
      sceneAsset: sceneAsset,
    );
  }
}

class NovelSceneMobility {
  const NovelSceneMobility({
    this.canOpenMap = true,
    this.status = 'available',
    this.reason = '',
    this.combatActive = false,
  });

  final bool canOpenMap;
  final String status;
  final String reason;
  final bool combatActive;

  bool get canMove => status == 'available';

  factory NovelSceneMobility.fromDynamic(dynamic value) {
    final data = _sceneJsonMap(value);
    final status = _sceneString(data['status']).toLowerCase();
    return NovelSceneMobility(
      canOpenMap: _sceneBool(data['can_open_map'], fallback: true),
      status: status.isEmpty ? 'available' : status,
      reason: _sceneString(data['reason']),
      combatActive: _sceneBool(data['combat_active']),
    );
  }
}

class NovelSceneMapData {
  const NovelSceneMapData({
    this.configured = false,
    this.currentSceneId = '',
    this.currentScene = const NovelSceneMapNode(),
    this.mobility = const NovelSceneMobility(),
    this.targets = const <NovelSceneMapNode>[],
    this.majorScenes = const <NovelSceneMapNode>[],
  });

  final bool configured;
  final String currentSceneId;
  final NovelSceneMapNode currentScene;
  final NovelSceneMobility mobility;
  final List<NovelSceneMapNode> targets;
  final List<NovelSceneMapNode> majorScenes;

  bool get hasCurrentScene =>
      currentSceneId.isNotEmpty || currentScene.name.isNotEmpty;

  factory NovelSceneMapData.fromDynamic(dynamic value) {
    final data = _sceneJsonMap(value);
    final rawTargets = data['targets'];
    final rawMajorScenes = data['major_scenes'];
    return NovelSceneMapData(
      configured: _sceneBool(data['configured']),
      currentSceneId: _sceneString(data['current_scene_id']),
      currentScene: NovelSceneMapNode.fromDynamic(data['current_scene']),
      mobility: NovelSceneMobility.fromDynamic(data['mobility']),
      targets: rawTargets is List
          ? rawTargets
              .map(NovelSceneMapNode.fromDynamic)
              .where((item) => item.sceneId.isNotEmpty || item.name.isNotEmpty)
              .toList(growable: false)
          : const <NovelSceneMapNode>[],
      majorScenes: rawMajorScenes is List
          ? rawMajorScenes
              .map(NovelSceneMapNode.fromDynamic)
              .where((item) => item.sceneId.isNotEmpty || item.name.isNotEmpty)
              .toList(growable: false)
          : const <NovelSceneMapNode>[],
    );
  }
}

class NovelHudEvent {
  const NovelHudEvent({
    required this.id,
    required this.kind,
    required this.title,
    this.detail = '',
    this.delta = 0,
    this.tone = 'neutral',
  });

  final int id;
  final String kind;
  final String title;
  final String detail;
  final int delta;
  final String tone;
}

/// 小说首次进入流程只有一个权威状态，避免 showOpening / storyStarted /
/// showCharacterSetup 三个布尔值互相打架。
enum NovelLaunchPhase {
  characterSetup,
  opening,
  startingNarrative,
  story,
}

/// 好感变化不再使用全屏 HUD 卡片。
/// 事件会暂存在 Controller，等对应角色真正出现在当前对白时，
/// 再让角色名旁边的爱心与数字做一次局部放大反馈。
class NovelAffectionPulse {
  const NovelAffectionPulse({
    required this.id,
    required this.characterId,
    required this.characterName,
    required this.delta,
  });

  final int id;
  final String characterId;
  final String characterName;
  final int delta;
}

class NovelGameController extends ChangeNotifier {
  NovelGameController({
    required this.scenarioId,
    required this.sessionId,
    required this.backend,
    required this.socket,
    required this.bgm,
    required this.settings,
    NovelTextParser? parser,
    this.sceneMapLoader,
    this.sceneMoveIntentCreator,
    this.navigationStreamSender,
    this.developerSkillAdder,
    this.battleStarter,
    this.battleSettler,
  }) : parser = parser ?? const NovelTextParser() {
    settings.addListener(_onSettingsChanged);
  }

  final String scenarioId;
  final String sessionId;
  final NovelBackend backend;
  final NovelSocketService socket;
  final NovelBgmService bgm;
  final NovelSettingsService settings;
  final NovelTextParser parser;
  final NovelSceneMapLoader? sceneMapLoader;
  final NovelSceneMoveIntentCreator? sceneMoveIntentCreator;
  final NovelNavigationStreamSender? navigationStreamSender;
  final NovelDeveloperSkillAdder? developerSkillAdder;
  final NovelBattleStarter? battleStarter;
  final NovelBattleSettler? battleSettler;

  NovelScenario? scenario;
  NovelWorldState world = const NovelWorldState();
  NovelStoryClock storyClock = const NovelStoryClock(enabled: false);
  /// 最近一次 /scene-map 的完整权威快照。剧情页的可对话角色与地图共用它，
  /// 避免页面再发第二次请求而读到不同结算阶段的数据。
  JsonMap sceneMapPayload = <String, dynamic>{};
  int sceneMapRevision = 0;
  List<NovelMessage> messages = <NovelMessage>[];
  List<NovelSentence> sentences = <NovelSentence>[];
  List<NovelChoice> choices = <NovelChoice>[];
  String playerHint = '';
  NovelScore score = const NovelScore();
  NovelTask? currentTask;

  // 当前阶段目标：独立于旧 task 系统。后端 StoryNode.goal 会转成玩家视角后传入。
  String currentGoal = '';
  String currentGoalNodeId = '';
  int currentGoalIndex = 0;
  int currentGoalTotal = 0;
  bool currentGoalEnded = false;

  NovelDiceRoll? diceRoll;
  NovelEnding ending = const NovelEnding();
  FateRevertData fateRevert = const FateRevertData();
  NovelInventoryData inventory = const NovelInventoryData();
  List<NovelShopItem> shopItems = <NovelShopItem>[];
  JsonMap journey = <String, dynamic>{};
  NovelSceneMapData sceneMap = const NovelSceneMapData();
  JsonMap surroundingsAvailability = <String, dynamic>{};
  JsonMap surroundingsData = <String, dynamic>{};
  NovelHudEvent? hudEvent;
  bool isSceneMapLoading = false;
  bool isSceneMoveSubmitting = false;
  bool isSurroundingsAvailabilityLoading = false;
  bool _surroundingsAvailabilityRefreshPending = false;
  int _surroundingsAvailabilityPollTicket = 0;
  bool isSurroundingsLoading = false;
  bool isSurroundingsActionRunning = false;
  bool isReaderRevealing = false;
  String sceneMapError = '';
  String sceneMoveError = '';
  String surroundingsError = '';
  DateTime? _lastSceneMapRefreshAt;
  bool isBackgroundGenerating = false;
  bool isStartingBattle = false;
  NovelPendingBattleStart? _pendingBattleStart;
  JsonMap? _pendingBattle;
  String _activeBattleOptionId = '';

  // 后端已经确认“攻击已经发动”的强制战斗。它与 Battle route 分离：
  // 玩家仍可把本轮正文读完，但不能再用自由输入/快捷选项开启新的剧情回合。
  JsonMap _forcedBattleTrigger = <String, dynamic>{};

  bool get forcedBattlePending =>
      boolValue(_forcedBattleTrigger['required']) &&
      intValue(_forcedBattleTrigger['source_message_id']) > 0;

  bool get forcedBattleReady =>
      forcedBattlePending &&
      !isGenerating &&
      !hasNext &&
      !isReaderRevealing &&
      !isStartingBattle;

  String get forcedBattleTargetName {
    final target = asJsonMap(_forcedBattleTrigger['target']);
    final name = stringValue(target['name']).trim();
    return name.isEmpty ? '当前敌人' : name;
  }
  final Map<String, String> characterExpressions = <String, String>{};
  int novelCharacterFlowers = 0;
  Map<String, JsonMap> novelCharacterRoster = <String, JsonMap>{};
  bool isNovelCharacterRosterLoading = false;
  // 区分“后端权威 roster 尚未读取”和“角色真实为 0 星”。
  // UI 不应在首次请求完成前把未知星级当成 0 星展示。
  bool hasLoadedNovelCharacterRoster = false;
  /// 正在自动生成立绘的角色 id 集合（素材库未命中时后端触发），供 UI 显示"生成中"占位
  final Set<String> generatingPortraitCharacterIds = <String>{};


  String _normalizeWorldTimePeriodKey(String raw) {
    final value = raw.trim().toLowerCase().replaceAll('-', '_').replaceAll(' ', '_');
    if (value == 'morning') return 'morning';
    if (value == 'noon') return 'noon';
    if (value == 'afternoon') return 'afternoon';
    if (value == 'evening') return 'evening';
    if (value == 'night') return 'night';
    if (value == 'midnight') return 'midnight';
    if (value.contains('凌晨') || value.contains('深夜')) return 'midnight';
    if (value.contains('夜晚') || value.contains('晚上')) return 'night';
    if (value.contains('傍晚') || value.contains('黄昏')) return 'evening';
    if (value.contains('下午') || value.contains('午后')) return 'afternoon';
    if (value.contains('中午') || value.contains('正午')) return 'noon';
    if (value.contains('清晨') || value.contains('早晨') || value.contains('上午')) return 'morning';
    return '';
  }

  String get effectiveWorldTimePeriodKey {
    // story_clock 是唯一时间真值。没有建立时钟前使用中性 noon 光照，
    // 不再从 time_desc / time_label 反向猜当前时间。
    final clockPeriod = _normalizeWorldTimePeriodKey(storyClock.periodKey);
    return clockPeriod.isNotEmpty ? clockPeriod : 'noon';
  }

  String get storyTimeDisplay => storyClock.displayLabel;

  void _applyStoryClock(dynamic raw) {
    final data = asJsonMap(raw);
    if (data.isEmpty) return;
    final next = NovelStoryClock.fromDynamic(data);
    storyClock = next;

    // NovelWorldState 里的旧展示字段继续作为单向投影供现有 UI 使用，
    // 但永远不能反过来成为时间来源。
    world = world.copyWith(
      timeDescription: next.timeDescription,
      timeLabel: next.dayLabel,
      currentDay: next.dayIndex,
    );
  }

  /// 远端 AI 模型配置。Vue 原版把这部分散在 index.vue；
  /// Flutter 收拢到 Controller，页面只负责展示和选择。
  List<NovelModelOption> availableModels = <NovelModelOption>[];
  String currentNovelModel = '';
  bool isChangingModel = false;

  bool isInitializing = false;
  bool isInitialized = false;
  bool isGenerating = false;
  bool isSyncingHistory = false;
  bool isRecoveringConnection = false;
  bool _authoritativeRecoveryPending = false;
  bool isReverting = false;
  NovelLaunchPhase _launchPhase = NovelLaunchPhase.characterSetup;
  bool showEnding = false;
  bool showEndingIntro = false;
  bool isCinematic = false;
  bool choicesVisible = false;
  bool pendingFateRevert = false;
  bool showFateRevert = false;
  bool showDice = false;
  bool taskCompleted = false;
  bool insufficientBalance = false;
  bool luckyCardActive = false;

  NovelLaunchPhase get launchPhase => _launchPhase;
  bool get showCharacterSetup => _launchPhase == NovelLaunchPhase.characterSetup;
  bool get showOpening => _launchPhase == NovelLaunchPhase.opening;
  bool get isStartingNarrative =>
      _launchPhase == NovelLaunchPhase.startingNarrative;
  bool get storyStarted =>
      _launchPhase == NovelLaunchPhase.startingNarrative ||
      _launchPhase == NovelLaunchPhase.story;

  /// “故事正在展开”只属于正文生成，不属于 Storyboard 图片生成。
  /// 新一轮第一张可阅读页到达后立即隐藏。
  bool get showStoryBrewing =>
      storyStarted && isGenerating && !_generationHasReadablePage && !showDice;

  void _setLaunchPhase(NovelLaunchPhase next, {bool notify = true}) {
    if (_launchPhase == next) return;
    _launchPhase = next;
    if (notify) _notify();
  }

  String protagonistCondition = '健康';
  List<dynamic> protagonistInjuries = <dynamic>[];
  String openingText = '';
  String lastError = '';
  String infoMessage = '';
  String timeSkipLabel = '';

  // Writer/provider 拒绝是“生成失败态”，不是场景错误。
  // 单独保存一次性通知，绝不能塞进 lastError，否则 NovelGamePage 会误启动场景恢复。
  JsonMap? _pendingGenerationNotice;
  int currentTurn = 0;
  int currentSentenceIndex = 0;
  int luckyCardCount = 0;

  // Storyboard is keyed by AI message id (= backend turn_id). Older async image
  // completions may still arrive after a newer turn starts, so never keep one
  // global image URL that can be overwritten by a stale turn.
  final Map<String, JsonMap> _storyboardTurns = <String, JsonMap>{};
  int _readerPageIndex = 0;
  int _readerPageTotal = 1;
  int _readerSentencePageIndex = 0;
  int _readerSentencePageTotal = 1;
  int _readerSentenceIndex = -1;
  String _readerPageTurnId = '';

  StreamSubscription<NovelSocketEvent>? _socketSubscription;
  Timer? _diceTimer;
  Timer? _taskTimer;
  Timer? _hudEventTimer;
  Timer? _developerGoalPreviewTimer;
  Timer? _developerConditionPreviewTimer;
  String? _developerGoalBackup;
  String? _developerGoalNodeBackup;
  int? _developerGoalIndexBackup;
  int? _developerGoalTotalBackup;
  bool? _developerGoalEndedBackup;
  String? _developerConditionBackup;
  List<dynamic>? _developerInjuriesBackup;

  // 流式文本如果每个 token 都立刻解析 + notify，会导致整页在手机上高频 rebuild。
  // 这里把多个小 chunk 合并成约 20fps 的 UI 刷新；比旧版 72ms 更贴近本地逐字节奏，
  // 同时仍避免每个网络 token 都触发整页 rebuild。网络流本身不降速，也不会丢字。
  Timer? _streamUiTimer;
  String _pendingStreamText = '';
  static const Duration _streamUiInterval = Duration(milliseconds: 48);

  final List<NovelHudEvent> _hudEventQueue = <NovelHudEvent>[];
  final Map<String, DateTime> _recentHudEventKeys = <String, DateTime>{};
  final List<NovelAffectionPulse> _affectionPulseQueue = <NovelAffectionPulse>[];
  int _hudEventSerial = 0;
  int _affectionPulseSerial = 0;
  int _generationId = 0;
  bool _generationHasReadablePage = false;
  bool _disposed = false;

  NovelMessage? get lastAssistantMessage {
    for (var i = messages.length - 1; i >= 0; i--) {
      if (messages[i].role == NovelMessageRole.assistant) return messages[i];
    }
    return null;
  }

  void _registerForcedBattleTrigger(dynamic raw, {bool notify = true}) {
    final data = asJsonMap(raw);
    if (data.isEmpty) return;

    final sourceMessageId = intValue(data['source_message_id']);
    final required = data.containsKey('required')
        ? boolValue(data['required'])
        : true; // battle_auto_required WS 本身就代表 required=true。
    if (!required || sourceMessageId <= 0) return;

    final target = asJsonMap(data['target']);
    _forcedBattleTrigger = <String, dynamic>{
      'required': true,
      'state': stringValue(data['state'], 'pending').trim().toLowerCase(),
      'source_message_id': sourceMessageId,
      'battle_mode': stringValue(data['battle_mode'], 'defend').trim().isEmpty
          ? 'defend'
          : stringValue(data['battle_mode'], 'defend').trim().toLowerCase(),
      'hostility': intValue(data['hostility']),
      'reason': stringValue(data['reason']),
      'target': <String, dynamic>{...target},
      if (stringValue(data['battle_id']).trim().isNotEmpty)
        'battle_id': stringValue(data['battle_id']).trim(),
      if (asJsonMap(data['battle_snapshot']).isNotEmpty)
        'battle_snapshot': <String, dynamic>{...asJsonMap(data['battle_snapshot'])},
    };

    // 已经 engaged 后，剧情层不存在下一步自由选择。无论旧 suggestions 是刚收到、
    // 历史恢复带回，还是与 WS 发生竞态，都立即清掉，防止用户继续推进 Writer。
    choices = <NovelChoice>[];
    choicesVisible = false;
    playerHint = '';
    luckyCardActive = false;
    if (notify && !_disposed) _notify();
  }

  void _clearForcedBattleTrigger({bool notify = false}) {
    if (_forcedBattleTrigger.isEmpty) return;
    _forcedBattleTrigger = <String, dynamic>{};
    if (notify && !_disposed) _notify();
  }

  void _restoreForcedBattleFromMessage(NovelMessage? message) {
    if (message == null) {
      _clearForcedBattleTrigger();
      return;
    }

    final raw = asJsonMap(message.customAttributes['forced_battle']);
    final state = stringValue(raw['state']).trim().toLowerCase();
    final sourceMessageId = intValue(
      raw['source_message_id'] ?? message.id,
    );

    if (raw.isEmpty || state.isEmpty || state == 'resolved') {
      _clearForcedBattleTrigger();
      return;
    }

    if (state == 'pending') {
      _registerForcedBattleTrigger(<String, dynamic>{
        ...raw,
        'required': true,
        'source_message_id': sourceMessageId,
      }, notify: false);
      return;
    }

    if (state != 'active' || sourceMessageId <= 0) {
      _clearForcedBattleTrigger();
      return;
    }

    // active means the server has already created/frozen this battle. Restore that exact
    // payload directly from history, so reopening an active fight needs no extra recovery route.
    final snapshot = asJsonMap(raw['battle_snapshot']);
    final battleId = stringValue(
      raw['battle_id'] ?? snapshot['battle_id'],
    ).trim();
    final opponent = asJsonMap(snapshot['battle_opponent']);

    // Defensive fallback for old/incomplete rows: keep the world locked as pending and let
    // the normal Continue path call /battle/auto-start, which is idempotent and returns the
    // cached active battle if it already exists.
    if (battleId.isEmpty || snapshot.isEmpty || opponent.isEmpty) {
      _registerForcedBattleTrigger(<String, dynamic>{
        ...raw,
        'state': 'pending',
        'required': true,
        'source_message_id': sourceMessageId,
      }, notify: false);
      return;
    }

    _registerForcedBattleTrigger(<String, dynamic>{
      ...raw,
      'state': 'active',
      'required': true,
      'source_message_id': sourceMessageId,
    }, notify: false);

    final target = asJsonMap(raw['target'] ?? snapshot['target']);
    final targetName = stringValue(target['name']).trim().isEmpty
        ? '当前敌人'
        : stringValue(target['name']).trim();
    final battleMode = stringValue(
      raw['battle_mode'] ?? asJsonMap(snapshot['battle_opponent'])['battle_mode'],
      'defend',
    ).trim().toLowerCase();
    final optionId = stringValue(
      snapshot['option_id'],
      'auto:$sourceMessageId',
    ).trim();

    // Do not enqueue the same restored route twice if history is refreshed while Battle UI
    // is already opening/open.
    if ((_pendingBattleStart?.optionId ?? '') == optionId ||
        _activeBattleOptionId == optionId) {
      return;
    }

    _pendingBattleStart = NovelPendingBattleStart(
      optionId: optionId,
      targetName: targetName,
      battleMode: battleMode.isEmpty ? 'defend' : battleMode,
      fromSurroundings: false,
      loadPayload: () async {
        return await _attachNovelCompanionStarsToBattle(
          <String, dynamic>{...snapshot},
        );
      },
    );
    isStartingBattle = true;
    choices = <NovelChoice>[];
    choicesVisible = false;
    playerHint = '';
    luckyCardActive = false;
  }

  Future<void> _queueForcedBattleStart() async {
    if (!forcedBattleReady) return;

    final sourceMessageId = intValue(_forcedBattleTrigger['source_message_id']);
    if (sourceMessageId <= 0) {
      lastError = '自动战斗来源已经失效，请同步剧情后重试。';
      _notify();
      return;
    }

    final targetName = forcedBattleTargetName;
    final battleMode = stringValue(
      _forcedBattleTrigger['battle_mode'],
      'defend',
    ).trim().toLowerCase();
    final restoredSnapshot = asJsonMap(_forcedBattleTrigger['battle_snapshot']);
    final restoredBattleId = stringValue(
      _forcedBattleTrigger['battle_id'] ?? restoredSnapshot['battle_id'],
    ).trim();
    final hasStoredActiveSnapshot =
        stringValue(_forcedBattleTrigger['state']).trim().toLowerCase() == 'active' &&
        restoredBattleId.isNotEmpty &&
        asJsonMap(restoredSnapshot['battle_opponent']).isNotEmpty;
    final optionId = stringValue(
      restoredSnapshot['option_id'],
      'auto:$sourceMessageId',
    ).trim();

    _pendingBattleStart = NovelPendingBattleStart(
      optionId: optionId,
      targetName: targetName,
      battleMode: battleMode.isEmpty ? 'defend' : battleMode,
      fromSurroundings: false,
      loadPayload: () async {
        if (hasStoredActiveSnapshot) {
          return await _attachNovelCompanionStarsToBattle(
            <String, dynamic>{...restoredSnapshot},
          );
        }
        final payload = await backend.startAutoBattle(
          sessionId: sessionId,
          sourceMessageId: sourceMessageId,
        );
        final battleId = stringValue(payload['battle_id']).trim();
        if (battleId.isEmpty || asJsonMap(payload['battle_opponent']).isEmpty) {
          throw const NovelBackendException('后端没有返回完整的自动战斗快照');
        }
        return await _attachNovelCompanionStarsToBattle(payload);
      },
    );
    isStartingBattle = true;
    choices = <NovelChoice>[];
    choicesVisible = false;
    playerHint = '';
    lastError = '';
    _notify();
  }

  /// 页面消费后即清空，不进入 lastError，也不会触发任何历史/场景刷新。
  JsonMap? takeGenerationNotice() {
    final notice = _pendingGenerationNotice;
    _pendingGenerationNotice = null;
    return notice == null ? null : Map<String, dynamic>.from(notice);
  }

  NovelPendingBattleStart? consumePendingBattleStart() {
    final request = _pendingBattleStart;
    _pendingBattleStart = null;
    if (request != null) {
      // Battle 路由已经接管生成过程，剧情页不再继续显示“正在生成对手”。
      isStartingBattle = false;
      _activeBattleOptionId = request.optionId;
    }
    return request;
  }

  void abandonBattleStart(String optionId) {
    if (_activeBattleOptionId == optionId.trim()) {
      _activeBattleOptionId = '';
    }
    isStartingBattle = false;
    if (!_disposed) _notify();
  }

  JsonMap? consumePendingBattle() {
    final payload = _pendingBattle;
    _pendingBattle = null;
    return payload;
  }

  NovelSentence? get currentSentence {
    if (sentences.isEmpty || currentSentenceIndex < 0 || currentSentenceIndex >= sentences.length) {
      return null;
    }
    return sentences[currentSentenceIndex];
  }

  String get currentStoryboardTurnId => lastAssistantMessage?.id.trim() ?? '';

  JsonMap get currentStoryboard {
    final turnId = currentStoryboardTurnId;
    if (turnId.isEmpty) return const <String, dynamic>{};
    final live = _storyboardTurns[turnId];
    if (live != null && live.isNotEmpty) return live;
    final stored = asJsonMap(lastAssistantMessage?.customAttributes['storyboard']);
    if (stored.isNotEmpty) return stored;
    return const <String, dynamic>{};
  }

  JsonMap _storyboardSheet(JsonMap payload, int sheetIndex) {
    final raw = payload['sheets'];
    if (raw is List) {
      for (final item in raw) {
        final row = asJsonMap(item);
        if (intValue(row['sheet_index']) == sheetIndex) return row;
      }
    } else if (raw is Map) {
      final direct = asJsonMap(raw['$sheetIndex']);
      if (direct.isNotEmpty) return direct;
      for (final value in raw.values) {
        final row = asJsonMap(value);
        if (intValue(row['sheet_index']) == sheetIndex) return row;
      }
    }
    return const <String, dynamic>{};
  }

  String _storyboardImageUrlFromSheet(JsonMap sheet) => stringValue(
        sheet['image_url'] ?? sheet['imageUrl'] ?? sheet['url'],
      ).trim();

  List<MapEntry<int, JsonMap>> _storyboardSheetEntries(JsonMap payload) {
    final byIndex = <int, JsonMap>{};
    final raw = payload['sheets'];
    if (raw is List) {
      for (final item in raw) {
        final row = asJsonMap(item);
        final index = intValue(row['sheet_index'] ?? row['sheetIndex']);
        if (index > 0) byIndex[index] = row;
      }
    } else if (raw is Map) {
      for (final entry in raw.entries) {
        final row = asJsonMap(entry.value);
        final index = intValue(
          row['sheet_index'] ?? row['sheetIndex'] ?? entry.key,
        );
        if (index > 0) byIndex[index] = row;
      }
    }
    final entries = byIndex.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return entries;
  }

  String storyboardSheetUrl(int sheetIndex) =>
      _storyboardImageUrlFromSheet(_storyboardSheet(currentStoryboard, sheetIndex));

  List<String> get currentStoryboardSheetUrls => _storyboardSheetEntries(currentStoryboard)
      .map((entry) => _storyboardImageUrlFromSheet(entry.value))
      .where((url) => url.isNotEmpty)
      .toList(growable: false);

  bool get hasCurrentStoryboard => currentStoryboardSheetUrls.isNotEmpty;

  int _firstAvailableStoryboardSheetIndex(JsonMap payload) {
    for (final entry in _storyboardSheetEntries(payload)) {
      if (_storyboardImageUrlFromSheet(entry.value).isNotEmpty) return entry.key;
    }
    return 0;
  }

  String _latestStoryboardImageUrlFromPayload(JsonMap payload) {
    final entries = _storyboardSheetEntries(payload);
    for (final entry in entries.reversed) {
      final url = _storyboardImageUrlFromSheet(entry.value);
      if (url.isNotEmpty) return url;
    }
    return stringValue(
      payload['image_url'] ?? payload['imageUrl'] ?? payload['scene_image_url'],
    ).trim();
  }

  /// Resolve a logical storyboard shot to its rendered sheet.
  /// Newer backends may render one final sheet even when shot metadata is incomplete;
  /// older clients incorrectly assumed shot_id == sheet_index, which could leave a
  /// valid image permanently invisible. Prefer explicit sheet metadata, then fall
  /// back to the only available sheet when the turn contains exactly one image.
  String storyboardImageUrlForShot(int shotId) {
    if (shotId <= 0) return '';
    final entries = _storyboardSheetEntries(currentStoryboard);
    for (final entry in entries) {
      final row = entry.value;
      final meta = asJsonMap(row['storyboard']);
      final linkedShotIds = <int>{};

      void collectShotIds(dynamic raw) {
        if (raw is! List) return;
        for (final item in raw) {
          if (item is Map) {
            final id = intValue(asJsonMap(item)['shot_id']);
            if (id > 0) linkedShotIds.add(id);
          } else {
            final id = intValue(item);
            if (id > 0) linkedShotIds.add(id);
          }
        }
      }

      collectShotIds(row['shot_ids']);
      collectShotIds(meta['render_shot_ids']);
      collectShotIds(meta['shots']);
      final primaryShotId = intValue(meta['primary_shot_id']);
      if (primaryShotId > 0) linkedShotIds.add(primaryShotId);

      if (linkedShotIds.contains(shotId)) {
        final url = _storyboardImageUrlFromSheet(row);
        if (url.isNotEmpty) return url;
      }
    }

    // Legacy mapping: shot N -> sheet N.
    final direct = storyboardSheetUrl(shotId);
    if (direct.isNotEmpty) return direct;

    // Current single-image contract: one valid sheet is sufficient even when the
    // timing/shot association payload was lost or arrived out of order.
    final urls = entries
        .map((entry) => _storyboardImageUrlFromSheet(entry.value))
        .where((url) => url.isNotEmpty)
        .toList(growable: false);
    return urls.length == 1 ? urls.first : '';
  }

  bool get _currentStoryboardUsesEarlySafeSingleImage {
    final payload = currentStoryboard;
    if (payload.isEmpty) return false;
    final mode = stringValue(payload['mode']).trim();
    final revealPolicy = stringValue(
      payload['reveal_policy'] ?? payload['revealPolicy'],
    ).trim();
    final contractVersion = stringValue(
      payload['style_contract_version'] ?? payload['styleContractVersion'],
    ).trim();

    // Current protocol: one rendered frame is directed exclusively from source segment 0.
    // It is therefore spoiler-safe as soon as the image URL exists; do not let a stale
    // reader-page callback keep a successfully generated frame hidden forever.
    if (mode == 'single_storyboard_image' &&
        (revealPolicy == 'first_safe_segment' || contractVersion == 'v2')) {
      return true;
    }

    final shots = currentStoryboardShots;
    if (shots.length == 1 && currentStoryboardSheetUrls.length == 1) {
      final revealAfter = intValue(
        shots.first['reveal_after_segment'] ?? shots.first['source_segment_end'],
        -1,
      );
      // Live sheet_update events keep the storyboard metadata nested under the sheet,
      // so the top-level mode can legitimately be empty. One sheet + one shot + reveal 0
      // is the protocol-level proof that this is an early-safe single image.
      return revealAfter == 0;
    }
    return false;
  }

  String get currentStoryboardDisplayCandidateUrl {
    final shotId = currentStoryboardShotId;
    if (shotId > 0) {
      final unlocked = storyboardImageUrlForShot(shotId);
      if (unlocked.isNotEmpty) return unlocked;
    }

    final readyImage = currentStoryboardReadyImageUrl;
    if (readyImage.isEmpty) return '';

    // New single-image storyboards only depict the first safe source segment, so the
    // URL itself is enough to promote the image. This intentionally bypasses ONLY the
    // fragile UI page clock, not story safety.
    if (_currentStoryboardUsesEarlySafeSingleImage) return readyImage;

    // Legacy safety net: if the user has already advanced to the final sentence, never
    // leave a completed current-turn image permanently hidden because the final sub-page
    // callback was dropped during a rebuild/swipe.
    if (!hasNext && boolValue(currentStoryboard['ready'])) return readyImage;

    return '';
  }

  /// A ready current-turn image independent of reveal timing. This is only a recovery
  /// source for malformed/missing timeline metadata; callers must not use it to bypass
  /// a valid anti-spoiler reveal checkpoint.
  String get currentStoryboardReadyImageUrl =>
      _latestStoryboardImageUrlFromPayload(currentStoryboard);

  /// Storyboard playback uses the same deterministic source-segment clock as Speaker.
  /// A shot becomes visible only after its reveal checkpoint has been fully read.
  /// This intentionally prefers a slightly late visual reveal over showing a future
  /// character/event before the user has seen it in text.
  List<JsonMap> get currentStoryboardShots {
    final payload = currentStoryboard;
    final byId = <int, JsonMap>{};

    void collect(dynamic raw) {
      if (raw is! List) return;
      for (final item in raw) {
        final row = asJsonMap(item);
        final shotId = intValue(row['shot_id']);
        if (shotId > 0) byId[shotId] = row;
      }
    }

    collect(payload['shots']);
    final sheets = payload['sheets'];
    if (sheets is List) {
      for (final item in sheets) {
        final sheet = asJsonMap(item);
        collect(asJsonMap(sheet['storyboard'])['shots']);
      }
    } else if (sheets is Map) {
      for (final value in sheets.values) {
        final sheet = asJsonMap(value);
        collect(asJsonMap(sheet['storyboard'])['shots']);
      }
    }

    final entries = byId.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return entries.map((entry) => entry.value).toList(growable: false);
  }

  int get _storyboardCompletedSourceSegment {
    if (sentences.isEmpty || currentSentenceIndex < 0) return -1;
    var completed = -1;

    // Storyboard playback is driven only by the visual reader position.
    // Typewriter/reveal state must never move the visual clock backwards: otherwise
    // a shot can appear for one frame and disappear as soon as the new page starts
    // revealing its text.
    final previousCount = currentSentenceIndex.clamp(0, sentences.length).toInt();
    for (var i = 0; i < previousCount; i++) {
      final end = sentences[i].storySourceEndSegment;
      if (end >= 0 && end > completed) completed = end;
    }

    final current = currentSentence;
    if (current == null) return completed;

    // setReaderPagePosition is published after the frame. During a sentence swipe,
    // the old sentence's sub-page index can therefore survive for one frame. Bind
    // page metadata to the exact sentence index so stale page state can never unlock
    // a shot for the newly selected sentence.
    final turnId = currentStoryboardTurnId;
    final readerPositionKnown =
        _readerPageTurnId == turnId &&
        _readerSentenceIndex == currentSentenceIndex;
    final atLastSentencePage = readerPositionKnown &&
        _readerSentencePageTotal > 0 &&
        _readerSentencePageIndex >= _readerSentencePageTotal - 1;

    // Reaching the visual reader page is enough to select its storyboard frame.
    // Do not couple this to isReaderRevealing: reveal animation is presentation, not
    // chronology. This keeps the selected shot stable while text types in.
    if (atLastSentencePage) {
      final end = current.storySourceEndSegment;
      if (end >= 0 && end > completed) completed = end;
    }
    return completed;
  }

  int get currentStoryboardShotId {
    final shots = currentStoryboardShots;
    final fallbackSheet = _firstAvailableStoryboardSheetIndex(currentStoryboard);

    // A valid rendered image must never become permanently invisible just because a
    // sheet update arrived without its optional shot timeline metadata.
    if (shots.isEmpty) return fallbackSheet;

    final completedSegment = _storyboardCompletedSourceSegment;
    var unlockedShot = 0;
    var hasUsableTimeline = false;
    for (final shot in shots) {
      final shotId = intValue(shot['shot_id']);
      final revealAfter = intValue(
        shot['reveal_after_segment'] ?? shot['source_segment_end'],
        -1,
      );
      if (shotId <= 0 || revealAfter < 0) continue;
      hasUsableTimeline = true;
      if (completedSegment >= 0 &&
          revealAfter <= completedSegment &&
          storyboardImageUrlForShot(shotId).isNotEmpty &&
          shotId > unlockedShot) {
        unlockedShot = shotId;
      }
    }

    // If timeline metadata exists, preserve anti-spoiler behavior: before the reveal
    // checkpoint return 0 and let the UI keep the previous successful world frame.
    if (hasUsableTimeline) return unlockedShot;

    // Metadata exists but none of it can drive playback. Showing the already-rendered
    // sheet is safer than leaving the user on a permanent black placeholder.
    return fallbackSheet;
  }

  bool get isCurrentStoryboardGenerating {
    final payload = currentStoryboard;
    return boolValue(payload['generating']) ||
        (isGenerating && !boolValue(payload['ready']));
  }

  void setReaderPagePosition(
    int index,
    int total, {
    int sentencePageIndex = 0,
    int sentencePageTotal = 1,
    int sentenceIndex = -1,
  }) {
    final safeTotal = total < 1 ? 1 : total;
    final safeIndex = index.clamp(0, safeTotal - 1).toInt();
    final safeSentenceTotal = sentencePageTotal < 1 ? 1 : sentencePageTotal;
    final safeSentencePageIndex =
        sentencePageIndex.clamp(0, safeSentenceTotal - 1).toInt();
    final safeSentenceIndex = sentenceIndex < 0
        ? currentSentenceIndex
        : sentenceIndex.clamp(0, sentences.isEmpty ? 0 : sentences.length - 1).toInt();
    final turnId = currentStoryboardTurnId;
    if (_readerPageIndex == safeIndex &&
        _readerPageTotal == safeTotal &&
        _readerSentencePageIndex == safeSentencePageIndex &&
        _readerSentencePageTotal == safeSentenceTotal &&
        _readerSentenceIndex == safeSentenceIndex &&
        _readerPageTurnId == turnId) {
      return;
    }
    _readerPageIndex = safeIndex;
    _readerPageTotal = safeTotal;
    _readerSentencePageIndex = safeSentencePageIndex;
    _readerSentencePageTotal = safeSentenceTotal;
    _readerSentenceIndex = safeSentenceIndex;
    _readerPageTurnId = turnId;
    debugPrint(
      '[StoryboardClock] turn=$turnId sentence=$safeSentenceIndex '
      'subPage=$safeSentencePageIndex/$safeSentenceTotal '
      'readerPage=$safeIndex/$safeTotal shot=$currentStoryboardShotId',
    );
    _notify();
  }

  void _mergeStoryboardPayload(JsonMap incoming, {bool notify = true}) {
    final turnId = stringValue(
      incoming['turn_id'] ?? incoming['message_id'],
    ).trim();
    if (turnId.isEmpty) return;

    final existing = Map<String, dynamic>.from(
      _storyboardTurns[turnId] ?? const <String, dynamic>{},
    );
    final bySheet = <int, JsonMap>{};

    void collect(dynamic raw) {
      if (raw is List) {
        for (final item in raw) {
          final row = asJsonMap(item);
          final index = intValue(row['sheet_index']);
          if (index > 0) bySheet[index] = Map<String, dynamic>.from(row);
        }
      } else if (raw is Map) {
        for (final value in raw.values) {
          final row = asJsonMap(value);
          final index = intValue(row['sheet_index']);
          if (index > 0) bySheet[index] = Map<String, dynamic>.from(row);
        }
      }
    }

    collect(existing['sheets']);
    collect(incoming['sheets']);

    final singleSheetIndex = intValue(
      incoming['sheet_index'] ?? incoming['sheetIndex'],
    );
    final singleImageUrl = stringValue(
      incoming['image_url'] ?? incoming['imageUrl'] ?? incoming['url'],
    ).trim();
    if (singleSheetIndex > 0 && singleImageUrl.isNotEmpty) {
      final previousSheet = bySheet[singleSheetIndex] ?? const <String, dynamic>{};
      bySheet[singleSheetIndex] = <String, dynamic>{
        ...previousSheet,
        'sheet_index': singleSheetIndex,
        'image_url': singleImageUrl,
        if (incoming['storyboard'] != null)
          'storyboard': asJsonMap(incoming['storyboard']),
      };
    }

    final sortedEntries = bySheet.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final merged = <String, dynamic>{
      ...existing,
      ...incoming,
      'turn_id': turnId,
      'sheets': sortedEntries
          .map((entry) => entry.value)
          .toList(growable: false),
    };

    _storyboardTurns[turnId] = merged;
    while (_storyboardTurns.length > 24) {
      _storyboardTurns.remove(_storyboardTurns.keys.first);
    }
    if (notify) _notify();
  }

  // 已经完整生成的页面可立即阅读；后台流继续进入队列，不再锁住翻页。
  bool get hasNext => currentSentenceIndex < sentences.length - 1;

  bool get hasPrevious => currentSentenceIndex > 0;

  NovelCharacter? get protagonist => scenario?.protagonist;

  String get scenarioInstanceId =>
      scenario?.id.isNotEmpty == true ? scenario!.id : scenarioId;

  String get protagonistName => protagonist?.name ?? '我';

  /// 选项按钮图标统一从 NovelChoice 读取。
  /// dialogue / action / battle 在 NovelChoice 内已经配置默认本地资源路径，
  /// 后端如传 icon_path / iconPath / icon 则会自动覆盖。
  String choiceIconPath(NovelChoice choice) => choice.iconPath;

  String get locationTitle {
    final raw = world.location.isNotEmpty ? world.location : (scenario?.title ?? '');
    final parts = raw.split(RegExp(r'[^一-龥a-zA-Z0-9]+')).where((part) => part.isNotEmpty).toList();
    return parts.isEmpty ? raw : parts.last;
  }

  String get locationSubtitle {
    final raw = world.location;
    final parts = raw.split(RegExp(r'[^一-龥a-zA-Z0-9]+')).where((part) => part.isNotEmpty).toList();
    if (parts.length <= 1) return '';
    return parts.sublist(0, parts.length - 1).join(' · ');
  }

  /// 探索页只消费后端 scene-map 返回的当前场景资产，不自行创建场景。
  JsonMap get currentSceneAsset => sceneMap.currentScene.sceneAsset;

  JsonMap get currentSceneAssetPackage =>
      asJsonMap(currentSceneAsset['asset_package']);

  /// 剧情分镜尚未完成时展示当前场景的永久底图；绝不回退上一回合分镜。
  String get currentSceneBackdropUrl {
    final direct = stringValue(
      currentSceneAsset['scene_image_url'] ??
          currentSceneAsset['backdrop_url'],
    ).trim();
    if (direct.isNotEmpty) return direct;
    return stringValue(
      asJsonMap(currentSceneAssetPackage['floor'])['url'],
    ).trim();
  }

  List<NovelSceneMapNode> get currentSceneNavigationTargets =>
      sceneMap.targets;

  bool get shouldShowSurroundingsAction {
    return storyStarted &&
        !isCinematic &&
        !isGenerating &&
        !forcedBattlePending &&
        !hasNext &&
        !isReaderRevealing &&
        !pendingFateRevert &&
        !showDice &&
        !isStartingBattle &&
        boolValue(surroundingsAvailability['available']) &&
        boolValue(surroundingsAvailability['can_investigate']);
  }

  bool get canInvestigateSurroundings => shouldShowSurroundingsAction;

  bool get surroundingsNeedsAttention {
    return canInvestigateSurroundings &&
        boolValue(surroundingsAvailability['needs_attention']);
  }

  String get surroundingsStatus {
    return stringValue(
      surroundingsData['status'] ?? surroundingsAvailability['status'],
      'unavailable',
    ).trim().toLowerCase();
  }

  String get surroundingsActionLabel {
    return switch (surroundingsStatus) {
      'exhausted' => '已探索',
      'reward_ready' => '有所发现',
      'in_progress' => '继续调查',
      _ => '探索周围',
    };
  }

  bool get canRequestSceneMove {
    return storyStarted &&
        !hasNext &&
        !isGenerating &&
        !forcedBattlePending &&
        !isReaderRevealing &&
        !isCinematic &&
        !pendingFateRevert &&
        !showDice &&
        !isSceneMoveSubmitting &&
        sceneMap.mobility.canMove;
  }

  String get sceneMoveDisabledReason {
    if (!storyStarted) return '剧情尚未开始';
    if (hasNext) return '请先返回最新剧情，再进行场景移动';
    if (isGenerating) return '剧情正在生成，请稍候';
    if (forcedBattlePending) return '当前袭击已经发生，请先处理战斗';
    if (isReaderRevealing) return '请先读完当前这段剧情';
    if (isCinematic) return '当前处于剧情演出，暂时无法移动';
    if (pendingFateRevert) return '请先处理当前命运回溯';
    if (showDice) return '检定尚未结束，暂时无法移动';
    if (isSceneMoveSubmitting) return '正在确认路线';
    if (!sceneMap.mobility.canMove) {
      return sceneMap.mobility.reason.isEmpty
          ? '当前状态无法移动'
          : sceneMap.mobility.reason;
    }
    return '';
  }

  bool canMoveToScene(NovelSceneMapNode target) {
    return canRequestSceneMove && !target.isLocked && target.sceneId.isNotEmpty;
  }

  void setReaderRevealing(bool value, {bool notify = true}) {
    if (isReaderRevealing == value) return;
    isReaderRevealing = value;
    if (!notify || _disposed) return;
    scheduleMicrotask(() {
      if (!_disposed) _notify();
    });
  }

  String _normalizeSpeakerLookupName(String value) {
    var normalized = value.trim();
    if (normalized.isEmpty) return '';

    // 流式/后端 speaker 字段偶尔会混入对白标点或动作说明。
    // 这里只做保守清洗，不修改真正展示给用户的 speakerName。
    normalized = normalized
        .replaceAll(RegExp(r'^[「『“]+|[」』”]+$'), '')
        .replaceAll(RegExp(r'[（(][^）)]*[）)]'), '')
        .replaceAll(RegExp(r'[:：\s]+$'), '')
        .trim();
    return normalized;
  }

  bool _matchesSpeakerName(NovelCharacter character, String rawSpeakerName) {
    final speakerName = rawSpeakerName.trim();
    if (speakerName.isEmpty) return false;
    if (character.matchesName(speakerName)) return true;

    final normalizedSpeaker = _normalizeSpeakerLookupName(speakerName);
    if (normalizedSpeaker.isEmpty) return false;
    if (character.matchesName(normalizedSpeaker)) return true;

    final normalizedCharacter = _normalizeSpeakerLookupName(character.name);
    return normalizedCharacter.isNotEmpty && normalizedSpeaker == normalizedCharacter;
  }

  NovelCharacter? get currentSpeakerCharacter {
    final sentence = currentSentence;
    if (sentence == null) return null;

    // 先判断主角和 characterId，再看 speakerName。
    // 有些 sentenceItems 会带 character_id 但 speaker_name 暂时为空，
    // 旧逻辑会在这里提前 return null，导致明明有角色 id 却拿不到立绘。
    if (sentence.isProtagonist) return protagonist;

    final rawSpeakerName = sentence.speakerName.trim();
    if (rawSpeakerName == '我' || rawSpeakerName == protagonistName) {
      return protagonist;
    }

    final characterId = sentence.characterId.trim();
    if (characterId.isNotEmpty) {
      final characters = scenario?.characters;

      // 第一层：兼容 characters Map 本身就是以角色 id 为 key 的情况。
      final direct = characters?[characterId];
      if (direct != null) return direct;

      // 第二层：Map key 可能是名字/序号，真正角色 id 存在 value.id 中。
      for (final character in characters?.values ?? const <NovelCharacter>[]) {
        if (character.id == characterId) return character;
      }
    }

    if (rawSpeakerName.isEmpty) return null;

    // 最后才按角色名/别名匹配，并对常见标点与“（动作）”做保守归一化。
    for (final character in scenario?.characters.values ?? const <NovelCharacter>[]) {
      if (_matchesSpeakerName(character, rawSpeakerName)) return character;
    }
    return null;
  }

  String get currentSpeakerName {
    final sentence = currentSentence;
    if (sentence == null || !sentence.hasSpeech) return '';
    if (sentence.isProtagonist) return protagonistName;
    return sentence.speakerName;
  }

  /// 只把“属于当前对白角色”的好感变化交给 UI。
  /// 角色还没出现在对白里时事件会继续保留，不会提前弹出任何提示。
  NovelAffectionPulse? affectionPulseFor(
    NovelCharacter? character, [
    String speakerName = '',
  ]) {
    if (character == null && speakerName.trim().isEmpty) return null;

    for (final pulse in _affectionPulseQueue) {
      if (character != null) {
        if (pulse.characterId.isNotEmpty &&
            pulse.characterId == character.id) {
          return pulse;
        }
        if (pulse.characterName.isNotEmpty &&
            character.matchesName(pulse.characterName)) {
          return pulse;
        }
      }

      final cleanSpeaker = speakerName.trim();
      if (cleanSpeaker.isNotEmpty &&
          pulse.characterName.isNotEmpty &&
          _normalizeSpeakerLookupName(cleanSpeaker) ==
              _normalizeSpeakerLookupName(pulse.characterName)) {
        return pulse;
      }
    }
    return null;
  }

  void consumeAffectionPulse(int pulseId) {
    _affectionPulseQueue.removeWhere((pulse) => pulse.id == pulseId);
  }

  String get currentPortraitUrl {
    final sentence = currentSentence;
    final character = currentSpeakerCharacter;

    final characterPortrait = character?.portraitUrl.trim() ?? '';
    if (characterPortrait.isNotEmpty) return characterPortrait;

    final sentencePortrait = sentence?.portraitUrl.trim() ?? '';
    if (sentencePortrait.isNotEmpty) return sentencePortrait;

    // 剧情页的“立绘层”只认真正的 portrait。
    // 如果没有立绘，就返回空字符串，让前端直接不显示人物层，
    // 而不是再退化成头像/首字母占位图。
    return '';
  }

  String get currentAvatarUrl {
    final sentence = currentSentence;
    final character = currentSpeakerCharacter;

    final characterAvatar = character?.avatarUrl.trim() ?? '';
    if (characterAvatar.isNotEmpty) return characterAvatar;

    final sentenceAvatar = sentence?.avatarUrl.trim() ?? '';
    if (sentenceAvatar.isNotEmpty) return sentenceAvatar;

    // 反向兜底：只有立绘没有独立头像时，头像位置也可以正常显示。
    final characterPortrait = character?.portraitUrl.trim() ?? '';
    if (characterPortrait.isNotEmpty) return characterPortrait;

    return sentence?.portraitUrl.trim() ?? '';
  }

  int get protagonistHp {
    final normalized = protagonistCondition.toLowerCase();
    if (normalized.contains('濒死') || normalized.contains('dying') || normalized.contains('near_death')) return 12;
    if (normalized.contains('重伤') || normalized.contains('heavy')) return 35;
    if (normalized.contains('轻伤') || normalized.contains('light')) return 68;
    return 100;
  }

  int get averageAffection {
    final npc = scenario?.characters.values.where((character) => !character.isMain).toList() ?? <NovelCharacter>[];
    if (npc.isEmpty) return 0;
    return (npc.fold<int>(0, (sum, character) => sum + character.affection) / npc.length).round();
  }

  bool _historyHasStartedNarrative(NovelHistoryResult history) {
    // `is_first_play` 不是“正文已经开始”的权威信号。角色确认会更新 scenario，
    // 某些后端链路可能因此提前把它变成 false；只有真实 turn 才代表已进入正文。
    if (history.currentTurn > 0) return true;

    for (final message in history.messages) {
      if (message.role != NovelMessageRole.assistant || message.isTemporary) continue;
      final attrs = message.customAttributes;
      final turn = intValue(
        attrs['turn_number'] ?? attrs['turn'] ?? attrs['story_turn'],
      );
      if (turn > 0) return true;
    }
    return false;
  }

  Future<void> initialize() async {
    if (isInitializing || isInitialized) return;
    isInitializing = true;
    lastError = '';
    _notify();

    try {
      await Future.wait(<Future<void>>[
        settings.load(),
        bgm.loadPreference(),
      ]);
      scenario = await backend.fetchScenario(scenarioId, full: true);
      world = scenario!.worldState;
      bgm.setConfig(scenario!.bgmConfig);
      unawaited(bgm.preloadTypingSfx());

      // 模型配置不是进入剧情的硬依赖：接口异常时不应该让整个小说页初始化失败。
      await _loadModelConfig(notify: false);

      // 场景详情 + 历史记录才是进入世界的硬依赖。
      // 人物状态、背包、WebSocket、BGM 任意一个暂时失败，都不应该让整页变成
      // “世界暂时无法载入”。这也更接近 Vue：附加模块失败只降级，不阻断剧情。
      final history = await backend.fetchHistory(sessionId, force: true);
      _applyHistory(history);

      // 当前目标不是进入世界的硬依赖；旧存档也可以由后端 /novel/goal 自动补齐。
      await refreshCurrentGoal(notify: false);

      // Opening 只读取剧本自己的 openingMessage。正文历史绝不反向充当序章。
      openingText = scenario!.openingMessage.trim().isNotEmpty
          ? scenario!.openingMessage
          : '故事即将开始。';

      final hasStartedNarrative = _historyHasStartedNarrative(history);
      if (hasStartedNarrative) {
        _setLaunchPhase(NovelLaunchPhase.story, notify: false);
      } else if (history.isFirstPlay) {
        _setLaunchPhase(NovelLaunchPhase.characterSetup, notify: false);
      } else {
        _setLaunchPhase(NovelLaunchPhase.opening, notify: false);
      }

      // 核心数据已经就绪，先允许游戏页面进入。
      isInitialized = true;
      // 地图是增强能力，不作为进入剧情的硬依赖。接口尚未部署或旧剧本
      // 没有 scene_graph 时只在地图面板内提示，不阻断正文。
      unawaited(refreshSceneMap(force: true));
      // 只读取轻量可用性，不生成调查内容；真正的 LLM 调用发生在用户点开时。
      unawaited(refreshSurroundingsAvailability());

      // 角色 / 经历 / 背包改为真正的按需加载：
      // 用户先看到页面，再由对应页面在首帧后异步刷新，避免进入世界时提前请求，
      // 也避免点击入口后长时间没有任何界面反馈。场景详情里已有的角色基础资料
      // 仍可直接用于剧情展示，实时状态在打开角色页后再刷新。

      _socketSubscription ??= socket.events.listen(_handleSocketEvent);
      try {
        await socket.connect(sessionId);
      } catch (error) {
        debugPrint('novel socket init skipped: $error');
      }

      try {
        await bgm.init(history.bgmIntensity, history.sceneMode);
      } catch (error) {
        debugPrint('novel bgm init skipped: $error');
      }
    } on NovelBackendException catch (error) {
      lastError = error.message;
      insufficientBalance = error.isInsufficientBalance;
    } catch (error) {
      lastError = '初始化失败：$error';
    } finally {
      isInitializing = false;
      _notify();
    }
  }

  void _applyHistory(
    NovelHistoryResult history, {
    bool preserveReaderPosition = false,
  }) {
    final visibleSentence = preserveReaderPosition ? currentSentence : null;
    final visibleSentenceIndex = currentSentenceIndex;

    messages = history.messages.where((message) => !message.isTemporary).toList();
    currentTurn = history.currentTurn;
    // 权威历史只允许把启动流程向前推进：一旦确认已有真实剧情回合，
    // 无论当前是 Opening 还是重连中的 starting，都统一进入 Story。
    // turn=0 不做反向迁移，避免回溯第 0 轮时重新弹出 Opening。
    if (_historyHasStartedNarrative(history)) {
      _setLaunchPhase(NovelLaunchPhase.story, notify: false);
    }
    score = NovelScore(total: history.currentScore);
    currentTask = history.currentTask;
    if (history.endingCg.isNotEmpty) {
      ending = ending.copyWith(text: history.endingCg);
      showEnding = true;
    }
    _syncUiFromLastMessage(lastAssistantMessage);
    _rebuildSentences(resetIndex: !preserveReaderPosition);

    if (preserveReaderPosition && sentences.isNotEmpty) {
      // HTTP 补拉会重新创建整组 NovelSentence，不能依赖对象引用。
      // 优先按正在阅读的内容找回原页；流式正文被补全、内容发生变化时，
      // 再保留原下标并夹紧到新分页范围，避免同步后跳回第一页。
      final matchingIndex = visibleSentence == null
          ? -1
          : sentences.indexWhere(
              (item) =>
                  item.readerText == visibleSentence.readerText &&
                  item.speakerName == visibleSentence.speakerName &&
                  item.type == visibleSentence.type,
            );
      currentSentenceIndex = matchingIndex >= 0
          ? matchingIndex
          : visibleSentenceIndex.clamp(0, sentences.length - 1).toInt();
    }
  }

  void _syncUiFromLastMessage(NovelMessage? message) {
    final attributes = message?.customAttributes ?? const <String, dynamic>{};

    // /chat/history already returns custom_attributes. Restore forced combat directly from
    // the triggering assistant Message; WebSocket is only the live fast-path.
    _restoreForcedBattleFromMessage(message);

    final storedStoryboard = asJsonMap(attributes['storyboard']);
    if (storedStoryboard.isNotEmpty && message != null) {
      _mergeStoryboardPayload(
        <String, dynamic>{
          ...storedStoryboard,
          'turn_id': stringValue(storedStoryboard['turn_id'], message.id),
          'generating': !boolValue(storedStoryboard['ready']),
        },
        notify: false,
      );
    }
    final rawChoices = attributes['suggested_replies'] ?? attributes['suggestions'];
    if (forcedBattlePending) {
      choices = <NovelChoice>[];
      choicesVisible = false;
      playerHint = '';
    } else if (rawChoices is List) {
      choices = rawChoices.map(NovelChoice.fromDynamic).where((item) => item.text.isNotEmpty).toList();
      playerHint = stringValue(attributes['player_hint'], playerHint);
    } else {
      choices = <NovelChoice>[];
      playerHint = stringValue(attributes['player_hint'], playerHint);
    }
    final task = asJsonMap(attributes['current_task']);
    if (task.isNotEmpty) currentTask = NovelTask.fromJson(task);

    final historyGoal = stringValue(attributes['current_goal']).trim();
    if (historyGoal.isNotEmpty) {
      _applyGoalPayload(<String, dynamic>{
        'objective': historyGoal,
        'node_id': attributes['current_goal_node_id'],
        'index': attributes['current_goal_index'],
        'total': attributes['current_goal_total'],
      });
    }

    world = world.copyWith(
      location: stringValue(attributes['location'], world.location),
      weather: stringValue(attributes['weather'], world.weather),
      atmosphere: stringValue(attributes['atmosphere'], world.atmosphere),
      backgroundUrl: stringValue(
        attributes['current_background_url'] ?? attributes['background_image'],
        world.backgroundUrl,
      ),
    );
    _applyStoryClock(attributes['story_clock']);

    if (attributes['protagonist_condition'] != null) {
      protagonistCondition = stringValue(attributes['protagonist_condition'], protagonistCondition);
      protagonistInjuries = attributes['protagonist_injuries'] is List
          ? List<dynamic>.of(attributes['protagonist_injuries'] as List)
          : protagonistInjuries;
    }
    if (attributes['is_cinematic'] != null) {
      isCinematic = boolValue(attributes['is_cinematic']);
    }
  }

  void _rebuildSentences({bool resetIndex = false}) {
    sentences = parser
        .buildSentences(
          message: lastAssistantMessage,
          isGenerating: isGenerating,
        )
        // 防止解析器把“……”“---”或只有空格的内容拆成独立剧情页。
        .where((sentence) =>
            novelTextHasReadableContent(sentence.readerText))
        .toList(growable: false);
    if (resetIndex) {
      currentSentenceIndex = 0;
    } else if (sentences.isEmpty) {
      currentSentenceIndex = 0;
    } else if (currentSentenceIndex >= sentences.length) {
      currentSentenceIndex = sentences.length - 1;
    }
  }

  Future<void> _loadModelConfig({bool notify = true}) async {
    try {
      final config = await backend.fetchModelConfig();
      availableModels = config.models;
      currentNovelModel = config.currentNovelModel;
    } catch (error) {
      // Vue 这里也是非阻塞 console.error；Flutter 同样不影响剧情主流程。
      debugPrint('load novel model config failed: $error');
    }
    if (notify) _notify();
  }

  Future<void> refreshModelConfig() => _loadModelConfig();

  Future<void> setNovelModel(String modelId) async {
    final next = modelId.trim();
    if (next.isEmpty || next == currentNovelModel || isChangingModel) return;
    final previous = currentNovelModel;
    // 与 Vue 一样先乐观切换，但失败时回滚，避免 UI 显示与后端实际配置不一致。
    currentNovelModel = next;
    isChangingModel = true;
    lastError = '';
    _notify();
    try {
      await backend.updateNovelModel(next);
      infoMessage = '小说引擎已切换';
    } catch (error) {
      currentNovelModel = previous;
      lastError = error is NovelBackendException
          ? error.message
          : '模型切换失败：$error';
    } finally {
      isChangingModel = false;
      _notify();
    }
  }

  String characterAppearance(NovelCharacter character) {
    final persona = character.persona;
    final status = character.status;
    final candidates = <dynamic>[
      persona['appearance'],
      persona['portrait_prompt'],
      persona['looks'],
      status['appearance'],
      status['description'],
      status['personality'],
      character.name,
    ];
    for (final value in candidates) {
      final text = stringValue(value).trim();
      if (text.isNotEmpty) return text;
    }
    return character.name;
  }

  String _visualBriefValue(dynamic value) {
    if (value == null) return '';
    if (value is String) return value.trim();
    if (value is List) {
      return value
          .map(_visualBriefValue)
          .where((item) => item.isNotEmpty)
          .join('、');
    }
    if (value is Map) {
      return value.values
          .map(_visualBriefValue)
          .where((item) => item.isNotEmpty)
          .join('、');
    }
    return value.toString().trim();
  }

  String _firstVisualBriefValue(List<dynamic> values) {
    for (final value in values) {
      final text = _visualBriefValue(value);
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  /// 给图片服务的“角色视觉简报”。
  ///
  /// Novel 端只负责整理角色事实、长期气质与世界观，不在这里写最终绘图 Prompt。
  /// image-service 仍负责把这份 brief 美术化、补充构图/材质/质量词并交给 ComfyUI。
  String buildCharacterVisualBrief(
    NovelCharacter character, {
    String userDirection = '',
  }) {
    final persona = character.persona;
    final status = character.status;
    final scenarioRaw = scenario?.raw ?? const <String, dynamic>{};
    final worldSetting = asJsonMap(scenarioRaw['world_setting']);
    final visualDna = asJsonMap(worldSetting['visual_dna']);

    final gender = _firstVisualBriefValue(<dynamic>[
      character.gender,
      persona['gender'],
      status['gender'],
    ]);
    final age = _firstVisualBriefValue(<dynamic>[
      persona['age'],
      status['age'],
      status['age_visual'],
    ]);
    final identity = _firstVisualBriefValue(<dynamic>[
      status['identity'],
      persona['identity'],
      status['role'],
      persona['role'],
    ]);
    final personality = _firstVisualBriefValue(<dynamic>[
      status['personality'],
      persona['personality'],
      persona['temperament'],
      persona['traits'],
    ]);
    final appearance = _firstVisualBriefValue(<dynamic>[
      persona['appearance'],
      status['appearance'],
      persona['looks'],
      persona['portrait_prompt'],
    ]);
    final background = _firstVisualBriefValue(<dynamic>[
      status['background'],
      persona['background'],
      persona['description'],
    ]);

    final worldOverview = _firstVisualBriefValue(<dynamic>[
      worldSetting['world_overview'],
      worldSetting['background'],
      scenarioRaw['world_overview'],
      scenarioRaw['background'],
      scenario?.description,
    ]);
    final worldVisual = _firstVisualBriefValue(<dynamic>[
      visualDna['world_positive'],
      visualDna['style_lock'],
      visualDna['culture_key'],
      worldSetting['art_style'],
      worldSetting['art_style_base'],
    ]);

    final extra = userDirection.trim();
    final buffer = StringBuffer()
      ..writeln('【角色视觉简报｜角色设定优先】')
      ..writeln('【角色姓名】${character.name}')
      ..writeln('【性别】${gender.isEmpty ? "未明确" : gender}')
      ..writeln('【年龄/年龄感】${age.isEmpty ? "未明确" : age}')
      ..writeln('【身份定位】${identity.isEmpty ? "未明确" : identity}')
      ..writeln('【人物性格与长期气质】${personality.isEmpty ? "未明确" : personality}')
      ..writeln('【剧情确认的静态外貌】${appearance.isEmpty ? "未明确" : appearance}')
      ..writeln('【人物背景】${background.isEmpty ? "未明确" : background}')
      ..writeln('【世界观/题材】${worldOverview.isEmpty ? "未明确" : worldOverview}')
      ..writeln('【世界视觉方向】${worldVisual.isEmpty ? "按当前世界设定判断" : worldVisual}');

    if (extra.isNotEmpty) {
      buffer.writeln('【用户本次额外调整】$extra');
    }

    buffer
      ..writeln('【美术转译要求】')
      ..writeln('1. 以上角色资料是事实与方向依据；不要只围绕发色、衣服颜色生成一个泛化人物。')
      ..writeln('2. 必须把身份、年龄、性格气质、背景和世界观一起视觉化到脸部气质、整体轮廓、服装层次、材质、配饰等级与姿态。')
      ..writeln('3. “剧情确认的静态外貌”只是硬事实之一；缺失的普通视觉细节可合理补全，但不能创造会改变剧情身份的特殊设定。')
      ..writeln('4. 高身份、超凡、武侠、仙侠、玄幻等角色不能被泛化成普通历史古装人物；现代角色也不能被错误古装化。')
      ..writeln('5. 用户本次额外调整仅作为本次美术方向，在不与角色硬事实冲突时优先体现。')
      ..writeln('6. 最终专业绘图 Prompt、画风词、构图、光影、质量词和负面词由图片服务统一处理。');

    return buffer.toString().trim();
  }

  /// AI 立绘任务不轮询 `/image/task/{taskId}`：该路由是 SSE 长连接，
  /// 普通 http.get 会一直等到流关闭，导致“图片已经生成但 Flutter 仍在等待/超时”。
  /// Flutter 只轮询普通 JSON 的 `/image/task/{taskId}/result`，
  /// Redis 中一旦出现 portrait_url 就立即返回给 UI，不必等待 completed。
  Future<({String portraitUrl, String avatarUrl})> generatePortrait({
    required NovelCharacter character,
    String prompt = '',
    String style = '',
  }) async {
    // 前端文本框只代表“本次额外调整”，不能再覆盖完整角色资料。
    // 即使用户留空，也始终使用完整 Character Brief 生成。
    final description = buildCharacterVisualBrief(
      character,
      userDirection: prompt,
    );

    final selectedStyle = style.trim().isNotEmpty
        ? style.trim()
        : settings.artStyle;
    final apiStyle = selectedStyle == 'stylized_3d' ? '3d' : selectedStyle;

    final created = await backend.createImageTask(
      description: description,
      style: apiStyle,
      removeBackground: true,
      autoCropAvatar: true,
    );
    final taskId = stringValue(created['task_id'] ?? created['id']);
    if (taskId.isEmpty) {
      throw const NovelBackendException('图片服务未返回 task_id');
    }

    // 图片服务自己会返回动态 estimated_wait。这里额外给 CDN/R2 同步留余量，
    // 但不允许单次 HTTP 请求吞掉整个 deadline。
    final estimated = intValue(created['estimated_wait'], 60);
    final timeoutSeconds = (estimated + 45).clamp(60, 180).toInt();
    final deadline = DateTime.now().add(Duration(seconds: timeoutSeconds));

    const failedStates = <String>{
      'failed',
      'error',
      'cancelled',
      'canceled',
    };

    String portraitFrom(JsonMap data, [String fallback = '']) {
      return stringValue(
        data['portrait_url'] ??
            data['portrait'] ??
            data['tachie'] ??
            data['image_url'] ??
            data['url'],
        fallback,
      ).trim();
    }

    String avatarFrom(JsonMap data, [String fallback = '']) {
      return stringValue(
        data['avatar_url'] ?? data['avatar'] ?? data['thumbnail_url'],
        fallback,
      ).trim();
    }

    var partialPortrait = portraitFrom(created);
    var partialAvatar = avatarFrom(created);

    // 极少数情况下创建任务响应本身已经带 URL。
    if (partialPortrait.isNotEmpty) {
      return (
        portraitUrl: partialPortrait,
        avatarUrl: partialAvatar.isEmpty ? partialPortrait : partialAvatar,
      );
    }

    NovelBackendException? lastBackendError;

    while (DateTime.now().isBefore(deadline)) {
      try {
        // 关键修复：只访问普通 JSON result 接口，绝不调用 SSE status 接口。
        final result = await backend
            .fetchImageTaskResult(taskId)
            .timeout(const Duration(seconds: 8));

        lastBackendError = null;
        final state = stringValue(
          result['status'] ?? result['state'] ?? result['task_status'],
        ).trim().toLowerCase();

        partialPortrait = portraitFrom(result, partialPortrait);
        partialAvatar = avatarFrom(result, partialAvatar);

        // portrait 一出现就让生成页立即刷新，不再等 avatar，也不等 completed。
        // avatar 尚未同步时先用 portrait 兜底，符合现有 UI 行为。
        if (partialPortrait.isNotEmpty) {
          return (
            portraitUrl: partialPortrait,
            avatarUrl: partialAvatar.isEmpty ? partialPortrait : partialAvatar,
          );
        }

        if (failedStates.contains(state)) {
          throw NovelBackendException(
            stringValue(
              result['error'] ?? result['message'],
              'AI 立绘生成失败',
            ),
          );
        }
      } on TimeoutException {
        // 单次网络请求超时不等于生成失败；继续下一轮，避免网络抖动误判。
      } on NovelBackendException catch (error) {
        if (error.statusCode == 404) {
          // 创建任务后 Redis/网关极短时间内尚未可见，继续轮询即可。
          lastBackendError = error;
        } else {
          rethrow;
        }
      } catch (_) {
        // 临时网络错误不立即终止生成。最终 deadline 前仍会继续探测 result。
      }

      await Future<void>.delayed(const Duration(milliseconds: 500));
    }

    // deadline 临界点再取最后一次，避免刚好在最后 500ms 写入 Redis。
    try {
      final result = await backend
          .fetchImageTaskResult(taskId)
          .timeout(const Duration(seconds: 8));
      final portrait = portraitFrom(result, partialPortrait);
      final avatar = avatarFrom(result, partialAvatar);
      if (portrait.isNotEmpty) {
        return (
          portraitUrl: portrait,
          avatarUrl: avatar.isEmpty ? portrait : avatar,
        );
      }
    } catch (_) {}

    if (lastBackendError != null && lastBackendError!.statusCode != 404) {
      throw lastBackendError!;
    }
    throw const NovelBackendException('立绘生成超时，请稍后重试');
  }

  Future<String> uploadCharacterImage({
    required List<int> bytes,
    required String filename,
    required String contentType,
    bool avatar = false,
  }) {
    return backend.uploadBytesToR2(
      bytes: bytes,
      filename: filename,
      contentType: contentType,
      category: avatar ? 'char/avatar' : 'char/portrait',
    );
  }

  /// 保存角色视觉信息时永远基于 Controller 当前最新 scenario.raw 修改，
  /// 避免 Vue 旧实现里“弹窗快照覆盖新数据”的竞态。
  Future<void> updateCharacterVisuals({
    required NovelCharacter character,
    required String portraitUrl,
    String? avatarUrl,
  }) async {
    final currentScenario = scenario;
    if (currentScenario == null) {
      throw const NovelBackendException('剧本数据尚未加载');
    }
    final portrait = portraitUrl.trim();
    // avatarUrl == null 表示这次只更新立绘，不触碰头像。
    // 头像与立绘是两个独立字段，禁止用 portrait 自动兜底写入 avatar。
    final shouldUpdateAvatar = avatarUrl != null;
    final avatar = shouldUpdateAvatar
        ? avatarUrl!.trim()
        : character.avatarUrl.trim();
    if (portrait.isEmpty) {
      throw const NovelBackendException('立绘地址为空，无法保存');
    }

    final payload = <String, dynamic>{...currentScenario.raw};

    bool matches(JsonMap item) {
      final itemId = stringValue(item['id'] ?? item['character_id']);
      if (character.id.isNotEmpty && itemId.isNotEmpty) {
        return itemId == character.id;
      }
      return stringValue(item['name']) == character.name;
    }

    List<JsonMap> patchCharacters(dynamic raw) {
      return asJsonList(raw).map((item) {
        if (!matches(item)) return <String, dynamic>{...item};
        return <String, dynamic>{
          ...item,
          'portrait': portrait,
          'tachie': portrait,
          'portrait_url': portrait,
          if (shouldUpdateAvatar) 'avatar': avatar,
          if (shouldUpdateAvatar) 'avatar_url': avatar,
        };
      }).toList();
    }

    if (payload['characters'] is List) {
      payload['characters'] = patchCharacters(payload['characters']);
    }
    if (payload['characters_detailed'] is List) {
      payload['characters_detailed'] = patchCharacters(payload['characters_detailed']);
    }

    await backend.updateScenario(scenarioId, payload);

    final updatedMap = Map<String, NovelCharacter>.of(currentScenario.characters);
    final entry = updatedMap.entries
        .where((entry) => entry.value.id == character.id || entry.value.name == character.name)
        .firstOrNull;
    if (entry != null) {
      updatedMap[entry.key] = entry.value.copyWith(
        portraitUrl: portrait,
        avatarUrl: shouldUpdateAvatar ? avatar : entry.value.avatarUrl,
      );
    }
    scenario = currentScenario.copyWith(characters: updatedMap, raw: payload);

    // 立绘更新属于原地编辑操作，不再写入全局 infoMessage，
    // 避免剧情页顶部出现“XXX 的立绘已更新”提示。
    _rebuildSentences();
    _notify();
  }

  Future<void> sendPlayerMessage(String value) async {
    final text = value.trim();
    if (text.isEmpty || isGenerating || forcedBattlePending) return;
    messages.add(NovelMessage(
      id: 'temp-user-${DateTime.now().microsecondsSinceEpoch}',
      role: NovelMessageRole.user,
      content: text,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      status: 'sending',
    ));
    await _triggerAi(text);
  }

  void _applySurroundingsPayload(JsonMap payload) {
    surroundingsData = Map<String, dynamic>.from(payload);
    surroundingsAvailability = <String, dynamic>{
      ...surroundingsAvailability,
      'available': payload['available'],
      'can_investigate': payload['can_investigate'],
      'needs_attention': payload['needs_attention'],
      'status': payload['status'],
      'reason': payload['reason'],
      'scene_key': payload['scene_key'],
      'scene_title': payload['scene_title'],
      'generated': true,
    };
  }

  Future<void> refreshSurroundingsAvailability({bool notify = true}) async {
    if (sessionId.trim().isEmpty) return;
    if (isSurroundingsAvailabilityLoading) {
      // Writer 正文完成和后台 StateAnalyzer 提交可能非常接近；如果刷新请求
      // 重叠，必须在当前请求结束后再读一次，不能把最新资格事件静默丢掉。
      _surroundingsAvailabilityRefreshPending = true;
      return;
    }
    isSurroundingsAvailabilityLoading = true;
    if (notify) _notify();
    try {
      final payload = await backend.fetchSurroundingsAvailability(sessionId);
      final incomingSceneKey = stringValue(payload['scene_key']);
      final loadedSceneKey = stringValue(surroundingsData['scene_key']);
      if (loadedSceneKey.isNotEmpty &&
          incomingSceneKey.isNotEmpty &&
          incomingSceneKey != loadedSceneKey) {
        surroundingsData = <String, dynamic>{};
        surroundingsError = '';
      }
      surroundingsAvailability = Map<String, dynamic>.from(payload);
      debugPrint(
        '[NovelSurroundings] scene=${stringValue(payload['scene_title'])} '
        'available=${boolValue(payload['available'])} '
        'canInvestigate=${boolValue(payload['can_investigate'])} '
        'status=${stringValue(payload['status'])} '
        'reason=${stringValue(payload['reason'])}',
      );
      final shouldLoadSceneInteractions =
          boolValue(payload['available']) &&
          boolValue(payload['can_investigate']) &&
          !isSurroundingsLoading &&
          (surroundingsData.isEmpty ||
              incomingSceneKey.isEmpty ||
              incomingSceneKey != loadedSceneKey);
      if (shouldLoadSceneInteractions) {
        unawaited(loadSurroundings());
      }
    } on NoSuchMethodError {
      surroundingsAvailability = <String, dynamic>{};
      surroundingsError = '当前客户端尚未接入调查接口';
    } on NovelBackendException catch (error) {
      surroundingsAvailability = <String, dynamic>{};
      surroundingsError = error.message;
    } catch (error) {
      surroundingsAvailability = <String, dynamic>{};
      surroundingsError = '调查状态暂时无法读取：$error';
    } finally {
      isSurroundingsAvailabilityLoading = false;
      if (notify) _notify();
      if (_surroundingsAvailabilityRefreshPending) {
        _surroundingsAvailabilityRefreshPending = false;
        unawaited(refreshSurroundingsAvailability(notify: notify));
      }
    }
  }

  void _scheduleSurroundingsAvailabilityRefreshAfterTurn() {
    final ticket = ++_surroundingsAvailabilityPollTicket;
    final generationId = _generationId;
    unawaited(_pollSurroundingsAvailabilityAfterTurn(ticket, generationId));
  }

  Future<void> _pollSurroundingsAvailabilityAfterTurn(
    int ticket,
    int generationId,
  ) async {
    // message_saved 往往早于后台 StateAnalyzer 落库。WS 只是加速通知，
    // 这里用轻量 GET 做最终一致性兜底，避免漏一条推送后入口永远不出现。
    const delays = <Duration>[
      Duration(milliseconds: 400),
      Duration(milliseconds: 1200),
      Duration(seconds: 3),
      Duration(seconds: 6),
      Duration(seconds: 10),
    ];
    for (final delay in delays) {
      await Future<void>.delayed(delay);
      if (_disposed ||
          ticket != _surroundingsAvailabilityPollTicket ||
          generationId != _generationId) {
        return;
      }
      await refreshSurroundingsAvailability();
      if (boolValue(surroundingsAvailability['available']) &&
          boolValue(surroundingsAvailability['can_investigate'])) {
        return;
      }
    }
  }

  Future<JsonMap> loadSurroundings({bool force = false}) async {
    if (isSurroundingsLoading) return surroundingsData;
    final availableSceneKey = stringValue(surroundingsAvailability['scene_key']);
    final loadedSceneKey = stringValue(surroundingsData['scene_key']);
    if (!force &&
        surroundingsData.isNotEmpty &&
        availableSceneKey.isNotEmpty &&
        availableSceneKey == loadedSceneKey) {
      return surroundingsData;
    }
    isSurroundingsLoading = true;
    surroundingsError = '';
    _notify();
    try {
      final payload = await backend.fetchSurroundings(sessionId);
      _applySurroundingsPayload(payload);
      return surroundingsData;
    } on NovelBackendException catch (error) {
      surroundingsError = error.message;
      rethrow;
    } catch (error) {
      surroundingsError = '调查内容载入失败：$error';
      rethrow;
    } finally {
      isSurroundingsLoading = false;
      _notify();
    }
  }

  Future<JsonMap> investigateSurroundNode(String nodeId) async {
    if (isSurroundingsActionRunning) return surroundingsData;
    isSurroundingsActionRunning = true;
    surroundingsError = '';
    _notify();
    try {
      final payload = await backend.investigateSurroundNode(
        sessionId,
        nodeId,
      );
      _applySurroundingsPayload(payload);
      return surroundingsData;
    } on NovelBackendException catch (error) {
      surroundingsError = error.message;
      rethrow;
    } catch (error) {
      surroundingsError = '调查失败：$error';
      rethrow;
    } finally {
      isSurroundingsActionRunning = false;
      _notify();
    }
  }

  Future<JsonMap> combineSurroundNodes(
    String firstId,
    String secondId,
  ) async {
    if (isSurroundingsActionRunning) return surroundingsData;
    isSurroundingsActionRunning = true;
    surroundingsError = '';
    _notify();
    try {
      final payload = await backend.combineSurroundNodes(
        sessionId,
        firstId,
        secondId,
      );
      _applySurroundingsPayload(payload);
      return surroundingsData;
    } on NovelBackendException catch (error) {
      surroundingsError = error.message;
      rethrow;
    } catch (error) {
      surroundingsError = '组合失败：$error';
      rethrow;
    } finally {
      isSurroundingsActionRunning = false;
      _notify();
    }
  }

  Future<JsonMap> claimSurroundReward(String nodeId) async {
    if (isSurroundingsActionRunning) return surroundingsData;
    isSurroundingsActionRunning = true;
    surroundingsError = '';
    _notify();
    try {
      final payload = await backend.claimSurroundReward(sessionId, nodeId);
      _applySurroundingsPayload(payload);
      final reward = asJsonMap(payload['reward']);
      final rewardType = stringValue(
        reward['type'] ?? reward['item_type'],
      ).trim().toLowerCase();
      if (rewardType == 'score') {
        final gained = intValue(reward['score'] ?? reward['quantity']);
        score = NovelScore(
          total: intValue(reward['new_score'], score.total + gained),
          delta: gained,
          reason: '探索发现',
        );
      } else {
        await refreshInventory(notify: false);
      }
      return payload;
    } on NovelBackendException catch (error) {
      surroundingsError = error.message;
      rethrow;
    } catch (error) {
      surroundingsError = '领取失败：$error';
      rethrow;
    } finally {
      isSurroundingsActionRunning = false;
      _notify();
    }
  }

  Future<void> startSurroundEncounter({
    required String nodeId,
    required String targetName,
  }) async {
    final cleanNodeId = nodeId.trim();
    if (cleanNodeId.isEmpty || isStartingBattle || forcedBattlePending) return;
    final cleanTarget = targetName.trim().isEmpty ? '未知敌人' : targetName.trim();
    final sceneKey = stringValue(surroundingsData['scene_key']).trim();
    final optionId = 'surround:$sceneKey:$cleanNodeId';
    _pendingBattleStart = NovelPendingBattleStart(
      optionId: optionId,
      targetName: cleanTarget,
      battleMode: 'hostile',
      fromSurroundings: true,
      loadPayload: () async {
        final payload = await backend.startSurroundEncounter(
          sessionId,
          cleanNodeId,
        );
        final battleId = stringValue(payload['battle_id']).trim();
        if (battleId.isEmpty || asJsonMap(payload['battle_opponent']).isEmpty) {
          throw const NovelBackendException('后端没有返回完整的探索战斗快照');
        }
        return await _attachNovelCompanionStarsToBattle(payload);
      },
    );
    isStartingBattle = true;
    lastError = '';
    _notify();
  }

  Future<void> finishSurroundingsBattle() async {
    _activeBattleOptionId = '';
    await refreshInventory(notify: false);
    await refreshSurroundingsAvailability(notify: false);
    try {
      await loadSurroundings(force: true);
    } catch (_) {
      // 战斗已完成时背包结算仍然有效；调查页允许玩家稍后手动重试刷新。
    }
    _notify();
  }

  /// 同步探索画面所需的两份后端权威状态：场景资产与场景交互节点。
  Future<void> refreshSceneExplorationState({bool forceMap = true}) async {
    await refreshSceneMap(force: forceMap, notify: false);
    await refreshSurroundingsAvailability(notify: false);
    if (boolValue(surroundingsAvailability['available']) &&
        boolValue(surroundingsAvailability['can_investigate'])) {
      try {
        await loadSurroundings(force: true);
      } catch (_) {
        // 地图与正文仍可使用；探索页会展示 surroundingsError 并允许后续事件重试。
      }
    }
    _notify();
  }

  /// 刷新包含当前位置、一跳导航目标和已发现的大场景。
  /// `novel_backend.dart` 可直接实现 fetchSceneMap(sessionId)，也可以在
  /// 构造 Controller 时通过 sceneMapLoader 注入，避免页面依赖 HTTP 细节。
  Future<void> refreshSceneMap({
    bool force = false,
    bool notify = true,
  }) async {
    if (isSceneMapLoading || sessionId.trim().isEmpty) return;
    final now = DateTime.now();
    if (!force &&
        _lastSceneMapRefreshAt != null &&
        now.difference(_lastSceneMapRefreshAt!) <
            const Duration(seconds: 2)) {
      return;
    }

    isSceneMapLoading = true;
    sceneMapError = '';
    if (force) sceneMoveError = '';
    if (notify) _notify();
    try {
      final Map<String, dynamic> payload;
      if (sceneMapLoader != null) {
        payload = await sceneMapLoader!(sessionId);
      } else {
        payload = await backend.fetchSceneMap(sessionId);
      }
      sceneMap = NovelSceneMapData.fromDynamic(payload);
      sceneMapPayload = Map<String, dynamic>.of(payload);
      final assetStatus = stringValue(
        sceneMap.currentScene.sceneAsset['status'],
      ).trim().toLowerCase();
      isBackgroundGenerating = const <String>{
        'queued',
        'pending',
        'processing',
        'generating',
      }.contains(assetStatus);
      final autoBattle = asJsonMap(payload['auto_battle']);
      if (boolValue(autoBattle['required'])) {
        _registerForcedBattleTrigger(autoBattle, notify: false);
      }
      _applyStoryClock(payload['story_clock']);
      sceneMapRevision += 1;
      _lastSceneMapRefreshAt = DateTime.now();
    } on NoSuchMethodError {
      sceneMapError = '当前客户端尚未接入场景地图接口';
    } on NovelBackendException catch (error) {
      sceneMapError = error.message;
    } catch (error) {
      sceneMapError = '地图暂时无法载入：$error';
    } finally {
      isSceneMapLoading = false;
      if (notify) _notify();
    }
  }

  /// 点击地图节点只提交移动意图，不直接修改当前位置。
  /// 后端会在普通聊天回合开始前再次检查连接、战斗和角色行动状态。
  Future<bool> requestSceneMove(NovelSceneMapNode target) async {
    sceneMoveError = '';
    if (!canMoveToScene(target)) {
      sceneMoveError = target.isLocked && target.reason.isNotEmpty
          ? target.reason
          : sceneMoveDisabledReason;
      if (sceneMoveError.isEmpty) sceneMoveError = '当前无法前往该场景';
      _notify();
      return false;
    }

    isSceneMoveSubmitting = true;
    _notify();
    try {
      final Map<String, dynamic> result;
      if (sceneMoveIntentCreator != null) {
        result = await sceneMoveIntentCreator!(sessionId, target.sceneId);
      } else {
        result = await backend.createSceneMoveIntent(
          sessionId,
          target.sceneId,
        );
      }

      final accepted = _sceneBool(result['accepted']);
      if (!accepted) {
        sceneMoveError = _sceneString(result['message']);
        if (sceneMoveError.isEmpty) {
          sceneMoveError = _sceneString(result['reason']);
        }
        if (sceneMoveError.isEmpty) sceneMoveError = '该场景当前不可达';
        return false;
      }

      final chatInput = _sceneString(result['chat_input']);
      final navigationAction = _sceneJsonMap(result['navigation_action']);
      if (chatInput.isEmpty || navigationAction.isEmpty) {
        sceneMoveError = '移动意图返回不完整，请稍后重试';
        return false;
      }

      messages.add(
        NovelMessage(
          id: 'temp-user-map-${DateTime.now().microsecondsSinceEpoch}',
          role: NovelMessageRole.user,
          content: chatInput,
          timestamp: DateTime.now().millisecondsSinceEpoch,
          status: 'sending',
        ),
      );

      // 先恢复按钮状态，让地图面板可以立即关闭；生成流程会同步进入
      // isGenerating，防止用户在关闭动画期间重复点击。
      isSceneMoveSubmitting = false;
      _notify();
      unawaited(
        _triggerAi(
          chatInput,
          isAction: true,
          navigationAction: navigationAction,
        ),
      );
      return true;
    } on NoSuchMethodError {
      sceneMoveError = '当前客户端尚未接入场景移动接口';
      return false;
    } on NovelBackendException catch (error) {
      sceneMoveError = error.message;
      return false;
    } catch (error) {
      sceneMoveError = '路线确认失败：$error';
      return false;
    } finally {
      if (isSceneMoveSubmitting) {
        isSceneMoveSubmitting = false;
        _notify();
      }
    }
  }

  Future<void> continueStory() async {
    if (isGenerating) return;
    if (forcedBattlePending) {
      // “继续”只是从已发生的袭击切入 Battle UI，不再生成任何新剧情。
      await _queueForcedBattleStart();
      return;
    }
    if (choices.isNotEmpty && !hasNext) {
      choicesVisible = true;
      _notify();
      return;
    }
    await _triggerAi('');
  }

  Future<void> forceContinue() async {
    if (isGenerating) return;
    if (forcedBattlePending) {
      await _queueForcedBattleStart();
      return;
    }
    const prompt = '（玩家选择了静静等待或没有做出明确动作。请顺着当前的氛围继续向下描写，可以是 NPC 主动的动作与对话、周遭环境的细节变化，或是时间的自然流逝，让故事自然而然地发展。）';
    await _triggerAi(prompt, isCommand: true, allowLuckyCard: false);
  }

  Future<void> selectChoice(NovelChoice choice) async {
    if (choice.text.trim().isEmpty ||
        isGenerating ||
        isStartingBattle ||
        forcedBattlePending) return;
    if (choice.isBattle) {
      await _startBattleChoice(choice);
      return;
    }
    // 选项提交走“可恢复事务”：
    // 在真正收到后端流事件前如果连接失败/超时，恢复当前剧情与原选项，
    // 不让界面永久停在“故事酝酿中”。
    await _triggerAi(
      choice.text,
      isAction: choice.isAction,
      restoreUiOnEarlyFailure: true,
    );
  }

  Future<void> _startBattleChoice(NovelChoice choice) async {
    final optionId = choice.optionId;
    if (optionId.isEmpty) {
      lastError = '这个战斗选项缺少有效标识，请继续剧情后重新选择。';
      _notify();
      return;
    }
    final starter = battleStarter;
    if (starter == null) {
      lastError = '当前客户端尚未配置剧情战斗入口。';
      _notify();
      return;
    }

    final targetName = choice.battleTargetName.trim().isNotEmpty
        ? choice.battleTargetName.trim()
        : choice.text.trim();
    final battleMode = choice.battleMode.trim().isEmpty
        ? 'hostile'
        : choice.battleMode.trim().toLowerCase();

    // 不再在剧情页 await 十几秒。
    // 这里只登记一份“可重复调用”的加载请求，下一帧由 Battle 页面接管。
    _pendingBattleStart = NovelPendingBattleStart(
      optionId: optionId,
      targetName: targetName,
      battleMode: battleMode,
      fromSurroundings: false,
      loadPayload: () async {
        final payload = await starter(sessionId, optionId);
        final battleId = stringValue(payload['battle_id']).trim();
        if (battleId.isEmpty ||
            asJsonMap(payload['battle_opponent']).isEmpty) {
          throw const NovelBackendException('后端没有返回完整的战斗快照');
        }
        return await _attachNovelCompanionStarsToBattle(payload);
      },
    );
    isStartingBattle = true;
    lastError = '';
    _notify();
  }

  /// 返回完整结算数据供战斗结束页展示；null 表示结算失败。
  Future<JsonMap?> settleStoryBattle({
    required String battleId,
    required String outcome,
    required List<JsonMap> consumptions,
  }) async {
    final settler = battleSettler;
    if (battleId.trim().isEmpty) {
      lastError = '当前战斗缺少有效结算标识。';
      _notify();
      return null;
    }
    try {
      JsonMap settlement = const <String, dynamic>{};
      if (settler != null) {
        settlement = await settler(
          sessionId,
          battleId.trim(),
          outcome.trim().toLowerCase(),
          consumptions,
        );
      } else {
        settlement = await backend.settleBattleItems(
          sessionId: sessionId,
          battleId: battleId.trim(),
          outcome: outcome.trim().toLowerCase(),
          consumptions: consumptions,
        );
      }
      final scoreReward = asJsonMap(settlement['score_reward']);
      if (scoreReward.isNotEmpty) {
        final gained = intValue(scoreReward['score']);
        score = NovelScore(
          total: intValue(scoreReward['new_score'], score.total + gained),
          delta: gained,
          reason: stringValue(scoreReward['source']) == 'story_battle'
              ? '主线战斗奖励'
              : '探索战斗奖励',
        );
      }
      final skillReward = asJsonMap(settlement['skill_reward']);
      if (skillReward.isNotEmpty) {
        await refreshCharacterStatus(notify: false);
        _enqueueHudEvent(
          kind: 'skill',
          title: '领悟新技能',
          detail: stringValue(skillReward['name'], '新技能'),
          tone: 'accent',
          dedupeKey: 'battle-skill:$battleId',
        );
      }
      await refreshInventory(notify: false);
      await refreshSurroundingsAvailability(notify: false);
      _notify();
      return settlement;
    } catch (error) {
      lastError = error is NovelBackendException
          ? error.message
          : '战斗结算失败，请重试。';
      _notify();
      return null;
    }
  }

  Future<void> continueAfterStoryBattle({
    required String targetName,
    required String battleMode,
    required String outcome,
  }) async {
    _clearForcedBattleTrigger();
    final resultLabel = switch (outcome.trim().toLowerCase()) {
      'victory' => '玩家获胜',
      'defeat' => '玩家落败',
      'escaped' => '玩家成功脱离战斗',
      _ => '战斗已经结束',
    };
    final modeLabel = switch (battleMode.trim().toLowerCase()) {
      'spar' => '切磋',
      'training' => '训练战',
      'duel' => '决斗',
      'defend' => '防卫战',
      _ => '战斗',
    };
    final target = targetName.trim().isEmpty ? '当前目标' : targetName.trim();
    choices.removeWhere((item) => item.optionId == _activeBattleOptionId);
    choicesVisible = false;
    _activeBattleOptionId = '';
    await _triggerAi(
      '（战斗系统权威结算：与$target的$modeLabel已经结束，结果为$resultLabel。'
      '请严格承接该结果继续描写后续剧情，不要重新进行或重新判定同一场战斗。）',
      isCommand: true,
      allowLuckyCard: false,
    );
  }

  Future<void> _triggerAi(
    String userPayload, {
    bool isCommand = false,
    bool isAction = false,
    bool allowLuckyCard = true,
    bool restoreUiOnEarlyFailure = false,
    Map<String, dynamic> navigationAction = const <String, dynamic>{},
  }) async {
    if (isGenerating) return;

    final preGenerationMessages = List<NovelMessage>.of(messages);
    final recoveryBaselineTurn = currentTurn;
    final recoveryBaselineAssistantId =
        _latestAssistantIn(preGenerationMessages)?.id ?? '';

    // 所有生成都保留一个纯前端快照。普通网络早失败仍按旧 restoreUiOnEarlyFailure
    // 规则恢复；MODEL_REFUSAL / MODEL_CONTENT_BLOCKED 则无条件恢复，因为服务端保证
    // story_state_changed=false，本轮在故事世界里从未发生。
    final rollbackMessages = List<NovelMessage>.of(preGenerationMessages);
    if (rollbackMessages.isNotEmpty) {
      final tail = rollbackMessages.last;
      if (tail.role == NovelMessageRole.user &&
          tail.isTemporary &&
          tail.status.trim().toLowerCase() == 'sending') {
        rollbackMessages.removeLast();
      }
    }
    final rollbackChoices = List<NovelChoice>.of(choices);
    final rollbackChoicesVisible = choicesVisible;
    final rollbackPlayerHint = playerHint;
    final rollbackSentenceIndex = currentSentenceIndex;
    final rollbackLuckyCardActive = luckyCardActive;
    final rollbackLuckyCardCount = luckyCardCount;

    final generationId = ++_generationId;
    final prompt = userPayload.isEmpty ? '（请继续描写接下来的剧情发展）' : userPayload;
    final clean = prompt.trim();
    final commandMode = isCommand ||
        ((clean.startsWith('（') && clean.endsWith('）')) ||
            (clean.startsWith('(') && clean.endsWith(')'))) ||
        userPayload.isEmpty;

    final historyPayload = parser.trimHistory(messages, 50);
    final activeLore = parser.scanLorebook(scenario?.lorebook ?? const <JsonMap>[], prompt);
    final ragQuery = parser.generateSearchQuery(prompt, messages);
    final temporaryAi = NovelMessage(
      id: 'temp-ai-${DateTime.now().microsecondsSinceEpoch}',
      role: NovelMessageRole.assistant,
      content: '',
      characterName: _defaultAiCharacter()?.name ?? 'AI',
      timestamp: DateTime.now().millisecondsSinceEpoch,
      status: 'streaming',
    );
    if (messages.isNotEmpty && messages.last.role == NovelMessageRole.assistant) {
      messages[messages.length - 1] = temporaryAi;
    } else {
      messages.add(temporaryAi);
    }

    // 新一轮生成开始前清掉上一轮尚未显示的 UI 缓冲。
    _streamUiTimer?.cancel();
    _streamUiTimer = null;
    _pendingStreamText = '';

    _generationHasReadablePage = false;
    isGenerating = true;
    choicesVisible = false;
    choices = <NovelChoice>[];
    playerHint = '';
    currentSentenceIndex = 0;
    lastError = '';
    _rebuildSentences(resetIndex: true);
    _notify();

    final useLucky = allowLuckyCard && luckyCardActive;
    if (useLucky) {
      luckyCardActive = false;
      luckyCardCount = (luckyCardCount - 1).clamp(0, 1 << 30).toInt();
    }

    final request = NovelSendRequest(
      prompt: prompt,
      sessionId: sessionId,
      scenarioId: scenarioId,
      characterInstanceId: _defaultAiCharacter()?.id ?? '',
      isCommand: commandMode,
      isAction: isAction,
      useLuckyCard: useLucky,
      activeLoreEntries: activeLore,
      ragQuery: ragQuery,
      clientHistory: historyPayload,
    );

    var receivedServerProgress = false;

    void restorePreGenerationUi({bool force = false}) {
      if (!force && (!restoreUiOnEarlyFailure || receivedServerProgress)) {
        return;
      }

      _streamUiTimer?.cancel();
      _streamUiTimer = null;
      _pendingStreamText = '';

      messages = List<NovelMessage>.of(rollbackMessages);
      choices = List<NovelChoice>.of(rollbackChoices);
      choicesVisible = rollbackChoicesVisible;
      playerHint = rollbackPlayerHint;
      luckyCardActive = rollbackLuckyCardActive;
      luckyCardCount = rollbackLuckyCardCount;
      isGenerating = false;

      _rebuildSentences(resetIndex: true);
      if (sentences.isNotEmpty) {
        currentSentenceIndex =
            rollbackSentenceIndex.clamp(0, sentences.length - 1).toInt();
      } else {
        currentSentenceIndex = 0;
      }
    }

    try {
      final Stream<NovelStreamEvent> responseStream;
      if (navigationAction.isEmpty) {
        responseStream = backend.sendMessageStream(request);
      } else if (navigationStreamSender != null) {
        responseStream = navigationStreamSender!(request, navigationAction);
      } else {
        // NovelBackend 对应适配方法负责把 navigation_action 与原聊天请求
        // 一起发出。不能把它拼进用户文字，否则会降低 Writer 的理解稳定性。
        responseStream = backend.sendNavigationMessageStream(
          request,
          navigationAction,
        );
      }

      await for (final event in responseStream) {
        if (generationId != _generationId || _disposed) return;
        if (event.type != NovelStreamEventType.error &&
            event.type != NovelStreamEventType.ignored) {
          receivedServerProgress = true;
        }
        switch (event.type) {
          case NovelStreamEventType.text:
            _appendStreamText(event.text);
            break;
          case NovelStreamEventType.speakerSentence:
            // 真 Speaker 流：每个事件只代表一个已经稳定的阅读页。
            // 这里只 append/幂等覆盖对应 index，绝不能把它当 completed。
            _flushStreamText(notify: false);
            _applySpeakerSentence(event);
            break;
          case NovelStreamEventType.messageSaved:
            // 新版协议中 message_saved 永远是本轮唯一最终帧。
            // 所有逐页增量都已经通过 speaker_sentence append 完成。
            _flushStreamText(notify: false);
            await _completeGeneration(event);
            break;
          case NovelStreamEventType.suggestions:
            choices = event.suggestions;
            if (event.playerHint.isNotEmpty) playerHint = event.playerHint;
            _notify();
            break;
          case NovelStreamEventType.playerHint:
            playerHint = event.playerHint;
            _notify();
            break;
          case NovelStreamEventType.score:
            if (event.score != null) _applyScoreUpdate(event.score!);
            _notify();
            break;
          case NovelStreamEventType.error:
            throw NovelBackendException(
              event.errorMessage.isEmpty ? '生成失败' : event.errorMessage,
              statusCode: event.statusCode,
              code: event.code,
              details: event.raw,
            );
          case NovelStreamEventType.ignored:
            break;
        }
      }
      if (generationId == _generationId && isGenerating) {
        _flushStreamText(notify: false);
        final rollbackEarlyChoice =
            restoreUiOnEarlyFailure && !receivedServerProgress;
        if (rollbackEarlyChoice) {
          restorePreGenerationUi();
        } else {
          isGenerating = false;
          _rebuildSentences();
          lastError = '剧情连接提前结束，正在恢复最终内容。';
          _notify();
          final recovered = await _recoverInterruptedGeneration(
            generationId: generationId,
            baselineTurn: recoveryBaselineTurn,
            baselineAssistantId: recoveryBaselineAssistantId,
            fallbackMessages: preGenerationMessages,
          );
          if (!recovered && generationId == _generationId) {
            lastError = '剧情连接已中断，尚未获取到完整内容，请稍后重试。';
            _notify();
          }
        }
      }
    } on NovelBackendException catch (error) {
      if (generationId != _generationId) return;

      final errorCode = error.code.trim().toUpperCase();
      final errorDetails = asJsonMap(error.details);
      final isNonMutatingModelRefusal =
          const <String>{'MODEL_REFUSAL', 'MODEL_CONTENT_BLOCKED'}
                  .contains(errorCode) &&
              !boolValue(errorDetails['story_state_changed']);

      if (isNonMutatingModelRefusal) {
        // 这是唯一必须“强制回到发起前 UI”的失败类型。拒绝正文没有落库，
        // 也没有任何权威状态结算，因此绝不调用任何权威恢复或场景刷新接口。
        restorePreGenerationUi(force: true);
        // Dice 是 Writer 前的瞬时视觉反馈；拒绝轮不成立时一并撤掉，避免玩家
        // 误以为这次行动已经被剧情系统正式结算。骰子算法与权威结果本身不改。
        _diceTimer?.cancel();
        _diceTimer = null;
        showDice = false;
        diceRoll = null;
        lastError = '';
        insufficientBalance = false;
        _pendingGenerationNotice = <String, dynamic>{
          'code': errorCode,
          'message': error.message.trim().isEmpty
              ? '当前模型拒绝生成，可能触发敏感内容；剧情未发生变化。'
              : error.message.trim(),
          'retryable': boolValue(errorDetails['retryable'], true),
          'story_state_changed': false,
          'model': stringValue(errorDetails['model']),
        };
        _notify();
        return;
      }

      final rollbackEarlyChoice =
          restoreUiOnEarlyFailure && !receivedServerProgress;
      if (rollbackEarlyChoice) {
        restorePreGenerationUi();
      } else {
        _flushStreamText(notify: false);
        isGenerating = false;
      }
      lastError = error.message;
      insufficientBalance = error.isInsufficientBalance;
      _notify();

      if (!rollbackEarlyChoice) {
        final shouldWaitForCommit =
            receivedServerProgress || error.code.toUpperCase().startsWith('STREAM_');
        if (shouldWaitForCommit) {
          await _recoverInterruptedGeneration(
            generationId: generationId,
            baselineTurn: recoveryBaselineTurn,
            baselineAssistantId: recoveryBaselineAssistantId,
            fallbackMessages: preGenerationMessages,
          );
        } else {
          await _recoverAuthoritativeState();
        }
      }
    } catch (error) {
      if (generationId != _generationId) return;
      final rollbackEarlyChoice =
          restoreUiOnEarlyFailure && !receivedServerProgress;
      if (rollbackEarlyChoice) {
        restorePreGenerationUi();
      } else {
        _flushStreamText(notify: false);
        isGenerating = false;
      }
      lastError = '生成中断：$error';
      _notify();
      if (!rollbackEarlyChoice) {
        final recovered = await _recoverInterruptedGeneration(
          generationId: generationId,
          baselineTurn: recoveryBaselineTurn,
          baselineAssistantId: recoveryBaselineAssistantId,
          fallbackMessages: preGenerationMessages,
        );
        if (!recovered && generationId == _generationId) {
          lastError = '生成连接中断，尚未获取到完整内容，请稍后重试。';
          _notify();
        }
      }
    }
  }

  void _appendStreamText(String rawText) {
    if (rawText.isEmpty || messages.isEmpty) return;

    // 只缓存，不在每个网络 token 到达时立刻做正则清洗、分页解析和整页 notify。
    // 48ms 内的 token 一次性合并，兼顾逐字平滑度与手机端 CPU / layout 压力。
    _pendingStreamText += rawText.replaceAll(r'\n', '\n');
    _streamUiTimer ??= Timer(_streamUiInterval, () => _flushStreamText());
  }

  void _flushStreamText({bool notify = true}) {
    _streamUiTimer?.cancel();
    _streamUiTimer = null;

    if (_pendingStreamText.isEmpty || messages.isEmpty) {
      _pendingStreamText = '';
      return;
    }

    final pending = _pendingStreamText;
    _pendingStreamText = '';

    final last = messages.last;
    final content = parser.cleanStreamingText('${last.content}$pending');
    messages[messages.length - 1] = last.copyWith(content: content);
    _markLatestUserSuccess();
    _rebuildSentences();
    if (notify) _notify();
  }

  Future<void> _completeGeneration(NovelStreamEvent event) async {
    if (messages.isEmpty) return;
    final visibleSentenceIndex = currentSentenceIndex;
    final last = messages.last;
    final streamedItemCount = last.sentenceItems.length;
    final streamedVisualCount = sentences.length;
    final cleanContent = event.content.isNotEmpty
        ? parser.cleanAiTags(event.content).trim()
        : last.content;

    // 与 Vue 保持一致：sentenceItems 必须先写入，再关闭 isGenerating。
    messages[messages.length - 1] = last.copyWith(
      id: event.messageId.isEmpty ? last.id : event.messageId,
      content: cleanContent,
      sentenceItems: event.sentenceItems,
      status: 'success',
    );
    _markLatestUserSuccess();
    if (event.suggestions.isNotEmpty) choices = event.suggestions;
    if (event.playerHint.isNotEmpty) playerHint = event.playerHint;
    if (event.score != null) _applyScoreUpdate(event.score!);

    // Vue message_saved 会携带 location / time_desc / weather / atmosphere。
    // 即使 WS 的 world_state_update 稍晚到达，也先同步一次页面，避免场景信息闪回旧值。
    final extra = event.raw;
    final messageGoal = stringValue(extra['current_goal']).trim();
    if (messageGoal.isNotEmpty) {
      _applyGoalPayload(<String, dynamic>{
        'objective': messageGoal,
        'node_id': extra['current_goal_node_id'],
        'index': extra['current_goal_index'],
        'total': extra['current_goal_total'],
      });
    }
    final previousMessageLocation = world.location;
    world = world.copyWith(
      location: stringValue(extra['location'], world.location),
      weather: stringValue(extra['weather'], world.weather),
      atmosphere: stringValue(extra['atmosphere'], world.atmosphere),
    );
    _applyStoryClock(extra['story_clock']);
    if (world.location != previousMessageLocation) {
      surroundingsData = <String, dynamic>{};
      surroundingsAvailability = <String, dynamic>{};
      surroundingsError = '';
      unawaited(refreshSurroundingsAvailability());
    }

    isGenerating = false;

    // 新版真流式协议的关键约束：
    // speaker_sentence 是唯一能够创建/追加“可播放阅读页”的事件；
    // message_saved 只是最终持久化确认，绝不能再次 rebuild 当前阅读队列。
    //
    // 旧逻辑在这里调用 _rebuildSentences()，即使最终 sentence_items 与已经
    // 播放的流式页面完全相同，也会让 Reader 在“最后一页 + generating=false”这个
    // 边界重新经历一次结构同步，造成偶发的最后一句二次逐字动画。
    //
    // 现在完整 sentence_items 仍然写入 messages，作为历史/刷新后的权威快照；
    // 但本轮屏幕正在使用的 sentences 列表保持原对象和原下标，最终确认不碰播放器。
    if (streamedVisualCount == 0) {
      // 防御性兜底：正常新版协议一定先收到 speaker_sentence。
      // 只有异常代理/测试环境直接送来 message_saved 时，才允许从最终快照构建一次。
      _rebuildSentences(resetIndex: true);
    } else {
      currentSentenceIndex = visibleSentenceIndex
          .clamp(0, sentences.length - 1)
          .toInt();

      if (event.sentenceItems.length != streamedItemCount) {
        debugPrint(
          'speaker final snapshot count mismatch: '
          'streamed=$streamedItemCount final=${event.sentenceItems.length}; '
          'keeping streamed reader queue to prevent replay',
        );
      }
    }
    _notify();
    unawaited(refreshSceneMap(force: true));
    _scheduleSurroundingsAvailabilityRefreshAfterTurn();

    if (event.messageId.isNotEmpty) {
      unawaited(backend.markMessageRead(scenarioId, event.messageId));
    }
  }

  void _applySpeakerSentence(NovelStreamEvent event) {
    if (messages.isEmpty || event.sentenceItems.isEmpty) return;

    final incoming = event.sentenceItems.first;
    final rawIndex = intValue(
      event.raw['sentence_index'],
      -1,
    );
    if (rawIndex < 0) return;

    final visibleSentenceIndex = currentSentenceIndex;
    final last = messages.last;
    final nextItems = List<NovelSentence>.of(last.sentenceItems);

    // 真增量协议必须严格 append。网络层即使偶发重复投递同一个 index，
    // 也只做幂等覆盖；绝不 append 第二份同页，也不允许跳号制造空洞。
    if (rawIndex < nextItems.length) {
      nextItems[rawIndex] = incoming;
    } else if (rawIndex == nextItems.length) {
      nextItems.add(incoming);
    } else {
      debugPrint(
        'speaker sentence out of order: index=$rawIndex current=${nextItems.length}',
      );
      return;
    }

    messages[messages.length - 1] = last.copyWith(
      id: event.messageId.isEmpty ? last.id : event.messageId,
      sentenceItems: nextItems,
      status: 'streaming',
    );
    _markLatestUserSuccess();
    _rebuildSentences();
    if (novelTextHasReadableContent(incoming.readerText)) {
      _generationHasReadablePage = true;
    }

    // 新页只进入队列，不抢玩家当前正在看的页。第一页首次到达时 index=0
    // 自然可见；之后 Speaker 再快也不会自动跳到最后一页。
    if (sentences.isNotEmpty) {
      currentSentenceIndex =
          visibleSentenceIndex.clamp(0, sentences.length - 1).toInt();
    }
    _notify();
  }

  void _markLatestUserSuccess() {
    for (var i = messages.length - 1; i >= 0; i--) {
      if (messages[i].role == NovelMessageRole.user) {
        messages[i] = messages[i].copyWith(status: 'success');
        return;
      }
    }
  }

  NovelCharacter? _defaultAiCharacter() {
    for (final character in scenario?.characters.values ?? const <NovelCharacter>[]) {
      if (!character.isMain) return character;
    }
    return scenario?.characters.values.firstOrNull;
  }

  Future<void> cancelGeneration() async {
    _generationId += 1;
    // 主动停止时仍把已收到的文字显示出来。
    _flushStreamText(notify: false);
    await backend.cancelActiveStream();
    isGenerating = false;
    _rebuildSentences();
    _notify();
  }

  Future<void> syncHistory() async {
    if (isSyncingHistory) return;
    isSyncingHistory = true;
    _notify();
    try {
      await cancelGeneration();
      final history = await backend.fetchHistory(sessionId, force: true);
      _applyHistory(history, preserveReaderPosition: true);
      await Future.wait(<Future<void>>[
        refreshCharacterStatus(notify: false),
        refreshCurrentGoal(notify: false),
        refreshSurroundingsAvailability(notify: false),
        refreshInventory(notify: false),
      ]);
      await refreshSceneMap(force: true, notify: false);
    } catch (error) {
      lastError = '同步故事状态失败：$error';
    } finally {
      isSyncingHistory = false;
      _notify();
    }
  }

  NovelMessage? _latestAssistantIn(Iterable<NovelMessage> source) {
    for (final message in source.toList().reversed) {
      if (message.role == NovelMessageRole.assistant && !message.isTemporary) {
        return message;
      }
    }
    return null;
  }

  bool _historyContainsCompletedTurn(
    NovelHistoryResult history, {
    required int baselineTurn,
    required String baselineAssistantId,
  }) {
    final latest = _latestAssistantIn(history.messages);
    if (latest == null || !novelTextHasReadableContent(latest.content)) {
      return false;
    }
    final status = latest.status.trim().toLowerCase();
    final statusComplete = !const <String>{
      'sending',
      'streaming',
      'pending',
      'generating',
    }.contains(status);
    final turnAdvanced = history.currentTurn > baselineTurn;
    final messageChanged =
        latest.id.isNotEmpty && latest.id != baselineAssistantId;
    return turnAdvanced || (messageChanged && statusComplete);
  }

  Future<void> _refreshRecoveredSideState() async {
    await Future.wait(<Future<void>>[
      refreshCharacterStatus(notify: false),
      refreshCurrentGoal(notify: false),
      refreshSurroundingsAvailability(notify: false),
      refreshInventory(notify: false),
    ]);
    await refreshSceneMap(force: true, notify: false);
  }

  Future<bool> _recoverInterruptedGeneration({
    required int generationId,
    required int baselineTurn,
    required String baselineAssistantId,
    required List<NovelMessage> fallbackMessages,
  }) async {
    // SSE 断开不代表后端停止。等待权威回合真正落库后再覆盖本地内容，
    // 避免第一次历史请求过早，把已有正文替换成空白页。
    await backend.cancelActiveStream();
    // 最多补拉 3 次；任意一次确认完整回合后立即结束。
    const delays = <Duration>[
      Duration.zero,
      Duration(milliseconds: 600),
      Duration(milliseconds: 1500),
    ];

    for (final delay in delays) {
      if (_disposed || generationId != _generationId) return false;
      if (delay != Duration.zero) await Future<void>.delayed(delay);
      if (_disposed || generationId != _generationId) return false;
      try {
        final history = await backend.fetchHistory(sessionId, force: true);
        if (!_historyContainsCompletedTurn(
          history,
          baselineTurn: baselineTurn,
          baselineAssistantId: baselineAssistantId,
        )) {
          continue;
        }
        _applyHistory(history, preserveReaderPosition: true);
        await _refreshRecoveredSideState();
        lastError = '';
        _notify();
        return true;
      } catch (_) {
        // 网络尚未恢复时继续下一档退避；最终失败统一保留本地已收到正文。
      }
    }

    final currentAi = lastAssistantMessage;
    if (currentAi == null || !novelTextHasReadableContent(currentAi.content)) {
      messages = List<NovelMessage>.of(fallbackMessages);
      _rebuildSentences(resetIndex: false);
    }
    _notify();
    return false;
  }

  Future<void> _recoverAuthoritativeState() async {
    if (_disposed || sessionId.trim().isEmpty) return;
    if (isRecoveringConnection) {
      _authoritativeRecoveryPending = true;
      return;
    }
    isRecoveringConnection = true;
    _notify();
    try {
      // 正在正常接收 SSE 时不能为了 WebSocket 重连而取消正文流。
      if (!isGenerating) {
        final history = await backend.fetchHistory(sessionId, force: true);
        _applyHistory(history, preserveReaderPosition: true);
      }
      await _refreshRecoveredSideState();
    } catch (error) {
      lastError = '连接恢复后同步状态失败：$error';
    } finally {
      isRecoveringConnection = false;
      _notify();
      if (_authoritativeRecoveryPending) {
        _authoritativeRecoveryPending = false;
        unawaited(_recoverAuthoritativeState());
      }
    }
  }

  Future<void> recoverAfterResume() async {
    try {
      await socket.connect(sessionId);
    } catch (_) {
      // WebSocket 可能仍处于自动重连退避；HTTP 补拉不应因此被跳过或向 UI 抛异常。
    }
    await _recoverAuthoritativeState();
  }

  void goNext() {
    if (pendingFateRevert && !hasNext) {
      showFateRevert = true;
      pendingFateRevert = false;
      _notify();
      return;
    }
    if (hasNext) {
      currentSentenceIndex += 1;
      _notify();
    }
  }

  void goPrevious() {
    if (hasPrevious) {
      currentSentenceIndex -= 1;
      _notify();
    }
  }

  void goLatest() {
    if (sentences.isNotEmpty) {
      currentSentenceIndex = sentences.length - 1;
      _notify();
    }
  }

  Future<void> handlePanelTap() async {
    if (hasNext || pendingFateRevert) {
      goNext();
    }
  }

  void toggleLuckyCard() {
    if (luckyCardCount <= 0) return;
    luckyCardActive = !luckyCardActive;
    _notify();
  }

  Future<void> refreshCharacterStatus({bool notify = true}) async {
    try {
      final list = await backend.fetchCharacterStatus(scenarioId);
      if (list.isEmpty || scenario == null) return;
      final updated = Map<String, NovelCharacter>.of(scenario!.characters);
      for (final incoming in list) {
        final key = incoming.id.isNotEmpty
            ? incoming.id
            : updated.entries
                    .where((entry) => entry.value.name == incoming.name)
                    .map((entry) => entry.key)
                    .firstOrNull ??
                incoming.name;
        final existing = updated[key];
        updated[key] = existing == null
            ? incoming
            : existing.copyWith(
                name: incoming.name,
                avatarUrl: incoming.avatarUrl.isNotEmpty ? incoming.avatarUrl : existing.avatarUrl,
                portraitUrl: incoming.portraitUrl.isNotEmpty ? incoming.portraitUrl : existing.portraitUrl,
                affection: incoming.affection,
                affectionLabel: incoming.affectionLabel,
                romance: incoming.romance,
                inhibition: incoming.inhibition,
                status: incoming.status.isNotEmpty ? incoming.status : existing.status,
                milestones: incoming.milestones.isNotEmpty ? incoming.milestones : existing.milestones,
              );
      }
      scenario = scenario!.copyWith(characters: updated);
      final host = updated.values.where((character) => character.isMain).firstOrNull;
      if (host != null) {
        protagonistCondition = stringValue(
          host.status['current_condition'],
          protagonistCondition,
        );
        if (host.status['injuries'] is List) {
          protagonistInjuries = List<dynamic>.of(host.status['injuries'] as List);
        }
      }
      if (notify) _notify();
    } catch (error) {
      if (notify) {
        lastError = '角色状态刷新失败：$error';
        _notify();
      }
    }
  }

  Set<String> _novelCharacterRosterIds(JsonMap item) {
    final ids = <String>{};
    for (final value in <dynamic>[
      item['character_instance_id'],
      item['character_id'],
      item['id'],
    ]) {
      final id = stringValue(value).trim();
      if (id.isNotEmpty) ids.add(id);
    }
    return ids;
  }

  String _novelCharacterRosterName(JsonMap item) {
    return stringValue(
      item['character_name'] ?? item['name'] ?? item['display_name'],
    ).trim();
  }

  String? _findNovelCharacterRosterKey(
    Map<String, JsonMap> source,
    JsonMap item,
  ) {
    final ids = _novelCharacterRosterIds(item);
    String? matchedKey;

    if (ids.isNotEmpty) {
      for (final entry in source.entries) {
        final existingIds = _novelCharacterRosterIds(entry.value);
        final matches = ids.contains(entry.key) ||
            existingIds.any((candidate) => ids.contains(candidate));
        if (!matches) continue;
        matchedKey ??= entry.key;
        // roster 返回的条目带 star，是结缘系统的权威角色条目。
        // companion payload 只负责技能/出战状态，应合并到这里而不是另起一条。
        if (entry.value.containsKey('star')) return entry.key;
      }
    }

    final name = _novelCharacterRosterName(item);
    if (name.isNotEmpty) {
      for (final entry in source.entries) {
        if (_novelCharacterRosterName(entry.value) != name) continue;
        matchedKey ??= entry.key;
        if (entry.value.containsKey('star')) return entry.key;
      }
    }
    return matchedKey;
  }

  JsonMap novelCharacterRosterEntry(String characterInstanceId) {
    final lookup = characterInstanceId.trim();
    if (lookup.isEmpty) return const <String, dynamic>{};

    final direct = novelCharacterRoster[lookup];
    final probe = <String, dynamic>{'character_id': lookup};
    final matchedKey = _findNovelCharacterRosterKey(novelCharacterRoster, probe);
    final matched = matchedKey == null ? null : novelCharacterRoster[matchedKey];

    if (direct != null || matched != null) {
      final merged = <String, dynamic>{
        ...?matched,
        ...?direct,
      };
      // 如果旧缓存里曾经因为两种 ID 分裂成两条，优先保留带 star 的权威值。
      if (matched != null && matched.containsKey('star')) {
        merged['star'] = matched['star'];
      }
      return merged;
    }

    // 极少数旧数据只在 roster 中保留实例 ID，而场景角色只保留名称。
    // 最后按角色名兜底，避免展示层因为 ID 版本差异误判为 0 星。
    NovelCharacter? scenarioCharacter;
    for (final character in scenario?.characters.values ?? const <NovelCharacter>[]) {
      if (character.id.trim() == lookup || character.name.trim() == lookup) {
        scenarioCharacter = character;
        break;
      }
    }
    final lookupName = scenarioCharacter?.name.trim() ?? lookup;
    if (lookupName.isNotEmpty) {
      for (final entry in novelCharacterRoster.entries) {
        if (_novelCharacterRosterName(entry.value) == lookupName) {
          return entry.value;
        }
      }
    }
    return const <String, dynamic>{};
  }

  bool isNovelCharacterOwned(String characterInstanceId) {
    return boolValue(
      novelCharacterRosterEntry(characterInstanceId)['owned'],
    );
  }

  int novelCharacterFragments(String characterInstanceId) {
    return intValue(
      novelCharacterRosterEntry(characterInstanceId)['fragments'],
    );
  }

  int novelCharacterStar(String characterInstanceId) {
    return intValue(
      novelCharacterRosterEntry(characterInstanceId)['star'],
    ).clamp(0, 10).toInt();
  }

  void _applyNovelCharacterRosterPayload(JsonMap payload) {
    novelCharacterFlowers = intValue(
      payload['flowers'],
      novelCharacterFlowers,
    );
    final previousRoster = novelCharacterRoster;
    final next = <String, JsonMap>{};
    for (final raw in asJsonList(payload['characters'] ?? payload['roster'])) {
      final item = asJsonMap(raw);
      final id = stringValue(
        item['character_instance_id'] ?? item['character_id'] ?? item['id'],
      ).trim();
      if (id.isEmpty) continue;

      final previousKey = _findNovelCharacterRosterKey(previousRoster, item);
      final previous =
          previousKey == null ? null : previousRoster[previousKey];
      next[id] = <String, dynamic>{
        ...?previous,
        ...item,
        if (previous != null && previous.containsKey('deployed'))
          'deployed': previous['deployed'],
        if (previous != null && previous.containsKey('skills'))
          'skills': previous['skills'],
      };
    }
    if (next.isNotEmpty ||
        payload.containsKey('characters') ||
        payload.containsKey('roster')) {
      novelCharacterRoster = next;
    }
  }

  void _applyNovelCompanionPayload(JsonMap payload) {
    final next = Map<String, JsonMap>.from(novelCharacterRoster);
    for (final raw in asJsonList(payload['characters'])) {
      final item = asJsonMap(raw);
      final id = stringValue(
        item['character_instance_id'] ?? item['character_id'] ?? item['id'],
      ).trim();
      if (id.isEmpty) continue;

      // companion 与 roster 可能分别使用 character_id / character_instance_id。
      // 先按所有别名寻找已有权威条目，再合并技能与 deployed，禁止生成重复角色。
      final targetKey = _findNovelCharacterRosterKey(next, item) ?? id;
      final existing = next[targetKey];
      next[targetKey] = <String, dynamic>{
        ...?existing,
        ...item,
        // /chat/novel-character/roster 才是星级权威来源。
        // /novel/companions 的 star 仅为兼容/战斗快照字段，可能来自旧存储并返回 0。
        // 已经有 roster 星级时，绝不能让 companion payload 把它覆盖掉。
        if (existing != null && existing.containsKey('star'))
          'star': existing['star'],
      };
    }
    novelCharacterRoster = next;
  }

  Future<JsonMap> _attachNovelCompanionStarsToBattle(JsonMap payload) async {
    // 角色星级的权威来源是 /chat/novel-character/roster。
    // Novel Router 只拥有援战阵容/技能，因此在进入战斗前做一次轻量 join，
    // 不把结缘系统的存储细节复制进第二套后端状态。
    try {
      final rosterPayload = await backend.fetchNovelCharacterRoster(sessionId);
      _applyNovelCharacterRosterPayload(rosterPayload);
      hasLoadedNovelCharacterRoster = true;
    } catch (error) {
      debugPrint('refresh companion stars before battle skipped: $error');
    }

    final next = <String, dynamic>{...payload};
    final player = asJsonMap(next['player_snapshot']);
    if (player.isEmpty) return next;

    final companions = asJsonList(player['companions']).map((raw) {
      final item = asJsonMap(raw);
      final id = stringValue(
        item['character_instance_id'] ?? item['character_id'] ?? item['id'],
      ).trim();
      final star = id.isEmpty ? 0 : novelCharacterStar(id);
      return <String, dynamic>{
        ...item,
        'star': star,
        'skill_effect_multiplier': 1.0 + star * .03,
      };
    }).toList(growable: false);

    next['player_snapshot'] = <String, dynamic>{
      ...player,
      'companions': companions,
    };
    return next;
  }

  Future<void> refreshNovelCharacterRoster({bool notify = true}) async {
    isNovelCharacterRosterLoading = true;
    if (notify) _notify();
    try {
      final payload = await backend.fetchNovelCharacterRoster(sessionId);
      _applyNovelCharacterRosterPayload(payload);
      // 即使 roster 合法为空，也代表“星级已经从后端确认过”，不能再当未知状态。
      hasLoadedNovelCharacterRoster = true;
      final companionPayload = await backend.fetchNovelCompanions(sessionId);
      _applyNovelCompanionPayload(companionPayload);
      await refreshInventory(notify: false);
    } finally {
      isNovelCharacterRosterLoading = false;
      if (notify) _notify();
    }
  }

  Future<JsonMap> drawNovelCharacters(int count) async {
    // 把 10 改为 5，或者改为支持 1, 5, 10
    if (count != 1 && count != 5 && count != 10) {
      throw const NovelBackendException('只支持结缘一次、五次或十次');
    }
    
    final payload = await backend.drawNovelCharacters(
      mainSessionId: sessionId,
      count: count,
    );
    
    _applyNovelCharacterRosterPayload(payload);
    
    await Future.wait(<Future<void>>[
      refreshInventory(notify: false),
      refreshCharacterStatus(notify: false),
    ]);
    
    _notify();
    return payload;
}

  Future<JsonMap> upgradeNovelCharacter(String characterInstanceId) async {
    final id = characterInstanceId.trim();
    if (id.isEmpty) {
      throw const NovelBackendException('角色 ID 不能为空');
    }
    final payload = await backend.upgradeNovelCharacter(
      mainSessionId: sessionId,
      characterInstanceId: id,
    );
    _applyNovelCharacterRosterPayload(payload);
    _notify();
    return payload;
  }

  List<JsonMap> novelCompanionSkills(String characterInstanceId) {
    return asJsonList(
      novelCharacterRosterEntry(characterInstanceId)['skills'],
    ).map(asJsonMap).where((item) => item.isNotEmpty).toList(growable: false);
  }

  bool isNovelCompanionDeployed(String characterInstanceId) {
    return boolValue(
      novelCharacterRosterEntry(characterInstanceId)['deployed'],
    );
  }

  int get deployedNovelCompanionCount => novelCharacterRoster.values
      .where((item) => boolValue(item['deployed']))
      .length;

  Future<JsonMap> updateNovelCompanionDeployment(
    String characterInstanceId,
    bool deployed,
  ) async {
    final id = characterInstanceId.trim();
    if (id.isEmpty) throw const NovelBackendException('角色 ID 不能为空');
    final payload = await backend.updateNovelCompanionDeployment(
      mainSessionId: sessionId,
      characterInstanceId: id,
      deployed: deployed,
    );
    _applyNovelCompanionPayload(payload);
    _notify();
    return payload;
  }

  Future<JsonMap> drawNovelCompanionSkill(String characterInstanceId) async {
    final id = characterInstanceId.trim();
    if (id.isEmpty) throw const NovelBackendException('角色 ID 不能为空');
    final payload = await backend.drawNovelCompanionSkill(
      mainSessionId: sessionId,
      characterInstanceId: id,
    );
    _applyNovelCompanionPayload(payload);
    _notify();
    return payload;
  }

  Future<JsonMap> renameNovelCompanionSkill({
    required String characterInstanceId,
    required String skillId,
    required String name,
  }) async {
    final payload = await backend.renameNovelCompanionSkill(
      mainSessionId: sessionId,
      characterInstanceId: characterInstanceId.trim(),
      skillId: skillId.trim(),
      name: name.trim(),
    );
    _applyNovelCompanionPayload(payload);
    _notify();
    return payload;
  }

  Future<JsonMap> fetchNovelCharacterChatHistory(
    String characterInstanceId, {
    int offset = 0,
    int limit = 30,
  }) {
    return backend.fetchNovelCharacterChatHistory(
      mainSessionId: sessionId,
      characterInstanceId: characterInstanceId,
      offset: offset,
      limit: limit,
    );
  }

  Stream<JsonMap> sendNovelCharacterChatStream({
    required String characterInstanceId,
    required String message,
  }) {
    return backend.sendNovelCharacterChatStream(
      mainSessionId: sessionId,
      characterInstanceId: characterInstanceId,
      message: message,
    );
  }

  void applyNovelCharacterChatEvent(JsonMap event) {
    final type = stringValue(event['type']).trim().toLowerCase();
    if (type == 'affection_update') {
      _applyAffectionUpdate(event);
      _notify();
    }
  }

  Future<void> cancelNovelCharacterChatStream() {
    return backend.cancelNovelCharacterChatStream();
  }

  Future<String> recognizeAndAcquireDeveloperContent(String rawName) async {
    final name = rawName.trim();
    if (name.isEmpty) {
      throw const NovelBackendException('名称不能为空');
    }
    final contentBackend = backend;
    if (contentBackend is! NovelDeveloperContentBackend) {
      throw const NovelBackendException('当前客户端尚未配置开发者内容识别接口');
    }
    final developerContentBackend =
        contentBackend as NovelDeveloperContentBackend;

    final payload = await developerContentBackend
        .recognizeAndAcquireDeveloperContent(
      sessionId: sessionId,
      name: name,
    );
    final recognized = boolValue(payload['recognized']);
    final reason = stringValue(payload['reason']).trim();
    if (!recognized) {
      return reason.isEmpty ? '未识别该名称，未写入存档' : '未识别：$reason';
    }

    final contentType = stringValue(payload['content_type']).trim();
    final created = boolValue(payload['created']);
    if (contentType == 'skill') {
      final rawSkills = payload['skills'];
      if (rawSkills is List) {
        _syncProtagonistStatus(<String, dynamic>{
          'skills': List<dynamic>.of(rawSkills),
        });
      } else {
        await refreshCharacterStatus(notify: false);
      }
      _notify();

      final rawSkill = payload['skill'];
      final skill = rawSkill is Map
          ? rawSkill.map<String, dynamic>(
              (key, value) => MapEntry<String, dynamic>('$key', value),
            )
          : <String, dynamic>{};
      final savedName = stringValue(skill['name'], name).trim();
      final spec = skill['battle_spec'] is Map
          ? Map<String, dynamic>.from(skill['battle_spec'] as Map)
          : <String, dynamic>{};
      final quality = intValue(spec['quality']);
      final qualityText = quality > 0 ? ' · 品质 $quality' : '';
      return created
          ? '已识别并学会「$savedName」$qualityText'
          : '已识别「$savedName」 · 技能已存在$qualityText';
    }

    await refreshInventory(notify: false);
    _notify();

    final rawItem = payload['item'];
    final item = rawItem is Map
        ? rawItem.map<String, dynamic>(
            (key, value) => MapEntry<String, dynamic>('$key', value),
          )
        : <String, dynamic>{};
    final savedName = stringValue(item['name'], name).trim();
    final quality = intValue(payload['quality'] ?? item['quality']);
    final typeText = switch (contentType) {
      'health_potion' => '生命药物',
      'energy_potion' => '精力药物',
      'weapon' => '武器',
      'armor' => '防具',
      'accessory' => '饰品',
      'quest' => '剧情物品',
      _ => '物品',
    };
    final qualityText = quality > 0 ? ' · 品质 $quality' : '';
    return created
        ? '已识别并获得「$savedName」 · $typeText$qualityText'
        : '已识别「$savedName」并增加 1 个 · $typeText$qualityText';
  }

  Future<void> refreshInventory({bool notify = true}) async {
    try {
      inventory = await backend.fetchInventory(sessionId);
      final savedProtagonist = inventory.protagonistState;
      if (savedProtagonist.isNotEmpty) {
        final savedCondition = stringValue(
          savedProtagonist['current_condition'],
          protagonistCondition,
        ).trim();
        if (savedCondition.isNotEmpty) protagonistCondition = savedCondition;
        if (savedProtagonist['injuries'] is List) {
          protagonistInjuries =
              List<dynamic>.of(savedProtagonist['injuries'] as List);
        }
        _syncProtagonistStatus(savedProtagonist);
      }
      novelCharacterFlowers = inventory.consumables
          .where((item) => item.itemType == 'gift')
          .fold<int>(0, (sum, item) => sum + item.quantity);
      luckyCardCount = inventory.consumables
          .where((item) => item.itemType == 'lucky_card')
          .fold<int>(0, (sum, item) => sum + item.quantity);
      if (luckyCardCount <= 0) luckyCardActive = false;
      if (notify) _notify();
    } catch (error) {
      if (notify) {
        lastError = '背包加载失败：$error';
        _notify();
      }
    }
  }

  Future<void> setEquipped(NovelInventoryItem item, bool equipped) async {
    // 与强化保持一致：优先使用后端返回的原始装备 ID。
    // NovelInventoryItem.id 可能经过前端归一化，直接拿它请求后端会导致
    // 穿戴/卸下时出现“物品不存在”，而强化却能正常找到同一件装备。
    final rawItemId = stringValue(
      item.raw['id'] ?? item.raw['item_id'] ?? item.raw['itemId'],
    ).trim();
    final itemId = rawItemId.isNotEmpty ? rawItemId : item.id.trim();
    if (itemId.isEmpty) {
      throw const NovelBackendException('装备ID不能为空');
    }
    if (scenario == null) {
      throw const NovelBackendException('剧本数据尚未加载');
    }

    // 背包是按当前 session 读取的；穿戴也必须把同一个 session 传给后端。
    // HttpNovelBackend 会把它作为 session_id 放进请求体，和强化链路保持一致，
    // 避免后端仅凭 scenario instance + item_id 查不到当前存档里的装备。
    await backend.equipItem(
      sessionId: sessionId,
      scenarioInstanceId: scenarioInstanceId,
      itemId: itemId,
      equipped: equipped,
    );
    await refreshInventory();
  }

  /// 消耗玄石尝试强化装备。成功率、保底、材料扣除与最终等级均以后端为准。
  ///
  /// Controller 只负责把装备和当前 scenario instance 转发给 NovelBackend，
  /// 然后重新拉取一次权威背包，让强化等级、失败保底与玄石数量同步到所有页面。
  Future<JsonMap> enhanceNovelEquipment(NovelInventoryItem item) async {
    // 优先发送后端原始装备 ID；兼容旧存档 item_id / itemId 别名。
    // NovelInventoryItem.id 可能经过前端归一化，不能在这里反过来覆盖后端真 ID。
    final rawItemId = stringValue(
      item.raw['id'] ?? item.raw['item_id'] ?? item.raw['itemId'],
    ).trim();
    final itemId = rawItemId.isNotEmpty ? rawItemId : item.id.trim();
    if (itemId.isEmpty) {
      throw const NovelBackendException('装备ID不能为空');
    }
    if (scenario == null) {
      throw const NovelBackendException('剧本数据尚未加载');
    }

    final payload = await backend.enhanceEquipment(
      sessionId: sessionId,
      scenarioInstanceId: scenarioInstanceId,
      itemId: itemId,
    );

    // 强化失败同样会消耗玄石并推进保底，因此成功/失败都必须刷新背包。
    await refreshInventory(notify: false);
    _notify();
    return payload;
  }

  Future<NovelGiftResult> giveGift(NovelCharacter character) async {
    if (scenario == null) return const NovelGiftResult();
    final result = await backend.useGift(
      sessionId: sessionId,
      scenarioInstanceId: scenarioInstanceId,
      characterInstanceId: character.id,
    );
    await Future.wait(<Future<void>>[
      refreshInventory(notify: false),
      refreshCharacterStatus(notify: false),
    ]);
    final giftName = result.characterName.isEmpty ? character.name : result.characterName;
    if (result.delta != 0) {
      _enqueueAffectionPulse(
        characterId: character.id,
        characterName: giftName,
        delta: result.delta,
        dedupeKey: 'affection:$giftName:${result.delta}',
      );
    }
    _notify();
    return result;
  }

  Future<NovelBlindBoxReward> openBlindBox() async {
    if (scenario == null) return const NovelBlindBoxReward();
    final reward = await backend.useBlindBox(
      sessionId: sessionId,
      scenarioInstanceId: scenarioInstanceId,
    );
    if (reward.newScore != null) {
      _applyScoreUpdate(NovelScore(
        total: reward.newScore!,
        delta: reward.score,
        reason: reward.jackpot ? '福袋超级奖励' : '福袋奖励',
      ));
    }
    await refreshInventory(notify: false);
    if (reward.type != 'score') {
      _enqueueHudEvent(
        kind: 'inventory',
        title: '获得 ${reward.name}',
        detail: '已放入背包',
        delta: 1,
        tone: 'accent',
        dedupeKey: 'blind-item:${reward.name}',
      );
    }
    _notify();
    return reward;
  }

  Future<void> refreshShop() async {
    shopItems = await backend.fetchShopItems(sessionId);
    _notify();
  }

  Future<void> buyShopItem(NovelShopItem item) async {
    if (scenario == null) return;
    if (score.total < item.price) {
      lastError = '积分不足';
      _notify();
      return;
    }
    final updatedScore = await backend.buyItem(
      sessionId: sessionId,
      scenarioInstanceId: scenarioInstanceId,
      itemType: item.itemType,
    );
    _applyScoreUpdate(updatedScore);
    shopItems = shopItems.map((current) {
      return current.itemType == item.itemType
          ? current.copyWith(quantity: current.quantity + 1)
          : current;
    }).toList();
    await refreshInventory(notify: false);
    
    // 替换为统一的 HUD 提示系统，它会自动定时消失
    _enqueueHudEvent(
      kind: 'inventory',
      title: '成功获得 ${item.name}',
      detail: '已放入背包',
      delta: 1,
      tone: 'accent',
      dedupeKey: 'shop-buy:${item.itemType}',
    );
    _notify();
  }

  Future<void> refreshJourney({bool notify = true}) async {
    try {
      journey = await backend.fetchJourney(scenarioId);
      if (notify) _notify();
    } catch (error) {
      if (notify) {
        lastError = '经历加载失败：$error';
        _notify();
      }
    }
  }

  Future<void> revertPreviousTurn() async {
    if (isReverting || currentTurn <= 0 || scenario == null) return;
    isReverting = true;
    lastError = '';
    _notify();
    try {
      final history = await backend.revertToTurn(
        sessionId: sessionId,
        scenarioInstanceId: scenarioInstanceId,
        targetTurn: currentTurn - 1,
      );
      _applyHistory(history);
      await refreshCharacterStatus(notify: false);
      goLatest();
    } catch (error) {
      lastError = error is NovelBackendException ? error.message : '回溯失败：$error';
    } finally {
      isReverting = false;
      _notify();
    }
  }

  Future<void> submitCharacterSetup(NovelCharacterSetupInput input) async {
    final currentScenario = scenario;
    final host = currentScenario?.protagonist;
    if (currentScenario == null || host == null) {
      lastError = '主角数据不存在';
      _notify();
      return;
    }

    final oldName = host.name;
    final newName = input.name.trim().isEmpty ? oldName : input.name.trim();
    dynamic replaceDeep(dynamic value) {
      if (value is String) return value.replaceAll(oldName, newName);
      if (value is List) return value.map(replaceDeep).toList();
      if (value is Map) {
        return value.map((key, item) => MapEntry(key.toString(), replaceDeep(item)));
      }
      return value;
    }

    final payload = asJsonMap(replaceDeep(currentScenario.raw));
    final characters = asJsonList(payload['characters']);
    final detailed = asJsonList(payload['characters_detailed']);

    void updateList(List<JsonMap> list, String mainKey) {
      for (final character in list) {
        final isMain = boolValue(character[mainKey] ?? character['is_main']);
        if (!isMain) continue;
        character['name'] = newName;
        if (input.gender.isNotEmpty) character['gender'] = input.gender;
        final personaRaw = character['persona'];
        final persona = personaRaw is String ? decodeJsonMap(personaRaw) : asJsonMap(personaRaw);
        if (input.gender.isNotEmpty) persona['gender'] = input.gender;
        if (input.age != null) persona['age'] = input.age;
        if (input.description.isNotEmpty) persona['background'] = input.description;
        if (input.appearance.isNotEmpty) persona['appearance'] = input.appearance;
        character['persona'] = persona;
      }
    }

    updateList(characters, 'is_main');
    updateList(detailed, 'is_main_character');
    payload['characters'] = characters;
    payload['characters_detailed'] = detailed;

    await backend.updateScenario(scenarioId, payload);
    final updatedMap = Map<String, NovelCharacter>.of(currentScenario.characters);
    final entry = updatedMap.entries.where((entry) => entry.value.isMain).firstOrNull;
    if (entry != null) {
      updatedMap[entry.key] = entry.value.copyWith(
        name: newName,
        gender: input.gender.isEmpty ? entry.value.gender : input.gender,
        persona: <String, dynamic>{
          ...entry.value.persona,
          if (input.gender.isNotEmpty) 'gender': input.gender,
          if (input.age != null) 'age': input.age,
          if (input.description.isNotEmpty) 'background': input.description,
          if (input.appearance.isNotEmpty) 'appearance': input.appearance,
        },
      );
    }
    scenario = currentScenario.copyWith(
      openingMessage: currentScenario.openingMessage.replaceAll(oldName, newName),
      characters: updatedMap,
      raw: payload,
    );
    openingText = scenario!.openingMessage.isNotEmpty ? scenario!.openingMessage : openingText;
    _setLaunchPhase(NovelLaunchPhase.opening);
  }

  Future<void> startNarrative() async {
    // 首轮启动只允许从 Opening 进入一次。Dialog 只上报“已读完”，
    // 由 Controller 统一负责状态迁移与生成，避免 UI 自己偷偷触发业务。
    if (_launchPhase != NovelLaunchPhase.opening || isGenerating) return;

    _setLaunchPhase(NovelLaunchPhase.startingNarrative, notify: false);

    // 开场阶段不应携带任何普通回合交互状态。
    choices = <NovelChoice>[];
    choicesVisible = false;
    playerHint = '';
    currentSentenceIndex = 0;
    _notify();

    // 第一轮必须直接进入 Writer，绝不经过 continueStory() 的旧 choices 门禁。
    await _triggerAi('');

    // 无论首轮最终成功、被恢复还是显示错误，Opening 都已经消费完成。
    // 真正落库后的重启会再由 history.currentTurn 决定 story 状态。
    if (!_disposed && _launchPhase == NovelLaunchPhase.startingNarrative) {
      _setLaunchPhase(NovelLaunchPhase.story);
    }
  }

  void acceptFateRevert() {
    showFateRevert = false;
    pendingFateRevert = false;
    _notify();
    unawaited(syncHistory());
  }

  void clearMessages() {
    lastError = '';
    infoMessage = '';
    _notify();
  }

  bool _matchesSession(JsonMap data) {
    final eventSession = stringValue(data['session_id']);
    return eventSession.isEmpty || eventSession == sessionId;
  }

  void _handleSocketEvent(NovelSocketEvent event) {
    if (_disposed) return;
    final data = event.data;
    final type = event.type;

    if (type == 'kicked') {
      lastError = stringValue(
        data['message'],
        '你的账号在其他设备登录，当前连接已断开',
      );
      _notify();
      return;
    }

    if (type == 'balance_error' ||
        (type == 'error' &&
            stringValue(data['code'] ?? asJsonMap(data['data'])['code']) == 'INSUFFICIENT_BALANCE')) {
      insufficientBalance = true;
      lastError = stringValue(data['message'], '余额不足');
      _notify();
      unawaited(syncHistory());
      return;
    }

    if (type == 'dice_roll') {
      diceRoll = NovelDiceRoll.fromJson(data);
      showDice = true;
      _diceTimer?.cancel();
      _diceTimer = Timer(const Duration(milliseconds: 2500), () {
        showDice = false;
        _notify();
      });
      _notify();
      return;
    }

    if (type == 'empty_reply' || type == 'error') {
      lastError = stringValue(data['message'], '剧情生成异常，正在同步');
      _notify();
      unawaited(syncHistory());
      return;
    }

    if (!_matchesSession(data)) return;

    if (type == 'socket_connected') {
      // 即使是首次连上，也可能已经晚于初始化时的 history 请求；每次连接成功
      // 都做一次权威补拉，彻底消除“请求完成到 WS 建连之间”的丢事件窗口。
      unawaited(_recoverAuthoritativeState());
      return;
    }
    if (type == 'socket_disconnected') {
      // 断线期间不清空任何页面；重连成功后再以 HTTP 权威状态覆盖。
      return;
    }

    switch (type) {
      case 'ending_cg_chunk':
        ending = ending.copyWith(text: '${ending.text}${stringValue(data['text'])}');
        showEnding = true;
        break;
      case 'story_ending':
        ending = ending.copyWith(
          triggeredEvents: (data['triggered_events'] is List)
              ? (data['triggered_events'] as List).map(stringValue).toList()
              : ending.triggeredEvents,
          milestones: (data['milestones'] is List)
              ? (data['milestones'] as List).map(stringValue).toList()
              : ending.milestones,
          affection: intValue(data['affection']),
          romance: intValue(data['romance']),
          title: stringValue(data['ending_title'], ending.title),
          code: stringValue(data['ending_code'], ending.code),
        );
        choices = <NovelChoice>[];
        showEnding = true;
        break;
      case 'storyboard_generating':
        _mergeStoryboardPayload(
          <String, dynamic>{
            ...data,
            'generating': true,
            'ready': false,
          },
          notify: false,
        );
        break;
      case 'storyboard_sheet_update':
        _mergeStoryboardPayload(
          <String, dynamic>{
            ...data,
            'generating': true,
          },
          notify: false,
        );
        break;
      case 'storyboard_turn_ready':
        _mergeStoryboardPayload(
          <String, dynamic>{
            ...data,
            'generating': false,
            'ready': true,
          },
          notify: false,
        );
        break;
      case 'storyboard_sheet_failed':
        _mergeStoryboardPayload(
          <String, dynamic>{
            ...data,
            'failed': true,
          },
          notify: false,
        );
        break;
      case 'character_portrait_generating':
        final genId = stringValue(data['character_id']);
        if (genId.isNotEmpty) generatingPortraitCharacterIds.add(genId);
        break;
      case 'character_portrait_update':
        _applyCharacterPortraitUpdate(data);
        break;
      case 'battle_auto_required':
        _registerForcedBattleTrigger(<String, dynamic>{
          ...data,
          'required': true,
        }, notify: false);
        break;
      case 'suggestions':
        if (forcedBattlePending) {
          // engaged 与 Suggestions 可能来自不同异步通道；强制战斗永远优先。
          choices = <NovelChoice>[];
          choicesVisible = false;
          playerHint = '';
          break;
        }
        final raw = data['suggestions'];
        choices = raw is List
            ? raw.map(NovelChoice.fromDynamic).where((choice) => choice.text.isNotEmpty).toList()
            : <NovelChoice>[];
        playerHint = stringValue(data['player_hint']);
        break;
      case 'background_update':
        // Scene-only storyboard fallback is delivered through background_update.
        // Older clients ignored this event, so a turn with no character-safe CG could
        // leave the visual stage with no image at all until the next history sync.
        final backgroundUrl = stringValue(
          data['image_url'] ?? data['background_url'] ?? data['url'],
        ).trim();
        if (backgroundUrl.isNotEmpty) {
          world = world.copyWith(
            backgroundUrl: backgroundUrl,
            location: stringValue(data['location'], world.location),
          );
        }
        break;
      case 'world_state_update':
        final previousLocation = world.location;
        world = world.copyWith(
          location: stringValue(data['current_location'] ?? data['location'], world.location),
          weather: stringValue(data['weather'], world.weather),
          atmosphere: stringValue(data['atmosphere'], world.atmosphere),
        );
        _applyStoryClock(data['story_clock']);
        if (boolValue(data['is_timeskip']) && storyClock.displayLabel.isNotEmpty) {
          timeSkipLabel = storyClock.displayLabel;
        }
        // Presence/settlement 变化必须重读 scene-map。新的 conversation_targets 与
        // story_clock 会在同一份快照里落到 Controller，页面不再自行竞争请求。
        unawaited(refreshSceneMap(force: true));
        if (world.location != previousLocation) {
          surroundingsData = <String, dynamic>{};
          surroundingsAvailability = <String, dynamic>{};
          surroundingsError = '';
          unawaited(refreshSceneExplorationState(forceMap: true));
        }
        break;
      case 'scene_asset_task':
        isBackgroundGenerating = true;
        unawaited(refreshSceneMap(force: true));
        break;
      case 'scene_asset_ready':
        isBackgroundGenerating = false;
        unawaited(refreshSceneExplorationState(forceMap: true));
        break;
      case 'surroundings_state_changed':
        // 该事件由 Writer 后台 StateAnalyzer 在权威状态提交后发送；此时再读
        // availability，确保同地点出现的新资源也能立即点亮入口。
        unawaited(refreshSceneExplorationState(forceMap: false));
        break;
      case 'relation_update':
        _applyRelationUpdate(data);
        break;
      case 'affection_update':
        _applyAffectionUpdate(data);
        break;
      case 'score':
        final incomingScore = NovelScore.fromJson(data);
        _applyScoreUpdate(incomingScore);
        // 积分变化只由右上角星星/数字原位放大反馈，不再额外弹 HUD 卡片。
        break;
      case 'story_milestone':
        // 新版后端随后还会发 world_feedback(goal.completed)。
        // 这里保留旧后端兼容，并使用相同 dedupeKey，避免显示两次。
        final completedGoal = currentGoal.trim().isNotEmpty
            ? currentGoal.trim()
            : stringValue(data['text'], '阶段目标已完成');
        _enqueueHudEvent(
          kind: 'goal_completed',
          title: '目标完成',
          detail: completedGoal,
          tone: 'accent',
          dedupeKey: 'goal:completed:$completedGoal',
        );
        break;
      case 'goal_update':
        _applyGoalPayload(data);
        break;
      case 'world_feedback':
        _applyWorldFeedback(data);
        break;
      case 'route_shift':
        // route_shift 表示当前阶段路线已经不可逆偏航；这才算“目标失败”。
        // 普通骰子 fail 只显示风险后果，不把阶段目标判死。
        final failedGoal = currentGoal.trim();
        if (failedGoal.isNotEmpty) {
          _enqueueHudEvent(
            kind: 'goal_failed',
            title: '目标失败',
            detail: failedGoal,
            tone: 'danger',
            dedupeKey: 'goal:failed:$failedGoal',
          );
          currentGoal = '';
          currentGoalNodeId = '';
          currentGoalIndex = 0;
          currentGoalEnded = false;
        } else {
          _enqueueHudEvent(
            kind: 'route_shift',
            title: stringValue(data['title'], '路线发生偏移'),
            detail: stringValue(data['text'], '你的选择改变了接下来的局面'),
            tone: 'violet',
            dedupeKey: 'route-shift:${currentTurn}:${stringValue(data['text'])}',
          );
        }
        break;
      case 'fate_revert':
        fateRevert = FateRevertData.fromJson(data);
        pendingFateRevert = true;
        choicesVisible = false;
        if (stringValue(data['bgm_url']).isNotEmpty) {
          unawaited(bgm.playUrl(
            stringValue(data['bgm_url']),
            intensity: stringValue(data['bgm_intensity'], 'low'),
            sceneMode: stringValue(data['scene_mode'], 'normal'),
          ));
        }
        unawaited(syncHistory());
        break;
      case 'protagonist_state_update':
        _applyProtagonistStateUpdate(data);
        break;
      case 'skill_update':
        if (data['skills'] is List) {
          _syncProtagonistStatus(<String, dynamic>{
            'skills': List<dynamic>.of(data['skills'] as List),
          });
        }
        break;
      case 'task_update':
        _applyTaskUpdate(data);
        break;
      case 'inventory_update':
        _applyInventoryUpdate(data);
        break;
      case 'blind_box_result':
        _applyBlindBoxSocketResult(data);
        break;
      case 'expression_update':
        _applyExpressionUpdate(data);
        break;
      case 'manual_revert':
        unawaited(syncHistory());
        break;
      case 'tension_update':
        final url = stringValue(data['bgm_url']);
        if (url.isNotEmpty) {
          unawaited(bgm.playUrl(
            url,
            intensity: stringValue(data['bgm_intensity'], 'low'),
            sceneMode: stringValue(data['scene_mode'], 'normal'),
          ));
        } else {
          unawaited(bgm.update(
            stringValue(data['bgm_intensity'], 'low'),
            stringValue(data['scene_mode'], 'normal'),
          ));
        }
        break;
      case 'cinematic_start':
        isCinematic = true;
        break;
      case 'cinematic_end':
        isCinematic = false;
        unawaited(refreshSurroundingsAvailability());
        break;
      case 'ending_intro':
        showEndingIntro = true;
        ending = ending.copyWith(text: '');
        break;
      default:
        break;
    }
    _notify();
  }

  Future<void> refreshCurrentGoal({bool notify = true}) async {
    try {
      final data = await MessageApi.getNovelGoal(sessionId);
      _applyGoalPayload(data);
      if (notify) _notify();
    } catch (error) {
      // 目标是增强体验，不应该因为单独接口失败阻断剧情页。
      debugPrint('novel goal refresh skipped: $error');
    }
  }

  void _applyGoalPayload(JsonMap data) {
    final objective = stringValue(data['objective'] ?? data['text'] ?? data['current_goal']).trim();
    final ended = boolValue(data['ended']);
    currentGoalEnded = ended;
    currentGoal = ended ? '' : objective;
    currentGoalNodeId = stringValue(data['node_id'] ?? data['current_goal_node_id']);
    currentGoalIndex = intValue(data['index'] ?? data['current_goal_index']);
    currentGoalTotal = intValue(data['total'] ?? data['current_goal_total']);
  }

  void _applyWorldFeedback(JsonMap data) {
    final rawEvents = data['events'];
    if (rawEvents is! List) return;

    for (final raw in rawEvents) {
      final item = asJsonMap(raw);
      if (item.isEmpty) continue;
      final category = stringValue(item['category']).trim();
      final action = stringValue(item['action']).trim();
      final title = stringValue(item['title']).trim();
      final text = stringValue(item['text']).trim();
      final detail = stringValue(item['detail']).trim();

      // item / relation / condition 已经有旧协议负责同步真实状态并生成 HUD；
      // world_feedback 对它们只做统一数据层，不重复显示。
      if (category == 'item' || category == 'relation' || category == 'condition') {
        continue;
      }

      if (category == 'score') {
        final value = intValue(item['value']);
        // world_feedback 经常只是对前面的 score 事件做展示说明。
        // 只有它明确携带最终 total 时才补同步，避免把 value 再加一遍。
        if (item.containsKey('total') && item['total'] != null) {
          final total = intValue(item['total'], score.total);
          if (total != score.total) {
            _applyScoreUpdate(
              NovelScore(
                total: total,
                delta: value != 0 ? value : total - score.total,
                reason: text.isNotEmpty ? text : detail,
              ),
            );
          }
        }
        continue;
      }

      if (category == 'goal') {
        final goalText = text.isNotEmpty ? text : currentGoal;
        if (action == 'completed') {
          _enqueueHudEvent(
            kind: 'goal_completed',
            title: title.isEmpty ? '目标完成' : title,
            detail: goalText,
            tone: 'accent',
            dedupeKey: 'goal:completed:$goalText',
          );
        } else if (action == 'failed') {
          _enqueueHudEvent(
            kind: 'goal_failed',
            title: title.isEmpty ? '目标失败' : title,
            detail: goalText,
            tone: 'danger',
            dedupeKey: 'goal:failed:$goalText',
          );
          if (goalText.isEmpty || goalText == currentGoal) {
            currentGoal = '';
            currentGoalNodeId = '';
            currentGoalIndex = 0;
          }
        }
        continue;
      }

      if (category == 'risk') {
        final grade = stringValue(item['grade']);
        _enqueueHudEvent(
          kind: 'risk',
          title: title.isEmpty ? '局势发生变化' : title,
          detail: text.isNotEmpty ? text : detail,
          tone: grade == 'critical_fail' ? 'critical' : 'warning',
          dedupeKey: 'risk:$action:${text.isNotEmpty ? text : detail}',
        );
        continue;
      }

      if (category == 'opportunity' || category == 'world') {
        _enqueueHudEvent(
          kind: category,
          title: title.isEmpty ? (category == 'opportunity' ? '新的机会出现' : '世界发生变化') : title,
          detail: text.isNotEmpty ? text : detail,
          tone: category == 'opportunity' ? 'accent' : 'neutral',
          dedupeKey: '$category:$action:${text.isNotEmpty ? text : detail}',
        );
      }
    }
  }

  void _applyRelationUpdate(JsonMap data, {bool allowRefresh = true}) {
    final currentScenario = scenario;
    if (currentScenario == null) return;

    final id = stringValue(data['character_id'] ?? data['character_instance_id']);
    final name = stringValue(data['character_name'] ?? data['name']);
    final updated = Map<String, NovelCharacter>.of(currentScenario.characters);

    MapEntry<String, NovelCharacter>? matched;
    if (id.isNotEmpty) {
      matched = updated.entries.where((entry) => entry.key == id || entry.value.id == id).firstOrNull;
    }
    if (matched == null && name.isNotEmpty) {
      matched = updated.entries.where((entry) => entry.value.matchesName(name)).firstOrNull;
    }

    // 绝不再把未知角色的关系变化误套到“第一个 NPC”。
    // 动态角色可能刚创建、前端列表尚未刷新：先刷新角色状态，再精确匹配一次。
    if (matched == null) {
      if (allowRefresh && (id.isNotEmpty || name.isNotEmpty)) {
        unawaited(_refreshAndApplyRelationUpdate(data));
      }
      return;
    }

    final key = matched.key;
    final current = matched.value;
    final oldAffection = current.affection;
    final newAffection = intValue(data['affection'], current.affection);
    final delta = newAffection - oldAffection;
    final milestones = asJsonList(data['milestones']);
    final newMilestones = asJsonList(data['new_milestones']);

    updated[key] = current.copyWith(
      affection: newAffection,
      affectionLabel: stringValue(data['affection_label'], current.affectionLabel),
      romance: intValue(data['romance'], current.romance),
      inhibition: intValue(data['inhibition'], current.inhibition),
      milestones: milestones.isEmpty ? current.milestones : milestones,
    );
    scenario = currentScenario.copyWith(characters: updated);

    if (delta != 0) {
      _enqueueAffectionPulse(
        characterId: current.id,
        characterName: current.name,
        delta: delta,
        dedupeKey: 'affection:${current.name}:$delta',
      );
    } else if (newMilestones.isNotEmpty) {
      final label = newMilestones
          .map((item) => stringValue(item['label'] ?? item['name']))
          .where((value) => value.isNotEmpty)
          .join(' · ');
      _enqueueHudEvent(
        kind: 'relation_milestone',
        title: '${current.name} · 关系发生变化',
        detail: label,
        tone: 'rose',
        dedupeKey: 'relation-milestone:${current.id}:$label',
      );
    }
  }

  Future<void> _refreshAndApplyRelationUpdate(JsonMap data) async {
    try {
      await refreshCharacterStatus(notify: false);
      _applyRelationUpdate(data, allowRefresh: false);
      _notify();
    } catch (error) {
      debugPrint('relation_update refresh skipped: $error');
    }
  }

  /// 角色立绘/头像自动生成完成后的推送（素材库未命中时后端触发出图）。
  /// 与 _applyRelationUpdate 同一套匹配逻辑：先按 id 匹配，再按名字匹配；
  /// 角色可能刚创建、前端列表还没同步，匹配不到时先刷新一次再重试。
  void _applyCharacterPortraitUpdate(JsonMap data, {bool allowRefresh = true}) {
    final currentScenario = scenario;
    if (currentScenario == null) return;

    final id = stringValue(data['character_id']);
    final name = stringValue(data['character_name']);
    final avatarUrl = stringValue(data['avatar_url']);
    final portraitUrl = stringValue(data['portrait_url']);
    if (avatarUrl.isEmpty && portraitUrl.isEmpty) return;

    final updated = Map<String, NovelCharacter>.of(currentScenario.characters);
    MapEntry<String, NovelCharacter>? matched;
    if (id.isNotEmpty) {
      matched = updated.entries.where((entry) => entry.key == id || entry.value.id == id).firstOrNull;
    }
    if (matched == null && name.isNotEmpty) {
      matched = updated.entries.where((entry) => entry.value.matchesName(name)).firstOrNull;
    }

    if (matched == null) {
      if (allowRefresh && (id.isNotEmpty || name.isNotEmpty)) {
        unawaited(_refreshAndApplyCharacterPortraitUpdate(data));
      }
      return;
    }

    generatingPortraitCharacterIds.remove(id.isNotEmpty ? id : matched.value.id);

    final key = matched.key;
    final current = matched.value;
    updated[key] = current.copyWith(
      avatarUrl: avatarUrl.isNotEmpty ? avatarUrl : current.avatarUrl,
      portraitUrl: portraitUrl.isNotEmpty ? portraitUrl : current.portraitUrl,
    );
    scenario = currentScenario.copyWith(characters: updated);
  }

  Future<void> _refreshAndApplyCharacterPortraitUpdate(JsonMap data) async {
    try {
      await refreshCharacterStatus(notify: false);
      _applyCharacterPortraitUpdate(data, allowRefresh: false);
      _notify();
    } catch (error) {
      debugPrint('character_portrait_update refresh skipped: $error');
    }
  }

  void _applyAffectionUpdate(JsonMap data) {
    final normalized = <String, dynamic>{
      ...data,
      'character_id': data['character_id'] ?? data['character_instance_id'],
    };
    _applyRelationUpdate(normalized);

    // gift 事件自带精确 delta；如果 relation_update 因本地状态已经提前刷新而算不出差值，
    // 仍保留一次赠礼反馈。dedupeKey 会挡住双重 WS/HTTP 提示。
    final delta = intValue(data['delta']);
    final name = stringValue(data['character_name'], '角色');
    if (delta != 0) {
      final characterId = stringValue(
        data['character_id'] ?? data['character_instance_id'],
      );
      _enqueueAffectionPulse(
        characterId: characterId,
        characterName: name,
        delta: delta,
        dedupeKey: 'affection:$name:$delta',
      );
    }
  }

  void _applyScoreUpdate(NovelScore incoming) {
    final previousTotal = score.total;
    final derivedDelta = incoming.delta != 0 ? incoming.delta : incoming.total - previousTotal;
    score = NovelScore(
      total: incoming.total,
      delta: derivedDelta,
      reason: incoming.reason,
    );
  }

  void _applyProtagonistStateUpdate(JsonMap data) {
    final oldCondition = protagonistCondition;
    final oldInjuries = protagonistInjuries.map(_injuryText).where((e) => e.isNotEmpty).toSet();

    final nextCondition = stringValue(data['condition'], protagonistCondition).trim();
    final nextInjuries = data['injuries'] is List
        ? List<dynamic>.of(data['injuries'] as List)
        : protagonistInjuries;

    protagonistCondition = nextCondition.isEmpty ? protagonistCondition : nextCondition;
    protagonistInjuries = nextInjuries;
    final statusPatch = <String, dynamic>{};
    if (data['skills'] is List) {
      statusPatch['skills'] = List<dynamic>.of(data['skills'] as List);
    }
    if (data.containsKey('level') && data['level'] != null) {
      statusPatch['level'] = data['level'];
    }
    if (data.containsKey('combat_power') && data['combat_power'] != null) {
      statusPatch['combat_power'] = data['combat_power'];
    }
    if (data['known_limits'] is List) {
      statusPatch['known_limits'] =
          List<dynamic>.of(data['known_limits'] as List);
    }
    _syncProtagonistStatus(statusPatch);

    final injuryLabels = protagonistInjuries.map(_injuryText).where((e) => e.isNotEmpty).toList();
    final added = injuryLabels.where((e) => !oldInjuries.contains(e)).toList();
    final conditionChanged = protagonistCondition != oldCondition;
    final recovered = boolValue(data['recovered']);
    final recoveryReason = stringValue(data['recovery_reason']).trim();

    if (conditionChanged || added.isNotEmpty || recovered) {
      final healthy = protagonistHp > 75;
      final recoveryDetail = <String>[
        if (recoveryReason.isNotEmpty) recoveryReason,
        if (!healthy && injuryLabels.isNotEmpty) ...injuryLabels.take(2),
      ].join(' · ');
      _enqueueHudEvent(
        kind: 'injury',
        title: recovered
            ? (healthy ? '伤势恢复' : '伤势好转')
            : healthy
                ? '伤势恢复'
                : protagonistCondition,
        detail: recovered && recoveryDetail.isNotEmpty
            ? recoveryDetail
            : added.isNotEmpty
                ? added.take(2).join(' · ')
                : injuryLabels.isNotEmpty
                    ? injuryLabels.take(2).join(' · ')
                    : healthy
                        ? '身体状态已恢复'
                        : '身体状态发生变化',
        tone: healthy
            ? 'accent'
            : protagonistHp <= 15
                ? 'critical'
                : protagonistHp <= 40
                    ? 'danger'
                    : 'warning',
        dedupeKey: 'injury:$protagonistCondition:${injuryLabels.join('|')}:$recovered',
      );
    }
  }

  void _syncProtagonistStatus([
    JsonMap extra = const <String, dynamic>{},
  ]) {
    final currentScenario = scenario;
    if (currentScenario == null) return;
    final updated = Map<String, NovelCharacter>.of(currentScenario.characters);
    final host = updated.entries.where((entry) => entry.value.isMain).firstOrNull;
    if (host == null) return;
    final status = <String, dynamic>{
      ...host.value.status,
      ...extra,
      'current_condition': protagonistCondition,
      'injuries': List<dynamic>.of(protagonistInjuries),
    };
    updated[host.key] = host.value.copyWith(status: status);
    scenario = currentScenario.copyWith(characters: updated);
  }

  String _injuryText(dynamic injury) {
    if (injury is Map) {
      final map = injury.map((key, value) => MapEntry(key.toString(), value));
      final direct = stringValue(
        map['description'] ?? map['detail'] ?? map['injury'] ?? map['name'],
      ).trim();
      if (direct.isNotEmpty) return direct;
      final location = stringValue(map['location'] ?? map['part']).trim();
      final severity = stringValue(map['severity'] ?? map['level']).trim();
      if (location.isNotEmpty && severity.isNotEmpty) return '$location · $severity';
      if (location.isNotEmpty) return location;
    }
    return stringValue(injury).trim();
  }

  void _applyInventoryUpdate(JsonMap data) {
    final delta = asJsonMap(data['delta']);
    final acquired = (delta['acquired'] is List)
        ? (delta['acquired'] as List).map(stringValue).where((e) => e.isNotEmpty).toList()
        : <String>[];
    final used = (delta['used'] is List)
        ? (delta['used'] as List).map(stringValue).where((e) => e.isNotEmpty).toList()
        : <String>[];
    final lost = (delta['lost'] is List)
        ? (delta['lost'] as List).map(stringValue).where((e) => e.isNotEmpty).toList()
        : <String>[];

    if (acquired.isNotEmpty) {
      _enqueueHudEvent(
        kind: 'inventory',
        title: '获得物品',
        detail: acquired.take(2).join(' · '),
        tone: 'accent',
        dedupeKey: 'inventory:+:${acquired.join('|')}',
      );
    } else if (lost.isNotEmpty || used.isNotEmpty) {
      final detail = <String>[...used.map((e) => '使用 $e'), ...lost.map((e) => '失去 $e')].take(2).join(' · ');
      _enqueueHudEvent(
        kind: 'inventory',
        title: used.isNotEmpty ? '物品已使用' : '物品已失去',
        detail: detail,
        tone: 'neutral',
        dedupeKey: 'inventory:-:$detail',
      );
    }
    unawaited(refreshInventory(notify: false).then((_) => _notify()));
  }

  void _applyBlindBoxSocketResult(JsonMap data) {
    final reward = asJsonMap(data['reward']);
    if (reward.isEmpty) return;
    final type = stringValue(reward['type']);
    if (type == 'score') {
      final total = intValue(reward['new_score'], score.total);
      final delta = intValue(reward['score']);
      _applyScoreUpdate(NovelScore(
        total: total,
        delta: delta,
        reason: boolValue(reward['jackpot']) ? '福袋超级奖励' : '福袋奖励',
      ));
    } else {
      final name = stringValue(reward['name'] ?? reward['item_name'], '道具');
      _enqueueHudEvent(
        kind: 'inventory',
        title: '获得 $name',
        detail: '已放入背包',
        delta: 1,
        tone: 'accent',
        dedupeKey: 'blind-item:$name',
      );
    }
    unawaited(refreshInventory(notify: false).then((_) => _notify()));
  }

  void _applyExpressionUpdate(JsonMap data) {
    final raw = data['expressions'];
    if (raw is! List || scenario == null) return;
    final currentScenario = scenario!;
    final updated = Map<String, NovelCharacter>.of(currentScenario.characters);

    for (final item in raw) {
      final map = asJsonMap(item);
      final id = stringValue(map['character_id'] ?? map['character_instance_id']);
      final name = stringValue(map['character_name'] ?? map['name']);
      final expression = stringValue(map['expression']).trim();
      if (expression.isEmpty) continue;
      final entry = updated.entries.where((entry) {
        if (id.isNotEmpty && (entry.key == id || entry.value.id == id)) return true;
        return name.isNotEmpty && entry.value.matchesName(name);
      }).firstOrNull;
      if (entry == null) continue;
      characterExpressions[entry.value.id.isNotEmpty ? entry.value.id : entry.key] = expression;
      updated[entry.key] = entry.value.copyWith(
        status: <String, dynamic>{...entry.value.status, 'expression': expression},
      );
    }
    scenario = currentScenario.copyWith(characters: updated);
  }


  void _restoreDeveloperGoalPreview() {
    if (_disposed || _developerGoalBackup == null) return;
    currentGoal = _developerGoalBackup!;
    currentGoalNodeId = _developerGoalNodeBackup ?? '';
    currentGoalIndex = _developerGoalIndexBackup ?? 0;
    currentGoalTotal = _developerGoalTotalBackup ?? 0;
    currentGoalEnded = _developerGoalEndedBackup ?? false;
    _developerGoalBackup = null;
    _developerGoalNodeBackup = null;
    _developerGoalIndexBackup = null;
    _developerGoalTotalBackup = null;
    _developerGoalEndedBackup = null;
    _developerGoalPreviewTimer = null;
    _notify();
  }

  void _restoreDeveloperConditionPreview() {
    if (_disposed || _developerConditionBackup == null) return;
    protagonistCondition = _developerConditionBackup!;
    protagonistInjuries = List<dynamic>.of(_developerInjuriesBackup ?? const <dynamic>[]);
    _developerConditionBackup = null;
    _developerInjuriesBackup = null;
    _developerConditionPreviewTimer = null;
    _syncProtagonistStatus();
    _notify();
  }

  void _enqueueAffectionPulse({
    String characterId = '',
    required String characterName,
    required int delta,
    String dedupeKey = '',
  }) {
    if (delta == 0) return;

    final cleanName = characterName.trim();
    final cleanId = characterId.trim();
    if (cleanName.isEmpty && cleanId.isEmpty) return;

    final now = DateTime.now();
    _recentHudEventKeys.removeWhere(
      (_, time) => now.difference(time) > const Duration(seconds: 4),
    );
    final key = dedupeKey.trim().isNotEmpty
        ? dedupeKey.trim()
        : 'affection-pulse:$cleanId:$cleanName:$delta';
    final previous = _recentHudEventKeys[key];
    if (previous != null &&
        now.difference(previous) < const Duration(milliseconds: 1800)) {
      return;
    }
    _recentHudEventKeys[key] = now;

    // 同一角色尚未出场时如果连续发生多次变化，合并成一次，
    // 等角色真正进入当前对白后再统一跳一次，避免连续闪烁。
    var mergedDelta = delta;
    _affectionPulseQueue.removeWhere((pulse) {
      final sameId = cleanId.isNotEmpty &&
          pulse.characterId.isNotEmpty &&
          pulse.characterId == cleanId;
      final sameName = cleanName.isNotEmpty &&
          pulse.characterName.isNotEmpty &&
          _normalizeSpeakerLookupName(pulse.characterName) ==
              _normalizeSpeakerLookupName(cleanName);
      if (sameId || sameName) {
        mergedDelta += pulse.delta;
        return true;
      }
      return false;
    });

    _affectionPulseQueue.add(
      NovelAffectionPulse(
        id: ++_affectionPulseSerial,
        characterId: cleanId,
        characterName: cleanName,
        delta: mergedDelta,
      ),
    );
  }

  void _previewDeveloperAffectionDelta(int delta) {
    final currentScenario = scenario;
    if (currentScenario == null || delta == 0) return;

    MapEntry<String, NovelCharacter>? target;
    final speaking = currentSpeakerCharacter;
    if (speaking != null && !speaking.isMain) {
      for (final entry in currentScenario.characters.entries) {
        if (entry.value.id == speaking.id ||
            entry.value.matchesName(speaking.name)) {
          target = entry;
          break;
        }
      }
    }

    if (target == null) {
      for (final entry in currentScenario.characters.entries) {
        if (!entry.value.isMain) {
          target = entry;
          break;
        }
      }
    }
    if (target == null) return;

    final character = target.value;
    final updated = Map<String, NovelCharacter>.of(currentScenario.characters);
    updated[target.key] = character.copyWith(
      affection: character.affection + delta,
    );
    scenario = currentScenario.copyWith(characters: updated);

    _enqueueAffectionPulse(
      characterId: character.id,
      characterName: character.name,
      delta: delta,
      dedupeKey:
          'developer:affection:${character.id}:$delta:${DateTime.now().microsecondsSinceEpoch}',
    );
    _notify();
  }

  /// 开发者测试专用：只预览当前客户端反馈，不写入后端、数据库或真实存档。
  ///
  /// 这些入口复用正式的局部动效 / 纯文字反馈 / 目标 / 伤势组件，确保预览与正式效果一致。
  void previewDeveloperFeedback(String type) {
    if (_disposed) return;

    switch (type) {
      case 'affection_up':
        _previewDeveloperAffectionDelta(2);
        break;
      case 'affection_down':
        _previewDeveloperAffectionDelta(-2);
        break;
      case 'item_obtained':
        _enqueueHudEvent(
          kind: 'inventory',
          title: '获得物品',
          detail: '云岚宗令牌 ×1',
          delta: 1,
          tone: 'accent',
          dedupeKey: 'developer:item:${DateTime.now().microsecondsSinceEpoch}',
        );
        break;
      case 'score_gain':
        // 开发者预览也直接驱动右上角积分星星，不再走通用 HUD。
        score = NovelScore(
          total: score.total + 13,
          delta: 13,
          reason: '剧情推进',
        );
        _notify();
        break;
      case 'goal_refresh':
        _developerGoalPreviewTimer?.cancel();
        _developerGoalBackup ??= currentGoal;
        _developerGoalNodeBackup ??= currentGoalNodeId;
        _developerGoalIndexBackup ??= currentGoalIndex;
        _developerGoalTotalBackup ??= currentGoalTotal;
        _developerGoalEndedBackup ??= currentGoalEnded;

        currentGoal = '揭开斗气消失真相并拜药老为师';
        currentGoalNodeId = 'DEV-N02';
        currentGoalIndex = 2;
        currentGoalTotal = 15;
        currentGoalEnded = false;
        _enqueueHudEvent(
          kind: 'milestone',
          title: '目标更新',
          detail: currentGoal,
          tone: 'accent',
          dedupeKey: 'developer:goal_refresh:${DateTime.now().microsecondsSinceEpoch}',
        );
        _notify();

        _developerGoalPreviewTimer =
            Timer(const Duration(milliseconds: 3200), _restoreDeveloperGoalPreview);
        break;
      case 'goal_completed':
        final goal = currentGoal.trim().isNotEmpty
            ? currentGoal.trim()
            : '结束退婚风波并确立三年之约';
        _enqueueHudEvent(
          kind: 'goal_completed',
          title: '目标完成',
          detail: goal,
          tone: 'accent',
          dedupeKey: 'developer:goal_completed:${DateTime.now().microsecondsSinceEpoch}',
        );
        break;
      case 'goal_failed':
        final goal = currentGoal.trim().isNotEmpty
            ? currentGoal.trim()
            : '潜入云岚宗后山';
        _enqueueHudEvent(
          kind: 'goal_failed',
          title: '目标失败',
          detail: goal,
          tone: 'danger',
          dedupeKey: 'developer:goal_failed:${DateTime.now().microsecondsSinceEpoch}',
        );
        break;
      case 'damage_light':
        _developerConditionPreviewTimer?.cancel();
        _developerConditionBackup ??= protagonistCondition;
        _developerInjuriesBackup ??= List<dynamic>.of(protagonistInjuries);

        protagonistCondition = '轻伤';
        protagonistInjuries = <dynamic>['手臂擦伤'];
        _syncProtagonistStatus();
        _enqueueHudEvent(
          kind: 'injury',
          title: '受到轻伤',
          detail: '手臂擦伤 · 当前状态：轻伤',
          tone: 'warning',
          dedupeKey: 'developer:damage_light:${DateTime.now().microsecondsSinceEpoch}',
        );
        _notify();

        _developerConditionPreviewTimer = Timer(
          const Duration(milliseconds: 6000),
          _restoreDeveloperConditionPreview,
        );
        break;
      case 'damage':
        _developerConditionPreviewTimer?.cancel();
        _developerConditionBackup ??= protagonistCondition;
        _developerInjuriesBackup ??= List<dynamic>.of(protagonistInjuries);

        protagonistCondition = '重伤';
        protagonistInjuries = <dynamic>['左肩受创'];
        _syncProtagonistStatus();
        _enqueueHudEvent(
          kind: 'injury',
          title: '受到重创',
          detail: '左肩受创 · 当前状态：重伤',
          tone: 'danger',
          dedupeKey: 'developer:damage:${DateTime.now().microsecondsSinceEpoch}',
        );
        _notify();

        _developerConditionPreviewTimer = Timer(
          const Duration(milliseconds: 6000),
          _restoreDeveloperConditionPreview,
        );
        break;
      case 'damage_critical':
        _developerConditionPreviewTimer?.cancel();
        _developerConditionBackup ??= protagonistCondition;
        _developerInjuriesBackup ??= List<dynamic>.of(protagonistInjuries);

        protagonistCondition = '濒死';
        protagonistInjuries = <dynamic>['严重失血'];
        _syncProtagonistStatus();
        _enqueueHudEvent(
          kind: 'injury',
          title: '生命垂危',
          detail: '严重失血 · 当前状态：濒危',
          tone: 'critical',
          dedupeKey: 'developer:damage_critical:${DateTime.now().microsecondsSinceEpoch}',
        );
        _notify();

        _developerConditionPreviewTimer = Timer(
          const Duration(milliseconds: 6000),
          _restoreDeveloperConditionPreview,
        );
        break;
      case 'recovery':
        _developerConditionPreviewTimer?.cancel();
        _developerConditionBackup ??= protagonistCondition;
        _developerInjuriesBackup ??= List<dynamic>.of(protagonistInjuries);

        protagonistCondition = '健康';
        protagonistInjuries = <dynamic>[];
        _syncProtagonistStatus();
        _enqueueHudEvent(
          kind: 'injury',
          title: '伤势恢复',
          detail: '身体状态已恢复',
          tone: 'accent',
          dedupeKey: 'developer:recovery:${DateTime.now().microsecondsSinceEpoch}',
        );
        _notify();

        _developerConditionPreviewTimer = Timer(
          const Duration(milliseconds: 6000),
          _restoreDeveloperConditionPreview,
        );
        break;
      case 'risk':
        _enqueueHudEvent(
          kind: 'risk',
          title: '警戒上升',
          detail: '守卫已经开始留意你的行动',
          tone: 'warning',
          dedupeKey: 'developer:risk:${DateTime.now().microsecondsSinceEpoch}',
        );
        break;
      default:
        return;
    }
  }

  void _enqueueHudEvent({
    required String kind,
    required String title,
    String detail = '',
    int delta = 0,
    String tone = 'neutral',
    String dedupeKey = '',
  }) {
    final cleanTitle = title.trim();
    final cleanDetail = detail.trim();
    if (cleanTitle.isEmpty && cleanDetail.isEmpty) return;

    final now = DateTime.now();
    _recentHudEventKeys.removeWhere(
      (_, time) => now.difference(time) > const Duration(seconds: 4),
    );
    final key = dedupeKey.trim().isNotEmpty
        ? dedupeKey.trim()
        : '$kind|$cleanTitle|$cleanDetail|$delta';
    final previous = _recentHudEventKeys[key];
    if (previous != null && now.difference(previous) < const Duration(milliseconds: 1800)) {
      return;
    }
    _recentHudEventKeys[key] = now;

    final event = NovelHudEvent(
      id: ++_hudEventSerial,
      kind: kind,
      title: cleanTitle,
      detail: cleanDetail,
      delta: delta,
      tone: tone,
    );

    // 目标完成/失败是阶段级反馈，优先于普通物品/人物状态等轻提示。
    if (kind == 'goal_completed' || kind == 'goal_failed') {
      _hudEventQueue.insert(0, event);
    } else {
      _hudEventQueue.add(event);
    }

    if (hudEvent == null) {
      _showNextHudEvent();
    }
  }

  void _showNextHudEvent() {
    if (_disposed) return;
    if (_hudEventQueue.isEmpty) {
      hudEvent = null;
      _notify();
      return;
    }
    hudEvent = _hudEventQueue.removeAt(0);
    _hudEventTimer?.cancel();
    _hudEventTimer = Timer(const Duration(milliseconds: 2100), () {
      if (_disposed) return;
      hudEvent = null;
      _notify();
      if (_hudEventQueue.isNotEmpty) {
        Timer(const Duration(milliseconds: 120), _showNextHudEvent);
      }
    });
    _notify();
  }

  void _applyTaskUpdate(JsonMap data) {
    final taskJson = asJsonMap(data['task']);
    final incoming = NovelTask.fromJson(taskJson);
    if (incoming.completed) {
      taskCompleted = true;
      _taskTimer?.cancel();
      _taskTimer = Timer(const Duration(seconds: 3), () {
        taskCompleted = false;
        currentTask = null;
        _notify();
      });
    } else if (incoming.display.isNotEmpty) {
      currentTask = incoming;
    }
  }

  void dismissTimeSkip() {
    timeSkipLabel = '';
    _notify();
  }

  void _onSettingsChanged() {
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generationId += 1;
    _surroundingsAvailabilityPollTicket += 1;
    _diceTimer?.cancel();
    _taskTimer?.cancel();
    _hudEventTimer?.cancel();
    _developerGoalPreviewTimer?.cancel();
    _developerConditionPreviewTimer?.cancel();
    _streamUiTimer?.cancel();
    _pendingStreamText = '';
    _hudEventQueue.clear();
    _affectionPulseQueue.clear();
    _socketSubscription?.cancel();
    unawaited(backend.close());
    unawaited(socket.dispose());
    unawaited(bgm.dispose());
    settings.removeListener(_onSettingsChanged);
    settings.dispose();
    super.dispose();
  }
}

extension FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    if (!iterator.moveNext()) return null;
    return iterator.current;
  }
}
