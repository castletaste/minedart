part of 'world_library.dart';

final class _CreateWorldDialog extends StatefulWidget {
  const _CreateWorldDialog();

  @override
  State<_CreateWorldDialog> createState() => _CreateWorldDialogState();
}

final class _CreateWorldDialogState extends State<_CreateWorldDialog> {
  final TextEditingController _nameController = TextEditingController(
    text: 'New World',
  );
  final TextEditingController _seedController = TextEditingController();
  late final Map<WorldLibraryPreset, FocusNode> _presetFocusNodes =
      <WorldLibraryPreset, FocusNode>{
        for (final preset in WorldLibraryPreset.values)
          preset: FocusNode(debugLabel: 'World preset ${preset.name}'),
      };
  WorldLibraryPreset _preset = WorldLibraryPreset.classic;

  @override
  void dispose() {
    _nameController.dispose();
    _seedController.dispose();
    for (final focusNode in _presetFocusNodes.values) {
      focusNode.dispose();
    }
    super.dispose();
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop((
      name: name,
      seed: int.tryParse(_seedController.text),
      preset: _preset,
    ));
  }

  void _selectPreset(WorldLibraryPreset preset) {
    if (_preset == preset) return;
    setState(() => _preset = preset);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Create world'),
    content: SizedBox(
      // AlertDialog measures its content intrinsically. A fixed-width wrapper
      // lets the inner LayoutBuilder receive real layout constraints instead.
      width: 440,
      child: LayoutBuilder(
        builder: (context, constraints) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            TextField(
              controller: _nameController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'World name'),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _seedController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Seed',
                hintText: 'Random if empty',
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 20),
            Text('World preset', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            _presetPicker(context, constraints),
          ],
        ),
      ),
    ),
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Create')),
    ],
  );

  Widget _presetPicker(BuildContext context, BoxConstraints constraints) {
    const compactBreakpoint = 360.0;
    final semantics = Semantics(
      key: WorldLibraryKeys.createPresetGroup,
      container: true,
      label: 'World preset',
      hint: constraints.maxWidth < compactBreakpoint
          ? 'Use arrow keys and Space to choose a world preset'
          : 'Use Tab, Space or Enter to choose a world preset',
      child: constraints.maxWidth < compactBreakpoint
          ? RadioGroup<WorldLibraryPreset>(
              groupValue: _preset,
              onChanged: (preset) {
                if (preset != null) _selectPreset(preset);
              },
              child: Column(
                children: <Widget>[
                  for (final preset in WorldLibraryPreset.values)
                    RadioListTile<WorldLibraryPreset>(
                      key: WorldLibraryKeys.createPreset(preset),
                      focusNode: _presetFocusNodes[preset],
                      value: preset,
                      selected: _preset == preset,
                      title: Text(preset.label),
                      subtitle: Text(preset.description),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                ],
              ),
            )
          : SegmentedButton<WorldLibraryPreset>(
              segments: <ButtonSegment<WorldLibraryPreset>>[
                for (final preset in WorldLibraryPreset.values)
                  ButtonSegment<WorldLibraryPreset>(
                    value: preset,
                    label: Text(preset.label),
                    tooltip: preset.description,
                  ),
              ],
              selected: <WorldLibraryPreset>{_preset},
              onSelectionChanged: (selection) =>
                  _selectPreset(selection.single),
              showSelectedIcon: false,
              expandedInsets: EdgeInsets.zero,
            ),
    );
    return semantics;
  }
}

final class _RenameWorldDialog extends StatefulWidget {
  const _RenameWorldDialog({required this.worldName});

  final String worldName;

  @override
  State<_RenameWorldDialog> createState() => _RenameWorldDialogState();
}

final class _RenameWorldDialogState extends State<_RenameWorldDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.worldName,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isNotEmpty) Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Rename ${widget.worldName}'),
    content: TextField(
      controller: _controller,
      autofocus: true,
      decoration: const InputDecoration(labelText: 'World name'),
      onSubmitted: (_) => _submit(),
    ),
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: WorldLibraryKeys.confirmRename,
        onPressed: _submit,
        child: const Text('Rename'),
      ),
    ],
  );
}
