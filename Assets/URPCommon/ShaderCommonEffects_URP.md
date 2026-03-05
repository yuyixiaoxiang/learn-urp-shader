# URP 常用 Shader 效果手册（小白详细版）

这份文档是给 Unity / 图形学初学者准备的。

你不需要先懂很多数学，只要按文档一步步看，就能知道：

1. 一个 shader 到底在做什么
2. 看到效果后该调哪个参数
3. 出问题时应该先查哪里

当前目录共有 21 个 shader（全部在本文覆盖）：

- `URP_UnlitTexture.shader`
- `URP_LitLambert.shader`
- `URP_NormalMapLambert.shader`
- `URP_Toon.shader`
- `URP_RimFresnel.shader`
- `URP_FresnelTransparent.shader`
- `URP_MatCap.shader`
- `URP_Triplanar.shader`
- `URP_Dissolve.shader`
- `URP_UVScroll.shader`
- `URP_FlowMap.shader`
- `URP_VertexWave.shader`
- `URP_PolarTwirl.shader`
- `URP_Outline.shader`
- `URP_AlphaBlend.shader`
- `URP_Additive.shader`
- `URP_AlphaClip.shader`
- `URP_DepthFade.shader`
- `URP_ScreenDistortion.shader`
- `URP_Hologram.shader`
- `URP_PlanarShadow.shader`

---

## 0. 看懂本文前，你只要掌握这 12 个关键词

### 0.1 顶点阶段（Vertex）

- 处理每个顶点
- 常做事：坐标变换、顶点位移（比如波浪）

### 0.2 片元阶段（Fragment / Pixel）

- 处理每个屏幕像素
- 常做事：采样贴图、算颜色、算透明度

### 0.3 坐标空间（非常重要）

- `OS`（Object Space）：模型本地坐标
- `WS`（World Space）：世界坐标
- `VS`（View Space）：相机坐标
- `CS`（Clip Space）：裁剪坐标，最终用于光栅化

你在代码中经常会看到：`positionOS -> positionWS -> positionCS`

### 0.4 法线（Normal）

- 法线表示“表面朝向”
- 与光方向点乘（dot）后可以得到明暗

### 0.5 `dot(a, b)`

- 两向量夹角关系
- 结果越大，方向越一致
- 光照里常用 `dot(N, L)`

### 0.6 `saturate(x)`

- 把值夹到 `[0,1]`
- 很多光照值必须这样处理，避免负亮度

### 0.7 `smoothstep(a, b, x)`

- 平滑过渡函数
- 常用于边缘柔和，不会硬切

### 0.8 `clip(x)`

- `x < 0` 的像素直接丢弃
- 用于镂空裁剪、溶解等

### 0.9 Blend（混合）

- `Blend SrcAlpha OneMinusSrcAlpha`：普通透明
- `Blend One One`：叠加发光（越叠越亮）

### 0.10 ZWrite / ZTest

- `ZWrite On`：写入深度，后面的物体会被挡住
- 透明通常 `ZWrite Off`，否则会出现排序问题

### 0.11 Render Queue

- `Geometry`：不透明
- `AlphaTest`：裁剪类（clip）
- `Transparent`：透明类

### 0.12 URP 里常见依赖开关

- `Depth Texture`：DepthFade 依赖
- `Opaque Texture`：ScreenDistortion 依赖

---

## 1. 新手推荐学习顺序

按这个顺序学，最稳：

1. `UnlitTexture`
2. `LitLambert`
3. `NormalMapLambert`
4. `AlphaBlend` / `Additive` / `AlphaClip`
5. `RimFresnel` / `FresnelTransparent`
6. `Dissolve`
7. `UVScroll` / `FlowMap`
8. `VertexWave` / `PolarTwirl`
9. `DepthFade` / `ScreenDistortion`
10. `Outline` / `PlanarShadow`
11. `Toon` / `MatCap` / `Triplanar` / `Hologram`

---

## 2. 每个 Shader 详细讲解（效果 + 原理 + 参数 + 常见坑 + 核心代码）

## 2.1 URP_UnlitTexture.shader

