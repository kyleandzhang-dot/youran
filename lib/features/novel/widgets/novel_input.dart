part of '../novel_widgets.dart';

// Novel Widgets · 自由输入
// 仅负责自由行动输入、语音输入、幸运卡入口与发送交互。

class NovelInputBar extends StatefulWidget {
  const NovelInputBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.socketService,
    this.gameController,
    required this.enabled,
    required this.luckyCardActive,
    required this.luckyCardCount,
    required this.onToggleLuckyCard,
    required this.onSend,
    this.targetActorName = '',
    this.targetActorAvatarUrl = '',
    this.targetActorPlaceholder = '',
    this.onClearTargetActor,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final NovelSocketService socketService;
  final NovelGameController? gameController;
  final bool enabled;
  final bool luckyCardActive;
  final int luckyCardCount;
  final VoidCallback onToggleLuckyCard;
  final ValueChanged<String> onSend;
  final String targetActorName;
  final String targetActorAvatarUrl;
  final String targetActorPlaceholder;
  final VoidCallback? onClearTargetActor;

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

  final LayerLink _inventoryLink = LayerLink();
  OverlayEntry? _inventoryOverlay;
  bool _inventoryRefreshing = false;
  String _inventoryCategory = '物品';
  final Set<String> _referencedItemNames = <String>{};

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

    if (oldWidget.enabled && !widget.enabled) {
      _closeInventoryPicker();
    }

