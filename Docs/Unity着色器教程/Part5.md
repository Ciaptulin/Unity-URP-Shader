# Part 5 · 让 MyLit 接入 URP 的完整光照系统

> **本节在整份教程中的位置**
> Part 1~4 结束时，`MyLit` 已经是一个能算 PBR 的着色器了：它有 albedo、法线、金属度、平滑度、自发光、清漆，最后交给 `UniversalFragmentPBR`。
> 但它对**场景里真实存在的光照系统**几乎是"充耳不闻"的：场景里有点光源没反应、烘焙好的光照贴图读不到、反射探针用不上、SSAO 拿不到法线。
>
> 本节就是把这些"接口"一个个接上。用标签区分三类工作：
>
> - 🟦 **【场景】** — 摆光源、勾 Static、烘焙、加 Renderer Feature。不管用不用自定义 Shader 都要做。
> - 🟩 **【Shader】** — 写代码的人要做的事：加关键字、加 UV、加字段、补 Pass。
> - 🟪 **【原理】** — 底层实现，读懂即可，绝大多数不需要你自己写。
>
> 本节涉及的项目文件：`Assets/Shader/MyLit/MyLit.shader`、`MyLitCommon.hlsl`、`MyLitForwardLitPass.hlsl`、`MyLitDepthNormalsPass.hlsl`、`MyLitMetaPass.hlsl`、`Assets/Scripts/AdditionalLightShadowController.cs`。
> 本节涉及的 URP 源码：`ShaderLibrary/Lighting.hlsl`、`RealtimeLights.hlsl`、`GlobalIllumination.hlsl`、`AmbientOcclusion.hlsl`、`LightCookie/LightCookie.hlsl`、`ObjectMotionVectors.hlsl`。
>
> **版本基准：Unity 2023.2.20f1 / URP 16.0.6。** 这一节里所有"关键字叫什么名字""函数有几个参数"都以这个版本为准——很多网上的教程（包括本教程的旧版）用的是 URP 12/14 的名字，直接抄会静默失效。

---

## 0. 这一节到底要解决什么问题

**问题**：`UniversalFragmentPBR(InputData, SurfaceData)` 是个"纯函数"——它只认你喂给它的两个结构体。你没喂进去的东西，它一律当不存在：

| 你没喂的东西 | 表现 |
|---|---|
| `_ADDITIONAL_LIGHTS` 关键字 | 场景里点光源/聚光灯照不亮物体 |
| `bakedGI` 字段 | 烘焙光照贴图完全不参与，物体只有实时光 |
| `occlusion` 字段 | 缝隙没有变暗，SSAO 与 AO 贴图失效 |
| `normalizedScreenSpaceUV` 字段 | SSAO 采样位置固定在一个点，整屏遮挡错乱 |
| DepthNormals / MotionVectors Pass | SSAO、运动模糊在你的材质上完全不生效 |

**一句话概括本节**：
> 本节 90% 的工作是"**把正确的开关打开、把正确的字段填上**"。真正要你写的算法代码接近于零——这正是 URP 自定义 Shader 的常态，也是旧版教程最容易把人带偏的地方：它花了大量篇幅讲"算法原理"，却没讲清楚"你到底该改哪一行"。

---

## 1. 🟩 附加光源（点光源 / 聚光灯）

### 1.1 关键字：一行都不能少，一个字母都不能错

在 `MyLit.shader` 的 ForwardLit Pass 里：

```hlsl
// 附加光源本体
#pragma multi_compile _ _ADDITIONAL_LIGHTS
// 附加光源阴影  ← 注意是 _ADDITIONAL_LIGHT_SHADOWS（单数 LIGHT）
#pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS
```

### 1.2 ⚠️ 全教程最坑的一个字母

这两个关键字长得几乎一样，**但复数形式不同**：

| 关键字 | 含义 | 拼写 |
|---|---|---|
| 启用附加光源 | 有多个"灯" | `_ADDITIONAL_LIGHTS` ← **复数** |
| 附加光源阴影 | 是"光"的阴影 | `_ADDITIONAL_LIGHT_SHADOWS` ← **单数** |

