import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'app_shared.dart';
import 'api/store_api.dart';
import 'api/profile_api.dart';
import 'api/notification_api.dart';
import 'discover_detail_sheet.dart';
import 'share_world_page.dart';
import 'mine_dialogs.dart';

/// 抽屉顶部的三个功能模块
enum DrawerModule { world, discover, mine }

/// 同一套导航既可作为剧情中的 Drawer，也可作为大厅中的固定侧栏。
enum GameDrawerPresentation { drawer, sidebar }

class GameDrawer extends StatelessWidget {
  const GameDrawer({
    super.key,
    required this.games,
    required this.selectedGameIndex,
    required this.onGameSelected,
    required this.onCreateWorld,
    required this.isLoggedIn,
    required this.userName,
    this.userAvatarUrl,
    required this.userPoints,
    this.userUid,
    this.onAvatarTap,
    this.onEditAvatar,
    this.onEditName,
    this.onLogout,
    this.checkinStatusLoaded = false,
    this.checkedInToday = false,
    this.onCheckin,
    this.onRefreshProfile,
    this.currentUserId,
    this.onScenarioLaunch,
    this.scenarioShareLinkBuilder,
    this.onOpenPublished,
    this.onOpenFavorites,
    this.onOpenNotifications,
    this.onShareWorld,
    this.onEditWorld,
    this.onRefreshWorld,
    this.onCheckWorldCreationCompleted,
    this.selectedModule = DrawerModule.world,
    this.onModuleSelected,
    this.isCreatingWorld = false,
    this.createWorldProgress = 0.0,
    this.createWorldStep = '',
    this.createWorldError = false,
    this.presentation = GameDrawerPresentation.drawer,
  });

  final List<GameData> games;
  final int selectedGameIndex;
  final ValueChanged<int> onGameSelected;
  final VoidCallback onCreateWorld;
  final bool isLoggedIn;
  final String userName;
  final String? userAvatarUrl;
  final int userPoints;
  final String? userUid;
  final VoidCallback? onAvatarTap;
  final VoidCallback? onEditAvatar;
  final VoidCallback? onEditName;
  final VoidCallback? onLogout;
  final bool checkinStatusLoaded;
  final bool checkedInToday;
  final VoidCallback? onCheckin;
  final VoidCallback? onRefreshProfile;
  final String? currentUserId;
  final ScenarioLaunchCallback? onScenarioLaunch;
  final String Function(String scenarioId)? scenarioShareLinkBuilder;
  final VoidCallback? onOpenPublished;
  final VoidCallback? onOpenFavorites;
  final VoidCallback? onOpenNotifications;
  final VoidCallback? onShareWorld;

  /// 刷新「世界」列表。
  /// 外层应传入真正重新请求世界列表的 Future 方法。
  final Future<void> Function()? onRefreshWorld;

  /// 创建世界期间，用后端真实状态兜底校验是否已经完成。
  /// 返回 true 表示后端已经完成创建；返回 false 表示仍在生成。
  /// 该回调可选：未提供时，会通过 onRefreshWorld + 世界数量变化做兜底。
  final Future<bool> Function()? onCheckWorldCreationCompleted;

  /// 点击「世界」列表每一项右侧的更多按钮时触发。
  /// 外层用 index 找到真实 scenarioId，再 push ScenarioEditPage。
  /// 之所以不直接读取 game.id，是因为当前 GameData 模型未暴露在此文件中。
  final ValueChanged<int>? onEditWorld;

  final DrawerModule selectedModule;
  final ValueChanged<DrawerModule>? onModuleSelected;

  final bool isCreatingWorld;
  final double createWorldProgress;
  final String createWorldStep;
  final bool createWorldError;

  /// drawer：剧情中由 Scaffold.drawer 弹出。
  /// sidebar：大厅中固定在左侧，不再响应 Navigator.pop() 关闭逻辑。
  final GameDrawerPresentation presentation;

  bool get _isSidebar => presentation == GameDrawerPresentation.sidebar;

  @override
  Widget build(BuildContext context) {
    final width = _isSidebar
        ? 300.0
        : math.min(MediaQuery.sizeOf(context).width * 0.82, 300.0);

    final content = Container(
      width: width,
      color: const Color.fromARGB(255, 253, 253, 253).withOpacity(0.1),
      child: SafeArea(
        child: Column(
          children: [
                const SizedBox(height: 12),
                _DrawerHeader(
                  isLoggedIn: isLoggedIn,
                  isMine: selectedModule == DrawerModule.mine,
                  name: userName,
                  avatarUrl: userAvatarUrl,
                  points: userPoints,
                  uid: userUid,
                  onProfileTap: onAvatarTap,
                  onEditAvatar: onEditAvatar,
                  onEditName: onEditName,
                  checkinStatusLoaded: checkinStatusLoaded,
                  checkedInToday: checkedInToday,
                  onCheckin: onCheckin,
                ),
                const SizedBox(height: 14),
                _ModuleTabs(
                  selected: selectedModule,
                  onSelected: onModuleSelected ?? (_) {},
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: _buildMainContent(),
                ),
                
                // 根据状态切换底部按钮或进度面板（加入原地过渡动画）
                if (selectedModule == DrawerModule.world)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 16),
                    child: _CreationProgressSlot(
                      isCreatingWorld: isCreatingWorld,
                      progress: createWorldProgress,
                      step: createWorldStep,
                      hasError: createWorldError,
                      worldCount: games.length,
                      onCreateWorld: onCreateWorld,
                      onRefreshWorld: onRefreshWorld,
                      onCheckCompleted: onCheckWorldCreationCompleted,
                    ),
                  )
                else if (selectedModule == DrawerModule.discover)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 16),
                    child: _BottomActionButton(
                      icon: LucideIcons.share,
                      label: '分享世界',
                      // 如果外层没传回调，就默认弹起分享面板
                      onTap: onShareWorld ?? () {
                        ShareWorldPage.show(
                          context,
                          games: games,
                          initialIndex: selectedGameIndex,
                        );
                      },
                    ),
                  ),
          ],
        ),
      ),
    );

    if (_isSidebar) {
      return SizedBox(
        width: width,
        height: double.infinity,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFF171717).withOpacity(.92),
            border: Border(
              right: BorderSide(color: Colors.white.withOpacity(.07)),
            ),
          ),
          child: content,
        ),
      );
    }

    return Drawer(
      width: width,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
          child: content,
        ),
      ),
    );
  }

  Widget _buildMainContent() {
    switch (selectedModule) {
      case DrawerModule.world:
        return _WorldPanel(
          games: games,
          selectedGameIndex: selectedGameIndex,
          onGameSelected: onGameSelected,
          onEditWorld: onEditWorld,
          onRefresh: onRefreshWorld,
          dismissOnReselect: !_isSidebar,
        );
      case DrawerModule.mine:
        return _MinePanel(
          isLoggedIn: isLoggedIn,
          currentUserId: currentUserId,
          onScenarioLaunch: onScenarioLaunch,
          scenarioShareLinkBuilder: scenarioShareLinkBuilder,
          onOpenPublished: onOpenPublished,
          onOpenFavorites: onOpenFavorites,
          onOpenNotifications: onOpenNotifications,
          onLogout: onLogout,
          onRefreshProfile: onRefreshProfile,
        );
      case DrawerModule.discover:
        return _DiscoverPanel(
          isLoggedIn: isLoggedIn,
          currentUserId: currentUserId,
          onScenarioLaunch: onScenarioLaunch,
          scenarioShareLinkBuilder: scenarioShareLinkBuilder,
        );
    }
  }
}


