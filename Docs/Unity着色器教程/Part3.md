## <font style="color:#117CEE;background-color:#C1E77E;"></font>引言
<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787024864557-d1a21d08-a6e0-4471-858f-91bfd8db52f9.png)<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787024898817-6fb12df3-a30c-46ec-b9c7-93fa1c8c5a6a.png)

如果你跟着色器开发者聊过天，几乎没有哪个词比"透明度（transparency）"更能让他们胆战心惊了！好吧，在本教程中，我想稍微揭开透明着色器的神秘面纱。在这个过程中，我们将学习**渲染队列、自定义检视器、混合模式、Alpha 裁剪、缠绕剔除和双面法线**。

废话不多说，让我们开始编程吧！

---

## Alpha 混合（Alpha Blending）
到目前为止，我们的着色器一直忽略了主纹理的 Alpha 通道，保持完全不透明。我觉得是时候改变了！透明度是一个复杂的话题，原因有很多，但上手其实很简单——只需在你的 Pass 块中添加一行代码。

```csharp
Shader "NedMakesGames/MyLit" {
    ... // Code omitted
    SubShader {
        Tags {"RenderPipeline" = "UniversalPipeline"}

        Pass {
            Name "ForwardLit"
            Tags{"LightMode" = "UniversalForward"}
            // Blend [SourceFactor] [DestinationFactor]
            Blend SrcAlpha OneMinusSrcAlpha
            
            ... // Code omitted
        }

        ... // Code omitted
    }
}
```

这个 `Blend` 命令决定了光栅化器如何将片段函数（fragment function）的输出与屏幕上（或渲染目标上）已有的颜色进行混合。这些已有的颜色是由之前运行的着色器绘制出来的！片段函数返回的颜色称为**源颜色（source color）**，而渲染目标上存储的颜色称为**目标颜色（destination color）**。

<font style="color:#117CEE;">原颜色和目标颜色调换位置就会产生透明度反转效果（不是负片效果，那需要颜色反转）</font>

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787024992502-9849fdd4-b4a9-45ab-ae87-d59cdde8e5a6.png)<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787025009823-71dbdbe4-40a0-4e29-88b7-050f8c6bf5fe.png)

_源颜色由 Fragment 函数返回_

光栅化器将每种颜色乘以某个数值，然后将乘积相加，把结果存回渲染目标，覆盖之前的内容。你可以用 `Blend` 命令指定这些乘数：先是源颜色乘数，然后是目标颜色乘数。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787025039527-09cbabf4-f323-4ba7-89c1-b2b7b7cee5aa.png)

+ `Blend One Zero` → 完全不透明材质——即默认值。
+ 对于透明度，我们需要根据源颜色的 Alpha 值在源颜色和目的地颜色之间进行线性插值。幸运的是，ShaderLab 提供了"源 Alpha"和"一减源 Alpha"乘数，完美契合我们的需求。将其添加到你的 ForwardLit Pass 块中

<font style="color:#117CEE;">对于不透明材质：请直接删除 Blend 这一行，或者显式写成 Blend Off。不要写 Blend One Zero，因为它在视觉上多此一举，且徒增性能损耗</font>

<font style="color:#117CEE;">只有在为了动态开关混合功能（例如配合 MaterialPropertyBlock 控制透明度开关）时，才可能需要用到 Blend One Zero 作为“混合开启但不透明”的过渡状态，否则请保持简洁</font>

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787025101218-46ba03a6-927d-47f7-a652-6a56e8b20b5b.png)

_红色球本应是透明的，但融合不正确_

在场景中，通过降低材质颜色色调的 Alpha 值，或放入一张带 Alpha 通道的纹理来测试混合效果。不幸的是，没过多久你就会注意到一些问题。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787025145618-2bbb317d-cff5-45d2-92e2-8b492afe6914.png)

_深度缓冲区存储每个绘制像素的表面深度_

### ZWrite 模式
还记得我们讨论阴影映射时提到的**深度缓冲区（depth buffer）**吗？目前，光栅化器会将透明对象的位置存入深度缓冲区，导致它后面的片段永远无法运行<font style="color:#117CEE;">（遮挡的对象会被剔除，因为你写入了深度）</font>。如果某个材质根本没有被绘制，我们就无法与它进行颜色混合<font style="color:#117CEE;">（剔除后物体当然没有被绘制，也就不能进行混合）</font>！我们需要一种方法来阻止透明表面被写入深度缓冲区。<font style="color:#117CEE;">所以关闭深度写入应运而生</font>

```csharp

Shader "NedMakesGames/MyLit" {
    ... // Code omitted
    SubShader {
        Tags {"RenderPipeline" = "UniversalPipeline"}

        Pass {
            Name "ForwardLit"
            Tags{"LightMode" = "UniversalForward"}

            Blend SrcAlpha OneMinusSrcAlpha
            ZWrite Off
            
            ... // Code omitted
        }

        ... // Code omitted
    }
}
```

幸运的是，这也很容易做到。在你的 ForwardLit Pass 块中添加这个 `ZWrite Off` 命令：

```plain
ZWrite Off
```

这会阻止光栅化器将该 Pass 的任何数据写入深度缓冲区。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787025223136-5841c9a4-3159-4055-a077-a0eb32f3fe1c.png)

现在，这个着色器后面的表面总能正确绘制了。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787025233150-a9677217-6ac7-4d28-b829-b3ae9f65319c.png)

### 渲染队列（Render Queues）
嗯，但仍然存在一些奇怪的现象。天空盒（skybox）完全覆盖了所有透明对象——这是因为**渲染顺序**的问题。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787025256991-3365fab9-bdcb-4858-88ab-5bc38da73503.png)

_完全不透明的绿色和红色像素会根据绘制顺序产生不同的最终颜色（当然，只有在关闭深度缓冲时才会如此）_

混合操作取决于对象绘制到渲染目标的顺序。**透明对象****<font style="background-color:#C1E77E;">后面的物体必须先绘制</font>**，才能与之混合！幸运的是，我们可以用渲染队列来控制绘制顺序。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787025279796-14ab4587-4193-4a35-98a3-9c93c680dce1.png)

在准备渲染场景时，URP 会查看所有可渲染对象，并按渲染队列对它们进行排序。你可以使用 `SubShader` 的 tags 块中设置的 `<font style="background-color:#C1E77E;">Queue</font>` 标签将<font style="background-color:#C1E77E;">着色器放入不同的队列</font>。默认设置是 `"Geometry"`，用于不透明材质。`"Transparent"` 队列排在 Geometry 之后<font style="color:#117CEE;">（Queue设置为Transparent自然就在不透明的后面了，具体看上面的渲染队列图）</font>。通过将 MyLit 放入这个队列，我们可以确保不透明对象先绘制。

还有一个 `"Skybox"` 队列，运行在 `Geometry` 和 `Transparent` 之间。之前，天空盒在 MyLit 之后渲染，而由于 MyLit 设置了 `ZWrite Off`，光栅化器允许天空盒着色器覆盖它。使用 Transparent 队列后，这就不是问题了。

<font style="color:#117CEE;">由于 ZWrite Off，球体成功画在了屏幕上，但深度缓冲区没有被更新，依然保留着</font><font style="color:#117CEE;background-color:#C1E77E;">清空时</font><font style="color:#117CEE;">的</font><font style="color:#117CEE;background-color:#C1E77E;">默认值</font><font style="color:#117CEE;">（通常是最远距离 1.0），天空盒的深度通常也是 1.0（最远）。进行深度测试（ZTest LEqual，默认）时，因为 1.0 <= 1.0 条件成立（通过），所以</font><font style="color:#117CEE;background-color:#C1E77E;">天空盒</font><font style="color:#117CEE;">的像素</font><font style="color:#117CEE;background-color:#C1E77E;">覆盖</font><font style="color:#117CEE;">了刚才球体的像素</font>

<font style="color:#117CEE;">我注意到Pass里也有tags块，能设置tags块控制Pass的渲染顺序。SubShader Tags 决定“这个物体什么时候画”，而 Pass Tags 决定“这个物体具体怎么画”</font>

```csharp
Shader "NedMakesGames/MyLit" {
    ... // Code omitted
    SubShader {
        Tags {"RenderPipeline" = "UniversalPipeline" "RenderType" = "Transparent" "Queue" = "Transparent"}

        ... // Code omitted
    }
}
```

为了调试以及一些更高级的系统，，Unity 还有一个 `<font style="background-color:#C1E77E;">RenderType</font>` 标签。它应设置为 `"Opaque"` 或 `"Transparent"`。`RenderType` 不影响渲染顺序，但我们现在就把它设置好。

<font style="color:#117CEE;">RenderType是对Shader进行分类而不控制渲染顺序，以便Unity（主要是内置渲染管线）在运行时能根据这个分类，批量地替换物体的Shader</font>

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787025320211-11be45bf-d3d5-4f48-9c4b-0af43618f660.png)

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787276612169-50092e11-fe9c-4a39-accc-c7d665c61b79.png)

_<font style="color:#117CEE;">这里点开颜色后设置透明度才能表现出来半透明效果</font>_

<font style="color:#117CEE;">尝试注释掉透明混合和深度写入的代码，并删掉控制Queue 标签，调整透明度会失效，一直保持不透明状态</font>

现在，两个透明球体都应该显示在天空盒前面了。注意球体之间也能正确相互叠加绘制。根据我们对渲染顺序的了解，你可能会猜到——没错——URP 会按**从相机距离由远及近**对同一个队列内的对象进行排序。这对透明着色器至关重要。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787025363939-88341fd0-9fe3-4f3a-9f88-d8e56f28ffb2.png)

_左边模型写入深度缓冲区，右边模型不写_

不幸的是，这种排序**不会**延伸到<font style="background-color:#C1E77E;">单个网格</font>内的三角形。如果你的网格有很多重叠的部分，它们可能会相互覆盖。唯一<font style="background-color:#C1E77E;">可靠</font>的解决方法是把<font style="background-color:#C1E77E;">网格拆成多个部分</font>。这只是使用透明材质时必须忍受的诸多头疼问题之一……

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787025396461-5afafd37-319f-4b17-8176-3515bba3df09.png)

