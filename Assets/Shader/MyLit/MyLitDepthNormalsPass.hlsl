#ifndef MY_LIT_DEPTH_NORMALS_PASS_INCLUDED
#define MY_LIT_DEPTH_NORMALS_PASS_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "MyLitCommon.hlsl"

struct Attributes
{
    float4 positionOS : POSITION;
    float3 normalOS : NORMAL;
    float4 tangentOS : TANGENT;
    float2 uv : TEXCOORD0;
};

struct Varyings{
    float4 positionCS : SV_POSITION;
    float2 uv : TEXCOORD0;
    float3 normalWS : TEXCOORD1;
#ifdef _NORMALMAP
    float4 tangentWS : TEXCOORD2;
#endif
};


Varyings DepthNormalsVertex(Attributes input){
    Varyings output = (Varyings)0;

    VertexNormalInputs normalInput = GetVertexNormalInputs(input.normalOS, input.tangentOS);

    output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
    output.uv = TRANSFORM_TEX(input.uv, _ColorMap);
    output.normalWS = normalInput.normalWS;

    #ifdef _NORMALMAP
        // GetOddNegativeScale处理负缩放翻转，不能省
        real sign = input.tangentOS.w * GetOddNegativeScale();
        output.tangentWS = half4(normalInput.tangentWS.xyz, sign);
    #endif

    return output;
}

half4 DepthNormalsFragment(Varyings input) : SV_TARGET{
    #ifdef _NORMALMAP
        half3 normalTS = UnpackNormalScale(
            SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, input.uv),
            _NormalStrength);

        // 注意这里顺序是 tangent/bitangent/normal
        half sgn = input.tangentWS.w;
        half3 bitangent = sgn * cross(input.normalWS.xyz, input.tangentWS.xyz);
        half3 normalWS = TransformTangentToWorld(
            normalTS, 
            half3x3(input.tangentWS.xyz, bitangent, input.normalWS.xyz));
    #else
        half3 normalWS = input.normalWS;
    #endif

    #ifdef _ALPHA_CUTOUT
        half alpha = CalculateDotMatrix(input.uv, _DotDensity, _DotRadius,
                                        float2(_DotScaleX, _DotScaleY));
        clip(alpha - _Cutoff);
    #endif
    // 发现必须归一化，否则SSAO会出现错误遮挡
    return half4(NormalizeNormalPerPixel(normalWS), 0.0);
}
#endif