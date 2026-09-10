import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'novel_backend.dart';
import 'novel_models.dart';
import 'novel_text_parser.dart';

typedef NovelTokenProvider = FutureOr<String?> Function();
typedef NovelUserIdProvider = FutureOr<String?> Function();
typedef NovelTokenRefresher = FutureOr<String?> Function();

/// 所有互动小说接口集中在这里。
///
/// 这些默认值已经按当前项目的 API Gateway 与原 Vue API 对齐：
/// - 场景详情：/scenario/:id/info?detailed=true
/// - 聊天：/chat/history、/chat/stream、/chat/mark-read
/// - 小说背包/商店：/novel/*
/// - 私有 WebSocket：/ws/private
class NovelEndpointConfig {
  const NovelEndpointConfig({
    this.scenarioDetail = '/scenario/{scenarioId}/info',
    this.history = '/chat/history',
    this.sendStream = '/chat/stream',
    this.markRead = '/chat/mark-read',
    this.sceneMap = '/novel/scene-map/{sessionId}',
    this.sceneMoveIntent = '/novel/scene-map/{sessionId}/move-intent',
    this.surroundingsAvailability =
        '/novel/surroundings/{sessionId}/availability',
    this.surroundings = '/novel/surroundings/{sessionId}',
    this.surroundingsInvestigate =
        '/novel/surroundings/{sessionId}/investigate',
    this.surroundingsCombine = '/novel/surroundings/{sessionId}/combine',
    this.surroundingsClaim = '/novel/surroundings/{sessionId}/claim',
    this.surroundingsEncounter =
        '/novel/surroundings/{sessionId}/encounter',
    this.characterStatus = '/scenario/{scenarioId}/characters/status',
    this.novelCharacterRoster = '/chat/novel-character/roster',
    this.novelCharacterDraw = '/chat/novel-character/draw',
    this.novelCharacterUpgrade = '/chat/novel-character/upgrade',
    this.novelCompanions = '/novel/companions/{sessionId}',
    this.novelCompanionDeployment = '/novel/companions/deployment',
    this.novelCompanionSkillDraw = '/novel/companions/skills/draw',
    this.novelCompanionSkillRename = '/novel/companions/skills/rename',
    this.novelCharacterHistory = '/chat/novel-character/history',
    this.novelCharacterStream = '/chat/novel-character/stream',
    this.journey = '/scenario/{scenarioId}/journey',
    this.updateScenario = '/scenario/{scenarioId}/update',
    this.modelConfig = '/model-config/',
    this.scenePreferences = '/model-config/scene-preferences',
    this.imageGenerate = '/image/generate',
    this.imageTask = '/image/task/{taskId}',
    this.imageTaskResult = '/image/task/{taskId}/result',
    this.r2Signature = '/r2/get-signature',
    this.inventory = '/novel/inventory/{sessionId}',
    this.battleItemSettlement = '/novel/battle/items/settle',
    this.equipItem = '/novel/inventory/{scenarioInstanceId}/equip',
    this.useGift = '/novel/use-gift',
    this.useBlindBox = '/novel/use-blind-box',
    this.shopItems = '/novel/shop/items',
    this.buyItem = '/novel/shop/buy',
    this.revertTurn = '/novel/revert',
    this.developerContent = '/novel/developer/content',
    this.developerBattleOpponents = '/novel/developer/battle-opponents',
    this.webSocket = '/ws/private',
  });

  final String scenarioDetail;
  final String history;
  final String sendStream;
  final String markRead;
  final String sceneMap;
  final String sceneMoveIntent;
  final String surroundingsAvailability;
  final String surroundings;
  final String surroundingsInvestigate;
  final String surroundingsCombine;
  final String surroundingsClaim;
  final String surroundingsEncounter;
  final String characterStatus;
  final String novelCharacterRoster;
  final String novelCharacterDraw;
  final String novelCharacterUpgrade;
  final String novelCompanions;
  final String novelCompanionDeployment;
  final String novelCompanionSkillDraw;
  final String novelCompanionSkillRename;
  final String novelCharacterHistory;
  final String novelCharacterStream;
  final String journey;
  final String updateScenario;
  final String modelConfig;
  final String scenePreferences;
  final String imageGenerate;
  final String imageTask;
  final String imageTaskResult;
  final String r2Signature;
  final String inventory;
  final String battleItemSettlement;
  final String equipItem;
  final String useGift;
  final String useBlindBox;
  final String shopItems;
  final String buyItem;
  final String revertTurn;
  final String developerContent;
  final String developerBattleOpponents;
  final String webSocket;

  String resolve(
    String template, {
    String? scenarioId,
    String? sessionId,
    String? messageId,
    String? scenarioInstanceId,
    String? taskId,
  }) {
    return template
        .replaceAll('{scenarioId}', Uri.encodeComponent(scenarioId ?? ''))
        .replaceAll('{sessionId}', Uri.encodeComponent(sessionId ?? ''))
        .replaceAll('{messageId}', Uri.encodeComponent(messageId ?? ''))
        .replaceAll(
          '{scenarioInstanceId}',
          Uri.encodeComponent(scenarioInstanceId ?? ''),
        )
        .replaceAll('{taskId}', Uri.encodeComponent(taskId ?? ''));
  }
}