在继续之前，打开**帧调试器（Frame Debugger）**看看。你可以看到渲染顺序，并验证每个对象是否在正确的队列中。查看 `"DrawTransparentObjects!"` 下面。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787045164436-165896eb-95f4-4050-9217-e434ba05c3e4.png)

如果出于某种原因你需要按材质微调绘制顺序，每个材质的<font style="color:#117CEE;">检视器底部</font>都有一个队列字段。你可以更改队列，甚至给某些材质赋予优先级。`"Geometry+1"` 队列在所有 Geometry 队列对象之后运行，但仍在 Skybox 队列之前。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787310987494-7a13c0df-cfa2-4bfc-9043-17866b8c5236.png)

<font style="color:#117CEE;">这里选中MyLitSphere材质，下方的渲染队列这里，直接输入2001，会自动生成一个Geomery+1的选项</font>

| <font style="color:#117CEE;">队列名称</font> | <font style="color:#117CEE;">内置数值</font> | <font style="color:#117CEE;">绘制顺序（优先级）</font> |
| --- | --- | --- |
| **<font style="color:#117CEE;">Background</font>** | <font style="color:#117CEE;">1000</font> | <font style="color:#117CEE;">最先画（最底层，如天空盒）</font> |
| **<font style="color:#117CEE;">Geometry</font>** | <font style="color:#117CEE;">2000</font> | <font style="color:#117CEE;">默认不透明物体</font> |
| **<font style="color:#117CEE;">Geometry+1</font>** | <font style="color:#117CEE;">2001</font> | <font style="color:#117CEE;">稍晚于不透明物体（你正在用的）</font> |
| **<font style="color:#117CEE;">AlphaTest</font>** | <font style="color:#117CEE;">2450</font> | <font style="color:#117CEE;">透明裁剪物体</font> |
| **<font style="color:#117CEE;">Transparent</font>** | <font style="color:#117CEE;">3000</font> | <font style="color:#117CEE;">半透明物体（从后往前画）</font> |
| **<font style="color:#117CEE;">Overlay</font>** | <font style="color:#117CEE;">4000</font> | <font style="color:#117CEE;">最后画（最顶层，如UI）</font> |


**<font style="color:#117CEE;">注意</font>**<font style="color:#117CEE;">：这个数值可以不是整数，也可以是 </font>`<font style="color:#117CEE;background-color:rgb(235, 238, 242);">2001.5</font>`<font style="color:#117CEE;">，但实际使用中填整数 </font>`<font style="color:#117CEE;background-color:rgb(235, 238, 242);">2001</font>`<font style="color:#117CEE;"> 最稳妥。</font>

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787045191674-5748481a-eeb5-4d3c-9a97-66712110829d.png)

_白色立方体使用透明光照材料，且不投射阴影_

你可能还注意到另一个 bug：**透明对象投射了完全不透明的阴影**。<font style="background-color:#C1E77E;">透明或半透明阴影非常复杂</font>，本系列不会涉及。无论好坏，Lit 着色器也不支持透明阴影。我们所能做的最好的办法就是为<font style="background-color:#C1E77E;">透明对象禁用阴影</font>。但要做到这一点，我们需要搭建一些 C# 基础设施……

---

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787045226135-9ae365d6-ccc3-4138-b2e0-c166503b8a65.png)

## 自定义材质检视器（Custom Material Inspectors）
如果你想像以前一样将这个着色器用于不透明材质，你可以使用不透明的纹理和色调。但这远非最优解。因为我们关闭了 Z 写入，就没有了防止过度绘制（overdraw）的保护。队列和渲染类型也不正确。

有没有办法通过材质属性来更改这些设置？嗯，有，但我们必须记得同步正确设置它们。让我们创建一个自定义材质检视器脚本，通过一个下拉菜单轻松在**不透明**和**透明**模式之间切换。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787045260508-5ca9eae9-21c8-4b47-84a6-4b109d5ddd05.png)

### 设置步骤
**1. 创建编辑器脚本**

Unity 编辑器脚本放在名为 `"Editor"` 的文件夹中，所以先创建这个文件夹。在其中创建一个名为 `"MyLitCustomInspector"` 的 C# 脚本。

<font style="color:#117CEE;">放在 Editor 文件夹里的脚本，只在 Unity 编辑器环境下运行</font>

```csharp

using UnityEditor;
using UnityEngine;
using UnityEngine.Rendering;

public class MyLitCustomInspector : ShaderGUI {

    public override void OnGUI(MaterialEditor materialEditor, MaterialProperty[] properties) {

        Material material = materialEditor.target as Material;

    }
}
```

打开它，然后删掉 `Start` 和 `Update` 函数。将 `MyLitCustomInspector` 的父类改为 `ShaderGUI`（该类位于 `UnityEditor` 命名空间下）。

Unity 编辑器脚本涉及的知识点非常多，但我们目前只需要用到其中几个核心特性。首先，**重写（override）**`**OnGUI**`** 方法**——这是 Unity 在需要绘制材质检视面板（Material Inspector）时会自动调用的回调。我们可以通过 `MaterialEditor` 的 `target` 字段来获取当前正在查看的材质（Material）对象。

```csharp
Shader "NedMakesGames/MyLit" {
    Properties{
        [Header(Surface options)]
        [MainTexture] _ColorMap("Color", 2D) = "white" {}
        [MainColor] _ColorTint("Tint", Color) = (1, 1, 1, 1)
        _Smoothness("Smoothness", Float) = 0

        // “幕后管道”属性，负责把你在下拉菜单里的选择，翻译成 Shader 底层渲染指令
        [HideInInspector] _SourceBlend("Source blend", Float) = 0
        [HideInInspector] _DestBlend("Destination blend", Float) = 0
        [HideInInspector] _ZWrite("ZWrite", Float) = 0

        // [HideInInspector] 只针对“Unity默认的检视面板”生效
        [HideInInspector] _SurfaceType("Surface type", Float) = 0
    }
    SubShader {
        Tags {"RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline"}

        Pass {
            Name "ForwardLit"
            Tags{"LightMode" = "UniversalForward"}

            Blend[_SourceBlend][_DestBlend]
            ZWrite[_ZWrite]

            ... // Code omitted
        }

        Pass {
            Name "ShadowCaster"
            Tags{"LightMode" = "ShadowCaster"}

            ColorMask 0

            ... // Code omitted
        }
    }
}
```

**2. 在着色器中设置属性**

在进一步操作之前，先在着色器文件里设置一些属性。属性不仅存储 HLSL 代码中用到的值——它们还存储关于材质的元数据。创建一个 `Float <font style="background-color:#C1E77E;">_SurfaceType</font>` 属性来记录材质是<font style="background-color:#C1E77E;">不透明还是透明</font>。添加 `<font style="background-color:#C1E77E;">HideInInspector</font>` 属性以确保它<font style="background-color:#C1E77E;">不会</font>出现在用户面前的<font style="background-color:#C1E77E;">检视器</font>中：

接下来，为源混合、目标混合和 Z 写入模式创建三个 `Float` 属性。要指示 ShaderLab 在 `Blend` 和 `ZWrite` 命令中使用属性值，用方括号包围属性名。对 ForwardLit Pass 执行此操作。ShadowCaster Pass 可以使用 `Blend One Zero` 和 `ZWrite On` 的默认值。

现在我们需要修改 `Queue` 和 `RenderType` 标签了！遗憾的是，**<font style="background-color:#C1E77E;">纯 ShaderLab 并不支持变量形式的标签</font>**（无法在材质面板中动态修改）——所以我们要在 **C# 自定义检视面板（Custom Inspector）** 中来搞定这件事！目前，先把 `<font style="background-color:#C1E77E;">RenderType</font>`<font style="background-color:#C1E77E;"> 重置为 </font>`<font style="background-color:#C1E77E;">Opaque</font>`，并<font style="background-color:#C1E77E;">移除 </font>`<font style="background-color:#C1E77E;">Queue</font>` 标签——移除后它会默认回退到 `Geometry`（几何体）队列。

```csharp
using UnityEditor;
using UnityEngine;
using UnityEngine.Rendering;

public class MyLitCustomInspector : ShaderGUI {

    public enum SurfaceType {
        Opaque, Transparent
    }

    public override void OnGUI(MaterialEditor materialEditor, MaterialProperty[] properties) {

        Material material = materialEditor.target as Material;
        // 1. 找到对应的“点餐员”
        var surfaceProp = BaseShaderGUI.FindProperty("_SurfaceType", properties, true);
        // 2. 开始监听“是否有改动”
        EditorGUI.BeginChangeCheck();
        
#if UNITY_2022_1_OR_NEWER
        // 3. （Unity 2022+专用）告诉系统：我现在要改这个属性了，请记录变体状态
        MaterialEditor.BeginProperty(surfaceProp);
#endif
        // 4. 画下拉菜单，并立马把用户选的值存回“点餐员”的 float 里
        surfaceProp.floatValue = (int)(SurfaceType)EditorGUILayout.EnumPopup("Surface type", (SurfaceType)surfaceProp.floatValue);
#if UNITY_2022_1_OR_NEWER
        // 5. 结束变体记录
        MaterialEditor.EndProperty();
#endif
// 这部分好像是作者抄过来的代码，注释掉        
// #if UNITY_2022_1_OR_NEWER
//         MaterialEditor.BeginProperty(faceProp);
// #endif
//         faceProp.floatValue = (int)(FaceRenderingMode)EditorGUILayout.EnumPopup("Face rendering mode", (FaceRenderingMode)faceProp.floatValue);
// #if UNITY_2022_1_OR_NEWER
//         MaterialEditor.EndProperty();
// #endif
        // 6. 如果刚才监听到用户确实点了下拉菜单并改了值
        if(EditorGUI.EndChangeCheck()) {
            // 这时候才真正拿着新值，去“后厨”（材质）里改渲染队列、混合模式等
            UpdateSurfaceType(material);
        }

        base.OnGUI(materialEditor, properties);
    }

    private void UpdateSurfaceType(Material material) {
        SurfaceType surface = (SurfaceType)material.GetFloat("_SurfaceType");
        switch(surface) {
        case SurfaceType.Opaque:
            material.renderQueue = (int)RenderQueue.Geometry;
            material.SetOverrideTag("RenderType", "Opaque");
            material.SetInt("_SourceBlend", (int)BlendMode.One);
            material.SetInt("_DestBlend", (int)BlendMode.Zero);
            material.SetInt("_ZWrite", 1);
            material.SetShaderPassEnabled("ShadowCaster", true);
            break;
        case SurfaceType.Transparent:
            material.renderQueue = (int)RenderQueue.Transparent;
            material.SetOverrideTag("RenderType", "Transparent");
            material.SetInt("_SourceBlend", (int)BlendMode.SrcAlpha);
            material.SetInt("_DestBlend", (int)BlendMode.OneMinusSrcAlpha);
            material.SetInt("_ZWrite", 0);
            material.SetShaderPassEnabled("ShadowCaster", false);
            break;
        }
    }
}
```

