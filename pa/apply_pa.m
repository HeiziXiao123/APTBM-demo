function waveform_pa_out = apply_pa(waveform_pa_in, cfg)
%APPLY_PA 按指定模型计算 PA 的无记忆或记忆多项式响应。
%
% 使用方法：waveform_pa_out = apply_pa(waveform_pa_in, cfg);
%
% 输入：
%   waveform_pa_in  由 set_input_backoff.m 调整幅度后的 PA 输入波形列向量。
%   cfg             仿真参数结构体，参数按 rapp、saleh、mp 模型分组存放。
%
% 输出：waveform_pa_out 为 PA 输出复波形，尺寸与输入相同。
%
% cfg.pa.model 为 'rapp' 时使用论文式 (20)，为 'saleh' 时使用式 (21)。
% 两种模型均逐采样点计算幅度压缩和相位偏移，属于无记忆模型。
% 'mp' 使用因果记忆多项式，按阶数和延迟抽头累加复数输出。
% MP 可按配置保持相位限幅；每次调用以零初始记忆开始，输出与输入等长。
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


%% 2. 按当前模型计算 PA 响应

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

    case 'mp'
        % 读取 MP 参数：系数矩阵的行对应阶数，列对应延迟抽头。
        orders = cfg.pa.mp.orders;
        coeffs = cfg.pa.mp.coeffs;
        memory_depth = cfg.pa.mp.memory_depth; % 抽头数 L，延迟为 0 到 L-1。

        if ~isscalar(memory_depth) || ~isreal(memory_depth) ...
                || ~isfinite(memory_depth) || memory_depth < 1 ...
                || mod(memory_depth, 1) ~= 0
            error('apply_pa:MemoryDepth', 'MP 记忆抽头数必须为正整数。');
        end

        if ~isvector(orders) || isempty(orders) || ~isreal(orders) ...
                || ~all(isfinite(orders(:))) || any(orders(:) < 1) ...
                || any(mod(orders(:), 2) ~= 1)
            error('apply_pa:Orders', 'MP 多项式阶数必须为非空的正奇数向量。');
        end

        if ~ismatrix(coeffs) || size(coeffs, 1) ~= numel(orders) ...
                || size(coeffs, 2) ~= memory_depth
            error('apply_pa:CoefficientsShape', 'MP 系数矩阵的行数须等于阶数数量，列数须等于记忆抽头数。');
        end

        if ~all(isfinite(coeffs(:)))
            error('apply_pa:CoefficientsValue', 'MP 系数必须只包含有限数值。');
        end

        % 先保护多项式的输入幅度，限幅时保持每个采样点的原始相位。
        x = waveform_pa_in;                 % 保留输入列向量，按配置对副本限幅。

        if cfg.pa.mp.clip_input
            max_input_amplitude = cfg.pa.mp.max_input_amplitude;

            if ~isscalar(max_input_amplitude) || ~isreal(max_input_amplitude) ...
                    || ~isfinite(max_input_amplitude) || max_input_amplitude <= 0
                error('apply_pa:MaxInputAmplitude', 'MP 输入幅度限幅上限必须为有限的正实数。');
            end

            idx_clip = amplitude_in > max_input_amplitude; % 仅处理超过上限的采样点。
            x(idx_clip) = max_input_amplitude * exp(1j * phase_in(idx_clip));
        end

        % 头部补 L-1 个零，实现输入开始前 x(n)=0 的因果边界条件。
        num_samples = numel(x);
        x_padded = [zeros(memory_depth - 1, 1); x];
        waveform_pa_out = complex(zeros(num_samples, 1)); % 为 N 个输出采样点分配空间。

        for l_idx = 1:memory_depth
            delay = l_idx - 1;             % 系数第 l_idx 列对应的实际延迟。
            first_sample = memory_depth - delay; % n=1 时延迟输入在补零向量中的位置。
            last_sample = first_sample + num_samples - 1;
            x_delayed = x_padded(first_sample:last_sample); % 整帧的 x(n-delay) 列向量。

            for k_idx = 1:numel(orders)
                order = orders(k_idx);     % 当前阶数，例如 1、3、5。
                polynomial_term = x_delayed .* (abs(x_delayed) .^ (order - 1));
                waveform_pa_out = waveform_pa_out + coeffs(k_idx, l_idx) .* polynomial_term;
            end
        end

        return;                             % MP 已得到复输出，直接返回，避免进入无记忆模型合成。

    case 'linear'
        waveform_pa_out = waveform_pa_in;     % 理想旁路保留输入的每个复数采样点。
        return;                              % 直接结束，不进行非线性变换。

    otherwise
        error('apply_pa:Model', 'PA 模型必须为 rapp、saleh、mp 或 linear。');
end


%% 3. 将输出幅度与输出相位合成为复波形

phase_out = phase_in + phase_shift;           % 原输入相位加上 PA 引入的相位偏移。
waveform_pa_out = amplitude_out .* exp(1j * phase_out); % 计算 PA 输出复波形。

end
