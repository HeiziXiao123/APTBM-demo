function results = check_linear_ber_snr()
%CHECK_LINEAR_BER_SNR 对比线性 PA 下 APTBM 与 OQAM 的 BER-SNR 曲线。
%
% 使用方法：在工程根目录先执行 startup，再执行 check_linear_ber_snr。
% 也可以使用 results = check_linear_ber_snr(); 获取本次统计结果。
%
% 调制设置：APTBM 使用 16 个公共相位和 16 个球面点，OQAM 使用 16-QAM。
% 两种方案每个符号周期均传输 4 比特，平均符号能量沿用统一配置。
% 每个 SNR 固定仿真 50 帧，每帧只生成一次比特，再分别送入两条链路。
% 线性条件下 APTBM 使用重构旁路；两条链路分别生成独立的 AWGN。
% SNR 定义为匹配滤波前、PA 输出端的采样点信噪比，不是 Eb/N0。
% SNR 扫描 0:1:20 dB，各曲线在首次零误码处停止绘制，不添加零误码标记。
% 图片保存为 results/linear_ber_snr.png，重复运行覆盖同名图片。


%% 1. 设置线性对比条件

cfg = comparison_config();                  % 读取公共参数和两种调制的配置。
cfg.pa.model = 'linear';                    % 使用理想单位增益 PA。
cfg.rx.reconstruction = 'none';             % 线性对比不使用非线性自重构。
frames_per_snr = 50;                       % 每个 SNR 固定运行 50 帧，不提前停止。
ibo_db = 6;                                % 两条链路使用相同 IBO，并在接收端校准。
cfg.channel.snr_db = 0:1:20;                % 本检查使用 1 dB 的 SNR 扫描间隔。
snr_db_list = cfg.channel.snr_db;           % 读取本次扫描的 21 个 SNR 点。
rng(cfg.sim.random_seed);                   % 整次实验只设置一次随机种子。

% 本检查固定为 16 阶设置，并同步更新与比特分组有关的派生参数。
cfg.aptbm.num_sphere_points = 16;           % APTBM 球面状态数 L。
cfg.aptbm.num_phases = 16;                  % APTBM 公共相位状态数 M。
cfg.aptbm.bits_per_block = log2(cfg.aptbm.num_sphere_points) ...
    + log2(cfg.aptbm.num_phases);           % 每个双符号块传输 8 比特。
cfg.oqam.modulation_order = 16;             % OQAM 使用的 QAM 星座点数。
cfg.oqam.bits_per_symbol = log2(cfg.oqam.modulation_order); % 每个复符号传输 4 比特。
cfg.sim.bits_per_frame = cfg.sim.blocks_per_frame * cfg.aptbm.bits_per_block;
cfg.oqam.symbols_per_frame = cfg.sim.bits_per_frame / cfg.oqam.bits_per_symbol;

codebook = build_codebook(cfg);             % 只生成一次 APTBM 码本。
constellation = build_oqam_constellation(cfg); % 只生成一次 QAM 星座与标签。
rrc_coeffs = design_rrc(cfg);               % 两种调制共用同一组单位能量 RRC 系数。


%% 2. 预先分配各 SNR 下的统计数组

num_snr = numel(snr_db_list);               % 待仿真的 SNR 点数。
bit_errors_aptbm = zeros(1, num_snr);        % APTBM 在各 SNR 下的累计误比特数。
bit_errors_oqam = zeros(1, num_snr);         % OQAM 在各 SNR 下的累计误比特数。
total_bits_aptbm = zeros(1, num_snr);        % APTBM 在各 SNR 下的累计发送比特数。
total_bits_oqam = zeros(1, num_snr);         % OQAM 在各 SNR 下的累计发送比特数。
ber_aptbm = zeros(1, num_snr);               % APTBM 的 BER 统计结果。
ber_oqam = zeros(1, num_snr);                % OQAM 的 BER 统计结果。

