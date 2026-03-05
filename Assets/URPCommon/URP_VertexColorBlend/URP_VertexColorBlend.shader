Shader "ELEX/URP/CommonEffects/VertexColorBlend"
{
    /*
    Vertex Color Blend（顶点色混合）
    ------------------------------------------------------------
    适用场景：
    1) 地形/道具局部脏污涂抹
    2) 美术在 DCC 或引擎里直接刷混合权重

    核心思路：
    1) 读取顶点色（默认使用 R 通道）作为混合因子
    2) 在两张贴图之间做 lerp
    3) 可通过 _BlendContrast 改变过渡硬度
    */
    Properties
    {
        [MainTexture] _BaseMap ("Layer A", 2D) = "white" {} // 第一层贴图（通常是基础材质）。
        _BlendMap ("Layer B", 2D) = "gray" {} // 第二层贴图（通常是脏污/苔藓/细节层）。
        _TintA ("Layer A Tint", Color) = (1, 1, 1, 1) // 第一层颜色乘子。
        _TintB ("Layer B Tint", Color) = (1, 1, 1, 1) // 第二层颜色乘子。
        _BlendContrast ("Blend Contrast", Range(0.1, 4)) = 1 // 混合对比度；>1 过渡更硬，<1 过渡更软。
    }

    SubShader
    {
        Tags { "RenderPipeline"="UniversalPipeline" "RenderType"="Opaque" "Queue"="Geometry" }
        LOD 180
        Cull Back
        ZWrite On

        Pass
        {
            Name "VertexColorBlend"
            Tags { "LightMode"="UniversalForward" }

            HLSLPROGRAM
            #pragma target 2.0
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_instancing

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST;
                float4 _BlendMap_ST;
                float4 _TintA;
                float4 _TintB;
                float _BlendContrast;
            CBUFFER_END

            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);
            TEXTURE2D(_BlendMap);
            SAMPLER(sampler_BlendMap);

            struct Attributes
            {
                float3 positionOS : POSITION;
                float2 uv : TEXCOORD0;
                float4 color : COLOR;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uvA : TEXCOORD0;
                float2 uvB : TEXCOORD1;
                float4 color : COLOR;
                UNITY_VERTEX_INPUT_INSTANCE_ID
                UNITY_VERTEX_OUTPUT_STEREO
            };

            Varyings vert(Attributes input)
            {
                Varyings output = (Varyings)0;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

                VertexPositionInputs pos = GetVertexPositionInputs(input.positionOS);
                output.positionCS = pos.positionCS;
                output.uvA = TRANSFORM_TEX(input.uv, _BaseMap);
                output.uvB = TRANSFORM_TEX(input.uv, _BlendMap);
                output.color = input.color;
                return output;
            }

            half4 frag(Varyings input) : SV_Target
            {
                half4 a = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uvA) * _TintA;
                half4 b = SAMPLE_TEXTURE2D(_BlendMap, sampler_BlendMap, input.uvB) * _TintB;

                // 以顶点色 R 通道作为混合权重
                half mask = saturate(input.color.r);
                mask = pow(mask, _BlendContrast);

                half4 finalCol = lerp(a, b, mask);
                return finalCol;
            }
            ENDHLSL
        }
    }
}
