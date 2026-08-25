import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:minedart/audio/audio.dart';
import 'package:minedart_core/minedart_core.dart';

void main() {
  group('generated audio assets', () {
    final assetPaths = <String>{
      for (final cue in AudioCue.values) ...cue.assetPaths,
    }.toList()..sort();
    for (final assetPath in assetPaths) {
      test('$assetPath is mono PCM16 at 44.1 kHz', () {
        final file = File('assets/$assetPath');
        expect(file.existsSync(), isTrue, reason: file.path);
        final bytes = file.readAsBytesSync();
        expect(bytes.length, greaterThan(44));
        expect(_text(bytes, 0, 4), 'RIFF');
        expect(_text(bytes, 8, 4), 'WAVE');
        expect(_text(bytes, 12, 4), 'fmt ');
        final view = ByteData.sublistView(bytes);
        expect(view.getUint16(20, Endian.little), 1);
        expect(view.getUint16(22, Endian.little), 1);
        expect(view.getUint32(24, Endian.little), 44100);
        expect(view.getUint16(34, Endian.little), 16);
        expect(_text(bytes, 36, 4), 'data');
        final dataLength = view.getUint32(40, Endian.little);
        expect(bytes.length, 44 + dataLength);
        expect(dataLength, greaterThan(4410));
        expect(dataLength, lessThan(44100 * 2));

        var peak = 0;
        for (var offset = 44; offset < bytes.length; offset += 2) {
          final samplePeak = view.getInt16(offset, Endian.little).abs();
          if (samplePeak > peak) peak = samplePeak;
        }
        expect(peak, lessThan(32767));
        if (_usesSoftenedMaterialTransient(assetPath)) {
          expect(peak / 32767, lessThanOrEqualTo(0.5));
          final quarterPeak = peak * 0.25;
          var onsetSamples = 0;
          for (var offset = 44; offset < bytes.length; offset += 2) {
            if (view.getInt16(offset, Endian.little).abs() >= quarterPeak) {
              onsetSamples = (offset - 44) ~/ 2;
              break;
            }
          }
          expect(
            onsetSamples,
            greaterThanOrEqualTo((44100 * 0.0015).round()),
            reason: '$assetPath must not begin with a click-like transient',
          );
        }
      });
    }
  });

  group('AudioCue', () {
    test(
      'explosion cue requires TNT rather than a large liquid retraction',
      () {
        final waterRetraction = <WorldChange>[
          for (var x = 0; x < 32; x++)
            WorldChange(
              x: x,
              y: 1,
              z: 0,
              oldRaw: LiquidState.pack(Blocks.water, x & 7),
              newRaw: Blocks.air,
            ),
        ];
        expect(shouldPlayExplosionForWorldChanges(waterRetraction), isFalse);
        expect(
          shouldPlayExplosionForWorldChanges(<WorldChange>[
            ...waterRetraction,
            const WorldChange(
              x: 40,
              y: 1,
              z: 0,
              oldRaw: Blocks.tnt,
              newRaw: Blocks.air,
            ),
          ]),
          isTrue,
        );
      },
    );

    test('maps stable block materials to break/place/step cues', () {
      expect(
        AudioCue.forBlock(Blocks.stone, BlockAudioAction.breakBlock),
        AudioCue.stoneBreak,
      );
      expect(
        AudioCue.forBlock(Blocks.cobblestone, BlockAudioAction.placeBlock),
        AudioCue.stonePlace,
      );
      expect(
        AudioCue.forBlock(Blocks.dirt, BlockAudioAction.breakBlock),
        AudioCue.dirtBreak,
      );
      expect(
        AudioCue.forBlock(Blocks.sand, BlockAudioAction.placeBlock),
        AudioCue.sandPlace,
      );
      expect(
        AudioCue.forBlock(Blocks.logOak, BlockAudioAction.breakBlock),
        AudioCue.woodBreak,
      );
      expect(
        AudioCue.forBlock(Blocks.planksOak, BlockAudioAction.placeBlock),
        AudioCue.woodPlace,
      );
      expect(
        AudioCue.forBlock(Blocks.gravel, BlockAudioAction.breakBlock),
        AudioCue.gravelBreak,
      );
      expect(
        AudioCue.forBlock(Blocks.water, BlockAudioAction.placeBlock),
        AudioCue.water,
      );
      expect(
        AudioCue.forBlock(Blocks.leavesOak, BlockAudioAction.breakBlock),
        AudioCue.leavesBreak,
      );
      expect(
        AudioCue.forBlock(Blocks.clothRed, BlockAudioAction.placeBlock),
        AudioCue.grassPlace,
      );
      expect(
        AudioCue.forBlock(Blocks.glass, BlockAudioAction.breakBlock),
        AudioCue.stoneHighBreak,
      );
      expect(
        AudioCue.forBlock(Blocks.goldBlock, BlockAudioAction.breakBlock),
        AudioCue.metalBreak,
      );
      expect(
        AudioCue.forBlock(Blocks.ironBlock, BlockAudioAction.placeBlock),
        AudioCue.metalPlace,
      );
      expect(
        AudioCue.forBlock(Blocks.stone, BlockAudioAction.step),
        AudioCue.stoneStep,
      );
      expect(
        AudioCue.forBlock(Blocks.stone, BlockAudioAction.breakBlock),
        AudioCue.stoneBreak,
      );
      expect(
        AudioCue.forBlock(Blocks.stone, BlockAudioAction.placeBlock),
        AudioCue.stonePlace,
      );
      expect(
        AudioCue.forBlock(Blocks.leavesOak, BlockAudioAction.step),
        AudioCue.leavesStep,
      );
      expect(AudioCue.dirtBreak.assetPaths, hasLength(4));
      expect(AudioCue.leavesBreak.assetPaths, hasLength(4));
      expect(
        AudioCue.dirtBreak.assetPaths,
        isNot(AudioCue.grassBreak.assetPaths),
      );
      expect(
        AudioCue.leavesBreak.assetPaths,
        isNot(AudioCue.grassBreak.assetPaths),
      );
      expect(AudioCue.stoneBreak.baseVolume, lessThan(0.7));
      expect(
        AudioCue.stoneHighBreak.assetPaths,
        isNot(AudioCue.stoneBreak.assetPaths),
      );
    });

    test('Classic actions share one sample bank per material', () {
      const cueGroups = <List<AudioCue>>[
        [AudioCue.stoneBreak, AudioCue.stonePlace, AudioCue.stoneStep],
        [
          AudioCue.stoneHighBreak,
          AudioCue.stoneHighPlace,
          AudioCue.stoneHighStep,
        ],
        [AudioCue.grassBreak, AudioCue.grassPlace, AudioCue.grassStep],
        [AudioCue.dirtBreak, AudioCue.dirtPlace, AudioCue.dirtStep],
        [AudioCue.leavesBreak, AudioCue.leavesPlace, AudioCue.leavesStep],
        [AudioCue.woodBreak, AudioCue.woodPlace, AudioCue.woodStep],
        [AudioCue.gravelBreak, AudioCue.gravelPlace, AudioCue.gravelStep],
        [AudioCue.metalBreak, AudioCue.metalPlace, AudioCue.metalStep],
        [AudioCue.sandBreak, AudioCue.sandPlace, AudioCue.sandStep],
      ];
      for (final group in cueGroups) {
        expect(group[1].assetPaths, group[0].assetPaths);
        expect(group[2].assetPaths, group[0].assetPaths);
      }
    });

    test('unknown IDs use the stable stone fallback', () {
      expect(
        AudioCue.forBlock(999, BlockAudioAction.breakBlock),
        AudioCue.stoneBreak,
      );
    });

    test('sample and volume variation is deterministic and bounded', () {
      final first = audioVariation(AudioCue.gravelBreak, 42);
      final second = audioVariation(AudioCue.gravelBreak, 42);
      expect(first, second);
      expect(first.variantIndex, inInclusiveRange(0, 3));
      expect(first.volume, inInclusiveRange(0.96, 1.0));
      expect(audioVariation(AudioCue.gravelBreak, 43), isNot(first));
    });

    test('legacy cue slot preserves deterministic cue indices', () {
      expect(AudioCue.gravelBreak.index, 8);
      expect(AudioCue.dirtBreak.index, 15);
    });

    test('volume clamping is bounded', () {
      expect(clampAudioVolume(-1), 0);
      expect(clampAudioVolume(2), 1);
    });
  });

  group('AudioService', () {
    test(
      'applies volume, mute, deterministic variation, and disposes backend',
      () async {
        final backend = _RecordingBackend();
        final service = AudioService.withBackend(backend, maxSfxVolume: 0.75);
        addTearDown(service.dispose);

        await service.play(AudioCue.uiClick, seed: 8, volume: 2);
        expect(backend.calls, hasLength(1));
        expect(backend.calls.single.cue, AudioCue.uiClick);
        expect(backend.calls.single.variantIndex, 0);
        expect(backend.calls.single.volume, lessThanOrEqualTo(0.75));
        await service.setSfxVolume(-2);
        await service.play(AudioCue.uiClick, seed: 8);
        expect(backend.calls, hasLength(1));
        await service.setSfxVolume(1);
        await service.setMuted(true);
        await service.play(AudioCue.uiClick);
        expect(backend.calls, hasLength(1));
        await service.setMuted(false);
        await service.dispose();
        expect(backend.disposeCalls, 1);
        expect(service.isDisposed, isTrue);
        await service.play(AudioCue.uiClick);
        expect(backend.calls, hasLength(1));
        await service.dispose();
        expect(backend.disposeCalls, 1);
      },
    );

    test('NullAudioService is safe to call', () async {
      const service = NullAudioService();
      await service.play(AudioCue.explosion, seed: 99);
      await service.setSfxVolume(0.3);
      await service.setMusicVolume(0.2);
      await service.setMuted(false);
      await service.dispose();
      expect(service.muted, isTrue);
    });
  });
}

String _text(Uint8List bytes, int offset, int length) =>
    String.fromCharCodes(bytes.sublist(offset, offset + length));

bool _usesSoftenedMaterialTransient(String assetPath) =>
    assetPath.startsWith('audio/dirt_') ||
    assetPath.startsWith('audio/grass_') ||
    assetPath.startsWith('audio/gravel_') ||
    assetPath.startsWith('audio/leaves_') ||
    assetPath.startsWith('audio/sand_') ||
    assetPath.startsWith('audio/stone_') ||
    assetPath.startsWith('audio/wood_');

final class _Call {
  const _Call(this.cue, this.variantIndex, this.volume);

  final AudioCue cue;
  final int variantIndex;
  final double volume;
}

final class _RecordingBackend implements AudioPoolBackend {
  final calls = <_Call>[];
  var disposeCalls = 0;

  @override
  Future<void> play({
    required AudioCue cue,
    required int variantIndex,
    required double volume,
  }) async {
    calls.add(_Call(cue, variantIndex, volume));
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
  }
}
