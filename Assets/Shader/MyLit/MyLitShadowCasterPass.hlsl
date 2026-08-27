#ifndef MY_LIT_SHADOW_CASTER_PASS_INCLUDED
#define MY_LIT_SHADOW_CASTER_PASS_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
#include "MyLitCommon.hlsl"

struct Attributes {
    float3 positionOS : POSITION;
    float3 normalOS : NORMAL;
    #ifdef _ALPHA_CUTOUT  // 字段已经在MyLit中注册
    float2 uv : TEXCOORD0;
    #endif
};

struct Interpolators{
    float4 positionCS : SV_POSITION;
    #ifdef _ALPHA_CUTOUT
    float2 uv : TEXCOORD0;
    float3 positionWS : TEXCOORD1;  // 传递世界坐标
    #endif

};
// 使用点积翻转法线
float3 FlipNormalBaseOnViewDir(float3 normalWS, float3 positionWS){
    float3 viewDirWS = GetWorldSpaceNormalizeViewDir(positionWS);
    return normalWS * (dot(normalWS, viewDirWS) < 0 ? -1 : 1);
}

// 用 CBUFFER 包裹材质属性 为了兼容 SRP Batcher（不然动态合批会有问题）
CBUFFER_START(UnityPerFrame) // 注意这里改成 UnityPerFrame
float3 _LightDirection;
CBUFFER_END


// 调用ApplyShadowBias施加偏移，调用TransformWorldToHClip转成裁剪空间坐标，最后进行深度钳制（Clamp）
float4 GetShadowCasterPositionCS(float3 positionWS, float3 normalWS){
    float3 lightDirectionWS = _LightDirection;
#ifdef _DOUBLE_SIDED_NORMALS
    normalWS = FlipNormalBaseOnViewDir(normalWS, positionWS);
#endif

    float4 positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, lightDirectionWS));

    // 图形API（DirectX vs OpenGL）对深度缓冲区（Depth Buffer）存储方式的规范差异
    #if UNITY_REVERSED_Z
    positionCS.z = min(positionCS.z, UNITY_NEAR_CLIP_VALUE);
#else
    positionCS.z = max(positionCS.z, UNITY_NEAR_CLIP_VALUE);
#endif 
    return positionCS;
}

Interpolators Vertex(Attributes input){
    Interpolators output;

    VertexPositionInputs posnInputs = GetVertexPositionInputs(input.positionOS);
    // 把模型空间（Object Space）下的法线，转换成世界空间（World Space）下的法线
    VertexNormalInputs normInputs = GetVertexNormalInputs(input.normalOS);
    // 接收“世界空间的位置和法线”，输出“最终用于渲染阴影的裁剪空间坐标（Clip Space）
    output.positionCS = GetShadowCasterPositionCS(posnInputs.positionWS, normInputs.normalWS);
    // _ALPHA_CUTOUT 定义时,将UV传递到输出结构体
    #ifdef _ALPHA_CUTOUT
    output.uv = TRANSFORM_TEX(input.uv, _ColorMap);
    output.positionWS = posnInputs.positionWS;
    #endif
    return output;
}

float4 Fragment(Interpolators input) : SV_TARGET{
    // 颜色纹理并调用 TestAlphaClip
    #ifdef _ALPHA_CUTOUT
    float2 uv = input.uv;
    float4 colorSample = SAMPLE_TEXTURE2D(_ColorMap, sampler_ColorMap, uv);
    colorSample.a = CalculateDotMatrix(input.uv, _DotDensity, _DotRadius, float2(_DotScaleX, _DotScaleY));

    TestAlphaClip(colorSample);
    #endif
    return 0;
}

#endif