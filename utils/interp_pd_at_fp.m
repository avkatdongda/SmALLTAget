function pd_val = interp_pd_at_fp(FPu, PDu, fp_thr)
% interp_pd_at_fp
% ========================================================================
% 作用：从目标级 envelope 曲线上提取 "Pd@FP<=阈值"。
% 
% 输入：
%   FPu, PDu - envelope 曲线点（FP升序，Pd单调不降）
%   fp_thr   - FP/frame 阈值（例如 0.5）
% 
% 输出：
%   pd_val   - 满足 FP<=fp_thr 的最大 Pd
% ========================================================================

    % 若曲线为空，返回 NaN。
    if isempty(FPu) || isempty(PDu)
        pd_val = NaN;
        return;
    end

    % 找到所有 FP<=阈值的点。
    idx = find(FPu <= fp_thr);

    % 若一个点都没有，按协议取 0。
    if isempty(idx)
        pd_val = 0;
        return;
    end

    % 取该范围内最大 Pd（等价于末点，因为已单调化）。
    pd_val = max(PDu(idx));
end
