"""Run on the target 950 host INSIDE the image; failure exits nonzero."""
import importlib
import os
import sys
from importlib.metadata import version

assert sys.version_info[:3] == (3, 13, 16), sys.version
for distribution in (
    "torch", "torch-npu", "torchvision", "triton", "triton-ascend",
    "transformer_engine", "transformers", "tokenizers", "numba", "mbridge",
):
    print(f"{distribution}: {version(distribution)}", flush=True)

import torch
import torch_npu

import runpy
runpy.run_path('/opt/tx_hy/check_versions.py', run_name='__main__')
assert torch.npu.is_available(), "NPU is unavailable: check host driver/device mounts"
device = int(os.environ.get("NPU_DEVICE", "0"))
torch.npu.set_device(device)
x = torch.randn(3, 4, device=f"npu:{device}")
y = x + x
torch.npu.synchronize()
torch.testing.assert_close(y.cpu(), x.cpu() * 2)
print(y, flush=True)

for module in (
    "torchvision", "transformer_engine.pytorch", "transformers", "tokenizers",
    "PIL", "einops", "pynvml", "omegaconf", "orjson", "numba", "mbridge",
    "Crypto", "Cryptodome", "yaml", "google.protobuf",
):
    importlib.import_module(module)
    print(f"IMPORT OK: {module}", flush=True)

import triton
import triton.language as tl


@triton.jit
def add_kernel(X, Y, Z, N: tl.constexpr, BLOCK: tl.constexpr):
    offsets = tl.program_id(0) * BLOCK + tl.arange(0, BLOCK)
    mask = offsets < N
    a = tl.load(X + offsets, mask=mask, other=0)
    b = tl.load(Y + offsets, mask=mask, other=0)
    tl.store(Z + offsets, a + b, mask=mask)


n = 4096
a = torch.randn(n, device=f"npu:{device}", dtype=torch.float32)
b = torch.randn_like(a)
c = torch.empty_like(a)
add_kernel[(triton.cdiv(n, 256),)](a, b, c, n, BLOCK=256)
torch.npu.synchronize()
torch.testing.assert_close(c.cpu(), a.cpu() + b.cpu())
print("PASS: imports, torch_npu addition, Triton-Ascend vector addition")
print("This smoke test does not validate TENPU model execution or multi-device HCCL.")
