function results = check_nonlinear_ser_snr()
%CHECK_NONLINEAR_SER_SNR 比较固定 PA 工作点下 APTBM 自重构与 OQAM 的 SER。
%
% 使用方法：先执行 startup，再执行 check_nonlinear_ser_snr。
% 也可以使用 results = check_nonlinear_ser_snr(); 获取累计统计结果。
%
% 调制设置为 16×16 APTBM 与 16-QAM OQAM，每个符号周期均传输 4 比特。
% Rapp 输入功率为 -20 dBm，Saleh 为 -13 dBm，SNR 扫描 0:2:40 dB。
% 每个 SNR 固定仿真 50 帧，每帧只生成一次比特，两种调制及两种 PA 共用。
% SNR 按各自 PA 输出整帧波形的采样点平均功率定义。
%
% SER 按复符号统计：APTBM 联合检测后分别比较块内两个复符号，
% OQAM 比较恢复的 QAM 复符号，分母均为实际发送的复符号总数。
% APTBM 每帧按几何防缠绕流程展开相位，再按式 (18) 独立估计平均块旋转角。
% 不使用相位分支参考、待测发送数据或无噪声接收结果估计相移。
% 输出为 results/nonlinear_ser_snr.png，左 Rapp、右 Saleh。


%% 1. 设置扫描条件，并初始化两种星座及共用 RRC

cfg = comparison_config();                  % 读取公共参数与调制配置。
cfg.rx.reconstruction = 'self';             % APTBM 启用幅度及相位自重构。
cfg.channel.snr_db = 0:2:40;                % 采样点 SNR，单位 dB。
snr_db_list = cfg.channel.snr_db;
model_names = {'rapp', 'saleh'};            % 两个工作点依次对应这两种 PA。
model_titles = {'Rapp', 'Saleh'};
pin_dbm_list = [-20, -13];                  % 分别对应 Rapp、Saleh 的输入平均功率。
frames_per_snr = 50;                       % 每个 SNR 固定仿真 50 帧。
rng(cfg.sim.random_seed);                   % 整次实验只设置一次随机种子。

cfg.aptbm.num_sphere_points = 16;           % 固定为 16×16 APTBM。
cfg.aptbm.num_phases = 16;
cfg.aptbm.bits_per_block = log2(cfg.aptbm.num_sphere_points) ...
    + log2(cfg.aptbm.num_phases);
cfg.oqam.modulation_order = 16;             % OQAM 使用 16-QAM 星座。
cfg.oqam.bits_per_symbol = log2(cfg.oqam.modulation_order);
cfg.sim.bits_per_frame = cfg.sim.blocks_per_frame * cfg.aptbm.bits_per_block;
cfg.oqam.symbols_per_frame = cfg.sim.bits_per_frame / cfg.oqam.bits_per_symbol;

codebook = build_codebook(cfg);
constellation = build_oqam_constellation(cfg);
rrc_coeffs = design_rrc(cfg);

%% 2. 准备输入功率及统计数组
% 每行对应一个 PA 模型，每列对应一个 SNR 点。

num_models = numel(model_names);
num_snr = numel(snr_db_list);
target_input_power = 10.^(pin_dbm_list / 10); % PA 模型的功率数值采用 mW 标度。
reference_input_power = [cfg.pa.rapp.reference_input_power, ...
    cfg.pa.saleh.reference_input_power];
ibo_db_list = 10 * log10(reference_input_power ./ target_input_power);

symbol_errors_aptbm = zeros(num_models, num_snr); % APTBM 累计复符号错误数。
symbol_errors_oqam = zeros(num_models, num_snr);  % OQAM 累计复符号错误数。
total_symbols_aptbm = zeros(num_models, num_snr); % APTBM 累计发送复符号数。
total_symbols_oqam = zeros(num_models, num_snr);  % OQAM 累计发送复符号数。
phase_shift_sum = zeros(num_models, num_snr); % 记录接收端估计的块相移之和。
ser_aptbm = zeros(num_models, num_snr);
ser_oqam = zeros(num_models, num_snr);

