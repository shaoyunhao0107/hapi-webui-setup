# hapi-webui-setup

把机器上已登录的官方 **Claude Code CLI** 包成一个 `0.0.0.0:3006` 可访问的 Web UI（局域网或公网 IP 都行，基于 [tiann/hapi](https://github.com/tiann/hapi)），**复用本机登录，不重新登录**，出口就是这台机器。

## 快速开始（macOS / Linux）

前提：`claude` 已安装并登录（`claude auth status` 显示 `loggedIn: true`），有 Node/npm。

```bash
git clone https://github.com/shaoyunhao0107/hapi-webui-setup.git
cd hapi-webui-setup
bash scripts/install.sh --service          # 安装 + hub 监听 0.0.0.0 + runner + 开机自启（Linux 自动探测公网 IP）
bash scripts/verify.sh --spawn             # 实测：网页会话真跑 Bash/Write/Read
```

参数：`--workspace DIR`（可重复，网页上能用的目录，默认 ~/projectai 或 $HOME）、`--port 3006`、`--service`（mac 用 launchd，linux 用 systemd --user）。

远程服务器：
```bash
ssh user@host 'git clone https://github.com/shaoyunhao0107/hapi-webui-setup.git /tmp/hapi-webui-setup && bash /tmp/hapi-webui-setup/scripts/install.sh --service && bash /tmp/hapi-webui-setup/scripts/verify.sh --spawn'
```

打开 `http://<局域网IP或公网IP>:3006`，Access Token 用这条命令查：
```bash
python3 -c "import json;print(json.load(open('$HOME/.hapi/settings.json'))['cliApiToken'])"
```

## 作为 Claude Code skill 使用

```bash
ln -sfn "$PWD" ~/.claude/skills/hapi-webui-setup
```

详细说明（权限模式、终端/网页交接、防封号要点、API 速查、踩坑）见 [SKILL.md](SKILL.md)。

## 访问与安全

监听 0.0.0.0，**局域网和公网 IP 都能访问**。有公网 IP 的服务器：在云安全组和系统防火墙放行 TCP 3006，然后从外部设备打开 `http://公网IP:3006`；也可以用 `--public-url http://公网IP:3006` 手动指定（Linux 上不指定会自动探测）。

只靠 token 验证（43 位随机串），拿到 token 的人就能完全控制这台机器。走的是 HTTP 明文，不要在不可信网络上登录；有域名的话可以用 Caddy 反向代理加上 HTTPS（见 SKILL.md）。
