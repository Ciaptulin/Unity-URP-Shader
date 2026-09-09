# URP 光源 Cookie 教程

> **适用版本**：Unity 2023.2.20f1 / URP 16.0.6  
> **适用项目**：Unity URP Shader — MyLit  
> **难度**：🟩 Shader 中等 + 🟦 场景配置简单

---

## 0. 什么是 Cookie

**Cookie**（也叫 Shadow Mask / Light Texture）是一张纹理，贴在光源上，用来**调制光源的强度和颜色分布**。

| 用途 | 示例 |
|------|------|
| 窗户投影 | 阳光穿过百叶窗在地面投下条纹 |
| 烛光闪烁 | 用噪声纹理让火焰的光忽明忽暗 |
| 体积光效 | 模拟光线穿过树叶的斑驳 |
| 遮挡效果 | 让光源只照亮特定形状的区域 |

本质上，Cookie 是一个 **2D 纹理**，光源在照射时用它来乘以光照强度：`finalColor *= cookieSample`。

---

## 1. 当前项目状态

### ✅ 已具备
- URP Asset 已启用 `m_SupportsLightCookies: 1`（Balanced / Performant / HighFidelity 全部已开）
- 附加光源 Cookie 分辨率已配置（Balanced=512, Performant=2048, HighFidelity=4096）

### ❌ 缺失
- `MyLit.shader` 没有声明 `_LIGHT_COOKIES` 关键字
- `MyLitForwardLitPass.hlsl` 没有 Cookie 采样代码
- 主光源和附加光源的 Cookie 均未处理

---

## 2. 工作原理

### 2.1 URP 的 Cookie 流程

```
光源 (Light)
    ↓
Cookie 纹理（贴在光源上的 2D 纹理）
    ↓
光源在照射时，根据表面点的位置采样 Cookie
    ↓
cookieSample ∈ [0, 1] 乘以光照强度
    ↓
finalColor = surfaceColor * lightColor * cookieSample * NdotL
```

### 2.2 主光源 vs 附加光源

| | 主光源 (Main Light) | 附加光源 (Additional Lights) |
|---|---|---|
| Cookie 支持 | ✅ 所有光源类型 | ✅ 仅 Spot Light（点光源和方向光不支持 Cookie） |
| 采样方式 | 自动采样（URP 内置） | 需要手动采样 |
| 关键字 | `_LIGHT_COOKIES` | `_LIGHT_COOKIES` |
| 性能 | 低（只有一个主光） | 中高（多个附加光源都要采样） |

### 2.3 Cookie 纹理坐标

Cookie 采样需要一个 **投影坐标**（把世界坐标投影到光源的纹理空间）：

| 光源类型 | 投影方式 |
|----------|----------|
| **Directional（方向光）** | 用 `worldPos.xy` 投影到正交的 Cookie 空间 |
| **Spot（聚光灯）** | 用透视投影，类似相机的 View-Projection 矩阵 |
| **Point（点光源）** | ❌ 不支持 Cookie |

URP 提供了内置函数来处理这些投影：

```hlsl
// 方向光 Cookie
float4 TransformWorldToCookiePositionWS(float3 positionWS, Light light);

// 聚光灯 Cookie
float4 TransformWorldToCookiePositionWS(float3 positionWS, Light light);
```

---

## 3. 实现步骤

### 3.1 🟦 场景配置（无需写代码）

#### 步骤 1：确认 URP Asset 已启用 Cookie

每个 URP Asset 都有以下设置（你的项目已经开了）：

```
URP-Balanced.asset:
  m_SupportsLightCookies: 1              ← 必须为 1
  m_AdditionalLightsCookieResolution: 512
  m_AdditionalLightsCookieFormat: 1
```

如果 `m_SupportsLightCookies` 是 0，Cookie 完全不会生效。

#### 步骤 2：给光源添加 Cookie 纹理

1. 在 Hierarchy 中选中一个 **Spot Light** 或 **Directional Light**
2. 在 Inspector 中找到 **Cookie** 属性
3. 拖入一张纹理（支持 2D 纹理或 Cube 纹理）
4. 调整 **Cookie Size** 控制投影大小

#### 步骤 3：Cookie 纹理导入设置

选中 Cookie 纹理文件，在 Inspector 中设置：

