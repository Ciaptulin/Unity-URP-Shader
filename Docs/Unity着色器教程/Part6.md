# Part 6 · 屏幕空间效果、后处理与自定义渲染 Pass

> **本节在整份教程中的位置**
> Part 5 结束时，`MyLit` 已经能读取场景的完整光照数据了。但还有一整类效果**不在材质里实现**——它们拿整个屏幕（或整个场景深度）当输入，在管线里"插一脚"完成。
>
> 本节涉及三类工作：
>
> - 🟦 **【场景】** — Renderer Data 里加 Feature、Volume 里加 Override。不写代码。
> - 🟩 **【Shader】** — 补 Pass、补字段、写全屏 Shader。
> - 🟪 **【原理】** — 算法理解。URP 已经实现好的部分，读懂即可。
>
> **版本基准：Unity 2023.2.20f1 / URP 16.0.6。**
> 这一节要特别小心：旧版教程里有一整章"URP 中 SSR Renderer Feature 的配置"和相应的参数表——**URP 16 根本没有内置 SSR**，那些参数是凭空写出来的。本节会把它纠正掉。

---

## 0. 这一节到底要解决什么问题

**问题**：SSAO、Bloom、运动模糊这些效果不是"某个材质的属性"，而是"**对已渲染画面做的二次处理**"。它们要么需要屏幕深度/法线，要么需要把画面再画一遍。你的 Shader 在其中扮演的角色只有两种：

| 角色 | 你要做的事 |
|---|---|
| **数据提供方** | 提供正确的法线（DepthNormals Pass）、屏幕 UV、运动向量 |
| **被执行方** | 提供一个额外的 Pass，让自定义 Feature 能把你再画一遍 |

**一句话概括本节**：
> 你在这一节里写的**不是材质代码**，而是"让 URP 的其他系统能读懂你的材质"的配套代码，以及可选的管线扩展代码。

---

## 1. 🟪➕🟦 SSAO

### 1.1 它解决什么

环境光是"从四面八方均匀照过来"的——这个假设在墙角、缝隙、物体交叠处是错的：那些地方被周围几何体挡住，收到的环境光更少。SSAO 就是在**渲染完成后**，用深度+法线反推这些缝隙，把环境光压暗。

### 1.2 原理（🟪，了解即可）

对每个像素：

1. 以该像素为中心、法线为轴，构造一个**采样半球**；
2. 在半球内取 N 个采样点（URP 用 Blue Noise 或 Interleaved Gradient Noise 生成）；
3. 把每个采样点投影回屏幕，读深度缓冲，比较"采样点的深度"与"深度缓冲记录的场景深度"；
4. 采样点被挡住得越多 → 遮挡值越高 → 环境光乘的系数越小。

关键参数（对应 URP 的真实字段，见 1.4）：

- **Radius** 决定半球多大：太大会把远处的几何也算进来，出现" halo "；太小则只捕捉到极细的缝。
- **Falloff** 决定距离衰减：让远处的采样点权重更低。
- **Intensity** 只是最后对遮挡值做的幂/对比度调整，不改物理含义。

### 1.3 它的数据从哪来（🟩 重点）

URP 的 SSAO 需要从两张纹理里取数据：

| 数据 | 来源 | 你的材质需要 |
|---|---|---|
| 深度 | 深度缓冲（或 `_CameraDepthTexture`） | 正常写深度即可（不透明物体默认写） |
| 世界法线 | `_CameraNormalsTexture` | **DepthNormals Pass**（见 Part 5 §6.2） |

所以 SSAO 在你的材质上"没反应"，99% 是这两个原因之一：

1. 没有 DepthNormals Pass → 法线纹理里根本没有你的物体；
2. 有 Pass，但 **`InputData.normalizedScreenSpaceUV` 没填** → AO 纹理采样位置固定在 (0,0)。

```hlsl
// Fragment 中，调用 UniversalFragmentPBR 之前
lightingInput.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(input.positionCS);
```

### 1.4 🟦 配置（URP 16 的真实参数）

`Renderer Data → Add Renderer Feature → Screen Space Ambient Occlusion`。

