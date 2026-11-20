function check_linear_link()
%CHECK_LINEAR_LINK 检查理想线性 PA、无噪声条件下的完整比特收发链路。
%
% 使用方法：在工程根目录先执行 startup，再执行 check_linear_link。
% 生成一帧随机比特，依次通过现有收发模块，最后比较发送与接收比特。
% 重构入口使用 none 模式，直接解映射校准后的接收块，作为自重构的基础对照。
% 本检查只显示比特数量和误码结果。


%% 1. 设置本次检查条件

cfg = default_config();                       % 读取默认参数，修改只在本函数内生效。
cfg.pa.model = 'linear';                      % 使用理想单位增益 PA。
cfg.rx.reconstruction = 'none';               % 基础链路检查使用重构旁路。
ibo_db = 6;                                  % 仍设置 IBO，以检查幅度缩放和校准的衔接。
snr_db = Inf;                                % 关闭加性噪声，检查基础链路。
rng(cfg.sim.random_seed);                     % 统一设置本次随机种子。

codebook = build_codebook(cfg);               % 生成收发双方共用的码本。
rrc_coeffs = design_rrc(cfg);                 % 生成收发双方共用的 RRC 系数。


%% 2. 生成比特并完成发射端处理

bits_tx = generate_bits(cfg);                 % 生成一帧随机比特。
blocks_tx = aptbm_map(bits_tx, codebook);      % 将比特映射为 APTBM 双符号块。
symbols_tx = serialize_blocks(blocks_tx);     % 将符号块按时间顺序串行化。
waveform_tx = pulse_shape(symbols_tx, rrc_coeffs, cfg); % 完成插零上采样和脉冲成形。

[waveform_pa_in, amplitude_scale] = set_input_backoff(waveform_tx, ibo_db, cfg);
waveform_pa_out = apply_pa(waveform_pa_in, cfg); % 通过本次选择的理想 PA。
waveform_rx = add_awgn(waveform_pa_out, snr_db, cfg); % 本次 SNR 为 Inf，保留原波形。


%% 3. 完成接收端处理并恢复比特

waveform_matched = matched_filter(waveform_rx, rrc_coeffs); % 接收端匹配滤波。
symbols_rx = sample_symbols(waveform_matched, rrc_coeffs, cfg); % 补偿总延迟并采样。
symbols_calibrated = calibrate_gain(symbols_rx, amplitude_scale, cfg); % 恢复幅度标度。
blocks_rx = deserialize_blocks(symbols_calibrated); % 将连续两个符号重新组成一块。
blocks_rec = aptbm_reconstruct(blocks_rx, cfg); % 本次为 none，直接返回接收块。
bits_rx = aptbm_demap(blocks_rec, codebook);   % 联合检测双符号块并恢复比特。


%% 4. 比较发送和接收比特

assert(isequal(size(bits_rx), size(bits_tx)), ...
    'check_linear_link:BitCount', '发送和接收比特的尺寸不一致。');

num_bit_errors = sum(bits_rx ~= bits_tx);      % 统计一帧中发生错误的比特数量。
ber = num_bit_errors / numel(bits_tx);         % 计算本帧误比特率 BER。

fprintf('发送比特数：%d\n', numel(bits_tx));
fprintf('接收比特数：%d\n', numel(bits_rx));
fprintf('误比特数：%d，BER = %.6g\n', num_bit_errors, ber);

assert(num_bit_errors == 0, ...
    'check_linear_link:BitErrors', '线性无噪声链路存在误比特，请检查收发模块的衔接。');

fprintf('线性无噪声比特收发链路检查通过。\n');

end
