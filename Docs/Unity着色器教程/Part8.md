# Part 8 · 顶点动画

> **本节在整份教程中的位置**
> 前面七节都在片元阶段工作：改颜色、改法线、改光照。本节回到**顶点阶段**——在顶点函数里移动顶点，让网格自己动起来。
>
> 用标签区分：
>
> - 🟩 **【Shader】** — 顶点函数里的位移与法线重算。
> - 🟦 **【场景/C#】** — 风场控制器、材质参数、模型顶点色。
> - 🟪 **【原理】** — 波形数学与 VAT 等进阶技术。
>
> **版本基准：Unity 2023.2.20f1 / URP 16.0.6。**
> 涉及的项目文件：`MyLitForwardLitPass.hlsl`、`MyLitShadowCasterPass.hlsl`、`MyLitDepthOnlyPass.hlsl`、`MyLitDepthNormalsPass.hlsl`。
>
> ⚠️ 本节有一整节讲"**多 Pass 同步**"——这是旧版教程完全没提、但项目里一定会踩的坑。

---

## 0. 这一节到底要解决什么问题

**问题**：旗帜、草、水面、果冻、呼吸感……这些效果的本质是"网格形状随时间变化"。有两条路：

| 方案 | 谁算 | 代价 |
|---|---|---|
| 骨骼动画 / Blend Shape | CPU（或 GPU 蒙皮） | 需要美术绑定，数据量随动画长度增长 |
| **顶点动画（Shader）** | GPU 顶点函数 | 零美术资源，但只是数学函数，表达力有限 |

**一句话概括本节**：
> 顶点动画很便宜也很简单：**改 `positionOS` → 重算法线 → 在所有 Pass 里做同样的事**。难的全在第三句。

---

## 1. 🟩 数据流：改在哪、什么时候改

### 1.1 唯一正确的插入点

```hlsl
Interpolators Vertex(Attributes input)
{
    Interpolators output;

    // ① 在这里改对象空间位置
    float3 positionOS = input.positionOS;
    positionOS = ApplyAnimation(positionOS, input.normalOS, input.uv, _Time.y);

    // ② 之后再做所有空间变换 —— 顺序不能反
    VertexPositionInputs posnInputs = GetVertexPositionInputs(positionOS);
    VertexNormalInputs  normInput   = GetVertexNormalInputs(animatedNormalOS, input.tangentOS);

    output.positionCS = posnInputs.positionCS;
    output.positionWS = posnInputs.positionWS;
    output.normalWS   = normInput.normalWS;
    ...
}
```

为什么必须在**对象空间**改？

- `GetVertexPositionInputs` 内部用 `UNITY_MATRIX_M` 做 OS→WS。改 OS，后续 WS / VS / CS 全部自动跟随；
- 如果你在 WS 里改，就要自己转回 OS 再变换，绕一圈且容易出错；
- 更重要的是：**光照、GI、阴影全都依赖 `positionWS`**。在 OS 改 → `posnInputs.positionWS` 自动是动画后的位置 → 一切正确。

### 1.2 法线必须重算

`GetVertexNormalInputs` 只做**空间变换**（OS→WS），**不会**根据你的位移重新计算朝向。

```hlsl
// ❌ 错：位置动了，法线还是原网格的
positionOS.y += sin(positionOS.x * 2 + time) * 0.1;
normalWS = GetVertexNormalInputs(input.normalOS).normalWS;   // 没变！

// ✅ 对：解析求导
float k = 2.0;                                   // 波数
float dWave_dx = cos(positionOS.x * k + time) * 0.1 * k;
float3 normalOS = normalize(float3(-dWave_dx, 1.0, 0.0));
```

不用解析导数时，**有限差分**是通用做法（对任意位移函数都有效）：

```hlsl
// 在切平面上取两个邻近点，用叉积得到新法线
float3 ApplyDisplacement(float3 p, float2 uv);   // 你的位移函数

float eps = 0.01;
float3 p0 = ApplyDisplacement(positionOS, uv);
float3 p1 = ApplyDisplacement(positionOS + tangentOS * eps, uv);
float3 p2 = ApplyDisplacement(positionOS + bitangentOS * eps, uv);
float3 newNormalOS = normalize(cross(p1 - p0, p2 - p0));
```

代价是位移函数要算三遍。解析导数更快，但只能用于"你写得出的函数"。

---

## 2. 🟩 波形动画

### 2.1 正弦波

```hlsl
float3 SineWave(float3 positionOS, float time)
{
    float wave1 = sin(positionOS.x * 2.0 + time) * 0.10;
    float wave2 = sin(positionOS.z * 1.5 + time * 0.8) * 0.05;
    positionOS.y += wave1 + wave2;
    return positionOS;
}
```

