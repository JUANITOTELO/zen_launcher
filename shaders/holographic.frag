#version 460 core

#include <flutter/runtime_effect.glsl>

// Viewport and sensor uniforms
uniform vec2 u_resolution;           // 0, 1: Viewport size in pixels (width, height)
uniform vec2 u_offset;               // 2, 3: Smoothed tilt offset from accelerometer/touch (-1.0 to 1.0)
uniform float u_focus_plane;         // 4: Depth focal plane (0.0 to 1.0)
uniform float u_depth_intensity;     // 5: Maximum parallax translation magnitude
uniform float u_overscan;            // 6: Zoom factor to eliminate blank borders during tilting
uniform float u_sheen;               // 7: Holographic iridescent dispersion intensity
uniform float u_detail_sensitivity;  // 8: Fine detail preservation strength (0.0 to 1.0)
uniform float u_perspective_warp;    // 9: 3D Keystone foreshortening & ray divergence (0.0 to 1.0)

// Texture samplers
uniform sampler2D u_image;           // Sampler 0: Color wallpaper texture
uniform sampler2D u_depth;           // Sampler 1: 8-bit depth map texture

out vec4 fragColor;

// Luminance calculation helper
float getLuma(vec3 c) {
    return dot(c, vec3(0.299, 0.587, 0.114));
}

