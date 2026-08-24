import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controller/world_library_controller.dart';
import 'modal_input_region.dart';

abstract final class WorldLibraryKeys {
  static const search = ValueKey<String>('world-library-search');
  static const create = ValueKey<String>('world-library-create');
  static const importWorld = ValueKey<String>('world-library-import');
  static const grid = ValueKey<String>('world-library-grid');
  static const confirmDestructive = ValueKey<String>(
    'world-library-confirm-destructive',
  );
  static const confirmRename = ValueKey<String>('world-library-confirm-rename');
  static const createPresetGroup = ValueKey<String>(
    'world-library-create-preset-group',
  );

  static ValueKey<String> card(String id) => ValueKey<String>('world-card-$id');

  static ValueKey<String> load(String id) => ValueKey<String>('world-load-$id');

  static ValueKey<String> actions(String id) =>
      ValueKey<String>('world-actions-$id');

  static ValueKey<String> createPreset(WorldLibraryPreset preset) =>
      ValueKey<String>('world-library-create-preset-${preset.name}');
}

final class WorldLibraryView extends StatefulWidget {
  const WorldLibraryView({
    required this.controller,
    required this.callbacks,
    required this.onClose,
    this.onInputCaptureChanged,
    super.key,
  });

  final WorldLibraryController controller;
  final WorldLibraryCallbacks callbacks;
  final VoidCallback onClose;
  final ValueChanged<bool>? onInputCaptureChanged;

  @override
  State<WorldLibraryView> createState() => _WorldLibraryViewState();
}

