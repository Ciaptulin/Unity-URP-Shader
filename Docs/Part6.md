# 高级 URP 特性：用代码编写 Unity URP 着色器（第 6 部分）

> 原作者：NedMakesGames
> 原文链接：https://nedmakesgames.medium.com/
> 本文件已按本项目实际重写（关键字 / 结构体名 / 编码 / 大括号风格 / Pass 编排全部对齐 `Assets/Shader/MyLit/`）
> 重写时间：Part5 完成后
> 分支：`feature/pbr-normal-mapping`

---

## 前言

Part5 结束时，MyLit 已经拥有 6 个 Pass、一整套 PBR 光照能力。功能是够了，但"能跑"不等于"跑得好"。

这一部分不再堆功能，而是让着色器**融入渲染管线的其余部分**，并在大规模场景下保持性能。主题：

+ **深度 / 法线通道回顾**：DepthOnly、DepthNormals 为什么存在（项目在 Part2 附近 / Part5-七 已落地）
+ **SSAO 集成**：让屏幕空间环境光遮蔽吃到我们的深度 + 法线
+ **SRP Batcher 兼容性**：CPU 侧最重要的优化
+ **GPU 实例化**：*（项目未采用，仅作知识扩展）*
+ **单通道 VR 渲染**：*（项目未采用，仅作知识扩展）*
+ **渲染器特性（Renderer Features）**：用 C# 扩展管线
+ **优化检查清单**：收尾自查

> **与 Part5 第七节的关系**：Part5-七 已经"从零写出"了 DepthNormals 和 MotionVectors。本部分不重复造，而是把这两个 Pass 放回**整条管线**的视角里，讲清它们服务谁、以及由此带出的性能话题。

---

## 一、深度预通道回顾：DepthOnly

### 1.1 它是什么

**DepthOnly Pass** 只把深度写进深度缓冲，不写颜色。URP 在某些设置下需要它——最典型的是 URP Asset 里启用 **Depth Priming（深度图素）** 时。

本项目的 DepthOnly 是 **Pass 4**，Part2 附近就加好了（见 `Docs/进度地图.md`）。这里只做回顾。

> **教程原文的坑**：原翻译稿把 DepthOnly 当作"本部分新增"从零讲，还教你 `#include` URP 内置的 `DepthOnlyPass.hlsl` 起步。**本项目不走这条路**——我们从头就自写 `MyLitDepthOnlyPass.hlsl`。原稿那段"先 include 再复制"的过渡，直接跳过。

### 1.2 片段一致性（关键规则）

这是整个深度预通道里**最重要的一条**：

> **DepthOnly 必须渲染与 ForwardLit 完全相同的片段集。**

如果 DepthOnly 写了某个像素的深度，而 ForwardLit 因为镂空把它裁掉了，深度图里就会留下**幽灵像素**。

**本项目的做法**：`MyLitDepthOnlyPass.hlsl` 里用与 ForwardLit / ShadowCaster **完全一致**的镂空逻辑：

```hlsl
// ===== [Part2] 仅深度通道（后效深度用，含镂空）=====
...
half4 DepthOnlyFragment(Interpolators input) : SV_TARGET
{
#ifdef _ALPHA_CUTOUT
    float4 colorSample = SAMPLE_TEXTURE2D(_ColorMap, sampler_ColorMap, input.uv);
    // 与 ShadowCaster / ForwardLit 保持一致的镂空
    colorSample.a = CalculateDotMatrix(input.uv, _DotDensity, _DotRadius, float2(_DotScaleX, _DotScaleY));
    TestAlphaClip(colorSample);
#endif
    return 0;
}
```

注意三点：

1. 关键字是 `_ALPHA_CUTOUT`，**不是**原稿写的 `_ALPHATEST_ON`
2. 镂空用项目的 `CalculateDotMatrix`（程序化点阵），不是单纯采样 albedo 的 alpha
3. 结构体名是 `Interpolators`，**不是** `DepthOnlyVaryings`

### 1.3 与教程示例的差异

| 项 | 教程示例 | 本项目 |
|---|---|---|
| 起点 | 先 `#include` URP 内置 DepthOnlyPass.hlsl | 全程自写 `MyLitDepthOnlyPass.hlsl` |
| 镂空关键字 | `_ALPHATEST_ON` | `_ALPHA_CUTOUT` |
| 镂空逻辑 | 采样 albedo alpha | `CalculateDotMatrix`（点阵）|
| 顶点输出结构体 | `DepthOnlyVaryings` | `Interpolators` |
| 大括号 | `Pass {` 不换行 | **大括号换行** |
| 额外关键字 | `LOD_FADE_CROSSFADE`、`multi_compile_instancing`、`DOTS.hlsl` | 项目**未使用**，已省略 |

