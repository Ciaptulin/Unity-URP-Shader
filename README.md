# Unity URP Shader — MyLit

一个基于 Unity URP 的自定义 PBR 着色器，实现了 **程序化点阵镂空（Dot Matrix Hatching）** 效果，支持 **法线贴图**、**金属度贴图**、**镜面反射贴图**、**粗糙度贴图**、**自发光**、**视差贴图** 和 **清漆（Clear Coat）** 效果。支持多种表面类型和面渲染模式，带有自定义材质编辑器。

---

## ✨ 特性

- **PBR 物理光照模型**：基于 URP 内置 `UniversalFragmentPBR`，支持主光源阴影、软阴影、级联阴影
- **附加光源支持**：完整的多光源前向渲染，支持附加光源阴影 (`_ADDITIONAL_LIGHTS` / `_ADDITIONAL_LIGHTS_SHADOWS`)
- **反射探针**：支持反射探针混合与盒投影 (`_REFLECTION_PROBE_BLENDING` / `_REFLECTION_PROBE_BOX_PROJECTION`)
- **光源层级**：兼容 URP 光源层级系统 (`_LIGHT_LAYERS`)
- **屏幕空间遮挡**：支持屏幕空间环境光遮蔽 (`_SCREEN_SPACE_OCCLUSION`)
- **双工作流支持**：
  - **金属度工作流**（默认）：金属度遮罩纹理 + 全局金属度系数，控制 F0 反射率
  - **镜面反射工作流**：镜面反射纹理 + 色调调节
- **法线贴图支持**：完整的 TBN 切线空间转换，可调节法线强度
- **粗糙度贴图**：支持粗糙度/平滑度遮罩纹理，与全局系数联动
- **自发光贴图**：支持 HDR 自发光色调，可驱动后处理 Bloom
- **视差贴图（Parallax Mapping）**：基于高度图的 UV 偏移采样，增加表面深度感
- **清漆效果（Clear Coat）**：支持清漆遮罩 + 强度 + 光滑度，模拟车漆/漆面多层反射
- **程序化点阵镂空**：通过数学计算在片元着色器中生成圆形点阵，实现半色调（halftone）镂空效果
- **多种表面类型**：
  - `Opaque` — 不透明
  - `TransparentCutout` — 透明裁切（点阵镂空）
  - `TransparentBlend` — 半透明混合
- **多种混合模式**（TransparentBlend 下可用）：
  - `Alpha` — 标准半透明
  - `Premultiplied` — 预乘半透明（玻璃效果）
  - `Additive` — 加法混合（提亮场景）
  - `Multiply` — 乘法混合（变暗场景）
- **面渲染模式**：
  - `FrontOnly` — 正面渲染（背面剔除）
  - `NoCulling` — 双面渲染，无法线翻转
  - `DoubleSided` — 双面渲染，自动翻转背面法线
- **Alpha 裁切**：可切换裁切阈值，镂空区域基于点阵密度动态计算
- **自定义材质检视面板**：下拉菜单控制 Surface Type / Blend Type / Face Rendering Mode，自动同步 Blend / ZWrite / Cull / Shader Keywords
- **SRP Batcher 兼容**：使用 `CBUFFER_START(UnityPerMaterial)` 包裹材质属性
- **DEBUG_DISPLAY 支持**：可配合 Unity 渲染调试器查看法线数据
- **多版本兼容**：支持 Unity 2021.3+ 和 2022+ 的 API 差异
- **Shader Variant 优化**：使用 `shader_feature_local` / `shader_feature_local_fragment` 按需编译变体，减少包体

---

## 🛠 环境要求

| 项目 | 版本 |
|------|------|
| Unity | **2023.2.20f1** 或更高 |
| URP | **16.0.6** |
| 渲染管线 | Universal Render Pipeline |

---

## 📁 项目结构