class _WorldPanel extends StatelessWidget {
  const _WorldPanel({
    required this.games,
    required this.selectedGameIndex,
    required this.onGameSelected,
    this.onEditWorld,
    this.onRefresh,
    this.dismissOnReselect = true,
  });

  final List<GameData> games;
  final int selectedGameIndex;
  final ValueChanged<int> onGameSelected;
  final ValueChanged<int>? onEditWorld;
  final Future<void> Function()? onRefresh;
  final bool dismissOnReselect;

  Future<void> _refresh() async {
    final callback = onRefresh;
    if (callback == null) return;
    await callback();
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      color: AppColors.accent,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        itemCount: games.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          return _WorldItem(
            game: games[index],
            selected: selectedGameIndex == index,
            onTap: () {
              // 核心拦截：如果点击的就是当前正在游玩的剧本
              if (selectedGameIndex == index) {
                // 剧情 Drawer 中重复点击当前世界：只关闭抽屉。
                // 大厅固定侧栏中不能 pop，否则会误退出当前页面。
                if (dismissOnReselect && Navigator.of(context).canPop()) {
                  Navigator.of(context).pop();
                }
                return;
              }
              
              // 点击了其他剧本，正常走切换逻辑
              onGameSelected(index);
            },
            onDetailTap: () {
              final callback = onEditWorld;
              if (callback == null) {
                debugPrint('未配置 onEditWorld：${games[index].title}');
                return;
              }

              // 直接触发跳转，不关闭抽屉
              callback(index);
            },
          );
        },
      ),
    );
  }
}

class _CreationProgressSlot extends StatefulWidget {
  const _CreationProgressSlot({
    required this.isCreatingWorld,
    required this.progress,
    required this.step,
    required this.hasError,
    required this.worldCount,
    required this.onCreateWorld,
    this.onRefreshWorld,
    this.onCheckCompleted,
  });

  final bool isCreatingWorld;
  final double progress;
  final String step;
  final bool hasError;
  final int worldCount;
  final VoidCallback onCreateWorld;
  final Future<void> Function()? onRefreshWorld;
  final Future<bool> Function()? onCheckCompleted;

  @override
  State<_CreationProgressSlot> createState() => _CreationProgressSlotState();
}

class _CreationProgressSlotState extends State<_CreationProgressSlot> {
  Timer? _pollTimer;
  bool _checking = false;
  bool _resolvedLocally = false;
  late int _worldCountAtStart;

  @override
  void initState() {
    super.initState();
    _worldCountAtStart = widget.worldCount;
    _configurePolling();
  }

