part of '../novel_widgets.dart';

// Novel Widgets · 核心剧情阅读器
// 对外入口：NovelDialogPanel
// 内部实现：旁白、对白、混合正文、逐字显示、说话者信息、推进提示。

class NovelDialogPanel extends StatefulWidget {
  const NovelDialogPanel({
    super.key,
    required this.controller,
    required this.textController,
    required this.focusNode,
    required this.onSend,
    required this.onContinue,
    required this.onForceContinue,
    required this.onOpenChoices,
    required this.onOpenInventory,
    required this.onOpenCharacters,
    required this.onOpenJourney,
    required this.onRevert,
    this.onOpenPortrait,
    this.targetActorName = '',
    this.targetActorAvatarUrl = '',
    this.targetActorPlaceholder = '',
    this.onClearTargetActor,
    this.active = true,
    this.bottomReservedHeight = 0,
    this.isExploring = false,
  });

  final NovelGameController controller;
  final TextEditingController textController;
  final FocusNode focusNode;
  final ValueChanged<String> onSend;
  final VoidCallback onContinue;
  final VoidCallback onForceContinue;
  final VoidCallback onOpenChoices;
  final VoidCallback onOpenInventory;
  final VoidCallback onOpenCharacters;
  final VoidCallback onOpenJourney;
  final VoidCallback onRevert;
  final VoidCallback? onOpenPortrait;
  final String targetActorName;
  final String targetActorAvatarUrl;
  final String targetActorPlaceholder;
  final VoidCallback? onClearTargetActor;

  /// 剧情页底部由外层占用的固定高度。
  /// 例如主页内嵌的走路探索区会占据屏幕底部，正文、选择框与输入栏
  /// 统一基于这个高度上移，而不是各自硬编码偏移。
  final double bottomReservedHeight;

  /// 剧情页虽然会被右侧一级 Tab 盖住，但 State 仍然保留。
  /// active=false 时必须暂停本地逐字 Timer，并停止打字音，避免后台继续“打字”。
  final bool active;

  /// 玩家已拨动摇杆进入探索模式：正文、立绘、空白推进手势全部隐藏/让开，
  /// 只保留底部输入框 (_NovelDialogFooter) 常驻可用。
  final bool isExploring;

  @override
  State<NovelDialogPanel> createState() => _NovelDialogPanelState();
}

enum _NovelLineMode { narration, npc, protagonist }

// 混合句不再在同一个舞台里按逐字进度切换“正文 / 对白”。
// 前置正文、角色对白、后置正文各自成为真正的阅读子页；横屏长正文还能继续细分。
enum _NovelMixedPageKind { leadingNarration, dialogue, trailingNarration }

class _NovelMixedReaderPage {
  const _NovelMixedReaderPage({required this.kind, required this.text});

  final _NovelMixedPageKind kind;
  final String text;
}

class _NovelStageActorVisual {
  const _NovelStageActorVisual({
    required this.id,
    required this.name,
    required this.portraitUrl,
    required this.active,
    required this.selected,
    required this.protagonist,
  });

  final String id;
  final String name;
  final String portraitUrl;
  final bool active;
  final bool selected;
  final bool protagonist;

  _NovelStageActorVisual copyWith({
    String? portraitUrl,
    bool? active,
    bool? selected,
  }) {
    return _NovelStageActorVisual(
      id: id,
      name: name,
      portraitUrl: portraitUrl ?? this.portraitUrl,
      active: active ?? this.active,
      selected: selected ?? this.selected,
      protagonist: protagonist,
    );
  }
}

class _NovelPresenceStage extends StatelessWidget {
  const _NovelPresenceStage({
    required this.actors,
    required this.stageSize,
    required this.reservedBottom,
    required this.wideDialogueLayout,
    required this.shortWide,
    required this.compact,
  });

  final List<_NovelStageActorVisual> actors;
  final Size stageSize;
  final double reservedBottom;
  final bool wideDialogueLayout;
  final bool shortWide;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (actors.isEmpty) return const SizedBox.shrink();

    final singleActor = actors.length == 1;
    late final double portraitWidth;
    late final double portraitHeightRatio;
    late final double sinkRatio;

    if (singleActor) {
      if (wideDialogueLayout) {
        final widthBased =
            (stageSize.width * .55).clamp(550.0, 960.0).toDouble();
        final heightBased =
            (stageSize.height * 1.05).clamp(500.0, 1000.0).toDouble();
        portraitWidth = math.min(widthBased, heightBased);
        portraitHeightRatio = 1.25;
        sinkRatio = .45;
      } else if (shortWide) {
        portraitWidth = math
            .min(stageSize.width * .55, stageSize.height * 1.22)
            .clamp(330.0, 520.0)
            .toDouble();
        portraitHeightRatio = 1.25;
        sinkRatio = .45;
      } else {
        const double minStage = 320.0;
        const double maxStage = 600.0;
        final t = ((stageSize.width - minStage) / (maxStage - minStage))
            .clamp(0.0, 1.0);
        final widthRatio = lerpDouble(1.00, .82, t)!;
        final minPortraitWidth = lerpDouble(350.0, 420.0, t)!;
        final maxPortraitWidth = lerpDouble(500.0, 600.0, t)!;
        portraitWidth = (stageSize.width * widthRatio)
            .clamp(minPortraitWidth, maxPortraitWidth)
            .toDouble();
        portraitHeightRatio = 1.22;
        sinkRatio = lerpDouble(.24, .16, t)!;
      }
    } else if (wideDialogueLayout) {
      portraitWidth = math
          .min(stageSize.width * .36, stageSize.height * .88)
          .clamp(330.0, 560.0)
          .toDouble();
      portraitHeightRatio = 1.25;
      sinkRatio = .43;
    } else if (shortWide) {
      portraitWidth = math
          .min(stageSize.width * .36, stageSize.height * 1.08)
          .clamp(230.0, 380.0)
          .toDouble();
      portraitHeightRatio = 1.25;
      sinkRatio = .44;
    } else {
      portraitWidth = (stageSize.width * .76).clamp(270.0, 410.0).toDouble();
      portraitHeightRatio = 1.22;
      sinkRatio = .20;
    }

    final portraitHeight = portraitWidth * portraitHeightRatio;
    final sinkOffset = -(portraitHeight * sinkRatio);
    final centers = switch (actors.length) {
      1 => <double>[actors.first.protagonist ? .72 : .24],
      2 => <double>[.24, .72],
      _ => <double>[.13, .50, .84],
    };

