#version 460 core

in vec2 fragTexCoord;
in vec4 fragColor;
in vec3 fragPosition;
in vec3 fragNormal;

out vec4 outColor;

uniform sampler2D albedoTexture;

uniform Material {
  vec4 albedoColor;
  vec4 fogColor;
  float fogStart;
  float fogEnd;
  float fogDensity;
  float bakedLightStrength;
  float debugView;
  float brightness;
} material;

uniform Camera {
  vec3 position;
} camera;

void main() {
  vec4 texel = texture(albedoTexture, fragTexCoord);
  vec3 bakedLight = mix(vec3(1.0), fragColor.rgb, material.bakedLightStrength);
  outColor = texel * vec4(bakedLight, fragColor.a) * material.albedoColor;

  // Alpha cutout: fully transparent texels (leaf holes, cross sprites) must
  // not write depth/color at all.
  if (outColor.a < 0.5) {
    discard;
  }

  // Premultiply BEFORE fog so fogged water converges to the sky color
  // instead of a darkened alpha-scaled band at the horizon.
  outColor.rgb *= outColor.a;

  int debugView = int(material.debugView + 0.5);
  if (debugView == 1) {
    outColor.rgb = texel.rgb * outColor.a;
  } else if (debugView == 2) {
    outColor.rgb = (normalize(fragNormal) * 0.5 + 0.5) * outColor.a;
  } else if (debugView == 3) {
    outColor.rgb = vec3(fragColor.b) * outColor.a;
  } else if (debugView == 4) {
    outColor.rgb = vec3(fragColor.r) * outColor.a;
  } else if (debugView == 5) {
    vec3 chunkUv = fract(abs(fragPosition) / 16.0);
    float edge = 1.0 - step(0.018, min(min(chunkUv.x, chunkUv.y), chunkUv.z));
    outColor.rgb = mix(outColor.rgb, vec3(1.0, 0.35, 0.05) * outColor.a, edge);
  } else if (debugView == 6) {
    outColor.rgb = vec3(0.85, 0.05, 0.75) * outColor.a;
  }

  outColor.rgb = min(outColor.rgb * material.brightness, vec3(outColor.a));

  float distanceToCamera = distance(fragPosition, camera.position);
  float fog = clamp(
    (distanceToCamera - material.fogStart) /
        (material.fogEnd - material.fogStart),
    0.0,
    1.0
  ) * material.fogDensity;
  outColor.rgb = mix(outColor.rgb, material.fogColor.rgb * outColor.a, fog);
}
