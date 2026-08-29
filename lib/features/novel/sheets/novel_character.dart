part of '../novel_sheets.dart';

// ============================================================================
// 人物 / 主角资料 / 角色立绘页
// 页面入口 / 对外入口：
//   - showNovelHostProfileSheet(...)
//   - showNovelCharactersSheet(...)
//   - NovelCharactersTab
//   - showNovelNpcProfileSheet(...)
//   - showNovelPortraitSheet(...)
// 其余以下划线 `_` 开头的类型/方法均为该页面内部实现或共享私有实现。
// ============================================================================

Future<void> showNovelHostProfileSheet(
  BuildContext context,
  NovelGameController controller,
) async {
  await _runNovelPageOnce('host-profile', () async {
    final host = controller.protagonist;
    final hostKey = host != null && host.id.trim().isNotEmpty
        ? host.id.trim()
        : (host?.name.trim() ?? controller.protagonistName);

    // 保持原来的大立绘人物总览，只聚焦主角；状态直接补在这套页面里。
    await _showNovelArchivePage<void>(
      context,
      child: _CharactersPanel(
        controller: controller,
        focusCharacterKey: hostKey,
        focusRequestId: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  });
}

Future<void> showNovelCharactersSheet(
  BuildContext context,
  NovelGameController controller,
) async {
  await _runNovelPageOnce('characters', () async {
    // 兼容旧调用：独立打开时仍保留原来的全屏归档页。
    await _showNovelArchivePage<void>(
      context,
      child: _CharactersPanel(controller: controller),
    );
  });
}

/// 主游戏底部 Tab 使用的人物页。
/// embedded=true 时不再显示“关闭”按钮，由右侧一级导航负责页面切换。
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
  int filter = 0; // 0 全部 / 1 亲密 / 2 普通
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

    // 从剧情对话框跳入人物页时，先回到“全部”，再精确定位当前说话角色。
    // 不依赖当前亲密/普通筛选，避免目标角色被筛掉后看起来像“没有定位”。
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
    // 主角固定放在“全部”的第一个；亲密/普通只筛 NPC，避免把主角硬塞进关系分类。
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

        // 人物页第一位永远是主角，后面才是 NPC。
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

        if (filtered.isEmpty) {
          return _CharacterArchiveBackground(
            controller: widget.controller,
            embedded: widget.embedded,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 620;
                final horizontalInset = compact ? 10.0 : 28.0;
                final verticalInset = compact ? 3.0 : 8.0;

                // 空筛选状态仍然复用正常角色页的同一套宽度、边距和底部占位。
                // 这样“全部 / 亲密 / 普通”的坐标不会因为有没有头像而变化。
                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 920),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        horizontalInset,
                        verticalInset,
                        horizontalInset,
                        verticalInset,
                      ),
                      child: Column(
                        children: <Widget>[
                          _CharacterArchiveHeader(
                            onClose: widget.embedded
                                ? null
                                : () => Navigator.of(context).pop(),
                          ),
                          const Expanded(
                            child: _ArchiveEmptyState(text: '当前筛选下暂无角色'),
                          ),
                          _CharacterFilterBar(
                            filter: filter,
                            total: characters.length,
                            closeCount: closeCount,
                            normalCount: normalCount,
                            onChanged: _changeFilter,
                          ),
                          // 与正常状态的 _CharacterThumbStrip 高度完全一致。
                          const SizedBox(height: 106),
                        ],
                      ),
                    ),
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
              final compact = constraints.maxWidth < 620;
              final horizontalInset = compact ? 10.0 : 28.0;
              final verticalInset = compact ? 3.0 : 8.0;

              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 920),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      horizontalInset,
                      verticalInset,
                      horizontalInset,
                      verticalInset,
                    ),
                    child: Column(
                      children: <Widget>[
                        _CharacterArchiveHeader(
                          onClose: widget.embedded
                              ? null
                              : () => Navigator.of(context).pop(),
                        ),
                        Expanded(
                          child: _CharacterShowcaseStage(
                            controller: widget.controller,
                            character: selected,
                            summary: _summaryOf(selected),
                            identity: _identityOf(selected),
                            compact: compact,
                          ),
                        ),
                        // “全部 / 亲密 / 普通”只控制下面的人物列表，
                        // 放到生成立绘区域之后、头像栏之前，手机阅读顺序更自然。
                        _CharacterFilterBar(
                          filter: filter,
                          total: characters.length,
                          closeCount: closeCount,
                          normalCount: normalCount,
                          onChanged: _changeFilter,
                        ),
                        _CharacterThumbStrip(
                          characters: filtered,
                          selectedKey: _characterKey(selected),
                          onSelected: (character) {
                            setState(() => selectedCharacterKey =
                                _characterKey(character));
                          },
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

class _NovelPrimaryTabSafeContent extends StatelessWidget {
  const _NovelPrimaryTabSafeContent({
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width <= 600;
    final safeBottom = MediaQuery.viewPaddingOf(context).bottom;

    return SafeArea(
      bottom: false,
      child: Padding(
        // 一级导航已回到右侧 HUD：取消整块底部预留，
        // 只在右侧留一条窄安全区，避免列表/资料文字被导航覆盖。
        padding: EdgeInsets.only(
          right: compact ? 54.0 : 62.0,
          bottom: safeBottom,
        ),
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
  });

  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 13, 12, 6),
      child: Row(
        children: <Widget>[
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '人物',
                  style: TextStyle(
                    color: Color(0xFF272824),
                    fontSize: 23,
                    height: 1,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
                SizedBox(height: 5),
                Text(
                  'CHARACTERS',
                  style: TextStyle(
                    color: Color(0x995F605B),
                    fontSize: 8.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2.1,
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
  });

  final int filter;
  final int total;
  final int closeCount;
  final int normalCount;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 3),
      child: Row(
        children: <Widget>[
          _CharacterFilterText(
            label: '全部',
            count: total,
            selected: filter == 0,
            onTap: () => onChanged(0),
          ),
          const SizedBox(width: 18),
          _CharacterFilterText(
            label: '亲密',
            count: closeCount,
            selected: filter == 1,
            onTap: () => onChanged(1),
          ),
          const SizedBox(width: 18),
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
    required this.compact,
  });

  final NovelGameController controller;
  final NovelCharacter character;
  final String summary;
  final String identity;
  final bool compact;

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

    // 上方人物舞台只允许使用“立绘”。
    // 头像是底部人物切换栏的素材，不能拿来顶替大立绘。
    return widget.character.portraitUrl.trim();
  }

  @override
  void didUpdateWidget(covariant _CharacterShowcaseStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_characterKey(oldWidget.character) != _characterKey(widget.character)) {
      _previewPortraitUrl = '';
    }
  }

  void _showPortrait(String value) {
    if (!mounted) return;
    setState(() => _previewPortraitUrl = value.trim());
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
        // 手机端不再按桌面“两栏”思维缩小人物。
        // 立绘承担主视觉，资料层缩窄并浮在右侧，让人物真正成为页面主体。
        final portraitWidth = widget.compact
            ? math.min(constraints.maxWidth * .76, 430.0)
            : math.min(constraints.maxWidth * .54, 490.0);
        final infoWidth = widget.compact
            ? math.min(constraints.maxWidth * .43, 210.0)
            : math.min(constraints.maxWidth * .41, 340.0);

        return Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: <Widget>[
            Positioned(
              left: widget.compact ? -portraitWidth * .14 : 18,
              bottom: widget.compact ? -h * .025 : -h * .05,
              child: IgnorePointer(
                child: SizedBox(
                  width: portraitWidth,
                  height: h * (widget.compact ? .96 : 1.02),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 260),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    child: NovelArtwork(
                      key: ValueKey<String>(
                        'showcase-${_portraitUrl}-${widget.character.name}',
                      ),
                      url: CdnUtil.resize(_portraitUrl, width: 800),
                      assetCandidates: <String>[fallbackAsset],
                      fit: BoxFit.contain,
                      alignment: Alignment.bottomCenter,
                      fallbackText: widget.character.name,
                      fallbackIcon: Icons.person_outline_rounded,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              right: widget.compact ? 7 : 26,
              top: widget.compact ? 13 : 34,
              bottom: widget.compact ? 8 : 20,
              width: infoWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  // 状态、能力、背景等人物资料独立滚动。
                  // 更换立绘编辑器固定在本栏底部，不再跟着资料一起卷走。
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding: EdgeInsets.only(
                        bottom: widget.compact ? 10 : 16,
                      ),
                      child: _CharacterShowcaseInfo(
                        character: widget.character,
                        summary: widget.summary,
                        identity: widget.identity,
                        relationLabel: _relationLabel,
                        compact: widget.compact,
                      ),
                    ),
                  ),
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.only(
                      top: widget.compact ? 8 : 12,
                    ),
                    decoration: const BoxDecoration(
                      border: Border(
                        top: BorderSide(color: _archiveLine, width: 1),
                      ),
                    ),
                    child: _CharacterQuickPortraitEditor(
                      controller: widget.controller,
                      character: widget.character,
                      compact: widget.compact,
                      onPortraitChanged: _showPortrait,
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
        final compact = media.size.width < 600;
        final dialogWidth = math.min(
          media.size.width - 40,
          compact ? 330.0 : 350.0,
        );
        final dialogHeight = math.min(
          media.size.height * (compact ? .60 : .66),
          520.0,
        );

        return PopScope(
          // 生成结果必须明确选择“放弃”或“保存”，避免返回键产生不清晰状态。
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
                                    assetCandidates: <String>[fallbackAsset],
                                    fit: BoxFit.contain,
                                    // 小型确认窗口以完整观察构图为主，立绘居中显示。
                                    // 角色主页面的大立绘仍保持 bottomCenter，不受影响。
                                    alignment: Alignment.center,
                                    fallbackText: character.name,
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

      // AI 返回的图片先只放进预览窗，不更新角色资料。
      // 用户明确点击“保存”后才真正绑定立绘和头像。
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

      // 生成结果里同时包含头像；刷新后底部缩略栏立即切换到新头像。
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

      // 本地上传只替换立绘；角色尚无头像时才用同一张图兜底头像。
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
    // 游戏页本身已经关闭 resizeToAvoidBottomInset。
    // 这里不再根据键盘高度手动平移编辑区：手机聚焦输入框时保持原坐标，
    // 避免“更换立绘”区域向上撞进角色资料；键盘只覆盖屏幕底部内容。
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
  });

  final List<NovelCharacter> characters;
  final String selectedKey;
  final ValueChanged<NovelCharacter> onSelected;

  String _keyOf(NovelCharacter c) => c.id.trim().isNotEmpty ? c.id.trim() : c.name.trim();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 106,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        // 名字已经移到头像卡片外部，因此把原来过大的上下内边距收紧。
        // 保持整个头像栏仍为 106 高，不改变“全部 / 亲密 / 普通”的固定位置。
        padding: const EdgeInsets.fromLTRB(14, 3, 18, 2),
        itemCount: characters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final character = characters[index];
          final selected = _keyOf(character) == selectedKey;
          // 底部角色栏只显示头像；头像为空时，使用默认男女立绘兜底。
          // 上方舞台则始终只读取 character.portraitUrl。
          final fallbackAsset = character.gender.trim() == '女'
              ? 'assets/images/portrait_female.webp'
              : 'assets/images/portrait_male.png';
          final image = character.avatarUrl.trim();
          return GestureDetector(
            onTap: () => onSelected(character),
            child: SizedBox(
              width: 66,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 66,
                    height: 82,
                    decoration: BoxDecoration(
                      color: _archiveSurfaceSoft,
                      borderRadius: BorderRadius.zero,
                      border: Border.all(
                        color: selected
                            ? _archiveThemeGreen
                            : _archiveLine,
                        width: selected ? 1.35 : 1,
                      ),
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        NovelArtwork(
                          url: CdnUtil.resize(image, width: 150), //
                          assetCandidates: <String>[fallbackAsset],
                          fit: BoxFit.cover,
                          alignment: Alignment.topCenter,
                          fallbackText: character.name,
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
                  const SizedBox(height: 6),
                  SizedBox(
                    width: 66,
                    child: Text(
                      character.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: selected ? _archiveText : _archiveTextSoft,
                        fontSize: 9.2,
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
        },
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
    // 同样直接打开“角色总览页”，并聚焦到该 NPC
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

  // 用于判断“是否真的改过”。
  // 没发生变化时，页面完全不显示保存按钮。
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

    // 角色完整资料由 Controller 自动整理成 Character Brief。
    // 这里仅填写“本次额外形象调整”，留空也可以直接生成。
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

      // AI 生成只先进入预览状态。
      // 只有用户确认保存后，才调用 updateCharacterVisuals。
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

        // 当前没有独立头像时，上传的立绘同时作为头像兜底。
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

      // 立绘保存属于原地编辑，不需要再额外弹“XXX 立绘已更新”状态提示。
      widget.controller.clearMessages();

      if (!mounted) return;

      setState(() {
        _portraitUrl = finalPortrait;
        _avatarUrl = finalAvatar;

        // 保存成功后更新“基准值”，保存按钮自动消失。
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
        fallbackText: widget.character.name,
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

        // 依靠 AspectRatio 保证比例，用 constraints 约束平板上的极限宽度，防止溢出
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
                      color: Colors.white, // 纯白底
                      borderRadius: BorderRadius.circular(12),
                      // 去掉了所有外框
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
            color: Colors.white, // 融入在极浅灰卡片上的纯白输入框
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

  // 角色完整资料由 Controller 自动整理成 Character Brief。
  // 这里仅填写“本次额外形象调整”，留空也可以直接生成。
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

            // 在异步保存开始前拿到稳定的 NavigatorState。
            // 后面不再通过可能正在 deactivate 的 BuildContext 重新查 Navigator。
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

              // 快捷更换立绘成功后不需要顶部再显示“XXX 立绘已更新”。
              controller.clearMessages();

              if (!pageContext.mounted) return;

              // 先把当前页面的本地状态完整收尾，再退出路由。
              // 避免 Navigator.pop() 已经开始 deactivate 页面后，finally 又 setState，
              // 从而触发 Flutter InheritedElement 的 _dependents.isEmpty 断言。
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

              // updateCharacterVisuals 会通知剧情页重建。
              // 等本帧完成再退页；直接使用异步开始前捕获的 NavigatorState，
              // 避免在页面 deactivate 过程中重新从 context 查找 InheritedWidget。
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
                fallbackText: target.name,
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
                final compact = constraints.maxWidth < 620;
                final previewHeight = compact ? 240.0 : 280.0;

                return ListView(
                  padding: EdgeInsets.fromLTRB(
                    compact ? 16 : 28,
                    8,
                    compact ? 16 : 28,
                    40,
                  ),
                  children: <Widget>[
                    // 角色信息只保留最必要的一行，避免页面像表单。
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
                              fallbackText: target.name,
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

                    // 预览是页面主体，不再用厚重卡片或多余边框。
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

                    // 画风使用轻量选择，不再用大块 SegmentedButton。
                    // 仅保留动漫和3D选项，去掉占空间的文字
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
    // Navigator.push() 的 Future 在 pop 后可能先完成，而路由的 reverse transition
    // 仍在使用 TextField。立即 dispose 会造成概率性“controller disposed”红屏。
    // 当前归档页 reverseTransitionDuration 为 220ms，留出额外余量后再释放。
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
                      width: 150), // <--- 列表小头像
                  fit: BoxFit.cover,
                  fallbackText: character.name,
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
