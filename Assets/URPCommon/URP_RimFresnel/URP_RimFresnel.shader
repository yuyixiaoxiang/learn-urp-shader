Shader "ELEX/URP/CommonEffects/RimFresnel"
{
    

/*
Moved From: ShaderCommonEffects_URP.md
Section: URP_RimFresnel.shader

- 一句话：轮廓边缘发亮。
- 视觉效果：物体外圈有“包边高光”。
- 核心原理：
1. 计算视线 `V` 与法线 `N` 的 dot
2. 越靠边（dot 小）亮度越高
3. 幂函数控制衰减曲线
- 关键参数：
- `_RimPower`：边缘范围
- `_RimIntensity`：亮度
- `_RimColor`：边缘颜色
- 常见坑：
- 强度过高会发白溢出
- 核心代码：

```hlsl
half rim = pow(1.0 - saturate(dot(N, V)), _RimPower) * _RimIntensity;
```
*/
Properties
    {
        [MainTexture] _BaseMap ("Base Map", 2D) = "white" {} // 主纹理采样源；用于定义物体表面图案，且支持 Inspector 的 Tiling/Offset（通过 _BaseMap_ST 参与 UV 变换）。
        [MainColor] _BaseColor ("Base Color", Color) = (1, 1, 1, 1) // 主颜色乘子；与主纹理结果相乘，统一控制整体染色与亮度（RGBA 都会参与）。
        [HDR] _RimColor ("Rim Color", Color) = (1, 1, 1, 1) // 边缘光颜色（HDR）；用于 Rim/Fresnel 或全息轮廓的高亮着色。
        _RimPower ("Rim Power", Range(0.5, 8)) = 2 // 边缘聚焦度；值越大，边缘发光越集中在轮廓附近。
        _RimIntensity ("Rim Intensity", Range(0, 5)) = 1 // 边缘光强度；对 Rim 颜色进行亮度放大。
    }

    SubShader
    {
        Tags { "RenderPipeline"="UniversalPipeline" "RenderType"="Opaque" "Queue"="Geometry" }
        LOD 150
        Cull Back
        ZWrite On

        Pass
        {
            Name "RimFresnel"
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
                float4 _RimColor;
                float _RimPower;
                float _RimIntensity;
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
                算法原理（Rim / Fresnel 近似）：
                1) 计算视线向量 V 与法线 N 的点积 dot(N, V)
                2) 视角越刮边（dot 越小），边缘光越强
                3) 用幂函数控制边缘衰减曲线

                核心公式：
                rim = pow(1 - saturate(dot(N, V)), _RimPower) * _RimIntensity
                */
                // 基础颜色
                half4 baseCol = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv) * _BaseColor;

                // 视线方向与法线夹角越大（越靠轮廓），Rim 越强
                half3 N = normalize(input.normalWS);
                half3 V = normalize(GetWorldSpaceViewDir(input.positionWS));
                half rim = pow(1.0 - saturate(dot(N, V)), _RimPower) * _RimIntensity;

                half3 finalCol = baseCol.rgb + _RimColor.rgb * rim;
                return half4(finalCol, baseCol.a);
            }
            ENDHLSL
        }
    }
}


