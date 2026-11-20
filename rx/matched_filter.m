function waveform_matched = matched_filter(waveform_rx, rrc_coeffs)
%MATCHED_FILTER 对接收波形进行匹配滤波，保留完整卷积结果。
%
% 使用方法：waveform_matched = matched_filter(waveform_rx, rrc_coeffs);
%
% 输入：
%   waveform_rx  由 add_awgn.m 输出的接收复波形列向量。
%   rrc_coeffs   发射端使用的 RRC 系数列向量，由 design_rrc.m 生成。
%
% 输出：waveform_matched 为匹配滤波后的复波形列向量。
%       输出长度 = 接收波形长度 + RRC 系数个数 - 1。
%       默认接收波形有 8037 点，RRC 有 41 个系数，输出为 8077 点。
%
% 匹配滤波器是发射滤波器的共轭时间反转，即 h_rx[n] = conj(h_tx[H-1-n])。
% 本函数保留群延迟和滤波尾部，收发总延迟由 sample_symbols.m 统一补偿。
% 默认收发滤波器各延迟 20 个采样点，总延迟为 40 个采样点。


%% 1. 检查输入波形和发射滤波器系数的尺寸

if ~iscolumn(waveform_rx) || isempty(waveform_rx)
    error('matched_filter:InputShape', '接收波形必须为非空列向量。');
end

if ~iscolumn(rrc_coeffs) || isempty(rrc_coeffs)
    error('matched_filter:FilterShape', '发射 RRC 系数必须为非空列向量。');
end


%% 2. 构造接收端匹配滤波器
% flipud 将列向量的系数顺序反转，conj 对每个系数取复共轭。
% 当前 RRC 系数为实数且对称，仍按共轭时间反转的定义构造匹配滤波器。

matched_coeffs = conj(flipud(rrc_coeffs));     % 得到与发射 RRC 对应的匹配滤波器。


%% 3. 对接收波形执行完整卷积
% 'full' 保留卷积首尾的所有采样点，供后续统一补偿延迟并抽取符号。

waveform_matched = conv(waveform_rx, matched_coeffs, 'full'); % 完成匹配滤波。

end
