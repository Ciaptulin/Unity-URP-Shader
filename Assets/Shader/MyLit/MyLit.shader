Shader "Custom/MyLit"
{
    Properties
    {
        [Header(Surface options)]  // 创建文本头部
        // [MainTexture] and [MainColor] allow Material.mainTexture and Material.color to use the correct properties
        [MainTexture] _ColorMap("颜色贴图", 2D) = "white" {}
        [MainColor] _ColorTint("Tint", Color) = (1,1,1,1)
        // 透明度裁切阈值滑条
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
        [Toggle(_EMISSION)] _EmissionToggle("自发光", Float) = 0
        [NoScaleOffset] _EmissionMap("Emission map", 2D) = "white" {}
        [HDR]_EmissionTint("Emission tint", Color) = (0,0,0,0)
        [NoScaleOffset] _ParallaxMap("Height/displacement map", 2D) = "white" {}
        _ParallaxStrength("Parallax strength", Range(0,1)) = 0.005
        [NoScaleOffset] _ClearCoatMask("Clear coat mask", 2D) = "white" {}
        _ClearCoatStrength("Clear coat strength", Range(0,1)) = 0
        [NoScaleOffset] _ClearCoatSmoothnessMask("Clear coat smoothness mask", 2D) = "white" {}
        _ClearCoatSmoothness("Clear coat smoothness", Range(0,1)) = 0

        // 程序化点阵镂空
        _DotDensity("Dot Density", Float) = 10
        _DotRadius("Dot Radius", Range(0,0.5)) = 0.2
        _DotScaleX("Dot Scale X", Range(0.1, 5)) = 1
        _DotScaleY("Dot Scale Y", Range(0.1, 5)) = 1

        // 遮挡贴图
        [Header(Occlusion)]
        [Toggle(_OCCLUSIONMAP)] _OcclusionToggle("使用遮挡贴图", Float) = 0
        [NoScaleOffset] _OcclusionMap("遮挡贴图", 2D) = "white" {}
        _OcclusionStrength("遮挡强度", Range(0,1)) = 1

        // 以下由自定义 Inspector 控制，不直接在面板显示
        [HideInInspector] _Cull("Cull mode", Float) = 2  // 2 is "Back"
        [HideInInspector] _SourceBlend("Source blend", Float) = 1
        [HideInInspector] _DestBlend("Destination blend", Float) = 0
        [HideInInspector] _ZWrite("ZWrite", Float) = 1

        [HideInInspector] _SurfaceType("Surface type", Float) = 0
        [HideInInspector] _BlendType("Blend type", Float) = 0
        [HideInInspector] _FaceRenderingMode("Face rendering type", Float) = 0

        [HideInInspector][NoScaleOffset] unity_Lightmaps("unity_Lightmaps", 2DArray) = "" {}
        [HideInInspector][NoScaleOffset] unity_LightmapsInd("unity_LightmapsInd", 2DArray) = "" {}
        [HideInInspector][NoScaleOffset] unity_ShadowMasks("unity_ShadowMasks", 2DArray) = "" {}
    }

    SubShader
    {
        Tags{"RenderPipeline" = "UniversalPipeline" "RenderType" = "Opaque" }

        // ===== Pass 1: 前向光照主体 [Part2 → Part5] =====
        Pass
        {
            Name "ForwardLit"  // For debugging
            Tags{"LightMode" = "UniversalForward"}

            // 引用属性值而非写死，解决不透明材质未渲染的问题
            Blend [_SourceBlend] [_DestBlend]
            ZWrite [_ZWrite]
            Cull[_Cull]

            HLSLPROGRAM
            // 材质特性关键字（按需编译）
            #pragma shader_feature_local_fragment _NORMALMAP
            #pragma shader_feature_local _CLEARCOATMAP
            #pragma shader_feature_local _ALPHA_CUTOUT
            #pragma shader_feature_local _DOUBLE_SIDED_NORMALS
            #pragma shader_feature_local_fragment _SPECULAR_SETUP
            #pragma shader_feature_local_fragment _ROUGHNESS_SETUP
            #pragma shader_feature_local_fragment _ALPHAPREMULTIPLY_ON

            // 主光源阴影
#if UNITY_VERSION >= 202120
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
#else
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
#endif
            #pragma multi_compile_fragment _ _SHADOWS_SOFT  // 只影响片元

            // 附加光源 [Part5-一]
            #pragma multi_compile _ _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS

            // 光源 Cookie [Part5-五]
            #pragma multi_compile _ _MAIN_LIGHT_COOKIE
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_COOKIE

            // 反射探针 [Part5-四]
            #pragma multi_compile_fragment _ _REFLECTION_PROBE_BLENDING
            #pragma multi_compile_fragment _ _REFLECTION_PROBE_BOX_PROJECTION
            // 光源层级
            #pragma multi_compile_fragment _ _LIGHT_LAYERS
            // 屏幕空间遮挡 [Part5-三]
            #pragma multi_compile_fragment _ _SCREEN_SPACE_OCCLUSION

            // Unity 内置关键字 - 烘焙光照必须 [Part5-二]
            #pragma multi_compile _ DIRLIGHTMAP_COMBINED
            #pragma multi_compile _ LIGHTMAP_ON
            #pragma multi_compile _ DYNAMICLIGHTMAP_ON
            #pragma multi_compile _ LIGHTMAP_SHADOW_MIXING
            #pragma multi_compile _ SHADOWS_SHADOWMASK
            #pragma shader_feature_local_fragment _EMISSION
            #pragma shader_feature_local_fragment _OCCLUSIONMAP

            // 调试：输出烘焙 GI 为灰度 [Part5-六]
            #pragma multi_compile _ _DEBUG_BAKED_GI

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

        // ===== Pass 2: 阴影投射 [Part2] =====
        Pass
        {
            Name "ShadowCaster"  // For debugging
            Tags{"LightMode" = "ShadowCaster"}

            ColorMask 0
            Cull[_Cull]

            HLSLPROGRAM
            #pragma shader_feature_local _ALPHA_CUTOUT
            #pragma shader_feature_local _DOUBLE_SIDED_NORMALS

            #pragma vertex Vertex
            #pragma fragment Fragment

            #include "MyLitShadowCasterPass.hlsl"
            ENDHLSL
        }

        // ===== Pass 3: 光照烘焙元通道 [Part5-二] =====
        Pass
        {
            Name "Meta"
            Tags{"LightMode" = "Meta"}
            Cull Off

            HLSLPROGRAM
            #pragma target 2.0
            #pragma vertex Vertex
            #pragma fragment Fragment
            #pragma shader_feature_local_fragment _SPECULAR_SETUP
            #pragma shader_feature_local_fragment _EMISSION
            #pragma shader_feature_local_fragment _ALPHA_CUTOUT
            #include "MyLitMetaPass.hlsl"
            ENDHLSL
        }

        // ===== Pass 4: 仅深度 [Part2 附近] =====
        Pass
        {
            Name "DepthOnly"
            Tags{"LightMode" = "DepthOnly"}

            ZWrite On
            ColorMask 0
            Cull [_Cull]

            HLSLPROGRAM
            #pragma exclude_renderers gles gles3 glcore
            #pragma target 4.5

            #pragma vertex DepthOnlyVertex
            #pragma fragment DepthOnlyFragment

            // 关键：ShadowCaster 里有，这里也必须同步
            #pragma shader_feature_local _ALPHA_CUTOUT
            #pragma shader_feature_local _DOUBLE_SIDED_NORMALS

            #include "MyLitDepthOnlyPass.hlsl"
            ENDHLSL
        }

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

        // ===== Pass 6: 运动向量 [Part5-七] =====
        Pass
        {
            Name "MotionVectors"
            Tags{"LightMode" = "MotionVectors"}

            ColorMask RG        // 只写RG，B/A留0

            HLSLPROGRAM
            #pragma target 3.5
            #pragma shader_feature_local _ALPHA_CUTOUT

            #pragma vertex Vertex
            #pragma fragment Fragment

            #include "MyLitMotionVectorPass.hlsl"
            ENDHLSL
        }
    }
    CustomEditor "MyLitCustomInspector"
}
