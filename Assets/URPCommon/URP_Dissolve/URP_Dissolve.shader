Shader "ELEX/URP/CommonEffects/Dissolve"
{
    

/*
Moved From: ShaderCommonEffects_URP.md
Section: URP_Dissolve.shader

- 一句话：按噪声图逐步溶解消失。
- 视觉效果：像烧毁、蒸发、传送。
- 核心原理：
1. 噪声决定“哪块先消失”
2. `clip(noise - threshold)` 删除像素
3. 阈值边缘加发光色
- 关键参数：
- `_Dissolve`：进度（0 到 1）
- `_EdgeWidth`：边缘带宽度
- `_EdgeColor/_EdgeIntensity`：边缘视觉
- 常见坑：
- 噪声图太平会导致效果单调
- 核心代码：

```hlsl
clip(noise - _Dissolve);
float edgeMask = 1.0 - smoothstep(_Dissolve, _Dissolve + _EdgeWidth, noise);
```
*/
Properties
    {
        [MainTexture] _BaseMap ("Base Map", 2D) = "white" {} // 主纹理采样源；用于定义物体表面图案，且支持 Inspector 的 Tiling/Offset（通过 _BaseMap_ST 参与 UV 变换）。
        [MainColor] _BaseColor ("Base Color", Color) = (1, 1, 1, 1) // 主颜色乘子；与主纹理结果相乘，统一控制整体染色与亮度（RGBA 都会参与）。
        _NoiseTex ("Noise Texture", 2D) = "white" {} // 噪声纹理；决定像素的溶解先后顺序，常用灰度噪声或云纹贴图。
        _Dissolve ("Dissolve", Range(0, 1)) = 0 // 溶解进度；0 表示几乎不溶解，1 表示大部分像素被裁剪。
        _EdgeWidth ("Edge Width", Range(0, 0.2)) = 0.05 // 边缘宽度；控制阈值附近高亮边带的厚度，值大时边缘更宽。
        [HDR] _EdgeColor ("Edge Color", Color) = (1, 0.6, 0, 1) // 边缘颜色（HDR）；用于溶解边带的发光着色，可配合 Bloom。
        _EdgeIntensity ("Edge Intensity", Range(0, 5)) = 1 // 边缘强度；对边缘颜色做亮度放大，控制发光观感强弱。
    }

    SubShader
    {
        Tags { "RenderPipeline"="UniversalPipeline" "RenderType"="TransparentCutout" "Queue"="AlphaTest" }
        LOD 200
        Cull Back
        ZWrite On

        Pass
        {
            Name "Dissolve"
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
                float4 _NoiseTex_ST;
                float _Dissolve;
                float _EdgeWidth;
                float4 _EdgeColor;
                float _EdgeIntensity;
            CBUFFER_END

            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);
            TEXTURE2D(_NoiseTex);
            SAMPLER(sampler_NoiseTex);

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
                算法原理（Dissolve）：
                1) 用噪声纹理 noise 表示“每个像素被消融的先后顺序”
                2) clip(noise - threshold) 把低于阈值的像素直接丢弃
                3) 在阈值附近做一条边缘带，并叠加发光色

                核心公式：
                - 裁剪：clip(noise - _Dissolve)
                - 边缘掩码：edgeMask = 1 - smoothstep(_Dissolve, _Dissolve + _EdgeWidth, noise)
                */
                half4 baseCol = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv) * _BaseColor;

                // 噪声值决定溶解进度，可单独调节噪声贴图的 Tiling/Offset
                float2 noiseUV = input.uv * _NoiseTex_ST.xy + _NoiseTex_ST.zw;
                float noise = SAMPLE_TEXTURE2D(_NoiseTex, sampler_NoiseTex, noiseUV).r;

                // 调参速查（仅影响观感，不改变算法结构）：
                // - _Dissolve ↑：裁剪阈值升高，消失区域变多（整体“溶解进度”前进）
                // - _EdgeWidth ↑：边缘带更宽、更柔；↓：边缘更细、更锐利
                // - _EdgeIntensity ↑：边缘发光更亮；过高可能导致 Bloom 过曝
                // - _NoiseTex_ST.xy（Tiling）↑：噪声更密，边缘更碎；↓：块状更大
                // - _NoiseTex_ST.zw（Offset）变化：可让噪声采样平移，做“流动溶解”
                // clip：小于阈值的像素直接丢弃（硬裁剪）
                clip(noise - _Dissolve);

                // 边缘带：阈值附近更亮，用于火边/能量边视觉
                // smoothstep(a,b,x) 会在 x∈[a,b] 时输出 0->1 的平滑 S 曲线：
                //   t = saturate((x-a)/(b-a)); edge = t*t*(3-2*t)
                // 这里 a=_Dissolve, b=_Dissolve+_EdgeWidth, x=noise。
                // 特征值（对理解曲线形状很直观）：
                // - x<=a -> t=0 -> edge=0
                // - x>=b -> t=1 -> edge=1
                // - x=(a+b)/2 -> t=0.5 -> edge=0.5
                // - t=0.25 -> edge=0.15625（慢起步）
                // - t=0.75 -> edge=0.84375（快收尾）
                // 示例（_Dissolve=0.40,_EdgeWidth=0.05）：
                // - noise=0.40 -> edge=0
                // - noise=0.425 -> edge=0.5
                // - noise=0.45 -> edge=1
                // 与上面的 clip(noise - _Dissolve) 联动后：
                // - noise < _Dissolve：像素已被裁剪掉，不显示
                // - noise 从 _Dissolve 到 _Dissolve+_EdgeWidth：edge 从 0 平滑到 1
                // - noise > _Dissolve+_EdgeWidth：edge 为 1（无边缘增亮）
                float edge = smoothstep(_Dissolve, _Dissolve + _EdgeWidth, noise);
                // 反相后让“刚过阈值”的区域最亮：edgeMask 在边缘带内由 1->0 衰减
                float edgeMask = 1.0 - edge;

                half3 finalCol = baseCol.rgb + _EdgeColor.rgb * edgeMask * _EdgeIntensity;
                return half4(finalCol, baseCol.a);
            }
            ENDHLSL
        }
    }
}


