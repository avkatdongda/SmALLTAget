function save_target_plot(FPf_raw, Pd_raw, FPu, PDu, png_path, alg_name, seq_name)
% save_target_plot
% ========================================================================
% 作用：保存单算法单序列的目标级 Pd-FP/frame 曲线图。
% 图中同时包含：
%   - raw 点（阈值扫描原始散点）
%   - envelope 线（可比性曲线）
% ========================================================================

    % 新建不可见图窗，批处理不弹窗。
    fig = figure('Visible', 'off');

    % raw 散点（浅灰色）。
    scatter(FPf_raw, Pd_raw, 14, [0.65 0.65 0.65], 'filled');
    hold on;

    % envelope 曲线（蓝色粗线）。
    plot(FPu, PDu, 'b-', 'LineWidth', 1.8);

    % 坐标标签与标题。
    xlabel('FP / frame');
    ylabel('Pd');
    title(sprintf('%s | %s | Target-level Pd-FP/frame', alg_name, seq_name));

    % 范围与网格。
    ylim([0,1]);
    xlim([0, max([1; FPu(:)+eps])]);
    grid on;

    % 图例放在右下，尽量不遮挡主区域。
    legend({'raw(th sweep)', 'envelope'}, 'Location', 'southeast');

    % 保存并关闭。
    exportgraphics(fig, png_path, 'Resolution', 150);
    close(fig);
end
