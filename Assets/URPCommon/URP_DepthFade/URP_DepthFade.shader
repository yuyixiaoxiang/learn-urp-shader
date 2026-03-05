Shader "ELEX/URP/CommonEffects/DepthFade"
{
    Properties
    {
        [MainTexture] _BaseMap ("Base Map", 2D) = "white" {} // 主纹理采样源；用于定义物体表面图案，且支持 Inspector 的 Tiling/Offset（通过 _BaseMap_ST 参与 UV 变换）。
        [MainColor] _BaseColor ("Base Color", Color) = (1, 1, 1, 1) // 主颜色乘子；与主纹理结果相乘，统一控制整体染色与亮度（RGBA 都会参与）。
        _Alpha ("Alpha", Range(0, 1)) = 1 // 整体透明度；会与贴图/颜色 alpha 相乘，最终参与透明混合。
        _FadeDistance ("Depth Fade Distance", Range(0.001, 5)) = 0.5 // 衰减距离；控制效果从强到弱的过渡范围（值越大，过渡越柔和）。
    }

    SubShader
    {
        Tags { "RenderPipeline"="UniversalPipeline" "RenderType"="Transparent" "Queue"="Transparent" }
        LOD 150
        Cull Back
        ZWrite Off
        Blend SrcAlpha OneMinusSrcAlpha

        Pass
        {
            Name "DepthFade"
            Tags { "LightMode"="UniversalForward" }

            HLSLPROGRAM
            #pragma target 3.0
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_instancing

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseColor;
                float4 _BaseMap_ST;
                float _Alpha;
                float _FadeDistance;
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
                float4 screenPos : TEXCOORD0;
                float3 positionWS : TEXCOORD1;
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
                output.positionCS = pos.positionCS;
                output.positionWS = pos.positionWS;
                output.screenPos = ComputeScreenPos(pos.positionCS);
                output.uv = TRANSFORM_TEX(input.uv, _BaseMap);
                return output;
            }

            half4 frag(Varyings input) : SV_Target
            {
                /*
                算法原理（Depth Fade）：
                1) 读取场景深度（当前像素后面的不透明表面深度）
                2) 计算场景深度与当前透明物体深度的差值
                3) 差值越小（越接近碰撞边界），alpha 越小，从而软化穿插边缘

                核心公式：
                fade = saturate((sceneDepth - fragDepth) / _FadeDistance)
                finalAlpha = baseAlpha * fade
                */
                half4 baseCol = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv) * _BaseColor;

                float2 screenUV = input.screenPos.xy / input.screenPos.w;
                float sceneRawDepth = SampleSceneDepth(screenUV);
                float sceneEyeDepth = LinearEyeDepth(sceneRawDepth, _ZBufferParams);

                // 视空间下，摄像机朝向为 -Z，因此取负得到正向眼深
                float fragEyeDepth = -TransformWorldToView(input.positionWS).z;

                float fade = saturate((sceneEyeDepth - fragEyeDepth) / max(_FadeDistance, 1e-5));
                baseCol.a *= (_Alpha * fade);
                return baseCol;
            }
            ENDHLSL
        }
    }
}
