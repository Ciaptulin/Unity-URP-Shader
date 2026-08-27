using System.Net.NetworkInformation;
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
        MaterialEditor.BeginProperty(faceProp);
#endif
        faceProp.floatValue = (int)(FaceRenderingMode)EditorGUILayout.EnumPopup("Face rendering mode", (FaceRenderingMode)faceProp.floatValue);
#if UNITY_2022_1_OR_NEWER
        MaterialEditor.EndProperty();
#endif

        if (EditorGUI.EndChangeCheck())
        {
            UpdateSurfaceType(material);
        }
        // 绘制默认的检视面板，包含你材质中所有没有标记HideInInspector属性的其它属性
        base.OnGUI(materialEditor, properties);

    }

    private void UpdateSurfaceType(Material material)
    {
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
                material.SetInt("_SourceBlend", (int)BlendMode.SrcAlpha);
                material.SetInt("_DestBlend", (int)BlendMode.OneMinusSrcAlpha);
                material.SetInt("_ZWrite", 0);
                // material.SetShaderPassEnabled("ShadowCaster", false);
                break;
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
