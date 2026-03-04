function S = WSLCM_fun(I)
% ========================================================================
% WSLCM_fun(I)
% 把你当前 WSLCM.m（脚本版）封装成函数：S = WSLCM_fun(I)
%
% 输入:
%   I : 单帧灰度图（uint8/double均可），尺寸 H×W
%
% 输出:
%   S : Multi-scale WSLCM 的显著图/score map（越大越像目标），H×W double
%
% 原脚本逻辑（你上传的 WSLCM.m）：
%   1) 高斯平滑 I_gauss
%   2) scs=[5,7,9,11] 多尺度
%   3) 每尺度：
%       - 用 create_mask(s) 构造 8 个方向 mask（每个 mask 内恰好 s^2 个1）
%       - 对中心 cell(ones(s)) 和 8方向 cell(mask) 做 top-K(=9) order-statistics 均值
%       - 得到 M0, M1..M8；同时计算 mean0, mean1..8（普通均值）
%       - BE = max(M1..M8)
%       - SLCM = (I_gauss^2)/BE - I_gauss, 取正
%       - IRIL0=M0-mean0, IRILi=Mi-meani
%       - WD = IRIL0 - max(IRILi), 取正
%       - WB = std(IRILi), 下界 xi=5
%       - W = (IRIL0.*WD)./WB
%       - WSLCM = W.*SLCM
%   4) 多尺度融合：max(Fout,[],3)
%
% 为什么封装：
%   - 脚本不能 WSLCM(I) 调用，无法接入批量框架
%   - 去掉 clearvars/close all/imshow，避免每帧重置+弹窗导致极慢
%   - 内置 create_mask，避免你缺依赖文件时报错
% ========================================================================

    % ---------- 0) 输入处理 ----------
    if ndims(I) == 3
        I = I(:,:,1);                      % 统一单通道
    end
    I = double(I);                         % 统一 double

    H = size(I,1); W = size(I,2);

    % ---------- 1) Gaussian 平滑（与你脚本一致） ----------
    gauss_krl = [1 2 1; 2 4 2; 1 2 1] / 16;
    I_gauss = imfilter(I, gauss_krl, 'replicate');

    % ---------- 2) 多尺度设置 ----------
    scs = [5 7 9 11];                      % 你脚本里的尺度
    itter = numel(scs);                    % 尺度数
    K = 9;                                 % top-9（与你脚本一致）
    xi = 5;                                % WB 的下界（与你脚本一致）

    % 保存每个尺度的结果
    Fout = zeros(H, W, itter);

    % ====================================================================
    % 3) 多尺度循环
    % ====================================================================
    for si = 1:itter
        s = scs(si);                       % 当前尺度（中心cell大小 s×s）

        % --- 3.1 生成 8 个方向 mask（每个 mask size=3s×3s，只有一个 s×s block 为1）---
        % 这样 nnz(mask)=s^2，所以 ordfilt2 的 order 用 s^2+1-j 与脚本一致
        [mask1,mask2,mask3,mask4,mask5,mask6,mask7,mask8] = create_mask_local(s);

        % --- 3.2 计算中心 cell 与 8方向 cell 的 top-K 均值（更省内存/更快）---
        % 你脚本是先存 m0(:,:,j) 再 mean(m0,3)
        % 这里直接 acc += ordfilt2(...)，最后除以K，完全等价但不占三维大内存
        acc0 = zeros(H,W); acc1 = zeros(H,W); acc2 = zeros(H,W); acc3 = zeros(H,W);
        acc4 = zeros(H,W); acc5 = zeros(H,W); acc6 = zeros(H,W); acc7 = zeros(H,W); acc8 = zeros(H,W);

        for j = 1:K
            ord = s^2 + 1 - j;             % 第 j 大（从最大到第K大）

            acc0 = acc0 + ordfilt2(I, ord, ones(s));   % 中心 cell（s×s）
            acc1 = acc1 + ordfilt2(I, ord, mask1);     % 方向1
            acc2 = acc2 + ordfilt2(I, ord, mask2);
            acc3 = acc3 + ordfilt2(I, ord, mask3);
            acc4 = acc4 + ordfilt2(I, ord, mask4);
            acc5 = acc5 + ordfilt2(I, ord, mask5);
            acc6 = acc6 + ordfilt2(I, ord, mask6);
            acc7 = acc7 + ordfilt2(I, ord, mask7);
            acc8 = acc8 + ordfilt2(I, ord, mask8);
        end

        M0 = acc0 / K;  M1 = acc1 / K;  M2 = acc2 / K;  M3 = acc3 / K;
        M4 = acc4 / K;  M5 = acc5 / K;  M6 = acc6 / K;  M7 = acc7 / K;  M8 = acc8 / K;

        % --- 3.3 普通均值 mean0..mean8（脚本里是 imfilter(...)/s^2）---
        % 注意：mask 是 3s×3s，但里面1的个数是 s^2，所以仍除以 s^2
        mean0 = imfilter(I, ones(s),  'replicate') / (s^2);
        mean1 = imfilter(I, mask1,    'replicate') / (s^2);
        mean2 = imfilter(I, mask2,    'replicate') / (s^2);
        mean3 = imfilter(I, mask3,    'replicate') / (s^2);
        mean4 = imfilter(I, mask4,    'replicate') / (s^2);
        mean5 = imfilter(I, mask5,    'replicate') / (s^2);
        mean6 = imfilter(I, mask6,    'replicate') / (s^2);
        mean7 = imfilter(I, mask7,    'replicate') / (s^2);
        mean8 = imfilter(I, mask8,    'replicate') / (s^2);

        % --- 3.4 BE：8方向 M 的最大值（背景估计 baseline）---
        BE = max(cat(3,M1,M2,M3,M4,M5,M6,M7,M8), [], 3);
        BE = max(BE, eps);                 % 防止除0

        % --- 3.5 SLCM：结构对比项（与你脚本一致）---
        SLCM = (I_gauss.^2) ./ BE - I_gauss;
        SLCM(SLCM < 0) = 0;                % 只保留正响应

        % --- 3.6 IRIL：排序均值 - 普通均值（中心与方向）---
        IRIL0 = M0 - mean0;
        IRIL1 = M1 - mean1;
        IRIL2 = M2 - mean2;
        IRIL3 = M3 - mean3;
        IRIL4 = M4 - mean4;
        IRIL5 = M5 - mean5;
        IRIL6 = M6 - mean6;
        IRIL7 = M7 - mean7;
        IRIL8 = M8 - mean8;

        temp2 = cat(3, IRIL1,IRIL2,IRIL3,IRIL4,IRIL5,IRIL6,IRIL7,IRIL8);

        % --- 3.7 WD：中心比方向更强才算目标（抑制边缘/杂波）---
        IRIL_max = max(temp2, [], 3);
        WD = IRIL0 - IRIL_max;
        WD(WD < 0) = 0;

        % --- 3.8 WB：方向差的标准差（作为分母权重），下界 xi=5 防止过大权重 ---
        WB = std(temp2, 0, 3);
        WB = max(WB, xi);                  % 等价于你脚本的"<=xi 就置 5"

        % --- 3.9 权重 W 与最终 WSLCM ---
        Wght = (IRIL0 .* WD) ./ WB;
        WSLCM = Wght .* SLCM;

        % 保存该尺度结果
        Fout(:,:,si) = WSLCM;
    end

    % ---------- 4) 多尺度融合（脚本是 max(Fout,[],3)） ----------
    S = max(Fout, [], 3);