fprintf('线性 PA 对比：每个 SNR 仿真 %d 帧，每帧 %d 比特。\n', ...
    frames_per_snr, cfg.sim.bits_per_frame);


%% 3. 遍历 SNR，每个 SNR 下仿真 50 帧

for snr_index = 1:num_snr
    snr_db = snr_db_list(snr_index);         % 读取当前信噪比。

    for frame_index = 1:frames_per_snr
        bits_tx = generate_bits(cfg);       % 本帧只生成一次比特，两种方案共用。

        % 3.1 APTBM：映射、成形、线性 PA 和加噪。
        blocks_tx = aptbm_map(bits_tx, codebook);
        symbols_tx_aptbm = serialize_blocks(blocks_tx);
        waveform_tx_aptbm = pulse_shape(symbols_tx_aptbm, rrc_coeffs, cfg);
        [pa_in_aptbm, scale_aptbm] = set_input_backoff(waveform_tx_aptbm, ibo_db, cfg);
        pa_out_aptbm = apply_pa(pa_in_aptbm, cfg);
        waveform_rx_aptbm = add_awgn(pa_out_aptbm, snr_db, cfg);

        % 3.2 APTBM：匹配滤波、采样、校准、块重组和解映射。
        matched_aptbm = matched_filter(waveform_rx_aptbm, rrc_coeffs);
        symbols_rx_aptbm = sample_symbols(matched_aptbm, rrc_coeffs, cfg);
        calibrated_aptbm = calibrate_gain(symbols_rx_aptbm, scale_aptbm, cfg);
        blocks_rx = deserialize_blocks(calibrated_aptbm);
        blocks_rec = aptbm_reconstruct(blocks_rx, cfg); % none 模式保留原接收块。
        bits_rx_aptbm = aptbm_demap(blocks_rec, codebook);

        % 3.3 OQAM：使用同一帧比特，完成映射、错位成形、线性 PA 和加噪。
        symbols_tx_oqam = oqam_map(bits_tx, constellation);
        waveform_tx_oqam = oqam_pulse_shape(symbols_tx_oqam, rrc_coeffs, cfg);
        [pa_in_oqam, scale_oqam] = set_input_backoff(waveform_tx_oqam, ibo_db, cfg);
        pa_out_oqam = apply_pa(pa_in_oqam, cfg);
        waveform_rx_oqam = add_awgn(pa_out_oqam, snr_db, cfg);

        % 3.4 OQAM：匹配滤波、I/Q 分时采样、幅度校准和解映射。
        matched_oqam = matched_filter(waveform_rx_oqam, rrc_coeffs);
        symbols_rx_oqam = oqam_sample_symbols(matched_oqam, rrc_coeffs, cfg);
        calibrated_oqam = calibrate_gain(symbols_rx_oqam, scale_oqam, cfg);
        bits_rx_oqam = oqam_demap(calibrated_oqam, constellation);

        % 3.5 检查比特尺寸，并累计本帧的误比特数和总比特数。
        assert(isequal(size(bits_rx_aptbm), size(bits_tx)), ...
            'check_linear_ber_snr:APTBMBitCount', 'APTBM 收发比特尺寸不一致。');
        assert(isequal(size(bits_rx_oqam), size(bits_tx)), ...
            'check_linear_ber_snr:OQAMBitCount', 'OQAM 收发比特尺寸不一致。');

        bit_errors_aptbm(snr_index) = bit_errors_aptbm(snr_index) ...
            + sum(bits_rx_aptbm ~= bits_tx);
        bit_errors_oqam(snr_index) = bit_errors_oqam(snr_index) ...
            + sum(bits_rx_oqam ~= bits_tx);
        total_bits_aptbm(snr_index) = total_bits_aptbm(snr_index) + numel(bits_tx);
        total_bits_oqam(snr_index) = total_bits_oqam(snr_index) + numel(bits_tx);
    end

    % 当前 SNR 的全部 50 帧完成后，再由累计数量计算 BER。
    ber_aptbm(snr_index) = bit_errors_aptbm(snr_index) / total_bits_aptbm(snr_index);
    ber_oqam(snr_index) = bit_errors_oqam(snr_index) / total_bits_oqam(snr_index);

    fprintf('SNR = %2g dB，帧数 = %d，总比特数 = %d\n', ...
        snr_db, frames_per_snr, total_bits_aptbm(snr_index));
    fprintf('  APTBM：误比特 %d，BER = %.6g；OQAM：误比特 %d，BER = %.6g\n', ...
        bit_errors_aptbm(snr_index), ber_aptbm(snr_index), ...
        bit_errors_oqam(snr_index), ber_oqam(snr_index));