- 一句话：最基础贴图显示，不受灯光影响。
- 视觉效果：灯光再亮再暗，物体颜色基本不变。
- 核心原理：
1. 采样 `_BaseMap`
2. 乘 `_BaseColor`
3. 直接输出
- 关键参数：
- `_BaseMap`：主贴图
- `_BaseColor`：整体染色和透明度
- 常见坑：
- 觉得“太平”，这是正常的，因为没有光照
- 核心代码：

```hlsl
half4 baseCol = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv);
baseCol *= _BaseColor;
return baseCol;
```

## 2.2 URP_LitLambert.shader

- 一句话：最标准的“朝光面亮、背光面暗”。
- 视觉效果：基础真实感，适合入门受光物体。
- 核心原理：
1. `N = 法线`，`L = 光方向`
2. 计算 `NdotL = max(0, dot(N,L))`
3. 主光 + 附加光 + 环境光叠加
- 关键参数：
- `_BaseMap`：颜色细节
- `_BaseColor`：整体亮度色调
- 常见坑：
- 模型法线错误会导致亮暗反转
- 核心代码：

```hlsl
half ndotl = saturate(dot(N, mainLight.direction));
half3 diffuse = albedo * mainLight.color * ndotl;
half3 ambient = SampleSH(N) * albedo;
```

## 2.3 URP_NormalMapLambert.shader

- 一句话：在 Lambert 上加法线贴图，凹凸感更明显。
- 视觉效果：模型面数不高，也会有细节起伏。
- 核心原理：
1. 法线贴图采样得到 `normalTS`（切线空间）
2. 通过 TBN 转到世界空间 `normalWS`
3. 用 `normalWS` 参与 Lambert
- 关键参数：
- `_NormalMap`：法线贴图
- `_NormalScale`：法线强度，越高凹凸越明显
- 常见坑：
- 法线贴图导入类型要设为 Normal Map
- 模型要有正确 tangent
- 核心代码：

```hlsl
half3 normalTS = UnpackNormalScale(texNormal, _NormalScale);
half3 N = normalize(T * normalTS.x + B * normalTS.y + N0 * normalTS.z);
```

## 2.4 URP_Toon.shader

- 一句话：把连续光照变成分段光照，做卡通风。
- 视觉效果：明暗分层明显，边界干净。
- 核心原理：
1. 先得到 `ndotl`
2. 用 `floor` 量化成若干台阶
3. 在阴影色和亮色间插值
- 关键参数：
- `_RampSteps`：层数，2~4 常用
- `_ShadowColor`：暗部颜色
- `_ShadowThreshold/_ShadowSmooth`：单阈值模式时控制边缘
- 常见坑：
- 阶梯太少会“跳层”严重
- 核心代码：

```hlsl
half ramp = floor(ndotl * steps) / max(1.0, steps - 1.0);
half3 toonTint = lerp(_ShadowColor.rgb, 1.0, ramp);
```

## 2.5 URP_RimFresnel.shader

- 一句话：轮廓边缘发亮。
- 视觉效果：物体外圈有“包边高光”。
- 核心原理：
1. 计算视线 `V` 与法线 `N` 的 dot
2. 越靠边（dot 小）亮度越高
3. 幂函数控制衰减曲线
- 关键参数：
- `_RimPower`：边缘范围
- `_RimIntensity`：亮度
- `_RimColor`：边缘颜色
- 常见坑：
- 强度过高会发白溢出
- 核心代码：

```hlsl
half rim = pow(1.0 - saturate(dot(N, V)), _RimPower) * _RimIntensity;
```

## 2.6 URP_FresnelTransparent.shader

- 一句话：透明物体边缘更实更亮。
- 视觉效果：玻璃/力场的轮廓更明显。
- 核心原理：
1. 用 Fresnel 得到边缘权重
2. 同时加到颜色和 alpha
- 关键参数：
- `_Alpha`：基础透明
- `_FresnelAlphaBoost`：边缘额外不透明
- `_FresnelPower`：边缘宽窄
- 常见坑：
- alpha 太低会导致主体几乎看不见
- 核心代码：

```hlsl
half fresnel = pow(1.0 - saturate(dot(N, V)), _FresnelPower);
half finalA = saturate(baseCol.a * _Alpha + fresnel * _FresnelAlphaBoost);
```

## 2.7 URP_MatCap.shader

