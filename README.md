# Unity URP Shader — MyLit

一个基于 Unity URP 的自定义 PBR 着色器，实现了 **程序化点阵镂空（Dot Matrix Hatching）** 效果，支持 **法线贴图**、**金属度贴图** 和 **镜面反射贴图**。支持多种表面类型和面渲染模式，带有自定义材质编辑器。

---

## ✨ 特性

- **PBR 物理光照模型**：基于 URP 内置 `UniversalFragmentPBR`，支持主光源阴影、软阴影、级联阴影
- **法线贴图支持**：完整的 TBN 切线空间转换，可调节法线强度
- **金属度贴图**：支持金属度遮罩纹理 + 全局金属度系数，控制 F0 反射率
- **镜面反射贴图**：支持镜面反射纹理 + 色调调节
- **程序化点阵镂空**：通过数学计算在片元着色器中生成圆形点阵，实现半色调（halftone）镂空效果
- **多种表面类型**：
  - `Opaque` — 不透明
  - `TransparentCutout` — 透明裁切（点阵镂空）
  - `TransparentBlend` — 半透明混合
- **面渲染模式**：
  - `FrontOnly` — 正面渲染（背面剔除）
  - `NoCulling` — 双面渲染，无法线翻转
  - `DoubleSided` — 双面渲染，自动翻转背面法线
- **Alpha 裁切**：可切换裁切阈值，镂空区域基于点阵密度动态计算
- **自定义材质检视面板**：下拉菜单控制 Surface Type 和 Face Rendering Mode，自动同步 Blend / ZWrite / Cull / Shader Keywords
- **SRP Batcher 兼容**：使用 `CBUFFER_START(UnityPerMaterial)` 包裹材质属性
- **DEBUG_DISPLAY 支持**：可配合 Unity 渲染调试器查看法线数据
- **多版本兼容**：支持 Unity 2021.3+ 和 2022+ 的 API 差异

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
├── Script/                        # （预留脚本目录）
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
   - 调整 **Dot Density**（点阵密度）和 **Dot Radius**（点半径）控制镂空效果
   - 调整 **Dot Scale X/Y** 可拉伸 UV 方向的点阵形状
4. **分配贴图**：
   - **Color** → 主纹理（反照率）
   - **Normal** → 法线贴图
   - **Metalness mask** → 金属度遮罩纹理
   - **Specular map** → 镜面反射纹理
5. **调整参数**：
   - **Normal strength** — 控制法线凹凸程度
   - **Metalness** — 全局金属度系数
   - **Specular tint** — 镜面反射色调
6. **应用到物体**：将 Material 拖拽到场景中的 Mesh Renderer 上

---

## 🎨 参数说明

| 参数 | 类型 | 说明 |
|------|------|------|
| `Color` | 2D 贴图 | 主纹理（RGB = 反照率, A = 透明度） |
| `Tint` | Color | 颜色 tint，与纹理颜色相乘 |
| `Normal` | 2D 贴图 | 法线贴图（OpenGL 格式），凹凸细节来源 |
| `Normal strength` | Range(0, 1) | 法线强度，控制凹凸程度 |
| `Metalness mask` | 2D 贴图 | 金属度遮罩纹理（R 通道控制金属度） |
| `Metalness` | Range(0, 1) | 全局金属度系数，与遮罩纹理相乘 |
| `Specular map` | 2D 贴图 | 镜面反射纹理 |
| `Specular tint` | Color | 镜面反射色调 |
| `Smoothness` | Range(0, 1) | 光滑度（影响高光锐利度） |
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
| `ForwardLit` | `UniversalForward` | 主前向光照通道，计算 PBR 光照 + 法线贴图 + 点阵镂空 + Alpha 裁切 |
| `ShadowCaster` | `ShadowCaster` | 阴影投射通道，支持带 Alpha 裁切的阴影生成 |

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

### 法线贴图管线

法线贴图采用完整的 TBN 切线空间转换流程：

1. **顶点阶段**：从 `Attributes` 读取 `tangentOS`，通过 `GetVertexNormalInputs` 获取世界空间切线，传递给 `Interpolators`
2. **片元阶段**：用 `CreateTangentToWorld()` 构建切线→世界矩阵
3. **采样与解码**：`UnpackNormalScale()` 解压法线贴图并应用强度系数
4. **空间转换**：`TransformTangentToWorld()` 将切线空间法线转换到世界空间参与光照

```hlsl
// 顶点输出
output.tangentWS = float4(normInput.tangentWS, input.tangentOS.w);

// 片元转换
float3x3 tangentToWorld = CreateTangentToWorld(normalWS, input.tangentWS.xyz, input.tangentWS.w);
float3 normalTS = UnpackNormalScale(SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, uv), _NormalStrength);
normalWS = normalize(TransformTangentToWorld(normalTS, tangentToWorld));
```

### 自定义 Inspector 关键字联动

| Surface Type | Render Queue | Blend | ZWrite | Alpha Cutout Keyword |
|-------------|-------------|-------|--------|---------------------|
| Opaque | Geometry | One / Zero | On | ❌ |
| TransparentCutout | AlphaTest | One / Zero | On | ✅ |
| TransparentBlend | Transparent | SrcAlpha / OneMinusSrcAlpha | Off | ❌ |

| Face Rendering Mode | Cull Mode | Double-Sided Normals Keyword |
|--------------------|-----------|------------------------------|
| FrontOnly | Back | ❌ |
| NoCulling | Off | ❌ |
| DoubleSided | Off | ✅ |

---

## 🔄 Changelog

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
