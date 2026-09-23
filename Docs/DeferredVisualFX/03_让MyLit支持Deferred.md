# 03 · 让 MyLit 支持 Deferred

> 目标：给现有 MyLit 加一个 `UniversalGBuffer` Pass，使它在 URP Deferred 下也能渲染。
> 说明：本章是**教程性质**，给出"如果要改，应该这样写"。**不实际改动你现有代码。**

---

## 3.1 现状：MyLit 只有 Forward

当前 `MyLit.shader` 的 6 个 Pass 里，光照主体是 `ForwardLit`（`UniversalForward`）。

切到 URP Deferred 后：

- 不透明物体**不再走** `UniversalForward`
- URP 找的是 `UniversalGBuffer` 这个 LightMode
- 没这个 Pass 的 shader → 物体消失

---

## 3.2 需要新增什么

一个 `UniversalGBuffer` Pass，把 MyLit 的表面属性写进 URP 的 4 张 GBuffer：

```
GBuffer0 ← albedo.rgb + occlusion
GBuffer1 ← specular.rgb + smoothness
GBuffer2 ← normalWS (0~1 编码)
GBuffer3 ← emission + bakedGI
```

---

## 3.3 新建 MyLitGBufferPass.hlsl

放在 `Assets/Shader/MyLit/` 下：

```hlsl
// ===== [Deferred] GBuffer 通道（URP Deferred 路径用）=====
#ifndef MY_LIT_GBUFFER_PASS_INCLUDED
#define MY_LIT_GBUFFER_PASS_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/ParallaxMapping.hlsl"
#include "MyLitCommon.hlsl"

struct Attributes
{
    float3 positionOS : POSITION;
    float3 normalOS : NORMAL;
    float4 tangentOS : TANGENT;
    float2 uv : TEXCOORD0;
    float2 uv2 : TEXCOORD1;   // 光照贴图 UV
};

struct Interpolators
{
    float4 positionCS : SV_POSITION;
    float2 uv : TEXCOORD0;
    float2 uv2 : TEXCOORD1;
    float3 positionWS : TEXCOORD2;
    float3 normalWS : TEXCOORD3;
    float4 tangentWS : TEXCOORD4;
    half vertexSH : TEXCOORD5;
};

Interpolators Vertex(Attributes input)
{
    Interpolators output;

    VertexPositionInputs posInputs = GetVertexPositionInputs(input.positionOS);
    VertexNormalInputs normInputs = GetVertexNormalInputs(input.normalOS);

    output.positionCS = posInputs.positionCS;
    output.uv = TRANSFORM_TEX(input.uv, _ColorMap);
    OUTPUT_LIGHTMAP_UV(input.uv2, unity_LightmapST, output.uv2);
    output.normalWS = normInputs.normalWS;
    output.tangentWS = float4(normInputs.tangentWS, input.tangentOS.w);
    output.positionWS = posInputs.positionWS;
    output.vertexSH = SampleSHVertex(normInputs.normalWS);

    return output;
}

// 写 4 张 GBuffer
void Fragment(Interpolators input,
    out half4 gBuffer0 : SV_Target0,   // albedo + occlusion
    out half4 gBuffer1 : SV_Target1,   // specular + smoothness
    out half4 gBuffer2 : SV_Target2,   // normal
    out half4 gBuffer3 : SV_Target3)   // emission + GI
{
    // ===== 法线准备（与 ForwardLit 一致）=====
    float3 normalWS = normalize(input.normalWS);

    // ===== 视差 =====
    float3 viewDirWS = GetWorldSpaceNormalizeViewDir(input.positionWS);
    float3 viewDirTS = GetViewDirectionTangentSpace(input.tangentWS, normalWS, viewDirWS);
    float2 uv = input.uv;
    uv += ParallaxMapping(TEXTURE2D_ARGS(_ParallaxMap, sampler_ParallaxMap),
                          viewDirTS, _ParallaxStrength, uv);

    // ===== 颜色 + 镂空 =====
    float4 colorSample = SAMPLE_TEXTURE2D(_ColorMap, sampler_ColorMap, uv) * _ColorTint;
    colorSample.a = CalculateDotMatrix(uv, _DotDensity, _DotRadius,
                                        float2(_DotScaleX, _DotScaleY));
    TestAlphaClip(colorSample);

    // ===== 法线贴图 =====
    #ifdef _NORMALMAP
        float3 normalTS = UnpackNormalScale(
            SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, uv), _NormalStrength);
        float3x3 tangentToWorld = CreateTangentToWorld(
            normalWS, input.tangentWS.xyz, input.tangentWS.w);
        normalWS = normalize(TransformTangentToWorld(normalTS, tangentToWorld));
    #endif

    // ===== 金属/高光工作流 =====
    half metallic;
    half3 specular;
    #ifdef _SPECULAR_SETUP
        specular = SAMPLE_TEXTURE2D(_SpecularMap, sampler_SpecularMap, uv).rgb * _SpecularTint.rgb;
        metallic = 0;
    #else
        specular = half3(1, 1, 1);   // 占位，稍后转换
        metallic = SAMPLE_TEXTURE2D(_MetalnessMask, sampler_MetalnessMask, uv).r * _Metalness;
    #endif

    // ===== 平滑度 =====
    half smoothnessSample = SAMPLE_TEXTURE2D(_SmoothnessMask, sampler_SmoothnessMask, uv).r;
    half smoothness;
    #ifdef _ROUGHNESS_SETUP
        smoothness = 1 - smoothnessSample;
    #else
        smoothness = smoothnessSample * _Smoothness;
    #endif

    // ===== 金属度 → 高光（URP GBuffer 用高光工作流）=====
    #ifndef _SPECULAR_SETUP
        // 介电质基础反射率
        const half3 kDielectricSpec = half3(0.04, 0.04, 0.04);
        specular = lerp(kDielectricSpec, colorSample.rgb, metallic);
    #endif

    // ===== 自发光 + AO =====
    half3 emission = SAMPLE_TEXTURE2D(_EmissionMap, sampler_EmissionMap, uv).rgb * _EmissionTint.rgb;
    half occlusion = 1.0;
    #ifdef _OCCLUSIONMAP
        occlusion = SAMPLE_TEXTURE2D(_OcclusionMap, sampler_OcclusionMap, uv).g * _OcclusionStrength;
    #endif

    // ===== 烘焙 GI =====
    half3 bakedGI;
    #ifdef LIGHTMAP_ON
        bakedGI = SampleLightmap(input.uv2, normalWS);
    #else
        bakedGI = SampleSHPixel(input.vertexSH, normalWS);
    #endif

    // ===== 写 GBuffer =====
    gBuffer0 = half4(colorSample.rgb, occlusion);
    gBuffer1 = half4(specular, smoothness);
    gBuffer2 = half4(normalWS * 0.5 + 0.5, 0);   // 0~1 编码
    gBuffer3 = half4(emission + bakedGI, 0);
}

#endif
```

