part of '../novel_sheets.dart';


// ============================================================================
// 经历 / 回溯页
// ============================================================================

// 【色彩重构】抛弃土味的蓝金配色，采用极致的暗场+纯白+高亮绿点缀
const Color _journeyInk = Color(0xFF171B22); // 呼应地图的深空黑
const Color _journeyInkSoft = Color(0xFF242A33); // 深灰背景
const Color _journeyAccent = Color(0xFF76B900); // 极简现代感的高亮核心色
const Color _journeyText = Color(0xFFFFFFFF); // 纯白，保留你喜欢的“白”的干净感
const Color _journeyTextSoft = Color(0xFFE0E0E0);
const Color _journeyMuted = Color(0x80FFFFFF); // 半透白
const Color _journeyLine = Color(0x15FFFFFF); // 极弱的分割线，减少边框感

Future<void> showNovelJourneySheet(
  BuildContext context,
  NovelGameController controller,
) async {
  await _runNovelPageOnce('journey', () async {
    await _showNovelArchivePage<void>(
      context,
      child: _GameStyleJourneyPage(controller: controller),
    );
  });
}

class NovelJourneyTab extends StatelessWidget {
  const NovelJourneyTab({
    super.key,
    required this.controller,
  });

  final NovelGameController controller;

  @override
  Widget build(BuildContext context) {
    return _GameStyleJourneyPage(
      controller: controller,
      embedded: true,
    );
  }
}

Future<bool> showNovelRevertDialog(
  BuildContext context,
  NovelGameController controller,
) async {
  final result = await _showNovelSheet<bool>(
    context,
    heightFactor: .40,
    child: _SheetScaffold(
      title: '轮次回溯',
      subtitle: '返回上一轮会消耗 1 个钟表',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Text(
              '确认返回到上一轮回合吗？',
              style: TextStyle(
                color: _journeyText,
                fontSize: 13,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _journeyTextSoft,
                      side: BorderSide(color: Colors.white.withOpacity(.10)), // 极简边框
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6), // 细微圆角
                      ),
                    ),
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: _journeyAccent, // 使用极简绿作为主按钮色
                      foregroundColor: Colors.black, // 绿底黑字，对比度更高更现代
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6), // 细微圆角
                      ),
                    ),
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('确认回溯', style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  if (result == true) await controller.revertPreviousTurn();
  return result ?? false;
}

class _GameStyleJourneyRecord {
  const _GameStyleJourneyRecord({
    required this.title,
    this.detail = '',
    this.time = '',
  });

  final String title;
  final String detail;
  final String time;

  bool get hasDetail => detail.trim().isNotEmpty && detail.trim() != title.trim();
}

class _GameStyleJourneyPage extends StatefulWidget {
  const _GameStyleJourneyPage({
    required this.controller,
    this.embedded = false,
  });

  final NovelGameController controller;
  final bool embedded;

  @override
  State<_GameStyleJourneyPage> createState() => _GameStyleJourneyPageState();
}