URP 源码里写死的是后者（`UniversalRenderPipelineCore.cs` 中 `AdditionalLightShadows = "_ADDITIONAL_LIGHT_SHADOWS"`）。写错成 `_ADDITIONAL_LIGHTS_SHADOWS` 时：

- Unity **不报错**（`multi_compile` 只是声明了一个没人用的关键字）；
- 变体会被编译，只是**阴影采样那段代码永远不参与编译**；
- 结果是"附加光源亮着，但就是不投阴影"——一个极难归因的 bug。

> 📌 **项目现状提示**：当前 `MyLit.shader` 里写的是 `_ADDITIONAL_LIGHTS_SHADOWS`（复数）。若发现点光源不投阴影，先改这一行再看别的。

### 1.3 光有关键字还不够：`InputData` 必须喂对

`UniversalFragmentPBR` 内部的附加光源循环长这样（URP 16 源码，`Lighting.hlsl`）：

```hlsl
LIGHT_LOOP_BEGIN(pixelLightCount)
    Light light = GetAdditionalLight(lightIndex, inputData, shadowMask, aoFactor);
    ...
LIGHT_LOOP_END
```

`GetAdditionalLight` 需要 `inputData.positionWS` 才能算方向、衰减和阴影坐标。所以：

> **positionWS 填错 = 附加光源全废**，而且和盒投影一样，不会有任何报错。

### 1.4 数量与性能：由 URP Asset 决定，不由 Shader 决定

- **Per Object Limit**（URP Asset → Lighting → Additional Lights）：每个物体最多受几个附加光源影响，默认 4，最大与平台有关。
- **Cast Shadows**：附加光源是否投影，在光源 Inspector 上单独开关，受 URP Asset 的 `Additional Lights > Shadow Atlas Resolution` 等限制。
- **Per Vertex 模式**：URP 16 的变体是 `_ADDITIONAL_LIGHTS_VERTEX`，需要在 Shader 里也声明才支持。

| 模式 | 关键字 | 计算位置 | 代价 |
|---|---|---|---|
| Per Pixel（默认） | `_ADDITIONAL_LIGHTS` | 片元 | 每个光源一次完整 BRDF |
| Per Vertex | `_ADDITIONAL_LIGHTS_VERTEX` | 顶点 | 便宜，但法线贴图细节在光照里体现不出来 |

> 💡 旧版教程说"每个附加光源会增加一次 Draw Call"，这是**内置管线前向渲染的说法**。URP 的前向渲染在**同一个 Pass 内循环所有光源**，不会每个光源多一次 Draw Call。真正增加的是**片元着色器的循环次数与分支成本**。

### 1.5 🟦 C# 侧：项目里已有的小工具

`Assets/Scripts/AdditionalLightShadowController.cs` 提供了一个开关，用来在运行时切换附加光源阴影：

```csharp
Light light = GetComponent<Light>();
light.lightShadows = LightShadows.Soft; // 或 None / Hard
```

它的价值在于 `OnValidate()`——在 Inspector 里改数值时立刻生效，方便你在编辑器里做 A/B 对比，验证"附加光源阴影到底有没有接上"。

---

## 2. 🟩➕🟦 烘焙光照（Lightmap + Light Probe）

### 2.1 数据流：三步，缺一不可

```
① Attributes 里声明 uv2（TEXCOORD1）
         ↓
② Vertex 里用 OUTPUT_LIGHTMAP_UV 宏变换后传给 Interpolators
         ↓
③ Fragment 里 SampleLightmap(uv2, normalWS) → inputData.bakedGI
```

**①** `MyLitForwardLitPass.hlsl`：

```hlsl
struct Attributes {
    float3 positionOS : POSITION;
    float2 uv         : TEXCOORD0; // 模型 UV
    float2 uv2        : TEXCOORD1; // 光照贴图 UV
    ...
};
```

**②** 关键点：**不要直接赋值**。必须用宏：

```hlsl
// ❌ 旧版教程的写法：漏掉了 unity_LightmapST 的缩放偏移
output.uv2 = input.uv2;

// ✅ 正确：Unity 会把 atlas 中的分块位置写进 unity_LightmapST
OUTPUT_LIGHTMAP_UV(input.uv2, unity_LightmapST, output.uv2);
```

