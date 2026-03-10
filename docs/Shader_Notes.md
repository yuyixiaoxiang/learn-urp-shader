# Shader Notes

This is the shared shader documentation file for this project.
All future shader notes should be appended here as new sections.

## ShaderLab Attributes: `[MainTexture]` and `[MainColor]`

### What They Mean

`[MainTexture]` and `[MainColor]` are ShaderLab property attributes.
They mark which texture/color property should be treated as the material main
texture/color by Unity editor tooling and material API.

They do not change shading math by themselves.
Final rendering still depends on shader code in `vert/frag`.

### `[MainTexture]`

- Marks a texture property as the material main texture.
- Commonly used with:
- `Material.mainTexture`
- `Material.mainTextureScale`
- `Material.mainTextureOffset`
- Useful when property name is not legacy `_MainTex` (for example `_BaseMap`).

### `[MainColor]`

- Marks a color property as the material main color.
- Commonly used with:
- `Material.color`
- Useful when property name is not legacy `_Color` (for example `_BaseColor`).

### Example

```shaderlab
Properties
{
    [MainTexture] _BaseMap ("Base Map", 2D) = "white" {}
    [MainColor] _BaseColor ("Base Color", Color) = (1,1,1,1)
}
```

### Mapping

- `material.mainTexture` maps to `_BaseMap`.
- `material.color` maps to `_BaseColor`.
- If shader code does not sample/multiply these properties, they will not
  affect final visuals automatically.

## Unity Shader CBUFFER 入门（新手版）

### 1. CBUFFER 是什么

`CBUFFER` 可以理解成 GPU 读取参数的“打包盒子”。
Shader 每次执行时，会从这些盒子里拿数据。

是的，`CBUFFER` 本质上就是 `Constant Buffer`（常量缓冲区）。
这里的“常量”指的是：在一次 draw/dispatch 执行期间，它对该次执行是固定值；
不是指“永远不变”。CPU 仍然可以在下一次 draw 前更新它。

在 Unity 里常见写法是 `CBUFFER_START(...)` / `CBUFFER_END`，这是跨平台宏，
最终会展开为底层图形 API 的常量缓冲区声明。

不同盒子按更新频率分组：

- 材质变了才更新（每材质）
- 物体变了才更新（每物体/每 Draw）
- 相机变了才更新（每相机）
- 每帧都更新（每帧）

这样做的目的：减少无意义数据上传，提高渲染效率。

### 2. 常见 CBUFFER（URP/HDRP 常见命名）

下面是你最常见到的几个名字。不同 Unity/管线版本可能有少量差异。

- `UnityPerMaterial`：每个材质的数据。你最常手写和维护这个。
- `UnityPerDraw`：每个 DrawCall/物体的数据，通常由引擎填充。
- `UnityPerCamera`：每个相机的数据，例如投影相关参数。
- `UnityPerCameraRare`：不常变化的相机数据（引擎内部分类）。
- `UnityPerFrame`：每帧全局数据，例如时间类参数。
- `UnityPerPass`：当前 Pass 相关数据（如阴影/深度等 Pass）。
- `UnityStereoGlobals`：XR 双目相关数据。
- 自定义全局 CBUFFER：你自己定义的全局参数块（跨材质共享）。

实战建议：

- 材质参数优先放 `UnityPerMaterial`（便于 SRP Batcher）。
- 引擎内置块通常只读取，不要手动改写它们的定义。

### 3. `UnityPerMaterial` 里能放什么

可以放数值类型（常量）：

- 标量：`float`、`int`、`uint`（常用 `float`）
- 向量：`float2`、`float3`、`float4`
- 矩阵：`float3x3`、`float4x4`
- 固定长度数组（由以上类型组成）
- 贴图变换参数：如 `_BaseMap_ST`（`float4`，对应 Tiling/Offset）

### 4. `UnityPerMaterial` 里不能放什么

下面这些是“资源对象”，不能放进 CBUFFER：

- `Texture2D`、`Texture3D`、`TextureCube`
- `SamplerState`
- `RWTexture*`、`StructuredBuffer*` 等资源类型

这些要单独声明，例如：

```hlsl
TEXTURE2D(_BaseMap);
SAMPLER(sampler_BaseMap);
```

### 5. `Properties` 和 `UnityPerMaterial` 的关系

新手最关键的一点：`Properties` 里的数值属性，通常要在
`UnityPerMaterial` 中有同名变量，Shader 才能正确拿到材质参数。

