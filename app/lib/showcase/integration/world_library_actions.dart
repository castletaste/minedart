import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';

import '../../data/worlds/worlds.dart';
import '../controller/world_library_controller.dart';
import 'launch_config.dart';
import 'world_defaults.dart';
import 'world_presets.dart';
import 'world_session_coordinator.dart';

/// File pickers and library commands belong to this UI adapter, not the game.
final class WorldLibraryActions {
  WorldLibraryActions({required this.session, required this.refresh});

  final WorldSessionCoordinator session;
  final Future<void> Function() refresh;

  WorldLibraryCallbacks callbacks({required void Function() onActivated}) =>
      WorldLibraryCallbacks(
        onCreate: (name, seed, preset) async {
          final document = _newWorld(
            name,
            resolveOptionalWorldSeed(seed),
            switch (preset) {
              WorldLibraryPreset.classic => LaunchWorldPreset.classic,
              WorldLibraryPreset.flat => LaunchWorldPreset.flat,
              WorldLibraryPreset.islands => LaunchWorldPreset.islands,
            },
          );
          if (await _perform(session.createWorld(document))) onActivated();
        },
        onLoad: (entry) async {
          if (await _perform(session.loadWorld(entry.id))) onActivated();
        },
        onImport: () async {
          final file = await openFile(acceptedTypeGroups: const [_worldFiles]);
          if (file == null || !session.host.isAttached) return;
          final now = DateTime.now().toUtc();
          await _perform(
            session.importWorld(
              Uint8List.fromList(await file.readAsBytes()),
              legacyMetadata: WorldMetadata(
                id: _worldId(now),
                name: importedWorldName(file.name),
                seed: 0,
                createdAt: now,
                updatedAt: now,
                spawn: const WorldSpawn.origin(),
              ),
            ),
          );
        },
        onRename: (entry, name) => _perform(session.rename(entry.id, name)),
        onDuplicate: (entry) => _perform(
          session.duplicateWorld(entry.id, (source) {
            final now = DateTime.now().toUtc();
            return WorldMetadata(
              id: duplicateWorldId(
                sourceId: entry.id,
                seed: entry.seed,
                nonce: now.microsecondsSinceEpoch,
              ),
              name: '${entry.name} Copy',
              seed: entry.seed,
              createdAt: now,
              updatedAt: now,
              spawn: source.metadata.spawn,
            );
          }),
        ),
        onDelete: (entry) async {
          final wasCurrent = entry.id == session.current.worldId;
          final changed = await _perform(
            session.delete(entry.id, replacement: () => _replacement(entry.id)),
          );
          if (changed && wasCurrent) onActivated();
        },
        onReset: (entry) async {
          final wasCurrent = entry.id == session.current.worldId;
          final changed = await _perform(
            session.reset(entry.id, (current) {
              final world = generatePresetWorld(
                entry.seed,
                presetForWorldId(entry.id),
              );
              return WorldDocument.fromWorld(
                metadata: current.metadata.copyWith(
                  updatedAt: DateTime.now().toUtc(),
                  spawn: defaultWorldSpawn(world),
                ),
                world: world,
              );
            }),
          );
          if (changed && wasCurrent) onActivated();
        },
        onExport: (entry) async {
          final result = await session.exportWorld(entry.id);
          final bytes = switch (result) {
            WorldSessionSuccess<Uint8List>(:final value) => value,
            WorldSessionCancelled<Uint8List>() => null,
            WorldSessionFailure<Uint8List>() => throw result,
          };
          if (bytes == null || !session.host.isAttached) return;
          final fileName = '${_fileName(entry.name)}.mdrt';
          final location = await getSaveLocation(
            suggestedName: fileName,
            acceptedTypeGroups: const [_worldFiles],
          );
          if (location == null) return;
          await XFile.fromData(
            bytes,
            mimeType: 'application/octet-stream',
            name: fileName,
          ).saveTo(location.path);
        },
        onShareSeed: (entry) => Clipboard.setData(
          ClipboardData(
            text: ShowcaseLaunchConfig(
              seed: entry.seed,
              preset: presetForWorldId(entry.id),
            ).shareUri(Uri.base).toString(),
          ),
        ),
      );

  Future<bool> _perform(Future<WorldSessionResult<void>> operation) async {
    final result = await operation;
    try {
      await refresh();
    } catch (error) {
      if (result case WorldSessionFailure<void> failure) {
        throw WorldSessionFailure<void>(
          failure.error,
          activeWorldChanged: failure.activeWorldChanged,
          durableStateChanged: failure.durableStateChanged,
          cleanupErrors: [...failure.cleanupErrors, error],
        );
      }
      rethrow;
    }
    return switch (result) {
      WorldSessionSuccess<void>() => true,
      WorldSessionCancelled<void>() => false,
      WorldSessionFailure<void>() => throw result,
    };
  }

  Future<WorldDocument> _replacement(String deletedId) async {
    final repository = session.repository;
    for (final entry in await repository.list()) {
      if (entry.id == deletedId) continue;
      final document = await repository.load(entry.id);
      if (document != null) return document;
    }
    final document = _newWorld(
      'Classic World',
      generateRandomWorldSeed(),
      LaunchWorldPreset.classic,
    );
    await repository.create(document);
    return document;
  }
}

const _worldFiles = XTypeGroup(label: 'Minedart world', extensions: ['mdrt']);

WorldDocument _newWorld(String name, int seed, LaunchWorldPreset preset) {
  final world = generatePresetWorld(seed, preset);
  final now = DateTime.now().toUtc();
  return WorldDocument.fromWorld(
    metadata: WorldMetadata(
      id: preset == LaunchWorldPreset.classic
          ? _worldId(now)
          : sharedWorldId(seed, preset, nonce: now.microsecondsSinceEpoch),
      name: name.trim().isEmpty ? 'Classic World' : name.trim(),
      seed: seed,
      createdAt: now,
      updatedAt: now,
      spawn: defaultWorldSpawn(world),
    ),
    world: world,
  );
}

String _worldId(DateTime now) =>
    'world-${now.microsecondsSinceEpoch.toRadixString(36)}';
String _fileName(String value) {
  final safe = value.trim().replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '-');
  return safe.isEmpty ? 'minedart-world' : safe;
}