```
Assets/
├── Editor/
│   └── MyLitCustomInspector.cs    # 自定义材质编辑器
├── Material/
│   └── MyLitSphere.mat            # 示例材质
├── Scenes/
│   └── SampleScene.unity          # 示例场景
├── Script/
│   └── AdditionalLightShadowController.cs  # 附加光源阴影控制脚本
├── Settings/                      # URP 设置资源
│   ├── URP-Balanced.asset         # URP Balanced 管线配置
│   ├── URP-HighFidelity.asset     # URP High Fidelity 管线配置
│   ├── URP-Performant.asset       # URP Performant 管线配置
│   └── ...                        # 渲染器 & Volume 配置文件
├── Shader/
│   └── MyLit/
│       ├── MyLit.shader           # 主 Shader 文件（属性 + Pass 定义）
│       ├── MyLitCommon.hlsl       # 通用函数（点阵计算、Alpha 裁切）
│       ├── MyLitForwardLitPass.hlsl   # 前向光照通道（顶点 + 片元）
│       └── MyLitShadowCasterPass.hlsl # 阴影投射通道
└── Textures/
    ├── cat.png                    # 示例贴图
    ├── metal/                     # Metal063 4K PBR 贴图组
    │   ├── Metal063_4K-JPG_Color.jpg
    │   ├── Metal063_4K-JPG_NormalGL.jpg
    │   ├── Metal063_4K-JPG_Metalness.jpg
    │   ├── Metal063_4K-JPG_Roughness.jpg
    │   └── Metal063_4K-JPG_Displacement.jpg
    ├── red_brick/                 # 红砖 4K PBR 贴图组
    │   ├── red_brick_diff_4k.jpg
    │   ├── red_brick_nor_gl_4k.exr
    │   ├── red_brick_rough_4k.exr
    │   └── red_brick_disp_4k.png
    └── rusty_metal/               # 锈金属 4K PBR 贴图组
        ├── rusty_metal_05_diff_4k.jpg
        ├── rusty_metal_05_nor_gl_4k.exr
        ├── rusty_metal_05_rough_4k.exr
        └── rusty_metal_05_disp_4k.png
```

---

## 🔧 使用方法

1. **导入项目**：克隆仓库后用 Unity 2023.2+ 打开
2. **应用 Shader**：创建 Material → Shader 选择 `Custom/MyLit`
3. **配置材质**：
   - 在 Inspector 中设置 **Surface Type** 和 **Face Rendering Mode**
   - 选择 `TransparentCutout` 时会显示 **Alpha Cutout Threshold** 滑条
   - 选择 `TransparentBlend` 时会显示 **Blend Type** 下拉菜单
   - 切换 **Use specular workflow** 可在金属度 / 镜面反射工作流之间切换
   - 启用 **Use roughness texture** 可激活粗糙度贴图采样
   - 调整 **Dot Density**（点阵密度）和 **Dot Radius**（点半径）控制镂空效果
   - 调整 **Dot Scale X/Y** 可拉伸 UV 方向的点阵形状
4. **分配贴图**：
   - **Color** → 主纹理（反照率）
   - **Normal** → 法线贴图
   - **Metalness mask** → 金属度遮罩纹理
   - **Specular map** → 镜面反射纹理（仅 Specular 工作流）
   - **Smoothness mask** → 平滑度/粗糙度遮罩纹理
   - **Emission map** → 自发光纹理
   - **Height/displacement map** → 视差高度图
   - **Clear coat mask** → 清漆遮罩纹理
   - **Clear coat smoothness mask** → 清漆光滑度遮罩纹理
5. **调整参数**：
   - **Normal strength** — 控制法线凹凸程度
   - **Metalness** — 全局金属度系数
   - **Specular tint** — 镜面反射色调
   - **Smoothness** — 全局光滑度系数
   - **Emission tint** — HDR 自发光色调
   - **Parallax strength** — 视差偏移强度
   - **Clear coat strength** — 清漆强度
   - **Clear coat smoothness** — 清漆光滑度
