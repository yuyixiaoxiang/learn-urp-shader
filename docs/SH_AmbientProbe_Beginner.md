# SH 与 Ambient Probe 入门（小白版）

这份文档专门解释你问的这段代码：

```hlsl
real3 SampleSH(real3 normalWS)
{
    return EvaluateAmbientProbeSRGB(normalWS);
}
```

目标是让你从 0 到 1 理解：

- SH 是什么
- 为什么 Unity/URP 用 SH 做环境光
- `AmbientProbe.hlsl` 这条调用链到底在做什么
- 你调试时该看哪些参数

---

## 1. 一句话先建立直觉

- `SampleSH(normalWS)`：根据“当前像素法线朝向”，从环境探针里取一份环境漫反射光。
- 法线朝天，通常更亮偏蓝（天空）。
- 法线朝地，通常更暗偏暖（地面反照）。

它不是主光直射，也不是阴影贴图；它是“环境底光”。

---

## 2. SH（球谐）到底是什么

### 2.1 先不看公式，先看用途

在渲染里，我们常要回答这个问题：

- 某个方向 `d` 上，环境光有多亮、是什么颜色？

这个“方向 -> 颜色”的函数，直接存很贵（需要很多采样点）。
SH 的思路是：用一组固定基函数去近似它，只存少量系数。

你可以把它理解成：

- 图像 JPEG 用频率压缩
- 球面光照用 SH 压缩

### 2.2 为什么它适合漫反射环境光

漫反射环境光属于“低频信号”（变化比较平滑），不需要太高细节。
所以只用低阶 SH（常见 L2）就够用了，速度快、内存小。

---

## 3. L0/L1/L2 是什么（最常见概念）

Unity 里最常见是 SH9（到二阶 L2）：

- L0：1 个基函数（全局平均亮度）
- L1：3 个基函数（大方向梯度）
- L2：5 个基函数（二阶变化细节）

总计：`1 + 3 + 5 = 9`（每个颜色通道 9 个系数）。

RGB 三通道就是 27 个数（Unity 会做打包，不让你直接手填 27 个 float）。

直觉上：

- 只用 L0：世界四面八方一样亮（很“糊”）
- 加上 L1：能区分“上亮下暗”
- 加上 L2：光照方向细节更自然

---

## 4. Unity 在 `AmbientProbe.hlsl` 里怎么实现

文件：`Packages/com.unity.render-pipelines.core/ShaderLibrary/AmbientProbe.hlsl`

### 4.1 关键函数关系

```hlsl
SampleSH -> EvaluateAmbientProbeSRGB -> EvaluateAmbientProbe -> SHEvalLinearL0L1 + SHEvalLinearL2
```

含义：

1. `EvaluateAmbientProbe`：先算线性空间环境光。
2. `EvaluateAmbientProbeSRGB`：如果项目是 Gamma 颜色空间，再转 sRGB。
3. `SampleSH`：只是个便捷包装名，外部直接调用它。

### 4.2 为什么有 `SRGB` 版本

因为项目可能是两种颜色空间：

- Linear（推荐）
- Gamma（老项目常见）

在 Gamma 项目里，代码会做 `LinearToSRGB(res)`，保证显示结果正确。

---

## 5. 你这段代码逐行解释

```hlsl
real3 SampleSH(real3 normalWS)
{
    return EvaluateAmbientProbeSRGB(normalWS);
}
```

### 5.1 `normalWS`

- 世界空间法线方向（World Space Normal）。
- 必须尽量归一化（单位长度）。
- 如果法线没归一化，SH 结果会偏亮或方向错乱。

### 5.2 `EvaluateAmbientProbeSRGB(normalWS)`

- 输入法线方向。
- 输出该方向对应的环境漫反射光颜色（`real3`）。
- 这个颜色就是“baked GI / ambient”里常见的一部分。

---

## 6. SH 与其他光照项的关系（避免混淆）

很多新手会把这些混在一起：

1. 主光直射（Directional/Point/Spot）
2. 阴影（ShadowMap 比较后得到遮挡）
3. 反射探针（specular 反射）
4. SH 环境光（diffuse 低频）

`SampleSH` 属于第 4 类：环境漫反射底光。

它通常与阴影不是一回事，也不直接替代主光。

---

## 7. 为什么 Unity 注释说“预卷积 with clamped cosine”