class _GameStyleJourneyPageState extends State<_GameStyleJourneyPage> {
  bool loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_refresh());
    });
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() => loading = true);
    await widget.controller.refreshJourney();
    if (mounted) setState(() => loading = false);
  }

  JsonMap _source(JsonMap data) {
    final nestedJourney = asJsonMap(data['journey']);
    if (nestedJourney.isNotEmpty) return nestedJourney;
    final nestedData = asJsonMap(data['data']);
    if (nestedData.isNotEmpty) return nestedData;
    return data;
  }

  List<dynamic> _listOf(JsonMap source, List<String> keys) {
    for (final key in keys) {
      final value = source[key];
      if (value is List && value.isNotEmpty) return value;
      if (value is Map && value.isNotEmpty) return value.values.toList();
    }
    return const <dynamic>[];
  }

  String _plainText(dynamic value) {
    if (value is String || value is num || value is bool) {
      return stringValue(value).trim();
    }
    return '';
  }

  _GameStyleJourneyRecord? _recordOf(dynamic raw) {
    if (raw == null) return null;

    if (raw is String || raw is num || raw is bool) {
      final text = stringValue(raw).trim();
      if (text.isEmpty) return null;
      return _GameStyleJourneyRecord(title: text);
    }

    final map = asJsonMap(raw);
    if (map.isEmpty) return null;

    final title = stringValue(
      map['event'] ??
          map['title'] ??
          map['name'] ??
          map['content'] ??
          map['text'] ??
          map['summary'],
    ).trim();

    final detail = stringValue(
      map['impact'] ??
          map['result'] ??
          map['description'] ??
          map['detail'] ??
          map['memory'],
    ).trim();

    final time = stringValue(
      map['chapter'] ??
          map['time'] ??
          map['date'] ??
          map['turn_label'],
    ).trim();

    final primary = title.isNotEmpty ? title : detail;
    if (primary.isEmpty) return null;

    return _GameStyleJourneyRecord(
      title: primary,
      detail: title.isNotEmpty ? detail : '',
      time: time,
    );
  }

  List<_GameStyleJourneyRecord> _recordsOf(
    JsonMap source,
    List<String> keys,
  ) {
    return _listOf(source, keys)
        .map(_recordOf)
        .whereType<_GameStyleJourneyRecord>()
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        widget.controller,
        novelDisplayMode,
      ]),
      builder: (context, _) {
        final source = _source(widget.controller.journey);

        final title = _plainText(
          source['scenario_title'] ??
              source['title'] ??
              source['scenario_name'],
        );

        final summary = _plainText(
          source['journey_summary'] ??
              source['story_summary'] ??
              source['summary'] ??
              source['description'],
        );

        final achievements = _recordsOf(
          source,
          const <String>[
            'key_achievements',
            'achievements',
            'important_experiences',
          ],
        );

        final events = _recordsOf(
          source,
          const <String>[
            'triggered_events',
            'events',
            'event_history',
            'timeline',
            'records',
            'journey',
          ],
        );

        final milestones = _recordsOf(
          source,
          const <String>[
            'milestones',
            'key_milestones',
            'past_milestones',
          ],
        );

        final hasContent = summary.isNotEmpty ||
            achievements.isNotEmpty ||
            events.isNotEmpty ||
            milestones.isNotEmpty;

        final emptyView = ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(28, 4, 28, 38),
          children: <Widget>[
            SizedBox(
              height: MediaQuery.sizeOf(context).height * .56,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Text(
                      '“',
                      style: TextStyle(
                        color: _journeyAccent, // 替换为高亮绿
                        fontSize: 52,
                        height: .8,
                        fontWeight: FontWeight.w300,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      loading ? '正在整理你的故事…' : '故事刚刚开始',
                      style: const TextStyle(
                        color: _journeyText,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        letterSpacing: .4,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      loading
                          ? '把散落的片段重新排成一条旅程。'
                          : '当新的选择留下痕迹，它们会在这里成为你的旅程。',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: _journeyMuted,
                        fontSize: 11.2,
                        height: 1.65,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );

        return _GameStyleBackdrop(
          controller: widget.controller,
          embedded: widget.embedded,
          lightTheme: false,
          child: DecoratedBox(
            // 【背景统一】采用和场景地图完全一致的深空渐变
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -.18),
                radius: 1.05,
                colors: <Color>[
                  Color(0xFF303641),
                  Color(0xFF242A33),
                  Color(0xFF171B22),
                ],
                stops: <double>[0, .52, 1],
              ),
            ),
            child: Column(
              children: <Widget>[
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isLandscape = constraints.maxWidth > constraints.maxHeight;
                    final desktopMode = widget.controller.desktopMode;
                    final leftInset = desktopMode ? 46.0 : (isLandscape ? 24.0 : 10.0);
                    final rightInset = desktopMode ? 54.0 : (isLandscape ? 24.0 : 12.0);
                    final contentMaxWidth = desktopMode ? 1440.0 : (isLandscape ? 900.0 : 560.0);
                    final topInset = desktopMode ? 14.0 : (isLandscape ? 4.0 : 4.0);
                    final hideHeader = isLandscape && !desktopMode; 

                    if (hideHeader) return SizedBox(height: topInset);

                    return Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: contentMaxWidth),
                        child: Padding(
                          padding: EdgeInsets.only(
                            left: leftInset,
                            right: rightInset,
                          ),
                          child: _JourneyPageHeader(
                            topInset: topInset,
                            onClose: widget.embedded
                                ? null
                                : () => Navigator.of(context).pop(),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final desktopMode = widget.controller.desktopMode;
                      final isLandscape = constraints.maxWidth > constraints.maxHeight;
                      
                      final leftInset = desktopMode ? 46.0 : (isLandscape ? 24.0 : 10.0);
                      final rightInset = desktopMode ? 54.0 : (isLandscape ? 24.0 : 12.0);
                      final contentMaxWidth = desktopMode ? 1440.0 : (isLandscape ? 900.0 : 560.0);

                      if (desktopMode || isLandscape) {
                        return Center(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(maxWidth: contentMaxWidth),
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(
                                leftInset,
                                isLandscape && !desktopMode ? 12 : 12,
                                rightInset,
                                24,
                              ),
                              child: RefreshIndicator(
                                onRefresh: _refresh,
                                color: _journeyAccent,
                                backgroundColor: _journeyInkSoft,
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      flex: 35,
                                      child: SingleChildScrollView(
                                        physics: const BouncingScrollPhysics(),
                                        padding: const EdgeInsets.only(bottom: 32),
                                        child: _JourneyStoryOpening(
                                          title: title.isEmpty ? '你的旅程' : title,
                                          summary: summary,
                                          achievements: achievements.length,
                                          events: events.length,
                                          milestones: milestones.length,
                                          isLandscape: true, 
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 48),
                                    Expanded(
                                      flex: 65,
                                      child: hasContent
                                          ? ListView(
                                              physics: const AlwaysScrollableScrollPhysics(),
                                              padding: const EdgeInsets.only(bottom: 46),
                                              children: <Widget>[
                                                if (achievements.isNotEmpty)
                                                  _GameStyleJourneySection(
                                                    eyebrow: 'MEMORIES',
                                                    title: '重要经历',
                                                    records: achievements,
                                                  ),
                                                if (events.isNotEmpty)
                                                  _GameStyleJourneySection(
                                                    eyebrow: 'STORYLINE',
                                                    title: '事件轨迹',
                                                    records: events,
                                                  ),
                                                if (milestones.isNotEmpty)
                                                  _GameStyleJourneySection(
                                                    eyebrow: 'MILESTONES',
                                                    title: '关键节点',
                                                    records: milestones,
                                                  ),
                                              ],
                                            )
                                          : emptyView,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      }

                      return Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: contentMaxWidth),
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(
                              leftInset,
                              2,
                              rightInset,
                              4,
                            ),
                            child: RefreshIndicator(
                              onRefresh: _refresh,
                              color: _journeyAccent,
                              backgroundColor: _journeyInkSoft,
                              child: hasContent
                                  ? ListView(
                                      physics: const AlwaysScrollableScrollPhysics(),
                                      padding: const EdgeInsets.fromLTRB(0, 14, 0, 46),
                                      children: <Widget>[
                                        _JourneyStoryOpening(
                                          title: title.isEmpty ? '你的旅程' : title,
                                          summary: summary,
                                          achievements: achievements.length,
                                          events: events.length,
                                          milestones: milestones.length,
                                        ),
                                        if (achievements.isNotEmpty)
                                          _GameStyleJourneySection(
                                            eyebrow: 'MEMORIES',
                                            title: '重要经历',
                                            records: achievements,
                                          ),
                                        if (events.isNotEmpty)
                                          _GameStyleJourneySection(
                                            eyebrow: 'STORYLINE',
                                            title: '事件轨迹',
                                            records: events,
                                          ),
                                        if (milestones.isNotEmpty)
                                          _GameStyleJourneySection(
                                            eyebrow: 'MILESTONES',
                                            title: '关键节点',
                                            records: milestones,
                                          ),
                                      ],
                                    )
                                  : emptyView,
                            ),
                          ),
                        ),
                      );
                    },
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

class _JourneyPageHeader extends StatelessWidget {
  const _JourneyPageHeader({
    required this.topInset,
    this.onClose,
  });

  final double topInset;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: EdgeInsets.only(top: topInset),
        child: SizedBox(
          height: 64,
          child: Row(
            children: <Widget>[
              const Expanded(
                child: Text(
                  '经历',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _journeyText,
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
                        color: _journeyTextSoft,
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

class _JourneyStoryOpening extends StatelessWidget {
  const _JourneyStoryOpening({
    required this.title,
    required this.summary,
    required this.achievements,
    required this.events,
    required this.milestones,
    this.isLandscape = false,
  });

  final String title;
  final String summary;
  final int achievements;
  final int events;
  final int milestones;
  final bool isLandscape;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'STORY JOURNAL',
            style: TextStyle(
              color: _journeyTextSoft, // 摒弃土味金，用干净的浅灰白
              fontSize: 8.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 3.0,
            ),
          ),
          const SizedBox(height: 9),
          Text(
            title,
            style: const TextStyle(
              color: _journeyText,
              fontSize: 27,
              height: 1.08,
              fontWeight: FontWeight.w800,
              letterSpacing: .5,
            ),
          ),
          const SizedBox(height: 16),
          // 【玻璃态框线】使用纯粹的白边半透明和高对比度绿条，摒弃实色填充
          ClipRRect(
            borderRadius: BorderRadius.circular(6), // 极细微圆角
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.fromLTRB(isLandscape ? 12 : 16, 14, 16, 14),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(.03),
                  border: isLandscape
                      ? const Border(left: BorderSide(color: _journeyAccent, width: 2.5))
                      : Border(
                          left: const BorderSide(color: _journeyAccent, width: 2.5),
                          top: BorderSide(color: Colors.white.withOpacity(.04), width: 1),
                          right: BorderSide(color: Colors.white.withOpacity(.04), width: 1),
                          bottom: BorderSide(color: Colors.white.withOpacity(.04), width: 1),
                        ),
                ),
                child: Text(
                  summary.isEmpty
                      ? '故事仍在继续。每一次选择、相遇与转折，都会在这里留下痕迹。'
                      : summary,
                  style: const TextStyle(
                    color: _journeyTextSoft,
                    fontSize: 12.6,
                    height: 1.8,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: <Widget>[
              _JourneyCountText(label: '经历', value: achievements),
              _JourneyCountText(label: '事件', value: events),
              _JourneyCountText(label: '节点', value: milestones),
            ],
          ),
          if (!isLandscape) ...[
            const SizedBox(height: 16),
            Container(height: 1, color: _journeyLine),
          ]
        ],
      ),
    );
  }
}

class _JourneyCountText extends StatelessWidget {
  const _JourneyCountText({
    required this.label,
    required this.value,
  });

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3), // 半透纯黑托底
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white.withOpacity(0.08)), // 极其微弱的边框
      ),
      child: Text(
        '$label  $value',
        style: const TextStyle(
          color: _journeyTextSoft,
          fontSize: 9.8,
          fontWeight: FontWeight.w700,
          letterSpacing: .25,
        ),
      ),
    );
  }
}

class _GameStyleJourneySection extends StatelessWidget {
  const _GameStyleJourneySection({
    required this.eyebrow,
    required this.title,
    required this.records,
  });

  final String eyebrow;
  final String title;
  final List<_GameStyleJourneyRecord> records;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            eyebrow,
            style: const TextStyle(
              color: _journeyTextSoft, // 替代金色
              fontSize: 8.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 2.0,
            ),
          ),
          const SizedBox(height: 5),
          Row(
            children: <Widget>[
              Text(
                title,
                style: const TextStyle(
                  color: _journeyText,
                  fontSize: 15.2,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .2,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(.08),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${records.length}',
                  style: const TextStyle(
                    color: _journeyMuted,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          for (var i = 0; i < records.length; i++)
            _GameStyleJourneyEntry(
              record: records[i],
              index: i,
              first: i == 0,
              last: i == records.length - 1,
            ),
        ],
      ),
    );
  }
}

class _GameStyleJourneyEntry extends StatelessWidget {
  const _GameStyleJourneyEntry({
    required this.record,
    required this.index,
    required this.first,
    required this.last,
  });

  final _GameStyleJourneyRecord record;
  final int index;
  final bool first;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final number = (index + 1).toString().padLeft(2, '0');

    return Padding(
      padding: EdgeInsets.only(bottom: last ? 8 : 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 36,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    number,
                    style: const TextStyle(
                      color: _journeyAccent, // 序号用高亮绿，作为时间线核心锚点
                      fontSize: 10.5,
                      fontWeight: FontWeight.w900,
                      letterSpacing: .7,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (record.time.isNotEmpty) ...<Widget>[
                  Text(
                    record.time,
                    style: const TextStyle(
                      color: _journeyTextSoft, // 弃用金色，改用高级灰白
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: .3,
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
                Text(
                  record.title,
                  style: const TextStyle(
                    color: _journeyText,
                    fontSize: 13.5,
                    height: 1.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (record.hasDetail) ...<Widget>[
                  const SizedBox(height: 6),
                  Text(
                    record.detail,
                    style: const TextStyle(
                      color: _journeyMuted, // 略微降低详细文本透明度，增强层次感
                      fontSize: 12.0,
                      height: 1.75,
                      fontWeight: FontWeight.w400, // 降低字重让视觉更轻量
                    ),
                  ),
                ],
                if (!last) ...<Widget>[
                  const SizedBox(height: 18),
                  Container(height: 1, color: _journeyLine),
                  const SizedBox(height: 18),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}