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

## 950-PR 容器启动说明

将以下脚本保存为 `run_950_PR.sh`：

```bash
#!/usr/bin/env bash
set -euo pipefail

export DOCKER_HOST=unix:///tmp/docker-test/docker.sock

IMAGE="tx_hy:cann9.1.0-py3.13.16"
CONTAINER_NAME="hg_test_cache"

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
    "${NPU_ARGS[@]}" \
    --entrypoint=bash \
    -v /usr/local/Ascend/driver:/usr/local/Ascend/driver \
    -v /usr/local/dcmi:/usr/local/dcmi \
    -v /usr/local/bin/npu-smi:/usr/local/bin/npu-smi \
    -v /usr/local/sbin:/usr/local/sbin \
    -v /home:/home \
    -v /tmp:/tmp \
    -v /taijifs_zwfy8:/taijifs_zwfy8 \
    "$IMAGE" \
    -c 'source /opt/tx_hy/env.sh && exec bash -i'

echo "进入容器：docker exec -it $CONTAINER_NAME bash"
```

启动并进入容器：

```bash
bash run_950_PR.sh
export DOCKER_HOST=unix:///tmp/docker-test/docker.sock
docker exec -it hg_test_cache bash
```

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
