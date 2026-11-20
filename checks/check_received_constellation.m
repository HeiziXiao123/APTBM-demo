function check_received_constellation()
%CHECK_RECEIVED_CONSTELLATION 绘制非线性链路下重构前的接收星座图。
%
% 使用方法：在工程根目录先执行 startup，再执行 check_received_constellation。
%
% 本文件生成同一帧 APTBM 信号，分别通过 Saleh 和 Rapp 模型，输入回退均为 9 dB。
% SNR 取默认扫描范围中的最高值，当前为 20 dB，可在参数区修改。
% 接收端完成匹配滤波、理想采样、幅度校准和块重组后，绘制 x_a、x_b 星座。
% 图中保留 PA 非线性失真和噪声，作为后续 APTBM 重构的对照。
% 每种模型各保存一张包含 x_a、x_b 子图的 PNG，重复运行覆盖同名文件。
% 输出为 results/saleh_received_constellation.png 和 results/rapp_received_constellation.png。


%% 1. 设置本次观察条件

cfg = default_config();                       % 读取统一参数，修改只在本函数内生效。
model_names = {'saleh', 'rapp'};              % 先处理已有的 Saleh 模型，再处理 Rapp 模型。
ibo_db = 9;                                  % 输入回退固定为 9 dB。
snr_db = max(cfg.channel.snr_db);             % 默认采用 20 dB 的采样点 SNR。
rng(cfg.sim.random_seed);                     % 设置一次随机种子，使接收星座可以复现。

codebook = build_codebook(cfg);               % 生成本帧使用的 APTBM 码本。
rrc_coeffs = design_rrc(cfg);                 % 生成收发双方使用的 RRC 系数。


%% 2. 生成两种模型共用的一帧发射波形

bits_tx = generate_bits(cfg);                 % 生成一帧随机比特。
blocks_tx = aptbm_map(bits_tx, codebook);      % 将比特映射为双符号块。
symbols_tx = serialize_blocks(blocks_tx);     % 将符号块按时间顺序串行化。
waveform_tx = pulse_shape(symbols_tx, rrc_coeffs, cfg); % 完成发射端脉冲成形。

%% 3. 准备图片保存目录

project_root = fileparts(fileparts(mfilename('fullpath'))); % 获取工程根目录。
results_dir = fullfile(project_root, 'results'); % 图片统一保存到结果目录。

if ~isfolder(results_dir)
    mkdir(results_dir);                       % 目录不存在时创建该目录。
end


%% 4. 分别计算两种非线性链路的原始接收星座

for model_index = 1:numel(model_names)
    cfg.pa.model = model_names{model_index};  % 切换当前模型，IBO 模块会选取对应参考功率。

    if strcmp(cfg.pa.model, 'saleh')
        model_title = 'Saleh';                % 当前图的模型名称。
        image_name = 'saleh_received_constellation.png'; % 保留已有的 Saleh 输出文件名。
    else
        model_title = 'Rapp';                 % 新增的 Rapp 模型名称。
        image_name = 'rapp_received_constellation.png';  % Rapp 模型单独保存一张图片。
    end

    % 先设置当前模型的实际输入功率，再通过 PA 和 AWGN 信道。
    [waveform_pa_in, amplitude_scale] = set_input_backoff(waveform_tx, ibo_db, cfg);
    waveform_pa_out = apply_pa(waveform_pa_in, cfg); % 计算当前模型的非线性幅相响应。
    waveform_rx = add_awgn(waveform_pa_out, snr_db, cfg); % 按同一 SNR 设定加入噪声。

    % 幅度校准补偿已知线性增益，星座保留非线性失真和噪声，处于自重构之前。
    waveform_matched = matched_filter(waveform_rx, rrc_coeffs); % 接收端匹配滤波。
    symbols_rx = sample_symbols(waveform_matched, rrc_coeffs, cfg); % 补偿总延迟并采样。
    symbols_calibrated = calibrate_gain(symbols_rx, amplitude_scale, cfg); % 校准幅度标度。
    blocks_rx = deserialize_blocks(symbols_calibrated); % 重新组成接收双符号块。

    %% 5. 绘制当前模型的 x_a、x_b 接收星座
    % 两幅子图使用相同的坐标范围，便于比较两个符号的分布。

    axis_limit = 1.1 * max([abs(blocks_rx(:)); sqrt(cfg.aptbm.block_energy)]); % 留出空白。
    figure_handle = figure('Name', [model_title, ' Received Constellation'], ...
        'NumberTitle', 'off', 'Color', 'w', ...
        'Position', [100, 100, 1050, 500]);     % 每种模型新建一个双子图窗口。

    subplot(1, 2, 1);                         % 第一幅：各接收块中的 x_a。
    plot(real(blocks_rx(:, 1)), imag(blocks_rx(:, 1)), 'b.', 'MarkerSize', 7);
    axis equal;                              % 实部和虚部使用相同的比例。
    axis([-axis_limit, axis_limit, -axis_limit, axis_limit]); % 设置统一范围。
    grid on;                                 % 显示坐标网格。
    xlabel('In-phase');                       % 横坐标为接收符号的实部。
    ylabel('Quadrature');                     % 纵坐标为接收符号的虚部。
    title('Received x_a');                    % 标注第一个接收符号。

    subplot(1, 2, 2);                         % 第二幅：各接收块中的 x_b。
    plot(real(blocks_rx(:, 2)), imag(blocks_rx(:, 2)), 'r.', 'MarkerSize', 7);
    axis equal;                              % 与第一幅子图保持相同的比例。
    axis([-axis_limit, axis_limit, -axis_limit, axis_limit]); % 设置统一范围。
    grid on;                                 % 显示坐标网格。
    xlabel('In-phase');                       % 横坐标为接收符号的实部。
    ylabel('Quadrature');                     % 纵坐标为接收符号的虚部。
    title('Received x_b');                    % 标注第二个接收符号。

    sgtitle(sprintf('%s PA: IBO = %g dB, SNR = %g dB (before reconstruction)', ...
        model_title, ibo_db, snr_db));        % 总标题记录当前模型和仿真条件。

    %% 6. 保存当前模型的整张接收星座图

    image_file = fullfile(results_dir, image_name); % 拼接当前模型的图片保存路径。
    print(figure_handle, image_file, '-dpng', '-r150'); % 以 150 dpi 保存一张 PNG。
    fprintf('%s 原始接收星座图已保存至：\n%s\n', model_title, image_file);
end

end
