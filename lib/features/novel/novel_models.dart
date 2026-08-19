import 'dart:convert';

typedef JsonMap = Map<String, dynamic>;

JsonMap asJsonMap(dynamic value) {
  if (value is JsonMap) return value;
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return <String, dynamic>{};
}

List<JsonMap> asJsonList(dynamic value) {
  if (value is! List) return const <JsonMap>[];
  return value.map(asJsonMap).where((item) => item.isNotEmpty).toList();
}

String stringValue(dynamic value, [String fallback = '']) {
  if (value == null) return fallback;
  final result = value.toString();
  return result == 'null' ? fallback : result;
}

int intValue(dynamic value, [int fallback = 0]) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(stringValue(value)) ?? fallback;
}

double doubleValue(dynamic value, [double fallback = 0]) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.tryParse(stringValue(value)) ?? fallback;
}

bool boolValue(dynamic value, [bool fallback = false]) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  final normalized = stringValue(value).toLowerCase();
  if (const {'1', 'true', 'yes', 'y'}.contains(normalized)) return true;
  if (const {'0', 'false', 'no', 'n', ''}.contains(normalized)) return false;
  return fallback;
}

JsonMap decodeJsonMap(String value) {
  try {
    return asJsonMap(jsonDecode(value));
  } catch (_) {
    return <String, dynamic>{};
  }
}

class NovelWorldState {
  const NovelWorldState({
    this.location = '',
    this.weather = '',
    this.timeDescription = '',
    this.atmosphere = '',
    this.backgroundUrl = '',
    this.timeLabel = '故事开始',
    this.currentDay = 1,
  });

  final String location;
  final String weather;
  final String timeDescription;
  final String atmosphere;
  final String backgroundUrl;
  final String timeLabel;
  final int currentDay;

  factory NovelWorldState.fromJson(JsonMap json) {
    final custom = asJsonMap(json['custom_attributes']);
    return NovelWorldState(
      location: stringValue(json['current_location'] ?? json['location']),
      weather: stringValue(json['weather']),
      timeDescription: stringValue(
        custom['time_desc'] ?? json['time_desc'] ?? json['world_time_str'],
      ),
      atmosphere: stringValue(custom['atmosphere'] ?? json['atmosphere']),
      backgroundUrl: stringValue(
        custom['current_background_url'] ??
            json['current_background_url'] ??
            json['background_image'],
      ),
      timeLabel: stringValue(json['time_label'], '故事开始'),
      currentDay: intValue(json['story_current_day'] ?? json['current_day'], 1),
    );
  }

  NovelWorldState copyWith({
    String? location,
    String? weather,
    String? timeDescription,
    String? atmosphere,
    String? backgroundUrl,
    String? timeLabel,
    int? currentDay,
  }) {
    return NovelWorldState(
      location: location ?? this.location,
      weather: weather ?? this.weather,
      timeDescription: timeDescription ?? this.timeDescription,
      atmosphere: atmosphere ?? this.atmosphere,
      backgroundUrl: backgroundUrl ?? this.backgroundUrl,
      timeLabel: timeLabel ?? this.timeLabel,
      currentDay: currentDay ?? this.currentDay,
    );
  }
}

class NovelCharacter {
  const NovelCharacter({
    required this.id,
    required this.name,
    this.avatarUrl = '',
    this.portraitUrl = '',
    this.isMain = false,
    this.affection = 0,
    this.affectionLabel = '',
    this.romance = 0,
    this.inhibition = 0,
    this.aliases = const <String>[],
    this.gender = '',
    this.status = const <String, dynamic>{},
    this.persona = const <String, dynamic>{},
    this.milestones = const <JsonMap>[],
  });

  final String id;
  final String name;
  final String avatarUrl;
  final String portraitUrl;
  final bool isMain;
  final int affection;
  final String affectionLabel;
  final int romance;
  final int inhibition;
  final List<String> aliases;
  final String gender;
  final JsonMap status;
  final JsonMap persona;
  final List<JsonMap> milestones;

