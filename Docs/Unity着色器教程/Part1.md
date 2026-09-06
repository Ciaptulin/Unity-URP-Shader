由教程转到我自己的教程，原文来自：[https://nedmakesgames.medium.com/writing-unity-urp-shaders-with-code-part-1-the-graphics-pipeline-and-you-798cbc941cea](https://nedmakesgames.medium.com/writing-unity-urp-shaders-with-code-part-1-the-graphics-pipeline-and-you-798cbc941cea)

选择URP项目模板

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786531219007-8417b8c1-a13a-4e69-bd0a-61a2e2285dbd.png)

或进入后在window-package manager里手动添加URP，Or use the blank template, add URP manually through the package manager, and activate it in Graphics settings. In the settings object, make sure that “Depth Priming Mode” is set to “Disabled” and that the rendering mode is “Forward.”

或者使用空白模板，通过包管理器手动添加 URP，然后在图形设置中激活。在设置对象中，确保“深度预备模式”设置为“禁用”，渲染模式设置为“前进”。

> 我觉得这样很好，中文表述不清楚的，直接英文原文+中文翻译对照理解
>

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786531321880-984e9f0b-74ec-436c-bca6-70130055b6cd.png)

接下来搭建项目基础，assets下创建Script、Shader文件夹，Shader下MyLit文件夹，MyLit下创建MyLit.shader，并创建MyLitSphere.mat

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786531830430-b8f5e4a9-bd30-48c5-ad87-59a4c4e49a4b.png)<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786531865435-973d4c63-2624-425a-89de-35c30311bd44.png)

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786532199804-1ab78044-c253-4f3f-b6e9-c8587ef7a48f.png)

MyLit.shader里自动生成的代码删掉

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786532300056-71c0faca-2d80-4a37-bde1-a60116f3d120.png)

有时候如果没有C#脚本，Unity就不会生成Visual Studio项目，所以如果你的着色器没有出现在解决方案资源管理器里，就创建一个空的C#脚本。

着色器的这一部分用一种叫做 ShaderLab 的语言编写，它定义了关于绘图代码的元信息。这第一行打开着色器块，并在材质检查器中定义着色器名称。任何斜线都会在选择菜单中创建子部分——这对组织非常有帮助。该块被卷括号绑定，类似于C#中的类。

<font style="color:#74B602;">着色器不仅仅是绘制代码。单个着色器实际上由许多——有时甚至数千个——较小函数组成。</font>Unity可以根据情况选择运行任意一个。它们被划分为几个细分区。最顶层的子划分称为子着色器。子着色器允许你为不同的渲染管线编写不同的代码。Unity会自动选择正确的子着色器。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786532418838-ef29683d-ec3b-4cfc-a970-89ca27753172.png)

定义一个子着色器，设置一个着色器块，并添加一个标签块来设置渲染管线。标签块以类似<u>C#字典的格式</u>保存用户自定义的元数据。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786532542876-bc838c32-c3af-431c-a782-339e14deafc0.png)

当通用渲染管道激活时，通过将“RenderPipeline”设置为“UniversalPipeline”，告诉Unity使用这个子着色器。这是我们教程中唯一需要的子着色器。

Subshaders are just the first subdivision; below them are passes. Passes’ purpose is more abstract. Each pass has a specific job to help draw the entire scene — like calculating lighting, cast shadows, or special data for post processing effects. Unity expects all shaders to have specific passes to enable all of URP features. For now, let’s focus on the most important pass: the one that draws a material’s lit color.

子着色器只是第一个细分;它们下方是山口。传球的目的更为抽象。每一遍都有特定任务，帮助绘制整个场景——比如计算光照、投射阴影或后期处理特效的特殊数据。Unity 期望所有着色器都有特定的通行证来启用所有 URP 功能。现在，让我们专注于最重要的操作：绘制材料光照颜色的过程。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786532709705-f1fa2837-7081-43d4-b9a2-999eba2748b6.png)

To signal that this pass will draw color, add a Tags block inside. The pass type key is “LightMode”, and the value for our lit color pass is “UniversalForward.” You can also name passes, which helps a lot when debugging.

为了表明这次通道会画色，在里面添加一个标签块。通行类型键是“LightMode”，我们点亮的彩色通行值是“UniversalForward”。你还可以给通行命名，这对调试非常有帮助。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786697671515-18667fdb-5440-4963-be2f-36afb37c7027.png)

好了，我们差不多准备好写代码了。URP 着色器代码用一种叫做 HLSL 的语言编写，类似于简化版的 C++。要标记着色器文件中的某一部分为包含HLSL，<font style="color:#74B602;">请用HLSLPROGRAM和ENDHLSL代码字环绕其周围。</font>

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786697715848-231f6384-4807-4228-9334-3c13d2c9288d.png)

```csharp
Shader "NedMakesGames/MyLit" {
    // Subshaders allow for different behaviour and options for different pipelines and platforms
    SubShader{
        // These tags are shared by all passes in this sub shader
        Tags{"RenderPipeline" = "UniversalPipeline"}

        // Shaders can have several passes which are used to render different data about the material
        // Each pass has it's own vertex and fragment function and shader variant keywords
        Pass {
            Name "ForwardLit" // For debugging
            Tags{"LightMode" = "UniversalForward"} // Pass specific tags. 
            // "UniversalForward" tells Unity this is the main lighting pass of this shader

            HLSLPROGRAM // Begin HLSL code

            ENDHLSL
        }
    }
}
```