示例：

```shaderlab
Properties
{
    _BaseColor ("Base Color", Color) = (1,1,1,1)
    _FlowSpeed ("Flow Speed", Range(0,5)) = 1
    _BaseMap ("Base Map", 2D) = "white" {}
}
```

```hlsl
CBUFFER_START(UnityPerMaterial)
    float4 _BaseColor;   // 对应 Color
    float  _FlowSpeed;   // 对应 Range/Float
    float4 _BaseMap_ST;  // 对应纹理 Tiling/Offset
CBUFFER_END

TEXTURE2D(_BaseMap);     // 纹理本体不进 CBUFFER
SAMPLER(sampler_BaseMap);
```

### 6. 对齐与布局（先记这几条就够用）

CBUFFER 有 16 字节对齐规则。新手先记下面几条，基本不会踩大坑：

- 把参数按 `float4` 思路分组最稳。
- `float3` 通常也会占一个 16 字节槽位（和 `float4` 一样“占格”）。
- 不要指望 `half` 一定能省常量缓冲空间，布局按 `float` 心智模型更安全。
- 同一个 Shader 的不同 Pass，`UnityPerMaterial` 布局要保持一致。

### 7. 新手高频错误清单

- 把纹理写进 `CBUFFER`（错误）。
- `Properties` 写了参数，但 HLSL 没有同名变量（读取不到材质值）。
- `_BaseMap` 写了，但忘记 `_BaseMap_ST`，导致 Tiling/Offset 不生效。
- 不同 Pass 的 `UnityPerMaterial` 定义不一致，影响兼容和批处理。
- 在材质参数里混入大量全局数据，导致职责混乱。

### 8. 一句话记忆版

- `UnityPerMaterial`：放“这个材质自己的数值参数”。
- 纹理和采样器：单独声明，不进 CBUFFER。
- 其他 `UnityPer*`：大多是引擎维护的数据分组，你通常是读取它们。

## Constant Buffer 在 OpenGL / DirectX 中如何分配（进阶）

### 1. 先说结论

- Unity 里的 `CBUFFER_START/END`，在不同后端会映射到对应平台的常量缓冲机制。
- DirectX 对应 Constant Buffer（或 CBV）。
- OpenGL 对应 UBO（Uniform Buffer Object）。
- Vulkan/Metal 也有等价机制（Uniform Buffer / Argument Buffer 常量区域）。

### 2. 在 GPU 中的典型生命周期

可以把它理解成 4 步：

- 第一步：创建缓冲资源（给驱动一个“我要一块常量数据内存”的请求）。
- 第二步：CPU 写入参数（一次性、每帧、或每 Draw 更新）。
- 第三步：把这块缓冲绑定到 shader 槽位（slot/binding point）。
- 第四步：GPU 在执行当前 draw/dispatch 时读取这块数据。

“常量”只表示在当前这次执行期间不变，不表示永远不变。

### 3. OpenGL（UBO）常见流程

- 创建并分配：`glGenBuffers` + `glBindBuffer(GL_UNIFORM_BUFFER)` + `glBufferData/glBufferStorage`
- 绑定到 binding point：`glBindBufferBase` 或 `glBindBufferRange`
- 让 shader 中的 `uniform block` 绑定到同一 binding：`glUniformBlockBinding`
- 常见布局：`std140`（跨平台稳定，规则明确）
- 上限由硬件和驱动决定：运行时查询 `GL_MAX_UNIFORM_BLOCK_SIZE`

说明：

- OpenGL 规范只保证最低能力（例如 UBO block size 最低保证值），实际显卡通常更大。
- 因此不要写死“所有机型都 64KB/128KB”，应运行时查询。

### 4. DirectX 11 常见流程

- 创建 `D3D11_BIND_CONSTANT_BUFFER` 缓冲。
- 高频更新常见 `Map(WRITE_DISCARD)`，中低频更新也可 `UpdateSubresource`。
- 绑定到着色器阶段：`VSSetConstantBuffers`、`PSSetConstantBuffers` 等。
- HLSL 常量寄存器模型里，单个常量缓冲常见上限是 4096 个 `float4`，即 64KB。

### 5. DirectX 12 常见流程

