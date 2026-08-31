// 本文件包含前向光照通道的顶点和片段函数
// 这是通过读取材质、光照、阴影等数据来计算材质可见颜色的着色器通道
#ifndef MY_LIT_FORWARD_LIT_PASS_INCLUDED
#define MY_LIT_FORWARD_LIT_PASS_INCLUDED
// 引入URP库函数和我们自己的通用函数
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/ParallaxMapping.hlsl"
#include "MyLitCommon.hlsl"
// 此属性结构体接收当前渲染网格的相关数据
// 数据会根据语义自动填充到对应字段中
struct Attributes {
    float3 positionOS : POSITION; // 对象空间中的位置
    float3 normalOS : NORMAL;
    float4 tangentOS : TANGENT;
    float2 uv : TEXCOORD0; // 材质贴图uv
};

// 此结构体由顶点函数输出，并作为片段函数的输入
// 注意：字段将被中间的光栅化阶段进行变换
struct Interpolators {
    // 该值从顶点函数输出时应包含裁剪空间中的位置（类似于屏幕上的位置）
    // 当从片段函数读取时，它将被转换为当前片段在屏幕上的像素位置
    float4 positionCS : SV_POSITION;
    float2 uv : TEXCOORD0;
    float3 positionWS : TEXCOORD1;
    float3 normalWS : TEXCOORD2;
    #ifdef _NORMALMAP
    float4 tangentWS : TEXCOORD3;
    #endif
};

// #ifndef MY_LIT_COMMON_INCLUDED
// // "#ifndef MY_LIT_COMMON_INCLUDED" is equivalent to "#if !defined(MY_LIT_COMMON_INCLUDED)"
// #define MY_LIT_COMMON_INCLUDED
// // 用 CBUFFER 包裹材质属性 为了兼容 SRP Batcher（不然动态合批会有问题）
// CBUFFER_START(UnityPerMaterial)
// float4 _ColorTint;
// float4 _ColorMap_ST; // 这是Unity自动设置的，供TRANSFORM_TEX使用来应用UV平铺
// float _Smoothness;
// float _Cutoff; // 让给GPU接收到透明度裁切阈值的滑条值
// CBUFFER_END
// // Textures
// TEXTURE2D(_ColorMap); SAMPLER(sampler_ColorMap); // RGB = albedo, A = alpha
// #endif


// 顶点函数。对网格上的每个顶点运行一次。
// 必须输出每个顶点在屏幕上应出现的位置，以及片段函数所需的任何数据
Interpolators Vertex(Attributes input) {
    Interpolators output;

    // 这些辅助函数位于 URP/ShaderLib/ShaderVariablesFunctions.hlsl 中
    // 用于将对象空间的值转换为世界空间和裁剪空间
    VertexPositionInputs posnInputs = GetVertexPositionInputs(input.positionOS);
    // 将法线向量从对象空间变换到世界空间
    VertexNormalInputs normInput = GetVertexNormalInputs(input.normalOS);

    // 将位置和方向数据传递给片段函数
    output.positionCS = posnInputs.positionCS;
    // 顶点函数里使用采样器采样uv
    output.uv = TRANSFORM_TEX(input.uv, _ColorMap);
    output.normalWS = normInput.normalWS;
    #ifdef _NORMALMAP
    output.tangentWS = float4(normInput.tangentWS, input.tangentOS.w);
    #endif
    output.positionWS = posnInputs.positionWS;

    return output;
}
// 已经移动到MyLitCommon.hlsl
// void TestAlphaClip(float4 colorSample){
//     #ifdef _ALPHA_CUTOUT
//     clip(colorSample.a * _ColorTint.a - _Cutoff);
// #endif
// }
// 片段函数。对每个片段（可理解为屏幕上的一个像素）运行一次
// 必须输出该像素的最终颜色
float4 Fragment(Interpolators input
    // 好刁钻的写法
    #ifdef _DOUBLE_SIDED_NORMALS
    , FRONT_FACE_TYPE frontFace : FRONT_FACE_SEMANTIC
    #endif
    ) : SV_TARGET {
    // 重排代码
    float3 normalWS = normalize(input.normalWS);
    #ifdef _DOUBLE_SIDED_NORMALS
    normalWS *= IS_FRONT_VFACE(frontFace, 1, -1);
    #endif
    // 重排代码，法线和视线方向在任何纹理采样之前计算，我们需要根据这些值计算新UV
    // 过程中使用这些 positionWS 和 viewDirectionWS 变量，转化后再传入input内
    // 这里就是把变量转移出来用
    float3 positionWS = input.positionWS;
    float3 viewDirWS = GetWorldSpaceNormalizeViewDir(input.positionWS); // In ShaderVariablesFunctions.hlsl
    #ifdef _NORMALMAP
    float3 viewDirTS = GetViewDirectionTangentSpace(input.tangentWS, normalWS, viewDirWS); // In ParallaxMapping.hlsl
    #endif
    float2 uv = input.uv; // 拿出uv
    // return float4(uv, 0, 1); // uv可视化
    #ifdef _NORMALMAP
    // 对uv进行偏移采样
    uv += ParallaxMapping(TEXTURE2D_ARGS(_ParallaxMap, sampler_ParallaxMap), viewDirTS, _ParallaxStrength, uv);
    #endif
    // 颜色映射样例
    float4 colorSample = SAMPLE_TEXTURE2D(_ColorMap, sampler_ColorMap, uv) * _ColorTint;
    // 括号内的值小于0，直接把这个像素丢弃
    // clip(colorSample.a * _ColorTint.a - 0.5);
    TestAlphaClip(colorSample);

// 这里一直在写宏，看上去像是在优化性能
#ifdef _NORMALMAP
    float3 normalTS = UnpackNormalScale(SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, uv), _NormalStrength);
    // tangentToWorld 必须在守卫外计算，否则渲染调试器的 "Lighting Without Normal Maps" 模式会出错
    float3x3 tangentToWorld = CreateTangentToWorld(normalWS, input.tangentWS.xyz, input.tangentWS.w);
    normalWS = normalize(TransformTangentToWorld(normalTS, tangentToWorld));
