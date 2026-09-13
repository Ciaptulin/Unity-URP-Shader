

## 前言
<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786962806011-0e4283fc-b087-456e-a26f-0a25cbdc3b48.png)

在本篇中，我将展示如何为着色器添加光照，包括对**阴影映射（shadow mapping）**的简单解释——即物体如何在 URP 中投射和接收阴影——以及**关键字（keywords）和着色器变体（shader variants）**的入门介绍，这是编写着色器时非常重要的概念！

## Blinn-Phong 光照
到目前为止，我们学会了编写无光照着色器，也就是不受灯光影响的着色器。显然，光照是渲染中极其重要的一环；程序员为此投入了大量的着色器代码。幸运的是，URP 提供了一个辅助函数来处理大部分工作。

在 URP 的 `lighting.hlsl` 文件中，有一个名为 `UniversalFragmentBlinnPhong` 的函数。它实现了一种标准的光照算法，叫做 **Blinn-Phong 光照模型**。Blinn-Phong 实际上由两个部分组成：

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786962883077-e43db3b2-c595-46ff-ba8a-f59d7696fa84.png)

+ **漫反射光照（Diffuse Lighting）**：照亮物体朝向光源的那一侧。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786962895142-9a169b94-195a-4287-bfeb-9cc696285f27.png)

+ **镜面高光（Specular Lighting）**：让光滑物体焕发生机的光泽或高光。

```csharp

float4 Fragment(Interpolators input) : SV_TARGET{
	float2 uv = input.uv;
	float4 colorSample = SAMPLE_TEXTURE2D(_ColorMap, sampler_ColorMap, uv);

	InputData lightingInput = (InputData)0;
	SurfaceData surfaceInput = (SurfaceData)0;

	return UniversalFragmentBlinnPhong(lightingInput, surfaceInput);
}
```

打开 `MyLitForwardLitPass.hlsl`，在 `Fragment` 函数中调用 `UniversalFragmentBlinnPhong`。它返回一个颜色值，我们可以直接将其作为结果返回。`UniversalFragmentBlinnPhong` 接受很多参数，但<font style="background-color:#C1E77E;">为了整洁</font>，它将它们打包成了两个<font style="background-color:#C1E77E;">结构体</font>：

+ `InputData`：保存当前片段处网格的位置和方向信息。
+ `SurfaceData`：保存表面材质的物理属性，比如颜色。

为两者分别定义变量。这些结构体各有近十二个字段，但我们目前不需要全部设置。与 C# 不同，结构体字段必须手动初始化。要将所有字段设为零，可以<font style="background-color:#C1E77E;">将零</font>强制转换为<font style="background-color:#C1E77E;">结构体</font>类型。这看起来有点奇怪，但这是初始化结构体的简便方法，无需知道所有字段名。

然后将 `inputData` 和 `surfaceData` 传给 `UniversalFragmentBlinnPhong`。

### 版本差异
在第一部分中我提到过，Unity 2020 和 Unity 2021 之间有几个差异。好吧，这是第一个影响我们着色器的差异。在 Unity 2020 中，URP 没有接受 `SurfaceData` 结构体的 `UniversalFragmentBlinnPhong` 重载。你需要像下面这样逐个传递字段。暂时不用纠结每个字段的含义，我们很快会讲到。

为了既让本教程更有条理，也为了帮助你将来升级项目，我希望同一份代码能在 Unity 2020 和 Unity 2021 中运行。幸运的是，有一种简单的方法可以根据当前 Unity 版本运行不同的代码。

你可能见过 C# 中的 `#if` 预处理指令——通常用于排除只在编辑器中运行的代码。`#if` 在 ShaderLab 和 HLSL 中也可用，而且非常常见！如果 `#if` 后面的表达式为真，则 `#if` 和 `#endif` 之间的代码会被编译。否则，编译器会忽略它。

`<font style="background-color:#C1E77E;">#if</font>` 只能依赖编译前<font style="background-color:#C1E77E;">已知的常量值</font>，比如常量和数字字面量。Unity 提供了一个名为 `UNITY_VERSION` 的常量，它将当前 Unity 版本以整数形式表示——基本上就是去掉了小数点的版本号。

所以，在我们的片段函数中，要根据 Unity 版本在传递 surface data 结构体还是逐个传递字段之间切换。如果版本号大于等于 `202102`，我们就可以传结构体。用 `#else` 定义否则的分支。在内部调用逐个传参的版本。

```csharp
float4 Fragment(Interpolators input) : SV_TARGET{
	float2 uv = input.uv;
	float4 colorSample = SAMPLE_TEXTURE2D(_ColorMap, sampler_ColorMap, uv);

	InputData lightingInput = (InputData)0;
	SurfaceData surfaceInput = (SurfaceData)0;

#if UNITY_VERSION >= 202120
	return UniversalFragmentBlinnPhong(lightingInput, surfaceInput);
#else
	return UniversalFragmentBlinnPhong(lightingInput, surfaceInput.albedo, float4(surfaceInput.specular, 1), surfaceInput.smoothness, 0, surfaceInput.alpha);
#endif
}
```

这样，着色器代码会根据我们使用的 Unity 版本动态变化。很整洁！

将来如果需要支持其他可能性，可以用 `#elif`（即 else-if 的简写）。下面是一个假设 Unity 2030 版本的示例。

```csharp

float4 Fragment(Interpolators input) : SV_TARGET{
	float2 uv = input.uv;
	float4 colorSample = SAMPLE_TEXTURE2D(_ColorMap, sampler_ColorMap, uv);

	InputData lightingInput = (InputData)0;
	SurfaceData surfaceInput = (SurfaceData)0;

#if UNITY_VERSION >= 203000
  return FutureBlinnPhong(lightingInput, surfaceInput);
#elif UNITY_VERSION >= 202120
	return UniversalFragmentBlinnPhong(lightingInput, surfaceInput);
#else
	return UniversalFragmentBlinnPhong(lightingInput, surfaceInput.albedo, float4(surfaceInput.specular, 1), surfaceInput.smoothness, 0, surfaceInput.alpha);
#endif
}
```

_这只是一个例子。你不需要把这段代码添加到你的着色器里_

回到场景编辑器中查看你的着色器——现在只是一个黑色的球体！

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786963344983-c72130f9-65dc-47b7-bf29-7fa5cace563b.png)

要恢复之前的效果，我们需要在输入结构体中填充一些字段。从颜色属性中，我们可以设置 `albedo` 和 `alpha`——这是基础颜色和透明度的花哨叫法。不过记住，着色器目前还不支持透明度，所以别抱太大期望。

```csharp
float4 Fragment(Interpolators input) : SV_TARGET{
	float2 uv = input.uv;
	float4 colorSample = SAMPLE_TEXTURE2D(_ColorMap, sampler_ColorMap, uv);

	InputData lightingInput = (InputData)0;

	SurfaceData surfaceInput = (SurfaceData)0;
	surfaceInput.albedo = colorSample.rgb * _ColorTint.rgb;
	surfaceInput.alpha = colorSample.a * _ColorTint.a;

#if UNITY_VERSION >= 202120
	return UniversalFragmentBlinnPhong(lightingInput, surfaceInput);
#else
	return UniversalFragmentBlinnPhong(lightingInput, surfaceInput.albedo, float4(surfaceInput.specular, 1), surfaceInput.smoothness, 0, surfaceInput.alpha);
#endif
}
```

_这只是一个例子。你不需要把这段代码添加到你的着色器里_

---

