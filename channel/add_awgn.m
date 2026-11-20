function [waveform_rx, noise_variance] = add_awgn(waveform_pa_out, snr_db, cfg)
%ADD_AWGN 在 PA 输出波形上加入复高斯白噪声。
%
% 使用方法：
%   waveform_rx = add_awgn(waveform_pa_out, snr_db, cfg);
%   [waveform_rx, noise_variance] = add_awgn(waveform_pa_out, snr_db, cfg);
%
% 输入：
%   waveform_pa_out  由 apply_pa.m 输出的一帧复波形列向量，包含滤波尾部。
%   snr_db           本次使用的单个信噪比 SNR，单位为 dB；Inf 表示不加噪声。
%   cfg              仿真参数结构体，使用 cfg.channel.snr_reference。
%
% 输出：
%   waveform_rx      加噪后的接收波形，尺寸与 PA 输出波形相同。
%   noise_variance   每个复噪声采样点的理论方差 E{|w|^2}。
%
% 本工程以加噪前、匹配滤波前的 PA 输出波形为 SNR 参考：
%   signal_power = mean(abs(waveform_pa_out).^2)，包含整帧滤波尾部。
%   SNR = 10*log10(signal_power / noise_variance)。
%   noise_variance = signal_power / 10^(snr_db/10)。
% 实部和虚部为相互独立的零均值高斯噪声，各自方差为 noise_variance/2。
% SNR 按采样点平均功率定义，无需使用比特数或每符号采样点数换算。
% 随机种子由仿真入口统一设置，本函数沿用当前随机数状态。


%% 1. 检查输入及信号功率参考位置

if ~iscolumn(waveform_pa_out) || isempty(waveform_pa_out)
    error('add_awgn:InputShape', 'PA 输出波形必须为非空列向量。');
end

if ~all(isfinite(waveform_pa_out))
    error('add_awgn:InputValue', 'PA 输出波形必须只包含有限数值。');
end

if ~isscalar(snr_db) || ~isreal(snr_db) || isnan(snr_db) || snr_db == -Inf
    error('add_awgn:SNR', 'SNR 必须为单个有限实数或正无穷 Inf。');
end

if ~strcmp(cfg.channel.snr_reference, 'pa_output')
    error('add_awgn:Reference', '当前函数使用 pa_output 作为 SNR 的参考位置。');
end


%% 2. 计算信号平均功率和复噪声总方差

signal_power = mean(abs(waveform_pa_out).^2); % 对 PA 输出整帧的采样点模平方取平均。

if ~isfinite(signal_power) || signal_power <= 0
    error('add_awgn:SignalPower', 'PA 输出波形的平均功率必须为有限的正数。');
end

snr_linear = 10^(snr_db / 10);                % 将 SNR 的 dB 值转换为线性功率比。
noise_variance = signal_power / snr_linear;   % 根据目标 SNR 确定复噪声的理论总方差。

if ~isfinite(noise_variance) || noise_variance < 0
    error('add_awgn:NoiseVariance', '该 SNR 对应的噪声方差超出可计算范围。');
end

if noise_variance == 0
    waveform_rx = waveform_pa_out;            % Inf 对应零噪声，直接返回原波形。
    return;                                  % 零噪声时无需生成随机数。
end


%% 3. 分别生成实部和虚部的高斯白噪声

num_samples = numel(waveform_pa_out);         % 读取一帧波形的采样点数。
noise_std = sqrt(noise_variance / 2);         % 实部和虚部各自的标准差。

noise_real = noise_std * randn(num_samples, 1); % 生成实部的零均值高斯噪声。
noise_imag = noise_std * randn(num_samples, 1); % 独立生成虚部的零均值高斯噪声。
complex_noise = noise_real + 1j * noise_imag;  % 合成为复高斯白噪声。


%% 4. 将复噪声加到 PA 输出波形上
% noise_variance 是理论值，有限长度噪声的实测平均功率会有随机波动。

waveform_rx = waveform_pa_out + complex_noise; % 得到进入接收机的加噪波形。

end
