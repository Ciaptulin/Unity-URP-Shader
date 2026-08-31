using UnityEditor;
using UnityEngine;
using UnityEngine.Rendering;

public class MyLitCustomInspector : ShaderGUI
{
    public enum SurfaceType
    {
        Opaque, TransparentBlend, TransparentCutout
    }
    public enum FaceRenderingMode
    {
        // 近正面，不裁剪，双面法线
        FrontOnly, NoCulling, DoubleSided
    }
    public enum BlendType
    {
        Alpha, Premultiplied, Additive, Multiply
    }

    // 解决切换着色器后，在操作下拉菜单前材质无法初始化的问题
    public override void AssignNewShaderToMaterial(Material material, Shader oldShader, Shader newShader)
    {
        base.AssignNewShaderToMaterial(material, oldShader, newShader);

        if(newShader.name == "Custom/MyLit")
        {
            UpdateSurfaceType(material);
        }
    }

    // 针对Unity2022材质变体不会正常在材质属性发生变化时调用 UpdateSurfaceType(material)
#if UNITY_2022_1_OR_NEWER
    public override void ValidateMaterial(Material material)
    {
        base.ValidateMaterial(material);
        UpdateSurfaceType(material);
    }
#endif
    public override void OnGUI(MaterialEditor materialEditor, MaterialProperty[] properties)
    {
        // 找到_Cutoff属性  当然你也可以用弱变量类型var 第三个参数为false，找不到返回null
        MaterialProperty cutoffProp = FindProperty("_Cutoff", properties, false);

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
        // 私自加料，在裁切模式下出现滑条
        // 获取当前材质，判断它是不是裁切模式
        float surfaceType = material.GetFloat("_SurfaceType");
        // 只有当前材质是"TransparentCutout"(值为2)时才显示这个滑条
        if (surfaceType == (int)SurfaceType.TransparentCutout) // 避免硬编码，改用枚举常量
        {
            materialEditor.RangeProperty(cutoffProp,"Alpha cutout threshold");
        }

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

        // 绘制默认的检视面板，包含你材质中所有没有标记HideInInspector属性的其它属性
        // 这个函数移动位置了，为了在法线贴图更改时调用 UpdateSurfaceType
        base.OnGUI(materialEditor, properties);

        if (EditorGUI.EndChangeCheck())
        {
            UpdateSurfaceType(material);
        }
    }

    private void UpdateSurfaceType(Material material)
    {
        // 未分配法线贴图纹理时禁用一个关键字
        if(material.GetTexture("_NormalMap") == null)
        {
            material.DisableKeyword("_NORMALMAP");
        }
        else
        {
            material.EnableKeyword("_NORMALMAP");
        }

        SurfaceType surface = (SurfaceType)material.GetFloat("_SurfaceType");
        // 设置排队序号
        switch (surface)
        {
            case SurfaceType.Opaque: // 不透明
                material.renderQueue = (int)RenderQueue.Geometry;
                material.SetOverrideTag("RenderType", "Opaque");
                break;
            case SurfaceType.TransparentCutout: // 透明裁切/镂空
                material.renderQueue = (int)RenderQueue.AlphaTest;
                material.SetOverrideTag("RenderType", "TransparentCutout");
                break;
            case SurfaceType.TransparentBlend: // 透明混合/半透明
                material.renderQueue = (int)RenderQueue.Transparent;
                material.SetOverrideTag("RenderType", "Transparent");
                break;
        }
        BlendType blend = (BlendType)material.GetFloat("_BlendType");
        // 设置颜色怎么叠和深度怎么写
        switch (surface)
        {   // 情况A Opaque和TransparentCutout 不透明和镂空
            case SurfaceType.Opaque:
            case SurfaceType.TransparentCutout:
                // 设置ZWrite和Blend属性
                material.SetInt("_SourceBlend", (int)BlendMode.One);  
                material.SetInt("_DestBlend", (int)BlendMode.Zero);
                // 引入Unity.Rendering命名空间，提供混合模式的便捷枚举
                material.SetInt("_ZWrite", 1);
                // // 禁用阴影投射Pass (Shadow Caster Pass)
                // material.SetShaderPassEnabled("ShadowCaster", true);
                break;
            // 情况B TransparentBlend 半透明混合
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
                // 最开始是半透明混合部分的，被挤压到分支末尾了
                material.SetInt("_ZWrite", 0);
                // material.SetShaderPassEnabled("ShadowCaster", false);
                break;
        }
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
        // 根据清漆强度是否大于0来决定启用/禁用关键字
        if(material.GetFloat("_ClearCoatStrength") > 0)
        {
            material.EnableKeyword("_CLEARCOATMAP");
        }
        else
        {
            material.DisableKeyword("_CLEARCOATMAP");
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

        // 更新Cull属性并启用或禁用关键字_DOUBLE_SIDED_NORMALS
        FaceRenderingMode faceRenderingMode = (FaceRenderingMode)material.GetFloat("_FaceRenderingMode");
        // 设置CullMode开关
        if(faceRenderingMode == FaceRenderingMode.FrontOnly)
        {
            material.SetInt("_Cull", (int)UnityEngine.Rendering.CullMode.Back);
        }
        else
        {
            material.SetInt("_Cull", (int)UnityEngine.Rendering.CullMode.Off);
        }
        // 进一步通过_DOUBLE_SIDED_NORMALS（双面法线）关键字在不剔除即Off的情况下细分开启和关闭法线翻转
        if(faceRenderingMode == FaceRenderingMode.DoubleSided)
        {
            material.EnableKeyword("_DOUBLE_SIDED_NORMALS");
        }
        else
        {
            material.DisableKeyword("_DOUBLE_SIDED_NORMALS");
        }
    }
}
