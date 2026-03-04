function result = eval_one_alg_one_seq_roc(alg_name, alg_fun, img_dir, gt_path, cfg)
% eval_one_alg_one_seq_roc
% ========================================================================
% 作用：执行“单算法 × 单序列”的完整评测，包含两套指标：
%   1) 像素级 ROC/AUC（ROI内像素 vs ROI外采样像素）
%   2) 目标级 Pd-FP/frame（连通域候选 + 近邻合并 + 命中/误检统计）
% ========================================================================

    % ------------------------- 1) 读取 GT 并解析 offset -------------------------
    [gt, row_offset, first_valid, n_gt_rows] = read_gt_with_offset(gt_path);

    % ------------------------- 2) 枚举图像并解析帧号 -------------------------
    files = dir(fullfile(img_dir, '*.bmp'));
    if isempty(files)
        error('图像目录为空：%s', img_dir);
    end

    frame_ids = nan(numel(files),1);
    for i = 1:numel(files)
        [~, nm, ~] = fileparts(files(i).name);
        frame_ids(i) = str2double(nm);
    end

    valid_file_mask = isfinite(frame_ids);
    files = files(valid_file_mask);
    frame_ids = frame_ids(valid_file_mask);

    [frame_ids, ord] = sort(frame_ids, 'ascend');
    files = files(ord);

    % ------------------------- 3) GT 可映射范围预裁剪 -------------------------
    f_max = n_gt_rows - row_offset - 1;
    map_ok_mask = frame_ids <= f_max;
    n_prefilter_oob = sum(~map_ok_mask);
    files = files(map_ok_mask);
    frame_ids = frame_ids(map_ok_mask);

    % ------------------------- 4) 抽帧与帧数限制 -------------------------
    stride_mask = mod(frame_ids, cfg.frame_stride) == 0;
    files = files(stride_mask);
    frame_ids = frame_ids(stride_mask);

    if cfg.max_frames_per_seq > 0
        keep_n = min(cfg.max_frames_per_seq, numel(frame_ids));
        files = files(1:keep_n);
        frame_ids = frame_ids(1:keep_n);
    end

    n_total_frames = numel(frame_ids);

    % ------------------------- 5) 像素级容器 -------------------------
    pos_scores = [];
    neg_scores = [];

    % ------------------------- 6) 目标级容器 -------------------------
    th_list = cfg.th_list_target(:);
    n_th = numel(th_list);
    hit_counts = zeros(n_th,1);
    fp_counts = zeros(n_th,1);

    % ------------------------- 7) 计数器与随机种子 -------------------------
    n_used = 0;
    n_done = 0;
    t_start = tic;

    n_skip_oob = 0;
    n_skip_invalid_gt = 0;
    n_skip_empty_sample = 0;
    n_skip_bad_size = 0;
    n_skip_algo_err = 0;

    seed = cfg.rng_seed + sum(double(alg_name)) + numel(img_dir);
    rng(seed);

    % ------------------------- 8) 逐帧处理 -------------------------
    for k = 1:n_total_frames
        n_done = n_done + 1;
        f = frame_ids(k);

        gt_row = row_offset + f + 1;
        if gt_row < 1 || gt_row > n_gt_rows
            n_skip_oob = n_skip_oob + 1;
            continue;
        end

        % x=列, y=行
        x = gt(gt_row,4);
        y = gt(gt_row,5);
        if ~isfinite(x) || ~isfinite(y)
            n_skip_invalid_gt = n_skip_invalid_gt + 1;
            continue;
        end

        img_path = fullfile(files(k).folder, files(k).name);

        try
            I = imread(img_path);
            if ndims(I) == 3
                I = I(:,:,1);
            end
            I = double(I);

            S = alg_fun(I);
            if ~isequal(size(S), size(I))
                n_skip_bad_size = n_skip_bad_size + 1;
                continue;
            end

            % 每帧 min-max 归一化（两套评测共享同一个 S_norm）。
            S = S - min(S(:));
            S = S / (max(S(:)) + eps);

            H = size(I,1);
            W = size(I,2);
            roi_mask = get_roi_mask(x, y, cfg.roi_r, H, W);

            % ------------------- 8.1 像素级统计 -------------------
            pos_this = S(roi_mask);
            neg_this = sample_neg_pixels(S, roi_mask, cfg.neg_sample_per_frame);
            if isempty(pos_this) || isempty(neg_this)
                n_skip_empty_sample = n_skip_empty_sample + 1;
                continue;
            end
            pos_scores = [pos_scores; pos_this(:)]; %#ok<AGROW>
            neg_scores = [neg_scores; neg_this(:)]; %#ok<AGROW>

            % ------------------- 8.2 目标级统计 -------------------
            % 对全局阈值列表逐阈值做：连通域->质心候选->近邻合并->命中/误检。
            for ti = 1:n_th
                th = th_list(ti);

                % 候选提取（WeightedCentroid 优先，失败退化 Centroid）。
                [cand_xy, cand_w] = extract_candidates_from_score(S, th);

                % 近邻合并（防止一个目标被多个碎片候选重复计为 FP）。
                [cand_xy_m, ~] = merge_candidates_by_distance(cand_xy, cand_w, cfg.r_merge);

                % 没有候选：既不命中，也无误检。
                if isempty(cand_xy_m)
                    continue;
                end

                % 与 GT 的 Chebyshev 距离（max(|dx|,|dy|)）判定是否落入9x9 ROI。
                dx = abs(cand_xy_m(:,1) - x);
                dy = abs(cand_xy_m(:,2) - y);
                in_roi = max(dx, dy) <= cfg.roi_r;

                % 命中判据：存在任一候选落在 ROI 内则该帧命中。
                if any(in_roi)
                    hit_counts(ti) = hit_counts(ti) + 1;
                end

                % 误检数：ROI 外候选数量。
                fp_counts(ti) = fp_counts(ti) + sum(~in_roi);
            end

            % 有效帧计数 +1。
            n_used = n_used + 1;

        catch ME
            n_skip_algo_err = n_skip_algo_err + 1;
            warning('[%s] 帧 %d 处理失败：%s', alg_name, f, ME.message);
            continue;
        end

        if mod(n_done, cfg.print_every) == 0 || n_done == n_total_frames
            elapsed = toc(t_start);
            avg_t = elapsed / max(n_done, 1);
            eta = avg_t * (n_total_frames - n_done);
            fprintf('[%s] %s: %d/%d 帧, 有效=%d, 耗时=%.1fs, ETA=%.1fs\n', ...
                alg_name, get_seq_name_from_dir(img_dir), n_done, n_total_frames, n_used, elapsed, eta);
        end
    end

    % ------------------------- 9) 跳帧汇总日志 -------------------------
    fprintf('[%s] %s 跳帧汇总: 预裁越界=%d, 运行越界=%d, GT无效=%d, 样本空=%d, 尺寸错=%d, 算法报错=%d\n', ...
        alg_name, get_seq_name_from_dir(img_dir), n_prefilter_oob, n_skip_oob, n_skip_invalid_gt, ...
        n_skip_empty_sample, n_skip_bad_size, n_skip_algo_err);

    % ------------------------- 10) 像素级 ROC/AUC -------------------------
    if n_used == 0 || isempty(pos_scores) || isempty(neg_scores)
        warning('[%s] 序列 %s 无有效帧。', alg_name, img_dir);
        thresholds = linspace(1, 0, cfg.n_thresholds)';
        TPR = zeros(size(thresholds));
        FPR = zeros(size(thresholds));
        AUC = NaN;
    else
        [FPR, TPR, thresholds, AUC] = compute_roc_auc(pos_scores, neg_scores, cfg.n_thresholds);
    end

    % ------------------------- 11) 目标级 Pd-FP/frame -------------------------
    if n_used == 0
        Pd_raw = zeros(size(th_list));
        FPf_raw = zeros(size(th_list));
    else
        Pd_raw = hit_counts / n_used;
        FPf_raw = fp_counts / n_used;
    end

    % 按要求做 envelope/cummax 后处理，得到可比曲线。
    [FPu_target, PDu_target] = build_target_curve_envelope(FPf_raw, Pd_raw);

    % 固定统计指标：Pd@FP<=0.25/0.5/1/2。
    Pd_at_FP_025 = interp_pd_at_fp(FPu_target, PDu_target, 0.25);
    Pd_at_FP_05  = interp_pd_at_fp(FPu_target, PDu_target, 0.5);
    Pd_at_FP_1   = interp_pd_at_fp(FPu_target, PDu_target, 1.0);
    Pd_at_FP_2   = interp_pd_at_fp(FPu_target, PDu_target, 2.0);

    % ------------------------- 12) 文件前缀 -------------------------
    seq_name = get_seq_name_from_dir(img_dir);
    seq_num = sscanf(seq_name, 'data%d');
    if isempty(seq_num)
        seq_num = 0;
    end
    prefix = sprintf('%s_data%02d', alg_name, seq_num);

    % ------------------------- 13) 保存像素级文件 -------------------------
    roc_tbl = table(thresholds(:), TPR(:), FPR(:), 'VariableNames', {'threshold', 'TPR', 'FPR'});
    writetable(roc_tbl, fullfile(cfg.out_dir, [prefix, '_roc.csv']));

    save_roc_plots(FPR, TPR, AUC, fullfile(cfg.out_dir, [prefix, '_roc.png']), ...
        fullfile(cfg.out_dir, [prefix, '_roc_logx.png']), alg_name, seq_name);

    % ------------------------- 14) 保存目标级文件 -------------------------
    target_tbl = table(FPu_target(:), PDu_target(:), 'VariableNames', {'FP_per_frame', 'Pd'});
    writetable(target_tbl, fullfile(cfg.out_dir, [prefix, '_target_curve.csv']));

    save_target_plot(FPf_raw, Pd_raw, FPu_target, PDu_target, ...
        fullfile(cfg.out_dir, [prefix, '_target.png']), alg_name, seq_name);

    % ------------------------- 15) 保存 MAT -------------------------
    N_used_frames = n_used; %#ok<NASGU>
    config = cfg; %#ok<NASGU>
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

    save(fullfile(cfg.out_dir, [prefix, '_target.mat']), ...
        'th_list', 'FPf_raw', 'Pd_raw', 'FPu_target', 'PDu_target', ...
        'Pd_at_FP_025', 'Pd_at_FP_05', 'Pd_at_FP_1', 'Pd_at_FP_2', 'N_used_frames', 'config');

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

    result.th_list = th_list;
    result.FPf_raw = FPf_raw;
    result.Pd_raw = Pd_raw;
    result.FPu_target = FPu_target;
    result.PDu_target = PDu_target;
    result.Pd_at_FP_025 = Pd_at_FP_025;
    result.Pd_at_FP_05 = Pd_at_FP_05;
    result.Pd_at_FP_1 = Pd_at_FP_1;
    result.Pd_at_FP_2 = Pd_at_FP_2;
end

function seq_name = get_seq_name_from_dir(img_dir)
% get_seq_name_from_dir
% 从路径末级目录提取序列名（例如 .../data1/data1 -> data1）。
    [~, seq_name] = fileparts(img_dir);
end
