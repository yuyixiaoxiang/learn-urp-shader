Shader "ELEX/URP/CommonEffects/ScreenDistortion"
{
    Properties
    {
        _DistortTex ("Distortion Texture", 2D) = "gray" {} // 扭曲贴图；通常使用噪声 RG 作为屏幕采样偏移向量来源。
        [MainColor] _TintColor ("Tint Color", Color) = (1, 1, 1, 1) // 染色颜色；对扭曲后的场景色做乘色，同时其 alpha 参与最终透明度。
        _Alpha ("Alpha", Range(0, 1)) = 1 // 整体透明度；会与贴图/颜色 alpha 相乘，最终参与透明混合。
        _DistortStrength ("Distort Strength", Range(0, 0.2)) = 0.03 // 扭曲强度；控制屏幕 UV 偏移距离，值越大折射感越强。
        _DistortSpeedX ("Distort Speed X", Range(-5, 5)) = 0.8 // X 向速度；控制扭曲噪声在 U 方向滚动速度。
        _DistortSpeedY ("Distort Speed Y", Range(-5, 5)) = 0.2 // Y 向速度；控制扭曲噪声在 V 方向滚动速度。
    }

    SubShader
    {
        Tags { "RenderPipeline"="UniversalPipeline" "RenderType"="Transparent" "Queue"="Transparent" }
        LOD 200
        Cull Back
        ZWrite Off
        Blend SrcAlpha OneMinusSrcAlpha

        Pass
        {
            Name "ScreenDistortion"
            Tags { "LightMode"="UniversalForward" }

            HLSLPROGRAM
            #pragma target 3.0
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_instancing

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareOpaqueTexture.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float4 _TintColor;
                float4 _DistortTex_ST;
                float _Alpha;
                float _DistortStrength;
                float _DistortSpeedX;
                float _DistortSpeedY;
            CBUFFER_END

            TEXTURE2D(_DistortTex);
            SAMPLER(sampler_DistortTex);

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
                float2 uv : TEXCOORD1;
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
                output.screenPos = ComputeScreenPos(pos.positionCS);
                output.uv = TRANSFORM_TEX(input.uv, _DistortTex);
                return output;
            }

            half4 frag(Varyings input) : SV_Target
            {
                /*
                算法原理（屏幕扭曲）：
                1) 从扭曲贴图读取一个二维偏移向量
                2) 用该偏移去采样相机的 OpaqueTexture
                3) 输出被偏折后的屏幕颜色，实现热浪/空气扰动

                核心公式：
                screenUV' = screenUV + distortion * _DistortStrength
                */
                float2 flow = float2(_DistortSpeedX, _DistortSpeedY) * _Time.y;
                float2 noiseUV = input.uv + flow;
                float2 distortion = SAMPLE_TEXTURE2D(_DistortTex, sampler_DistortTex, noiseUV).rg * 2.0 - 1.0;
                distortion *= _DistortStrength;

                float2 screenUV = input.screenPos.xy / input.screenPos.w;
                float2 distortedUV = saturate(screenUV + distortion);

                half3 sceneCol = SampleSceneColor(distortedUV);
                half3 finalRGB = sceneCol * _TintColor.rgb;
                half finalA = saturate(_Alpha * _TintColor.a);
                return half4(finalRGB, finalA);
            }
            ENDHLSL
        }
    }
}
