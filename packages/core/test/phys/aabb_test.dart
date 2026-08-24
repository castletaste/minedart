import 'package:minedart_core/minedart_core.dart';
import 'package:test/test.dart';

void main() {
  test('Aabb intersections are strict at touching faces', () {
    final box = Aabb(minX: 0, minY: 0, minZ: 0, maxX: 1, maxY: 1, maxZ: 1);
    final overlapping = Aabb(
      minX: 0.5,
      minY: 0.5,
      minZ: 0.5,
      maxX: 1.5,
      maxY: 1.5,
      maxZ: 1.5,
    );
    final touching = Aabb(minX: 1, minY: 0, minZ: 0, maxX: 2, maxY: 1, maxZ: 1);

    expect(box.intersects(overlapping), isTrue);
    expect(box.intersects(touching), isFalse);
    expect(box.intersectsVoxel(0, 0, 0), isTrue);
    expect(box.intersectsVoxel(1, 0, 0), isFalse);
  });
}
