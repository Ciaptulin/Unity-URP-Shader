# 09 · URP 里做粒子光照

> 目标：在 URP 里实现参考项目的粒子光照。
> 参考项目：`Shaders/ShaderLibrary/ParticleLighting.hlsl`

---

## 9.1 参考项目极简

```hlsl
float3 GetParticleLighting(float4 albedo)
{
    return albedo.rgb;   // 直接用颜色
}
```

**为什么这么简单**：粒子（火焰、烟雾）靠纹理 + 混合模式出效果，PBR 光照反而"脏"。

---

## 9.2 URP 里天然就有

URP 的 **Particles/Unlit** 或 **Particles/Lit** shader 已经覆盖了这个需求：

| 需求 | URP 内置 |
|---|---|
| 纯颜色粒子 | `Universal Render Pipeline/Particles/Unlit` |
| 受光粒子 | `Universal Render Pipeline/Particles/Lit` |
| 加法混合 | 材质 `Blend Mode = Additive` |

**结论**：普通粒子需求，URP 内置就够了。

---

## 9.3 参考项目做法的意义

参考项目在 GBuffer ID 里给粒子留了 10~20 的区间，想让延迟光照统一处理粒子。但**在延迟管线里让透明粒子走 GBuffer 本身就不自然**——透明物体不该写 GBuffer。

参考项目注释也承认：粒子部分"目前场景的 A 通道没有对应的贴图"，是**实验性预留**。

**所以移植到 URP 的价值不高**。真要做：

- 粒子走 URP 的透明 Forward
- 用 `Particles/Lit`，或自写一个"用颜色当光照"的 shader

---

## 9.4 自写粒子 Shader（如果想）

```hlsl
Shader "Custom/ToonParticle"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
        _TintColor ("Tint", Color) = (1,1,1,1)
        _SoftParticles ("Soft Particles", Range(0,1)) = 0.5
    }
    SubShader
    {
        Tags{"RenderPipeline" = "UniversalPipeline" "Queue" = "Transparent"
             "RenderType" = "Transparent"}

        Pass
        {
            Tags{"LightMode" = "UniversalForward"}
            Blend SrcAlpha One     // 加法混合
            ZWrite Off
            Cull Off

            HLSLPROGRAM
            #pragma vertex Vertex
            #pragma fragment Fragment
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);
            float4 _MainTex_ST;
            float4 _TintColor;
            float _SoftParticles;

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
                float4 color : COLOR;
            };

            struct Interpolators
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                float4 color : COLOR;
                float4 screenPos : TEXCOORD1;
            };

            Interpolators Vertex(Attributes input)
            {
                Interpolators output;
                output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                output.uv = TRANSFORM_TEX(input.uv, _MainTex);
                output.color = input.color * _TintColor;
                output.screenPos = ComputeScreenPos(output.positionCS);
                return output;
            }

            float4 Fragment(Interpolators input) : SV_Target
            {
                float4 tex = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, input.uv);

                // 软粒子：与场景深度混合，避免硬边
                float2 screenUV = input.screenPos.xy / input.screenPos.w;
                float sceneDepth = SampleSceneDepth(screenUV);
                float particleDepth = input.positionCS.z;
                // ... 深度差算 alpha 衰减 ...

                float4 color = tex * input.color;
                return color;
            }
            ENDHLSL
        }
    }
}
```

---

## 9.5 URP 粒子建议

| 场景 | 推荐 |
|---|---|
| 火焰 / 光效（加法混合）| `Particles/Unlit` + Additive |
| 烟雾 / 雾（alpha 混合）| `Particles/Unlit` + Alpha |
| 需要受光 | `Particles/Lit` |
| 特殊风格 | 自写（参考项目思路）|

---

## 9.6 验证

- 粒子正常显示
- 加法混合的火焰有发光感
- 软粒子在硬表面边缘平滑过渡

---

## 9.7 常见坑

- ❌ **粒子走 GBuffer**：透明物体不该写 GBuffer
- ❌ **忘了 SoftParticles**：粒子与场景交界有硬边
- ❌ **排序问题**：多个粒子互相遮挡时闪烁（透明通病）

---

## 9.8 与下一章的联系

粒子搞定。下一章：双层材质。

---

> 章节完。下一章 `10_URP里做双层材质.md`。