- 创建资源（常见用 Upload Heap 写入动态常量数据）。
- 创建 CBV（Constant Buffer View）描述符。
- 通过 root signature 绑定（root CBV 或 descriptor table）。
- 常见做法是“环形上传缓冲 + 多帧偏移”，避免 CPU/GPU 等待。
- D3D12 常见对齐要求：CBV 偏移按 256 字节对齐。

### 6. 还有哪些“缓冲区”

除了 Constant Buffer，还常见：

- Vertex Buffer：顶点数据
- Index Buffer：索引数据
- Structured Buffer：结构化只读数据
- RW/UAV Buffer：可读写缓冲（计算着色器常用）
- ByteAddress/Raw Buffer：按字节寻址
- Indirect Args Buffer：间接绘制参数
- Readback/Staging Buffer：GPU 到 CPU 回读

## Constant Buffer 大小怎么理解（你问的重点）

### 1. 单个 Constant Buffer 能有多大

要分平台看：

- DirectX 路径里，单个常量缓冲通常按 64KB 上限来设计最安全。
- OpenGL 路径里，看 `GL_MAX_UNIFORM_BLOCK_SIZE`，不要硬编码。
- Unity 是跨平台引擎，建议把单个材质常量块做小，通常几百字节到几 KB 最稳。

### 2. 你图里这个 `UnityPerMaterial` 例子有多大

示例字段：

- `float4 _BaseColor`
- `float4 _BaseMap_ST`
- `float4 _FlowMap_ST`
- `float _FlowStrength`
- `float _FlowSpeed`

按常量缓冲 16 字节打包规则，结果是：

- 前 3 个 `float4` = 48 字节
- 两个 `float` 会落到同一个 16 字节槽内
- 总计 64 字节（逻辑大小）

注意：

- 后端实现可能还会做更大粒度对齐（例如 256 字节对齐），所以真实分配可能大于 64 字节。

### 3. 场景里对象很多时，要分配多少

核心不是“每个对象一份完整 `UnityPerMaterial`”。
更准确是分两块看：

1. 每材质数据（`UnityPerMaterial`）
内存约等于：`唯一材质数 * 单材质常量块对齐后大小`

2. 每 Draw/每对象数据（`UnityPerDraw` 等）
通常由引擎按 Draw 更新并放在动态上传区，不一定长期“一对象一常驻块”。

可以用下面估算：

- `PerMaterialTotal ~= MaterialCount * Align(MaterialCBSize, BackendAlign)`
- `PerFramePerDrawUpload ~= DrawCountPerFrame * PerDrawBytes`
- 多帧并行时（常见 2~3 帧 in flight），动态上传缓冲预算可再乘以 `FramesInFlight`

这里：

- `BackendAlign` 常见至少 16 字节，某些后端/实现常见 256 字节粒度
- `PerDrawBytes` 取决于该 pass 需要的对象数据量（矩阵、光照探针、反射探针等）

### 4. 一个直观例子

假设：

- 你的材质块逻辑大小是 64 字节
- 后端按 256 字节粒度分配
- 场景有 200 个“唯一材质”

那么仅材质常量块大约：

- `200 * 256 = 51200 bytes`，约 50 KB

如果是 20000 个对象但只用这 200 个材质：

- `UnityPerMaterial` 不是按 20000 份算
- 真正会随对象数明显增长的是每帧的 PerDraw 上传量和 draw call 数

### 5. 面对“大量可绘制对象”的优化方向

- 减少“唯一材质数”（共享材质、少造变体）
- 使用 GPU Instancing（同材质多实例）
- 使用 SRP Batcher 友好写法（材质参数集中在 `UnityPerMaterial`）
- 谨慎使用 `MaterialPropertyBlock`（会改变每对象参数上传模式）
- 减少不必要的 per-object 特性（探针、额外 pass、重度变体）

## 快速结论（FAQ 速查）

### Q1. 单个 Constant Buffer 多大

- DirectX 路径通常按单个 CB 64KB 上限设计最稳。
- OpenGL 路径应运行时查询 `GL_MAX_UNIFORM_BLOCK_SIZE`。
- Unity 跨平台项目里，`UnityPerMaterial` 建议保持在几百字节到几 KB。

### Q2. 示例材质块大小（3 个 `float4` + 2 个 `float`）

- 按 16 字节打包规则，逻辑大小是 64 bytes。
- 实际占用可能因后端对齐（例如 256 字节粒度）而更大。

### Q3. 对象很多时，是否每个对象都要一份 `UnityPerMaterial`

