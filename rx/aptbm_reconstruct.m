function [blocks_rec, block_phase_shift] = aptbm_reconstruct(blocks_rx, cfg, previous_shift)
%APTBM_RECONSTRUCT 进行 APTBM 幅度与相位非线性自重构。
%
% 使用方法：blocks_rec = aptbm_reconstruct(blocks_rx, cfg);
% 获取帧平均块旋转角：[blocks_rec, block_phase_shift] = aptbm_reconstruct(blocks_rx, cfg);
%
% 输入：
%   blocks_rx  已完成幅度校准的接收块矩阵，每行是 [y_a, y_b]。
%   cfg        仿真参数结构体，提供块能量 P0、公共相位数 M 和权重参数 mu。
%   previous_shift  仅为兼容旧接口保留，新方法不使用其数值计算相移。
%
% 输出：blocks_rec 为重构后的复符号块，尺寸及块排列顺序与输入相同。
%       block_phase_shift 为仅根据当前帧、按式 (18) 计算的平均块旋转角。
%       none 模式输出原接收块，block_phase_shift 为 0。
%
% 'self' 依次执行幅度重构和相位重构，'none' 直接返回输入块。
% 幅度采用已确认的交叉补偿解释，等价于式 (15) 图片中的矩阵右乘列权重。
% 权重和补偿角分配分别沿用式 (16)-(17)、式 (19)。
% 当前链路已补偿 IBO 缩放和 PA 小信号增益，因此 P0 取码本块能量。
% 相位按当前复基带约定使用弧度，以 amplitude*exp(1j*phase) 合成符号。
% 按单位矢量角平分线建立局部坐标系，展开相位后严格按式 (18) 求均值。
% 一次调用对应一帧，只计算一次整帧平均块旋转角，不跨帧或跨功率点跟踪。
% 原去调制圆均值和相位分支跟踪方法完整注释保留在第 4 节。


%% 1. 检查输入和重构方式

if nargin < 3
    previous_shift = 0;                    % 兼容旧接口，新方法不使用此参考值。
end

block_phase_shift = 0;                     % 初始化相移输出，旁路时直接返回此值。

if ~ismatrix(blocks_rx) || size(blocks_rx, 2) ~= 2 || isempty(blocks_rx)
    error('aptbm_reconstruct:InputShape', '接收块必须为非空的 N 行 2 列矩阵。');
end

if ~all(isfinite(blocks_rx(:)))
    error('aptbm_reconstruct:InputValue', '接收块必须只包含有限数值。');
end

if strcmp(cfg.rx.reconstruction, 'none')
    blocks_rec = blocks_rx;                   % 旁路时保留每个复符号的原始值。
    return;
elseif ~strcmp(cfg.rx.reconstruction, 'self')
    error('aptbm_reconstruct:Mode', '重构方式必须为 self 或 none。');
end

block_energy = cfg.aptbm.block_energy;        % 校准后的理想块能量，对应论文的 P0。
num_phases = cfg.aptbm.num_phases;            % 公共相位字母表的状态数 M。
mu = cfg.rx.reconstruction_mu;               % 式 (17) 的缩放因子，论文取 0.6。

if ~isscalar(block_energy) || ~isreal(block_energy) ...
        || ~isfinite(block_energy) || block_energy <= 0
    error('aptbm_reconstruct:BlockEnergy', '理想块能量 P0 必须为有限的正实数。');
end

if ~isscalar(num_phases) || ~isreal(num_phases) || ~isfinite(num_phases) ...
        || num_phases < 1 || mod(num_phases, 1) ~= 0
    error('aptbm_reconstruct:PhaseCount', '公共相位数 M 必须为正整数。');
end

if ~isscalar(mu) || ~isreal(mu) || ~isfinite(mu) || mu <= 0
    error('aptbm_reconstruct:Mu', '权重缩放因子 mu 必须为有限的正实数。');
end

if ~isscalar(previous_shift) || ~isreal(previous_shift) || ~isfinite(previous_shift)
    error('aptbm_reconstruct:PreviousShift', '参考块相移必须为有限的实数，单位为弧度。');
end


%% 2. 按式 (16)、式 (17) 计算每个块的权重

amplitude_a = abs(blocks_rx(:, 1));           % 接收块中第一个符号的原始幅度。
amplitude_b = abs(blocks_rx(:, 2));           % 接收块中第二个符号的原始幅度。
power_a = amplitude_a.^2;                    % 第一个符号的功率。
power_b = amplitude_b.^2;                    % 第二个符号的功率。
power_sum = power_a + power_b;               % 每个接收块的原始功率和。

if ~all(isfinite(power_sum)) || any(power_sum <= 0)
    error('aptbm_reconstruct:BlockPower', '每个接收块的功率和必须为有限的正数。');
end

power_difference = (power_a - power_b) ./ power_sum; % 式 (16) 的归一化功率差 Pd。
num_blocks = size(blocks_rx, 1);             % 接收块总数 N。
weights = zeros(num_blocks, 1);              % 保存每个块的 xi 权重。

for block_index = 1:num_blocks
    sigmoid_argument = mu * tan(0.5 * pi * power_difference(block_index));

    % 两个分支均等价于 1/(1+exp(sigmoid_argument))，指数的自变量保持非正。
    % 这样在 Pd 接近正负 1 时也能避免 exp 溢出。
    if sigmoid_argument >= 0
        exponential = exp(-sigmoid_argument);
        weights(block_index) = exponential / (1 + exponential);
    else
        exponential = exp(sigmoid_argument);
        weights(block_index) = 1 / (1 + exponential);
    end
