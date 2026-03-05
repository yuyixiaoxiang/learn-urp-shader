Shader "ELEX/URP/CommonEffects/FlowMap"
{
    

/*
Moved From: ShaderCommonEffects_URP.md
Section: URP_FlowMap.shader

- 一句话：按 FlowMap 指定方向流动。
- 视觉效果：局部绕流、分叉流，比 UVScroll 更自然。
- 核心原理：
1. `flowRG` 映射到 `[-1,1]`
2. 两相位偏移采样
3. 交替混合降低相位跳变
- 关键参数：
- `_FlowMap`：方向图（RG）
- `_FlowStrength`：偏移幅度
- `_FlowSpeed`：速度
- 常见坑：
- FlowMap 太噪会造成撕裂感
- 核心代码：

```hlsl
float2 flow = SAMPLE_TEXTURE2D(_FlowMap, sampler_FlowMap, flowUV).rg * 2.0 - 1.0;
float2 uv0 = uv + flow * phase0;
float2 uv1 = uv + flow * phase1;
```
*/
Properties
    {
        [MainTexture] _BaseMap ("Base Map", 2D) = "white" {} // 主纹理采样源；用于定义物体表面图案，且支持 Inspector 的 Tiling/Offset（通过 _BaseMap_ST 参与 UV 变换）。
        _FlowMap ("Flow Map (RG)", 2D) = "gray" {} // 流向贴图（RG）；RG 会映射到 [-1,1] 作为 UV 偏移方向。
        [MainColor] _BaseColor ("Base Color", Color) = (1, 1, 1, 1) // 主颜色乘子；与主纹理结果相乘，统一控制整体染色与亮度（RGBA 都会参与）。
        _FlowStrength ("Flow Strength", Range(0, 1)) = 0.15 // 流动幅度；控制 FlowMap 导致的 UV 偏移量大小。
        _FlowSpeed ("Flow Speed", Range(0, 5)) = 1 // 流动速度；控制流动动画相位推进快慢。
    }

    SubShader
    {
        Tags { "RenderPipeline"="UniversalPipeline" "RenderType"="Opaque" "Queue"="Geometry" }
        LOD 160
        Cull Back
        ZWrite On

        Pass
        {
            Name "FlowMap"
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
                float4 _FlowMap_ST;
                float _FlowStrength;
                float _FlowSpeed;
            CBUFFER_END

            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);
            TEXTURE2D(_FlowMap);
            SAMPLER(sampler_FlowMap);

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

                VertexPositionInputs pos = GetVertexPositionInputs(input.positionOS);
                output.positionCS = pos.positionCS;
                output.uv = TRANSFORM_TEX(input.uv, _BaseMap);
                return output;
            }

            half4 frag(Varyings input) : SV_Target
            {
                /*
                算法原理（FlowMap）：
                1) FlowMap 的 RG 表示 UV 流向（先映射到 [-1, 1]）
                2) 用两相位采样（phase0/phase1）并交替混合，降低跳变
                3) 常用于岩浆、水流、能量表面

                核心公式：
                flow = (flowRG * 2 - 1) * _FlowStrength
                uv' = uv + flow * phase
                */
                float2 flowUV = input.uv * _FlowMap_ST.xy + _FlowMap_ST.zw;
                float2 flow = SAMPLE_TEXTURE2D(_FlowMap, sampler_FlowMap, flowUV).rg * 2.0 - 1.0;
                flow *= _FlowStrength;

                float phase0 = frac(_Time.y * _FlowSpeed);
                float phase1 = frac(phase0 + 0.5);
                float blend = abs(phase0 * 2.0 - 1.0);

                float2 uv0 = input.uv + flow * phase0;
                float2 uv1 = input.uv + flow * phase1;

                half4 col0 = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, uv0);
                half4 col1 = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, uv1);
                half4 finalCol = lerp(col0, col1, blend) * _BaseColor;
                return finalCol;
            }
            ENDHLSL
        }
    }
}


