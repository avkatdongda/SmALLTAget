function [cand_xy_merged, cand_w_merged] = merge_candidates_by_distance(cand_xy, cand_w, r_merge)
% merge_candidates_by_distance
% ========================================================================
% 作用：对候选点做“近邻合并（传递闭包）”，防止目标裂解成多个候选导致 FP 虚高。
% 
% 输入：
%   cand_xy - N×2 候选点坐标 [x,y]
%   cand_w  - N×1 候选点权重
%   r_merge - 合并半径（欧氏距离 <= r_merge 视为同一簇）
% 
% 输出：
%   cand_xy_merged - M×2 合并后簇中心 [x,y]
%   cand_w_merged  - M×1 合并后簇权重（簇内权重和）
% 
% 关键：
%   - 使用“连通分量思想”实现传递闭包：A近B、B近C => A/B/C 同簇。
%   - 簇中心采用权重加权平均，更稳定。
% ========================================================================

    % 空输入直接返回空。
    if isempty(cand_xy)
        cand_xy_merged = zeros(0,2);
        cand_w_merged = zeros(0,1);
        return;
    end

    % 若权重缺失，默认全1。
    if nargin < 2 || isempty(cand_w)
        cand_w = ones(size(cand_xy,1),1);
    end

    % 点数量。
    n = size(cand_xy,1);

    % 建立邻接矩阵：dist<=r_merge 视为有边。
    A = false(n,n);
    for i = 1:n
        % 与自身有边。
        A(i,i) = true;
        for j = i+1:n
            % 计算欧氏距离。
            d = hypot(cand_xy(i,1)-cand_xy(j,1), cand_xy(i,2)-cand_xy(j,2));
            if d <= r_merge
                A(i,j) = true;
                A(j,i) = true;
            end
        end
    end

    % 使用图连通分量求簇标签。
    G = graph(A);
    comp_id = conncomp(G);

    % 唯一簇编号。
    u = unique(comp_id);
    m = numel(u);

    % 预分配输出。
    cand_xy_merged = zeros(m,2);
    cand_w_merged = zeros(m,1);

    % 逐簇计算加权中心。
    for k = 1:m
        % 当前簇成员索引。
        idx = find(comp_id == u(k));

        % 提取簇内坐标与权重。
        pts = cand_xy(idx,:);
        w = cand_w(idx);

        % 防止全零权重导致除0。
        wsum = sum(w);
        if wsum <= 0
            w = ones(size(w));
            wsum = sum(w);
        end

        % 加权中心（x/y 分别加权）。
        cx = sum(pts(:,1).*w) / wsum;
        cy = sum(pts(:,2).*w) / wsum;

        % 写入输出。
        cand_xy_merged(k,:) = [cx, cy];
        cand_w_merged(k) = wsum;
    end
end
