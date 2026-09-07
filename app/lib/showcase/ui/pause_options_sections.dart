part of 'pause_options.dart';

final class _PauseSectionContent extends StatelessWidget {
  const _PauseSectionContent({
    required this.section,
    required this.compact,
    required this.controller,
    required this.callbacks,
    required this.onStartRebinding,
  });

  final PauseOptionsSection section;
  final bool compact;
  final OptionsController controller;
  final PauseMenuCallbacks callbacks;
  final ValueChanged<GameInputAction> onStartRebinding;

  @override
  Widget build(BuildContext context) => switch (section) {
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
              onPressed: callbacks.onResume,
              icon: Icons.play_arrow,
              label: 'Resume game',
              primary: true,
            ),
            const SizedBox(height: 9),
            _BlockButton(
              key: PauseOptionsKeys.worldLibrary,
              onPressed: callbacks.onOpenWorldLibrary,
              icon: Icons.public,
              label: 'World Library',
            ),
            const SizedBox(height: 9),
            _BlockButton(
              key: PauseOptionsKeys.renderLab,
              onPressed: callbacks.onOpenRenderLab,
              icon: Icons.science_outlined,
              label: 'Render Lab',
            ),
            const SizedBox(height: 14),
            ControlsHint(controller: controller),
            const SizedBox(height: 18),
            _BlockButton(
              key: PauseOptionsKeys.saveAndQuit,
              onPressed: callbacks.onSaveAndQuit,
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
              valueLabel: '${(controller.mouseSensitivity * 100).round()}%',
              value: controller.mouseSensitivity,
              min: 0.05,
              max: 1,
              divisions: 19,
              onChanged: controller.setMouseSensitivity,
            ),
            SwitchListTile(
              key: PauseOptionsKeys.invertMouse,
              contentPadding: EdgeInsets.zero,
              title: const Text('Invert vertical look'),
              subtitle: const Text('Mouse up looks down'),
              value: controller.invertMouseY,
              onChanged: controller.setInvertMouseY,
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      ShowcasePanel(
        title: 'Key bindings',
        subtitle: 'Choose an action, then press a key. Conflicts swap keys.',
        trailing: TextButton(
          onPressed: controller.resetBindings,
          child: const Text('Reset'),
        ),
        child: Column(
          children: <Widget>[
            if (controller.rebindingAction != null)
              Semantics(
                liveRegion: true,
                label:
                    'Waiting for a key for ${controller.rebindingAction!.label}',
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
                  onPressed: () => onStartRebinding(action),
                  child: Text(
                    controller.rebindingAction == action
                        ? 'Press a key…'
                        : controller.bindingLabel(action),
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
                selected: controller.fogPreset == preset,
                onSelected: (_) => controller.setFogPreset(preset),
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
              value: controller.audioMuted,
              onChanged: controller.setAudioMuted,
            ),
            LabeledSlider(
              label: 'Master volume',
              valueLabel: _percent(controller.masterVolume),
              value: controller.masterVolume,
              min: 0,
              max: 1,
              divisions: 20,
              onChanged: controller.setMasterVolume,
            ),
            LabeledSlider(
              label: 'Block effects',
              valueLabel: _percent(controller.effectsVolume),
              value: controller.effectsVolume,
              min: 0,
              max: 1,
              divisions: 20,
              onChanged: controller.setEffectsVolume,
            ),
            LabeledSlider(
              label: 'Ambience',
              valueLabel: _percent(controller.ambienceVolume),
              value: controller.ambienceVolume,
              min: 0,
              max: 1,
              divisions: 20,
              onChanged: controller.setAmbienceVolume,
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
              value: controller.highContrast,
              onChanged: controller.setHighContrast,
            ),
            SwitchListTile(
              key: PauseOptionsKeys.reducedMotion,
              contentPadding: EdgeInsets.zero,
              title: const Text('Reduced motion'),
              subtitle: const Text('Minimize camera and UI movement'),
              value: controller.reducedMotion,
              onChanged: controller.setReducedMotion,
            ),
          ],
        ),
      ),
    ],
  );

  static String _percent(double value) => '${(value * 100).round()}%';
}

final class _BlockPanel extends StatelessWidget {
  const _BlockPanel({required this.child, required this.controller, super.key});

  final Widget child;
  final OptionsController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    child: child,
    builder: (context, child) {
      final colors = Theme.of(context).colorScheme;
      final highContrast =
          controller.highContrast || MediaQuery.highContrastOf(context);
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
    },
  );
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
      label: label,
      selected: selected,
      button: true,
      onTap: onPressed,
      excludeSemantics: true,
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
