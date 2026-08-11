import 'dart:ui';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'login_sheet.dart';
import 'api/user_api.dart';
import 'api/api_client.dart';
import 'api/mine_api.dart';
import 'api/store_api.dart';
import 'app_shared.dart';
import 'create_world_dialog.dart';
import 'game_drawer.dart';
import 'scenario_edit_page.dart';
import 'share_world_page.dart';
import 'services/session_manager.dart';
import 'story_stage.dart';
import 'mine_dialogs.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    this.initialSession,
    this.backgroundAsset = 'assets/images/home_background.jpg',
    this.sceneName = '萧家',
    this.sceneSubtitle = '后山',
    this.characterName = '林夕',
    this.characterAvatarAsset = 'assets/images/character_avatar.png',
    this.characterHp = 78,
    this.characterMaxHp = 100,
    this.inputHint = '输入你的行动…',
    this.storyLines = const [],
    this.onSendMessage,
  });

  final UserSession? initialSession;
  final String backgroundAsset;
  final String sceneName;
  final String sceneSubtitle;
  final String characterName;
  final String characterAvatarAsset;
  final int characterHp;
  final int characterMaxHp;
  final String inputHint;
  final List<StoryLine> storyLines;
  final ValueChanged<String>? onSendMessage;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  int _selectedGameIndex = 0;
  DrawerModule _selectedModule = DrawerModule.world;

  late bool _isLoggedIn;
  late String _userName;
  /// 后端真实 user_id：用于作者权限、评论权限等业务判断。
  late String _userId;
  /// 展示用短 UID。
  late String _userUid;
  late int _userPoints;
  bool _checkinStatusLoaded = false;
  bool _checkedInToday = false;

  String? _userAvatarUrl;
  List<GameData> _games = const [];

  // 创建世界状态
  bool _isCreatingWorld = false;
  double _createWorldProgress = 0.0;
  String _createWorldStep = '';
  bool _createWorldError = false;

  final TextEditingController _messageController = TextEditingController();
  final FocusNode _messageFocusNode = FocusNode();
  bool _canSendMessage = false;
  late List<StoryLine> _displayedStoryLines;

  late final AnimationController _sceneIntroController;
  late final Animation<double> _sceneIntroOpacity;
  late final Animation<Offset> _sceneIntroSlide;

  @override
  void initState() {
    super.initState();

    _sceneIntroController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    );

    _sceneIntroOpacity = TweenSequence<double>(
      [
        TweenSequenceItem(tween: Tween<double>(begin: 0, end: 1), weight: 18),
        TweenSequenceItem(tween: ConstantTween<double>(1), weight: 56),
        TweenSequenceItem(tween: Tween<double>(begin: 1, end: 0), weight: 26),
      ],
    ).animate(
      CurvedAnimation(parent: _sceneIntroController, curve: Curves.easeOutCubic),
    );

    _sceneIntroSlide = Tween<Offset>(
      begin: const Offset(-0.035, 0.025),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _sceneIntroController,
        curve: const Interval(0, 0.30, curve: Curves.easeOutCubic),
      ),
    );

    _messageController.addListener(_handleMessageChanged);
    _displayedStoryLines = List<StoryLine>.of(widget.storyLines);

    final session = widget.initialSession;
    if (session != null) {
      _isLoggedIn = true;
      _userName = session.username;
      _userId = session.userId;
      // 冷启动时先用真实 userId 兜底，profile 拉回后再替换成 short_id。
      _userUid = session.userId;
      _userPoints = session.tokenBalance;
      _refreshUserData();
    } else {
      _isLoggedIn = false;
      _userName = '玩家';
      _userId = '';
      _userUid = '';
      _userPoints = 0;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _sceneIntroController.forward(from: 0);
    });
  }

  @override
  void didUpdateWidget(covariant HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sceneName != widget.sceneName ||
        oldWidget.sceneSubtitle != widget.sceneSubtitle) {
      _sceneIntroController.forward(from: 0);
    }
    if (!identical(oldWidget.storyLines, widget.storyLines)) {
      _displayedStoryLines = List<StoryLine>.of(widget.storyLines);
    }
  }

  @override
  void dispose() {
    _sceneIntroController.dispose();
    _messageController..removeListener(_handleMessageChanged)..dispose();
    _messageFocusNode.dispose();
    super.dispose();
  }

  Future<void> _refreshUserData({String? focusScenarioId}) async {
    await Future.wait<void>([
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
      debugPrint('load checkin status failed: $error');
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
        if (backendUserId.isNotEmpty) _userId = backendUserId;
        if (shortId.isNotEmpty) _userUid = shortId;
        _userPoints = balance;
        _userAvatarUrl = avatar.isEmpty ? null : avatar;
      });
    } catch (error) {
      debugPrint('load profile failed: $error');
    }
  }

  Future<void> _loadHomeData({String? focusScenarioId}) async {
    try {
      final home = await UserApi.getHomeData();
      if (!mounted) return;

      final games = home.scenarios.map((s) => GameData(
        title: s.title, category: s.mode, imageUrl: s.coverUrl, id: s.id, mode: s.mode,
      )).toList();

      final targetScenarioId = focusScenarioId ?? home.activeScenarioId;
      var selectedIndex = 0;
      if (games.isNotEmpty && targetScenarioId != null) {
        final foundIndex = games.indexWhere((g) => g.id.toString() == targetScenarioId.toString());
        if (foundIndex >= 0) selectedIndex = foundIndex;
      }

      setState(() {
        _games = games;
        _selectedGameIndex = games.isEmpty ? 0 : selectedIndex;
      });
    } catch (error) {
      debugPrint('load home data failed: $error');
    }
  }

  /// 世界列表点击：先让后端设置当前剧本并拿到 session_id，
  /// 然后与「发现 / 我的作品」共用同一套路由入口。
  Future<void> _onGameSelected(int index) async {
    if (index < 0 || index >= _games.length) return;

    if (!_isLoggedIn) {
      if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
        Navigator.of(context).pop();
      }
      _openLoginSheet();
      return;
    }

    final scenario = _games[index];
    setState(() => _selectedGameIndex = index);

    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      Navigator.of(context).pop();
    }

    try {
      final result = await UserApi.setActiveScenario(scenario.id.toString());
      if (!mounted) return;

      await _openScenarioRoute(
        ScenarioLaunchInfo(
          mode: scenario.mode,
          scenarioId: result.scenarioId,
          sessionId: result.sessionId,
        ),
      );
    } catch (error) {
      debugPrint('set active scenario failed: $error');
      if (!mounted) return;
      _showInPageNotification('进入世界失败，请稍后重试');
    }
  }

  /// 「发现 / 我的作品」的详情页已经完成 fork，并直接返回
  /// ScenarioLaunchInfo(mode + scenarioId + sessionId)。
  ///
  /// DiscoverDetailWindow 会在回调返回后关闭自己的弹窗，因此这里将真正
  /// 的路由跳转放到下一帧，避免“刚 push 游戏页又被详情弹窗 pop 掉”。
  void _onScenarioLaunch(ScenarioLaunchInfo launch) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _openScenarioRoute(launch);
    });
  }

  /// 与 Vue 的 handleEnterChat / 作品启动逻辑保持相同的 mode 路由规则。
  Future<void> _openScenarioRoute(ScenarioLaunchInfo launch) async {
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
      await Navigator.of(context, rootNavigator: true).pushNamed(
        route,
        arguments: arguments,
      );
    } catch (error) {
      debugPrint('scenario route failed: route=$route error=$error');
      if (!mounted) return;
      _showInPageNotification('游戏路由尚未配置：$route');
    }
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

  Future<void> _onEditWorld(int index) async {
    if (index < 0 || index >= _games.length) return;

    final scenario = _games[index];
    final scenarioId = scenario.id.toString();

    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ScenarioEditPage(
          scenarioId: scenarioId,
        ),
      ),
    );

    if (!mounted) return;

    // 从编辑页返回后重新拉取世界列表。
    // 这样标题、封面、删除状态等修改会立刻同步到 Drawer。
    if (changed == true) {
      await _loadHomeData(focusScenarioId: scenarioId);
    } else {
      await _loadHomeData();
    }
  }

  Future<void> _onShareWorld() async {
    if (!_isLoggedIn) {
      if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
        Navigator.of(context).pop();
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
      if (!mounted) return;
      _openLoginSheet();
      return;
    }

    if (_games.isEmpty) {
      _showInPageNotification('还没有可以分享的世界');
      return;
    }

    // 分享世界直接浮在当前页面和左侧抽屉之上，不主动关闭 Drawer。
    if (!mounted) return;

    final safeIndex = _selectedGameIndex.clamp(0, _games.length - 1).toInt();
    await ShareWorldPage.show(
      context,
      games: _games,
      initialIndex: safeIndex,
    );
  }

  Future<void> _onCreateWorld() async {
    // 保持抽屉开启，直接弹出居中对话框
    final taskId = await CreateWorldDialog.show(context);
    if (!mounted || taskId == null) return;

    // 拿到 taskId 开始抽屉底部的任务更新
    _startPollingCreation(taskId);
  }

  Future<void> _startPollingCreation(String taskId) async {
    setState(() {
      _isCreatingWorld = true;
      _createWorldProgress = 0.0;
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

        final statusData = statusResponse is Map ? statusResponse['data'] ?? statusResponse : {};
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
          
          await Future.delayed(const Duration(milliseconds: 1200)); 
          if (!mounted) return;
          
          setState(() => _isCreatingWorld = false);
          
          final result = statusData['result'] as Map?;
          if (result != null) {
            await _refreshUserData(focusScenarioId: result['scenario_id']?.toString());
          }
          return;
        }

        if (status == 'failed') {
          throw Exception(statusData['error']?.toString() ?? '构筑中断：检测到敏感词或余额不足');
        }

        if (statusData['next_poll_interval'] != null) {
          currentInterval = int.tryParse(statusData['next_poll_interval'].toString()) ?? currentInterval;
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

      await Future.delayed(Duration(milliseconds: currentInterval));
    }
    
    if (mounted && _createWorldError) {
      await Future.delayed(const Duration(seconds: 4));
      if (mounted) setState(() => _isCreatingWorld = false);
    }
  }

  void _showInPageNotification(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF161616),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
           borderRadius: BorderRadius.circular(8),
           side: BorderSide(color: const Color(0xFFE0554A).withOpacity(0.4), width: 1),
        ),
        margin: const EdgeInsets.only(bottom: 84, left: 20, right: 20),
        content: Text(
          msg,
          style: const TextStyle(color: Color(0xFFE7685E), fontSize: 13),
        ),
        duration: const Duration(milliseconds: 2500),
      ),
    );
  }

  void _onAvatarTap() {
    if (!_isLoggedIn) {
      _openLoginSheet();
      return;
    }

    // 已登录时顶部资料区只负责切到「我的」，不关闭 Drawer。
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
      if (result.balance != null) {
        _userPoints = result.balance!;
      }
    });

    if (result.balance == null) {
      await _loadProfile();
      if (!mounted) return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF161616),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(milliseconds: 1800),
          content: Row(
            children: [
              const Icon(
                Icons.check_circle_outline_rounded,
                size: 17,
                color: AppColors.accent,
              ),
              const SizedBox(width: 8),
              Text(
                '签到成功  +${result.reward} y币',
                style: const TextStyle(
                  color: AppColors.textOnDark,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
  }

  Future<void> _logout() async {
    // 同时清空内存 access token、refresh token 和本地用户快照。
    await SessionManager.logout();

    if (!mounted) return;
    setState(() {
      _isLoggedIn = false;
      _userName = '玩家';
      _userId = '';
      _userUid = '';
      _userPoints = 0;
      _userAvatarUrl = null;
      _checkinStatusLoaded = false;
      _checkedInToday = false;
      _selectedModule = DrawerModule.world;
    });
  }

  void _openLoginSheet() {
    LoginSheet.show(
      context,
      onLoginSuccess: (result) async {
        await SessionManager.persist(result);
        if (!mounted) return;
        setState(() {
          _isLoggedIn = true;
          _userName = result.username;
          _userId = result.userId;
          _userUid = result.shortId.isNotEmpty ? result.shortId : result.userId;
          _userPoints = result.tokenBalance.toInt();
        });
        _refreshUserData();
      },
    );
  }

  void _handleMessageChanged() {
    final canSend = _messageController.text.trim().isNotEmpty;
    if (canSend == _canSendMessage || !mounted) return;
    setState(() => _canSendMessage = canSend);
  }

  void _sendPlayerMessage() {
    final message = _messageController.text.trim();
    if (message.isEmpty) return;

    setState(() {
      _displayedStoryLines = [
        ..._displayedStoryLines,
        StoryLine(text: message, type: StoryLineType.player),
      ];
    });

    final onSendMessage = widget.onSendMessage;
    if (onSendMessage != null) {
      onSendMessage(message);
    } else {
      _showInPageNotification('消息已提交，请通过 onSendMessage 接入剧情接口');
    }

    _messageController.clear();
    _messageFocusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      resizeToAvoidBottomInset: true,
      backgroundColor: const Color(0xFF090A09),
      drawerScrimColor: Colors.black.withOpacity(0.80),
      drawer: GameDrawer(
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
        // 发现页作者权限需要后端真实 user_id，不能传展示用 short UID。
        currentUserId: _isLoggedIn ? _userId : null,
        // 发现 / 我的作品 → 详情 → 开始游戏，统一走这里。
        onScenarioLaunch: _onScenarioLaunch,
        selectedModule: _selectedModule,
        onModuleSelected: (module) => setState(() => _selectedModule = module),
        isCreatingWorld: _isCreatingWorld,
        createWorldProgress: _createWorldProgress,
        createWorldStep: _createWorldStep,
        createWorldError: _createWorldError,
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          _WorldBackground(assetPath: widget.backgroundAsset),
          SafeArea(
            minimum: const EdgeInsets.fromLTRB(16, 10, 16, 18),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 410;
                return Stack(
                  children: [
                    Align(
                      alignment: Alignment.topLeft,
                      child: _SceneHeader(
                        title: widget.sceneName,
                        subtitle: widget.sceneSubtitle,
                        compact: compact,
                        onMenuTap: () => _scaffoldKey.currentState?.openDrawer(),
                      ),
                    ),
                    Align(
                      alignment: Alignment.topRight,
                      child: _CharacterStatus(
                        name: widget.characterName, avatarAsset: widget.characterAvatarAsset,
                        hp: widget.characterHp, maxHp: widget.characterMaxHp, compact: compact,
                      ),
                    ),
                    Positioned(
                      left: compact ? 8 : 18,
                      right: compact ? 48 : constraints.maxWidth * 0.28,
                      top: constraints.maxHeight * (compact ? 0.18 : 0.20),
                      child: IgnorePointer(
                        child: FadeTransition(
                          opacity: _sceneIntroOpacity,
                          child: SlideTransition(
                            position: _sceneIntroSlide,
                            child: _SceneArrivalTitle(
                              title: widget.sceneName, subtitle: widget.sceneSubtitle, compact: compact,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0, right: 0,
                      top: constraints.maxHeight * (compact ? 0.29 : 0.31),
                      bottom: compact ? 64 : 68,
                      child: StoryStage(lines: _displayedStoryLines),
                    ),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 720),
                        child: _StoryInputBar(
                          controller: _messageController, focusNode: _messageFocusNode,
                          hintText: widget.inputHint, canSend: _canSendMessage, onSend: _sendPlayerMessage,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _WorldBackground extends StatelessWidget {
  const _WorldBackground({required this.assetPath});
  final String assetPath;
  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(assetPath, fit: BoxFit.cover, alignment: Alignment.center, filterQuality: FilterQuality.high, errorBuilder: (_,__,___)=>const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF343027), Color(0xFF171A17), Color(0xFF080908)])))),
        const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, stops: [0.0, 0.22, 0.58, 1.0], colors: [Color(0x5E000000), Color(0x1F000000), Color(0x00000000), Color(0x4A000000)]))),
        const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.centerLeft, end: Alignment.centerRight, stops: [0.0, 0.26, 0.62, 1.0], colors: [Color(0x50000000), Color(0x14000000), Color(0x00000000), Color(0x16000000)]))),
        IgnorePointer(child: DecoratedBox(decoration: BoxDecoration(gradient: RadialGradient(center: const Alignment(0.04, -0.08), radius: 1.18, colors: [Colors.transparent, Colors.black.withOpacity(0.25)], stops: const [0.56, 1.0])))),
      ],
    );
  }
}

