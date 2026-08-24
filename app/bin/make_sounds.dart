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
  'glass',
  'sand',
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
  if (material == 'gravel') {
    return _sourceBackedVariant(
      path: 'tool/audio_sources/tinyworlds/gravel_source.wav',
      variant: variant,
      startSeconds: 0.018,
      sourceDuration: 0.250,
      fadeInSeconds: 0.004,
      fadeOutSeconds: 0.018,
      targetPeak: 0.40,
    );
  }
  if (material == 'stone') {
    return _sourceBackedVariant(
      path: 'tool/audio_sources/tinyworlds/stone_source.wav',
      variant: variant,
      startSeconds: 0,
      sourceDuration: 0.175,
      fadeInSeconds: 0.008,
      fadeOutSeconds: 0.018,
      lowPassHz: 1300,
      rateScale: 0.90,
      targetPeak: 0.42,
    );
  }
  if (material == 'wood') {
    const paths = <String>[
      'tool/audio_sources/tinyworlds/wood01_source.wav',
      'tool/audio_sources/tinyworlds/wood02_source.wav',
      'tool/audio_sources/tinyworlds/wood03_source.wav',
      'tool/audio_sources/tinyworlds/wood03_source.wav',
    ];
    const starts = <double>[0, 0.035, 0.023, 0.023];
    const durations = <double>[0.180, 0.150, 0.210, 0.210];
    return _sourceBackedVariant(
      path: paths[variant % paths.length],
      variant: variant,
      startSeconds: starts[variant % starts.length],
      sourceDuration: durations[variant % durations.length],
      fadeInSeconds: 0.008,
      fadeOutSeconds: 0.018,
      targetPeak: 0.42,
    );
  }
  if (material == 'leaves') {
    const paths = <String>[
      'tool/audio_sources/tinyworlds/leaves01_source.wav',
      'tool/audio_sources/tinyworlds/leaves02_source.wav',
      'tool/audio_sources/tinyworlds/leaves01_source.wav',
      'tool/audio_sources/tinyworlds/leaves02_source.wav',
    ];
    const durations = <double>[0.275, 0.205, 0.275, 0.205];
    return _sourceBackedVariant(
      path: paths[variant % paths.length],
      variant: variant,
      startSeconds: 0,
      sourceDuration: durations[variant % durations.length],
      fadeInSeconds: 0.008,
      fadeOutSeconds: 0.020,
      targetPeak: 0.40,
    );
  }
  if (material == 'dirt') {
    return _sourceBackedVariant(
      path: 'tool/audio_sources/tinyworlds/mud02_source.wav',
      variant: variant,
      startSeconds: 0,
      sourceDuration: 0.120,
      fadeInSeconds: 0.004,
      fadeOutSeconds: 0.016,
      targetPeak: 0.40,
    );
  }

  final duration = switch (material) {
    'grass' => 0.175 + variant * 0.006,
    'dirt' => 0.158 + variant * 0.006,
    'leaves' => 0.155 + variant * 0.007,
    'gravel' => 0.155 + variant * 0.005,
    'stone' => 0.150 + variant * 0.004,
    'wood' => 0.158 + variant * 0.006,
    'metal' => 0.126 + variant * 0.004,
    'glass' => 0.090 + variant * 0.003,
    'sand' => 0.165 + variant * 0.006,
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
    'grass' || 'dirt' || 'leaves' || 'wood' || 'sand' => true,
    _ => false,
  };
  final lowResponse = switch (material) {
    'grass' => 0.050,
    'dirt' => 0.070,
    'sand' => 0.070,
    'gravel' => 0.055,
    'stone' => 0.050,
    _ => softMaterial ? 0.12 : 0.16,
  };
  final slowResponse = switch (material) {
    'grass' => 0.010,
    'dirt' => 0.014,
    'sand' => 0.012,
    'gravel' => 0.010,
    'stone' => 0.009,
    _ => softMaterial ? 0.028 : 0.035,
  };

  for (var i = 0; i < count; i++) {
    final t = i / sampleRate;
    final p = i / count;
    final raw = random.next() * 2 - 1;
    low += (raw - low) * lowResponse;
    slow += (raw - slow) * slowResponse;
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
        slow * 0.34 +
            low * 0.12 +
            mid * 0.38 +
            high * 0.0015 +
            (rustle - low) * 0.015 +
            grain * mid * 0.05,
      'dirt' =>
        slow * 0.34 +
            low * 0.32 +
            mid * 0.13 +
            high * 0.0015 +
            _ring(t, 92 + variant * 7, 46, 0.07) +
            _ring(t, 137 + variant * 9, 58, 0.035) +
            grain * mid * 0.05,
      'leaves' =>
        high * 0.10 +
            mid * 0.18 +
            (rustle - slow) * 0.28 +
            math.sin(2 * math.pi * (840 + variant * 23) * t) * 0.018 +
            grain * 0.07,
      'gravel' =>
        (slow * 0.16 +
                low * 0.28 +
                mid * 0.25 +
                high * 0.004 +
                grain * mid * 0.10) *
            (0.30 +
                _burst(t, 0.012 + variant * 0.001, 0.007) +
                _burst(t, 0.050 + variant * 0.003, 0.010) * 0.82 +
                _burst(t, 0.096 - variant * 0.002, 0.013) * 0.62),
      'stone' =>
        (slow * 0.14 +
                    low * 0.28 +
                    mid * 0.30 +
                    high * 0.003 +
                    grain * mid * 0.07) *
                (0.24 +
                    _burst(t, 0.007 + variant * 0.001, 0.005) * 1.08 +
                    _burst(t, 0.043 + variant * 0.002, 0.008) * 0.74 +
                    _burst(t, 0.091 - variant * 0.002, 0.012) * 0.50) +
            _ring(t, 315 + variant * 23, 145, 0.012) +
            _ring(t, 510 + variant * 29, 180, 0.005),
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
      'glass' =>
        mid * 0.12 +
            high * 0.18 +
            grain * high * 0.16 +
            _ring(t, 1320 + variant * 47, 138, 0.075) +
            _ring(t, 2110 + variant * 61, 184, 0.035),
      'sand' =>
        slow * 0.30 +
            low * 0.32 +
            mid * 0.24 +
            high * 0.006 +
            grain * mid * 0.08,
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
      'grass' => _timedEnvelope(t, p, 0.015, 2.45),
      'dirt' => _timedEnvelope(t, p, 0.014, 2.55),
      'sand' => _timedEnvelope(t, p, 0.012, 2.35),
      'gravel' => _timedEnvelope(t, p, 0.008, 2.25),
      'stone' => _timedEnvelope(t, p, 0.005, 2.85),
      'glass' => _timedEnvelope(t, p, 0.002, 3.40),
      'leaves' || 'wood' => _softEnvelope(p),
      'metal' => _stoneEnvelope(p),
      _ => _shortEnvelope(p),
    };
    samples[i] = sound * flutter * envelope;
  }
  final targetPeak = switch (material) {
    'grass' => 0.32,
    'dirt' => 0.38,
    'leaves' => 0.46,
    'wood' => 0.52,
    'sand' => 0.38,
    'gravel' => 0.38,
    'stone' => 0.40,
    'metal' => 0.54,
    'glass' => 0.44,
    _ => 0.68,
  };
  return _normalize(samples, targetPeak);
}

