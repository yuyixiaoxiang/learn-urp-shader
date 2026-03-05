Shader "ELEX/URP/CommonEffects/PolarTwirl"
{
    

/*
Moved From: ShaderCommonEffects_URP.md
Section: URP_PolarTwirl.shader

- 一句话：中心旋涡扭曲。
- 视觉效果：黑洞、能量门、法阵扭曲。
- 核心原理：
1. 计算像素到中心的距离
2. 距离越近旋转角越大
3. 旋转 UV 后采样
- 关键参数：
- `_Center`：扭曲中心
- `_TwirlStrength`：扭曲强度
- `_Radius`：影响半径
- 常见坑：
- 半径太小几乎看不出效果
- 核心代码：

```hlsl
float angle = _TwirlStrength * saturate(1.0 - dist / _Radius);
float2 rotated = float2(offset.x * c - offset.y * s, offset.x * s + offset.y * c);
```
*/
Properties
    {
        [MainTexture] _BaseMap ("Base Map", 2D) = "white" {} // 主纹理采样源；用于定义物体表面图案，且支持 Inspector 的 Tiling/Offset（通过 _BaseMap_ST 参与 UV 变换）。
        [MainColor] _BaseColor ("Base Color", Color) = (1, 1, 1, 1) // 主颜色乘子；与主纹理结果相乘，统一控制整体染色与亮度（RGBA 都会参与）。
        _Center ("Twirl Center (UV)", Vector) = (0.5, 0.5, 0, 0) // 旋涡中心（UV）；极坐标扭曲的中心点坐标。
        _TwirlStrength ("Twirl Strength", Range(-15, 15)) = 6 // 旋涡强度；控制 UV 角度扭曲量，正负值决定旋转方向。
        _Radius ("Twirl Radius", Range(0.01, 2)) = 0.6 // 影响半径；控制扭曲作用范围，超出范围后效果减弱。
    }

    SubShader
    {
        Tags { "RenderPipeline"="UniversalPipeline" "RenderType"="Transparent" "Queue"="Transparent" }
        LOD 120
        Cull Back
        ZWrite Off
        Blend SrcAlpha OneMinusSrcAlpha

        Pass
        {
            Name "PolarTwirl"
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
                float4 _Center;
                float _TwirlStrength;
                float _Radius;
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
                算法原理（Polar Twirl）：
                1) 先把 UV 看作以中心点为原点的极坐标
                2) 距离中心越近，旋转角度越大；越远旋转越小
                3) 把旋转后的坐标用于采样，得到漩涡扭曲效果

                核心公式：
                angle = _TwirlStrength * saturate(1 - dist / _Radius)
                */
                float2 center = _Center.xy;
                float2 offset = input.uv - center;
                float dist = length(offset);

                float twirlMask = saturate(1.0 - dist / max(_Radius, 1e-5));
                float angle = _TwirlStrength * twirlMask;
                float s = sin(angle);
                float c = cos(angle);

                float2 rotated;
                rotated.x = offset.x * c - offset.y * s;
                rotated.y = offset.x * s + offset.y * c;

                float2 twirlUV = center + rotated;
                half4 baseCol = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, twirlUV) * _BaseColor;
                return baseCol;
            }
            ENDHLSL
        }
    }
}