  factory NovelCharacter.fromJson(JsonMap json) {
    dynamic personaRaw = json['persona'] ?? json['json_data'];
    final persona = personaRaw is String
        ? decodeJsonMap(personaRaw)
        : asJsonMap(personaRaw);
    final status = asJsonMap(json['status']);
    final aliasesRaw = json['aliases'] ?? persona['aliases'];
    final aliases = aliasesRaw is List
        ? aliasesRaw.map(stringValue).where((e) => e.isNotEmpty).toList()
        : stringValue(aliasesRaw)
            .split(RegExp(r'[、,，\s]+'))
            .where((e) => e.isNotEmpty)
            .toList();

    return NovelCharacter(
      id: stringValue(json['id'] ?? json['character_id']),
      name: stringValue(json['name'], '未命名角色'),
      avatarUrl: stringValue(json['avatar'] ?? json['avatar_url']),
      portraitUrl: stringValue(
        json['tachie'] ?? json['sprite_url'] ?? json['portrait_url'] ?? json['portrait'],
      ),
      isMain: boolValue(json['is_main_character'] ?? json['is_main']),
      affection: intValue(json['affection'] ?? status['affection']),
      affectionLabel: stringValue(
        json['affection_label'] ?? status['affection_label'] ?? status['relationship'],
      ),
      romance: intValue(json['romance'] ?? json['romance_level']),
      inhibition: intValue(json['inhibition'] ?? json['inhibition_level']),
      aliases: aliases,
      gender: stringValue(json['gender'] ?? persona['gender']),
      status: status,
      persona: persona,
      milestones: asJsonList(json['milestones']),
    );
  }

  NovelCharacter copyWith({
    String? id,
    String? name,
    String? avatarUrl,
    String? portraitUrl,
    bool? isMain,
    int? affection,
    String? affectionLabel,
    int? romance,
    int? inhibition,
    List<String>? aliases,
    String? gender,
    JsonMap? status,
    JsonMap? persona,
    List<JsonMap>? milestones,
  }) {
    return NovelCharacter(
      id: id ?? this.id,
      name: name ?? this.name,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      portraitUrl: portraitUrl ?? this.portraitUrl,
      isMain: isMain ?? this.isMain,
      affection: affection ?? this.affection,
      affectionLabel: affectionLabel ?? this.affectionLabel,
      romance: romance ?? this.romance,
      inhibition: inhibition ?? this.inhibition,
      aliases: aliases ?? this.aliases,
      gender: gender ?? this.gender,
      status: status ?? this.status,
      persona: persona ?? this.persona,
      milestones: milestones ?? this.milestones,
    );
  }

  bool matchesName(String target) {
    final normalized = target.trim();
    return normalized.isNotEmpty && (name == normalized || aliases.contains(normalized));
  }
}

class NovelScenario {
  const NovelScenario({
    required this.id,
    required this.title,
    this.description = '',
    this.openingMessage = '',
    this.hostAvatarUrl = '',
    this.artStyle = 'anime',
    this.characters = const <String, NovelCharacter>{},
    this.worldState = const NovelWorldState(),
    this.lorebook = const <JsonMap>[],
    this.bgmConfig = const <String, dynamic>{},
    this.raw = const <String, dynamic>{},
  });

  final String id;
  final String title;
  final String description;
  final String openingMessage;
  final String hostAvatarUrl;
  final String artStyle;
  final Map<String, NovelCharacter> characters;
  final NovelWorldState worldState;
  final List<JsonMap> lorebook;
  final JsonMap bgmConfig;
  final JsonMap raw;

  NovelCharacter? get protagonist {
    for (final character in characters.values) {
      if (character.isMain) return character;
    }
    return null;
  }

  factory NovelScenario.fromJson(JsonMap json) {
    final characterList = asJsonList(
      json['characters_detailed'] ?? json['characters'],
    );
    final characters = <String, NovelCharacter>{};
    for (var i = 0; i < characterList.length; i++) {
      final character = NovelCharacter.fromJson(characterList[i]);
      final key = character.id.isNotEmpty ? character.id : 'character-$i';
      characters[key] = character;
    }

    final world = asJsonMap(json['world_state']);
    final worldSetting = asJsonMap(json['world_setting']);
    final lorebookRoot = asJsonMap(json['lorebook']);
    return NovelScenario(
      id: stringValue(json['id'] ?? json['scenario_id']),
      title: stringValue(json['title'], '互动世界'),
      description: stringValue(json['description']),
      openingMessage: stringValue(
        json['opening_message'],
      ),
      hostAvatarUrl: stringValue(json['host_avatar']),
      artStyle: stringValue(
        json['art_style_base'] ?? worldSetting['art_style_base'],
        'anime',
      ),
      characters: characters,
      worldState: NovelWorldState.fromJson(world),
      lorebook: asJsonList(json['lorebook_entries'] ?? lorebookRoot['entries']),
      bgmConfig: asJsonMap(worldSetting['bgm_config']),
      raw: json,
    );
  }

