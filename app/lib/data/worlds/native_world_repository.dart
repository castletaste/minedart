/// Native file repository. This library is deliberately never imported on web.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'world_repository_base.dart';

final class NativeWorldRepository extends StoredWorldRepository {
  NativeWorldRepository(Directory root, {super.clock})
    : super(_NativeWorldByteStore(root));

  /// Production location: Application Support/minedart/worlds.
  static Future<NativeWorldRepository> createDefault({
    DateTime Function()? clock,
  }) async {
    final support = await getApplicationSupportDirectory();
    return NativeWorldRepository(
      Directory(
        '${support.path}${Platform.pathSeparator}minedart${Platform.pathSeparator}worlds',
      ),
      clock: clock,
    );
  }
}

final class _NativeWorldByteStore implements WorldByteStore {
  _NativeWorldByteStore(this.root);

  final Directory root;
  int _scratchNonce = 0;

  @override
  Future<List<String>> keys() async {
    if (!await root.exists()) return const <String>[];
    final ids = <String>[];
    await for (final entity in root.list(followLinks: false)) {
      if (entity is File && entity.path.endsWith('.mdrt')) {
        ids.add(
          entity.uri.pathSegments.last.substring(
            0,
            entity.uri.pathSegments.last.length - 5,
          ),
        );
      }
    }
    return ids;
  }

  @override
  Future<Uint8List?> read(String id) async {
    final file = _fileFor(id);
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  @override
  Future<void> write(String id, Uint8List bytes) async {
    final file = _fileFor(id);
    await root.create(recursive: true);
    // Concurrent writers to one world must not share a scratch path, or one
    // writer renames a file the other is still filling and publishes a torn
    // document. The rename itself stays atomic per writer.
    final temp = File('${file.path}.${_scratchNonce++}.tmp');
    try {
      await temp.writeAsBytes(bytes, flush: true);
      await temp.rename(file.path);
    } on Object {
      if (await temp.exists()) await temp.delete();
      rethrow;
    }
  }

  @override
  Future<bool> remove(String id) async {
    final file = _fileFor(id);
    if (!await file.exists()) return false;
    await file.delete();
    return true;
  }

  File _fileFor(String id) {
    if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(id)) {
      throw ArgumentError.value(id, 'id', 'must be a safe file identifier');
    }
    return File('${root.path}${Platform.pathSeparator}$id.mdrt');
  }
}
