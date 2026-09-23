# 04 · URP 里做 SSAO

> 目标：在 URP 里启用 / 自写 SSAO，对照参考项目的实现。
> 参考项目：`Scripts/PostFX/SSAO.cs`、`Shaders/PostFX/SSAO.hlsl`

---

## 4.1 三条路线

在 URP 里做 SSAO，有三条路：

| 路线 | 工作量 | 控制力 |
|---|---|---|
| **A. 用 URP 内置 SSAO** | 最低（配一下）| 低 |
| **B. 自己写 Renderer Feature + Shader** | 高 | 完全可控 |
| **C. 从参考项目移植算法** | 中 | 中 |

**建议**：先走 A 验证需求，不够再走 B/C。

---

## 4.2 路线 A：URP 内置 SSAO

1. 选中 **URP Asset 对应的 Renderer**
2. **Add Renderer Feature → Screen Space Ambient Occlusion**
3. 配置：
   - **Source**：`Depth Normals`（若 MyLit 有 DepthNormals Pass，用这个质量更高）
   - **Method**：`Blue Noise`（质量高）/ `Interleaved Gradient`（快）
   - **Intensity / Radius / Falloff Distance**
   - **Downsample**：勾上省性能

**前提**：MyLit 已有 `DepthNormals` Pass（项目已实现），所以 SSAO 能拿到法线，质量更高。

---

## 4.3 路线 B/C：自写 Renderer Feature

参考项目的 SSAO 是**两遍**：

1. **算 AO**：对每像素半球采样
2. **模糊 + 应用**：模糊 AO 后乘到场景颜色

移植到 URP 的结构：

```csharp
public class MySSAOFeature : ScriptableRendererFeature
{
    class MySSAOPass : ScriptableRenderPass
    {
        Material m_Material;

        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData data)
        {
            // 配置 RT
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData data)
        {
            // 两遍：算 AO → 模糊+应用
        }
    }
}
```

**与参考项目的差异**：

| 参考项目 | URP |
|---|---|
| 手写 `CommandBuffer` | 用 `ScriptableRenderPass` |
| 自己管理 RT | `ConfigureTarget` / `GetTemporaryRT` |
| 读自己的 `_gDepthRT` / `_gBufferRT1` | 读 URP 的 `_CameraDepthTexture` / `_CameraNormalsTexture` |
| `PostFXStack` 驱动 | Renderer Feature 自动触发 |

---

## 4.4 关键：替换数据源

参考项目的 shader 里读的是：

```hlsl
float rawDepth = SAMPLE_TEXTURE2D(_gDepthRT, sampler_point_clamp, uv).r;
float3 normalWS = SAMPLE_TEXTURE2D(_gBufferRT1, sampler_gBufferRT1, uv).xyz * 2 - 1;
```

移植到 URP，改成：

```hlsl
float rawDepth = SampleSceneDepth(uv);            // URP 辅助函数
float3 normalWS = SampleSceneNormals(uv);         // URP 辅助函数
```

这两个函数在 `Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl` 和 `DeclareNormalsTexture.hlsl` 里。

**其余算法（半球采样、深度比较、模糊）可以原样移植。**

---

## 4.5 半球采样（核心算法）

参考项目的 `UniformSampling`：给定屏幕 UV 和法线，返回半球内随机方向。算法本身与管线无关：

```hlsl
float3 UniformSampling(float2 uv, float3 normalVS)
{
    // 随机数
    float r1 = frac(sin(dot(uv, float2(12.9898, 78.233))) * 43758.5453);
    float r2 = frac(sin(dot(uv, float2(39.346, 11.135))) * 24634.6345);

    // 半球均匀采样（余弦加权更好）
    float theta = acos(1 - 2 * r1);
    float phi = 2 * PI * r2;

    float3 localDir = float3(sin(theta) * cos(phi), cos(theta), sin(theta) * sin(phi));

    // 从法线构建 TBN，把 localDir 转到视空间
    float3 up = abs(normalVS.z) < 0.999 ? float3(0, 0, 1) : float3(1, 0, 0);
    float3 tangent = normalize(cross(up, normalVS));
    float3 bitangent = cross(normalVS, tangent);

    return tangent * localDir.x + bitangent * localDir.y + normalVS * localDir.z;
}
```

**要点**：半球采样要**以法线为轴**，否则 AO 会均匀分布在整个球面，效果错。

---

## 4.6 AO 计算

````hlsl
float ao = 0;
for (int i = 0; i < SAMPLE_COUNT; i++)
{
    float3 sampleDir = UniformSampling(uv, normalVS);
    float3 samplePosVS = positionVS + sampleDir * _radius;

    // 投回屏幕
    float2 sampleUV = ViewToDepthUV(samplePosVS);

    float sampleDepth = LinearEyeDepth(SampleSceneDepth(sampleUV), _ZBufferParams);
    float currentDepth = LinearEyeDepth(SampleSceneDepth(uv), _ZBufferParams);

    // 采样点更远 = 被挡
    float diff = sampleDepth - currentDepth - _depthBias;
    if (diff > 0)
        ao += 1;
}
ao = 1 - ao / SAMPLE_COUNT;
```

参考项目里 `ao += max(1, abs(distance))` 是另一种加权方式，效果类似。

---

## 4.7 模糊

```hlsl
// 简单 box 模糊
float aoBlur = 0;
for (int x = -5; x < 5; x++)
    for (int y = -5; y < 5; y++)
        aoBlur += SAMPLE_TEXTURE2D(_SSAOTexture, sampler_LinearClamp,
            uv + float2(x, y) * texelSize * _blurRadius).r;
aoBlur /= 100;
```

---

## 4.8 应用

AO 乘到**环境光**上（不是乘到整个颜色，否则直射光被错误压暗）：

```hlsl
// 只对 indirect / ambient 乘 AO
color.indirect *= ao;
```

参考项目是直接 `color *= ao`（简化），效果稍糙。

---

## 4.9 验证

- 物体接缝、凹陷处变暗
- 调 radius / strength
- 关掉对比：无 AO 时画面更"平"

---

## 4.10 常见坑

- ❌ **半球采样没按法线对齐**：AO 分布错
- ❌ **没 depthBias**：平面自遮蔽
- ❌ **AO 乘到整个颜色**：直射光也被压暗
- ❌ **RT 没释放**：显存泄漏

---

## 4.11 与下一章的联系

SSAO 搞定。下一章：SSR。

---

> 章节完。下一章 `05_URP里做SSR.md`。
