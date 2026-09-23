# MyLit 延迟渲染与视觉效果复刻 —— 教程总纲

> 目标项目：`Unity URP Shader`（URP 16.0.6 + Unity 2023.2.20f1，已有 Custom/MyLit 六 Pass 前向着色器）
> 教程定位：**保持 URP**，把参考项目 `CustomSRP_Deferred_PBR` 的视觉效果逐个复刻进来
> 重要：本教程**只写教程，不改动现有代码**。所有代码均为"如果你想做，这样写"的指导
> 参考项目路径：`D:/Code/Technical-Artist-Portfolio/TA-Portfolio-Repo/CustomSRP_Deferred_PBR`

---

## 前提：两条路线的取舍

参考项目是**自写 SRP**，它的 GBuffer 布局和延迟光照循环是**自己定死的**。URP 不允许替换这些。所以：

| 参考项目功能 | 在 URP 能否复刻 | 怎么做 |
|---|---|---|
| 延迟渲染路径 | ✅ 但布局不同 | 用 URP 自带 Deferred，写 `UniversalGBuffer` Pass |
| 自写 5-RT GBuffer | ❌ | URP 的 GBuffer 是固定的 |
| 自写延迟光照循环 | ❌ | URP 内部完成 |
| SSAO / SSR / Bloom | ✅ | URP 内置 或 自写 Renderer Feature |
| 卡通角色光照 | ✅ | shader 层移植（与管线无关）|
| 粒子光照 / 双层材质 / 水面 | ✅ | shader 层移植（与管线无关）|
| SH9 环境光 | ⚠️ 部分 | URP 用 Light Probe（L2），已有等效 |
| 体积云 | ✅ | Renderer Feature 自写 |

**结论**：与管线强绑定的部分用 URP 等价物替代；与管线无关的 shader 逐个移植。

---

## 章节规划

### 第一部分：理解 URP 延迟路径

| 章 | 标题 | 产出 |
|---|---|---|
| 01 | URP 的 Forward / Deferred / Forward+ 三条路 | 概念 + 选择依据 |
| 02 | URP GBuffer 布局详解 | 与参考项目 5-RT 布局的对照 |
| 03 | 让 MyLit 支持 Deferred | 新增 `UniversalGBuffer` Pass 的写法（教程性质，不改代码）|

### 第二部分：屏幕空间效果（Renderer Feature 路线）

| 章 | 标题 | 产出 |
|---|---|---|
| 04 | URP 里做 SSAO | 内置 SSAO 配置 + 自写版原理 |
| 05 | URP 里做 SSR | Renderer Feature + 光线步进 |
| 06 | URP 里做 Bloom | Volume 内置 + 自写版原理 |
| 07 | URP 里做体积云 | Renderer Feature + 光线步进 |

### 第三部分：特殊材质（Shader 层移植）

| 章 | 标题 | 产出 |
|---|---|---|
| 08 | 卡通角色光照 | 移植 `CharacterToonLighting.hlsl` 到 URP |
| 09 | 粒子光照 | 移植 `ParticleLighting.hlsl` |
| 10 | 双层材质 | 移植 `StandardLayer`（雪/苔藓效果）|
| 11 | 水面 | 移植 `Pond` |

### 第四部分：进阶

| 章 | 标题 | 产出 |
|---|---|---|
| 12 | SH9 环境光 vs URP Light Probe | 对比与取舍 |
| 13 | URP Deferred 下的 MyLit 完整改造 | 汇总：GBuffer + 透明 + 特效共存 |

---

## 每章的固定结构

1. **目标** —— 学完能做什么
2. **参考项目的做法** —— 它是怎么实现的（贴关键代码）
3. **URP 的对应方案** —— 为什么这样替代，差异在哪
4. **具体步骤** —— 分步指导（教程性质，不改现有代码）
5. **验证方法** —— 怎么确认对了
6. **风险与坑** —— 易错点

---

## 与现有教程的关系

- `Part1.md` ~ `Part9.md`：URP 自定义着色器基础（已完成）
- 本系列：在此之上，进入**延迟渲染 + 屏幕空间效果 + 特殊材质**

---

> 总纲完。逐章正文见同目录下的 `01_*.md` ~ `13_*.md`。