| 参数 | 含义 | 备注 |
|---|---|---|
| **Method** | `Blue Noise` / `Interleaved Gradient` | 采样点生成方式 |
| **Downsample** | 半分辨率计算 | 性能首选，移动端建议开 |
| **After Opaque** | 在不透明物体之后执行 | 关掉可以少一次深度拷贝 |
| **Source** | `Depth` / `DepthNormals` | 选 `DepthNormals` 时必须有 DepthNormals Pass；选 `Depth` 则从深度重建法线（质量低但不需要额外 Pass） |
| **Normal Quality** | 法线采样质量 Low/Medium/High | 只在 `Source = Depth` 时影响重建精度 |
| **Intensity** | 强度 | 默认 3.0 |
| **Direct Lighting Strength** | AO 对**直接光**的影响比例 | 默认 0.25；PBR 里一般保持较低 |
| **Radius** | 采样半径 | 默认 0.035，场景尺度大时要调大 |
| **Samples** | Low / Medium / High | 采样点数 |
| **Blur Quality** | 模糊质量 | 抑制噪点 |
| **Falloff** | 距离衰减 | 默认 100 |

### 1.5 SSAO 与遮挡贴图的组合（🟪，纠正旧版错误）

旧版教程说"最终遮挡 = 贴图 AO × SSAO"。**URP 16 用的是 `min`**：

```hlsl
// AmbientOcclusion.hlsl
aoFactor.indirectAmbientOcclusion = min(aoFactor.indirectAmbientOcclusion, occlusion);
```

这更符合直觉：两处都说"这里被挡了 30%"，正确结果应该是"被挡 30%"，而不是"被挡 51%"。

| | 贴图 AO | SSAO |
|---|---|---|
| 尺度 | 物体自身的褶皱、缝隙（高频） | 物体之间的接触、角落（低频） |
| 来源 | 美术烘焙 | 实时深度 |
| 动态物体间遮挡 | ❌ 不支持 | ✅ 支持 |

两者是**互补**关系，都要。

---

## 2. SSR（屏幕空间反射）

### 2.1 ⚠️ 先说结论：URP 16 没有内置 SSR

URP 16.0.6 的 `Runtime/RendererFeatures/` 目录里只有这些：

```
DecalRendererFeature.cs
FullScreenPassRendererFeature.cs
RenderObjects.cs
ScreenSpaceAmbientOcclusion.cs
ScreenSpaceShadows.cs
```

**没有 `ScreenSpaceReflections`。** 所以：

- 旧版教程里那张"SSR 参数详解"表（Max Distance / Step Count / Thickness / Smoothness Threshold …）**在 URP 16 里不存在**，那是 HDRP 的参数；
- 也不要去 Renderer Data 里找"Screen Space Reflections"这个 Feature，找不到是正常的。

### 2.2 原理（🟪）

SSR 用**射线步进（Ray Marching）**：

1. 由 `reflect(-viewDir, normal)` 得到反射方向（URP 里还会用粗糙度做抖动）；
2. 从表面点出发，沿该方向一步步前进；
3. 每步投影到屏幕空间，把射线深度与深度缓冲比较；
4. 射线深度 > 场景深度 → 判定相交，二分细化后取该屏幕位置的颜色；
5. 走出屏幕 / 超过步数 → 失败，回退反射探针或天空盒。

**根本限制**：只能用屏幕上的信息。屏幕外、物体背面、被遮挡区域一律没有数据。

> **所以 SSR 从来不是反射探针的替代品，而是叠加层**：屏幕内的精确反射归 SSR，屏幕外归探针。

### 2.3 选型参考

| 需求 | 方案 | URP 16 状态 |
|---|---|---|
| 绝大多数场景 | 反射探针 | ✅ 内置（见反射探针专文） |
| 水面、镜面地板 | 平面反射（镜像相机 + RT） | ⚠️ 需自定义 Render Feature |
| 通用实时反射 | SSR | ⚠️ 需自定义 Render Feature 或第三方插件 |
| 移动端 | 仅反射探针 | — |

自己实现 SSR 时，你的材质需要提供给它的数据：**法线**（DepthNormals Pass）、**深度**、**平滑度**（决定抖动强度）。前两个已经有了，平滑度通常需要额外渲染一张 GBuffer——这也是 URP 迟迟没有内置 SSR 的原因之一（前向渲染拿不到便宜的 GBuffer）。

---

## 3. 🟦 后处理（Volume 系统）

