import 'package:flutter_test/flutter_test.dart';

import '../lib/features/novel/novel_models.dart';
import '../lib/features/novel/novel_text_parser.dart';

void main() {
  const parser = NovelTextParser();

  test('清理模型结构标签但保留正文', () {
    const raw = '<inner>不应显示</inner>\n[老徐]：你好。<score value="2"/>';
    expect(parser.cleanAiTags(raw).trim(), '[老徐]：你好。');
  });

  test('支持中英文角色括号与冒号', () {
    const raw = '[老徐]：第一句。\n【阿青】：第二句。\n风从山后吹来。';
    final chunks = parser.splitNovelText(raw);
    expect(chunks, hasLength(3));
    expect(parser.extractSpeaker(chunks[0]), '老徐');
    expect(parser.extractSpeaker(chunks[1]), '阿青');
  });

  test('流式期间只展示已经结束的完整句', () {
    const message = NovelMessage(
      id: '1',
      role: NovelMessageRole.assistant,
      content: '[老徐]：第一句已经完成。第二句还没有写完',
    );
    final values = parser.buildSentences(message: message, isGenerating: true);
    expect(values, hasLength(1));
    expect(values.single.text, '第一句已经完成。');
  });

  test('后端 sentence_items 优先并合并短旁白', () {
    const message = NovelMessage(
      id: '2',
      role: NovelMessageRole.assistant,
      content: '该内容不应优先',
      sentenceItems: <NovelSentence>[
        NovelSentence(text: '天色渐暗。'),
        NovelSentence(text: '山林安静下来。'),
        NovelSentence(text: '你来了。', type: 'dialogue', speakerName: '阿青'),
      ],
    );
    final values = parser.buildSentences(message: message, isGenerating: false);
    expect(values, hasLength(2));
    expect(values.first.text, contains('山林安静下来'));
    expect(values.last.speakerName, '阿青');
  });
}
