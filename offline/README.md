# 部分离线安装版

本版本独立于已验证的 `9.1.0-relase`，不修改根目录 Dockerfile 或版本快照。新版本只做指定组件离线安装，**不是完全断网构建**。

| 组件 | 安装方式 |
|---|---|
| CANN Toolkit / 950 ops / NNAL | 三个指定的本地 `.run` 文件，按此顺序安装 |
| Torch / torch_npu | 指定的本地 `.whl`，版本限定为 `2.10.0` 系列，允许 post/dev/local 后缀 |
| Triton-Ascend | 指定的本地 `.whl`，版本从元数据读取 |
| 基础 Triton | 默认按依赖联网安装；需要未发布版本时可额外指定 `--triton` |
| Ubuntu、apt、Miniforge、Conda Python、其他 pip 依赖、TENPU | 继续联网安装 |

保持 Ubuntu 24.04、Python 3.13.16、x86_64 / Ascend 950。CANN 的三个安装包应由你选择配套版本，安装布局需提供 `ascend-toolkit/set_env.sh`、`${ASCEND_HOME_PATH}/share/info/ascendnpu-ir/bin/set_env.sh`、`nnal/atb/set_env.sh`。新版通过 CANN 设置的 ASCEND_HOME_PATH 定位 Bisheng，不再写死 `cann-9.1.0`。

## 一条命令构建

在仓库根目录执行。下面的 `/data/packages/...` 都是示例文件路径，替换成实际路径，可位于仓库之外，路径含空格时保留引号：

```bash
export DOCKER_HOST=unix:///tmp/docker-test/docker.sock
set -o pipefail

bash offline/build.sh \
  --toolkit "/data/packages/Ascend-cann-toolkit_new_linux-x86_64.run" \
  --ops "/data/packages/Ascend-cann-950-ops_new_linux-x86_64.run" \
  --nnal "/data/packages/Ascend-cann-nnal_new_linux-x86_64.run" \
  --torch "/data/packages/torch-2.10.0+cpu-cp313-cp313-manylinux_2_28_x86_64.whl" \
  --torch-npu "/data/packages/torch_npu-2.10.0.post7-cp313-cp313-manylinux_2_28_x86_64.whl" \
  --triton-ascend "/data/packages/triton_ascend-3.2.2-cp313-cp313-linux_x86_64.whl" \
  --tag tx_hy:partial-offline \
  2>&1 | tee build-partial-offline.log
```

示例 wheel 文件名不表示这些内部版本已发布或已验证。**保留下载文件的原始 wheel 文件名**，不要为了通过检查手动改名。脚本校验是否存在；镜像内根据真实 METADATA 校验包名、版本、wheel 文件名及 CPython/平台兼容标签。

脚本自动配置 `--network=host`、`--platform linux/amd64`，转发当前终端代理。Docker daemon 必须已启动、Buildx 已安装。

可选参数举例（加到上述命令中）：

```text
--triton /data/packages/<配套基础triton>.whl
```

额外 Docker 构建参数放在 `--` 后，例如：

```text
-- --build-arg TENPU_REF=<兼容的commit> --build-arg STRICT_CANN_PIP_CHECK=1
```

尖括号内容为占位符，需要替换。默认 TENPU 仍克隆在线默认分支。

## 文件与缓存处理

- 只把你指定的文件暂存为一个 BuildKit 命名上下文 `offline_inputs`，不传入整台机器或整个下载目录。
- 暂存优先使用硬链接，跨文件系统时尝试 reflink/复制。不会修改原安装包；完成或失败后清理临时目录。
- 临时目录默认在 `/tmp`；空间不足时先设置 `export OFFLINE_STAGING_ROOT=/data/tx_hy_staging`。不同磁盘之间复制可能需要额外数 GB 空间。
- 安装包通过只读构建挂载提供；CANN 安装时临时复制至镜像构建目录并在同一层删除，不保留原始安装包层。BuildKit 缓存仍可能保存输入内容。
- 离线 Dockerfile 有独立的 `Dockerfile.dockerignore`，根目录 `.dockerignore` 保持不变。
- 不上传内部 `.run` / `.whl` 到 GitHub；`.gitignore` 已排除这些文件。

本地三个核心 wheel（以及可选基础 Triton）安装前会按真实版本生成约束，TENPU/其他依赖安装不能悄悄替换它们。后续最终版本检查必须与本地输入一致。依赖无法满足时明确失败；不会以 `--no-deps` 强行安装来隐藏冲突。

例如某个 `2.10.0.dev...` 内部版本虽然属于 2.10.0 系列，仍可能不满足 torchvision 或 torch_npu 的精确依赖声明。需要配套 wheel，不能保证仅靠“大版本相同”就兼容。

## 启动及验证

在仓库根目录执行，驱动路径以现场实际为准：

```bash
NPU_ARGS=()
for dev in /dev/davinci* /dev/devmm_svm /dev/hisi_hdc; do
  [ -c "$dev" ] && NPU_ARGS+=(--device="$dev")
done
docker run -it --name tx_hy_offline_dev \
  --network=host --shm-size=8g "${NPU_ARGS[@]}" \
  --mount type=bind,src=/usr/local/Ascend/driver,dst=/usr/local/Ascend/driver,readonly \
  -v "$PWD":/workspace/tx_hy \
  tx_hy:partial-offline bash
```

容器内：

```bash
python /opt/tx_hy/check_versions.py
cat /opt/tx_hy/build-info/offline-wheels.json
python /opt/tx_hy/smoke_test.py
```

离线版请用 `/opt/tx_hy/smoke_test.py`；根目录的旧版 `smoke_test.py` 仍固定校验在线版 `torch_npu==2.10.0.post6`，不会修改它。

`build-info/` 保存核心 wheel 包名、版本、SHA256、CANN 包 SHA256、原文件名、完整依赖清单与 TENPU commit。版本清单可能包含构建时的临时 wheel 路径；重建请使用本构建脚本和原始安装包，不能直接把该 pip freeze 文件当成在线 requirements 使用。

## 验证边界

新增代码已做静态语法和构建脚本/轮子校验逻辑测试；未取得你的内部安装包，**未完成离线版真实镜像构建或 NPU 验证**。

沿用在线基线的依赖检查策略：Conda pip check、te/tbe 顶层导入及核心版本匹配必须通过；逐条列出的 CANN 已知问题只记录警告，未列出的新问题会阻断构建并显示具体条目。内部 CANN 可能改变工具包版本/依赖，因此出现新报告需要单独定位，不会自动全部忽略。

## CANN 9.2.0 最终检查报错

若日志显示 Conda `No broken requirements found`、`te/tbe` 顶层导入成功，但最终检查失败，先查看 `pip check` 的具体条目。9.2.0 实际日志新增了以下四条，现已加入离线版的精确告警名单：

```text
cannsim 0.1.0 requires plotly, which is not installed.
mindstudio-kpp 26.2.0 requires plotly, which is not installed.
msboost 26.2.0 requires colorlog, which is not installed.
msboost 26.2.0 requires pydantic, which is not installed.
```

这项修改只允许上述已定位问题以告警形式保留，不补装这些依赖，不代表相关 CANN 工具可用。`STRICT_CANN_PIP_CHECK=1` 仍会让所有 CANN 检查错误阻断构建。Conda 检查、顶层导入、核心版本检查仍必须通过。

拉取包含修复的分支后重新执行原来的 `linshi.sh` 即可，安装包路径和参数无需修改。保留构建缓存，不加 `--no-cache`；本次 Dockerfile 修改位于最终检查，之前的安装层可继续复用。
