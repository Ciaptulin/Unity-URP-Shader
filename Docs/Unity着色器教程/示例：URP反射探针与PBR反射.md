# URP 反射探针与 PBR 反射

> **本节在整份教程中的位置**
> 这是一份「手写 URP PBR Shader」教程中的一节。所以全文会涉及两类完全不同的工作，混淆它们是本节最大的阅读障碍。下面用标签区分：
>
> - 🟦 **【场景】** — 摆放、配置、烘焙。不管用不用自定义 Shader 都要做。
> - 🟩 **【Shader】** — 写代码的人要做的事。结论是：本节几乎不用你写代码。
> - 🟪 **【原理】** — 底层实现。读懂即可，**不需要你自己写**，`UniversalFragmentPBR` 已经全包了。
>
> 本节涉及的代码文件：`Packages/com.unity.render-pipelines.universal/ShaderLibrary/EntityLighting.hlsl`、`ImageBasedLighting.hlsl`、`Lighting.hlsl`。

---

## 0. 这一节到底要解决什么问题

**问题**：Unity 默认用一张天空盒（Skybox）给全场景所有物体提供反射。天空盒假设全世界处于同一个「无限远的环境」中。于是你在室内放一个金属球，天花板和墙明明把天空挡住了，球上却反射出外面的蓝天——**穿帮**。

**方案**：反射探针（Reflection Probe）。在场景某点架一台 360° 相机拍一张全景快照（Cubemap），让附近的物体改用这张。

**一句话概括本节**：
> 探针解决「反射内容不对」，盒投影解决「反射位置不对」，粗糙度决定「反射清不清晰」，金属度决定「反射带不带颜色」。而你写的 Shader，只需要保留两个关键字，其余全交给 `UniversalFragmentPBR`。

---

## 1. 🟪 前置：反射从哪来（原文缺失的起点）

不先搞清楚这一层，后面所有内容都没有锚点。**物体的「环境贡献」是两笔独立的账**，原文的「反射的工作流程」把它们混着写了，这是最坑的地方：

| | **漫反射环境光**（Irradiance / GI） | **镜面反射**（Specular Reflection） |
|---|---|---|
| 采样依据 | **法线方向** | **反射向量**（视线 + 法线算出） |
| 数据来源 | 球谐函数 SH / **光照探针 Light Probe** | **Cubemap**（天空盒 或 反射探针） |
| 原文叫法 | 「环境光反射」 | 「镜面反射」 |
| 金属材质下 | **归零**（金属没有漫反射） | 承担全部亮度 |

### 由此推出本节最重要的一条

> **金属的漫反射是 0，画面亮度 100% 来自镜面反射。**

这解释了两件事：
1. 为什么「金属球发黑」这个坑特别常见于金属而非塑料——塑料还有 SH 兜底，金属没有。
2. 为什么验证反射效果一定要用金属球——它是唯一能纯粹暴露 Cubemap 内容的东西。

### 菲涅尔不是独立一步

原文把菲涅尔列成「流程第 3 步」，读起来像要自己算。**不需要**。菲涅尔已经包含在 BRDF 的 F 项（Schlick 近似）里，是 `UniversalFragmentPBR` 内部的事。

---

## 2. 🟦 反射探针是什么，为什么不够用

### 2.1 它做了什么

在场景某点 P 拍一张 Cubemap，附近物体反射时采样它，而不是天空盒那张全局图。

### 2.2 它的本质局限

探针记录的是「**从 P 点看到的**」世界，而不是「**从物体表面看到的**」。物体离 P 越远，误差越大——极端情况下物体会反射出它自己。

> 本节后面所有的优化手段（多探针、混合、盒投影、平面反射），全都是在补这一个洞。记住这条主线，后面的内容就是同一件事的层层递进。

### 2.3 三个硬限制（原文未提，但会直接决定你的布点策略）

| 限制 | 影响 |
|---|---|
| **每个物体最多同时用 2 个探针** | Unity 架构限制，Shader 里只有 `unity_SpecCube0` 和 `unity_SpecCube1` 两组变量。重叠再多的探针，也只有 2 个参与计算 |
| **Baked 探针只拍静态物体** | 只捕捉勾选了 `Reflection Probe Static` 的物体 |
| **盒子外回退天空盒** | 物体完全不在任何探针盒内时，回到天空盒 |

