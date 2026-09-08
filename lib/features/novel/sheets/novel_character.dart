part of '../novel_sheets.dart';

// ============================================================================

const Color _characterHighStar = Color(0xFFE75B62);
// 人物 / NPC资料 / 角色立绘页
// 页面入口 / 对外入口：
//   - showNovelCharactersSheet(...)
//   - NovelCharactersTab
//   - showNovelNpcProfileSheet(...)
//   - showNovelPortraitSheet(...)
// ============================================================================

Future<void> showNovelCharactersSheet(
  BuildContext context,
  NovelGameController controller,
) async {
  await _runNovelPageOnce('characters', () async {
    await _showNovelArchivePage<void>(
      context,
      child: _NovelCharacterHub(controller: controller),
    );
  });
}

class NovelCharactersTab extends StatelessWidget {
  const NovelCharactersTab({
    super.key,
    required this.controller,
    this.focusCharacterKey = '',
    this.focusRequestId = 0,
  });

  final NovelGameController controller;
  final String focusCharacterKey;
  final int focusRequestId;

  @override
  Widget build(BuildContext context) {
    return _CharactersPanel(
      controller: controller,
      embedded: true,
      focusCharacterKey: focusCharacterKey,
      focusRequestId: focusRequestId,
    );
  }
}

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
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(text),
          duration: const Duration(milliseconds: 1600),
        ),
      );
  }

  void _selectHero(NovelCharacter character) {
    setState(() {
      selectedCharacterKey = _keyOf(character);
      showingSummon = false;
    });
  }

  void _openSummon() {
    setState(() {
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
    final name = await _showCompanionSkillNamingDialog(
      context,
      skill,
      title: '${character.name}获得新技能',
    );
    if (name == null || !mounted) return;
    await widget.controller.renameNovelCompanionSkill(
      characterInstanceId: character.id,
      skillId: stringValue(skill['id']),
      name: name,
    );
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
        final subpageVisible = showingSummon || archiveVisible;
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
                showingSubpage: subpageVisible,
                subpageTitle: archiveVisible
                    ? '图鉴'
                    : showingSummon
                        ? '鲜花结缘'
                        : '',
                dense: landscape,
                onBack: subpageVisible
                    ? () => setState(() {
                          tab = 0;
                          showingSummon = false;
                        })
                    : null,
                onSummon: null,
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
                            onSummon: _openSummon,
                            onOpenArchive: () => setState(() => tab = 1),
                          )
                        : tab == 0
                            ? _CharacterEmptyTeamState(
                                loading: loading,
                                onSummon: _openSummon,
                                onOpenArchive: () => setState(() => tab = 1),
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
    required this.onOpenArchive,
  });

  final bool loading;
  final VoidCallback onSummon;
  final VoidCallback onOpenArchive;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        Center(
          child: Text(
            loading ? '正在整理队伍资料…' : '暂未拥有伙伴，可通过结缘获得角色',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _characterTextMuted,
              fontSize: 10.5,
              letterSpacing: .8,
            ),
          ),
        ),
        Positioned(
          left: 0,
          bottom: 8,
          child: Column(
            children: <Widget>[
              _CharacterCornerCard(
                icon: Icons.local_florist_outlined,
                assetPath: 'assets/images/character_bond.png',
                label: '结缘',
                onTap: onSummon,
              ),
              const SizedBox(height: 6),
              _CharacterCornerCard(
                icon: Icons.auto_stories_outlined,
                assetPath: 'assets/images/character_archive.png',
                label: '图鉴',
                onTap: onOpenArchive,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CharacterGameHeader extends StatelessWidget {
  const _CharacterGameHeader({
    required this.flowers,
    required this.showingSubpage,
    required this.subpageTitle,
    this.onBack,
    this.onSummon,
    this.onClose,
    this.dense = false,
  });

  final int flowers;
  final bool showingSubpage;
  final String subpageTitle;
  final VoidCallback? onBack;
  final VoidCallback? onSummon;
  final VoidCallback? onClose;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    // 核心逻辑：如果是抽卡页面，把标题完全置空，彻底做减法
    final String displayText;
    if (showingSubpage) {
      displayText = subpageTitle == '鲜花结缘' ? '' : subpageTitle;
    } else {
      displayText = '角色';
    }

    return SizedBox(
      height: dense ? 44 : 68,
      child: Row(
        children: <Widget>[
          if (onBack != null) ...<Widget>[
            IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: _characterTextSoft, size: 18),
              onPressed: onBack,
              padding: EdgeInsets.zero,
              splashRadius: 20,
            ),
            SizedBox(width: dense ? 3 : 8),
          ],
          Expanded(
            child: displayText.isEmpty 
                ? const SizedBox.shrink() 
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        displayText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _characterText,
                          fontSize: dense ? 16 : 20,
                          height: 1,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2.2,
                        ),
                      ),
                    ],
                  ),
          ),
          Container(
            height: dense ? 26 : 30,
            padding: EdgeInsets.only(left: dense ? 3 : 5, right: dense ? 8 : 11),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(.18),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Row(
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
                  ),
                ),
              ],
            ),
          ),
          if (onSummon != null) ...<Widget>[
            const SizedBox(width: 18),
            _CharacterHeaderAction(label: '结缘', onTap: onSummon!),
          ],
          if (onClose != null) ...<Widget>[
            const SizedBox(width: 18),
            _CharacterHeaderAction(label: '关闭', onTap: onClose!),
          ],
        ],
      ),
    );
  }
}

class _CharacterHeaderAction extends StatelessWidget {
  const _CharacterHeaderAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            label,
            style: const TextStyle(
              color: _characterTextSoft,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('立绘已更新')),
        );
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('立绘已更新')),
        );
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
    required this.onSummon,
    required this.onOpenArchive,
  });

  final NovelGameController controller;
  final NovelCharacter character;
  final List<NovelCharacter> characters;
  final int star;
  final int fragments;
  final ValueChanged<NovelCharacter> onSelect;
  final VoidCallback onSummon;
  final VoidCallback onOpenArchive;

  @override
  State<_CharacterHeroStage> createState() => _CharacterHeroStageState();
}

class _CharacterHeroStageState extends State<_CharacterHeroStage> {
  late int _localStar;
  bool _upgrading = false;
  bool _showUpgradeFlash = false;
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
                        '突破成功 · 全属性提升',
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
    ScaffoldMessenger.maybeOf(context)?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
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
    final name = await _showCompanionSkillNamingDialog(
      context,
      skill,
      title: customNamed ? '修改技能名称' : '学习到新技能',
      initialName: customNamed ? stringValue(skill['name']) : '',
      allowCancel: customNamed,
    );
    if (name == null || name.trim().isEmpty || !mounted) return;
    setState(() => _companionBusy = true);
    try {
      await widget.controller.renameNovelCompanionSkill(
        characterInstanceId: widget.character.id,
        skillId: stringValue(skill['id']),
        name: name,
      );
    } catch (error) {
      if (mounted) {
        _showCompanionMessage(
          error is NovelBackendException ? error.message : '技能命名失败：$error',
        );
      }
    } finally {
      if (mounted) setState(() => _companionBusy = false);
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

  Future<void> _openCompanionSkill(JsonMap skill) async {
    if (_companionBusy) return;
    final rename = await _showCompanionSkillDetails(context, skill);
    if (rename == true && mounted) {
      await _nameCompanionSkill(skill);
    }
  }

  Future<void> _upgradeStar() async {
    if (_upgrading || _localStar >= 10 || widget.fragments < 20) return;
    final id = widget.character.id.trim();
    if (id.isEmpty) return;
    setState(() => _upgrading = true);
    try {
      final payload = await widget.controller.upgradeNovelCharacter(id);
      if (!mounted) return;
      final nextStar = intValue(
        payload['star'],
        _localStar + 1,
      ).clamp(0, 10).toInt();
      setState(() {
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
      ScaffoldMessenger.maybeOf(context)?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
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
                  if (!keyboardVisible)
                    Positioned(
                      left: 0,
                      bottom: 8,
                      child: Column(
                        children: <Widget>[
                          _CharacterCornerCard(
                            icon: Icons.local_florist_outlined,
                            assetPath: 'assets/images/character_bond.png',
                            label: '结缘',
                            onTap: widget.onSummon,
                          ),
                          const SizedBox(height: 6),
                          _CharacterCornerCard(
                            icon: Icons.auto_stories_outlined,
                            assetPath: 'assets/images/character_archive.png',
                            label: '图鉴',
                            onTap: widget.onOpenArchive,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            );

          case _CharacterViewportMode.landscape:
            // 手机横屏：三栏舞台 + 底部聊天。与竖屏是独立 Widget 树。
            const globalNavInset = 64.0;
            final chatHeight = constraints.maxHeight < 390 ? 96.0 : 108.0;
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
                      bottom: chatHeight + 8,
                      width: 48,
                      child: portraitRail(),
                    ),
                  Positioned(
                    left: 48,
                    right: infoWidth + globalNavInset + 4,
                    top: 0,
                    bottom: chatHeight + 4,
                    child: artwork(const Alignment(-0.08, 0.12)),
                  ),
                  if (!keyboardVisible)
                    Positioned(
                      left: 54,
                      top: 4,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          _CharacterCornerCard(
                            compact: true,
                            icon: Icons.local_florist_outlined,
                            assetPath: 'assets/images/character_bond.png',
                            label: '结缘',
                            onTap: widget.onSummon,
                          ),
                          const SizedBox(width: 6),
                          _CharacterCornerCard(
                            compact: true,
                            icon: Icons.auto_stories_outlined,
                            assetPath: 'assets/images/character_archive.png',
                            label: '图鉴',
                            onTap: widget.onOpenArchive,
                          ),
                        ],
                      ),
                    ),
                  if (!keyboardVisible)
                    Positioned(
                      right: globalNavInset + 6,
                      top: 6,
                      bottom: chatHeight + 8,
                      width: infoWidth,
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: infoPanel(compact: true),
                      ),
                    ),
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    left: 8,
                    right: globalNavInset,
                    bottom: keyboardVisible ? keyboardInset + 4 : 4,
                    height: chatHeight,
                    child: _CharacterInlineChat(
                      controller: widget.controller,
                      character: widget.character,
                      dense: true,
                    ),
                  ),
                ],
              ),
            );

