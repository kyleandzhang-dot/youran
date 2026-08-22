import 'novel_models.dart';

class NovelTextParser {
  const NovelTextParser({
    // 单段只负责防止极长文本失控；最终翻页由阅读页组合器决定。
    this.maxDialogueCharsPerPage = 96,
    this.maxNarrationCharsPerPage = 150,
    this.mergeNarrationMaxChars = 140,
  });

  final int maxDialogueCharsPerPage;
  final int maxNarrationCharsPerPage;
  final int mergeNarrationMaxChars;

  static const int _mixedPageMaxChars = 120;
  static const int _sameSpeakerMaxChars = 105;
  static const int _leadingNarrationMaxChars = 92;
  static const int _trailingNarrationMaxChars = 52;
  static const int _holdShortNarrationChars = 46;

  static final RegExp _structuredTagBlock = RegExp(
    r'<(inner|template|think|score|suggested_replies|reply|state_update|protagonist_update|node_status|current_intent|planted_hooks|next_plan|item_event|dice_check|task_update|relation_state|memory_anchors|past_milestones|immutable_facts|current_scene|scene_presence|pacing_reference|hook_style_reference)\b[^>]*>[\s\S]*?<\/\1>',
    caseSensitive: false,
  );

  static final RegExp _structuredSelfClosing = RegExp(
    r'<(inner|template|think|score|suggested_replies|reply)\b[^>]*\/?>',
    caseSensitive: false,
  );

  String cleanAiTags(String text) {
    if (text.isEmpty) return '';
    var result = text.replaceAll(RegExp(r'[\u200B-\u200D\uFEFF]'), '');
    result = result.replaceAllMapped(
      RegExp(r'[\*_]*\[([^\]]+)\][\*_]*'),
      (match) => '[${match.group(1)}]',
    );
    result = result.replaceAll(_structuredTagBlock, '');
    result = result.replaceAll(_structuredSelfClosing, '');
    result = result.replaceAll(
      RegExp(
        r'<(inner|template|think|score|suggested_replies|reply)\b[\s\S]*',
        caseSensitive: false,
      ),
      '',
    );
    result = result.replaceAll(
      RegExp(r'<\/?(?:[a-zA-Z_][a-zA-Z0-9_:-]*)\b[^>]*>'),
      '',
    );
    result = result.replaceAll(RegExp(r'<[\/a-zA-Z_]+[^>]*$'), '');
    result = result.replaceAll(RegExp(r'\n\s*\n'), '\n');
    return result;
  }

  String cleanStreamingText(String text) {
    var filtered = cleanAiTags(text);
    filtered = filtered.replaceAll(
      RegExp(r'<[a-z_]{3,30}(?:[^>]*)?>(?:[^<]*)$', caseSensitive: false),
      '',
    );
    return filtered;
  }

  String extractSpeaker(String chunk) {
    if (chunk.isEmpty) return '';
    final match = RegExp(r'^[\s\*]*[【\[]([^】\]\n]{1,20})[】\]]')
        .firstMatch(chunk);
    return match?.group(1)?.trim() ?? '';
  }

  String stripSpeakerPrefix(String chunk) {
    if (chunk.isEmpty) return '';
    var text = chunk.replaceFirst(
      RegExp(r'^[\s\*]*[【\[][^】\]\n]{1,20}[】\]]\s*'),
      '',
    );
    text = text.replaceFirst(RegExp(r'^[:：]\s*'), '');
    text = text.replaceFirstMapped(
      RegExp(r'^([(（][^)）]+[)）])\s*[:：]\s*'),
      (match) => '${match.group(1)} ',
    );
    return text;
  }

