# CANN OPS 更新在 Docker commit 后丢失的排查与修复

日期：2026-11-02。

## 结论

Docker 使用 vfs 存储驱动，OPS 安装保留了文件的固定 mtime。部分更新文件与父镜像文件大小、权限、mtime 等元数据一致，内容却不同。VFS 的目录差异比较漏检这些文件，commit 后继承了父镜像中的旧文件，形成新旧 OPS 混装。

这不是镜像加载时自动降级，也不是只修改版本显示即可解决的问题。

## 现场证据

- 正常源容器：`tx_hy_tenpu9.2.0_20261102_test`，nn/math/transformer 为 9.2.1，minimal.py 实测 PASS。
- 问题容器：`tx_hy_tenpu9.2.0_20261102_test2`，上述版本为 9.2.0，minimal.py 在 abs 阶段失败，出现 vector core 异常。
- Docker 29.1.3，Storage Driver 为 vfs，Docker Root Dir 为 `/home/docker-test`。
- nn/math/transformer 的 version.info 文件大小分别为 450/408/532 字节，mtime 均为 2026-02-09 00:00:00 +0800，新旧文件内容哈希不同。
- 对正常容器与其父镜像的完整 CANN 目录进行比较，发现 19,712 个文件元数据一致但内容不同，且全部未出现在 docker diff 中。包括 9,669 个 .o、35 个 .so、9,960 个 .json，含 AsStrided 配置。
- 临时更新 ops_nn/version.info 的 mtime 后，docker diff 立即识别到该文件；实验后恢复原 mtime。
- 漏检清单见 missed-files.json。

参考：Moby https://github.com/moby/moby/blob/v28.0.0/pkg/archive/changes.go#L248-L267 。该历史源码解释比较机制；当前环境另有上述实测验证。

## 本次修复

保留旧目标镜像标签：

```text
tx_hy_tenpu:9.2.0_py313_torch2.10.0_20261102_before_vfs_fix
```

从正常的 `_test` 容器修复并提交，目标名称按要求保留 9.2.0 字样，但内部 OPS nn/math/transformer 实际为 9.2.1。

```bash
OLD=tx_hy_tenpu9.2.0_20261102_test
IMAGE=tx_hy_tenpu:9.2.0_py313_torch2.10.0_20261102

docker exec "$OLD" bash -c \
  'find /usr/local/Ascend/cann-9.2.0 -xdev -exec touch -h -m -- {} +'
docker commit "$OLD" "$IMAGE"
```

该操作只改变时间戳，不改写文件内容。必须覆盖完整 CANN 安装目录，不能只 touch version.info。commit 默认会暂停源容器，完成后恢复。

## 后续标准流程

1. 在容器内更新 OPS 后，加载正确的 set_env.sh，用指定的 Python 执行 minimal.py，确保 PASS。
2. 查询实际 Docker 存储驱动：`docker info --format '{{.Driver}}'`。当前 VFS 环境在安装完成后刷新完整 CANN 安装目录的 mtime，再制作镜像。若安装位置改变，命令也要相应调整。
3. 首先使用新标签制作候选镜像，启动全新的验证容器，重新提供 NPU 设备、driver 挂载、共享数据路径与运行环境。
4. 比较源容器和新容器完整 CANN 目录的内容哈希、符号链接和文件路径，不能依赖 docker diff 或版本号作为唯一验证。
5. 在新容器运行 minimal.py，确认 PASS 后再发布正式标签。不要直接沿用已知有问题的 `_test2` 作为正常源。
6. 用 Dockerfile 固化安装包版本和安装过程；在当前 VFS 环境，安装后仍保留更新时间戳步骤。更换存储驱动应作为单独迁移工作，不直接改动现有 Docker 数据目录。
7. 镜像分发使用 docker save/load，保存时记录镜像 ID；load 后核对 ID。commit 不包含 bind mount/volume 中的内容，也不保存当前交互 shell 中临时 export 的变量。启动脚本应显式 source CANN 环境并指定 Python。

回归命令（在已经正确映射 NPU 和共享目录的新容器内）：

```bash
source /usr/local/Ascend/cann-9.2.0/set_env.sh
/opt/conda/envs/hunyuan4_tenpu/bin/python \
  /taijifs_zwfy8/share-305477973/hy_test/CJL_problems/stride_debug/minimal.py
```

本次最终镜像 ID、文件一致性检查及回归结果见下方验收记录。

## 本次验收记录

- 正式镜像：`tx_hy_tenpu:9.2.0_py313_torch2.10.0_20261102`。
- 镜像 ID：`sha256:fea8e361920cceb8006120ef3c871824a2573b754468b1c3a66dfe6d0142d6f1`。
- 新建验证容器：`tx_hy_tenpu_20261102_fixed_verify_v2`。
- 完整 CANN 对比：源容器与新容器各 76,546 个条目，文件内容哈希、符号链接目标与路径零差异。见 hash-verification.json。
- nn/math/transformer 均为 9.2.1。
- 新容器运行 minimal.py：PASS。见 minimal-fixed.log。
- 源容器已恢复运行，未重装 OPS。
- 验证仅使用共享测试目录、驱动相关挂载和 NPU 设备。原配置的 /home:rslave 在当前环境无法直接重新挂载，因此未沿用该项；未修改宿主机挂载传播设置。首次失败的验证容器停留于 Created 状态。
- 本次完成本地镜像制作与启动验收，未导出镜像 tar。
