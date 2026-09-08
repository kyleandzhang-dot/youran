part of '../novel_sheets.dart';

// ============================================================================
// 主角资料页
//
// 主页头像入口：showNovelHostProfileSheet(...)
// 与 NPC 角色中心彻底分离；模式只读取 controller.desktopMode。
// 页面主体继续遵守统一边距：
//   mobile  -> left 10 / right 12 / maxWidth 560
//   desktop -> left 46 / right 54 / maxWidth 1440
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
        final compact = !desktopMode;
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
                              : _CharacterShowcaseStage(
                                  controller: widget.controller,
                                  character: host,
                                  summary: _summaryOf(host),
                                  identity: _identityOf(host),
                                  compact: compact,
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