  NovelScenario copyWith({
    String? id,
    String? title,
    String? description,
    String? openingMessage,
    String? hostAvatarUrl,
    String? artStyle,
    Map<String, NovelCharacter>? characters,
    NovelWorldState? worldState,
    List<JsonMap>? lorebook,
    JsonMap? bgmConfig,
    JsonMap? raw,
  }) {
    return NovelScenario(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      openingMessage: openingMessage ?? this.openingMessage,
      hostAvatarUrl: hostAvatarUrl ?? this.hostAvatarUrl,
      artStyle: artStyle ?? this.artStyle,
      characters: characters ?? this.characters,
      worldState: worldState ?? this.worldState,
      lorebook: lorebook ?? this.lorebook,
      bgmConfig: bgmConfig ?? this.bgmConfig,
      raw: raw ?? this.raw,
    );
  }
}

enum NovelMessageRole { user, assistant, system }

class NovelSentence {
  const NovelSentence({
    required this.text,
    this.type = 'narration',
    this.speakerName = '',
    this.characterId = '',
    this.avatarUrl = '',
    this.portraitUrl = '',
    this.isProtagonist = false,
    this.hasSpeech = true,
    this.preloadPortrait = false,
    this.nextSpeakerName = '',
    this.nextCharacterId = '',
    this.nextPortraitUrl = '',
    this.nextAvatarUrl = '',
    this.speakerInfo = const <String, dynamic>{},
  });

  final String text;
  final String type;
  final String speakerName;
  final String characterId;
  final String avatarUrl;
  final String portraitUrl;
  final bool isProtagonist;
  final bool hasSpeech;
  final bool preloadPortrait;
  final String nextSpeakerName;
  final String nextCharacterId;
  final String nextPortraitUrl;
  final String nextAvatarUrl;
  final JsonMap speakerInfo;

  bool get isNarration => type == 'narration' || speakerName.isEmpty;

  factory NovelSentence.fromJson(JsonMap json) {
    return NovelSentence(
      text: stringValue(
        json['currentSentence'] ?? json['current_sentence'] ?? json['text'] ?? json['content'],
      ),
      type: stringValue(json['type'], 'narration'),
      speakerName: stringValue(json['speakerName'] ?? json['speaker_name']),
      characterId: stringValue(json['characterId'] ?? json['character_id']),
      avatarUrl: stringValue(json['avatarUrl'] ?? json['avatar_url']),
      portraitUrl: stringValue(json['portraitUrl'] ?? json['portrait_url']),
      isProtagonist: boolValue(json['is_protagonist'] ?? json['isProtagonist']),
      hasSpeech: json.containsKey('has_speech')
          ? boolValue(json['has_speech'])
          : boolValue(json['hasSpeech'], true),
      preloadPortrait: boolValue(json['preloadPortrait'] ?? json['preload_portrait']),
      nextSpeakerName: stringValue(json['nextSpeakerName'] ?? json['next_speaker_name']),
      nextCharacterId: stringValue(json['nextCharacterId'] ?? json['next_character_id']),
      nextPortraitUrl: stringValue(json['nextPortraitUrl'] ?? json['next_portrait_url']),
      nextAvatarUrl: stringValue(json['nextAvatarUrl'] ?? json['next_avatar_url']),
      speakerInfo: asJsonMap(json['speakerInfo'] ?? json['speaker_info']),
    );
  }

