import 'dart:async';

import 'package:flutter/foundation.dart';

import 'novel_backend.dart';
import 'novel_bgm_service.dart';
import 'novel_models.dart';
import 'novel_settings_service.dart';
import 'novel_socket_service.dart';
import 'novel_text_parser.dart';

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

class NovelGameController extends ChangeNotifier {
  NovelGameController({
    required this.scenarioId,
    required this.sessionId,
    required this.backend,
    required this.socket,
    required this.bgm,
    required this.settings,
    NovelTextParser? parser,
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

  NovelScenario? scenario;
  NovelWorldState world = const NovelWorldState();
  List<NovelMessage> messages = <NovelMessage>[];
  List<NovelSentence> sentences = <NovelSentence>[];
  List<NovelChoice> choices = <NovelChoice>[];
  String playerHint = '';
  NovelScore score = const NovelScore();
  NovelTask? currentTask;
  NovelDiceRoll? diceRoll;
  NovelEnding ending = const NovelEnding();
  FateRevertData fateRevert = const FateRevertData();
  NovelInventoryData inventory = const NovelInventoryData();
  List<NovelShopItem> shopItems = <NovelShopItem>[];
  JsonMap journey = <String, dynamic>{};
  NovelHudEvent? hudEvent;
  bool isBackgroundGenerating = false;
  final Map<String, String> characterExpressions = <String, String>{};
  /// 正在自动生成立绘的角色 id 集合（素材库未命中时后端触发），供 UI 显示"生成中"占位
  final Set<String> generatingPortraitCharacterIds = <String>{};

  /// 远端 AI 模型配置。Vue 原版把这部分散在 index.vue；
  /// Flutter 收拢到 Controller，页面只负责展示和选择。
  List<NovelModelOption> availableModels = <NovelModelOption>[];
  String currentNovelModel = '';
  bool isChangingModel = false;

  bool isInitializing = false;
  bool isInitialized = false;
  bool isGenerating = false;
  bool isSyncingHistory = false;
  bool isReverting = false;
  bool storyStarted = false;
  bool showCharacterSetup = false;
  bool showOpening = false;
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

  String protagonistCondition = '健康';
  List<dynamic> protagonistInjuries = <dynamic>[];
  String openingText = '';
  String lastError = '';
  String infoMessage = '';
  String timeSkipLabel = '';
  int currentTurn = 0;
  int currentSentenceIndex = 0;
  int luckyCardCount = 0;

  StreamSubscription<NovelSocketEvent>? _socketSubscription;
  Timer? _diceTimer;
  Timer? _taskTimer;
  Timer? _hudEventTimer;

  // 流式文本如果每个 token 都立刻解析 + notify，会导致整页在手机上高频 rebuild。
  // 这里把多个小 chunk 合并成约 14fps 的 UI 刷新；网络流本身不降速，也不会丢字。
  Timer? _streamUiTimer;
  String _pendingStreamText = '';
  static const Duration _streamUiInterval = Duration(milliseconds: 72);

  final List<NovelHudEvent> _hudEventQueue = <NovelHudEvent>[];
  final Map<String, DateTime> _recentHudEventKeys = <String, DateTime>{};
  int _hudEventSerial = 0;
  int _generationId = 0;
  bool _disposed = false;

  NovelMessage? get lastAssistantMessage {
    for (var i = messages.length - 1; i >= 0; i--) {
      if (messages[i].role == NovelMessageRole.assistant) return messages[i];
    }
    return null;
  }

  NovelSentence? get currentSentence {
    if (sentences.isEmpty || currentSentenceIndex < 0 || currentSentenceIndex >= sentences.length) {
      return null;
    }
    return sentences[currentSentenceIndex];
  }

  bool get hasNext =>
      !isGenerating && currentSentenceIndex < sentences.length - 1;

  bool get hasPrevious => currentSentenceIndex > 0;

  NovelCharacter? get protagonist => scenario?.protagonist;

  String get scenarioInstanceId =>
      scenario?.id.isNotEmpty == true ? scenario!.id : scenarioId;

  String get protagonistName => protagonist?.name ?? '我';

  String get locationTitle {
    final raw = world.location.isNotEmpty ? world.location : (scenario?.title ?? '');
    final parts = raw.split(RegExp(r'[^一-龥a-zA-Z0-9]+')).where((part) => part.isNotEmpty).toList();
    return parts.isEmpty ? raw : parts.last;
  }

  String get locationSubtitle {
    final raw = world.location;
    final parts = raw.split(RegExp(r'[^一-龥a-zA-Z0-9]+')).where((part) => part.isNotEmpty).toList();
    if (parts.length <= 1) return world.timeDescription;
    return parts.sublist(0, parts.length - 1).join(' · ');
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

      // 模型配置不是进入剧情的硬依赖：接口异常时不应该让整个小说页初始化失败。
      await _loadModelConfig(notify: false);

      // 场景详情 + 历史记录才是进入世界的硬依赖。
      // 人物状态、背包、WebSocket、BGM 任意一个暂时失败，都不应该让整页变成
      // “世界暂时无法载入”。这也更接近 Vue：附加模块失败只降级，不阻断剧情。
      final history = await backend.fetchHistory(sessionId, force: true);
      _applyHistory(history);

      openingText = history.messages.reversed
              .where((message) => message.role == NovelMessageRole.assistant)
              .map((message) => message.content)
              .firstOrNull ??
          scenario!.openingMessage;

      if (history.isFirstPlay) {
        storyStarted = false;
        showCharacterSetup = true;
      } else {
        storyStarted = true;
      }

      // 核心数据已经就绪，先允许游戏页面进入。
      isInitialized = true;

      try {
        await refreshCharacterStatus(notify: false);
      } catch (error) {
        debugPrint('novel character status init skipped: $error');
      }

      try {
        await refreshInventory(notify: false);
      } catch (error) {
        debugPrint('novel inventory init skipped: $error');
      }

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

  void _applyHistory(NovelHistoryResult history) {
    messages = history.messages.where((message) => !message.isTemporary).toList();
    currentTurn = history.currentTurn;
    score = NovelScore(total: history.currentScore);
    currentTask = history.currentTask;
    if (history.endingCg.isNotEmpty) {
      ending = ending.copyWith(text: history.endingCg);
      showEnding = true;
    }
    _syncUiFromLastMessage(lastAssistantMessage);
    _rebuildSentences(resetIndex: true);
  }

  void _syncUiFromLastMessage(NovelMessage? message) {
    final attributes = message?.customAttributes ?? const <String, dynamic>{};
    final rawChoices = attributes['suggested_replies'] ?? attributes['suggestions'];
    if (rawChoices is List) {
      choices = rawChoices.map(NovelChoice.fromDynamic).where((item) => item.text.isNotEmpty).toList();
    } else {
      choices = <NovelChoice>[];
    }
    playerHint = stringValue(attributes['player_hint'], playerHint);
    final task = asJsonMap(attributes['current_task']);
    if (task.isNotEmpty) currentTask = NovelTask.fromJson(task);

    world = world.copyWith(
      location: stringValue(attributes['location'], world.location),
      timeDescription: stringValue(
        attributes['time_desc'] ?? attributes['world_time_str'],
        world.timeDescription,
      ),
      weather: stringValue(attributes['weather'], world.weather),
      atmosphere: stringValue(attributes['atmosphere'], world.atmosphere),
      backgroundUrl: stringValue(
        attributes['current_background_url'] ?? attributes['background_image'],
        world.backgroundUrl,
      ),
      timeLabel: stringValue(attributes['time_label'], world.timeLabel),
      currentDay: intValue(
        attributes['story_current_day'] ?? attributes['current_day'],
        world.currentDay,
      ),
    );

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
    final oldLength = sentences.length;
    sentences = parser.buildSentences(
      message: lastAssistantMessage,
      isGenerating: isGenerating,
    );
    if (resetIndex) {
      currentSentenceIndex = 0;
    } else if (isGenerating && sentences.length > oldLength && sentences.isNotEmpty) {
      currentSentenceIndex = sentences.length - 1;
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
    if (text.isEmpty || isGenerating) return;
    messages.add(NovelMessage(
      id: 'temp-user-${DateTime.now().microsecondsSinceEpoch}',
      role: NovelMessageRole.user,
      content: text,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      status: 'sending',
    ));
    await _triggerAi(text);
  }

  Future<void> continueStory() async {
    if (isGenerating) return;
    if (choices.isNotEmpty && !hasNext) {
      choicesVisible = true;
      _notify();
      return;
    }
    await _triggerAi('');
  }

  Future<void> forceContinue() async {
    if (isGenerating) return;
    const prompt = '（玩家选择了静静等待或没有做出明确动作。请顺着当前的氛围继续向下描写，可以是 NPC 主动的动作与对话、周遭环境的细节变化，或是时间的自然流逝，让故事自然而然地发展。）';
    await _triggerAi(prompt, isCommand: true, allowLuckyCard: false);
  }

  Future<void> selectChoice(NovelChoice choice) async {
    if (choice.text.trim().isEmpty || isGenerating) return;
    choicesVisible = false;
    choices = <NovelChoice>[];
    await _triggerAi(choice.text, isAction: choice.isAction);
  }

  Future<void> _triggerAi(
    String userPayload, {
    bool isCommand = false,
    bool isAction = false,
    bool allowLuckyCard = true,
  }) async {
    if (isGenerating) return;
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

    try {
      await for (final event in backend.sendMessageStream(request)) {
        if (generationId != _generationId || _disposed) return;
        switch (event.type) {
          case NovelStreamEventType.text:
            _appendStreamText(event.text);
            break;
          case NovelStreamEventType.completed:
            // complete 可能紧跟在最后一个 token 后面；先把缓冲刷进 message，
            // 避免服务端 completed 没带 content 时漏掉尾部文本。
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
              code: stringValue(event.raw['code']),
              details: event.raw,
            );
          case NovelStreamEventType.ignored:
            break;
        }
      }
      if (generationId == _generationId && isGenerating) {
        _flushStreamText(notify: false);
        isGenerating = false;
        _rebuildSentences();
        _notify();
      }
    } on NovelBackendException catch (error) {
      if (generationId != _generationId) return;
      _flushStreamText(notify: false);
      isGenerating = false;
      lastError = error.message;
      insufficientBalance = error.isInsufficientBalance;
      _notify();
      await syncHistory();
    } catch (error) {
      if (generationId != _generationId) return;
      _flushStreamText(notify: false);
      isGenerating = false;
      lastError = '生成中断：$error';
      _notify();
      await syncHistory();
    }
  }

  void _appendStreamText(String rawText) {
    if (rawText.isEmpty || messages.isEmpty) return;

    // 只缓存，不在每个网络 token 到达时立刻做正则清洗、分页解析和整页 notify。
    // 72ms 内的 token 一次性合并，手机端 CPU / layout 压力会小很多。
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
    final last = messages.last;
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
    world = world.copyWith(
      location: stringValue(extra['location'], world.location),
      timeDescription: stringValue(extra['time_desc'], world.timeDescription),
      weather: stringValue(extra['weather'], world.weather),
      atmosphere: stringValue(extra['atmosphere'], world.atmosphere),
    );

    isGenerating = false;
    _rebuildSentences(resetIndex: true);
    _notify();

    if (event.messageId.isNotEmpty) {
      unawaited(backend.markMessageRead(scenarioId, event.messageId));
    }
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
    _notify();
  }

  Future<void> syncHistory() async {
    if (isSyncingHistory) return;
    isSyncingHistory = true;
    _notify();
    try {
      await cancelGeneration();
      final history = await backend.fetchHistory(sessionId, force: true);
      _applyHistory(history);
      await refreshCharacterStatus(notify: false);
    } catch (error) {
      lastError = '同步故事状态失败：$error';
    } finally {
      isSyncingHistory = false;
      _notify();
    }
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

  Future<void> refreshInventory({bool notify = true}) async {
    try {
      inventory = await backend.fetchInventory(sessionId);
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
    if (scenario == null) return;
    await backend.equipItem(
      scenarioInstanceId: scenarioInstanceId,
      itemId: item.id,
      equipped: equipped,
    );
    await refreshInventory();
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
      _enqueueHudEvent(
        kind: 'affection',
        title: '$giftName  好感度 ${result.delta > 0 ? '+' : ''}${result.delta}',
        detail: '赠礼产生了回应',
        delta: result.delta,
        tone: result.delta >= 0 ? 'rose' : 'danger',
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
    if (reward.type == 'score') {
      _enqueueHudEvent(
        kind: 'score',
        title: reward.jackpot ? '超级奖励' : '获得积分',
        detail: reward.jackpot ? '幸运触发福袋大奖' : '福袋奖励',
        delta: reward.score,
        tone: reward.jackpot ? 'gold' : 'accent',
        dedupeKey: 'score:${reward.newScore}:${reward.score}',
      );
    } else {
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
    infoMessage = '成功获得 ${item.name}';
    _notify();
  }

  Future<void> refreshJourney() async {
    journey = await backend.fetchJourney(scenarioId);
    _notify();
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
    showCharacterSetup = false;
    showOpening = true;
    _notify();
  }

  Future<void> startNarrative() async {
    showOpening = false;
    storyStarted = true;
    _notify();
    await continueStory();
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
      case 'background_generating':
        isBackgroundGenerating = true;
        break;
      case 'background_update':
        isBackgroundGenerating = false;
        world = world.copyWith(backgroundUrl: stringValue(data['image_url'], world.backgroundUrl));
        break;
      case 'character_portrait_generating':
        final genId = stringValue(data['character_id']);
        if (genId.isNotEmpty) generatingPortraitCharacterIds.add(genId);
        break;
      case 'character_portrait_update':
        _applyCharacterPortraitUpdate(data);
        break;
      case 'suggestions':
        final raw = data['suggestions'];
        choices = raw is List
            ? raw.map(NovelChoice.fromDynamic).where((choice) => choice.text.isNotEmpty).toList()
            : <NovelChoice>[];
        playerHint = stringValue(data['player_hint']);
        break;
      case 'world_state_update':
        world = world.copyWith(
          location: stringValue(data['current_location'] ?? data['location'], world.location),
          timeDescription: stringValue(
            data['time_desc'] ?? asJsonMap(data['world_time'])['period_name'],
            world.timeDescription,
          ),
          weather: stringValue(data['weather'], world.weather),
          atmosphere: stringValue(data['atmosphere'], world.atmosphere),
          timeLabel: stringValue(data['time_label'], world.timeLabel),
          currentDay: intValue(data['story_current_day'] ?? data['current_day'], world.currentDay),
        );
        if (boolValue(data['is_timeskip']) && stringValue(data['time_label']).isNotEmpty) {
          timeSkipLabel = stringValue(data['time_label']);
        }
        break;
      case 'relation_update':
        _applyRelationUpdate(data);
        break;
      case 'affection_update':
        _applyAffectionUpdate(data);
        break;
      case 'score':
        _applyScoreUpdate(NovelScore.fromJson(data));
        break;
      case 'story_milestone':
        _enqueueHudEvent(
          kind: 'milestone',
          title: stringValue(data['title'], '剧情推进'),
          detail: stringValue(data['text']),
          tone: 'gold',
          dedupeKey: 'story-milestone:${stringValue(data['text'])}',
        );
        break;
      case 'route_shift':
        _enqueueHudEvent(
          kind: 'route_shift',
          title: stringValue(data['title'], '路线发生偏移'),
          detail: stringValue(data['text'], '你的选择改变了接下来的局面'),
          tone: 'violet',
          dedupeKey: 'route-shift:${currentTurn}:${stringValue(data['text'])}',
        );
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
      final milestoneLabel = newMilestones
          .map((item) => stringValue(item['label'] ?? item['name']))
          .where((value) => value.isNotEmpty)
          .join(' · ');
      _enqueueHudEvent(
        kind: 'affection',
        title: '${current.name}  好感度 ${delta > 0 ? '+' : ''}$delta',
        detail: milestoneLabel.isNotEmpty ? milestoneLabel : _relationshipHint(updated[key]!),
        delta: delta,
        tone: delta > 0 ? 'rose' : 'danger',
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
      _enqueueHudEvent(
        kind: 'affection',
        title: '$name  好感度 ${delta > 0 ? '+' : ''}$delta',
        detail: '赠礼产生了回应',
        delta: delta,
        tone: delta > 0 ? 'rose' : 'danger',
        dedupeKey: 'affection:$name:$delta',
      );
    }
  }

  String _relationshipHint(NovelCharacter character) {
    final label = character.affectionLabel.trim();
    if (label.isNotEmpty) return label;
    if (character.affection >= 80) return '关系非常亲密';
    if (character.affection >= 60) return '关系正在靠近';
    if (character.affection >= 30) return '彼此更加熟悉';
    if (character.affection < 0) return '关系出现裂痕';
    return '关系产生了变化';
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
    _syncProtagonistStatus();

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

  void _syncProtagonistStatus() {
    final currentScenario = scenario;
    if (currentScenario == null) return;
    final updated = Map<String, NovelCharacter>.of(currentScenario.characters);
    final host = updated.entries.where((entry) => entry.value.isMain).firstOrNull;
    if (host == null) return;
    final status = <String, dynamic>{
      ...host.value.status,
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
      _enqueueHudEvent(
        kind: 'score',
        title: boolValue(reward['jackpot']) ? '超级奖励' : '获得积分',
        detail: boolValue(reward['jackpot']) ? '幸运触发福袋大奖' : '福袋奖励',
        delta: delta,
        tone: boolValue(reward['jackpot']) ? 'gold' : 'accent',
        dedupeKey: 'score:$total:$delta',
      );
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

  void _enqueueHudEvent({
    required String kind,
    required String title,
    String detail = '',
    int delta = 0,
    String tone = 'neutral',
    String dedupeKey = '',
  }) {
    // 游戏主界面不再显示全局 HUD 浮层。
    // 剧情推进、路线变化、受伤、积分、背包、关系等变化都只更新真实状态，
    // 不再额外弹出屏幕提示。好感度变化由当前角色对话框旁的爱心动画承担。
    return;
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
    _diceTimer?.cancel();
    _taskTimer?.cancel();
    _hudEventTimer?.cancel();
    _streamUiTimer?.cancel();
    _pendingStreamText = '';
    _hudEventQueue.clear();
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