特点：顶点只在 Y 轴上下移动，**波峰波谷对称**，看起来比较"假"。

### 2.2 Gerstner 波：让波峰变尖

真实的水波，顶点做的是**圆周运动**：波峰处顶点挤在一起（变尖），波谷处拉开（变平）。Gerstner 波在水平方向也做位移，就能得到这个效果。

```hlsl
// 单个 Gerstner 波；同时累加切线、副切线，用于求法线
void GerstnerWave(
    inout float3 positionOS,
    inout float3 tangent,      // 累加
    inout float3 binormal,     // 累加
    float2 direction, float steepness, float wavelength,
    float time, float speed)
{
    float k = 2.0 * PI / wavelength;      // 波数
    float c = sqrt(9.8 / k);              // 相速度（重力波）
    float2 d = normalize(direction);
    float f = k * (dot(d, positionOS.xz) - c * time * speed * 0.1);
    float a = steepness / k;              // 振幅：由陡峭度推出

    positionOS.x += d.x * a * cos(f);
    positionOS.y += a * sin(f);
    positionOS.z += d.y * a * cos(f);

    tangent  += float3(-d.x * d.x * steepness * sin(f),
                        d.x * steepness * cos(f),
                       -d.x * d.y * steepness * sin(f));
    binormal += float3(-d.x * d.y * steepness * sin(f),
                        d.y * steepness * cos(f),
                       -d.y * d.y * steepness * sin(f));
}

// 用法
float3 tangent  = float3(1, 0, 0);
float3 binormal = float3(0, 0, 1);
GerstnerWave(positionOS, tangent, binormal, float2(1, 0), 0.25, 10.0, time, 1.0);
GerstnerWave(positionOS, tangent, binormal, float2(0.7, 0.3), 0.25, 6.0, time, 1.3);
GerstnerWave(positionOS, tangent, binormal, float2(-0.3, 0.9), 0.20, 3.0, time, 1.7);

float3 normalOS = normalize(cross(binormal, tangent));
```

参数含义：

| 参数 | 作用 | 建议 |
|---|---|---|
| `steepness` | 波峰尖锐程度 | 0~1；多个波的 steepness 之和 > 1 会自交（出现翻转的"打结"） |
| `wavelength` | 波长 | 大波 10~60，细节波 1~5 |
| `speed` | 相速度倍率 | 0.5~2 |

> ⚠️ **旧版代码的 Q 公式** `Q = steepness / (frequency * amplitude + 0.0001)` 与这里"用 `a = steepness / k` 直接把陡峭度折算成振幅"的写法等价性存疑，直接抄容易出现波峰自交。**用上面这种累加切线/副切线的版本更稳**（它天然保证法线与位置一致）。

### 2.3 时间参数

`_Time` 是 URP 自动提供的全局 `float4`：

- `_Time.y` = 游戏内已运行秒数（受 `Time.timeScale` 影响）
- `_Time.w` = `0.5 * (sin + cos)` 之类，很少用

需要暂停时动画也继续 → 自己在 C# 里传一个 `unscaledTime`：

```csharp
Shader.SetGlobalFloat("_UnscaledTime", Time.unscaledTime);
```

---

## 3. 🟩➕🟦 风动系统

### 3.1 权重从哪来

让"草根不动、草尖狂摆"需要一个权重。常用两个来源：

| 来源 | 做法 | 优点 |
|---|---|---|
| **顶点色 R 通道** | 建模时在软件里刷：根黑、尖红 | 美术可控性最高 |
| **高度** | `saturate(positionOS.y / _ObjectHeight)` 再 `pow` | 零美术成本 |

```hlsl
float GetWindWeight(float4 vertexColor, float3 positionOS)
{
    float w = vertexColor.r;
    if (w < 0.001)                                  // 没有顶点色时用高度兜底
        w = pow(saturate(positionOS.y / _ObjectHeight), 2.0);
    return w;
}
```

顶点色需要在 `Attributes` 里声明：`float4 color : COLOR;`

### 3.2 三层叠加

```hlsl
// ① 主干摆动：低频、大幅
float phase = dot(positionWS.xz, windDir) * _Turbulence;
float sway = sin(time * _WindSpeed * 0.5 + phase);
sway += sin(time * _WindSpeed * 0.31 + phase * 1.3) * 0.5;   // 非整数倍频率 → 不循环
offset = float3(windDir.x, 0, windDir.y) * (sway / 1.5) * weight * 0.3;

// ② 细节抖动：高频、小幅
offset += float3(windDir.x, 0, windDir.y) * sin(time * 6.0 + phase * 2.0) * weight * 0.05;

// ③ 阵风：用一个慢周期包络整体缩放
float gust = 0.6 + 0.4 * sin(time * 0.23);
offset *= gust;
```

