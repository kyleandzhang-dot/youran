import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app_shared.dart';
import 'app_notice.dart';
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

class _GameShellState extends State<GameShell> with WidgetsBindingObserver {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  UserSession? _session;
  bool _loaded = false;
  bool _autoOpened = false;

  /// -1 表示当前没有真正激活的剧情。
  int _selectedGameIndex = -1;
  DrawerModule _selectedModule = DrawerModule.world;

  /// 只有用户点击剧情并且 setActiveScenario 成功后，才允许关闭空 Shell 的左侧抽屉。
  bool _scenarioSelectionCommitted = false;

  bool get _mustKeepDrawerOpen {
    if (_scenarioSelectionCommitted) return false;
    final activeId = widget.activeScenarioId?.trim() ?? '';
    return activeId.isEmpty;
  }

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
  String? _activeCreationTaskId;
  bool _creationPolling = false;
  bool _recoveringCreation = false;
  bool _appInForeground = true;
  int _creationPollEpoch = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  @override
  void dispose() {
    _creationPollEpoch++;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _appInForeground = true;
      if (_isLoggedIn) unawaited(_recoverCreationTask());
      return;
    }

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _appInForeground = false;
      _creationPollEpoch++;
      _creationPolling = false;
    }
  }

  @override
  void didUpdateWidget(covariant GameShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeScenarioId != widget.activeScenarioId && _loaded) {
      _scenarioSelectionCommitted = false;
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
    if (_isLoggedIn) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_recoverCreationTask());
      });
    }
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

      // 只有“当前路由真的正在展示某个世界”或调用方明确要求 focus 时，
      // 才把世界列表中的某一项标记为已选中。
      // 空 GameShellPage 只是世界选择页，即使后端仍记着 activeScenarioId，
      // 也必须保持 selectedIndex = -1；否则用户点击刚刚取消进入的同一世界时，
      // Drawer 会把它当成“重复点击当前世界”直接 return，表现为完全没反应。
      final focusId = focusScenarioId?.toString().trim() ?? '';
      final routeActiveId = widget.activeScenarioId?.toString().trim() ?? '';
      final targetScenarioId = focusId.isNotEmpty
          ? focusId
          : (routeActiveId.isNotEmpty ? routeActiveId : null);

      var selectedIndex = -1;
      final targetId = targetScenarioId?.toString().trim() ?? '';
      if (games.isNotEmpty && targetId.isNotEmpty) {
        final found = games.indexWhere(
          (game) => game.id.toString() == targetId,
        );
        if (found >= 0) selectedIndex = found;
      }

      setState(() {
        _games = games;
        _selectedGameIndex = selectedIndex;
      });
    } catch (error) {
      debugPrint('GameShell home data failed: $error');
    }
  }

  /// 统一的 Drawer 世界列表刷新入口。
  /// 手动下拉、删除后的同步、创建完成后的同步都最终走 _loadHomeData。
  Future<void> _refreshDrawerWorlds() async {
    await _loadHomeData(focusScenarioId: widget.activeScenarioId);
  }

  /// 后端写入/删除完成后，HomeData 可能有极短的可见性延迟。
  /// 这里做少量重试，确保 Drawer 最终和后端一致。
  Future<bool> _syncWorldListUntil({
    required String scenarioId,
    required bool shouldExist,
    String? focusScenarioId,
    int maxAttempts = 5,
  }) async {
    final targetId = scenarioId.trim();

    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      await _loadHomeData(focusScenarioId: focusScenarioId);
      if (!mounted) return false;

      if (targetId.isEmpty) return true;

      final exists = _games.any(
        (game) => game.id.toString() == targetId,
      );

      if (exists == shouldExist) return true;

      if (attempt < maxAttempts - 1) {
        await Future<void>.delayed(
          Duration(milliseconds: 250 + attempt * 200),
        );
      }
    }

    return false;
  }

  Future<void> _closeDrawerIfNeeded({bool force = false}) async {
    if (!force && _mustKeepDrawerOpen) return;

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

    try {
      final result = await UserApi.setActiveScenario(scenario.id.toString());
      if (!mounted) return;

      // 后端确认成功后，才算用户真正选择了剧情。
      setState(() {
        _selectedGameIndex = index;
        _scenarioSelectionCommitted = true;
      });

      await _closeDrawerIfNeeded(force: true);
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
      if (mounted) AppNotice.error(context, '进入世界失败，请稍后重试');
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
      AppNotice.error(context, '缺少剧本或会话参数，无法进入世界');
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
      if (mounted) AppNotice.error(context, '游戏路由尚未配置：$route');
    }
  }

  Future<void> _reenterScenarioAfterReset(String scenarioId) async {
    final targetId = scenarioId.trim();
    if (targetId.isEmpty) return;

    // resetScenario 会清空当前运行时会话/剧情数据，因此不能继续留在旧游戏页。
    // 先重新同步一次世界列表，确保仍能拿到这个 scenario 的最新信息。
    await _syncWorldListUntil(
      scenarioId: targetId,
      shouldExist: true,
      focusScenarioId: targetId,
    );
    if (!mounted) return;

    final targetIndex = _games.indexWhere(
      (game) => game.id.toString() == targetId,
    );

    if (targetIndex < 0) {
      AppNotice.error(context, '世界已重置，但暂时无法重新载入，请从世界列表重新进入');
      _scaffoldKey.currentState?.openDrawer();
      return;
    }

    // 直接复用正常“进入世界”的完整流程：
    // setActiveScenario -> 获取新的 sessionId -> pushReplacement 到对应游戏页。
    // 这里必须主动调用，不能依赖用户再次点击当前世界；Drawer 对当前世界重选会直接 return。
    await _onGameSelected(targetIndex);
  }

  Future<void> _onEditWorld(int index) async {
    if (index < 0 || index >= _games.length) return;

    final scenario = _games[index];
    final scenarioId = scenario.id.toString();
    var deleted = false;

    // 编辑页目前用 true 表示“数据生命周期发生变化”。
    // 删除通过 onDeleted 单独标记；其余 true 即为重置剧情。
    final isDataChanged = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => ScenarioEditPage(
          scenarioId: scenarioId,
          onDeleted: () {
            deleted = true;
          },
        ),
      ),
    );

    if (!mounted) return;

    // 判断：编辑的这个剧本，是不是我们现在正在玩的剧本？
    final isCurrentWorld = widget.activeScenarioId?.toString() == scenarioId;

    if (deleted) {
      await _syncWorldListUntil(
        scenarioId: scenarioId,
        shouldExist: false,
      );
      if (!mounted) return;

      // 如果删除的是当前世界，退出当前剧本，回到空 Shell。
      if (isCurrentWorld) {
        Navigator.of(context, rootNavigator: true).pushReplacement<void, void>(
          MaterialPageRoute<void>(
            builder: (_) => GameShellPage(
              initialSession: _session,
              autoOpenDrawer: true,
            ),
          ),
        );
      }
      return;
    }

    // 如果重置的是当前正在玩的世界，旧 session / 剧情状态已经失效。
    // 必须立即重新执行一次“进入世界”，让后端创建/返回新的 session，
    // 否则旧游戏页会继续读取被清空的运行时数据，最终表现为空白页面。
    if (isDataChanged == true && isCurrentWorld) {
      await _reenterScenarioAfterReset(scenarioId);
      return;
    }

    // 重置的不是当前世界，或只是普通退出编辑页：仅刷新世界列表即可。
    await _loadHomeData(
      focusScenarioId: isDataChanged == true ? scenarioId : null,
    );
  }

  Future<void> _onShareWorld() async {
    if (!_isLoggedIn) {
      await _closeDrawerIfNeeded();
      if (mounted) _openLoginSheet();
      return;
    }
    if (_games.isEmpty) {
      AppNotice.info(context, '还没有可以分享的世界');
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
    var pollingStarted = false;
    final taskId = await CreateWorldDialog.show(
      context,
      onTaskSubmitted: (submittedTaskId) {
        if (!mounted || pollingStarted) return;
        pollingStarted = true;
        unawaited(_startPollingCreation(submittedTaskId));
      },
    );

    if (!mounted || taskId == null || pollingStarted) return;
    unawaited(_startPollingCreation(taskId));
  }

  Future<void> _recoverCreationTask() async {
    if (!mounted ||
        !_isLoggedIn ||
        !_appInForeground ||
        _recoveringCreation ||
        _creationPolling) {
      return;
    }

    _recoveringCreation = true;
    try {
      final response = await ApiClient.instance.get(
        '/chat/ai/generate-scenario/active',
      );
      if (!mounted || !_appInForeground) return;

      final raw = response['data'];
      if (raw is! Map) return;
      final taskId = raw['task_id']?.toString().trim() ?? '';
      if (taskId.isEmpty) return;

      unawaited(_startPollingCreation(taskId, recovered: true));
    } catch (error) {
      // 恢复查询失败不能伪装成“生成失败”；下次回前台或刷新时会再次查询。
      debugPrint('GameShell restore creation task failed: $error');
    } finally {
      _recoveringCreation = false;
    }
  }

  Future<void> _acknowledgeCreationTask(String taskId) async {
    try {
      await ApiClient.instance.post(
        '/chat/ai/generate-scenario/status/$taskId/acknowledge',
      );
    } catch (error) {
      // 未确认成功时后端会在下次启动继续返回该结果，避免完成通知永久丢失。
      debugPrint('GameShell acknowledge creation task failed: $error');
    }
  }

  Future<void> _showCreationFailure(String taskId, String message) async {
    if (!mounted) return;
    setState(() {
      _createWorldError = true;
      _createWorldStep = message;
      _activeCreationTaskId = null;
    });
    AppNotice.error(context, message);
    await _acknowledgeCreationTask(taskId);
    await Future<void>.delayed(const Duration(seconds: 4));
    if (mounted) {
      setState(() {
        _isCreatingWorld = false;
        _createWorldError = false;
      });
    }
  }

  Future<void> _startPollingCreation(
    String taskId, {
    bool recovered = false,
  }) async {
    final normalizedTaskId = taskId.trim();
    if (normalizedTaskId.isEmpty || !mounted) return;
    if (_creationPolling && _activeCreationTaskId == normalizedTaskId) return;

    final pollEpoch = ++_creationPollEpoch;
    _creationPolling = true;
    final isSameTask = _activeCreationTaskId == normalizedTaskId;
    _activeCreationTaskId = normalizedTaskId;

    setState(() {
      _isCreatingWorld = true;
      if (!isSameTask) _createWorldProgress = 0;
      _createWorldStep = recovered ? '正在恢复世界创建进度...' : '任务已提交，正在构筑世界...';
      _createWorldError = false;
    });

    var currentInterval = 2000;
    var consecutiveErrors = 0;
    var missingTaskErrors = 0;

    try {
      // 只要 App 在前台且任务未结束就持续查询；进入后台时由 epoch 立即失效。
      while (mounted && _appInForeground && pollEpoch == _creationPollEpoch) {
        try {
          final statusResponse = await ApiClient.instance.get(
            '/chat/ai/generate-scenario/status/$normalizedTaskId',
          );
          if (!mounted || pollEpoch != _creationPollEpoch) return;

          consecutiveErrors = 0;
          missingTaskErrors = 0;
          final rawStatusData = statusResponse['data'];
          final statusData = rawStatusData is Map
              ? rawStatusData
              : <String, dynamic>{};
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

            final result = statusData['result'] as Map?;
            final createdScenarioId =
                result?['scenario_id']?.toString().trim() ?? '';
            final title = result?['title']?.toString().trim() ?? '';

            var synced = true;
            if (createdScenarioId.isNotEmpty) {
              synced = await _syncWorldListUntil(
                scenarioId: createdScenarioId,
                shouldExist: true,
                focusScenarioId: createdScenarioId,
              );
            } else {
              await _loadHomeData();
            }

            if (!mounted || pollEpoch != _creationPollEpoch) return;
            setState(() {
              _isCreatingWorld = false;
              _activeCreationTaskId = null;
            });

            if (synced) {
              AppNotice.success(
                context,
                title.isEmpty ? '世界创建完成，已加入世界列表' : '《$title》创建完成，已加入世界列表',
              );
            } else {
              AppNotice.info(context, '世界已生成，列表同步稍有延迟，可下拉刷新');
            }
            await _acknowledgeCreationTask(normalizedTaskId);
            return;
          }

          if (status == 'failed') {
            final message = statusData['error']?.toString().trim();
            await _showCreationFailure(
              normalizedTaskId,
              message == null || message.isEmpty
                  ? '世界创建失败，请稍后重试'
                  : message,
            );
            return;
          }

          final suggested = int.tryParse(
            statusData['next_poll_interval']?.toString() ?? '',
          );
          if (suggested != null && suggested > 0) {
            currentInterval = suggested.clamp(1000, 10000).toInt();
          }
        } on ApiException catch (error) {
          consecutiveErrors++;
          if (error.statusCode == 404) missingTaskErrors++;

          if (missingTaskErrors >= 3) {
            await _showCreationFailure(
              normalizedTaskId,
              '创建任务记录已失效，请重新创建',
            );
            return;
          }

          if (mounted && pollEpoch == _creationPollEpoch) {
            setState(() {
              _createWorldStep = '网络不稳定，正在重新连接...';
              _createWorldError = false;
            });
          }
          currentInterval = math.min(10000, 1500 * (consecutiveErrors + 1));
        } catch (error) {
          consecutiveErrors++;
          debugPrint('GameShell creation polling retry: $error');
          if (mounted && pollEpoch == _creationPollEpoch) {
            setState(() {
              _createWorldStep = '连接暂时中断，正在恢复进度...';
              _createWorldError = false;
            });
          }
          currentInterval = math.min(10000, 1500 * (consecutiveErrors + 1));
        }

        await Future<void>.delayed(Duration(milliseconds: currentInterval));
      }
    } finally {
      if (pollEpoch == _creationPollEpoch) {
        _creationPolling = false;
      }
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

    try {
      // 抛弃弹窗，直接调用 API 发起签到请求
      final result = await MineApi.dailyCheckin();

      // 强制重新请求一次个人资料，确保点数绝对准确
      await _loadProfile();

      if (!mounted) return;

      // 触发 UI 刷新，将状态变为已签到
      setState(() {
        _checkinStatusLoaded = true;
        _checkedInToday = true;
      });

      AppNotice.success(context, '签到成功  +${result.reward} 积分');
    } catch (e) {
      if (!mounted) return;
      final errorMsg = e.toString().replaceFirst('Exception: ', '').replaceFirst('ApiException: ', '');
      AppNotice.error(context, errorMsg);
    }
  }

  Future<void> _logout() async {
    _creationPollEpoch++;
    _creationPolling = false;
    _activeCreationTaskId = null;
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
        if (mounted) unawaited(_recoverCreationTask());
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

  @override
  Widget build(BuildContext context) {
    final drawer = GameDrawer(
      games: _games,
      selectedGameIndex: _selectedGameIndex,
      onGameSelected: _onGameSelected,
      onEditWorld: _onEditWorld,
      onCreateWorld: _onCreateWorld,
      onShareWorld: _onShareWorld,
      onRefreshWorld: _refreshDrawerWorlds,
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
      onRefreshProfile: _loadProfile,
      currentUserId: _isLoggedIn ? _userId : null,
      onScenarioLaunch: _onScenarioLaunch,
      selectedModule: _selectedModule,
      onModuleSelected: (module) => setState(() => _selectedModule = module),
      isCreatingWorld: _isCreatingWorld,
      createWorldProgress: _createWorldProgress,
      createWorldStep: _createWorldStep,
      createWorldError: _createWorldError,
    );

    final pageBody = widget.builder(
      context,
      () => _scaffoldKey.currentState?.openDrawer(),
    );

    // 空 Shell 且没有已激活剧情时，左侧栏直接固定在页面上。
    // 这样点击遮罩、返回键、侧滑都无法把它关闭；
    // 用户必须真正选择一个剧情并激活成功后才会解锁。
    if (_loaded && _mustKeepDrawerOpen) {
      return PopScope(
        canPop: false,
        child: Scaffold(
          key: _scaffoldKey,
          resizeToAvoidBottomInset: widget.resizeToAvoidBottomInset,
          backgroundColor: const Color(0xFF171918),
          body: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              pageBody,
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {},
                child: ColoredBox(
                  color: Colors.black.withOpacity(.58),
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: math.min(
                    MediaQuery.sizeOf(context).width * 0.82,
                    300.0,
                  ),
                  height: double.infinity,
                  child: drawer,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return PopScope(
      // 剧情路由永远不允许系统返回键直接 pop。
      // 否则当它已经是根游戏路由时，会暴露下面的空壳/空白页面。
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop) return;
        final scaffold = _scaffoldKey.currentState;
        if (scaffold == null) return;

        if (scaffold.isDrawerOpen) {
          // 菜单已经打开时，返回键只负责把菜单收起。
          Navigator.of(context).pop();
        } else {
          // 正常剧情中按返回：只打开左侧菜单，不离开当前世界。
          scaffold.openDrawer();
        }
      },
      child: Scaffold(
        key: _scaffoldKey,
        resizeToAvoidBottomInset: widget.resizeToAvoidBottomInset,
        backgroundColor: widget.backgroundColor,
        drawerScrimColor: Colors.black.withOpacity(.78),
        drawer: drawer,
        body: pageBody,
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
