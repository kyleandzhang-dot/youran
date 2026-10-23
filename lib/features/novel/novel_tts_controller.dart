import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import 'novel_backend.dart';
import 'novel_models.dart';

/// 朗读播放器抽象：以后换音频包或写测试替身只需要实现这个接口。
abstract class NovelTtsPlayer {
  /// 播放一个 URL；当前条目播放结束后返回，不会主动重播。
  Future<void> playUrl(String url);

  Future<void> stop();

  Future<void> dispose();
}

/// 可提前把下一条音频加入播放队列的能力。
/// 使用独立接口，避免影响现有的测试播放器或其他 NovelTtsPlayer 实现。
abstract class NovelTtsPreloader {
  /// 确保当前音频已经在队列中，但不主动开始播放。
  Future<void> prepareUrl(String url);

  /// 提前把下一条音频加入同一个播放器的队列。
  Future<void> preloadUrl(String url);
}

/// 基于 just_audio 的单播放器队列实现。
/// 当前句播放时，把下一句加入同一个 AudioPlayer 的 playlist；
/// 已准备好的下一句由播放器自动接播，避免每句都 stop() + setUrl()。
class JustAudioNovelTtsPlayer implements NovelTtsPlayer, NovelTtsPreloader {
  AudioPlayer? _player;
  StreamSubscription<int?>? _indexSubscription;
  StreamSubscription<PlayerState>? _stateSubscription;

  final Map<String, int> _urlToIndex = <String, int>{};
  final Set<int> _completedIndices = <int>{};
  final Set<int> _startedIndices = <int>{};
  int? _lastObservedIndex;
  final Map<String, Future<void>> _preparingUrls = <String, Future<void>>{};
  Future<void> _queueMutation = Future<void>.value();

  int _generation = 0;
  int _queueGeneration = 0;
  bool _initialized = false;
  int? _activeIndex;
  Completer<void>? _activeDone;
  bool _activeStarted = false;

  AudioPlayer _ensure() {
    final existing = _player;
    if (existing != null) return existing;
    // 关闭惰性准备：只向队列追加一条前瞻音频，让它在当前句播放时尽早准备。
    final player = AudioPlayer(useLazyPreparation: false);
    _indexSubscription = player.currentIndexStream.listen(_handleCurrentIndex);
    _stateSubscription = player.playerStateStream.listen(_handlePlayerState);
    return _player = player;
  }

  void _handleCurrentIndex(int? index) {
    final previousIndex = _lastObservedIndex;
    _lastObservedIndex = index;
    // 即使控制器还没来得及为预加载音频注册等待器，也记录已经自然播过的队列项，防止短句被重播。
    if (previousIndex != null &&
        index != previousIndex &&
        _startedIndices.contains(previousIndex)) {
      _completedIndices.add(previousIndex);
    }

    final activeIndex = _activeIndex;
    if (activeIndex == null) return;
    final player = _player;
    if (index == activeIndex) {
      if (player?.playing == true) _activeStarted = true;
      return;
    }
    // 在同一播放队列里切换到下一条，说明当前条目已经自然结束。
    if (_activeStarted || (index != null && index > activeIndex)) {
      _completeActive();
    }
  }

  void _handlePlayerState(PlayerState state) {
    final player = _player;
    if (player == null) return;
    final currentIndex = player.currentIndex;
    if (state.playing && currentIndex != null) {
      _startedIndices.add(currentIndex);
    }
    if (state.processingState == ProcessingState.completed &&
        currentIndex != null &&
        _startedIndices.contains(currentIndex)) {
      _completedIndices.add(currentIndex);
    }

    final activeIndex = _activeIndex;
    if (activeIndex == null) return;
    if (state.playing && currentIndex == activeIndex) {
      _activeStarted = true;
    }
    if (_activeStarted &&
        state.processingState == ProcessingState.completed &&
        currentIndex == activeIndex) {
      _completeActive();
    }
  }

  void _completeActive() {
    final done = _activeDone;
    final completedIndex = _activeIndex;
    if (completedIndex != null) _completedIndices.add(completedIndex);
    _activeDone = null;
    _activeIndex = null;
    _activeStarted = false;
    if (done != null && !done.isCompleted) done.complete();
  }

