import 'package:flutter_test/flutter_test.dart';
import 'package:minedart/showcase/controller/world_library_controller.dart';

void main() {
  test('World Library exposes the three UI-only preset choices', () {
    expect(WorldLibraryPreset.values, <WorldLibraryPreset>[
      WorldLibraryPreset.classic,
      WorldLibraryPreset.flat,
      WorldLibraryPreset.islands,
    ]);
    expect(WorldLibraryPreset.classic.label, 'Classic');
    expect(WorldLibraryPreset.flat.label, 'Flat');
    expect(WorldLibraryPreset.islands.label, 'Islands');
  });
}