---

## 完成状态

全部 13 章已完成 ✅

| 章 | 标题 |
|---|---|
| 01 | URP 三条渲染路径 ✅ |
| 02 | URP GBuffer 布局详解 ✅ |
| 03 | 让 MyLit 支持 Deferred ✅ |
| 04 | URP 里做 SSAO ✅ |
| 05 | URP 里做 SSR ✅ |
| 06 | URP 里做 Bloom ✅ |
| 07 | URP 里做体积云 ✅ |
| 08 | URP 里做卡通角色光照 ✅ |
| 09 | URP 里做粒子光照 ✅ |
| 10 | URP 里做双层材质 ✅ |
| 11 | URP 里做水面 ✅ |
| 12 | SH9 与 URP 光照探针对比 ✅ |
| 13 | MyLit 完整改造路线图 ✅ |

**姊妹教程**：从零构建 CustomSRP 管线，见
`D:/Code/Technical-Artist-Portfolio/TA-Portfolio-Repo/CustomSRP_Deferred_PBR/Docs/`

---

## 完成状态

全部 13 章已完成 ✅

| 章 | 标题 |
|---|---|
| 01 | URP 三条渲染路径 ✅ |
| 02 | URP GBuffer 布局详解 ✅ |
| 03 | 让 MyLit 支持 Deferred ✅ |
| 04 | URP 里做 SSAO ✅ |
| 05 | URP 里做 SSR ✅ |
| 06 | URP 里做 Bloom ✅ |
| 07 | URP 里做体积云 ✅ |
| 08 | URP 里做卡通角色光照 ✅ |
| 09 | URP 里做粒子光照 ✅ |
| 10 | URP 里做双层材质 ✅ |
| 11 | URP 里做水面 ✅ |
| 12 | SH9 与 URP 光照探针对比 ✅ |
| 13 | MyLit 完整改造路线图 ✅ |

**姊妹教程**：从零构建 CustomSRP 管线，见
`D:/Code/Technical-Artist-Portfolio/TA-Portfolio-Repo/CustomSRP_Deferred_PBR/Docs/`

---

## 完成状态

全部 13 章已完成 ✅

| 章 | 标题 |
|---|---|
| 01 | URP 三条渲染路径 ✅ |
| 02 | URP GBuffer 布局详解 ✅ |
| 03 | 让 MyLit 支持 Deferred ✅ |
| 04 | URP 里做 SSAO ✅ |
| 05 | URP 里做 SSR ✅ |
| 06 | URP 里做 Bloom ✅ |
| 07 | URP 里做体积云 ✅ |
| 08 | URP 里做卡通角色光照 ✅ |
| 09 | URP 里做粒子光照 ✅ |
| 10 | URP 里做双层材质 ✅ |
| 11 | URP 里做水面 ✅ |
| 12 | SH9 与 URP 光照探针对比 ✅ |
| 13 | MyLit 完整改造路线图 ✅ |

**姊妹教程**：从零构建 CustomSRP 管线，见
`D:/Code/Technical-Artist-Portfolio/TA-Portfolio-Repo/CustomSRP_Deferred_PBR/Docs/`

---

## 完成状态

全部 13 章已完成 ✅

| 章 | 标题 |
|---|---|
| 01 | URP 三条渲染路径 ✅ |
| 02 | URP GBuffer 布局详解 ✅ |
| 03 | 让 MyLit 支持 Deferred ✅ |
| 04 | URP 里做 SSAO ✅ |
| 05 | URP 里做 SSR ✅ |
| 06 | URP 里做 Bloom ✅ |
| 07 | URP 里做体积云 ✅ |
| 08 | URP 里做卡通角色光照 ✅ |
| 09 | URP 里做粒子光照 ✅ |
| 10 | URP 里做双层材质 ✅ |
| 11 | URP 里做水面 ✅ |
| 12 | SH9 与 URP 光照探针对比 ✅ |
| 13 | MyLit 完整改造路线图 ✅ |

**姊妹教程**：从零构建 CustomSRP 管线，见
`D:/Code/Technical-Artist-Portfolio/TA-Portfolio-Repo/CustomSRP_Deferred_PBR/Docs/`
