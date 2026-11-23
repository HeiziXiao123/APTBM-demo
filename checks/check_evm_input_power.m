function results = check_evm_input_power()
%CHECK_EVM_INPUT_POWER 比较 16 阶 OQAM 与 APTBM 自重构后的 EVM-输入功率曲线。
%
% 使用方法：在工程根目录先执行 startup，再执行 check_evm_input_power。
% 也可以使用 results = check_evm_input_power(); 获取累计统计结果。
%
% 从左到右为 Rapp、Saleh、MP，每图显示 OQAM 和 APTBM 自重构两条曲线。
% 输入平均功率 Pin 扫描 -35:1:-5 dBm，SNR=Inf，不加入 AWGN。
% APTBM 使用 16×16 码本，OQAM 使用 16-QAM，两者每符号周期均传输 4 比特。
%
% 按论文式 (27)-(28)：EVM_dB = 10*log10(累计误差能量/累计发送符号能量)。
% abs(y-x)^2 等于 I/Q 两维误差平方之和，APTBM 每块的两个符号均计入。
% 误差使用校准后的连续接收符号；APTBM 还需完成自重构，不做硬判决。
% 校准只补偿 IBO 缩放及 PA 小信号增益，不额外拟合幅度或公共相位。
% MP 的 OQAM 接收端先校准匹配滤波后的连续复波形，再进行 I/Q 分时采样。
% 静态复增益校准后，MP 的频率相关记忆失真及初始瞬态继续保留。
% Pin 按进入 apply_pa 的完整波形定义，MP 内部限幅由 cfg.pa.mp.clip_input 控制。
% 无噪声条件下，有限长 RRC 的残余码间干扰和重构估计误差仍会保留。
% 每个模型、每个功率点先汇总全部 100 帧，再按式 (18) 估计一次平均块旋转角。
% 相位按角平分线局部坐标系展开，不使用相位跟踪参考。
% 输出为 results/evm_input_power.png，重复运行覆盖同名图片。


%% 1. 设置扫描条件，并初始化星座和滤波器

cfg = comparison_config();                  % 读取两种调制共用的配置。
cfg.channel.snr_db = Inf;                   % 关闭 AWGN，只观察无噪声链路误差。
cfg.rx.reconstruction = 'self';             % APTBM 使用幅度与相位自重构。
pin_dbm_list = -35:1:-5;                    % PA 输入平均功率，单位 dBm。
model_names = {'rapp', 'saleh', 'mp'};      % 三个子图依次对应 Rapp、Saleh、MP。
model_titles = {'Rapp', 'Saleh', 'MP'};     % 子图使用的模型名称。
num_frames = 100;                         % 每个模型、每个功率点共用这 100 帧数据。
rng(cfg.sim.random_seed);                   % 整次检查只设置一次随机种子。

% 固定为 16 阶设置，并同步更新与比特分组有关的派生参数。
cfg.aptbm.num_sphere_points = 16;
cfg.aptbm.num_phases = 16;
cfg.aptbm.bits_per_block = log2(cfg.aptbm.num_sphere_points) ...
    + log2(cfg.aptbm.num_phases);           % 每个 APTBM 双符号块传输 8 比特。
cfg.oqam.modulation_order = 16;
cfg.oqam.bits_per_symbol = log2(cfg.oqam.modulation_order); % 每个复符号传输 4 比特。
cfg.sim.bits_per_frame = cfg.sim.blocks_per_frame * cfg.aptbm.bits_per_block;
cfg.oqam.symbols_per_frame = cfg.sim.bits_per_frame / cfg.oqam.bits_per_symbol;

codebook = build_codebook(cfg);             % APTBM 收发共用的码本。
constellation = build_oqam_constellation(cfg); % OQAM 使用的 QAM 星座表。
rrc_coeffs = design_rrc(cfg);               % 两条链路共用的单位能量 RRC 系数。


%% 2. 预先分配累计能量及 IBO 数组
% 每行对应一个 PA 模型，每列对应一个输入功率点。

num_models = numel(model_names);
num_power_points = numel(pin_dbm_list);
error_energy_aptbm = zeros(num_models, num_power_points); % 自重构后的累计误差能量。
error_energy_oqam = zeros(num_models, num_power_points);  % OQAM 的累计误差能量。
ibo_db_list = zeros(num_models, num_power_points); % 各模型、各 Pin 对应的 IBO。
block_phase_shift_list = zeros(num_models, num_power_points); % 各工况统一的块旋转角。
reference_energy_aptbm = 0;                 % 全部发送 APTBM 符号的累计能量。
reference_energy_oqam = 0;                  % 全部发送 QAM 符号的累计能量。

% 每个单元保存一种 PA、一个 Pin 下的全部帧，不混合不同工况。
num_blocks_all = num_frames * cfg.sim.blocks_per_frame;
blocks_tx_all = complex(zeros(num_blocks_all, 2)); % 全部帧的发送块，仅用于 EVM 比较。
blocks_rx_all = cell(num_models, num_power_points);

