part of '../novel_widgets.dart';

/// One scene actor that can either be a stable talk target or an ambient bark anchor.
///
/// Important/named characters are shown by [NovelTalkTargetBar]. Ambient barks are
/// intentionally reserved for local/ambient scene life so named characters do not
/// randomly appear and disappear as bubbles.
class NovelSceneBarkActor {
  const NovelSceneBarkActor({
    required this.id,
    required this.name,
    this.kind = 'ambient',
    this.role = '',
    this.avatarUrl = '',
    this.priority = 50,
    this.source = '',
    this.ephemeral = false,
  });

  final String id;
  final String name;
  final String kind;
  final String role;
  final String avatarUrl;
  final int priority;
  /// scene_presence / speaker_pending / interactive_local 等后端诊断来源。
  final String source;
  /// true 只表示结算窗口中的临时候选；仍然可以点击，不等于已永久在场。
  final bool ephemeral;

  String get cleanName => name.trim();

  String get normalizedKind => kind.trim().toLowerCase();

  bool get isImportant {
    final value = normalizedKind;
    return value == 'named' ||
        value == 'present' ||
        value == 'important' ||
        value == 'main' ||
        value == 'npc' ||
        value == 'companion' ||
        value == 'character' ||
        value == 'story';
  }

  bool get isGroup {
    final value = '$kind $name $role'.toLowerCase();
    return value.contains('group') ||
        value.contains('crowd') ||
        value.contains('team') ||
        name.contains('高层') ||
        name.contains('族人') ||
        name.contains('小队') ||
        name.contains('人群') ||
        name.contains('佣兵');
  }

  String get inputPlaceholder {
    final target = cleanName.isEmpty ? '对方' : cleanName;
    if (isGroup) return '想向$target打听什么？';
    if (normalizedKind == 'local' || role.trim().isNotEmpty) {
      return '想问$target什么？';
    }
    return '想和$target说什么？';
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'kind': kind,
        if (role.trim().isNotEmpty) 'role': role,
        if (avatarUrl.trim().isNotEmpty) 'avatar_url': avatarUrl,
        'priority': priority,
        if (source.trim().isNotEmpty) 'source': source,
        if (ephemeral) 'ephemeral': true,
      };

  static Map<String, dynamic> _mapOf(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map<String, dynamic>(
        (dynamic key, dynamic value) => MapEntry<String, dynamic>('$key', value),
      );
    }
    return <String, dynamic>{};
  }

  static List<dynamic> _listOf(dynamic value) {
    if (value is List) return value;
    return const <dynamic>[];
  }

  static String _string(dynamic value, [String fallback = '']) {
    final result = '${value ?? ''}'.trim();
    return result.isEmpty ? fallback : result;
  }

  static int _int(dynamic value, [int fallback = 50]) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse('${value ?? ''}'.trim()) ?? fallback;
  }

  static bool _bool(dynamic value, {bool fallback = false}) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    final normalized = '${value ?? ''}'.trim().toLowerCase();
    if (normalized == 'true' || normalized == '1' || normalized == 'yes') return true;
    if (normalized == 'false' || normalized == '0' || normalized == 'no') return false;
    return fallback;
  }

  static bool _looksLikePlayer(String name) {
    final value = name.trim();
    return value.isEmpty ||
        value == '你' ||
        value == '玩家' ||
        value == '主角' ||
        value == '萧炎';
  }

  static List<NovelSceneBarkActor> talkTargetsFromSceneMap(
    Map<String, dynamic> payload,
  ) {
    final result = <NovelSceneBarkActor>[];
    final seen = <String>{};

    void addActor({
      required dynamic rawValue,
      required String defaultKind,
      required int defaultPriority,
    }) {
      if (rawValue is String) {
        final name = rawValue.trim();
        if (_looksLikePlayer(name)) return;
        final key = name.toLowerCase();
        if (!seen.add(key)) return;
        result.add(
          NovelSceneBarkActor(
            id: name,
            name: name,
            kind: defaultKind,
            priority: defaultPriority,
          ),
        );
        return;
      }

      final raw = _mapOf(rawValue);
      if (raw.isEmpty) return;
      final name = _string(
        raw['name'] ??
            raw['display_name'] ??
            raw['character_name'] ??
            raw['speakerName'] ??
            raw['speaker'] ??
            raw['title'],
      );
      if (_looksLikePlayer(name)) return;

      final id = _string(
        raw['id'] ?? raw['actor_id'] ?? raw['character_id'] ?? raw['characterInstanceId'],
        name,
      );
      final kind = _string(raw['kind'] ?? raw['type'] ?? raw['category'], defaultKind);
      final role = _string(raw['role'] ?? raw['title'] ?? raw['description'] ?? raw['identity']);
      final avatarUrl = _string(
        raw['avatar_url'] ?? raw['avatarUrl'] ?? raw['avatar'] ?? raw['portrait_url'] ?? raw['portraitUrl'] ?? raw['portrait'],
      );
      final priority = _int(raw['priority'], defaultPriority);
      final source = _string(raw['source']);
      final ephemeral = _bool(raw['ephemeral']);

      final key = id.trim().isNotEmpty ? 'id:${id.trim()}' : 'name:${name.toLowerCase()}';
      if (!seen.add(key) && !seen.add('name:${name.toLowerCase()}')) return;
      result.add(
        NovelSceneBarkActor(
          id: id,
          name: name,
          kind: kind,
          role: role,
          avatarUrl: avatarUrl,
          priority: priority,
          source: source,
          ephemeral: ephemeral,
        ),
      );
    }

    // V5 起 conversation_targets 是“当前可对话角色”的唯一权威协议。
    // scene_presence、Speaker race fallback、interactive local 都已经由后端合并完毕；
    // 前端不得再从 present_npcs / talk_targets 等字段自行拼名单。
    for (final raw in _listOf(payload['conversation_targets'])) {
      addActor(rawValue: raw, defaultKind: 'named', defaultPriority: 90);
    }

    result.sort((a, b) => b.priority.compareTo(a.priority));
    return result.take(12).toList(growable: false);
  }
}

