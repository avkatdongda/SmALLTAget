function neg_scores = sample_neg_pixels(S, roi_mask, max_neg)
% sample_neg_pixels
% ========================================================================
% 作用：从 ROI 外像素中随机采样负样本分数，避免内存爆炸。
% 
% 输入：
%   S        - score map（H×W）
%   roi_mask - ROI 掩膜（true 为正样本区域）
%   max_neg  - 每帧最多采样的负样本数量
% 
% 输出：
%   neg_scores - 采样得到的负样本分数列向量
% ========================================================================

    % 负样本区域是 ROI 外。
    neg_mask = ~roi_mask;

    % 拉平后获取所有负样本分数。
    neg_all = S(neg_mask);

    % 若没有负样本，直接返回空。
    if isempty(neg_all)
        neg_scores = [];
        return;
    end

    % 如果负样本总数 <= 上限，则全保留（无需采样）。
    if numel(neg_all) <= max_neg
        neg_scores = neg_all(:);
        return;
    end

    % 否则随机无放回采样 max_neg 个索引。
    idx = randperm(numel(neg_all), max_neg);

    % 取采样结果并转列向量。
    neg_scores = neg_all(idx);
    neg_scores = neg_scores(:);
end
