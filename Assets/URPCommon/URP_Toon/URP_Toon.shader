Shader "ELEX/URP/CommonEffects/Toon"
{
    

/*
Moved From: ShaderCommonEffects_URP.md
Section: URP_Toon.shader

- 一句话：把连续光照变成分段光照，做卡通风。
- 视觉效果：明暗分层明显，边界干净。
- 核心原理：
1. 先得到 `ndotl`
2. 用 `floor` 量化成若干台阶
3. 在阴影色和亮色间插值
- 关键参数：
- `_RampSteps`：层数，2~4 常用
- `_ShadowColor`：暗部颜色
- `_ShadowThreshold/_ShadowSmooth`：单阈值模式时控制边缘
- 常见坑：
- 阶梯太少会“跳层”严重
- 核心代码：

```hlsl
half ramp = floor(ndotl * steps) / max(1.0, steps - 1.0);
half3 toonTint = lerp(_ShadowColor.rgb, 1.0, ramp);
```
*/
Properties
    {
        [MainTexture] _BaseMap ("Base Map", 2D) = "white" {} // 主纹理采样源；用于定义物体表面图案，且支持 Inspector 的 Tiling/Offset（通过 _BaseMap_ST 参与 UV 变换）。
        [MainColor] _BaseColor ("Base Color", Color) = (1, 1, 1, 1) // 主颜色乘子；与主纹理结果相乘，统一控制整体染色与亮度（RGBA 都会参与）。
        _RampSteps ("Ramp Steps", Range(1, 5)) = 3 // 卡通分档数；大于 1 时把明暗量化为离散台阶。
        _ShadowThreshold ("Shadow Threshold", Range(0, 1)) = 0.5 // 阴影阈值；单档模式下的明暗分界位置。
        _ShadowSmooth ("Shadow Smooth", Range(0, 0.2)) = 0.02 // 阴影平滑宽度；阈值附近的过渡软化范围。
        _ShadowColor ("Shadow Color", Color) = (0.2, 0.2, 0.2, 1) // 阴影颜色；用于平面投影阴影或卡通暗部着色（alpha 影响透明度）。
    }

    SubShader
    {
        Tags { "RenderPipeline"="UniversalPipeline" "RenderType"="Opaque" "Queue"="Geometry" }
        LOD 200
        Cull Back
        ZWrite On

        Pass
        {
            Name "Toon"
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
                float _RampSteps;
                float _ShadowThreshold;
                float _ShadowSmooth;
                float4 _ShadowColor;
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
                VertexNormalInputs normalInput = GetVertexNormalInputs(input.normalOS);

                output.positionCS = pos.positionCS;
                output.positionWS = pos.positionWS;
                output.normalWS = normalInput.normalWS;
                output.uv = TRANSFORM_TEX(input.uv, _BaseMap);
                return output;
            }

            half4 frag(Varyings input) : SV_Target
            {
                /*
                算法原理（Toon）：
                1) 先算标准漫反射 ndotl = max(0, dot(N, L))
                2) 把连续 ndotl 量化成阶梯亮度（或阈值二分）
                3) 用阶梯结果在“影色/亮色”之间插值，得到卡通明暗块

                核心公式（多阶）：
                ramp = floor(ndotl * steps) / (steps - 1)
                */
                half3 albedo = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv).rgb * _BaseColor.rgb;
                half3 N = normalize(input.normalWS);

                float4 shadowCoord = TransformWorldToShadowCoord(input.positionWS);
                Light mainLight = GetMainLight(shadowCoord);
                half ndotl = saturate(dot(N, mainLight.direction));

                // Toon 阶梯：
                // - 当 RampSteps > 1 时使用多档硬阶梯
                // - 当 RampSteps == 1 时使用阈值 + 平滑过渡
                half ramp = ndotl;
                if (_RampSteps > 1.0)
                {
                    float steps = _RampSteps;
                    // 把连续光照量化成离散台阶
                    ramp = floor(ndotl * steps) / max(1.0, steps - 1.0);
                }
                else
                {
                    // 1 档时退化为“阈值 + 平滑边缘”
                    ramp = smoothstep(_ShadowThreshold - _ShadowSmooth, _ShadowThreshold + _ShadowSmooth, ndotl);
                }

                // 影色与亮色混合，再乘主光颜色
                half3 toonTint = lerp(_ShadowColor.rgb, 1.0, ramp);
                half3 lit = albedo * toonTint * mainLight.color * (mainLight.distanceAttenuation * mainLight.shadowAttenuation);

                // 环境光补一点（避免纯黑）
                half3 ambient = SampleSH(N) * albedo;

                return half4(lit + ambient, 1.0);
            }
            ENDHLSL
        }
    }
}


