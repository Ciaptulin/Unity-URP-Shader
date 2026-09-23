# 11 · URP 里做水面

> 目标：把参考项目的水面（Pond）移植到 URP。
> 参考项目：`Shaders/Pond.shader` / `Pond.hlsl` / `PondHeader.hlsl`

---

## 11.1 水面的组成

| 效果 | 参考项目做法 | URP 做法 |
|---|---|---|
| 深浅颜色 | 按水深 lerp | 相同 |
| 波浪 | Gerstner 波顶点位移 | 相同 |
| 法线 | 两层滚动法线贴图 | 相同 |
| 边缘泡沫 | 按水深 | 相同 |
| 闪烁 | 高频法线 + 高光 | 相同 |
| 折射 | 采样场景颜色 + 扰动 | `_CameraOpaqueTexture` |
| 反射 | SSR | URP SSR Feature（第 5 章）|

**核心算法都与管线无关，可整体移植。**

---

## 11.2 移植关键：数据源替换

| 参考项目 | URP |
|---|---|
| `_gLightingRT0`（场景颜色）| `_CameraOpaqueTexture` |
| `_gDepthRT` | `_CameraDepthTexture` |
| `GetLighting`（自定义）| `UniversalFragmentPBR` |
| `_SSREFLECTION` 关键字 | URP SSR Feature 控制 |

---

## 11.3 Shader 骨架

```hlsl
Shader "Custom/Pond"
{
    Properties
    {
        [Header(Base Color)]
        _ShallowColor ("Shallow", Color) = (0.44, 0.95, 0.36, 1)
        _DeepColor ("Deep", Color) = (0.0, 0.05, 0.19, 1)
        _DepthDensity ("Depth Density", Range(0,1)) = 0.5

        [Header(Waves)]
        _WaveNormalMap ("Wave Normal", 2D) = "bump" {}
        _WaveNormalSpeed ("Wave Speed", Float) = 0.05
        _WaveNormalScale ("Wave Scale", Float) = 20
        _Wave0Direction ("Wave0 Dir", Range(0,0.5)) = 0.25
        _Wave0Amplitude ("Wave0 Amp", Float) = 1
        _Wave0Length ("Wave0 Len", Float) = 10
        _Wave0Speed ("Wave0 Speed", Float) = 0.25
        _Wave1Direction ("Wave1 Dir", Range(0.5,1)) = 0.75
        _Wave1Amplitude ("Wave1 Amp", Float) = 1
        _Wave1Length ("Wave1 Len", Float) = 10
        _Wave1Speed ("Wave1 Speed", Float) = 0.25

        [Header(Foam)]
        _EdgeFoamColor ("Edge Foam Color", Color) = (1,1,1,1)
        _EdgeFoamDepth ("Edge Foam Depth", Range(0,1)) = 0.25
        _FoamNormal ("Foam Normal", 2D) = "bump" {}
        _FoamNoiseScale ("Foam Noise Scale", Float) = 0.5
        _FoamSpeed ("Foam Speed", Float) = 1

        [Header(Sparkle)]
        _SparkleNormalMap ("Sparkle Normal", 2D) = "bump" {}
        _SparkleScale ("Sparkle Scale", Float) = 75
        _SparkleSpeed ("Sparkle Speed", Float) = 0.025
        _SparkleColor ("Sparkle Color", Color) = (1,1,1,1)
        _SparkleExponent ("Sparkle Exponent", Float) = 3
        _SparkleAmplitude ("Sparkle Amplitude", Float) = 5

        [Header(PBR)]
        _Metallic ("Metallic", Range(0,1)) = 1
        _Smoothness ("Smoothness", Range(0,1)) = 1
    }
    SubShader
    {
        Tags{"RenderPipeline" = "UniversalPipeline" "Queue" = "Transparent"}
        // ...
    }
}
```

---

## 11.4 顶点：Gerstner 波（可直接移植）

```hlsl
Interpolators Vertex(Attributes input)
{
    Interpolators output;

    float3 positionWS = TransformObjectToWorld(input.positionOS.xyz);

    // 两个方向的 Gerstner 波
    float2 dir0 = float2(cos(_Wave0Direction * PI * 2), sin(_Wave0Direction * PI * 2));
    float2 dir1 = float2(cos(_Wave1Direction * PI * 2), sin(_Wave1Direction * PI * 2));

    float k0 = 2 * PI / _Wave0Length;
    float k1 = 2 * PI / _Wave1Length;

    float phase0 = k0 * dot(dir0, positionWS.xz) - _Wave0Speed * _Time.y;
    float phase1 = k1 * dot(dir1, positionWS.xz) - _Wave1Speed * _Time.y;

    positionWS.y += _Wave0Amplitude * sin(phase0) + _Wave1Amplitude * sin(phase1);

    output.positionWS = positionWS;
    output.positionCS = TransformWorldToHClip(positionWS);
    output.normalWS = TransformObjectToWorldNormal(input.normalOS);
    output.tangentWS = TransformObjectToWorldDir(input.tangentOS.xyz);
    output.uv = input.uv;
    output.screenPos = ComputeScreenPos(output.positionCS);

    return output;
}
```