- 一句话：用一张 MatCap 贴图快速模拟材质光感。
- 视觉效果：金属/陶瓷/泥塑等风格化反射感。
- 核心原理：
1. 世界法线 -> 观察空间法线
2. 用 `normalVS.xy` 当 matcap 的 UV
3. 采样 matcap 乘到基础色
- 关键参数：
- `_MatCapTex`：风格核心
- `_MatCapStrength`：影响强度
- 常见坑：
- matcap 图质量决定上限
- 核心代码：

```hlsl
float3 normalVS = normalize(TransformWorldToViewDir(input.normalWS, true));
float2 matcapUV = normalVS.xy * 0.5 + 0.5;
```

## 2.8 URP_Triplanar.shader

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

## 2.9 URP_Dissolve.shader

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

## 2.10 URP_UVScroll.shader

- 一句话：贴图按固定速度滚动。
- 视觉效果：水流、能量流、云层流动。
- 核心原理：`uv = uv + speed * time`
- 关键参数：
- `_ScrollX / _ScrollY`：滚动速度方向
- 常见坑：
- 贴图边缘不无缝会“接缝跳变”
- 核心代码：

```hlsl
float2 uv = input.uv + float2(_ScrollX, _ScrollY) * _Time.y;
```

## 2.11 URP_FlowMap.shader

- 一句话：按 FlowMap 指定方向流动。
- 视觉效果：局部绕流、分叉流，比 UVScroll 更自然。
- 核心原理：
1. `flowRG` 映射到 `[-1,1]`
2. 两相位偏移采样
3. 交替混合降低相位跳变
- 关键参数：
- `_FlowMap`：方向图（RG）
- `_FlowStrength`：偏移幅度
- `_FlowSpeed`：速度
- 常见坑：
- FlowMap 太噪会造成撕裂感
- 核心代码：

```hlsl
float2 flow = SAMPLE_TEXTURE2D(_FlowMap, sampler_FlowMap, flowUV).rg * 2.0 - 1.0;
float2 uv0 = uv + flow * phase0;
float2 uv1 = uv + flow * phase1;
```

## 2.12 URP_VertexWave.shader

- 一句话：直接让模型顶点上下波动。
- 视觉效果：草摆动、旗子抖动、水面起伏。
- 核心原理：
1. 相位 `phase = 位置影响 + 时间影响`
2. `sin(phase)` 得波形
3. 加到顶点 y
- 关键参数：
- `_WaveAmplitude`：振幅
- `_WaveFrequency`：频率
- `_WaveSpeed`：速度
- `_WaveDirection`：传播方向
- 常见坑：
- 振幅过大容易穿插
- 核心代码：

```hlsl
float phase = dot(posOS.xz, dir) * _WaveFrequency + _Time.y * _WaveSpeed;
posOS.y += sin(phase) * _WaveAmplitude;
```

## 2.13 URP_PolarTwirl.shader

- 一句话：中心旋涡扭曲。
- 视觉效果：黑洞、能量门、法阵扭曲。
- 核心原理：
1. 计算像素到中心的距离
2. 距离越近旋转角越大
3. 旋转 UV 后采样
- 关键参数：
- `_Center`：扭曲中心
- `_TwirlStrength`：扭曲强度
- `_Radius`：影响半径
- 常见坑：
- 半径太小几乎看不出效果
- 核心代码：

```hlsl
float angle = _TwirlStrength * saturate(1.0 - dist / _Radius);
float2 rotated = float2(offset.x * c - offset.y * s, offset.x * s + offset.y * c);
```

## 2.14 URP_Outline.shader

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

## 2.15 URP_AlphaBlend.shader

- 一句话：标准透明混合。
- 视觉效果：玻璃、薄膜、半透明物体。
- 核心原理：
- 输出时按 `srcA` 与背景混合
- 关键参数：
- `_Alpha`：整体透明度
- 常见坑：
- 多个透明物体互相穿插时排序不完美（常见）
- 核心代码：

```hlsl
Blend SrcAlpha OneMinusSrcAlpha
baseCol.a *= _Alpha;
```

## 2.16 URP_Additive.shader

- 一句话：发光叠加。
- 视觉效果：火焰、魔法、爆炸余辉。
- 核心原理：源色直接加到背景色。
- 关键参数：
- `_Intensity`：发光强度
- 常见坑：
- 亮背景里效果会变弱（因为本来就很亮）
- 核心代码：