后处理与你的 Shader 的关系很松：**它们在你的片元函数输出之后运行**，只是拿到一张颜色纹理做事。

### 3.1 Volume 系统

| 概念 | 说明 |
|---|---|
| **Volume 组件** | 挂在场景对象上，持有一个 Profile |
| **Profile** | 一组 Override（Bloom / Tonemapping / Color Adjustments …） |
| **Global Volume** | `isGlobal = true`，影响整个场景 |
| **Local Volume** | 需要 Collider 定义范围，按 `Blend Distance` 平滑过渡 |
| **Priority** | 多个 Volume 重叠时，优先级高的生效 |

🟩 与 Shader 有关的只有一点：后处理是**逐相机**的，你的材质不需要为它做任何适配。

### 3.2 HDR：Bloom 的前提

Bloom 的工作方式是"提取亮度超过 Threshold 的像素 → 模糊 → 加回去"。如果颜色被限制在 [0,1]，就只有纯白区域能参与，效果会很生硬。

需要三处都打开：

1. **URP Asset** → Quality → HDR：开；
2. **Camera** → Allow HDR（URP 下由 URP Asset 控制，HDR 关掉时相机会自动降级）；
3. **材质侧**：自发光颜色要能 > 1（项目里 `_EmissionTint` 已标 `[HDR]`）。

```hlsl
surfaceInput.emission = SAMPLE_TEXTURE2D(_EmissionMap, sampler_EmissionMap, uv).rgb * _EmissionTint;
```

> 💡 自发光配 Bloom 是"最便宜的炫技"：把 `_EmissionTint` 的强度调到 2~5，再在 Volume 里加一个 Threshold ≈ 1.0 的 Bloom，立刻有辉光。

### 3.3 色调映射（Tonemapping）

HDR 值最终要压回显示器能显示的 [0,1]。URP 提供：

- **Neutral**：保留颜色，适合需要准确配色的项目；
- **ACES**：电影感，高对比，暗部更沉。

**它会改变你所有颜色的最终呈现**——调材质颜色时如果开着 ACES 调，关掉后颜色会"跑"。建议定好 Tonemapping 再调色。

### 3.4 需要深度的后处理

景深、运动模糊这类需要深度纹理。URP Asset → General → **Depth Texture** 打开后，Shader 里可以：

```hlsl
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

float rawDepth = SampleSceneDepth(screenUV);          // 原始深度
float linear01 = Linear01Depth(rawDepth, _ZBufferParams); // 线性化到 [0,1]
```

> ⚠️ 采样必须用**归一化屏幕 UV**（`GetNormalizedScreenSpaceUV(positionCS)`），不是模型 UV。这和 SSAO 是同一套坐标。

---

## 4. 🟩 自定义 Renderer Feature

### 4.1 什么时候需要它

- 想在整个场景上做一次全屏效果（自定义后处理、扫描线、屏幕空间扭曲）；
- 想用特殊材质把某些物体**再画一遍**（描边、轮廓、遮挡高亮）；
- 想在某个时机往 RT 里写自定义数据。

如果只想要一个全屏效果，**先试 URP 自带的 `Full Screen Pass Renderer Feature`**——它接受一个材质和一个插入点，不需要写 C#。只有需要多 RT、多 Pass、依赖深度或按 Layer 过滤时，才自己写。

### 4.2 结构与生命周期（URP 16）

