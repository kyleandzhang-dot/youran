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
  });

  final String baseUrl;
  final String? webSocketBaseUrl;
  final RuntimeTokenProvider tokenProvider;
  final RuntimeUserIdProvider userIdProvider;
  final RuntimeTokenRefresher? tokenRefresher;
  final RuntimeKickedCallback? onKicked;
  final NovelEndpointConfig endpoints;
  final String fallbackBackgroundAsset;

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
        builder: (_) => const _InvalidNovelRoutePage(),
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

class _InvalidNovelRoutePage extends StatelessWidget {
  const _InvalidNovelRoutePage();

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
              const Icon(Icons.link_off_rounded, color: Color(0xFFE97878), size: 42),
              const SizedBox(height: 16),
              const Text(
                '缺少剧本或会话参数',
                style: TextStyle(color: Color(0xFFF4F1EA), fontSize: 20, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              const Text(
                '路由应为 /chat/{scenarioId} 或 /novel/{scenarioId}，并在 arguments 中传入 session_id。',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFFA4A8A2), height: 1.6),
              ),
              const SizedBox(height: 22),
              TextButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Text('返回'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
