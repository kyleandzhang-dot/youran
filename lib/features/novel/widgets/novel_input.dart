part of '../novel_widgets.dart';

// Novel Widgets · 自由输入
// 仅负责自由行动输入、语音输入、幸运卡入口与发送交互。

class NovelInputBar extends StatefulWidget {
  const NovelInputBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.socketService,
    required this.enabled,
    required this.luckyCardActive,
    required this.luckyCardCount,
    required this.onToggleLuckyCard,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final NovelSocketService socketService;
  final bool enabled;
  final bool luckyCardActive;
  final int luckyCardCount;
  final VoidCallback onToggleLuckyCard;
  final ValueChanged<String> onSend;

  @override
  State<NovelInputBar> createState() => _NovelInputBarState();
}

class _NovelInputBarState extends State<NovelInputBar> {
  static const Duration _maximumSpeechDuration = Duration(seconds: 30);
  static const Duration _speechTranscriptionTimeout = Duration(seconds: 10);

  late NovelAsrStreamService _asr;

  bool _hasText = false;
  bool _speechStarting = false;
  bool _isListening = false;
  bool _micHeld = false;
  bool _speechFinishing = false;
  String _speechBaseText = '';
  int _speechSessionId = 0;
  Future<void>? _startFuture;
  Stopwatch? _speechHoldWatch;
  Timer? _speechLimitTimer;

  @override
  void initState() {
    super.initState();
    _asr = NovelAsrStreamService(socketService: widget.socketService);
    widget.controller.addListener(_update);
    widget.focusNode.addListener(_updateFocus);
    _update();
  }

