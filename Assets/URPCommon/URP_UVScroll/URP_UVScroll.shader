Shader "ELEX/URP/CommonEffects/UVScroll"
{
    

/*
Moved From: ShaderCommonEffects_URP.md
Section: URP_UVScroll.shader

- 一句话：贴图按固定速度滚动。
- 视觉效果：水流、能量流、云层流动。
- 核心原理：`uv = uv + speed * time`
- 关键参数：
- `_ScrollX / _ScrollY`：滚动速度方向
- 常见坑：
- 贴图边缘不无缝会“接缝跳变”
- 核心代码：

```hlsl
float2 uv = input.uv + float2(_ScrollX, _ScrollY) * _Time.y;
```
*/
Properties
    {
        [MainTexture] _BaseMap ("Base Map", 2D) = "white" {} // 主纹理采样源；用于定义物体表面图案，且支持 Inspector 的 Tiling/Offset（通过 _BaseMap_ST 参与 UV 变换）。
        [MainColor] _BaseColor ("Base Color", Color) = (1, 1, 1, 1) // 主颜色乘子；与主纹理结果相乘，统一控制整体染色与亮度（RGBA 都会参与）。
        _ScrollX ("Scroll X", Range(-5, 5)) = 0.2 // U 方向滚动速度；控制纹理横向流动快慢。
        _ScrollY ("Scroll Y", Range(-5, 5)) = 0.0 // V 方向滚动速度；控制纹理纵向流动快慢。
    }

    SubShader
    {
        Tags { "RenderPipeline"="UniversalPipeline" "RenderType"="Opaque" "Queue"="Geometry" }
        LOD 100
        Cull Back
        ZWrite On

        Pass
        {
            Name "UVScroll"
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
                float _ScrollX;
                float _ScrollY;
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

                VertexPositionInputs pos = GetVertexPositionInputs(input.positionOS);
                output.positionCS = pos.positionCS;
                output.uv = TRANSFORM_TEX(input.uv, _BaseMap);
                return output;
            }

            half4 frag(Varyings input) : SV_Target
            {
                /*
                算法原理（UV Scroll）：
                1) 使用 _Time.y 作为线性时间
                2) UV 偏移量 = 速度 * 时间
                3) 用偏移后的 UV 采样纹理，形成“流动”错觉

                核心公式：
                uv' = uv + float2(_ScrollX, _ScrollY) * _Time.y
                */
                float2 scroll = float2(_ScrollX, _ScrollY) * _Time.y;
                float2 uv = input.uv + scroll;

                half4 baseCol = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, uv) * _BaseColor;
                return baseCol;
            }
            ENDHLSL
        }
    }
}


