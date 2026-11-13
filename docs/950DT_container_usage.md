# Ascend 950DT（16 卡）容器使用说明：Docker / containerd

> 更新时间：2026-11-13。**本文所有命令、名称、镜像、代理和挂载路径均为示例，必须以目标宿主机配置为准。** 基于用户在 950DT 机器上已执行通过的 Docker / ctr 启动方式整理，不代表所有跨机 HCCL、RDMA 或长稳训练已验证。
>
> 镜像：**mirrors.tencent.com/taiji-ptm-mirrors/ubuntu24.04-cann9.2.0-py3.13-torch2.10:ptm_2610_preview12**。单机 16 卡。本页不使用旧版 950DT 的固定 **20G** 共享内存配置。

## 1. 宿主机检查

~~~bash
npu-smi info
ls -l /dev/davinci_manager /dev/hisi_hdc
for i in $(seq 0 15); do
    test -c "/dev/davinci$i" || echo "缺少 NPU 设备节点：/dev/davinci$i"
done
ls -ld /usr/local/Ascend/driver /usr/local/dcmi 2>/dev/null
~~~

检查设备节点只是前置条件，NPU Health 仍应为可用状态。Docker 和 ctr -n k8s.io 的镜像与容器管理命令不同；**从 ctr 拉取镜像不等于 Docker 能直接看到该镜像**。建议选用当前节点已验证可用的一种运行时。

## 2. containerd / ctr 使用方法

### 2.1 镜像拉取和检查

~~~bash
IMAGE="mirrors.tencent.com/taiji-ptm-mirrors/ubuntu24.04-cann9.2.0-py3.13-torch2.10:ptm_2610_preview12"

ctr -n k8s.io images pull "$IMAGE"
ctr -n k8s.io images ls | grep 'ptm_2610_preview12'
ctr -n k8s.io images check | grep 'ptm_2610_preview12'
~~~

已测试镜像拉取输出包含 resolved、各层 done、unpacking done；images check 可进一步检查完整性。若看到 registry mirrors DEPRECATION 警告，这是配置弃用提示，不等于拉取失败。

### 2.2 新建、后台运行容器

将下述代码保存为 **run_950dt_ctr.sh**，执行 bash run_950dt_ctr.sh。该示例不设 20G 共享内存，也没有主动加入宿主 IPC。

~~~bash
#!/usr/bin/env bash
set -euo pipefail

IMAGE="mirrors.tencent.com/taiji-ptm-mirrors/ubuntu24.04-cann9.2.0-py3.13-torch2.10:ptm_2610_preview12"
NAME="tx-hy-950dt-preview12"

# 检查宿主机 16 张 NPU
for i in $(seq 0 15); do
    if [[ ! -c "/dev/davinci$i" ]]; then
        echo "ERROR: /dev/davinci$i 不存在"
        exit 1
    fi
done

# 不覆盖已有容器
if ctr -n k8s.io containers info "$NAME" >/dev/null 2>&1; then
    echo "ERROR: 已存在容器 $NAME"
    exit 1
fi

# 根据宿主机实际存在的路径生成挂载列表
MOUNTS=()
add_mount() {
    local src="$1" dst="${2:-$1}"
    if [[ -e "$src" ]]; then
        MOUNTS+=(--mount "type=bind,src=$src,dst=$dst,options=rbind:rw")
    else
        echo "SKIP: 不存在的挂载源 $src"
    fi
}

for path in \
    /usr/local/Ascend/driver /usr/local/Ascend/firmware \
    /usr/local/dcmi /usr/local/bin/npu-smi /usr/local/sbin/npu-smi \
    /etc/hccl_rootinfo.json /etc/hixlep \
    /etc/atlas_topo_galaxy.json /etc/ascend_install.info \
    /root/host /mnt /home /data \
    /taijifs_zwfy8 /taijifs_zwfy /taijifs_cqtl31; do
    add_mount "$path"
done
add_mount /var/log/npu /usr/slog
add_mount /taijifs_zwfy8 /apdcephfs_zwfy8
add_mount /taijifs_zwfy /apdcephfs_zwfy

ctr -n k8s.io run -d \
    --runtime io.containerd.runc.v2 \
    --privileged \
    --net-host \
    --user 0:0 \
    "${MOUNTS[@]}" \
    "$IMAGE" "$NAME" \
    /bin/bash -lc 'exec sleep infinity'

echo "已启动：$NAME"
~~~

