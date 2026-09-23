# 01 · URP 的三条渲染路径：Forward / Deferred / Forward+

> 目标：搞清 URP 三条路径的差异，明确我们要在哪条上做延迟复刻。
> 参考项目 `CustomSRP_Deferred_PBR` 是**纯延迟**。URP 这边要选对应路径。

---

## 1.1 三条路各自是什么

| 路径 | 光照计算时机 | 核心缓冲 | 适用 |
|---|---|---|---|
| **Forward** | 每个物体在片元里算所有光 | 颜色 + 深度 | 少量光源、透明多 |
| **Deferred** | 物体先写 GBuffer，再由全屏 Pass 算光 | GBuffer（多张 RT）| 大量光源 |
| **Forward+** | 保留 Forward，但用 tile/cluster 剔除光源 | 颜色 + 深度 + 光源列表 | 中量光源 + 支持透明 |

---

## 1.2 关键区别：GBuffer 是谁的

参考项目自己定义了 5 张 GBuffer：

```
RT0: albedo + alpha
RT1: normal + 1
RT2: (0,0, metallic, roughness)
RT3: emission + ao
RT4: 材质 ID
```

**URP 的 GBuffer 是固定的**（由 Unity 定义，见下一章），你**不能**改成上面这套。这是 URP Deferred 路线最大的约束。

---

## 1.3 我们怎么选

| 你的需求 | 建议路径 |
|---|---|
| 大量实时光源 + 一个不透明场景 | **Deferred** |
| 透明物体多 / 光源少 | Forward+ 或 Forward |
| 移动端 | Forward（低端）/ Forward+（中端） |

本系列教程主线：**Deferred 起步**，透明与特殊材质走 Forward 兜底（参考项目也是这么做的：不透明走 BasePass，透明走 BaseTransparentPass）。

---

## 1.4 在 URP 里切换路径

1. 选中你的 **URP Asset**（`Assets/_lighting` 之类）
2. Inspector → **Rendering → Rendering Path**
3. 选：
   - `Forward`
   - `Deferred`
   - `Forward+`

切换后，URP 会用不同的 pass 编译你的 shader。

---

## 1.5 对我们的 MyLit 意味着什么

当前 MyLit 只有 `UniversalForward` Pass。切到 Deferred 后：

- 不透明物体**不会**走 `UniversalForward`
- 而是走一个叫 `UniversalGBuffer` 的 Pass
- 没有这个 Pass 的 shader 在 Deferred 下会**消失**（除非被标为 Forward-only）

**所以要让 MyLit 支持 Deferred，就必须新增 GBuffer Pass。** 具体写法见第 3 章。

---

## 1.6 常见坑

- ❌ **以为 URP Deferred 可以改 GBuffer 布局**：不行，Unity 定死
- ❌ **切了 Deferred 但 shader 没 GBuffer Pass**：物体会消失
- ❌ **以为 Deferred 快**：它只是"光源多时"快；光源少时 Forward 更快

---

## 1.7 与下一章的联系

下一章拆开 URP 的 GBuffer 布局——看清它每个通道存什么，你才知道 GBuffer Pass 该怎么写。

---

> 章节完。下一章 `02_URP-GBuffer布局详解.md`。
