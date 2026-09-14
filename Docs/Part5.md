

## <font style="color:rgb(51, 51, 51);">前言</font>
<font style="color:rgb(51, 51, 51);">欢迎回来！在上一部分中，我们为着色器添加了丰富的表面功能——PBR材质、法线贴图、金属/高光工作流、自发光、视差映射和清漆效果。现在，是时候让我们的材质与场景中的光照系统更深度地交互了！</font>

<font style="color:rgb(51, 51, 51);">在本教程中，我们将学习：</font>

+ **<font style="color:rgb(51, 51, 51);">附加光源（Additional Lights）</font>**<font style="color:rgb(51, 51, 51);">：支持多个点光源和聚光灯</font>
+ **<font style="color:rgb(51, 51, 51);">烘焙光照（Baked Lighting）</font>**<font style="color:rgb(51, 51, 51);">：让着色器读取光照贴图</font>
+ **<font style="color:rgb(51, 51, 51);">遮挡贴图（Occlusion Maps）</font>**<font style="color:rgb(51, 51, 51);">：添加环境光遮挡细节</font>
+ **<font style="color:rgb(51, 51, 51);">反射探针（Reflection Probes）</font>**<font style="color:rgb(51, 51, 51);">：实现表面反射</font>
+ **<font style="color:rgb(51, 51, 51);">光源 Cookie（Light Cookies）</font>**<font style="color:rgb(51, 51, 51);">：支持光源遮罩纹理</font>
+ **<font style="color:rgb(51, 51, 51);">调试光照（Debugging Lighting）</font>**<font style="color:rgb(51, 51, 51);">：学会诊断光照问题</font>
+ **<font style="color:rgb(51, 51, 51);">性能考虑（Performance Considerations）</font>**<font style="color:rgb(51, 51, 51);">：移动端优化策略</font>

<font style="color:rgb(51, 51, 51);">教程开始之前，你需要自己探索将fbx的模型以及贴图正确的放置到场景内，并对他们应用上你自己写的着色器，你可能还得自己学习如何将其他文件格式转换为Unity能够识别的模型格式。</font>

<font style="color:rgb(51, 51, 51);">废话不多说，让我们开始吧！</font>

---

## <font style="color:rgb(51, 51, 51);">一、附加光源</font>
<font style="color:rgb(51, 51, 51);">在第二部分中，我提到过我们的着色器目前只支持主光源（方向光）。如果你在场景中放置了点光源或聚光灯，它们不会影响使用 MyLit 材质的物体。是时候改变这一点了！</font>

### <font style="color:rgb(51, 51, 51);">URP 的光照循环</font>
<font style="color:rgb(51, 51, 51);">URP 使用一种称为</font>**光照循环（Lighting Loop）**<font style="color:rgb(51, 51, 51);">的架构来处理多个光源。理解这个架构是添加多光源支持的关键。</font>

<font style="color:rgb(51, 51, 51);">URP 渲染物体时，会按以下顺序处理光源：</font>

1. **<font style="color:rgb(51, 51, 51);">主光源（Main Light）</font>**<font style="color:rgb(51, 51, 51);">：场景中的方向光，每个物体只处理一个。它在一个独立的循环迭代中计算完整的漫反射和镜面反射。</font>
2. **<font style="color:rgb(51, 51, 51);">附加光源（Additional Lights）</font>**<font style="color:rgb(51, 51, 51);">：点光源、聚光灯等，可以有多个。每个附加光源在独立的循环迭代中叠加贡献。</font>

<font style="color:rgb(51, 51, 51);">URP 的 </font>`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">ForwardRenderer</font>`<font style="color:rgb(51, 51, 51);"> 负责管理整个渲染流程。在渲染器初始化时，它会根据 URP Asset 中的设置配置附加光源的处理方式。每个附加光源会增加一次 </font><font style="color:rgb(51, 51, 51);background-color:#C1E77E;">Draw Call</font><font style="color:rgb(51, 51, 51);">（绘制调用），因为它们是在独立的渲染 Pass 中处理的。</font>

<font style="color:#117CEE;">DrawCall是绘制调用的意思，现在终于知道了当时liris说的这个DrawCall</font>

<font style="color:rgb(51, 51, 51);">主光源在 </font>`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">UniversalForward</font>`<font style="color:rgb(51, 51, 51);"> Pass 中处理，而附加光源的处理方式取决于 URP 的设置。</font>

### <font style="color:rgb(51, 51, 51);">光照循环模式</font>
<font style="color:rgb(51, 51, 51);">URP 提供了两种处理附加光源的模式：</font>

**<font style="color:rgb(51, 51, 51);">Per Pixel（逐像素）</font>**<font style="color:rgb(51, 51, 51);">：每个附加光源都进行完整的光照计算。每个像素独立计算光照方向和衰减，质量最高，但性能开销最大。每个附加光源会增加一次完整的全屏 Draw Call。</font>

**<font style="color:rgb(51, 51, 51);">Per Vertex（逐顶点）</font>**<font style="color:rgb(51, 51, 51);">：附加光源在顶点阶段计算光照结果，由光栅化器插值到像素。性能更好（只需在顶点级别计算一次），但质量较低——法线细节无法正确反映在光照中。</font>

<font style="color:rgb(51, 51, 51);">你可以在 URP 资源设置中选择附加光源的处理模式。路径为：</font>

`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">Project窗口 > 选择URP Asset > Inspector > General > Additional Lights > Per Object Limit</font>`<font style="color:rgb(51, 51, 51);">以及光照计算模式切换。</font>

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1788286449627-1e262372-a4fb-4d03-bb87-88b089e84108.png)

_<font style="color:rgb(51, 51, 51);">URP Asset 中的附加光源设置面板</font>_

<font style="color:rgb(51, 51, 51);">在 Unity 2021.2+ 版本中，URP 的默认光照循环改为</font>**<font style="color:rgb(51, 51, 51);">Per Pixel</font>**<font style="color:rgb(51, 51, 51);">模式，因为现代 GPU 的处理能力已经足够强大。但在移动平台或 VR 项目中，Per Vertex 模式仍然是一个有用的优化选项。</font>

### <font style="color:rgb(51, 51, 51);">Per Pixel vs Per Vertex 的性能对比</font>
| **<font style="color:rgb(51, 51, 51);">特性</font>** | **<font style="color:rgb(51, 51, 51);">Per Pixel</font>** | **<font style="color:rgb(51, 51, 51);">Per Vertex</font>** |
| :--- | :--- | :--- |
| <font style="color:rgb(51, 51, 51);">光照质量</font> | <font style="color:rgb(51, 51, 51);">高（逐像素法线）</font> | <font style="color:rgb(51, 51, 51);">低（插值法线）</font> |
| <font style="color:rgb(51, 51, 51);">Draw Call</font> | <font style="color:rgb(51, 51, 51);">每个光源 +1</font> | <font style="color:rgb(51, 51, 51);">每个光源 +1</font> |
| <font style="color:rgb(51, 51, 51);">顶点计算</font> | <font style="color:rgb(51, 51, 51);">简单</font> | <font style="color:rgb(51, 51, 51);">每个光源的光照计算</font> |
| <font style="color:rgb(51, 51, 51);">像素计算</font> | <font style="color:rgb(51, 51, 51);">每个光源的光照计算</font> | <font style="color:rgb(51, 51, 51);">简单（仅插值）</font> |
| <font style="color:rgb(51, 51, 51);">适用场景</font> | <font style="color:rgb(51, 51, 51);">主机、PC</font> | <font style="color:rgb(51, 51, 51);">移动端、VR</font> |


### <font style="color:rgb(51, 51, 51);">添加多光源支持</font>
<font style="color:rgb(51, 51, 51);">好消息是，</font>`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">UniversalFragmentPBR</font>`<font style="color:rgb(51, 51, 51);"> 函数已经内置了多光源支持！我们只需要确保着色器正确配置了关键字。</font>

```glsl
Shader "Custom/MyLit" {
  ...
    SubShader {
    Tags {"RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline"}

    Pass {
      Name "ForwardLit"
        Tags{"LightMode" = "UniversalForward"}

      ...

        HLSLPROGRAM

        #pragma shader_feature_local_fragment _NORMALMAP
        #pragma shader_feature_local _CLEARCOATMAP
        #pragma shader_feature_local _ALPHA_CUTOUT
        #pragma shader_feature_local _DOUBLE_SIDED_NORMALS
        #pragma shader_feature_local_fragment _SPECULAR_SETUP
        #pragma shader_feature_local_fragment _ROUGHNESS_SETUP
        #pragma shader_feature_local_fragment _ALPHAPREMULTIPLY_ON

        #if UNITY_VERSION >= 202120
        #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
        #else
        #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
        #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
        #endif
        #pragma multi_compile_fragment _ _SHADOWS_SOFT

        // 附加光源支持的关键字
        #pragma multi_compile _ _ADDITIONAL_LIGHTS
        #pragma multi_compile_fragment _ _ADDITIONAL_LIGHTS_SHADOWS
        #pragma multi_compile_fragment _ _REFLECTION_PROBE_BLENDING
        #pragma multi_compile_fragment _ _REFLECTION_PROBE_BOX_PROJECTION
        #pragma multi_compile_fragment _ _LIGHT_LAYERS
        #pragma multi_compile_fragment _ _SCREEN_SPACE_OCCLUSION

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

<font style="color:rgb(51, 51, 51);">在 </font>`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">MyLit.shader</font>`<font style="color:rgb(51, 51, 51);"> 的前向光照通道中添加两个新的 </font>`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">multi_compile</font>`<font style="color:rgb(51, 51, 51);"> 指令：</font>

+ `<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">_ADDITIONAL_LIGHTS</font>`<font style="color:rgb(51, 51, 51);">：启用附加光源支持</font>
+ `<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">_ADDITIONAL_LIGHTS_SHADOWS</font>`<font style="color:rgb(51, 51, 51);">：启用附加光源的阴影</font>
+ `<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">_REFLECTION_PROBE_BLENDING</font>`<font style="color:rgb(51, 51, 51);">：启用反射探针混合（多个探针之间平滑过渡）</font>
+ `<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">_REFLECTION_PROBE_BOX_PROJECTION</font>`<font style="color:rgb(51, 51, 51);">：启用反射探针盒投影（修正室内反射失真）</font>
+ `<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">_LIGHT_LAYERS</font>`<font style="color:rgb(51, 51, 51);">：启用光源层级（让特定光源只影响特定物体）</font>
+ `<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">_SCREEN_SPACE_OCCLUSION</font>`<font style="color:rgb(51, 51, 51);">：启用屏幕空间遮挡（与 SSAO Renderer Feature 配合）</font>

<font style="color:#117CEE;">_ADDITIONAL_LIGHTS 关键字的工作原理</font>

`<font style="color:#117CEE;background-color:rgb(243, 244, 244);">multi_compile</font>`<font style="color:#117CEE;"> 指令会让 Unity 生成多个</font>**<font style="color:#117CEE;">着色器变体（Shader Variants）</font>**<font style="color:#117CEE;">。对于 </font>`<font style="color:#117CEE;background-color:rgb(243, 244, 244);">_ADDITIONAL_LIGHTS</font>`<font style="color:#117CEE;">，Unity 会生成两个变体：一个带有该关键字定义，一个不带有。</font>

<font style="color:#117CEE;">当场景中存在附加光源时，</font>`<font style="color:#117CEE;background-color:rgb(243, 244, 244);">ForwardRenderer</font>`<font style="color:#117CEE;"> 会激活 </font>`<font style="color:#117CEE;background-color:rgb(243, 244, 244);">_ADDITIONAL_LIGHTS</font>`<font style="color:#117CEE;"> 关键字，Unity 会自动选择对应的着色器变体。如果场景中没有附加光源，对应的变体不会被编译到最终的构建中，从而节省包体和内存。</font>

<font style="color:#117CEE;">这是 URP 的关键优化策略：通过关键字系统实现</font>**<font style="color:#117CEE;">按需编译</font>**<font style="color:#117CEE;">。你不需要为不同的光源组合手动编写不同的着色器，multi_compile 会自动处理所有可能性。</font>

<font style="color:#117CEE;">为什么使用 multi_compile 而不是 shader_feature？</font>`<font style="color:#117CEE;background-color:rgb(243, 244, 244);">multi_compile</font>`<font style="color:#117CEE;"> 保证即使材质没有使用某个变体，变体也会被编译。</font>`<font style="color:#117CEE;background-color:rgb(243, 244, 244);">shader_feature</font>`<font style="color:#117CEE;"> 则只编译被实际使用的变体。对于引擎级关键字（如光源相关），URP 使用 multi_compile 确保</font><font style="color:#117CEE;background-color:#C1E77E;">变体始终可用</font><font style="color:#117CEE;">。</font>

### <font style="color:rgb(51, 51, 51);">附加光源阴影</font>
<font style="color:rgb(51, 51, 51);">附加光源的阴影比主光源更复杂。每个附加光源都可以投射阴影，但计算成本很高。URP 使用一种称为</font>**附加光源阴影贴图（Additional Lights Shadow Map）**<font style="color:rgb(51, 51, 51);">的技术来高效地处理多个光源的阴影。</font>

<font style="color:rgb(51, 51, 51);">在同一个渲染 Pass 中，所有附加光源的阴影信息会被打包到一个阴影贴图中。着色器通过 </font>`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">_ADDITIONAL_LIGHTS_SHADOWS</font>`<font style="color:rgb(51, 51, 51);"> 关键字启用对这张共享阴影贴图的采样。</font>

<font style="color:rgb(51, 51, 51);">URP 对附加光源阴影有数量限制：默认最多支持 </font>**<font style="color:rgb(51, 51, 51);background-color:#C1E77E;">4 个附加光源</font>**<font style="color:rgb(51, 51, 51);">同时投射阴影（这个限制取决于平台能力和 URP Asset 设置）。超出限制的光源不会投射阴影，但</font><font style="color:rgb(51, 51, 51);background-color:#C1E77E;">仍然会贡献光照</font><font style="color:rgb(51, 51, 51);">。</font>

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1788288304061-218ea7ff-ea4d-4c54-8690-f0904ea79612.png)

<font style="color:#117CEE;">在 Hierarchy 中选中场景里的点光源/聚光灯，在 Inspector 中找到 Light 组件，展开 Shadows 下拉选项，控制灯光的阴影投影</font>

<font style="color:#117CEE;">另一种方法，你可以通过以下代码控制单个附加光源的阴影投射（在 C# 脚本中）</font>

<font style="color:#117CEE;">在Assets/Scripts/ 文件夹下新建C#脚本，</font>`<font style="color:#117CEE;">Project</font>`<font style="color:#117CEE;">窗口右键 → </font>`<font style="color:#117CEE;">Create</font>`<font style="color:#117CEE;"> → </font>`<font style="color:#117CEE;">C# Script</font>`<font style="color:#117CEE;">，命名为 </font>`<font style="color:#117CEE;">AdditionalLightShadowController.cs</font>`

<font style="color:#117CEE;">将脚本拖到主光源（Directional Light）上，不运行游戏，直接在 Inspector 里勾选/取消</font>`<font style="color:#117CEE;">Cast Shadows</font>`<font style="color:#117CEE;">即可看到效果</font>

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1788293390150-ceb90cf3-7530-4b98-8c05-2dec52948d74.png)<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1788293402304-378263e2-fa8f-48c3-a9e0-cf1254e5f088.png)

```glsl
using UnityEngine;

public class AdditionalLightShadowController : MonoBehaviour
{
  [Tooltip("是否让这个光源透射阴影")]
  public bool castShadows = true;

  [Tooltip("阴影类型")]
  public LightShadows shadowType = LightShadows.Soft;

  private Light targetLight;

  void Start()
  {
    targetLight = GetComponent<Light>();

    if (targetLight == null)
    {
      Debug.LogError("当前GameObject上没有Light组件");
      return;
    }

    ApplyShadowSettings();
  }

  // 新增方法，在Inspector里修改数值时，编辑器会立刻调用它
  private void OnValidate()
  {
    if(targetLight == null)
      targetLight = GetComponent<Light>();

    if(targetLight != null)
      ApplyShadowSettings();
  }
  void ApplyShadowSettings()
  {
    if (castShadows)
    {
      targetLight.shadows = shadowType;
      Debug.Log($"[{gameObject.name}] 阴影已启用：{shadowType}");
    }
    else
    {
      targetLight.shadows = LightShadows.None;
      Debug.Log($"[{gameObject.name}] 阴影已禁用");
    }
  }
}
```

<font style="color:#117CEE;">项目中当前未实现，仅作为扩展：</font>

<font style="color:#117CEE;">如果运行时（Play模式）想动态控制</font>

<font style="color:#117CEE;">如果你想在游戏运行时通过其他脚本调用开关，可以这样写：</font>

<font style="color:#117CEE;">（注意把 ApplyShadowSettings() 改成 public 方法）</font>

```glsl
// 在其他脚本中获取该组件并修改
GetComponent<AdditionalLightShadowController>().castShadows = false;
GetComponent<AdditionalLightShadowController>().ApplyShadowSettings(); // 手动调用刷新
```

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1788294402428-12389521-f0c4-4dc7-a756-8201c8a7fc6c.png)

<font style="color:#117CEE;">关掉主光源，点光源产生的阴影，脚本同样可以挂载到点光源上面（直接光只能有一个产生阴影）</font>

### <font style="color:rgb(51, 51, 51);">光照衰减</font>
<font style="color:rgb(51, 51, 51);">附加光源的强度随距离衰减。URP 提供了几种衰减模型：</font>

**平方反比衰减（Inverse Square / Physical Falloff）**<font style="color:rgb(51, 51, 51);">：物理正确的衰减，遵循平方反比定律：</font>

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1788287885024-bfac4be9-1a83-4b32-a634-e0af3eefff67.png)

<font style="color:rgb(51, 51, 51);">其中I_0是光源的初始强度，d是到光源的距离。这种衰减在近距离变化剧烈，远距离逐渐平缓，符合真实物理规律。URP 防除零优化公式：</font>

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1788287950586-0fa88e05-4980-4a21-b761-9762381e17de.png)

<font style="color:rgb(51, 51, 51);">加 1 是为了避免距离趋近于 0 时光照强度趋近于无穷大。</font>

**<font style="color:rgb(51, 51, 51);">平滑衰减（Smooth）</font>**<font style="color:rgb(51, 51, 51);">：使用平滑曲线模拟衰减，在光源边界处产生柔和的过渡。</font>

**<font style="color:rgb(51, 51, 51);">无衰减（None）</font>**<font style="color:rgb(51, 51, 51);">：不进行衰减，光照强度恒定。</font>

<font style="color:rgb(51, 51, 51);">URP 会自动处理衰减计算，我们只需要确保 </font>`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">InputData</font>`<font style="color:rgb(51, 51, 51);"> 中的世界空间位置正确传递即可——这一点我们已经在做了。在着色器中，衰减值通过 </font>`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">light.distanceAttenuation</font>`<font style="color:rgb(51, 51, 51);"> 传递给光照计算，它是由 C# 端的 </font>`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">AdditionalLightsDirectional</font>`<font style="color:rgb(51, 51, 51);"> 函数预先计算的。</font>

<font style="color:#117CEE;">这里的数学上的探究，就不深入了</font>

### <font style="color:rgb(51, 51, 51);">附加光源数量限制</font>
<font style="color:rgb(51, 51, 51);">URP 中每个物体能同时受多少个附加光源影响，由 URP Asset 中的 </font>**<font style="color:rgb(51, 51, 51);">Per Object Limit</font>**<font style="color:rgb(51, 51, 51);"> 设置控制：</font>

+ <font style="color:rgb(51, 51, 51);">默认值：4（大多数项目）</font>
+ <font style="color:rgb(51, 51, 51);">最大值：8（取决于平台）</font>
+ <font style="color:rgb(51, 51, 51);">移动端建议：1-2 个</font>

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1788294912197-d5aace15-5327-4147-9809-f8c58d85f5d5.png)

<font style="color:rgb(51, 51, 51);">超出限制的光源会被</font><font style="color:rgb(51, 51, 51);background-color:#C1E77E;">自动剔除</font><font style="color:rgb(51, 51, 51);">，最远的光源优先级最低。你可以通过 </font>`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">renderingLayerMask</font>`<font style="color:rgb(51, 51, 51);">控制光源只影响特定层级的物体，这在高光源密度的场景中非常有用。</font>

### <font style="color:rgb(51, 51, 51);">常见坑点</font>
1. **<font style="color:rgb(51, 51, 51);">附加光源不生效</font>**<font style="color:rgb(51, 51, 51);">：检查光源的 </font>`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">Rendering Layer</font>`<font style="color:rgb(51, 51, 51);"> 是否与物体的 </font>`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">Layer</font>`<font style="color:rgb(51, 51, 51);"> 匹配。URP 2021+ 引入了 </font>`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">Rendering Layer Mask</font>`<font style="color:rgb(51, 51, 51);"> 系统，</font><font style="color:rgb(51, 51, 51);background-color:#C1E77E;">光源</font><font style="color:rgb(51, 51, 51);">只会</font><font style="color:rgb(51, 51, 51);background-color:#C1E77E;">影响相同层级</font><font style="color:rgb(51, 51, 51);">的物体。</font>
2. **<font style="color:rgb(51, 51, 51);">移动端性能问题</font>**<font style="color:rgb(51, 51, 51);">：在移动设备上，每个附加光源都是一次完整的 Draw Call。如果一个场景有 10 个点光源，每个物体可能被绘制 11 次（主光源 + 10 个附加光源）。务必控制光源数量。</font>
3. **<font style="color:rgb(51, 51, 51);">Per Vertex 模式下法线细节丢失</font>**<font style="color:rgb(51, 51, 51);">：Per Vertex 模式在</font><font style="color:rgb(51, 51, 51);background-color:#C1E77E;">顶点级别计算光照</font><font style="color:rgb(51, 51, 51);">，法线贴图的细节无法正确表现。如果你的材质</font><font style="color:rgb(51, 51, 51);background-color:#C1E77E;">依赖法线贴图表现细节</font><font style="color:rgb(51, 51, 51);">，</font><font style="color:rgb(51, 51, 51);background-color:#C1E77E;">不要</font><font style="color:rgb(51, 51, 51);">对它们</font><font style="color:rgb(51, 51, 51);background-color:#C1E77E;">使用 Per Vertex </font><font style="color:rgb(51, 51, 51);">模式。</font>
4. **<font style="color:rgb(51, 51, 51);">附加光源阴影不显示</font>**<font style="color:rgb(51, 51, 51);">：确认光源的 </font>`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">Shadows</font>`<font style="color:rgb(51, 51, 51);"> 设置为 </font>`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">Soft</font>`<font style="color:rgb(51, 51, 51);"> 或 </font>`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">Hard</font>`<font style="color:rgb(51, 51, 51);">，并且 URP Asset 中启用了附加光源阴影。</font>

### <font style="color:rgb(51, 51, 51);">测试附加光源</font>
<font style="color:rgb(51, 51, 51);">在场景中放置几个点光源或聚光灯，确保它们影响使用 MyLit 材质的物体。你应该能看到：</font>

+ <font style="color:rgb(51, 51, 51);">多个光源同时照亮物体</font>
+ <font style="color:rgb(51, 51, 51);">每个光源的颜色和强度正确叠加</font>
+ <font style="color:rgb(51, 51, 51);">附加光源的阴影（如果启用了）</font>

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1788295182712-ab90ec7c-126f-4770-b48b-8b8c8c0e0395.png)

_<font style="color:rgb(51, 51, 51);">多个点光源同时影响 MyLit 材质</font>_

### <font style="color:rgb(51, 51, 51);">实际项目修改</font>
<font style="color:rgb(51, 51, 51);">在你的 </font>`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">MyLit.shader</font>`<font style="color:rgb(51, 51, 51);"> 文件中，找到 ForwardLit Pass 的 HLSLPROGRAM 部分，在现有的 </font>`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">#pragma multi_compile_fragment _ _SHADOWS_SOFT</font>`<font style="color:rgb(51, 51, 51);"> 下方添加以下代码：</font>