          case _CharacterViewportMode.portrait:
            // 手机竖屏：保持原本的竖向构图和交互尺寸。
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
                  if (!keyboardVisible)
                    Positioned(
                      left: 0,
                      bottom: chatHeight + 14,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          _CharacterCornerCard(
                            icon: Icons.local_florist_outlined,
                            assetPath: 'assets/images/character_bond.png',
                            label: '结缘',
                            onTap: widget.onSummon,
                          ),
                          const SizedBox(height: 6),
                          _CharacterCornerCard(
                            icon: Icons.auto_stories_outlined,
                            assetPath: 'assets/images/character_archive.png',
                            label: '图鉴',
                            onTap: widget.onOpenArchive,
                          ),
                        ],
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

class _CharacterCornerCard extends StatelessWidget {
  const _CharacterCornerCard({
    required this.icon,
    required this.label,
    required this.onTap,
    this.assetPath,
    this.compact = false,
  });

  final IconData icon;
  final String? assetPath;
  final String label;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    Widget actionIcon(double size) {
      final path = assetPath?.trim() ?? '';
      if (path.isEmpty) return Icon(icon, size: size, color: _characterGold);
      return Image.asset(
        path,
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) =>
            Icon(icon, size: size, color: _characterGold),
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          width: compact ? 68 : 46,
          height: compact ? 34 : 50,
          decoration: BoxDecoration(
            color: _characterInkSoft.withOpacity(.52),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: _characterGold.withOpacity(.26)),
          ),
          child: compact ? Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              actionIcon(15),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: _characterText,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ) : Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              actionIcon(18),
              const SizedBox(height: 4),
              Text(
                label,
                style: const TextStyle(
                  color: _characterText,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .8,
                ),
              ),
            ],
          ),
        ),
      ),
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
    return Container(
      padding: EdgeInsets.only(top: compact ? 7 : 11),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Colors.white.withOpacity(.09)),
        ),
      ),
      child: Row(
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
                onTap: canUpgrade ? onUpgrade : null,
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
                        ? '已满星'
                        : '升星  $fragments/20',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: canUpgrade
                          ? const Color(0xFF161A18)
                          : const Color(0xFF8B908D),
                      fontSize: compact ? 7.6 : 9.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

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

Future<String?> _showCompanionSkillNamingDialog(
  BuildContext context,
  JsonMap skill, {
  required String title,
  String initialName = '',
  bool allowCancel = false,
}) async {
  final editor = TextEditingController(text: initialName);
  final type = _companionSkillTypeOf(skill);
  final typeName = _companionSkillTypeName(type);
  final quality = intValue(skill['quality']).clamp(1, 10).toInt();
  final color = _companionSkillQualityColor(quality);
  final result = await showDialog<String>(
    context: context,
    barrierDismissible: allowCancel,
    builder: (dialogContext) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      child: Container(
        width: 340,
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
        decoration: BoxDecoration(
          color: const Color(0xFF111827),
          border: Border.all(color: color.withOpacity(.42)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              title,
              style: const TextStyle(
                color: _characterText,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: <Widget>[
                Container(
                  width: 42,
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: color.withOpacity(.10),
                    border: Border.all(color: color.withOpacity(.45)),
                  ),
                  child: Image.asset(
                    _companionSkillTypeAsset(type),
                    width: 24,
                    height: 24,
                    color: color,
                    semanticLabel: typeName,
                    errorBuilder: (_, __, ___) => Icon(
                      _companionSkillFallbackIcon(type),
                      size: 24,
                      color: color,
                      semanticLabel: typeName,
                    ),
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        typeName,
                        style: TextStyle(
                          color: color,
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      const Text(
                        '技能效果',
                        style: TextStyle(
                          color: _characterTextMuted,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(.035),
                border: Border.all(color: Colors.white.withOpacity(.08)),
              ),
              child: Text(
                _companionSkillEffectText(skill),
                style: const TextStyle(
                  color: _characterText,
                  fontSize: 11,
                  height: 1.55,
                ),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: editor,
              autofocus: true,
              maxLength: 7,
              decoration: const InputDecoration(
                hintText: '给技能命名',
                counterText: '',
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                ),
              ),
              onSubmitted: (value) {
                final clean = value.trim();
                if (clean.isNotEmpty) Navigator.of(dialogContext).pop(clean);
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                if (allowCancel) ...<Widget>[
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      style: TextButton.styleFrom(
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.zero,
                        ),
                      ),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: SizedBox(
                    height: 38,
                    child: FilledButton(
                      onPressed: () {
                        final clean = editor.text.trim();
                        if (clean.isNotEmpty) {
                          Navigator.of(dialogContext).pop(clean);
                        }
                      },
                      style: FilledButton.styleFrom(
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.zero,
                        ),
                      ),
                      child: const Text('确定'),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  editor.dispose();
  return result;
}

Future<bool?> _showCompanionSkillDetails(
  BuildContext context,
  JsonMap skill,
) {
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      child: Container(
        width: 330,
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
        decoration: BoxDecoration(
          color: const Color(0xFF111827),
          border: Border.all(color: Colors.white.withOpacity(.10)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    stringValue(skill['name'], '未命名'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _characterText,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  '${intValue(skill['quality']).clamp(1, 10)} 品',
                  style: const TextStyle(
                    color: _characterGoldSoft,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              '技能效果',
              style: TextStyle(
                color: _characterTextMuted,
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              _companionSkillEffectText(skill),
              style: const TextStyle(
                color: _characterText,
                fontSize: 11,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    child: const Text('关闭'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                    child: const Text('修改名称'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
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
      return Tooltip(
        message: '学习技能',
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
    return Tooltip(
      message: typeName,
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
                  stringValue(skill['name'], '未命名'),
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
  });

  final NovelGameController controller;
  final NovelCharacter character;
  final bool dense;

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
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            child: Stack(
              children: <Widget>[
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: <Color>[
                            Colors.transparent,
                            _characterInk.withOpacity(.18),
                            _characterInk.withOpacity(.76),
                          ],
                          stops: const <double>[.18, .56, 1],
                        ),
                      ),
                    ),
                  ),
                ),
                ShaderMask(
                  blendMode: BlendMode.dstIn,
                  shaderCallback: (bounds) => const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[
                      Colors.transparent,
                      Colors.white,
                      Colors.white,
                      Colors.transparent,
                    ],
                    stops: <double>[0, .09, .92, 1],
                  ).createShader(bounds),
                  child: ListView.separated(
                    controller: _scrollController,
                    padding: EdgeInsets.fromLTRB(6, widget.dense ? 6 : 14, 6, widget.dense ? 8 : 18),
                    itemCount: _messages.isEmpty ? 1 : _messages.length,
                    separatorBuilder: (_, __) => SizedBox(height: widget.dense ? 5 : 9),
                    itemBuilder: (context, index) {
                    if (_messages.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 22),
                        child: Text(
                          _loading
                              ? '正在读取对话…'
                              : !_canChat
                                  ? '主角不能与自己私聊'
                                  : '和${widget.character.name}说点什么吧',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: _characterTextMuted,
                            fontSize: 10.5,
                          ),
                        ),
                      );
                    }
                    final message = _messages[index];
                    final line = _CharacterChatLineView(
                      message: message,
                      desktopMode: desktopMode,
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
              ],
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
            color: Colors.white.withOpacity(0.06), 
            borderRadius: BorderRadius.circular(6), 
            border: Border.all(
              color: Colors.white.withOpacity(0.12),
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
  });

  final _NovelCharacterChatLine message;
  final bool desktopMode;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: desktopMode
              ? 460
              : MediaQuery.sizeOf(context).width * .84,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: message.isUser
              ? _characterBlue.withOpacity(.30)
              : Colors.white.withOpacity(.075),
          borderRadius: BorderRadius.circular(7),
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
            fontSize: desktopMode ? 11.8 : 13,
            height: 1.5,
            fontFamily: 'MiSans',
            shadows: const <Shadow>[
              Shadow(color: Colors.black45, blurRadius: 2),
            ],
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

class _CharactersPanel extends StatefulWidget {
  const _CharactersPanel({
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
  State<_CharactersPanel> createState() => _CharactersPanelState();
}

class _CharactersPanelState extends State<_CharactersPanel> {
  int filter = 0; 
  bool loading = true;
  String selectedCharacterKey = '';


  @override
  void initState() {
    super.initState();
    selectedCharacterKey = widget.focusCharacterKey.trim();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_refresh());
    });
  }

  @override
  void didUpdateWidget(covariant _CharactersPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final focusChanged =
        widget.focusRequestId != oldWidget.focusRequestId ||
        widget.focusCharacterKey != oldWidget.focusCharacterKey;
    if (!focusChanged) return;

    final key = widget.focusCharacterKey.trim();
    if (key.isEmpty) return;

    filter = 0;
    selectedCharacterKey = key;
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() => loading = true);
    await widget.controller.refreshCharacterStatus();
    if (mounted) setState(() => loading = false);
  }

  bool _isClose(NovelCharacter c) => c.affection >= 60;

  String _characterKey(NovelCharacter c) =>
      c.id.trim().isNotEmpty ? c.id.trim() : c.name.trim();

  List<NovelCharacter> _applyFilter(List<NovelCharacter> source) {
    if (filter == 1) {
      return source.where((c) => !c.isMain && _isClose(c)).toList();
    }
    if (filter == 2) {
      return source.where((c) => !c.isMain && !_isClose(c)).toList();
    }
    return source;
  }

  String _summaryOf(NovelCharacter c) {
    final status = c.status;
    final persona = c.persona;
    final values = <String>[
      stringValue(status['description']),
      stringValue(persona['description']),
      stringValue(status['background']),
      stringValue(persona['background']),
      stringValue(status['personality']),
      stringValue(persona['personality']),
    ].where((e) => e.trim().isNotEmpty).toList();
    return values.isNotEmpty ? values.first : '这个人物的故事还没有完全展开。';
  }

  String _identityOf(NovelCharacter c) {
    final identity = stringValue(c.status['identity'] ?? c.persona['identity']).trim();
    if (identity.isNotEmpty) return identity;
    final occupation = stringValue(c.status['occupation'] ?? c.persona['occupation']).trim();
    return occupation;
  }

  NovelCharacter _selected(List<NovelCharacter> source) {
    if (source.isEmpty) {
      throw StateError('No character available');
    }
    final currentKey = selectedCharacterKey.trim();
    if (currentKey.isNotEmpty) {
      for (final item in source) {
        if (_characterKey(item) == currentKey) return item;
      }
    }
    return source.first;
  }

  void _changeFilter(int value) {
    if (filter == value) return;
    setState(() {
      filter = value;
      selectedCharacterKey = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final scenarioCharacters =
            widget.controller.scenario?.characters.values.toList() ??
                <NovelCharacter>[];

        NovelCharacter? host = widget.controller.protagonist;
        if (host == null) {
          for (final item in scenarioCharacters) {
            if (item.isMain) {
              host = item;
              break;
            }
          }
        }

        final npcs = scenarioCharacters
            .where((character) => !character.isMain)
            .toList();
        npcs.sort((a, b) {
          if (_isClose(a) != _isClose(b)) return _isClose(a) ? -1 : 1;
          return b.affection.compareTo(a.affection);
        });

        final characters = <NovelCharacter>[
          if (host != null) host,
          ...npcs,
        ];

        if (characters.isEmpty) {
          return _CharacterArchiveBackground(
            controller: widget.controller,
            embedded: widget.embedded,
            child: _ArchiveEmptyState(
              text: loading ? '正在整理人物档案…' : '还没有人物资料',
            ),
          );
        }

        final closeCount = npcs.where(_isClose).length;
        final normalCount = npcs.length - closeCount;
        final filtered = _applyFilter(characters);

        Widget filterBar(_CharacterViewportMode mode) => _CharacterFilterBar(
              filter: filter,
              total: characters.length,
              closeCount: closeCount,
              normalCount: normalCount,
              dense: mode == _CharacterViewportMode.landscape,
              onChanged: _changeFilter,
            );

        Widget header(_CharacterViewportMode mode) => _CharacterArchiveHeader(
              dense: mode == _CharacterViewportMode.landscape,
              onClose: widget.embedded
                  ? null
                  : () => Navigator.of(context).pop(),
            );

        Widget shell(
          _CharacterViewportMode mode,
          Widget content,
        ) {
          switch (mode) {
            case _CharacterViewportMode.desktop:
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1280),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: content,
                  ),
                ),
              );
            case _CharacterViewportMode.landscape:
              return Padding(
                padding: const EdgeInsets.fromLTRB(8, 2, 8, 2),
                child: content,
              );
            case _CharacterViewportMode.portrait:
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 3, 10, 3),
                    child: content,
                  ),
                ),
              );
          }
        }

        if (filtered.isEmpty) {
          return _CharacterArchiveBackground(
            controller: widget.controller,
            embedded: widget.embedded,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final mode = _characterViewportMode(
                  constraints,
                  widget.controller.desktopMode,
                );
                return shell(
                  mode,
                  Column(
                    children: <Widget>[
                      header(mode),
                      const Expanded(
                        child: _ArchiveEmptyState(text: '当前筛选下暂无角色'),
                      ),
                      filterBar(mode),
                      if (mode != _CharacterViewportMode.landscape)
                        const SizedBox(height: 106),
                    ],
                  ),
                );
              },
            ),
          );
        }

        final selected = _selected(filtered);

        return _CharacterArchiveBackground(
          controller: widget.controller,
          embedded: widget.embedded,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final mode = _characterViewportMode(
                constraints,
                widget.controller.desktopMode,
              );

              final stage = _CharacterShowcaseStage(
                controller: widget.controller,
                character: selected,
                summary: _summaryOf(selected),
                identity: _identityOf(selected),
                mode: mode,
              );

              void selectCharacter(NovelCharacter character) {
                setState(() => selectedCharacterKey = _characterKey(character));
              }

              switch (mode) {
                case _CharacterViewportMode.landscape:
                  // 横屏使用左侧人物轨道 + 中间舞台 + 右侧人物信息。
                  // 与竖屏底部缩略图结构彻底分离。
                  return shell(
                    mode,
                    Column(
                      children: <Widget>[
                        header(mode),
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              _CharacterThumbStrip(
                                vertical: true,
                                dense: true,
                                characters: filtered,
                                selectedKey: _characterKey(selected),
                                onSelected: selectCharacter,
                              ),
                              const SizedBox(width: 6),
                              Expanded(child: stage),
                            ],
                          ),
                        ),
                        filterBar(mode),
                      ],
                    ),
                  );

                case _CharacterViewportMode.portrait:
                  return shell(
                    mode,
                    Column(
                      children: <Widget>[
                        header(mode),
                        Expanded(child: stage),
                        filterBar(mode),
                        _CharacterThumbStrip(
                          characters: filtered,
                          selectedKey: _characterKey(selected),
                          onSelected: selectCharacter,
                        ),
                      ],
                    ),
                  );

                case _CharacterViewportMode.desktop:
                  return shell(
                    mode,
                    Column(
                      children: <Widget>[
                        header(mode),
                        Expanded(child: stage),
                        filterBar(mode),
                        _CharacterThumbStrip(
                          characters: filtered,
                          selectedKey: _characterKey(selected),
                          onSelected: selectCharacter,
                        ),
                      ],
                    ),
                  );
              }
            },
          ),
        );
      },
    );
  }
}