`OUTPUT_LIGHTMAP_UV` 展开后就是 `uv2 * unity_LightmapST.xy + unity_LightmapST.zw`。一张光照贴图 atlas 里塞了几十个物体，每个物体只占其中一小块——不做这个变换，所有物体都会采样到 atlas 的左下角。

### 2.2 ⚠️ 最大的坑：`SampleLightmap` 在没有 lightmap 时返回 0

URP 16 源码（`GlobalIllumination.hlsl`）：

```hlsl
half3 SampleLightmap(float2 staticLightmapUV, half3 normalWS)
{
#ifndef LIGHTMAP_ON
    return half3(0, 0, 0);   // ← 注意这里
#else
    ...
#endif
}
```

这解释了一个极其常见的现象：

> **"我的动态物体一进场景就全黑，静态物体却正常。"**

因为：
- 静态物体 → `LIGHTMAP_ON` 被定义 → `SampleLightmap` 正常工作；
- 动态物体 → 没有 lightmap，本该用**光照探针（SH）** 兜底，但你无脑调了 `SampleLightmap` → 返回 0 → 环境光归零。

**正确写法：两个分支都要有。**

```hlsl
#ifdef LIGHTMAP_ON
    // 静态：采样光照贴图
    lightingInput.bakedGI = SampleLightmap(input.uv2, normalWS);
#else
    // 动态：用顶点阶段算好的球谐系数兜底
    lightingInput.bakedGI = SampleSHPixel(input.vertexSH, normalWS);
#endif
```

配套地，顶点函数里要先算出 SH（代价低，放顶点）：

```hlsl
// Vertex 中
output.vertexSH = SampleSHVertex(normInput.normalWS);

// Interpolators 中
half3 vertexSH : TEXCOORD5;
```

> 📌 **项目现状**：`MyLitForwardLitPass.hlsl` 已经按上面的正确写法修过了，并且额外留了一个 `_DEBUG_BAKED_GI` 关键字，可以直接把 `bakedGI` 输出成灰度图来看烘焙结果对不对。这是排查 GI 问题最省事的一招。

### 2.3 三种 GI 来源，别混为一谈

| 来源 | 适用对象 | 数据形式 | 采样依据 |
|---|---|---|---|
| **Lightmap** | 静态物体 | 纹理（atlas） | 光照贴图 UV（`uv2`） |
| **Light Probe** | 动态物体 | 球谐 SH | 世界位置 + 法线 |
| **Reflection Probe** | 所有物体的**镜面**反射 | Cubemap | 反射向量（见反射探针专文） |

前两个填 `InputData.bakedGI`（漫反射 GI），第三个由 `UniversalFragmentPBR` 内部自动处理（镜面 GI）。**这是两笔独立的账**，旧版教程把它们混在一个"反射的工作流程"里讲，是最大的阅读障碍。

### 2.4 🟦 场景侧清单（烘焙不出来的原因都在这）

1. 物体勾选 **Static → Contribute GI**（旧版本叫 Lightmap Static）。
2. 光源 Mode 设为 **Baked** 或 **Mixed**。
3. 模型导入设置里 **Generate Lightmap UVs** 打开（没有第二套 UV 就没法烘焙）。
4. `Window > Rendering > Lighting > Scene` → 设置 **Lighting Mode**：
   - `Baked Indirect`：烘焙间接光，实时算直接光和阴影（最常用）；
   - `Shadowmask`：额外烘焙一张阴影遮罩，让静态阴影保留到远处；
   - `Subtractive`：全烘焙，最省但质量最低。
5. 点 **Generate Lighting**。

> ⚠️ **Shadowmask 模式的额外要求**：需要在 Shader 里给 `InputData.shadowMask` 赋值（`SAMPLE_SHADOWMASK(input.uv2)`），并声明 `SHADOWS_SHADOWMASK` / `LIGHTMAP_SHADOW_MIXING` 关键字。否则即使场景设成 Shadowmask，你的材质也只会表现得像 Baked Indirect。项目里目前没接这一项。

### 2.5 Meta Pass：别让你的自发光"烤不进"场景

烘焙时 Unity 需要知道物体表面自身长什么样（albedo / 自发光），才能算出它向周围反弹了多少光。这个数据由 `LightMode = Meta` 的 Pass 提供。