```hlsl
Blend One One
baseCol.rgb *= _Intensity;
```

## 2.17 URP_AlphaClip.shader

- 一句话：硬裁剪镂空。
- 视觉效果：树叶边缘、铁丝网、洞口。
- 核心原理：alpha 小于阈值的像素直接丢弃。
- 关键参数：
- `_Cutoff`：阈值
- 常见坑：
- 边缘会锯齿，这是硬裁剪的特征
- 核心代码：

```hlsl
clip(baseCol.a - _Cutoff);
```

## 2.18 URP_DepthFade.shader

- 一句话：特效与地面交界变柔和。
- 视觉效果：烟雾/能量贴地处不再硬切。
- 核心原理：
1. 读取场景深度
2. 计算与当前片元深度差
3. 差小则透明度更低
- 关键参数：
- `_FadeDistance`：衰减距离
- `_Alpha`：基础透明
- 常见坑：
- 没开 `Depth Texture` 会失效
- 核心代码：

```hlsl
float sceneEye = LinearEyeDepth(SampleSceneDepth(screenUV), _ZBufferParams);
float fragEye = -TransformWorldToView(input.positionWS).z;
float fade = saturate((sceneEye - fragEye) / _FadeDistance);
```

## 2.19 URP_ScreenDistortion.shader

- 一句话：扭曲后面的屏幕画面。
- 视觉效果：热浪、空气扰动、隐身波纹。
- 核心原理：
1. 读取扭曲贴图的偏移向量
2. 偏移屏幕 UV
3. 采样 `OpaqueTexture`
- 关键参数：
- `_DistortStrength`：扭曲幅度
- `_DistortSpeedX/Y`：流动速度
- 常见坑：
- 没开 `Opaque Texture` 会失效
- 核心代码：

```hlsl
float2 distortion = (noiseRG * 2 - 1) * _DistortStrength;
half3 sceneCol = SampleSceneColor(screenUV + distortion);
```

## 2.20 URP_Hologram.shader

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

## 2.21 URP_PlanarShadow.shader

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

---

## 3. 快速选型总表（按需求）

- UI/图标/简单特效贴图：`UnlitTexture`
- 基础受光：`LitLambert`
- 凹凸细节：`NormalMapLambert`
- 卡通角色：`Toon + Outline`
- 能量边缘：`RimFresnel / FresnelTransparent`
- 角色低成本阴影：`PlanarShadow`
- 溶解消失：`Dissolve`
- 水流/岩浆流：`UVScroll / FlowMap`
- 热浪折射：`ScreenDistortion`
- 全息风格：`Hologram`
- 无 UV 地形：`Triplanar`
- 发光特效：`Additive`
- 树叶镂空：`AlphaClip`

---

## 4. Unity 内实际使用步骤（从 0 到 1）

1. 创建材质：`Create > Material`
2. 选择 Shader：`ELEX/URP/CommonEffects/...`
3. 赋贴图和参数
4. 把材质拖到模型上
5. 调参时遵循：
- 先调“范围参数”（强度/宽度/速度）
- 再调颜色
- 最后调透明和混合

---

## 5. 两个必须检查的 URP 开关

- `Depth Texture`：DepthFade 需要
- `Opaque Texture`：ScreenDistortion 需要

路径通常在：URP Renderer Asset -> Rendering -> Depth Texture / Opaque Texture

---

## 6. 透明相关高频问题（新手最容易踩坑）

### 6.1 为什么透明物体前后顺序看起来不对

- 原因：透明队列按对象排序，不是按每个像素绝对正确排序
- 解决方向：
- 尽量避免多个大面积透明体重叠
- 调整 render queue
- 分层拆模型

### 6.2 为什么透明边缘发黑或奇怪

- 看贴图 alpha 通道
- 看是否使用了错误混合模式
- 看是否颜色空间、贴图压缩造成边缘污染

### 6.3 为什么特效贴地处硬切

- 用 `DepthFade`
- 确认 `Depth Texture` 已开启

---

## 7. 调参经验（实战）

- 先把参数拉到极端看变化方向，再回调到合理值
- 一个参数只改一个维度：
- 强度参数控制“有多强”
- 范围参数控制“影响多宽”
- 速度参数控制“变化多快”
- 色彩参数最后调，不要最先陷入调色

