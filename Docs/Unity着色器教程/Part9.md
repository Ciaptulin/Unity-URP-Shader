# Part 9 · 用 C# 驱动着色器

> **本节在整份教程中的位置**
> 这是本系列的最后一部分。前八节都在写 HLSL，本节换个方向：**从 C# 控制着色器**——改属性、切关键字、传全局参数、做动画、响应游戏事件。
>
> 用标签区分：
>
> - 🟩 **【Shader】** — 为了能被 C# 控制，着色器侧要做什么（属性声明、关键字声明、CBUFFER）。
> - 🟦 **【C#】** — 脚本侧写法。
> - ⚠️ **纠错** — 旧版教程在 MPB 与材质实例化这两块有明确错误，本节逐条纠正。
>
> **版本基准：Unity 2023.2.20f1 / URP 16.0.6。**
> 涉及项目文件：`Assets/Shader/MyLit/MyLit.shader`、`MyLitCommon.hlsl`、`Assets/Editor/MyLitCustomInspector.cs`。

---

## 0. 这一节到底要解决什么问题

**问题**：着色器里的值有两类——

| 类型 | 例子 | 谁来写 |
|---|---|---|
| 静态/美术设定 | albedo 贴图、金属度 | 材质 Inspector |
| 动态/游戏逻辑 | 血量对应的红色、受击闪烁、溶解进度、全局风 | **C# 脚本** |

**一句话概括本节**：
> 三种手段覆盖所有需求：**材质属性**（个体差异）、**关键字**（分支/变体）、**全局属性**（全场统一）。选错手段会导致要么失效，要么打断合批。

---

## 1. 🟩➕🟦 材质属性

### 1.1 最小示例

```csharp
public class ShaderController : MonoBehaviour
{
    public Material material;

    void Start()
    {
        material.SetColor("_ColorTint", Color.red);
        material.SetFloat("_Smoothness", 0.8f);
        material.SetTexture("_ColorMap", someTexture);
    }
}
```

前提（🟩）：HLSL 里必须**同名**声明，且属性要放进 `UnityPerMaterial` CBUFFER（SRP Batcher 要求，见 Part 1~3）：

```hlsl
CBUFFER_START(UnityPerMaterial)
    float4 _ColorTint;
    float  _Smoothness;
CBUFFER_END
```

### 1.2 `material` vs `sharedMaterial`

| | `renderer.material` | `renderer.sharedMaterial` |
|---|---|---|
| 是否创建副本 | **首次访问时创建**一个实例并缓存 | 不创建，直接返回工程里的材质资产 |
| 影响范围 | 只影响这个 Renderer | 影响**所有**用这个材质的物体 |
| 释放 | 需要手动 `Destroy`（实例不在 Assets 里，切场景不会被自动回收） | 不需要 |

> ⚠️ **纠正旧版说法**：旧版写"每次访问 `renderer.material` 都会创建新实例"——不准确。Unity 会在**第一次**访问时创建实例并缓存在 Renderer 上，后续访问返回同一个。真正的代价是：
> ① 实例常驻内存且不会随场景卸载自动释放（**需要在 `OnDestroy` 里 `Destroy`**）；
> ② **打断 SRP Batcher / GPU Instancing**（每个物体一份材质数据）。

```csharp
private Renderer _renderer;
private Material _instance;

void Awake()
{
    _renderer = GetComponent<Renderer>();
    _instance = _renderer.material;   // 只在这里实例化一次，之后复用引用
}

void OnDestroy()
{
    if (_instance != null) Destroy(_instance);
}
```

### 1.3 属性 ID 缓存

字符串查找有开销。热路径用 `Shader.PropertyToID`：

```csharp
private static readonly int ColorTintID = Shader.PropertyToID("_ColorTint");
private static readonly int SmoothnessID = Shader.PropertyToID("_Smoothness");

void Update()
{
    material.SetFloat(SmoothnessID, Mathf.PingPong(Time.time, 1f));
}
```

`static readonly` 是安全的：`PropertyToID` 的返回值在整个进程生命周期内稳定。

### 1.4 Color 与 Vector 的区别（容易踩）

- 属性在 ShaderLab 里声明为 **`Color`**：`SetColor` 会参与**色彩空间转换**（线性工作流下传入的 gamma 值会转到线性）。想要"原样传数值"，改用 `SetVector`。
- 项目里的 `_ColorTint` 是 `Color`，`_Cutoff`、`_Smoothness` 是 `Range`/`Float` —— 传数据时按声明类型调用对应的 Set 方法即可。

### 1.5 数组与批量

```csharp
material.SetFloatArray("_Weights", new[] { 0.5f, 0.8f, 1.0f });
```

