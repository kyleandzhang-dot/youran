part of '../novel_sheets.dart';

// ============================================================================
// 经历 / 回溯页
// 页面入口 / 对外入口：
//   - showNovelJourneySheet(...)
//   - NovelJourneyTab
//   - showNovelRevertDialog(...)
// 其余以下划线 `_` 开头的类型/方法均为该页面内部实现或共享私有实现。
// ============================================================================

const Color _journeyBackground = Color(0xFF0A0F0D);
const Color _journeySurface = Color(0xFF131A17);
const Color _journeySurfaceSoft = Color(0xFF17201C);
const Color _journeyText = Color(0xFFEEF2EF);
const Color _journeyTextSoft = Color(0xFFC4CCC7);
const Color _journeyMuted = Color(0xFF7F8B84);
const Color _journeyMutedSoft = Color(0xFF55605A);
const Color _journeyLine = Color(0xFF26312B);

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

/// 主游戏底部 Tab 使用的经历页。
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
                color: NovelPalette.text,
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
                      foregroundColor: NovelPalette.muted,
                      side: BorderSide(color: Colors.white.withOpacity(.08)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
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
                      backgroundColor: NovelPalette.accent,
                      foregroundColor: NovelPalette.accentDark,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('确认回溯'),
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
      animation: widget.controller,
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

        return _GameStyleBackdrop(
          controller: widget.controller,
          embedded: widget.embedded,
          lightTheme: false,
          child: Padding(
            padding: EdgeInsets.zero,
            child: Column(
              children: <Widget>[
              _GameStyleHeader(
                title: '经历',
                english: 'JOURNEY',
                onClose: widget.embedded
                    ? null
                    : () => Navigator.of(context).pop(),
                lightTheme: false,
              ),
              Expanded(
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment(-.45, -.35),
                      radius: 1.15,
                      colors: <Color>[
                        Color(0xFF17201C),
                        _journeyBackground,
                        Color(0xFF070A09),
                      ],
                      stops: <double>[0, .58, 1],
                    ),
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxWidth < 620;
                      return Padding(
                        padding: EdgeInsets.fromLTRB(
                          compact ? 10 : 30,
                          compact ? 2 : 8,
                          compact ? 10 : 30,
                          compact ? 4 : 12,
                        ),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 720),
                            child: RefreshIndicator(
                              onRefresh: _refresh,
                              color: NovelPalette.accent,
                              backgroundColor: _journeySurface,
                              child: hasContent
                                  ? ListView(
                                      physics:
                                          const AlwaysScrollableScrollPhysics(),
                                      padding: const EdgeInsets.fromLTRB(
                                          26, 14, 26, 46),
                                      children: <Widget>[
                                        _JourneyStoryOpening(
                                          title: title.isEmpty
                                              ? '你的旅程'
                                              : title,
                                          summary: summary,
                                          achievements:
                                              achievements.length,
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
                                  : ListView(
                                      physics:
                                          const AlwaysScrollableScrollPhysics(),
                                      padding: const EdgeInsets.fromLTRB(
                                          28, 4, 28, 38),
                                      children: <Widget>[
                                        SizedBox(
                                          height:
                                              MediaQuery.sizeOf(context).height *
                                                  .56,
                                          child: Center(
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: <Widget>[
                                                const Text(
                                                  '“',
                                                  style: TextStyle(
                                                    color:
                                                        Color(0xFF435048),
                                                    fontSize: 52,
                                                    height: .8,
                                                    fontWeight:
                                                        FontWeight.w300,
                                                  ),
                                                ),
                                                const SizedBox(height: 8),
                                                Text(
                                                  loading
                                                      ? '正在整理你的故事…'
                                                      : '故事刚刚开始',
                                                  style: const TextStyle(
                                                    color: _journeyText,
                                                    fontSize: 14,
                                                    fontWeight:
                                                        FontWeight.w700,
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
                                    ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
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

class _JourneyStoryOpening extends StatelessWidget {
  const _JourneyStoryOpening({
    required this.title,
    required this.summary,
    required this.achievements,
    required this.events,
    required this.milestones,
  });

  final String title;
  final String summary;
  final int achievements;
  final int events;
  final int milestones;

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
              color: NovelPalette.accentSoft,
              fontSize: 8.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 2.4,
            ),
          ),
          const SizedBox(height: 9),
          Text(
            title,
            style: const TextStyle(
              color: _journeyText,
              fontSize: 27,
              height: 1.08,
              fontWeight: FontWeight.w700,
              letterSpacing: .5,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
            decoration: BoxDecoration(
              color: _journeySurfaceSoft,
              border: const Border(
                left: BorderSide(color: NovelPalette.accent, width: 2),
                top: BorderSide(color: _journeyLine, width: .7),
                right: BorderSide(color: _journeyLine, width: .7),
                bottom: BorderSide(color: _journeyLine, width: .7),
              ),
            ),
            child: Text(
              summary.isEmpty
                  ? '故事仍在继续。每一次选择、相遇与转折，都会在这里留下痕迹。'
                  : summary,
              style: const TextStyle(
                color: _journeyTextSoft,
                fontSize: 12.6,
                height: 1.78,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(height: 15),
          Wrap(
            spacing: 15,
            runSpacing: 6,
            children: <Widget>[
              _JourneyCountText(label: '经历', value: achievements),
              _JourneyCountText(label: '事件', value: events),
              _JourneyCountText(label: '节点', value: milestones),
            ],
          ),
          const SizedBox(height: 6),
          Container(height: 1, color: _journeyLine),
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
    return Text(
      '$label  $value',
      style: const TextStyle(
        color: _journeyMuted,
        fontSize: 9.8,
        fontWeight: FontWeight.w600,
        letterSpacing: .25,
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
      padding: const EdgeInsets.only(top: 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            eyebrow,
            style: const TextStyle(
              color: NovelPalette.accentSoft,
              fontSize: 8.2,
              fontWeight: FontWeight.w700,
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
                  fontSize: 14.2,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .2,
                ),
              ),
              const SizedBox(width: 7),
              Text(
                '${records.length}',
                style: const TextStyle(
                  color: _journeyMuted,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
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
      padding: EdgeInsets.only(bottom: last ? 2 : 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 31,
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                number,
                style: const TextStyle(
                  color: _journeyMutedSoft,
                  fontSize: 9.2,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .7,
                ),
              ),
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
                      color: _journeyMuted,
                      fontSize: 9.3,
                      fontWeight: FontWeight.w600,
                      letterSpacing: .25,
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
                Text(
                  record.title,
                  style: const TextStyle(
                    color: _journeyText,
                    fontSize: 12.7,
                    height: 1.55,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (record.hasDetail) ...<Widget>[
                  const SizedBox(height: 5),
                  Text(
                    record.detail,
                    style: const TextStyle(
                      color: _journeyTextSoft,
                      fontSize: 11.5,
                      height: 1.72,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                if (!last) ...<Widget>[
                  const SizedBox(height: 17),
                  Container(height: .8, color: _journeyLine),
                  const SizedBox(height: 17),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