---

## 8. 如果你想继续进阶，建议下一步学什么

1. 法线贴图与切线空间（TBN）
2. 阴影坐标与深度空间
3. BRDF（从 Lambert 到 PBR）
4. 后处理与屏幕空间效果
5. GPU Instancing 与 SRP Batcher 优化

---

## 9. 本仓库阅读建议（给小白）

每个 shader 都已经加入“算法原理 + 核心公式”注释。推荐阅读方式：

1. 先看 `Properties`（知道可调什么）
2. 看 `SubShader` 的 `Blend / ZWrite / Queue`（知道渲染行为）
3. 看 `vert`（几何怎么变）
4. 看 `frag`（颜色怎么算）
5. 回到场景里拖动参数，建立直觉

这样学 3~5 个效果后，你会明显感觉“shader 不再神秘”。

---

## 10. 一套可复现的测试场景（建议你照做一次）

如果你是小白，最怕“代码看懂了，但场景里不知道怎么验证”。  
下面是一套可复现步骤，你只要照着做，就能把文档里 80% 的效果跑起来。

### 10.1 场景搭建

1. 新建空场景 `ShaderPlayground`
2. 放一个 `Plane`（当地面）
3. 放 `Sphere / Capsule / Cube` 各一个
4. 放一个 Directional Light（默认即可）
5. 放一个 Camera，对准地面和三个模型
6. 确认项目是 URP（不是 Built-in）

### 10.2 材质准备

1. 新建 21 个材质（可先少建）
2. 每个材质选对应 shader：`ELEX/URP/CommonEffects/...`
3. 把材质分别拖到不同模型上测试

### 10.3 先测这 6 个（最容易建立直觉）

1. `UnlitTexture`：确认不受光照影响
2. `LitLambert`：转动物体，观察明暗变化
3. `AlphaBlend`：降低 `_Alpha` 看透明
4. `Additive`：加亮背景，看叠加发光
5. `Dissolve`：拖动 `_Dissolve` 看消失
6. `VertexWave`：调 `_WaveSpeed` 看动态

---

## 11. 参数起始值速查（你可以直接抄）

这些是“起步好看”的经验值，不是绝对值。

### 11.1 发光/边缘类

- `RimFresnel`
- `_RimPower = 2.0`
- `_RimIntensity = 0.8`
- `FresnelTransparent`
- `_Alpha = 0.25`
- `_FresnelPower = 3.0`
- `_FresnelAlphaBoost = 0.5`
- `Hologram`
- `_ScanDensity = 30`
- `_ScanSpeed = 2`
- `_RimPower = 3`
- `_FlickerSpeed = 6`

### 11.2 动态/流动类

- `UVScroll`
- `_ScrollX = 0.2`
- `_ScrollY = 0.0`
- `FlowMap`
- `_FlowStrength = 0.1`
- `_FlowSpeed = 1.2`
- `VertexWave`
- `_WaveAmplitude = 0.05`
- `_WaveFrequency = 2.0`
- `_WaveSpeed = 1.5`
- `PolarTwirl`
- `_TwirlStrength = 5`
- `_Radius = 0.6`

### 11.3 透明/裁剪类

- `AlphaBlend`
- `_Alpha = 0.5`
- `AlphaClip`
- `_Cutoff = 0.45`
- `DepthFade`
- `_Alpha = 0.8`
- `_FadeDistance = 0.5`
- `ScreenDistortion`
- `_DistortStrength = 0.02`
- `_DistortSpeedX = 0.5`
- `_DistortSpeedY = 0.1`

### 11.4 风格化/投影类

- `Toon`
- `_RampSteps = 3`
- `_ShadowThreshold = 0.5`
- `_ShadowSmooth = 0.02`
- `Outline`
- `_OutlineWidth = 0.005 ~ 0.015`
- `Triplanar`
- `_Tiling = 2`
- `_BlendSharpness = 4`
- `PlanarShadow`
- `_UseMainLight = 1`
- `_ShadowBias = 0.01`
- `_FadeDistance = 4`

---

## 12. PlanarShadow 专项说明（详细版）

因为你刚要求了 Planar Shadow，这里单独讲透。

### 12.1 什么时候用 Planar Shadow

