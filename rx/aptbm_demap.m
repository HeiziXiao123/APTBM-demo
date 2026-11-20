function [bits_rx, block_indices] = aptbm_demap(blocks_rx, codebook)
%APTBM_DEMAP 通过最小欧氏距离检测 APTBM 候选块，并恢复比特。
%
% 使用方法：
%   bits_rx = aptbm_demap(blocks_rx, codebook);
%   [bits_rx, block_indices] = aptbm_demap(blocks_rx, codebook);
%
% 输入：
%   blocks_rx  N 行 2 列的接收复符号块，每行为 [x_a, x_b]。
%              输入应完成幅度校准，也可以使用后续重构模块输出的符号块。
%   codebook   由 build_codebook.m 生成的码本，与发射端使用相同的配置。
%
% 输出：
%   bits_rx        N*K 行 1 列的数值比特向量，排列顺序与发射比特一致。
%   block_indices  N 行 1 列，记录各接收块选中的候选块行号，从 1 开始。
%
% 每个候选块的距离平方为 abs(y_a-x_a)^2 + abs(y_b-x_b)^2。
% 选出距离最小的完整双符号块，再读取该行的比特标签进行解映射。
% 距离平方与距离的大小顺序相同，因此直接比较平方值即可。


%% 1. 检查接收块，并读取码本

if ~ismatrix(blocks_rx) || size(blocks_rx, 2) ~= 2 || isempty(blocks_rx)
    error('aptbm_demap:InputShape', '接收块必须为非空的 N 行 2 列矩阵。');
end

if ~all(isfinite(blocks_rx(:)))
    error('aptbm_demap:InputValue', '接收块必须只包含有限数值。');
end

candidate_blocks = codebook.blocks;           % 读取所有合法的候选双符号块。
bit_labels = codebook.bit_labels;             % 读取与候选块逐行对应的比特标签。
bits_per_block = codebook.bits_per_block;     % 每个块对应的比特数 K。
num_candidates = size(candidate_blocks, 1);  % 码本中候选块的总数量。

if ~ismatrix(candidate_blocks) || size(candidate_blocks, 2) ~= 2 ...
        || isempty(candidate_blocks) ...
        || ~isequal(size(bit_labels), [num_candidates, bits_per_block])
    error('aptbm_demap:CodebookShape', '候选块和比特标签的尺寸不一致。');
end


%% 2. 预先分配输出和距离数组

num_blocks = size(blocks_rx, 1);              % 读取本帧接收块数 N。
bits_rx = zeros(num_blocks * bits_per_block, 1); % 每个块的 K 位标签依次写入此列向量。
block_indices = zeros(num_blocks, 1);         % 保存每个接收块的检测结果。
distance_squared = zeros(num_candidates, 1);  % 保存当前接收块到各候选块的距离平方。


%% 3. 逐块比较两个复符号的联合距离，并恢复标签

for block_index = 1:num_blocks
    for candidate_index = 1:num_candidates
        error_a = blocks_rx(block_index, 1) - candidate_blocks(candidate_index, 1);
        error_b = blocks_rx(block_index, 2) - candidate_blocks(candidate_index, 2);
        distance_squared(candidate_index) = abs(error_a)^2 + abs(error_b)^2;
    end

    % min 的第二个输出为最小值的行号，距离相同时取最前面的候选块。
    [~, codebook_row] = min(distance_squared); % 得到距离最近的合法双符号块。
    block_indices(block_index) = codebook_row; % 保存本块对应的码本行号。

    first_bit = (block_index - 1) * bits_per_block + 1; % 本块标签的起始位置。
    last_bit = block_index * bits_per_block;          % 本块标签的结束位置。

    % 用 .' 将该行标签转为列向量，按与发射端一致的块顺序写回比特。
    bits_rx(first_bit:last_bit) = bit_labels(codebook_row, :).';
end

end