  List<String> splitNovelText(String text) {
    if (text.trim().isEmpty) return const <String>[];
    var content = cleanAiTags(text).trim();
    if (content.isEmpty) return const <String>[];
    content = content.replaceAll(RegExp(r'^[ \t\u3000]+', multiLine: true), '');

    final marker = RegExp(r'(?=[\[【][^\]】]{1,10}[\]】]\s*[：:])');
    final rawSegments = content.split(marker);
    final result = <String>[];
    final speakerPrefix = RegExp(r'^[\[【][^\]】]{1,10}[\]】]\s*[：:]');

    for (var segment in rawSegments) {
      segment = segment.trim();
      if (segment.isEmpty) continue;
      if (speakerPrefix.hasMatch(segment)) {
        final firstNewline = segment.indexOf('\n');
        if (firstNewline >= 0) {
          final dialogue = segment.substring(0, firstNewline).trim();
          final pureText = dialogue
              .replaceFirst(RegExp(r'^[\[【][^\]】]{1,10}[\]】]\s*[：:]\s*'), '')
              .trim();
          if (pureText.isNotEmpty) result.add(dialogue);
          final narration = segment.substring(firstNewline).split('\n');
          for (final line in narration) {
            final cleaned = line.trim();
            if (cleaned.isNotEmpty) result.add(cleaned);
          }
        } else {
          final pureText = segment
              .replaceFirst(RegExp(r'^[\[【][^\]】]{1,10}[\]】]\s*[：:]\s*'), '')
              .trim();
          if (pureText.isNotEmpty) result.add(segment);
        }
      } else {
        for (final line in segment.split('\n')) {
          final cleaned = line.trim();
          if (cleaned.isNotEmpty) result.add(cleaned);
        }
      }
    }
    return result;
  }

  List<String> _completeTailPieces(String chunk) {
    if (chunk.isEmpty) return const <String>[];
    final speaker = extractSpeaker(chunk);
    final body = stripSpeakerPrefix(chunk);
    final prefix = speaker.isEmpty ? '' : '【$speaker】：';
    final result = <String>[];
    var start = 0;
    for (var i = 0; i < body.length; i++) {
      if ('。！？；…?!;'.contains(body[i])) {
        final piece = body.substring(start, i + 1).trim();
        if (piece.isNotEmpty) result.add('$prefix$piece');
        start = i + 1;
      }
    }
    if (start >= body.length) return result;
    return result;
  }

  List<String> _splitPlainText(String body, int maxChars) {
    if (body.trim().isEmpty) return const <String>[];
    if (body.trim().length <= maxChars) return <String>[body.trim()];

    final tokens = <String>[];
    final tokenRegex = RegExp(
      r'(\*\*[\s\S]*?\*\*|\*[\s\S]*?\*|["【《（\[(][\s\S]*?["】》）\])]|[a-zA-Z0-9_]+[。！？，、；：.,!?;:]*|[\s\S][。！？，、；：.,!?;:]*)',
    );
    for (final match in tokenRegex.allMatches(body)) {
      final value = match.group(0);
      if (value != null && value.isNotEmpty) tokens.add(value);
    }
    if (tokens.isEmpty) tokens.add(body);

    final result = <String>[];
    var current = '';
    for (final token in tokens) {
      if (current.isNotEmpty && current.length + token.length > maxChars) {
        result.add(current.trim());
        current = token.trimLeft();
      } else {
        current = current.isEmpty ? token.trimLeft() : '$current$token';
      }
    }
    if (current.trim().isNotEmpty) result.add(current.trim());
    return result;
  }

  List<String> _splitLongChunk(String chunk) {
    final speaker = extractSpeaker(chunk);
    final body = stripSpeakerPrefix(chunk);
    final maxChars = speaker.isEmpty
        ? maxNarrationCharsPerPage
        : maxDialogueCharsPerPage;
    if (body.trim().length <= maxChars) return <String>[chunk.trim()];
    final prefix = speaker.isEmpty ? '' : '【$speaker】：';
    return _splitPlainText(body, maxChars)
        .map((piece) => '$prefix$piece'.trim())
        .toList(growable: false);
  }

