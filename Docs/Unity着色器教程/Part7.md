# Part 7 · 自定义光照模型（BRDF）

> **本节在整份教程中的位置**
> Part 1~6 我们一直在"用 URP 的东西"：`UniversalFragmentPBR` 帮你算 D/F/G、帮你采样反射探针、帮你处理阴影与 GI。本节要把它**换掉**，自己写。
>
> 用标签区分：
>
> - 🟪 **【原理】** — BRDF 数学。读代码的时候要懂，但大部分不用你自己写。
> - 🟩 **【Shader】** — 真正要落地的代码：替换点在哪、API 怎么调、怎么写才不会和 URP 脱节。
> - ⚠️ **纠错** — 本节有一整节用于指出旧版教程代码中的错误，**照抄旧版会得到"看起来能跑但完全不对"的结果**。
>
> **版本基准：Unity 2023.2.20f1 / URP 16.0.6。**
> 涉及 URP 源码：`ShaderLibrary/BRDF.hlsl`、`Lighting.hlsl`、`RealtimeLights.hlsl`、`GlobalIllumination.hlsl`。

---

## 0. 这一节到底要解决什么问题

**先问：你真的需要自定义 BRDF 吗？**

| 需求 | 该改什么 | 需要自定义 BRDF 吗 |
|---|---|---|
| 金属/粗糙度表现不对 | SurfaceData 的输入值 | ❌ |
| 想要更锐/更柔的高光 | 换 NDF 或改 roughness 映射 | ⚠️ 部分 |
| 卡通渲染、风格化阶梯 | 光照结果的**后处理** | ✅ |
| 次表面散射、各向异性 | 新的 BRDF 项 | ✅ |
| 只是想"更亮/更暗" | 灯光与后处理 | ❌ |

**代价必须提前说清楚**：一旦自己写光照，下面这些 URP 已经帮你做好的东西，**全部要自己接回来**：

- 反射探针采样 + 盒投影 + 多探针混合
- 烘焙 GI / 光照探针
- SSAO 与贴图 AO
- 光源 Cookie
- Light Layers

> **一句话概括本节**：
> 自定义 BRDF 的正确姿势不是"从零写一套 PBR"，而是"**只替换你想要的那一项，其余继续复用 URP 的组件**"。

---

## 1. 🟪 微表面 BRDF 速览

镜面反射的标准形式：

```
f(l,v) = D · F · V          （V 已经包含了 1/(4·NdotL·NdotV)）
       = D · F · G / (4·NdotL·NdotV)
```

三（四）个函数各管一件事：

| 项 | 名字 | 决定什么 | 粗糙时的表现 |
|---|---|---|---|
| **D** | 法线分布 NDF | 高光的**形状与大小** | 峰值变矮变宽 |
| **F** | 菲涅尔 | 高光的**颜色与边缘增强** | 与粗糙度无关 |
| **G / V** | 几何遮蔽 | **掠射角**的能量损失 | 掠射处更暗 |
| — | 分母 `4·NdotL·NdotV` | 从"微表面分布密度"到"可见反射率"的归一化 | — |

两个必须记住的约定：

1. **能量守恒**：漫反射 + 镜面反射 ≤ 1。URP 的做法是 `diffuse = albedo * (1 - reflectivity)`，镜面部分再乘菲涅尔。
2. **感知粗糙度 ≠ 物理粗糙度**：
   - `perceptualRoughness = 1 - smoothness`（滑条上的值）
   - `alpha = perceptualRoughness²`（喂给 D/F/V 的"粗糙度"）

> ⚠️ 这也是旧版代码第一个不一致的地方：它把 `1 - smoothness` 直接当 `roughness` 平方后使用，导致同一个 Smoothness 滑条在你的模型和 URP 内置 Lit 上**看起来不一样**。

### 1.1 各向同性 vs 各向异性

- **各向同性**：绕法线旋转，BRDF 不变（石头、塑料、大部分材质）。
- **各向异性**：随方位角变化（拉丝金属、头发、CD）。需要额外一个**切线方向**，用两个粗糙度 `αx / αy` 代替一个 `α`。

---

## 2. 🟩 接入点：到底改哪一行

`MyLitForwardLitPass.hlsl` 的最后一行：

```hlsl
return UniversalFragmentPBR(lightingInput, surfaceInput);
```