class _NovelPrimaryTabSafeContent extends StatelessWidget {
  const _NovelPrimaryTabSafeContent({
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: EdgeInsets.zero,
        child: child,
      ),
    );
  }
}

class _CharacterArchiveBackground extends StatelessWidget {
  const _CharacterArchiveBackground({
    required this.controller,
    required this.child,
    this.embedded = false,
  });

  final NovelGameController controller;
  final Widget child;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final content = embedded
        ? _NovelPrimaryTabSafeContent(child: child)
        : SafeArea(child: child);

    return ColoredBox(
      color: _archiveBackground,
      child: content,
    );
  }
}

class _CharacterArchiveHeader extends StatelessWidget {
  const _CharacterArchiveHeader({
    this.onClose,
    this.dense = false,
  });

  final VoidCallback? onClose;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        dense ? 10 : 20,
        dense ? 3 : 13,
        dense ? 8 : 12,
        dense ? 2 : 6,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '人物',
                  style: TextStyle(
                    color: const Color(0xFF272824),
                    fontSize: dense ? 18 : 23,
                    height: 1,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
          if (onClose != null) ...<Widget>[
            _CharacterHeaderButton(
              tooltip: '关闭',
              icon: Icons.close_rounded,
              onTap: onClose,
            ),
          ],
        ],
      ),
    );
  }
}

