# 13 · MyLit 完整改造路线图

> 目标：汇总前面 12 章，给 MyLit 一份可执行的 Deferred + 特效改造路线图。
> 说明：本章是**规划**，不改动现有代码。

---

## 13.1 现状回顾

MyLit 当前（Part5 完成时）：

- 6 个 Pass：ForwardLit / ShadowCaster / Meta / DepthOnly / DepthNormals / MotionVectors
- 全 Forward 路径
- 已有 SSAO 支持（`_SCREEN_SPACE_OCCLUSION`）

---

## 13.2 改造的三个阶段

### 阶段一：支持 Deferred（第 2、3 章）

| 步骤 | 产出 |
|---|---|
| 1 | 读 URP GBuffer 布局（第 2 章）|
| 2 | 新增 `MyLitGBufferPass.hlsl`（第 3 章）|
| 3 | 在 `MyLit.shader` 加 `UniversalGBuffer` Pass |
| 4 | 保留 `ForwardLit`（透明物体用）|
| 5 | URP Asset 切 Deferred，验证 |

**风险**：URP 的 GBuffer 用高光工作流，metallic 要转换。

---

### 阶段二：屏幕空间效果（第 4~7 章）

| 效果 | 推荐做法 |
|---|---|
| SSAO | URP 内置（Source = Depth Normals）|
| SSR | 自写 Renderer Feature（第 5 章）|
| Bloom | URP 内置 Volume |
| 体积云 | 自写 Renderer Feature（第 7 章）|

**顺序建议**：Bloom → SSAO → SSR → 体积云（由易到难）。

---

### 阶段三：特殊材质（第 8~11 章）

| 材质 | 做法 |
|---|---|
| 卡通角色 | 独立 Shader（第 8 章）|
| 粒子 | URP Particles/Unlit 或 Lit（第 9 章）|
| 双层材质 | 复制 URP Lit 改（第 10 章）|
| 水面 | 独立 Shader + SSR（第 11 章）|

---

## 13.3 每个阶段后的 Pass 清单

改造后 MyLit 的 Pass 可能是：

| Pass | LightMode | 用途 |
|---|---|---|
| GBuffer | `UniversalGBuffer` | Deferred 不透明 |
| ForwardLit | `UniversalForward` | 透明 / 不支持 Deferred 时 |
| ShadowCaster | `ShadowCaster` | 阴影 |
| DepthOnly | `DepthOnly` | 深度 |
| DepthNormals | `DepthNormals` | SSAO / SSR |
| MotionVectors | `MotionVectors` | TAA / 运动模糊 |
| Meta | `Meta` | 烘焙 |

（7 个 Pass）

---

## 13.4 与参考项目的功能对照表

| 参考项目功能 | MyLit 目标 | 章节 | 状态 |
|---|---|---|---|
| Deferred 延迟渲染 | ✅ URP Deferred | 2-3 | 教程已给 |
| 自写 5-RT GBuffer | ❌ 用 URP GBuffer | 2 | 不可复刻 |
| 自写延迟光照 | ❌ 用 URP 内置 | 3 | 不可复刻 |
| CSM 阴影 | ✅ URP 已有 | - | 已具备 |
| 点光/聚光 | ✅ URP 已有 | - | 已具备 |
| 逐对象光源 | ✅ URP Forward+ 或 Deferred | - | 已具备 |
| SSAO | ✅ | 4 | 教程已给 |
| SSR | ✅ | 5 | 教程已给 |
| Bloom | ✅ | 6 | 教程已给 |
| 体积云 | ✅ | 7 | 教程已给 |
| SH9 环境光 | ✅ 用 Light Probe | 12 | 对齐 |
| 卡通角色 | ✅ | 8 | 教程已给 |
| 粒子光照 | ✅ | 9 | 教程已给 |
| 双层材质 | ✅ | 10 | 教程已给 |
| 水面 | ✅ | 11 | 教程已给 |

---

## 13.5 不可复刻的部分（明确）

| 参考项目 | 原因 |
|---|---|
| 自定义 GBuffer 布局（5 RT）| URP 固定 4 RT |
| 自定义延迟光照循环 | URP 内部完成 |
| 自定义 Light Index Map | URP 有自己的机制 |
| `_LIGHTS_PER_OBJECT` | URP 用 Forward+ 的 cluster |
| 自写 PostFXStack | URP 用 Renderer Feature |

**这些是"URP 帮你做了"，不是"URP 做不到"。**

---

## 13.6 建议的执行顺序

```
第 1 步：读第 2 章，确认 URP GBuffer 布局
   ↓
第 2 步：按第 3 章加 GBuffer Pass，验证 Deferred 能跑
   ↓
第 3 步：按第 6 章配 Bloom（最简单，先尝到甜头）
   ↓
第 4 步：按第 4 章配 SSAO
   ↓
第 5 步：按第 8 章做卡通角色（独立 shader，风险低）
   ↓
第 6 步：按第 10 章做双层材质
   ↓
第 7 步：按第 5 章做 SSR（较难）
   ↓
第 8 步：按第 11 章做水面
   ↓
第 9 步：按第 7 章做体积云（最难）
```

---

## 13.7 学习建议

1. **每一步都先跑通再下一步**——不要一次全上
2. **多用 Frame Debugger**——URP 的 Renderer Feature 顺序很重要
3. **对照参考项目**——它是"自写版"，理解它有助于理解 URP 在替你做什么
4. **保留 Forward 路径**——透明物体和某些效果仍需 Forward

---

## 13.8 与参考项目教程（教程 B）的关系

- 教程 B（`CustomSRP_Deferred_PBR/Docs/`）：**从零写管线**，理解底层
- 教程 A（本目录）：**在 URP 上复刻效果**，实用导向

**建议**：先读教程 B 理解原理，再读教程 A 落地到 URP。

---

## 13.9 教程 A 完结

到这里，教程 A 全部 13 章完成：

| 部分 | 章节 |
|---|---|
| 理解 URP 延迟路径 | 01-03 |
| 屏幕空间效果 | 04-07 |
| 特殊材质 | 08-11 |
| 进阶 | 12-13 |

**你现在拥有的**：

- 理解 URP Forward / Deferred / Forward+ 的差异
- 知道 URP GBuffer 存什么、与自写管线差在哪
- 知道每个参考项目效果在 URP 里怎么做（内置 / Renderer Feature / 独立 Shader）
- 知道哪些能复刻、哪些不能

---

> 教程 A 全部完成。感谢阅读。
> 教程 B（从零建管线）见 `D:/Code/Technical-Artist-Portfolio/TA-Portfolio-Repo/CustomSRP_Deferred_PBR/Docs/`。
