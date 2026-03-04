function run_all_trad_roc()
% run_all_trad_roc
% ========================================================================
% 【主入口脚本】一键运行“红外小目标检测传统算法对比实验（单帧、点标注）”。
% 该函数会遍历 7 个算法 × data1..data10 序列，并生成每个组合的 ROC/AUC 结果。
% 
% 你只需要在 MATLAB 命令行中执行：
%   run_all_trad_roc
% 
% 本文件承担以下职责：
%   1) 统一配置参数（路径、抽帧策略、采样数、随机种子等）。
%   2) 注册算法并统一接口到 S = algo_fun(I)。
%   3) 循环调用 eval_one_alg_one_seq_roc 完成单算法单序列评测。
%   4) 汇总 AUC 到 summary_auc.csv 与 overall_rank.csv。
% 
% 评测口径关键点（严格统一）：
%   - 输入图像统一：若 RGB 则取第一通道，再转 double。
%   - 输出打分图统一：每帧 min-max 归一化到 [0,1]。
%   - 正样本：GT 点中心 9x9 ROI（roi_r=4）。
%   - 负样本：ROI 外像素，按帧随机下采样。
% ========================================================================

    % ------------------------- 0) 基础路径配置 -------------------------
    % 数据根目录（严格按你的真实目录结构）。
    cfg.root_dir = "E:/dimifrdata";
    % 算法目录（包含 AdMD7_eff/BLCM/...）。
    cfg.baseline_root = fullfile(cfg.root_dir, "baselines");
    % 输出目录（所有 ROC 图、CSV、MAT、汇总表都会写到这里）。
    cfg.out_dir = "E:/dimifrdata/results_trad_roc";

    % ------------------------- 1) 评测参数配置 -------------------------
    % 需要跑哪些序列，默认 data1..data10。
    cfg.seq_ids = 1:10;
    % 抽帧步长：1=每帧都跑；5=每隔5帧跑一帧。
    cfg.frame_stride = 5;
    % 每个序列最多处理多少帧，0 表示不限制。
    cfg.max_frames_per_seq = 200;
    % ROI 半径，roi_r=4 对应 9x9 ROI。
    cfg.roi_r = 4;
    % 每帧最多采样多少个负样本像素，控制内存与速度。
    cfg.neg_sample_per_frame = 20000;
    % 固定随机种子，保证可复现。
    cfg.rng_seed = 0;
    % 是否使用并行（需要 Parallel Toolbox）。
    cfg.use_parallel = false;
    % 帧级日志打印间隔（每处理多少帧打印一次进度）。
    cfg.print_every = 10;
    % ROC 阈值数量（fallback 实现会用到）。
    cfg.n_thresholds = 2000;
    % 是否运行快速测试：true 时只跑 data1 + 前20帧 + 前2算法。
    cfg.quick_test = false;

    % ------------------------- 2) 快速测试配置 -------------------------
    % 如果你希望快速验证代码是否跑通，把上面的 cfg.quick_test 改为 true。
    if cfg.quick_test
        % quick test 只跑 data1。
        cfg.seq_ids = 1;
        % quick test 每帧都跑，便于快速看到输出。
        cfg.frame_stride = 1;
        % quick test 限制前20帧。
        cfg.max_frames_per_seq = 20;
    end

    % ------------------------- 3) 环境准备 -------------------------
    % 固定随机种子，确保每次负样本采样一致，可复现。
    rng(cfg.rng_seed);
    % 把 baseline 目录递归加入路径，保证算法函数可调用。
    addpath(genpath(cfg.baseline_root));
    % 把当前工程目录（含 utils）加入路径。
    addpath(genpath(fileparts(mfilename('fullpath'))));
    % 创建输出目录（不存在就自动创建）。
    if ~exist(cfg.out_dir, 'dir')
        mkdir(cfg.out_dir);
    end

    % ------------------------- 4) 注册算法 -------------------------
    % 注册函数会自动统一 7 个算法接口，并处理 TLLCM/WSLCM 脚本兼容。
    algs = registry_trad_algorithms(cfg.baseline_root);
    % quick test 时只取前2个算法，便于快速跑通。
    if cfg.quick_test
        algs = algs(1:min(2, numel(algs)));
    end

    % ------------------------- 5) 结果表初始化 -------------------------
    % 算法数量。
    n_alg = numel(algs);
    % 序列数量。
    n_seq = numel(cfg.seq_ids);
    % AUC 矩阵：行=算法，列=序列。
    auc_mat = nan(n_alg, n_seq);

    % ------------------------- 6) 主循环：算法 × 序列 -------------------------
    % 这里采用“外层算法，内层序列”的结构，方便按算法查看进度。
    for ai = 1:n_alg
        % 当前算法名字（例如 BLCM）。
        alg_name = algs(ai).name;
        % 当前算法函数句柄（统一成 S=fun(I)）。
        alg_fun = algs(ai).fun;

        % 算法级进度打印。
        fprintf('\n==================== 算法 %d/%d: %s ====================\n', ai, n_alg, alg_name);

        % 可选并行：每个序列彼此独立，因此可以并行。
        if cfg.use_parallel && license('test', 'Distrib_Computing_Toolbox')
            % 并行分支：每个 worker 处理一个序列。
            parfor si = 1:n_seq
                % 当前序列编号（1..10）。
                seq_id = cfg.seq_ids(si);
                % 调用 helper，返回该算法在该序列的评测结果。
                auc_val = run_one_seq(alg_name, alg_fun, seq_id, cfg);
                % 写回 AUC。
                auc_mat(ai, si) = auc_val;
            end
        else
            % 串行分支：兼容没有并行工具箱的环境。
            for si = 1:n_seq
                % 当前序列编号（1..10）。
                seq_id = cfg.seq_ids(si);
                % 调用 helper，返回 AUC。
                auc_mat(ai, si) = run_one_seq(alg_name, alg_fun, seq_id, cfg);
            end
        end
    end

    % ------------------------- 7) 写 summary_auc.csv -------------------------
    % 构造表头：Algorithm, data1..data10, mean_AUC。
    var_names = cell(1, n_seq + 2);
    var_names{1} = 'Algorithm';
    for si = 1:n_seq
        var_names{si + 1} = sprintf('data%d', cfg.seq_ids(si));
    end
    var_names{end} = 'mean_AUC';

    % 构造单元格（第一列算法名 + 每列 AUC + 均值）。
    out_cell = cell(n_alg, n_seq + 2);
    for ai = 1:n_alg
        out_cell{ai, 1} = algs(ai).name;
        for si = 1:n_seq
            out_cell{ai, si + 1} = auc_mat(ai, si);
        end
        out_cell{ai, end} = mean(auc_mat(ai, :), 'omitnan');
    end

    % 单元格转 table，便于导出 CSV。
    summary_tbl = cell2table(out_cell, 'VariableNames', var_names);
    % 写 summary_auc.csv。
    writetable(summary_tbl, fullfile(cfg.out_dir, 'summary_auc.csv'));

    % ------------------------- 8) 写 overall_rank.csv -------------------------
    % 按 mean_AUC 从高到低排序。
    mean_auc = cell2mat(out_cell(:, end));
    [sorted_mean, order] = sort(mean_auc, 'descend', 'MissingPlacement', 'last');

    % 排名表内容：Rank, Algorithm, mean_AUC。
    rank_tbl = table((1:n_alg)', string(summary_tbl.Algorithm(order)), sorted_mean, ...
        'VariableNames', {'Rank', 'Algorithm', 'mean_AUC'});
    % 写 overall_rank.csv。
    writetable(rank_tbl, fullfile(cfg.out_dir, 'overall_rank.csv'));

    % ------------------------- 9) 结束打印 -------------------------
    fprintf('\n全部任务完成，输出目录：%s\n', cfg.out_dir);
