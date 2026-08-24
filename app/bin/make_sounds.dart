import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

const sampleRate = 44100;
const _materials = <String>[
  'grass',
  'gravel',
  'stone',
  'wood',
  'dirt',
  'leaves',
  'metal',
];
const _variantCount = 4;
const _auxiliary = <String>['water', 'tnt_fuse', 'explosion', 'ui_click'];
const _obsoleteAssets = <String>[
  'stone_break.wav',
  'stone_place.wav',
  'dirt_break.wav',
  'dirt_place.wav',
  'wood_break.wav',
  'wood_place.wav',
  'gravel_break.wav',
  'gravel_place.wav',
  'step.wav',
];

void main() {
  final output = Directory('assets/audio')..createSync(recursive: true);
  for (final name in _obsoleteAssets) {
    final old = File('${output.path}/$name');
    if (old.existsSync()) old.deleteSync();
  }

  var written = 0;
  for (
    var materialIndex = 0;
    materialIndex < _materials.length;
    materialIndex++
  ) {
    final material = _materials[materialIndex];
    for (var variant = 0; variant < _variantCount; variant++) {
      final samples = _synthMaterial(material, materialIndex, variant);
      File(
        '${output.path}/${material}_${variant + 1}.wav',
      ).writeAsBytesSync(_wav(samples));
      written++;
    }
  }
  for (var index = 0; index < _auxiliary.length; index++) {
    final name = _auxiliary[index];
    File(
      '${output.path}/$name.wav',
    ).writeAsBytesSync(_wav(_synthAuxiliary(name, 100 + index)));
    written++;
  }
  stdout.writeln(
    'Generated $written deterministic Classic-inspired WAV files.',
  );
}

List<double> _synthMaterial(String material, int materialIndex, int variant) {
  final duration = switch (material) {
    'grass' => 0.145 + variant * 0.006,
    'dirt' => 0.138 + variant * 0.006,
    'leaves' => 0.155 + variant * 0.007,
    'gravel' => 0.115 + variant * 0.005,
    'stone' => 0.112 + variant * 0.004,
    'wood' => 0.158 + variant * 0.006,
    'metal' => 0.126 + variant * 0.004,
    _ => throw ArgumentError.value(material, 'material'),
  };
  final count = (duration * sampleRate).round();
  final samples = List<double>.filled(count, 0);
  final random = _Noise(0x434c4153 + materialIndex * 97 + variant * 7919);
  var low = 0.0;
  var slow = 0.0;
  var grain = 0.0;
  var rustle = 0.0;
  final softMaterial = switch (material) {
    'grass' || 'dirt' || 'leaves' || 'wood' => true,
    _ => false,
  };

  for (var i = 0; i < count; i++) {
    final t = i / sampleRate;
    final p = i / count;
    final raw = random.next() * 2 - 1;
    low += (raw - low) * (softMaterial ? 0.12 : 0.16);
    slow += (raw - slow) * (softMaterial ? 0.028 : 0.035);
    final high = raw - low;
    final mid = low - slow;
    if (random.next() >
        (softMaterial ? 0.972 - variant * 0.001 : 0.965 - variant * 0.002)) {
      grain = 1.0;
    }
    grain *= softMaterial ? 0.72 : 0.78;
    rustle += (raw - rustle) * 0.18;

    final sound = switch (material) {
      'grass' =>
        high * 0.07 +
            mid * 0.30 +
            slow * 0.16 +
            math.sin(2 * math.pi * (610 + variant * 19) * t) * 0.025,
      'dirt' =>
        low * 0.23 +
            mid * 0.34 +
            high * 0.035 +
            _ring(t, 155 + variant * 11, 31, 0.12) +
            _ring(t, 238 + variant * 13, 38, 0.07) +
            grain * 0.055,
      'leaves' =>
        high * 0.10 +
            mid * 0.18 +
            (rustle - slow) * 0.28 +
            math.sin(2 * math.pi * (840 + variant * 23) * t) * 0.018 +
            grain * 0.07,
      'gravel' => high * 0.24 + mid * 0.23 + grain * (0.23 + high.abs() * 0.16),
      'stone' =>
        low * 0.16 +
            mid * 0.38 +
            high * (0.055 + grain * 0.12) +
            _ring(t, 128 + variant * 9, 42, 0.20) +
            _ring(t, 214 + variant * 13, 62, 0.10),
      'wood' =>
        high * 0.035 +
            mid * 0.10 +
            _ring(t, 205 + variant * 13, 25, 0.27) +
            _ring(t, 342 + variant * 17, 35, 0.12) +
            _delayedRing(t, 0.048 + variant * 0.003, 260, 42, 0.08),
      'metal' =>
        low * 0.12 +
            mid * 0.20 +
            high * (0.045 + grain * 0.08) +
            _ring(t, 176 + variant * 11, 38, 0.22) +
            _ring(t, 302 + variant * 17, 58, 0.09),
      _ => 0,
    };
    final flutter = switch (material) {
      'grass' =>
        0.84 + 0.16 * math.sin(2 * math.pi * (34 + variant * 2) * t).abs(),
      'leaves' =>
        0.72 + 0.28 * math.sin(2 * math.pi * (27 + variant * 2) * t).abs(),
      _ => 1.0,
    };
    final envelope = switch (material) {
      'grass' || 'dirt' || 'leaves' || 'wood' => _softEnvelope(p),
      'stone' || 'metal' => _stoneEnvelope(p),
      _ => _shortEnvelope(p),
    };
    samples[i] = sound * flutter * envelope;
  }
  final targetPeak = switch (material) {
    'grass' => 0.48,
    'dirt' => 0.50,
    'leaves' => 0.46,
    'wood' => 0.52,
    'stone' => 0.56,
    'metal' => 0.54,
    _ => 0.68,
  };
  return _normalize(samples, targetPeak);
}