## 法线向量
接下来，我们需要一种叫做**法线向量（normal vector）**的东西。你可能从数学或 Unity 物理系统中了解过法线向量——它们是直接从表面向外指出的向量。Blinn-Phong 用它们来判断网格的哪个面朝向光源。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786963998916-f95f1f3b-5c79-4990-9b0d-6a1f60c5f9d0.png)

_立方体模型面上的法向量可视化_

法线向量应用于面，但它们被<font style="background-color:#C1E77E;">组织进网格的顶点流</font>中，就像位置或 UV 一样。这会让事情变得复杂。在球体上没有问题，但在棱角分明的网格（比如立方体）上，看起来一个顶点会有多个法线向量。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786964117052-764a4812-7a6c-41cd-ba57-e336ac06d1a7.png)

_存储在球面顶点上的法向量_

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786964129812-f42c5005-cd0c-4203-845a-f90214a33674.png)

_存储在立方体顶点上的法向量。注意重复的顶点！_

实际上，Unity 会<font style="background-color:#C1E77E;">复制顶点</font>——每个法线向量对应一个。这样，顶点的法线始终与其所属的面匹配。

无论如何，输入装配器（input assembler）会负责收集法线数据。在 `Attributes` 结构体中添加一个新字段，用 `<font style="background-color:#C1E77E;">NORMAL</font>`<font style="background-color:#C1E77E;"> 语义</font>标记。这些法线同样处于<font style="background-color:#C1E77E;">对象空间</font>（object space），就像位置一样。

```csharp
struct Attributes {
	float3 positionOS : POSITION;
	float3 normalOS : NORMAL;
	float2 uv : TEXCOORD0;
};
```

当向着色器添加新数据源时，规划好它在代码中的"旅程"很有用。Blinn-Phong 在片段阶段需要法线，但它们只能通过输入装配器访问。我们需要将它们穿过顶点阶段，并由光栅化器进行插值。

> 又提到了数据流动的问题，需要走顶点着色器把数据传递到Interpolators结构体，然后fragment shader从这个结构体里面拿到法线数据
>

此外，`UniversalBlinnPhong` 期望世界空间（world space）的法线，我们必须适时进行变换。我们可以在片段阶段做这件事，但我们在那里完全不需要对象空间的法线。在顶点函数中计算世界空间法线会更优一些，因为顶点函数运行的次数比片段函数少。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786964968951-3a09af9e-310c-45d2-99f4-eb09ab47fde2.png)

按照这个计划，逐段检查代码并做相应修改。

```csharp

struct Attributes {
	float3 positionOS : POSITION;
	float3 normalOS : NORMAL;
	float2 uv : TEXCOORD0;
};

struct Interpolators {
	float4 positionCS : SV_POSITION;

	float2 uv : TEXCOORD0;
	float3 normalWS : TEXCOORD1;
};

Interpolators Vertex(Attributes input) {
	Interpolators output;

	VertexPositionInputs posnInputs = GetVertexPositionInputs(input.positionOS);
	VertexNormalInputs normInputs = GetVertexNormalInputs(input.normalOS);

	output.positionCS = posnInputs.positionCS;
	output.uv = TRANSFORM_TEX(input.uv, _ColorMap);
	output.normalWS = normInputs.normalWS;

	return output;
}

float4 Fragment(Interpolators input) : SV_TARGET {
	float2 uv = input.uv;
	float4 colorSample = SAMPLE_TEXTURE2D(_ColorMap, sampler_ColorMap, uv);

	InputData lightingInput = (InputData)0;
	lightingInput.normalWS = input.normalWS;

	SurfaceData surfaceInput = (SurfaceData)0;
	surfaceInput.albedo = colorSample.rgb * _ColorTint.rgb;
	surfaceInput.alpha = colorSample.a * _ColorTint.a;

#if UNITY_VERSION >= 202120
	return UniversalFragmentBlinnPhong(lightingInput, surfaceInput);
#else
	return UniversalFragmentBlinnPhong(lightingInput, surfaceInput.albedo, float4(surfaceInput.specular, 1), surfaceInput.smoothness, 0, surfaceInput.alpha);
#endif
}
```

我们已经在 `Attributes` 中添加了 `normalOS` 字段。在 `Interpolators` 中添加一个 `normalWS` 字段。<font style="background-color:#C1E77E;">光栅化器</font>会插值<font style="background-color:#C1E77E;">任何</font>带有 `<font style="background-color:#C1E77E;">TEXCOORD</font>`<font style="background-color:#C1E77E;"> 语义</font>的字段，所以给法线标记 `TEXCOORD1`。

为什么是 1 而不是 0？因为 `TEXCOORD0` 已经被 UV 占用了，两个字段不能有相同的语义。光栅化器可以处理很多 `TEXCOORD` 变量——两个完全没问题。

> 为啥这里不和之前一样用NORMAL呢？
>
> 因为 NORMAL 是顶点输入阶段从 Mesh 读取数据的"<font style="background-color:#C1E77E;">读取标签</font>"，而 TEXCOORDn 是光栅化阶段通用的高精度<font style="background-color:#C1E77E;">插值通道</font>——算好的世界空间法线只是<font style="background-color:#C1E77E;">普通数据</font>，借 TEXCOORDn 这个"通用货位"传过去就行，用 NORMAL 反而有精度限制。
>

在顶点函数中，将法线向量从对象空间变换到世界空间。URP 提供了另一个函数来做这件事——`GetVertexNormalInputs`，类似于我们用于位置的函数。调用它，并在 `Interpolators` 结构体中设置世界空间法线。

在片段函数中，设置 `InputData` 结构体中的 `normalWS`。

在继续之前，让我们思考一下法线向量在插值过程中会发生什么。当<font style="background-color:#C1E77E;">光栅化器</font>对向量进行<font style="background-color:#C1E77E;">插值</font>时，它会逐个分量地插值。这可能导致向量的长度发生变化，就像这个例子中的那样。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786967219975-f0d067df-05fa-4860-8f11-ce5412ebad81.png)

_当对指向相反方向的法线进行插值时，中间值的长度会发生变化_

为了让光照效果最佳，所有法线向量的长度必须为 1。当一个向量表示方向时，这个要求很常见。我们可以用一个恰如其名的 `normalize` 函数将任意向量归一化为单位长度。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786967262322-1852aaa3-68fd-44dc-abf5-a67ea48f6ea0.png)

_这些正态线已被归一化为始终长度为1_

`normalize` 有点慢，因为<font style="background-color:#C1E77E;">内部</font>有一个开销较大的<font style="background-color:#C1E77E;">平方根计算</font>。我认为为了更平滑的光照效果，这一步是值得的——在镜面高光上尤其明显——但如果你对算力很紧张，可以跳过它。

```csharp
float4 Fragment(Interpolators input) : SV_TARGET {
	float2 uv = input.uv;
	float4 colorSample = SAMPLE_TEXTURE2D(_ColorMap, sampler_ColorMap, uv);

	InputData lightingInput = (InputData)0;
	lightingInput.normalWS = normalize(input.normalWS);

	SurfaceData surfaceInput = (SurfaceData)0;
	surfaceInput.albedo = colorSample.rgb * _ColorTint.rgb;
	surfaceInput.alpha = colorSample.a * _ColorTint.a;

#if UNITY_VERSION >= 202120
	return UniversalFragmentBlinnPhong(lightingInput, surfaceInput);
#else
	return UniversalFragmentBlinnPhong(lightingInput, surfaceInput.albedo, float4(surfaceInput.specular, 1), surfaceInput.smoothness, 0, surfaceInput.alpha);
#endif
}
```