为了保持有条理，我喜欢把<font style="color:#74B602;">HLSL代码放在与.shader元数据分开的文件里</font>。幸运的是，这很容易做到。你不能直接在Unity里创建HLSL文件，但你可以在Visual Studio里（选择任意模板并将扩展名改为“.hlsl”），或者在文件系统中创建（创建一个文本文件并将扩展名改为“.hlsl”）。

这个新文件命名为“MyLitForwardLit.hlsl”，在代码编辑器中打开它。我只是想提一下，很多代码编辑器和URP着色器配合得不好。在完成这个教程时，忽略代码编辑器中看到的任何错误，只依赖Unity的控制台。

图形流程。写着色器时，你需要有不同的思维方式。首先，没有“堆”，意味着大多数变量像数值原语一样工作。你也不能定义类或方法，也不能使用继承。结构体和函数依然可用来帮助你组织代码！如果你曾经从事过数据驱动设计，写着色器你会感到自在。重点是**<font style="color:#74B602;">收集数据并将其从一种形式转化为另一种形式</font>**。从最广义上讲，着色器将网格、材质和方向数据转换为屏幕上的颜色。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786606877874-df37982e-cfd6-4861-a77f-52ea91920376.png)<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786606918270-e2db54ad-e92b-4f0a-ba03-4fee0582c4cb.png)

系统会调用两个标准函数，有点像MonoBehavious中的Start和Update，这些函数称为顶点和片元函数，每次通过都必须有两者各一个

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786607025770-b2778ebb-e101-4e76-8f80-0d96547372be.png)

两种函数都是把数据从一种形式转换到另一种形式，顶点函数将网格和世界位置数据转换为屏幕上的位置，片元函数会处理这些位置及材质设置，并生成像素颜色

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786607108735-8f1c8183-483e-4ec5-b4c2-4949b5b94512.png)<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786607121644-969d8c55-fb42-482c-aaf8-cdfc275b2ff8.png)

Unity的渲染系统采用了图形流水线来连接这些功能并处理底层逻辑。流水线收集并准备你的数据，调用顶点和片元函数，并在屏幕上显示最终颜色。它由多个阶段组成，依次运行，就像流水线一样。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786607231737-d62e94a2-ce38-48e3-8444-b694cd949431.png)

每个阶段都有既定的任务，负责转换装配线下游各阶段的数据。顶点阶段和片元阶段是可编程的，运行你写的顶点和片元函数，其它阶段不可编程，所有着色器都运行相同的代码，不过你可以通过不同的设置影响他们。

比如使用Tags标签算不算里面的一种，一直允许深度测试，关闭深度写入，关闭背面剔除这些呢。

### 输入装配器（Input Assembler）
<font style="color:#74B602;">为顶点阶段准备数据，从网格收集数据并将其打包到一个整洁的结构体中</font>。HLSL中的结构体与C#非常相似，一个通过值传递的变量，包含多个数据字段。这个结构体可以自定义，你可以通过向结构体添加字段来确定输入装配器收集的数据

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786607541240-8fa5f9ae-22d2-4db1-8198-bd2b56ec2bc1.png)

_每个顶点对应每个字段的数据：位置、法线和UV。_

输入装配器可以访问哪些数据呢？可以处理网格，特别是网格顶点，每个顶点分配了大量数据，比如位置、法线矢量、纹理UV等。每种数据类型都被称为“顶点数据流”，要访问输入结构中的任何流，只需要给它打标签，装配器会自动帮你设置。

例如，这是我们前向通道的顶点函数的输入结构体。它定义了一个名为 `Attributes` 的结构体。它有一个名为 `position` 的字段，类型为 `float3`。`float3` 是 HLSL 中对 C# `Vector3`（即包含三个浮点数的向量）的称呼。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786607856014-4e9992de-2c66-46de-8343-2f0ddb37a33b.png)

_使用POSITION语义访问位置数据。_

使用**语义（semantics）**来标记变量——输入装配器会自动将它们设置为特定的顶点数据流。例如，`POSITION` 语义对应于顶点位置。请记住，**<font style="color:#74B602;">只有语义才决定输入装配器会选择什么数据</font>**——变量名无关紧要。你可以随意命名变量。我们稍后会看到更多语义，HLSL经常用语义来帮助图形学编程。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786608003227-ed033b7b-f5f5-4d9f-a65b-7788a0f84155.png)

### 顶点阶段（Vertex Stage）
既然这样，我们来讲第一个可编程阶段，顶点阶段，在这里你可以定义这里运行的代码

```csharp
void Vertex(Attributes input) {

}
```

在 HLSL 中定义函数与 C# 非常相似，带有返回类型——这次是 void——函数名和参数列表。参数的类型位于变量名之前。这个函数只需要一个 `Attributes` 类型的参数。

顶点阶段的主要目标是计算网格顶点在屏幕上的位置。但是，请注意 `Attributes` 结构体只包含单个位置——仅单个顶点的数据。<font style="color:#74B602;">渲染管线实际上会</font>**<font style="color:#74B602;">多次调用</font>**<font style="color:#74B602;">顶点函数</font>，为每个顶点传入数据，直到所有顶点都被放置在屏幕上。事实上，许多调用会**<font style="color:#74B602;">并行运行</font>**！

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786640116701-54f8b452-2448-4099-92c4-7df1344525e6.png)

如果你曾经编写过多线程系统，就知道并行处理会带来大量复杂性。<font style="color:#74B602;">着色器通过</font>**<font style="color:#74B602;">禁止存储状态信息</font>**<font style="color:#74B602;">规避了大部分复杂性</font>。因此，每次顶点函数调用与其他所有调用实际上是隔离的。你不能将一个顶点函数的结果——或内部计算的任何数据——传递给另一个。每个调用只能依赖于输入结构体中的数据（以及其他全局数据；稍后详述）。