HLSL 侧：

```hlsl
float _Weights[3];     // 注意：数组不能放进 UnityPerMaterial CBUFFER 之外随意声明
```

> 💡 CBUFFER 里的数组/结构体在跨平台对齐上容易出问题，且 SRP Batcher 要求 `UnityPerMaterial` 的布局固定。批量数据（>4 个值）更稳妥的做法是 `SetGlobalVector` 或 `ComputeBuffer`（HLSL 侧对应 `StructuredBuffer`）。

以下是完整实现代码（`ShaderPropertyController.cs`）：

```csharp
using UnityEngine;

/// <summary>
/// Part 9：最基础的材质属性控制。
/// 演示：属性 ID 缓存、material 实例的正确取得与释放、避免每帧无意义写入。
/// </summary>
public class ShaderPropertyController : MonoBehaviour
{
    [Header("Target")]
    public Renderer targetRenderer;

    [Header("Animate")]
    public bool animateSmoothness = true;
    public float speed = 1f;

    // 字符串查找有开销，热路径一律先转 ID 并缓存
    private static readonly int SmoothnessID = Shader.PropertyToID("_Smoothness");
    private static readonly int ColorTintID  = Shader.PropertyToID("_ColorTint");

    private Material m_MaterialInstance;
    private float m_LastWritten = float.MinValue;

    private void Awake()
    {
        if (targetRenderer == null)
            targetRenderer = GetComponent<Renderer>();

        // renderer.material 会在首次访问时创建一份实例（之后复用同一份）
        // 只在 Awake 里取一次并缓存引用，别放进 Update
        m_MaterialInstance = targetRenderer.material;
    }

    private void Update()
    {
        if (!animateSmoothness)
            return;

        float value = Mathf.PingPong(Time.time * speed, 1f);

        // 只在真的变化时才写，省掉无意义的 CPU→GPU 传输
        if (Mathf.Abs(value - m_LastWritten) < 0.001f)
            return;

        m_MaterialInstance.SetFloat(SmoothnessID, value);
        m_LastWritten = value;
    }

    // 材质实例是运行时 new 出来的，不在 Assets 里，切场景不会自动回收，必须手动释放
    private void OnDestroy()
    {
        if (m_MaterialInstance != null)
            Destroy(m_MaterialInstance);
    }

    [ContextMenu("改成红色（用 material 实例，只影响自己）")]
    private void SetRed()
    {
        m_MaterialInstance.SetColor(ColorTintID, Color.red);
    }

    [ContextMenu("打印所有属性名")]
    private void PrintProperties()
    {
        Shader shader = m_MaterialInstance.shader;
        for (int i = 0; i < shader.GetPropertyCount(); i++)
        {
            Debug.Log($"[{i}] {shader.GetPropertyName(i)} : {shader.GetPropertyType(i)}");
        }
    }
}
```

---

## 2. 🟦 MaterialPropertyBlock

### 2.1 它解决什么

想让 1000 个相同材质的物体有不同颜色，用 `renderer.material` 会产生 1000 份材质副本。**MPB 把属性覆盖存在 Renderer 上**，材质本身只有一份。

```csharp
private Renderer _renderer;
private MaterialPropertyBlock _block;
private static readonly int ColorTintID = Shader.PropertyToID("_ColorTint");

void Awake()
{
    _renderer = GetComponent<Renderer>();
    _block = new MaterialPropertyBlock();
}

void Update()
{
    _renderer.GetPropertyBlock(_block);                 // 先取（保留已有覆盖）
    _block.SetColor(ColorTintID, Color.HSVToRGB(Time.time * 0.1f % 1f, 1, 1));
    _renderer.SetPropertyBlock(_block);
}
```

取消覆盖：`_renderer.SetPropertyBlock(null)`。

### 2.2 ⚠️ 纠正：MPB **不兼容 SRP Batcher**

Unity 官方文档中 `MaterialPropertyBlock` 的说明明确写着：**"请注意，这与 SRP Batcher 不兼容。"**

旧版教程说"使用 MPB 的物体仍然可以被 GPU Instancing 和 SRP Batcher 合并"——**后半句是错的**。

| | 材质实例 | MPB |
|---|---|---|
| 内存 | 一份完整材质副本 | 仅存覆盖的属性 |
| **SRP Batcher** | ❌ 打断（不同材质实例） | ❌ **同样打断**（Unity 官方说明） |
| **GPU Instancing** | ❌ 打断 | ✅ 支持（前提：属性声明在实例化缓冲里，见下） |
| 关键字 | ✅ 支持 | ❌ 不支持 |
| 纹理 ST（缩放偏移） | ✅ | ❌ |

