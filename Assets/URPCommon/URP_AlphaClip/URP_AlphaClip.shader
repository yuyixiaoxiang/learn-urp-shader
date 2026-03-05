Shader "ELEX/URP/CommonEffects/AlphaClip"
{
    

/*
Moved From: ShaderCommonEffects_URP.md
Section: URP_AlphaClip.shader

- 一句话：硬裁剪镂空。
- 视觉效果：树叶边缘、铁丝网、洞口。
- 核心原理：alpha 小于阈值的像素直接丢弃。
- 关键参数：
- `_Cutoff`：阈值
- 常见坑：
- 边缘会锯齿，这是硬裁剪的特征
- 核心代码：

```hlsl
clip(baseCol.a - _Cutoff);
```
*/
Properties
    {
        [MainTexture] _BaseMap ("Base Map", 2D) = "white" {} // 主纹理采样源；用于定义物体表面图案，且支持 Inspector 的 Tiling/Offset（通过 _BaseMap_ST 参与 UV 变换）。
        [MainColor] _BaseColor ("Base Color", Color) = (1, 1, 1, 1) // 主颜色乘子；与主纹理结果相乘，统一控制整体染色与亮度（RGBA 都会参与）。
        _Cutoff ("Alpha Cutoff", Range(0, 1)) = 0.5 // 裁剪阈值；alpha 低于该值的像素会被 clip 丢弃，用于镂空/植被等硬边透明。
    }

    SubShader
    {
        Tags { "RenderPipeline"="UniversalPipeline" "RenderType"="TransparentCutout" "Queue"="AlphaTest" }
        LOD 100
        Cull Back
        ZWrite On

        Pass
        {
            Name "AlphaClip"
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
                float _Cutoff;
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
                算法原理（Alpha Clip / Cutout）：
                1) 采样纹理 alpha
                2) clip(alpha - _Cutoff) 小于阈值的像素直接丢弃
                3) 剩余像素作为不透明面渲染（可写深度、可投影）

                核心公式：
                clip(baseCol.a - _Cutoff)
                */
                half4 baseCol = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv) * _BaseColor;
                clip(baseCol.a - _Cutoff);
                return baseCol;
            }
            ENDHLSL
        }
    }
}


