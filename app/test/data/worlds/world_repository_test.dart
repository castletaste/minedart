import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:minedart/data/worlds/mdrt_codec.dart';
import 'package:minedart/data/worlds/native_world_repository.dart';
import 'package:minedart/data/worlds/world_models.dart';
import 'package:minedart/data/worlds/world_repository_base.dart';
import 'package:minedart_core/src/block.dart';

void main() {
  final start = DateTime.utc(2026, 8, 24, 12);
  var tick = 0;
  late StoredWorldRepository repository;

  WorldDocument document(
    String id,
    String name, {
    int seed = 7,
    int block = 0,
  }) {
    final blocks = Uint16List(WorldDocument.blockCount)..[0] = block;
    return WorldDocument(
      metadata: WorldMetadata(
        id: id,
        name: name,
        seed: seed,
        createdAt: start,
        updatedAt: start.add(Duration(seconds: tick)),
        spawn: const WorldSpawn.origin(),
      ),
      blocks: blocks,
    );
  }

  setUp(() {
    tick = 0;
    repository = StoredWorldRepository(
      MemoryWorldByteStore(),
      clock: () => start.add(Duration(seconds: ++tick)),
    );
  });

  test('lists most recently updated first', () async {
    await repository.create(document('old', 'Old'));
    await repository.create(document('new', 'New'));
    await repository.rename('new', 'Newest');

    expect((await repository.list()).map((entry) => entry.id), <String>[
      'new',
      'old',
    ]);
  });

  test(
    'rename, duplicate, delete and export/import retain canonical data',
    () async {
      await repository.create(
        document('source', 'Source', block: Blocks.grass),
      );
      final renamed = await repository.rename('source', '  Renamed  ');
      final duplicate = await repository.duplicate(
        'source',
        document('copy', 'Copy', seed: 123).metadata,
      );

      expect(renamed!.name, 'Renamed');
      expect(duplicate!.metadata.seed, 7);
      expect(duplicate.blocks[0], Blocks.grass);
      final bytes = await repository.exportBytes('copy');
      expect(await repository.delete('source'), isTrue);
      expect(await repository.load('source'), isNull);

      final destination = StoredWorldRepository(MemoryWorldByteStore());
      final imported = await destination.importBytes(bytes);
      expect(imported.metadata.id, 'copy');
      expect(imported.blocks[0], Blocks.grass);
      final importedAgain = await destination.importBytes(bytes);
      expect(importedAgain.metadata.id, isNot('copy'));
      expect(importedAgain.blocks[0], Blocks.grass);
      expect(await destination.list(), hasLength(2));
    },
  );

  test(
    'repository rejects unsafe ids before reaching its byte store',
    () async {
      expect(
        () => repository.create(document('../../escaped', 'Unsafe')),
        throwsArgumentError,
      );
      expect(() => repository.load('../escaped'), throwsArgumentError);
    },
  );

  test(
    'single repository serializes conflicting creates and recovers queue',
    () async {
      final first = repository.create(document('same', 'First'));
      final second = repository.create(document('same', 'Second'));

      expect(await first, isA<WorldDocument>());
      await expectLater(second, throwsStateError);
      await repository.save(document('after-failure', 'Still writable'));
      expect((await repository.load('same'))!.metadata.name, 'First');
      expect(await repository.load('after-failure'), isNotNull);
    },
  );

  test(
    'library listing reads MDRT2 metadata without inflating blocks',
    () async {
      final store = MemoryWorldByteStore();
      final metadataOnlyRepository = StoredWorldRepository(store);
      final encoded = await MdrtCodec.encode(document('metadata-only', 'Fast'));
      final metadataLength = ByteData.sublistView(
        encoded,
      ).getUint32(5, Endian.little);
      final truncatedPayload = Uint8List.sublistView(
        encoded,
        0,
        9 + metadataLength + 1,
      );
      await store.write('metadata-only', truncatedPayload);

      final summaries = await metadataOnlyRepository.list();

      expect(summaries.single.name, 'Fast');
      expect(
        () => metadataOnlyRepository.load('metadata-only'),
        throwsA(isA<Object>()),
      );
    },
  );

  group('NativeWorldRepository', () {
    late Directory root;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('minedart-worlds-');
    });

    tearDown(() => root.delete(recursive: true));

    test(
      'writes one atomically replaced MDRT file under the injected root',
      () async {
        final native = NativeWorldRepository(root);
        await native.create(document('atomic', 'First', block: Blocks.stone));
        await native.save(document('atomic', 'Second', block: Blocks.dirt));

        final files = await root.list().toList();
        expect(files.map((file) => file.uri.pathSegments.last), <String>[
          'atomic.mdrt',
        ]);
        expect(files.where((file) => file.path.endsWith('.tmp')), isEmpty);
        final loaded = await native.load('atomic');
        expect(loaded!.metadata.name, 'Second');
        expect(loaded.blocks[0], Blocks.dirt);
      },
    );

    test('concurrent saves use independent temporary files', () async {
      final native = NativeWorldRepository(root);
      await native.create(document('concurrent', 'Initial'));

      await Future.wait([
        for (var i = 0; i < 8; i++)
          native.save(document('concurrent', 'Version $i', block: i + 1)),
      ]);

      final loaded = await native.load('concurrent');
      expect(loaded!.metadata.name, 'Version 7');
      expect(loaded.blocks[0], 8);
      final files = await root.list().toList();
      expect(files.map((file) => file.uri.pathSegments.last), [
        'concurrent.mdrt',
      ]);
    });
  });
}
