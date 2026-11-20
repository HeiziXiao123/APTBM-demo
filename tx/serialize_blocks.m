function symbols_tx = serialize_blocks(blocks_tx)
%SERIALIZE_BLOCKS 将 APTBM 符号块按时间顺序串行化。
%
% 使用方法：symbols_tx = serialize_blocks(blocks_tx);
%
% 输入：blocks_tx 为 aptbm_map.m 输出的 N 行 2 列复数矩阵。
%       每行存放一个符号块 [x_a, x_b]。
% 输出：symbols_tx 为 2*N 行 1 列的复符号序列。
%       排列顺序为 [x_a1; x_b1; x_a2; x_b2; ...]。
%
% 串行化只改变符号的排列方式，保留每个符号的实部和虚部。


%% 1. 检查输入矩阵的尺寸

if ~ismatrix(blocks_tx) || size(blocks_tx, 2) ~= 2
    error('serialize_blocks:InputShape', '输入必须为 N 行 2 列的符号块矩阵。');
end


%% 2. 预先分配串行符号列向量

num_blocks = size(blocks_tx, 1);               % 读取输入的符号块数 N。
num_symbols = 2 * num_blocks;                 % 每个块包含两个符号，共有 2*N 个符号。
symbols_tx = complex(zeros(num_symbols, 1));   % 为串行复符号序列预先分配空间。


%% 3. 按块顺序依次写入两个符号

for block_index = 1:num_blocks
    first_symbol = 2 * block_index - 1;        % 当前块的 x_a 对应奇数位置。
    second_symbol = 2 * block_index;           % 当前块的 x_b 对应偶数位置。

    symbols_tx(first_symbol) = blocks_tx(block_index, 1);  % 先写入 x_a。
    symbols_tx(second_symbol) = blocks_tx(block_index, 2); % 再写入 x_b。
end

end
