function blocks_tx = aptbm_map(bits_tx, codebook)
%APTBM_MAP 将一帧比特映射为 APTBM 符号块。
%
% 使用方法：blocks_tx = aptbm_map(bits_tx, codebook);
%
% 输入：
%   bits_tx   由 generate_bits.m 生成的比特列向量，只包含数值 0 和 1。
%   codebook  由 build_codebook.m 生成的码本结构体。
%
% 输出：
%   blocks_tx 为 N 行 2 列的复数矩阵，每行是一个符号块 [x_a, x_b]。
%   N 为输入比特总数除以每块比特数 K，前 K 位对应第一行，以此类推。
%
% 本函数沿用现有码本的自然二进制标签，高位在左。
% 前 log2(M) 位选择公共相位，后 log2(L) 位选择球面点。
% 标签对应的十进制整数加 1，就是该符号块在码本中的行号。


%% 1. 读取每块比特数，并检查输入比特

bits_per_block = codebook.bits_per_block;      % 从码本读取每个符号块的比特数 K。
num_bits = numel(bits_tx);                     % 统计输入的一帧比特总数。

if ~iscolumn(bits_tx)
    error('aptbm_map:InputShape', '输入比特必须为列向量。');
end

if ~all(bits_tx == 0 | bits_tx == 1)
    error('aptbm_map:InvalidBits', '输入比特只能包含数值 0 和 1。');
end

if mod(num_bits, bits_per_block) ~= 0
    error('aptbm_map:BitCount', '输入比特总数必须为每块比特数 K 的整数倍。');
end


%% 2. 预先分配输出符号块矩阵

num_blocks = num_bits / bits_per_block;        % 计算这一帧包含的符号块数 N。
blocks_tx = complex(zeros(num_blocks, 2));      % 每行预留两个复符号的位置。


%% 3. 逐块读取比特，并查找对应的候选符号块

for block_index = 1:num_blocks
    first_bit = (block_index - 1) * bits_per_block + 1; % 当前块第一位比特的位置。
    last_bit = block_index * bits_per_block;          % 当前块最后一位比特的位置。

    label_value = 0;                           % 初始化当前标签的十进制整数值。

    % 从高位到低位逐位读取，每次将已有整数乘以 2，再加上当前比特。
    % 例如标签 [1, 0, 1] 的整数值依次为 1、2、5。
    for bit_index = first_bit:last_bit
        label_value = 2 * label_value + bits_tx(bit_index); % 将二进制标签转为整数。
    end

    codebook_row = label_value + 1;            % MATLAB 的数组行号从 1 开始。
    blocks_tx(block_index, :) = codebook.blocks(codebook_row, :); % 取出 [x_a, x_b]。
end

end