  @override
  void didUpdateWidget(covariant _CreationProgressSlot oldWidget) {
    super.didUpdateWidget(oldWidget);

    // 新一轮创建开始时重新建立基线。
    if (widget.isCreatingWorld && !oldWidget.isCreatingWorld) {
      _resolvedLocally = false;
      _worldCountAtStart = widget.worldCount;
      _configurePolling();
    }

    // 外层已经收到完成状态，立即结束本地轮询。
    if (!widget.isCreatingWorld && oldWidget.isCreatingWorld) {
      _resolvedLocally = false;
      _pollTimer?.cancel();
      _pollTimer = null;
    }

    // 即使完成事件丢失，只要刷新后世界数量增加，也判定创建已落库。
    if (widget.isCreatingWorld &&
        !_resolvedLocally &&
        widget.worldCount > _worldCountAtStart) {
      _markResolved();
    }

    // 100% 本身就是强完成信号：马上再向后端/列表核对一次。
    if (widget.isCreatingWorld &&
        !widget.hasError &&
        widget.progress >= 100 &&
        oldWidget.progress < 100) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncCreationState());
    }

    if (widget.isCreatingWorld &&
        (oldWidget.onRefreshWorld != widget.onRefreshWorld ||
            oldWidget.onCheckCompleted != widget.onCheckCompleted)) {
      _configurePolling();
    }
  }

  void _configurePolling() {
    _pollTimer?.cancel();
    _pollTimer = null;

    if (!widget.isCreatingWorld || _resolvedLocally) return;
    if (widget.onRefreshWorld == null && widget.onCheckCompleted == null) return;

    WidgetsBinding.instance.addPostFrameCallback((_) => _syncCreationState());
    _pollTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _syncCreationState(),
    );
  }

  Future<void> _syncCreationState() async {
    if (!mounted ||
        !widget.isCreatingWorld ||
        widget.hasError ||
        _resolvedLocally ||
        _checking) {
      return;
    }

    _checking = true;
    try {
      final checker = widget.onCheckCompleted;
      if (checker != null) {
        final completed = await checker();
        if (!mounted) return;
        if (completed) {
          _markResolved();
          await widget.onRefreshWorld?.call();
          return;
        }
      }

      // 没有专门状态接口时，至少重拉世界列表。
      // 新世界一旦出现在 games 中，didUpdateWidget 会自动结束进度条。
      await widget.onRefreshWorld?.call();

      // 如果流式进度已经明确到 100%，刷新一次后不再让 UI 永久卡住。
      if (mounted && widget.progress >= 100 && !widget.hasError) {
        _markResolved();
      }
    } catch (e) {
      debugPrint('创建世界状态同步失败：$e');
    } finally {
      _checking = false;
    }
  }

  void _markResolved() {
    if (!mounted || _resolvedLocally) return;
    _pollTimer?.cancel();
    _pollTimer = null;
    setState(() => _resolvedLocally = true);
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showProgress = widget.isCreatingWorld && !_resolvedLocally;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: SizeTransition(
            sizeFactor: animation,
            axisAlignment: 1.0,
            child: child,
          ),
        );
      },
      child: showProgress
          ? _CreationProgressPanel(
              key: const ValueKey('progress_panel'),
              progress: widget.progress,
              step: widget.step,
              hasError: widget.hasError,
            )
          : _BottomActionButton(
              key: const ValueKey('create_button'),
              icon: LucideIcons.plus,
              label: '创建世界',
              onTap: widget.onCreateWorld,
            ),
    );
  }
}

class _CreationProgressPanel extends StatefulWidget {
  const _CreationProgressPanel({
    super.key,
    required this.progress,
    required this.step,
    required this.hasError,
  });

  final double progress;
  final String step;
  final bool hasError;

  @override
  State<_CreationProgressPanel> createState() => _CreationProgressPanelState();
}