> 💡 频率取**非整数倍**（0.5 与 0.31、1.3 这些）能让多个正弦永不重合，避免出现明显的循环周期。

### 3.3 🟦 C# 全局风场

风对所有植被一致 → 用**全局属性**传，避免每个材质各设一遍：

```csharp
public class WindController : MonoBehaviour
{
    public Vector3 windDirection = new Vector3(1, 0, 0);
    [Range(0, 10)] public float windSpeed = 3f;
    [Range(0, 2)]  public float windStrength = 0.5f;

    private void Update()
    {
        Vector3 d = windDirection.normalized * windStrength;
        Shader.SetGlobalVector("_WindData", new Vector4(d.x, d.y, d.z, windStrength));
        Shader.SetGlobalFloat("_WindSpeed", windSpeed);
    }
}
```

Shader 侧直接声明同名变量即可（**不要**放进 `UnityPerMaterial` CBUFFER，那是每材质的数据）：

```hlsl
float4 _WindData;   // xyz = 方向*强度, w = 强度
float  _WindSpeed;
```

### 3.4 参数参考

| 植被 | 振幅 | 频率 | 刚度 |
|---|---|---|---|
| 草 | 0.10~0.30 | 2~5 | 0.1~0.3 |
| 灌木 | 0.05~0.15 | 1~2 | 0.3~0.5 |
| 树干 | 0.02~0.05 | 0.3~0.8 | 0.8 |
| 树叶 | 0.10~0.20 | 2~4 | 0.2 |

---

### 3.5 完整实现代码

以下是项目中的完整实现代码（`MyLitAnimation.hlsl`），包含权重计算、风偏移、法线修正：

```hlsl
#ifndef MY_LIT_ANIMATION_INCLUDED
#define MY_LIT_ANIMATION_INCLUDED

// Part 8：顶点动画公共文件。
// 关键点：所有 Pass（ForwardLit / ShadowCaster / DepthOnly / DepthNormals）都 include 它，
// 保证影子、深度、SSAO 法线与画面里的模型动得一模一样。

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

// 全局风场参数，由 Assets/Scripts/WindController.cs 通过 Shader.SetGlobal* 设置
// 注意：全局属性不能放进 UnityPerMaterial（那是每材质的数据）
float4 _WindData;        // xyz = 方向 * 强度, w = 整体强度
float  _WindSpeed;
float  _WindTurbulence;  // 湍流：让相邻位置产生相位差
float  _WindHeight;      // 没有顶点色时的兜底高度

// 权重：优先用顶点色 R 通道（美术刷的），没有则用高度
float MyLitWindWeight(float4 vertexColor, float3 positionOS)
{
    float weight = vertexColor.r;
    if (weight < 0.001)
        weight = pow(saturate(positionOS.y / max(_WindHeight, 0.001)), 2.0);
    return weight;
}

// 单个顶点的风偏移量（世界空间）
float3 MyLitWindOffset(float3 positionWS, float weight, float time)
{
    // 加一点极小值，避免 _WindData.xz 为 0 时 normalize 出 NaN
    float2 windDir = normalize(_WindData.xz + float2(1e-4, 1e-4));

    // 相位里带上世界位置：让一片草随风形成"波浪"，而不是整体同步平移
    float phase = dot(positionWS.xz, windDir) * _WindTurbulence;

    // ① 主干摆动：低频、大幅。两个非整数倍频率叠加，避免出现明显循环
    float sway  = sin(time * _WindSpeed * 0.5 + phase);
    sway       += sin(time * _WindSpeed * 0.31 + phase * 1.3) * 0.5;
    sway       /= 1.5;

    float3 offset = float3(windDir.x, 0, windDir.y) * sway * weight;

    // ② 细节抖动：高频、小幅
    offset.y += sin(time * _WindSpeed * 2.0 + phase) * weight * 0.05;

    return offset * _WindData.w;
}

// 只改位置（DepthOnly 这类不需要法线的 Pass 用这个）
float3 MyLitApplyWind(float3 positionOS, float4 vertexColor, float time)
{
    float weight = MyLitWindWeight(vertexColor, positionOS);

    // 风的相位要用世界坐标算，所以先转到世界空间再转回来
    float3 positionWS = TransformObjectToWorld(positionOS);
    positionWS += MyLitWindOffset(positionWS, weight, time);
    return TransformWorldToObject(positionWS);
}

// 同时修正法线：位移改变了表面朝向，不重算光照就会"不跟着动"
void MyLitApplyWindWithNormal(inout float3 positionOS, inout float3 normalOS,
                              float4 vertexColor, float time)
{
    // 以原法线构造一组正交基
    float3 up = abs(normalOS.y) < 0.99 ? float3(0, 1, 0) : float3(1, 0, 0);
    float3 tangent   = normalize(cross(normalOS, up));
    float3 bitangent = cross(normalOS, tangent);   // 保证 cross(tangent, bitangent) = normalOS

    const float eps = 0.02;   // 对象空间步长，太大法线会糊，太小会抖

    float3 p0 = MyLitApplyWind(positionOS, vertexColor, time);
    float3 p1 = MyLitApplyWind(positionOS + tangent   * eps, vertexColor, time);
    float3 p2 = MyLitApplyWind(positionOS + bitangent * eps, vertexColor, time);

    positionOS = p0;
    normalOS   = normalize(cross(p1 - p0, p2 - p0));
}

#endif
```

