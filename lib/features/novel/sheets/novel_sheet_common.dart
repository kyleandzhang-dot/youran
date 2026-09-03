part of '../novel_sheets.dart';

// ============================================================================
// Sheet 公共层（所有子页面共享）
// 页面入口 / 对外入口：
//   - _showNovelSheet / _showNovelArchivePage / _showNovelEndDrawer
//   - _SheetFrame / _SheetScaffold / _GameStyleBackdrop 等公共组件
// 其余以下划线 `_` 开头的类型/方法均为该页面内部实现或共享私有实现。
// ============================================================================

/// 防止背包 / 角色 / 经历 / 主角资料被连续点击后重复 push。
/// 锁从开始打开一直保持到对应页面真正关闭。
final Set<String> _novelSingleOpenPages = <String>{};

Future<void> _runNovelPageOnce(
  String pageKey,
  Future<void> Function() action,
) async {
  if (!_novelSingleOpenPages.add(pageKey)) return;
  try {
    await action();
  } finally {
    _novelSingleOpenPages.remove(pageKey);
  }
}

Future<T?> _showNovelSheet<T>(
  BuildContext context, {
  required Widget child,
  double heightFactor = .76,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭面板',
    barrierColor: Colors.black.withOpacity(.80),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (dialogContext, _, __) {
      final media = MediaQuery.of(dialogContext);
      final maxHeight =
          (media.size.height * heightFactor).clamp(360.0, 650.0).toDouble();
      return Material(
        color: Colors.transparent,
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 420,
                  maxHeight: maxHeight,
                ),
                child: _SheetFrame(child: child),
              ),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: .965, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}


Future<T?> _showNovelArchivePage<T>(
  BuildContext context, {
  required Widget child,
}) {
  return Navigator.of(context).push<T>(
    PageRouteBuilder<T>(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 260),
      reverseTransitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (routeContext, animation, secondaryAnimation) {
        return Scaffold(
          // 将深色背景换为纯白，填满上下间隙
          backgroundColor: const Color(0xFFFFFFFF),
          // 移除 SafeArea，将安全区处理下放到 _GameStyleBackdrop 和 _CharacterArchiveBackground 中
          body: child,
        );
      },
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(curved),
          child: FadeTransition(
            opacity: curved,
            child: child,
          ),
        );
      },
    ),
  );
}

class _ArchivePageScaffold extends StatelessWidget {
  const _ArchivePageScaffold({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    const pageBackground = Color(0xFF151515);
    const textPrimary = Color(0xFFF2F2F2);
    const textMuted = Color(0xFF969696);

    return Scaffold(
      backgroundColor: pageBackground,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Container(
              color: Colors.transparent,
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => Navigator.of(context).pop(),
                      borderRadius: BorderRadius.circular(10),
                      child: const SizedBox(
                        width: 38,
                        height: 38,
                        child: Icon(
                          Icons.close_rounded,
                          size: 20,
                          color: textMuted,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 820),
                  child: SizedBox.expand(child: child),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArchiveEmptyState extends StatelessWidget {
  const _ArchiveEmptyState({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF929292),
            fontSize: 12.5,
            height: 1.5,
          ),
        ),
      ),
    );
  }
}
/// 从右侧滑出的设置抽屉。
/// 视觉规则与左侧 GameDrawer 镜像统一：
/// - 直角
/// - 抽屉自身毛玻璃
/// - 10% 白色透明叠层
/// - 内侧一条细分隔线
/// - 抽屉外主游戏画面只压暗，不做全屏模糊
Future<T?> _showNovelEndDrawer<T>(
  BuildContext context, {
  required Widget child,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭面板',

    // 对齐左侧 Drawer 打开后的主背景压暗感。
    // 只作用在抽屉外部，不会把主场景做毛玻璃。
    barrierColor: Colors.black.withOpacity(.78),

    transitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (dialogContext, _, __) {
      final media = MediaQuery.of(dialogContext);

      // 与左侧 GameDrawer 完全一致：屏幕宽度 82%，最大 300。
      final width = math.min(media.size.width * .82, 300.0);

      return Align(
        alignment: Alignment.centerRight,
        child: SizedBox(
          width: width,
          height: media.size.height,
          child: Material(
            color: Colors.transparent,
            child: _EndDrawerFrame(child: child),
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );

      // 右侧镜像左侧抽屉：水平滑入，不缩放、不做弹窗式动画。
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      );
    },
  );
}

class _EndDrawerFrame extends StatelessWidget {
  const _EndDrawerFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // 非常关键：
    // 用 ClipRect 把 BackdropFilter 严格限制在“右侧抽屉本身”的矩形范围内。
    // Chrome/Web 下如果不裁剪，BackdropFilter 可能让整个主游戏画面看起来都被模糊。
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
        child: Container(
          // 与左侧 GameDrawer 保持一致：
          // 使用轻微的白色透明叠层，而不是更重的黑色压暗层。
          color: const Color.fromARGB(255, 253, 253, 253).withOpacity(0.1),
          child: SafeArea(child: child),
        ),
      ),
    );
  }
}