回到场景编辑器中，我们终于有光照了！

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786968958520-f0ef71e1-a921-4e1f-ad53-c4e277367209.png)

---

## 镜面光照
但是，目前只有漫反射光照，看起来有点平。对于镜面高光，URP 需要更多数据，具体说是世界空间位置。

```csharp
struct Interpolators {
	float4 positionCS : SV_POSITION;
	float2 uv : TEXCOORD0;
	float3 positionWS : TEXCOORD1;
	float3 normalWS : TEXCOORD2;
};

Interpolators Vertex(Attributes input) {
	Interpolators output;

	VertexPositionInputs posnInputs = GetVertexPositionInputs(input.positionOS);
	VertexNormalInputs normInputs = GetVertexNormalInputs(input.normalOS);

	output.positionCS = posnInputs.positionCS;
	output.uv = TRANSFORM_TEX(input.uv, _ColorMap);
	output.normalWS = normInputs.normalWS;
	output.positionWS = posnInputs.positionWS;
	return output;
}

float4 Fragment(Interpolators input) : SV_TARGET {
	float2 uv = input.uv;
	float4 colorSample = SAMPLE_TEXTURE2D(_ColorMap, sampler_ColorMap, uv);
    // 这个结构体像天上掉下来的，在库函数里面定义过了
	InputData lightingInput = (InputData)0;
	lightingInput.positionWS = input.positionWS;
	lightingInput.normalWS = normalize(input.normalWS);

	SurfaceData surfaceInput = (SurfaceData)0;
	surfaceInput.albedo = colorSample.rgb * _ColorTint.rgb;
	surfaceInput.alpha = colorSample.a * _ColorTint.a;

#if UNITY_VERSION >= 202120
	return UniversalFragmentBlinnPhong(lightingInput, surfaceInput);
#else
	return UniversalFragmentBlinnPhong(lightingInput, surfaceInput.albedo, float4(surfaceInput.specular, 1), surfaceInput.smoothness, 0, surfaceInput.alpha);
#endif
}
```

目前，片段函数只能访问像素位置，无法访问世界空间位置。将这些像素位置转换回世界空间并不容易；最好将它作为 `Interpolators` 结构体的另一个字段传递过来。用另一个空闲的 `TEXCOORD` 变量标记它。（我在这里稍微重新组织了一下，纯属个人偏好。）

> 为什么需要世界空间位置呢？
>
> 数据流向
>
> 模型空间 → 世界空间 → 观察空间 → 裁剪空间（SV_POSITION）
>
> positionWS 是在"流向裁剪空间"的途中，**顺手存下**来的一个中间状态。因为后续片段着色器要计算光照，它需要知道"这个像素在世界的哪个位置"，才能算出视线方向和光线方向
>
> `InputData lightingInput`里的结构体，在<font style="background-color:#C1E77E;">库函数</font>里面已经定义好了
>

在顶点阶段使用 URP 方便的变换函数设置位置！然后，在片段函数中，设置 `InputData` 中的 `positionWS`。当然这里不需要归一化，因为位置不是方向，可以有任意长度。

> 看11行和17行蓝色底色标记部分，11行已经有了，因为在`Interpolators`结构体里面增加了`positionWS`，在顶点着色器里面接受`positionOS`对象空间位置，<font style="background-color:#C1E77E;">转化</font>为世界空间位置，用于后面的<font style="background-color:#C1E77E;">视方向的计算</font>。接着就可以看到26行将数据拿到了`InputData`结构体
>
> 另外一点，无论是庄懂还是奈德，他们组织代码都是<font style="background-color:#C1E77E;">先位置，后法线</font>
>

如果你用默认光照着色器移动物体，会注意到高光也会轻微移动。这是因为镜面光照取决于**视方向（view direction）**，即从片段指向摄像机的方向。

```csharp
float4 Fragment(Interpolators input) : SV_TARGET{
	float2 uv = input.uv;
	float4 colorSample = SAMPLE_TEXTURE2D(_ColorMap, sampler_ColorMap, uv);

	InputData lightingInput = (InputData)0;
	lightingInput.positionWS = input.positionWS;
	lightingInput.normalWS = normalize(input.normalWS);
	lightingInput.viewDirectionWS = GetWorldSpaceNormalizeViewDir(input.positionWS);

	SurfaceData surfaceInput = (SurfaceData)0;
	surfaceInput.albedo = colorSample.rgb * _ColorTint.rgb;
	surfaceInput.alpha = colorSample.a * _ColorTint.a;
	surfaceInput.specular = 1;

#if UNITY_VERSION >= 202120
	return UniversalFragmentBlinnPhong(lightingInput, surfaceInput);
#else
	return UniversalFragmentBlinnPhong(lightingInput, surfaceInput.albedo, float4(surfaceInput.specular, 1), surfaceInput.smoothness, 0, surfaceInput.alpha);
#endif
}
```

我们可以在片段函数中用另一个方便的 URP 函数 `GetWorldSpaceNormalizeViewDir` 从世界空间位置计算它。调用它并设置 `InputData` 中的 `viewDirectionWS`。

> 注意到这里是在Fragment里计算视方向的，为啥不在Vertex里计算呢？
>
> 视方向 = 摄像机位置 − 三角形上的点
>
> 三角形上的点在片元阶段会经过归一化，如果先计算，后面再归一化，视方向就会错误
>
> 我们要的最终结果是什么？
>
> 每个像素上，一个从<font style="background-color:#C1E77E;">表面指向摄像机</font>的<font style="background-color:#C1E77E;">单位方向</font>向量。
>
> <!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787067575825-45da63bc-7d4d-449f-9a13-660c60d751d2.png)<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787067587470-c79026c0-bf65-411e-ac31-b2e9a54f2c16.png)
>

高光的颜色有时可能与反照率（albedo）不同，URP 允许你在 `SurfaceData` 结构体的 `specular` 字段中指定。目前，将其设为白色。

> 接上文，拿到了世界空间的位置后，就使用`GetWorldSpaceNormalizeViewDir`来计算视方向向量
>
> 接着设置这个`specular`
>

如果你瞥一眼场景，仍然没有高光！原来 `UniversalFragmentBlinnPhong` 内部使用了 `#if` 指令来开关高光。它用一种叫做**关键字（keyword）**的特殊常量来做这件事。关键字有点像你用 `#define` 指令启用的布尔常量。

着色器广泛使用<font style="background-color:#C1E77E;">关键字</font>来<font style="background-color:#C1E77E;">开启和关闭</font>不同功能。禁用镜面光照比把高光颜色设为黑色更快。两种方案视觉效果相同，但不计算总比算完丢弃要快。

```csharp
Shader "NedMakesGames/MyLit" {
    Properties{
        [Header(Surface options)] // Creates a text header
        [MainTexture] _ColorMap("Color", 2D) = "white" {}
        [MainColor] _ColorTint("Tint", Color) = (1, 1, 1, 1)
    }

    SubShader{
        Tags{"RenderPipeline" = "UniversalPipeline"}

        Pass {
            Name "ForwardLit"
            Tags{"LightMode" = "UniversalForward"}

            HLSLPROGRAM

            #define _SPECULAR_COLOR

            #pragma vertex Vertex
            #pragma fragment Fragment

            #include "MyLitForwardLitPass.hlsl"
            ENDHLSL
        }
    }
}
```

