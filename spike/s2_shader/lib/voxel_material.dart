import 'dart:ui' hide FragmentShader;

import 'package:flame_3d/graphics.dart';
import 'package:flame_3d/resources.dart';

/// Minimal custom material: outColor = texture * fragColor * albedoColor.
///
/// Unlike the stock UnlitMaterial/SpatialMaterial (which ignore fragColor),
/// this one multiplies by the interpolated per-vertex color, so baked AO
/// stored in Vertex.color darkens the surface.
class VoxelMaterial extends Material {
  VoxelMaterial({
    this.albedoColor = const Color(0xFFFFFFFF),
    Texture? albedoTexture,
  }) : albedoTexture = albedoTexture ?? Texture.standard,
       super(
         vertexShader: VertexShader.fromAsset(
           'assets/shaders/voxel_material.shaderbundle',
           slots: ['VertexInfo', 'JointMatrices'],
         ),
         fragmentShader: FragmentShader.fromAsset(
           'assets/shaders/voxel_material.shaderbundle',
           slots: ['albedoTexture', 'Material'],
         ),
       );

  Color albedoColor;
  Texture albedoTexture;

  @override
  void apply(covariant RenderContext3D context) {
    vertexShader
      ..setMatrix4('VertexInfo.model', context.model)
      ..setMatrix4('VertexInfo.view', context.view)
      ..setMatrix4('VertexInfo.projection', context.projection);

    // The vertex shader includes skinning.glsl, so JointMatrices must exist.
    // For static voxel geometry all weights are zero -> identity path; we
    // still have to declare the slot, but do not need to fill it.

    fragmentShader
      ..setTexture('albedoTexture', albedoTexture)
      ..setColor('Material.albedoColor', albedoColor);
  }
}