- 你想要“性能便宜的角色落地阴影”
- 地面基本可近似为平面
- 不追求真实软阴影细节

### 12.2 它不是实时阴影贴图的替代品

Planar Shadow 是“投影假阴影”，优点是便宜、稳定；  
但它不能正确投到复杂凹凸地形，也不能表现真实遮挡关系。

### 12.3 平面方程到底是什么意思

文档里看到：`dot(n, x) + d = 0`

- `n`：平面法线方向（例如地面通常 `(0,1,0)`）
- `d`：平面偏移

如果你的平面就是 `y=0`，那么可用：

- `n = (0,1,0)`
- `d = 0`

### 12.4 最常见的配置方法

1. `_PlaneNormal = (0,1,0,0)`
2. `_PlaneOffset = 0`
3. `_UseMainLight = 1`
4. `_ShadowBias = 0.01`
5. `_FadeDistance = 4~8`

### 12.5 常见问题和处理

- 阴影离角色太远：
- 检查光方向是否异常（尤其是手动 `_LightDirWS`）
- 阴影闪烁：
- 适当增加 `_ShadowBias`（例如 0.005 -> 0.02）
- 阴影太硬太黑：
- 降低 `_ShadowColor.a`，比如 0.6 -> 0.35
- 斜坡地形不贴合：
- 这是单平面方案天生限制，考虑改 Blob Shadow 或真实阴影

---

## 13. 新手高频报错/异常对照

### 13.1 “看不到 Distortion”

- 原因：`Opaque Texture` 没开
- 检查：URP Renderer Asset -> Opaque Texture

### 13.2 “DepthFade 没反应”

- 原因：`Depth Texture` 没开
- 检查：URP Renderer Asset -> Depth Texture

### 13.3 “法线贴图看起来不对”

- 原因：法线贴图导入类型错误
- 检查：Texture Import Settings -> Texture Type = Normal map

### 13.4 “透明物体排序乱”

- 原因：透明渲染天然问题
- 处理：拆网格、调 Queue、减少大面积透明重叠

### 13.5 “Outline 很抖或断裂”

- 原因：模型法线质量差或描边太宽
- 处理：优化法线、减小 `_OutlineWidth`

---

## 14. 给小白的练习任务（建议）

### 任务 1：做一个“能量护盾”

组合建议：

- 基础：`FresnelTransparent`
- 增强：`RimColor` 偏蓝
- 动态：可叠加 `Hologram` 思路做扫描线

### 任务 2：做一个“燃烧消失”

组合建议：

- 主体：`Dissolve`
- 边缘：`_EdgeColor` 设橙黄
- 附加：叠一个 `Additive` 粒子

### 任务 3：做一个“角色落地阴影”

组合建议：

- 阴影：`PlanarShadow`
- 角色描边：`Outline`
- 如果地形复杂：改成更通用阴影方案

---

## 15. 最后给你的学习建议（真心实用）

如果你是小白，不要一上来追“最炫技”的 shader。  
最有效路线是：
1. 先理解渲染状态（Blend/ZWrite/Queue）
2. 再理解法线和 `dot`
3. 再玩动态 UV 与顶点位移
4. 最后再学屏幕空间效果

按这个顺序，你学习速度会明显更快，而且不容易卡住。

---

## 16. 7 天学习路线（每天 30~60 分钟）

如果你希望“不是看懂，而是真的会做”，可以按这个计划执行。

### Day 1：看见渲染状态的影响

目标：

1. 区分 `Opaque / AlphaTest / Transparent`
2. 感受到 `Blend / ZWrite / Queue` 的区别

实操：

1. 同一个模型分别挂 `UnlitTexture / AlphaBlend / AlphaClip`
2. 只改一个参数，观察画面变化

通过标准：

1. 你能解释为什么 `AlphaBlend` 常常 `ZWrite Off`
2. 你能解释 `AlphaClip` 为什么边缘是硬的

### Day 2：最基础光照

目标：

1. 理解 `dot(N, L)` 在控制明暗
2. 理解法线错误会导致光照错误

实操：

1. 对比 `UnlitTexture` 和 `LitLambert`
2. 换一个法线不平滑的模型看差异

通过标准：

1. 你能说出 Lambert 的核心公式
2. 你能看出“法线问题”和“贴图问题”的区别

