function bits_tx = generate_bits(cfg)
%GENERATE_BITS 生成一帧用于 APTBM 调制的随机比特。
%
% 使用方法：bits_tx = generate_bits(cfg);
%
% 输入：cfg 为 default_config.m 返回的参数结构体。
% 输出：bits_tx 为只包含数值 0 和 1 的 double 类型列向量。
% 长度：每帧块数乘以每块比特数，保证能够按完整的 APTBM 块分组。
% 排列：前 K 位属于第一个块，接下来的 K 位属于第二个块，以此类推。
%
% 随机种子由仿真入口统一设置，本函数每次调用时继续生成新的随机比特。


%% 1. 计算一帧所需的比特数

blocks_per_frame = cfg.sim.blocks_per_frame;   % 读取每帧的 APTBM 块数。
bits_per_block = cfg.aptbm.bits_per_block;     % 读取每个 APTBM 块承载的比特数 K。
bits_per_frame = blocks_per_frame * bits_per_block; % 计算一帧的总比特数。


%% 2. 生成随机比特列向量

bits_tx = randi([0, 1], bits_per_frame, 1);     % 等概率生成 0 和 1，每行存放一个比特。

end