此外，每次顶点函数调用只知道单个顶点的数据。这是为了效率：GPU 不必一次性加载整个网格。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786640321854-35c17cb5-231f-4f67-98ae-8f52de650fbf.png)

_在Blender中查看顶点的对象空间位置_

我们需要计算 `Attributes` 结构体中描述的顶点的屏幕位置。在谈论位置时，确定其所处的坐标系——"空间"——很重要。<font style="color:#74B602;">位置顶点数据流给出的值处于</font>**<font style="color:#74B602;">对象空间（object space）</font>**，这是你在 Unity 场景编辑器中熟悉的另一名称：<font style="color:#74B602;">局部空间</font>。如果你在 3D 建模软件中查看网格，也会显示这些位置。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786640473850-4d908b34-dab8-470e-b7de-90df0dfabc15.png)

_Unity的Transform组件描述了如何将顶点从对象移动到世界空间_

另一个常见的空间是**世界空间（world space）**。这是所有对象共存的一个通用空间。要从对象空间获得世界空间，只需应用对象的 Transform 组件。Unity 会将这些数据提供给着色器，我们很快就会看到。

然而，顶点在屏幕上的位置是用一个叫做"**裁剪空间（clip space）**"的空间来描述的。对裁剪空间的解释可以单独填满一整个教程，但幸运的是我们不必直接与之打交道。URP 提供了一个便捷的函数，可将对象空间位置转换为裁剪空间。要访问它，我们首先需要访问 URP 着色器库。

```csharp
// Pull in URP library functions and our own common functions
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

struct Attributes {
	float3 position : POSITION; // Position in object space
};

void Vertex(Attributes input) {

}
```

在 HLSL 中，我们可以用 `#include` 指令引用任何其他 HLSL 文件。这些命令告诉着色器处理器读取位于给定位置的文件，并将其内容复制到这一行。如果你好奇 `Lighting.hlsl` 或其他任何 URP 源文件内部是什么，你可以在 packages 文件夹中自行阅读。

```csharp
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
```

被包含的文件本身可以 `#include` 许多其他文件，从而形成一种树状结构。例如，`Lighting.hlsl` 会从整个 URP 库中拉入许多有用的函数。

```csharp
// From Core.hlsl
struct VertexPositionInputs {
    float3 positionWS; // World space position
    float3 positionVS; // View space position
    float4 positionCS; // Homogeneous clip space position
    float4 positionNDC;// Homogeneous normalized device coordinates
};

// From ShaderVariablesFunctions.hlsl
VertexPositionInputs GetVertexPositionInputs(float3 positionOS) {
    VertexPositionInputs input;
    ...
    return input;
}
```

_来自URP着色器库。你的着色器里不需要这个代码。_

其中一个函数 `GetVertexPositionInputs`，位于 `ShaderVariableFunctions.hlsl` 中。它的源代码现在并不重要，但它返回一个结构体，其中包含传入的对象空间位置转换到各种其他空间后的结果。裁剪空间就是其中之一！

```csharp
struct Attributes {
	float3 positionOS : POSITION; // Position in object space
};

void Vertex(Attributes input) {
	// These helper functions, found in URP/ShaderLib/ShaderVariablesFunctions.hlsl
	// transform object space values into world and clip space
	VertexPositionInputs posnInputs = GetVertexPositionInputs(input.position);

	// Pass position and orientation data to the fragment function
	float4 positionClipSpace = posnInputs.positionCS;
}
```

> <font style="color:#74B602;">就是通过这个函数返回一个结构，这个结构里的</font>`<font style="color:#74B602;">positionCS</font>`<font style="color:#74B602;">对象就是裁剪空间的位置</font>
>

请注意，裁剪空间是一个 `float4` 类型。如果你试图将其存储在 `float3` 中，Unity 会警告你数据将被截断——即丢失。这是一个常见的错误来源，所以务必留意这些警告并使用正确的向量大小！

快速跟踪某个位置处于哪个空间可能变得棘手！标准 URP 代码会在所有位置变量后添加一个后缀来指示空间。"OS"表示对象空间，"CS"表示裁剪空间，等等。我们也遵循这种模式。

---

> 知道了这个函数后，我们在自己的着色器里面进行尝试
>

接下来，我们必须完成顶点阶段的工作，为输入顶点输出裁剪空间位置。为此，定义另一个名为 `Interpolators` 的结构体，作为顶点阶段的返回类型。在其中写入一个 `float4 positionCS` 字段，并附上 `SV_POSITION` 语义。<font style="background-color:#C1E77E;">该语义表明此字段包含裁剪空间顶点位置</font>。

```csharp
// This struct is output by the vertex function and input to the fragment function.
// Note that fields will be transformed by the intermediary rasterization stage
struct Interpolators {
	// This value should contain the position in clip space (which is similar to a position on screen)
	// when output from the vertex function. It will be transformed into pixel position of the current
	// fragment on the screen when read from the fragment function
	float4 positionCS : SV_POSITION;
};
```

让 `Vertex` 函数返回一个 `Interpolators` 结构体，声明一个 `Interpolators` 类型的变量，设置其 `positionCS` 字段，然后返回该结构体。

```csharp
// The vertex function. This runs for each vertex on the mesh.
// It must output the position on the screen each vertex should appear at,
// as well as any data the fragment function will need
Interpolators Vertex(Attributes input) {
	Interpolators output;

	// These helper functions, found in URP/ShaderLib/ShaderVariablesFunctions.hlsl
	// transform object space values into world and clip space
	VertexPositionInputs posnInputs = GetVertexPositionInputs(input.positionOS);

	// Pass position and orientation data to the fragment function
	output.positionCS = posnInputs.positionCS;

	return output;
}
```

