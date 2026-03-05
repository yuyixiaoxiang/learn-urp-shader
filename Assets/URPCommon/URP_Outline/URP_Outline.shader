Shader "ELEX/URP/CommonEffects/Outline"
{
    

/*
Moved From: ShaderCommonEffects_URP.md
Section: URP_Outline.shader

- 一句话：模型外轮廓线。
- 视觉效果：角色描边、交互高亮边框。
- 核心原理：
1. 描边 Pass：顶点沿法线膨胀
2. `Cull Front` 只画背面
3. Base Pass 再画本体
- 关键参数：
- `_OutlineWidth`：线宽
- `_OutlineColor`：线色
- 常见坑：
- 模型法线不平滑会导致描边抖动
- 核心代码：

```hlsl
posWS += normalWS * _OutlineWidth;
Cull Front
```
*/
Properties
    {
        [MainTexture] _BaseMap ("Base Map", 2D) = "white" {} // 主纹理采样源；用于定义物体表面图案，且支持 Inspector 的 Tiling/Offset（通过 _BaseMap_ST 参与 UV 变换）。
        [MainColor] _BaseColor ("Base Color", Color) = (1, 1, 1, 1) // 主颜色乘子；与主纹理结果相乘，统一控制整体染色与亮度（RGBA 都会参与）。
        [HDR] _OutlineColor ("Outline Color", Color) = (0, 0, 0, 1) // 描边颜色（HDR）；用于外扩轮廓 pass 的最终输出颜色。
        _OutlineWidth ("Outline Width", Range(0, 0.05)) = 0.01 // 描边宽度；沿法线外扩距离，值越大描边越粗。
    }

    SubShader
    {
        Tags { "RenderPipeline"="UniversalPipeline" "RenderType"="Opaque" "Queue"="Geometry" }
        LOD 200

        // Pass 1: 外描边（反面剔除 + 法线膨胀）
        Pass
        {
            Name "Outline"
            Tags { "LightMode"="SRPDefaultUnlit" }
            Cull Front
            ZWrite On
            ZTest LEqual

            HLSLPROGRAM
            #pragma target 2.0
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_instancing

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseColor;
                float4 _BaseMap_ST;
                float4 _OutlineColor;
                float _OutlineWidth;
            CBUFFER_END

            struct Attributes
            {
                float3 positionOS : POSITION;
                float3 normalOS : NORMAL;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                UNITY_VERTEX_INPUT_INSTANCE_ID
                UNITY_VERTEX_OUTPUT_STEREO
            };

            Varyings vert(Attributes input)
            {
                Varyings output = (Varyings)0;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

                /*
                算法原理（外描边 Pass）：
                1) 顶点沿法线方向膨胀：posWS += normalWS * _OutlineWidth
                2) 只渲染背面（Cull Front），让膨胀体从模型边缘露出
                3) 输出纯色描边
                */
                float3 normalWS = TransformObjectToWorldNormal(input.normalOS);
                float3 posWS = TransformObjectToWorld(input.positionOS);
                posWS += normalWS * _OutlineWidth;

                output.positionCS = TransformWorldToHClip(posWS);
                return output;
            }

            half4 frag(Varyings input) : SV_Target
            {
                return _OutlineColor;
            }
            ENDHLSL
        }

        // Pass 2: 基础贴图
        Pass
        {
            Name "Base"
            Tags { "LightMode"="UniversalForward" }
            Cull Back
            ZWrite On

            HLSLPROGRAM
            #pragma target 2.0
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_instancing

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseColor;
                float4 _BaseMap_ST;
                float4 _OutlineColor;
                float _OutlineWidth;
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
                // Base Pass：正常显示模型本体（贴图 * 颜色）
                half4 baseCol = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv) * _BaseColor;
                return baseCol;
            }
            ENDHLSL
        }
    }
}


