import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'http_novel_backend.dart';
import 'novel_backend.dart';
import 'novel_bgm_service.dart';
import 'novel_game_controller.dart';
import 'novel_game_page.dart';
import 'novel_settings_service.dart';
import 'novel_socket_service.dart';

typedef RuntimeTokenProvider = FutureOr<String?> Function();
typedef RuntimeUserIdProvider = FutureOr<String?> Function();
typedef RuntimeTokenRefresher = FutureOr<String?> Function();
typedef RuntimeKickedCallback = Future<void> Function();

class NovelRuntime {
  const NovelRuntime({
    required this.baseUrl,
    required this.tokenProvider,
    required this.userIdProvider,
    this.tokenRefresher,
    this.onKicked,
    this.webSocketBaseUrl,
    this.endpoints = const NovelEndpointConfig(),
    this.fallbackBackgroundAsset = 'assets/images/home_background.jpg',
    this.invalidRouteFallbackName = '/',
  });

  final String baseUrl;
  final String? webSocketBaseUrl;
  final RuntimeTokenProvider tokenProvider;
  final RuntimeUserIdProvider userIdProvider;
  final RuntimeTokenRefresher? tokenRefresher;
  final RuntimeKickedCallback? onKicked;
  final NovelEndpointConfig endpoints;
  final String fallbackBackgroundAsset;

  /// 当路由缺少 scenarioId/sessionId 时，自动跳转到的路由名。
  final String invalidRouteFallbackName;

  Uri _developerSkillUri() {
    final base = Uri.parse(baseUrl);
    return base.replace(
      path: '/api/v1/novel/developer/skills',
      query: null,
      fragment: null,
    );
  }