项目里已经有 `MyLitMetaPass.hlsl`。**如果缺这个 Pass**，自发光物体周围的墙面在烘焙后不会发亮——又是一个"不报错但不对"的坑。

---

## 3. 🟩 遮挡贴图（Occlusion Map）

### 3.1 通道约定：绿色

```hlsl
surfaceInput.occlusion = SAMPLE_TEXTURE2D(_OcclusionMap, sampler_OcclusionMap, uv).g * _OcclusionStrength;
```

Unity 沿用的 ORM 打包约定是 **R = 环境光遮挡 / G = 粗糙度 / B = 金属度**（glTF 标准），而 URP 内置 Lit 用的是 **G 通道**。项目沿用 URP 惯例取 `.g`。

> 💡 旧版教程给的解释是"绿色通道在 DXT5 里精度更高（6 bit）"——这个说法**只对老式 DXT5 成立**。现代项目普遍用 BC7（各通道等精度）或 ASTC（移动端），理由只剩"与 URP 内置 Lit 保持一致"。**跟着引擎惯例走就够了，别在颜色通道上自创标准。**

### 3.2 AO 在 PBR 里到底作用在哪

`UniversalFragmentPBR` 内部（`AmbientOcclusion.hlsl` + `GlobalIllumination.hlsl`）：

```hlsl
AmbientOcclusionFactor aoFactor = CreateAmbientOcclusionFactor(inputData, surfaceData);
// → indirectAmbientOcclusion = min(SSAO, surfaceData.occlusion)

lightingData.giColor = GlobalIllumination(brdfData, brdfDataClearCoat, clearCoatMask,
                                          inputData.bakedGI,
                                          aoFactor.indirectAmbientOcclusion,   // ← 只给间接光
                                          ...);
```

要点：

1. **AO 只压间接光（GI + 反射），不压直接光**。这是 PBR 的正确做法——直接光有自己的阴影系统，不该被一张贴图再乘一遍。
2. 贴图 AO 与 SSAO 的组合方式是 **`min()`，不是相乘**（旧版教程写的是相乘，错的）。取更小值 = 取更"暗"的那个遮挡，避免两处缝隙叠加成死黑。
3. 直接光的那一份由 `_AmbientOcclusionParam.w` 控制，来源是 **SSAO Renderer Feature 面板上的 Direct Lighting Strength**（默认 0.25），不是 URP Asset。

---

## 4. 反射探针（Reflection Probe）

本节**不展开**。反射探针、盒投影、粗糙度与 mip、金属 F0 等内容已单独整理成一份文档，风格与本系列一致：

> 👉 **见同目录 `示例：URP反射探针与PBR反射.md`**

那一份里同时给出了旧版教程反射章节中三处代码错误的修正（`unity_SpecCube0_BoxMin` 取中心、忘记减去探针中心、采样时用了未修正的 `reflectDir`）。

这里只留一句结论：

> **Shader 侧只需要保留两个关键字** `_REFLECTION_PROBE_BLENDING` 与 `_REFLECTION_PROBE_BOX_PROJECTION`（项目里已加），其余全是场景侧的活。

---

## 5. 🟦➕🟩 光源 Cookie

### 5.1 关键字：URP 16 只有一个

```hlsl
#pragma multi_compile_fragment _ _LIGHT_COOKIES
```

旧版教程写的 `_MAIN_LIGHT_COOKIE` 与 `_ADDITIONAL_LIGHTS_COOKIE` 是**早期版本/内置管线的名字**。URP 16 的 `Lit.shader` 里只有一行 `#pragma multi_compile_fragment _ _LIGHT_COOKIES`，主光与附加光的 cookie 都由它统管。

> 📌 **项目现状**：`MyLit.shader` 里还没有这一行。需要 cookie 时补上即可——它同样不需要你写任何采样代码。

### 5.2 Cookie 内部怎么做的（🟪，了解即可）

URP 16 把所有 cookie 打包进一张 **atlas 纹理**，每类光源的 UV 算法不同（`LightCookie/LightCookie.hlsl`）：

