> 原文：[Mapping Our Way to PBR: Writing Unity URP Shaders with Code (Part 4)](https://nedmakesgames.medium.com/mapping-our-way-to-pbr-writing-unity-urp-shaders-with-code-part-4-6c4ae9875529)  
作者：NedMakesGames
>

---

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787348176010-700401be-00ea-4c9a-9aae-d42dbfc84e22.png)

## 前言
大家好，我是 Ned，一名游戏开发者！你是否曾经好奇 Unity 中的着色器是如何工作的？或者，你想为通用渲染管线（URP）编写自己的着色器，但不想用 Shader Graph？无论是因为你需要某些特殊功能，还是单纯更喜欢手写代码，本教程都能帮到你。

今天，我们将深入探讨材质选项，为模型赋予更逼真的外观。通过基于物理的渲染（PBR），我们将实现法线贴图、金属工作流、更多透明混合模式、视差遮挡映射和清漆效果。最后，我还会介绍一些优化纹理使用的技巧，帮助你打造属于自己的着色器。

---

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787348162979-be4730ad-9948-4f75-8d08-1547888271d0.png)

## 一、基于物理的渲染（PBR）
到目前为止，我们在 MyLit 着色器中使用的是 Blinn-Phong 着色算法。它对简单物体来说很好用，但我们可以做得更好。大多数渲染引擎都已经采用了一个标准的着色范式——"基于物理的渲染"，通常缩写为 **PBR**。它通过"双向反射分布函数（BRDF）"来模拟真实的光照。

幸运的是，Unity 已经在默认的 Lit 着色器中帮我们写好了这个实现！<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787348208701-655a9ee9-44fd-4dad-a5df-e205f78602be.png)

我们可以非常轻松地在 MyLit 着色器中复用他们的实现。

```csharp
float4 Fragment(Interpolators input
#ifdef _DOUBLE_SIDED_NORMALS
	, FRONT_FACE_TYPE frontFace : FRONT_FACE_SEMANTIC
#endif
) : SV_TARGET {
	float2 uv = input.uv;
	float4 colorSample = SAMPLE_TEXTURE2D(_ColorMap, sampler_ColorMap, uv) * _ColorTint;
	TestAlphaClip(colorSample);

	float3 normalWS = normalize(input.normalWS);
	#ifdef _DOUBLE_SIDED_NORMALS
	normalWS *= IS_FRONT_VFACE(frontFace, 1, -1);
	#endif
	
	InputData lightingInput = (InputData)0;
	lightingInput.positionWS = input.positionWS;
	lightingInput.normalWS = normalWS;
	lightingInput.viewDirectionWS = GetWorldSpaceNormalizeViewDir(input.positionWS);
	lightingInput.shadowCoord = TransformWorldToShadowCoord(input.positionWS);
	
	SurfaceData surfaceInput = (SurfaceData)0;
	surfaceInput.albedo = colorSample.rgb;
	surfaceInput.alpha = colorSample.a;
	surfaceInput.specular = 1;
	surfaceInput.smoothness = _Smoothness;
	
	return UniversalFragmentPBR(lightingInput, surfaceInput);
}
```

在 `MyLitForwardLitPass`的`Fragment`函数中，将最终的函数调用改为 `<font style="background-color:#C1E77E;">UniversalFragmentPBR</font>`。在 Unity 2020 和 2021 中，它接受相同的参数，因此可以安全地移除 `#if` 分支。

```csharp
Shader "NedMakesGames/MyLit" {
    Properties{
        // Code omitted
    }

    SubShader {
        Tags {"RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline"}

        Pass {
            Name "ForwardLit"
            Tags{"LightMode" = "UniversalForward"}

            Blend[_SourceBlend][_DestBlend]
            ZWrite[_ZWrite] 
            Cull[_Cull]

            HLSLPROGRAM
            
            #pragma shader_feature_local _ALPHA_CUTOUT
            #pragma shader_feature_local _DOUBLE_SIDED_NORMALS
            
#if UNITY_VERSION >= 202120
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
#else
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
#endif
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
            
            #pragma vertex Vertex
            #pragma fragment Fragment
            
            #include "MyLitForwardLitPass.hlsl"
            ENDHLSL
        }

        // Code omitted
    }

    CustomEditor "MyLitCustomInspector"
}
```

PBR 默认就包含镜面高光——着色器文件中的 `#define` 不再需要。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787348276435-2596ae26-7f5d-4824-93ec-d58425aadc1d.png)

在场景视图中，看起来非常相似。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787348294664-0afaaa0c-27f3-48ed-a389-c91b4bd83d87.png)

_在Unity 2020中，使用PBR时，光滑度（Smoothness）值的范围应为0到1_

如果你使用的是 Unity 2020，请将材质的<font style="background-color:#C1E77E;">平滑度</font>降低到 <font style="background-color:#C1E77E;">0 到 1 之间</font>的值。实际上，我们可以在 Inspector 中强制限制这个范围。

```csharp
Shader "NedMakesGames/MyLit" {
    Properties{
        [Header(Surface options)]
        [MainTexture] _ColorMap("Color", 2D) = "white" {}
        [MainColor] _ColorTint("Tint", Color) = (1, 1, 1, 1)
        _Cutoff("Alpha cutout threshold", Range(0, 1)) = 0.5
        _Smoothness("Smoothness", Range(0, 1)) = 0.5
        
        [HideInInspector] _Cull("Cull mode", Float) = 2 // 2 is "Back"
        [HideInInspector] _SourceBlend("Source blend", Float) = 0
        [HideInInspector] _DestBlend("Destination blend", Float) = 0
        [HideInInspector] _ZWrite("ZWrite", Float) = 0
        [HideInInspector] _SurfaceType("Surface type", Float) = 0
        [HideInInspector] _FaceRenderingMode("Face rendering type", Float) = 0
    }
    
    // Code omitted
}
```

在 `.shader` 文件中，将 `_Smoothness` 属性改为 `Range` 类型，范围设为 0 到 1。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787348363713-7061d2a1-10d5-428f-9759-53bf7778bd6a.png)

Inspector 会渲染为一个滑块，并将值限制在最小值和最大值之间。

这就是在着色器中使用 PBR 所需的全部操作——尽管是一个非常精简的版本。我们很快会实现更多功能。现在，请注意更真实的镜面高光效果。我不会在本教程中深入讲解 BRDF 或 PBR 算法背后的数学原理，但如果这听起来很有趣，请告诉我！

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787348372399-851f6b93-7b41-4306-aeb5-235ab79efb2f.png)

_帧调试器_

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787815280473-ecea1b96-f879-46fd-8f84-3713ecd8ccca.png)

<font style="color:#117CEE;">修改代码后，在很片的角度才能看到高光。高光是白色的，设置为白色底色不容易看到高光，调成红色色调后就明显得多，如图所示</font>

---

## 二、调试视图
随着着色器变得越来越复杂，对更好调试工具的需求也在增长。我们在上一节中使用了帧调试器（Frame Debugger），它对于查看绘制顺序很有用，但如果我们想检查变量的值呢？在 C# 中有 `Debug.Log`，但 HLSL 没有类似的函数。

不过，片元函数输出的是颜色，而我们知道，颜色本质上就是数字。我们可以用它们来可视化任何值——只要值的范围在 0 到 1 之间。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787348389383-123c1b7c-7766-4dcc-8f6c-c12aaa6f31d2.png)

例如，将法线向量作为颜色输出非常有用。只需几个小步骤就能实现：

```csharp
float4 Fragment(Interpolators input
#ifdef _DOUBLE_SIDED_NORMALS
	, FRONT_FACE_TYPE frontFace : FRONT_FACE_SEMANTIC
#endif
) : SV_TARGET {
	float2 uv = input.uv;
	float4 colorSample = SAMPLE_TEXTURE2D(_ColorMap, sampler_ColorMap, uv) * _ColorTint;
	TestAlphaClip(colorSample);

	float3 normalWS = normalize(input.normalWS);
	#ifdef _DOUBLE_SIDED_NORMALS
	normalWS *= IS_FRONT_VFACE(frontFace, 1, -1);
	#endif

	return float4((normalWS + 1) * 0.5, 1);
	
	// Code omitted... It would not run anyway!
}
```

**第一步**，将每个分量重新映射到 0 到 1 的范围。由于法线向量是归一化的，长度始终为 1，每个分量的范围是 -1 到 1。通过加 1 再除以 2 来<font style="background-color:#C1E77E;">重新映射</font>。

**第二步**，`Fragment` 输出的是 `float4`，而法线向量是 `float3`。使用 `float4` 构造函数，在法线向量末尾<font style="background-color:#C1E77E;">追加一个 1</font> 来解决这个问题。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787348409608-ff06186c-3aa8-4297-9aa0-2d9ee3091a40.png)

查看结果时，你可以将偏红的值理解为法线指向 X 轴正方向，绿色对应 Y 轴，蓝色对应 Z 轴。嘿！这些颜色刚好和 Unity 的 XYZ 辅助图标对应上了！

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787348422076-60b6b3f3-0404-468c-a890-f2eb24c6061d.png)<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787348431272-dc0958ad-5e37-46d1-a4b9-47f840bda5cb.png)<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787348440376-03d3666f-6db4-4604-a701-2409efc0b5aa.png)<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787348448086-d23bce66-99a3-43c4-9916-1ee4586a5d02.png)<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787348458363-9db739d4-c940-4c44-bd32-1779b0ba5e01.png)<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787348467278-56cdd9bf-d796-4206-bf05-7e33920e3447.png)

_从左上角开始，+X、+Z、-X、-Z、+Y、-Y方向对应的法线颜色_

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787815622733-f4a7f2d3-31de-4f95-ae15-462f167ac491.png)

<font style="color:#117CEE;">我自己也试了下</font>

以下是每个主轴方向对应的颜色：

| 方向 | RGB 颜色 |
| --- | --- |
| +X（右） | (1, 0, 0) 红色 |
| +Y（上） | (0, 1, 0) 绿色 |
| +Z（前） | (0, 0, 1) 蓝色 |
| -X（左） | (0, 0.5, 0.5) 青色 |
| -Y（下） | (0.5, 0, 0.5) 品红 |
| -Z（后） | (0.5, 0.5, 0) 黄色 |


<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787348511921-fc1919d1-7344-458c-8606-131523025535.png)

```csharp
float4 Fragment(Interpolators input
#ifdef _DOUBLE_SIDED_NORMALS
	, FRONT_FACE_TYPE frontFace : FRONT_FACE_SEMANTIC
#endif
) : SV_TARGET {
	float2 uv = input.uv;
	return float4(uv, 0, 1);

  // ... code omitted
}
```

_UV可视化！_

你可以使用这个技巧来可视化任何值！试着输出平滑度、UV 坐标或缩放后的世界坐标。这就是着色器开发中的 `Debug.Log`——虽然有点原始，但遇到问题时这是一个很好的起点！

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787348556930-9c50ddfe-5ccd-406f-8f0b-4fadfa4a990d.png)

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787815715062-b0aac7b4-a25f-40cf-ad33-7ac4ba0735ce.png)

<font style="color:#117CEE;">同样也试了下uv可视化，这些也是一种调试方法，后面要好好利用这种方法进行调试哦</font>

---

## 三、渲染调试器
Unity 2021 有一个名为**渲染调试器（Rendering Debugger）**的新功能，它能自动提供许多常见的输出视图。MyLit 应该已经支持其中不少了！

相关逻辑在 `UniversalFragmentPBR` 内部。许多视图只是输出传入 `InputData` 和 `SurfaceData` 结构体的数据。

```csharp
float4 Fragment(...) : SV_TARGET {
	...
	
	InputData lightingInput = (InputData)0;
	lightingInput.positionWS = input.positionWS;
	lightingInput.normalWS = normalWS;
	lightingInput.viewDirectionWS = GetWorldSpaceNormalizeViewDir(input.positionWS);
	lightingInput.shadowCoord = TransformWorldToShadowCoord(input.positionWS);
#if UNITY_VERSION >= 202120
	lightingInput.positionCS = input.positionCS;
#endif
	
	...
	
	return UniversalFragmentPBR(lightingInput, surfaceInput);
}
```

为了支持更多视图，请在 `InputData` 中<font style="background-color:#C1E77E;">设置裁剪空间位置字段</font>……

```csharp
Shader "NedMakesGames/MyLit" {
    ...

    SubShader {
        Tags {"RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline"}

        Pass {
            Name "ForwardLit"
            ...

            HLSLPROGRAM
            
            #pragma shader_feature_local _ALPHA_CUTOUT
            #pragma shader_feature_local _DOUBLE_SIDED_NORMALS
            
#if UNITY_VERSION >= 202120
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
#else
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
#endif
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
#if UNITY_VERSION >= 202120
            #pragma multi_compile_fragment _ DEBUG_DISPLAY
#endif
            
            #pragma vertex Vertex
            #pragma fragment Fragment
            
            #include "MyLitForwardLitPass.hlsl"
            ENDHLSL
        }
        ...
    }
    ...
}
```

……并在前向光照通道中添加 `<font style="background-color:#C1E77E;">DEBUG_DISPLAY</font>`<font style="background-color:#C1E77E;"></font>着色器特性。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787348591572-1817def2-4d03-4528-b049-ec54067f78f7.png)

_查看反照率，或基础颜色_

仍有一些视图 MyLit 不支持，这种情况下它会显示为全黑或全白。随着本教程系列的推进，这些空白会被逐步填补。但遗憾的是，如果你使用的是 Unity 2020，你只能继续使用传统的调试方法。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787816289479-e1a998a2-71e1-428a-8d04-cd56b978f3db.png)

<font style="color:#117CEE;">设置好后，你可以通过Rendering Debugger来查看Albedo、Specular、Alpha这些</font>

---

## 四、法线贴图与切线空间
如果你使用过 3D 模型，很可能已经用过法线贴图了。它们也被称为凹凸贴图（bump maps），这些纹理编码了方向信息，并修改模型的法线向量。请记住，<font style="background-color:#C1E77E;">法线向量决定了漫反射光照的强度</font>；使用法线贴图，你可以以极低的成本轻松为模型添加细节。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787348614985-15c95762-aca3-4648-b312-4985dff73ecd.png)

_左侧应用了法线贴图。注意前额和手臂上额外的光照细节_

在实现法线贴图之前，让我们先理解它的工作原理。纹理存储的是颜色，但再次强调，颜色本质上就是数字。我们可以将它们解释为归一化的向量，类似于几段前我们输出调试法线的方式。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787348632975-eac697c4-e242-4e16-8b44-821c2c986c1e.png)<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787348643708-7c5aedb9-de7d-4650-9626-2cdbb62f3d8f.png)

_一个编码球体法线向量的示例纹理_

每个像素存储一个向量，被重新映射到 0 到 1 的范围。要反转这个过程，乘以 2 再减去 1。这就得到了一个以零为中心的向量。

```csharp
float4 Fragment(...) : SV_TARGET {
	float2 uv = input.uv;
	float4 normalSample = SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, uv);
    // 向量重映射到颜色的逆过程
	float3 normalWS = normalSample.rgb * 2 - 1;
    // 向量重映射成颜色
	return float4((normalWS + 1) * 0.5, 1);
	
	...
}
```

