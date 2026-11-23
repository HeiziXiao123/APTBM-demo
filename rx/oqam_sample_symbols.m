function symbols_rx = oqam_sample_symbols(waveform_matched, rrc_coeffs, cfg)
%OQAM_SAMPLE_SYMBOLS 在理想同步条件下分别采样 I/Q 分支，恢复复符号序列。
%
% 使用方法：symbols_rx = oqam_sample_symbols(waveform_matched, rrc_coeffs, cfg);
%
% 输入：
%   waveform_matched  matched_filter.m 输出的完整接收复波形列向量。
%   rrc_coeffs        发射端使用的单位能量实数 RRC 系数列向量。
%   cfg               comparison_config.m 返回的参数结构体。
%
% 输出：symbols_rx 为 N 行 1 列的复符号序列，顺序与 oqam_map.m 输出一致。
%       N 取 cfg.oqam.symbols_per_frame，默认输出 2000 个复符号。
%
% 假设帧起点、符号定时和载波同步已知，输入保留收发滤波器的全部延迟。
% I 分支在补偿收发滤波总延迟后采样，Q 分支的采样时刻再延后 T/2。
% 默认 I 分支取第 41、45、...、8037 点的实部，
%      Q 分支取第 43、47、...、8039 点的虚部，再按 I+1j*Q 合成。
% 采样后仍保留当前幅度标度、非线性失真、噪声及有限长滤波的残余干扰。
% MP 模型应先对连续匹配滤波波形调用 calibrate_gain.m，再传入本函数采样。
% 原有正实数增益模型可在采样后校准，最后调用 oqam_demap.m。


%% 1. 检查输入，并读取采样参数

if ~iscolumn(waveform_matched) || isempty(waveform_matched)
    error('oqam_sample_symbols:InputShape', '匹配滤波后的波形必须为非空列向量。');
end

if ~all(isfinite(waveform_matched))
    error('oqam_sample_symbols:InputValue', '接收波形必须只包含有限数值。');
end

if ~iscolumn(rrc_coeffs) || isempty(rrc_coeffs) ...
        || ~isreal(rrc_coeffs) || ~all(isfinite(rrc_coeffs))
    error('oqam_sample_symbols:FilterValue', 'RRC 系数必须为非空、有限的实数列向量。');
end

samples_per_symbol = cfg.pulse.samples_per_symbol; % 相邻 I 符号或 Q 符号的采样间隔 S。
q_delay_samples = cfg.oqam.q_delay_samples;    % 发射时 Q 分支相对 I 分支的延迟 D。
num_symbols = cfg.oqam.symbols_per_frame;     % 本帧需要恢复的 QAM 复符号数 N。

if ~isscalar(samples_per_symbol) || ~isreal(samples_per_symbol) ...
        || ~isfinite(samples_per_symbol) || samples_per_symbol < 2 ...
        || mod(samples_per_symbol, 2) ~= 0
    error('oqam_sample_symbols:SamplesPerSymbol', '每符号采样点数必须为正偶数。');
end

if ~isscalar(q_delay_samples) || ~isreal(q_delay_samples) ...
        || q_delay_samples ~= samples_per_symbol / 2
    error('oqam_sample_symbols:QDelay', 'Q 分支延迟必须等于每符号采样点数的一半。');
end

if ~isscalar(num_symbols) || ~isreal(num_symbols) || ~isfinite(num_symbols) ...
        || num_symbols < 1 || mod(num_symbols, 1) ~= 0
    error('oqam_sample_symbols:SymbolCount', '每帧 QAM 复符号数必须为正整数。');
end


%% 2. 计算收发滤波总延迟和 I/Q 采样起点
% 长度为 H 的对称 RRC 滤波器群延迟为 (H-1)/2 个采样点。
% 收发滤波器等长，总延迟为 H-1；Q 分支还需保留发射时的半符号延迟。

num_taps = numel(rrc_coeffs);                % 读取实际使用的 RRC 系数个数 H。
tx_delay = (num_taps - 1) / 2;               % 发射滤波器的群延迟。
rx_delay = (num_taps - 1) / 2;               % 接收匹配滤波器的群延迟。
total_delay = tx_delay + rx_delay;           % 收发滤波器总群延迟。

first_i_sample = total_delay + 1;           % 第一个 I 符号的采样位置。
first_q_sample = first_i_sample + q_delay_samples; % 第一个 Q 符号的采样位置。
last_q_sample = first_q_sample + (num_symbols - 1) * samples_per_symbol;

% Q 分支的最后采样点晚于 I 分支，用它检查能否恢复完整一帧。
if numel(waveform_matched) < last_q_sample
    error('oqam_sample_symbols:WaveformLength', '输入波形长度不足，无法抽取完整一帧 I/Q 符号。');
end


%% 3. 分别抽取实部和虚部，并按符号顺序重新组合
% 同一序号的 I/Q 信息来自发送端同一个 QAM 复符号，但采样时刻不同。

symbols_rx = complex(zeros(num_symbols, 1)); % 预先分配恢复的复符号列向量。

for symbol_index = 1:num_symbols
    sample_offset = (symbol_index - 1) * samples_per_symbol; % 当前符号相对首符号的位置。
    i_sample = first_i_sample + sample_offset; % 当前 I 分支采样位置。
    q_sample = first_q_sample + sample_offset; % 当前 Q 分支采样位置。

    i_value = real(waveform_matched(i_sample)); % 在 I 时刻只取实部。
    q_value = imag(waveform_matched(q_sample)); % 在 Q 时刻只取虚部。
    symbols_rx(symbol_index) = i_value + 1j * q_value; % 恢复对应的复符号。
end

end