| 光源类型 | 贴图类型 | UV 算法 |
|---|---|---|
| Directional | 2D | 正交投影到光空间，`*0.5+0.5` |
| Spot | 2D | 透视投影 + 透视除法 |
| Point | 2D（八面体编码） | 方向 → Octahedral UV |

采样在 `RealtimeLights.hlsl` 里完成：

```hlsl
real3 cookieColor = SampleMainLightCookie(positionWS);          // 主光
real3 cookieColor = SampleAdditionalLightCookie(lightIndex, positionWS); // 附加光
```

> **又一次回到 positionWS**。这个字段在 Part 5 里已经是第三次成为关键先生了（附加光源、盒投影、cookie）。它必须逐像素精确。

### 5.3 🟦 纹理导入设置

1. Texture Type 选 **Cookie**；
2. Light Type 选对应光源类型；
3. 纯灰度图没有 alpha 时勾选 **Alpha From Luminance**；
4. Wrap Mode 决定 Repeat / Clamp（在光源 Inspector 上体现为平铺次数）。

---

## 6. 🟩 补充 Pass：DepthNormals 与 MotionVectors

### 6.1 为什么需要它们

URP 的一些效果需要从"场景整体"拿数据，而不是从某个材质拿：

| 效果 | 需要的数据 | 来源 Pass |
|---|---|---|
| SSAO | 深度 + 世界法线 | `DepthNormals` |
| 运动模糊 / TAA | 每像素上一帧位置 | `MotionVectors` |
| 景深 | 深度 | `DepthOnly` / 深度纹理 |

**如果你的 Shader 没有这些 Pass，这些效果就对你无效**——而且是"别人身上有、就你没有"的局部失效。

### 6.2 DepthNormals Pass

项目里的 `MyLitDepthNormalsPass.hlsl` 已经是正确写法，三个要点：

**① LightMode 标签**

```hlsl
Pass {
    Name "DepthNormals"
    Tags { "LightMode" = "DepthNormals" }
    ZWrite On
    Cull [_Cull]
    HLSLPROGRAM
    #pragma vertex DepthNormalsVertex
    #pragma fragment DepthNormalsFragment
    #pragma shader_feature_local _ALPHA_CUTOUT
    #pragma shader_feature_local _DOUBLE_SIDED_NORMALS
    #pragma shader_feature_local_fragment _NORMALMAP
    #include "MyLitDepthNormalsPass.hlsl"
    ENDHLSL
}
```

> ⚠️ 标签是 `DepthNormals`，**不是** `DepthNormalsOnly`（旧版教程写的是后者）。URP 16 的 `DepthNormalOnlyPass` 同时接受两个标签（`k_DepthNormals` 列表里两个都有），但 URP 内置 Lit 与本项目统一用 `DepthNormals`。

**② 法线编码：直接写 [-1,1]，不要 `*0.5+0.5`**

```hlsl
// ❌ 旧版教程：这是内置管线时代的写法
return float4(normalWS * 0.5 + 0.5, 1);

// ✅ URP 16：法线纹理是 R8G8B8A8_SNorm（有符号），直接写原值
return half4(NormalizeNormalPerPixel(normalWS), 0.0);
```

`DepthNormalOnlyPass.GetGraphicsFormat()` 里明确用了 `GraphicsFormat.R8G8B8A8_SNorm`。再自己 `*0.5+0.5` 等于把法线整体压缩到 [0,1] 的正卦限里——SSAO 会算出完全错误的遮挡。

**③ 关键字必须与 ForwardLit 对齐**

`_NORMALMAP` / `_ALPHA_CUTOUT` / `_DOUBLE_SIDED_NORMALS` 要在这个 Pass 里再声明一遍。否则：法线贴图不会体现在 SSAO 上，镂空区域会参与遮挡计算。

### 6.3 MotionVectors Pass（URP 16 的正确写法）

旧版教程给的代码有两个问题：一是自己编了一个 `_PrevViewProjM` 矩阵（URP 里不存在），二是把 DepthNormals 的代码原样复制过来当运动向量（输出的是法线）。

URP 16 的标准做法（`ObjectMotionVectors.hlsl`）：

