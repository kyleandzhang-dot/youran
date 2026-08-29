part of '../novel_sheets.dart';

// ============================================================================
// 场景地图页
// 页面入口 / 对外入口：
//   - showNovelSceneMapSheet(...)
// 其余以下划线 `_` 开头的类型/方法均为该页面内部实现或共享私有实现。
// ============================================================================

Future<void> showNovelSceneMapSheet(
  BuildContext context,
  NovelGameController controller,
) async {
  await _runNovelPageOnce('scene-map:${controller.sessionId}', () async {
    // 面板先打开再刷新，避免网络稍慢时用户点击地点却没有即时反馈。
    unawaited(controller.refreshSceneMap(force: true));
    await _showNovelSheet<void>(
      context,
      heightFactor: .88,
      child: _NovelSceneMapPanel(controller: controller),
    );
  });
}

class _NovelSceneMapPanel extends StatefulWidget {
  const _NovelSceneMapPanel({required this.controller});

  final NovelGameController controller;

  @override
  State<_NovelSceneMapPanel> createState() => _NovelSceneMapPanelState();
}

class _NovelSceneMapPanelState extends State<_NovelSceneMapPanel> {
  String _selectedSceneId = '';

  NovelGameController get controller => widget.controller;

  Future<void> _moveTo(NovelSceneMapNode target) async {
    final accepted = await controller.requestSceneMove(target);
    if (!mounted) return;
    if (accepted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final map = controller.sceneMap;
        final currentName = map.currentScene.name.isNotEmpty
            ? map.currentScene.name
            : controller.locationTitle;

        return _SheetScaffold(
          title: '场景地图',
          subtitle: currentName.isEmpty
              ? '探索会逐步显现相邻场景'
              : '当前位置 · $currentName',
          trailing: _SceneMapRefreshButton(
            loading: controller.isSceneMapLoading,
            onTap: () => unawaited(
              controller.refreshSceneMap(force: true),
            ),
          ),
          child: _buildBody(map),
        );
      },
    );
  }

  Widget _buildBody(NovelSceneMapData map) {
    if (controller.isSceneMapLoading && !map.hasCurrentScene) {
      return const _SceneMapLoadingState();
    }

    if (controller.sceneMapError.isNotEmpty && !map.hasCurrentScene) {
      return _SceneMapEmptyState(
        icon: Icons.cloud_off_outlined,
        title: '地图暂时无法载入',
        detail: controller.sceneMapError,
        actionLabel: '重新载入',
        onAction: () => unawaited(
          controller.refreshSceneMap(force: true),
        ),
      );
    }

    if (!map.configured) {
      return _SceneMapEmptyState(
        icon: Icons.map_outlined,
        title: '这片世界尚未绘制地图',
        detail: '剧情仍可正常进行；配置场景连接后，附近地点会在这里逐步出现。',
        actionLabel: '重新检查',
        onAction: () => unawaited(
          controller.refreshSceneMap(force: true),
        ),
      );
    }

    final moveBlock = controller.sceneMoveDisabledReason;
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 26),
      children: <Widget>[
        if (controller.sceneMoveError.isNotEmpty) ...<Widget>[
          _SceneMapStatusBanner(
            icon: Icons.error_outline_rounded,
            text: controller.sceneMoveError,
            color: NovelPalette.danger,
          ),
          const SizedBox(height: 10),
        ] else if (moveBlock.isNotEmpty) ...<Widget>[
          _SceneMapStatusBanner(
            icon: map.mobility.combatActive
                ? Icons.shield_outlined
                : Icons.lock_outline_rounded,
            text: moveBlock,
            color: map.mobility.combatActive
                ? NovelPalette.danger
                : NovelPalette.warning,
          ),
          const SizedBox(height: 10),
        ],
        _SceneMapCurrentCard(
          node: map.currentScene,
          fallbackName: controller.locationTitle,
        ),
        if (map.targets.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(34, 22, 8, 8),
            child: Text(
              '附近暂时没有已发现的出口',
              style: TextStyle(
                color: NovelPalette.muted,
                fontSize: 11.5,
                height: 1.45,
              ),
            ),
          )
        else ...<Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(34, 18, 0, 10),
            child: Row(
              children: <Widget>[
                Text(
                  '附近场景',
                  style: TextStyle(
                    color: Colors.white.withOpacity(.86),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: .8,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${map.targets.length}',
                  style: const TextStyle(
                    color: NovelPalette.muted,
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),
          ),
          for (var index = 0; index < map.targets.length; index++)
            Padding(
              padding: EdgeInsets.only(
                bottom: index == map.targets.length - 1 ? 0 : 8,
              ),
              child: _SceneMapTargetTile(
                node: map.targets[index],
                selected: _selectedSceneId == map.targets[index].sceneId,
                isLast: index == map.targets.length - 1,
                canMove: controller.canMoveToScene(map.targets[index]),
                disabledReason: map.targets[index].isLocked
                    ? map.targets[index].reason
                    : moveBlock,
                submitting: controller.isSceneMoveSubmitting,
                onTap: () {
                  setState(() {
                    _selectedSceneId =
                        _selectedSceneId == map.targets[index].sceneId
                            ? ''
                            : map.targets[index].sceneId;
                  });
                },
                onMove: () => _moveTo(map.targets[index]),
              ),
            ),
        ],
      ],
    );
  }
}

