# tx_hy

面向 **x86_64 / Ascend 950** 的 hunyuan4_tenpu 开发环境。所有安装步骤均在根目录 `Dockerfile` 内，可单独使用该文件构建；不是复制已有 Conda 环境。

## 验证状态

**9.1.0-relase 已由用户构建成功并完成基本环境验证（2026-10-10）。** 新增部分离线版尚未使用内部安装包完成实际构建。原有 CANN 工具依赖警告的范围不变，用户反馈不扩大解释为完整训练、通信或 profiling 验证。

| 版本 | 文件 / 使用说明 | 状态 |
|---|---|---|
| 9.1.0-relase | [固定配方和命令](versions/9.1.0-relase/README.md) | 用户基本验证通过 |
| 部分离线迭代版 | [本地包构建说明](offline/README.md)、[构建脚本](offline/build.sh) | 代码检查通过，真实构建待验证 |

根目录 `Dockerfile` 与 `versions/9.1.0-relase/Dockerfile` 逐字节一致，离线迭代只新增独立 `offline/Dockerfile`。`9.1.0-relase` 同名分支保留线上基线和发布命令（分支，不是 Git tag）。


## 环境配置

| 项目 | 配置 |
|---|---|
| OS | `ubuntu:24.04`，不锁定 24.04.3 小版本 |
| 架构 / 设备 | `linux/amd64` / Ascend 950 |
| Conda | Miniforge（提供 conda；使用 conda-forge channel） |
| 环境名 | `hunyuan4_tenpu` |
| Python | **3.13.16**，普通 CPython cp313，非 free-threaded/debug 构建 |
| CANN | **9.1.0 Toolkit + 950 ops + NNAL** |
| torch | **2.10.0+cpu**，PyTorch CPU 源 |
| torch_npu | **2.10.0.post6** |
| Triton-Ascend | 按用户命令不固定版本；由安装源与依赖解析决定 |
| TENPU | 从 GitCode 克隆默认分支，`pip install -e ... --no-build-isolation` |

其他指定依赖：`torchvision==0.25.0`、`pillow==12.2.0`、`tokenizers==0.22.2`、`transformers==4.57.1`、`einops==0.8.2`、`pynvml==13.0.1`、`omegaconf==2.3.1`、`mbridge==0.15.1`、`pycryptodomex==3.23.0`；`orjson`、`numba`、`pycryptodome` 按用户流程不固定版本。CANN 前置依赖包含 `protobuf==3.20.0`、PyYAML、NumPy 等。

`torchvision` 保留版本和 `--no-deps`，但明确从 PyTorch CPU 源安装，得到匹配 CPU Torch 的构建，避免默认 PyPI CUDA 构建引入 CUDA 动态库要求。`pip list` 可能显示 `0.25.0+cpu`，满足 `==0.25.0`。

`PIP_CONSTRAINT=/opt/tx_hy/constraints.txt` 在镜像中持续生效，防止后续安装覆盖指定版本；如上游浮动依赖与这些版本冲突，构建会失败，而不会自动更换 Torch。未固定的版本及上游分支仍会变化，**这不是完全锁定的可复现环境**。

## 安装顺序

1. Ubuntu 编译工具、动态库和开发包。
2. Miniforge，以及 Python 3.13.16 的 Conda 环境。
3. 版本约束、CANN 所需 Python 依赖。
4. 在线下载并安装 CANN Toolkit → 950 ops → NNAL，安装后删除 `.run` 包。
5. 配置统一环境初始化脚本，包含 Conda、CANN、Bisheng、ATB 和宿主驱动库路径。
6. 安装 Torch、torch_npu、Triton-Ascend、TENPU。
7. 安装 angelptm_hy4 的依赖。
8. Conda 依赖检查、CANN 顶层导入、完整依赖检查报告、框架版本断言，保存实际安装清单及 TENPU commit。

仅安装用户列出的 angelptm_hy4 **依赖**；不包含业务代码、模型权重或数据，也不额外安装 ascend_deepep。

## CANN 安装来源

