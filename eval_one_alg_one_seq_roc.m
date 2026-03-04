function result = eval_one_alg_one_seq_roc(alg_name, alg_fun, img_dir, gt_path, cfg)
% eval_one_alg_one_seq_roc
% ========================================================================
% 作用：执行“单算法 × 单序列”的完整 ROI 像素级 ROC/AUC 评测。
% 
% 输入：
%   alg_name - 算法名称字符串（用于命名输出文件）
%   alg_fun  - 统一算法接口函数句柄，调用形式 S = alg_fun(I)
%   img_dir  - 图像目录（例如 E:/dimifrdata/data1/data1）
%   gt_path  - GT 点标注 txt 路径（例如 E:/dimifrdata/data_label/data1.txt）
%   cfg      - 配置结构体（stride/roi/neg采样/输出目录等）
% 
% 输出：
%   result   - 结构体，至少包含：
%              AUC, thresholds, TPR, FPR,
%              pos_scores, neg_scores,
%              N_used_frames, row_offset, first_valid
% ========================================================================

    % ------------------------- 1) 读取 GT 并解析 offset -------------------------
    % GT 的第4列是 x(列)，第5列是 y(行)。
    [gt, row_offset, first_valid, n_gt_rows] = read_gt_with_offset(gt_path);

    % ------------------------- 2) 枚举图像文件 -------------------------
    % 只读取 bmp 文件。
    files = dir(fullfile(img_dir, '*.bmp'));
    % 若目录无图像，直接报错。
    if isempty(files)
        error('图像目录为空：%s', img_dir);
    end

    % 解析帧号（文件名应为 0.bmp,1.bmp,...）。
    frame_ids = nan(numel(files), 1);
    for i = 1:numel(files)
        [~, nm, ~] = fileparts(files(i).name);
        frame_ids(i) = str2double(nm);
    end

    % 去掉无法解析成数字的异常文件。
    valid_file_mask = isfinite(frame_ids);
    files = files(valid_file_mask);
    frame_ids = frame_ids(valid_file_mask);

    % 按帧号升序排序，保证处理顺序一致。
    [frame_ids, ord] = sort(frame_ids, 'ascend');
    files = files(ord);

    % ------------------------- 3) 先按 GT 可映射范围做预裁剪 -------------------------
    % 根据映射公式 row = row_offset + f + 1，可反推出可安全映射的最大帧号：
    %   f_max = n_gt_rows - row_offset - 1
    % 这一步不会改变评测协议，只是把“必然越界”的帧提前剔除，减少无意义 warning。
    f_max = n_gt_rows - row_offset - 1;
    % 只保留 frame_id <= f_max 的文件。
    map_ok_mask = frame_ids <= f_max;
    % 统计被预裁掉的越界帧数量（用于最终日志汇总）。
    n_prefilter_oob = sum(~map_ok_mask);
    files = files(map_ok_mask);
    frame_ids = frame_ids(map_ok_mask);

    % ------------------------- 4) 按 stride / max_frames 选帧 -------------------------
    % 先按 stride 抽帧。
    stride_mask = mod(frame_ids, cfg.frame_stride) == 0;
    files = files(stride_mask);
    frame_ids = frame_ids(stride_mask);

    % 如果限制最大帧数，则截断。
    if cfg.max_frames_per_seq > 0
        keep_n = min(cfg.max_frames_per_seq, numel(frame_ids));
        files = files(1:keep_n);
        frame_ids = frame_ids(1:keep_n);
    end

    % 候选帧数（注意不等于有效帧数，有些帧可能因错误被跳过）。
    n_total_frames = numel(frame_ids);

    % ------------------------- 5) 初始化采样缓存与计时 -------------------------
    % 正样本分数集合（ROI 内全部像素）。
    pos_scores = [];
    % 负样本分数集合（ROI 外随机采样像素）。
    neg_scores = [];
    % 有效帧计数（成功参与统计的帧数）。
    n_used = 0;
    % 总帧计数（已尝试处理的帧数）。
    n_done = 0;
    % 计时起点。
    t_start = tic;

    % ------------------------- 6) 初始化跳帧计数器（用于汇总日志） -------------------------
    % 记录 GT 行越界的帧数（理论上预裁后应趋近于0，保留该计数用于双保险）。
    n_skip_oob = 0;
    % 记录 GT 坐标无效（NaN/Inf）的帧数。
    n_skip_invalid_gt = 0;
    % 记录正负样本为空的帧数。
    n_skip_empty_sample = 0;
    % 记录算法输出尺寸不匹配的帧数。
    n_skip_bad_size = 0;
    % 记录算法执行异常的帧数。
    n_skip_algo_err = 0;

    % ------------------------- 7) 固定随机种子 -------------------------
    % 为了“可复现”，每个算法+序列设置确定性的种子偏移。
    seed = cfg.rng_seed + sum(double(alg_name)) + numel(img_dir);
    rng(seed);

    % ------------------------- 8) 主循环：逐帧评测 -------------------------
    for k = 1:n_total_frames
        % 当前尝试帧计数 +1。
        n_done = n_done + 1;
        % 当前帧号（文件名对应的数字）。
        f = frame_ids(k);

        % GT 行映射：row = row_offset + f + 1。
        gt_row = row_offset + f + 1;

        % 若映射越界，则跳过该帧。
        if gt_row < 1 || gt_row > n_gt_rows
            % 计数+1（仅统计，不逐帧 warning，避免刷屏）。
            n_skip_oob = n_skip_oob + 1;
            continue;
        end

        % 读取该帧 GT 点：x=第4列(列坐标)，y=第5列(行坐标)。
        x = gt(gt_row, 4);
        y = gt(gt_row, 5);

        % 若 x/y 非法（NaN/Inf），跳过该帧。
        if ~isfinite(x) || ~isfinite(y)
            % 计数+1（仅统计，不逐帧 warning，避免刷屏）。
            n_skip_invalid_gt = n_skip_invalid_gt + 1;
            continue;
        end

        % 读图路径。
        img_path = fullfile(files(k).folder, files(k).name);

        % 对单帧做异常保护：任何算法报错都不影响整序列。
        try
            % 读图。
            I = imread(img_path);
            % 若是 RGB，取第一通道。
            if ndims(I) == 3
                I = I(:, :, 1);
            end
            % 转 double。
            I = double(I);

            % 调用算法得到 score map。
            S = alg_fun(I);
            % 若输出尺寸不匹配输入图像，跳过该帧。
            if ~isequal(size(S), size(I))
                % 计数+1（尺寸错通常是算法实现问题，仍继续处理后续帧）。
                n_skip_bad_size = n_skip_bad_size + 1;
                continue;
            end

            % 统一每帧 min-max 归一化到 [0,1]，保证 ROC 公平可比。
            S = S - min(S(:));
            S = S / (max(S(:)) + eps);

            % 图像尺寸。
            H = size(I, 1);
            W = size(I, 2);

            % ROI mask：以 GT 点为中心 9x9（roi_r=4）并自动裁边。
            roi_mask = get_roi_mask(x, y, cfg.roi_r, H, W);

            % 采集正样本：ROI 内全部像素分数。
            pos_this = S(roi_mask);

            % 采集负样本：ROI 外随机下采样。
            neg_this = sample_neg_pixels(S, roi_mask, cfg.neg_sample_per_frame);

            % 若任一集合为空，则该帧不计入有效帧。
            if isempty(pos_this) || isempty(neg_this)
                % 计数+1（仅统计，不逐帧 warning）。
                n_skip_empty_sample = n_skip_empty_sample + 1;
                continue;
            end

            % 拼接到全局向量。
            pos_scores = [pos_scores; pos_this(:)]; %#ok<AGROW>
            neg_scores = [neg_scores; neg_this(:)]; %#ok<AGROW>

            % 有效帧计数 +1。
            n_used = n_used + 1;

        catch ME
            % 单帧异常只 warning，不中断全流程。
            n_skip_algo_err = n_skip_algo_err + 1;
            warning('[%s] 帧 %d 处理失败：%s', alg_name, f, ME.message);
            continue;
        end

        % ------------------------- 9) 进度打印 -------------------------
        if mod(n_done, cfg.print_every) == 0 || n_done == n_total_frames
            % 已耗时。
            elapsed = toc(t_start);
            % 平均每帧耗时（基于尝试帧）。
            avg_t = elapsed / max(n_done, 1);
            % 剩余帧估计。
            eta = avg_t * (n_total_frames - n_done);
            % 打印帧级进度。
            fprintf('[%s] %s: %d/%d 帧, 有效=%d, 耗时=%.1fs, ETA=%.1fs\n', ...
                alg_name, get_seq_name_from_dir(img_dir), n_done, n_total_frames, n_used, elapsed, eta);
        end
    end

    % ------------------------- 10) 打印跳帧汇总日志 -------------------------
    % 统一汇总打印，便于你快速判断“为什么有效帧减少”。
    fprintf('[%s] %s 跳帧汇总: 预裁越界=%d, 运行越界=%d, GT无效=%d, 样本空=%d, 尺寸错=%d, 算法报错=%d\n', ...
        alg_name, get_seq_name_from_dir(img_dir), n_prefilter_oob, n_skip_oob, n_skip_invalid_gt, ...
        n_skip_empty_sample, n_skip_bad_size, n_skip_algo_err);

    % ------------------------- 11) 空结果保护 -------------------------
    % 如果没有任何有效帧，构造空 ROC 并 AUC=NaN。
    if n_used == 0 || isempty(pos_scores) || isempty(neg_scores)
        warning('[%s] 序列 %s 无有效帧。', alg_name, img_dir);
        thresholds = linspace(1, 0, cfg.n_thresholds)';
        TPR = zeros(size(thresholds));
        FPR = zeros(size(thresholds));
        AUC = NaN;
    else
        % 计算 ROC/AUC（内部自带 perfcurve fallback）。
        [FPR, TPR, thresholds, AUC] = compute_roc_auc(pos_scores, neg_scores, cfg.n_thresholds);
    end

    % ------------------------- 12) 输出文件名 -------------------------
    seq_name = get_seq_name_from_dir(img_dir);
    seq_num = sscanf(seq_name, 'data%d');
    if isempty(seq_num)
        seq_num = 0;
    end

    % 统一文件前缀，例如 BLCM_data01。
    prefix = sprintf('%s_data%02d', alg_name, seq_num);

    % ------------------------- 13) 保存 ROC CSV -------------------------
    % ROC 表：threshold, TPR, FPR。
    roc_tbl = table(thresholds(:), TPR(:), FPR(:), 'VariableNames', {'threshold', 'TPR', 'FPR'});
    writetable(roc_tbl, fullfile(cfg.out_dir, [prefix, '_roc.csv']));

    % ------------------------- 14) 保存 ROC 图 -------------------------
    % 线性坐标 + log-x 坐标两张图。
    save_roc_plots(FPR, TPR, AUC, fullfile(cfg.out_dir, [prefix, '_roc.png']), ...
        fullfile(cfg.out_dir, [prefix, '_roc_logx.png']), alg_name, seq_name);

    % ------------------------- 15) 保存 MAT -------------------------
    % 保存关键中间数据与配置，便于复现和审计。
    N_used_frames = n_used; %#ok<NASGU>
    config = cfg; %#ok<NASGU>
    % 把跳帧统计也写入 MAT，方便后续审计与排查。
    skip_stats = struct(); %#ok<NASGU>
    skip_stats.n_prefilter_oob = n_prefilter_oob;
    skip_stats.n_skip_oob = n_skip_oob;
    skip_stats.n_skip_invalid_gt = n_skip_invalid_gt;
    skip_stats.n_skip_empty_sample = n_skip_empty_sample;
    skip_stats.n_skip_bad_size = n_skip_bad_size;
    skip_stats.n_skip_algo_err = n_skip_algo_err;
    save(fullfile(cfg.out_dir, [prefix, '_scores.mat']), ...
        'pos_scores', 'neg_scores', 'AUC', 'N_used_frames', 'row_offset', 'first_valid', ...
        'thresholds', 'TPR', 'FPR', 'config', 'skip_stats', 'f_max');

    % ------------------------- 16) 返回结构体 -------------------------
    result = struct();
    result.AUC = AUC;
    result.thresholds = thresholds;
    result.TPR = TPR;
    result.FPR = FPR;
    result.pos_scores = pos_scores;
    result.neg_scores = neg_scores;
    result.N_used_frames = n_used;
    result.row_offset = row_offset;
    result.first_valid = first_valid;
    result.f_max = f_max;
    result.skip_stats = skip_stats;
end

function seq_name = get_seq_name_from_dir(img_dir)
% get_seq_name_from_dir
% 从路径末级目录提取序列名（例如 .../data1/data1 -> data1）。

    [~, seq_name] = fileparts(img_dir);
end
