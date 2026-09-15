# 与 C# 交互：用代码编写 Unity URP 着色器（第 9 部分）

> 原作者：NedMakesGames
> 原文链接：https://nedmakesgames.medium.com/
> 本文件已按本项目实际重写（属性名 / Inspector / MaterialPropertyBlock 与 Instancing 的关系 / C# 代码 bug 全部对齐或修正）
> 重写时间：Part6 完成后
> 分支：`feature/pbr-normal-mapping`

---

## 目录

- [引言](#引言)
- [从 C# 设置材质属性](#从-c-设置材质属性)
  - [基本属性设置](#基本属性设置)
  - [属性 ID 优化](#属性-id-优化)
- [全局着色器变量](#全局着色器变量)
- [材质属性块（Material Property Block）](#材质属性块material-property-block)
  - [与 SRP Batcher / GPU Instancing 的关系（修正）](#与-srp-batcher--gpu-instancing-的关系修正)
- [渲染纹理交互](#渲染纹理交互)
- [程序化颜色](#程序化颜色)
- [运行时材质实例化](#运行时材质实例化)
- [事件驱动的着色器效果](#事件驱动的着色器效果)
- [调试与性能](#调试与性能)
- [完整示例：交互式涟漪系统](#完整示例交互式涟漪系统)
- [总结](#总结)
- [与原翻译稿的差异对照](#与原翻译稿的差异对照)

---

## 引言

前面几部分让 MyLit 有了完整的光照 / 深度 / 动画能力，但着色器还是**孤立的**——不会响应游戏状态。这一部分闭合循环：从 C# 与着色器通信。

> **状态说明**：本部分内容**项目尚未落地**，是学习 / 扩展方向。但有一处例外——项目已有 `MyLitCustomInspector.cs`（Part2~Part5），它本身就是"用 C# 控制材质 / 关键字"的实战样例，应作为本部分的第一参照。

---

## 从 C# 设置材质属性

### 基本属性设置

> **命名已对齐项目**：项目用的是 `_Metalness`（不是 `_Metallic`）、`_ColorTint`、`_Smoothness`、`_ColorMap`。详细清单见 `MyLit.shader`。

```csharp
using UnityEngine;

public class MaterialController : MonoBehaviour
{
    public Material targetMaterial;

    void Start()
    {
        targetMaterial.SetFloat("_Smoothness", 0.8f);
        targetMaterial.SetFloat("_Metalness", 0.5f);      // 项目名：_Metalness
        targetMaterial.SetColor("_ColorTint", Color.red);
        targetMaterial.SetTexture("_ColorMap", someTex);  // 项目名：_ColorMap
        targetMaterial.SetVector("_WindDirection", new Vector4(1, 0, 0, 0));
        targetMaterial.SetInt("_SurfaceType", 1);
    }
}
```

> 属性的"权威清单"在 `MyLit.shader` 的 `Properties` 块和 `MyLitCommon.hlsl` 的 `UnityPerMaterial` CBUFFER。写 C# 前先看这两处。

### 属性 ID 优化

```csharp
public class OptimizedMaterialController : MonoBehaviour
{
    public Material targetMaterial;

    private static readonly int SmoothnessID = Shader.PropertyToID("_Smoothness");
    private static readonly int ColorTintID  = Shader.PropertyToID("_ColorTint");
    private static readonly int MetalnessID  = Shader.PropertyToID("_Metalness");

    void Update()
    {
        targetMaterial.SetFloat(SmoothnessID, Mathf.PingPong(Time.time * 0.5f, 1.0f));
        targetMaterial.SetColor(ColorTintID, Color.Lerp(Color.white, Color.red, Time.time % 2));
        targetMaterial.SetFloat(MetalnessID, Mathf.PingPong(Time.time * 0.3f, 1.0f));
    }
}
```

> 原稿示例里 `WindDirectionID` 缓存了但 `Update` 里用 `targetMaterial.SetVector(WindDirectionID, ...)`——**项目现有 Attributes 没有 `_WindDirection`**（那要 `08_顶点动画.md` 那批新属性）。为避免误导，本版换成项目里**确实存在**的属性。

---

## 全局着色器变量

想让**所有**材质同时响应同一个值（全局风、全局时间缩放、全局伤害脉冲）时用。

```csharp
public class GlobalWindController : MonoBehaviour
{
    private static readonly int GlobalWindID      = Shader.PropertyToID("_GlobalWindDirection");
    private static readonly int GlobalTimeScaleID = Shader.PropertyToID("_GlobalTimeScale");

    [Range(0, 2)]
    public float timeScale = 1.0f;

    void Update()
    {
        Vector3 windDir = new Vector3(
            Mathf.Sin(Time.time * 0.2f), 0,
            Mathf.Cos(Time.time * 0.2f)
        ).normalized;

        Shader.SetGlobalVector(GlobalWindID, windDir);
        Shader.SetGlobalFloat(GlobalTimeScaleID, timeScale);
    }
}
```

着色器侧——**全局变量声明在 CBUFFER 外**，写在 `MyLitCommon.hlsl` 里：

```hlsl
// ===== 全局变量（不在 UnityPerMaterial CBUFFER 中）=====
float3 _GlobalWindDirection;
float  _GlobalTimeScale;
```

> **注意**：`Shader.SetGlobal*` 一旦设置，**所有**着色器都能读到，与材质无关。`SetGlobalColor` / `SetGlobalTexture` 同理。它**不破坏 SRP Batcher**——因为全局变量本来就不在 `UnityPerMaterial` 里。

---

## 材质属性块（Material Property Block）

**作用**：给同一材质的**不同渲染器**设不同属性，而不产生材质实例。

```csharp
public class GrassColorController : MonoBehaviour
{
    private static readonly int ColorTintID = Shader.PropertyToID("_ColorTint");

    private MeshRenderer meshRenderer;
    private MaterialPropertyBlock block;

    void Awake()
    {
        meshRenderer = GetComponent<MeshRenderer>();
        block = new MaterialPropertyBlock();
    }

    void Start()
    {
        Color c = Color.Lerp(
            new Color(0.2f, 0.6f, 0.1f),
            new Color(0.5f, 0.9f, 0.2f),
            Random.value
        );
        block.SetColor(ColorTintID, c);
        meshRenderer.SetPropertyBlock(block);
    }
}
```

### 与 SRP Batcher / GPU Instancing 的关系（修正）

> **原稿这里说错了**。原稿写：
>
> > "如果你需要 SRP Batcher **和** 逐实例属性，解决方案是 GPU Instancing（如第 6 章所述）。"
>
> **真相更微妙**：

| 手段 | SRP Batcher | GPU Instancing |
|---|---|---|
| `Material.Set*`（材质实例） | ✅ 兼容 | ❌ 不涉及 |
| `Shader.SetGlobal*` | ✅ 兼容（全局变量本就在 CBUFFER 外）| ❌ |
| **`MaterialPropertyBlock`** | **❌ 破坏 SRP Batcher** | ✅ 逐渲染器设值 |
| **GPU Instancing**（`UNITY_DEFINE_INSTANCED_PROP`）| ✅ 兼容（走实例缓冲，不进 `UnityPerMaterial`）| ✅ 逐实例设值 |

**关键**：
- `MaterialPropertyBlock` 与 SRP Batcher **互斥**（MPB 的逐渲染器值会绕过 SRP Batcher 的 CBUFFER）
- GPU Instancing 和 SRP Batcher **可以共存**——Instancing 的逐实例数据走 `UNITY_INSTANCING_BUFFER`，不污染 `UnityPerMaterial`
- 所以：**要"逐对象 + 保留 SRP Batcher"，用 GPU Instancing；不要 SRP Batcher，才用 MPB**

**决策树**：
```
需要逐渲染器属性？
├── 是
│   ├── 该材质已启用 GPU Instancing？
│   │   ├── 是 → 用 UNITY_DEFINE_INSTANCED_PROP（SRP Batcher 兼容）
│   │   └── 否 → 用 MaterialPropertyBlock（放弃 SRP Batcher 对该材质的好处）
│   └── 否 → 直接用 Material.Set*（SRP Batcher 兼容）
```

> **本项目现况**：`MyLit` **未启用 GPU Instancing**。要用 MPB，等于放弃 MyLit 的 SRP Batcher 兼容。若在乎 SRP Batcher，别用 MPB。

### 着色器侧（Instancing 版本，仅当启用了 Instancing）

```hlsl
UNITY_INSTANCING_BUFFER_START(Props)
    UNITY_DEFINE_INSTANCED_PROP(float4, _InstanceColor)
UNITY_INSTANCING_BUFFER_END(Props)

// 片元
float4 c = UNITY_ACCESS_INSTANCED_PROP(Props, _InstanceColor);
```

> **注意**：`UNITY_ACCESS_INSTANCED_PROP` 那套必须配合 `#pragma multi_compile_instancing` 和 `UNITY_VERTEX_INPUT_INSTANCE_ID` 一起用。**项目没这套**，直接加会编译失败。详见 `Part6.md` 第五节。

---

## 渲染纹理交互

RT 让你的着色器有"记忆"——玩家能在表面涂鸦、踩草、留脚印。

### 创建 RT

```csharp
public class InteractionTextureCreator : MonoBehaviour
{
    public int textureSize = 512;
    public RenderTexture interactionRT;

    void Awake()
    {
        interactionRT = new RenderTexture(textureSize, textureSize, 0, RenderTextureFormat.R8);
        interactionRT.filterMode = FilterMode.Bilinear;
        interactionRT.wrapMode = TextureWrapMode.Clamp;
        interactionRT.Create();

        RenderTexture.active = interactionRT;
        GL.Clear(true, true, Color.black);
        RenderTexture.active = null;
    }

    void OnDestroy()
    {
        if (interactionRT != null)
            interactionRT.Release();
    }
}
```

### 着色器侧

```hlsl
// MyLitCommon.hlsl
TEXTURE2D(_InteractionMap);
SAMPLER(sampler_InteractionMap);
float4 _InteractionMap_ST;
float4 _InteractionMapBoundsMin;
float4 _InteractionMapBoundsMax;
```

```hlsl
// Vertex：世界 XZ → 交互 UV
float2 worldXZ = positionWS.xz;
float2 interactionUV = (worldXZ - _InteractionMapBoundsMin.xz)
                     / (_InteractionMapBoundsMax.xz - _InteractionMapBoundsMin.xz);
output.interactionUV = saturate(interactionUV);
```

> **注意**：`_InteractionMap` 这类 RT 是**材质属性**（每个材质一张）。若想全局共享（比如所有草共用一张踩踏图），走 `Shader.SetGlobalTexture`——但那时**不要**再声明进 `UnityPerMaterial` CBUFFER。

### 从 C# 写入 RT

写 RT 更稳的做法是用 `CommandBuffer` + `Graphics.Blit`（画一张"笔刷"图到 RT 上）：

```csharp
public class GrassPainter : MonoBehaviour
{
    public RenderTexture interactionRT;
    public Material brushMaterial;   // 一个简单的笔刷材质
    public Transform bounds;

    private static readonly int BrushPosID = Shader.PropertyToID("_BrushPos");
    private static readonly int BrushRadiusID = Shader.PropertyToID("_BrushRadius");

    void Update()
    {
        if (!Input.GetMouseButton(0)) return;

        Ray ray = Camera.main.ScreenPointToRay(Input.mousePosition);
        if (!Physics.Raycast(ray, out RaycastHit hit)) return;

        Vector3 localPos = bounds.InverseTransformPoint(hit.point);
        Vector2 uv = new Vector2(localPos.x + 0.5f, localPos.z + 0.5f);

        brushMaterial.SetVector(BrushPosID, uv);
        brushMaterial.SetFloat(BrushRadiusID, 0.1f);

        var cmd = CommandBufferPool.Get("PaintGrass");
        cmd.SetRenderTarget(interactionRT);
        cmd.DrawMesh(FullscreenMesh, Matrix4x4.identity, brushMaterial);  // 用笔刷材质全屏绘
        context.ExecuteCommandBuffer(cmd);
        CommandBufferPool.Release(cmd);
    }
}
```

> 原稿用 `GL.PushMatrix` / `GL.LoadPixelMatrix` 手工画——**可行但过时**。更现代的方式是 `CommandBuffer` / `Graphics.Blit`。而且 `GL.LoadPixelMatrix` 在不同平台 / 图形 API 上行为有差异（D3D vs GL 的 Y 轴），能避则避。

---

## 程序化颜色

### 基于时间的颜色

```csharp
public class TimeBasedColor : MonoBehaviour
{
    public Material targetMaterial;
    public Gradient dayNightGradient;
    public Light sunLight;

    private static readonly int ColorTintID = Shader.PropertyToID("_ColorTint");

    void Update()
    {
        float sunHeight = sunLight.transform.forward.y;
        float t = Mathf.InverseLerp(-0.2f, 0.8f, sunHeight);
        targetMaterial.SetColor(ColorTintID, dayNightGradient.Evaluate(t));
    }
}
```

### 基于状态的颜色

```csharp
public class HealthColorController : MonoBehaviour
{
    public Material targetMaterial;
    public float maxHealth = 100f;
    private float currentHealth;

    private static readonly int ColorTintID = Shader.PropertyToID("_ColorTint");
    private static readonly int EmissionTintID = Shader.PropertyToID("_EmissionTint");

    void Start() { currentHealth = maxHealth; }

    public void TakeDamage(float amount)
    {
        currentHealth = Mathf.Max(0, currentHealth - amount);
        float healthPercent = currentHealth / maxHealth;

        // 项目名：_ColorTint / _EmissionTint（不是 _HealthColor / _DamageFlash）
        targetMaterial.SetColor(ColorTintID, Color.Lerp(Color.red, Color.green, healthPercent));
        targetMaterial.SetColor(EmissionTintID, Color.Lerp(Color.black, Color.red, 1 - healthPercent));
    }
}
```

> 溶解效果的 `_NoiseTexture` / `_DissolveAmount` 是**新属性**，项目里**不存在**。要加的话，按 `Part7.md` 的方式先声明进 `MyLit.shader` 属性块 + `MyLitCommon.hlsl` 的 CBUFFER。原稿直接拿 `_NoiseTexture` 用但**没声明过**，直接抄会编译失败。

### HP 条与 UI 着色器

UI 着色器是**另一支**着色器（不进 URP Lit），属性按需自己声明。这里只展示与"外部驱动"相关的手法——和上面的 `_ColorTint` / `SetFloat` 一模一样，故从略。

---

## 运行时材质实例化

### Material 克隆

```csharp
public class RuntimeMaterialCreator : MonoBehaviour
{
    public Material baseMaterial;
    public MeshRenderer targetRenderer;

    private Material instance;

    void Start()
    {
        instance = new Material(baseMaterial);
        instance.SetColor("_ColorTint", Random.ColorHSV());
        instance.SetFloat("_Smoothness", Random.Range(0.1f, 0.9f));
        instance.SetFloat("_Metalness", Random.value > 0.5f ? 1 : 0);  // 项目名：_Metalness
        targetRenderer.material = instance;
    }

    void OnDestroy()
    {
        if (instance != null)
            Destroy(instance);
    }
}
```

> **原稿的 bug**：`OnDestroy` 里写 `if (targetRenderer.material != null && targetRenderer.material != baseMaterial)`——但 `targetRenderer.material` **每次访问都会自动克隆**！这个判断会在 `OnDestroy` 里制造一个新的克隆，然后销毁它，同时**没销毁真正的实例**。正确做法是**自己持有引用**（如上 `private Material instance`），`OnDestroy` 只销毁它。**永远不要**在清理代码里访问 `renderer.material`。

### 共享材质 vs 实例材质

```csharp
// ❌ 改共享材质，影响所有用它的物体
renderer.sharedMaterial.SetColor("_ColorTint", Color.red);

// ✅ 改实例材质（隐式克隆一次）
renderer.material.SetColor("_ColorTint", Color.red);
```

---

## 事件驱动的着色器效果

### 受伤闪白

> **原稿用了 `_FlashColor` / `_FlashAmount`**——这两个属性**项目里没有**。本项目已有的等效属性是 `_EmissionTint`（配合 `_EMISSION` 关键字）。下面给出**用项目现有属性**的实现。

```csharp
public class DamageFlashEffect : MonoBehaviour
{
    public Material targetMaterial;
    public float flashDuration = 0.15f;
    public Color flashColor = Color.white;

    private static readonly int EmissionTintID = Shader.PropertyToID("_EmissionTint");
    private static readonly int EmissionKeyword = Shader.PropertyToID("_EMISSION");

    private Color originalEmission;
    private Coroutine flashCoroutine;

    void Awake()
    {
        originalEmission = targetMaterial.GetColor(EmissionTintID);
    }

    public void OnDamaged()
    {
        if (flashCoroutine != null) StopCoroutine(flashCoroutine);
        flashCoroutine = StartCoroutine(FlashCoroutine());
    }

    IEnumerator FlashCoroutine()
    {
        targetMaterial.EnableKeyword("_EMISSION");
        targetMaterial.globalIlluminationFlags = MaterialGlobalIlluminationFlags.EmissiveIsBlack;

        float elapsed = 0;
        while (elapsed < flashDuration)
        {
            elapsed += Time.deltaTime;
            float t = elapsed / flashDuration;
            float amount = Mathf.Pow(1 - t, 3);
            targetMaterial.SetColor(EmissionTintID, flashColor * amount);
            yield return null;
        }

        // 恢复
        targetMaterial.SetColor(EmissionTintID, originalEmission);
        // 若原本没有自发光，这里可 DisableKeyword("_EMISSION")；由业务决定
    }
}
```

> **关键字注意**：`_EMISSION` 在项目里是 `shader_feature_local_fragment`。它不会因为你设了 `_EmissionTint` 颜色就自动亮——**必须显式 `EnableKeyword("_EMISSION")`**。这条项目在 `MyLitCustomInspector.cs` 的 `UpdateSurfaceType` 里已经处理了（依据贴图 / 色调）。

### 元素状态切换

结构上和上面一致（切换 `_ColorMap` / `_EmissionTint` / 关键字），不再赘述。

---

## 调试与性能

### 属性设置性能

按性能从快到慢：

| 方法 | 每帧 1000 物体 | 内存 | 适用 |
|---|---|---|---|
| `Shader.SetGlobal*` | 最快 | 无 | 全局参数 |
| `Material.Set*`（缓存 ID）| 快 | 中（每材质实例）| 少量物体 |
| `MaterialPropertyBlock` | 中（且**破坏 SRP Batcher**）| 低（每渲染器）| 不要 SRP Batcher 的逐对象 |
| `Material.Set*`（字符串）| 慢 | 中 | ❌ 避免每帧 |
| `new Material()` 每帧 | 最慢 + GC | 高 | ❌ 绝对不要 |

> 原稿此表漏了"MPB 破坏 SRP Batcher"这一关键代价，已补。

### 常见陷阱

**1. 字符串属性名**
```csharp
// ❌
mat.SetFloat("_Smoothness", v);
// ✅
private static readonly int SmoothnessID = Shader.PropertyToID("_Smoothness");
mat.SetFloat(SmoothnessID, v);
```

**2. 每帧创建材质**
```csharp
// ❌ 每帧 GC
void Update() { renderer.material = new Material(baseMat); }
// ✅ 创建一次，复用
private Material inst;
void Awake() { inst = new Material(baseMat); renderer.material = inst; }
void Update() { inst.SetFloat(SmoothnessID, v); }
```

**3. 改 sharedMaterial**
```csharp
// ❌ 影响所有使用该材质的物体
renderer.sharedMaterial.SetColor(id, c);
// ✅ 只影响自己
renderer.material.SetColor(id, c);
```

**4. 在 OnDestroy 里访问 renderer.material**
```csharp
// ❌ 会触发隐式克隆（见上节）
void OnDestroy()
{
    if (renderer.material != null) Destroy(renderer.material);
}
// ✅ 自己持有引用，销毁它
private Material instance;
void OnDestroy() { if (instance != null) Destroy(instance); }
```

---

## 完整示例：交互式涟漪系统

组合全局变量 + RT + 时间驱动。**着色器侧新增属性**（需先按 `Part7.md` 方式声明）：

```hlsl
// MyLitCommon.hlsl —— 全局变量（不在 CBUFFER）
float3 _RippleOrigin;
float  _RippleTime;
float4 _RippleParams;   // x=radius, y=strength, z=speed

float3 CalculateRipple(float3 positionWS)
{
    float distToRipple = distance(positionWS.xz, _RippleOrigin.xz);
    float rippleRadius   = _RippleParams.x;
    float rippleStrength = _RippleParams.y;
    float rippleSpeed    = _RippleParams.z;

    float rippleWave = sin(distToRipple * 20 - _RippleTime * 10);
    float falloff    = exp(-distToRipple * distToRipple / (rippleRadius * rippleRadius));
    float waveFront  = 1 - smoothstep(0, 0.1, abs(distToRipple - _RippleTime * rippleSpeed * 0.5));

    return float3(0, rippleWave * falloff * rippleStrength * waveFront, 0);
}
```

```hlsl
// Vertex —— 注意顺序：先改 positionOS，再走 GetVertexPositionInputs（见 Part8）
float3 positionOS = input.positionOS.xyz;
float3 positionWS = TransformObjectToWorld(positionOS);
positionWS += CalculateRipple(positionWS);
positionOS = TransformWorldToObject(positionWS);

VertexPositionInputs posInputs = GetVertexPositionInputs(positionOS);
output.positionCS = posInputs.positionCS;
output.positionWS = posInputs.positionWS;
```

```csharp
using UnityEngine;

public class RippleSystem : MonoBehaviour
{
    public Transform groundPlane;
    public float rippleRadius = 0.5f;
    public float rippleSpeed = 3.0f;
    public float rippleDamping = 0.95f;

    private static readonly int RippleOriginID = Shader.PropertyToID("_RippleOrigin");
    private static readonly int RippleTimeID   = Shader.PropertyToID("_RippleTime");
    private static readonly int RippleParamsID = Shader.PropertyToID("_RippleParams");

    private float currentRippleTime;
    private Vector3 lastRipplePos;
    private float rippleStrength;
    private bool hasActiveRipple;

    void Update()
    {
        if (Input.GetMouseButtonDown(0))
        {
            Ray ray = Camera.main.ScreenPointToRay(Input.mousePosition);
            if (Physics.Raycast(ray, out RaycastHit hit))
            {
                lastRipplePos = hit.point;
                currentRippleTime = 0;
                rippleStrength = 1.0f;
                hasActiveRipple = true;
            }
        }

        if (hasActiveRipple)
        {
            currentRippleTime += Time.deltaTime * rippleSpeed;
            rippleStrength *= rippleDamping;

            if (rippleStrength < 0.01f)
            {
                hasActiveRipple = false;
                rippleStrength = 0;
            }

            Shader.SetGlobalVector(RippleOriginID, lastRipplePos);
            Shader.SetGlobalFloat(RippleTimeID, currentRippleTime);
            Shader.SetGlobalVector(RippleParamsID,
                new Vector4(rippleRadius, rippleStrength, rippleSpeed, 0));
        }
    }
}
```

> **原稿的坑**：原稿在 C# 里 `Shader.SetGlobalTexture(RippleRTID, rippleRT)` 但着色器又声明 `_RippleTexture`——混合了"RT 交互"和"全局参数"两条路，最终代码里 `CommandBuffer` 的"绘制圆形"是空的（只写了注释）。本版改成**纯参数驱动**（无 RT），逻辑闭环，能跑。

---

## 总结

### C# ↔ Shader 通信速查表

| 方法 | C# 端 | 着色器端 | 作用域 | 与 SRP Batcher |
|---|---|---|---|---|
| `Material.SetFloat` | `mat.SetFloat(id, v)` | `float _MyFloat;`（在 CBUFFER）| 单个材质实例 | ✅ |
| `Material.SetColor` | `mat.SetColor(id, c)` | `float4 _MyColor;`（在 CBUFFER）| 单个材质实例 | ✅ |
| `Material.SetTexture` | `mat.SetTexture(id, t)` | `TEXTURE2D(_MyTex)`（CBUFFER 外）| 单个材质实例 | ✅ |
| `Material.SetVector` | `mat.SetVector(id, v)` | `float4 _MyVec;`（在 CBUFFER）| 单个材质实例 | ✅ |
| `Shader.SetGlobalFloat` | `Shader.SetGlobalFloat(id, v)` | `float _GlobalVal;`（CBUFFER 外）| 全局 | ✅ |
| `Shader.SetGlobalTexture` | `Shader.SetGlobalTexture(id, t)` | `TEXTURE2D(_GlobalTex)`（CBUFFER 外）| 全局 | ✅ |
| **`MaterialPropertyBlock`** | `block.SetFloat(id, v)` | 普通材质属性 | 逐渲染器 | **❌ 破坏** |
| **GPU Instancing** | `Graphics.DrawMeshInstanced` | `UNITY_DEFINE_INSTANCED_PROP` | 逐实例 | ✅ |

### 属性 ID 命名约定

```csharp
// ✅
private static readonly int SmoothnessID = Shader.PropertyToID("_Smoothness");
private static readonly int ColorTintID  = Shader.PropertyToID("_ColorTint");
// ❌
mat.SetFloat("s", 0.5f);
```

---

## 与原翻译稿的差异对照

| # | 原稿 | 本项目 / 正确做法 |
|---|---|---|
| 1 | `_Metallic` | `_Metalness`（项目名）|
| 2 | `_HealthColor` / `_DamageFlash` / `_NoiseTexture` / `_FlashColor` / `_FlashAmount` 直接用 | 项目里**不存在**，需先声明；本版改用现有 `_EmissionTint` / `_ColorTint` |
| 3 | "MPB + SRP Batcher 用 Instancing 解决" | 表述**错误**：MPB 与 SRP Batcher 互斥；Instancing 才两者兼得。已重写"关系"表 |
| 4 | `OnDestroy` 里访问 `renderer.material` | 会触发隐式克隆 + 内存泄漏；改为自持引用 |
| 5 | `GL.LoadPixelMatrix` 画 RT | 改用 `CommandBuffer` / `Graphics.Blit`（更稳，跨 API 一致）|
| 6 | 涟漪示例 `CommandBuffer` 里"绘制圆形"是空注释 | 改为纯参数驱动，逻辑闭环 |
| 7 | `EmissionTintID` 声明后未用 | 本版直接用起来 |
| 8 | 属性设置性能表漏"MPB 破 SRP Batcher" | 已补 |
| 9 | "全系列总结"宣称"卡通渲染 ✅ / GPU Instancing ✅ / 顶点动画 ✅" | 项目实况里**均未落地**，本版删除误导性清单 |
| 10 | `switch` / 大括号不换行 | if 链 / 大括号换行 |

---

## 下一步

+ 读 `MyLitCustomInspector.cs`——它本身就是"用 C# 控制材质 / 关键字 / Pass 开关"的实战参考
+ 回到 `Part6.md` 第八节的"项目未采用项"清单，决定哪些要真正落地

> 文档完。如有疑问，翻 `Docs/` 下的其他文档。
