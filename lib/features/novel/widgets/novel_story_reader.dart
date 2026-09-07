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
    this.active = true,
    this.bottomReservedHeight = 0,
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

  /// 剧情页底部由外层占用的固定高度。
  /// 例如主页内嵌的走路探索区会占据屏幕底部，正文、选择框与输入栏
  /// 统一基于这个高度上移，而不是各自硬编码偏移。
  final double bottomReservedHeight;

  /// 剧情页虽然会被右侧一级 Tab 盖住，但 State 仍然保留。
  /// active=false 时必须暂停本地逐字 Timer，并停止打字音，避免后台继续“打字”。
  final bool active;

  @override
  State<NovelDialogPanel> createState() => _NovelDialogPanelState();
}

enum _NovelLineMode { narration, npc, protagonist }

class _NovelDialogPanelState extends State<NovelDialogPanel>
    with SingleTickerProviderStateMixin {
  Timer? _revealTimer;
  int _visibleLength = 0;
  String _lastIdentity = '';
  // 用户主动点“快速显示”后，当前句后续 SSE 继续补长时也保持全文直出 + 静音。
  // 用 identity 而不是全局 bool，进入下一句会自动恢复正常逐字与打字音。
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
    final next = MediaQuery.of(context).disableAnimations;
    if (next != _animationsDisabled) {
      _animationsDisabled = next;
      _syncReveal(force: true);
    }
  }

  void _handleInputTextChanged() {
    if (mounted) setState(() {});
  }

  bool get _revealInstantly =>
      _animationsDisabled || controller.settings.textSpeedCps <= 0;

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
      // “即时显示”是用户明确要求跳过逐字，不能因为 SSE 仍在生成而继续保留循环音效。
      unawaited(controller.bgm.stopTypingSound());
      return;
    }
    if (_revealing) _scheduleReveal();
  }

  double _adaptiveFooterHeight({
    required double availableWidth,
    required bool compact,
    required bool choicesVisible,
  }) {
    final base = compact ? 52.0 : 54.0;
    final text = widget.textController.text;
    if (text.isEmpty) return base;

    // 与实际输入栏宽度保持近似：页面主体最多 720，扣除继续按钮、幸运卡和发送键。
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
    return base + (lines - 1) * (compact ? 19.0 : 20.0);
  }

  // _syncReveal 会在句子变化 / SSE 补长时一次性更新 Unicode rune 缓存。
  // 逐字 Timer 不再每推进一个字符都把整段 String.runes.toList() 重做一遍。
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
    // 本地临时消息的毫秒时间戳在 completed copyWith 后保持不变，
    // 因而不会因为 temp id 被服务端正式 id 替换而重播当前页。
    final timestamp = message?.timestamp ?? 0;
    if (timestamp > 0) return 'timestamp:$timestamp';
    final id = message?.id.trim() ?? '';
    if (id.isNotEmpty) return id;
    return 'assistant-message';
  }

  void _syncReveal({bool force = false}) {
    final sentence = controller.currentSentence;
    // 后端已输出最终可展示的 currentSentence；前端不再做角色名/动作/引号解析。
    final full = _sanitizeNovelSentenceReaderText(sentence);

    // 必须把 assistant message id 放进 identity。
    // 否则新一轮回复如果仍是“第 0 句 + 同一个说话人 + 同一种类型”，
    // 会被误判成上一轮句子的 SSE 续写，继承旧的逐字与音效状态。
    final messageKey = _currentAssistantMessageKey;
    final identity =
        '$messageKey|${controller.currentSentenceIndex}|${sentence?.speakerName ?? ''}|${sentence?.type ?? ''}';

    if (force || identity != _lastIdentity) {
      _lastIdentity = identity;
      _lastFullText = full;
      _lastFullRunes = full.runes.toList(growable: false);
      _revealTimer?.cancel();
      _revealTimer = null;
      _visibleLength = 0;
      _displayTextNotifier.value = '';

      if (_revealInstantly || _skippedRevealIdentity == identity) {
        _visibleLength = _fullRuneLength;
        _publishVisibleText();
        _revealing = false;
        _typingSoundForReveal = false;
        return;
      }

      // 每页第一次展示时播放；即使当时仍在生成，完成后回看也不会重复响。
      final soundKey = '$messageKey|${controller.currentSentenceIndex}';
      _typingSoundForReveal = _typingSoundVisited.add(soundKey);

      _revealing = full.isNotEmpty;
      _scheduleReveal();
      return;
    }

    // SSE 继续补长同一句时保留已经打出的部分，不闪回。
    // 原代码拿 full.length 和实时 _fullText.length 比较，两者其实是同一个值，
    // 导致流式补长后 timer 已结束时无法重新启动。
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

    // --- 拟人化叙事节奏 ---
    int baseDelay = 1000 ~/ (controller.settings.textSpeedCps > 0 ? controller.settings.textSpeedCps : 20);
    int delayMs = baseDelay;
    
    if (afterCharacter.isNotEmpty) {
      final char = afterCharacter;
      if (char == '，' || char == '、' || char == ',') {
        delayMs = baseDelay * 3; // 短停顿，像讲述者的换气
      } else if (char == '。' || char == '！' || char == '？' || char == '!' || char == '?') {
        delayMs = baseDelay * 7; // 句末长停顿，留给玩家消化情绪
      } else if (char == '…' || char == '—' || char == '~' || char == '～') {
        delayMs = baseDelay * 5; // 情绪延展
      } else if (char == '\n') {
        delayMs = baseDelay * 10; // 换行大停顿，像翻开新的一页
      }
    }
    var delay = Duration(milliseconds: delayMs);

    // 流式首字先留一个很短的本地缓冲，让 SSE 至少积累 1~2 次刷新，
    // 避免“打一个字 -> 等网络 -> 又打一个字”的锯齿节奏。
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

      // 每一段首次逐字展示都播放；回退重看已经展示过的句子保持安静。
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

    // 生成中“追到当前流尾”不等于整句真正结束，此时让音轨按 idle grace 自然淡出，
    // 避免下一批 SSE 刚到又和一个尚未完成的显式 stop 互相打架。
    if (!controller.isGenerating) {
      unawaited(controller.bgm.stopTypingSound());
    }
  }

  void _handleStoryTap() {
    // 主动快速显示与“自然追到当前流尾”必须区分开：
    // 前者要锁定当前句为全文直出，后续 SSE 也不能重新启动逐字 Timer / 打字音。
    if (_revealing || controller.isGenerating) {
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
    controller.goNext();
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

    final canMove = direction < 0 ? controller.hasNext : controller.hasPrevious;
    if (!canMove) {
      await _springSwipeBack();
      return;
    }

    _swipeTransitioning = true;
    _swipeHintTimer?.cancel();
    if (_showSwipeHint && mounted) {
      setState(() => _showSwipeHint = false);
    }

    // 横滑是明确的翻页动作，不再被逐字动画吞掉。
    // 离场时保持当前已显示文字，不突然补全整句，视觉更稳定。
    if (_revealing) {
      _finishReveal();
    }
    await controller.bgm.stopTypingSound();
    if (!mounted) return;

    final width = MediaQuery.sizeOf(context).width;
    final exit = _swipeLimit(width) * (direction < 0 ? -1 : 1);

    try {
      // 旧内容顺着手势方向短距离离场 + 轻微淡出。
      await _animateSwipeTo(
        exit,
        duration: const Duration(milliseconds: 125),
        curve: Curves.easeOutCubic,
      );
      if (!mounted) return;

      if (direction < 0) {
        controller.goNext();
      } else {
        controller.goPrevious();
      }

      if (!mounted) return;

      // 新内容从相反方向轻轻进入。幅度刻意控制得很小，
      // 保留“剧情阅读器”的高级感，而不是整页卡片飞来飞去。
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

  void _handleHorizontalDragStart(DragStartDetails details) {
    if (widget.focusNode.hasFocus ||
        _swipeTransitioning) {
      return;
    }
    _swipeController.stop();
    _horizontalDragDistance = 0;
  }

  void _handleHorizontalDragUpdate(DragUpdateDetails details) {
    if (widget.focusNode.hasFocus ||
        _swipeTransitioning) {
      return;
    }

    _horizontalDragDistance += details.primaryDelta ?? 0;
    final width = MediaQuery.sizeOf(context).width;
    final limit = _swipeLimit(width);
    final wantsNext = _horizontalDragDistance < 0;
    final canMove = wantsNext ? controller.hasNext : controller.hasPrevious;

    // 可翻页时正常跟手；已经到头时增加阻尼，只让内容轻轻被“拉动”。
    final rawVisual = canMove
        ? _horizontalDragDistance
        : _horizontalDragDistance * .18;
    final visual = rawVisual.clamp(-limit, limit).toDouble();

    setState(() => _swipeVisualOffset = visual);
  }

  void _handleHorizontalDragEnd(DragEndDetails details) {
    if (widget.focusNode.hasFocus ||
        _swipeTransitioning) {
      _horizontalDragDistance = 0;
      if (_swipeVisualOffset != 0) {
        unawaited(_springSwipeBack());
      }
      return;
    }

    final velocity = details.primaryVelocity ?? 0;
    final distance = _horizontalDragDistance;

    // 慢滑看位移，快速轻扫看速度。两个条件满足任意一个即可。
    final hasEnoughDistance = distance.abs() >= 46;
    final hasEnoughVelocity = velocity.abs() >= 320;
    if (!hasEnoughDistance && !hasEnoughVelocity) {
      unawaited(_springSwipeBack());
      return;
    }

    final directionSource = hasEnoughDistance ? distance : velocity;
    final direction = directionSource < 0 ? -1 : 1;
    final canMove = direction < 0 ? controller.hasNext : controller.hasPrevious;

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
    final speaker = controllerSpeaker.isNotEmpty ? controllerSpeaker : sentenceSpeaker;
    final character = controller.currentSpeakerCharacter;
    final sentenceType = sentence?.type.toLowerCase().trim() ?? '';
    final isHost = sentence?.isProtagonist == true || character?.isMain == true;
    final hasSpeaker = speaker.isNotEmpty || character != null;
    final isNarration = sentence == null || (!hasSpeaker && (sentence.isNarration || sentenceType == 'narration' || sentenceType == 'action'));
    final mode = isNarration ? _NovelLineMode.narration : isHost ? _NovelLineMode.protagonist : _NovelLineMode.npc;

    final affection = mode == _NovelLineMode.npc ? character?.affection : null;
    final affectionPulse = mode == _NovelLineMode.npc
        ? controller.affectionPulseFor(character, speaker)
        : null;

    final avatarUrl = <String>[
      controller.currentAvatarUrl,
      character?.avatarUrl ?? '',
      sentence?.avatarUrl ?? '',
      character?.portraitUrl ?? '',
      sentence?.portraitUrl ?? '',
    ].map((value) => value.trim()).firstWhere(
          (value) => value.isNotEmpty,
          orElse: () => '',
        );

    final canShowChoices = controller.choices.isNotEmpty && !controller.hasNext && !controller.isGenerating && !_revealing;
    final inputEnabled = !controller.isGenerating && !_revealing && !controller.isCinematic && !controller.pendingFateRevert;

    final emptyTextFallback = controller.isGenerating ? '' : '等待故事继续…';

    return LayoutBuilder(
      builder: (context, constraints) {
        final screen = MediaQuery.sizeOf(context);
        final compact = screen.width <= 600;
        final availableHeight = constraints.maxHeight.isFinite ? constraints.maxHeight : screen.height - MediaQuery.paddingOf(context).vertical;
        final browsingStory = controller.hasNext;

        final composerVisible = !browsingStory && !controller.isGenerating && !_revealing;
        final navigationHeight = MediaQuery.viewPaddingOf(context).bottom;
        final composerHeight = composerVisible
            ? _adaptiveFooterHeight(availableWidth: constraints.maxWidth, compact: compact, choicesVisible: canShowChoices)
            : 0.0;
        final footerHeight = navigationHeight + (composerVisible ? composerHeight + (compact ? 4.0 : 6.0) : 0.0);
        final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
        final keyboardActive = compact && keyboardInset > 0;
        
        final reservedBottom = keyboardActive ? 0.0 : math.max(0.0, widget.bottomReservedHeight);
        final composerBottom = keyboardActive ? keyboardInset : reservedBottom;
        final footerBottom = reservedBottom;

        final choiceCount = controller.choices.length;
        final choiceHeaderExtent = compact ? 42.0 : 44.0;
        final choiceItemHeight = 48.0;
        final choiceItemGap = compact ? 5.0 : 6.0;
        final choiceDockHeight = canShowChoices
            ? choiceHeaderExtent + choiceCount * choiceItemHeight + (choiceCount > 1 ? (choiceCount - 1) * choiceItemGap : 0)
            : 0.0;
        final choiceBottomGap = compact ? 4.0 : 5.0;

        return SizedBox(
          width: double.infinity,
          height: availableHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              // 【核心修复1】：全屏点击热区，并通过 top: 80 强行避开顶部的系统菜单
              Positioned(
                top: 80,
                left: 0,
                right: 0,
                // 将 bottom 改为 composerBottom 加上一定的安全距离（例如 100）
                // 这样热区只覆盖画面中上部，底部留给摇杆和 UI
                bottom: composerBottom + 100.0, 
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: _handleStoryTap,
                  child: const SizedBox.expand(),
                ),
              ),

              if (mode == _NovelLineMode.protagonist)
                Positioned(
                  left: compact ? 10 : 22,
                  right: compact ? 10 : 22,
                  top: compact ? 84 : 96,
                  // 【核心修复2】：彻底删掉 _withSwipeMotion 外壳，消灭命中测试崩溃红屏 Bug
                  child: _NovelStageDialogueBubble(
                    sentence: sentence,
                    speakerName: speaker.isEmpty ? (mode == _NovelLineMode.protagonist ? controller.protagonistName : '角色') : speaker,
                    avatarUrl: avatarUrl,
                    isHost: mode == _NovelLineMode.protagonist,
                    displayTextListenable: _displayTextNotifier,
                    isGenerating: controller.isGenerating,
                    fontFamily: controller.settings.fontFamily,
                    fontSize: controller.settings.fontSize,
                    onTap: _handleStoryTap,
                  ),
                ),

              if (mode == _NovelLineMode.narration || sentence?.hasMixedContent == true)
                Positioned(
                  left: compact ? 14 : 30,
                  right: compact ? 14 : 30,
                  bottom: footerBottom + footerHeight + (canShowChoices ? choiceDockHeight + choiceBottomGap + 8.0 : (compact ? 8.0 : 12.0)),
                  // 【核心修复3】：同样删掉 _withSwipeMotion
                  child: _NovelStageNarrationStrip(
                    sentence: sentence,
                    displayTextListenable: _displayTextNotifier,
                    emptyTextFallback: emptyTextFallback,
                    isGenerating: controller.isGenerating,
                    fontFamily: controller.settings.fontFamily,
                    fontSize: controller.settings.fontSize,
                    onTap: _handleStoryTap,
                  ),
                ),

              if (canShowChoices && !controller.isGenerating && !_revealing)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: footerBottom + footerHeight + choiceBottomGap,
                  child: NovelChoiceDock(
                    choices: controller.choices,
                    onSelected: controller.selectChoice,
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
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _NovelStageDialogueBubble extends StatelessWidget {
  const _NovelStageDialogueBubble({
    required this.sentence,
    required this.speakerName,
    required this.avatarUrl,
    required this.isHost,
    required this.displayTextListenable,
    required this.isGenerating,
    required this.fontFamily,
    required this.fontSize,
    required this.onTap,
  });

  final NovelSentence? sentence;
  final String speakerName;
  final String avatarUrl;
  final bool isHost;
  final ValueListenable<String> displayTextListenable;
  final bool isGenerating;
  final String? fontFamily;
  final double fontSize;
  final VoidCallback onTap;

  Widget _avatarImage() {
    final source = avatarUrl.trim();
    if (source.isEmpty) {
      return const ColoredBox(
        color: Color(0xFFE9E9E6),
        child: Icon(Icons.person_rounded, color: Color(0xFF6C706D), size: 25),
      );
    }
    if (source.startsWith('assets/')) {
      return Image.asset(
        source,
        fit: BoxFit.cover,
        alignment: Alignment.topCenter,
        filterQuality: FilterQuality.high,
        errorBuilder: (_, __, ___) => const ColoredBox(
          color: Color(0xFFE9E9E6),
          child: Icon(Icons.person_rounded, color: Color(0xFF6C706D), size: 25),
        ),
      );
    }
    return Image.network(
      source,
      fit: BoxFit.cover,
      alignment: Alignment.topCenter,
      filterQuality: FilterQuality.high,
      errorBuilder: (_, __, ___) => const ColoredBox(
        color: Color(0xFFE9E9E6),
        child: Icon(Icons.person_rounded, color: Color(0xFF6C706D), size: 25),
      ),
    );
  }

  Widget _avatar(double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withOpacity(.92), width: 2),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x55000000),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: _avatarImage(),
    );
  }

  Widget _bubble({
    required BuildContext context,
    required String display,
    required TextStyle textStyle,
    required bool compact,
  }) {
    final tailOnRight = isHost;
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        Container(
          constraints: BoxConstraints(
            maxWidth: compact ? 282 : 470,
            maxHeight: compact ? 138 : 166,
          ),
          padding: EdgeInsets.fromLTRB(
            compact ? 14 : 17,
            compact ? 10 : 12,
            compact ? 14 : 17,
            compact ? 11 : 13,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFFF8F8F5),
            borderRadius: BorderRadius.circular(compact ? 15 : 17),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x3F000000),
                blurRadius: 14,
                offset: Offset(0, 5),
              ),
            ],
          ),
          child: SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment:
                  isHost ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  speakerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: const Color(0xFF6E716D),
                    fontSize: compact ? 10.2 : 11.2,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .7,
                  ),
                ),
                SizedBox(height: compact ? 4 : 6),
                if (display.isNotEmpty)
                  Text.rich(
                    TextSpan(
                      children: _buildNovelDialogueDisplaySpans(display, textStyle),
                    ),
                    textAlign: isHost ? TextAlign.right : TextAlign.left,
                  )
                else
                  Text('……', style: textStyle),
              ],
            ),
          ),
        ),
        Positioned(
          top: compact ? 19 : 22,
          left: tailOnRight ? null : -6,
          right: tailOnRight ? -6 : null,
          child: Transform.rotate(
            angle: math.pi / 4,
            child: const SizedBox(
              width: 13,
              height: 13,
              child: ColoredBox(color: Color(0xFFF8F8F5)),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width <= 600;
    final avatarSize = compact ? 44.0 : 50.0;
    return ValueListenableBuilder<String>(
      valueListenable: displayTextListenable,
      builder: (context, value, _) {
        final parts = _visibleReaderParts(sentence, value);
        final display = parts.dialogue.trim();
        if (display.isEmpty && !isGenerating) return const SizedBox.shrink();

        final textStyle = TextStyle(
          color: const Color(0xFF252827),
          fontFamily: fontFamily,
          fontSize: fontSize + (compact ? 0 : .5),
          height: 1.48,
          fontWeight: FontWeight.w600,
          letterSpacing: .08,
        );

        // NPC 的舞台立绘已经负责身份识别，阅读器兜底对白不再重复显示头像；
        // 主角仍保留原有头像。
        final avatar = isHost ? _avatar(avatarSize) : const SizedBox.shrink();
        final bubble = _bubble(
          context: context,
          display: display,
          textStyle: textStyle,
          compact: compact,
        );

        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: onTap,
          child: Align(
            alignment: isHost ? Alignment.centerRight : Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: isHost
                  ? <Widget>[
                      Flexible(child: bubble),
                      SizedBox(width: compact ? 11 : 13),
                      avatar,
                    ]
                  : <Widget>[
                      avatar,
                      SizedBox(width: compact ? 11 : 13),
                      Flexible(child: bubble),
                    ],
            ),
          ),
        );
      },
    );
  }
}