```glsl
// 在 MyLit.shader 的 ForwardLit Pass 中// 位于 #pragma multi_compile_fragment _ _SHADOWS_SOFT 之后
// 附加光源支持
pragma multi_compile _ _ADDITIONAL_LIGHTS
  pragma multi_compile_fragment _ _ADDITIONAL_LIGHTS_SHADOWS
  // 反射探针混合与盒投影
  pragma multi_compile_fragment _ _REFLECTION_PROBE_BLENDING
  pragma multi_compile_fragment _ _REFLECTION_PROBE_BOX_PROJECTION
  // 光源层级
  pragma multi_compile_fragment _ _LIGHT_LAYERS
  // 屏幕空间遮挡
  pragma multi_compile_fragment _ _SCREEN_SPACE_OCCLUSION
```

---

这些关键字不需要在 `MyLitCommon.hlsl` 中添加任何属性或纹理声明——它们完全由 URP 引擎端控制。你只需要确保它们出现在 ForwardLit Pass 的编译指令中即可。

---

## <font style="color:rgb(51, 51, 51);">二、烘焙光照</font>
<font style="color:rgb(51, 51, 51);">实时光照很棒，但性能开销很大。对于不会移动的光源和物体，我们可以使用</font>**<font style="color:rgb(51, 51, 51);">烘焙光照（Baked Lighting）</font>**<font style="color:rgb(51, 51, 51);">来预计算光照结果，存储在</font>**<font style="color:rgb(167, 167, 167);"></font>****<font style="color:rgb(51, 51, 51);">光照贴图（Lightmap）</font>**<font style="color:rgb(51, 51, 51);">中。</font>

### <font style="color:rgb(51, 51, 51);">光照贴图基础</font>
<font style="color:rgb(51, 51, 51);">光照贴图本质上是一张纹理，存储了每个表面点的预计算光照信息。在运行时，着色器只需要采样这张纹理就能获得复杂的光照效果，几乎零性能成本。</font>

<font style="color:rgb(51, 51, 51);">要让我们的着色器支持光照贴图，需要做两件事：</font>

1. **<font style="color:rgb(51, 51, 51);">传递光照贴图 UV</font>**<font style="color:rgb(51, 51, 51);">：每个顶点需要知道自己在光照贴图中的位置</font>
2. **<font style="color:rgb(51, 51, 51);">采样光照贴图</font>**<font style="color:rgb(51, 51, 51);">：在片段函数中读取预计算的光照数据</font>

### <font style="color:rgb(51, 51, 51);">光照贴图 UV 详解</font>
<font style="color:rgb(51, 51, 51);">每个被烘焙的物体都有两组 UV：</font>

+ **<font style="color:rgb(51, 51, 51);">模型 UV（TEXCOORD0）</font>**<font style="color:rgb(51, 51, 51);">：用于采样颜色贴图、法线贴图等</font>
+ **<font style="color:rgb(51, 51, 51);">光照贴图 UV（TEXCOORD1）</font>**<font style="color:rgb(51, 51, 51);">：用于采样光照贴图</font>

<font style="color:rgb(51, 51, 51);">光照贴图 UV 存储在 </font>`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">TEXCOORD1</font>`<font style="color:rgb(51, 51, 51);"> 语义中（与模型 UV 的 </font>`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">TEXCOORD0</font>`<font style="color:rgb(51, 51, 51);"> 不同）。</font>

#### <font style="color:rgb(51, 51, 51);">为什么需要第二套 UV？</font>
<font style="color:rgb(51, 51, 51);">光照贴图 UV 与模型 UV 有本质区别：</font>

+ **<font style="color:rgb(51, 51, 51);">模型 UV</font>**<font style="color:rgb(51, 51, 51);">：关注纹理的连续性和重复性，允许重叠（如对称模型）</font>
+ **<font style="color:rgb(51, 51, 51);">光照贴图 UV</font>**<font style="color:rgb(51, 51, 51);">：要求每个表面点在光照贴图中有</font>**<font style="color:rgb(51, 51, 51);">唯一</font>**<font style="color:rgb(51, 51, 51);">的坐标，不允许重叠</font>

<font style="color:rgb(51, 51, 51);">如果光照贴图 UV 重叠，多个表面点会采样到同一个光照值，导致光照错误（如一面墙的阴影出现在另一面墙上）。</font>

#### <font style="color:rgb(51, 51, 51);">Generate Lightmap UVs</font>
<font style="color:rgb(51, 51, 51);">选中模型文件->Inspector->切换到model选项卡->在下方Geometry部分，勾选 </font>**<font style="color:rgb(51, 51, 51);">"Generate Lightmap UVs"</font>**<font style="color:rgb(51, 51, 51);"> 可以让 Unity 自动生成第二套 UV。你需要设置以下参数：</font>

+ **<font style="color:rgb(51, 51, 51);">Hard Angle</font>**<font style="color:rgb(51, 51, 51);">：决定 UV 接缝的角度阈值（默认 88°）</font>
+ **<font style="color:rgb(51, 51, 51);">Pack Margin</font>**<font style="color:rgb(51, 51, 51);">：UV 岛之间的间距（防止漏光，默认 4 单位）</font>

`<font style="color:#117CEE;">Pack Margin</font>`<font style="color:#117CEE;">需要</font>`<font style="color:#117CEE;">Margin Method</font>`<font style="color:#117CEE;">切换成</font>`<font style="color:#117CEE;">Manual</font>`<font style="color:#117CEE;">才会出现</font>

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1788313897029-6427259c-4d3b-433f-93e1-37475a304462.png)

_<font style="color:rgb(51, 51, 51);">模型导入设置中的 Generate Lightmap UVs 选项</font>_

<font style="color:rgb(167, 167, 167);"></font><font style="color:rgb(119, 119, 119);">注意：如果模型自带第二套 UV（在建模软件中创建），Unity 会优先使用它。只有当模型没有第二套 UV 时，才会使用自动生成的。</font>

### <font style="color:rgb(51, 51, 51);">完整的烘焙工作流程</font>
<font style="color:rgb(51, 51, 51);">以下是烘焙光照的完整步骤：</font>

1. **<font style="color:rgb(51, 51, 51);background-color:#C1E77E;">标记</font>****<font style="color:rgb(51, 51, 51);">静态物体</font>**<font style="color:rgb(51, 51, 51);">：选择场景中的静态物体，勾选 Inspector 右上角的 </font>**<font style="color:rgb(51, 51, 51);">Static</font>**<font style="color:rgb(51, 51, 51);"> 复选框。确保 </font>**<font style="color:rgb(51, 51, 51);">"Contribute GI"</font>**<font style="color:rgb(51, 51, 51);"> 被启用。</font>

<font style="color:#117CEE;">Unity 会自动烘焙所有</font><font style="color:#117CEE;background-color:#C1E77E;">标记为 Static 的物体</font><font style="color:#117CEE;">和</font><font style="color:#117CEE;background-color:#C1E77E;">所有 Baked/Mixed 光源</font><font style="color:#117CEE;">，不需要手动选择目标。</font>

2. **<font style="color:rgb(51, 51, 51);">设置光源模式</font>**<font style="color:rgb(51, 51, 51);">：选择光源，在 Inspector 中将 </font>**<font style="color:rgb(51, 51, 51);">Mode</font>**<font style="color:rgb(51, 51, 51);"> 设置为 </font>**<font style="color:rgb(51, 51, 51);">Baked</font>**<font style="color:rgb(51, 51, 51);"> 或 </font>**<font style="color:rgb(51, 51, 51);">Mixed</font>**<font style="color:rgb(51, 51, 51);">。</font>
3. **<font style="color:rgb(51, 51, 51);">打开 Lighting 窗口</font>**<font style="color:rgb(51, 51, 51);">：</font>`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">Window > Rendering > Lighting</font>`<font style="color:rgb(51, 51, 51);">。</font>
4. **<font style="color:rgb(51, 51, 51);">配置烘焙参数</font>**<font style="color:rgb(51, 51, 51);">：</font>
    - **<font style="color:rgb(51, 51, 51);">Lightmapper</font>**<font style="color:rgb(51, 51, 51);">：Progressive GPU（推荐）或 Progressive CPU</font>
    - **<font style="color:rgb(51, 51, 51);">Lightmap Resolution</font>**<font style="color:rgb(51, 51, 51);">：控制光照贴图的精度（默认 40 texels/unit）</font>
    - **<font style="color:rgb(51, 51, 51);">Lightmap Size</font>**<font style="color:rgb(51, 51, 51);">：单张光照贴图的最大尺寸（默认 1024）</font>

<font style="color:#117CEE;">其他设置项：</font>

<font style="color:#117CEE;">Compress Lightmaps: 是否压缩光照贴图以节省空间。</font>

<font style="color:#117CEE;">Bounces: 间接光反弹次数，通常2就足够。</font>

<font style="color:#117CEE;">Direct Samples / Indirect Samples: 控制直接/间接光照的采样质量，值越高噪点越少，烘焙越慢。</font>

<font style="color:#117CEE;">Ambient Occlusion: 开启以增加物体间的接触阴影，增强真实感。</font>

5. **<font style="color:rgb(51, 51, 51);">点击 Generate Lighting</font>**<font style="color:rgb(51, 51, 51);">：开始烘焙。烘焙时间取决于场景复杂度和参数设置。</font>

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1788314566156-2b5de13e-75d0-4f3a-be19-4920d6878471.png)<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1788314730655-cac25da2-2273-4fc1-a574-a8c65168c91b.png)<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1788314949622-693001ff-7b82-4d4d-8ccf-9b8d3ae16911.png)<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1788315677333-280de63c-2736-4f54-9480-9dfda92f0c0c.png)

_<font style="color:rgb(51, 51, 51);">Lighting 窗口和 Generate Lighting 按钮</font>_

### <font style="color:rgb(51, 51, 51);">三种混合模式的详细对比</font>
<font style="color:rgb(51, 51, 51);">URP 支持三种光照混合模式，在 Lighting 窗口的 </font>**<font style="color:rgb(51, 51, 51);">Lighting Mode</font>**<font style="color:rgb(51, 51, 51);"> 中设置：</font>

| **<font style="color:rgb(51, 51, 51);">模式</font>** | **<font style="color:rgb(51, 51, 51);">烘焙内容</font>** | **<font style="color:rgb(51, 51, 51);">实时内容</font>** | **<font style="color:rgb(51, 51, 51);">性能</font>** | **<font style="color:rgb(51, 51, 51);">适用场景</font>** |
| :--- | :--- | :--- | :--- | :--- |
| **<font style="color:rgb(51, 51, 51);">Baked Indirect</font>** | <font style="color:rgb(51, 51, 51);">间接光照（反弹光）</font> | <font style="color:rgb(51, 51, 51);">直接光照 + 阴影</font> | <font style="color:rgb(51, 51, 51);">中</font> | <font style="color:rgb(51, 51, 51);">大多数场景</font> |
| **<font style="color:rgb(51, 51, 51);">Shadowmask</font>** | <font style="color:rgb(51, 51, 51);">阴影遮罩</font> | <font style="color:rgb(51, 51, 51);">直接光照</font> | <font style="color:rgb(51, 51, 51);">低</font> | <font style="color:rgb(51, 51, 51);">需要动态阴影的场景</font> |
| **<font style="color:rgb(51, 51, 51);">Subtractive</font>** | <font style="color:rgb(51, 51, 51);">所有光照</font> | <font style="color:rgb(51, 51, 51);">直接光照叠加</font> | <font style="color:rgb(51, 51, 51);">最低</font> | <font style="color:rgb(51, 51, 51);">性能敏感项目</font> |


**<font style="color:rgb(51, 51, 51);">Baked Indirect</font>**<font style="color:rgb(51, 51, 51);">：烘焙间接光照（光线在物体间反弹的效果），实时计算直接光照和阴影。这是最常用的模式，平衡了质量和性能。</font>

**<font style="color:rgb(51, 51, 51);">Shadowmask</font>**<font style="color:rgb(51, 51, 51);">：烘焙一张阴影遮罩纹理，实时光源通过这张遮罩判断是否被遮挡。动态物体可以使用烘焙的阴影信息，但无法与实时阴影完美融合。</font>

**<font style="color:rgb(51, 51, 51);">Subtractive</font>**<font style="color:rgb(51, 51, 51);">：烘焙所有光照（包括直接和间接），实时光源只叠加直接光照。这是性能最低的模式，但视觉质量可能不如前两种。</font>

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1788316135712-ba11b7dd-9cb4-416a-aa03-2989d121f0da.png)

也可以打开 Lighting 窗口：`Window > Rendering > Lighting`打开窗口

### <font style="color:rgb(51, 51, 51);">光照贴图 UV 的代码处理</font>
```glsl
struct Attributes {
  float3 positionOS : POSITION;
  float3 normalOS : NORMAL;
  float4 tangentOS : TANGENT;
  float2 uv : TEXCOORD0;       // 模型 UV
  float2 uv2 : TEXCOORD1;      // 光照贴图 UV ← 新增
};

struct Interpolators {
  float4 positionCS : SV_POSITION;
  float2 uv : TEXCOORD0;       // 模型 UV
  float2 uv2 : TEXCOORD1;      // 光照贴图 UV ← 新增
  float3 positionWS : TEXCOORD2;
  float3 normalWS : TEXCOORD3;
  float4 tangentWS : TEXCOORD4;
};
```

<font style="color:rgb(51, 51, 51);">在 </font>`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">MyLitForwardLitPass.hlsl</font>`<font style="color:rgb(51, 51, 51);"> 中，向 </font>`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">Attributes</font>`<font style="color:rgb(51, 51, 51);"> 和 </font>`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">Interpolators</font>`<font style="color:rgb(51, 51, 51);"> 结构体添加光照贴图 UV 字段。</font>

```glsl
Interpolators Vertex(Attributes input) {
  Interpolators output;

  VertexPositionInputs posnInputs = GetVertexPositionInputs(input.positionOS);
  VertexNormalInputs normInput = GetVertexNormalInputs(input.normalOS);

  output.positionCS = posnInputs.positionCS;
  output.uv = TRANSFORM_TEX(input.uv, _ColorMap);
  output.uv2 = input.uv2;  // ← 新增：传递光照贴图 UV
  output.normalWS = normInput.normalWS;
  output.tangentWS = float4(normInput.tangentWS, input.tangentOS.w);
  output.positionWS = posnInputs.positionWS;

  return output;
}
```

<font style="color:rgb(51, 51, 51);">在顶点函数中，将光照贴图 UV 从 </font>`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">Attributes</font>`<font style="color:rgb(51, 51, 51);"> 传递到 </font>`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">Interpolators</font>`<font style="color:rgb(51, 51, 51);">。</font>

### <font style="color:rgb(51, 51, 51);">采样光照贴图</font>
<font style="color:rgb(51, 51, 51);">URP 提供了一组宏来处理光照贴图的采样。这些宏会根据当前的渲染模式（烘焙、混合、实时）自动选择正确的采样方式。</font>

```glsl
float4 Fragment(Interpolators input
                #ifdef _DOUBLE_SIDED_NORMALS
                , FRONT_FACE_TYPE frontFace : FRONT_FACE_SEMANTIC
                #endif
               ) : SV_TARGET {
  ...

    InputData lightingInput = (InputData)0;
  lightingInput.positionWS = input.positionWS;
  lightingInput.normalWS = normalWS;
  lightingInput.viewDirectionWS = viewDirWS;
  lightingInput.shadowCoord = TransformWorldToShadowCoord(input.positionWS);

  // ← 新增：光照贴图采样
  lightingInput.bakedGI = SampleLightmap(input.uv2, normalWS);

  ...
  }
```

<font style="color:rgb(51, 51, 51);">URP 的 </font>`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">SampleLightmap</font>`<font style="color:rgb(51, 51, 51);"> 宏会自动处理光照贴图的采样。它需要光照贴图 UV 和世界空间法线作为参数。另外，</font><font style="color:#000000;">光照贴图支持不需要在 MyLit.shader 的 Properties 中添加任何属性。</font>`<font style="color:#000000;background-color:rgb(243, 244, 244);">SampleLightmap</font>`<font style="color:#000000;"> 宏会自动处理所有事情。</font>

注意：`<font style="color:rgb(17, 124, 238);background-color:rgb(243, 244, 244);">SampleLightmap</font>` 是一个宏，不是函数。它会根据光照贴图的模式（烘焙、混合、实时）展开为不同的代码。

#### <font style="color:rgb(51, 51, 51);">SampleLightmap 宏展开后是什么？</font>
`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">SampleLightmap</font>`<font style="color:rgb(51, 51, 51);"> 宏在 URP 中展开为以下逻辑：</font>

```glsl
// 简化版展开
float3 SampleLightmap(float2 lightmapUV, float3 normalWS) {
  #ifdef LIGHTMAP_ON
  // 使用 unity_LightmapST 对 UV 进行变换
  float2 transformedUV = lightmapUV * unity_LightmapST.xy + unity_LightmapST.zw;
  // 采样光照贴图
  float4 lightmapSample = SAMPLE_TEXTURE2D(unity_Lightmap, samplerunity_Lightmap, transformedUV);
  // 使用 LIGHTMAP_RGBM 解码
  float3 bakedGI = DecodeLightmap(lightmapSample);
  // 应用法线方向的影响（用于方向性光照贴图）
  #ifdef DIRLIGHTMAP_COMBINED
  // 方向性光照贴图的额外处理
  #endif
  return bakedGI;
  #else
  // 没有光照贴图时返回零
  return float3(0, 0, 0);
  #endif
}
```

`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">LIGHTMAP_ON</font>`<font style="color:rgb(51, 51, 51);"> 关键字由 Unity 自动设置，当物体参与烘焙时启用。</font>`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">unity_LightmapST</font>`<font style="color:rgb(51, 51, 51);"> 是光照贴图的缩放和平移参数，由 Unity 自动传递。</font>

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1788317122558-1df798ad-2a9e-48ec-a5a9-3c03fea7e3ef.png)

<font style="color:#117CEE;">光照烘焙后颜色碎掉了</font>

<font style="color:#117CEE;">检查是不是代码写错了</font>

<font style="color:#117CEE;">MyLitForwardLitPass.hlsl 第 62-63 行</font>

```glsl
output.uv = TRANSFORM_TEX(input.uv, _ColorMap);
output.uv = input.uv2; // 传递光照贴图UV
// 原本的UV被光照贴图UV覆盖，改成这样
output.uv2 = input.uv2; // 传递光照贴图UV
```

这里我还顺便修复了下Bake后点光源没有阴影的问题，设置灯光的Light->Mode后再次烘焙即可，其余点光源也可以烘焙一下

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1788336116356-459c91eb-6ebd-4985-a36c-bff143978fc5.png)

### <font style="color:rgb(51, 51, 51);">光照探针（Light Probes）</font>
<font style="color:rgb(51, 51, 51);">对于移动的物体，它们无法使用光照贴图（因为光照贴图是静态的）。URP 使用</font>**光照探针（Light Probes）**<font style="color:rgb(51, 51, 51);">来为动态物体提供烘焙光照信息。</font>

<font style="color:rgb(51, 51, 51);">光照探针是场景中放置的采样点，存储了该位置的光照信息。动态物体会根据自身位置，插值附近的光照探针数据。</font>

<font style="color:#117CEE;">说白了就是放几个采样点，对这几个点的光照进行烘焙，根据自身位置，插值附近采样点的数据</font>

<font style="color:#117CEE;">探针不是Game Object，是一个整体，本质上是Light Probe Group组件内部的一组坐标点（每个探针是27个浮点数编码的球谐光照），可以进Scene视图用Edit Light Probe Group工具点选单个黄球</font>

#### <font style="color:rgb(51, 51, 51);">光照探针的放置策略</font>
+ <font style="color:rgb(51, 51, 51);">在</font><font style="color:rgb(51, 51, 51);background-color:#C1E77E;">光照变化剧烈</font><font style="color:rgb(51, 51, 51);">的区域（如阴影边界）密集放置</font>
+ <font style="color:rgb(51, 51, 51);">在</font><font style="color:rgb(51, 51, 51);background-color:#C1E77E;">开阔</font><font style="color:rgb(51, 51, 51);">平坦区域</font><font style="color:rgb(51, 51, 51);background-color:#C1E77E;">稀疏放置</font>
+ <font style="color:rgb(51, 51, 51);">确保动态</font><font style="color:rgb(51, 51, 51);background-color:#C1E77E;">物体移动路径</font><font style="color:rgb(51, 51, 51);">上始终有探针覆盖</font>

#### <font style="color:rgb(51, 51, 51);">SH（球谐函数）编码原理</font>
<font style="color:rgb(51, 51, 51);">光照探针使用</font>**球谐函数（Spherical Harmonics, SH）**<font style="color:rgb(51, 51, 51);">来编码光照信息。SH 是一种数学工具，可以将球面上的函数（如环境光照）分解为一系列基函数的线性组合。</font>

<font style="color:rgb(51, 51, 51);">URP 使用 3 阶 SH（9 个系数），可以编码低频的环境光照信息。虽然精度有限，但对于漫反射光照来说已经足够。</font>

<font style="color:#117CEE;">9 个球谐系数 × RGB 三个颜色通道 = 27，球谐（Spherical Harmonics）可以理解为"用一组基函数去拟合一个球面全景图"。按阶数 band 分组</font>

| **阶** | **数学名** | **系数个数** | **物理含义** |
| :--- | :--- | :--- | :--- |
| <font style="color:#117CEE;">L0</font> | <font style="color:#117CEE;">常数项</font> | <font style="color:#117CEE;">1</font> | <font style="color:#117CEE;">环境光的</font>**平均亮度**<font style="color:#117CEE;">（四面八方都一样）</font> |
| <font style="color:#117CEE;">L1</font> | <font style="color:#117CEE;">线性项</font> | <font style="color:#117CEE;">3</font> | <font style="color:#117CEE;">光主要从</font>**哪个方向**<font style="color:#117CEE;">来（x/y/z 三个轴向的强弱差）</font> |
| <font style="color:#117CEE;">L2</font> | <font style="color:#117CEE;">二次项</font> | <font style="color:#117CEE;">5</font> | <font style="color:#117CEE;">更细的分布形状（哪里有亮斑、哪里被遮挡）</font> |


<font style="color:#117CEE;">单个探针极便宜：27 × 4 字节 = 108 字节，约 0.1 KB，所以记录的光照是高度模糊的，所以需要增加探针密度</font>

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1788344649950-75908373-bed0-4a47-96c0-6c6e3ae3118f.png)

<font style="color:#117CEE;">进 Scene 视图用 Edit Light Probe Group 工具才能点选单个黄球</font>

<font style="color:#117CEE;">Hierarchy 里的对象是一个探针组，场景里实际的探针点为8个（默认），排成立方体的8个顶角，你可以自己增加探针点，如上图</font>

#### <font style="color:rgb(51, 51, 51);">探针代理体积（Probe Proxy Volume）</font>
<font style="color:rgb(51, 51, 51);">对于大型动态物体（如角色），单点探针插值会导致光照不准确。</font>**<font style="color:rgb(51, 51, 51);">探针代理体积（Probe Proxy Volume, PPV）</font>**<font style="color:rgb(51, 51, 51);">允许物体在多个位置采样探针，然后进行体积插值，获得更准确的光照。</font>

<font style="color:rgb(51, 51, 51);">URP 会自动处理光照探针的插值，我们只需要确保 </font>`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">InputData</font>`<font style="color:rgb(51, 51, 51);"> 中的世界空间位置正确即可。</font>

<font style="color:#117CEE;">这条路走不通，至少在当前版本。结论是URP 用不了 LPPV(PPV 和 LPPV 是同一件事，官方全称带 Light，缩写才是 LPPV)。Unity 6 / URP 17 起 APV(Adaptive Probe Volumes) 转正，它直接把 LPPV 想解决的问题做掉了——逐像素采样，天然就有空间梯度，不再需要给每个大物体挂一个代理体。</font>