_这是演示代码，用于说明法线映射的一种简单实现。你的着色器不需要它_

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787348684805-f0d06e9b-7011-488f-9980-2b0a3a3192f8.png)

如果你直接插入一张法线贴图并尝试输出这些向量，它们看起来是不正确的。原因有两个：

**第一**：Unity 以<font style="background-color:#C1E77E;">特殊格式编码</font>法线贴图，针对<font style="background-color:#C1E77E;">法线向量存储</font>进行了优化。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787349471097-6913b669-8f30-4900-95a3-6e399e3ff46e.png)

这就是为什么 Unity 总是<font style="background-color:#C1E77E;">提醒你</font>在导入设置中将<font style="background-color:#C1E77E;">纹理标记为法线贴图</font>。

```csharp
float4 Fragment(...) : SV_TARGET {
	float2 uv = input.uv;
	float4 normalSample = SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, uv);
    // 解码法线贴图纹理采样
	float3 normalWS = UnpackNormal(normalSample);
    // 将法线重映射回颜色
	return float4((normalWS + 1) * 0.5, 1);
}
```

URP 有一个函数来解码法线贴图纹理采样，叫做 `<font style="background-color:#E8F7CF;">UnpackNormal</font>`，它也包含了重新映射的步骤。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787348740744-1bcfec9d-7e06-4478-82ae-da66a678fd92.png)

这些看起来好一些了，但仍然有问题。法线都偏蓝色（指向 Z 方向），而且当物体旋转时它们不会变化。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787896392464-684db51a-2e6b-489e-bbc4-d3da63c93c48.png)<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787896492196-0ddc11cf-6097-47bf-9a02-ef70bd44a149.png)

<font style="color:#117CEE;">采样出来再解码，会得到这样的效果（使用红砖墙的法线贴图）</font>

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787348755565-7ec70647-b3f4-44b4-8399-1d90418dca2e.png)

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787897579625-bb249b47-4a10-45ac-8c15-2c51b69a8a3f.png)<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787897756035-51d91850-bf8e-4cc6-a541-b29591e31849.png)

<font style="color:#117CEE;">这里不return，硬着头皮往下走，得到黑色的渲染结果</font>

```csharp
float3 normalWS = UnpackNormal(colorSample);       // 法线范围 [-1, 1]
normalWS = float4((normalWS + 1) * 0.5, 1);        // 重映射到 [0, 1]
```

<font style="color:#117CEE;">把法线从 [-1, 1] 重映射到了 [0, 1]，然后把这个结果直接拿去当法线用</font>

```csharp
lightingInput.normalWS = normalWS;  // 这不是法线了！
```

<font style="color:#117CEE;">光照计算依赖</font>`<font style="color:#117CEE;">dot(normalWS, lightDir)</font>`<font style="color:#117CEE;">，要求法线分量在 [-1, 1] 范围内。你传进去的是 [0, 1] 范围的值，点积结果完全错误，光照计算失效，所以渲染出来是黑色或很暗。</font>

如果你取法线贴图中存储的向量并用它来计算光照，显然我们漏掉了一步。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787348762339-2f125b5a-12d3-49a4-9349-ec06961284fb.png)<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787348771311-0f45eee5-adbe-4708-afe7-26faea2cc99d.png)

### 切线空间
法线贴图中的向量存在于一个特殊的参考系中，叫做**切线空间（Tangent Space）**。最容易想象的方式是想象一个地球仪：向上指向北极点的外侧，向右和向前则是赤道上互相垂直的两个方向。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787348783323-319e5fe6-0210-45fb-8cc8-088b4f195c73.png)

现在，想象自己站在地球表面。从你的视角看，向上指向头顶，向右沿右臂方向，向前指向面前。你存在于切线空间中！这就是站在网格表面上的物体的视角。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787348791180-5bd1797d-3d19-4762-84d9-55f64765d093.png)

在切线空间中，向上、向右和向前这三个向量有特殊的名称。向上向量很明显就是网格的法线向量。向前和向右的向量分别叫做**切线（Tangent）**和**副切线（Bitangent）**。

<font style="color:#117CEE;">将左手中指朝向法线方向，大拇指方向为切线方向，食指为副切线方向</font>

<font style="color:#117CEE;">Unity的常见坐标系里，观察空间是右手系，其余全为左手系（记忆：右要观察）</font>

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787348814920-46934894-571c-46ef-8492-694b7b62c038.png)<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787348827649-abcf8f2e-8fc7-44bb-bbc7-f0aa446a8db3.png)<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787348837481-e1d62efc-e631-45b1-b68a-e5864c4b106b.png)

注意，这些方向（相对于世界空间）会随着你在地球表面位置的不同而变化。

这很好理解，但在着色器的世界中，光照、摄像机以及所有其他渲染数据都处于世界空间中。如果我们想在光照计算中使用法线向量，它也必须处于世界空间中！

好在，使用**基变换（Change of Basis）**，我们可以轻松地将向量从切线空间转换到世界空间。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787348875016-bb94796d-aa65-49e7-8f5d-2c3ccbc1acd9.png)<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787348880584-d2c9ae88-04b1-4686-b196-2a43616caeb6.png)<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787348886708-86ae5255-d8a7-418d-9d48-0ef7f29bb014.png)

_切线空间到世界空间计算的可视化表示_

**基（Basis）**是坐标轴的数学名称：世界空间中的 X-Y-Z，或切线空间中的 Tangent-Bitangent-Normal。如果你有了一个空间的基方向用另一个空间表示，就很容易在两者之间进行点转换。

在上面的 2D 示例中，我们想将一个点从切线空间转换到世界空间。给定切线和副切线在世界空间中的方向，将每个基方向与点向量中对应的分量相乘，然后求和。(2, 1) 这个点等于切线向量乘以 2 加上副切线向量乘以 1。

<font style="color:#117CEE;">基矢1 = 切线空间的基</font>

<font style="color:#117CEE;">基矢2 = 世界空间的基</font>

<font style="color:#117CEE;">基矢1 × 切线坐标 = 基矢2 × 世界坐标</font>

_<font style="color:#117CEE;">点 × 基矢可以理解为从基矢如何出发到达那个点，既然都是表示如何到那个点，那这两个是可以画等号的</font>_

<font style="color:#117CEE;">基矢2</font><sup><font style="color:#117CEE;">-1</font></sup><font style="color:#117CEE;"> × 基矢1 × 切线坐标 = 基矢2</font><sup><font style="color:#117CEE;">-1</font></sup>_<font style="color:#117CEE;"> </font>_<font style="color:#117CEE;">× 基矢2 × 世界坐标</font>

<font style="color:#117CEE;">即：世界坐标 = 基矢2</font><sup><font style="color:#117CEE;">-1</font></sup><font style="color:#117CEE;"> × 基矢1 × 切线坐标</font>

<font style="color:#117CEE;">把 [基矢2</font><sup><font style="color:#117CEE;">-1</font></sup><font style="color:#117CEE;"> × 基矢1]框起来，叫做TBN矩阵，就这么简单</font>

所以，我们需要获取世界空间中的切线-副切线-法线基方向。我们已经有了法线（通过网格数据获得）。理论上，我们可以任意选择两个互相垂直的向量作为切线和副切线。但在着色器开发中，我们定义切线和副切线使其与模型的 UV 坐标对应。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787348923496-0b56e51f-9ead-42cf-ba60-af25bbc5b28e.png)

回到地球仪，在上面叠加简单的 UV 值，类似于经度和纬度。U 坐标用红色表示，V 坐标用绿色表示。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787348931292-580891d9-d008-4fcc-9c26-b21d989b19ce.png)

切线向量指向 U 值增长的方向。换句话说，如果你沿切线方向行走，脚下的 U 值会不断增加。类似地，副切线指向 V 值增长的方向。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787348940840-30ee437e-bb14-47e5-8076-1c4d360563d9.png)<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787348951900-0e740f51-167e-4a86-bcac-70091f943333.png)<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787348962928-d5fe6794-0ac7-4d44-b14d-4432a9727ba6.png)

这非常完美。由于法线贴图是通过 UV 应用到模型上的纹理，切线和副切线与纹理对齐。如果你展开地球仪，观察沿切线和副切线行走时它们的指向，从法线贴图的角度看，它们始终指向同一个方向。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787348965945-b10b69c9-3156-4235-bad3-d5d3d36bc001.png)

网格将切线和副切线向量作为网格数据流存储，就像法线或位置一样。有了这些，我们现在就拥有了世界空间中完整的切线空间基，可以将从法线贴图中提取的向量转换到世界空间，并用于光照计算。

<font style="color:#117CEE;">顶点着色器：</font>

<font style="color:#117CEE;">读取顶点数据，位置、UV、法线 N、切线 T</font>

<font style="color:#117CEE;">其中N、T用叉积法构建出B，或者利用顶点UV差值计算出T/B，构成TBN矩阵</font>

<font style="color:#117CEE;">还有做一件事就是把世界坐标乘以 VP 矩阵，让世界空间只剩下能在裁剪空间看到的内容</font>

<font style="color:#117CEE;">像素着色器：</font>

<font style="color:#117CEE;">像素着色器从光栅化器拿到插值后的UV后，数据兵分两路</font>

<font style="color:#117CEE;">路径A（获取颜色）：采样漫反射贴图获取颜色，得到的RGB颜色将会和后面的光照结果相乘</font>

<font style="color:#117CEE;">路径B（获取方向向量）：拿到同样的UV采样法线贴图，同样得到RGB颜色，解码颜色变成方向向量</font>

<font style="color:#117CEE;">方向向量乘以TBN矩阵，拿到世界空间下的法线方向</font>

_<font style="color:#117CEE;">怎么理解这个解码呢？</font>_

_<font style="color:#117CEE;">想象一个球，上面每个点都可以建立一个切线空间，然后在这个切线空间下表示法线方向，T、B方向编码后得到趋近于0.5的值，N方向编码后得到趋近1的值，这也就是为什么法线贴图整体偏蓝的原因。</font>_

_<font style="color:#117CEE;">在切线空间有个法线向量，固定这个向量与坐标系的相对位置，该如何旋转基矢让其变的跟世界空间的基矢保持相同的方向呢？</font>_

_<font style="color:#117CEE;">依次操作TBN三个基矢，依次与世界空间的XYZ基矢对齐，记录这个旋转，拼到一起就得到了TBN矩阵，同时方向向量也变成了世界空间的方向向量</font>_

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787940464767-2ae394f1-8089-46a9-9277-cdbf8e241e8b.png)

<font style="color:#117CEE;">仿射变换矩阵（Affine Transformation），右下角1仅为了维持坐标齐次性</font>

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787941018331-1bb55028-41a2-4ed6-b263-e99f9d6e14a3.png)

<font style="color:#117CEE;">路径 B 得到的世界空间法线去计算光照（漫反射、高光），得到的光照强度。光照强度再与路径A得到的颜色相乘，得到最终像素颜色</font>



<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787348990069-3c8aab83-ce05-4ce7-ae98-a3c80b8c095e.png)

呼，数学内容真不少，但我觉得真正理解法线贴图的工作原理很重要。它们是着色器开发的基础！让我们开始编程吧！

---

## 五、添加法线贴图
```csharp
Shader "NedMakesGames/MyLit" {
    Properties{
        [Header(Surface options)]
        [MainTexture] _ColorMap("Color", 2D) = "white" {}
        [MainColor] _ColorTint("Tint", Color) = (1, 1, 1, 1)
        _Cutoff("Alpha cutout threshold", Range(0, 1)) = 0.5
        [NoScaleOffset][Normal] _NormalMap("Normal", 2D) = "bump" {}
        _Smoothness("Smoothness", Range(0, 1)) = 0.5
        
        [HideInInspector] _Cull("Cull mode", Float) = 2 // 2 is "Back"
        [HideInInspector] _SourceBlend("Source blend", Float) = 0
        [HideInInspector] _DestBlend("Destination blend", Float) = 0
        [HideInInspector] _ZWrite("ZWrite", Float) = 0
        [HideInInspector] _SurfaceType("Surface type", Float) = 0
        [HideInInspector] _FaceRenderingMode("Face rendering type", Float) = 0
    }
    
    ...
}
```

首先打开`MyLit.shader`并添加另一个纹理属性。用两个属性标记它。首先，`<font style="background-color:#C1E77E;">NoScaleOffset</font>`属性隐藏检查器中的平铺字段。这是可取的，因为法线贴图应与颜色贴图匹配。其次，这个`Normal`属性提示Unity检查放入其中的任何纹理是否已正确编码。

白色不是法线贴图的好默认颜色。白色，即`(1,1,1)`，会产生未归一化的奇怪法线，指向对角线方向。默认值应表现为没有法线贴图——仅使用网格顶点的法线向量进行光照。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787349727894-60e21bf2-1436-41fa-984e-9a3789e87dcf.png)

_默认法线贴图蓝色_

“bump”默认值为 (0.5, 0.5, 1)，一种类似长春花的颜色，该颜色对应切线空间向量 (0, 0, 1)。

```plain

...

TEXTURE2D(_ColorMap); SAMPLER(sampler_ColorMap);
TEXTURE2D(_NormalMap); SAMPLER(sampler_NormalMap);

...
```

在 `MyLitCommon.hlsl` 中，添加纹理声明：

```plain
struct Attributes {
	float3 positionOS : POSITION; // 仓库的特殊货架1
	float3 normalOS : NORMAL; // 仓库的特殊货架2
	float4 tangentOS : TANGENT; // 仓库的特殊货架3
	float2 uv : TEXCOORD0; // 仓库的一般货架1
};

struct Interpolators {
	float4 positionCS : SV_POSITION; // 车头（永远不插值，必须带路）

	float2 uv : TEXCOORD0; // 1号车厢
	float3 positionWS : TEXCOORD1; // 2号车厢
	float3 normalWS : TEXCOORD2; // 3号车厢
	float4 tangentWS : TEXCOORD3; // 4号车厢
  
  // 加了 nointerpolation，强制不插值！
	// nointerpolation float3 normalWS : TEXCOORD2; 
};
```

<font style="color:#117CEE;">输入时，uv可以走普通货架，其它数据走专用货架</font>

<font style="color:#117CEE;">输出时，系统数据放车头外，其余放哪个车厢无所谓</font>

<font style="color:#117CEE;">扩展：其它语义</font>

`<font style="color:#117CEE;">SV_TARGET</font>`<font style="color:#117CEE;">（输出到渲染目标） </font>

`<font style="color:#117CEE;">nointerpolation</font>`<font style="color:#117CEE;"> 修饰符（禁止插值）</font>

`<font style="color:#117CEE;">nointerpolation</font>`<font style="color:#117CEE;"> 还有些亲戚：</font>

+ `<font style="color:#117CEE;">linear</font>`<font style="color:#117CEE;">：默认就是这个，不用写，代表做透视矫正插值。</font>
+ `<font style="color:#117CEE;">centroid</font>`<font style="color:#117CEE;">：抗锯齿专用。当像素中心点在三角形外时，强制把采样点拉回三角形内部，防止边缘黑边。</font>
+ `<font style="color:#117CEE;">sample</font>`<font style="color:#117CEE;">：强制使用多重采样（MSAA）的特定子像素位置取值，用于精细处理透明纹理边缘。</font>