| 属性 | 推荐值 | 说明 |
|------|--------|------|
| **Texture Shape** | 2D（方向光/聚光灯）或 Cube（点光源，但 URP 不支持点光源 Cookie） | 决定投影方式 |
| **sRGB (Color Texture)** | ✅ 开启 | Cookie 是颜色数据，需要 sRGB |
| **Wrap Mode** | Clamp | 边缘不重复，避免接缝 |
| **Filter Mode** | Bilinear | 平滑采样 |
| **Generate Mip Maps** | ❌ 关闭 | Cookie 不需要 mip |

#### 步骤 4：验证场景

1. 创建一个 Spot Light，指向地面
2. 给它一个条纹纹理作为 Cookie
3. 运行场景，地面应该出现条纹光斑

---

### 3.2 🟩 Shader 修改

#### 步骤 1：声明关键字

在 `MyLit.shader` 的 ForwardLit Pass 中，添加：

```hlsl
#pragma multi_compile _ _LIGHT_COCKIES
```

> ⚠️ 注意：URP 16 的关键字名是 `_LIGHT_COOKIES`（带 I），不是 `_LIGHT_COCKIES`。

#### 步骤 2：在片元函数中采样 Cookie

在 `MyLitForwardLitPass.hlsl` 的 `Fragment()` 函数中，获取主光源后添加 Cookie 采样：

```hlsl
// 获取主光源（带阴影坐标和 AO）
Light mainLight = GetMainLight(lightingInput.shadowCoord, lightingInput.positionWS, half4(1,1,1,1));

#ifdef _LIGHT_COOKIES
    // 主光源 Cookie 采样
    float4 cookiePos = TransformWorldToCookiePositionWS(input.positionWS, mainLight);
    float cookieSample = SAMPLE_TEXTURE2D(_MainLightCookieTexture, sampler_MainLightCookieTexture, cookiePos.xy).r;
    mainLight.color *= cookieSample;  // 用 Cookie 调制光强
#endif
```

#### 步骤 3：附加光源 Cookie

在附加光源循环中：

```hlsl
uint additionalLightCount = GetAdditionalLightsCount();
for (uint i = 0u; i < additionalLightCount; i++)
{
    Light light = GetAdditionalLight(i, input.positionWS, half4(1,1,1,1));
    
    #ifdef _LIGHT_COOKIES
        // 附加光源 Cookie（仅 Spot Light 有效）
        if (light.cookie != null)  // 或者用关键字守卫
        {
            float4 cookiePos = TransformWorldToCookiePositionWS(input.positionWS, light);
            float cookieSample = SAMPLE_TEXTURE2D(_AdditionalCookieTexture, sampler_AdditionalCookieTexture, cookiePos.xy).r;
            light.color *= cookieSample;
        }
    #endif
}
```

#### 步骤 4：CBUFFER 更新

在 `MyLitCommon.hlsl` 中添加 Cookie 纹理声明：

```hlsl
TEXTURE2D(_MainLightCookieTexture); SAMPLER(sampler_MainLightCookieTexture);
TEXTURE2D(_AdditionalCookieTexture); SAMPLER(sampler_AdditionalCookieTexture);
```

---

## 4. 完整代码示例

### MyLit.shader（ForwardLit Pass 关键字部分）

```hlsl
// 在已有的 multi_compile 区域添加：
#pragma multi_compile _ _LIGHT_COOKIES
```

### MyLitForwardLitPass.hlsl（Fragment 函数）

```hlsl
float4 Fragment(Interpolators input
    #ifdef _DOUBLE_SIDED_NORMALS
    , FRONT_FACE_TYPE frontFace : FRONT_FACE_SEMANTIC
    #endif
    ) : SV_TARGET {
    
    // ... 前面的法线、UV、采样代码保持不变 ...
    
    InputData lightingInput = (InputData)0;
    lightingInput.positionWS = input.positionWS;
    lightingInput.normalWS = normalWS;
    lightingInput.viewDirectionWS = viewDirWS;
    lightingInput.shadowCoord = TransformWorldToShadowCoord(input.positionWS);
    lightingInput.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(input.positionCS);
    lightingInput.shadowMask = half4(1.0, 1.0, 1.0, 1.0);
    
    // ... 后面的 SurfaceData 构建保持不变 ...
    
    return UniversalFragmentPBR(lightingInput, surfaceInput);
}
```

