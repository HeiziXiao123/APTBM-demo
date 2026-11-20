function check_codebook(cfg, codebook)
%CHECK_CODEBOOK 检查 APTBM 码本，并绘制星座图。
%
% 使用方法：
%   check_codebook();                % 生成并检查默认码本。
%   check_codebook(cfg, codebook);   % 检查已有的参数与码本。
%
% 运行前先在工程根目录执行 startup，将各模块加入 MATLAB 搜索路径。
% 检查失败时，assert 会显示原因并停止；全部通过后绘制并保存一张星座图。


%% 1. 准备参数与码本

if nargin < 1
    cfg = default_config();                    % 未传入参数时，使用默认配置。
end

if nargin < 2
    codebook = build_codebook(cfg);             % 未传入码本时，根据配置生成。
end

num_phases = cfg.aptbm.num_phases;              % 公共相位数 M。
num_sphere_points = cfg.aptbm.num_sphere_points; % 球面点数 L。
block_energy = cfg.aptbm.block_energy;          % 每个符号块的总能量 P。
bits_per_block = log2(num_phases) + log2(num_sphere_points); % 每块比特数 K。
num_blocks = num_phases * num_sphere_points;    % 候选符号块的总数量。
tolerance = 1e-10;                             % 归一化数值的比较容差。


%% 2. 检查尺寸

assert(codebook.num_phases == num_phases, ...
    'check_codebook:Dimensions', '码本中的公共相位数与配置不一致。');

assert(codebook.num_sphere_points == num_sphere_points, ...
    'check_codebook:Dimensions', '码本中的球面点数与配置不一致。');

assert(codebook.block_energy == block_energy, ...
    'check_codebook:Dimensions', '码本中的块能量与配置不一致。');

assert(codebook.bits_per_block == bits_per_block, ...
    'check_codebook:Dimensions', '码本中的每块比特数不正确。');

assert(isequal(size(codebook.sphere_points), [num_sphere_points, 3]), ...
    'check_codebook:Dimensions', 'sphere_points 的尺寸应为 L 行 3 列。');

assert(isequal(size(codebook.common_phases), [num_phases, 1]), ...
    'check_codebook:Dimensions', 'common_phases 的尺寸应为 M 行 1 列。');

assert(isequal(size(codebook.phase_differences), [num_sphere_points, 1]), ...
    'check_codebook:Dimensions', 'phase_differences 的尺寸应为 L 行 1 列。');

assert(isequal(size(codebook.blocks), [num_blocks, 2]), ...
    'check_codebook:Dimensions', 'blocks 的尺寸应为 M*L 行 2 列。');

assert(isequal(size(codebook.bit_labels), [num_blocks, bits_per_block]), ...
    'check_codebook:Dimensions', 'bit_labels 的尺寸应为 M*L 行 K 列。');

fprintf('1. 尺寸检查通过：%d 个候选块，每块 %d 比特。\n', num_blocks, bits_per_block);


%% 3. 检查比特标签
% 当前工程使用自然二进制标签，高位在左，标签从全 0 依次排列到全 1。
% 其整数值应为行号减 1，因此同时检查了唯一性、完整性和排列顺序。

labels_are_binary = all(codebook.bit_labels(:) == 0 | codebook.bit_labels(:) == 1);
assert(labels_are_binary, ...
    'check_codebook:BitLabels', '比特标签只能包含数值 0 和 1。');

label_values = zeros(num_blocks, 1);            % 保存每行标签对应的十进制整数。

for bit_index = 1:bits_per_block
    label_values = 2 * label_values + codebook.bit_labels(:, bit_index); % 逐位转换。
end

expected_values = (0:num_blocks - 1).';         % 自然二进制标签应对应这些整数。
assert(all(label_values == expected_values), ...
    'check_codebook:BitLabels', '比特标签存在缺失、重复或排列顺序错误。');