在前向光照通道中，我们需要网格的切线和副切线向量。切线存储在带有`<font style="background-color:#C1E77E;">TANGENT</font>`语义的顶点数据流中。和`NORMAL` 一样，这些切线向量处于对象空间中。

我之前撒了个小谎……<font style="background-color:#C1E77E;">副切线并非直接存储在网格中</font>。不过，我们可以从法线向量、切线向量和一个特殊的副切线符号值推导出它。Unity 将这个符号值存储在 `TANGENT` 语义的 w 通道中。

<font style="color:#117CEE;">副切线（Bitangent / Binormal）的计算公式：</font>

`<font style="color:#117CEE;">bitangentWS = cross(normalWS, tangentWS.xyz) * tangentWS.w</font>`

`<font style="color:#117CEE;">* tangentWS.w</font>`<font style="color:#117CEE;">：这就是作者说的“符号值”。它不是用来计算长度的，而是用来控制方向的（正负号）</font>

我们还在片元阶段需要切线和副切线，这需要在 `Interpolators` 结构体中<font style="background-color:#C1E77E;">新增一个切线字段</font>。它此时已处于世界空间，同时仍包含副切线符号。用下一个可用的 `TEXCOORD`语义标记它。

```glsl
Interpolators Vertex(Attributes input) {
  Interpolators output;

  // Found in URP/ShaderLib/ShaderVariablesFunctions.hlsl
  VertexPositionInputs posnInputs = GetVertexPositionInputs(input.positionOS);
  VertexNormalInputs normInputs = GetVertexNormalInputs(input.normalOS, input.tangentOS);

  output.positionCS = posnInputs.positionCS;
  output.uv = TRANSFORM_TEX(input.uv, _ColorMap);
  output.normalWS = normInputs.normalWS;
  output.tangentWS = float4(normInputs.tangentWS, input.tangentOS.w);
  output.positionWS = posnInputs.positionWS;

  return output;
}
```

在 `Vertex` 函数中，我们需要将切线向量转换到世界空间。`GetVertexNormalInputs` 函数有一个重载，接受切线向量和副切线符号，输出世界空间切线向量。将其存储在输出中，将副切线符号作为 W 分量传递。

```glsl
float4 Fragment(Interpolators input
                #ifdef _DOUBLE_SIDED_NORMALS
                , FRONT_FACE_TYPE frontFace : FRONT_FACE_SEMANTIC
                #endif
               ) : SV_TARGET {
  float2 uv = input.uv;

  float4 colorSample = SAMPLE_TEXTURE2D(_ColorMap, sampler_ColorMap, uv) * _ColorTint;
  TestAlphaClip(colorSample);

  float3 normalWS = normalize(input.normalWS);
  #ifdef _DOUBLE_SIDED_NORMALS
  normalWS *= IS_FRONT_VFACE(frontFace, 1, -1);
  #endif

  float3 normalTS = UnpackNormal(SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, uv));
  float3x3 tangentToWorld = CreateTangentToWorld(normalWS, input.tangentWS.xyz, input.tangentWS.w);
  normalWS = normalize(TransformTangentToWorld(normalTS, tangentToWorld));

  return float4(normalWS * 0.5 + 0.5, 1);

  ... Code omitted
  }
```

现在 `Fragment` 函数拥有它所需的一切。首先，计算切线空间法线向量。如前所述，Unity 以特殊方式编码法线贴图；使用 URP 函数 `UnpackNormal` 来解码切线空间法线向量。

接下来，计算切线空间基。我们有了法线和切线，但还没有副切线！

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787349962562-71d2a6ec-3111-45a0-a305-d53b2d6c68b7.png)

_两个蓝色向量与红色和绿色向量垂直_

在 3D 空间中，给定任意两个不同方向，恰好有两个方向同时垂直于两者——一个方向及其反方向！使用副切线符号在两者中选择一个向量。URP 会在 `<font style="background-color:#C1E77E;">CreateTangentToWorld</font>`<font style="background-color:#C1E77E;"></font>函数中为我们计算。传入法线向量、切线向量和副切线符号。

它返回一个 `float3x3` 矩阵，本质上就是三个 `float3` 向量叠在一起。你可以将矩阵视为二维数组或向量列表。还记得将向量从切线空间转换到世界空间的公式吗？在 HLSL 中使用矩阵乘法很容易实现。

`TransformTangentToWorld` 函数将切线空间法线向量（来自法线贴图）与切线到世界矩阵相乘，生成世界空间向量。我们将用它来计算光照！

最后一步：归一化这个新的法线以防止舍入误差。该进行测试了！返回法线向量，适当地进行重新映射。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787350004175-58eef8ca-6c8b-4066-bd7f-74eef8b9a628.png)

在场景编辑器中，找一张测试法线贴图，在纹理导入器中将其设置为法线贴图。将其应用到你的材质上，确保一切合理。如果移除法线贴图，显示的颜色不应剧烈变化。旋转模型应该导致法线向量随之旋转。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787350014837-8eb941a2-1a67-45d0-8d6d-ab14196206b2.png)

它甚至支持双面渲染！完美！

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787954210840-36d524a6-b3d0-4e78-9630-f045e4f89194.png)

<font style="color:#117CEE;">好吧，简单的实现了，单法线贴图，没有texture，旋转模型法线也跟着走</font>

```glsl
float4 Fragment(Interpolators input
                #ifdef _DOUBLE_SIDED_NORMALS
                , FRONT_FACE_TYPE frontFace : FRONT_FACE_SEMANTIC
                #endif
               ) : SV_TARGET {
  float2 uv = input.uv;

  float4 colorSample = SAMPLE_TEXTURE2D(_ColorMap, sampler_ColorMap, uv) * _ColorTint;
  TestAlphaClip(colorSample);

  float3 normalWS = normalize(input.normalWS);
  #ifdef _DOUBLE_SIDED_NORMALS
  normalWS *= IS_FRONT_VFACE(frontFace, 1, -1);
  #endif

  float3 normalTS = UnpackNormal(SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, uv));
  float3x3 tangentToWorld = CreateTangentToWorld(normalWS, input.tangentWS.xyz, input.tangentWS.w);
  normalWS = normalize(TransformTangentToWorld(normalTS, tangentToWorld));

  InputData lightingInput = (InputData)0;
  lightingInput.positionWS = input.positionWS;
  lightingInput.normalWS = normalWS;
  lightingInput.viewDirectionWS = GetWorldSpaceNormalizeViewDir(input.positionWS);
  lightingInput.shadowCoord = TransformWorldToShadowCoord(input.positionWS);
  #if UNITY_VERSION >= 202120
  lightingInput.positionCS = input.positionCS;
  #endif

  SurfaceData surfaceInput = (SurfaceData)0;
  surfaceInput.albedo = colorSample.rgb;
  surfaceInput.alpha = colorSample.a;
  surfaceInput.specular = 1;
  surfaceInput.smoothness = _Smoothness;

  return UniversalFragmentPBR(lightingInput, surfaceInput);
}
```

回到代码中，移除测试行。然后在 `lightingData` 中设置法线向量。

<font style="color:#117CEE;">作者其实说的是</font>`<font style="color:#117CEE;">lightingInput.normalWS = normalWS;</font>`<font style="color:#117CEE;">这一行，但是之前做双面渲染时已经用宏来处理</font>`<font style="color:#117CEE;">normalWS</font>`<font style="color:#117CEE;">了，这里只需要删掉测试行，不需要其它额外操作</font>

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787350056355-cc9c8c86-1764-429b-a00d-5586cf3cf8bb.png)

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787954818221-ead3c685-894f-4a0e-891f-663ac812f13e.png)<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787954889775-1610b7bd-7173-4cc9-9cfb-2de0fc3a0f7f.png)

<font style="color:#117CEE;">你将会得到左图，让我们增加Texture上去试试，调整下粗糙度，得到右图，完美！</font>

---

## 六、法线强度
再次将法线贴图应用到你的材质上，惊叹于增加的细节！有时光照效果太强了。有一种简单的方法可以调整法线贴图的强度，而无需编辑纹理。

```glsl
Properties {
  [Header(Surface options)]
  [MainTexture] _ColorMap("Color", 2D) = "white" {}
  [MainColor] _ColorTint("Tint", Color) = (1, 1, 1, 1)
    _Cutoff("Alpha cutout threshold", Range(0, 1)) = 0.5
    [NoScaleOffset][Normal] _NormalMap("Normal", 2D) = "bump" {}
  _NormalStrength("Normal strength", Range(0, 1)) = 1
    _Smoothness("Smoothness", Range(0, 1)) = 0.5

    ...
  }
...
}
```

在 `MyLit.shader` 中添加一个<font style="background-color:#C1E77E;">法线强度属性</font>——通常推荐范围为 0 到 1。

```glsl

...
  TEXTURE2D(_ColorMap); SAMPLER(sampler_ColorMap);
TEXTURE2D(_NormalMap); SAMPLER(sampler_NormalMap);

float4 _ColorMap_ST;
float4 _ColorTint;
float _Cutoff;
float _NormalStrength;
float _Smoothness;
...
```

将声明添加到通用 hlsl 文件中。

```glsl

float4 Fragment(...) : SV_TARGET {
  ...

    float3 normalTS = UnpackNormalScale(SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, uv), _NormalStrength);
  float3x3 tangentToWorld = CreateTangentToWorld(normalWS, input.tangentWS.xyz, input.tangentWS.w);
  normalWS = normalize(TransformTangentToWorld(normalTS, tangentToWorld));

  ...

    return UniversalFragmentPBR(lightingInput, surfaceInput);
}
```

然后，将 `UnpackNormal` 函数替换为 `<font style="background-color:#C1E77E;">UnpackNormalScale</font>`，传入强度值。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787350165891-cf493025-5df8-4172-b99d-206ca1c364f9.png)

就这么简单！

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787955478427-e870b76e-0120-4a1f-a5a2-f4c9fcd781f1.png)

<font style="color:#117CEE;">降低法线强度会让物体看上去变得扁平</font>

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787350182669-3d528f10-1ac0-4be8-9894-b75243e5b551.png)

_左侧使用OpenGL风格的副切线，其中副切线从底部指向顶部。右侧使用DirectX风格的副切线，方向相反，副切线从顶部指向底部_

<font style="color:#117CEE;">看上去是一个凹进去，一个凸出来</font>

---

## 七、调试法线贴图
还有一个细节你需要了解。 选择法线贴图时，URP 和我们的着色器假定副切线指向 V 轴增大的方向，即从法线贴图的底部指向顶部。而某些其他程序使用相反的副切线方向。请确保你的法线贴图遵循“OpenGL”约定，这样就没问题了。

<font style="color:#117CEE;">是的，上面说的这种正是左手系，中指向屏幕内，食指向上，V值增长的方向自然对应法线贴图的底部到顶部</font>

```glsl
float4 Fragment(...) : SV_TARGET {
	...
	
	InputData lightingInput = (InputData)0;
	lightingInput.positionWS = input.positionWS;
	lightingInput.normalWS = normalWS;
	lightingInput.viewDirectionWS = GetWorldSpaceNormalizeViewDir(input.positionWS);
	lightingInput.shadowCoord = TransformWorldToShadowCoord(input.positionWS);
#if UNITY_VERSION >= 202120
	lightingInput.positionCS = input.positionCS;
	// 调试法线贴图，会在渲染调试器中输出额外视图
  lightingInput.tangentToWorld = tangentToWorld; 
#endif
	
	SurfaceData surfaceInput = (SurfaceData)0;
	surfaceInput.albedo = colorSample.rgb;
	surfaceInput.alpha = colorSample.a;
	surfaceInput.specular = 1;
	surfaceInput.smoothness = _Smoothness;
  // normalTS：切线空间法线（Tangent-Space Normal）
	surfaceInput.normalTS = normalTS; // 这纯粹是为了补齐结构体，不影响眼前的光照颜色
	
	return UniversalFragmentPBR(lightingInput, surfaceInput);
}
```

<font style="color:rgb(15, 17, 21);">最后，在 Unity 2021 中，我们可以在渲染器调试器里做更多事情来支持额外视图。在 </font>`<font style="color:rgb(15, 17, 21);background-color:rgb(235, 238, 242);">lightingData</font>`<font style="color:rgb(15, 17, 21);"> 中设置“tangentToWorld”变换矩阵，并在 </font>`<font style="color:rgb(15, 17, 21);background-color:rgb(235, 238, 242);">surfaceInput</font>`<font style="color:rgb(15, 17, 21);"> 中设置切线空间法线。（尽管在 2020 版本中该值未被使用，但 </font>`<font style="color:rgb(15, 17, 21);background-color:rgb(235, 238, 242);">SurfaceData</font>`<font style="color:rgb(15, 17, 21);"> 中确实存在 </font>`<font style="color:rgb(15, 17, 21);background-color:#C1E77E;">normalTS</font>`<font style="color:rgb(15, 17, 21);">字段。）</font>

```glsl
Shader "NedMakesGames/MyLit" {
    ...
    SubShader {
        Tags {"RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline"}

        Pass {
            Name "ForwardLit"
            Tags{"LightMode" = "UniversalForward"}

            ...

            HLSLPROGRAM

            #define _NORMALMAP
            #pragma shader_feature_local _ALPHA_CUTOUT
            #pragma shader_feature_local _DOUBLE_SIDED_NORMALS
            
#if UNITY_VERSION >= 202120
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
#else
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
#endif
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
#if UNITY_VERSION >= 202120
            #pragma multi_compile_fragment _ DEBUG_DISPLAY
#endif
            
            #pragma vertex Vertex
            #pragma fragment Fragment
            
            #include "MyLitForwardLitPass.hlsl"
            ENDHLSL
        }
        ...
    }
    ...
}
```

然后，通过在 `.shader`文件中定义 `_NORMALMAP` 关键字，向调试器表明该着色器支持法线贴图。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787350276316-fe865f64-b124-4085-9677-3849d2ac5cd4.png)

现在，渲染器调试器可以显示切线空间法线，并从光照计算中移除法线贴图的影响。

<font style="color:#E4495B;">注意这里的define，不是pragma，不然会导致</font>`<font style="color:#E4495B;">Lighting Debug Mode</font>`<font style="color:#E4495B;">和</font>`<font style="color:#E4495B;">Lighting Without Normal Maps</font>`<font style="color:#E4495B;">切换但不会有效果而踩坑</font>

<font style="color:#117CEE;">渲染调试器（Rendering Debugger）里有两个独立的辅助诊断功能，你必须把 Shader 里的“数据通道”都打通，这两个功能才能完美工作</font>

1. <font style="color:#117CEE;">显示切线空间法线</font>

`<font style="color:#117CEE;">Rendering Debugger</font>`<font style="color:#117CEE;"> 的 </font>`<font style="color:#117CEE;">Material</font>`<font style="color:#117CEE;"> 面板中，把 </font>`<font style="color:#117CEE;">Material Override</font>`<font style="color:#117CEE;"> 改为 </font>`<font style="color:#117CEE;">NormalTangentSpace</font>`