for model_index = 1:num_models
    for power_index = 1:num_power_points
        blocks_rx_all{model_index, power_index} = complex(zeros(num_blocks_all, 2));
    end
end

fprintf('EVM 扫描：Pin = -35:1:-5 dBm，SNR = Inf，每点 %d 帧。\n', num_frames);


%% 3. 逐帧生成共用比特及两种发射波形

for frame_index = 1:num_frames
    bits_tx = generate_bits(cfg);           % 每帧只生成一次比特。
    blocks_tx = aptbm_map(bits_tx, codebook);
    first_block = (frame_index - 1) * cfg.sim.blocks_per_frame + 1;
    last_block = frame_index * cfg.sim.blocks_per_frame;
    blocks_tx_all(first_block:last_block, :) = blocks_tx; % 保留原帧顺序。
    symbols_tx_aptbm = serialize_blocks(blocks_tx);
    waveform_tx_aptbm = pulse_shape(symbols_tx_aptbm, rrc_coeffs, cfg);
    symbols_tx_oqam = oqam_map(bits_tx, constellation);
    waveform_tx_oqam = oqam_pulse_shape(symbols_tx_oqam, rrc_coeffs, cfg);

    % 每帧参考能量只累计一次，所有模型和功率点使用同一组发送符号。
    reference_energy_aptbm = reference_energy_aptbm + sum(abs(blocks_tx(:)).^2);
    reference_energy_oqam = reference_energy_oqam + sum(abs(symbols_tx_oqam).^2);

    for model_index = 1:num_models
        cfg.pa.model = model_names{model_index}; % 切换当前非线性 PA 模型。

        switch cfg.pa.model
            case 'rapp'
                reference_input_power = cfg.pa.rapp.reference_input_power;

            case 'saleh'
                reference_input_power = cfg.pa.saleh.reference_input_power;

            case 'mp'
                reference_input_power = cfg.pa.mp.reference_input_power;
        end

        for power_index = 1:num_power_points
            pin_dbm = pin_dbm_list(power_index); % 当前目标 PA 输入平均功率。

            % PA 数字模型约定模平方数值采用 mW 标度，P = 10^(Pin_dBm/10)。
            % IBO = 10*log10(Pref/P)，并非直接将 Pin 当作 IBO。
            target_input_power = 10^(pin_dbm / 10);
            ibo_db = 10 * log10(reference_input_power / target_input_power);
            ibo_db_list(model_index, power_index) = ibo_db;

            % 3.1 APTBM：设置输入功率、经过 PA 和无噪声信道。
            [pa_in_aptbm, scale_aptbm] = set_input_backoff(waveform_tx_aptbm, ibo_db, cfg);
            pa_out_aptbm = apply_pa(pa_in_aptbm, cfg);
            waveform_rx_aptbm = add_awgn(pa_out_aptbm, cfg.channel.snr_db, cfg);

            % 3.2 APTBM：匹配滤波、采样、校准，暂存本帧接收块。
            matched_aptbm = matched_filter(waveform_rx_aptbm, rrc_coeffs);
            symbols_rx_aptbm = sample_symbols(matched_aptbm, rrc_coeffs, cfg);
            calibrated_aptbm = calibrate_gain(symbols_rx_aptbm, scale_aptbm, cfg);
            blocks_rx = deserialize_blocks(calibrated_aptbm);
            blocks_rx_all{model_index, power_index}(first_block:last_block, :) = blocks_rx;

            % 3.3 OQAM：设置相同输入功率，经过 PA 和无噪声信道。
            [pa_in_oqam, scale_oqam] = set_input_backoff(waveform_tx_oqam, ibo_db, cfg);
            pa_out_oqam = apply_pa(pa_in_oqam, cfg);
            waveform_rx_oqam = add_awgn(pa_out_oqam, cfg.channel.snr_db, cfg);

            % 3.4 OQAM：MP 必须先校准连续复波形，再分别取 I/Q 采样值。
            matched_oqam = matched_filter(waveform_rx_oqam, rrc_coeffs);

            if strcmp(cfg.pa.model, 'mp')
                % 复数相位校准会旋转 I/Q 轴，应在分时取实部、虚部之前完成。
                matched_calibrated_oqam = calibrate_gain(matched_oqam, scale_oqam, cfg);
                calibrated_oqam = oqam_sample_symbols(matched_calibrated_oqam, rrc_coeffs, cfg);
            else
                % 原有模型使用正实数增益，继续沿用先采样、后幅度校准的顺序。
                symbols_rx_oqam = oqam_sample_symbols(matched_oqam, rrc_coeffs, cfg);
                calibrated_oqam = calibrate_gain(symbols_rx_oqam, scale_oqam, cfg);
            end

            % 3.5 核对实际输入功率，平均时包含完整成形波形的滤波尾部。
            power_ratio_aptbm = mean(abs(pa_in_aptbm).^2) / target_input_power;
            power_ratio_oqam = mean(abs(pa_in_oqam).^2) / target_input_power;
            assert(abs(power_ratio_aptbm - 1) < 1e-10 ...
                && abs(power_ratio_oqam - 1) < 1e-10, ...
                'check_evm_input_power:InputPower', '实际 PA 输入平均功率与目标 Pin 不一致。');

            % 3.6 OQAM 逐帧累计误差；APTBM 待全部帧收齐后统一重构再比较。
            error_oqam = calibrated_oqam - symbols_tx_oqam;
            error_energy_oqam(model_index, power_index) = ...
                error_energy_oqam(model_index, power_index) + sum(abs(error_oqam).^2);
        end
    end

    if mod(frame_index, 10) == 0
        fprintf('已完成 %d/%d 帧的全部模型与输入功率扫描。\n', frame_index, num_frames);
    end