class _SceneHeader extends StatelessWidget {
  const _SceneHeader({required this.title, required this.subtitle, required this.compact, required this.onMenuTap});
  final String title; final String subtitle; final bool compact; final VoidCallback onMenuTap;
  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          height: 42, constraints: BoxConstraints(maxWidth: compact ? 164 : 204), color: Colors.white.withOpacity(0.065),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                button: true, label: '打开菜单',
                child: Material(
                  color: Colors.transparent,
                  child: InkResponse(
                    onTap: onMenuTap, radius: 22, containedInkWell: true, highlightShape: BoxShape.rectangle,
                    child: SizedBox(width: 42, height: 42, child: Center(child: Icon(LucideIcons.menu, size: 20, color: Colors.white.withOpacity(0.92)))),
                  ),
                ),
              ),
              Container(width: 1, height: 18, color: Colors.white.withOpacity(0.13)),
              const SizedBox(width: 10),
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFFF4F3EE), fontSize: 14.5, height: 1, fontWeight: FontWeight.w600, letterSpacing: 0.45)),
                      const SizedBox(height: 4),
                      Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white.withOpacity(0.48), fontSize: 9, height: 1, fontWeight: FontWeight.w500, letterSpacing: 1.35)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SceneArrivalTitle extends StatelessWidget {
  const _SceneArrivalTitle({required this.title, required this.subtitle, required this.compact});
  final String title; final String subtitle; final bool compact;
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: const Color(0xFFF7F3EA), fontSize: compact ? 39 : 50, height: 0.96, fontWeight: FontWeight.w500, letterSpacing: compact ? 3.0 : 4.2, shadows: const [Shadow(color: Color(0xD9000000), blurRadius: 24, offset: Offset(0, 5))])),
        const SizedBox(height: 15),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: compact ? 27 : 38, height: 1, color: Colors.white.withOpacity(0.68)),
            const SizedBox(width: 12),
            Flexible(child: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white.withOpacity(0.76), fontSize: compact ? 11 : 12, height: 1, fontWeight: FontWeight.w500, letterSpacing: compact ? 3.6 : 4.8, shadows: const [Shadow(color: Color(0xC7000000), blurRadius: 12)]))),
          ],
        ),
      ],
    );
  }
}