class _SceneMapRefreshButton extends StatelessWidget {
  const _SceneMapRefreshButton({
    required this.loading,
    required this.onTap,
  });

  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '刷新附近场景',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: loading ? null : onTap,
          borderRadius: BorderRadius.circular(18),
          child: SizedBox(
            width: 34,
            height: 34,
            child: Center(
              child: loading
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.4,
                        color: NovelPalette.accent,
                      ),
                    )
                  : const Icon(
                      Icons.refresh_rounded,
                      size: 18,
                      color: NovelPalette.muted,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SceneMapLoadingState extends StatelessWidget {
  const _SceneMapLoadingState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 1.6,
              color: NovelPalette.accent,
            ),
          ),
          SizedBox(height: 14),
          Text(
            '正在确认附近路线…',
            style: TextStyle(
              color: NovelPalette.muted,
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _SceneMapEmptyState extends StatelessWidget {
  const _SceneMapEmptyState({
    required this.icon,
    required this.title,
    required this.detail,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String detail;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 34),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(.035),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withOpacity(.08)),
              ),
              child: Icon(icon, size: 22, color: NovelPalette.muted),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: NovelPalette.text,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: NovelPalette.muted,
                fontSize: 11,
                height: 1.55,
              ),
            ),
            const SizedBox(height: 18),
            TextButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: Text(actionLabel),
              style: TextButton.styleFrom(
                foregroundColor: NovelPalette.accent,
                textStyle: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SceneMapStatusBanner extends StatelessWidget {
  const _SceneMapStatusBanner({
    required this.icon,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: color.withOpacity(.07),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(.20)),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 15, color: color.withOpacity(.92)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: Colors.white.withOpacity(.76),
                fontSize: 10.5,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SceneMapCurrentCard extends StatelessWidget {
  const _SceneMapCurrentCard({
    required this.node,
    required this.fallbackName,
  });

  final NovelSceneMapNode node;
  final String fallbackName;

  @override
  Widget build(BuildContext context) {
    final name = node.name.isNotEmpty ? node.name : fallbackName;
    return Padding(
      padding: const EdgeInsets.only(left: 34),
      child: Container(
        padding: const EdgeInsets.fromLTRB(13, 12, 12, 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              NovelPalette.accent.withOpacity(.105),
              Colors.white.withOpacity(.018),
            ],
          ),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: NovelPalette.accent.withOpacity(.34)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: NovelPalette.accent.withOpacity(.12),
                shape: BoxShape.circle,
                border: Border.all(
                  color: NovelPalette.accent.withOpacity(.28),
                ),
              ),
              child: const Icon(
                Icons.my_location_rounded,
                size: 16,
                color: NovelPalette.accent,
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          name.isEmpty ? '当前位置' : name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: NovelPalette.text,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const _SceneMapTinyLabel(
                        text: '当前位置',
                        color: NovelPalette.accent,
                      ),
                    ],
                  ),
                  if (node.description.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 5),
                    Text(
                      node.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: NovelPalette.muted,
                        fontSize: 10.5,
                        height: 1.45,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SceneMapTargetTile extends StatelessWidget {
  const _SceneMapTargetTile({
    required this.node,
    required this.selected,
    required this.isLast,
    required this.canMove,
    required this.disabledReason,
    required this.submitting,
    required this.onTap,
    required this.onMove,
  });

  final NovelSceneMapNode node;
  final bool selected;
  final bool isLast;
  final bool canMove;
  final String disabledReason;
  final bool submitting;
  final VoidCallback onTap;
  final VoidCallback onMove;

  Color get _tone {
    if (node.isAvailable) return NovelPalette.accent;
    if (node.isRisky) return NovelPalette.warning;
    return NovelPalette.muted;
  }

  String get _stateLabel {
    if (node.isAvailable) return node.visited ? '可前往 · 已到访' : '可前往';
    if (node.isRisky) return '存在风险';
    return '暂不可达';
  }

  @override
  Widget build(BuildContext context) {
    final tone = _tone;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _SceneMapBranchRail(color: tone, isLast: isLast),
          Expanded(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(10),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.fromLTRB(12, 11, 10, 11),
                  decoration: BoxDecoration(
                    color: selected
                        ? tone.withOpacity(.070)
                        : Colors.white.withOpacity(.018),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: selected
                          ? tone.withOpacity(.34)
                          : Colors.white.withOpacity(.065),
                    ),
                  ),
                  child: AnimatedSize(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Icon(
                              node.isLocked
                                  ? Icons.lock_outline_rounded
                                  : node.isRisky
                                      ? Icons.warning_amber_rounded
                                      : Icons.place_outlined,
                              size: 16,
                              color: tone,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                node.name.isEmpty ? '未命名场景' : node.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: node.isLocked
                                      ? Colors.white.withOpacity(.58)
                                      : NovelPalette.text,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            _SceneMapTinyLabel(text: _stateLabel, color: tone),
                            const SizedBox(width: 3),
                            AnimatedRotation(
                              turns: selected ? .5 : 0,
                              duration: const Duration(milliseconds: 180),
                              child: const Icon(
                                Icons.keyboard_arrow_down_rounded,
                                size: 17,
                                color: NovelPalette.muted,
                              ),
                            ),
                          ],
                        ),
                        if (node.exitName.isNotEmpty) ...<Widget>[
                          const SizedBox(height: 5),
                          Text(
                            '经由 ${node.exitName}',
                            style: TextStyle(
                              color: Colors.white.withOpacity(.44),
                              fontSize: 9.5,
                            ),
                          ),
                        ],
                        if (selected) ...<Widget>[
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Divider(
                              height: 1,
                              color: Colors.white.withOpacity(.06),
                            ),
                          ),
                          if (node.description.isNotEmpty)
                            Text(
                              node.description,
                              style: const TextStyle(
                                color: NovelPalette.muted,
                                fontSize: 10.5,
                                height: 1.5,
                              ),
                            ),
                          if (node.presentNpcs.isNotEmpty) ...<Widget>[
                            const SizedBox(height: 7),
                            Text(
                              '可见人物 · ${node.presentNpcs.join('、')}',
                              style: TextStyle(
                                color: Colors.white.withOpacity(.55),
                                fontSize: 9.8,
                              ),
                            ),
                          ],
                          if (disabledReason.trim().isNotEmpty) ...<Widget>[
                            const SizedBox(height: 8),
                            Text(
                              disabledReason,
                              style: TextStyle(
                                color: tone.withOpacity(.90),
                                fontSize: 10.2,
                                height: 1.4,
                              ),
                            ),
                          ],
                          const SizedBox(height: 11),
                          _SceneMapMoveButton(
                            color: tone,
                            risky: node.isRisky,
                            enabled: canMove && !submitting,
                            loading: submitting,
                            onTap: onMove,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SceneMapBranchRail extends StatelessWidget {
  const _SceneMapBranchRail({required this.color, required this.isLast});

  final Color color;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 34,
      child: Stack(
        children: <Widget>[
          Positioned(
            left: 13,
            top: 0,
            bottom: isLast ? null : 0,
            height: isLast ? 24 : null,
            child: Container(
              width: 1,
              color: Colors.white.withOpacity(.13),
            ),
          ),
          Positioned(
            left: 13,
            top: 23,
            width: 17,
            child: Container(
              height: 1,
              color: Colors.white.withOpacity(.13),
            ),
          ),
          Positioned(
            left: 10,
            top: 20,
            child: Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.black.withOpacity(.45),
                  width: 1.5,
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: color.withOpacity(.28),
                    blurRadius: 7,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SceneMapTinyLabel extends StatelessWidget {
  const _SceneMapTinyLabel({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(.085),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(.20)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color.withOpacity(.94),
          fontSize: 8.5,
          height: 1,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _SceneMapMoveButton extends StatelessWidget {
  const _SceneMapMoveButton({
    required this.color,
    required this.risky,
    required this.enabled,
    required this.loading,
    required this.onTap,
  });

  final Color color;
  final bool risky;
  final bool enabled;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 36,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: enabled
                  ? color.withOpacity(.13)
                  : Colors.white.withOpacity(.025),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: enabled
                    ? color.withOpacity(.34)
                    : Colors.white.withOpacity(.06),
              ),
            ),
            child: loading
                ? SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.4,
                      color: color,
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        risky
                            ? Icons.casino_outlined
                            : Icons.directions_walk_rounded,
                        size: 15,
                        color: enabled ? color : NovelPalette.muted,
                      ),
                      const SizedBox(width: 7),
                      Text(
                        risky ? '尝试前往 · 需要检定' : '前往此处',
                        style: TextStyle(
                          color: enabled ? color : NovelPalette.muted,
                          fontSize: 10.8,
                          fontWeight: FontWeight.w600,
                          letterSpacing: .3,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