**3. 重写 OnGUI 方法**

回到自定义检视面板（Custom Inspector）。创建一个枚举（enum），包含我们想要支持的所有“表面类型（surface types）”：不透明（opaque）和透明（transparent）。

然后，为了在面板上添加一个包含该枚举所有值的下拉菜单，请在 `OnGUI` 中调用 `EditorGUILayout.EnumPopup`。它的第一个参数是 UI 标签（Label），第二个参数是当前选中的值。

Unity 会将当前选中的值存储在材质的 `_SurfaceType` 属性中。但是，**如果我们想要支持序列化（serialization）、撤销（Undo）、着色器变体（shader variants）以及其他编辑器特性，就****<font style="background-color:#C1E77E;">不能直接去读取</font>****这个值**。

首先，Unity 会将一个属性封装在 `MaterialProperty` 类中。Unity 会把一个 `MaterialProperty` 列表传给 `OnGUI`（Shader 的每个属性对应一个实例），并提供了一个 `BaseShaderGUI.FindProperty` 方法来轻松获取与 `_SurfaceType` 对应的那个实例。

`MaterialProperty` 将属性值存储为 `float` 类型，不过把它强制转换（cast）为 `SurfaceType` 很容易。把它作为第二个参数（即当前值）传给 `EnumPopup`。`EnumPopup` 会返回当前下拉菜单中显示的值——要么是传入的原值，要么就是用户新选中的值。无论哪种情况，都请将其重新强制转换回 `float`，并更新 `MaterialProperty` 中的值。<font style="color:#117CEE;">  
</font>`<font style="color:#117CEE;">MaterialProperty</font>`<font style="color:#117CEE;">和材质像“点餐”和“后厨”的关系，如果直接改材质，Unity 的 撤销（Ctrl+Z）、材质变体（Material Variant） 和 序列化 功能就会失效。</font>

<font style="color:#117CEE;">这里还有一个问题未解决（后面已解决）：渲染混合方式</font><font style="color:#117CEE;background-color:#C1E77E;">未改成方括号引用</font>

**用 **`**BeginProperty**`** 和 **`**EndProperty**`** 函数把 **`**EnumPopup**`** 的调用包裹起来**。这能启用材质变体（Material Variants）及其所有强大的特性——**但请注意，这仅限于 Unity 2022 及以上版本**。遗憾的是，之前的版本并没有这两个函数。如果你使用的是 Unity 2021 或更早版本，请务必用 `#if` 预编译指令将它们包裹起来，或者直接省略它们。

现在，为了监听用户的输入并适当地设置材质属性，请用 `EditorGUI.BeginChangeCheck` 和 `EditorGUI.EndChangeCheck` 把 `EnumPopup` 包裹起来。`EndChangeCheck` 会在用户从下拉菜单中选了一个新值时返回 `true`。

**4. 实现 UpdateSurfaceType 函数**

创建一个名为 `UpdateSurfaceType` 的函数，接收材质（material）作为参数。在 `EndChangeCheck` 返回 `true` 的代码块中调用它。`UpdateSurfaceType` 将根据 `_SurfaceType` 来刷新 ZWrite 模式、混合（Blend）模式、标签以及阴影投射器（Shadow Caster）。由于该函数在用户输入之后运行，因此可以直接从材质中安全地读取属性。

使用 `switch` 语句，根据 `SurfaceType` 枚举来刷新材质。

+ 使用 `Material.renderQueue` 来设置渲染队列（Render Queue）。 
+ 使用 `SetOverrideTag` 来覆盖 `RenderType` 标签。 
+ 使用 `SetInt` 来设置 ZWrite 和 Blend 属性。Unity 有一个用于<font style="background-color:#C1E77E;">混合模式的便捷枚举</font>——引入 `<font style="background-color:#C1E77E;">Unity.Rendering</font>` 命名空间即可使用它。至于 ZWrite，`1` 代表开启（On），`0` 代表关闭（Off）。 

最后，为了关闭阴影，我们可以禁用阴影投射 Pass（Shadow Caster Pass）。使用 `SetShaderPassEnabled` 来处理这件事。

最后，回到 `OnGUI` 中，确保在该方法的末尾调用 `base.OnGUI`。这会绘制默认的检视面板，包含你材质中所有**没有**标记 `HideInInspector` 属性的其他属性。

```csharp
Shader "NedMakesGames/MyLit" {
    Properties{
        ... // Code omitted
    }
    SubShader {
        ... // Code omitted
    }
    CustomEditor "MyLitCustomInspector"
}
```

**5. 注册检视器**

剩下的唯一工作就是将我们的检视面板类注册到着色器中。在 .shader 文件中，在 Shader 代码块内使用 `<font style="background-color:#C1E77E;">CustomEditor</font>`<font style="background-color:#C1E77E;"> 命令</font>。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787049953413-1e3e66a5-0072-404e-932d-12f71116dbf2.png)

在场景中检查一下吧！您现在可以轻松地在“不透明”和“透明”模式之间切换了。同时请确认在 Frame Debugger（帧调试器）中一切看起来也都正常。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787049986044-0e57a366-2524-42b1-af02-9856fa2c3a7e.png)

_切换到 Lit 着色器再切回 MyLit 会破坏属性与下拉菜单之间的同步！_

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787397403642-4a42748a-35fd-486d-8e42-21a1dc32c566.png)<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787398550868-aeb018d0-71ea-44ce-a7cb-5e3ae0c0a7eb.png)

<font style="color:#117CEE;">成功在透明和不透明之间切换（左），切换到其它着色器再切换回来，球体未正常初始化（右）</font>

您可能会注意到一个问题：如果在切换着色器后，在您操作表面类型下拉菜单之前，材质可能无法正确初始化。

```csharp
using UnityEditor;
using UnityEngine;
using UnityEngine.Rendering;

public class MyLitCustomInspector : ShaderGUI {

    public enum SurfaceType {
        Opaque, Transparent
    }
    
    public override void AssignNewShaderToMaterial(Material material, Shader oldShader, Shader newShader) {
        base.AssignNewShaderToMaterial(material, oldShader, newShader);

        if(newShader.name == "NedMakesGames/MyLit") {
            UpdateSurfaceType(material);
        }
    }

    public override void OnGUI(MaterialEditor materialEditor, MaterialProperty[] properties) {
        ... // Code omitted
    }

    private void UpdateSurfaceType(Material material) {
        ... // Code omitted
    }
}
```

**6. 处理着色器切换**

ShaderGUI 类在将新着色器分配给材质时会触发一个回调：`<font style="background-color:#C1E77E;">AssignNewShaderToMaterial</font>`。请重写该方法，并在方法顶部保留对基类方法的调用。使用其 `name` 字段检查新着色器是否为“MyLit”着色器。如果是，则调用 `<font style="background-color:#C1E77E;">UpdateSurfaceType</font>`<font style="background-color:#C1E77E;"></font>函数。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787049750579-3c877bad-0b8a-484d-b3cf-858d98281d36.png)

```csharp
public class MyLitCustomInspector : ShaderGUI {
    ...
    
#if UNITY_2022_1_OR_NEWER
    public override void ValidateMaterial(Material material) {
        base.ValidateMaterial(material);
        UpdateSurfaceType(material);
    }
#endif
    
    ...
}
```

此外，在 Unity 2022 中，除非我们再添加一个函数 `ValidateMaterial`，否则材质变体不会正确更新。Unity 在材质属性发生变化时（用户编辑或父变体改变）调用此方法。让它调用 `UpdateSurfaceType` 即可。

Another bug squashed!（又一只虫子被压扁了！）

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787050485636-d9579d17-9ebd-4dbc-b8bf-e89bb9ca6303.png)<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787050523315-d72b6478-deda-4cf3-9112-9bc0dbf68ff1.png)

<font style="color:#117CEE;">目前，我们将这个材质选择为不透明的情况下，会出现材质未被渲染的情况，看上去是不透明的效果没有传递过来，还记得我们前面提到过的问题么，接下来填这个坑</font>

<font style="color:#117CEE;">处理起来很简单，将混合方式、深度写入从写死替换为</font><font style="color:#117CEE;background-color:#C1E77E;">方括号引用属性值</font>

```csharp
SubShader{
        Tags{"RenderPipeline" = "UniversalPipeline" "RenderType" = "Opaque" }

        // ColorMask 0
        
        Pass{
        Name "ForwardLit" // For debugging
        Tags{"LightMode" = "UniversalForward"}

        // Blend SrcAlpha OneMinusSrcAlpha
        // ZWrite Off
        // 从写死替换为方括号引用属性值，解决材质选择为不透明的情况下，会出现材质未被渲染的情况
        Blend [_SourceBlend] [_DestBlend]
        ZWrite [_ZWrite]
        HLSLPROGRAM // Begin HLSL code
    ...
```

---

## Alpha 裁剪（Alpha Cutouts）
有没有办法将透明材质的灵活性与不透明材质的性能结合起来？算有吧！另一种常见的透明度策略叫做**Alpha 测试（alpha testing）、Alpha 裁剪（alpha clipping）或 Alpha 裁切（alpha cutouts）**。在这种模式下，我们像用饼干模具一样使用纹理，只渲染网格的某些部分。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787050627125-522b8d9d-0d25-4ee4-8a7d-93bdfb4a6e9c.png)

_这里的叶子是用alpha剪影渲染的_

这是一种**混合模式**！每个片段要么完全不透明，要么完全透明。不需要混合，因此可以安全地写入深度缓冲区并投射阴影。