### Day 3：法线贴图 + 风格化

目标：

1. 学会法线贴图正确导入
2. 学会 Toon 阶梯调参

实操：

1. 用 `NormalMapLambert` 调 `_NormalScale`
2. 用 `Toon` 调 `_RampSteps`

通过标准：

1. 你能把“凹凸强度”调到自然不过度
2. 你能做出 2 档和 4 档卡通明暗

### Day 4：透明与发光

目标：

1. 清楚普通透明和加色叠加的视觉差异
2. 理解为什么发光特效常用 Additive

实操：

1. 对比 `AlphaBlend` 与 `Additive`
2. 用 `FresnelTransparent` 做护盾

通过标准：

1. 你能解释“为什么 Additive 在亮背景不明显”
2. 你能做一个边缘更亮的透明材质

### Day 5：动态效果

目标：

1. 学会时间驱动 (`_Time.y`)
2. 学会 UV 动和顶点动的区别

实操：

1. `UVScroll` / `FlowMap` / `VertexWave`
2. 调速度和强度，找“可用范围”

通过标准：

1. 你能判断一个动态应该放在 UV 还是顶点
2. 你能避免“抖得太厉害”的参数组合

### Day 6：屏幕空间 + 深度

目标：

1. 理解为什么某些效果依赖 Renderer 开关
2. 学会排查 Depth/Opaque 相关问题

实操：

1. `DepthFade` 看贴地软化
2. `ScreenDistortion` 看背景扭曲

通过标准：

1. 你能独立解决“效果没反应”的开关问题
2. 你能解释屏幕扭曲是在采样相机颜色

### Day 7：组合实战

目标：

1. 把 2~3 个效果组合成一个完整小特效
2. 学会“先功能后美术”的调参流程

实操：

1. 护盾：`FresnelTransparent + Hologram`
2. 传送：`Dissolve + Additive + Rim`
3. 角色脚下阴影：`PlanarShadow`

通过标准：

1. 你可以从空材质在 20 分钟内搭建一个可用特效
2. 你能清晰说出每个参数在控制什么

---

## 17. 21 个 Shader 的“验收标准”

下面是“你做完后应该看到什么”的检查清单。

### 17.1 基础显示

- `UnlitTexture`：关灯后仍能稳定显示
- `LitLambert`：转动模型可见明暗面变化
- `NormalMapLambert`：低模表面出现凹凸细节

### 17.2 风格化

- `Toon`：明暗分层明显，不是连续渐变
- `RimFresnel`：轮廓边缘明显更亮
- `FresnelTransparent`：边缘更实、中心更透
- `MatCap`：旋转模型时光感风格随视角变化
- `Triplanar`：无 UV 也能正确铺贴，不明显拉伸
- `Hologram`：扫描线和闪烁都可见

### 17.3 动态与形变

- `UVScroll`：纹理沿固定方向移动
- `FlowMap`：局部方向流动，不是统一平移
- `VertexWave`：模型几何有真实起伏
- `PolarTwirl`：中心区域有旋涡扭曲

### 17.4 透明与特效

- `AlphaBlend`：背景可透过，透明平滑
- `Additive`：叠加后明显变亮
- `AlphaClip`：洞边是硬切不是半透明
- `Dissolve`：随进度逐步消失，边缘带清楚
- `DepthFade`：与地面交界不硬切
- `ScreenDistortion`：背景发生扭曲

### 17.5 几何附加

- `Outline`：模型外有稳定描边
- `PlanarShadow`：地面有贴地阴影，能随角色移动

---

## 18. 排错决策树（遇到问题按这个查）

### 18.1 “我改参数了，但画面没变化”

1. 先确认材质是否真的挂在目标模型上
2. 再确认是否编辑了正确材质实例（不是另一个）
3. 确认 Inspector 没锁定到别的对象
4. 检查 shader 是否编译失败（Console）

### 18.2 “DepthFade / Distortion 没效果”

1. `DepthFade`：检查 `Depth Texture` 是否开启
2. `ScreenDistortion`：检查 `Opaque Texture` 是否开启
3. Camera 与对象是否在同一个 URP Renderer 下

### 18.3 “透明效果很奇怪”