> ⚠️ 第一条才是「避免探针重叠过多」的**真正原因**——不是计算量问题，是**多出来的根本用不上**。三个盒子套娃，中间的物体只会用到其中两个，第三个纯属浪费。

---

## 3. 🟪➕🟦 Box Projection（盒投影）

### 3.1 默认做法错在哪

**无限投影（Infinite Projection）**：反射向量指向无穷远处的虚拟立方体，采样时**只用方向、忽略物体位置**。

后果：一个房间里并排两个金属球，它们朝向相同 → 反射向量相同 → **反射出的图案一模一样**。真实世界里两个球的倒影明显不同。这就是穿帮。

### 3.2 盒投影怎么修

把反射向量当成一条射线，**从物体表面位置出发**，求它与探针盒子边界的交点，改用「物体位置 → 交点」这个新向量采样。

> 效果有多强：**一个盒投影探针 ≈ 九个普通探针的视觉质量**。这是本节性价比最高的一步，务必开启。

### 3.3 启用机制（原文只说对了一半——实际是三道开关）

| 层级 | 开关 | 由谁决定 |
|---|---|---|
| ① 编译期 | Shader 的 `#pragma multi_compile` 里有 `_REFLECTION_PROBE_BOX_PROJECTION` | 写代码的人 |
| ② 运行期 | `unity_SpecCube0_ProbePosition.w > 0`，Unity 用 `if` 逐探针判断 | 探针 Inspector 上的 **Box Projection** 勾选框 |
| ③ 管线层 | **URP Asset** 里启用 Box Projection | 项目配置（**URP 特有**） |

**三道都要满足，缺一不生效。** 这解释了两个高频困惑：

- 「面板勾了盒投影，怎么没反应？」→ Shader 里没这个关键字（①）。
- 「关键字在，怎么还是没用？」→ 探针没勾（②），或 URP Asset 没开（③）。

### 3.4 关键前提：`positionWS` 必须正确

盒投影的计算依赖物体表面的世界坐标。**`InputData.positionWS` 填错或没填，盒投影直接失效**，而且没有任何报错，只是反射静静地变回无限投影的样子。

---

## 4. 🟦 放置策略与混合

### 4.1 URP 与内置管线的行为不同，请注意

**URP 是逐像素评估探针权重的**，内置管线是逐物体。URP 的规则：

| 像素位置 | 该探针权重 |
|---|---|
| 落在盒子**表面** | 0% |
| 深入内部、距各面**超过 Blend Distance** | 100% |
| 两个探针权重和 < 1 | **剩余部分回退给天空盒**（`_GlossyEnvironmentCubeMap`） |

### 4.2 放置策略

1. **覆盖整个场景**：关键区域各放一个，确保无死角。
2. **避免重叠过多**：不是性能问题——是超过 2 个也用不上（见 2.3）。
3. **室内/室外分离**：交界处放探针，避免室内反射到室外天空。
4. **高度变化**：多层建筑每层至少一个。

### 4.3 让混合真正生效的三个条件（原文缺失）

| # | 条件 | 说明 |
|---|---|---|
| 1 | **盒子必须真的重叠** | 光设 Importance 没用，边界不重叠就不会混合 |
| 2 | **Importance 必须相等** | 相等 → 等权混合；**不相等 → 直接用高的那个，完全不混合** |
| 3 | **`_REFLECTION_PROBE_BLENDING` 关键字在** | 否则整个混合分支不编译 |

> 💡 **Importance 的坑**：很多人以为 Importance 是「优先级 + 平滑过渡」，实际是「**优先级 或 等权过渡**」——只要不相等就是硬切换。

### 4.4 排查利器

选中 Mesh Renderer，**Inspector 底部会列出当前生效的探针 #0 / #1 及其权重**。混合对不对，一眼就能看出来。

### 4.5 混合权重存在哪

`unity_SpecCube0_BoxMin.w`。值为 **1** = 只用第一个探针；**小于 1** = 存在混合。

