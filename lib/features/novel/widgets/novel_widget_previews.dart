part of '../novel_widgets.dart';

// Novel Widgets · 开发预览
// 对外入口：NovelNarrationStylePreview
// 内部实现：正文标记样式预览样本与预览 Sheet。

class NovelNarrationStylePreview {
  const NovelNarrationStylePreview._();

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => const _NovelNarrationStylePreviewSheet(),
    );
  }
}

class _NovelNarrationPreviewSample {
  const _NovelNarrationPreviewSample(this.label, this.raw);
  final String label;
  final String raw;
}

// 每一行覆盖一种标记，最后一行把所有标记混在一句里，模拟真实剧情文本的样子。
const List<_NovelNarrationPreviewSample> _novelNarrationPreviewSamples = <_NovelNarrationPreviewSample>[
  _NovelNarrationPreviewSample(
    '圆括号 / 半角括号 —— 心理活动、动作旁注',
    '（她微微皱眉）他没有回答，(反而转身走向了窗边)。',
  ),
  _NovelNarrationPreviewSample(
    '星号 —— 动作/神态（酒馆式标记，效果同圆括号）',
    '*他缓缓握紧了拳头*，指节因为用力而发白。',
  ),
  _NovelNarrationPreviewSample(
    '【】—— 系统类播报',
    '【触发隐藏剧情】守卫的视线还未离开，你必须尽快做出选择。',
  ),
  _NovelNarrationPreviewSample(
    '[] —— 重点词汇（技能/道具/专有名词）',
    '你在角落发现了一把[生锈的钥匙]，似乎能打开地窖的门。',
  ),
  _NovelNarrationPreviewSample(
    '引号 —— 叙述中夹带的引述对白（符号保留）',
    '她低声说道："你终于来了。"随后转身离去，"别让我等太久。"',
  ),
  _NovelNarrationPreviewSample(
    '混合示例 —— 模拟真实剧情文本',
    '（心跳漏了一拍）*他猛地看向门口*，【战斗触发】她说："小心，[黑袍人]来了。"',
  ),
];

class _NovelNarrationStylePreviewSheet extends StatelessWidget {
  const _NovelNarrationStylePreviewSheet();

  @override
  Widget build(BuildContext context) {
    final baseStyle = const TextStyle(
      color: Color(0xFFF3F4F6),
      fontSize: 16,
      height: 1.9,
      fontWeight: FontWeight.w500,
      shadows: <Shadow>[
        Shadow(color: Color(0x99000000), blurRadius: 6, offset: Offset(0, 1)),
      ],
    );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .82,
          ),
          child: _GlassSurface(
            radius: 20,
            blur: 24,
            color: const Color(0xE0191B19),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 14, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Container(
                        width: 3,
                        height: 14,
                        decoration: BoxDecoration(
                          color: NovelPalette.accent,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          '正文正则样式预览',
                          style: TextStyle(
                            color: NovelPalette.text,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            letterSpacing: .3,
                          ),
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: Icon(
                          Icons.close_rounded,
                          color: Colors.white.withOpacity(.6),
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '仅开发调试用：只展示正文/旁白层的渲染效果（角色对白样式不受此规则影响），不写入任何真实剧情数据。',
                    style: TextStyle(
                      color: NovelPalette.muted,
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Flexible(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          for (final sample in _novelNarrationPreviewSamples) ...<Widget>[
                            Text(
                              sample.label,
                              style: const TextStyle(
                                color: NovelPalette.muted,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: .4,
                              ),
                            ),
                            const SizedBox(height: 6),
                            DecoratedBox(
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(.04),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.white.withOpacity(.06)),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                child: Text.rich(
                                  TextSpan(
                                    children: _buildNovelNarrationDisplaySpans(
                                      sample.raw,
                                      baseStyle,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),
                          ],
                        ],
                      ),
                    ),
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
