# 与 C# 交互：用代码编写 Unity URP 着色器（第 9 部分）

> 原文作者：NedMakesGames  
> 原文链接：https://nedmakesgames.medium.com/  
> 翻译时间：2026-08-14

---

## 目录

- [引言](#引言)
- [从 C# 设置材质属性](#从-c-设置材质属性)
  - [基本属性设置](#基本属性设置)
  - [属性 ID 优化](#属性-id-优化)
- [全局着色器变量](#全局着色器变量)
  - [Shader.SetGlobalFloat/Color/Vector](#shadersetglobalfloatcolorvector)
  - [全局纹理](#全局纹理)
- [材质属性块（Material Property Block）](#材质属性块material-property-block)
  - [何时使用](#何时使用)
  - [与 SRP Batcher 的关系](#与-srp-batcher-的关系)
- [渲染纹理交互](#渲染纹理交互)
  - [创建渲染纹理](#创建渲染纹理)
  - [着色器中的交互贴图](#着色器中的交互贴图)
  - [从 C# 写入渲染纹理](#从-c-写入渲染纹理)
- [程序化颜色](#程序化颜色)
  - [基于时间的颜色](#基于时间的颜色)
  - [基于状态的颜色](#基于状态的颜色)
  - [HP 条与 UI 着色器](#hp-条与-ui-着色器)
- [运行时材质实例化](#运行时材质实例化)
  - [Material 克隆](#material-克隆)
  - [共享材质 vs 实例材质](#共享材质-vs-实例材质)
- [事件驱动的着色器效果](#事件驱动的着色器效果)
  - [受伤闪白](#受伤闪白)
  - [元素状态切换](#元素状态切换)
- [调试与性能](#调试与性能)
  - [属性设置性能](#属性设置性能)
  - [常见陷阱](#常见陷阱)
- [完整示例：交互式涟漪系统](#完整示例交互式涟漪系统)
- [总结](#总结)
- [全系列总结](#全系列总结)
- [致谢](#致谢)

---

## 引言

大家好，我是 Ned，一名游戏开发者！这是本系列的**最后一章**了！在上一章中，我们为 MyLit 添加了顶点动画——风中的草、飘动的旗帜、点击涟漪和踩踏效果。

今天，我们将闭合这个循环——从 C# 脚本与着色器交互。着色器不应该是孤立的；它们需要响应游戏状态。生命值降低时变红？着火时发出橙光？被点击时产生涟漪？全部可以用 C# + 着色器实现。

这是系列的终章，让我们精彩收尾！

在继续之前，我想感谢所有赞助者让这个系列成为可能。让我们开始吧！

---

## 从 C# 设置材质属性

### 基本属性设置

每个着色器属性都可以通过 C# 的 `Material` 类来设置。这是最基础的桥梁：

```csharp
using UnityEngine;

public class MaterialController : MonoBehaviour
{
    public Material targetMaterial;
    
    void Start()
    {
        // 设置浮点数（如平滑度、金属度）
        targetMaterial.SetFloat("_Smoothness", 0.8f);
        
        // 设置颜色（如反照率色调）
        targetMaterial.SetColor("_ColorTint", Color.red);
        
        // 设置纹理
        Texture newTexture = Resources.Load<Texture>("MyTexture");
        targetMaterial.SetTexture("_ColorMap", newTexture);
        
        // 设置向量
        targetMaterial.SetVector("_WindDirection", new Vector4(1, 0, 0, 0));
        
        // 设置整数（如枚举值）
        targetMaterial.SetInt("_SurfaceType", 1);
    }
}
```

### 属性 ID 优化

每次调用 `SetFloat("_Smoothness", value)` 时，Unity 内部都要通过字符串查找属性 ID。在 `Update` 中每帧调用会很慢！

**解决方案：** 使用 `Shader.PropertyToID` 缓存属性 ID：

```csharp
public class OptimizedMaterialController : MonoBehaviour
{
    public Material targetMaterial;
    
    // 缓存属性 ID
    private static readonly int SmoothnessID = Shader.PropertyToID("_Smoothness");
    private static readonly int ColorTintID = Shader.PropertyToID("_ColorTint");
    private static readonly int WindDirectionID = Shader.PropertyToID("_WindDirection");
    private static readonly int EmissionTintID = Shader.PropertyToID("_EmissionTint");
    
    void Update()
    {
        // 使用 ID 而非字符串 —— 快得多！
        targetMaterial.SetFloat(SmoothnessID, Mathf.PingPong(Time.time * 0.5f, 1.0f));
        targetMaterial.SetColor(ColorTintID, Color.Lerp(Color.white, Color.red, Time.time % 2));
        targetMaterial.SetVector(WindDirectionID, new Vector4(
            Mathf.Sin(Time.time * 0.3f), 0, 
            Mathf.Cos(Time.time * 0.3f), 0
        ));
    }
}
```

> **性能差异：** 字符串查找每帧约 0.1-0.5μs，ID 查找约 0.01μs。对于 1000 个物体，差别是 500μs vs 10μs——50 倍！

---

## 全局着色器变量

有时你想让**所有**材质同时响应同一个值——比如全局时间缩放、全局风方向，或全局伤害脉冲。

### Shader.SetGlobalFloat/Color/Vector

```csharp
public class GlobalWindController : MonoBehaviour
{
    private static readonly int GlobalWindID = Shader.PropertyToID("_GlobalWindDirection");
    private static readonly int GlobalTimeScaleID = Shader.PropertyToID("_GlobalTimeScale");
    private static readonly int GlobalDamagePulseID = Shader.PropertyToID("_GlobalDamagePulse");
    
    [Range(0, 2)]
    public float timeScale = 1.0f;
    
    void Update()
    {
        // 全局风方向 —— 所有使用此属性的着色器都会响应
        Vector3 windDir = new Vector3(
            Mathf.Sin(Time.time * 0.2f), 0, 
            Mathf.Cos(Time.time * 0.2f)
        ).normalized;
        
        Shader.SetGlobalVector(GlobalWindID, windDir);
        Shader.SetGlobalFloat(GlobalTimeScaleID, timeScale);
    }
    
    // 从任何地方调用此函数
    public static void TriggerDamagePulse(float intensity)
    {
        Shader.SetGlobalFloat(GlobalDamagePulseID, intensity);
    }
}
```

在着色器中声明全局属性（无需在 Properties 块中）：

```hlsl
// 在 MyLitCommon.hlsl 中
CBUFFER_START(UnityPerMaterial)
    // ... 现有属性 ...
CBUFFER_END

// 全局变量（不在 CBUFFER 中！）
float3 _GlobalWindDirection;
float  _GlobalTimeScale;
float  _GlobalDamagePulse;
```

在顶点或片段函数中使用：

```hlsl
// 在 Vertex 函数中
float3 windDir = normalize(_GlobalWindDirection) * _WindStrength;
float windWave = sin((_Time.y * _GlobalTimeScale) + positionWS.x * 0.1);
positionWS.xz += windDir.xz * windWave * heightFactor;
```

### 全局纹理

你也可以用 C# 设置全局纹理：

```csharp
// 设置全局纹理
Shader.SetGlobalTexture("_GlobalNoiseTexture", noiseTexture);
Shader.SetGlobalTexture("_GlobalDamageMask", damageMaskRT);
```

```hlsl
// 在 HLSL 中
TEXTURE2D(_GlobalNoiseTexture);
SAMPLER(sampler_GlobalNoiseTexture);

// 采样
half4 noise = SAMPLE_TEXTURE2D(_GlobalNoiseTexture, sampler_GlobalNoiseTexture, uv);
```

> **用例：** 全局噪声纹理（所有材质共享一张噪声）、伤害遮罩、天气效果遮罩。

---

## 材质属性块（Material Property Block）

**Material Property Block** 是性能最优的方案——它允许你为**同一个材质**的不同渲染器设置不同属性，而无需创建材质实例。

### 何时使用

| 场景 | 推荐方案 | 原因 |
|------|----------|------|
| 场景中 5 个不同颜色的物体 | `Material.SetColor` | 数量少，简单直接 |
| 1000 棵草，每棵不同颜色 | `MaterialPropertyBlock` | 零实例开销 |
| 全局风/时间 | `Shader.SetGlobal*` | 所有材质共享 |
| 运行时动态创建材质 | `Material.Instantiate` | 需要完全独立的材质 |

### 实现

```csharp
public class GrassColorController : MonoBehaviour
{
    private static readonly int InstanceColorID = Shader.PropertyToID("_InstanceColor");
    private static readonly int InstanceHeightID = Shader.PropertyToID("_InstanceHeight");
    private static readonly int InstanceSwayID = Shader.PropertyToID("_InstanceSwaySpeed");
    
    private MeshRenderer meshRenderer;
    private MaterialPropertyBlock propertyBlock;
    
    void Awake()
    {
        meshRenderer = GetComponent<MeshRenderer>();
        propertyBlock = new MaterialPropertyBlock();
    }
    
    void Start()
    {
        // 给每棵草一个随机颜色
        Color grassColor = Color.Lerp(
            new Color(0.2f, 0.6f, 0.1f),  // 深绿
            new Color(0.5f, 0.9f, 0.2f),  // 浅绿
            Random.value
        );
        
        // 随机高度和摆动速度
        float height = Random.Range(0.8f, 1.5f);
        float swaySpeed = Random.Range(0.5f, 2.0f);
        
        // 设置到 PropertyBlock
        propertyBlock.SetColor(InstanceColorID, grassColor);
        propertyBlock.SetFloat(InstanceHeightID, height);
        propertyBlock.SetFloat(InstanceSwayID, swaySpeed);
        
        // 应用到渲染器
        meshRenderer.SetPropertyBlock(propertyBlock);
    }
}
```

在着色器中：

```hlsl
// 属性声明
UNITY_INSTANCING_BUFFER_START(Props)
    UNITY_DEFINE_INSTANCED_PROP(float4, _InstanceColor)
    UNITY_DEFINE_INSTANCED_PROP(float, _InstanceHeight)
    UNITY_DEFINE_INSTANCED_PROP(float, _InstanceSwaySpeed)
UNITY_INSTANCING_BUFFER_END(Props)

// 在片段函数中使用
float4 instanceColor = UNITY_ACCESS_INSTANCED_PROP(Props, _InstanceColor);
float instanceHeight = UNITY_ACCESS_INSTANCED_PROP(Props, _InstanceHeight);
float instanceSway = UNITY_ACCESS_INSTANCED_PROP(Props, _InstanceSwaySpeed);

half3 finalColor = surfaceData.albedo * instanceColor.rgb * instanceHeight;
```

### 与 SRP Batcher 的关系

> ⚠️ **重要：** `MaterialPropertyBlock` 会**破坏** SRP Batcher 兼容性！
> 
> 如果你需要 SRP Batcher **和** 逐实例属性，解决方案是 `GPU Instancing`（如第 6 章所述）。`MaterialPropertyBlock` 仅用于非实例化渲染。

**决策树：**
```
需要逐实例属性？
├── 是 → 使用 GPU Instancing（SRP Batcher 兼容）
│       或 MaterialPropertyBlock（更灵活，但破坏 SRP Batcher）
└── 否 → 直接用 Material.Set*（SRP Batcher 兼容）
```

---

## 渲染纹理交互

**渲染纹理（Render Texture）** 允许你在着色器中创建动态纹理——玩家可以在表面上"绘画"、踩踏草、或留下痕迹。

### 创建渲染纹理

```csharp
public class InteractionTextureCreator : MonoBehaviour
{
    public int textureSize = 512;
    public RenderTexture interactionRT;
    
    void Awake()
    {
        // 创建渲染纹理
        interactionRT = new RenderTexture(textureSize, textureSize, 0, RenderTextureFormat.R8);
        interactionRT.filterMode = FilterMode.Bilinear;
        interactionRT.wrapMode = TextureWrapMode.Clamp;
        interactionRT.Create();
        
        // 初始化为黑色（无交互）
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

### 着色器中的交互贴图

```hlsl
// 属性
TEXTURE2D(_InteractionMap);
SAMPLER(sampler_InteractionMap);
float4 _InteractionMap_ST;

// 在 Vertex 函数中计算交互 UV
// 假设世界 XZ 映射到 UV [0,1]
float2 worldXZ = positionWS.xz;
float2 interactionUV = (worldXZ - _InteractionMapBoundsMin.xz) 
                    / (_InteractionMapBoundsMax.xz - _InteractionMapBoundsMin.xz);

// 传递给片段
output.interactionUV = saturate(interactionUV);
```

```hlsl
// 在 Fragment 函数中
half interaction = SAMPLE_TEXTURE2D(_InteractionMap, sampler_InteractionMap, input.interactionUV).r;

// 使用交互值影响外观
// 例如：被踩踏的草变平
float bendAmount = interaction * _MaxBendAngle;
positionWS.xz += bendDirection * bendAmount;
```

### 从 C# 写入渲染纹理

```csharp
public class GrassPainter : MonoBehaviour
{
    public RenderTexture interactionRT;
    private static readonly int InteractionMapID = Shader.PropertyToID("_InteractionMap");
    private static readonly int PaintPositionID = Shader.PropertyToID("_PaintPosition");
    private static readonly int PaintRadiusID = Shader.PropertyToID("_PaintRadius");
    private static readonly int PaintStrengthID = Shader.PropertyToID("_PaintStrength");
    
    public Material paintMaterial;  // 一个简单的"画笔"材质
    
    void Update()
    {
        if (Input.GetMouseButton(0))
        {
            Ray ray = Camera.main.ScreenPointToRay(Input.mousePosition);
            if (Physics.Raycast(ray, out RaycastHit hit))
            {
                // 方法 1：用 Graphics.DrawTexture 绘制
                PaintAtPosition(hit.point, 0.5f, 1.0f);
                
                // 方法 2：通过材质属性发送位置
                Shader.SetGlobalVector(PaintPositionID, hit.point);
                Shader.SetGlobalFloat(PaintRadiusID, 0.5f);
                Shader.SetGlobalFloat(PaintStrengthID, 1.0f);
            }
        }
    }
    
    void PaintAtPosition(Vector3 worldPos, float radius, float strength)
    {
        // 将世界坐标转换为纹理 UV
        Vector3 localPos = transform.InverseTransformPoint(worldPos);
        float u = (localPos.x / boundsSize.x) + 0.5f;
        float v = (localPos.z / boundsSize.z) + 0.5f;
        
        // 用画笔材质绘制到渲染纹理
        RenderTexture.active = interactionRT;
        GL.PushMatrix();
        GL.LoadPixelMatrix(0, interactionRT.width, interactionRT.height, 0);
        
        // 绘制一个圆形渐变
        // ... 简化的绘制逻辑 ...
        
        GL.PopMatrix();
        RenderTexture.active = null;
    }
}
```

> **完整方案：** 使用 `CommandBuffer` 和 `Graphics.Blit` 来绘制更复杂的画笔形状（如柔和边缘的圆、噪点图案）。

---

## 程序化颜色

### 基于时间的颜色

```csharp
public class TimeBasedColor : MonoBehaviour
{
    public Material targetMaterial;
    public Gradient dayNightGradient;
    public Light sunLight;
    
    private static readonly int SkyTintID = Shader.PropertyToID("_SkyTint");
    private static readonly int AmbientIntensityID = Shader.PropertyToID("_AmbientIntensity");
    
    void Update()
    {
        // 根据太阳高度计算时间
        float sunHeight = sunLight.transform.forward.y;  // -1 到 1
        float time01 = Mathf.InverseLerp(-0.2f, 0.8f, sunHeight);
        
        // 采样渐变
        Color skyColor = dayNightGradient.Evaluate(time01);
        
        targetMaterial.SetColor(SkyTintID, skyColor);
        targetMaterial.SetFloat(AmbientIntensityID, time01);
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
    
    private static readonly int HealthColorID = Shader.PropertyToID("_HealthColor");
    private static readonly int DamageFlashID = Shader.PropertyToID("_DamageFlash");
    private static readonly int DissolveAmountID = Shader.PropertyToID("_DissolveAmount");
    
    void Start()
    {
        currentHealth = maxHealth;
    }
    
    public void TakeDamage(float amount)
    {
        currentHealth = Mathf.Max(0, currentHealth - amount);
        
        // 根据生命值计算颜色：绿 → 黄 → 红
        float healthPercent = currentHealth / maxHealth;
        Color healthColor = Color.Lerp(Color.red, Color.green, healthPercent);
        
        // 添加伤害闪白
        float flashAmount = 1.0f;
        
        targetMaterial.SetColor(HealthColorID, healthColor);
        targetMaterial.SetFloat(DamageFlashID, flashAmount);
        
        // 死亡时溶解
        if (currentHealth <= 0)
        {
            StartCoroutine(DissolveCoroutine());
        }
    }
    
    IEnumerator DissolveCoroutine()
    {
        float dissolve = 0;
        while (dissolve < 1)
        {
            dissolve += Time.deltaTime * 0.5f;
            targetMaterial.SetFloat(DissolveAmountID, dissolve);
            yield return null;
        }
    }
}
```

着色器端：

```hlsl
// 属性
float4 _HealthColor;
float  _DamageFlash;
float  _DissolveAmount;

// 在 Fragment 中
// 伤害闪白
half3 baseColor = surfaceData.albedo * _HealthColor.rgb;
half3 flashColor = half3(1, 1, 1) * _DamageFlash;
half3 finalColor = lerp(baseColor, flashColor, _DamageFlash * 0.5);

// 溶解效果
half dissolveThreshold = _DissolveAmount;
half noise = SAMPLE_TEXTURE2D(_NoiseTexture, sampler_NoiseTexture, input.uv).r;
clip(noise - dissolveThreshold);  // 低于阈值的像素被丢弃

// 溶解边缘发光
half edgeWidth = 0.05;
half edgeGlow = smoothstep(dissolveThreshold, dissolveThreshold + edgeWidth, noise)
              - smoothstep(dissolveThreshold + edgeWidth, dissolveThreshold + edgeWidth * 2, noise);
finalColor += half3(1, 0.3, 0) * edgeGlow * 2;
```

### HP 条与 UI 着色器

```csharp
public class HPBarShader : MonoBehaviour
{
    public Material hpBarMaterial;
    public float currentHP = 100f;
    public float maxHP = 100f;
    
    private static readonly int HPPercentID = Shader.PropertyToID("_HPPercent");
    private static readonly int BarColorID = Shader.PropertyToID("_BarColor");
    private static readonly int FlashAmountID = Shader.PropertyToID("_FlashAmount");
    
    void Update()
    {
        float hpPercent = currentHP / maxHP;
        hpBarMaterial.SetFloat(HPPercentID, hpPercent);
        
        // 低血量时闪烁红色
        Color barColor = hpPercent > 0.3f ? Color.green : Color.Lerp(Color.red, Color.yellow, Mathf.Sin(Time.time * 8));
        hpBarMaterial.SetColor(BarColorID, barColor);
    }
}
```

```hlsl
// UI 着色器片段
float _HPPercent;
float4 _BarColor;
float _FlashAmount;

half4 Fragment(Interpolators input) : SV_TARGET
{
    // UV.x 从左到右 = 0 到 1
    // 当 UV.x > HPPercent 时，显示空槽
    float fillMask = step(input.uv.x, _HPPercent);
    
    // 空槽颜色（暗灰）
    half3 emptyColor = half3(0.2, 0.2, 0.2);
    
    // 填充颜色
    half3 fillColor = _BarColor.rgb;
    
    // 边缘高光（在填充边界处加亮）
    float edge = smoothstep(_HPPercent - 0.02, _HPPercent, input.uv.x)
                - smoothstep(_HPPercent, _HPPercent + 0.02, input.uv.x);
    fillColor += edge * 0.5;
    
    half3 finalColor = lerp(emptyColor, fillColor, fillMask);
    
    // 闪烁
    finalColor = lerp(finalColor, half3(1, 1, 1), _FlashAmount * 0.3);
    
    return half4(finalColor, 1);
}
```

---

## 运行时材质实例化

### Material 克隆

```csharp
public class RuntimeMaterialCreator : MonoBehaviour
{
    public Material baseMaterial;
    public MeshRenderer targetRenderer;
    
    void Start()
    {
        // 创建材质实例
        Material instance = new Material(baseMaterial);
        
        // 修改实例
        instance.SetColor("_ColorTint", Random.ColorHSV());
        instance.SetFloat("_Smoothness", Random.Range(0.1f, 0.9f));
        instance.SetFloat("_Metallic", Random.value > 0.5f ? 1 : 0);
        
        // 赋给渲染器
        targetRenderer.material = instance;
    }
    
    void OnDestroy()
    {
        // 销毁实例释放内存
        if (targetRenderer.material != null && targetRenderer.material != baseMaterial)
        {
            Destroy(targetRenderer.material);
        }
    }
}
```

### 共享材质 vs 实例材质

```csharp
// ❌ 错误：修改共享材质（影响所有使用此材质的物体！）
renderer.sharedMaterial.SetColor("_ColorTint", Color.red);

// ✅ 正确：修改实例材质（仅影响这个渲染器）
renderer.material.SetColor("_ColorTint", Color.red);

// ✅ 更高效：使用 MaterialPropertyBlock（不产生新材质）
var block = new MaterialPropertyBlock();
block.SetColor("_ColorTint", Color.red);
renderer.SetPropertyBlock(block);
```

> **注意：** `renderer.material` 会**自动克隆**材质（如果尚未克隆）。`renderer.sharedMaterial` 返回原始共享材质。

---

## 事件驱动的着色器效果

### 受伤闪白

```csharp
public class DamageFlashEffect : MonoBehaviour
{
    public Material targetMaterial;
    public float flashDuration = 0.15f;
    public Color flashColor = Color.white;
    
    private static readonly int FlashColorID = Shader.PropertyToID("_FlashColor");
    private static readonly int FlashAmountID = Shader.PropertyToID("_FlashAmount");
    
    private Coroutine flashCoroutine;
    
    public void OnDamaged()
    {
        if (flashCoroutine != null)
            StopCoroutine(flashCoroutine);
        
        flashCoroutine = StartCoroutine(FlashCoroutine());
    }
    
    IEnumerator FlashCoroutine()
    {
        targetMaterial.SetColor(FlashColorID, flashColor);
        
        float elapsed = 0;
        while (elapsed < flashDuration)
        {
            elapsed += Time.deltaTime;
            float t = elapsed / flashDuration;
            
            // 快速淡出
            float amount = Mathf.Pow(1 - t, 3);  // 立方衰减
            targetMaterial.SetFloat(FlashAmountID, amount);
            
            yield return null;
        }
        
        targetMaterial.SetFloat(FlashAmountID, 0);
    }
}
```

着色器端：

```hlsl
float4 _FlashColor;
float  _FlashAmount;

// 在 Fragment 中
half3 flash = _FlashColor.rgb * _FlashAmount;
finalColor = lerp(finalColor, finalColor + flash, _FlashAmount);
```

### 元素状态切换

```csharp
public class ElementalMaterialSwitcher : MonoBehaviour
{
    public enum ElementType { Fire, Ice, Lightning, Poison }
    
    public Material targetMaterial;
    public Texture fireTexture;
    public Texture iceTexture;
    public Texture lightningTexture;
    public Texture poisonTexture;
    
    private static readonly int ElementTextureID = Shader.PropertyToID("_ElementTexture");
    private static readonly int ElementColorID = Shader.PropertyToID("_ElementColor");
    private static readonly int ElementGlowID = Shader.PropertyToID("_ElementGlow");
    private static readonly int TransitionAmountID = Shader.PropertyToID("_TransitionAmount");
    
    private ElementType currentElement;
    private Coroutine transitionCoroutine;
    
    public void SwitchElement(ElementType newElement)
    {
        if (currentElement == newElement) return;
        
        // 设置新元素属性
        Texture elementTex = GetElementTexture(newElement);
        Color elementCol = GetElementColor(newElement);
        
        targetMaterial.SetTexture(ElementTextureID, elementTex);
        targetMaterial.SetColor(ElementColorID, elementCol);
        
        // 触发过渡动画
        if (transitionCoroutine != null)
            StopCoroutine(transitionCoroutine);
        transitionCoroutine = StartCoroutine(TransitionCoroutine());
        
        currentElement = newElement;
    }
    
    IEnumerator TransitionCoroutine()
    {
        // 先熄灭旧元素
        float t = 0;
        while (t < 0.3f)
        {
            t += Time.deltaTime;
            targetMaterial.SetFloat(TransitionAmountID, 1 - t / 0.3f);
            yield return null;
        }
        
        // 再点亮新元素
        t = 0;
        while (t < 0.5f)
        {
            t += Time.deltaTime;
            targetMaterial.SetFloat(TransitionAmountID, t / 0.5f);
            yield return null;
        }
        
        targetMaterial.SetFloat(TransitionAmountID, 1);
    }
    
    Texture GetElementTexture(ElementType element)
    {
        switch (element)
        {
            case ElementType.Fire: return fireTexture;
            case ElementType.Ice: return iceTexture;
            case ElementType.Lightning: return lightningTexture;
            case ElementType.Poison: return poisonTexture;
            default: return null;
        }
    }
    
    Color GetElementColor(ElementType element)
    {
        switch (element)
        {
            case ElementType.Fire: return new Color(1, 0.3f, 0);
            case ElementType.Ice: return new Color(0.3f, 0.7f, 1);
            case ElementType.Lightning: return new Color(0.8f, 0.8f, 1);
            case ElementType.Poison: return new Color(0.5f, 0.8f, 0.2f);
            default: return Color.white;
        }
    }
}
```

---

## 调试与性能

### 属性设置性能

按性能从快到慢排列：

| 方法 | 每帧 1000 物体耗时 | 内存开销 | 适用场景 |
|------|---------------------|----------|----------|
| `Shader.SetGlobal*` | ~0.01ms | 无 | 全局参数 |
| `MaterialPropertyBlock` | ~0.05ms | 低（每渲染器） | 逐实例差异化 |
| `Material.Set*` (ID) | ~0.1ms | 中（每材质实例） | 少量物体 |
| `Material.Set*` (字符串) | ~5ms | 中 | ❌ 避免每帧调用 |
| `new Material()` 每帧 | ~10ms + GC | 高 | ❌ 绝对不要 |

### 常见陷阱

**1. 字符串属性名**
```csharp
// ❌ 每帧字符串查找
material.SetFloat("_Smoothness", value);

// ✅ 缓存 ID
private static readonly int SmoothnessID = Shader.PropertyToID("_Smoothness");
material.SetFloat(SmoothnessID, value);
```

**2. 每帧创建材质**
```csharp
// ❌ 每帧 GC 分配
void Update() 
{ 
    var m = new Material(baseMat); 
    renderer.material = m; 
}

// ✅ 创建一次，复用
private Material instance;
void Awake() 
{ 
    instance = new Material(baseMat); 
    renderer.material = instance; 
}
void Update() 
{ 
    instance.SetFloat(id, value); 
}
```

**3. 修改 sharedMaterial**
```csharp
// ❌ 影响所有使用该材质的物体
renderer.sharedMaterial.SetColor(id, color);

// ✅ 只影响这个渲染器
renderer.material.SetColor(id, color);
```

**4. 忘记销毁材质**
```csharp
// ❌ 内存泄漏
void OnDestroy() { }  // 忘记清理

// ✅ 正确清理
void OnDestroy()
{
    if (renderer.material != baseMaterial)
        Destroy(renderer.material);
}
```

---

## 完整示例：交互式涟漪系统

让我们把所有内容组合起来，创建一个完整的交互式涟漪系统：

```csharp
using UnityEngine;
using UnityEngine.Rendering;

public class RippleSystem : MonoBehaviour
{
    [Header("Ripple Settings")]
    public Material targetMaterial;
    public RenderTexture rippleRT;
    public Material paintMaterial;
    public float rippleRadius = 0.5f;
    public float rippleStrength = 1.0f;
    public float rippleSpeed = 3.0f;
    public float rippleDamping = 0.95f;
    public int textureSize = 512;
    
    [Header("References")]
    public Transform groundPlane;
    
    private static readonly int RippleRTID = Shader.PropertyToID("_RippleTexture");
    private static readonly int RippleOriginID = Shader.PropertyToID("_RippleOrigin");
    private static readonly int RippleTimeID = Shader.PropertyToID("_RippleTime");
    private static readonly int RippleParamsID = Shader.PropertyToID("_RippleParams");
    
    private CommandBuffer paintCommandBuffer;
    private float currentRippleTime;
    private Vector3 lastRipplePosition;
    private bool hasActiveRipple;
    
    void Awake()
    {
        // 创建渲染纹理
        rippleRT = new RenderTexture(textureSize, textureSize, 0, RenderTextureFormat.RGFloat);
        rippleRT.filterMode = FilterMode.Bilinear;
        rippleRT.wrapMode = TextureWrapMode.Clamp;
        rippleRT.Create();
        
        // 初始化
        RenderTexture.active = rippleRT;
        GL.Clear(true, true, new Color(0, 0, 0, 0));
        RenderTexture.active = null;
        
        // 设置全局纹理
        Shader.SetGlobalTexture(RippleRTID, rippleRT);
        
        // 创建命令缓冲区
        paintCommandBuffer = new CommandBuffer { name = "RipplePaint" };
    }
    
    void Update()
    {
        // 检测点击
        if (Input.GetMouseButtonDown(0))
        {
            Ray ray = Camera.main.ScreenPointToRay(Input.mousePosition);
            if (Physics.Raycast(ray, out RaycastHit hit))
            {
                CreateRipple(hit.point);
            }
        }
        
        // 持续更新涟漪时间
        if (hasActiveRipple)
        {
            currentRippleTime += Time.deltaTime * rippleSpeed;
            
            // 衰减
            rippleStrength *= rippleDamping;
            
            if (rippleStrength < 0.01f)
            {
                hasActiveRipple = false;
                rippleStrength = 0;
            }
            
            // 更新着色器
            Shader.SetGlobalVector(RippleOriginID, lastRipplePosition);
            Shader.SetGlobalFloat(RippleTimeID, currentRippleTime);
            Shader.SetGlobalVector(RippleParamsID, 
                new Vector4(rippleRadius, rippleStrength, rippleSpeed, 0));
        }
    }
    
    void CreateRipple(Vector3 worldPosition)
    {
        lastRipplePosition = worldPosition;
        currentRippleTime = 0;
        rippleStrength = 1.0f;
        hasActiveRipple = true;
        
        // 将世界坐标转换为平面 UV
        Vector3 localPos = groundPlane.InverseTransformPoint(worldPosition);
        float u = (localPos.x / groundPlane.localScale.x) * 0.5f + 0.5f;
        float v = (localPos.z / groundPlane.localScale.z) * 0.5f + 0.5f;
        
        // 用命令缓冲区绘制涟漪到渲染纹理
        paintCommandBuffer.Clear();
        paintCommandBuffer.SetRenderTarget(rippleRT);
        
        // 在指定 UV 位置绘制一个圆形
        // ... 实际实现使用 Graphics.DrawTexture 或全屏 quad ...
        
        Graphics.ExecuteCommandBuffer(paintCommandBuffer);
    }
    
    void OnDestroy()
    {
        if (rippleRT != null)
            rippleRT.Release();
        
        if (paintCommandBuffer != null)
            paintCommandBuffer.Dispose();
    }
}
```

着色器端（添加到 MyLitCommon.hlsl）：

```hlsl
// 全局涟漪参数
float3 _RippleOrigin;
float  _RippleTime;
float4 _RippleParams;  // xy = radius, strength, speed, _

// 涟漪计算函数
float3 CalculateRipple(float3 positionWS)
{
    float distToRipple = distance(positionWS.xz, _RippleOrigin.xz);
    float rippleRadius = _RippleParams.x;
    float rippleStrength = _RippleParams.y;
    float rippleSpeed = _RippleParams.z;
    
    // 涟漪从原点向外传播
    float rippleWave = sin(distToRipple * 20 - _RippleTime * 10);
    
    // 高斯衰减
    float rippleFalloff = exp(-distToRipple * distToRipple / (rippleRadius * rippleRadius));
    
    // 只在波前附近有位移
    float waveFront = smoothstep(0, 0.1, abs(distToRipple - _RippleTime * rippleSpeed * 0.5));
    waveFront = 1 - waveFront;
    
    float3 displacement = float3(0, rippleWave * rippleFalloff * rippleStrength * waveFront, 0);
    return displacement;
}
```

在顶点函数中使用：

```hlsl
// 在 Vertex 函数中
float3 positionWS = TransformObjectToWorld(positionOS);

// 应用涟漪位移
float3 rippleOffset = CalculateRipple(positionWS);
positionWS += rippleOffset;

// 重新计算裁剪空间
output.positionCS = TransformWorldToHClip(positionWS);
```

---

## 总结

### C# ↔ Shader 通信速查表

| 方法 | C# 端 | 着色器端 | 作用域 |
|------|--------|----------|--------|
| **Material.SetFloat** | `mat.SetFloat(id, val)` | `float _MyFloat;` | 单个材质实例 |
| **Material.SetColor** | `mat.SetColor(id, col)` | `float4 _MyColor;` | 单个材质实例 |
| **Material.SetTexture** | `mat.SetTexture(id, tex)` | `TEXTURE2D(_MyTex)` | 单个材质实例 |
| **Material.SetVector** | `mat.SetVector(id, vec)` | `float4 _MyVector;` | 单个材质实例 |
| **Material.SetInt** | `mat.SetInt(id, val)` | `int _MyInt;` 或 `float` | 单个材质实例 |
| **Shader.SetGlobalFloat** | `Shader.SetGlobalFloat(id, val)` | `float _GlobalVal;` | 全局所有着色器 |
| **Shader.SetGlobalColor** | `Shader.SetGlobalColor(id, col)` | `float4 _GlobalCol;` | 全局所有着色器 |
| **Shader.SetGlobalTexture** | `Shader.SetGlobalTexture(id, tex)` | `TEXTURE2D(_GlobalTex)` | 全局所有着色器 |
| **MaterialPropertyBlock** | `block.SetFloat(id, val)` | `UNITY_ACCESS_INSTANCED_PROP()` | 逐渲染器 |
| **GPU Instancing** | `Graphics.DrawMeshInstanced()` | `UNITY_DEFINE_INSTANCED_PROP()` | 逐实例（批量） |

### 属性 ID 命名约定

```csharp
// ✅ 推荐：静态只读 + 描述性名称
private static readonly int SmoothnessID = Shader.PropertyToID("_Smoothness");
private static readonly int MainColorID = Shader.PropertyToID("_ColorTint");
private static readonly int WindDirectionID = Shader.PropertyToID("_WindDirection");

// ❌ 避免：硬编码字符串、无意义名称
material.SetFloat("s", 0.5f);
material.SetColor("_c", Color.red);
```

---

## 全系列总结

恭喜！你已经完成了全部九章教程。让我们回顾一下我们构建的内容：

### 系列旅程地图

```
第1章 · 图形管线基础
├── ShaderLab 结构（SubShader、Pass、Tags）
├── HLSL 基础（顶点/片段函数、结构体）
├── 坐标空间（对象→世界→裁剪）
├── 光栅化器与插值
└── 纹理采样（颜色贴图、UV、Tiling/Offset）

第2章 · 光照与阴影
├── Blinn-Phong 光照模型
├── 法线向量与世界空间变换
├── 镜面高光与平滑度
├── 阴影映射算法
├── 着色器变体（multi_compile）
├── Shadow Caster Pass
└── 阴影偏差与阴影粉刺

第3章 · 透明度
├── Alpha 混合（Blend 命令）
├── ZWrite 与渲染队列
├── 自定义材质检视器
├── Alpha 裁剪（Clip/Discard）
├── 着色器特性（shader_feature）
├── 通用 HLSL 文件
└── 双面渲染与双面法线

第4章 · 基于物理的渲染
├── UniversalFragmentPBR
├── 调试视图与渲染调试器
├── 法线贴图与切线空间
├── 金属/高光工作流
├── 平滑度与金属度遮罩
├── 透明混合模式（Additive/Multiply/Premultiplied）
├── 自发光
├── 视差遮挡映射
├── 清漆效果
└── 纹理通道打包

第5章 · 高级光照
├── 附加光源循环（LIGHT_LOOP）
├── Forward+ 渲染路径
├── 点光源与聚光灯
├── 烘焙光照与光照贴图
├── Meta Pass
├── 光照探针
├── 遮挡遮罩
├── 反射探针与菲涅尔
├── 光照 Cookie
└── 雾效

第6章 · 高级 URP 特性
├── DepthOnly Pass
├── DepthNormals Pass
├── 屏幕空间环境光遮蔽（SSAO）
├── SRP Batcher 兼容性
├── GPU 实例化
├── 单通道 VR 渲染
└── 渲染器特性

第7章 · 自定义光照模型
├── 绕过 UniversalFragmentPBR
├── Lambert / Half-Lambert
├── 卡通渲染（Cel / Toon）
├── Ramp 贴图
├── 布料光照（各向异性）
├── 皮肤光照（次表面散射）
├── 头发光照（Kajiya-Kay）
├── 植物叶片光照
└── 调试可视化

第8章 · 顶点动画
├── 正弦波与多频率叠加
├── 方向性风与噪声风
├── 旗帜动画
├── 顶点颜色遮罩
├── 骨骼式顶点动画
├── 交互式顶点位移
└── 运动矢量 Pass

第9章 · 与 C# 交互（本章）
├── 材质属性设置
├── 属性 ID 优化
├── 全局着色器变量
├── 材质属性块
├── 渲染纹理交互
├── 程序化颜色
├── 运行时材质实例化
└── 事件驱动效果
```

### MyLit 着色器特性清单

| 特性 | 支持 |
|------|:------:|
| 基础颜色 + 纹理 | ✅ |
| Blinn-Phong 光照 | ✅ |
| PBR（金属/高光工作流） | ✅ |
| 法线贴图 | ✅ |
| 视差遮挡映射 | ✅ |
| 清漆效果 | ✅ |
| Alpha 混合 + 裁剪 | ✅ |
| 主光源 + 附加光源 | ✅ |
| 烘焙光照（Lightmap） | ✅ |
| 光照探针 | ✅ |
| 阴影（主光 + 附加光） | ✅ |
| 光照 Cookie | ✅ |
| 雾效 | ✅ |
| 自发光 | ✅ |
| 遮挡遮罩 | ✅ |
| 反射探针 | ✅ |
| 卡通渲染 | ✅ |
| 布料/皮肤/头发/植物光照 | ✅ |
| 顶点动画（风/旗帜/涟漪） | ✅ |
| 运动矢量 | ✅ |
| SRP Batcher 兼容 | ✅ |
| GPU Instancing | ✅ |
| 深度预通道 + SSAO | ✅ |
| C# 交互（全局/局部属性） | ✅ |

**你已经拥有了一个功能完备、生产级、高度优化的 URP 着色器。**

---

## 致谢

最后，我想感谢所有赞助者的支持，特别感谢本系列全程的次世代赞助人！没有你们，这个系列不可能完成。

这个系列对我意义非凡。我从 2014 年开始编写着色器，一路上学到了太多东西——有太多优秀的资源帮助了我。我希望这个系列也能成为你旅程中的一块垫脚石。

**特别感谢：**
- **Crubidoobidoo** —— 全程支持，从第 1 章到第 9 章
- 所有 Patreon 赞助人 —— 你们让这一切成为可能
- **Unity Technologies** —— 为 URP 源码开放点赞
- **Cyanilux** —— 出色的 URP 代码模板和社区贡献

### 接下来去哪里？

- 📖 阅读 Unity 的 [URP Shader 文档](https://docs.unity3d.com/Manual/universal-render-pipeline.html)
- 🎮 研究 [URP 3D Sample](https://assetstore.unity.com/packages/essentials/tutorial-projects/urp-3d-sample-267693) 项目
- 🔬 探索 [Cyanilux 的 URP 代码模板](https://github.com/Cyanilux/URP_ShaderCodeTemplates)
- 🎥 尝试将 MyLit 移植到 HDRP 或 Built-in 管线
- 🧪 实验！修改光照模型、添加新特性、打破规则

**最重要的是——去做游戏吧！**

---

> **全系列最终版本：** 完成所有九章后的完整着色器文件，请参考 GitHub 仓库。
>
> 如果你喜欢本系列，请考虑[关注原作者](https://nedmakesgames.medium.com/)。
>
> 如果你想在 Unity 项目中下载所有着色器，请考虑[加入 Patreon](https://www.patreon.com/NedMakesGames)。
>
> 如果你有任何问题，欢迎在评论区留言或通过社交媒体联系原作者。
>
> ©️ Timothy Ned Atton 2026. 保留所有权利。GitHub Gist 中出现的代码均以 MIT 许可证分发，除非另有说明。

---

*感谢阅读！这是 NedMakesGames 的 URP 着色器系列的终章。愿你的像素永远明亮，你的帧率永远流畅。* ✨