6. **应用到物体**：将 Material 拖拽到场景中的 Mesh Renderer 上

---

## 🎨 参数说明

### 基础参数

| 参数 | 类型 | 说明 |
|------|------|------|
| `Color` | 2D 贴图 | 主纹理（RGB = 反照率, A = 透明度） |
| `Tint` | Color | 颜色 tint，与纹理颜色相乘 |

### 工作流切换

| 参数 | 类型 | 说明 |
|------|------|------|
| `Use specular workflow` | Toggle | 开启后使用镜面反射工作流，关闭使用金属度工作流 |
| `Use roughness texture` | Toggle | 开启后启用粗糙度贴图采样 |

### 法线 & 视差

| 参数 | 类型 | 说明 |
|------|------|------|
| `Normal` | 2D 贴图 | 法线贴图（OpenGL 格式），凹凸细节来源 |
| `Normal strength` | Range(0, 1) | 法线强度，控制凹凸程度 |
| `Height/displacement map` | 2D 贴图 | 视差高度图，用于 UV 偏移采样 |
| `Parallax strength` | Range(0, 1) | 视差偏移强度 |

### 金属度工作流

| 参数 | 类型 | 说明 |
|------|------|------|
| `Metalness mask` | 2D 贴图 | 金属度遮罩纹理（R 通道控制金属度） |
| `Metalness` | Range(0, 1) | 全局金属度系数，与遮罩纹理相乘 |

### 镜面反射工作流

| 参数 | 类型 | 说明 |
|------|------|------|
| `Specular map` | 2D 贴图 | 镜面反射纹理 |
| `Specular tint` | Color | 镜面反射色调 |

### 光滑度 & 粗糙度

| 参数 | 类型 | 说明 |
|------|------|------|
| `Smoothness mask` | 2D 贴图 | 平滑度/粗糙度遮罩纹理 |
| `Smoothness` | Range(0, 1) | 全局光滑度系数（Roughness 模式下：贴图白=粗糙，黑=光滑） |

### 自发光

| 参数 | 类型 | 说明 |
|------|------|------|
| `Emission map` | 2D 贴图 | 自发光纹理 |
| `Emission tint` | Color (HDR) | HDR 自发光色调，可驱动 Bloom 后处理 |

### 清漆效果

| 参数 | 类型 | 说明 |
|------|------|------|
| `Clear coat mask` | 2D 贴图 | 清漆遮罩纹理 |
| `Clear coat strength` | Range(0, 1) | 清漆强度，>0 时启用清漆效果 |
| `Clear coat smoothness mask` | 2D 贴图 | 清漆光滑度遮罩纹理 |
| `Clear coat smoothness` | Range(0, 1) | 清漆光滑度系数 |

### 点阵镂空

| 参数 | 类型 | 说明 |
|------|------|------|
| `Dot Density` | Float | 点阵密度，值越大点越密集 |
| `Dot Radius` | Range(0, 0.5) | 每个点的半径大小 |
| `Dot Scale X` | Range(0.1, 5) | X 方向点阵拉伸 |
| `Dot Scale Y` | Range(0.1, 5) | Y 方向点阵拉伸 |
| `Alpha cutout threshold` | Range(0, 1) | 透明度裁切阈值（仅在 Cutout 模式下显示） |

---

## 🔬 技术细节

### Shader Pass 架构

| Pass | LightMode | 作用 |
|------|-----------|------|
| `ForwardLit` | `UniversalForward` | 主前向光照通道，计算 PBR 光照 + 法线贴图 + 视差 + 清漆 + 点阵镂空 + Alpha 裁切 + 附加光源 + 反射探针 + 屏幕空间遮挡 |
| `ShadowCaster` | `ShadowCaster` | 阴影投射通道，支持带 Alpha 裁切的阴影生成 |

### Shader Variant 关键字