**结论**：
- 物体数量大、需要个体属性差异 → **MPB + GPU Instancing**；
- 物体数量少、只需要一两个不同 → 材质实例也没关系；
- 想保住 SRP Batcher → **只有一条路：不改任何个体属性**（同一材质 + 相同关键字）。

### 2.3 MPB + GPU Instancing 的前提（🟩）

要让每个实例的属性真正进入实例化缓冲，着色器里必须这样声明：

```hlsl
#pragma multi_compile_instancing

UNITY_INSTANCING_BUFFER_START(UnityPerMaterial)
    UNITY_DEFINE_INSTANCED_PROP(float4, _ColorTint)
UNITY_INSTANCING_BUFFER_END(UnityPerMaterial)
```

配合 `UNITY_SETUP_INSTANCE_ID(input)` / `UNITY_ACCESS_INSTANCED_PROP`。

> 📌 **项目现状**：`MyLit` 目前用的是普通 CBUFFER（为 SRP Batcher 优化），**没有**实例化缓冲声明。这意味着当前的定位是 **SRP Batcher 优先**。如果某天需要"几千个同材质不同色的物体"，就要把那条属性改成实例化版本并接受放弃 SRP Batcher——**两者二选一，要按场景决定**。

以下是完整实现代码（`MaterialPropertyBlockController.cs`）：

```csharp
using UnityEngine;
using System.Collections.Generic;

/// <summary>
/// Part 9：MaterialPropertyBlock（MPB）。
/// 适合"大量物体共用一个材质、但每个个体参数不同"的场景。
///
/// ⚠️ 两点必须知道：
///   1. MPB 与 SRP Batcher 不兼容（Unity 官方说明），但支持 GPU Instancing；
///   2. MPB 不能切关键字、不能改纹理的 Tiling/Offset。
/// </summary>
public class MaterialPropertyBlockController : MonoBehaviour
{
    [Header("Setup")]
    public int instanceCount = 200;
    public GameObject prefab;
    public Vector3 areaSize = new Vector3(20f, 0f, 20f);

    private static readonly int ColorTintID = Shader.PropertyToID("_ColorTint");

    private readonly List<Renderer> m_Renderers = new List<Renderer>();
    private readonly List<MaterialPropertyBlock> m_Blocks = new List<MaterialPropertyBlock>();

    private void Start()
    {
        if (prefab == null)
            return;

        for (int i = 0; i < instanceCount; i++)
        {
            Vector3 pos = new Vector3(
                Random.Range(-areaSize.x * 0.5f, areaSize.x * 0.5f),
                0f,
                Random.Range(-areaSize.z * 0.5f, areaSize.z * 0.5f));

            GameObject go  = Instantiate(prefab, pos, Quaternion.identity, transform);
            Renderer rend  = go.GetComponent<Renderer>();
            if (rend == null)
                continue;

            // 一个物体一个 block，之后复用它，别每帧 new
            var block = new MaterialPropertyBlock();
            block.SetColor(ColorTintID, Random.ColorHSV(0f, 1f, 0.6f, 1f, 0.6f, 1f));
            rend.SetPropertyBlock(block);

            m_Renderers.Add(rend);
            m_Blocks.Add(block);
        }
    }

    private void Update()
    {
        for (int i = 0; i < m_Renderers.Count; i++)
        {
            float hue = (i * 0.01f + Time.time * 0.05f) % 1f;

            // 先取回来再改，避免覆盖掉 block 里已有的其它属性
            m_Renderers[i].GetPropertyBlock(m_Blocks[i]);
            m_Blocks[i].SetColor(ColorTintID, Color.HSVToRGB(hue, 0.8f, 1f));
            m_Renderers[i].SetPropertyBlock(m_Blocks[i]);
        }
    }

    [ContextMenu("清除所有 MPB 覆盖")]
    private void ClearBlocks()
    {
        foreach (var rend in m_Renderers)
            rend.SetPropertyBlock(null);   // 传 null 即恢复材质默认值
    }
}
```

---

## 3. 🟦 着色器关键字

### 3.1 材质级关键字

```csharp
material.EnableKeyword("_ALPHA_CUTOUT");
material.DisableKeyword("_ALPHA_CUTOUT");
bool on = material.IsKeywordEnabled("_ALPHA_CUTOUT");
```

项目里可用的关键字（🟩，来自 `MyLit.shader`）：

