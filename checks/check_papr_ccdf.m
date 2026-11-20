function results = check_papr_ccdf()
%CHECK_PAPR_CCDF 比较 16×16 APTBM 与 16-QAM OQAM 发射波形的 PAPR-CCDF。
%
% 使用方法：在工程根目录先执行 startup，再执行 check_papr_ccdf。
% 也可以使用 results = check_papr_ccdf(); 获取每帧 PAPR 与 CCDF 统计结果。
%
% 统计位置：RRC 成形后、进入 PA 之前，不经过 PA 或 AWGN 信道。
% 每帧只生成一次比特，分别送入两种调制，使用相同的 RRC 参数。
% 每条链路以自身完整成形波形为观测窗口，包含滤波首尾响应。
% OQAM 还包含 Q 分支半符号延迟，默认两者长度分别为 8037、8039 点。
%
% 论文式 (23) 的离散计算：PAPR_dB = 10*log10(max(|x|^2)/mean(|x|^2))。
% 式 (22) 描述成形前的符号 PAPR，此处按式 (23) 的峰均功率比定义统计波形。
% CCDF(z) = Pr(PAPR_dB > z)，用超过门限 z 的帧数除以总帧数估计。
% 每帧只提供一个 PAPR 样本，不将各个波形采样点作为独立 PAPR 样本。
% 图片保存为 results/papr_ccdf.png，重复运行覆盖同名图片。


%% 1. 设置调制参数和统计帧数

cfg = comparison_config();                  % 读取两种调制共用的配置。
num_frames = 10000;                        % 用于估计 PAPR 分布的随机帧数。
threshold_step_db = 0.05;                  % CCDF 横坐标的门限间隔，单位 dB。
rng(cfg.sim.random_seed);                   % 整次实验只设置一次随机种子。

% 固定为当前工程的 16 阶对比：APTBM 为 16×16，OQAM 使用 16-QAM。
cfg.aptbm.num_sphere_points = 16;           % APTBM 球面状态数 L。
cfg.aptbm.num_phases = 16;                  % APTBM 公共相位状态数 M。
cfg.aptbm.bits_per_block = log2(cfg.aptbm.num_sphere_points) ...
    + log2(cfg.aptbm.num_phases);           % 每个 APTBM 双符号块传输 8 比特。
cfg.oqam.modulation_order = 16;             % OQAM 使用的 QAM 星座点数。
cfg.oqam.bits_per_symbol = log2(cfg.oqam.modulation_order); % 每个复符号传输 4 比特。
cfg.sim.bits_per_frame = cfg.sim.blocks_per_frame * cfg.aptbm.bits_per_block;
cfg.oqam.symbols_per_frame = cfg.sim.bits_per_frame / cfg.oqam.bits_per_symbol;

codebook = build_codebook(cfg);             % 只生成一次 APTBM 码本。
constellation = build_oqam_constellation(cfg); % 只生成一次 QAM 星座表。
rrc_coeffs = design_rrc(cfg);               % 两种方案共用同一组单位能量 RRC 系数。
papr_db_aptbm = zeros(num_frames, 1);       % 每帧 APTBM 波形的 PAPR，单位 dB。
papr_db_oqam = zeros(num_frames, 1);        % 每帧 OQAM 波形的 PAPR，单位 dB。

fprintf('PAPR 统计：%d 帧，每帧 %d 比特，每符号 %d 个采样点。\n', ...
    num_frames, cfg.sim.bits_per_frame, cfg.pulse.samples_per_symbol);


%% 2. 生成多帧波形，并分别计算成形后的 PAPR

for frame_index = 1:num_frames
    bits_tx = generate_bits(cfg);           % 每帧只生成一次，两种调制共用这些比特。

    % 2.1 APTBM 映射、串行化及 RRC 成形。
    blocks_tx = aptbm_map(bits_tx, codebook);
    symbols_tx_aptbm = serialize_blocks(blocks_tx);
    waveform_tx_aptbm = pulse_shape(symbols_tx_aptbm, rrc_coeffs, cfg);

    % 2.2 OQAM 映射及 I/Q 半符号错位成形。
    symbols_tx_oqam = oqam_map(bits_tx, constellation);
    waveform_tx_oqam = oqam_pulse_shape(symbols_tx_oqam, rrc_coeffs, cfg);

    % 2.3 对完整成形波形计算瞬时功率，再求峰值与平均值之比。
    power_aptbm = abs(waveform_tx_aptbm).^2;  % APTBM 每个采样点的瞬时功率。
    power_oqam = abs(waveform_tx_oqam).^2;    % OQAM 每个采样点的瞬时功率。
    peak_power_aptbm = max(power_aptbm);     % 当前帧 APTBM 的峰值功率。
    peak_power_oqam = max(power_oqam);       % 当前帧 OQAM 的峰值功率。
    mean_power_aptbm = mean(power_aptbm);    % 包含滤波尾部的帧平均功率。
    mean_power_oqam = mean(power_oqam);      % 包含半符号延迟及滤波尾部的帧平均功率。

    papr_db_aptbm(frame_index) = 10 * log10(peak_power_aptbm / mean_power_aptbm);
    papr_db_oqam(frame_index) = 10 * log10(peak_power_oqam / mean_power_oqam);

    if mod(frame_index, 100) == 0
        fprintf('已完成 %d/%d 帧。\n', frame_index, num_frames);
    end