  void _completeActiveWithError(Object error, StackTrace stack) {
    final done = _activeDone;
    _activeDone = null;
    _activeIndex = null;
    _activeStarted = false;
    if (done != null && !done.isCompleted) done.completeError(error, stack);
  }

  @override
  Future<void> prepareUrl(String url) {
    if (url.isEmpty || _urlToIndex.containsKey(url)) {
      return Future<void>.value();
    }
    final pending = _preparingUrls[url];
    if (pending != null) return pending;

    final queueGeneration = _queueGeneration;
    late final Future<void> operation;
    operation = _queueMutation.then((_) async {
      if (queueGeneration != _queueGeneration) return;
      final player = _ensure();
      final source = AudioSource.uri(Uri.parse(url));

      if (!_initialized) {
        // 第一次初始化播放器时设置首条音频；之后只动态追加，避免每句重置播放器。
        await player.setAudioSource(source, preload: true);
        _initialized = true;
        if (queueGeneration != _queueGeneration) return;
        _urlToIndex[url] = 0;
      } else {
        final wasEmpty = player.audioSources.isEmpty;
        await player.addAudioSource(source);
        if (queueGeneration != _queueGeneration) return;
        if (wasEmpty) {
          // stop/clear 后的第一条新音频显式 load，兼容 Web 上的 playlist 初始化时序。
          await player.load();
          if (queueGeneration != _queueGeneration) return;
        }
        _urlToIndex[url] = player.audioSources.length - 1;
      }
      debugPrint(
        '[novel tts player] queued index=${_urlToIndex[url]} '
        'url=$url total=${player.audioSources.length}',
      );
    });

    // 让队列后续操作在前一个操作失败后仍然可以继续；原始 operation 的错误仍交给调用方。
    _queueMutation = operation.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    _preparingUrls[url] = operation;
    operation.then<void>(
      (_) {
        if (identical(_preparingUrls[url], operation)) _preparingUrls.remove(url);
      },
      onError: (Object error, StackTrace stack) {
        if (identical(_preparingUrls[url], operation)) _preparingUrls.remove(url);
      },
    );
    return operation;
  }

  @override
  Future<void> preloadUrl(String url) => prepareUrl(url);

  @override
  Future<void> playUrl(String url) async {
    final generation = ++_generation;
    await prepareUrl(url);
    if (generation != _generation) return;

    final player = _ensure();
    final targetIndex = _urlToIndex[url];
    if (targetIndex == null) {
      throw StateError('TTS audio was not queued: $url');
    }

    final done = Completer<void>();
    _activeDone = done;
    _activeIndex = targetIndex;
    _activeStarted = false;

    final currentIndex = player.currentIndex;
    if (_completedIndices.contains(targetIndex) ||
        (currentIndex != null && currentIndex > targetIndex)) {
      // 该队列项已经自然播放过去，不回头重播。
      _completeActive();
    } else if (currentIndex != targetIndex) {
      if (player.playing && currentIndex != null && currentIndex < targetIndex) {
        // 让正在播放的队列自然走到目标项，不打断当前音频。
      } else {
        await player.seek(Duration.zero, index: targetIndex);
        if (generation != _generation) return;
        _startPlayback(player, generation, targetIndex);
      }
    } else if (player.playing) {
      _activeStarted = true;
    } else {
      _startPlayback(player, generation, targetIndex);
    }

    await done.future;
    if (generation == _generation) {
      debugPrint('[novel tts player] completed index=$targetIndex url=$url');
    }
  }

  void _startPlayback(AudioPlayer player, int generation, int targetIndex) {
    if (generation != _generation || _activeIndex != targetIndex) return;
    final future = player.play();
    if (player.playing && player.currentIndex == targetIndex) {
      _activeStarted = true;
    }
    // play() 的 Future 会在整个队列结束时才正常完成；这里只接住播放异常，
    // 每条音频的完成由 currentIndexStream / playerStateStream 精确判断。
    unawaited(future.catchError((Object error, StackTrace stack) {
      if (generation == _generation && _activeIndex == targetIndex) {
        _completeActiveWithError(error, stack);
      }
    }));
  }