### 光栅化器（Rasterizer）
<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786649237250-5f67d68e-2050-421f-89c1-c64332b4308a.png)

至此，顶点阶段就完成了。渲染管线中的下一个阶段被称为**光栅化器（rasterizer）**。光栅化器接收顶点的屏幕位置，并计算网格的哪些三角形会出现在屏幕的哪些像素上。如果一个三角形完全在屏幕之外，渲染器会很聪明地直接忽略它！

> <font style="color:#74B602;">光栅化器对一些位置做了变换，后面会提到</font>
>

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786649337219-69fd0459-9b44-4f4e-80a4-a3d413ece9ef.png)

_光栅化器会识别出这些浅灰色像素覆盖了该三角形，并将这一数据沿着渲染管线向下传递。_

光栅化器然后为管线中的下一个阶段——**片段阶段（fragment stage）**——收集数据。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786649413687-dc8fb9c8-52f5-4572-97c2-75bbbac9fae3.png)

### 片元阶段（Fragment Stage）
片元阶段也是可编程的，光栅器判定为包含的三角形内的每个像素都会运行一次片元函数。片元函数计算并输出每个像素的最终颜色，当然每次调用只处理一个像素

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786692185662-f7b747b0-0ae5-4501-acc5-c9b7198d3fcf.png)

```csharp
// The fragment function. This runs once per fragment, which you can think of as a pixel on the screen
// It must output the final color of this pixel
float4 Fragment(Interpolators input) : SV_TARGET {
	return float4(1, 1, 1, 1);
}
```

如上就是一个片元函数，接受一个结构体输入，结构体来自于顶点着色器的输出，自然的，他们的数据类型应相同。顶点阶段和片元阶段并不是直连的，<font style="color:#74B602;">中间的光栅化器会对顶点函数的输出做一点修改，例如将positionCS从裁剪空间位置转化为该片段的像素位置。</font>

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786693487158-8018147b-70a7-488d-8021-22130c831090.png)

_片段的像素位置。像素（0， 0）位于图的左下角_

顶点函数将整个结构体传递给片元函数，你可以在这个包裹里面塞入你想要的数据，这个我们稍后研究。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786693766213-db7d0191-d4ff-4e57-a49b-1831e17d26f2.png)

_黄色被编码为矢量（1， 1， 0， 0）。红色=1，绿色=1，蓝色=0，α（不透明度）=1_

用四个0~1的数来表示三原色和透明度，使用`SV_TARGET`语义标记函数让编译器解释为颜色而不是普通的数字。<font style="color:#74B602;">标记函数时其返回值也会带上标记</font>，例如返回的float4被当作颜色处理。

试着把所有像素都涂成白色并显示到屏幕，我们只需要返回一个所有分量全为1的float4即可。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786694429717-937ad8f2-bd0f-4af7-8da2-4f3a364b0cc0.png)

### 呈现阶段（Presentation Stage）
图形流程的最后一个阶段是呈现阶段，根据片元函数的输出，结合光栅器信息对所有像素进行着色

```csharp
// This file contains the vertex and fragment functions for the forward lit pass
// This is the shader pass that computes visible colors for a material
// by reading material, light, shadow, etc. data

// Pull in URP library functions and our own common functions
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

// This attributes struct receives data about the mesh we're currently rendering
// Data is automatically placed in fields according to their semantic
struct Attributes {
	float3 positionOS : POSITION; // Position in object space
};

// This struct is output by the vertex function and input to the fragment function.
// Note that fields will be transformed by the intermediary rasterization stage
struct Interpolators {
	// This value should contain the position in clip space (which is similar to a position on screen)
	// when output from the vertex function. It will be transformed into pixel position of the current
	// fragment on the screen when read from the fragment function
	float4 positionCS : SV_POSITION;
};

// The vertex function. This runs for each vertex on the mesh.
// It must output the position on the screen each vertex should appear at,
// as well as any data the fragment function will need
Interpolators Vertex(Attributes input) {
	Interpolators output;

	// These helper functions, found in URP/ShaderLib/ShaderVariablesFunctions.hlsl
	// transform object space values into world and clip space
	VertexPositionInputs posnInputs = GetVertexPositionInputs(input.positionOS);

	// Pass position and orientation data to the fragment function
	output.positionCS = posnInputs.positionCS;

	return output;
}

// The fragment function. This runs once per fragment, which you can think of as a pixel on the screen
// It must output the final color of this pixel
float4 Fragment(Interpolators input) : SV_TARGET {
	return float4(1, 1, 1, 1);
}
```

_完成的“MyLitForwardLitPass.hlsl”文件——暂时如此！_

### 注册函数到通道
最后一件事就是将顶点和片元函数注册到着色器通道。在MyLit.shader文件`HLSLPROGRAM`和`ENDHLSL`中用`#pragma`注册函数并用`#include`命令读取`MyLitForwardLitPass.hlsl`文件中的代码。

`#pragma`有各种与着色器元数据相关的用途，其中`vertex` 和 `fragment` 子命令将相应的函数注册到所属通道，这里的函数名要与 HLSL 文件中的名称匹配！

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786697758124-530a8176-c0d9-4666-8ff5-5f2d47a1b517.png)<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786698344321-8083ad6f-4fd1-4280-babe-cae05ddcad9a.png)

在场景中创建球体，接着创建材质，在材质上选择刚刚写好的着色器，并让球体应用材质，应该看到

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786698606234-46a000d6-1489-4806-853f-4077e1fb743d.png)