void main() {
    // 1. Normalized screen coordinate [0.0, 1.0]
    vec2 screenUv = FlutterFragCoord().xy / u_resolution;

    // 2. 3D Projective Keystone Homography & Overscan
    // Simulates natural 50mm cinematic camera lens foreshortening as the viewer tilts
    vec2 centeredUv = screenUv - 0.5;
    float keystoneDenominator = 1.0 + dot(centeredUv, u_offset) * (u_perspective_warp * 0.35);
    vec2 warpedUv = (centeredUv / keystoneDenominator) / u_overscan + 0.5;

    vec2 texelSize = vec2(1.0) / u_resolution;
    vec2 stepX = vec2(texelSize.x * 2.0, 0.0);
    vec2 stepY = vec2(0.0, texelSize.y * 2.0);

    // 3. Multi-Tap Depth & High-Frequency Detail Analysis
    float dC = texture(u_depth, clamp(warpedUv, vec2(0.0), vec2(1.0))).r;
    float dL = texture(u_depth, clamp(warpedUv - stepX, vec2(0.0), vec2(1.0))).r;
    float dR = texture(u_depth, clamp(warpedUv + stepX, vec2(0.0), vec2(1.0))).r;
    float dT = texture(u_depth, clamp(warpedUv - stepY, vec2(0.0), vec2(1.0))).r;
    float dB = texture(u_depth, clamp(warpedUv + stepY, vec2(0.0), vec2(1.0))).r;

    // Filtered base depth suppresses single-pixel noise
    float baseDepth = (dC * 2.0 + dL + dR + dT + dB) / 6.0;

    // Spatial gradient & 2D Laplacian curvature
    vec2 depthGrad = vec2(dR - dL, dB - dT) * 0.5;
    float depthLaplacian = abs(4.0 * dC - (dL + dR + dT + dB));
    float depthEdgeMetric = length(depthGrad) * 4.0 + depthLaplacian * 3.0;

    // High-frequency color texture edge detection for delicate architectural details/wires/edges
    vec3 colC_raw = texture(u_image, clamp(warpedUv, vec2(0.0), vec2(1.0))).rgb;
    vec3 colL_raw = texture(u_image, clamp(warpedUv - stepX, vec2(0.0), vec2(1.0))).rgb;
    vec3 colR_raw = texture(u_image, clamp(warpedUv + stepX, vec2(0.0), vec2(1.0))).rgb;
    vec3 colT_raw = texture(u_image, clamp(warpedUv - stepY, vec2(0.0), vec2(1.0))).rgb;
    vec3 colB_raw = texture(u_image, clamp(warpedUv + stepY, vec2(0.0), vec2(1.0))).rgb;

    float lumaGrad = length(vec2(
        getLuma(colR_raw) - getLuma(colL_raw),
        getLuma(colB_raw) - getLuma(colT_raw)
    )) * 0.5;

    // Combined Fine-Detail Factor (0.0 = uniform smooth surface, 1.0 = sharp fine detail / edge)
    float fineDetailFactor = clamp(depthEdgeMetric * 0.6 + lumaGrad * 1.4, 0.0, 1.0);

    // Fine-Detail Adaptive Displacement Damping:
    // Firmly anchors delicate architectural railings, cables, and filigree to stop tearing
    float detailDamping = 1.0 / (1.0 + u_detail_sensitivity * (fineDetailFactor * 3.0 + pow(fineDetailFactor, 2.0) * 4.0));

    // 4. Optical 3D Perspective Ray & Depth Disparity
    vec2 eyePos = -u_offset * 0.25;
    vec2 rayDir = (warpedUv - 0.5 - eyePos);
    float depthDisparity = (pow(baseDepth, 2.0) - pow(u_focus_plane, 2.0));

    vec2 totalDisplacement = (-u_offset + rayDir * (u_perspective_warp * 0.35)) * u_depth_intensity * depthDisparity * detailDamping;

    // 5. Asymmetric Depth-Occlusion Clamping (Anti-Halo / Zero Black Silhouette Outlines)
    // Critical Optical Rule: Background rays (sea/sky) must NEVER sample foreground surfaces (cliff/building).
    // If destination depth is higher than source depth, we are stepping across a silhouette into the foreground.
    vec2 testUv = clamp(warpedUv + totalDisplacement, vec2(0.0), vec2(1.0));
    float destDepth = texture(u_depth, testUv).r;
    float occlusionCliff = max(0.0, destDepth - baseDepth);

    // Secondary mid-point check to prevent skipping narrow foreground struts
    vec2 midUv = clamp(warpedUv + totalDisplacement * 0.5, vec2(0.0), vec2(1.0));
    float midDepth = texture(u_depth, midUv).r;
    float midCliff = max(0.0, midDepth - baseDepth);
    float maxCliff = max(occlusionCliff, midCliff);

    // When background rays land on foreground cliffs, occlusionWeight drops sharply to 0.0,
    // pulling the sample back to the background sea/sky and completely eliminating dark halo ghosting.
    float occlusionWeight = clamp(1.0 - maxCliff * 7.5, 0.0, 1.0);

    vec2 finalUv = clamp(warpedUv + totalDisplacement * occlusionWeight, vec2(0.0), vec2(1.0));

    // 6. Base Color Sample
    vec4 baseColor = texture(u_image, finalUv);

    // 7. Cinematic Contact Ambient Occlusion (Grounded Crevices, Zero Flashbang)
    // Deepens rock crevices and architectural undersides for tactile solidity without adding brightness.
    float contactAO = clamp(1.0 - depthLaplacian * 1.5, 0.82, 1.0);

    // 8. Soft Directional Relief (Subtle ±3% Sculptural Shading)
    vec3 normal = normalize(vec3(-depthGrad * 2.0, 1.0));
    vec3 lightDir = normalize(vec3(-u_offset * 0.6, 0.95));
    float relief = (dot(normal, lightDir) - 0.7) * 0.05;

    // 9. Restrained Holographic Micro-Sheen
    // Gentle optical anti-reflective dispersion, strictly masked by grazing angles (Fresnel)
    float fresnel = pow(1.0 - clamp(dot(normal, vec3(0.0, 0.0, 1.0)), 0.0, 1.0), 3.5);
    vec3 iridescentPhase = vec3(0.0, 0.33, 0.67);
    vec3 iridescentRainbow = 0.5 + 0.5 * cos(6.28318 * (fresnel * 1.8 + iridescentPhase + dot(u_offset, vec2(0.3))));
    vec3 sheenOffset = (iridescentRainbow - 0.5) * (fresnel * u_sheen * 3.0);

    // 10. Filmic Composition & Tone Preservation (Zero Flashbang, Rich Cinematic Contrast)
    vec3 composedRgb = (baseColor.rgb * contactAO + sheenOffset) * (1.0 + relief);

    // Soft highlight knee compression (guarantees highlights never blow out or flashbang)
    vec3 filmicRgb = clamp(composedRgb, vec3(0.0), vec3(1.15));
    filmicRgb = filmicRgb / (1.0 + max(vec3(0.0), filmicRgb - 0.85) * 0.35);

    // Subtle 2% cinematic lens vignette to focus eye on architecture
    float vignette = 1.0 - dot(centeredUv, centeredUv) * 0.10;
    filmicRgb *= vignette;

    fragColor = vec4(clamp(filmicRgb, 0.0, 1.0), baseColor.a);
}