<font style="color:#117CEE;">【埋坑】这里后续用APV来实现吧</font>

### <font style="color:rgb(51, 51, 51);">混合烘焙和实时光照</font>
<font style="color:rgb(51, 51, 51);">在实际项目中，通常会同时使用烘焙光照和实时光照。例如，静态物体使用烘焙光照，而动态物体使用实时光照。URP 支持几种混合模式：</font>

+ **<font style="color:rgb(51, 51, 51);">Baked Indirect</font>**<font style="color:rgb(51, 51, 51);">：烘焙间接光照，实时直接光照</font>
+ **<font style="color:rgb(51, 51, 51);">Shadowmask</font>**<font style="color:rgb(51, 51, 51);">：烘焙阴影遮罩，实时直接光照</font>
+ **<font style="color:rgb(51, 51, 51);">Subtractive</font>**<font style="color:rgb(51, 51, 51);">：烘焙所有光照，实时光源叠加直接光照</font>

`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">SampleLightmap</font>`<font style="color:rgb(51, 51, 51);"> 宏会根据当前的混合模式自动调整采样方式。</font>

### <font style="color:rgb(51, 51, 51);">常见坑点</font>
1. **<font style="color:rgb(51, 51, 51);">UV 重叠导致漏光</font>**<font style="color:rgb(51, 51, 51);">：如果光照贴图UV有</font><font style="color:rgb(51, 51, 51);background-color:#C1E77E;">重叠</font><font style="color:rgb(51, 51, 51);">，烘焙时会出现</font><font style="color:rgb(51, 51, 51);background-color:#C1E77E;">光泄漏</font><font style="color:rgb(51, 51, 51);">。检查模型的 Lightmap UV，确保没有重叠。</font>
2. **<font style="color:rgb(51, 51, 51);">光照贴图分辨率不足</font>**<font style="color:rgb(51, 51, 51);">：如果物体表面出现</font><font style="color:rgb(51, 51, 51);background-color:#C1E77E;">模糊的光照效果</font><font style="color:rgb(51, 51, 51);">，增加 Lighting 窗口中的</font><font style="color:rgb(51, 51, 51);background-color:#C1E77E;"> </font>**<font style="color:rgb(51, 51, 51);background-color:#C1E77E;">Lightmap Resolution</font>**<font style="color:rgb(51, 51, 51);">。</font>
3. **<font style="color:rgb(51, 51, 51);">动态物体穿过探针边界时跳变</font>**<font style="color:rgb(51, 51, 51);">：当动态物体从一个探针区域移动到另一个时，光照可能突然变化。增加探针</font><font style="color:rgb(51, 51, 51);background-color:#C1E77E;">密度</font><font style="color:rgb(51, 51, 51);">或使用 PPV 可以缓解。</font>
4. **<font style="color:rgb(51, 51, 51);">烘焙后物体变黑</font>**<font style="color:rgb(51, 51, 51);">：确认物体被</font><font style="color:rgb(51, 51, 51);background-color:#C1E77E;">标记为 Static</font><font style="color:rgb(51, 51, 51);">，光源模式为 Baked/Mixed，并且已经点击了 Generate Lighting。</font>

### <font style="color:rgb(51, 51, 51);">测试烘焙光照</font>
1. <font style="color:rgb(51, 51, 51);">将场景中的光源设置为"Baked"或"Mixed"模式</font>
2. <font style="color:rgb(51, 51, 51);">将静态物体标记为"Contribute GI"</font>
3. <font style="color:rgb(51, 51, 51);">打开"Window > Rendering > Lighting"窗口，点击"Generate Lighting"</font>
4. <font style="color:rgb(51, 51, 51);">运行游戏，观察烘焙光照效果</font>

<font style="color:#117CEE;">这里主光源和点光源我都</font>

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1788346187183-117af65b-da90-4a58-89a5-00c5b5b6e208.png)<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1788346284969-e40101bf-de0e-4949-afa7-3c04deb20c26.png)

_<font style="color:rgb(51, 51, 51);">烘焙光照效果：复杂的光照几乎零性能成本</font>_

<font style="color:#117CEE;">踩坑记录：我都照做了，但是烘焙出来直接黑掉</font>

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1788347313180-f07f12e7-1825-4436-b9cf-b4896cf02680.png)

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1788349493650-9d553639-bb3c-4414-b6a0-1a3a7a102a66.png)

在`MyLit.shader`的`ForwardLit` pass 里添加<font style="background-color:#C1E77E;">光照贴图关键字</font>和<font style="background-color:#C1E77E;">光照探针SH评估</font>

```glsl
SubShader{
        Tags{"RenderPipeline" = "UniversalPipeline" "RenderType" = "Opaque" }
        Pass{          
            // ... code omitted
            // 光源层级
            #pragma multi_compile_fragment _ _LIGHT_LAYERS
            // 屏幕空间遮挡
            #pragma multi_compile_fragment _ _SCREEN_SPACE_OCCLUSION

            // Unity defined keywords - 烘焙光照必须
            #pragma multi_compile _ DIRLIGHTMAP_COMBINED
            #pragma multi_compile _ LIGHTMAP_ON
            #pragma multi_compile _ DYNAMICLIGHTMAP_ON
            #pragma multi_compile _ LIGHTMAP_SHADOW_MIXING
            #pragma multi_compile _ SHADOWS_SHADOWMASK

            // 光照探针SH评估
            #pragma multi_compile _ EVALUATE_SH_MIXED EVALUATE_SH_VERTEX


#if UNITY_VERSION >= 202120
            #pragma multi_compile_fragment _ DEBUG_DISPLAY
#endif
            // Register our programmable stage functions
            #pragma vertex Vertex
            #pragma fragment Fragment

            // Include our code file
            #include "MyLitForwardLitPass.hlsl"
        ENDHLSL
        }
// ... code omitted
```

<font style="color:#117CEE;">在</font>`<font style="color:#117CEE;">MyLit.shader</font>`<font style="color:#117CEE;">添加纹理声明</font>

```glsl
    Properties{
// ... code omitted
        [HideInInspector][NoScaleOffset] unity_Lightmaps("unity_Lightmaps", 2DArray) = "" {}
        [HideInInspector][NoScaleOffset] unity_LightmapsInd("unity_LightmapsInd", 2DArray) = "" {}
        [HideInInspector][NoScaleOffset] unity_ShadowMasks("unity_ShadowMasks", 2DArray) = "" {}
    }
```

`<font style="color:#117CEE;">MyLit.shader</font>`<font style="color:#117CEE;"> 的 </font>`<font style="color:#117CEE;">SubShader</font>`<font style="color:#117CEE;"> 中添加一个完整的 </font>`<font style="color:#117CEE;">Meta</font>`<font style="color:#117CEE;"> pass，注意</font>`<font style="color:#117CEE;">HLSLPROGRAM</font>`<font style="color:#117CEE;">和</font>`<font style="color:#117CEE;">ENDHLSL</font>`<font style="color:#117CEE;">要成对出现</font>

```glsl
Pass
{
    Name "Meta"
    Tags { "LightMode" = "Meta" }
    Cull Off
    HLSLPROGRAM
    #pragma target 2.0
    #pragma vertex Vertex
    #pragma fragment Fragment
    #pragma shader_feature_local_fragment _SPECULAR_SETUP
    #pragma shader_feature_local_fragment _EMISSION
    #include "MyLitMetaPass.hlsl"
    ENDHLSL
}
```

<font style="color:#117CEE;">我们还缺少</font>`<font style="color:#117CEE;">MyLitMetaPass.hlsl</font>`<font style="color:#117CEE;">，在Scripts文件夹下创建它</font>

```glsl
#ifndef MY_LIT_META_PASS_INCLUDE
#define MY_LIT_META_PASS_INCLUDE

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/UniversalMetaPass.hlsl"
#include "MyLitCommon.hlsl"

// 顶点函数：UniversalMetaPass.hlsl里的UniversVertexMeta引用了_BaseMap
// 我们的shader用的是_ColorMap，所以需要自己写一个
Varyings Vertex(Attributes input){
    Varyings output = (Varyings)0;
    output.positionCS = UnityMetaVertexPosition(input.positionOS.xyz, input.uv1, input.uv2);
    output.uv = TRANSFORM_TEX(input.uv0, _ColorMap);
    return output;
}

// 片段函数：采样材质纹理，输出给光照烘焙器
float4 Fragment(Varyings input) : SV_TARGET{
    // 1. 采样反照率（和ForwardLit里一样用TRANSFORM_TEX处理UV平铺）
    float2 uv = TRANSFORM_TEX(input.uv, _ColorMap);
    float3 albedo = SAMPLE_TEXTURE2D(_ColorMap, sampler_ColorMap, uv).rgb * _ColorTint.rgb;

    // 2. 采样自发光
    float3 emission = SAMPLE_TEXTURE2D(_EmissionMap, sampler_EmissionMap, uv).rgb * _EmissionTint.rgb;

    // 3. 填UnityMetaInput，传给内置的UnityMetaFragment
    UnityMetaInput metaInput;
    metaInput.Albedo = albedo;
    metaInput.Emission = emission;

    return UnityMetaFragment(metaInput);
}
#endif
```

<font style="color:#117CEE;">我们还需要在 </font>`<font style="color:#117CEE;">MyLitCommon.hlsl</font>`<font style="color:#117CEE;">里第5行添加，因为</font>`<font style="color:#117CEE;">MetaPass.hlsl</font>`<font style="color:#117CEE;"> 第 81 行用到了 </font>`<font style="color:#117CEE;">unity_LightmapST</font>`<font style="color:#117CEE;">，这个变量在 </font>`<font style="color:#117CEE;">UnityInput.hlsl</font>`<font style="color:#117CEE;"> 里声明</font>

```glsl
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/UnityInput.hlsl"  // ← 加这行
```

<font style="color:#117CEE;">【埋坑】</font><font style="color:#117CEE;background-color:#C1E77E;">【已填坑】</font><font style="color:#117CEE;">这里埋坑了，烘焙的时候只有点光源看上去能正常烘焙，其余的主光源，关掉后直接变黑了，我已经绑定过static了，主光源关灯后场景直接凉凉。emm，现在是点光源关掉后也全黑，这个烘焙有点迷，暂时解决不了</font>

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1788361020746-e1f20591-462a-475f-8373-c395bc0ad7b7.png)

<font style="color:#117CEE;">关闭灯光后全黑，关闭了主光和一个点光源</font>

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1788361064118-d79283d3-67ac-4c3a-ba21-845108de374e.png)

<font style="color:#117CEE;">去掉环境光亮度和改变相机的渲染模式，不让相机渲染天空盒，构建一个全黑环境</font>

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1788361273683-e5a6c672-a2d4-4566-b6a9-9f1c7b4c6f0b.png)

<font style="color:#117CEE;">遗憾的是，在做了很多努力后，我们仍然没有成功的烘焙。</font>

<font style="color:#117CEE;">【填坑】烘焙变黑的完整修复</font>

<font style="color:#117CEE;">经过排查，烘焙变黑问题是由于多个原因叠加导致，首先就是我的shader的结构问题，我们来依次解决他们</font>

#### 步骤 1：修复 `MyLit.shader `— 删除 HDRP 关键字
**文件路径**：`Assets/Shader/MyLit/MyLit.shader`

找到这段代码（大约第 108–109 行）：

```glsl
// 光照探针SH评估
#pragma multi_compile _ EVALUATE_SH_MIXED EVALUATE_SH_VERTEX
```

**删除这两整行**（注释和 pragma 都要删）。

**<font style="color:rgb(51, 51, 51);">为什么</font>**<font style="color:rgb(51, 51, 51);">：这是 HDRP 的关键字，URP 根本不认。它们只会白白多编译 2 个变体，对烘焙没有任何帮助。</font>

**<font style="color:rgb(51, 51, 51);">修复</font>**<font style="color:rgb(51, 51, 51);">：直接删除这两整行（注释和 pragma 都要删）。</font>

#### 步骤2：修复 `MyLit.shader` — 修正 include 拼写
**文件路径**：`Assets/Shader/MyLit/MyLit.shader`

在 DepthNormals Pass 中，找到（大约第 198 行）：

```glsl
#include "MyLitDepthNormalsPass.hlsl"
```

确认文件名拼写正确。你的项目里已经是 `MyLitDepthNormalsPass.hlsl`（正确），但修复目录里原来的注释说这里是 `MyLitDepthNormalPass.hlsl`（少一个 s）。检查一下你的文件，如果是错的，改成：

```glsl
#include "MyLitDepthNormalsPass.hlsl"
```

> 根据我读到的内容，你的项目里已经是正确的拼写，所以这一步可能不需要改。但请确认一下。
>

**<font style="color:rgb(51, 51, 51);">为什么</font>**<font style="color:rgb(51, 51, 51);">：如果文件名拼写错误（如 </font>`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">MyLitDepthNormalPass.hlsl</font>`<font style="color:rgb(51, 51, 51);"> 少了一个 s），include 失败会导致整个 Shader 编译不过。</font>

**<font style="color:rgb(51, 51, 51);">修复</font>**<font style="color:rgb(51, 51, 51);">：确认拼写为 </font>`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">MyLitDepthNormalsPass.hlsl</font>`<font style="color:rgb(51, 51, 51);">（正确）。如果已经是正确的则无需修改。</font>

---

#### 步骤 3：修复 `MyLitDepthOnlyPass.hlsl` — 整个文件重写
**文件路径**：`Assets/Shader/MyLit/MyLitDepthOnlyPass.hlsl`

如果没有则创建，全部内容替换为：

这个是依赖深度 Pass 的功能（SSAO、深度渲染等）

```glsl
#ifndef MY_LIT_DEPTH_ONLY_PASS_INCLUDED
#define MY_LIT_DEPTH_ONLY_PASS_INCLUDED

// 原文件是空文件（0 字节），导致 Shader 整体编译失败
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "MyLitCommon.hlsl"

struct Attributes
{
  float4 positionOS : POSITION;
  float2 uv         : TEXCOORD0;
};

struct Varyings
{
  float4 positionCS : SV_POSITION;
  float2 uv         : TEXCOORD0;
};

Varyings DepthOnlyVertex(Attributes input)
{
  Varyings output = (Varyings)0;
  output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
  output.uv = TRANSFORM_TEX(input.uv, _ColorMap);
  return output;
}

half4 DepthOnlyFragment(Varyings input) : SV_TARGET
{
  #ifdef _ALPHA_CUTOUT
  float2 uv = input.uv;
  float4 colorSample = SAMPLE_TEXTURE2D(_ColorMap, sampler_ColorMap, uv);
  // 与 ShadowCaster / ForwardLit 保持一致的镂空
  colorSample.a = CalculateDotMatrix(uv, _DotDensity, _DotRadius,
                                       float2(_DotScaleX, _DotScaleY));
  TestAlphaClip(colorSample);
  #endif
  return 0;
}

#endif
```

---

#### 步骤 4：修复 `MyLitDepthNormalsPass.hlsl` — 整个文件重写
**文件路径**：`Assets/Shader/MyLit/MyLitDepthNormalsPass.hlsl`

**<font style="color:rgb(51, 51, 51);">为什么</font>**<font style="color:rgb(51, 51, 51);">：原文件是残缺片段，缺少 include guard、#include、结构体定义，导致编译失败。当时是准备借用一部分自带的头文件的，发现不行，则全部重写吧</font>

如果没有则创建，全部内容替换为：

```glsl
#ifndef MY_LIT_DEPTH_NORMALS_PASS_INCLUDED
#define MY_LIT_DEPTH_NORMALS_PASS_INCLUDED

// 原文件缺少 include guard、include 与结构体定义
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "MyLitCommon.hlsl"

struct Attributes
{
  float4 positionOS : POSITION;
  float3 normalOS   : NORMAL;
  float4 tangentOS  : TANGENT;
  float2 uv         : TEXCOORD0;
};

struct Varyings
{
  float4 positionCS : SV_POSITION;
  float2 uv         : TEXCOORD0;
  float3 normalWS   : TEXCOORD1;
  #ifdef _NORMALMAP
  float4 tangentWS  : TEXCOORD2;
  #endif
};

Varyings DepthNormalsVertex(Attributes input)
{
  Varyings output = (Varyings)0;

  VertexNormalInputs normalInput =
    GetVertexNormalInputs(input.normalOS, input.tangentOS);

  output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
  output.uv = TRANSFORM_TEX(input.uv, _ColorMap);
  output.normalWS = normalInput.normalWS;

  #ifdef _NORMALMAP
  // GetOddNegativeScale 处理负缩放翻转，不能省
  real sign = input.tangentOS.w * GetOddNegativeScale();
  output.tangentWS = half4(normalInput.tangentWS.xyz, sign);
  #endif

  return output;
}

half4 DepthNormalsFragment(Varyings input) : SV_TARGET
{
  #ifdef _NORMALMAP
  half3 normalTS = UnpackNormalScale(
    SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, input.uv),
    _NormalStrength);

  // 顺序必须是 tangent / bitangent / normal
  half sgn = input.tangentWS.w;
  half3 bitangent = sgn * cross(input.normalWS.xyz, input.tangentWS.xyz);
  half3 normalWS = TransformTangentToWorld(
    normalTS,
    half3x3(input.tangentWS.xyz, bitangent, input.normalWS.xyz));
  #else
  half3 normalWS = input.normalWS;
  #endif

  #ifdef _ALPHA_CUTOUT
  half alpha = CalculateDotMatrix(input.uv, _DotDensity, _DotRadius,
                                    float2(_DotScaleX, _DotScaleY));
  clip(alpha - _Cutoff);
  #endif

  // 法线必须归一化，否则 SSAO 会出现错误遮挡
  return half4(NormalizeNormalPerPixel(normalWS), 0.0);
}

#endif
```

---

#### 步骤 5：修复 `MyLitForwardLitPass.hlsl` — 4 处修改
**文件路径**：`Assets/Shader/MyLit/MyLitForwardLitPass.hlsl`

##### 5.1 在 Interpolators 结构体中新增 `vertexSH` 字段
**<font style="color:rgb(51, 51, 51);">为什么</font>**<font style="color:rgb(51, 51, 51);">：后续 SH 兜底需要在顶点阶段采样球谐函数并传递给片元。没有这个字段，球谐数据无法从顶点传到片元。</font>

找到（大约第 21–31 行）：

```glsl
struct Interpolators {
  float4 positionCS : SV_POSITION;
  float2 uv : TEXCOORD0;
  float2 uv2 : TEXCOORD1;
  float3 positionWS : TEXCOORD2;
  float3 normalWS : TEXCOORD3;
  float4 tangentWS : TEXCOORD4;

};
```

在 `tangentWS` 后面加一行，改为：

```glsl
struct Interpolators {
  float4 positionCS : SV_POSITION;
  float2 uv : TEXCOORD0;
  float2 uv2 : TEXCOORD1;
  float3 positionWS : TEXCOORD2;
  float3 normalWS : TEXCOORD3;
  float4 tangentWS : TEXCOORD4;
  half3 vertexSH : TEXCOORD5;   // 修复：无光照贴图时用球谐函数兜底
};
```

##### 5.2 在 Vertex 函数中新增 SH 采样
**<font style="color:rgb(51, 51, 51);">为什么</font>**<font style="color:rgb(51, 51, 51);">：</font>`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">SampleSHVertex</font>`<font style="color:rgb(51, 51, 51);"> 需要在顶点阶段计算球谐系数，然后插值到片元供 </font>`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">SampleSHPixel</font>`<font style="color:rgb(51, 51, 51);"> 使用。没有这行，光照探针对象无法获得间接光。</font>

找到 Vertex 函数末尾（大约第 68–70 行）：

```glsl
output.positionWS = posnInputs.positionWS;

return output;
```

在 `return output;` 之前插入一行：

```glsl
output.positionWS = posnInputs.positionWS;

// 修复：没有 LIGHTMAP_ON 时（光照探针 / lightmap 被剥离）靠 SH 提供间接光
output.vertexSH = SampleSHVertex(normInput.normalWS);

return output;
```

##### 5.3 把 `CalculateDotMatrix` 移到 `TestAlphaClip` 之前
找到（大约第 107–110 行）`CalculateDotMatrix`要移动到`TestAlphaClip(colorSample);`之前

**<font style="color:rgb(51, 51, 51);">为什么</font>**<font style="color:rgb(51, 51, 51);">：</font>`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">CalculateDotMatrix</font>`<font style="color:rgb(51, 51, 51);"> 对 </font>`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">colorSample.a</font>`<font style="color:rgb(51, 51, 51);"> 的赋值在 </font>`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">TestAlphaClip</font>`**<font style="color:rgb(51, 51, 51);">之后</font>**<font style="color:rgb(51, 51, 51);">，导致赋值根本没生效——clip 用的还是纹理原始 alpha，像素已经被丢弃了，程序化点阵镂空完全没作用。另外原始代码用的是 </font>`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">input.uv</font>`<font style="color:rgb(51, 51, 51);">（原始 UV），而不是经过 </font>`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">ParallaxMapping</font>`<font style="color:rgb(51, 51, 51);"> 偏移后的 </font>`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">uv</font>`<font style="color:rgb(51, 51, 51);">。</font>

```glsl
// -------程序化点阵镂空-------
colorSample.a = CalculateDotMatrix(input.uv, _DotDensity, _DotRadius, float2(_DotScaleX, _DotScaleY));

TestAlphaClip(colorSample);
```

`<font style="color:rgb(51, 51, 51);">CalculateDotMatrix</font>`<font style="color:rgb(51, 51, 51);"> 在 </font>`<font style="color:rgb(51, 51, 51);">TestAlphaClip</font>`<font style="color:rgb(51, 51, 51);"> 之后，导致镂空没生效。交换它们的位置，改为：</font>

```glsl
// 修复：原来这一行在 TestAlphaClip 之后，导致程序化点阵镂空完全没生效
colorSample.a = CalculateDotMatrix(input.uv, _DotDensity, _DotRadius,
                                       float2(_DotScaleX, _DotScaleY));

// 括号内的值小于0，直接把这个像素丢弃
TestAlphaClip(colorSample);
```

还有一个问题，原始文件中 `CalculateDotMatrix` 用的是 `input.uv`（<font style="background-color:#C1E77E;">原始 UV</font>），而不是经过 `ParallaxMapping` 偏移后的 `uv`。修复版改用<font style="background-color:#C1E77E;">偏移后的 </font>`<font style="background-color:#C1E77E;">uv</font>`：

所以把第 108 行从 `input.uv` 改为 `uv`：

```glsl
colorSample.a = CalculateDotMatrix(uv, _DotDensity, _DotRadius,
                                       float2(_DotScaleX, _DotScaleY));
```

#####  5.4 给 `SampleLightmap` 补 SH 兜底
**<font style="color:rgb(51, 51, 51);">为什么</font>**<font style="color:rgb(51, 51, 51);">：当物体没有被烘焙到光照贴图时（例如使用光照探针的动态物体），</font>`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">LIGHTMAP_ON</font>`<font style="color:rgb(51, 51, 51);"> 关键字未定义，</font>`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">SampleLightmap</font>`<font style="color:rgb(51, 51, 51);"> 宏展开后直接返回 </font>`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">float3(0, 0, 0)</font>`<font style="color:rgb(51, 51, 51);">，导致物体整体变黑。这是"关掉主光源后场景全黑"的元凶之一。</font>

找到（大约第 140 行）：

```glsl
lightingInput.bakedGI = SampleLightmap(input.uv2, normalWS);
```

替换为：

```glsl
// 修复：原来无条件调用 SampleLightmap，它在 LIGHTMAP_ON 未定义时直接返回 0，
//       导致使用光照探针的对象整体变黑。这里补了 SH 兜底。
#ifdef LIGHTMAP_ON
lightingInput.bakedGI = SampleLightmap(input.uv2, normalWS);
#else
lightingInput.bakedGI = SampleSHPixel(input.vertexSH, normalWS);
#endif
```

---