**前面所有的采样、`SurfaceData` / `InputData` 构建全部保留**——那是 Part 1~5 的成果，与光照模型无关。你只替换最后这一步。

### 2.1 两条路线

| | 路线 A：拼装 URP 组件（推荐） | 路线 B：纯手写 |
|---|---|---|
| 做法 | 用 `InitializeBRDFData` + `LightingPhysicallyBased` + `EnvironmentBRDF`，只改合成方式 | 自己写 D/F/V 与环境项 |
| 保住的 URP 特性 | 清漆、能量守恒、AO、环境 BRDF | 全部要自己接 |
| 适合 | 卡通/风格化、加一层特效 | 研究、非真实感模型、各向异性 |

### 2.2 路线 A：卡通渲染、风格化的正确落地方式

思路：**不要去改物理光照，而是在它输出的结果上做风格化**。

```hlsl
// MyLitForwardLitPass.hlsl 末尾
half4 pbrColor = UniversalFragmentPBR(lightingInput, surfaceInput);

#ifdef _TOON_SHADING
    // 1. 拿到主光的 NdotL，做阶梯化
    Light mainLight = GetMainLight(lightingInput.shadowCoord, lightingInput.positionWS, half4(1,1,1,1));
    half NdotL = dot(lightingInput.normalWS, mainLight.direction);
    half banded = floor(saturate(NdotL) * _ToonSteps) / _ToonSteps;

    // 2. 用阶梯值缩放整体亮度（保留 URP 的 GI、反射、阴影）
    pbrColor.rgb *= banded;
#endif

return pbrColor;
```

优点：**一行关键字切换**，GI、反射探针、阴影、AO 全部照常工作。旧版教程那种"卡通渲染重新写一遍光照循环"的做法，等于主动放弃整个 URP 光照系统，最后还要一个个补回来。

### 2.3 路线 B：完全自己写（正确版）

```hlsl
// ── 1. 预计算 ────────────────────────────────────────
half3 normalWS = lightingInput.normalWS;
half3 viewDirWS = lightingInput.viewDirectionWS;
half perceptualRoughness = 1.0 - surfaceInput.smoothness;
half alpha  = max(perceptualRoughness * perceptualRoughness, 0.002); // α
half alpha2 = alpha * alpha;

// F0：非金属 0.04，金属取 albedo
half3 F0 = lerp((half3)0.04, surfaceInput.albedo, surfaceInput.metallic);
half3 diffuseColor = surfaceInput.albedo * (1.0 - surfaceInput.metallic);

// ── 2. 单项函数 ──────────────────────────────────────
half D_GGX(half NdotH, half a2)
{
    half d = NdotH * NdotH * (a2 - 1.0) + 1.00001;
    return a2 / (PI * d * d);
}

half3 F_Schlick(half3 f0, half VdotH)
{
    return f0 + (1.0 - f0) * pow(1.0 - VdotH, 5.0);
}

// Smith height-correlated visibility —— 注意它已经含 1/(4·NdotL·NdotV)
half V_SmithGGX(half NdotL, half NdotV, half a2)
{
    half ggxL = NdotV * sqrt(NdotL * NdotL * (1.0 - a2) + a2);
    half ggxV = NdotL * sqrt(NdotV * NdotV * (1.0 - a2) + a2);
    return 0.5 / max(ggxL + ggxV, 1e-5);
}

// ── 3. 直接光 ────────────────────────────────────────
half3 DirectPBR(half3 lightColor, half3 lightDirWS, half shadowAttenuation)
{
    half3 halfVec = normalize(lightDirWS + viewDirWS);
    half NdotL = saturate(dot(normalWS, lightDirWS));
    half NdotV = max(dot(normalWS, viewDirWS), 1e-4);
    half NdotH = saturate(dot(normalWS, halfVec));
    half VdotH = saturate(dot(viewDirWS, halfVec));

    half3 F = F_Schlick(F0, VdotH);
    half  D = D_GGX(NdotH, alpha2);
    half  V = V_SmithGGX(NdotL, NdotV, alpha2);

    half3 specular = D * F * V;                 // ← 不要再除以 4·NdotL·NdotV
    half3 diffuse  = diffuseColor * (1.0 - F) * INV_PI;

    return (diffuse + specular) * lightColor * NdotL * shadowAttenuation;
}

// ── 4. 环境光（复用 URP，别自己采样 Cubemap）────────────
half3 reflectVector = reflect(-viewDirWS, normalWS);
half3 indirectSpecular = GlossyEnvironmentReflection(
    reflectVector,
    lightingInput.positionWS,            // 盒投影需要它
    perceptualRoughness,
    surfaceInput.occlusion,
    lightingInput.normalizedScreenSpaceUV);

half NoV = saturate(dot(normalWS, viewDirWS));
half fresnelTerm = Pow4(1.0 - NoV);
half3 environment = EnvironmentBRDF(brdfData, lightingInput.bakedGI, indirectSpecular, fresnelTerm);

// ── 5. 合成 ──────────────────────────────────────────
half3 color = environment + surfaceInput.emission;

half4 shadowMask = half4(1, 1, 1, 1);
Light mainLight = GetMainLight(lightingInput.shadowCoord, lightingInput.positionWS, shadowMask);
color += DirectPBR(mainLight.color * mainLight.distanceAttenuation, mainLight.direction, mainLight.shadowAttenuation);

uint lightCount = GetAdditionalLightsCount();
for (uint i = 0u; i < lightCount; i++)
{
    // 第二参数是 positionWS，不是法线
    Light light = GetAdditionalLight(i, lightingInput.positionWS, shadowMask);
    color += DirectPBR(light.color * light.distanceAttenuation, light.direction, light.shadowAttenuation);
}

return half4(color, surfaceInput.alpha);
}
```

