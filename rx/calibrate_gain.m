function symbols_calibrated = calibrate_gain(symbols_rx, amplitude_scale, cfg)
%CALIBRATE_GAIN 补偿已知 PA 小信号增益，将接收符号恢复到调制星座的参考标度。
%
% 使用方法：symbols_calibrated = calibrate_gain(symbols_rx, amplitude_scale, cfg);
%
% 输入：
%   symbols_rx       接收复数列向量，可以是采样符号，也可以是匹配滤波后的连续波形。
%   amplitude_scale  set_input_backoff.m 返回的第二个输出，即本帧的幅度缩放系数。
%   cfg              仿真参数结构体，按 cfg.pa.model 读取 PA 小信号增益。
%
% 输出：symbols_calibrated 为校准后的复数列向量，尺寸与输入相同。
%
% 仿真中假设接收端已知本帧的 amplitude_scale 和 PA 小信号增益。
% 总线性增益为 amplitude_scale * small_signal_gain，通过相除完成校准。
% rapp、saleh、linear 使用正实数增益；mp 使用一阶记忆系数之和作为静态复增益。
% MP 的直流小信号复增益同时补偿线性幅度和静态相移，不等同于记忆通道均衡。
% MP-OQAM 必须先校准匹配滤波后的连续复波形，再调用 oqam_sample_symbols。
% 发射 RRC 已归一化为单位能量，其匹配滤波峰值增益为 1。
% 校准后的 PA 非线性失真、记忆引起的频率相关幅相误差、噪声和残余干扰继续保留。
% 因此，码本的参考块能量由 cfg.aptbm.block_energy 给定，实际接收块能量仍可偏离。


%% 1. 检查接收符号和本帧幅度缩放系数

if ~iscolumn(symbols_rx) || isempty(symbols_rx)
    error('calibrate_gain:InputShape', '接收符号必须为非空列向量。');
end

if ~all(isfinite(symbols_rx))
    error('calibrate_gain:InputValue', '接收符号必须只包含有限数值。');
end

if ~isscalar(amplitude_scale) || ~isreal(amplitude_scale) ...
        || ~isfinite(amplitude_scale) || amplitude_scale <= 0
    error('calibrate_gain:AmplitudeScale', '本帧幅度缩放系数必须为有限的正实数。');
end


%% 2. 读取当前 PA 模型的小信号增益

switch cfg.pa.model
    case 'rapp'
        small_signal_gain = cfg.pa.rapp.g0;   % Rapp 在小幅度处的增益为 g0。

    case 'saleh'
        small_signal_gain = cfg.pa.saleh.alpha1; % Saleh 在小幅度处的增益为 alpha1。

    case 'mp'
        linear_row = find(cfg.pa.mp.orders == 1); % 查找一阶项对应的系数行。

        if numel(linear_row) ~= 1
            error('calibrate_gain:LinearOrder', 'MP 阶数向量必须包含唯一的一阶项。');
        end

        % 直流时各延迟抽头的相位因子均为 1，因此直接求一阶系数之和。
        small_signal_gain = sum(cfg.pa.mp.coeffs(linear_row, :));
        % 默认约为 1.0122+0.0827j，除以它可同时补偿幅度和约 +4.67 度静态相移。

    case 'linear'
        small_signal_gain = 1;               % 理想线性旁路的幅度增益为 1。

    otherwise
        error('calibrate_gain:Model', 'PA 模型必须为 rapp、saleh、mp 或 linear。');
end


%% 3. 补偿已知的总线性增益

total_gain = amplitude_scale * small_signal_gain; % IBO 缩放与 PA 小信号增益的乘积。

if ~isscalar(total_gain) || ~isfinite(total_gain) || abs(total_gain) <= 0
    error('calibrate_gain:TotalGain', '总线性增益必须为有限的非零标量。');
end

% 原有三个模型仍保持正实数增益约束，MP 允许使用非零复数增益。
if ~strcmp(cfg.pa.model, 'mp') && (~isreal(total_gain) || total_gain <= 0)
    error('calibrate_gain:TotalGain', 'rapp、saleh、linear 的总线性增益必须为正实数。');
end

symbols_calibrated = symbols_rx / total_gain; % 统一补偿整帧的线性幅度及 MP 静态相移。

end
