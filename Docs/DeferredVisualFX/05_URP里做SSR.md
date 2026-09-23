# 05 · URP 里做 SSR

> 目标：在 URP 里实现屏幕空间反射，对照参考项目的 SSR。
> 参考项目：`Scripts/PostFX/SSReflection.cs` + `Shaders/PostFX/SSReflection.hlsl`

---

## 5.1 URP 的现状

**URP 不内置 SSR**（Screen Space Reflection）到 16.0.6 为止只有 **SSR 的 shader 库函数**（`GlobalIllumination.hlsl` 里的 `GlobalIllumination`），没有开箱即用的 Renderer Feature。

所以要做 SSR，得自己写 Renderer Feature。

---

## 5.2 参考项目的 SSR 结构

| 部分 | 位置 | 说明 |
|---|---|---|
| 参数 | `SSReflectionSettings` | stepSize / maxStep / thickness / edgeFade |
| 驱动 | `SSReflection.Render` | 决定走确定性还是随机版本 |
| 光线步进 | `RayMarching2` | 核心算法 |
| 合成 | `SSSReflectionResolvePassFragment` | 采样反射颜色 + 边缘淡出 |

---

## 5.3 移植到 URP：Renderer Feature 骨架

```csharp
public class SSRFeature : ScriptableRendererFeature
{
    [System.Serializable]
    public class Settings
    {
        public bool enable = false;
        public float stepSize = 0.2f;
        public int maxStep = 32;
        public float thickness = 0.3f;
        public float stepSizeMultiplier = 1.2f;
        public float edgeFade = 0.3f;
    }

    public Settings settings = new Settings();
    Material m_Material;

    class SSRPass : ScriptableRenderPass
    {
        Material m_Material;
        Settings m_Settings;

        public SSRPass(Material mat, Settings s)
        {
            m_Material = mat;
            m_Settings = s;
            renderPassEvent = RenderPassEvent.BeforeRenderingTransparents;
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData data)
        {
            if (!m_Settings.enable) return;

            CommandBuffer cmd = CommandBufferPool.Get("SSR");

            // 配置参数
            m_Material.SetFloat("_stepSize", m_Settings.stepSize);
            m_Material.SetInteger("_maxStep", m_Settings.maxStep);
            m_Material.SetFloat("_thickness", m_Settings.thickness);
            m_Material.SetFloat("_stepSizeMultiplier", m_Settings.stepSizeMultiplier);
            m_Material.SetFloat("_edgeFade", m_Settings.edgeFade);

            // 用 Blitter 做全屏 Pass
            Blitter.BlitCameraTexture(cmd, data.cameraData.renderer.cameraColorTargetHandle,
                data.cameraData.renderer.cameraColorTargetHandle, m_Material, 0);

            context.ExecuteCommandBuffer(cmd);
            CommandBufferPool.Release(cmd);
        }
    }

    public override void Create()
    {
        var shader = Shader.Find("Hidden/MySSR");
        if (shader == null) return;
        m_Material = CoreUtils.CreateEngineMaterial(shader);
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData data)
    {
        if (m_Material == null) return;
        renderer.EnqueuePass(new SSRPass(m_Material, settings));
    }

    protected override void Dispose(bool disposing)
    {
        CoreUtils.Destroy(m_Material);
    }
}
```

> **URP 16 注意**：`Blitter.BlitCameraTexture` 是新 API；`cameraColorTargetHandle` 是 RTHandle。老教程里的 `cameraColorTarget`（RenderTargetIdentifier）已过时。

---

## 5.4 Shader：数据源替换

参考项目读自己的 RT，URP 里改读：

| 参考项目 | URP |
|---|---|
| `_gDepthRT` | `_CameraDepthTexture`（`SampleSceneDepth`）|
| `_gBufferRT1`（法线）| `_CameraNormalsTexture`（`SampleSceneNormals`）|
| `_gBufferRT2`（roughness）| URP 无直接等价，需自读 GBuffer 或跳过 |
| `_gLightingRT0` | `_CameraOpaqueTexture`（场景颜色）|