  NovelSentence copyWith({
    String? text,
    String? type,
    String? speakerName,
    String? characterId,
    String? avatarUrl,
    String? portraitUrl,
    bool? isProtagonist,
    bool? hasSpeech,
    bool? preloadPortrait,
    String? nextSpeakerName,
    String? nextCharacterId,
    String? nextPortraitUrl,
    String? nextAvatarUrl,
    JsonMap? speakerInfo,
  }) {
    return NovelSentence(
      text: text ?? this.text,
      type: type ?? this.type,
      speakerName: speakerName ?? this.speakerName,
      characterId: characterId ?? this.characterId,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      portraitUrl: portraitUrl ?? this.portraitUrl,
      isProtagonist: isProtagonist ?? this.isProtagonist,
      hasSpeech: hasSpeech ?? this.hasSpeech,
      preloadPortrait: preloadPortrait ?? this.preloadPortrait,
      nextSpeakerName: nextSpeakerName ?? this.nextSpeakerName,
      nextCharacterId: nextCharacterId ?? this.nextCharacterId,
      nextPortraitUrl: nextPortraitUrl ?? this.nextPortraitUrl,
      nextAvatarUrl: nextAvatarUrl ?? this.nextAvatarUrl,
      speakerInfo: speakerInfo ?? this.speakerInfo,
    );
  }
}

class NovelMessage {
  const NovelMessage({
    required this.id,
    required this.role,
    required this.content,
    this.characterName = '',
    this.timestamp = 0,
    this.status = 'success',
    this.customAttributes = const <String, dynamic>{},
    this.sentenceItems = const <NovelSentence>[],
  });

  final String id;
  final NovelMessageRole role;
  final String content;
  final String characterName;
  final int timestamp;
  final String status;
  final JsonMap customAttributes;
  final List<NovelSentence> sentenceItems;

  bool get isTemporary => id.startsWith('temp-');

  factory NovelMessage.fromJson(JsonMap json) {
    final rawRole = stringValue(json['role']).toLowerCase();
    final role = switch (rawRole) {
      'user' => NovelMessageRole.user,
      'system' => NovelMessageRole.system,
      _ => NovelMessageRole.assistant,
    };
    final custom = asJsonMap(json['custom_attributes']);
    final sentenceRaw = json['sentence_items'] ??
        json['sentenceItems'] ??
        custom['sentence_items'];
    return NovelMessage(
      id: stringValue(json['id'] ?? json['message_id'], 'message-${DateTime.now().microsecondsSinceEpoch}'),
      role: role,
      content: stringValue(json['content']),
      characterName: stringValue(json['characterName'] ?? json['character_name']),
      timestamp: intValue(json['timestamp'], DateTime.now().millisecondsSinceEpoch),
      status: stringValue(json['status'], 'success'),
      customAttributes: custom,
      sentenceItems: asJsonList(sentenceRaw).map(NovelSentence.fromJson).toList(),
    );
  }

  NovelMessage copyWith({
    String? id,
    NovelMessageRole? role,
    String? content,
    String? characterName,
    int? timestamp,
    String? status,
    JsonMap? customAttributes,
    List<NovelSentence>? sentenceItems,
  }) {
    return NovelMessage(
      id: id ?? this.id,
      role: role ?? this.role,
      content: content ?? this.content,
      characterName: characterName ?? this.characterName,
      timestamp: timestamp ?? this.timestamp,
      status: status ?? this.status,
      customAttributes: customAttributes ?? this.customAttributes,
      sentenceItems: sentenceItems ?? this.sentenceItems,
    );
  }
}

class NovelChoice {
  const NovelChoice({
    required this.text,
    this.type = 'normal',
    this.dice = false,
    this.raw = const <String, dynamic>{},
  });

  final String text;
  final String type;
  final bool dice;
  final JsonMap raw;

  bool get isAction => type == 'action' || dice;

  factory NovelChoice.fromDynamic(dynamic value) {
    if (value is String) return NovelChoice(text: value);
    final json = asJsonMap(value);
    return NovelChoice(
      text: stringValue(json['text'] ?? json['label']),
      type: stringValue(json['type'], 'normal'),
      dice: boolValue(json['dice']),
      raw: json,
    );
  }
}

class NovelTask {
  const NovelTask({
    this.display = '',
    this.completed = false,
    this.isNew = false,
  });

  final String display;
  final bool completed;
  final bool isNew;

  factory NovelTask.fromJson(JsonMap json) {
    return NovelTask(
      display: stringValue(json['display']),
      completed: boolValue(json['completed']),
      isNew: boolValue(json['new_task']),
    );
  }
}

class NovelScore {
  const NovelScore({
    this.total = 0,
    this.delta = 0,
    this.reason = '',
  });

  final int total;
  final int delta;
  final String reason;