`AmbientProbe.hlsl` 里有一句关键注释：Ambient Probe 已经做了和 clamped cosine 的预卷积。

通俗说：

- 这份 SH 数据已经被处理成“更适合漫反射”的形式。
- 所以拿来就可以当 diffuse irradiance 用。
- 它不是原始 HDR 天空辐射值（不是直接给镜面高光用的）。

---

## 8. 小白最常见误区

### 误区 1：把 SH 当成阴影

不是。阴影来自 Shadow Map，SH 是环境光底色。

### 误区 2：法线空间用错

`SampleSH` 需要 `normalWS`（世界空间）。
把切线空间法线直接塞进去会错。

### 误区 3：觉得 SH 能表达锐利细节

SH（尤其 L2）是低频近似，不擅长硬边高频光照。

### 误区 4：Gamma/Linear 不分

看到 `EvaluateAmbientProbeSRGB` 以为“重复 gamma”。
实际上它是按工程颜色空间分支处理，不是盲目重复转换。

---

## 9. 在 URP 里的典型使用位置

`URP` 的 `GlobalIllumination.hlsl` 会 include `AmbientProbe.hlsl`，并在对应路径调用：

- `SampleSHVertex`
- `SampleSHPixel`
- `EvaluateAmbientProbeSRGB`

这就是你在 Lit/SimpleLit 里看到“物体在阴影区也不全黑”的重要来源之一。

---

## 10. 你可以立刻做的 3 个实验（最快建立直觉）

### 实验 A：转动物体看底光变化

1. 场景保留天空盒。
2. 关闭主光或把主光调很弱。
3. 旋转球体，观察朝上/朝下部分颜色变化。

你看到的变化主要就是 SH 环境光。

### 实验 B：切换天空盒

1. 用偏蓝天空盒。
2. 再换成暖色/黄昏天空盒。

物体整体环境色会跟着变，这就是探针对环境的采样变化。

### 实验 C：检查法线是否归一化

在自定义 shader 中故意不归一化 `normalWS`，再对比归一化版本。
你会看到环境光强度或方向感不稳定。

---

## 11. 一页速记（记住这些就够用了）

1. `SampleSH(normalWS)` = 取“该法线方向”的环境漫反射光。  
2. SH9 = L0(1) + L1(3) + L2(5)，低成本近似环境光。  
3. `AmbientProbe` 数据是给 diffuse 用的（低频、平滑）。  
4. 它不是阴影，不是高光反射。  
5. 法线必须是世界空间并归一化。  

---

## 12. 数学原理（通俗版，不怕公式）

这部分给你“能看懂、用得上”的数学直觉，不走纯理论路线。

### 12.1 SH 的本质是“函数展开”

我们想表示一个方向函数：

- `f(w)`：某个方向 `w` 上的环境光颜色强度

SH 说：我用一组固定模板函数 `Y_i(w)` 去拼它：

```text
f(w) ≈ c0*Y0(w) + c1*Y1(w) + ... + cN*YN(w)
```

你可以把这理解成“乐高拼图”：

- `Y_i` 是固定积木形状（基函数）
- `c_i` 是每块积木要放多少（系数）

### 12.2 系数 `c_i` 怎么来

每个系数是投影积分（可以理解成“相关性打分”）：

```text
c_i = ∫ f(w) * Y_i(w) dw
```

含义：

- 如果 `f` 和某个 `Y_i` 很像，`c_i` 就大。
- 不像，`c_i` 就小。

### 12.3 为什么只取到 L2（SH9）就够

数学上，阶数越高，表达的“频率细节”越高。

- 低阶：平滑大轮廓
- 高阶：尖锐高频细节

漫反射环境光本身偏平滑，所以通常只保留到 L2：

- 好处：非常快
- 代价：细节会被“软化”

这就是你经常听到的“SH 是低通近似”。

### 12.4 正交性的意义（为什么计算简单）

SH 基函数之间是正交的（可类比“互不串音”）。
所以每个系数可以独立计算，互不干扰。

这就是 SH 能稳定做“压缩 + 重建”的核心原因。

---

## 13. 漫反射为什么和 SH 天然搭配

### 13.1 漫反射真实公式长什么样

像素法线为 `n` 时，漫反射环境光本质是这个积分：

```text
E(n) = ∫ L(w) * max(0, n·w) dw
```

其中：

