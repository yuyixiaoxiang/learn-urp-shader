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
                1) 从 FlowMap 读取 RG（0~1），映射到 UV 偏移方向（-1~1）
                2) 用时间相位驱动 UV 位移，让底图看起来“在流动”
                3) 使用双相位（phase0/phase1）交替混合，掩盖单相位循环回卷的跳变
                4) 常用于岩浆、水流、能量表面

                核心公式：
                flow = (flowRG * 2 - 1) * _FlowStrength
                phase0 = frac(_Time.y * _FlowSpeed)
                phase1 = frac(phase0 + 0.5)
                uv0 = uv + flow * phase0
                uv1 = uv + flow * phase1
                final = lerp(sample(uv0), sample(uv1), blend)

                函数说明：
                - SAMPLE_TEXTURE2D(tex, sampler, uv)：按 uv 从纹理采样颜色
                - frac(x)：取小数部分，范围 [0,1)，用于周期循环
                - abs(x)：绝对值，这里把线性相位变成三角波混合权重
                - lerp(a, b, t)：线性插值，返回 a*(1-t) + b*t

                返回语义：
                - SV_Target：当前像素输出到渲染目标（颜色缓冲）
                */
                // _FlowMap_ST.xy = Tiling，_FlowMap_ST.zw = Offset（只作用于 FlowMap 的采样坐标）
                float2 flowUV = input.uv * _FlowMap_ST.xy + _FlowMap_ST.zw;

                // 读取 flow map 的 RG 通道并从 [0,1] 解码到 [-1,1] 作为二维流向向量
                float2 flow = SAMPLE_TEXTURE2D(_FlowMap, sampler_FlowMap, flowUV).rg * 2.0 - 1.0;

                // 流动强度：放大或缩小 UV 偏移量
                flow *= _FlowStrength;

                // phase0：主相位（0->1 循环）。_Time.y 是秒级时间，_FlowSpeed 控制流速
                float phase0 = frac(_Time.y * _FlowSpeed);

                // phase1：与 phase0 错开半个周期（+0.5），用于双相位交替
                float phase1 = frac(phase0 + 0.5);

                // 混合权重（三角波）：phase0=0/1 时权重大，phase0=0.5 时权重小
                // 这样可在一个相位回卷时，用另一个相位“接力”，降低跳变感
                float blend = abs(phase0 * 2.0 - 1.0);

                // 同一张底图，用两个相位各采样一次
                float2 uv0 = input.uv + flow * phase0;
                float2 uv1 = input.uv + flow * phase1;

                half4 col0 = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, uv0);
                half4 col1 = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, uv1);

                // 交叉混合两相位结果，再乘主颜色
                half4 finalCol = lerp(col0, col1, blend) * _BaseColor;
                return finalCol;
            }
            ENDHLSL
        }
    }
}


