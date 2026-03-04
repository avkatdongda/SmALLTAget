function [gt, row_offset, first_valid, n_rows] = read_gt_with_offset(gt_path)
% read_gt_with_offset
% ========================================================================
% 作用：读取 GT 文本并自动处理“头行/元信息行”导致的 NaN 偏移问题。
% 
% 输入：
%   gt_path - GT 文件路径（dataX.txt）
% 
% 输出：
%   gt         - readmatrix 读出的数值矩阵（N×5 或更宽）
%   row_offset - 行偏移，满足：row = row_offset + frame_id + 1
%   first_valid- 第一个 x/y 均为有限值的行号（1-based）
%   n_rows     - GT 总行数
% ========================================================================

    % 检查文件存在性。
    if exist(gt_path, 'file') ~= 2
        error('GT 文件不存在：%s', gt_path);
    end

    % 使用 readmatrix 读取数值矩阵。
    gt = readmatrix(gt_path);

    % 基础合法性检查：必须至少有5列（第4/5列是 x/y）。
    if size(gt, 2) < 5
        error('GT 文件列数不足5列：%s', gt_path);
    end

    % 找到第一个有效 x/y 行（x=col4, y=row5）。
    first_valid = find(isfinite(gt(:,4)) & isfinite(gt(:,5)), 1, 'first');

    % 若找不到有效行，说明 GT 文件可能损坏。
    if isempty(first_valid)
        error('GT 文件找不到有效的第4/5列坐标：%s', gt_path);
    end

    % 行偏移定义：first_valid = row_offset + 0 + 1 => row_offset = first_valid - 1。
    row_offset = first_valid - 1;

    % GT 总行数。
    n_rows = size(gt, 1);
end