class NovelSceneBark {
  const NovelSceneBark({
    required this.id,
    required this.text,
    required this.actor,
    this.clickable = false,
    this.priority = 50,
    this.mood = '',
  });

  final String id;
  final String text;
  final NovelSceneBarkActor actor;
  final bool clickable;
  final int priority;
  final String mood;

  String get identityKey => '${actor.id}|$id|$text';

  static Map<String, dynamic> _mapOf(dynamic value) => NovelSceneBarkActor._mapOf(value);
  static List<dynamic> _listOf(dynamic value) => NovelSceneBarkActor._listOf(value);
  static String _string(dynamic value, [String fallback = '']) => NovelSceneBarkActor._string(value, fallback);
  static int _int(dynamic value, [int fallback = 50]) => NovelSceneBarkActor._int(value, fallback);

  static bool _bool(dynamic value, {bool fallback = false}) {
    if (value is bool) return value;
    final text = '${value ?? ''}'.trim().toLowerCase();
    if (text == 'true' || text == '1' || text == 'yes') return true;
    if (text == 'false' || text == '0' || text == 'no') return false;
    return fallback;
  }

  static bool _isImportantKind(String value) {
    final kind = value.trim().toLowerCase();
    return kind == 'named' ||
        kind == 'present' ||
        kind == 'important' ||
        kind == 'main' ||
        kind == 'npc' ||
        kind == 'companion' ||
        kind == 'character' ||
        kind == 'story';
  }

