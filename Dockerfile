# syntax=docker/dockerfile:1
# Reference: Ascend/cann-container-image/cann/9.1.0-950-ubuntu22.04-py3.12/Dockerfile
# Target: x86_64 Ascend 950; driver and firmware are installed on the host.
FROM ubuntu:24.04

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG TARGETARCH=amd64
ARG MINIFORGE_URL=https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-x86_64.sh
# Optional checksum for an explicitly pinned installer URL.
ARG MINIFORGE_SHA256=""
ARG CANN_DOWNLOAD_BASE=https://ascend-repo.obs.cn-east-2.myhuaweicloud.com/CANN/CANN%209.1.0
# Empty values preserve the user's unpinned install commands.
ARG TRITON_ASCEND_VERSION=""
ARG TENPU_REF=""

ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    CONDA_ENV_NAME=hunyuan4_tenpu \
    CONDA_PREFIX=/opt/conda/envs/hunyuan4_tenpu \
    PATH=/opt/conda/envs/hunyuan4_tenpu/bin:/opt/conda/bin:${PATH}

# 1. OS and native build dependencies (also retained for editable development).
RUN test "${TARGETARCH}" = amd64 && test "$(uname -m)" = x86_64 && \
    apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl wget git bash build-essential cmake ninja-build \
      pkg-config gfortran patchelf unzip bzip2 xz-utils \
      zlib1g-dev libssl-dev libffi-dev libsqlite3-dev libbz2-dev \
      libreadline-dev liblzma-dev libncurses-dev libgdbm-dev libnss3 \
      libblas-dev liblapack-dev libnuma-dev libgomp1 libstdc++6 \
      libgl1 libglib2.0-0t64 libjpeg-dev libpng-dev \
      pciutils net-tools procps less vim-tiny && \
    rm -rf /var/lib/apt/lists/*

# 2. Miniforge provides conda with conda-forge as the package channel.
# Python is pinned exactly; never silently fall back to another patch release.
RUN <<'BASH'
set -e
curl -fL --retry 3 "${MINIFORGE_URL}" -o /tmp/miniforge.sh
if [ -n "${MINIFORGE_SHA256}" ]; then
    echo "${MINIFORGE_SHA256}  /tmp/miniforge.sh" | sha256sum -c -
fi
mkdir -p /opt/tx_hy/build-info
sha256sum /tmp/miniforge.sh > /opt/tx_hy/build-info/miniforge.sha256
bash /tmp/miniforge.sh -b -p /opt/conda
rm /tmp/miniforge.sh
conda create -y -n hunyuan4_tenpu --override-channels -c conda-forge \
    python=3.13.16 'python_abi=3.13=*_cp313' pip setuptools wheel
conda clean -afy
python -c 'import sys,sysconfig; assert sys.version_info[:3] == (3,13,16); assert not sysconfig.get_config_var("Py_GIL_DISABLED"); assert not sysconfig.get_config_var("Py_DEBUG"); print(sys.version)'
BASH

# 3. Keep the user's fixed versions across EVERY subsequent pip operation.
# Unspecified versions remain resolver-selected, as requested.
RUN <<'BASH'
set -e
cat > /opt/tx_hy/constraints.txt <<'EOF'
torch==2.10.0+cpu
torch-npu==2.10.0.post6
torchvision==0.25.0
pillow==12.2.0
tokenizers==0.22.2
transformers==4.57.1
einops==0.8.2
pynvml==13.0.1
omegaconf==2.3.1
mbridge==0.15.1
pycryptodomex==3.23.0
protobuf==3.20.0
EOF
if [ -n "${TRITON_ASCEND_VERSION}" ]; then
    printf 'triton-ascend==%s\n' "${TRITON_ASCEND_VERSION}" >> /opt/tx_hy/constraints.txt
fi
BASH
ENV PIP_CONSTRAINT=/opt/tx_hy/constraints.txt

# CANN runtime prerequisites from the reference Dockerfile.
RUN python -m pip install --upgrade pip setuptools wheel && \
    python -m pip install attrs cython numpy decorator sympy cffi pyyaml \
      pathlib2 psutil protobuf==3.20.0 scipy requests absl-py packaging ninja

# 4. Install the SAME three CANN 9.1.0 x86_64 packages as the reference.
# Download/install/remove in one layer so the ~4.4 GB installers are not retained.
RUN <<'BASH'
set -e
mkdir -p /tmp/cann-installers
cd /tmp/cann-installers
for package in toolkit 950-ops nnal; do
    filename="Ascend-cann-${package}_9.1.0_linux-x86_64.run"
    curl -fL --retry 3 --referer 'https://www.hiascend.com/' \
        "${CANN_DOWNLOAD_BASE}/${filename}" -o "${filename}"
    sha256sum "${filename}" >> /opt/tx_hy/build-info/cann-installers.sha256
    chmod +x "${filename}"
    if [ "${package}" = nnal ]; then
        source /usr/local/Ascend/ascend-toolkit/set_env.sh
    fi
    "./${filename}" --quiet --install --install-for-all
    rm "${filename}"
done
test -f /usr/local/Ascend/ascend-toolkit/set_env.sh
test -f /usr/local/Ascend/nnal/atb/set_env.sh
cd /
rmdir /tmp/cann-installers
BASH

# 5. One environment initializer for build, entrypoint and interactive shells.
# Vendor environment scripts are sourced without nounset (-u).
ENV ATB_CXX_ABI=1
RUN <<'BASH'
set -e
cat > /opt/tx_hy/env.sh <<'EOF'
source /opt/conda/etc/profile.d/conda.sh || return $?
conda activate hunyuan4_tenpu || return $?
source /usr/local/Ascend/ascend-toolkit/set_env.sh || return $?
source /usr/local/Ascend/cann-9.1.0/share/info/ascendnpu-ir/bin/set_env.sh || return $?
source /usr/local/Ascend/nnal/atb/set_env.sh --cxx_abi="${ATB_CXX_ABI:-1}" || return $?
export LD_LIBRARY_PATH="/usr/local/Ascend/driver/lib64:/usr/local/Ascend/driver/lib64/common:/usr/local/Ascend/driver/lib64/driver${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
EOF
cat > /usr/local/bin/tx-hy-entrypoint <<'EOF'
#!/bin/bash
set -e
source /opt/tx_hy/env.sh
exec "$@"
EOF
chmod +x /usr/local/bin/tx-hy-entrypoint
printf '\nsource /opt/tx_hy/env.sh\n' >> /etc/bash.bashrc
cat > /etc/profile.d/tx-hy.sh <<'EOF'
if [ -n "${BASH_VERSION:-}" ]; then
    source /opt/tx_hy/env.sh
fi
EOF
BASH

# 6. PyTorch CPU build + Ascend backend; no NPU execution during docker build.
RUN source /opt/tx_hy/env.sh && \
    python -m pip install torch==2.10.0+cpu --index-url https://download.pytorch.org/whl/cpu && \
    python -m pip install torch-npu==2.10.0.post6 \
      --extra-index-url https://ascend.devcloud.huaweicloud.com/pypi/simple/

# 7. Preserve the requested Triton-Ascend install command.
# Let its dependency metadata select the matching Triton; do not overwrite it later.
RUN source /opt/tx_hy/env.sh && \
    python -m pip install triton-ascend \
      --extra-index-url=https://mirrors.huaweicloud.com/ascend/repos/pypi

# 8. TENPU editable install. Keep its source tree at this stable absolute path.
RUN <<'BASH'
set -e
source /opt/tx_hy/env.sh
mkdir -p /opt/src
git clone https://gitcode.com/Ascend/TransformerEngineNPU.git /opt/src/TransformerEngineNPU
if [ -n "${TENPU_REF}" ]; then
    git -C /opt/src/TransformerEngineNPU checkout --detach "${TENPU_REF}"
fi
git -C /opt/src/TransformerEngineNPU rev-parse HEAD > /opt/tx_hy/build-info/tenpu-commit.txt
python -m pip install -e /opt/src/TransformerEngineNPU --no-build-isolation
BASH

# 9. angelptm_hy4 dependencies. CPU torchvision matches torch+cpu and avoids
# CUDA-linked torchvision binaries. Keep --no-deps as requested.
RUN source /opt/tx_hy/env.sh && \
    python -m pip install torchvision==0.25.0 --no-deps --index-url https://download.pytorch.org/whl/cpu && \
    python -m pip install pillow==12.2.0 tokenizers==0.22.2 transformers==4.57.1 \
      einops==0.8.2 pynvml==13.0.1 omegaconf==2.3.1 orjson numba \
      mbridge==0.15.1 pycryptodomex==3.23.0 pycryptodome

# 10. Fail on inconsistent metadata and record the actual resolved environment.
# NPU imports/kernels and distributed communication are runtime checks on 950.
RUN <<'BASH'
set -e
source /opt/tx_hy/env.sh
python -m pip check
python -c 'import sys; from importlib.metadata import version; assert sys.version_info[:3] == (3,13,16); assert version("torch") == "2.10.0+cpu"; assert version("torch-npu") == "2.10.0.post6"; print("Pinned framework versions: OK")'
python -m pip freeze --all > /opt/tx_hy/build-info/pip-freeze.txt
python -m pip list --format=json > /opt/tx_hy/build-info/pip-list.json
conda list --explicit -n hunyuan4_tenpu > /opt/tx_hy/build-info/conda-explicit.txt
conda env export -n hunyuan4_tenpu > /opt/tx_hy/build-info/environment.yml
cp /etc/os-release /opt/tx_hy/build-info/os-release
python --version > /opt/tx_hy/build-info/python-version.txt
BASH

WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/tx-hy-entrypoint"]
CMD ["bash"]