% 高位选择公共相位，低位选择球面点，索引均转换为从 1 开始。
phase_indices = floor(label_values / num_sphere_points) + 1;
sphere_indices = mod(label_values, num_sphere_points) + 1;

fprintf('2. 比特标签检查通过：标签完整、唯一，且公共相位比特在前。\n');


%% 4. 检查单位球面约束

assert(isreal(codebook.sphere_points) && all(isfinite(codebook.sphere_points(:))), ...
    'check_codebook:Sphere', '球面点的三个坐标必须为有限的实数。');

sphere_norm_squared = sum(codebook.sphere_points.^2, 2); % 每个点的模平方。
sphere_error = max(abs(sphere_norm_squared - 1));       % 与单位球面的最大偏差。

assert(sphere_error < tolerance, ...
    'check_codebook:Sphere', '球面点不满足 U1^2 + U2^2 + U3^2 = 1。');

fprintf('3. 球面约束检查通过：最大误差 %.3e。\n', sphere_error);


%% 5. 检查块能量

assert(isfinite(block_energy) && block_energy > 0, ...
    'check_codebook:BlockEnergy', '块能量 P 必须为有限的正数。');

assert(all(isfinite(codebook.blocks(:))), ...
    'check_codebook:BlockEnergy', '候选块的复符号必须为有限数值。');

measured_energy = sum(abs(codebook.blocks).^2, 2); % 每个候选块的实际能量。
energy_error = max(abs(measured_energy / block_energy - 1)); % 相对能量误差。

assert(energy_error < tolerance, ...
    'check_codebook:BlockEnergy', '候选块不满足 |x_a|^2 + |x_b|^2 = P。');

fprintf('4. 块能量检查通过：最大相对误差 %.3e。\n', energy_error);


%% 6. 检查正反变换一致性
% 先由复符号反求球面点、差分相位及公共相位，再重新构造复符号。
% 与 build_codebook.m 的式 (10) 保持一致：theta = angle(x_b)-angle(x_a)。

normalized_blocks = codebook.blocks / sqrt(block_energy); % 将块能量归一化为 1。
symbol_a = normalized_blocks(:, 1);            % 取出所有块的第一个符号。
symbol_b = normalized_blocks(:, 2);            % 取出所有块的第二个符号。

recovered_u1 = abs(symbol_a).^2 - abs(symbol_b).^2; % 由功率差恢复 U1。
cross_product = conj(symbol_a) .* symbol_b;    % 公共相位在此乘积中相互抵消。
recovered_u2 = 2 * real(cross_product);         % 由乘积的实部恢复 U2。
recovered_u3 = 2 * imag(cross_product);         % 由乘积的虚部恢复 U3。

recovered_points = [recovered_u1, recovered_u2, recovered_u3]; % 恢复的球面坐标。
expected_points = codebook.sphere_points(sphere_indices, :);  % 对应的原球面坐标。
point_difference = recovered_points - expected_points;       % 正反变换的坐标偏差。
point_error = max(abs(point_difference(:)));                 % 最大坐标误差。

assert(point_error < tolerance, ...
    'check_codebook:Transform', '由复符号恢复的球面点与原球面点不一致。');

assert(isreal(codebook.phase_differences) && isreal(codebook.common_phases), ...
    'check_codebook:Transform', '公共相位和差分相位必须为实数。');

assert(all(isfinite(codebook.phase_differences)) && all(isfinite(codebook.common_phases)), ...
    'check_codebook:Transform', '公共相位和差分相位必须为有限数值。');

recovered_theta = atan2(recovered_u3, recovered_u2); % 保留象限地恢复差分相位。
expected_theta = codebook.phase_differences(sphere_indices); % 原差分相位。
theta_error = max(abs(exp(1j * recovered_theta) - exp(1j * expected_theta)));

assert(theta_error < tolerance, ...
    'check_codebook:Transform', '恢复的差分相位与原差分相位不一致。');

