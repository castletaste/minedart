/// Non-interactive control legend shared by Pause and the world-start hint.
///
/// The legend is presentation only: it never takes pointer input, never joins
/// focus traversal, and collapses to a single accessible summary node so a
/// screen reader announces the whole scheme once instead of nine fragments.
library;

import 'package:flutter/material.dart';

/// One legend row: the printed key cap, the action it performs, and the
/// spoken form used to build the accessible summary.
@immutable
final class ControlsHintEntry {
  const ControlsHintEntry({
    required this.keys,
    required this.action,
    required this.spokenKeys,
  });

  /// Compact key cap text, e.g. `WASD` or `1-9`.
  final String keys;

  /// Action label, e.g. `Move`.
  final String action;

  /// Screen-reader friendly spelling of [keys], e.g. `1 to 9`.
  final String spokenKeys;
}

abstract final class ControlsHintKeys {
  static const root = ValueKey<String>('controls-hint');
  static const oneColumn = ValueKey<String>('controls-hint-1-column');
  static const twoColumns = ValueKey<String>('controls-hint-2-columns');
  static const threeColumns = ValueKey<String>('controls-hint-3-columns');

  static ValueKey<String> column(int columns) => switch (columns) {
    1 => oneColumn,
    2 => twoColumns,
    _ => threeColumns,
  };
}

/// Monospace label style used by the block-game UI surfaces. Mirrors the HUD
/// debug overlay so Pause, the legend and the HUD read as one typeface family
/// without shipping a custom font.
TextStyle blockMonoStyle(
  BuildContext context, {
  double fontSize = 13,
  FontWeight fontWeight = FontWeight.w600,
  Color? color,
  double letterSpacing = 0.6,
}) => TextStyle(
  fontSize: fontSize,
  fontWeight: fontWeight,
  height: 1.25,
  letterSpacing: letterSpacing,
  color: color ?? Theme.of(context).colorScheme.onSurface,
  fontFamily: 'monospace',
  fontFamilyFallback: const <String>['Menlo', 'Courier'],
);

/// Reusable legend of the default control scheme.
final class ControlsHint extends StatelessWidget {
  const ControlsHint({this.title = 'Controls', this.maxColumns = 3, super.key});

  /// Optional caption above the legend. Pass `null` to hide it.
  final String? title;

  /// Upper bound on legend columns; the real count follows parent constraints.
  final int maxColumns;

  static const List<ControlsHintEntry> entries = <ControlsHintEntry>[
    ControlsHintEntry(keys: 'WASD', action: 'Move', spokenKeys: 'W A S D'),
    ControlsHintEntry(
      keys: 'W W',
      action: 'Sprint',
      spokenKeys: 'Double tap W',
    ),
    ControlsHintEntry(keys: 'Space', action: 'Jump', spokenKeys: 'Space'),
    ControlsHintEntry(keys: 'N', action: 'Noclip', spokenKeys: 'N'),
    ControlsHintEntry(
      keys: 'LMB',
      action: 'Break',
      spokenKeys: 'Left mouse button',
    ),
    ControlsHintEntry(
      keys: 'RMB',
      action: 'Place',
      spokenKeys: 'Right mouse button',
    ),
    ControlsHintEntry(keys: 'E', action: 'Inventory', spokenKeys: 'E'),
    ControlsHintEntry(keys: '1-9', action: 'Hotbar', spokenKeys: '1 to 9'),
    ControlsHintEntry(keys: 'F', action: 'Fog', spokenKeys: 'F'),
    ControlsHintEntry(keys: 'F3', action: 'Debug', spokenKeys: 'F3'),
    ControlsHintEntry(keys: 'Esc', action: 'Pause', spokenKeys: 'Escape'),
  ];

  /// Single spoken summary for the whole legend.
  static String get semanticsSummary {
    final parts = entries.map(
      (entry) => '${entry.spokenKeys} ${entry.action.toLowerCase()}',
    );
    return 'Controls: ${parts.join(', ')}.';
  }

  @override
  Widget build(BuildContext context) => Semantics(
    key: ControlsHintKeys.root,
    container: true,
    excludeSemantics: true,
    label: semanticsSummary,
    child: ExcludeFocus(
      child: IgnorePointer(
        child: LayoutBuilder(
          builder: (context, constraints) => _legend(context, constraints),
        ),
      ),
    ),
  );

  Widget _legend(BuildContext context, BoxConstraints constraints) {
    final colors = Theme.of(context).colorScheme;
    final highContrast = MediaQuery.highContrastOf(context);
    final width = constraints.maxWidth;
    final columns = _columnsFor(width);
    const spacing = 10.0;
    final itemWidth = width.isFinite
        ? (width - spacing * (columns - 1)) / columns
        : null;

    return Column(
      key: ControlsHintKeys.column(columns),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (title case final caption?) ...<Widget>[
          Text(
            caption.toUpperCase(),
            style: blockMonoStyle(
              context,
              fontSize: 11,
              letterSpacing: 1.4,
              color: highContrast ? colors.onSurface : colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
        ],
        Wrap(
          spacing: spacing,
          runSpacing: 6,
          children: <Widget>[
            for (final entry in entries)
              SizedBox(
                width: itemWidth,
                child: _ControlsHintRow(
                  entry: entry,
                  highContrast: highContrast,
                ),
              ),
          ],
        ),
      ],
    );
  }

  int _columnsFor(double width) {
    if (!width.isFinite) return maxColumns.clamp(1, 3).toInt();
    final fits = width >= 540
        ? 3
        : width >= 260
        ? 2
        : 1;
    return fits.clamp(1, maxColumns.clamp(1, 3)).toInt();
  }
}

final class _ControlsHintRow extends StatelessWidget {
  const _ControlsHintRow({required this.entry, required this.highContrast});

  final ControlsHintEntry entry;
  final bool highContrast;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _KeyCap(label: entry.keys, highContrast: highContrast),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            entry.action,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: blockMonoStyle(
              context,
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: highContrast ? colors.onSurface : colors.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

final class _KeyCap extends StatelessWidget {
  const _KeyCap({required this.label, required this.highContrast});

  final String label;
  final bool highContrast;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final edge = highContrast ? 2.0 : 1.5;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 42),
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest,
          border: Border(
            top: BorderSide(color: colors.surfaceBright, width: edge),
            left: BorderSide(color: colors.surfaceBright, width: edge),
            right: BorderSide(color: colors.surfaceDim, width: edge),
            bottom: BorderSide(color: colors.surfaceDim, width: edge),
          ),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.clip,
          style: blockMonoStyle(
            context,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
            color: colors.onSurface,
          ),
        ),
      ),
    );
  }
}
