import 'package:flutter/material.dart';

import '../lib/features/novel/novel_ending_adapter.dart';
import '../lib/features/novel/novel_route.dart';

Future<String?> loadAccessTokenFromYourSessionManager() async {
  // TODO: return SessionManager 中真实的 access token。
  return null;
}

final NovelRuntime novelRuntime = NovelRuntime(
  baseUrl: 'https://你的-api-域名.com',
  webSocketBaseUrl: 'wss://你的-api-域名.com',
  tokenProvider: loadAccessTokenFromYourSessionManager,
);

Route<dynamic>? buildNovelRoute(RouteSettings settings) {
  return novelRuntime.onGenerateRoute(
    settings,
    endingBuilder: buildExistingEndingPage,
  );
}
