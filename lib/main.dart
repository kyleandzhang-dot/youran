// lib/main.dart

import 'package:flutter/material.dart';

import 'api/api_client.dart';
import 'api/user_api.dart';
import 'features/novel/novel.dart';
import 'game_shell.dart';
import 'services/session_manager.dart';
import 'login_sheet.dart'; // 引入登录面板组件

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

const NovelEndpointConfig _novelEndpoints = NovelEndpointConfig(
  scenarioDetail: '/scenario/{scenarioId}/info',
  characterStatus: '/scenario/{scenarioId}/characters/status',
  journey: '/scenario/{scenarioId}/journey',
  updateScenario: '/scenario/{scenarioId}/update',
  history: '/chat/history',
  sendStream: '/chat/stream',
  markRead: '/chat/mark-read',
  modelConfig: '/model-config/',
  scenePreferences: '/model-config/scene-preferences',
  imageGenerate: '/image/generate',
  imageTask: '/image/task/{taskId}',
  imageTaskResult: '/image/task/{taskId}/result',
  r2Signature: '/r2/get-signature',
  inventory: '/novel/inventory/{sessionId}',
  equipItem: '/novel/inventory/{scenarioInstanceId}/equip',
  useGift: '/novel/use-gift',
  useBlindBox: '/novel/use-blind-box',
  shopItems: '/novel/shop/items',
  buyItem: '/novel/shop/buy',
  revertTurn: '/novel/revert',
  webSocket: '/ws/private',
);

final NovelRuntime novelRuntime = NovelRuntime(
  baseUrl: ApiClient.baseUrl,
  webSocketBaseUrl: ApiClient.webSocketBaseUrl,
  tokenProvider: () => ApiClient.instance.accessToken,
  userIdProvider: () => ApiClient.instance.userId,
  tokenRefresher: SessionManager.refreshAccessToken,
  onKicked: _handleForcedLogout,
  endpoints: _novelEndpoints,
  fallbackBackgroundAsset: 'assets/images/home_background.jpg',
);

Future<void> _handleForcedLogout() async {
  await SessionManager.logout();
  final navigator = appNavigatorKey.currentState;
  if (navigator == null) return;
  navigator.pushAndRemoveUntil<void>(
    MaterialPageRoute<void>(
      builder: (_) => const GameShellPage(autoOpenDrawer: true),
    ),
    (route) => false,
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  debugPrint('HTTP API：${ApiClient.baseUrl}');
  debugPrint('WebSocket：${ApiClient.webSocketBaseUrl}');

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: appNavigatorKey,
      title: '悠然',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const _StartupGate(),
      onGenerateRoute: (RouteSettings settings) {
        return novelRuntime.onGenerateRoute(
          settings,
          endingBuilder: buildExistingEndingPage,
        );
      },
    );
  }
}

class _StartupLaunch {
  const _StartupLaunch({
    required this.mode,
    required this.scenarioId,
    required this.sessionId,
  });

  final String mode;
  final String scenarioId;
  final String sessionId;
}

class _StartupGate extends StatefulWidget {
  const _StartupGate();

  @override
  State<_StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<_StartupGate> {
  UserSession? _session;
  _StartupLaunch? _launch;
  bool _loading = true;
  String _status = '正在恢复世界…';

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    // restore() 只允许用于 App 冷启动。
    // 用户刚完成验证码登录时已经拿到了完整 token，不能再次 restore()，
    // 否则 restore() 会先清空内存 token，再刷新，造成第一次登录的状态竞争。
    final session = await SessionManager.restore();
    if (!mounted) return;

    if (session == null) {
      _session = null;
      _launch = null;
      setState(() => _loading = false);

      // 未登录：第一帧空壳渲染完成后弹出不可手动关闭的登录页。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        LoginSheet.show(
          context,
          onLoginSuccess: (result) async {
            // LoginSheet 会先完整退出，再执行到这里，因此这里可以安全刷新/跳转。
            await SessionManager.persist(result);
            if (!mounted) return;

            final loggedInSession = UserSession(
              userId: result.userId,
              username: result.username,
              tokenBalance: result.tokenBalance.toInt(),
              accessToken: result.accessToken,
            );

            // 直接使用本次登录结果继续，不再调用 SessionManager.restore()。
            await _continueWithSession(loggedInSession);
          },
        );
      });
      return;
    }

    await _continueWithSession(session);
  }

  Future<void> _continueWithSession(UserSession session) async {
    if (!mounted) return;

    _session = session;
    _launch = null;

    // 在任何 UserApi / Novel 请求前确保运行时身份已经就绪。
    ApiClient.instance.setAccessToken(session.accessToken);
    ApiClient.instance.setUserId(session.userId);

    setState(() {
      _loading = true;
      _status = '正在寻找上次的世界…';
    });

    debugPrint(
      '[Startup] session ready: userId=${ApiClient.instance.userId}, '
      'token=${ApiClient.instance.accessToken == null ? 'missing' : 'ready'}',
    );

    try {
      final home = await UserApi.getHomeData();
      final activeId = home.activeScenarioId?.toString().trim() ?? '';

      if (activeId.isNotEmpty) {
        final matches = home.scenarios.where(
          (scenario) => scenario.id.toString() == activeId,
        );

        if (matches.isNotEmpty) {
          final scenario = matches.first;
          if (mounted) {
            setState(() => _status = '正在进入 ${scenario.title}…');
          }

          final result = await UserApi.setActiveScenario(activeId);
          _launch = _StartupLaunch(
            mode: scenario.mode,
            scenarioId: result.scenarioId.toString(),
            sessionId: result.sessionId.toString(),
          );
        }
      }
    } catch (error) {
      // 登录已经有效；恢复上次世界失败时只进入空 Shell，不重新要求登录。
      debugPrint('startup active scenario restore failed: $error');
      _launch = null;
    }

    if (!mounted) return;
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: const Color(0xFF090A09),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white54,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _status,
                style: TextStyle(
                  color: Colors.white.withOpacity(.48),
                  fontSize: 12,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final launch = _launch;
    if (launch != null) {
      return _StartupRedirect(launch: launch);
    }

    // 无登录态 / 没有 activeScenario / 恢复失败：
    // 不再进入 HomePage，只保留空 GameShell。未登录时不自动打开 Drawer，避免抢焦点。
    return GameShellPage(
      initialSession: _session,
      autoOpenDrawer: _session != null, 
    );
  }
}

class _StartupRedirect extends StatefulWidget {
  const _StartupRedirect({required this.launch});

  final _StartupLaunch launch;

  @override
  State<_StartupRedirect> createState() => _StartupRedirectState();
}

class _StartupRedirectState extends State<_StartupRedirect> {
  bool _redirected = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_redirected) return;
    _redirected = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final launch = widget.launch;
      final mode = launch.mode.trim().toLowerCase();
      final routeMode = _routeMode(mode);
      final route = mode == 'online'
          ? '/online/${launch.scenarioId}'
          : '/$routeMode/${launch.scenarioId}';

      Navigator.of(context).pushReplacementNamed(
        route,
        arguments: <String, dynamic>{
          'session_id': launch.sessionId,
          if (mode == 'online') 'mode': 'create',
        },
      );
    });
  }

  String _routeMode(String mode) {
    switch (mode) {
      case 'novel':
        return 'novel';
      case 'group':
        return 'group';
      case 'rpg':
        return 'rpg';
      case 'chat':
      default:
        return 'chat';
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF090A09),
      body: SizedBox.expand(),
    );
  }
}