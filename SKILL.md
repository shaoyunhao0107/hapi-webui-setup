---
name: hapi-webui-setup
description: 在任意机器（macOS / Linux / Windows 服务器）上安装 HAPI（tiann/hapi），把本机官方 claude CLI 包成一个 0.0.0.0 可访问的 Web UI，复用本机已登录的 Claude Code，不重新登录。包含一键安装脚本（hub 监听 0.0.0.0 + runner + 可选开机自启）、实测验证脚本（网页新建会话真跑 Bash/Write/Read）、token 获取、权限模式选择、终端与网页交接、防封号要点和踩坑。触发词：HAPI、hapi、hapi claude、Claude Code 网页版、Claude 网页 UI、手机远程用 Claude Code、0.0.0.0 访问 Claude、给服务器装 Claude webui。
---

# HAPI：本机 Claude CLI 的 Web UI

目标：在目标机器上让浏览器（手机、其他电脑）通过 `http://<机器IP>:3006` 使用这台机器上的**官方 claude CLI**，复用它已有的登录，出口就是这台机器。

> 2026-11-08 在 macOS 26.7.1（Intel，claude 2.1.319，HAPI v0.34.4）上全流程实测通过。

## 为什么选 HAPI（结论，不用每次重新评估）

- 它是包装官方 `claude` 的程序，不自己请求 Anthropic：远程模式下源码 `cli/src/claude/claudeRemote.ts` 用 `pathToClaudeCodeExecutable: getDefaultClaudeCodePath()` 启动本机 claude。
- 登录、`~/.claude` 配置、skills、MCP、MEMORY.md、会话记录（`~/.claude/projects/`）全部照常生效，**不需要重新登录**。
- 仓库活跃（5k+ star），AGPL-3.0，网页版 / PWA 免费，原生 App 收费（不需要）。

## 安装（macOS / Linux）

前提：目标机器上 `claude --version` 能跑，`claude auth status` 显示 `loggedIn: true`；有 Node/npm。

```bash
bash scripts/install.sh                                  # 默认 workspace=~/projectai（不存在就用 $HOME）
bash scripts/install.sh --workspace ~/proj --workspace ~/work --port 3006
bash scripts/install.sh --service                        # 另外配开机自启（mac 用 launchd，linux 用 systemd --user）
```

脚本做的事：
1. 用官方源安装 `npm i -g @twsxtd/hapi --registry=https://registry.npmjs.org`（镜像源可能缺平台包）
2. 以 `HAPI_LISTEN_HOST=0.0.0.0` 启动 `hapi hub --no-relay`（这个值会自动写进 `~/.hapi/settings.json` 的 `listenHost`，之后一直有效）
3. 启动 `hapi runner start --workspace-root <dir>`（网页新建会话靠它；只能浏览、新建这些目录）
4. 检查 `/health`、局域网 IP 能否访问，最后打印访问地址

远程服务器用法：`ssh user@host 'git clone https://github.com/shaoyunhao0107/hapi-webui-setup.git /tmp/hapi-webui-setup && bash /tmp/hapi-webui-setup/scripts/install.sh --service'`。

## Windows

- `npm i -g @twsxtd/hapi --registry=https://registry.npmjs.org`
- 网页终端功能依赖 Bun ConPTY，要求 **Bun ≥ 1.3.14**
- 经常找不到 claude 时要设 `HAPI_CLAUDE_PATH`（指向 `claude.exe`，来自 CSDN 踩坑记录）
- 设 `$env:HAPI_LISTEN_HOST="0.0.0.0"`，再运行 `hapi hub --no-relay`，另开一个窗口运行 `hapi runner start --workspace-root I:\xxx`
- 记得在防火墙放行 3006 端口（未实测）

## 验证（装完必跑）

```bash
bash scripts/verify.sh            # 只做健康检查和接口登录
bash scripts/verify.sh --spawn    # 另外从网页 API 新建一个会话，让它真跑 Bash/Write/Read，然后归档
```

`--spawn` 通过的标准：测试文件被写出来，`~/.claude/projects/` 里能找到对应的会话记录。

## 登录网页

- 地址：`http://<机器局域网IP>:3006`（本机打开 `http://localhost:3006`）
- Access Token：`python3 -c "import json;print(json.load(open('$HOME/.hapi/settings.json'))['cliApiToken'])"`
- token 能完全控制这台机器，**不要发给别人、不要贴群里**。泄露后删掉 settings.json 里的 `cliApiToken`，重启 hub 会生成新的。

