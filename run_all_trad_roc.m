function run_all_trad_roc()
% run_all_trad_roc
% ========================================================================
% 主入口：一键运行像素级 ROC + 目标级 Pd-FP/frame，并输出单算法结果和叠加图。
% ========================================================================

    % ------------------------- 0) 基础路径配置 -------------------------
    cfg.root_dir = "E:/dimifrdata";
    cfg.baseline_root = fullfile(cfg.root_dir, "baselines");
    cfg.out_dir = "E:/dimifrdata/results_trad_roc";

    % ------------------------- 1) 评测参数 -------------------------
    cfg.seq_ids = 1:10;
    cfg.frame_stride = 5;
    cfg.max_frames_per_seq = 200;
    cfg.roi_r = 4;
    cfg.neg_sample_per_frame = 20000;
    cfg.rng_seed = 0;
    cfg.use_parallel = false;
    cfg.print_every = 10;
    cfg.n_thresholds = 2000;
    cfg.quick_test = false;

    % 目标级评测参数：阈值扫描列表与近邻合并半径。
    cfg.th_list_target = linspace(0, 1, 80);
    cfg.r_merge = 3;

    % quick test：只跑 data1 + 前20帧 + 前2算法。
    if cfg.quick_test
        cfg.seq_ids = 1;
        cfg.frame_stride = 1;
        cfg.max_frames_per_seq = 20;
    end

    % ------------------------- 2) 环境准备 -------------------------
    rng(cfg.rng_seed);
    addpath(genpath(cfg.baseline_root));
    addpath(genpath(fileparts(mfilename('fullpath'))));
    if ~exist(cfg.out_dir, 'dir')
        mkdir(cfg.out_dir);
    end

    % ------------------------- 3) 算法注册 -------------------------
    algs = registry_trad_algorithms(cfg.baseline_root);
    if cfg.quick_test
        algs = algs(1:min(2, numel(algs)));
    end

    n_alg = numel(algs);
    n_seq = numel(cfg.seq_ids);

    % AUC 与目标级指标矩阵。
    auc_mat = nan(n_alg, n_seq);
    pd05_mat = nan(n_alg, n_seq);
    pd1_mat = nan(n_alg, n_seq);

    % 用 cell 保存每个算法×序列的曲线，供 overlay 与 overall 平均使用。
    pixel_curves = cell(n_alg, n_seq);
    target_curves = cell(n_alg, n_seq);

    % ------------------------- 4) 主循环：按序列组织 -------------------------
    for si = 1:n_seq
        seq_id = cfg.seq_ids(si);
        seq_name = sprintf('data%d', seq_id);

        fprintf('\n==================== 序列 %s (%d/%d) ====================\n', seq_name, si, n_seq);

        for ai = 1:n_alg
            alg_name = algs(ai).name;
            alg_fun = algs(ai).fun;

            fprintf('[%s] 处理序列 %s\n', alg_name, seq_name);

            result = run_one_seq(alg_name, alg_fun, seq_id, cfg);

            auc_mat(ai, si) = result.AUC;
            pd05_mat(ai, si) = result.Pd_at_FP_05;
            pd1_mat(ai, si) = result.Pd_at_FP_1;

            pixel_curves{ai, si} = struct('FPR', result.FPR(:), 'TPR', result.TPR(:), 'AUC', result.AUC);
            target_curves{ai, si} = struct('FP', result.FPu_target(:), 'Pd', result.PDu_target(:), ...
                'Pd05', result.Pd_at_FP_05, 'Pd1', result.Pd_at_FP_1);

            fprintf('[%s] %s 完成，AUC=%.6f，Pd@FP<=0.5=%.4f\n', alg_name, seq_name, result.AUC, result.Pd_at_FP_05);
        end

        % ------------------- 4.1 生成该序列的 4 张 overlay 图 -------------------
        save_overlay_for_one_seq(cfg.out_dir, seq_id, algs, pixel_curves(:,si), target_curves(:,si));

        % ------------------- 4.2 命令行打印 Top3 -------------------
        print_top3_for_seq(seq_name, algs, auc_mat(:,si), pd05_mat(:,si));
    end

    % ------------------------- 5) 汇总表 -------------------------
    write_summary_tables(cfg.out_dir, cfg.seq_ids, algs, auc_mat, pd05_mat, pd1_mat);

    % ------------------------- 6) 全局平均叠加图 -------------------------
    save_overall_mean_overlays(cfg.out_dir, algs, pixel_curves, target_curves);

    fprintf('\n全部任务完成，输出目录：%s\n', cfg.out_dir);
end

function result = run_one_seq(alg_name, alg_fun, seq_id, cfg)
% run_one_seq
% 单算法单序列执行包装，负责路径拼接。

    seq_name = sprintf('data%d', seq_id);
    img_dir = fullfile(cfg.root_dir, seq_name, seq_name);
    gt_path = fullfile(cfg.root_dir, 'data_label', sprintf('%s.txt', seq_name));

    result = eval_one_alg_one_seq_roc(alg_name, alg_fun, img_dir, gt_path, cfg);