    Widget actorWidget(_NovelStageActorVisual actor, int index) {
      final focused = actor.active;
      final selected = actor.selected;
      final opacity = focused ? 1.0 : (selected ? .82 : .58);
      final scale = focused ? 1.035 : (selected ? .985 : .94);
      final verticalOffset = focused ? -0.018 : (selected ? 0.0 : .018);
      final dimStrength = focused ? 0.0 : (selected ? .08 : .22);
      final centerX = centers[index.clamp(0, centers.length - 1)];
      final left = stageSize.width * centerX - portraitWidth / 2;

      return Positioned(
        key: ValueKey<String>('presence-position|${actor.id}|${actor.portraitUrl}'),
        left: left,
        bottom: reservedBottom + sinkOffset,
        width: portraitWidth,
        height: portraitHeight,
        child: IgnorePointer(
          child: AnimatedSlide(
            offset: Offset(0, verticalOffset),
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            child: AnimatedScale(
              scale: scale,
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              alignment: Alignment.bottomCenter,
              child: AnimatedOpacity(
                opacity: opacity,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                child: ColorFiltered(
                  colorFilter: ColorFilter.mode(
                    Colors.black.withOpacity(dimStrength),
                    BlendMode.srcATop,
                  ),
                  child: _NovelPortraitMotion(
                    key: ValueKey<String>(
                      'presence-motion|${actor.id}|${actor.portraitUrl}',
                    ),
                    speaking: focused,
                    alignRight: centerX >= .5,
                    child: _StagePortraitArtwork(
                      url: actor.portraitUrl,
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    final indexed = <({int index, _NovelStageActorVisual actor})>[
      for (var i = 0; i < actors.length; i++) (index: i, actor: actors[i]),
    ]..sort((a, b) {
        final aDepth = a.actor.active ? 2 : (a.actor.selected ? 1 : 0);
        final bDepth = b.actor.active ? 2 : (b.actor.selected ? 1 : 0);
        return aDepth.compareTo(bDepth);
      });

    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        for (final entry in indexed) actorWidget(entry.actor, entry.index),
      ],
    );
  }
}

List<String> _novelPaginateNarrationText(String text) {
  final source = text
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .trim();
  if (source.isEmpty) return const <String>[];

  const softLimit = 112;
  const hardLimit = 148;
  const minFill = 72;

  List<String> splitStrongSentences(String paragraph) {
    final result = <String>[];
    final buffer = StringBuffer();
    const strongStops = '。！？!?';
    for (final rune in paragraph.runes) {
      final char = String.fromCharCode(rune);
      buffer.write(char);
      if (strongStops.contains(char)) {
        final value = buffer.toString().trim();
        if (value.isNotEmpty) result.add(value);
        buffer.clear();
      }
    }
    final tail = buffer.toString().trim();
    if (tail.isNotEmpty) result.add(tail);
    return result.isEmpty ? <String>[paragraph.trim()] : result;
  }

  List<String> splitLongUnit(String value) {
    final runes = value.runes.toList(growable: false);
    if (runes.length <= hardLimit) return <String>[value];

    final result = <String>[];
    var start = 0;
    const weakStops = '，、；：,;:';
    while (start < runes.length) {
      final remaining = runes.length - start;
      if (remaining <= hardLimit) {
        result.add(String.fromCharCodes(runes.sublist(start)).trim());
        break;
      }

      var cut = start + hardLimit;
      final earliest = start + (hardLimit * .58).round();
      for (var i = cut - 1; i >= earliest; i--) {
        final char = String.fromCharCode(runes[i]);
        if (weakStops.contains(char)) {
          cut = i + 1;
          break;
        }
      }
      result.add(String.fromCharCodes(runes.sublist(start, cut)).trim());
      start = cut;
    }
    return result.where((value) => value.isNotEmpty).toList(growable: false);
  }

  final paragraphs = source
      .split(RegExp(r'\n+'))
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toList(growable: false);

  final pages = <String>[];
  final current = StringBuffer();
  var currentRunes = 0;
  var paragraphsOnPage = 0;

  void flushPage() {
    final value = current.toString().trim();
    if (value.isNotEmpty) pages.add(value);
    current.clear();
    currentRunes = 0;
    paragraphsOnPage = 0;
  }

  for (final paragraph in paragraphs) {
    final units = <String>[];
    for (final sentence in splitStrongSentences(paragraph)) {
      units.addAll(splitLongUnit(sentence));
    }

    var paragraphStartedOnCurrentPage = false;
    for (final unit in units) {
      if (unit.isEmpty) continue;
      final unitRunes = unit.runes.length;
      final startsNewParagraph = !paragraphStartedOnCurrentPage;
      final separator = current.isNotEmpty && startsNewParagraph ? '\n\n' : '';
      final projected = currentRunes + separator.runes.length + unitRunes;

      final paragraphLimitReached = current.isNotEmpty &&
          startsNewParagraph &&
          paragraphsOnPage >= 2 &&
          currentRunes >= minFill;
      final lengthLimitReached = current.isNotEmpty &&
          projected > softLimit &&
          (currentRunes >= minFill || projected > hardLimit);

      if (paragraphLimitReached || lengthLimitReached) {
        flushPage();
        paragraphStartedOnCurrentPage = false;
      }

      if (!paragraphStartedOnCurrentPage) {
        if (current.isNotEmpty) {
          current.write('\n\n');
          currentRunes += 2;
        }
        paragraphsOnPage++;
        paragraphStartedOnCurrentPage = true;
      }
      current.write(unit);
      currentRunes += unitRunes;
    }
  }

  flushPage();
  return pages.isEmpty ? <String>[source] : pages;
}

bool _novelSentenceLooksLikeStandaloneNarration(NovelSentence sentence) {
  final type = sentence.type.toLowerCase().trim();
  return !sentence.hasMixedContent &&
      !sentence.isProtagonist &&
      sentence.speakerName.trim().isEmpty &&
      (sentence.isNarration || type == 'narration' || type == 'action');
}

List<_NovelMixedReaderPage> _novelMixedReaderPages(
  NovelSentence? sentence, {
  bool paginateNarration = false,
}) {
  if (sentence == null || !sentence.hasMixedContent) {
    return const <_NovelMixedReaderPage>[];
  }

  final pages = <_NovelMixedReaderPage>[];
  final leading = _sanitizeNovelStreamingText(sentence.leadingNarration);
  final dialogue = _sanitizeNovelStreamingText(sentence.text);
  final trailing = _sanitizeNovelStreamingText(sentence.trailingNarration);

  void addNarrationPages(_NovelMixedPageKind kind, String text) {
    if (_novelVisibleNarrationText(text).trim().isEmpty) return;
    final narrationPages = paginateNarration
        ? _novelPaginateNarrationText(text)
        : <String>[text];
    for (final page in narrationPages) {
      if (page.trim().isEmpty) continue;
      pages.add(_NovelMixedReaderPage(kind: kind, text: page));
    }
  }

  addNarrationPages(_NovelMixedPageKind.leadingNarration, leading);
  if (dialogue.trim().isNotEmpty) {
    pages.add(_NovelMixedReaderPage(
      kind: _NovelMixedPageKind.dialogue,
      text: dialogue,
    ));
  }
  addNarrationPages(_NovelMixedPageKind.trailingNarration, trailing);

  return pages;
}

int _novelReaderPageCount(
  NovelSentence sentence, {
  bool paginateNarration = false,
}) {
  final mixedPages = _novelMixedReaderPages(
    sentence,
    paginateNarration: paginateNarration,
  );
  if (mixedPages.isNotEmpty) return mixedPages.length;

  if (paginateNarration &&
      _novelSentenceLooksLikeStandaloneNarration(sentence)) {
    final text = _sanitizeNovelSentenceReaderText(sentence);
    final pages = _novelPaginateNarrationText(text);
    if (pages.isNotEmpty) return pages.length;
  }
  return 1;
}

class _NovelDialogPanelState extends State<NovelDialogPanel>
    with SingleTickerProviderStateMixin {
  Timer? _revealTimer;
  int _visibleLength = 0;
  String _lastIdentity = '';
  String _lastSentenceIdentity = '';
  String _lastRevealMessageKey = '';
  int _lastRevealSentenceIndex = -1;
  int _mixedPageIndex = 0;
  int _narrationPageIndex = 0;
  bool _compactNarrationPaging = false;
  bool _enterPreviousSentenceAtLastReaderPage = false;
  String _skippedRevealIdentity = '';
  String _lastFullText = '';
  List<int> _lastFullRunes = const <int>[];
  late final ValueNotifier<String> _displayTextNotifier;
  bool _revealing = false;
  bool _typingSoundForReveal = false;
  final Set<String> _typingSoundVisited = <String>{};
  bool _showSwipeHint = true;
  Timer? _swipeHintTimer;
  double _horizontalDragDistance = 0;
  double _swipeVisualOffset = 0;
  bool _swipeTransitioning = false;
  bool _animationsDisabled = false;
  int _lastTextSpeedCps = -1;
  double _measuredInputBarHeight = 0;
  late final AnimationController _swipeController;

  NovelGameController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _displayTextNotifier = ValueNotifier<String>('');
    widget.textController.addListener(_handleInputTextChanged);
    _lastTextSpeedCps = widget.controller.settings.textSpeedCps;
    widget.controller.settings.addListener(_handleRevealSettingsChanged);
    _swipeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _syncReveal(force: true);
    _settleCommittedHistoryOnMount();
    _swipeHintTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && _showSwipeHint) {
        setState(() => _showSwipeHint = false);
      }
    });
  }

  @override
  void didUpdateWidget(covariant NovelDialogPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller.settings != widget.controller.settings) {
      oldWidget.controller.settings.removeListener(_handleRevealSettingsChanged);
      _lastTextSpeedCps = widget.controller.settings.textSpeedCps;
      widget.controller.settings.addListener(_handleRevealSettingsChanged);
    }
    if (oldWidget.textController != widget.textController) {
      oldWidget.textController.removeListener(_handleInputTextChanged);
      widget.textController.addListener(_handleInputTextChanged);
    }
    _syncReveal();

    final targetActorClosed = oldWidget.targetActorName.trim().isNotEmpty &&
        widget.targetActorName.trim().isEmpty;
    if (targetActorClosed) {
      _swipeController.stop(canceled: false);
      _horizontalDragDistance = 0;
      _swipeVisualOffset = 0;
      _swipeTransitioning = false;
      if (widget.focusNode.hasFocus) {
        widget.focusNode.unfocus();
      }
    }

    if (oldWidget.active != widget.active) {
      if (widget.active) {
        _resumeRevealIfNeeded();
      } else {
        _pauseRevealForHiddenStory();
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final media = MediaQuery.of(context);
    final nextAnimationsDisabled = media.disableAnimations;
    final nextCompactNarrationPaging = NovelViewportMetrics.fromMediaQuery(
      media,
      desktopMode: controller.desktopMode,
    ).shortWide;

    final animationsChanged =
        nextAnimationsDisabled != _animationsDisabled;
    final pagingChanged =
        nextCompactNarrationPaging != _compactNarrationPaging;

    _animationsDisabled = nextAnimationsDisabled;
    _compactNarrationPaging = nextCompactNarrationPaging;

    if (animationsChanged || pagingChanged) {
      _syncReveal(force: animationsChanged);
    }
  }

  void _handleInputTextChanged() {
    if (mounted) setState(() {});
  }

  bool get _revealInstantly =>
      _animationsDisabled || controller.settings.textSpeedCps <= 0;

  bool get _mountedFromCommittedHistory {
    if (controller.isGenerating) return false;
    final message = controller.lastAssistantMessage;
    if (message == null) return false;
    final status = message.status.trim().toLowerCase();
    return !const <String>{
      'sending',
      'streaming',
      'pending',
      'generating',
    }.contains(status);
  }

  void _settleCommittedHistoryOnMount() {
    if (!_mountedFromCommittedHistory) return;
    _revealTimer?.cancel();
    _revealTimer = null;
    _visibleLength = _fullRuneLength;
    _publishVisibleText();
    _revealing = false;
    _typingSoundForReveal = false;
    controller.setReaderRevealing(false, notify: false);
  }

  void _handleRevealSettingsChanged() {
    if (!mounted) return;
    final nextSpeed = controller.settings.textSpeedCps;
    if (nextSpeed == _lastTextSpeedCps) return;
    _lastTextSpeedCps = nextSpeed;
    if (_revealInstantly) {
      _revealTimer?.cancel();
      _revealTimer = null;
      _visibleLength = _fullRuneLength;
      _publishVisibleText();
      _typingSoundForReveal = false;
      if (_revealing && mounted) setState(() => _revealing = false);
      unawaited(controller.bgm.stopTypingSound());
      return;
    }
    if (_revealing) _scheduleReveal();
  }

  void _handleInputLayoutHeightChanged(double height) {
    final safeHeight = height.isFinite ? math.max(0.0, height) : 0.0;
    if ((_measuredInputBarHeight - safeHeight).abs() < .5) return;
    if (!mounted) return;
    setState(() => _measuredInputBarHeight = safeHeight);
  }

  double _adaptiveFooterHeight({
    required double availableWidth,
    required bool compact,
    required bool shortViewport,
    required bool choicesVisible,
    required bool inputContextVisible,
  }) {
    final base = shortViewport ? 46.0 : (compact ? 52.0 : 54.0);
    final contextReserve = inputContextVisible
        ? (shortViewport ? 30.0 : (compact ? 33.0 : 34.0))
        : 0.0;
    final text = widget.textController.text;
    if (text.isEmpty) return base + contextReserve;

    var textWidth = math.min(availableWidth, 720.0) - 124.0;
    if (!choicesVisible) textWidth -= 56.0;
    if (controller.luckyCardCount > 0) textWidth -= 50.0;
    textWidth = textWidth.clamp(150.0, 560.0).toDouble();

    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(fontSize: 14, height: 1.35),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 5,
    )..layout(maxWidth: textWidth);

    final lines = painter.computeLineMetrics().length.clamp(1, 5);
    return base +
        contextReserve +
        (lines - 1) * (shortViewport ? 17.0 : (compact ? 19.0 : 20.0));
  }

  String get _fullText => _lastFullText;

  int get _fullRuneLength => _lastFullRunes.length;

  void _publishVisibleText() {
    final safeLength = _visibleLength.clamp(0, _fullRuneLength);
    final next = safeLength >= _fullRuneLength
        ? _fullText
        : String.fromCharCodes(_lastFullRunes.take(safeLength));
    if (_displayTextNotifier.value != next) {
      _displayTextNotifier.value = next;
    }
  }

  void _pauseRevealForHiddenStory() {
    _revealTimer?.cancel();
    _revealTimer = null;
    _revealing = false;
    controller.setReaderRevealing(false, notify: false);
    unawaited(controller.bgm.stopTypingSound());
  }

  void _resumeRevealIfNeeded() {
    if (!widget.active ||
        _revealInstantly ||
        _skippedRevealIdentity == _lastIdentity ||
        _visibleLength >= _fullRuneLength) {
      return;
    }
    _revealing = true;
    _scheduleReveal();
  }

  String get _currentAssistantMessageKey {
    final message = controller.lastAssistantMessage;
    final timestamp = message?.timestamp ?? 0;
    if (timestamp > 0) return 'timestamp:$timestamp';
    final id = message?.id.trim() ?? '';
    if (id.isNotEmpty) return id;
    return 'assistant-message';
  }

  List<_NovelMixedReaderPage> _mixedReaderPagesForCurrentSentence() {
    return _novelMixedReaderPages(
      controller.currentSentence,
      paginateNarration: _compactNarrationPaging,
    );
  }

  int _safeMixedPageIndex(List<_NovelMixedReaderPage> pages) {
    if (pages.isEmpty) return 0;
    return _mixedPageIndex.clamp(0, pages.length - 1).toInt();
  }

  bool _currentSentenceUsesNarrationPaging(NovelSentence? sentence) {
    if (!_compactNarrationPaging ||
        sentence == null ||
        sentence.hasMixedContent) {
      return false;
    }

    final controllerSpeaker = controller.currentSpeakerName.trim();
    final sentenceSpeaker = sentence.speakerName.trim();
    final character = controller.currentSpeakerCharacter;
    final type = sentence.type.toLowerCase().trim();
    final hasSpeaker =
        controllerSpeaker.isNotEmpty || sentenceSpeaker.isNotEmpty || character != null;

    return !hasSpeaker &&
        (sentence.isNarration || type == 'narration' || type == 'action');
  }

  List<String> _narrationPagesForCurrentSentence() {
    final sentence = controller.currentSentence;
    final full = _sanitizeNovelSentenceReaderText(sentence);
    if (!_currentSentenceUsesNarrationPaging(sentence)) {
      return <String>[full];
    }
    final pages = _novelPaginateNarrationText(full);
    return pages.isEmpty ? <String>[full] : pages;
  }

  int _safeNarrationPageIndex(List<String> pages) {
    if (pages.isEmpty) return 0;
    return _narrationPageIndex.clamp(0, pages.length - 1).toInt();
  }

  bool get _hasNextNarrationReaderPage {
    final sentence = controller.currentSentence;
    if (!_currentSentenceUsesNarrationPaging(sentence)) return false;
    final pages = _narrationPagesForCurrentSentence();
    return pages.length > 1 &&
        _safeNarrationPageIndex(pages) < pages.length - 1;
  }

  bool get _hasPreviousNarrationReaderPage {
    final sentence = controller.currentSentence;
    if (!_currentSentenceUsesNarrationPaging(sentence)) return false;
    final pages = _narrationPagesForCurrentSentence();
    return pages.length > 1 && _safeNarrationPageIndex(pages) > 0;
  }

  void _setNarrationReaderPage(int nextIndex) {
    final pages = _narrationPagesForCurrentSentence();
    if (pages.length <= 1) return;
    final target = nextIndex.clamp(0, pages.length - 1).toInt();
    if (target == _safeNarrationPageIndex(pages)) return;

    if (mounted) {
      setState(() => _narrationPageIndex = target);
    } else {
      _narrationPageIndex = target;
    }
    _syncReveal(force: true);
  }

  bool get _hasNextMixedReaderPage {
    final pages = _mixedReaderPagesForCurrentSentence();
    return pages.isNotEmpty && _safeMixedPageIndex(pages) < pages.length - 1;
  }

  bool get _hasPreviousMixedReaderPage {
    final pages = _mixedReaderPagesForCurrentSentence();
    return pages.isNotEmpty && _safeMixedPageIndex(pages) > 0;
  }

  bool get _canMoveNextReaderPage =>
      _hasNextMixedReaderPage ||
      _hasNextNarrationReaderPage ||
      controller.hasNext;

  bool get _canMovePreviousReaderPage =>
      _hasPreviousMixedReaderPage ||
      _hasPreviousNarrationReaderPage ||
      controller.hasPrevious;

  void _setMixedReaderPage(int nextIndex) {
    final pages = _mixedReaderPagesForCurrentSentence();
    if (pages.isEmpty) return;
    final target = nextIndex.clamp(0, pages.length - 1).toInt();
    if (target == _safeMixedPageIndex(pages)) return;

    if (mounted) {
      setState(() => _mixedPageIndex = target);
    } else {
      _mixedPageIndex = target;
    }
    _syncReveal(force: true);
  }

  int? _preservedRevealLengthForStructuralRefresh({
    required String messageKey,
    required int sentenceIndex,
    required String nextFull,
  }) {
    if (_lastIdentity.isEmpty ||
        _lastRevealMessageKey != messageKey ||
        _lastRevealSentenceIndex != sentenceIndex ||
        nextFull.isEmpty) {
      return null;
    }

    final previousFull = _lastFullText;
    final visibleText = _displayTextNotifier.value;
    final nextLength = nextFull.runes.length;

    if (previousFull == nextFull) {
      return _visibleLength.clamp(0, nextLength).toInt();
    }

    if (visibleText.isNotEmpty && nextFull.startsWith(visibleText)) {
      return visibleText.runes.length.clamp(0, nextLength).toInt();
    }
    if (visibleText.isNotEmpty && visibleText.startsWith(nextFull)) {
      return nextLength;
    }
    return null;
  }

  void _syncReveal({bool force = false}) {
    final sentence = controller.currentSentence;
    final messageKey = _currentAssistantMessageKey;

    final sentenceIdentity =
        '$messageKey|${controller.currentSentenceIndex}|${sentence?.speakerName ?? ''}|${sentence?.type ?? ''}';
    final mixedPages = _novelMixedReaderPages(
      sentence,
      paginateNarration: _compactNarrationPaging,
    );
    final usesNarrationPaging =
        mixedPages.isEmpty && _currentSentenceUsesNarrationPaging(sentence);
    final narrationPages = usesNarrationPaging
        ? _narrationPagesForCurrentSentence()
        : <String>[];

    if (sentenceIdentity != _lastSentenceIdentity) {
      _lastSentenceIdentity = sentenceIdentity;
      if (_enterPreviousSentenceAtLastReaderPage) {
        if (mixedPages.isNotEmpty) {
          _mixedPageIndex = mixedPages.length - 1;
          _narrationPageIndex = 0;
        } else if (usesNarrationPaging && narrationPages.isNotEmpty) {
          _mixedPageIndex = 0;
          _narrationPageIndex = narrationPages.length - 1;
        } else {
          _mixedPageIndex = 0;
          _narrationPageIndex = 0;
        }
      } else {
        _mixedPageIndex = 0;
        _narrationPageIndex = 0;
      }
      _enterPreviousSentenceAtLastReaderPage = false;
    } else if (mixedPages.isNotEmpty) {
      _mixedPageIndex = _safeMixedPageIndex(mixedPages);
      _narrationPageIndex = 0;
    } else {
      _mixedPageIndex = 0;
      _narrationPageIndex = usesNarrationPaging
          ? _safeNarrationPageIndex(narrationPages)
          : 0;
    }

    final activeMixedPage = mixedPages.isEmpty
        ? null
        : mixedPages[_safeMixedPageIndex(mixedPages)];
    final activeNarrationPage = usesNarrationPaging && narrationPages.isNotEmpty
        ? narrationPages[_safeNarrationPageIndex(narrationPages)]
        : null;

    final full = sentence?.hasMixedContent == true
        ? (activeMixedPage?.text ?? '')
        : (activeNarrationPage ?? _sanitizeNovelSentenceReaderText(sentence));
    final pageToken = activeMixedPage != null
        ? '${activeMixedPage.kind.name}:$_mixedPageIndex'
        : activeNarrationPage != null
            ? 'narration:$_narrationPageIndex'
            : (sentence?.hasMixedContent == true ? 'mixed-empty' : 'single');
    final identity = '$sentenceIdentity|$pageToken';

    final structuralPreservedLength = !force && identity != _lastIdentity
        ? _preservedRevealLengthForStructuralRefresh(
            messageKey: messageKey,
            sentenceIndex: controller.currentSentenceIndex,
            nextFull: full,
          )
        : null;

    if (force || identity != _lastIdentity) {
      final keepTypingSound = _typingSoundForReveal;
      _lastIdentity = identity;
      _lastFullText = full;
      _lastFullRunes = full.runes.toList(growable: false);
      _lastRevealMessageKey = messageKey;
      _lastRevealSentenceIndex = controller.currentSentenceIndex;
      _revealTimer?.cancel();
      _revealTimer = null;

      if (structuralPreservedLength != null) {
        _visibleLength = structuralPreservedLength
            .clamp(0, _fullRuneLength)
            .toInt();
        _publishVisibleText();
        _typingSoundForReveal = keepTypingSound;

        if (_revealInstantly || _visibleLength >= _fullRuneLength) {
          _visibleLength = _fullRuneLength;
          _publishVisibleText();
          _revealing = false;
          _typingSoundForReveal = false;
        } else {
          _revealing = true;
          _scheduleReveal();
        }
        return;
      }

      _visibleLength = 0;
      _displayTextNotifier.value = '';

      if (_revealInstantly || _skippedRevealIdentity == identity) {
        _visibleLength = _fullRuneLength;
        _publishVisibleText();
        _revealing = false;
        _typingSoundForReveal = false;
        return;
      }

      final soundKey = '$messageKey|${controller.currentSentenceIndex}|$pageToken';
      _typingSoundForReveal = _typingSoundVisited.add(soundKey);

      _revealing = full.isNotEmpty;
      _scheduleReveal();
      return;
    }

    if (full != _lastFullText) {
      final previousLength = _lastFullRunes.length;
      final nextRunes = full.runes.toList(growable: false);
      final nextLength = nextRunes.length;
      _lastFullText = full;
      _lastFullRunes = nextRunes;

      if (_revealInstantly || _skippedRevealIdentity == identity) {
        _revealTimer?.cancel();
        _revealTimer = null;
        _visibleLength = nextLength;
        _publishVisibleText();
        _typingSoundForReveal = false;
        if (_revealing && mounted) setState(() => _revealing = false);
        return;
      }

      if (_visibleLength > nextLength) {
        _visibleLength = nextLength;
        _publishVisibleText();
      }

      if (nextLength > previousLength &&
          _visibleLength < nextLength &&
          _revealTimer == null) {
        _revealing = true;
        _scheduleReveal();
      }
    }
  }

  void _scheduleReveal({String afterCharacter = ''}) {
    _revealTimer?.cancel();
    _revealTimer = null;

    if (!widget.active) {
      _revealing = false;
      return;
    }

    final runes = _lastFullRunes;
    final skippedByUser = _skippedRevealIdentity == _lastIdentity;
    if (_revealInstantly || skippedByUser) {
      _visibleLength = runes.length;
      _publishVisibleText();
      _typingSoundForReveal = false;
      if (_revealing && mounted) setState(() => _revealing = false);
      if (skippedByUser || !controller.isGenerating) {
        unawaited(controller.bgm.stopTypingSound());
      }
      return;
    }
    if (!mounted || _visibleLength >= runes.length) {
      if (_revealing && mounted) {
        setState(() => _revealing = false);
      }
      if (!controller.isGenerating) {
        unawaited(controller.bgm.stopTypingSound());
      }
      return;
    }

    int baseDelay = 1000 ~/ (controller.settings.textSpeedCps > 0 ? controller.settings.textSpeedCps : 20);
    int delayMs = baseDelay;
    
    if (afterCharacter.isNotEmpty) {
      final char = afterCharacter;
      if (char == '，' || char == '、' || char == ',') {
        delayMs = baseDelay * 3;
      } else if (char == '。' || char == '！' || char == '？' || char == '!' || char == '?') {
        delayMs = baseDelay * 7;
      } else if (char == '…' || char == '—' || char == '~' || char == '～') {
        delayMs = baseDelay * 5;
      } else if (char == '\n') {
        delayMs = baseDelay * 10;
      }
    }
    var delay = Duration(milliseconds: delayMs);

    if (controller.isGenerating &&
        _visibleLength == 0 &&
        afterCharacter.isEmpty &&
        delay < const Duration(milliseconds: 72)) {
      delay = const Duration(milliseconds: 72);
    }

    _revealTimer = Timer(delay, () {
      if (!mounted || !widget.active) {
        _revealTimer = null;
        unawaited(controller.bgm.stopTypingSound());
        return;
      }

      final latestRunes = _lastFullRunes;
      if (latestRunes.isEmpty || _visibleLength >= latestRunes.length) {
        _finishReveal();
        return;
      }

      final current =
          String.fromCharCode(latestRunes[_visibleLength.clamp(0, latestRunes.length - 1)]);
      _visibleLength = (_visibleLength + 1).clamp(0, latestRunes.length);
      _publishVisibleText();

      if (controller.settings.typingSoundEnabled &&
          _typingSoundForReveal &&
          _shouldPlayNovelTypingTick(
            visibleLength: _visibleLength,
            currentCharacter: current,
          )) {
        controller.bgm.playTypingTick();
      }

      if (_visibleLength >= latestRunes.length) {
        _finishReveal();
      } else {
        _scheduleReveal(afterCharacter: current);
      }
    });
  }

  void _finishReveal() {
    _revealTimer?.cancel();
    _revealTimer = null;
    if (mounted) setState(() => _revealing = false);

    if (!controller.isGenerating) {
      unawaited(controller.bgm.stopTypingSound());
    }
  }

  void _handleStageTap() {
    if (!widget.active || _swipeTransitioning) return;

    if (widget.targetActorName.trim().isNotEmpty) return;

    if (widget.focusNode.hasFocus &&
        MediaQuery.viewInsetsOf(context).bottom > 0) {
      widget.focusNode.unfocus();
      return;
    }

    if (widget.focusNode.hasFocus) {
      widget.focusNode.unfocus();
    }
    _handleStoryTap();
  }

  void _handleStoryTap() {
    if (_revealing) {
      _skippedRevealIdentity = _lastIdentity;
      _typingSoundForReveal = false;
      _visibleLength = _fullRuneLength;
      _publishVisibleText();
      _finishReveal();
      unawaited(controller.bgm.stopTypingSound());
      return;
    }

    if (_hasNextMixedReaderPage || _hasNextNarrationReaderPage) {
      unawaited(_goNextAfterTypingStops());
      return;
    }

    if (controller.isGenerating) {
      _skippedRevealIdentity = _lastIdentity;
      _typingSoundForReveal = false;
      _visibleLength = _fullRuneLength;
      _publishVisibleText();
      _finishReveal();
      unawaited(controller.bgm.stopTypingSound());
      return;
    }

    if (controller.hasNext || controller.pendingFateRevert) {
      unawaited(_goNextAfterTypingStops());
    }
  }

  Future<void> _goNextAfterTypingStops() async {
    await controller.bgm.stopTypingSound();
    if (!mounted) return;

    if (_hasNextMixedReaderPage) {
      _setMixedReaderPage(_mixedPageIndex + 1);
      return;
    }
    if (_hasNextNarrationReaderPage) {
      _setNarrationReaderPage(_narrationPageIndex + 1);
      return;
    }

    final hadControllerNext = controller.hasNext;
    controller.goNext();
    if (hadControllerNext) {
      _syncReveal(force: true);
    }
  }

  double _swipeLimit(double width) =>
      (width * .22).clamp(72.0, 126.0).toDouble();

  Widget _withSwipeMotion(Widget child, double width) {
    final progress =
        (_swipeVisualOffset.abs() / _swipeLimit(width)).clamp(0.0, 1.0);
    final opacity = (1.0 - progress * .20).clamp(.80, 1.0).toDouble();

    return Opacity(
      opacity: opacity,
      child: Transform.translate(
        offset: Offset(_swipeVisualOffset, 0),
        child: child,
      ),
    );
  }

  Future<void> _animateSwipeTo(
    double target, {
    required Duration duration,
    required Curve curve,
  }) async {
    if (!mounted) return;

    _swipeController.stop();
    _swipeController.duration = duration;
    final begin = _swipeVisualOffset;
    final animation = Tween<double>(begin: begin, end: target).animate(
      CurvedAnimation(parent: _swipeController, curve: curve),
    );

    void tick() {
      if (!mounted) return;
      setState(() => _swipeVisualOffset = animation.value);
    }

    _swipeController.addListener(tick);
    try {
      await _swipeController.forward(from: 0);
    } finally {
      _swipeController.removeListener(tick);
    }
  }

  Future<void> _springSwipeBack() async {
    if (_swipeTransitioning) return;
    _swipeTransitioning = true;
    try {
      await _animateSwipeTo(
        0,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
      );
    } finally {
      _horizontalDragDistance = 0;
      _swipeTransitioning = false;
    }
  }

  Future<void> _commitSwipe(int direction) async {
    if (_swipeTransitioning || !mounted) return;

    final canMove = direction < 0
        ? _canMoveNextReaderPage
        : _canMovePreviousReaderPage;
    if (!canMove) {
      await _springSwipeBack();
      return;
    }

    _swipeTransitioning = true;
    _swipeHintTimer?.cancel();
    if (_showSwipeHint && mounted) {
      setState(() => _showSwipeHint = false);
    }

    if (_revealing) {
      _finishReveal();
    }
    await controller.bgm.stopTypingSound();
    if (!mounted) return;

    final width = MediaQuery.sizeOf(context).width;
    final exit = _swipeLimit(width) * (direction < 0 ? -1 : 1);

    try {
      await _animateSwipeTo(
        exit,
        duration: const Duration(milliseconds: 125),
        curve: Curves.easeOutCubic,
      );
      if (!mounted) return;

      if (direction < 0) {
        if (_hasNextMixedReaderPage) {
          _mixedPageIndex = _safeMixedPageIndex(
                _mixedReaderPagesForCurrentSentence(),
              ) +
              1;
          _syncReveal(force: true);
        } else if (_hasNextNarrationReaderPage) {
          final pages = _narrationPagesForCurrentSentence();
          _narrationPageIndex = _safeNarrationPageIndex(pages) + 1;
          _syncReveal(force: true);
        } else {
          controller.goNext();
          _syncReveal(force: true);
        }
      } else {
        if (_hasPreviousMixedReaderPage) {
          _mixedPageIndex = _safeMixedPageIndex(
                _mixedReaderPagesForCurrentSentence(),
              ) -
              1;
          _syncReveal(force: true);
        } else if (_hasPreviousNarrationReaderPage) {
          final pages = _narrationPagesForCurrentSentence();
          _narrationPageIndex = _safeNarrationPageIndex(pages) - 1;
          _syncReveal(force: true);
        } else {
          _enterPreviousSentenceAtLastReaderPage = true;
          controller.goPrevious();
          _syncReveal(force: true);
        }
      }

      if (!mounted) return;

      setState(() {
        _horizontalDragDistance = 0;
        _swipeVisualOffset = direction < 0 ? 30.0 : -30.0;
      });

      await _animateSwipeTo(
        0,
        duration: const Duration(milliseconds: 190),
        curve: Curves.easeOutCubic,
      );
    } finally {
      _horizontalDragDistance = 0;
      _swipeVisualOffset = 0;
      _swipeTransitioning = false;
      if (mounted) setState(() {});
    }
  }

  bool get _inputBlocksReaderGesture {
    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
    return widget.targetActorName.trim().isNotEmpty ||
        (widget.focusNode.hasFocus && keyboardVisible);
  }

  void _handleHorizontalDragStart(DragStartDetails details) {
    if (_inputBlocksReaderGesture ||
        _swipeTransitioning) {
      return;
    }
    _swipeController.stop();
    _horizontalDragDistance = 0;
  }

  void _handleHorizontalDragUpdate(DragUpdateDetails details) {
    if (_inputBlocksReaderGesture ||
        _swipeTransitioning) {
      return;
    }

    _horizontalDragDistance += details.primaryDelta ?? 0;
    final width = MediaQuery.sizeOf(context).width;
    final limit = _swipeLimit(width);
    final wantsNext = _horizontalDragDistance < 0;
    final canMove =
        wantsNext ? _canMoveNextReaderPage : _canMovePreviousReaderPage;

    final rawVisual = canMove
        ? _horizontalDragDistance
        : _horizontalDragDistance * .18;
    final visual = rawVisual.clamp(-limit, limit).toDouble();

    setState(() => _swipeVisualOffset = visual);
  }

  void _handleHorizontalDragEnd(DragEndDetails details) {
    if (_inputBlocksReaderGesture ||
        _swipeTransitioning) {
      _horizontalDragDistance = 0;
      if (_swipeVisualOffset != 0) {
        unawaited(_springSwipeBack());
      }
      return;
    }

    final velocity = details.primaryVelocity ?? 0;
    final distance = _horizontalDragDistance;

    final hasEnoughDistance = distance.abs() >= 46;
    final hasEnoughVelocity = velocity.abs() >= 320;
    if (!hasEnoughDistance && !hasEnoughVelocity) {
      unawaited(_springSwipeBack());
      return;
    }

    final directionSource = hasEnoughDistance ? distance : velocity;
    final direction = directionSource < 0 ? -1 : 1;
    final canMove = direction < 0
        ? _canMoveNextReaderPage
        : _canMovePreviousReaderPage;

    if (!canMove) {
      unawaited(_springSwipeBack());
      return;
    }

    unawaited(_commitSwipe(direction));
  }

  void _handleHorizontalDragCancel() {
    if (_swipeVisualOffset != 0 && !_swipeTransitioning) {
      unawaited(_springSwipeBack());
    }
  }

  @override
  void dispose() {
    _revealTimer?.cancel();
    _swipeHintTimer?.cancel();
    unawaited(controller.bgm.stopTypingSound());
    controller.setReaderRevealing(false, notify: false);
    widget.textController.removeListener(_handleInputTextChanged);
    widget.controller.settings.removeListener(_handleRevealSettingsChanged);
    _swipeController.dispose();
    _displayTextNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) controller.setReaderRevealing(widget.active && _revealing);
    });
    final sentence = controller.currentSentence;
    final controllerSpeaker = controller.currentSpeakerName.trim();
    final sentenceSpeaker = sentence?.speakerName.trim() ?? '';
    final speaker =
        controllerSpeaker.isNotEmpty ? controllerSpeaker : sentenceSpeaker;
    final character = controller.currentSpeakerCharacter;
    final sentenceType = sentence?.type.toLowerCase().trim() ?? '';
    final isHost =
        sentence?.isProtagonist == true || character?.isMain == true;
    final hasSpeaker = speaker.isNotEmpty || character != null;
    final isNarration = sentence == null ||
        (!hasSpeaker &&
            (sentence.isNarration ||
                sentenceType == 'narration' ||
                sentenceType == 'action'));
    final mode = isNarration
        ? _NovelLineMode.narration
        : isHost
            ? _NovelLineMode.protagonist
            : _NovelLineMode.npc;