class _CharacterStatus extends StatelessWidget {
  const _CharacterStatus({required this.name, required this.avatarAsset, required this.hp, required this.maxHp, required this.compact});
  final String name; final String avatarAsset; final int hp; final int maxHp; final bool compact;
  @override
  Widget build(BuildContext context) {
    final safeMax = maxHp <= 0 ? 1 : maxHp;
    final progress = (hp.clamp(0, safeMax) / safeMax);
    return Row(
      mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: compact ? 72 : 104),
              child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.right, style: const TextStyle(color: Color(0xFFF4F3EE), fontSize: 12.5, height: 1, fontWeight: FontWeight.w600, letterSpacing: 0.3, shadows: [Shadow(color: Color(0xA6000000), blurRadius: 8, offset: Offset(0, 2))])),
            ),
            const SizedBox(height: 7),
            _GlowHpBar(progress: progress, width: compact ? 54 : 68),
          ],
        ),
        const SizedBox(width: 9),
        _LightAvatar(assetPath: avatarAsset),
      ],
    );
  }
}

class _LightAvatar extends StatelessWidget {
  const _LightAvatar({required this.assetPath});
  final String assetPath;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34, height: 34,
      decoration: const BoxDecoration(shape: BoxShape.circle, boxShadow: [BoxShadow(color: Color(0x52000000), blurRadius: 10, offset: Offset(0, 3))]),
      child: ClipOval(child: Image.asset(assetPath, fit: BoxFit.cover, filterQuality: FilterQuality.high, errorBuilder: (_,__,___)=>Container(color: const Color(0xB3222521), alignment: Alignment.center, child: Icon(LucideIcons.userRound, size: 15, color: Colors.white.withOpacity(0.66))))),
    );
  }
}

