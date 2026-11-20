function check_pa_waveform()
%CHECK_PA_WAVEFORM 观察同一帧信号经过两种 PA 模型前后的包络波形。
%
% 使用方法：在工程根目录先执行 startup，再执行 check_pa_waveform。
%
% 本文件生成一帧 APTBM 成形波形，分别经过 Rapp 和 Saleh 模型。
% 每种模型都使用 3、6、9 dB 三个 IBO，共输出两张图，每张图有六条曲线。
% 每个 IBO 对应一条线性参考包络和一条 PA 输出包络。
% 线性参考为“小信号幅度增益乘以实际 PA 输入”，用于观察 AM-AM 幅度压缩。
% 同一 IBO 使用相同颜色，虚线为线性参考，实线为 PA 输出。
%
% 完整一帧参与 PA 处理，绘图显示前 200 个采样点，便于观察细节。
% 图片保存为 results/rapp_pa_waveform.png 和 results/saleh_pa_waveform.png。
% 重复运行时覆盖同名 PNG，不额外保存波形数据或其他格式文件。


%% 1. 读取参数，并设置本次观察条件

cfg = default_config();                       % 读取工程的统一参数。
rng(cfg.sim.random_seed);                     % 设置一次随机种子，使结果可以复现。

ibo_values_db = [3, 6, 9];                    % 本次观察使用的三个输入回退值。
model_names = {'rapp', 'saleh'};               % 依次观察两种 PA 模型。
num_plot_samples = 200;                       % 每张图显示的采样点数，可在此修改。
curve_colors = [1, 0, 0; 0, 0, 1; 0, 0.5, 0]; % 三行依次为 3、6、9 dB 的红、蓝、绿颜色。


%% 2. 生成一帧发射端成形波形
% 只生成一次，保证两种模型和三个 IBO 使用完全相同的原始信号。

codebook = build_codebook(cfg);               % 生成 APTBM 候选符号块及比特标签。
bits_tx = generate_bits(cfg);                 % 生成一帧随机比特。
blocks_tx = aptbm_map(bits_tx, codebook);      % 将比特映射为 APTBM 符号块。
symbols_tx = serialize_blocks(blocks_tx);     % 将双符号块按时间顺序串行化。
rrc_coeffs = design_rrc(cfg);                 % 生成单位能量 RRC 滤波器系数。
waveform_tx = pulse_shape(symbols_tx, rrc_coeffs, cfg); % 得到完整的成形波形。

num_samples = numel(waveform_tx);              % 一帧成形波形的总采样点数。
num_plot_samples = min(num_plot_samples, num_samples); % 显示范围不超过帧长度。
plot_indices = 1:num_plot_samples;            % 从原始波形中选取的采样位置。
sample_axis = (0:num_plot_samples - 1).';      % 横坐标从第 0 个采样点开始计数。


%% 3. 准备图片保存目录

project_root = fileparts(fileparts(mfilename('fullpath'))); % 获取工程根目录。
results_dir = fullfile(project_root, 'results'); % 图片统一保存到 results 目录。

if ~isfolder(results_dir)
    mkdir(results_dir);                       % 目录不存在时创建该目录。
end


%% 4. 分别经过两种 PA，并绘制三组包络对比曲线

for model_index = 1:numel(model_names)
    cfg.pa.model = model_names{model_index};  % 从名称列表中取出当前模型。
    waveform_inputs = complex(zeros(num_samples, 3)); % 三列保存三个 IBO 的实际 PA 输入。
    waveform_outputs = complex(zeros(num_samples, 3)); % 三列分别保存三个 IBO 的输出。

    for ibo_index = 1:numel(ibo_values_db)
        ibo_db = ibo_values_db(ibo_index);     % 当前使用的单个 IBO 值。

        % 先按当前模型的参考功率设置 IBO，再计算整个帧的 PA 非线性响应。
        waveform_pa_in = set_input_backoff(waveform_tx, ibo_db, cfg);
        waveform_inputs(:, ibo_index) = waveform_pa_in; % 保留本次 IBO 对应的实际输入。
        waveform_outputs(:, ibo_index) = apply_pa(waveform_pa_in, cfg);
    end

    if strcmp(cfg.pa.model, 'rapp')
        model_title = 'Rapp';                 % 第一张图的模型名称。
        image_name = 'rapp_pa_waveform.png';   % 第一张图的固定文件名。
        small_signal_gain = cfg.pa.rapp.g0;   % Rapp 模型的小信号幅度增益。
    else
        model_title = 'Saleh';                % 第二张图的模型名称。
        image_name = 'saleh_pa_waveform.png';  % 第二张图的固定文件名。
        small_signal_gain = cfg.pa.saleh.alpha1; % Saleh 在小幅度处的幅度增益。
    end

    linear_references = small_signal_gain * waveform_inputs; % 各 IBO 的理想线性输出。

    figure_handle = figure('Name', [model_title, ' PA Waveform'], ...
        'NumberTitle', 'off', 'Color', 'w', ...
        'Position', [100, 100, 1100, 520]);     % 每种模型新建一个六曲线窗口。

    hold on;                                 % 在同一坐标轴中叠加三组参考与输出。

    for ibo_index = 1:numel(ibo_values_db)
        ibo_db = ibo_values_db(ibo_index);     % 当前一组曲线对应的 IBO。
        curve_color = curve_colors(ibo_index, :); % 为这一组曲线选择相同颜色。

        plot(sample_axis, abs(linear_references(plot_indices, ibo_index)), ...
            '--', 'Color', curve_color, 'LineWidth', 1.1, ...
            'DisplayName', sprintf('Linear ref: IBO = %d dB', ibo_db)); % 虚线：线性参考。

        plot(sample_axis, abs(waveform_outputs(plot_indices, ibo_index)), ...
            '-', 'Color', curve_color, 'LineWidth', 1.1, ...
            'DisplayName', sprintf('PA output: IBO = %d dB', ibo_db)); % 实线：实际输出。
    end

    hold off;                                % 结束当前图中的曲线叠加。
    grid on;                                 % 显示网格，便于观察包络变化。
    xlim([0, num_plot_samples - 1]);           % 所有曲线使用相同的显示区间。
    xlabel('Sample index');                   % 横坐标为采样点编号。
    ylabel('Envelope amplitude');             % 纵坐标为复波形的模值。
    title([model_title, ' PA: linear references and outputs']); % 标注比较内容。

    legend('show', 'Location', 'northoutside', 'NumColumns', 3); % 每列为同一 IBO 的一组曲线。

    %% 5. 保存当前模型的整张图片

    image_file = fullfile(results_dir, image_name); % 拼接当前图片的完整路径。
    print(figure_handle, image_file, '-dpng', '-r150'); % 以 150 dpi 保存一张 PNG。
    fprintf('%s 波形图已保存至：\n%s\n', model_title, image_file); % 显示保存位置。
end

end