class _NovelStageNarrationStrip extends StatelessWidget {
  const _NovelStageNarrationStrip({
    required this.sentence,
    required this.displayTextListenable,
    required this.emptyTextFallback,
    required this.isGenerating,
    required this.fontFamily,
    required this.fontSize,
    required this.onTap,
  });

  final NovelSentence? sentence;
  final ValueListenable<String> displayTextListenable;
  final String emptyTextFallback;
  final bool isGenerating;
  final String? fontFamily;
  final double fontSize;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width <= 600;
    return ValueListenableBuilder<String>(
      valueListenable: displayTextListenable,
      builder: (context, value, _) {
        final parts = _visibleReaderParts(sentence, value);
        final isMixed = sentence?.hasMixedContent == true;
        final narration = isMixed
            ? <String>[
                _novelVisibleNarrationText(parts.leadingNarration).trim(),
                _novelVisibleNarrationText(parts.trailingNarration).trim(),
              ].where((part) => part.isNotEmpty).join(' ')
            : _novelVisibleNarrationText(value).trim();
        final display = narration.isNotEmpty
            ? narration
            : (value.isEmpty && !isGenerating ? emptyTextFallback : '');
        if (display.trim().isEmpty) return const SizedBox.shrink();

        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: onTap,
          child: Center(
            child: ConstrainedBox(
              // 1. 增加一个最大高度，防止上千字的超长文本直接顶穿屏幕
              constraints: BoxConstraints(
                maxWidth: compact ? 560 : 760,
                maxHeight: 280, 
              ),
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 13 : 18,
                  vertical: compact ? 8 : 10,
                ),
                decoration: const BoxDecoration(
                  color: Colors.transparent, // 保持全透明，没有丑陋的黑色遮罩
                ),
                // 2. 套一层滑动组件，让文字完整呈现。超长剧情可以在这里滑动看完
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Text(
                    display,
                    // 3. 核心修复：彻底删掉 maxLines: 3 和 overflow: TextOverflow.ellipsis！
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: const Color(0xEAF4F1EA),
                      fontFamily: fontFamily,
                      fontSize: math.max(12.0, fontSize - (compact ? 1.0 : .4)),
                      height: 1.5,
                      fontWeight: FontWeight.w500,
                      letterSpacing: .12,
                      shadows: const <Shadow>[
                        Shadow(color: Color(0xD0000000), blurRadius: 7),
                      ],
                    ),
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
  final ValueChanged<NovelChoice> onSelected;
  final VoidCallback onCustomInput;
  final VoidCallback onForceContinue;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width <= 600;
    
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: onTap,
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ValueListenableBuilder<String>(
              valueListenable: displayTextListenable,
              builder: (context, value, _) => TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: isRevealing ? 1.0 : 0.0),
                duration: const Duration(milliseconds: 600),
                curve: Curves.easeOutCubic,
                builder: (context, glow, child) {
                  final style = TextStyle(
                    color: const Color(0xFFF3F4F6),
                    fontFamily: fontFamily,
                    fontSize: fontSize + 2,
                    height: 1.90,
                    fontWeight: FontWeight.w500,
                    letterSpacing: .55,
                    shadows: <Shadow>[
                      Shadow(color: Color.lerp(const Color(0x99000000), const Color(0xD9000000), glow)!, blurRadius: 6 - 2 * glow, offset: const Offset(0, 1)),
                      Shadow(color: Color.lerp(const Color(0x66000000), const Color(0x80FFFFFF), glow)!, blurRadius: 12),
                    ],
                  );
                  return _NovelNarrationParagraphText(
                    value: value.isEmpty ? emptyTextFallback : value,
                    style: style,
                    textAlign: TextAlign.left,
                    paragraphSpacing: compact ? 9 : 11,
                  );
                },
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
      ),
    );
  }
}