### 4.6 Mesh Renderer 上的反射设置

| 选项 | 行为 |
|---|---|
| **Off** | 完全忽略探针 |
| **Blend Probes** | 在探针间混合，但**不回退天空盒** → 移出所有探针范围时会硬切 |
| **Blend Probes And Skybox** | 混合并能平滑过渡到天空盒（推荐） |
| **Simple** | 不混合，硬切换 |

另外注意 **Anchor Override**：它会拽走采样锚点，导致物体用上完全不相干的探针。莫名其妙时先检查这项是否为 `None`。

---

## 5. 🟪 粗糙度如何影响反射

表面粗糙度决定反射清晰度：**光滑 → 锐利，粗糙 → 模糊**。机制是采样不同层级的 mipmap。

### 5.1 核心代码

```hlsl
half perceptualRoughness = 1.0 - smoothness;
half mip = PerceptualRoughnessToMipmapLevel(perceptualRoughness);

half4 encoded = SAMPLE_TEXTURECUBE_LOD(unity_SpecCube0, samplerunity_SpecCube0, reflectDir, mip);
half3 envColor = DecodeHDREnvironment(encoded, unity_SpecCube0_HDR);
```

### 5.2 三个补充细节

1. **传入的是感知粗糙度，不是物理粗糙度**
   - 感知粗糙度（perceptualRoughness）= `1 - smoothness`
   - 物理粗糙度（roughness）= `perceptualRoughness²`
   - 平方关系让模糊在**视觉上**均匀，而不是数值上均匀——这正是函数名叫 "Perceptual" 的原因。

2. **URP 内部还有一次重映射**，进一步保证视觉均匀：
   ```hlsl
   // URP 内部实现（了解即可）
   perceptualRoughness = perceptualRoughness * (1.7 - 0.7 * perceptualRoughness);
   return perceptualRoughness * UNITY_SPECCUBE_LOD_STEPS;
   ```

3. **模糊依赖 Cubemap 自身的 mip 链**
   Unity 生成探针时会预过滤出整条 mipmap。探针若丢失 mip 链，粗糙反射就会出错。

### 5.3 为什么必须 `DecodeHDREnvironment`

采样回来的是 **RGBM 编码**，需解码才能表达超过 1.0 的亮度（HDR）。**这就是 HDR 探针的意义**——保留高光能量，让金属反射能「亮过白」。

---

## 6. 🟩 金属表面的反射

### 6.1 为什么金属反射带颜色

`metallic = 1` 时：
- 漫反射归零
- **albedo 被当作 F0（基础反射率）直接给到镜面反射**

所以铜反射橙金色、金反射黄色——因为它们的 albedo 本身就是那个颜色。

### 6.2 常用金属 F0（直接填进 albedo）

| 材质 | Albedo (RGB) |
|---|---|
| 金 Gold | (1.00, 0.77, 0.34) |
| 铜 Copper | (0.95, 0.64, 0.54) |
| 铝 Aluminum | (0.91, 0.92, 0.92) |
| 银 Silver | (0.97, 0.96, 0.96) |
| 铁 Iron | (0.56, 0.57, 0.58) |

### 6.3 铁律

> **metallic 要么 0，要么 1。** 中间值物理上不存在，只应用于「金属/非金属过渡遮罩」（如生锈的铁）。乱给 0.5 会出现莫名的暗边。

---

## 7. 🟦 动手验证

1. 场景中放一个反射探针（Baked 或 Realtime 均可）。
2. 建一个球体，**Metallic = 1，Smoothness = 0.8~1**。
3. 观察球体是否反射出**周围环境**。

> ⚠️ **Smoothness 别忘了**。只把 Metallic 调到 1 而 Smoothness 很低，反射会被粗糙度糊掉，看着像「没反射」。

验收标准：金属球反射出的是**这个房间的墙**，而不是外面的天空。

---

## 8. 🟩 写 Shader 的人要做什么（原文重点，但结论是否定的）

### 8.1 结论：几乎什么都不用做

**不需要**添加任何新属性或新纹理。`UniversalFragmentPBR` 自动处理：

