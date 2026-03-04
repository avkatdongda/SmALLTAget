function [cand_xy, cand_w] = extract_candidates_from_score(S_norm, th)
% extract_candidates_from_score
% ========================================================================
% 作用：在给定阈值下，从单帧 score map 中提取“候选目标点”。
% 
% 输入：
%   S_norm - 已归一化到 [0,1] 的得分图（H×W）
%   th     - 当前阈值
% 
% 输出：
%   cand_xy - N×2，候选点坐标，每行 [x,y] = [列,行]
%   cand_w  - N×1，每个候选点的权重（该连通域内 S_norm 累加）
% 
% 设计说明：
%   1) 先做二值化 BW=(S_norm>=th)
%   2) 再做 2D 连通域 bwconncomp（严禁 3D）
%   3) 每个连通域提取 WeightedCentroid（若不可用退化为 Centroid）
%   4) 连通域总强度作为后续“合并簇中心”加权权重
% ========================================================================

    % 若误传了三维输入，强制取第一通道，保证 2D 连通域。
    if ndims(S_norm) == 3
        S_norm = S_norm(:,:,1);
    end

    % 按阈值生成二值图。
    BW = (S_norm >= th);

    % 连通域提取（8 连通默认足够用于小目标区域）。
    CC = bwconncomp(BW);

    % 若当前阈值下无任何连通域，直接返回空。
    if CC.NumObjects == 0
        cand_xy = zeros(0,2);
        cand_w = zeros(0,1);
        return;
    end

    % 先尝试 WeightedCentroid（首选方案）。
    use_weighted = true;
    try
        stats = regionprops(CC, S_norm, 'WeightedCentroid', 'PixelIdxList');
    catch
        % 若当前 MATLAB 版本/环境不支持该调用，则退化到普通质心。
        use_weighted = false;
        stats = regionprops(CC, 'Centroid', 'PixelIdxList');
    end

    % 预分配输出。
    n = numel(stats);
    cand_xy = zeros(n,2);
    cand_w = zeros(n,1);

    % 逐连通域写入坐标与权重。
    for i = 1:n
        % 根据是否支持 WeightedCentroid 选择字段。
        if use_weighted
            c = stats(i).WeightedCentroid;
        else
            c = stats(i).Centroid;
        end

        % 坐标形式统一为 [x,y] = [col,row]。
        cand_xy(i,1) = c(1);
        cand_xy(i,2) = c(2);

        % 权重定义为该连通域的 S_norm 累加。
        cand_w(i) = sum(S_norm(stats(i).PixelIdxList));
    end
end
