# Antigravity Proxy Launcher for macOS

> **免责与非官方声明**
> 本项目是一个**非官方（Unofficial）社区维护的 macOS 启动器小工具**，与 Google 或 Antigravity 官方团队无任何关联。
> 本仓库**仅包含纯文本 AppleScript 启动脚本与本地构建脚本**，**不包含**任何 Antigravity 客户端本体、第三方闭源程序、代理内核或网络服务。用户需自行安装正版 Antigravity 及所需的本地 HTTP 代理（如企业内网代理、本地抓包代理或自建代理服务）。

一个轻量级的 macOS 启动包装器，用于在不修改系统全局代理、也不修改 `/Applications/Antigravity.app` 原安装包的前提下，为单次启动的 Antigravity 进程注入标准代理环境变量与远程调试参数。

---

## 它解决了什么问题？

1. **进程级代理隔离**：仅向本次启动的 Antigravity 进程注入 `HTTP_PROXY` / `HTTPS_PROXY` / `NO_PROXY`（同时包含大小写变量），不修改 macOS 系统代理设置，也不影响其他应用。
2. **避免本地插件断连**：默认自动附加 `NO_PROXY=localhost,127.0.0.1,::1`，防止本机 Sidecar / MCP 插件流量被错误转发到代理。
3. **兼容本地 CDP 插件胶囊**：启动前自动清理陈旧的 `DevToolsActivePort` 文件，并传入 `--remote-debugging-port=0`，避免重启后依赖本地调试端口的扩展（例如用量监控胶囊）无法挂载。
4. **防误触重复打开**：如果 Antigravity 已在运行，弹窗询问是「仅切到前台」还是「优雅退出并重启应用配置」，避免 `open -a` 直接复用旧进程导致环境变量未生效。
5. **免改代码自定义端口**：检测不到默认端口时，可直接在弹窗中输入 `主机:端口` 保存到 `~/.config/antigravity-proxy-launcher/config.env`，或选择「不带代理启动」。

---

## 快速开始（推荐本地构建）

本地编译生成的 `.app` 直接由你自己的 macOS 编译并签名，**不会触发 Gatekeeper「无法验证开发者 / 已损坏」拦截**，且代码完全透明可审计：

```bash
git clone https://github.com/xzhe030203-art/antigravity-proxy-launcher-macos.git
cd antigravity-proxy-launcher-macos
chmod +x scripts/build.sh
./scripts/build.sh
```

构建完成后，生成的启动器位于：

```text
dist/Antigravity Proxy Launcher.app
```

你可以将它拖到 `/Applications`（应用程序）文件夹或 Dock 栏，以后双击即可启动。

> 如果你希望自定义生成的应用名称（例如中文名）：
> ```bash
> APP_NAME="Antigravity 代理启动.app" ./scripts/build.sh
> ```

---

## 配置说明

默认监听 `127.0.0.1:7890`。有两种方式修改配置：

### 方式一：弹窗交互修改（最简单）
首次启动如果未检测到默认端口，点击弹窗里的 **「修改代理地址」**，输入你的本地 HTTP 代理监听地址（例如 `127.0.0.1:8888`），会自动保存到配置文件。

### 方式二：手动编辑配置文件
复制示例配置：

```bash
mkdir -p ~/.config/antigravity-proxy-launcher
cp config.example.env ~/.config/antigravity-proxy-launcher/config.env
```

编辑 `~/.config/antigravity-proxy-launcher/config.env`：

```ini
PROXY_HOST=127.0.0.1
PROXY_PORT=7890
NO_PROXY=localhost,127.0.0.1,::1
APP_PATH=/Applications/Antigravity.app
ENABLE_REMOTE_DEBUG=1
```

---

## 替代方案（如果不想使用 `.app` 启动器）

如果你习惯使用终端，也可以不构建 `.app`，直接在 `~/.zshrc` 中添加一个 Shell 函数实现同样效果：

```zsh
antigravity-proxy() {
  local proxy_host="${1:-127.0.0.1}"
  local proxy_port="${2:-7890}"
  local proxy_url="http://${proxy_host}:${proxy_port}"

  if ! nc -z -w 2 "$proxy_host" "$proxy_port"; then
    echo "未检测到本地代理端口 ${proxy_host}:${proxy_port}" >&2
    return 1
  fi

  rm -f "$HOME/Library/Application Support/Antigravity/DevToolsActivePort"
  open -a "/Applications/Antigravity.app" \
    --env HTTP_PROXY="$proxy_url" \
    --env HTTPS_PROXY="$proxy_url" \
    --env NO_PROXY="localhost,127.0.0.1,::1" \
    --env http_proxy="$proxy_url" \
    --env https_proxy="$proxy_url" \
    --env no_proxy="localhost,127.0.0.1,::1" \
    --args --remote-debugging-port=0
}
```

保存后执行 `source ~/.zshrc`，以后在终端输入 `antigravity-proxy`（或 `antigravity-proxy 127.0.0.1 8888`）即可。

---

## 常见问题

- **为什么不建议直接分发预编译的 `.app`？**
  未经过 Apple 付费开发者公证的 `.app` 从网络下载后会被 macOS Gatekeeper 拦截。本地运行 `./scripts/build.sh` 只需 1 秒，更安全也更省心。
- **是否会修改 Antigravity 原始安装文件？**
  不会。本工具仅通过 macOS 原生 `/usr/bin/open` 启动应用，不触碰 `/Applications/Antigravity.app` 内的任何文件。

## License

[MIT](LICENSE)