double _ring(double t, double frequency, double decay, double gain) =>
    math.sin(2 * math.pi * frequency * t) * math.exp(-t * decay) * gain;

double _delayedRing(
  double t,
  double delay,
  double frequency,
  double decay,
  double gain,
) {
  final local = t - delay;
  return local < 0 ? 0 : _ring(local, frequency, decay, gain);
}

double _shortEnvelope(double progress) {
  final attack = (progress / 0.012).clamp(0.0, 1.0);
  return attack * math.pow(1 - progress, 2.15);
}

double _softEnvelope(double progress) {
  final attack = (progress / 0.024).clamp(0.0, 1.0);
  return attack * math.pow(1 - progress, 2.65);
}

double _stoneEnvelope(double progress) {
  final attack = (progress / 0.008).clamp(0.0, 1.0);
  return attack * math.pow(1 - progress, 3.25);
}

List<double> _synthAuxiliary(String name, int seed) {
  final random = _Noise(seed);
  final duration = switch (name) {
    'explosion' => 0.44,
    'water' => 0.25,
    'tnt_fuse' => 0.20,
    'ui_click' => 0.065,
    _ => throw ArgumentError.value(name, 'name'),
  };
  final count = (duration * sampleRate).round();
  final samples = List<double>.filled(count, 0);
  var low = 0.0;
  for (var i = 0; i < count; i++) {
    final t = i / sampleRate;
    final p = i / count;
    final noise = random.next() * 2 - 1;
    low += (noise - low) * 0.08;
    final value = switch (name) {
      'explosion' =>
        low * (1 - p) * 0.78 +
            math.sin(2 * math.pi * (62 - 31 * p) * t) * (1 - p) * 0.18,
      'water' =>
        (noise - low) * 0.13 +
            math.sin(2 * math.pi * 760 * t) * 0.055 +
            math.sin(2 * math.pi * 1130 * t) * 0.035,
      'tnt_fuse' =>
        (noise - low) * 0.13 + math.sin(2 * math.pi * 2180 * t) * 0.16,
      'ui_click' =>
        math.sin(2 * math.pi * (820 - 190 * p) * t) * 0.52 +
            (noise - low) * 0.025,
      _ => 0,
    };
    samples[i] = value * _shortEnvelope(p);
  }
  return _normalize(samples, name == 'explosion' ? 0.82 : 0.62);
}

List<double> _normalize(List<double> samples, double targetPeak) {
  var peak = 0.0;
  for (final sample in samples) {
    if (sample.abs() > peak) peak = sample.abs();
  }
  if (peak == 0) return samples;
  final gain = targetPeak / peak;
  for (var i = 0; i < samples.length; i++) {
    samples[i] *= gain;
  }
  return samples;
}

Uint8List _wav(List<double> samples) {
  final bytes = ByteData(44 + samples.length * 2);
  void ascii(int offset, String value) {
    for (var i = 0; i < value.length; i++) {
      bytes.setUint8(offset + i, value.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  bytes.setUint32(4, bytes.lengthInBytes - 8, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  bytes.setUint32(16, 16, Endian.little);
  bytes.setUint16(20, 1, Endian.little);
  bytes.setUint16(22, 1, Endian.little);
  bytes.setUint32(24, sampleRate, Endian.little);
  bytes.setUint32(28, sampleRate * 2, Endian.little);
  bytes.setUint16(32, 2, Endian.little);
  bytes.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  bytes.setUint32(40, samples.length * 2, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    final sample = (samples[i].clamp(-0.98, 0.98) * 32767).round();
    bytes.setInt16(44 + i * 2, sample, Endian.little);
  }
  return bytes.buffer.asUint8List();
}

final class _Noise {
  _Noise(int seed) : _state = (seed * 0x45D9F3B) & 0x7FFFFFFF;

  int _state;

  double next() {
    _state = (_state * 1103515245 + 12345) & 0x7FFFFFFF;
    return _state / 0x7FFFFFFF;
  }
}