以下是项目中的完整实现代码（`MyLitCustomBRDF.hlsl`）：

```hlsl
#ifndef MY_LIT_CUSTOM_BRDF_INCLUDED
#define MY_LIT_CUSTOM_BRDF_INCLUDED

// 本文件由 MyLitForwardLitPass.hlsl 在 _CUSTOM_BRDF 关键字下使用。
// 依赖 URP 的 InputData / SurfaceData / Light / BRDFData，这里显式引入保证自洽（都有 include 守卫）。
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/AmbientOcclusion.hlsl"

// ─────────────────────────────────────────────────────────────
// D：GGX 法线分布函数
//     alpha2 = (perceptualRoughness²)²，与 URP 的 roughness2 对齐
// ─────────────────────────────────────────────────────────────
half CustomD_GGX(half NdotH, half alpha2)
{
    half d = NdotH * NdotH * (alpha2 - 1.0) + 1.00001;
    return alpha2 / (PI * d * d);
}

// ─────────────────────────────────────────────────────────────
// F：Schlick 菲涅尔近似
// ─────────────────────────────────────────────────────────────
half3 CustomF_Schlick(half3 f0, half VdotH)
{
    half f  = saturate(1.0 - VdotH);
    half f5 = f * f * f * f * f;               // pow(1 - VdotH, 5)
    return f0 + (1.0 - f0) * f5;
}

// ─────────────────────────────────────────────────────────────
// V：Smith height-correlated visibility
//     ⚠️ 它已经包含 1 / (4 * NdotL * NdotV)，调用处不要再除一次！
// ─────────────────────────────────────────────────────────────
half CustomV_SmithGGX(half NdotL, half NdotV, half alpha2)
{
    half lambdaV = NdotL * sqrt(NdotV * NdotV * (1.0 - alpha2) + alpha2);
    half lambdaL = NdotV * sqrt(NdotL * NdotL * (1.0 - alpha2) + alpha2);
    return 0.5 / max(lambdaV + lambdaL, 1e-5);
}

// ─────────────────────────────────────────────────────────────
// 单个光源的直接光：diffuse + specular
//   注意：URP 内置 Lit 的漫反射不除 π（灯光单位约定不同），这里跟随 URP
//   以便切换关键字时亮度可直接对比。若要以辐射亮度为单位做严格物理，
//   给 diffuse 乘上 INV_PI 即可。
// ─────────────────────────────────────────────────────────────
half3 CustomDirectBRDF(half3 diffuseColor, half3 F0, half alpha2,
                       half3 normalWS, half3 viewDirWS, Light light)
{
    half3 halfVec = normalize(light.direction + viewDirWS);

    half NdotL = saturate(dot(normalWS, light.direction));
    half NdotV = max(dot(normalWS, viewDirWS), 1e-4);
    half NdotH = saturate(dot(normalWS, halfVec));
    half VdotH = saturate(dot(viewDirWS, halfVec));

    half3 F = CustomF_Schlick(F0, VdotH);
    half  D = CustomD_GGX(NdotH, alpha2);
    half  V = CustomV_SmithGGX(NdotL, NdotV, alpha2);

    half3 specular = D * V * F;                // V 已含 1/(4*NdotL*NdotV)
    half3 diffuse  = diffuseColor * (1.0 - F); // 能量守恒：被反射走的那部分不再漫反射

    half3 radiance = light.color * (light.distanceAttenuation * light.shadowAttenuation);
    return (diffuse + specular) * radiance * NdotL;
}

// ─────────────────────────────────────────────────────────────
// 自定义光照入口：替换 UniversalFragmentPBR
//   环境部分完全复用 URP（反射探针/盒投影/混合/GI/环境 BRDF 都不重写），
//   只把"直接光怎么算"换成上面的 D·F·V。
// ─────────────────────────────────────────────────────────────
half4 CustomLighting(InputData inputData, SurfaceData surfaceData)
{
    half3 normalWS  = inputData.normalWS;
    half3 viewDirWS = inputData.viewDirectionWS;

    half perceptualRoughness = 1.0 - surfaceData.smoothness;
    half alpha  = max(perceptualRoughness * perceptualRoughness, 0.002);
    half alpha2 = alpha * alpha;

    half3 F0           = lerp((half3)0.04, surfaceData.albedo, surfaceData.metallic);
    half3 diffuseColor = surfaceData.albedo * (1.0 - surfaceData.metallic);

    half4 shadowMask = CalculateShadowMask(inputData);
    AmbientOcclusionFactor aoFactor = CreateAmbientOcclusionFactor(inputData, surfaceData);

    // ── 直接光：主光 + 附加光 ──
    half3 color = 0;

    Light mainLight = GetMainLight(inputData, shadowMask, aoFactor);
    color += CustomDirectBRDF(diffuseColor, F0, alpha2, normalWS, viewDirWS, mainLight);

    uint additionalLightCount = GetAdditionalLightsCount();
    for (uint i = 0u; i < additionalLightCount; i++)
    {
        Light light = GetAdditionalLight(i, inputData, shadowMask, aoFactor);
        color += CustomDirectBRDF(diffuseColor, F0, alpha2, normalWS, viewDirWS, light);
    }

    // ── 环境光：复用 URP 的 BRDFData 与环境 BRDF ──
    BRDFData brdfData;
    InitializeBRDFData(surfaceData, brdfData);

    half3 reflectVector = reflect(-viewDirWS, normalWS);
    half3 indirectSpecular = GlossyEnvironmentReflection(
        reflectVector,
        inputData.positionWS,                  // 盒投影需要它
        perceptualRoughness,
        surfaceData.occlusion,
        inputData.normalizedScreenSpaceUV);

    half NoV = saturate(dot(normalWS, viewDirWS));
    half fresnelTerm = Pow4(1.0 - NoV);
    half3 environment = EnvironmentBRDF(brdfData, inputData.bakedGI, indirectSpecular, fresnelTerm);

    color += environment * aoFactor.indirectAmbientOcclusion;
    color += surfaceData.emission;

    return half4(color, surfaceData.alpha);
}

#endif
```

