Shader "ELEX/URP/CommonEffects/SoftParticle"
{
    /*
    Soft Particle（软粒子）
    ------------------------------------------------------------
    适用场景：
    1) 烟雾、尘土、能量雾
    2) 粒子贴地/贴墙时的交界柔化

    核心思路：
    1) 读取场景深度（不透明物体深度）
    2) 计算“场景深度 - 粒子深度”
    3) 差值越小，说明越接近碰撞边界，alpha 越低

    注意：
    - 依赖 URP Renderer 的 Depth Texture 开关
    */
    Properties
    {
        [MainTexture] _BaseMap ("Particle Texture", 2D) = "white" {} // 粒子纹理；通常带 alpha 边缘渐隐。
        [MainColor] _BaseColor ("Tint Color", Color) = (1, 1, 1, 1) // 粒子颜色和亮度乘子。
        _Alpha ("Global Alpha", Range(0, 1)) = 1 // 全局透明度；在软粒子衰减后再次整体缩放。
        _SoftDistance ("Soft Distance", Range(0.001, 5)) = 0.5 // 软化距离；越大交界过渡越柔和。
        _ScrollX ("Scroll X", Range(-5, 5)) = 0 // U 方向滚动速度；常用于云烟流动。
        _ScrollY ("Scroll Y", Range(-5, 5)) = 0 // V 方向滚动速度；常用于云烟流动。
    }

    SubShader
    {
        Tags { "RenderPipeline"="UniversalPipeline" "RenderType"="Transparent" "Queue"="Transparent" }
        LOD 170
        Cull Back
        ZWrite Off
        Blend SrcAlpha OneMinusSrcAlpha

        Pass
        {
            Name "SoftParticle"
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
                float _SoftDistance;
                float _ScrollX;
                float _ScrollY;
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
                // UV 滚动
                float2 uv = input.uv + float2(_ScrollX, _ScrollY) * _Time.y;
                half4 col = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, uv) * _BaseColor;

                // 读取屏幕深度并转眼空间深度
                float2 screenUV = input.screenPos.xy / max(input.screenPos.w, 1e-5);
                float sceneRawDepth = SampleSceneDepth(screenUV);
                float sceneEyeDepth = LinearEyeDepth(sceneRawDepth, _ZBufferParams);

                // 当前粒子片元眼空间深度
                float fragEyeDepth = -TransformWorldToView(input.positionWS).z;

                // soft 因子：越靠近交界处越小
                float soft = saturate((sceneEyeDepth - fragEyeDepth) / max(_SoftDistance, 1e-5));

                col.a *= (_Alpha * soft);
                return col;
            }
            ENDHLSL
        }
    }
}