| 关键字 | 含义 | 声明方式 |
|---|---|---|
| `_NORMALMAP` | 启用法线贴图 | `shader_feature_local_fragment` |
| `_SPECULAR_SETUP` | 高光工作流 | `shader_feature_local_fragment` |
| `_ROUGHNESS_SETUP` | 粗糙度贴图模式 | `shader_feature_local_fragment` |
| `_CLEARCOATMAP` | 清漆 | `shader_feature_local` |
| `_ALPHA_CUTOUT` | 透明裁剪 | `shader_feature_local` |
| `_DOUBLE_SIDED_NORMALS` | 双面法线 | `shader_feature_local` |
| `_ALPHAPREMULTIPLY_ON` | 预乘 alpha | `shader_feature_local_fragment` |
| `_DEBUG_BAKED_GI` | 输出烘焙 GI 调试 | `multi_compile` |

> ⚠️ **`shader_feature` 的变体剥离问题**：用 `shader_feature` 声明的变体，**只有被场景中某个材质实际用到时才会打进包**。如果你打算在运行时靠 C# 打开某个 `shader_feature` 关键字，而没有任何材质预先用过它 → **运行时该变体不存在，切换无效**（表现是"改了但没变化"）。
> 解决办法三选一：
> ① 让一个材质预先启用并保存；
> ② 加入 `ShaderVariantCollection`；
> ③ 把关键字改成 `multi_compile`（代价：变体变多）。

### 3.2 新版关键字 API（推荐）

Unity 2021.2+ 引入了结构体形式，避免字符串查找与"关键字不存在"问题：

```csharp
using UnityEngine.Rendering;

private LocalKeyword _normalMapKeyword;

void Awake()
{
    _normalMapKeyword = new LocalKeyword(material.shader.keywordSpace, "_NORMALMAP");
}

void Toggle()
{
    material.SetKeyword(_normalMapKeyword, true);
}
```

全局关键字：

```csharp
private static GlobalKeyword _globalKeyword = GlobalKeyword.Create("_MY_GLOBAL_FEATURE");
Shader.EnableKeyword(_globalKeyword);
```

字符串版本 `Shader.EnableKeyword("_NAME")` 在 2023.2 仍可用（不存在时会自动创建 `GlobalKeyword`），但**推荐缓存结构体版本**。

### 3.3 全局 vs 局部

| | 设置方式 | 作用域 | 优先级 |
|---|---|---|---|
| 局部 | `material.EnableKeyword` / `SetKeyword` | 单个材质 | 高 |
| 全局 | `Shader.EnableKeyword` | 所有材质 | 低 |

URP 自己用的那些（`_ADDITIONAL_LIGHTS`、`_LIGHT_COOKIES`、`_MAIN_LIGHT_SHADOWS` …）是引擎在全局设置的，你只需要在 Shader 里声明 `multi_compile`。

### 3.4 变体预热

关键字首次切换到未编译变体时会卡顿。用 `ShaderVariantCollection` 预热：

```csharp
public ShaderVariantCollection variantCollection;

IEnumerator Start()
{
    yield return null;
    variantCollection.WarmUp();     // 可能耗时较长，建议在加载界面做
}
```

以下是完整实现代码（`ShaderKeywordController.cs`）：

```csharp
using UnityEngine;
using UnityEngine.Rendering;

/// <summary>
/// Part 9：着色器关键字控制（材质级 + 全局级）。
/// 演示 2021.2+ 推荐的 LocalKeyword / GlobalKeyword 结构体写法（避免字符串查找）。
/// </summary>
public class ShaderKeywordController : MonoBehaviour
{
    [Header("Target")]
    public Material material;

    [Header("Material Keyword")]
    public string keywordName = "_CUSTOM_BRDF";

    [Header("Global Keyword")]
    public string globalKeywordName = "_MY_GLOBAL_FEATURE";

    private LocalKeyword m_LocalKeyword;
    private GlobalKeyword m_GlobalKeyword;
    private bool m_Valid;

    private void Awake()
    {
        if (material == null)
        {
            var rend = GetComponent<Renderer>();
            if (rend != null)
                material = rend.material;
        }

        if (material == null)
            return;

        // 关键字必须在 shader 的 keywordSpace 里存在，否则这个构造会给出无效关键字
        m_LocalKeyword = new LocalKeyword(material.shader.keywordSpace, keywordName);
        m_Valid = m_LocalKeyword.isValid;

        if (!m_Valid)
            Debug.LogWarning($"关键字 [{keywordName}] 不在 shader 的 keywordSpace 里，切换不会生效", this);

        m_GlobalKeyword = GlobalKeyword.Create(globalKeywordName);
    }

    [ContextMenu("切换材质关键字")]
    private void ToggleMaterialKeyword()
    {
        if (!m_Valid)
            return;

        bool current = material.IsKeywordEnabled(m_LocalKeyword);
        material.SetKeyword(m_LocalKeyword, !current);
        Debug.Log($"[{keywordName}] -> {!current}");
    }

    [ContextMenu("打开全局关键字")]
    private void EnableGlobal()   => Shader.EnableKeyword(m_GlobalKeyword);

    [ContextMenu("关闭全局关键字")]
    private void DisableGlobal()  => Shader.DisableKeyword(m_GlobalKeyword);

    [ContextMenu("打印当前启用的关键字")]
    private void PrintEnabledKeywords()
    {
        foreach (var kw in material.enabledKeywords)
            Debug.Log($"启用中：{kw.name}");
    }

    private void OnDestroy()
    {
        if (material != null)
            Destroy(material);
    }
}
```