class _CharacterHeaderButton extends StatelessWidget {
  const _CharacterHeaderButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: SizedBox(
            width: 42,
            height: 42,
            child: Icon(
              icon,
              size: 22,
              color: onTap == null
                  ? _archiveMutedSoft
                  : _archiveTextSoft,
            ),
          ),
        ),
      ),
    );
  }
}

class _CharacterFilterBar extends StatelessWidget {
  const _CharacterFilterBar({
    required this.filter,
    required this.total,
    required this.closeCount,
    required this.normalCount,
    required this.onChanged,
    this.dense = false,
  });

  final int filter;
  final int total;
  final int closeCount;
  final int normalCount;
  final ValueChanged<int> onChanged;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        dense ? 8 : 18,
        dense ? 1 : 4,
        dense ? 8 : 18,
        dense ? 1 : 3,
      ),
      child: Row(
        children: <Widget>[
          _CharacterFilterText(
            label: '全部',
            count: total,
            selected: filter == 0,
            onTap: () => onChanged(0),
          ),
          SizedBox(width: dense ? 10 : 18),
          _CharacterFilterText(
            label: '亲密',
            count: closeCount,
            selected: filter == 1,
            onTap: () => onChanged(1),
          ),
          SizedBox(width: dense ? 10 : 18),
          _CharacterFilterText(
            label: '普通',
            count: normalCount,
            selected: filter == 2,
            onTap: () => onChanged(2),
          ),
          const Spacer(),
          Container(
            width: 54,
            height: .7,
            color: _archiveLine,
          ),
        ],
      ),
    );
  }
}

