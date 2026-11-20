function check_oqam_linear_link()
%CHECK_OQAM_LINEAR_LINK 检查线性 PA、无噪声条件下的 OQAM 完整链路。
%
% 使用方法：在工程根目录先执行 startup，再执行 check_oqam_linear_link。
%
% 先用单个已知符号检查半符号错位和 I/Q 采样，再检查一帧随机比特。
% 完整链路包括映射、成形、IBO 调整、线性 PA、无噪声信道、
% 匹配滤波、I/Q 分时采样、幅度校准、星座检测和比特恢复。
% 本检查只显示采样位置与误码统计，不绘图、不保存文件。


%% 1. 设置本次检查条件

cfg = comparison_config();                  % 读取对比参数，修改只在本函数内生效。
cfg.pa.model = 'linear';                    % 使用理想单位增益 PA。
ibo_db = 6;                                % 保留 IBO 缩放，以检查后续幅度校准。
snr_db = Inf;                              % 无噪声条件。
tolerance = 1e-10;                         % 单符号响应与采样检查的数值容差。
rng(cfg.sim.random_seed);                   % 固定本次检查的随机种子。

constellation = build_oqam_constellation(cfg); % 生成收发双方共用的 QAM 星座表。
rrc_coeffs = design_rrc(cfg);               % 生成单位能量的实数 RRC 系数。
samples_per_symbol = cfg.pulse.samples_per_symbol; % 每个符号周期的采样点数 S。
half_symbol_samples = samples_per_symbol / 2; % 理论半符号延迟 D。
num_taps = numel(rrc_coeffs);               % RRC 系数个数 H。


%% 2. 用单个已知符号检查错位发送和采样对齐
% 取 I=1、Q=2，使两分支数值不同，便于发现分支交换或采样错误。
% 单符号没有相邻符号干扰，单位能量 RRC 匹配滤波后应精确恢复 1+2j。

probe_cfg = cfg;                           % 使用独立配置，不改变随机帧的符号数。
probe_cfg.oqam.symbols_per_frame = 1;       % 本次只发送一个已知复符号。
probe_symbol = 1 + 2j;                     % 仅用于对齐检查，不要求属于 QAM 星座。
probe_waveform = oqam_pulse_shape(probe_symbol, rrc_coeffs, probe_cfg);

% I 响应从第一点开始，Q 响应前补 D 个零，两者均保留完整滤波尾部。
expected_i = [rrc_coeffs; zeros(half_symbol_samples, 1)];
expected_q = [zeros(half_symbol_samples, 1); 2 * rrc_coeffs];
expected_waveform = expected_i + 1j * expected_q;

assert(isequal(size(probe_waveform), size(expected_waveform)), ...
    'check_oqam_linear_link:ProbeLength', '单符号成形波形长度不正确。');

assert(max(abs(probe_waveform - expected_waveform)) < tolerance, ...
    'check_oqam_linear_link:TransmitAlignment', '发射 I/Q 响应或半符号错位不正确。');

probe_matched = matched_filter(probe_waveform, rrc_coeffs); % 对已知符号匹配滤波。
probe_received = oqam_sample_symbols(probe_matched, rrc_coeffs, probe_cfg);

assert(abs(probe_received - probe_symbol) < tolerance, ...
    'check_oqam_linear_link:ReceiveAlignment', '单符号 I/Q 采样未能正确恢复已知符号。');


%% 3. 生成一帧随机比特，并完成发射端处理

bits_tx = generate_bits(cfg);               % 生成两种调制共用规则下的一帧随机比特。
symbols_tx = oqam_map(bits_tx, constellation); % 将比特映射为 QAM 复符号序列。
waveform_tx = oqam_pulse_shape(symbols_tx, rrc_coeffs, cfg); % RRC 成形及 Q 分支错位。

assert(isequal(size(symbols_tx), [cfg.oqam.symbols_per_frame, 1]), ...
    'check_oqam_linear_link:SymbolCount', '映射符号数与 OQAM 帧配置不一致。');

[waveform_pa_in, amplitude_scale] = set_input_backoff(waveform_tx, ibo_db, cfg);
waveform_pa_out = apply_pa(waveform_pa_in, cfg); % 通过理想线性 PA。
[waveform_rx, noise_variance] = add_awgn(waveform_pa_out, snr_db, cfg);

assert(noise_variance == 0 && isequal(waveform_rx, waveform_pa_out), ...
    'check_oqam_linear_link:Noise', '本检查要求信道不添加噪声。');


%% 4. 接收端匹配滤波、I/Q 采样、幅度校准与解映射

waveform_matched = matched_filter(waveform_rx, rrc_coeffs); % 保留完整匹配滤波响应。
symbols_rx = oqam_sample_symbols(waveform_matched, rrc_coeffs, cfg); % 对齐并组合 I/Q。
symbols_calibrated = calibrate_gain(symbols_rx, amplitude_scale, cfg); % 恢复星座幅度。
[bits_rx, symbol_indices] = oqam_demap(symbols_calibrated, constellation);

assert(isequal(size(symbols_rx), size(symbols_tx)), ...
    'check_oqam_linear_link:ReceivedSymbolCount', '发送和接收符号的尺寸不一致。');

assert(isequal(size(bits_rx), size(bits_tx)), ...
    'check_oqam_linear_link:BitCount', '发送和接收比特的尺寸不一致。');


%% 5. 分别检查 I/Q 判决，并统计误比特数
% 有限长度 RRC 存在少量残余码间干扰，采样值不必与发送值完全相等。
% 因此比较最终判决的星座点，并要求两分支均无判决错误。

symbols_detected = constellation.symbols(symbol_indices); % 根据检测行号读取判决点。
num_i_errors = sum(real(symbols_detected) ~= real(symbols_tx)); % I 分支判决错误数。
num_q_errors = sum(imag(symbols_detected) ~= imag(symbols_tx)); % Q 分支判决错误数。
num_bit_errors = sum(bits_rx ~= bits_tx);    % 一帧恢复比特的错误数。
ber = num_bit_errors / numel(bits_tx);       % 本帧误比特率。

first_i_sample = num_taps;                  % 总延迟 H-1，对应 MATLAB 第 H 点。
first_q_sample = first_i_sample + half_symbol_samples; % Q 分支晚半个符号周期。
last_i_sample = first_i_sample + (numel(symbols_tx) - 1) * samples_per_symbol;
last_q_sample = last_i_sample + half_symbol_samples;

fprintf('单符号半符号错位与 I/Q 采样检查通过。\n');
fprintf('I 分支采样：%d:%d:%d\n', first_i_sample, samples_per_symbol, last_i_sample);
fprintf('Q 分支采样：%d:%d:%d\n', first_q_sample, samples_per_symbol, last_q_sample);
fprintf('发送符号数：%d，接收符号数：%d\n', numel(symbols_tx), numel(symbols_rx));
fprintf('I 分支判决错误数：%d，Q 分支判决错误数：%d\n', num_i_errors, num_q_errors);
fprintf('发送比特数：%d，接收比特数：%d\n', numel(bits_tx), numel(bits_rx));
fprintf('误比特数：%d，BER = %.6g\n', num_bit_errors, ber);

assert(num_i_errors == 0 && num_q_errors == 0, ...
    'check_oqam_linear_link:BranchErrors', 'I/Q 分支存在判决错误，请检查成形、采样及幅度校准。');

assert(num_bit_errors == 0, ...
    'check_oqam_linear_link:BitErrors', '线性无噪声 OQAM 链路存在误比特，请检查标签与比特顺序。');

fprintf('OQAM 线性无噪声完整链路检查通过。\n');

end
