part of '../novel_sheets.dart';

// ============================================================================
// 主角资料页
//
// 主页头像入口：showNovelHostProfileSheet(...)
// 与 NPC 角色中心分离，显示模式只读取 controller.desktopMode。
//
// 页面主体统一边距：
//   mobile  -> left 10 / right 12 / maxWidth 560
//   desktop -> left 46 / right 54 / maxWidth 1440
//
// 手机继续使用紧凑人物展示；电脑使用真正的左右分栏：
//   左侧大立绘 / 右侧完整资料 + 立绘编辑。
// ============================================================================

Future<void> showNovelHostProfileSheet(
  BuildContext context,
  NovelGameController controller,
) async {
  await _runNovelPageOnce('host-profile', () async {
    await _showNovelArchivePage<void>(
      context,
      child: _NovelHostProfilePage(controller: controller),
    );
  });
}

class _NovelHostProfilePage extends StatefulWidget {
  const _NovelHostProfilePage({required this.controller});

  final NovelGameController controller;

  @override
  State<_NovelHostProfilePage> createState() => _NovelHostProfilePageState();
}

class _NovelHostProfilePageState extends State<_NovelHostProfilePage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_refresh());
    });
  }

  Future<void> _refresh() async {
    try {
      await widget.controller.refreshCharacterStatus();
    } catch (_) {
      // 资料页允许直接使用 controller 已有快照；刷新失败不打断页面。
    }
  }

  String _identityOf(NovelCharacter character) {
    return stringValue(
      character.status['identity'] ??
          character.persona['identity'] ??
          character.status['occupation'] ??
          character.persona['occupation'],
    ).trim();
  }

  String _summaryOf(NovelCharacter character) {
    for (final value in <dynamic>[
      character.status['description'],
      character.persona['description'],
      character.status['background'],
      character.persona['background'],
      character.status['personality'],
      character.persona['personality'],
    ]) {
      final text = stringValue(value).trim();
      if (text.isNotEmpty) return text;
    }
    return '你的故事仍在继续。';
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        widget.controller,
        novelDisplayMode,
      ]),
      builder: (context, _) {
        final desktopMode = widget.controller.desktopMode;
        final leftInset = desktopMode ? 46.0 : 10.0;
        final rightInset = desktopMode ? 54.0 : 12.0;
        final contentMaxWidth = desktopMode ? 1440.0 : 560.0;
        final topInset = desktopMode ? 14.0 : 4.0;
        final bottomInset = desktopMode ? 12.0 : 4.0;
        final host = widget.controller.protagonist;

        return _CharacterArchiveBackground(
          controller: widget.controller,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: contentMaxWidth),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      leftInset,
                      topInset,
                      rightInset,
                      bottomInset,
                    ),
                    child: Column(
                      children: <Widget>[
                        _HostProfileHeader(
                          onClose: () => Navigator.of(context).pop(),
                        ),
                        Expanded(
                          child: host == null
                              ? const Center(
                                  child: Text(
                                    '正在读取主角资料…',
                                    style: TextStyle(
                                      color: _archiveMuted,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                )
                              : desktopMode
                                  ? _HostProfileDesktopStage(
                                      controller: widget.controller,
                                      character: host,
                                      summary: _summaryOf(host),
                                      identity: _identityOf(host),
                                    )
                                  : _CharacterShowcaseStage(
                                      controller: widget.controller,
                                      character: host,
                                      summary: _summaryOf(host),
                                      identity: _identityOf(host),
                                      compact: true,
                                    ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _HostProfileHeader extends StatelessWidget {
  const _HostProfileHeader({this.onClose});

  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      child: Row(
        children: <Widget>[
          const Expanded(
            child: Text(
              '主角资料',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _archiveText,
                fontSize: 20,
                height: 1,
                fontWeight: FontWeight.w800,
                letterSpacing: 2.2,
              ),
            ),
          ),
          if (onClose != null)
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onClose,
                borderRadius: BorderRadius.circular(99),
                child: const Padding(
                  padding: EdgeInsets.all(10),
                  child: Icon(
                    Icons.close_rounded,
                    size: 19,
                    color: _archiveTextSoft,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 主角资料电脑模式：真正的宽屏左右分栏，不再只是把手机版 Stage 放大。
class _HostProfileDesktopStage extends StatefulWidget {
  const _HostProfileDesktopStage({
    required this.controller,
    required this.character,
    required this.summary,
    required this.identity,
  });

  final NovelGameController controller;
  final NovelCharacter character;
  final String summary;
  final String identity;

  @override
  State<_HostProfileDesktopStage> createState() =>
      _HostProfileDesktopStageState();
}

class _HostProfileDesktopStageState extends State<_HostProfileDesktopStage> {
  String _previewPortraitUrl = '';

  String _characterKey(NovelCharacter character) =>
      character.id.trim().isNotEmpty
          ? character.id.trim()
          : character.name.trim();

  String get _portraitUrl {
    final preview = _previewPortraitUrl.trim();
    if (preview.isNotEmpty) return preview;
    final portrait = widget.character.portraitUrl.trim();
    if (portrait.isNotEmpty) return portrait;
    return widget.character.avatarUrl.trim();
  }

  @override
  void didUpdateWidget(covariant _HostProfileDesktopStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_characterKey(oldWidget.character) !=
        _characterKey(widget.character)) {
      _previewPortraitUrl = '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final fallbackAsset = widget.character.gender.trim() == '男'
        ? 'assets/images/portrait_male.png'
        : 'assets/images/portrait_female.webp';

    return LayoutBuilder(
      builder: (context, constraints) {
        final infoWidth = (constraints.maxWidth * .34)
            .clamp(360.0, 460.0)
            .toDouble();
        final portraitMaxWidth = math.max(
          420.0,
          constraints.maxWidth - infoWidth - 34.0,
        );

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(
              child: Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  Positioned.fill(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: math.min(780.0, portraitMaxWidth),
                        ),
                        child: FractionallySizedBox(
                          heightFactor: .98,
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 260),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            child: NovelArtwork(
                              key: ValueKey<String>(
                                'host-desktop-${_portraitUrl}-${widget.character.name}',
                              ),
                              url: CdnUtil.resize(_portraitUrl, width: 1000),
                              assetCandidates: <String>[
                                fallbackAsset,
                                'assets/images/portrait_female.webp',
                                'assets/images/portrait_male.png',
                              ],
                              fit: BoxFit.contain,
                              alignment: Alignment.bottomCenter,
                              fallbackText: '',
                              fallbackIcon: Icons.person_outline_rounded,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 34),
            Container(
              width: infoWidth,
              padding: const EdgeInsets.only(left: 24, top: 18, bottom: 18),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(
                    color: _archiveLine.withOpacity(.75),
                    width: .8,
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.only(right: 4, bottom: 14),
                      child: _CharacterShowcaseInfo(
                        character: widget.character,
                        summary: widget.summary,
                        identity: widget.identity,
                        relationLabel: '主角',
                        compact: false,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _CharacterQuickPortraitEditor(
                    controller: widget.controller,
                    character: widget.character,
                    compact: false,
                    onPortraitChanged: (portraitUrl) {
                      if (!mounted) return;
                      setState(() => _previewPortraitUrl = portraitUrl);
                    },
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
