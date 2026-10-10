#!/usr/bin/env bash
# Selected local installers; all other dependencies may still use the network.
set -euo pipefail
usage() {
  cat <<'EOF'
Usage: bash offline/build.sh \
  --toolkit /path/toolkit.run --ops /path/950-ops.run --nnal /path/nnal.run \
  --torch /path/torch.whl --torch-npu /path/torch_npu.whl \
  --triton-ascend /path/triton_ascend.whl [--triton /path/triton.whl] \
  [--tag tx_hy:partial-offline] [-- extra docker build options]
Set OFFLINE_STAGING_ROOT to a directory with enough free space if /tmp is small.
Optional --triton supplies the base Triton wheel if the Ascend wheel needs an
unreleased Triton version. Default network: host; shell proxies are forwarded.
EOF
}
repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
declare -A inputs=()
tag=tx_hy:partial-offline
extra=()
while (($#)); do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --toolkit|--ops|--nnal|--torch|--torch-npu|--triton-ascend|--triton)
      (($# >= 2)) || { echo "Missing value for $1" >&2; exit 2; }
      inputs["${1#--}"]=$2; shift 2 ;;
    --tag)
      (($# >= 2)) || { echo 'Missing tag' >&2; exit 2; }
      tag=$2; shift 2 ;;
    --) shift; extra=("$@"); break ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done
for key in toolkit ops nnal torch torch-npu triton-ascend; do
  [[ -n ${inputs[$key]:-} ]] || { echo "Required: --$key" >&2; exit 2; }
done
for key in "${!inputs[@]}"; do
  path=${inputs[$key]}
  [[ -f $path && -r $path && -s $path ]] || { echo "Unreadable/empty file: $path" >&2; exit 2; }
  case "$key:$path" in
    toolkit:*.run|ops:*.run|nnal:*.run|torch:*.whl|torch-npu:*.whl|triton-ascend:*.whl|triton:*.whl) ;;
    *) echo "Wrong file extension for --$key: $path" >&2; exit 2 ;;
  esac
done
command -v docker >/dev/null
docker buildx version >/dev/null
# Stage only the explicitly selected files, never their entire parent directories.
staging_parent=${OFFLINE_STAGING_ROOT:-${TMPDIR:-/tmp}}
mkdir -p -- "$staging_parent"
stage=$(mktemp -d "${staging_parent%/}/tx-hy-offline.XXXXXXXX")
trap 'rm -rf -- "$stage"' EXIT
mkdir -p "$stage/cann" "$stage/wheels"
for key in "${!inputs[@]}"; do
  path=${inputs[$key]}
  case "$key" in
    toolkit|ops|nnal) dst="$stage/cann/$key.run" ;;
    *) mkdir -p "$stage/wheels/$key"; dst="$stage/wheels/$key/$(basename -- "$path")" ;;
  esac
  # Never chmod or edit these links: they may refer to the caller's originals.
  ln -- "$path" "$dst" 2>/dev/null || cp --reflink=auto -- "$path" "$dst"
  printf '%s\t%s\n' "$key" "$(basename -- "$path")" >> "$stage/original-filenames.tsv"
done
export DOCKER_BUILDKIT=1
docker build \
  --network=host --platform linux/amd64 --progress=plain \
  --build-arg HTTP_PROXY="${http_proxy:-${HTTP_PROXY:-}}" \
  --build-arg HTTPS_PROXY="${https_proxy:-${HTTPS_PROXY:-}}" \
  --build-arg ALL_PROXY="${all_proxy:-${ALL_PROXY:-}}" \
  --build-arg NO_PROXY="${no_proxy:-${NO_PROXY:-}}" \
  --build-context "offline_inputs=$stage" \
  -f "$repo_dir/offline/Dockerfile" -t "$tag" \
  "${extra[@]}" "$repo_dir"
