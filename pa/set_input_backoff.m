function [waveform_pa_in, amplitude_scale] = set_input_backoff(waveform_tx, ibo_db, cfg)
%SET_INPUT_BACKOFF 根据指定的 IBO 调整成形波形的幅度。
%
% 使用方法：
%   waveform_pa_in = set_input_backoff(waveform_tx, ibo_db, cfg);
%   [waveform_pa_in, amplitude_scale] = set_input_backoff(waveform_tx, ibo_db, cfg);
%
% 输入：
%   waveform_tx  由 pulse_shape.m 输出的成形波形列向量。
%   ibo_db       本次使用的单个输入回退值，单位为 dB。
%   cfg          仿真参数结构体，按 cfg.pa.model 选择分组中的输入参考功率。
%
% 输出：
%   waveform_pa_in  调整幅度后送入 PA 的波形，尺寸与输入相同。
%   amplitude_scale 施加在整帧波形上的幅度缩放系数，可供接收端校准使用。
%
% 定义：IBO = 10*log10(输入参考功率 / PA 输入平均功率)。
% 平均功率按整帧波形的采样点计算，包含脉冲成形的滤波尾部。
% cfg.pa.ibo_db 是待扫描的数组，调用时应从中选择一个值传入 ibo_db。


%% 1. 读取输入参考功率，并检查输入

switch cfg.pa.model
    case 'rapp'
        reference_input_power = cfg.pa.rapp.reference_input_power; % Rapp 的参考功率。

    case 'saleh'
        reference_input_power = cfg.pa.saleh.reference_input_power; % Saleh 的参考功率。

    case 'mp'
        reference_input_power = cfg.pa.mp.reference_input_power; % MP 的参考功率。

    case 'linear'
        reference_input_power = 1;            % 理想单位增益旁路使用归一化参考功率 1。

    otherwise
        error('set_input_backoff:Model', 'PA 模型必须为 rapp、saleh、mp 或 linear。');
end

if ~iscolumn(waveform_tx) || isempty(waveform_tx)
    error('set_input_backoff:InputShape', '成形波形必须为非空列向量。');
end

if ~isscalar(ibo_db) || ~isreal(ibo_db) || ~isfinite(ibo_db)
    error('set_input_backoff:IBO', '本次 IBO 必须为单个有限实数，单位为 dB。');
end

if ~isscalar(reference_input_power) || ~isreal(reference_input_power) ...
        || ~isfinite(reference_input_power) || reference_input_power <= 0
    error('set_input_backoff:ReferencePower', '输入参考功率必须为有限的正实数。');
end


%% 2. 计算当前平均功率和目标平均功率

current_power = mean(abs(waveform_tx).^2);     % 对整帧波形的模平方取平均。

if ~isfinite(current_power) || current_power <= 0
    error('set_input_backoff:WaveformPower', '波形平均功率必须为有限的正数。');
end

target_power = reference_input_power / 10^(ibo_db / 10); % 根据 IBO 定义反求目标功率。

if ~isfinite(target_power) || target_power <= 0
    error('set_input_backoff:TargetPower', '该 IBO 对应的目标功率超出可计算范围。');
end


%% 3. 用统一的幅度系数缩放整帧波形
% 功率随幅度的平方变化，因此幅度系数等于目标功率与当前功率之比的平方根。
% 所有采样点使用同一个正实数系数，保留波形的相位和相对幅度关系。

amplitude_scale = sqrt(target_power / current_power); % 计算幅度缩放系数。
waveform_pa_in = amplitude_scale * waveform_tx;      % 得到 PA 输入端的波形。

end
