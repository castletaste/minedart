import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controller/options_controller.dart';
import 'controls_hint.dart';
import 'modal_input_region.dart';
import 'showcase_panel.dart';

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
  Widget build(BuildContext context) => ModalInputRegion(
    onInputCaptureChanged: widget.onInputCaptureChanged,
    child: Focus(
      focusNode: _keyboardFocus,
      autofocus: true,
      onKeyEvent: _onKeyEvent,
      child: AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) => LayoutBuilder(
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
                        highContrast:
                            widget.controller.highContrast ||
                            MediaQuery.highContrastOf(context),
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
    ),
  );

  Widget _compact(BuildContext context) => Column(
    key: PauseOptionsKeys.compact,
    children: <Widget>[
      _header(context),
      _horizontalNavigation(context),
      const _BlockDivider(),
      Expanded(child: _sectionBody(context, compact: true)),
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
            Expanded(child: _sectionBody(context, compact: false)),
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

  Widget _sectionBody(BuildContext context, {required bool compact}) =>
      switch (_section) {
        PauseOptionsSection.pause => _pauseMenu(context, compact: compact),
        PauseOptionsSection.controls => _controls(context),
        PauseOptionsSection.graphics => _graphics(context),
        PauseOptionsSection.audio => _audio(context),
        PauseOptionsSection.accessibility => _accessibility(context),
      };

  Widget _pauseMenu(BuildContext context, {required bool compact}) => ListView(
    padding: EdgeInsets.all(compact ? 14 : 20),
    children: <Widget>[
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _BlockButton(
              key: PauseOptionsKeys.resume,
              onPressed: widget.callbacks.onResume,
              icon: Icons.play_arrow,
              label: 'Resume game',
              primary: true,
            ),
            const SizedBox(height: 9),
            _BlockButton(
              key: PauseOptionsKeys.worldLibrary,
              onPressed: widget.callbacks.onOpenWorldLibrary,
              icon: Icons.public,
              label: 'World Library',
            ),
            const SizedBox(height: 9),
            _BlockButton(
              key: PauseOptionsKeys.renderLab,
              onPressed: widget.callbacks.onOpenRenderLab,
              icon: Icons.science_outlined,
              label: 'Render Lab',
            ),
            const SizedBox(height: 14),
            const ControlsHint(),
            const SizedBox(height: 18),
            _BlockButton(
              key: PauseOptionsKeys.saveAndQuit,
              onPressed: widget.callbacks.onSaveAndQuit,
              icon: Icons.save_outlined,
              label: 'Save and quit',
              destructive: true,
            ),
          ],
        ),
      ),
    ],
  );

  Widget _controls(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: <Widget>[
      ShowcasePanel(
        title: 'Mouse',
        child: Column(
          children: <Widget>[
            LabeledSlider(
              key: PauseOptionsKeys.mouseSensitivity,
              label: 'Mouse sensitivity',
              valueLabel:
                  '${(widget.controller.mouseSensitivity * 100).round()}%',
              value: widget.controller.mouseSensitivity,
              min: 0.05,
              max: 1,
              divisions: 19,
              onChanged: widget.controller.setMouseSensitivity,
            ),
            SwitchListTile(
              key: PauseOptionsKeys.invertMouse,
              contentPadding: EdgeInsets.zero,
              title: const Text('Invert vertical look'),
              subtitle: const Text('Mouse up looks down'),
              value: widget.controller.invertMouseY,
              onChanged: widget.controller.setInvertMouseY,
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      ShowcasePanel(
        title: 'Key bindings',
        subtitle: 'Choose an action, then press a key. Conflicts swap keys.',
        trailing: TextButton(
          onPressed: widget.controller.resetBindings,
          child: const Text('Reset'),
        ),
        child: Column(
          children: <Widget>[
            if (widget.controller.rebindingAction != null)
              Semantics(
                liveRegion: true,
                label:
                    'Waiting for a key for ${widget.controller.rebindingAction!.label}',
                child: Card(
                  color: Theme.of(context).colorScheme.tertiaryContainer,
                  child: const Padding(
                    padding: EdgeInsets.all(12),
                    child: Row(
                      children: <Widget>[
                        Icon(Icons.keyboard),
                        SizedBox(width: 8),
                        Expanded(child: Text('Press a key · Escape cancels')),
                      ],
                    ),
                  ),
                ),
              ),
            for (final action in GameInputAction.values)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(action.label),
                trailing: OutlinedButton(
                  key: PauseOptionsKeys.binding(action),
                  onPressed: () => _startRebinding(action),
                  child: Text(
                    widget.controller.rebindingAction == action
                        ? 'Press a key…'
                        : widget.controller.bindingLabel(action),
                  ),
                ),
              ),
          ],
        ),
      ),
    ],
  );

  Widget _graphics(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: <Widget>[
      ShowcasePanel(
        title: 'Fog distance',
        subtitle: 'F cycles the same presets in game.',
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final preset in FogPreset.values)
              ChoiceChip(
                key: PauseOptionsKeys.fog(preset),
                label: Text(preset.label),
                selected: widget.controller.fogPreset == preset,
                onSelected: (_) => widget.controller.setFogPreset(preset),
              ),
          ],
        ),
      ),
    ],
  );

  Widget _audio(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: <Widget>[
      ShowcasePanel(
        title: 'Audio',
        child: Column(
          children: <Widget>[
            SwitchListTile(
              key: PauseOptionsKeys.audioMuted,
              contentPadding: EdgeInsets.zero,
              title: const Text('Mute audio'),
              value: widget.controller.audioMuted,
              onChanged: widget.controller.setAudioMuted,
            ),
            LabeledSlider(
              label: 'Master volume',
              valueLabel: _percent(widget.controller.masterVolume),
              value: widget.controller.masterVolume,
              min: 0,
              max: 1,
              divisions: 20,
              onChanged: widget.controller.setMasterVolume,
            ),
            LabeledSlider(
              label: 'Block effects',
              valueLabel: _percent(widget.controller.effectsVolume),
              value: widget.controller.effectsVolume,
              min: 0,
              max: 1,
              divisions: 20,
              onChanged: widget.controller.setEffectsVolume,
            ),
            LabeledSlider(
              label: 'Ambience',
              valueLabel: _percent(widget.controller.ambienceVolume),
              value: widget.controller.ambienceVolume,
              min: 0,
              max: 1,
              divisions: 20,
              onChanged: widget.controller.setAmbienceVolume,
            ),
          ],
        ),
      ),
    ],
  );

  Widget _accessibility(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: <Widget>[
      ShowcasePanel(
        title: 'Accessibility',
        child: Column(
          children: <Widget>[
            SwitchListTile(
              key: PauseOptionsKeys.highContrast,
              contentPadding: EdgeInsets.zero,
              title: const Text('High contrast'),
              subtitle: const Text('Stronger outlines and UI separation'),
              value: widget.controller.highContrast,
              onChanged: widget.controller.setHighContrast,
            ),
            SwitchListTile(
              key: PauseOptionsKeys.reducedMotion,
              contentPadding: EdgeInsets.zero,
              title: const Text('Reduced motion'),
              subtitle: const Text('Minimize camera and UI movement'),
              value: widget.controller.reducedMotion,
              onChanged: widget.controller.setReducedMotion,
            ),
          ],
        ),
      ),
    ],
  );

  static String _percent(double value) => '${(value * 100).round()}%';
}