#### 步骤 6：修复 `MyLitMetaPass.hlsl` — 2 处修改
**文件路径**：`Assets/Shader/MyLit/MyLitMetaPass.hlsl`

##### 6.1 Vertex 函数中做 `TRANSFORM_TEX`
**<font style="color:rgb(51, 51, 51);">为什么</font>**<font style="color:rgb(51, 51, 51);">：光照烘焙器在烘焙时需要知道每个表面的反照率（albedo）和自发光（emission），这些数据通过 </font>**<font style="color:rgb(51, 51, 51);">Meta Pass</font>**<font style="color:rgb(51, 51, 51);">（</font>`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">LightMode = Meta</font>`<font style="color:rgb(51, 51, 51);">）来获取。如果 Vertex 中不做 </font>`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">TRANSFORM_TEX</font>`<font style="color:rgb(51, 51, 51);">，UV 的平铺/偏移就没有被应用，采样位置是错的。</font>

找到（大约第 25–30 行）：

```glsl
Varyings Vertex(Attributes input){
  Varyings output = (Varyings)0;
  output.positionCS = UnityMetaVertexPosition(input.positionOS.xyz, input.uv1, input.uv2);
  // output.uv = TRANSFORM_TEX(input.uv0, _ColorMap);
  return output;
}
```

把注释掉的那行取消注释，改为：

```glsl
Varyings Vertex(Attributes input){
  Varyings output = (Varyings)0;

  // 三参数重载内部会转发到五参数版（使用 unity_LightmapST / unity_DynamicLightmapST），
  // core 的 MetaPass.hlsl 两个重载都有，所以这样写是安全的。
  // 注意：这里必须传 uv1 / uv2（第二、三套 UV），不能传 uv0。
  output.positionCS = UnityMetaVertexPosition(input.positionOS.xyz,
                                                input.uv1, input.uv2);

  // TRANSFORM_TEX 只在这里做一次，片元里直接用
  output.uv = TRANSFORM_TEX(input.uv0, _ColorMap);
  return output;
}
```

#### 6.2 Fragment 中删除重复的 `TRANSFORM_TEX`，并补镂空
**<font style="color:rgb(51, 51, 51);">为什么</font>**<font style="color:rgb(51, 51, 51);">：片元里又做了一次 </font>`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">TRANSFORM_TEX</font>`<font style="color:rgb(51, 51, 51);">，导致平铺/偏移被应用两次（顶点一次 + 片元一次），UV 完全错乱。另外 Meta Pass 完全没有镂空逻辑，烘焙出来的 GI 和 ShadowCaster 的阴影对不上（阴影有洞、GI 没洞）。</font>

找到（大约第 33–46 行）：

```glsl
float4 Fragment(Varyings input) : SV_TARGET{
  // 1. 采样反照率（和ForwardLit里一样用TRANSFORM_TEX处理UV平铺）
  float2 uv = TRANSFORM_TEX(input.uv, _ColorMap);
  float3 albedo = SAMPLE_TEXTURE2D(_ColorMap, sampler_ColorMap, uv).rgb * _ColorTint.rgb;

  // 2. 采样自发光
  float3 emission = SAMPLE_TEXTURE2D(_EmissionMap, sampler_EmissionMap, uv).rgb * _EmissionTint.rgb;

  // 3. 填UnityMetaInput，传给内置的UnityMetaFragment
  UnityMetaInput metaInput;
  metaInput.Albedo = albedo;
  metaInput.Emission = emission;

  return UnityMetaFragment(metaInput);
}
```

替换为：

```glsl
float4 Fragment(Varyings input) : SV_TARGET
{
  // 修复：原来片元里又做了一次 TRANSFORM_TEX，导致平铺/偏移被应用两次
  float2 uv = input.uv;

  float4 colorSample = SAMPLE_TEXTURE2D(_ColorMap, sampler_ColorMap, uv) * _ColorTint;

  // 修复：原来 Meta Pass 完全没做镂空，与 ShadowCaster 的阴影对不上
  #ifdef _ALPHA_CUTOUT
  colorSample.a = CalculateDotMatrix(uv, _DotDensity, _DotRadius,
                                       float2(_DotScaleX, _DotScaleY));
  TestAlphaClip(colorSample);
  #endif

  float3 emission = SAMPLE_TEXTURE2D(_EmissionMap, sampler_EmissionMap, uv).rgb
    * _EmissionTint.rgb;

  UnityMetaInput metaInput;
  metaInput.Albedo   = colorSample.rgb;
  metaInput.Emission = emission;

  return UnityMetaFragment(metaInput);
}
```

---

#### 步骤 7：修复 `MyLitCustomInspector.cs` — 新增自发光 GI
**文件路径**：`Assets/Editor/MyLitCustomInspector.cs`

在 `UpdateSurfaceType` 方法的**末尾**（最后一行 `}` 之前），在最后一段 faceRenderingMode 逻辑之后，插入自发光 GI 代码。

**<font style="color:rgb(51, 51, 51);">为什么</font>**<font style="color:rgb(51, 51, 51);">：</font>`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">_EMISSION</font>`<font style="color:rgb(51, 51, 51);"> 是 </font>`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">shader_feature_local_fragment</font>`<font style="color:rgb(51, 51, 51);"> 关键字，必须手动 Enable 才能激活自发光变体。同时，</font>`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">globalIlluminationFlags</font>`<font style="color:rgb(51, 51, 51);"> 不设置的话，自发光也不会参与光照烘焙。原代码这两项都没有处理，导致自发光材质在烘焙后完全不发光。</font>

找到（大约第 221–228 行）：

```glsl
if(faceRenderingMode == FaceRenderingMode.DoubleSided)
{
  material.EnableKeyword("_DOUBLE_SIDED_NORMALS");
}
else
{
  material.DisableKeyword("_DOUBLE_SIDED_NORMALS");
}
}
```

在闭合括号 `}` 之前插入：

```glsl
if(faceRenderingMode == FaceRenderingMode.DoubleSided)
{
  material.EnableKeyword("_DOUBLE_SIDED_NORMALS");
}
else
{
  material.DisableKeyword("_DOUBLE_SIDED_NORMALS");
}

// ============ 新增：自发光 GI ============
// _EMISSION 是 shader_feature_local_fragment，没有人 Enable 就永远走不到自发光变体。
// globalIlluminationFlags 不设置的话，自发光也不会参与光照烘焙。
bool hasEmission = material.GetTexture("_EmissionMap") != null
  || material.GetColor("_EmissionTint") != Color.black;

CoreUtils.SetKeyword(material, "_EMISSION", hasEmission);

material.globalIlluminationFlags = hasEmission
  ? MaterialGlobalIlluminationFlags.BakedEmissive
  : MaterialGlobalIlluminationFlags.EmissiveIsBlack;
}
```

---

在原来的代码中，还发现一个问题，occlusion 被清零导致烘焙光被整个乘没

**<font style="color:rgb(51, 51, 51);">文件路径</font>**<font style="color:rgb(51, 51, 51);">：</font>`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">Assets/Shader/MyLit/MyLitForwardLitPass.hlsl</font>`

**<font style="color:rgb(51, 51, 51);">为什么</font>**<font style="color:rgb(51, 51, 51);">：在 </font>`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">MyLitForwardLitPass.hlsl</font>`<font style="color:rgb(51, 51, 51);"> 中：</font>

```glsl
SurfaceData surfaceInput = (SurfaceData)0;  // ← occlusion 被清零为 0
surfaceInput.albedo = colorSample.rgb;
surfaceInput.alpha = colorSample.a * _ColorTint.a;
// 后面所有字段都赋了值，唯独漏了 occlusion
```

<font style="color:rgb(51, 51, 51);">URP 的 </font>`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">Lighting.hlsl</font>`<font style="color:rgb(51, 51, 51);"> → </font>`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">GlobalIllumination()</font>`<font style="color:rgb(51, 51, 51);"> 函数内部：</font>

half3 indirectDiffuse = bakedGI * occlusion;  // 0 × bakedGI = 0

<font style="color:rgb(51, 51, 51);">因为 </font>`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">occlusion</font>`<font style="color:rgb(51, 51, 51);"> 只作用于间接光，所以实时灯照着时看得见模型，一切 Baked 就全黑——烘焙出来的间接光被 0 乘没了。</font>

**<font style="color:rgb(51, 51, 51);">修复</font>**<font style="color:rgb(51, 51, 51);">：在 </font>`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">SurfaceData</font>`<font style="color:rgb(51, 51, 51);"> 初始化后，如果没有 AO 贴图就填 1：</font>

```plain
SurfaceData surfaceInput = (SurfaceData)0;
surfaceInput.occlusion = 1.0;  // ← 没有 AO 贴图时必须设为 1
surfaceInput.albedo = colorSample.rgb;
surfaceInput.alpha = colorSample.a * _ColorTint.a;
```

---

改完后回到 Unity，Console 应该不再有 Shader 编译错误。然后去 Lighting 窗口 Clean GI Cache → Generate Lighting，确认烘焙不再变黑。

#### 开始烘焙测试
新建一个红色的主光，关闭其他灯光，物体被标记为Static后，烘焙后应该出现阴影，如未出现阴影，检查控制阴影的脚本是否正确挂载

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1788420717198-784995a7-4842-4434-a390-e06766d59f62.png)<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1788412650301-da00282f-c671-4875-b51e-67a6446e7041.png)

此时你可以使用帧调试器进行检查，是否正常渲染阴影以及我们添加的其他信息是否正常。这里我将天空盒设置为固定的黑色，确保整个环境无其他光干扰。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1788420955778-a72bda9a-c82f-4993-b7ed-c6f799802741.png)

尝试不同的烘焙模式，你可以选择不同的颜色来方便的观察你是否跑通了烘焙效果。烘焙成功后，关闭灯光，物体应仍具有光照效果，但移动物体或光源，物体的光照效果不随着移动位置而改变

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1788413270345-1cdbb05b-dcda-4916-8db0-f6cf379045ce.png)

注意：SkinnedMeshRenderer 不参与 lightmap 烘焙，Baked 灯的直接光只写进 lightmap，<font style="background-color:#C1E77E;">永远照不到角色身上</font>——勾 Static 也没用，这是 Unity 的<font style="background-color:#C1E77E;">架构限制</font>。

选择mixed模式是可以把光打到角色脸上的

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1788416783017-f7f4a19c-cc24-4c4c-8c4e-a28ef5f404c8.png)

---

## <font style="color:rgb(51, 51, 51);">三、遮挡贴图</font>
```glsl
学习，启动！
既然没啥好玩的了，那就敲点代码来启动吧
开始流淌咯
void StartFunction(StartLearn input){
  // 开始学习
  print(
}
```

**<font style="color:rgb(51, 51, 51);">环境光遮挡（Ambient Occlusion）</font>**<font style="color:rgb(51, 51, 51);">模拟了物体缝隙和凹陷处的阴影效果。这些区域接收到的环境光较少，因此看起来更暗。</font>

### <font style="color:rgb(51, 51, 51);">遮挡贴图基础</font>
<font style="color:rgb(51, 51, 51);">遮挡贴图是一张</font><font style="color:rgb(51, 51, 51);background-color:#C1E77E;">灰度纹理</font><font style="color:rgb(51, 51, 51);">，白色表示完全暴露（接收全部环境光），</font><font style="color:rgb(51, 51, 51);background-color:#C1E77E;">黑色</font><font style="color:rgb(51, 51, 51);">表示</font><font style="color:rgb(51, 51, 51);background-color:#C1E77E;">完全遮挡</font><font style="color:rgb(51, 51, 51);">（不接收环境光）。</font>

<font style="color:rgb(51, 51, 51);">遮挡贴图通常存储在纹理的</font><font style="color:rgb(51, 51, 51);background-color:#C1E77E;">某个通道</font><font style="color:rgb(51, 51, 51);">中。在 Unity 的默认 Lit 着色器中，遮挡贴图存储在纹理的</font><font style="color:rgb(51, 51, 51);background-color:#C1E77E;">绿色</font><font style="color:rgb(51, 51, 51);">通道中。</font>

### <font style="color:rgb(51, 51, 51);">遮挡贴图的生成方式</font>
<font style="color:rgb(51, 51, 51);">遮挡贴图通常在 3D 建模软件中烘焙生成：</font>

+ **<font style="color:rgb(51, 51, 51);">Substance Painter</font>**<font style="color:rgb(51, 51, 51);">：在纹理集设置中启用"AO"贴图，烘焙时自动生成</font>
+ **<font style="color:rgb(51, 51, 51);">Maya</font>**<font style="color:rgb(51, 51, 51);">：使用 Transfer Maps 工具，将高模的细节烘焙为 AO 贴图</font>
+ **<font style="color:rgb(51, 51, 51);">Blender</font>**<font style="color:rgb(51, 51, 51);">：在 Bake 面板中选择"Ambient Occlusion"类型进行烘焙</font>

<font style="color:rgb(51, 51, 51);">烘焙时需要注意：</font>

+ **<font style="color:rgb(51, 51, 51);">Max Distance</font>**<font style="color:rgb(51, 51, 51);">：控制 AO 的影响范围，值越大 AO 覆盖范围越广</font>
+ **<font style="color:rgb(51, 51, 51);">Spread</font>**<font style="color:rgb(51, 51, 51);">：控制 AO 从缝隙向外扩散的程度</font>

<font style="color:rgb(162, 127, 3);">【埋坑】少图了，这里不会啊，后面看看怎么在SP中烘焙</font>

_<font style="color:rgb(51, 51, 51);">Substance Painter 中的 AO 烘焙设置</font>_

### <font style="color:rgb(51, 51, 51);">为什么是绿色通道？</font>
<font style="color:rgb(51, 51, 51);">在 Unity 的 PBR 工作流中，遮挡贴图通常存储在绿色通道中。这是因为绿色通道在纹理压缩中通常有更高的精度。</font>

#### <font style="color:rgb(51, 51, 51);">纹理压缩格式中的通道精度</font>
<font style="color:rgb(51, 51, 51);">不同的纹理压缩格式对各通道的精度分配不同：</font>

+ **<font style="color:rgb(51, 51, 51);">BC5（3Dc）</font>**<font style="color:rgb(51, 51, 51);">：用于法线贴图，R 和 G 通道各 8 bit，B 通道通过 R×G 重建</font>
+ **<font style="color:rgb(51, 51, 51);">DXT5</font>**<font style="color:rgb(51, 51, 51);">：用于带 Alpha 的纹理，R、B、B 各 5/6/5 bit，但 </font><font style="color:rgb(51, 51, 51);background-color:#C1E77E;">Alpha</font><font style="color:rgb(51, 51, 51);"> 通道使用 </font><font style="color:rgb(51, 51, 51);background-color:#C1E77E;">8 bit 独立压缩</font>
+ **<font style="color:rgb(51, 51, 51);">BC7</font>**<font style="color:rgb(51, 51, 51);">：现代格式，各通道精度均匀</font>

<font style="color:rgb(51, 51, 51);">在传统的 DXT5 压缩中，绿色通道使用 6 bit（红色和蓝色各 5 bit），因此绿色通道的</font><font style="color:rgb(51, 51, 51);background-color:#C1E77E;">精度略高</font><font style="color:rgb(51, 51, 51);">。虽然现代 BC7 格式已经解决了这个问题，但 Unity 仍然沿用绿色通道作为遮挡贴图的惯例。</font>

<font style="color:rgb(51, 51, 51);">此外，绿色通道在视觉上对</font><font style="color:rgb(51, 51, 51);background-color:#C1E77E;">人眼最敏感</font><font style="color:rgb(51, 51, 51);">，轻微的精度损失在绿色通道中更不容易被察觉。</font>

<font style="color:#117CEE;">这就是16bit色深的来源</font>

<font style="color:#117CEE;">BC7给RGB三个通道的精度是均匀且平等的，现在还放绿色通道是因为行业惯性</font>

<font style="color:#117CEE;">向后兼容、导出预设惯性、压缩伪影的一致性</font>

<font style="color:#117CEE;">真正拉开差距的是BC7拥有不同的压缩模式，根据纹理内容智能切换模式</font>

+ <font style="color:#117CEE;">模式0-3：专门针对无Alpha的RGB优化</font>
+ <font style="color:#117CEE;">模式4-5：专门针对RGBA优化</font>
+ <font style="color:#117CEE;">模式6-7：专门针对单纯的双色阶或如同UI图标这类极简色块优化</font>

<font style="color:#117CEE;">如果项目要兼顾移动端（使用ETC2/ASTC）或旧格式，那么继续沿用绿色通道存AO的惯例依然是兼容性最好的设置</font>

### <font style="color:rgb(51, 51, 51);">遮挡在 PBR 中的作用</font>
<font style="color:rgb(51, 51, 51);">环境光遮挡（ao）在 PBR 光照模型中影响两个部分：</font>

1. **<font style="color:rgb(51, 51, 51);">漫反射环境光（Diffuse GI）</font>**<font style="color:rgb(51, 51, 51);">：</font>`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">ao</font>`<font style="color:rgb(51, 51, 51);"> 直接乘以烘焙或探针提供的间接漫反射光照</font>
2. **<font style="color:rgb(51, 51, 51);">镜面反射环境光（Specular GI）</font>**<font style="color:rgb(51, 51, 51);">：</font>`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">ao</font>`<font style="color:rgb(51, 51, 51);"> 也会影响反射探针的采样结果，粗糙表面的反射受 AO 影响更大</font>

<font style="color:rgb(51, 51, 51);">在 </font>`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">UniversalFragmentPBR</font>`<font style="color:rgb(51, 51, 51);"> 中，</font>`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">SurfaceData.occlusion</font>`<font style="color:rgb(51, 51, 51);"> 会被用于：</font>

```glsl
// 简化版 PBR 中的 AO 应用
diffuseGI *= occlusion;
specularGI *= lerp(1, occlusion, roughness * roughness);
```

<font style="color:rgb(51, 51, 51);">注意：镜面反射的 AO 影响通常通过粗糙度进行调制——越粗糙的表面，AO 对反射的影响越大。</font>

#### <font style="color:rgb(51, 51, 51);">Metallic vs Specular Workflow 中的 AO 应用</font>
<font style="color:rgb(51, 51, 51);">在 </font>**<font style="color:rgb(51, 51, 51);">Metallic Workflow</font>**<font style="color:rgb(51, 51, 51);"> 中，AO 同时影响</font><font style="color:rgb(51, 51, 51);background-color:#C1E77E;">漫反射</font><font style="color:rgb(51, 51, 51);">和</font><font style="color:rgb(51, 51, 51);background-color:#C1E77E;">镜面反射</font><font style="color:rgb(51, 51, 51);">的间接光照。</font>

<font style="color:rgb(51, 51, 51);">在 </font>**<font style="color:rgb(51, 51, 51);">Specular Workflow</font>**<font style="color:rgb(51, 51, 51);"> 中，AO 的应用方式相同，但镜面反射的颜色由 Specular Color 定义而非 Albedo。</font>

<font style="color:rgb(51, 51, 51);">两种工作流中 AO 的计算逻辑完全一致，只是镜面反射的颜色来源不同。</font>

<font style="color:#117CEE;">这不就是AO图吗，然后PBR基础里有讲，就是个遮罩而已</font>

<font style="color:#117CEE;">反射的颜色由albedo提供，Metallic Roughness工作流，一版我们游戏里面就用这个，Specular Glossiness(高光/光泽度)一般用于离线渲染</font>

### <font style="color:rgb(51, 51, 51);">遮挡强度的实际应用场景</font>
`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">_OcclusionStrength</font>`<font style="color:rgb(51, 51, 51);"> 属性允许美术调整遮挡效果的强度。值为 0 时完全禁用遮挡，值为 1 时使用完整的遮挡贴图数据。</font>

**<font style="color:rgb(51, 51, 51);">为什么需要调整强度？</font>**

+ **<font style="color:rgb(51, 51, 51);">风格化项目</font>**<font style="color:rgb(51, 51, 51);">：可能需要减弱 AO 以获得更平面的卡通风格</font>
+ **<font style="color:rgb(51, 51, 51);">过暗的场景</font>**<font style="color:rgb(51, 51, 51);">：如果 AO 导致场景过暗，可以适当降低强度</font>
+ **<font style="color:rgb(51, 51, 51);">特定材质</font>**<font style="color:rgb(51, 51, 51);">：某些材质（如皮肤）可能需要自定义的 AO 强度</font>

### <font style="color:rgb(51, 51, 51);">遮挡贴图与 SSAO 的关系和区别</font>
| **<font style="color:rgb(51, 51, 51);">特性</font>** | **<font style="color:rgb(51, 51, 51);">遮挡贴图（Texture AO）</font>** | **<font style="color:rgb(51, 51, 51);">屏幕空间 AO（SSAO）</font>** |
| :--- | :--- | :--- |
| <font style="color:rgb(51, 51, 51);">数据来源</font> | <font style="color:rgb(51, 51, 51);">预烘焙的纹理</font> | <font style="color:rgb(51, 51, 51);">实时深度缓冲</font> |
| <font style="color:rgb(51, 51, 51);">性能成本</font> | <font style="color:rgb(51, 51, 51);">极低（纹理采样）</font> | <font style="color:rgb(51, 51, 51);">中等（屏幕空间计算）</font> |
| <font style="color:rgb(51, 51, 51);">覆盖范围</font> | <font style="color:rgb(51, 51, 51);">仅自身遮挡</font> | <font style="color:rgb(51, 51, 51);">物体间遮挡</font> |
| <font style="color:rgb(51, 51, 51);">动态物体</font> | <font style="color:rgb(51, 51, 51);">不支持</font> | <font style="color:rgb(51, 51, 51);">支持</font> |
| <font style="color:rgb(51, 51, 51);">精度</font> | <font style="color:rgb(51, 51, 51);">取决于纹理分辨率</font> | <font style="color:rgb(51, 51, 51);">取决于采样数</font> |


<font style="color:rgb(51, 51, 51);">两者可以</font>**<font style="color:rgb(51, 51, 51);">共存</font>**<font style="color:rgb(51, 51, 51);">：贴图 AO 提供物体自身的细节遮挡，SSAO 提供物体间的动态遮挡。在 URP 中，SSAO 作为后处理效果实现，与着色器中的贴图 AO 互不冲突。</font>

<font style="color:#117CEE;">一个AO是贴图，另外一个属于后处理特效，是GPU算现场算出来的灰度遮罩，只会在显存里出现</font>

### <font style="color:rgb(51, 51, 51);">代码实现</font>
```glsl
Shader "Custom/MyLit" {
    Properties {
        [Header(Surface options)]
        [MainTexture] _ColorMap("Color", 2D) = "white" {}
        [MainColor] _ColorTint("Tint", Color) = (1, 1, 1, 1)
        _Cutoff("Alpha cutout threshold", Range(0, 1)) = 0.5
        [NoScaleOffset][Normal] _NormalMap("Normal", 2D) = "bump" {}
        _NormalStrength("Normal strength", Range(0, 1)) = 1
        [NoScaleOffset] _MetalnessMask("Metalness mask", 2D) = "white" {}
        _Metalness("Metalness", Range(0, 1)) = 0
        [Toggle(_SPECULAR_SETUP)] _SpecularSetupToggle("Use specular workflow", Float) = 0
        [Toggle(_ROUGHNESS_SETUP)] _RoughnessSetupToggle("Use roughness texture", Float) = 0
        [NoScaleOffset] _SpecularMap("Specular map", 2D) = "white" {}
        _SpecularTint("Specular tint", Color) = (1, 1, 1, 1)
        [NoScaleOffset] _SmoothnessMask("Smoothness mask", 2D) = "white" {}
        _Smoothness("Smoothness", Range(0, 1)) = 0.5
        [NoScaleOffset] _EmissionMap("Emission map", 2D) = "white" {}
        [HDR]_EmissionTint("Emission tint", Color) = (0, 0, 0, 0)
        [NoScaleOffset] _ParallaxMap("Height/displacement map", 2D) = "white" {}
        _ParallaxStrength("Parallax strength", Range(0, 1)) = 0.005
        [NoScaleOffset] _ClearCoatMask("Clear coat mask", 2D) = "white" {}
        _ClearCoatStrength("Clear coat strength", Range(0, 1)) = 0
        [NoScaleOffset] _ClearCoatSmoothnessMask("Clear coat smoothness mask", 2D) = "white" {}
        _ClearCoatSmoothness("Clear coat smoothness", Range(0, 1)) = 0

        // 遮挡贴图
        [Header(Occlusion)]
        [NoScaleOffset] _OcclusionMap("Occlusion", 2D) = "white" {}
        _OcclusionStrength("Occlusion strength", Range(0, 1)) = 1

        ...
    }
    ...
}
```

