function blocks_rx = deserialize_blocks(symbols_calibrated)
%DESERIALIZE_BLOCKS 将校准后的符号序列重新组成 APTBM 双符号块。
%
% 使用方法：blocks_rx = deserialize_blocks(symbols_calibrated);
%
% 输入：symbols_calibrated 为 calibrate_gain.m 输出的复符号列向量。
%       排列顺序为 [x_a1; x_b1; x_a2; x_b2; ...]，符号总数必须为偶数。
% 输出：blocks_rx 为 N 行 2 列的复数矩阵，每行存放一个接收块 [x_a, x_b]。
%       默认将 2000 个连续符号恢复为 1000 个 APTBM 块。
%
% 本函数与 serialize_blocks.m 的排列顺序对应，只整理数据，不改变复符号值。
% 假设理想同步已确定块边界，第一个输入符号属于第一个块的 x_a。


%% 1. 检查输入符号序列

if ~iscolumn(symbols_calibrated) || isempty(symbols_calibrated)
    error('deserialize_blocks:InputShape', '校准后的符号必须为非空列向量。');
end

num_symbols = numel(symbols_calibrated);      % 读取输入的复符号总数。

if mod(num_symbols, 2) ~= 0
    error('deserialize_blocks:SymbolCount', '符号总数必须为偶数，每两个符号组成一块。');
end


%% 2. 预先分配接收符号块矩阵

num_blocks = num_symbols / 2;                % 每两个连续符号组成一个 APTBM 块。
blocks_rx = complex(zeros(num_blocks, 2));    % 每行预留两个复符号的位置。


%% 3. 按时间顺序将相邻两个符号写入同一行

for block_index = 1:num_blocks
    first_symbol = 2 * block_index - 1;       % 当前块的 x_a 位于输入序列的奇数位置。
    second_symbol = 2 * block_index;          % 当前块的 x_b 位于输入序列的偶数位置。

    blocks_rx(block_index, 1) = symbols_calibrated(first_symbol);  % 第一列存放 x_a。
    blocks_rx(block_index, 2) = symbols_calibrated(second_symbol); % 第二列存放 x_b。
end

end
