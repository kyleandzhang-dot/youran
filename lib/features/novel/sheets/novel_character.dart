part of '../novel_sheets.dart';

// ============================================================================

const Color _characterHighStar = Color(0xFFE75B62);
// 深色队伍 / 结缘 / 图鉴 / 伙伴养成页
// 页面入口 / 对外入口：
//   - NovelTeamTab
//
// 绿白“角色 / 人物档案”页已拆分到 novel_characters.dart。
// ============================================================================

/// 队伍、结缘、图鉴与伙伴养成页。
class NovelTeamTab extends StatelessWidget {
  const NovelTeamTab({
    super.key,
    required this.controller,
  });

  final NovelGameController controller;

  @override
  Widget build(BuildContext context) {
    return _NovelCharacterHub(
      controller: controller,
      embedded: true,
    );
  }
}

// ============================================================================
// 游戏化角色中心
// ============================================================================

const Color _characterInk = Color(0xFF090E1A);
const Color _characterInkSoft = Color(0xFF111A2C);
const Color _characterBlue = Color(0xFF506FEF);
const Color _characterBlueBright = Color(0xFF7D98FF);
const Color _characterGold = Color(0xFFC9B778);
const Color _characterGoldSoft = Color(0xFF86794D);
const Color _characterText = Color(0xFFF2F0E8);
const Color _characterTextSoft = Color(0xFFB9C0D0);
const Color _characterTextMuted = Color(0xFF737C91);


void _showCharacterFloatingNotice(BuildContext context, String message) {
  final text = message.trim();
  if (text.isEmpty) return;
  ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;

  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (overlayContext) => _CharacterFloatingNotice(
      message: text,
      onFinished: () {
        if (entry.mounted) entry.remove();
      },
    ),
  );
  overlay.insert(entry);
}

class _CharacterFloatingNotice extends StatefulWidget {
  const _CharacterFloatingNotice({
    required this.message,
    required this.onFinished,
  });

  final String message;
  final VoidCallback onFinished;

  @override
  State<_CharacterFloatingNotice> createState() => _CharacterFloatingNoticeState();
}

class _CharacterFloatingNoticeState extends State<_CharacterFloatingNotice>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<double> _lift;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _opacity = TweenSequence<double>(<TweenSequenceItem<double>>[
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: 0, end: 1)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 18,
      ),
      TweenSequenceItem<double>(tween: ConstantTween<double>(1), weight: 52),
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: 1, end: 0)
            .chain(CurveTween(curve: Curves.easeInCubic)),
        weight: 30,
      ),
    ]).animate(_controller);
    _lift = Tween<double>(begin: 10, end: -18).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) widget.onFinished();
    });
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color _noticeColor() {
    final text = widget.message;
    if (RegExp(r'失败|不足|错误|最多|无法|不存在').hasMatch(text)) {
      return _characterHighStar;
    }
    if (RegExp(r'已|成功|获得|领悟|更新').hasMatch(text)) {
      return _characterGold;
    }
    return _characterTextSoft;
  }

  @override
  Widget build(BuildContext context) {
    final color = _noticeColor();
    return Positioned(
      left: 24,
      right: 24,
      top: MediaQuery.paddingOf(context).top + 66,
      child: IgnorePointer(
        child: Material(
          type: MaterialType.transparency,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) => Transform.translate(
              offset: Offset(0, _lift.value),
              child: Opacity(opacity: _opacity.value, child: child),
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Text(
                  widget.message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: color,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .75,
                    height: 1.35,
                    decoration: TextDecoration.none,
                    decorationColor: Colors.transparent,
                    shadows: <Shadow>[
                      Shadow(color: Colors.black.withOpacity(.95), blurRadius: 10),
                      Shadow(color: color.withOpacity(.30), blurRadius: 8),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CharacterDialogBackdrop extends StatelessWidget {
  const _CharacterDialogBackdrop({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 3.8, sigmaY: 3.8),
      child: child,
    );
  }
}

// 透明叠加在立绘上的文字统一使用细描边，替代大面积深色遮罩。
const List<Shadow> _characterTextOutlineShadows = <Shadow>[
  Shadow(color: Color(0xF2000000), offset: Offset(-.9, 0), blurRadius: 1.2),
  Shadow(color: Color(0xF2000000), offset: Offset(.9, 0), blurRadius: 1.2),
  Shadow(color: Color(0xF2000000), offset: Offset(0, -.9), blurRadius: 1.2),
  Shadow(color: Color(0xF2000000), offset: Offset(0, .9), blurRadius: 1.2),
  Shadow(color: Color(0xB3000000), offset: Offset(0, 1.6), blurRadius: 3.4),
];

enum _CharacterViewportMode { portrait, landscape, desktop }

_CharacterViewportMode _characterViewportMode(
  BoxConstraints constraints,
  bool desktopMode,
) {
  final width = constraints.maxWidth;
  final height = constraints.maxHeight;

  // 真正的手机横屏优先于 desktopMode。这样 iPhone 横过来时不会误套 PC。
  final phoneLandscape =
      width > height && height <= 540 && width <= 1100;
  if (phoneLandscape) return _CharacterViewportMode.landscape;

  // 竖屏手机也直接按实际画布识别，保证旋转回来后恢复竖屏布局。
  final phonePortrait = height >= width && width <= 640;
  if (phonePortrait) return _CharacterViewportMode.portrait;

  if (desktopMode) return _CharacterViewportMode.desktop;
  return width > height
      ? _CharacterViewportMode.landscape
      : _CharacterViewportMode.portrait;
}

class _CharacterGameBackdrop extends StatelessWidget {
  const _CharacterGameBackdrop({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Color(0xFF070B15),
            Color(0xFF101A30),
            Color(0xFF090E1A),
          ],
          stops: <double>[0, .56, 1],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Positioned(
            left: -170,
            top: -240,
            child: Container(
              width: 520,
              height: 520,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: _characterGold.withOpacity(.13),
                  width: 1,
                ),
              ),
            ),
          ),
          Positioned(
            right: -230,
            bottom: -310,
            child: Container(
              width: 650,
              height: 650,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: <Color>[
                    _characterBlue.withOpacity(.17),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 90,
            right: 90,
            top: 0,
            height: 1,
            child: ColoredBox(color: _characterGoldSoft.withOpacity(.16)),
          ),
          child,
        ],
      ),
    );
  }
}

class _NovelCharacterHub extends StatefulWidget {
  const _NovelCharacterHub({
    required this.controller,
    this.embedded = false,
    this.focusCharacterKey = '',
    this.focusRequestId = 0,
  });

  final NovelGameController controller;
  final bool embedded;
  final String focusCharacterKey;
  final int focusRequestId;

  @override
  State<_NovelCharacterHub> createState() => _NovelCharacterHubState();
}

class _NovelCharacterHubState extends State<_NovelCharacterHub> {
  int tab = 0; // 0 角色主页 / 1 图鉴
  bool loading = true;
  bool showingSummon = false;
  bool isDrawing = false; 
  String selectedCharacterKey = '';
  List<_CharacterDrawResult> lastDrawResults = <_CharacterDrawResult>[];

  @override
  void initState() {
    super.initState();
    selectedCharacterKey = widget.focusCharacterKey.trim();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_refresh());
    });
  }

  @override
  void didUpdateWidget(covariant _NovelCharacterHub oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changed = widget.focusRequestId != oldWidget.focusRequestId ||
        widget.focusCharacterKey != oldWidget.focusCharacterKey;
    if (!changed || widget.focusCharacterKey.trim().isEmpty) return;
    setState(() {
      selectedCharacterKey = widget.focusCharacterKey.trim();
      showingSummon = false;
    });
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() => loading = true);
    try {
      await widget.controller.refreshNovelCharacterRoster(notify: false);
      await widget.controller.refreshCharacterStatus(notify: false);
    } catch (error) {
      if (mounted) {
        _message(
          error is NovelBackendException
              ? error.message
              : '角色数据加载失败：$error',
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  String _keyOf(NovelCharacter character) => character.id.trim().isNotEmpty
      ? character.id.trim()
      : character.name.trim();

  bool _asBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    return const <String>{'1', 'true', 'yes', 'on'}
        .contains(value?.toString().trim().toLowerCase());
  }

  int _asInt(dynamic value, [int fallback = 0]) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  bool _isOwned(NovelCharacter character) {
    if (character.isMain) return true;
    final id = character.id.trim();
    if (id.isNotEmpty) {
      final roster = widget.controller.novelCharacterRosterEntry(id);
      if (roster.isNotEmpty) return boolValue(roster['owned']);
    }
    final explicit = character.status['owned'] ??
        character.status['is_owned'] ??
        character.persona['owned'] ??
        character.persona['is_owned'];
    return _asBool(explicit);
  }

  bool _isRecruitable(NovelCharacter character) {
    if (character.isMain) return false;
    final explicit = character.status['recruitable'] ??
        character.persona['recruitable'];
    return explicit == null || _asBool(explicit);
  }

  int _fragmentsOf(NovelCharacter character) {
    final id = character.id.trim();
    if (id.isNotEmpty) {
      final roster = widget.controller.novelCharacterRosterEntry(id);
      if (roster.isNotEmpty) {
        return intValue(roster['fragments']).clamp(0, 9999).toInt();
      }
    }
    return _asInt(
      character.status['fragments'] ?? character.status['character_fragments'],
    ).clamp(0, 9999).toInt();
  }

  int _starOf(NovelCharacter character) {
    if (character.isMain) return 0;
    final id = character.id.trim();
    if (id.isNotEmpty) {
      final roster = widget.controller.novelCharacterRosterEntry(id);
      if (roster.isNotEmpty) {
        return intValue(roster['star']).clamp(0, 10).toInt();
      }
    }
    return _asInt(
      character.status['star'] ?? character.status['stars'],
      0,
    ).clamp(0, 10).toInt();
  }

  String _summaryOf(NovelCharacter character) {
    final values = <dynamic>[
      character.status['description'],
      character.persona['description'],
      character.status['background'],
      character.persona['background'],
      character.status['personality'],
      character.persona['personality'],
    ];
    for (final value in values) {
      final text = stringValue(value).trim();
      if (text.isNotEmpty) return text;
    }
    return '更多故事，将在与你的相遇中逐渐解锁。';
  }

  void _message(String text) {
    _showCharacterFloatingNotice(context, text);
  }

  void _selectHero(NovelCharacter character) {
    setState(() {
      selectedCharacterKey = _keyOf(character);
      showingSummon = false;
    });
  }

  void _openSummon() {
    setState(() {
      tab = 0;
      showingSummon = true;
    });
  }

  Future<void> _draw(List<NovelCharacter> characters, int count) async {
    final flowers = widget.controller.novelCharacterFlowers;
    if (flowers < count) {
      _message('鲜花不足，还需要 ${count - flowers} 朵');
      return;
    }

    final candidates = characters
        .where((character) => !character.isMain && _isRecruitable(character))
        .toList();
    if (candidates.isEmpty) {
      _message('暂无可结缘角色');
      return;
    }

    // 弹出独立的沉浸式结缘动画窗口
    final results = await showGeneralDialog<List<_CharacterDrawResult>>(
      context: context,
      barrierDismissible: false,
      barrierColor: const Color(0xEE05080E), 
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, _, __) {
        return _SummonProcessModal(
          controller: widget.controller,
          candidates: candidates,
          count: count,
        );
      },
    );

    if (results != null && results.isNotEmpty && mounted) {
      setState(() => lastDrawResults = results);
      for (final result in results.where((item) => item.newlyOwned)) {
        final characterId = result.character.id.trim();
        if (characterId.isEmpty) continue;
        try {
          final payload =
              await widget.controller.drawNovelCompanionSkill(characterId);
          final skill = asJsonMap(payload['drawn_skill']);
          if (skill.isNotEmpty && mounted) {
            await _nameInitialCompanionSkill(result.character, skill);
          }
        } catch (error) {
          if (mounted) {
            _message(error is NovelBackendException
                ? error.message
                : '初始技能生成失败：$error');
          }
        }
      }
    }
  }

  Future<void> _nameInitialCompanionSkill(
    NovelCharacter character,
    JsonMap skill,
  ) async {
    var draftName = '';
    while (mounted) {
      var latestDraft = draftName;
      final name = await _showCompanionSkillNamingDialog(
        context,
        skill,
        title: '${character.name}获得新技能',
        initialName: draftName,
        allowDiscard: true,
        onDraftChanged: (value) => latestDraft = value,
        confirmLabel: '命名并领悟',
      );
      draftName = latestDraft;
      if (name == null || !mounted) return;

      if (name == _companionSkillDiscardToken) {
        final skillName = stringValue(skill['name'], '该技能');
        final confirmed = await _confirmDiscardCompanionSkill(context, skillName);
        if (!mounted) return;
        if (confirmed != true) {
          // 用户只是从“确认舍弃”返回：继续编辑刚才输入的草稿名。
          continue;
        }
        try {
          await widget.controller.renameNovelCompanionSkill(
            characterInstanceId: character.id,
            skillId: stringValue(skill['id']),
            name: _companionSkillDiscardToken,
          );
          if (mounted) _message('已舍弃技能「$skillName」');
        } catch (error) {
          if (mounted) {
            _message(
              error is NovelBackendException ? error.message : '舍弃技能失败：$error',
            );
          }
        }
        return;
      }

      final clean = name.trim();
      if (clean.isEmpty) continue;
      await _finalizeCompanionSkillWithPreview(
        context: context,
        controller: widget.controller,
        character: character,
        skill: skill,
        name: clean,
      );
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final source =
            widget.controller.scenario?.characters.values.toList() ??
                <NovelCharacter>[];
        final npcs = source.where((character) => !character.isMain).toList()
          ..sort((a, b) => b.affection.compareTo(a.affection));
        final allCharacters = npcs;

        final ownedCharacters = allCharacters.where(_isOwned).toList();
        ownedCharacters.sort((a, b) {
          final ak = _keyOf(a);
          final bk = _keyOf(b);
          final ad = widget.controller.isNovelCompanionDeployed(ak);
          final bd = widget.controller.isNovelCompanionDeployed(bk);
          if (ad && !bd) return -1;
          if (bd && !ad) return 1;
          return 0;
        });

        NovelCharacter? selected;
        for (final character in allCharacters) {
          if (_keyOf(character) == selectedCharacterKey) {
            selected = character;
            break;
          }
        }

        final archiveVisible = tab == 1;
        final activeSection = showingSummon
            ? 'summon'
            : (archiveVisible ? 'archive' : 'characters');
        final firstOwnedNpc =
            ownedCharacters.isEmpty ? null : ownedCharacters.first;
        final hero = selected != null && _isOwned(selected!)
            ? selected
            : firstOwnedNpc;

        Widget buildBody(_CharacterViewportMode mode) {
          final desktop = mode == _CharacterViewportMode.desktop;
          final landscape = mode == _CharacterViewportMode.landscape;

          return Column(
            children: <Widget>[
              _CharacterGameHeader(
                flowers: widget.controller.novelCharacterFlowers,
                activeSection: activeSection,
                dense: landscape,
                onCharacters: () => setState(() {
                  tab = 0;
                  showingSummon = false;
                }),
                onArchive: () => setState(() {
                  tab = 1;
                  showingSummon = false;
                }),
                onSummon: _openSummon,
                onClose: widget.embedded
                    ? null
                    : () => Navigator.of(context).pop(),
              ),
              Expanded(
                child: showingSummon
                    ? _CharacterSummonView(
                        characters: allCharacters,
                        desktopMode: desktop,
                        landscapeMode: landscape,
                        flowers: widget.controller.novelCharacterFlowers,
                        results: lastDrawResults,
                        isDrawing: isDrawing,
                        isOwned: _isOwned,
                        fragmentsOf: _fragmentsOf,
                        onDrawOne: () => _draw(allCharacters, 1),
                        onDrawFive: () => _draw(allCharacters, 5),
                      )
                    : tab == 0 && hero != null
                        ? _CharacterHeroStage(
                            controller: widget.controller,
                            character: hero,
                            characters: ownedCharacters,
                            star: _starOf(hero),
                            fragments: _fragmentsOf(hero),
                            onSelect: _selectHero,
                          )
                        : tab == 0
                            ? _CharacterEmptyTeamState(
                                loading: loading,
                                onSummon: _openSummon,
                              )
                            : _CharacterGridPage(
                                desktopMode: desktop,
                                landscapeMode: landscape,
                                characters: allCharacters,
                                loading: loading,
                                starOf: _starOf,
                              ),
              ),
            ],
          );
        }

        return _CharacterGameBackdrop(
          child: SafeArea(
            bottom: false,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final mode = _characterViewportMode(
                  constraints,
                  widget.controller.desktopMode,
                );

                switch (mode) {
                  case _CharacterViewportMode.desktop:
                    return Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1440),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(46, 14, 54, 12),
                          child: buildBody(mode),
                        ),
                      ),
                    );
                  case _CharacterViewportMode.landscape:
                    // 手机横屏：独立画布。横向空间全部使用，纵向间距单独收紧。
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(10, 2, 10, 2),
                      child: buildBody(mode),
                    );
                  case _CharacterViewportMode.portrait:
                    // 手机竖屏：保留原来的窄屏结构，不被横屏布局影响。
                    return Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 560),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(10, 4, 12, 4),
                          child: buildBody(mode),
                        ),
                      ),
                    );
                }
              },
            ),
          ),
        );
      },
    );
  }
}

class _CharacterEmptyTeamState extends StatelessWidget {
  const _CharacterEmptyTeamState({
    required this.loading,
    required this.onSummon,
  });