<font style="color:rgb(51, 51, 51);">在 </font>`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">MyLit.shader</font>`<font style="color:rgb(51, 51, 51);"> 中添加遮挡贴图属性。</font>`<font style="color:rgb(51, 51, 51);background-color:#C1E77E;">_OcclusionMap</font>`<font style="color:rgb(51, 51, 51);">是纹理属性，</font>`<font style="color:rgb(51, 51, 51);background-color:#C1E77E;">_OcclusionStrength</font>`<font style="color:rgb(51, 51, 51);background-color:#C1E77E;"></font><font style="color:rgb(51, 51, 51);">是控制遮挡强度的浮点属性。</font>

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
TEXTURE2D(_OcclusionMap); SAMPLER(sampler_OcclusionMap);

float4 _ColorMap_ST;
float4 _ColorTint;
float _Cutoff;
float _NormalStrength;
float _Metalness;
float4 _SpecularTint;
float _Smoothness;
float3 _EmissionTint;
float _ParallaxStrength;
float _ClearCoatStrength;
float _ClearCoatSmoothness;
float _OcclusionStrength;
...
```

<font style="color:rgb(51, 51, 51);">在 </font>`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">MyLitCommon.hlsl</font>`<font style="color:rgb(51, 51, 51);"> 中声明遮挡贴图和强度属性。</font>

```glsl
float4 Fragment(Interpolators input
    #ifdef _DOUBLE_SIDED_NORMALS
    , FRONT_FACE_TYPE frontFace : FRONT_FACE_SEMANTIC
    #endif
    ) : SV_TARGET {
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
    surfaceInput.smoothness = ...;
    surfaceInput.emission = SAMPLE_TEXTURE2D(_EmissionMap, sampler_EmissionMap, uv).rgb * _EmissionTint;
    // ← 新增：遮挡贴图采样
    surfaceInput.occlusion = SAMPLE_TEXTURE2D(_OcclusionMap, sampler_OcclusionMap, uv).g * _OcclusionStrength;
    ...

    return UniversalFragmentPBR(lightingInput, surfaceInput);
}
```

<font style="color:rgb(51, 51, 51);">在 </font>`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">Fragment</font>`<font style="color:rgb(51, 51, 51);"> 函数中采样遮挡贴图。注意我们使用</font>**绿色通道（.g）**<font style="color:rgb(51, 51, 51);">，这是 Unity 的标准做法。将采样结果与 </font>`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">_OcclusionStrength</font>`<font style="color:rgb(51, 51, 51);"> 相乘，并设置到 </font>`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">SurfaceData</font>`<font style="color:rgb(51, 51, 51);"> 的 </font>`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">occlusion</font>`<font style="color:rgb(51, 51, 51);"> 字段中。</font>

为什么是绿色通道？在 Unity 的 PBR 工作流中，遮挡贴图通常存储在绿色通道中。这是因为绿色通道在纹理压缩中<font style="background-color:#C1E77E;">通常有</font>更高的精度。

<font style="color:#117CEE;">前面提到了为啥是通常有嘛，自己去看</font>

### <font style="color:rgb(51, 51, 51);">遮挡强度</font>
`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">_OcclusionStrength</font>`<font style="color:rgb(51, 51, 51);"> 属性允许美术调整遮挡效果的强度。值为 0 时完全禁用遮挡，值为 1 时使用完整的遮挡贴图数据。</font>

<font style="color:#117CEE;">看代码，直接乘的是这个，当然是越接近1越强咯，牢记控制的是</font><font style="color:#117CEE;background-color:#C1E77E;">遮挡的强度</font>

### <font style="color:rgb(51, 51, 51);">测试遮挡贴图</font>
<font style="color:rgb(51, 51, 51);">找一张遮挡贴图（或从 Substance Painter 等软件导出），应用到材质上。你应该能看到：</font>

+ <font style="color:rgb(51, 51, 51);">缝隙和凹陷处变暗</font>
+ <font style="color:rgb(51, 51, 51);">暴露的表面保持明亮</font>
+ <font style="color:rgb(51, 51, 51);">遮挡强度滑块可以调整效果</font>

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1788659230484-4af74864-83d2-40c8-b5f3-5d4c580b3e11.png)<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1788659244772-61f29bab-2017-4b36-8f6e-b6247d9ed732.png)

_<font style="color:rgb(51, 51, 51);">左侧无遮挡贴图，右侧有遮挡贴图。注意缝隙处的阴影细节</font>_

<font style="color:#117CEE;">小复习</font>

<font style="color:#117CEE;">lerp函数，lerp是Linear intERPolation（线性插值 ）的缩写，名字取的很直白：在两个值之间按一定比例取中间值</font>

```glsl
lerp(a, b, t) = a + (b - a) * t
             = a * (1 - t) + b * t
```

<font style="color:#117CEE;">t 是"往 b 靠的程度"。t=1 就完全变成 b。</font>

<font style="color:#117CEE;">起始值怎么设置呢？遵循一个原则，"</font>**<font style="color:#117CEE;">起点 = 效果的无效值</font>**<font style="color:#117CEE;">"，所以代码这里</font>

```glsl
lerp(1.0, ao, _OcclusionStrength)
```

<font style="color:#117CEE;">AO是乘在光照上的，遮蔽是把光照变暗，所以“完全不生效”的默认值是1.0，给定一个强度然后往ao上靠，按照这个思路，类似的</font>

```glsl
lerp(1.0, ao,        _OcclusionStrength);  // 遮蔽：乘法 → 起点 1
lerp(1.0, tintColor, _TintStrength);       // 染色：乘法 → 起点 1
lerp(0.0, rimColor,  _RimStrength);        // 边缘光：加法 → 起点 0
lerp(baseColor, emissionColor, _MixRatio); // 两色混合 → 起点是原色
```

### <font style="color:rgb(51, 51, 51);">实际项目修改</font>
**<font style="color:rgb(51, 51, 51);">MyLit.shader</font>**<font style="color:rgb(51, 51, 51);"> — 在 Properties 中添加遮挡贴图属性：</font>

```glsl
// 在 MyLit.shader 的 Properties 块中
// 位于 _ClearCoatSmoothness 属性之后添加

[Header(Occlusion)]
[NoScaleOffset] _OcclusionMap("Occlusion", 2D) = "white" {}
_OcclusionStrength("Occlusion strength", Range(0, 1)) = 1
```

**<font style="color:rgb(51, 51, 51);">MyLitCommon.hlsl</font>**<font style="color:rgb(51, 51, 51);"> — 在 CBUFFER 中添加纹理声明：</font>

```glsl
// 在 MyLitCommon.hlsl 的 CBUFFER(UnityPerMaterial) 中
// 位于其他 TEXTURE2D 声明之后添加
TEXTURE2D(_OcclusionMap); SAMPLER(sampler_OcclusionMap);
```

**<font style="color:rgb(51, 51, 51);">MyLitCommon.hlsl</font>**<font style="color:rgb(51, 51, 51);"> — 添加强度变量：</font>

```glsl
// 在 CBUFFER 中，位于其他变量之后添加
float _OcclusionStrength;
```

**<font style="color:rgb(51, 51, 51);">MyLitForwardLitPass.hlsl</font>**<font style="color:rgb(51, 51, 51);"> — 修改 Fragment 函数：</font>

```glsl
// 在 Fragment 函数中，设置 surfaceInput.emission 之后添加
surfaceInput.occlusion = SAMPLE_TEXTURE2D(_OcclusionMap, sampler_OcclusionMap, uv).g * _OcclusionStrength;
```

---

## <font style="color:rgb(51, 51, 51);">四、反射探针</font>
**<font style="color:rgb(51, 51, 51);">问题</font>**<font style="color:rgb(51, 51, 51);">：Unity 默认用一张天空盒（Skybox）给全场景所有物体提供反射。天空盒假设全世界处于同一个「无限远的环境」中。于是你在室内放一个金属球，天花板和墙明明把天空挡住了，</font><font style="color:rgb(51, 51, 51);background-color:#C1E77E;">球上却反射出外面的蓝天</font><font style="color:rgb(51, 51, 51);">——</font>**<font style="color:rgb(51, 51, 51);">穿帮</font>**<font style="color:rgb(51, 51, 51);">。</font>

**<font style="color:rgb(51, 51, 51);">方案</font>**<font style="color:rgb(51, 51, 51);">：反射探针（Reflection Probe）。在场景某点架一台 360° 相机拍一张全景快照（Cubemap），让附近的物体改用这张。</font>

**<font style="color:rgb(51, 51, 51);">一句话概括本节</font>**<font style="color:rgb(51, 51, 51);">：</font>

> <font style="color:#000000;">探针解决「反射内容不对」，盒投影解决「反射位置不对」，粗糙度决定「反射清不清晰」，金属度决定「反射带不带颜色」。而你写的 Shader，只需要保留两个关键字，其余全交给 </font>`<font style="color:#000000;background-color:rgb(243, 244, 244);">UniversalFragmentPBR</font>`<font style="color:#000000;">。</font>  
 
>

**反射探针（Reflection Probes）**<font style="color:rgb(51, 51, 51);">允许物体反射周围环境。它们通过在特定位置渲染场景</font><font style="color:rgb(51, 51, 51);background-color:#C1E77E;">立方体贴图</font><font style="color:rgb(51, 51, 51);">来实现反射效果。</font>

<font style="color:#117CEE;">立方体贴图？第一次见哦，之前听说过，注意一下啦</font>

<font style="color:#117CEE;">就是在点P照一张360°的全景照，给定一个区域，让其替代天空盒作为反射的来源</font>

### <font style="color:rgb(51, 51, 51);">反射探针基础</font>
<font style="color:rgb(51, 51, 51);">反射探针会渲染场景到一个立方体贴图（Cubemap）中。在运行时，着色器根据表面的法线和视角方向，从立方体贴图中采样反射颜色。</font>

<font style="color:rgb(51, 51, 51);">URP 的反射系统会自动处理大部分工作。我们只需要确保 </font>`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">SurfaceData</font>`<font style="color:rgb(51, 51, 51);"> 中的数据正确即可。</font>

<font style="color:#117CEE;">立方体贴图可以用来制作天空盒</font>

<font style="color:#117CEE;">标准UV贴图用2个值来定位平面内的一个颜色，那如果我用6个面包围出一个立方体呢</font>

<font style="color:#117CEE;">视方向和法线方向确定，可以得到反射向量，反射向量打到这个立方体上，戳到了哪个像素就取哪个颜色。虽然是6张2D图拼接而成的，但是传入的向量必然是3D向量，所以也被称为立方体贴图</font>

### <font style="color:rgb(51, 51, 51);">反射探针的三种类型</font>
<font style="color:rgb(51, 51, 51);">URP 中的反射探针有三种类型，在 Inspector 的 </font>**<font style="color:rgb(51, 51, 51);">Mode</font>**<font style="color:rgb(51, 51, 51);"> 中选择：</font>

| **<font style="color:rgb(51, 51, 51);">类型</font>** | **<font style="color:rgb(51, 51, 51);">更新时机</font>** | **<font style="color:rgb(51, 51, 51);">性能影响</font>** | **<font style="color:rgb(51, 51, 51);">适用场景</font>** |
| :--- | :--- | :--- | :--- |
| **<font style="color:rgb(51, 51, 51);">Baked</font>** | <font style="color:rgb(51, 51, 51);">仅在烘焙时渲染一次</font> | <font style="color:rgb(51, 51, 51);">无运行时开销</font> | <font style="color:rgb(51, 51, 51);">静态场景</font> |
| **<font style="color:rgb(51, 51, 51);">Realtime</font>** | <font style="color:rgb(51, 51, 51);">每帧或按设定频率更新</font> | <font style="color:rgb(51, 51, 51);">高（每帧渲染6个面）</font> | <font style="color:rgb(51, 51, 51);">动态场景</font> |
| **<font style="color:rgb(51, 51, 51);">Custom</font>** | <font style="color:rgb(51, 51, 51);">通过脚本手动控制</font> | <font style="color:rgb(51, 51, 51);">可控</font> | <font style="color:rgb(51, 51, 51);">特殊需求</font> |


<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1788683434887-8ee8151f-80d0-4a6d-ad3b-7700a6ec07d2.png)

**<font style="color:rgb(51, 51, 51);">Baked</font>**<font style="color:rgb(51, 51, 51);">：在光照烘焙时渲染一次，运行时直接使用。性能最优，但无法反映场景变化。</font>

**<font style="color:rgb(51, 51, 51);">Realtime</font>**<font style="color:rgb(51, 51, 51);">：每帧（或按设定频率）重新渲染立方体贴图。可以反射动态物体，但性能开销大。可以通过 </font>**<font style="color:rgb(51, 51, 51);">Refresh Mode</font>**<font style="color:rgb(51, 51, 51);"> 设置为 </font>**<font style="color:rgb(51, 51, 51);">Every Frame</font>**<font style="color:rgb(51, 51, 51);"> 或 </font>**<font style="color:rgb(51, 51, 51);">Via Scripting</font>**<font style="color:rgb(51, 51, 51);"> 来控制更新频率。</font>

**<font style="color:rgb(51, 51, 51);">Custom</font>**<font style="color:rgb(51, 51, 51);">：由脚本控制渲染时机，灵活性最高。</font>

`<font style="color:rgb(51, 51, 51);">GameObject > Light > Reflection Probe</font>`应该多出一个叫 Reflection Probe 的对象，选中他并按F键，视角应飞到它旁边

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1788683059391-15064b3b-1fa1-4aa9-9492-3465afe61b95.png)

_<font style="color:rgb(51, 51, 51);">反射探针的 Inspector 面板，显示 Mode 选择</font>_

### <font style="color:rgb(51, 51, 51);">Box Projection 的原理和启用</font>
<font style="color:rgb(51, 51, 51);">默认情况下，反射探针使用</font>**无限投影（Infinite Projection）**<font style="color:rgb(51, 51, 51);">——反射方向指向无穷远处的虚拟立方体贴图。这在室内场景中会导致不正确的反射（如看到室外的天空）。</font>

<font style="color:#74B602;">盒投影和无限投影，金属球上会比较明显，探针上看到的是探针点上的世界，而金属球上反射的是无限投影处的光线，也就是天空盒</font>

<font style="color:#74B602;">那我搞个小盒子框起来不就行了吗，让反射走我自己的这个盒子、</font>

<font style="color:#74B602;">金属的漫反射是 0，画面亮度 100% 来自镜面反射。</font>

<font style="color:#74B602;">在场景某点 P 拍一张 Cubemap，附近物体反射时采样它，而不是天空盒那张全局图。</font>

<font style="color:#74B602;">2.2 它的本质局限</font>

<font style="color:#74B602;">探针记录的是「从 P 点看到的」世界，而不是「从物体表面看到的」。物体离 P 越远，误差越大——极端情况下物体会反射出它自己。</font>

**Box Projection（盒投影）**<font style="color:rgb(51, 51, 51);">通过将反射限制在一个有限的空间盒内来解决这个问题。反射方向与盒的交点决定了采样位置，使得反射更加真实。</font>

<font style="color:rgb(51, 51, 51);">在反射探针的 Inspector 中勾选 </font>**<font style="color:rgb(51, 51, 51);">Box Projection</font>**<font style="color:rgb(51, 51, 51);"> 即可启用。</font>

<font style="color:rgb(51, 51, 51);">在着色器中，Box Projection 通过 </font>`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">BOX_PROJECTION</font>`<font style="color:rgb(51, 51, 51);"> 宏启用。URP 的 </font>`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">UniversalFragmentPBR</font>`<font style="color:rgb(51, 51, 51);"> 会自动处理这个宏，我们不需要额外编写代码。</font>

<font style="color:#74B602;">把反射向量当成一条射线，从物体表面位置出发，求它与探针盒子边界的交点，改用「物体位置 → 交点」这个新向量采样。</font>

<font style="color:#74B602;">怎么修呢，这样修</font>

<font style="color:#74B602;">先别反射探针了，我整了个金属球的shader，然后搞个金属球玩玩，先构建出金属球，然后再看能不能烘焙</font>

<font style="color:#74B602;">现在整了个着色器，报错了，给ai修一轮，这次是需要首次验证，先跑通，先完成，再完美，就是说搞完之后再自己手写这些东西</font>

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1788788163155-5466172f-6400-43e5-87b9-24ab07b6aa18.png)

哎呀呀呀，突然意识到这个是反射了天空盒，这不就穿帮了，明白了，还得是实践出真知

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1788791423786-729f70d4-cb5e-4a05-81da-ba98df17c233.png)

按照路径烘焙出的，但是穿帮了，得在球体位置烘焙才可以，剩下的问题后面再解决吧

也没有那种完全穿帮，移动球体的位置是能够看到变化的，但是只记录到了标记为static的物体

### <font style="color:rgb(51, 51, 51);">反射探针的放置策略</font>
1. **<font style="color:rgb(51, 51, 51);">覆盖整个场景</font>**<font style="color:rgb(51, 51, 51);">：在场景的关键位置放置探针，确保每个区域都有反射数据</font>
2. **<font style="color:rgb(51, 51, 51);">避免重叠过多</font>**<font style="color:rgb(51, 51, 51);">：过多的重叠探针会增加混合计算量</font>
3. **<font style="color:rgb(51, 51, 51);">室内/室外分离</font>**<font style="color:rgb(51, 51, 51);">：在室内外交界处放置探针，避免室内反射到室外</font>
4. **<font style="color:rgb(51, 51, 51);">高度变化</font>**<font style="color:rgb(51, 51, 51);">：在多层建筑中，每层至少放置一个探针</font>

<font style="color:rgb(51, 51, 51);">探针之间的混合过渡是自动的——当物体位于多个探针的范围内时，URP 会根据距离进行</font><font style="color:rgb(51, 51, 51);background-color:#C1E77E;">插值混合</font><font style="color:rgb(51, 51, 51);">。</font>

### <font style="color:rgb(51, 51, 51);">粗糙度如何影响反射</font>
<font style="color:rgb(51, 51, 51);">表面的粗糙度会影响反射的清晰度：</font>

+ **<font style="color:rgb(51, 51, 51);">光滑表面（smoothness = 1）</font>**<font style="color:rgb(51, 51, 51);">：反射清晰锐利，采样 Cubemap 的最低 mipmap 级别</font>
+ **<font style="color:rgb(51, 51, 51);">粗糙表面（smoothness = 0）</font>**<font style="color:rgb(51, 51, 51);">：反射模糊扩散，采样 Cubemap 的较高 mipmap 级别</font>

<font style="color:#117CEE;">越光滑，反射的细节就越多，当然就是要更低的mipmap级别</font>

<font style="color:rgb(51, 51, 51);">URP 使用以下公式将光滑度转换为 mipmap 级别：</font>

```glsl
float mip = PerceptualRoughnessToMipmapLevel(1.0 - smoothness);
float3 reflectionSample = SAMPLE_TEXTURECUBE_LOD(reflectionCube, sampler_reflectionCube, reflectDir, mip);
```

<font style="color:rgb(51, 51, 51);">其中 </font>`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">PerceptualRoughnessToMipmapLevel</font>`<font style="color:rgb(51, 51, 51);"> 将感知粗糙度转换为 mipmap 级别，确保模糊效果在视觉上均匀。</font>

### <font style="color:rgb(51, 51, 51);">反射的工作流程</font>
<font style="color:rgb(51, 51, 51);">反射的计算流程如下：</font>

1. **<font style="color:rgb(51, 51, 51);">环境光反射（Ambient Reflection）</font>**<font style="color:rgb(51, 51, 51);">：基于表面法线，从反射探针或天空盒中采样</font>
2. **<font style="color:rgb(51, 51, 51);">镜面反射（Specular Reflection）</font>**<font style="color:rgb(51, 51, 51);">：基于视角方向和法线，计算反射方向，从立方体贴图中采样</font>
3. **<font style="color:rgb(51, 51, 51);">菲涅尔效应（Fresnel Effect）</font>**<font style="color:rgb(51, 51, 51);">：视角越斜，反射越强</font>

`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">UniversalFragmentPBR</font>`<font style="color:rgb(51, 51, 51);"> 内部会处理所有这些计算。我们只需要确保：</font>

+ `<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">SurfaceData</font>`<font style="color:rgb(51, 51, 51);"> 中的 </font>`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">albedo</font>`<font style="color:rgb(51, 51, 51);">、</font>`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">specular</font>`<font style="color:rgb(51, 51, 51);">、</font>`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">metallic</font>`<font style="color:rgb(51, 51, 51);">、</font>`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">smoothness</font>`<font style="color:rgb(51, 51, 51);"> 正确设置</font>
+ `<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">InputData</font>`<font style="color:rgb(51, 51, 51);"> 中的 </font>`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">normalWS</font>`<font style="color:rgb(51, 51, 51);"> 和 </font>`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">viewDirectionWS</font>`<font style="color:rgb(51, 51, 51);"> 正确设置</font>

### <font style="color:rgb(51, 51, 51);">金属表面的反射</font>
<font style="color:rgb(51, 51, 51);">金属表面的反射颜色受反照率（albedo）影响。这就是为什么金属的反射会带有颜色——铜反射出橙金色，金反射出黄色。</font>

`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">UniversalFragmentPBR</font>`<font style="color:rgb(51, 51, 51);"> 会根据 </font>`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">metallic</font>`<font style="color:rgb(51, 51, 51);"> 值自动调整反射的颜色。金属度越高，反射颜色越接近反照率颜色。</font>

### <font style="color:rgb(51, 51, 51);">Planar Reflection（平面反射）</font>
<font style="color:rgb(51, 51, 51);">对于水面、地板等平面反射，标准的立方体贴图反射不够准确。</font>**平面反射（Planar Reflection）**<font style="color:rgb(51, 51, 51);">通过从</font><font style="color:rgb(51, 51, 51);background-color:#C1E77E;">反射视角重新渲染场景</font><font style="color:rgb(51, 51, 51);">来实现精确的反射。</font>

<font style="color:rgb(51, 51, 51);">实现思路：</font>

1. <font style="color:rgb(51, 51, 51);">创建一个镜像摄像机（沿平面对称翻转）</font>
2. <font style="color:rgb(51, 51, 51);">将镜像摄像机的渲染结果输出到 Render Texture</font>
3. <font style="color:rgb(51, 51, 51);">在着色器中采样这张 Render Texture</font>

<font style="color:rgb(51, 51, 51);">URP 中可以通过自定义 Render Feature 实现平面反射。这超出了本教程的范围，但了解其原理有助于选择合适的反射方案。</font>

### <font style="color:rgb(51, 51, 51);">代码层面：手动采样反射探针</font>
<font style="color:rgb(51, 51, 51);">虽然 </font>`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">UniversalFragmentPBR</font>`<font style="color:rgb(51, 51, 51);"> 已经处理了反射，但了解底层实现有助于自定义效果：</font>

```glsl
// 手动采样反射探针的简化代码
float3 reflectDir = reflect(-viewDirWS, normalWS);

// Box Projection 修正
#if defined(BOX_PROJECTION)
    float3 boxMin = unity_SpecCube0_BoxMin;
    float3 boxMax = unity_SpecCube0_BoxMax;
    float3 boxCenter = unity_SpecCube0_BoxMin;
    // 计算与盒的交点
    float3 intersectMax = (boxMax - posWS) / reflectDir;
    float3 intersectMin = (boxMin - posWS) / reflectDir;
    float3 intersect = max(intersectMax, intersectMin);
    float dist = min(min(intersect.x, intersect.y), intersect.z);
    posWS += reflectDir * dist;
#endif

// 计算 mipmap 级别
float roughness = 1.0 - smoothness;
float mip = PerceptualRoughnessToMipmapLevel(roughness);

// 采样 Cubemap
float4 sample = SAMPLE_TEXTURECUBE_LOD(unity_SpecCube0, samplerunity_SpecCube0, reflectDir, mip);
float3 envColor = DecodeHDR(sample, unity_SpecCube0_HDR);
```