---

## 4. 🟩 纹理驱动的位移

### 4.1 顶点阶段采样纹理

```hlsl
// ⚠️ 必须用 _LOD 并显式指定 mip = 0
//    顶点阶段没有 ddx/ddy，硬件算不出 mip 等级
float h = SAMPLE_TEXTURE2D_LOD(_DisplacementMap, sampler_DisplacementMap, uv, 0).r;
positionOS += normalOS * (h * 2.0 - 1.0) * _DisplacementStrength;
```

限制：

- 顶点纹理采样在部分老 GLES2 设备上不支持（URP 16 只面向 GLES3+，一般没问题）；
- **网格必须有足够多的顶点**。位移贴图是逐顶点的，一个 12 顶点的立方体位移不出细节。

### 4.2 Flow Map（流向图）

用于水流、熔岩：一张纹理存流动方向（RG），两张相位错位混合消除"整体平移感"：

```hlsl
float2 flowDir = SAMPLE_TEXTURE2D_LOD(_FlowMap, sampler_FlowMap, uv, 0).rg * 2.0 - 1.0;
float phase = frac(time * _FlowSpeed);

float s1 = SAMPLE_TEXTURE2D_LOD(_FlowTex, sampler_FlowTex, uv + flowDir * phase, 0).r;
float s2 = SAMPLE_TEXTURE2D_LOD(_FlowTex, sampler_FlowTex, uv + flowDir * (phase - 1.0), 0).r;

// 交叉淡入淡出：phase 走完一圈时权重回到 0，无缝循环
float blend = abs(phase * 2.0 - 1.0);
float h = lerp(s1, s2, blend);
```

### 4.3 VAT（顶点动画纹理）🟪

把**每一帧每个顶点的位置**烘到一张纹理里：宽度 = 顶点数，高度 = 帧数。运行时按时间采样，就能播放任意复杂的预计算动画（碎裂、布料、流体）。

```hlsl
// 编码：pos = texel.rgb * boundsSize + boundsMin
float3 SampleVAT(float vertexId, float frame)
{
    float2 uv = float2((vertexId + 0.5) / _VATWidth, (frame + 0.5) / _VATHeight);
    float3 encoded = SAMPLE_TEXTURE2D_LOD(_VATPositionMap, sampler_VATPositionMap, uv, 0).rgb;
    return encoded * _VATBoundsSize.xyz + _VATBoundsMin.xyz;
}
```

要点：

- 纹理必须是**未压缩、无 sRGB、Point 滤波**的高精度格式（`RGBAHalf` 或 `RGBAFloat`）；
- 顶点 ID 通常烘进 UV 的某个通道（例如 `uv2.x = vertexIndex / width`）；
- 适合"大量同款物体播同一段动画"（配合 GPU Instancing 极佳）。

---

## 5. ⚠️ 关键坑：所有 Pass 必须同步

这是本节最重要的一节。

### 5.1 现象

你在 ForwardLit 里做了顶点动画，画面上旗帜在飘，但：

- **影子是静止的**（ShadowCaster Pass 没做动画）；
- **SSAO 的接触阴影错位**（DepthNormals Pass 没做动画）；
- 开了深度预处理时，**物体自己遮住自己**（DepthOnly Pass 没做动画）；
- 运动模糊**方向不对**（MotionVectors Pass 没算上顶点位移）。

### 5.2 原因

每个 Pass 都是**独立的一段 HLSL**。你在 ForwardLit 里写的动画函数，对其他 Pass 完全不可见。

### 5.3 怎么做

把动画函数抽到公共文件里，所有 Pass 都 include 并调用：

