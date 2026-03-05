Shader "ELEX/URP/CommonEffects/NormalMapLambert"
{
    Properties
    {
        [MainTexture] _BaseMap ("Base Map", 2D) = "white" {} // 主纹理采样源；用于定义物体表面图案，且支持 Inspector 的 Tiling/Offset（通过 _BaseMap_ST 参与 UV 变换）。
        [MainColor] _BaseColor ("Base Color", Color) = (1, 1, 1, 1) // 主颜色乘子；与主纹理结果相乘，统一控制整体染色与亮度（RGBA 都会参与）。
        [Normal] _NormalMap ("Normal Map", 2D) = "bump" {} // 法线贴图；提供表面微法线细节以增强受光层次。
        _NormalScale ("Normal Scale", Range(0, 2)) = 1 // 法线强度；缩放法线贴图扰动幅度，0 接近平滑表面。
    }

    SubShader
    {
        Tags { "RenderPipeline"="UniversalPipeline" "RenderType"="Opaque" "Queue"="Geometry" }
        LOD 250
        Cull Back
        ZWrite On

        Pass
        {
            Name "NormalMapLambert"
            Tags { "LightMode"="UniversalForward" }

            HLSLPROGRAM
            #pragma target 3.0
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_instancing
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _ADDITIONAL_LIGHTS

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/SurfaceInput.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseColor;
                float4 _BaseMap_ST;
                float4 _NormalMap_ST;
                float _NormalScale;
            CBUFFER_END

            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);
            TEXTURE2D(_NormalMap);
            SAMPLER(sampler_NormalMap);

            struct Attributes
            {
                float3 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float4 tangentOS : TANGENT;
                float2 uv : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionWS : TEXCOORD0;
                float3 normalWS : TEXCOORD1;
                float3 tangentWS : TEXCOORD2;
                float3 bitangentWS : TEXCOORD3;
                float2 uv : TEXCOORD4;
                UNITY_VERTEX_INPUT_INSTANCE_ID
                UNITY_VERTEX_OUTPUT_STEREO
            };

            Varyings vert(Attributes input)
            {
                Varyings output = (Varyings)0;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

                VertexPositionInputs pos = GetVertexPositionInputs(input.positionOS);
                VertexNormalInputs normalInput = GetVertexNormalInputs(input.normalOS, input.tangentOS);

                output.positionCS = pos.positionCS;
                output.positionWS = pos.positionWS;
                output.normalWS = normalize(normalInput.normalWS);
                output.tangentWS = normalize(normalInput.tangentWS);
                output.bitangentWS = normalize(normalInput.bitangentWS);
                output.uv = TRANSFORM_TEX(input.uv, _BaseMap);
                return output;
            }

            half4 frag(Varyings input) : SV_Target
            {
                /*
                算法原理（法线贴图 + Lambert）：
                1) 采样切线空间法线 normalTS（来自法线贴图）
                2) 用 TBN 矩阵把 normalTS 变换到世界空间 normalWS
                3) 用 normalWS 参与 Lambert 光照，得到更细节的明暗变化

                核心公式：
                N = normalize(T * nTS.x + B * nTS.y + N0 * nTS.z)
                diffuse = albedo * lightColor * max(0, dot(N, L))
                */
                half3 albedo = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv).rgb * _BaseColor.rgb;

                float2 normalUV = input.uv * _NormalMap_ST.xy + _NormalMap_ST.zw;
                half3 normalTS = UnpackNormalScale(SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, normalUV), _NormalScale);
                half3 N = normalize(
                    input.tangentWS * normalTS.x +
                    input.bitangentWS * normalTS.y +
                    input.normalWS * normalTS.z
                );

                float4 shadowCoord = TransformWorldToShadowCoord(input.positionWS);
                Light mainLight = GetMainLight(shadowCoord);
                half ndotl = saturate(dot(N, mainLight.direction));
                half3 diffuse = albedo * mainLight.color * (mainLight.distanceAttenuation * mainLight.shadowAttenuation) * ndotl;

                #if defined(_ADDITIONAL_LIGHTS)
                uint lightCount = GetAdditionalLightsCount();
                for (uint i = 0; i < lightCount; i++)
                {
                    Light light = GetAdditionalLight(i, input.positionWS);
                    half addNdotL = saturate(dot(N, light.direction));
                    diffuse += albedo * light.color * (light.distanceAttenuation * light.shadowAttenuation) * addNdotL;
                }
                #endif

                half3 ambient = SampleSH(N) * albedo;
                return half4(diffuse + ambient, 1.0);
            }
            ENDHLSL
        }
    }
}