- `L(w)`：环境 radiance（某方向来的光）
- `max(0, n·w)`：Lambert 余弦项（背面不贡献）

### 13.2 这其实是一个“卷积”

上式可看成：

- 环境光 `L`
- 和一个核函数 `max(0, n·w)`（clamped cosine）

做球面卷积。

### 13.3 SH 域里卷积更便宜

卷积到 SH 域会变成“每个频带乘一个常数”的操作。
这就是为什么 Unity 注释里说 Ambient Probe 已经做了 clamped cosine 预卷积：

- 运行时不再做昂贵积分
- 只要把法线代入多项式就出结果

所以你才看到 shader 里只是 `SHEvalLinearL0L1 + SHEvalLinearL2` 这种轻量计算。

---

## 14. 把 Unity 代码和数学一一对上

对应文件：`SphericalHarmonics.hlsl` 与 `AmbientProbe.hlsl`

### 14.1 `SHEvalLinearL0L1(...)`

它在算低阶项（常量 + 一阶）：

- 常量项决定整体平均亮度（L0）
- 一阶项决定“上亮下暗、左亮右暗”这类大方向变化（L1）

### 14.2 `SHEvalLinearL2(...)`

它在补二阶细节（L2）：

- 让光照分布不是只有大梯度，而是更贴近真实环境形状

### 14.3 `EvaluateAmbientProbeSRGB(...)`

它负责：

1. 先在**线性空间**评估 SH。
2. 若项目是 Gamma，再转到 sRGB 显示空间。

这不是“重复 gamma”，而是正确的颜色流程。

---

## 15. 一个极简“脑内演示”

假设只有 L0（其他全 0）：

- 球体任何朝向得到的环境光都一样
- 看起来像“均匀灰雾打光”

再加 L1（比如“上方更亮”）：

- 球顶更亮，球底更暗
- 开始有天空/地面方向感

再加 L2：

- 明暗过渡更自然
- 局部方向变化更细腻，但仍然是平滑的

这就是“SH9 够用”的实际视觉原因。

---

## 16. 为什么 SH 看起来会“偏糊”

因为你只保留到 L2，本质上是频率截断：

- 高频被砍掉
- 结果一定更平滑

优点是稳定、便宜、抗噪声。
缺点是无法表达锐利阴影边界或高频镜面细节。

这不是 bug，是设计目标。

---

## 17. 小白调试流程（实战）

当你觉得“环境光怪怪的”时，按这个顺序查：

1. `normalWS` 是否归一化。  
2. `normalWS` 是否真的是世界空间。  
3. 项目颜色空间是 Linear 还是 Gamma。  
4. 是否误把 SH 当作阴影项调了。  
5. 场景天空盒/环境光设置是否异常。  
6. 是否期望 SH 去表达高频效果（这本身不适合）。  

---

## 18. 给小白的最终记忆法

把 SH 当成一句话就行：

- “用少量系数压缩环境光方向分布，并在像素上按法线快速还原漫反射底光。”

把 Ambient Probe 当成一句话就行：

- “Unity 已经帮你准备好的、可直接用于漫反射的 SH 环境光数据。”

---

## 19. 系数到底怎么得到（从环境图到 SH 系数）

你在 shader 里看到的是“使用系数”。
但系数本身不是 shader 即时算出来的，通常是离线/预处理得到。

### 19.1 原始输入是什么

- 一张环境图（例如 skybox/cubemap）
- 对每个方向 `w`，你能查到该方向入射光 `L(w)`（RGB）

### 19.2 投影到 SH 的本质步骤

对每个 SH 基函数 `Y_i`，都做一次“相关性积分”：

```text
c_i = ∫ L(w) * Y_i(w) dw
```

离散实现（实际工程常这么做）：

```text
c_i ≈ Σ [L(w_k) * Y_i(w_k) * ΔΩ_k]
```

其中：

- `w_k`：第 k 个采样方向
- `ΔΩ_k`：该采样方向对应的立体角权重（非常重要）

### 19.3 为什么要乘立体角 `ΔΩ`

因为球面采样不是平面像素面积，方向覆盖“面积”不均匀。
不乘权重会偏色/偏亮，尤其在 cubemap 边角更明显。

---

## 20. 漫反射预卷积为什么能“提前做”

前面说过漫反射积分：

```text
E(n) = ∫ L(w) * max(0, n·w) dw
```

