function [FPu, PDu] = build_target_curve_envelope(FPf_raw, Pd_raw)
% build_target_curve_envelope
% ========================================================================
% 作用：对目标级原始曲线点做“可比性后处理”，得到单调 envelope。
% 
% 输入：
%   FPf_raw - 原始 FP/frame 序列
%   Pd_raw  - 原始 Pd 序列
% 
% 输出：
%   FPu - 去重/排序后的 FP/frame 轴
%   PDu - 对应 envelope Pd（单调不下降）
% 
% 处理步骤（严格按要求）：
%   1) 先按 FPf 升序排序
%   2) 相同 FPf 只保留最大 Pd（上包络）
%   3) 再做 cummax，保证 Pd 随 FP 不下降
% ========================================================================

    % 转列向量，统一形状。
    FPf_raw = FPf_raw(:);
    Pd_raw = Pd_raw(:);

    % 先按 FPf 升序排序。
    [FPs, ord] = sort(FPf_raw, 'ascend');
    Pds = Pd_raw(ord);

    % 对相同 FP 值分组，保留该组最大 Pd。
    [FPu, ~, gid] = unique(FPs, 'stable');
    PDu = zeros(size(FPu));
    for i = 1:numel(FPu)
        PDu(i) = max(Pds(gid == i));
    end

    % 用 cummax 单调化，避免“回头线”。
    PDu = cummax(PDu);
end