  factory NovelScore.fromJson(JsonMap json) {
    return NovelScore(
      total: intValue(json['total_score'] ?? json['score_left']),
      delta: intValue(json['score_value']),
      reason: stringValue(json['score_reason']),
    );
  }
}

class NovelDiceRoll {
  const NovelDiceRoll({
    this.roll = 0,
    this.dc = 0,
    this.skill = '',
    this.grade = '',
    this.label = '成功',
    this.effect = 'success',
    this.narration = '',
  });

  final int roll;
  final int dc;
  final String skill;
  final String grade;
  final String label;
  final String effect;
  final String narration;

  factory NovelDiceRoll.fromJson(JsonMap json) {
    final label = stringValue(json['label'], '成功');
    final grade = stringValue(json['grade']).trim().toLowerCase();
    var effect = stringValue(json['effect']).trim().toLowerCase();

    // 后端 grade 才是判定结果的稳定协议；中文 label 只是展示文案。
    // 例如自然 20 后端会返回 grade=critical、label=“暴击！”，
    // 旧前端只猜 label 会把它误判成普通 success。
    if (effect.isEmpty) {
      effect = switch (grade) {
        'critical' => 'critical',
        'great' => 'critical',
        'critical_fail' => 'fumble',
        'fumble' => 'fumble',
        'fail' => 'fail',
        'partial' => 'partial',
        'success' => 'success',
        _ => '',
      };
    }
    if (effect.isEmpty) {
      if (label.contains('暴击') || label.contains('完美') || label.contains('大成功')) {
        effect = 'critical';
      } else if (label.contains('大失败')) {
        effect = 'fumble';
      } else if (label.contains('失败')) {
        effect = 'fail';
      } else if (label.contains('部分') || label.contains('基本成功')) {
        effect = 'partial';
      } else {
        effect = 'success';
      }
    }
    return NovelDiceRoll(
      roll: intValue(json['roll']),
      dc: intValue(json['dc']),
      skill: stringValue(json['skill']),
      grade: grade,
      label: label,
      effect: effect,
      narration: stringValue(json['narration']),
    );
  }
}

class NovelEnding {
  const NovelEnding({
    this.text = '',
    this.backgroundUrl = '',
    this.title = '故事终章',
    this.code = '结局',
    this.triggeredEvents = const <String>[],
    this.milestones = const <String>[],
    this.affection = 0,
    this.romance = 0,
  });

  final String text;
  final String backgroundUrl;
  final String title;
  final String code;
  final List<String> triggeredEvents;
  final List<String> milestones;
  final int affection;
  final int romance;

  NovelEnding copyWith({
    String? text,
    String? backgroundUrl,
    String? title,
    String? code,
    List<String>? triggeredEvents,
    List<String>? milestones,
    int? affection,
    int? romance,
  }) {
    return NovelEnding(
      text: text ?? this.text,
      backgroundUrl: backgroundUrl ?? this.backgroundUrl,
      title: title ?? this.title,
      code: code ?? this.code,
      triggeredEvents: triggeredEvents ?? this.triggeredEvents,
      milestones: milestones ?? this.milestones,
      affection: affection ?? this.affection,
      romance: romance ?? this.romance,
    );
  }
}

class FateRevertData {
  const FateRevertData({
    this.deathCount = 1,
    this.scoreDeduct = 0,
    this.totalScore,
    this.message = '',
    this.deathSceneContent = '',
  });

  final int deathCount;
  final int scoreDeduct;
  final int? totalScore;
  final String message;
  final String deathSceneContent;

  factory FateRevertData.fromJson(JsonMap json) {
    return FateRevertData(
      deathCount: intValue(json['death_count'], 1),
      scoreDeduct: intValue(json['score_deduct']),
      totalScore: json['total_score'] == null ? null : intValue(json['total_score']),
      message: stringValue(json['message']),
      deathSceneContent: stringValue(json['death_scene_content']),
    );
  }
}

class NovelInventoryItem {
  const NovelInventoryItem({
    required this.id,
    required this.name,
    this.description = '',
    this.itemType = '',
    this.quantity = 0,
    this.isEquipped = false,
    this.imageUrl = '',
    this.raw = const <String, dynamic>{},
  });

  final String id;
  final String name;
  final String description;
  final String itemType;
  final int quantity;
  final bool isEquipped;
  final String imageUrl;
  final JsonMap raw;

  bool get isConsumable => itemType.isNotEmpty;

