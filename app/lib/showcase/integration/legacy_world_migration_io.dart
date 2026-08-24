import 'dart:io';

import '../../data/worlds/mdrt_codec.dart';
import '../../data/worlds/world_models.dart';
import '../../save/world_saver.dart';

Future<WorldDocument?> readLegacyWorld({required int fallbackSeed}) async {
  final file = await WorldSaver.defaultFile();
  if (!await file.exists()) return null;
  final bytes = await file.readAsBytes();
  final now = DateTime.now().toUtc();
  try {
    return await MdrtCodec.decode(
      bytes,
      legacyMetadata: WorldMetadata(
        id: 'classic-world',
        name: 'Classic World',
        seed: fallbackSeed,
        createdAt: now,
        updatedAt: now,
        spawn: const WorldSpawn.origin(),
      ),
    );
  } on FormatException {
    return null;
  } on FileSystemException {
    return null;
  }
}
