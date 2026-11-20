function [bits_rx, symbol_indices] = oqam_demap(symbols_rx, constellation)
%OQAM_DEMAP 通过最小欧氏距离检测 QAM 星座点，并恢复 OQAM 比特。
%
% 使用方法：
%   bits_rx = oqam_demap(symbols_rx, constellation);
%   [bits_rx, symbol_indices] = oqam_demap(symbols_rx, constellation);
%
% 输入：
%   symbols_rx     N 行 1 列的接收复符号序列。
%                  I/Q 分支应已按各自时刻采样、对齐，并完成幅度校准。
%   constellation  由 build_oqam_constellation.m 生成的星座结构体。
%                  应与发射端使用同一份星座表。
%
% 输出：
%   bits_rx         N*K 行 1 列的数值比特向量，顺序与发射端一致。
%   symbol_indices  N 行 1 列，记录各接收符号选中的星座表行号，从 1 开始。
%
% 每个候选点的距离平方为 abs(接收符号 - 候选符号)^2。
% 选出距离最近的星座点，再直接读取该行标签，无需另外转换 Gray 码。
% 本函数只完成硬判决检测和比特恢复。


%% 1. 检查接收符号，并读取星座表

if ~iscolumn(symbols_rx) || isempty(symbols_rx)
    error('oqam_demap:InputShape', '接收符号必须为非空的列向量。');
end

if ~all(isfinite(symbols_rx))
    error('oqam_demap:InputValue', '接收符号必须只包含有限数值。');
end

candidate_symbols = constellation.symbols;   % 读取所有合法的候选复符号。
bit_labels = constellation.bit_labels;       % 读取与候选符号逐行对应的标签。
bits_per_symbol = constellation.bits_per_symbol; % 每个符号对应的比特数 K。
num_candidates = numel(candidate_symbols);   % 星座表中候选点的数量。

if ~iscolumn(candidate_symbols) || isempty(candidate_symbols) ...
        || ~isequal(size(bit_labels), [num_candidates, bits_per_symbol])
    error('oqam_demap:ConstellationShape', '候选符号和比特标签的尺寸不一致。');
end


%% 2. 预先分配输出和距离数组

num_symbols = numel(symbols_rx);             % 读取本帧接收符号数 N。
bits_rx = zeros(num_symbols * bits_per_symbol, 1); % 按符号顺序存放恢复的比特。
symbol_indices = zeros(num_symbols, 1);      % 保存各符号对应的星座表行号。
distance_squared = zeros(num_candidates, 1); % 保存当前接收符号到各候选点的距离平方。


%% 3. 逐符号检测最近的星座点，并恢复比特标签

for symbol_index = 1:num_symbols
    for candidate_index = 1:num_candidates
        symbol_error = symbols_rx(symbol_index) - candidate_symbols(candidate_index);
        distance_squared(candidate_index) = abs(symbol_error)^2; % 计算欧氏距离平方。
    end

    % 距离平方与距离的大小顺序相同，直接比较平方值即可。
    % min 的第二个输出为最小值行号，距离相同时选择最前面的候选点。
    [~, constellation_row] = min(distance_squared);
    symbol_indices(symbol_index) = constellation_row; % 保存当前符号的判决结果。

    first_bit = (symbol_index - 1) * bits_per_symbol + 1; % 本符号标签的起始位置。
    last_bit = symbol_index * bits_per_symbol;          % 本符号标签的结束位置。

    % 用 .' 将一行标签转为列向量，保留每组标签高位在前的排列顺序。
    bits_rx(first_bit:last_bit) = bit_labels(constellation_row, :).';
end

end
