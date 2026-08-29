part of '../novel_widgets.dart';

// Novel Widgets · 公共基础
// 对外入口：NovelPortraitCache / NovelPalette / NovelArtwork
// 内部实现：正文清洗、富文本标记、低功耗模糊、逐字辅助等共享能力。

class NovelPortraitCache {
  NovelPortraitCache._();

  static final NovelPortraitCache instance =
      NovelPortraitCache._();

  final LinkedHashMap<String, ImageProvider> _cache =
      LinkedHashMap<String, ImageProvider>();

  static const int maxSize = 200;


  ImageProvider get(String url) {
    final key = url.trim();

    final old = _cache.remove(key);
    if (old != null) {
      _cache[key] = old;
      return old;
    }

    final ImageProvider provider;

    if (key.startsWith('http://') ||
        key.startsWith('https://')) {
      provider = NetworkImage(CdnUtil.resize(key, width: 800));
    } else {
      provider = AssetImage(key);
    }

    _cache[key] = provider;

    if (_cache.length > maxSize) {
      _cache.remove(_cache.keys.first);
    }

    return provider;
  }
}

class NovelPalette {
  // 小说模式主题强调色统一为低饱和抹茶绿；正文仍以白 / 灰白保证可读性。
  // 信息页与剧情页统一使用中性冷灰黑基底。
  // 不再使用偏棕的“羊皮纸黑”，避免角色 / 背包页显旧、显脏。
  static const Color background = Color(0xFF0C0E10);
  static const Color panel = Color(0x18FFFFFF);
  static const Color panelStrong = Color(0x26FFFFFF);
  static const Color text = Color(0xFFF4F5F2);
  static const Color muted = Color(0xFF949A96);
  // Novel 模式统一主绿色。交互选中 / 主按钮 / 成功提示直接引用 accent。
  // 深色文字和浅色承载层使用派生色，避免在白底上直接用高亮绿导致看不清。
  // 平衡型主绿色：比荧光绿柔和，但仍保留足够的游戏感和识别度。
  static const Color accent = Color(0xFF6FD35F);
  static const Color accentDeep = Color(0xFF4B9142);
  static const Color accentSoft = Color(0xFFF1F8EF);
  static const Color accentLine = Color(0xFFD7E8D2);
  static const Color accentDark = Color(0xFF1C3219);
  static const Color warning = Color(0xFFE2C27A);
  static const Color danger = Color(0xFFE7685E);
}



/// 流式文本在网络 chunk 边界被错误解码时，偶尔会短暂出现 U+FFFD（�）。
/// 最终完整响应到达后通常又会恢复正常，所以显示层先过滤这些无效占位符，
/// 避免用户在流式过程中看到“方框/叉号”。
String _sanitizeNovelStreamingText(String value) {
  if (value.isEmpty) return value;
  final buffer = StringBuffer();
  for (final rune in value.runes) {
    if (rune == 0xFFFD || rune == 0x0000 || rune == 0xFEFF) {
      continue;
    }
    buffer.writeCharCode(rune);
  }
  return novelTextWithoutSymbolOnlyLines(buffer.toString());
}

/// 混合页的逐字进度必须使用清洗后的三个组成部分重新计算。
/// 三部分之间只保留一个正常换行，不能重新制造双换行空白。
String _sanitizeNovelSentenceReaderText(NovelSentence? sentence) {
  if (sentence == null) return '';
  if (!sentence.hasMixedContent) {
    // 不再 trim 整段正文：正文自己的正常换行与行首排版必须保留。
    return _sanitizeNovelStreamingText(sentence.readerText);
  }

  return <String>[
    _sanitizeNovelStreamingText(sentence.leadingNarration),
    _sanitizeNovelStreamingText(sentence.text),
    _sanitizeNovelStreamingText(sentence.trailingNarration),
  ]
      // 每一部分已经逐行清洗完成；这里只过滤真正没有文字的部分，
      // 不再 trim 后重新破坏原本的换行/缩进。
      .where(novelTextHasReadableContent)
      .join('\n');
}