这是“环境光 L”和“余弦核 max(0, n·w)”的球面卷积。

### 20.1 SH 域里的好处

在 SH 域里，卷积会变成“每个频带乘一个常数”。
对 L0/L1/L2 三个频带分别乘固定因子即可。

在 Unity 代码里你能看到对应常量（`SphericalHarmonics.hlsl`）：

- `kClampedCosine0 = 1.0`
- `kClampedCosine1 = 2.0/3.0`
- `kClampedCosine2 = 1.0/4.0`

这就是“预卷积 with clamped cosine”的工程含义：

1. 先把环境数据按这些频带规则处理好。
2. 运行时就不用再做昂贵积分了。

---

## 21. Unity 运行时到底算了什么（逐步拆）

对应函数：`SHEvalLinearL0L1` + `SHEvalLinearL2`

### 21.1 低阶部分（L0 + L1）

代码形态（简化）：

```hlsl
vA = float4(N.x, N.y, N.z, 1)
resLow.r = dot(shAr, vA)
resLow.g = dot(shAg, vA)
resLow.b = dot(shAb, vA)
```

直觉：

- `1` 对应常量项（L0）
- `N.x/N.y/N.z` 对应一阶方向项（L1）

### 21.2 二阶部分（L2）

代码形态（简化）：

```hlsl
vB = (N.x*N.y, N.y*N.z, N.z*N.z, N.z*N.x)
resMid = dot(shB*, vB)
vC = N.x*N.x - N.y*N.y
resHigh = shC.rgb * vC
res = resLow + resMid + resHigh
```

直觉：

- 这些是二阶多项式基
- 用来补充更细一点的方向变化（但仍属于低频）

### 21.3 为什么计算这么快

本质是几次 dot + 乘加（MAD），没有循环采样环境贴图。
这就是 SH 适合移动端/大场景的重要原因。

---

## 22. Unity 系数打包（为什么变量名这么怪）

你会看到这些变量：

- `unity_SHAr / unity_SHAg / unity_SHAb`
- `unity_SHBr / unity_SHBg / unity_SHBb`
- `unity_SHC`

这是 Unity 为了高效 dot 计算做的打包布局，不是随机命名。

在 `SphericalHarmonics.hlsl` 里 `PackSH(...)` 可以看到打包逻辑：

- 前 3 个 `float4` 对应每个颜色通道的常量+一阶项（A 组）
- 再 3 个 `float4` 对应二阶中的 4 项（B 组）
- 最后 1 个 `float4` 对应二阶最后 1 项（C 组，rgb 有效）

你不需要死记每个分量映射，只要记住：

- A 组给 `SHEvalLinearL0L1`
- B/C 组给 `SHEvalLinearL2`

---

## 23. 一个带数字的小例子（只看趋势）

为了易懂，先假设只启用 L0+L1（忽略 L2）：

```text
E(n) ≈ c0 + c1*n.x + c2*n.y + c3*n.z
```

假设某通道系数是：

- `c0 = 0.30`（基础环境亮度）
- `c2 = 0.20`（“向上更亮”）
- 其余为 0

则：

- 法线朝上 `n=(0,1,0)`：`E = 0.30 + 0.20 = 0.50`
- 法线朝下 `n=(0,-1,0)`：`E = 0.30 - 0.20 = 0.10`
- 法线水平 `n=(1,0,0)`：`E = 0.30`

这就是你看到“球体上亮下暗”的最基础数学来源。

---

## 24. 为什么有时会出现负值/偏灰

SH 是“截断展开”，不是完美重建。
在某些方向可能出现轻微负值（数学上允许，物理上不合理）。

工程里常见处理：

1. 在某些路径做 `max(0, res)`。  
2. 或在后续能量控制里间接压制异常。  
3. 通过更稳定探针数据和颜色空间流程减少问题。  

URP 的某些路径（例如 `SampleSHPixel` 的 mixed 分支）能看到 `max(half3(0,0,0), res)` 处理。

---

## 25. SH、Light Probe、APV 的关系（容易混）

### 25.1 SH 是“表示方式”

- 一组系数 + 一套基函数
- 用来表示低频方向光照

### 25.2 Light Probe / Ambient Probe 是“数据来源”

- 这些系统提供 SH 系数数据
- shader 负责按法线求值

