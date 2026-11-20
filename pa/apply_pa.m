function waveform_pa_out = apply_pa(waveform_pa_in, cfg)
%APPLY_PA 按指定模型计算 PA 的 AM-AM 和 AM-PM 非线性响应。
%
% 使用方法：waveform_pa_out = apply_pa(waveform_pa_in, cfg);
%
% 输入：
%   waveform_pa_in  由 set_input_backoff.m 调整幅度后的 PA 输入波形列向量。
%   cfg             仿真参数结构体，模型参数分别存放在 cfg.pa.rapp 和 cfg.pa.saleh。
%
% 输出：waveform_pa_out 为 PA 输出复波形，尺寸与输入相同。
%
% cfg.pa.model 为 'rapp' 时使用论文式 (20)，为 'saleh' 时使用式 (21)。
% 两种模型均逐采样点计算幅度压缩和相位偏移，属于无记忆模型。
% 'linear' 表示单位增益理想旁路，直接返回输入波形。
%
% 单位：Rapp 的 alpha0=2560 对应度制相位偏移，计算后转为弧度。
%       Saleh 的相位偏移直接使用弧度；复指数中的角度统一为弧度。
% Rapp 度制参数来源：IEEE 802.11-09/0296r16，TGad Evaluation Methodology。


%% 1. 检查输入，并提取幅度与相位

if ~iscolumn(waveform_pa_in) || isempty(waveform_pa_in)
    error('apply_pa:InputShape', 'PA 输入波形必须为非空列向量。');
end

if ~all(isfinite(waveform_pa_in))
    error('apply_pa:InputValue', 'PA 输入波形必须只包含有限数值。');
end

amplitude_in = abs(waveform_pa_in);            % 提取每个输入采样点的幅度。
phase_in = angle(waveform_pa_in);              % 提取输入相位，单位为弧度。


%% 2. 按当前模型计算输出幅度和附加相位

switch cfg.pa.model
    case 'rapp'
        % 读取式 (20) 的参数，变量名与图中公式对应。
        g0 = cfg.pa.rapp.g0;                  % 小信号幅度增益。
        a_sat = cfg.pa.rapp.a_sat;            % 输出饱和幅度。
        q0 = cfg.pa.rapp.q0;                  % 幅度压缩的平滑系数。
        alpha0 = cfg.pa.rapp.alpha0;          % 度制相位偏移的分子系数。
        beta0 = cfg.pa.rapp.beta0;            % 相位模型的幅度参数。
        q1 = cfg.pa.rapp.q1;                  % 相位模型分子的幅度指数。
        q2 = cfg.pa.rapp.q2;                  % 相位模型分母的幅度指数。

        % AM-AM：按 Rapp 公式计算压缩后的幅度。
        linear_amplitude = g0 * amplitude_in; % 小信号线性放大时的幅度。
        compression_term = (linear_amplitude / a_sat).^(2 * q0); % 压缩项。
        amplitude_out = linear_amplitude ./ (1 + compression_term).^(1 / (2 * q0));

        % AM-PM：按改进 Rapp 公式计算相位偏移，再从度换算为弧度。
        phase_numerator = alpha0 * amplitude_in.^q1; % 相位公式的分子。
        phase_denominator = 1 + (amplitude_in / beta0).^q2; % 相位公式的分母。
        phase_shift_deg = phase_numerator ./ phase_denominator; % 度制相位偏移。
        phase_shift = phase_shift_deg * pi / 180; % 转为复指数所需的弧度。

    case 'saleh'
        % 读取式 (21) 的参数。
        alpha1 = cfg.pa.saleh.alpha1;          % 幅度公式的分子系数。
        beta1 = cfg.pa.saleh.beta1;            % 幅度公式的分母系数。
        alpha2 = cfg.pa.saleh.alpha2;          % 相位公式的分子系数。
        beta2 = cfg.pa.saleh.beta2;            % 相位公式的分母系数。

        input_power = amplitude_in.^2;        % 两个公式共同使用的输入幅度平方。

        % AM-AM：直接使用 Saleh 幅度公式，保留大幅度区域的输出回落特性。
        amplitude_out = alpha1 * amplitude_in ./ (1 + beta1 * input_power);

        % AM-PM：Saleh 公式给出的附加相位单位为弧度。
        phase_shift = alpha2 * input_power ./ (1 + beta2 * input_power);

    case 'linear'
        waveform_pa_out = waveform_pa_in;     % 理想旁路保留输入的每个复数采样点。
        return;                              % 直接结束，不进行非线性变换。

    otherwise
        error('apply_pa:Model', 'PA 模型必须为 rapp、saleh 或 linear。');
end


%% 3. 将输出幅度与输出相位合成为复波形

phase_out = phase_in + phase_shift;           % 原输入相位加上 PA 引入的相位偏移。
waveform_pa_out = amplitude_out .* exp(1j * phase_out); % 计算 PA 输出复波形。

end
