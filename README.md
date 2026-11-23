# APTBM-demo

基于 MATLAB 的 APTBM 与 OQAM 单载波收发仿真，比较线性和非线性功率放大器条件下的 BER、SER、EVM 与发射波形 PAPR–CCDF。

完整目录、接口、参数定义与实现状态见 [工程目录说明](工程目录说明.md)。参考论文存放在 `论文/`，当前结果图片存放在 `results/`。

## 运行方法

在 MATLAB 中进入本项目根目录，然后运行：

```matlab
startup;
check_linear_link;
check_oqam_linear_link;
```

运行性能对比检查：

```matlab
ber_results = check_linear_ber_snr();
papr_results = check_papr_ccdf();
evm_results = check_evm_input_power();
ser_results = check_nonlinear_ser_snr();
```

上述检查会各自生成一张 PNG，保存到 `results/`，再次运行覆盖同名图片。当前通过各检查函数组织仿真，统一 `main.m` 入口尚未实现。

## 当前设置

| 项目 | 设置 |
|---|---|
| 调制 | 16×16 APTBM、16-QAM OQAM，每个符号周期均承载 4 比特 |
| 帧长度 | 8000 比特、2000 个复符号 |
| RRC | 滚降系数 0.25，每符号 4 点，跨度 10 个符号，单位能量 |
| PA | 改进 Rapp、Saleh、记忆多项式 MP，以及理想线性旁路 |
| SNR | 匹配滤波前、PA 输出端的采样点平均功率与复噪声功率之比 |
| 线性 BER | SNR 为 `0:1:20` dB，每点 50 帧 |
| PAPR–CCDF | 成形后、PA 前统计，共 10000 帧 |
| EVM | Rapp、Saleh、MP 三子图，SNR 为 `Inf`，Pin 为 `-35:1:-5` dBm，每点 100 帧 |
| 非线性 SER | Rapp Pin 为 −20 dBm，Saleh Pin 为 −13 dBm；SNR 为 `0:2:40` dB，每点 100 帧 |

APTBM 当前按角平分线局部坐标系展开相位，EVM 和非线性 SER 检查将同一工况的全部 100 帧接收块汇总，按论文式 (18) 统一计算一次平均块旋转角，再按式 (19) 补偿全部帧。不同 PA、输入功率及 SNR 分开统计。原圆均值与分支跟踪代码已在 `rx/aptbm_reconstruct.m` 中注释保留。

工程包含已实现的基础模块和待实现模块的目录规划，具体以工程说明中的状态标注为准。结果反映当前实现和有限帧统计，相关相位估计约定与限制见工程说明。
