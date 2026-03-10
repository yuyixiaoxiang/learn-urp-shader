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
        // 常用组合：
        // Opaque: RenderType=Opaque, Queue=Geometry
        // Alpha Blend: RenderType=Transparent, Queue=Transparent
        // Alpha Clip / Dither: RenderType=TransparentCutout, Queue=AlphaTest
        Tags { "RenderPipeline"="UniversalPipeline" "RenderType"="TransparentCutout" "Queue"="AlphaTest" }
        LOD 130
        Cull Back
        ZWrite On

        HLSLINCLUDE
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseColor;
                float4 _BaseMap_ST;
                float _Alpha;
                float _DitherScale;
            CBUFFER_END

            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);

            // 将 2D 坐标映射到稳定的伪随机阈值，输出范围 [0,1)
            float InterleavedNoise(float2 p)
            {
                // 固定到网格单元：同一像素格内阈值一致，跨格子才变化
                float2 i = floor(p);
                // 2D->1D 点积打散，再用 sin 非线性扰动；最后 frac 取小数部分归一化到 [0,1)
                return frac(sin(dot(i, float2(12.9898, 78.233))) * 43758.5453);
            }

            float ComputeDitherThreshold(float4 positionCS)
            {
                // 透视除法：xy / w，把裁剪空间坐标转换到 NDC 平面（通常范围 [-1, 1]）
                // max(w, 1e-5) 用于避免 w 接近 0 时的除零/数值爆炸问题
                float2 screenUV = positionCS.xy / max(positionCS.w, 1e-5);
                // 将 NDC 坐标映射到像素尺度并按 _DitherScale 调整点阵密度
                float2 pixelPos = screenUV * _ScreenParams.xy * _DitherScale;
                return InterleavedNoise(pixelPos);
            }

            void ApplyDitherClip(float2 uv, float4 positionCS)
            {
                half4 col = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, uv) * _BaseColor;
                float alpha = saturate(_Alpha * col.a);
                clip(alpha - ComputeDitherThreshold(positionCS));
            }
        ENDHLSL

        Pass
        {
            Name "DitherTransparent"
            Tags { "LightMode"="UniversalForward" }

            HLSLPROGRAM
            #pragma target 2.0
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_instancing

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
                UNITY_TRANSFER_INSTANCE_ID(input, output);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

                VertexPositionInputs pos = GetVertexPositionInputs(input.positionOS);
                output.positionCS = pos.positionCS;
                output.uv = TRANSFORM_TEX(input.uv, _BaseMap);
                return output;
            }

            half4 frag(Varyings input) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);

                half4 col = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv) * _BaseColor;

                // 目标 alpha = 材质 alpha * 贴图 alpha
                float alpha = saturate(_Alpha * col.a);

                // alpha 小于阈值则丢弃，形成“点阵透明”
                clip(alpha - ComputeDitherThreshold(input.positionCS));

                // Cutout 输出通常可把 alpha 设为 1，避免后续混合影响
                return half4(col.rgb, 1.0);
            }
            ENDHLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }

            ZWrite On
            ZTest LEqual
            ColorMask 0

            HLSLPROGRAM
            #pragma target 2.0
            #pragma vertex vertShadow
            #pragma fragment fragShadow
            #pragma multi_compile_instancing
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

            float3 _LightDirection;
            float3 _LightPosition;

            struct AttributesShadow
            {
                float3 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float2 uv : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct VaryingsShadow
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            float4 GetShadowPositionCS(AttributesShadow input)
            {
                float3 positionWS = TransformObjectToWorld(input.positionOS);
                float3 normalWS = TransformObjectToWorldNormal(input.normalOS);

                #if _CASTING_PUNCTUAL_LIGHT_SHADOW
                    float3 lightDirectionWS = normalize(_LightPosition - positionWS);
                #else
                    float3 lightDirectionWS = _LightDirection;
                #endif

                float4 positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, lightDirectionWS));
                positionCS = ApplyShadowClamping(positionCS);
                return positionCS;
            }

            VaryingsShadow vertShadow(AttributesShadow input)
            {
                VaryingsShadow output = (VaryingsShadow)0;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_TRANSFER_INSTANCE_ID(input, output);

                output.positionCS = GetShadowPositionCS(input);
                output.uv = TRANSFORM_TEX(input.uv, _BaseMap);
                return output;
            }

            half4 fragShadow(VaryingsShadow input) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(input);
                ApplyDitherClip(input.uv, input.positionCS);
                return 0;
            }
            ENDHLSL
        }

        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }

            ZWrite On
            ColorMask R

            HLSLPROGRAM
            #pragma target 2.0
            #pragma vertex vertDepth
            #pragma fragment fragDepth
            #pragma multi_compile_instancing

            struct AttributesDepth
            {
                float3 positionOS : POSITION;
                float2 uv : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct VaryingsDepth
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
                UNITY_VERTEX_OUTPUT_STEREO
            };

            VaryingsDepth vertDepth(AttributesDepth input)
            {
                VaryingsDepth output = (VaryingsDepth)0;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_TRANSFER_INSTANCE_ID(input, output);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

                output.positionCS = TransformObjectToHClip(input.positionOS);
                output.uv = TRANSFORM_TEX(input.uv, _BaseMap);
                return output;
            }

            half fragDepth(VaryingsDepth input) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);

                ApplyDitherClip(input.uv, input.positionCS);
                return input.positionCS.z;
            }
            ENDHLSL
        }
    }
}
