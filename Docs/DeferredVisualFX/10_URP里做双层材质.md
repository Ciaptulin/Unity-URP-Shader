# 10 · URP 里做双层材质

> 目标：把参考项目的双层材质（雪 / 苔藓）移植到 URP。
> 参考项目：`StandardLayer.shader` / `StandardLayer.hlsl` / `StandardLayerHeader.hlsl`

---

## 10.1 这个效果是什么

同一个物体上叠**两层外观**，按**世界法线方向**混合：

- 石头顶部有雪、侧面没雪
- 墙面朝上的部分长苔藓
- 金属氧化层

**关键**：按**世界法线朝上程度**混合（不是按光、不是按高度贴图）。

---

## 10.2 移植到 URP 的两种做法

| 路线 | 做法 | 适用 |
|---|---|---|
| **A. 独立 Shader** | 基于 URP Lit 改一个"双层版" | 推荐 ✅ |
| **B. Shader Graph** | 用节点搭 | 快速原型 |

本教程走 A。

---

## 10.3 复用 URP 的 Lit 结构

把 `Packages/com.unity.render-pipelines.universal/Shaders/Lit.shader` **复制**一份，改名 `Custom/LitLayer.shader`，然后：

1. 加覆盖层属性
2. 改 `LitInput.hlsl` → 自写 `LitLayerInput.hlsl`
3. 改 `LitForwardPass.hlsl` → 自写，加混合逻辑

---

## 10.4 属性（在 Lit 基础上加）

```hlsl
Properties
{
    // ... 原有 Lit 属性 ...

    [Header(Layer)]
    [Toggle(_LAYER_ON)] _LayerOn ("Enable Layer", Float) = 0
    _LayerContrast ("Layer Contrast", Range(0,1)) = 0.5
    _LayerTiling ("Layer Tiling", Float) = 1
    [NoScaleOffset] _LayerBaseMap ("Layer Albedo", 2D) = "white" {}
    _LayerBaseColor ("Layer Color", Color) = (1,1,1,1)
    [NoScaleOffset] _LayerNormalMap ("Layer Normal", 2D) = "bump" {}
    [NoScaleOffset] _LayerMaskMap ("Layer Metallic(S) AO(G) Smoothness(A)", 2D) = "white" {}
}
```

---

## 10.5 混合核心

```hlsl
// 采样基础层
half4 baseMap = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, uv) * _BaseColor;
half3 normalTS = UnpackNormalScale(
    SAMPLE_TEXTURE2D(_BumpMap, sampler_BumpMap, uv), _BumpScale);
half4 maskMap = SAMPLE_TEXTURE2D(_MetallicSpecGlossMap, sampler_MetallicSpecGlossMap, uv);

// 采样覆盖层
half2 layerUV = uv * _LayerTiling;
half4 layerBase = SAMPLE_TEXTURE2D(_LayerBaseMap, sampler_LayerBaseMap, layerUV) * _LayerBaseColor;
half3 layerNormalTS = UnpackNormalScale(
    SAMPLE_TEXTURE2D(_LayerNormalMap, sampler_LayerNormalMap, layerUV), 1);
half4 layerMask = SAMPLE_TEXTURE2D(_LayerMaskMap, sampler_LayerMaskMap, layerUV);

// 世界法线朝上程度
half upDot = dot(normalize(input.normalWS), half3(0, 1, 0));

// 阈值随 contrast 变化：contrast=0 → 阈值 1（只有正朝上才覆盖）
//                    contrast=1 → 阈值 -1（全都覆盖）
half threshold = lerp(1, -1, _LayerContrast);
half blendValue = step(threshold, upDot);   // 1 = 基础层，0 = 覆盖层

// 注意方向：参考项目里 blendValue=1 用 base
// 所以这里：
half4 finalBase = lerp(layerBase, baseMap, blendValue);
half3 finalNormalTS = lerp(layerNormalTS, normalTS, blendValue);
half finalMetallic = lerp(layerMask.r, maskMap.r, blendValue);
half finalSmoothness = lerp(layerMask.a, maskMap.a, blendValue);
```