```csharp
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class MyRenderFeature : ScriptableRendererFeature
{
    [System.Serializable]
    public class Settings
    {
        public RenderPassEvent passEvent = RenderPassEvent.BeforeRenderingPostProcessing;
        public Material material;
    }

    public Settings settings = new Settings();
    private MyRenderPass pass;

    public override void Create()          // 只调用一次
    {
        pass = new MyRenderPass(settings);
        pass.renderPassEvent = settings.passEvent;
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        // 预览相机、材质缺失、后处理关闭 → 直接不加入队列
        if (settings.material == null) return;
        if (renderingData.cameraData.isPreviewCamera) return;

        pass.Setup(renderer);
        renderer.EnqueuePass(pass);
    }

    protected override void Dispose(bool disposing) => pass?.Cleanup();

    // ---------------- Pass ----------------
    class MyRenderPass : ScriptableRenderPass
    {
        private readonly Settings m_Settings;
        private readonly ProfilingSampler m_Profiler = new ProfilingSampler("MyRenderPass");
        private RTHandle m_Source;
        private RTHandle m_Temp;

        public MyRenderPass(Settings s) => m_Settings = s;

        public void Setup(ScriptableRenderer renderer)
        {
            m_Source = renderer.cameraColorTargetHandle;
        }

        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            var desc = renderingData.cameraData.cameraTargetDescriptor;
            desc.depthBufferBits = 0;                      // 全屏 Pass 不需要深度
            RenderingUtils.ReAllocateIfNeeded(ref m_Temp, desc, FilterMode.Bilinear, name: "_MyTemp");
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            CommandBuffer cmd = CommandBufferPool.Get();
            using (new ProfilingScope(cmd, m_Profiler))
            {
                // 源与目标不能是同一个 RT，用临时 RT 中转
                Blitter.BlitCameraTexture(cmd, m_Source, m_Temp, m_Settings.material, 0);
                Blitter.BlitCameraTexture(cmd, m_Temp, m_Source, 0);
            }
            context.ExecuteCommandBuffer(cmd);
            CommandBufferPool.Release(cmd);
        }

        public void Cleanup() => m_Temp?.Release();
    }
}
```

配套的材质必须是一个"全屏 Shader"：

```hlsl
Shader "Hidden/MyFullScreen"
{
    SubShader
    {
        Tags { "RenderPipeline" = "UniversalPipeline" }
        Pass
        {
            ZWrite Off
            ZTest Always      // 必须 Always，否则会被深度剔除
            Cull Off
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            float _Intensity;

            float4 Frag(Varyings input) : SV_Target
            {
                float4 col = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_BlitTexture, input.texcoord);
                return col * _Intensity;
            }
            ENDHLSL
        }
    }
}
```

以下是项目中的完整实现代码：

```csharp
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

/// <summary>
/// Part 6 示例：一个最小可用的全屏 Renderer Feature。
/// 用法：Renderer Data → Add Renderer Feature → 选 Custom Full Screen Feature → 拖入使用
/// Hidden/CustomFullScreen 的材质。
/// </summary>
public class CustomFullScreenFeature : ScriptableRendererFeature
{
    [System.Serializable]
    public class Settings
    {
        public RenderPassEvent passEvent = RenderPassEvent.BeforeRenderingPostProcessing;
        public Material material;
        [Range(0f, 2f)] public float intensity = 1.0f;
    }

    public Settings settings = new Settings();

    private CustomFullScreenPass m_Pass;

    // 只调用一次：创建 Pass 实例
    public override void Create()
    {
        m_Pass = new CustomFullScreenPass(settings);
        m_Pass.renderPassEvent = settings.passEvent;
    }

    // 每帧调用：决定要不要把这个 Pass 排进队列
    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        if (settings.material == null)
            return;

        // 场景视图小窗、材质预览等都不需要处理
        if (renderingData.cameraData.isPreviewCamera)
            return;

        m_Pass.Setup(renderer);
        renderer.EnqueuePass(m_Pass);
    }

    protected override void Dispose(bool disposing)
    {
        m_Pass?.Cleanup();
    }

    // ---------------- Pass ----------------
    private class CustomFullScreenPass : ScriptableRenderPass
    {
        private readonly Settings m_Settings;
        private readonly ProfilingSampler m_Profiler = new ProfilingSampler("Custom Full Screen");
        private static readonly int IntensityID = Shader.PropertyToID("_Intensity");

        private RTHandle m_Source;
        private RTHandle m_Temp;

        public CustomFullScreenPass(Settings settings)
        {
            m_Settings = settings;
        }

        // 在 Execute 之前拿不到相机颜色目标，所以放在这里取
        public void Setup(ScriptableRenderer renderer)
        {
            m_Source = renderer.cameraColorTargetHandle;
        }

        // 分配临时 RT；只在尺寸/格式变化时真正重新分配
        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            RenderTextureDescriptor desc = renderingData.cameraData.cameraTargetDescriptor;
            desc.depthBufferBits = 0;   // 全屏 Pass 不需要深度缓冲

            RenderingUtils.ReAllocateIfNeeded(
                ref m_Temp, desc, filterMode: FilterMode.Bilinear, name: "_CustomFullScreenTemp");
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            if (m_Settings.material == null)
                return;

            CommandBuffer cmd = CommandBufferPool.Get();
            using (new ProfilingScope(cmd, m_Profiler))
            {
                m_Settings.material.SetFloat(IntensityID, m_Settings.intensity);

                // 源和目标不能是同一个 RT，必须经临时 RT 中转
                Blitter.BlitCameraTexture(cmd, m_Source, m_Temp, m_Settings.material, 0);
                Blitter.BlitCameraTexture(cmd, m_Temp, m_Source, 0);
            }

            context.ExecuteCommandBuffer(cmd);
            CommandBufferPool.Release(cmd);
        }

        public void Cleanup()
        {
            m_Temp?.Release();
        }
    }
}
```