2. <font style="color:#117CEE;">从光照中移除法线贴图效果</font>

`<font style="color:#117CEE;">Rendering Debugger</font>`<font style="color:#117CEE;">的 </font>`<font style="color:#117CEE;">Lighting</font>`<font style="color:#117CEE;">面板中，把</font>`<font style="color:#117CEE;">Lighting Debug Mode</font>`<font style="color:#117CEE;">改为</font>`<font style="color:#117CEE;">Lighting Without Normal Maps</font>`

<font style="color:#117CEE;">注：与它对应的 </font>`<font style="color:#117CEE;">Lighting With Normal Maps</font>`<font style="color:#117CEE;"> 模式则会保留法线贴图效果，方便你进行对比</font>

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787973724693-78c236c5-d0b3-451c-a7e4-d0ef421f50b0.png)

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1788068268757-50b70a47-2ed1-4802-afed-9b42bb467d7a.png)<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1788068291111-73e91d31-bf61-459c-9513-2d4767932dcc.png)

_<font style="color:#117CEE;">切换Lighting Without（左）/ With（右）Normal Maps</font>_

<font style="color:#117CEE;">切换</font>`<font style="color:#117CEE;">Lighting Without Normal Maps</font>`<font style="color:#117CEE;">（左）和</font>`<font style="color:#117CEE;">Lighting With Normal Maps</font>`<font style="color:#117CEE;">（右）就能看出它们的区别，</font>`<font style="color:#117CEE;">Lighting Without Normal Maps</font>`<font style="color:#117CEE;">基本上是平的法线贴图一样的颜色，右图能看到高低起伏</font>

<font style="color:#117CEE;">两行代码是给 Unity 内部调试工具“喂数据”的。在正式发布的游戏包（Release Build）中，这两行赋值对画面颜色没有一丝一毫的影响，但在开发期（Editor 中）打开渲染调试面板时，它们能让你直观地检查法线贴图是否采样正确、方向是否反了（OpenGL/DirectX 格式问题），以及法线是否被后续的细节贴图正确混合。</font>

<font style="color:#117CEE;">在开启</font>`<font style="color:#117CEE;">NormalTangentSpace</font>`<font style="color:#117CEE;">下，如果注释掉</font>`<font style="color:#117CEE;">surfaceInput.normalTS = normalTS;</font>`<font style="color:#117CEE;">，</font>`<font style="color:#117CEE;">Lighting Without Normal Maps</font>`<font style="color:#117CEE;">视图下便看不到高低起伏的法线</font>

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1788019280526-be67ecb7-2d53-4271-9ab0-2b9b2b523c01.png)

<font style="color:#117CEE;background-color:#C1E77E;">【埋坑】</font><font style="color:#117CEE;">这里初步写了它们的作用，但是我的Unity2023.2.20f1版本下，增减这两行代码没有看出区别</font>

<font style="color:#E4495B;">找到原因了：</font>`<font style="color:#E4495B;">define</font>`<font style="color:#E4495B;">写成了</font>`<font style="color:#E4495B;">pragma</font>`<font style="color:#E4495B;">，上面的调试器部分重新编辑了，这下应该不模糊了</font>

```glsl
// 首先是在MyLitForwardLitPass.hlsl文件下
// ... code omitted
    lightingInput.normalWS = normalWS;
    lightingInput.viewDirectionWS = GetWorldSpaceNormalizeViewDir(input.positionWS);
    lightingInput.shadowCoord = TransformWorldToShadowCoord(input.positionWS);
#if UNITY_VERSION >= 202120
    lightingInput.positionCS = input.positionCS;
    // 调试法线贴图，会在渲染调试器中输出额外视图
    lightingInput.tangentToWorld = tangentToWorld; // 提供转换矩阵
#endif
// ... code omitted

// 其次是在MyLit.shader里
// ... code omitted
Pass{
        Name "ForwardLit" // For debugging
        Tags{"LightMode" = "UniversalForward"}

        // Blend SrcAlpha OneMinusSrcAlpha
        // ZWrite Off
        // 从写死替换为方括号引用属性值，解决材质选择为不透明的情况下，会出现材质未被渲染的情况
        Blend [_SourceBlend] [_DestBlend]
        ZWrite [_ZWrite]
        Cull[_Cull]
        HLSLPROGRAM // Begin HLSL code
            // #define _SPECULAR_COLOR // 切换为 PBR，默认包含镜面高光，此部分不再需要
            #define _NORMALMAP
            #pragma shader_feature_local _ALPHA_CUTOUT
            #pragma shader_feature_local _DOUBLE_SIDED_NORMALS
// ... code omitted
  }
```

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1788068268757-50b70a47-2ed1-4802-afed-9b42bb467d7a.png)<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1788068973292-4c3be8a0-519f-4fa7-989e-73f440b9fb21.png)

<font style="color:#117CEE;">如果没有转换矩阵，会变成右图</font>

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1788069026601-8d88cbd2-8806-4329-9f20-784949010c32.png)<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1788069156239-39b89c39-6487-4752-96ef-81d0872f1014.png)

```glsl
// normalTS：切线空间法线（Tangent-Space Normal）
	surfaceInput.normalTS = normalTS; // 这纯粹是为了补齐结构体，不影响眼前的光照颜色
```

<font style="color:#117CEE;">如果没有传递切线空间法线，则会变成右图【填坑完毕】</font>

以上就是法线贴图的基础知识。其背后有复杂的数学原理，但 URP 能很好地帮你绕过这些，无需过多纠结。务必善用法线贴图，让你的模型更加出彩。

---

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787350401388-6274603c-3f13-4939-9886-00959b773d1e.png)

_左侧启用了金属度贴图。注意鼻子周围更丰富的色彩和更锐利的高光_

## 八、金属工作流
PBR 着色器的一个很酷的方面是它们能够创建金属表面。URP 的 `UniversalFragmentPBR` 函数使金属效果非常容易在我们的着色器中实现！

```glsl
Shader "NedMakesGames/MyLit" {
    Properties {
        [Header(Surface options)]
        [MainTexture] _ColorMap("Color", 2D) = "white" {}
        [MainColor] _ColorTint("Tint", Color) = (1, 1, 1, 1)
        _Cutoff("Alpha cutout threshold", Range(0, 1)) = 0.5
        [NoScaleOffset][Normal] _NormalMap("Normal", 2D) = "bump" {}
        _NormalStrength("Normal strength", Range(0, 1)) = 1
        _Metalness("Metalness", Range(0, 1)) = 0
        _Smoothness("Smoothness", Range(0, 1)) = 0.5
        
        ...
    }
    ...
}
```

首先，在 `MyLit.shader` 中添加一个 `<font style="background-color:#C1E77E;">_Metalness</font>`浮点属性，范围为 0 到 1。

```glsl
...
  TEXTURE2D(_ColorMap); SAMPLER(sampler_ColorMap);
TEXTURE2D(_NormalMap); SAMPLER(sampler_NormalMap);

float4 _ColorMap_ST;
float4 _ColorTint;
float _Cutoff;
float _NormalStrength;
float _Metalness;
float _Smoothness;
...
```

在 `MyLitCommon.hlsl` 中，声明新属性。

```glsl
float4 Fragment(...) : SV_TARGET {
  ...

    SurfaceData surfaceInput = (SurfaceData)0;
  surfaceInput.albedo = colorSample.rgb;
  surfaceInput.alpha = colorSample.a;
  surfaceInput.specular = 1;
  surfaceInput.metallic = _Metalness;
  surfaceInput.smoothness = _Smoothness;
  surfaceInput.normalTS = normalTS;

  return UniversalFragmentPBR(lightingInput, surfaceInput);
}
```

然后，在 `MyLitForwardLitPass.hlsl` 中，将 `surfaceData` 中的金属度字段同步到此属性。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787350481968-4a9cdf9b-a987-4db8-ab3e-3902b0733631.png)

在场景编辑器中试试吧！注意金属强度如何改变高光对材质的影响。现在看起来相当暗，因为反射在金属表面主导了光照。我们将在本系列的下一部分中设置这些！

---

## 九、金属度遮罩
物体很少是完全金属的，如果能沿网格变化金属度会很有帮助。用另一张纹理来实现这一点非常容易！将金属度值存储在纹理中，像颜色贴图和法线贴图一样使用 UV 进行采样。使用纹理来开启或关闭着色器功能通常被称为**遮罩（Masking）**。

```glsl
Shader "NedMakesGames/MyLit" {
    Properties {
        [Header(Surface options)]
        [MainTexture] _ColorMap("Color", 2D) = "white" {}
        [MainColor] _ColorTint("Tint", Color) = (1, 1, 1, 1)
        _Cutoff("Alpha cutout threshold", Range(0, 1)) = 0.5
        [NoScaleOffset][Normal] _NormalMap("Normal", 2D) = "bump" {}
        _NormalStrength("Normal strength", Range(0, 1)) = 1
        [NoScaleOffset] _MetalnessMask("Metalness mask", 2D) = "white" {}
        _Metalness("Metalness strength", Range(0, 1)) = 0
        _Smoothness("Smoothness", Range(0, 1)) = 0.5
        ...
    }
    ...
}
```

在着色器文件中，为<font style="background-color:#C1E77E;">金属度遮罩</font>添加另一个纹理属性……

```glsl
...
TEXTURE2D(_ColorMap); SAMPLER(sampler_ColorMap);
TEXTURE2D(_NormalMap); SAMPLER(sampler_NormalMap);
TEXTURE2D(_MetalnessMask); SAMPLER(sampler_MetalnessMask);

float4 _ColorMap_ST;
float4 _ColorTint;
float _Cutoff;
float _NormalStrength;
float _Metalness;
float _Smoothness;
...
```

……并将新属性添加到通用 HLSL 文件中。

```glsl
float4 Fragment(...) : SV_TARGET {
	...
	SurfaceData surfaceInput = (SurfaceData)0;
	surfaceInput.albedo = colorSample.rgb;
	surfaceInput.alpha = colorSample.a;
	surfaceInput.specular = 1;
	surfaceInput.metallic = 
      SAMPLE_TEXTURE2D(_MetalnessMask, sampler_MetalnessMask, uv).r * _Metalness;
	surfaceInput.smoothness = _Smoothness;
	surfaceInput.normalTS = normalTS;
	
	return UniversalFragmentPBR(lightingInput, surfaceInput);
}
```

在`Fragment`函数中，<font style="background-color:#C1E77E;">采样金属度遮罩</font>。由于<font style="background-color:#D9EAFC;">金属度</font>是一个浮点数，只保存<font style="background-color:#F8B881;">红色通道</font>的值。将其与`<font style="background-color:#FCE75A;">_Metalness</font>`属性相乘，并在 `surfaceData` 中设置它。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787350532859-3f9a9e66-d8db-40bd-958c-a828d0731fd3.png)

回到 Unity，在材质中设置金属度纹理。由于此纹理编码的是特殊数据而非颜色，最好在纹理导入器中关闭 sRGB 设置。对于任何存储数据的纹理（如遮罩或查找表），都应关闭此选项。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1788064988933-0b373c72-2d83-4e62-9751-834899210374.png)

<font style="color:#117CEE;background-color:#FFFFFF;">关闭sRGB设置后，球体确实变量了，色彩更加还原了</font>

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1788067060092-61e69bd6-d386-4a7b-8fce-c19d89af1991.png)<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1788067076499-9964837c-d4b2-47e0-85f9-eeaf93c7e2fa.png)

<font style="color:#117CEE;">这里金属度拉上去，然后光滑度拉上去，看到的是这种效果</font>

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787350650513-3ba4b2d0-299c-4bb0-ab09-05c9928b578c.png)

无论如何，只有遮罩为白色的区域才应呈现金属质感。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787350655677-7fd222cc-2f9c-4db1-9c93-2909bdd49be2.png)

你可以通过在渲染调试器中查看金属度视图模式（或输出金属度强度）来验证这一点。将遮罩放入颜色贴图槽中与你的遮罩进行对比。  
<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1788067438001-ecae67a1-4792-4e69-8fc4-b3065a94a8fb.png)

<font style="color:#117CEE;">是的，在这个视图下，我的渲染目标现实为大块白色，但是实际上渲染的效果没有那么金属</font>

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787350681148-bd9f0165-1bda-4ee8-bf10-b6aeca2743a6.png)

_这把小提琴使用高光工作流，按金属区域指定高光颜色。_

---

## 十、高光工作流
Lit 着色器实际上有两种不同的模式来处理金属表面：**金属工作流（Metallic Workflow）**和**高光工作流（Specular Workflow）**。高光工作流使用高光颜色纹理来确定模型上高光的颜色。高光颜色的亮度控制该点的金属度。

```glsl
Shader "NedMakesGames/MyLit" {
    Properties {
        [Header(Surface options)]
        [MainTexture] _ColorMap("Color", 2D) = "white" {}
        [MainColor] _ColorTint("Tint", Color) = (1, 1, 1, 1)
        _Cutoff("Alpha cutout threshold", Range(0, 1)) = 0.5
        [NoScaleOffset][Normal] _NormalMap("Normal", 2D) = "bump" {}
        _NormalStrength("Normal strength", Range(0, 1)) = 1
        [NoScaleOffset] _MetalnessMask("Metalness mask", 2D) = "white" {}
        _Metalness("Metalness strength", Range(0, 1)) = 0
        [NoScaleOffset] _SpecularMap("Specular map", 2D) = "white" {}
        _SpecularTint("Specular tint", Color) = (1, 1, 1, 1)
        _Smoothness("Smoothness", Range(0, 1)) = 0.5
        ...
    }

    SubShader {
        Tags {"RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline"}

        Pass {
            Name "ForwardLit"
            ...

            HLSLPROGRAM

            #define _NORMALMAP
            #pragma shader_feature_local _ALPHA_CUTOUT
            #pragma shader_feature_local _DOUBLE_SIDED_NORMALS
            #define _SPECULAR_SETUP
            
#if UNITY_VERSION >= 202120
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
#else
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
#endif
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
#if UNITY_VERSION >= 202120
            #pragma multi_compile_fragment _ DEBUG_DISPLAY
#endif
            
            #pragma vertex Vertex
            #pragma fragment Fragment
            
            #include "MyLitForwardLitPass.hlsl"
            ENDHLSL
        }
        ...
    }
    ...
}
```

要启用高光工作流，首先在 `MyLit.shader` 的前向光照通道块中 `#define _SPECULAR_SETUP` 这个关键字。我们还需要高光纹理和色调的属性。

```glsl

...
  TEXTURE2D(_ColorMap); SAMPLER(sampler_ColorMap);
TEXTURE2D(_NormalMap); SAMPLER(sampler_NormalMap);
TEXTURE2D(_MetalnessMask); SAMPLER(sampler_MetalnessMask);
TEXTURE2D(_SpecularMap); SAMPLER(sampler_SpecularMap);

float4 _ColorMap_ST;
float4 _ColorTint;
float _Cutoff;
float _NormalStrength;
float _Metalness;
float3 _SpecularTint;
float _Smoothness;
...
```

在 `MyLitCommon.hlsl` 中也定义它们。

