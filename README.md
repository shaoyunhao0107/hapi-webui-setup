# hapi-webui-setup

把机器上已登录的官方 **Claude Code CLI** 包成一个局域网 `0.0.0.0:3006` 可访问的 Web UI（基于 [tiann/hapi](https://github.com/tiann/hapi)），**复用本机登录，不重新登录**，出口就是这台机器。

## 快速开始（macOS / Linux）

前提：`claude` 已安装并登录（`claude auth status` 显示 `loggedIn: true`），有 Node/npm。

```bash
git clone https://github.com/shaoyunhao0107/hapi-webui-setup.git
cd hapi-webui-setup
bash scripts/install.sh --service          # 安装 + hub 监听 0.0.0.0 + runner + 开机自启
bash scripts/verify.sh --spawn             # 实测：网页会话真跑 Bash/Write/Read
```

参数：`--workspace DIR`（可重复，网页上能用的目录，默认 ~/projectai 或 $HOME）、`--port 3006`、`--service`（mac 用 launchd，linux 用 systemd --user）。

远程服务器：
```bash
scp -r hapi-webui-setup user@host:/tmp/
ssh user@host 'bash /tmp/hapi-webui-setup/scripts/install.sh --service && bash /tmp/hapi-webui-setup/scripts/verify.sh --spawn'
```

打开 `http://<机器IP>:3006`，Access Token 用这条命令查：
```bash
python3 -c "import json;print(json.load(open('$HOME/.hapi/settings.json'))['cliApiToken'])"
```

## 作为 Claude Code skill 使用

```bash
ln -sfn "$PWD" ~/.claude/skills/hapi-webui
```

详细说明（权限模式、终端/网页交接、防封号要点、API 速查、踩坑）见 [SKILL.md](SKILL.md)。

## 安全

0.0.0.0 没有 HTTPS，拿到 token 的人就能完全控制这台机器。只在可信局域网用，不要做公网端口映射；要从外网访问，用 Tailscale 或 HAPI 自带的 `--relay`。
