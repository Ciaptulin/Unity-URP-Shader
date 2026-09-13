# 高级 URP 特性：用代码编写 Unity URP 着色器（第 6 部分）

> 原文作者：NedMakesGames  
> 原文链接：https://nedmakesgames.medium.com/  
> 翻译时间：2026-08-14

---

## 目录

- [引言](#引言)
- [深度预通道（Depth Prepass）](#深度预通道depth-prepass)
  - [DepthOnly Pass](#depthonly-pass)
  - [片段一致性](#片段一致性)
- [深度法线通道（Depth Normals Pass）](#深度法线通道depth-normals-pass)
  - [SSAO 集成](#ssao-集成)
- [屏幕空间环境光遮蔽（SSAO）](#屏幕空间环境光遮蔽ssao)
- [SRP Batcher 兼容性](#srp-batcher-兼容性)
  - [UnityPerMaterial CBUFFER](#unitypermaterial-cbuffer)
  - [UnityPerDraw CBUFFER](#unityperdraw-cbuffer)
  - [验证兼容性](#验证兼容性)
- [GPU 实例化（GPU Instancing）](#gpu-实例化gpu-instancing)
  - [实例化属性](#实例化属性)
  - [逐实例数据](#逐实例数据)
- [单通道 VR 渲染](#单通道-vr-渲染)
- [渲染器特性（Renderer Features）](#渲染器特性renderer-features)
- [优化检查清单](#优化检查清单)
- [总结](#总结)
- [致谢](#致谢)

---

## 引言

大家好，我是 Ned，一名游戏开发者！在上一章中，我们大幅扩展了 MyLit 的光照能力——现在它支持点光源、聚光灯、烘焙光照、遮挡遮罩、反射探针、光照 Cookie 和雾效。这是一个功能完备的着色器了！

但是，编写着色器不只是让它"能工作"——你还需要让它**高效工作**。今天，我们将专注于 URP 的高级特性，这些特性能让你的着色器融入渲染管线的其余部分，并在大规模场景下保持性能。

我们会覆盖深度预通道、深度法线、屏幕空间环境光遮蔽、SRP Batcher、GPU 实例化和 VR 渲染。这是大量内容，但每一项都很重要。

在继续之前，我想感谢所有赞助者让这个系列成为可能。让我们开始吧！

---

## 深度预通道（Depth Prepass）

到目前为止，我们的着色器只包含一个 ForwardLit Pass 和一个 ShadowCaster Pass。但对于某些 URP 特性（如深度图、运动矢量，或深度图素（Depth Priming）），我们还需要额外的 Pass。

### DepthOnly Pass

**DepthOnly Pass** 的作用正如其名：它只将深度写入深度缓冲区，不写入颜色。URP 在某些设置下需要这个 Pass——最明显的是当你在 URP 设置资源中启用"Depth Priming"时。

在 `MyLit.shader` 中，添加一个新的 Pass 块：

```hlsl
Pass
{
    Name "DepthOnly"
    Tags { "LightMode" = "DepthOnly" }
    
    // 只写入深度，不写入颜色
    ZWrite On
    ColorMask 0
    Cull [_Cull]
    
    HLSLPROGRAM
    #pragma vertex DepthOnlyVertex
    #pragma fragment DepthOnlyFragment
    
    // 材质关键字
    #pragma shader_feature_local _ALPHATEST_ON
    #pragma shader_feature_local_fragment _ _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A
    
    // Unity 定义的关键字
    #pragma multi_compile _ LOD_FADE_CROSSFADE
    
    // GPU 实例化
    #pragma multi_compile_instancing
    #include_with_pragmas "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DOTS.hlsl"
    
    #include "Packages/com.unity.render-pipelines.universal/Shaders/LitInput.hlsl"
    #include "Packages/com.unity.render-pipelines.universal/Shaders/DepthOnlyPass.hlsl"
    ENDHLSL
}
```

> **等等！** 你可能会想——我们为什么要 `#include` URP 内置的 `LitInput.hlsl` 和 `DepthOnlyPass.hlsl`？这不是在引入依赖吗？

是的，确实如此。对于生产级着色器，你应该将 `DepthOnlyPass.hlsl` 的内容复制到自己的文件中（就像我们对其他 Pass 所做的那样）。但为了保持教程的简洁，在初始设置时使用 URP 的文件是可以接受的。

### 片段一致性

这里有一个**关键规则**：DepthOnly Pass 必须渲染与 ForwardLit Pass **完全相同**的片段集。如果 DepthOnly 写入了某个片段的深度，但 ForwardLit 却因为 Alpha 裁剪而丢弃了它，你会在深度图中看到幽灵像素。

**解决方案：** 在 DepthOnly Pass 中包含相同的 Alpha 裁剪逻辑。

创建一个自定义的 `MyLitDepthOnlyPass.hlsl`：

```hlsl
#ifndef MY_LIT_DEPTH_ONLY_PASS_INCLUDED
#define MY_LIT_DEPTH_ONLY_PASS_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "MyLitCommon.hlsl"

struct DepthOnlyAttributes
{
    float4 positionOS : POSITION;
    float2 uv : TEXCOORD0;
    #if defined(_ALPHATEST_ON)
        float2 uv1 : TEXCOORD1;
    #endif
    UNITY_VERTEX_INPUT_INSTANCE_ID
};

struct DepthOnlyVaryings
{
    float4 positionCS : SV_POSITION;
    #if defined(_ALPHATEST_ON)
        float2 uv : TEXCOORD0;
    #endif
    UNITY_VERTEX_INPUT_INSTANCE_ID
};

DepthOnlyVaryings DepthOnlyVertex(DepthOnlyAttributes input)
{
    DepthOnlyVaryings output = (DepthOnlyVaryings)0;
    UNITY_SETUP_INSTANCE_ID(input);
    UNITY_TRANSFER_INSTANCE_ID(input, output);
    
    output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
    
    #if defined(_ALPHATEST_ON)
        output.uv = TRANSFORM_TEX(input.uv, _ColorMap);
    #endif
    
    return output;
}

void DepthOnlyFragment(DepthOnlyVaryings input)
{
    UNITY_SETUP_INSTANCE_ID(input);
    
    #if defined(_ALPHATEST_ON)
        half4 colorSample = SAMPLE_TEXTURE2D(_ColorMap, sampler_ColorMap, input.uv);
        TestAlphaClip(colorSample);
    #endif
}

#endif
```

然后在 `.shader` 文件中引用它：

```hlsl
Pass
{
    Name "DepthOnly"
    Tags { "LightMode" = "DepthOnly" }
    ZWrite On
    ColorMask 0
    Cull [_Cull]
    
    HLSLPROGRAM
    #pragma vertex DepthOnlyVertex
    #pragma fragment DepthOnlyFragment
    
    #pragma shader_feature_local _ALPHATEST_ON
    #pragma shader_feature_local_fragment _ _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A
    #pragma multi_compile _ LOD_FADE_CROSSFADE
    #pragma multi_compile_instancing
    
    #include "MyLitDepthOnlyPass.hlsl"
    ENDHLSL
}
```

---

## 深度法线通道（Depth Normals Pass）

**DepthNormals Pass** 与 DepthOnly 类似，但它同时写入深度**和**法线。这对于屏幕空间效果至关重要——尤其是**屏幕空间环境光遮蔽（SSAO）**。

### SSAO 集成

URP 的 SSAO 渲染器特性有两种模式：
- **Depth 模式：** 仅使用深度图
- **Depth Normals 模式：** 同时使用深度图和法线图（质量更高）

如果你没有 DepthNormals Pass，URP 会回退到 Depth 模式，效果较差。添加这个 Pass 可以显著提升 SSAO 质量。

```hlsl
Pass
{
    Name "DepthNormals"
    Tags { "LightMode" = "DepthNormals" }
    ZWrite On
    Cull [_Cull]
    
    HLSLPROGRAM
    #pragma vertex DepthNormalsVertex
    #pragma fragment DepthNormalsFragment
    
    // 材质关键字
    #pragma shader_feature_local _NORMALMAP
    #pragma shader_feature_local _PARALLAXMAP
    #pragma shader_feature_local _ALPHATEST_ON
    #pragma shader_feature_local_fragment _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A
    
    // Unity 定义的关键字
    #pragma multi_compile _ LOD_FADE_CROSSFADE
    
    // GPU 实例化
    #pragma multi_compile_instancing
    #include_with_pragmas "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DOTS.hlsl"
    
    #include "MyLitDepthNormalsPass.hlsl"
    ENDHLSL
}
```

创建 `MyLitDepthNormalsPass.hlsl`：

```hlsl
#ifndef MY_LIT_DEPTH_NORMALS_PASS_INCLUDED
#define MY_LIT_DEPTH_NORMALS_PASS_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "MyLitCommon.hlsl"

struct DepthNormalsAttributes
{
    float4 positionOS : POSITION;
    float4 tangentOS : TANGENT;
    float3 normalOS : NORMAL;
    float2 uv : TEXCOORD0;
    UNITY_VERTEX_INPUT_INSTANCE_ID
};

struct DepthNormalsVaryings
{
    float4 positionCS : SV_POSITION;
    float2 uv : TEXCOORD0;
    float3 normalWS : TEXCOORD1;
    #if defined(_NORMALMAP)
        float4 tangentWS : TEXCOORD2;
    #endif
    UNITY_VERTEX_INPUT_INSTANCE_ID
};

DepthNormalsVaryings DepthNormalsVertex(DepthNormalsAttributes input)
{
    DepthNormalsVaryings output = (DepthNormalsVaryings)0;
    UNITY_SETUP_INSTANCE_ID(input);
    UNITY_TRANSFER_INSTANCE_ID(input, output);
    
    output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
    output.uv = TRANSFORM_TEX(input.uv, _ColorMap);
    output.normalWS = TransformObjectToWorldNormal(input.normalOS);
    
    #if defined(_NORMALMAP)
        output.tangentWS = float4(
            TransformObjectToWorldDir(input.tangentOS.xyz),
            input.tangentOS.w
        );
    #endif
    
    return output;
}

half4 DepthNormalsFragment(DepthNormalsVaryings input) : SV_TARGET
{
    UNITY_SETUP_INSTANCE_ID(input);
    
    // Alpha 裁剪
    #if defined(_ALPHATEST_ON)
        half4 colorSample = SAMPLE_TEXTURE2D(_ColorMap, sampler_ColorMap, input.uv);
        TestAlphaClip(colorSample);
    #endif
    
    // 编码法线到 [0, 1] 范围
    float3 normalWS = normalize(input.normalWS);
    
    #if defined(_NORMALMAP)
        // 采样法线贴图并转换到世界空间
        half4 normalSample = SAMPLE_TEXTURE2D(_BumpMap, sampler_BumpMap, input.uv);
        half3 normalTS = UnpackNormalScale(normalSample, _NormalScale);
        
        float3 tangentWS = normalize(input.tangentWS.xyz);
        float3 bitangentWS = cross(normalWS, tangentWS) * input.tangentWS.w;
        float3x3 tangentToWorld = float3x3(tangentWS, bitangentWS, normalWS);
        
        normalWS = TransformTangentToWorld(normalTS, tangentToWorld);
        normalWS = normalize(normalWS);
    #endif
    
    return float4(normalWS * 0.5 + 0.5, 1);
}

#endif
```

> **关键技巧：** 片段函数返回 `normalWS * 0.5 + 0.5` 将法线从 [-1, 1] 范围重新映射到 [0, 1] 范围，以便存储在纹理中。URP 的 SSAO 特性知道如何解码这个值。

---

## 屏幕空间环境光遮蔽（SSAO）

现在你已经有了 DepthNormals Pass，启用 SSAO 就很简单了：

1. 打开 **URP 设置资源**（在 Project Settings → Graphics 中）
2. 在渲染器数据中，点击 **Add Renderer Feature → Screen Space Ambient Occlusion**
3. 设置 Source 为 **Depth Normals**（如果你有 DepthNormals Pass）
4. 调整 Intensity、Radius 和 Falloff Distance

URP 的 SSAO 会自动采样你的 DepthNormals Pass 输出（存储在 `_CameraNormalsTexture` 中）和深度纹理（`_CameraDepthTexture`），然后计算屏幕空间遮蔽。

> **提示：** 如果你在 DepthNormals Pass 中启用了 `_NORMALMAP`，SSAO 会考虑法线贴图的细节——这意味着裂缝和缝隙中的遮蔽会更精确！

---

## SRP Batcher 兼容性

**SRP Batcher** 是 URP 中最重要的 CPU 优化特性之一。它通过将逐对象的常数缓冲区（CBUFFER）与材质属性分开，大幅减少了 Draw Call 开销。

### UnityPerMaterial CBUFFER

要让 MyLit 兼容 SRP Batcher，**所有**材质属性必须声明在名为 `UnityPerMaterial` 的 CBUFFER 中。

在 `MyLitCommon.hlsl` 中，将所有属性包装在 CBUFFER 块中：

```hlsl
#ifndef MY_LIT_COMMON_INCLUDED
#define MY_LIT_COMMON_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

// ============================================================
// UnityPerMaterial CBUFFER —— SRP Batcher 兼容性要求
// ============================================================
CBUFFER_START(UnityPerMaterial)
    
    // 表面颜色
    float4 _ColorTint;
    float4 _ColorMap_ST;
    
    // 法线贴图
    float _NormalScale;
    
    // 金属度
    float _Metalness;
    
    // 平滑度
    float _Smoothness;
    
    // Alpha 裁剪
    float _Cutoff;
    
    // 自发光
    float4 _EmissionTint;
    
    // 视差
    float _ParallaxStrength;
    
    // 清漆
    float _ClearCoatStrength;
    float _ClearCoatSmoothness;
    
    // 遮挡
    float _OcclusionStrength;
    
    // 表面类型（用于自定义检视器）
    float _SurfaceType;
    float _BlendType;
    float _FaceRenderingMode;
    float _Cull;
    
    // 双面法线
    float _DoubleSidedNormals;
    
CBUFFER_END

// 纹理和采样器声明在 CBUFFER 外部！
TEXTURE2D(_ColorMap);
SAMPLER(sampler_ColorMap);

TEXTURE2D(_BumpMap);
SAMPLER(sampler_BumpMap);

TEXTURE2D(_MetalnessMask);
SAMPLER(sampler_MetalnessMask);

TEXTURE2D(_SmoothnessMap);
SAMPLER(sampler_SmoothnessMap);

TEXTURE2D(_EmissionMap);
SAMPLER(sampler_EmissionMap);

TEXTURE2D(_ParallaxMap);
SAMPLER(sampler_ParallaxMap);

TEXTURE2D(_ClearCoatMask);
SAMPLER(sampler_ClearCoatMask);

TEXTURE2D(_ClearCoatSmoothnessMap);
SAMPLER(sampler_ClearCoatSmoothnessMap);

TEXTURE2D(_OcclusionMap);
SAMPLER(sampler_OcclusionMap);

// ============================================================
// 函数
// ============================================================

void TestAlphaClip(float4 colorSample)
{
    #ifdef _ALPHATEST_ON
        clip(colorSample.a * _ColorTint.a - _Cutoff);
    #endif
}

#endif
```

> **关键规则：**
> - ✅ 材质属性（float、float4 等）**必须**在 `UnityPerMaterial` CBUFFER 中
> - ✅ 纹理和采样器声明在 CBUFFER **外部**
> - ❌ 永远不要在全局作用域声明材质属性（不使用 CBUFFER）

### UnityPerDraw CBUFFER

URP 还需要一个名为 `UnityPerDraw` 的 CBUFFER 来存储引擎提供的逐对象数据。当你使用 URP 的变换函数（如 `TransformObjectToWorld`）时，这些会自动处理。

URP 的内置 CBUFFER 包括：
- `unity_ObjectToWorld` — 对象到世界矩阵
- `unity_WorldToObject` — 世界到对象矩阵
- `unity_SHAr`, `unity_SHAg`, `unity_SHAb` — 球谐系数
- `unity_ProbeVolumeParams` — 光照探针体积参数

只要你 `#include` 了 URP 的 Core.hlsl，这些就都为你设置好了。

### 验证兼容性

要检查你的着色器是否与 SRP Batcher 兼容：

1. 打开 **Frame Debugger**（Window → Analysis → Frame Debugger）
2. 导航到任意 Draw Call
3. 查看 "SRP Batcher" 列——如果显示 ✅，你的着色器是兼容的

如果你的着色器**不兼容**，常见原因包括：
- 属性未在 `UnityPerMaterial` CBUFFER 中声明
- 使用了 `MaterialPropertyBlock`（这会破坏 SRP Batcher）
- 全局变量中存储了材质属性

---

## GPU 实例化（GPU Instancing）

**GPU Instancing** 允许你在一次 Draw Call 中渲染同一网格的成千上万个副本，每个副本可以有不同的属性（如颜色、缩放）。

### 实例化属性

要在 MyLit 中启用 GPU 实例化，需要三样东西：

**1. multi_compile_instancing 指令：**

```hlsl
#pragma multi_compile_instancing
```

**2. 实例 ID 宏：**

在 `Attributes` 结构体中添加 `UNITY_VERTEX_INPUT_INSTANCE_ID`：

```hlsl
struct Attributes
{
    float4 positionOS : POSITION;
    float3 normalOS : NORMAL;
    float4 tangentOS : TANGENT;
    float2 uv : TEXCOORD0;
    UNITY_VERTEX_INPUT_INSTANCE_ID  // 新增
};
```

在 `Interpolators` 结构体中添加 `UNITY_VERTEX_INPUT_INSTANCE_ID`：

```hlsl
struct Interpolators
{
    float4 positionCS : SV_POSITION;
    float2 uv : TEXCOORD0;
    float3 normalWS : TEXCOORD1;
    float3 positionWS : TEXCOORD2;
    UNITY_VERTEX_INPUT_INSTANCE_ID  // 新增
};
```

**3. 设置和传递实例 ID：**

在顶点函数中：

```hlsl
Interpolators Vertex(Attributes input)
{
    Interpolators output = (Interpolators)0;
    UNITY_SETUP_INSTANCE_ID(input);
    UNITY_TRANSFER_INSTANCE_ID(input, output);
    
    // ... 其余代码不变
}
```

### 逐实例数据

如果你想让每个实例有不同的颜色（例如，一片草地中每棵草有不同的绿色色调），使用 `UNITY_INSTANCING_BUFFER_START/END`：

```hlsl
UNITY_INSTANCING_BUFFER_START(Props)
    UNITY_DEFINE_INSTANCED_PROP(float4, _InstanceColor)
UNITY_INSTANCING_BUFFER_END(Props)
```

在片段函数中访问：

```hlsl
half4 instanceColor = UNITY_ACCESS_INSTANCED_PROP(Props, _InstanceColor);
color *= instanceColor.rgb;
```

在 C# 中设置逐实例属性：

```csharp
MaterialPropertyBlock block = new MaterialPropertyBlock();
block.SetColor("_InstanceColor", Color.red);
renderer.SetPropertyBlock(block);
```

---

## 单通道 VR 渲染

URP 支持 **单通道立体渲染（Single-Pass Stereo Rendering）**，它在一次 Draw Call 中同时渲染左右眼。要让你的着色器兼容，需要少量修改。

### 屏幕空间位置

在 VR 中，每只眼睛有不同的视图矩阵。使用 `UnityStereoTransformScreenSpaceTex` 宏来处理屏幕空间 UV：

```hlsl
// 在片段函数中
float2 screenUV = input.positionCS.xy / _ScaledScreenParams.xy;
screenUV = UnityStereoTransformScreenSpaceTex(screenUV);
```

### 实例化立体渲染

URP 的 VR 渲染使用 GPU 实例化来同时渲染两只眼睛。只要你的着色器支持 GPU 实例化（如上节所述），它就自动兼容单通道 VR。

### 视差修正

在 VR 中，每只眼睛看到视差偏移的版本。对于视差映射，使用 `GetViewDirectionTangentSpace` 已经考虑了立体渲染——URP 会自动传入正确的视图方向。

---

## 渲染器特性（Renderer Features）

URP 的**渲染器特性**系统允许你通过 C# 脚本扩展渲染管线。虽然这不是严格意义上的着色器代码，但了解如何编写配套的渲染器特性很重要。

### 自定义渲染器特性示例

这是一个简单的渲染器特性，它在所有不透明物体之后、透明物体之前注入一个自定义 Pass：

```csharp
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class MyCustomFeature : ScriptableRendererFeature
{
    class MyCustomPass : ScriptableRenderPass
    {
        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            // 自定义渲染逻辑
            CommandBuffer cmd = CommandBufferPool.Get("MyCustomPass");
            // ... 添加绘制命令 ...
            context.ExecuteCommandBuffer(cmd);
            CommandBufferPool.Release(cmd);
        }
    }
    
    MyCustomPass m_Pass;
    
    public override void Create()
    {
        m_Pass = new MyCustomPass();
        m_Pass.renderPassEvent = RenderPassEvent.AfterRenderingOpaques;
    }
    
    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        renderer.EnqueuePass(m_Pass);
    }
}
```

> **用途：** 渲染器特性可用于后处理效果、自定义阴影、水反射、屏幕空间效果等。MyLit 着色器通过正确设置 Pass 名称和 LightMode 标签来与这些特性协作。

---

## 优化检查清单

现在你的着色器已经功能完备且高度优化，以下是最终检查清单：

### SRP Batcher 兼容性 ✅

- [x] 所有材质属性在 `UnityPerMaterial` CBUFFER 中
- [x] 纹理/采样器在 CBUFFER 外部声明
- [x] 未使用 `MaterialPropertyBlock`
- [x] 未使用全局变量存储材质属性

### GPU Instancing ✅

- [x] `#pragma multi_compile_instancing` 已添加
- [x] `UNITY_VERTEX_INPUT_INSTANCE_ID` 在输入/输出结构体中
- [x] `UNITY_SETUP_INSTANCE_ID` 在顶点函数开头
- [x] `UNITY_TRANSFER_INSTANCE_ID` 传递实例 ID

### Pass 完整性 ✅

- [x] ForwardLit Pass（主渲染）
- [x] ShadowCaster Pass（投射阴影）
- [x] DepthOnly Pass（深度预通道）
- [x] DepthNormals Pass（SSAO 支持）
- [x] Meta Pass（光照烘焙）

### 关键字优化 ✅

- [x] 使用 `shader_feature_local` 替代 `multi_compile`（当可能时）
- [x] 移除未使用的变体
- [x] 按重要性排列关键字

---

## 总结

### 完整 Pass 架构

```
MyLit.shader
├── SubShader
│   ├── Pass: ForwardLit (LightMode = UniversalForward)
│   │   ├── 主光源 + 附加光源
│   │   ├── PBR 光照
│   │   ├── 法线贴图 / 视差
│   │   ├── 自发光 / 遮挡
│   │   └── 雾效
│   │
│   ├── Pass: ShadowCaster (LightMode = ShadowCaster)
│   │   ├── 深度偏移（阴影偏差）
│   │   └── Alpha 裁剪
│   │
│   ├── Pass: DepthOnly (LightMode = DepthOnly)
│   │   ├── 仅深度写入
│   │   └── Alpha 裁剪（与 ForwardLit 一致）
│   │
│   ├── Pass: DepthNormals (LightMode = DepthNormals)
│   │   ├── 深度 + 法线写入
│   │   ├── 法线贴图支持
│   │   └── Alpha 裁剪
│   │
│   └── Pass: Meta (LightMode = Meta)
│       └── 为光照烘焙提供反照率和自发光
```

### 关键优化策略

| 策略 | 性能提升 | 实现难度 |
|--------|-----------|----------|
| SRP Batcher | ⭐⭐⭐⭐⭐ | 低（CBUFFER 包装） |
| GPU Instancing | ⭐⭐⭐⭐⭐ | 中（宏 + 属性块） |
| 关键字裁剪 | ⭐⭐⭐⭐ | 中（shader_feature） |
| 纹理通道打包 | ⭐⭐⭐ | 中（Photoshop/代码） |
| 延迟渲染路径 | ⭐⭐⭐⭐ | 高（管线设置） |

---

## 致谢

我想感谢所有赞助者的支持，特别感谢本教程开发期间的次世代赞助人！非常感谢你们所有人。

在下一章中，我将专注于**自定义光照模型**！我们将学习如何绕过 URP 的内置 PBR 函数，编写自己的光照算法——从卡通渲染到布料、皮肤、头发和植物叶片。

感谢阅读，去做游戏吧！

---

> **参考链接：** 完成本教程后的着色器文件最终版本，请参考原文末尾的 GitHub Gist 链接。
>
> 如果你喜欢本教程，请考虑[关注原作者](https://nedmakesgames.medium.com/)，以便在下一部分发布时收到邮件通知。
>
> 如果你想从另一个角度看看本教程，这里也有[视频版本](https://www.youtube.com/)。
>
> 如果你想在 Unity 项目中下载本教程中展示的所有着色器，请考虑[加入 Patreon](https://www.patreon.com/NedMakesGames)。
>
> 如果你有任何问题，欢迎在评论区留言或通过社交媒体联系原作者。