不过，我想在这个着色器中启用镜面光照。为了条理清晰，我在 ShaderLab 文件中为每个 Pass 定义关键字，让人一眼就能看出启用了哪些关键字。在你的 Pass 块中添加 `#define _SPECULAR_COLOR`。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786969085122-13e4d300-34ba-4be4-96bb-5696840c275c.png)

现在——终于——有高光了！但是，它们太大了！URP 提供了一种简单的方法，用一个叫做**平滑度（smoothness）**的值来缩小高光。平滑度越高，高光越小。想象一个完美光滑的金属球；高光非常集中！

> specular设置高光，smoothness光滑度控制高光大小，roughness是粗糙度，别搞混了
>

```csharp
Properties{
    [Header(Surface options)]
    [MainTexture] _ColorMap("Color", 2D) = "white" {}
    [MainColor] _ColorTint("Tint", Color) = (1, 1, 1, 1)
    _Smoothness("Smoothness", Float) = 0
}
```

目前，让我们用一个材质属性来定义<font style="background-color:#C1E77E;">平滑度</font>。在着色器中添加一个 `_Smoothness` 属性，类型为 `Float`。

```csharp
TEXTURE2D(_ColorMap); SAMPLER(sampler_ColorMap);
float4 _ColorMap_ST;
float4 _ColorTint;
float _Smoothness;

... // Code omitted

float4 Fragment(Interpolators input) : SV_TARGET{
	float2 uv = input.uv;
	float4 colorSample = SAMPLE_TEXTURE2D(_ColorMap, sampler_ColorMap, uv);

	InputData lightingInput = (InputData)0;
	lightingInput.positionWS = input.positionWS;
	lightingInput.normalWS = normalize(input.normalWS);
	lightingInput.viewDirectionWS = GetWorldSpaceNormalizeViewDir(input.positionWS);

	SurfaceData surfaceInput = (SurfaceData)0;
	surfaceInput.albedo = colorSample.rgb * _ColorTint.rgb;
	surfaceInput.alpha = colorSample.a * _ColorTint.a;
	surfaceInput.specular = 1;
	surfaceInput.smoothness = _Smoothness;

#if UNITY_VERSION >= 202120
	return UniversalFragmentBlinnPhong(lightingInput, surfaceInput);
#else
	return UniversalFragmentBlinnPhong(lightingInput, surfaceInput.albedo, float4(surfaceInput.specular, 1), surfaceInput.smoothness, 0, surfaceInput.alpha);
#endif
}
```

在 `MyLitForwardLitPass` 中，在文件顶部声明 `_Smoothness` 并在 `SurfaceData` 结构体中设置它。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786969132079-23bde4bd-2a5d-4a8c-a359-6dcce512c269.png)

通过材质检查器，你可以用平滑度属性控制高光的大小。注意平滑度在不同 Unity 版本中表现不同。2021 的实现要敏感得多。这只是 URP 幕后计算光照方式的一个后果。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786969143430-c7963953-92e0-4d6e-8624-2b6901252b93.png)

在继续之前说一句。着色器目前只支持主光源。我们应该先把基础打好，再用附加光源把事情复杂化，但我会在本系列第五部分展示如何添加对它们的支持！

---

## 阴影映射算法
到目前为止，我们只处理了一个物体。如果你创建另一个，会注意到使用我们着色器的物体既不投射也不接收阴影。在着色器的世界里，这是两个独立的概念，我们需要两者都实现。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786969157772-6c0c295c-c0b1-4dcf-8f33-3fb43ab89b0f.png)

首先，让我们用一种叫做**"阴影映射"**的算法来研究 URP 如何处理阴影。

目标是找到一种廉价的方法，判断某个片段相对于光源是否处于阴影中。同样，我们先只考虑主光源。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786969194921-9ec7772c-7239-4d1d-a03c-cc6586621589.png)

_我们想计算是否有多个表面处于阴影中_

一种 naive 的方法是检查片段和光源之间是否有物体。这非常慢，因为着色器需要执行光线投射，遍历场景中所有物体。肯定有更快的方法。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787134684267-d1caabe3-e41d-48b7-9343-3d5d36409fed.png)

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786969242813-e46d396c-7a3a-454b-9181-d131d4d54332.png)<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786969228034-6af20e35-0c4b-4787-8b40-78103db1e569.png)

_中间表面处于阴影中。从表面到光线的光线投射会与另一个表面相交_

首先，让我们重构算法，让光线从光源出发沿直线射出，穿过我们的片段和同一直线上的任何其他表面。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786969279512-ea0b41b3-77cc-4b08-8e01-5da53f071046.png)

其次，注意光线上的表面只有一个被照亮。对于除离光源最近的那个表面外的所有表面，在它和光源之间都存在物体。要判断一个片段是否在阴影中，只需测试它到光源的距离是否大于所有表面到光源的最小距离。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786969288868-5b9380ba-6a36-4f94-b1a2-ffed1a36598b.png)

_只有最近的表面没有被阴影遮挡_

这就把问题简化为：找到沿所有光线从<font style="background-color:#C1E77E;">光源到最近表面</font>的距离。这听起来有点耳熟……渲染时，我们沿所有"视线"绘制离摄像机最近表面的颜色。把颜色换成距离，把摄像机换成光源，就成了！

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786969490671-2707c09d-abbb-4f1b-81e9-4501b303e7b3.png)<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786969510891-36b5db11-f1b5-45e4-8d15-bc00e76a721d.png)

_左图是普通渲染，右图则显示与相机的距离。两者都是从光的视角出发_

怎么"绘制距离"呢？记住颜色只是数字，所以我们可以把<font style="background-color:#C1E77E;">距离</font>存在颜色的<font style="background-color:#C1E77E;">红色通道</font>中。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786969480040-4fa321cf-4198-4db1-be83-78f9c86d1b0e.png)

URP 的阴影映射系统在幕后做这件事。在渲染颜色之前，它将摄像机切换到匹配主光源的视角。然后，它利用另一个着色器 Pass——**Shadow Caster Pass**——来绘制每个像素的深度。

> 切换到主光源视角绘制深度图
>

不过，我们不想把这些深度绘制到屏幕上。URP <font style="background-color:#C1E77E;">劫持</font>了呈现阶段，将其引导到一个叫做**<font style="background-color:#C1E77E;">渲染目标</font>****（render target）**的<font style="background-color:#C1E77E;">特殊纹理</font>上。这个包含离光源距离的渲染目标就叫做**<font style="background-color:#C1E77E;">阴影贴图</font>****（shadow map）**，算法也因此得名。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786969501101-6090dc4f-3741-4add-8fb7-bc582ee2ae4d.png)

_阴影贴图纹理和其他纹理一样有UV坐标_

要计算一个片段是否在阴影中，我们需要它到光源的距离和阴影贴图中存储的距离。要采样阴影贴图，我们需要计算对应的阴影贴图 UV——也叫**阴影坐标（shadow coord）**。URP 又提供了一个函数 `TransformWorldToShadowCoord`，将世界空间位置转换为阴影坐标。

```csharp
float4 Fragment(Interpolators input) : SV_TARGET{
	float2 uv = input.uv;
	float4 colorSample = SAMPLE_TEXTURE2D(_ColorMap, sampler_ColorMap, uv);

	InputData lightingInput = (InputData)0;
	lightingInput.positionWS = input.positionWS;
	lightingInput.normalWS = normalize(input.normalWS);
	lightingInput.viewDirectionWS = GetWorldSpaceNormalizeViewDir(input.positionWS);
	lightingInput.shadowCoord = TransformWorldToShadowCoord(input.positionWS);
	
	SurfaceData surfaceInput = (SurfaceData)0;
	surfaceInput.albedo = colorSample.rgb * _ColorTint.rgb;
	surfaceInput.alpha = colorSample.a * _ColorTint.a;
	surfaceInput.specular = 1;
	surfaceInput.smoothness = _Smoothness;

#if UNITY_VERSION >= 202120
	return UniversalFragmentBlinnPhong(lightingInput, surfaceInput);
#else
	return UniversalFragmentBlinnPhong(lightingInput, surfaceInput.albedo, float4(surfaceInput.specular, 1), surfaceInput.smoothness, surfaceInput.emission, surfaceInput.alpha);
#endif
}
```

