// 金属材质着色器，用于反射探针烘焙时排查用
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