### 方案 A：让 URP 自动处理 Cookie（推荐）

**URP 的 `UniversalFragmentPBR` 内部已经处理了主光源 Cookie**。如果你只是想让 Cookie 生效，只需要：

1. 在 Shader 中声明 `#pragma multi_compile _ _LIGHT_COOKIES`
2. 确保 URP Asset 的 `m_SupportsLightCookies = 1`
3. 给光源拖入 Cookie 纹理

**不需要手动采样 Cookie**，URP 会自动在 `GetMainLight()` 返回的 `Light` 中应用 Cookie。

### 方案 B：手动采样 Cookie（自定义光照模型）

如果你使用了自定义 BRDF（如教程 Part 7 的 `MyLitCustomBRDF.hlsl`），则需要手动采样：

```hlsl
#ifdef _LIGHT_COOKIES
    // 主光源 Cookie
    float4 mainCookiePos = TransformWorldToCookiePositionWS(input.positionWS, mainLight);
    float mainCookie = SAMPLE_TEXTURE2D(_MainLightCookieTexture, sampler_MainLightCookieTexture, mainCookiePos.xy).r;
    mainLight.color *= mainCookie;
#endif
```

---

## 5. 调试

### 5.1 Cookie 不生效排查

| 现象 | 排查 |
|------|------|
| Cookie 完全没效果 | 检查 URP Asset 的 `m_SupportsLightCookies` 是否为 1 |
| Cookie 投影方向反了 | 检查 Cookie 纹理的 `Texture Shape` 是否正确 |
| Cookie 边缘有接缝 | 将纹理的 `Wrap Mode` 改为 `Clamp` |
| 附加光源 Cookie 无效 | 确认光源类型是 Spot Light（点光源不支持 Cookie） |
| Cookie 太模糊/太锐利 | 调整纹理的 `Filter Mode` 和分辨率 |
| 编译报错 `_LIGHT_COOKIES` | 确认关键字拼写正确（带 I） |

### 5.2 可视化 Cookie

```hlsl
// 在 Fragment 中直接输出 Cookie 值
#ifdef _LIGHT_COOKIES
    float4 cookiePos = TransformWorldToCookiePositionWS(input.positionWS, mainLight);
    float cookieVal = SAMPLE_TEXTURE2D(_MainLightCookieTexture, sampler_MainLightCookieTexture, cookiePos.xy).r;
    return float4(cookieVal.xxx, 1);
#endif
```

---

## 6. 性能

| 项 | 说明 |
|------|------|
| **主光源 Cookie** | 几乎零成本（URP 自动处理） |
| **附加光源 Cookie** | 每个 Spot Light 多一次纹理采样，注意光源数量 |
| **Cookie 纹理分辨率** | 方向光建议 512~2048，聚光灯建议 256~1024 |
| **变体数量** | `_LIGHT_COOKIES` 是 `multi_compile`，会增加一倍变体 |

---

## 7. 落到 MyLit 项目的检查清单

| # | 项目 | 位置 | 状态 |
|---|------|------|------|
| ① | URP Asset 启用 Cookie | Settings/URP-*.asset | ✅ 已启用 |
| ② | Shader 声明 `_LIGHT_COOKIES` 关键字 | MyLit.shader | ❌ 待添加 |
| ③ | 确认 `UniversalFragmentPBR` 自动处理 | MyLitForwardLitPass.hlsl | ✅ 自动 |
| ④ | 给光源添加 Cookie 纹理 | 场景中的 Spot/Dir Light | 🟦 待配 |
| ⑤ | Cookie 纹理导入设置 | 纹理资产 | 🟦 待配 |
| ⑥ | 测试 Cookie 效果 | 场景 | 🟦 待验证 |

---

## 8. 快速验证步骤

1. **打开 URP-Balanced.asset** → 确认 `m_SupportsLightCookies = 1` ✅
2. **在 MyLit.shader 中添加**：`#pragma multi_compile _ _LIGHT_COOKIES`
3. **在 SampleScene 中创建一个 Spot Light**
4. **给 Spot Light 的 Cookie 属性拖入一张纹理**
5. **运行场景** → 地面应该出现 Cookie 投影效果

---

*教程最后更新：2026-09-06*