  @override
  void didUpdateWidget(covariant NovelInputBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_update);
      widget.controller.addListener(_update);
      _update();
    }
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_updateFocus);
      widget.focusNode.addListener(_updateFocus);
    }
    if (oldWidget.socketService != widget.socketService) {
      unawaited(_asr.dispose());
      _asr = NovelAsrStreamService(socketService: widget.socketService);
    }

    if (oldWidget.enabled && !widget.enabled &&
        (_isListening || _micHeld || _speechStarting || _asr.isSessionOpen)) {
      _micHeld = false;
      unawaited(_finishHoldListening(commit: false));
    }
  }

  void _update() {
    final next = widget.controller.text.trim().isNotEmpty;
    if (next != _hasText && mounted) setState(() => _hasText = next);
  }

  void _updateFocus() {
    if (mounted) setState(() {});
  }

  void _submit() {
    final text = widget.controller.text.trim();
    if (!widget.enabled || _isListening || _micHeld || _speechStarting || _speechFinishing || text.isEmpty) return;
    widget.onSend(text);
    widget.controller.clear();
    widget.focusNode.requestFocus();
  }

  void _insertNewline() {
    if (!widget.enabled || _isListening || _micHeld || _speechStarting || _speechFinishing) return;

    final value = widget.controller.value;
    final selection = value.selection;
    final start = selection.isValid ? selection.start : value.text.length;
    final end = selection.isValid ? selection.end : start;
    final nextText = value.text.replaceRange(start, end, '\n');

    widget.controller.value = value.copyWith(
      text: nextText,
      selection: TextSelection.collapsed(offset: start + 1),
      composing: TextRange.empty,
    );
  }

  KeyEventResult _handleInputKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent ||
        !widget.enabled ||
        _isListening ||
        _micHeld ||
        _speechStarting ||
        _speechFinishing) {
      return KeyEventResult.ignored;
    }

    final isEnter = event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter;
    if (!isEnter) return KeyEventResult.ignored;

    final composing = widget.controller.value.composing;
    if (composing.isValid && !composing.isCollapsed) {
      return KeyEventResult.ignored;
    }

    if (HardwareKeyboard.instance.isShiftPressed) {
      _insertNewline();
      return KeyEventResult.handled;
    }

    _submit();
    return KeyEventResult.handled;
  }

  String _mergeSpeechText(String base, String spoken) {
    final words = spoken.trim();
    if (words.isEmpty) return base;
    if (base.isEmpty) return words;
    if (RegExp(r'\s$').hasMatch(base)) return '$base$words';

    final last = base.runes.isEmpty ? 0 : base.runes.last;
    final first = words.runes.isEmpty ? 0 : words.runes.first;
    bool isCjk(int rune) =>
        (rune >= 0x3400 && rune <= 0x9FFF) ||
        (rune >= 0xF900 && rune <= 0xFAFF);

    return isCjk(last) && isCjk(first) ? '$base$words' : '$base $words';
  }

  void _commitSpeechText(int sessionId, String spoken) {
    if (!mounted || sessionId != _speechSessionId) return;
    final words = spoken.trim();
    if (words.isEmpty) return;

    final nextText = _mergeSpeechText(_speechBaseText, words);
    widget.controller.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextText.length),
      composing: TextRange.empty,
    );
  }

  Future<void> _beginHoldListening() async {
    if (!widget.enabled || _speechFinishing || _speechStarting || _micHeld) return;

    // 新一轮语音开始时立即清掉上一条轻提示，用户无需等 SnackBar 动画结束。
    ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar(
      reason: SnackBarClosedReason.hide,
    );

    final sessionId = ++_speechSessionId;
    _speechBaseText = widget.controller.text;
    _speechHoldWatch = Stopwatch()..start();
    _speechLimitTimer?.cancel();
    _speechLimitTimer = Timer(_maximumSpeechDuration, () {
      if (!mounted ||
          sessionId != _speechSessionId ||
          (!_micHeld && !_isListening && !_speechStarting)) {
        return;
      }
      // 最长录音 30 秒；到时自动按正常松手流程结束并开始转文字。
      unawaited(_finishHoldListening());
    });
    widget.focusNode.unfocus();
    if (mounted) {
      setState(() {
        _micHeld = true;
        _speechStarting = true;
      });
    }

    // 捕获本轮服务实例；超时后会替换 _asr，旧任务只能清理自己的实例，
    // 不会误取消用户紧接着开始的新一轮录音。
    final asr = _asr;
    final startFuture = asr.start();
    _startFuture = startFuture;
    try {
      await startFuture;
      if (!mounted || sessionId != _speechSessionId) {
        await asr.cancel();
        return;
      }
      setState(() {
        _speechStarting = false;
        _isListening = _micHeld;
      });
    } on NovelAsrStreamException catch (error) {
      if (!mounted || sessionId != _speechSessionId) return;
      _speechLimitTimer?.cancel();
      _speechLimitTimer = null;
      setState(() {
        _speechStarting = false;
        _isListening = false;
        _micHeld = false;
      });
      _showSpeechMessage(error.message);
    } catch (_) {
      if (!mounted || sessionId != _speechSessionId) return;
      _speechLimitTimer?.cancel();
      _speechLimitTimer = null;
      setState(() {
        _speechStarting = false;
        _isListening = false;
        _micHeld = false;
      });
      _showSpeechMessage('无法启动语音输入，请重试。');
    } finally {
      if (identical(_startFuture, startFuture)) _startFuture = null;
    }
  }

  Future<void> _finishHoldListening({bool commit = true}) async {
    if (_speechFinishing) return;

    _speechLimitTimer?.cancel();
    _speechLimitTimer = null;

    final sessionId = _speechSessionId;
    final asr = _asr;
    final hadActiveSession =
        _micHeld || _isListening || _speechStarting || asr.isSessionOpen;
    if (!hadActiveSession) return;

    final heldFor = _speechHoldWatch?.elapsed ?? Duration.zero;
    _speechHoldWatch?.stop();
    _speechHoldWatch = null;
    final tooShort = commit && heldFor < NovelAsrStreamService.minimumSpeechDuration;

    if (mounted) {
      setState(() {
        _micHeld = false;
        // 少于 1 秒属于误触：直接取消，不进入“正在转文字…”状态。
        _speechStarting = false;
        _isListening = false;
        _speechFinishing = commit && !tooShort;
      });
    } else {
      _micHeld = false;
      _speechStarting = false;
      _isListening = false;
      _speechFinishing = commit && !tooShort;
    }

    var speechCommitted = false;
    try {
      if (!commit || tooShort) {
        final starting = _startFuture;
        if (starting != null) {
          try {
            await starting;
          } catch (_) {
            // 启动异常已在 _beginHoldListening 中提示。
          }
        }
        if (sessionId != _speechSessionId) return;
        await asr.cancel();
        if (tooShort && mounted && sessionId == _speechSessionId) {
          _showSpeechMessage('说话太短了', lightweight: true);
        }
      } else {
        // “正在转文字…”从松手开始计时：等待 ASR 启动完成和最终结果
        // 合计最多 10 秒，超时后直接取消并忽略迟到结果。
        final finalText = await (() async {
          final starting = _startFuture;
          if (starting != null) {
            try {
              await starting;
            } catch (_) {
              // 启动异常已在 _beginHoldListening 中提示。
            }
          }
          if (sessionId != _speechSessionId || !asr.isSessionOpen) {
            return '';
          }
          return asr.stopAndGetFinal();
        })().timeout(_speechTranscriptionTimeout);

        if (finalText.trim().isNotEmpty) {
          _commitSpeechText(sessionId, finalText);
          speechCommitted = true;
        }
      }
    } on TimeoutException {
      // Future.timeout 不会终止底层任务，主动取消 ASR 会话；上面的
      // sessionId 校验和本地 await 链保证迟到结果不会写回输入框。
      unawaited(asr.dispose());
      if (identical(_asr, asr)) {
        _asr = NovelAsrStreamService(socketService: widget.socketService);
      }
      if (commit && mounted && sessionId == _speechSessionId) {
        _showSpeechMessage('识别超时，已放弃', lightweight: true);
      }
    } on NovelAsrStreamException catch (error) {
      if (commit && mounted && sessionId == _speechSessionId) {
        final code = error.code.trim().toUpperCase();
        if (code == 'AUDIO_TOO_SHORT') {
          _showSpeechMessage('说话太短了', lightweight: true);
        } else if (code == 'NO_VOICE' ||
            code == 'EMPTY_RESULT' ||
            code == 'EMPTY_AUDIO') {
          // “没说到话 / 没识别出来”都属于可立即重试的轻反馈，
          // 不使用黑色 SnackBar 卡片，避免打断下一次按住说话。
          _showSpeechMessage('未识别到语音', lightweight: true);
        } else {
          _showSpeechMessage(error.message);
        }
      }
    } catch (_) {
      if (commit && mounted && sessionId == _speechSessionId) {
        _showSpeechMessage('语音识别失败，请再试一次。');
      }
    } finally {
      if (!mounted || sessionId != _speechSessionId) return;
      setState(() {
        _speechStarting = false;
        _isListening = false;
        _speechFinishing = false;
      });
      // 误触 / 太短 / 无声时不要自动重新聚焦输入框，避免弹键盘阻碍再次按住语音。
      if (speechCommitted) {
        widget.focusNode.requestFocus();
      }
    }
  }

  void _showSpeechMessage(String message, {bool lightweight = false}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar(reason: SnackBarClosedReason.hide)
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
            textAlign: lightweight ? TextAlign.center : TextAlign.start,
            style: TextStyle(
              color: Colors.white,
              fontSize: lightweight ? 13 : 13,
              fontWeight: lightweight ? FontWeight.w600 : FontWeight.w400,
              shadows: lightweight
                  ? const <Shadow>[
                      Shadow(
                        color: Color(0xB3000000),
                        blurRadius: 5,
                        offset: Offset(0, 1),
                      ),
                    ]
                  : null,
            ),
          ),
          duration: Duration(milliseconds: lightweight ? 650 : 1400),
          behavior: SnackBarBehavior.floating,
          // 可立即重试的语音轻提示（如“说话太短了 / 未识别到语音”）
          // 不显示黑色卡片背景，只保留白字 + 轻微阴影。
          backgroundColor: lightweight
              ? Colors.transparent
              : Colors.black.withOpacity(.72),
          elevation: lightweight ? 0 : 4,
          padding: EdgeInsets.symmetric(
            horizontal: lightweight ? 4 : 14,
            vertical: lightweight ? 2 : 9,
          ),
          width: lightweight ? 112 : null,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(lightweight ? 0 : 12),
          ),
        ),
      );
  }

  @override
  void dispose() {
    _speechSessionId++;
    _micHeld = false;
    _speechLimitTimer?.cancel();
    _speechLimitTimer = null;
    _speechHoldWatch?.stop();
    _speechHoldWatch = null;
    widget.controller.removeListener(_update);
    widget.focusNode.removeListener(_updateFocus);
    unawaited(_asr.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final speaking = _micHeld || _isListening || _speechStarting;
    final speechBusy = speaking || _speechFinishing;
    final canSend = widget.enabled &&
        _hasText &&
        !speaking &&
        !_speechFinishing;
    final focused = widget.enabled && widget.focusNode.hasFocus;
    // 只要输入框已有文字（键盘输入或语音转写），即使失焦也保持深色玻璃，
    // 避免场景背景直接穿透导致已输入内容看不清。
    final glassActive = focused || _hasText;
    final lowPowerEffects = _useLowPowerNovelEffects(context);
    // 正在连接时也必须继续接收 pointerUp，否则用户松手会丢失结束事件。
    final micEnabled = widget.enabled && !_speechFinishing;

    return AnimatedOpacity(
        opacity: widget.enabled ? 1 : .50,
        duration: const Duration(milliseconds: 160),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            if (widget.luckyCardCount > 0) ...<Widget>[
              ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: _AdaptiveBackdropBlur(
                    sigma: 14,
                    child: Material(
                      color: widget.luckyCardActive
                          ? NovelPalette.accent.withOpacity(.12)
                          : Colors.white.withOpacity(.045),
                      child: InkWell(
                        onTap: widget.enabled ? widget.onToggleLuckyCard : null,
                        child: Container(
                          width: 44,
                          height: 50,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: widget.luckyCardActive
                                  ? NovelPalette.accent.withOpacity(.40)
                                  : Colors.white.withOpacity(.12),
                              width: .65,
                            ),
                          ),
                          child: Stack(fit: StackFit.expand, children: <Widget>[
                            const Padding(
                                padding: EdgeInsets.all(11),
                                child: NovelArtwork(
                                  assetCandidates: <String>['assets/images/lucky_card.webp'],
                                  fit: BoxFit.contain,
                                  fallbackIcon: Icons.auto_awesome_outlined,
                                )),
                            Positioned(
                                top: 3,
                                right: 3,
                                child: Container(
                                  constraints: const BoxConstraints(minWidth: 15),
                                  height: 15,
                                  padding: const EdgeInsets.symmetric(horizontal: 3),
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(color: NovelPalette.text, borderRadius: BorderRadius.circular(5)),
                                  child: Text('${widget.luckyCardCount}', style: const TextStyle(color: Color(0xFF111512), fontSize: 8.5, fontWeight: FontWeight.w900)),
                                )),
                          ]),
                        ),
                      ),
                    ),
                  )),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                // 桌面端保留局部毛玻璃；手机 / 关闭动画模式下由自适应层直接跳过
                // BackdropFilter，避免输入时持续触发昂贵的背景采样与合成。
                child: _AdaptiveBackdropBlur(
                  sigma: glassActive ? 10 : 16,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 170),
                    constraints: const BoxConstraints(minHeight: 50, maxHeight: 128),
                    padding: const EdgeInsets.fromLTRB(12, 6, 5, 6),
                    decoration: BoxDecoration(
                      // 聚焦或已有文字时只保留一层很浅的暗色玻璃。
                      // 聚焦态更通透，仍依靠 12px 模糊保证亮背景上的文字可读。
                      color: glassActive
                          ? Colors.black.withOpacity(
                              lowPowerEffects ? .22 : (focused ? .16 : .12),
                            )
                          : Colors.white.withOpacity(speechBusy ? .085 : .045),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: speechBusy
                            ? NovelPalette.accent.withOpacity(.72)
                            : Colors.white.withOpacity(focused ? .32 : (glassActive ? .22 : .14)),
                        width: speechBusy ? .9 : .65,
                      ),
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: Colors.black.withOpacity(glassActive ? .11 : .08),
                          blurRadius: glassActive ? 10 : 7,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: <Widget>[
                        Padding(
                          padding: const EdgeInsets.only(bottom: 1),
                          child: Listener(
                            behavior: HitTestBehavior.opaque,
                            onPointerDown: micEnabled
                                ? (_) => unawaited(_beginHoldListening())
                                : null,
                            onPointerUp: micEnabled
                                ? (_) => unawaited(_finishHoldListening())
                                : null,
                            onPointerCancel: micEnabled
                                ? (_) => unawaited(_finishHoldListening(commit: false))
                                : null,
                            child: AnimatedOpacity(
                              duration: const Duration(milliseconds: 120),
                              opacity: micEnabled ? 1 : .42,
                              child: AnimatedScale(
                                scale: speaking ? 1.08 : 1,
                                duration: const Duration(milliseconds: 120),
                                child: SizedBox(
                                  width: 36,
                                  height: 36,
                                  child: CustomPaint(
                                    painter: _CutoutVoiceWavePainter(
                                      speaking: speaking,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Focus(
                            onKeyEvent: _handleInputKey,
                            child: TextField(
                              controller: widget.controller,
                              focusNode: widget.focusNode,
                              enabled: widget.enabled && !speaking && !_speechFinishing,
                              minLines: 1,
                              maxLines: 5,
                              keyboardType: TextInputType.multiline,
                              textInputAction: TextInputAction.send,
                              onSubmitted: (_) => _submit(),
                              cursorColor: NovelPalette.accent,
                              style: const TextStyle(color: Color(0xFFF4F3EE), fontSize: 14, height: 1.35, fontWeight: FontWeight.w400),
                              decoration: InputDecoration(
                                hintText: _speechFinishing
                                    ? '正在转文字…'
                                    : speaking
                                        ? '正在听… 松开后转成文字'
                                        : (widget.luckyCardActive
                                            ? '运气已加持，描述你的行动…'
                                            : '描述你想做的事…'),
                                hintStyle: TextStyle(
                                  color: speechBusy
                                      ? NovelPalette.accent.withOpacity(.76)
                                      : Colors.white.withOpacity(focused ? .48 : .32),
                                  fontSize: 13.2,
                                  fontWeight: FontWeight.w400,
                                ),
                                isDense: true,
                                contentPadding: const EdgeInsets.only(top: 8, bottom: 12),
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                disabledBorder: InputBorder.none,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 1),
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 150),
                            opacity: canSend ? 1 : .34,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              curve: Curves.easeOutCubic,
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: canSend
                                    ? NovelPalette.accent
                                    : Colors.white.withOpacity(.055),
                                borderRadius: BorderRadius.circular(3),
                                border: Border.all(
                                  color: canSend
                                      ? NovelPalette.accent.withOpacity(.92)
                                      : Colors.white.withOpacity(.10),
                                  width: .65,
                                ),
                                boxShadow: const <BoxShadow>[],
                              ),
                              child: Material(
                                color: Colors.transparent,
                                borderRadius: BorderRadius.circular(3),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(3),
                                  onTap: canSend ? _submit : null,
                                  child: Center(
                                    child: Icon(
                                      Icons.arrow_upward_rounded,
                                      size: 17,
                                      color: canSend
                                        ? Colors.white
                                        : Colors.white.withOpacity(.52),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )
          ],
        ));
  }
}
