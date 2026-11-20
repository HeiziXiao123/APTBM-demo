function waveform_tx = pulse_shape(symbols_tx, rrc_coeffs, cfg)
%PULSE_SHAPE 对串行符号插零上采样，并进行 RRC 脉冲成形。
%
% 使用方法：waveform_tx = pulse_shape(symbols_tx, rrc_coeffs, cfg);
%
% 输入：
%   symbols_tx  由 serialize_blocks.m 输出的复符号列向量。
%   rrc_coeffs  由 design_rrc.m 生成的单位能量 RRC 系数列向量。
%   cfg         仿真参数结构体，使用其中的每符号采样点数。
%
% 输出：waveform_tx 为成形后的复基带波形列向量。
%       若输入有 N 个符号，上采样因子为 S，滤波器长度为 H，
%       则完整输出长度为 (N-1)*S+H。
%       默认 N=2000、S=4、H=41，输出长度为 8037。
%
% 本函数保留完整滤波尾部及发射滤波器群延迟，延迟由接收端统一补偿。
% 成形沿用 RRC 系数的幅度，PA 输入功率由后续 set_input_backoff.m 调整。


%% 1. 检查输入并读取上采样因子

if ~iscolumn(symbols_tx) || isempty(symbols_tx)
    error('pulse_shape:InputShape', '输入符号必须为非空列向量。');
end

if ~iscolumn(rrc_coeffs) || isempty(rrc_coeffs)
    error('pulse_shape:FilterShape', 'RRC 系数必须为非空列向量。');
end

samples_per_symbol = cfg.pulse.samples_per_symbol; % 每个符号对应的采样点数 S。

if ~isfinite(samples_per_symbol) || samples_per_symbol < 1 ...
        || mod(samples_per_symbol, 1) ~= 0
    error('pulse_shape:SamplesPerSymbol', '每符号采样点数必须为正整数。');
end


%% 2. 在相邻符号之间插入零，完成上采样
% 例如符号为 [a; b; c]，S=4 时得到 [a; 0; 0; 0; b; 0; 0; 0; c]。
% 上采样序列从第一个符号开始，到最后一个符号结束，共有 (N-1)*S+1 点。

num_symbols = numel(symbols_tx);              % 读取输入符号的数量 N。
num_samples = (num_symbols - 1) * samples_per_symbol + 1; % 上采样序列的长度。
symbols_upsampled = complex(zeros(num_samples, 1)); % 预先分配插零后的复数列向量。

for symbol_index = 1:num_symbols
    sample_index = (symbol_index - 1) * samples_per_symbol + 1; % 当前符号的位置。
    symbols_upsampled(sample_index) = symbols_tx(symbol_index); % 写入符号，其余位置为零。
end


%% 3. 与 RRC 滤波器进行完整卷积
% 'full' 保留首尾的全部卷积结果，包含最后一个符号的完整滤波响应。
% 两个输入均为列向量，输出也为列向量。

waveform_tx = conv(symbols_upsampled, rrc_coeffs, 'full'); % 得到发射端成形波形。

end
