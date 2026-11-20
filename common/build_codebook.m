function codebook = build_codebook(cfg)
%BUILD_CODEBOOK 根据论文中的定义生成 APTBM 码本。
%
% 使用方法：codebook = build_codebook(cfg);
%
% 参考论文：Amplitude-Phase-Time Block Modulation for Resisting Nonlinear
% Amplification and Its Application for Energy-Efficient Wireless Communications。
% 生成过程对应第 III 节：公共相位、式 (9) 的球面点、式 (10) 的符号块。
%
% 输出字段：
%   num_sphere_points  球面点数 L。
%   num_phases         公共相位数 M。
%   block_energy       块能量 P，每个块满足 |x_a|^2 + |x_b|^2 = P。
%   bits_per_block     每块承载的比特数 log2(M) + log2(L)。
%   sphere_points      L 行 3 列，每行为单位球面点 [U1, U2, U3]。
%   common_phases      M 行 1 列，存放论文中的 V = phi/2，单位为弧度。
%   phase_differences  L 行 1 列，存放式 (10) 中的 theta，单位为弧度。
%   blocks             M*L 行 2 列，每行为一个候选符号块 [x_a, x_b]。
%   bit_labels         M*L 行 K 列，每行为对应符号块的自然二进制标签。
%
% 标签约定：高位在左，前 log2(M) 位选择公共相位，后 log2(L) 位选择球面点。
% 行号约定：第 m 个公共相位与第 l 个球面点对应第 (m-1)*L+l 行。
% 本函数只返回码本，保存 .mat 文件由后续仿真入口负责。


%% 1. 读取调制参数

num_sphere_points = cfg.aptbm.num_sphere_points; % 球面点数 L。
num_phases = cfg.aptbm.num_phases;               % 公共相位数 M。
block_energy = cfg.aptbm.block_energy;           % 两个符号的总能量 P。

sphere_bits = log2(num_sphere_points);           % 选择一个球面点需要的比特数。
phase_bits = log2(num_phases);                   % 选择一个公共相位需要的比特数。
bits_per_block = phase_bits + sphere_bits;       % 每个符号块承载的比特数 K。
num_blocks = num_phases * num_sphere_points;     % 全部候选符号块的数量 M*L。

% 这里只检查生成码本所必需的条件，完整参数检查由 validate_config.m 负责。
if num_sphere_points < 1 || mod(sphere_bits, 1) ~= 0
    error('球面点数 L 必须为 2 的非负整数次幂。');
end

if num_phases < 1 || mod(phase_bits, 1) ~= 0
    error('公共相位数 M 必须为 2 的非负整数次幂。');
end

if bits_per_block == 0
    error('M 和 L 不能同时为 1，否则符号块无法承载比特。');
end

if block_energy <= 0 || ~isfinite(block_energy)
    error('块能量 P 必须为有限的正数。');
end


%% 2. 生成公共相位集合
% 论文第 III-B 节给出 V_m = phi_m/2 = 2*pi*(m-1)/M。
% 式 (10) 中对应的公共复数因子为 exp(-1j*V_m)。

common_phases = zeros(num_phases, 1);            % 预先分配公共相位数组。

for m = 1:num_phases
    common_phases(m) = 2 * pi * (m - 1) / num_phases; % 在圆周上等间隔取点。
end


%% 3. 根据式 (9) 生成 Fibonacci 球面点
% 球面点已归一化，每个点满足 U1^2 + U2^2 + U3^2 = 1。
% 索引 l 从 1 开始，严格使用论文中的 (2*l-1)/L-1 和 2*pi*chi*l。

golden_ratio = (sqrt(5) - 1) / 2;                % 论文中的黄金比例 chi。
sphere_points = zeros(num_sphere_points, 3);    % 预先分配球面点坐标数组。
phase_differences = zeros(num_sphere_points, 1); % 预先分配 theta 数组。
differential_symbols = complex(zeros(num_sphere_points, 2)); % 差分符号对。

for l = 1:num_sphere_points
    u1 = (2 * l - 1) / num_sphere_points - 1;    % 球面点的第一维坐标。
    circle_radius = sqrt(1 - u1^2);             % 固定 U1 后，截面圆的半径。
    circle_angle = 2 * pi * golden_ratio * l;   % 截面圆上的角度。

    u2 = circle_radius * cos(circle_angle);     % 球面点的第二维坐标。
    u3 = circle_radius * sin(circle_angle);     % 球面点的第三维坐标。

    sphere_points(l, :) = [u1, u2, u3];         % 保存第 l 个归一化球面点。

    % 论文写作 arctan(U3/U2)，这里使用 atan2(U3,U2) 保留完整象限。
    theta = atan2(u3, u2);                      % 获取式 (10) 所用的 theta。
    phase_differences(l) = theta;               % 保存该球面点对应的相位差参数。

    % 按式 (10) 构造差分部分：x_a 使用负相位，x_b 使用正相位。
    % 因而本文件中 theta = angle(x_b)-angle(x_a)，相位等式按模 2*pi 理解。
    amplitude_a = sqrt(block_energy * (1 + u1) / 2); % 第一个符号的幅度。
    amplitude_b = sqrt(block_energy * (1 - u1) / 2); % 第二个符号的幅度。

    differential_symbols(l, 1) = amplitude_a * exp(-1j * theta / 2);
    differential_symbols(l, 2) = amplitude_b * exp(1j * theta / 2);
end


%% 4. 根据式 (10) 组合全部符号块，并分配比特标签
% 外层遍历公共相位，内层遍历球面点，保证标签的两部分顺序固定。
% 自然二进制标签是本工程采用的标记方式，论文未指定唯一的逐点比特标签。

blocks = complex(zeros(num_blocks, 2));         % 每行存放一个候选符号块。
bit_labels = zeros(num_blocks, bits_per_block); % 每行存放对应的 K 位标签。

for m = 1:num_phases
    common_symbol = exp(-1j * common_phases(m)); % 当前公共相位对应的复数因子。

    for l = 1:num_sphere_points
        row = (m - 1) * num_sphere_points + l;  % 当前组合在码本中的行号。

        blocks(row, 1) = common_symbol * differential_symbols(l, 1); % x_a。
        blocks(row, 2) = common_symbol * differential_symbols(l, 2); % x_b。

        bit_text = dec2bin(row - 1, bits_per_block); % 将从 0 开始的索引转为二进制字符。
        bit_labels(row, :) = bit_text - '0';        % 将字符 '0'、'1' 转为数值 0、1。
    end
end


%% 5. 整理输出码本

codebook = struct();                           % 创建码本结构体。
codebook.num_sphere_points = num_sphere_points; % 保存球面点数 L。
codebook.num_phases = num_phases;               % 保存公共相位数 M。
codebook.block_energy = block_energy;           % 保存块能量 P。
codebook.bits_per_block = bits_per_block;       % 保存每块比特数 K。
codebook.sphere_points = sphere_points;         % 保存单位球面上的 L 个点。
codebook.common_phases = common_phases;         % 保存 M 个公共相位状态 V。
codebook.phase_differences = phase_differences; % 保存 L 个相位差参数 theta。
codebook.blocks = blocks;                       % 保存全部候选符号块。
codebook.bit_labels = bit_labels;               % 保存各候选符号块的比特标签。

end