### <font style="color:rgb(51, 51, 51);">常见坑点</font>
1. **<font style="color:rgb(51, 51, 51);">反射探针不更新</font>**<font style="color:rgb(51, 51, 51);">：确认探针的 Mode 设置为 Realtime，并且 Refresh Mode 不是 "On Awake"。</font>
2. **<font style="color:rgb(51, 51, 51);">Box Projection 设置不正确导致反射扭曲</font>**<font style="color:rgb(51, 51, 51);">：检查探针的 Box Size 和 Box Offset 是否正确包围了反射区域。</font>
3. **<font style="color:rgb(51, 51, 51);">反射过亮或过暗</font>**<font style="color:rgb(51, 51, 51);">：确认反射探针的 HDR 设置与场景匹配。HDR 探针提供更亮的反射，LDR 探针反射较暗。</font>
4. **<font style="color:rgb(51, 51, 51);">金属表面反射为黑色</font>**<font style="color:rgb(51, 51, 51);">：确认场景中有反射探针或天空盒。没有反射数据时，金属表面会显示为黑色。</font>

### <font style="color:rgb(51, 51, 51);">反射探针的设置</font>
<font style="color:rgb(51, 51, 51);">在场景中添加反射探针：</font>

1. <font style="color:rgb(51, 51, 51);">创建反射探针：</font>`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">GameObject > Light > Reflection Probe</font>`
2. <font style="color:rgb(51, 51, 51);">调整探针的位置和范围</font>
3. <font style="color:rgb(51, 51, 51);">设置探针的类型：</font>
    - **<font style="color:rgb(51, 51, 51);">Baked</font>**<font style="color:rgb(51, 51, 51);">：烘焙反射，运行时不变</font>
    - **<font style="color:rgb(51, 51, 51);">Realtime</font>**<font style="color:rgb(51, 51, 51);">：实时渲染反射，性能开销大</font>
    - **<font style="color:rgb(51, 51, 51);">Custom</font>**<font style="color:rgb(51, 51, 51);">：自定义渲染时机</font>

### <font style="color:rgb(51, 51, 51);">测试反射</font>
1. <font style="color:rgb(51, 51, 51);">在场景中添加一个反射探针</font>
2. <font style="color:rgb(51, 51, 51);">创建一个金属球体，调整金属度到 1</font>
3. <font style="color:rgb(51, 51, 51);">观察球体反射周围环境的效果</font>

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1788859091026-c0d752f7-12de-48d9-8120-6c4399573652.png)

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1788843634295-193fc815-8e54-43aa-ae25-6c833d97baac.png)

_<font style="color:rgb(51, 51, 51);">金属球体反射周围环境</font>_

### <font style="color:rgb(51, 51, 51);">实际项目修改</font>
<font style="color:rgb(51, 51, 51);">反射探针支持</font>**<font style="color:rgb(51, 51, 51);">不需要在着色器中添加任何新属性或纹理</font>**<font style="color:rgb(51, 51, 51);">。你只需要确保在附加光源章节中添加的 </font>`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">_REFLECTION_PROBE_BLENDING</font>`<font style="color:rgb(51, 51, 51);"> 和 </font>`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">_REFLECTION_PROBE_BOX_PROJECTION</font>`<font style="color:rgb(51, 51, 51);"> 关键字已经存在。</font>

<font style="color:rgb(51, 51, 51);">URP 的 </font>`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">UniversalFragmentPBR</font>`<font style="color:rgb(51, 51, 51);"> 函数会自动处理：</font>

+ <font style="color:rgb(51, 51, 51);">反射探针的采样</font>
+ <font style="color:rgb(51, 51, 51);">多个探针之间的混合（需要 </font>`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">_REFLECTION_PROBE_BLENDING</font>`<font style="color:rgb(51, 51, 51);">）</font>
+ <font style="color:rgb(51, 51, 51);">Box Projection 修正（需要 </font>`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">_REFLECTION_PROBE_BOX_PROJECTION</font>`<font style="color:rgb(51, 51, 51);">）</font>
+ <font style="color:rgb(51, 51, 51);">粗糙度对反射模糊的影响</font>

<font style="color:rgb(51, 51, 51);">你只需要在场景中放置反射探针（</font>`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">GameObject > Light > Reflection Probe</font>`<font style="color:rgb(51, 51, 51);">）并调整其设置即可。</font>

```glsl
// =============================================================
//  Custom/MaterialSphere — URP 版金属球测试着色器
//  对应原 Built-in Surface Shader 的功能，改用 URP HLSL 重写
//
//  重点（反射探针相关）：
//    1. 必须保留 _REFLECTION_PROBE_BLENDING / _REFLECTION_PROBE_BOX_PROJECTION
//    2. InputData.positionWS 必须正确赋值 —— 盒投影全靠它
//    3. URP Asset 里也要启用 Box Projection（第三道开关，见说明）
// =============================================================

Shader "Custom/MaterialSphere"
{
    Properties
    {
        _BaseColor  ("Color", Color) = (1,1,1,1)
        _MainTex    ("Albedo (RGB)", 2D) = "white" {}
        _Metallic   ("Metallic", Range(0,1)) = 1.0
        _Smoothness ("Smoothness", Range(0,1)) = 0.95
    }

    SubShader
    {
        Tags
        {
            "RenderPipeline" = "UniversalPipeline"
            "RenderType" = "Opaque"
            "Queue" = "Geometry"
            "UniversalMaterialType" = "Lit"
            "IgnoreProjector" = "True"
        }
        LOD 200

        // ----------------------------------------------------
        //  主 Pass：前向光照 + PBR
        // ----------------------------------------------------
        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode" = "UniversalForward" }

            HLSLPROGRAM
            #pragma target 3.0
            #pragma exclude_renderers gles gles3 glcore

            #pragma vertex   Vert
            #pragma fragment Frag

            // ---- GPU Instancing（对应原文的 instancing 支持）----
            #pragma multi_compile_instancing
            #pragma instancing_options assumeuniformscaling

            // ---- 主光 / 附加光 / 阴影 ----
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile _ _SHADOWS_SOFT
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _LIGHT_COOKIES
            #pragma multi_compile_fragment _ _SCREEN_SPACE_OCCLUSION

            // ---- 反射探针（★ 关键，缺一个盒投影就失效）----
            #pragma multi_compile_fragment _ _REFLECTION_PROBE_BLENDING
            #pragma multi_compile_fragment _ _REFLECTION_PROBE_BOX_PROJECTION
            #pragma shader_feature_local_fragment _ENVIRONMENTREFLECTIONS_OFF

            // ---- 雾 ----
            #pragma multi_compile_fog

            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/EntityLighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);

            // SRP Batcher 兼容写法：所有属性放进 UnityPerMaterial
            CBUFFER_START(UnityPerMaterial)
                half4  _BaseColor;
                float4 _MainTex_ST;
                half   _Metallic;
                half   _Smoothness;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float2 uv         : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv         : TEXCOORD0;
                float3 positionWS : TEXCOORD1;
                float3 normalWS   : TEXCOORD2;
                float3 viewDirWS  : TEXCOORD3;
                float  fogFactor  : TEXCOORD4;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            Varyings Vert(Attributes input)
            {
                Varyings output = (Varyings)0;

                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_TRANSFER_INSTANCE_ID(input, output);

                VertexPositionInputs posInput = GetVertexPositionInputs(input.positionOS.xyz);
                VertexNormalInputs   nrmInput = GetVertexNormalInputs(input.normalOS);

                output.positionCS = posInput.positionCS;
                output.positionWS = posInput.positionWS;   // ★ 盒投影要用，绝不能省
                output.normalWS   = nrmInput.normalWS;
                output.viewDirWS  = GetWorldSpaceViewDir(posInput.positionWS);
                output.uv         = TRANSFORM_TEX(input.uv, _MainTex);
                output.fogFactor  = ComputeFogFactor(posInput.positionCS.z);

                return output;
            }

            half4 Frag(Varyings input) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(input);

                // ---------------- SurfaceData：材质表面属性 ----------------
                SurfaceData surface = (SurfaceData)0;
                half4 albedo = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, input.uv) * _BaseColor;

                surface.albedo              = albedo.rgb;
                surface.alpha               = 1.0;
                surface.metallic            = _Metallic;     // 金属度
                surface.smoothness          = _Smoothness;   // 光滑度 → 决定反射清晰度
                surface.specular            = half3(0.0, 0.0, 0.0);
                surface.normalTS            = half3(0.0, 0.0, 1.0);
                surface.emission            = half3(0.0, 0.0, 0.0);
                surface.occlusion           = 1.0;
                surface.clearCoatMask       = 0.0;
                surface.clearCoatSmoothness = 0.0;

                // ---------------- InputData：光照输入 ----------------
                InputData lightingInput = (InputData)0;
                lightingInput.positionWS  = input.positionWS;   // ★★ 盒投影的唯一输入
                lightingInput.normalWS    = normalize(input.normalWS);
                lightingInput.viewDirectionWS = SafeNormalize(input.viewDirWS);
                lightingInput.bakedGI     = SampleSH(lightingInput.normalWS);
                lightingInput.fogCoord    = input.fogFactor;
                lightingInput.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(input.positionCS);
                lightingInput.shadowCoord = TransformWorldToShadowCoord(input.positionWS);
                lightingInput.shadowMask  = half4(1.0, 1.0, 1.0, 1.0);

                // 采样反射探针 / 天空盒、混合、盒投影、按粗糙度选 mip —— 全在这里面
                half4 color = UniversalFragmentPBR(lightingInput, surface);

                color.rgb = MixFog(color.rgb, input.fogFactor);
                return color;
            }
            ENDHLSL
        }

        // ---------- 下面这些 Pass 直接复用 URP 内置 Lit，省事且可靠 ----------
        // 若某行报「找不到 Pass」，删掉即可（只影响投影 / 深度法线 / 烘焙）
        UsePass "Universal Render Pipeline/Lit/ShadowCaster"
        UsePass "Universal Render Pipeline/Lit/DepthOnly"
        UsePass "Universal Render Pipeline/Lit/DepthNormals"
        UsePass "Universal Render Pipeline/Lit/Meta"
    }

    FallBack "Hidden/Universal Render Pipeline/FallbackError"
}

```

<font style="color:#117CEE;">我使用上面的反射探针shader来跑通了渲染，但是实际上我的mylit着色器的功能更加丰富，完全可以兼容这个着色器，但是当我使用mylit着色来渲染的时候出现了一些bug</font>

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1788850270954-8c772e67-339d-4656-a3e3-985243d28370.png)

```glsl
half3 refl = reflect(-viewDirWS, normalWS);
half4 envTest = SAMPLE_TEXTURECUBE_LOD(unity_SpecCube0, samplerunity_SpecCube0, refl, 0);
return half4(DecodeHDREnvironment(envTest, unity_SpecCube0_HDR), 1);
```

<font style="color:#117CEE;">球体一直是死黑的，直接让他反射天空盒</font>

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1788850519044-54af7e5a-222a-4653-9e2b-8896ec943d70.png)

<font style="color:#117CEE;">这行代码绕过了整个光照计算，直接把探针/天空盒的 cubemap 原样贴到物体表面，换成这三行好了，说明场景侧全对了，天空盒也有效，问题在 Shader 内部</font>

<font style="color:#117CEE;">先撤掉诊断代码，把那三行恢复成</font>

```glsl
return UniversalFragmentPBR(lightingInput, surfaceInput);
```

<font style="color:#117CEE;">顺手发现个问题，加个补丁，在 </font>`<font style="color:#117CEE;">lightingInput.shadowCoord</font>`<font style="color:#117CEE;"> 那行下面补：</font>

```glsl
lightingInput.shadowCoord = TransformWorldToShadowCoord(input.positionWS);

// ★ 补这两行
lightingInput.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(input.positionCS);
lightingInput.shadowMask = half4(1.0, 1.0, 1.0, 1.0);
```

<font style="color:#117CEE;">如果亮了就是 normalizedScreenSpaceUV = (0,0) 导致 SSAO 采样错误，把环境反射乘没了，但实际上没亮，接着向下处理</font>

<font style="color:#117CEE;">在 </font>`<font style="color:#117CEE;">return UniversalFragmentPBR(...)</font>`<font style="color:#117CEE;"> 前面临时插一行：</font>

```glsl
return half4(surfaceInput.occlusion.xxx, 1);
```

<font style="color:#117CEE;">如果是黑色，可能是</font>`<font style="color:#117CEE;">_OcclusionMap</font>`<font style="color:#117CEE;"> 没贴图时默认 </font>`<font style="color:#117CEE;">gray</font>`<font style="color:#117CEE;">，</font>`<font style="color:#117CEE;">.g</font>`<font style="color:#117CEE;">通道应该是 1×1=1，变黑说明</font><font style="color:#117CEE;background-color:#C1E77E;">贴图</font><font style="color:#117CEE;">或 </font>`<font style="color:#117CEE;background-color:#C1E77E;">_OcclusionStrength</font>`<font style="color:#117CEE;"> 有问题</font>

```glsl
// surfaceInput.occlusion = SAMPLE_TEXTURE2D(_OcclusionMap, sampler_OcclusionMap, uv).g * _OcclusionStrength;
surfaceInput.occlusion = 1.0;   // 临时硬编码
```

<font style="color:#117CEE;">这次球终于亮了，发现是这里的</font>`<font style="color:#117CEE;">_OcclusionStrength</font>`<font style="color:#117CEE;">调整成0了</font>

<font style="color:#117CEE;">同时我也注意到代码这里：</font>

```glsl
    // 如果以后想做AO，就采样一张Occlusion贴图，URP惯例用g通道
    surfaceInput.occlusion = 1.0;
```

<font style="color:#117CEE;">虽然那个时候想到了没有做AO，直接给赋值了，但是这条代码写的太靠前了，在后来的代码中被忘记了，这次已经查明了原因，整个场景所有用 MyLit 的物体的</font><font style="color:#117CEE;background-color:#C1E77E;">间接光</font><font style="color:#117CEE;">都被抹掉了，只是金属的漫反射本来就是 0，全靠环境反射，所以只有它黑得这么彻底。</font>

<font style="color:#117CEE;">就是说漫反射强度被设置为0了，强度全被抹掉了，所以除了高光显示全黑。</font>

<font style="color:#117CEE;">AO 是 PBR 的标准一环，功能上必须保留。但你的直觉方向是对的：它现在缺一个开关，导致"没贴图也在采样"，这也会把反射搞黑。</font>

<font style="color:#117CEE;">我们来增加这个开关</font>

```glsl
[Header(Occlusion)]
[Toggle(_OCCLUSIONMAP)] _OcclusionToggle("使用遮挡贴图", Float) = 0 // 增加这一行
[NoScaleOffset] _OcclusionMap("遮挡贴图", 2D) = "white" {}
_OcclusionStrength("遮挡强度", Range(0,1)) = 1
```

<font style="color:#117CEE;">ForwardLit Pass 的 pragma 区</font>

```glsl
#pragma shader_feature_local_fragment _OCCLUSIONMAP
```

`<font style="color:#117CEE;">MyLitForwardLitPass.hlsl</font>`<font style="color:#117CEE;">的这里，将</font>`<font style="color:#117CEE;">surfaceInput.occlusion = 1.0;</font>`<font style="color:#117CEE;">用守卫关键字包裹，放在</font>`<font style="color:#117CEE;">occlusion</font>`<font style="color:#117CEE;">采样的</font>`<font style="color:#117CEE;">else</font>`<font style="color:#117CEE;">分支里</font>

```glsl
#ifdef _OCCLUSIONMAP
    surfaceInput.occlusion = SAMPLE_TEXTURE2D(_OcclusionMap, sampler_OcclusionMap, uv).g * _OcclusionStrength;
#else
    surfaceInput.occlusion = 1.0;
#endif
```

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1788849908186-70c02e56-d127-456f-ae25-3c14c32cbd49.png)

还有一个问题需要解决，这个背景是黑色的

这个技巧以后能救命。用亮色背景，一眼就能分清"物体没渲染"和"物体渲染成了黑色"——这是完全不同的两类问题。

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1788860163267-fbb00c48-040d-4e27-97bb-373fe7fac284.png)

GameObject > Light > Reflection Probe这里创建一个光照探针

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1788853797409-7dfe4b82-dd3b-47f2-9f4e-2ba17aba1a4e.png)

背面颜色有点奇怪，这源于我一直使用一个平面去搭建环境，这里我使用了5个Cube围成了一个敞口容器，在这里进行渲染，注意Cube需要设置为Static

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1788859777135-293fea86-f04b-441d-9d94-bf9e68a33d2a.png)<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1788860115245-f29467ee-7f94-4f26-85dc-67a53fb472fe.png)<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1788860248422-b25d247b-94bd-40b6-8011-d474242e9e7b.png)

这里金属球已经用MyLit着色提前调好了参数，烘焙后得到这样的效果

最后，在本节中，Planar Reflection（平面反射）部分只是简单带过，简单来说就是把整个场景从镜像视角重新渲染一遍，输出到一张 RT，然后 Shader 用屏幕空间 UV 去采样这张 RT。

【埋坑】这部分内容属于中级偏上的内容，现在主要是把效果做出了，而不是去深挖里面的bug

---

## <font style="color:rgb(51, 51, 51);">五、光源 Cookie</font>
**<font style="color:rgb(51, 51, 51);">光源 Cookie（Light Cookies）</font>**<font style="color:rgb(51, 51, 51);">是</font><font style="color:rgb(51, 51, 51);background-color:#C1E77E;">一张纹理</font><font style="color:rgb(51, 51, 51);">，用于遮罩光源的照射区域。你可以用它来模拟光线通过</font><font style="color:rgb(51, 51, 51);background-color:#C1E77E;">百叶窗</font><font style="color:rgb(51, 51, 51);">、树叶等物体</font><font style="color:rgb(51, 51, 51);background-color:#C1E77E;">投射的阴影效果</font><font style="color:rgb(51, 51, 51);">。</font>

<font style="color:#117CEE;">Cookie 是一张贴在光源上的遮罩纹理，逐像素地乘在光照强度上。</font>

<font style="color:#117CEE;">物理类比：想象在手电筒前蒙一张打了孔的黑纸，或者在投影仪上放一张幻灯片——光线穿过图案，就把图案"印"到了被照的地方。Cookie 就是这张幻灯片，区别只是它是数字纹理，可以任意画。较新的 URP 支持彩色 Cookie（彩色玻璃、舞台染色灯），此时是 light.color *= cookie.rgb，顺带给光线染色。灰度 Cookie 时 RGB 各通道相等，取 .r 还是 .a 都一样——所以你会在不同版本的 URP 源码里看到两种写法，不用纠结。</font>

<font style="color:#117CEE;">Cookie 的"假"体现在哪：图案不随物体几何变形，也不随距离变化。真实的百叶窗投影，墙面离窗户越远光斑越模糊、越大；Cookie 打在哪都是同一张图。所以 Cookie 适合"氛围型、面积大、不需要精确"的光影，精确遮挡必须走 Shadow Map。</font>

<font style="color:#117CEE;">反过来 Cookie 也有 Shadow Map 做不到的：Shadow Map 只能投出"有/无"，Cookie 能投出任意软硬渐变、彩色图案，而且几乎不要钱。</font>

### <font style="color:rgb(51, 51, 51);">Cookie 基础</font>
<font style="color:rgb(51, 51, 51);">Cookie 纹理定义了光源的强度分布：</font>

+ **<font style="color:rgb(51, 51, 51);">白色</font>**<font style="color:rgb(51, 51, 51);">：完全照射</font>
+ **<font style="color:rgb(51, 51, 51);">黑色</font>**<font style="color:rgb(51, 51, 51);">：完全不照射</font>
+ **<font style="color:rgb(51, 51, 51);">灰色</font>**<font style="color:rgb(51, 51, 51);">：部分照射</font>

<font style="color:rgb(51, 51, 51);">Cookie 可以用于方向光和点光源。聚光灯默认使用一个圆锥形的 Cookie。</font>

### <font style="color:rgb(51, 51, 51);">Cookie 纹理的制作要求</font>
<font style="color:rgb(51, 51, 51);">在 Unity 中使用 Cookie 纹理时，需要注意以下导入设置：</font>

1. **<font style="color:rgb(51, 51, 51);">Texture Type</font>**<font style="color:rgb(51, 51, 51);">：设置为 </font>**<font style="color:rgb(51, 51, 51);">Cookie</font>**
2. **<font style="color:rgb(51, 51, 51);">Light Type</font>**<font style="color:rgb(51, 51, 51);">：选择对应的光源类型（Directional / Point / Spot）</font>
3. **<font style="color:rgb(51, 51, 51);">Alpha From Luminance</font>**<font style="color:rgb(51, 51, 51);">：启用后，Cookie 的 Alpha 通道由亮度自动生成（适用于没有 Alpha 通道的纹理）</font>

<font style="color:rgb(162, 127, 3);"></font>

_<font style="color:rgb(51, 51, 51);">Cookie 纹理的导入设置面板</font>_

<font style="color:rgb(119, 119, 119);">注意：Cookie 纹理应该是</font><font style="color:rgb(119, 119, 119);background-color:#C1E77E;">方形</font><font style="color:rgb(119, 119, 119);">（如 256×256 或 512×512），并且建议使用</font><font style="color:rgb(119, 119, 119);background-color:#C1E77E;">单通道（灰度）纹理</font><font style="color:rgb(119, 119, 119);">以节省内存。</font>

### <font style="color:rgb(51, 51, 51);">方向光 Cookie vs 点光源 Cookie vs 聚光灯 Cookie</font>
<font style="color:rgb(51, 51, 51);">不同类型的 Cookie 使用不同的采样方式：</font>

| **<font style="color:rgb(51, 51, 51);">光源类型</font>** | **<font style="color:rgb(51, 51, 51);">Cookie 类型</font>** | **<font style="color:rgb(51, 51, 51);">采样方式</font>** |
| :--- | :--- | :--- |
| **<font style="color:rgb(51, 51, 51);">方向光（Directional）</font>** | <font style="color:rgb(51, 51, 51);">2D 纹理</font> | <font style="color:rgb(51, 51, 51);">使用光源的世界空间矩阵变换到纹理空间</font> |
| **<font style="color:rgb(51, 51, 51);">点光源（Point）</font>** | <font style="color:rgb(51, 51, 51);">Cubemap</font> | <font style="color:rgb(51, 51, 51);">根据方向采样立方体贴图</font> |
| **<font style="color:rgb(51, 51, 51);">聚光灯（Spot）</font>** | <font style="color:rgb(51, 51, 51);">2D 纹理（默认圆锥）</font> | <font style="color:rgb(51, 51, 51);">使用投影矩阵变换到纹理空间</font> |


<font style="color:rgb(51, 51, 51);">方向光的 Cookie 使用一个 </font><font style="color:rgb(51, 51, 51);background-color:#C1E77E;">2D 纹理</font><font style="color:rgb(51, 51, 51);">，通过光源的世界空间矩阵将表面点变换到纹理坐标。这使得方向光 Cookie 可以</font><font style="color:rgb(51, 51, 51);background-color:#C1E77E;">模拟平行光通过遮挡物</font><font style="color:rgb(51, 51, 51);">的效果。</font>

<font style="color:rgb(51, 51, 51);">点光源的 Cookie 使用 Cubemap，因为点光源向所有方向发射光线，需要从</font><font style="color:rgb(51, 51, 51);background-color:#C1E77E;">六个面</font><font style="color:rgb(51, 51, 51);">采样。</font>