**配置说明：** ctr 的 --privileged 在常见 runc 实现中允许并传入宿主设备，因此该方案不重复指定 16 个 --device；仍需在容器中检查设备可见性。--net-host 只设置网络，**不等于 --ipc=host**。这里未指定独立共享内存大小；通过 df -h /dev/shm 查看实际值。缺失的目录会跳过，不意味着相关 NPU/驱动/HCCL 功能可以正常运行。

### 2.3 ctr 常用查询、进入和管理命令

~~~bash
NAME="tx-hy-950dt-preview12"

# 镜像与任务查询
ctr -n k8s.io images ls
ctr -n k8s.io images check
ctr -n k8s.io containers ls
ctr -n k8s.io containers info "$NAME"
ctr -n k8s.io tasks ls

# 进入容器，exec-id 每次必须唯一
ctr -n k8s.io tasks exec \
    --exec-id "shell-$(date +%s)-$$" -t "$NAME" /bin/bash

# 停止后再清理（操作前核对名称，不要操作 Kubernetes 托管的任务）
ctr -n k8s.io tasks kill --signal SIGTERM "$NAME"
ctr -n k8s.io tasks ls
# 确认任务已停止：
ctr -n k8s.io tasks rm "$NAME"
# 不再需要该容器文件系统时：
ctr -n k8s.io containers rm "$NAME"

# 镜像打包/导入（按需执行，不代表保存容器可写层）
# ctr -n k8s.io images export preview12.tar "$IMAGE"
# ctr -n k8s.io images import preview12.tar
~~~

说明：containerd 中 **container（容器元数据）** 和 **task（运行进程）** 是不同对象。k8s.io 命名空间可能存在 Kubernetes 管理的资源，切勿直接清理非自己创建的任务。

## 3. Docker 使用方法

### 3.1 配置代理、拉取镜像

~~~bash
# 内部代理仅为示例，按节点网络配置设置
export https_proxy=http://star-proxy.oa.com:3128
export http_proxy=http://star-proxy.oa.com:3128

IMAGE="mirrors.tencent.com/taiji-ptm-mirrors/ubuntu24.04-cann9.2.0-py3.13-torch2.10:ptm_2610_preview12"
docker pull "$IMAGE"
docker images | grep 'ptm_2610_preview12'
~~~

说明：shell 代理变量不保证自动作用于独立运行的 Docker daemon，拉取失败时须检查 daemon 代理/认证配置。

### 3.2 新建、后台运行容器

将代码保存为 **run_950dt_docker.sh**，执行 bash run_950dt_docker.sh。基于已测试命令，保留 NPU、网络、IPC、驱动、RDMA 和大量共享目录；自动检测设备并去重挂载。原命令同时设置 --ipc=host 和 --shm-size=500g；**host IPC 使用宿主共享内存，--shm-size 不提供独立 500G 限额，所以此处去掉冗余选项**。如果需要私有 IPC 和自定义容量，另外以 --ipc=private --shm-size=<容量> 测试。

~~~bash
#!/usr/bin/env bash
set -euo pipefail

IMAGE="mirrors.tencent.com/taiji-ptm-mirrors/ubuntu24.04-cann9.2.0-py3.13-torch2.10:ptm_2610_preview12"
CONTAINER_NAME="tx_hy_tenpu9.2.0_20261113"

NPU_ARGS=()
for dev in /dev/davinci[0-9]*; do
    if [[ -c "$dev" ]]; then
        NPU_ARGS+=(--device="$dev")
    fi