```hlsl
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareNormalsTexture.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareOpaqueTexture.hlsl"

float rawDepth = SampleSceneDepth(uv);
float3 normalWS = SampleSceneNormals(uv);
float3 sceneColor = SampleSceneColor(uv);
```

---

## 5.5 重建世界坐标

参考项目用 `_ViewToProjectionInv`。URP 里有现成函数：

```hlsl
// 从深度重建世界坐标（URP 官方辅助）
float3 positionWS = ComputeWorldSpacePosition(uv, rawDepth, UNITY_MATRIX_I_VP);
```

或手动：

```hlsl
float4 posNDC = float4(uv * 2 - 1, rawDepth, 1);
float4 positionWS = mul(UNITY_MATRIX_I_VP, posNDC);
positionWS /= positionWS.w;
```

**URP 用 `UNITY_MATRIX_I_VP`**，不用自己算。

---

## 5.6 光线步进（可原样移植）

`RayMarching2` 的算法与管线无关，直接搬：

```hlsl
RayHit RayMarching2(Ray ray, float dither)
{
    RayHit hit; hit.distance = -1; hit.uv = 0;

    float stepSize = _stepSize;
    for (int i = 0; i < _maxStep; i++)
    {
        ray.position += ray.direction * stepSize * (1 + dither);

        float4 clipPos = mul(UNITY_MATRIX_VP, float4(ray.position, 1));
        float2 uv = clipPos.xy / clipPos.w * 0.5 + 0.5;

        if (any(uv < 0) || any(uv > 1)) break;

        float sceneDepth = SampleSceneDepth(uv);
        float rayDepth = -TransformWorldToView(ray.position).z;

        float diff = rayDepth - sceneDepth;
        if (diff > 0 && diff < _thickness)
        {
            hit.distance = 1;
            hit.uv = uv;
            break;
        }
        stepSize *= _stepSizeMultiplier;
    }
    return hit;
}
```

---

## 5.7 合成

```hlsl
float4 SSRFragment(Varyings input) : SV_Target
{
    float2 uv = input.screenUV;

    float rawDepth = SampleSceneDepth(uv);
    float3 normalWS = normalize(SampleSceneNormals(uv));
    float3 positionWS = ComputeWorldSpacePosition(uv, rawDepth, UNITY_MATRIX_I_VP);

    float3 viewDir = normalize(positionWS - _WorldSpaceCameraPos);
    Ray ray;
    ray.position = positionWS;
    ray.direction = reflect(viewDir, normalWS);

    float dither = InterleavedGradientNoise(uv * _ScreenParams.xy, 0) * 0.25 - 0.125;
    RayHit hit = RayMarching2(ray, dither);

    float4 original = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv);

    if (hit.distance > 0)
    {
        float3 reflection = SampleSceneColor(hit.uv);
        // 边缘淡出
        float fade = EdgeOfScreenFade(hit.uv);
        return float4(lerp(original.rgb, reflection, fade), original.a);
    }
    return original;
}
```

---

## 5.8 验证

- 光滑地面反射出上方物体
- 物体移出屏幕，反射消失（SSR 固有限制）
- 调 `thickness`：太大反射穿透，太小反射断裂

---

## 5.9 常见坑

- ❌ **`_CameraOpaqueTexture` 没开**：URP Asset 里要勾 `Opaque Texture`
- ❌ **用了过时 API**：URP 16 用 `Blitter.BlitCameraTexture` + RTHandle
- ❌ **没设 `renderPassEvent`**：SSR 要在透明之前
- ❌ **URP 无 roughness 来源**：反射无法按粗糙度模糊（URP 限制）

---

## 5.10 与下一章的联系

SSR 移植完。下一章：Bloom。

---

> 章节完。下一章 `06_URP里做Bloom.md`。