    if (oldWidget.enabled && !widget.enabled &&
        (_isListening || _micHeld || _speechStarting || _asr.isSessionOpen)) {
      _micHeld = false;
      unawaited(_finishHoldListening(commit: false));
    }
  }

  void _update() {
    final next = widget.controller.text.trim().isNotEmpty;
    final changed = next != _hasText;
    _hasText = next;
    if (changed && mounted) setState(() {});
  }

  void _updateFocus() {
    if (mounted) setState(() {});
  }

  List<NovelInventoryItem> _referenceableInventoryItems() {
    final data = widget.gameController?.inventory;
    if (data == null) return const <NovelInventoryItem>[];

    final result = <NovelInventoryItem>[];
    final seen = <String>{};
    for (final item in <NovelInventoryItem>[
      ...data.storyItems,
      ...data.consumables,
    ]) {
      if (item.quantity <= 0 || item.isEquipped) continue;
      if (item.itemType.trim().toLowerCase() == 'lucky_card') continue;
      final key = item.id.trim().isNotEmpty
          ? 'id:${item.id.trim()}'
          : '${item.itemType.trim()}:${item.name.trim()}';
      if (seen.add(key)) result.add(item);
    }
    return result;
  }

  String _referenceItemTypeLabel(NovelInventoryItem item) {
    return switch (item.itemType.trim().toLowerCase()) {
      'consumable' => '消耗品',
      'material' => '材料',
      'quest' => '任务物品',
      'gift' => '赠礼',
      'blind_box' => '特殊物品',
      'weapon' || 'handheld' => '手持',
      'wearable' || 'armor' => '穿戴',
      'accessory' => '饰品',
      _ => '物品',
    };
  }

  bool _isReferenceEquipment(NovelInventoryItem item) {
    final type = item.itemType.trim().toLowerCase();
    return const <String>{
      'weapon',
      'handheld',
      'wearable',
      'armor',
      'accessory',
      'head',
      'face',
      'upper',
      'lower',
      'feet',
      'back',
    }.contains(type);
  }


  bool _isItemReferenced(NovelInventoryItem item) {
    final name = item.name.trim();
    return name.isNotEmpty && _referencedItemNames.contains(name);
  }

  List<NovelInventoryItem> _activeReferencedItems() {
    return _referenceableInventoryItems().where(_isItemReferenced).toList();
  }

  void _removeInventoryReference(NovelInventoryItem item) {
    final name = item.name.trim();
    if (name.isEmpty || !_referencedItemNames.contains(name)) return;

    unawaited(HapticFeedback.selectionClick());
    setState(() => _referencedItemNames.remove(name));
    _inventoryOverlay?.markNeedsBuild();
  }

  void _insertInventoryReference(NovelInventoryItem item) {
    final name = item.name.trim();
    if (name.isEmpty) return;

    unawaited(HapticFeedback.selectionClick());
    setState(() {
      if (_referencedItemNames.contains(name)) {
        _referencedItemNames.remove(name);
      } else {
        _referencedItemNames.add(name);
      }
    });
    _inventoryOverlay?.markNeedsBuild();
  }

  void _closeInventoryPicker() {
    final entry = _inventoryOverlay;
    _inventoryOverlay = null;
    if (entry != null && entry.mounted) entry.remove();
    if (entry != null && mounted) setState(() {});
  }

  Future<void> _refreshInventoryPicker() async {
    final gameController = widget.gameController;
    if (gameController == null || _inventoryRefreshing) return;
    _inventoryRefreshing = true;
    _inventoryOverlay?.markNeedsBuild();
    try {
      await gameController.refreshInventory(notify: false);
    } catch (_) {
      // 引用面板刷新失败时保留 Controller 当前已有的背包快照，不打断输入。
    } finally {
      _inventoryRefreshing = false;
      _inventoryOverlay?.markNeedsBuild();
    }
  }

  void _toggleInventoryPicker() {
    if (_inventoryOverlay != null) {
      _closeInventoryPicker();
      return;
    }
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null || widget.gameController == null) return;

    _inventoryOverlay = OverlayEntry(
      builder: (overlayContext) {
        final screenWidth = MediaQuery.sizeOf(overlayContext).width;
        final panelWidth = math.min(318.0, math.max(244.0, screenWidth - 24));
        final items = _referenceableInventoryItems();
        const categoryLabels = <String>['物品', '装备'];
        if (!categoryLabels.contains(_inventoryCategory)) {
          _inventoryCategory = '物品';
        }
        final visibleItems = items.where((item) {
          final equipment = _isReferenceEquipment(item);
          return _inventoryCategory == '装备' ? equipment : !equipment;
        }).toList();
        final selectedCount = items.where(_isItemReferenced).length;

        return Stack(
          children: <Widget>[
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _closeInventoryPicker,
              ),
            ),
            CompositedTransformFollower(
              link: _inventoryLink,
              showWhenUnlinked: false,
              targetAnchor: Alignment.topLeft,
              followerAnchor: Alignment.bottomLeft,
              offset: const Offset(-10, -8),
              child: Material(
                color: Colors.transparent,
                child: ClipRRect(
                  borderRadius: BorderRadius.zero,
                  child: BackdropFilter(
                    filter: ImageFilter.blur(
                      sigmaX: 46,
                      sigmaY: 46,
                      tileMode: TileMode.clamp,
                    ),
                    child: Container(
                      width: panelWidth,
                      constraints: const BoxConstraints(maxHeight: 310),
                      decoration: BoxDecoration(
                        color: const Color(0x66121513),
                        borderRadius: BorderRadius.zero,
                        border: Border.all(
                          color: Colors.white.withOpacity(.12),
                          width: .65,
                        ),
                        boxShadow: const <BoxShadow>[
                          BoxShadow(
                            color: Color(0x16000000),
                            blurRadius: 12,
                            offset: Offset(0, 5),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          SizedBox(
                            height: 48,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(12, 0, 11, 0),
                              child: Row(
                                children: <Widget>[
                                  Expanded(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: <Widget>[
                                        Text(
                                          '引用物品',
                                          style: TextStyle(
                                            color: Colors.white.withOpacity(.94),
                                            fontSize: 12.3,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: .12,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          items.isEmpty
                                              ? '当前没有可引用物品'
                                              : selectedCount > 0
                                                  ? '已选择 $selectedCount 件 · 再次点击取消'
                                                  : '点击物品即可引用',
                                          style: TextStyle(
                                            color: Colors.white.withOpacity(.46),
                                            fontSize: 9.4,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (_inventoryRefreshing) ...<Widget>[
                                    SizedBox.square(
                                      dimension: 12,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 1.3,
                                        color: Colors.white.withOpacity(.72),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                  Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: _closeInventoryPicker,
                                      splashColor: Colors.white.withOpacity(.06),
                                      highlightColor: Colors.white.withOpacity(.03),
                                      child: SizedBox(
                                        width: 28,
                                        height: 28,
                                        child: Center(
                                          child: Icon(
                                            Icons.close_rounded,
                                            size: 17,
                                            color: Colors.white.withOpacity(.78),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Container(
                            height: .65,
                            color: Colors.white.withOpacity(.075),
                          ),
                          if (categoryLabels.length > 1) ...<Widget>[
                            SizedBox(
                              height: 35,
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(10, 6, 10, 5),
                                child: Row(
                                  children: <Widget>[
                                    for (var index = 0; index < categoryLabels.length; index++) ...<Widget>[
                                      if (index > 0) const SizedBox(width: 16),
                                      Builder(
                                        builder: (context) {
                                          final label = categoryLabels[index];
                                          final selected = label == _inventoryCategory;
                                          return InkWell(
                                            onTap: () {
                                              if (_inventoryCategory == label) return;
                                              setState(() => _inventoryCategory = label);
                                              _inventoryOverlay?.markNeedsBuild();
                                            },
                                            splashColor: Colors.white.withOpacity(.05),
                                            highlightColor: Colors.white.withOpacity(.025),
                                            child: Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 1, vertical: 4),
                                              child: Text(
                                                label,
                                                style: TextStyle(
                                                  color: Colors.white.withOpacity(selected ? .96 : .43),
                                                  fontSize: 10.2,
                                                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                                                ),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                            Container(
                              height: .55,
                              color: Colors.white.withOpacity(.055),
                            ),
                          ],
                          if (items.isEmpty && !_inventoryRefreshing)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 24),
                              child: Text(
                                '背包里暂无可引用物品',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(.42),
                                  fontSize: 10.8,
                                ),
                              ),
                            )
                          else if (visibleItems.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 20),
                              child: Text(
                                '该分类暂无可引用物品',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(.38),
                                  fontSize: 10.6,
                                ),
                              ),
                            )
                          else
                            Flexible(
                              child: ListView.separated(
                                shrinkWrap: true,
                                physics: const BouncingScrollPhysics(),
                                padding: const EdgeInsets.fromLTRB(7, 7, 7, 8),
                                itemCount: visibleItems.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 3),
                                itemBuilder: (context, index) {
                                  final item = visibleItems[index];
                                  return _InventoryReferenceTile(
                                    name: item.name,
                                    typeLabel: _referenceItemTypeLabel(item),
                                    description: item.description,
                                    referenced: _isItemReferenced(item),
                                    onTap: () => _insertInventoryReference(item),
                                  );
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
    overlay.insert(_inventoryOverlay!);
    if (mounted) setState(() {});
    unawaited(_refreshInventoryPicker());
  }

  void _submit() {
    _closeInventoryPicker();
    final visibleText = widget.controller.text.trim();
    final referencedItems = _activeReferencedItems();
    if (!widget.enabled ||
        _isListening ||
        _micHeld ||
        _speechStarting ||
        _speechFinishing ||
        (visibleText.isEmpty && referencedItems.isEmpty)) {
      return;
    }

    final references = referencedItems
        .map((item) => '〔${item.name.trim()}〕')
        .join();
    final sendText = visibleText.isEmpty
        ? '使用$references'
        : references.isEmpty
            ? visibleText
            : '$visibleText $references';

    widget.onSend(sendText);
    widget.controller.clear();
    if (_referencedItemNames.isNotEmpty) {
      setState(_referencedItemNames.clear);
    }
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

  Widget _buildReferencedItemChip(NovelInventoryItem item) {
    return _ReferencedInventoryChip(
      name: item.name,
      description: item.description,
      onRemove: () => _removeInventoryReference(item),
    );
  }

  @override
  void dispose() {
    final inventoryEntry = _inventoryOverlay;
    _inventoryOverlay = null;
    if (inventoryEntry != null && inventoryEntry.mounted) inventoryEntry.remove();
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
    final referencedItems = _activeReferencedItems();
    final canSend = widget.enabled &&
        (_hasText || referencedItems.isNotEmpty) &&
        !speaking &&
        !_speechFinishing;
    final focused = widget.enabled && widget.focusNode.hasFocus;
    // 只要输入框已有文字（键盘输入或语音转写），即使失焦也保持深色玻璃，
    // 避免场景背景直接穿透导致已输入内容看不清。
    final glassActive = focused || _hasText;
    final lowPowerEffects = _useLowPowerNovelEffects(context);
    // 正在连接时也必须继续接收 pointerUp，否则用户松手会丢失结束事件。
    final micEnabled = widget.enabled && !_speechFinishing;
    final inventoryPickerOpen = _inventoryOverlay != null;
    final viewport = NovelViewportMetrics.of(
      context,
      desktopMode: widget.gameController?.desktopMode ?? false,
    );
    final shortViewport = viewport.shortViewport;
    final shortWide = viewport.shortWide;
    final targetActorName = widget.targetActorName.trim();
    final targetActorActive = targetActorName.isNotEmpty;
    final contextChips = <Widget>[
      if (targetActorActive)
        _TargetActorContextChip(
          name: targetActorName,
          avatarUrl: widget.targetActorAvatarUrl.trim(),
          onClear: widget.onClearTargetActor,
        ),
      for (final item in referencedItems) _buildReferencedItemChip(item),
    ];

    return AnimatedOpacity(
        opacity: widget.enabled ? 1 : .50,
        duration: const Duration(milliseconds: 160),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            if (widget.luckyCardCount > 0) ...<Widget>[
              ClipRRect(
                  borderRadius: BorderRadius.zero,
                  child: _AdaptiveBackdropBlur(
                    sigma: 14,
                    child: Material(
                      color: widget.luckyCardActive
                          ? NovelPalette.accent.withOpacity(.12)
                          : Colors.white.withOpacity(.045),
                      child: InkWell(
                        onTap: widget.enabled ? widget.onToggleLuckyCard : null,
                        child: Container(
                          width: shortViewport ? 40 : 44,
                          height: shortViewport ? 44 : 50,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.zero,
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
              const SizedBox(width: 4),
            ],
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (contextChips.isNotEmpty) ...<Widget>[
                    // 对话目标和引用物品是同一层“输入上下文”：角色优先，其后是物品引用。
                    SizedBox(
                      height: shortViewport ? 26 : 30,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        itemCount: contextChips.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 5),
                        itemBuilder: (context, index) => contextChips[index],
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],
                  ClipRRect(
                    borderRadius: BorderRadius.zero,
                    child: _AdaptiveBackdropBlur(
                      sigma: glassActive ? 10 : 16,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 170),
                        constraints: BoxConstraints(
                          minHeight: shortViewport ? 44 : 50,
                          maxHeight: shortViewport ? 118 : 158,
                        ),
                        padding: EdgeInsets.fromLTRB(
                          shortViewport ? 8 : 10,
                          shortViewport ? 4 : 6,
                          5,
                          shortViewport ? 4 : 6,
                        ),
                        decoration: BoxDecoration(
                          color: glassActive
                              ? Colors.black.withOpacity(
                                  lowPowerEffects ? .22 : (focused ? .16 : .12),
                                )
                              : Colors.white.withOpacity(speechBusy ? .075 : .04),
                          borderRadius: BorderRadius.zero,
                          border: Border.all(
                            // 竖屏、横屏、电脑统一使用同一套高可见度边线，
                            // 不再让非横屏模式显得灰暗或线条偏细。
                            color: speechBusy
                                ? NovelPalette.accent.withOpacity(.72)
                                : Colors.white.withOpacity(
                                    focused
                                        ? .36
                                        : (glassActive ? .28 : .20),
                                  ),
                            width: speechBusy ? .9 : .85,
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: <Widget>[
                            if (widget.gameController != null) ...<Widget>[
                              Padding(
                                padding: const EdgeInsets.only(bottom: 1),
                                child: CompositedTransformTarget(
                                  link: _inventoryLink,
                                  child: Tooltip(
                                    message: '引用物品',
                                    child: AnimatedContainer(
                                      duration: const Duration(milliseconds: 140),
                                      width: shortViewport ? 29 : 32,
                                      height: shortViewport ? 30 : 34,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: inventoryPickerOpen
                                            ? Colors.white.withOpacity(.075)
                                            : Colors.white.withOpacity(.025),
                                        borderRadius: BorderRadius.zero,
                                        border: Border.all(
                                          color: inventoryPickerOpen
                                              ? Colors.white.withOpacity(.30)
                                              : Colors.white.withOpacity(.08),
                                          width: .75,
                                        ),
                                      ),
                                      child: Material(
                                        color: Colors.transparent,
                                        child: InkWell(
                                          onTap: widget.enabled && !speechBusy
                                              ? _toggleInventoryPicker
                                              : null,
                                          borderRadius: BorderRadius.zero,
                                          splashColor: Colors.white.withOpacity(.08),
                                          highlightColor: Colors.white.withOpacity(.055),
                                          child: Center(
                                            child: AnimatedDefaultTextStyle(
                                              duration: const Duration(milliseconds: 140),
                                              style: TextStyle(
                                                color: inventoryPickerOpen
                                                    ? Colors.white.withOpacity(.96)
                                                    : Colors.white.withOpacity(
                                                        widget.enabled && !speechBusy ? .60 : .26,
                                                      ),
                                                fontSize: shortViewport ? 18 : 20,
                                                height: 1,
                                                fontWeight: FontWeight.w300,
                                              ),
                                              child: const Text('+'),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                            ],
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
                                      width: shortViewport ? 32 : 36,
                                      height: shortViewport ? 32 : 36,
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
                            const SizedBox(width: 6),
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
                                  cursorColor: targetActorActive
                                      ? Colors.white.withOpacity(.92)
                                      : NovelPalette.accent,
                                  style: TextStyle(
                                    color: const Color(0xFFF4F3EE),
                                    fontSize: shortViewport ? 13.4 : 14,
                                    height: shortViewport ? 1.28 : 1.35,
                                    fontWeight: FontWeight.w400,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: _speechFinishing
                                        ? '正在转文字…'
                                        : speaking
                                            ? '正在听… 松开后转成文字'
                                            : targetActorActive
                                                ? '输入要说的话…'
                                                : (widget.luckyCardActive
                                                    ? '运气已加持，描述你的行动…'
                                                    : '描述你想做的事…'),
                                    hintStyle: TextStyle(
                                      color: speechBusy
                                          ? Colors.white.withOpacity(.58)
                                          : Colors.white.withOpacity(
                                              targetActorActive
                                                  ? (focused ? .42 : .30)
                                                  : (focused ? .48 : .32),
                                            ),
                                      fontSize: shortViewport ? 12.5 : 13.2,
                                      fontWeight: FontWeight.w400,
                                    ),
                                    isDense: true,
                                    contentPadding: EdgeInsets.only(
                                      top: shortViewport ? 6 : 8,
                                      bottom: shortViewport ? 9 : 12,
                                    ),
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
                                  width: shortViewport ? 31 : 34,
                                  height: shortViewport ? 31 : 34,
                                  decoration: BoxDecoration(
                                    // 发送按钮使用纯白强调色，不再沿用全局绿色 accent。
                                    color: canSend
                                        ? Colors.white
                                        : Colors.white.withOpacity(.055),
                                    borderRadius: BorderRadius.zero,
                                    border: Border.all(
                                      color: canSend
                                          ? Colors.white.withOpacity(.96)
                                          : Colors.white.withOpacity(.10),
                                      width: .65,
                                    ),
                                  ),
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      borderRadius: BorderRadius.zero,
                                      onTap: canSend ? _submit : null,
                                      splashColor: Colors.black.withOpacity(.08),
                                      highlightColor: Colors.black.withOpacity(.055),
                                      hoverColor: Colors.black.withOpacity(.035),
                                      child: Center(
                                        child: Icon(
                                          Icons.arrow_upward_rounded,
                                          size: shortViewport ? 16 : 17,
                                          color: canSend
                                              ? const Color(0xFF111512)
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
                ],
              ),
            )
          ],
        ));
  }
}

class _InventoryReferenceTile extends StatefulWidget {
  const _InventoryReferenceTile({
    required this.name,
    required this.typeLabel,
    required this.description,
    required this.referenced,
    required this.onTap,
  });

  final String name;
  final String typeLabel;
  final String description;
  final bool referenced;
  final VoidCallback onTap;

  @override
  State<_InventoryReferenceTile> createState() => _InventoryReferenceTileState();
}

class _InventoryReferenceTileState extends State<_InventoryReferenceTile> {
  bool _pressed = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.referenced;
    final description = widget.description.trim();
    final background = _pressed
        ? Colors.white.withOpacity(.070)
        : active
            ? Colors.white.withOpacity(.085)
            : _hovered
                ? Colors.white.withOpacity(.040)
                : Colors.transparent;
    final border = active
        ? Colors.white.withOpacity(.30)
        : _pressed
            ? Colors.white.withOpacity(.24)
            : _hovered
                ? Colors.white.withOpacity(.12)
                : Colors.white.withOpacity(.055);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Tooltip(
        message: description.isEmpty ? widget.typeLabel : description,
        waitDuration: const Duration(milliseconds: 320),
        preferBelow: false,
        child: AnimatedScale(
          scale: _pressed ? .985 : 1,
          duration: const Duration(milliseconds: 90),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.zero,
              border: Border.all(color: border, width: .8),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: widget.onTap,
                onHighlightChanged: (value) {
                  if (mounted) setState(() => _pressed = value);
                },
                borderRadius: BorderRadius.zero,
                splashColor: Colors.white.withOpacity(.055),
                highlightColor: Colors.white.withOpacity(.03),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
                  child: Row(
                    children: <Widget>[
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 140),
                        width: 2,
                        height: 25,
                        color: active
                            ? Colors.white.withOpacity(.86)
                            : Colors.white.withOpacity(_hovered ? .24 : .07),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            AnimatedDefaultTextStyle(
                              duration: const Duration(milliseconds: 120),
                              style: TextStyle(
                                color: Colors.white.withOpacity(
                                  active ? .96 : (_hovered ? .90 : .78),
                                ),
                                fontSize: 11.7,
                                height: 1.1,
                                fontWeight: active
                                    ? FontWeight.w700
                                    : FontWeight.w600,
                              ),
                              child: Text(
                                widget.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              active
                                  ? '${widget.typeLabel} · 已引用'
                                  : widget.typeLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: active
                                    ? Colors.white.withOpacity(.70)
                                    : Colors.white.withOpacity(_hovered ? .44 : .31),
                                fontSize: 9.2,
                                fontWeight: FontWeight.w500,
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
    );
  }
}

class _ReferencedInventoryChip extends StatefulWidget {
  const _ReferencedInventoryChip({
    required this.name,
    required this.description,
    required this.onRemove,
  });

  final String name;
  final String description;
  final VoidCallback onRemove;

  @override
  State<_ReferencedInventoryChip> createState() => _ReferencedInventoryChipState();
}

class _ReferencedInventoryChipState extends State<_ReferencedInventoryChip> {
  bool _pressed = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final description = widget.description.trim();
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Tooltip(
        message: description.isEmpty ? widget.name : description,
        waitDuration: const Duration(milliseconds: 320),
        preferBelow: false,
        child: AnimatedScale(
          scale: _pressed ? .97 : 1,
          duration: const Duration(milliseconds: 80),
          curve: Curves.easeOutCubic,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onRemove,
              onHighlightChanged: (value) {
                if (mounted) setState(() => _pressed = value);
              },
              borderRadius: BorderRadius.zero,
              splashColor: Colors.white.withOpacity(.075),
              highlightColor: Colors.white.withOpacity(.05),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                height: 26,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: _pressed
                      ? Colors.white.withOpacity(.085)
                      : _hovered
                          ? Colors.white.withOpacity(.055)
                          : Colors.white.withOpacity(.028),
                  borderRadius: BorderRadius.zero,
                  border: Border.all(
                    color: Colors.white.withOpacity(
                      _pressed ? .34 : (_hovered ? .24 : .105),
                    ),
                    width: .75,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      width: 2,
                      height: 14,
                      color: Colors.white.withOpacity(
                        _hovered || _pressed ? .78 : .42,
                      ),
                    ),
                    const SizedBox(width: 7),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 128),
                      child: AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 120),
                        style: TextStyle(
                          color: Colors.white.withOpacity(
                            _hovered || _pressed ? .97 : .78,
                          ),
                          fontSize: 10.4,
                          height: 1,
                          fontWeight: FontWeight.w700,
                        ),
                        child: Text(
                          widget.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      '×',
                      style: TextStyle(
                        color: Colors.white.withOpacity(
                          _hovered || _pressed ? .92 : .40,
                        ),
                        fontSize: 12.5,
                        height: 1,
                        fontWeight: FontWeight.w400,
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


class _TargetActorContextChip extends StatelessWidget {
  const _TargetActorContextChip({
    required this.name,
    this.avatarUrl = '',
    this.onClear,
  });

  final String name;
  final String avatarUrl;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final compact = NovelViewportMetrics.of(context).compactChrome;
    final textColor = Colors.white.withOpacity(.90);
    final subtleColor = Colors.white.withOpacity(.52);
    final avatarSize = compact ? 18.0 : 20.0;
    final prefixHeight = compact ? 25.0 : 28.0;

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: compact ? 140 : 168),
      child: Container(
        height: prefixHeight,
        padding: EdgeInsets.only(
          left: compact ? 6 : 7,
          right: onClear == null ? (compact ? 7 : 8) : 3,
        ),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(.040),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: Colors.white.withOpacity(.135),
            width: .65,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              '对',
              style: TextStyle(
                color: subtleColor,
                fontSize: compact ? 10.4 : 11.0,
                height: 1,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 5),
            _TargetActorMiniAvatar(
              name: name,
              avatarUrl: avatarUrl,
              size: avatarSize,
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: textColor,
                  fontSize: compact ? 10.8 : 11.5,
                  height: 1,
                  fontWeight: FontWeight.w600,
                  letterSpacing: .05,
                ),
              ),
            ),
            const SizedBox(width: 3),
            Text(
              '说：',
              style: TextStyle(
                color: subtleColor,
                fontSize: compact ? 10.4 : 11.0,
                height: 1,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (onClear != null) ...<Widget>[
              const SizedBox(width: 2),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onClear,
                  borderRadius: BorderRadius.circular(5),
                  splashColor: Colors.white.withOpacity(.055),
                  highlightColor: Colors.white.withOpacity(.035),
                  child: SizedBox(
                    width: compact ? 21 : 23,
                    height: prefixHeight,
                    child: Center(
                      child: Icon(
                        Icons.close_rounded,
                        size: compact ? 13.5 : 14.5,
                        color: Colors.white.withOpacity(.62),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TargetActorMiniAvatar extends StatelessWidget {
  const _TargetActorMiniAvatar({
    required this.name,
    required this.avatarUrl,
    required this.size,
  });

  final String name;
  final String avatarUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cleanAvatar = avatarUrl.trim();
    final initial = name.trim().isEmpty ? '' : name.trim().substring(0, 1);
    final radius = BorderRadius.circular(5);

    if (cleanAvatar.isNotEmpty) {
      return ClipRRect(
        borderRadius: radius,
        child: Image.network(
          cleanAvatar,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _AvatarFallback(
            initial: initial,
            size: size,
            radius: radius,
          ),
        ),
      );
    }

    return _AvatarFallback(
      initial: initial,
      size: size,
      radius: radius,
    );
  }
}

class _AvatarFallback extends StatelessWidget {
  const _AvatarFallback({
    required this.initial,
    required this.size,
    required this.radius,
  });

  final String initial;
  final double size;
  final BorderRadius radius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: radius,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        color: Colors.white.withOpacity(.070),
        child: Text(
          initial,
          maxLines: 1,
          overflow: TextOverflow.clip,
          style: TextStyle(
            color: Colors.white.withOpacity(.86),
            fontSize: size * .48,
            height: 1,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