final class _WorldLibraryViewState extends State<WorldLibraryView> {
  late final TextEditingController _searchController = TextEditingController(
    text: widget.controller.query,
  );

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ModalInputRegion(
    onInputCaptureChanged: widget.onInputCaptureChanged,
    child: CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): widget.onClose,
      },
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        child: SafeArea(
          child: AnimatedBuilder(
            animation: widget.controller,
            builder: (context, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _header(context),
                if (widget.controller.errorMessage case final error?)
                  _error(context, error),
                Expanded(child: _worlds(context)),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _header(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  'World Library',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Close World Library',
              onPressed: widget.onClose,
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 600;
            final search = TextField(
              key: WorldLibraryKeys.search,
              controller: _searchController,
              autofocus: true,
              onChanged: widget.controller.setQuery,
              decoration: const InputDecoration(
                labelText: 'Search worlds',
                hintText: 'Name or seed',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
            );
            final actions = Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                FilledButton.icon(
                  key: WorldLibraryKeys.create,
                  onPressed: widget.controller.isBusy
                      ? null
                      : () => unawaited(_createWorld(context)),
                  icon: const Icon(Icons.add),
                  label: const Text('Create'),
                ),
                OutlinedButton.icon(
                  key: WorldLibraryKeys.importWorld,
                  onPressed: widget.controller.isBusy
                      ? null
                      : () => unawaited(
                          widget.controller.run(
                            '@import',
                            widget.callbacks.onImport,
                          ),
                        ),
                  icon: const Icon(Icons.file_open_outlined),
                  label: const Text('Import'),
                ),
              ],
            );
            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[search, const SizedBox(height: 8), actions],
              );
            }
            return Row(
              children: <Widget>[
                Expanded(child: search),
                const SizedBox(width: 12),
                actions,
              ],
            );
          },
        ),
      ],
    ),
  );

  Widget _error(BuildContext context, String error) => Semantics(
    liveRegion: true,
    label: 'World action failed: $error',
    child: MaterialBanner(
      content: Text('World action failed: $error'),
      actions: <Widget>[
        TextButton(
          onPressed: widget.controller.clearError,
          child: const Text('Dismiss'),
        ),
      ],
    ),
  );

  Widget _worlds(BuildContext context) {
    final worlds = widget.controller.visibleWorlds;
    if (worlds.isEmpty) {
      return Center(
        child: Semantics(
          liveRegion: true,
          child: Text(
            widget.controller.query.isEmpty
                ? 'No worlds yet. Create or import one.'
                : 'No worlds match this search.',
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final extent = constraints.maxWidth < 600 ? 560.0 : 390.0;
        return GridView.builder(
          key: WorldLibraryKeys.grid,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          itemCount: worlds.length,
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: extent,
            mainAxisExtent: 236,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
          ),
          itemBuilder: (context, index) => _worldCard(context, worlds[index]),
        );
      },
    );
  }

  Widget _worldCard(BuildContext context, WorldLibraryEntry world) {
    final busy = widget.controller.busyWorldId == world.id;
    return Semantics(
      key: WorldLibraryKeys.card(world.id),
      container: true,
      label: 'World ${world.name}, seed ${world.seed}',
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Text(
                      world.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  if (world.isCurrent)
                    const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: Chip(label: Text('Current')),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text('Seed ${world.seed}'),
              Text('Updated ${_formatDate(world.updatedAt)}'),
              Text('MDRT${world.formatVersion}'),
              const Spacer(),
              if (busy) const LinearProgressIndicator(),
              Row(
                children: <Widget>[
                  Expanded(
                    child: FilledButton.icon(
                      key: WorldLibraryKeys.load(world.id),
                      onPressed: widget.controller.isBusy
                          ? null
                          : () => unawaited(
                              widget.controller.run(
                                world.id,
                                () => widget.callbacks.onLoad(world),
                              ),
                            ),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Load'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  PopupMenuButton<WorldLibraryAction>(
                    key: WorldLibraryKeys.actions(world.id),
                    enabled: !widget.controller.isBusy,
                    tooltip: 'Actions for ${world.name}',
                    onSelected: (action) =>
                        unawaited(_handleAction(context, world, action)),
                    itemBuilder: (context) =>
                        <PopupMenuEntry<WorldLibraryAction>>[
                          for (final action in WorldLibraryAction.values)
                            if (action != WorldLibraryAction.load)
                              PopupMenuItem<WorldLibraryAction>(
                                value: action,
                                child: Row(
                                  children: <Widget>[
                                    Icon(
                                      _actionIcon(action),
                                      color: action.isDestructive
                                          ? Theme.of(context).colorScheme.error
                                          : null,
                                    ),
                                    const SizedBox(width: 10),
                                    Text(action.label),
                                  ],
                                ),
                              ),
                        ],
                    icon: const Icon(Icons.more_horiz),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleAction(
    BuildContext context,
    WorldLibraryEntry world,
    WorldLibraryAction action,
  ) async {
    switch (action) {
      case WorldLibraryAction.load:
        await widget.controller.run(
          world.id,
          () => widget.callbacks.onLoad(world),
        );
      case WorldLibraryAction.rename:
        final name = await _renameWorld(context, world);
        if (name != null && name != world.name) {
          await widget.controller.run(
            world.id,
            () => widget.callbacks.onRename(world, name),
          );
        }
      case WorldLibraryAction.duplicate:
        await widget.controller.run(
          world.id,
          () => widget.callbacks.onDuplicate(world),
        );
      case WorldLibraryAction.delete:
        if (await _confirmDestructive(context, action, world)) {
          await widget.controller.run(
            world.id,
            () => widget.callbacks.onDelete(world),
          );
        }
      case WorldLibraryAction.reset:
        if (await _confirmDestructive(context, action, world)) {
          await widget.controller.run(
            world.id,
            () => widget.callbacks.onReset(world),
          );
        }
      case WorldLibraryAction.exportWorld:
        await widget.controller.run(
          world.id,
          () => widget.callbacks.onExport(world),
        );
      case WorldLibraryAction.shareSeed:
        await widget.controller.run(
          world.id,
          () => widget.callbacks.onShareSeed(world),
        );
    }
  }

  Future<void> _createWorld(BuildContext context) async {
    final result =
        await showDialog<({String name, int? seed, WorldLibraryPreset preset})>(
          context: context,
          builder: (context) => const _CreateWorldDialog(),
        );
    if (result == null) return;
    await widget.controller.run(
      '@create',
      () => widget.callbacks.onCreate(result.name, result.seed, result.preset),
    );
  }

  Future<String?> _renameWorld(BuildContext context, WorldLibraryEntry world) =>
      showDialog<String>(
        context: context,
        builder: (context) => _RenameWorldDialog(worldName: world.name),
      );

  Future<bool> _confirmDestructive(
    BuildContext context,
    WorldLibraryAction action,
    WorldLibraryEntry world,
  ) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('${action.label} ${world.name}?'),
          content: Text(
            action == WorldLibraryAction.delete
                ? 'This removes the saved world. This cannot be undone.'
                : 'This replaces all edits with a fresh world from seed ${world.seed}.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: WorldLibraryKeys.confirmDestructive,
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              child: Text(action.label),
            ),
          ],
        ),
      ) ??
      false;

  static IconData _actionIcon(WorldLibraryAction action) => switch (action) {
    WorldLibraryAction.load => Icons.play_arrow,
    WorldLibraryAction.rename => Icons.edit_outlined,
    WorldLibraryAction.duplicate => Icons.copy_outlined,
    WorldLibraryAction.delete => Icons.delete_outline,
    WorldLibraryAction.reset => Icons.restart_alt,
    WorldLibraryAction.exportWorld => Icons.file_download_outlined,
    WorldLibraryAction.shareSeed => Icons.share_outlined,
  };

  static String _formatDate(DateTime value) {
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}

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
