# SmALLTAget
# 红外小目标检测传统算法对比实验（单帧、点标注）

本工程用于复现并批量评测 7 种传统算法，**同时输出**：

1. 像素级 ROC + AUC
2. 目标级 Pd-FP/frame（Target-level ROC / FROC 风格）

## 1. 目录假设（严格）

- 数据根目录：`E:/dimifrdata`
- 序列图像目录：`E:/dimifrdata/dataX/dataX/0.bmp, 1.bmp, ...`
- 标注目录：`E:/dimifrdata/data_label/dataX.txt`
- baseline 算法目录：`E:/dimifrdata/baselines`

> GT 第 4/5 列分别为 `x(列)` 与 `y(行)`。

## 2. 一键运行

```matlab
run_all_trad_roc
```

## 3. quick test（快速验收）

在 `run_all_trad_roc.m` 中设置：

```matlab
cfg.quick_test = true;
```

quick test 会自动变成：

- 只跑 `data1`
- 前 20 帧
- 前 2 个算法
- 输出单算法结果 + 该序列的 4 张 overlay 图

## 4. 评测协议

### 4.1 输入输出统一

- 输入图像：若 RGB，取第一通道，转 `double`
- 输出得分图：每帧 min-max 归一化到 `[0,1]`

### 4.2 像素级 ROC

- 正样本：GT 点中心 9×9 ROI（`roi_r=4`）
- 负样本：ROI 外像素，按帧随机下采样
- ROC：`TPR/FPR`
- AUC：`trapz(FPR,TPR)`

### 4.3 目标级 Pd-FP/frame

- 对 `th_list_target` 阈值扫描
- 每阈值：
  1. `BW=(S_norm>=th)`
  2. 2D 连通域 `bwconncomp`
  3. `regionprops(...,'WeightedCentroid')` 提候选（不可用则退化 `Centroid`）
  4. 候选点近邻合并（`r_merge`，传递闭包）
  5. 命中判据：`max(|dx|,|dy|)<=roi_r`
  6. 误检：ROI 外候选数
- 曲线定义：
  - `Pd = 命中帧数 / 有效帧数`
  - `FP/frame = 总FP / 有效帧数`
- 后处理：按 FP 升序 + 同 FP 取最大 Pd + `cummax` 单调化得到 envelope

### 4.4 GT 偏移与越界

- 自动查第一个有效坐标行：
  `first_valid = find(isfinite(gt(:,4)) & isfinite(gt(:,5)),1,'first')`
- `row_offset = first_valid - 1`
- 先计算 `f_max = n_gt_rows - row_offset - 1` 预裁剪越界帧

## 5. 输出文件

输出目录：`E:/dimifrdata/results_trad_roc`

### 5.1 每算法 × 每序列

- 像素级：
  - `{alg}_data{XX}_roc.csv`
  - `{alg}_data{XX}_roc.png`
  - `{alg}_data{XX}_roc_logx.png`
  - `{alg}_data{XX}_scores.mat`
- 目标级：
  - `{alg}_data{XX}_target_curve.csv`（`FP_per_frame,Pd`）
  - `{alg}_data{XX}_target.png`
  - `{alg}_data{XX}_target.mat`（含 `th_list,FPf_raw,Pd_raw,FPu_target,PDu_target`）

### 5.2 每序列 overlay（同一数据集多算法叠加）

- `overlay_data{XX}_pixelROC.png`
- `overlay_data{XX}_pixelROC_logx.png`
- `overlay_data{XX}_targetPdFP.png`
- `overlay_data{XX}_targetPdFP_logx.png`

### 5.3 全局输出

- `summary_auc.csv`
- `overall_rank.csv`
- `overall_mean_metrics.csv`（`mean_AUC, mean_Pd@FP<=0.5, mean_Pd@FP<=1`）
- `overall_pixelROC_mean.png`
- `overall_targetPdFP_mean.png`

## 6. 命令行排名打印

每个 `dataX` 叠加图生成后，命令行会打印：

- AUC Top3
- Pd@FP<=0.5 Top3