Shader "ELEX/URP/CommonEffects/HeightFog"
{
    /*
    Height Fog（高度雾）
    ------------------------------------------------------------
    适用场景：
    1) 低空薄雾、山谷雾层
    2) 需要按“世界高度”控制雾浓度

    核心思路：
    1) 根据像素世界坐标 y 计算高度雾权重
    2) 低于雾层起始高度时雾更浓
    3) 与基础受光结果做 lerp
    */
    Properties
    {
        [MainTexture] _BaseMap ("Base Map", 2D) = "white" {} // 基础纹理。
        [MainColor] _BaseColor ("Base Color", Color) = (1, 1, 1, 1) // 基础颜色乘子。
        _FogColor ("Fog Color", Color) = (0.75, 0.82, 0.88, 1) // 雾颜色。
        _FogStartHeight ("Fog Start Height", Float) = 0 // 雾层“最浓”高度起点（通常更低）。
        _FogEndHeight ("Fog End Height", Float) = 3 // 雾层“几乎无雾”高度终点（通常更高）。
        _FogDensity ("Fog Density", Range(0, 5)) = 1 // 雾密度倍率。
    }

    SubShader
    {
        Tags { "RenderPipeline"="UniversalPipeline" "RenderType"="Opaque" "Queue"="Geometry" }
        LOD 180
        Cull Back
        ZWrite On

        Pass
        {
            Name "HeightFog"
            Tags { "LightMode"="UniversalForward" }

            HLSLPROGRAM
            #pragma target 3.0
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_instancing

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseColor;
                float4 _BaseMap_ST;
                float4 _FogColor;
                float _FogStartHeight;
                float _FogEndHeight;
                float _FogDensity;
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
                VertexNormalInputs nrm = GetVertexNormalInputs(input.normalOS);
                output.positionCS = pos.positionCS;
                output.positionWS = pos.positionWS;
                output.normalWS = normalize(nrm.normalWS);
                output.uv = TRANSFORM_TEX(input.uv, _BaseMap);
                return output;
            }

            half4 frag(Varyings input) : SV_Target
            {
                half3 albedo = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv).rgb * _BaseColor.rgb;
                half3 N = normalize(input.normalWS);

                // 基础受光
                Light mainLight = GetMainLight();
                half ndotl = saturate(dot(N, mainLight.direction));
                half3 diffuse = albedo * mainLight.color * (0.25 + 0.75 * ndotl);
                half3 ambient = SampleSH(N) * albedo;
                half3 litColor = diffuse + ambient;

                // 高度雾因子：高度越低，雾越浓
                float hRange = max(_FogEndHeight - _FogStartHeight, 1e-5);
                float fogByHeight = saturate((_FogEndHeight - input.positionWS.y) / hRange);
                float fogFactor = saturate(fogByHeight * _FogDensity);

                half3 finalCol = lerp(litColor, _FogColor.rgb, fogFactor);
                return half4(finalCol, _BaseColor.a);
            }
            ENDHLSL
        }
    }
}