List<double> _sourceBackedVariant({
  required String path,
  required int variant,
  required double startSeconds,
  required double sourceDuration,
  required double fadeInSeconds,
  required double fadeOutSeconds,
  double? lowPassHz,
  double rateScale = 1,
  required double targetPeak,
}) {
  const playbackRates = <double>[0.975, 0.992, 1.008, 1.025];
  const startOffsets = <double>[0, 0.0015, 0.003, 0.0005];
  final source = _readMonoPcm16Wav(path);
  final baseRate = playbackRates[variant % playbackRates.length];
  final rate = rateScale == 1 ? baseRate : baseRate * rateScale;
  final sourceStart =
      ((startSeconds + startOffsets[variant % startOffsets.length]) *
              sampleRate)
          .round();
  final available = math.max(0, source.length - sourceStart);
  final sourceCount = math.min(
    available,
    (sourceDuration * sampleRate).round(),
  );
  final outputCount = (sourceCount / rate).floor();
  final output = List<double>.filled(outputCount, 0);
  final fadeInSamples = math.max(1, (fadeInSeconds * sampleRate).round());
  final fadeOutSamples = math.max(1, (fadeOutSeconds * sampleRate).round());
  final lowPassAlpha = lowPassHz == null
      ? null
      : 1 - math.exp(-2 * math.pi * lowPassHz / sampleRate);
  var lowPassState = 0.0;
  for (var i = 0; i < outputCount; i++) {
    final sourcePosition = sourceStart + i * rate;
    final lower = sourcePosition.floor();
    final upper = math.min(lower + 1, source.length - 1);
    final fraction = sourcePosition - lower;
    final sample = source[lower] * (1 - fraction) + source[upper] * fraction;
    if (lowPassAlpha != null) {
      lowPassState += (sample - lowPassState) * lowPassAlpha;
    }
    final filteredSample = lowPassAlpha == null ? sample : lowPassState;
    final fadeIn = (i / fadeInSamples).clamp(0.0, 1.0);
    final fadeOut = ((outputCount - 1 - i) / fadeOutSamples).clamp(0.0, 1.0);
    output[i] = filteredSample * math.min(fadeIn, fadeOut);
  }
  return _normalize(output, targetPeak);
}

