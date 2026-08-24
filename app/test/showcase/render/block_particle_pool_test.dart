import 'package:flutter_test/flutter_test.dart';
import 'package:minedart/showcase/render/block_particle_pool.dart';

void main() {
  group('BlockParticlePool', () {
    test('is fixed-capacity and recycles slots in deterministic order', () {
      final pool = BlockParticlePool(capacity: 3, seed: 7);
      final mesh = pool.mesh;

      expect(pool.emit(blockId: 1, x: 1, y: 2, z: 3, count: 5), 3);
      expect(pool.activeCount, 3);
      expect(pool.emittedCount, 3);
      expect(
        pool.particles.every((particle) => identical(particle.mesh, mesh)),
        isTrue,
      );

      expect(pool.emit(blockId: 2, x: 4, y: 5, z: 6, count: 2), 2);
      expect(pool.activeCount, 3);
      expect(pool.emittedCount, 5);
      expect(pool.particles.map((particle) => particle.serial), <int>[4, 5, 3]);
      expect(pool.particles.map((particle) => particle.blockId), <int>[
        2,
        2,
        1,
      ]);
      expect(
        () => pool.particles.add(pool.particles.first),
        throwsUnsupportedError,
      );
    });

    test('same seed and events produce identical particle state', () {
      final first = BlockParticlePool(capacity: 4, seed: 0x5eed);
      final second = BlockParticlePool(capacity: 4, seed: 0x5eed);

      first.emitBlock(blockId: 16, x: 10, y: 20, z: 30, count: 4);
      second.emitBlock(blockId: 16, x: 10, y: 20, z: 30, count: 4);

      for (var i = 0; i < first.capacity; i++) {
        final a = first.particles[i];
        final b = second.particles[i];
        expect(a.position.x, b.position.x);
        expect(a.position.y, b.position.y);
        expect(a.position.z, b.position.z);
        expect(a.velocityX, b.velocityX);
        expect(a.velocityY, b.velocityY);
        expect(a.velocityZ, b.velocityZ);
        expect(a.lifetime, b.lifetime);
      }

      first.update(0.1);
      second.update(0.1);
      for (var i = 0; i < first.capacity; i++) {
        expect(first.particles[i].position, second.particles[i].position);
      }
    });

    test('expires particles and reduced motion suppresses bursts', () {
      final pool = BlockParticlePool(capacity: 4, seed: 1);
      pool.emit(blockId: 3, x: 0, y: 0, z: 0, count: 4);
      expect(pool.activeCount, 4);

      pool.update(2);
      expect(pool.activeCount, 0);

      pool.emit(blockId: 3, x: 0, y: 0, z: 0, count: 2);
      pool.reducedMotion = true;
      expect(pool.activeCount, 0);
      expect(pool.emit(blockId: 3, x: 0, y: 0, z: 0), 0);

      pool
        ..reducedMotion = false
        ..enabled = false;
      expect(pool.emit(blockId: 3, x: 0, y: 0, z: 0), 0);
    });
  });
}
