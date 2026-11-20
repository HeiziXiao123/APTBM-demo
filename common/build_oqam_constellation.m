function constellation = build_oqam_constellation(cfg)
%BUILD_OQAM_CONSTELLATION 生成 OQAM 映射所需的方形 QAM 星座。
%
% 使用方法：constellation = build_oqam_constellation(cfg);
% 输入：cfg 为 comparison_config.m 返回的参数结构体。
%
% 输出字段：
%   modulation_order    QAM 星座点数，支持 4、16、64 等方形 QAM。
%   bits_per_symbol     每个 QAM 复符号承载的比特数 K。
%   mean_symbol_energy  归一化后的星座平均能量。
%   symbols             M 行 1 列，每行存放一个候选复符号 I + 1j*Q。
%   bit_labels          M 行 K 列，每行为对应符号的数值比特标签。
%
% 标签约定：高位在左，前 K/2 位选择 I，后 K/2 位选择 Q。
% I/Q 两轴均采用 Gray 标记，相邻电平的标签只相差一位。
% 输出按标签的自然二进制值排列：标签对应整数 d，符号位于第 d+1 行。
% 本函数只生成映射表；半符号错位由 oqam_pulse_shape.m 实现。
% 保存 .mat 文件由后续仿真入口负责。


%% 1. 读取参数并检查生成条件

modulation_order = cfg.oqam.modulation_order; % QAM 星座点数 M。
mean_symbol_energy = cfg.oqam.mean_symbol_energy; % 目标平均符号能量。
bits_per_symbol = log2(modulation_order);    % 每个复符号的比特数 K。

% 方形 QAM 要求 M = 2^(2*k)，每条轴各承载 k 位比特。
if ~isfinite(bits_per_symbol) || ~isreal(bits_per_symbol) ...
        || bits_per_symbol < 2 || mod(bits_per_symbol, 2) ~= 0
    error('QAM 星座点数必须为 4、16、64 等 2 的正偶数次幂。');
end

if cfg.oqam.bits_per_symbol ~= bits_per_symbol
    error('cfg.oqam.bits_per_symbol 必须与星座点数的 log2 值一致。');
end

if ~isreal(mean_symbol_energy) || ~isfinite(mean_symbol_energy) ...
        || mean_symbol_energy <= 0
    error('QAM 平均符号能量必须为有限的正数。');
end

bits_per_axis = bits_per_symbol / 2;        % I 轴和 Q 轴各自的比特数。
points_per_axis = 2^bits_per_axis;          % 每条轴的电平数量。
axis_levels = -(points_per_axis - 1):2:(points_per_axis - 1); % 等间距对称电平。


%% 2. 生成星座点，并按 Gray 标记确定查表行号
% 默认 16-QAM 的每条轴电平为 -3、-1、1、3。
% 按电平从小到大的顺序，其 Gray 标签为 00、01、11、10。

symbols = complex(zeros(modulation_order, 1)); % 预先分配复星座点数组。
bit_labels = zeros(modulation_order, bits_per_symbol); % 预先分配标签数组。

for i = 1:points_per_axis
    % Gray 码 g = b XOR floor(b/2)，bitxor 为 MATLAB 自带的按位异或函数。
    i_gray = bitxor(i - 1, floor((i - 1) / 2)); % 当前 I 电平的 Gray 标签整数。

    for q = 1:points_per_axis
        q_gray = bitxor(q - 1, floor((q - 1) / 2)); % 当前 Q 电平的 Gray 标签整数。

        % I 标签在高位、Q 标签在低位，合并后得到该符号的标签整数。
        label_value = i_gray * points_per_axis + q_gray;
        row = label_value + 1;             % MATLAB 数组行号从 1 开始。

        symbols(row) = axis_levels(i) + 1j * axis_levels(q); % 构造 I+jQ。
        bit_text = dec2bin(label_value, bits_per_symbol); % 整数转为二进制字符。
        bit_labels(row, :) = bit_text - '0'; % 字符标签转为数值 0 和 1。
    end
end


%% 3. 归一化平均符号能量
% 平均能量按所有星座点等概率计算，不对每个星座点分别归一化。
% 默认 16-QAM 的原始平均能量为 10，目标为 1，因此统一除以 sqrt(10)。

original_energy = mean(abs(symbols).^2);    % 未归一化星座的平均能量。
amplitude_scale = sqrt(mean_symbol_energy / original_energy); % 统一幅度系数。
symbols = symbols * amplitude_scale;       % 缩放全部星座点，保持相对位置。


%% 4. 整理输出映射表

constellation = struct();                  % 创建星座结构体。
constellation.modulation_order = modulation_order; % 保存星座点数。
constellation.bits_per_symbol = bits_per_symbol; % 保存每符号比特数。
constellation.mean_symbol_energy = mean_symbol_energy; % 保存目标平均能量。
constellation.symbols = symbols;           % 保存归一化后的候选复符号。
constellation.bit_labels = bit_labels;     % 保存与候选符号逐行对应的比特标签。

end