```hlsl
// MyLitMotionVectorsPass.hlsl
#ifndef MY_LIT_MOTION_VECTORS_PASS_INCLUDED
#define MY_LIT_MOTION_VECTORS_PASS_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/UnityInput.hlsl"
#include "MyLitCommon.hlsl"

struct Attributes
{
    float4 position    : POSITION;
    float3 positionOld : TEXCOORD4;   // 上一帧的对象空间位置，由 Unity 自动填充
    float2 uv          : TEXCOORD0;
};

struct Varyings
{
    float4 positionCS                 : SV_POSITION;
    float4 positionCSNoJitter         : POSITION_CS_NO_JITTER;
    float4 previousPositionCSNoJitter : PREV_POSITION_CS_NO_JITTER;
    float2 uv                         : TEXCOORD0;
};

Varyings MotionVectorsVertex(Attributes input)
{
    Varyings output = (Varyings)0;

    VertexPositionInputs vertexInput = GetVertexPositionInputs(input.position.xyz);
    output.uv = TRANSFORM_TEX(input.uv, _ColorMap);
    output.positionCS = vertexInput.positionCS;

    // 当前帧（无抖动）
    output.positionCSNoJitter = mul(_NonJitteredViewProjMatrix, mul(UNITY_MATRIX_M, input.position));
    // 上一帧（无抖动）—— 注意用的是 UNITY_PREV_MATRIX_M，不是本帧矩阵
    float4 prevPos = (unity_MotionVectorsParams.x == 1) ? float4(input.positionOld, 1) : input.position;
    output.previousPositionCSNoJitter = mul(_PrevViewProjMatrix, mul(UNITY_PREV_MATRIX_M, prevPos));

    ApplyMotionVectorZBias(output.positionCS);
    return output;
}

float4 MotionVectorsFragment(Varyings input) : SV_Target
{
    #if defined(_ALPHA_CUTOUT)
        half4 colorSample = SAMPLE_TEXTURE2D(_ColorMap, sampler_ColorMap, input.uv) * _ColorTint;
        TestAlphaClip(colorSample);
    #endif

    float2 mv = CalcNdcMotionVectorFromCsPositions(
        input.positionCSNoJitter, input.previousPositionCSNoJitter);
    return float4(mv, 0, 0);
}

#endif
```

对应的 Pass 声明：

```hlsl
Pass {
    Name "MotionVectors"
    Tags { "LightMode" = "MotionVectors" }
    ColorMask RG
    HLSLPROGRAM
    #pragma shader_feature_local _ALPHA_CUTOUT
    #include "MyLitMotionVectorsPass.hlsl"
    ENDHLSL
}
```

三个容易忽略的细节：

1. **`ColorMask RG`**：运动向量只有两个分量，URP 按 RG 通道读取。
2. **`PREV_POSITION_CS_NO_JITTER` / `POSITION_CS_NO_JITTER` 是保留语义**，名字不能改，URP 靠它们识别。
3. **`UNITY_PREV_MATRIX_M`**：上一帧的模型矩阵。顶点动画（Part 8）如果改了顶点位置，这个 Pass 也要同步改，否则运动向量会和实际画面不一致。

> 📌 **项目现状**：目前还没有 MotionVectors Pass。需要运动模糊 / TAA 时再补，不必提前加——每个多余的 Pass 都是一次额外的几何绘制。

### 6.4 让 SSAO 真正生效的最后一环

回到第 0 节那张表：即使 DepthNormals Pass 完全正确，SSAO 仍然会错，因为还差一个字段：

```hlsl
// Fragment 中，必须在调用 UniversalFragmentPBR 之前
lightingInput.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(input.positionCS);
```

URP 用 `inputData.normalizedScreenSpaceUV` 去采样 `_ScreenSpaceOcclusionTexture`。**不填就是 (0,0)**——整屏读的是左下角那一个像素的 AO 值。

> 📌 **项目现状**：`MyLitForwardLitPass.hlsl` 里**还没有设这个字段**。这是当前 SSAO 在 MyLit 上不生效的直接原因。

---

## 7. 坑点排查表

