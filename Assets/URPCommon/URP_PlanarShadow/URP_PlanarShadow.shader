Shader "ELEX/URP/CommonEffects/PlanarShadow"
{
    

/*
Moved From: ShaderCommonEffects_URP.md
Section: URP_PlanarShadow.shader

- 一句话：把模型投影到一个平面上形成“假阴影”。
- 视觉效果：角色脚下稳定阴影，性能低成本。
- 核心原理（这是重点）：
1. 定义平面：`dot(n, x) + d = 0`
2. 给定顶点 `p` 与投影方向 `v`（光方向）
3. 求 `p + v*t` 落在平面上时的 `t`
4. 得到投影点 `p'`
5. 沿法线抬一点 `_ShadowBias`，防止 Z-fighting
6. 按原顶点离平面距离做透明衰减
- 关键参数：
- `_UseMainLight`：1 用主方向光，0 用 `_LightDirWS`
- `_PlaneNormal` / `_PlaneOffset`：定义平面
- `_ShadowBias`：防穿插抖动
- `_FadeDistance`：离平面越远阴影越淡
- 常见坑：
- 光方向与平面几乎平行时阴影会拉很长（代码已做保护，但视觉上仍需调光）
- 非平面地形不适合单平面阴影
- 核心代码：

```hlsl
float t = -(dot(planeN, posWS) + planeOffset) / dot(planeN, castDir);
float3 projectedWS = posWS + castDir * t;
projectedWS += planeN * _ShadowBias;
```
*/
Properties
    {
        [HDR] _ShadowColor ("Shadow Color", Color) = (0, 0, 0, 0.5) // 阴影颜色；用于平面投影阴影或卡通暗部着色（alpha 影响透明度）。
        _PlaneNormal ("Plane Normal (WS)", Vector) = (0, 1, 0, 0) // 平面法线（世界空间）；定义接收投影阴影的平面朝向。
        _PlaneOffset ("Plane Offset (dot(n, x) + d = 0)", Float) = 0 // 平面偏移 d；对应平面方程 dot(n, x) + d = 0 中的 d。
        _ShadowBias ("Shadow Bias", Range(0, 0.1)) = 0.01 // 阴影偏移；沿投影方向微移以减少与地面重叠产生的闪烁。
        _FadeDistance ("Fade Distance", Range(0.1, 20)) = 5 // 衰减距离；控制效果从强到弱的过渡范围（值越大，过渡越柔和）。

        [Toggle] _UseMainLight ("Use Main Directional Light", Float) = 1 // 主光开关；开启时使用场景主方向光，关闭时改用手动光方向。
        _LightDirWS ("Manual Light Dir (WS)", Vector) = (0.5, -1, 0.5, 0) // 手动光方向（世界空间）；仅在关闭主光开关时生效。
    }

    SubShader
    {
        Tags { "RenderPipeline"="UniversalPipeline" "RenderType"="Transparent" "Queue"="Transparent-10" }
        LOD 120
        Cull Off
        ZWrite Off
        ZTest LEqual
        Blend SrcAlpha OneMinusSrcAlpha

        Pass
        {
            Name "PlanarShadow"
            Tags { "LightMode"="SRPDefaultUnlit" }

            HLSLPROGRAM
            #pragma target 2.0
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_instancing

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float4 _ShadowColor;
                float4 _PlaneNormal;
                float _PlaneOffset;
                float _ShadowBias;
                float _FadeDistance;
                float _UseMainLight;
                float4 _LightDirWS;
            CBUFFER_END

            struct Attributes
            {
                float3 positionOS : POSITION;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                half shadowFade : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
                UNITY_VERTEX_OUTPUT_STEREO
            };

            Varyings vert(Attributes input)
            {
                Varyings output = (Varyings)0;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

                /*
                算法原理（Planar Shadow）：
                1) 先定义地面平面：dot(n, x) + d = 0
                2) 顶点沿投影方向 v 投到平面：
                   t = -(dot(n, p) + d) / dot(n, v)
                   p' = p + v * t
                3) p' 再沿平面法线略微抬高，避免与地面 Z-fighting
                4) 根据顶点离平面的距离做透明衰减

                核心公式：
                p' = p + v * (-(dot(n, p) + d) / dot(n, v))
                */
                float3 posWS = TransformObjectToWorld(input.positionOS);

                float3 planeN = _PlaneNormal.xyz;
                float nLen = max(length(planeN), 1e-5);
                planeN /= nLen;

                Light mainLight = GetMainLight();
                float3 castDirFromMain = normalize(-mainLight.direction);
                float3 manualDir = _LightDirWS.xyz;
                if (dot(manualDir, manualDir) < 1e-6)
                {
                    manualDir = float3(0.5, -1.0, 0.5);
                }
                float3 castDirFromManual = normalize(manualDir);
                float useMain = step(0.5, _UseMainLight);
                float3 castDir = normalize(lerp(castDirFromManual, castDirFromMain, useMain));

                float denom = dot(planeN, castDir);
                float denomAbs = max(abs(denom), 1e-4);
                denom = (denom >= 0.0) ? denomAbs : -denomAbs;

                float t = -(dot(planeN, posWS) + _PlaneOffset) / denom;
                t = max(0.0, t);

                float3 projectedWS = posWS + castDir * t;
                projectedWS += planeN * _ShadowBias;

                float distToPlane = abs(dot(planeN, posWS) + _PlaneOffset);
                output.shadowFade = saturate(1.0 - distToPlane / max(_FadeDistance, 1e-5));
                output.positionCS = TransformWorldToHClip(projectedWS);
                return output;
            }

            half4 frag(Varyings input) : SV_Target
            {
                half4 col = _ShadowColor;
                col.a *= input.shadowFade;
                return col;
            }
            ENDHLSL
        }
    }
}