  final bool loading;
  final VoidCallback onSummon;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(
        child: Text(
          '正在整理队伍资料…',
          style: TextStyle(
            color: _characterTextMuted,
            fontSize: 10.5,
            letterSpacing: .8,
          ),
        ),
      );
    }

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            Icons.local_florist_outlined,
            size: 32,
            color: _characterGoldSoft.withOpacity(.82),
          ),
          const SizedBox(height: 12),
          const Text(
            '还没有结缘角色',
            style: TextStyle(
              color: _characterText,
              fontSize: 15,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '前往结缘，遇见可以加入队伍的角色',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _characterTextMuted,
              fontSize: 10.5,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 15),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onSummon,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const <Widget>[
                    Text(
                      '前往结缘',
                      style: TextStyle(
                        color: _characterGoldSoft,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.1,
                      ),
                    ),
                    SizedBox(width: 6),
                    Icon(
                      Icons.arrow_forward,
                      size: 14,
                      color: _characterGoldSoft,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CharacterGameHeader extends StatelessWidget {
  const _CharacterGameHeader({
    required this.flowers,
    required this.activeSection,
    required this.onCharacters,
    required this.onArchive,
    required this.onSummon,
    this.onClose,
    this.dense = false,
  });

  final int flowers;
  final String activeSection;
  final VoidCallback onCharacters;
  final VoidCallback onArchive;
  final VoidCallback onSummon;
  final VoidCallback? onClose;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final gap = dense ? 13.0 : 20.0;
    return SizedBox(
      height: dense ? 44 : 68,
      child: Row(
        children: <Widget>[
          Expanded(
            child: Row(
              children: <Widget>[
                _CharacterHeaderNavAction(
                  label: '角色',
                  selected: activeSection == 'characters',
                  dense: dense,
                  onTap: onCharacters,
                ),
                SizedBox(width: gap),
                _CharacterHeaderNavAction(
                  label: '图鉴',
                  selected: activeSection == 'archive',
                  dense: dense,
                  onTap: onArchive,
                ),
                SizedBox(width: gap),
                _CharacterHeaderNavAction(
                  label: '结缘',
                  selected: activeSection == 'summon',
                  dense: dense,
                  featured: true,
                  icon: Icons.local_florist_outlined,
                  onTap: onSummon,
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: dense ? 2 : 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                SizedBox(
                  width: dense ? 19 : 23,
                  height: dense ? 19 : 23,
                  child: Image.asset(
                    'assets/images/gift.webp',
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.local_florist_outlined,
                      size: 18,
                      color: _characterGold,
                    ),
                  ),
                ),
                SizedBox(width: dense ? 5 : 8),
                Text(
                  '$flowers',
                  style: TextStyle(
                    color: _characterText,
                    fontSize: dense ? 10.5 : 11.5,
                    fontWeight: FontWeight.w700,
                    shadows: _characterTextOutlineShadows,
                  ),
                ),
              ],
            ),
          ),
          if (onClose != null) ...<Widget>[
            SizedBox(width: dense ? 7 : 12),
            IconButton(
              onPressed: onClose,
              padding: EdgeInsets.zero,
              splashRadius: 18,
              constraints: BoxConstraints.tightFor(
                width: dense ? 28 : 32,
                height: dense ? 28 : 32,
              ),
              icon: Icon(
                Icons.close,
                size: dense ? 16 : 18,
                color: _characterTextSoft,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CharacterHeaderNavAction extends StatelessWidget {
  const _CharacterHeaderNavAction({
    required this.label,
    required this.selected,
    required this.dense,
    required this.onTap,
    this.featured = false,
    this.icon,
  });

  final String label;
  final bool selected;
  final bool dense;
  final bool featured;
  final IconData? icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final selectedColor = featured ? _characterGoldSoft : _characterText;
    final idleColor = featured
        ? _characterGoldSoft.withOpacity(.78)
        : _characterTextMuted.withOpacity(.88);
    final color = selected ? selectedColor : idleColor;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: dense ? 34 : 42,
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (icon != null) ...<Widget>[
                      Icon(icon, size: dense ? 12 : 14, color: color),
                      SizedBox(width: dense ? 4 : 5),
                    ],
                    Text(
                      label,
                      style: TextStyle(
                        color: color,
                        fontSize: dense ? 11 : 12.5,
                        fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                        letterSpacing: selected ? 1.25 : 1.0,
                        shadows: _characterTextOutlineShadows,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                Positioned(
                  left: 4,
                  right: 4,
                  bottom: 2,
                  child: Container(
                    height: 2,
                    color: selectedColor.withOpacity(.92),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CharacterGridPage extends StatelessWidget {
  const _CharacterGridPage({
    required this.characters,
    required this.loading,
    required this.starOf,
    required this.desktopMode,
    this.landscapeMode = false,
  });

  final List<NovelCharacter> characters;
  final bool loading;
  final int Function(NovelCharacter) starOf;
  final bool desktopMode;
  final bool landscapeMode;

  @override
  Widget build(BuildContext context) {
    if (characters.isEmpty) {
      return Center(
        child: Text(
          loading
              ? '正在整理角色资料…'
              : '还没有获得角色',
          style: const TextStyle(
            color: _characterTextMuted,
            fontSize: 10.5,
            letterSpacing: .8,
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        // 模式决定密度；尺寸只在当前模式内部决定具体列数。
        final count = desktopMode
            ? (constraints.maxWidth >= 1260
                ? 7
                : constraints.maxWidth >= 980
                    ? 6
                    : 5)
            : landscapeMode
                ? (constraints.maxWidth >= 820
                    ? 7
                    : constraints.maxWidth >= 680
                        ? 6
                        : 5)
                : (constraints.maxWidth >= 420 ? 4 : 3);
        return GridView.builder(
          padding: EdgeInsets.fromLTRB(
            desktopMode ? 6 : 2,
            2,
            desktopMode ? 6 : 2,
            desktopMode ? 34 : 28,
          ),
          physics: const BouncingScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: count,
            crossAxisSpacing: desktopMode ? 14 : (landscapeMode ? 10 : 8),
            mainAxisSpacing: desktopMode ? 14 : (landscapeMode ? 10 : 9),
            childAspectRatio: desktopMode ? .69 : (landscapeMode ? .76 : .65), 
          ),
          itemCount: characters.length,
          itemBuilder: (context, index) {
            final character = characters[index];
            return _CharacterGameCard(
              character: character,
              star: starOf(character),
            );
          },
        );
      },
    );
  }
}

class _CharacterGameCard extends StatelessWidget {
  const _CharacterGameCard({
    required this.character,
    required this.star,
  });

  final NovelCharacter character;
  final int star;

  @override
  Widget build(BuildContext context) {
    final fallbackAsset = character.gender.trim() == '女'
        ? 'assets/images/portrait_female.webp'
        : 'assets/images/portrait_male.png';
    final imageUrl = character.avatarUrl.trim().isNotEmpty
        ? character.avatarUrl
        : character.portraitUrl;
        
    return Container(
          decoration: BoxDecoration(
            color: _characterInkSoft,
            borderRadius: BorderRadius.circular(4), 
            border: Border.all(
              color: Colors.white.withOpacity(0.08),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              ColorFiltered(
                colorFilter: const ColorFilter.matrix(<double>[
                        1, 0, 0, 0, 0,
                        0, 1, 0, 0, 0,
                        0, 0, 1, 0, 0,
                        0, 0, 0, 1, 0,
                      ]),
                child: NovelArtwork(
                  url: CdnUtil.resize(imageUrl, width: 420),
                  assetCandidates: <String>[
                    fallbackAsset,
                    'assets/images/portrait_female.webp',
                    'assets/images/portrait_male.png',
                  ],
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                  fallbackText: '',
                  fallbackIcon: Icons.person_outline_rounded,
                ),
              ),
              const Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 60,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: <Color>[
                        Colors.transparent,
                        Color(0xD9090E1A),
                        Color(0xFF090E1A),
                      ],
                      stops: <double>[0, .4, 1],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 8,
                top: 8,
                child: Text(
                  '已拥有',
                  style: const TextStyle(
                    color: _characterGold,
                    fontSize: 7.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: .8,
                  ),
                ),
              ),
              Positioned(
                left: 10,
                right: 10,
                bottom: 8, 
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      character.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _characterText,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: .6,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      star == 0
                          ? '0 星'
                          : List<String>.filled(
                              star > 5 ? star - 5 : star,
                              '✦',
                            ).join(' '),
                      style: TextStyle(
                        color: star > 5
                            ? _characterHighStar
                            : _characterGold,
                        fontSize: 9,
                        letterSpacing: .8,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
  }
}

// ============================================================================
// 结缘抽卡及沉浸式动画全集
// ============================================================================
class _CharacterDrawResult {
  const _CharacterDrawResult({
    required this.character,
    required this.fragments,
    required this.direct,
    required this.newlyOwned,
    required this.duplicate,
  });

  final NovelCharacter character;
  final int fragments;
  final bool direct;
  final bool newlyOwned;
  final bool duplicate;
}

class _CharacterSummonView extends StatelessWidget {
  const _CharacterSummonView({
    required this.characters,
    required this.desktopMode,
    this.landscapeMode = false,
    required this.flowers,
    required this.results,
    required this.isDrawing,
    required this.isOwned,
    required this.fragmentsOf,
    required this.onDrawOne,
    required this.onDrawFive,
  });

  final List<NovelCharacter> characters;
  final bool desktopMode;
  final bool landscapeMode;
  final int flowers;
  final List<_CharacterDrawResult> results;
  final bool isDrawing;
  final bool Function(NovelCharacter) isOwned;
  final int Function(NovelCharacter) fragmentsOf;
  final VoidCallback onDrawOne;
  final VoidCallback onDrawFive;

  Widget _buildBannerPortrait(NovelCharacter character, double width, double opacity, Alignment alignment) {
    final fallbackAsset = character.gender.trim() == '男' ? 'assets/images/portrait_male.png' : 'assets/images/portrait_female.webp';
    final imageUrl = character.portraitUrl.isNotEmpty ? character.portraitUrl : character.avatarUrl;

    return Align(
      alignment: alignment,
      child: Opacity(
        opacity: opacity,
        child: SizedBox(
          width: width,
          child: NovelArtwork(
            url: CdnUtil.resize(imageUrl, width: width.toInt() * 2),
            assetCandidates: <String>[fallbackAsset, 'assets/images/portrait_female.webp', 'assets/images/portrait_male.png'],
            fit: BoxFit.contain,
            alignment: Alignment.bottomCenter,
            fallbackText: '',
            fallbackIcon: Icons.person_outline_rounded,
          ),
        ),
      ),
    );
  }

  Widget _buildSummonButton({required String label, required int cost, required bool enabled, required VoidCallback onTap, required bool primary}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: 150,
          height: 48,
          decoration: BoxDecoration(
            color: !enabled ? Colors.white.withOpacity(0.04) : primary ? _characterBlue.withOpacity(0.85) : Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: primary && enabled ? _characterGold.withOpacity(0.7) : Colors.white.withOpacity(0.12)),
            boxShadow: primary && enabled ? [BoxShadow(color: _characterBlue.withOpacity(0.4), blurRadius: 15, offset: const Offset(0, 4))] : [],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(label, style: TextStyle(color: enabled ? _characterText : _characterTextMuted, fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
              const SizedBox(width: 8),
              Opacity(
                opacity: enabled ? 1.0 : 0.4,
                child: Image.asset('assets/images/gift.webp', width: 18, height: 18, fit: BoxFit.contain, errorBuilder: (_, __, ___) => Icon(Icons.local_florist_rounded, size: 16, color: enabled ? _characterGold : _characterTextMuted)),
              ),
              const SizedBox(width: 4),
              Text('$cost', style: TextStyle(color: enabled ? _characterGold : _characterTextMuted, fontSize: 14, fontWeight: FontWeight.w900)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final candidates = characters.where((character) => !character.isMain).toList();
    final topCharacters = candidates.take(3).toList();
    final screen = MediaQuery.sizeOf(context);
    final bannerHeight = screen.height *
        (desktopMode ? .64 : (landscapeMode ? .82 : .49));
    final sidePortraitWidth = desktopMode ? 300.0 : (landscapeMode ? 150.0 : 185.0);
    final heroPortraitWidth = desktopMode ? 420.0 : (landscapeMode ? 235.0 : 270.0);
    final actionBottom = desktopMode
        ? screen.height * .09
        : (landscapeMode ? 6.0 : screen.height * .08);

    return Stack(
      fit: StackFit.expand,
      children: [
        if (topCharacters.isNotEmpty)
          Positioned(
            top: 0, left: 0, right: 0, height: bannerHeight,
            child: Stack(
              children: [
                if (topCharacters.length >= 2) _buildBannerPortrait(topCharacters[1], sidePortraitWidth, desktopMode ? .52 : .38, const Alignment(-0.9, 1.0)),
                if (topCharacters.length >= 3) _buildBannerPortrait(topCharacters[2], sidePortraitWidth, desktopMode ? .52 : .38, const Alignment(0.9, 1.0)),
                _buildBannerPortrait(topCharacters[0], heroPortraitWidth, 1.0, const Alignment(0.0, 1.0)),
                Positioned(
                  left: 0, right: 0, bottom: 0, height: desktopMode ? 180 : 120,
                  child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, _characterInkSoft.withOpacity(0.8), _characterInkSoft]))),
                ),
              ],
            ),
          ),
        Positioned(
          left: 0, right: 0, bottom: actionBottom,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '寻 访 角 色',
                style: TextStyle(
                  color: _characterText,
                  fontSize: desktopMode ? 30 : (landscapeMode ? 17 : 21),
                  fontWeight: FontWeight.w900,
                  letterSpacing: desktopMode ? 7 : (landscapeMode ? 3.2 : 4.5),
                  shadows: const [Shadow(color: Colors.black87, blurRadius: 10)],
                ),
              ),
              SizedBox(height: desktopMode ? 14 : (landscapeMode ? 4 : 9)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(color: Colors.black.withOpacity(0.4), borderRadius: BorderRadius.circular(99), border: Border.all(color: Colors.white.withOpacity(0.05))),
                child: const Text('消耗鲜花寻访，获取完整角色或角色碎片', style: TextStyle(color: _characterTextSoft, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1.0)),
              ),
              SizedBox(height: desktopMode ? 32 : (landscapeMode ? 8 : 20)),
              Wrap(
                spacing: desktopMode ? 20 : 10,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  _buildSummonButton(label: '寻访 1 次', cost: 1, enabled: flowers >= 1 && candidates.isNotEmpty, onTap: onDrawOne, primary: false),
                  _buildSummonButton(label: '寻访 5 次', cost: 5, enabled: flowers >= 5 && candidates.isNotEmpty, onTap: onDrawFive, primary: true),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SummonProcessModal extends StatefulWidget {
  const _SummonProcessModal({required this.controller, required this.candidates, required this.count});
  final NovelGameController controller;
  final List<NovelCharacter> candidates;
  final int count;
  @override
  State<_SummonProcessModal> createState() => _SummonProcessModalState();
}

class _SummonProcessModalState extends State<_SummonProcessModal> {
  bool _loading = true;
  String _error = '';
  List<_CharacterDrawResult> _results = [];

  @override
  void initState() {
    super.initState();
    _doDraw();
  }

  Future<void> _doDraw() async {
    final startedAt = DateTime.now();
    try {
      final payload = await widget.controller.drawNovelCharacters(widget.count);
      final results = <_CharacterDrawResult>[];
      for (final raw in asJsonList(payload['results'])) {
        final item = asJsonMap(raw);
        final id = stringValue(item['character_instance_id'] ?? item['character_id']).trim();
        final name = stringValue(item['character_name']).trim();
        NovelCharacter? matched;
        for (final character in widget.candidates) {
          if ((id.isNotEmpty && character.id == id) || (name.isNotEmpty && character.name == name)) {
            matched = character;
            break;
          }
        }
        if (matched == null) continue;
        results.add(_CharacterDrawResult(character: matched, fragments: intValue(item['fragments_gained']), direct: boolValue(item['direct']), newlyOwned: boolValue(item['newly_owned']), duplicate: boolValue(item['duplicate'])));
      }
      final elapsed = DateTime.now().difference(startedAt);
      if (elapsed < const Duration(milliseconds: 1800)) {
        await Future<void>.delayed(const Duration(milliseconds: 1800) - elapsed);
      }
      if (mounted) setState(() { _results = results; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e is NovelBackendException ? e.message : '寻访失败：$e'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () { if (!_loading) Navigator.pop(context, _results); },
        child: SizedBox(
          width: double.infinity, height: double.infinity,
          child: _loading
              ? const Center(child: _DestinyLoadingIndicator())
              : _error.isNotEmpty
                  ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Text(_error, style: const TextStyle(color: _characterHighStar, fontSize: 13)), const SizedBox(height: 20), const _PulseContinueText()]))
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final compact = !widget.controller.desktopMode;
                        return Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Spacer(flex: 3),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: Wrap(
                                spacing: 16, runSpacing: 20, alignment: WrapAlignment.center,
                                children: _results.asMap().entries.map((e) => SizedBox(width: compact ? 102 : 132, height: compact ? 150 : 192, child: _CharacterDrawResultCard(result: e.value, revealIndex: e.key))).toList(),
                              ),
                            ),
                            const Spacer(flex: 2),
                            const _PulseContinueText(),
                            const Spacer(flex: 1),
                          ],
                        );
                      },
                    ),
        ),
      ),
    );
  }
}

class _DestinyLoadingIndicator extends StatefulWidget {
  const _DestinyLoadingIndicator();
  @override
  State<_DestinyLoadingIndicator> createState() => _DestinyLoadingIndicatorState();
}

class _DestinyLoadingIndicatorState extends State<_DestinyLoadingIndicator> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  @override
  void initState() { super.initState(); _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat(reverse: true); }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        return Container(
          width: 90, height: 90,
          decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [BoxShadow(color: _characterGold.withOpacity(0.15 + 0.35 * _ctrl.value), blurRadius: 20 + 30 * _ctrl.value, spreadRadius: 5 + 10 * _ctrl.value)]),
          child: Center(
            child: Opacity(
              opacity: 0.5 + 0.5 * _ctrl.value,
              child: Image.asset('assets/images/gift.webp', width: 36 + 8 * _ctrl.value, height: 36 + 8 * _ctrl.value, fit: BoxFit.contain, errorBuilder: (_, __, ___) => Icon(Icons.local_florist_rounded, color: _characterGold, size: 36 + 8 * _ctrl.value)),
            ),
          ),
        );
      },
    );
  }
}

class _PulseContinueText extends StatefulWidget {
  const _PulseContinueText();
  @override
  State<_PulseContinueText> createState() => _PulseContinueTextState();
}

class _PulseContinueTextState extends State<_PulseContinueText> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  @override
  void initState() { super.initState(); _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))..repeat(reverse: true); }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Opacity(opacity: 0.3 + 0.7 * _ctrl.value, child: const Text('—  点击任意处继续  —', style: TextStyle(color: _characterTextSoft, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 3))),
    );
  }
}

class _CharacterDrawResultCard extends StatefulWidget {
  const _CharacterDrawResultCard({super.key, required this.result, required this.revealIndex});
  final _CharacterDrawResult result;
  final int revealIndex;
  @override
  State<_CharacterDrawResultCard> createState() => _CharacterDrawResultCardState();
}

class _CharacterDrawResultCardState extends State<_CharacterDrawResultCard> with SingleTickerProviderStateMixin {
  bool _visible = false;
  bool _revealed = false;
  late AnimationController _animController;
  late Animation<double> _flipAnim;
  late Animation<double> _flashAnim;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
    _flipAnim = Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(parent: _animController, curve: const Interval(0.0, 0.4, curve: Curves.easeOutBack)));
    _flashAnim = TweenSequence<double>([TweenSequenceItem(tween: Tween<double>(begin: 0, end: 1).chain(CurveTween(curve: Curves.easeIn)), weight: 1), TweenSequenceItem(tween: Tween<double>(begin: 1, end: 0).chain(CurveTween(curve: Curves.easeOut)), weight: 2)]).animate(CurvedAnimation(parent: _animController, curve: const Interval(0.35, 0.75)));
    _scaleAnim = Tween<double>(begin: 1.0, end: 1.12).animate(CurvedAnimation(parent: _animController, curve: const Interval(0.4, 1.0, curve: Curves.easeOutCubic)));
    Future<void>.delayed(Duration(milliseconds: 100 + widget.revealIndex * 150), () { if (mounted) setState(() => _visible = true); });
  }

  @override
  void dispose() { _animController.dispose(); super.dispose(); }

  void _onTapReveal() {
    if (!_visible || _revealed) return;
    setState(() => _revealed = true);
    _animController.forward();
  }

  @override
  Widget build(BuildContext context) {
    final character = widget.result.character;
    final fallbackAsset = character.gender.trim() == '女' ? 'assets/images/portrait_female.webp' : 'assets/images/portrait_male.png';

    return AnimatedOpacity(
      opacity: _visible ? 1 : 0, duration: const Duration(milliseconds: 260), curve: Curves.easeOut,
      child: AnimatedScale(
        scale: _visible ? 1 : .8, duration: const Duration(milliseconds: 360), curve: Curves.easeOutBack,
        child: widget.result.direct
            ? GestureDetector(
                onTap: _onTapReveal,
                child: AnimatedBuilder(
                  animation: _animController,
                  builder: (context, _) {
                    final showFront = _flipAnim.value >= 0.5;
                    final angle = showFront ? math.pi * (_flipAnim.value - 1) : math.pi * _flipAnim.value;
                    return Transform(alignment: Alignment.center, transform: Matrix4.identity()..setEntry(3, 2, 0.0015)..rotateY(angle), child: showFront ? _buildFront(character, fallbackAsset, isFlipping: true) : _buildBack());
                  },
                ),
              )
            : _buildFront(character, fallbackAsset),
      ),
    );
  }

  Widget _buildBack() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Colors.white.withOpacity(.12), _characterGoldSoft.withOpacity(.15), Colors.white.withOpacity(.04)]),
        border: Border.all(color: _characterGold.withOpacity(.4)), borderRadius: BorderRadius.circular(6), boxShadow: [BoxShadow(color: _characterGold.withOpacity(.15), blurRadius: 15, offset: const Offset(0, 5))],
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(child: Padding(padding: const EdgeInsets.all(8.0), child: Container(decoration: BoxDecoration(borderRadius: BorderRadius.circular(4), border: Border.all(color: _characterGoldSoft.withOpacity(.3)), gradient: const RadialGradient(colors: [Colors.transparent, Color(0x33000000)], radius: 0.8)), child: Center(child: Icon(Icons.change_history_rounded, color: _characterGold.withOpacity(0.5), size: 28))))),
          const Positioned(left: 0, right: 0, bottom: 15, child: Text('启示', textAlign: TextAlign.center, style: TextStyle(color: _characterGold, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 4.0))),
        ],
      ),
    );
  }

  Widget _buildFront(NovelCharacter character, String fallbackAsset, {bool isFlipping = false}) {
    final result = widget.result;
    return Container(
      decoration: BoxDecoration(
        color: _characterInkSoft,
        border: Border.all(color: result.direct ? _characterGold.withOpacity(.7) : Colors.white.withOpacity(.08), width: result.direct ? 1.5 : 1.0),
        borderRadius: BorderRadius.circular(6),
        boxShadow: result.direct && _revealed ? [BoxShadow(color: _characterGold.withOpacity(.25), blurRadius: 20, spreadRadius: 2)] : [],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Column(
            children: <Widget>[
              Expanded(child: ClipRect(child: Transform.scale(scale: isFlipping ? _scaleAnim.value : 1.0, child: NovelArtwork(url: CdnUtil.resize(character.avatarUrl.trim().isNotEmpty ? character.avatarUrl : character.portraitUrl, width: 240), assetCandidates: <String>[fallbackAsset, 'assets/images/portrait_female.webp', 'assets/images/portrait_male.png'], fit: BoxFit.cover, alignment: Alignment.topCenter, fallbackText: '', fallbackIcon: Icons.person_outline_rounded)))),
              Container(
                width: double.infinity, padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
                decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Color(0xFF090E1A), Color(0xCC090E1A), Colors.transparent])),
                child: Column(
                  children: <Widget>[
                    Text(character.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _characterText, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.0)),
                    const SizedBox(height: 4),
                    Text(result.direct ? (result.duplicate ? '重复角色 · 转${result.fragments}碎片' : '新角色 · 命运结缘') : (result.newlyOwned ? '碎片集齐 · 加入队伍' : '角色碎片 · ${result.fragments} 片'), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: result.direct ? (result.duplicate ? _characterBlueBright : _characterGold) : _characterTextMuted, fontSize: 8.5, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            ],
          ),
          if (isFlipping) Positioned.fill(child: IgnorePointer(child: Container(color: Colors.white.withOpacity(_flashAnim.value)))),
        ],
      ),
    );
  }
}

class _CharacterPortraitRail extends StatelessWidget {
  const _CharacterPortraitRail({
    required this.characters,
    required this.selected,
    required this.onSelect,
    this.isCooperating,
  });

  final List<NovelCharacter> characters;
  final NovelCharacter selected;
  final ValueChanged<NovelCharacter> onSelect;
  final bool Function(NovelCharacter character)? isCooperating;

  String _keyOf(NovelCharacter value) => value.id.trim().isNotEmpty
      ? value.id.trim()
      : value.name.trim();