List<double> _readMonoPcm16Wav(String path) {
  final bytes = File(path).readAsBytesSync();
  final view = ByteData.sublistView(bytes);
  String ascii(int offset, int length) =>
      String.fromCharCodes(bytes.sublist(offset, offset + length));
  if (bytes.length < 44 || ascii(0, 4) != 'RIFF' || ascii(8, 4) != 'WAVE') {
    throw FormatException('Not a RIFF/WAVE file: $path');
  }

  var offset = 12;
  int? dataOffset;
  int? dataLength;
  var formatIsSupported = false;
  while (offset + 8 <= bytes.length) {
    final chunkId = ascii(offset, 4);
    final chunkLength = view.getUint32(offset + 4, Endian.little);
    final payload = offset + 8;
    if (payload + chunkLength > bytes.length) break;
    if (chunkId == 'fmt ' && chunkLength >= 16) {
      formatIsSupported =
          view.getUint16(payload, Endian.little) == 1 &&
          view.getUint16(payload + 2, Endian.little) == 1 &&
          view.getUint32(payload + 4, Endian.little) == sampleRate &&
          view.getUint16(payload + 14, Endian.little) == 16;
    } else if (chunkId == 'data') {
      dataOffset = payload;
      dataLength = chunkLength;
    }
    offset = payload + chunkLength + chunkLength.remainder(2);
  }
  if (!formatIsSupported || dataOffset == null || dataLength == null) {
    throw FormatException('Expected mono PCM16 at 44.1 kHz: $path');
  }

  return List<double>.generate(
    dataLength ~/ 2,
    (index) => view.getInt16(dataOffset! + index * 2, Endian.little) / 32768.0,
    growable: false,
  );
}

double _ring(double t, double frequency, double decay, double gain) =>
    math.sin(2 * math.pi * frequency * t) * math.exp(-t * decay) * gain;

double _burst(double t, double center, double width) {
  final normalized = (t - center) / width;
  return math.exp(-normalized * normalized);
}

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

double _timedEnvelope(
  double elapsedSeconds,
  double progress,
  double attackSeconds,
  double decayPower,
) {
  final attack = (elapsedSeconds / attackSeconds).clamp(0.0, 1.0);
  return attack * math.pow(1 - progress, decayPower);
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