1. 看 `Blend` 是否符合预期
2. 看 `ZWrite` 是否关闭
3. 看 Queue 是否在 Transparent
4. 透明对象是否大面积重叠

### 18.4 “Outline 抖/穿插”

1. 降低 `_OutlineWidth`
2. 检查模型法线和缩放是否异常
3. 避免非均匀缩放过大

### 18.5 “PlanarShadow 位置不对”

1. 先用默认：`_PlaneNormal=(0,1,0)`、`_PlaneOffset=0`
2. `_UseMainLight=1` 看是否回正
3. 若用手动光线，检查 `_LightDirWS` 是否有长度
4. 调 `_ShadowBias` 抑制抖动

---

## 19. 参数联动思路（避免“乱调一通”）

### 19.1 Dissolve

1. 先调 `_Dissolve`（决定进度）
2. 再调 `_EdgeWidth`（决定边缘厚度）
3. 最后调 `_EdgeColor/_EdgeIntensity`（决定观感）

### 19.2 FresnelTransparent

1. 先定 `_Alpha`（主体透明度）
2. 再调 `_FresnelPower`（边缘范围）
3. 最后调 `_FresnelAlphaBoost`（边缘实度）

### 19.3 Hologram

1. 先设 `_Alpha`
2. 再调 `_ScanDensity/_ScanSpeed`
3. 最后少量调 `_FlickerSpeed`，避免晃眼

### 19.4 PlanarShadow

1. 先把平面定义正确（法线和偏移）
2. 再确定投影方向（主光或手动）
3. 最后调 `Bias/Fade/Color`

---

## 20. 性能入门建议（移动端优先看）

### 20.1 哪些通常更便宜

- `UnlitTexture`
- `AlphaClip`（比复杂透明便宜，但有 overdraw 风险）
- `PlanarShadow`（相比真实阴影很便宜）

### 20.2 哪些通常更贵

- `ScreenDistortion`（屏幕采样）
- `DepthFade`（深度采样）
- 多层透明叠加（overdraw 高）
- 高强度动态 + 大面积覆盖屏幕

### 20.3 通用优化方向

1. 减少同时出现的透明大面片
2. 控制特效屏幕占比
3. 降低不必要的采样次数
4. 合理复用材质，减少状态切换

---

## 21. 术语速查（小白版）

- `Albedo`：物体本色（不含光照）
- `Normal Map`：记录法线扰动的贴图
- `TBN`：切线/副切线/法线组成的坐标基
- `NdotL`：法线与光方向点乘，控制漫反射强弱
- `Fresnel`：边缘视角增强效应
- `Overdraw`：同一屏幕像素被重复绘制多次
- `Clip`：丢弃像素
- `Opaque Texture`：相机已渲染的不透明颜色
- `Depth Texture`：相机深度图

---

## 22. 常用公式抄表（不需要死记）

### 22.1 Lambert

```hlsl
diffuse = albedo * lightColor * saturate(dot(N, L));
```

### 22.2 Fresnel（近似）

```hlsl
f = pow(1 - saturate(dot(N, V)), power);
```

### 22.3 溶解裁剪

```hlsl
clip(noise - threshold);
```

### 22.4 平面投影阴影

```hlsl
t = -(dot(n, p) + d) / dot(n, v);
p_projected = p + v * t;
```

---

## 23. 你可以直接照抄的“第一次交付模板”

目标：做一个“可交付演示”的小场景（10~20 分钟）。

1. 地面：`Plane + LitLambert`
2. 主角：`Toon + Outline`
3. 护盾：`FresnelTransparent`
4. 脚下阴影：`PlanarShadow`
5. 地面能量圈：`UVScroll` 或 `FlowMap`
6. 消失演示：`Dissolve`（挂到第二个模型）

验收要求：

1. 每个效果都能通过一个参数明显变化
2. 场景里没有明显闪烁/错层
3. 你能口头解释每个效果“为什么会这样”

---

## 24. 下一步升级建议（学完这份后）

1. 给每个 shader 做一个对照动图（参数从小到大）
2. 把常用参数做成 `ScriptableObject` 预设库
3. 写一个简单运行时 UI，实时拖参数对比
4. 给 PlanarShadow 加入“只投指定层”的控制

到这一步，你已经不是“只会调参数”，而是能独立做效果的人了。
