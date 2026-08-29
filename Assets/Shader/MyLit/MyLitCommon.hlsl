#ifndef MY_LIT_COMMON_INCLUDED
// "#ifndef MY_LIT_COMMON_INCLUDED" is equivalent to "#if !defined(MY_LIT_COMMON_INCLUDED)"
#define MY_LIT_COMMON_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

// 用 CBUFFER 包裹材质属性 为了兼容 SRP Batcher（不然动态合批会有问题）
CBUFFER_START(UnityPerMaterial)
float4 _ColorTint;
float4 _ColorMap_ST; // 这是Unity自动设置的，供TRANSFORM_TEX使用来应用UV平铺
float _NormalStrength;
float _Smoothness;
float _Cutoff; // 让给GPU接收到透明度裁切阈值的滑条值
// 程序化生成镂空材质
float _DotDensity; // 点的密度（比如 10.0）
float _DotRadius;  // 点的半径（比如 0.3）
float _DotScaleX;
float _DotScaleY;
CBUFFER_END
// Textures
TEXTURE2D(_ColorMap); SAMPLER(sampler_ColorMap); // RGB = albedo, A = alpha
TEXTURE2D(_NormalMap); SAMPLER(sampler_NormalMap);

void TestAlphaClip(float4 colorSample) {
#ifdef _ALPHA_CUTOUT
	// clip(colorSample.a * _ColorTint.a - _Cutoff);
    clip(colorSample.a - _Cutoff);  // 去掉 * _ColorTint.a
#endif
}

// 程序化生成点阵 世界坐标版
float CalculateDotMatrix(float3 worldPos, float density, float radius){
    float3 localPos = frac(worldPos * density) - 0.5;
    float dist = length(localPos);
    return step(dist, radius);
}
// UV 坐标版
float CalculateDotMatrix(float2 uv, float density, float radius, float2 scale) {
    float2 scaledUV = uv * scale;
    float2 localPos = frac(scaledUV * density) - 0.5;
    float dist = length(localPos);
    return step(dist, radius);
}

#endif