### 25.3 APV（Adaptive Probe Volume）是“更高级的采样系统”

- 仍然会产出可用于漫反射 GI 的结果
- 只是空间采样、插值、管理方式更高级

所以“SH”和“Probe”不是替代关系，而是“表示方式”和“数据系统”的关系。

---

## 26. 小白进阶：如何判断该不该用 SH

适合 SH 的情况：

1. 你需要环境漫反射底光。  
2. 你追求稳定、低成本。  
3. 你不需要表现锐利高频方向细节。  

不该指望 SH 做到的事：

1. 锐利阴影边界。  
2. 高光反射细节（这该交给反射探针/IBL specular）。  
3. 高对比度细小光斑的精确重建。  

---

## 27. 最终总结（数学 + 工程）

数学上：

- SH 是把球面函数投影到正交基，再截断到低阶的近似方法。

工程上：

- Unity 预先准备好 Ambient Probe 的 SH 数据（含漫反射卷积语义）。
- shader 运行时只做低阶多项式求值，按法线输出环境底光。

你可以把它当作：

- “把复杂环境光积分，折叠成几次 dot 运算。”

---

## 28. `unity_SHAr / unity_SHBr / unity_SHC` 映射表（最实用）

这一节是你写自定义 shader 时最有用的“对照表”。

先记法线：

- `N = (Nx, Ny, Nz)`，且应归一化。

### 28.1 L0 + L1（`SHEvalLinearL0L1`）

URP/Unity 代码等价于：

```text
R_low = unity_SHAr.x * Nx + unity_SHAr.y * Ny + unity_SHAr.z * Nz + unity_SHAr.w
G_low = unity_SHAg.x * Nx + unity_SHAg.y * Ny + unity_SHAg.z * Nz + unity_SHAg.w
B_low = unity_SHAb.x * Nx + unity_SHAb.y * Ny + unity_SHAb.z * Nz + unity_SHAb.w
```

你可以把它理解成：

- `x/y/z` 分量：方向梯度（L1）
- `w` 分量：基础常量亮度（带打包修正）

### 28.2 L2（`SHEvalLinearL2`）

先定义中间项：

```text
t0 = Nx * Ny
t1 = Ny * Nz
t2 = Nz * Nz
t3 = Nz * Nx
t4 = Nx * Nx - Ny * Ny
```

则：

```text
R_l2 = unity_SHBr.x * t0 + unity_SHBr.y * t1 + unity_SHBr.z * t2 + unity_SHBr.w * t3 + unity_SHC.r * t4
G_l2 = unity_SHBg.x * t0 + unity_SHBg.y * t1 + unity_SHBg.z * t2 + unity_SHBg.w * t3 + unity_SHC.g * t4
B_l2 = unity_SHBb.x * t0 + unity_SHBb.y * t1 + unity_SHBb.z * t2 + unity_SHBb.w * t3 + unity_SHC.b * t4
```

最终结果：

```text
R = R_low + R_l2
G = G_low + G_l2
B = B_low + B_l2
```

如果是 Gamma 颜色空间路径，还会再做 Linear -> sRGB。

### 28.3 一句话记忆

- `A` 组：常量 + 一阶（低频大方向）
- `B/C` 组：二阶细节（稍细但仍低频）

---

## 29. 从法线到颜色：手算一遍（完整 mini 示例）

这里只为了建立直觉，不追求真实场景数值。

假设某像素法线：

```text
N = (0, 1, 0)   // 朝上
```

并且（只举 R 通道）：

```text
unity_SHAr = (0.00, 0.20, 0.00, 0.30)
unity_SHBr = (0.00, 0.00, 0.02, 0.00)
unity_SHC.r = 0.01
```

### 29.1 算低阶项

```text
R_low = 0*0 + 0.20*1 + 0*0 + 0.30 = 0.50
```

### 29.2 算二阶项

`N=(0,1,0)` 时：

```text
t0=0*1=0
t1=1*0=0
t2=0*0=0
t3=0*0=0
t4=0*0 - 1*1 = -1
```

所以：

```text
R_l2 = 0 + 0 + 0.02*0 + 0 + 0.01*(-1) = -0.01
```

### 29.3 合成

```text
R = R_low + R_l2 = 0.50 - 0.01 = 0.49
```

这说明：

- L0/L1 决定大方向亮度
- L2 只做较细微修正

---

