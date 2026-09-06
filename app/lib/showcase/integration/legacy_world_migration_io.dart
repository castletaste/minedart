import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../data/worlds/mdrt_codec.dart';
import '../../data/worlds/world_models.dart';

Future<WorldDocument?> readLegacyWorld({
  required int fallbackSeed,
  File? source,
  DateTime Function()? clock,
}) async {
  final file = source ?? await legacyWorldFile();
  if (!await file.exists()) return null;
  final bytes = await file.readAsBytes();
  final now = (clock ?? DateTime.now)().toUtc();
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

/// Location used by the previous single-file persistence implementation.
Future<File> legacyWorldFile({Directory? applicationSupportDirectory}) async {
  final support =
      applicationSupportDirectory ?? await getApplicationSupportDirectory();
  final directory = Directory(
    '${support.parent.path}${Platform.pathSeparator}minedart',
  );
  return File('${directory.path}${Platform.pathSeparator}world.dat');
}
