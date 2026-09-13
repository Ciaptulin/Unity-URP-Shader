// ===== [Part2] 仅深度通道（后效深度用，含镂空）=====
#ifndef MY_LIT_DEPTH_ONLY_PASS_INCLUDED
#define MY_LIT_DEPTH_ONLY_PASS_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "MyLitCommon.hlsl"

struct Attributes
{
    float4 positionOS : POSITION;
    float2 uv : TEXCOORD0;
};

struct Interpolators
{
    float4 positionCS : SV_POSITION;
    float2 uv : TEXCOORD0;
};

Interpolators DepthOnlyVertex(Attributes input)
{
    Interpolators output = (Interpolators)0;
    output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
    output.uv = TRANSFORM_TEX(input.uv, _ColorMap);
    return output;
}

half4 DepthOnlyFragment(Interpolators input) : SV_TARGET
{
#ifdef _ALPHA_CUTOUT
    float4 colorSample = SAMPLE_TEXTURE2D(_ColorMap, sampler_ColorMap, input.uv);
    // 与 ShadowCaster / ForwardLit 保持一致的镂空
    colorSample.a = CalculateDotMatrix(input.uv, _DotDensity, _DotRadius, float2(_DotScaleX, _DotScaleY));
    TestAlphaClip(colorSample);
#endif
    return 0;
}

#endif
