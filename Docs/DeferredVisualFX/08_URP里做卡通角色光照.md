# 08 · URP 里做卡通角色光照

> 目标：把参考项目的卡通角色光照移植到 URP。
> 参考项目：`Shaders/ShaderLibrary/CharacterToonLighting.hlsl`

---

## 8.1 移植的难点：没有材质 ID 通道

参考项目靠 **GBuffer RT4 的材质 ID** 在延迟光照里分派光照模型。**URP 没有这个通道**。

所以移植到 URP 有两条路：

| 路线 | 做法 | 适用 |
|---|---|---|
| **A. 独立 Shader** | 角色用单独的卡通 Shader（不用 MyLit）| 简单直接 ✅ |
| **B. 借用 GBuffer 通道** | 把 ID 塞进某个未用通道 | 复杂，不推荐 |

**推荐路线 A**：角色的光照模型本来就和场景不同，用独立 Shader 最干净。

---

## 8.2 独立卡通 Shader 结构

```hlsl
Shader "Custom/ToonCharacter"
{
    Properties
    {
        _ColorMap ("Albedo", 2D) = "white" {}
        _ColorTint ("Tint", Color) = (1,1,1,1)

        [Header(Toon)]
        _ToonCutoff ("Toon Cutoff", Range(0,1)) = 0.5
        _ExtraBandThickness ("Extra Band Thickness", Range(0,1)) = 0.1
        _ShadowsFloor ("Shadows Floor", Range(0,1)) = 0.3
        [KeywordEnum(Skin, Hair)] _ShadingStyle ("Shading Style", Float) = 0

        [Header(Specular)]
        _SpecularColor ("Specular Color", Color) = (1,1,1,1)
        _SpecularThreshold ("Specular Threshold", Range(0,1)) = 0.9
        _PaintbrushSize ("Paintbrush Size", Float) = 1

        [Header(Rim)]
        _RimStrength ("Rim Strength", Range(0,3)) = 1
        _RimPower ("Rim Power", Float) = 3

        [Header(PBR)]
        _Metallic ("Metallic", Range(0,1)) = 0
        _Smoothness ("Smoothness", Range(0,1)) = 0.5
    }

    SubShader
    {
        Tags{"RenderPipeline" = "UniversalPipeline"}

        // ForwardLit Pass
        Pass
        {
            Tags{"LightMode" = "UniversalForward"}
            HLSLPROGRAM
            #pragma vertex Vertex
            #pragma fragment Fragment
            #pragma shader_feature_local _SHADINGSTYLE_SKIN _SHADINGSTYLE_HAIR
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _ADDITIONAL_LIGHTS
            #include "ToonCharacterPass.hlsl"
            ENDHLSL
        }
    }
}
```

---

## 8.3 移植 CharacterToonLighting.hlsl

参考项目的这些函数**与管线无关**，可直接复制：

- `CullingMask` —— 阶梯明暗
- `SoftBackRimColor` / `StrongSideRimColor` —— 边缘光
- `MainLightSpecularHighlight` —— Blinn-Phong 高光
- `SpecularColor` —— 笔触高光
- `FresnelEffect` —— 菲涅尔

**依赖**：`UnityBuildInNode.hlsl`（Shader Graph 节点的 hlsl 版）——整套复制即可，纯数学。

---

## 8.4 适配 URP 的光源接口

参考项目用自己的 `Light` 结构 + `GetDirectionalLight` / `GetOtherLight`。URP 里换成：

```hlsl
// URP 的 Light 结构
Light mainLight = GetMainLight(shadowCoord);

// 参考项目的代码里用 light.direction / light.color / light.attenuation
// 适配：
float3 lightDir = mainLight.direction;
float3 lightColor = mainLight.color;
float attenuation = mainLight.shadowAttenuation * mainLight.distanceAttenuation;
```

---

## 8.5 阶梯明暗（URP 版）

