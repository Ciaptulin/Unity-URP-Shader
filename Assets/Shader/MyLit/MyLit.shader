Shader "Custom/MyLit"
{
    Properties{
        [Header(Surface options)]  // 创建文本头部
        // [MainTexture] and [MainColor] allow Material.mainTexture and Material.color to use the correct properties
        [MainTexture] _ColorMap("Color", 2D) = "white" {}
        [MainColor] _ColorTint("Tint", Color) = (1,1,1,1)
        // 定义一个滑条，用来控制透明度裁切的阈值
        [HideInInspector] _Cutoff("Alpha cutout threshold", Range(0,1)) = 0.5
        [NoScaleOffset][Normal] _NormalMap("Normal", 2D) = "bump" {}
        _NormalStrength("Normal strength", Range(0, 1)) = 1
        [NoScaleOffset] _MetalnessMask("Metalness mask", 2D) = "white" {}
        _Metalness("Metalness", Range(0,1)) = 0
        [Toggle(_SPECULAR_SETUP)] _SpecularSetupToggle("Use specular workflow", Float) = 0
        [Toggle(_ROUGHNESS_SETUP)] _RoughnessSetupToggle("Use roughness texture", Float) = 0
        [NoScaleOffset] _SpecularMap("Specular map", 2D) = "white" {}
        _SpecularTint("Specular tint", Color) = (1,1,1,1)
        [NoScaleOffset] _SmoothnessMask("Smoothness mask", 2D) = "white" {}
        _Smoothness("Smoothness", Range(0,1)) = 0.5
        [NoScaleOffset] _EmissionMap("Emission map", 2D) = "white" {}
        [HDR]_EmissionTint("Emission tint", Color) = (0,0,0,0)
        [NoScaleOffset] _ParallaxMap("Height/displacement map", 2D) = "white" {}
        _ParallaxStrength("Parallax strength", Range(0,1)) = 0.005
        [NoScaleOffset] _ClearCoatMask("Clear coat mask", 2D) = "white" {}
        _ClearCoatStrength("Clear coat strength", Range(0,1)) = 0
        [NoScaleOffset] _ClearCoatSmoothnessMask("Clear coat smoothness mask", 2D) = "white" {}
        _ClearCoatSmoothness("Clear coat smoothness", Range(0,1)) = 0

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
        [HideInInspector] _BlendType("Blend type", Float) = 0
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
            // #define _SPECULAR_COLOR // 切换为 PBR，默认包含镜面高光，此部分不再需要
            //#define _NORMALMAP
            #pragma shader_feature_local_fragment _NORMALMAP
            // #define _CLEARCOATMAP
            #pragma shader_feature_local _CLEARCOATMAP
            #pragma shader_feature_local _ALPHA_CUTOUT
            #pragma shader_feature_local _DOUBLE_SIDED_NORMALS
            // #define _SPECULAR_SETUP // 设置了Toggle属性，这里被变体替换
            #pragma shader_feature_local_fragment _SPECULAR_SETUP
            // 这里我主动适配了粗糙度贴图
            #pragma shader_feature_local_fragment _ROUGHNESS_SETUP
            #pragma shader_feature_local_fragment _ALPHAPREMULTIPLY_ON

#if UNITY_VERSION >= 202120
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
#else
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
#endif
            #pragma multi_compile_fragment _ _SHADOWS_SOFT // 只影响片元
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