    final mixedPages = _novelMixedReaderPages(
      sentence,
      paginateNarration: _compactNarrationPaging,
    );
    final mixedPageIndex = _safeMixedPageIndex(mixedPages);
    final activeMixedPage =
        mixedPages.isEmpty ? null : mixedPages[mixedPageIndex];
    final isMixedSentence = sentence?.hasMixedContent == true;
    final mixedNarrationPageActive = isMixedSentence &&
        activeMixedPage != null &&
        activeMixedPage.kind != _NovelMixedPageKind.dialogue;
    final dialoguePageActive = isMixedSentence
        ? activeMixedPage?.kind == _NovelMixedPageKind.dialogue
        : mode != _NovelLineMode.narration;
    final currentPortraitUrl = controller.currentPortraitUrl.trim();
    final stageActors = dialoguePageActive && currentPortraitUrl.isNotEmpty
        ? <_NovelStageActorVisual>[
            _NovelStageActorVisual(
              id: character?.id.trim().isNotEmpty == true
                  ? character!.id.trim()
                  : (sentence?.characterId.trim().isNotEmpty == true
                      ? sentence!.characterId.trim()
                      : speaker),
              name: speaker.isNotEmpty
                  ? speaker
                  : (isHost ? controller.protagonistName : '角色'),
              portraitUrl: currentPortraitUrl,
              active: true,
              selected: false,
              protagonist: isHost,
            ),
          ]
        : const <_NovelStageActorVisual>[];
    final hasNextMixedReaderPage =
        mixedPages.isNotEmpty && mixedPageIndex < mixedPages.length - 1;
    final hasPreviousMixedReaderPage =
        mixedPages.isNotEmpty && mixedPageIndex > 0;
    final targetActorActive = widget.targetActorName.trim().isNotEmpty;
    final forcedBattlePending = controller.forcedBattlePending;
    final narrationPages = _narrationPagesForCurrentSentence();
    final narrationPageIndex = _safeNarrationPageIndex(narrationPages);
    final narrationPagingActive =
        _currentSentenceUsesNarrationPaging(sentence) && narrationPages.length > 1;
    final hasNextNarrationReaderPage = narrationPagingActive &&
        narrationPageIndex < narrationPages.length - 1;
    final hasPreviousNarrationReaderPage =
        narrationPagingActive && narrationPageIndex > 0;
    final readerHasNext = hasNextMixedReaderPage ||
        hasNextNarrationReaderPage ||
        (forcedBattlePending ? false : controller.hasNext);
    final readerHasPrevious = hasPreviousMixedReaderPage ||
        hasPreviousNarrationReaderPage ||
        controller.hasPrevious;