class _NovelVisibleReaderParts {
  const _NovelVisibleReaderParts({
    this.leadingNarration = '',
    this.dialogue = '',
    this.trailingNarration = '',
  });

  final String leadingNarration;
  final String dialogue;
  final String trailingNarration;
}

_NovelVisibleReaderParts _visibleReaderParts(
  NovelSentence? sentence,
  String visibleText,
) {
  if (sentence == null || !sentence.hasMixedContent) {
    return _NovelVisibleReaderParts(dialogue: visibleText);
  }

  final leading = _sanitizeNovelStreamingText(sentence.leadingNarration);
  final dialogue = _sanitizeNovelStreamingText(sentence.text);
  final trailing = _sanitizeNovelStreamingText(sentence.trailingNarration);
  var remaining = visibleText.runes.length;

  String take(String value) {
    if (value.isEmpty || remaining <= 0) return '';
    final length = value.runes.length;
    final count = math.min(remaining, length).toInt();
    remaining -= count;
    return _novelPrefixByRunes(value, count);
  }

  void consumeGap() {
    if (remaining <= 0) return;
    // _sanitizeNovelSentenceReaderText 在相邻部分之间只插入一个换行。
    remaining = math.max(0, remaining - 1).toInt();
  }

  final visibleLeading = take(leading);
  // leading 剥符号前非空不代表它会显示任何东西——纯符号残留（比如只有一个
  // 孤立的 （ 或 *）剥完是空字符串，不值得为它扣一次“段落停顿”的预算。
  // dialogue 走的是 _buildNovelDialogueDisplaySpans，不做符号剥离，
  // 所以 dialogue 的 isNotEmpty 判断本身就是准的，不用同样处理。
  if (leading.isNotEmpty &&
      visibleLeading.runes.length >= leading.runes.length &&
      _novelVisibleNarrationText(leading).trim().isNotEmpty) {
    consumeGap();
  }
  final visibleDialogue = take(dialogue);
  if (dialogue.isNotEmpty &&
      visibleDialogue.runes.length >= dialogue.runes.length) {
    consumeGap();
  }
  final visibleTrailing = take(trailing);

  return _NovelVisibleReaderParts(
    leadingNarration: visibleLeading,
    dialogue: visibleDialogue,
    trailingNarration: visibleTrailing,
  );
}