/// 后端已经把 dialogue.currentSentence 整理成最终展示格式：
///   （动作/神态/语气）真正对白
/// Flutter 不再理解小说语义，只负责把后端约定的全角括号区间做视觉降级。
/// 逐字动画尚未出现右括号时，从左括号到当前末尾也保持淡色，避免闪烁。
List<InlineSpan> _buildNovelDialogueDisplaySpans(
  String value,
  TextStyle baseStyle,
) {
  if (value.isEmpty) {
    return <InlineSpan>[TextSpan(text: value, style: baseStyle)];
  }

  final stageStyle = baseStyle.copyWith(
    color: (baseStyle.color ?? const Color(0xFFF7F7F7)).withOpacity(.58),
    fontWeight: FontWeight.w400,
    shadows: const <Shadow>[
      Shadow(color: Color(0x30000000), blurRadius: 1.5, offset: Offset(0, 1)),
    ],
  );

  final spans = <InlineSpan>[];
  var cursor = 0;

  while (cursor < value.length) {
    final open = value.indexOf('（', cursor);
    if (open < 0) {
      spans.add(TextSpan(text: value.substring(cursor), style: baseStyle));
      break;
    }

    if (open > cursor) {
      spans.add(TextSpan(text: value.substring(cursor, open), style: baseStyle));
    }

    final close = value.indexOf('）', open + 1);
    if (close < 0) {
      spans.add(TextSpan(text: value.substring(open), style: stageStyle));
      break;
    }

    spans.add(
      TextSpan(
        text: value.substring(open, close + 1),
        style: stageStyle,
      ),
    );
    cursor = close + 1;
  }

  return spans;
}

/// 旁白 / 正文专用的富文本标记。只作用于叙述层，不影响角色对白
/// （对白继续走上面的 _buildNovelDialogueDisplaySpans，不受此函数影响）。
///
/// 覆盖市面上主流文字游戏 / 互动小说（含"酒馆"式 RP 排版惯例）常见的几类标记：
///   （…）/ (…)  全角/半角圆括号 —— 心理活动、动作旁注
///   *…*         星号包裹 —— 酒馆最常见的动作/神态标记，语义等同圆括号
///   【…】        系统类播报（面板音效、状态提示、命运转折的"画外音"）
///   […]         重点词汇（技能 / 道具 / 专有名词、地名首次出现）
///   "…" / "…"   叙述中夹带的引述对白
///
/// 圆括号 / 星号 / 方括号本质上只是"排版指令"——告诉渲染层这段该用什么视觉样式，
/// 不是真正要给读者看的字符，所以解析后把符号本身丢掉，只保留内容 + 对应样式。
/// 引号不一样：它是书面语法里"这是被转述的话"的正式标点，删掉会让读者分不清
/// 这句到底是叙述还是引述，所以引号本身要保留，只是颜色/字重上做轻微区分。
enum _NovelNarrationMarkerKind { aside, system, keyword, quote }

class _NovelNarrationMarkerDef {
  const _NovelNarrationMarkerDef(this.open, this.close, this.kind, {required this.strip});
  final String open;
  final String close;
  final _NovelNarrationMarkerKind kind;
  final bool strip;
}

const List<_NovelNarrationMarkerDef> _novelNarrationMarkers = <_NovelNarrationMarkerDef>[
  _NovelNarrationMarkerDef('（', '）', _NovelNarrationMarkerKind.aside, strip: true),
  _NovelNarrationMarkerDef('(', ')', _NovelNarrationMarkerKind.aside, strip: true),
  _NovelNarrationMarkerDef('*', '*', _NovelNarrationMarkerKind.aside, strip: true),
  _NovelNarrationMarkerDef('【', '】', _NovelNarrationMarkerKind.system, strip: true),
  _NovelNarrationMarkerDef('[', ']', _NovelNarrationMarkerKind.keyword, strip: true),
  _NovelNarrationMarkerDef('"', '"', _NovelNarrationMarkerKind.quote, strip: false),
  _NovelNarrationMarkerDef('“', '”', _NovelNarrationMarkerKind.quote, strip: false),
];