done
if [[ ${#NPU_ARGS[@]} -ne 16 ]]; then
    echo "ERROR: 预期 16 张卡，找到 ${#NPU_ARGS[@]} 张"
    exit 1
fi

for dev in /dev/davinci_manager /dev/hisi_hdc /dev/devmm_svm /dev/infiniband; do
    if [[ ! -e "$dev" ]]; then
        echo "ERROR: 缺少设备/目录 $dev"
        exit 1
    fi
done

if docker container inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
    echo "ERROR: 已存在容器 $CONTAINER_NAME"
    exit 1
fi

# 自动跳过不在本节点的目录，避免 Docker -v 创建意外空目录
VOLUMES=()
add_volume() {
    local src="$1" dst="${2:-$1}"
    if [[ -e "$src" ]]; then
        VOLUMES+=(-v "$src:$dst")
    else
        echo "SKIP: 不存在的挂载源 $src"
    fi
}

for path in \
    /etc/libibverbs.d /usr/local/Ascend/driver /usr/local/dcmi \
    /usr/local/bin/npu-smi /usr/local/sbin \
    /home /tmp /taijifs_zwfy8 /taijifs_zwfy \
    /apdcephfs_jn2 /cfs_hy_aide \
    /apdcephfs_zwfy10 /apdcephfs_zwfy6 /apdcephfs_zwfy2 \
    /apdcephfs_zwfy11 /apdcephfs_zwfy14 /apdcephfs_zwfy5 \
    /apdcephfs_zwfy3 /apdcephfs_nj11 /apdcephfs_nj8 \
    /apdcephfs_jn4 /apdcephfs_jn5 /apdcephfs_nj12 \
    /apdcephfs_nj2 /apdcephfs_nj4 /apdcephfs_nj9 \
    /apdcephfs_jn /apdcephfs_nj10 /apdcephfs_jn3 \
    /apdcephfs_nj3 /apdcephfs_wzc1 /taijifs_wzc3 \
    /apdcephfs_wzc2; do
    add_volume "$path"
done
add_volume /taijifs_zwfy8 /apdcephfs_zwfy8
add_volume /taijifs_zwfy /apdcephfs_zwfy

docker run --name "$CONTAINER_NAME" \
    --ipc=host -it -d \
    --net=host \
    --privileged=true \
    --ulimit memlock=-1:-1 \
    -w /workspace \
    --device=/dev/davinci_manager \
    --device=/dev/hisi_hdc \
    --device=/dev/devmm_svm \
    --device=/dev/infiniband \
    "${NPU_ARGS[@]}" \
    --entrypoint=bash \
    "${VOLUMES[@]}" \
    "$IMAGE"

echo "进入容器：docker exec -it $CONTAINER_NAME bash"
~~~

### 3.3 Docker 常用命令

~~~bash
CONTAINER_NAME="tx_hy_tenpu9.2.0_20261113"

docker ps -a
docker ps
docker images
docker inspect "$CONTAINER_NAME"
docker exec -it "$CONTAINER_NAME" bash
docker logs --tail 100 "$CONTAINER_NAME"
docker stop "$CONTAINER_NAME"
docker start "$CONTAINER_NAME"

# 确认不再需要容器或镜像时：
# docker rm "$CONTAINER_NAME"
# docker rmi "$IMAGE"
~~~

## 4. 容器内部验证（两种方式通用）

~~~bash
cat /etc/os-release | head -5
python --version
df -h /dev/shm
ls -l /dev/davinci[0-9]* 2>/dev/null
npu-smi info

python - <<'PY'
import torch
import torch_npu
print("Torch:", torch.__version__)
print("NPU available:", torch.npu.is_available())
print("Visible NPU count:", torch.npu.device_count())
PY
~~~

预期设备数量为 16，但 device_count==16 只代表可枚举，仍须确认每张卡健康、NPU 算子实际执行及 HCCL 通信。个别镜像进入容器后需要根据实际安装路径手动 source CANN/Conda 环境。

## 5. 差异、权限和注意事项

| 对比项 | ctr | Docker |
|---|---|---|
| 镜像 | ctr -n k8s.io images pull | docker pull |
| 进入容器 | ctr tasks exec（需唯一 exec-id） | docker exec -it |
| 管理 | containers 与 tasks 分开管理 | docker ps / stop / start |
| 网络 | --net-host | --net=host |
| IPC | 示例未使用宿主 IPC | --ipc=host |
| 共享内存大小 | 未指定固定值 | host IPC，不单设 --shm-size |
| 设备 | 特权模式可访问宿主设备 | 显式添加现有 NPU/管理设备 |

- **权限风险：** --privileged、宿主网络和 /home、/tmp、共享目录的可写 bind mount 都可能影响宿主机或其他作业，仅限受信开发节点；必要时使用只读挂载。
- **驱动：** 宿主驱动目录可按需挂载，不要直接把整个 /usr/local/Ascend 覆盖到同一路径，以免盖掉镜像内 CANN 用户态包。
- **持久化：** bind mount 中的数据位于宿主机，容器可写层不等于共享目录；删除容器前确认数据是否保留。
- **版本：** 镜像标签、节点挂载路径均为示例。迁移到其他节点时需核对 OS/架构、driver/CANN、RDMA、HCCL、拓扑和实际可见卡数。

## 6. 官方参考

- [Docker 容器启动与 IPC](https://docs.docker.com/reference/cli/docker/container/run/)
- [containerd ctr 参数](https://github.com/containerd/containerd/blob/main/cmd/ctr/commands/commands.go)
- [containerd ctr run Linux 实现](https://github.com/containerd/containerd/blob/main/cmd/ctr/commands/run/run_unix.go)
