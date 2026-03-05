Shader "ELEX/URP/CommonEffects/LitLambert"
{
    Properties
    {
        [MainTexture] _BaseMap ("Base Map", 2D) = "white" {} // 主纹理采样源；用于定义物体表面图案，且支持 Inspector 的 Tiling/Offset（通过 _BaseMap_ST 参与 UV 变换）。
        [MainColor] _BaseColor ("Base Color", Color) = (1, 1, 1, 1) // 主颜色乘子；与主纹理结果相乘，统一控制整体染色与亮度（RGBA 都会参与）。
    }

    SubShader
    {
        Tags { "RenderPipeline"="UniversalPipeline" "RenderType"="Opaque" "Queue"="Geometry" }
        LOD 200
        Cull Back
        ZWrite On

        Pass
        {
            Name "LitLambert"
            Tags { "LightMode"="UniversalForward" }

            HLSLPROGRAM
            #pragma target 3.0
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_instancing
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _ADDITIONAL_LIGHTS

            // 光照相关函数
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseColor;
                float4 _BaseMap_ST;
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

                // 顶点位置与法线转换到世界空间
                VertexPositionInputs pos = GetVertexPositionInputs(input.positionOS);
                VertexNormalInputs normalInput = GetVertexNormalInputs(input.normalOS);

                output.positionCS = pos.positionCS;
                output.positionWS = pos.positionWS;
                output.normalWS = normalInput.normalWS;
                output.uv = TRANSFORM_TEX(input.uv, _BaseMap);
                return output;
            }

            half4 frag(Varyings input) : SV_Target
            {
                /*
                算法原理（Lambert 漫反射）：
                1) 计算 NdotL = saturate(dot(N, L))
                2) 漫反射 = albedo * lightColor * NdotL * 衰减 * 阴影
                3) 主光 + 额外光 累加，最后再加环境光（SH）

                核心公式：
                diffuse = albedo * lightColor * max(0, dot(N, L))
                */
                // 基础颜色（纹理 * 颜色）
                half3 albedo = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv).rgb;
                albedo *= _BaseColor.rgb;

                // 世界空间法线
                half3 N = normalize(input.normalWS);

                // 主光（方向光）
                float4 shadowCoord = TransformWorldToShadowCoord(input.positionWS);
                Light mainLight = GetMainLight(shadowCoord);
                half NdotL = saturate(dot(N, mainLight.direction));
                half3 diffuse = albedo * mainLight.color * (mainLight.distanceAttenuation * mainLight.shadowAttenuation) * NdotL;

                // 额外光源（点光/聚光）
                #if defined(_ADDITIONAL_LIGHTS)
                uint lightCount = GetAdditionalLightsCount();
                for (uint i = 0; i < lightCount; i++)
                {
                    Light light = GetAdditionalLight(i, input.positionWS);
                    half ndotl = saturate(dot(N, light.direction));
                    diffuse += albedo * light.color * (light.distanceAttenuation * light.shadowAttenuation) * ndotl;
                }
                #endif

                // 环境光（球谐）
                half3 ambient = SampleSH(N) * albedo;

                half3 finalCol = diffuse + ambient;
                return half4(finalCol, 1.0);
            }
            ENDHLSL
        }
    }
}
