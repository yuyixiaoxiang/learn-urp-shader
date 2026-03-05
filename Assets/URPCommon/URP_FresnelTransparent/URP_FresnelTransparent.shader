Shader "ELEX/URP/CommonEffects/FresnelTransparent"
{
    Properties
    {
        [MainTexture] _BaseMap ("Base Map", 2D) = "white" {} // 主纹理采样源；用于定义物体表面图案，且支持 Inspector 的 Tiling/Offset（通过 _BaseMap_ST 参与 UV 变换）。
        [MainColor] _BaseColor ("Base Color", Color) = (1, 1, 1, 1) // 主颜色乘子；与主纹理结果相乘，统一控制整体染色与亮度（RGBA 都会参与）。
        [HDR] _FresnelColor ("Fresnel Color", Color) = (0.4, 0.8, 1, 1) // 菲涅尔颜色（HDR）；在掠射角区域叠加的边缘光颜色。
        _Alpha ("Base Alpha", Range(0, 1)) = 0.3 // 整体透明度；会与贴图/颜色 alpha 相乘，最终参与透明混合。
        _FresnelPower ("Fresnel Power", Range(0.5, 8)) = 3 // 菲涅尔指数；值越大，边缘高光越窄且越贴边。
        _FresnelIntensity ("Fresnel Intensity", Range(0, 5)) = 1 // 菲涅尔强度；控制边缘光贡献亮度。
        _FresnelAlphaBoost ("Fresnel Alpha Boost", Range(0, 2)) = 0.6 // 菲涅尔透明增强；在边缘角度额外提升 alpha，强化轮廓可见性。
    }

    SubShader
    {
        Tags { "RenderPipeline"="UniversalPipeline" "RenderType"="Transparent" "Queue"="Transparent" }
        LOD 180
        Cull Back
        ZWrite Off
        Blend SrcAlpha OneMinusSrcAlpha

        Pass
        {
            Name "FresnelTransparent"
            Tags { "LightMode"="UniversalForward" }

            HLSLPROGRAM
            #pragma target 2.0
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_instancing

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseColor;
                float4 _BaseMap_ST;
                float4 _FresnelColor;
                float _Alpha;
                float _FresnelPower;
                float _FresnelIntensity;
                float _FresnelAlphaBoost;
            CBUFFER_END

            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);

            struct Attributes
            {
                float3 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float2 uv : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionWS : TEXCOORD0;
                float3 normalWS : TEXCOORD1;
                float2 uv : TEXCOORD2;
                UNITY_VERTEX_INPUT_INSTANCE_ID
                UNITY_VERTEX_OUTPUT_STEREO
            };

            Varyings vert(Attributes input)
            {
                Varyings output = (Varyings)0;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

                VertexPositionInputs pos = GetVertexPositionInputs(input.positionOS);
                VertexNormalInputs normalInput = GetVertexNormalInputs(input.normalOS);

                output.positionCS = pos.positionCS;
                output.positionWS = pos.positionWS;
                output.normalWS = normalize(normalInput.normalWS);
                output.uv = TRANSFORM_TEX(input.uv, _BaseMap);
                return output;
            }

            half4 frag(Varyings input) : SV_Target
            {
                /*
                算法原理（透明 Fresnel）：
                1) 计算 N 与 V 的夹角，越靠轮廓 dot(N,V) 越小
                2) 用 pow(1 - dot(N,V), power) 得到边缘高亮权重
                3) 同时把该权重用于颜色和透明度增强

                核心公式：
                fresnel = pow(1 - saturate(dot(N, V)), _FresnelPower) * _FresnelIntensity
                */
                half4 baseCol = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv) * _BaseColor;
                half3 N = normalize(input.normalWS);
                half3 V = normalize(GetWorldSpaceViewDir(input.positionWS));

                half fresnel = pow(1.0 - saturate(dot(N, V)), _FresnelPower) * _FresnelIntensity;
                half3 finalRGB = baseCol.rgb + _FresnelColor.rgb * fresnel;
                half finalA = saturate(baseCol.a * _Alpha + fresnel * _FresnelAlphaBoost);
                return half4(finalRGB, finalA);
            }
            ENDHLSL
        }
    }
}
