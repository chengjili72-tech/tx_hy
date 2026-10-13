#!/usr/bin/env bash
# 四台 Kubernetes 容器分别执行：安装 Docker、启动独立 daemon、加载共享镜像。
# 已验证核心命令：2026-10-10，Docker 29.1.3。
# 注意：/home/docker-test 必须是各机器独立的存储目录，不可多机共用同一个 data-root。
set -euo pipefail

IMAGE_TAR='/taijifs_zwfy8/share-305477973/hy_test/tx_hy_images/tx_hy_cann9.2.0_py3.13.16_20261010.tar'
IMAGE_TAG='tx_hy_tenpu:9.2.0_py313_torch2.10.0'  # docker load 实际输出的镜像标签
export DOCKER_HOST='unix:///home/docker-test/docker.sock'

# 1. 安装 Docker（本次 apt-get install -y docker.io 已成功）
apt-get install -y docker.io

# 2. 创建本机 daemon 目录
mkdir -p /home/docker-test /home/docker-exec-test

# 3. 启动 daemon；已运行时不重复启动
if ! docker info >/dev/null 2>&1; then
    nohup dockerd \
        --data-root=/home/docker-test \
        --exec-root=/home/docker-exec-test \
        --host=unix:///home/docker-test/docker.sock \
        --iptables=false \
        --bridge=none \
        --storage-driver=vfs \
        > /home/docker-test/dockerd.log 2>&1 < /dev/null &

    # 等待后台 daemon 初始化
    for i in $(seq 1 30); do
        docker info >/dev/null 2>&1 && break
        sleep 1
    done
fi

# 4. 验证 daemon：失败时显示日志
if ! docker info >/dev/null 2>&1; then
    tail -n 80 /home/docker-test/dockerd.log
    exit 1
fi
echo '[OK] Docker daemon 已启动'
docker ps -a

# 5. 从共享目录加载镜像（本次已成功加载）
ls -lh "$IMAGE_TAR"
df -h /home
if ! docker image inspect "$IMAGE_TAG" >/dev/null 2>&1; then
    docker load -i "$IMAGE_TAR"
else
    echo "[SKIP] 镜像已存在：$IMAGE_TAG"
fi
docker images

# 6. 保存 Docker socket 配置，供以后登录时自动使用
DOCKER_HOST_LINE='export DOCKER_HOST=unix:///home/docker-test/docker.sock'
grep -qxF "$DOCKER_HOST_LINE" "$HOME/.bashrc" || echo "$DOCKER_HOST_LINE" >> "$HOME/.bashrc"

echo '[OK] 全部完成；新开的 Bash 终端将自动使用该 Docker daemon。'
echo '当前交互式终端可执行：source ~/.bashrc'
echo '排错：tail -n 100 /home/docker-test/dockerd.log'
