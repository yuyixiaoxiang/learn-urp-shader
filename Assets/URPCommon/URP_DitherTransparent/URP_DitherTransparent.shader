Shader "ELEX/URP/CommonEffects/DitherTransparent"
{
    /*
    Dither 伪透明（可写深度）
    ------------------------------------------------------------
    适用场景：
    1) 角色隐身过渡（不希望出现透明排序错乱）
    2) 建筑淡入淡出（需要仍然参与深度遮挡）

    核心思路：
    1) 不使用传统 Alpha Blend，而是用 clip 丢弃一部分像素
    2) 按屏幕像素位置生成可重复的抖动阈值
    3) alpha 越低，被丢弃的像素越多，看起来就越透明

    注意：
    - 这是“视觉透明”，本质还是 AlphaTest/Cutout
    - 远处可能看到点阵感，通常配合 TAA 或后处理更好
    */
    Properties
    {
        [MainTexture] _BaseMap ("Base Map", 2D) = "white" {} // 主纹理；决定基础图案和 alpha 通道内容。
        [MainColor] _BaseColor ("Base Color", Color) = (1, 1, 1, 1) // 主颜色乘子；用于统一调色和亮度。
        _Alpha ("Dither Alpha", Range(0, 1)) = 1 // 目标透明度；越低时被 clip 的像素越多。
        _DitherScale ("Dither Scale", Range(0.5, 8)) = 1 // 抖动图案密度；值越大图案越细密。
    }

    SubShader
    {
        Tags { "RenderPipeline"="UniversalPipeline" "RenderType"="TransparentCutout" "Queue"="AlphaTest" }
        LOD 130
        Cull Back
        ZWrite On

        Pass
        {
            Name "DitherTransparent"
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
                float _Alpha;
                float _DitherScale;
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

            // 使用简单哈希噪声作为阈值源，范围 [0,1)
            float InterleavedNoise(float2 p)
            {
                float2 i = floor(p);
                return frac(sin(dot(i, float2(12.9898, 78.233))) * 43758.5453);
            }

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
                half4 col = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv) * _BaseColor;

                // 目标 alpha = 材质 alpha * 贴图 alpha
                float alpha = saturate(_Alpha * col.a);

                // 用屏幕像素坐标生成阈值图案；_DitherScale 控制图案密度
                float2 screenUV = input.positionCS.xy / max(input.positionCS.w, 1e-5);
                float2 pixelPos = screenUV * _ScreenParams.xy * _DitherScale;
                float threshold = InterleavedNoise(pixelPos);

                // alpha 小于阈值则丢弃，形成“点阵透明”
                clip(alpha - threshold);

                // Cutout 输出通常可把 alpha 设为 1，避免后续混合影响
                return half4(col.rgb, 1.0);
            }
            ENDHLSL
        }
    }
}