## 使用方式（已实测的结论）

| 方式 | 运行形态 | 原版界面 | 网页能看到 |
|---|---|---|---|
| 终端 `cd 项目 && hapi claude` | 原版界面 | ✅ | ✅（标记 `sentFrom: cli`；要点进会话才看得到） |
| 网页新建会话 | runner 用 SDK 方式启动本机 claude（`--output-format stream-json`，相当于 `claude -p`） | ❌ | ✅ |

- **网页新建的会话能正常干活**：Bash、Write、Read、skills、MCP、记忆都实测可用，不是只能聊天。
- **Claude 没有 PTY 模式**：spawn 接口的 `startingMode: pty` 对 Claude 无效（`cli/src/claude/loop.ts` 没接 runPty）。不要再推荐这个选项。
- **交接**：终端会话收到网页发来的消息后，会切到远程模式，终端显示 HAPI 的简化界面；在终端**连按两下空格**切回原版界面，上下文不丢。同一时间只有一边在控制。
- 一定要在网页上用原版界面：会话页的 Terminal 标签里运行 `tmux new -A -s cc 'cd ~/projectai && hapi claude'`（未实测）。

## 权限模式（网页上的 Permission Mode）

| 模式 | 含义 |
|---|---|
| `default` | 有风险的操作都要在网页上点同意 |
| `acceptEdits` | 改文件自动同意，跑命令要问，**网页干活推荐用这个** |
| `auto` | 由分类器判断，安全的自动放行 |
| `plan` | 只出方案不动手 |
| `bypassPermissions` / **YOLO** | 全部放行，等于 `--dangerously-skip-permissions`，人不在电脑前时别开 |

在终端用 `hapi claude` 启动时，会沿用本机 Claude Code 默认的权限模式（如果本机默认是 bypassPermissions，网页上看到的也是），需要的话在网页上改。

## 防封号要点

- 出口、程序、登录和直接用 CLI 完全一样，网页模式就是官方的无界面 `-p` 用法，额度照常从订阅里扣。这是第三方工具里风险最低的一类，但没法打包票。
- 不要：把网页或 token 给别人用（等于共享账号）、24 小时不停地大批量自动跑、换成那种直接拿登录凭证去请求 API 的工具。
- 只用 `--no-relay` 加局域网访问；0.0.0.0 没有 HTTPS，**不要做公网端口映射**。要从外网访问，用 Tailscale 或 HAPI 自带的 `--relay`（端到端加密）。

## API 速查（脚本和排障用）

```bash
TOK=$(python3 -c "import json;print(json.load(open('$HOME/.hapi/settings.json'))['cliApiToken'])")
JWT=$(curl -s -X POST localhost:3006/api/auth -H 'content-type: application/json' -d "{\"accessToken\":\"$TOK\"}" | python3 -c "import sys,json;print(json.load(sys.stdin)['token'])")   # JWT 4 小时有效
curl -s localhost:3006/api/machines -H "Authorization: Bearer $JWT"
curl -s localhost:3006/api/sessions -H "Authorization: Bearer $JWT"
# 新建会话：POST /api/machines/<mid>/spawn {"directory","agent":"claude","startingMode":"remote","permissionMode"}
# 发消息：POST /api/sessions/<sid>/messages {"text","localId"}
# 停止 / 归档：POST /api/sessions/<sid>/abort | /archive  body {}
```

- `/api/sessions/<sid>/messages` 返回的内容结构比较乱，要看 Claude 实际做了什么，直接读 `~/.claude/projects/<目录>/<agentSessionId>.jsonl`（会话元数据里有 agentSessionId，也可以用 `grep -l` 按消息内容找）。
- 诊断：`hapi doctor`；清理残留进程：`hapi doctor clean`；runner：`hapi runner status|logs|stop`。

## 踩坑

- 用 nohup 拉起来的 hub 重启电脑后就没了，要长期用就加 `--service`。
- 改了 listenHost 或升级之后要重启 hub（`pkill -f "hapi hub"` 再启动），runner 会自己重连。
- 从网页新建的会话会一直挂着一个后台 claude 进程，用完在网页上归档。
- 升级后版本号没变：先 `npm rm -g @twsxtd/hapi` 再从官方源重新装，然后检查 PATH 里有没有更早的 hapi。