  factory NovelInventoryItem.fromJson(JsonMap json) {
    return NovelInventoryItem(
      id: stringValue(json['id'] ?? json['item_id'] ?? json['item_type']),
      name: stringValue(json['name'], '未知道具'),
      description: stringValue(json['desc'] ?? json['description']),
      itemType: stringValue(json['item_type'] ?? json['type']),
      quantity: intValue(json['quantity'], 1),
      isEquipped: boolValue(json['equipped'] ?? json['is_equipped']),
      imageUrl: stringValue(json['image_url'] ?? json['icon_url']),
      raw: json,
    );
  }
}

class NovelInventoryData {
  const NovelInventoryData({
    this.storyItems = const <NovelInventoryItem>[],
    this.consumables = const <NovelInventoryItem>[],
    this.protagonistState = const <String, dynamic>{},
  });

  final List<NovelInventoryItem> storyItems;
  final List<NovelInventoryItem> consumables;

  /// 与背包一起返回的主角权威状态。
  /// 这样重新打开游戏后，不依赖上一轮 WS 也能恢复技能/境界/伤势。
  final JsonMap protagonistState;

  factory NovelInventoryData.fromJson(JsonMap json) {
    final storyJson = <JsonMap>[
      ...asJsonList(json['inventory'] ?? json['items']),
      ...asJsonList(json['currencies']),
    ];
    return NovelInventoryData(
      storyItems: storyJson.map(NovelInventoryItem.fromJson).toList(),
      consumables: asJsonList(json['consumables'])
          .map(NovelInventoryItem.fromJson)
          .toList(),
      protagonistState: asJsonMap(
        json['protagonist'] ?? json['protagonist_state'],
      ),
    );
  }
}

class NovelShopItem {
  const NovelShopItem({
    required this.itemType,
    required this.name,
    this.description = '',
    this.price = 0,
    this.quantity = 0,
    this.imageUrl = '',
  });

  final String itemType;
  final String name;
  final String description;
  final int price;
  final int quantity;
  final String imageUrl;

  factory NovelShopItem.fromJson(JsonMap json) {
    return NovelShopItem(
      itemType: stringValue(json['item_type']),
      name: stringValue(json['name']),
      description: stringValue(json['desc'] ?? json['description']),
      price: intValue(json['price']),
      quantity: intValue(json['quantity']),
      imageUrl: stringValue(json['image_url'] ?? json['icon_url']),
    );
  }

  NovelShopItem copyWith({int? quantity}) {
    return NovelShopItem(
      itemType: itemType,
      name: name,
      description: description,
      price: price,
      quantity: quantity ?? this.quantity,
      imageUrl: imageUrl,
    );
  }
}

class NovelModelOption {
  const NovelModelOption({
    required this.id,
    required this.name,
    this.raw = const <String, dynamic>{},
  });

  final String id;
  final String name;
  final JsonMap raw;

  factory NovelModelOption.fromJson(JsonMap json) {
    final id = stringValue(
      json['id'] ?? json['model_id'] ?? json['value'] ?? json['name'],
    );
    return NovelModelOption(
      id: id,
      name: stringValue(json['name'] ?? json['label'], id),
      raw: json,
    );
  }
}

class NovelModelConfig {
  const NovelModelConfig({
    this.models = const <NovelModelOption>[],
    this.currentNovelModel = '',
  });

  final List<NovelModelOption> models;
  final String currentNovelModel;

  factory NovelModelConfig.fromJson(JsonMap json) {
    final models = asJsonList(json['models'])
        .map(NovelModelOption.fromJson)
        .where((item) => item.id.isNotEmpty)
        .toList();
    final preferences = asJsonMap(json['scene_preferences']);
    return NovelModelConfig(
      models: models,
      currentNovelModel: stringValue(preferences['novel']),
    );
  }
}

class NovelHistoryResult {
  const NovelHistoryResult({
    this.messages = const <NovelMessage>[],
    this.isFirstPlay = false,
    this.currentScore = 0,
    this.currentTurn = 0,
    this.currentTask,
    this.bgmIntensity = 'low',
    this.sceneMode = 'normal',
    this.endingCg = '',
  });

  final List<NovelMessage> messages;
  final bool isFirstPlay;
  final int currentScore;
  final int currentTurn;
  final NovelTask? currentTask;
  final String bgmIntensity;
  final String sceneMode;
  final String endingCg;
}

