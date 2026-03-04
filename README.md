# 红外小目标检测传统算法对比实验（单帧、点标注）

本工程用于复现并批量评测 7 种传统算法在 DIMIFR 风格目录上的性能，评测指标为 **ROI 像素级 ROC + AUC**。

## 1. 目录假设（严格）

- 数据根目录：`E:/dimifrdata`
- 序列图像目录：`E:/dimifrdata/dataX/dataX/0.bmp, 1.bmp, ...`
- 标注目录：`E:/dimifrdata/data_label/dataX.txt`
- baseline 算法目录：`E:/dimifrdata/baselines`

> 其中 GT 的第 4/5 列分别为 `x(列)` 与 `y(行)`。

## 2. 一键运行

在 MATLAB 命令行执行：

```matlab
run_all_trad_roc
```

脚本会自动：

1. 加载算法；
2. 自动检测 `TLLCM.m` / `WSLCM.m` 是否脚本；
3. 遍历 `data1..data10`；
4. 输出每个算法×序列的 ROC 图、ROC CSV、scores MAT；
5. 生成全局 `summary_auc.csv` 和 `overall_rank.csv`。

## 3. quick test（快速冒烟）

打开 `run_all_trad_roc.m` 顶部配置区，把：

```matlab
cfg.quick_test = true;
```

该模式会自动改为：

- 只跑 `data1`
- `frame_stride = 1`
- `max_frames_per_seq = 20`
- 只跑前 2 个算法（用于快速确认流程可跑通）

## 4. 评测协议（严格一致）

### 4.1 输入输出统一

- 输入图像：若是 RGB，取第一通道；再转 `double`
- 算法输出：`S` 必须与输入同尺寸
- 每帧统一归一化：

```matlab
S = S - min(S(:));
S = S / (max(S(:)) + eps);
```

原因：不同算法输出量纲差异较大，不归一化会导致 ROC 不公平。

### 4.2 ROI 像素级正负样本定义

由于只有点标注，没有像素 mask，采用以下定义：

- 正样本：以 GT 点为中心的 `9x9` ROI（`roi_r=4`）
- 负样本：ROI 外所有像素

为了避免内存爆炸，负样本按帧随机下采样（默认每帧最多 `20000` 个），并固定随机种子保证可复现。

### 4.3 GT 行偏移处理

GT 可能有头行（导致第4/5列 NaN），自动执行：

```matlab
first_valid = find(isfinite(gt(:,4)) & isfinite(gt(:,5)), 1, 'first');
row_offset = first_valid - 1;
row = row_offset + f + 1;
```

其中 `f` 为帧号（从 0 开始）。

### 4.4 ROC/AUC 计算

- 若环境有 `perfcurve`，可直接使用
- 若无 `perfcurve`，自动 fallback 到手写阈值扫描（`1 -> 0`）
- AUC 一律用 `trapz(FPR, TPR)`

并输出两种图：

1. 线性坐标 ROC
2. log-x ROC（低误警区域更清晰，`FPR=0` 会夹紧到 `1e-6`）

## 5. 输出文件

输出目录固定为：`E:/dimifrdata/results_trad_roc`

对每个 `算法 × 序列` 会产生：

- `{alg}_data{XX}_roc.csv`
- `{alg}_data{XX}_roc.png`
- `{alg}_data{XX}_roc_logx.png`
- `{alg}_data{XX}_scores.mat`

全局输出：

- `summary_auc.csv`（行=算法，列=data1..data10 + mean_AUC）
- `overall_rank.csv`（按 mean_AUC 降序）