---

## 11.5 片元：波浪法线

```hlsl
// 两层滚动
float2 uv0 = input.positionWS.xz * _WaveNormalScale
           + _Time.y * _WaveNormalSpeed * float2(1, 1);
float2 uv1 = input.positionWS.xz * _WaveNormalScale
           + _Time.y * _WaveNormalSpeed * float2(-1, 0.5);

float3 n0 = UnpackNormal(SAMPLE_TEXTURE2D(_WaveNormalMap, sampler_WaveNormalMap, uv0));
float3 n1 = UnpackNormal(SAMPLE_TEXTURE2D(_WaveNormalMap, sampler_WaveNormalMap, uv1));

float3 normalTS = normalize(float3(n0.xy + n1.xy, n0.z * n1.z));

// 切线空间 → 世界空间（URP 辅助）
float3 normalWS = TransformTangentToWorld(normalTS,
    float3x3(input.tangentWS, cross(input.normalWS, input.tangentWS), input.normalWS));
normalWS = NormalizeNormalPerPixel(normalWS);
```

---

## 11.6 片元：深浅 + 泡沫 + 闪烁

```hlsl
// 1. 水深
float2 screenUV = input.screenPos.xy / input.screenPos.w;
float sceneDepth = LinearEyeDepth(SampleSceneDepth(screenUV), _ZBufferParams);
float waterDepth = -TransformWorldToView(input.positionWS).z;
float depth = sceneDepth - waterDepth;

float depthFactor = saturate(depth * _DepthDensity);
float3 waterColor = lerp(_ShallowColor.rgb, _DeepColor.rgb, depthFactor);

// 2. 边缘泡沫
float edgeFoam = 1 - saturate(depth / _EdgeFoamDepth);
float foamNoise = SAMPLE_TEXTURE2D(_FoamNormal, sampler_FoamNormal,
    input.positionWS.xz * _FoamNoiseScale + _Time.y * _FoamSpeed).r;
edgeFoam *= foamNoise;
waterColor = lerp(waterColor, _EdgeFoamColor.rgb, edgeFoam);

// 3. 闪烁
float2 sparkleUV = input.positionWS.xz * _SparkleScale + _Time.y * _SparkleSpeed;
float3 sparkleNormal = UnpackNormal(
    SAMPLE_TEXTURE2D(_SparkleNormalMap, sampler_SparkleNormalMap, sparkleUV));
float3 halfDir = normalize(GetMainLight().direction +
    GetWorldSpaceNormalizeViewDir(input.positionWS));
float sparkle = pow(saturate(dot(normalWS, halfDir)), _SparkleExponent) * _SparkleAmplitude;
waterColor += _SparkleColor.rgb * sparkle;
```

---

## 11.7 片元：折射 + 反射

```hlsl
// 折射：扰动屏幕 UV 采样 _CameraOpaqueTexture
float2 refractionUV = screenUV + normalWS.xz * 0.02;
float3 refracted = SAMPLE_TEXTURE2D(_CameraOpaqueTexture, sampler_CameraOpaqueTexture,
    refractionUV).rgb;

// Fresnel 混合
float3 viewDir = GetWorldSpaceNormalizeViewDir(input.positionWS);
float fresnel = pow(1 - saturate(dot(normalWS, viewDir)), 5);
float3 finalColor = lerp(refracted, waterColor, fresnel);

// 反射交给 URP SSR Feature（单独开启）
```

> **注意**：URP 的 `_CameraOpaqueTexture` 需要在 URP Asset 里勾 **Opaque Texture**。

---

## 11.8 水面是透明的

- Render Queue 设 Transparent
- `ZWrite Off`（或按需）
- 走 `UniversalForward` Pass

---

## 11.9 参考项目 vs URP 对照

| 项 | 参考项目 | URP |
|---|---|---|
| 光照 | 自定义 | `GetMainLight` / `UniversalFragmentPBR` |
| 场景颜色 | `_gLightingRT0` | `_CameraOpaqueTexture` |
| 深度 | `_gDepthRT` | `_CameraDepthTexture` |
| 反射 | 内嵌 SSR | URP SSR Feature |
| 波浪/泡沫/闪烁 | 相同 | 相同 |

---

## 11.10 验证

- 水面起伏、岸边泡沫、波光闪烁
- 透过水面看到水下场景扭曲
- 光滑水面反射岸边（需开 SSR）

---

## 11.11 常见坑

- ❌ **`_CameraOpaqueTexture` 没开**：折射采样到黑
- ❌ **只滚一层法线**：像"平移贴图"
- ❌ **Gerstner 幅度太大**：几何穿插
- ❌ **水面写深度**：透明物体应 ZWrite Off

---

## 11.12 与下一章的联系

水面搞定。下一章：SH9 vs URP Light Probe。

---

> 章节完。下一章 `12_SH9与URP光照探针对比.md`。