class NovelSendRequest {
  const NovelSendRequest({
    required this.prompt,
    required this.sessionId,
    required this.scenarioId,
    this.msgType = 'text',
    this.imageUrl = '',
    this.characterInstanceId = '',
    this.userCharacterId = '',
    this.isCommand = false,
    this.isAction = false,
    this.useLuckyCard = false,
    this.activeLoreEntries = const <String>[],
    this.ragQuery = '',
    this.clientHistory = const <NovelMessage>[],
    this.sceneType = '',
    this.voiceTempKey = '',
    this.source = 'web',
  });

  final String prompt;
  final String sessionId;
  final String scenarioId;
  final String msgType;
  final String imageUrl;
  final String characterInstanceId;
  final String userCharacterId;
  final bool isCommand;
  final bool isAction;
  final bool useLuckyCard;

  /// 与 Vue clientAiEngine.scanLorebook() 保持一致：
  /// 发送“命中的世界书 content 字符串”，而不是整条 entry 对象。
  final List<String> activeLoreEntries;
  final String ragQuery;
  final List<NovelMessage> clientHistory;
  final String sceneType;
  final String voiceTempKey;
  final String source;

  JsonMap toJson() {
    return <String, dynamic>{
      // 严格按照 Vue src/api/chat.js 的 payload 字段。
      'message': prompt.trim(),
      'session_id': sessionId,
      'scenario_id': scenarioId,
      'msg_type': msgType,
      'image': imageUrl.isEmpty ? null : imageUrl,
      'active_lorebook_entries': activeLoreEntries,
      'rag_query': ragQuery.trim().isNotEmpty && ragQuery.trim() != prompt.trim()
          ? ragQuery.trim()
          : null,
      'client_history': clientHistory.map((message) => <String, dynamic>{
            'role': message.role == NovelMessageRole.user
                ? 'user'
                : message.role == NovelMessageRole.system
                    ? 'system'
                    : 'assistant',
            'content': message.content,
            'msg_type': 'text',
            'image': null,
          }).toList(),
      'is_command': isCommand,
      'source': source,
      'is_action': isAction,
      'use_lucky_card': useLuckyCard,
      if (sceneType.isNotEmpty) 'scene_type': sceneType,
      if (characterInstanceId.isNotEmpty)
        'character_instance_id': characterInstanceId,
      if (userCharacterId.isNotEmpty) 'user_character_id': userCharacterId,
      if (voiceTempKey.isNotEmpty) 'voice_temp_key': voiceTempKey,
    };
  }
}

enum NovelStreamEventType {
  text,
  completed,
  suggestions,
  playerHint,
  score,
  error,
  ignored,
}

class NovelStreamEvent {
  const NovelStreamEvent({
    required this.type,
    this.text = '',
    this.messageId = '',
    this.content = '',
    this.sentenceItems = const <NovelSentence>[],
    this.suggestions = const <NovelChoice>[],
    this.playerHint = '',
    this.score,
    this.errorMessage = '',
    this.statusCode,
    this.raw = const <String, dynamic>{},
  });

  final NovelStreamEventType type;
  final String text;
  final String messageId;
  final String content;
  final List<NovelSentence> sentenceItems;
  final List<NovelChoice> suggestions;
  final String playerHint;
  final NovelScore? score;
  final String errorMessage;
  final int? statusCode;
  final JsonMap raw;
}

class NovelSocketEvent {
  const NovelSocketEvent({required this.type, required this.data});

  final String type;
  final JsonMap data;
}

class NovelGiftResult {
  const NovelGiftResult({
    this.characterName = '',
    this.delta = 0,
  });

  final String characterName;
  final int delta;
}

class NovelBlindBoxReward {
  const NovelBlindBoxReward({
    this.type = '',
    this.name = '',
    this.itemType = '',
    this.score = 0,
    this.newScore,
    this.jackpot = false,
  });

  final String type;
  final String name;
  final String itemType;
  final int score;
  final int? newScore;
  final bool jackpot;
}

class NovelCharacterSetupInput {
  const NovelCharacterSetupInput({
    required this.name,
    this.gender = '',
    this.age,
    this.description = '',
    this.appearance = '',
  });

  final String name;
  final String gender;
  final int? age;
  final String description;
  final String appearance;
}