#### Shader Features（按需编译）

| 关键字 | 类型 | 说明 |
|--------|------|------|
| `_NORMALMAP` | `shader_feature_local_fragment` | 法线贴图，有法线贴图时启用 |
| `_SPECULAR_SETUP` | `shader_feature_local_fragment` | 镜面反射工作流切换 |
| `_ROUGHNESS_SETUP` | `shader_feature_local_fragment` | 粗糙度贴图模式 |
| `_CLEARCOATMAP` | `shader_feature_local` | 清漆效果，强度 >0 时启用 |
| `_ALPHA_CUTOUT` | `shader_feature_local` | Alpha 裁切（Cutout 模式） |
| `_DOUBLE_SIDED_NORMALS` | `shader_feature_local` | 双面法线翻转 |
| `_ALPHAPREMULTIPLY_ON` | `shader_feature_local_fragment` | 预乘 Alpha 混合（玻璃效果） |

#### Multi Compile（URP 全局关键字）

| 关键字 | 类型 | 说明 |
|--------|------|------|
| `_MAIN_LIGHT_SHADOWS` | `multi_compile` | 主光源阴影 |
| `_MAIN_LIGHT_SHADOWS_CASCADE` | `multi_compile` | 级联阴影 |
| `_SHADOWS_SOFT` | `multi_compile_fragment` | 软阴影 |
| `_ADDITIONAL_LIGHTS` | `multi_compile` | 附加光源 |
| `_ADDITIONAL_LIGHTS_SHADOWS` | `multi_compile_fragment` | 附加光源阴影 |
| `_REFLECTION_PROBE_BLENDING` | `multi_compile_fragment` | 反射探针混合 |
| `_REFLECTION_PROBE_BOX_PROJECTION` | `multi_compile_fragment` | 反射探针盒投影 |
| `_LIGHT_LAYERS` | `multi_compile_fragment` | 光源层级 |
| `_SCREEN_SPACE_OCCLUSION` | `multi_compile_fragment` | 屏幕空间环境光遮蔽 |

### 程序化点阵镂空算法

点阵镂空在片元着色器中通过 `CalculateDotMatrix()` 函数实现：

```hlsl
// UV 坐标版
float CalculateDotMatrix(float2 uv, float density, float radius, float2 scale) {
    float2 scaledUV = uv * scale;
    float2 localPos = frac(scaledUV * density) - 0.5;  // 将 UV 划分为网格单元
    float dist = length(localPos);                      // 计算到单元中心的距离
    return step(dist, radius);                          // 距离小于半径 = 显示，否则丢弃
}
```

该函数的返回值直接覆盖纹理的 alpha 通道，随后由 `clip()` 进行硬裁切。

### 视差贴图（Parallax Mapping）

视差效果通过 URP 内置 `ParallaxMapping.hlsl` 实现，在片元着色器中对 UV 进行视角相关的偏移采样。该效果**始终**执行，不依赖 `_NORMALMAP` 关键字，可独立于法线贴图启用：

```hlsl
// 切线空间视角方向（tangentWS 始终可用）
float3 viewDirTS = GetViewDirectionTangentSpace(input.tangentWS, normalWS, viewDirWS);
// UV 偏移采样（始终执行）
uv += ParallaxMapping(TEXTURE2D_ARGS(_ParallaxMap, sampler_ParallaxMap), viewDirTS, _ParallaxStrength, uv);
```

### 法线贴图管线

法线贴图采用完整的 TBN 切线空间转换流程。切线数据**始终**通过 `Interpolators` 传递，不依赖 `_NORMALMAP` 关键字：

