# 机器重启后恢复共享盘

本次恢复的共享盘：`/taijifs_cqtl31/share304153846`。

## 1. 确认是否已挂载

```bash
findmnt -M /taijifs_cqtl31/share304153846
ls -la /taijifs_cqtl31/share304153846
```

如果 `findmnt` 已显示该挂载点，不要重复挂载或移动目录。工作目录暂时为空，不代表远端数据已丢失。

## 2. 执行挂载

机器已有 `taiji_client`，并保存了可访问该共享盘的平台身份，本次没有重新输入 token。

挂载点为空或不存在时，执行：

```bash
taiji_client mount --mount_path /taijifs_cqtl31/share304153846
```

本次重启后，尚未挂载的本地路径下被重新创建了空的项目目录。客户端要求挂载目标为空，因此先保留这个本地占位目录，再挂载。**下面的改名仅用于确认尚未挂载、且目录是本地占位目录的情况；不要对已经挂载的共享盘执行。**

本次实际使用的命令：

```bash
mv /taijifs_cqtl31/share304153846 /taijifs_cqtl31/share304153846.reboot-placeholder-20261125
taiji_client mount --mount_path /taijifs_cqtl31/share304153846 > /tmp/cew_mount_recovery_20261125.log 2>&1
cat /tmp/cew_mount_recovery_20261125.log
```

`mv` 保留了原目录，没有删除或覆盖数据。再次恢复时，备份目录应使用新的、不存在的名称；如果本地占位目录里已有文件，也先保留并单独核对。

## 3. 验证恢复

```bash
findmnt -M /taijifs_cqtl31/share304153846
ls -la /taijifs_cqtl31/share304153846/tx_hy/CJL_arXiv_experiments/checkpoint-equivalence-lab
git -C /taijifs_cqtl31/share304153846/tx_hy/CJL_arXiv_experiments/checkpoint-equivalence-lab status --short
```

本次客户端返回 `Mount hifs ... successfully`，原仓库、论文、实验产物重新可见。另按实验归档收据逐文件复核大小及 SHA-256，确认恢复后的原始载荷与中断前一致；挂载成功本身不能替代完整性校验。

## 原理

共享盘的数据保存在远端 HIFS 存储。本地路径是访问远端文件的入口，客户端通过文件系统挂载把远端目录呈现给本机程序。

本次机器重启后，挂载未自动恢复，程序看到的是挂载点下的本地空目录。重新执行平台挂载命令后，同一路径再次指向原来的远端存储，因此原文件重新出现，无需重新训练或复制全部数据。客户端记录的跨园区访问提示属于延迟提示，不是挂载失败。

如果命令提示身份或权限失败，需要恢复平台登录/授权；不要把 token 或密码写入仓库，也不要通过格式化磁盘解决挂载问题。