如果我们设置了 `InputData` 结构体中的 `shadowCoord`，URP 会负责比较距离和采样阴影贴图。在 `MyLitForwardLitPass.hlsl` 的片段函数中，去设置它吧。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787176006538-51864afe-924c-4d77-9736-36cfd72c7e47.png)

---

## 着色器变体
与镜面光照类似，URP 用一个叫做 `_MAIN_LIGHT_SHADOWS` 的关键字来开关阴影。但是，如果我正在做一个没有主光源的暗场景呢？那种情况下我想关闭阴影，但又不想仅仅为了取消定义这个关键字就创建一个全新的着色器。

```csharp
Shader "NedMakesGames/MyLit" {
    ... // Code omitted
    SubShader{
        Tags{"RenderPipeline" = "UniversalPipeline"}

        Pass {
            Name "ForwardLit"
            Tags{"LightMode" = "UniversalForward"}
            HLSLPROGRAM

            #define _SPECULAR_COLOR
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS

            #pragma vertex Vertex
            #pragma fragment Fragment

            #include "MyLitForwardLitPass.hlsl"
            ENDHLSL
        }
    }
}
```

幸运的是，Unity 有着色器变体系统来处理这种用例。使用 `#pragma multi_compile` 指令，我们可以让 Unity 编译<font style="background-color:#C1E77E;">两个版本的着色器</font>——一个启用 `_MAIN_LIGHT_SHADOWS`，一个不启用。这两个版本被称为我们着色器的**变体（variants）**，更具体地说，是 Forward Lit Pass 的变体。

如果看不到阴影，关闭级联和软阴影（<font style="background-color:#C1E77E;">关掉 Cascade 和 Soft Shadow</font>），降级排查思路，关掉后只需要最简单的 `_MAIN_LIGHT_SHADOWS` 就能验证阴影管线是否通了。泼一盆冷水，在Unity2023版本级联最低为1，不能用这种方案来验证。

在Unity2023中，默认的URP关键是打开Cascade和Soft Shadow的，如果你想直接看到阴影，可以这样写

```csharp
SubShader{
        Tags{"RenderPipeline" = "UniversalPipeline"}

        Pass{
        Name "ForwardLit" // For debugging
        Tags{"LightMode" = "UniversalForward"}

        HLSLPROGRAM // Begin HLSL code
            #define _SPECULAR_COLOR
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
            // 想要兼容多个版本可以这样写，Unity 2021.2、2022.3、2023.2、Unity 6 全部通用
            // #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            // Register our programmable stage functions
            #pragma vertex Vertex
            #pragma fragment Fragment

            // Include our code file
            #include "MyLitForwardLitPass.hlsl"
        ENDHLSL
        }
    }
```

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786969605740-3eefa2fb-3c71-4179-a7d6-ecd340948def.png)

_添加变体会在下一个过程下，产生一个顶点和片段函数略有不同的细分_

Multi compile 也可以接受一整列关键字，这种情况下它会创建多个变体，每个变体启用其中一个关键字。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786969651646-36e491af-f237-4222-b7e7-c894d477006e.png)

通过添加一个单独的下划线 `_`，它还会编译一个不启用任何关键字的变体。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786969665952-4b815daa-cb80-49d7-8e78-9f759279747f.png)

更方便的是，材质会自动为当前情况选择合适的变体。

```csharp
// C# code

Material m;
m.EnableKeyword("_MAIN_LIGHT_SHADOWS");
// The material will switch to a variant with _MAIN_LIGHT_SHADOWS defined

m.DisbleKeyword("_MAIN_LIGHT_SHADOWS");
// The material will switch back to a variant without _MAIN_LIGHT_SHADOWS defined
```

你看，如果想使用定义了 `_MAIN_LIGHT_SHADOWS` 的变体，只需在 C# 中对材质调用 `EnableKeyword("_MAIN_LIGHT_SHADOWS")` 即可。`DisableKeyword` 则会取消定义该关键字。如果 URP 检测到场景中有<font style="background-color:#C1E77E;">方向光</font>，它会<font style="background-color:#C1E77E;">自动做</font>这件事。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786969730694-53ed2c8a-b33a-4923-b3b1-693068118bc4.png)

来试试吧！创建一个使用默认光照材质的物体，把它放在你的 MyLit 物体和光源之间。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786969747192-10ba1519-2350-483f-8d89-308f6feaf0b5.png)

---

## 阴影级联与软阴影
如果你看不到阴影，请在你的 URP 设置资源中关闭**级联（cascades）**和**软阴影（soft shadows）**。不过，支持这两个选项以获得更好质量还是很不错的。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786969746977-eb59b70c-af6a-4f14-bfa3-0ca0dc33a8e4.png)<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786969748658-7e60a8bd-7edf-4d42-a94d-5935c7745b09.png)<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786969757277-f7b58d96-729e-494d-8824-14b6f4302924.png)

_三层级联阴影，每一层都让观察者对本场景看得更清晰。_

我们一直说得好像主光源有个位置似的，但因为它是模拟太阳的，所以它实际上离场景中的一切无限远。这使得在保持足够细节以获得良好质量的同时，创建一张包含整个场景的阴影贴图变得困难。Unity 试图用**级联（cascades）**来平衡这一点——它<font style="background-color:#C1E77E;">渲染多张阴影贴图</font>，每张包含场景更大的切片，并在任何位置<font style="background-color:#C1E77E;">采样细节最多</font>的那一张。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786969875766-3cc4db51-9d46-4801-9c9b-a4ee3c2f1bcb.png)

_Unity 采样的是包含特定世界位置的最高细节级联。这里的每种颜色代表来自不同级联的阴影数据_

因为阴影贴图有方形像素，你有时会在表面上看到它们锯齿状的边缘。**软阴影**通过在给定阴影坐标周围<font style="background-color:#C1E77E;">多次采样阴影贴图</font>来帮助<font style="background-color:#C1E77E;">消除</font>这些<font style="background-color:#C1E77E;">伪影</font>。它对这些样本取平均，有效地模糊了阴影贴图。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786969873818-9ea0be2c-60ac-45f7-bae2-5ed2c07ea695.png)

我们不需要操心这两个系统的细节。只需启用两个关键字，URP 就会处理其余一切。

```csharp
Shader "NedMakesGames/MyLit" {
    ... // Code omitted
    SubShader{
        Tags{"RenderPipeline" = "UniversalPipeline"}

        Pass {
            Name "ForwardLit"
            Tags{"LightMode" = "UniversalForward"}

            HLSLPROGRAM

            #define _SPECULAR_COLOR
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile_fragment _ _SHADOWS_SOFT

            #pragma vertex Vertex
            #pragma fragment Fragment

            #include "MyLitForwardLitPass.hlsl"
            ENDHLSL
        }
    }
}
```

为这些新关键字添加更多 multi compile 指令。多个 multi compile 指令放在一起时，Unity 会做排列组合，为每种关键字组合创建一个变体。我们才刚刚开始，就已经有六个变体了。每个变体都需要编译时间，所以保持这个数量较低是值得的。

