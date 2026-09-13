// ===== [Part5-二] 光照烘焙元通道（反照率 + 自发光 + 镂空）=====
#ifndef MY_LIT_META_PASS_INCLUDED
#define MY_LIT_META_PASS_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/UnityInput.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/MetaPass.hlsl"
#include "MyLitCommon.hlsl"

struct Attributes
{
    float4 positionOS : POSITION;
    float3 normalOS : NORMAL;
    float2 uv0 : TEXCOORD0;
    float2 uv1 : TEXCOORD1;
    float2 uv2 : TEXCOORD2;
};

struct Interpolators
{
    float4 positionCS : SV_POSITION;
    float2 uv : TEXCOORD0;
};

// 顶点函数：UniversalMetaPass.hlsl 里的 UniversalVertexMeta 引用了 _BaseMap，
// 我们的 shader 用的是 _ColorMap，所以需要自己写一个
Interpolators Vertex(Attributes input)
{
    Interpolators output = (Interpolators)0;

    // 三参数重载内部会转发到五参数版（使用 unity_LightmapST / unity_DynamicLightmapST）
    // 注意：必须传 uv1 / uv2（第二、三套 uv），不能传 uv0
    output.positionCS = UnityMetaVertexPosition(input.positionOS.xyz, input.uv1, input.uv2);

    // TRANSFORM_TEX 只在这里做一次，片元里直接用
    output.uv = TRANSFORM_TEX(input.uv0, _ColorMap);
    return output;
}

// 片段函数：采样材质纹理，输出给光照烘焙器
float4 Fragment(Interpolators input) : SV_TARGET
{
    float2 uv = input.uv;

    float4 colorSample = SAMPLE_TEXTURE2D(_ColorMap, sampler_ColorMap, uv) * _ColorTint;

    // 镂空必须与 ShadowCaster 保持一致，否则烘焙的光照会对不上阴影
#ifdef _ALPHA_CUTOUT
    colorSample.a = CalculateDotMatrix(uv, _DotDensity, _DotRadius,
                                        float2(_DotScaleX, _DotScaleY));
    TestAlphaClip(colorSample);
#endif

    // 采样自发光
    float3 emission = SAMPLE_TEXTURE2D(_EmissionMap, sampler_EmissionMap, uv).rgb * _EmissionTint.rgb;

    // 填 UnityMetaInput，传给内置的 UnityMetaFragment
    UnityMetaInput metaInput;
    metaInput.Albedo = colorSample.rgb;
    metaInput.Emission = emission;

    return UnityMetaFragment(metaInput);
}

#endif