<font style="color:rgb(51, 51, 51);">聚光灯默认有一个</font><font style="color:rgb(51, 51, 51);background-color:#C1E77E;">圆锥形</font><font style="color:rgb(51, 51, 51);">的 Cookie（定义了光照的锥形范围），但你可以替换为自定义纹理。</font>

<font style="color:#117CEE;">很好理解嘛，本质上是采样贴图，那方向光就是从高空往下照，点光源是四面八方的发射光线，和cubemap一样，需要6个2d纹理，聚光灯</font>

### <font style="color:rgb(51, 51, 51);">Cookie 在 Shader 中的采样原理</font>
<font style="color:rgb(51, 51, 51);">Cookie 的采样涉及将世界空间坐标变换到光源的纹理空间：</font>

```glsl
// 方向光 Cookie 的采样原理
float4 TransformWorldToLightCoord(float3 worldPos, float4x4 lightMatrix) {
    float4 lightCoord = mul(lightMatrix, float4(worldPos, 1.0));
    return lightCoord / lightCoord.w;  // 透视除法
}

// 在光照计算中
float cookieAttenuation = SAMPLE_TEXTURE2D(_MainLightCookie, sampler_MainLightCookie, lightCoord.xy).r;
light.color *= cookieAttenuation;
```

<font style="color:rgb(51, 51, 51);">URP 的 </font>`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">UniversalFragmentPBR</font>`<font style="color:rgb(51, 51, 51);"> 内部已经处理了 Cookie 的采样，我们</font><font style="color:rgb(51, 51, 51);background-color:#C1E77E;">只需要启用对应的宏</font><font style="color:rgb(51, 51, 51);">即可。</font>

### <font style="color:rgb(51, 51, 51);">Cookie 的硬件限制</font>
<font style="color:rgb(51, 51, 51);">不同平台对 Cookie 的支持有限制：</font>

+ **<font style="color:rgb(51, 51, 51);">PC/主机</font>**<font style="color:rgb(51, 51, 51);">：支持大尺寸 Cookie（最大 2048×2048），数量无限制</font>
+ **<font style="color:rgb(51, 51, 51);">移动端</font>**<font style="color:rgb(51, 51, 51);">：建议使用小尺寸 Cookie（256×256 或 512×512），数量不超过 4 个</font>
+ **<font style="color:rgb(51, 51, 51);">WebGL</font>**<font style="color:rgb(51, 51, 51);">：Cookie 支持有限，某些格式可能不兼容</font>

### <font style="color:rgb(51, 51, 51);">实际应用案例</font>
1. **<font style="color:rgb(51, 51, 51);">百叶窗投影效果</font>**<font style="color:rgb(51, 51, 51);">：创建一个黑白条纹纹理作为方向光 Cookie，模拟</font><font style="color:rgb(51, 51, 51);background-color:#C1E77E;">阳光透过百叶窗</font><font style="color:rgb(51, 51, 51);">的效果</font>
2. **<font style="color:rgb(51, 51, 51);">树叶阴影效果</font>**<font style="color:rgb(51, 51, 51);">：使用树叶纹理作为方向光 Cookie，模拟阳光穿过树冠的效果</font>
3. **<font style="color:rgb(51, 51, 51);">体积光效果</font>**<font style="color:rgb(51, 51, 51);">：结合 Cookie 和</font><font style="color:rgb(51, 51, 51);background-color:#C1E77E;">雾效</font><font style="color:rgb(51, 51, 51);">，模拟光线穿过窗户的</font><font style="color:rgb(51, 51, 51);background-color:#C1E77E;">体积光</font><font style="color:rgb(51, 51, 51);">效果</font>

### <font style="color:rgb(51, 51, 51);">添加 Cookie 支持</font>
<font style="color:rgb(51, 51, 51);">URP 会自动处理 Cookie 的采样，我们只需要确保着色器启用了正确的关键字。</font>

```glsl
Shader "Custom/MyLit" {
    ...
    SubShader {
        ...
        Pass {
            Name "ForwardLit"
            ...
            HLSLPROGRAM

            #pragma shader_feature_local_fragment _NORMALMAP
            #pragma shader_feature_local _CLEARCOATMAP
            #pragma shader_feature_local _ALPHA_CUTOUT
            #pragma shader_feature_local _DOUBLE_SIDED_NORMALS
            #pragma shader_feature_local_fragment _SPECULAR_SETUP
            #pragma shader_feature_local_fragment _ROUGHNESS_SETUP
            #pragma shader_feature_local_fragment _ALPHAPREMULTIPLY_ON

#if UNITY_VERSION >= 202120
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
#else
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
#endif
            #pragma multi_compile_fragment _ _SHADOWS_SOFT

            // 附加光源支持
            #pragma multi_compile _ _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHTS_SHADOWS

            // Cookie 支持
            #pragma multi_compile _ _MAIN_LIGHT_COOKIE
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_COOKIE

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

<font style="color:rgb(51, 51, 51);">在 </font>`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">MyLit.shader</font>`<font style="color:rgb(51, 51, 51);"> 中添加两个 Cookie 相关的关键字：</font>

+ `<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">_MAIN_LIGHT_COOKIE</font>`<font style="color:rgb(51, 51, 51);">：主光源的 Cookie</font>
+ `<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">_ADDITIONAL_LIGHTS_COOKIE</font>`<font style="color:rgb(51, 51, 51);">：附加光源的 Cookie</font>

注意：URP 会根据光源是否设置了 Cookie 自动启用这些关键字。

### <font style="color:rgb(51, 51, 51);">Cookie 纹理设置</font>
<font style="color:rgb(51, 51, 51);">在 Unity 中设置光源的 Cookie：</font>

1. <font style="color:rgb(51, 51, 51);">选择方向光或点光源</font>
2. <font style="color:rgb(51, 51, 51);">在 Inspector 中设置 Cookie 纹理</font>
3. <font style="color:rgb(51, 51, 51);">调整 Cookie 大小和方向</font>

<font style="color:#117CEE;">需要生成 Mipmap，所以纹理规格需要是2 的幂</font>

### <font style="color:rgb(51, 51, 51);">测试 Cookie</font>
1. <font style="color:rgb(51, 51, 51);">创建一张黑白条纹纹理</font>
2. <font style="color:rgb(51, 51, 51);">将其设置为方向光的 Cookie</font>
3. <font style="color:rgb(51, 51, 51);">观察光线通过条纹投射的阴影效果</font>

<font style="color:rgb(162, 127, 3);"></font>

_<font style="color:rgb(51, 51, 51);">光源通过百叶窗 Cookie 投射的条纹阴影</font>_

### <font style="color:rgb(51, 51, 51);">实际项目修改</font>
<font style="color:rgb(51, 51, 51);">Cookie 支持</font>**<font style="color:rgb(51, 51, 51);">不需要在着色器中添加任何新属性或纹理</font>**<font style="color:rgb(51, 51, 51);">。你只需要确保在附加光源章节中添加的 </font>`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">_MAIN_LIGHT_COOKIE</font>`<font style="color:rgb(51, 51, 51);"> 和 </font>`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">_ADDITIONAL_LIGHTS_COOKIE</font>`<font style="color:rgb(51, 51, 51);"> 关键字已经存在。</font>

<font style="color:rgb(51, 51, 51);">URP 会自动处理 Cookie 的采样和光源遮罩计算。你只需要在场景中的光源上设置 Cookie 纹理即可。</font>

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1789054928193-f8c8993b-c8a9-4eff-ae3a-550b31b20739.png)<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1789054992079-a8711ac0-9648-4576-991d-3f72e99c0818.png)

Unity 的实时全局光照（Realtime Global Illumination, RTGI）系统目前不支持聚光灯（Spot）和点光源（Point）的间接光反弹阴影。对于聚光灯，设置为0即可消灭警告

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2026/png/25470454/1789055192487-b950ffc3-b317-41a0-96a1-494382633088.png)

在地面上投射红砖效果，当投影机用了

<font style="color:#74B602;">Spot Light 用的是透视投影（类似相机），TransformWorldToCookiePositionWS 返回的 UV 坐标天然就在纹理范围内，不会超出边缘，所以 Repeat 和 Clamp 效果一样。</font>

<font style="color:#74B602;">为什么教程推荐 Clamp？</font>

<font style="color:#74B602;">主要是为了 Directional Light。方向光用的是正交投影，如果场景很大，UV 可能超出范围，Repeat 会导致纹理在边缘突然重复，出现明显的接缝。Clamp 则会让边缘保持平滑。</font>

---

## <font style="color:rgb(51, 51, 51);">六、调试光照</font>
<font style="color:rgb(51, 51, 51);">随着光照系统变得越来越复杂，调试也变得越来越重要。让我们回顾一些调试技巧。</font>

### <font style="color:rgb(51, 51, 51);">渲染调试器中的光照视图</font>
<font style="color:rgb(51, 51, 51);">Unity 2021 的渲染调试器（Rendering Debugger）提供了多个光照相关的调试视图：</font>

+ **<font style="color:rgb(51, 51, 51);">Direct Diffuse</font>**<font style="color:rgb(51, 51, 51);">：直接漫反射光照。显示每个像素接收到的直接光源漫反射贡献。</font>
+ **<font style="color:rgb(51, 51, 51);">Direct Specular</font>**<font style="color:rgb(51, 51, 51);">：直接镜面光照。显示每个像素接收到的直接光源镜面反射贡献。</font>
+ **<font style="color:rgb(51, 51, 51);">Indirect Diffuse</font>**<font style="color:rgb(51, 51, 51);">：间接漫反射光照（烘焙）。显示光照贴图和探针提供的间接漫反射贡献。</font>
+ **<font style="color:rgb(51, 51, 51);">Indirect Specular</font>**<font style="color:rgb(51, 51, 51);">：间接镜面光照（反射）。显示反射探针和天空盒提供的间接镜面贡献。</font>
+ **<font style="color:rgb(51, 51, 51);">Shadow Cascades</font>**<font style="color:rgb(51, 51, 51);">：阴影级联可视化。显示每个像素使用的阴影级联级别。</font>

<font style="color:rgb(51, 51, 51);">这些视图可以帮助你诊断光照问题。例如：</font>

+ <font style="color:rgb(51, 51, 51);">如果 Direct Diffuse 全黑，说明光源没有正确照射到物体</font>
+ <font style="color:rgb(51, 51, 51);">如果 Indirect Diffuse 全黑，说明烘焙光照或探针没有正确设置</font>
+ <font style="color:rgb(51, 51, 51);">如果 Indirect Specular 全黑，说明反射探针缺失或未覆盖该区域</font>

<font style="color:rgb(162, 127, 3);"><!-- 这是一张图片，ocr 内容为： --></font>

_<font style="color:rgb(51, 51, 51);">Rendering Debugger 中的光照调试视图</font>_

### <font style="color:rgb(51, 51, 51);">帧调试器中的光照 Pass</font>
<font style="color:rgb(51, 51, 51);">在帧调试器（Frame Debugger）中，你可以看到 URP 渲染场景时的各个 Pass：</font>

1. **<font style="color:rgb(51, 51, 51);">Main Light Shadow Rendering</font>**<font style="color:rgb(51, 51, 51);">：渲染主光源阴影贴图</font>
2. **<font style="color:rgb(51, 51, 51);">Additional Lights Shadow Rendering</font>**<font style="color:rgb(51, 51, 51);">：渲染附加光源阴影贴图</font>
3. **<font style="color:rgb(51, 51, 51);">Forward Rendering</font>**<font style="color:rgb(51, 51, 51);">：前向渲染 Pass（包含所有光照计算）</font>

<font style="color:rgb(51, 51, 51);">通过检查每个 Pass 的输出，你可以定位光照问题的来源。例如，如果阴影贴图全黑，说明光源的阴影设置有问题。</font>

### <font style="color:rgb(51, 51, 51);">光照调试模式</font>
<font style="color:rgb(51, 51, 51);">URP 提供了几种光照调试模式，可以在渲染调试器的 Lighting 面板中找到：</font>

+ **<font style="color:rgb(51, 51, 51);">No Shadows</font>**<font style="color:rgb(51, 51, 51);">：禁用所有阴影</font>
+ **<font style="color:rgb(51, 51, 51);">No Normal Maps</font>**<font style="color:rgb(51, 51, 51);">：禁用法线贴图</font>
+ **<font style="color:rgb(51, 51, 51);">No Ambient</font>**<font style="color:rgb(51, 51, 51);">：禁用环境光</font>
+ **<font style="color:rgb(51, 51, 51);">No Reflections</font>**<font style="color:rgb(51, 51, 51);">：禁用反射</font>

<font style="color:rgb(51, 51, 51);">这些模式可以帮助你隔离问题。例如，如果禁用阴影后光照恢复正常，说明阴影设置有问题。</font>

### <font style="color:rgb(51, 51, 51);">常用调试关键字</font>
<font style="color:rgb(51, 51, 51);">在 Shader 中添加调试输出模式，可以帮助你可视化中间计算结果：</font>

```glsl
// 在 Fragment 函数中添加调试分支
#ifdef DEBUG_DISPLAY
    // 输出法线方向（用于检查法线是否正确）
    return float4(normalWS * 0.5 + 0.5, 1.0);
    
    // 输出光照方向
    // return float4(lightDirectionWS * 0.5 + 0.5, 1.0);
    
    // 输出粗糙度
    // return float4(roughness, roughness, roughness, 1.0);
#endif
```

<font style="color:rgb(51, 51, 51);">在 Unity 中，你可以通过 </font>`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">Window > Analysis > Rendering Debugger > Lighting</font>`<font style="color:rgb(51, 51, 51);"> 启用这些调试视图。</font>

<font style="color:#117CEE;">调试问题当时在前面几节已经搞过了，后面再调试的话用AI协同调试</font>

---

## 七、补充 Pass：深度法线与运动向量

前六个小节让 ForwardLit Pass 拥有了完整的光照能力，但屏幕空间后效（SSAO、运动模糊、TAA）需要**额外的几何数据**：深度、法线、运动向量。这些数据由独立的 Pass 渲染到单独的纹理里。

本节为 MyLit 添加两个 Pass：

+ **DepthNormals Pass**：输出深度 + 世界空间法线（SSAO / SSR 用）
+ **MotionVectors Pass**：输出屏幕空间运动向量（运动模糊 / TAA 用）

---

### 7.1 DepthNormals Pass

#### 它输出什么

+ **深度**：不靠 shader 手写，`ZWrite On` 让光栅化阶段自动把裁剪空间 Z 写进深度缓冲
+ **法线**：片元返回世界空间法线，URP 把它渲进 `_CameraNormalsTexture`

#### 为什么需要它

+ **SSAO**：需要每个像素的法线来计算半球采样方向
+ **SSR（屏幕空间反射）**：需要法线计算反射方向
+ **运动模糊**：需要深度判断物体运动范围

#### MyLit.shader 中的 Pass 定义

```glsl
// ===== Pass 5: 深度 + 法线 [Part5-七] =====
Pass
{
    Name "DepthNormals"
    Tags{"LightMode" = "DepthNormals"}

    ZWrite On
    Cull [_Cull]

    HLSLPROGRAM
    #pragma exclude_renderers gles gles3 glcore
    #pragma target 4.5

    #pragma vertex DepthNormalsVertex
    #pragma fragment DepthNormalsFragment

    #pragma shader_feature_local _ALPHA_CUTOUT
    #pragma shader_feature_local _DOUBLE_SIDED_NORMALS
    #pragma shader_feature_local_fragment _NORMALMAP

    #include "MyLitDepthNormalsPass.hlsl"
    ENDHLSL
}
```

**关键点**：

+ `LightMode` 用 `"DepthNormals"`（URP 内置 Lit 的写法），**不是** `"DepthNormalsOnly"`。后者是 HDRP 的用法，在 URP 里会导致 Pass 不被识别
+ 需要同步 `_ALPHA_CUTOUT` / `_DOUBLE_SIDED_NORMALS` / `_NORMALMAP` 三个关键字，才能和 ForwardLit 的镂空、双面法线、法线贴图表现一致

#### MyLitDepthNormalsPass.hlsl

```glsl
// ===== [Part5-七] 深度 + 法线通道（SSAO / SSR 用）=====
#ifndef MY_LIT_DEPTH_NORMALS_PASS_INCLUDED
#define MY_LIT_DEPTH_NORMALS_PASS_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "MyLitCommon.hlsl"

struct Attributes
{
    float4 positionOS : POSITION;
    float3 normalOS : NORMAL;
    float4 tangentOS : TANGENT;
    float2 uv : TEXCOORD0;
};

struct Interpolators
{
    float4 positionCS : SV_POSITION;
    float2 uv : TEXCOORD0;
    float3 normalWS : TEXCOORD1;
#ifdef _NORMALMAP
    float4 tangentWS : TEXCOORD2;
#endif
};

Interpolators DepthNormalsVertex(Attributes input)
{
    Interpolators output = (Interpolators)0;

    VertexNormalInputs normInputs = GetVertexNormalInputs(input.normalOS, input.tangentOS);

    output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
    output.uv = TRANSFORM_TEX(input.uv, _ColorMap);
    output.normalWS = normInputs.normalWS;

    #ifdef _NORMALMAP
        // GetOddNegativeScale 处理负缩放翻转，不能省
        real sign = input.tangentOS.w * GetOddNegativeScale();
        output.tangentWS = half4(normInputs.tangentWS.xyz, sign);
    #endif

    return output;
}

half4 DepthNormalsFragment(Interpolators input) : SV_TARGET
{
    #ifdef _NORMALMAP
        half3 normalTS = UnpackNormalScale(
            SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, input.uv),
            _NormalStrength);

        // 注意顺序是 tangent / bitangent / normal
        half sgn = input.tangentWS.w;
        half3 bitangent = sgn * cross(input.normalWS.xyz, input.tangentWS.xyz);
        half3 normalWS = TransformTangentToWorld(
            normalTS,
            half3x3(input.tangentWS.xyz, bitangent, input.normalWS.xyz));
    #else
        half3 normalWS = input.normalWS;
    #endif

    #ifdef _ALPHA_CUTOUT
        half alpha = CalculateDotMatrix(input.uv, _DotDensity, _DotRadius,
                                        float2(_DotScaleX, _DotScaleY));
        clip(alpha - _Cutoff);
    #endif

    // 必须归一化，否则插值后的法线长度 < 1，会让 SSAO 半球采样方向偏斜
    return half4(NormalizeNormalPerPixel(normalWS), 0.0);
}

#endif
```

#### 与本教程示例的三处差异

1. **法线输出格式**

   教程示例返回 `normalWS * 0.5 + 0.5`（把 -1~1 映射到 0~1）。**这个在 URP 里不是必需的**：URP 的 `_CameraNormalsTexture` 是带符号格式（SNorm），可以直接存 -1~1 的法线。URP 内置 Lit 的 `DepthNormalsFragment` 就是直接返回 `NormalizeNormalPerPixel(normalWS)`，本项目与官方一致。

2. **TBN 构建方式**

   项目在 `_NORMALMAP` 守卫内才传 `tangentWS`，片元里手写 `cross` 构造 TBN。这和 URP 提供的 `CreateTangentToWorld` 等价，但更省：没法线贴图时省一个插值器。

3. **法线归一化**

   `NormalizeNormalPerPixel(normalWS)` 不能省。插值后法线长度会小于 1，不归一化会让 SSAO 的半球采样方向出现明显偏差。

---

### 7.2 MotionVectors Pass

#### 它输出什么

每个像素在**屏幕空间**上从上一帧到当前帧移动了多少。后处理（运动模糊、TAA）用它判断像素应该往哪个方向拖影。

#### 核心原理

一个像素的运动 = **当前帧 NDC 位置 − 上一帧 NDC 位置**。

当前帧位置手上有（`positionCS`），上一帧位置需要**用当前世界坐标乘上一帧的视图投影矩阵重新投影**。

#### 与教程示例的关键差异（重要）

教程示例是**教学简化版**，直接用会导致编译错误或效果异常。URP 16 的正确做法：

| 项 | 教程示例 | URP 16 正确写法 |
|---|---|---|
| 上一帧视图投影矩阵 | `_PrevViewProjM` ❌ 不存在 | `_PrevViewProjMatrix` |
| 当前帧矩阵 | 用 `positionCS` 直接算 | 需要 `_NonJitteredViewProjMatrix`（非抖动） |
| 上一帧物体矩阵 | 未提 | `UNITY_PREV_MATRIX_M`（物体自身的历史位置） |
| 输出格式 | `float4(ndc, 0, 1)` | `float4(velocity, 0, 0)`，用 URP 辅助函数处理 |
| 关键字 | 未提 | 无需 `_MOTION_VECTORS`，靠 `#include_with_pragmas` 或显式 pragma |

#### MyLit.shader 中的 Pass 定义

```glsl
// ===== Pass 6: 运动向量 [Part5-七] =====
Pass
{
    Name "MotionVectors"
    Tags{"LightMode" = "MotionVectors"}

    ColorMask RG        // 只写 RG，B/A 留 0

    HLSLPROGRAM
    #pragma target 3.5
    #pragma shader_feature_local _ALPHA_CUTOUT

    #pragma vertex Vertex
    #pragma fragment Fragment

    #include "MyLitMotionVectorPass.hlsl"
    ENDHLSL
}
```

**关键点**：

+ `ColorMask RG`：运动向量是二维（UV offset），只占 RG 通道
+ `LightMode` 用 `"MotionVectors"`：这个关键字是 Unity 内建约定，URP 渲染器会据此识别

#### MyLitMotionVectorPass.hlsl

```glsl
// ===== [Part5-七] 运动向量通道（运动模糊 / TAA 用）=====
#ifndef MY_LIT_MOTION_VECTORS_PASS_INCLUDED
#define MY_LIT_MOTION_VECTORS_PASS_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/UnityInput.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/MotionVectorsCommon.hlsl"
#include "MyLitCommon.hlsl"

struct Attributes
{
    float4 positionOS : POSITION;
#ifdef _ALPHA_CUTOUT
    float2 uv : TEXCOORD0;
#endif
};

struct Interpolators
{
    float4 positionCS : SV_POSITION;
    float4 positionCSNoJitter : POSITION_CS_NO_JITTER;
    float4 previousPositionCSNoJitter : PREV_POSITION_CS_NO_JITTER;
#ifdef _ALPHA_CUTOUT
    float2 uv : TEXCOORD0;
#endif
};

Interpolators Vertex(Attributes input)
{
    Interpolators output = (Interpolators)0;
    VertexPositionInputs vpInputs = GetVertexPositionInputs(input.positionOS.xyz);

    // 抖动位置（光栅化用）
    output.positionCS = vpInputs.positionCS;

    // 当前帧非抖动位置：当前 M + 非抖动 VP
    output.positionCSNoJitter = mul(_NonJitteredViewProjMatrix, mul(UNITY_MATRIX_M, input.positionOS));

    // 上一帧位置：上一帧 M + 上一帧 VP
    float4 prevPos = input.positionOS;
    output.previousPositionCSNoJitter = mul(_PrevViewProjMatrix, mul(UNITY_PREV_MATRIX_M, prevPos));

    // 防运动向量纹理缝隙（必须在 positionCS 赋值之后）
    ApplyMotionVectorZBias(output.positionCS);

    #ifdef _ALPHA_CUTOUT
    output.uv = TRANSFORM_TEX(input.uv, _ColorMap);
    #endif

    return output;
}

float4 Fragment(Interpolators input) : SV_TARGET
{
    #ifdef _ALPHA_CUTOUT
    float4 colorSample = SAMPLE_TEXTURE2D(_ColorMap, sampler_ColorMap, input.uv);
    colorSample.a = CalculateDotMatrix(input.uv, _DotDensity, _DotRadius, float2(_DotScaleX, _DotScaleY));
    TestAlphaClip(colorSample);
    #endif

    // CalcNdcMotionVectorFromCsPositions 来自 MotionVectorsCommon.hlsl
    float2 velocity = CalcNdcMotionVectorFromCsPositions(input.positionCSNoJitter, input.previousPositionCSNoJitter);
    return float4(velocity, 0, 0);
}
#endif
```