如果出现洋红色，检查Unity控制台和着色器资产，看看有没有错误。如果有任何问题，请检查 Unity 的控制台和着色器资源，看是否有任何错误。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786698696300-2936439c-af74-40e0-996c-a7b142da3012.png)

## 用材质属性添加颜色
让颜色可以从材质检视面板中调节，可以通过 Unity 称之为"**材质属性（material properties）**"的系统来实现。

材质属性本质上是HLSL变量，可以通过材料检查器设置这些变量让同一个着色器的物体看起来不同。材质是一个带有特定属性设置的着色器。

在Shader中用`Properties`块定义属性，按照惯例，属性带有下划线前缀

```csharp

Shader "NedMakesGames/MyLit" {
    // Properties are options set per material, exposed by the material inspector
    Properties {
        _ColorTint("Tint", Color) = (1, 1, 1, 1)
    }
    ...
}
```

后面跟一对圆括号，就像你在写函数参数一样。第一个参数是字符串。这是标签——它将如何在材质检视面板中显示。下一个参数是属性类型。有多种类型，但 "Color" 定义了一个颜色属性。设置默认值。每种属性类型的语法不同，但对于颜色，以等号开头，然后在括号内写上红-绿-蓝-alpha 值。

你现在可以在材质检视面板中看到你的属性了！

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786712547968-5670f7ac-7dd7-4423-a47b-30d663873148.png)

_材质检视面板中显示的颜色属性_

属性也可以像 C# 中的类一样被打上**特性（attributes）**标签，赋予属性特殊功能。<font style="background-color:#C1E77E;">用 </font>`<font style="background-color:#C1E77E;">[MainColor]</font>`<font style="background-color:#C1E77E;"> 标记</font> `_ColorTint`。这样就可以<font style="background-color:#C1E77E;">通过 C# 使用 </font>`<font style="background-color:#C1E77E;">Material.color</font>` 轻松设置此属性。

```csharp
public class Test : MonoBehaviour {
  
  public Color color;
  public Material material;
  
  void Start() {
    material.color = color;
  }
}
```

属性已设置好，但值并未反映在屏幕上。打开 `MyLitForwardLit.hlsl`。

```csharp

// This file contains the vertex and fragment functions for the forward lit pass
// This is the shader pass that computes visible colors for a material
// by reading material, light, shadow, etc. data

...

float4 _ColorTint;

...

// The fragment function. This runs once per fragment, which you can think of as a pixel on the screen
// It must output the final color of this pixel
float4 Fragment(Interpolators input) : SV_TARGET {
	return _ColorTint;
}
```

尽管我们在 ShaderLab 中定义了一个属性，我们也必须在 HLSL 中定义它——确保参考名称完全匹配。Unity 会自动将此变量与材质检视面板同步。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786713157336-78eaa2e1-e5e6-4393-b563-a365b5eff9c9.png)

_碎片函数还可以访问材料属性_

之前我说过，顶点和片段函数只能访问来自单个顶点或片段的数据。虽然这是真的，但它们也可以访问任何材质属性。这些变量是"**uniform**"的，意味着它们在管线运行期间不会改变。Unity 在管线开始前设置它们，你无法从顶点或片段函数中修改它们。

考虑到这一点，让片段函数返回 `_ColorTint` 作为最终颜色。

---

**知识补充：**

像 `_ColorTint` 这种需要从材质面板接收数据的变量，本质上是**全局 Uniform 变量**。它们不能定义在结构体内部（结构体是用来传递顶点数据流和插值数据的），所以必须像你现在这样声明在外部。

<font style="background-color:#C1E77E;">位置写在#include之后，结构体数据之前</font>

在 URP 中，Unity 引入了 **SRP Batcher** 来大幅提升渲染合批性能。为了让 Shader 兼容 SRP Batcher，所有**材质属性（Material Properties）** 必须<font style="background-color:#C1E77E;">放在名为 </font>`<font style="background-color:#C1E77E;">UnityPerMaterial</font>`<font style="background-color:#C1E77E;"> 的常量缓冲区中</font>。

```glsl
// 本文件包含前向光照通道的顶点和片段函数
// 这是通过读取材质、光照、阴影等数据来计算材质可见颜色的着色器通道

// 引入URP库函数和我们自己的通用函数
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

CBUFFER_START(UnityPerMaterial)
    float4 _ColorTint; // 颜色色调属性
CBUFFER_END

// 此属性结构体接收当前渲染网格的相关数据
// 数据会根据语义自动填充到对应字段中
struct Attributes {
  float3 positionOS : POSITION; // 对象空间中的位置
};

// 此结构体由顶点函数输出，并作为片段函数的输入
// 注意：字段将被中间的光栅化阶段进行变换
struct Interpolators {
  // 该值从顶点函数输出时应包含裁剪空间中的位置（类似于屏幕上的位置）
  // 当从片段函数读取时，它将被转换为当前片段在屏幕上的像素位置
  float4 positionCS : SV_POSITION;
};

// 顶点函数。对网格上的每个顶点运行一次。
// 必须输出每个顶点在屏幕上应出现的位置，以及片段函数所需的任何数据
Interpolators Vertex(Attributes input) {
  Interpolators output;

  // 这些辅助函数位于 URP/ShaderLib/ShaderVariablesFunctions.hlsl 中
  // 用于将对象空间的值转换为世界空间和裁剪空间
  VertexPositionInputs posnInputs = GetVertexPositionInputs(input.positionOS);

  // 将位置和方向数据传递给片段函数
  output.positionCS = posnInputs.positionCS;

  return output;
}

// 片段函数。对每个片段（可理解为屏幕上的一个像素）运行一次
// 必须输出该像素的最终颜色
float4 Fragment(Interpolators input) : SV_TARGET {
  return _ColorTint;
}
```