    final affection = mode == _NovelLineMode.npc ? character?.affection : null;
    final affectionPulse = mode == _NovelLineMode.npc
        ? controller.affectionPulseFor(character, speaker)
        : null;

    final storyContextOpacity = targetActorActive ? .50 : 1.0;
    final canShowChoices = !targetActorActive &&
        !forcedBattlePending &&
        controller.choices.isNotEmpty &&
        !readerHasNext &&
        !controller.isGenerating &&
        !_revealing &&
        !widget.isExploring;
    final inputEnabled = !hasNextMixedReaderPage &&
        !hasNextNarrationReaderPage &&
        !controller.isGenerating &&
        !_revealing &&
        !controller.isCinematic &&
        !controller.pendingFateRevert;

    final emptyTextFallback =
        controller.isGenerating ? '' : '等待故事继续…';

    return LayoutBuilder(
      builder: (context, constraints) {
        final screen = MediaQuery.sizeOf(context);
        final viewport = NovelViewportMetrics.of(
          context,
          desktopMode: controller.desktopMode,
        );
        final compact = viewport.compactContent;
        final shortViewport = viewport.shortViewport;
        final shortWide = viewport.shortWide;
        final availableHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : screen.height - MediaQuery.paddingOf(context).vertical;

        final wideDialogueLayout = viewport.useDesktopDialogue;

        const narrationRightSafeWidth = 0.0;
        
        final dialogueRightSafeWidth = wideDialogueLayout
            ? 0.0 
            : (shortWide 
                ? 52.0 
                : ((controller.hasNext || controller.isGenerating)
                    ? (compact ? 58.0 : 70.0)
                    : 0.0));
        final browsingStory = readerHasNext;

        final composerVisible =
            !browsingStory &&
            !controller.isGenerating &&
            !_revealing &&
            !forcedBattlePending;

        final surroundingsAction = NovelChoiceDockActionScope.maybeOf(context);
        final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
        final keyboardActive = compact && keyboardInset > 0;
        final surroundingsActionVisible =
            composerVisible &&
            !keyboardActive &&
            surroundingsAction?.visible == true;

        const navigationHeight = 0.0;
        final inputContextVisible = targetActorActive;
        final estimatedComposerHeight = composerVisible
            ? _adaptiveFooterHeight(
                  availableWidth: constraints.maxWidth,
                  compact: compact,
                  shortViewport: shortViewport,
                  choicesVisible: canShowChoices,
                  inputContextVisible: inputContextVisible,
                )
            : 0.0;
        final composerHeight = composerVisible
            ? math.max(estimatedComposerHeight, _measuredInputBarHeight)
            : 0.0;
        final footerHeight = navigationHeight +
            (composerVisible ? composerHeight + (compact ? 4.0 : 6.0) : 0.0);
        final reservedBottom = keyboardActive
            ? 0.0
            : math.max(0.0, widget.bottomReservedHeight);
        final composerBottom = keyboardActive ? keyboardInset : reservedBottom;
        final footerBottom = reservedBottom;

        final choiceDockHeight = canShowChoices
            ? (shortWide
                ? 30.0
                : (shortViewport ? 38.0 : (compact ? 42.0 : 44.0)))
            : 0.0;

        const choiceBottomGap = 2.0;
        final contentChoiceGap = shortViewport ? 4.0 : (compact ? 5.0 : 6.0);
        final dialogGap = shortViewport ? 10.0 : (compact ? 18.0 : 24.0);
        final panelBottom = footerBottom + footerHeight + dialogGap;

        final choiceContentBottom = footerBottom +
            footerHeight +
            choiceBottomGap +
            choiceDockHeight +
            contentChoiceGap;
        final choiceContentTop =
            MediaQuery.paddingOf(context).top + viewport.topContentReserve;
        final choiceAvailableContentHeight =
            (availableHeight - choiceContentTop - choiceContentBottom)
                .clamp(0.0, availableHeight)
                .toDouble();

        final sentenceReaderPageIndex = mixedPages.isNotEmpty
            ? mixedPageIndex
            : (narrationPagingActive ? narrationPageIndex : 0);
        final sentenceReaderPageTotal = sentence == null
            ? 1
            : _novelReaderPageCount(
                sentence,
                paginateNarration: _compactNarrationPaging,
              );
        var readerPageIndex = sentenceReaderPageIndex;
        var readerPageTotal = 0;
        for (var i = 0; i < controller.sentences.length; i++) {
          final pageCount = _novelReaderPageCount(
            controller.sentences[i],
            paginateNarration: _compactNarrationPaging,
          );
          if (i < controller.currentSentenceIndex) {
            readerPageIndex += pageCount;
          }
          readerPageTotal += pageCount;
        }
        if (readerPageTotal <= 0) readerPageTotal = 1;
        readerPageIndex = readerPageIndex.clamp(0, readerPageTotal - 1).toInt();

        final readerSentenceIndex = controller.currentSentenceIndex;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          controller.setReaderPagePosition(
            readerPageIndex,
            readerPageTotal,
            sentencePageIndex: sentenceReaderPageIndex,
            sentencePageTotal: sentenceReaderPageTotal,
            sentenceIndex: readerSentenceIndex,
          );
        });