#else
    float3 normalTS = float3(0, 0, 1); // 默认平法线，_NORMALMAP 未启用时给调试器兜底
    float3x3 tangentToWorld = float3x3(1,0,0, 0,1,0, 0,0,1);
    normalWS = normalize(normalWS);
#endif

    // return float4(normalWS * 0.5 + 0.5, 1);  // 测试法线贴图，旋转模型法线应跟着走
    // return float4((normalWS + 1) * 0.5, 1); // 向量重映射
    InputData lightingInput = (InputData)0;
    lightingInput.positionWS = input.positionWS;
    // 设置世界空间法线，数据是走Interpolators来的，input接应了这个结构体
    // lightingInput.normalWS = normalize(input.normalWS) * IS_FRONT_VFACE(frontFace, 1, -1);
    // 守卫关键字会处理好条件翻转，这里直接传值就好了
    lightingInput.normalWS = normalWS; // 之前干啥了：拿到viewDirWS给GetViewDirectionTangentSpace使用
    lightingInput.viewDirectionWS = viewDirWS; // 之前干啥了：拿到viewDirTS用于UV偏移采样
    lightingInput.shadowCoord = TransformWorldToShadowCoord(input.positionWS);
#if UNITY_VERSION >= 202120
    lightingInput.positionCS = input.positionCS;
    // 调试法线贴图，会在渲染调试器中输出额外视图
    lightingInput.tangentToWorld = tangentToWorld; // 提供转换矩阵
#endif

    // -------程序化点阵镂空-------
    colorSample.a = CalculateDotMatrix(input.uv, _DotDensity, _DotRadius, float2(_DotScaleX, _DotScaleY));

    SurfaceData surfaceInput = (SurfaceData)0;
    surfaceInput.albedo = colorSample.rgb; //  * _ColorTint.rgb; // 98行已经乘过了
    surfaceInput.alpha = colorSample.a * _ColorTint.a;
    #ifdef _SPECULAR_SETUP
    surfaceInput.specular = SAMPLE_TEXTURE2D(_SpecularMap, sampler_SpecularMap, uv).rgb * _SpecularTint;
    surfaceInput.metallic = 0;
    #else
    surfaceInput.specular = 1;
    surfaceInput.metallic = SAMPLE_TEXTURE2D(_MetalnessMask, sampler_MetalnessMask, uv).r * _Metalness;
    #endif

    // 适配粗糙度roughness贴图（平滑度的反值）
    float smoothnessSample = SAMPLE_TEXTURE2D(_SmoothnessMask, sampler_SmoothnessMask, uv).r; // * _Smoothness; // 第三回合，适配粗糙度模式，现在这个单拿出来后面乘
    #ifdef _ROUGHNESS_SETUP
    surfaceInput.smoothness = 1 - smoothnessSample; // 粗糙度模式：贴图白=粗糙，黑=光滑
    #else
    surfaceInput.smoothness = smoothnessSample * _Smoothness; // 平滑度模式：滑条控制强度
    #endif
    // 拿到守卫关键字里面去处理了，适配平滑度模式
    // surfaceInput.smoothness = smoothnessSample;
    // surfaceInput.metallic = _Metalness;  // 这个值已经在采样时乘过去了，不需要再单独赋值了
    // surfaceInput.smoothness = _Smoothness; // 同上
    surfaceInput.emission = SAMPLE_TEXTURE2D(_EmissionMap, sampler_EmissionMap, uv).rgb * _EmissionTint;
#ifdef _CLEARCOATMAP
    surfaceInput.clearCoatMask = SAMPLE_TEXTURE2D(_ClearCoatMask, sampler_ClearCoatMask, uv).r * _ClearCoatStrength;
    surfaceInput.clearCoatSmoothness = SAMPLE_TEXTURE2D(_ClearCoatSmoothnessMask, sampler_ClearCoatSmoothnessMask, uv).r * _ClearCoatSmoothness;
#endif
    // 调试钩子，给 Unity 内部调试工具“喂数据”，不影响眼前的光照颜色
    surfaceInput.normalTS = normalTS; // 提供原始切线法线
    // 现在切PBR了，这里不需要了  最后再乘个色调
// #if UNITY_VERSION >= 202120
//     return UniversalFragmentBlinnPhong(lightingInput, surfaceInput);
// #else
//     return UniversalFragmentBlinnPhong(lightingInput, surfaceInput.albedo, float4(surfaceInput.specular, 1), surfaceInput.smoothness, 0, surfaceInput.alpha );
// #endif

    return UniversalFragmentPBR(lightingInput, surfaceInput);
}


#endif