返回场景编辑器，选择你的材质并更改颜色色调属性。着色器应该立即反映出你的选择！

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786713496456-9e447c12-49d1-4129-9b7d-140f75aa4bbb.png)

_更改颜色色调后，球体立即反映新颜色_

## 用纹理改变颜色
平坦的颜色很棒，但我想让颜色在球体上变化。我们可以用纹理做到这一点！

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786875179744-cc83c6d7-5a93-40cd-bb86-32fdde9c2eec.png)<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786875178673-359170c0-1de0-412e-af3b-dfb04802766d.png)

_放大贴图（不混合），它们其实只是二维数组的事实会更明显。数组中的每个位置都包含一种颜色_

着色器喜欢处理纹理。它们只是图像文件，但着色器将它们视为颜色数据的二维数组。要向着色器添加纹理，首先添加一个纹理材质属性。

```glsl

Shader "NedMakesGames/MyLit" {
    // Properties are options set per material, exposed by the material inspector
    Properties{
        [Header(Surface options)] // Creates a text header
        // [MainTexture] and [MainColor] allow Material.mainTexture and Material.color to use the correct properties
        [MainTexture] _ColorMap("Color", 2D) = "white" {}
        [MainColor] _ColorTint("Tint", Color) = (1, 1, 1, 1)
    }
    ...
}
```

定义纹理属性与颜色属性非常相似。与其将类型列为 `Color`，不如将其设为 `2D`。默认纹理的语法很奇怪。在等号后面，键入带引号的 "white" 后跟一对花括号。如果在材质检视面板中没有设置纹理，Unity 将用一个小的白色纹理填充此属性。你也可以将默认颜色设置为 "black"、"gray" 或 "red"。

与 `[MainColor]` 特性类似，有一个 `[MainTexture]` 特性。标记此属性使得可以通过 C# 使用 `Material.mainTexture` 字段轻松赋值。

你的属性现在应该显示在材质检视面板中了。注意它旁边的四个数字。它们允许你为此纹理设置偏移和缩放，这对于平铺很有用。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786879028492-85f9b153-9e06-4056-a962-1e13c0c7e103.png)

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786879058989-db50666e-f8c2-4fa6-b190-76cc7fdc500e.png)

_材质检视面板中的纹理属性及平铺/偏移参数_

### HLSL 中的纹理和 UV
现在，让我们看看 HLSL 这方面的事情。

```glsl
// Textures
TEXTURE2D(_ColorMap); // RGB = albedo, A = alpha
```

定义纹理变量比颜色稍微复杂一些。你必须使用这种特殊语法来定义二维纹理变量。同样，名称必须与属性参考名称完全匹配。

这里的 `TEXTURE2D` 不是一个类型，而是叫<font style="background-color:#C1E77E;">做"</font>**<font style="background-color:#C1E77E;">宏（macro）</font>**<font style="background-color:#C1E77E;">"</font>的东西。你可以将宏视为类似于函数，只不过它们在<font style="background-color:#C1E77E;">组成代码的文本上运行</font>。你可以使用 `#define` 命令自己创建宏。

```glsl
// Macro:
#define MY_MACRO(argument) argument + 2

// MY_MACRO(4);
// expands to:
// 4 + 2;

// float var = MY_MACRO(floatVariable);
// expands to
// float var = floatVariable + 2
```

_这是一个例子。你不需要把它加到着色器里_

在编译之前，系统会搜索任何与已定义宏匹配的文本，并将宏名称替换为你指定的文本。宏也可以有参数。系统会将宏定义中出现的任何参数名称替换为传入的任何文本。

这是对宏的一个非常简单概述，但它们在着色器代码中相当有用。HLSL 没有继承或多态，所以如果你想处理任何具有 `positionOS` 字段但你不一定知道结构体类型的结构，宏可以解决这个问题。

```glsl
// Macro
// Use a macro to work on a positionOS field from any struct
#define MY_MACRO(myStruct) myStruct.positionOS * 0.5

struct StructureA {
  float3 positionOS;
  float otherValue;
}

struct StructureB {
  float3 positionOS;
  float4 otherColor;
}

void Work(StructureA structA, StructureB structB) {
  float3 a = MY_MACRO(structA);
  // float3 a = structA.positionOS * 0.5
  float3 b = MY_MACRO(structB);
}
```

_这是一个例子。你不需要把它加到着色器里_

它们在处理平台差异方面也很棒，Unity 用 `TEXTURE2D` 正是做到了这一点。你看，不同的图形 API（DirectX、OpenGL 等）对纹理使用不同的类型名称。为了使着色器代码独立于平台，Unity 提供了各种宏来处理纹理。这让我们可以少操一份心！

```glsl
// Textures
TEXTURE2D(_ColorMap); SAMPLER(sampler_ColorMap); // RGB = albedo, A = alpha

float4 _ColorMap_ST; // 这是Unity自动设置的，供TRANSFORM_TEX使用来应用UV平铺
```

继续，当你定义纹理属性时，Unity 会自动设置另外几个变量。纹理有一个配套的结构体叫做"**采样器（sampler）**"，它定义了如何读取纹理。选项包括你在纹理导入器中熟悉的采样和钳制模式——点采样、双线性等。