        final readerTapTop = (MediaQuery.paddingOf(context).top +
                viewport.topContentReserve +
                (shortWide ? 2.0 : 4.0))
            .clamp(0.0, availableHeight)
            .toDouble();
        final readerTapSideInset =
            shortWide ? 72.0 : (compact ? 68.0 : 88.0);
        final requestedReaderTapBottom = canShowChoices
            ? choiceContentBottom
            : math.max(panelBottom, footerBottom + footerHeight + 10.0);
        final readerTapBottom = requestedReaderTapBottom
            .clamp(0.0, math.max(0.0, availableHeight - readerTapTop - 48.0))
            .toDouble();

        return GestureDetector(
          behavior: HitTestBehavior.deferToChild,
          onHorizontalDragStart: _handleHorizontalDragStart,
          onHorizontalDragUpdate: _handleHorizontalDragUpdate,
          onHorizontalDragEnd: _handleHorizontalDragEnd,
          onHorizontalDragCancel: _handleHorizontalDragCancel,
          child: SizedBox(
            width: double.infinity,
            height: availableHeight,
            child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              Positioned(
                left: readerTapSideInset,
                right: readerTapSideInset,
                top: readerTapTop,
                bottom: readerTapBottom,
                child: IgnorePointer(
                  ignoring: widget.isExploring,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _handleStageTap,
                    child: const SizedBox.expand(),
                  ),
                ),
              ),

              if (stageActors.isNotEmpty)
                Positioned.fill(
                  child: AnimatedOpacity(
                    opacity: widget.isExploring ? 0.0 : 1.0,
                    duration: const Duration(milliseconds: 240),
                    curve: Curves.easeOutCubic,
                    child: IgnorePointer(
                      ignoring: widget.isExploring,
                      child: _NovelPresenceStage(
                        actors: stageActors,
                        stageSize: Size(constraints.maxWidth, availableHeight),
                        reservedBottom: panelBottom,
                        wideDialogueLayout: wideDialogueLayout,
                        shortWide: shortWide,
                        compact: compact,
                      ),
                    ),
                  ),
                ),

              if (mixedNarrationPageActive)
                Positioned(
                  left: 0,
                  right: narrationRightSafeWidth,
                  top: canShowChoices ? choiceContentTop : 0,
                  bottom: canShowChoices ? choiceContentBottom : panelBottom,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    opacity: widget.isExploring ? 0.0 : storyContextOpacity,
                    child: IgnorePointer(
                      ignoring: targetActorActive || widget.isExploring,
                      child: _withSwipeMotion(
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: compact ? 20 : 34,
                      ),
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: shortWide ? 520.0 : 560.0,
                            maxHeight:
                                availableHeight * (shortWide ? .40 : .46),
                          ),
                          child: _NovelMixedNarrationSurface(
                            displayTextListenable: _displayTextNotifier,
                            isRevealing: _revealing,
                            fontFamily: controller.settings.fontFamily,
                            fontSize: controller.settings.fontSize,
                            storyAction: null,
                            onTap: _handleStoryTap,
                          ),
                        ),
                      ),
                    ),
                    screen.width,
                      ),
                    ),
                  ),
                ),

              if (!isMixedSentence && mode == _NovelLineMode.narration)
                if (canShowChoices)
                  Positioned(
                    left: 0,
                    right: narrationRightSafeWidth,
                    top: choiceContentTop,
                    bottom: choiceContentBottom,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutCubic,
                      opacity: widget.isExploring ? 0.0 : storyContextOpacity,
                      child: IgnorePointer(
                        ignoring: targetActorActive || widget.isExploring,
                        child: _withSwipeMotion(
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: compact ? 16 : 30,
                        ),
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: shortWide ? 520.0 : 560.0,
                          ),
                          child: _NovelNarrationSurface(
                            key: ValueKey<String>('narration-${controller.currentSentenceIndex}'),
                            displayTextListenable: _displayTextNotifier,
                            emptyTextFallback: emptyTextFallback,
                            isGenerating: controller.isGenerating,
                            isRevealing: _revealing,
                            fontFamily: controller.settings.fontFamily,
                            fontSize: controller.settings.fontSize,
                            hasNext: readerHasNext,
                            choices: controller.choices,
                            playerHint: controller.playerHint,
                            storyAction: null,
                            onSelected: controller.selectChoice,
                            onCustomInput: () => widget.focusNode.requestFocus(),
                            onForceContinue: widget.onForceContinue,
                            onTap: _handleStoryTap,
                            ),
                          ),
                        ),
                      ),
                      screen.width,
                        ),
                      ),
                    ),
                  )
                else
                  Positioned(
                    left: 0,
                    right: narrationRightSafeWidth,
                    top: 0,
                    bottom: footerHeight + footerBottom +
                        (compact ? 18.0 : 24.0),
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutCubic,
                      opacity: widget.isExploring ? 0.0 : storyContextOpacity,
                      child: IgnorePointer(
                        ignoring: targetActorActive || widget.isExploring,
                        child: _withSwipeMotion(
                      Align(
                        alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: compact ? 16 : 30,
                        ),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: shortWide ? 520.0 : 560.0,
                            maxHeight:
                                availableHeight * (shortWide ? .42 : .48),
                          ),
                          child: _NovelNarrationSurface(
                            key: ValueKey<String>('narration-${controller.currentSentenceIndex}'),
                            displayTextListenable: _displayTextNotifier,
                            emptyTextFallback: emptyTextFallback,
                            isGenerating: controller.isGenerating,
                            isRevealing: _revealing,
                            fontFamily: controller.settings.fontFamily,
                            fontSize: controller.settings.fontSize,
                            hasNext: readerHasNext,
                            choices: const <NovelChoice>[],
                            playerHint: controller.playerHint,
                            storyAction: null,
                            onSelected: controller.selectChoice,
                            onCustomInput: () => widget.focusNode.requestFocus(),
                            onForceContinue: widget.onForceContinue,
                            onTap: _handleStoryTap,
                            ),
                          ),
                        ),
                      ),
                      screen.width,
                        ),
                      ),
                    ),
                  ),
              if (dialoguePageActive)
                Positioned(
                  left: 0,
                  right: dialogueRightSafeWidth,
                  top: canShowChoices ? choiceContentTop : null,
                  bottom: canShowChoices ? choiceContentBottom : panelBottom,
                  child: ValueListenableBuilder<String>(
                    valueListenable: _displayTextNotifier,
                    builder: (context, _, __) {
                      return TweenAnimationBuilder<double>(
                        key: ValueKey<String>(
                          'dialogue-phase|${controller.currentSentenceIndex}|$speaker',
                        ),
                        tween: Tween<double>(begin: 0, end: 1),
                        duration: const Duration(milliseconds: 190),
                        curve: Curves.easeOutCubic,
                        builder: (context, value, child) {
                          final direction =
                              mode == _NovelLineMode.protagonist ? -1.0 : 1.0;
                          return Opacity(
                            opacity: value,
                            child: FractionalTranslation(
                              translation: Offset(
                                direction * .025 * (1 - value),
                                0,
                              ),
                              child: child,
                            ),
                          );
                        },
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOutCubic,
                          opacity: widget.isExploring ? 0.0 : storyContextOpacity,
                          child: IgnorePointer(
                            ignoring: targetActorActive || widget.isExploring,
                            child: _withSwipeMotion(
                          _NovelCharacterDialogueSurface(
                                key: ValueKey<String>(
                                  '${mode.name}-${controller.currentSentenceIndex}-$speaker',
                                ),
                                mode: mode,
                                desktopMode: wideDialogueLayout,
                                sentence: sentence,
                                speakerName: speaker.isEmpty
                                    ? (mode == _NovelLineMode.protagonist
                                        ? controller.protagonistName
                                        : '角色')
                                    : speaker,
                                affection: affection,
                                affectionPulse: affectionPulse,
                                onAffectionPulseConsumed:
                                    controller.consumeAffectionPulse,
                                displayTextListenable: _displayTextNotifier,
                                emptyTextFallback: emptyTextFallback,
                                isGenerating: controller.isGenerating,
                                isRevealing: _revealing,
                                fontFamily: controller.settings.fontFamily,
                                fontSize: controller.settings.fontSize,
                                hasNext: readerHasNext,
                                choices: canShowChoices
                                    ? controller.choices
                                    : const <NovelChoice>[],
                                playerHint: controller.playerHint,
                                showPlayerHint: !_revealing &&
                                    !readerHasNext &&
                                    !controller.isGenerating,
                            storyAction: null,
                                maxPanelHeight: canShowChoices
                                    ? choiceAvailableContentHeight
                                    : availableHeight *
                                        (shortWide ? .52 : (compact ? .38 : .31)),
                                onSelected: controller.selectChoice,
                                onCustomInput: () =>
                                    widget.focusNode.requestFocus(),
                                onForceContinue: widget.onForceContinue,
                                onTap: _handleStoryTap,
                                onOpenPortrait: widget.onOpenPortrait,
                          ),
                          screen.width,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              if (canShowChoices && !controller.isGenerating && !_revealing)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: footerBottom + footerHeight + choiceBottomGap,
                  child: _withSwipeMotion(
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: wideDialogueLayout
                              ? 920.0
                              : (shortWide
                                  ? math.min(720.0, screen.width)
                                  : screen.width),
                        ),
                        child: NovelChoiceDock(
                          choices: controller.choices,
                          onSelected: controller.selectChoice,
                        ),
                      ),
                    ),
                    screen.width,
                  ),
                ),
              if (surroundingsActionVisible)
                Positioned(
                  left: compact ? 8.0 : 14.0,
                  top: math.max(
                    MediaQuery.paddingOf(context).top +
                        viewport.topContentReserve +
                        (shortWide ? 8.0 : 14.0),
                    availableHeight * (shortWide ? .30 : .38),
                  ),
                  child: AnimatedOpacity(
                    opacity: widget.isExploring ? 0.0 : 1.0,
                    duration: const Duration(milliseconds: 180),
                    child: IgnorePointer(
                      ignoring: widget.isExploring,
                      child: _NovelFloatingSurroundingsAction(
                        scope: surroundingsAction!,
                        compact: compact || shortWide,
                      ),
                    ),
                  ),
                ),
              Positioned(
                left: 0,
                right: 0,
                bottom: composerBottom,
                child: _NovelDialogFooter(
                  controller: controller,
                  choicesAvailable: canShowChoices,
                  inputEnabled: inputEnabled,
                  showComposer: composerVisible,
                  textController: widget.textController,
                  focusNode: widget.focusNode,
                  onSend: widget.onSend,
                  onOpenInventory: widget.onOpenInventory,
                  onOpenCharacters: widget.onOpenCharacters,
                  onOpenJourney: widget.onOpenJourney,
                  onContinue: widget.onContinue,
                  showBattleContinue: forcedBattlePending && !readerHasNext,
                  onForceContinue: widget.onForceContinue,
                  targetActorName: widget.targetActorName,
                  targetActorAvatarUrl: widget.targetActorAvatarUrl,
                  targetActorPlaceholder: widget.targetActorPlaceholder,
                  onClearTargetActor: widget.onClearTargetActor,
                  onInputLayoutHeightChanged: _handleInputLayoutHeightChanged,
                  isExploring: widget.isExploring,
                ),
              ),
              if (_showSwipeHint &&
                  !canShowChoices &&
                  !controller.isGenerating &&
                  !_revealing &&
                  (readerHasPrevious || readerHasNext))
                Positioned(
                  left: compact ? 18 : 34,
                  right: compact ? 18 : 34,
                  bottom: footerBottom + footerHeight + (browsingStory ? 26 : 7),
                  child: AnimatedOpacity(
                    opacity: widget.isExploring ? 0.0 : 1.0,
                    duration: const Duration(milliseconds: 180),
                    child: const Center(
                      child: _LuxurySwipeHint(),
                    ),
                  ),
                ),
              Positioned(
                left: compact ? 18 : 34,
                right: compact ? 18 : 34,
                bottom: footerBottom + navigationHeight + (compact ? 6 : 8),
                child: AnimatedOpacity(
                  opacity: widget.isExploring ? 0.0 : 1.0,
                  duration: const Duration(milliseconds: 180),
                  child: _StoryProgressLocator(
                    currentIndex: readerPageIndex,
                    totalCount: readerPageTotal,
                    isBrowsingHistory: browsingStory,
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

class _NovelNarrationSurface extends StatelessWidget {
  const _NovelNarrationSurface({
    super.key,
    required this.displayTextListenable,
    required this.emptyTextFallback,
    required this.isGenerating,
    required this.isRevealing,
    required this.fontFamily,
    required this.fontSize,
    required this.hasNext,
    required this.choices,
    required this.playerHint,
    this.storyAction,
    required this.onSelected,
    required this.onCustomInput,
    required this.onForceContinue,
    required this.onTap,
  });

  final ValueListenable<String> displayTextListenable;
  final String emptyTextFallback;
  final bool isGenerating;
  final bool isRevealing;
  final String? fontFamily;
  final double fontSize;
  final bool hasNext;
  final List<NovelChoice> choices;
  final String playerHint;
  final Widget? storyAction;
  final ValueChanged<NovelChoice> onSelected;
  final VoidCallback onCustomInput;
  final VoidCallback onForceContinue;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final viewport = NovelViewportMetrics.of(context);
    final compact = viewport.compactContent;
    final shortWide = viewport.shortWide;

    return SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        clipBehavior: Clip.none,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: shortWide
              ? CrossAxisAlignment.stretch
              : CrossAxisAlignment.start,
          children: <Widget>[
            if (storyAction != null) ...<Widget>[
              Align(
                alignment: Alignment.centerLeft,
                child: storyAction!,
              ),
              SizedBox(height: shortWide ? 3 : (compact ? 5 : 7)),
            ],
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: onTap,
              child: ValueListenableBuilder<String>(
              valueListenable: displayTextListenable,
              builder: (context, value, _) => TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: isRevealing ? 1.0 : 0.0),
                duration: const Duration(milliseconds: 600),
                curve: Curves.easeOutCubic,
                builder: (context, glow, child) {
                  final style = TextStyle(
                    color: const Color(0xE6F3F4F6),
                    fontFamily: fontFamily,
                    fontSize: fontSize + .4,
                    height: shortWide ? 1.56 : (compact ? 1.62 : 1.68),
                    fontWeight: FontWeight.w400,
                    letterSpacing: .22,
                    shadows: <Shadow>[
                      Shadow(
                        color: Color.lerp(
                          const Color(0x8A000000),
                          const Color(0xB0000000),
                          glow,
                        )!,
                        blurRadius: 5,
                        offset: const Offset(0, 1),
                      ),
                      const Shadow(
                        color: Color(0x4D000000),
                        blurRadius: 14,
                        offset: Offset(0, 3),
                      ),
                    ],
                  );
                  return _NovelNarrationParagraphText(
                    value: value.isEmpty ? emptyTextFallback : value,
                    style: style,
                    textAlign: TextAlign.left,
                    paragraphSpacing: compact ? 7 : 9,
                  );
                },
              ),
              ),
            ),
            if (!hasNext &&
                !isGenerating &&
                !isRevealing &&
                playerHint.trim().isNotEmpty) ...<Widget>[
              const SizedBox(height: 14),
              _NarratorHint(text: playerHint),
            ],
          ],
        ),
      );
  }
}