> `brdfData` 通过 `InitializeBRDFData(surfaceInput, brdfData)` 得到，`INV_PI` / `PI` / `Pow4` 都在 URP 的 `Common.hlsl` / `BRDF.hlsl` 里。

---

## 3. ⚠️ 旧版代码错在哪（逐条对照）

| # | 旧版写法 | 问题 | 后果 |
|---|---|---|---|
| 1 | `SmithGGXGeometry()` 返回 `0.5/(ggxV+ggxL)`，之后又 `/(4*NdotL*NdotV)` | 返回值是 **V**（已含分母），又被除了一次 | 高光暗到几乎看不见 |
| 2 | 把 `1 - smoothness` 当 `roughness`，内部再平方 | α 的换算与 URP 不一致（URP 是 `α = perceptual²`） | 同一 Smoothness 值，你的模型与内置 Lit 观感不同 |
| 3 | `GetAdditionalLight(i, normalWS)` | 第二参数是 **世界坐标** | 方向、衰减、阴影全错 |
| 4 | `GlossyEnvironmentReflection(reflectDir, roughness, 1)` | 少传 `positionWS`（三参旧重载） | **盒投影失效**，室内反射穿帮 |
| 5 | `surfaceInput.anisotropy = 0` | URP 16 的 `SurfaceData` **没有这个字段** | 编译报错 |
| 6 | `UniversalFragmentPBR(input, normalWS, viewDirWS, ...)` | 正确签名只有两个参数 | 编译报错 |
| 7 | `SchlickFresnel(float F0, ...)` 却传 `float3` | 类型不匹配 | 编译报错 / 隐式截断 |
| 8 | `float3 diffuse = albedo * (1 - metallic) / 3.14159;` 再乘 `NdotL`，同时又算了未使用的 `diffuseRatio/specularRatio` | 冗余且未做能量守恒（`1 - F` 那一项丢了） | 金属边缘偏亮 |
| 9 | 卡通代码：`smoothstep(quantized - blur, quantized + blur, NdotL)` | 对**已经量化过**的值再做 smoothstep，逻辑颠倒 | 阶梯位置错乱，不是期望的硬边 |
| 10 | Oren-Nayar 里用 `acos / sin / tan` 逐像素 | 不是错误，但极贵 | 移动端几乎不可用 |