- 不是。
- `UnityPerMaterial` 主要按“唯一材质数”增长，不按对象数线性增长。
- 对象数主要影响每帧 `UnityPerDraw` 上传量与 draw call 数。

### Q4. 快速估算公式

- `PerMaterialTotal ~= MaterialCount * Align(MaterialCBSize, BackendAlign)`
- `PerFramePerDrawUpload ~= DrawCountPerFrame * PerDrawBytes * FramesInFlight`

### Q5. 你当前工程里 `UnityPerDraw` 在哪里

- `E:/UrpShader/Library/PackageCache/com.unity.render-pipelines.universal@66e99ffa09c7/ShaderLibrary/UnityInput.hlsl`
- 在该文件可看到 `CBUFFER_START(UnityPerDraw)` 的实际定义。

## Unity 内置时间变量：`_Time`（FlowMap 常用）

### 1. `_Time` 是什么

`_Time` 是 Unity 提供的全局时间变量，类型是 `float4`。
可以直接在 shader 中使用，不需要你自己在 `Properties` 里声明。

在你当前 URP 包中定义为：

- `float4 _Time; // (t/20, t, t*2, t*3)`

其中 `t` 是运行时间（秒）。

### 2. 四个分量分别表示什么

- `_Time.x = t / 20`
- `_Time.y = t`
- `_Time.z = t * 2`
- `_Time.w = t * 3`

常用约定：

- 需要“普通速度”动画时优先用 `_Time.y`
- 需要更快频率可用 `_Time.z` 或 `_Time.w`
- 需要更慢频率可用 `_Time.x`

### 3. 在 FlowMap 中的实际意义

典型代码：

```hlsl
float phase0 = frac(_Time.y * _FlowSpeed);
```

解释：

- `_Time.y * _FlowSpeed`：让相位随时间线性增长，`_FlowSpeed` 控制增速
- `frac(...)`：只保留小数部分，得到 `[0,1)` 循环相位
- 相位循环后用于 `uv + flow * phase`，形成连续流动动画

### 4. 相关时间变量

除了 `_Time`，Unity 还提供：

- `_SinTime`：`sin(t/8), sin(t/4), sin(t/2), sin(t)`
- `_CosTime`：`cos(t/8), cos(t/4), cos(t/2), cos(t)`
- `_TimeParameters`：`t, sin(t), cos(t)`
- `_LastTimeParameters`：上一帧的 `t, sin(t), cos(t)`

这些变量通常用于脉冲、呼吸、摆动、波浪等周期动画。

## 通俗理解：什么是菲涅尔现象（Fresnel）

### 1. 一句话解释

看东西时，视线越“擦着表面边缘”看，反光通常越明显，这就是菲涅尔现象。

### 2. 生活里的例子

- 看平静水面：正上方看进去更容易看到水下；斜着看更像一面镜子。
- 看玻璃杯边缘：边缘位置更亮、更容易看到反光。

### 3. 在 Shader 里常怎么用

- 做“边缘高亮”或“轮廓发光”
- 控制反射强度（正面弱、掠射角强）
- 常见于水、玻璃、能量护盾、卡通描边高光

常见近似写法（思路）：

```hlsl
float fresnel = pow(1.0 - saturate(dot(N, V)), _FresnelPower);
```

解释：

- `N` 是法线，`V` 是视线方向
- `dot(N,V)` 越小表示越接近边缘角度
- `1-dot` 越大，菲涅尔项越强
- `pow` 用来调曲线陡峭程度（边缘“硬/软”）

### 4. 新手常见误解

- 菲涅尔不是“固定的一圈描边贴图”，而是和观察角度相关的反射变化。
- 它通常用于“增强真实感”，不是单纯的特效开关。

## 通俗理解：什么是丁达尔现象（Tyndall）

### 1. 一句话解释

光在含有微小颗粒的介质中传播时，会被散射出来，于是你能“看到光路”，这就是丁达尔现象。

### 2. 生活里的例子

- 阳光照进有灰尘的房间，会看到一束束“光柱”。
- 雾天车灯会形成明显的光束。
- 手电筒照浑浊水体，会看到光在水里“发亮”。

### 3. 在图形/Shader 里对应什么

- 常见表现是体积光、光柱、雾中可见光路（God Rays / Volumetric Lighting）
- 本质是“介质散射”效果，不是表面反射
- 实现上常结合深度、体积雾、光源方向和散射相函数近似

### 4. 和菲涅尔的区别（最关键）

