Shader "ELEX/URP/CommonEffects/SimplePBR"
{
    /*
    Simple PBR（简化版金属度流程）
    ------------------------------------------------------------
    适用场景：
    1) 在教学或快速验证里需要“比 Lambert 更像 PBR”的材质
    2) 想用较少参数快速表达金属/塑料差异

    说明：
    - 这是教学友好的“简化实现”，不是完整 URP Lit 替代
    - 包含：漫反射、简化高光、环境光、自发光
    */
    Properties
    {
        [MainTexture] _BaseMap ("Base Map", 2D) = "white" {} // 基础颜色贴图。
        [MainColor] _BaseColor ("Base Color", Color) = (1, 1, 1, 1) // 基础颜色乘子。
        _Metallic ("Metallic", Range(0, 1)) = 0 // 金属度；0 近似非金属，1 近似金属。
        _Smoothness ("Smoothness", Range(0, 1)) = 0.5 // 光滑度；越高高光越锐。
        _OcclusionStrength ("Occlusion Strength", Range(0, 1)) = 1 // 环境光强度缩放。
        [HDR] _EmissionColor ("Emission Color", Color) = (0, 0, 0, 1) // 自发光颜色（HDR）。
        _EmissionIntensity ("Emission Intensity", Range(0, 5)) = 0 // 自发光强度。
    }

    SubShader
    {
        Tags { "RenderPipeline"="UniversalPipeline" "RenderType"="Opaque" "Queue"="Geometry" }
        LOD 260
        Cull Back
        ZWrite On

        Pass
        {
            Name "SimplePBR"
            Tags { "LightMode"="UniversalForward" }

            HLSLPROGRAM
            #pragma target 3.0
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_instancing
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseColor;
                float4 _BaseMap_ST;
                float _Metallic;
                float _Smoothness;
                float _OcclusionStrength;
                float4 _EmissionColor;
                float _EmissionIntensity;
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
                VertexNormalInputs nrm = GetVertexNormalInputs(input.normalOS);
                output.positionCS = pos.positionCS;
                output.positionWS = pos.positionWS;
                output.normalWS = normalize(nrm.normalWS);
                output.uv = TRANSFORM_TEX(input.uv, _BaseMap);
                return output;
            }

            half4 frag(Varyings input) : SV_Target
            {
                half4 baseTex = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv);
                half3 albedo = baseTex.rgb * _BaseColor.rgb;

                half3 N = normalize(input.normalWS);
                half3 V = normalize(GetWorldSpaceViewDir(input.positionWS));

                float4 shadowCoord = TransformWorldToShadowCoord(input.positionWS);
                Light mainLight = GetMainLight(shadowCoord);

                // 漫反射：金属度越高，漫反射越弱
                half ndotl = saturate(dot(N, mainLight.direction));
                half3 diffuse = albedo * (1.0 - _Metallic) * ndotl;

                // 简化镜面：根据金属度混合 F0
                half3 F0 = lerp(half3(0.04, 0.04, 0.04), albedo, _Metallic);
                half3 H = normalize(mainLight.direction + V);
                half ndoth = saturate(dot(N, H));
                half specPower = exp2(2.0 + _Smoothness * 10.0); // 大致 4~1024
                half specTerm = pow(ndoth, specPower) * (0.5 + _Smoothness);
                half3 specular = F0 * specTerm * ndotl;

                half attenuation = mainLight.distanceAttenuation * mainLight.shadowAttenuation;
                half3 direct = (diffuse + specular) * mainLight.color * attenuation;

                // 环境光（SH）
                half3 ambient = SampleSH(N) * albedo * _OcclusionStrength;

                // 自发光
                half3 emission = _EmissionColor.rgb * _EmissionIntensity;

                half3 finalCol = direct + ambient + emission;
                return half4(finalCol, baseTex.a * _BaseColor.a);
            }
            ENDHLSL
        }
    }
}