class _SheetFrame extends StatelessWidget {
  const _SheetFrame({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
        child: Container(
          decoration: BoxDecoration(
            color: NovelPalette.panel,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: Colors.white.withOpacity(.08),
              width: 1,
            ),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 28,
                offset: Offset(0, 14),
              ),
            ],
          ),
          child: SafeArea(top: false, child: child),
        ),
      ),
    );
  }
}

class _SheetScaffold extends StatelessWidget {
  const _SheetScaffold({
    required this.title,
    required this.subtitle,
    required this.child,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: const TextStyle(
                        color: NovelPalette.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (subtitle.trim().isNotEmpty) ...<Widget>[
                      const SizedBox(height: 5),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: NovelPalette.muted,
                          fontSize: 11,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...<Widget>[
                const SizedBox(width: 10),
                trailing!,
                const SizedBox(width: 6),
              ],
              _PanelCloseButton(onTap: () => Navigator.of(context).pop()),
            ],
          ),
        ),
        Divider(
          height: 1,
          thickness: 1,
          color: Colors.white.withOpacity(.05),
        ),
        Expanded(child: child),
      ],
    );
  }
}

class _PanelCloseButton extends StatelessWidget {
  const _PanelCloseButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: const SizedBox(
          width: 32,
          height: 32,
          child: Icon(
            Icons.close_rounded,
            size: 18,
            color: NovelPalette.muted,
          ),
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.number,
    this.assetIconPath = '',
    this.highlighted = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final int? number;
  final String assetIconPath;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
          decoration: BoxDecoration(
            color: highlighted
                ? NovelPalette.accent.withOpacity(.055)
                : Colors.white.withOpacity(.018),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: highlighted
                  ? NovelPalette.accent.withOpacity(.25)
                  : Colors.white.withOpacity(.07),
            ),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: highlighted
                      ? NovelPalette.accent.withOpacity(.10)
                      : Colors.white.withOpacity(.025),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: highlighted
                        ? NovelPalette.accent.withOpacity(.16)
                        : Colors.white.withOpacity(.055),
                  ),
                ),
                child: number != null
                    ? Text(
                        '$number',
                        style: const TextStyle(
                          color: NovelPalette.accent,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      )
                    : assetIconPath.trim().isNotEmpty
                        ? Image.asset(
                            assetIconPath,
                            width: 18,
                            height: 18,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => Icon(
                              icon,
                              color: NovelPalette.accent,
                              size: 16,
                            ),
                          )
                        : Icon(icon, color: NovelPalette.accent, size: 16),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: const TextStyle(
                        color: NovelPalette.text,
                        fontSize: 13,
                        height: 1.4,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (subtitle.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: NovelPalette.muted,
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.chevron_right_rounded,
                color: NovelPalette.muted,
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
const Color _archiveBackground = Color(0xFFFFFFFF);
const Color _archiveSurface = Color(0xFFFFFFFF);
const Color _archiveSurfaceSoft = Color(0xFFF6F7F6);
const Color _archiveText = Color(0xFF1F2420);
const Color _archiveTextSoft = Color(0xFF404640);
const Color _archiveMuted = Color(0xFF707770);
const Color _archiveMutedSoft = Color(0xFF969C96);
const Color _archiveLine = Color(0xFFE4E8E4);
const Color _archiveAccent = NovelPalette.accentDeep;
const Color _archiveThemeGreen = NovelPalette.accent;

// 经历页与人物 / 背包 / 设置统一引用 NovelPalette 主绿色；正文和结构线保持中性灰。
const Color _journeyMatcha = NovelPalette.accent;
const Color _journeyMatchaDeep = NovelPalette.accentDeep;
const Color _journeyMatchaSoft = NovelPalette.accentSoft;
const Color _journeyMatchaLine = NovelPalette.accentLine;


// ============================================================================
// Game archive visual system
// 角色 / 角色档案 / 背包 / 经历共用一套“深色场景 + 香槟金信息层”视觉语言。
// 只借鉴游戏信息层级，不照搬参考游戏的货币栏、功能大厅等无关结构。
// ============================================================================

class _GameStyleBackdrop extends StatelessWidget {
  const _GameStyleBackdrop({
    required this.controller,
    required this.child,
    this.embedded = false,
    this.overlayColor = const Color(0x42000000),
    this.lightTheme = false,
  });

  final NovelGameController controller;
  final Widget child;
  final bool embedded;
  final Color overlayColor;
  final bool lightTheme;

  @override
  Widget build(BuildContext context) {
    // 独立全屏打开时，由它负责提供安全区
    final content = embedded
        ? _NovelPrimaryTabSafeContent(child: child)
        : SafeArea(child: child);

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        if (lightTheme) ...<Widget>[
          const ColoredBox(color: _archiveBackground),
        ] else ...<Widget>[
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -0.02),
                radius: 1.08,
                colors: <Color>[
                  Color(0xFF272B32),
                  Color(0xFF191C22),
                  Color(0xFF090B0F),
                ],
                stops: <double>[0, .58, 1],
              ),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[
                  Color(0x26000000),
                  Colors.transparent,
                  Color(0x3D000000),
                ],
                stops: <double>[0, .46, 1],
              ),
            ),
          ),
        ],
        content,
      ],
    );
  }
}