---

## 二、深度法线通道回顾：DepthNormals

### 2.1 它是什么

**DepthNormals Pass** 与 DepthOnly 类似，但同时写入**深度 + 世界空间法线**。它对屏幕空间效果至关重要，尤其是 **SSAO**。

本项目的 DepthNormals 是 **Pass 5**，在 Part5-七 完成（见 `Part5.md` 7.1）。这里把"它服务谁"讲清。

### 2.2 它服务谁

| 消费方 | 需要什么 |
|---|---|
| **SSAO** | 每个像素的法线，用来定半球采样方向 |
| **SSR（屏幕空间反射）** | 法线，用来算反射方向 |
| **运动模糊** | 深度，用来判断物体运动范围 |

### 2.3 项目 Pass 定义（对照）

```hlsl
// ===== Pass 5: 深度 + 法线 [Part5-七] =====
Pass
{
    Name "DepthNormals"
    Tags{"LightMode" = "DepthNormals"}

    ZWrite On
    Cull [_Cull]

    HLSLPROGRAM
    #pragma exclude_renderers gles gles3 glcore
    #pragma target 4.5

    #pragma vertex DepthNormalsVertex
    #pragma fragment DepthNormalsFragment

    #pragma shader_feature_local _ALPHA_CUTOUT
    #pragma shader_feature_local _DOUBLE_SIDED_NORMALS
    #pragma shader_feature_local_fragment _NORMALMAP

    #include "MyLitDepthNormalsPass.hlsl"
    ENDHLSL
}
```

**关键点**：

+ `LightMode` 用 `"DepthNormals"`（URP 内置 Lit 的写法），**不是** `"DepthNormalsOnly"`（那是 HDRP 的写法，在 URP 里 Pass 不被识别）
+ 三个关键字（`_ALPHA_CUTOUT` / `_DOUBLE_SIDED_NORMALS` / `_NORMALMAP`）必须与 ForwardLit 同步，否则镂空、双面法线、法线贴图的表现会对不上

### 2.4 与本部分教程示例的三处差异

这三处 Part5-七 已详细记录，此处复述：

1. **法线输出格式**：原稿返回 `normalWS * 0.5 + 0.5`。**URP 不需要**——`_CameraNormalsTexture` 是带符号格式（SNorm），URP 内置 Lit 直接返回 `NormalizeNormalPerPixel(normalWS)`。项目与官方一致。

2. **TBN 构建方式**：项目在 `_NORMALMAP` 守卫内才传 `tangentWS`，片元里手写 `cross` 构造 TBN，比 `CreateTangentToWorld` 更省一个插值器。

3. **法线归一化**：`NormalizeNormalPerPixel(normalWS)` 不能省。插值后法线长度 < 1，不归一化会让 SSAO 半球采样方向明显偏斜。

### 2.5 原稿的关键字错误对照

| 原稿 | 项目实际 |
|---|---|
| `_ALPHATEST_ON` | `_ALPHA_CUTOUT` |
| `_BumpMap` / `sampler_BumpMap` | `_NormalMap` / `sampler_NormalMap` |
| `_NormalScale` | `_NormalStrength` |
| `float4(normalWS * 0.5 + 0.5, 1)` | `half4(NormalizeNormalPerPixel(normalWS), 0.0)` |
| `DepthNormalsVaryings` | `Interpolators` |

---

## 三、屏幕空间环境光遮蔽（SSAO）

### 3.1 原理一句话

SSAO 在屏幕空间里，对每个像素沿法线开一个半球，数一数有多少邻居"挡光"，挡住越多遮蔽越重。它需要 **深度图 + 法线图**——正好是 DepthNormals Pass 的输出。

### 3.2 URP 的两种模式

URP 的 SSAO 渲染器特性有两种模式：

+ **Depth 模式**：只用深度图（`_CameraDepthTexture`）
+ **Depth Normals 模式**：同时用深度图和法线图（`_CameraNormalsTexture`），质量更高

没有 DepthNormals Pass 时，URP 会回退到 Depth 模式，效果较差。有了它，SSAO 质量显著提升。

### 3.3 启用步骤（本项目）

