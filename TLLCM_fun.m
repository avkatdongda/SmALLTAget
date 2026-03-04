function S = TLLCM_fun(I)
% ========================================================================
% TLLCM_fun(I)
% 把你当前的 TLLCM.m（脚本版）封装成函数，便于批量评测调用：S = TLLCM_fun(I)
%
% 输入:
%   I : 单帧灰度图（uint8 / double 均可），尺寸 H×W
%
% 输出:
%   S : TLLCM 的显著图/score map（越大越像目标），尺寸 H×W，double
%
% 原脚本要点（你上传的 TLLCM.m）：
%   1) 读图 img=double(imread("img_address"))
%   2) 3×3 Gaussian 平滑得到 I_core
%   3) 构造 3×3 cell 的 tri-layer 窗口（总大小 27×27，单 cell 为 9×9）
%   4) 对 8 个外环方向 cell，取 top-9 灰度的均值（用 ordfilt2 实现）
%   5) I_mean_out = 8方向均值的最大值（作为背景估计 baseline）
%   6) out = (I_core^2)/I_mean_out - I_core，并截断为非负
%
% 为什么要封装：
%   - 脚本无法用 TLLCM(I) 调用，批量框架需要函数接口。
%   - 去掉 clearvars/close all/imshow，避免每帧清环境与弹窗导致极慢。
% ========================================================================

    % ---------- 0) 输入检查与类型统一 ----------
    % 你数据里有些 bmp 实际可能是 RGB（3通道），这里统一取单通道，避免后续处理变3D
    if ndims(I) == 3
        I = I(:,:,1);
    end
    I = double(I);                         % 统一为 double，ordfilt2/imfilter 更稳定

    % ---------- 1) Gaussian 平滑（与原脚本一致） ----------
    % 原脚本 gauss_krl=[1 2 1;2 4 2;1 2 1]/16
    gauss_krl = [1 2 1; 2 4 2; 1 2 1] / 16;
    I_core = imfilter(I, gauss_krl, 'replicate');
    % 为什么要平滑：抑制 PNHB 噪点，让目标更像"连续小斑块"，增强 top-order 的稳定性

    % ---------- 2) 构造 8 个方向的 mask（27×27，每个 mask 只有一个 9×9 block 为1） ----------
    % 这一步对应你脚本里的 m91..m98
    % tri-layer window：3×3 block，每块大小=9，整体 27
    b = 9;                                 % block size（固定为 9：你脚本写死 9×9）
    W = 3*b;                               % 27
    masks = cell(1,8);                     % 8个方向：TL,T,TR,R,BR,B,BL,L

    % 左上
    m = zeros(W); m(1:b, 1:b) = 1;         masks{1} = m;
    % 上
    m = zeros(W); m(1:b, b+1:2*b) = 1;     masks{2} = m;
    % 右上
    m = zeros(W); m(1:b, 2*b+1:3*b) = 1;   masks{3} = m;
    % 右
    m = zeros(W); m(b+1:2*b, 2*b+1:3*b) = 1; masks{4} = m;
    % 右下
    m = zeros(W); m(2*b+1:3*b, 2*b+1:3*b) = 1; masks{5} = m;
    % 下
    m = zeros(W); m(2*b+1:3*b, b+1:2*b) = 1; masks{6} = m;
    % 左下
    m = zeros(W); m(2*b+1:3*b, 1:b) = 1;   masks{7} = m;
    % 左
    m = zeros(W); m(b+1:2*b, 1:b) = 1;     masks{8} = m;

    % ---------- 3) 计算 8 个方向 cell 的 top-9 均值（更省内存的写法） ----------
    % 你脚本是 I11(:,:,i)=ordfilt2(...,82-i,mask) 然后 mean(...,3)
    % 这里等价，但不保存 256×256×9 的大数组，直接累加求均值，速度/内存更友好。
    K = 9;                                 % top-9（与你脚本一致）
    H = size(I,1); Wimg = size(I,2);       % 图像尺寸
    I_mean_dir = zeros(H, Wimg, 8);        % 每个方向一个均值图

    for d = 1:8
        acc = zeros(H, Wimg);              % 累加器：累计 top-9 的和
        for j = 1:K
            % 原脚本 order = 82 - i, i=1..9 => 81..73
            % 这里 j=1..9 => order=81..73，完全等价
            ord = 82 - j;

            % ordfilt2 的 order 是"第 ord 大"（mask 中 1 的位置作为候选集合）
            acc = acc + ordfilt2(I, ord, masks{d});
        end
        I_mean_dir(:,:,d) = acc / K;       % top-9 的均值
    end

    % ---------- 4) 背景 baseline：8方向取最大（与原脚本一致） ----------
    I_mean_out = max(I_mean_dir, [], 3);

    % 防止除0：如果某些位置 baseline 为 0，会导致 Inf
    I_mean_out = max(I_mean_out, eps);

    % ---------- 5) TLLCM 输出（与你脚本 out=((I_core^2)/I_mean_out)-I_core 一致） ----------
    S = (I_core.^2) ./ I_mean_out - I_core;

    % 只保留正响应（小目标希望为正；负值通常是背景抑制后的残差）
    S(S < 0) = 0;

end