class HttpNovelBackend
    implements NovelBackend, NovelDeveloperContentBackend {
  HttpNovelBackend({
    required this.baseUrl,
    required this.tokenProvider,
    required this.userIdProvider,
    this.tokenRefresher,
    this.endpoints = const NovelEndpointConfig(),
    http.Client? client,
    NovelTextParser? parser,
    this.defaultHeaders = const <String, String>{},
  })  : _client = client ?? http.Client(),
        _parser = parser ?? const NovelTextParser();

  final String baseUrl;
  final NovelTokenProvider tokenProvider;
  final NovelUserIdProvider userIdProvider;
  final NovelTokenRefresher? tokenRefresher;
  final NovelEndpointConfig endpoints;
  final Map<String, String> defaultHeaders;
  final http.Client _client;
  final NovelTextParser _parser;

  http.Client? _activeStreamClient;
  http.Client? _activeCharacterStreamClient;
  bool _streamCancelled = false;
  bool _characterStreamCancelled = false;

  // 剧情流不能无限卡在“故事酝酿中”。
  // 连接阶段与首个 SSE 数据分别限时，超过后向 Controller 返回可恢复错误。
  static const Duration _streamConnectTimeout = Duration(seconds: 12);
  static const Duration _streamFirstEventTimeout = Duration(seconds: 30);
  static const Duration _streamInactivityTimeout = Duration(seconds: 45);

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    final uri = Uri.parse('$base$normalizedPath');
    return query == null ? uri : uri.replace(queryParameters: <String, String>{
      ...uri.queryParameters,
      ...query,
    });
  }

  Future<Map<String, String>> _headers({bool stream = false}) async {
    final token = await tokenProvider();
    final userId = await userIdProvider();
    return <String, String>{
      'Accept': stream
          ? 'text/event-stream, application/x-ndjson, application/json'
          : 'application/json',
      'Content-Type': 'application/json; charset=utf-8',
      ...defaultHeaders,
      if (token != null && token.trim().isNotEmpty)
        'Authorization': 'Bearer ${token.trim()}',
      if (userId != null && userId.trim().isNotEmpty)
        'X-User-ID': userId.trim(),
    };
  }

  dynamic _dataOf(dynamic value) {
    if (value is Map && value.containsKey('data')) return value['data'];
    return value;
  }

  Future<dynamic> _decodeResponse(http.Response response) async {
    dynamic decoded;
    try {
      decoded = response.bodyBytes.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      decoded = utf8.decode(response.bodyBytes);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final map = asJsonMap(decoded);
      throw NovelBackendException(
        stringValue(map['detail'] ?? map['message'], '请求失败 (${response.statusCode})'),
        statusCode: response.statusCode,
        code: stringValue(map['code']),
        details: decoded,
      );
    }
    return decoded;
  }

  Future<bool> _tryRefreshToken() async {
    final refresher = tokenRefresher;
    if (refresher == null) return false;
    try {
      final token = await refresher();
      return token != null && token.trim().isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<dynamic> _get(String path, {Map<String, String>? query}) async {
    Future<http.Response> execute() async {
      return _client
          .get(_uri(path, query), headers: await _headers())
          .timeout(const Duration(seconds: 60));
    }

    var response = await execute();
    if (response.statusCode == 401 && await _tryRefreshToken()) {
      response = await execute();
    }
    // 不做全局 data 解包。Vue request 拦截器返回的是完整 response.data，
    // 各 API 是否再取 .data 是“接口级约定”，必须在对应方法里处理。
    return _decodeResponse(response);
  }

  Future<dynamic> _send(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
  }) async {
    Future<http.Response> execute() async {
      final request = http.Request(method, _uri(path, query));
      request.headers.addAll(await _headers());
      if (body != null) request.body = jsonEncode(body);
      final streamed = await _client
          .send(request)
          .timeout(const Duration(seconds: 60));
      return http.Response.fromStream(streamed);
    }

    var response = await execute();
    if (response.statusCode == 401 && await _tryRefreshToken()) {
      response = await execute();
    }
    return _decodeResponse(response);
  }

  @override
  Future<NovelScenario> fetchScenario(
    String scenarioId, {
    bool full = true,
  }) async {
    final path = endpoints.resolve(
      endpoints.scenarioDetail,
      scenarioId: scenarioId,
    );

    // 与当前 Vue scenario_detail.js 完全一致：
    // GET /scenario/{scenarioId}/info?detailed=true
    final response = await _get(
      path,
      query: <String, String>{
        'detailed': full ? 'true' : 'false',
      },
    );

    // Vue getScenarioDetail() 明确 return res.data。
    return NovelScenario.fromJson(asJsonMap(_dataOf(response)));
  }

  @override
  Future<NovelHistoryResult> fetchHistory(
    String sessionId, {
    bool force = false,
  }) async {
    // 与 Vue message.js 完全一致：
    // GET /chat/history?session_id=...&offset=0&limit=50
    final raw = await _get(
      endpoints.history,
      query: <String, String>{
        'session_id': sessionId,
        'offset': '0',
        'limit': '50',
      },
    );

    final root = asJsonMap(raw);
    final listRaw = raw is List ? raw : (root['list'] ?? root['messages'] ?? root['data']);
    final messages = <NovelMessage>[];
    for (final json in asJsonList(listRaw)) {
      var message = NovelMessage.fromJson(json);
      if (message.role == NovelMessageRole.assistant) {
        message = message.copyWith(content: _parser.cleanAiTags(message.content).trim());
      }
      messages.add(message);
    }

    return NovelHistoryResult(
      messages: messages,
      isFirstPlay: boolValue(root['is_first_play']),
      currentScore: intValue(root['current_score']),
      currentTurn: intValue(root['current_turn']),
      currentTask: asJsonMap(root['current_task']).isEmpty
          ? null
          : NovelTask.fromJson(asJsonMap(root['current_task'])),
      bgmIntensity: stringValue(root['current_bgm_intensity'], 'low'),
      sceneMode: stringValue(root['current_scene_mode'], 'normal'),
      endingCg: stringValue(root['ending_cg']),
    );
  }

  @override
  Future<JsonMap> fetchSceneMap(String sessionId) async {
    final path = endpoints.resolve(
      endpoints.sceneMap,
      sessionId: sessionId,
    );
    final response = await _get(path);
    return asJsonMap(_dataOf(response));
  }

  @override
  Future<JsonMap> createSceneMoveIntent(
    String sessionId,
    String targetSceneId,
  ) async {
    final cleanTarget = targetSceneId.trim();
    if (cleanTarget.isEmpty) {
      throw const NovelBackendException('目标场景不能为空');
    }
    final path = endpoints.resolve(
      endpoints.sceneMoveIntent,
      sessionId: sessionId,
    );
    final response = await _send(
      'POST',
      path,
      body: <String, dynamic>{'target_scene_id': cleanTarget},
    );
    return asJsonMap(_dataOf(response));
  }

  @override
  Future<JsonMap> fetchSurroundingsAvailability(String sessionId) async {
    final path = endpoints.resolve(
      endpoints.surroundingsAvailability,
      sessionId: sessionId,
    );
    final response = await _get(path);
    return asJsonMap(_dataOf(response));
  }

  @override
  Future<JsonMap> fetchSurroundings(String sessionId) async {
    final path = endpoints.resolve(
      endpoints.surroundings,
      sessionId: sessionId,
    );
    final response = await _get(path);
    return asJsonMap(_dataOf(response));
  }

  @override
  Future<JsonMap> investigateSurroundNode(
    String sessionId,
    String nodeId,
  ) async {
    final path = endpoints.resolve(
      endpoints.surroundingsInvestigate,
      sessionId: sessionId,
    );
    final response = await _send(
      'POST',
      path,
      body: <String, dynamic>{'node_id': nodeId.trim()},
    );
    return asJsonMap(_dataOf(response));
  }

  @override
  Future<JsonMap> combineSurroundNodes(
    String sessionId,
    String firstId,
    String secondId,
  ) async {
    final path = endpoints.resolve(
      endpoints.surroundingsCombine,
      sessionId: sessionId,
    );
    final response = await _send(
      'POST',
      path,
      body: <String, dynamic>{
        'first_id': firstId.trim(),
        'second_id': secondId.trim(),
      },
    );
    return asJsonMap(_dataOf(response));
  }

  @override
  Future<JsonMap> claimSurroundReward(
    String sessionId,
    String nodeId,
  ) async {
    final path = endpoints.resolve(
      endpoints.surroundingsClaim,
      sessionId: sessionId,
    );
    final response = await _send(
      'POST',
      path,
      body: <String, dynamic>{'node_id': nodeId.trim()},
    );
    return asJsonMap(_dataOf(response));
  }

  @override
  Future<JsonMap> startSurroundEncounter(
    String sessionId,
    String nodeId,
  ) async {
    final path = endpoints.resolve(
      endpoints.surroundingsEncounter,
      sessionId: sessionId,
    );
    final response = await _send(
      'POST',
      path,
      body: <String, dynamic>{'node_id': nodeId.trim()},
    );
    return asJsonMap(_dataOf(response));
  }

  @override
  Stream<NovelStreamEvent> sendMessageStream(NovelSendRequest request) {
    return _sendMessageStream(request);
  }

  @override
  Stream<NovelStreamEvent> sendNavigationMessageStream(
    NovelSendRequest request,
    JsonMap navigationAction,
  ) {
    return _sendMessageStream(
      request,
      navigationAction: navigationAction,
    );
  }

  Stream<NovelStreamEvent> _sendMessageStream(
    NovelSendRequest request, {
    JsonMap navigationAction = const <String, dynamic>{},
  }) async* {
    await cancelActiveStream();
    _streamCancelled = false;
    final client = http.Client();
    _activeStreamClient = client;

    Future<http.StreamedResponse> executeStreamRequest() async {
      final httpRequest = http.Request('POST', _uri(endpoints.sendStream));
      final headers = await _headers(stream: true).timeout(_streamConnectTimeout);
      httpRequest.headers.addAll(headers);
      httpRequest.body = jsonEncode(<String, dynamic>{
        ...request.toJson(),
        if (navigationAction.isNotEmpty)
          'navigation_action': navigationAction,
      });

      // Future.timeout 本身不会取消底层 socket，但 finally 中 client.close()
      // 会在超时后立即终止该次连接，避免浏览器一直挂着 pending request。
      return client.send(httpRequest).timeout(_streamConnectTimeout);
    }

    NovelStreamEvent timeoutEvent({
      required String code,
      required String message,
    }) {
      return NovelStreamEvent(
        type: NovelStreamEventType.error,
        errorMessage: message,
        raw: <String, dynamic>{'code': code},
      );
    }

    try {
      http.StreamedResponse response;
      try {
        response = await executeStreamRequest();
      } on TimeoutException {
        if (!_streamCancelled) {
          yield timeoutEvent(
            code: 'STREAM_CONNECT_TIMEOUT',
            message: '剧情连接超时，请重试。',
          );
        }
        return;
      }

      if (response.statusCode == 401) {
        bool refreshed = false;
        try {
          refreshed =
              await _tryRefreshToken().timeout(_streamConnectTimeout);
        } on TimeoutException {
          if (!_streamCancelled) {
            yield timeoutEvent(
              code: 'STREAM_AUTH_TIMEOUT',
              message: '登录状态刷新超时，请重试。',
            );
          }
          return;
        }

        if (refreshed) {
          // 401 body 不值得无限等待；尽量排空后立即重试。
          try {
            await response.stream
                .drain<void>()
                .timeout(const Duration(seconds: 3));
          } catch (_) {}

          try {
            response = await executeStreamRequest();
          } on TimeoutException {
            if (!_streamCancelled) {
              yield timeoutEvent(
                code: 'STREAM_CONNECT_TIMEOUT',
                message: '剧情连接超时，请重试。',
              );
            }
            return;
          }
        }
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        String body = '';
        try {
          body = await utf8.decoder
              .bind(response.stream)
              .join()
              .timeout(const Duration(seconds: 10));
        } catch (_) {}
        final map = decodeJsonMap(body);
        yield NovelStreamEvent(
          type: NovelStreamEventType.error,
          errorMessage: stringValue(map['detail'] ?? map['message'], '生成请求失败'),
          statusCode: response.statusCode,
          raw: map,
        );
        return;
      }

      final lines = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter());
      final iterator = StreamIterator<String>(lines);
      final eventBuffer = <String>[];

      try {
        bool hasLine;
        try {
          // HTTP 200 只能证明连接建立；如果 30 秒连第一行 SSE 都没有，
          // 不能继续让前端永久显示“故事酝酿中”。
          hasLine =
              await iterator.moveNext().timeout(_streamFirstEventTimeout);
        } on TimeoutException {
          if (!_streamCancelled) {
            yield timeoutEvent(
              code: 'STREAM_FIRST_EVENT_TIMEOUT',
              message: '剧情响应超时，请重试。',
            );
          }
          return;
        }

        if (!hasLine) {
          if (!_streamCancelled) {
            yield timeoutEvent(
              code: 'STREAM_EMPTY_RESPONSE',
              message: '剧情连接已结束，请重试。',
            );
          }
          return;
        }

        while (hasLine) {
          if (_streamCancelled) return;

          final originalLine = iterator.current;
          final line = originalLine.trimRight();

          if (line.isEmpty) {
            if (eventBuffer.isNotEmpty) {
              final payload = eventBuffer.join('\n');
              eventBuffer.clear();
              yield* _parseStreamPayload(payload);
            }
          } else if (!line.startsWith(':') && !line.startsWith('event:')) {
            if (line.startsWith('data:')) {
              eventBuffer.add(line.substring(5).trimLeft());
            } else if (eventBuffer.isNotEmpty) {
              eventBuffer.add(line);
            } else {
              yield* _parseStreamPayload(line);
            }
          }

          try {
            hasLine =
                await iterator.moveNext().timeout(_streamInactivityTimeout);
          } on TimeoutException {
            if (!_streamCancelled) {
              yield timeoutEvent(
                code: 'STREAM_INACTIVITY_TIMEOUT',
                message: '剧情响应中断，请重试。',
              );
            }
            return;
          }
        }

        if (eventBuffer.isNotEmpty && !_streamCancelled) {
          yield* _parseStreamPayload(eventBuffer.join('\n'));
        }
      } finally {
        await iterator.cancel();
      }
    } on http.ClientException catch (error) {
      if (!_streamCancelled) {
        yield NovelStreamEvent(
          type: NovelStreamEventType.error,
          errorMessage: error.message,
          raw: const <String, dynamic>{'code': 'STREAM_CLIENT_ERROR'},
        );
      }
    } on TimeoutException {
      if (!_streamCancelled) {
        yield timeoutEvent(
          code: 'STREAM_TIMEOUT',
          message: '剧情连接超时，请重试。',
        );
      }
    } catch (error) {
      if (!_streamCancelled) {
        yield NovelStreamEvent(
          type: NovelStreamEventType.error,
          errorMessage: '网络连接中断：$error',
          raw: const <String, dynamic>{'code': 'STREAM_NETWORK_ERROR'},
        );
      }
    } finally {
      if (identical(_activeStreamClient, client)) _activeStreamClient = null;
      client.close();
    }
  }

  Stream<NovelStreamEvent> _parseStreamPayload(String payload) async* {
    final trimmed = payload.trim();
    if (trimmed.isEmpty || trimmed == '[DONE]') return;

    dynamic decoded;
    try {
      decoded = jsonDecode(trimmed);
    } catch (_) {
      yield NovelStreamEvent(type: NovelStreamEventType.text, text: trimmed);
      return;
    }

    if (decoded is String) {
      yield NovelStreamEvent(type: NovelStreamEventType.text, text: decoded);
      return;
    }

    final json = asJsonMap(decoded);
    final type = stringValue(json['type'] ?? json['event']).toLowerCase();
    final nested = asJsonMap(json['data']);
    final source = nested.isNotEmpty ? <String, dynamic>{...json, ...nested} : json;

    if (const {'content', 'text', 'delta', 'chunk', 'message_delta'}.contains(type)) {
      yield NovelStreamEvent(
        type: NovelStreamEventType.text,
        text: stringValue(source['text'] ?? source['content'] ?? source['delta']),
        raw: source,
      );
      return;
    }

    if (type == 'speaker_sentence') {
      final sentenceJson = asJsonMap(source['sentence'] ?? source['item']);
      if (sentenceJson.isNotEmpty) {
        yield NovelStreamEvent(
          type: NovelStreamEventType.speakerSentence,
          messageId: stringValue(source['message_id'] ?? source['id']),
          sentenceItems: <NovelSentence>[NovelSentence.fromJson(sentenceJson)],
          raw: source,
        );
      }
      return;
    }

    if (type == 'message_saved') {
      final suggestionsRaw = source['suggested_replies'] ?? source['suggestions'];
      yield NovelStreamEvent(
        type: NovelStreamEventType.messageSaved,
        messageId: stringValue(source['message_id'] ?? source['id']),
        content: stringValue(source['content']),
        sentenceItems: asJsonList(source['sentence_items'])
            .map(NovelSentence.fromJson)
            .toList(),
        suggestions: suggestionsRaw is List
            ? suggestionsRaw.map(NovelChoice.fromDynamic).toList()
            : const <NovelChoice>[],
        playerHint: stringValue(source['player_hint']),
        score: asJsonMap(source['score']).isEmpty
            ? null
            : NovelScore.fromJson(asJsonMap(source['score'])),
        raw: source,
      );
      return;
    }

    if (type == 'suggestions' ||
        type == 'suggested_replies' ||
        type == 'choices') {
      final values = source['suggestions'] ??
          source['suggested_replies'] ??
          source['options'];
      yield NovelStreamEvent(
        type: NovelStreamEventType.suggestions,
        suggestions: values is List
            ? values.map(NovelChoice.fromDynamic).toList()
            : const <NovelChoice>[],
        playerHint: stringValue(source['player_hint']),
        raw: source,
      );
      return;
    }

    if (type == 'player_hint') {
      yield NovelStreamEvent(
        type: NovelStreamEventType.playerHint,
        playerHint: stringValue(source['player_hint'] ?? source['text']),
        raw: source,
      );
      return;
    }

    if (type == 'score') {
      yield NovelStreamEvent(
        type: NovelStreamEventType.score,
        score: NovelScore.fromJson(source),
        raw: source,
      );
      return;
    }

    if (type == 'error' ||
        type == 'empty_reply' ||
        type == 'rollback' ||
        source['error'] != null) {
      yield NovelStreamEvent(
        type: NovelStreamEventType.error,
        errorMessage: stringValue(
          source['detail'] ?? source['message'] ?? source['error'],
          '生成失败',
        ),
        statusCode: source['status'] == null ? null : intValue(source['status']),
        raw: source,
      );
      return;
    }

    if (source['text'] != null && type.isEmpty) {
      yield NovelStreamEvent(
        type: NovelStreamEventType.text,
        text: stringValue(source['text']),
        raw: source,
      );
      return;
    }

    yield NovelStreamEvent(type: NovelStreamEventType.ignored, raw: json);
  }

  @override
  Future<void> cancelActiveStream() async {
    _streamCancelled = true;
    _activeStreamClient?.close();
    _activeStreamClient = null;
  }

  @override
  Future<void> markMessageRead(String scenarioId, String messageId) async {
    if (scenarioId.isEmpty || messageId.isEmpty) return;

    // Vue chat.js 使用 query string，不是 JSON body：
    // POST /chat/mark-read?scenario_id=...&message_id=...
    await _send(
      'POST',
      endpoints.markRead,
      query: <String, String>{
        'scenario_id': scenarioId,
        'message_id': messageId,
      },
    );
  }

  @override
  Future<List<NovelCharacter>> fetchCharacterStatus(String scenarioId) async {
    final path = endpoints.resolve(endpoints.characterStatus, scenarioId: scenarioId);
    final response = await _get(path);
    // Vue getCharactersStatus() return res.data。
    final raw = _dataOf(response);
    final root = asJsonMap(raw);
    final list = raw is List ? raw : (root['characters'] ?? root['list'] ?? root['data']);
    return asJsonList(list).map(NovelCharacter.fromJson).toList();
  }

  @override
  Future<JsonMap> fetchNovelCharacterRoster(String mainSessionId) async {
    final response = await _get(
      endpoints.novelCharacterRoster,
      query: <String, String>{'main_session_id': mainSessionId},
    );
    return asJsonMap(_dataOf(response));
  }

  @override
  Future<JsonMap> drawNovelCharacters({
    required String mainSessionId,
    required int count,
  }) async {
    final response = await _send(
      'POST',
      endpoints.novelCharacterDraw,
      body: <String, dynamic>{
        'main_session_id': int.tryParse(mainSessionId) ?? mainSessionId,
        'count': count,
      },
    );
    return asJsonMap(_dataOf(response));
  }

  @override
  Future<JsonMap> upgradeNovelCharacter({
    required String mainSessionId,
    required String characterInstanceId,
  }) async {
    final response = await _send(
      'POST',
      endpoints.novelCharacterUpgrade,
      body: <String, dynamic>{
        'main_session_id': int.tryParse(mainSessionId) ?? mainSessionId,
        'character_instance_id':
            int.tryParse(characterInstanceId) ?? characterInstanceId,
      },
    );
    return asJsonMap(_dataOf(response));
  }

  @override
  Future<JsonMap> fetchNovelCompanions(String mainSessionId) async {
    final path = endpoints.resolve(
      endpoints.novelCompanions,
      sessionId: mainSessionId,
    );
    final response = await _get(path);
    return asJsonMap(_dataOf(response));
  }

  @override
  Future<JsonMap> updateNovelCompanionDeployment({
    required String mainSessionId,
    required String characterInstanceId,
    required bool deployed,
  }) async {
    final response = await _send(
      'POST',
      endpoints.novelCompanionDeployment,
      body: <String, dynamic>{
        'session_id': int.tryParse(mainSessionId) ?? mainSessionId,
        'character_instance_id':
            int.tryParse(characterInstanceId) ?? characterInstanceId,
        'deployed': deployed,
      },
    );
    return asJsonMap(_dataOf(response));
  }

  @override
  Future<JsonMap> drawNovelCompanionSkill({
    required String mainSessionId,
    required String characterInstanceId,
  }) async {
    final response = await _send(
      'POST',
      endpoints.novelCompanionSkillDraw,
      body: <String, dynamic>{
        'session_id': int.tryParse(mainSessionId) ?? mainSessionId,
        'character_instance_id':
            int.tryParse(characterInstanceId) ?? characterInstanceId,
      },
    );
    return asJsonMap(_dataOf(response));
  }

  @override
  Future<JsonMap> renameNovelCompanionSkill({
    required String mainSessionId,
    required String characterInstanceId,
    required String skillId,
    required String name,
  }) async {
    final response = await _send(
      'POST',
      endpoints.novelCompanionSkillRename,
      body: <String, dynamic>{
        'session_id': int.tryParse(mainSessionId) ?? mainSessionId,
        'character_instance_id':
            int.tryParse(characterInstanceId) ?? characterInstanceId,
        'skill_id': skillId,
        'name': name,
      },
    );
    return asJsonMap(_dataOf(response));
  }

  @override
  Future<JsonMap> fetchNovelCharacterChatHistory({
    required String mainSessionId,
    required String characterInstanceId,
    int offset = 0,
    int limit = 30,
  }) async {
    final response = await _get(
      endpoints.novelCharacterHistory,
      query: <String, String>{
        'main_session_id': mainSessionId,
        'character_instance_id': characterInstanceId,
        'offset': '$offset',
        'limit': '$limit',
      },
    );
    return asJsonMap(_dataOf(response));
  }

  @override
  Stream<JsonMap> sendNovelCharacterChatStream({
    required String mainSessionId,
    required String characterInstanceId,
    required String message,
  }) async* {
    await cancelNovelCharacterChatStream();
    _characterStreamCancelled = false;
    final client = http.Client();
    _activeCharacterStreamClient = client;

    try {
      Future<http.StreamedResponse> execute() async {
        final request = http.Request(
          'POST',
          _uri(endpoints.novelCharacterStream),
        );
        request.headers.addAll(
          await _headers(stream: true).timeout(_streamConnectTimeout),
        );
        request.body = jsonEncode(<String, dynamic>{
          'main_session_id': int.tryParse(mainSessionId) ?? mainSessionId,
          'character_instance_id':
              int.tryParse(characterInstanceId) ?? characterInstanceId,
          'message': message,
        });
        return client.send(request).timeout(_streamConnectTimeout);
      }

      var response = await execute();
      if (response.statusCode == 401 && await _tryRefreshToken()) {
        try {
          await response.stream.drain<void>().timeout(const Duration(seconds: 3));
        } catch (_) {}
        response = await execute();
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final body = await utf8.decoder
            .bind(response.stream)
            .join()
            .timeout(const Duration(seconds: 10));
        final error = decodeJsonMap(body);
        throw NovelBackendException(
          stringValue(error['detail'] ?? error['message'], '角色回复失败'),
          statusCode: response.statusCode,
          code: stringValue(error['code']),
          details: error,
        );
      }

      final lines = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .timeout(_streamInactivityTimeout);
      final buffer = <String>[];
      await for (final originalLine in lines) {
        if (_characterStreamCancelled) return;
        final line = originalLine.trimRight();
        if (line.isEmpty) {
          if (buffer.isEmpty) continue;
          final event = _decodeCharacterStreamEvent(buffer.join('\n'));
          buffer.clear();
          if (event != null) yield event;
          continue;
        }
        if (line.startsWith(':') || line.startsWith('event:')) continue;
        if (line.startsWith('data:')) {
          buffer.add(line.substring(5).trimLeft());
        } else if (buffer.isNotEmpty) {
          buffer.add(line);
        } else {
          final event = _decodeCharacterStreamEvent(line);
          if (event != null) yield event;
        }
      }
      if (buffer.isNotEmpty && !_characterStreamCancelled) {
        final event = _decodeCharacterStreamEvent(buffer.join('\n'));
        if (event != null) yield event;
      }
    } on NovelBackendException {
      rethrow;
    } on TimeoutException {
      throw const NovelBackendException('角色回复超时，请重试');
    } on http.ClientException catch (error) {
      if (!_characterStreamCancelled) {
        throw NovelBackendException('角色聊天连接中断：${error.message}');
      }
    } finally {
      if (identical(_activeCharacterStreamClient, client)) {
        _activeCharacterStreamClient = null;
      }
      client.close();
    }
  }

  JsonMap? _decodeCharacterStreamEvent(String payload) {
    final value = payload.trim();
    if (value.isEmpty || value == '[DONE]') return null;
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map) return asJsonMap(decoded);
      if (decoded is String && decoded.trim().isNotEmpty) {
        return <String, dynamic>{'type': 'chat_message', 'text': decoded};
      }
    } catch (_) {
      return <String, dynamic>{'type': 'chat_message', 'text': value};
    }
    return null;
  }

  @override
  Future<void> cancelNovelCharacterChatStream() async {
    _characterStreamCancelled = true;
    _activeCharacterStreamClient?.close();
    _activeCharacterStreamClient = null;
  }

  @override
  Future<JsonMap> fetchJourney(String scenarioId) async {
    final path = endpoints.resolve(endpoints.journey, scenarioId: scenarioId);
    final response = await _get(path);
    // Vue getScenarioJourney() return res.data。
    return asJsonMap(_dataOf(response));
  }

  @override
  Future<void> updateScenario(String scenarioId, JsonMap payload) async {
    final path = endpoints.resolve(endpoints.updateScenario, scenarioId: scenarioId);
    await _send('PUT', path, body: payload);
  }

  @override
  Future<NovelModelConfig> fetchModelConfig() async {
    final response = await _get(endpoints.modelConfig);
    final root = asJsonMap(response);
    // Vue 只在 code == 200 && data != null 时读取。
    final data = root['data'] is Map ? asJsonMap(root['data']) : root;
    return NovelModelConfig.fromJson(data);
  }

  @override
  Future<void> updateNovelModel(String modelId) async {
    if (modelId.trim().isEmpty) return;
    await _send(
      'POST',
      endpoints.scenePreferences,
      body: <String, dynamic>{'novel': modelId.trim()},
    );
  }

  @override
  Future<JsonMap> createImageTask({
    required String description,
    required String style,
    bool removeBackground = true,
    bool autoCropAvatar = true,
  }) async {
    final response = await _send(
      'POST',
      endpoints.imageGenerate,
      body: <String, dynamic>{
        'description': description.trim(),
        'style': style,
        'remove_bg': removeBackground,
        'auto_crop_avatar': autoCropAvatar,
      },
    );
    final root = asJsonMap(response);
    return asJsonMap(root['data']).isNotEmpty ? asJsonMap(root['data']) : root;
  }

  @override
  Future<JsonMap> fetchImageTaskStatus(String taskId) async {
    final path = endpoints.resolve(endpoints.imageTask, taskId: taskId);
    final response = await _get(path);
    final root = asJsonMap(response);
    return asJsonMap(root['data']).isNotEmpty ? asJsonMap(root['data']) : root;
  }

  @override
  Future<JsonMap> fetchImageTaskResult(String taskId) async {
    final path = endpoints.resolve(endpoints.imageTaskResult, taskId: taskId);
    final response = await _get(path);
    final root = asJsonMap(response);
    return asJsonMap(root['data']).isNotEmpty ? asJsonMap(root['data']) : root;
  }

  @override
  Future<String> uploadBytesToR2({
    required List<int> bytes,
    required String filename,
    required String contentType,
    String category = 'general',
  }) async {
    if (bytes.isEmpty) {
      throw const NovelBackendException('上传文件为空');
    }
    final signatureResponse = await _send(
      'POST',
      endpoints.r2Signature,
      body: <String, dynamic>{
        'filename': filename,
        'content_type': contentType,
        'category': category,
      },
    );
    final root = asJsonMap(signatureResponse);
    final signed = asJsonMap(root['data']).isNotEmpty ? asJsonMap(root['data']) : root;
    final uploadUrl = stringValue(signed['upload_url']);
    var publicUrl = stringValue(signed['public_url']);
    if (uploadUrl.isEmpty || publicUrl.isEmpty) {
      throw const NovelBackendException('获取上传签名失败：缺少 upload_url/public_url');
    }
    if (!publicUrl.startsWith('http://') && !publicUrl.startsWith('https://')) {
      publicUrl = 'https://$publicUrl';
    }

    final response = await http
        .put(
          Uri.parse(uploadUrl),
          headers: <String, String>{'Content-Type': contentType},
          body: bytes,
        )
        .timeout(const Duration(seconds: 90));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw NovelBackendException(
        'R2 上传失败（HTTP ${response.statusCode}）',
        statusCode: response.statusCode,
        details: utf8.decode(response.bodyBytes),
      );
    }
    return publicUrl;
  }

  @override
  Future<NovelInventoryData> fetchInventory(String sessionId) async {
    // Vue 的真实路由是 GET /novel/inventory/{sessionId}。
    final path = endpoints.resolve(
      endpoints.inventory,
      sessionId: sessionId,
    );
    final response = await _get(path);
    return NovelInventoryData.fromJson(asJsonMap(_dataOf(response)));
  }

  @override
  Future<JsonMap> settleBattleItems({
    required String sessionId,
    required List<JsonMap> consumptions,
    required String outcome,
    String battleId = '',
  }) async {
    final numericSessionId = int.tryParse(sessionId);
    if (numericSessionId == null) {
      throw const NovelBackendException('当前会话ID无效，无法结算战斗道具');
    }
    final normalized = <JsonMap>[];
    for (final raw in consumptions) {
      final itemId = stringValue(raw['item_id'] ?? raw['id']).trim();
      final quantity = intValue(raw['quantity']);
      if (itemId.isEmpty || quantity <= 0) continue;
      normalized.add(<String, dynamic>{
        'item_id': itemId,
        'quantity': quantity.clamp(1, 999).toInt(),
      });
    }
    final response = await _send(
      'POST',
      endpoints.battleItemSettlement,
      body: <String, dynamic>{
        'session_id': numericSessionId,
        'battle_id': battleId.trim(),
        'outcome': outcome.trim(),
        'consumptions': normalized,
      },
    );
    return asJsonMap(_dataOf(response));
  }

  @override
  Future<JsonMap> recognizeAndAcquireDeveloperContent({
    required String sessionId,
    required String name,
  }) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) {
      throw const NovelBackendException('名称不能为空');
    }
    final numericSessionId = int.tryParse(sessionId);
    if (numericSessionId == null) {
      throw const NovelBackendException('当前会话ID无效，无法识别开发者内容');
    }
    final response = await _send(
      'POST',
      endpoints.developerContent,
      body: <String, dynamic>{
        'session_id': numericSessionId,
        'name': cleanName,
      },
    );
    return asJsonMap(_dataOf(response));
  }

  /// 开发者测试：让后端读取当前玩家权威状态并生成一个可直接开战的对手。
  /// 对手不会写入剧情角色库；返回值同时包含 player_snapshot、对手技能和
  /// 后端按双方真实阶位计算的中立裁判倍率。
  Future<JsonMap> createDeveloperBattleOpponent({
    required String sessionId,
    required String name,
    String description = '',
  }) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) {
      throw const NovelBackendException('对手名称不能为空');
    }
    final numericSessionId = int.tryParse(sessionId);
    if (numericSessionId == null) {
      throw const NovelBackendException('当前会话ID无效，无法生成测试对手');
    }
    final response = await _send(
      'POST',
      endpoints.developerBattleOpponents,
      body: <String, dynamic>{
        'session_id': numericSessionId,
        'name': cleanName,
        'description': description.trim(),
      },
    );
    return asJsonMap(_dataOf(response));
  }

  @override
  Future<void> equipItem({
    required String scenarioInstanceId,
    required String itemId,
    required bool equipped,
  }) async {
    final path = endpoints.resolve(
      endpoints.equipItem,
      scenarioInstanceId: scenarioInstanceId,
    );
    await _send('POST', path, body: <String, dynamic>{
      'item_id': itemId,
      'equipped': equipped,
    });
  }

  @override
  Future<NovelGiftResult> useGift({
    required String sessionId,
    required String scenarioInstanceId,
    required String characterInstanceId,
  }) async {
    final response = await _send('POST', endpoints.useGift, body: <String, dynamic>{
      'session_id': sessionId,
      'scenario_instance_id': scenarioInstanceId,
      'character_instance_id': characterInstanceId,
    });
    final raw = asJsonMap(_dataOf(response));
    return NovelGiftResult(
      characterName: stringValue(raw['character_name']),
      delta: intValue(raw['delta']),
    );
  }

  @override
  Future<NovelBlindBoxReward> useBlindBox({
    required String sessionId,
    required String scenarioInstanceId,
  }) async {
    final response = await _send('POST', endpoints.useBlindBox, body: <String, dynamic>{
      'session_id': sessionId,
      'scenario_instance_id': scenarioInstanceId,
    });
    final raw = asJsonMap(_dataOf(response));
    final reward = asJsonMap(raw['reward'] ?? raw);
    return NovelBlindBoxReward(
      type: stringValue(reward['type']),
      name: stringValue(reward['item_name'] ?? reward['name']),
      itemType: stringValue(reward['item_type']),
      score: intValue(reward['score']),
      newScore: reward['new_score'] == null ? null : intValue(reward['new_score']),
      jackpot: boolValue(reward['jackpot']),
    );
  }

  @override
  Future<List<NovelShopItem>> fetchShopItems(String sessionId) async {
    final response = await _get(
      endpoints.shopItems,
      query: <String, String>{'session_id': sessionId},
    );
    final raw = _dataOf(response);
    final root = asJsonMap(raw);
    return asJsonList(root['items'] ?? raw).map(NovelShopItem.fromJson).toList();
  }

  @override
  Future<NovelScore> buyItem({
    required String sessionId,
    required String scenarioInstanceId,
    required String itemType,
    int quantity = 1,
  }) async {
    final response = await _send('POST', endpoints.buyItem, body: <String, dynamic>{
      'session_id': sessionId,
      'scenario_instance_id': scenarioInstanceId,
      'item_type': itemType,
      'quantity': quantity,
    });
    return NovelScore.fromJson(asJsonMap(_dataOf(response)));
  }

  @override
  Future<NovelHistoryResult> revertToTurn({
    required String sessionId,
    required String scenarioInstanceId,
    required int targetTurn,
  }) async {
    await _send('POST', endpoints.revertTurn, body: <String, dynamic>{
      'session_id': sessionId,
      'scenario_instance_id': scenarioInstanceId,
      'turn_number': targetTurn,
    });
    return fetchHistory(sessionId, force: true);
  }

  @override
  Future<void> close() async {
    await cancelNovelCharacterChatStream();
    await cancelActiveStream();
    _client.close();
  }
}