bool _novelDialogueHasStarted(
  NovelSentence? sentence,
  String visibleText,
) {
  // 纯对白页从页面出现时就按原样展示；只有“正文 + 对白”混合页需要
  // 等逐字进度真正进入对白部分后，才让角色立绘、名字和对白区登场。
  if (sentence?.hasMixedContent != true) return true;
  return _visibleReaderParts(sentence, visibleText).dialogue.trim().isNotEmpty;
}

class _NovelMixedNarrationSurface extends StatelessWidget {
  const _NovelMixedNarrationSurface({
    required this.sentence,
    required this.displayTextListenable,
    required this.isRevealing,
    required this.fontFamily,
    required this.fontSize,
    required this.onTap,
  });

  final NovelSentence sentence;
  final ValueListenable<String> displayTextListenable;
  final bool isRevealing;
  final String? fontFamily;
  final double fontSize;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: onTap,
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: ValueListenableBuilder<String>(
          valueListenable: displayTextListenable,
          builder: (context, value, _) {
            final parts = _visibleReaderParts(sentence, value);
            // 用“剥符号之后真正会显示的文字”来判断是否渲染这个区块 / 插入间距，
            // 而不是原始文本是否非空——否则只剩纯符号（残留的半个 *、空的 （）标记）
            // 的片段，虽然视觉上什么都没有，依然会占一整行高度 + 12px 间距，
            // 看起来就像莫名多出一段大空白/换行。
            final hasLeading =
                _novelVisibleNarrationText(parts.leadingNarration).trim().isNotEmpty;
            final hasTrailing =
                _novelVisibleNarrationText(parts.trailingNarration).trim().isNotEmpty;
                
            return TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: isRevealing ? 1.0 : 0.0),
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOutCubic,
              builder: (context, glow, child) {
                final style = TextStyle(
                  color: const Color(0xFFF3F4F6),
                  fontFamily: fontFamily,
                  fontSize: fontSize + 1.4,
                  height: 1.86,
                  fontWeight: FontWeight.w500,
                  letterSpacing: .48,
                  shadows: <Shadow>[
                    Shadow(color: Color.lerp(const Color(0x99000000), const Color(0xD9000000), glow)!, blurRadius: 6 - 2 * glow, offset: const Offset(0, 1)),
                    Shadow(color: Color.lerp(const Color(0x66000000), const Color(0x80FFFFFF), glow)!, blurRadius: 12),
                  ],
                );
                
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    if (hasLeading)
                      _NovelNarrationParagraphText(
                        value: parts.leadingNarration,
                        style: style,
                        textAlign: TextAlign.left,
                      ),
                    if (hasLeading && hasTrailing) const SizedBox(height: 12),
                    if (hasTrailing)
                      _NovelNarrationParagraphText(
                        value: parts.trailingNarration,
                        style: style,
                        textAlign: TextAlign.left,
                      ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _NovelCharacterDialogueSurface extends StatelessWidget {
  const _NovelCharacterDialogueSurface({
    super.key,
    required this.mode,
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
    required this.maxPanelHeight,
    required this.onSelected,
    required this.onCustomInput,
    required this.onForceContinue,
    required this.onTap,
    this.onOpenPortrait,
  });

  final _NovelLineMode mode;
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
    final compact = screen.width <= 600;

    // NPC 在左 -> 对白固定到右侧。
    // 主角在右 -> 对白固定到左侧。
    final sideAlignment = isHost ? Alignment.centerLeft : Alignment.centerRight;
    final bottomSideAlignment =
        isHost ? Alignment.bottomLeft : Alignment.bottomRight;

    // 手机也坚持左右关系，但不能把正文压成极窄的一列。
    // 对话仍然属于左右两侧，而不是往屏幕中央收。
    // NPC 右侧文字 / 主角左侧文字都保留足够宽度，只和立绘拉开一点点距离。
    final dialogueWidth = compact
        ? (screen.width * .60).clamp(208.0, 350.0).toDouble()
        : (screen.width * .46).clamp(348.0, 610.0).toDouble();

    final outerHorizontal = compact ? 9.0 : 20.0;

    // 只和立绘拉开一点，不把整个对白推向屏幕中央。
    final portraitFacingGap = compact ? 7.0 : 12.0;

    // 角色名直接嵌在线条中间：不再使用中央星星，也不再把名字放在线条下方。
    // 左右线条保持轻微方向感，但提高亮度与厚度，复杂背景下也能看清。
    final shortNameLine = compact ? 28.0 : 38.0;
    final longNameLine = compact ? 48.0 : 70.0;
    final leftNameLine = isHost ? longNameLine : shortNameLine;
    final rightNameLine = isHost ? shortNameLine : longNameLine;

    final speakerHeaderWidth = compact ? 188.0 : 244.0;

    final dialogueContent = SizedBox(
      width: dialogueWidth,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: maxPanelHeight.clamp(0.0, 520.0).toDouble(),
        ),
        child: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Stack(
                children: <Widget>[
                  // 名字不再居中整个对话区。
                  // NPC 立绘在左 -> 名字贴在右侧对白区的左端；
                  // 主角立绘在右 -> 名字贴在左侧对白区的右端。
                  Align(
                    alignment:
                        isHost ? Alignment.centerRight : Alignment.centerLeft,
                    child: SizedBox(
                      width: speakerHeaderWidth,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: isHost
                            ? CrossAxisAlignment.end
                            : CrossAxisAlignment.start,
                        children: <Widget>[
                          SizedBox(
                            height: compact ? 26 : 29,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: <Widget>[
                                SizedBox(
                                  width: leftNameLine,
                                  child: Container(
                                    height: 1.05,
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.centerLeft,
                                        end: Alignment.centerRight,
                                        colors: <Color>[
                                          Colors.transparent,
                                          Colors.white.withOpacity(.28),
                                          Colors.white.withOpacity(.64),
                                        ],
                                        stops: const <double>[0, .40, 1],
                                      ),
                                    ),
                                  ),
                                ),
                                SizedBox(width: compact ? 8 : 10),
                                Flexible(
                                  child: _SpeakerIdentity(
                                    name: speakerName,
                                    affection: affection,
                                    isHost: isHost,
                                    affectionPulse: affectionPulse,
                                    onAffectionPulseConsumed:
                                        onAffectionPulseConsumed,
                                  ),
                                ),
                                SizedBox(width: compact ? 8 : 10),
                                SizedBox(
                                  width: rightNameLine,
                                  child: Container(
                                    height: 1.05,
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.centerLeft,
                                        end: Alignment.centerRight,
                                        colors: <Color>[
                                          Colors.white.withOpacity(.64),
                                          Colors.white.withOpacity(.28),
                                          Colors.transparent,
                                        ],
                                        stops: const <double>[0, .60, 1],
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
                  if (onOpenPortrait != null)
                    Align(
                      alignment: isHost
                          ? Alignment.centerLeft
                          : Alignment.centerRight,
                      child: _PortraitSwitchButton(onTap: onOpenPortrait!),
                    ),
                ],
              ),
              SizedBox(height: compact ? 7 : 10),

              ValueListenableBuilder<String>(
                valueListenable: displayTextListenable,
                builder: (context, value, _) {
                  final hasStoryText = sentence?.readerText.isNotEmpty == true;
                  final display = value.isEmpty && !hasStoryText
                      ? emptyTextFallback
                      : value;
                  final parts = _visibleReaderParts(sentence, display);
                  final alignment =
                      isHost ? TextAlign.right : TextAlign.left;
                      
                  return TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0, end: isRevealing ? 1.0 : 0.0),
                    duration: const Duration(milliseconds: 600),
                    curve: Curves.easeOutCubic,
                    builder: (context, glow, child) {
                      final style = TextStyle(
                        color: const Color(0xFFF4F1EA),
                        fontFamily: fontFamily,
                        fontSize: fontSize + (compact ? 0 : .4),
                        height: 1.82,
                        fontWeight: FontWeight.w500,
                        letterSpacing: .15,
                        shadows: <Shadow>[
                          Shadow(color: Color.lerp(const Color(0x99000000), const Color(0xD9000000), glow)!, blurRadius: 6 - 2 * glow, offset: const Offset(0, 1)),
                          Shadow(color: Color.lerp(const Color(0x66000000), const Color(0x80FFFFFF), glow)!, blurRadius: 12),
                        ],
                      );
                      
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          if (parts.dialogue.isNotEmpty)
                            Text.rich(
                              TextSpan(
                                children: _buildNovelDialogueDisplaySpans(
                                  parts.dialogue,
                                  style,
                                ),
                              ),
                              // NPC 在左：对白区在右，文字左对齐；
                              // 主角在右：对白区在左，文字右对齐。
                              textAlign: alignment,
                            ),
                        ],
                      );
                    },
                  );
                },
              ),
              if (showPlayerHint && playerHint.trim().isNotEmpty) ...<Widget>[
                const SizedBox(height: 12),
                _NarratorHint(text: playerHint),
              ],
            ],
          ),
        ),
      ),
    );