<font style="color:#117CEE;">作者这里的说法是有点问题的，实际上应该是8个变体，如果优化一下可以变成6个变体，这样写也是URP中常见的变体优化技巧</font>

```csharp
// 将两个阴影关键词合并成一行（这是URP中常见的优化写法）
#pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE  // 3种状态
#pragma multi_compile_fragment _ _SHADOWS_SOFT                           // 2种状态
```

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786969899520-209cbb73-7b5b-4125-80bc-230cec50d3ef.png)

考虑到这一点，Unity 2021.2 对级联系统做了一些调整。在 2020 中，我们必须为主光源阴影和级联都启用关键字；但在 2021 中，<font style="background-color:#C1E77E;">启用级联</font>就意味着<font style="background-color:#C1E77E;">主光源阴影</font>也已<font style="background-color:#C1E77E;">启用</font>。我们可以用 `#if` 块处理两种情况，并在 2021 中减少变体数量。

<font style="color:#117CEE;">没有主阴影就不可能存在级联阴影，但是在2020版本中还是把这个编译出来了，仅级联阴影是一种冗余组合，然后加上开关软阴影的两种状态，也就减少了两个变体</font>

```csharp
Shader "NedMakesGames/MyLit" {
    ... // Code emitted
    SubShader{
        Tags{"RenderPipeline" = "UniversalPipeline"}

        Pass {
            Name "ForwardLit"
            Tags{"LightMode" = "UniversalForward"} 

            HLSLPROGRAM

            #define _SPECULAR_COLOR
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
    }
}
```

另外，注意到软阴影 pragma 中的 `<font style="background-color:#C1E77E;">_fragment</font>`<font style="background-color:#C1E77E;"> 后缀</font>了吗？我们可以通过标明 `_SHADOWS_SOFT` 关键字<font style="background-color:#C1E77E;">只在片段阶段使用</font>来节省一点编译时间。Unity 会让这个 multi compile 指令创建的变体<font style="background-color:#C1E77E;">共享同一个顶点函数</font>。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786969893449-caad9e53-e1f8-4280-a750-16dbc01dbee0.png)

做完这些，我们来测试一下。务必调整阴影级联并启用软阴影，看看你所有的着色器变体都在工作。你会看到 URP 在着色器短暂闪烁洋红色时动态编译着色器变体。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786969918203-7767fbb6-54f5-43f1-8b2c-842df2a1693f.png)

Unity 2022 有额外的阴影质量选项：高质量软阴影和阴影级联的"保守包围球（conservative enclosing sphere）"。试着启用它们看看效果——无需修改代码。

<font style="color:#117CEE;">高质量软阴影似乎没啥效果</font>

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787192633105-e960be40-8df1-4625-bed7-965627686c63.png)

<font style="color:#117CEE;">需要打开URP-High Fidelity 这个文件，在Inspector里把 Normal 切到 Debug 模式，再去找Conservative Enclosing Sphere（切回Normal模式依然生效）</font>

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787192580765-2fd35486-0b01-4d38-8b3e-3d8fa437b1f4.png)

<font style="color:#117CEE;">学完整篇回来看，高质量阴影这里需要去</font><font style="color:#117CEE;background-color:#C1E77E;">主光源组件那里调整</font><font style="color:#117CEE;">，这样才有效果</font>

---

## 帧调试器
现在似乎是介绍一个强大调试工具的好时机：**帧调试器（Frame Debugger）**！在 "Window" 菜单下的 "Analysis" 中找到它。用左上角的这个按钮启用它。确保你的游戏视图可见——如果正在运行，它也会自动暂停。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786969934684-28096be4-4146-4aee-8f2d-0678000b2c1f.png)

这个有用的窗口告诉你 Unity 如何渲染场景的各种信息。它按菜单中的顺序渲染物体。你可以看到 Unity 在渲染光照 Pass 之前创建阴影贴图，甚至可以查看阴影贴图长什么样。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786969941534-dff4506f-3808-47e7-91e8-d350cd1c89eb.png)

帧调试器还会告诉你任何物体当前激活的是哪个着色器变体。导航到 "DrawOpaqueObjects" 下拉菜单，找到你的球体。检查着色器名称，它会是 "MyLit!"。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786970084459-2815e10c-8ea2-46e1-b462-b35f4c84aa00.png)

你可以看到当前的子着色器和 Pass，其下方是决定了着色器变体的已定义关键字列表。试着关闭软阴影、级联和主光源游戏对象，看看这如何影响一切。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786970154580-5ccbcf18-8a87-4242-bc50-7573c8bcfc09.png)<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786970170278-1a467c0e-0267-4380-8258-2a20ee4128e2.png)

_MyLit着色器禁用主光，然后关闭柔和阴影_

这个窗口不太擅长保持选中同一个物体，当你开关东西时得重新找你的着色器。不同 Unity 版本也会有细微差异，请记住这一点。

---

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786970187473-a29d6969-a1bf-415d-bae8-f5b4bbf8e542.png)

## Shadow Caster Pass
你可能试着把 MyLit 着色器应用到你的阴影投射球体上，却发现它不再投射阴影了。这是因为<font style="background-color:#C1E77E;">投射</font>和<font style="background-color:#C1E77E;">接收阴影</font>在 3D 渲染中是完全不同的过程，而我们还没处理投射！

在上一节中，我提到 URP 用另一个着色器 Pass（叫做 Shadow Caster Pass）创建阴影贴图纹理。我们要给 MyLit 添加阴影投射功能，只需编写这个 Pass。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786970239623-0a8949ac-b442-46db-ad07-e500301c5e77.png)

记住，<font style="background-color:#C1E77E;">Pass 是</font>拥有自己顶点和片段函数的<font style="background-color:#C1E77E;">着色器子分部</font>。Pass 也可以有自己的 multi compile 关键字和着色器变体。每个着色器 Pass 都有 URP 赋予的特定工作。`UniversalForward`（Forward Lit）Pass 计算最终像素颜色，而 `ShadowCaster` Pass 为阴影贴图计算数据。

老实说，实践起来比听起来简单得多。URP 负责在正确时间调用正确的 Pass，并将输出颜色路由到正确的目标。这些抽象的 Pass 很难可视化，所以让我们动手写点东西。

```csharp
Shader "NedMakesGames/MyLit" {
    ... // Code omitted
    SubShader {
        Tags {"RenderPipeline" = "UniversalPipeline"}

        Pass {
            Name "ForwardLit"
            Tags{"LightMode" = "UniversalForward"}
            ... // Code omitted
        }

        Pass {
            Name "ShadowCaster"
            Tags{"LightMode" = "ShadowCaster"}

            HLSLPROGRAM
            #pragma vertex Vertex
            #pragma fragment Fragment

            #include "MyLitShadowCasterPass.hlsl"
            ENDHLSL
        }
    }
}
```

首先在 `MyLit.shader` 文件中添加另一个 Pass 块。复制 `ForwardLit` Pass，将名称和 Light Mode 标签改为 `ShadowCaster`。这里没有光照；删除 `_SPECULAR_COLOR` 定义和着色器变体 pragma。

为了条理清晰，我喜欢把每个 Pass 写在自己的 HLSL 文件中。修改 `#include` 指向 `MyLitShadowCasterPass.hlsl`。然后，创建一个名为 `MyLitShadowCasterPass.hlsl` 的新 HLSL 文件。

