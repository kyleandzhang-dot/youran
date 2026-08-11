import 'package:flutter/widgets.dart';

import '../../ending_page.dart';
import 'novel_game_controller.dart';
import 'novel_models.dart';
import 'novel_sheets.dart';

/// 把迁移后的 [NovelEnding] 与角色关系数据转换为你现有的 EndingPage 参数。
Widget buildExistingEndingPage(
  BuildContext context,
  NovelGameController controller,
  NovelEnding ending,
) {
  final bonds = <String, CharacterBond>{};
  for (final entry in controller.scenario?.characters.entries ??
      const <MapEntry<String, NovelCharacter>>[]) {
    final character = entry.value;
    if (character.isMain) continue;
    bonds[entry.key] = CharacterBond(
      name: character.name,
      affection: character.affection,
      avatarUrl: character.avatarUrl,
      relationship: character.affectionLabel,
    );
  }

  return EndingPage(
    text: ending.text,
    charsMap: bonds,
    milestones: ending.milestones,
    triggered_events: ending.triggeredEvents,
    backgroundImageUrl: ending.backgroundUrl.isEmpty
        ? controller.world.backgroundUrl
        : ending.backgroundUrl,
    endingTitle: ending.title,
    endingCode: ending.code,
    onClose: () => Navigator.of(context).pop(),
    onReplay: controller.currentTurn > 0
        ? () async {
            Navigator.of(context).pop();
            await controller.revertPreviousTurn();
          }
        : null,
    onArchive: () => showNovelJourneySheet(context, controller),
  );
}