---

## 4. 🟦 全局着色器属性

适合"全场一致"的数据：时间、天气、风向、雾参数。

```csharp
Shader.SetGlobalFloat("_GlobalTime", Time.time);
Shader.SetGlobalVector("_WindData", new Vector4(dir.x, dir.y, dir.z, strength));
Shader.SetGlobalColor("_FogColor", fogColor);
Shader.SetGlobalTexture("_GlobalNoise", noiseTexture);
```

🟩 Shader 侧直接声明同名变量，**不要**放进 `UnityPerMaterial`：

```hlsl
float4 _WindData;
float  _GlobalTime;
```

> ⚠️ 全局属性命名一定要加前缀（`_MyGame_XXX`）。它对**所有**着色器可见，重名会互相覆盖，而且不报错。

以下是完整实现代码（`GlobalPropertiesController.cs`）：

```csharp
using UnityEngine;

/// <summary>
/// Part 9：全局着色器属性。一次设置，全场所有材质都能读到。
/// 适合时间、天气、雾、风这类"全场一致"的数据。
///
/// Shader 侧直接声明同名变量即可，不要放进 UnityPerMaterial CBUFFER。
/// </summary>
public class GlobalPropertiesController : MonoBehaviour
{
    [Header("Time")]
    public bool useUnscaledTime = true;

    [Header("Custom")]
    public Color globalTint = Color.white;
    public float globalIntensity = 1f;

    // 全局属性名冲突不会报错，所以一定要加项目前缀
    private static readonly int GlobalTimeID      = Shader.PropertyToID("_MyGame_GlobalTime");
    private static readonly int GlobalTintID      = Shader.PropertyToID("_MyGame_GlobalTint");
    private static readonly int GlobalIntensityID = Shader.PropertyToID("_MyGame_GlobalIntensity");

    private float m_Time;

    private void Update()
    {
        // Time.time 受 timeScale 影响（暂停就停）；unscaledTime 不会
        m_Time = useUnscaledTime ? Time.unscaledTime : Time.time;

        Shader.SetGlobalFloat(GlobalTimeID, m_Time);
        Shader.SetGlobalColor(GlobalTintID, globalTint);
        Shader.SetGlobalFloat(GlobalIntensityID, globalIntensity);
    }

    private void OnDisable()
    {
        Shader.SetGlobalFloat(GlobalIntensityID, 1f);
    }
}
```

---

## 5. 🟦 着色器动画

### 5.1 协程 + 曲线（最灵活）

```csharp
public class FlashEffect : MonoBehaviour
{
    [SerializeField] private AnimationCurve curve = AnimationCurve.EaseInOut(0, 0, 1, 1);
    [SerializeField] private float duration = 0.25f;

    private static readonly int FlashID = Shader.PropertyToID("_FlashIntensity");
    private Material _mat;
    private Coroutine _routine;

    void Awake() => _mat = GetComponent<Renderer>().material;

    public void Play()
    {
        if (_routine != null) StopCoroutine(_routine);
        _routine = StartCoroutine(Flash());
    }

    IEnumerator Flash()
    {
        for (float t = 0; t < duration; t += Time.deltaTime)
        {
            _mat.SetFloat(FlashID, curve.Evaluate(t / duration));
            yield return null;
        }
        _mat.SetFloat(FlashID, 0f);
        _routine = null;
    }

    void OnDestroy() { if (_mat != null) Destroy(_mat); }
}
```

### 5.2 三种时间

| 需求 | 用什么 |
|---|---|
| 受暂停/慢动作影响 | `Time.time`（传给 Shader 的 `_Time.y` 就是这个） |
| 暂停时仍要动（UI、加载动画） | `Time.unscaledTime`（自己 `SetGlobalFloat`） |
| 与物理同步 | `Time.fixedTime`，在 `FixedUpdate` 里更新 |