---

## 3.4 在 MyLit.shader 里加 Pass

在 `SubShader` 里，`ForwardLit` Pass **之前**插入：

```hlsl
// ===== Pass 0: GBuffer（Deferred 路径）=====
Pass
{
    Name "GBuffer"
    Tags { "LightMode" = "UniversalGBuffer" }

    // 关掉默认的 forward 光照
    ZWrite On
    Cull [_Cull]

    HLSLPROGRAM
    #pragma exclude_renderers gles gles3 glcore
    #pragma target 4.5

    // 与 ForwardLit 一致的关键字
    #pragma shader_feature_local_fragment _NORMALMAP
    #pragma shader_feature_local _ALPHA_CUTOUT
    #pragma shader_feature_local _DOUBLE_SIDED_NORMALS
    #pragma shader_feature_local_fragment _SPECULAR_SETUP
    #pragma shader_feature_local_fragment _ROUGHNESS_SETUP
    #pragma shader_feature_local_fragment _EMISSION
    #pragma shader_feature_local_fragment _OCCLUSIONMAP

    // Unity 内置
    #pragma multi_compile _ LIGHTMAP_ON
    #pragma multi_compile _ DIRLIGHTMAP_COMBINED
    #pragma multi_compile _ DYNAMICLIGHTMAP_ON
    #pragma multi_compile _ LIGHTMAP_SHADOW_MIXING
    #pragma multi_compile _ SHADOWS_SHADOWMASK

    #pragma vertex Vertex
    #pragma fragment Fragment

    #include "MyLitGBufferPass.hlsl"
    ENDHLSL
}
```

**要点**：

- `LightMode = "UniversalGBuffer"` 是 URP 识别的关键字
- 关键字集要跟 ForwardLit 对齐，否则镂空/法线表现不一致
- `_DOUBLE_SIDED_NORMALS` 在 GBuffer 里也要处理（翻转法线）

---

## 3.5 光照谁来算

**关键**：加了 GBuffer Pass 后，**光照由 URP 内部完成**，你**不需要**写 LightingPass。

URP 会在所有物体写完 GBuffer 后，跑它自己的延迟光照（Deferred Lighting），光照函数是 URP 内置的 `UniversalFragmentPBR` 等价物。

**这就是 URP 与参考项目最大的不同**——参考项目要自己写 LightingPass，URP 帮你做了。

---

## 3.6 透明怎么办

透明物体在 Deferred 下会回退到 **Forward**：

- URP 自动把透明队列的物体走 `UniversalForward`
- 所以 MyLit 的 `ForwardLit` Pass **要保留**（不能只留 GBuffer）

---

## 3.7 验证

如果真做了：

1. URP Asset → Rendering Path 设为 **Deferred**
2. 用 MyLit 材质的物体应正常显示（走 GBuffer + URP 延迟光照）
3. Frame Debugger 里看到 `UniversalGBuffer` Pass 被调用
4. 与 Forward 对比，不透明部分光照应一致

---

## 3.8 常见坑

- ❌ **忘了 `SV_Target` 序号与 URP GBuffer 顺序对应**：颜色错位
- ❌ **把 metalness 直接写进 GBuffer1**：URP 期待的是 specular
- ❌ **删了 ForwardLit**：透明物体消失
- ❌ **`_DOUBLE_SIDED_NORMALS` 没处理**：双面模型光照错

---

## 3.9 与下一章的联系

GBuffer 支持完了。下一章起进入屏幕空间效果——先在 URP 里做 SSAO。

---

> 章节完。下一章 `04_URP里做SSAO.md`。