class _NovelMixedNarrationSurface extends StatelessWidget {
  const _NovelMixedNarrationSurface({
    required this.displayTextListenable,
    required this.isRevealing,
    required this.fontFamily,
    required this.fontSize,
    this.storyAction,
    required this.onTap,
  });

  final ValueListenable<String> displayTextListenable;
  final bool isRevealing;
  final String? fontFamily;
  final double fontSize;
  final Widget? storyAction;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final viewport = NovelViewportMetrics.of(context);
    final shortWide = viewport.shortWide;
    final compact = viewport.compactContent;

    return SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        clipBehavior: Clip.none,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (storyAction != null) ...<Widget>[
              Align(
                alignment: Alignment.centerLeft,
                child: storyAction!,
              ),
              SizedBox(height: shortWide ? 3 : (compact ? 5 : 7)),
            ],
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: onTap,
              child: ValueListenableBuilder<String>(
          valueListenable: displayTextListenable,
          builder: (context, value, _) {
            final visibleNarration = _novelVisibleNarrationText(value).trim();
            if (visibleNarration.isEmpty) return const SizedBox.shrink();

            return TweenAnimationBuilder<double>(
              key: ValueKey<String>('mixed-narration-page'),
              tween: Tween<double>(begin: 0, end: 1),
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              builder: (context, entrance, child) {
                final glow = isRevealing ? 1.0 : 0.0;
                final style = TextStyle(
                  color: const Color(0xE6F3F4F6),
                  fontFamily: fontFamily,
                  fontSize: fontSize + .25,
                  height: shortWide ? 1.54 : (compact ? 1.60 : 1.66),
                  fontWeight: FontWeight.w400,
                  letterSpacing: .20,
                  shadows: <Shadow>[
                    Shadow(
                      color: Color.lerp(
                        const Color(0x8A000000),
                        const Color(0xB0000000),
                        glow,
                      )!,
                      blurRadius: 5,
                      offset: const Offset(0, 1),
                    ),
                    const Shadow(
                      color: Color(0x4D000000),
                      blurRadius: 14,
                      offset: Offset(0, 3),
                    ),
                  ],
                );

                return Opacity(
                  opacity: entrance,
                  child: Transform.translate(
                    offset: Offset(0, (1 - entrance) * 5),
                    child: _NovelNarrationParagraphText(
                      value: value,
                      style: style,
                      textAlign: TextAlign.left,
                    ),
                  ),
                );
              },
            );
          },
              ),
            ),
          ],
        ),
      );
  }
}

