# 自定义光照模型：用代码编写 Unity URP 着色器（第 7 部分）

> 原作者：NedMakesGames
> 原文链接：https://nedmakesgames.medium.com/
> 本文件已按本项目实际重写（命名 / CBUFFER / 结构体 / 大括号风格全部对齐 `Assets/Shader/MyLit/`）
> 重写时间：Part6 完成后
> 分支：`feature/pbr-normal-mapping`

---

## 目录

- [引言](#引言)
- [绕过 UniversalFragmentPBR](#绕过-universalfragmentpbr)
  - [会丢失什么（重要）](#会丢失什么重要)
- [构建自定义光照函数](#构建自定义光照函数)
  - [准备自定义结构体](#准备自定义结构体)
  - [漫反射模型](#漫反射模型)
  - [高光模型](#高光模型)
- [卡通渲染（Toon Shading）](#卡通渲染toon-shading)
- [布料光照（Cloth）](#布料光照cloth)
- [皮肤光照（Skin Subsurface）](#皮肤光照skin-subsurface)
- [头发光照（Anisotropic Hair）](#头发光照anisotropic-hair)
- [植物叶片（Foliage）](#植物叶片foliage)
- [调试可视化](#调试可视化)
- [混合光照模型](#混合光照模型)
- [总结](#总结)
- [与原翻译稿的差异对照](#与原翻译稿的差异对照)

---

## 引言

Part5 / Part6 结束时，MyLit 已经是"功能全 + 性能可控"的 6-Pass 着色器。但它的着色主体一直靠 URP 的 `UniversalFragmentPBR`——一个**黑盒**。

这一部分开始，我们**绕过**它，自己写光照。这是 MyLit 从"跑得对"走向"看起来有风格"的分水岭：

+ **卡通渲染**：PBR 太写实，需要阶梯响应
+ **布料**：需要沿纤维方向的各向异性高光
+ **皮肤**：需要次表面散射
+ **头发**：需要 R / TT 双波瓣高光
+ **植物叶片**：需要背面透射

> **状态说明**：本部分内容**项目尚未落地**，是学习 / 扩展方向。文中的新属性 / 新结构体是**新增建议**，不会自动出现在现有 `MyLit.shader` 里。

---

## 绕过 UniversalFragmentPBR

### 当前结构（项目实况）

项目 `MyLitForwardLitPass.hlsl` 的 Fragment 末尾就是这一句：

```hlsl
// ===== PBR 出最终颜色 =====
return UniversalFragmentPBR(lightingInput, surfaceInput);
```

### 目标结构

把这一句替换成自写光照函数：

```hlsl
// 1. 准备 InputData（项目已有）
InputData lightingInput = (InputData)0;
lightingInput.positionWS = input.positionWS;
lightingInput.normalWS = normalWS;
lightingInput.viewDirectionWS = viewDirWS;
lightingInput.shadowCoord = TransformWorldToShadowCoord(input.positionWS);
lightingInput.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(input.positionCS);
lightingInput.shadowMask = half4(1.0, 1.0, 1.0, 1.0);
...

// 2. 准备 SurfaceData（项目已有）
SurfaceData surfaceInput = (SurfaceData)0;
...

// 3. 改为自写光照，不再是 UniversalFragmentPBR
return CustomLighting(lightingInput, surfaceInput);
```

### 会丢失什么（重要）

> **原翻译稿完全没提这一点**，直接建议"把第 3 步替换掉"。在真实项目里这会**掉一堆功能**——因为 `UniversalFragmentPBR` 内部不只是"光照"，它把这些都打包了：

| 会丢的功能 | 项目对应位置 | 想保留怎么办 |
|---|---|---|
| **雾效** | URP 内置在 PBR 里 | 自写完后调 `MixFog(color, fogFactor)` |
| **反射探针** | PBR 里的 `GlossyEnvironmentReflection` | 自写里手动调 |
| **烘焙 GI** | `lightingInput.bakedGI` | 自写里手动加进最终色 |
| **光源层级** | `_LIGHT_LAYERS` 分支 | 自写里加 `IsMatchingLightLayer` 判断 |
| **光源 Cookie** | `GetMainLight` 内部 | `GetMainLight` 保留即可（它自己处理）|
| **附加光源阴影** | `_ADDITIONAL_LIGHT_SHADOWS` | 自写循环里自己采样 |
| **SSAO** | `_SCREEN_SPACE_OCCLUSION` | 自写里读 `SampleAmbientOcclusion` 或直接读 `_ScreenSpaceOcclusionTexture` |
| **调试显示** | `DEBUG_DISPLAY` | 自写里挂 `UniversalFragmentDebug` |
| **清漆** | PBR 有 `clearCoat*` 字段 | 自写里忽略或另写 |

**建议**：自写光照**先只替换"主光 + 附加光的 BRDF 部分"**，其余（雾 / 反射 / GI / SSAO）继续沿用 URP 提供的函数。这样最少代价拿到"风格化"收益。

---

## 构建自定义光照函数

### 准备自定义结构体

```hlsl
// 放在 MyLitCommon.hlsl 里
struct MySurfaceData
{
    half3 albedo;
    half3 emission;
    half  metallic;
    half  smoothness;
    half  occlusion;
    half  alpha;
    half3 normalWS;
    half3 viewDirWS;
    float3 positionWS;
};

struct MyLightingData
{
    half3 normalWS;
    half3 viewDirWS;
    half3 reflectDirWS;
    half  NdotV;
    half  fresnel;
};

MyLightingData CreateLightingData(MySurfaceData s)
{
    MyLightingData d = (MyLightingData)0;
    d.normalWS = s.normalWS;
    d.viewDirWS = s.viewDirWS;
    d.reflectDirWS = reflect(-s.viewDirWS, s.normalWS);
    d.NdotV = saturate(dot(s.normalWS, s.viewDirWS));
    d.fresnel = pow(1 - d.NdotV, 5);
    return d;
}
```

### 漫反射模型

```hlsl
// Lambert
half3 LambertDiffuse(half3 lightColor, half3 lightDirWS, half3 normalWS)
{
    half NdotL = saturate(dot(normalWS, lightDirWS));
    return lightColor * NdotL;
}

// Half-Lambert：把阴影区拉亮，卡通 / 游戏风格常用
half3 HalfLambertDiffuse(half3 lightColor, half3 lightDirWS, half3 normalWS)
{
    half NdotL = dot(normalWS, lightDirWS) * 0.5 + 0.5;
    return lightColor * NdotL;
}

// 带能量控制的 Half-Lambert
half3 EnergyHalfLambert(half3 lightColor, half3 lightDirWS, half3 normalWS, half energy)
{
    half NdotL = dot(normalWS, lightDirWS) * 0.5 + 0.5;
    NdotL = pow(NdotL, energy);
    return lightColor * NdotL;
}
```

### 高光模型

```hlsl
// Blinn-Phong
half3 BlinnPhongSpecular(half3 lightColor, half3 lightDirWS, half3 normalWS,
                         half3 viewDirWS, half smoothness)
{
    half3 halfWS = normalize(lightDirWS + viewDirWS);
    half NdotH = saturate(dot(normalWS, halfWS));
    half shininess = exp2(smoothness * 10 + 1);
    return lightColor * pow(NdotH, shininess);
}

// GGX（PBR 标准）
half3 GGXSpecular(half3 lightColor, half3 lightDirWS, half3 normalWS,
                  half3 viewDirWS, half roughness)
{
    half3 halfWS = normalize(lightDirWS + viewDirWS);
    half NdotH = saturate(dot(normalWS, halfWS));
    half NdotV = saturate(dot(normalWS, viewDirWS));
    half NdotL = saturate(dot(normalWS, lightDirWS));

    half a2 = roughness * roughness;
    half denom = NdotH * NdotH * (a2 - 1) + 1;
    half D = a2 / (PI * denom * denom);

    // 简化的 Schlick Fresnel
    half3 F = lerp(half3(0.04, 0.04, 0.04), half3(1, 1, 1), pow(1 - NdotV, 5));

    return lightColor * D * F * NdotL;
}
```

---

## 卡通渲染（Toon Shading）

卡通的核心：用**阶梯响应**替代平滑的 NdotL。

```hlsl
// 硬边
half3 ToonDiffuse(half3 lightColor, half3 lightDirWS, half3 normalWS, half threshold)
{
    half NdotL = dot(normalWS, lightDirWS);
    return lightColor * step(threshold, NdotL);
}

// 平滑阶梯
half3 SmoothToonDiffuse(half3 lightColor, half3 lightDirWS, half3 normalWS,
                        half threshold, half softness)
{
    half NdotL = dot(normalWS, lightDirWS) * 0.5 + 0.5;
    return lightColor * smoothstep(threshold - softness, threshold + softness, NdotL);
}
```

### Ramp 贴图

用一张一维渐变纹理让美术控制响应曲线。

```hlsl
// 属性（需在 MyLit.shader 里新增，见下方）
// [NoScaleOffset] _ToonRamp("Toon Ramp", 2D) = "white" {}

// MyLitCommon.hlsl 的纹理区
TEXTURE2D(_ToonRamp);
SAMPLER(sampler_ToonRamp);

half3 RampDiffuse(half3 lightColor, half3 lightDirWS, half3 normalWS)
{
    half NdotL = dot(normalWS, lightDirWS) * 0.5 + 0.5;
    half3 ramp = SAMPLE_TEXTURE2D(_ToonRamp, sampler_ToonRamp, float2(NdotL, 0.5)).rgb;
    return lightColor * ramp;
}
```

### 卡通所需的新属性（放进项目 CBUFFER）

按项目约定，新材质属性**必须**进 `MyLitCommon.hlsl` 的 `CBUFFER_START(UnityPerMaterial)`：

```hlsl
CBUFFER_START(UnityPerMaterial)
// ... 现有属性 ...
float _CelShadeMidPoint;
float _CelShadeSoftness;
float _ReceiveShadowAmount;
float _SpecularThreshold;
float4 _SpecularColor;
float _AmbientStrength;
CBUFFER_END
```

`.shader` 的 `Properties` 块：

```hlsl
[Header(Toon Shading)]
_CelShadeMidPoint("Cel Mid Point", Range(0, 1)) = 0.5
_CelShadeSoftness("Cel Softness", Range(0, 0.5)) = 0.05
_ReceiveShadowAmount("Receive Shadow", Range(0, 1)) = 1.0
_SpecularThreshold("Specular Threshold", Range(0, 1)) = 0.9
_SpecularColor("Specular Color", Color) = (1, 1, 1, 1)
_AmbientStrength("Ambient Strength", Range(0, 1)) = 0.3
[NoScaleOffset] _ToonRamp("Toon Ramp Texture", 2D) = "white" {}
```

### 完整卡通片段（对齐项目）

```hlsl
// 主光源（沿用项目里已有的 GetMainLight 调用）
Light mainLight = GetMainLight(lightingInput.shadowCoord, lightingInput.positionWS, lightingInput.shadowMask);

// 卡通漫反射
half NdotL = dot(normalWS, mainLight.direction) * 0.5 + 0.5;
half toon = smoothstep(_CelShadeMidPoint - _CelShadeSoftness,
                       _CelShadeMidPoint + _CelShadeSoftness, NdotL);
toon *= lerp(1, mainLight.shadowAttenuation, _ReceiveShadowAmount);

half3 diffuse = mainLight.color * toon * colorSample.rgb * _ColorTint.rgb;

// 卡通高光（锐利）
half3 halfWS = normalize(mainLight.direction + lightingInput.viewDirectionWS);
half NdotH = saturate(dot(normalWS, halfWS));
half specToon = step(_SpecularThreshold, NdotH);
half3 specular = mainLight.color * specToon * _SpecularColor.rgb;

// 环境光（项目里已有 vertexSH / SampleSHPixel）
half3 ambient = SampleSHPixel(input.vertexSH, normalWS) * colorSample.rgb * _AmbientStrength;

// 自发光（项目里已有 surfaceInput.emission）
half3 finalColor = diffuse + specular + surfaceInput.emission + ambient;

return half4(finalColor, colorSample.a * _ColorTint.a);
```

> **差异提醒**：`SampleSHPixel`（项目里在 ForwardLit 已用过），**不是**原稿写的 `SampleSH`。`SampleSH` 是 Built-in / 部分版本的函数，URP 16 里用 `SampleSHPixel`（片元）/ `SampleSHVertex`（顶点）。

---

## 布料光照（Cloth）

```hlsl
// Wrap 漫反射：让光"绕过"边缘
half3 ClothDiffuse(half3 lightColor, half3 lightDirWS, half3 normalWS, half wrapAmount)
{
    half NdotL = dot(normalWS, lightDirWS);
    half wrapped = (NdotL + wrapAmount) / (1 + wrapAmount);
    return lightColor * saturate(wrapped);
}

// 各向异性高光（Ward 简化版）
half3 ClothSpecular(half3 lightColor, half3 lightDirWS, half3 normalWS,
                    half3 viewDirWS, half3 tangentWS,
                    half roughness, half anisotropy)
{
    half3 halfWS = normalize(lightDirWS + viewDirWS);
    half TdotH = dot(tangentWS, halfWS);
    half NdotL = saturate(dot(normalWS, lightDirWS));

    half aniso = sqrt(max(1 - TdotH * TdotH, 0));
    half exponent = roughness * 100;
    half spec = pow(aniso, exponent) * anisotropy;

    return lightColor * spec * NdotL;
}
```

---

## 皮肤光照（Skin Subsurface）

```hlsl
half3 SkinDiffuse(half3 lightColor, half3 lightDirWS, half3 normalWS)
{
    half NdotL = dot(normalWS, lightDirWS);

    // Wrap：让光"弯"到背面
    half wrap = (NdotL + 0.5) / 1.5;

    // 简化的暖色散射
    half3 scatterColor = half3(0.8, 0.3, 0.2);
    half scatter = pow(saturate(NdotL * 0.5 + 0.5), 2) * 0.3;

    return lightColor * (saturate(wrap) + scatter * scatterColor);
}

half3 SkinSpecular(half3 lightColor, half3 lightDirWS, half3 normalWS, half3 viewDirWS)
{
    half3 halfWS = normalize(lightDirWS + viewDirWS);
    half NdotH = saturate(dot(normalWS, halfWS));

    // 宽而弱的高光
    half spec = pow(NdotH, 16) * 0.3;

    // 皮肤特有的红色 Fresnel
    half fresnel = pow(1 - saturate(dot(normalWS, viewDirWS)), 3);
    half3 skinFresnel = half3(0.8, 0.4, 0.3) * fresnel;

    return lightColor * (spec + skinFresnel * 0.1);
}
```

> URP 16 的 `SurfaceData` 有 `transmission` 字段，也有 `SampleTransmission` 辅助函数可用于更高质量的 SSS。本部分展示的是简化近似。

---

## 头发光照（Anisotropic Hair）

```hlsl
// Kajiya-Kay 简化版：R 波瓣 + TT 波瓣
half3 AnisotropicHairSpecular(half3 lightColor, half3 lightDirWS, half3 normalWS,
                              half3 viewDirWS, half3 tangentWS, half roughness)
{
    half3 halfWS = normalize(lightDirWS + viewDirWS);
    half TdotH = dot(tangentWS, halfWS);

    // R 波瓣（沿切线）
    half rLobe = sqrt(1 - TdotH * TdotH);
    half rExponent = lerp(2, 64, 1 - roughness);
    half rSpec = pow(rLobe, rExponent);

    // TT 波瓣（透射，在背面）
    half TTdotH = dot(-tangentWS, halfWS);
    half ttLobe = sqrt(1 - TTdotH * TTdotH);
    half ttSpec = pow(ttLobe, 32) * 0.5;

    return lightColor * (rSpec + ttSpec);
}
```

---

## 植物叶片（Foliage）

```hlsl
half3 FoliageDiffuse(half3 lightColor, half3 lightDirWS, half3 normalWS,
                     half3 backNormalWS)
{
    half NdotL = dot(normalWS, lightDirWS);
    half front = NdotL * 0.5 + 0.5;

    half back = saturate(dot(backNormalWS, lightDirWS) * 0.5 + 0.5);
    half transmission = pow(back, 2) * 0.5;

    half3 transmissionColor = half3(0.6, 0.8, 0.2);
    return lightColor * (front + transmission * transmissionColor);
}

half3 FoliageSpecular(half3 lightColor, half3 lightDirWS, half3 normalWS, half3 viewDirWS)
{
    half3 halfWS = normalize(lightDirWS + viewDirWS);
    half NdotH = saturate(dot(normalWS, halfWS));
    half spec = pow(NdotH, 4) * 0.15;
    return lightColor * spec * half3(0.7, 0.9, 0.6);
}
```

> **项目配合**：叶片需要双面渲染。把 Inspector 的 `Face rendering mode` 设为 **DoubleSided**，项目已自动启用 `_DOUBLE_SIDED_NORMALS` 关键字（见 `MyLitCustomInspector.cs`）。`backNormalWS` 就是 `normalWS` 乘面朝向——Fragment 里的 `normalWS *= IS_FRONT_VFACE(frontFace, 1, -1)` 已经做了这一步，可以直接复用。

---

## 调试可视化

> **原稿用了 `switch`**——HLSL 对 `switch` 支持有限（需要 SM4.0+，且某些移动平台有坑）。项目走的是"编译期关键字 + 内联条件"路线，等价且更稳。

### 可选方案 A：关键字式（推荐，与项目现有做法一致）

```hlsl
// MyLit.shader 里加
#pragma multi_compile _ _DEBUG_VIEW_NORMAL _DEBUG_VIEW_NDOTL _DEBUG_VIEW_ALBEDO

// Fragment 里
#if defined(_DEBUG_VIEW_NORMAL)
    return half4(normalWS * 0.5 + 0.5, 1);
#elif defined(_DEBUG_VIEW_NDOTL)
    return half4(dot(normalWS, mainLight.direction).xxx, 1);
#elif defined(_DEBUG_VIEW_ALBEDO)
    return half4(colorSample.rgb, 1);
#endif
```

### 可选方案 B：属性开关（若坚持面板控制）

```hlsl
// 属性
_DebugView("Debug View", Float) = 0
// 注意：不要用 [Enum(...)] 那种声明，它只是编辑器显示；运行时还是 float

// Fragment 里用 if 链替代 switch（HLSL switch 有坑）
half3 debugValue = half3(0, 0, 0);
int mode = (int)_DebugView;
if (mode == 1)      debugValue = normalWS;
else if (mode == 2) debugValue = lightingInput.viewDirectionWS;
else if (mode == 3) debugValue = mainLight.direction;
else if (mode == 4) debugValue = dot(normalWS, mainLight.direction).xxx;
else if (mode == 5) debugValue = surfaceInput.smoothness.xxx;
else if (mode == 6) debugValue = surfaceInput.metallic.xxx;
else                debugValue = finalColor;

// 归一化显示：[-1,1] → [0,1]（放在用到它之前定义）
debugValue = debugValue * 0.5 + 0.5;
return half4(debugValue, 1);
```

> 项目已有内建的 `DEBUG_DISPLAY` 支持（Part5-六）。自写光照时，若还想沿用 Rendering Debugger 的视图，需要额外挂 `UniversalFragmentDebug`（见 4.4 节"会丢失什么"）。

---

## 混合光照模型

最强大的做法：**分区切换模型**。比如同一角色，皮肤走 SSS，衣服走卡通，金属饰品走 PBR。

```hlsl
// 用一张 mask 贴图的通道决定每个像素走哪套
half3 MixedLighting(MySurfaceData s, MyLightingData l, Light light)
{
    half NdotL = dot(l.normalWS, light.direction);

    // 1. 卡通分量
    half toon = smoothstep(0.5 - 0.05, 0.5 + 0.05, NdotL * 0.5 + 0.5);

    // 2. GGX 分量（PBR）
    half3 pbr = GGXSpecular(light.color, light.direction, l.normalWS,
                            l.viewDirWS, 1 - s.smoothness);

    // 3. SSS 分量
    half wrap = (NdotL + 0.5) / 1.5;
    half3 sss = light.color * wrap * half3(0.8, 0.3, 0.2) * 0.3;

    // 用 mask 混合（mask.r = 卡通, mask.g = PBR, mask.b = SSS）
    half3 diffuse = toon * light.color;
    half3 specular = lerp(half3(0,0,0), pbr, s.metallic);
    half3 scattering = sss * (1 - s.metallic);

    return (diffuse + specular + scattering) * s.albedo;
}
```

---

## 总结

### 光照模型速查表

| 模型 | 核心公式 | 适用 |
|---|---|---|
| Lambert | `NdotL` | 哑光 |
| Half-Lambert | `NdotL * 0.5 + 0.5` | 游戏通用 |
| Cel / Toon | `smoothstep` | 卡通 |
| Ramp | `tex2D(ramp, NdotL)` | 美术驱动 |
| GGX / PBR | `D * F * G / (4 * NdotL * NdotV)` | 写实金属 |
| Ward（各向异性）| `pow(aniso, exp)` | 布料 / 拉丝金属 |
| Kajiya-Kay | `sqrt(1 - TdotH²)` | 头发 |
| Wrap / SSS | `(NdotL + w) / (1 + w)` | 皮肤 / 蜡 |
| Foliage | `front + back² * tint` | 叶片 |

### 自定义光照架构（对齐项目）

```
Fragment()
├── 1. 法线准备（项目已有）
├── 2. 视差 / 颜色采样 / 镂空 / 法线贴图（项目已有）
├── 3. 填充 lightingInput / surfaceInput（项目已有）
├── 4. 烘焙 GI（项目已有：SampleLightmap / SampleSHPixel）
├── 5. 获取主光源：GetMainLight(shadowCoord, positionWS, shadowMask)
├── 6. 主光源 BRDF：自写 diffuse + specular
├── 7. 附加光源循环：LIGHT_LOOP_BEGIN / LIGHT_LOOP_END（项目已有结构）
├── 8. 环境光：SampleSHPixel(vertexSH, normalWS)
├── 9. 雾 / 反射 / SSAO / GI（若不想丢：显式调 URP 函数）
├── 10. 调试视图（可选）
└── 11. 返回
```

### 性能提示

+ **避免分支**：GPU 不擅长 `if`，优先 `lerp` / `step` / `smoothstep`
+ **预计算**：能放顶点就放顶点
+ **纹理采样贵**：把 mask 打包到同一张图
+ **用关键字控制**：材质级开关走 `shader_feature`

> **注意**：原稿"优化策略"表里有一行"延迟渲染路径 ⭐⭐⭐⭐ 高"——**误导**。本项目走 URP Forward。延迟渲染是整条管线的选择，不是 shader 层的优化手段，已删除。

---

## 与原翻译稿的差异对照

| # | 原稿 | 本项目 / 正确做法 |
|---|---|---|
| 1 | 未提"绕过 PBR 会丢哪些功能" | 新增"会丢失什么"清单（雾 / 反射 / GI / LightLayer / SSAO / Cookie / 调试）|
| 2 | `_BumpMap` / `_NormalScale` | `_NormalMap` / `_NormalStrength` |
| 3 | `SampleSH(normalWS)` | `SampleSHPixel(vertexSH, normalWS)`（片元）/ `SampleSHVertex`（顶点）|
| 4 | 未说明新属性放哪 | 明确要进 `CBUFFER_START(UnityPerMaterial)` |
| 5 | `switch` 实现调试视图 | `#if` 关键字式（推荐）；属性式也要用 if 链 |
| 6 | `NormalizeToColor` 先用后定义 | 已内联 / 前置 |
| 7 | 优化策略表含"延迟渲染路径" | 删除（本项目走 Forward）|
| 8 | 结构体名 `MySurfaceData` / `MyLightingData` 无归属 | 明确放 `MyLitCommon.hlsl` |
| 9 | 大括号不换行 | 大括号换行 |

---

## 下一步

+ 若真的要"绕过 PBR"：先按本文 3.4 的方法**保留 URP 侧的雾 / 反射 / GI**，只换 BRDF
+ 后续：`08_顶点动画.md` → 重写版 `Part8.md`

> 文档完。如有疑问，翻 `Docs/` 下的其他文档。