> **关键**：`step` 产生硬边。如果想要软过渡，改成 `smoothstep`。

---

## 10.6 完整 Fragment（嵌入 URP Lit）

```hlsl
half4 LitLayerFragment(Interpolators input) : SV_Target
{
    // ===== 采样（含双层混合）=====
    half4 baseMap = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv) * _BaseColor;
    half3 normalTS = UnpackNormalScale(
        SAMPLE_TEXTURE2D(_BumpMap, sampler_BumpMap, input.uv), _BumpScale);
    half4 maskMap = SAMPLE_TEXTURE2D(_MetallicSpecGlossMap, sampler_MetallicSpecGlossMap, input.uv);

#ifdef _LAYER_ON
    half2 layerUV = input.uv * _LayerTiling;
    half4 layerBase = SAMPLE_TEXTURE2D(_LayerBaseMap, sampler_LayerBaseMap, layerUV) * _LayerBaseColor;
    half3 layerNormalTS = UnpackNormalScale(
        SAMPLE_TEXTURE2D(_LayerNormalMap, sampler_LayerNormalMap, layerUV), 1);
    half4 layerMask = SAMPLE_TEXTURE2D(_LayerMaskMap, sampler_LayerMaskMap, layerUV);

    half upDot = dot(normalize(input.normalWS), half3(0, 1, 0));
    half threshold = lerp(1, -1, _LayerContrast);
    half blendValue = step(threshold, upDot);

    baseMap = lerp(layerBase, baseMap, blendValue);
    normalTS = lerp(layerNormalTS, normalTS, blendValue);
    maskMap = lerp(layerMask, maskMap, blendValue);
#endif

    // ===== 重建法线 =====
    half3 normalWS = TransformTangentToWorld(normalTS,
        half3x3(input.tangentWS.xyz, input.bitangentWS.xyz, input.normalWS.xyz));
    normalWS = NormalizeNormalPerPixel(normalWS);

    // ===== 填充 SurfaceData =====
    SurfaceData surfaceData = (SurfaceData)0;
    surfaceData.albedo = baseMap.rgb;
    surfaceData.metallic = maskMap.r;
    surfaceData.smoothness = maskMap.a;
    surfaceData.occlusion = maskMap.g;
    // ... emission 等 ...

    InputData inputData = (InputData)0;
    inputData.positionWS = input.positionWS;
    inputData.normalWS = normalWS;
    inputData.viewDirectionWS = GetWorldSpaceNormalizeViewDir(input.positionWS);
    inputData.shadowCoord = TransformWorldToShadowCoord(input.positionWS);

    return UniversalFragmentPBR(inputData, surfaceData);
}
```

---

## 10.7 参考项目 vs URP 的差异

| 项 | 参考项目 | URP |
|---|---|---|
| 光照 | 自定义延迟 | `UniversalFragmentPBR` |
| 法线混合 | `lerp` | `lerp`（相同）|
| `_LayerContrast` | 相同 | 相同 |
| 实例化 | `UNITY_INSTANCING_BUFFER` | URP 的 `UnityPerMaterial` CBUFFER |

**混合算法完全一致，只是把光照后端换成 URP 的。**

---

## 10.8 为什么用世界法线而不是高度

- 世界法线：模型旋转后，雪仍在"朝上"面（符合物理）
- 高度：需要额外高度信息，且旋转后错位

参考项目用世界法线，是对的。

---

## 10.9 验证

- 放个球体，开 `_LAYER_ON`，上半球变白（雪）
- 调 `_LayerContrast`：雪线上下移动
- 旋转物体，雪始终在朝上的面

---

## 10.10 常见坑

- ❌ **用光照方向混合**：光一转，雪就跑
- ❌ **两层共用 tiling**：覆盖层无法独立缩放
- ❌ **混合后法线没归一化**：光照变暗
- ❌ **忘了 `_LAYER_ON` 关键字**：性能浪费

---

## 10.11 与下一章的联系

双层材质搞定。下一章：水面。

---

> 章节完。下一章 `11_URP里做水面.md`。
