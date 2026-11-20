function symbols_rx = sample_symbols(waveform_matched, rrc_coeffs, cfg)
%SAMPLE_SYMBOLS 在理想同步条件下补偿滤波总延迟，并按符号间隔采样。
%
% 使用方法：symbols_rx = sample_symbols(waveform_matched, rrc_coeffs, cfg);
%
% 输入：
%   waveform_matched  matched_filter.m 输出的完整接收波形列向量。
%   rrc_coeffs        发射端使用的 RRC 系数列向量，接收端使用其匹配滤波器。
%   cfg               仿真参数结构体，提供每符号采样点数和每帧符号数量。
%
% 输出：symbols_rx 为符号速率的复数列向量，排列顺序与 symbols_tx 一致。
%       符号数量为每帧 APTBM 块数乘以每块符号数，默认输出 2000 行 1 列。
%
% 假设帧起点和符号定时已知，输入波形保留了收发滤波器的全部群延迟。
% 两个滤波器的总延迟由实际 RRC 系数长度计算，本函数通过采样起点补偿。
% 默认总延迟为 40 点，因此抽取第 41、45、49、...、8037 点。
% 采样保留信号当前的幅度和相位，后续由校准、重构和解调模块继续处理。


%% 1. 检查输入，并读取采样参数

if ~iscolumn(waveform_matched) || isempty(waveform_matched)
    error('sample_symbols:InputShape', '匹配滤波后的波形必须为非空列向量。');
end

if ~iscolumn(rrc_coeffs) || isempty(rrc_coeffs)
    error('sample_symbols:FilterShape', '发射 RRC 系数必须为非空列向量。');
end

samples_per_symbol = cfg.pulse.samples_per_symbol; % 相邻两个符号的采样点间隔。
num_symbols = cfg.sim.blocks_per_frame * cfg.aptbm.symbols_per_block; % 每帧符号数。

if ~isscalar(samples_per_symbol) || ~isreal(samples_per_symbol) ...
        || ~isfinite(samples_per_symbol) || samples_per_symbol < 1 ...
        || mod(samples_per_symbol, 1) ~= 0
    error('sample_symbols:SamplesPerSymbol', '每符号采样点数必须为正整数。');
end

if ~isscalar(num_symbols) || ~isreal(num_symbols) || ~isfinite(num_symbols) ...
        || num_symbols < 1 || mod(num_symbols, 1) ~= 0
    error('sample_symbols:SymbolCount', '每帧符号数必须为正整数。');
end


%% 2. 计算收发滤波器的总群延迟和有效采样范围
% 长度为 H 的对称 RRC 滤波器群延迟为 (H-1)/2 个采样点。
% 接收匹配滤波器与发射滤波器等长，两者延迟相加。

num_taps = numel(rrc_coeffs);                 % 读取实际使用的发射 RRC 系数个数。
tx_delay = (num_taps - 1) / 2;                % 发射滤波器的群延迟。
rx_delay = (num_taps - 1) / 2;                % 接收匹配滤波器的群延迟。
total_delay = tx_delay + rx_delay;            % 收发滤波器的总群延迟。

first_sample = total_delay + 1;              % MATLAB 从 1 开始编号，第一个符号在此采样。
last_sample = first_sample + (num_symbols - 1) * samples_per_symbol; % 最后一个符号位置。

if numel(waveform_matched) < last_sample
    error('sample_symbols:WaveformLength', '输入波形长度不足，无法抽取完整一帧符号。');
end


%% 3. 从理想采样位置逐个抽取符号
% 按确定的一帧符号数量抽取，保留每个符号的复数值。
% 有限长度 RRC 可能带来少量残余码间干扰，理想同步只负责确定采样位置。

symbols_rx = complex(zeros(num_symbols, 1));  % 为接收符号列向量预先分配空间。

for symbol_index = 1:num_symbols
    sample_index = first_sample + (symbol_index - 1) * samples_per_symbol; % 采样位置。
    symbols_rx(symbol_index) = waveform_matched(sample_index); % 取出当前复符号。
end

end