### 5.3 免代码方案

- **Animation 窗口**：选中带 Renderer 的物体 → Add Property → Renderer → Material.xxx，直接录关键帧。
- **DOTween / LeanTween**：`DOTween.To(() => mat.GetFloat(id), x => mat.SetFloat(id, x), 1, 0.5f)`。
- **Timeline**：需要与其他轨道对齐时用。

以下是完整实现代码（`HitFlashController.cs`）：

```csharp
using UnityEngine;
using System.Collections;

/// <summary>
/// Part 9：受击闪烁。协程 + AnimationCurve，最常用的事件驱动写法。
/// </summary>
public class HitFlashController : MonoBehaviour
{
    [Header("Settings")]
    public Color flashColor = Color.red;
    public float flashDuration = 0.25f;

    [Tooltip("横轴 0→1 表示一次闪烁的进度，纵轴是强度")]
    public AnimationCurve flashCurve = AnimationCurve.EaseInOut(0f, 1f, 1f, 0f);

    private static readonly int ColorTintID = Shader.PropertyToID("_ColorTint");

    private Material m_Material;
    private Coroutine m_Routine;

    private void Awake()
    {
        var rend = GetComponent<Renderer>();
        if (rend != null)
            m_Material = rend.material;
    }

    // 外部（比如伤害系统）调用这个
    public void TakeDamage()
    {
        if (m_Material == null)
            return;

        if (m_Routine != null)
            StopCoroutine(m_Routine);

        m_Routine = StartCoroutine(Flash());
    }

    private IEnumerator Flash()
    {
        for (float t = 0f; t < flashDuration; t += Time.deltaTime)
        {
            float intensity = flashCurve.Evaluate(t / flashDuration);

            // 从原色（白）插值到闪光色，强度由曲线控制
            Color target = Color.Lerp(Color.white, flashColor, intensity);
            m_Material.SetColor(ColorTintID, target);

            yield return null;
        }

        m_Material.SetColor(ColorTintID, Color.white);
        m_Routine = null;
    }

    private void OnDestroy()
    {
        if (m_Material != null)
            Destroy(m_Material);
    }
}
```

---

## 6. 🟩➕🟦 事件驱动效果：溶解

以"溶解"为例走一遍完整链路。

### 6.1 Shader 侧

```hlsl
// MyLitCommon.hlsl
float _DissolveAmount;      // 0 = 完整, 1 = 完全消失
float _EdgeWidth;
float3 _EdgeColor;
TEXTURE2D(_DissolveMap); SAMPLER(sampler_DissolveMap);

void ApplyDissolve(inout float4 color, float2 uv, float alpha)
{
    float noise = SAMPLE_TEXTURE2D(_DissolveMap, sampler_DissolveMap, uv).r;
    float threshold = _DissolveAmount * (1.0 + _EdgeWidth) - _EdgeWidth;
    clip(noise - threshold);                                  // 关键：直接用 clip

    float edge = 1.0 - smoothstep(threshold, threshold + _EdgeWidth, noise);
    color.rgb += _EdgeColor * edge * 2.0;                     // 边缘发光（配 Bloom 更好看）
}
```

> 💡 项目里已经有 `_ALPHA_CUTOUT` + `TestAlphaClip()` 这套机制（见 `MyLitCommon.hlsl`）。溶解可以复用它：把噪声图的结果写进 `colorSample.a`，再交给 `clip(a - _Cutoff)`，只需要在 C# 里推 `_Cutoff` 一个值即可，不用改 Shader。

### 6.2 C# 侧

```csharp
public class DissolveEffect : MonoBehaviour
{
    [SerializeField] private float duration = 1.5f;
    public event System.Action OnComplete;

    private static readonly int CutoffID = Shader.PropertyToID("_Cutoff");
    private Material _mat;

    void Awake() => _mat = GetComponent<Renderer>().material;

    public void Play() => StartCoroutine(Dissolve());

    IEnumerator Dissolve()
    {
        for (float t = 0; t < duration; t += Time.deltaTime)
        {
            _mat.SetFloat(CutoffID, t / duration);
            yield return null;
        }
        _mat.SetFloat(CutoffID, 1f);
        OnComplete?.Invoke();
        gameObject.SetActive(false);
    }

    void OnDestroy() { if (_mat != null) Destroy(_mat); }
}
```

> ⚠️ 要看到溶解效果，材质必须已经启用了 `_ALPHA_CUTOUT`（否则 `TestAlphaClip` 里没有 `clip`）。参见 3.1 的变体剥离问题。

以下是完整实现代码（`DissolveController.cs`）：