---

## 4. 🟩 三种常见高级模型

### 4.1 卡通 / 赛璐璐（Toon）

三个核心操作：

```hlsl
// ① 漫反射阶梯化（推荐用 smoothstep 做"软硬可调"的边）
half NdotL = saturate(dot(normalWS, lightDirWS));
half band  = floor(NdotL * _ToonSteps) / _ToonSteps;
half soft  = smoothstep(band, band + _ToonEdgeSoftness, NdotL);
half toon  = lerp(band, soft, _ToonEdgeSoftness);

// ② 硬边高光（step 而不是 pow）
half NdotH = saturate(dot(normalWS, normalize(lightDirWS + viewDirWS)));
half spec  = step(_SpecularThreshold, NdotH) * surfaceInput.smoothness;

// ③ 边缘光 Rim
half rim = pow(1.0 - saturate(dot(normalWS, viewDirWS)), _RimPower) * _RimIntensity;
```

两个要点：

- **阴影也要卡通化**：`shadowAttenuation = step(0.5, mainLight.shadowAttenuation)`，否则软阴影会和硬边的受光区打架。
- **保留 ShadowCaster Pass**：卡通 Shader 一样要投阴影，用 `UsePass "Universal Render Pipeline/Lit/ShadowCaster"` 或直接复用项目里的 `MyLitShadowCasterPass.hlsl`。

### 4.2 次表面散射（SSS）

**原理**：光进入半透明介质，内部散射后从别处射出。耳廓、鼻尖、蜡烛、玉石在背光时透红，就是这个。

最划算的做法是 **Wrap Lighting**（只改漫反射项）：

```hlsl
// wrap = 0 → 标准 Lambert；wrap = 1 → 最强散射
half wrapped = saturate((dot(normalWS, lightDirWS) + _Wrap) / (1.0 + _Wrap));
half3 diffuse = diffuseColor * wrapped;

// 背光透射项：视线越接近"逆着光"，越亮
half back = pow(saturate(dot(viewDirWS, -(lightDirWS + normalWS * _Distortion))), _ScatterPower);
half3 sss = _ScatterColor * back * _Thickness;   // _Thickness 来自厚度贴图（黑=薄）
```

进阶方案（了解即可）：预积分皮肤 LUT（以 `NdotL` 与曲率为 UV 查表）、屏幕空间可分离模糊。

### 4.3 各向异性高光

需要**两个**粗糙度，并且需要切线：

```hlsl
half3 tangentWS   = normalize(input.tangentWS.xyz);
half3 bitangentWS = cross(normalWS, tangentWS) * input.tangentWS.w;  // w 是手性，不能丢

half TdotH = dot(tangentWS, halfVec);
half BdotH = dot(bitangentWS, halfVec);
half NdotH = saturate(dot(normalWS, halfVec));

half ax = max(perceptualRoughness * (1.0 + _Anisotropy), 0.002);
half ay = max(perceptualRoughness * (1.0 - _Anisotropy), 0.002);

// 各向异性 GGX
half e  = (TdotH * TdotH) / (ax * ax) + (BdotH * BdotH) / (ay * ay) + NdotH * NdotH;
half D  = 1.0 / (PI * ax * ay * e * e);
// F、V 沿用各向同性版本，V 用 sqrt(ax * ay) 作为等效 α
```

