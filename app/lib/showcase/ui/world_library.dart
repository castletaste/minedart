import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controller/world_library_controller.dart';
import 'modal_input_region.dart';

part 'world_library_dialogs.dart';
part 'world_library_components.dart';

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
  void didUpdateWidget(WorldLibraryView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    _searchController.value = TextEditingValue(
      text: widget.controller.query,
      selection: TextSelection.collapsed(
        offset: widget.controller.query.length,
      ),
    );
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
          itemBuilder: (context, index) => _WorldCard(
            world: worlds[index],
            controller: widget.controller,
            callbacks: widget.callbacks,
            onAction: (action) =>
                unawaited(_handleAction(context, worlds[index], action)),
          ),
        );
      },
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
        if (!mounted) return;
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
        final confirmed = await _confirmDestructive(context, action, world);
        if (!mounted) return;
        if (confirmed) {
          await widget.controller.run(
            world.id,
            () => widget.callbacks.onDelete(world),
          );
        }
      case WorldLibraryAction.reset:
        final confirmed = await _confirmDestructive(context, action, world);
        if (!mounted) return;
        if (confirmed) {
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
    if (!mounted || result == null) return;
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
}
