function symbols_tx = oqam_map(bits_tx, constellation)
%OQAM_MAP 将一帧比特映射为 OQAM 成形所需的 QAM 复符号序列。
%
% 使用方法：symbols_tx = oqam_map(bits_tx, constellation);
%
% 输入：
%   bits_tx        由 generate_bits.m 生成的比特列向量，只包含数值 0 和 1。
%   constellation  由 build_oqam_constellation.m 生成的星座结构体。
%
% 输出：
%   symbols_tx 为 N 行 1 列的复符号序列，每个元素为一个 I + 1j*Q 符号。
%   N 为输入比特总数除以每符号比特数 K，默认一帧输出 2000 个符号。
%   real(symbols_tx) 和 imag(symbols_tx) 分别作为后续成形的 I/Q 分支输入。
%
% 每 K 位构成一个标签，高位在前；前 K/2 位选择 I，后 K/2 位选择 Q。
% 星座表已包含 Gray 标记与能量归一化，本函数直接查表，不再转换标签。
% I/Q 半符号错位及脉冲成形由 oqam_pulse_shape.m 实现。


%% 1. 读取每符号比特数，并检查输入比特

bits_per_symbol = constellation.bits_per_symbol; % 每个 QAM 复符号承载的比特数 K。
num_bits = numel(bits_tx);                     % 统计一帧输入的比特总数。

if ~iscolumn(bits_tx)
    error('oqam_map:InputShape', '输入比特必须为列向量。');
end

if ~all(bits_tx == 0 | bits_tx == 1)
    error('oqam_map:InvalidBits', '输入比特只能包含数值 0 和 1。');
end

if mod(num_bits, bits_per_symbol) ~= 0
    error('oqam_map:BitCount', '输入比特总数必须为每符号比特数 K 的整数倍。');
end


%% 2. 预先分配复符号列向量

num_symbols = num_bits / bits_per_symbol;      % 计算本帧的 QAM 复符号数 N。
symbols_tx = complex(zeros(num_symbols, 1));   % 按发送顺序预留 N 个复符号的位置。


%% 3. 逐组读取比特，并查找对应的星座点

for symbol_index = 1:num_symbols
    first_bit = (symbol_index - 1) * bits_per_symbol + 1; % 当前组第一位的位置。
    last_bit = symbol_index * bits_per_symbol;          % 当前组最后一位的位置。

    label_value = 0;                           % 初始化当前标签的整数值。

    % 从高位到低位逐位读取，每次将已有整数乘以 2，再加上当前比特。
    % 例如标签 [0, 1, 1, 0] 对应整数 6，应读取星座表第 7 行。
    for bit_index = first_bit:last_bit
        label_value = 2 * label_value + bits_tx(bit_index); % 二进制标签转为整数。
    end

    constellation_row = label_value + 1;      % MATLAB 的数组行号从 1 开始。
    symbols_tx(symbol_index) = constellation.symbols(constellation_row); % 查表取符号。
end

end