1. 打开 **URP 设置资源**（Project Settings → Graphics → 选中的 URP Asset）
2. 找到其 **Renderer**（Forward Renderer Data）
3. **Add Renderer Feature → Screen Space Ambient Occlusion**
4. 把 **Source** 设为 **Depth Normals**（因为项目已有 DepthNormals Pass）
5. 调 Intensity、Radius、Falloff Distance

### 3.4 项目侧的关键修复（易踩）

SSAO 不仅依赖 DepthNormals Pass，还依赖 ForwardLit 里正确的 **屏幕空间 UV**。项目在 `MyLitForwardLitPass.hlsl` 里补了这一行：

```hlsl
// normalizedScreenSpaceUV = (0,0) 会导致 SSAO 采样错误，把环境反射乘没
lightingInput.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(input.positionCS);
```

**为什么**：`InputData` 用 `(InputData)0` 初始化，若不给 `normalizedScreenSpaceUV` 赋值，它默认为 `(0,0)`，SSAO 会一直在屏幕左上角采样，表现为"环境反射被乘没"。

### 3.5 关键字

ForwardLit 已声明：

```hlsl
// 屏幕空间遮挡 [Part5-三]
#pragma multi_compile_fragment _ _SCREEN_SPACE_OCCLUSION
```

这是引擎级关键字（由 SSAO 特性在运行时激活），**必须用 `multi_compile`**，不能用 `shader_feature`。

> **注意**：原稿把 SSAO 单独列成一大节、把 DepthNormals 列成另一节，且没提 `normalizedScreenSpaceUV` 这个实际项目踩过的坑。本项目把它补在 3.4。

---

## 四、SRP Batcher 兼容性

### 4.1 它是什么

**SRP Batcher** 是 URP 中最重要的 CPU 优化之一。它把"逐对象"的常量缓冲（`UnityPerDraw`）与"逐材质"的属性（`UnityPerMaterial`）分开管理，大幅降低 Draw Call 的 CPU 开销。

### 4.2 UnityPerMaterial CBUFFER

规则：**所有材质属性（float / float4）必须声明在名为 `UnityPerMaterial` 的 CBUFFER 里；纹理和采样器声明在 CBUFFER 外。**

本项目在 `MyLitCommon.hlsl` 里已满足：

```hlsl
// ===== [Part2] 材质属性（CBUFFER 兼容 SRP Batcher）=====
CBUFFER_START(UnityPerMaterial)
float4 _ColorTint;
float4 _ColorMap_ST;        // Unity 自动设置，供 TRANSFORM_TEX 应用 UV 平铺
float _Cutoff;              // 透明度裁切阈值
float _NormalStrength;      // [Part3] 法线强度
float _Metalness;           // [Part3] 金属度
float4 _SpecularTint;       // [Part3] 高光工作流色调
float4 _EmissionTint;       // [Part4] 自发光色调
float _Smoothness;          // [Part3] 平滑度
float _ParallaxStrength;    // [Part4] 视差强度
float _ClearCoatStrength;   // [Part4] 清漆强度
float _ClearCoatSmoothness; // [Part4] 清漆光滑度
float _OcclusionStrength;   // [Part5-三] 遮挡强度
// [Part4] 程序化点阵镂空参数
float _DotDensity;
float _DotRadius;
float _DotScaleX;
float _DotScaleY;
CBUFFER_END

// ===== 纹理声明（在 CBUFFER 外）=====
TEXTURE2D(_ColorMap); SAMPLER(sampler_ColorMap);
...
```

### 4.3 原稿 CBUFFER 示例的错误

原稿的 `UnityPerMaterial` 示例与本项目**不符**：

| 原稿 | 项目实际 |
|---|---|
| 含 `_SurfaceType` / `_BlendType` / `_FaceRenderingMode` / `_Cull` / `_DoubleSidedNormals` | 这些**不放进 CBUFFER**（`_Cull` 等用于 Pass 状态块；`_SurfaceType` 等只被 C# Inspector 读取）|
| `_NormalScale` | `_NormalStrength` |
| `_SmoothnessMap` | `_SmoothnessMask` |
| `_ClearCoatSmoothnessMap` | `_ClearCoatSmoothnessMask` |
| 缺 `_SpecularTint` / `_DotDensity` / `_DotRadius` / `_DotScaleX` / `_DotScaleY` | 项目实际有这些 |

> 换句话说：**照原稿抄 CBUFFER 会漏项，也可能多出不该在里面的项。以 `MyLitCommon.hlsl` 为准。**