## 30. 为什么法线“差一点”结果会差很多

SH 求值本质就是一堆 `N` 的线性/二次项。
如果 `N` 错了，所有项都连带错。

### 30.1 新手最常见三类错法

1. 用了切线空间法线当世界空间法线。  
2. 忘了 normalize。  
3. 法线贴图混合后未正确变换到世界空间。  

### 30.2 快速自检

1. 临时把 `normalWS` 可视化输出为颜色。  
2. 旋转模型看颜色是否稳定跟随世界方向。  
3. 关闭 normal map 对比，确认异常是否来自法线链路。  

---

## 31. 你写自定义函数时的推荐模板

如果你希望最贴近 URP 默认行为，建议直接走：

```hlsl
real3 gi = SampleSH(normalWS);
```

如果你要自己拆分（例如做实验）：

```hlsl
real3 gi = SHEvalLinearL0L1(normalWS, unity_SHAr, unity_SHAg, unity_SHAb);
gi += SHEvalLinearL2(normalWS, unity_SHBr, unity_SHBg, unity_SHBb, unity_SHC);
#ifdef UNITY_COLORSPACE_GAMMA
gi = LinearToSRGB(gi);
#endif
```

这样你就能精确控制：

1. 是否仅看 L0/L1（注释掉 L2）。  
2. 是否做 clamp。  
3. 是否对比 Gamma/Linear 差异。  

---

## 32. 常见问答（小白高频）

### Q1：SH 和 Lightmap 是二选一吗？

不是。很多情况下会按管线路径混合或择优使用，SH 常作为无 lightmap 或补充环境项。

### Q2：为什么我关了主光还有亮度？

很可能就是 SH/环境光在起作用（还有可能是 emissive/后处理）。

### Q3：SH 能不能做“硬阴影”？

不能。SH 是低频环境光近似，不是阴影边界求解器。

### Q4：为什么看起来有点“灰”？

低阶近似天生更平滑，且环境项本来就是全局底光，主对比来自直射和阴影。

---

## 33. 下一步学习建议（按难度）

1. 先完全理解本文件第 28 节映射表。  
2. 在一个球体上做 L0/L1/L2 开关实验。  
3. 再看 Unity `SphericalHarmonics.hlsl` 的 `PackSH`，理解 CPU 如何打包。  
4. 最后再进入 APV/Probe Volume 的采样与插值。  

---

## 34. `PackSH` 硬核映射（索引级别）

这一节把 CPU 侧 `sh[27]` 和 shader 侧 `unity_SH*` 做精确对齐。

### 34.1 `sh` 数组里 9 个系数的索引语义

在 Unity Core 的实现里，索引是：

- `i = l*(l+1) + m`

到 L2 时，单通道 9 项就是：

1. `i0 = (l=0,m=0)`
2. `i1 = (l=1,m=-1)`
3. `i2 = (l=1,m=0)`
4. `i3 = (l=1,m=1)`
5. `i4 = (l=2,m=-2)`
6. `i5 = (l=2,m=-1)`
7. `i6 = (l=2,m=0)`
8. `i7 = (l=2,m=1)`
9. `i8 = (l=2,m=2)`

RGB 三通道就是 `sh[c*9 + i]`，`c` 取 0/1/2。

### 34.2 Unity 打包到 `unity_SH*` 的公式

根据 `PackSH(...)`，每个颜色通道 `c` 有：

```text
unity_SHA(c).x = sh[c*9 + 3]
unity_SHA(c).y = sh[c*9 + 1]
unity_SHA(c).z = sh[c*9 + 2]
unity_SHA(c).w = sh[c*9 + 0] - sh[c*9 + 6]

unity_SHB(c).x = sh[c*9 + 4]
unity_SHB(c).y = sh[c*9 + 5]
unity_SHB(c).z = sh[c*9 + 6] * 3
unity_SHB(c).w = sh[c*9 + 7]

unity_SHC(c)   = sh[c*9 + 8]
```

其中：

- `unity_SHA(c)` 对应 R/G/B 通道分别是 `unity_SHAr/Ag/Ab`
- `unity_SHB(c)` 对应 R/G/B 通道分别是 `unity_SHBr/Bg/Bb`
- `unity_SHC(c)` 对应 `unity_SHC.r/g/b`

---

## 35. 为什么 `A.w = sh0 - sh6`、`B.z = 3*sh6`