end


%% 3. 根据帧 PAPR 样本计算经验 CCDF
% 门限范围覆盖两种调制全部实测 PAPR，向下、向上分别取整到整数 dB。
% 例如 CCDF=0.01 表示有 1% 的帧，其 PAPR 超过当前门限。

min_threshold_db = floor(min([papr_db_aptbm; papr_db_oqam]));
max_threshold_db = ceil(max([papr_db_aptbm; papr_db_oqam]));
threshold_db = min_threshold_db:threshold_step_db:max_threshold_db;
num_thresholds = numel(threshold_db);       % 用于绘图的门限数量。
ccdf_aptbm = zeros(1, num_thresholds);      % APTBM 的门限超越概率。
ccdf_oqam = zeros(1, num_thresholds);       % OQAM 的门限超越概率。

for threshold_index = 1:num_thresholds
    threshold = threshold_db(threshold_index); % 当前 PAPR 门限，单位 dB。
    count_aptbm = sum(papr_db_aptbm > threshold); % APTBM 超过当前门限的帧数。
    count_oqam = sum(papr_db_oqam > threshold);   % OQAM 超过当前门限的帧数。
    ccdf_aptbm(threshold_index) = count_aptbm / num_frames;
    ccdf_oqam(threshold_index) = count_oqam / num_frames;
end


%% 4. 绘制两条 PAPR-CCDF 曲线
% 对数坐标只显示正概率；零概率处停止绘制，不添加替代标点。
% num_frames=10000 时，最低可观测的非零经验 CCDF 为 1/10000。

ccdf_plot_aptbm = ccdf_aptbm;               % 创建绘图副本，保留原统计值。
ccdf_plot_oqam = ccdf_oqam;
ccdf_plot_aptbm(ccdf_aptbm == 0) = NaN;
ccdf_plot_oqam(ccdf_oqam == 0) = NaN;
marker_indices = 1:4:num_thresholds;        % 每隔四个门限显示一个标记，避免过密。

figure_handle = figure('Name', 'PAPR-CCDF Comparison', ...
    'NumberTitle', 'off', 'Color', 'w', 'Position', [100, 100, 900, 600]);
semilogy(threshold_db, ccdf_plot_aptbm, 'b-o', 'LineWidth', 1.5, ...
    'MarkerIndices', marker_indices, 'DisplayName', 'APTBM (16 x 16)');
hold on;
semilogy(threshold_db, ccdf_plot_oqam, 'r--s', 'LineWidth', 1.5, ...
    'MarkerIndices', marker_indices, 'DisplayName', 'OQAM (16-QAM)');
hold off;
grid on;
xlabel('PAPR threshold (dB)');
ylabel('CCDF: Pr(PAPR > threshold)');
title(sprintf('After RRC, before PA: %d frames, %d samples/symbol', ...
    num_frames, cfg.pulse.samples_per_symbol));
legend('Location', 'southwest');
xlim([min_threshold_db, max_threshold_db]);
ylim([0.5 / num_frames, 1]);                % 显示最低非零经验概率，不外推尾部。


%% 5. 保存图片，并返回统计结果

project_root = fileparts(fileparts(mfilename('fullpath'))); % 根据本文件定位工程根目录。
results_dir = fullfile(project_root, 'results');

if ~isfolder(results_dir)
    mkdir(results_dir);                    % 结果目录不存在时创建。
end

image_file = fullfile(results_dir, 'papr_ccdf.png');
print(figure_handle, image_file, '-dpng', '-r150'); % 只保存包含两条曲线的 PNG。
fprintf('PAPR-CCDF 对比图已保存至：\n%s\n', image_file);

results = struct();                        % 返回每帧数据，便于核对 CCDF 计算。
results.cfg = cfg;
results.num_frames = num_frames;
results.papr_db_aptbm = papr_db_aptbm;
results.papr_db_oqam = papr_db_oqam;
results.threshold_db = threshold_db;
results.ccdf_aptbm = ccdf_aptbm;
results.ccdf_oqam = ccdf_oqam;

end