fprintf('非线性 SER 扫描：SNR = 0:2:40 dB，每点 %d 帧。\n', frames_per_snr);
fprintf('Rapp Pin = %g dBm，Saleh Pin = %g dBm。\n', pin_dbm_list(1), pin_dbm_list(2));


%% 3. 遍历 SNR，并完成每点 50 帧的收发与统计

for snr_index = 1:num_snr
    snr_db = snr_db_list(snr_index);

    for frame_index = 1:frames_per_snr
        bits_tx = generate_bits(cfg);       % 本帧只生成一次，两条调制链路共用。
        blocks_tx = aptbm_map(bits_tx, codebook);
        symbols_tx_aptbm = serialize_blocks(blocks_tx);
        waveform_tx_aptbm = pulse_shape(symbols_tx_aptbm, rrc_coeffs, cfg);
        symbols_tx_oqam = oqam_map(bits_tx, constellation);
        waveform_tx_oqam = oqam_pulse_shape(symbols_tx_oqam, rrc_coeffs, cfg);

        for model_index = 1:num_models
            cfg.pa.model = model_names{model_index};
            ibo_db = ibo_db_list(model_index); % 将指定 Pin 换算为当前模型的 IBO。

            % 3.1 APTBM：固定输入功率、通过 PA 和 AWGN 信道。
            [pa_in_aptbm, scale_aptbm] = set_input_backoff(waveform_tx_aptbm, ibo_db, cfg);
            pa_out_aptbm = apply_pa(pa_in_aptbm, cfg);
            waveform_rx_aptbm = add_awgn(pa_out_aptbm, snr_db, cfg);

            % 3.2 APTBM：匹配滤波、采样、幅度校准及自重构。
            matched_aptbm = matched_filter(waveform_rx_aptbm, rrc_coeffs);
            symbols_rx_aptbm = sample_symbols(matched_aptbm, rrc_coeffs, cfg);
            calibrated_aptbm = calibrate_gain(symbols_rx_aptbm, scale_aptbm, cfg);
            blocks_rx = deserialize_blocks(calibrated_aptbm);
            [blocks_rec, block_phase_shift] = aptbm_reconstruct(blocks_rx, cfg);
            [~, block_indices] = aptbm_demap(blocks_rec, codebook);
            blocks_detected = codebook.blocks(block_indices, :); % 联合检测后的 a、b 符号。

            % 3.3 OQAM：相同 Pin、相同 SNR，独立生成信道噪声。
            [pa_in_oqam, scale_oqam] = set_input_backoff(waveform_tx_oqam, ibo_db, cfg);
            pa_out_oqam = apply_pa(pa_in_oqam, cfg);
            waveform_rx_oqam = add_awgn(pa_out_oqam, snr_db, cfg);
            matched_oqam = matched_filter(waveform_rx_oqam, rrc_coeffs);
            symbols_rx_oqam = oqam_sample_symbols(matched_oqam, rrc_coeffs, cfg);
            calibrated_oqam = calibrate_gain(symbols_rx_oqam, scale_oqam, cfg);
            [~, symbol_indices] = oqam_demap(calibrated_oqam, constellation);
            symbols_detected = constellation.symbols(symbol_indices);

            % 3.4 核对实际 PA 输入平均功率，并累计复符号错误数。
            power_ratio_aptbm = mean(abs(pa_in_aptbm).^2) / target_input_power(model_index);
            power_ratio_oqam = mean(abs(pa_in_oqam).^2) / target_input_power(model_index);
            assert(abs(power_ratio_aptbm - 1) < 1e-10 ...
                && abs(power_ratio_oqam - 1) < 1e-10, ...
                'check_nonlinear_ser_snr:InputPower', '实际 PA 输入平均功率与指定 Pin 不一致。');

            % 检测值和发送值均来自同一份星座表，可以直接比较复数值是否相等。
            symbol_errors_aptbm(model_index, snr_index) = ...
                symbol_errors_aptbm(model_index, snr_index) ...
                + sum(blocks_detected(:) ~= blocks_tx(:));
            symbol_errors_oqam(model_index, snr_index) = ...
                symbol_errors_oqam(model_index, snr_index) ...
                + sum(symbols_detected ~= symbols_tx_oqam);
            total_symbols_aptbm(model_index, snr_index) = ...
                total_symbols_aptbm(model_index, snr_index) + numel(blocks_tx);
            total_symbols_oqam(model_index, snr_index) = ...
                total_symbols_oqam(model_index, snr_index) + numel(symbols_tx_oqam);
            phase_shift_sum(model_index, snr_index) = ...
                phase_shift_sum(model_index, snr_index) + block_phase_shift;
        end
    end

    for model_index = 1:num_models
        ser_aptbm(model_index, snr_index) = symbol_errors_aptbm(model_index, snr_index) ...
            / total_symbols_aptbm(model_index, snr_index);
        ser_oqam(model_index, snr_index) = symbol_errors_oqam(model_index, snr_index) ...
            / total_symbols_oqam(model_index, snr_index);
        fprintf('%s：SNR = %2g dB，APTBM SER = %.6g，OQAM SER = %.6g\n', ...
            model_titles{model_index}, snr_db, ...
            ser_aptbm(model_index, snr_index), ser_oqam(model_index, snr_index));
    end
