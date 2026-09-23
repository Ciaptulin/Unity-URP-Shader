# 07 · URP 里做体积云

> 目标：在 URP 里实现屏幕空间体积云。
> 参考项目：`Scripts/PostFX/VolumetricCloud.cs` + 对应 hlsl

---

## 7.1 URP 没有内置体积云

URP 不提供体积云。要么用第三方（如 HDRP 的体积云、社区插件），要么自己写 Renderer Feature。

参考项目是在 CustomSRP 的 PostFXStack 里做的，移植到 URP 需要**改写为 Renderer Feature**。

---

## 7.2 参考项目的核心

**光线步进**：从相机出发，射线在云层高度范围内分段采样 3D 噪声，按密度积分。

| 输入 | 来源 |
|---|---|
| 射线起点 | `_WorldSpaceCameraPos` |
| 射线方向 | 从深度重建的世界坐标 - 起点 |
| 云层范围 | 世界 Y 的 `[cloudBottom, cloudTop]` |
| 3D 噪声 | `_noise3D` / `_noiseDetail3D` |
| 天气图 | `_weatherMap`（2D）|
| 蓝噪声 | `_blueNoise`（抖动起点）|

---

## 7.3 移植到 URP 的结构

```csharp
public class VolumetricCloudFeature : ScriptableRendererFeature
{
    [System.Serializable]
    public class Settings
    {
        public bool enable = false;
        public float rayStep = 0.06f;
        public float step = 3.5f;
        public float densityOffset = -10.9f;
        public float densityMultiplier = 1.2f;
        public Color colA = Color.white;
        public Color colB = Color.white;
        public Texture3D noise3D;
        public Texture3D noiseDetail3D;
        public Texture2D weatherMap;
        public Texture2D blueNoise;
        public Texture2D maskNoise;
        public float shapeTiling = 0.002f;
        public float detailTiling = 0.022f;
        public Transform cloudTransform;
        public Light sun;
    }

    public Settings settings = new Settings();
    Material m_Material;

    class CloudPass : ScriptableRenderPass
    {
        Material m_Material;
        Settings m_Settings;

        public CloudPass(Material mat, Settings s)
        {
            m_Material = mat;
            m_Settings = s;
            // 云要在不透明后、透明前
            renderPassEvent = RenderPassEvent.BeforeRenderingTransparents;
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData data)
        {
            if (!m_Settings.enable) return;

            CommandBuffer cmd = CommandBufferPool.Get("VolumetricCloud");

            // 传参
            m_Material.SetFloat("_rayStep", m_Settings.rayStep);
            m_Material.SetFloat("_step", m_Settings.step);
            m_Material.SetFloat("_densityOffset", m_Settings.densityOffset);
            m_Material.SetFloat("_densityMultiplier", m_Settings.densityMultiplier);
            m_Material.SetColor("_colA", m_Settings.colA);
            m_Material.SetColor("_colB", m_Settings.colB);
            m_Material.SetTexture("_noise3D", m_Settings.noise3D);
            m_Material.SetTexture("_noiseDetail3D", m_Settings.noiseDetail3D);
            m_Material.SetTexture("_weatherMap", m_Settings.weatherMap);
            m_Material.SetTexture("_blueNoise", m_Settings.blueNoise);
            m_Material.SetFloat("_shapeTiling", m_Settings.shapeTiling);
            m_Material.SetFloat("_detailTiling", m_Settings.detailTiling);

            if (m_Settings.sun != null)
                m_Material.SetVector("_MainLightDirection",
                    -m_Settings.sun.transform.forward);

            // 全屏 Blit
            Blitter.BlitCameraTexture(cmd,
                data.cameraData.renderer.cameraColorTargetHandle,
                data.cameraData.renderer.cameraColorTargetHandle,
                m_Material, 0);

            context.ExecuteCommandBuffer(cmd);
            CommandBufferPool.Release(cmd);
        }
    }

    public override void Create()
    {
        var shader = Shader.Find("Hidden/VolumetricCloud");
        if (shader == null) return;
        m_Material = CoreUtils.CreateEngineMaterial(shader);
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData data)
    {
        if (m_Material == null) return;
        renderer.EnqueuePass(new CloudPass(m_Material, settings));
    }
}
```

---

## 7.4 Shader：数据源