  static List<NovelSceneBark> listFromSceneMap(Map<String, dynamic> payload) {
    final result = <NovelSceneBark>[];
    final seen = <String>{};

    void add(NovelSceneBark bark) {
      if (bark.text.trim().isEmpty || bark.actor.cleanName.isEmpty) return;
      if (bark.actor.isImportant) return; // named characters are fixed talk targets, not bubbles.
      final key = bark.identityKey;
      if (seen.add(key)) result.add(bark);
    }

    void addBarkMap(dynamic rawValue) {
      final raw = _mapOf(rawValue);
      if (raw.isEmpty) return;
      final text = _string(raw['text'] ?? raw['line'] ?? raw['content']);
      if (text.isEmpty) return;

      final actorName = _string(
        raw['anchor_name'] ??
            raw['actor_name'] ??
            raw['target_name'] ??
            raw['speaker'] ??
            raw['name'],
      );
      if (actorName.isEmpty) return;

      final actorKind = _string(
        raw['anchor_kind'] ?? raw['actor_kind'] ?? raw['kind'],
        'ambient',
      );
      if (_isImportantKind(actorKind)) return;

      final actorId = _string(
        raw['anchor_id'] ?? raw['actor_id'] ?? raw['target_id'] ?? raw['id'],
        actorName,
      );
      final role = _string(raw['role'] ?? raw['title'] ?? raw['type']);
      add(
        NovelSceneBark(
          id: _string(raw['id'], 'bark:${actorId.hashCode}:${text.hashCode}'),
          text: text,
          actor: NovelSceneBarkActor(
            id: actorId,
            name: actorName,
            kind: actorKind,
            role: role,
          ),
          // 环境气泡现在也可以作为轻量对话入口：默认可点。
          // 后端仍可显式传 clickable=false 来关闭某条特殊气泡。
          clickable: _bool(raw['clickable'], fallback: true),
          priority: _int(raw['priority'], 50),
          mood: _string(raw['mood']),
        ),
      );
    }

    final rawBarks = <dynamic>[
      ..._listOf(payload['ambient_barks']),
      ..._listOf(payload['scene_barks']),
      ..._listOf(payload['barks']),
    ];
    for (final raw in rawBarks) addBarkMap(raw);

    final sceneActors = _mapOf(payload['scene_actors']);
    final localActors = <dynamic>[
      ..._listOf(payload['local_actors']),
      ..._listOf(sceneActors['locals']),
    ];
    for (final rawValue in localActors) {
      final raw = _mapOf(rawValue);
      final name = _string(raw['name']);
      if (name.isEmpty) continue;
      final kind = _string(raw['kind'], 'local');
      if (_isImportantKind(kind)) continue;
      final id = _string(raw['id'] ?? raw['actor_id'], name);
      final role = _string(raw['role'] ?? raw['type'] ?? raw['title']);
      add(
        NovelSceneBark(
          id: 'local-bark:$id',
          text: _fallbackLocalLine(name: name, role: role),
          actor: NovelSceneBarkActor(
            id: id,
            name: name,
            kind: kind,
            role: role,
          ),
          clickable: true,
          priority: 62,
          mood: 'vendor',
        ),
      );
    }

    final ambientActors = <dynamic>[
      ..._listOf(payload['ambient_actors']),
      ..._listOf(sceneActors['ambient']),
    ];
    for (final rawValue in ambientActors) {
      final raw = _mapOf(rawValue);
      final name = _string(raw['name']);
      if (name.isEmpty) continue;
      final kind = _string(raw['kind'], 'ambient');
      if (_isImportantKind(kind)) continue;
      final id = _string(raw['id'] ?? raw['actor_id'], name);
      final role = _string(raw['activity'] ?? raw['role'] ?? raw['description']);
      add(
        NovelSceneBark(
          id: 'ambient-bark:$id',
          text: _fallbackAmbientLine(name: name, role: role),
          actor: NovelSceneBarkActor(
            id: id,
            name: name,
            kind: kind,
            role: role,
          ),
          clickable: true,
          priority: 38,
          mood: 'ambient',
        ),
      );
    }

    result.sort((a, b) => b.priority.compareTo(a.priority));
    return result.take(24).toList(growable: false);
  }

  static String _fallbackLocalLine({required String name, required String role}) {
    final combined = '$name $role';
    if (combined.contains('药') || combined.contains('丹') || combined.contains('医')) {
      return '止血散！疗伤丹！进来看看！';
    }
    if (combined.contains('武') || combined.contains('铁') || combined.contains('兵器') || combined.contains('刀')) {
      return '精钢兵器，今天便宜卖！';
    }
    if (combined.contains('酒') || combined.contains('客栈')) {
      return '热酒热菜，里面请！';
    }
    if (combined.contains('魔核') || combined.contains('兽核')) {
      return '最便宜的魔核！打骨折咯！';
    }
    if (combined.contains('拍卖')) {
      return '今晚有好东西，手慢可没有。';
    }
    return '来看看，需要什么尽管问。';
  }

  static String _fallbackAmbientLine({required String name, required String role}) {
    final combined = '$name $role';
    if (combined.contains('佣兵') || combined.contains('小队')) {
      return '缺个带路的，进山有人来吗？';
    }
    if (combined.contains('高层') || combined.contains('族人')) {
      return '云岚宗这是欺我萧家无人……';
    }
    if (combined.contains('护卫')) {
      return '大厅内气氛不对，别靠太近。';
    }
    if (combined.contains('人群') || combined.contains('路人')) {
      return '听说拍卖行今晚有好东西……';
    }
    if (combined.contains('酒客')) {
      return '昨晚城外又不太平。';
    }
    return role.trim().isNotEmpty ? role.trim() : '这地方今天可真热闹。';
  }
}