参考 [Ascend 官方 Dockerfile](https://github.com/Ascend/cann-container-image/blob/main/cann/9.1.0-950-ubuntu22.04-py3.12/Dockerfile)（制作时读取的文件 blob SHA：`569aa42439a2dc38c51c180eff7c758c57db9162`）。沿用其下载目录与安装参数 `--quiet --install --install-for-all`：

```text
https://ascend-repo.obs.cn-east-2.myhuaweicloud.com/CANN/CANN%209.1.0/
  Ascend-cann-toolkit_9.1.0_linux-x86_64.run
  Ascend-cann-950-ops_9.1.0_linux-x86_64.run
  Ascend-cann-nnal_9.1.0_linux-x86_64.run
```

制作端检查这三个地址返回 HTTP 200；用户后续已完成包含这些安装步骤的构建层（2026-10-10），运行兼容性仍待真机验证。三个安装包总计约 4.4 GB，构建还需要 Conda、Python wheels、CANN 解包和 Docker 层空间；此前 `vfs` 存储驱动尤其需要预留空间。

驱动与固件安装在宿主机。容器安装用户态 CANN，运行时使用宿主机匹配的驱动、设备与通信配置。不要将宿主机整个 `/usr/local/Ascend` 挂载到容器相同位置，这会覆盖镜像安装的 CANN。

## 构建

```bash
git clone https://github.com/chengjili72-tech/tx_hy.git
cd tx_hy

# 沿用之前已启动的独立 Docker daemon；若用系统 Docker，请跳过此行。
export DOCKER_HOST=unix:///tmp/docker-test/docker.sock
docker info

# Dockerfile 使用 heredoc，需 BuildKit / docker buildx。
set -o pipefail
DOCKER_BUILDKIT=1 docker build \
  --network=host \
  --platform linux/amd64 \
  --build-arg HTTP_PROXY="${http_proxy:-${HTTP_PROXY:-}}" \
  --build-arg HTTPS_PROXY="${https_proxy:-${HTTPS_PROXY:-}}" \
  --build-arg ALL_PROXY="${all_proxy:-${ALL_PROXY:-}}" \
  --build-arg NO_PROXY="${no_proxy:-${NO_PROXY:-}}" \
  --progress=plain \
  -t tx_hy:cann9.1.0-py3.13.16 . \
  2>&1 | tee build.log
```

如果报 buildx 组件缺失，需要在执行构建的 Docker 客户端环境安装与之配套的 Buildx 插件。构建过程需要访问 Ubuntu apt、GitHub、conda-forge、PyPI、PyTorch CPU 源、华为源和 GitCode。没有在本仓库中关闭 HTTPS 证书验证。

构建阶段不执行 `.npu()`，无需挂载 NPU。`pip check` 只能检查依赖声明，不能代替 ABI、CANN 算子或真机兼容性验证。

## CANN 依赖检查的范围与限制

CANN 的 set_env.sh 将 `/usr/local/Ascend/cann-9.1.0/python/site-packages` 加入 PYTHONPATH。直接运行 pip check 会同时检查这些厂商包和 Conda 包。本次检查结果：

- Conda 环境：`env -u PYTHONPATH python -m pip check` 通过。
- CANN te 0.4.0：WHEEL 标签为 cp311-cp311-linux_x86_64；RECORD 未列出动态库，te/tbe 顶层导入成功。尚不能确认标签是否不准确，不能据此声称二进制或完整运行兼容。
- affinity-sched / mindstudio-kpp / ms-service-profiler：存在已观察到的缺包和 pandas 版本冲突，**这些问题尚未修复**。使用相关工具前须单独补齐兼容依赖并验证。

默认构建要求 Conda 检查、te/tbe 顶层导入和框架版本断言通过；完整 pip check 仅对 Dockerfile 中逐条列出的 12 条已观察到的 CANN 问题给出警告并保存报告。新增或变化的错误仍会使构建失败。没有卸载 CANN 包、改写 WHEEL 标签或改变 Python 版本。

如需完整 pip check 零报错才能生成镜像，在上述构建命令增加 `--build-arg STRICT_CANN_PIP_CHECK=1`，当前已知问题仍会使该模式失败。

报告位于 `/opt/tx_hy/build-info/pip-check-conda.txt`、`pip-check-with-cann.txt` 和 `pip-check-with-cann.exit-code`。不要将默认构建成功描述为全部 CANN 工具已通过验证。

已确认的网络问题：独立 daemon 缺少 bridge 时需 `--network=host`；当前终端能通过代理联网，但构建 RUN 不自动继承终端代理，需要上述四个代理参数。代理地址不写入 Dockerfile。

## 950-PR 容器启动说明（CANN 9.2.0）

将以下脚本保存为 `run_950_PR.sh`。使用镜像 `tx_hy_tenpu:9.2.0_py313_torch2.10.0_20261026`，连接 `/home/docker-test/docker.sock`：

```bash
#!/usr/bin/env bash
set -euo pipefail

export DOCKER_HOST=unix:///home/docker-test/docker.sock

IMAGE="tx_hy_tenpu:9.2.0_py313_torch2.10.0_20261026"
CONTAINER_NAME="tx_hy_tenpu9.2.0_20261026"

# 补充当前可见的 NPU 计算设备
NPU_ARGS=()
for dev in /dev/davinci[0-9]*; do
    if [ -c "$dev" ]; then
        NPU_ARGS+=(--device="$dev")
    fi
done

docker run --name "$CONTAINER_NAME" \
    --ipc=host -it -d \
    --net=host \
    --shm-size=500g \
    --privileged=true \
    --ulimit memlock=-1:-1 \
    -w /workspace \
    --device=/dev/davinci_manager \
    --device=/dev/hisi_hdc \
    --device=/dev/devmm_svm \
    --device=/dev/infiniband \
    "${NPU_ARGS[@]}" \
    --entrypoint=bash \
    -v /etc/libibverbs.d:/etc/libibverbs.d \
    -v /usr/local/Ascend/driver:/usr/local/Ascend/driver \
    -v /usr/local/dcmi:/usr/local/dcmi \
    -v /usr/local/bin/npu-smi:/usr/local/bin/npu-smi \
    -v /usr/local/sbin:/usr/local/sbin \
    -v /home:/home \
    -v /tmp:/tmp \
    -v /taijifs_zwfy8:/taijifs_zwfy8 \
    -v /taijifs_zwfy:/taijifs_zwfy \
    -v /taijifs_zwfy8:/apdcephfs_zwfy8 \
    -v /taijifs_zwfy:/apdcephfs_zwfy \
    -v /apdcephfs_jn2:/apdcephfs_jn2 \
    -v /cfs_hy_aide:/cfs_hy_aide \
    -v /apdcephfs_zwfy10:/apdcephfs_zwfy10 \
    -v /apdcephfs_zwfy6:/apdcephfs_zwfy6 \
    -v /apdcephfs_zwfy2:/apdcephfs_zwfy2 \
    -v /apdcephfs_zwfy11:/apdcephfs_zwfy11 \
    -v /apdcephfs_zwfy14:/apdcephfs_zwfy14 \
    -v /apdcephfs_zwfy5:/apdcephfs_zwfy5 \
    -v /apdcephfs_zwfy3:/apdcephfs_zwfy3 \
    -v /apdcephfs_nj11:/apdcephfs_nj11 \
    -v /apdcephfs_nj8:/apdcephfs_nj8 \
    -v /apdcephfs_jn4:/apdcephfs_jn4 \
    -v /apdcephfs_jn5:/apdcephfs_jn5 \
    -v /apdcephfs_nj12:/apdcephfs_nj12 \
    -v /apdcephfs_nj2:/apdcephfs_nj2 \
    -v /apdcephfs_nj4:/apdcephfs_nj4 \
    -v /apdcephfs_nj9:/apdcephfs_nj9 \
    -v /apdcephfs_jn:/apdcephfs_jn \
    -v /apdcephfs_nj10:/apdcephfs_nj10 \
    -v /apdcephfs_jn3:/apdcephfs_jn3 \
    -v /apdcephfs_nj3:/apdcephfs_nj3 \
    -v /apdcephfs_wzc1:/apdcephfs_wzc1 \
    -v /taijifs_wzc3:/taijifs_wzc3 \
    -v /apdcephfs_wzc2:/apdcephfs_wzc2 \
    "$IMAGE" \
    -c 'source /opt/tx_hy/env.sh && exec bash -i'

echo "进入容器：docker exec -it $CONTAINER_NAME bash"
```

启动并进入容器：

```bash
bash run_950_PR.sh
export DOCKER_HOST=unix:///home/docker-test/docker.sock
docker exec -it tx_hy_tenpu9.2.0_20261026 bash
```

`--ipc=host` 下共享内存容量以 daemon 所在环境为准，可在容器内执行 `df -h /dev/shm` 查看。脚本中 `/apdcephfs_jn2` 挂载保留一次。

## 启动与真机检查

优先使用目标环境已经验证可用的 Ascend 容器启动方式。下面是常见设备节点的**单卡示例**；先确认目标机存在这些节点。950 的实际设备节点、宿主驱动路径与运行时挂载要求，以该机器的驱动部署为准。

```bash
npu-smi info
ls -l /dev/davinci0 /dev/davinci_manager /dev/devmm_svm /dev/hisi_hdc

docker run --rm -it --name tx_hy_test \
  --device=/dev/davinci0 \
  --device=/dev/davinci_manager \
  --device=/dev/devmm_svm \
  --device=/dev/hisi_hdc \
  --shm-size=8g \
  -v /usr/local/Ascend/driver:/usr/local/Ascend/driver:ro \
  -v "$PWD":/opt/tx_hy_tests:ro \
  tx_hy:cann9.1.0-py3.13.16 \
  python /opt/tx_hy_tests/smoke_test.py
```

检测脚本检查关键模块导入、torch_npu 加法和 Triton-Ascend 向量加法。失败会返回非零状态；TENPU 此处只验证导入，不代表模型训练、多卡 HCCL 或长稳测试通过。多卡通信应复用你在 950 上验证过的设备、网络和通信库挂载配置，再单独执行集合通信测试。

默认 `docker run ... IMAGE bash` 会初始化 Conda 与 CANN。已有容器执行非交互命令时，`docker exec` 不会重新运行 ENTRYPOINT，请显式使用：

```bash
docker exec <容器名> /usr/local/bin/tx-hy-entrypoint python -c \
  'import torch, torch_npu; print(torch.randn(3, 4).npu())'
```

交互式 Bash 会通过 `/etc/bash.bashrc` 加载环境。手动初始化可用：

```bash
source /opt/tx_hy/env.sh
```

TENPU 源码保留在 `/opt/src/TransformerEngineNPU`，editable 安装依赖该目录，不要删除或用挂载覆盖它。

## 查看本次构建使用的版本

```bash
docker run --rm tx_hy:cann9.1.0-py3.13.16 \
  cat /opt/tx_hy/build-info/pip-freeze.txt
docker run --rm tx_hy:cann9.1.0-py3.13.16 \
  cat /opt/tx_hy/build-info/tenpu-commit.txt
```

`/opt/tx_hy/build-info/` 还保存 `pip-list.json`、`conda-explicit.txt`、`environment.yml`、系统/Python 版本及安装包 SHA256。SHA256 用于追溯下载内容；除非显式提供 Miniforge 的预期校验值，否则仅记录摘要不等于与官方摘要核验。

后续需要固定已验证的 Triton-Ascend/TENPU 时，可传入实际版本和 commit：

```bash
DOCKER_BUILDKIT=1 docker build --platform linux/amd64 --progress=plain \
  --build-arg TRITON_ASCEND_VERSION=<已验证版本> \
  --build-arg TENPU_REF=<已验证commit或tag> \
  -t tx_hy:validated .
```

上面尖括号是占位符，请替换后执行。Miniforge 也可使用 `MINIFORGE_URL` 与 `MINIFORGE_SHA256` 固定。完整复现还需要锁定基础镜像 digest、apt/Conda/pip 全部依赖及下载源。

浮动 Git 分支和 pip 索引更新不会自动使 Docker 的 RUN 缓存失效。确实需要重新拉取时使用 `--no-cache`；这将重装整个环境。

## 镜像共享

```bash
docker save tx_hy:cann9.1.0-py3.13.16 | gzip > tx_hy_cann9.1.0_py3.13.16.tar.gz
# 在目标机器或另一个 daemon 中：
gunzip -c tx_hy_cann9.1.0_py3.13.16.tar.gz | docker load
```

仓库只保存构建文件、说明和检查脚本，不上传 CANN 安装包、镜像归档或环境备份。