- `_Anisotropy ∈ [-1, 1]`：正值沿切线拉长高光，负值沿副切线。
- 头发常用**双高光**（R 峰 + TT 峰）：第二个峰把半程向量沿切线偏移一点再算一次 GGX。完整 Marschner 模型过于复杂，游戏里一般用这个近似。

---

## 5. 调试自定义光照模型

### 5.1 把中间量画出来

最快的方式就是 `return` 它：

```hlsl
#ifdef _DEBUG_BRDF
    return half4((half3)D, 1);          // D：高光中心应有明显峰值
    return half4(F, 1);                 // F：正视角应≈F0，掠射→1
    return half4((half3)V, 1);          // V：掠射角应显著变暗
    return half4(diffuse, 1);           // 漫反射
    return half4(specular, 1);          // 高光
    return half4(normalWS * 0.5 + 0.5, 1); // 法线（调试输出时才做 0.5+0.5）
#endif
```

> ⚠️ 注意最后一行：**只有调试可视化**才需要 `*0.5+0.5`。URP 的 `_CameraNormalsTexture` 是 SNorm 格式，DepthNormals Pass 里不能这么写（见 Part 5 §6.2）。

### 5.2 与内置 PBR 并排对比

在同一个 Shader 里留一个关键字，切换内置/自定义，用同一盏灯、同一个球对比：

```hlsl
#ifdef _DEBUG_USE_BUILTIN_PBR
    return UniversalFragmentPBR(lightingInput, surfaceInput);
#else
    return half4(customColor, surfaceInput.alpha);
#endif
```

**验收标准**：在 `metallic = 0 / 1`、`smoothness = 0 / 0.5 / 1` 六个组合下，你的结果应和内置 Lit **大致一致**（允许风格差异，不允许整体亮度差一个量级）。

### 5.3 坑点排查表

| 现象 | 原因 |
|---|---|
| 高光几乎看不见 | 重复除以 `4·NdotL·NdotV`（错误 #1） |
| 整体偏暗 | 忘了加 `bakedGI` / 环境项；忘了乘 `lightColor` |
| 金属发黑 | 金属漫反射被清零却没拿到环境反射（`GlossyEnvironmentReflection` 参数不对，或场景无探针/天空盒） |
| 高光位置随相机乱跑 | `viewDirWS` 未归一化，或用了 `GetWorldSpaceViewDir`（未归一化版本） |
| 附加光源方向全错 | `GetAdditionalLight` 传了法线而不是 `positionWS` |
| 掠射角出现白边/黑边 | V 项写错或 NdotV 未 clamp |
| 编译报"undeclared identifier anisotropy/normalTS" | 用了 URP 16 不存在的 `SurfaceData` 字段 |

---

## 6. 本节结论：落到项目上的建议

| # | 建议 | 说明 |
|---|---|---|
| ① | 优先用**路线 A**（复用 URP 组件） | 保住 GI、反射、AO、Cookie |
| ② | 自定义代码放在 `MyLitForwardLitPass.hlsl` 末尾 | 前面的采样与结构体构建不动 |
| ③ | 环境项**一定复用** `GlossyEnvironmentReflection` + `EnvironmentBRDF` | 手写 Cubemap 采样会丢掉盒投影与混合 |
| ④ | 用关键字切内置/自定义 | 便于 A/B 对比，也便于回退 |
| ⑤ | 别动 `SurfaceData` / `InputData` 的字段结构 | 它们是 URP 的契约 |

---

## 小结

- BRDF = **D · F · V**，V 已包含 `1/(4·NdotL·NdotV)`，别重复除。
- 粗糙度换算要和 URP 对齐：`perceptualRoughness = 1 - smoothness`，`α = perceptualRoughness²`。
- **自定义 ≠ 重写**：能复用 `InitializeBRDFData` / `LightingPhysicallyBased` / `EnvironmentBRDF` 就复用。
- 风格化（卡通）最省事的做法是**对 PBR 的输出做二次处理**，而不是另起炉灶。

下一节（Part 8）我们离开片元函数，回到顶点阶段——用顶点动画让网格动起来。