end

function [m1,m2,m3,m4,m5,m6,m7,m8] = create_mask_local(s)
% create_mask_local(s)
% 生成 8 个方向 mask，每个 mask 尺寸为 (3s)×(3s)，只有一个 s×s block 为1。
% 方向编号与 TLLCM 的 8 方向一致：
%   1 TL, 2 T, 3 TR, 4 R, 5 BR, 6 B, 7 BL, 8 L
%
% 为什么这样设计：
%   - 这样每个 mask 的 nnz = s^2
%   - 你的脚本用 ordfilt2(img, s^2+1-j, mask)，order 与 nnz 完全匹配

    W = 3*s;
    b = s;

    % TL
    m = zeros(W); m(1:b, 1:b) = 1;             m1 = m;
    % T
    m = zeros(W); m(1:b, b+1:2*b) = 1;         m2 = m;
    % TR
    m = zeros(W); m(1:b, 2*b+1:3*b) = 1;       m3 = m;
    % R
    m = zeros(W); m(b+1:2*b, 2*b+1:3*b) = 1;   m4 = m;
    % BR
    m = zeros(W); m(2*b+1:3*b, 2*b+1:3*b) = 1; m5 = m;
    % B
    m = zeros(W); m(2*b+1:3*b, b+1:2*b) = 1;   m6 = m;
    % BL
    m = zeros(W); m(2*b+1:3*b, 1:b) = 1;       m7 = m;
    % L
    m = zeros(W); m(b+1:2*b, 1:b) = 1;         m8 = m;
end