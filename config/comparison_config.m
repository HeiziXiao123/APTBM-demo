function cfg = comparison_config()
%COMPARISON_CONFIG 返回 OQAM 与 APTBM 性能对比使用的统一参数。
%
% 使用方法：cfg = comparison_config();
%
% 本工程的 OQAM 指 QAM 的 I/Q 分支错开半个符号周期的单载波调制。
% 当前比较 16-QAM 对应的 OQAM 与 16×16 APTBM。
% 两者每个符号周期均传输 4 比特，平均符号能量均为 1。
% 本函数只定义参数，不生成比特、星座、波形或结果文件。


%% 1. 继承公共参数与 APTBM 参数
% 随机种子、帧数、RRC、PA、IBO、SNR 和自重构参数沿用默认配置。
% 两条链路共用 cfg.pulse、cfg.pa 和 cfg.channel 中的参数。

cfg = default_config();


%% 2. OQAM 调制参数

cfg.oqam.modulation_order = 16;          % I/Q 错位前的 QAM 星座点数。
cfg.oqam.bits_per_symbol = log2(cfg.oqam.modulation_order); % 每个 QAM 复符号的比特数。

% 归一化 QAM 星座的平均能量，使其与 APTBM 每个时间符号的平均能量相同。
% I/Q 分支分别承载实部和虚部，半符号错位不会增加信息比特数。
cfg.oqam.mean_symbol_energy = cfg.aptbm.mean_symbol_energy;

% Q 分支相对 I 分支延迟 T/2，当前每符号 4 点，对应延迟 2 点。
cfg.oqam.q_delay_samples = cfg.pulse.samples_per_symbol / 2;


%% 3. 两种调制共用的帧长度
% 以现有 APTBM 块数确定帧比特数，保持 generate_bits.m 的接口不变。
% 后续入口只生成一次 bits_tx，再把同一份比特送入两条链路。

cfg.sim.bits_per_frame = cfg.sim.blocks_per_frame * cfg.aptbm.bits_per_block;
cfg.oqam.symbols_per_frame = cfg.sim.bits_per_frame / cfg.oqam.bits_per_symbol;

% 默认一帧为 8000 比特：1000 个 APTBM 块，或 2000 个 OQAM 复符号。
% APTBM 每块占用两个符号周期，因此两种调制的有效数据时长相同。
% OQAM 波形末尾还需保留 Q 分支半符号延迟及滤波尾部。


%% 4. 对比实验的扫描选项

cfg.comparison.pa_models = {'rapp', 'saleh'}; % 依次比较两种非线性 PA。
cfg.comparison.reconstruction_modes = {'none', 'self'}; % APTBM 未重构与自重构。

% PA 循环中，将当前模型名称赋给 cfg.pa.model，再调用已有 PA 模块。
% IBO 扫描直接使用 cfg.pa.ibo_db，默认 [0, 3, 6, 9] dB。
% SNR 扫描直接使用 cfg.channel.snr_db，默认 0:2:20 dB。
% 重构模式只用于 APTBM；OQAM 使用自身的 QAM 检测与解映射。
% 两个 APTBM 结果应使用同一份接收块，分别进行旁路和自重构。
% 噪声仍按各自 PA 输出整帧波形的采样点平均功率定义 SNR。


%% 5. 检查对比所需的基本条件
% 这里只检查本配置新增的约束，完整参数检查由 validate_config.m 实现。

if mod(cfg.pulse.samples_per_symbol, 2) ~= 0
    error('OQAM 的半符号延迟要求每符号采样点数为偶数。');
end

if mod(cfg.sim.bits_per_frame, cfg.oqam.bits_per_symbol) ~= 0
    error('每帧比特数必须是 OQAM 每符号比特数的整数倍。');
end

% 相同符号周期下，每周期的比特数相同，才能保持相同的名义数据速率。
if cfg.oqam.bits_per_symbol ~= cfg.aptbm.bits_per_block / cfg.aptbm.symbols_per_block
    error('OQAM 与 APTBM 每个符号周期承载的比特数必须相同。');
end

end
