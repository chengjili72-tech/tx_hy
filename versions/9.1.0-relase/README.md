# 9.1.0-relase

按用户指定拼写保留 `relase`。本目录 Dockerfile 与已验证的根目录 Dockerfile **逐字节一致**。对应代码基线为 `490a0ed3490bf3e47ba17fc814f5f5648df1ed63`。

2026-10-10：用户完成镜像构建，并反馈“验证了下基本没问题”。这是用户侧基本验证，不扩大解释为全量模型、多机通信或 profiling 工具验证。已构建镜像 ID：

```text
sha256:7f3488c46f2d75fd3cb895f27dc74869dfb82b9e499a955387c61d3f9d82ea1b
```

软件组合：Ubuntu 24.04、Conda hunyuan4_tenpu、Python 3.13.16、CANN 9.1.0 Toolkit/950 ops/NNAL、Torch 2.10.0+cpu、torch_npu 2.10.0.post6，以及在线 Triton-Ascend / editable TENPU。原有 CANN 检查警告保留，详见根目录 README。

## 给已经验证的镜像增加版本名

在原来的机器、同一个 daemon 上执行；不需要重建：

```bash
export DOCKER_HOST=unix:///tmp/docker-test/docker.sock
docker tag tx_hy:cann9.1.0-py3.13.16 tx_hy:9.1.0-relase
docker image inspect tx_hy:9.1.0-relase --format '{{.Id}}'
```

Git 分支/文件快照保存构建配方，不保存 Docker 镜像。上游浮动依赖仍可能变化，因此保留验证过的镜像归档比重新构建更能精确复现。

## 从配方重新构建

在仓库根目录执行，已安装 Buildx：

```bash
export DOCKER_HOST=unix:///tmp/docker-test/docker.sock
set -o pipefail
DOCKER_BUILDKIT=1 docker build \
  --network=host --platform linux/amd64 \
  --build-arg HTTP_PROXY="${http_proxy:-${HTTP_PROXY:-}}" \
  --build-arg HTTPS_PROXY="${https_proxy:-${HTTPS_PROXY:-}}" \
  --build-arg ALL_PROXY="${all_proxy:-${ALL_PROXY:-}}" \
  --build-arg NO_PROXY="${no_proxy:-${NO_PROXY:-}}" \
  --progress=plain \
  -f versions/9.1.0-relase/Dockerfile \
  -t tx_hy:9.1.0-relase . 2>&1 | tee build-9.1.0-relase.log
```

## 950-PR 容器启动脚本（候选版，非最终版）

本次按用户现场命令整理。**启动配置尚待用户实机验证**，不会因原镜像基本验证通过而自动视为已验证。脚本名：[run-950-PR.sh](run-950-PR.sh)。

在仓库根目录执行：

```bash
export DOCKER_HOST=unix:///tmp/docker-test/docker.sock
# 已做过镜像 tag 可跳过
docker tag tx_hy:cann9.1.0-py3.13.16 tx_hy:9.1.0-relase

# 可先查看展开的命令，不启动容器
bash versions/9.1.0-relase/run-950-PR.sh --dry-run

# 后台启动
bash versions/9.1.0-relase/run-950-PR.sh

# 进入容器
docker exec -it hg_test_cache bash
```

可覆盖名称和镜像，不必编辑脚本：

```bash
CONTAINER_NAME=hg_test_cache_950pr IMAGE=tx_hy:9.1.0-relase \
  bash versions/9.1.0-relase/run-950-PR.sh
```

保留用户提供的 `--ipc host -it -d --net=host --shm-size=500g --privileged=true`、工作目录 `/data` 和全部挂载；挂载默认读写。补充：

- 默认镜像名 `tx_hy:9.1.0-relase`，默认容器名 `hg_test_cache`。
- 当前环境可见的数字 NPU 节点 `/dev/davinci[0-9]*`；保留三个显式管理设备。privileged 本身也会扩大设备访问，显式设备列表用于记录现场配置，不代表仅开放这些设备。
- `--ulimit memlock=-1:-1`，供需要锁页内存的运行场景使用。
- 覆盖 ENTRYPOINT 为 bash 后显式执行 `source /opt/tx_hy/env.sh && exec bash -i`，初始化 Conda/CANN 再保持交互 Shell。
- 容器标签 `tx_hy.launch-profile=950-PR`、`tx_hy.validation=pending`，保留待验证标识。

**共享内存说明：** `--ipc=host` 共享 daemon 所在环境的 IPC 和 /dev/shm；保留的 `--shm-size=500g` 不会把宿主的共享内存改成 500GB。若 daemon 在外层容器中，实际受外层容器环境约束。验证时以 `df -h /dev/shm` 为准。

脚本面向当前本地独立 daemon：检查挂载源和管理设备存在，不自动创建空目录，也不删除同名容器。缺少 /data1 等目录时请按真实现场调整挂载。不会挂载宿主整个 /usr/local/Ascend，以免覆盖镜像里的 CANN。/usr/local/dcmi、npu-smi、/usr/local/sbin 及其他路径按用户给定保持原样。

容器内先检查：

```bash
python --version
echo "$CONDA_PREFIX"
echo "$ASCEND_HOME_PATH"
df -h /dev/shm
ulimit -l
npu-smi info
python -c 'import torch, torch_npu; print(torch.__version__); print(torch_npu.__version__); print(torch.randn(3,4).npu())'
```

不自动添加未经确认的通信配置/URMA 库路径；后续以用户实测后的最终命令更新。顶层挂载 `/taijifs_zwfy8` 已包含现场代码路径；可通过该路径运行仓库的 smoke_test.py。

已停止的容器可用 `docker start hg_test_cache` 启动，再用 `docker exec -it hg_test_cache bash` 进入。首次启动异常可查看 `docker logs hg_test_cache`。

## 保存与恢复

在有足够空间的持久化目录执行：

```bash
docker save -o tx_hy_9.1.0-relase.tar tx_hy:9.1.0-relase
sha256sum tx_hy_9.1.0-relase.tar > tx_hy_9.1.0-relase.tar.sha256

# 恢复前校验并加载
sha256sum -c tx_hy_9.1.0-relase.tar.sha256
docker load -i tx_hy_9.1.0-relase.tar
```

停止 daemon 本身不删除镜像；`/tmp/docker-test` 被清理或外层容器被删除仍可能丢失数据。不要上传镜像归档到代码仓库，也不要让多个 daemon 共用同一个 data-root。
