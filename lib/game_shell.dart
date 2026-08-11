import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app_shared.dart';
import 'api/store_api.dart';
import 'api/api_client.dart';
import 'api/mine_api.dart';
import 'api/user_api.dart';
import 'create_world_dialog.dart';
import 'game_drawer.dart';
import 'login_sheet.dart';
import 'mine_dialogs.dart';
import 'scenario_edit_page.dart';
import 'services/session_manager.dart';
import 'share_world_page.dart';

typedef GameShellBodyBuilder = Widget Function(
  BuildContext context,
  VoidCallback openDrawer,
);

/// 全局游戏壳：负责 Drawer、用户资料、世界列表、创建/编辑/分享世界与世界切换。
///
/// 它不是“首页”。真正的游戏页面（Novel / RPG / Chat）作为 [builder] 的内容显示。
/// 切换世界使用 pushReplacementNamed，始终只保留当前世界这一层游戏路由。
class GameShell extends StatefulWidget {
  const GameShell({
    super.key,
    required this.builder,
    this.activeScenarioId,
    this.initialSession,
    this.autoOpenDrawer = false,
    this.backgroundColor = const Color(0xFF090A09),
    this.resizeToAvoidBottomInset = true,
  });

  final GameShellBodyBuilder builder;
  final String? activeScenarioId;
  final UserSession? initialSession;
  final bool autoOpenDrawer;
  final Color backgroundColor;
  final bool resizeToAvoidBottomInset;

  @override
  State<GameShell> createState() => _GameShellState();
}