/// 单个标记扫描出来的片段：普通正文 kind 为 null；命中某种标记时是对应 kind。
/// 这是 _buildNovelNarrationDisplaySpans（渲染用）和 _novelVisibleNarrationText
/// （纯粹判断“剥完符号后是否还有可见内容”用）共用的唯一一套解析逻辑——
/// 两边分别再造一遍容易在后续改动里悄悄跑偏，所以只在这里写一次。
class _NovelNarrationSegment {
  const _NovelNarrationSegment(this.text, this.kind);
  final String text;
  final _NovelNarrationMarkerKind? kind;
}

List<_NovelNarrationSegment> _novelNarrationSegments(String value) {
  if (value.isEmpty) return const <_NovelNarrationSegment>[];

  final segments = <_NovelNarrationSegment>[];
  var cursor = 0;

  while (cursor < value.length) {
    // 找出从 cursor 开始，离得最近的一个标记起始符（几种标记里最早出现的那个）。
    _NovelNarrationMarkerDef? nearestMarker;
    var nearestIndex = -1;
    for (final marker in _novelNarrationMarkers) {
      final index = value.indexOf(marker.open, cursor);
      if (index < 0) continue;
      if (nearestIndex < 0 || index < nearestIndex) {
        nearestIndex = index;
        nearestMarker = marker;
      }
    }

    if (nearestMarker == null || nearestIndex < 0) {
      segments.add(_NovelNarrationSegment(value.substring(cursor), null));
      break;
    }

    if (nearestIndex > cursor) {
      segments.add(
        _NovelNarrationSegment(value.substring(cursor, nearestIndex), null),
      );
    }

    final close = value.indexOf(nearestMarker.close, nearestIndex + 1);
    final strip = nearestMarker.strip;

    if (close < 0) {
      // 逐字动画尚未出现右侧闭合符号时，从左标记到当前末尾也保持对应样式，避免闪烁。
      // strip 类标记连起始符号也一起丢掉；引号类保留起始符号本身。
      final tailStart = strip ? nearestIndex + 1 : nearestIndex;
      segments.add(
        _NovelNarrationSegment(value.substring(tailStart), nearestMarker.kind),
      );
      break;
    }

    final matchedText = strip
        ? value.substring(nearestIndex + 1, close)
        : value.substring(nearestIndex, close + 1);
    segments.add(_NovelNarrationSegment(matchedText, nearestMarker.kind));
    cursor = close + 1;
  }

  return segments;
}

/// 剥符号之后真正会显示给读者的纯文字（不带样式）。
/// 专门用来在渲染前判断“这一段剥完符号后是否还有可见内容”——
/// 纯符号片段（残留的半个 *、内容为空的 （）标记）剥完就是空字符串，
/// 不应该再触发段落间距 / 占位行高。
String _novelVisibleNarrationText(String value) {
  if (value.isEmpty) return value;
  final buffer = StringBuffer();
  for (final segment in _novelNarrationSegments(value)) {
    buffer.write(segment.text);
  }
  return buffer.toString();
}

List<InlineSpan> _buildNovelNarrationDisplaySpans(
  String value,
  TextStyle baseStyle,
) {
  if (value.isEmpty) {
    return <InlineSpan>[TextSpan(text: value, style: baseStyle)];
  }

  final Color baseColor = baseStyle.color ?? const Color(0xFFF3F4F6);

  final asideStyle = baseStyle.copyWith(
    color: baseColor.withOpacity(.60),
    fontStyle: FontStyle.italic,
    fontWeight: FontWeight.w400,
    shadows: const <Shadow>[
      Shadow(color: Color(0x30000000), blurRadius: 1.5, offset: Offset(0, 1)),
    ],
  );

  final systemStyle = baseStyle.copyWith(
    color: NovelPalette.accent,
    fontWeight: FontWeight.w700,
    letterSpacing: (baseStyle.letterSpacing ?? 0) + .8,
    // 淡淡的底色，模拟系统提示的“标签感”，同时不影响整体呼吸感排版。
    background: Paint()..color = NovelPalette.accent.withOpacity(.14),
    shadows: <Shadow>[
      Shadow(color: NovelPalette.accent.withOpacity(.45), blurRadius: 10),
      const Shadow(color: Color(0x66000000), blurRadius: 4, offset: Offset(0, 1)),
    ],
  );

  final keywordStyle = baseStyle.copyWith(
    color: NovelPalette.warning,
    fontStyle: FontStyle.italic,
    fontWeight: FontWeight.w600,
    shadows: const <Shadow>[
      Shadow(color: Color(0x40000000), blurRadius: 3, offset: Offset(0, 1)),
    ],
  );

  final quoteStyle = baseStyle.copyWith(
    color: NovelPalette.accentLine,
    fontWeight: FontWeight.w600,
  );

  TextStyle styleFor(_NovelNarrationMarkerKind kind) {
    switch (kind) {
      case _NovelNarrationMarkerKind.aside:
        return asideStyle;
      case _NovelNarrationMarkerKind.system:
        return systemStyle;
      case _NovelNarrationMarkerKind.keyword:
        return keywordStyle;
      case _NovelNarrationMarkerKind.quote:
        return quoteStyle;
    }
  }

  return <InlineSpan>[
    for (final segment in _novelNarrationSegments(value))
      TextSpan(
        text: segment.text,
        style: segment.kind == null ? baseStyle : styleFor(segment.kind!),
      ),
  ];
}

