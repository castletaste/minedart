import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controller/options_controller.dart';
import 'controls_hint.dart';
import 'modal_input_region.dart';
import 'showcase_panel.dart';

part 'pause_options_sections.dart';

enum PauseOptionsSection {
  pause('Pause', Icons.pause_circle_outline),
  controls('Controls', Icons.keyboard_alt_outlined),
  graphics('Graphics', Icons.landscape_outlined),
  audio('Audio', Icons.volume_up_outlined),
  accessibility('Accessibility', Icons.accessibility_new_outlined);

  const PauseOptionsSection(this.label, this.icon);

  final String label;
  final IconData icon;
}

abstract final class PauseOptionsKeys {
  static const compact = ValueKey<String>('pause-options-compact');
  static const expanded = ValueKey<String>('pause-options-expanded');
  static const dimmer = ValueKey<String>('pause-options-dimmer');
  static const panel = ValueKey<String>('pause-options-panel');
  static const resume = ValueKey<String>('pause-options-resume');
  static const worldLibrary = ValueKey<String>('pause-options-world-library');
  static const renderLab = ValueKey<String>('pause-options-render-lab');
  static const saveAndQuit = ValueKey<String>('pause-options-save-and-quit');
  static const mouseSensitivity = ValueKey<String>('options-mouse-sensitivity');
  static const invertMouse = ValueKey<String>('options-invert-mouse');
  static const audioMuted = ValueKey<String>('options-audio-muted');
  static const highContrast = ValueKey<String>('options-high-contrast');
  static const reducedMotion = ValueKey<String>('options-reduced-motion');

  static ValueKey<String> section(PauseOptionsSection section) =>
      ValueKey<String>('pause-section-${section.name}');

  static ValueKey<String> binding(GameInputAction action) =>
      ValueKey<String>('options-binding-${action.name}');

  static ValueKey<String> fog(FogPreset preset) =>
      ValueKey<String>('options-fog-${preset.name}');
}

@immutable
final class PauseMenuCallbacks {
  const PauseMenuCallbacks({
    required this.onResume,
    required this.onOpenWorldLibrary,
    required this.onOpenRenderLab,
    required this.onSaveAndQuit,
  });

  final VoidCallback onResume;
  final VoidCallback onOpenWorldLibrary;
  final VoidCallback onOpenRenderLab;
  final VoidCallback onSaveAndQuit;
}

/// Compact, keyboard-safe Pause surface over the still-visible game world.
final class PauseOptionsView extends StatefulWidget {
  const PauseOptionsView({
    required this.controller,
    required this.callbacks,
    this.onInputCaptureChanged,
    super.key,
  });

  final OptionsController controller;
  final PauseMenuCallbacks callbacks;
  final ValueChanged<bool>? onInputCaptureChanged;

  @override
  State<PauseOptionsView> createState() => _PauseOptionsViewState();
}

final class _PauseOptionsViewState extends State<PauseOptionsView> {
  PauseOptionsSection _section = PauseOptionsSection.pause;
  final FocusNode _keyboardFocus = FocusNode(debugLabel: 'Pause options');

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_syncRebindingFocus);
  }

  @override
  void didUpdateWidget(PauseOptionsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_syncRebindingFocus);
    widget.controller.addListener(_syncRebindingFocus);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncRebindingFocus);
    _keyboardFocus.dispose();
    super.dispose();
  }

  void _syncRebindingFocus() {
    if (widget.controller.rebindingAction == null || _keyboardFocus.hasFocus) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.controller.rebindingAction != null) {
        _keyboardFocus.requestFocus();
      }
    });
  }

  KeyEventResult _onKeyEvent(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (widget.controller.rebindingAction != null) {
      widget.controller.captureKey(event.logicalKey);
      return KeyEventResult.handled;
    }
    if (event.logicalKey != LogicalKeyboardKey.escape) {
      return KeyEventResult.ignored;
    }
    if (_section != PauseOptionsSection.pause) {
      setState(() => _section = PauseOptionsSection.pause);
    } else {
      widget.callbacks.onResume();
    }
    return KeyEventResult.handled;
  }

  void _startRebinding(GameInputAction action) {
    widget.controller.beginRebinding(action);
    _keyboardFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: _keyboardFocus,
    onKeyEvent: _onKeyEvent,
    child: ModalInputRegion(
      onInputCaptureChanged: widget.onInputCaptureChanged,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 700;
          return Stack(
            fit: StackFit.expand,
            children: <Widget>[
              const ColoredBox(
                key: PauseOptionsKeys.dimmer,
                color: Color(0xAA000000),
              ),
              SafeArea(
                minimum: const EdgeInsets.all(12),
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: compact ? 520 : 900,
                      maxHeight: constraints.maxHeight,
                    ),
                    child: _BlockPanel(
                      key: PauseOptionsKeys.panel,
                      controller: widget.controller,
                      child: compact ? _compact(context) : _expanded(context),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );

  Widget _compact(BuildContext context) => Column(
    key: PauseOptionsKeys.compact,
    children: <Widget>[
      _header(context),
      _horizontalNavigation(context),
      const _BlockDivider(),
      Expanded(child: _sectionBody(compact: true)),
    ],
  );

  Widget _expanded(BuildContext context) => Column(
    key: PauseOptionsKeys.expanded,
    children: <Widget>[
      _header(context),
      const _BlockDivider(),
      Expanded(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SizedBox(width: 184, child: _verticalNavigation(context)),
            const _BlockDivider(vertical: true),
            Expanded(child: _sectionBody(compact: false)),
          ],
        ),
      ),
    ],
  );

  Widget _header(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 10, 10),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                _section == PauseOptionsSection.pause
                    ? 'GAME PAUSED'
                    : _section.label.toUpperCase(),
                style: blockMonoStyle(
                  context,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.4,
                  color: colors.onSurface,
                ),
              ),
            ),
          ),
          _BlockButton(
            onPressed: widget.callbacks.onResume,
            icon: Icons.play_arrow,
            label: 'Resume',
            compact: true,
            key: PauseOptionsKeys.resume,
          ),
        ],
      ),
    );
  }

  Widget _horizontalNavigation(BuildContext context) => SizedBox(
    height: 48,
    child: ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      scrollDirection: Axis.horizontal,
      itemCount: PauseOptionsSection.values.length,
      separatorBuilder: (_, _) => const SizedBox(width: 6),
      itemBuilder: (context, index) {
        final section = PauseOptionsSection.values[index];
        return _SectionButton(
          key: PauseOptionsKeys.section(section),
          section: section,
          selected: _section == section,
          onPressed: () => setState(() => _section = section),
          compact: true,
        );
      },
    ),
  );

  Widget _verticalNavigation(BuildContext context) => ListView(
    padding: const EdgeInsets.all(12),
    children: <Widget>[
      for (final section in PauseOptionsSection.values)
        Padding(
          padding: const EdgeInsets.only(bottom: 7),
          child: _SectionButton(
            key: PauseOptionsKeys.section(section),
            section: section,
            selected: _section == section,
            onPressed: () => setState(() => _section = section),
          ),
        ),
    ],
  );

  Widget _sectionBody({required bool compact}) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) => _PauseSectionContent(
      section: _section,
      compact: compact,
      controller: widget.controller,
      callbacks: widget.callbacks,
      onStartRebinding: _startRebinding,
    ),
  );
}