<font style="color:#117CEE;">阴影也是裁剪的。Unity 内置的 Lit 着色器在投射阴影时，同样会在阴影 Pass 中读取主纹理 Alpha 并进行 clip 裁剪。因此，投射到地面上的阴影不是实心的方块，而是和灌木丛视觉形状完全一致的镂空剪影（叶片的缝隙处没有阴影）</font>

```csharp
using UnityEditor;
using UnityEngine;
using UnityEngine.Rendering;

public class MyLitCustomInspector : ShaderGUI {

    public enum SurfaceType {
        Opaque, TransparentBlend, TransparentCutout
    }

    public override void AssignNewShaderToMaterial(Material material, Shader oldShader, Shader newShader) {
        ... // Code omitted
    }

    public override void OnGUI(MaterialEditor materialEditor, MaterialProperty[] properties) {
        ... // Code omitted
    }

    private void UpdateSurfaceType(Material material) {
        SurfaceType surface = (SurfaceType)material.GetFloat("_SurfaceType");
        switch(surface) {
        case SurfaceType.Opaque:
            material.renderQueue = (int)RenderQueue.Geometry;
            material.SetOverrideTag("RenderType", "Opaque");
            break;
        case SurfaceType.TransparentCutout:
            material.renderQueue = (int)RenderQueue.AlphaTest;
            material.SetOverrideTag("RenderType", "TransparentCutout");
            break;
        case SurfaceType.TransparentBlend:
            material.renderQueue = (int)RenderQueue.Transparent;
            material.SetOverrideTag("RenderType", "Transparent");
            break;
        }

        switch(surface) {
        case SurfaceType.Opaque:
        case SurfaceType.TransparentCutout:
            material.SetInt("_SourceBlend", (int)BlendMode.One);
            material.SetInt("_DestBlend", (int)BlendMode.Zero);
            material.SetInt("_ZWrite", 1);
            break;
        case SurfaceType.TransparentBlend:
            material.SetInt("_SourceBlend", (int)BlendMode.SrcAlpha);
            material.SetInt("_DestBlend", (int)BlendMode.OneMinusSrcAlpha);
            material.SetInt("_ZWrite", 0);
            break;
        }

        material.SetShaderPassEnabled("ShadowCaster", surface != SurfaceType.TransparentBlend);
    }
}
```

### AlphaTest 队列
支持裁切需要对我们迄今为止编写的所有代码进行小幅调整。首先，在 `SurfaceType` 枚举中添加一个 `<font style="background-color:#C1E77E;">TransparentCutout</font>` 成员。同时，为了更清晰，将原来的 `Transparent` 模式重命名为 `<font style="background-color:#E8F7CF;">TransparentBlend</font>`。

在 `UpdateSurfaceType` 中，我们需要为裁切模式设置所有内容。<font style="color:rgb(15, 17, 21);">这里有个关键点要记住：裁切模式，在“颜色怎么叠加”（Blend）和“要不要写深度缓存”（ZWrite）这两项上，</font>**<font style="color:rgb(15, 17, 21);">跟不透明物体（Opaque）是完全一样的</font>**<font style="color:rgb(15, 17, 21);">，直接抄它的设置就行。</font>  
<font style="color:rgb(15, 17, 21);">但是呢，裁切模式用的“渲染队列”（排队编号）和“渲染类型标签”（归类标签）不能跟不透明物体混在一起，得用自己独有的一套。另外，裁切模式也是能投射阴影的，别把它漏掉了。搞明白上面这几条规则之后，我们就可以动手重新整理一下那个 </font>`<font style="color:rgb(15, 17, 21);background-color:rgb(235, 238, 242);">switch</font>`<font style="color:rgb(15, 17, 21);"> 判断语句了，把不透明、裁切、混合这三种情况都给它安排得明明白白。</font>

<font style="color:#117CEE;">排队序号分了3类，分别是首先渲染不透明，接着渲染透明裁切/镂空，最后渲染透明混合/半透明</font>

<font style="color:#117CEE;">归类标签的case里分了情况A：不透明和镂空，情况B：半透明混合两种来归类</font>

<font style="color:rgb(15, 17, 21);">这里要特意提一下“AlphaTest”这个队列。裁切物体得放到一个叫“AlphaTest”的新队列里去跑。</font><font style="color:#117CEE;">  
</font><font style="color:rgb(15, 17, 21);">这个队列的出场顺序很明确：排在普通不透明物体（Geometry）的</font>**<font style="color:rgb(15, 17, 21);">后面</font>**<font style="color:rgb(15, 17, 21);">，但又排在天空盒（Skybox）的</font>**<font style="color:rgb(15, 17, 21);">前面</font>**<font style="color:rgb(15, 17, 21);">。看到这儿你肯定会纳闷：“既然裁切又不需要搞颜色混合，直接把它扔到普通不透明物体（Geometry）那一堆里不就行了吗？干嘛非得单独开个小灶？”</font><font style="color:#117CEE;">  
</font><font style="color:rgb(15, 17, 21);">这个问题问到点子上了。</font>**<font style="color:rgb(15, 17, 21);">之所以要单独给它开个队列，纯粹是为了照顾显卡的性能</font>**<font style="color:rgb(15, 17, 21);">（因为裁切会打断GPU的深度测试优化，把这类“刺头”单独拎出来排队，能尽量减少对正常物体的性能拖累）。</font>

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787050690873-11abe902-4c06-41b8-905b-1e4070102269.png)

_便宜的白色球体防止了昂贵的彩虹球体渲染_

除了启用透明度之外，绘制顺序也是一个强大的优化工具！想象一下这种情况：两个对象有不透明着色器，但其中一个资源密集得多。我们希望尽量减少过度绘制，以防止在昂贵材质不可见时仍对其进行着色。Unity 尝试通过<font style="background-color:#C1E77E;">深度排序</font>来实现这一点，但并不总是可靠。

通过将昂贵的着色器放入靠后的队列，我们确保它在深度缓冲区填充更多后才被绘制。<font style="background-color:#C1E77E;">Alpha 裁切</font>比不透明着色器<font style="background-color:#C1E77E;">更昂贵</font>，所以 Unity 把它们排在后面以节省时间！

```csharp
... // Code omitted

float4 Fragment(Interpolators input) : SV_TARGET {
	float2 uv = input.uv;
	// Sample the color map
	float4 colorSample = SAMPLE_TEXTURE2D(_ColorMap, sampler_ColorMap, uv);
    // 括号内的值小于0，直接把这个像素丢弃
	clip(colorSample.a * _ColorTint.a - 0.5);

	// For lighting, create the InputData struct, which contains position and orientation data
	InputData lightingInput = (InputData)0; // Found in URP/ShaderLib/Input.hlsl
	lightingInput.positionWS = input.positionWS;
	lightingInput.normalWS = normalize(input.normalWS);
	lightingInput.viewDirectionWS = GetWorldSpaceNormalizeViewDir(input.positionWS); // In ShaderVariablesFunctions.hlsl
	lightingInput.shadowCoord = TransformWorldToShadowCoord(input.positionWS); // In Shadows.hlsl
	
	// Calculate the surface data struct, which contains data from the material textures
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

### Clip 与 Discard
回到代码。在 `MyLitForwardLitPass.hlsl` 中，利用 HLSL 的 `clip` 函数来完成工作。如果你传给它一个小于或等于零的数，它会**丢弃（discard）**当前正在运行的片段。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787050769838-c1922911-3f19-434f-a1bd-5d62dc9c0f4c.png)<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787050784838-04c80dfa-dce0-456b-aace-5dac0c7ae30c.png)<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787050790734-148a838c-b48a-4cb9-8e75-a41ceefda74e.png)

`discard` 是发给光栅化器的一条命令，导致它假装从未调用过某个片段。它会<font style="background-color:#C1E77E;">短路片段函数</font>，在 `clip` 之后立即返回，并丢弃与该片段相关的所有数据——不写入深度缓冲区或渲染目标。就好像片段函数从未被调用过一样！

我们希望在 Alpha 值低于某个阈值时裁剪片段——暂时先用 0.5。从 Alpha 分量中减去 0.5 并传给 `clip`。要应用颜色色调的 Alpha，将其与纹理采样结果相乘：

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787050828529-0cde98aa-aa92-4d81-a240-e8752559cf43.png)

试试看！找一张带 Alpha 通道的纹理，将材质切换为 `"Transparent Cutout"` 模式。很酷，但还有几个问题需要修复。

### Alpha 截断值（Alpha Cutoff）
目前，我们总是裁剪 Alpha 低于 50% 的像素，但这可能不太合适。让我们添加一个属性使其可调。

```csharp
Shader "NedMakesGames/MyLit" {
    Properties{
        [Header(Surface options)]
        [MainTexture] _ColorMap("Color", 2D) = "white" {}
        [MainColor] _ColorTint("Tint", Color) = (1, 1, 1, 1)
        _Cutoff("Alpha cutout threshold", Range(0, 1)) = 0.5
        _Smoothness("Smoothness", Float) = 0

        [HideInInspector] _SourceBlend("Source blend", Float) = 0
        [HideInInspector] _DestBlend("Destination blend", Float) = 0
        [HideInInspector] _ZWrite("ZWrite", Float) = 0

        [HideInInspector] _SurfaceType("Surface type", Float) = 0
    }
    
    ... // Code omitted
}
```

在 `.shader` 文件中定义一个 `"_Cutoff"` 属性。它应始终在 0 到 1 之间，所以使用特殊的 `Range` 属性类型来创建一个滑块：

顺便提一下，这个属性有一个“魔法”名称，这意味着 Unity 总是会在名为 `<font style="background-color:#C1E77E;">_Cutoff</font>` 的属性中寻找 Alpha 裁剪（透明度剔除）阈值。这对于某些高级功能（例如<font style="background-color:#C1E77E;">烘焙光照</font>）非常重要。目前，只需确保你的属性名称是 `_Cutoff` 即可。

```csharp

... // Code omitted

TEXTURE2D(_ColorMap); SAMPLER(sampler_ColorMap);
float4 _ColorMap_ST;
float4 _ColorTint;
float _Cutoff;
float _Smoothness;

... // Code omitted