Unity 将采样器存储在第二个变量中，你用 `SAMPLER` 宏定义它。这里的名称很重要；它必须始终遵循"**<font style="background-color:#C1E77E;">sampler</font>**<font style="background-color:#C1E77E;"> 后跟纹理参考名称</font>"的模式。

最后，还记得材质检视面板中的平铺和偏移值吗？Unity 将它们存储在 `float4` 变量中。名称必须遵循"纹理名称后跟 `_ST`"的模式。在其内部，X 和 Y 分量保存 X 和 Y 缩放，而 Z 和 W 分量保存 X 和 Y 偏移。

```glsl
// The fragment function. This runs once per fragment, which you can think of as a pixel on the screen
// It must output the final color of this pixel
float4 Fragment(Interpolators input) : SV_TARGET {
	// Sample the color map
	float4 colorSample = SAMPLE_TEXTURE2D(_ColorMap, sampler_ColorMap, uv);
}
```

现在，我们需要对纹理进行**采样**（Sample），也就是从中读取颜色数据。我们将在**片元阶段**（fragment stage）执行此操作，以便将纹理颜色应用到各个像素上。请使用 `SAMPLE_TEXTURE2D` 宏（macro）来从特定位置获取纹理的颜色。该宏接收三个参数：**<font style="background-color:#C1E77E;">纹理对象</font>**<font style="background-color:#C1E77E;">、</font>**<font style="background-color:#C1E77E;">采样器</font>**<font style="background-color:#C1E77E;">（sampler）以及要采样的 </font>**<font style="background-color:#C1E77E;">UV 坐标</font>**。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786879891521-3acfd277-77e2-43b2-b373-b79b93d9ec38.png)

_这个球体模型的UV将每个顶点映射到平面上的位置。我们可以用它们在3D形状上绘制纹理_

### 什么是 UV？
首先，什么是 UV？UV 是分配给网格所有顶点的纹理坐标，定义了纹理如何包裹模型。想想制图师如何试图将地球展开以适应平面地图。他们基本上是在为地球上的位置分配 UV。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786879915972-e1273dd2-cf72-4029-83d9-0453edf10bd9.png)<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786879923304-c2e13e90-3faf-4b68-a076-d77fa36d7acc.png)

_这个地球模型会把贴图“展开”到一个平面上_

UV 是 `float2` 变量，其中 X 和 Y 坐标定义了纹理上的二维位置。UV 是**归一化的**，或与纹理的尺寸无关。它们总是在零到一的范围内。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786879957440-c678854a-0a8f-4f7e-bd35-813190dbc838.png)

_纹理上的几个UV坐标。注意（1， 1）总是在右上角，无论纹理的尺寸或宽高比如何_

### 插值顶点数据
我们无法在片段阶段凭空抓取 UV——它们是<font style="background-color:#C1E77E;">输入装配器</font>需要收集的又一个<font style="background-color:#C1E77E;">顶点数据流</font>。

```glsl

// This attributes struct receives data about the mesh we're currently rendering
// Data is automatically placed in fields according to their semantic
struct Attributes {
	float3 positionOS : POSITION; // Position in object space
	float2 uv : TEXCOORD0; // Material texture UVs
};
```

向 `Attributes` 结构体添加一个 `float2 uv` 字段，使用 `TEXCOORD0` 语义，这是"<font style="background-color:#C1E77E;">texture coordinate set number zero（第零组纹理坐标）</font>"的缩写。模型可以有多组 UV——例如 Unity 使用 `TEXCOORD1` 作为光照贴图 UV，但我们稍后会讲到。

`Attributes` 结构体在片段阶段也是不可用的。但是，我们可以将数据存储在 `Interpolators` 结构体中，它最终会到达片段阶段。

> `Attributes`结构体的生命周期不会到达片元阶段，他们中间是需要传递数据的，例如变量从裁剪空间到光栅化器这里，转化屏幕空间，再到达片元处理阶段
>

```glsl

// This struct is output by the vertex function and input to the fragment function.
// Note that fields will be transformed by the intermediary rasterization stage
struct Interpolators {
	// This value should contain the position in clip space (which is similar to a position on screen)
	// when output from the vertex function. It will be transformed into pixel position of the current
	// fragment on the screen when read from the fragment function
	float4 positionCS : SV_POSITION;

	// The following variables will retain their values from the vertex stage, except the
	// rasterizer will interpolate them between vertices
	float2 uv : TEXCOORD0; // Material texture UVs
};
```

在那里<font style="background-color:#C1E77E;">添加另一个 </font>`<font style="background-color:#C1E77E;">float2 uv</font>`<font style="background-color:#C1E77E;"> 字段</font>，同样使用 `TEXCOORD0` 语义。

```glsl
// The vertex function. This runs for each vertex on the mesh.
// It must output the position on the screen each vertex should appear at,
// as well as any data the fragment function will need
Interpolators Vertex(Attributes input) {
	Interpolators output;

	// These helper functions, found in URP/ShaderLib/ShaderVariablesFunctions.hlsl
	// transform object space values into world and clip space
	VertexPositionInputs posnInputs = GetVertexPositionInputs(input.positionOS);

	// Pass position and orientation data to the fragment function
	output.positionCS = posnInputs.positionCS;
	output.uv = TRANSFORM_TEX(input.uv, _ColorMap);

	return output;
}
```

在 `Vertex` 函数中，将 UV 从 `Attributes` 结构体传递到 `Interpolators` 结构体。我们也可以在这里<font style="background-color:#C1E77E;">应用 UV 缩放和偏移</font>——不妨这样做！这样我们只会在每个顶点计算一次，而不是每个像素计算一次。由于在<font style="background-color:#C1E77E;">顶点函数中尽可能多地做事</font>是个好主意，因为它的运行次数通常少于片段函数。

