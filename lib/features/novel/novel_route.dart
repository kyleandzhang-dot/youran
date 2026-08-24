import 'dart:async';

import 'package:flutter/material.dart';

import 'http_novel_backend.dart';
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
  Timer? _redirectTimer;

  @override
  void initState() {
    super.initState();
    // 记录到日志/监控系统供排查，不在 UI 上暴露给用户。
    debugPrint(
      '[NovelRoute] invalid route: missing scenarioId/sessionId, '
      'settings=${ModalRoute.of(context)?.settings}',
    );
    // 短暂停留后自动跳转，避免用户卡在一个不知所云的页面上。
    _redirectTimer = Timer(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil(
        widget.fallbackRouteName,
        (route) => false,
      );
    });
  }

  @override
  void dispose() {
    _redirectTimer?.cancel();
    super.dispose();
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
                  _redirectTimer?.cancel();
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