### 4.4 UnityPerDraw CBUFFER

引擎提供的逐对象数据（`unity_ObjectToWorld`、`unity_SHAr` 等）由 URP 的 `Core.hlsl` 自动处理，只要 include 了就有，无需手动声明。

### 4.5 验证兼容性

1. 打开 **Frame Debugger**（Window → Analysis → Frame Debugger）
2. 选中任意 Draw Call
3. 看 **"SRP Batcher"** 列——显示 `✅` 即兼容

不兼容的常见原因：

+ 材质属性没在 `UnityPerMaterial` CBUFFER 里
+ 用了 `MaterialPropertyBlock`（会破坏 SRP Batcher）
+ 材质属性存成了全局变量

---

## 五、GPU 实例化（项目未采用，仅作知识扩展）

> **状态说明**：本项目**未启用** GPU Instancing。以下内容为知识扩展，实际代码里**没有** `multi_compile_instancing` / `UNITY_VERTEX_INPUT_INSTANCE_ID` 等宏。原稿把这些当作"必做步骤"，与项目实况不符。

### 5.1 它是什么

GPU Instancing 让同网格的大量副本在一次 Draw Call 里画完，每个副本可有不同属性（颜色、缩放）。

### 5.2 启用三件套

1. `#pragma multi_compile_instancing`
2. 在 `Attributes` / `Interpolators` 里加 `UNITY_VERTEX_INPUT_INSTANCE_ID`
3. 顶点函数里 `UNITY_SETUP_INSTANCE_ID(input)` + `UNITY_TRANSFER_INSTANCE_ID(input, output)`

### 5.3 逐实例数据

用 `UNITY_INSTANCING_BUFFER_START/END` 声明，片元里用 `UNITY_ACCESS_INSTANCED_PROP` 取，C# 侧用 `MaterialPropertyBlock` 设。

> **矛盾提醒**：5.3 用 `MaterialPropertyBlock`，而 4.5 说 `MaterialPropertyBlock` 会破坏 SRP Batcher。这是真实取舍——**要 instancing 的逐实例数据，就放弃 SRP Batcher 的批处理**。二者不是无条件共存。

---

## 六、单通道 VR 渲染（项目未采用，仅作知识扩展）

> **状态说明**：本项目**不涉及 VR**。以下为知识扩展。

URP 支持 **Single-Pass Stereo**，一次 Draw Call 渲染双眼。要点：

+ 屏幕空间 UV 用 `UnityStereoTransformScreenSpaceTex` 修正
+ 只要支持 GPU Instancing，就自动兼容单通道 VR（VR 用 instancing 渲染双眼）
+ 视差映射的 `GetViewDirectionTangentSpace` 已内置处理立体视图方向

---

## 七、渲染器特性（Renderer Features）

URP 的 **Renderer Feature** 系统允许用 C# 扩展管线。虽然不属于着色器代码，但理解它有助于让自定义 Pass 和管线协作。

### 7.1 基本结构

一个最小的 Renderer Feature：

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

### 7.2 ⚠️ URP 16 的重要变化（原稿未提）

本项目环境是 **Unity 2023.2.20f1 + URP 16.0.6**。在这个版本上：

+ `ScriptableRenderPass.Execute(ScriptableRenderContext, ref RenderingData)` 已被标记 **`[Obsolete]`**，会编译告警
+ 如果 URP Asset 里启用了 **Render Graph**，这个旧回调**根本不会被调用**，需要用 `RecordRenderGraph`

> **学习建议**：本项目暂不写 Renderer Feature。若将来要写，先确认 URP Asset 的 Render Graph 开关，再决定用旧 API（兼容模式）还是新 Render Graph API。**不要照原稿的代码直接抄**——它在 2023.2 上至少会有弃用警告。

### 7.3 与 MyLit 的协作

MyLit 通过正确的 **Pass 名 + LightMode 标签**与管线协作：

| Pass | LightMode | 被谁调用 |
|---|---|---|
| ForwardLit | `UniversalForward` | 前向渲染 |
| ShadowCaster | `ShadowCaster` | 阴影投射 |
| DepthOnly | `DepthOnly` | 深度预通道 / Depth Priming |
| DepthNormals | `DepthNormals` | SSAO / SSR 的深度法线 |
| MotionVectors | `MotionVectors` | 运动模糊 / TAA |
| Meta | `Meta` | 光照烘焙 |

---

## 八、优化检查清单

### 8.1 SRP Batcher 兼容性