/// 显式换行必须和屏幕宽度造成的自动折行有视觉区别。
/// 每个 `\n` 都作为一个新段落渲染，并增加一小段段间距；这里不插入空白行，
/// 因而仍然符合“只保留单换行、不要双换行”的正文规则。
class _NovelNarrationParagraphText extends StatelessWidget {
  const _NovelNarrationParagraphText({
    required this.value,
    required this.style,
    this.textAlign = TextAlign.left,
    this.paragraphSpacing = 10,
  });

  final String value;
  final TextStyle style;
  final TextAlign textAlign;
  final double paragraphSpacing;

  @override
  Widget build(BuildContext context) {
    // 清洗后的完整正文不会有空行；逐字动画刚好停在换行符时，末尾仍可能
    // 暂时出现一个空片段，过滤它可避免打字过程中提前撑出空白高度。
    final paragraphs = value
        .split('\n')
        .where((paragraph) => paragraph.isNotEmpty)
        .toList(growable: false);

    if (paragraphs.isEmpty) return const SizedBox.shrink();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (var index = 0; index < paragraphs.length; index++) ...<Widget>[
          Text.rich(
            TextSpan(
              children: _buildNovelNarrationDisplaySpans(
                paragraphs[index],
                style,
              ),
            ),
            textAlign: textAlign,
          ),
          if (index < paragraphs.length - 1)
            SizedBox(height: paragraphSpacing),
        ],
      ],
    );
  }
}

bool _useLowPowerNovelEffects(BuildContext context) {
  final media = MediaQuery.of(context);
  // 手机（含横屏）优先稳定帧率；平板/桌面继续保留完整毛玻璃与背景缓动。
  return media.size.shortestSide < 600 || media.disableAnimations;
}

class _AdaptiveBackdropBlur extends StatelessWidget {
  const _AdaptiveBackdropBlur({
    required this.sigma,
    required this.child,
  });

  final double sigma;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (_useLowPowerNovelEffects(context) || sigma <= 0) {
      return child;
    }
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
      child: child,
    );
  }
}

/// 按 Unicode code point 截取，而不是用 String.substring 的 UTF-16 code unit。
/// 这样不会把 emoji / 扩展字符截成半个代理对，避免逐字动画产生临时乱码。
String _novelPrefixByRunes(String value, int count) {
  if (value.isEmpty || count <= 0) return '';
  final runes = value.runes.toList(growable: false);
  final safeCount = count.clamp(0, runes.length);
  return String.fromCharCodes(runes.take(safeCount));
}

/// 逐字播放只服从本地阅读速度，不再跟随 SSE token 到达频率。
/// 标点后的短暂停顿能保留剧情节奏，同时不会让整页等待过久。
Duration _novelRevealDelay(int charactersPerSecond, String afterCharacter) {
  final cps = charactersPerSecond.clamp(1, 120);
  final baseMilliseconds = (1000 / cps).round().clamp(10, 90).toInt();
  var punctuationPause = 0;
  if ('。！？!?'.contains(afterCharacter)) {
    punctuationPause = 110;
  } else if ('…'.contains(afterCharacter)) {
    punctuationPause = 90;
  } else if ('；：;:'.contains(afterCharacter)) {
    punctuationPause = 60;
  } else if ('，、,'.contains(afterCharacter)) {
    punctuationPause = 42;
  }
  return Duration(milliseconds: baseMilliseconds + punctuationPause);
}