class _NovelCharacterDialogueSurface extends StatelessWidget {
  const _NovelCharacterDialogueSurface({
    super.key,
    required this.mode,
    required this.desktopMode,
    required this.sentence,
    required this.speakerName,
    required this.affection,
    required this.affectionPulse,
    required this.onAffectionPulseConsumed,
    required this.displayTextListenable,
    required this.emptyTextFallback,
    required this.isGenerating,
    required this.isRevealing,
    required this.fontFamily,
    required this.fontSize,
    required this.hasNext,
    required this.choices,
    required this.playerHint,
    required this.showPlayerHint,
    this.storyAction,
    required this.maxPanelHeight,
    required this.onSelected,
    required this.onCustomInput,
    required this.onForceContinue,
    required this.onTap,
    this.onOpenPortrait,
  });

  final _NovelLineMode mode;
  final bool desktopMode;
  final NovelSentence? sentence;
  final String speakerName;
  final int? affection;
  final NovelAffectionPulse? affectionPulse;
  final ValueChanged<int> onAffectionPulseConsumed;
  final ValueListenable<String> displayTextListenable;
  final String emptyTextFallback;
  final bool isGenerating;
  final bool isRevealing;
  final String? fontFamily;
  final double fontSize;
  final bool hasNext;
  final List<NovelChoice> choices;
  final String playerHint;
  final bool showPlayerHint;
  final Widget? storyAction;
  final double maxPanelHeight;
  final ValueChanged<NovelChoice> onSelected;
  final VoidCallback onCustomInput;
  final VoidCallback onForceContinue;
  final VoidCallback onTap;
  final VoidCallback? onOpenPortrait;

  bool get isHost => mode == _NovelLineMode.protagonist;

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final viewport = NovelViewportMetrics.of(
      context,
      desktopMode: desktopMode,
    );
    final compact = viewport.compactContent;
    final compactChrome = viewport.compactChrome;
    final shortWide = viewport.shortWide;
    final wideDialogueLayout = viewport.useDesktopDialogue;

    final dialogueWidth = shortWide
        ? (screen.width * .44).clamp(280.0, 420.0).toDouble()
        : compact
            ? (screen.width * .60).clamp(208.0, 350.0).toDouble()
            : wideDialogueLayout
                ? (screen.width * .52).clamp(500.0, 960.0).toDouble()
                : (screen.width * .50).clamp(360.0, 680.0).toDouble();

    final outerHorizontal = shortWide ? 26.0 : (compact ? 9.0 : (wideDialogueLayout ? 120.0 : 20.0));
    final isLandscape = screen.width > screen.height;
    final landscapeNpcLeftShift = isLandscape && !wideDialogueLayout && !isHost
        ? (screen.width * .08).clamp(72.0, 156.0).toDouble()
        : 0.0;
    final portraitFacingGap = shortWide ? 10.0 : (compact ? 7.0 : (wideDialogueLayout ? 16.0 : 12.0));

    const panelRadius = 18.0;

    final dialogueContent = SizedBox(
      width: dialogueWidth,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxPanelHeight.clamp(0.0, 520.0).toDouble()),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          clipBehavior: Clip.none,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: wideDialogueLayout
                ? CrossAxisAlignment.start
                : (isHost ? CrossAxisAlignment.end : CrossAxisAlignment.start),
            children: <Widget>[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isHost && onOpenPortrait != null) _PortraitSwitchButton(onTap: onOpenPortrait!),
                  if (isHost && onOpenPortrait != null) const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: _SpeakerIdentity(
                      name: speakerName,
                      affection: affection,
                      isHost: isHost,
                      affectionPulse: affectionPulse,
                      onAffectionPulseConsumed: onAffectionPulseConsumed,
                    ),
                  ),
                  if (!isHost && onOpenPortrait != null) const SizedBox(width: 8),
                  if (!isHost && onOpenPortrait != null) _PortraitSwitchButton(onTap: onOpenPortrait!),
                ],
              ),
              
              const SizedBox(height: 6),

              GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: onTap,
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: isRevealing ? 1.0 : 0.0),
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.easeOutCubic,
                  builder: (context, glow, child) {
                    final style = TextStyle(
                      color: const Color(0xFFF4F1EA),
                      fontFamily: fontFamily,
                      fontSize: fontSize + (shortWide ? -.2 : (compact ? 0 : .4)),
                      height: shortWide ? 1.55 : 1.72,
                      fontWeight: FontWeight.w500,
                      letterSpacing: .35,
                      shadows: <Shadow>[
                        Shadow(color: Color.lerp(const Color(0x99000000), const Color(0xD9000000), glow)!, blurRadius: 6 - 2 * glow, offset: const Offset(0, 1)),
                        Shadow(color: Color.lerp(const Color(0x66000000), const Color(0x80FFFFFF), glow)!, blurRadius: 12),
                      ],
                    );
                    
                    return Container(
                      margin: const EdgeInsets.only(bottom: 16.0),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(panelRadius),
                        boxShadow: const [BoxShadow(color: Color(0x1A000000), blurRadius: 16, offset: Offset(0, 6))],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(panelRadius),
                        child: _AdaptiveBackdropBlur(
                          sigma: 16,
                          child: Container(
                            padding: EdgeInsets.symmetric(horizontal: compact ? 16 : 20, vertical: compact ? 14 : 16),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(panelRadius),
                              border: Border.all(color: Colors.white.withOpacity(0.35), width: 1.0),
                            ),
                            child: ValueListenableBuilder<String>(
                              valueListenable: displayTextListenable,
                              builder: (context, value, _) {
                                final display = value.isEmpty && !(sentence?.readerText.isNotEmpty == true) ? emptyTextFallback : value;
                                const alignment = TextAlign.left;
                                return Text.rich(
                                  TextSpan(children: _buildNovelDialogueDisplaySpans(display, style)),
                                  textAlign: alignment,
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (showPlayerHint && playerHint.trim().isNotEmpty) ...<Widget>[
                const SizedBox(height: 2),
                _NarratorHint(text: playerHint),
              ],
            ],
          ),
        ),
      ),
    );

    final sceneHudLeftInset = compactChrome ? 6.0 : 14.0;
    final horizontalReadingAlignment = wideDialogueLayout
        ? Alignment.centerRight
        : (isHost ? Alignment.centerLeft : Alignment.centerRight);

    return Align(
        alignment: choices.isNotEmpty ? Alignment.bottomCenter : const Alignment(0, -0.15),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (storyAction != null) ...<Widget>[
              Padding(
                padding: EdgeInsets.only(left: sceneHudLeftInset),
                child: Align(alignment: Alignment.centerLeft, child: storyAction!),
              ),
              SizedBox(height: shortWide ? 3 : (compact ? 5 : 7)),
            ],
            Padding(
              padding: EdgeInsets.only(
                left: outerHorizontal,
                right: outerHorizontal + landscapeNpcLeftShift,
              ),
              child: Align(
                alignment: horizontalReadingAlignment,
                child: Padding(
                  padding: EdgeInsets.only(
                    right: wideDialogueLayout ? 0 : (isHost ? portraitFacingGap : 0),
                    left: wideDialogueLayout ? portraitFacingGap : (isHost ? 0 : portraitFacingGap),
                  ),
                  child: dialogueContent, 
                ),
              ),
            ),
          ],
        ),
      );
  }
}

class _SpeakerIdentity extends StatefulWidget {
  const _SpeakerIdentity({
    required this.name,
    required this.affection,
    required this.isHost,
    required this.affectionPulse,
    required this.onAffectionPulseConsumed,
  });

  final String name;
  final int? affection;
  final bool isHost;
  final NovelAffectionPulse? affectionPulse;
  final ValueChanged<int> onAffectionPulseConsumed;

  @override
  State<_SpeakerIdentity> createState() =>
      _SpeakerIdentityState();
}

class _SpeakerIdentityState extends State<_SpeakerIdentity> {
  static const Color _affectionPink = Color(0xFFFF7DA5);
  static const Color _affectionPinkGlow = Color(0xFFFFB0C8);
  static const Color _affectionLoss = Color(0xFFCB667B);

  Timer? _affectionPulseTimer;
  int _pulseSerial = 0;
  int _pulseDirection = 0;
  int _pulseDelta = 0;

  @override
  void initState() {
    super.initState();
    _activateInitialPulse(widget.affectionPulse);
  }