| 参考项目 | URP |
|---|---|
| `_gDepthRT` | `_CameraDepthTexture` |
| `_ViewToProjectionInv` | `UNITY_MATRIX_I_VP` |
| `_MainLightDirection`（全局）| 从 Renderer Feature 传 |

---

## 7.5 Shader：核心（可直接移植）

```hlsl
float4 CloudFragment(Varyings input) : SV_Target
{
    float2 uv = input.screenUV;
    float rawDepth = SampleSceneDepth(uv);
    float3 positionWS = ComputeWorldSpacePosition(uv, rawDepth, UNITY_MATRIX_I_VP);

    float3 rayOrigin = _WorldSpaceCameraPos;
    float3 rayDir = normalize(positionWS - rayOrigin);

    // 云层范围
    float cloudBottom = 0;
    float cloudTop = 300;

    float tMin, tMax;
    if (!IntersectCloudLayer(rayOrigin, rayDir, cloudBottom, cloudTop, tMin, tMax))
        return SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv);

    // 蓝噪声抖动
    float blueNoise = SAMPLE_TEXTURE2D(_blueNoise, sampler_blueNoise,
        uv * _blueNoiseCoords.xy).r;

    float stepSize = (tMax - tMin) / _step;
    float t = tMin + stepSize * blueNoise;

    float3 color = 0;
    float transmittance = 1;

    for (int i = 0; i < _step; i++)
    {
        if (transmittance < 0.01) break;

        float3 pos = rayOrigin + rayDir * t;
        float density = SampleCloudDensity(pos);

        if (density > 0)
        {
            float3 lightEnergy = LightMarching(pos);
            float3 luminance = lerp(_colB, _colA, lightEnergy) * density;

            float extinction = density * _lightAbsorptionThroughCloud;
            float sampleTransmittance = exp(-extinction);

            color += luminance * transmittance * (1 - sampleTransmittance);
            transmittance *= sampleTransmittance;
        }
        t += stepSize;
    }

    float3 scene = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv).rgb;
    return float4(scene * transmittance + color, 1);
}
```

**`IntersectCloudLayer`**（射线与两个水平面的交点）：

```hlsl
bool IntersectCloudLayer(float3 o, float3 d, float bottom, float top,
                         out float tMin, out float tMax)
{
    if (abs(d.y) < 1e-5) return false;

    float t0 = (bottom - o.y) / d.y;
    float t1 = (top - o.y) / d.y;

    tMin = min(t0, t1);
    tMax = max(t0, t1);

    if (tMax < 0) return false;
    tMin = max(tMin, 0);
    return true;
}
```

---

## 7.6 噪声纹理准备

参考项目需要：

- **3D 噪声**（shape + detail）：可以用 Unity 的 `Texture3D`，或运行时用 compute 生成
- **天气图**（2D）：控制云分布
- **蓝噪声**（2D）：抖动

**3D 噪声生成**思路：用 compute shader 对 Worley / Perlin 噪声采样，写进 `RenderTexture`（volume）。

---

## 7.7 与参考项目的差异

| 项 | 参考项目 | URP |
|---|---|---|
| 驱动 | `PostFXStack` | Renderer Feature |
| 数据源 | 自有 RT | URP `_CameraDepthTexture` |
| 光照方向 | `PostFXManager.sun` | Renderer Feature 传 |
| 全屏 Blit | 手写三角形 | `Blitter.BlitCameraTexture` |

**核心算法（步进 / 密度 / 光照）完全一致，可原样搬。**

---

## 7.8 验证

- 云层高度范围内出现云
- 云随时间流动（`_Time.y` 驱动 warp）
- 太阳方向有前向散射光晕
- 性能：全屏云很贵，注意 `_step` 数量

---

## 7.9 常见坑

- ❌ **步进次数太多**：帧率暴跌。`_step` 建议 32~64
- ❌ **没蓝噪声抖动**：明显条带
- ❌ **光照步进太多**：再乘几倍开销
- ❌ **云画在透明之后**：透明物体被云盖住
- ❌ **3D 噪声无 mipmap**：远处闪烁

---

## 7.10 与下一章的联系

后处理移植完。下一章进入特殊材质：卡通角色光照。

---

> 章节完。下一章 `08_URP里做卡通角色光照.md`。