```hlsl
Shader "Hidden/CustomFullScreen"
{
    SubShader
    {
        Tags { "RenderPipeline" = "UniversalPipeline" }

        Pass
        {
            Name "CustomFullScreen"

            // 全屏 Pass 三件套：不写深度、不做深度测试、不剔面
            ZWrite Off
            ZTest Always
            Cull Off

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag

            // Core.hlsl 提供 XR 相关依赖；Blit.hlsl 提供 Varyings / Vert / _BlitTexture / FragBlit
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            float  _Intensity;
            float4 _Tint;

            float4 Frag(Varyings input) : SV_Target
            {
                // FragBlit 是 Blit.hlsl 提供的辅助函数，内部处理了 XR / 数组纹理的差异
                float4 color = FragBlit(input, sampler_LinearClamp);

                color.rgb *= _Intensity;
                color.rgb = lerp(color.rgb, color.rgb * _Tint.rgb, _Tint.a);

                return color;
            }
            ENDHLSL
        }
    }
}
```

### 4.3 插入点怎么选

| RenderPassEvent | 时机 | 典型用途 |
|---|---|---|
| `AfterRenderingOpaques` | 不透明物体之后 | 描边、遮挡高亮（透明物体还没画） |
| `AfterRenderingSkybox` | 天空盒之后 | 基于完整背景的效果 |
| `BeforeRenderingTransparents` | 透明物体之前 | 水面扭曲（需要背景，又要在透明之前） |
| `BeforeRenderingPostProcessing` | 内置后处理之前 | 自定义后处理 |
| `AfterRenderingPostProcessing` | 全部之后 | UI 叠加、最终调色 |

### 4.4 三个必踩的坑

1. **源与目标不能是同一个 RT**：`Blitter.BlitCameraTexture(cmd, src, src, mat)` 结果未定义。必须用一个临时 RT 中转两次。
2. **全屏材质的 `ZTest Always`**：默认 `ZTest LEqual` 会让你什么也看不见。
3. **`ReAllocateIfNeeded` 而不是 `new RTHandle`**：前者只在尺寸变化时重建，后者每帧分配显存。

> 🚩 **升级提示**：本节的 `Execute()` 是 URP 16 的经典写法。Unity 6（URP 17）起 Render Graph 成为默认路径，`ScriptableRenderPass` 要改写成 `RecordRenderGraph()`。现在写的 Feature 在升级时需要迁移——不是 bug，是 API 换代。

### 4.5 描边：用 RenderObjects 更省事

如果只是想"用另一个材质把某些物体再画一遍"，URP 自带的 **Render Objects** Feature 就够了：设置 Layer Mask、覆盖材质、插入点，零代码。

经典的"背面外扩描边"材质关键两行：

```hlsl
Cull Front                                  // 只画背面
float3 pos = input.positionOS + input.normalOS * _OutlineWidth; // 沿法线外扩
```

> ⚠️ 用这种方式做描边时，**外扩用的是模型法线**。硬边模型（如立方体）法线不连续，描边会在棱角处断开——需要在建模软件里做平滑法线，或把平滑法线存到另一套 UV/顶点色里。

---

## 5. 调试

### 5.1 Rendering Debugger（`Window > Analysis > Rendering Debugger`）

| 位置 | 用途 |
|---|---|
| **Lighting** → Lighting Debug Modes | 关阴影 / 关环境光 / 关反射，用于隔离问题 |
| **Material** → Albedo / Specular / Smoothness / Normal | 看材质各通道输出 |
| **Rendering** → Depth / Normal Texture / Motion Vectors / Overdraw | 看管线中间纹理 |