- [x] 所有材质属性在 `UnityPerMaterial` CBUFFER 中（见 `MyLitCommon.hlsl`）
- [x] 纹理 / 采样器在 CBUFFER 外声明
- [x] 未在着色器里用 `MaterialPropertyBlock` 存材质属性

### 8.2 Pass 完整性（本项目实况 = 6 个）

- [x] ForwardLit（`UniversalForward`）
- [x] ShadowCaster（`ShadowCaster`）
- [x] Meta（`Meta`）
- [x] DepthOnly（`DepthOnly`）
- [x] DepthNormals（`DepthNormals`）
- [x] MotionVectors（`MotionVectors`）

> **与原稿的差异**：原稿"完整 Pass 架构"只列了 5 个（缺 MotionVectors）。本项目实为 6 个。

### 8.3 关键字优化

- [x] 材质级用 `shader_feature_local*`（`_NORMALMAP`、`_EMISSION`、`_ALPHA_CUTOUT` 等）
- [x] 引擎级用 `multi_compile*`（光照、阴影、Lightmap 等）
- [ ] 检查是否还有能改成 `shader_feature` 的 `multi_compile`（详见 `Part5.md` 8.4）
- [ ] 在构建层配一次 Variant Stripping（详见 `Part5.md` 8.4）

### 8.4 项目未采用项（明确标注）

- [ ] ~~GPU Instancing~~（未采用）
- [ ] ~~单通道 VR~~（未采用）
- [ ] ~~LOD_FADE_CROSSFADE~~（未采用）
- [ ] ~~`_SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A`~~（未采用）

---

## 九、总结

### 9.1 完整 Pass 架构（本项目 6 Pass）

```
MyLit.shader
└── SubShader
    ├── Pass 1: ForwardLit       (LightMode = UniversalForward)   PBR 主体
    ├── Pass 2: ShadowCaster     (LightMode = ShadowCaster)       阴影投射
    ├── Pass 3: Meta             (LightMode = Meta)               光照烘焙
    ├── Pass 4: DepthOnly        (LightMode = DepthOnly)          仅深度
    ├── Pass 5: DepthNormals     (LightMode = DepthNormals)       深度 + 法线
    └── Pass 6: MotionVectors    (LightMode = MotionVectors)      运动向量
```

### 9.2 本部分新增的认知

| 主题 | 要点 |
|---|---|
| 片段一致性 | DepthOnly / DepthNormals 必须与 ForwardLit 渲染同一片段集（镂空逻辑同步）|
| SSAO 集成 | Source 设为 Depth Normals；ForwardLit 必须补 `normalizedScreenSpaceUV` |
| SRP Batcher | 材质属性进 `UnityPerMaterial` CBUFFER；纹理在外 |
| Renderer Feature | URP 16 旧 `Execute` 已弃用；Render Graph 开启时不回调 |
| 优化 | Shader 层 + 构建层两层看；Stripping 只对 `multi_compile` 有意义 |

### 9.3 与原翻译稿的差异清单（备查）

| # | 原稿 | 本项目 |
|---|---|---|
| 1 | 把 DepthOnly / DepthNormals 当"新增"讲 | 项目已在 Part2 / Part5-七 完成，本部分改为回顾 |
| 2 | `_ALPHATEST_ON` | `_ALPHA_CUTOUT` |
| 3 | `_BumpMap` / `_NormalScale` | `_NormalMap` / `_NormalStrength` |
| 4 | 法线输出 `* 0.5 + 0.5` | `NormalizeNormalPerPixel`（SNorm）|
| 5 | 结构体 `*Varyings` | 统一 `Interpolators` |
| 6 | 大括号不换行 | 大括号换行 |
| 7 | CBUFFER 示例含 `_SurfaceType` 等 | 不在 CBUFFER，详见 4.3 |
| 8 | `LOD_FADE_CROSSFADE` / instancing / DOTS | 项目未采用 |
| 9 | Renderer Feature 旧 API 直接给 | 标注 URP 16 弃用 + Render Graph 变化 |
| 10 | 完整架构 5 Pass | 项目 6 Pass（含 MotionVectors）|

---

## 下一步

+ 按 `Part5-完整修改清单.md` 第七节，把 ⏳ 的场景验证项过一遍（含 SSAO、Motion Blur）
+ 进入 `07_自定义光照模型.md`：绕过 `UniversalFragmentPBR`，手写 BRDF

> 文档完。如有疑问，翻 `Docs/` 下的其他文档。
