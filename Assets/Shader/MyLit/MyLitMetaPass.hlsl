#ifndef MY_LIT_META_PASS_INCLUDED
#define MY_LIT_META_PASS_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl" 
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/UnityInput.hlsl"  // ← 放最前面
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/MetaPass.hlsl"
#include "MyLitCommon.hlsl"

struct Attributes
{
    float4 positionOS : POSITION;
    float3 normalOS   : NORMAL;
    float2 uv0        : TEXCOORD0;
    float2 uv1        : TEXCOORD1;
    float2 uv2        : TEXCOORD2;
};

struct Varyings
{
    float4 positionCS : SV_POSITION;
    float2 uv         : TEXCOORD0;
};
// 顶点函数：UniversalMetaPass.hlsl里的UniversVertexMeta引用了_BaseMap
// 我们的shader用的是_ColorMap，所以需要自己写一个
Varyings Vertex(Attributes input){
    Varyings output = (Varyings)0;

    // 三参数重载内部会转发到五参数版（使用unity_LightmapST/unity_DynamicLightmapST),core的MetaPass.hlsl两个重载都有，所有这样写是安全的
    // 注意：这里必须传uv1/uv2（第二、三套uv），不能传uv0
    output.positionCS = UnityMetaVertexPosition(input.positionOS.xyz, input.uv1, input.uv2);
    
    // TRANSFORM_TEX只在这里做一次，片元里直接用
    output.uv = TRANSFORM_TEX(input.uv0, _ColorMap);
    return output;
}

// 片段函数：采样材质纹理，输出给光照烘焙器
float4 Fragment(Varyings input) : SV_TARGET{
    // 修复：原来片元里又做了一次TRANSFORM_TEX，导致平铺/偏移被应用两次
    float2 uv = input.uv;

    float4 colorSample = SAMPLE_TEXTURE2D(_ColorMap, sampler_ColorMap, uv) * _ColorTint;

    // 修复：原来MetaPass完全没做镂空，与ShadowCaster的阴影对不上
#ifdef _ALPHA_CUTOUT
    colorSample.a = CalculateDotMatrix(uv, _DotDensity, _DotRadius,
                                        float2(_DotScaleX, _DotScaleY));
    TestAlphaClip(colorSample);
#endif
    // 采样自发光
    float3 emission = SAMPLE_TEXTURE2D(_EmissionMap, sampler_EmissionMap, uv).rgb * _EmissionTint.rgb;

    // 填UnityMetaInput，传给内置的UnityMetaFragment
    UnityMetaInput metaInput;
    metaInput.Albedo = colorSample.rgb;
    metaInput.Emission = emission;

    return UnityMetaFragment(metaInput);
}
#endif