```csharp
using UnityEngine;
using System.Collections;
using UnityEngine.Events;

/// <summary>
/// Part 9：溶解效果。
/// 复用 MyLit 已有的 _ALPHA_CUTOUT 机制：只需把 _Cutoff 从 0 推到 1，
/// TestAlphaClip 里的 clip(a - _Cutoff) 就会把噪声值低于阈值的像素丢掉。
/// 前提：材质必须已经启用 _ALPHA_CUTOUT 关键字（脚本会自动开）。
/// </summary>
public class DissolveController : MonoBehaviour
{
    [Header("Settings")]
    public float duration = 1.5f;
    public bool enableCutoutAutomatically = true;

    public UnityEvent onDissolveComplete;

    private static readonly int CutoffID = Shader.PropertyToID("_Cutoff");

    private Material m_Material;
    private Coroutine m_Routine;

    private void Awake()
    {
        var rend = GetComponent<Renderer>();
        if (rend == null)
            return;

        m_Material = rend.material;

        if (enableCutoutAutomatically)
            m_Material.EnableKeyword("_ALPHA_CUTOUT");
    }

    [ContextMenu("播放溶解")]
    public void Play()
    {
        if (m_Material == null)
            return;

        if (m_Routine != null)
            StopCoroutine(m_Routine);

        m_Routine = StartCoroutine(Dissolve());
    }

    public void Reset()
    {
        if (m_Material == null)
            return;

        if (m_Routine != null)
        {
            StopCoroutine(m_Routine);
            m_Routine = null;
        }

        m_Material.SetFloat(CutoffID, 0f);
    }

    private IEnumerator Dissolve()
    {
        for (float t = 0f; t < duration; t += Time.deltaTime)
        {
            m_Material.SetFloat(CutoffID, t / duration);
            yield return null;
        }

        m_Material.SetFloat(CutoffID, 1f);
        m_Routine = null;
        onDissolveComplete?.Invoke();
    }

    private void OnDestroy()
    {
        if (m_Material != null)
            Destroy(m_Material);
    }
}
```

---

## 7. 性能

| 规则 | 说明 |
|---|---|
| **缓存属性 ID** | `static readonly int` |
| **只在变化时写** | `if (Mathf.Abs(v - last) > 0.001f) SetFloat(...)` |
| **别在 Update 里访问 `renderer.material`** | 缓存引用；否则每次访问都走一次属性 getter |
| **避免每帧新建对象** | `MaterialPropertyBlock` 复用同一个实例 |
| **全局属性优先于遍历材质** | 风、时间这类数据一次设置全场生效 |
| **关键字只在状态切换时改** | 每帧 `EnableKeyword` 不会更贵，但会让代码难以追踪状态 |
| **注意变体数量** | 每多一个 `multi_compile` 关键字，变体数翻倍，编译时间与包体同步增长 |

---

## 8. 调试

```csharp
[ContextMenu("打印所有属性")]
void PrintProperties()
{
    var shader = GetComponent<Renderer>().sharedMaterial.shader;
    for (int i = 0; i < shader.GetPropertyCount(); i++)
        Debug.Log($"{shader.GetPropertyName(i)} : {shader.GetPropertyType(i)}");
}
```

| 现象 | 排查 |
|---|---|
| `SetFloat` 改了没反应 | 名字拼错（`HasProperty` 检查）；HLSL 里没声明；属性被放进了错误的 CBUFFER |
| 运行时 `EnableKeyword` 无效 | 变体被剥离（见 3.1） |
| 物体没有进 SRP Batcher | Rendering Debugger 会给出原因（常见：用了 MPB、材质实例、CBUFFER 不一致） |
| 全局属性被覆盖 | 命名冲突，加前缀 |
| 材质内存一直涨 | `renderer.material` 创建的实例没 `Destroy` |

工具：

- **Frame Debugger**：看每个 DrawCall 的关键字组合，判断合批为何断开。
- **Rendering Debugger → Rendering → SRP Batcher** 面板：直接列出不兼容原因。

---

## 10. 🟦 全局风场控制器（Part 8 配套）

以下是完整实现代码（`WindController.cs`），与 Part 8 的风动系统配套：