final class _BlockPanel extends StatelessWidget {
  const _BlockPanel({
    required this.child,
    required this.highContrast,
    super.key,
  });

  final Widget child;
  final bool highContrast;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final edge = highContrast ? 3.0 : 2.0;
    return Material(
      color: colors.surfaceContainer,
      elevation: 18,
      shadowColor: Colors.black,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: colors.surfaceBright, width: edge),
            left: BorderSide(color: colors.surfaceBright, width: edge),
            right: BorderSide(color: colors.surfaceDim, width: edge),
            bottom: BorderSide(color: colors.surfaceDim, width: edge),
          ),
        ),
        child: child,
      ),
    );
  }
}

final class _BlockDivider extends StatelessWidget {
  const _BlockDivider({this.vertical = false});

  final bool vertical;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.outlineVariant;
    return vertical
        ? VerticalDivider(width: 1, thickness: 1, color: color)
        : Divider(height: 1, thickness: 1, color: color);
  }
}

final class _SectionButton extends StatelessWidget {
  const _SectionButton({
    required this.section,
    required this.selected,
    required this.onPressed,
    this.compact = false,
    super.key,
  });

  final PauseOptionsSection section;
  final bool selected;
  final VoidCallback onPressed;
  final bool compact;

  @override
  Widget build(BuildContext context) => _BlockButton(
    onPressed: onPressed,
    icon: section.icon,
    label: section.label,
    selected: selected,
    compact: compact,
  );
}

final class _BlockButton extends StatelessWidget {
  const _BlockButton({
    required this.onPressed,
    required this.icon,
    required this.label,
    this.primary = false,
    this.destructive = false,
    this.selected = false,
    this.compact = false,
    super.key,
  });

  final VoidCallback onPressed;
  final IconData icon;
  final String label;
  final bool primary;
  final bool destructive;
  final bool selected;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final highContrast = MediaQuery.highContrastOf(context);
    final active = primary || selected;
    final background = destructive
        ? colors.errorContainer
        : active
        ? colors.primaryContainer
        : colors.surfaceContainerHighest;
    final foreground = destructive
        ? colors.onErrorContainer
        : active
        ? colors.onPrimaryContainer
        : colors.onSurface;
    final edge = highContrast ? 2.0 : 1.0;

    return Semantics(
      selected: selected,
      button: true,
      child: FocusableActionDetector(
        child: Builder(
          builder: (context) => InkWell(
            onTap: onPressed,
            focusColor: Colors.transparent,
            hoverColor: colors.primary.withValues(alpha: 0.12),
            child: AnimatedContainer(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 90),
              curve: Curves.easeOut,
              constraints: BoxConstraints(minHeight: compact ? 36 : 44),
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 10 : 14,
                vertical: compact ? 6 : 9,
              ),
              decoration: BoxDecoration(
                color: background,
                border: Border(
                  top: BorderSide(color: colors.surfaceBright, width: edge),
                  left: BorderSide(color: colors.surfaceBright, width: edge),
                  right: BorderSide(color: colors.surfaceDim, width: edge),
                  bottom: BorderSide(color: colors.surfaceDim, width: edge),
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: colors.shadow.withValues(alpha: 0.45),
                    offset: const Offset(2, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(icon, size: compact ? 17 : 19, color: foreground),
                  const SizedBox(width: 8),
                  if (compact)
                    Text(
                      label.toUpperCase(),
                      style: blockMonoStyle(
                        context,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.75,
                        color: foreground,
                      ),
                    )
                  else
                    Expanded(
                      child: Text(
                        label.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: blockMonoStyle(
                          context,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.75,
                          color: foreground,
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
