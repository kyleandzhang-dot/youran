part of '../novel_sheets.dart';

// ============================================================================
// 经历 / 回溯页
// 页面入口 / 对外入口：
//   - showNovelJourneySheet(...)
//   - NovelJourneyTab
//   - showNovelRevertDialog(...)
// 其余以下划线 `_` 开头的类型/方法均为该页面内部实现或共享私有实现。
// ============================================================================

const Color _journeyInk = Color(0xFF090E1A);
const Color _journeyInkSoft = Color(0xFF111A2C);
const Color _journeyBlue = Color(0xFF506FEF);
const Color _journeyGold = Color(0xFFC9B778);
const Color _journeyGoldSoft = Color(0xFF86794D);
const Color _journeyText = Color(0xFFF2F0E8);
const Color _journeyTextSoft = Color(0xFFB9C0D0);
const Color _journeyMuted = Color(0xFF737C91);
const Color _journeyLine = Color(0x1FFFFFFF);

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
                      side: BorderSide(color: Colors.white.withOpacity(.12)),
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
                      backgroundColor: _journeyBlue, // 统一使用主题蓝
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
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

  // 构建微圆角磨砂玻璃容器
  Widget _buildGlassPanel({required Widget child, EdgeInsetsGeometry? padding}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: _journeyInkSoft.withOpacity(0.55),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Colors.white.withOpacity(0.08),
              width: 0.8,
            ),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x26000000),
                blurRadius: 16,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
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
                        color: _journeyBlue, // 空状态符号改为蓝色
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
            // 【关键修改点】将深邃蓝渐变背景移到最外层，包裹住 Header 和内容
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(-.45, -.35),
                radius: 1.15,
                colors: <Color>[
                  Color(0xFF111A2C),
                  _journeyInk,
                  Color(0xFF070B15),
                ],
                stops: <double>[0, .58, 1],
              ),
            ),
            child: Column(
              children: <Widget>[
                LayoutBuilder(
                  builder: (context, constraints) {
                    final desktopMode = widget.controller.desktopMode;
                    final leftInset = desktopMode ? 46.0 : 10.0;
                    final rightInset = desktopMode ? 54.0 : 12.0;
                    final contentMaxWidth = desktopMode ? 1440.0 : 560.0;
                    final topInset = desktopMode ? 14.0 : 4.0;

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
                      // 与角色页使用同一套真正的页面主体边距。
                      // 模式只认共享 desktopMode，不再根据当前窗口宽度偷偷切换。
                      final desktopMode = widget.controller.desktopMode;
                      final leftInset = desktopMode ? 46.0 : 10.0;
                      final rightInset = desktopMode ? 54.0 : 12.0;
                      final contentMaxWidth = desktopMode ? 1440.0 : 560.0;

                      // 电脑端：双栏布局，宽屏真正利用空间，但仍和角色页主体对齐。
                      if (desktopMode) {
                        return Center(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(maxWidth: contentMaxWidth),
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(
                                leftInset,
                                12,
                                rightInset,
                                24,
                              ),
                              child: RefreshIndicator(
                                onRefresh: _refresh,
                                color: _journeyGold,
                                backgroundColor: _journeyInkSoft,
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // 左侧栏：故事梗概卡片
                                    Expanded(
                                      flex: 4,
                                      child: _buildGlassPanel(
                                        padding: const EdgeInsets.fromLTRB(26, 26, 26, 32),
                                        child: _JourneyStoryOpening(
                                          title: title.isEmpty ? '你的旅程' : title,
                                          summary: summary,
                                          achievements: achievements.length,
                                          events: events.length,
                                          milestones: milestones.length,
                                          isDesktop: true,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 24),
                                    // 右侧栏：经历与事件流水
                                    Expanded(
                                      flex: 7,
                                      child: _buildGlassPanel(
                                        child: hasContent
                                            ? ListView(
                                                physics: const AlwaysScrollableScrollPhysics(),
                                                padding: const EdgeInsets.fromLTRB(32, 12, 32, 46),
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
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      }

                      // 手机端：和角色页一致的 10 / 12 页面边距与 560 最大宽度。
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
                              color: _journeyGold,
                              backgroundColor: _journeyInkSoft,
                              child: hasContent
                                  ? ListView(
                                      physics: const AlwaysScrollableScrollPhysics(),
                                      // 外层已经控制左右页边距，这里不再重复吃掉横向空间。
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
    this.isDesktop = false,
  });

  final String title;
  final String summary;
  final int achievements;
  final int events;
  final int milestones;
  final bool isDesktop;

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
              color: _journeyGold, // 使用点缀金
              fontSize: 8.5,
              fontWeight: FontWeight.w800,
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
              fontWeight: FontWeight.w800,
              letterSpacing: .5,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: BoxDecoration(
              color: isDesktop ? Colors.transparent : _journeyInkSoft.withOpacity(.6),
              borderRadius: isDesktop ? null : BorderRadius.circular(4),
              border: isDesktop
                  ? const Border(left: BorderSide(color: _journeyBlue, width: 2.5))
                  : Border(
                      left: const BorderSide(color: _journeyBlue, width: 2.5),
                      top: BorderSide(color: Colors.white.withOpacity(.05), width: .8),
                      right: BorderSide(color: Colors.white.withOpacity(.05), width: .8),
                      bottom: BorderSide(color: Colors.white.withOpacity(.05), width: .8),
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
          const SizedBox(height: 20),
          Wrap(
            spacing: 15,
            runSpacing: 6,
            children: <Widget>[
              _JourneyCountText(label: '经历', value: achievements),
              _JourneyCountText(label: '事件', value: events),
              _JourneyCountText(label: '节点', value: milestones),
            ],
          ),
          if (!isDesktop) ...[
            const SizedBox(height: 12),
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
        color: _journeyBlue.withOpacity(.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: _journeyBlue.withOpacity(.2)),
      ),
      child: Text(
        '$label  $value',
        style: const TextStyle(
          color: _journeyText,
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
              color: _journeyGold, // 小标题英文改用金色
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
          // 左侧：序号与微型时间线设计
          SizedBox(
            width: 36,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    number,
                    style: const TextStyle(
                      color: _journeyBlue, // 序号蓝调
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
                      color: _journeyGoldSoft,
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
                      color: _journeyTextSoft,
                      fontSize: 12.0,
                      height: 1.75,
                      fontWeight: FontWeight.w500,
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