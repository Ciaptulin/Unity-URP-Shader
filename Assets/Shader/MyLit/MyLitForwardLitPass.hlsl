// 本文件包含前向光照通道的顶点和片段函数
// 通过读取材质、光照、阴影等数据来计算材质可见颜色
// 主体对应教程 Part2 → Part5
#ifndef MY_LIT_FORWARD_LIT_PASS_INCLUDED
#define MY_LIT_FORWARD_LIT_PASS_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/ParallaxMapping.hlsl"
#include "MyLitCommon.hlsl"

// 顶点着色器输入：接收当前渲染网格的数据，由语义自动填充
struct Attributes
{
    float3 positionOS : POSITION;   // 对象空间位置
    float3 normalOS : NORMAL;
    float4 tangentOS : TANGENT;
    float2 uv : TEXCOORD0;          // 材质贴图 UV
    float2 uv2 : TEXCOORD1;         // 光照贴图 UV [Part5-二]
};

// 顶点着色器输出，经光栅化插值后作为片元着色器输入
struct Interpolators
{
    // 顶点阶段输出裁剪空间位置，片元阶段读取为屏幕像素位置
    float4 positionCS : SV_POSITION;
    float2 uv : TEXCOORD0;
    float2 uv2 : TEXCOORD1;
    float3 positionWS : TEXCOORD2;
    float3 normalWS : TEXCOORD3;
    float4 tangentWS : TEXCOORD4;
    half vertexSH : TEXCOORD5;      // 无光照贴图时用球谐函数兜底 [Part5-二]
};

// 顶点函数。对网格上的每个顶点运行一次。
// 必须输出顶点在屏幕上的位置，以及片段函数所需的任何数据
Interpolators Vertex(Attributes input)
{
    Interpolators output;

    // 这些辅助函数位于 URP/ShaderLib/ShaderVariablesFunctions.hlsl
    // 用于将对象空间的值转换到世界空间和裁剪空间
    VertexPositionInputs posInputs = GetVertexPositionInputs(input.positionOS);
    VertexNormalInputs normInputs = GetVertexNormalInputs(input.normalOS);

    // 将位置和方向数据传递给片段函数
    output.positionCS = posInputs.positionCS;
    output.uv = TRANSFORM_TEX(input.uv, _ColorMap);
    // 宏定义在 Lighting.hlsl 里 [Part5-二]
    OUTPUT_LIGHTMAP_UV(input.uv2, unity_LightmapST, output.uv2);
    output.normalWS = normInputs.normalWS;
    output.tangentWS = float4(normInputs.tangentWS, input.tangentOS.w);
    output.positionWS = posInputs.positionWS;

    // 没有 LIGHTMAP_ON 时（光照探针/lightmap 被剥离）靠 SH 提供间接光 [Part5-二]
    output.vertexSH = SampleSHVertex(normInputs.normalWS);

    return output;
}

// 片段函数。对每个片段（屏幕上的一个像素）运行一次，输出最终颜色
float4 Fragment(Interpolators input
    // 双面渲染时接收面朝向
    #ifdef _DOUBLE_SIDED_NORMALS
    , FRONT_FACE_TYPE frontFace : FRONT_FACE_SEMANTIC
    #endif
    ) : SV_TARGET
{
    // ===== [Part3] 法线准备 =====
    float3 normalWS = normalize(input.normalWS);
    #ifdef _DOUBLE_SIDED_NORMALS
    normalWS *= IS_FRONT_VFACE(frontFace, 1, -1);
    #endif

    // ===== [Part4] 视差：先算法线与视线方向，再偏移 uv =====
    float3 viewDirWS = GetWorldSpaceNormalizeViewDir(input.positionWS);                      // In ShaderVariablesFunctions.hlsl
    float3 viewDirTS = GetViewDirectionTangentSpace(input.tangentWS, normalWS, viewDirWS);   // In ParallaxMapping.hlsl

    float2 uv = input.uv;
    uv += ParallaxMapping(TEXTURE2D_ARGS(_ParallaxMap, sampler_ParallaxMap), viewDirTS, _ParallaxStrength, uv);

    // ===== [Part4] 颜色采样 + 程序化点阵镂空 + Alpha 裁切 =====
    float4 colorSample = SAMPLE_TEXTURE2D(_ColorMap, sampler_ColorMap, uv) * _ColorTint;

    // 用偏移后的 uv 生成点阵，覆盖纹理 alpha
    colorSample.a = CalculateDotMatrix(uv, _DotDensity, _DotRadius,
                                        float2(_DotScaleX, _DotScaleY));

    TestAlphaClip(colorSample);

    // ===== [Part3] 法线贴图（切线空间 → 世界空间）=====
#ifdef _NORMALMAP
    float3 normalTS = UnpackNormalScale(SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, uv), _NormalStrength);
    // tangentToWorld 必须在守卫外计算，否则渲染调试器的 "Lighting Without Normal Maps" 模式会出错
    float3x3 tangentToWorld = CreateTangentToWorld(normalWS, input.tangentWS.xyz, input.tangentWS.w);
    normalWS = normalize(TransformTangentToWorld(normalTS, tangentToWorld));