```hlsl
// MyLitCommon.hlsl
float3 ApplyWind(float3 positionOS, float3 normalOS, float4 vertexColor, float time);
```

| Pass | 文件 | 是否要同步 |
|---|---|---|
| ForwardLit | `MyLitForwardLitPass.hlsl` | ✅ |
| ShadowCaster | `MyLitShadowCasterPass.hlsl` | ✅（否则影子不动） |
| DepthOnly | `MyLitDepthOnlyPass.hlsl` | ✅（否则深度预处理出错） |
| DepthNormals | `MyLitDepthNormalsPass.hlsl` | ✅（否则 SSAO 错位） |
| MotionVectors | （Part 5 §6.3） | ✅ 且 `positionOld` 也要算上一帧的动画 |
| Meta（烘焙） | `MyLitMetaPass.hlsl` | ❌ 烘焙用静态形状 |

> 💡 实践建议：把动画抽成 `MyLitAnimation.hlsl`，用**同一个关键字**（如 `_WIND_ENABLED`）在所有 Pass 里守卫，保证改一处、处处同步。

### 5.4 包围盒剔除

顶点动画发生在 GPU 上，CPU 端的 `Mesh.bounds` 还是原始大小。位移较大时，物体**还没真正出画就被剔除**了（画面上会突然消失）。

解决：

```csharp
// C#：把包围盒放大一点
var mesh = GetComponent<MeshFilter>().mesh;
mesh.bounds = new Bounds(center, size * 1.5f);
```

或者直接在建模时把模型做大一圈。

---

## 6. 调试

```hlsl
// 可视化位移量
float d = length(animatedPosOS - input.positionOS);
return half4(d.xxx * 10.0, 1);

// 可视化权重（顶点色 R）
return half4(input.color.rrr, 1);

// 可视化法线（仅调试输出用 0.5+0.5）
return half4(normalWS * 0.5 + 0.5, 1);
```

排查顺序：

1. **先关掉所有动画**，确认基础渲染正常；
2. **只开一层**（例如只留主干摆动），确认方向与幅度；
3. **再叠细节**；
4. 最后检查**其他 Pass 有没有同步**（把相机转到能看到影子的角度）。

---

## 7. 性能

| 项 | 说明 |
|---|---|
| **顶点数量** | 顶点动画的成本与顶点数成正比。远景用 LOD 降面 |
| **纹理采样** | 顶点阶段每次采样都要显式 mip，且比片元采样更容易成为瓶颈。尽量用顶点色/数学函数代替 |
| **除法与三角函数** | 风动里 `sin/cos` 用到 6~8 次是常态，可接受；`acos/asin` 尽量避免 |
| **分支** | 开关用关键字 `#pragma multi_compile _ _WIND_ENABLED`，别用 `if (_Enable)` |
| **Pass 数量** | 每同步一个 Pass，就多一遍顶点计算。草这类大量物体要权衡 |

---

## 8. 本节结论：落到项目上的检查清单

| # | 项目 | 位置 | 备注 |
|---|---|---|---|
| ① | 动画函数在**对象空间**、在 `GetVertexPositionInputs` **之前**调用 | `MyLitForwardLitPass.hlsl` | 顺序不能反 |
| ② | 位移后**重算法线**（解析导数或有限差分） | 同上 | 否则光照不跟着动 |
| ③ | 动画函数抽到 `MyLitCommon.hlsl` 或独立的 `MyLitAnimation.hlsl` | 公共文件 | 供所有 Pass 复用 |
| ④ | ShadowCaster / DepthOnly / DepthNormals **同步调用** | 各 Pass | 否则影子与 SSAO 错位 |
| ⑤ | 用统一关键字守卫（如 `_WIND_ENABLED`）并在每个 Pass 声明 | `MyLit.shader` | 保证同步开关 |
| ⑥ | 需要时放大 `Mesh.bounds` | C# / 模型 | 防止提前被剔除 |
| ⑦ | 顶点纹理采样一律 `SAMPLE_TEXTURE2D_LOD(..., 0)` | Shader | 顶点阶段没有导数 |

---

## 小结

- 顶点动画的三步：**改 OS 位置 → 重算法线 → 在所有 Pass 同步**。
- 法线不重算 = 光照不跟着动；Pass 不同步 = 影子/SSAO 与画面对不上。
- 风动用**顶点色权重 + 全局属性**，多层不同频率叠加。
- 复杂动画优先考虑 VAT + GPU Instancing。

下一节（Part 9，本系列最后一部分）我们把控制权交给 C#：属性、关键字、全局参数，以及如何用脚本驱动着色器动画。
