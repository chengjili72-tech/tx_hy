#!/usr/bin/env bash
# 950-PR container startup candidate — NOT FINAL / pending user hardware validation.
# Based on the user's launch configuration; does not change the verified image.
set -euo pipefail

IMAGE=${IMAGE:-tx_hy:9.1.0-relase}
CONTAINER_NAME=${CONTAINER_NAME:-hg_test_cache}
# Use the same independent daemon unless the caller explicitly selects another.
export DOCKER_HOST=${DOCKER_HOST:-unix:///tmp/docker-test/docker.sock}

if [[ ${1:-} == --help ]]; then
  echo 'Usage: [IMAGE=...] [CONTAINER_NAME=...] bash run-950-PR.sh [--dry-run]'
  exit 0
fi
if (($# > 1)) || [[ ${1:-} != "" && ${1:-} != --dry-run ]]; then
  echo 'Supported option: --dry-run or --help' >&2
  exit 2
fi

NPU_ARGS=()
for dev in /dev/davinci[0-9]*; do
  [[ -c "$dev" ]] && NPU_ARGS+=(--device="$dev")
done

cmd=(
  docker run --name "$CONTAINER_NAME" --ipc host -it -d
  --net=host --shm-size=500g
  --privileged=true
  --ulimit memlock=-1:-1
  -w /data
  --device=/dev/davinci_manager
  --device=/dev/hisi_hdc
  --device=/dev/devmm_svm
  "${NPU_ARGS[@]}"
  --entrypoint=bash
  --label tx_hy.launch-profile=950-PR
  --label tx_hy.validation=pending
  -v /usr/local/Ascend/driver:/usr/local/Ascend/driver
  -v /usr/local/dcmi:/usr/local/dcmi
  -v /usr/local/bin/npu-smi:/usr/local/bin/npu-smi
  -v /usr/local/sbin:/usr/local/sbin
  -v /home:/home
  -v /tmp:/tmp
  -v /data:/data
  -v /data1:/data1
  -v /taijifs_zwfy8:/taijifs_zwfy8
  -v /mnt:/mnt
  "$IMAGE"
  -c 'source /opt/tx_hy/env.sh && exec bash -i'
)

if [[ ${1:-} == --dry-run ]]; then
  printf '%q ' "${cmd[@]}"
  printf '\n'
  exit 0
fi

# Check caller-visible paths for this local DinD setup; do not silently create
# empty directories when a device/driver mount source is missing.
for dev in /dev/davinci_manager /dev/hisi_hdc /dev/devmm_svm; do
  [[ -c "$dev" ]] || { echo "Missing character device: $dev" >&2; exit 1; }
done
for dir in /usr/local/Ascend/driver /usr/local/dcmi /usr/local/sbin /home /tmp /data /data1 /taijifs_zwfy8 /mnt; do
  [[ -d "$dir" ]] || { echo "Missing mount directory: $dir (adjust for the target host)" >&2; exit 1; }
done
[[ -f /usr/local/bin/npu-smi && -x /usr/local/bin/npu-smi ]] || {
  echo 'Missing executable: /usr/local/bin/npu-smi' >&2; exit 1;
}
docker info >/dev/null
docker image inspect "$IMAGE" >/dev/null
if docker container inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
  echo "Container already exists: $CONTAINER_NAME. Use docker start / exec or choose another name." >&2
  exit 1
fi
echo '950-PR candidate: pending hardware validation; not the final launch profile.'
echo 'IPC=host: /dev/shm capacity comes from the daemon host, not an independent 500g allocation.'
"${cmd[@]}"
printf 'Enter with: docker exec -it %q bash\n' "$CONTAINER_NAME"