- 反射探针的采样
- 多探针混合（需 `_REFLECTION_PROBE_BLENDING`）
- Box Projection 修正（需 `_REFLECTION_PROBE_BOX_PROJECTION`）
- 粗糙度对反射模糊的影响

### 8.2 你要做的只有一件事：保住两个关键字

```hlsl
#pragma multi_compile _ _REFLECTION_PROBE_BLENDING
#pragma multi_compile _ _REFLECTION_PROBE_BOX_PROJECTION
```

> 在「附加光源」章节添加的关键字，到这里是必须保留的。**删掉任何一句，场景里摆再多的探针，对你的 Shader 也完全无效**——它会只认天空盒那一张图。

### 8.3 确保输入数据正确（`UniversalFragmentPBR` 的唯一要求）

```
SurfaceData :  albedo / specular / metallic / smoothness
InputData   :  normalWS / viewDirectionWS / positionWS
```

`positionWS` 最容易被忽略，但**盒投影必须靠它**（见 3.4）。

---

## 9. 🟪 更精确的反射方案（选型参考）

Cubemap 反射的根本缺陷是「**从探针位置看到的**」。水面、镜子这类要求精确反射的场景必须换方案。

| 方案 | URP 状态 | 适用 |
|---|---|---|
| **反射探针** | ✅ 内置 | 绝大多数场景，便宜 |
| **Planar Reflection** | ⚠️ **URP 无内置**（HDRP 有） | 水面、镜面地板 |
| **SSR 屏幕空间反射** | ⚠️ 官方实现较新版本才提供，老版本需第三方 | 通用实时反射 |

### Planar Reflection 原理

1. 创建**镜像摄像机**（沿反射平面翻转）
2. 渲染结果输出到 **Render Texture**
3. Shader 里用屏幕空间 UV 采样这张 RT

URP 下需自定义 Render Feature 实现（可参考 Unity 官方 Boat Attack 示例的 `PlanarReflections.cs`）。

### SSR 的固有局限

**只能拿到屏幕上的信息**。射线走出屏幕边缘、或射到物体背后时，信息不足 → **回退到反射探针或天空盒**。

> 所以 **SSR 不能替代探针**，两者是**叠加**关系：SSR 负责屏幕内的精确反射，探针负责屏幕外的兜底。

---

## 10. 🟪 原理：手动采样反射探针（读懂即可，不必自己写）

### 10.1 ⚠️ 原文代码有三处错误

原文片段：

```hlsl
float3 boxCenter = unity_SpecCube0_BoxMin;   // ❌ 错误 1
...
posWS += reflectDir * dist;                  // ❌ 错误 2
SAMPLE_TEXTURECUBE_LOD(..., reflectDir, mip) // ❌ 错误 3
```

| # | 问题 | 后果 |
|---|---|---|
| 1 | 中心取错了变量，应为 `unity_SpecCube0_ProbePosition.xyz` | 坐标系原点错误 |
| 2 | 没减去探针中心 | 盒投影结果必须是**相对探针中心的方向**，不是世界坐标 |
| 3 | 采样时用的是未修正的 `reflectDir` | **前两步白算**，行为退回无限投影 |

### 10.2 修正版