end


%% 3. 按已确认的式 (15) 交叉补偿形式重构幅度
% 将图片中的 2*2 矩阵右乘 [xi; 1-xi]，得到下面两个加权幅度。
% sqrt(P0-|y_b|^2) 是第一个符号的交叉幅度估计，另一项同理。
% 噪声可能使单个符号功率超过 P0，将根号内的负值截为 0，保持幅度为实数。

cross_amplitude_a = sqrt(max(block_energy - power_b, 0)); % 由 y_b 估计 y_a 的幅度。
cross_amplitude_b = sqrt(max(block_energy - power_a, 0)); % 由 y_a 估计 y_b 的幅度。

amplitude_rec_a = weights .* amplitude_a + (1 - weights) .* cross_amplitude_a;
amplitude_rec_b = weights .* cross_amplitude_b + (1 - weights) .* amplitude_b;


%% 4. 几何防缠绕展开，并严格按式 (18) 计算当前帧平均块旋转角

% 原方法：消除调制相位，求圆均值，并选择连续的相移分支。
% 以下旧代码完整注释保留，不参与当前计算。
% x_a*x_b 的差分相位抵消，只剩公共相位 exp(-1j*2*V)。
% 取 K=M/gcd(M,2) 次幂后，公共调制相位也抵消，保留块相移的信息。
% 在单位圆上平均，避免先映射到 [0,2*pi) 再求算术平均引入绕回偏差。
%
% phase_a = angle(blocks_rx(:, 1));             % 第一个接收符号的主值相角。
% phase_b = angle(blocks_rx(:, 2));             % 第二个接收符号的主值相角。
% valid_phase_blocks = power_a > 0 & power_b > 0; % 两个符号均非零时乘积相位才有定义。
%
% if ~any(valid_phase_blocks)
%     error('aptbm_reconstruct:PhaseObservation', '没有两个符号均非零的块，无法估计块相移。');
% end
%
% phase_sum = angle(blocks_rx(valid_phase_blocks, 1) ...
%     .* blocks_rx(valid_phase_blocks, 2));    % 接收符号乘积的主值相角。
% moment_order = num_phases / gcd(num_phases, 2); % 消除公共调制相位所需的阶数 K。
% phase_moment = mean(exp(1j * moment_order * phase_sum)); % 去调制后在单位圆上求均值。
%
% if abs(phase_moment) < 1e-12
%     error('aptbm_reconstruct:PhaseMoment', '去调制后的圆均值接近零，无法可靠估计相移。');
% end
%
% wrapped_shift = angle(phase_moment) / moment_order; % 只能确定到一个周期内的块相移。
% phase_period = 2 * pi / moment_order;       % 可选相移分支之间的间隔。
% branch_index = round((previous_shift - wrapped_shift) / phase_period);
% block_phase_shift = wrapped_shift + branch_index * phase_period; % 选择最接近参考的分支。

% 4.1 将两个接收符号归一化后相加，得到角平分线方向。
ya = blocks_rx(:, 1);                      % 当前帧所有块的第一个接收符号。
yb = blocks_rx(:, 2);                      % 当前帧所有块的第二个接收符号。
v_mid = ya ./ (abs(ya) + eps) + yb ./ (abs(yb) + eps); % eps 防止除零。

% 4.2 将角平分线的辐角映射到与公共 PSK 状态对应的 [0,2*pi) 区间。
psi_mid = mod(angle(v_mid), 2 * pi);

% 4.3 以半个公共状态间隔为门限，将零状态的负向微扰拉回负半轴。
idx_wrap = psi_mid > (2 * pi - pi / num_phases);
psi_mid(idx_wrap) = psi_mid(idx_wrap) - 2 * pi;

% 4.4 先旋转到角平分线局部坐标系，再加回基准角，得到展开后的相位。
% 不直接对两个接收符号的主值相角相加。
psi_ra = psi_mid + angle(ya .* exp(-1j * psi_mid));
psi_rb = psi_mid + angle(yb .* exp(-1j * psi_mid));

% 4.5 每帧只取一次均值，再减去式 (18) 的理论发送块相位均值。
phi_s_hat = mean(psi_ra + psi_rb) - 2 * pi * (num_phases - 1) / num_phases;
block_phase_shift = phi_s_hat;             % 返回当前帧的平均块旋转角。


%% 5. 按式 (19) 分配相位补偿，并合成重构后的复符号
% block_phase_shift 表示整个块的平均相移，两个补偿角相加等于该块相移。

phase_shift_a = (3 / 4 - weights / 2) * block_phase_shift; % 第一个符号的补偿角。
phase_shift_b = (1 / 4 + weights / 2) * block_phase_shift; % 第二个符号的补偿角。
% 原方法使用主值相角进行补偿，以下两行注释保留。
% phase_rec_a = phase_a - phase_shift_a;        % 从原始相角中减去第一个补偿角。
% phase_rec_b = phase_b - phase_shift_b;        % 从原始相角中减去第二个补偿角。
phase_rec_a = psi_ra - phase_shift_a;        % 从局部展开后的相位中减去第一个补偿角。
phase_rec_b = psi_rb - phase_shift_b;        % 从局部展开后的相位中减去第二个补偿角。

blocks_rec = complex(zeros(num_blocks, 2));   % 为输出双符号块预先分配空间。
blocks_rec(:, 1) = amplitude_rec_a .* exp(1j * phase_rec_a); % 合成第一个复符号。
blocks_rec(:, 2) = amplitude_rec_b .* exp(1j * phase_rec_b); % 合成第二个复符号。

end
