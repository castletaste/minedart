import 'package:flutter_scene/build_hooks.dart';
import 'package:hooks/hooks.dart';

/// Compiles the flutter_scene renderer's materials. Only the listed `.fmat`
/// sources are built; textures under assets/ are left to Flutter unchanged.
void main(List<String> args) async {
  await build(args, (input, output) async {
    await buildMaterials(
      buildInput: input,
      buildOutput: output,
      materials: const [
        'assets/materials/voxel_opaque.fmat',
        'assets/materials/voxel_translucent.fmat',
        'assets/materials/solid_color.fmat',
      ],
    );
  });
}
