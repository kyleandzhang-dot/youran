part of '../novel_sheets.dart';

// ============================================================================
// 命运选择页
// 页面入口 / 对外入口：
//   - showNovelChoicesSheet(...)
// 其余以下划线 `_` 开头的类型/方法均为该页面内部实现或共享私有实现。
// ============================================================================

Future<void> showNovelChoicesSheet(
  BuildContext context,
  NovelGameController controller, {
  List<NovelChoice>? previewChoices,
  bool previewOnly = false,
}) async {
  await _showNovelSheet<void>(
    context,
    heightFactor: .58,
    child: AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final visibleChoices = previewChoices ?? controller.choices;
        return _SheetScaffold(
          title: previewOnly ? '选择框样式' : '命运选择',
          subtitle: previewOnly
              ? '固定预览 dialogue / action / battle 三种类型'
              : (controller.playerHint.isEmpty
                  ? '每一个决定都会留下痕迹'
                  : controller.playerHint),
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
            itemCount: visibleChoices.length + (previewOnly ? 0 : 1),
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              if (!previewOnly && index == visibleChoices.length) {
                return _ActionTile(
                  icon: Icons.hourglass_empty_rounded,
                  title: '暂不行动',
                  subtitle: '让角色或环境自然推进剧情',
                  onTap: () async {
                    Navigator.of(context).pop();
                    await controller.forceContinue();
                  },
                );
              }

              final choice = visibleChoices[index];
              final isBattle = choice.isBattle;
              final isAction = choice.isAction;
              final typeLabel = isBattle
                  ? 'battle · 冲突 / 对战'
                  : isAction
                      ? 'action · 行动判定'
                      : 'dialogue · 对话 / 普通互动';
              final fallbackIcon = isBattle
                  ? Icons.flash_on_rounded
                  : isAction
                      ? Icons.casino_outlined
                      : Icons.chat_bubble_outline_rounded;

              return _ActionTile(
                number: previewOnly ? null : index + 1,
                icon: fallbackIcon,
                assetIconPath: previewOnly ? choice.iconPath : '',
                title: choice.text,
                subtitle: previewOnly
                    ? typeLabel
                    : (isAction ? '该行动可能触发判定' : ''),
                highlighted: previewOnly ? (isAction || isBattle) : isAction,
                onTap: () async {
                  Navigator.of(context).pop();
                  if (!previewOnly) {
                    await controller.selectChoice(choice);
                  }
                },
              );
            },
          ),
        );
      },
    ),
  );
}