  void _activateInitialPulse(NovelAffectionPulse? pulse) {
    if (pulse == null || pulse.delta == 0) return;
    _pulseSerial = pulse.id;
    _pulseDirection = pulse.delta > 0 ? 1 : -1;
    _pulseDelta = pulse.delta;
    _schedulePulseReset();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onAffectionPulseConsumed(pulse.id);
    });
  }

  void _activatePulse(NovelAffectionPulse pulse) {
    _affectionPulseTimer?.cancel();
    setState(() {
      _pulseSerial = pulse.id;
      _pulseDirection = pulse.delta > 0 ? 1 : -1;
      _pulseDelta = pulse.delta;
    });
    _schedulePulseReset();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onAffectionPulseConsumed(pulse.id);
    });
  }

  void _schedulePulseReset() {
    _affectionPulseTimer?.cancel();
    _affectionPulseTimer = Timer(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      setState(() => _pulseDirection = 0);
    });
  }

  @override
  void didUpdateWidget(covariant _SpeakerIdentity oldWidget) {
    super.didUpdateWidget(oldWidget);

    final nextPulse = widget.affectionPulse;
    final oldPulseId = oldWidget.affectionPulse?.id ?? 0;
    if (nextPulse != null &&
        nextPulse.delta != 0 &&
        nextPulse.id != oldPulseId) {
      _activatePulse(nextPulse);
    }
  }

  @override
  void dispose() {
    _affectionPulseTimer?.cancel();
    super.dispose();
  }

  Widget _feedbackTransform({
    required String keyPrefix,
    required Widget child,
  }) {
    if (_pulseDirection == 0) return child;

    return TweenAnimationBuilder<double>(
      key: ValueKey<String>('$keyPrefix-$_pulseSerial'),
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 720),
      curve: Curves.linear,
      child: child,
      builder: (context, value, child) {
        if (_pulseDirection > 0) {
          final double scale;
          if (value < .22) {
            scale = lerpDouble(1.0, 1.25, value / .22)!;
          } else if (value < .46) {
            scale = lerpDouble(1.25, .97, (value - .22) / .24)!;
          } else {
            scale = lerpDouble(.97, 1.0, (value - .46) / .54)!;
          }
          final lift = -2.5 * math.sin(value * math.pi);
          return Transform.translate(
            offset: Offset(0, lift),
            child: Transform.scale(scale: scale, child: child),
          );
        }

        final envelope = 1.0 - value;
        final shakeX = math.sin(value * math.pi * 6) * 3.0 * envelope;
        final scale = 1.0 + math.sin(value * math.pi) * .065;
        return Transform.translate(
          offset: Offset(shakeX, 0),
          child: Transform.scale(scale: scale, child: child),
        );
      },
    );
  }

  Widget _buildAffectionHeart(int affection) {
    final activeColor = _pulseDirection < 0 ? _affectionLoss : _affectionPink;

    final heart = Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: <Widget>[
        if (_pulseDirection > 0)
          TweenAnimationBuilder<double>(
            key: ValueKey<String>('heart-glow-$_pulseSerial'),
            tween: Tween<double>(begin: 0, end: 1),
            duration: const Duration(milliseconds: 650),
            builder: (context, value, child) {
              final opacity = math.sin(value * math.pi).clamp(0.0, 1.0).toDouble();
              return Opacity(
                opacity: opacity * .30,
                child: Transform.scale(
                  scale: 1.0 + value * .70,
                  child: const Icon(
                    Icons.favorite_rounded,
                    size: 14.5,
                    color: _affectionPinkGlow,
                  ),
                ),
              );
            },
          ),
        Icon(
          Icons.favorite_rounded,
          size: _pulseDirection == 0 ? 12.8 : 13.8,
          color: activeColor,
        ),
      ],
    );

    return _feedbackTransform(
      keyPrefix: 'heart',
      child: heart,
    );
  }

  Widget _buildDeltaFeedback() {
    if (_pulseDirection == 0 || _pulseDelta == 0) {
      return const SizedBox.shrink();
    }

    final positive = _pulseDirection > 0;
    return Positioned(
      top: positive ? -19 : 14,
      child: TweenAnimationBuilder<double>(
        key: ValueKey<int>(_pulseSerial),
        tween: Tween<double>(begin: 0, end: 1),
        duration: const Duration(milliseconds: 880),
        curve: Curves.linear,
        builder: (context, value, child) {
          final opacity = value < .12
              ? value / .12
              : value > .66
                  ? (1.0 - value) / .34
                  : 1.0;

          if (positive) {
            final travel = Curves.easeOutCubic.transform(value);
            final offsetY = -18.0 * travel;

            final double scale;
            if (value < .18) {
              scale = lerpDouble(.72, 1.28, value / .18)!;
            } else if (value < .38) {
              scale = lerpDouble(1.28, 1.0, (value - .18) / .20)!;
            } else {
              scale = 1.0;
            }

            final particleOpacity = ((1.0 - value) * .72).clamp(0.0, .72).toDouble();
            return Opacity(
              opacity: opacity.clamp(0.0, 1.0).toDouble(),
              child: Transform.translate(
                offset: Offset(0, offsetY),
                child: Transform.scale(
                  scale: scale,
                  child: Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.center,
                    children: <Widget>[
                      Text(
                        '+$_pulseDelta',
                        style: const TextStyle(
                          color: _affectionPink,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w900,
                          shadows: <Shadow>[
                            Shadow(
                              color: Color(0x99FF7DA5),
                              blurRadius: 9,
                            ),
                            Shadow(
                              color: Color(0xD9000000),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                      ),
                      Transform.translate(
                        offset: Offset(-10 - 7 * value, -5 - 8 * value),
                        child: Opacity(
                          opacity: particleOpacity,
                          child: const Icon(
                            Icons.favorite_rounded,
                            size: 4.8,
                            color: _affectionPinkGlow,
                          ),
                        ),
                      ),
                      Transform.translate(
                        offset: Offset(11 + 8 * value, -2 - 11 * value),
                        child: Opacity(
                          opacity: particleOpacity * .85,
                          child: const Icon(
                            Icons.circle,
                            size: 3.4,
                            color: _affectionPinkGlow,
                          ),
                        ),
                      ),
                      Transform.translate(
                        offset: Offset(4 + 4 * value, -10 - 7 * value),
                        child: Opacity(
                          opacity: particleOpacity * .65,
                          child: const Icon(
                            Icons.circle,
                            size: 2.6,
                            color: _affectionPinkGlow,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          final dropY = 8.0 * Curves.easeOut.transform(value);
          final shakeX = math.sin(value * math.pi * 6) * 2.7 * (1.0 - value);
          final double scale;
          if (value < .20) {
            scale = lerpDouble(.86, 1.12, value / .20)!;
          } else if (value < .42) {
            scale = lerpDouble(1.12, .95, (value - .20) / .22)!;
          } else {
            scale = lerpDouble(.95, 1.0, (value - .42) / .58)!;
          }

          return Opacity(
            opacity: opacity.clamp(0.0, 1.0).toDouble(),
            child: Transform.translate(
              offset: Offset(shakeX, dropY),
              child: Transform.scale(
                scale: scale,
                child: Text(
                  '$_pulseDelta',
                  style: const TextStyle(
                    color: _affectionLoss,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w900,
                    shadows: <Shadow>[
                      Shadow(color: Color(0xD9000000), blurRadius: 5),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final affection = widget.affection;

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Text(
          widget.name,
          style: const TextStyle(
            color: Color(0xFFF9FAFC),
            fontFamily: 'WenJinMinchoP0',
            fontSize: 14.4,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.10,
            shadows: <Shadow>[
              Shadow(
                color: Color(0x66000000),
                blurRadius: 3,
                offset: Offset(0, 1),
              ),
              Shadow(
                color: Color(0xF0000000),
                blurRadius: 9,
                offset: Offset(0, 2),
              ),
              Shadow(
                color: Color(0x33FFFFFF),
                blurRadius: 7,
              ),
            ],
          ),
        ),
        if (affection != null) ...<Widget>[
          const SizedBox(width: 8),
          _buildAffectionHeart(affection),
          const SizedBox(width: 3),
          Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: <Widget>[
              _feedbackTransform(
                keyPrefix: 'affection-number',
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) {
                    final direction = _pulseDirection >= 0 ? 1.0 : -1.0;
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: Offset(0, .20 * direction),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    );
                  },
                  child: Text(
                    '$affection',
                    key: ValueKey<int>(affection),
                    style: TextStyle(
                      color: _pulseDirection < 0
                          ? _affectionLoss
                          : _affectionPink,
                      fontSize: 10.7,
                      fontWeight: FontWeight.w800,
                      shadows: <Shadow>[
                        if (_pulseDirection > 0)
                          const Shadow(
                            color: Color(0x66FF7DA5),
                            blurRadius: 8,
                          ),
                        const Shadow(
                          color: Color(0xD9000000),
                          blurRadius: 5,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              _buildDeltaFeedback(),
            ],
          ),
        ],
      ],
    );
  }
}

class _PortraitSwitchButton extends StatelessWidget {
  const _PortraitSwitchButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '形象',
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          splashColor: Colors.white.withOpacity(.08),
          highlightColor: Colors.white.withOpacity(.04),
          child: Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black.withOpacity(.22),
              border: Border.all(
                color: Colors.white.withOpacity(.18),
                width: .8,
              ),
            ),
            child: Icon(
              Icons.cached_rounded,
              size: 18,
              color: Colors.white.withOpacity(.92),
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
      ),
    );
  }
}

class _StoryAdvanceCue extends StatefulWidget {
  const _StoryAdvanceCue();

  @override
  State<_StoryAdvanceCue> createState() => _StoryAdvanceCueState();
}

class _StoryAdvanceCueState extends State<_StoryAdvanceCue> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1350),
    )..repeat(reverse: true);
    _opacity = Tween<double>(begin: .46, end: .96).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    _slide = Tween<Offset>(begin: const Offset(0, -.06), end: const Offset(0, .11)).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOutCubic));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(
        position: _slide,
        child: const _GameContinueGlyph(size: 34),
      ),
    );
  }
}

class _GameContinueGlyph extends StatelessWidget {
  const _GameContinueGlyph({this.size = 36});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          Transform.rotate(
            angle: .7853981633974483,
            child: Container(
              width: size * .52,
              height: size * .52,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(.08),
                border: Border.all(
                  color: const Color(0xFFF3EBDD).withOpacity(.42),
                  width: .75,
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: Colors.black.withOpacity(.18),
                    blurRadius: 9,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
            ),
          ),
          Icon(
            Icons.keyboard_arrow_down_rounded,
            size: size * .50,
            color: const Color(0xFFF6F1E7).withOpacity(.88),
            shadows: const <Shadow>[
              Shadow(color: Color(0x8A000000), blurRadius: 6),
            ],
          ),
        ],
      ),
    );
  }
}

class _NarratorHint extends StatefulWidget {
  const _NarratorHint({required this.text});
  final String text;

  @override
  State<_NarratorHint> createState() => _NarratorHintState();
}

class _NarratorHintState extends State<_NarratorHint> {
  bool revealed = false;

  @override
  Widget build(BuildContext context) {
    final hintText = widget.text.trim();

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => setState(() => revealed = !revealed),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topLeft,
        child: Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              revealed
                  ? '旁白提示：$hintText'
                  : '查看旁白提示',
              maxLines: revealed ? 4 : 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.left,
              style: TextStyle(
                color: Colors.white.withOpacity(revealed ? .86 : .78),
                fontSize: 11.2,
                height: 1.48,
                fontWeight: FontWeight.w600,
                letterSpacing: .12,
                shadows: const <Shadow>[
                  Shadow(
                    color: Color(0x8A000000),
                    blurRadius: 4,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}