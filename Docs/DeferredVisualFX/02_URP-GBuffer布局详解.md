# 02 · URP GBuffer 布局详解

> 目标：看清 URP Deferred 的 GBuffer 每个通道存什么，与参考项目的 5-RT 布局对照。
> 这是让 MyLit 支持 Deferred 的前提。

---

## 2.1 URP 的 GBuffer 布局

URP Deferred 用 **4 张 RT**（外加深度），命名与通道如下：

| RT | 名称 | 通道 | 内容 |
|---|---|---|---|
| **GBuffer0** | `_GBuffer0` | RGB / A | albedo.rgb / occlusion |
| **GBuffer1** | `_GBuffer1` | RGB / A | specular.rgb / smoothness |
| **GBuffer2** | `_GBuffer2` | RGB / A | normalWS（0~1）/ 未用 |
| **GBuffer3** | `_GBuffer3` | RGB / A | emission + GI（烘焙光）|

另有 **Depth** 和 **DepthNormals**（如果启用）。

---

## 2.2 与参考项目布局的对照

| 参考项目 | URP | 差异 |
|---|---|---|
| RT0: albedo + alpha | GBuffer0: albedo + occlusion | alpha 没了，改了 occlusion |
| RT1: normal + 1 | GBuffer2: normal | URP 把法线放 RT2 |
| RT2: (0,0,metallic,roughness) | GBuffer1: specular + smoothness | URP 用**高光工作流**不是金属度 |
| RT3: emission + ao | GBuffer3: emission + GI | URP 的 RT3 装烘焙 GI |
| RT4: 材质 ID | **无** | URP 没有材质 ID 通道 |

**关键差异**：

1. **URP 用高光/平滑度（specular/smoothness）**，不是金属度/粗糙度。metalness 要在 GBuffer Pass 里转换。
2. **URP 没有材质 ID 通道**——想按材质分派光照模型，得另想办法（见第 8 章）。
3. **URP 的 GBuffer3 装烘焙 GI**，不是纯 emission。

---

## 2.3 金属度 → 高光转换

URP 的 `UniversalFragmentPBR` 内部做这个转换，GBuffer Pass 里我们要手动做：

```hlsl
// 输入：metallic, smoothness, albedo
// 输出：specular.rgb, smoothness

// 介电质反射率
const half3 kDielectricSpec = half3(0.04, 0.04, 0.04);

// metallic 决定 specular
half3 specular = lerp(kDielectricSpec, albedo, metallic);

// oneMinusReflectivity 影响 diffuse
half oneMinusReflectivity = OneMinusReflectivityMetallic(metallic);
```

URP 提供现成函数，在 `Packages/com.unity.render-pipelines.universal/ShaderLibrary/BRDF.hlsl` 里。

---

## 2.4 URP GBuffer 的采样函数

URP 提供 `InitializeGBuffer` 等函数，但**最简单**的做法是直接声明 RT 并采样：

```hlsl
// 在自定义 Renderer Feature 或 full-screen pass 里
TEXTURE2D_X(_GBuffer0);
TEXTURE2D_X(_GBuffer1);
TEXTURE2D_X(_GBuffer2);
TEXTURE2D_X(_GBuffer3);
SAMPLER(sampler_LinearClamp);

float4 g0 = SAMPLE_TEXTURE2D_X(_GBuffer0, sampler_LinearClamp, uv);
float3 albedo = g0.rgb;
float occlusion = g0.a;

float4 g1 = SAMPLE_TEXTURE2D_X(_GBuffer1, sampler_LinearClamp, uv);
float3 specular = g1.rgb;
float smoothness = g1.a;

float4 g2 = SAMPLE_TEXTURE2D_X(_GBuffer2, sampler_LinearClamp, uv);
float3 normalWS = g2.rgb * 2 - 1;

float4 g3 = SAMPLE_TEXTURE2D_X(_GBuffer3, sampler_LinearClamp, uv);
float3 emissionAndGI = g3.rgb;
```

---

## 2.5 验证

1. URP Asset 切成 **Deferred**
2. 用官方 **Lit** 材质放个球
3. 打开 Frame Debugger，找到 `RenderLoop.Draw` 或 `GBuffer` 相关的 Pass
4. 观察它写了 4 张 RT

> **注意**：URP 的 RT 名称在不同版本可能微调，用 Frame Debugger 确认实际名字。

---

## 2.6 常见坑

- ❌ **以为能改 URP GBuffer 布局**：不能
- ❌ **直接用 metalness 采样 URP GBuffer**：URP 存的是 specular，要反算
- ❌ **忘了 URP 的 GBuffer 是 `TEXTURE2D_X`**：XR 下是数组，采样要用 `SAMPLE_TEXTURE2D_X`

---

## 2.7 与下一章的联系

看懂了布局，下一章：给 MyLit 加一个 `UniversalGBuffer` Pass，让它能写进 URP 的 GBuffer。

---

> 章节完。下一章 `03_让MyLit支持Deferred.md`。
