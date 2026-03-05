Shader "ELEX/URP/CommonEffects/Hologram"
{
    

/*
Moved From: ShaderCommonEffects_URP.md
Section: URP_Hologram.shader

- 一句话：全息投影风格。
- 视觉效果：扫描线 + 轮廓发亮 + 闪烁。
- 核心原理：
1. 世界 y + 时间生成扫描线
2. Fresnel 做边缘高亮
3. sin 做轻微闪烁
- 关键参数：
- `_ScanDensity`：扫描线密度
- `_ScanSpeed`：扫描线移动速度
- `_RimPower`：边缘宽度
- `_FlickerSpeed`：闪烁速度
- 常见坑：
- 过度闪烁会影响可读性
- 核心代码：

```hlsl
float line = frac(input.positionWS.y * _ScanDensity + _Time.y * _ScanSpeed);
half rim = pow(1.0 - saturate(dot(N, V)), _RimPower);
```
*/
Properties
    {
        [MainTexture] _BaseMap ("Base Map", 2D) = "white" {} // 主纹理采样源；用于定义物体表面图案，且支持 Inspector 的 Tiling/Offset（通过 _BaseMap_ST 参与 UV 变换）。
        [MainColor] _BaseColor ("Base Color", Color) = (0.3, 0.8, 1.0, 1) // 主颜色乘子；与主纹理结果相乘，统一控制整体染色与亮度（RGBA 都会参与）。
        [HDR] _ScanColor ("Scanline Color", Color) = (0.2, 0.8, 1.2, 1) // 扫描线颜色（HDR）；全息扫描条纹的发光颜色。
        [HDR] _RimColor ("Rim Color", Color) = (0.5, 1.0, 1.5, 1) // 边缘光颜色（HDR）；用于 Rim/Fresnel 或全息轮廓的高亮着色。
        _Alpha ("Alpha", Range(0, 1)) = 0.55 // 整体透明度；会与贴图/颜色 alpha 相乘，最终参与透明混合。
        _ScanDensity ("Scan Density", Range(1, 200)) = 40 // 扫描密度；单位高度内的扫描条纹数量，值越大条纹越密。
        _ScanSpeed ("Scan Speed", Range(-10, 10)) = 3 // 扫描速度；控制扫描线随时间移动的速度与方向（负值反向）。
        _ScanWidth ("Scan Width", Range(0.001, 0.2)) = 0.04 // 扫描宽度；控制单条扫描线高亮带的厚度。
        _RimPower ("Rim Power", Range(0.5, 8)) = 3 // 边缘聚焦度；值越大，边缘发光越集中在轮廓附近。
        _FlickerSpeed ("Flicker Speed", Range(0, 20)) = 8 // 闪烁速度；控制全息亮度抖动频率，提升电子感。
    }

    SubShader
    {
        Tags { "RenderPipeline"="UniversalPipeline" "RenderType"="Transparent" "Queue"="Transparent" }
        LOD 220
        Cull Back
        ZWrite Off
        Blend SrcAlpha One

        Pass
        {
            Name "Hologram"
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
                float4 _ScanColor;
                float4 _RimColor;
                float _Alpha;
                float _ScanDensity;
                float _ScanSpeed;
                float _ScanWidth;
                float _RimPower;
                float _FlickerSpeed;
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
                output.normalWS = normalize(normalInput.normalWS);
                output.uv = TRANSFORM_TEX(input.uv, _BaseMap);
                return output;
            }

            half4 frag(Varyings input) : SV_Target
            {
                /*
                算法原理（Hologram）：
                1) 以世界空间 Y 坐标 + 时间生成扫描线
                2) 用 Fresnel 强化轮廓亮边
                3) 再加 flicker 闪烁，形成电子投影感

                核心公式：
                line = frac(posWS.y * density + time * speed)
                rim = pow(1 - dot(N, V), rimPower)
                */
                half4 baseTex = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv) * _BaseColor;

                float line = frac(input.positionWS.y * _ScanDensity + _Time.y * _ScanSpeed);
                float scanMask = 1.0 - smoothstep(0.0, _ScanWidth, abs(line - 0.5));

                half3 N = normalize(input.normalWS);
                half3 V = normalize(GetWorldSpaceViewDir(input.positionWS));
                half rim = pow(1.0 - saturate(dot(N, V)), _RimPower);

                half flicker = 0.8 + 0.2 * sin(_Time.y * _FlickerSpeed);

                half3 rgb = baseTex.rgb * 0.35;
                rgb += _ScanColor.rgb * scanMask;
                rgb += _RimColor.rgb * rim;
                rgb *= flicker;

                half alpha = saturate(baseTex.a * _Alpha + rim * 0.35 + scanMask * 0.25);
                return half4(rgb, alpha);
            }
            ENDHLSL
        }
    }
}


