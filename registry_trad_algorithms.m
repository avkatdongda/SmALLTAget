function algs = registry_trad_algorithms(baseline_root)
% registry_trad_algorithms
% ========================================================================
% 作用：注册传统算法列表，并统一成 S = fun(I) 的标准接口。
% 
% 输入：
%   baseline_root - baseline 算法所在根目录（例如 E:/dimifrdata/baselines）
% 
% 输出：
%   algs - 结构体数组，每个元素包含：
%          algs(i).name  算法名
%          algs(i).fun   统一接口函数句柄，调用形式 S = fun(I)
% 
% 关键要求：
%   - 必须包含 7 个算法：AdMD7_eff/BLCM/MLCM_fun/MPCM_fun/RLCM/TLLCM/WSLCM
%   - 对 TLLCM/WSLCM 自动检测是否 script。
%   - 若是 script，则调用函数版 TLLCM_fun/WSLCM_fun（无副作用）。
% ========================================================================

    % ------------------------- 1) 定义算法名 -------------------------
    % 这里严格使用你指定的 7 个算法名称。
    names = {'AdMD7_eff', 'BLCM', 'MLCM_fun', 'MPCM_fun', 'RLCM', 'TLLCM', 'WSLCM'};

    % ------------------------- 2) 预分配输出结构体 -------------------------
    % 预分配结构体数组提高可读性与稳定性。
    algs = struct('name', cell(size(names)), 'fun', cell(size(names)));

    % ------------------------- 3) 逐个构造统一接口 -------------------------
    for i = 1:numel(names)
        % 当前算法名。
        nm = names{i};

        % 默认调用名就是原名。
        call_name = nm;

        % 仅 TLLCM/WSLCM 需要判断是否脚本。
        if strcmp(nm, 'TLLCM') || strcmp(nm, 'WSLCM')
            % 找到原始文件路径。
            fpath = which([nm, '.m']);
            % 如果路径为空，尝试 baseline_root 下直连查找。
            if isempty(fpath)
                fpath = fullfile(baseline_root, [nm, '.m']);
            end

            % 若文件存在，进行“脚本/函数”检测。
            if exist(fpath, 'file') == 2
                % 读取文件内容（文本）。
                txt = fileread(fpath);
                % 去掉前导空白后检查是否以 function 开头。
                is_func = ~isempty(regexp(txt, '^\s*function\b', 'once'));

                % 若不是 function，则认定是 script。
                if ~is_func
                    % script 不能直接 TLLCM(I) 方式调用，转用函数版。
                    call_name = [nm, '_fun'];
                    % 如果函数版不存在，报错提示用户生成/检查。
                    if exist(call_name, 'file') ~= 2
                        error('检测到 %s 是脚本，但找不到函数版 %s.m。', nm, call_name);
                    end
                end
            else
                % 原始文件都找不到，直接报错。
                error('未找到算法文件：%s.m', nm);
            end
        end

        % 写入算法名（name 仍保留原始名字，便于输出文件命名一致）。
        algs(i).name = nm;
        % 用匿名函数包装，后续统一调用 S = algs(i).fun(I)。
        algs(i).fun = @(I) call_algorithm_safe(call_name, I);
    end
end

function S = call_algorithm_safe(call_name, I)
% call_algorithm_safe
% ========================================================================
% 统一算法调用安全层：
%   1) 输入 I 统一成单通道 double。
%   2) 调用算法函数获得原始得分图 S。
%   3) 对 S 做基本合法性检查（非空、二维）。
% 
% 注意：真正的 min-max 归一化在 eval_one_alg_one_seq_roc 中做，保证评测口径统一。
% ========================================================================

    % 若 I 是 RGB，统一取第一通道。
    if ndims(I) == 3
        I = I(:, :, 1);
    end
    % 转 double，避免整型运算差异。
    I = double(I);

    % 获取函数句柄。
    fh = str2func(call_name);
    % 调用算法。
    S = fh(I);

    % 基本检查：输出不能为空。
    if isempty(S)
        error('%s 输出为空。', call_name);
    end
    % 基本检查：输出必须是二维矩阵。
    if ndims(S) ~= 2
        error('%s 输出不是二维矩阵。', call_name);
    end

    % 转 double，统一后续处理数据类型。
    S = double(S);
end