/// 每个非空白字符都为内存打字声轨续时；真正的 tick 间隔由音频声轨控制。
/// 不能再只在字符数恰好为 3 的倍数时调用：流式补字、标点停顿和页面重建
/// 会让部分手机只收到开头一两次脉冲，随后声轨便被当作空闲而暂停。
bool _shouldPlayNovelTypingTick({
  required int visibleLength,
  required String currentCharacter,
}) {
  if (currentCharacter.trim().isEmpty) return false;
  return visibleLength > 0;
}

class NovelArtwork extends StatelessWidget {
  const NovelArtwork({
    super.key,
    this.url = '',
    this.assetCandidates = const <String>[],
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.fallbackIcon = Icons.image_outlined,
    this.fallbackText = '',
    this.filterQuality = FilterQuality.medium,
  });

  final String url;
  final List<String> assetCandidates;
  final BoxFit fit;
  final Alignment alignment;
  final IconData fallbackIcon;
  final String fallbackText;
  final FilterQuality filterQuality;

  Widget _fallback() {
    return ColoredBox(
      color: Colors.white.withOpacity(.025),
      child: Center(
        child: fallbackText.trim().isNotEmpty
            ? Text(
                String.fromCharCode(fallbackText.trim().runes.first),
                style: TextStyle(
                  color: NovelPalette.text.withOpacity(.48),
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              )
            : Icon(
                fallbackIcon,
                size: 20,
                color: NovelPalette.muted.withOpacity(.58),
              ),
      ),
    );
  }

  Widget _assetAt(int index) {
    if (index >= assetCandidates.length) return _fallback();
    final asset = assetCandidates[index].trim();
    if (asset.isEmpty) return _assetAt(index + 1);
    return Image.asset(
      asset,
      fit: fit,
      alignment: alignment,
      filterQuality: filterQuality,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => _assetAt(index + 1),
    );
  }

  Widget _remoteOrAsset() {
    final value = url.trim();
    if (value.startsWith('data:image/')) {
      try {
        return Image.memory(
          base64Decode(value.split(',').last),
          fit: fit,
          alignment: alignment,
          filterQuality: filterQuality,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => _assetAt(0),
        );
      } catch (_) {
        return _assetAt(0);
      }
    }
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return Image(
        // 这里直接从我们改过的缓存里拿图片就行了，缓存已经加过 CdnUtil.resize 了
        image: NovelPortraitCache.instance.get(value), 
        fit: fit,
        alignment: alignment,
        filterQuality: filterQuality,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => _assetAt(0),
      );
    }
    if (value.isNotEmpty) {
      return Image.asset(
        value,
        fit: fit,
        alignment: alignment,
        filterQuality: filterQuality,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => _assetAt(0),
      );
    }
    return _assetAt(0);
  }

  @override
  Widget build(BuildContext context) => _remoteOrAsset();
}

class _StagePortraitArtwork extends StatelessWidget {
  const _StagePortraitArtwork({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.topCenter,
    this.filterQuality = FilterQuality.medium,
  });

  final String url;
  final BoxFit fit;
  final Alignment alignment;
  final FilterQuality filterQuality;

  @override
  Widget build(BuildContext context) {
    final value = url.trim();
    if (value.isEmpty) return const SizedBox.shrink();

    if (value.startsWith('data:image/')) {
      try {
        return Image.memory(
          base64Decode(value.split(',').last),
          fit: fit,
          alignment: alignment,
          filterQuality: filterQuality,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        );
      } catch (_) {
        return const SizedBox.shrink();
      }
    }

    if (value.startsWith('http://') || value.startsWith('https://')) {
      return Image(
        // 这里直接从缓存里拿，缓存里已经加过 CdnUtil.resize 了
        image: NovelPortraitCache.instance.get(value),
        fit: fit,
        alignment: alignment,
        filterQuality: filterQuality,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      );
    }

    return Image(
      image: NovelPortraitCache.instance.get(value),
      fit: fit,
      alignment: alignment,
      filterQuality: filterQuality,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
    );
  }
}