class _GameShellState extends State<GameShell> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  UserSession? _session;
  bool _loaded = false;
  bool _autoOpened = false;

  int _selectedGameIndex = 0;
  DrawerModule _selectedModule = DrawerModule.world;

  bool _isLoggedIn = false;
  String _userName = '玩家';
  String _userId = '';
  String _userUid = '';
  int _userPoints = 0;
  String? _userAvatarUrl;

  bool _checkinStatusLoaded = false;
  bool _checkedInToday = false;

  List<GameData> _games = const <GameData>[];

  bool _isCreatingWorld = false;
  double _createWorldProgress = 0;
  String _createWorldStep = '';
  bool _createWorldError = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void didUpdateWidget(covariant GameShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeScenarioId != widget.activeScenarioId && _loaded) {
      _loadHomeData(focusScenarioId: widget.activeScenarioId);
    }
  }

  Future<void> _bootstrap() async {
    // 重要：GameShell 不能再次调用 SessionManager.restore()。
    // NovelGamePage 的 controller.initialize() 会与 Shell 同时启动；
    // 某些 SessionManager.restore() 会先清空内存 token/userId，再刷新 token，
    // 这会让正在进行的场景/历史请求瞬间失去鉴权，最终显示“世界暂时无法载入”。
    //
    // 冷启动的 Session 由 main.dart 的 StartupGate 只恢复一次；
    // 游戏页 Shell 只复用已经存在的 ApiClient 身份。
    final restored = widget.initialSession;

    if (restored != null) {
      ApiClient.instance.accessToken = restored.accessToken;
      ApiClient.instance.userId =
          restored.userId.trim().isEmpty ? null : restored.userId.trim();
      _applySession(restored);
    } else {
      final token = ApiClient.instance.accessToken?.trim() ?? '';
      final userId = ApiClient.instance.userId?.trim() ?? '';

      _session = null;
      _isLoggedIn = token.isNotEmpty;
      _userName = '玩家';
      _userId = userId;
      _userUid = userId;
      _userPoints = 0;

      if (!_isLoggedIn) {
        _userAvatarUrl = null;
        _checkinStatusLoaded = false;
        _checkedInToday = false;
      }
    }

    if (_isLoggedIn) {
      await _refreshUserData(focusScenarioId: widget.activeScenarioId);
    }

    if (!mounted) return;
    setState(() => _loaded = true);
    _maybeAutoOpenDrawer();
  }

  void _applySession(UserSession? session) {
    _session = session;
    _isLoggedIn = session != null;
    if (session == null) {
      _userName = '玩家';
      _userId = '';
      _userUid = '';
      _userPoints = 0;
      _userAvatarUrl = null;
      _checkinStatusLoaded = false;
      _checkedInToday = false;
      return;
    }

    _userName = session.username;
    _userId = session.userId;
    _userUid = session.userId;
    _userPoints = session.tokenBalance;

    // Shell 内所有请求与 NovelRuntime 共用同一份身份。
    ApiClient.instance.accessToken = session.accessToken;
    ApiClient.instance.userId =
        session.userId.trim().isEmpty ? null : session.userId.trim();
  }

  void _maybeAutoOpenDrawer() {
    if (!widget.autoOpenDrawer || _autoOpened || !mounted) return;
    _autoOpened = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scaffoldKey.currentState?.openDrawer();
    });
  }

  Future<void> _refreshUserData({String? focusScenarioId}) async {
    if (!_isLoggedIn) return;
    await Future.wait<void>(<Future<void>>[
      _loadProfile(),
      _loadCheckinStatus(),
      _loadHomeData(focusScenarioId: focusScenarioId),
    ]);
  }

  Future<void> _loadCheckinStatus() async {
    try {
      final status = await MineApi.getCheckinStatus();
      if (!mounted) return;
      setState(() {
        _checkinStatusLoaded = true;
        _checkedInToday = status.checkedInToday;
      });
    } catch (error) {
      debugPrint('GameShell checkin status failed: $error');
    }
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await MineApi.getProfile();
      if (!mounted) return;

      final name = MineApi.profileName(profile);
      final shortId = MineApi.profileShortId(profile);
      final backendUserId =
          (profile['user_id'] ?? profile['id'] ?? '').toString().trim();
      final avatar = MineApi.profileAvatar(profile);
      final balance = MineApi.profileBalance(profile);

      setState(() {
        if (name.isNotEmpty) _userName = name;
        if (backendUserId.isNotEmpty) {
          _userId = backendUserId;
          ApiClient.instance.userId = backendUserId;
        }
        if (shortId.isNotEmpty) _userUid = shortId;
        _userPoints = balance;
        _userAvatarUrl = avatar.isEmpty ? null : avatar;
      });
    } catch (error) {
      debugPrint('GameShell profile failed: $error');
    }
  }

  Future<void> _loadHomeData({String? focusScenarioId}) async {
    try {
      final home = await UserApi.getHomeData();
      if (!mounted) return;

      final games = home.scenarios
          .map(
            (scenario) => GameData(
              title: scenario.title,
              category: scenario.mode,
              imageUrl: scenario.coverUrl,
              id: scenario.id,
              mode: scenario.mode,
            ),
          )
          .toList();

      final targetScenarioId =
          focusScenarioId ?? widget.activeScenarioId ?? home.activeScenarioId?.toString();
      var selectedIndex = 0;
      if (games.isNotEmpty && targetScenarioId != null) {
        final found = games.indexWhere(
          (game) => game.id.toString() == targetScenarioId.toString(),
        );
        if (found >= 0) selectedIndex = found;
      }

      setState(() {
        _games = games;
        _selectedGameIndex = games.isEmpty ? 0 : selectedIndex;
      });
    } catch (error) {
      debugPrint('GameShell home data failed: $error');
    }
  }

  Future<void> _closeDrawerIfNeeded() async {
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      Navigator.of(context).pop();
      await Future<void>.delayed(const Duration(milliseconds: 110));
    }
  }

  Future<void> _onGameSelected(int index) async {
    if (index < 0 || index >= _games.length) return;

    if (!_isLoggedIn) {
      await _closeDrawerIfNeeded();
      if (!mounted) return;
      _openLoginSheet();
      return;
    }

    final scenario = _games[index];
    if (mounted) setState(() => _selectedGameIndex = index);
    await _closeDrawerIfNeeded();
    if (!mounted) return;

    try {
      final result = await UserApi.setActiveScenario(scenario.id.toString());
      if (!mounted) return;
      await _replaceScenarioRoute(
        ScenarioLaunchInfo(
          mode: scenario.mode,
          scenarioId: result.scenarioId,
          sessionId: result.sessionId,
        ),
      );
    } catch (error) {
      debugPrint('GameShell set active scenario failed: $error');
      if (mounted) _showInPageNotification('进入世界失败，请稍后重试');
    }
  }

  void _onScenarioLaunch(ScenarioLaunchInfo launch) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _replaceScenarioRoute(launch);
    });
  }

  String _routeMode(String mode) {
    switch (mode.trim().toLowerCase()) {
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

  Future<void> _replaceScenarioRoute(ScenarioLaunchInfo launch) async {
    if (!launch.isValid) {
      _showInPageNotification('缺少剧本或会话参数，无法进入世界');
      return;
    }

    final mode = launch.mode.trim().toLowerCase();
    final route = mode == 'online'
        ? '/online/${launch.scenarioId}'
        : '/${_routeMode(mode)}/${launch.scenarioId}';

    final arguments = <String, dynamic>{
      'session_id': launch.sessionId,
      if (mode == 'online') 'mode': 'create',
    };

    try {
      await Navigator.of(context, rootNavigator: true).pushReplacementNamed(
        route,
        arguments: arguments,
      );
    } catch (error) {
      debugPrint('GameShell route failed: route=$route error=$error');
      if (mounted) _showInPageNotification('游戏路由尚未配置：$route');
    }
  }

  Future<void> _onEditWorld(int index) async {
    if (index < 0 || index >= _games.length) return;
    final scenario = _games[index];
    final scenarioId = scenario.id.toString();

    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => ScenarioEditPage(scenarioId: scenarioId),
      ),
    );

    if (!mounted) return;
    await _loadHomeData(focusScenarioId: changed == true ? scenarioId : null);
  }

  Future<void> _onShareWorld() async {
    if (!_isLoggedIn) {
      await _closeDrawerIfNeeded();
      if (mounted) _openLoginSheet();
      return;
    }
    if (_games.isEmpty) {
      _showInPageNotification('还没有可以分享的世界');
      return;
    }

    final safeIndex = _selectedGameIndex.clamp(0, _games.length - 1).toInt();
    await ShareWorldPage.show(
      context,
      games: _games,
      initialIndex: safeIndex,
    );
  }

  Future<void> _onCreateWorld() async {
    final taskId = await CreateWorldDialog.show(context);
    if (!mounted || taskId == null) return;
    _startPollingCreation(taskId);
  }

  Future<void> _startPollingCreation(String taskId) async {
    setState(() {
      _isCreatingWorld = true;
      _createWorldProgress = 0;
      _createWorldStep = '任务已提交，正在构筑世界...';
      _createWorldError = false;
    });

    var currentInterval = 2000;
    const maxRetries = 120;

    for (var attempts = 0; attempts < maxRetries; attempts++) {
      if (!mounted) return;
      try {
        final statusResponse = await ApiClient.instance.get(
          '/chat/ai/generate-scenario/status/$taskId',
        );
        if (!mounted) return;

        final statusData =
            statusResponse is Map ? statusResponse['data'] ?? statusResponse : <String, dynamic>{};
        final status = (statusData['status']?.toString() ?? '').toLowerCase();
        final progress = statusData['progress'] as Map?;

        if (progress != null) {
          setState(() {
            _createWorldStep = progress['step']?.toString() ?? _createWorldStep;
            final pct = double.tryParse(progress['percent']?.toString() ?? '');
            if (pct != null) {
              _createWorldProgress = math.max(_createWorldProgress, pct);
            }
          });
        }

        if (status == 'completed') {
          setState(() {
            _createWorldProgress = 100;
            _createWorldStep = '生成完成！';
          });
          await Future<void>.delayed(const Duration(milliseconds: 650));
          if (!mounted) return;

          final result = statusData['result'] as Map?;
          final createdScenarioId = result?['scenario_id']?.toString() ?? '';
          setState(() => _isCreatingWorld = false);
          await _loadHomeData(
            focusScenarioId: createdScenarioId.isEmpty ? null : createdScenarioId,
          );

          if (createdScenarioId.isNotEmpty && mounted) {
            final index = _games.indexWhere(
              (game) => game.id.toString() == createdScenarioId,
            );
            if (index >= 0) await _onGameSelected(index);
          }
          return;
        }

        if (status == 'failed') {
          throw Exception(
            statusData['error']?.toString() ?? '构筑中断：检测到敏感词或余额不足',
          );
        }

        if (statusData['next_poll_interval'] != null) {
          currentInterval =
              int.tryParse(statusData['next_poll_interval'].toString()) ?? currentInterval;
        }
      } catch (error) {
        if (mounted) {
          setState(() {
            _createWorldError = true;
            _createWorldStep = error.toString().replaceAll('Exception: ', '');
          });
        }
        break;
      }

      await Future<void>.delayed(Duration(milliseconds: currentInterval));
    }

    if (mounted && _createWorldError) {
      await Future<void>.delayed(const Duration(seconds: 4));
      if (mounted) setState(() => _isCreatingWorld = false);
    }
  }

  void _onAvatarTap() {
    if (!_isLoggedIn) {
      _openLoginSheet();
      return;
    }
    if (_selectedModule != DrawerModule.mine) {
      setState(() => _selectedModule = DrawerModule.mine);
    }
  }

  Future<void> _editUserName() async {
    if (!_isLoggedIn) return;
    final nextName = await MineDialogs.editName(
      context,
      currentName: _userName,
    );
    if (!mounted || nextName == null || nextName.isEmpty) return;
    setState(() => _userName = nextName);
  }

  Future<void> _editUserAvatar() async {
    if (!_isLoggedIn) return;
    final nextAvatar = await MineDialogs.editAvatar(context);
    if (!mounted || nextAvatar == null || nextAvatar.isEmpty) return;
    setState(() => _userAvatarUrl = nextAvatar);
  }

  Future<void> _handleHeaderCheckin() async {
    if (!_isLoggedIn) return;
    final result = await MineDialogs.checkin(context);
    if (!mounted || result == null) return;

    setState(() {
      _checkinStatusLoaded = true;
      _checkedInToday = true;
      if (result.balance != null) _userPoints = result.balance!;
    });

    if (result.balance == null) {
      await _loadProfile();
      if (!mounted) return;
    }

    _showInPageNotification('签到成功  +${result.reward} y币', success: true);
  }

  Future<void> _logout() async {
    await SessionManager.logout();
    ApiClient.instance.accessToken = null;
    ApiClient.instance.userId = null;
    if (!mounted) return;

    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil<void>(
      MaterialPageRoute<void>(
        builder: (_) => const GameShellPage(autoOpenDrawer: true),
      ),
      (route) => false,
    );
  }

  void _openLoginSheet() {
    LoginSheet.show(
      context,
      onLoginSuccess: (result) async {
        await SessionManager.persist(result);

        // 兼容不同版本 SessionManager：登录成功后这里再显式同步一次。
        ApiClient.instance.accessToken = result.accessToken;
        ApiClient.instance.userId = result.userId;

        if (!mounted) return;
        setState(() {
          _isLoggedIn = true;
          _userName = result.username;
          _userId = result.userId;
          _userUid = result.shortId.isNotEmpty ? result.shortId : result.userId;
          _userPoints = result.tokenBalance.toInt();
        });
        await _refreshUserData();
        if (!mounted) return;
        await _openActiveScenarioAfterLogin();
      },
    );
  }

  Future<void> _openActiveScenarioAfterLogin() async {
    try {
      final home = await UserApi.getHomeData();
      final activeId = home.activeScenarioId?.toString() ?? '';
      if (activeId.isEmpty) {
        _maybeAutoOpenDrawer();
        return;
      }
      final index = _games.indexWhere((game) => game.id.toString() == activeId);
      if (index >= 0) await _onGameSelected(index);
    } catch (error) {
      debugPrint('GameShell open active after login failed: $error');
    }
  }

  void _showInPageNotification(String message, {bool success = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xE8181A19),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.only(bottom: 26, left: 20, right: 20),
          duration: const Duration(milliseconds: 2200),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.white.withOpacity(.08)),
          ),
          content: Row(
            children: <Widget>[
              Icon(
                success ? Icons.check_circle_outline_rounded : Icons.info_outline_rounded,
                size: 17,
                color: success ? const Color(0xFF8FC6A0) : Colors.white70,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(color: Color(0xFFF1F1ED), fontSize: 12.5),
                ),
              ),
            ],
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final drawer = GameDrawer(
      games: _games,
      selectedGameIndex: _selectedGameIndex,
      onGameSelected: _onGameSelected,
      onEditWorld: _onEditWorld,
      onCreateWorld: _onCreateWorld,
      onShareWorld: _onShareWorld,
      isLoggedIn: _isLoggedIn,
      userName: _userName,
      userAvatarUrl: _userAvatarUrl,
      userPoints: _userPoints,
      userUid: _isLoggedIn ? _userUid : null,
      onAvatarTap: _onAvatarTap,
      onEditAvatar: _editUserAvatar,
      onEditName: _editUserName,
      onLogout: _logout,
      checkinStatusLoaded: _checkinStatusLoaded,
      checkedInToday: _checkedInToday,
      onCheckin: _handleHeaderCheckin,
      currentUserId: _isLoggedIn ? _userId : null,
      onScenarioLaunch: _onScenarioLaunch,
      selectedModule: _selectedModule,
      onModuleSelected: (module) => setState(() => _selectedModule = module),
      isCreatingWorld: _isCreatingWorld,
      createWorldProgress: _createWorldProgress,
      createWorldStep: _createWorldStep,
      createWorldError: _createWorldError,
    );

    return Scaffold(
      key: _scaffoldKey,
      resizeToAvoidBottomInset: widget.resizeToAvoidBottomInset,
      backgroundColor: widget.backgroundColor,
      drawerScrimColor: Colors.black.withOpacity(.78),
      drawer: drawer,
      body: widget.builder(
        context,
        () => _scaffoldKey.currentState?.openDrawer(),
      ),
    );
  }
}

