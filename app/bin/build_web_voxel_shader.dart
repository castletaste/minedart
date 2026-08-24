import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

/// Builds a small WebGPU-only shader bundle from flame_3d's bundled unlit
/// vertex shader/reflection. This avoids requiring the external `naga` CLI
/// while adding the two voxel-specific operations the stock material lacks:
/// vertex lighting and alpha cutout.
Future<void> main() async {
  final libraryUri = await Isolate.resolvePackageUri(
    Uri.parse('package:flame_3d/resources.dart'),
  );
  if (libraryUri == null) {
    throw StateError('Unable to resolve flame_3d shader bundle.');
  }
  final sourceUri = libraryUri.resolve(
    '../assets/shaders/unlit_material.wgslbundle',
  );

  final bundle =
      jsonDecode(File.fromUri(sourceUri).readAsStringSync())
          as Map<String, dynamic>;
  bundle['fragment'] = _fragmentSource;
  final slots = bundle['slots'] as Map<String, dynamic>;
  slots['Material'] = <String, Object>{
    'group': 1,
    'binding': 2,
    'sizeInBytes': 64,
    'memberOffsets': <String, int>{
      'albedoColor': 0,
      'fogColor': 16,
      'fogStart': 32,
      'fogEnd': 36,
      'fogDensity': 40,
      'bakedLightStrength': 44,
      'debugView': 48,
      'brightness': 52,
    },
  };
  slots['Camera'] = <String, Object>{
    'group': 1,
    'binding': 3,
    'sizeInBytes': 16,
    'memberOffsets': <String, int>{'position': 0},
  };

  final output = File('assets/shaders/web_voxel_material.wgslbundle');
  output.parent.createSync(recursive: true);
  output.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(bundle));
  stdout.writeln('Wrote ${output.path}');
}

const _fragmentSource = r'''
struct Material {
  albedoColor: vec4<f32>,
  fogColor: vec4<f32>,
  fogStart: f32,
  fogEnd: f32,
  fogDensity: f32,
  bakedLightStrength: f32,
  debugView: f32,
  brightness: f32,
}

struct Camera {
  position: vec3<f32>,
}

struct FragmentOutput {
  @location(0) outColor: vec4<f32>,
}

@group(1) @binding(0)
var albedoTexture: texture_2d<f32>;
@group(1) @binding(1)
var albedoTextureSampler: sampler;
@group(1) @binding(2)
var<uniform> material: Material;
@group(1) @binding(3)
var<uniform> camera: Camera;

@fragment
fn main(
  @location(0) fragTexCoord: vec2<f32>,
  @location(1) fragColor: vec4<f32>,
  @location(2) fragPosition: vec3<f32>,
  @location(3) fragNormal: vec3<f32>,
) -> FragmentOutput {
  let texel = textureSample(
    albedoTexture,
    albedoTextureSampler,
    fragTexCoord,
  );
  let bakedLight = mix(
    vec3<f32>(1f),
    fragColor.rgb,
    vec3<f32>(material.bakedLightStrength),
  );
  var color = texel * material.albedoColor * vec4<f32>(bakedLight, fragColor.a);
  if (color.a < 0.5) {
    discard;
  }
  color = vec4<f32>(color.rgb * color.a, color.a);

  let debugView = i32(material.debugView + 0.5f);
  if (debugView == 1) {
    color = vec4<f32>(texel.rgb * color.a, color.a);
  } else if (debugView == 2) {
    color = vec4<f32>((normalize(fragNormal) * 0.5f + 0.5f) * color.a, color.a);
  } else if (debugView == 3) {
    color = vec4<f32>(vec3<f32>(fragColor.b) * color.a, color.a);
  } else if (debugView == 4) {
    color = vec4<f32>(vec3<f32>(fragColor.r) * color.a, color.a);
  } else if (debugView == 5) {
    let chunkUv = fract(abs(fragPosition) / 16f);
    let edge = 1f - step(0.018f, min(min(chunkUv.x, chunkUv.y), chunkUv.z));
    color = vec4<f32>(mix(color.rgb, vec3<f32>(1f, 0.35f, 0.05f) * color.a, vec3<f32>(edge)), color.a);
  } else if (debugView == 6) {
    color = vec4<f32>(vec3<f32>(0.85f, 0.05f, 0.75f) * color.a, color.a);
  }
  color = vec4<f32>(min(color.rgb * material.brightness, vec3<f32>(color.a)), color.a);

  let fogSpan = max(material.fogEnd - material.fogStart, 0.001f);
  let fog = clamp(
    (distance(fragPosition, camera.position) - material.fogStart) / fogSpan,
    0f,
    1f,
  ) * material.fogDensity;
  color = vec4<f32>(
    mix(color.rgb, material.fogColor.rgb * color.a, vec3<f32>(fog)),
    color.a,
  );
  return FragmentOutput(color);
}
''';
