part of '../novel_widgets.dart';

// Novel Widgets · 独立选择面板
// 对外入口：NovelChoicePanel
// 内部实现：选择卡片及其视觉状态。

class NovelChoicePanel extends StatelessWidget {
  const NovelChoicePanel({
    super.key,
    required this.options,
    required this.onSelect,
    this.enabled = true,
    this.title = '请做出你的选择',
  });

  final List<String> options;
  final ValueChanged<String> onSelect;
  final bool enabled;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Column(
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
            Text(
              title,
              style: const TextStyle(
                color: NovelPalette.text,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                letterSpacing: .5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        for (int i = 0; i < options.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(height: 10),
          _NovelChoiceCard(
            label: options[i],
            enabled: enabled,
            onTap: () => onSelect(options[i]),
          ),
        ],
      ],
    );
  }
}

class _NovelChoiceCard extends StatelessWidget {
  const _NovelChoiceCard({
    required this.label,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: _AdaptiveBackdropBlur(
        sigma: 18,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.circular(14),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                // 反光玻璃遮罩：顶部略亮、底部略暗的渐变，模拟光线打在磨砂玻璃上的高光
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    Colors.white.withOpacity(.16),
                    Colors.white.withOpacity(.045),
                  ],
                ),
                border: Border.all(
                  color: Colors.white.withOpacity(.11),
                  width: .55,
                ),
                boxShadow: const <BoxShadow>[
                  BoxShadow(color: Color(0x30000000), blurRadius: 14, offset: Offset(0, 6)),
                ],
              ),
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: NovelPalette.text.withOpacity(enabled ? .80 : .42),
                  fontSize: 14.5,
                  fontWeight: FontWeight.w500,
                  height: 1.3,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 开发者调试专用：把正文（旁白层，不含角色对白）里所有正则标记的实际渲染效果
/// 集中展示出来，不用真的在剧情里凑齐每种符号才能看到样式。
///
/// 用法：在开发设置抽屉里加一个按钮/开关项，调用
///   NovelNarrationStylePreview.show(context);
/// 即可弹出这个预览面板；面板本身不写入任何真实数据，随时可以关掉。