  Future<Map<String, dynamic>> _addDeveloperSkill(
    String sessionId,
    String skillName,
  ) async {
    Future<http.Response> submit(String token) async {
      final userId = (await userIdProvider())?.trim() ?? '';
      return http.post(
        _developerSkillUri(),
        headers: <String, String>{
          'Content-Type': 'application/json; charset=utf-8',
          if (token.trim().isNotEmpty) 'Authorization': 'Bearer ${token.trim()}',
          if (userId.isNotEmpty) 'X-User-ID': userId,
        },
        body: jsonEncode(<String, dynamic>{
          'session_id': int.tryParse(sessionId) ?? sessionId,
          'name': skillName.trim(),
        }),
      );
    }

    var token = (await tokenProvider())?.trim() ?? '';
    var response = await submit(token);
    if (response.statusCode == 401 && tokenRefresher != null) {
      token = (await tokenRefresher!())?.trim() ?? '';
      if (token.isNotEmpty) response = await submit(token);
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      decoded = null;
    }
    final data = decoded is Map
        ? decoded.map<String, dynamic>(
            (key, value) => MapEntry<String, dynamic>('$key', value),
          )
        : <String, dynamic>{};
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = data['detail'] ?? data['message'] ?? data['error'];
      throw NovelBackendException(
        detail?.toString().trim().isNotEmpty == true
            ? detail.toString()
            : '新增技能失败（${response.statusCode}）',
        statusCode: response.statusCode,
        code: data['code']?.toString() ?? '',
        details: data,
      );
    }
    return data;
  }

  Uri _battleUri(String action) {
    final base = Uri.parse(baseUrl);
    return base.replace(
      path: '/api/v1/novel/battle/$action',
      query: null,
      fragment: null,
    );
  }

  Future<Map<String, dynamic>> _postBattleJson(
    String action,
    Map<String, dynamic> body,
  ) async {
    Future<http.Response> submit(String token) async {
      final userId = (await userIdProvider())?.trim() ?? '';
      return http.post(
        _battleUri(action),
        headers: <String, String>{
          'Content-Type': 'application/json; charset=utf-8',
          if (token.trim().isNotEmpty) 'Authorization': 'Bearer ${token.trim()}',
          if (userId.isNotEmpty) 'X-User-ID': userId,
        },
        body: jsonEncode(body),
      );
    }

    var token = (await tokenProvider())?.trim() ?? '';
    var response = await submit(token);
    if (response.statusCode == 401 && tokenRefresher != null) {
      token = (await tokenRefresher!())?.trim() ?? '';
      if (token.isNotEmpty) response = await submit(token);
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      decoded = null;
    }
    final data = decoded is Map
        ? decoded.map<String, dynamic>(
            (key, value) => MapEntry<String, dynamic>('$key', value),
          )
        : <String, dynamic>{};
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = data['detail'] ?? data['message'] ?? data['error'];
      throw NovelBackendException(
        detail?.toString().trim().isNotEmpty == true
            ? detail.toString()
            : '战斗请求失败（${response.statusCode}）',
        statusCode: response.statusCode,
        code: data['code']?.toString() ?? '',
        details: data,
      );
    }
    return data;
  }

  Future<Map<String, dynamic>> _startStoryBattle(
    String sessionId,
    String battleOptionId,
  ) {
    return _postBattleJson('start', <String, dynamic>{
      'session_id': int.tryParse(sessionId) ?? sessionId,
      'battle_option_id': battleOptionId,
    });
  }

  Future<Map<String, dynamic>> _settleStoryBattle(
    String sessionId,
    String battleId,
    String outcome,
    List<Map<String, dynamic>> consumptions,
  ) {
    return _postBattleJson('items/settle', <String, dynamic>{
      'session_id': int.tryParse(sessionId) ?? sessionId,
      'battle_id': battleId,
      'outcome': outcome,
      'consumptions': consumptions,
    });
  }

  NovelGameController createController({
    required String scenarioId,
    required String sessionId,
  }) {
    final backend = HttpNovelBackend(
      baseUrl: baseUrl,
      tokenProvider: tokenProvider,
      userIdProvider: userIdProvider,
      tokenRefresher: tokenRefresher,
      endpoints: endpoints,
    );
    final socket = NovelSocketService(
      baseUrl: webSocketBaseUrl ?? baseUrl,
      path: endpoints.webSocket,
      tokenProvider: tokenProvider,
      userIdProvider: userIdProvider,
      onKicked: onKicked,
    );
    return NovelGameController(
      scenarioId: scenarioId,
      sessionId: sessionId,
      backend: backend,
      socket: socket,
      bgm: NovelBgmService(),
      settings: NovelSettingsService(),
      developerSkillAdder: _addDeveloperSkill,
      battleStarter: _startStoryBattle,
      battleSettler: _settleStoryBattle,
    );
  }

  Route<dynamic>? onGenerateRoute(
    RouteSettings settings, {
    NovelEndingBuilder? endingBuilder,
  }) {
    final name = settings.name;
    if (name == null) return null;
    final uri = Uri.parse(name);
    if (uri.pathSegments.length != 2 ||
        !const <String>{'chat', 'novel'}.contains(uri.pathSegments.first)) {
      return null;
    }
    final scenarioId = uri.pathSegments[1];
    final args = settings.arguments is Map
        ? Map<String, dynamic>.from(settings.arguments! as Map)
        : <String, dynamic>{};
    final sessionId = (args['session_id'] ??
            args['sessionId'] ??
            uri.queryParameters['session_id'] ??
            '')
        .toString();

    if (scenarioId.isEmpty || sessionId.isEmpty) {
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => _InvalidNovelRoutePage(
          fallbackRouteName: invalidRouteFallbackName,
        ),
      );
    }

    final controller = createController(
      scenarioId: scenarioId,
      sessionId: sessionId,
    );
    return MaterialPageRoute<void>(
      settings: settings,
      builder: (_) => NovelGamePage(
        controller: controller,
        fallbackBackgroundAsset: fallbackBackgroundAsset,
        endingBuilder: endingBuilder,
      ),
    );
  }
}

class _InvalidNovelRoutePage extends StatefulWidget {
  const _InvalidNovelRoutePage({this.fallbackRouteName = '/'});

  /// 找不到有效会话时自动跳转的路由，默认回首页。
  final String fallbackRouteName;

  @override
  State<_InvalidNovelRoutePage> createState() => _InvalidNovelRoutePageState();
}

class _InvalidNovelRoutePageState extends State<_InvalidNovelRoutePage> {
  @override
  void initState() {
    super.initState();
    // 记录到日志/监控系统供排查，不在 UI 上暴露给用户。
    // 注意：initState 阶段不能用 ModalRoute.of(context)（会在 State 完成挂载前
    // 触发 dependOnInheritedWidgetOfExactType 报错），改用 widget 上已有的信息。
    debugPrint(
      '[NovelRoute] invalid route: missing scenarioId/sessionId, '
      'fallbackRouteName=${widget.fallbackRouteName}',
    );
    // 首帧渲染完成后立刻跳转，不做停留（相当于 0 秒）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil(
        widget.fallbackRouteName,
        (route) => false,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF090A09),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: Color(0xFFE97878),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                '页面走丢了',
                style: TextStyle(color: Color(0xFFF4F1EA), fontSize: 20, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              const Text(
                '正在回到首页…',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFFA4A8A2), height: 1.6),
              ),
              const SizedBox(height: 22),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pushNamedAndRemoveUntil(
                    widget.fallbackRouteName,
                    (route) => false,
                  );
                },
                child: const Text('立即返回'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