  @override
  Future<void> stop() async {
    ++_generation;
    ++_queueGeneration;
    _completeActive();
    // 清掉旧代次的 in-flight 去重项，避免新页面误复用已取消的准备任务。
    _preparingUrls.clear();
    final player = _player;
    if (player == null) return;

    // 把清理操作也放进队列：新页面即使立刻开始准备音频，也会排在清理之后执行。
    final priorMutations = _queueMutation;
    late final Future<void> cleanup;
    cleanup = priorMutations.then((_) async {
      await player.stop();
      if (_initialized) {
        await player.clearAudioSources();
        _urlToIndex.clear();
        _completedIndices.clear();
        _startedIndices.clear();
        _lastObservedIndex = null;
        // 不清空 _preparingUrls：其中可能已有排在 cleanup 后面的新页面任务。
        _initialized = true;
      }
    });
    _queueMutation = cleanup.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    try {
      await cleanup;
    } catch (error) {
      debugPrint('[novel tts player] queue cleanup failed: $error');
    }
  }

  @override
  Future<void> dispose() async {
    ++_generation;
    ++_queueGeneration;
    _completeActive();
    await _queueMutation;
    await _indexSubscription?.cancel();
    await _stateSubscription?.cancel();
    _indexSubscription = null;
    _stateSubscription = null;
    await _player?.dispose();
    _player = null;
    _urlToIndex.clear();
    _completedIndices.clear();
    _startedIndices.clear();
    _lastObservedIndex = null;
    _preparingUrls.clear();
  }
}

/// 剧情朗读（沉浸听书）。
///
/// 数据流：
///   游戏控制器每次翻页/状态变化 → [syncPage]（当前页 + 对应的后端条目下标）
///   → 首次进入某条消息时 POST /novel/tts/start（后端后台按句序批量合成）
///   → 轮询 GET /novel/tts/manifest，等到需要的条目 ready 就播放
///   → 一页的条目全部播完 → [onPageFinished]（由游戏控制器接到 goNext）
///
/// 每页按条目顺序只播放一遍，结束后回调自动进入下一页；不会循环重播。
/// 手动翻页、关闭阅读、新消息到来都会让旧的播放令牌 [_run] 失效，旧任务自动退出。
class NovelTtsController extends ChangeNotifier {
  NovelTtsController({
    required this.backend,
    NovelTtsPlayer? player,
    this.pollInterval = const Duration(milliseconds: 900),
    this.silentPageAdvance = const Duration(milliseconds: 2500),
  }) : _player = player;

  final NovelBackend backend;
  final Duration pollInterval;

  /// 当前页没有可朗读条目（流式文本回退等）时，多久后自动翻页；null = 停在这一页。
  final Duration? silentPageAdvance;

  /// 一页读完后的回调。由游戏控制器设置为“有下一句就自动 goNext”。
  VoidCallback? onPageFinished;

  NovelTtsPlayer? _player;
  NovelTtsPlayer get _audio => _player ??= JustAudioNovelTtsPlayer();

  bool _enabled = false;
  bool _loading = false;
  bool _audioActive = false;
  int? _currentItemIndex;
  bool _disposed = false;
  String _error = '';

  int _run = 0;
  String _pageKey = '';
  int _finishedRun = -1;

  // 某些阅读句会合并多个后端 sentence_items，相邻句的映射也可能有重叠。
  // 同一阅读会话中，同一条目/同一音频 URL 只允许成功播放一次。
  int _playedMessageId = 0;
  final Set<int> _playedIndices = <int>{};
  final Set<String> _playedUrls = <String>{};

  int _sessionMessageId = 0;
  bool _jobRunning = false;
  final Map<int, JsonMap> _manifest = <int, JsonMap>{};
  final Map<String, Future<String?>> _urlWaits = <String, Future<String?>>{};

  /// 朗读模式是否开启（开启后自动播放并自动翻页）。
  bool get enabled => _enabled;

  /// 正在等待后端生成 / 等待消息落库。
  bool get loading => _loading;
  bool get isPlaying => _enabled && _audioActive;

  /// 当前实际正在播放的后端 sentence_items 下标，用于字幕逐条同步。
  int? get currentItemIndex => _currentItemIndex;

  String get error => _error;