  List<NovelSentence> _paginateStructuredSentences(
    List<NovelSentence> input,
  ) {
    final result = <NovelSentence>[];
    for (final item in input) {
      final maxChars = item.isNarration
          ? maxNarrationCharsPerPage
          : maxDialogueCharsPerPage;
      final pieces = _splitPlainText(item.text, maxChars);
      if (pieces.isEmpty) continue;
      for (var i = 0; i < pieces.length; i++) {
        result.add(
          item.copyWith(
            text: pieces[i],
            // 预加载提示只需要附在最后一页，避免同一句分页时重复触发。
            preloadPortrait: i == pieces.length - 1 && item.preloadPortrait,
            nextSpeakerName:
                i == pieces.length - 1 ? item.nextSpeakerName : '',
            nextCharacterId:
                i == pieces.length - 1 ? item.nextCharacterId : '',
            nextPortraitUrl:
                i == pieces.length - 1 ? item.nextPortraitUrl : '',
            nextAvatarUrl:
                i == pieces.length - 1 ? item.nextAvatarUrl : '',
          ),
        );
      }
    }
    return result;
  }

  List<NovelSentence> mergeNarrations(List<NovelSentence> input) {
    if (input.isEmpty) return input;
    final result = <NovelSentence>[];
    NovelSentence? pending;

    void flush() {
      if (pending != null) {
        result.add(pending!);
        pending = null;
      }
    }

    for (final item in input) {
      if (!_isPackableNarration(item)) {
        flush();
        result.add(item);
        continue;
      }
      if (pending == null) {
        pending = item;
      } else if (pending!.text.length + item.text.length <=
          mergeNarrationMaxChars) {
        pending = pending!.copyWith(
          text: '${pending!.text}\n\n${item.text}',
          preloadPortrait: item.preloadPortrait || pending!.preloadPortrait,
          nextSpeakerName: item.nextSpeakerName.isNotEmpty
              ? item.nextSpeakerName
              : pending!.nextSpeakerName,
          nextCharacterId: item.nextCharacterId.isNotEmpty
              ? item.nextCharacterId
              : pending!.nextCharacterId,
          nextPortraitUrl: item.nextPortraitUrl.isNotEmpty
              ? item.nextPortraitUrl
              : pending!.nextPortraitUrl,
          nextAvatarUrl: item.nextAvatarUrl.isNotEmpty
              ? item.nextAvatarUrl
              : pending!.nextAvatarUrl,
        );
      } else {
        flush();
        pending = item;
      }
    }
    flush();
    return result;
  }

  bool _isPackableNarration(NovelSentence item) {
    if (!item.isNarration) return false;
    final type = item.type.toLowerCase().trim();
    return type.isEmpty ||
        const <String>{
          'narration',
          'narrative',
          'action',
          'description',
        }.contains(type);
  }

  bool _sameDialogueSpeaker(NovelSentence first, NovelSentence second) {
    if (first.isNarration || second.isNarration) return false;
    if (first.isProtagonist != second.isProtagonist) return false;
    if (first.characterId.isNotEmpty && second.characterId.isNotEmpty) {
      return first.characterId == second.characterId;
    }
    return first.speakerName.trim().isNotEmpty &&
        first.speakerName.trim() == second.speakerName.trim();
  }

  int _readerCharCount(NovelSentence item) => item.readerText.runes.length;

  NovelSentence _combineSameSpeaker(
    NovelSentence first,
    NovelSentence second,
  ) {
    return first.copyWith(
      text: <String>[first.text.trim(), second.text.trim()]
          .where((value) => value.isNotEmpty)
          .join('\n\n'),
      trailingNarration: second.trailingNarration,
      hasSpeech: first.hasSpeech || second.hasSpeech,
      preloadPortrait: first.preloadPortrait || second.preloadPortrait,
      nextSpeakerName: second.nextSpeakerName.isNotEmpty
          ? second.nextSpeakerName
          : first.nextSpeakerName,
      nextCharacterId: second.nextCharacterId.isNotEmpty
          ? second.nextCharacterId
          : first.nextCharacterId,
      nextPortraitUrl: second.nextPortraitUrl.isNotEmpty
          ? second.nextPortraitUrl
          : first.nextPortraitUrl,
      nextAvatarUrl: second.nextAvatarUrl.isNotEmpty
          ? second.nextAvatarUrl
          : first.nextAvatarUrl,
    );
  }

