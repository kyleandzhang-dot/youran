#version 460 core
#include <flutter/runtime_effect.glsl>

out vec4 fragColor;

uniform vec2 u_size;          // auto supplied by ImageFilter.shader
uniform sampler2D u_texture;  // auto supplied filter input
uniform float u_time;
uniform float u_distortion;
uniform float u_chromatic;
uniform float u_frost;
uniform float u_heat;
uniform float u_shock;
uniform float u_center_x;
uniform float u_center_y;

float hash21(vec2 p) {
  p = fract(p * vec2(123.34, 456.21));
  p += dot(p, p + 45.32);
  return fract(p.x * p.y);
}

float noise2(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  float a = hash21(i);
  float b = hash21(i + vec2(1.0, 0.0));
  float c = hash21(i + vec2(0.0, 1.0));
  float d = hash21(i + vec2(1.0, 1.0));
  return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
  float v = 0.0;
  float a = 0.5;
  for (int i = 0; i < 5; i++) {
    v += a * noise2(p);
    p = p * 2.03 + vec2(17.13, 9.71);
    a *= 0.5;
  }
  return v;
}

void main() {
  vec2 uv = FlutterFragCoord().xy / u_size;
#if defined(IMPELLER_TARGET_OPENGLES) && !defined(IMPELLER_OPENGLES_UNFLIPPED_DEPRECATED)
  uv.y = 1.0 - uv.y;
#endif

  vec2 center = vec2(u_center_x, u_center_y);
  vec2 d = uv - center;
  float r = length(d);
  vec2 dir = r > 0.0001 ? d / r : vec2(0.0);

  float n = fbm(uv * 8.0 + vec2(u_time * 0.55, -u_time * 0.41));
  float fine = fbm(uv * 24.0 - vec2(u_time * 0.23, u_time * 0.37));

  // Generic refraction/distortion. Frost uses crystalline noise, heat uses vertical shimmer.
  float heatWave = sin(uv.y * 70.0 + u_time * 18.0 + n * 8.0) * u_heat;
  vec2 warp = dir * (n - 0.5) * u_distortion * (0.35 + 0.65 * smoothstep(0.75, 0.05, r));
  warp += vec2(heatWave * 0.0035, cos(uv.x * 55.0 + u_time * 12.0) * u_heat * 0.0018);
  warp += (vec2(fine, n) - 0.5) * u_frost * 0.0045;

  // One expanding pressure ring. Runtime controls strength; this is not skill-specific.
  float ringRadius = fract(u_time * 1.15) * 0.72;
  float ring = exp(-pow((r - ringRadius) * 58.0, 2.0)) * u_shock;
  warp += dir * ring * 0.018;

  vec2 suv = clamp(uv + warp, vec2(0.001), vec2(0.999));
  vec2 ca = dir * u_chromatic * (0.20 + r * 0.80);
  float rr = texture(u_texture, clamp(suv + ca, vec2(0.001), vec2(0.999))).r;
  float gg = texture(u_texture, suv).g;
  float bb = texture(u_texture, clamp(suv - ca, vec2(0.001), vec2(0.999))).b;
  float aa = texture(u_texture, suv).a;
  vec3 color = vec3(rr, gg, bb);

  // Frost veins: sparse branching-looking procedural lines, strongest near the screen centre.
  float cells = abs(fract((n * 3.2 + fine * 1.8) * 5.0) - 0.5);
  float vein = smoothstep(0.085, 0.015, cells) * u_frost;
  vein *= smoothstep(0.95, 0.08, r);
  color += vec3(0.38, 0.78, 1.0) * vein * 0.42;

  // Pressure ring gets a brief white-blue rim independent of material family.
  color += vec3(0.62, 0.82, 1.0) * ring * 0.24;

  // Heat lifts warm highlights but keeps the source scene dominant.
  color += vec3(1.0, 0.30, 0.04) * u_heat * max(0.0, n - 0.62) * 0.12;

  fragColor = vec4(color, aa);
}