/// 只有“没有可直接进入的激活世界”时才会出现。
/// 它不是首页，只是 GameShell 的空壳，并默认打开 Drawer 让玩家选择世界。
class GameShellPage extends StatelessWidget {
  const GameShellPage({
    super.key,
    this.initialSession,
    this.autoOpenDrawer = true,
  });

  final UserSession? initialSession;
  final bool autoOpenDrawer;

  @override
  Widget build(BuildContext context) {
    return GameShell(
      initialSession: initialSession,
      autoOpenDrawer: autoOpenDrawer,
      builder: (context, openDrawer) {
        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[
                    Color(0xFF171918),
                    Color(0xFF0D0F0E),
                    Color(0xFF080908),
                  ],
                ),
              ),
            ),
            SafeArea(
              child: Stack(
                children: <Widget>[
                  Positioned(
                    left: 14,
                    top: 10,
                    child: IconButton(
                      tooltip: '菜单',
                      onPressed: openDrawer,
                      icon: const Icon(Icons.menu_rounded),
                      color: Colors.white.withOpacity(.86),
                    ),
                  ),
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 36),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(
                            Icons.explore_outlined,
                            size: 30,
                            color: Colors.white.withOpacity(.30),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            '从左侧选择一个世界',
                            style: TextStyle(
                              color: Colors.white.withOpacity(.58),
                              fontSize: 13,
                              letterSpacing: 1.1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