float4 Fragment(Interpolators input) : SV_TARGET {
	float2 uv = input.uv;
	// Sample the color map
	float4 colorSample = SAMPLE_TEXTURE2D(_ColorMap, sampler_ColorMap, uv);
	clip(colorSample.a * _ColorTint.a - _Cutoff);

	... // Code omitted
}
```

然后，在 `MyLitForwardLitPass.hlsl` 中，在 `_Cutoff` 附近定义它，并从 Alpha 中减去 `_Cutoff` 而不是 0.5：

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787051115285-0dc17b2e-e79c-42ed-a05b-e333b5d10e7d.png)

_左球面的 _Cutoff = 0.001，右边球面的 _Cutoff = 1_

现在，你可以编辑材质以更好地匹配纹理中的 Alpha 值了。

下一个问题：**即使在混合材质中我们也在裁剪！** 这不仅不正确，而且仅仅在着色器中有一个 clip 函数就可能大幅降低性能。我们应该使用一个**关键字（keyword）**来在在不透明或混合模式下移除 clip 代码。

```csharp
... // Code omitted

float4 Fragment(Interpolators input) : SV_TARGET {
	float2 uv = input.uv;
	float4 colorSample = SAMPLE_TEXTURE2D(_ColorMap, sampler_ColorMap, uv);
	
#if defined(_ALPHA_CUTOUT)
	clip(colorSample.a * _ColorTint.a - _Cutoff);
#endif

	... // Code omitted
}
```

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787627095087-04a358a2-c9d0-479d-935a-df43f84f01d8.png)

<font style="color:#117CEE;">这里的问题就是在混合模式下，继续调低透明度，这个半透明物体会被裁剪掉</font>

### 着色器特性（Shader Features）
这将是我们第一次真正使用关键字来更改自己的代码。这些关键字没有值，甚至没有 true 或 false，所以 `#if` 块无法解析它们。相反，使用 `defined` 函数来测试关键字是否已定义。关键字在启用时被定义，禁用时则未定义。

```csharp
... // Code omitted

float4 Fragment(Interpolators input) : SV_TARGET {
	float2 uv = input.uv;
	float4 colorSample = SAMPLE_TEXTURE2D(_ColorMap, sampler_ColorMap, uv);
	
#ifdef _ALPHA_CUTOUT
	clip(colorSample.a * _ColorTint.a - _Cutoff);
#endif

	... // Code omitted
}
```

有一个快捷方式：`#ifdef`。请记住，出于某种原因没有 `#elifdef`，所以我有时为了清晰起见使用完整的 `defined` 语法。总之，使用 `_ALPHA_CUTOUT` 关键字来包含或省略 clip 函数：

```plain
using UnityEditor;
using UnityEngine;
using UnityEngine.Rendering;

public class MyLitCustomInspector : ShaderGUI {

    ... // Code omitted

    private void UpdateSurfaceType(Material material) {
        SurfaceType surface = (SurfaceType)material.GetFloat("_SurfaceType");
        
        ... // Code omitted

        if(surface == SurfaceType.TransparentCutout) {
            material.EnableKeyword("_ALPHA_CUTOUT");
        } else {
            material.DisableKeyword("_ALPHA_CUTOUT");
        }
    }
}
```

可以从 C# 中启用和禁用关键字，所以在自定义检视器中处理这个。在 `UpdateSurfaceType` 中，根据表面类型启用或禁用 `_ALPHA_CUTOUT`：

```csharp
Shader "NedMakesGames/MyLit" {
    ... // Code omitted
    SubShader {
        Tags {"RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline"}

        Pass {
            Name "ForwardLit"
            ... // Code omitted

            HLSLPROGRAM

            #define _SPECULAR_COLOR

            #pragma shader_feature_local _ALPHA_CUTOUT

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

        ... // Code omitted
    }

    // Code omitted
}
```

现在，我们需要基于 `<font style="background-color:#C1E77E;">_ALPHA_CUTOUT</font>`<font style="background-color:#C1E77E;"> 的着色器变体</font>。转到 `.shader` 文件，添加一个 `#pragma` 来生成它们。使用 `<font style="background-color:#C1E77E;">shader_feature_local</font>` 命令而不是 `multi_compile`。着色器特性（Shader features）与多重编译（multi compiles）非常相似，因为它们都是基于一系列关键字（keywords）来生成着色器变体的。区别在于**游戏构建（game builds）**时的行为。

<font style="color:#117CEE;">进度推进到这里，之前已经拥有在Cutout模式下才会出现拉条的特性，这个在之前的探索中通过指导做完了</font>

<font style="color:#117CEE;">当前新解决了两个问题：</font>

1. <font style="color:#117CEE;">_Cutoff放在glsl中更合适，放到pass中就作为全局变量了，glsl中只作用与该glsl，另外用CBUFFER包裹</font>
2. <font style="color:#117CEE;">透明混合模式下也能被裁切，这不合理，已经通过宏修复，只在Cutoff模式下开启</font>
3. <font style="color:#117CEE;">使用关键字标记Properties内的变量时，属性值优先显示C#中的（例如会优先显示cs中写的"透明度裁切的阈值"</font>

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787051397909-b82a0b86-ab60-49c2-b911-e71fec4dc42b.png)

> `shader_feature`** 与 **`multi_compile`** 的区别：**
>
> + `multi_compile` 生成的所有变体都会被包含在游戏构建中。
> + `shader_feature` 变体在包含之前，Unity 会检查是否有材质启用了所需的关键字。
> + 例如，只有当材质使用裁切表面类型（从而启用 `_ALPHA_CUTOUT` 关键字）时，Unity 才会包含带 `_ALPHA_CUTOUT` 的 MyLit 变体。
>
> 由于此检查发生在构建时，**<font style="background-color:#C1E77E;">运行时动态更改的关键字</font>**（如 URP 光照关键字）应使<font style="background-color:#C1E77E;">用 </font>`<font style="background-color:#C1E77E;">multi_compile</font>`。否则使用 `shader_feature`。
>

在构建游戏或创建可分发包时，Unity 必须确定要将哪些已编译的着色器变体包含进构建中。它会收集游戏中使用的所有着色器，然后开始对着色器变体进行筛选。

Unity 会包含由 `multi_compile` 指令生成的所有变体，但在包含 `shader_feature` 变体之前，它会先<font style="background-color:#C1E77E;">检查</font>以确保确实有某个材质启用了所需的<font style="background-color:#C1E77E;">关键字</font>。例如，只有当某个材质使用了裁剪（cutout）表面类型（从而启用了 `_ALPHA_CUTOUT` 关键字）时，Unity 才会将启用了 `_ALPHA_CUTOUT` 的 MyLit 变体包含在内。

由于这个检查发生在**构建时（build-time）**，因此那些在**运行时（runtime）**动态更改的关键字（比如 URP 光照关键字）应该使用 `multi_compile`。否则，请使用 `shader_feature`。

为什么要费心做这个？因为**着色器变体的编译成本不低**！着色器特性有助于优化构建时间。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787051502171-03e5eb4f-abe5-4adc-a1d6-7a61d30fa014.png)

`shader_feature` 总是在关键字列表中<font style="background-color:#C1E77E;">隐含一个 </font>`<font style="background-color:#C1E77E;">"_"</font>`；换句话说，它们总是会触发一个没有任何列出关键字被启用的变体。当然，你的游戏可能用也可能不用那个变体，但 Unity 为这种可能性做好了准备！

最后，`<font style="background-color:#C1E77E;">local</font>`<font style="background-color:#C1E77E;"> 后缀</font>表示关键字对该着色器是唯一的，不会全局设置。我们按材质设置 `_ALPHA_CUTOUT`，所以它可以使本地变体。URP 全局设置的关键字（如 `_MAIN_LIGHT_SHADOWS`）不能是本地的。Unity 对可支持的<font style="background-color:#C1E77E;">全局关键字数量有硬性限制</font>，所以尽可能使用<font style="background-color:#C1E77E;">本地变体</font>是好习惯。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787051584964-9db4bc22-b18a-4d28-97b0-296de0c5f2e3.png)

你的着色器看起来应该和以前一样，但你的 FPS 会感谢你这次优化！

---

## 通用 HLSL 文件（Common HLSL Files）
下一个要解决的 bug 是**阴影**：对象投射的阴影不再匹配它们的裁切形状！要解决这个问题，需要在阴影投射通道中也裁剪片段。

```csharp
void TestAlphaClip(float4 colorSample) {
#ifdef _ALPHA_CUTOUT
	clip(colorSample.a * _ColorTint.a - _Cutoff);
#endif
}

float4 Fragment(Interpolators input) : SV_TARGET {
	float2 uv = input.uv;
	float4 colorSample = SAMPLE_TEXTURE2D(_ColorMap, sampler_ColorMap, uv);
	TestAlphaClip(colorSample);

	InputData lightingInput = (InputData)0;
	... // Code omitted
}
```

首先，把 `MyLitForwardLitPass.hlsl` 中的 Alpha 裁剪逻辑移到一个名为 `TestAlphaClip` 的函数中。将颜色纹理采样作为参数传递。为了让 `MyLitShadowCasterPass.hlsl` 也能使用它，我们应该把它添加到一个单独的文件中，然后在两个文件中都 `#include` 它。

```csharp

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

TEXTURE2D(_ColorMap); SAMPLER(sampler_ColorMap);

float4 _ColorMap_ST;
float4 _ColorTint;
float _Cutoff;
float _Smoothness;

void TestAlphaClip(float4 colorSample) {
#ifdef _ALPHA_CUTOUT
	clip(colorSample.a * _ColorTint.a - _Cutoff);
#endif
}
```

```csharp
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
#include "MyLitCommon.hlsl"

struct Attributes {
	... // Code omitted
};


struct Interpolators {
	... // Code omitted
};

Interpolators Vertex(Attributes input) {
	... // Code omitted
}

float4 Fragment(Interpolators input) : SV_TARGET {
	... // Code omitted
}
```

创建一个新文件 `"MyLitCommon.hlsl"`。从 `MyLitForwardLitPass.hlsl` 中移除 `TestAlphaClip` 并粘贴到这里。`TestAlphaClip` 需要几个属性：`_Tint` 和 `_Cutoff`。属性是着色器范围内定义的，所以把属性定义也移到通用文件中是有意义的。引入 URP 库以使用 `TEXTURE2D` 宏：