end

function save_overlay_for_one_seq(out_dir, seq_id, algs, pix_cells, tgt_cells)
% save_overlay_for_one_seq
% 作用：对同一序列叠加所有算法曲线，输出 4 张 overlay 图。

    seq_name = sprintf('data%d', seq_id);

    % ------------------- 1) Pixel ROC overlay (linear) -------------------
    fig1 = figure('Visible', 'off');
    hold on;
    leg1 = cell(numel(algs),1);
    for i = 1:numel(algs)
        c = pix_cells{i};
        plot(c.FPR, c.TPR, 'LineWidth', 1.4);
        leg1{i} = sprintf('%s (AUC=%.3f)', algs(i).name, c.AUC);
    end
    grid on; xlim([0,1]); ylim([0,1]);
    xlabel('FPR'); ylabel('TPR');
    title(sprintf('%s | Pixel ROC Overlay', seq_name));
    legend(leg1, 'Location', 'southeast');
    exportgraphics(fig1, fullfile(out_dir, sprintf('overlay_data%02d_pixelROC.png', seq_id)), 'Resolution', 150);
    close(fig1);

    % ------------------- 2) Pixel ROC overlay (log-x) -------------------
    fig2 = figure('Visible', 'off');
    hold on;
    for i = 1:numel(algs)
        c = pix_cells{i};
        fpr_log = max(c.FPR, 1e-8);
        semilogx(fpr_log, c.TPR, 'LineWidth', 1.4);
    end
    grid on; xlim([1e-8,1]); ylim([0,1]);
    xlabel('FPR (log scale)'); ylabel('TPR');
    title(sprintf('%s | Pixel ROC Overlay (log-x)', seq_name));
    legend(leg1, 'Location', 'southeast');
    exportgraphics(fig2, fullfile(out_dir, sprintf('overlay_data%02d_pixelROC_logx.png', seq_id)), 'Resolution', 150);
    close(fig2);

    % ------------------- 3) Target Pd-FP overlay (linear) -------------------
    fig3 = figure('Visible', 'off');
    hold on;
    leg3 = cell(numel(algs),1);
    for i = 1:numel(algs)
        c = tgt_cells{i};
        plot(c.FP, c.Pd, 'LineWidth', 1.6);
        leg3{i} = sprintf('%s (Pd@FP<=0.5=%.3f)', algs(i).name, c.Pd05);
    end
    grid on; ylim([0,1]);
    xlabel('FP / frame'); ylabel('Pd');
    title(sprintf('%s | Target-level Pd-FP/frame Overlay', seq_name));
    legend(leg3, 'Location', 'southeast');
    exportgraphics(fig3, fullfile(out_dir, sprintf('overlay_data%02d_targetPdFP.png', seq_id)), 'Resolution', 150);
    close(fig3);

    % ------------------- 4) Target Pd-FP overlay (log-x) -------------------
    fig4 = figure('Visible', 'off');
    hold on;
    for i = 1:numel(algs)
        c = tgt_cells{i};
        fp_log = max(c.FP, 1e-6);
        semilogx(fp_log, c.Pd, 'LineWidth', 1.6);
    end
    grid on; xlim([1e-6, max(1, max_cell_fp(tgt_cells))]); ylim([0,1]);
    xlabel('FP / frame (log scale)'); ylabel('Pd');
    title(sprintf('%s | Target-level Pd-FP/frame Overlay (log-x)', seq_name));
    legend(leg3, 'Location', 'southeast');
    exportgraphics(fig4, fullfile(out_dir, sprintf('overlay_data%02d_targetPdFP_logx.png', seq_id)), 'Resolution', 150);
    close(fig4);
end

function v = max_cell_fp(tgt_cells)
% 计算目标级曲线中的最大 FP，用于设置 log-x 上限。
    v = 0;
    for i = 1:numel(tgt_cells)
        c = tgt_cells{i};
        if ~isempty(c.FP)
            v = max(v, max(c.FP));
        end
    end
    if v <= 0
        v = 1;
    end
end

function print_top3_for_seq(seq_name, algs, auc_col, pd05_col)
% print_top3_for_seq
% 每个序列完成后打印 AUC Top3 与 Pd@FP<=0.5 Top3。

    [auc_sorted, ia] = sort(auc_col, 'descend', 'MissingPlacement', 'last');
    [pd_sorted, ip] = sort(pd05_col, 'descend', 'MissingPlacement', 'last');

    k1 = min(3, numel(algs));
    fprintf('--- %s AUC Top%d ---\n', seq_name, k1);
    for t = 1:k1
        fprintf('  %d) %s : %.6f\n', t, algs(ia(t)).name, auc_sorted(t));
    end

    k2 = min(3, numel(algs));
    fprintf('--- %s Pd@FP<=0.5 Top%d ---\n', seq_name, k2);
    for t = 1:k2
        fprintf('  %d) %s : %.6f\n', t, algs(ip(t)).name, pd_sorted(t));
    end
end

