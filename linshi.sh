export DOCKER_HOST=unix:///tmp/docker-test/docker.sock
set -o pipefail

bash offline/build.sh \
  --toolkit "/taijifs_zwfy8/share-305477973/hy_test/packet/cann_packet_9.2.0/Ascend-cann-toolkit_9.2.0_linux-x86_64.run" \
  --ops "/taijifs_zwfy8/share-305477973/hy_test/packet/cann_packet_9.2.0/Ascend-cann-950-ops_9.2.0_linux-x86_64.run" \
  --nnal "/taijifs_zwfy8/share-305477973/hy_test/packet/cann_packet_9.2.0/Ascend-cann-nnal_9.2.0_linux-x86_64.run" \
  --torch "/taijifs_zwfy8/share-305477973/hy_test/packet/pta_2.10.0/torch-2.10.0+cpu-cp313-cp313-manylinux_2_28_x86_64.whl" \
  --torch-npu "/taijifs_zwfy8/share-305477973/hy_test/packet/pta_2.10.0/torch_npu-2.10.0.post7-cp313-cp313-manylinux_2_28_x86_64.whl" \
  --triton-ascend "/taijifs_zwfy8/share-305477973/hy_test/packet/triton_ascend_3.6.0/triton_ascend-3.6.0+dev20260923230212-cp313-cp313-manylinux_2_27_x86_64.manylinux_2_28_x86_64.whl" \
  --tag tx_hy_tenpu:9.2.0_py313_torch2.10.0 \
  2>&1 | tee build-partial-offline.log



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
    -v /apdcephfs_jn2:/apdcephfs_jn2 \
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

容器里安装 roce 相关依赖（cx7网卡）
apt-get install net-tools iputils libverbs rdma-core perftest -y
apt-get install -y \
  net-tools \
  iproute2 \
  iputils-ping \
  libibverbs1 \
  ibverbs-providers \
  ibverbs-utils \
  rdma-core \
  perftest



export https_proxy=http://star-proxy.oa.com:3128
export http_proxy=http://star-proxy.oa.com:3128

curl -fsSL https://www.codebuddy.cn/cli/install.sh | bash

apt update && apt install -y lrzsz

apt-get update

apt-get install -y \
    vim \
    git \
    curl \
    wget \
    less \
    procps \
    iproute2 \
    iputils-ping \
    net-tools \
    lsof \
    unzip \
    psmisc \
    ca-certificates

pip uninstall torchvision
pip install torchvision==0.25.0 --no-deps

tail -n 100 -f output/train.log
帮我使用profile采集一下训练整网的profile,采集步数为第9到10步共两步,包含调用栈,ops,profiler_level=Level1,record_shapes=True,profile_memory 
  =True,,采集所有卡数,训练启动命令为当前目录下bash 
  start_cmd.sh,环境为/opt/conda/envs/hunyuan4_tenpu,将采集数据放在/taijifs_cqtl31/share304153846/tx_hy/profile,采集成功后将你修改的代码部分 
  和步骤整理成一份md也放在同目录下


ssh -N \
  -L 127.0.0.1:18080:127.0.0.1:8080 \
  -p 36000 用户名@服务器地址


export TORCHINDUCTOR_NPU_BACKEND=ascendc
env -u PIP_CONSTRAINT python -m pip install triton-ascend --extra-index-url=https://mirrors.huaweicloud.com/ascend/repos/pypi


(
set -euo pipefail
log_dir="gm_copy_check_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$log_dir"

for ep in 2 4; do
    port=$((29600 + ep * 10))
    OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 \
    python -u test/test_v1_intranode.py \
        --ep-size "$ep" \
        --first-device 0 \
        --transport mte \
        --num-tokens 129 \
        --hidden 6144 \
        --num-topk 8 \
        --experts-per-rank "$((384 / ep))" \
        --num-aiv 32 \
        --seed 20260823 \
        2>&1 | tee "$log_dir/ep${ep}.log"
done
)


source /usr/local/Ascend/cann/set_env.sh

mkdir -p /taijifs_zwfy8/share-305477973/hunyuan/jensengeng/hy4/cjl_profile

msprof \
    --output="/taijifs_zwfy8/share-305477973/hunyuan/jensengeng/hy4/cjl_profile" \
    --task-time=l1 \
    --runtime-api=on \
    --hccl=on \
    bash investigation_20261012/run_experiment.sh p2p_cross_sendfirst_warm




1．先退出所有正在运行的 Codex，再复制现有数据（只执行一次）：
mkdir -m 700 /taijifs_zwfy8/share-305477973/hy_test/codex_home && \
cp -a /root/.codex/. /taijifs_zwfy8/share-305477973/hy_test/codex_home/

如果提示目录已经存在，先检查其中内容，不要重复覆盖旧会话。

2．设置当前容器使用新路径：
export CODEX_HOME="/taijifs_zwfy8/share-305477973/hy_test/codex_home"
export PATH="$HOME/.local/bin:$PATH"

cat >> ~/.bashrc <<'EOF'
export CODEX_HOME="/taijifs_zwfy8/share-305477973/hy_test/codex_home"
export PATH="$HOME/.local/bin:$PATH"
EOF

# 打开历史会话列表
codex resume --all

resume --all 可以查找不同工作目录下的历史会话。ChatGPT Learn

3．以后更换容器，在新容器中执行：
# 指向原有数据目录，不要重新复制旧容器的 /root/.codex
export CODEX_HOME="/taijifs_zwfy8/share-305477973/hy_test/codex_home"

# 在新容器中安装命令入口
curl -fsSL https://chatgpt.com/codex/install.sh | sh

export PATH="$HOME/.local/bin:$PATH"

# 保存新容器的环境设置
cat >> ~/.bashrc <<'EOF'
export CODEX_HOME="/taijifs_zwfy8/share-305477973/hy_test/codex_home"
export PATH="$HOME/.local/bin:$PATH"
EOF

# 继续之前的会话
codex resume --all
codex resume --last --sandbox danger-full-access --ask-for-approval on-request
codex resume --all --sandbox danger-full-access --ask-for-approval on-request
/expert
codex --sandbox danger-full-access --ask-for-approval on-request
/apdcephfs_zwfy/share_305477973/eiren/Ascend200/driver/tools/msnpureport




python3 scripts/launch_hccl.py \
  --hosts root@28.157.231.17 root@28.157.242.135 \
  --container tx_hy_tenpu9.2.0_20261026 \
  --shared-dir "$PWD" \
  --python /opt/conda/envs/hunyuan4_tenpu/bin/python \
  --cann-env /opt/tx_hy/env.sh \
  --preflight-timeout 300 \
  --ep 4 --timeout 300 --port 23456 \
  --output "$PWD/logs/A_hccl/container_ep4_20261026_NEW5"

DOCKER_HOST=unix:///home/docker-test/docker.sock
/taijifs_cqtl31/share304153846/jensengeng/angelptm_runs/20261022_161345_2118/tensorboard/profile/timeline_rank_0_4039_20261022162146640_ascend_pt