#else
    float3 normalTS = float3(0, 0, 1);  // 默认平法线，_NORMALMAP 未启用时给调试器兜底
    float3x3 tangentToWorld = float3x3(1, 0, 0, 0, 1, 0, 0, 0, 1);
    normalWS = normalize(normalWS);
#endif

    // ===== [Part5] 填充 lightingInput =====
    InputData lightingInput = (InputData)0;
    lightingInput.positionWS = input.positionWS;
    lightingInput.normalWS = normalWS;
    lightingInput.viewDirectionWS = viewDirWS;
    lightingInput.shadowCoord = TransformWorldToShadowCoord(input.positionWS);
    // normalizedScreenSpaceUV = (0,0) 会导致 SSAO 采样错误，把环境反射乘没
    lightingInput.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(input.positionCS);
    lightingInput.shadowMask = half4(1.0, 1.0, 1.0, 1.0);
#if UNITY_VERSION >= 202120
    lightingInput.positionCS = input.positionCS;
    lightingInput.tangentToWorld = tangentToWorld;  // 渲染调试器需要，用于输出额外视图
#endif

    // ===== [Part5-二] 烘焙 GI：lightmap 或 SH 兜底 =====
    // SampleLightmap 在 LIGHTMAP_ON 未定义时直接返回 0，
    // 会让使用光照探针的对象整体变黑，所以这里补了 SH 兜底
#ifdef LIGHTMAP_ON
    lightingInput.bakedGI = SampleLightmap(input.uv2, normalWS);
#else
    lightingInput.bakedGI = SampleSHPixel(input.vertexSH, normalWS);
#endif

    // 调试：输出烘焙 GI 为灰度
    #ifdef _DEBUG_BAKED_GI
        return float4(lightingInput.bakedGI, 1);
    #endif

    // ===== [Part3/4/5] 填充 SurfaceData =====
    SurfaceData surfaceInput = (SurfaceData)0;
    surfaceInput.albedo = colorSample.rgb;
    surfaceInput.alpha = colorSample.a * _ColorTint.a;

    #ifdef _SPECULAR_SETUP
    // 高光工作流 [Part3]
    surfaceInput.specular = SAMPLE_TEXTURE2D(_SpecularMap, sampler_SpecularMap, uv).rgb * _SpecularTint;
    surfaceInput.metallic = 0;
    #else
    // 金属度工作流（默认）[Part3]
    surfaceInput.specular = 1;
    surfaceInput.metallic = SAMPLE_TEXTURE2D(_MetalnessMask, sampler_MetalnessMask, uv).r * _Metalness;
    #endif

    // 平滑度 / 粗糙度 [Part3]
    float smoothnessSample = SAMPLE_TEXTURE2D(_SmoothnessMask, sampler_SmoothnessMask, uv).r;
    #ifdef _ROUGHNESS_SETUP
    surfaceInput.smoothness = 1 - smoothnessSample;         // 粗糙度模式：贴图白 = 粗糙，黑 = 光滑
    #else
    surfaceInput.smoothness = smoothnessSample * _Smoothness;  // 平滑度模式：滑条控制强度
    #endif

    // 自发光 [Part4]
    surfaceInput.emission = SAMPLE_TEXTURE2D(_EmissionMap, sampler_EmissionMap, uv).rgb * _EmissionTint;

    // 遮挡贴图（URP 惯例用 G 通道）[Part5-三]
#ifdef _OCCLUSIONMAP
    surfaceInput.occlusion = SAMPLE_TEXTURE2D(_OcclusionMap, sampler_OcclusionMap, uv).g * _OcclusionStrength;
#else
    surfaceInput.occlusion = 1.0;
#endif

    // 清漆 [Part4]
    #ifdef _CLEARCOATMAP
    surfaceInput.clearCoatMask = SAMPLE_TEXTURE2D(_ClearCoatMask, sampler_ClearCoatMask, uv).r * _ClearCoatStrength;
    surfaceInput.clearCoatSmoothness = SAMPLE_TEXTURE2D(_ClearCoatSmoothnessMask, sampler_ClearCoatSmoothnessMask, uv).r * _ClearCoatSmoothness;
    #endif

    // 给 Unity 内部调试工具喂原始切线法线，不影响最终颜色
    surfaceInput.normalTS = normalTS;

    // ===== PBR 出最终颜色 =====
    return UniversalFragmentPBR(lightingInput, surfaceInput);
}

#endif

// ==================== 调试片段（需要时临时挪到 Fragment 里）====================
// uv 可视化：      return float4(uv, 0, 1);
// 法线可视化：     return float4(normalWS * 0.5 + 0.5, 1);
// 向量重映射：     return float4((normalWS + 1) * 0.5, 1);
// 烘焙 GI 灰度：   return float4(lightingInput.bakedGI, 1);
// 查看 AO：        return half4(surfaceInput.occlusion.xxx, 1);
// ==========================================================================
