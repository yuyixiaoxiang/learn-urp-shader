Shader "ELEX/URP/CommonEffects/Hologram"
{
    

/*
Moved From: ShaderCommonEffects_URP.md
Section: URP_Hologram.shader

效果概述
- 一句话：全息投影风格。
- 视觉效果：扫描线 + 轮廓发亮 + 轻微闪烁。
- 适用场景：科幻 UI、角色投影、能量体、传送门提示物。

实现思路
1. 用世界空间 positionWS.y 作为扫描坐标，这样扫描线会沿世界竖直方向统一流动。
2. 用 _Time.y * _ScanSpeed 推动扫描相位，让条纹随时间滚动。
3. 用 Fresnel 近似公式做边缘高亮，让轮廓比正面更亮。
4. 用 sin 做整体亮度轻微起伏，制造电子信号不稳定感。
5. 使用透明队列 + Additive 风格混合，让最终画面更像发光投影而不是实体表面。

渲染状态解读
- Queue=Transparent：放到透明队列，按透明物体渲染。
- ZWrite Off：不写深度，避免透明材质把后面的透明层完全挡住。
- Blend SrcAlpha One：加法偏发光混合。alpha 越大，加到背景上的颜色越强。
- Cull Back：默认只渲染正面，避免背面和正面同时叠加导致过亮。

关键数学
- frac(x)：只保留小数部分，把任意递增值压回 0~1 的循环相位。
- abs(x - 0.5)：求当前相位离扫描中心的距离。
- smoothstep(a, b, x)：在 a~b 内做平滑过渡，这里用来做柔和扫描边缘。
- dot(N, V)：法线和视线的夹角余弦，越接近 1 表示越正对摄像机。
- 1 - dot(N, V)：越靠轮廓值越大，所以适合做边缘光。
- pow(fresnel, _RimPower)：控制边缘光宽度；幂越大，边缘越细越锐。
- sin(_Time.y * _FlickerSpeed)：输出周期性波动，用来模拟亮度闪烁。

关键参数
- _ScanDensity：扫描线密度，越大条纹越密。
- _ScanSpeed：扫描速度，负值可反向滚动。
- _ScanWidth：单条扫描线宽度。
- _RimPower：边缘光聚焦程度。
- _FlickerSpeed：闪烁频率。

常见坑
- 如果 _ScanWidth 太小而 _ScanDensity 太大，条纹会过细，远处容易闪烁或丢失。
- Blend SrcAlpha One 偏加法，HDR 颜色和 Bloom 一起用时很容易过曝。
- 扫描线基于世界空间 Y，物体整体升高时，条纹相位也会改变；这是设计特性，不是 UV 漂移 bug。
- 过高的闪烁速度会影响可读性，尤其是 UI 或小模型。

主要中间变量范围
- baseTex.rgb：通常在 0~1；如果 _BaseColor 被设为 HDR，也可能超过 1。
- baseTex.a：通常在 0~1。
- scanPhase：frac(...) 后稳定在 [0, 1)。
- abs(scanPhase - 0.5)：稳定在 [0, 0.5]。
- scanMask：smoothstep 反转后稳定在 [0, 1]；只有扫描中心附近才明显大于 0。
- dot(N, V)：理论上在 [-1, 1]；对常见可见正面像素通常在 [0, 1]。
- rim：pow 之后稳定在 [0, 1]；正面接近 0，轮廓接近 1。
- flicker：0.8 + 0.2 * sin(...)，因此稳定在 [0.6, 1.0]。
- baseTex.a * _Alpha：在 [0, 1]；默认 _Alpha=0.55 且贴图 alpha=1 时最大为 0.55。
- rim * 0.35：在 [0, 0.35]。
- scanMask * 0.25：在 [0, 0.25]。
- alpha：saturate 后稳定在 [0, 1]。
- rgb：理论上大于等于 0；由于 _ScanColor / _RimColor 支持 HDR，所以可明显大于 1。

核心公式
```hlsl
float scanPhase = frac(input.positionWS.y * _ScanDensity + _Time.y * _ScanSpeed);
float scanMask = 1.0 - smoothstep(0.0, _ScanWidth, abs(scanPhase - 0.5));
half rim = pow(1.0 - saturate(dot(N, V)), _RimPower);
half flicker = 0.8 + 0.2 * sin(_Time.y * _FlickerSpeed);
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
        // 作为透明的 URP 特效渲染：不追求真实光照，重点是发光投影感。
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

                // 把模型空间顶点/法线转换到片元阶段更容易使用的空间：
                // positionCS 用于屏幕光栅化，positionWS/normalWS 用于世界空间效果。
                VertexPositionInputs pos = GetVertexPositionInputs(input.positionOS);
                VertexNormalInputs normalInput = GetVertexNormalInputs(input.normalOS);

                output.positionCS = pos.positionCS;
                output.positionWS = pos.positionWS;
                output.normalWS = normalize(normalInput.normalWS);
                // TRANSFORM_TEX 等价于 uv * _BaseMap_ST.xy + _BaseMap_ST.zw，
                // 也就是把材质面板里的 Tiling / Offset 应用到 UV。
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
                scanPhase = frac(posWS.y * density + time * speed)
                scanMask = 1 - smoothstep(0, width, abs(scanPhase - 0.5))
                rim = pow(1 - dot(N, V), rimPower)

                这里不是物理真实材质，而是把 3 个风格化信号叠加到一起：
                baseTex  : 基础底色
                scanMask : 扫描线亮带
                rim      : 轮廓边缘光
                */
                // 基础颜色层：贴图定义局部花纹，_BaseColor 统一决定整体染色。
                half4 baseTex = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv) * _BaseColor;

                // 扫描线相位：
                // positionWS.y 负责“条纹在物体哪一段出现”，_Time.y 负责“条纹在动”。
                // frac 会把不断增长的值折回 0~1，得到周期性循环。
                float scanPhase = frac(input.positionWS.y * _ScanDensity + _Time.y * _ScanSpeed);
                // 以 0.5 为扫描中心做一条窄亮带：
                // abs(scanPhase - 0.5) 越小，说明越接近扫描中心；
                // smoothstep 让亮带边缘柔和，1.0 - ... 则把“中心亮、外围暗”反转出来。
                // 数值范围：
                // scanPhase ∈ [0, 1)
                // abs(scanPhase - 0.5) ∈ [0, 0.5]
                // scanMask ∈ [0, 1]
                float scanMask = 1.0 - smoothstep(0.0, _ScanWidth, abs(scanPhase - 0.5));

                // Fresnel/Rim：
                // dot(N, V) 越小，说明法线越偏离视线，也就是越靠近物体轮廓。
                // 再通过 pow 调整轮廓宽度和锐度。
                // 数值范围：
                // dot(N, V) ∈ [-1, 1]
                // saturate(dot(N, V)) ∈ [0, 1]
                // rim ∈ [0, 1]
                half3 N = normalize(input.normalWS);
                half3 V = normalize(GetWorldSpaceViewDir(input.positionWS));
                half rim = pow(1.0 - saturate(dot(N, V)), _RimPower);

                // 周期性闪烁，范围大约在 0.6~1.0 之间。
                // 振幅不大，只是让它“活”起来，而不是明显明灭。
                half flicker = 0.8 + 0.2 * sin(_Time.y * _FlickerSpeed);

                // 颜色合成策略：
                // 1. 先压低底图亮度，避免看起来像实体漫反射。
                // 2. 叠加扫描线和边缘光的 HDR 颜色。
                // 3. 最后统一乘 flicker，让整体一起轻微抖动。
                half3 rgb = baseTex.rgb * 0.35;
                rgb += _ScanColor.rgb * scanMask;
                rgb += _RimColor.rgb * rim;
                rgb *= flicker;

                // alpha 不只由底图决定，还额外受 rim 和 scanMask 提升。
                // 这样扫描线经过和边缘区域会更“实”、更容易被看见。
                // 分项范围：
                // baseTex.a * _Alpha ∈ [0, 1]
                // rim * 0.35 ∈ [0, 0.35]
                // scanMask * 0.25 ∈ [0, 0.25]
                // saturate 之后 alpha ∈ [0, 1]
                half alpha = saturate(baseTex.a * _Alpha + rim * 0.35 + scanMask * 0.25);
                return half4(rgb, alpha);
            }
            ENDHLSL
        }
    }
}


