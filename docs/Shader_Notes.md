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