end

function auc_val = run_one_seq(alg_name, alg_fun, seq_id, cfg)
% run_one_seq
% ========================================================================
% 这个局部函数只做一件事：
%   调用 eval_one_alg_one_seq_roc，执行“一个算法 + 一个序列”的完整评测。
% 将路径拼接与异常保护放在这里，主循环更清晰。
% ========================================================================

    % 序列名，例如 data1。
    seq_name = sprintf('data%d', seq_id);
    % 图像目录，严格匹配你的真实结构：E:/dimifrdata/dataX/dataX/*.bmp
    img_dir = fullfile(cfg.root_dir, seq_name, seq_name);
    % GT 文件路径：E:/dimifrdata/data_label/dataX.txt
    gt_path = fullfile(cfg.root_dir, 'data_label', sprintf('%s.txt', seq_name));

    % 打印序列级进度。
    fprintf('[%s] 处理序列 %s\n', alg_name, seq_name);

    % 用 try-catch 包住单序列，防止某一序列异常导致全局中断。
    try
        % 调用单序列评测函数。
        result = eval_one_alg_one_seq_roc(alg_name, alg_fun, img_dir, gt_path, cfg);
        % 提取 AUC。
        auc_val = result.AUC;
        % 打印该序列 AUC。
        fprintf('[%s] %s 完成，AUC=%.6f，有效帧=%d\n', alg_name, seq_name, auc_val, result.N_used_frames);
    catch ME
        % 如果该序列失败，打印 warning 并返回 NaN。
        warning('[%s] %s 失败：%s', alg_name, seq_name, ME.message);
        auc_val = NaN;
    end
end
