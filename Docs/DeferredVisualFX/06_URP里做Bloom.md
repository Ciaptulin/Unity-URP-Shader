# 06 · URP 里做 Bloom

> 目标：在 URP 里启用 Bloom，理解参考项目的 Bloom 实现，对比差异。
> 参考项目：`Scripts/PostFX/Bloom.cs`、`Shaders/PostFX/Bloom.hlsl`

---

## 6.1 URP 有内置 Bloom

URP 的 **Volume** 系统内置 Bloom，用起来很简单：

1. 场景里建一个空物体，加 **Volume** 组件
2. 新建 **Volume Profile**（Create → Volume Profile）
3. Add Override → **Post-processing → Bloom**
4. 勾上参数：Intensity / Threshold / Scatter / Tint

**前提**：URP Asset 里 **Quality → HDR** 要勾上（否则 Bloom 效果差）。

---

## 6.2 URP Bloom 原理（与参考项目一致）

两者都是**多级降采样 + 升采样**：

| 步骤 | URP | 参考项目 |
|---|---|---|
| 1. 阈值 | `Threshold` 参数 | `_luminanceThreshole` |
| 2. 降采样 | 固定 6 级（WebGL 少）| `downSampleStep` 可配（默认 7）|
| 3. 每级模糊 | 高斯（1D 分离）| `GaussNxN`（2D）|
| 4. 升采样累加 | 是 | 是 |
| 5. 合成 | ACES + 颜色空间 | ACES + Gamma |

**结论**：算法同源。用 URP 内置的就行。

---

## 6.3 URP 内置 vs 参考项目的差异

| 项 | URP 内置 | 参考项目 |
|---|---|---|
| 模糊核 | 1D 分离（两次）| 2D 一次 |
| 强度模型 | Scatter 控制扩散 | intensity 直接乘 |
| Tonemapping | 独立 Volume 项 | 内嵌在合成里 |
| 可配级数 | 否 | 是 |

**实践建议**：

- 一般需求 → 用 URP 内置
- 需要特殊模糊形状 / 级数控制 → 参考项目的方式自己写

---

## 6.4 参考项目的 Bloom 要点

**阈值**（`BloomThresholdPassFragment`）：

```hlsl
float lum = dot(float3(0.2126, 0.7152, 0.0722), color.rgb);  // Rec.709 亮度
if (lum > _luminanceThreshole) return color;
return float4(0, 0, 0, 1);
```

**升采样累加**（`BloomUpSamplePassFragment`）：

```hlsl
float3 prevMip = GaussNxN(_PrevMip, uv, _upSampleBlurSize, preStride, _upSampleBlurSigma);
float3 curMip = GaussNxN(_postFXSource, uv, _upSampleBlurSize, curStride, _upSampleBlurSigma);
color.rgb = prevMip + curMip;   // 累加
```

**合成**（`BloomCombinePassFragment`）：

```hlsl
bloom *= _bloomIntensity;
bloom.rgb = ACESToneMapping(bloom.rgb, 1.0);
bloom.rgb = saturate(pow(bloom.rgb, 1.0 / 2.2));   // 转 Gamma
color.rgb += bloom.rgb;
```

---

## 6.5 如果自己写：URP 下的结构

```csharp
public class BloomFeature : ScriptableRendererFeature
{
    class BloomPass : ScriptableRenderPass
    {
        public override void Execute(ScriptableRenderContext context, ref RenderingData data)
        {
            CommandBuffer cmd = CommandBufferPool.Get("CustomBloom");

            // 1. 阈值
            int thresholdID = Shader.PropertyToID("_ThresholdRT");
            cmd.GetTemporaryRT(thresholdID, w, h, 0, FilterMode.Bilinear, format);
            Blitter.BlitCameraTexture(cmd, src, thresholdID, mat, 0);

            // 2. 降采样链
            for (int i = 0; i < steps; i++)
            {
                int downID = Shader.PropertyToID("_BloomDown" + i);
                cmd.GetTemporaryRT(downID, w >> (i+1), h >> (i+1), 0, FilterMode.Bilinear, format);
                Blitter.BlitCameraTexture(cmd, prev, downID, mat, 1);
                prev = downID;
            }

            // 3. 升采样
            // ...

            // 4. 合成
            Blitter.BlitCameraTexture(cmd, src, dst, mat, 3);

            context.ExecuteCommandBuffer(cmd);
            CommandBufferPool.Release(cmd);
        }
    }
}
```

> **URP 16 关键 API**：`Blitter.BlitCameraTexture(cmd, source, destination, material, pass)`。它内部处理了 UV 翻转、颜色空间。

---

## 6.6 验证

- 高亮物体周围有光晕
- 调 Threshold：越低光晕越多
- 调 Intensity：越强越亮
- **HDR 必须开**（URP Asset → Quality）

---

## 6.7 常见坑

- ❌ **HDR 没开**：Bloom 几乎看不到
- ❌ **Bloom 加在透明之前**：透明物体没 Bloom
- ❌ **Tonemapping 和 Bloom 冲突**：都做 Gamma 会过曝
- ❌ **临时 RT 没释放**：显存泄漏

---

## 6.8 与下一章的联系

Bloom 搞定。下一章：体积云。

---

> 章节完。下一章 `07_URP里做体积云.md`。
