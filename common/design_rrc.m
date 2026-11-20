function rrc_coeffs = design_rrc(cfg)
%DESIGN_RRC 生成单位能量的根升余弦（RRC）滤波器系数。
%
% 使用方法：rrc_coeffs = design_rrc(cfg);
%
% 输入：cfg 为 default_config.m 返回的参数结构体。
% 输出：rrc_coeffs 为实数列向量，长度为 span_symbols*samples_per_symbol+1。
%       系数关于中心对称，归一化后满足 sum(abs(rrc_coeffs).^2) = 1。
%
% 默认配置：滚降系数 0.25，上采样因子 4，跨度 10 个符号，共 41 个系数。
% 单个滤波器的群延迟为 (系数个数-1)/2，默认对应 20 个采样点。
% 本函数直接计算 RRC 时域公式，只返回系数，脉冲成形由后续模块完成。


%% 1. 读取滤波器参数

rolloff = cfg.pulse.rolloff;                   % 滚降系数，下面公式中的 beta。
samples_per_symbol = cfg.pulse.samples_per_symbol; % 每个符号对应的采样点数。
span_symbols = cfg.pulse.span_symbols;         % 滤波器截断长度，单位为符号周期。


%% 2. 检查设计滤波器所需的参数

if ~isfinite(rolloff) || rolloff < 0 || rolloff > 1
    error('design_rrc:Rolloff', '滚降系数必须为 0 到 1 之间的有限数值。');
end

if ~isfinite(samples_per_symbol) || samples_per_symbol < 1 ...
        || mod(samples_per_symbol, 1) ~= 0
    error('design_rrc:SamplesPerSymbol', '每符号采样点数必须为正整数。');
end

if ~isfinite(span_symbols) || span_symbols < 1 || mod(span_symbols, 1) ~= 0
    error('design_rrc:Span', '滤波器跨度必须为正整数个符号周期。');
end

filter_order = span_symbols * samples_per_symbol; % 滤波器阶数，等于系数个数减 1。

if mod(filter_order, 2) ~= 0
    error('design_rrc:FilterOrder', '跨度与每符号采样点数的乘积必须为偶数。');
end


%% 3. 按 RRC 时域公式逐点计算系数
% 时间 t 已除以符号周期，因此 t = 1 表示一个符号周期。
% 一般位置的公式为：
% h(t) = [sin(pi*t*(1-beta)) + 4*beta*t*cos(pi*t*(1+beta))]
%        / [pi*t*(1-(4*beta*t)^2)]。
% 在 t = 0 和 t = +/-1/(4*beta) 处使用极限值，避免分母为 0。

num_taps = filter_order + 1;                   % 计算滤波器系数个数。
center_index = (num_taps + 1) / 2;             % 中心系数对应 t = 0。
rrc_coeffs = zeros(num_taps, 1);               % 预先分配实数系数列向量。

for tap_index = 1:num_taps
    t = (tap_index - center_index) / samples_per_symbol; % 当前采样点的归一化时间。

    if t == 0
        % 中心位置的极限值：h(0) = 1-beta+4*beta/pi。
        rrc_coeffs(tap_index) = 1 - rolloff + 4 * rolloff / pi;

    elseif rolloff == 0
        % 滚降系数为 0 时退化为 sinc；t = 0 已在上一分支处理。
        rrc_coeffs(tap_index) = sin(pi * t) / (pi * t);

    elseif abs(abs(4 * rolloff * t) - 1) < 1e-12
        % 在 t = +/-1/(4*beta) 附近使用极限值。
        limit_angle = pi / (4 * rolloff);      % 极限公式中的角度。
        sine_part = (1 + 2 / pi) * sin(limit_angle); % 极限公式的正弦项。
        cosine_part = (1 - 2 / pi) * cos(limit_angle); % 极限公式的余弦项。
        rrc_coeffs(tap_index) = rolloff / sqrt(2) * (sine_part + cosine_part);

    else
        % 其余位置直接使用一般公式。
        sine_part = sin(pi * t * (1 - rolloff)); % 分子中的正弦项。
        cosine_part = 4 * rolloff * t * cos(pi * t * (1 + rolloff)); % 余弦项。
        denominator = pi * t * (1 - (4 * rolloff * t)^2); % 一般公式的分母。
        rrc_coeffs(tap_index) = (sine_part + cosine_part) / denominator;
    end
end


%% 4. 将滤波器系数归一化为单位能量
% 收发端沿用这一能量约定，便于后续确定匹配滤波增益和噪声方差。

filter_energy = sum(abs(rrc_coeffs).^2);        % 计算截断后的离散滤波器能量。
rrc_coeffs = rrc_coeffs / sqrt(filter_energy);  % 缩放系数，使模平方之和等于 1。

end