    // 角色对白不再铺任何深色背景 / 渐变卡片。
    // 只依靠正文自身的文字阴影保证复杂场景中的可读性。
    final readingZone = Padding(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 2 : 5,
        vertical: compact ? 2 : 4,
      ),
      child: dialogueContent,
    );

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: outerHorizontal),
        child: Align(
          alignment:
              choices.isNotEmpty ? bottomSideAlignment : sideAlignment,
          child: Padding(
            padding: EdgeInsets.only(
              right: isHost ? portraitFacingGap : 0,
              left: isHost ? 0 : portraitFacingGap,
            ),
            child: readingZone,
          ),
        ),
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
  // 沿用旧版“好感增加”动画的粉色，默认状态也直接使用这支颜色。
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

  /// 正反馈：弹起、回弹、轻微上浮，不抖动。
  /// 负反馈：只做短促左右震动 + 轻微收缩，不与正反馈共用同一种动作语言。
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
    // 好感度默认态始终使用实心粉色爱心，不再根据数值切换为空心。
    // 正负反馈只改变颜色 / 动画，不改变爱心的实心形态。
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

          // 负反馈：-X 轻微下坠，同时短促左右抖 3 次。
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
            // 角色名必须比正文和装饰线更亮，暗背景下第一眼就能识别。
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
                      // 默认就是旧版增加动画使用的粉色，不再回到半透明白。
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
    // 可直接放入你自己的游戏 UI PNG：assets/images/novel_continue.png
    // 推荐透明底、白/香槟色细线菱形 + 向下箭头，尺寸 96x96 或 128x128。
    return SizedBox(
      width: size,
      height: size,
      child: Image.asset(
        'assets/images/novel_continue.png',
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, __, ___) => Stack(
          alignment: Alignment.center,
          children: <Widget>[
            Transform.rotate(
              angle: .7853981633974483,
              child: Container(
                width: size * .56,
                height: size * .56,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(.10),
                  border: Border.all(color: const Color(0xFFF3EBDD).withOpacity(.48), width: .85),
                  boxShadow: <BoxShadow>[BoxShadow(color: Colors.black.withOpacity(.26), blurRadius: 12, offset: const Offset(0, 4))],
                ),
              ),
            ),
            Icon(Icons.keyboard_arrow_down_rounded, size: size * .54, color: const Color(0xFFF6F1E7).withOpacity(.92), shadows: const <Shadow>[Shadow(color: Color(0xB3000000), blurRadius: 7)]),
          ],
        ),
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
