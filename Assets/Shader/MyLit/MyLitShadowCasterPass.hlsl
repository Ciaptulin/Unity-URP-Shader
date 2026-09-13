// ===== [Part2] 阴影投射通道（含 Alpha 裁切镂空）=====
#ifndef MY_LIT_SHADOW_CASTER_PASS_INCLUDED
#define MY_LIT_SHADOW_CASTER_PASS_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
#include "MyLitCommon.hlsl"

struct Attributes
{
    float3 positionOS : POSITION;
    float3 normalOS : NORMAL;
    #ifdef _ALPHA_CUTOUT  // 字段已经在 MyLit.shader 中注册
    float2 uv : TEXCOORD0;
    #endif
};

struct Interpolators
{
    float4 positionCS : SV_POSITION;
    #ifdef _ALPHA_CUTOUT
    float2 uv : TEXCOORD0;
    float3 positionWS : TEXCOORD1;
    #endif
};

// 用视线方向点积翻转法线
float3 FlipNormalBaseOnViewDir(float3 normalWS, float3 positionWS)
{
    float3 viewDirWS = GetWorldSpaceNormalizeViewDir(positionWS);
    return normalWS * (dot(normalWS, viewDirWS) < 0 ? -1 : 1);
}

// CBUFFER 包裹，兼容 SRP Batcher。注意这里是 UnityPerFrame
CBUFFER_START(UnityPerFrame)
float3 _LightDirection;
CBUFFER_END

// 调用 ApplyShadowBias 施加偏移，再转裁剪空间，最后做深度钳制
float4 GetShadowCasterPositionCS(float3 positionWS, float3 normalWS)
{
    float3 lightDirectionWS = _LightDirection;
#ifdef _DOUBLE_SIDED_NORMALS
    normalWS = FlipNormalBaseOnViewDir(normalWS, positionWS);
#endif

    float4 positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, lightDirectionWS));

    // 处理 DirectX / OpenGL 对深度缓冲区存储方式的差异
    #if UNITY_REVERSED_Z
    positionCS.z = min(positionCS.z, UNITY_NEAR_CLIP_VALUE);
    #else
    positionCS.z = max(positionCS.z, UNITY_NEAR_CLIP_VALUE);
    #endif
    return positionCS;
}

Interpolators Vertex(Attributes input)
{
    Interpolators output;

    VertexPositionInputs posInputs = GetVertexPositionInputs(input.positionOS);
    // 把模型空间的法线转到世界空间
    VertexNormalInputs normInputs = GetVertexNormalInputs(input.normalOS);
    // 接收世界空间的位置和法线，输出最终用于渲染阴影的裁剪空间坐标
    output.positionCS = GetShadowCasterPositionCS(posInputs.positionWS, normInputs.normalWS);
    #ifdef _ALPHA_CUTOUT
    output.uv = TRANSFORM_TEX(input.uv, _ColorMap);
    output.positionWS = posInputs.positionWS;
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
    return 0;
}

#endif
