Shader "Custom/MyLit"
{
    Properties{
        [Header(Surface options)]  // 创建文本头部
        // [MainTexture] and [MainColor] allow Material.mainTexture and Material.color to use the correct properties
        [MainTexture] _ColorMap("Color", 2D) = "white" {}
        [MainColor] _ColorTint("Tint", Color) = (1,1,1,1)
        // 定义一个滑条，用来控制透明度裁切的阈值
        [HideInInspector] _Cutoff("Alpha cutout threshold", Range(0,1)) = 0.5
        _Smoothness("Smoothness", Float) = 0

        _DotDensity("Dot Density", Float) = 10
        _DotRadius("Dot Radius", Range(0,0.5)) = 0.2
        
        _DotScaleX("Dot Scale X", Range(0.1, 5)) = 1
        _DotScaleY("Dot Scale Y", Range(0.1, 5)) = 1


        // [Enum(UnityEngine.Rendering.CullMode)] _Cull("Cull mode", Float) = 2
        // 替换原本的枚举属性，枚举交由代码处理
        [HideInInspector] _Cull("Cull mode", Float) = 2  // 2 is "Back"
        [HideInInspector] _SourceBlend("Source blend", Float) = 0
        [HideInInspector] _DestBlend("Destination blend", Float) = 0
        [HideInInspector] _ZWrite("ZWrite", Float) = 0

        [HideInInspector] _SurfaceType("Surface type", Float) = 0
        [HideInInspector] _FaceRenderingMode("Face rendering type", Float) = 0

        
    }
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
        Cull[_Cull]
        HLSLPROGRAM // Begin HLSL code
            #define _SPECULAR_COLOR
            #pragma shader_feature_local _ALPHA_CUTOUT
            #pragma shader_feature_local _DOUBLE_SIDED_NORMALS
#if UNITY_VERSION >= 202120
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
#else
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
#endif
            #pragma multi_compile_fragment _ _SHADOWS_SOFT // 只影响片元
            // Register our programmable stage functions
            #pragma vertex Vertex
            #pragma fragment Fragment

            // Include our code file
            #include "MyLitForwardLitPass.hlsl"
        ENDHLSL
        }
        Pass{
        Name "ShadowCaster" // For debugging
        Tags{"LightMode" = "ShadowCaster"}

        ColorMask 0
        Cull[_Cull]

        HLSLPROGRAM // Begin HLSL code
            // Register our programmable stage functions
            #pragma shader_feature_local _ALPHA_CUTOUT
            #pragma shader_feature_local _DOUBLE_SIDED_NORMALS

            #pragma vertex Vertex
            #pragma fragment Fragment

            // Include our code file
            #include "MyLitShadowCasterPass.hlsl"
        ENDHLSL
        }
    }
    CustomEditor "MyLitCustomInspector"
}