end


%% 4. 绘制 BER-SNR 对比曲线
% 每条曲线只绘制首次零误码之前的非零 BER 点，不再添加零误码标记。
% 全部 SNR 的仿真统计仍保留，只在绘图副本中用 NaN 隐藏后续点。

ber_plot_aptbm = ber_aptbm;                 % 创建绘图副本，不改变统计值。
ber_plot_oqam = ber_oqam;
first_zero_aptbm = find(ber_aptbm == 0, 1);  % 查找 APTBM 首次零误码的位置。
first_zero_oqam = find(ber_oqam == 0, 1);    % 查找 OQAM 首次零误码的位置。

if ~isempty(first_zero_aptbm)
    ber_plot_aptbm(first_zero_aptbm:end) = NaN; % APTBM 从首次零误码处停止绘制。
end

if ~isempty(first_zero_oqam)
    ber_plot_oqam(first_zero_oqam:end) = NaN; % OQAM 从首次零误码处停止绘制。
end

figure_handle = figure('Name', 'Linear BER-SNR Comparison', ...
    'NumberTitle', 'off', 'Color', 'w', 'Position', [100, 100, 900, 600]);
semilogy(snr_db_list, ber_plot_aptbm, 'b-o', 'LineWidth', 1.5, ...
    'DisplayName', 'APTBM (16 x 16, no reconstruction)');
hold on;
semilogy(snr_db_list, ber_plot_oqam, 'r-s', 'LineWidth', 1.5, ...
    'DisplayName', 'OQAM (16-QAM, Gray)');
hold off;
grid on;
xlabel('PA-output sample SNR (dB)');
ylabel('Bit error rate (BER)');
title(sprintf('Linear PA: %d frames/SNR, %d bits/frame', ...
    frames_per_snr, cfg.sim.bits_per_frame));
legend('Location', 'southwest');
xlim([min(snr_db_list) - 1, max(snr_db_list) + 1]); % 横轴两端留白，避免标记被截断。
ylim([0.5 / max(total_bits_aptbm), 1]);      % 保留可显示单个误比特 BER 的纵轴范围。


%% 5. 保存图片，并返回累计统计结果

project_root = fileparts(fileparts(mfilename('fullpath'))); % 根据本文件定位工程根目录。
results_dir = fullfile(project_root, 'results');

if ~isfolder(results_dir)
    mkdir(results_dir);                    % 结果目录不存在时创建。
end

image_file = fullfile(results_dir, 'linear_ber_snr.png');
print(figure_handle, image_file, '-dpng', '-r150'); % 只保存当前 BER-SNR 图片。
fprintf('BER-SNR 对比图已保存至：\n%s\n', image_file);

results = struct();                        % 返回结果，便于在 MATLAB 工作区查看。
results.cfg = cfg;
results.snr_db = snr_db_list;
results.frames_per_snr = frames_per_snr;
results.ibo_db = ibo_db;
results.bit_errors_aptbm = bit_errors_aptbm;
results.bit_errors_oqam = bit_errors_oqam;
results.total_bits_aptbm = total_bits_aptbm;
results.total_bits_oqam = total_bits_oqam;
results.ber_aptbm = ber_aptbm;
results.ber_oqam = ber_oqam;

end
