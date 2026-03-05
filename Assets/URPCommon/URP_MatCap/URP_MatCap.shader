Shader "ELEX/URP/CommonEffects/MatCap"
{
    Properties
    {
        [MainTexture] _BaseMap ("Base Map", 2D) = "white" {} // 主纹理采样源；用于定义物体表面图案，且支持 Inspector 的 Tiling/Offset（通过 _BaseMap_ST 参与 UV 变换）。
        _MatCapTex ("MatCap Texture", 2D) = "gray" {} // MatCap 纹理；基于视角法线查表得到“假环境反射/高光”外观。
        [MainColor] _BaseColor ("Base Color", Color) = (1, 1, 1, 1) // 主颜色乘子；与主纹理结果相乘，统一控制整体染色与亮度（RGBA 都会参与）。
        _MatCapStrength ("MatCap Strength", Range(0, 2)) = 1 // MatCap 强度；控制 MatCap 结果与底色的混合权重。
    }

    SubShader
    {
        Tags { "RenderPipeline"="UniversalPipeline" "RenderType"="Opaque" "Queue"="Geometry" }
        LOD 150
        Cull Back
        ZWrite On

        Pass
        {
            Name "MatCap"
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
                float _MatCapStrength;
            CBUFFER_END

            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);
            TEXTURE2D(_MatCapTex);
            SAMPLER(sampler_MatCapTex);

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
                float3 normalWS : TEXCOORD0;
                float2 uv : TEXCOORD1;
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
                output.normalWS = normalize(normalInput.normalWS);
                output.uv = TRANSFORM_TEX(input.uv, _BaseMap);
                return output;
            }

            half4 frag(Varyings input) : SV_Target
            {
                /*
                算法原理（MatCap）：
                1) 把世界法线转换到观察空间 normalVS
                2) 用 normalVS.xy 映射到 [0,1] 作为 MatCap UV
                3) MatCap 纹理可快速模拟金属/陶瓷等“烘焙反射感”

                核心公式：
                matcapUV = normalVS.xy * 0.5 + 0.5
                */
                half4 baseCol = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv) * _BaseColor;

                float3 normalVS = normalize(TransformWorldToViewDir(input.normalWS, true));
                float2 matcapUV = normalVS.xy * 0.5 + 0.5;
                half3 matcap = SAMPLE_TEXTURE2D(_MatCapTex, sampler_MatCapTex, matcapUV).rgb;

                // 允许 _MatCapStrength > 1 做风格化增强（而不是强制钳到 1）
                half3 matcapLit = baseCol.rgb * matcap * 2.0;
                half3 finalRGB = baseCol.rgb + (matcapLit - baseCol.rgb) * _MatCapStrength;
                return half4(finalRGB, baseCol.a);
            }
            ENDHLSL
        }
    }
}