在 `MyLitForwardPass.hlsl` 中，删除重复代码并 `#include` 新的通用代码文件。

### 守卫关键字（Guard Keywords）
让我们花点时间想想。HLSL 非常像 C++，`#include` 会导致编译器将通用文件的内容**逐字复制粘贴**到 `#include` 行上。如果我意外地 `#include` 了同一个文件两次会怎样？Unity 会抛出错误，说某个变量已经被声明了。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787051686444-9469af76-cd23-4017-a40d-3d6d5895b741.png)

好的，但重复 `#include` 同一行并不常见。那么，如果 `MyLitCommon` 和 `MyLitForwardPass` 都 `#include` 了一个名为 `MyMath.hlsl` 的文件呢？那 `MyMath` 就会被重复！

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787051699174-a8385d4e-eb39-4e77-98f7-8e507cc2bec4.png)

为了简化并防止错误，习惯上用**守卫关键字块**包裹 HLSL 文件中的所有代码。首先，检查某个关键字是否**未**被定义（这就是 `#ifndef` 的作用，它是 `#if !defined()` 的简写）。在紧接着的下一行，`#define` 这个守卫关键字。别忘了文件末尾的 `#endif`！

```glsl
#ifndef MY_LIT_COMMON_INCLUDED
// "#ifndef MY_LIT_COMMON_INCLUDED" is equivalent to "#if !defined(MY_LIT_COMMON_INCLUDED)"
#define MY_LIT_COMMON_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

TEXTURE2D(_ColorMap); SAMPLER(sampler_ColorMap);

float4 _ColorMap_ST;
float4 _ColorTint;
float _Cutoff;
float _Smoothness;

void TestAlphaClip(float4 colorSample) {
  #ifdef _ALPHA_CUTOUT
  clip(colorSample.a * _ColorTint.a - _Cutoff);
  #endif
}

#endif
```

现在，第一次包含 `MyMath` 时，编译器定义守卫关键字。第二次时，守卫关键字已启用，它会跳过其中的代码。很聪明！继续给 `MyLitCommon` 加上守卫关键字吧。为了安全起见，我也给所有 HLSL 文件都加上了。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787051730865-66b77f3d-bedd-4bee-ab92-c6d17b31c0cf.png)

<font style="color:#117CEE;">在MyLitForwardLitPass.hlsl里面这样写</font>

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787664088416-4d177021-1714-4fea-a271-20e367fc0e4a.png)

<font style="color:#117CEE;">两个问题：</font>

1. <font style="color:#117CEE;">能在原来的hlsl文件里面加守卫关键字将变量包裹吗？</font>
2. <font style="color:#117CEE;">包裹后的关键字在里面新增变量会被跳过吗？</font>

<font style="color:#117CEE;">问题1：不建议这么做。URP 的 SRP Batcher 要求 UnityPerMaterial 的变量布局在所有 Pass 中必须完全一致。如果你把变量分散在不同的文件里，很容易导致内存布局错乱，引发渲染错误或合批失败。</font>

<font style="color:#117CEE;">问题2：是的，检测到宏被定义过，直接跳过了你写的这一段大括号代码，如果后续引用变量，会出现未定义的标识符</font>

### 在阴影投射通道中裁剪（Clip in the Shadow Caster）
经过这番清理，你的着色器应该仍然能正常工作。现在让我们终于给阴影投射器加上裁剪。

```glsl

Shader "NedMakesGames/MyLit" {
  ... // Code omitted
    SubShader {
    Tags {"RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline"}

    Pass {
      Name "ForwardLit" // For debugging
        ... // Code omitted
      }

    Pass {
      Name "ShadowCaster"
        Tags{"LightMode" = "ShadowCaster"}

      ColorMask 0

        HLSLPROGRAM

        #pragma shader_feature_local _ALPHA_CUTOUT

        #pragma vertex Vertex
        #pragma fragment Fragment

        #include "MyLitShadowCasterPass.hlsl"
        ENDHLSL
      }
  }
  ... // Code omitted
  }
```

首先，在 `.shader` 文件中，给 ShadowCaster Pass 也加上 `_ALPHA_CUTOUT` 着色器特性：

```glsl
#ifndef MY_LIT_SHADOW_CASTER_PASS_INCLUDED
#define MY_LIT_SHADOW_CASTER_PASS_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
#include "MyLitCommon.hlsl"

struct Attributes {
  float3 positionOS : POSITION;
  float3 normalOS : NORMAL;
  #ifdef _ALPHA_CUTOUT
  float2 uv : TEXCOORD0;
  #endif
};

struct Interpolators {
  float4 positionCS : SV_POSITION;
  #ifdef _ALPHA_CUTOUT
  float2 uv : TEXCOORD0;
  #endif
};

float3 _LightDirection;

float4 GetShadowCasterPositionCS(float3 positionWS, float3 normalWS) {
  ... // Code omitted
  }

Interpolators Vertex(Attributes input) {
  Interpolators output;

  VertexPositionInputs posnInputs = GetVertexPositionInputs(input.positionOS);
  VertexNormalInputs normInputs = GetVertexNormalInputs(input.normalOS);

  output.positionCS = GetShadowCasterPositionCS(posnInputs.positionWS, normInputs.normalWS);
  #ifdef _ALPHA_CUTOUT
  output.uv = TRANSFORM_TEX(input.uv, _ColorMap);
  #endif
  return output;
}

float4 Fragment(Interpolators input) : SV_TARGET {
  #ifdef _ALPHA_CUTOUT
  float2 uv = input.uv;
  float4 colorSample = SAMPLE_TEXTURE2D(_ColorMap, sampler_ColorMap, uv);
  TestAlphaClip(colorSample);
  #endif
  return 0;
}

#endif
```

在 `MyLitShadowCasterPass.hlsl` 中，添加 `#include "MyLitCommon.hlsl"`。目前，阴影投射器没有 UV 来采样主纹理。我们需要一路把它们传递到片段阶段。

为此，在 `Interpolators` 中<font style="background-color:#E8F7CF;">添加</font>一个 `<font style="background-color:#E8F7CF;">uv</font>`<font style="background-color:#E8F7CF;"> 字段</font>。这里的每个字段都是光栅化器需要插值的另一个数据，最好让这个结构体尽可能小。用 `#if` 块包裹 `uv` 字段，确保只在<font style="background-color:#CEF5F7;">需要时才插值</font>。在 `Attributes` 结构体中也做类似处理。

在<font style="background-color:#C1E77E;">顶点函数</font>中，<font style="background-color:#C1E77E;">将 UV 传递到输出结构体</font>——同样，仅在 `_ALPHA_CUTOUT` 已定义时。

然后，在<font style="background-color:#C1E77E;">片段函数</font>中，<font style="background-color:#C1E77E;">采样颜色纹理并调用 </font>`<font style="background-color:#C1E77E;">TestAlphaClip</font>`。同样用 `#if` 块包裹。记住，`clip` 在传入值低于零时会丢弃片段，导致光栅化器扔掉它们，<font style="background-color:#C1E77E;">不写入深度缓冲区</font>。由于深度缓冲区就是阴影贴图，被裁剪的片段也不会出现在那里。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787051888746-bb7f44ea-cd46-4216-aeca-41e060de4618.png)

至此，你的阴影就能正确匹配裁切形状了。务必在材质上测试所有模式，确保所有 `#if` 块都设置正确。

还有一个问题我想修复，但这需要多一点解释……

<font style="color:#117CEE;">推进到这里</font>

<font style="color:#117CEE;">解决了哪些问题：</font>

1. <font style="color:#117CEE;">程序化纹理生成，解决没有镂空的贴图问题</font>
2. <font style="color:#117CEE;">重载生成函数，支持uv和调整纹理放缩</font>
3. <font style="color:#117CEE;">在cutoff下支持阴影裁切，阴影也能镂空</font>

---

## 双面渲染（Double Sided Rendering）
<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787051913310-c15b2891-05de-4929-859c-c82ae5d01690.png)

通常，游戏在扁平平面上使用 Alpha 裁剪，这种情况下一切看起来都很好。但如果你在球体上开启 Alpha 裁剪，可能会注意到**内部变得不可见**了！

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787051949865-53a37362-cb93-44aa-b613-3bb49049c9cd.png)<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787051961415-5b5a1dc8-f3e1-48cb-931b-eb77edda56de.png)

_一个半球体，开启和禁用剔除_

### 面剔除（Face Culling）
这是另一种优化技术，叫做**面剔除（face culling）**、**缠绕剔除（winding culling）**或简称"剔除（culling）"。具体细节不重要，但基本上，光栅化器会判断它是在渲染网格三角形的正面还是背面。背面通常在模型的内部，所以光栅化器会"剔除"它，即决定不渲染它。如果你曾遇到从 Blender 导入的奇怪问题，不得不翻转面，罪魁祸首就是剔除。

在我们的例子中，我们想渲染球体的内部。幸运的是，关闭剔除很容易。

```glsl
Shader "NedMakesGames/MyLit" {
    Properties{
        ... // Code omitted

        [Enum(UnityEngine.Rendering.CullMode)] _Cull("Cull mode", Float) = 2
    }
    SubShader {
        Tags {"RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline"}

        Pass {
            Name "ForwardLit"
            Tags{"LightMode" = "UniversalForward"}

            Blend[_SourceBlend][_DestBlend]
            ZWrite[_ZWrite]
            Cull[_Cull]

            ... // Code omitted
        }

        Pass {
            Name "ShadowCaster"
            Tags{"LightMode" = "ShadowCaster"}

            ColorMask 0
            Cull[_Cull]

            ... // Code omitted
        }
    }

    ... // Code omitted
}
```

在 `MyLit.shader` 中，添加一个名为`<font style="background-color:#C1E77E;">_Cull</font>`的新 float 属性。我们将用它来设置另一个 ShaderLab 命令：`Cull`。`Cull` 可以取三个不同的值：`Off`、`Front` 和 `Back`。`Off` 完全关闭剔除，而另外两个各剔除三角形的一侧。

Unity 有一个对应的 C# 枚举 `<font style="background-color:#E8F7CF;">CullMode</font>`，我们可以指示默认材质检视器用它来创建下拉菜单。在枚举中，`Back` 的 int 值为 2，所以让我们将其设为默认值：