```csharp
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

struct Attributes {
	float3 positionOS : POSITION;
};

struct Interpolators {
	float4 positionCS : SV_POSITION;
};

Interpolators Vertex(Attributes input) {
	Interpolators output;

	VertexPositionInputs posnInputs = GetVertexPositionInputs(input.positionOS);

	output.positionCS = posnInputs.positionCS;
	return output;
}

float4 Fragment(Interpolators input) : SV_TARGET {
	return 0;
}
```

在文件内部，先定义数据结构。在 `Attributes` 中，我们只需要位置；而 `Interpolators` 只需要裁剪空间位置。在顶点函数中，调用 URP 函数将位置转换到裁剪空间，在输出结构体中设置它并返回。在片段函数中，直接返回零。

> Unity在观察空间使用右手系（记忆：U要观察），其余使用左手系
>

---

## 深度缓冲区
等等，阴影贴图不是应该编码‘光源摄像机’到物体的距离吗？确实是，但渲染器会自动处理这件事。裁剪空间位置编码了一种叫做**深度（depth）**的东西，它与离摄像机的距离有关。在插值过程中，光栅化器将每个片段的深度存储在一个叫做**深度缓冲区（depth buffer）**的数据结构中。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786970309605-a3bd79e5-eb45-40b7-9e7f-3e59f3694f25.png)

_剪辑空间位置的Z分量是（与）片段深度相关的_

Unity 利用深度缓冲区来减少**过度绘制（overdraw）**。过度绘制发生在一帧中两个或多个具有相同像素位置的片段被渲染时。当一切都是不透明时（就像现在），只有更近的片段最终会被显示。任何其他片段都会被丢弃，导致工作被浪费。如果某个片段的深度大于深度缓冲区中存储的值，光栅化器可以避免调用其片段函数。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786970319193-7894263c-17ea-4be1-b14a-edc2912e6082.png)

_如果没有深度缓冲，这两个球体重叠的部分会被渲染两次_

URP 将 Shadow Caster Pass 产生的深度缓冲区复用为阴影贴图。不过，大多数其他 Pass 也有自己的深度缓冲区。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786970339307-83240f79-aa90-4994-b825-1c0baf779dc1.png)

_窗户画廊场景的深度缓冲区_

<font style="color:#117CEE;">“光源的深度图”和“主摄像机的深度图”永远是两张独立的图，存放在两块独立的显存区域中，永远不存在互相转换和写入。</font>

<font style="color:#117CEE;">阴影一般都是最后计算，首先拿到剔除后的深度图，深度图转世界坐标，在世界坐标里转到光源摄像机的坐标（可以直接转，不需要过世界坐标），在这个光源摄像机空间对比深度，深度比记录的深，就渲染阴影</font>

<font style="color:#117CEE;">具体的数学实现细节，比如透视除法，我了解它是处理齐次坐标的关键步骤。如果实际项目中遇到精度或性能问题，我有能力通过查阅Unity官方文档或Graphics博客来定位解决。</font>

---

## 阴影粉刺（Shadow Acne）
我们的 MyLit 物体现在应该能投射阴影了，但你会看到一些叫做**阴影粉刺（shadow acne）**的丑陋伪影覆盖在它们上面。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786970367560-3af984e0-e8ce-454e-b19a-b3efe6c91385.png)

这主要发生在阴影投射物体的表面上。这是每个程序员都头疼的另一个后果：**浮点误差**。在这种情况下，阴影贴图深度和网格深度几乎相等，所以系统有时会把阴影画在投射表面上。

要修复粉刺，需要施加一个**偏移（bias）**，即偏移阴影投射顶点的位置。在计算裁剪空间位置时，没有规定它们必须完全匹配网格。我们可以将位置沿远离光源的方向偏移，也可以沿网格法线方向偏移。这两种偏移都有助于防止阴影粉刺。

<font style="color:#117CEE;">防止阴影粉刺的核心是避免由于浮点误差造成的自遮挡。顶点法线方向外扩，顶点向光源方向偏移一定距离，让当前深度小于等于贴图深度，从而避免自遮挡。实际调参时，我会优先调 Normal Bias，因为 Depth Bias 调太大容易导致阴影与物体分离，出现‘彼得潘效应’（悬浮感）。</font>

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786970443181-2703b97c-8082-4bb8-9ea4-5032f48aeb28.png)

_女孩的顶点在法向量上偏移_

```csharp
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

struct Attributes {
	float3 positionOS : POSITION;
	float3 normalOS : NORMAL;
};

struct Interpolators {
	float4 positionCS : SV_POSITION;
};

float3 _LightDirection;

float4 GetShadowCasterPositionCS(float3 positionWS, float3 normalWS) {
	float3 lightDirectionWS = _LightDirection;
	float4 positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, lightDirectionWS));
// 图形 API（DirectX vs OpenGL）对深度缓冲区（Depth Buffer）存储方式的规范差异
    #if UNITY_REVERSED_Z
	positionCS.z = min(positionCS.z, UNITY_NEAR_CLIP_VALUE);
#else
	positionCS.z = max(positionCS.z, UNITY_NEAR_CLIP_VALUE);
#endif
	return positionCS;
}

Interpolators Vertex(Attributes input) {
	Interpolators output;

	VertexPositionInputs posnInputs = GetVertexPositionInputs(input.positionOS);
	VertexNormalInputs normInputs = GetVertexNormalInputs(input.normalOS);

	output.positionCS = GetShadowCasterPositionCS(posnInputs.positionWS, normInputs.normalWS);
	return output;
}

float4 Fragment(Interpolators input) : SV_TARGET {
	return 0;
}
```

Shadow Caster 现在需要法线了，所以在 `Attributes` 结构体中添加一个法线字段。然后，写一个 `GetShadowCasterPositionCS` 函数来计算偏移后的裁剪空间位置。它需要世界空间位置和法线。

URP 库中的 `<font style="background-color:#C1E77E;">ApplyShadowBias</font>` 会读取并应用<font style="background-color:#C1E77E;">阴影偏移</font>设置。它需要<font style="background-color:#C1E77E;">世界空间位置</font>和<font style="background-color:#C1E77E;">法线</font>，以及<font style="background-color:#C1E77E;">渲染光源</font>的<font style="background-color:#C1E77E;">方向</font>。URP 在一个名为 `_LightDirection` 的全局变量中提供这个。我们需要像材质属性一样定义它。在函数上方做这件事，并将其传给 `ApplyShadowBias`。`ApplyShadowBias` 返回世界空间中的位置。用另一个 URP 函数 `TransformWorldToHClip` 将其变换到裁剪空间。

裁剪空间有深度边界，如果我们在施加偏移时不小心越界了，阴影可能会消失或闪烁。深度的边界由"光-近裁剪平面（light near clip plane）"定义。用 `UNITY_NEAR_CLIP_VALUE` 定义的近平面值来**钳制（clamp）**裁剪空间的 z 坐标。

<font style="color:#117CEE;">任何摄像机（包括光源摄像机）都有一个</font><font style="color:#117CEE;background-color:#C1E77E;">近裁剪平面</font><font style="color:#117CEE;">（Near Clip Plane），既然“光源摄像机”都看不到这个物体了，那它自然不会出现在这张阴影贴图（深度图）里。等主摄像机渲染画面时，去读取这张阴影贴图，发现里面空空如也（没有这个物体的遮挡深度数据），那自然就没有阴影投射下来——阴影就此完全消失了。</font>

<font style="color:#117CEE;">打个形象的比方：</font>

