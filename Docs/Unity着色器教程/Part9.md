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
