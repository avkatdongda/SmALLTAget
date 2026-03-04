function save_roc_plots(FPR, TPR, AUC, png_linear, png_logx, alg_name, seq_name)
% save_roc_plots
% ========================================================================
% 作用：保存两张 ROC 图。
%   1) 线性坐标 ROC（FPR 0~1）
%   2) 对数 x 轴 ROC（低误警区域更清晰）
% 
% 输入：
%   FPR, TPR   - ROC 曲线点
%   AUC        - 面积值
%   png_linear - 线性图输出路径
%   png_logx   - log-x 图输出路径
%   alg_name   - 算法名（用于标题）
%   seq_name   - 序列名（用于标题）
% ========================================================================

    % ------------------------- 1) 线性 ROC 图 -------------------------
    % 新建不可见图窗（批处理时不弹窗）。
    fig1 = figure('Visible', 'off');
    % 绘制 ROC 曲线。
    plot(FPR, TPR, 'b-', 'LineWidth', 1.5);
    hold on;
    % 画对角线作为随机参考。
    plot([0, 1], [0, 1], 'k--', 'LineWidth', 1);
    hold off;
    % 设置坐标范围。
    xlim([0, 1]);
    ylim([0, 1]);
    % 网格与标签。
    grid on;
    xlabel('FPR');
    ylabel('TPR');
    % 标题包含算法、序列、AUC。
    title(sprintf('%s | %s | ROC (AUC=%.6f)', alg_name, seq_name, AUC));
    % 保存 PNG。
    exportgraphics(fig1, png_linear, 'Resolution', 150);
    % 关闭图窗释放内存。
    close(fig1);

    % ------------------------- 2) log-x ROC 图 -------------------------
    % FPR=0 在对数轴不可显示，需做下限夹紧。
    fpr_log = max(FPR, 1e-6);

    % 新建不可见图窗。
    fig2 = figure('Visible', 'off');
    % semilogx 绘图（x轴对数）。
    semilogx(fpr_log, TPR, 'r-', 'LineWidth', 1.5);
    hold on;
    % 参考线（同样用对数 x 画一条）。
    semilogx([1e-6, 1], [1e-6, 1], 'k--', 'LineWidth', 1);
    hold off;
    % 设置坐标范围。
    xlim([1e-6, 1]);
    ylim([0, 1]);
    % 网格与标签。
    grid on;
    xlabel('FPR (log scale)');
    ylabel('TPR');
    % 标题说明是低误警视角。
    title(sprintf('%s | %s | ROC log-x (AUC=%.6f)', alg_name, seq_name, AUC));
    % 保存 PNG。
    exportgraphics(fig2, png_logx, 'Resolution', 150);
    % 关闭图窗。
    close(fig2);
end