- 菲涅尔：发生在“表面”，重点是观察角度导致的反射变化。
- 丁达尔：发生在“介质内部”（雾、烟、尘、水体），重点是光被颗粒散射而可见。

### 5. 新手常见误解

- 看到“亮边”不一定是丁达尔，很多时候那是菲涅尔或描边。
- 丁达尔效果通常需要介质参与；没有雾尘等介质，光路一般不可见。

## URP 中的 Pass（通俗版）

### 1. 先用一句话区分两个常见 Pass

- `ShadowCaster`：给“灯光”看的，决定物体怎么写入阴影贴图（Shadow Map）。
- `DepthOnly`：给“相机”看的，决定物体怎么写入相机深度纹理（Camera Depth Texture）。

可以把它们理解成两张不同用途的“轮廓图”：

- 阴影轮廓图：供光照计算“哪里该暗”。
- 深度轮廓图：供后处理/屏幕特效判断“哪里近哪里远”。

### 2. 这两个 Pass 在渲染流程里什么时候执行

- 渲染阴影贴图阶段，会查找 `LightMode = "ShadowCaster"` 的 Pass。
- 生成相机深度纹理阶段，会查找 `LightMode = "DepthOnly"` 的 Pass。
- 最后主画面颜色阶段才是 `UniversalForward`（或其他颜色 Pass）。

所以它们不是“重复绘制颜色”，而是提前写“辅助数据”。

### 3. `ShadowCaster` Pass 原理（独立）

典型关键点：

- `Tags { "LightMode"="ShadowCaster" }`
- `ZWrite On`
- `ZTest LEqual`
- `ColorMask 0`

#### 3.1 为什么 `ColorMask 0`

- 阴影贴图核心是“深度关系”，不是颜色。
- 所以这个 Pass 不需要写入 RGB/A，直接关闭颜色写入更高效。

#### 3.2 顶点阶段在做什么

典型逻辑：

- 物体空间顶点、法线 -> 世界空间。
- 根据光源类型算光方向：
- 平行光：直接用 `_LightDirection`。
- 点光/聚光：用 `normalize(_LightPosition - positionWS)`。
- 应用 `ApplyShadowBias`，减少阴影痤疮（Shadow Acne）。
- 把结果变换到光源裁剪空间（用于写阴影图深度）。

通俗讲：把模型“从光的视角重新投影”一遍。

#### 3.3 片元阶段在做什么

- 若是实体不透明：通常直接写深度即可。
- 若是 Cutout / Dither：先做 `clip`（按 alpha 或抖动阈值裁剪），通过的像素才写阴影深度。

结果：阴影轮廓会和可见轮廓保持一致，避免“画面镂空但阴影整块”的穿帮。

#### 3.4 这个 Pass 解决了什么问题

如果没有 `ShadowCaster`（或裁剪规则与主 Pass 不一致），常见现象是：

- 画面看着已经半透明/镂空了；
- 但阴影还是实体整块，违和感很强。

### 4. `DepthOnly` Pass 原理（独立）

典型关键点：

- `Tags { "LightMode"="DepthOnly" }`
- `ZWrite On`
- `ColorMask R`

#### 4.1 为什么叫 DepthOnly

- 它的目标是写“深度信息”，不是颜色信息。
- 管线后续很多效果会读取这张深度图（例如雾、景深、软粒子、部分屏幕空间特效）。

#### 4.2 顶点阶段在做什么

典型逻辑：

- 顶点从物体空间变换到相机裁剪空间 `TransformObjectToHClip`。
- 如需 alpha/cutout 判断，会把 UV 传到片元阶段。

通俗讲：把模型“从相机视角投影”一遍，准备写深度。

#### 4.3 片元阶段在做什么

- 若是实体不透明：直接写深度。
- 若是 Cutout / Dither：先执行 `clip`，再写深度值（常见为 `positionCS.z`）。

这意味着：

- 被裁掉的像素不会占深度。
- 保留像素才会占深度。

#### 4.4 这个 Pass 解决了什么问题

如果没有 `DepthOnly`（或裁剪规则不一致），常见穿帮是：

- 视觉上物体已经“透明很多”；
- 但深度图里它仍像整块实心，导致雾/景深/软粒子等效果错误遮挡。

### 5. 后续渲染如何依赖 Shadow Map 计算阴影（调用链）

下面按“先写入 -> 再采样 -> 再参与光照”解释：