end


%% 4. 绘制左 Rapp、右 Saleh 的 SER-SNR 对比图
% 每条曲线在首次零误码处停止绘制，统计结果仍保留全部 SNR 的实测值。

figure_handle = figure('Name', 'Nonlinear SER-SNR Comparison', ...
    'NumberTitle', 'off', 'Color', 'w', 'Position', [100, 100, 1200, 500]);

for model_index = 1:num_models
    ser_plot_aptbm = ser_aptbm(model_index, :);
    ser_plot_oqam = ser_oqam(model_index, :);
    first_zero_aptbm = find(ser_plot_aptbm == 0, 1);
    first_zero_oqam = find(ser_plot_oqam == 0, 1);

    if ~isempty(first_zero_aptbm)
        ser_plot_aptbm(first_zero_aptbm:end) = NaN;
    end

    if ~isempty(first_zero_oqam)
        ser_plot_oqam(first_zero_oqam:end) = NaN;
    end

    subplot(1, 2, model_index);
    semilogy(snr_db_list, ser_plot_aptbm, 'b-o', 'LineWidth', 1.5, ...
        'DisplayName', 'APTBM (16 x 16, reconstructed)');
    hold on;
    semilogy(snr_db_list, ser_plot_oqam, 'r:s', 'LineWidth', 1.5, ...
        'DisplayName', 'OQAM (16-QAM)');
    hold off;
    grid on;
    xlabel('PA-output sample SNR (dB)');
    ylabel('Symbol error rate (SER)');
    title(sprintf('%s PA: Pin = %g dBm', model_titles{model_index}, pin_dbm_list(model_index)));
    legend('Location', 'southwest');
    xlim([snr_db_list(1), snr_db_list(end)]);
    ylim([0.5 / max(total_symbols_aptbm(:)), 1]); % 两幅图采用相同的纵轴范围。
end

sgtitle(sprintf('16-order comparison: %d frames/SNR, per-frame phase reconstruction', ...
    frames_per_snr));


%% 5. 保存整张图片，并返回统计结果

project_root = fileparts(fileparts(mfilename('fullpath')));
results_dir = fullfile(project_root, 'results');

if ~isfolder(results_dir)
    mkdir(results_dir);
end

image_file = fullfile(results_dir, 'nonlinear_ser_snr.png');
print(figure_handle, image_file, '-dpng', '-r150');
fprintf('非线性 SER-SNR 对比图已保存至：\n%s\n', image_file);

results = struct();
results.cfg = cfg;
results.model_names = model_names;
results.pin_dbm = pin_dbm_list;
results.ibo_db = ibo_db_list;
results.snr_db = snr_db_list;
results.frames_per_snr = frames_per_snr;
results.mean_block_phase_shift = phase_shift_sum / frames_per_snr;
results.symbol_errors_aptbm = symbol_errors_aptbm;
results.symbol_errors_oqam = symbol_errors_oqam;
results.total_symbols_aptbm = total_symbols_aptbm;
results.total_symbols_oqam = total_symbols_oqam;
results.ser_aptbm = ser_aptbm;
results.ser_oqam = ser_oqam;

end
