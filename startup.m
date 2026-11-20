%STARTUP 将 APTBM 工程的各模块目录加入 MATLAB 搜索路径。
%
% 使用方法：在工程根目录的 MATLAB 命令行中输入 startup。
% 路径由本文件的位置确定，移动工程后不需要手动修改路径。
% 这里只添加代码目录；data 和 results 用于存放数据，不加入搜索路径。


%% 1. 获取工程根目录

project_root = fileparts(mfilename('fullpath')); % 获取 startup.m 所在的目录。


%% 2. 添加工程根目录和各模块目录

addpath(project_root);                          % 根目录：仿真入口等文件。

addpath(fullfile(project_root, 'config'));       % 配置模块：统一仿真参数。

addpath(fullfile(project_root, 'tx'));           % 发射模块：比特生成、映射和成形。

addpath(fullfile(project_root, 'pa'));           % 功放模块：输入回退和非线性 PA。

addpath(fullfile(project_root, 'channel'));      % 信道模块：添加 AWGN 噪声。

addpath(fullfile(project_root, 'rx'));           % 接收模块：匹配滤波、重构和解调。

addpath(fullfile(project_root, 'common'));       % 公共模块：码本、滤波器和参数检查。

addpath(fullfile(project_root, 'simulation'));   % 仿真模块：单帧处理和参数扫描。

addpath(fullfile(project_root, 'evaluation'));   % 评估模块：性能统计和绘图。

addpath(fullfile(project_root, 'checks'));       % 检查模块：映射和线性链路检查。