> 在顶点计算确实相对于片元着色器里计算缩放是要好些，像素的数量那可太多了啊~
>
> 传给光栅化器的数据已经通过缩放和偏移处理
>

```glsl

#define TRANSFORM_TEX(tex, name) (tex.xy * name##_ST.xy + name##_ST.zw)

// TRANSFORM_TEX(input.uv, _ColorMap)
// evaluates to
// input.uv.xy * _ColorMap_ST.xy + _ColorMap_ST.zw
```

Unity 提供了 `TRANSFORM_TEX` 宏来应用平铺。关于它有两件有趣的事情。首先，<font style="background-color:#C1E77E;">双井号 </font>`<font style="background-color:#C1E77E;">##</font>` 告诉预编译器将<font style="background-color:#C1E77E;">文本附加到作为参数传入的任何内容之后</font>。当宏运行时，你可以看到它如何将 `name` 替换为 `_ColorMap`，正确引用了 `_ColorMap_ST`。

```glsl

float4 vector = float4(1, 2, 3, 4); // (x, y, z, w)

float z = vector.z; // 3
float2 horizontal = vector.xz; // (1, 3)
float fourx = vector.xxxx; // (1, 1, 1, 1)
float4 reverse = vector.wzyx; // (4, 3, 2, 1)
float4 noY = vector;
noY.y = 0; // (1, 0, 2, 3)
float4 replace = vector;
replace.xyz = float3(7, 8, 9); // (7, 8, 9, 4)

float4 color = float4(0.1, 0.2, 0.3, 0.4); // (r, g, b, a)
// You can do all the same things with rgba!
float blue = color.b; // 0.3
float onlyGreen = color;
onlyGreen.xz = 0; // (0, 0.2, 0, 0.4)
// No mixing xyzw and rgba!
```

其次，`xy` 和 `zw` 后缀让你轻松访问一对分量。这种机制称为"**<font style="background-color:#C1E77E;">swizzling（分量重排）</font>**"。你可以以<font style="background-color:#C1E77E;">任意顺序</font>请求 x、y、z 和 w 分量的任意组合。编译器将为你构造一个适当大小的 float 向量变量。你也可以用同样的方式使用 r、g、b 和 a——对颜色更直观。甚至<font style="background-color:#C1E77E;">可以用 swizzle 运算符赋值</font>。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786880793042-5d235046-fa90-4d74-807c-0afaaeb69e63.png)

_每个顶点的值都不同。光栅器如何决定每个片段调用要赋予哪个值？_

无论如何，现在我们在片段阶段有了 UV 数据。但是，让我们花点时间真正思考一下这里发生了什么。顶点函数为每个顶点输出数据。光栅化器接收这些值，将顶点放置在屏幕上，找出哪些像素覆盖了所形成的三角形，最后为每个片段函数调用生成一个输入结构体。对于每个片段，`input.uv` 的值会是什么？

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786880821587-efe99abf-a0e0-4124-83e4-098e4e63baae.png)

_一个插值在一条线的两端之间。线性插值。_

光栅化器会使用一种叫做"**<font style="background-color:#C1E77E;">重心插值（barycentric interpolation）</font>**"的算法，<font style="background-color:#C1E77E;">对任何用 </font>`<font style="background-color:#C1E77E;">TEXCOORD</font>`<font style="background-color:#C1E77E;"> 语义标记的字段进行插值</font>。你可能熟悉线性插值，即数轴上的值表示为端点值的加权平均。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786880859784-5ca33ed4-2f84-4402-b548-3fb15e9d613c.png)

_一个在三角形的三个角之间插值的值。重心插值。_

重心插值思路相同，只是在三角形上。三角形内任意点的值是每个角点值的加权平均。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786880900680-860db221-9e92-44e0-b76a-38163016632d.png)

_这是一个光栅器如何通过插值顶点数据为每个片段调用分配值的例子。_

幸运的是，<font style="background-color:#C1E77E;">光栅化器</font>为我们<font style="background-color:#C1E77E;">处理了这些</font>，所以算法本身并不重要。回顾一下，`Interpolators` 中的值是顶点函数返回值的组合。具体来说，对于任何片段，它们是形成覆盖该片段的三角形的三个顶点的值的组合。

```glsl
// The fragment function. This runs once per fragment, which you can think of as a pixel on the screen
// It must output the final color of this pixel
float4 Fragment(Interpolators input) : SV_TARGET {
  float2 uv = input.uv;
  // Sample the color map
  float4 colorSample = SAMPLE_TEXTURE2D(_ColorMap, sampler_ColorMap, uv);

  return colorSample * _ColorTint;
}
```

### 采样纹理
为了拿到这些 UV 做了这么多工作，但现在我们有了调用 `SAMPLE_TEXTURE2D` 所需的一切。它返回一个 `float4`，即指定 UV 位置处纹理的颜色。根据采样器的采样模式（点采样、双线性等），此颜色可能是相邻像素的组合，以帮助平滑效果。

在 HLSL 中，<font style="background-color:#C1E77E;">两个向量相乘是按分量进行</font>的，这意味着每个向量的 X 分量相乘，然后是 Y 分量，以此类推。所有算术运算符都以这种方式工作。

在场景编辑器中，在你的材质上设置一个纹理，然后惊叹于你所取得的成就！

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1786880997199-31b463d4-bb74-4e29-8d0b-9ecaa13af273.png)

请注意，如果你的纹理具有 alpha 分量，着色器尚未处理透明度。球体将始终是不透明的。请继续关注以修复这个问题！