| 现象 | 排查方向 |
|---|---|
| 点光源/聚光灯完全不影响物体 | `_ADDITIONAL_LIGHTS` 关键字；`InputData.positionWS` 是否正确；URP Asset 的 Per Object Limit |
| 附加光源亮但不投阴影 | 关键字拼写：`_ADDITIONAL_LIGHT_SHADOWS`（单数）；光源 Inspector 的 Shadows 开关 |
| 动态物体全黑，静态正常 | 无条件调用了 `SampleLightmap`，缺 SH 兜底分支（见 2.2） |
| 烘焙结果全黑 | 物体没勾 Contribute GI；光源不是 Baked/Mixed；没点 Generate Lighting |
| 烘焙结果错位/串到别的物体 | 顶点函数里没用 `OUTPUT_LIGHTMAP_UV` |
| 光照贴图有漏光、黑边 | 模型的第二套 UV 有重叠；Pack Margin 太小 |
| 自发光烤不进周围墙面 | 缺 Meta Pass |
| AO 贴图没效果 | 通道取错（应为 `.g`）；`_OcclusionStrength` 为 0；AO 只压间接光，直接光下看不出变化 |
| SSAO 无效 / 全屏一个色 | 缺 `normalizedScreenSpaceUV`；缺 DepthNormals Pass；法线被 `*0.5+0.5` 编码过 |
| SSAO 在镂空区域出错 | DepthNormals Pass 没有同步 `_ALPHA_CUTOUT` 裁剪逻辑 |
| 反射不对 | 见 `示例：URP反射探针与PBR反射.md` 的排查表 |
| Cookie 不生效 | URP 16 用的是 `_LIGHT_COOKIES` 一个关键字 |

---

## 8. 本节结论：落到项目上的检查清单

| # | 项目 | 位置 | 状态 |
|---|---|---|---|
| ① | `_ADDITIONAL_LIGHTS` 关键字 | `MyLit.shader` | ✅ 已有 |
| ② | 附加光源阴影关键字改为 `_ADDITIONAL_LIGHT_SHADOWS`（单数） | `MyLit.shader` | ⚠️ 待核对 |
| ③ | `uv2` + `OUTPUT_LIGHTMAP_UV` | `MyLitForwardLitPass.hlsl` | ✅ 已有 |
| ④ | `LIGHTMAP_ON` 双分支 + `SampleSHPixel` 兜底 | `MyLitForwardLitPass.hlsl` | ✅ 已有 |
| ⑤ | `_OcclusionMap` / `_OcclusionStrength`（`.g` 通道） | `MyLit.shader` + `MyLitCommon.hlsl` | ✅ 已有 |
| ⑥ | 反射探针两个关键字 | `MyLit.shader` | ✅ 已有 |
| ⑦ | `_LIGHT_COOKIES` 关键字 | `MyLit.shader` | ❌ 缺失（需要 cookie 时补） |
| ⑧ | `normalizedScreenSpaceUV` | `MyLitForwardLitPass.hlsl` | ❌ 缺失（SSAO 必需） |
| ⑨ | DepthNormals Pass（`DepthNormals` 标签 + SNorm 法线） | `MyLit.shader` + Pass 文件 | ✅ 已有 |
| ⑩ | MotionVectors Pass | 新建 | ❌ 缺失（需要运动模糊/TAA 时补） |
| ⑪ | Meta Pass（烘焙 GI / 自发光） | `MyLit.shader` + Pass 文件 | ✅ 已有 |
| ⑫ | 场景：反射探针 + 烘焙 + Static 标记 | SampleScene | 🟦 场景侧 |

> **时间分配提示**：本节看起来长了，但第 ①~⑪ 项加起来不超过二十行代码。**真正花时间的是 ⑫**——摆探针、勾 Static、调 Box Size、等烘焙。别把精力放反了。

---

## 小结

- 附加光源、烘焙 GI、AO、cookie、反射探针，本质上都是"**喂数据 + 开开关**"。
- 三个反复出现的元凶：`positionWS` 不对、关键字拼写不对、Pass 缺失。
- URP 16 的关键字/函数名与老版本差异不小（附加光阴影单复数、cookie 合并为一个、`DepthNormals` 标签、SNorm 法线编码），**抄老教程前先对着 `Library/PackageCache` 里的 URP 源码核一遍**。

下一节（Part 6）我们把视角从"Shader 内部"移到"Shader 外面"：SSAO、后处理，以及如何写一个自定义 Renderer Feature 插进 URP 的渲染流程。
