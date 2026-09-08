#version 460 core
#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform vec2 uView;
uniform float uStrength;
uniform float uOverscan;
uniform sampler2D uColor;
uniform sampler2D uDepth;

out vec4 fragColor;

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;

  // Slight overscan prevents black borders while the virtual camera moves.
  vec2 baseUv = (uv - vec2(0.5)) / uOverscan + vec2(0.5);

  // Depth Anything V2 preview is normalized as black=far, white=near.
  float depth = texture(uDepth, clamp(baseUv, vec2(0.0), vec2(1.0))).r;
  depth = smoothstep(0.03, 0.97, depth);

  // Far pixels still move a little; near pixels move substantially more.
  // This is deliberately subtle so the result reads as camera motion rather
  // than a rubber-sheet distortion.
  float layerMotion = mix(0.12, 1.0, depth);
  vec2 maxShift = vec2(0.020, 0.016) * uStrength;
  vec2 shift = uView * maxShift * layerMotion;

  vec2 sampleUv = clamp(baseUv - shift, vec2(0.001), vec2(0.999));
  fragColor = texture(uColor, sampleUv);
}