class _CreationProgressPanelState extends State<_CreationProgressPanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _glowController;
  late final Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true); 

    _glowAnimation = Tween<double>(begin: 0.2, end: 0.7).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        border: Border.all(
          color: widget.hasError 
              ? const Color(0xFFE0554A).withOpacity(0.4) 
              : Colors.white.withOpacity(0.08),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  widget.step,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: widget.hasError ? const Color(0xFFE0554A) : AppColors.textOnDark,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (!widget.hasError)
                Text(
                  '${widget.progress.round()}%',
                  style: const TextStyle(
                    color: AppColors.accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Courier',
                  ),
                ),
            ],
          ),
          if (!widget.hasError) ...[
            const SizedBox(height: 8),
            ClipRect(
              child: SizedBox(
                height: 2.5, 
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(color: Colors.white.withOpacity(0.1)),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: AnimatedFractionallySizedBox(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOutCubic,
                        widthFactor: (widget.progress / 100).clamp(0.0, 1.0),
                        child: AnimatedBuilder(
                          animation: _glowAnimation,
                          builder: (context, child) {
                            return Container(
                              decoration: BoxDecoration(
                                color: AppColors.accent,
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.accent.withOpacity(_glowAnimation.value),
                                    blurRadius: 6,
                                    spreadRadius: 0.5,
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ]
        ],
      ),
    );
  }
}

class _DrawerHeader extends StatelessWidget {
  const _DrawerHeader({
    required this.isLoggedIn,
    required this.isMine,
    required this.name,
    required this.avatarUrl,
    required this.points,
    this.uid,
    this.onProfileTap,
    this.onEditAvatar,
    this.onEditName,
    this.checkinStatusLoaded = false,
    this.checkedInToday = false,
    this.onCheckin,
  });

  final bool isLoggedIn;
  final bool isMine;
  final String name;
  final String? avatarUrl;
  final int points;
  final String? uid;
  final VoidCallback? onProfileTap;
  final VoidCallback? onEditAvatar;
  final VoidCallback? onEditName;
  final bool checkinStatusLoaded;
  final bool checkedInToday;
  final VoidCallback? onCheckin;

  @override
  Widget build(BuildContext context) {
    // 手机端顶部头像行为统一：
    // 已登录时无论当前在“世界 / 发现 / 我的”哪个模块，都直接编辑头像；
    // 未登录时才走登录/资料入口。
    final avatarTap =
        isLoggedIn ? (onEditAvatar ?? onProfileTap) : onProfileTap;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Row(
        children: [
          GestureDetector(
            onTap: avatarTap,
            behavior: HitTestBehavior.opaque,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                ClipOval(
                  child: (isLoggedIn &&
                          avatarUrl != null &&
                          avatarUrl!.isNotEmpty)
                      ? Image.network(
                          avatarUrl!,
                          width: 44,
                          height: 44,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _fallbackAvatar(),
                        )
                      : _fallbackAvatar(),
                ),
                if (!isLoggedIn)
                  Positioned(
                    right: -1,
                    bottom: -1,
                    child: Container(
                      width: 16,
                      height: 16,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.accent,
                        border: Border.all(
                          color: const Color.fromARGB(255, 20, 20, 20),
                          width: 1.5,
                        ),
                      ),
                      child: const Icon(
                        Icons.add_rounded,
                        size: 11,
                        color: Color.fromARGB(255, 6, 6, 6),
                      ),
                    ),
                  )
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              onTap: !isLoggedIn
                  ? onProfileTap
                  : isMine
                      ? null
                      : onProfileTap,
              behavior: HitTestBehavior.opaque,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: isLoggedIn && isMine ? onEditName : null,
                    behavior: HitTestBehavior.opaque,
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            isLoggedIn ? name : '登录 / 注册',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textOnDark,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (isLoggedIn)
                    Row(
                      children: [
                        Text(
                          'UID: ${uid?.isNotEmpty == true ? uid : '--'}',
                          style: TextStyle(
                            color: AppColors.textOnDarkMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Icon(
                          LucideIcons.gem,
                          size: 11,
                          color: AppColors.textOnDarkMuted,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          '$points',
                          style: TextStyle(
                            color: AppColors.textOnDarkMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    )
                  else
                    Text(
                      '登录解锁存档与积分',
                      style: TextStyle(
                        color: AppColors.textOnDarkMuted,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (isLoggedIn && isMine) ...[
            const SizedBox(width: 8),
            _HeaderCheckinButton(
              loaded: checkinStatusLoaded,
              checked: checkedInToday,
              onTap: onCheckin,
            ),
          ],
        ],
      ),
    );
  }

  Widget _fallbackAvatar() {
    return Container(
      width: 44,
      height: 44,
      color: Colors.white.withOpacity(0.08),
      child: Icon(
        Icons.person_rounded,
        color: AppColors.textOnDarkMuted,
        size: 22,
      ),
    );
  }
}


class _HeaderCheckinButton extends StatelessWidget {
  const _HeaderCheckinButton({
    required this.loaded,
    required this.checked,
    this.onTap,
  });

  final bool loaded;
  final bool checked;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final canTap = loaded && onTap != null;

    return Material(
      color: checked
          ? Colors.white.withOpacity(0.028)
          : AppColors.accent.withOpacity(0.08),
      borderRadius: BorderRadius.circular(6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: canTap ? onTap : null,
        child: Container(
          height: 31,
          constraints: const BoxConstraints(minWidth: 50),
          padding: const EdgeInsets.symmetric(horizontal: 9),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(
              color: checked
                  ? Colors.white.withOpacity(0.06)
                  : AppColors.accent.withOpacity(0.18),
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            !loaded
                ? '···'
                : checked
                    ? '已签到'
                    : '签到',
            style: TextStyle(
              color: checked
                  ? AppColors.textOnDarkMuted
                  : AppColors.accent,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _ModuleTabs extends StatelessWidget {
  const _ModuleTabs({
    required this.selected,
    required this.onSelected,
  });

  final DrawerModule selected;
  final ValueChanged<DrawerModule> onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          Expanded(child: _tab(context, '世界', LucideIcons.layoutGrid, DrawerModule.world)),
          const SizedBox(width: 8),
          Expanded(child: _tab(context, '发现', LucideIcons.compass, DrawerModule.discover)),
          const SizedBox(width: 8),
          Expanded(child: _tab(context, '我的', LucideIcons.user, DrawerModule.mine)),
        ],
      ),
    );
  }

  Widget _tab(BuildContext context, String label, IconData icon, DrawerModule module) {
    final isSelected = selected == module;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onSelected(module),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(
              color: isSelected ? Colors.white.withOpacity(0.35) : Colors.transparent,
              width: 1,
            ),
          ),
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: isSelected ? AppColors.textOnDark : AppColors.textOnDarkMuted,
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? AppColors.textOnDark : AppColors.textOnDarkMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DiscoverPanel extends StatefulWidget {
  const _DiscoverPanel({
    required this.isLoggedIn,
    this.currentUserId,
    this.onScenarioLaunch,
    this.scenarioShareLinkBuilder,
  });

  final bool isLoggedIn;
  final String? currentUserId;
  final ScenarioLaunchCallback? onScenarioLaunch;
  final String Function(String scenarioId)? scenarioShareLinkBuilder;

  @override
  State<_DiscoverPanel> createState() => _DiscoverPanelState();
}

class _DiscoverPanelState extends State<_DiscoverPanel> {
  List<StoreItem> _items = [];
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final items = await StoreApi.getStoreList();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent),
        ),
      );
    }

    if (_failed) {
      return Center(
        child: Text(
          '加载失败，下拉重试',
          style: TextStyle(color: AppColors.textOnDarkMuted, fontSize: 13),
        ),
      );
    }

    if (_items.isEmpty) {
      return Center(
        child: Text(
          '暂无内容',
          style: TextStyle(color: AppColors.textOnDarkMuted, fontSize: 13),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.accent,
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 0.72,
        ),
        itemCount: _items.length,
        itemBuilder: (context, index) {
          final item = _items[index];
          return _DiscoverItem(
            id: item.id,
            imageUrl: item.coverUrl,
            title: item.title,
            likes: item.likes,
            isLiked: item.isLiked,
            avatarUrl: item.avatarUrl,
            userName: item.authorName,
            isLoggedIn: widget.isLoggedIn,
            currentUserId: widget.currentUserId,
            onScenarioLaunch: widget.onScenarioLaunch,
            shareUrl: widget.scenarioShareLinkBuilder?.call(item.id),
            onDeleted: (id) {
              setState(() => _items = _items.where((e) => e.id != id).toList());
            },
            onLikeChanged: (id, liked, likes) {
              final itemIndex = _items.indexWhere((e) => e.id == id);
              if (itemIndex == -1) return;
              setState(() {
                final next = [..._items];
                next[itemIndex] = next[itemIndex].copyWith(
                  isLiked: liked,
                  likes: likes,
                );
                _items = next;
              });
            },
          );
        },
      ),
    );
  }
}

class _DiscoverItem extends StatelessWidget {
  const _DiscoverItem({
    required this.id,
    required this.imageUrl,
    required this.title,
    required this.likes,
    required this.avatarUrl,
    required this.userName,
    required this.isLoggedIn,
    this.currentUserId,
    this.onScenarioLaunch,
    this.shareUrl,
    this.onDeleted,
    this.onLikeChanged,
    this.isLiked = false,
  });

  final String id;
  final String imageUrl;
  final String title;
  final int likes;
  final bool isLiked;
  final String avatarUrl;
  final String userName;
  final bool isLoggedIn;
  final String? currentUserId;
  final ScenarioLaunchCallback? onScenarioLaunch;
  final String? shareUrl;
  final ScenarioDeletedCallback? onDeleted;
  final ScenarioLikeChangedCallback? onLikeChanged;

  void _showDetail(BuildContext context) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black.withOpacity(0.6),
      transitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Center(
          child: DiscoverDetailWindow(
            id: id,
            title: title,
            imageUrl: imageUrl,
            userName: userName,
            avatarUrl: avatarUrl,
            likes: likes,
            isLiked: isLiked,
            isLoggedIn: isLoggedIn,
            currentUserId: currentUserId,
            shareUrl: shareUrl,
            onLaunch: onScenarioLaunch,
            onDeleted: onDeleted,
            onLikeChanged: onLikeChanged,
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.95, end: 1.0).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            ),
            child: child,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _showDetail(context),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white.withOpacity(0.08)),
            borderRadius: BorderRadius.circular(8),
            color: Colors.white.withOpacity(0.02),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                  child: Image.network(
                    imageUrl,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: Colors.white.withOpacity(0.06),
                      child: Icon(
                        Icons.image_outlined,
                        color: AppColors.textOnDarkMuted,
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textOnDark,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              ClipOval(
                                child: Image.network(
                                  avatarUrl,
                                  width: 14,
                                  height: 14,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Icon(
                                    Icons.person,
                                    size: 14,
                                    color: Colors.white.withOpacity(0.2),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  userName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: AppColors.textOnDarkMuted,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 4),
                        Row(
                          children: [
                            Icon(
                              LucideIcons.heart,
                              size: 11,
                              color: isLiked ? const Color(0xFFE0554A) : AppColors.textOnDarkMuted,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              '$likes',
                              style: TextStyle(
                                color: AppColors.textOnDarkMuted,
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _MineSection { published, favorites, notifications }

class _MinePanel extends StatefulWidget {
  const _MinePanel({
    required this.isLoggedIn,
    this.currentUserId,
    this.onScenarioLaunch,
    this.scenarioShareLinkBuilder,
    this.onOpenPublished,
    this.onOpenFavorites,
    this.onOpenNotifications,
    this.onLogout,
    this.onRefreshProfile,
  });

  final bool isLoggedIn;
  final String? currentUserId;
  final ScenarioLaunchCallback? onScenarioLaunch;
  final String Function(String scenarioId)? scenarioShareLinkBuilder;
  final VoidCallback? onOpenPublished;
  final VoidCallback? onOpenFavorites;
  final VoidCallback? onOpenNotifications;
  final VoidCallback? onLogout;
  final VoidCallback? onRefreshProfile;
  @override
  State<_MinePanel> createState() => _MinePanelState();
}

class _MinePanelState extends State<_MinePanel> {
  UserProfile? _profile;
  List<StoreItem> _publishedItems = const [];
  List<AppNotification> _notifications = const [];

  _MineSection? _expandedSection;

  bool _loading = false;
  String? _error;

  bool _notificationsLoaded = false;
  bool _notificationsLoading = false;
  bool _markingAll = false;
  String? _notificationsError;


  int get _unreadCount => _notificationsLoaded
      ? _notifications.where((item) => !item.isRead).length
      : (_profile?.unreadNotifications ?? 0);

  bool get _hasUnread => _unreadCount > 0;

  @override
  void initState() {
    super.initState();
    if (widget.isLoggedIn) _loadData();
  }

  @override
  void didUpdateWidget(covariant _MinePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isLoggedIn && !oldWidget.isLoggedIn) {
      _loadData();
    } else if (!widget.isLoggedIn && oldWidget.isLoggedIn) {
      setState(() {
        _profile = null;
        _publishedItems = const [];
        _notifications = const [];
        _notificationsLoaded = false;
        _expandedSection = null;
        _error = null;
        _notificationsError = null;
      });
    }
  }

  Future<void> _loadData() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    UserProfile? profile;
    List<StoreItem>? published;
    Object? profileError;
    Object? publishedError;

    try {
      profile = await ProfileApi.getUserProfile();
    } catch (e) {
      profileError = e;
    }

    try {
      published = await StoreApi.getMyPublishedScripts();
    } catch (e) {
      publishedError = e;
    }

    if (!mounted) return;
    setState(() {
      if (profile != null) _profile = profile;
      if (published != null) _publishedItems = published;
      _loading = false;
      if (profileError != null && publishedError != null) {
        _error = '个人信息加载失败';
      }
    });
  }

  Future<void> _refreshAll() async {
    await _loadData();
    if (_notificationsLoaded || _expandedSection == _MineSection.notifications) {
      await _loadNotifications();
    }
  }

  void _toggleSection(_MineSection section) {
    final willOpen = _expandedSection != section;
    setState(() {
      _expandedSection = willOpen ? section : null;
    });

    if (willOpen && section == _MineSection.notifications && !_notificationsLoaded) {
      _loadNotifications();
    }
  }

  Future<void> _loadNotifications() async {
    if (_notificationsLoading) return;
    setState(() {
      _notificationsLoading = true;
      _notificationsError = null;
    });

    try {
      final page = await NotificationApi.getNotifications();
      if (!mounted) return;
      setState(() {
        _notifications = page.items;
        _notificationsLoaded = true;
        _notificationsLoading = false;
        if (_profile != null) {
          _profile = _profile!.copyWith(unreadNotifications: page.unreadCount);
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _notificationsLoading = false;
        _notificationsError = '通知加载失败';
      });
    }
  }

  Future<void> _markAllRead() async {
    if (_markingAll || !_hasUnread) return;
    setState(() => _markingAll = true);
    try {
      await NotificationApi.markAllRead();
      if (!mounted) return;
      setState(() {
        _notifications = _notifications
            .map((item) => item.copyWith(isRead: true))
            .toList();
        _markingAll = false;
        if (_profile != null) {
          _profile = _profile!.copyWith(unreadNotifications: 0);
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _markingAll = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('全部已读失败')),
      );
    }
  }

  Future<void> _openNotificationItem(AppNotification item) async {
    var nextItem = item;
    if (!item.isRead) {
      try {
        await NotificationApi.markRead(item.id);
        if (!mounted) return;
        final index = _notifications.indexWhere((e) => e.id == item.id);
        if (index >= 0) {
          setState(() {
            final next = [..._notifications];
            next[index] = next[index].copyWith(isRead: true);
            _notifications = next;
            nextItem = next[index];
            if (_profile != null) {
              _profile = _profile!.copyWith(unreadNotifications: _unreadCount);
            }
          });
        }
      } catch (_) {
        // fail silently
      }
    }
    if (!mounted) return;
    _openNotificationTarget(nextItem);
  }

  Widget _publishedCoverFallback({double size = 50}) {
    return Container(
      width: size,
      height: size,
      color: Colors.white.withOpacity(0.055),
      alignment: Alignment.center,
      child: Icon(
        Icons.image_outlined,
        color: AppColors.textOnDarkMuted,
        size: 18,
      ),
    );
  }

  String _publishedStatusText(String? status) {
    switch (status) {
      case 'active':
        return '已发布';
      case 'pending':
        return '审核中';
      case 'offline':
        return '已下架';
      default:
        return '作品详情';
    }
  }

  void _openScenarioDetail(StoreItem item) {
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black.withOpacity(0.6),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return Center(
          child: DiscoverDetailWindow(
            id: item.id,
            title: item.title,
            imageUrl: item.coverUrl,
            userName: item.authorName,
            avatarUrl: item.avatarUrl,
            likes: item.likes,
            isLiked: item.isLiked,
            isLoggedIn: widget.isLoggedIn,
            currentUserId: widget.currentUserId ?? _profile?.userId,
            shareUrl: widget.scenarioShareLinkBuilder?.call(item.id),
            onLaunch: widget.onScenarioLaunch,
            onDeleted: (id) {
              if (!mounted) return;
              setState(() {
                _publishedItems = _publishedItems.where((e) => e.id != id).toList();
              });
            },
            onLikeChanged: (id, liked, likes) {
              final index = _publishedItems.indexWhere((e) => e.id == id);
              if (index == -1 || !mounted) return;
              setState(() {
                final next = [..._publishedItems];
                next[index] = next[index].copyWith(
                  isLiked: liked,
                  likes: likes,
                );
                _publishedItems = next;
              });
            },
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            ),
            child: child,
          ),
        );
      },
    );
  }

  void _openNotificationTarget(AppNotification item) {
    final templateId = item.templateId?.trim();
    if (templateId == null || templateId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('这条通知没有关联作品，无法跳转')),
      );
      return;
    }

    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black.withOpacity(0.6),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return Center(
          child: DiscoverDetailWindow(
            id: templateId,
            title: item.templateTitle?.trim().isNotEmpty == true
                ? item.templateTitle!
                : '作品详情',
            imageUrl: item.coverUrl ?? '',
            userName: '',
            avatarUrl: '',
            likes: 0,
            isLoggedIn: widget.isLoggedIn,
            currentUserId: widget.currentUserId ?? _profile?.userId,
            shareUrl: widget.scenarioShareLinkBuilder?.call(templateId),
            onLaunch: widget.onScenarioLaunch,
            initialCommentId: item.locateCommentId,
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            ),
            child: child,
          ),
        );
      },
    );
  }

  String _formatTime(String value) {
    if (value.trim().isEmpty) return '';
    final parsed = DateTime.tryParse(value)?.toLocal();
    if (parsed == null) return value;
    final now = DateTime.now();
    final diff = now.difference(parsed);
    if (!diff.isNegative && diff.inMinutes < 1) return '刚刚';
    if (!diff.isNegative && diff.inHours < 1) return '${diff.inMinutes}分钟前';
    if (!diff.isNegative && diff.inDays < 1) return '${diff.inHours}小时前';
    if (!diff.isNegative && diff.inDays < 7) return '${diff.inDays}天前';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(parsed.month)}-${two(parsed.day)}';
  }

  String _actionText(AppNotification item) {
    final provided = item.raw['action_text'] ?? item.raw['message'];
    if (provided != null && provided.toString().trim().isNotEmpty) {
      return provided.toString();
    }
    switch (item.type.toLowerCase()) {
      case 'reply':
      case 'comment_reply':
      case 'reply_comment':
        return '回复了你的评论';
      case 'comment':
      case 'scenario_comment':
        return '评论了你的作品';
      case 'comment_like':
      case 'like_comment':
        return '赞了你的评论';
      case 'scenario_like':
      case 'like_scenario':
        return '赞了你的作品';
      default:
        return '与你互动';
    }
  }

  Widget _sectionAnimation({
    required _MineSection section,
    required Widget child,
  }) {
    final expanded = _expandedSection == section;
    return ClipRect(
      child: AnimatedSize(
        duration: const Duration(milliseconds: 230),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: expanded ? child : const SizedBox(width: double.infinity),
      ),
    );
  }

  Widget _buildPublishedInline() {
    if (_loading && _publishedItems.isEmpty) {
      return const _MineInlineLoading();
    }
    if (_publishedItems.isEmpty) {
      return const _MineInlineEmpty(text: '还没有发布作品');
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 2, 2, 8),
      child: Column(
        children: [
          for (int i = 0; i < _publishedItems.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                indent: 58,
                color: Colors.white.withOpacity(0.045),
              ),
            _buildPublishedRow(_publishedItems[i]),
          ],
        ],
      ),
    );
  }

  Widget _buildPublishedRow(StoreItem item) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openScenarioDetail(item),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: item.coverUrl.isNotEmpty
                    ? Image.network(
                        item.coverUrl,
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            _publishedCoverFallback(size: 48),
                      )
                    : _publishedCoverFallback(size: 48),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textOnDark,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          _publishedStatusText(item.status),
                          style: TextStyle(
                            color: AppColors.textOnDarkMuted,
                            fontSize: 10.5,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Icon(
                          LucideIcons.heart,
                          size: 11.5,
                          color: item.isLiked
                              ? const Color(0xFFE0554A)
                              : AppColors.textOnDarkMuted,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          '${item.likes}',
                          style: TextStyle(
                            color: AppColors.textOnDarkMuted,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(
                LucideIcons.chevronRight,
                size: 15,
                color: AppColors.textOnDarkMuted.withOpacity(0.45),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFavoritesInline() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(44, 4, 8, 14),
      child: Text(
        '收藏列表接口还没提供。接入后直接在这里显示收藏作品，不再弹新窗口。',
        style: TextStyle(
          color: AppColors.textOnDarkMuted,
          fontSize: 11.5,
          height: 1.5,
        ),
      ),
    );
  }

  Widget _buildNotificationsInline() {
    if (_notificationsLoading && !_notificationsLoaded) {
      return const _MineInlineLoading();
    }
    if (_notificationsError != null && !_notificationsLoaded) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(44, 4, 8, 12),
        child: GestureDetector(
          onTap: _loadNotifications,
          child: Text(
            '$_notificationsError，点击重试',
            style: TextStyle(
              color: AppColors.textOnDarkMuted,
              fontSize: 11.5,
            ),
          ),
        ),
      );
    }
    if (_notifications.isEmpty) {
      return const _MineInlineEmpty(text: '暂无新通知');
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 2, 8),
      child: Column(
        children: [
          if (_hasUnread)
            Padding(
              padding: const EdgeInsets.fromLTRB(44, 0, 4, 2),
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _markingAll ? null : _markAllRead,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    _markingAll ? '处理中…' : '全标已读',
                    style: const TextStyle(
                      color: AppColors.accent,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          for (int i = 0; i < _notifications.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                indent: 52,
                color: Colors.white.withOpacity(0.045),
              ),
            _buildNotificationRow(_notifications[i]),
          ],
        ],
      ),
    );
  }

  Widget _buildNotificationRow(AppNotification item) {
    final avatarUrl = item.actor.avatarUrl;
    final coverUrl = item.coverUrl ?? '';
    return Material(
      color: item.isRead ? Colors.transparent : Colors.white.withOpacity(0.018),
      child: InkWell(
        onTap: () => _openNotificationItem(item),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  ClipOval(
                    child: SizedBox(
                      width: 38,
                      height: 38,
                      child: avatarUrl.isEmpty
                          ? _notificationAvatarFallback()
                          : Image.network(
                              avatarUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  _notificationAvatarFallback(),
                            ),
                    ),
                  ),
                  if (!item.isRead)
                    Positioned(
                      right: -1,
                      top: -1,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Color(0xFFE0554A),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.actor.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textOnDark,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Text(
                          _formatTime(item.createdAt),
                          style: TextStyle(
                            color: AppColors.textOnDarkMuted.withOpacity(0.7),
                            fontSize: 9.5,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _actionText(item),
                      style: TextStyle(
                        color: AppColors.textOnDarkMuted,
                        fontSize: 11,
                      ),
                    ),
                    if ((item.content ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        item.content!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textOnDark,
                          fontSize: 11.5,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (coverUrl.isNotEmpty && (item.templateId ?? '').isNotEmpty) ...[
                const SizedBox(width: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: Image.network(
                    coverUrl,
                    width: 42,
                    height: 42,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 42,
                      height: 42,
                      color: Colors.white.withOpacity(0.05),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _notificationAvatarFallback() {
    return Container(
      color: Colors.white.withOpacity(0.055),
      alignment: Alignment.center,
      child: Icon(
        Icons.person_rounded,
        size: 18,
        color: AppColors.textOnDarkMuted,
      ),
    );
  }



  Future<void> _openRedeem() async {
    final success = await MineDialogs.redeem(context);
    if (!mounted || !success) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: Color(0xFF161616),
        behavior: SnackBarBehavior.floating,
        content: Text(
          '兑换成功',
          style: TextStyle(color: AppColors.textOnDark),
        ),
      ),
    );
    await _loadData();
    
    // 【修改这行】不再调用 onCheckin，改为调用专用的刷新资料回调
    widget.onRefreshProfile?.call(); 
  }

  Future<void> _openFeedback() async {
    final success = await MineDialogs.feedback(context);
    if (!mounted || !success) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: Color(0xFF161616),
        behavior: SnackBarBehavior.floating,
        content: Text(
          '反馈已提交',
          style: TextStyle(color: AppColors.textOnDark),
        ),
      ),
    );
  }

  Future<void> _logout() async {
    final confirmed = await MineDialogs.confirmLogout(context);
    if (!mounted || !confirmed) return;
    widget.onLogout?.call();
  }

  Widget _buildPrimarySection() {
    return Column(
      children: [
        _MineListItem(
          icon: LucideIcons.bookOpen,
          title: '已发布的作品',
          trailingText: _loading && _publishedItems.isEmpty
              ? '…'
              : _publishedItems.length.toString(),
          expanded: _expandedSection == _MineSection.published,
          onTap: () => _toggleSection(_MineSection.published),
        ),
        _sectionAnimation(
          section: _MineSection.published,
          child: _buildPublishedInline(),
        ),
        const SizedBox(height: 4),
        _MineListItem(
          icon: LucideIcons.bookmark,
          title: '收藏的作品',
          expanded: _expandedSection == _MineSection.favorites,
          onTap: () => _toggleSection(_MineSection.favorites),
        ),
        _sectionAnimation(
          section: _MineSection.favorites,
          child: _buildFavoritesInline(),
        ),
        const SizedBox(height: 4),
        _MineListItem(
          icon: Icons.notifications_none_rounded,
          title: '消息通知',
          badgeCount: _unreadCount,
          expanded: _expandedSection == _MineSection.notifications,
          onTap: () => _toggleSection(_MineSection.notifications),
        ),
        _sectionAnimation(
          section: _MineSection.notifications,
          child: _buildNotificationsInline(),
        ),
      ],
    );
  }

  Widget _buildBottomTools() {
    Widget pair(_MineQuickAction left, _MineQuickAction right) {
      return Row(
        children: [
          Expanded(child: left),
          const SizedBox(width: 8),
          Expanded(child: right),
        ],
      );
    }

    return Column(
      children: [
        pair(
          _MineQuickAction(
            icon: LucideIcons.megaphone,
            title: '公告',
            onTap: () => MineDialogs.announcements(context),
          ),
          _MineQuickAction(
            icon: LucideIcons.ticketCheck,
            title: '兑换码',
            onTap: _openRedeem,
          ),
        ),
        const SizedBox(height: 8),
        pair(
          _MineQuickAction(
            icon: LucideIcons.braces,
            title: 'API 设置',
            onTap: () => MineDialogs.apiSettingsPending(context),
          ),
          _MineQuickAction(
            icon: LucideIcons.circleHelp,
            title: '帮助反馈',
            onTap: _openFeedback,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isLoggedIn) {
      return Center(
        child: Text(
          '请先登录',
          style: TextStyle(
            color: AppColors.textOnDarkMuted,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refreshAll,
            color: AppColors.accent,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              children: [
                if (_loading && _profile == null && _publishedItems.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: LinearProgressIndicator(
                      minHeight: 1.5,
                      color: AppColors.accent,
                      backgroundColor: Colors.transparent,
                    ),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: GestureDetector(
                      onTap: _loadData,
                      child: Text(
                        '$_error，点击重试',
                        style: TextStyle(
                          color: AppColors.textOnDarkMuted,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),

                _buildPrimarySection(),

              ],
            ),
          ),
        ),

        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
          child: _buildBottomTools(),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
          child: _MineLogoutButton(onTap: _logout),
        ),
      ],
    );
  }

}

class _MineInlineLoading extends StatelessWidget {
  const _MineInlineLoading();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(44, 10, 8, 14),
      child: Align(
        alignment: Alignment.centerLeft,
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 1.6,
            color: AppColors.textOnDarkMuted,
          ),
        ),
      ),
    );
  }
}

class _MineInlineEmpty extends StatelessWidget {
  const _MineInlineEmpty({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(44, 8, 8, 14),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          style: TextStyle(
            color: AppColors.textOnDarkMuted,
            fontSize: 11.5,
          ),
        ),
      ),
    );
  }
}

class _MineListItem extends StatelessWidget {
  const _MineListItem({
    required this.icon,
    required this.title,
    this.trailingText,
    this.badgeCount = 0,
    this.expanded = false,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String? trailingText;
  final int badgeCount;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 13),
          color: expanded ? Colors.white.withOpacity(0.025) : Colors.transparent,
          child: Row(
            children: [
              Icon(icon, size: 18, color: AppColors.textOnDarkMuted),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textOnDark,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (trailingText != null)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    trailingText!,
                    style: TextStyle(
                      color: AppColors.textOnDarkMuted,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              if (badgeCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE0554A),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    badgeCount > 99 ? '99+' : '$badgeCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      height: 1.1,
                    ),
                  ),
                ),
              AnimatedRotation(
                turns: expanded ? 0.25 : 0,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                child: Icon(
                  LucideIcons.chevronRight,
                  size: 16,
                  color: AppColors.textOnDarkMuted.withOpacity(0.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


class _MineQuickAction extends StatelessWidget {
  const _MineQuickAction({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.highlighted = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool highlighted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withOpacity(0.018),
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            border: Border.all(
              color: highlighted
                  ? AppColors.accent.withOpacity(0.20)
                  : Colors.white.withOpacity(0.055),
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 16,
                color: highlighted
                    ? AppColors.accent
                    : AppColors.textOnDarkMuted,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textOnDark,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: TextStyle(
                          color: highlighted
                              ? AppColors.accent
                              : AppColors.textOnDarkMuted,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MineLogoutButton extends StatelessWidget {
  const _MineLogoutButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          height: 42,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                LucideIcons.logOut,
                size: 15,
                color: const Color(0xFFE7685E).withOpacity(0.86),
              ),
              const SizedBox(width: 7),
              Text(
                '退出登录',
                style: TextStyle(
                  color: const Color(0xFFE7685E).withOpacity(0.90),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WorldItem extends StatelessWidget {
  const _WorldItem({
    required this.game,
    required this.selected,
    required this.onTap,
    required this.onDetailTap,
  });

  final GameData game;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onDetailTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: Image.network(
                  game.imageUrl,
                  width: 52,
                  height: 52,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 52,
                    height: 52,
                    color: Colors.white.withOpacity(0.06),
                    child: Icon(
                      Icons.image_outlined,
                      size: 20,
                      color: AppColors.textOnDarkMuted,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 5),
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                    border: Border.all(
                      color: selected ? Colors.white.withOpacity(0.35) : Colors.transparent,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              game.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.textOnDark,
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              game.category,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.textOnDarkMuted,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: onDetailTap,
                        behavior: HitTestBehavior.opaque,
                        child: Container(
                          padding: const EdgeInsets.only(left: 10, right: 4, top: 4, bottom: 4),
                          child: Icon(
                            LucideIcons.moreHorizontal,
                            size: 16,
                            color: AppColors.textOnDarkMuted.withOpacity(0.6),
                          ),
                        ),
                      ),
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

class _BottomActionButton extends StatelessWidget {
  const _BottomActionButton({
    super.key, // <--- 补充这一行
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.accent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 52,
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: const Color.fromARGB(255, 6, 6, 6),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: Color.fromARGB(255, 12, 12, 12),
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}