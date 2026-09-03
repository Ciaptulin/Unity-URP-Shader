#ifndef MY_LIT_DEPTH_ONLY_PASS_INCLUDED
#define MY_LIT_DEPTH_ONLY_PASS_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "MyLitCommon.hlsl"

struct Attributes{
    float4 positionOS : POSITION;
    float2 uv : TEXCOORD0;
};

struct Varyings{
    float4 positionCS : SV_POSITION;
    float2 uv : TEXCOORD0;
};

Varyings DepthOnlyVertex(Attributes input){
    Varyings output = (Varyings)0;
    output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
    output.uv = TRANSFORM_TEX(input.uv, _ColorMap);
    return output;
}

half4 DepthOnlyFragment(Varyings input) : SV_TARGET{
#ifdef _ALPHA_CUTOUT
    float2 uv = input.uv;
    float4 colorSample = SAMPLE_TEXTURE2D(_ColorMap, sampler_ColorMap, uv);
    // 与ShadowCaster / ForwardLit保持一致的镂空
    colorSample.a = CalculateDotMatrix(uv, _DotDensity, _DotRadius, float2(_DotScaleX, _DotScaleY));
    TestAlphaClip(colorSample);
#endif
    return 0;
}
#endif