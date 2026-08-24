import 'package:minedart_core/minedart_core.dart';
import 'package:test/test.dart';

void main() {
  test('value noise is deterministic, bounded, and seed-dependent', () {
    const first = ValueNoise(42);
    const same = ValueNoise(42);
    const other = ValueNoise(43);

    var differs = false;
    for (var i = -20; i <= 20; i++) {
      final x = i * 0.173;
      final y = i * -0.091;
      final z = i * 0.047;
      final a = first.noise3(x, y, z);
      expect(a, same.noise3(x, y, z));
      expect(a, inInclusiveRange(-1.0, 1.0));
      differs = differs || a != other.noise3(x, y, z);
    }
    expect(differs, isTrue);
  });

  test('fBm remains normalized', () {
    const noise = ValueNoise(7);
    for (var z = 0; z < 30; z++) {
      for (var x = 0; x < 30; x++) {
        expect(
          noise.fbm2(x * 0.21, z * 0.19, octaves: 5),
          inInclusiveRange(-1.0, 1.0),
        );
      }
    }
  });
}