class NovelRightSceneDock extends StatelessWidget {
  const NovelRightSceneDock({
    super.key,
    required this.targets,
    required this.selectedActorId,
    required this.onSelected,
    required this.exploreVisible,
    required this.exploreLabel,
    required this.exploreAttention,
    required this.exploreLoading,
    required this.onExplore,
    this.onClear,
  });

  final List<NovelSceneBarkActor> targets;
  final String selectedActorId;
  final ValueChanged<NovelSceneBarkActor> onSelected;
  final VoidCallback? onClear;
  final bool exploreVisible;
  final String exploreLabel;
  final bool exploreAttention;
  final bool exploreLoading;
  final VoidCallback onExplore;

  @override
  Widget build(BuildContext context) {
    if (targets.isEmpty && !exploreVisible) return const SizedBox.shrink();

    final viewport = NovelViewportMetrics.of(context);
    final compact = viewport.compactChrome;
    final targetWidth = compact ? 88.0 : 104.0;
    final exploreWidth = compact ? 38.0 : 42.0;
    final horizontalGap = exploreVisible && targets.isNotEmpty
        ? (compact ? 8.0 : 10.0)
        : 0.0;
    final totalWidth = targetWidth +
        (exploreVisible ? exploreWidth + horizontalGap : 0.0);
    final fallbackHeight = viewport.shortWide
        ? 150.0
        : (viewport.phoneWidth ? 236.0 : 314.0);

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : fallbackHeight;

        // 探索是“场景动作”，不再接在人物头像列表最下面。
        // 它独立浮在人物列左侧，避免看起来像又一个角色槽位。
        return RepaintBoundary(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: totalWidth,
              maxHeight: maxHeight,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (exploreVisible)
                  Padding(
                    padding: EdgeInsets.only(top: compact ? 3 : 4),
                    child: _SceneExploreAction(
                      label: exploreLabel,
                      attention: exploreAttention,
                      loading: exploreLoading,
                      compact: compact,
                      onTap: onExplore,
                    ),
                  ),
                if (exploreVisible && targets.isNotEmpty)
                  SizedBox(width: horizontalGap),
                if (targets.isNotEmpty)
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: targetWidth,
                      maxHeight: maxHeight,
                    ),
                    child: NovelTalkTargetBar(
                      targets: targets,
                      selectedActorId: selectedActorId,
                      onSelected: onSelected,
                      onClear: onClear,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SceneExploreAction extends StatefulWidget {
  const _SceneExploreAction({
    required this.label,
    required this.attention,
    required this.loading,
    required this.compact,
    required this.onTap,
  });

  final String label;
  final bool attention;
  final bool loading;
  final bool compact;
  final VoidCallback onTap;

  @override
  State<_SceneExploreAction> createState() => _SceneExploreActionState();
}

class _SceneExploreActionState extends State<_SceneExploreAction>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.of(context).disableAnimations;
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant _SceneExploreAction oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.loading != widget.loading ||
        oldWidget.attention != widget.attention ||
        oldWidget.label != widget.label) {
      _syncAnimation();
    }
  }

  bool get _shouldPulse {
    final label = widget.label.trim();
    if (widget.loading) return false;
    return label != '已探索';
  }

