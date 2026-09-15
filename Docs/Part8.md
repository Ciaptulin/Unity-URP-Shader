# 顶点动画：用代码编写 Unity URP 着色器（第 8 部分）

> 原作者：NedMakesGames
> 原文链接：https://nedmakesgames.medium.com/
> 本文件已按本项目实际重写（命名 / MotionVectors Pass 对齐项目现有实现 / 大括号风格统一）
> 重写时间：Part6 完成后
> 分支：`feature/pbr-normal-mapping`

---

## 目录

- [引言](#引言)
- [顶点着色器基础](#顶点着色器基础)
  - [对象空间 vs 世界空间](#对象空间-vs-世界空间)
  - [修改顶点位置（对齐项目）](#修改顶点位置对齐项目)
- [正弦波动画](#正弦波动画)
- [风效模拟](#风效模拟)
  - [方向性风](#方向性风)
  - [每实例随机种子（需 GPU Instancing）](#每实例随机种子需-gpu-instancing)
  - [噪声风](#噪声风)
- [旗帜动画](#旗帜动画)
- [顶点颜色遮罩](#顶点颜色遮罩)
- [骨骼式顶点动画](#骨骼式顶点动画)
- [交互式顶点位移](#交互式顶点位移)
- [运动矢量（Motion Vectors）](#运动矢量motion-vectors)
  - [项目现有实现（已落地）](#项目现有实现已落地)
  - [顶点动画后如何补](#顶点动画后如何补)
- [性能考量](#性能考量)
- [总结](#总结)
- [与原翻译稿的差异对照](#与原翻译稿的差异对照)

---

## 引言

Part7 给 MyLit 换上了自写光照。但几何体本身还是静止的。这一部分让网格**动起来**——旗帜飘、草摇摆、水面涟漪、披风飞扬，全部在 GPU 顶点阶段完成，零 CPU 骨骼开销。

> **状态说明**：本部分内容**项目尚未落地**，是学习 / 扩展方向。文中的新属性 / 新函数不会自动出现在现有代码里。
>
> **注意**：`MotionVectors Pass`（见 [运动矢量](#运动矢量motion-vectors)）**项目已落地**（Pass 6，Part5-七）。

---

## 顶点着色器基础

### 对象空间 vs 世界空间

关键问题：**在哪一层做顶点动画？**

| 空间 | 优点 | 缺点 | 适用 |
|---|---|---|---|
| **对象空间** | 简单、可预测 | 不考虑对象旋转 | 旗帜、局部摆动 |
| **世界空间** | 考虑全局位置 | 要额外变换 | 风、水流 |
| **切线空间** | 沿表面方向 | 要切线数据 | 表面涟漪 |

### 修改顶点位置（对齐项目）

项目 `MyLitForwardLitPass.hlsl` 的 Vertex 目前是：

```hlsl
Interpolators Vertex(Attributes input)
{
    Interpolators output;

    VertexPositionInputs posInputs = GetVertexPositionInputs(input.positionOS);
    VertexNormalInputs normInputs = GetVertexNormalInputs(input.normalOS);

    output.positionCS = posInputs.positionCS;
    output.uv = TRANSFORM_TEX(input.uv, _ColorMap);
    OUTPUT_LIGHTMAP_UV(input.uv2, unity_LightmapST, output.uv2);
    output.normalWS = normInputs.normalWS;
    output.tangentWS = float4(normInputs.tangentWS, input.tangentOS.w);
    output.positionWS = posInputs.positionWS;
    output.vertexSH = SampleSHVertex(normInputs.normalWS);

    return output;
}
```

加顶点动画时的**正确姿势**：改完对象空间位置，**重新**调用位置相关函数。

```hlsl
Interpolators Vertex(Attributes input)
{
    Interpolators output;

    float3 positionOS = input.positionOS.xyz;

    // === 顶点动画（下一节展开）===
    ApplyVertexAnimation(positionOS, ...);

    // 重新用改过的 positionOS 走一遍位置输入
    VertexPositionInputs posInputs = GetVertexPositionInputs(positionOS);
    VertexNormalInputs normInputs = GetVertexNormalInputs(input.normalOS);

    output.positionCS = posInputs.positionCS;
    output.positionWS = posInputs.positionWS;   // 后续所有依赖 positionWS 的都跟着变
    output.uv = TRANSFORM_TEX(input.uv, _ColorMap);
    OUTPUT_LIGHTMAP_UV(input.uv2, unity_LightmapST, output.uv2);
    output.normalWS = normInputs.normalWS;
    output.tangentWS = float4(normInputs.tangentWS, input.tangentOS.w);
    output.vertexSH = SampleSHVertex(normInputs.normalWS);

    return output;
}
```

> **关键**：改 `positionOS` 后**必须重算** `GetVertexPositionInputs`。原稿直接写了 `output.positionWS = TransformObjectToWorld(positionOS)`——本项目统一走 `GetVertexPositionInputs`，能一次拿到 `positionWS` / `positionCS` / `positionVS` / `positionNDC`。

---

## 正弦波动画

```hlsl
// 属性（要加进 CBUFFER）
float _WaveFrequency;
float _WaveAmplitude;
float _WaveSpeed;

// 在 Vertex 里
float wave = sin(_Time.y * _WaveSpeed + positionOS.x * _WaveFrequency);
positionOS.y += wave * _WaveAmplitude;
```

### 多频率叠加

单正弦太假，叠三层：

```hlsl
float wave1 = sin(_Time.y * 1.0 + positionOS.x * 2.0) * 0.05;
float wave2 = sin(_Time.y * 2.3 + positionOS.z * 3.1) * 0.03;
float wave3 = sin(_Time.y * 0.7 + positionOS.x * 1.5 + positionOS.z * 0.8) * 0.04;
positionOS.y += wave1 + wave2 + wave3;
```

---

## 风效模拟

### 方向性风

草 / 植物：根部固定，顶部摆动。

```hlsl
// 属性
float3 _WindDirection;
float  _WindStrength;
float  _WindSpeed;
float  _WindFrequency;
float  _MaxHeight;

// 顶点函数
float heightFactor = saturate(positionOS.y / _MaxHeight);

float3 positionWS = TransformObjectToWorld(positionOS);
float windPhase = dot(positionWS.xz, _WindDirection.xz) * _WindFrequency;
float windWave = sin(_Time.y * _WindSpeed + windPhase);

// 方案 A：在世界空间偏
float3 windOffset = _WindDirection.xyz * windWave * _WindStrength * heightFactor;
positionWS += windOffset;

// 转回对象空间，方便后续统一处理
positionOS = TransformWorldToObject(positionWS);
```

> **原稿做法**："继续用世界空间，`output.positionCS = TransformWorldToHClip(positionWS)`"——本项目里不要这么干。项目所有 Pass 的 `positionWS` 都通过 `GetVertexPositionInputs` 得到，直接算 CS 会绕过它，且雾 / GI 会用到 `positionWS`，容易错位。**世界空间偏完，转回 OS，再走正常流程**。

### 每实例随机种子（需 GPU Instancing）

```hlsl
// 用实例 ID 做种子
float randomSeed = input.instanceID * 12.9898;
float randomPhase = sin(randomSeed) * 6.28318;

float windWave = sin(_Time.y * _WindSpeed + windPhase + randomPhase);
```

> ⚠️ **本项目未启用 GPU Instancing**。`input.instanceID` 要走 `UNITY_VERTEX_INPUT_INSTANCE_ID`，需要 `#pragma multi_compile_instancing` 整套宏（见 `Part6.md` 第五节）。**项目当前没这套**，这行直接抄会编译失败。想用的话，得先把 Instancing 那套加齐。

替代方案（项目现况）：用**物体位置**做种子，不需要 Instancing。

```hlsl
float3 objectPivotWS = TransformObjectToWorld(float3(0, 0, 0));
float randomPhase = frac(sin(dot(objectPivotWS.xz, float2(12.9898, 78.233))) * 43758.5453) * 6.28318;
```

### 噪声风

```hlsl
float Noise2D(float2 p)
{
    return sin(p.x) * cos(p.y) * 0.5 + 0.5;
}

// 顶点函数
float2 noiseUV = positionWS.xz * 0.1 + _Time.y * 0.1;
float noise = Noise2D(noiseUV);
float windWave = sin(_Time.y * _WindSpeed + noise * 6.28);
```

> 更高品质可用 `Packages/com.unity.render-pipelines.core/ShaderLibrary/Noise.hlsl` 里的 `SimpleNoise` / `GradientNoise`。

---

## 旗帜动画

```hlsl
// 属性
float _FlagWaveStrength;
float _FlagWaveFrequency;
float _FlagWaveSpeed;
float _FlagWidth;
float3 _FlagPoleAxis;

// 顶点函数
float distanceFromPole = length(positionOS.xyz - _FlagPoleAxis.xyz * positionOS.x);
float waveFactor = saturate(distanceFromPole / _FlagWidth);
float wave = sin(_Time.y * _FlagWaveSpeed - positionOS.x * _FlagWaveFrequency);

positionOS.z += wave * _FlagWaveStrength * waveFactor;
positionOS.y += wave * _FlagWaveStrength * 0.3 * waveFactor;
```

### 多波叠加

```hlsl
float wave = sin(_Time.y * _FlagWaveSpeed) * 0.5
           + sin(_Time.y * _FlagWaveSpeed * 0.7 + 1.3) * 0.3
           + sin(_Time.y * _FlagWaveSpeed * 1.3 + 2.1) * 0.2;
positionOS.z += wave * _FlagWaveStrength * waveFactor;
```

---

## 顶点颜色遮罩

用顶点色控制"哪些顶点受影响"——比阈值更精确。

```hlsl
// Attributes
float4 color : COLOR;

// Interpolators
float4 vertexColor : COLOR;

// Vertex
output.vertexColor = input.color;
float influence = input.color.r;
float3 windOffset = _WindDirection.xyz * windWave * _WindStrength * influence;
```

> 项目现有 `Attributes` **没有 `COLOR` 语义**（见 `MyLitForwardLitPass.hlsl`）。要用顶点色遮罩，需要在所有相关 Pass（ForwardLit / ShadowCaster / DepthOnly / DepthNormals / MotionVectors）的 `Attributes` 里都加 `float4 color : COLOR`，并考虑其对 `Interpolators` 的占用。

---

## 骨骼式顶点动画

### 时间偏移（纯 shader，无需额外矩阵）

```hlsl
// 属性
float _BoneCount;
float _BoneAmplitude;
float _BoneSpeed;
float _BoneHeight;

// 顶点函数
float boneIndex = floor(positionOS.y / _BoneHeight);
float phaseOffset = boneIndex * 0.5;

float boneWave = sin(_Time.y * _BoneSpeed - phaseOffset);
float2 boneDir = normalize(float2(positionOS.x, positionOS.z));

positionOS.xz += boneDir * boneWave * _BoneAmplitude * (boneIndex / _BoneCount);
```

### 程序化骨骼（C# 传矩阵）

```csharp
public class BoneAnimator : MonoBehaviour
{
    public Material targetMaterial;
    public int boneCount = 4;
    public float speed = 1.0f;
    public float maxAngle = 30f;

    void Update()
    {
        for (int i = 0; i < boneCount; i++)
        {
            float phase = Time.time * speed - i * 0.5f;
            float angle = Mathf.Sin(phase) * maxAngle;

            Matrix4x4 mat = Matrix4x4.TRS(
                Vector3.zero,
                Quaternion.Euler(0, 0, angle),
                Vector3.one
            );

            targetMaterial.SetMatrix($"_BoneMatrix{i}", mat);
        }
    }
}
```

```hlsl
// HLSL
#define MAX_BONES 8
float4x4 _BoneMatrix[MAX_BONES];
float _BoneHeight;
float _BoneCount;

// 顶点函数
float boneIndex = floor(positionOS.y / _BoneHeight);
boneIndex = clamp(boneIndex, 0, _BoneCount - 1);

float3 pivot = float3(0, boneIndex * _BoneHeight, 0);
float3 localPos = positionOS - pivot;

float4x4 boneMat = _BoneMatrix[boneIndex];
float3 rotatedPos = mul(boneMat, float4(localPos, 1)).xyz;

positionOS = rotatedPos + pivot;
```

> ⚠️ `_BoneMatrix[]` / `_BoneHeight` / `_BoneCount` 是**着色器全局 / 材质属性**，不是 `UnityPerMaterial` CBUFFER 里的普通字段——**数组不能进 `UnityPerMaterial` CBUFFER**。要么走 `Material.SetMatrixArray`（材质属性，但会破坏 SRP Batcher 对数组的支持），要么走 `Shader.SetGlobalMatrixArray`（全局）。前者更常用。

---

## 交互式顶点位移

### 点击涟漪

```csharp
public class RippleSender : MonoBehaviour
{
    public Material targetMaterial;
    private static readonly int RippleOriginID = Shader.PropertyToID("_RippleOrigin");
    private static readonly int RippleTimeID = Shader.PropertyToID("_RippleTime");

    void Update()
    {
        if (Input.GetMouseButtonDown(0))
        {
            Ray ray = Camera.main.ScreenPointToRay(Input.mousePosition);
            if (Physics.Raycast(ray, out RaycastHit hit))
            {
                targetMaterial.SetVector(RippleOriginID, hit.point);
                targetMaterial.SetFloat(RippleTimeID, Time.time);
            }
        }
    }
}
```

```hlsl
// 属性（进 CBUFFER）
float3 _RippleOrigin;
float  _RippleTime;
float  _RippleSpeed;
float  _RippleAmplitude;
float  _RippleWidth;

// 顶点函数
float3 positionWS = TransformObjectToWorld(positionOS);
float distToRipple = distance(positionWS.xz, _RippleOrigin.xz);

float rippleAge = _Time.y - _RippleTime;
float rippleRadius = rippleAge * _RippleSpeed;
float rippleDist = abs(distToRipple - rippleRadius);

float ripple = exp(-rippleDist * rippleDist / _RippleWidth)
             * sin(distToRipple * 10 - rippleAge * _RippleSpeed * 5);

positionWS.y += ripple * _RippleAmplitude;
positionOS = TransformWorldToObject(positionWS);
```

> 原稿直接在 `positionWS` 上加完就走 `output.positionCS = TransformWorldToHClip(positionWS)`。**本项目不要**——见"方向性风"里的说明，改成转回 OS。

### 角色踩踏

```csharp
public class GrassStomper : MonoBehaviour
{
    public Material grassMaterial;
    public float stompRadius = 2f;
    public float stompDepth = 0.3f;

    private static readonly int StompPosID = Shader.PropertyToID("_StompPosition");
    private static readonly int StompRadiusID = Shader.PropertyToID("_StompRadius");
    private static readonly int StompDepthID = Shader.PropertyToID("_StompDepth");

    void Update()
    {
        grassMaterial.SetVector(StompPosID, transform.position);
        grassMaterial.SetFloat(StompRadiusID, stompRadius);
        grassMaterial.SetFloat(StompDepthID, stompDepth);
    }
}
```

```hlsl
float3 _StompPosition;
float  _StompRadius;
float  _StompDepth;

// 顶点函数
float3 positionWS = TransformObjectToWorld(positionOS);
float distToStomp = distance(positionWS.xz, _StompPosition.xz);

float stompFactor = 1 - smoothstep(0, _StompRadius, distToStomp);
stompFactor = pow(stompFactor, 2);

float3 stompDir = normalize(positionWS.xz - _StompPosition.xz);
positionWS.xz += stompDir * stompFactor * _StompDepth;
positionWS.y  -= stompFactor * _StompDepth * 0.5;

positionOS = TransformWorldToObject(positionWS);
```

---

## 运动矢量（Motion Vectors）

### 项目现有实现（已落地）

**项目已经有 `MyLitMotionVectorPass.hlsl`（Pass 6）**，Part5-七 完成。原稿当作"本部分新增从零写"，与项目实况不符。

项目现有版本核心（对齐 `MotionVectorsCommon.hlsl`）：

```hlsl
// ===== [Part5-七] 运动向量通道（运动模糊 / TAA 用）=====
Interpolators Vertex(Attributes input)
{
    Interpolators output = (Interpolators)0;
    VertexPositionInputs vpInputs = GetVertexPositionInputs(input.positionOS.xyz);

    output.positionCSNoJitter = mul(_NonJitteredViewProjMatrix, mul(UNITY_MATRIX_M, input.positionOS));
    output.previousPositionCSNoJitter = mul(_PrevViewProjMatrix, mul(UNITY_PREV_MATRIX_M, input.positionOS));

    output.positionCS = vpInputs.positionCS;
    ApplyMotionVectorZBias(output.positionCS);
    ...
}

float4 Fragment(Interpolators input) : SV_TARGET
{
    float2 velocity = CalcNdcMotionVectorFromCsPositions(
        input.positionCSNoJitter,
        input.previousPositionCSNoJitter);
    return float4(velocity, 0, 0);
}
```

### 顶点动画后如何补

**关键问题**：项目现在的 MotionVectors Pass **没有顶点动画**。一旦 ForwardLit 加了顶点动画，MotionVectors 也必须**用同一套动画函数**算当前位置和上一帧位置，否则 TAA / 运动模糊会抖动或穿帮。

正确做法：

```hlsl
Interpolators Vertex(Attributes input)
{
    Interpolators output = (Interpolators)0;

    // ===== 当前帧位置（带动画）=====
    float3 positionOS = input.positionOS.xyz;
    ApplyVertexAnimation(positionOS, /*time*/ _Time.y);
    output.positionCSNoJitter = mul(_NonJitteredViewProjMatrix, mul(UNITY_MATRIX_M, float4(positionOS, 1)));

    // ===== 上一帧位置（用上一帧时间，同样带动画）=====
    float3 prevPositionOS = input.positionOS.xyz;
    ApplyVertexAnimation(prevPositionOS, /*time*/ _Time.y - unity_DeltaTime.x);
    output.previousPositionCSNoJitter = mul(_PrevViewProjMatrix, mul(UNITY_PREV_MATRIX_M, float4(prevPositionOS, 1)));

    // ===== 光栅化位置（用普通位置即可，抖动由管线补）=====
    VertexPositionInputs vpInputs = GetVertexPositionInputs(positionOS);
    output.positionCS = vpInputs.positionCS;
    ApplyMotionVectorZBias(output.positionCS);

    return output;
}

// 顶点动画函数必须【共用】：ForwardLit 和 MotionVectors 都 include 它
void ApplyVertexAnimation(inout float3 positionOS, float time)
{
    // 用 time 而不是 _Time.y，才能算上一帧位置
    float wave = sin(time * _WindSpeed + positionOS.x * _WindFrequency);
    positionOS.y += wave * _WindAmplitude;
}
```

要点：

1. **动画函数必须参数化时间**，不能写死 `_Time.y`——算上一帧位置要用 `_Time.y - unity_DeltaTime.x`
2. **动画函数放共享头文件**（比如 `MyLitVertexAnimation.hlsl`），ForwardLit / MotionVectors 同时 include
3. 上一帧矩阵用 `UNITY_PREV_MATRIX_M`（物体历史）+ `_PrevViewProjMatrix`（相机历史），Part5-七 已讲透

> **原稿的坑**：用了 `unity_MatrixPreviousM`（旧名，部分版本已变 `UNITY_PREV_MATRIX_M`）、`UNITY_MATRIX_P` 自己算投影、`_ALPHATEST_ON`、`CalculateMotionVector`（旧函数名）。**全部与本项目不符**。以项目 `MyLitMotionVectorPass.hlsl` 为准。

---

## 性能考量

### 批处理兼容性

| 批处理方式 | 兼容顶点动画？ |
|---|---|
| SRP Batcher | ✅（只要 CBUFFER 规则对） |
| GPU Instancing | ✅（每实例独立参数） |
| **静态批处理** | ❌（CPU 端合并，顶点着色器看不到原对象空间） |
| **动态批处理** | ❌（顶点数上限） |

> 本项目：SRP Batcher ✅，GPU Instancing ❌（未启用）。

### 优化技巧

1. **顶点阶段少做复杂运算**：噪声别叠太多
2. **预计算**：能 C# 算的，通过属性传进来
3. **LOD**：远处用简版动画或直接关
4. **共用动画函数**：ForwardLit / MotionVectors 走同一套，避免两边逻辑漂移

### 顶点动画 vs 骨骼动画

| 特性 | 顶点动画 | 骨骼动画 |
|---|---|---|
| CPU 开销 | 极低 | 中（蒙皮）|
| GPU 开销 | 低 | 中（蒙皮矩阵）|
| 灵活性 | 程序化、无限变化 | 手工、精确 |
| 适用 | 草 / 旗 / 水 | 角色 / 机械 |

---

## 总结

### 顶点动画速查表

| 效果 | 核心公式 | 复杂度 |
|---|---|---|
| 正弦波浪 | `sin(time * speed + pos * freq)` | ⭐ |
| 方向性风 | `windDir * sin(time + dot(pos, windDir))` | ⭐⭐ |
| 旗帜飘动 | `sin(time - x * freq) * distFromPole` | ⭐⭐ |
| 噪声风 | `sin(time + noise(pos * scale))` | ⭐⭐⭐ |
| 顶点颜色遮罩 | `vertexColor.r * animation` | ⭐ |
| 骨骼链 | 相位偏移 + 旋转矩阵 | ⭐⭐⭐ |
| 点击涟漪 | `exp(-d²) * sin(dist * freq - time)` | ⭐⭐ |
| 踩踏弯曲 | `smoothstep(dist, radius) * dir` | ⭐⭐ |

### 关键提醒（对齐项目）

+ ✅ 改完 `positionOS` 后，**重新调 `GetVertexPositionInputs`**（而不是自己算 CS）
+ ✅ 世界空间偏完**转回对象空间**再走正常流程
+ ✅ 用顶点色 / UV 做遮罩
+ ✅ 顶点动画如果上了，**MotionVectors Pass 必须同步**
+ ✅ 动画函数**参数化时间**（支持上一帧）
+ ❌ 不在顶点里做纹理采样
+ ❌ 不对大量顶点做复杂数学

---

## 与原翻译稿的差异对照

| # | 原稿 | 本项目 / 正确做法 |
|---|---|---|
| 1 | 顶点动画后直接 `output.positionCS = TransformWorldToHClip(positionWS)` | 改完转回 `positionOS`，走 `GetVertexPositionInputs` |
| 2 | 用 `input.instanceID` 但项目无 Instancing | 用物体位置做种子（现况可用）|
| 3 | MotionVectors 当"新增"讲 | 项目已有 Pass 6；重点是"加顶点动画后如何同步" |
| 4 | `unity_MatrixPreviousM` / `UNITY_MATRIX_P` / `CalculateMotionVector` | `UNITY_PREV_MATRIX_M` / `_PrevViewProjMatrix` / `CalcNdcMotionVectorFromCsPositions` |
| 5 | `_ALPHATEST_ON` | `_ALPHA_CUTOUT` |
| 6 | 动画函数写死 `_Time.y` | 必须参数化时间，支持上一帧 |
| 7 | `_BoneMatrix[]` 未说明放哪 | 数组不能进 UnityPerMaterial CBUFFER，走材质属性数组 / 全局 |
| 8 | 大括号不换行 | 大括号换行 |
| 9 | 顶点色直接假设 Attributes 里有 | 项目 Attributes 现无 COLOR，需同步所有 Pass |

---

## 下一步

+ 若真要落地顶点动画：先抽出共享 `MyLitVertexAnimation.hlsl`，ForwardLit 和 MotionVectors **同时 include**
+ 后续：`09_CSharp交互.md` → 重写版 `Part9.md`

> 文档完。如有疑问，翻 `Docs/` 下的其他文档。