<font style="color:#117CEE;">你拿着手电筒照墙壁，你的手（物体）挡在手电筒前面，墙上就有手的影子。但如果你把手往后缩，缩得比手电筒的灯头还要靠后（藏到手电筒屁股后面），这时候手电筒的光根本照不到手，墙上自然没有任何手的影子——这就是阴影“消失”的根本原因。</font>

<font style="color:#117CEE;">而“闪烁”则是：你的手没有完全缩到手电筒后面，只是手腕在后面，手指还在前面，导致硬件为了强行拼凑这个破碎的手部图形，在阴影边界产生撕裂和跳动。</font>

<font style="color:#117CEE;">所以，钳制（Clamp）代码的作用就是：“就算你把手缩过头了，我也强行把你的</font><font style="color:#117CEE;background-color:#C1E77E;">深度值</font><font style="color:#117CEE;">定在</font><font style="color:#117CEE;background-color:#C1E77E;">近平面最近的位置</font><font style="color:#117CEE;">，假装你还在手电筒前面，绝不能让光源摄像机把你丢掉。” 这样虽然位置有点偏差，但至少影子不会凭空消失。</font>

更复杂的是，某些图形 API 会<font style="background-color:#C1E77E;">反转裁剪空间的 z 轴</font>。幸好，URP 提供了另一个布尔常量 `UNITY_REVERSED_Z` 来告诉我们边界是最小值还是最大值。用 `#if` 语句处理两种情况，并返回最终的裁剪空间位置。

<font style="color:#117CEE;">UNITY_REVERSED_Z（反转裁剪空间 Z 轴）与“左手系”或“右手系”没有任何关系。</font>

<font style="color:#117CEE;">它纯粹是图形 API（DirectX vs OpenGL）对深度缓冲区（Depth Buffer）存储方式的规范差异，本质上是一个精度优化策略。</font>

<font style="color:#117CEE;">模型空间 / 世界空间：左手系（+Z 指向屏幕内）。</font>

<font style="color:#117CEE;">观察空间（View Space）：右手系（+Z 指向屏幕外，即指向观察者身后）。因为 Unity 的观察空间遵循 OpenGL 传统，摄像机看向 -Z 方向。</font>

<font style="color:#117CEE;">裁剪空间（Clip Space）：取决于图形 API。在透视投影变换后，Unity 会把观察空间的右手系坐标映射到裁剪空间。但裁剪空间的 Z 轴到底是左手还是右手，取决于投影矩阵的构造，而 Unity 会根据平台动态调整矩阵。</font>

在顶点函数中，用 URP 的变换函数计算世界空间位置和法线，然后调用你自定义的阴影投射裁剪空间函数。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786970445865-813abef9-9dbc-40e6-9aa6-6dec5657cc96.png)

回到场景编辑器中，情况可能立刻就好多了。如果没有，请编辑<font style="background-color:#C1E77E;">主光源组件</font>上的阴影偏移设置和光-近裁剪平面值。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786970468804-1c1fef47-1489-4928-b207-d2814446448a.png)<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786970480861-0cf1cd48-be99-45e8-9d0e-9661be53eb69.png)

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787262284058-6eaddc1f-a6da-4624-98a7-dfd67fd7530a.png)

<font style="color:#117CEE;background-color:#C1E77E;">选中主光源组件</font><font style="color:#117CEE;">-Shadow-Bias调整为Custom，Depth就对应了Bias（深度偏移）和 Normal（法线偏移），Near Plane（近裁剪面）是裁剪边界</font>

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787262642776-8905c08c-63e6-40da-812f-3fcb0924a502.png)

_<font style="color:#117CEE;">局部Depth、Normal全设置为0出现阴影粉刺</font>_

你也可以在 URP 设置资源上设置全局偏移设置。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787262568452-d0ccf54e-7a59-4694-89fa-76a2014c8fe5.png)<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787262845288-34867bad-7caa-4e35-8d12-ef8e17fe523a.png)

<font style="color:#117CEE;">调整全局Bias影响的是"选中主光源组件-Shadow-Bias-Use setting from Render Pipeline Asset"这部分的效果</font>

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787263004209-9d1ec083-c255-48ae-b72a-409db14fb802.png)

_<font style="color:#117CEE;">调整全局Bias为0，可以在"Bias-Use setting from Render Pipeline Asset"选项上看到阴影粉刺效果</font>_



---

## ColorMask
在收尾之前，我们可以通过给 Pass 块添加一些元数据来优化一下 Shadow Caster。既然 Shadow Caster 只使用深度缓冲区，我们基本上可以用 `ColorMask` 指令<font style="background-color:#C1E77E;">关闭颜色输出</font>。

```csharp
Shader "NedMakesGames/MyLit" {
    ... // Code omitted
    SubShader {
        Tags {"RenderPipeline" = "UniversalPipeline"}

        Pass {
            Name "ForwardLit" 
            ... // Code omitted
        }

        Pass {
            Name "ShadowCaster"
            Tags{"LightMode" = "ShadowCaster"}

            ColorMask 0

            HLSLPROGRAM
            #pragma vertex Vertex
            #pragma fragment Fragment

            #include "MyLitShadowCasterPass.hlsl"
            ENDHLSL
        }
    }
}
```

这个 `ColorMask 0` 指令就是干这个的，基本上就是指示渲染器<font style="background-color:#C1E77E;">不写入任何颜色</font>。默认情况下，`ColorMask` 设为 `RGBA`，这是我们在 Forward Lit Pass 中想要的。而这个设置会绘制所有颜色通道。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786970547031-d8effc7c-2fcd-4eb9-b0aa-b3741102bd65.png)<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786970555504-d145ddb6-687c-4eac-93fb-5869edf0bfdc.png)

<font style="color:#117CEE;">这玩意确实有效果哦，我尝试在ForwardLit这个Pass里添加</font>`<font style="color:#117CEE;">ColorMask 0</font>`<font style="color:#117CEE;">，结果渲染好好的球直接变黑了</font>

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787263783062-395fca96-fb5b-4775-a4ed-93694a93123b.png)

<font style="color:#117CEE;">非常</font><font style="color:#117CEE;background-color:#C1E77E;">硬核的带宽节省术</font><font style="color:#117CEE;">，默认情况下，哪怕你的 Fragment 函数返回 return 0，GPU 的 ROP 单元依然会老老实实地把“0,0,0,0”这个颜色值，通过显存总线，写入颜色缓冲区。</font>

<font style="color:#117CEE;">ROP 通常要处理</font>**<font style="color:#117CEE;">两个“挂载点”</font>**<font style="color:#117CEE;">：</font>

+ **<font style="color:#117CEE;">颜色缓冲区（Color Buffer）</font>**<font style="color:#117CEE;">：存储你在屏幕上看到的 RGB 颜色。</font>
+ **<font style="color:#117CEE;">深度/模板缓冲区（Depth/Stencil Buffer）</font>**<font style="color:#117CEE;">：存储该像素的深度值（Z值）。</font>

<font style="color:#117CEE;">像素着色器依然会跑（因为需要算出是否丢弃像素，或者做 Alpha 测试），它依然会返回一个 float4 值。但在 ROP 写入阶段，这条指令</font><font style="color:#117CEE;background-color:#C1E77E;">切断</font><font style="color:#117CEE;">了</font><font style="color:#117CEE;background-color:#C1E77E;">颜色写入</font><font style="color:#117CEE;">的电路。ROP 只看像素着色器输出的深度值（SV_DEPTH），并把它写入深度贴图。颜色数据被直接丢弃在 ROP 单元的缓存里，根本没走显存总线。</font>