  void _syncAnimation() {
    if (!_reduceMotion && _shouldPulse) {
      if (!_pulse.isAnimating) _pulse.repeat();
    } else {
      _pulse
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Widget _pulseRing({
    required double phase,
    required double size,
    required double strength,
  }) {
    final safe = phase.clamp(0.0, 1.0).toDouble();
    return Opacity(
      opacity: ((1 - safe) * strength).clamp(0.0, 1.0).toDouble(),
      child: Transform.scale(
        scale: 1 + safe * .62,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withOpacity(.72),
              width: .65,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rawLabel = widget.label.trim();
    final semanticsLabel = widget.loading
        ? '探索中'
        : (rawLabel.isEmpty || rawLabel == '探索' || rawLabel == '探索周围'
            ? '探索周围'
            : rawLabel);

    // 探索入口现在是独立圆形场景动作，不再占用整条“人物行”宽度。
    final hitSize = widget.compact ? 38.0 : 42.0;
    final coreSize = widget.compact ? 27.0 : 31.0;
    final pulseSlotSize = widget.compact ? 31.0 : 33.0;
    final foreground = Colors.white.withOpacity(widget.attention ? .98 : .90);
    final pulseStrength = widget.attention ? .42 : .28;

    return Semantics(
      button: true,
      enabled: !widget.loading,
      label: semanticsLabel,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.loading ? null : widget.onTap,
          borderRadius: BorderRadius.circular(99),
          splashColor: Colors.white.withOpacity(.035),
          highlightColor: Colors.white.withOpacity(.018),
          child: SizedBox.square(
            dimension: hitSize,
            child: Center(
              child: SizedBox(
                width: pulseSlotSize,
                height: pulseSlotSize,
                child: AnimatedBuilder(
                  animation: _pulse,
                  builder: (context, _) {
                    final p1 = _reduceMotion ? 0.0 : _pulse.value;
                    final p2 = _reduceMotion
                        ? 0.0
                        : ((_pulse.value + .50) % 1.0);
                    return Stack(
                      alignment: Alignment.center,
                      clipBehavior: Clip.none,
                      children: <Widget>[
                        if (_shouldPulse && !_reduceMotion) ...<Widget>[
                          _pulseRing(
                            phase: p1,
                            size: coreSize,
                            strength: pulseStrength,
                          ),
                          _pulseRing(
                            phase: p2,
                            size: coreSize,
                            strength: pulseStrength * .82,
                          ),
                        ],
                        ClipOval(
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                            child: Container(
                              width: coreSize,
                              height: coreSize,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.black.withOpacity(.22),
                                border: Border.all(
                                  color: Colors.white.withOpacity(
                                    widget.attention ? .27 : .16,
                                  ),
                                  width: .7,
                                ),
                              ),
                              alignment: Alignment.center,
                              child: widget.loading
                                  ? SizedBox.square(
                                      dimension: widget.compact ? 11.0 : 12.0,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 1.15,
                                        color: foreground,
                                      ),
                                    )
                                  : Icon(
                                      Icons.explore_outlined,
                                      size: widget.compact ? 15.0 : 17.0,
                                      color: foreground,
                                    ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class NovelTalkTargetBar extends StatelessWidget {
  const NovelTalkTargetBar({
    super.key,
    required this.targets,
    required this.selectedActorId,
    required this.onSelected,
    this.onClear,
  });

  final List<NovelSceneBarkActor> targets;
  final String selectedActorId;
  final ValueChanged<NovelSceneBarkActor> onSelected;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    if (targets.isEmpty) return const SizedBox.shrink();

    final viewport = NovelViewportMetrics.of(context);
    final compact = viewport.compactChrome;
    final width = compact ? 88.0 : 104.0;
    final fallbackHeight = viewport.shortWide
        ? 142.0
        : (viewport.phoneWidth ? 220.0 : 300.0);

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : fallbackHeight;
        final itemHeight = compact ? 30.0 : 34.0;
        final itemGap = compact ? 6.0 : 7.0;
        final naturalListHeight = targets.length * itemHeight +
            math.max(0, targets.length - 1) * itemGap;
        final listHeight = math.min(naturalListHeight, maxHeight);

        if (listHeight <= 0) return const SizedBox.shrink();

        // 不再显示“当前可对话”标题。角色名字 + 圆头像本身已经足够表达交互含义，
        // 也让探索入口能直接与角色行在同一视觉轴上。
        return RepaintBoundary(
          child: SizedBox(
            width: width,
            height: listHeight,
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(
                scrollbars: false,
                overscroll: false,
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.vertical,
                physics: const BouncingScrollPhysics(),
                clipBehavior: Clip.none,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    for (var i = 0; i < targets.length; i++) ...<Widget>[
                      _TalkTargetChip(
                        actor: targets[i],
                        selected: selectedActorId.trim().isNotEmpty &&
                            selectedActorId.trim() == targets[i].id.trim(),
                        compact: compact,
                        onTap: () => onSelected(targets[i]),
                      ),
                      if (i != targets.length - 1)
                        SizedBox(height: itemGap),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TalkTargetChip extends StatelessWidget {
  const _TalkTargetChip({
    required this.actor,
    required this.selected,
    required this.compact,
    required this.onTap,
  });

  final NovelSceneBarkActor actor;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  Widget _avatar() {
    final size = compact ? 27.0 : 31.0;
    final url = actor.avatarUrl.trim();
    Widget image;
    if (url.startsWith('http://') || url.startsWith('https://')) {
      image = Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => _initial(size),
      );
    } else {
      image = _initial(size);
    }

    return AnimatedScale(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOutCubic,
      scale: selected ? 1.035 : 1,
      child: SizedBox(
        width: size,
        height: size,
        child: ClipOval(child: image),
      ),
    );
  }

  Widget _initial(double size) {
    final initial = actor.cleanName.isNotEmpty
        ? String.fromCharCodes(actor.cleanName.runes.take(1))
        : '？';
    return SizedBox(
      width: size,
      height: size,
      child: Center(
        child: Text(
          initial,
          style: TextStyle(
            color: Colors.white.withOpacity(selected ? .98 : .92),
            fontSize: compact ? 13.0 : 14.0,
            height: 1,
            fontWeight: FontWeight.w700,
            shadows: const <Shadow>[
              Shadow(color: Color(0x99000000), blurRadius: 5),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rowWidth = compact ? 88.0 : 104.0;
    final nameWidth = compact ? 52.0 : 64.0;
    return Semantics(
      button: true,
      selected: selected,
      label: '和${actor.cleanName}说话',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(7),
          splashColor: Colors.white.withOpacity(.035),
          highlightColor: Colors.white.withOpacity(.018),
          child: SizedBox(
            width: rowWidth,
            height: compact ? 30.0 : 34.0,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1, vertical: 1),
              child: Row(
                mainAxisSize: MainAxisSize.max,
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  SizedBox(
                    width: nameWidth,
                    child: Text(
                      actor.cleanName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: compact ? 9.2 : 9.9,
                        height: 1.05,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w600,
                        letterSpacing: .02,
                        shadows: const <Shadow>[
                          Shadow(
                            color: Color(0x99000000),
                            blurRadius: 5,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(width: compact ? 5 : 6),
                  _avatar(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class NovelSceneBarkLayer extends StatefulWidget {
  const NovelSceneBarkLayer({
    super.key,
    required this.barks,
    required this.enabled,
    required this.onBarkTap,
    this.bottomReserve = 0,
  });

  final List<NovelSceneBark> barks;
  final bool enabled;
  final ValueChanged<NovelSceneBark> onBarkTap;
  final double bottomReserve;

  @override
  State<NovelSceneBarkLayer> createState() => _NovelSceneBarkLayerState();
}

class _ActiveSceneBark {
  _ActiveSceneBark({
    required this.key,
    required this.bark,
    required this.alignment,
  });

  final String key;
  final NovelSceneBark bark;
  final Alignment alignment;
  bool visible = false;
  bool closing = false;
  Timer? timer;
}

class _NovelSceneBarkLayerState extends State<NovelSceneBarkLayer> {
  final math.Random _random = math.Random();
  final List<_ActiveSceneBark> _active = <_ActiveSceneBark>[];
  final Map<String, DateTime> _cooldownUntil = <String, DateTime>{};
  Timer? _spawnTimer;
  int _serial = 0;

  @override
  void initState() {
    super.initState();
    _scheduleNext(initial: true);
  }

  @override
  void didUpdateWidget(covariant NovelSceneBarkLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldKeys = oldWidget.barks.map((bark) => bark.identityKey).join('\u0001');
    final newKeys = widget.barks.map((bark) => bark.identityKey).join('\u0001');
    if (!widget.enabled || newKeys != oldKeys) {
      _removeStaleActiveBarks();
    }
    _scheduleNext(initial: oldWidget.enabled != widget.enabled || newKeys != oldKeys);
  }

  @override
  void dispose() {
    _spawnTimer?.cancel();
    for (final item in _active) {
      item.timer?.cancel();
    }
    _active.clear();
    super.dispose();
  }

  int _maxVisible(NovelViewportMetrics viewport) {
    if (viewport.phoneWidth || viewport.shortWide) return 2;
    return 3;
  }

  List<Alignment> _positions(NovelViewportMetrics viewport) {
    if (viewport.shortWide) {
      return const <Alignment>[
        Alignment(-.62, -.25),
        Alignment(.48, -.12),
        Alignment(-.05, .18),
      ];
    }
    if (viewport.phoneWidth) {
      return const <Alignment>[
        Alignment(-.55, -.30),
        Alignment(.44, -.10),
        Alignment(-.12, .18),
      ];
    }
    return const <Alignment>[
      Alignment(-.48, -.28),
      Alignment(.38, -.18),
      Alignment(-.05, .10),
      Alignment(.18, .26),
    ];
  }

  void _removeStaleActiveBarks() {
    final valid = widget.barks.map((bark) => bark.identityKey).toSet();
    for (final item in List<_ActiveSceneBark>.from(_active)) {
      if (!widget.enabled || !valid.contains(item.bark.identityKey)) {
        item.timer?.cancel();
        _active.remove(item);
      }
    }
    if (mounted) setState(() {});
  }

  void _scheduleNext({bool initial = false}) {
    _spawnTimer?.cancel();
    if (!mounted || !widget.enabled || widget.barks.isEmpty) return;

    final delay = initial
        // 第一条要很快出现，但不要完全“啪”一下贴上去，留一点呼吸感。
        ? Duration(milliseconds: 80 + _random.nextInt(160))
        // 后续不要一次性补满。间隔生成单条气泡，才能看起来像有人陆续说话。
        : Duration(milliseconds: 1300 + _random.nextInt(1700));
    _spawnTimer = Timer(delay, _trySpawn);
  }

  void _trySpawn() {
    if (!mounted || !widget.enabled || widget.barks.isEmpty) return;

    final viewport = NovelViewportMetrics.of(context);
    final maxVisible = _maxVisible(viewport);
    final now = DateTime.now();

    // 只生成一条，不再 while 一口气补满。这样气泡会“陆续出现 / 陆续消失”，
    // 视觉上才像场景里有人在说话，而不是几张固定贴纸。
    if (_active.length < maxVisible) {
      final activeKeys = _active.map((item) => item.bark.identityKey).toSet();
      var candidates = widget.barks.where((bark) {
        if (activeKeys.contains(bark.identityKey)) return false;
        final cooldown = _cooldownUntil[bark.identityKey];
        return cooldown == null || now.isAfter(cooldown);
      }).toList();

      // 如果当前没有气泡，允许忽略冷却补一条，保证气泡层常驻。
      // 如果当前已经有气泡，就尊重冷却，避免同一句刷屏。
      if (candidates.isEmpty && _active.isEmpty) {
        candidates = widget.barks
            .where((bark) => !activeKeys.contains(bark.identityKey))
            .toList();
      }

      if (candidates.isNotEmpty) {
        final bark = _weightedPick(candidates);
        final positions = _positions(viewport);
        final usedPositions = _active.map((item) => item.alignment).toSet();
        final availablePositions = positions
            .where((alignment) => !usedPositions.contains(alignment))
            .toList();
        final pool = availablePositions.isEmpty ? positions : availablePositions;
        final alignment = pool[_random.nextInt(pool.length)];
        final item = _ActiveSceneBark(
          key: 'scene-bark-${_serial++}',
          bark: bark,
          alignment: alignment,
        );
        _active.add(item);

        // 较短冷却 + 较短停留：既能循环，又不会固定在屏幕上太久。
        _cooldownUntil[bark.identityKey] = now.add(
          Duration(seconds: 5 + _random.nextInt(4)),
        );

        // 5.8 - 8.8 秒：能读完，但不会像上一版 16 - 25 秒那样静止。
        final visibleMs = 5800 + _random.nextInt(3000);
        item.timer = Timer(
          Duration(milliseconds: visibleMs),
          () => _closeItem(item),
        );

        if (mounted) setState(() {});
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_active.contains(item) || item.closing) return;
          setState(() => item.visible = true);
        });
      }
    }

    _scheduleNext(initial: _active.isEmpty);
  }

  NovelSceneBark _weightedPick(List<NovelSceneBark> candidates) {
    var total = 0;
    for (final bark in candidates) {
      total += bark.priority.clamp(8, 120).toInt();
    }
    var pick = _random.nextInt(math.max(1, total));
    for (final bark in candidates) {
      pick -= bark.priority.clamp(8, 120).toInt();
      if (pick <= 0) return bark;
    }
    return candidates.first;
  }

  void _closeItem(_ActiveSceneBark item) {
    if (!mounted || !_active.contains(item)) return;
    setState(() => item.closing = true);
    Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      item.timer?.cancel();
      _active.remove(item);
      setState(() {});
      // 清空时快速补下一条；没清空时按正常节奏继续轮播。
      _scheduleNext(initial: _active.isEmpty);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || widget.barks.isEmpty || _active.isEmpty) {
      return const SizedBox.shrink();
    }

    final viewport = NovelViewportMetrics.of(context);
    final topPadding = viewport.topContentReserve + (viewport.shortWide ? 8 : 18);
    final bottomPadding = math.max(
      widget.bottomReserve,
      viewport.shortWide ? 78.0 : (viewport.phoneWidth ? 132.0 : 146.0),
    );

    return RepaintBoundary(
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, topPadding, 12, bottomPadding),
        child: Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            for (final item in _active)
              Positioned.fill(
                key: ValueKey<String>(item.key),
                child: Align(
                  alignment: item.alignment,
                  child: _SceneBarkBubble(
                    bark: item.bark,
                    visible: item.visible,
                    closing: item.closing,
                    compact: viewport.compactContent,
                    onTap: item.bark.clickable
                        ? () => widget.onBarkTap(item.bark)
                        : null,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SceneBarkBubble extends StatelessWidget {
  const _SceneBarkBubble({
    required this.bark,
    required this.visible,
    required this.closing,
    required this.compact,
    required this.onTap,
  });

  final NovelSceneBark bark;
  final bool visible;
  final bool closing;
  final bool compact;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final clickable = onTap != null;
    final maxWidth = compact ? 196.0 : 246.0;
    final label = bark.actor.cleanName;
    final radius = compact ? 15.0 : 17.0;
    // 更轻的深色玻璃，不压画面，只让白字在背景上可读。
    final bubbleColor = const Color(0x16111312);
    final borderColor = Colors.white.withOpacity(clickable ? .42 : .34);

    final shown = visible && !closing;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      opacity: shown ? 1 : 0,
      child: AnimatedScale(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutBack,
        scale: shown ? 1 : .94,
        child: Semantics(
          button: clickable,
          label: clickable ? '和$label说话' : '$label说：${bark.text}',
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(radius),
              splashColor: Colors.white.withOpacity(.04),
              highlightColor: Colors.white.withOpacity(.018),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: <Widget>[
                    Container(
                      constraints: BoxConstraints(maxWidth: maxWidth),
                      padding: EdgeInsets.fromLTRB(
                        compact ? 11 : 13,
                        compact ? 8 : 9,
                        compact ? 12 : 14,
                        compact ? 9 : 10,
                      ),
                      decoration: BoxDecoration(
                        color: bubbleColor,
                        borderRadius: BorderRadius.circular(radius),
                        border: Border.all(
                          color: borderColor,
                          width: .75,
                        ),
                        boxShadow: <BoxShadow>[
                          BoxShadow(
                            color: Colors.black.withOpacity(.055),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          if (label.isNotEmpty) ...<Widget>[
                            Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withOpacity(.64),
                                fontSize: compact ? 8.8 : 9.4,
                                height: 1,
                                fontWeight: FontWeight.w500,
                                letterSpacing: .22,
                              ),
                            ),
                            SizedBox(height: compact ? 5 : 6),
                          ],
                          Text(
                            bark.text,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withOpacity(.94),
                              fontFamily: 'MiSans',
                              fontSize: compact ? 11.6 : 12.4,
                              height: 1.30,
                              fontWeight: FontWeight.w500,
                              letterSpacing: .02,
                              shadows: const <Shadow>[
                                Shadow(
                                  color: Color(0x44000000),
                                  blurRadius: 2.5,
                                  offset: Offset(0, 1),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      left: compact ? 22 : 26,
                      bottom: -7,
                      child: CustomPaint(
                        size: const Size(18, 10),
                        painter: _SceneBarkTailPainter(
                          fillColor: bubbleColor,
                          borderColor: borderColor,
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
    );
  }
}

class _SceneBarkTailPainter extends CustomPainter {
  const _SceneBarkTailPainter({
    required this.fillColor,
    required this.borderColor,
  });

  final Color fillColor;
  final Color borderColor;

  @override
  void paint(Canvas canvas, Size size) {
    // 关键：向上偏移 1 个像素，用填充色完美覆盖气泡本体的底边框，消除割裂感
    const double overlap = 1.2;

    // 经典漫画弧线尖角
    final path = Path()
      ..moveTo(0, -overlap)
      ..quadraticBezierTo(size.width * 0.15, size.height * 0.2, 
                          size.width * 0.35, size.height)
      ..quadraticBezierTo(size.width * 0.55, size.height * 0.3, 
                          size.width, -overlap)
      ..close();

    final fill = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, fill);

    final border = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.75
      ..strokeCap = StrokeCap.round;

    // 只描两边，不描顶部，配合 overlap 完美融合
    final leftEdge = Path()
      ..moveTo(0, -overlap)
      ..quadraticBezierTo(size.width * 0.15, size.height * 0.2, 
                          size.width * 0.35, size.height);
                          
    final rightEdge = Path()
      ..moveTo(size.width * 0.35, size.height)
      ..quadraticBezierTo(size.width * 0.55, size.height * 0.3, 
                          size.width, -overlap);

    canvas.drawPath(leftEdge, border);
    canvas.drawPath(rightEdge, border);
  }

  @override
  bool shouldRepaint(covariant _SceneBarkTailPainter oldDelegate) {
    return fillColor != oldDelegate.fillColor ||
        borderColor != oldDelegate.borderColor;
  }
}
