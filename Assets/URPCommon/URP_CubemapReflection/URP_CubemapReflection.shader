Shader "ELEX/URP/CommonEffects/CubemapReflection"
{
    /*
    Environment Reflection（环境反射，LatLong）
    ------------------------------------------------------------
    适用场景：
    1) 金属/塑料/抛光表面
    2) 低成本“反射感”表达

    核心思路：
    1) 用法线 N 和视线 V 求反射向量 R
    2) 把 R 转成经纬度 UV，采样环境贴图（LatLong）
    3) 通过 Fresnel 让边缘反射更强，中心更弱
    */
    Properties
    {
        [MainTexture] _BaseMap ("Base Map", 2D) = "white" {} // 基础颜色纹理。
        [MainColor] _BaseColor ("Base Color", Color) = (1, 1, 1, 1) // 基础颜色乘子。
        _EnvMap ("Environment Map (LatLong)", 2D) = "gray" {} // 经纬度环境贴图（HDR/LDR 均可）。
        _ReflectionStrength ("Reflection Strength", Range(0, 1)) = 0.5 // 反射整体强度。
        _FresnelPower ("Fresnel Power", Range(0.5, 8)) = 3 // Fresnel 聚焦度；越大边缘反射越集中。
    }

    SubShader
    {
        Tags { "RenderPipeline"="UniversalPipeline" "RenderType"="Opaque" "Queue"="Geometry" }
        LOD 220
        Cull Back
        ZWrite On

        Pass
        {
            Name "CubemapReflection"
            Tags { "LightMode"="UniversalForward" }

            HLSLPROGRAM
            #pragma target 3.0
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_instancing

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseColor;
                float4 _BaseMap_ST;
                float _ReflectionStrength;
                float _FresnelPower;
            CBUFFER_END

            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);
            TEXTURE2D(_EnvMap);
            SAMPLER(sampler_EnvMap);

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
                VertexNormalInputs nrm = GetVertexNormalInputs(input.normalOS);
                output.positionCS = pos.positionCS;
                output.positionWS = pos.positionWS;
                output.normalWS = normalize(nrm.normalWS);
                output.uv = TRANSFORM_TEX(input.uv, _BaseMap);
                return output;
            }

            // 把方向向量转换为经纬度（LatLong）UV
            float2 DirToLatLongUV(float3 dir)
            {
                dir = normalize(dir);
                float2 uv;
                uv.x = atan2(dir.x, dir.z) * (0.5 / PI) + 0.5;
                uv.y = 0.5 - asin(clamp(dir.y, -1.0, 1.0)) / PI;
                return uv;
            }

            half4 frag(Varyings input) : SV_Target
            {
                half3 albedo = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv).rgb * _BaseColor.rgb;

                half3 N = normalize(input.normalWS);
                half3 V = normalize(GetWorldSpaceViewDir(input.positionWS));

                // 基础受光（简单漫反射 + 环境光）
                Light mainLight = GetMainLight();
                half ndotl = saturate(dot(N, mainLight.direction));
                half3 diffuse = albedo * mainLight.color * (0.25 + 0.75 * ndotl);
                half3 ambient = SampleSH(N) * albedo;
                half3 litBase = diffuse + ambient;

                // 反射向量采样 Cubemap
                float3 R = reflect(-V, N);
                float2 envUV = DirToLatLongUV(R);
                half3 reflection = SAMPLE_TEXTURE2D(_EnvMap, sampler_EnvMap, envUV).rgb;

                // Fresnel：边缘更容易看到反射
                half fresnel = pow(1.0 - saturate(dot(N, V)), _FresnelPower);
                half reflectMask = saturate(_ReflectionStrength * (0.2 + 0.8 * fresnel));

                half3 finalCol = lerp(litBase, reflection, reflectMask);
                return half4(finalCol, 1.0);
            }
            ENDHLSL
        }
    }
}