  NovelSentence _attachLeadingNarration(
    NovelSentence dialogue,
    NovelSentence narration,
  ) {
    final leading = <String>[
      narration.readerText.trim(),
      dialogue.leadingNarration.trim(),
    ].where((value) => value.isNotEmpty).join('\n\n');
    return dialogue.copyWith(leadingNarration: leading);
  }

  NovelSentence _attachTrailingNarration(
    NovelSentence dialogue,
    NovelSentence narration,
  ) {
    final trailing = <String>[
      dialogue.trailingNarration.trim(),
      narration.readerText.trim(),
    ].where((value) => value.isNotEmpty).join('\n\n');
    return dialogue.copyWith(
      trailingNarration: trailing,
      preloadPortrait: dialogue.preloadPortrait || narration.preloadPortrait,
      nextSpeakerName: narration.nextSpeakerName.isNotEmpty
          ? narration.nextSpeakerName
          : dialogue.nextSpeakerName,
      nextCharacterId: narration.nextCharacterId.isNotEmpty
          ? narration.nextCharacterId
          : dialogue.nextCharacterId,
      nextPortraitUrl: narration.nextPortraitUrl.isNotEmpty
          ? narration.nextPortraitUrl
          : dialogue.nextPortraitUrl,
      nextAvatarUrl: narration.nextAvatarUrl.isNotEmpty
          ? narration.nextAvatarUrl
          : dialogue.nextAvatarUrl,
    );
  }

  /// 把语义句组合成适合手机连续阅读的页面：
  /// - 短旁白可以和紧接的一个角色对白同页；
  /// - 同一角色的连续短对白尽量合并；
  /// - 对白后的短旁白可留在同页；
  /// - 不混合两个不同说话人，也不把未知的特殊事件类型塞进普通页；
  /// - 流式末尾只有一小段旁白时先保留，等待下一块决定如何组合。
  List<NovelSentence> _composeReaderPages(
    List<NovelSentence> input, {
    required bool isGenerating,
  }) {
    if (input.isEmpty) return input;
    final pages = <NovelSentence>[];
    var index = 0;

    while (index < input.length) {
      final item = input[index];

      if (_isPackableNarration(item)) {
        final narrationLength = _readerCharCount(item);
        final hasDialogueAfter = index + 1 < input.length &&
            !input[index + 1].isNarration;
        if (hasDialogueAfter &&
            narrationLength <= _leadingNarrationMaxChars &&
            narrationLength + _readerCharCount(input[index + 1]) <=
                _mixedPageMaxChars) {
          var page = _attachLeadingNarration(input[index + 1], item);
          index += 2;

          while (index < input.length &&
              _sameDialogueSpeaker(page, input[index]) &&
              _readerCharCount(page) + _readerCharCount(input[index]) <=
                  _sameSpeakerMaxChars) {
            page = _combineSameSpeaker(page, input[index]);
            index += 1;
          }

          if (index < input.length &&
              _isPackableNarration(input[index]) &&
              _readerCharCount(input[index]) <= _trailingNarrationMaxChars &&
              _readerCharCount(page) + _readerCharCount(input[index]) <=
                  _mixedPageMaxChars) {
            page = _attachTrailingNarration(page, input[index]);
            index += 1;
          }
          pages.add(page);
          continue;
        }

        if (isGenerating &&
            index == input.length - 1 &&
            narrationLength < _holdShortNarrationChars) {
          break;
        }
        pages.add(item);
        index += 1;
        continue;
      }

      if (!item.isNarration) {
        var page = item;
        index += 1;

        while (index < input.length &&
            _sameDialogueSpeaker(page, input[index]) &&
            _readerCharCount(page) + _readerCharCount(input[index]) <=
                _sameSpeakerMaxChars) {
          page = _combineSameSpeaker(page, input[index]);
          index += 1;
        }

        if (index < input.length &&
            _isPackableNarration(input[index]) &&
            _readerCharCount(input[index]) <= _trailingNarrationMaxChars &&
            _readerCharCount(page) + _readerCharCount(input[index]) <=
                _mixedPageMaxChars) {
          page = _attachTrailingNarration(page, input[index]);
          index += 1;
        }
        pages.add(page);
        continue;
      }

      // 未知的特殊类型保持独立页面，作为天然的强制分页点。
      pages.add(item);
      index += 1;
    }
    return pages;
  }