几个快速判断：

- **Normal Texture 全屏一个颜色** → 你的材质没写 DepthNormals Pass，或法线编码错（Part 5 §6.2）；
- **Depth 全黑** → URP Asset 没开 Depth Texture，或近/远裁剪面设置不合理；
- **Overdraw 大面积发亮** → 透明物体叠加过多；
- **Material 面板报 "not SRP Batcher compatible"** → 材质属性没全放进 `UnityPerMaterial` CBUFFER。

### 5.2 Frame Debugger（`Window > Analysis > Frame Debugger`）

按 Pass 逐条看：DepthOnly → DepthNormals → Shadow → Opaque → Transparent → PostProcessing。

用法要点：

- 在列表里找不到你的 Pass → 检查 `LightMode` 标签拼写；
- 某个 DrawCall 的关键字组合不对 → 点开看 Shader 名后面的关键字列表；
- 想确认"这个 Feature 到底跑没跑" → 在列表里搜 ProfilingSampler 的名字。

### 5.3 项目里自带的调试开关

`MyLit.shader` 里留了一个 `_DEBUG_BAKED_GI` 关键字，配合自定义 Inspector 可以直接把 `bakedGI` 输出成灰度图。这是"临时把中间量画出来"的标准做法——遇到可疑的中间值，就加一个关键字把它 `return` 出来。

---

## 6. 性能

| 项 | 说明 |
|---|---|
| **DepthNormals Pass** | 多一遍全场景几何绘制。SSAO 不需要时可以从 Shader 里去掉这个 Pass |
| **SSAO** | 半分辨率 + 低采样 ≈ 0.5ms；全分辨率 + 高采样可达 2~3ms（1080p）。移动端建议 Downsample |
| **SSR** | 最贵的一项，通常 2~7ms。移动端基本不用 |
| **Bloom** | 便宜（0.2~0.5ms），性价比极高 |
| **自定义全屏 Pass** | 每加一个就是一次全屏读写，注意合并 |
| **变体数量** | 每多一个 `multi_compile` 关键字，编译时间和包体翻倍增长 |

三条实用建议：

1. **按质量档分 URP Asset**：项目里已有 Performant / Balanced / HighFidelity 三套，把 SSAO、阴影、HDR 按档位配置，而不是在 Shader 里做分支。
2. **能用 `shader_feature` 就别用 `multi_compile`**：材质级开关用 `shader_feature_local`，只有被引擎全局控制的关键字（光源、阴影、探针）才用 `multi_compile`。
3. **不要提前加 Pass**：MotionVectors 这类 Pass，等真的需要运动模糊时再加。

---

## 7. 本节结论：落到项目上的检查清单

| # | 项目 | 位置 | 状态 |
|---|---|---|---|
| ① | 给 `InputData.normalizedScreenSpaceUV` 赋值 | `MyLitForwardLitPass.hlsl` | ❌ 缺失（SSAO 必需） |
| ② | DepthNormals Pass 已存在且标签为 `DepthNormals` | `MyLit.shader` | ✅ 已有 |
| ③ | Renderer Data 添加 SSAO Feature，Source 选 `DepthNormals` | Settings | 🟦 待配 |
| ④ | URP Asset 开启 Depth Texture（若用景深/运动模糊） | Settings | 🟦 待配 |
| ⑤ | 确认项目不使用内置 SSR（URP 16 没有），需要则另做 | — | ✅ 已知 |
| ⑥ | Volume：Bloom + Tonemapping（HDR 开启） | 场景 | 🟦 待配 |
| ⑦ | RendererFeature 用 `Execute` 老 API，升级 Unity 6 需迁移 | 自定义代码 | 🚩 备注 |

---

## 小结

- 屏幕空间效果依赖**你提供的数据**（法线、深度、屏幕 UV），不依赖你的光照代码。
- URP 16 **没有内置 SSR**，别去找那个 Feature。
- 自定义管线扩展优先用现成的 `Full Screen Pass` / `Render Objects`，实在不够再写 `ScriptableRendererFeature`。
- 调试靠 Rendering Debugger 看纹理、Frame Debugger 看 Pass 顺序。

下一节（Part 7）我们回到着色器内部，把 `UniversalFragmentPBR` 换成自己写的 BRDF——真正开始写数学。