class _GlowHpBar extends StatelessWidget {
  const _GlowHpBar({required this.progress, required this.width});
  final double progress; final double width;
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width, height: 3,
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(color: Colors.black.withOpacity(0.32), borderRadius: BorderRadius.circular(20)))),
          FractionallySizedBox(widthFactor: progress.clamp(0.0, 1.0).toDouble(), child: Container(height: 3, decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: AppColors.accent.withOpacity(0.58), blurRadius: 7, spreadRadius: 0.3)]))),
        ],
      ),
    );
  }
}

class _StoryInputBar extends StatelessWidget {
  const _StoryInputBar({required this.controller, required this.focusNode, required this.hintText, required this.canSend, required this.onSend});
  final TextEditingController controller; final FocusNode focusNode; final String hintText; final bool canSend; final VoidCallback onSend;
  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          constraints: const BoxConstraints(minHeight: 48), padding: const EdgeInsets.fromLTRB(15, 5, 6, 5), color: Colors.white.withOpacity(0.085),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: controller, focusNode: focusNode, minLines: 1, maxLines: 3, keyboardType: TextInputType.multiline, textInputAction: TextInputAction.newline, cursorColor: AppColors.accent,
                  style: const TextStyle(color: Color(0xFFF4F3EE), fontSize: 14, height: 1.35, fontWeight: FontWeight.w400),
                  decoration: InputDecoration(hintText: hintText, hintStyle: TextStyle(color: Colors.white.withOpacity(0.38), fontSize: 13.5, fontWeight: FontWeight.w400), isDense: true, contentPadding: const EdgeInsets.symmetric(vertical: 8), border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none),
                ),
              ),
              const SizedBox(width: 8),
              AnimatedOpacity(
                duration: const Duration(milliseconds: 150), opacity: canSend ? 1 : 0.34,
                child: Material(
                  color: canSend ? AppColors.accent : Colors.white.withOpacity(0.10), shape: const CircleBorder(),
                  child: InkWell(customBorder: const CircleBorder(), onTap: canSend ? onSend : null, child: SizedBox(width: 36, height: 36, child: Icon(LucideIcons.arrowUp, size: 18, color: canSend ? const Color(0xFF0A110C) : Colors.white.withOpacity(0.52)))),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}