#### 5.1 先写入 Shadow Map（ShadowCaster 阶段）

- `ShadowCaster` Pass 把从光源视角看到的深度写进阴影图。
- 主光阴影纹理会绑定到 `_MainLightShadowmapTexture`。
- 额外光阴影纹理会绑定到 `_AdditionalLightsShadowmapTexture`。

这一步只是在“存参考深度”，还没开始给主画面打阴影。

#### 5.2 CPU 设置阴影接收所需全局参数

阴影图写完后，URP 会把后续采样需要的参数推到全局常量：

- 主光 world->shadow 矩阵：`_MainLightWorldToShadow`
- 主光阴影参数：`_MainLightShadowParams`
- 级联分割球参数（级联阴影时）
- 软阴影采样偏移和阴影图尺寸参数

额外光也会设置对应的矩阵数组/结构化缓冲和参数数组。

通俗讲：CPU 告诉 shader“去哪里采样、怎么采样、采样要不要做软化”。

#### 5.3 主渲染阶段先算当前像素的 `shadowCoord`

在 `LitForwardPass` / `LitGBufferPass` 中，URP 会对每个像素（或插值后像素）计算：

- `inputData.shadowCoord = TransformWorldToShadowCoord(inputData.positionWS);`

如果是主光级联阴影，会先根据像素世界坐标决定属于哪个 cascade，再用对应矩阵变换。

#### 5.4 用 `shadowCoord` 采样 Shadow Map 并做深度比较

主光路径大致是：

- `GetMainLight(...)`
- `MainLightShadow(...)` 或 `MainLightRealtimeShadow(...)`
- `SampleShadowmap(...)`

`SampleShadowmap` 里会：

- 做透视除法（需要时）
- 用比较采样器读取 shadow map
- 若开启软阴影，走 PCF 过滤（低/中/高质量）
- 输出 `attenuation`（阴影衰减，0~1）

语义上：

- `1.0` 约等于“受光”
- `0.0` 约等于“在阴影里”
- 中间值对应软阴影过渡

#### 5.5 实时阴影会和烘焙阴影/距离淡出做混合

主光常见会走：

- 实时阴影 `realtimeShadow`
- 烘焙 shadowmask `bakedShadow`（如果启用）
- 距离淡出 `shadowFade`

最终通过 `MixRealtimeAndBakedShadows(...)` 得到阴影因子。

#### 5.6 最终如何影响光照

计算 BRDF 时，URP 会把阴影因子乘到直射光能量里：

- `light.distanceAttenuation * light.shadowAttenuation`

所以阴影本质上是“把该光源对该像素的直射贡献按比例压暗”。

一句话公式可记为：

- `FinalDirect = BRDF * LightColor * DistanceAtten * ShadowAtten`

## URP DitherTransparent：Pass 落地与对齐

本文对应文件：

- `Assets/URPCommon/URP_DitherTransparent/URP_DitherTransparent.shader`

### 1. 为什么此 Shader 要同时写 `ShadowCaster` 与 `DepthOnly`

`DitherTransparent` 是屏幕门透明（Dither + Clip）方案，视觉上会“打孔”。
为了避免阴影与深度和主画面不一致，需要在三个路径都用同一套裁剪规则：

- `UniversalForward`（颜色）
- `ShadowCaster`（阴影）
- `DepthOnly`（深度）

### 2. 关键实现：复用同一个 `ApplyDitherClip`

当前做法是：

- `Forward`、`ShadowCaster`、`DepthOnly` 都调用同一个 `ApplyDitherClip(...)`。

好处是三种结果保持一致：

- 眼睛看到的形状（颜色）
- 灯光看到的形状（阴影）
- 相机深度看到的形状（深度）

一致性越高，越不容易出现“画面一个样，阴影/后处理另一个样”的断裂感。

### 3. 常见现象与调参建议（针对 Dither）

- `_Alpha` 降低：可见像素变少，透明感增强。
- `_DitherScale` 提高：点阵更细密，颗粒感更细但可能更“闪”。
- 运动时出现颗粒闪烁：这是屏幕门透明的典型特征，可用 TAA/后处理缓解。

### 4. 快速排查清单

- 阴影不对：先看是否命中了 `ShadowCaster` Pass。
- 后处理遮挡不对：看相机是否启用深度纹理，是否命中了 `DepthOnly` Pass。
- 形状不一致：检查三个 Pass 是否都调用同一个 `ApplyDitherClip`。