然后，在你的 ForwardLit 和 ShadowCaster Pass 中添加一个 `Cull` 命令，方括号中放 `_Cull` 属性：

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787052121620-d05f29a9-4e63-4a0c-88ab-420c07039e7e.png)

回到场景试试。关闭剔除会显示球体的两面！

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787707850644-21d789c6-b650-4c26-8c01-59370eafa87a.png)<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787707814549-4820bbea-67fa-41b7-afd0-dda4a3409061.png)

<font style="color:#117CEE;">关闭剔除显示球体的两面（右）</font>

<font style="color:#117CEE;"></font>

### 双面法线（Double Sided Normals）
但是，一个新的 bug！**光照不正确**。注意三角形的两面接收到相同数量的光，就好像球体是用纸做的一样。这是因为两面的法线向量相同——它不会为背面自动翻转。我们需要自己来做。

```glsl
... // Code omitted

float4 Fragment(Interpolators input, FRONT_FACE_TYPE frontFace : FRONT_FACE_SEMANTIC) : SV_TARGET {
	... // Code omitted

	InputData lightingInput = (InputData)0;
	lightingInput.positionWS = input.positionWS;
	lightingInput.normalWS = normalize(input.normalWS) * IS_FRONT_VFACE(frontFace, 1, -1);
	lightingInput.viewDirectionWS = GetWorldSpaceNormalizeViewDir(input.positionWS);
	lightingInput.shadowCoord = TransformWorldToShadowCoord(input.positionWS);
	
	... // Code omitted
}

... // Code omitted
```

在 `MyLitForwardLitPass.hlsl` 中，如果渲染的是三角形的背面，就翻转传给 `InputData` 的法线向量。要翻转一个向量，只需将它乘以 -1。但怎么知道正在渲染三角形的哪一面呢？光栅化器有这个信息，并通过一个特殊的、**<font style="background-color:#C1E77E;">仅片段阶段</font>**的语义来提供它。

要获取它，只需给片段函数添加另一个参数。确切的语义和参数类型取决于当前平台。幸运的是，Unity 提供了宏来规避这个问题。无论哪种方式，`frontFace`的类型本质上是一个布尔值，如果三角形正面可见则为 true。

<font style="color:rgb(15, 17, 21);">在给 </font>`<font style="color:rgb(15, 17, 21);background-color:rgb(235, 238, 242);">lightingInput.normalWS</font>`<font style="color:rgb(15, 17, 21);"> 赋值法线之前，我们需要先把法线向量乘以 </font>`<font style="color:rgb(15, 17, 21);background-color:rgb(235, 238, 242);">1</font>`<font style="color:rgb(15, 17, 21);">（正面）或 </font>`<font style="color:rgb(15, 17, 21);background-color:rgb(235, 238, 242);">-1</font>`<font style="color:rgb(15, 17, 21);">（背面）。要实现这个“根据正反面选值”的操作，Unity 提供了一个专门的宏，它类似于 C# 的三元运算符（</font>`<font style="color:rgb(15, 17, 21);background-color:rgb(235, 238, 242);">条件 ? 真 : 假</font>`<font style="color:rgb(15, 17, 21);">），可以直接根据 </font>`<font style="color:rgb(15, 17, 21);background-color:rgb(235, 238, 242);">frontFace</font>`<font style="color:rgb(15, 17, 21);"> 参数返回对应的系数。直接用这个宏去乘法线就行了</font>

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787052181182-c631b197-20a0-4b06-b107-73e91b00aee3.png)

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787709667051-dc4e1913-7d29-4ec6-81bb-bc84874a4083.png)<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787709597532-a58bfd9f-cdf1-4f5e-a9ae-36f3de5ad370.png)

<font style="color:#117CEE;">未翻转对背面翻转法线前（左）正确的渲染（右）</font>

<font style="color:#117CEE;">看出问题在哪了吗，</font><font style="color:#117CEE;background-color:#C1E77E;">左图右上面的内侧不应该亮</font>

<font style="color:#117CEE;">球体正面外表面右侧：法线朝右 → 正对光线 → 亮。</font>

<font style="color:#117CEE;">球体背面内表面右侧：注意！ 内表面的几何位置虽然在球体右侧，但它的法线数据和外表面一样，依然朝右。</font>

看起来修复了光照，但三角形背面现在有**阴影粉刺（shadow acne）**了。由于阴影偏移也依赖于法线，我们也需要翻转它们。不幸的是，光栅化器的正面数据在顶点阶段不可用——它在光栅化器之前运行！

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787052202961-80073c64-22d5-41c3-800c-bd5849cd6479.png)<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787052221663-ace8e2d6-c828-4606-ab7b-12d24cbc81b9.png)<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787052231232-353203fd-1f9e-40cb-b014-daee95543312.png)

_在第一张图像中，红色法向量距离蓝色视野方向不到90度。第二张图中，它在射程外——翻过来！_

幸运的是还有另一种方法。如果我们假设法线向量应该总是大致朝向相机，那么当它不是时就翻转它。让我们尽量让法线向量和视线方向之间的角度小于 90 度。如果角度更大，就翻转法线。这会让它回到可接受的范围内！

有一个非常简单的函数来查找两个向量之间的角度：**点积（dot product）**。它返回该角度的余弦值。90 度的余弦是 0，如果点积小于 0，向量之间的角度就大于 90 度。

```glsl
... // Code omitted

float3 FlipNormalBasedOnViewDir(float3 normalWS, float3 positionWS) {
	float3 viewDirWS = GetWorldSpaceNormalizeViewDir(positionWS);
	return normalWS * (dot(normalWS, viewDirWS) < 0 ? -1 : 1);
}

float3 _LightDirection;

float4 GetShadowCasterPositionCS(float3 positionWS, float3 normalWS) {
	float3 lightDirectionWS = _LightDirection;
	normalWS = FlipNormalBasedOnViewDir(normalWS, positionWS);

	float4 positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, lightDirectionWS));

#if UNITY_REVERSED_Z
	positionCS.z = min(positionCS.z, UNITY_NEAR_CLIP_VALUE);
#else
	positionCS.z = max(positionCS.z, UNITY_NEAR_CLIP_VALUE);
#endif
	return positionCS;
}

... // Code omitted
```

让我们在 `MyLitShadowCasterPass.hlsl` 中用一个新的 `<font style="background-color:#E8F7CF;">FlipNormalBasedOnViewDir</font>`<font style="background-color:#E8F7CF;"></font>函数来实现这个逻辑。传入位置和法线。用 URP 内置函数计算视线方向。然后，仅当法线和视线方向的点积小于零时，将法线乘以 -1。返回法线。

修改裁剪空间计算以调用 `FlipNormalBasedOnViewDir`。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787052323870-47527fef-6595-4fae-9a0a-ba07222026b0.png)

回到场景编辑器，看起来不再有阴影粉刺了！任务完成！

这种技术并不完美——有时当你围绕对象旋转时，它会产生有点闪烁的阴影。但这可能比阴影粉刺更可取。

<font style="color:#117CEE;">这里一大段说的是啥呢，现在出现了阴影痤疮，解决阴影痤疮需要移动顶点，之前处理法线翻转那样优雅的方法需要基于</font>`<font style="color:#117CEE;">frontFace</font>`<font style="color:#117CEE;">【光栅化器负责把三角形的三个顶点拆成一个个像素，只有在这个拆分的瞬间，它才能计算出当前这个像素是属于三角形的“正面”还是“背面”（即 frontFace 信息）。】，但是这个需要在光栅化后才能出现，所以得另谋他法。</font>

<font style="color:#117CEE;">采用视线与法线点积法，正面与视线的夹角小于90°，反面大于90°，如果点积的值小于0说明在背面，直接翻转法线方向。  
</font><font style="color:#117CEE;">依赖于一个隐藏前提：默认物体的法线（Normal）是指</font><font style="color:#117CEE;background-color:#FFFFFF;">向外部的，</font><font style="color:#117CEE;">且摄像机在物体外部。如果</font><font style="color:#117CEE;background-color:#C1E77E;">模型本身法线是乱的</font><font style="color:#117CEE;">，或者</font><font style="color:#117CEE;background-color:#C1E77E;">摄像机穿模进入了物体内部</font><font style="color:#117CEE;">，这个几何假设就失效了，这就是教程最后提到“</font><font style="color:#117CEE;background-color:#C1E77E;">旋转时会有闪烁</font><font style="color:#117CEE;">”的根本原因。</font>

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787715613907-f281b481-fb25-427f-9840-2e5677c2b0ef.png)<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787716394663-ae28514e-3832-4f07-9d02-efee371c0aa2.png)

<font style="color:#117CEE;background-color:#C1E77E;">选中主光源组件</font><font style="color:#117CEE;">-Shadow-Bias调整为Custom，调整depth和normal暴露阴影痤疮，应用这个点积函数来修复痤疮，同样的参数下你可以看到  
</font><!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787715702859-5035e0e2-e34d-4053-8304-77e83f4e5b3d.png)<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787716452445-fa53b649-70a4-4d87-a2b5-747a2948dd14.png)

### 面渲染模式（Face Rendering Mode）
双面法线不是免费的——翻转操作和正面语义都有一些开销。使用关键字来开启和关闭此功能是个好主意。仔细想想，如果剔除以开启状态运行，也完全没有理由翻转法线。这只剩下三种有用的配置：**背面剔除、不剔除、不剔除并翻转法线**。

