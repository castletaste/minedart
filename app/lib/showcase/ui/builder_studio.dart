import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../hud/block_palette.dart';
import '../controller/builder_studio_controller.dart';
import 'modal_input_region.dart';

enum BuilderStudioSizeClass { compact, medium, expanded }

abstract final class BuilderStudioKeys {
  static const compact = ValueKey<String>('builder-studio-compact');
  static const medium = ValueKey<String>('builder-studio-medium');
  static const expanded = ValueKey<String>('builder-studio-expanded');
  static const search = ValueKey<String>('builder-studio-search');
  static const catalog = ValueKey<String>('builder-studio-catalog');
  static const assign = ValueKey<String>('builder-studio-assign');
  static const selectedSlot = ValueKey<String>('builder-selected-slot');

  static ValueKey<String> block(int blockId) =>
      ValueKey<String>('builder-block-$blockId');

  static ValueKey<String> blockSemantics(int blockId) =>
      ValueKey<String>('builder-block-semantics-$blockId');

  static ValueKey<String> hotbar(int slot) =>
      ValueKey<String>('builder-hotbar-$slot');
}

Future<void> showBuilderStudio(
  BuildContext context, {
  required BuilderStudioController controller,
  ValueChanged<bool>? onInputCaptureChanged,
  LogicalKeyboardKey closeKey = LogicalKeyboardKey.keyE,
}) => showGeneralDialog<void>(
  context: context,
  barrierDismissible: true,
  barrierLabel: 'Close Block inventory',
  barrierColor: Colors.black54,
  requestFocus: true,
  transitionDuration: const Duration(milliseconds: 140),
  pageBuilder: (dialogContext, _, _) => BuilderStudioView(
    controller: controller,
    onClose: () => Navigator.of(dialogContext).pop(),
    onInputCaptureChanged: onInputCaptureChanged,
    closeKey: closeKey,
  ),
);

final class BuilderStudioView extends StatelessWidget {
  const BuilderStudioView({
    required this.controller,
    required this.onClose,
    this.onInputCaptureChanged,
    this.closeKey = LogicalKeyboardKey.keyE,
    super.key,
  });

  static const double compactBreakpoint = 600;
  static const double expandedBreakpoint = 900;
  static const double maxInventoryWidth = 440;
  static const double maxInventoryHeight = 430;

  final BuilderStudioController controller;
  final VoidCallback onClose;
  final ValueChanged<bool>? onInputCaptureChanged;
  final LogicalKeyboardKey closeKey;

  static BuilderStudioSizeClass sizeClassFor(double width) {
    if (width < compactBreakpoint) return BuilderStudioSizeClass.compact;
    if (width < expandedBreakpoint) return BuilderStudioSizeClass.medium;
    return BuilderStudioSizeClass.expanded;
  }

  Map<ShortcutActivator, VoidCallback> get _shortcuts =>
      <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): onClose,
        SingleActivator(closeKey): onClose,
        for (var slot = 0; slot < _digitKeys.length; slot++)
          SingleActivator(_digitKeys[slot]): () {
            controller.selectHotbarSlot(slot);
          },
      };

  void _activateBlock(int blockId) {
    controller.assignBlockToHotbar(blockId, controller.selectedHotbarSlot);
    onClose();
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: _shortcuts,
    child: ModalInputRegion(
      onInputCaptureChanged: onInputCaptureChanged,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final sizeClass = BuilderStudioView.sizeClassFor(
            constraints.maxWidth,
          );
          final availableWidth = math.max(0.0, constraints.maxWidth - 24);
          final availableHeight = math.max(0.0, constraints.maxHeight - 24);
          return Center(
            child: SizedBox(
              key: switch (sizeClass) {
                BuilderStudioSizeClass.compact => BuilderStudioKeys.compact,
                BuilderStudioSizeClass.medium => BuilderStudioKeys.medium,
                BuilderStudioSizeClass.expanded => BuilderStudioKeys.expanded,
              },
              width: math.min(
                BuilderStudioView.maxInventoryWidth,
                availableWidth,
              ),
              height: math.min(
                BuilderStudioView.maxInventoryHeight,
                availableHeight,
              ),
              child: _surface(context),
            ),
          );
        },
      ),
    ),
  );

  Widget _surface(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surface,
      elevation: 18,
      clipBehavior: Clip.antiAlias,
      borderRadius: BorderRadius.circular(12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: colors.outline, width: 2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: SafeArea(
          child: AnimatedBuilder(
            animation: controller,
            builder: (context, _) => _content(context),
          ),
        ),
      ),
    );
  }

  Widget _content(BuildContext context) {
    final targetBlock = controller.entryFor(
      controller.hotbar[controller.selectedHotbarSlot],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 6, 2),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    'Block inventory',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Close Block inventory',
                onPressed: onClose,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Semantics(
            key: BuilderStudioKeys.selectedSlot,
            liveRegion: true,
            label:
                'Target hotbar slot ${controller.selectedHotbarSlot + 1}, '
                '${targetBlock?.name ?? 'empty'}',
            child: Text(
              'Replace slot ${controller.selectedHotbarSlot + 1} · '
              '${targetBlock?.name ?? 'empty'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(child: _catalog(context)),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          child: Text(
            '1–9 choose slot  ·  ${_keyLabel(closeKey)} / Esc close',
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  Widget _catalog(BuildContext context) {
    final blocks = controller.visibleBlocks;
    if (blocks.isEmpty) {
      return Center(
        child: Semantics(
          liveRegion: true,
          child: const Text('Every block is already in the hotbar.'),
        ),
      );
    }
    return GridView.builder(
      key: BuilderStudioKeys.catalog,
      padding: const EdgeInsets.all(10),
      itemCount: blocks.length,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 100,
        mainAxisExtent: 92,
        crossAxisSpacing: 7,
        mainAxisSpacing: 7,
      ),
      itemBuilder: (context, index) {
        final entry = blocks[index];
        return _BlockTile(
          entry: entry,
          onPressed: () => _activateBlock(entry.id),
        );
      },
    );
  }
}

final class _BlockTile extends StatelessWidget {
  const _BlockTile({required this.entry, required this.onPressed});

  final BlockCatalogEntry entry;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    key: BuilderStudioKeys.blockSemantics(entry.id),
    label: entry.semanticsLabel,
    hint:
        'Replace the selected hotbar slot with this block and close inventory',
    button: true,
    onTap: onPressed,
    excludeSemantics: true,
    child: OutlinedButton(
      key: BuilderStudioKeys.block(entry.id),
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.all(6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          DecoratedBox(
            decoration: BoxDecoration(
              color: blockColor(entry.id),
              border: Border.all(color: Colors.black45),
              borderRadius: BorderRadius.circular(3),
            ),
            child: const SizedBox.square(dimension: 38),
          ),
          const SizedBox(height: 5),
          Text(
            entry.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    ),
  );
}

String _keyLabel(LogicalKeyboardKey key) {
  final label = key.keyLabel.trim();
  return label.isEmpty ? 'Key ${key.keyId}' : label.toUpperCase();
}

const List<LogicalKeyboardKey> _digitKeys = <LogicalKeyboardKey>[
  LogicalKeyboardKey.digit1,
  LogicalKeyboardKey.digit2,
  LogicalKeyboardKey.digit3,
  LogicalKeyboardKey.digit4,
  LogicalKeyboardKey.digit5,
  LogicalKeyboardKey.digit6,
  LogicalKeyboardKey.digit7,
  LogicalKeyboardKey.digit8,
  LogicalKeyboardKey.digit9,
];
