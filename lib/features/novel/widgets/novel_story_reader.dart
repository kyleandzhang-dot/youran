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
    // 地图入口位于 NovelDialogPanel 外部，因此把逐字显示状态同步给
    // Controller。这样地图仍可随时查看，但“前往”会等当前段落读完。
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

    // 剧情页人物层只显示真正的立绘，不再把头像/首字母当成立绘顶上去。
    final portraitUrl = <String>[
      controller.currentPortraitUrl,
      character?.portraitUrl ?? '',
      sentence?.portraitUrl ?? '',
    ].map((value) => value.trim()).firstWhere(
          (value) => value.isNotEmpty,
          orElse: () => '',
        );

    final canShowChoices = controller.choices.isNotEmpty && !controller.hasNext && !controller.isGenerating && !_revealing;
    final inputEnabled = !controller.isGenerating && !_revealing && !controller.isCinematic && !controller.pendingFateRevert;

    final emptyTextFallback =
        controller.isGenerating ? '' : '等待故事继续…';

    return LayoutBuilder(
      builder: (context, constraints) {
        final screen = MediaQuery.sizeOf(context);
        final compact = screen.width <= 600;
        // 正文始终保持左右对称，不为右侧悬浮按钮预留宽度。
        // 1. 把高度和宽屏的判断提前
        final availableHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : screen.height - MediaQuery.paddingOf(context).vertical;
            
        final wideDialogueLayout = controller.desktopMode;

        const narrationRightSafeWidth = 0.0;
        
        // 2. 角色对话框右侧避让逻辑重构：
        // 手机端保持原样（动态避让）；
        // 电脑端直接锁死 0.0！我们完全依靠上一步加大的 outerHorizontal 来留白，
        // 这样可以彻底避免“剧情说完一瞬间，对话框突然往右跳一下”的视觉 Bug。
        final dialogueRightSafeWidth = wideDialogueLayout
            ? 0.0 
            : ((controller.hasNext || controller.isGenerating)
                ? (compact ? 58.0 : 70.0)
                : 0.0);
        final browsingStory = controller.hasNext;

        // 一级导航已移回右侧 HUD，不再占据底部。
        // 回看历史 / 逐字显示 / 生成中只影响输入区；底部只保留系统安全区。
        final composerVisible =
            !browsingStory && !controller.isGenerating && !_revealing;
        final surroundingsAction = NovelChoiceDockActionScope.maybeOf(context);
        final surroundingsActionVisible =
            composerVisible && surroundingsAction?.visible == true;
        final navigationHeight = MediaQuery.viewPaddingOf(context).bottom;
        final composerHeight = composerVisible
            ? _adaptiveFooterHeight(
                  availableWidth: constraints.maxWidth,
                  compact: compact,
                  choicesVisible: canShowChoices,
                ) +
                (surroundingsActionVisible ? (compact ? 22.0 : 24.0) : 0.0)
            : 0.0;
        final footerHeight = navigationHeight +
            (composerVisible ? composerHeight + (compact ? 4.0 : 6.0) : 0.0);
        final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
        final keyboardActive = compact && keyboardInset > 0;
        // 底部整块调查舞台当前隐藏，bottomReservedHeight 通常为 0。
        // “探索周围”恢复成输入框上方的轻量入口，其高度已计入 composerHeight。
        final reservedBottom = keyboardActive
            ? 0.0
            : math.max(0.0, widget.bottomReservedHeight);
        final composerBottom = keyboardActive ? keyboardInset : reservedBottom;
        final footerBottom = reservedBottom;

        // 选择区已经改成输入框上方的单行横向滑动条。
        // 无论有几个选项都只占一行，不能再按“选项数量 × 卡片高度”把正文往上顶。
        final choiceDockHeight = canShowChoices
            ? (compact ? 42.0 : 44.0)
            : 0.0;

        // 最后一条选择与自由输入框之间只保留轻微呼吸距离。
        final choiceBottomGap = compact ? 4.0 : 5.0;

        // 正文与选择区之间只留一条很小的安全距离。
        final contentChoiceGap = compact ? 5.0 : 6.0;

        // 剧情文字统一向屏幕底部收：只给输入栏 / 系统安全区留少量呼吸距离。
        // 底部大探索舞台暂时隐藏；正文只需避开输入框、轻量探索入口和选项条。
        final dialogGap = compact ? 18.0 : 24.0;
        final panelBottom = footerBottom + footerHeight + dialogGap;

        // 最后一句出现选项时，不再把正文整体按选项数量不断往上推。
        // 选择区上方只保留一个固定高度的“正文阅读窗口”：
        // 短正文自然居中/靠下显示；长正文直接在窗口内滚动。
        final choiceContentBottom = footerBottom +
            footerHeight +
            choiceBottomGap +
            choiceDockHeight +
            contentChoiceGap;
        // 最后一句正文不再使用固定比例/固定高度。
        // 上边界只避开顶部 HUD，其余整块屏幕空间都交给正文使用。
        // 正文从选择框上方向上自然生长；只有真正占满剩余屏幕后才滚动。
        final choiceContentTop =
            MediaQuery.paddingOf(context).top + (compact ? 74.0 : 86.0);
        final choiceAvailableContentHeight =
            (availableHeight - choiceContentTop - choiceContentBottom)
                .clamp(0.0, availableHeight)
                .toDouble();

        return GestureDetector(
          // 整个对话舞台都能接收横滑，而不是只有命中内部文字/按钮时才生效。
          behavior: HitTestBehavior.translucent,
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
              // 当前角色半身立绘。
              // 500×800 原图只显示顶部约 64%，避免把完整全身硬塞进画面。
              // NPC 靠左；主角/玩家靠右。
              if (mode != _NovelLineMode.narration && portraitUrl.isNotEmpty)
                Builder(
                  builder: (context) {
                    // 使用当前剧情舞台的真实尺寸，而不是全局 MediaQuery。
                    // 这样 PC 全宽舞台 / Web 手机预览 / 未来桌面窗口都不会出现
                    // “算的是整屏宽度，实际却被父级约束成 720px”的错位。
                    final stageSize = Size(constraints.maxWidth, availableHeight);

                    // 手机竖屏与电脑/横向宽屏使用两套真正不同的镜头语言。
                    // PC 不是“把手机版缩小”：说话角色固定成为左侧的大半身近景，
                    // 右侧留给较长对白，形成更接近视觉小说的面对面代入感。
                    final wideDialogueLayout = controller.desktopMode;

                    late final double portraitWidth;
                    late final double portraitHeightRatio;
                    late final double sinkRatio;
                    late final double edgePush;

                    if (wideDialogueLayout) {
                      final widthBased =
                          (stageSize.width * .55).clamp(550.0, 960.0).toDouble();
                      final heightBased =
                          (stageSize.height * 1.05).clamp(500.0, 1000.0).toDouble();
                      portraitWidth = math.min(widthBased, heightBased);
                      
                      portraitHeightRatio = 1.25; 
                      
                      // 【核心修改】：大幅度增加下沉比例！
                      // 从 0.18 直接拉高到 0.35（甚至 0.40）。
                      // 这意味着立绘高度的 35% 都会被硬生生拖进屏幕底部边界之外。
                      // 这下屏幕绝对能把腰部以下全部“一口吞掉”，只给你留下标准的胸像！
                      sinkRatio = 0.45; 
                      
                      edgePush = 0.08; 
                    } else {
                      // 手机竖屏保持原样...
                      // 手机竖屏继续保留原来的近景人物感与主角/NPC 左右关系。
                      const double minStage = 360.0;
                      const double maxStage = 700.0;
                      final double t = ((stageSize.width - minStage) /
                              (maxStage - minStage))
                          .clamp(0.0, 1.0);
                      final widthRatio = lerpDouble(.98, .76, t)!;
                      final minPortraitWidth = lerpDouble(400.0, 470.0, t)!;
                      final maxPortraitWidth = lerpDouble(600.0, 650.0, t)!;
                      portraitWidth = (stageSize.width * widthRatio)
                          .clamp(minPortraitWidth, maxPortraitWidth)
                          .toDouble();
                      portraitHeightRatio = 1.22;
                      sinkRatio = lerpDouble(.25, .16, t)!;
                      edgePush = lerpDouble(.35, .18, t)!;
                    }

                    final fullPortraitHeight = portraitWidth * portraitHeightRatio;
                    // PC 镜头固定：所有正在说话的角色都从左侧入镜。
                    // 手机仍保留 NPC 左 / 主角右的原有构图。
                    final showOnRight = !wideDialogueLayout &&
                        mode == _NovelLineMode.protagonist;
                    final sinkOffset = -(fullPortraitHeight * sinkRatio);
                    final npcLeftOffset = -(portraitWidth * edgePush);
                    final protagonistRightOffset = -(portraitWidth * edgePush);

                    return Positioned(
                      // 最后一页展开底部调查区时，人物立绘以调查区上沿作为新的
                      // “屏幕底部”，避免腿部和底部调查角色互相压在一起。
                      bottom: reservedBottom + sinkOffset,
                      left: showOnRight ? null : npcLeftOffset,
                      right: showOnRight ? protagonistRightOffset : null,
                      child: ValueListenableBuilder<String>(
                        valueListenable: _displayTextNotifier,
                        builder: (context, visibleText, _) {
                          final dialogueStarted =
                              _novelDialogueHasStarted(
                            sentence,
                            visibleText,
                          );
                          return AnimatedSlide(
                            // 人物随对白柔和入场，避免 180ms 的突然“弹出”感。
                            duration: const Duration(milliseconds: 340),
                            curve: Curves.easeOutCubic,
                            offset: dialogueStarted
                                ? Offset.zero
                                : Offset(showOnRight ? .04 : -.04, .008),
                            child: AnimatedOpacity(
                              duration: const Duration(milliseconds: 280),
                              curve: Curves.easeOutCubic,
                              opacity: dialogueStarted ? 1 : 0,
                              child: _withSwipeMotion(
                                IgnorePointer(
                                  child: SizedBox(
                                    width: portraitWidth,
                                    height: fullPortraitHeight,
                                    child: AnimatedSwitcher(
                                      duration:
                                          const Duration(milliseconds: 360),
                                      switchInCurve: Curves.easeOutCubic,
                                      switchOutCurve: Curves.easeInCubic,
                                      // 呼吸和前倾会略微超出原始图片边界；这里不裁切，
                                      // 避免头发顶部随着呼吸出现一条生硬的切线。
                                      layoutBuilder:
                                          (currentChild, previousChildren) =>
                                              Stack(
                                        alignment: Alignment.center,
                                        clipBehavior: Clip.none,
                                        children: <Widget>[
                                          ...previousChildren,
                                          if (currentChild != null)
                                            currentChild,
                                        ],
                                      ),
                                      transitionBuilder: (child, animation) =>
                                          FadeTransition(
                                        opacity: animation,
                                        child: child,
                                      ),
                                      child: _NovelPortraitMotion(
                                        key: ValueKey<String>(
                                          'portrait-motion|$portraitUrl',
                                        ),
                                        speaking: dialogueStarted,
                                        alignRight: showOnRight,
                                        child: _StagePortraitArtwork(
                                          url: portraitUrl,
                                          fit: BoxFit.cover,
                                          alignment: Alignment.topCenter,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                stageSize.width,
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),

              // 混合页只是把正文与对白安排在同一页，并不改变各自的视觉语义：
              // 正文仍留在独立的叙事区域，对白仍留在角色对白区域。
              if (mode != _NovelLineMode.narration &&
                  sentence?.hasMixedContent == true)
                Positioned(
                  left: 0,
                  right: narrationRightSafeWidth,
                  // 混合页有角色立绘时，把正文重心抬到屏幕中间偏上，
                  // 给下方/侧边人物留出更干净的视觉空间；没有立绘时保持原来的居中。
                  // 这里从页面一开始就按 portraitUrl 判定，避免立绘淡入后正文突然跳位。
                  top: canShowChoices ? choiceContentTop : 0,
                  bottom: canShowChoices ? choiceContentBottom : 0,
                  child: _withSwipeMotion(
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: compact ? 20 : 34,
                      ),
                      child: Align(
                        alignment: portraitUrl.isNotEmpty
                            ? const Alignment(0, -.36)
                            : Alignment.center,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 650),
                          child: _NovelMixedNarrationSurface(
                            sentence: sentence!,
                            displayTextListenable: _displayTextNotifier,
                            isRevealing: _revealing,
                            fontFamily: controller.settings.fontFamily,
                            fontSize: controller.settings.fontSize,
                            onTap: _handleStoryTap,
                          ),
                        ),
                      ),
                    ),
                    screen.width,
                  ),
                ),

              if (mode == _NovelLineMode.narration)
                if (canShowChoices)
                  Positioned(
                    left: 0,
                    right: narrationRightSafeWidth,
                    top: choiceContentTop,
                    bottom: choiceContentBottom,
                    child: _withSwipeMotion(
                      Padding(
                        // 右侧 HUD 只占窄列，正文仍保持主体居中。
                        padding: EdgeInsets.symmetric(
                          horizontal: compact ? 16 : 30,
                        ),
                      child: Align(
                        // 短正文始终贴着选择框上方；
                        // 内容增加时只向上扩展，不会跑到屏幕中间悬空。
                        alignment: Alignment.bottomCenter,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 650),
                          child: _NovelNarrationSurface(
                            key: ValueKey<String>('narration-${controller.currentSentenceIndex}'),
                            displayTextListenable: _displayTextNotifier,
                            emptyTextFallback: emptyTextFallback,
                            isGenerating: controller.isGenerating,
                            isRevealing: _revealing,
                            fontFamily: controller.settings.fontFamily,
                            fontSize: controller.settings.fontSize,
                            hasNext: controller.hasNext,
                            choices: controller.choices,
                            playerHint: controller.playerHint,
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
                  )
                else
                  Positioned(
                    left: 0,
                    right: narrationRightSafeWidth,
                    top: 0,
                    bottom: footerHeight + footerBottom +
                        (compact ? 18.0 : 24.0),
                    child: _withSwipeMotion(
                      Align(
                        // 普通剧情不再悬在屏幕中央，统一从底部向上生长。
                        // 这里本身没有灰色/半透明背景，只保留文字与轻量阴影。
                        alignment: Alignment.bottomCenter,
                      child: Padding(
                        // 右侧 HUD 保持轻量，不额外挤压旁白主体。
                        padding: EdgeInsets.symmetric(
                          horizontal: compact ? 16 : 30,
                        ),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: 650,
                            maxHeight: availableHeight * .60,
                          ),
                          child: _NovelNarrationSurface(
                            key: ValueKey<String>('narration-${controller.currentSentenceIndex}'),
                            displayTextListenable: _displayTextNotifier,
                            emptyTextFallback: emptyTextFallback,
                            isGenerating: controller.isGenerating,
                            isRevealing: _revealing,
                            fontFamily: controller.settings.fontFamily,
                            fontSize: controller.settings.fontSize,
                            hasNext: controller.hasNext,
                            choices: const <NovelChoice>[],
                            playerHint: controller.playerHint,
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
                  )
              else
                Positioned(
                  left: 0,
                  right: dialogueRightSafeWidth,
                  top: canShowChoices ? choiceContentTop : null,
                  bottom: canShowChoices ? choiceContentBottom : panelBottom,
                  child: ValueListenableBuilder<String>(
                    valueListenable: _displayTextNotifier,
                    builder: (context, visibleText, _) {
                      final dialogueStarted = _novelDialogueHasStarted(
                        sentence,
                        visibleText,
                      );
                      return IgnorePointer(
                        ignoring: !dialogueStarted,
                        child: AnimatedSlide(
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOutCubic,
                          offset: dialogueStarted
                              ? Offset.zero
                              : Offset(
                                  mode == _NovelLineMode.protagonist
                                      ? -.025
                                      : .025,
                                  0,
                                ),
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 180),
                            curve: Curves.easeOutCubic,
                            opacity: dialogueStarted ? 1 : 0,
                            child: _withSwipeMotion(
                              _NovelCharacterDialogueSurface(
                                key: ValueKey<String>(
                                  '${mode.name}-${controller.currentSentenceIndex}-$speaker',
                                ),
                                mode: mode,
                                desktopMode: controller.desktopMode,
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
                                hasNext: controller.hasNext,
                                choices: canShowChoices
                                    ? controller.choices
                                    : const <NovelChoice>[],
                                playerHint: controller.playerHint,
                                showPlayerHint: !_revealing &&
                                    !controller.hasNext &&
                                    !controller.isGenerating,
                                maxPanelHeight: canShowChoices
                                    ? choiceAvailableContentHeight
                                    : availableHeight *
                                        (compact ? .38 : .31),
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
                              : screen.width,
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
              if (_showSwipeHint &&
                  !canShowChoices &&
                  !controller.isGenerating &&
                  !_revealing &&
                  (controller.hasPrevious || controller.hasNext))
                Positioned(
                  // 左右保持统一安全边距；右侧功能入口独立悬浮。
                  left: compact ? 18 : 34,
                  right: compact ? 18 : 34,
                  // 回溯历史时进度条会出现在最底部，滑动提示居中放在它正上方。
                  bottom: footerBottom + footerHeight + (browsingStory ? 26 : 7),
                  child: const Center(
                    child: _LuxurySwipeHint(),
                  ),
                ),
              // 历史刻度贴近底部安全区；回看时输入区会自动收起。
              Positioned(
                left: compact ? 18 : 34,
                right: compact ? 18 : 34,
                bottom: footerBottom + navigationHeight + (compact ? 6 : 8),
                child: _StoryProgressLocator(
                  currentIndex: controller.currentSentenceIndex,
                  totalCount: controller.sentences.length,
                  isBrowsingHistory: browsingStory,
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
        physics: const BouncingScrollPhysics(),
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
        physics: const BouncingScrollPhysics(),
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
    final wideDialogueLayout = desktopMode;

    // 手机仍保持 NPC 左 / 主角右。
    // PC 镜头固定：角色永远在左，整个对白阅读区稳定放在右侧，
    // 避免主角/NPC 一开口界面就左右跳，画面会更像真正的视觉小说舞台。
    final sideAlignment = wideDialogueLayout
        ? Alignment.centerRight
        : (isHost ? Alignment.centerLeft : Alignment.centerRight);
    final bottomSideAlignment = wideDialogueLayout
        ? Alignment.bottomRight
        : (isHost ? Alignment.bottomLeft : Alignment.bottomRight);

    // PC 对白仍然比手机长，但不再无限铺满：
    // 左侧大半身人物约占 46%，右侧文字约占一半，二者共同构成画面。
    final dialogueWidth = compact
        ? (screen.width * .60).clamp(208.0, 350.0).toDouble()
        : wideDialogueLayout
            ? (screen.width * .52).clamp(500.0, 960.0).toDouble()
            : (screen.width * .50).clamp(360.0, 680.0).toDouble();

    final outerHorizontal = compact ? 9.0 : (wideDialogueLayout ? 120.0 : 20.0);

    final portraitFacingGap =
        compact ? 7.0 : (wideDialogueLayout ? 16.0 : 12.0);

    // 角色名直接嵌在线条中间：不再使用中央星星，也不再把名字放在线条下方。
    final shortNameLine = compact ? 28.0 : (wideDialogueLayout ? 46.0 : 38.0);
    final longNameLine = compact ? 48.0 : (wideDialogueLayout ? 86.0 : 70.0);
    final leftNameLine = isHost ? longNameLine : shortNameLine;
    final rightNameLine = isHost ? shortNameLine : longNameLine;

    final speakerHeaderWidth =
        compact ? 188.0 : (wideDialogueLayout ? 320.0 : 244.0);

    final dialogueContent = SizedBox(
      width: dialogueWidth,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: maxPanelHeight.clamp(0.0, 520.0).toDouble(),
        ),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
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
                    alignment: wideDialogueLayout
                        ? Alignment.centerLeft
                        : (isHost ? Alignment.centerRight : Alignment.centerLeft),
                    child: SizedBox(
                      width: speakerHeaderWidth,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: wideDialogueLayout
                            ? CrossAxisAlignment.start
                            : (isHost
                                ? CrossAxisAlignment.end
                                : CrossAxisAlignment.start),
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
                      alignment: wideDialogueLayout
                          ? Alignment.centerRight
                          : (isHost
                              ? Alignment.centerLeft
                              : Alignment.centerRight),
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
                  final alignment = wideDialogueLayout
                      ? TextAlign.left
                      : (isHost ? TextAlign.right : TextAlign.left);
                      
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
              right: wideDialogueLayout
                  ? 0
                  : (isHost ? portraitFacingGap : 0),
              left: wideDialogueLayout
                  ? portraitFacingGap
                  : (isHost ? 0 : portraitFacingGap),
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
