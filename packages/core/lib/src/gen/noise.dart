/// Deterministic dependency-free value noise used by world generation.
library;

/// Seeded value noise in two and three dimensions.
///
/// Lattice values are derived directly from coordinates, so sampling order
/// does not affect the result. All methods return values approximately in the
/// range `[-1, 1]`.
final class ValueNoise {
  const ValueNoise(this.seed);

  final int seed;

  double noise2(double x, double y) {
    final x0 = x.floor();
    final y0 = y.floor();
    final tx = _fade(x - x0);
    final ty = _fade(y - y0);

    final a = _lerp(_lattice(x0, y0, 0), _lattice(x0 + 1, y0, 0), tx);
    final b = _lerp(_lattice(x0, y0 + 1, 0), _lattice(x0 + 1, y0 + 1, 0), tx);
    return _lerp(a, b, ty);
  }

  double noise3(double x, double y, double z) {
    final x0 = x.floor();
    final y0 = y.floor();
    final z0 = z.floor();
    final tx = _fade(x - x0);
    final ty = _fade(y - y0);
    final tz = _fade(z - z0);

    final x00 = _lerp(_lattice(x0, y0, z0), _lattice(x0 + 1, y0, z0), tx);
    final x10 = _lerp(
      _lattice(x0, y0 + 1, z0),
      _lattice(x0 + 1, y0 + 1, z0),
      tx,
    );
    final x01 = _lerp(
      _lattice(x0, y0, z0 + 1),
      _lattice(x0 + 1, y0, z0 + 1),
      tx,
    );
    final x11 = _lerp(
      _lattice(x0, y0 + 1, z0 + 1),
      _lattice(x0 + 1, y0 + 1, z0 + 1),
      tx,
    );
    return _lerp(_lerp(x00, x10, ty), _lerp(x01, x11, ty), tz);
  }

  double fbm2(
    double x,
    double y, {
    int octaves = 4,
    double lacunarity = 2,
    double persistence = 0.5,
  }) {
    if (octaves <= 0) return 0;
    var value = 0.0;
    var amplitude = 1.0;
    var frequency = 1.0;
    var amplitudeSum = 0.0;
    for (var octave = 0; octave < octaves; octave++) {
      value += noise2(x * frequency, y * frequency) * amplitude;
      amplitudeSum += amplitude;
      frequency *= lacunarity;
      amplitude *= persistence;
    }
    return value / amplitudeSum;
  }

  double fbm3(
    double x,
    double y,
    double z, {
    int octaves = 3,
    double lacunarity = 2,
    double persistence = 0.5,
  }) {
    if (octaves <= 0) return 0;
    var value = 0.0;
    var amplitude = 1.0;
    var frequency = 1.0;
    var amplitudeSum = 0.0;
    for (var octave = 0; octave < octaves; octave++) {
      value += noise3(x * frequency, y * frequency, z * frequency) * amplitude;
      amplitudeSum += amplitude;
      frequency *= lacunarity;
      amplitude *= persistence;
    }
    return value / amplitudeSum;
  }

  double _lattice(int x, int y, int z) {
    var h =
        (seed & 0x7fffffff) ^
        ((x * 0x1f123bb5) & 0x7fffffff) ^
        ((y * 0x5f356495) & 0x7fffffff) ^
        ((z * 0x6c8e9cf5) & 0x7fffffff);
    h = (((h >> 16) ^ h) * 0x045d9f3b) & 0x7fffffff;
    h = (((h >> 16) ^ h) * 0x045d9f3b) & 0x7fffffff;
    h = (h >> 16) ^ h;
    return h / 0x7fffffff * 2.0 - 1.0;
  }

  static double _fade(double t) => t * t * (3 - 2 * t);

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
}
