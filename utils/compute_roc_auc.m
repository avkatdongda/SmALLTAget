function [FPR, TPR, thresholds, AUC] = compute_roc_auc(pos_scores, neg_scores, n_thresholds)
% compute_roc_auc
% ========================================================================
% 作用：根据正/负样本分数计算 ROC 曲线与 AUC。
% 
% 输入：
%   pos_scores    - 正样本分数向量
%   neg_scores    - 负样本分数向量
%   n_thresholds  - 阈值数量（fallback 阈值扫会用到）
% 
% 输出：
%   FPR, TPR      - ROC 曲线点
%   thresholds    - 对应阈值
%   AUC           - 曲线下面积（trapz 计算）
% 
% 说明：
%   - 如果系统有 perfcurve（Statistics Toolbox），优先使用。
%   - 如果没有 perfcurve，自动 fallback 到纯 MATLAB 实现。
% ========================================================================

    % 强制列向量，避免维度问题。
    pos_scores = pos_scores(:);
    neg_scores = neg_scores(:);

    % 合并标签与分数，便于 perfcurve 调用。
    y = [ones(numel(pos_scores), 1); zeros(numel(neg_scores), 1)];
    s = [pos_scores; neg_scores];

    % 如果存在 perfcurve，则优先使用官方实现。
    if exist('perfcurve', 'file') == 2
        % 以正类标签1计算 ROC。
        [FPR, TPR, thresholds, AUC] = perfcurve(y, s, 1);
        % perfcurve 返回点可能未严格排序，这里按 FPR 升序重排以稳妥计算 trapz。
        [FPR, ord] = sort(FPR(:), 'ascend');
        TPR = TPR(ord);
        thresholds = thresholds(ord);
        % 再次用 trapz 计算，保证与你协议一致。
        AUC = trapz(FPR, TPR);
        return;
    end

    % ------------------------- fallback：手工阈值扫 -------------------------
    % 阈值从 1 到 0 扫描（分数已做过 [0,1] 归一化）。
    thresholds = linspace(1, 0, n_thresholds)';

    % 预分配 TPR/FPR。
    TPR = zeros(n_thresholds, 1);
    FPR = zeros(n_thresholds, 1);

    % 正负样本数量。
    n_pos = numel(pos_scores);
    n_neg = numel(neg_scores);

    % 逐阈值计算。
    for i = 1:n_thresholds
        % 当前阈值。
        t = thresholds(i);
        % 判定为“检测到目标”的条件：score >= t。
        tp = sum(pos_scores >= t);
        fp = sum(neg_scores >= t);
        % 真阳率 = TP / P。
        TPR(i) = tp / max(n_pos, 1);
        % 假阳率 = FP / N。
        FPR(i) = fp / max(n_neg, 1);
    end

    % 为了用 trapz(FPR,TPR) 计算面积，按 FPR 升序排序。
    [FPR, ord] = sort(FPR, 'ascend');
    TPR = TPR(ord);
    thresholds = thresholds(ord);

    % 数值积分得到 AUC。
    AUC = trapz(FPR, TPR);
end
