function cfg = default_config()
%DEFAULT_CONFIG 返回 APTBM 单载波收发仿真的默认参数。
%
% 使用方法：cfg = default_config();
%
% 命名约定：字段使用小写字母和下划线，按所属模块分组。
% 单位约定：角度使用弧度，Rapp 表中保留的度制参数在 apply_pa.m 中换算。
% 带 _db 后缀的参数使用 dB，带 _dbm 后缀的参数使用 dBm。
% 调制能量采用归一化数值，PA 模型的功率标度在第 4 节单独说明。
% 本函数只定义参数，不生成比特、码本、滤波器或仿真结果。

cfg = struct();                         % 创建用于存放全部参数的结构体。


%% 1. 仿真控制参数

cfg.sim.random_seed = 2026;             % 随机种子，由仿真入口设置随机数生成器。
cfg.sim.blocks_per_frame = 1000;        % 每帧包含的 APTBM 块数。
cfg.sim.max_frames = 100;               % 每个参数组合最多仿真的帧数。
cfg.sim.target_bit_errors = 200;        % 累计误比特数达到此值后，可结束当前组合。


%% 2. APTBM 调制参数
% 以下数值是初始仿真设置，具体球面坐标和比特标签由码本模块定义。
% 球面点数和初始相位数均应为 2 的整数次幂。

cfg.aptbm.num_sphere_points = 16;       % 球面状态点数 L。
cfg.aptbm.num_phases = 16;              % 初始相位数 M。
cfg.aptbm.symbols_per_block = 2;        % 每个块包含两个连续复符号 [a, b]。
cfg.aptbm.block_energy = 2;             % 每块满足 |a|^2 + |b|^2 = 2。

% 每块比特数 K = log2(L) + log2(M)，当前设置为 8 比特。
cfg.aptbm.bits_per_block = log2(cfg.aptbm.num_sphere_points) ...
    + log2(cfg.aptbm.num_phases);

% 平均每个时间符号的能量，当前设置为 1。
cfg.aptbm.mean_symbol_energy = cfg.aptbm.block_energy ...
    / cfg.aptbm.symbols_per_block;


%% 3. 脉冲成形与匹配滤波参数
% 发射端使用 RRC 滤波器，接收端使用对应的匹配滤波器。
% RRC 系数在 design_rrc.m 中归一化，使系数模平方之和等于 1。

cfg.pulse.samples_per_symbol = 4;       % 按论文配置，每个时间符号对应 4 个采样点。
cfg.pulse.rolloff = 0.25;               % RRC 滚降系数，取值范围为 0 到 1。
cfg.pulse.span_symbols = 10;            % 单个 RRC 滤波器跨越的时间符号数。


%% 4. 功率放大器参数
% 两种无记忆非线性模型均包含 AM-AM 和 AM-PM，参数取自论文表 II。
% 'rapp' 对应式 (20)，'saleh' 对应式 (21)，'linear' 为单位增益理想旁路。

cfg.pa.model = 'rapp';                  % 本次使用的 PA 模型，可改为 'saleh' 或 'linear'。
cfg.pa.ibo_db = [0, 3, 6, 9];           % 待扫描的输入回退值，单位为 dB。

% 4.1 改进 Rapp 模型参数
cfg.pa.rapp.g0 = 4.65;                 % 小信号幅度增益 g0，采用线性数值。
cfg.pa.rapp.a_sat = 0.58;              % 输出饱和幅度 A_sat。
cfg.pa.rapp.q0 = 0.81;                 % AM-AM 平滑系数 q0。
cfg.pa.rapp.alpha0 = 2560;             % AM-PM 系数 alpha0；本组参数计算的偏移为度。
cfg.pa.rapp.beta0 = 0.114;             % AM-PM 幅度参数 beta0。
cfg.pa.rapp.q1 = 2.4;                  % AM-PM 分子中的幅度指数 q1。
cfg.pa.rapp.q2 = 2.3;                  % AM-PM 分母中的幅度指数 q2。
cfg.pa.rapp.input_saturation_dbm = -15; % 论文给出的输入饱和功率，作为 IBO 参考点。

% 4.2 Saleh 模型参数
cfg.pa.saleh.alpha1 = 2.1587;          % AM-AM 分子系数 alpha1，也是小信号幅度增益。
cfg.pa.saleh.beta1 = 1.1517;           % AM-AM 分母系数 beta1。
cfg.pa.saleh.alpha2 = 4.0033;          % AM-PM 分子系数 alpha2，计算的偏移为弧度。
cfg.pa.saleh.beta2 = 9.1040;           % AM-PM 分母系数 beta2。
cfg.pa.saleh.input_saturation_dbm = 0; % 论文给出的输入饱和功率，作为 IBO 参考点。

% 4.3 输入参考功率
% 为对应论文的功率坐标，PA 端约定 abs(x)^2 的数值采用 mW 标度。
% 因此 P_dBm = 10*log10(P)，反变换为 P = 10^(P_dBm/10)。
% 这里的功率数值用于数字模型，不额外引入射频阻抗或电压换算。
cfg.pa.rapp.reference_input_power = 10^(cfg.pa.rapp.input_saturation_dbm / 10);
cfg.pa.saleh.reference_input_power = 10^(cfg.pa.saleh.input_saturation_dbm / 10);

% IBO = 10*log10(当前模型的输入参考功率 / PA 输入平均功率)。
% set_input_backoff.m 根据 cfg.pa.model 选择参考功率；理想旁路以 1 为参考。


%% 5. AWGN 信道参数

cfg.channel.snr_db = 0:2:20;            % 待扫描的采样点信噪比 SNR，单位为 dB。
cfg.channel.snr_reference = 'pa_output'; % 使用加噪前、匹配滤波前的 PA 输出功率。

% 信号功率 Ps = mean(abs(PA 输出波形).^2)，平均时包含整帧滤波尾部。
% SNR = 10*log10(Ps/Pn)，复噪声总方差 Pn = Ps/10^(SNR/10)。
% 实部和虚部各占噪声总方差的一半，无需按比特数或上采样因子换算。


%% 6. 接收端参数
% 假设载波同步、符号定时和块边界已知，仍需补偿收发滤波器总延迟。
% 幅度重构使用已确认的式 (15) 交叉补偿解释，权重按式 (16)-(17) 计算。
% 相位先按角平分线局部坐标系展开，每帧按式 (18) 独立估计平均块旋转角。
% 单符号补偿角按式 (19) 分配，不使用跨帧或跨功率点相移跟踪。
% 输入为已完成幅度校准的接收块。

cfg.rx.reconstruction = 'self';         % 'self' 使用论文自重构，'none' 为重构旁路。
cfg.rx.reconstruction_mu = 0.6;         % 式 (17) 中的权重缩放因子 mu。

end
