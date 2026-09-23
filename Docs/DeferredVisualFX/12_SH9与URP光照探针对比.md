# 12 · SH9 环境光 vs URP 光照探针

> 目标：搞清参考项目的 SH9 与 URP 光照探针的关系，决定要不要移植。
> 参考项目：`Shaders/SH9/`、`Scripts/Environment/SH9Helpher.cs`

---

## 12.1 两者都是做什么的

**都是给物体提供"环境光 / 间接光"**——物体的暗部不该是纯黑，应有来自环境的颜色。

| 方案 | 数据 | 维度 |
|---|---|---|
| 参考项目 SH9 | 9 个球谐系数 | L2（9 系数）|
| URP Light Probe | 每个探针 27 个系数（3 色 × 9）| L2 |

**其实是同一套数学**——都是 SH L2。URP 叫 Light Probe，参考项目叫 SH9。

---

## 12.2 URP 光照探针怎么用

1. 场景里放 **Light Probe Group**（GameObject → Light → Light Probe Group）
2. 编辑探针位置
3. 烘焙：**Window → Rendering → Lighting → Generate Lighting**
4. 动态物体勾 **Mesh Renderer → Light Probes → Blend Probes**

着色器里**自动**读：

```hlsl
// URP 的 SampleSH
half3 sh = SampleSH(normalWS);
```

**不需要写任何代码。**

---

## 12.3 参考项目的 SH9 为什么要自己做

它自写 SRP，**没有 URP 的光照探针系统**。所以自己写：

- compute shader 从 cubemap 生成 SH9
- 全局变量 `_SH9[9]` 传给着色器
- 着色器里 `SH9(normal)` 重建

**对 URP 用户，这套是多余的**——URP 的 Light Probe 已经做了同样的事，而且有编辑器工具。

---

## 12.4 对比

| 项 | 参考项目 SH9 | URP Light Probe |
|---|---|---|
| 数据源 | 手填 cubemap | 场景烘焙 |
| 生成 | compute | 编辑器 |
| 每物体不同 | 否（全局）| 是（探针位置）|
| 编辑器支持 | 无 | 完整 |
| 着色器接口 | `SH9(normal)` | `SampleSH(normalWS)` |
| 是否值得移植 | ❌ | 用现成的 |

---

## 12.5 URP 的 SH 采样接口

```hlsl
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

// 顶点阶段（推荐，省算力）
half3 vertexSH = SampleSHVertex(normalWS);

// 片元阶段
half3 pixelSH = SampleSHPixel(vertexSH, normalWS);

// 直接
half3 sh = SampleSH(normalWS);
```

MyLit 项目已经用了 `SampleSHVertex` / `SampleSHPixel`（见 `MyLitForwardLitPass.hlsl`）。

---

## 12.6 如果非要移植 SH9（不推荐）

唯一可能的需求：**用一张自定义 cubemap 做全局环境光**，不走探针。

做法：

1. 保留 `SH9Generator.compute` / `SH9Reconstructor.compute`
2. 在 C# 里跑 compute，结果设成全局 `float4 _SH9[9]`
3. 着色器里用 `SH9(normal)` 代替 `SampleSH`

但**与 URP 的 Light Probe 会冲突**（两套环境光叠加）。除非完全关掉 Light Probe。

---

## 12.7 结论

| 你的目标 | 建议 |
|---|---|
| 一般环境光 | **用 URP Light Probe** |
| 自定义 cubemap 环境光 | 用 URP 的 **Reflection Probe** |
| 想学 SH 原理 | 读参考项目，但不必移植 |

**这一章的主要价值是"对齐认知"**：参考项目的 SH9 不是 URP 缺的功能，URP 有等价物。

---

## 12.8 验证

- URP 项目里放 Light Probe Group，烘焙后动态物体暗部有环境色
- 对照参考项目的 SH9 效果，应一致

---

## 12.9 与下一章的联系

环境光对齐了。最后一章：把前面所有内容汇总，给 MyLit 一份完整的 Deferred 改造路线图。

---

> 章节完。下一章 `13_MyLit完整改造路线图.md`。