---

### 7.3 学习总结：运动向量背后的三个知识模块

这一节的代码只有十几行，但每一行背后都依赖一块前置知识。以下是补课内容，方便日后回查。

#### 模块 1：齐次坐标 / NDC / 透视除法

**核心公式**：

```
对象空间 --[M]--> 世界空间 --[VP]--> 裁剪空间 (x,y,z,w) --[÷w]--> NDC --[映射]--> 屏幕像素
```

**必须记住的三件事**：

1. **w 携带深度**。`w_clip = -z_eye`，相机前方的点 w > 0，相机背后的点 w < 0，相机原点 w = 0
2. **看到 NDC 先除以 w**。裁剪空间 `(x,y,z,w)` 除以 w 才得到 NDC `(x/w, y/w, z/w)`
3. **NDC ≠ UV**。NDC 原点在屏幕中心、范围 [-1,1]；UV 原点在角、范围 [0,1]

**投影矩阵第三、四行的来历**：

投影矩阵的最后两行是：

```
[ 0  0  A  B ]
[ 0  0 -1  0 ]
```

+ 第四行的 `-1` 负责生成 w（`w_clip = -z_eye`），透视除法由此产生"近大远小"
+ 第三行的 `A, B` 负责深度重映射。用"近平面映射到 NDC z 一端、远平面映射到另一端"两个边界条件可解出（OpenGL 约定）：

```
A = -(far + near) / (far - near)
B = -2 * far * near / (far - near)
```

**关键结论**：裁剪空间 z 只是参与深度比较的中间量，它**不直接对应距离**。想知道点多远，看 w（即 z_eye），不看 z_clip。

#### 模块 2：URP 内置矩阵体系

顶点从对象空间到裁剪空间只有两跳：`对象 --[M]--> 世界 --[VP]--> 裁剪`。URP 为了省事，把 View 和 Projection 合并成 `_ViewProjMatrix` 系列。

**运动向量需要的四个矩阵**：

| 矩阵 | 含义 | 用途 |
|---|---|---|
| `UNITY_MATRIX_M` | 当前帧，物体 → 世界 | 当前世界位置 |
| `UNITY_PREV_MATRIX_M` | **上一帧**，物体 → 世界 | 物体自身的历史位置 |
| `_NonJitteredViewProjMatrix` | 当前帧，世界 → 裁剪（**无抖动**） | 当前帧屏幕位置 |
| `_PrevViewProjMatrix` | 上一帧，世界 → 裁剪 | 上一帧屏幕位置 |

**为什么要两套位置（当前 vs 上一帧）**：

+ 相机和物体的运动是**两条独立的自由度**。`_PrevViewProjMatrix` 管相机的历史，`UNITY_PREV_MATRIX_M` 管物体的历史，缺一不可
+ 如果只换 VP 而不换 M，物体自身的位移会被完全抹掉

**`mul` 的读法**：

```glsl
mul(VP, mul(M, pos))
//   ↑ 后作用      ↑ 先作用
// 结果 = VP × M × pos
```

矩阵乘法满足结合律，所以 `VP × (M × pos) == (VP × M) × pos`。**读法是"最靠近顶点的先作用"**，和函数嵌套 `A(B(v))` 一致。

**透视投影不可线性叠加**：

正交投影下，相机运动 + 物体运动的屏幕位移可以拆分相加。透视投影下**不行**——因为除以 w 是非线性操作。这是"位移不可简单相加"的根本原因。

#### 模块 3：TAA 抖动（Jitter）

**TAA 原理**：跨帧采样。每帧让投影矩阵带一个亚像素抖动，让同一个物体在多帧里落在略有差异的像素位置，累积后边缘被磨平。

**抖动的两个副作用**：

+ **光栅化必须用抖动位置**：否则 TAA 累积的采样点完全重叠，抗锯齿失效
+ **运动向量必须用非抖动位置**：否则速度图被"抖动伪位移"污染，TAA 会产生鬼影

这就是为什么 `Interpolators` 里要传三个位置字段：

| 字段 | 语义 | 是否参与光栅化 | 用途 |
|---|---|---|---|
| `positionCS` | `SV_POSITION` | ✅ 参与 | 决定像素画在哪 |
| `positionCSNoJitter` | `POSITION_CS_NO_JITTER` | ❌ 不参与位置定位 | 算运动向量（当前帧） |
| `previousPositionCSNoJitter` | `PREV_POSITION_CS_NO_JITTER` | ❌ 不参与位置定位 | 算运动向量（上一帧） |

**`POSITION_CS_NO_JITTER` 的真实作用**：

+ 它**不参与"位置裁剪 + 像素定位"**（那是 `SV_POSITION` 的活儿）
+ 但它**仍然经历顶点 → 插值 → 片元**的完整管线
+ 用它而不用 `TEXCOORD`，是因为 `TEXCOORD` 常是 `half` 精度，小位移会被量化吃掉；而它是 `float` 精度

**jitter 的量级认知**：jitter 是**亚像素级**（约 0.5 像素）。物体慢速运动时真实位移和 jitter 同量级，抖动位置算运动向量会严重污染；快速运动时污染相对小，但仍会累积成残影。**无论快慢，抖动位置算运动向量都是错的。**

#### 模块 4：CalcNdcMotionVectorFromCsPositions 内部做了什么

```
裁剪空间位置 pair
  │  ÷ w
  ▼
NDC pair
  │  相减
  ▼
NDC 位移
  │  1. y 翻转（如果 UNITY_UV_STARTS_AT_TOP）
  │  2. * 0.5
  ▼
UV space offset  ← 存入 _MotionVectorTexture
```

**为什么要 `* 0.5`**：NDC 范围 [-1,1] 长度是 2，UV 范围 [0,1] 长度是 1，缩放比 = 1/2。位移转换时 `+0.5` 的平移项相减抵消，只剩缩放。

**为什么要 y 翻转**：NDC 的 y 向上为正；但 D3D（Windows）的 UV 原点在左上、v 向下为正。`UNITY_UV_STARTS_AT_TOP` 宏为真时必须翻转，否则垂直方向的运动模糊方向会反。

**为什么后处理要 UV space**：后处理采样历史帧用的是 UV（`SAMPLE_TEXTURE2D`），直接给 UV offset 最省事。

#### 模块 5：ApplyMotionVectorZBias

**作用**：把物体在裁剪空间的 z 往相机方向推一个极小量，防止运动向量纹理出现**缝隙**。

**缝隙的成因**：GPU 光栅化对三角形边缘的像素归属判定存在边界情况，某些像素可能被相邻的所有三角形都判为"不属于"，导致 `_MotionVectorTexture` 上出现空洞。后处理读到空洞位置的垃圾值会算出错误位移。

**实现原理**：

```glsl
#if defined(UNITY_REVERSED_Z)
positionCS.z -= unity_MotionVectorsParams.z * positionCS.w;
#else
positionCS.z += unity_MotionVectorsParams.z * positionCS.w;
#endif
```

**为什么乘 `positionCS.w`**：`positionCS.z` 是裁剪空间 z，透视除法后才是 NDC。要让 NDC 上变化固定量 `Δ`，分子必须加 `Δ * w`。乘 w 保证了**所有距离的物体偏移量透视一致**。

**与 `ApplyShadowBias` 的对比**：

| | ApplyShadowBias | ApplyMotionVectorZBias |
|---|---|---|
| 防什么 | Shadow acne（阴影自遮挡条纹） | MotionVector gaps（运动向量纹理缝隙）|
| 偏移方向 | 沿光源方向 | 沿相机方向 |
| 相同原理 | 都是"给深度加偏移" | 同左 |

**注意**：删掉它通常不会立刻出问题，它是一道防御硬件边缘情况的保险。但如果开启 TAA，缝隙会每帧被历史累积放大成残影，那时它就很关键。

---

### 7.4 验证步骤

写完两个 Pass 后，按下面顺序验证：

1. **编译**：Unity Console 无报错（尤其注意 hlsl 结尾的 `#endif` 有没有漏）
2. **Frame Debugger**：Window → Analysis → Frame Debugger，分别找到 `DepthNormals` 和 `MotionVectors` 两个 draw call，确认被绘制
3. **DepthNormals 验证**：开 SSAO Renderer Feature，观察镂空处 / 凹凸处的遮挡是否正确；用 Rendering Debugger 的 Normal 视图对比
4. **MotionVectors 验证**：开 URP 的 Motion Blur（Volume 里加 Motion Blur Override），物体快速移动时应出现拖影；若拖影为 0 或乱飞，检查矩阵用对没有

**常见问题**：

+ 看不到 MotionVectors draw call → 检查 `LightMode` 标签是否为 `"MotionVectors"`
+ 拖影方向反了 → 检查 `UNITY_UV_STARTS_AT_TOP` 的处理（本项目直接调用 URP 辅助函数，已内置处理）
+ 编译报 `_PrevViewProjM undeclared` → 教程示例的旧名字，应改成 `_PrevViewProjMatrix`

---

## <font style="color:rgb(51, 51, 51);">八、性能考虑</font>
<font style="color:rgb(51, 51, 51);">添加这些光照功能后，着色器的性能开销会增加。以下是一些优化建议：</font>

### <font style="color:rgb(51, 51, 51);">1. 附加光源的性能影响量化</font>
<font style="color:rgb(51, 51, 51);">每个附加光源对性能的影响包括：</font>

+ **<font style="color:rgb(51, 51, 51);">Draw Call</font>**<font style="color:rgb(51, 51, 51);">：每个附加光源增加 1 次 Draw Call（全屏四边形）</font>
+ **<font style="color:rgb(51, 51, 51);">顶点计算</font>**<font style="color:rgb(51, 51, 51);">：Per Vertex 模式下，每个光源增加顶点级别的光照计算</font>
+ **<font style="color:rgb(51, 51, 51);">像素计算</font>**<font style="color:rgb(51, 51, 51);">：Per Pixel 模式下，每个光源增加像素级别的光照计算（包括 BRDF、阴影、衰减）</font>
+ **<font style="color:rgb(51, 51, 51);">带宽</font>**<font style="color:rgb(51, 51, 51);">：每个光源需要读取光源数据（位置、颜色、衰减）</font>

<font style="color:rgb(51, 51, 51);">在移动设备上，每个附加光源可能增加 </font>**<font style="color:rgb(51, 51, 51);">0.5-2ms</font>**<font style="color:rgb(51, 51, 51);"> 的渲染时间（取决于分辨率和 GPU）。建议移动端最多使用 1-2 个附加光源。</font>

### <font style="color:rgb(51, 51, 51);">2. shader_feature vs multi_compile 的选择策略</font>
| **<font style="color:rgb(51, 51, 51);">指令</font>** | **<font style="color:rgb(51, 51, 51);">编译时机</font>** | **<font style="color:rgb(51, 51, 51);">适用场景</font>** |
| :--- | :--- | :--- |
| `<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">shader_feature</font>` | <font style="color:rgb(51, 51, 51);">只编译被实际使用的变体</font> | <font style="color:rgb(51, 51, 51);">材质级别的可选功能</font> |
| `<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">multi_compile</font>` | <font style="color:rgb(51, 51, 51);">编译所有可能的变体</font> | <font style="color:rgb(51, 51, 51);">引擎级功能（光源、阴影等）</font> |


<font style="color:rgb(51, 51, 51);">对于材质级别的功能（如法线贴图、遮挡贴图），使用 </font>`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">shader_feature_local</font>`<font style="color:rgb(51, 51, 51);"> 可以显著减少变体数量。对于引擎级功能（如光源、阴影），必须使用 </font>`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">multi_compile</font>`<font style="color:rgb(51, 51, 51);"> 以确保变体始终可用。</font>

### <font style="color:rgb(51, 51, 51);">3. LOD 级别的设置方法</font>
<font style="color:rgb(51, 51, 51);">为着色器设置不同的 LOD（Level of Detail）级别，远处的物体使用更简单的着色器变体：</font>

```glsl
SubShader {
  LOD 300  // 高质量版本（所有功能）
    ...
  }

SubShader {
  LOD 200  // 中等质量版本（简化光照）
    ...
  }

SubShader {
  LOD 100  // 低质量版本（仅主光源）
    ...
  }
```

<font style="color:rgb(51, 51, 51);">在 Unity 中，你可以通过 </font>`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">Project Settings > Quality > LOD Bias</font>`<font style="color:rgb(51, 51, 51);"> 控制 LOD 切换的距离。</font>

### <font style="color:rgb(51, 51, 51);">4. 移动端特定的优化建议</font>
+ **<font style="color:rgb(51, 51, 51);">使用 Per Vertex 光照模式</font>**<font style="color:rgb(51, 51, 51);">：在 URP Asset 中将 Additional Lights 设置为 Per Vertex</font>
+ **<font style="color:rgb(51, 51, 51);">减少附加光源数量</font>**<font style="color:rgb(51, 51, 51);">：移动端最多 1-2 个附加光源</font>
+ **<font style="color:rgb(51, 51, 51);">使用烘焙光照</font>**<font style="color:rgb(51, 51, 51);">：尽可能将光源烘焙，减少实时光源</font>
+ **<font style="color:rgb(51, 51, 51);">禁用软阴影</font>**<font style="color:rgb(51, 51, 51);">：使用硬阴影或禁用阴影</font>
+ **<font style="color:rgb(51, 51, 51);">降低 Cookie 分辨率</font>**<font style="color:rgb(51, 51, 51);">：使用 256×256 或更小的 Cookie 纹理</font>
+ **<font style="color:rgb(51, 51, 51);">使用 Half 精度</font>**<font style="color:rgb(51, 51, 51);">：在 Shader 中使用 </font>`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">half</font>`<font style="color:rgb(51, 51, 51);"> 类型代替 </font>`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">float</font>`<font style="color:rgb(51, 51, 51);"> 进行中间计算</font>

### <font style="color:rgb(51, 51, 51);">5. 变体数量控制</font>
<font style="color:rgb(51, 51, 51);">过多的着色器变体会增加编译时间和包体大小。使用 </font>`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">shader_feature_local</font>`<font style="color:rgb(51, 51, 51);"> 代替 </font>`<font style="color:rgb(51, 51, 51);background-color:rgb(243, 244, 244);">shader_feature</font>`<font style="color:rgb(51, 51, 51);"> 可以限制变体的传播范围：</font>

```glsl
// 只在当前着色器中生成变体
#pragma shader_feature_local _NORMALMAP

// 全局生成变体（可能影响其他着色器）
#pragma shader_feature _NORMALMAP
```

---

## <font style="color:rgb(51, 51, 51);">九、Part 5 完整修改清单</font>
<font style="color:rgb(51, 51, 51);">以下是本教程中所有需要进行的修改的完整检查清单。使用此清单确保你没有遗漏任何步骤。</font>

### <font style="color:rgb(51, 51, 51);">MyLit.shader 修改清单</font>
```glsl
Pass {
  Name "ForwardLit"
    ...
    HLSLPROGRAM
    // 现有关键字保持不变...

    // □ 添加以下新关键字（位于 _SHADOWS_SOFT 之后）
    // □ #pragma multi_compile _ _ADDITIONAL_LIGHTS
    // □ #pragma multi_compile_fragment _ _ADDITIONAL_LIGHTS_SHADOWS
    // □ #pragma multi_compile_fragment _ _REFLECTION_PROBE_BLENDING
    // □ #pragma multi_compile_fragment _ _REFLECTION_PROBE_BOX_PROJECTION
    // □ #pragma multi_compile_fragment _ _LIGHT_LAYERS
    // □ #pragma multi_compile_fragment _ _SCREEN_SPACE_OCCLUSION
    // □ #pragma multi_compile _ _MAIN_LIGHT_COOKIE
    // □ #pragma multi_compile _ _ADDITIONAL_LIGHTS_COOKIE

    #pragma vertex Vertex
    #pragma fragment Fragment
    #include "MyLitForwardLitPass.hlsl"
    ENDHLSL
  }

// □ 在 ShadowCaster Pass 之后添加 DepthNormals Pass
// □ 在 DepthNormals Pass 之后添加 MotionVectors Pass
```

**<font style="color:rgb(51, 51, 51);">Properties 修改：</font>**

```glsl
// □ 在 _ClearCoatSmoothness 属性之后添加
// □ [NoScaleOffset] _OcclusionMap("Occlusion", 2D) = "white" {}
// □ _OcclusionStrength("Occlusion strength", Range(0, 1)) = 1
```

### <font style="color:rgb(51, 51, 51);">MyLitCommon.hlsl 修改清单</font>
```glsl
// □ 在 CBUFFER(UnityPerMaterial) 中添加纹理声明
// □ TEXTURE2D(_OcclusionMap); SAMPLER(sampler_OcclusionMap);

// □ 在 CBUFFER 中添加变量
// □ float _OcclusionStrength;
```

### <font style="color:rgb(51, 51, 51);">MyLitForwardLitPass.hlsl 修改清单</font>
```glsl
// □ 在 Attributes 结构体中添加
// □ float2 uv2 : TEXCOORD1;

// □ 在 Interpolators 结构体中添加
// □ float2 uv2 : TEXCOORD1;

// □ 在 Vertex 函数中添加
// □ output.uv2 = input.uv2;

// □ 在 Fragment 函数中添加
// □ lightingInput.bakedGI = SampleLightmap(input.uv2, normalWS);
// □ surfaceInput.occlusion = SAMPLE_TEXTURE2D(_OcclusionMap, sampler_OcclusionMap, uv).g * _OcclusionStrength;
```

### <font style="color:rgb(51, 51, 51);">新建文件清单</font>
```glsl
// □ 创建 MyLitDepthNormalsPass.hlsl
// □ 创建 MyLitMotionVectorsPass.hlsl
```

### <font style="color:rgb(51, 51, 51);">场景设置清单</font>
```glsl
// □ 在场景中添加反射探针（GameObject > Light > Reflection Probe）
// □ 在需要烘焙的物体上启用 Static 和 Contribute GI
// □ 将光源设置为 Baked 或 Mixed 模式
// □ 打开 Window > Rendering > Lighting，点击 Generate Lighting
// □ 在 URP Asset 中配置 Additional Lights 设置
```

---

## <font style="color:rgb(51, 51, 51);">结语</font>
<font style="color:rgb(51, 51, 51);">恭喜！你现在拥有了一个功能完整的 PBR 着色器，支持：</font>

+ <font style="color:rgb(51, 51, 51);">✅</font><font style="color:rgb(51, 51, 51);"> </font>**<font style="color:rgb(51, 51, 51);">多光源</font>**<font style="color:rgb(51, 51, 51);">：方向光、点光源、聚光灯的完整支持</font>
+ <font style="color:rgb(51, 51, 51);">✅</font><font style="color:rgb(51, 51, 51);"> </font>**<font style="color:rgb(51, 51, 51);">附加光源阴影</font>**<font style="color:rgb(51, 51, 51);">：多个光源的阴影投射</font>
+ <font style="color:rgb(51, 51, 51);">✅</font><font style="color:rgb(51, 51, 51);"> </font>**<font style="color:rgb(51, 51, 51);">光照衰减</font>**<font style="color:rgb(51, 51, 51);">：物理正确的平方反比衰减</font>
+ <font style="color:rgb(51, 51, 51);">✅</font><font style="color:rgb(51, 51, 51);"> </font>**<font style="color:rgb(51, 51, 51);">烘焙光照</font>**<font style="color:rgb(51, 51, 51);">：光照贴图和光照探针的完整支持</font>
+ <font style="color:rgb(51, 51, 51);">✅</font><font style="color:rgb(51, 51, 51);"> </font>**<font style="color:rgb(51, 51, 51);">三种混合模式</font>**<font style="color:rgb(51, 51, 51);">：Baked Indirect / Shadowmask / Subtractive</font>
+ <font style="color:rgb(51, 51, 51);">✅</font><font style="color:rgb(51, 51, 51);"> </font>**<font style="color:rgb(51, 51, 51);">环境光遮挡</font>**<font style="color:rgb(51, 51, 51);">：遮挡贴图和强度控制</font>
+ <font style="color:rgb(51, 51, 51);">✅</font><font style="color:rgb(51, 51, 51);"> </font>**<font style="color:rgb(51, 51, 51);">反射探针</font>**<font style="color:rgb(51, 51, 51);">：Baked / Realtime / Custom 三种类型</font>
+ <font style="color:rgb(51, 51, 51);">✅</font><font style="color:rgb(51, 51, 51);"> </font>**<font style="color:rgb(51, 51, 51);">Box Projection</font>**<font style="color:rgb(51, 51, 51);">：正确的有限空间反射</font>
+ <font style="color:rgb(51, 51, 51);">✅</font><font style="color:rgb(51, 51, 51);"> </font>**<font style="color:rgb(51, 51, 51);">光源 Cookie</font>**<font style="color:rgb(51, 51, 51);">：方向光、点光源、聚光灯的 Cookie 支持</font>
+ <font style="color:rgb(51, 51, 51);">✅</font><font style="color:rgb(51, 51, 51);"> </font>**<font style="color:rgb(51, 51, 51);">深度法线 Pass</font>**<font style="color:rgb(51, 51, 51);">：为 SSAO 和屏幕空间效果提供法线数据</font>
+ <font style="color:rgb(51, 51, 51);">✅</font><font style="color:rgb(51, 51, 51);"> </font>**<font style="color:rgb(51, 51, 51);">运动向量 Pass</font>**<font style="color:rgb(51, 51, 51);">：为运动模糊提供运动数据</font>
+ <font style="color:rgb(51, 51, 51);">✅</font><font style="color:rgb(51, 51, 51);"> </font>**<font style="color:rgb(51, 51, 51);">光源层级</font>**<font style="color:rgb(51, 51, 51);">：让特定光源只影响特定物体</font>
+ <font style="color:rgb(51, 51, 51);">✅</font><font style="color:rgb(51, 51, 51);"> </font>**<font style="color:rgb(51, 51, 51);">调试工具</font>**<font style="color:rgb(51, 51, 51);">：Rendering Debugger 和 Frame Debugger 的使用</font>
+ <font style="color:rgb(51, 51, 51);">✅</font><font style="color:rgb(51, 51, 51);"> </font>**<font style="color:rgb(51, 51, 51);">性能优化</font>**<font style="color:rgb(51, 51, 51);">：移动端优化策略和变体控制</font>

<font style="color:rgb(51, 51, 51);">在下一个教程中，我们将探索</font>**<font style="color:rgb(167, 167, 167);"></font>****<font style="color:rgb(51, 51, 51);">高级 URP 特性</font>**<font style="color:rgb(51, 51, 51);">，包括：</font>

+ <font style="color:rgb(51, 51, 51);">屏幕空间环境光遮蔽（SSAO）</font>
+ <font style="color:rgb(51, 51, 51);">屏幕空间反射（SSR）</font>
+ <font style="color:rgb(51, 51, 51);">后处理效果集成</font>
+ <font style="color:rgb(51, 51, 51);">自定义渲染 Pass</font>
+ <font style="color:rgb(51, 51, 51);">法线贴图混合技术</font>
+ <font style="color:rgb(51, 51, 51);">细节贴图（Detail Maps）</font>

<font style="color:rgb(51, 51, 51);">感谢阅读，去制作游戏吧！</font>

---

**<font style="color:rgb(119, 119, 119);">参考链接</font>**<font style="color:rgb(119, 119, 119);">：</font>

+ <font style="color:rgb(119, 119, 119);">原文：</font>[<font style="color:rgb(65, 131, 196);">Writing Unity URP Shaders with Code (Part 5)</font>](https://nedmakesgames.medium.com/)
+ <font style="color:rgb(119, 119, 119);">作者：NedMakesGames</font>

<font style="color:rgb(119, 119, 119);">如果你喜欢本教程，请考虑关注作者，以便在下一部分发布时收到邮件通知。</font>

<font style="color:rgb(119, 119, 119);">如果你有任何问题，欢迎在评论区留言或通过社交媒体联系作者。</font>

