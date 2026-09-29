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
                        color: _journeyAccent,
                        fontSize: 52,
                        height: .8,
                        fontWeight: FontWeight.w300,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      loading ? '正在整理你的故事…' : '故事刚刚开始',
                      style: const TextStyle(
                        color: _journeyText,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        letterSpacing: .4,
                      ),
                    ),
                    const SizedBox(height: 12),
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
                    
                    final leftInset = desktopMode ? 46.0 : (isLandscape ? 44.0 : 24.0);
                    final rightInset = desktopMode ? 54.0 : (isLandscape ? 44.0 : 24.0);
                    final topInset = desktopMode ? 14.0 : (isLandscape ? 4.0 : 8.0);
                    final hideHeader = isLandscape && !desktopMode; 

                    if (hideHeader) return SizedBox(height: topInset);

                    return Center(
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
                    );
                  },
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final desktopMode = widget.controller.desktopMode;
                      final isLandscape = constraints.maxWidth > constraints.maxHeight;
                      
                      final leftInset = desktopMode ? 46.0 : (isLandscape ? 44.0 : 24.0);
                      final rightInset = desktopMode ? 54.0 : (isLandscape ? 44.0 : 24.0);

                      return Center(
                        child: SizedBox(
                          // 【全屏解禁】取消最大宽度限制，让横屏充分展开
                          width: double.infinity,
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(
                              leftInset,
                              0,
                              rightInset,
                              0,
                            ),
                            child: RefreshIndicator(
                              onRefresh: _refresh,
                              color: _journeyAccent,
                              backgroundColor: _journeyInkSoft,
                              child: hasContent
                                  ? ListView(
                                      physics: const AlwaysScrollableScrollPhysics(),
                                      // 【留白恢复】大幅增加上下基础边距，让滚动时有舒适的缓冲
                                      padding: const EdgeInsets.fromLTRB(0, 24, 0, 86),
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
                                            title: '重要经历',
                                            records: achievements,
                                          ),
                                        if (events.isNotEmpty)
                                          _GameStyleJourneySection(
                                            title: '事件轨迹',
                                            records: events,
                                          ),
                                        if (milestones.isNotEmpty)
                                          _GameStyleJourneySection(
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
                    fontSize: 18, // 稍微缩小标题，更显精致
                    height: 1,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2.0,
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
  });

  final String title;
  final String summary;
  final int achievements;
  final int events;
  final int milestones;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // 【修复 1】去掉 bottom 的 24 留白，彻底消除边距叠加
      padding: const EdgeInsets.only(top: 8, bottom: 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: const TextStyle(
              color: _journeyText,
              fontSize: 25,
              height: 1.1,
              fontWeight: FontWeight.w800,
              letterSpacing: .5,
            ),
          ),
          const SizedBox(height: 20),
          if (summary.isNotEmpty) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(6), 
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(.03),
                    border: Border(
                      left: const BorderSide(color: _journeyAccent, width: 2.0),
                      top: BorderSide(color: Colors.white.withOpacity(.04), width: 1),
                      right: BorderSide(color: Colors.white.withOpacity(.04), width: 1),
                      bottom: BorderSide(color: Colors.white.withOpacity(.04), width: 1),
                    ),
                  ),
                  child: Text(
                    summary,
                    style: const TextStyle(
                      color: _journeyTextSoft,
                      fontSize: 12.0, 
                      height: 1.75, 
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: <Widget>[
              _JourneyCountText(label: '经历', value: achievements),
              _JourneyCountText(label: '事件', value: events),
              _JourneyCountText(label: '节点', value: milestones),
            ],
          ),
          const SizedBox(height: 24), 
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3), 
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Text(
        '$label  $value',
        style: const TextStyle(
          color: _journeyTextSoft,
          fontSize: 9.5, 
          fontWeight: FontWeight.w700,
          letterSpacing: .25,
        ),
      ),
    );
  }
}

class _GameStyleJourneySection extends StatelessWidget {
  const _GameStyleJourneySection({
    required this.title,
    required this.records,
  });

  final String title;
  final List<_GameStyleJourneyRecord> records;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // 【修复 2】间距从 36 收缩到 24，刚好与上一条分割线的上面形成 24px 的完美对称
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                title,
                style: const TextStyle(
                  color: _journeyText,
                  fontSize: 14.5, 
                  fontWeight: FontWeight.w800,
                  letterSpacing: .2,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(.08),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${records.length}',
                  style: const TextStyle(
                    color: _journeyMuted,
                    fontSize: 9.0,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
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
      // 【修复 3】把最后一个元素的 bottom 强制设为 0，防止把大空白带给下一个章节
      padding: const EdgeInsets.only(bottom: 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 38, 
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    number,
                    style: const TextStyle(
                      color: _journeyAccent, 
                      fontSize: 10.0,
                      fontWeight: FontWeight.w900,
                      letterSpacing: .5,
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
                      color: _journeyTextSoft, 
                      fontSize: 9.5, 
                      fontWeight: FontWeight.w700,
                      letterSpacing: .3,
                    ),
                  ),
                  const SizedBox(height: 6), 
                ],
                Text(
                  record.title,
                  style: const TextStyle(
                    color: _journeyText,
                    fontSize: 13.0, 
                    height: 1.45,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (record.hasDetail) ...<Widget>[
                  const SizedBox(height: 8), 
                  Text(
                    record.detail,
                    style: const TextStyle(
                      color: _journeyMuted,
                      fontSize: 11.5, 
                      height: 1.75, 
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
                if (!last) ...<Widget>[
                  const SizedBox(height: 22),
                  Container(height: 1, color: _journeyLine),
                  const SizedBox(height: 22),
                ] else ...<Widget>[
                  // 最后一个条目只给一丢丢间距收尾
                  const SizedBox(height: 12),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}