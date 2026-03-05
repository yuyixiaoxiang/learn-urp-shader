Shader "ELEX/URP/CommonEffects/Triplanar"
{
    

/*
Moved From: ShaderCommonEffects_URP.md
Section: URP_Triplanar.shader

- 一句话：不依赖 UV 的三向投影贴图。
- 视觉效果：岩石地形不拉伸、接缝少。
- 核心原理：
1. 分别在 X/Y/Z 平面采样
2. 按法线方向权重混合
- 关键参数：
- `_Tiling`：世界空间密度
- `_BlendSharpness`：三个方向过渡软硬
- 常见坑：
- 条纹图案会在不同方向看出拼接感
- 核心代码：

```hlsl
float3 w = pow(abs(N), _BlendSharpness);
w /= max(w.x + w.y + w.z, 1e-5);
```
*/
Properties
    {
        [MainTexture] _BaseMap ("Base Map", 2D) = "white" {} // 主纹理采样源；用于定义物体表面图案，且支持 Inspector 的 Tiling/Offset（通过 _BaseMap_ST 参与 UV 变换）。
        [MainColor] _BaseColor ("Base Color", Color) = (1, 1, 1, 1) // 主颜色乘子；与主纹理结果相乘，统一控制整体染色与亮度（RGBA 都会参与）。
        _Tiling ("World Tiling", Range(0.1, 20)) = 2 // 世界平铺密度；Triplanar 采样的世界坐标缩放系数。
        _BlendSharpness ("Blend Sharpness", Range(1, 16)) = 4 // 混合锐度；三向投影权重指数，越大过渡越硬。
    }

    SubShader
    {
        Tags { "RenderPipeline"="UniversalPipeline" "RenderType"="Opaque" "Queue"="Geometry" }
        LOD 220
        Cull Back
        ZWrite On

        Pass
        {
            Name "Triplanar"
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
                float _Tiling;
                float _BlendSharpness;
            CBUFFER_END

            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);

            struct Attributes
            {
                float3 positionOS : POSITION;
                float3 normalOS : NORMAL;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionWS : TEXCOORD0;
                float3 normalWS : TEXCOORD1;
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
                return output;
            }

            half4 frag(Varyings input) : SV_Target
            {
                /*
                算法原理（Triplanar）：
                1) 不依赖模型 UV，直接用世界坐标在 X/Y/Z 三个平面投影采样
                2) 用法线绝对值作为三个方向权重，再归一化混合
                3) 适合岩石、地形、无 UV 模型

                核心公式：
                weights = pow(abs(N), sharpness); weights /= sum(weights)
                col = colX * w.x + colY * w.y + colZ * w.z
                */
                half3 N = normalize(input.normalWS);

                float3 w = pow(abs(N), _BlendSharpness);
                w /= max(w.x + w.y + w.z, 1e-5);

                float2 uvX = input.positionWS.zy * _Tiling;
                float2 uvY = input.positionWS.xz * _Tiling;
                float2 uvZ = input.positionWS.xy * _Tiling;

                half3 colX = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, uvX).rgb;
                half3 colY = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, uvY).rgb;
                half3 colZ = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, uvZ).rgb;

                half3 albedo = (colX * w.x + colY * w.y + colZ * w.z) * _BaseColor.rgb;

                float4 shadowCoord = TransformWorldToShadowCoord(input.positionWS);
                Light mainLight = GetMainLight(shadowCoord);
                half ndotl = saturate(dot(N, mainLight.direction));
                half3 diffuse = albedo * mainLight.color * (mainLight.distanceAttenuation * mainLight.shadowAttenuation) * ndotl;
                half3 ambient = SampleSH(N) * albedo;
                return half4(diffuse + ambient, 1.0);
            }
            ENDHLSL
        }
    }
}