% Fibonacci 球面点不在两极，两个符号的幅度均大于 0，可分别消除差分相位。
% 这样恢复完整的公共相位，避免直接将 angle(x_a*x_b) 除以 2 的相位歧义。
common_from_a = symbol_a .* exp(1j * recovered_theta / 2) ./ abs(symbol_a);
common_from_b = symbol_b .* exp(-1j * recovered_theta / 2) ./ abs(symbol_b);
expected_common = exp(-1j * codebook.common_phases(phase_indices)); % 原公共因子。

common_error_a = max(abs(common_from_a - expected_common)); % 第一符号的恢复误差。
common_error_b = max(abs(common_from_b - expected_common)); % 第二符号的恢复误差。

assert(common_error_a < tolerance && common_error_b < tolerance, ...
    'check_codebook:Transform', '恢复的公共相位与原公共相位不一致。');

% 利用恢复的参数执行正变换，重新生成归一化后的两个复符号。
amplitude_a = sqrt((1 + recovered_u1) / 2);     % 从恢复的 U1 计算第一符号幅度。
amplitude_b = sqrt((1 - recovered_u1) / 2);     % 从恢复的 U1 计算第二符号幅度。
rebuilt_a = common_from_a .* amplitude_a .* exp(-1j * recovered_theta / 2);
rebuilt_b = common_from_a .* amplitude_b .* exp(1j * recovered_theta / 2);

symbol_error_a = max(abs(rebuilt_a - symbol_a)); % 第一符号的正反变换误差。
symbol_error_b = max(abs(rebuilt_b - symbol_b)); % 第二符号的正反变换误差。

assert(symbol_error_a < tolerance && symbol_error_b < tolerance, ...
    'check_codebook:Transform', '正反变换后得到的符号块与原符号块不一致。');

fprintf('5. 正反变换检查通过：球面点最大误差 %.3e。\n', point_error);
fprintf('   差分相位误差 %.3e，公共相位误差 %.3e，符号误差 %.3e。\n', ...
    theta_error, max(common_error_a, common_error_b), max(symbol_error_a, symbol_error_b));


%% 7. 检查候选块是否重复
% 比较两个复符号组成的完整块；单个符号相同不代表整个块重复。
% 在归一化后比较距离，使重复判定不受块能量 P 的缩放影响。

minimum_distance = inf;                       % 记录不同候选块之间的最小距离。

for first_row = 1:num_blocks - 1
    for second_row = first_row + 1:num_blocks
        difference = normalized_blocks(first_row, :) - normalized_blocks(second_row, :);
        distance = sqrt(sum(abs(difference).^2)); % 计算两个完整块的欧氏距离。

        assert(distance > tolerance, ...
            'check_codebook:DuplicateBlocks', ...
            '第 %d 行与第 %d 行候选块重复或距离小于容差。', first_row, second_row);

        minimum_distance = min(minimum_distance, distance); % 更新最小距离。
    end
end

fprintf('6. 重复检查通过：归一化块的最小距离 %.6f。\n', minimum_distance);


%% 8. 绘制码本星座图
% 前两幅显示公共和差分状态空间，后两幅显示实际发送的两个复符号。

figure_handle = figure('Name', 'APTBM Codebook', 'NumberTitle', 'off', ...
    'Color', 'w', 'Position', [100, 100, 1000, 760]); % 新建四子图窗口。

subplot(2, 2, 1);                             % 第一幅：公共相位星座。
circle_angles = linspace(0, 2 * pi, 361);      % 在单位圆周上取点，用于绘制参考圆。
plot(cos(circle_angles), sin(circle_angles), ...
    'Color', [0.6, 0.6, 0.6], 'LineWidth', 1); % 用灰色细线绘制单位圆周。
