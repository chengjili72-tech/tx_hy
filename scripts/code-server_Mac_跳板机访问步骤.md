# Mac 通过跳板机访问 code-server

将下文 `YOUR_USER`、`YOUR_SERVER_IP`、`YOUR_SSH_PORT` 和 `/path/to/project` 替换为自己的配置。`127.0.0.1` 是本地回环地址，保持不变。

访问链路：Mac 浏览器 → VS Code 端口转发 → 跳板环境 18080 → 目标服务器 8080。

## 1. 用 Mac 的 VS Code 连接跳板环境

打开 VS Code 终端，确认当前终端位于跳板机环境。

## 2. 在终端 A 登录目标服务器并启动 code-server

```bash
TARGET_USER="YOUR_USER"
TARGET_HOST="YOUR_SERVER_IP"
TARGET_PORT="YOUR_SSH_PORT"
ssh "$TARGET_USER@$TARGET_HOST" -p "$TARGET_PORT"
code-server
```

看到以下输出说明启动成功，保持终端 A 运行：

```text
HTTP server listening on http://127.0.0.1:8080/
```

## 3. 在终端 B 建立 SSH 端口转发

在 VS Code 新建一个终端，确认仍是跳板环境 `跳板机终端`，执行：

```bash
TARGET_USER="YOUR_USER"
TARGET_HOST="YOUR_SERVER_IP"
TARGET_PORT="YOUR_SSH_PORT"
ssh -N \
  -L 127.0.0.1:18080:127.0.0.1:8080 \
  "$TARGET_USER@$TARGET_HOST" -p "$TARGET_PORT"
```

输入密码后没有输出是正常的，保持终端 B 运行。

## 4. 在 VS Code 转发 18080 端口

打开底部 **端口 / Ports** 面板 → **转发端口** → 输入 `18080` → 点击 **在浏览器中打开**。

以面板显示的本地地址为准。如果本地端口仍为 18080，访问：

<http://127.0.0.1:18080>

## 5. 登录并打开项目

需要查看登录密码时，在另一个终端登录目标服务器后执行：

```bash
cat ~/.config/code-server/config.yaml
```

使用配置中的 `password` 登录网页，然后选择 **File → Open Folder**，打开：

```text
/path/to/project
```

选择 **Terminal → New Terminal** 即可打开目标服务器终端，网页中保存的文件会直接写入目标服务器。

## 使用期间保持连接

保持 code-server、SSH 转发终端以及 VS Code 远程连接运行。

若访问异常，在跳板环境另一个终端执行：

```bash
curl -I http://127.0.0.1:18080/
```

返回 HTTP 响应（包括 302 登录跳转）说明 SSH 转发已通，再检查 VS Code 的端口转发。
