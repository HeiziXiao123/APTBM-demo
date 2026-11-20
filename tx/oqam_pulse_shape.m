function waveform_tx = oqam_pulse_shape(symbols_tx, rrc_coeffs, cfg)
%OQAM_PULSE_SHAPE 对 I/Q 分支进行 RRC 成形，并使 Q 分支延迟半个符号周期。
%
% 使用方法：waveform_tx = oqam_pulse_shape(symbols_tx, rrc_coeffs, cfg);
%
% 输入：
%   symbols_tx  由 oqam_map.m 输出的 QAM 复符号列向量。
%   rrc_coeffs  由 design_rrc.m 生成的单位能量实数 RRC 系数列向量。
%   cfg         由 comparison_config.m 返回的参数结构体。
%
% 输出：waveform_tx 为 I/Q 分支错位后合成的复基带波形列向量。
%       输入符号数为 N，每符号采样点数为 S，滤波器长度为 H，
%       Q 分支延迟为 D=S/2 时，输出长度为 (N-1)*S+H+D。
%       默认 N=2000、S=4、H=41、D=2，输出长度为 8039。
%
% 两分支使用同一个 RRC 滤波器，合成方式为 I 波形 + 1j*延迟后的 Q 波形。
% 保留发射滤波器群延迟、完整滤波尾部和 Q 分支半符号延迟。
% 沿用 RRC 的幅度标度，PA 输入功率由后续 set_input_backoff.m 调整。


%% 1. 检查输入并读取采样参数

if ~iscolumn(symbols_tx) || isempty(symbols_tx)
    error('oqam_pulse_shape:InputShape', '输入符号必须为非空列向量。');
end

if ~all(isfinite(symbols_tx))
    error('oqam_pulse_shape:InputValue', '输入符号必须只包含有限数值。');
end

if ~iscolumn(rrc_coeffs) || isempty(rrc_coeffs) ...
        || ~isreal(rrc_coeffs) || ~all(isfinite(rrc_coeffs))
    error('oqam_pulse_shape:FilterValue', 'RRC 系数必须为非空、有限的实数列向量。');
end

samples_per_symbol = cfg.pulse.samples_per_symbol; % 每个符号周期的采样点数 S。
q_delay_samples = cfg.oqam.q_delay_samples;    % Q 分支相对 I 分支的延迟 D。

if ~isfinite(samples_per_symbol) || samples_per_symbol < 2 ...
        || mod(samples_per_symbol, 2) ~= 0
    error('oqam_pulse_shape:SamplesPerSymbol', '每符号采样点数必须为正偶数。');
end

if q_delay_samples ~= samples_per_symbol / 2
    error('oqam_pulse_shape:QDelay', 'Q 分支延迟必须等于每符号采样点数的一半。');
end


%% 2. 分离 I/Q 信息，并分别插零上采样
% 两分支的相邻信息符号均间隔 S 个采样点；半符号错位在成形后实现。

num_symbols = numel(symbols_tx);             % 读取输入 QAM 复符号数 N。
num_samples = (num_symbols - 1) * samples_per_symbol + 1; % 插零后的分支长度。
i_upsampled = zeros(num_samples, 1);         % 预先分配 I 分支的实数列向量。
q_upsampled = zeros(num_samples, 1);         % 预先分配 Q 分支的实数列向量。

for symbol_index = 1:num_symbols
    sample_index = (symbol_index - 1) * samples_per_symbol + 1; % 当前符号的位置。
    i_upsampled(sample_index) = real(symbols_tx(symbol_index)); % 实部送入 I 分支。
    q_upsampled(sample_index) = imag(symbols_tx(symbol_index)); % 虚部送入 Q 分支。
end


%% 3. 两个分支分别进行完整 RRC 卷积
% 使用 'full' 保留最后一个信息符号的完整滤波响应。

i_shaped = conv(i_upsampled, rrc_coeffs, 'full'); % I 分支成形波形。
q_shaped = conv(q_upsampled, rrc_coeffs, 'full'); % Q 分支成形波形。


%% 4. 将 Q 分支延迟 T/2，并合成复基带波形
% 在 Q 分支开头补 D 个零，实现向后延迟，不使用循环移位。
% 在 I 分支末尾补 D 个零，使两分支长度相同，并保留 Q 分支尾部。

i_waveform = [i_shaped; zeros(q_delay_samples, 1)]; % I 分支时间起点保持不变。
q_waveform = [zeros(q_delay_samples, 1); q_shaped]; % Q 分支相对延迟 D 个采样点。
waveform_tx = i_waveform + 1j * q_waveform;   % 合成为可送入 PA 的复波形。

end