function write_summary_tables(out_dir, seq_ids, algs, auc_mat, pd05_mat, pd1_mat)
% write_summary_tables
% 写出 summary_auc.csv / overall_rank.csv / overall_mean_metrics.csv。

    n_alg = numel(algs);
    n_seq = numel(seq_ids);

    % ---------- summary_auc.csv ----------
    var_names = cell(1, n_seq + 2);
    var_names{1} = 'Algorithm';
    for si = 1:n_seq
        var_names{si + 1} = sprintf('data%d', seq_ids(si));
    end
    var_names{end} = 'mean_AUC';

    out_cell = cell(n_alg, n_seq + 2);
    for ai = 1:n_alg
        out_cell{ai,1} = algs(ai).name;
        for si = 1:n_seq
            out_cell{ai,si+1} = auc_mat(ai,si);
        end
        out_cell{ai,end} = mean(auc_mat(ai,:), 'omitnan');
    end
    summary_tbl = cell2table(out_cell, 'VariableNames', var_names);
    writetable(summary_tbl, fullfile(out_dir, 'summary_auc.csv'));

    % ---------- overall_rank.csv ----------
    mean_auc = cell2mat(out_cell(:,end));
    [sorted_mean, ord] = sort(mean_auc, 'descend', 'MissingPlacement', 'last');
    rank_tbl = table((1:n_alg)', string(summary_tbl.Algorithm(ord)), sorted_mean, ...
        'VariableNames', {'Rank', 'Algorithm', 'mean_AUC'});
    writetable(rank_tbl, fullfile(out_dir, 'overall_rank.csv'));

    % ---------- overall_mean_metrics.csv ----------
    alg_names = strings(n_alg,1);
    mean_auc_v = nan(n_alg,1);
    mean_pd05_v = nan(n_alg,1);
    mean_pd1_v = nan(n_alg,1);
    for ai = 1:n_alg
        alg_names(ai) = string(algs(ai).name);
        mean_auc_v(ai) = mean(auc_mat(ai,:), 'omitnan');
        mean_pd05_v(ai) = mean(pd05_mat(ai,:), 'omitnan');
        mean_pd1_v(ai) = mean(pd1_mat(ai,:), 'omitnan');
    end
    mean_tbl = table(alg_names, mean_auc_v, mean_pd05_v, mean_pd1_v, ...
        'VariableNames', {'Algorithm','mean_AUC','mean_Pd_at_FP_le_0p5','mean_Pd_at_FP_le_1'});
    writetable(mean_tbl, fullfile(out_dir, 'overall_mean_metrics.csv'));
end

function save_overall_mean_overlays(out_dir, algs, pixel_curves, target_curves)
% save_overall_mean_overlays
% 作用：Across datasets 做平均叠加图。

    n_alg = numel(algs);
    n_seq = size(pixel_curves, 2);

    % ------------------- overall pixelROC mean -------------------
    fpr_grid = linspace(0, 1, 600);
    fig1 = figure('Visible', 'off');
    hold on;
    for ai = 1:n_alg
        tmp = nan(n_seq, numel(fpr_grid));
        for si = 1:n_seq
            c = pixel_curves{ai,si};
            if isempty(c) || isempty(c.FPR)
                continue;
            end
            [x, ux] = unique(c.FPR(:), 'stable');
            y = c.TPR(ux);
            tmp(si,:) = interp1(x, y, fpr_grid, 'linear', 'extrap');
        end
        mtpr = mean(tmp, 1, 'omitnan');
        mtpr = min(max(mtpr, 0), 1);
        plot(fpr_grid, mtpr, 'LineWidth', 1.6);
    end
    grid on; xlim([0,1]); ylim([0,1]);
    xlabel('FPR'); ylabel('Mean TPR');
    title('Overall Mean Pixel ROC (data1..data10)');
    legend(string({algs.name}), 'Location', 'southeast');
    exportgraphics(fig1, fullfile(out_dir, 'overall_pixelROC_mean.png'), 'Resolution', 150);
    close(fig1);

    % ------------------- overall target Pd-FP mean -------------------
    fp_grid = linspace(0, 2, 400);
    fig2 = figure('Visible', 'off');
    hold on;
    for ai = 1:n_alg
        tmp = nan(n_seq, numel(fp_grid));
        for si = 1:n_seq
            c = target_curves{ai,si};
            if isempty(c) || isempty(c.FP)
                continue;
            end
            [x, ux] = unique(c.FP(:), 'stable');
            y = c.Pd(ux);
            tmp(si,:) = interp1(x, y, fp_grid, 'linear', 'extrap');
        end
        mpd = mean(tmp, 1, 'omitnan');
        mpd = min(max(mpd, 0), 1);
        plot(fp_grid, mpd, 'LineWidth', 1.6);
    end
    grid on; ylim([0,1]);
    xlabel('FP / frame'); ylabel('Mean Pd');
    title('Overall Mean Target-level Pd-FP/frame (data1..data10)');
    legend(string({algs.name}), 'Location', 'southeast');
    exportgraphics(fig2, fullfile(out_dir, 'overall_targetPdFP_mean.png'), 'Resolution', 150);
    close(fig2);
end