  void setEnabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    _error = '';
    _pageKey = ''; // 让下一次 syncPage 一定重新开始
    _finishedRun = -1;
    // 每次重新开启阅读都从当前页开始；关闭再开启是一个新阅读会话。
    _playedMessageId = 0;
    _playedIndices.clear();
    _playedUrls.clear();
    _urlWaits.clear();
    _cancelRun();
    _notify();
  }

  /// 出错后重试：清掉错误并让下一次 syncPage 重新开始（包括重新调 /tts/start）。
  void retry() {
    if (!_enabled) return;
    _error = '';
    _pageKey = '';
    _sessionMessageId = 0;
    _notify();
  }

  /// 由游戏控制器在每次状态变化时调用；只有“页面标识”变化才会真正重新开始。
  void syncPage({
    required int? messageId,
    required int sentenceIndex,
    required List<int> itemIndices,
    required bool generating,
  }) {
    if (!_enabled) return;

    if (generating || messageId == null || messageId <= 0) {
      // 流式生成中，消息还没落库，后端取不到 sentence_items：先不读，生成结束后会再次触发。
      if (_pageKey.isNotEmpty) {
        _pageKey = '';
        _cancelRun();
      }
      if (!_loading) {
        _loading = true;
        _notify();
      }
      return;
    }

    final isNewMessage = _playedMessageId != messageId;
    if (isNewMessage) {
      _playedMessageId = messageId;
      _playedIndices.clear();
      _playedUrls.clear();
      _urlWaits.clear();
    }

    final key = '$messageId|$sentenceIndex|${itemIndices.join(',')}';
    if (key == _pageKey) return;
    final preserveQueue = !isNewMessage && !_audioActive && _finishedRun == _run;
    _pageKey = key;
    _cancelRun(preserveQueue: preserveQueue);
    unawaited(_playPage(_run, messageId, sentenceIndex, List<int>.of(itemIndices)));
  }

  // ───────────────────────── 内部 ─────────────────────────

  void _cancelRun({bool preserveQueue = false}) {
    _run += 1;
    _loading = false;
    _audioActive = false;
    _currentItemIndex = null;
    // 自动进入同一条消息的下一阅读页时，保留刚刚预加载的下一条音频；
    // 用户主动中断、关闭朗读或切换到新消息时仍然完整停止并清空队列。
    final player = _player;
    if (player != null && !preserveQueue) unawaited(player.stop());
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _fail(String message) {
    debugPrint('[novel tts] FAILED: $message');
    _error = message;
    _loading = false;
    _notify();
  }

  void _finishPageOnce(int run, int messageId, int sentenceIndex) {
    if (run != _run || !_enabled || _finishedRun == run) return;
    _finishedRun = run;
    debugPrint(
      '[novel tts] page finished message=$messageId sentence=$sentenceIndex',
    );
    onPageFinished?.call();
  }

  Future<void> _playPage(
    int run,
    int messageId,
    int sentenceIndex,
    List<int> indices,
  ) async {
    _error = '';
    _loading = true;
    _notify();
    debugPrint(
      '[novel tts] page start message=$messageId sentence=$sentenceIndex '
      'items=$indices alreadyPlayed=${_playedIndices.toList()}',
    );
    try {
      if (indices.isEmpty) {
        _loading = false;
        _notify();
        final wait = silentPageAdvance;
        if (wait != null) {
          await Future<void>.delayed(wait);
          if (run == _run && _enabled) {
            _finishPageOnce(run, messageId, sentenceIndex);
          }
        }
        return;
      }

      // 若相邻阅读句复用了已读过的后端条目，跳过旧条目而不是再次播音。
      final pendingIndices = indices
          .where((index) => !_playedIndices.contains(index))
          .toList(growable: false);
      if (pendingIndices.isEmpty) {
        _loading = false;
        _notify();
        debugPrint(
          '[novel tts] all items already played; advance once '
          'message=$messageId sentence=$sentenceIndex items=$indices',
        );
        // 让出当前事件循环，避免连续重叠页同步递归推进。
        await Future<void>.delayed(Duration.zero);
        if (run == _run && _enabled) {
          _finishPageOnce(run, messageId, sentenceIndex);
        }
        return;
      }

      if (_sessionMessageId != messageId) {
        _manifest.clear();
        _jobRunning = false;
        if (!await _startWithRetry(run, messageId, pendingIndices.first)) {
          if (run == _run) _fail(_error.isEmpty ? '朗读生成失败，请稍后重试' : _error);
          return;
        }
      }

      var played = 0;
      var unavailable = 0;
      var lastIssue = '';
      for (var position = 0; position < pendingIndices.length; position++) {
        final index = pendingIndices[position];
        if (run != _run) return;
        final url = await _awaitUrl(run, messageId, index);
        if (run != _run) return;
        if (url == null) {
          // 生成失败 / 超时：记下来，整页都放不出来时要报错，而不是悄悄翻页。
          unavailable += 1;
          lastIssue = '语音生成失败';
          continue;
        }
        if (url.isEmpty) continue; // 后端标记为 skip（纯动作句等），正常跳过
        if (run != _run) return;

        if (_playedUrls.contains(url)) {
          _playedIndices.add(index);
          debugPrint(
            '[novel tts] skip duplicate url item=$index message=$messageId',
          );
          continue;
        }

        _loading = false;
        _audioActive = true;
        _currentItemIndex = index;
        // 字幕仍按后端 item 同步；普通阅读页的分句/合并规则不变。
        _notify();
        try {
          // 先确保当前音频进入播放队列，再预加载下一条，保证队列顺序不会颠倒。
          final audio = _audio;
          // 显式转换为可预加载接口，兼容 Dart 对接口类型提升的差异；
          // 普通测试播放器若不支持预加载，仍按 playUrl 的原流程播放。
          final NovelTtsPreloader? preloader = audio is NovelTtsPreloader
              ? audio as NovelTtsPreloader
              : null;
          if (preloader != null) {
            await preloader.prepareUrl(url);
            if (run != _run) return;
            final candidates = <int>[];
            final seenCandidates = <int>{index};
            candidates.addAll(pendingIndices.skip(position + 1));
            seenCandidates.addAll(candidates);
            final laterManifestIndices = _manifest.keys
                .where((candidate) =>
                    candidate > index &&
                    !_playedIndices.contains(candidate) &&
                    !seenCandidates.contains(candidate))
                .toList()
              ..sort();
            candidates.addAll(laterManifestIndices);
            if (candidates.isNotEmpty) {
              unawaited(_preloadFollowing(run, messageId, url, candidates));
            }
          }

          debugPrint('[novel tts] play item=$index url=$url');
          await _audio.playUrl(url);
          if (run != _run) return;
          debugPrint('[novel tts] completed item=$index message=$messageId');
          _playedIndices.add(index);
          _playedUrls.add(url);
          played += 1;
        } catch (error) {
          if (run != _run) return;
          unavailable += 1;
          lastIssue = '音频无法播放';
          debugPrint('[novel tts] play failed item=$index: $error');
        } finally {
          if (run == _run) _audioActive = false;
        }
      }

      if (run != _run) return;
      if (played == 0 && unavailable > 0) {
        _fail(lastIssue);
        return;
      }
      _loading = false;
      _notify();
      _finishPageOnce(run, messageId, sentenceIndex);
    } catch (error) {
      if (run != _run) return;
      debugPrint('[novel tts] page failed: $error');
      _fail('朗读出错，请稍后重试');
    }
  }

  /// 当前句播放时，提前等待并把后续可朗读音频加入同一个 just_audio 队列。
  /// 允许预加载跨越同一消息的阅读页边界，但用户中断或切换新消息时会自动失效。
  Future<void> _preloadFollowing(
    int originRun,
    int messageId,
    String currentUrl,
    List<int> candidates,
  ) async {
    final audio = _audio;
    if (audio is! NovelTtsPreloader) return;
    final NovelTtsPreloader preloader = audio as NovelTtsPreloader;

    bool stillRelevant() =>
        _enabled &&
        !_disposed &&
        _playedMessageId == messageId &&
        (originRun == _run || _finishedRun == originRun);

    for (final candidate in candidates) {
      if (!stillRelevant()) return;
      if (_playedIndices.contains(candidate)) continue;
      final url = await _awaitUrl(
        originRun,
        messageId,
        candidate,
        isValid: stillRelevant,
      );
      if (!stillRelevant()) return;
      if (url == null) return;
      if (url.isEmpty || url == currentUrl || _playedUrls.contains(url)) continue;
      try {
        await preloader.preloadUrl(url);
        if (!stillRelevant()) return;
        debugPrint('[novel tts] preloaded next item=$candidate message=$messageId');
        return; // 只预加载最近的下一条，避免过度占用浏览器缓冲资源。
      } catch (error) {
        debugPrint('[novel tts] preload failed item=$candidate: $error');
        return;
      }
    }
  }

  /// 触发后端后台批量合成（已经在跑时后端幂等返回当前进度）。
  /// 流式刚结束时消息可能还没落库（404），所以带重试。
  Future<bool> _startWithRetry(int run, int messageId, int startIndex) async {
    for (var attempt = 0; attempt < 6; attempt++) {
      if (run != _run || !_enabled) return false;
      try {
        final snapshot = await backend.startNovelTts(
          messageId: messageId,
          startIndex: startIndex,
        );
        if (run != _run) return false;
        _applySnapshot(snapshot);
        _sessionMessageId = messageId;
        debugPrint(
          '[novel tts] started message=$messageId '
          'items=${_manifest.length} running=$_jobRunning',
        );
        return true;
      } on NovelBackendException catch (error) {
        // 没有 statusCode = 后端实现不支持朗读，重试没有意义。
        if (error.statusCode == null) {
          _error = error.message;
          return false;
        }
        debugPrint('[novel tts] start failed (${error.statusCode}): ${error.message}');
      } catch (error) {
        debugPrint('[novel tts] start failed: $error');
      }
      await Future<void>.delayed(const Duration(milliseconds: 1500));
    }
    return false;
  }

  Future<void> _refreshManifest(int messageId) async {
    final snapshot = await backend.fetchNovelTtsManifest(messageId);
    if (_sessionMessageId != messageId) return;
    _applySnapshot(snapshot);
  }

  void _applySnapshot(JsonMap snapshot) {
    for (final item in asJsonList(snapshot['items'])) {
      final index = intValue(item['index'], -1);
      if (index >= 0) _manifest[index] = item;
    }
    _jobRunning = boolValue(snapshot['running']);
  }

  /// 等某一条 ready。返回 url；空字符串 = 不需要播（skip）；null = 失败 / 超时 / 被打断。
  Future<String?> _awaitUrl(
    int run,
    int messageId,
    int index, {
    bool Function()? isValid,
  }) {
    final key = '$run|$messageId|$index';
    final existing = _urlWaits[key];
    if (existing != null) return existing;
    late final Future<String?> future;
    future = _awaitUrlImpl(run, messageId, index, isValid: isValid).whenComplete(() {
      if (identical(_urlWaits[key], future)) _urlWaits.remove(key);
    });
    _urlWaits[key] = future;
    return future;
  }

  Future<String?> _awaitUrlImpl(
    int run,
    int messageId,
    int index, {
    bool Function()? isValid,
  }) async {
    bool valid() => isValid?.call() ?? (run == _run && _enabled);
    var restarts = 0;
    var failures = 0;
    while (valid()) {
      final item = _manifest[index];
      final status = stringValue(item?['status']);
      if (status == 'ready') {
        final url = stringValue(item?['url']);
        return url.isEmpty ? null : url;
      }
      if (status == 'skip') return ''; // 空字符串 = 这一条本来就不需要播
      if (status.isEmpty && _manifest.isNotEmpty) return ''; // 清单里没有这一条

      // pending / failed 但后台任务没在跑（进程重启、任务过期、部分失败）：重新触发，最多 2 次。
      if (status.isNotEmpty && !_jobRunning) {
        if (restarts >= 2) return null;
        restarts += 1;
        if (!valid()) return null;
        final startRun = isValid == null ? run : _run;
        if (!await _startWithRetry(startRun, messageId, index)) return null;
        continue;
      }

      await Future<void>.delayed(pollInterval);
      if (!valid()) return null;
      try {
        await _refreshManifest(messageId);
        failures = 0;
      } catch (error) {
        failures += 1;
        debugPrint('[novel tts] manifest failed: $error');
        if (failures >= 5) return null;
      }
    }
    return null;
  }

  @override
  void dispose() {
    _disposed = true;
    _enabled = false;
    _run += 1;
    final player = _player;
    _player = null;
    if (player != null) unawaited(player.dispose());
    super.dispose();
  }
}