class _CharacterFilterText extends StatelessWidget {
  const _CharacterFilterText({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              label,
              style: TextStyle(
                color: selected
                    ? _archiveText
                    : _archiveMuted,
                fontSize: 11.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '$count',
              style: TextStyle(
                color: selected
                    ? _archiveMuted
                    : _archiveMutedSoft,
                fontSize: 9.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CharacterShowcaseStage extends StatefulWidget {
  const _CharacterShowcaseStage({
    required this.controller,
    required this.character,
    required this.summary,
    required this.identity,
    _CharacterViewportMode? mode,
    bool? compact,
  }) : mode = mode ??
            (compact == false
                ? _CharacterViewportMode.desktop
                : _CharacterViewportMode.portrait);

  final NovelGameController controller;
  final NovelCharacter character;
  final String summary;
  final String identity;
  final _CharacterViewportMode mode;

  @override
  State<_CharacterShowcaseStage> createState() =>
      _CharacterShowcaseStageState();
}

class _CharacterShowcaseStageState extends State<_CharacterShowcaseStage> {
  String _previewPortraitUrl = '';

  String _characterKey(NovelCharacter c) =>
      c.id.trim().isNotEmpty ? c.id.trim() : c.name.trim();

  String get _portraitUrl {
    final preview = _previewPortraitUrl.trim();
    if (preview.isNotEmpty) return preview;
    return widget.character.portraitUrl.trim();
  }

  @override
  void didUpdateWidget(covariant _CharacterShowcaseStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_characterKey(oldWidget.character) != _characterKey(widget.character)) {
      _previewPortraitUrl = '';
    }
  }

  String get _relationLabel {
    if (widget.character.isMain) return '主角';
    return widget.character.affectionLabel.trim().isNotEmpty
        ? widget.character.affectionLabel.trim()
        : (widget.character.affection >= 60 ? '亲密' : '普通');
  }

  @override
  Widget build(BuildContext context) {
    final fallbackAsset = widget.character.gender.trim() == '男'
        ? 'assets/images/portrait_male.png'
        : 'assets/images/portrait_female.webp';

    return LayoutBuilder(
      builder: (context, constraints) {
        final h = constraints.maxHeight;
        final desktop = widget.mode == _CharacterViewportMode.desktop;
        final landscape = widget.mode == _CharacterViewportMode.landscape;
        final compact = !desktop;

        final portraitWidth = desktop
            ? math.min(constraints.maxWidth * .55, 620.0)
            : landscape
                ? math.min(constraints.maxWidth * .54, 470.0)
                : math.min(constraints.maxWidth * .78, 430.0);
        final infoWidth = desktop
            ? math.min(constraints.maxWidth * .36, 390.0)
            : landscape
                ? math.min(constraints.maxWidth * .36, 270.0)
                : math.min(constraints.maxWidth * .43, 210.0);

        final portraitLeft = desktop
            ? 28.0
            : landscape
                ? 2.0
                : -portraitWidth * .14;
        final portraitBottom = desktop
            ? -h * .055
            : landscape
                ? -h * .08
                : -h * .025;
        final portraitHeight = desktop
            ? h * 1.02
            : landscape
                ? h * 1.10
                : h * .96;

        return Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: <Widget>[
            Positioned(
              left: portraitLeft,
              bottom: portraitBottom,
              child: IgnorePointer(
                child: SizedBox(
                  width: portraitWidth,
                  height: portraitHeight,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 260),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    child: NovelArtwork(
                      key: ValueKey<String>(
                        'showcase-${_portraitUrl}-${widget.character.name}',
                      ),
                      url: CdnUtil.resize(_portraitUrl, width: 800),
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
            Positioned(
              right: desktop ? 38 : (landscape ? 6 : 7),
              top: desktop ? 30 : (landscape ? 3 : 13),
              bottom: desktop ? 22 : (landscape ? 3 : 8),
              width: infoWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding: EdgeInsets.only(
                        bottom: landscape ? 4 : (compact ? 8 : 12),
                      ),
                      child: _CharacterShowcaseInfo(
                        character: widget.character,
                        summary: widget.summary,
                        identity: widget.identity,
                        relationLabel: _relationLabel,
                        compact: compact,
                      ),
                    ),
                  ),
                  SizedBox(height: landscape ? 4 : (compact ? 8 : 12)),
                  _CharacterQuickPortraitEditor(
                    controller: widget.controller,
                    character: widget.character,
                    compact: compact,
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

class _CharacterShowcaseInfo extends StatelessWidget {
  const _CharacterShowcaseInfo({
    required this.character,
    required this.summary,
    required this.identity,
    required this.relationLabel,
    required this.compact,
  });

  final NovelCharacter character;
  final String summary;
  final String identity;
  final String relationLabel;
  final bool compact;

  String _valueText(dynamic value) {
    if (value == null) return '';
    if (value is String || value is num || value is bool) {
      return stringValue(value).trim();
    }
    if (value is List) {
      final values = value
          .map(_valueText)
          .where((item) => item.isNotEmpty)
          .toSet()
          .toList();
      return values.join('、');
    }
    if (value is Map) {
      final map = value.map((key, item) => MapEntry(key.toString(), item));
      final name = stringValue(
        map['name'] ?? map['title'] ?? map['event'] ?? map['skill'],
      ).trim();
      final mastery = stringValue(map['mastery'] ?? map['level']).trim();
      final detail = stringValue(
        map['description'] ?? map['detail'] ?? map['content'] ?? map['summary'],
      ).trim();
      final parts = <String>[
        if (name.isNotEmpty) name,
        if (mastery.isNotEmpty && mastery != name) mastery,
        if (detail.isNotEmpty && detail != name) detail,
      ];
      if (parts.isNotEmpty) return parts.join(' · ');
      return map.values
          .map(_valueText)
          .where((item) => item.isNotEmpty)
          .toSet()
          .join('、');
    }
    return value.toString().trim();
  }

  String _firstValue(List<dynamic> values) {
    for (final value in values) {
      final text = _valueText(value);
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  Widget _detailSection(String label, String value) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: const TextStyle(
              color: _archiveMuted,
              fontSize: 9.2,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: _archiveTextSoft.withOpacity(.92),
              fontSize: compact ? 10.5 : 11.5,
              height: 1.55,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nameSize = compact ? 30.0 : 37.0;
    final status = character.status;
    final persona = character.persona;
    final level = stringValue(status['level']).trim();
    final condition = stringValue(status['current_condition']).trim();
    final combatPower = stringValue(status['combat_power']).trim();
    final mainStatus = <String>[
      if (condition.isNotEmpty) condition,
      if (level.isNotEmpty) level,
      if (combatPower.isNotEmpty) '战力 $combatPower',
    ];
    final description = _firstValue(<dynamic>[
      status['description'],
      persona['description'],
    ]);
    final personality = _firstValue(<dynamic>[
      status['personality'],
      persona['personality'],
    ]);
    final background = _firstValue(<dynamic>[
      status['background'],
      persona['background'],
    ]);
    final appearance = _firstValue(<dynamic>[
      status['appearance'],
      persona['appearance'],
      persona['portrait_prompt'],
    ]);
    final skills = _valueText(status['skills']);
    final abilities = _valueText(status['abilities']);
    final injuries = _valueText(status['injuries']);
    final limits = _valueText(status['known_limits']);
    final milestones = _valueText(character.milestones);
    final aliases = character.aliases.join('、');
    final hasFullDetails = <String>[
      description,
      personality,
      background,
      appearance,
      skills,
      abilities,
      injuries,
      limits,
      milestones,
      aliases,
    ].any((value) => value.isNotEmpty);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          character.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: _archiveText,
            fontSize: nameSize,
            height: .95,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          identity.isEmpty
              ? (character.isMain ? '主角' : '故事人物')
              : identity,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFF616B64),
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            letterSpacing: .4,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          width: 64,
          height: 1,
          color: _archiveLine,
        ),
        if (character.isMain && mainStatus.isNotEmpty) ...<Widget>[
          const SizedBox(height: 10),
          Text(
            mainStatus.join('  ·  '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _archiveText,
              fontSize: compact ? 10.4 : 11.2,
              height: 1.45,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Icon(
              character.isMain
                  ? Icons.stars_rounded
                  : Icons.favorite_border_rounded,
              size: 14,
              color: _archiveMuted,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                character.isMain
                    ? relationLabel
                    : '$relationLabel  ·  ${character.affection}',
                style: const TextStyle(
                  color: Color(0xFF4E5851),
                  fontSize: 10.7,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        if (!hasFullDetails) _detailSection('人物资料', summary),
        _detailSection('人物简介', description),
        _detailSection('性格', personality),
        _detailSection('背景', background),
        _detailSection('外貌', appearance),
        _detailSection('技能', skills),
        _detailSection('能力', abilities),
        _detailSection('伤势', injuries),
        _detailSection('限制', limits),
        _detailSection('里程碑', milestones),
        _detailSection('别名', aliases),
      ],
    );
  }
}

class _CharacterQuickPortraitEditor extends StatefulWidget {
  const _CharacterQuickPortraitEditor({
    required this.controller,
    required this.character,
    required this.compact,
    required this.onPortraitChanged,
  });

  final NovelGameController controller;
  final NovelCharacter character;
  final bool compact;
  final ValueChanged<String> onPortraitChanged;

  @override
  State<_CharacterQuickPortraitEditor> createState() =>
      _CharacterQuickPortraitEditorState();
}

class _CharacterQuickPortraitEditorState
    extends State<_CharacterQuickPortraitEditor> {
  late final TextEditingController _promptController;
  late final FocusNode _promptFocusNode;
  bool _generating = false;
  bool _uploading = false;
  String _errorText = '';
  int _requestToken = 0;

  String _characterKey(NovelCharacter c) =>
      c.id.trim().isNotEmpty ? c.id.trim() : c.name.trim();

  @override
  void initState() {
    super.initState();
    _promptController = TextEditingController();
    _promptFocusNode = FocusNode();
  }

  @override
  void didUpdateWidget(covariant _CharacterQuickPortraitEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_characterKey(oldWidget.character) != _characterKey(widget.character)) {
      _requestToken++;
      _promptController.clear();
      _errorText = '';
      _generating = false;
      _uploading = false;
    }
  }

  @override
  void dispose() {
    _promptFocusNode.dispose();
    _promptController.dispose();
    super.dispose();
  }

  Future<bool> _showGeneratedPortraitPreview({
    required NovelCharacter character,
    required String portraitUrl,
  }) async {
    if (!mounted) return false;

    final fallbackAsset = character.gender.trim() == '男'
        ? 'assets/images/portrait_male.png'
        : 'assets/images/portrait_female.webp';

    final decision = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierLabel: '立绘预览',
      barrierColor: Colors.black.withOpacity(.82),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (dialogContext, _, __) {
        final media = MediaQuery.of(dialogContext);
        final compact = !widget.controller.desktopMode;
        final dialogWidth = math.min(
          media.size.width - 40,
          compact ? 330.0 : 420.0,
        );
        final dialogHeight = math.min(
          media.size.height * (compact ? .60 : .72),
          compact ? 520.0 : 620.0,
        );

        return PopScope(
          canPop: false,
          child: Material(
            color: Colors.transparent,
            child: SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: SizedBox(
                    width: dialogWidth,
                    height: dialogHeight,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: _archiveSurface,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: <BoxShadow>[
                          BoxShadow(
                            color: Colors.black.withOpacity(.20),
                            blurRadius: 32,
                            offset: const Offset(0, 16),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 14, 14, 13),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            const Padding(
                              padding: EdgeInsets.fromLTRB(2, 0, 2, 11),
                              child: Text(
                                '立绘预览',
                                style: TextStyle(
                                  color: _archiveText,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: ColoredBox(
                                  color: _archiveSurfaceSoft,
                                  child: NovelArtwork(
                                    url: portraitUrl,
                                    assetCandidates: <String>[
                    fallbackAsset,
                    'assets/images/portrait_female.webp',
                    'assets/images/portrait_male.png',
                  ],
                                    fit: BoxFit.contain,
                                    alignment: Alignment.center,
                                    fallbackText: '',
                                    fallbackIcon: Icons.person_outline_rounded,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 13),
                            SizedBox(
                              height: 42,
                              child: Row(
                                children: <Widget>[
                                  Expanded(
                                    child: Material(
                                      color: _archiveSurfaceSoft,
                                      borderRadius: BorderRadius.circular(11),
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(11),
                                        onTap: () =>
                                            Navigator.of(dialogContext).pop(false),
                                        child: const Center(
                                          child: Text(
                                            '放弃',
                                            style: TextStyle(
                                              color: _archiveTextSoft,
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Material(
                                      color: _archiveThemeGreen,
                                      borderRadius: BorderRadius.circular(11),
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(11),
                                        onTap: () =>
                                            Navigator.of(dialogContext).pop(true),
                                        child: const Center(
                                          child: Text(
                                            '保存',
                                            style: TextStyle(
                                              color: NovelPalette.accentDark,
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
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

    return decision == true;
  }

  Future<void> _generatePortrait() async {
    if (_generating || _uploading) return;

    final target = widget.character;
    final targetKey = _characterKey(target);
    final requestToken = ++_requestToken;
    final prompt = _promptController.text.trim();

    setState(() {
      _generating = true;
      _errorText = '';
    });

    try {
      final result = await widget.controller.generatePortrait(
        character: target,
        prompt: prompt,
        style: 'anime',
      );

      if (!mounted ||
          requestToken != _requestToken ||
          _characterKey(widget.character) != targetKey) {
        return;
      }

      final shouldSave = await _showGeneratedPortraitPreview(
        character: target,
        portraitUrl: result.portraitUrl,
      );
      if (!mounted ||
          !shouldSave ||
          requestToken != _requestToken ||
          _characterKey(widget.character) != targetKey) {
        return;
      }

      await widget.controller.updateCharacterVisuals(
        character: target,
        portraitUrl: result.portraitUrl,
        avatarUrl: result.avatarUrl,
      );
      widget.controller.clearMessages();

      if (!mounted) return;
      final stillCurrent = requestToken == _requestToken &&
          _characterKey(widget.character) == targetKey;
      if (stillCurrent) {
        widget.onPortraitChanged(result.portraitUrl);
      }

      await widget.controller.refreshCharacterStatus();
    } catch (error) {
      if (!mounted || requestToken != _requestToken) return;
      setState(() {
        _errorText = error is NovelBackendException
            ? error.message
            : '生成立绘失败：$error';
      });
    } finally {
      if (mounted && requestToken == _requestToken) {
        setState(() => _generating = false);
      }
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
      if (!mounted) return;
      setState(() => _errorText = '图片请控制在 12MB 以内');
      return;
    }

    final target = widget.character;
    final targetKey = _characterKey(target);
    final requestToken = ++_requestToken;

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

      final avatarUrl = target.avatarUrl.trim().isEmpty
          ? portraitUrl
          : target.avatarUrl;

      await widget.controller.updateCharacterVisuals(
        character: target,
        portraitUrl: portraitUrl,
        avatarUrl: avatarUrl,
      );
      widget.controller.clearMessages();

      if (!mounted) return;
      final stillCurrent = requestToken == _requestToken &&
          _characterKey(widget.character) == targetKey;
      if (stillCurrent) {
        widget.onPortraitChanged(portraitUrl);
      }

      await widget.controller.refreshCharacterStatus();
    } catch (error) {
      if (!mounted || requestToken != _requestToken) return;
      setState(() {
        _errorText = error is NovelBackendException
            ? error.message
            : '上传立绘失败：$error';
      });
    } finally {
      if (mounted && requestToken == _requestToken) {
        setState(() => _uploading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
        const Text(
          '更换立绘',
          style: TextStyle(
            color: Color(0xFF414A44),
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            letterSpacing: .3,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: _archiveSurface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _archiveLine,
              width: 1,
            ),
          ),
          constraints: BoxConstraints(
            minHeight: widget.compact ? 104 : 112,
          ),
          padding: const EdgeInsets.fromLTRB(11, 11, 11, 10),
          child: TextField(
            controller: _promptController,
            focusNode: _promptFocusNode,
            enabled: !_generating,
            minLines: 4,
            maxLines: widget.compact ? 4 : 5,
            scrollPadding: EdgeInsets.zero,
            cursorColor: NovelPalette.accent,
            style: TextStyle(
              color: _archiveText,
              fontSize: widget.compact ? 10.6 : 11.2,
              height: 1.45,
            ),
            decoration: const InputDecoration(
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
              hintText: '可留空直接生成；也可写发型、服装、气质等调整…',
              hintStyle: TextStyle(
                color: Color(0x88727C75),
                fontSize: 10.2,
                height: 1.4,
              ),
            ),
          ),
        ),
        if (_errorText.isNotEmpty) ...<Widget>[
          const SizedBox(height: 5),
          Text(
            _errorText,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFFD98A83),
              fontSize: 9.5,
              height: 1.35,
            ),
          ),
        ],
        const SizedBox(height: 7),
        SizedBox(
          width: double.infinity,
          height: 40,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: (_generating || _uploading) ? null : _generatePortrait,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _generating
                      ? _archiveSurfaceSoft
                      : _archiveThemeGreen,
                  border: Border.all(
                    color: _generating
                        ? _archiveLine
                        : _archiveThemeGreen,
                    width: .9,
                  ),
                ),
                child: _generating
                    ? const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          SizedBox.square(
                            dimension: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: NovelPalette.accent,
                            ),
                          ),
                          SizedBox(width: 7),
                          Text(
                            '生成中…',
                            style: TextStyle(
                              color: Color(0xFF4E514C),
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      )
                    : const Text(
                        '生成立绘',
                        style: TextStyle(
                          color: NovelPalette.accentDark,
                          fontSize: 11.4,
                          fontWeight: FontWeight.w800,
                          letterSpacing: .6,
                        ),
                      ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 7),
        SizedBox(
          width: double.infinity,
          height: 38,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: (_generating || _uploading)
                  ? null
                  : _pickAndApplyLocalPortrait,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _uploading
                      ? _archiveSurfaceSoft
                      : Colors.transparent,
                  border: Border.all(
                    color: _uploading
                        ? _archiveLine
                        : _archiveAccent.withOpacity(.55),
                    width: .9,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (_uploading) ...<Widget>[
                      const SizedBox.square(
                        dimension: 11,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.4,
                          color: NovelPalette.accentDeep,
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      _uploading ? '上传中…' : '本地上传',
                      style: const TextStyle(
                        color: _archiveAccent,
                        fontSize: 10.4,
                        fontWeight: FontWeight.w700,
                        letterSpacing: .35,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        ],
      ),
    );
  }
}

class _CharacterThumbStrip extends StatelessWidget {
  const _CharacterThumbStrip({
    required this.characters,
    required this.selectedKey,
    required this.onSelected,
    this.vertical = false,
    this.dense = false,
  });

  final List<NovelCharacter> characters;
  final String selectedKey;
  final ValueChanged<NovelCharacter> onSelected;
  final bool vertical;
  final bool dense;

  String _keyOf(NovelCharacter c) => c.id.trim().isNotEmpty ? c.id.trim() : c.name.trim();

  @override
  Widget build(BuildContext context) {
    Widget buildThumb(NovelCharacter character) {
      final selected = _keyOf(character) == selectedKey;
      final fallbackAsset = character.gender.trim() == '女'
          ? 'assets/images/portrait_female.webp'
          : 'assets/images/portrait_male.png';
      final image = character.avatarUrl.trim();
      final cardWidth = vertical ? (dense ? 48.0 : 56.0) : 66.0;
      final imageHeight = vertical ? (dense ? 55.0 : 66.0) : 82.0;

      return GestureDetector(
        onTap: () => onSelected(character),
        child: SizedBox(
          width: cardWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: cardWidth,
                height: imageHeight,
                decoration: BoxDecoration(
                  color: _archiveSurfaceSoft,
                  borderRadius: BorderRadius.zero,
                  border: Border.all(
                    color: selected ? _archiveThemeGreen : _archiveLine,
                    width: selected ? 1.35 : 1,
                  ),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    NovelArtwork(
                      url: CdnUtil.resize(image, width: 150),
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
                    if (selected)
                      const Positioned(
                        right: 3,
                        top: 3,
                        child: Icon(
                          Icons.check_circle_rounded,
                          size: 13,
                          color: _archiveThemeGreen,
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(height: vertical ? 3 : 6),
              SizedBox(
                width: cardWidth,
                child: Text(
                  character.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: selected ? _archiveText : _archiveTextSoft,
                    fontSize: vertical ? 8.2 : 9.2,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
                    letterSpacing: .1,
                    height: 1.05,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (vertical) {
      return SizedBox(
        width: dense ? 56 : 64,
        child: ListView.separated(
          scrollDirection: Axis.vertical,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(2, 2, 4, 4),
          itemCount: characters.length,
          separatorBuilder: (_, __) => SizedBox(height: dense ? 5 : 7),
          itemBuilder: (context, index) => buildThumb(characters[index]),
        ),
      );
    }

    return SizedBox(
      height: 106,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 3, 18, 2),
        itemCount: characters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) => buildThumb(characters[index]),
      ),
    );
  }
}

Future<void> showNovelNpcProfileSheet(
  BuildContext context,
  NovelGameController controller,
  NovelCharacter character,
) async {
  await _runNovelPageOnce('character-profile', () async {
    final key = character.id.trim().isNotEmpty ? character.id.trim() : character.name.trim();
    await _showNovelArchivePage<void>(
      context,
      child: _CharactersPanel(
        controller: controller,
        focusCharacterKey: key,
        focusRequestId: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  });
}

class _InlineCharacterVisualEditor extends StatefulWidget {
  const _InlineCharacterVisualEditor({
    required this.controller,
    required this.character,
  });

  final NovelGameController controller;
  final NovelCharacter character;

  @override
  State<_InlineCharacterVisualEditor> createState() =>
      _InlineCharacterVisualEditorState();
}

class _InlineCharacterVisualEditorState
    extends State<_InlineCharacterVisualEditor> {
  late final TextEditingController _promptController;

  late String _imageStyle;
  late String _portraitUrl;
  late String _avatarUrl;

  late String _savedPortraitUrl;
  late String _savedAvatarUrl;

  Uint8List? _localBytes;
  String _localFilename = '';
  String _localContentType = '';

  bool _generating = false;
  bool _saving = false;
  String _errorText = '';

  bool get _hasPortrait =>
      _localBytes != null || _portraitUrl.trim().isNotEmpty;

  bool get _hasPendingChanges =>
      _localBytes != null ||
      _portraitUrl != _savedPortraitUrl ||
      _avatarUrl != _savedAvatarUrl;

  @override
  void initState() {
    super.initState();

    _promptController = TextEditingController();

    _imageStyle = 'anime';

    _portraitUrl = widget.character.portraitUrl;
    _avatarUrl = widget.character.avatarUrl;

    _savedPortraitUrl = _portraitUrl;
    _savedAvatarUrl = _avatarUrl;
  }

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  Future<void> _pickLocalImage() async {
    if (_generating || _saving) return;

    final result = await FilePicker.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: true,
    );

    final file = result?.files.single;
    if (file == null || file.bytes == null) return;

    if (file.size > 12 * 1024 * 1024) {
      setState(() {
        _errorText = '图片请控制在 12MB 以内';
      });
      return;
    }

    setState(() {
      _localBytes = file.bytes;
      _localFilename = file.name;
      _localContentType = _imageContentType(file.name);
      _errorText = '';
    });
  }

  Future<void> _generatePortrait() async {
    if (_generating || _saving) return;

    final prompt = _promptController.text.trim();

    setState(() {
      _generating = true;
      _errorText = '';
    });

    try {
      final result = await widget.controller.generatePortrait(
        character: widget.character,
        prompt: prompt,
        style: 'anime',
      );

      if (!mounted) return;

      setState(() {
        _portraitUrl = result.portraitUrl;
        _avatarUrl = result.avatarUrl;
        _localBytes = null;
        _localFilename = '';
        _localContentType = '';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorText = error is NovelBackendException
            ? error.message
            : '生成立绘失败：$error';
      });
    } finally {
      if (mounted) {
        setState(() => _generating = false);
      }
    }
  }

  Future<void> _savePortrait() async {
    if (_generating || _saving || !_hasPendingChanges) return;

    if (!_hasPortrait) {
      setState(() {
        _errorText = '请先上传或生成一张立绘';
      });
      return;
    }

    setState(() {
      _saving = true;
      _errorText = '';
    });

    try {
      var finalPortrait = _portraitUrl;
      var finalAvatar = _avatarUrl;

      if (_localBytes != null) {
        finalPortrait = await widget.controller.uploadCharacterImage(
          bytes: _localBytes!,
          filename:
              _localFilename.isEmpty ? 'portrait.jpg' : _localFilename,
          contentType: _localContentType.isEmpty
              ? 'image/jpeg'
              : _localContentType,
        );

        if (finalAvatar.trim().isEmpty ||
            finalAvatar == widget.character.avatarUrl) {
          finalAvatar = finalPortrait;
        }
      }

      await widget.controller.updateCharacterVisuals(
        character: widget.character,
        portraitUrl: finalPortrait,
        avatarUrl: finalAvatar,
      );

      widget.controller.clearMessages();

      if (!mounted) return;

      setState(() {
        _portraitUrl = finalPortrait;
        _avatarUrl = finalAvatar;

        _savedPortraitUrl = finalPortrait;
        _savedAvatarUrl = finalAvatar;

        _localBytes = null;
        _localFilename = '';
        _localContentType = '';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorText = error is NovelBackendException
            ? error.message
            : '保存失败：$error';
      });
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Widget _buildPreview() {
    if (_localBytes != null) {
      return Image.memory(
        _localBytes!,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
      );
    }

    if (_portraitUrl.trim().isNotEmpty) {
      return NovelArtwork(
        url: CdnUtil.resize(_portraitUrl, width: 600),
        fit: BoxFit.contain,
        fallbackText: '',
        fallbackIcon: Icons.person_outline_rounded,
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: (_generating || _saving) ? null : _pickLocalImage,
        child: Center(
          child: Text(
            '暂无立绘，点击这里上传',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _archiveMuted,
              fontSize: 11.5,
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const Color primaryGreen = NovelPalette.accent;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: [
            Container(
              width: 3,
              height: 14,
              decoration: BoxDecoration(
                color: primaryGreen,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              '形象设定',
              style: TextStyle(
                color: _archiveText,
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: AspectRatio(
              aspectRatio: 3 / 4,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: (_generating || _saving) ? null : _pickLocalImage,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        _buildPreview(),
                        if (_generating)
                          ColoredBox(
                            color: Colors.black.withOpacity(.42),
                            child: const Center(
                              child: SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: primaryGreen,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (_hasPortrait) ...<Widget>[
          const SizedBox(height: 7),
          Center(
            child: Text(
              '点击立绘可上传',
              style: TextStyle(
                color: _archiveMutedSoft,
                fontSize: 10.2,
              ),
            ),
          ),
        ],

        const SizedBox(height: 22),
        
        Text(
          '额外形象要求（可选）',
          style: TextStyle(
            color: _archiveMuted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: Colors.white, 
            borderRadius: BorderRadius.circular(8),
          ),
          child: TextField(
            controller: _promptController,
            enabled: !_generating && !_saving,
            minLines: 3,
            maxLines: 5,
            cursorColor: primaryGreen,
            style: const TextStyle(
              color: _archiveText,
              fontSize: 12,
              height: 1.5,
            ),
            decoration: InputDecoration(
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
              hintText: '留空按角色完整设定生成；例如：裙摆更轻盈、气质更清冷、仙气更强……',
              hintStyle: TextStyle(
                color: _archiveMutedSoft,
                fontSize: 11,
              ),
            ),
          ),
        ),

        if (_errorText.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            _errorText,
            style: const TextStyle(
              color: Color(0xFFE07A78),
              fontSize: 10.5,
              height: 1.4,
            ),
          ),
        ],

        const SizedBox(height: 16),

        SizedBox(
          width: double.infinity,
          height: 42,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: (_generating || _saving) ? null : _generatePortrait,
              borderRadius: BorderRadius.circular(8),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: (_generating || _saving)
                      ? _archiveMutedSoft.withOpacity(0.3)
                      : primaryGreen,
                ),
                child: _generating
                    ? const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          SizedBox.square(
                            dimension: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.6,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(width: 8),
                          Text(
                            '生成中…',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11.2,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      )
                    : const Text(
                        '生成立绘',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.0,
                        ),
                      ),
              ),
            ),
          ),
        ),

        if (_hasPendingChanges) ...<Widget>[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 42,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: _archiveText,
                foregroundColor: Colors.white,
                disabledBackgroundColor: _archiveMutedSoft.withOpacity(0.3),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: (_generating || _saving) ? null : _savePortrait,
              child: _saving
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.8,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      '保存立绘',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.0,
                      ),
                    ),
            ),
          ),
        ],
      ],
    );
  }
}

class _VisualStyleChoice extends StatelessWidget {
  const _VisualStyleChoice({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null && !selected;
    return Material(
      color: selected
          ? _archiveSurfaceSoft
          : disabled
              ? _archiveBackground
              : _archiveSurface,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 8,
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected
                  ? _archiveText
                  : disabled
                      ? _archiveMutedSoft
                      : _archiveMuted,
              fontSize: 11.5,
              fontWeight:
                  selected ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileSoftAction extends StatelessWidget {
  const _ProfileSoftAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.loading = false,
    this.primary = false,
    this.greenPrimary = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool loading;
  final bool primary;
  final bool greenPrimary;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;

    return Material(
      color: greenPrimary
          ? (enabled ? _archiveThemeGreen : _archiveSurfaceSoft)
          : primary
              ? (enabled ? _archiveText : _archiveSurfaceSoft)
              : (enabled ? _archiveSurfaceSoft : _archiveBackground),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          height: 40,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              if (loading)
                SizedBox.square(
                  dimension: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.7,
                    color: greenPrimary
                        ? NovelPalette.accentDark
                        : (primary
                            ? _archiveSurface
                            : _archiveMuted),
                  ),
                )
              else
                Icon(
                  icon,
                  size: 13,
                  color: greenPrimary
                      ? NovelPalette.accentDark
                      : (primary
                          ? _archiveSurface
                          : _archiveMuted),
                ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: greenPrimary
                        ? (enabled
                            ? NovelPalette.accentDark
                            : _archiveMutedSoft)
                        : (primary
                            ? _archiveSurface
                            : (enabled
                                ? _archiveText
                                : _archiveMutedSoft)),
                    fontSize: 11.2,
                    fontWeight: FontWeight.w700,
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

Future<void> showNovelPortraitSheet(
  BuildContext context,
  NovelGameController controller, {
  NovelCharacter? character,
}) async {
  final target =
      character ?? controller.currentSpeakerCharacter ?? controller.protagonist;

  if (target == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('当前没有可编辑的角色')),
    );
    return;
  }

  final promptController = TextEditingController();

  var imageStyle = 'anime';

  var portraitUrl = target.portraitUrl;
  var avatarUrl = target.avatarUrl;

  var savedPortraitUrl = portraitUrl;
  var savedAvatarUrl = avatarUrl;

  Uint8List? localBytes;
  String localFilename = '';
  String localContentType = '';

  var generating = false;
  var saving = false;
  var errorText = '';

  bool hasPortrait() =>
      localBytes != null || portraitUrl.trim().isNotEmpty;

  bool hasPendingChanges() =>
      localBytes != null ||
      portraitUrl != savedPortraitUrl ||
      avatarUrl != savedAvatarUrl;

  try {
    await _showNovelArchivePage<void>(
      context,
      child: StatefulBuilder(
        builder: (pageContext, setState) {
          Future<void> pickLocalImage() async {
            if (generating || saving) return;

            final result = await FilePicker.pickFiles(
              type: FileType.image,
              allowMultiple: false,
              withData: true,
            );

            final file = result?.files.single;
            if (file == null || file.bytes == null) return;
            if (!pageContext.mounted) return;

            if (file.size > 12 * 1024 * 1024) {
              setState(() => errorText = '图片请控制在 12MB 以内');
              return;
            }

            setState(() {
              localBytes = file.bytes;
              localFilename = file.name;
              localContentType = _imageContentType(file.name);
              errorText = '';
            });
          }

          Future<void> generateImage() async {
            if (generating || saving) return;

            final prompt = promptController.text.trim();

            setState(() {
              generating = true;
              errorText = '';
            });

            try {
              final result = await controller.generatePortrait(
                character: target,
                prompt: prompt,
                style: 'anime',
              );

              if (!pageContext.mounted) return;

              setState(() {
                portraitUrl = result.portraitUrl;
                avatarUrl = result.avatarUrl;
                localBytes = null;
                localFilename = '';
                localContentType = '';
              });
            } catch (error) {
              if (!pageContext.mounted) return;
              setState(() {
                errorText = error is NovelBackendException
                    ? error.message
                    : '生成立绘失败：$error';
              });
            } finally {
              if (pageContext.mounted) {
                setState(() => generating = false);
              }
            }
          }

          Future<void> saveImage() async {
            if (generating || saving || !hasPendingChanges()) return;

            final pageNavigator = Navigator.of(pageContext);

            if (!hasPortrait()) {
              setState(() => errorText = '请先上传或生成一张立绘');
              return;
            }

            setState(() {
              saving = true;
              errorText = '';
            });

            try {
              var finalPortrait = portraitUrl;
              var finalAvatar = avatarUrl;

              if (localBytes != null) {
                finalPortrait = await controller.uploadCharacterImage(
                  bytes: localBytes!,
                  filename:
                      localFilename.isEmpty ? 'portrait.jpg' : localFilename,
                  contentType: localContentType.isEmpty
                      ? 'image/jpeg'
                      : localContentType,
                );

                if (finalAvatar.trim().isEmpty ||
                    finalAvatar == target.avatarUrl) {
                  finalAvatar = finalPortrait;
                }
              }

              await controller.updateCharacterVisuals(
                character: target,
                portraitUrl: finalPortrait,
                avatarUrl: finalAvatar,
              );

              controller.clearMessages();

              if (!pageContext.mounted) return;

              setState(() {
                savedPortraitUrl = finalPortrait;
                savedAvatarUrl = finalAvatar;
                portraitUrl = finalPortrait;
                avatarUrl = finalAvatar;
                localBytes = null;
                localFilename = '';
                localContentType = '';
                saving = false;
              });

              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!pageNavigator.mounted) return;
                if (pageNavigator.canPop()) pageNavigator.pop();
              });
            } catch (error) {
              if (!pageContext.mounted) return;
              setState(() {
                saving = false;
                errorText = error is NovelBackendException
                    ? error.message
                    : '保存失败：$error';
              });
            }
          }

          Widget buildPreview() {
            if (localBytes != null) {
              return Image.memory(
                localBytes!,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
              );
            }

            if (portraitUrl.trim().isNotEmpty) {
              return NovelArtwork(
                url: portraitUrl,
                fit: BoxFit.contain,
                fallbackText: '',
                fallbackIcon: Icons.person_outline_rounded,
              );
            }

            return Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: (generating || saving) ? null : pickLocalImage,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        Icons.add_photo_alternate_outlined,
                        size: 26,
                        color: _archiveMuted,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '点击上传',
                        style: TextStyle(
                          color: _archiveText,
                          fontSize: 11.6,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '或在下方生成新的立绘',
                        style: TextStyle(
                          color: _archiveMutedSoft,
                          fontSize: 10.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          return _ArchivePageScaffold(
            title: '生成立绘',
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = !controller.desktopMode;
                final previewHeight = compact ? 240.0 : 340.0;

                return ListView(
                  padding: EdgeInsets.fromLTRB(
                    compact ? 16 : 28,
                    8,
                    compact ? 16 : 28,
                    40,
                  ),
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: SizedBox(
                            width: 34,
                            height: 34,
                            child: NovelArtwork(
                              url: target.avatarUrl.isNotEmpty
                                  ? target.avatarUrl
                                  : target.portraitUrl,
                              fit: BoxFit.cover,
                              fallbackText: '',
                              fallbackIcon: Icons.person_outline_rounded,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            target.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _archiveText,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Text(
                          target.isMain ? '主角' : '角色',
                          style: TextStyle(
                            color: _archiveMutedSoft,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 14),

                    Container(
                      height: previewHeight,
                      alignment: Alignment.bottomCenter,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: _archiveSurfaceSoft,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Stack(
                        fit: StackFit.expand,
                        children: <Widget>[
                          buildPreview(),

                          if (generating)
                            ColoredBox(
                              color: Colors.black.withOpacity(.38),
                              child: Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    const SizedBox.square(
                                      dimension: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 1.7,
                                        color: _archiveText,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      '正在生成…',
                                      style: TextStyle(
                                        color:
                                            NovelPalette.text.withOpacity(.86),
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                          if (hasPortrait() && !generating)
                            Positioned(
                              top: 10,
                              right: 10,
                              child: Material(
                                color: Colors.black.withOpacity(.28),
                                shape: const CircleBorder(),
                                child: InkWell(
                                  onTap: saving ? null : pickLocalImage,
                                  customBorder: const CircleBorder(),
                                  child: SizedBox(
                                    width: 34,
                                    height: 34,
                                    child: Icon(
                                      Icons.photo_camera_back_outlined,
                                      size: 16,
                                      color:
                                          NovelPalette.text.withOpacity(.88),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 18),

                    Row(
                      children: <Widget>[
                        _VisualStyleChoice(
                          label: '动漫',
                          selected: true,
                          onTap: (generating || saving)
                              ? null
                              : () => setState(() => imageStyle = 'anime'),
                        ),
                        const SizedBox(width: 8),
                        const _VisualStyleChoice(
                          label: '3D（已锁定）',
                          selected: false,
                          onTap: null,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '立绘会自动读取完整角色资料；下方只需填写本次想额外调整的方向。',
                      style: TextStyle(
                        color: _archiveMutedSoft,
                        fontSize: 10.2,
                      ),
                    ),

                    const SizedBox(height: 16),

      

                    Text(
                      '额外形象要求（可选）',
                      style: TextStyle(
                        color: _archiveMuted,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),

                    Container(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      decoration: BoxDecoration(
                        color: _archiveSurfaceSoft,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: TextField(
                        controller: promptController,
                        enabled: !generating && !saving,
                        minLines: 3,
                        maxLines: 5,
                        cursorColor: NovelPalette.accent,
                        style: const TextStyle(
                          color: _archiveText,
                          fontSize: 12.3,
                          height: 1.55,
                        ),
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          isDense: true,
                          hintText:
                              '留空按角色完整设定生成；例如：服装更轻盈、气质更清冷、减少华丽首饰…',
                          hintStyle: TextStyle(
                            color: _archiveMutedSoft,
                            fontSize: 11.1,
                          ),
                        ),
                      ),
                    ),

                    if (errorText.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 9),
                      Text(
                        errorText,
                        style: const TextStyle(
                          color: NovelPalette.danger,
                          fontSize: 11,
                          height: 1.45,
                        ),
                      ),
                    ],

                    const SizedBox(height: 16),

                    Row(
                      children: <Widget>[
                        Expanded(
                          child: _ProfileSoftAction(
                            icon: Icons.auto_awesome_rounded,
                            label: generating ? '生成中…' : '生成立绘',
                            loading: generating,
                            greenPrimary: true,
                            onTap: (generating || saving)
                                ? null
                                : generateImage,
                          ),
                        ),
                        if (hasPendingChanges()) ...<Widget>[
                          const SizedBox(width: 8),
                          Expanded(
                            child: _ProfileSoftAction(
                              icon: Icons.check_rounded,
                              label: saving ? '保存中…' : '保存',
                              loading: saving,
                              primary: true,
                              onTap: (generating || saving)
                                  ? null
                                  : saveImage,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  } finally {
    await Future<void>.delayed(const Duration(milliseconds: 320));
    promptController.dispose();
  }
}

String _imageContentType(String filename) {
  final lower = filename.toLowerCase();
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.gif')) return 'image/gif';
  if (lower.endsWith('.heic') || lower.endsWith('.heif')) return 'image/heic';
  return 'image/jpeg';
}

class _CharacterCard extends StatelessWidget {
  const _CharacterCard({required this.character, this.onTap});
  final NovelCharacter character;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final relationship = character.affectionLabel.trim().isNotEmpty
        ? character.affectionLabel.trim()
        : (character.isMain ? '主角' : '故事角色');
    final progress = (character.affection.clamp(0, 100) / 100).toDouble();
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.fromLTRB(8, 9, 8, 9),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(.016),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withOpacity(.065)),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: character.isMain
                        ? NovelPalette.accent.withOpacity(.28)
                        : Colors.white.withOpacity(.07),
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: NovelArtwork(
                 url: CdnUtil.resize(
                      character.avatarUrl.isNotEmpty
                          ? character.avatarUrl
                          : character.portraitUrl,
                      width: 150),
                  fit: BoxFit.cover,
                  fallbackText: '',
                  fallbackIcon: Icons.person_outline_rounded,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            character.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: NovelPalette.text,
                              fontSize: 13.8,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Text(
                          relationship,
                          style: TextStyle(
                            color: character.isMain
                                ? NovelPalette.accent
                                : NovelPalette.muted,
                            fontSize: 9.8,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(99),
                            child: SizedBox(
                              height: 3,
                              child: LinearProgressIndicator(
                                value: progress,
                                backgroundColor: Colors.white.withOpacity(.06),
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  NovelPalette.accent.withOpacity(.82),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 9),
                        Text(
                          character.isMain ? '—' : '${character.affection}',
                          style: TextStyle(
                            color: character.isMain
                                ? NovelPalette.muted
                                : NovelPalette.accent,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    if (character.status.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 7),
                      Text(
                        stringValue(
                          character.status['latest_dynamic'] ??
                              character.status['status_text'] ??
                              character.status['mood'],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: NovelPalette.muted,
                          fontSize: 9.8,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (onTap != null) ...<Widget>[
                const SizedBox(width: 7),
                Icon(
                  Icons.chevron_right_rounded,
                  color: NovelPalette.muted.withOpacity(.48),
                  size: 17,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