```glsl
float4 Fragment(...) : SV_TARGET {
  ...
    SurfaceData surfaceInput = (SurfaceData)0;
  surfaceInput.albedo = colorSample.rgb;
  surfaceInput.alpha = colorSample.a;
  #ifdef _SPECULAR_SETUP
  surfaceInput.specular = SAMPLE_TEXTURE2D(_SpecularMap, sampler_SpecularMap, uv).rgb * _SpecularTint;
  surfaceInput.metallic = 0;
  #else
  surfaceInput.specular = 1;
  surfaceInput.metallic = SAMPLE_TEXTURE2D(_MetalnessMask, sampler_MetalnessMask, uv).r * _Metalness;
  #endif
  surfaceInput.smoothness = _Smoothness;
  surfaceInput.normalTS = normalTS;

  return UniversalFragmentPBR(lightingInput, surfaceInput);
}
```

在 `MyLitForwardLitPass.hlsl` 的 `Fragment`函数中，采样高光贴图并将颜色乘以高光色调。在高光工作流模式下，`UniversalFragmentPBR`实际上会<font style="background-color:#C1E77E;">忽略金属度值</font>。使用 `#if` 块，仅在启用 `_SPECULAR_SETUP` 时设置高光颜色，否则设置金属度。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787350739613-62d68244-c3a1-4f25-9b26-266ec49e5771.png)

在场景视图中，尝试添加一张彩色的高光纹理，看看效果如何！很炫酷。注意高光颜色有点像是表面颜色的补色——这就是光学原理在起作用！

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787350746200-c6b15776-6764-43ce-bf08-c10e37f0ba68.png)

你还可以在渲染调试器中检查高光颜色。

你可能注意到我们使用了一个关键字来在<font style="background-color:#C1E77E;">金属和高光工作流之间切换</font>。很容易添加一个属性来切换关键字的开关，无需自定义 Inspector 代码！

```glsl
Shader "NedMakesGames/MyLit" {
  Properties {
    [Header(Surface options)]
    [MainTexture] _ColorMap("Color", 2D) = "white" {}
    [MainColor] _ColorTint("Tint", Color) = (1, 1, 1, 1)
      _Cutoff("Alpha cutout threshold", Range(0, 1)) = 0.5
      [NoScaleOffset][Normal] _NormalMap("Normal", 2D) = "bump" {}
    _NormalStrength("Normal strength", Range(0, 1)) = 1
      [NoScaleOffset] _MetalnessMask("Metalness mask", 2D) = "white" {}
    _Metalness("Metalness strength", Range(0, 1)) = 0
      [Toggle(_SPECULAR_SETUP)] _SpecularSetupToggle("Use specular workflow", Float) = 0
      [NoScaleOffset] _SpecularMap("Specular map", 2D) = "white" {}
    _SpecularTint("Specular tint", Color) = (1, 1, 1, 1)
      _Smoothness("Smoothness", Range(0, 1)) = 0.5
      ...
    }
  SubShader {
    Tags {"RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline"}

    Pass {
      Name "ForwardLit"
        ...
        HLSLPROGRAM

        #define _NORMALMAP
        #pragma shader_feature_local _ALPHA_CUTOUT
        #pragma shader_feature_local _DOUBLE_SIDED_NORMALS
        #pragma shader_feature_local_fragment _SPECULAR_SETUP
        ...
        #include "MyLitForwardLitPass.hlsl"
        ENDHLSL
      }
    ...
    }
  ...
  }
```

在 `MyLit.shader` 中，添加一个带有特殊 `Toggle` 属性的浮点属性。要启用和禁用的关键字名称放在属性内部。属性名称无关紧要，选一个相关的就好。最后，将属性值设为零以默认禁用关键字。

在前向光照通道块中，将 `<font style="background-color:#C1E77E;">#define</font>`<font style="background-color:#C1E77E;"> 替换为 </font>`<font style="background-color:#C1E77E;">#pragma shader_feature_local_fragment</font>`。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787350800400-401651b7-cf5f-429a-935a-c5ff71ff1fb5.png)

在场景编辑器中，你现在可以轻松地在金属模式和高光模式之间切换。

**<font style="color:#117CEE;">复习：MR工作流和SG工作流</font>**

<font style="color:#117CEE;">M/R：当前实时渲染的主流（UE4/5、Unity、Substance Painter 默认），因兼容性广且对美术更友好。</font>

<font style="color:#117CEE;">S/G：多见于离线渲染（V-Ray、Arnold 旧版）或需要精确控制 F0 的老管线，现在正逐渐被 M/R 取代，但在制作宝石、水晶等特殊非金属时仍有优势。</font>

[https://www.yuque.com/duanmuyifeng/ogufkr/spqin2plhev6k3gz#brSuu](https://www.yuque.com/duanmuyifeng/ogufkr/spqin2plhev6k3gz#brSuu)

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1788134623299-f8d67290-b74c-4b6a-a5a6-528f8cbf17b7.png)<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1788134552169-7cc6f441-195e-456a-b76b-531fde8b6e72.png)

1. <font style="color:#117CEE;">高光工作流渲染的确实是要亮一些。</font>
2. <font style="color:#117CEE;">在使用specular map后，渲染调试器里在Specular视图里看到了这个贴图</font>

---

## 十一、平滑度遮罩
说到镜面光照，如果能沿模型表面变化平滑度就太好了。我们可以用另一张<font style="background-color:#FFFFFF;">遮罩纹理</font>来实现，这次存储的是平滑度值。

```glsl
Shader "NedMakesGames/MyLit" {
    Properties {
        [Header(Surface options)]
        [MainTexture] _ColorMap("Color", 2D) = "white" {}
        [MainColor] _ColorTint("Tint", Color) = (1, 1, 1, 1)
        _Cutoff("Alpha cutout threshold", Range(0, 1)) = 0.5
        [NoScaleOffset][Normal] _NormalMap("Normal", 2D) = "bump" {}
        _NormalStrength("Normal strength", Range(0, 1)) = 1
        [NoScaleOffset] _MetalnessMask("Metalness mask", 2D) = "white" {}
        _Metalness("Metalness strength", Range(0, 1)) = 0
        [Toggle(_SPECULAR_SETUP)] _SpecularSetupToggle("Use specular workflow", Float) = 0
        [NoScaleOffset] _SpecularMap("Specular map", 2D) = "white" {}
        _SpecularTint("Specular tint", Color) = (1, 1, 1, 1)
        [NoScaleOffset] _SmoothnessMask("Smoothness mask", 2D) = "white" {}
        _Smoothness("Smoothness multiplier", Range(0, 1)) = 0.5
        ...
    }
    ...
}
```

在着色器属性中<font style="background-color:#C1E77E;">添加一个平滑度纹理</font>……

```glsl
...
TEXTURE2D(_ColorMap); SAMPLER(sampler_ColorMap);
TEXTURE2D(_NormalMap); SAMPLER(sampler_NormalMap);
TEXTURE2D(_MetalnessMask); SAMPLER(sampler_MetalnessMask);
TEXTURE2D(_SpecularMap); SAMPLER(sampler_SpecularMap);
TEXTURE2D(_SmoothnessMask); SAMPLER(sampler_SmoothnessMask);

float4 _ColorMap_ST;
float4 _ColorTint;
float _Cutoff;
float _NormalStrength;
float _Metalness;
float3 _SpecularTint;
float _Smoothness;
...
```

……在<font style="background-color:#E8F7CF;">通用文件中声明</font>它……

```glsl
float4 Fragment(...) : SV_TARGET {
	...
	SurfaceData surfaceInput = (SurfaceData)0;
	surfaceInput.albedo = colorSample.rgb;
	surfaceInput.alpha = colorSample.a;
#ifdef _SPECULAR_SETUP
	surfaceInput.specular = SAMPLE_TEXTURE2D(_SpecularMap, sampler_SpecularMap, uv).rgb * _SpecularTint;
	surfaceInput.metallic = 0;
#else
	surfaceInput.specular = 1;
	surfaceInput.metallic = SAMPLE_TEXTURE2D(_MetalnessMask, sampler_MetalnessMask, uv).r * _Metalness;
#endif
	surfaceInput.smoothness = SAMPLE_TEXTURE2D(_SmoothnessMask, sampler_SmoothnessMask, uv).r * _Smoothness;
  // surfaceInput.metallic = _Metalness;  // 这个值已经在采样时乘过去了，不需要再单独赋值了
  // surfaceInput.smoothness = _Smoothness; // 同上
  surfaceInput.normalTS = normalTS;
	
	return UniversalFragmentPBR(lightingInput, surfaceInput);
}
```

……并在前向光照通道的片元函数中采样它。使用红色通道，将其与<font style="background-color:#C1E77E;">预先存在</font>的 `<font style="background-color:#C1E77E;">_Smoothness</font>`属性相乘，并在 `surfaceData` 中设置它。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787350858072-fcb9e6f4-080c-49db-a5cd-08dab989dc10.png)

在场景编辑器中，尝试添加一张平滑度遮罩。同样要关闭 sRGB。太酷了，这些纹理效果非常显著！

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1788143229584-85cfd89f-d37a-4767-b136-cb6b7a34344a.png)

<font style="color:#117CEE;">带有污渍（遮罩）的金属面</font>

如果你使用过其他 3D 软件，可能会看到有些使用<font style="background-color:#D9EAFC;">光泽度（gloss 或 glossiness）</font>贴图——这只是<font style="background-color:#D9EAFC;">平滑度贴图</font>的<font style="background-color:#D9EAFC;">另一个名称</font>。还有一些使用<font style="background-color:#C1E77E;">粗糙度（roughness）</font>遮罩，它只是<font style="background-color:#C1E77E;">平滑度的反值</font>。换句话说，平滑度等于 1 减去粗糙度。

```glsl
  float smoothnessSample = SAMPLE_TEXTURE2D(_SmoothnessMask, sampler_SmoothnessMask, uv).r * _Smoothness;
#ifdef _ROUGHNESS_SETUP
	smoothnessSample = 1 - smoothnessSample;
#endif
	surfaceInput.smoothness = smoothnessSample;
```

_这是示例代码——你不需要将其添加到你的着色器中_

如果你想在着色器中使用粗糙度，只需在设置到 `surfaceData` 之前将纹理采样值取反即可。你甚至可以添加一个属性来可选地执行此操作！不过，在本教程的其余部分，我只支持简单的平滑度遮罩。

我知道有着色器经验的人可能会对我们为所有这些遮罩使用单独的纹理感到不安。在本教程结束时，我会解释如何优化一下。暂时先把这个放在脑后。

<font style="color:#117CEE;">对，这个地方是可以缩减贴图数量的，这个在PBR流程博客里面有讲到</font>

[https://www.yuque.com/duanmuyifeng/ogufkr/spqin2plhev6k3gz#brSuu](https://www.yuque.com/duanmuyifeng/ogufkr/spqin2plhev6k3gz#brSuu)

<font style="color:#117CEE;">另外，上方的示例代码，我在着色器里面进行了适配，因为我下载的贴图是roughness贴图，我不得不适配他们。</font>

---

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787350919435-7554ff96-7757-4b6f-b8ae-39f2f509cd11.png)

## 十二、透明混合模式
MyLit 已经具备完整的透明度支持，但 URP 的 Lit 着色器还有几个额外的透明模式我们可以添加：**Additive（加法）**、**Multiply（乘法）**和 **Premultiplied（预乘）**。加法和乘法模式对粒子非常有用，而<font style="background-color:#C1E77E;">预乘模式</font>有助于<font style="background-color:#C1E77E;">模拟玻璃</font>。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787350934648-b3c7d003-4975-4cf6-bee3-526f7cd885bf.png)<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787350950800-a290f783-c8a5-4f67-8d2b-02198e01b1dd.png)

_加法粒子与乘法粒子_

```csharp
using UnityEditor;
using UnityEngine;
using UnityEngine.Rendering;

public class MyLitCustomInspector : ShaderGUI {

    public enum SurfaceType {
        Opaque, TransparentBlend, TransparentCutout
        }

    public enum FaceRenderingMode {
        FrontOnly, NoCulling, DoubleSided
        }

    public enum BlendType {
        Alpha, Premultiplied, Additive, Multiply
        }

    public override void AssignNewShaderToMaterial(Material material, Shader oldShader, Shader newShader) {
        ...
        }

    public override void ValidateMaterial(Material material) {
        ...
        }

    public override void OnGUI(MaterialEditor materialEditor, MaterialProperty[] properties) {

        Material material = materialEditor.target as Material;
        var surfaceProp = BaseShaderGUI.FindProperty("_SurfaceType", properties, true);
        var blendProp = BaseShaderGUI.FindProperty("_BlendType", properties, true);
        var faceProp = BaseShaderGUI.FindProperty("_FaceRenderingMode", properties, true);

        EditorGUI.BeginChangeCheck();

        #if UNITY_2022_1_OR_NEWER
            MaterialEditor.BeginProperty(surfaceProp);
        #endif
            surfaceProp.floatValue = (int)(SurfaceType)EditorGUILayout.EnumPopup("Surface type", (SurfaceType)surfaceProp.floatValue);
        #if UNITY_2022_1_OR_NEWER
            MaterialEditor.EndProperty();
        #endif

        #if UNITY_2022_1_OR_NEWER
            MaterialEditor.BeginProperty(blendProp);
        #endif
            blendProp.floatValue = (int)(BlendType)EditorGUILayout.EnumPopup("Blend type", (BlendType)blendProp.floatValue);
        #if UNITY_2022_1_OR_NEWER
            MaterialEditor.EndProperty();
        #endif

        #if UNITY_2022_1_OR_NEWER
            MaterialEditor.BeginProperty(faceProp);
        #endif
            faceProp.floatValue = (int)(FaceRenderingMode)EditorGUILayout.EnumPopup("Face rendering mode", (FaceRenderingMode)faceProp.floatValue);
        #if UNITY_2022_1_OR_NEWER
            MaterialEditor.EndProperty();
        #endif

            if(EditorGUI.EndChangeCheck()) {
                UpdateSurfaceType(material);
            }
        base.OnGUI(materialEditor, properties);
    }

    private void UpdateSurfaceType(Material material) {
        SurfaceType surface = (SurfaceType)material.GetFloat("_SurfaceType");
        ...

            BlendType blend = (BlendType)material.GetFloat("_BlendType");
        switch(surface) {
            case SurfaceType.Opaque:
            case SurfaceType.TransparentCutout:
                material.SetInt("_SourceBlend", (int)BlendMode.One);
                material.SetInt("_DestBlend", (int)BlendMode.Zero);
                material.SetInt("_ZWrite", 1);
                break;
            // 半透明混合分支
            case SurfaceType.TransparentBlend:
                switch(blend) {
                    // 标准半透明子分支
                    case BlendType.Alpha:
                        material.SetInt("_SourceBlend", (int)BlendMode.SrcAlpha);
                        material.SetInt("_DestBlend", (int)BlendMode.OneMinusSrcAlpha);
                        break;
                    // 预乘半透明，玻璃效果子分支
                    case BlendType.Premultiplied:
                        material.SetInt("_SourceBlend", (int)BlendMode.One);
                        material.SetInt("_DestBlend", (int)BlendMode.OneMinusSrcAlpha);
                    break;
                    // 加法混合子分支，提亮场景
                    case BlendType.Additive:
                        material.SetInt("_SourceBlend", (int)BlendMode.SrcAlpha);
                        material.SetInt("_DestBlend", (int)BlendMode.One);
                        break;
                    // 乘法混合子分支，变暗场景
                    case BlendType.Multiply:
                        material.SetInt("_SourceBlend", (int)BlendMode.Zero);
                        material.SetInt("_DestBlend", (int)BlendMode.SrcColor);
                        break;
            }
            material.SetInt("_ZWrite", 0);
            break;
        }
        ...
    }
}
```