  List<NovelSentence> buildSentences({
    required NovelMessage? message,
    required bool isGenerating,
  }) {
    if (message == null) return const <NovelSentence>[];
    if (message.sentenceItems.isNotEmpty) {
      return _composeReaderPages(
        mergeNarrations(
          _paginateStructuredSentences(message.sentenceItems),
        ),
        isGenerating: isGenerating,
      );
    }
    if (message.content.trim().isEmpty) return const <NovelSentence>[];

    final chunks = splitNovelText(message.content)
        .where((chunk) => chunk.trim().isNotEmpty)
        .toList();
    var displayable = chunks;
    if (isGenerating) {
      if (chunks.isEmpty) return const <NovelSentence>[];
      final completeChunks = chunks.length > 1
          ? chunks.sublist(0, chunks.length - 1)
          : <String>[];
      final tail = chunks.last;
      displayable = <String>[...completeChunks, ..._completeTailPieces(tail)];
    }

    final sentences = <NovelSentence>[];
    for (final chunk in displayable) {
      for (final page in _splitLongChunk(chunk)) {
        final speaker = extractSpeaker(page);
        sentences.add(
          NovelSentence(
            text: stripSpeakerPrefix(page).trim(),
            type: speaker.isEmpty ? 'narration' : 'dialogue',
            speakerName: speaker,
            isProtagonist: speaker == '我',
          ),
        );
      }
    }
    return _composeReaderPages(
      mergeNarrations(sentences),
      isGenerating: isGenerating,
    );
  }

  List<String> scanLorebook(List<JsonMap> lorebook, String prompt) {
    if (lorebook.isEmpty || prompt.trim().isEmpty) return const <String>[];

    final normalizedPrompt = prompt.toLowerCase();
    final matchedContents = <String>[];
    final dedupe = <String>{};

    for (final entry in lorebook) {
      if (entry['enabled'] == false) continue;

      final keysRaw = entry['keys'] ?? entry['keywords'] ?? entry['key'];
      final keys = keysRaw is List
          ? keysRaw.map(stringValue).where((e) => e.isNotEmpty).toList()
          : stringValue(keysRaw)
              .split(RegExp(r'[,，、\s]+'))
              .where((e) => e.isNotEmpty)
              .toList();

      // Vue 的逻辑是“至少命中一个关键词”才激活；空 keys 不自动注入。
      final hit = keys.any(
        (key) => normalizedPrompt.contains(key.toLowerCase()),
      );
      if (!hit) continue;

      final content = stringValue(entry['content']);
      if (content.isEmpty) continue;
      final identity = stringValue(entry['id'], content);
      if (!dedupe.add(identity)) continue;
      matchedContents.add(content);
    }

    return matchedContents;
  }

  String generateSearchQuery(String prompt, List<NovelMessage> history) {
    if (history.isEmpty) return prompt;
    final last = history.last;
    final context = last.role == NovelMessageRole.assistant ? last.content : '';
    final combined = '$context $prompt';
    return combined.length <= 150
        ? combined
        : combined.substring(combined.length - 150);
  }

  List<NovelMessage> trimHistory(
    List<NovelMessage> history, [
    int maxCount = 20,
    int maxChars = 3000,
  ]) {
    if (history.isEmpty) return const <NovelMessage>[];

    final sliced = history.length <= maxCount
        ? List<NovelMessage>.of(history)
        : history.sublist(history.length - maxCount);

    var totalChars = 0;
    final result = <NovelMessage>[];
    for (var i = sliced.length - 1; i >= 0; i--) {
      final message = sliced[i];
      final length = message.content.length;
      if (totalChars + length > maxChars) break;
      totalChars += length;
      result.insert(0, message);
    }
    return result;
  }

}
