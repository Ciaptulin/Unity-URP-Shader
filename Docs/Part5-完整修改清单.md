# Part5 完整修改清单（本项目实况版）

> 对照教程第九节生成，但以 `Assets/Shader/MyLit/` 的实际代码为准。
> 教程示例里的 Pass 名、结构体名、关键字写法与本项目不同，均已按实际更新。
> 生成时间：Part5 收尾阶段

---

## 一、MyLit.shader

### Pass 总览（6 个）

| # | Pass 名 | LightMode | 状态 |
|---|---|---|---|
| 1 | ForwardLit | `UniversalForward` | ✅ |
| 2 | ShadowCaster | `ShadowCaster` | ✅ |
| 3 | Meta | `Meta` | ✅ |
| 4 | DepthOnly | `DepthOnly` | ✅ |
| 5 | DepthNormals | `DepthNormals` | ✅ |
| 6 | MotionVectors | `MotionVectors` | ✅ |

### ForwardLit 关键字核对

**材质级（`shader_feature_local*`）**：

- [x] `_NORMALMAP`（fragment）
- [x] `_SPECULAR_SETUP`（fragment）
- [x] `_ROUGHNESS_SETUP`（fragment）
- [x] `_ALPHAPREMULTIPLY_ON`（fragment）
- [x] `_EMISSION`（fragment）
- [x] `_OCCLUSIONMAP`（fragment）
- [x] `_CLEARCOATMAP`
- [x] `_ALPHA_CUTOUT`
- [x] `_DOUBLE_SIDED_NORMALS`

**引擎级（`multi_compile*`）**：

- [x] `_MAIN_LIGHT_SHADOWS` / `_MAIN_LIGHT_SHADOWS_CASCADE`
- [x] `_SHADOWS_SOFT`（fragment）
- [x] `_ADDITIONAL_LIGHTS`
- [x] `_ADDITIONAL_LIGHT_SHADOWS`（fragment）
- [x] `_MAIN_LIGHT_COOKIE`
- [x] `_ADDITIONAL_LIGHTS_COOKIE`
- [x] `_REFLECTION_PROBE_BLENDING`（fragment）
- [x] `_REFLECTION_PROBE_BOX_PROJECTION`（fragment）
- [x] `_LIGHT_LAYERS`（fragment）
- [x] `_SCREEN_SPACE_OCCLUSION`（fragment）
- [x] `DIRLIGHTMAP_COMBINED`
- [x] `LIGHTMAP_ON`
- [x] `DYNAMICLIGHTMAP_ON`
- [x] `LIGHTMAP_SHADOW_MIXING`
- [x] `SHADOWS_SHADOWMASK`
- [x] `_DEBUG_BAKED_GI`
- [x] `DEBUG_DISPLAY`（fragment）

### Properties 核对

- [x] `_OcclusionMap` + `_OcclusionStrength`（含 `[Toggle(_OCCLUSIONMAP)]`）
- [x] `_Cull` / `_SourceBlend` / `_DestBlend` / `_ZWrite`（HideInInspector）
- [x] `_SurfaceType` / `_BlendType` / `_FaceRenderingMode`（HideInInspector）
- [x] `unity_Lightmaps` / `unity_LightmapsInd` / `unity_ShadowMasks`

---

## 二、MyLitCommon.hlsl

- [x] `CBUFFER_START(UnityPerMaterial)` 内含 `_OcclusionStrength`
- [x] `TEXTURE2D(_OcclusionMap); SAMPLER(sampler_OcclusionMap);`
- [x] `TestAlphaClip` 函数
- [x] `CalculateDotMatrix` 两个重载（worldPos 版 + uv 版）

---

## 三、MyLitForwardLitPass.hlsl

- [x] Attributes 含 `uv2 : TEXCOORD1`（光照贴图 UV）
- [x] Interpolators 含 `uv2`、`vertexSH`
- [x] Vertex 里 `OUTPUT_LIGHTMAP_UV` + `SampleSHVertex`
- [x] Fragment 里 `SampleLightmap` / `SampleSHPixel` 分支
- [x] Fragment 里 `surfaceInput.occlusion` 采样（`_OCCLUSIONMAP` 分支）
- [x] `lightingInput.normalizedScreenSpaceUV`（SSAO 修复）

---

## 四、新建文件核对

- [x] `MyLitDepthNormalsPass.hlsl`
- [x] `MyLitMotionVectorPass.hlsl`

---

## 五、场景设置核对

- [ ] 场景内有反射探针（GameObject > Light > Reflection Probe）
- [ ] 需要烘焙的物体启用 `Static` + `Contribute GI`
- [ ] 需要烘焙的光源设成 `Baked` 或 `Mixed` 模式
- [ ] 执行 `Window > Rendering > Lighting > Generate Lighting`
- [ ] URP Asset 里配置 `Additional Lights`（Per Pixel / Per Vertex、数量上限）
- [ ] 加了 Spot Light 用于测试附加光源阴影（本轮已加）

---

## 六、教程第九节 vs 本项目的差异（重要）

教程示例的写法**已过时/简化**，本项目采用更贴近 URP 官方 Lit 的做法：

| 项 | 教程示例 | 本项目 |
|---|---|---|
| 顶点输出结构体名 | `Varyings` / `Interpolators` 混用 | 统一 `Interpolators` |
| DepthNormals 的 LightMode | `DepthNormalsOnly` | `DepthNormals`（URP Lit 同款）|
| MotionVectors 上一帧矩阵 | `_PrevViewProjM` ❌ 不存在 | `_PrevViewProjMatrix` + `_NonJitteredViewProjMatrix` |
| 法线输出 | `normalWS * 0.5 + 0.5` | `NormalizeNormalPerPixel(normalWS)`（SNorm 格式）|
| 大括号风格 | 混合 | 统一换行 |
| MotionVectors 编码 | 自己 `* 0.5` / y 翻转 | 调 `CalcNdcMotionVectorFromCsPositions` |

---

## 七、Part5 功能验收清单

对照 Part5 全部特性，实际可用性检查：

| 特性 | 代码就绪 | 场景验证 |
|---|---|---|
| 附加光源 | ✅ | ⏳ 用 Spot Light 测 |
| 附加光源阴影 | ✅ | ⏳ |
| 烘焙光照 | ✅ | ✅（lightmap 已烘焙）|
| 光照探针 SH 兜底 | ✅ | ✅ |
| 遮挡贴图 | ✅ | ⏳ |
| 反射探针 | ✅ | ✅（ReflectionProbe 资源已存在）|
| 反射探针混合 / 盒投影 | ✅ | ⏳ |
| 光源 Cookie | ✅ | ⏳ 需配 Cookie 纹理 |
| 光源层级 | ✅ | ⏳ |
| SSAO | ✅（normalizedScreenSpaceUV 已补）| ⏳ |
| DepthNormals Pass | ✅ | ⏳ 开 SSAO 验证 |
| MotionVectors Pass | ✅ | ⏳ 开 Motion Blur 验证 |
| 调试（Rendering Debugger）| ✅ | ⏳ |

---

> **下一步建议**：把"⏳ 未验证"逐项在 SampleScene 里过一遍，每项验证后打勾。