这段工作的主体在于自定义Inspector。新增一个`<font style="background-color:#C1E77E;">BlendType</font>`枚举，包含我们将要支持的四种混合模式：`Alpha`、`Premultiplied`、`Additive`和`Multiply`。为了存储当前选中的混合模式，我们还需要添加一个属性`_BlendType`，处理方式与`_SurfaceType`类似。在`OnGUI`函数中获取和设置这个新属性。

这些混合模式之间的主要区别在于它们所使用的<font style="background-color:#E8F7CF;">源混合因子</font>和<font style="background-color:#E8F7CF;">目标混合因子</font>。请记住，这些因子指示渲染器如何将片元函数输出的颜色与屏幕上的已有颜色进行组合。在`<font style="background-color:#C1E77E;">UpdateSurfaceType</font>`函数中，读取`<font style="background-color:#E8F7CF;">BlendType</font>`属性。在设置混合模式的`switch`语句中，在`TransparentBlend`分支内部再添加一个`switch`。在该内部`switch`中，为每种情况设置相应的源混合因子和目标混合因子。

| 模式 | 源混合（Src） | 目标混合（Dst） | 效果 |
| --- | --- | --- | --- |
| **Alpha** | SrcAlpha | OneMinusSrcAlpha | 标准半透明 |
| **Premultiplied** | One | OneMinusSrcAlpha | 预乘 Alpha，玻璃效果 |
| **Additive** | SrcAlpha | One | 加法混合，提亮场景 |
| **Multiply** | DstColor | Zero | 乘法混合，变暗场景 |


**Alpha** 模式就像我们习惯的那样，基于源像素的 Alpha 值进行混合。在此模式下，光栅化器将源颜色乘以 Alpha 值，目标颜色乘以 1 减去 Alpha 值，然后将它们相加。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787351014512-87d5a0fd-b97d-4ed0-beca-b60b613f1e18.png)

_相机镜头和取景器窗口使用预乘Alpha来模拟玻璃效果_

**Premultiplied** 模式假设 Alpha 已经与颜色相乘并存储在纹理的 RGB 值中。这就解释了名称——Alpha 已被预先相乘。在这种情况下，源混合类型应为 One，这样 Alpha 不会被再次应用，但目标仍应像正常情况一样表现。预乘 Alpha 为美术提供了更好的控制——实际上，更亮的像素更不透明。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787351045861-0962aef3-7cd8-4052-b2c6-605bb6a5a9cd.png)

**Additive** 模式在数学上是 **Premultiplied** 模式的逆。在此模式下，源受 Alpha 影响，但目标不受影响。目标颜色只会被叠加。加法模式会提亮场景，非常适合火焰和闪电等粒子效果。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787351086054-6f736ecc-8a18-45a4-aa29-9c9c4da02961.png)

最后，**Multiply**模式用于特殊用途。它使用一种新的混合模式`<font style="background-color:#F1A2AB;">SrcColor</font>`，即源像素的RGB值。Multiply模式完全忽略Alpha，只是将源和目标相乘。它会使<font style="background-color:#F1A2AB;">场景变暗</font>；有时可用于<font style="background-color:#F1A2AB;">异世界效果</font>和<font style="background-color:#F1A2AB;">遮罩</font>。

```glsl
Shader "NedMakesGames/MyLit" {
    Properties {
        ...
        [HideInInspector] _Cull("Cull mode", Float) = 2 // 2 is "Back"
        [HideInInspector] _SourceBlend("Source blend", Float) = 0
        [HideInInspector] _DestBlend("Destination blend", Float) = 0
        [HideInInspector] _ZWrite("ZWrite", Float) = 0
        [HideInInspector] _SurfaceType("Surface type", Float) = 0
        [HideInInspector] _BlendType("Blend type", Float) = 0
        [HideInInspector] _FaceRenderingMode("Face rendering type", Float) = 0
    }
    ...
}
```

在 `MyLit.shader` 中，别忘了添加新的 `<font style="background-color:#C1E77E;">_BlendType</font>`<font style="background-color:#C1E77E;"></font>属性。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787351127862-76e5d635-4327-4bf2-8507-f03db8c1e9e0.png)

在场景中查看新模式！只需操纵混合模式就能获得这么多效果，真酷。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1788160069143-3eb6bfce-22e5-4a21-b164-9458c8a266f6.png)

<font style="color:#117CEE;">没错，按照上述的代码逻辑，我也整出来了这个效果</font>

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1788161202358-52a41961-71d9-48b7-bc37-e3bc77d8a487.png)

```csharp
// ... code omitted
            case SurfaceType.TransparentBlend:
                switch (blend)
                {
                    // 标准半透明子分支
                    case BlendType.Alpha:
                        material.SetInt("_SourceBlend", (int)BlendMode.SrcAlpha);
                        material.SetInt("_DestBlend", (int)BlendMode.OneMinusSrcAlpha);
                        break;
                    // 预乘半透明，玻璃效果子分支
                    case BlendType.Premultiplied:
                        material.SetInt("_SourceBlend", (int)BlendMode.One);
                        material.SetInt("_DestBlend", (int)BlendMode.OneMinusSrcAlpha);
                        // 这一行得到更加像玻璃的效果
                        material.EnableKeyword("_PERMULTIPLY");
                        break;
// ... code omitted
```

```glsl
// ... code omitted

// Premultiplied模式下得到更像玻璃的效果
#ifdef _PREMULTIPLY
surfaceInput.albedo *= surfaceInput.alpha; // 预乘
#endif
return UniversalFragmentPBR(lightingInput, surfaceInput);
}

#endif
```

<font style="color:#117CEE;">接着我对</font>`<font style="color:#117CEE;">Premultiplied</font>`<font style="color:#117CEE;">做了下处理，给</font>`<font style="color:#117CEE;">albedo</font>`<font style="color:#117CEE;">预乘了</font>`<font style="color:#117CEE;">alpha</font>`<font style="color:#117CEE;">的值，看起来更像玻璃效果了</font>

<font style="color:#117CEE;">注意哦，这种写法不规范，下面作者”预乘模式的高光不透明度“给出的这种才是规范的操作，我的这个改动已经在代码里面删除，现在使用的是作者的方案，二者的效果是相同的</font>

---

## 十三、预乘模式的高光不透明度
URP 通过让光照影响材质的 Alpha 进一步增强了 **Premultiplied** 模式。它对玻璃非常有用，高光区域看起来是不透明的。`UniversalFragmentPBR` 处理了所有事情，我们只需启用一个关键字：`<font style="background-color:#C1E77E;">_ALPHAPREMULTIPLY_ON</font>`。

```glsl
    ...
    private void UpdateSurfaceType(Material material) {
        SurfaceType surface = (SurfaceType)material.GetFloat("_SurfaceType");
        ...

        BlendType blend = (BlendType)material.GetFloat("_BlendType");
        switch(surface) {
            ...
        }
        if(surface == SurfaceType.TransparentBlend && blend == BlendType.Premultiplied) {
            material.EnableKeyword("_ALPHAPREMULTIPLY_ON");
        } else {
            material.DisableKeyword("_ALPHAPREMULTIPLY_ON");
        }
        ...
    }
    ...
```

回到自定义 Inspector，适当地启用或禁用该关键字。

```glsl
Shader "NedMakesGames/MyLit" {
    ...
    SubShader {
        Tags {"RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline"}

        Pass {
            Name "ForwardLit"
            ...
            HLSLPROGRAM

            #define _NORMALMAP
            #pragma shader_feature_local _ALPHA_CUTOUT
            #pragma shader_feature_local _DOUBLE_SIDED_NORMALS
            #pragma shader_feature_local_fragment _SPECULAR_SETUP
            #pragma shader_feature_local_fragment _ALPHAPREMULTIPLY_ON
            ...
            #include "MyLitForwardLitPass.hlsl"
            ENDHLSL
        }
        ...
    }
    ...
}
```

然后，在 `MyLit.shader` 中，向前向光照通道添加一个着色器特性。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787351230702-74a7a735-940f-4190-9ffa-8b6b039b2cf8.png)

在场景编辑器中试试吧！高光确实看起来更不透明了。

---

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787351254162-23fabf9a-26ca-4ecd-9d48-50a39219b9e4.png)

_自发光给人一种前大灯在发光的错觉_

## 十四、自发光
有些物体，如电子设备或魔法神器，有发光的部件。用真正的灯光来实现这些精细细节太昂贵了，但我们可以用**自发光纹理（Emission Texture）**尽力而为！它定义了网格上的发光区域。

```glsl
Shader "NedMakesGames/MyLit" {
    Properties {
        [Header(Surface options)]
        [MainTexture] _ColorMap("Color", 2D) = "white" {}
        [MainColor] _ColorTint("Tint", Color) = (1, 1, 1, 1)
        _Cutoff("Alpha cutout threshold", Range(0, 1)) = 0.5
        [NoScaleOffset][Normal] _NormalMap("Normal", 2D) = "bump" {}
        _NormalStrength("Normal strength", Range(0, 1)) = 1
        [NoScaleOffset] _MetalnessMask("Metalness mask", 2D) = "white" {}
        _Metalness("Metalness strength", Range(0, 1)) = 0
        [Toggle(_SPECULAR_SETUP)] _SpecularSetupToggle("Use specular workflow", Float) = 0
        [NoScaleOffset] _SpecularMap("Specular map", 2D) = "white" {}
        _SpecularTint("Specular tint", Color) = (1, 1, 1, 1)
        [NoScaleOffset] _SmoothnessMask("Smoothness mask", 2D) = "white" {}
        _Smoothness("Smoothness multiplier", Range(0, 1)) = 0.5
        [NoScaleOffset] _EmissionMap("Emission map", 2D) = "white" {}
        [HDR]_EmissionTint("Emission tint", Color) = (0, 0, 0, 0)
        ...
    }
    ...
}
```

自发光很容易实现！在 `MyLit.shader` 中添加一个<font style="background-color:#C1E77E;">自发光纹理属性</font>，以及一个<font style="background-color:#E8F7CF;">自发光色调</font>。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787351306253-d7bf2cd9-581d-4436-aa08-ae01b2085223.png)

`HDR` 属性将色调标记为高动态范围颜色，意味着其分量可以取大于 1 的值。这与某些后处理效果（如泛光 Bloom）结合使用很有用。我们会在本系列后面的教程中详细讨论。

```glsl
...
TEXTURE2D(_ColorMap); SAMPLER(sampler_ColorMap);
TEXTURE2D(_NormalMap); SAMPLER(sampler_NormalMap);
TEXTURE2D(_MetalnessMask); SAMPLER(sampler_MetalnessMask);
TEXTURE2D(_SpecularMap); SAMPLER(sampler_SpecularMap);
TEXTURE2D(_SmoothnessMask); SAMPLER(sampler_SmoothnessMask);
TEXTURE2D(_EmissionMap); SAMPLER(sampler_EmissionMap);

float4 _ColorMap_ST;
float4 _ColorTint;
float _Cutoff;
float _NormalStrength;
float _Metalness;
float3 _SpecularTint;
float _Smoothness;
float3 _EmissionTint;
...
```

将新属性添加到通用 HLSL 文件中。

```glsl
float4 Fragment(...) : SV_TARGET {
	...
	SurfaceData surfaceInput = (SurfaceData)0;
	surfaceInput.albedo = colorSample.rgb;
	surfaceInput.alpha = colorSample.a;
#ifdef _SPECULAR_SETUP
	surfaceInput.specular = SAMPLE_TEXTURE2D(_SpecularMap, sampler_SpecularMap, uv).rgb * _SpecularTint;
	surfaceInput.metallic = 0;
#else
	surfaceInput.specular = 1;
	surfaceInput.metallic = SAMPLE_TEXTURE2D(_MetalnessMask, sampler_MetalnessMask, uv).r * _Metalness;
#endif
	surfaceInput.smoothness = SAMPLE_TEXTURE2D(_SmoothnessMask, sampler_SmoothnessMask, uv).r * _Smoothness;
	surfaceInput.emission = SAMPLE_TEXTURE2D(_EmissionMap, sampler_EmissionMap, uv).rgb * _EmissionTint;
	surfaceInput.normalTS = normalTS;
	
	return UniversalFragmentPBR(lightingInput, surfaceInput);
}
```

然后在前向光照 `Fragment` 函数中<font style="background-color:#C1E77E;">采样自发光纹理</font>。将其与 `<font style="background-color:#E8F7CF;">_EmissionTint</font>`<font style="background-color:#E8F7CF;"></font>相乘并存储在 `surfaceData` 中。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787351351416-ebd03191-9177-477d-954f-079871f102e9.png)

这就是支持自发光所需的全部。通过获取一张自发光纹理并调整自发光色调来测试。请注意，如果自发光色调为<font style="background-color:#C1E77E;">黑色</font>，则<font style="background-color:#C1E77E;">不会</font>出现<font style="background-color:#C1E77E;">自发光</font>。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787351361413-ad6be796-3040-4fed-877c-2b3576564ba6.png)

你可以在渲染调试器中查看自发光。如果想暂时禁用它，可以使用光照特性枚举中的一个选项来实现。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1788168676184-239bca4e-5823-4902-9dcd-4be716a969bf.png)<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1788168761561-2e38cd8c-5b25-4090-b816-b6893983e53f.png)

<font style="color:#117CEE;">自发光已搞定，在Rendering Debugger里先点击everything，再去掉勾选自发光，可以关掉自发光</font>

自发光通过忽略阴影和使受影响区域过曝来工作，遗憾的是它实际上并不会照亮场景。我们可以通过将其与烘焙光照结合来解决这个问题，这将在本系列的第 5 部分中实现！

---

<font style="color:rgba(0, 0, 0, 0.8);">视频不见了</font>

_<font style="color:rgba(0, 0, 0, 0.8);">视频右半部分有视差遮挡映射，UV根据视角和高度图偏移</font>_<font style="color:rgba(0, 0, 0, 0.8);"></font>

## 十五、视差遮挡映射
URP 的 Complex Lit 着色器有几个很酷的选项值得我们关注，首先是**视差（Parallax）**。视差是一种通过根据纹理与摄像机的距离滚动纹理来<font style="background-color:#C1E77E;">模拟深度</font>的方法。我们可以移动 UV 来模拟材质中的小凹坑！

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787351485334-c6747143-56fd-4314-aa11-fdbd8d1ca6e5.png)

_沙纹理的高度图_