```hlsl
// ── 1. 计算反射向量 ────────────────────────────────
float3 reflectDir = reflect(-viewDirWS, normalWS);

// ── 2. Box Projection 修正 ─────────────────────────
//     编译期关键字控制这段代码是否存在；
//     运行期由 cubemapCenter.w 判断「这个探针是否开了盒投影」
float3 BoxProjectedCubemapDirection(
    float3 reflectionWS, float3 positionWS,
    float4 cubemapCenter, float4 boxMin, float4 boxMax)
{
    if (cubemapCenter.w > 0.0)   // ← 该探针勾了 Box Projection 吗
    {
        // 按方向符号直接选远端面，避免除以 0 产生 NaN
        float3 boxMinMax = (reflectionWS > 0.0) ? boxMax.xyz : boxMin.xyz;
        float3 rbMinMax  = (boxMinMax - positionWS) / reflectionWS;
        float  fa        = min(min(rbMinMax.x, rbMinMax.y), rbMinMax.z);

        float3 worldPos = positionWS - cubemapCenter.xyz;  // ← 关键：相对中心
        return worldPos + reflectionWS * fa;               // ← 返回方向，非坐标
    }
    return reflectionWS;
}

reflectDir = BoxProjectedCubemapDirection(
    reflectDir, positionWS,
    unity_SpecCube0_ProbePosition,
    unity_SpecCube0_BoxMin,
    unity_SpecCube0_BoxMax);

// ── 3. 由粗糙度算出 mip 等级 ───────────────────────
half perceptualRoughness = 1.0 - smoothness;
half mip = PerceptualRoughnessToMipmapLevel(perceptualRoughness);

// ── 4. 采样并解码 HDR ──────────────────────────────
half4 encoded = SAMPLE_TEXTURECUBE_LOD(
    unity_SpecCube0, samplerunity_SpecCube0, reflectDir, mip);
half3 envColor = DecodeHDREnvironment(encoded, unity_SpecCube0_HDR);
```

### 10.3 两个实现细节

**为什么用三元运算符而不是原文的 `max(intersectMax, intersectMin)`**
反射向量某分量为 0 时，除法产生 inf/NaN，会污染 `min()` 的结果。按符号直接选面更稳。

**第二探针的采样器**
Shader 里只有 `samplerunity_SpecCube0` 一个采样器，没有 `samplerunity_SpecCube1`。采样第二探针时必须复用第一个的采样器：

```hlsl
// 错误 —— samplerunity_SpecCube1 不存在
UNITY_PASS_TEXCUBE(unity_SpecCube1)

// 正确 —— 组合第二探针的纹理 + 第一探针的采样器
UNITY_PASS_TEXCUBE_SAMPLER(unity_SpecCube1, unity_SpecCube0)
```

---

## 11. 🟦 坑点排查表

| 现象 | 排查方向 |
|---|---|
| **探针不更新** | 先分清类型：**Baked 不更新是设计如此**，改了场景要重新 Generate Lighting。只有 Realtime 才谈刷新，且 Refresh Mode 不能是 `On Awake` |
| **反射扭曲拉伸** | Box Size / Box Offset 没贴合房间墙体。盒投影的盒子必须与实际房间吻合 |
| **反射过亮 / 过暗** | 探针的 HDR 开关 + Intensity；还有 Lighting 窗口 `Environment Reflections > Intensity Multiplier` |
| **金属表面发黑** | 场景无探针**且**无天空盒；或是 Baked 探针没烘焙 |
| **物体完全不受探针影响** | Mesh Renderer 的 **Reflection Probes** 下拉是否为 `Off`；锚点是否被 **Anchor Override** 拽走 |
| **混合不生效** | 盒子必须真重叠 + 两探针 Importance **相等** + `_REFLECTION_PROBE_BLENDING` 关键字在 |
| **URP 下盒投影无效** | 三道开关：探针勾选 + Shader 关键字 + **URP Asset 里启用** |
| **Baked 探针烘焙出来是空的** | 周围物体没勾 `Reflection Probe Static` |

---

## 12. 本节结论：落到项目上的检查清单

| 步骤 | 位置 | 耗时 |
|---|---|---|
| ① 保留两个 `multi_compile` 关键字 | Shader | 30 秒 |
| ② URP Asset 里启用 Box Projection | 管线配置 | 10 秒 |
| ③ 每个封闭区域放一个 Baked 探针，勾 Box Projection，Box Size 贴合房间 | 场景 | **主要工作量** |
| ④ 静态物体勾选 `Reflection Probe Static` | 场景 | — |
| ⑤ `Window > Rendering > Lighting` → Generate Lighting | 编辑器 | — |
| ⑥ 丢金属球（Metallic=1, Smoothness≈0.95）验收 | 场景 | — |

> **时间分配提示**：第 8 节（Shader 侧）文字量最大、看着最深，但在实际操作中占用的时间是**零**——检查关键字在不在而已。真正花时间的是③⑤这些场景侧的脏活。别被篇幅误导，把精力放对地方。
