/// Bottom-center hotbar with nine block slots.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'block_palette.dart';
import 'hud_state.dart';

class Hotbar extends StatelessWidget {
  const Hotbar({required this.hud, this.interactionKey, super.key});

  static const double slotSize = 48;
  static const double slotGap = 4;

  final HudState hud;

  /// Bounds used by [HudOverlay] to keep hotbar clicks out of game actions.
  final GlobalKey? interactionKey;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: ListenableBuilder(
            listenable: Listenable.merge([
              hud.selectedSlot,
              hud.hotbarRevision,
            ]),
            builder: (context, _) {
              final selected = hud.selectedSlot.value;
              return DecoratedBox(
                key: interactionKey,
                decoration: BoxDecoration(
                  color: const Color(0x66000000),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      for (var i = 0; i < hud.blocks.length; i++)
                        Padding(
                          padding: EdgeInsets.only(
                            right: i == hud.blocks.length - 1 ? 0 : slotGap,
                          ),
                          child: _HotbarSlot(
                            blockId: hud.blocks[i],
                            index: i,
                            active: i == selected,
                            onActivate: () => hud.selectSlot(i),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

abstract final class HotbarKeys {
  static ValueKey<String> slot(int index) =>
      ValueKey<String>('hotbar-slot-$index');
}

class _HotbarSlot extends StatelessWidget {
  const _HotbarSlot({
    required this.blockId,
    required this.index,
    required this.active,
    required this.onActivate,
  });

  final int blockId;
  final int index;
  final bool active;
  final VoidCallback onActivate;

  @override
  Widget build(BuildContext context) {
    final label = 'Hotbar slot ${index + 1}: ${blockLabel(blockId)}';
    return Semantics(
      key: HotbarKeys.slot(index),
      button: true,
      selected: active,
      label: label,
      hint: active ? 'Selected' : 'Activate to select',
      onTap: onActivate,
      child: FocusableActionDetector(
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              onActivate();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onActivate,
          child: ExcludeSemantics(
            child: SizedBox(
              width: Hotbar.slotSize,
              height: Hotbar.slotSize + 12,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Container(
                    width: Hotbar.slotSize,
                    height: Hotbar.slotSize - 12,
                    decoration: BoxDecoration(
                      color: blockColor(blockId),
                      border: Border.all(
                        color: active
                            ? const Color(0xFFFFFFFF)
                            : const Color(0x55FFFFFF),
                        width: active ? 3 : 1,
                      ),
                    ),
                    alignment: Alignment.topLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 2, top: 1),
                      child: Text(
                        '${index + 1}',
                        style: const TextStyle(
                          fontSize: 10,
                          height: 1,
                          color: Color(0xFFFFFFFF),
                          shadows: <Shadow>[
                            Shadow(color: Color(0xFF000000), blurRadius: 2),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    blockLabel(blockId),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 8,
                      height: 1.1,
                      color: active
                          ? const Color(0xFFFFFFFF)
                          : const Color(0xBBFFFFFF),
                      shadows: const <Shadow>[
                        Shadow(color: Color(0xFF000000), blurRadius: 2),
                      ],
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
