// ===== [Part5-七] 运动向量通道（运动模糊 / TAA 用）=====
#ifndef MY_LIT_MOTION_VECTORS_PASS_INCLUDED
#define MY_LIT_MOTION_VECTORS_PASS_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/UnityInput.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/MotionVectorsCommon.hlsl"
#include "MyLitCommon.hlsl"

struct Attributes
{
    float4 positionOS : POSITION;
#ifdef _ALPHA_CUTOUT
    float2 uv :TEXCOORD0;
#endif
};

struct Interpolators
{
    float4 positionCS : SV_POSITION;
    float4 positionCSNoJitter : POSITION_CS_NO_JITTER;
    float4 previousPositionCSNoJitter : PREV_POSITION_CS_NO_JITTER;
#ifdef _ALPHA_CUTOUT
    float2 uv : TEXCOORD0;
#endif
};

Interpolators Vertex(Attributes input)
{
    Interpolators output = (Interpolators)0;
    VertexPositionInputs vpInputs = GetVertexPositionInputs(input.positionOS.xyz);
    // 当前帧非抖动位置（[Part5-七] 模块2：当前M + 非抖动VP）
    output.positionCSNoJitter = mul(_NonJitteredViewProjMatrix, mul(UNITY_MATRIX_M, input.positionOS));

    // 上一帧位置（上一帧M + 上一帧VP）
    float4 prevPos = input.positionOS;
    output.previousPositionCSNoJitter = mul(_PrevViewProjMatrix, mul(UNITY_PREV_MATRIX_M, prevPos));

    // 防运动向量纹理缝隙（[Part5-七] 模块3）
    output.positionCS = vpInputs.positionCS;
    ApplyMotionVectorZBias(output.positionCS);

    #ifdef _ALPHA_CUTOUT
    output.uv = TRANSFORM_TEX(input.uv, _ColorMap);
    #endif

    return output;
}

float4 Fragment(Interpolators input) : SV_TARGET
{
    #ifdef _ALPHA_CUTOUT
    float4 colorSample = SAMPLE_TEXTURE2D(_ColorMap, sampler_ColorMap, input.uv);
    colorSample.a = CalculateDotMatrix(input.uv, _DotDensity, _DotRadius, float2(_DotScaleX, _DotScaleY));
    TestAlphaClip(colorSample);
    #endif

    // CalcNdcMotionVectorFromCsPositions 来自 MotionVectorsCommon.hlsl
    float2 velocity = CalcNdcMotionVectorFromCsPositions(input.positionCSNoJitter, input.previousPositionCSNoJitter);
    return float4(velocity, 0, 0);
}
#endif