hold on;                                     % 保留圆周，再叠加公共相位状态点。
common_symbols = exp(-1j * codebook.common_phases); % 计算公共相位复数因子。
plot(real(common_symbols), imag(common_symbols), 'bo', 'MarkerFaceColor', 'b');
hold off;                                    % 结束当前子图的叠加绘制。
axis equal;                                  % 横纵坐标使用相同的比例。
axis([-1.2, 1.2, -1.2, 1.2]);                % 显示完整的单位圆状态空间。
grid on;                                     % 显示网格，便于观察点的位置。
xlabel('In-phase');                           % 横坐标为实部。
ylabel('Quadrature');                         % 纵坐标为虚部。
title(sprintf('Common alphabet (M = %d)', num_phases));

subplot(2, 2, 2);                             % 第二幅：单位球面上的状态点。
[sphere_x, sphere_y, sphere_z] = sphere(24);   % 生成单位球面的网格坐标。
surf(sphere_x, sphere_y, sphere_z, ...
    'FaceColor', [0.75, 0.85, 0.95], 'FaceAlpha', 0.18, ...
    'EdgeColor', [0.7, 0.7, 0.7], 'EdgeAlpha', 0.35); % 绘制半透明球面和网格。
hold on;                                     % 保留球面，再叠加球面状态点。
scatter3(codebook.sphere_points(:, 1), codebook.sphere_points(:, 2), ...
    codebook.sphere_points(:, 3), 36, 'b', 'filled'); % 绘制三维球面点。
hold off;                                    % 结束当前子图的叠加绘制。
axis equal;                                  % 三个坐标轴使用相同的比例。
axis([-1.1, 1.1, -1.1, 1.1, -1.1, 1.1]);    % 显示完整的单位球面范围。
grid on;                                     % 显示三维坐标网格。
view(45, 25);                                % 设置观察球面点的角度。
xlabel('U_1');                               % 球面第一维坐标。
ylabel('U_2');                               % 球面第二维坐标。
zlabel('U_3');                               % 球面第三维坐标。
title(sprintf('Sphere alphabet (L = %d)', num_sphere_points));

symbol_limit = 1.1 * sqrt(block_energy);       % 两个符号图共用同一坐标范围。

subplot(2, 2, 3);                             % 第三幅：每个块中的第一个复符号。
plot(real(codebook.blocks(:, 1)), imag(codebook.blocks(:, 1)), 'b.');
axis equal;                                  % 保持星座几何形状。
axis([-symbol_limit, symbol_limit, -symbol_limit, symbol_limit]);
grid on;                                     % 显示坐标网格。
xlabel('In-phase');                           % 第一符号的实部。
ylabel('Quadrature');                         % 第一符号的虚部。
title('Symbol x_a');                          % 标注第一个符号的星座。

subplot(2, 2, 4);                             % 第四幅：每个块中的第二个复符号。
plot(real(codebook.blocks(:, 2)), imag(codebook.blocks(:, 2)), 'r.');
axis equal;                                  % 保持星座几何形状。
axis([-symbol_limit, symbol_limit, -symbol_limit, symbol_limit]);
grid on;                                     % 显示坐标网格。
xlabel('In-phase');                           % 第二符号的实部。
ylabel('Quadrature');                         % 第二符号的虚部。
title('Symbol x_b');                          % 标注第二个符号的星座。

%% 9. 保存整张星座图
% 使用固定文件名，重复运行时覆盖同一张 PNG，不单独保存四幅子图。

project_root = fileparts(fileparts(mfilename('fullpath'))); % 获取工程根目录。
results_dir = fullfile(project_root, 'results'); % 结果目录不依赖当前工作目录。

if ~isfolder(results_dir)
    mkdir(results_dir);                       % 结果目录不存在时创建该目录。
end

image_file = fullfile(results_dir, 'codebook_constellation.png'); % 唯一的图片文件。
print(figure_handle, image_file, '-dpng', '-r150'); % 将整张四子图保存为 150 dpi PNG。

fprintf('码本全部检查通过，星座图已保存至：\n%s\n', image_file);

end
