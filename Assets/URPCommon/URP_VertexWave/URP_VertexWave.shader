Shader "ELEX/URP/CommonEffects/VertexWave"
{
    Properties
    {
        [MainTexture] _BaseMap ("Base Map", 2D) = "white" {} // 主纹理采样源；用于定义物体表面图案，且支持 Inspector 的 Tiling/Offset（通过 _BaseMap_ST 参与 UV 变换）。
        [MainColor] _BaseColor ("Base Color", Color) = (1, 1, 1, 1) // 主颜色乘子；与主纹理结果相乘，统一控制整体染色与亮度（RGBA 都会参与）。
        _WaveAmplitude ("Wave Amplitude", Range(0, 1)) = 0.1 // 波浪振幅；顶点高度位移最大值，决定波高。
        _WaveFrequency ("Wave Frequency", Range(0, 10)) = 2 // 波浪频率；空间周期密度，值越大波峰越密。
        _WaveSpeed ("Wave Speed", Range(0, 10)) = 2 // 波浪速度；时间相位推进速度，决定动画快慢。
        _WaveDirection ("Wave Direction (XZ)", Vector) = (1, 0, 0, 0) // 波浪方向（XZ）；决定波在平面内传播的方向向量。
    }

    SubShader
    {
        Tags { "RenderPipeline"="UniversalPipeline" "RenderType"="Opaque" "Queue"="Geometry" }
        LOD 150
        Cull Back
        ZWrite On

        Pass
        {
            Name "VertexWave"
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
                float _WaveAmplitude;
                float _WaveFrequency;
                float _WaveSpeed;
                float4 _WaveDirection;
            CBUFFER_END

            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);

            struct Attributes
            {
                float3 positionOS : POSITION;
                float2 uv : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
                UNITY_VERTEX_OUTPUT_STEREO
            };

            Varyings vert(Attributes input)
            {
                Varyings output = (Varyings)0;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

                /*
                算法原理（Vertex Wave）：
                1) 以顶点位置和方向向量计算相位 phase
                2) wave = sin(phase) * 振幅
                3) 把 wave 加到顶点 y，实现几何级别波动

                核心公式：
                phase = dot(posOS.xz, dir) * _WaveFrequency + _Time.y * _WaveSpeed
                posOS.y += sin(phase) * _WaveAmplitude
                */
                float3 posOS = input.positionOS;
                float2 dir = normalize(_WaveDirection.xy + 1e-5); // 避免零向量
                float phase = dot(posOS.xz, dir) * _WaveFrequency + _Time.y * _WaveSpeed;
                float wave = sin(phase) * _WaveAmplitude;
                posOS.y += wave;

                VertexPositionInputs pos = GetVertexPositionInputs(posOS);
                output.positionCS = pos.positionCS;
                output.uv = TRANSFORM_TEX(input.uv, _BaseMap);
                return output;
            }

            half4 frag(Varyings input) : SV_Target
            {
                half4 baseCol = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv) * _BaseColor;
                return baseCol;
            }
            ENDHLSL
        }
    }
}