<font style="color:#117CEE;">就比如说背面剔除了，再翻转法线还需要多余开销</font>

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

    public override void AssignNewShaderToMaterial(Material material, Shader oldShader, Shader newShader) {
        ... // Code omitted
        }

    public override void ValidateMaterial(Material material) {
        ... // Code omitted
        }

    public override void OnGUI(MaterialEditor materialEditor, MaterialProperty[] properties) {
        Material material = materialEditor.target as Material;
        var surfaceProp = BaseShaderGUI.FindProperty("_SurfaceType", properties, true);
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
        ... // Code omitted

            FaceRenderingMode faceRenderingMode = (FaceRenderingMode)material.GetFloat("_FaceRenderingMode");
        if(faceRenderingMode == FaceRenderingMode.FrontOnly) {
            material.SetInt("_Cull", (int)UnityEngine.Rendering.CullMode.Back);
        } else {
            material.SetInt("_Cull", (int)UnityEngine.Rendering.CullMode.Off);
        }

        if(faceRenderingMode == FaceRenderingMode.DoubleSided) {
            material.EnableKeyword("_DOUBLE_SIDED_NORMALS");
        } else {
            material.DisableKeyword("_DOUBLE_SIDED_NORMALS");
        }
    }
}
```

让我们通过更新自定义检视器来解决这些问题。创建一个新的枚举 `<font style="background-color:#C1E77E;">FaceRenderingMode</font>`来封装上述模式。与表面模式类似，使用另一个隐藏属性来跟踪此设置。在 `OnGUI` 中，添加另一个控制此新属性 `<font style="background-color:#E8F7CF;">_FaceRenderingMode</font>`的枚举下拉菜单（以及 Unity 2022 所需的适当包围函数）。

在 `UpdateSurfaceType` 中，更新 `_Cull` 属性并启用或禁用关键字 `<font style="background-color:#C1E77E;">_DOUBLE_SIDED_NORMALS</font>`。如果面渲染模式是 `<font style="background-color:#CEF5F7;">FrontOnly</font>`，使用 Unity 的 `CullMode` 枚举将 `_Cull` 设为 `Back`。否则，关闭剔除。然后适当地启用或禁用我们的关键字。

```glsl
Shader "NedMakesGames/MyLit" {
    Properties{
        [Header(Surface options)]
        [MainTexture] _ColorMap("Color", 2D) = "white" {}
        [MainColor] _ColorTint("Tint", Color) = (1, 1, 1, 1)
        _Cutoff("Alpha cutout threshold", Range(0, 1)) = 0.5
        _Smoothness("Smoothness", Float) = 0
        
        [HideInInspector] _Cull("Cull mode", Float) = 2 // 2 is "Back"
        [HideInInspector] _SourceBlend("Source blend", Float) = 0
        [HideInInspector] _DestBlend("Destination blend", Float) = 0
        [HideInInspector] _ZWrite("ZWrite", Float) = 0

        [HideInInspector] _SurfaceType("Surface type", Float) = 0
        [HideInInspector] _FaceRenderingMode("Face rendering type", Float) = 0
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

            #define _SPECULAR_COLOR
            #pragma shader_feature_local _ALPHA_CUTOUT
            #pragma shader_feature_local _DOUBLE_SIDED_NORMALS
            ... // Code omitted
            ENDHLSL
        }

        Pass {
            Name "ShadowCaster"
            Tags{"LightMode" = "ShadowCaster"}

            ColorMask 0
            Cull[_Cull]

            HLSLPROGRAM

            #pragma shader_feature_local _ALPHA_CUTOUT
            #pragma shader_feature_local _DOUBLE_SIDED_NORMALS
            ... // Code omitted
            ENDHLSL
        }
    }

    ... // Code omitted
}
```

转到 `MyLit.shader`，首先隐藏检视器中的 `_Cull` 属性并移除 `Enum` 属性（现在由代码处理）。其次，为 `_FaceRenderingMode` 添加另一个隐藏属性。第三，给<font style="background-color:#C1E77E;">两个 Pass 都加上</font> `_DOUBLE_SIDED_NORMALS` 的着色器特性。

```glsl
float4 Fragment(Interpolators input
#ifdef _DOUBLE_SIDED_NORMALS
	, FRONT_FACE_TYPE frontFace : FRONT_FACE_SEMANTIC
#endif
) : SV_TARGET {
	float2 uv = input.uv;
	float4 colorSample = SAMPLE_TEXTURE2D(_ColorMap, sampler_ColorMap, uv);
	TestAlphaClip(colorSample);

	float3 normalWS = normalize(input.normalWS);
#ifdef _DOUBLE_SIDED_NORMALS
	normalWS *= IS_FRONT_VFACE(frontFace, 1, -1);
#endif
	
	InputData lightingInput = (InputData)0;
	lightingInput.positionWS = input.positionWS;
  // 前面守卫关键字会处理好法线翻转，这里只需传值
	lightingInput.normalWS = normalWS;
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

在 `MyLitForwardLitPass` 中，用 `#if` 块<font style="background-color:#E8F7CF;">包裹</font>所有<font style="background-color:#E8F7CF;">法线翻转代码</font>。这里有一些技巧来在不需要时隐藏正面语义。虽然有点丑，但能用！

```glsl
float4 GetShadowCasterPositionCS(float3 positionWS, float3 normalWS) {
	float3 lightDirectionWS = _LightDirection;
#ifdef _DOUBLE_SIDED_NORMALS
	normalWS = FlipNormalBasedOnViewDir(normalWS, positionWS);
#endif
	float4 positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, lightDirectionWS));

#if UNITY_REVERSED_Z
	positionCS.z = min(positionCS.z, UNITY_NEAR_CLIP_VALUE);
#else
	positionCS.z = max(positionCS.z, UNITY_NEAR_CLIP_VALUE);
#endif
	return positionCS;
}
```

在 `MyLitShadowCasterPass` 中，类似地用 `#if` 块<font style="background-color:#C1E77E;">包裹</font>对 `FlipNormalBasedOnViewDir` 的调用。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787052449851-11a3981d-c92a-4199-a237-c11f3d1c8437.png)

_每个球体都有不同的面部渲染模式设置_

在场景编辑器中，尝试不同的面渲染模式，确保一切按预期工作！

以后，请仔细考虑一个对象是否真的需要这些选项。关闭剔除会显著增加性能成本，双面法线也并非廉价。这些选项对于树叶等东西非常有用——只是不要盲目地为所有材质启用它们！

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787052540202-dbc0bd34-38b4-46fe-81a5-b13186af5d41.png)

至此，我认为这已经是一个**功能完备的着色器**了！它支持所有基本需求：纹理、光照、阴影、透明度，甚至在双面法线方面超越了 Lit 着色器！但当然，我们远未结束。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1787052574712-82a0f864-20d4-47c0-a2d8-b65bb9972b04.png)

在下一个教程中，我将专注于**更多表面选项**！我们将实现一种名为 **PBR（基于物理的渲染）** 的新光照模型，它提供更多的自定义选项，使光照更加逼真。粗糙、金属、玻璃、光滑、闪亮和发光材质都在我们的未来！

---

## 总结
### 关键知识点速查表
| 概念 | 核心要点 |
| --- | --- |
| **Blend 命令** | `Blend SrcAlpha OneMinusSrcAlpha` 实现标准透明度混合 |
| **ZWrite Off** | 透明材质必须关闭深度写入，否则后面的物体无法透过它看到 |
| **渲染队列** | Geometry → AlphaTest → Skybox → Transparent，由远及近排序 |
| **自定义检视器** | 继承 `ShaderGUI`，用 `EnumPopup` 做下拉菜单，统一管理材质状态 |
| **Alpha 裁剪** | 用 `clip()` 丢弃低于阈值的片段，深度缓冲和阴影正常工作 |
| **Shader Features** | `shader_feature_local` 按需编译变体，优化构建时间 |
| **守卫关键字** | `#ifndef` + `#define` + `#endif` 防止头文件重复包含 |
| **面剔除** | `Cull Back/Front/Off`，关闭后可渲染双面 |
| **双面法线** | 用 `FRONT_FACE_SEMANTIC` 判断正反面，翻转背面法线 |
| **阴影法线修复** | 用点积判断法线是否背向相机，若是则翻转 |


### 渲染队列顺序表
| 队列名 | 值 | 用途 |
| --- | --- | --- |
| Geometry | 2000 | 不透明物体 |
| AlphaTest | 2450 | Alpha 裁剪物体 |
| Skybox | 2900 | 天空盒 |
| Transparent | 3000 | 透明混合物体 |


---

## 致谢
我想感谢 **Crubidoobidoo** 的所有支持，以及在本教程开发期间的所有赞助人：

> Adam R. Vierra, Amin, autumnboy, Ben Luker, Ben Wander, bgbg, Bohemian Grape, Boscayolo, Brannon Northington, Brooke Waddington, Cameron Horst, Charlie Jiao, Christopher Ellis, CongDT7, Connor Wendt, Crubidoobidoo, Dan Pearce, Daniel Sim, Davide, Derek Arndt, Dongsik Gang, Elmar Moelzer, Eren Aydin, far few giants, Henry Chung, Howard Day, Isobel Shasha, Jack Phelps, John Lism Fishman, John Luna, Joseph Hirst, JP Lee, jpzz kim, JY, Kat, Kyle Harrison, Lasserino, Leafenzo (Seclusion Tower), lexie Dostal, Lhong Lhi, Lien Dinh, Lukas Schneider, Mad Science, Marcin Krzeszowiec, Mattai, Minh Triết Đỗ, Oliver Davies, P W, Patrick, Patrik Bergsten, rafael ludescher, Richard Pieterse, Robin Benzinger, Sam CD-ROM, Samuel Ang, Sandro Traettino, santhosh, SHELL SHELL, Simon Jackson, starbi, Steph, Stephan Maier, Steve DeBusschere, Syll art-design, Taavi Varm, Team 21 Studio, thearperson, Thomas Terkildsen, Tim Hart, Tomasz Patek, ultraklei, Vincent Thémereau, Voids Adrift, Wei Suo, Wojciech Marek, Xavier Larrosa Rogel
>

如果你喜欢本教程，请考虑[关注我](https://nedmakesgames.medium.com/)以便在下一部分发布时收到邮件通知。[第四部分点这里！](https://nedmakesgames.medium.com/)

如果你想从另一个角度看待本教程，我创建了一个[视频版本](https://www.youtube.com/)。

如果你想要一个包含所有着色器文件的 Unity 项目，请考虑[加入我的 Patreon](https://www.patreon.com/NedMakesGames)。你还将获得教程抢先看、投票权等更多福利。谢谢！

如果你有任何问题，欢迎在评论区留言或通过社交媒体联系我。

非常感谢阅读，去做游戏吧！

---

> **Change log / 更新日志：** 本文为翻译版本，内容与原作者原文保持一致。如有翻译疏漏，欢迎指正。
>