让我们看看它是如何工作的。首先，我们需要另一张名为高度图（Height Map）或<font style="background-color:#C1E77E;">位移图（Displacement Map）</font>的纹理，用来确定哪些区域低于表面。白色像素在网格表面上，而黑色像素则低于表面。

<font style="color:#117CEE;">下载的纹理里面有纹理提供了位移图</font>

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787351482624-dbaef598-47c5-4f2e-b78d-84b9357835f3.png)<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787351482725-7dd01e06-38fd-446d-901a-914b4c07bca6.png)

_蓝色线条是视线，它穿过原始UV，与变形表面的碰撞__<font style="background-color:#C1E77E;">产生新的UV</font>_

接下来，假装这张高度图实际上使网格变形了。当评估特定 UV 坐标的视差时，从摄像机投射一条射线，穿过 UV，直到它击中想象中的变形表面。将撞击点投影回纹理上，使用该新的 UV 坐标来采样颜色贴图、法线贴图等。

通过这种方式，UV 会根据视线方向发生变化——对于被高度图压低的区域变化更大。这种效果产生了深度的错觉。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1788169306974-fd06a774-1096-49f1-8c19-b1ac8b1dc39b.png)

<font style="color:#117CEE;">就是说现在的uv采样不是完全死的，如图中这个采样点会变化，而且坑越大uv采样位置偏移的越多，所以产生了深度的错觉</font>

```glsl
Shader "NedMakesGames/MyLit" {
    Properties {
        [Header(Surface options)]
        [MainTexture] _ColorMap("Color", 2D) = "white" {}
        [MainColor] _ColorTint("Tint", Color) = (1, 1, 1, 1)
        _Cutoff("Alpha cutout threshold", Range(0, 1)) = 0.5
        [NoScaleOffset][Normal] _NormalMap("Normal", 2D) = "bump" {}
        _NormalStrength("Normal strength", Range(0, 1)) = 1
        [NoScaleOffset] _MetalnessMask("Metalness mask", 2D) = "white" {}
        _Metalness("Metalness strength", Range(0, 1)) = 0
        [Toggle(_SPECULAR_SETUP)] _SpecularSetupToggle("Use specular workflow", Float) = 0
        [NoScaleOffset] _SpecularMap("Specular map", 2D) = "white" {}
        _SpecularTint("Specular tint", Color) = (1, 1, 1, 1)
        [NoScaleOffset] _SmoothnessMask("Smoothness mask", 2D) = "white" {}
        _Smoothness("Smoothness multiplier", Range(0, 1)) = 0.5
        [NoScaleOffset] _EmissionMap("Emission map", 2D) = "white" {}
        [HDR] _EmissionTint("Emission tint", Color) = (0, 0, 0, 0)
        [NoScaleOffset] _ParallaxMap("Height/displacement map", 2D) = "white" {}
        _ParallaxStrength("Parallax strength", Range(0, 1)) = 0.005
        ...
    }
    ...
}
```

幸运的是，光线投射等背后的所有数学都由 URP 函数处理。首先，在 `MyLit.shader` 中添加<font style="background-color:#C1E77E;">高度图</font>和<font style="background-color:#E8F7CF;">视差强度</font>属性。

```glsl
...
  TEXTURE2D(_ColorMap); SAMPLER(sampler_ColorMap);
TEXTURE2D(_NormalMap); SAMPLER(sampler_NormalMap);
TEXTURE2D(_MetalnessMask); SAMPLER(sampler_MetalnessMask);
TEXTURE2D(_SpecularMap); SAMPLER(sampler_SpecularMap);
TEXTURE2D(_SmoothnessMask); SAMPLER(sampler_SmoothnessMask);
TEXTURE2D(_EmissionMap); SAMPLER(sampler_EmissionMap);
TEXTURE2D(_ParallaxMap); SAMPLER(sampler_ParallaxMap);

float4 _ColorMap_ST;
float4 _ColorTint;
float _Cutoff;
float _NormalStrength;
float _Metalness;
float3 _SpecularTint;
float _Smoothness;
float3 _EmissionTint;
float _ParallaxStrength;
...
```

在 `MyLitCommon.hlsl` 中，添加这些新属性的声明。

```glsl
...
#include "MyLitCommon.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/ParallaxMapping.hlsl"

...

float4 Fragment(Interpolators input
#ifdef _DOUBLE_SIDED_NORMALS
	, FRONT_FACE_TYPE frontFace : FRONT_FACE_SEMANTIC
#endif
) : SV_TARGET {
	float3 normalWS = input.normalWS;
#ifdef _DOUBLE_SIDED_NORMALS
	normalWS *= IS_FRONT_VFACE(frontFace, 1, -1);
#endif

	float3 positionWS = input.positionWS;
	float3 viewDirWS = GetWorldSpaceNormalizeViewDir(positionWS); // In ShaderVariablesFunctions.hlsl
	float3 viewDirTS = GetViewDirectionTangentSpace(input.tangentWS, normalWS, viewDirWS); // In ParallaxMapping.hlsl
	
	float2 uv = input.uv;
	uv += ParallaxMapping(TEXTURE2D_ARGS(_ParallaxMap, sampler_ParallaxMap), viewDirTS, _ParallaxStrength, uv);

	float4 colorSample = SAMPLE_TEXTURE2D(_ColorMap, sampler_ColorMap, uv) * _ColorTint;
	TestAlphaClip(colorSample);

	float3 normalTS = UnpackNormalScale(SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, uv), _NormalStrength);
	float3x3 tangentToWorld = CreateTangentToWorld(normalWS, input.tangentWS.xyz, input.tangentWS.w);
	normalWS = normalize(TransformTangentToWorld(normalTS, tangentToWorld));
	
	InputData lightingInput = (InputData)0;
	lightingInput.positionWS = positionWS;
	lightingInput.normalWS = normalWS;
	lightingInput.viewDirectionWS = viewDirWS;
	lightingInput.shadowCoord = TransformWorldToShadowCoord(positionWS);
#if UNITY_VERSION >= 202120
	lightingInput.positionCS = input.positionCS;
	lightingInput.tangentToWorld = tangentToWorld;
#endif
	
	SurfaceData surfaceInput = (SurfaceData)0;
	surfaceInput.albedo = colorSample.rgb;
	surfaceInput.alpha = colorSample.a;
#ifdef _SPECULAR_SETUP
	surfaceInput.specular = SAMPLE_TEXTURE2D(_SpecularMap, sampler_SpecularMap, uv).rgb * _SpecularTint;
	surfaceInput.metallic = 0;
#else
	surfaceInput.specular = 1;
	surfaceInput.metallic = SAMPLE_TEXTURE2D(_MetalnessMask, sampler_MetalnessMask, uv).r * _Metalness;
#endif
	surfaceInput.smoothness = SAMPLE_TEXTURE2D(_SmoothnessMask, sampler_SmoothnessMask, uv).r * _Smoothness;
	surfaceInput.emission = SAMPLE_TEXTURE2D(_EmissionMap, sampler_EmissionMap, uv).rgb * _EmissionTint;
	surfaceInput.normalTS = normalTS;
	
	return UniversalFragmentPBR(lightingInput, surfaceInput);
}
```

在 `MyLitForwardLitPass.hlsl` 中，重新排列代码，使法线和视线方向<font style="background-color:#C1E77E;">在任何纹理采样之前计算</font>。我们需要根据这些值计算新的 UV！在此过程中，在整个函数中使用这些 `positionWS` 和 `viewDirectionWS` 变量，而不是 `input` 中的值。

视差遮挡映射算法需要<font style="background-color:#D9EAFC;">切线空间中的视线方向</font>，因为高度图形成的想象表面存在于切线空间中。URP 提供了一个 `<font style="background-color:#D9EAFC;">GetViewDirectionTangentSpace</font>`函数来实现这一点。包含 SRP 的 `<font style="background-color:#F1A2AB;">ParallaxMapping.hlsl</font>` 文件使其可用，并传入世界空间切线（带副切线符号）、法线和视线方向向量。`GetViewDirectionTangentSpace` 需要处于未归一化状态的顶点法线，这是需要记住的重要信息！

现在调用神奇的 `<font style="background-color:#CEF5F7;">ParallaxMapping</font>`函数来完成工作。它需要高度图和采样器。要将纹理和采样器传递给函数，必须使用这个特殊的宏：`<font style="background-color:#E8F7CF;">TEXTURE2D_ARGS</font>`。它的存在是为了规避平台差异，类似于纹理声明。

然后，将切线空间视线方向、视差强度属性和当前 UV 传递给 `ParallaxMapping`。`ParallaxMapping` 返回根据上面解释的视差算法偏移 UV 的量。将偏移量添加到当前 UV 上，并在采样所有其他纹理时务必使用这个新的 UV。

在场景中查看效果！找一张高度图并设置视差强度。不需要太多就能产生非常强烈的效果！通常 0.05 左右的视差强度就足够了。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1788172414552-4eb35d6c-ce64-4087-863a-6078f6c9787b.png)

<font style="color:#117CEE;">有效果，这里设置了Parallax strength为0.1，数值设置过大会产生畸变，给我的感觉emm...一般</font>

<font style="color:#117CEE;">好消息是我顺手修复了另一个bug，之前在fragment里加关键字框住法线采样，但是加上后法线一直平平的，找到原因了！</font>

`<font style="color:#117CEE;">shader_feature_local</font>`<font style="color:#117CEE;"> 关键字需要你在 C# 中显式调用 </font>`<font style="color:#117CEE;">material.EnableKeyword("_NORMALMAP") </font>`<font style="color:#117CEE;">才能激活对应的 </font>`<font style="color:#117CEE;">shader variant</font>`<font style="color:#117CEE;">。</font>

```glsl
// MyLitCustomInspector.cs
// ...code omitted
// 这里是增加玻璃效果的，和我写在里面那种效果一样，但那边那个我已经注释掉
        if(surface == SurfaceType.TransparentBlend && blend == BlendType.Premultiplied)
        {
            material.EnableKeyword("_ALPHAPREMULTIPLY_ON");
        }
        else
        {
            material.DisableKeyword("_ALPHAPREMULTIPLY_ON");
        }
        // shader_feature_local 关键字需要你在 C# 中显式调用才能激活变体
        // 根据是否分配了法线贴图来启用/禁用 _NORMALMAP 关键字
        if (material.GetTexture("_NormalMap"))
        {
            material.EnableKeyword("_NORMALMAP");
        }
        else
        {
            material.DisableKeyword("_NORMALMAP");
        }
        // 处理阴影，只要不是半透明混合模式就投射阴影
        material.SetShaderPassEnabled("ShadowCaster", surface != SurfaceType.TransparentBlend);
        
        if(surface == SurfaceType.TransparentCutout)
        {
            material.EnableKeyword("_ALPHA_CUTOUT");
        }
        else
        {
            material.DisableKeyword("_ALPHA_CUTOUT");
        }
// ...code omitted
```

这就是 Complex Lit 视差映射的全部内容，但我们还可以做更多。你有兴趣在另一个教程系列中了解更多吗？请告诉我。

---

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787351745976-b79f3dbf-c265-4842-995c-7daf80643d17.png)

_右侧应用了清漆遮罩_

## 十六、清漆效果
除了视差，Complex Lit 着色器中还隐藏着一个高级功能：**清漆（Clear Coat）**！你知道汽车油漆上的光亮涂层吗？清漆可以重现这种效果。

```glsl
Shader "NedMakesGames/MyLit" {
    Properties {
        [Header(Surface options)]
        [MainTexture] _ColorMap("Color", 2D) = "white" {}
        [MainColor] _ColorTint("Tint", Color) = (1, 1, 1, 1)
        _Cutoff("Alpha cutout threshold", Range(0, 1)) = 0.5
        [NoScaleOffset][Normal] _NormalMap("Normal", 2D) = "bump" {}
        _NormalStrength("Normal strength", Range(0, 1)) = 1
        [NoScaleOffset] _MetalnessMask("Metalness mask", 2D) = "white" {}
        _Metalness("Metalness strength", Range(0, 1)) = 0
        [Toggle(_SPECULAR_SETUP)] _SpecularSetupToggle("Use specular workflow", Float) = 0
        [NoScaleOffset] _SpecularMap("Specular map", 2D) = "white" {}
        _SpecularTint("Specular tint", Color) = (1, 1, 1, 1)
        [NoScaleOffset] _SmoothnessMask("Smoothness mask", 2D) = "white" {}
        _Smoothness("Smoothness multiplier", Range(0, 1)) = 0.5
        [NoScaleOffset] _EmissionMap("Emission map", 2D) = "white" {}
        [HDR] _EmissionTint("Emission tint", Color) = (0, 0, 0, 0)
        [NoScaleOffset] _ParallaxMap("Height/displacement map", 2D) = "white" {}
        _ParallaxStrength("Parallax strength", Range(0, 1)) = 0.005
        [NoScaleOffset] _ClearCoatMask("Clear coat mask", 2D) = "white" {}
        _ClearCoatStrength("Clear coat strength", Range(0, 1)) = 0
        [NoScaleOffset] _ClearCoatSmoothnessMask("Clear coat smoothness mask", 2D) = "white" {}
        _ClearCoatSmoothness("Clear coat smoothness", Range(0, 1)) = 0
        ...
    }

    SubShader {
        Tags {"RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline"}

        Pass {
            Name "ForwardLit"
            ...
            HLSLPROGRAM

            #define _NORMALMAP
            #define _CLEARCOATMAP
            #pragma shader_feature_local _ALPHA_CUTOUT
            #pragma shader_feature_local _DOUBLE_SIDED_NORMALS
            #pragma shader_feature_local_fragment _SPECULAR_SETUP
            #pragma shader_feature_local_fragment _ALPHAPREMULTIPLY_ON
            
#if UNITY_VERSION >= 202120
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
#else
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
#endif
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
#if UNITY_VERSION >= 202120
            #pragma multi_compile_fragment _ DEBUG_DISPLAY
#endif
            
            #pragma vertex Vertex
            #pragma fragment Fragment
            
            #include "MyLitForwardLitPass.hlsl"
            ENDHLSL
        }
        ...
    }
    ...
}
```

和之前的自发光一样，它很容易实现。添加一个<font style="background-color:#C1E77E;">清漆强度遮罩</font>和<font style="background-color:#C1E77E;">浮点属性</font>。清漆模拟表面上方的一层透明涂层，因此它可以有自己独立的平滑度值。同时添加<font style="background-color:#E8F7CF;">清漆平滑度遮罩</font>和<font style="background-color:#E8F7CF;">强度属性</font>。在前向光照通道块中，定义 `<font style="background-color:#D9EAFC;">_CLEARCOATMAP</font>`关键字，以便 `UniversalFragmentPBR` 包含相关计算。