```hlsl
half4 Fragment(Interpolators input) : SV_Target
{
    // 采样
    float4 base = SAMPLE_TEXTURE2D(_ColorMap, sampler_ColorMap, input.uv) * _ColorTint;

    // 法线
    float3 normalWS = normalize(input.normalWS);
    #ifdef _NORMALMAP
        // ... TBN 转换 ...
    #endif

    // 主光
    Light mainLight = GetMainLight(TransformWorldToShadowCoord(input.positionWS));

    // ===== 阶梯明暗 =====
    float nDotL = dot(normalWS, mainLight.direction);
    float toonTreatment = step(_ToonCutoff, nDotL * mainLight.shadowAttenuation);

    #ifdef _SHADINGSTYLE_HAIR
        float extraBand = step(_ExtraBandThickness + _ToonCutoff,
                               nDotL * mainLight.shadowAttenuation) * 0.5 + 0.5;
        toonTreatment *= extraBand;
    #endif

    // 阴影最暗值
    float shadowColor = lerp(_ShadowsFloor, 1, toonTreatment);

    // ===== 边缘光 =====
    float3 viewDir = GetWorldSpaceNormalizeViewDir(input.positionWS);
    float fresnel = pow(1 - saturate(dot(normalWS, viewDir)), _RimPower);
    float rimAngle = 1 - (dot(viewDir, mainLight.direction) + 0.3);
    float rim = step(0.5, fresnel * rimAngle) * _RimStrength;

    // ===== 笔触高光 =====
    float3 halfDir = normalize(mainLight.direction + viewDir);
    float NdotH = saturate(dot(normalWS, halfDir));
    float gloss = exp2(_Smoothness * 10 + 1);
    float spec = pow(NdotH, gloss);

    // 用噪声画笔触（简化版，不依赖 UnityBuildInNode）
    float noise = frac(sin(dot(input.uv * _PaintbrushSize,
                               float2(12.9898, 78.233))) * 43758.5453);
    float paintbrush = step(0.01, spec) * noise;

    // ===== 合成 =====
    half3 diffuse = base.rgb * mainLight.color * shadowColor;
    half3 specular = mainLight.color * paintbrush * _SpecularColor.rgb;
    half3 rimColor = mainLight.color * rim;

    half3 finalColor = diffuse + specular + rimColor;

    return half4(finalColor, base.a);
}
```

---

## 8.6 附加光源

参考项目对附加光做了阶梯化。URP 里：

```hlsl
#ifdef _ADDITIONAL_LIGHTS
    uint count = GetAdditionalLightsCount();
    for (uint i = 0; i < count; i++)
    {
        Light light = GetAdditionalLight(i, input.positionWS);
        float addNdotL = step(_AdditionalLightCutoff,
                              dot(normalWS, light.direction));
        float addAtten = step(0.001, light.distanceAttenuation);
        finalColor += light.color * base.rgb * addNdotL * addAtten;
    }
#endif
```

---

## 8.7 参考项目 vs URP 移植对照

| 参考项目 | URP 移植 |
|---|---|
| GBuffer ID 分派 | 独立 Shader + 关键字 |
| 自有 Light 结构 | URP 的 `Light` / `GetMainLight` |
| `GetOtherLight` | `GetAdditionalLight` |
| 自有 shadow | `TransformWorldToShadowCoord` |
| UnityBuildInNode | 可复制，或简化为噪声函数 |

---

## 8.8 验证

- 角色出现硬边明暗
- 调 `_ToonCutoff`：明暗交界线移动
- 开 `_SHADINGSTYLE_HAIR`：多一档色带
- 背光时轮廓亮边
- 高光有笔触感

---

## 8.9 常见坑

- ❌ **想用 GBuffer ID 分派**：URP 没这个通道
- ❌ **忘了 URP 的 shadowAttenuation**：直接用自定义 shadow 会错
- ❌ **附加光没遍历**：只有主光
- ❌ **边缘光方向算错**：应"背光侧"亮

---

## 8.10 与下一章的联系

角色搞定了。下一章：粒子光照。

---

> 章节完。下一章 `09_URP里做粒子光照.md`。
