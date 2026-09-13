#ifndef MY_LIT_COMMON_INCLUDED
// "#ifndef MY_LIT_COMMON_INCLUDED" is equivalent to "#if !defined(MY_LIT_COMMON_INCLUDED)"
#define MY_LIT_COMMON_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/UnityInput.hlsl"

// ===== [Part2] 材质属性（CBUFFER 兼容 SRP Batcher）=====
CBUFFER_START(UnityPerMaterial)
float4 _ColorTint;
float4 _ColorMap_ST;        // Unity 自动设置，供 TRANSFORM_TEX 应用 UV 平铺
float _Cutoff;              // 透明度裁切阈值
float _NormalStrength;      // [Part3] 法线强度
float _Metalness;           // [Part3] 金属度
float4 _SpecularTint;       // [Part3] 高光工作流色调
float4 _EmissionTint;       // [Part4] 自发光色调
float _Smoothness;          // [Part3] 平滑度
float _ParallaxStrength;    // [Part4] 视差强度
float _ClearCoatStrength;   // [Part4] 清漆强度
float _ClearCoatSmoothness; // [Part4] 清漆光滑度
float _OcclusionStrength;   // [Part5-三] 遮挡强度
// [Part4] 程序化点阵镂空参数
float _DotDensity;
float _DotRadius;
float _DotScaleX;
float _DotScaleY;
CBUFFER_END

// ===== 纹理声明 =====
TEXTURE2D(_ColorMap); SAMPLER(sampler_ColorMap);   // RGB = albedo, A = alpha
TEXTURE2D(_NormalMap); SAMPLER(sampler_NormalMap);
TEXTURE2D(_MetalnessMask); SAMPLER(sampler_MetalnessMask);
TEXTURE2D(_SpecularMap); SAMPLER(sampler_SpecularMap);
TEXTURE2D(_SmoothnessMask); SAMPLER(sampler_SmoothnessMask);
TEXTURE2D(_EmissionMap); SAMPLER(sampler_EmissionMap);
TEXTURE2D(_ParallaxMap); SAMPLER(sampler_ParallaxMap);
TEXTURE2D(_ClearCoatMask); SAMPLER(sampler_ClearCoatMask);
TEXTURE2D(_ClearCoatSmoothnessMask); SAMPLER(sampler_ClearCoatSmoothnessMask);
TEXTURE2D(_OcclusionMap); SAMPLER(sampler_OcclusionMap);
// 以下已在 URP 库的 Lighting.hlsl 里声明，无需重复
// TEXTURE2D(_MainLightCookieTexture); SAMPLER(sampler_MainLightCookieTexture);
// TEXTURE2D(_AdditionalCookieTexture); SAMPLER(sampler_AdditionalCookieTexture);

// ===== [Part4] Alpha 裁切 =====
void TestAlphaClip(float4 colorSample)
{
#ifdef _ALPHA_CUTOUT
    clip(colorSample.a - _Cutoff);
#endif
}

// ===== [Part4] 程序化点阵镂空 =====
// 世界坐标版
float CalculateDotMatrix(float3 worldPos, float density, float radius)
{
    float3 localPos = frac(worldPos * density) - 0.5;
    float dist = length(localPos);
    return step(dist, radius);
}
// UV 坐标版
float CalculateDotMatrix(float2 uv, float density, float radius, float2 scale)
{
    float2 scaledUV = uv * scale;
    float2 localPos = frac(scaledUV * density) - 0.5;
    float dist = length(localPos);
    return step(dist, radius);
}

#endif