```glsl
...
TEXTURE2D(_ColorMap); SAMPLER(sampler_ColorMap);
TEXTURE2D(_NormalMap); SAMPLER(sampler_NormalMap);
TEXTURE2D(_MetalnessMask); SAMPLER(sampler_MetalnessMask);
TEXTURE2D(_SpecularMap); SAMPLER(sampler_SpecularMap);
TEXTURE2D(_SmoothnessMask); SAMPLER(sampler_SmoothnessMask);
TEXTURE2D(_EmissionMap); SAMPLER(sampler_EmissionMap);
TEXTURE2D(_ParallaxMap); SAMPLER(sampler_ParallaxMap);
TEXTURE2D(_ClearCoatMask); SAMPLER(sampler_ClearCoatMask);
TEXTURE2D(_ClearCoatSmoothnessMask); SAMPLER(sampler_ClearCoatSmoothnessMask);

float4 _ColorMap_ST;
float4 _ColorTint;
float _Cutoff;
float _NormalStrength;
float _Metalness;
float3 _SpecularTint;
float _Smoothness;
float3 _EmissionTint;
float _ParallaxStrength;
float _ClearCoatStrength;
float _ClearCoatSmoothness;
...
```

在 `MyLitCommon.hlsl` 中，定义新的纹理和浮点属性。

```glsl
float4 Fragment(...) : SV_TARGET {
	...
	SurfaceData surfaceInput = (SurfaceData)0;
	surfaceInput.albedo = colorSample.rgb;
	surfaceInput.alpha = colorSample.a;
#ifdef _SPECULAR_SETUP
	surfaceInput.specular = SAMPLE_TEXTURE2D(_SpecularMap, sampler_SpecularMap, uv).rgb * _SpecularTint;
	surfaceInput.metallic = 0;
#else
	surfaceInput.specular = 1;
	surfaceInput.metallic = SAMPLE_TEXTURE2D(_MetalnessMask, sampler_MetalnessMask, uv).r * _Metalness;
#endif
	surfaceInput.smoothness = SAMPLE_TEXTURE2D(_SmoothnessMask, sampler_SmoothnessMask, uv).r * _Smoothness;
	surfaceInput.emission = SAMPLE_TEXTURE2D(_EmissionMap, sampler_EmissionMap, uv).rgb * _EmissionTint;
	surfaceInput.clearCoatMask = SAMPLE_TEXTURE2D(_ClearCoatMask, sampler_ClearCoatMask, uv).r * _ClearCoatStrength;
	surfaceInput.clearCoatSmoothness = SAMPLE_TEXTURE2D(_ClearCoatSmoothnessMask, sampler_ClearCoatSmoothnessMask, uv).r * _ClearCoatSmoothness;
	surfaceInput.normalTS = normalTS;
	
	return UniversalFragmentPBR(lightingInput, surfaceInput);
}
```

在 `MyLitForwardLitPass.hlsl` 中，<font style="background-color:#C1E77E;">采样遮罩</font>，取它们的<font style="background-color:#F1A2AB;">红色通道</font>并与浮点属性相乘。设置 `surfaceInput` 中的 `<font style="background-color:#C1E77E;">clearCoatMask</font>`<font style="background-color:#C1E77E;"></font>和 `<font style="background-color:#E8F7CF;">clearCoatSmoothness</font>`字段。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787351893359-b3303169-1dc3-4762-951d-24f3ec0b9883.png)

基本上就是这样！清漆对许多不同的物体都很有用，比如汽车、家具甚至糖果。但它很昂贵，基本上每个材质需要两次 BRDF 计算。如果不需要，考虑将其省略。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1788175093656-f5621060-570c-4e62-b2b4-a62b96177e3b.png)

<font style="color:#117CEE;">确实能调出清漆的效果，这里我对代码进行了一些修改，几处优化</font>

1. <font style="color:#117CEE;">增加清漆采样守卫关键字</font>
2. <font style="color:#117CEE;">将</font>`<font style="color:#117CEE;">define</font>`<font style="color:#117CEE;">变成变体模式适配关键字</font>
3. <font style="color:#117CEE;">在C#里面显式调用清漆关键字</font>

---

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787351923001-d23cf5ad-f051-432c-80f5-befe295c6f2d.png)

## 十七、优化纹理使用
掌握了清漆之后，我们几乎支持 URP 内置的所有表面选项。然而，我们的着色器已经膨胀了不少，现在是时候考虑精简它了。

在本教程系列的后续部分，我会坚持使用这个通用的、未优化的着色器。但是，一旦你确切知道你的个人着色器需要哪些功能，请重新审视本节中的技巧来加速并使其更易于使用。

### 第一步：确定你需要哪些功能
总是使用金属工作流？移除对高光工作流的支持，包括高光颜色纹理和色调。移除昂贵的功能（如清漆、视差或法线贴图）是值得的。也可以使用关键字来按需开启或关闭功能。

### 可选功能
例如，假设只有部分材质需要法线贴图。我们可以设置 Inspector，当<font style="background-color:#C1E77E;">未分配法线贴图</font>纹理时<font style="background-color:#C1E77E;">禁用一个关键字</font>。

```glsl
...
public class MyLitCustomInspector : ShaderGUI {
    ...

    public override void OnGUI(MaterialEditor materialEditor, MaterialProperty[] properties) {
        Material material = materialEditor.target as Material;
        var surfaceProp = BaseShaderGUI.FindProperty("_SurfaceType", properties, true);
        var blendProp = BaseShaderGUI.FindProperty("_BlendType", properties, true);
        var faceProp = BaseShaderGUI.FindProperty("_FaceRenderingMode", properties, true);
        
        EditorGUI.BeginChangeCheck();
        
#if UNITY_2022_1_OR_NEWER
        MaterialEditor.BeginProperty(surfaceProp);
#endif
        surfaceProp.floatValue = (int)(SurfaceType)EditorGUILayout.EnumPopup("Surface type", (SurfaceType)surfaceProp.floatValue);
#if UNITY_2022_1_OR_NEWER
        MaterialEditor.EndProperty();
#endif

#if UNITY_2022_1_OR_NEWER
        MaterialEditor.BeginProperty(blendProp);
#endif
        blendProp.floatValue = (int)(BlendType)EditorGUILayout.EnumPopup("Blend type", (BlendType)blendProp.floatValue);
#if UNITY_2022_1_OR_NEWER
        MaterialEditor.EndProperty();
#endif
        
#if UNITY_2022_1_OR_NEWER
        MaterialEditor.BeginProperty(faceProp);
#endif
        faceProp.floatValue = (int)(FaceRenderingMode)EditorGUILayout.EnumPopup("Face rendering mode", (FaceRenderingMode)faceProp.floatValue);
#if UNITY_2022_1_OR_NEWER
        MaterialEditor.EndProperty();
#endif
        // 这个函数移动位置了
        base.OnGUI(materialEditor, properties);
        
        if(EditorGUI.EndChangeCheck()) {
            UpdateSurfaceType(material);
        }
    }

    private void UpdateSurfaceType(Material material) {
        ...
        if(material.GetTexture("_NormalMap") == null) {
            material.DisableKeyword("_NORMALMAP");
        } else {
            material.EnableKeyword("_NORMALMAP");
        }
    }
}
```

在 `MyLitCustomInspector` 的 `UpdateSurfaceType` 函数中，对材质使用 `<font style="background-color:#C1E77E;">GetTexture</font>`。根据返回值是否为 null 来启用或禁用 `<font style="background-color:#E8F7CF;">_NORMALMAP</font>`关键字。

为了在法线贴图更改时调用 `UpdateSurfaceType`，将 `<font style="background-color:#CEF5F7;">base.OnGUI</font>` 调用移到 `<font style="background-color:#CEF5F7;">Begin-</font>` 和 `<font style="background-color:#CEF5F7;">EndChangeCheck</font>`之间。

```glsl
Shader "NedMakesGames/MyLit" {
    ...
    SubShader {
        Tags {"RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline"}

        Pass {
            Name "ForwardLit"
            ...
            HLSLPROGRAM

            #pragma shader_feature_local_fragment _NORMALMAP
            #define _CLEARCOATMAP
            #pragma shader_feature_local _ALPHA_CUTOUT
            #pragma shader_feature_local _DOUBLE_SIDED_NORMALS
            #pragma shader_feature_local_fragment _SPECULAR_SETUP
            #pragma shader_feature_local_fragment _ALPHAPREMULTIPLY_ON
            
#if UNITY_VERSION >= 202120
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
#else
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
#endif
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
#if UNITY_VERSION >= 202120
            #pragma multi_compile_fragment _ DEBUG_DISPLAY
#endif
            
            #pragma vertex Vertex
            #pragma fragment Fragment
            
            #include "MyLitForwardLitPass.hlsl"
            ENDHLSL
        }
        ...
    }
    ...
}
```

在 `MyLit.shader` 中，将 `#define` 改为 `<font style="background-color:#C1E77E;">#pragma shader_feature</font>`。

```glsl
float4 Fragment(...) : SV_TARGET {
  ...
    #ifdef _NORMALMAP
    float3 normalTS = UnpackNormalScale(SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, uv), _NormalStrength);
  float3x3 tangentToWorld = CreateTangentToWorld(normalWS, input.tangentWS.xyz, input.tangentWS.w);
  normalWS = normalize(TransformTangentToWorld(normalTS, tangentToWorld));
  #else
  float3 normalTS = float3(0, 0, 1);
  float3x3 tangentToWorld = float3x3(1, 0, 0, 0, 1, 0, 0, 0, 1);
  normalWS = normalize(normalWS);
  #endif
  ...
    return UniversalFragmentPBR(lightingInput, surfaceInput);
}
```

在 `MyLitForwardLitPass.hlsl` 中，如果未定义 `<font style="background-color:#C1E77E;">_NORMALMAP</font>`，则使用网格的法线向量。这对应于 `float3(0, 0, 1)` 的切线空间法线向量。

<font style="color:#117CEE;">从这里还算正常，但是我尝试移除视差映射时，出现了连续报错，暂时先到这里吧，我得自己单独研究怎么精简shader了，至于后续的纹理打包，这个了解到可以这样操作就可以了，其实不难，但是需要多通道贴图，这个是美术那边该考虑的事情，抓住主要矛盾，暂时不搞这部分</font>

```glsl
struct Interpolators {
	float4 positionCS : SV_POSITION;

	float2 uv : TEXCOORD0;
	float3 positionWS : TEXCOORD1;
	float3 normalWS : TEXCOORD2;
#ifdef _NORMALMAP
	float4 tangentWS : TEXCOORD3;
#endif
};
```

如果你更进一步<font style="background-color:#C1E77E;">移除视差映射</font>，你就完全<font style="background-color:#C1E77E;">不需要切线</font>了。保持 `Interpolators` 结构体尽可能小对性能很重要，因为<font style="background-color:#F1A2AB;">每个变量</font>都是光栅化器<font style="background-color:#F1A2AB;">需要插值</font>的更多数据。在那里使用关键字效果很好。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787352031044-d4863e3f-2296-4c28-b0b7-14d0372b43bd.png)

_四个遮罩纹理合并为一个_

### 纹理通道打包
另一个有用的技巧是**纹理通道打包（Texture Channel Packing）**。注意各种遮罩纹理只使用了纹理的红色通道。如果我们将几张遮罩合并到一张纹理中会怎样？例如，我们可以将金属度遮罩放入红色通道，平滑度放入绿色通道，清漆强度放入蓝色通道，清漆平滑度放入 Alpha 通道。

```glsl
float4 Fragment(...) : SV_TARGET {
	...
	SurfaceData surfaceInput = (SurfaceData)0;
	float4 masks = SAMPLE_TEXTURE2D(_Mask, sampler_Mask, uv);
	surfaceInput.albedo = colorSample.rgb;
	surfaceInput.alpha = colorSample.a;
	surfaceInput.specular = 1;
	surfaceInput.metallic = masks.r * _Metalness;
	surfaceInput.smoothness = masks.g * _Smoothness;
	surfaceInput.emission = SAMPLE_TEXTURE2D(_EmissionMap, sampler_EmissionMap, uv).rgb * _EmissionTint;
	surfaceInput.clearCoatMask = masks.b * _ClearCoatStrength;
	surfaceInput.clearCoatSmoothness = masks.a * _ClearCoatSmoothness;
	surfaceInput.normalTS = normalTS;
	
	return UniversalFragmentPBR(lightingInput, surfaceInput);
}
```

_金属度、光滑度、清漆和清漆光滑度被打包到一张纹理中_

纹理采样是一个巨大的资源消耗，尤其是在移动平台上，将四次采样合并为一次非常棒！你可以使用 Photoshop 或任何其他照片编辑软件来构建此纹理。将每个遮罩视为灰度纹理，并将它们分别放入一个颜色通道中。

```glsl
float4 Fragment(...) : SV_TARGET {
	...
	SurfaceData surfaceInput = (SurfaceData)0;
	float4 colorSmoothnessSample = SAMPLE_TEXTURE2D(_ColorSmoothnessMap, sampler_ColorSmoothnessMap, uv);
	surfaceInput.albedo = colorSmoothnessSample.rgb * _ColorTint.rgb;
	surfaceInput.alpha = 1;
	surfaceInput.specular = 1;
	surfaceInput.metallic = 0;
	surfaceInput.smoothness = colorSmoothnessSample.a * _Smoothness;
	surfaceInput.emission = 0;
	surfaceInput.clearCoatMask = 0;
	surfaceInput.clearCoatSmoothness = 0;
	surfaceInput.normalTS = normalTS;
	
	return UniversalFragmentPBR(lightingInput, surfaceInput);
}
```

_一个简单的不透明着色器，其中光滑度遮罩被打包到颜色贴图的alpha通道中_

很多时候 Alpha 通道未被使用——它们是放置遮罩的黄金地段。如果你的材质始终是不透明的，你可以在颜色贴图的 Alpha 通道中隐藏一个遮罩。高光颜色和自发光纹理的 Alpha 通道通常也未被使用！

**提醒！** 我们稍后会在本系列中添加另一种遮罩纹理：**遮挡遮罩（Occlusion Mask）**。它控制模型上环境光照的强度。如果你现在就去优化着色器，请为这张纹理留出空间，因为它相当重要。

---

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787352189538-06a30d5b-fdb1-4fd6-a4ab-7584ff01f927.png)

## 结语
为材质添加炫酷的表面功能是我最喜欢的着色器开发方面之一。现在，我们可以制作金属物体、玻璃物体、凹凸物体，甚至一辆崭新的汽车！

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787352188348-ad7e227f-8922-4623-8f77-cdface95db3f.png)

我们已经用自己的材质做了很多事情，是时候向外看了！在下一个教程中，我将专注于一个备受期待的话题：**高级光照**。我们将学习如何支持多个点光源和锥形光源、烘焙光照、遮挡纹理、反射探针、光照 Cookie 等更多内容！

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787352205961-6a6c0dee-f21e-4de6-b4c5-b8ce17ad1d9a.png)

感谢阅读，去制作游戏吧！

---

> **参考链接**：完成本教程后未经优化的着色器文件最终版本，请参考原文末尾的 GitHub Gist 链接。
>
> 如果你喜欢本教程，请考虑[关注](https://nedmakesgames.medium.com/)作者，以便在下一部分发布时收到邮件通知。
>
> 如果你想在 Unity 项目中下载本教程中展示的所有着色器，请考虑[加入作者的 Patreon](https://www.patreon.com/nedmakesgames)。你还将获得教程的早期访问权、主题投票权等更多福利。
>
> 如果你有任何问题，欢迎在评论区留言或通过社交媒体联系作者。
>

