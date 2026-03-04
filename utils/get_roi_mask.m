function roi_mask = get_roi_mask(x, y, roi_r, H, W)
% get_roi_mask
% ========================================================================
% 作用：根据 GT 点坐标生成 ROI 掩膜。
% 
% 输入：
%   x     - 列坐标（col）
%   y     - 行坐标（row）
%   roi_r - ROI 半径（4 -> 9x9）
%   H, W  - 图像尺寸
% 
% 输出：
%   roi_mask - H×W 逻辑矩阵，true 表示 ROI 内像素
% ========================================================================

    % 先把 x/y 四舍五入到最近整数像素。
    x = round(x);
    y = round(y);

    % 将中心点裁剪到图像范围内，防止越界。
    x = min(max(x, 1), W);
    y = min(max(y, 1), H);

    % ROI 的行范围：[y-roi_r, y+roi_r]，并裁剪到 [1,H]。
    r1 = max(1, y - roi_r);
    r2 = min(H, y + roi_r);

    % ROI 的列范围：[x-roi_r, x+roi_r]，并裁剪到 [1,W]。
    c1 = max(1, x - roi_r);
    c2 = min(W, x + roi_r);

    % 初始化全 false 掩膜。
    roi_mask = false(H, W);
    % ROI 区域置 true。
    roi_mask(r1:r2, c1:c2) = true;
end