end


%% 4. APTBM 全部帧统一估计一次旋转角，再计算 EVM
% 每种 PA、每个输入功率点只调用一次重构函数，输入包含全部 100 帧。

for model_index = 1:num_models
    cfg.pa.model = model_names{model_index};

    for power_index = 1:num_power_points
        [blocks_rec_all, block_phase_shift] = aptbm_reconstruct( ...
            blocks_rx_all{model_index, power_index}, cfg);
        block_phase_shift_list(model_index, power_index) = block_phase_shift;
        error_aptbm = blocks_rec_all - blocks_tx_all; % 所有帧使用同一个平均旋转角。
        error_energy_aptbm(model_index, power_index) = sum(abs(error_aptbm(:)).^2);
    end
end

% 按论文定义计算 EVM，单位 dB。
% N*Pavg 等于全部发送符号的能量之和，故可直接用累计能量之比。
% APTBM 的分子、分母均包括块内两个符号，避免遗漏或重复乘以 2。
% 先累计线性能量，再取对数，不对各帧的 dB 结果直接求平均。

evm_db_aptbm = 10 * log10(error_energy_aptbm / reference_energy_aptbm);
evm_db_oqam = 10 * log10(error_energy_oqam / reference_energy_oqam);
min_evm_db = 5 * floor(min([evm_db_aptbm(:); evm_db_oqam(:)]) / 5);
max_evm_db = 5 * ceil(max([evm_db_aptbm(:); evm_db_oqam(:)]) / 5);


%% 5. 绘制 Rapp、Saleh、MP 的 EVM-输入功率曲线

figure_handle = figure('Name', 'EVM versus PA Input Power', ...
    'NumberTitle', 'off', 'Color', 'w', 'Position', [50, 100, 1650, 500]);

for model_index = 1:num_models
    subplot(1, num_models, model_index);
    plot(pin_dbm_list, evm_db_aptbm(model_index, :), 'b-o', ...
        'LineWidth', 1.5, 'DisplayName', 'APTBM (16 x 16, reconstructed)');
    hold on;
    plot(pin_dbm_list, evm_db_oqam(model_index, :), 'r:s', ...
        'LineWidth', 1.5, 'DisplayName', 'OQAM (16-QAM)');
    hold off;
    grid on;
    xlabel('PA input power Pin (dBm)');
    ylabel('EVM (dB)');
    title([model_titles{model_index}, ' PA']);
    legend('Location', 'northwest');
    xlim([pin_dbm_list(1), pin_dbm_list(end)]);
    ylim([min_evm_db, max_evm_db]);          % 三幅子图使用相同纵轴范围，便于对比。
end

sgtitle(sprintf('16-order comparison: SNR = Inf, one phase estimate from %d frames/point', num_frames));


%% 6. 保存整张图片，并返回统计结果

project_root = fileparts(fileparts(mfilename('fullpath'))); % 根据本文件定位工程根目录。
results_dir = fullfile(project_root, 'results');

if ~isfolder(results_dir)
    mkdir(results_dir);
end

image_file = fullfile(results_dir, 'evm_input_power.png');
print(figure_handle, image_file, '-dpng', '-r150'); % 三个子图合为一张 PNG 保存。
fprintf('EVM-输入功率对比图已保存至：\n%s\n', image_file);

results = struct();
results.cfg = cfg;
results.model_names = model_names;
results.pin_dbm = pin_dbm_list;
results.ibo_db = ibo_db_list;
results.num_frames = num_frames;
results.error_energy_aptbm = error_energy_aptbm;
results.error_energy_oqam = error_energy_oqam;
results.reference_energy_aptbm = reference_energy_aptbm;
results.reference_energy_oqam = reference_energy_oqam;
results.evm_db_aptbm = evm_db_aptbm;
results.evm_db_oqam = evm_db_oqam;
results.mean_block_phase_shift = block_phase_shift_list; % 每个点由全部帧估计的一次旋转角。

end