1. **顶点阶段**：从 `Attributes` 读取 `tangentOS`，通过 `GetVertexNormalInputs` 获取世界空间切线，**无条件**传递给 `Interpolators`
2. **片元阶段**：用 `CreateTangentToWorld()` 构建切线→世界矩阵（在 `_NORMALMAP` 守卫外计算，保证调试器兼容）
3. **采样与解码**（`_NORMALMAP` 启用时）：`UnpackNormalScale()` 解压法线贴图并应用强度系数
4. **空间转换**（`_NORMALMAP` 启用时）：`TransformTangentToWorld()` 将切线空间法线转换到世界空间参与光照
5. **兜底**（`_NORMALMAP` 未启用时）：`normalTS` 默认为 `(0, 0, 1)`，`normalWS` 保持原始世界法线

```hlsl
// 顶点输出（无条件）
output.tangentWS = float4(normInput.tangentWS, input.tangentOS.w);

// 片元转换（守卫外计算，始终可用）
float3x3 tangentToWorld = CreateTangentToWorld(normalWS, input.tangentWS.xyz, input.tangentWS.w);

#ifdef _NORMALMAP
float3 normalTS = UnpackNormalScale(SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, uv), _NormalStrength);
normalWS = normalize(TransformTangentToWorld(normalTS, tangentToWorld));
#else
float3 normalTS = float3(0, 0, 1);
normalWS = normalize(normalWS);
#endif
```

### 自定义 Inspector 关键字联动

| Surface Type | Render Queue | Blend | ZWrite | Alpha Cutout Keyword |
|-------------|-------------|-------|--------|---------------------|
| Opaque | Geometry | One / Zero | On | ❌ |
| TransparentCutout | AlphaTest | One / Zero | On | ✅ |
| TransparentBlend | Transparent | 见下方混合模式表 | Off | ❌ |

| Blend Type | Source Blend | Dest Blend | Premultiply Keyword |
|-----------|-------------|-----------|---------------------|
| Alpha | SrcAlpha | OneMinusSrcAlpha | ❌ |
| Premultiplied | One | OneMinusSrcAlpha | ✅ |
| Additive | SrcAlpha | One | ❌ |
| Multiply | Zero | SrcColor | ❌ |

| Face Rendering Mode | Cull Mode | Double-Sided Normals Keyword |
|--------------------|-----------|------------------------------|
| FrontOnly | Back | ❌ |
| NoCulling | Off | ❌ |
| DoubleSided | Off | ✅ |

### 附加光源阴影控制器

`Assets/Script/AdditionalLightShadowController.cs` 是一个辅助脚本，用于在编辑器中快速配置附加光源的阴影设置：

```csharp
public class AdditionalLightShadowController : MonoBehaviour
{
    public bool castShadows = true;           // 是否投射阴影
    public LightShadows shadowType = LightShadows.Soft; // 阴影类型
}
```

- 挂载到带有 `Light` 组件的 GameObject 上
- 在 Inspector 中修改数值时通过 `OnValidate()` 实时应用
- 支持 `Soft` / `Hard` / `None` 三种阴影类型

---

## 🔄 Changelog

### — 附加光源 / 反射探针 / 光源层级 / 屏幕空间遮挡 + 阴影控制脚本

**新增功能：**
- 添加 **附加光源支持**：`_ADDITIONAL_LIGHTS` + `_ADDITIONAL_LIGHTS_SHADOWS` 多编译变体，完整支持 URP 多光源前向渲染
- 添加 **反射探针混合与盒投影**：`_REFLECTION_PROBE_BLENDING` + `_REFLECTION_PROBE_BOX_PROJECTION`
- 添加 **光源层级**支持：`_LIGHT_LAYERS`，兼容 URP 光源层级系统
- 添加 **屏幕空间环境光遮蔽**：`_SCREEN_SPACE_OCCLUSION`
- 新增 `AdditionalLightShadowController.cs` 脚本：辅助在编辑器中配置附加光源阴影（类型开关 + Soft/Hard/None）

**影响：**
- Shader 现在完整支持 URP 高级光照特性，可在复杂多光源场景中使用
- 附加光源可正确投射阴影，与主光源阴影系统协同工作

---