```csharp
using UnityEngine;

/// <summary>
/// Part 8：全局风场。用 Shader.SetGlobal* 一次设置，全场所有开了 _WIND_ENABLED 的材质都能读到。
/// 用法：挂到场景里任意一个空物体上，调参数即可。
/// </summary>
public class WindController : MonoBehaviour
{
    [Header("Wind")]
    public Vector3 windDirection = new Vector3(1f, 0f, 0f);
    [Range(0f, 10f)] public float windSpeed = 3f;
    [Range(0f, 2f)]  public float windStrength = 0.5f;
    [Range(0f, 5f)]  public float turbulence = 1f;

    [Header("Fallback")]
    [Tooltip("模型没有顶点色权重时，用这个高度按 Y 轴比例兜底")]
    public float windHeight = 2f;

    // 缓存 ID：字符串查找有开销，热路径一律用 ID
    private static readonly int WindDataID       = Shader.PropertyToID("_WindData");
    private static readonly int WindSpeedID      = Shader.PropertyToID("_WindSpeed");
    private static readonly int WindTurbulenceID = Shader.PropertyToID("_WindTurbulence");
    private static readonly int WindHeightID     = Shader.PropertyToID("_WindHeight");

    private void Update()
    {
        Vector3 dir = windDirection.normalized * windStrength;

        // xyz = 方向 * 强度，w = 整体强度（Shader 里最后乘在偏移上）
        Shader.SetGlobalVector(WindDataID, new Vector4(dir.x, dir.y, dir.z, windStrength));
        Shader.SetGlobalFloat(WindSpeedID, windSpeed);
        Shader.SetGlobalFloat(WindTurbulenceID, turbulence);
        Shader.SetGlobalFloat(WindHeightID, windHeight);
    }

    // 物体被禁用时把风停掉，避免残留上一次的数值
    private void OnDisable()
    {
        Shader.SetGlobalVector(WindDataID, Vector4.zero);
    }

    // 顶点动画发生在 GPU 上，CPU 端的包围盒还是原始大小，
    // 位移较大时物体会在还没出画的时候被剔除。把包围盒放大一点即可。
    [ContextMenu("放大自身及子物体的包围盒")]
    private void ExpandBoundsOfChildren()
    {
        foreach (var filter in GetComponentsInChildren<MeshFilter>())
        {
            Mesh mesh = filter.sharedMesh;
            if (mesh == null)
                continue;

            mesh.bounds = new Bounds(mesh.bounds.center, mesh.bounds.size * 1.5f);
            Debug.Log($"[{filter.name}] bounds 已放大", filter);
        }
    }
}
```

---

## 9. 全系列回顾

```
Part 1  图形管线        渲染管线 / ShaderLab / HLSL / 顶点与片元函数
Part 2  光照与阴影      Blinn-Phong / 法线 / 阴影映射 / 着色器变体 / ShadowCaster
Part 3  透明度          Alpha 混合与裁剪 / 渲染队列 / 自定义 Inspector / 双面渲染
Part 4  PBR 与表面      UniversalFragmentPBR / 法线贴图 / 金属与高光工作流 / 自发光 / 视差 / 清漆
Part 5  光照系统接入    附加光源 / 烘焙 GI / 遮挡贴图 / Cookie / DepthNormals / MotionVectors
Part 6  屏幕空间与扩展  SSAO / SSR 现状 / 后处理 Volume / 自定义 Renderer Feature / 调试
Part 7  自定义 BRDF     D·F·V / 能量守恒 / 卡通 / SSS / 各向异性
Part 8  顶点动画        波形 / Gerstner / 风动 / 位移与 FlowMap / VAT / 多 Pass 同步
Part 9  C# 交互         材质属性 / MPB / 关键字 / 全局属性 / 动画 / 事件效果
```

**贯穿全系列的三条经验**：

1. **先搞清楚"这活归谁"**：URP 已经实现的（GI、反射、阴影、BRDF）不要重写，你的工作是**喂对数据、开对开关**。
2. **所有"不报错但不对"的问题**，八成出在：关键字拼写、`positionWS`、`LightMode` 标签、Pass 缺失。
3. **版本差异是最大的陷阱**。抄任何教程前，先对着 `Library/PackageCache/com.unity.render-pipelines.universal@16.0.6` 核一遍函数名与关键字名——本项目已经因为这个问题踩过附加光源阴影的坑。

---

## 结语

到这里，你已经从"写一个白色球体的着色器"走到了"一个能接入 URP 完整光照系统、可被 C# 驱动、可扩展管线、可自定义 BRDF 的 PBR 着色器"。

接下来值得投入的方向：

- **渲染管线定制**：把 Part 6 的 Renderer Feature 写熟，再往 Render Graph（Unity 6）迁移；
- **Shader Graph 与 HLSL 混合**：用 Shader Graph 出原型，用本系列的 HLSL 做性能关键路径；
- **Compute Shader**：粒子、剔除、后处理的另一条路；
- **读 URP 源码**：`Library/PackageCache` 里那份就是最好的教材，本系列所有的"正确答案"都是从那里查出来的。