这是一个非常经典、非常聪明的重排。

### 35.1 先看 shader 里的二阶相关项

`SHEvalLinearL2` 里有：

- `t2 = Nz*Nz`
- 系数项是 `B.z * t2`

如果 `B.z = 3*sh6`，那这一项是：

```text
3*sh6*Nz^2
```

### 35.2 再看 `A.w`

`SHEvalLinearL0L1` 常量项来自 `A.w`。
如果 `A.w = sh0 - sh6`，那常量里就有：

```text
sh0 - sh6
```

### 35.3 两者合并

把常量和 `Nz^2` 项放一起：

```text
(sh0 - sh6) + 3*sh6*Nz^2
= sh0 + sh6*(3*Nz^2 - 1)
```

这正好对应 SH 二阶里常见的 `(3z^2 - 1)` 结构。

通俗讲：

- Unity 通过“拆一部分到常量项”的打包方式，减少运行时额外组合成本。

---

## 36. 按单通道展开后的完整求值式

以 R 通道为例，代入 `SHEvalLinearL0L1 + SHEvalLinearL2` 可写成：

```text
R =
  unity_SHAr.x * Nx
+ unity_SHAr.y * Ny
+ unity_SHAr.z * Nz
+ unity_SHAr.w
+ unity_SHBr.x * (Nx*Ny)
+ unity_SHBr.y * (Ny*Nz)
+ unity_SHBr.z * (Nz*Nz)
+ unity_SHBr.w * (Nz*Nx)
+ unity_SHC.r  * (Nx*Nx - Ny*Ny)
```

G/B 通道同理，把 `Ar/Br/C.r` 换成 `Ag/Bg/C.g`、`Ab/Bb/C.b`。

这就是“每像素几次 dot + 少量乘法”背后的完整数学。

---

## 37. 可直接抄的调试版本（分项可视化）

当你怀疑 SH 项异常时，可以先把每项拆开看颜色贡献：

```hlsl
real3 EvalSH_Debug_L0L1(real3 N)
{
    real3 low = SHEvalLinearL0L1(N, unity_SHAr, unity_SHAg, unity_SHAb);
    return low;
}

real3 EvalSH_Debug_L2(real3 N)
{
    real3 l2 = SHEvalLinearL2(N, unity_SHBr, unity_SHBg, unity_SHBb, unity_SHC);
    return l2;
}

real3 EvalSH_Debug_Full(real3 N)
{
    real3 v = EvalSH_Debug_L0L1(N) + EvalSH_Debug_L2(N);
#ifdef UNITY_COLORSPACE_GAMMA
    v = LinearToSRGB(v);
#endif
    return v;
}
```

调试步骤建议：

1. 先看 `L0L1`，确认大方向对不对（上亮下暗是否符合预期）。  
2. 再看 `L2`，确认细节是微调而不是主导。  
3. 最后看 `Full`，确认与 `SampleSH` 一致。  

---

## 38. 一条最实用的工程建议

当你做角色/物体自定义光照时：

1. 不要一上来重写 SH 全流程。  
2. 先保留 `SampleSH(normalWS)` 作为 baseline。  
3. 只在确认需要时，才拆成 `L0L1/L2` 做风格化调节。  

这样最不容易把颜色空间、法线空间、系数打包这三件事同时搞乱。

---

## 39. `Y_lm` 形状直觉图（不画图版）

如果你记不住公式，先记“形状”。

### 39.1 L0：一个常量球

- 形状：整颗球同一个值。
- 作用：决定“整体底亮度”。

### 39.2 L1：三个一阶方向梯度

- `x` 项：左右方向一正一负（左亮右暗或相反）。
- `y` 项：上下方向一正一负。
- `z` 项：前后方向一正一负。

作用：决定“大方向偏亮”。

### 39.3 L2：五个二阶模式

在 Unity 求值多项式里对应：

1. `Nx*Ny`
2. `Ny*Nz`
3. `Nz*Nz`（配合常量重排）
4. `Nz*Nx`
5. `Nx*Nx - Ny*Ny`

作用：补充“比梯度更细一点”的方向结构（但仍然平滑低频）。

### 39.4 记忆口诀

- L0 定基线  
- L1 定方向  
- L2 修形状  

---

## 40. 从 Cubemap 到 SH9 的伪代码（离线预处理）