class _GameStyleHeader extends StatelessWidget {
  const _GameStyleHeader({
    required this.title,
    required this.english,
    this.onClose,
    this.lightTheme = false,
  });

  final String title;
  final String english;
  final VoidCallback? onClose;
  final bool lightTheme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 13, 12, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: TextStyle(
                    color: lightTheme
                        ? _archiveText
                        : const Color(0xFFF5F7FA),
                    fontSize: 23,
                    height: 1,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                    shadows: lightTheme
                        ? const <Shadow>[]
                        : const <Shadow>[
                            Shadow(
                              color: Color(0x88000000),
                              blurRadius: 8,
                              offset: Offset(0, 2),
                            ),
                          ],
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  english,
                  style: TextStyle(
                    color: lightTheme
                        ? _archiveMutedSoft
                        : const Color(0x99DCE1E7),
                    fontSize: 8.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2.2,
                  ),
                ),
              ],
            ),
          ),
          if (onClose != null) ...<Widget>[
            _GameStyleHeaderIcon(
              tooltip: '关闭',
              icon: Icons.close_rounded,
              onTap: onClose,
              lightTheme: lightTheme,
            ),
          ],
        ],
      ),
    );
  }
}

class _GameStyleHeaderIcon extends StatelessWidget {
  const _GameStyleHeaderIcon({
    required this.tooltip,
    required this.icon,
    required this.onTap,
    this.lightTheme = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onTap;
  final bool lightTheme;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          // 显式覆盖 Flutter Theme 默认交互色，避免悬浮/点击时继承全局紫色。
          hoverColor: lightTheme
              ? const Color(0x0A000000)
              : const Color(0x12FFFFFF),
          splashColor: lightTheme
              ? const Color(0x12000000)
              : const Color(0x18FFFFFF),
          highlightColor: Colors.transparent,
          child: SizedBox(
            width: 42,
            height: 42,
            child: Icon(
              icon,
              size: 22,
              color: onTap == null
                  ? (lightTheme
                      ? _archiveMutedSoft
                      : const Color(0x667D7565))
                  : (lightTheme
                      ? _archiveTextSoft
                      : const Color(0xFFE2E6EB)),
            ),
          ),
        ),
      ),
    );
  }
}

class _GameStyleSectionTitle extends StatelessWidget {
  const _GameStyleSectionTitle({
    required this.title,
    this.count,
    this.lightTheme = false,
  });

  final String title;
  final int? count;
  final bool lightTheme;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Text(
          title,
          style: TextStyle(
            color: lightTheme
                ? _archiveTextSoft
                : const Color(0xFFE7EAEE),
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: .6,
          ),
        ),
        if (count != null) ...<Widget>[
          const SizedBox(width: 7),
          Text(
            '$count',
            style: TextStyle(
              color: lightTheme
                  ? _archiveMuted
                  : const Color(0xFF827B6D),
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            height: .7,
            color: lightTheme
                ? _archiveLine
                : const Color(0x2EFFFFFF),
          ),
        ),
      ],
    );
  }
}