### — 法线 & 视差管线解耦 + 架构简化

**架构变更：**
- 移除 `tangentWS` 的 `_NORMALMAP` 条件编译守卫 — 切线数据现在**始终**通过 `Interpolators` 传递，不再依赖法线贴图关键字
- 移除视差贴图（Parallax Mapping）的 `_NORMALMAP` 条件编译守卫 — UV 偏移采样现在**始终**执行，确保高度图效果独立于法线贴图开关
- 移除顶点函数中 `output.tangentWS` 的 `_NORMALMAP` 守卫，切线数据在顶点阶段无条件计算
- 法线贴图采样仍由 `_NORMALMAP` 关键字控制，未分配法线贴图时 `normalTS` 回退为默认平面法线 `(0,0,1)`
- `tangentToWorld` 矩阵在 `_NORMALMAP` 守卫外始终计算，保证渲染调试器 "Lighting Without Normal Maps" 模式正常工作

**影响：**
- 视差效果不再依赖法线贴图分配，可单独启用
- 减少 shader variant 分支，简化关键字管理
- 切线数据始终可用，为后续扩展（如各向异性、细节法线）提供基础

---

### — 清漆 / 自发光 / 视差 / 粗糙度贴图 / 混合模式升级

**新增功能：**
- 添加 **清漆效果**（Clear Coat）：清漆遮罩 + 强度 + 光滑度遮罩 + 光滑度系数
- 添加 **自发光贴图**（Emission Map）+ HDR 自发光色调
- 添加 **视差贴图**（Parallax Mapping）：高度图 + 偏移强度，基于 URP 内置 `ParallaxMapping.hlsl`
- 添加 **粗糙度贴图**（Roughness Texture）支持，通过 `Use roughness texture` 切换
- 添加 **双工作流切换**：金属度工作流 ↔ 镜面反射工作流
- 添加 **多种混合模式**：Alpha / Premultiplied / Additive / Multiply
- 添加 `_ALPHAPREMULTIPLY_ON` 关键字支持预乘 Alpha 玻璃效果
- Shader 关键字从 `#define` 全面升级为 `shader_feature_local` / `shader_feature_local_fragment`，按需编译变体
- 自定义 Inspector 新增 Blend Type 下拉菜单，自动管理 `_NORMALMAP` / `_CLEARCOATMAP` / `_ALPHAPREMULTIPLY_ON` 关键字
- 法线贴图关键字改为根据是否分配纹理自动启用/禁用

---

### — 金属度 / 镜面反射贴图 + Bug 修复

**Bug 修复：**
- 修复 `#pragma _NORMALMAP` 语法错误，改为 `#define _NORMALMAP`

**新增功能：**
- 添加金属度遮罩贴图 (`_MetalnessMask`) 和全局金属度系数 (`_Metalness`)
- 添加镜面反射贴图 (`_SpecularMap`) 和镜面反射色调 (`_SpecularTint`)
- 新增 Metal063 和 rusty_metal_05 两套 4K PBR 贴图组
- 贴图集重组为 `metal/`、`red_brick/`、`rusty_metal/` 子目录

---

### — PBR + 法线贴图升级

**Shader 改动：**
- 光照模型从 `UniversalFragmentBlinnPhong` 切换为 `UniversalFragmentPBR`
- 新增法线贴图属性 `_NormalMap` 和强度控制 `_NormalStrength`
- 添加切线数据流（`tangentOS` → `tangentWS`）和 TBN 矩阵转换
- 使用 `UnpackNormalScale` 支持可调节的法线强度
- 添加 `DEBUG_DISPLAY` 调试钩子（`surfaceInput.normalTS`）
- `_Smoothness` 改为 Range(0,1)，默认值 0.5
- 新增 4K PBR 红砖测试贴图（漫反射、法线、粗糙度、位移）

---

## 📄 License

本项目仅供学习参考，欢迎自由使用和修改。