下面是最常见流程，适合你自己做工具或验证 Unity 结果。

### 40.1 输入输出

输入：

- 线性空间 cubemap（HDR 或 LDR）

输出：

- `sh[3][9]`（RGB 三通道，每通道 9 个系数）

### 40.2 伪代码

```text
init sh[3][9] = 0
sumOmega = 0

for each face in cubemap:
  for each texel (x, y):
    dir = CubemapTexelToDirection(face, x, y)   // 归一化方向
    L   = SampleCubemapLinear(face, x, y)       // linear RGB
    dOmega = TexelSolidAngle(face, x, y, size)  // 立体角权重

    basis[0..8] = EvalRealSH9Basis(dir)         // Y00..Y22

    for c in {R,G,B}:
      for i in 0..8:
        sh[c][i] += L[c] * basis[i] * dOmega

    sumOmega += dOmega

// 可选：检查 sumOmega 是否接近 4*PI（离散误差允许小偏差）

// 若你先得到的是 radiance SH，再做漫反射卷积：
// L0 频带乘 k0
// L1 频带乘 k1
// L2 频带乘 k2
// (clamped cosine: k0=1, k1=2/3, k2=1/4)

// 最后按 Unity PackSH 规则打包到 unity_SHA / SHB / SHC 结构
```

### 40.3 最容易做错的三处

1. 没用线性颜色做积分（Gamma 颜色直接积分会偏）。  
2. 漏掉立体角权重 `dOmega`。  
3. 坐标系约定不一致（x/y/z 轴方向和面朝向定义错位）。  

---

## 41. `EvalRealSH9Basis(dir)` 应该返回什么

标准 real SH9（常见教材形式）通常包含这些项：

1. 常量项  
2. 一阶三项（与 `x/y/z` 线性相关）  
3. 二阶五项（`xy/yz/(3z^2-1)/xz/(x^2-y^2)`）

注意：

- Unity 内部有自己的打包与符号约定。
- 如果你的目标是“和 Unity 完全一致”，优先对照 Unity 的 `PackSH` 和 `SHEval*` 路径，不要混用别的库默认约定。

实践建议：

1. 先用 Unity 原生路径当基准。  
2. 再用你自己的 `EvalRealSH9Basis` 对比误差。  
3. 误差大时优先检查轴向和符号，而不是先怀疑积分本身。  

---

## 42. 数值稳定与验收标准（工程向）

做完投影后，建议至少做这几项检查：

1. `sumOmega` 接近 `4*pi`。  
2. 对“常量白环境”投影后，L1/L2 应接近 0（只剩 L0 主导）。  
3. 将结果回代到球体法线上，颜色变化应平滑、无明显断层。  
4. 与引擎内置 `SampleSH` 结果做对比，允许小误差但趋势一致。  

如果不满足：

1. 先查坐标系约定。  
2. 再查立体角公式。  
3. 最后查颜色空间和卷积顺序。  

---

## 43. 30 分钟速学路线（按时间）

### 第 0~10 分钟：只建立直觉

1. 看第 1、2、3 节。  
2. 记住一句话：`SampleSH(normalWS)` 是环境漫反射底光。  
3. 记住 L0/L1/L2 分工：基线/方向/修形。  

### 第 10~20 分钟：对照代码

1. 看第 28、36 节映射式。  
2. 在 shader 里拆 `L0L1` 与 `L2` 可视化。  
3. 旋转球体验证“上亮下暗”是否符合预期。  

### 第 20~30 分钟：理解预处理

1. 看第 40、41、42 节。  
2. 理解 Cubemap 投影伪代码。  
3. 记住三大坑：线性颜色、立体角、坐标系。  

30 分钟结束后，你应该能做到：

1. 看懂 `SampleSH` 调用链。  
2. 判断 SH 异常来自法线、系数还是颜色空间。  
3. 自己写一个可工作的 SH 调试分项函数。  

---

## 44. 你下一步最值得做的一个小项目

做一个“SH Inspector 小工具”（哪怕是临时脚本）：

1. 输入：场景当前环境。  
2. 输出：`unity_SHA/B/C` 数值与预览球。  
3. 功能：L0/L1/L2 开关、法线方向探针、Gamma/Linear 切换对比。  

这个小项目做完，你对 SH 的理解会从“看懂”变成“会用 + 会排错”。