  @override
  Widget build(BuildContext context) {
    final visibleCharacters =
        characters.where((character) => !character.isMain).toList();
    return ListView.separated(
      // 角色头像始终保持竖向列表；角色过多时从上往下滚动。
      scrollDirection: Axis.vertical,
      padding: const EdgeInsets.symmetric(vertical: 4),
      physics: const BouncingScrollPhysics(),
      itemCount: visibleCharacters.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final character = visibleCharacters[index];
        final active = _keyOf(character) == _keyOf(selected);
        final cooperating = !character.isMain &&
            (isCooperating?.call(character) ?? false);
        final fallbackAsset = character.gender.trim() == '女'
            ? 'assets/images/portrait_female.webp'
            : 'assets/images/portrait_male.png';
        final imageUrl = character.avatarUrl.trim().isNotEmpty
            ? character.avatarUrl
            : character.portraitUrl;
        return SizedBox(
          width: 46,
          height: 46,
          child: Center(
            child: Material(
              color: Colors.transparent,
              shape: const CircleBorder(),
              child: InkWell(
                onTap: () => onSelect(character),
                customBorder: const CircleBorder(),
                child: AnimatedScale(
                  scale: active ? 1.08 : 1,
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: <Widget>[
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: 36,
                        height: 36,
                        padding: EdgeInsets.all(active || cooperating ? 2 : 1),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: active
                                ? _characterGold
                                : cooperating
                                    ? _characterBlueBright
                                    : Colors.white.withOpacity(.12),
                          ),
                          boxShadow: active || cooperating
                              ? <BoxShadow>[
                                  BoxShadow(
                                    color: (cooperating
                                            ? _characterBlueBright
                                            : _characterBlue)
                                        .withOpacity(.38),
                                    blurRadius: cooperating ? 13 : 10,
                                    spreadRadius: cooperating ? 1 : 0,
                                  ),
                                ]
                              : const <BoxShadow>[],
                        ),
                        child: ClipOval(
                          child: NovelArtwork(
                            url: CdnUtil.resize(imageUrl, width: 140),
                            assetCandidates: <String>[
                              fallbackAsset,
                              'assets/images/portrait_female.webp',
                              'assets/images/portrait_male.png',
                            ],
                            fit: BoxFit.cover,
                            alignment: Alignment.topCenter,
                            fallbackText: '',
                            fallbackIcon: Icons.person_outline_rounded,
                          ),
                        ),
                      ),
                      if (cooperating)
                        Positioned(
                          right: -3,
                          bottom: -2,
                          child: Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              color: _characterBlueBright,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(0xFF101827),
                                width: 1.5,
                              ),
                            ),
                            child: const Icon(
                              Icons.link_rounded,
                              size: 9,
                              color: Colors.white,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ============================================================================
// 更换立绘小窗口 (替换全屏立绘页)
// ============================================================================

Future<void> showNovelPortraitModal(
  BuildContext context,
  NovelGameController controller,
  NovelCharacter character,
) async {
  await showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: '更换立绘',
    barrierColor: const Color(0xCC070B15), // 沉浸式深色遮罩
    transitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (context, _, __) {
      return Center(
        child: Material(
          color: Colors.transparent,
          child: _CharacterPortraitModalContent(
            controller: controller,
            character: character,
          ),
        ),
      );
    },
  );
}

class _CharacterPortraitModalContent extends StatefulWidget {
  const _CharacterPortraitModalContent({
    required this.controller,
    required this.character,
  });

  final NovelGameController controller;
  final NovelCharacter character;

  @override
  State<_CharacterPortraitModalContent> createState() =>
      _CharacterPortraitModalContentState();
}

class _CharacterPortraitModalContentState
    extends State<_CharacterPortraitModalContent> {
  late final TextEditingController _promptController;
  bool _generating = false;
  bool _uploading = false;
  String _errorText = '';
  late String _currentPortraitUrl;

  @override
  void initState() {
    super.initState();
    _promptController = TextEditingController();
    _currentPortraitUrl = widget.character.portraitUrl.isNotEmpty
        ? widget.character.portraitUrl
        : widget.character.avatarUrl;
  }

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  Future<void> _generatePortrait() async {
    if (_generating || _uploading) return;

    setState(() {
      _generating = true;
      _errorText = '';
    });

    try {
      final prompt = _promptController.text.trim();
      final result = await widget.controller.generatePortrait(
        character: widget.character,
        prompt: prompt,
        style: 'anime', 
      );

      await widget.controller.updateCharacterVisuals(
        character: widget.character,
        portraitUrl: result.portraitUrl,
        avatarUrl: result.avatarUrl,
      );
      widget.controller.clearMessages();
      await widget.controller.refreshCharacterStatus();

      if (mounted) {
        setState(() {
          _currentPortraitUrl = result.portraitUrl;
          _promptController.clear();
        });
        _showCharacterFloatingNotice(context, '立绘已更新');
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _errorText = error is NovelBackendException
              ? error.message
              : '生成失败：$error';
        });
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _pickAndApplyLocalPortrait() async {
    if (_generating || _uploading) return;

    final picked = await FilePicker.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: true,
    );
    final file = picked?.files.single;
    if (file == null || file.bytes == null) return;

    if (file.size > 12 * 1024 * 1024) {
      setState(() => _errorText = '图片请控制在 12MB 以内');
      return;
    }

    setState(() {
      _uploading = true;
      _errorText = '';
    });

    try {
      final portraitUrl = await widget.controller.uploadCharacterImage(
        bytes: file.bytes!,
        filename: file.name.isEmpty ? 'portrait.jpg' : file.name,
        contentType: _imageContentType(file.name), 
      );

      final avatarUrl = widget.character.avatarUrl.trim().isEmpty
          ? portraitUrl
          : widget.character.avatarUrl;

      await widget.controller.updateCharacterVisuals(
        character: widget.character,
        portraitUrl: portraitUrl,
        avatarUrl: avatarUrl,
      );
      widget.controller.clearMessages();
      await widget.controller.refreshCharacterStatus();

      if (mounted) {
        setState(() => _currentPortraitUrl = portraitUrl);
        _showCharacterFloatingNotice(context, '立绘已更新');
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _errorText = error is NovelBackendException
              ? error.message
              : '上传失败：$error';
        });
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fallbackAsset = widget.character.gender.trim() == '女'
        ? 'assets/images/portrait_female.webp'
        : 'assets/images/portrait_male.png';

    final media = MediaQuery.sizeOf(context);
    final landscape = media.width > media.height;
    final modalWidth = landscape
        ? math.min(520.0, media.width * .72)
        : math.min(320.0, media.width - 28);
    final modalHeight = landscape
        ? math.min(media.height * .90, 390.0)
        : math.min(560.0, media.height * .90);

    return Container(
      width: modalWidth,
      height: modalHeight,
      decoration: BoxDecoration(
        color: _characterInk,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 30,
            offset: const Offset(0, 15),
          ),
        ],
      ),
      child: Column(
        children: <Widget>[
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  NovelArtwork(
                    key: ValueKey(_currentPortraitUrl), 
                    url: CdnUtil.resize(_currentPortraitUrl, width: 600),
                    assetCandidates: <String>[
                      fallbackAsset,
                      'assets/images/portrait_female.webp',
                      'assets/images/portrait_male.png',
                    ],
                    fit: BoxFit.cover,
                    alignment: Alignment.topCenter,
                    fallbackText: '',
                    fallbackIcon: Icons.person_outline_rounded,
                  ),
                  if (_generating || _uploading)
                    ColoredBox(
                      color: Colors.black.withOpacity(0.5),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(
                              color: _characterGold,
                              strokeWidth: 2,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _generating ? 'AI 绘制中...' : '图片上传中...',
                              style: const TextStyle(
                                color: _characterGold,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
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
          
          Container(
            padding: const EdgeInsets.all(14),
            color: _characterInkSoft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  decoration: BoxDecoration(
                    color: _characterInk,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.white.withOpacity(0.06)),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: TextField(
                    controller: _promptController,
                    enabled: !_generating && !_uploading,
                    maxLines: 2,
                    style: const TextStyle(color: _characterText, fontSize: 11.5),
                    cursorColor: _characterGold,
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      border: InputBorder.none,
                      hintText: '输入额外形象要求 (留空按原设定生成)\n如：白发、赛博朋克风格、手持长剑...',
                      hintStyle: TextStyle(color: _characterTextMuted, fontSize: 10.5),
                    ),
                  ),
                ),
                
                if (_errorText.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    _errorText,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _characterHighStar, fontSize: 10),
                  ),
                ],
                
                const SizedBox(height: 12),
                
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _CharacterDetailButton(
                        label: 'AI 生成',
                        primary: true,
                        enabled: !_generating && !_uploading,
                        onTap: _generatePortrait,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _CharacterDetailButton(
                        label: '本地上传',
                        enabled: !_generating && !_uploading,
                        onTap: _pickAndApplyLocalPortrait,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CharacterHeroStage extends StatefulWidget {
  const _CharacterHeroStage({
    required this.controller,
    required this.character,
    required this.characters,
    required this.star,
    required this.fragments,
    required this.onSelect,
  });

  final NovelGameController controller;
  final NovelCharacter character;
  final List<NovelCharacter> characters;
  final int star;
  final int fragments;
  final ValueChanged<NovelCharacter> onSelect;

  @override
  State<_CharacterHeroStage> createState() => _CharacterHeroStageState();
}

class _CharacterHeroStageState extends State<_CharacterHeroStage> {
  late int _localStar;
  bool _upgrading = false;
  bool _showUpgradeFlash = false;
  int? _upgradeFromStar;
  bool _companionBusy = false;

  @override
  void initState() {
    super.initState();
    _localStar = widget.star;
  }

  @override
  void didUpdateWidget(covariant _CharacterHeroStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.character != widget.character || oldWidget.star != widget.star) {
      _localStar = widget.star;
    }
  }

  String _statusValue(List<String> keys) {
    for (final key in keys) {
      final value = widget.character.status[key];
      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString();
      }
    }
    return '—';
  }

  Widget _stars() {
    final secondStage = _localStar > 5;
    final visibleStars = secondStage ? _localStar - 5 : _localStar;
    return Wrap(
      spacing: 1,
      runSpacing: 2,
      children: List<Widget>.generate(5, (index) {
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 800), 
          switchInCurve: Curves.elasticOut, 
          transitionBuilder: (child, animation) {
            return ScaleTransition(
              scale: Tween<double>(begin: 0.2, end: 1.0).animate(animation),
              child: RotationTransition(
                turns: Tween<double>(begin: -0.25, end: 0).animate(
                  CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
                ),
                child: child,
              ),
            );
          },
          child: Icon(
            Icons.star_rounded,
            key: ValueKey<String>('${_localStar}_$index'),
            size: 10.5,
            color: index < visibleStars
                ? (secondStage ? _characterHighStar : _characterGold)
                : (secondStage
                    ? _characterHighStar.withOpacity(.18)
                    : _characterGoldSoft.withOpacity(.25)),
          ),
        );
      }),
    );
  }

  Widget _buildAnimatedInfoPanel(Widget panel) {
    return TweenAnimationBuilder<double>(
      key: ValueKey<int>(_localStar),
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 2200),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        final flash = 1.0 - value; 
        final textOpacity = flash > 0.3 ? 1.0 : (flash / 0.3);
        
        return Stack(
          clipBehavior: Clip.none,
          children: [
            child!,
            if (flash > 0 && _showUpgradeFlash)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.transparent,
                          _characterGold.withOpacity(0.22 * flash), 
                          Colors.transparent,
                        ],
                        stops: [
                          math.max(0.0, value - 0.2),
                          value,
                          math.min(1.0, value + 0.2),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            if (flash > 0 && _showUpgradeFlash)
              Positioned(
                right: 0,
                top: -10 - (60 * Curves.easeOutQuint.transform(value)),
                child: Opacity(
                  opacity: textOpacity,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.arrow_upward_rounded, 
                        color: _characterGold, 
                        size: 14 
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _upgradeFromStar == null
                            ? '升星成功 · 援战技能数值效果 ${100 + _localStar.clamp(0, 10) * 3}%'
                            : '升星成功 · 援战技能 ${100 + _upgradeFromStar!.clamp(0, 10) * 3}% → ${100 + _localStar.clamp(0, 10) * 3}%',
                        style: TextStyle(
                          color: _characterGold,
                          fontSize: 12.5, 
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                          shadows: [
                            Shadow(
                              color: _characterGold.withOpacity(0.8),
                              blurRadius: 10,
                            )
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
      child: panel,
    );
  }

  void _showCompanionMessage(String message) {
    _showCharacterFloatingNotice(context, message);
  }

  Future<void> _toggleCooperation() async {
    if (_companionBusy || widget.character.isMain) return;
    final id = widget.character.id.trim();
    if (id.isEmpty) return;
    final deployed = widget.controller.isNovelCompanionDeployed(id);
    if (!deployed && widget.controller.deployedNovelCompanionCount >= 3) {
      _showCompanionMessage('最多只能让 3 名角色进入协同状态');
      return;
    }
    setState(() => _companionBusy = true);
    try {
      await widget.controller.updateNovelCompanionDeployment(id, !deployed);
    } catch (error) {
      if (mounted) {
        _showCompanionMessage(
          error is NovelBackendException ? error.message : '协同状态更新失败：$error',
        );
      }
    } finally {
      if (mounted) setState(() => _companionBusy = false);
    }
  }

  Future<void> _nameCompanionSkill(JsonMap skill) async {
    if (_companionBusy || widget.character.isMain) return;
    final customNamed = boolValue(skill['custom_named']);

    // 已经领悟的技能改名：只做 rename，不再复用“首次领悟 + 推演预览”的流程。
    if (customNamed) {
      final oldName = stringValue(skill['name']).trim();
      final name = await _showCompanionSkillNamingDialog(
        context,
        skill,
        title: '修改技能名称',
        initialName: oldName,
        allowCancel: true,
        allowDiscard: false,
        confirmLabel: '确认修改',
      );
      final clean = name?.trim() ?? '';
      if (clean.isEmpty || !mounted || clean == oldName) return;

      setState(() => _companionBusy = true);
      try {
        await widget.controller.renameNovelCompanionSkill(
          characterInstanceId: widget.character.id,
          skillId: stringValue(skill['id']),
          name: clean,
        );
        if (mounted) _showCompanionMessage('技能已更名为「$clean」');
      } catch (error) {
        if (mounted) {
          _showCompanionMessage(
            error is NovelBackendException ? error.message : '技能改名失败：$error',
          );
        }
      } finally {
        if (mounted) setState(() => _companionBusy = false);
      }
      return;
    }

    // 新抽到的技能必须完成“命名并领悟”或真正确认舍弃。
    // 若误点舍弃后选择返回，则回到命名框并保留刚才的草稿。
    var draftName = '';
    while (mounted) {
      var latestDraft = draftName;
      final name = await _showCompanionSkillNamingDialog(
        context,
        skill,
        title: '学习到新技能',
        initialName: draftName,
        allowCancel: false,
        allowDiscard: true,
        onDraftChanged: (value) => latestDraft = value,
        confirmLabel: '命名并领悟',
      );
      draftName = latestDraft;
      if (name == null || !mounted) return;

      if (name == _companionSkillDiscardToken) {
        final skillName = stringValue(skill['name'], '该技能');
        final confirmed = await _confirmDiscardCompanionSkill(context, skillName);
        if (!mounted) return;
        if (confirmed != true) {
          continue;
        }
        await _discardCompanionSkillConfirmed(skill);
        return;
      }

      final clean = name.trim();
      if (clean.isEmpty) continue;
      setState(() => _companionBusy = true);
      try {
        await _finalizeCompanionSkillWithPreview(
          context: context,
          controller: widget.controller,
          character: widget.character,
          skill: skill,
          name: clean,
        );
      } finally {
        if (mounted) setState(() => _companionBusy = false);
      }
      return;
    }
  }

  Future<void> _learnCompanionSkill() async {
    if (_companionBusy || widget.character.isMain) return;
    final id = widget.character.id.trim();
    if (id.isEmpty) return;
    final skills = widget.controller.novelCompanionSkills(id);
    if (skills.length >= 4) {
      _showCompanionMessage('每名角色最多学习 4 个援战技能');
      return;
    }
    setState(() => _companionBusy = true);
    JsonMap? drawn;
    try {
      final payload = await widget.controller.drawNovelCompanionSkill(id);
      drawn = asJsonMap(payload['drawn_skill']);
    } catch (error) {
      if (mounted) {
        _showCompanionMessage(
          error is NovelBackendException ? error.message : '技能学习失败：$error',
        );
      }
    } finally {
      if (mounted) setState(() => _companionBusy = false);
    }
    if (drawn != null && drawn.isNotEmpty && mounted) {
      await _nameCompanionSkill(drawn);
    }
  }

  Future<void> _discardCompanionSkill(JsonMap skill) async {
    if (_companionBusy || widget.character.isMain) return;
    final skillName = stringValue(skill['name'], '该技能');
    final confirmed = await _confirmDiscardCompanionSkill(context, skillName);
    if (confirmed != true || !mounted) return;
    await _discardCompanionSkillConfirmed(skill);
  }

  Future<void> _discardCompanionSkillConfirmed(JsonMap skill) async {
    if (_companionBusy || widget.character.isMain || !mounted) return;
    final skillName = stringValue(skill['name'], '该技能');
    setState(() => _companionBusy = true);
    try {
      // 兼容现有控制器：后端把这个 UI 无法输入的保留名称解释为“舍弃技能”。
      await widget.controller.renameNovelCompanionSkill(
        characterInstanceId: widget.character.id,
        skillId: stringValue(skill['id']),
        name: _companionSkillDiscardToken,
      );
      if (mounted) _showCompanionMessage('已舍弃技能「$skillName」');
    } catch (error) {
      if (mounted) {
        _showCompanionMessage(
          error is NovelBackendException ? error.message : '舍弃技能失败：$error',
        );
      }
    } finally {
      if (mounted) setState(() => _companionBusy = false);
    }
  }

  Future<void> _openCompanionSkill(JsonMap skill) async {
    if (_companionBusy) return;
    final action = await _showCompanionSkillDetails(context, skill);
    if (!mounted) return;
    if (action == 'rename') {
      await _nameCompanionSkill(skill);
    } else if (action == 'discard') {
      await _discardCompanionSkill(skill);
    }
  }

  Future<void> _upgradeStar() async {
    if (_upgrading) return;
    if (_localStar >= 10) {
      _showCompanionMessage('该角色已达到满星');
      return;
    }
    if (widget.fragments < 20) {
      _showCompanionMessage('升星材料不足 · 角色碎片 ${widget.fragments}/20');
      return;
    }
    final id = widget.character.id.trim();
    if (id.isEmpty) {
      _showCompanionMessage('角色数据异常，暂时无法升星');
      return;
    }
    final previousStar = _localStar;
    setState(() => _upgrading = true);
    try {
      final payload = await widget.controller.upgradeNovelCharacter(id);
      if (!mounted) return;
      final nextStar = intValue(
        payload['star'],
        _localStar + 1,
      ).clamp(0, 10).toInt();
      setState(() {
        _upgradeFromStar = previousStar;
        _localStar = nextStar;
        _showUpgradeFlash = true;
      });
      Future<void>.delayed(const Duration(milliseconds: 2250), () {
        if (mounted) setState(() => _showUpgradeFlash = false);
      });
    } catch (error) {
      if (!mounted) return;
      final message = error is NovelBackendException
          ? error.message
          : '升星失败：$error';
      _showCharacterFloatingNotice(context, message);
    } finally {
      if (mounted) setState(() => _upgrading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fallbackAsset = widget.character.gender.trim() == '男'
        ? 'assets/images/portrait_male.png'
        : 'assets/images/portrait_female.webp';
    final imageUrl = widget.character.portraitUrl.trim().isNotEmpty
        ? widget.character.portraitUrl
        : widget.character.avatarUrl;
    final identity = stringValue(
      widget.character.status['identity'] ?? widget.character.persona['identity'],
    ).trim();
    final appearance = stringValue(
      widget.character.status['appearance'] ?? widget.character.persona['appearance'],
    ).trim();
    final stats = <MapEntry<String, String>>[
      MapEntry<String, String>('生命', _statusValue(<String>['hp', 'health', 'max_hp'])),
      MapEntry<String, String>('攻击', _statusValue(<String>['attack', 'strength'])),
      MapEntry<String, String>('防御', _statusValue(<String>['defense', 'tenacity'])),
      MapEntry<String, String>('好感', '${widget.character.affection}'),
    ];
    final companionSkills = widget.character.isMain
        ? const <JsonMap>[]
        : widget.controller.novelCompanionSkills(widget.character.id);
    final cooperating = !widget.character.isMain &&
        widget.controller.isNovelCompanionDeployed(widget.character.id);

    void openPortraitEditor() {
      showNovelPortraitModal(context, widget.controller, widget.character);
    }

    Widget infoPanel({required bool compact}) {
      final panel = compact
          ? _CharacterCompactMeta(
              character: widget.character,
              identity: identity,
              appearance: appearance,
              stars: _stars(),
              stats: stats,
              onChangePortrait: openPortraitEditor,
              star: _localStar,
              fragments: widget.fragments,
              onUpgrade: _upgradeStar,
              companionSkills: companionSkills,
              cooperating: cooperating,
              companionBusy: _companionBusy,
              onToggleCooperation:
                  widget.character.isMain ? null : _toggleCooperation,
              onLearn: widget.character.isMain ? null : _learnCompanionSkill,
              onRename: _openCompanionSkill,
            )
          : _CharacterStageInfo(
              character: widget.character,
              identity: identity,
              appearance: appearance,
              stars: _stars(),
              stats: stats,
              onChangePortrait: openPortraitEditor,
              star: _localStar,
              fragments: widget.fragments,
              onUpgrade: _upgradeStar,
              companionSkills: companionSkills,
              cooperating: cooperating,
              companionBusy: _companionBusy,
              onToggleCooperation:
                  widget.character.isMain ? null : _toggleCooperation,
              onLearn: widget.character.isMain ? null : _learnCompanionSkill,
              onRename: _openCompanionSkill,
            );
      return _buildAnimatedInfoPanel(panel);
    }

    Widget artwork(Alignment alignment) {
      return Hero(
        tag: 'character-stage-${widget.character.id}-${widget.character.name}',
        child: NovelArtwork(
          url: CdnUtil.resize(imageUrl, width: 1280),
          assetCandidates: <String>[
            fallbackAsset,
            'assets/images/portrait_female.webp',
            'assets/images/portrait_male.png',
          ],
          fit: BoxFit.contain,
          alignment: alignment,
          fallbackText: '',
          fallbackIcon: Icons.person_outline_rounded,
        ),
      );
    }

    Widget portraitRail() => _CharacterPortraitRail(
          characters: widget.characters,
          selected: widget.character,
          onSelect: widget.onSelect,
          isCooperating: (character) =>
              widget.controller.isNovelCompanionDeployed(character.id),
        );

    return LayoutBuilder(
      builder: (context, constraints) {
        final mode = _characterViewportMode(
          constraints,
          widget.controller.desktopMode,
        );
        final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
        final keyboardVisible = keyboardInset > 0;

        switch (mode) {
          case _CharacterViewportMode.desktop:
            final shortViewport = constraints.maxHeight < 620;
            final chatHeight = shortViewport ? 164.0 : 218.0;
            return ClipRect(
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  const Positioned.fill(
                    child: CustomPaint(painter: _CharacterOrbitPainter()),
                  ),
                  Positioned(
                    left: 68,
                    right: 318,
                    top: 0,
                    bottom: 0,
                    child: artwork(const Alignment(-0.35, 0)),
                  ),
                  Positioned(
                    left: 0,
                    top: 14,
                    bottom: 138,
                    width: 60,
                    child: portraitRail(),
                  ),
                  Positioned(
                    right: 26,
                    top: 24,
                    bottom: shortViewport ? 170 : 226,
                    width: 336,
                    child: infoPanel(compact: false),
                  ),
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    left: 140,
                    right: 382,
                    bottom: keyboardVisible ? keyboardInset + 8 : 8,
                    height: chatHeight,
                    child: _CharacterInlineChat(
                      controller: widget.controller,
                      character: widget.character,
                    ),
                  ),
                ],
              ),
            );

          case _CharacterViewportMode.landscape:
            // 手机横屏：聊天记录需要足够高度回看历史。
            // 默认占舞台高度约 70%，但仍保留合理上下限；
            // 底部输入框高度保持不变，横向只增加少量呼吸边距。
            const globalNavInset = 64.0;
            final chatHeight = (constraints.maxHeight * .70)
                .clamp(210.0, 340.0)
                .toDouble();
            final infoWidth = constraints.maxWidth < 760 ? 210.0 : 238.0;
            return ClipRect(
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  const Positioned.fill(
                    child: CustomPaint(painter: _CharacterOrbitPainter()),
                  ),
                  if (!keyboardVisible)
                    Positioned(
                      left: 0,
                      top: 44,
                      // 聊天记录只覆盖中间立绘区，不再把左侧头像轨向上挤。
                      // 仅避开最底部 34px 输入框。
                      bottom: 42,
                      width: 48,
                      child: portraitRail(),
                    ),
                  Positioned(
                    left: 48,
                    right: infoWidth + globalNavInset + 4,
                    top: 0,
                    // 横屏聊天记录改为覆盖在立绘下半部，因此立绘只需避开
                    // 最底部的输入框，不再为整块聊天记录让出高度。
                    bottom: 42,
                    child: artwork(const Alignment(-0.08, 0.12)),
                  ),
                  if (!keyboardVisible)
                    Positioned(
                      right: globalNavInset + 6,
                      top: 6,
                      // 记录区通过 messageRightInset 避开人物资料栏，
                      // 所以资料栏无需再为 70% 高的聊天记录让出纵向空间。
                      bottom: 42,
                      width: infoWidth,
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: infoPanel(compact: true),
                      ),
                    ),
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    // 横屏聊天整体留出左右呼吸空间，避免输入框贴住头像轨 / 右侧导航。
                    left: 18,
                    right: globalNavInset + 12,
                    bottom: keyboardVisible ? keyboardInset + 4 : 4,
                    height: chatHeight,
                    child: _CharacterInlineChat(
                      controller: widget.controller,
                      character: widget.character,
                      dense: true,
                      // 父聊天区现在从 x=18 开始；记录区再向内收一点，
                      // 最终比立绘左右边缘各留约 8px，阅读时不会贴边。
                      // 底部输入框不使用这两个 inset，只使用上面的整体左右留白。
                      messageLeftInset: 38,
                      messageRightInset: infoWidth,
                    ),
                  ),
                ],
              ),
            );

          case _CharacterViewportMode.portrait:
            // 手机竖屏保持独立构图和交互尺寸，不复用横屏的尺寸/定位。
            // 但聊天透明化与文字描边作为统一视觉规则同步应用。
            const globalNavInset = 64.0;
            const chatHeight = 250.0;
            return ClipRect(
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  const Positioned.fill(
                    child: CustomPaint(painter: _CharacterOrbitPainter()),
                  ),
                  Positioned(
                    left: -52,
                    right: 52,
                    top: 0,
                    bottom: 0,
                    child: artwork(const Alignment(-0.15, 0)),
                  ),
                  if (!keyboardVisible)
                    Positioned(
                      left: 0,
                      top: 8,
                      bottom: chatHeight + 128,
                      width: 52,
                      child: portraitRail(),
                    ),
                  if (!keyboardVisible)
                    Positioned(
                      right: 7,
                      top: 10,
                      width: 158,
                      child: infoPanel(compact: true),
                    ),
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    left: 8,
                    right: globalNavInset,
                    bottom: keyboardVisible ? keyboardInset + 8 : 8,
                    height: chatHeight,
                    child: _CharacterInlineChat(
                      controller: widget.controller,
                      character: widget.character,
                    ),
                  ),
                ],
              ),
            );
        }
      },
    );
  }
}

class _CharacterPortraitEditButton extends StatelessWidget {
  const _CharacterPortraitEditButton({
    required this.onTap,
    this.compact = false,
  });

  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(5),
        child: Container(
          height: compact ? 25 : 28,
          padding: EdgeInsets.symmetric(horizontal: compact ? 2 : 9),
          decoration: BoxDecoration(
            color: _characterInkSoft.withOpacity(.46),
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: Colors.white.withOpacity(.11)),
          ),
          child: Center(
            child: Text(
              '更换立绘',
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: TextStyle(
                color: _characterTextSoft,
                fontSize: compact ? 7.8 : 9.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CharacterProfileActions extends StatelessWidget {
  const _CharacterProfileActions({
    required this.star,
    required this.fragments,
    required this.onChangePortrait,
    required this.onUpgrade,
    this.compact = false,
  });

  final int star;
  final int fragments;
  final VoidCallback onChangePortrait;
  final VoidCallback onUpgrade;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final fullStar = star >= 10;
    final canUpgrade = !fullStar && fragments >= 20;
    final currentSkillEffect = 100 + star.clamp(0, 10) * 3;
    final nextSkillEffect = 100 + (star + 1).clamp(0, 10) * 3;
    return Container(
      padding: EdgeInsets.only(top: compact ? 7 : 11),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Colors.white.withOpacity(.09)),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                Icons.auto_awesome_rounded,
                size: compact ? 8.5 : 10.5,
                color: _characterGold.withOpacity(.92),
              ),
              SizedBox(width: compact ? 3 : 4),
              Expanded(
                child: Text(
                  fullStar
                      ? '援战技能数值效果 $currentSkillEffect% · 已达上限'
                      : '援战技能数值效果 $currentSkillEffect%  →  $nextSkillEffect%',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _characterGoldSoft.withOpacity(.94),
                    fontSize: compact ? 7.2 : 8.8,
                    fontWeight: FontWeight.w800,
                    letterSpacing: compact ? .15 : .3,
                  ),
                ),
              ),
              if (!fullStar)
                Text(
                  '每星 +3%',
                  style: TextStyle(
                    color: _characterTextMuted.withOpacity(.82),
                    fontSize: compact ? 6.8 : 8.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
          SizedBox(height: compact ? 5 : 7),
          Row(
            children: <Widget>[
              Expanded(
                child: _CharacterPortraitEditButton(
                  compact: compact,
                  onTap: onChangePortrait,
                ),
              ),
              SizedBox(width: compact ? 5 : 8),
              Expanded(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    // 碎片不足时仍允许点击，由 _upgradeStar() 本地提示；
                    // 只有材料充足才会真正向后端发送升星请求。
                    onTap: fullStar ? null : onUpgrade,
                    borderRadius: BorderRadius.circular(5),
                    child: Container(
                      height: compact ? 25 : 28,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(
                          color: Colors.white,
                        ),
                      ),
                      child: Text(
                        fullStar
                            ? '已满星 · 技能效果 130%'
                            : '升星  $fragments/20  ·  +3%',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: canUpgrade
                              ? const Color(0xFF161A18)
                              : const Color(0xFF8B908D),
                          fontSize: compact ? 7.2 : 9.1,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

const String _companionSkillDiscardToken = '__discard_skill__';

String _companionSkillEffectText(JsonMap skill) {
  for (final key in <String>[
    'effect_text',
    'effect_summary',
    'description',
    'effect',
  ]) {
    final value = stringValue(skill[key]).trim();
    if (value.isNotEmpty) return value;
  }
  final effects = skill['effects'];
  if (effects is List && effects.isNotEmpty) {
    final lines = <String>[];
    for (final raw in effects) {
      if (raw is Map) {
        final effect = asJsonMap(raw);
        final name = stringValue(
          effect['description'] ?? effect['name'] ?? effect['type'],
        ).trim();
        final value = stringValue(
          effect['value'] ?? effect['amount'] ?? effect['power'],
        ).trim();
        final duration = intValue(effect['duration_turns']);
        final parts = <String>[
          if (name.isNotEmpty) name,
          if (value.isNotEmpty) value,
          if (duration > 0) '持续 $duration 回合',
        ];
        if (parts.isNotEmpty) lines.add(parts.join(' · '));
      } else {
        final value = raw.toString().trim();
        if (value.isNotEmpty) lines.add(value);
      }
    }
    if (lines.isNotEmpty) return lines.join('\n');
  }
  return '该技能的具体效果将在战斗中生效';
}

String _companionSkillTypeOf(JsonMap skill) {
  var type = stringValue(skill['category']).trim().toLowerCase();
  if (type.isEmpty) {
    type = stringValue(asJsonMap(skill['battle_spec'])['archetype'])
        .trim()
        .toLowerCase();
  }
  if (type.isNotEmpty) return type;
  final effects = asJsonList(asJsonMap(skill['battle_spec'])['effects']);
  if (effects.isNotEmpty) {
    final effectType =
        stringValue(asJsonMap(effects.first)['type']).trim().toLowerCase();
    return switch (effectType) {
      'damage_over_time' => 'dot',
      'energy_restore' => 'energy',
      'next_attack_bonus' => 'expose',
      _ => effectType,
    };
  }
  return 'direct';
}

String _companionSkillTypeName(String type) => switch (type) {
      'direct' => '直击',
      'dot' => '持续伤害',
      'guard' => '守护',
      'evade' => '闪避',
      'heal' => '治疗',
      'energy' => '精力恢复',
      'lifesteal' => '吸血',
      'expose' => '破绽',
      'counter' => '反击',
      'stun' => '压制',
      _ => '攻击',
    };

String _companionSkillTypeAsset(String type) =>
    'assets/images/companion_skill_icons/${switch (type) {
      'direct' => 'direct',
      'dot' => 'dot',
      'guard' => 'guard',
      'evade' => 'evade',
      'heal' => 'heal',
      'energy' => 'energy',
      'lifesteal' => 'lifesteal',
      'expose' => 'expose',
      'counter' => 'counter',
      'stun' => 'stun',
      _ => 'direct',
    }}.webp';

IconData _companionSkillFallbackIcon(String type) => switch (type) {
      'direct' => Icons.flash_on_rounded,
      'dot' => Icons.local_fire_department_rounded,
      'guard' => Icons.shield_rounded,
      'evade' => Icons.air_rounded,
      'heal' => Icons.favorite_rounded,
      'energy' => Icons.bolt_rounded,
      'lifesteal' => Icons.bloodtype_rounded,
      'expose' => Icons.gps_fixed_rounded,
      'counter' => Icons.reply_rounded,
      'stun' => Icons.auto_awesome_rounded,
      _ => Icons.flash_on_rounded,
    };

Color _companionSkillQualityColor(int quality) =>
    switch (quality.clamp(1, 10)) {
      10 => const Color(0xFFFF5C7C),
      9 => const Color(0xFFFFCA62),
      8 => const Color(0xFFFF9D5C),
      7 => const Color(0xFFD979FF),
      6 => const Color(0xFFA88BFF),
      5 => const Color(0xFF5BD9F5),
      4 => const Color(0xFF64AEFF),
      3 => const Color(0xFF62D6B3),
      2 => const Color(0xFF91A9C7),
      _ => const Color(0xFFB9C5D6),
    };

class _CharacterGlassDialogFrame extends StatelessWidget {
  const _CharacterGlassDialogFrame({
    required this.width,
    required this.child,
  });

  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: const Color(0xA6101721),
        border: Border.all(
          color: Colors.white.withOpacity(.09),
          width: .8,
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withOpacity(.24),
            blurRadius: 32,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[
                      Colors.white.withOpacity(.075),
                      Colors.white.withOpacity(.018),
                      Colors.transparent,
                    ],
                    stops: const <double>[0, .28, 1],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: Container(height: .8, color: Colors.white.withOpacity(.12)),
          ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Container(width: .8, color: Colors.white.withOpacity(.08)),
          ),
          child,
        ],
      ),
    );
  }
}

class _CharacterDialogCloseButton extends StatelessWidget {
  const _CharacterDialogCloseButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(
            Icons.close,
            size: 16,
            color: _characterTextSoft.withOpacity(.74),
          ),
        ),
      ),
    );
  }
}

Future<String?> _showCompanionSkillNamingDialog(
  BuildContext context,
  JsonMap skill, {
  required String title,
  String initialName = '',
  bool allowCancel = false,
  bool allowDiscard = false,
  ValueChanged<String>? onDraftChanged,
  String? confirmLabel,
}) async {
  final editor = TextEditingController(text: initialName);
  final type = _companionSkillTypeOf(skill);
  final typeName = _companionSkillTypeName(type);
  final quality = intValue(skill['quality']).clamp(1, 10).toInt();
  final color = _companionSkillQualityColor(quality);
  final effectText = _companionSkillEffectText(skill);
  final result = await showDialog<String>(
    context: context,
    barrierDismissible: allowCancel,
    barrierColor: Colors.black.withOpacity(.20),
    builder: (dialogContext) => _CharacterDialogBackdrop(child: Dialog(
      elevation: 0,
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 26),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      child: _CharacterGlassDialogFrame(
        width: 350,
        child: Stack(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Padding(
                    padding: EdgeInsets.only(right: allowCancel ? 30 : 0),
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _characterText,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: .35,
                      ),
                    ),
                  ),
                  const SizedBox(height: 15),
                  Row(
                    children: <Widget>[
                      Image.asset(
                        _companionSkillTypeAsset(type),
                        width: 26,
                        height: 26,
                        color: color,
                        semanticLabel: typeName,
                        errorBuilder: (_, __, ___) => Icon(
                          _companionSkillFallbackIcon(type),
                          size: 26,
                          color: color,
                          semanticLabel: typeName,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        width: 14,
                        height: 1,
                        color: color.withOpacity(.58),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '$typeName · $quality 品',
                          style: TextStyle(
                            color: _characterTextSoft.withOpacity(.86),
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: .7,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (effectText.trim().isNotEmpty) ...<Widget>[
                    const SizedBox(height: 12),
                    Text(
                      effectText,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _characterTextMuted.withOpacity(.84),
                        fontSize: 10.5,
                        height: 1.58,
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(0, 6, 0, 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(.028),
                      border: Border(
                        bottom: BorderSide(
                          color: color.withOpacity(.62),
                          width: .9,
                        ),
                      ),
                    ),
                    child: TextField(
                      controller: editor,
                      autofocus: true,
                      maxLength: 7,
                      cursorColor: color,
                      style: const TextStyle(
                        color: _characterText,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        letterSpacing: .5,
                      ),
                      decoration: InputDecoration(
                        hintText: '输入技能名称',
                        hintStyle: TextStyle(
                          color: _characterTextMuted.withOpacity(.62),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                        counterText: '',
                        isDense: true,
                        filled: false,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.fromLTRB(0, 4, 0, 8),
                      ),
                      onChanged: onDraftChanged,
                      onSubmitted: (value) {
                        final clean = value.trim();
                        if (clean.isNotEmpty) Navigator.of(dialogContext).pop(clean);
                      },
                    ),
                  ),
                  if (allowDiscard) ...<Widget>[
                    const SizedBox(height: 10),
                    Text(
                      '不想保留这次技能可以直接舍弃；已消耗的技能书不会返还。',
                      style: TextStyle(
                        color: _characterTextMuted.withOpacity(.70),
                        fontSize: 9.8,
                        height: 1.45,
                      ),
                    ),
                  ],
                  const SizedBox(height: 13),
                  Row(
                    children: <Widget>[
                      if (allowDiscard) ...<Widget>[
                        _CharacterSkillDialogAction(
                          label: '舍弃',
                          foreground: _characterTextMuted.withOpacity(.88),
                          fillColor: Colors.white.withOpacity(.018),
                          borderColor: Colors.white.withOpacity(.10),
                          onTap: () => Navigator.of(dialogContext).pop(
                            _companionSkillDiscardToken,
                          ),
                        ),
                        const Spacer(),
                      ] else
                        const Spacer(),
                      if (allowCancel) ...<Widget>[
                        _CharacterSkillDialogAction(
                          label: '取消',
                          foreground: _characterTextMuted.withOpacity(.92),
                          fillColor: Colors.white.withOpacity(.025),
                          borderColor: Colors.white.withOpacity(.10),
                          onTap: () => Navigator.of(dialogContext).pop(),
                        ),
                        const SizedBox(width: 14),
                      ],
                      _CharacterSkillDialogAction(
                        label: confirmLabel ?? (initialName.trim().isEmpty ? '命名并领悟' : '确认修改'),
                        foreground: _characterText,
                        fillColor: color.withOpacity(.13),
                        borderColor: color.withOpacity(.42),
                        onTap: () {
                          final clean = editor.text.trim();
                          if (clean.isNotEmpty) {
                            Navigator.of(dialogContext).pop(clean);
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (allowCancel)
              Positioned(
                right: 0,
                top: 0,
                child: _CharacterDialogCloseButton(
                  onTap: () => Navigator.of(dialogContext).pop(),
                ),
              ),
          ],
        ),
      ),
    )),
  );
  editor.dispose();
  return result;
}


Future<void> _finalizeCompanionSkillWithPreview({
  required BuildContext context,
  required NovelGameController controller,
  required NovelCharacter character,
  required JsonMap skill,
  required String name,
}) async {
  final skillId = stringValue(skill['id']).trim();
  if (skillId.isEmpty || name.trim().isEmpty) return;

  JsonMap responseSkill = const <String, dynamic>{};
  JsonMap responseVfx = const <String, dynamic>{};
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withOpacity(.32),
    builder: (dialogContext) => _CharacterDialogBackdrop(child: _CompanionSkillEvolutionDialog(
      skillName: name.trim(),
      seedSkill: <String, dynamic>{...skill, 'name': name.trim()},
      onGenerate: () async {
        // 用 dynamic 兼容旧控制器 Future<void> 与新版 Future<JsonMap> 两种签名。
        final dynamic rawPayload = await (controller as dynamic).renameNovelCompanionSkill(
          characterInstanceId: character.id,
          skillId: skillId,
          name: name.trim(),
        );
        final payload = asJsonMap(rawPayload);
        responseSkill = asJsonMap(payload['renamed_skill']);
        responseVfx = asJsonMap(payload['vfx_spec']);
      },
      resolveSkill: () {
        if (responseSkill.isNotEmpty) return responseSkill;
        final skills = controller.novelCompanionSkills(character.id);
        for (final candidate in skills) {
          if (stringValue(candidate['id']).trim() == skillId) {
            return candidate;
          }
        }
        return <String, dynamic>{
          ...skill,
          'name': name.trim(),
          if (responseVfx.isNotEmpty) 'vfx_spec': responseVfx,
        };
      },
    )),
  );
}

class _CompanionSkillEvolutionDialog extends StatefulWidget {
  const _CompanionSkillEvolutionDialog({
    required this.skillName,
    required this.seedSkill,
    required this.onGenerate,
    required this.resolveSkill,
  });

  final String skillName;
  final JsonMap seedSkill;
  final Future<void> Function() onGenerate;
  final JsonMap Function() resolveSkill;

  @override
  State<_CompanionSkillEvolutionDialog> createState() =>
      _CompanionSkillEvolutionDialogState();
}

class _CompanionSkillEvolutionDialogState
    extends State<_CompanionSkillEvolutionDialog> {
  bool _loading = true;
  String _error = '';
  JsonMap _skill = const <String, dynamic>{};
  int _replayToken = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_generate());
  }

  Future<void> _generate() async {
    if (!_loading && _error.isEmpty) return;
    setState(() {
      _loading = true;
      _error = '';
    });
    final startedAt = DateTime.now();
    try {
      await widget.onGenerate();
      final elapsed = DateTime.now().difference(startedAt);
      if (elapsed < const Duration(milliseconds: 720)) {
        await Future<void>.delayed(
          const Duration(milliseconds: 720) - elapsed,
        );
      }
      if (!mounted) return;
      final resolved = widget.resolveSkill();
      setState(() {
        _skill = resolved.isNotEmpty
            ? resolved
            : <String, dynamic>{
                ...widget.seedSkill,
                'name': widget.skillName,
              };
        _loading = false;
        _replayToken++;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error is NovelBackendException
            ? error.message
            : '技能推演失败：$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final skill = _skill.isNotEmpty
        ? _skill
        : <String, dynamic>{
            ...widget.seedSkill,
            'name': widget.skillName,
          };
    final quality = intValue(skill['quality']).clamp(1, 10).toInt();
    final color = _companionSkillQualityColor(quality);
    final media = MediaQuery.sizeOf(context);
    final width = math.min(430.0, media.width - 30);

    return Dialog(
      elevation: 0,
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 15),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      child: _CharacterGlassDialogFrame(
        width: width,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 320),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: _loading
              ? _buildLoading(color)
              : _error.isNotEmpty
                  ? _buildError(color)
                  : _buildPreview(skill, quality, color),
        ),
      ),
    );
  }

  Widget _buildLoading(Color color) {
    return Padding(
      key: const ValueKey<String>('vfx-loading'),
      padding: const EdgeInsets.fromLTRB(28, 30, 28, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(
            width: 92,
            height: 92,
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: .72, end: 1.0),
                  duration: const Duration(milliseconds: 850),
                  curve: Curves.easeInOut,
                  builder: (_, value, child) => Transform.scale(
                    scale: value,
                    child: child,
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: color.withOpacity(.42)),
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: color.withOpacity(.22),
                          blurRadius: 28,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  width: 48,
                  height: 48,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.6,
                    color: color,
                    backgroundColor: Colors.white.withOpacity(.04),
                  ),
                ),
                Icon(Icons.auto_awesome_rounded, color: color, size: 21),
              ],
            ),
          ),
          const SizedBox(height: 22),
          Text(
            '正在推演「${widget.skillName}」',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _characterText,
              fontSize: 16,
              fontWeight: FontWeight.w900,
              letterSpacing: .6,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '根据技能名称与真实效果凝聚招式表现…',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _characterTextMuted.withOpacity(.86),
              fontSize: 10.5,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(Color color) {
    return Padding(
      key: const ValueKey<String>('vfx-error'),
      padding: const EdgeInsets.fromLTRB(26, 26, 26, 22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            '技能推演未完成',
            style: TextStyle(
              color: _characterText,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _error,
            style: const TextStyle(
              color: _characterHighStar,
              fontSize: 11,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: <Widget>[
              _CharacterSkillDialogAction(
                label: '返回',
                foreground: _characterTextMuted,
                fillColor: Colors.white.withOpacity(.025),
                borderColor: Colors.white.withOpacity(.10),
                onTap: () => Navigator.of(context).pop(),
              ),
              const Spacer(),
              _CharacterSkillDialogAction(
                label: '重新推演',
                foreground: _characterText,
                fillColor: color.withOpacity(.13),
                borderColor: color.withOpacity(.42),
                onTap: _generate,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPreview(JsonMap skill, int quality, Color color) {
    final type = _companionSkillTypeOf(skill);
    final typeName = _companionSkillTypeName(type);
    return Padding(
      key: const ValueKey<String>('vfx-preview'),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withOpacity(.10),
                  border: Border.all(color: color.withOpacity(.42)),
                ),
                child: Icon(
                  Icons.auto_awesome_rounded,
                  size: 17,
                  color: color,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      stringValue(skill['name'], widget.skillName),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _characterText,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$typeName · $quality 品 · 技能已成',
                      style: TextStyle(
                        color: color.withOpacity(.92),
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: .65,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            height: 218,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: const Color(0xFF050711),
              border: Border.all(color: Colors.white.withOpacity(.08)),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: color.withOpacity(.11),
                  blurRadius: 22,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: _CompanionSkillVfxPreview(
              key: ValueKey<String>(
                '${stringValue(skill['id'])}-${stringValue(skill['name'])}-$_replayToken',
              ),
              skill: skill,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _companionSkillEffectText(skill),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _characterTextMuted.withOpacity(.86),
              fontSize: 10.5,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              _CharacterSkillDialogAction(
                label: '再看一次',
                foreground: _characterTextSoft,
                fillColor: Colors.white.withOpacity(.025),
                borderColor: Colors.white.withOpacity(.10),
                onTap: () => setState(() => _replayToken++),
              ),
              const Spacer(),
              _CharacterSkillDialogAction(
                label: '确定',
                foreground: _characterText,
                fillColor: color.withOpacity(.14),
                borderColor: color.withOpacity(.48),
                onTap: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

double _companionVfxDouble(dynamic value, [double fallback = 0]) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? fallback;
}

JsonMap _fallbackCompanionVfxSpec(JsonMap skill) {
  final name = stringValue(skill['name']).toLowerCase();
  final description = _companionSkillEffectText(skill).toLowerCase();
  final text = '$name $description';
  final type = _companionSkillTypeOf(skill);
  final quality = intValue(skill['quality']).clamp(1, 10).toInt();

  String element = 'arcane';
  String palette = 'violet';
  if (<String>['冰', '霜', '雪', '寒'].any(text.contains)) {
    element = 'ice';
    palette = 'ice_blue';
  } else if (<String>['雷', '电', '霆'].any(text.contains)) {
    element = 'lightning';
    palette = 'violet';
  } else if (<String>['火', '炎', '焰', '燃', '莲'].any(text.contains)) {
    element = 'fire';
    palette = 'flame';
  } else if (<String>['风', '岚'].any(text.contains)) {
    element = 'wind';
    palette = 'emerald';
  } else if (<String>['圣', '光', '辉'].any(text.contains)) {
    element = 'light';
    palette = 'gold';
  } else if (<String>['暗', '影', '幽', '冥'].any(text.contains)) {
    element = 'dark';
    palette = 'shadow';
  }

  final sequence = <JsonMap>[];
  if (quality >= 8) {
    sequence.add(<String, dynamic>{
      'type': 'darken', 'at': 0.0, 'duration': .42, 'scale': 1.0,
      'amount': 1, 'direction': 'center',
    });
  }
  sequence.add(<String, dynamic>{
    'type': 'charge', 'at': .05, 'duration': .35, 'scale': .9,
    'amount': 2, 'direction': 'center',
  });

  if (<String>['heal', 'energy'].contains(type)) {
    sequence.add(<String, dynamic>{
      'type': 'heal_ring', 'at': .28, 'duration': .48, 'scale': 1.0,
      'amount': 3, 'direction': 'radial',
    });
    sequence.add(<String, dynamic>{
      'type': 'aura', 'at': .45, 'duration': .45, 'scale': 1.1,
      'amount': 3, 'direction': 'center',
    });
  } else if (type == 'guard') {
    sequence.add(<String, dynamic>{
      'type': 'shield', 'at': .28, 'duration': .5, 'scale': 1.0,
      'amount': 2, 'direction': 'center',
    });
  } else if (type == 'evade') {
    sequence.add(<String, dynamic>{
      'type': 'afterimage', 'at': .25, 'duration': .45, 'scale': 1.0,
      'amount': 4, 'direction': 'left_to_right',
    });
  } else {
    sequence.add(<String, dynamic>{
      'type': name.contains('龙')
          ? 'dragon_trail'
          : name.contains('莲')
              ? 'lotus'
              : <String>['斩', '刀', '剑'].any(name.contains)
                  ? 'slash'
                  : 'projectile',
      'at': .28,
      'duration': .4,
      'scale': 1.1,
      'amount': 4,
      'direction': 'left_to_right',
    });
    if (element == 'lightning') {
      sequence.add(<String, dynamic>{
        'type': 'lightning', 'at': .42, 'duration': .35, 'scale': 1.0,
        'amount': 4, 'direction': 'radial',
      });
    } else if (element == 'ice') {
      sequence.add(<String, dynamic>{
        'type': 'ice_shards', 'at': .45, 'duration': .35, 'scale': 1.0,
        'amount': 4, 'direction': 'radial',
      });
    } else if (element == 'fire') {
      sequence.add(<String, dynamic>{
        'type': 'fire_particles', 'at': .42, 'duration': .4, 'scale': 1.0,
        'amount': 4, 'direction': 'radial',
      });
    }
    sequence.add(<String, dynamic>{
      'type': quality >= 8 ? 'explosion' : 'shockwave',
      'at': .62, 'duration': .3, 'scale': 1.15,
      'amount': 3, 'direction': 'radial',
    });
  }

  return <String, dynamic>{
    'schema_version': 1,
    'element': element,
    'style': quality >= 8 ? 'ultimate' : 'burst',
    'palette': palette,
    'intensity': quality,
    'duration_ms': quality >= 8 ? 1750 : 1050 + quality * 45,
    'sequence': sequence.take(6).toList(),
    'caption': stringValue(skill['name']),
    'source': 'local_fallback',
  };
}

JsonMap _companionSkillVfxSpec(JsonMap skill) {
  final raw = asJsonMap(skill['vfx_spec']);
  return _sanitizeCompanionVfxSpec(raw.isNotEmpty ? raw : _fallbackCompanionVfxSpec(skill));
}

Color _companionVfxPalette(String palette) => switch (palette) {
      'ice_blue' => const Color(0xFF83E7FF),
      'flame' => const Color(0xFFFF7A2C),
      'emerald' => const Color(0xFF6DE6B4),
      'gold' => const Color(0xFFFFD873),
      'crimson' => const Color(0xFFFF5C67),
      'shadow' => const Color(0xFF9670C9),
      'white' => const Color(0xFFF5F3FF),
      _ => const Color(0xFFB779FF),
    };

const Set<String> _companionVfxHumanTokens = <String>{
  'human', 'humanoid', 'person', 'body', 'face', 'head', 'arm', 'leg', 'hand', 'foot',
  'warrior', 'swordsman', 'samurai', 'ninja', 'knight', 'fighter', 'character',
  'figure', 'stick', 'stickman', 'silhouette', 'man', 'woman', 'girl', 'boy', 'hero', 'avatar',
};

bool _companionVfxLooksHuman(dynamic value) {
  final text = '${value ?? ''}'.trim().toLowerCase();
  if (text.isEmpty) return false;
  return _companionVfxHumanTokens.any(text.contains);
}

JsonMap _sanitizeCompanionVfxSpec(JsonMap raw) {
  if (raw.isEmpty) return const <String, dynamic>{};
  final spec = Map<String, dynamic>.from(raw);
  final identity = '${spec['visual_identity'] ?? ''}'.trim().toLowerCase();
  if (_companionVfxLooksHuman(identity) || identity == 'transformation') {
    spec['visual_identity'] = 'elemental_construct';
  }
  final rawSequence = spec['sequence'];
  if (rawSequence is List) {
    final filtered = <JsonMap>[];
    for (final rawItem in rawSequence.take(12)) {
      final item = asJsonMap(rawItem);
      if (item.isEmpty) continue;
      final blocked = _companionVfxLooksHuman(item['type']) ||
          _companionVfxLooksHuman(item['shape']) ||
          _companionVfxLooksHuman(item['motion']) ||
          _companionVfxLooksHuman(item['path']) ||
          _companionVfxLooksHuman(item['origin']) ||
          _companionVfxLooksHuman(item['role']) ||
          _companionVfxLooksHuman(item['subject']) ||
          _companionVfxLooksHuman(item['subject_type']);
      if (blocked) continue;
      filtered.add(item);
    }
    spec['sequence'] = filtered;
  }
  return Map<String, dynamic>.unmodifiable(spec);
}

class _CompanionSkillVfxPreview extends StatefulWidget {
  const _CompanionSkillVfxPreview({
    super.key,
    required this.skill,
    this.tapToReplay = true,
    this.showReplayHint = false,
  });

  final JsonMap skill;
  final bool tapToReplay;
  final bool showReplayHint;

  @override
  State<_CompanionSkillVfxPreview> createState() =>
      _CompanionSkillVfxPreviewState();
}

class _CompanionSkillVfxPreviewState extends State<_CompanionSkillVfxPreview>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late JsonMap _spec;

  @override
  void initState() {
    super.initState();
    _spec = _companionSkillVfxSpec(widget.skill);
    final duration = intValue(_spec['duration_ms'], 1200).clamp(550, 3000).toInt();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: duration),
    )..forward();
  }

  @override
  void didUpdateWidget(covariant _CompanionSkillVfxPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.skill, widget.skill)) return;
    _spec = _companionSkillVfxSpec(widget.skill);
    final duration = intValue(_spec['duration_ms'], 1200).clamp(550, 3000).toInt();
    _controller.duration = Duration(milliseconds: duration);
    _controller.forward(from: 0);
  }

  void _replay() {
    if (!widget.tapToReplay) return;
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.tapToReplay ? _replay : null,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (_, __) => CustomPaint(
          painter: _CompanionSkillVfxPainter(
            spec: _spec,
            progress: _controller.value,
          ),
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              Align(
                alignment: const Alignment(0, .72),
                child: Opacity(
                  opacity: (_controller.value * 2.4).clamp(0.0, 1.0).toDouble(),
                  child: Text(
                    stringValue(_spec['caption'], stringValue(widget.skill['name'])),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withOpacity(.82),
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2.2,
                      shadows: const <Shadow>[Shadow(color: Colors.black, blurRadius: 8)],
                    ),
                  ),
                ),
              ),
              if (widget.showReplayHint)
                Positioned(
                  right: 8,
                  bottom: 7,
                  child: IgnorePointer(
                    child: Text(
                      '点击重播',
                      style: TextStyle(
                        color: Colors.white.withOpacity(.34),
                        fontSize: 8.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: .7,
                      ),
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


class _CompanionSkillVfxPainter extends CustomPainter {
  const _CompanionSkillVfxPainter({required this.spec, required this.progress});

  final JsonMap spec;
  final double progress;

  Color get accent => _companionVfxPalette(stringValue(spec['palette']));

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF050711));
    final caster = Offset(size.width * .27, size.height * .50);
    final target = Offset(size.width * .72, size.height * .46);
    final center = Offset(size.width * .5, size.height * .46);
    final ambience = Paint()
      ..shader = RadialGradient(
        colors: <Color>[accent.withOpacity(.035), accent.withOpacity(0)],
      ).createShader(Rect.fromCircle(center: center, radius: size.width * .50));
    canvas.drawRect(Offset.zero & size, ambience);
    _CompanionVfxGraphRenderer(
      spec: Map<String, dynamic>.from(spec),
      progress: progress,
      accent: accent,
    ).paint(canvas, size, caster: caster, target: target);
  }

  @override
  bool shouldRepaint(covariant _CompanionSkillVfxPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.spec != spec;
}


class _CompanionVfxGraphRenderer {
  const _CompanionVfxGraphRenderer({
    required this.spec,
    required this.progress,
    required this.accent,
  });

  final Map<String, dynamic> spec;
  final double progress;
  final Color accent;

  Map<String, dynamic> _map(dynamic value) {
    if (value is! Map) return const <String, dynamic>{};
    return value.map((key, item) => MapEntry('$key', item));
  }

  double _d(dynamic value, [double fallback = 0]) {
    if (value is num) return value.toDouble();
    return double.tryParse('${value ?? ''}') ?? fallback;
  }

  int _i(dynamic value, [int fallback = 0]) {
    if (value is num) return value.round();
    return int.tryParse('${value ?? ''}') ?? fallback;
  }

  String _s(dynamic value, [String fallback = '']) {
    final text = '${value ?? ''}'.trim();
    return text.isEmpty ? fallback : text;
  }

  double _clamp01(double value) => value.clamp(0.0, 1.0).toDouble();

  double _easeOut(double t) {
    final x = _clamp01(t);
    return 1 - math.pow(1 - x, 3).toDouble();
  }

  double _easeInOut(double t) {
    final x = _clamp01(t);
    return x < .5
        ? 4 * x * x * x
        : 1 - math.pow(-2 * x + 2, 3).toDouble() / 2;
  }

  double _pulse(double t) => math.sin(_clamp01(t) * math.pi);

  double _seed01(int index, int salt, int seed) {
    final x = math.sin((index + seed * .071) * 12.9898 + salt * 78.233) * 43758.5453;
    return x - x.floorToDouble();
  }

  Paint _stroke(Color color, double opacity, double width, {double blur = 0}) {
    final paint = Paint()
      ..color = color.withOpacity(_clamp01(opacity))
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(.35, width)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    if (blur > .01) {
      paint.maskFilter = MaskFilter.blur(BlurStyle.normal, blur);
    }
    return paint;
  }

  Paint _fill(Color color, double opacity, {double blur = 0, bool additive = false}) {
    final paint = Paint()
      ..color = color.withOpacity(_clamp01(opacity))
      ..style = PaintingStyle.fill;
    if (blur > .01) paint.maskFilter = MaskFilter.blur(BlurStyle.normal, blur);
    if (additive) paint.blendMode = BlendMode.plus;
    return paint;
  }

  void _layeredPath(
    Canvas canvas,
    Path path,
    Color color,
    double opacity,
    double width, {
    double glow = 4,
    bool whiteCore = true,
  }) {
    if (glow > .01) {
      canvas.drawPath(path, _stroke(color, opacity * .17, width * 2.5, blur: glow));
    }
    canvas.drawPath(path, _stroke(color, opacity * .78, width));
    if (whiteCore) {
      canvas.drawPath(path, _stroke(Colors.white, opacity * .78, math.max(.6, width * .20)));
    }
  }

  Offset _originFor(Map<String, dynamic> item, Size size, Offset caster, Offset target) {
    switch (_s(item['origin'], 'target').toLowerCase()) {
      case 'caster':
        return caster;
      case 'center':
        return Offset(size.width * .5, size.height * .44);
      case 'sky':
        return Offset(target.dx, size.height * .08);
      case 'ground':
        return Offset(target.dx, size.height * .72);
      default:
        return target;
    }
  }

  double _directionAngle(String direction, double randomAngle) {
    switch (direction) {
      case 'left_to_right':
        return 0;
      case 'right_to_left':
        return math.pi;
      case 'up':
        return -math.pi / 2;
      case 'down':
        return math.pi / 2;
      default:
        return randomAngle;
    }
  }

  List<dynamic> _renderSequence() {
    final raw = spec['sequence'];
    final original = raw is List ? raw : const <dynamic>[];
    if (_i(spec['schema_version'], 1) >= 3) return original;

    // Legacy V1/V2 specs used only a few coarse primitives. Upgrade them locally so
    // already-owned skills immediately benefit from V3 without another LLM request.
    final caption = _s(spec['caption']).toLowerCase();
    final element = _s(spec['element'], 'arcane').toLowerCase();
    final style = _s(spec['style'], 'burst').toLowerCase();
    final intensity = _i(spec['intensity'], 4).clamp(1, 10).toInt();
    final seed = caption.runes.fold<int>(17, (value, rune) => ((value * 31) + rune) & 0x7fffffff) % 10000;
    final particles = math.min(120, 30 + intensity * 8);

    Map<String, dynamic> n(
      String type,
      double at,
      double duration, {
      double scale = 1,
      int amount = 4,
      String direction = 'center',
      String shape = 'spark',
      String motion = 'radial',
      String path = 'straight',
      String origin = 'target',
      int particleCount = 0,
      double speed = .7,
      double spread = .6,
      double gravity = 0,
      double trail = .3,
      double glow = .35,
      int variant = 0,
      int salt = 0,
    }) => <String, dynamic>{
      'type': type, 'at': at, 'duration': duration, 'scale': scale,
      'amount': amount, 'direction': direction, 'shape': shape, 'motion': motion,
      'path': path, 'origin': origin, 'particle_count': particleCount,
      'speed': speed, 'spread': spread, 'gravity': gravity, 'trail': trail,
      'glow': glow, 'variant': variant, 'seed': (seed + salt) % 10000,
    };

    if (caption.contains('龙')) {
      return <dynamic>[
        if (intensity >= 8) n('darken', 0, .30, amount: 1, salt: 1),
        n('sigil', .02, .28, origin: 'caster', amount: 5, variant: seed % 6, salt: 2),
        n('dragon_trail', .16, .54, scale: 1.18, amount: 7, direction: 'left_to_right', path: 'serpentine', shape: element == 'ice' ? 'snow' : 'spark', particleCount: particles, trail: .82, glow: .52, salt: 3),
        n('particle_burst', .60, .28, scale: 1.2, particleCount: math.min(120, particles + 24), shape: element == 'ice' ? 'shard' : 'streak', motion: 'radial', speed: 1.05, spread: .95, gravity: element == 'ice' ? .18 : 0, trail: .48, glow: .42, salt: 4),
        n('impact_lines', .61, .18, scale: 1.3, amount: 9, salt: 5),
      ];
    }
    if (caption.contains('莲')) {
      return <dynamic>[
        n('energy_orb', .02, .26, origin: 'center', particleCount: 24, shape: 'ember', motion: 'converge', glow: .58, salt: 6),
        n('lotus', .16, .47, origin: 'center', scale: 1.18, amount: 8, variant: seed % 6, salt: 7),
        n('rune_ring', .20, .40, origin: 'center', scale: 1.32, amount: 6, variant: (seed + 2) % 6, salt: 8),
        n('petal_burst', .46, .32, origin: 'center', particleCount: math.min(100, particles), shape: 'petal', motion: 'swirl', speed: .78, spread: .88, gravity: -.06, glow: .40, salt: 9),
        n('particle_burst', .62, .28, origin: 'center', particleCount: math.min(120, particles + 28), shape: 'ember', motion: 'radial', speed: 1.1, spread: 1, trail: .38, glow: .52, salt: 10),
        n('impact_lines', .63, .18, origin: 'center', scale: 1.3, amount: 9, salt: 11),
      ];
    }
    if (style == 'slash' || <String>['斩', '刀', '剑', '刃'].any((token) => caption.contains(token))) {
      return <dynamic>[
        if (intensity >= 8) n('darken', 0, .28, amount: 1, salt: 12),
        if (element == 'lightning' || intensity >= 8) n('sigil', .02, .28, origin: 'center', amount: 5, variant: seed % 6, salt: 13),
        n('blade_manifest', .14, .34, origin: 'caster', scale: 1.16, particleCount: 22 + intensity * 3, shape: 'blade', motion: 'converge', glow: .54, salt: 14),
        n('slash', .42, .18, scale: 1.35, amount: 6, direction: 'left_to_right', path: seed.isEven ? 'crescent' : 'arc', trail: .78, glow: .54, salt: 15),
        n('particle_burst', .48, .28, particleCount: math.min(120, particles + 24), shape: 'streak', motion: 'cone', speed: 1.1, spread: .84, trail: .72, glow: .44, salt: 16),
        n('impact_lines', .49, .17, scale: 1.35, amount: 10, salt: 17),
        if (intensity >= 8) n('space_crack', .54, .38, scale: 1.2, amount: 8, path: 'zigzag', glow: .48, salt: 18),
        if (element == 'lightning') n('lightning', .57, .32, scale: 1.22, amount: 8, motion: 'scatter', salt: 19),
      ];
    }
    if (element == 'lightning') {
      return <dynamic>[
        n('sigil', .03, .30, origin: 'caster', amount: 6, variant: seed % 6, salt: 20),
        n('trail', .16, .42, origin: 'caster', direction: 'left_to_right', path: 'zigzag', particleCount: math.min(100, particles), shape: 'streak', motion: 'stream', speed: .96, spread: .32, trail: .74, glow: .38, salt: 21),
        n('lightning', .38, .36, amount: 9, motion: 'scatter', glow: .48, salt: 22),
        n('particle_burst', .58, .26, particleCount: math.min(120, particles + 18), shape: 'streak', motion: 'radial', speed: 1.02, spread: .92, trail: .58, glow: .42, salt: 23),
        n('impact_lines', .59, .18, amount: 10, scale: 1.25, salt: 24),
      ];
    }
    if (element == 'ice') {
      return <dynamic>[
        n('rune_ring', .03, .30, origin: 'caster', amount: 5, variant: seed % 6, salt: 25),
        n('trail', .16, .44, origin: 'caster', direction: 'left_to_right', path: 'wave', particleCount: math.min(90, particles), shape: 'snow', motion: 'stream', speed: .82, spread: .42, trail: .52, glow: .30, salt: 26),
        n('particle_burst', .56, .30, particleCount: math.min(120, particles + 20), shape: 'shard', motion: 'radial', speed: .98, spread: .95, gravity: .20, trail: .38, glow: .34, salt: 27),
        n('ground_crack', .58, .30, amount: 8, scale: 1.1, salt: 28),
        n('shockwave', .59, .23, scale: 1.25, amount: 5, salt: 29),
      ];
    }
    if (element == 'fire') {
      return <dynamic>[
        n('energy_orb', .03, .28, origin: 'caster', particleCount: 26 + intensity * 3, shape: 'ember', motion: 'converge', glow: .58, salt: 30),
        n('beam', .24, .42, origin: 'caster', direction: 'left_to_right', path: seed % 3 == 0 ? 'wave' : 'straight', particleCount: math.min(90, particles), shape: 'streak', motion: 'stream', speed: .96, spread: .26, trail: .70, glow: .52, salt: 31),
        n('particle_burst', .59, .28, particleCount: math.min(120, particles + 24), shape: 'ember', motion: 'radial', speed: 1.08, spread: .98, trail: .42, glow: .50, salt: 32),
        n('impact_lines', .60, .18, amount: 9, scale: 1.25, salt: 33),
      ];
    }
    if (style == 'aura') {
      return <dynamic>[
        n('rune_ring', .04, .44, origin: 'caster', amount: 6, variant: seed % 6, salt: 34),
        n('energy_orb', .18, .44, origin: 'caster', particleCount: 22 + intensity * 3, shape: 'star', motion: 'converge', glow: .44, salt: 35),
        n('particle_emitter', .20, .62, origin: 'caster', particleCount: math.min(80, particles), shape: 'star', motion: 'rise', speed: .34, spread: .72, gravity: -.14, trail: .14, glow: .30, salt: 36),
      ];
    }

    // Generic legacy skill: keep its old primary idea but add a deterministic visual identity.
    return <dynamic>[
      n('sigil', .03, .30, origin: 'caster', amount: 5, variant: seed % 6, salt: 37),
      n('energy_orb', .18, .28, origin: 'caster', particleCount: 20 + intensity * 3, shape: 'spark', motion: 'converge', glow: .46, salt: 38),
      n('projectile', .36, .30, origin: 'caster', direction: 'left_to_right', shape: seed.isEven ? 'diamond' : 'orb', path: seed % 3 == 0 ? 'arc' : 'straight', glow: .34, salt: 39),
      n('particle_burst', .60, .26, particleCount: math.min(110, particles), shape: 'spark', motion: 'radial', speed: .92, spread: .86, trail: .30, glow: .38, salt: 40),
      n('impact_lines', .61, .18, amount: 8, scale: 1.16, salt: 41),
    ];
  }

  void paint(Canvas canvas, Size size, {required Offset caster, required Offset target}) {
    final identity = _s(spec['visual_identity']).toLowerCase();
    final intensity = _i(spec['intensity'], 4).clamp(1, 10).toInt();
    final sequence = _renderSequence();

    // Cinematic skills get a subtle vignette, not a full-screen colored fog.
    if (identity == 'domain' || identity == 'magic_sigil' || identity == 'summoned_creature') {
      final r = math.max(size.width, size.height) * .72;
      final shader = RadialGradient(
        colors: <Color>[accent.withOpacity(.025 + intensity * .002), Colors.transparent],
      ).createShader(Rect.fromCircle(center: Offset(size.width * .5, size.height * .44), radius: r));
      canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
    }

    for (final raw in sequence.take(10)) {
      final item = _map(raw);
      if (item.isEmpty) continue;
      final at = _d(item['at']).clamp(0.0, .97).toDouble();
      final duration = math.max(.06, _d(item['duration'], .30));
      if (progress < at) continue;
      final local = ((progress - at) / duration).clamp(0.0, 1.0).toDouble();
      _drawNode(canvas, size, caster, target, item, local, intensity);
    }
  }

  void _drawNode(
    Canvas canvas,
    Size size,
    Offset caster,
    Offset target,
    Map<String, dynamic> item,
    double t,
    int intensity,
  ) {
    final type = _s(item['type']).toLowerCase();
    final scale = _d(item['scale'], 1).clamp(.35, 2.4).toDouble();
    final amount = _i(item['amount'], 3).clamp(1, 12).toInt();
    final direction = _s(item['direction'], 'center').toLowerCase();
    final pathKind = _s(item['path'], 'straight').toLowerCase();
    final seed = _i(item['seed'], 0).clamp(0, 9999).toInt();
    final origin = _originFor(item, size, caster, target);
    final pulse = _pulse(t);
    final fade = (1 - (t - .72).clamp(0.0, .28) / .28).clamp(0.0, 1.0).toDouble();
    final glow = _d(item['glow'], .35).clamp(0.0, 1.0).toDouble();

    if (type == 'darken') {
      canvas.drawRect(Offset.zero & size, Paint()..color = Colors.black.withOpacity(.50 * pulse));
      return;
    }
    if (type == 'screen_flash') {
      canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white.withOpacity(.62 * pulse));
      return;
    }
    if (type == 'starfield') {
      _drawStarfield(canvas, size, item, t, fade, seed);
      return;
    }
    if (type == 'particle_emitter' || type == 'particle_burst' || type == 'petal_burst') {
      _drawParticles(canvas, size, origin, item, t, intensity,
          burst: type != 'particle_emitter', forcedShape: type == 'petal_burst' ? 'petal' : null);
      return;
    }
    if (type == 'sigil' || type == 'rune_ring') {
      _drawSigil(canvas, origin, item, t, scale, intensity, fade, ringOnly: type == 'rune_ring');
      return;
    }
    if (type == 'energy_orb' || type == 'charge' || type == 'aura') {
      _drawEnergyOrb(canvas, size, origin, item, t, scale, intensity, fade,
          aura: type == 'aura');
      return;
    }
    if (type == 'blade_manifest') {
      _drawBlade(canvas, size, caster, target, item, t, scale, intensity, fade);
      return;
    }
    if (type == 'beam') {
      _drawBeam(canvas, size, caster, target, item, t, scale, intensity, fade);
      return;
    }
    if (type == 'crescent_wave') {
      _drawCrescent(canvas, size, caster, target, item, t, scale, intensity, fade);
      return;
    }
    if (type == 'projectile_swarm') {
      _drawProjectileSwarm(canvas, size, caster, target, item, t, scale, intensity, fade, seed);
      return;
    }
    if (type == 'dragon_trail') {
      _drawDragon(canvas, size, caster, target, item, t, scale, intensity, fade, seed);
      return;
    }
    if (type == 'lotus') {
      _drawLotus(canvas, size, origin, item, t, scale, intensity, fade, seed);
      return;
    }
    if (type == 'vortex') {
      _drawVortex(canvas, size, origin, item, t, scale, intensity, fade, seed);
      return;
    }
    if (type == 'meteor') {
      _drawMeteor(canvas, size, target, item, t, scale, intensity, fade, seed);
      return;
    }
    if (type == 'force_field') {
      _drawForceField(canvas, origin, item, t, scale, intensity, fade);
      return;
    }
    if (type == 'impact_lines') {
      _drawImpactLines(canvas, origin, item, t, scale, intensity, fade, seed);
      return;
    }
    if (type == 'ground_crack') {
      _drawGroundCrack(canvas, size, origin, item, t, scale, fade, seed);
      return;
    }
    if (type == 'trail') {
      _drawTrail(canvas, size, caster, target, item, t, scale, intensity, fade, seed);
      return;
    }
    if (type == 'smoke' || type == 'frost_mist') {
      final smokeItem = <String, dynamic>{...item, 'shape': type == 'frost_mist' ? 'snow' : 'dust', 'motion': 'rise'};
      _drawParticles(canvas, size, origin, smokeItem, t, intensity, burst: false);
      return;
    }
    if (type == 'slash') {
      _drawSlash(canvas, size, caster, target, item, t, scale, intensity, fade, pathKind);
      return;
    }
    if (type == 'projectile') {
      _drawProjectile(canvas, size, caster, target, item, t, scale, intensity, fade);
      return;
    }
    if (type == 'lightning') {
      _drawLightning(canvas, size, origin, target, item, t, scale, intensity, fade, seed);
      return;
    }
    if (type == 'ice_shards' || type == 'fire_particles') {
      final particleItem = <String, dynamic>{
        ...item,
        'shape': type == 'ice_shards' ? 'shard' : 'ember',
        'motion': _s(item['motion'], 'radial'),
        'particle_count': _i(item['particle_count'], amount * 9),
      };
      _drawParticles(canvas, size, origin, particleItem, t, intensity, burst: true);
      return;
    }
    if (type == 'shockwave' || type == 'explosion') {
      _drawShockwave(canvas, origin, item, t, scale, intensity, fade, seed, explosion: type == 'explosion');
      return;
    }
    if (type == 'heal_ring') {
      _drawHealRing(canvas, origin, item, t, scale, intensity, fade);
      return;
    }
    if (type == 'shield') {
      _drawShield(canvas, origin, item, t, scale, intensity, fade);
      return;
    }
    if (type == 'afterimage') {
      _drawAfterimages(canvas, size, caster, target, item, t, scale, fade);
      return;
    }
    if (type == 'space_crack') {
      _drawSpaceCrack(canvas, size, origin, item, t, scale, intensity, fade, seed);
      return;
    }
  }

  void _drawParticles(
    Canvas canvas,
    Size size,
    Offset origin,
    Map<String, dynamic> item,
    double t,
    int intensity, {
    bool burst = false,
    String? forcedShape,
  }) {
    final seed = _i(item['seed'], 0);
    final shape = forcedShape ?? _s(item['shape'], 'spark').toLowerCase();
    final motion = _s(item['motion'], burst ? 'radial' : 'stream').toLowerCase();
    final direction = _s(item['direction'], 'radial').toLowerCase();
    var count = _i(item['particle_count'], 0);
    if (count <= 0) count = _i(item['amount'], 3) * (burst ? 9 : 7);
    count = count.clamp(2, 120).toInt();
    final speed = _d(item['speed'], .65).clamp(0.0, 1.5).toDouble();
    final spread = _d(item['spread'], .55).clamp(0.0, 1.0).toDouble();
    final gravity = _d(item['gravity'], 0).clamp(-1.0, 1.0).toDouble();
    final trail = _d(item['trail'], .25).clamp(0.0, 1.0).toDouble();
    final glow = _d(item['glow'], .35).clamp(0.0, 1.0).toDouble();
    final scale = _d(item['scale'], 1).clamp(.35, 2.4).toDouble();
    final baseDistance = size.shortestSide * (.20 + speed * .62) * scale;

    Offset particlePosition(int i, double age) {
      final a0 = _seed01(i, 11, seed) * math.pi * 2;
      final s1 = _seed01(i, 17, seed);
      final s2 = _seed01(i, 23, seed);
      final s3 = _seed01(i, 29, seed);
      final baseAngle = _directionAngle(direction, a0);
      final jitter = (s1 - .5) * math.pi * (direction == 'radial' ? 2 : .9) * spread;
      final angle = baseAngle + jitter;
      final distance = baseDistance * (.52 + s2 * .78) * age;
      final gravY = size.height * gravity * age * age * .16;

      switch (motion) {
        case 'rise':
          return Offset(
            origin.dx + (s1 - .5) * size.width * .24 * spread + math.sin(age * 7 + i) * 5,
            origin.dy - distance * .72 + gravY,
          );
        case 'fall':
          return Offset(
            origin.dx + (s1 - .5) * size.width * .30 * spread,
            origin.dy + distance * .78 + gravY,
          );
        case 'orbit':
          final r = size.shortestSide * (.08 + s2 * .18) * scale * (1 - age * .16);
          final a = a0 + age * (2.2 + s3 * 3.4) * (i.isEven ? 1 : -1);
          return Offset(origin.dx + math.cos(a) * r, origin.dy + math.sin(a) * r * .62);
        case 'swirl':
        case 'spiral':
          final r = size.shortestSide * (.04 + age * (.10 + spread * .22)) * scale * (.65 + s2 * .6);
          final a = a0 + age * (4.0 + s3 * 5.0) * (i.isEven ? 1 : -1);
          return Offset(origin.dx + math.cos(a) * r, origin.dy + math.sin(a) * r * .68 + gravY);
        case 'converge':
          final startR = size.shortestSide * (.18 + s2 * .30) * scale;
          final a = a0 + age * (i.isEven ? .8 : -.8);
          final r = startR * (1 - _easeOut(age));
          return Offset(origin.dx + math.cos(a) * r, origin.dy + math.sin(a) * r * .65);
        case 'wave':
          return Offset(
            origin.dx + math.cos(angle) * distance,
            origin.dy + math.sin(angle) * distance + math.sin(age * math.pi * 5 + i) * 12 * spread + gravY,
          );
        case 'stream':
          final side = (s1 - .5) * size.shortestSide * .18 * spread * (1 - age * .55);
          return Offset(
            origin.dx + math.cos(baseAngle) * distance + math.cos(baseAngle + math.pi / 2) * side,
            origin.dy + math.sin(baseAngle) * distance + math.sin(baseAngle + math.pi / 2) * side + gravY,
          );
        case 'cone':
        case 'scatter':
        case 'radial':
        default:
          return Offset(
            origin.dx + math.cos(angle) * distance,
            origin.dy + math.sin(angle) * distance * (.72 + s3 * .35) + gravY,
          );
      }
    }

    for (var i = 0; i < count; i++) {
      final spawn = burst
          ? _seed01(i, 31, seed) * .10
          : (i / count) * (.52 + _seed01(i, 37, seed) * .12);
      if (t <= spawn) continue;
      final age = ((t - spawn) / math.max(.001, 1 - spawn)).clamp(0.0, 1.0).toDouble();
      if (age >= 1) continue;
      final life = math.sin(age * math.pi).clamp(0.0, 1.0).toDouble();
      final p = particlePosition(i, age);
      final previous = particlePosition(i, math.max(0.0, age - (.035 + trail * .11)));
      final rnd = _seed01(i, 41, seed);
      final sizePx = (.8 + rnd * (2.0 + intensity * .10)) * scale;
      _drawParticleShape(canvas, shape, p, previous, sizePx, life, glow, i, seed);
    }
  }

  void _drawParticleShape(
    Canvas canvas,
    String shape,
    Offset p,
    Offset previous,
    double sizePx,
    double life,
    double glow,
    int index,
    int seed,
  ) {
    final angle = math.atan2(p.dy - previous.dy, p.dx - previous.dx);
    final additive = Paint()
      ..blendMode = BlendMode.plus
      ..color = accent.withOpacity((.16 + glow * .22) * life);
    if (glow > .12) {
      canvas.drawCircle(p, sizePx * (1.8 + glow * 2.4), additive);
    }

    if (shape == 'streak' || shape == 'line') {
      canvas.drawLine(previous, p, _stroke(accent, .72 * life, math.max(.65, sizePx * .62)));
      canvas.drawLine(previous, p, _stroke(Colors.white, .52 * life, math.max(.35, sizePx * .18)));
      return;
    }
    if (shape == 'orb' || shape == 'spark' || shape == 'ember' || shape == 'dust') {
      final c = shape == 'ember' && index.isEven ? Colors.white : accent;
      canvas.drawCircle(p, sizePx * (shape == 'dust' ? 1.5 : 1), _fill(c, (shape == 'dust' ? .18 : .72) * life));
      if (shape == 'ember') canvas.drawLine(previous, p, _stroke(accent, .30 * life, .7));
      return;
    }

    canvas.save();
    canvas.translate(p.dx, p.dy);
    canvas.rotate(angle + (_seed01(index, 47, seed) - .5) * 1.4);
    if (shape == 'shard') {
      final shard = Path()
        ..moveTo(sizePx * 2.8, 0)
        ..lineTo(-sizePx * 1.2, -sizePx * .9)
        ..lineTo(-sizePx * .4, sizePx * 1.1)
        ..close();
      canvas.drawPath(shard, _fill(accent, .70 * life));
      canvas.drawPath(shard, _stroke(Colors.white, .45 * life, .45));
    } else if (shape == 'diamond' || shape == 'blade') {
      final long = shape == 'blade' ? 4.2 : 2.2;
      final path = Path()
        ..moveTo(sizePx * long, 0)
        ..lineTo(0, -sizePx * .75)
        ..lineTo(-sizePx * (shape == 'blade' ? 1.8 : 2.0), 0)
        ..lineTo(0, sizePx * .75)
        ..close();
      canvas.drawPath(path, _fill(accent, .58 * life));
      canvas.drawPath(path, _stroke(Colors.white, .62 * life, .5));
    } else if (shape == 'petal') {
      final len = sizePx * 4.0;
      final wid = sizePx * 1.45;
      final path = Path()
        ..moveTo(-len * .35, 0)
        ..quadraticBezierTo(0, -wid, len * .65, 0)
        ..quadraticBezierTo(0, wid, -len * .35, 0)
        ..close();
      canvas.drawPath(path, _fill(accent, .48 * life));
      canvas.drawPath(path, _stroke(Colors.white, .30 * life, .4));
    } else if (shape == 'snow') {
      for (var k = 0; k < 3; k++) {
        final a = k * math.pi / 3;
        canvas.drawLine(
          Offset(math.cos(a) * -sizePx * 1.8, math.sin(a) * -sizePx * 1.8),
          Offset(math.cos(a) * sizePx * 1.8, math.sin(a) * sizePx * 1.8),
          _stroke(Colors.white, .50 * life, .45),
        );
      }
    } else if (shape == 'star') {
      for (var k = 0; k < 2; k++) {
        final a = k * math.pi / 2;
        canvas.drawLine(
          Offset(math.cos(a) * -sizePx * 2.0, math.sin(a) * -sizePx * 2.0),
          Offset(math.cos(a) * sizePx * 2.0, math.sin(a) * sizePx * 2.0),
          _stroke(Colors.white, .62 * life, .55),
        );
      }
    } else if (shape == 'rune') {
      canvas.drawCircle(Offset.zero, sizePx * 1.5, _stroke(accent, .52 * life, .5));
      canvas.drawLine(Offset(-sizePx, 0), Offset(sizePx, 0), _stroke(Colors.white, .34 * life, .4));
    } else {
      canvas.drawCircle(Offset.zero, sizePx, _fill(accent, .62 * life));
    }
    canvas.restore();
  }

  void _drawStarfield(Canvas canvas, Size size, Map<String, dynamic> item, double t, double fade, int seed) {
    final count = _i(item['particle_count'], 36).clamp(12, 90).toInt();
    for (var i = 0; i < count; i++) {
      final x = _seed01(i, 61, seed) * size.width;
      final y = _seed01(i, 67, seed) * size.height * .82;
      final twinkle = .35 + .65 * math.sin((t * 6 + i * .73)).abs();
      final r = .35 + _seed01(i, 71, seed) * 1.1;
      canvas.drawCircle(Offset(x, y), r, _fill(i % 4 == 0 ? accent : Colors.white, .10 * fade * twinkle));
    }
  }

  void _drawSigil(Canvas canvas, Offset c, Map<String, dynamic> item, double t, double scale, int intensity, double fade, {bool ringOnly = false}) {
    final amount = _i(item['amount'], 5).clamp(2, 12).toInt();
    final variant = _i(item['variant'], 0).clamp(0, 6).toInt();
    final reveal = _easeOut(t);
    final r = (28 + intensity * 3.4) * scale * reveal;
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(t * (variant.isEven ? .65 : -.48));
    for (var ring = 0; ring < math.min(4, 1 + amount ~/ 3); ring++) {
      final rr = r * (1 - ring * .18);
      final rect = Rect.fromCircle(center: Offset.zero, radius: rr);
      for (var i = 0; i < 12; i++) {
        canvas.drawArc(rect, i * math.pi * 2 / 12 + ring * .19, math.pi * (.045 + (i % 3) * .012), false,
            _stroke(i.isEven ? accent : Colors.white, (.20 + ring * .035) * fade, .65 + ring * .18));
      }
    }
    if (!ringOnly) {
      if (variant % 3 == 0) {
        // Eye-shaped sigil.
        final eye = Path()
          ..moveTo(-r * .82, 0)
          ..quadraticBezierTo(0, -r * .40, r * .82, 0)
          ..quadraticBezierTo(0, r * .40, -r * .82, 0);
        _layeredPath(canvas, eye, accent, .62 * fade, 1.05 * scale, glow: 3.0);
        canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: r * .15, height: r * .55), _fill(Colors.white, .72 * fade));
      } else {
        final sides = 3 + variant % 4;
        final poly = Path();
        for (var i = 0; i <= sides; i++) {
          final a = -math.pi / 2 + i * math.pi * 2 / sides;
          final p = Offset(math.cos(a) * r * .62, math.sin(a) * r * .62);
          if (i == 0) poly.moveTo(p.dx, p.dy); else poly.lineTo(p.dx, p.dy);
        }
        _layeredPath(canvas, poly, accent, .48 * fade, .9 * scale, glow: 2.5, whiteCore: false);
      }
      for (var i = 0; i < amount; i++) {
        final a = i * math.pi * 2 / amount - t * 1.1;
        final p = Offset(math.cos(a) * r * .82, math.sin(a) * r * .82);
        canvas.drawCircle(p, 1.1 * scale, _fill(Colors.white, .42 * fade));
      }
    }
    canvas.restore();
  }

  void _drawEnergyOrb(Canvas canvas, Size size, Offset c, Map<String, dynamic> item, double t, double scale, int intensity, double fade, {bool aura = false}) {
    final pulse = _pulse(t);
    final amount = _i(item['amount'], 4).clamp(2, 10).toInt();
    final coreR = (4 + intensity * .45 + pulse * 6) * scale;
    canvas.drawCircle(c, coreR * 2.4, _fill(accent, .10 * pulse, blur: 5, additive: true));
    canvas.drawCircle(c, coreR, _fill(Colors.white, .82 * pulse));
    canvas.drawCircle(c, coreR + 3 * scale, _stroke(accent, .68 * pulse, 1.1));
    for (var i = 0; i < math.min(5, amount); i++) {
      final r = (20 + i * 11 + t * (aura ? 18 : 9)) * scale;
      final rect = Rect.fromCircle(center: c, radius: r);
      canvas.drawArc(rect, i * .78 + t * (i.isEven ? 1.3 : -.9), math.pi * (aura ? .95 : .55), false,
          _stroke(i.isEven ? accent : Colors.white, (.22 - i * .025) * fade, .8 + i * .08));
    }
    if (_i(item['particle_count'], 0) > 0) {
      final particles = <String, dynamic>{...item, 'motion': _s(item['motion'], 'converge'), 'shape': _s(item['shape'], 'spark')};
      _drawParticles(canvas, size, c, particles, t, intensity, burst: false);
    }
  }

  void _drawBlade(Canvas canvas, Size size, Offset caster, Offset target, Map<String, dynamic> item, double t, double scale, int intensity, double fade) {
    final q = _easeOut(t);
    final start = Offset(caster.dx - size.width * .06, caster.dy + size.height * .08);
    final len = math.min(size.width * .34, 220.0) * q * scale;
    final angle = -.16;
    canvas.save();
    canvas.translate(start.dx, start.dy);
    canvas.rotate(angle);
    final blade = Path()
      ..moveTo(-len * .10, 3 * scale)
      ..lineTo(len, -2 * scale)
      ..lineTo(len * .92, 2 * scale)
      ..lineTo(-len * .10, 6 * scale)
      ..close();
    canvas.drawPath(blade, _fill(accent, .26 * fade));
    canvas.drawLine(Offset(-len * .08, 3 * scale), Offset(len, 0), _stroke(Colors.white, .88 * fade, 1.4 * scale));
    canvas.drawLine(Offset(-len * .18, 4 * scale), Offset(-len * .03, 4 * scale), _stroke(accent, .82 * fade, 5 * scale));
    canvas.drawLine(Offset(-len * .08, -8 * scale), Offset(-len * .08, 14 * scale), _stroke(Colors.white, .46 * fade, 1.2 * scale));
    canvas.restore();
    if (_i(item['particle_count'], 0) > 0) {
      final p = <String, dynamic>{...item, 'origin': 'caster', 'motion': 'converge', 'shape': 'streak'};
      _drawParticles(canvas, size, start, p, t, intensity, burst: false);
    }
  }

  Path _beamPath(Offset start, Offset end, String pathKind, double reveal, double scale) {
    final p = Path()..moveTo(start.dx, start.dy);
    final current = Offset(start.dx + (end.dx - start.dx) * reveal, start.dy + (end.dy - start.dy) * reveal);
    if (pathKind == 'wave') {
      final mid = Offset((start.dx + current.dx) * .5, (start.dy + current.dy) * .5 - 18 * scale * math.sin(reveal * math.pi));
      p.quadraticBezierTo(mid.dx, mid.dy, current.dx, current.dy);
    } else if (pathKind == 'arc' || pathKind == 'crescent') {
      final mid = Offset((start.dx + current.dx) * .5, math.min(start.dy, current.dy) - 42 * scale);
      p.quadraticBezierTo(mid.dx, mid.dy, current.dx, current.dy);
    } else {
      p.lineTo(current.dx, current.dy);
    }
    return p;
  }

  void _drawBeam(Canvas canvas, Size size, Offset caster, Offset target, Map<String, dynamic> item, double t, double scale, int intensity, double fade) {
    final reveal = _easeOut(math.min(1.0, t * 1.35));
    final path = _beamPath(caster, target, _s(item['path'], 'straight'), reveal, scale);
    final width = (3.2 + intensity * .55) * scale;
    _layeredPath(canvas, path, accent, .88 * fade, width, glow: 7 + _d(item['glow'], .4) * 8);
    final side1 = path;
    canvas.drawPath(side1, _stroke(accent, .16 * fade, width * 2.2));
    if (_i(item['particle_count'], 0) > 0) {
      final mid = Offset(caster.dx + (target.dx - caster.dx) * reveal * .55, caster.dy + (target.dy - caster.dy) * reveal * .55);
      final p = <String, dynamic>{...item, 'origin': 'caster', 'motion': 'stream', 'direction': target.dx >= caster.dx ? 'left_to_right' : 'right_to_left', 'shape': _s(item['shape'], 'streak')};
      _drawParticles(canvas, size, mid, p, t, intensity, burst: false);
    }
  }

  void _drawCrescent(Canvas canvas, Size size, Offset caster, Offset target, Map<String, dynamic> item, double t, double scale, int intensity, double fade) {
    final q = _easeOut(t);
    final center = Offset(caster.dx + (target.dx - caster.dx) * q, caster.dy + (target.dy - caster.dy) * q);
    final r = (32 + intensity * 4.5) * scale;
    final rect = Rect.fromCircle(center: center, radius: r);
    canvas.drawArc(rect, -math.pi * .72, math.pi * 1.36, false, _stroke(accent, .18 * fade, 9 * scale, blur: 4));
    canvas.drawArc(rect, -math.pi * .72, math.pi * 1.36, false, _stroke(accent, .78 * fade, 3.2 * scale));
    canvas.drawArc(rect, -math.pi * .72, math.pi * 1.36, false, _stroke(Colors.white, .82 * fade, .9 * scale));
  }

  void _drawProjectileSwarm(Canvas canvas, Size size, Offset caster, Offset target, Map<String, dynamic> item, double t, double scale, int intensity, double fade, int seed) {
    var count = _i(item['particle_count'], 48) ~/ 4;
    count = count.clamp(8, 28).toInt();
    for (var i = 0; i < count; i++) {
      final delay = (i / count) * .38 + _seed01(i, 83, seed) * .05;
      if (t < delay) continue;
      final u = ((t - delay) / math.max(.01, 1 - delay)).clamp(0.0, 1.0).toDouble();
      final lane = (_seed01(i, 89, seed) - .5) * size.height * .42;
      final arc = math.sin(u * math.pi) * (18 + _seed01(i, 97, seed) * 42) * (i.isEven ? -1 : 1);
      final p = Offset(
        caster.dx + (target.dx - caster.dx) * _easeOut(u),
        caster.dy + lane * (1 - u) + (target.dy - caster.dy) * u + arc,
      );
      final prevU = math.max(0.0, u - .06);
      final prev = Offset(
        caster.dx + (target.dx - caster.dx) * _easeOut(prevU),
        caster.dy + lane * (1 - prevU) + (target.dy - caster.dy) * prevU + math.sin(prevU * math.pi) * (18 + _seed01(i, 97, seed) * 42) * (i.isEven ? -1 : 1),
      );
      _drawParticleShape(canvas, _s(item['shape'], 'blade'), p, prev, (1.2 + _seed01(i, 101, seed) * 1.1) * scale, fade, _d(item['glow'], .3), i, seed);
    }
  }

  void _drawDragon(Canvas canvas, Size size, Offset caster, Offset target, Map<String, dynamic> item, double t, double scale, int intensity, double fade, int seed) {
    final reveal = _easeInOut(t);
    final startX = caster.dx - size.width * .08;
    final endX = target.dx + size.width * .08;
    Offset point(double u) {
      final x = startX + (endX - startX) * u * reveal;
      final wave = math.sin((u * 3.15 - reveal * .55 + (seed % 11) * .013) * math.pi) * 30 * scale;
      final lift = -math.sin(u * math.pi) * 22 * scale;
      return Offset(x, caster.dy + (target.dy - caster.dy) * u + wave * (1 - u * .18) + lift);
    }
    final body = Path();
    for (var i = 0; i <= 46; i++) {
      final p = point(i / 46);
      if (i == 0) body.moveTo(p.dx, p.dy); else body.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(body, _stroke(accent, .13 * fade, 22 * scale, blur: 8));
    canvas.drawPath(body, _stroke(accent, .30 * fade, 12 * scale, blur: 2));
    canvas.drawPath(body, _stroke(accent, .64 * fade, 6.5 * scale));
    canvas.drawPath(body, _stroke(Colors.white, .84 * fade, 1.35 * scale));

    for (var i = 5; i < 42; i += 4) {
      final u = i / 46;
      final p = point(u);
      final p2 = point(math.min(1.0, u + .018));
      final a = math.atan2(p2.dy - p.dy, p2.dx - p.dx) - math.pi / 2;
      final len = (4 + _seed01(i, 109, seed) * 7) * scale;
      canvas.drawLine(p, Offset(p.dx + math.cos(a) * len, p.dy + math.sin(a) * len), _stroke(Colors.white, .30 * fade, .7));
    }

    final head = point(1);
    final neck = point(.965);
    final angle = math.atan2(head.dy - neck.dy, head.dx - neck.dx);
    canvas.save();
    canvas.translate(head.dx, head.dy);
    canvas.rotate(angle);
    final s = (13 + intensity * .60) * scale;
    final headPath = Path()
      ..moveTo(s * 1.20, 0)
      ..lineTo(s * .38, -s * .60)
      ..lineTo(-s * .55, -s * .48)
      ..lineTo(-s * .25, -s * .08)
      ..lineTo(-s * .72, s * .44)
      ..lineTo(s * .22, s * .54)
      ..close();
    canvas.drawPath(headPath, _fill(accent, .56 * fade));
    canvas.drawPath(headPath, _stroke(Colors.white, .78 * fade, 1.0));
    final horns = Path()
      ..moveTo(-s * .30, -s * .43)..lineTo(-s * .68, -s * 1.15)
      ..moveTo(s * .08, -s * .50)..lineTo(-s * .02, -s * 1.20);
    canvas.drawPath(horns, _stroke(accent, .88 * fade, 1.2));
    canvas.drawCircle(Offset(s * .48, -s * .16), 1.8 * scale, _fill(Colors.white, .96 * fade, blur: 1));
    canvas.restore();

    final pItem = <String, dynamic>{
      ...item,
      'origin': 'caster',
      'motion': 'stream',
      'direction': 'left_to_right',
      'shape': _s(item['shape'], 'snow'),
      'particle_count': _i(item['particle_count'], 48 + intensity * 4),
      'spread': math.min(.58, _d(item['spread'], .38)),
    };
    _drawParticles(canvas, size, point(.55), pItem, t, intensity, burst: false);
  }

  void _drawLotus(Canvas canvas, Size size, Offset c, Map<String, dynamic> item, double t, double scale, int intensity, double fade, int seed) {
    final bloom = _easeOut(t);
    final amount = _i(item['amount'], 7).clamp(4, 12).toInt();
    final variant = _i(item['variant'], 0);
    final spin = t * (.22 + variant * .025);
    canvas.save();
    canvas.translate(c.dx, c.dy);
    void petal(double angle, double len, double width, double alpha) {
      canvas.save();
      canvas.rotate(angle);
      final p = Path()
        ..moveTo(0, 0)
        ..cubicTo(len * .24, -width, len * .74, -width * .82, len, 0)
        ..cubicTo(len * .74, width * .82, len * .24, width, 0, 0)
        ..close();
      final paint = Paint()
        ..shader = LinearGradient(
          colors: <Color>[Colors.white.withOpacity(.80 * alpha), accent.withOpacity(.64 * alpha), accent.withOpacity(.04)],
          stops: const <double>[0, .34, 1],
        ).createShader(Rect.fromLTWH(0, -width, len, width * 2));
      paint.blendMode = BlendMode.plus;
      canvas.drawPath(p, paint);
      canvas.drawPath(p, _stroke(Colors.white, .26 * alpha, .55));
      canvas.restore();
    }
    final outer = math.max(10, amount * 2);
    final outerLen = (28 + 52 * bloom + intensity * 1.7) * scale;
    final outerW = (8 + 12 * bloom) * scale;
    for (var i = 0; i < outer; i++) {
      petal(i * math.pi * 2 / outer + spin, outerLen, outerW, fade);
    }
    final inner = math.max(7, amount + 2);
    for (var i = 0; i < inner; i++) {
      petal(i * math.pi * 2 / inner - spin * 1.5 + .22, outerLen * .62, outerW * .68, fade * .86);
    }
    final ringR = outerLen * .95;
    final ring = Rect.fromCircle(center: Offset.zero, radius: ringR);
    for (var i = 0; i < 18; i++) {
      canvas.drawArc(ring, i * math.pi * 2 / 18 - t * .5, math.pi * .038, false, _stroke(accent, .26 * fade, .8));
    }
    final core = (5 + 10 * _pulse(t)) * scale;
    canvas.drawCircle(Offset.zero, core * 2.2, _fill(accent, .12 * fade, blur: 5, additive: true));
    canvas.drawCircle(Offset.zero, core, _fill(Colors.white, .88 * fade));
    canvas.restore();
  }

  void _drawVortex(Canvas canvas, Size size, Offset c, Map<String, dynamic> item, double t, double scale, int intensity, double fade, int seed) {
    final arms = _i(item['amount'], 6).clamp(3, 10).toInt();
    final radius = size.shortestSide * (.12 + intensity * .012) * scale * _easeOut(t);
    for (var arm = 0; arm < arms; arm++) {
      final path = Path();
      for (var i = 0; i <= 32; i++) {
        final u = i / 32;
        final a = arm * math.pi * 2 / arms + u * math.pi * (2.2 + (seed % 5) * .18) + t * 2.4;
        final r = radius * u;
        final p = Offset(c.dx + math.cos(a) * r, c.dy + math.sin(a) * r * .62);
        if (i == 0) path.moveTo(p.dx, p.dy); else path.lineTo(p.dx, p.dy);
      }
      _layeredPath(canvas, path, accent, .38 * fade, 1.0 + arm % 2 * .4, glow: 2.5, whiteCore: arm % 3 == 0);
    }
    final particles = <String, dynamic>{...item, 'motion': 'spiral', 'shape': _s(item['shape'], 'streak')};
    _drawParticles(canvas, size, c, particles, t, intensity, burst: false);
  }

  void _drawMeteor(Canvas canvas, Size size, Offset target, Map<String, dynamic> item, double t, double scale, int intensity, double fade, int seed) {
    final q = _easeInOut(t);
    final start = Offset(target.dx - size.width * .28, -size.height * .08);
    final p = Offset(start.dx + (target.dx - start.dx) * q, start.dy + (target.dy - start.dy) * q);
    final prevQ = math.max(0.0, q - .12);
    final prev = Offset(start.dx + (target.dx - start.dx) * prevQ, start.dy + (target.dy - start.dy) * prevQ);
    final tail = Path()..moveTo(prev.dx, prev.dy)..lineTo(p.dx, p.dy);
    _layeredPath(canvas, tail, accent, .72 * fade, (6 + intensity * .5) * scale, glow: 8);
    final r = (8 + intensity * .65) * scale;
    canvas.drawCircle(p, r * 2.4, _fill(accent, .18 * fade, blur: 7, additive: true));
    canvas.drawCircle(p, r, _fill(Colors.white, .88 * fade));
    final particles = <String, dynamic>{...item, 'origin': 'sky', 'direction': 'down', 'motion': 'stream', 'shape': _s(item['shape'], 'ember'), 'particle_count': math.max(24, _i(item['particle_count'], 48))};
    _drawParticles(canvas, size, p, particles, t, intensity, burst: false);
  }

  void _drawForceField(Canvas canvas, Offset c, Map<String, dynamic> item, double t, double scale, int intensity, double fade) {
    final amount = _i(item['amount'], 5).clamp(2, 10).toInt();
    final q = _easeOut(t);
    for (var i = 0; i < amount; i++) {
      final rx = (26 + i * 9 + q * 30) * scale;
      final ry = rx * (.42 + (i % 2) * .08);
      final rect = Rect.fromCenter(center: c, width: rx * 2, height: ry * 2);
      canvas.drawArc(rect, i * .6 + t * (i.isEven ? 1.1 : -.7), math.pi * (1.15 - i * .035), false,
          _stroke(i.isEven ? accent : Colors.white, (.30 - i * .018) * fade, .8 + (i % 3) * .25));
    }
    canvas.drawCircle(c, (11 + intensity) * scale * _pulse(t), _stroke(Colors.white, .18 * fade, .7));
  }

  void _drawImpactLines(Canvas canvas, Offset c, Map<String, dynamic> item, double t, double scale, int intensity, double fade, int seed) {
    final amount = (_i(item['amount'], 8) * 2).clamp(8, 28).toInt();
    final q = _easeOut(t);
    for (var i = 0; i < amount; i++) {
      final a = i * math.pi * 2 / amount + (_seed01(i, 127, seed) - .5) * .22;
      final inner = (12 + _seed01(i, 131, seed) * 16) * scale * q;
      final outer = inner + (28 + _seed01(i, 137, seed) * (44 + intensity * 3)) * scale * q;
      final p1 = Offset(c.dx + math.cos(a) * inner, c.dy + math.sin(a) * inner);
      final p2 = Offset(c.dx + math.cos(a) * outer, c.dy + math.sin(a) * outer);
      canvas.drawLine(p1, p2, _stroke(i % 4 == 0 ? Colors.white : accent, (.52 - i % 3 * .08) * fade, .55 + _seed01(i, 139, seed) * 1.2));
    }
  }

  void _drawGroundCrack(Canvas canvas, Size size, Offset c, Map<String, dynamic> item, double t, double scale, double fade, int seed) {
    final branches = _i(item['amount'], 8).clamp(4, 12).toInt();
    final q = _easeOut(t);
    for (var i = 0; i < branches; i++) {
      final base = math.pi * (.08 + .84 * i / math.max(1, branches - 1));
      final path = Path()..moveTo(c.dx, c.dy);
      var x = c.dx;
      var y = c.dy;
      for (var k = 0; k < 5; k++) {
        final step = (10 + _seed01(i * 11 + k, 149, seed) * 16) * scale * q;
        final a = base + (_seed01(i * 17 + k, 151, seed) - .5) * .65;
        x += math.cos(a) * step;
        y += math.sin(a) * step * .55;
        path.lineTo(x, y);
      }
      canvas.drawPath(path, _stroke(Colors.black, .72 * fade, 2.4 * scale));
      canvas.drawPath(path, _stroke(accent, .42 * fade, .75 * scale));
    }
  }

  void _drawTrail(Canvas canvas, Size size, Offset caster, Offset target, Map<String, dynamic> item, double t, double scale, int intensity, double fade, int seed) {
    final q = _easeOut(t);
    final kind = _s(item['path'], 'wave');
    final path = Path();
    final steps = 34;
    for (var i = 0; i <= steps; i++) {
      final u = i / steps * q;
      var x = caster.dx + (target.dx - caster.dx) * u;
      var y = caster.dy + (target.dy - caster.dy) * u;
      if (kind == 'wave' || kind == 'serpentine') y += math.sin((u * 3.0 + t * .8) * math.pi) * 18 * scale;
      if (kind == 'arc') y -= math.sin(u * math.pi) * 42 * scale;
      if (kind == 'spiral') {
        x += math.cos(u * math.pi * 6) * (1 - u) * 28 * scale;
        y += math.sin(u * math.pi * 6) * (1 - u) * 18 * scale;
      }
      if (i == 0) path.moveTo(x, y); else path.lineTo(x, y);
    }
    _layeredPath(canvas, path, accent, .58 * fade, 2.2 * scale, glow: 4.0);
    final p = <String, dynamic>{...item, 'origin': 'caster', 'direction': target.dx >= caster.dx ? 'left_to_right' : 'right_to_left', 'motion': 'stream'};
    _drawParticles(canvas, size, caster, p, t, intensity, burst: false);
  }

  void _drawSlash(Canvas canvas, Size size, Offset caster, Offset target, Map<String, dynamic> item, double t, double scale, int intensity, double fade, String pathKind) {
    final reveal = _easeOut(t);
    final reverse = _s(item['direction']) == 'right_to_left';
    final start = reverse ? Offset(size.width * .88, target.dy + 34 * scale) : Offset(size.width * .10, target.dy + 34 * scale);
    final endFull = reverse ? Offset(size.width * .10, target.dy - 34 * scale) : Offset(size.width * .90, target.dy - 34 * scale);
    final end = Offset(start.dx + (endFull.dx - start.dx) * reveal, start.dy + (endFull.dy - start.dy) * reveal);
    final mid = Offset((start.dx + end.dx) * .5, (start.dy + end.dy) * .5 - (pathKind == 'crescent' ? 46 : 18) * scale);
    final slash = Path()..moveTo(start.dx, start.dy)..quadraticBezierTo(mid.dx, mid.dy, end.dx, end.dy);
    canvas.drawPath(slash, _stroke(Colors.black, .88 * fade, (7.5 + intensity * .25) * scale));
    _layeredPath(canvas, slash, accent, .96 * fade, (2.5 + intensity * .12) * scale, glow: 5.5 + _d(item['glow'], .4) * 5);
    final amount = _i(item['amount'], 4).clamp(1, 10).toInt();
    for (var i = 0; i < amount; i++) {
      final off = (i - (amount - 1) / 2) * 4.2 * scale;
      final ghost = Path()..moveTo(start.dx, start.dy + off)..quadraticBezierTo(mid.dx, mid.dy + off * .35, end.dx, end.dy + off);
      canvas.drawPath(ghost, _stroke(accent, .11 * fade, .65));
    }
  }

  void _drawProjectile(Canvas canvas, Size size, Offset caster, Offset target, Map<String, dynamic> item, double t, double scale, int intensity, double fade) {
    final q = _easeOut(t);
    final arc = _s(item['path']) == 'arc' ? -math.sin(q * math.pi) * 42 * scale : -math.sin(q * math.pi) * 14 * scale;
    final p = Offset(caster.dx + (target.dx - caster.dx) * q, caster.dy + (target.dy - caster.dy) * q + arc);
    final prevQ = math.max(0.0, q - .12);
    final prev = Offset(caster.dx + (target.dx - caster.dx) * prevQ, caster.dy + (target.dy - caster.dy) * prevQ + (_s(item['path']) == 'arc' ? -math.sin(prevQ * math.pi) * 42 * scale : 0));
    _drawParticleShape(canvas, _s(item['shape'], 'diamond'), p, prev, (2.2 + intensity * .10) * scale, fade, _d(item['glow'], .35), 0, _i(item['seed'], 0));
    canvas.drawLine(prev, p, _stroke(accent, .36 * fade, 2.2 * scale, blur: 2));
  }

  void _drawLightning(Canvas canvas, Size size, Offset origin, Offset target, Map<String, dynamic> item, double t, double scale, int intensity, double fade, int seed) {
    final amount = _i(item['amount'], 5).clamp(2, 12).toInt();
    final q = _easeOut(t);
    for (var b = 0; b < amount; b++) {
      final randomA = _seed01(b, 157, seed) * math.pi * 2;
      final baseA = _directionAngle(_s(item['direction'], 'radial'), randomA);
      final length = (42 + intensity * 7 + _seed01(b, 163, seed) * 52) * scale * q;
      final path = Path()..moveTo(origin.dx, origin.dy);
      var x = origin.dx;
      var y = origin.dy;
      for (var k = 1; k <= 8; k++) {
        final u = k / 8;
        final perp = (_seed01(b * 19 + k, 167, seed) - .5) * 24 * scale * (1 - u * .35);
        x = origin.dx + math.cos(baseA) * length * u + math.cos(baseA + math.pi / 2) * perp;
        y = origin.dy + math.sin(baseA) * length * u + math.sin(baseA + math.pi / 2) * perp;
        path.lineTo(x, y);
      }
      _layeredPath(canvas, path, accent, .72 * fade, 1.25 * scale, glow: 3.2);
    }
  }

  void _drawShockwave(Canvas canvas, Offset c, Map<String, dynamic> item, double t, double scale, int intensity, double fade, int seed, {required bool explosion}) {
    final q = _easeOut(t);
    final r = (14 + q * (explosion ? 132 : 96)) * scale;
    canvas.drawCircle(c, r, _stroke(accent, .56 * fade, explosion ? 2.8 : 1.7));
    canvas.drawCircle(c, r * .72, _stroke(Colors.white, .30 * fade, .75));
    if (explosion) {
      final rays = (_i(item['amount'], 5) * 3).clamp(10, 30).toInt();
      for (var i = 0; i < rays; i++) {
        final a = i * math.pi * 2 / rays + (_seed01(i, 173, seed) - .5) * .12;
        final inner = r * (.12 + _seed01(i, 179, seed) * .08);
        final outer = r * (.55 + _seed01(i, 181, seed) * .40);
        canvas.drawLine(Offset(c.dx + math.cos(a) * inner, c.dy + math.sin(a) * inner), Offset(c.dx + math.cos(a) * outer, c.dy + math.sin(a) * outer), _stroke(i.isEven ? Colors.white : accent, .42 * fade, .65 + _seed01(i, 191, seed)));
      }
      final core = (5 + 11 * _pulse(t)) * scale;
      canvas.drawCircle(c, core * 2.5, _fill(accent, .12 * fade, blur: 4, additive: true));
      canvas.drawCircle(c, core, _fill(Colors.white, .80 * fade));
    }
  }

  void _drawHealRing(Canvas canvas, Offset c, Map<String, dynamic> item, double t, double scale, int intensity, double fade) {
    final amount = _i(item['amount'], 4).clamp(2, 10).toInt();
    final q = _easeOut(t);
    for (var i = 0; i < amount; i++) {
      final r = (22 + i * 13 + q * 24) * scale;
      final rect = Rect.fromCircle(center: c, radius: r);
      canvas.drawArc(rect, -math.pi * .8 + i * .6 + t, math.pi * 1.18, false, _stroke(i.isEven ? accent : Colors.white, (.34 - i * .025) * fade, 1.0));
    }
    for (var i = 0; i < 6; i++) {
      final a = i * math.pi * 2 / 6 - t * .6;
      final p = Offset(c.dx + math.cos(a) * 18 * scale, c.dy + math.sin(a) * 18 * scale);
      canvas.drawCircle(p, 1.3 * scale, _fill(Colors.white, .42 * fade));
    }
  }

  void _drawShield(Canvas canvas, Offset c, Map<String, dynamic> item, double t, double scale, int intensity, double fade) {
    final q = _easeOut(t);
    final r = (34 + intensity * 2.4 + 12 * _pulse(t)) * scale * q;
    final shield = Path()
      ..moveTo(c.dx, c.dy - r)
      ..quadraticBezierTo(c.dx + r * .88, c.dy - r * .45, c.dx + r * .68, c.dy + r * .40)
      ..quadraticBezierTo(c.dx + r * .34, c.dy + r * .96, c.dx, c.dy + r * 1.12)
      ..quadraticBezierTo(c.dx - r * .34, c.dy + r * .96, c.dx - r * .68, c.dy + r * .40)
      ..quadraticBezierTo(c.dx - r * .88, c.dy - r * .45, c.dx, c.dy - r)
      ..close();
    canvas.drawPath(shield, _fill(accent, .045 * fade));
    _layeredPath(canvas, shield, accent, .68 * fade, 1.7 * scale, glow: 3.2, whiteCore: false);
    _drawSigil(canvas, c, {...item, 'amount': 4, 'variant': 2}, t, scale * .62, intensity, fade, ringOnly: false);
  }

  void _drawAfterimages(Canvas canvas, Size size, Offset caster, Offset target, Map<String, dynamic> item, double t, double scale, double fade) {
    final count = _i(item['amount'], 5).clamp(2, 10).toInt();
    final dx = target.dx - caster.dx;
    final dy = target.dy - caster.dy;
    final distance = math.max(1.0, math.sqrt(dx * dx + dy * dy));
    final ux = dx / distance;
    final uy = dy / distance;
    final nx = -uy;
    final ny = ux;
    for (var i = count - 1; i >= 0; i--) {
      final u = (t - i * .055).clamp(0.0, 1.0).toDouble();
      final eased = _easeOut(u);
      final p = Offset(
        caster.dx + dx * eased,
        caster.dy + dy * u - math.sin(u * math.pi) * 10,
      );
      final opacity = (.07 + (count - i) * .026) * fade;
      final length = (18 + (count - i) * 5.0) * scale;
      final bend = math.sin((u + i * .17) * math.pi * 2) * 6 * scale;
      final start = Offset(p.dx - ux * length, p.dy - uy * length);
      final end = Offset(p.dx + ux * 7 * scale, p.dy + uy * 7 * scale);
      final path = Path()
        ..moveTo(start.dx, start.dy)
        ..quadraticBezierTo(
          p.dx + nx * bend,
          p.dy + ny * bend,
          end.dx,
          end.dy,
        );
      canvas.drawPath(path, _stroke(accent, opacity * .72, 5.2 * scale, blur: 6));
      canvas.drawPath(path, _stroke(accent, opacity, 1.45 * scale));
      canvas.drawPath(path, _stroke(Colors.white, opacity * .42, .55 * scale));
    }
  }

  void _drawSpaceCrack(Canvas canvas, Size size, Offset c, Map<String, dynamic> item, double t, double scale, int intensity, double fade, int seed) {
    final q = _easeOut(math.min(1.0, t * 1.3));
    final start = Offset(size.width * .10, c.dy + 22 * scale);
    final end = Offset(size.width * .90, c.dy - 28 * scale);
    final main = Path()..moveTo(start.dx, start.dy);
    final segments = 18;
    for (var i = 1; i <= segments; i++) {
      final u = i / segments * q;
      final x = start.dx + (end.dx - start.dx) * u;
      final y = start.dy + (end.dy - start.dy) * u + (_seed01(i, 197, seed) - .5) * 9 * scale;
      main.lineTo(x, y);
    }
    canvas.drawPath(main, _stroke(Colors.black, .96 * fade, (7 + intensity * .2) * scale));
    canvas.drawPath(main, _stroke(accent, .78 * fade, 1.8 * scale, blur: 2.8));
    canvas.drawPath(main, _stroke(Colors.white, .56 * fade, .65 * scale));
    final branches = _i(item['amount'], 7).clamp(3, 12).toInt();
    for (var i = 0; i < branches; i++) {
      final u = .15 + i / math.max(1, branches - 1) * .70;
      if (u > q) continue;
      var x = start.dx + (end.dx - start.dx) * u;
      var y = start.dy + (end.dy - start.dy) * u;
      final branch = Path()..moveTo(x, y);
      final side = i.isEven ? -1.0 : 1.0;
      for (var k = 0; k < 4; k++) {
        x += side * (8 + _seed01(i * 13 + k, 199, seed) * 17) * scale;
        y += (_seed01(i * 17 + k, 211, seed) - .5) * 22 * scale;
        branch.lineTo(x, y);
      }
      canvas.drawPath(branch, _stroke(accent, .42 * fade, .75));
    }
  }
}


Future<String?> _showCompanionSkillDetails(
  BuildContext context,
  JsonMap skill,
) {
  final type = _companionSkillTypeOf(skill);
  final typeName = _companionSkillTypeName(type);
  final quality = intValue(skill['quality']).clamp(1, 10).toInt();
  final color = _companionSkillQualityColor(quality);
  final skillName = stringValue(skill['name'], '未命名');

  return showDialog<String>(
    context: context,
    barrierColor: Colors.black.withOpacity(.20),
    builder: (dialogContext) => _CharacterDialogBackdrop(child: Dialog(
      elevation: 0,
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      child: _CharacterGlassDialogFrame(
        width: 370,
        child: Stack(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.only(right: 30),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: <Widget>[
                        Image.asset(
                          _companionSkillTypeAsset(type),
                          width: 32,
                          height: 32,
                          color: color,
                          semanticLabel: typeName,
                          errorBuilder: (_, __, ___) => Icon(
                            _companionSkillFallbackIcon(type),
                            size: 32,
                            color: color,
                            semanticLabel: typeName,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                skillName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: _characterText,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: .42,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Row(
                                children: <Widget>[
                                  Container(
                                    width: 12,
                                    height: 1,
                                    color: color.withOpacity(.62),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    typeName,
                                    style: TextStyle(
                                      color: color.withOpacity(.94),
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: .75,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '$quality 品',
                                    style: TextStyle(
                                      color: _characterTextMuted.withOpacity(.84),
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: .55,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    height: 176,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: const Color(0xFF050711),
                      border: Border.all(color: color.withOpacity(.24), width: .8),
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: color.withOpacity(.07),
                          blurRadius: 16,
                          spreadRadius: 0,
                        ),
                      ],
                    ),
                    child: _CompanionSkillVfxPreview(
                      key: ValueKey<String>('detail-${stringValue(skill['id'])}-$skillName'),
                      skill: skill,
                      tapToReplay: true,
                      showReplayHint: true,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    '技能效果',
                    style: TextStyle(
                      color: _characterTextMuted.withOpacity(.82),
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.35,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(0, 10, 0, 0),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(
                          color: Colors.white.withOpacity(.06),
                          width: .8,
                        ),
                      ),
                    ),
                    child: Text(
                      _companionSkillEffectText(skill),
                      style: TextStyle(
                        color: _characterTextSoft.withOpacity(.95),
                        fontSize: 12.5,
                        height: 1.72,
                        letterSpacing: .12,
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Container(
                    width: double.infinity,
                    height: .8,
                    color: Colors.white.withOpacity(.06),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: <Widget>[
                      _CharacterSkillDialogAction(
                        label: '舍弃技能',
                        foreground: _characterTextSoft.withOpacity(.86),
                        fillColor: Colors.white.withOpacity(.018),
                        borderColor: Colors.white.withOpacity(.10),
                        onTap: () => Navigator.of(dialogContext).pop('discard'),
                      ),
                      const Spacer(),
                      _CharacterSkillDialogAction(
                        label: '修改名称',
                        foreground: _characterText,
                        fillColor: color.withOpacity(.12),
                        borderColor: color.withOpacity(.40),
                        onTap: () => Navigator.of(dialogContext).pop('rename'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Positioned(
              right: 0,
              top: 0,
              child: _CharacterDialogCloseButton(
                onTap: () => Navigator.of(dialogContext).pop(),
              ),
            ),
          ],
        ),
      ),
    )),
  );
}

Future<bool?> _confirmDiscardCompanionSkill(
  BuildContext context,
  String skillName,
) {
  return showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withOpacity(.22),
    builder: (dialogContext) => _CharacterDialogBackdrop(child: Dialog(
      elevation: 0,
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      child: _CharacterGlassDialogFrame(
        width: 332,
        child: Stack(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(23, 22, 23, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Padding(
                    padding: EdgeInsets.only(right: 28),
                    child: Text(
                      '舍弃技能',
                      style: TextStyle(
                        color: _characterText,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .35,
                      ),
                    ),
                  ),
                  const SizedBox(height: 11),
                  Text(
                    '「$skillName」舍弃后无法恢复。之后学习新的援战技能会消耗 1 本技能书。',
                    style: TextStyle(
                      color: _characterTextSoft.withOpacity(.86),
                      fontSize: 11.5,
                      height: 1.68,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: <Widget>[
                      _CharacterSkillDialogAction(
                        label: '返回',
                        foreground: _characterTextMuted.withOpacity(.92),
                        fillColor: Colors.white.withOpacity(.025),
                        borderColor: Colors.white.withOpacity(.10),
                        onTap: () => Navigator.of(dialogContext).pop(false),
                      ),
                      const Spacer(),
                      _CharacterSkillDialogAction(
                        label: '确认舍弃',
                        foreground: _characterText,
                        fillColor: _characterGoldSoft.withOpacity(.09),
                        borderColor: _characterGoldSoft.withOpacity(.30),
                        onTap: () => Navigator.of(dialogContext).pop(true),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Positioned(
              right: 0,
              top: 0,
              child: _CharacterDialogCloseButton(
                onTap: () => Navigator.of(dialogContext).pop(false),
              ),
            ),
          ],
        ),
      ),
    )),
  );
}

class _CharacterSkillDialogAction extends StatelessWidget {
  const _CharacterSkillDialogAction({
    required this.label,
    required this.foreground,
    required this.onTap,
    this.icon,
    this.fillColor = Colors.transparent,
    this.borderColor = Colors.transparent,
  });

  final String label;
  final IconData? icon;
  final Color foreground;
  final Color fillColor;
  final Color borderColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashColor: foreground.withOpacity(.06),
        highlightColor: foreground.withOpacity(.035),
        child: Container(
          constraints: const BoxConstraints(minHeight: 34),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          decoration: BoxDecoration(
            color: fillColor,
            border: Border.all(color: borderColor, width: .8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(
                label,
                style: TextStyle(
                  color: foreground,
                  fontSize: 10.8,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .78,
                ),
              ),
              if (icon != null) ...<Widget>[
                const SizedBox(width: 5),
                Icon(icon, size: 12.5, color: foreground),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CharacterCompanionSkillsPanel extends StatelessWidget {
  const _CharacterCompanionSkillsPanel({
    required this.skills,
    required this.cooperating,
    required this.busy,
    required this.onToggleCooperation,
    required this.onLearn,
    required this.onRename,
    this.compact = false,
  });

  final List<JsonMap> skills;
  final bool cooperating;
  final bool busy;
  final VoidCallback onToggleCooperation;
  final VoidCallback onLearn;
  final ValueChanged<JsonMap> onRename;
  final bool compact;

  Color _qualityColor(int quality) {
    return switch (quality.clamp(1, 10)) {
      10 => const Color(0xFFFF5C7C),
      9 => const Color(0xFFFFCA62),
      8 => const Color(0xFFFF9D5C),
      7 => const Color(0xFFD979FF),
      6 => const Color(0xFFA88BFF),
      5 => const Color(0xFF5BD9F5),
      4 => const Color(0xFF64AEFF),
      3 => const Color(0xFF62D6B3),
      2 => const Color(0xFF91A9C7),
      _ => const Color(0xFFB9C5D6),
    };
  }

  String _skillType(JsonMap skill) {
    var type = stringValue(skill['category']).trim().toLowerCase();
    if (type.isEmpty) {
      type = stringValue(asJsonMap(skill['battle_spec'])['archetype'])
          .trim()
          .toLowerCase();
    }
    if (type.isNotEmpty) return type;

    final effects = asJsonList(asJsonMap(skill['battle_spec'])['effects']);
    if (effects.isNotEmpty) {
      final effectType = stringValue(asJsonMap(effects.first)['type'])
          .trim()
          .toLowerCase();
      return switch (effectType) {
        'damage_over_time' => 'dot',
        'energy_restore' => 'energy',
        'next_attack_bonus' => 'expose',
        _ => effectType,
      };
    }
    return 'direct';
  }

  String _skillTypeName(String type) => switch (type) {
        'direct' => '直击',
        'dot' => '持续伤害',
        'guard' => '守护',
        'evade' => '闪避',
        'heal' => '治疗',
        'energy' => '精力恢复',
        'lifesteal' => '吸血',
        'expose' => '破绽',
        'counter' => '反击',
        'stun' => '压制',
        _ => '攻击',
      };

  String _skillTypeAsset(String type) => switch (type) {
        'direct' => 'assets/images/companion_skill_icons/direct.webp',
        'dot' => 'assets/images/companion_skill_icons/dot.webp',
        'guard' => 'assets/images/companion_skill_icons/guard.webp',
        'evade' => 'assets/images/companion_skill_icons/evade.webp',
        'heal' => 'assets/images/companion_skill_icons/heal.webp',
        'energy' => 'assets/images/companion_skill_icons/energy.webp',
        'lifesteal' => 'assets/images/companion_skill_icons/lifesteal.webp',
        'expose' => 'assets/images/companion_skill_icons/expose.webp',
        'counter' => 'assets/images/companion_skill_icons/counter.webp',
        'stun' => 'assets/images/companion_skill_icons/stun.webp',
        _ => 'assets/images/companion_skill_icons/direct.webp',
      };

  IconData _skillTypeFallbackIcon(String type) => switch (type) {
        'direct' => Icons.flash_on_rounded,
        'dot' => Icons.local_fire_department_rounded,
        'guard' => Icons.shield_rounded,
        'evade' => Icons.air_rounded,
        'heal' => Icons.favorite_rounded,
        'energy' => Icons.bolt_rounded,
        'lifesteal' => Icons.bloodtype_rounded,
        'expose' => Icons.gps_fixed_rounded,
        'counter' => Icons.reply_rounded,
        'stun' => Icons.auto_awesome_rounded,
        _ => Icons.flash_on_rounded,
      };

  Widget _skillSlot(JsonMap? skill) {
    if (skill == null) {
      // 桌面端不要在频繁重建的技能槽上使用 Tooltip。Tooltip 内部依赖
      // OverlayPortal，Windows 鼠标 hover + 面板重建时可能触发 overlay/mouse_tracker
      // 的调试断言。这里用 Semantics 保留可访问性说明，不创建悬浮 Overlay。
      return Semantics(
        label: '学习新技能，消耗 1 本技能书',
        button: true,
        enabled: !busy,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: busy ? null : onLearn,
          child: Container(
            height: compact ? 30 : 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(.025),
              border: Border.all(color: Colors.white.withOpacity(.13)),
            ),
            child: Icon(
              Icons.add_rounded,
              size: compact ? 16 : 18,
              color: busy
                  ? _characterTextMuted.withOpacity(.35)
                  : _characterTextMuted,
            ),
          ),
        ),
      );
    }

    final quality = intValue(skill['quality']).clamp(1, 10).toInt();
    final color = _qualityColor(quality);
    final type = _skillType(skill);
    final typeName = _skillTypeName(type);
    final skillName = stringValue(skill['name'], '未命名');
    return Semantics(
      label: '$typeName，$skillName',
      button: true,
      enabled: !busy,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: busy ? null : () => onRename(skill),
        child: Container(
          height: compact ? 30 : 34,
          padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 8),
          decoration: BoxDecoration(
            color: color.withOpacity(.075),
            border: Border.all(color: color.withOpacity(.46)),
          ),
          child: Row(
            children: <Widget>[
              Image.asset(
                _skillTypeAsset(type),
                width: compact ? 13 : 15,
                height: compact ? 13 : 15,
                color: color,
                semanticLabel: typeName,
                errorBuilder: (_, __, ___) => Icon(
                  _skillTypeFallbackIcon(type),
                  size: compact ? 13 : 15,
                  color: color,
                  semanticLabel: typeName,
                ),
              ),
              SizedBox(width: compact ? 4 : 6),
              Expanded(
                child: Text(
                  skillName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: compact ? 8.5 : 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final slots = <JsonMap?>[
      ...skills.take(4),
      ...List<JsonMap?>.filled(4 - skills.take(4).length, null),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(child: _skillSlot(slots[0])),
            const SizedBox(width: 6),
            Expanded(child: _skillSlot(slots[1])),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: <Widget>[
            Expanded(child: _skillSlot(slots[2])),
            const SizedBox(width: 6),
            Expanded(child: _skillSlot(slots[3])),
          ],
        ),
        const SizedBox(height: 9),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: busy ? null : onToggleCooperation,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: double.infinity,
            height: compact ? 34 : 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: cooperating
                  ? _characterBlueBright
                  : Colors.white.withOpacity(.055),
              border: Border.all(
                color: cooperating
                    ? _characterBlueBright
                    : Colors.white.withOpacity(.18),
              ),
              boxShadow: cooperating
                  ? <BoxShadow>[
                      BoxShadow(
                        color: _characterBlueBright.withOpacity(.22),
                        blurRadius: 10,
                      ),
                    ]
                  : const <BoxShadow>[],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(
                  cooperating ? Icons.link_off_rounded : Icons.link_rounded,
                  size: 14,
                  color: cooperating ? Colors.white : _characterTextSoft,
                ),
                const SizedBox(width: 6),
                Text(
                  cooperating ? '取消协同' : '协同出战',
                  style: TextStyle(
                    color: cooperating ? Colors.white : _characterTextSoft,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
class _CharacterCompactMeta extends StatelessWidget {
  const _CharacterCompactMeta({
    required this.character,
    required this.identity,
    required this.appearance,
    required this.stars,
    required this.stats,
    required this.onChangePortrait,
    required this.star,
    required this.fragments,
    required this.onUpgrade,
    required this.companionSkills,
    required this.cooperating,
    required this.companionBusy,
    required this.onToggleCooperation,
    required this.onLearn,
    required this.onRename,
  });

  final NovelCharacter character;
  final String identity;
  final String appearance;
  final Widget stars;
  final List<MapEntry<String, String>> stats;
  final VoidCallback onChangePortrait;
  final int star;
  final int fragments;
  final VoidCallback onUpgrade;
  final List<JsonMap> companionSkills;
  final bool cooperating;
  final bool companionBusy;
  final VoidCallback? onToggleCooperation;
  final VoidCallback? onLearn;
  final ValueChanged<JsonMap> onRename;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(),
      child: Padding(
        padding: const EdgeInsets.only(right: 9),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Text(
              character.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: _characterText,
                fontSize: 22,
                height: 1,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 6),
            if (identity.isNotEmpty)
              Text(
                identity,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  color: _characterGold,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .7,
                ),
              ),
            const SizedBox(height: 6),
            stars,
            if (onToggleCooperation != null && onLearn != null) ...<Widget>[
              const SizedBox(height: 9),
              _CharacterCompanionSkillsPanel(
                skills: companionSkills,
                cooperating: cooperating,
                busy: companionBusy,
                compact: true,
                onToggleCooperation: onToggleCooperation!,
                onLearn: onLearn!,
                onRename: onRename,
              ),
            ],
            if (appearance.isNotEmpty) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                appearance,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: _characterTextSoft.withOpacity(.8),
                  fontSize: 10.5,
                  height: 1.5,
                ),
              ),
            ],
            const SizedBox(height: 8),
            _CharacterProfileActions(
              compact: true,
              star: star,
              fragments: fragments,
              onChangePortrait: onChangePortrait,
              onUpgrade: onUpgrade,
            ),
          ],
        ),
      ),
    );
  }
}

class _CharacterStageInfo extends StatelessWidget {
  const _CharacterStageInfo({
    required this.character,
    required this.identity,
    required this.appearance,
    required this.stars,
    required this.stats,
    required this.onChangePortrait,
    required this.star,
    required this.fragments,
    required this.onUpgrade,
    required this.companionSkills,
    required this.cooperating,
    required this.companionBusy,
    required this.onToggleCooperation,
    required this.onLearn,
    required this.onRename,
  });

  final NovelCharacter character;
  final String identity;
  final String appearance;
  final Widget stars;
  final List<MapEntry<String, String>> stats;
  final VoidCallback onChangePortrait;
  final int star;
  final int fragments;
  final VoidCallback onUpgrade;
  final List<JsonMap> companionSkills;
  final bool cooperating;
  final bool companionBusy;
  final VoidCallback? onToggleCooperation;
  final VoidCallback? onLearn;
  final ValueChanged<JsonMap> onRename;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 24),
      child: DecoratedBox(
        decoration: const BoxDecoration(),
        child: Padding(
          padding: const EdgeInsets.only(left: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                character.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _characterText,
                  fontSize: 34,
                  height: 1,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.6,
                ),
              ),
              if (identity.isNotEmpty) ...<Widget>[
                const SizedBox(height: 7),
                Text(
                  identity,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _characterTextSoft,
                    fontSize: 9.5,
                    letterSpacing: .7,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              stars,
              Container(
                height: 1,
                margin: const EdgeInsets.symmetric(vertical: 13),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: <Color>[
                      _characterGold,
                      Color(0x00C9B778),
                    ],
                  ),
                ),
              ),
              if (onToggleCooperation != null && onLearn != null)
                _CharacterCompanionSkillsPanel(
                  skills: companionSkills,
                  cooperating: cooperating,
                  busy: companionBusy,
                  onToggleCooperation: onToggleCooperation!,
                  onLearn: onLearn!,
                  onRename: onRename,
                ),
              if (appearance.isNotEmpty) ...<Widget>[
                const SizedBox(height: 15),
                const Text(
                  '形象',
                  style: TextStyle(
                    color: _characterText,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  appearance,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _characterTextSoft.withOpacity(.88),
                    fontSize: 9.3,
                    height: 1.55,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              _CharacterProfileActions(
                star: star,
                fragments: fragments,
                onChangePortrait: onChangePortrait,
                onUpgrade: onUpgrade,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CharacterInlineChat extends StatefulWidget {
  const _CharacterInlineChat({
    required this.controller,
    required this.character,
    this.dense = false,
    this.messageLeftInset = 0,
    this.messageRightInset = 0,
  });

  final NovelGameController controller;
  final NovelCharacter character;
  final bool dense;

  /// 只限制聊天记录显示区；底部输入框始终保持父级提供的完整宽度。
  /// 手机横屏时把记录区压进立绘下半部，竖屏 / PC 默认仍为 0。
  final double messageLeftInset;
  final double messageRightInset;

  @override
  State<_CharacterInlineChat> createState() => _CharacterInlineChatState();
}

class _CharacterInlineChatState extends State<_CharacterInlineChat> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<_NovelCharacterChatLine> _messages = <_NovelCharacterChatLine>[];
  bool _loading = true;
  bool _sending = false;
  String _errorText = '';
  int _requestTicket = 0;
  int _lineSequence = 0;

  String get _characterKey => widget.character.id.trim().isNotEmpty
      ? widget.character.id.trim()
      : widget.character.name.trim();

  bool get _canChat =>
      !widget.character.isMain && widget.character.id.trim().isNotEmpty;

  _NovelCharacterChatLine _newLine({
    required String role,
    required String text,
    bool animate = false,
  }) {
    return _NovelCharacterChatLine(
      id: ++_lineSequence,
      role: role,
      text: text,
      animate: animate,
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_loadHistory());
    });
  }

  @override
  void didUpdateWidget(covariant _CharacterInlineChat oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldKey = oldWidget.character.id.trim().isNotEmpty
        ? oldWidget.character.id.trim()
        : oldWidget.character.name.trim();
    if (oldKey != _characterKey) {
      _requestTicket++;
      if (_sending) {
        unawaited(oldWidget.controller.cancelNovelCharacterChatStream());
      }
      _controller.clear();
      _messages.clear();
      _loading = true;
      _sending = false;
      _errorText = '';
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_loadHistory());
      });
    }
  }

  @override
  void dispose() {
    _requestTicket++;
    if (_sending) {
      unawaited(widget.controller.cancelNovelCharacterChatStream());
    }
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  List<_NovelCharacterChatLine> _parseHistory(JsonMap payload) {
    final result = <_NovelCharacterChatLine>[];
    for (final raw in asJsonList(payload['messages'])) {
      final item = asJsonMap(raw);
      final role = stringValue(item['role']).trim().toLowerCase();
      if (role != 'user' && role != 'assistant') continue;

      final parts = <String>[];
      if (role == 'assistant') {
        for (final rawPart in asJsonList(item['messages'])) {
          final part = rawPart is Map
              ? stringValue(
                  asJsonMap(rawPart)['text'] ??
                      asJsonMap(rawPart)['content'] ??
                      asJsonMap(rawPart)['message'],
                ).trim()
              : stringValue(rawPart).trim();
          if (part.isNotEmpty) parts.add(part);
        }
      }
      if (parts.isEmpty) {
        final content = stringValue(item['content']).trim();
        if (content.isNotEmpty) parts.add(content);
      }
      for (final text in parts) {
        result.add(
          _newLine(
            role: role,
            text: text,
          ),
        );
      }
    }
    return result;
  }

  Future<void> _loadHistory() async {
    final ticket = ++_requestTicket;
    if (!_canChat) {
      if (!mounted || ticket != _requestTicket) return;
      setState(() {
        _messages.clear();
        _loading = false;
        _sending = false;
        _errorText = '';
      });
      return;
    }

    setState(() {
      _loading = true;
      _errorText = '';
    });
    try {
      final payload = await widget.controller.fetchNovelCharacterChatHistory(
        widget.character.id,
        limit: 50,
      );
      if (!mounted || ticket != _requestTicket) return;
      final history = _parseHistory(payload);
      final affection = intValue(payload['affection'], -1);
      if (affection >= 0) {
        widget.controller.applyNovelCharacterChatEvent(<String, dynamic>{
          'type': 'affection_update',
          'character_instance_id': widget.character.id,
          'character_name': widget.character.name,
          'affection': affection,
        });
      }
      if (!mounted || ticket != _requestTicket) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(history);
        _loading = false;
      });
      _scrollToBottom(jump: true);
    } catch (error) {
      if (!mounted || ticket != _requestTicket) return;
      setState(() {
        _loading = false;
        _errorText = error is NovelBackendException
            ? error.message
            : '聊天记录加载失败：$error';
      });
    }
  }

  Future<void> _appendAssistantText(
    String text, {
    required int ticket,
    required int partIndex,
    required int previousPartLength,
  }) async {
    final value = text.trim();
    if (value.isEmpty) return;

    if (partIndex > 0) {
      final pauseMs = math.min(900, 320 + previousPartLength * 16).toInt();
      await Future<void>.delayed(Duration(milliseconds: pauseMs));
      if (!mounted || ticket != _requestTicket) return;
    }

    setState(() {
      _messages.add(
        _newLine(role: 'assistant', text: value, animate: true),
      );
    });
    _scrollToBottom();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _loading || _sending || !_canChat) return;

    final characterId = widget.character.id.trim();
    final ticket = ++_requestTicket;
    setState(() {
      _messages.add(_newLine(role: 'user', text: text, animate: true));
      _sending = true;
      _errorText = '';
    });
    _controller.clear();
    _scrollToBottom();

    var receivedReply = false;
    var replyPartIndex = 0;
    var previousReplyLength = 0;
    try {
      await for (final event
          in widget.controller.sendNovelCharacterChatStream(
        characterInstanceId: characterId,
        message: text,
      )) {
        if (!mounted || ticket != _requestTicket) return;
        final type = stringValue(event['type']).trim().toLowerCase();
        if (type == 'chat_message' || type == 'content') {
          final reply = stringValue(
            event['text'] ?? event['content'] ?? event['message'],
          );
          if (reply.trim().isNotEmpty) {
            receivedReply = true;
            await _appendAssistantText(
              reply,
              ticket: ticket,
              partIndex: replyPartIndex,
              previousPartLength: previousReplyLength,
            );
            previousReplyLength = reply.trim().length;
            replyPartIndex++;
          }
        } else if (type == 'affection_update') {
          widget.controller.applyNovelCharacterChatEvent(event);
        } else if (type == 'error' || type == 'empty_reply') {
          throw NovelBackendException(
            stringValue(event['message'], '角色回复失败，请重试'),
            code: stringValue(event['code']),
            details: event,
          );
        }
      }
      if (!mounted || ticket != _requestTicket) return;
      if (!receivedReply) {
        throw const NovelBackendException('没有收到角色回复，请重试');
      }
    } catch (error) {
      if (!mounted || ticket != _requestTicket) return;
      setState(() {
        _errorText = error is NovelBackendException
            ? error.message
            : '发送失败：$error';
      });
    } finally {
      if (mounted && ticket == _requestTicket) {
        setState(() => _sending = false);
        _scrollToBottom();
      }
    }
  }

  void _scrollToBottom({bool jump = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final target = _scrollController.position.maxScrollExtent;
      if (jump) {
        _scrollController.jumpTo(target);
      } else {
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final desktopMode = widget.controller.desktopMode && !widget.dense;
    return Column(
      children: <Widget>[
        Expanded(
          // 横屏 dense 模式只收窄“聊天记录”本身，让它覆盖在立绘下半部；
          // 下方输入框仍处在 Column 外层，因此继续占用原来的完整宽度。
          child: Padding(
            padding: EdgeInsets.only(
              left: widget.dense ? widget.messageLeftInset : 0,
              right: widget.dense ? widget.messageRightInset : 0,
            ),
            child: Container(
              margin: EdgeInsets.only(bottom: widget.dense ? 5 : 8),
              // 横屏、竖屏和桌面统一取消聊天区的大面积渐变/ShaderMask 遮罩。
              // 对话直接覆盖在立绘上，可读性由消息文字描边负责。
              child: ListView.separated(
                controller: _scrollController,
                padding: EdgeInsets.fromLTRB(
                  widget.dense ? 3 : 6,
                  widget.dense ? 3 : 14,
                  widget.dense ? 3 : 6,
                  widget.dense ? 4 : 18,
                ),
                itemCount: _messages.isEmpty ? 1 : _messages.length,
                separatorBuilder: (_, __) =>
                    SizedBox(height: widget.dense ? 3 : 9),
                itemBuilder: (context, index) {
                  if (_messages.isEmpty) {
                    // 空聊天保持画面干净，不再显示引导文案。
                    if (!_loading && _canChat) {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: 22),
                      child: Text(
                        _loading ? '正在读取对话…' : '主角不能与自己私聊',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: widget.dense
                              ? _characterTextSoft
                              : _characterTextMuted,
                          fontSize: widget.dense ? 9.2 : 10.5,
                          shadows: _characterTextOutlineShadows,
                        ),
                      ),
                    );
                  }
                  final message = _messages[index];
                  final line = _CharacterChatLineView(
                    message: message,
                    desktopMode: desktopMode,
                    dense: widget.dense,
                  );
                  if (!message.animate) return line;
                  return TweenAnimationBuilder<double>(
                    key: ValueKey<int>(message.id),
                    tween: Tween<double>(begin: 0, end: 1),
                    duration: Duration(
                      milliseconds: message.isUser ? 180 : 300,
                    ),
                    curve: Curves.easeOutCubic,
                    builder: (context, value, child) {
                      return Opacity(
                        opacity: value,
                        child: Transform.translate(
                          offset: Offset(0, (1 - value) * 7),
                          child: child,
                        ),
                      );
                    },
                    child: line,
                  );
                },
              ),
            ),
          ),
        ),
        if (_errorText.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    _errorText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFE8A6A6),
                      fontSize: 9.5,
                    ),
                  ),
                ),
                if (!_sending)
                  InkWell(
                    onTap: _loadHistory,
                    child: const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: Text(
                        '重新加载',
                        style: TextStyle(
                          color: _characterGold,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),

        Container(
          height: widget.dense ? 34 : (desktopMode ? 38 : 46),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            // 输入区只保留细边框，不再额外铺半透明底色。
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: Colors.white.withOpacity(0.18),
            ),
          ),
          child: Row(
            children: <Widget>[
              const SizedBox(width: 14),
              Expanded(
                child: TextField(
                  controller: _controller,
                  enabled: _canChat && !_loading && !_sending,
                  onSubmitted: (_) => _send(),
                  textInputAction: TextInputAction.send,
                  cursorColor: _characterGold,
                  style: TextStyle(
                    color: _characterText,
                    fontSize: widget.dense ? 11.5 : 13,
                    shadows: _characterTextOutlineShadows,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: !_canChat
                        ? '主角不能与自己私聊'
                        : _sending
                            ? '${widget.character.name}正在回复…'
                            : '输入想说的话…',
                    hintStyle: TextStyle(
                      color: _characterTextMuted,
                      fontSize: 12.5,
                      shadows: _characterTextOutlineShadows,
                    ),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: widget.dense ? 6 : 10),
                  ),
                ),
              ),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _canChat && !_loading && !_sending ? _send : null,
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    child: _sending
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: _characterGold,
                            ),
                          )
                        : Icon(
                            Icons.send_rounded,
                            size: 18,
                            color: _canChat && !_loading
                                ? _characterTextSoft
                                : _characterTextMuted,
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ],
    );
  }
}

class _NovelCharacterChatLine {
  const _NovelCharacterChatLine({
    required this.id,
    required this.role,
    required this.text,
    this.animate = false,
  });

  final int id;
  final String role;
  final String text;
  final bool animate;

  bool get isUser => role == 'user';
}

class _CharacterChatLineView extends StatelessWidget {
  const _CharacterChatLineView({
    required this.message,
    required this.desktopMode,
    this.dense = false,
  });

  final _NovelCharacterChatLine message;
  final bool desktopMode;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: desktopMode
              ? 460
              : dense
                  ? MediaQuery.sizeOf(context).width * .46
                  : MediaQuery.sizeOf(context).width * .84,
        ),
        padding: EdgeInsets.symmetric(
          horizontal: dense ? 8 : 12,
          vertical: dense ? 5 : 9,
        ),
        decoration: BoxDecoration(
          color: message.isUser
              ? _characterBlue.withOpacity(dense ? .24 : .30)
              : Colors.white.withOpacity(dense ? .060 : .075),
          borderRadius: BorderRadius.circular(dense ? 4 : 7),
          border: Border.all(
            color: message.isUser
                ? _characterBlueBright.withOpacity(.38)
                : Colors.white.withOpacity(.12),
          ),
        ),
        child: Text(
          message.text,
          style: TextStyle(
            color: _characterText,
            fontSize: dense ? 10.6 : (desktopMode ? 11.8 : 13),
            height: dense ? 1.34 : 1.5,
            fontFamily: 'MiSans',
            // 三种布局都取消聊天大遮罩，因此统一使用多方向阴影模拟细描边。
            shadows: _characterTextOutlineShadows,
          ),
        ),
      ),
    );
  }
}

class _CharacterOrbitPainter extends CustomPainter {
  const _CharacterOrbitPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * .43, size.height * .52);
    final orbitPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .75
      ..color = _characterGold.withOpacity(.12);
    final bluePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..color = _characterBlueBright.withOpacity(.12);
    final radius = math.min(size.width, size.height) * .47;
    canvas.drawCircle(center, radius, orbitPaint);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius * .78),
      -math.pi * .72,
      math.pi * 1.15,
      false,
      bluePaint,
    );
    canvas.drawLine(
      Offset(size.width * .08, size.height * .91),
      Offset(size.width * .67, size.height * .91),
      orbitPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _CharacterOrbitPainter oldDelegate) => false;
}

class _CharacterGameDetail extends StatelessWidget {
  const _CharacterGameDetail({
    required this.character,
    required this.characters,
    required this.owned,
    required this.recruitable,
    required this.fragments,
    required this.star,
    required this.summary,
    required this.compact,
    required this.onSelect,
    required this.onSummon,
  });

  final NovelCharacter character;
  final List<NovelCharacter> characters;
  final bool owned;
  final bool recruitable;
  final int fragments;
  final int star;
  final String summary;
  final bool compact;
  final ValueChanged<NovelCharacter> onSelect;
  final VoidCallback onSummon;

  @override
  Widget build(BuildContext context) {
    final fallbackAsset = character.gender.trim() == '男'
        ? 'assets/images/portrait_male.png'
        : 'assets/images/portrait_female.webp';
    final identity = stringValue(
      character.status['identity'] ?? character.persona['identity'],
    ).trim();
    String stat(List<String> keys) {
      for (final key in keys) {
        final value = character.status[key];
        if (value != null && value.toString().trim().isNotEmpty) {
          return value.toString();
        }
      }
      return '—';
    }

    final stats = <MapEntry<String, String>>[
      MapEntry<String, String>('生命', stat(<String>['hp', 'health', 'max_hp'])),
      MapEntry<String, String>('攻击', stat(<String>['attack', 'strength'])),
      MapEntry<String, String>('防御', stat(<String>['defense', 'tenacity'])),
      MapEntry<String, String>('敏捷', stat(<String>['agility', 'speed'])),
      MapEntry<String, String>('暴击', stat(<String>['critical', 'crit_rate'])),
      MapEntry<String, String>('好感', '${character.affection}'),
    ];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(-.18, .05),
          radius: 1.05,
          colors: <Color>[
            _characterBlue.withOpacity(.2),
            const Color(0x0010182B),
          ],
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          if (!compact)
            Positioned(
              left: 2,
              top: 26,
              bottom: 26,
              width: 54,
              child: _CharacterPortraitRail(
                characters: characters,
                selected: character,
                onSelect: onSelect,
              ),
            ),
          Positioned(
            left: compact ? -75 : 64,
            top: compact ? 22 : 2,
            bottom: -12,
            width: compact ? 300 : 540,
            child: NovelArtwork(
              url: CdnUtil.resize(
                character.portraitUrl.trim().isNotEmpty
                    ? character.portraitUrl
                    : character.avatarUrl,
                width: 1100,
              ),
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
          Positioned(
            left: compact ? 128 : 420,
            top: 30,
            bottom: 30,
            width: 1,
            child: ColoredBox(color: _characterGold.withOpacity(.11)),
          ),
          Positioned(
            right: compact ? 10 : 28,
            top: compact ? 15 : 28,
            bottom: compact ? 15 : 28,
            width: compact ? 190 : 370,
            child: Padding(
              padding: EdgeInsets.only(left: compact ? 12 : 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    character.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _characterText,
                      fontSize: compact ? 25 : 38,
                      height: 1,
                      fontWeight: FontWeight.w700,
                      letterSpacing: compact ? 1 : 2,
                    ),
                  ),
                  if (identity.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 8),
                    Text(
                      identity,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _characterTextMuted,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: .6,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  if (owned)
                    star == 0
                        ? const Text(
                            '0 星',
                            style: TextStyle(
                              color: _characterGold,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          )
                        : Row(
                            children: List<Widget>.generate(
                              star > 5 ? star - 5 : star,
                              (index) => Padding(
                                padding: const EdgeInsets.only(right: 3),
                                child: Icon(
                                  Icons.star_rounded,
                                  size: 13,
                                  color: star > 5
                                      ? _characterHighStar
                                      : _characterGold,
                                ),
                              ),
                            ),
                          )
                  else
                    Text(
                      '碎片  $fragments / 25',
                      style: const TextStyle(
                        color: _characterTextSoft,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                      ),
                    ),
                  Container(
                    height: 1,
                    margin: const EdgeInsets.symmetric(vertical: 13),
                    color: _characterGold.withOpacity(.42),
                  ),
                  const Text(
                    '属性',
                    style: TextStyle(
                      color: _characterText,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Wrap(
                    spacing: 5,
                    runSpacing: 5,
                    children: stats.map((entry) {
                      return Container(
                        width: compact ? 82 : 164,
                        height: 25,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        color: Colors.white.withOpacity(.045),
                        child: Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                entry.key,
                                style: const TextStyle(
                                  color: _characterTextMuted,
                                  fontSize: 8.5,
                                ),
                              ),
                            ),
                            Text(
                              entry.value,
                              style: const TextStyle(
                                color: _characterText,
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 13),
                  const Text(
                    '记忆',
                    style: TextStyle(
                      color: _characterText,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Text(
                        summary,
                        style: TextStyle(
                          color: _characterTextSoft.withOpacity(.9),
                          fontSize: compact ? 9.3 : 10.5,
                          height: 1.65,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                  ),
                  if (!owned && recruitable) ...<Widget>[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: fragments / 25,
                        minHeight: 3,
                        backgroundColor: Colors.white.withOpacity(.08),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          _characterBlueBright,
                        ),
                      ),
                    ),
                    const SizedBox(height: 9),
                    _CharacterDetailButton(
                      label: '前往鲜花结缘',
                      primary: true,
                      onTap: onSummon,
                    ),
                  ] else if (!owned)
                    const _CharacterLockedNotice(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CharacterDetailButton extends StatelessWidget {
  const _CharacterDetailButton({
    required this.label,
    required this.onTap,
    this.primary = false,
    this.enabled = true,
  });

  final String label;
  final VoidCallback onTap;
  final bool primary;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(2),
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: !enabled
                ? Colors.white.withOpacity(.035)
                : primary
                    ? _characterBlue.withOpacity(.78)
                    : Colors.white.withOpacity(.065),
            border: Border.all(
              color: primary && enabled
                  ? _characterGold.withOpacity(.55)
                  : Colors.white.withOpacity(.08),
            ),
            borderRadius: BorderRadius.circular(2),
          ),
          child: Center(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: enabled ? _characterText : _characterTextMuted,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CharacterLockedNotice extends StatelessWidget {
  const _CharacterLockedNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.04),
        borderRadius: BorderRadius.circular(2),
      ),
      child: const Text(
        '该角色暂不可结缘',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: _characterTextMuted,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

