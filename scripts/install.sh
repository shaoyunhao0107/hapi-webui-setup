#!/usr/bin/env bash
# HAPI 安装：hub 监听 0.0.0.0（局域网 + 公网 IP 都能访问，不走 relay）+ runner，可选开机自启。
# 用法: install.sh [--workspace DIR]... [--port 3006] [--public-url http://公网IP:3006] [--service]
set -euo pipefail

PORT=3006; SERVICE=0; WS=(); PUBURL=""
while [ $# -gt 0 ]; do
  case "$1" in
    --workspace) WS+=("$2"); shift 2;;
    --port) PORT="$2"; shift 2;;
    --service) SERVICE=1; shift;;
    --public-url) PUBURL="$2"; shift 2;;
    *) echo "未知参数: $1"; exit 1;;
  esac
done
if [ ${#WS[@]} -eq 0 ]; then
  if [ -d "$HOME/projectai" ]; then WS=("$HOME/projectai"); else WS=("$HOME"); fi
fi

say(){ printf '\n== %s\n' "$*"; }

say "检查 claude CLI 和登录状态"
command -v claude >/dev/null || { echo "找不到 claude，请先安装并登录 Claude Code"; exit 1; }
claude --version
if ! claude auth status 2>/dev/null | grep -q '"loggedIn": true'; then
  echo "claude 还没登录，请先在这台机器上运行 claude 完成登录，再重新执行本脚本"; exit 1
fi

say "安装 / 升级 HAPI（官方 npm 源）"
command -v npm >/dev/null || { echo "需要 Node/npm"; exit 1; }
npm install -g @twsxtd/hapi --registry=https://registry.npmjs.org >/dev/null
hapi --version
HAPI_BIN=$(command -v hapi); CLAUDE_BIN=$(command -v claude)
SVC_PATH="$(dirname "$HAPI_BIN"):$(dirname "$CLAUDE_BIN"):/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

WS_ARGS=(); for d in "${WS[@]}"; do WS_ARGS+=(--workspace-root "$d"); done
if [ -z "$PUBURL" ] && [ "$(uname)" = Linux ]; then   # mac 多在 NAT 后面，不自动探测
  PUBIP=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null || true)
  [[ "$PUBIP" =~ ^[0-9.]+$ ]] && PUBURL="http://$PUBIP:$PORT"
fi
[ -n "$PUBURL" ] && export HAPI_PUBLIC_URL="$PUBURL"
mkdir -p "$HOME/.hapi/logs"

if [ "$SERVICE" = 1 ]; then
  pkill -f "hapi hub" 2>/dev/null || true
  hapi runner stop >/dev/null 2>&1 || true
  if [ "$(uname)" = Darwin ]; then
    say "配置 launchd（登录后自动启动）"
    LA="$HOME/Library/LaunchAgents"; mkdir -p "$LA"
    mk_plist(){ # label args...
      local label=$1; shift
      { echo '<?xml version="1.0" encoding="UTF-8"?>'
        echo '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
        echo "<plist version=\"1.0\"><dict><key>Label</key><string>$label</string>"
        echo '<key>ProgramArguments</key><array>'
        for a in "$@"; do echo "<string>$a</string>"; done
        echo '</array><key>EnvironmentVariables</key><dict>'
        echo "<key>PATH</key><string>$SVC_PATH</string><key>HOME</key><string>$HOME</string>"
        echo "<key>HAPI_LISTEN_HOST</key><string>0.0.0.0</string><key>HAPI_LISTEN_PORT</key><string>$PORT</string>"
        [ -n "$PUBURL" ] && echo "<key>HAPI_PUBLIC_URL</key><string>$PUBURL</string>"
        echo '<key>HAPI_RUNNER_SUPERVISED</key><string>1</string></dict>'
        echo "<key>WorkingDirectory</key><string>$HOME</string>"
        echo '<key>RunAtLoad</key><true/><key>KeepAlive</key><true/>'
        echo "<key>StandardOutPath</key><string>$HOME/.hapi/logs/$label.log</string>"
        echo "<key>StandardErrorPath</key><string>$HOME/.hapi/logs/$label.log</string>"
        echo '</dict></plist>'; } > "$LA/$label.plist"
      launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
      launchctl bootstrap "gui/$(id -u)" "$LA/$label.plist"
    }
    mk_plist run.hapi.hub "$HAPI_BIN" hub --no-relay
    sleep 4
    mk_plist run.hapi.runner "$HAPI_BIN" runner start-sync "${WS_ARGS[@]}"
  else
    say "配置 systemd --user（开机自启需要 linger）"
    UD="$HOME/.config/systemd/user"; mkdir -p "$UD"
    cat > "$UD/hapi-hub.service" <<EOF
[Unit]
Description=HAPI hub
After=network-online.target
[Service]
Environment=PATH=$SVC_PATH
Environment=HAPI_LISTEN_HOST=0.0.0.0
Environment=HAPI_LISTEN_PORT=$PORT
Environment=HAPI_PUBLIC_URL=$PUBURL
ExecStart=$HAPI_BIN hub --no-relay
Restart=always
[Install]
WantedBy=default.target
EOF
    cat > "$UD/hapi-runner.service" <<EOF
[Unit]
Description=HAPI runner
After=hapi-hub.service
Requires=hapi-hub.service
[Service]
Environment=PATH=$SVC_PATH
Environment=HAPI_RUNNER_SUPERVISED=1
WorkingDirectory=$HOME
ExecStart=$HAPI_BIN runner start-sync ${WS_ARGS[*]}
Restart=always
[Install]
WantedBy=default.target
EOF
    loginctl enable-linger "$(id -un)" 2>/dev/null || echo "（enable-linger 失败：需要 sudo loginctl enable-linger $(id -un)，否则退出登录后服务会停）"
    systemctl --user daemon-reload
    systemctl --user enable --now hapi-hub.service; sleep 4
    systemctl --user enable --now hapi-runner.service
  fi
else
  say "启动 hub（0.0.0.0:${PORT}，--no-relay）"
  pkill -f "hapi hub" 2>/dev/null || true; sleep 1
  HAPI_LISTEN_HOST=0.0.0.0 HAPI_LISTEN_PORT=$PORT nohup hapi hub --no-relay > "$HOME/.hapi/logs/hub-manual.log" 2>&1 &
  sleep 6
  say "启动 runner（workspace: ${WS[*]}）"
  hapi runner stop >/dev/null 2>&1 || true
  hapi runner start "${WS_ARGS[@]}" | tail -1
fi

sleep 4
say "健康检查"
curl -fsS "http://127.0.0.1:$PORT/health" && echo
if [ "$(uname)" = Darwin ]; then IP=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || true)
else IP=$(hostname -I 2>/dev/null | awk '{print $1}'); fi
[ -n "${IP:-}" ] && curl -s -o /dev/null -w "局域网 http://$IP:$PORT -> %{http_code}\n" "http://$IP:$PORT/"
hapi runner status 2>&1 | grep -m1 -i "running" || echo "runner 状态异常，运行 hapi runner logs 查看"

say "完成"
echo "局域网: http://${IP:-<本机IP>}:${PORT}   （本机: http://localhost:${PORT}）"
if [ -n "$PUBURL" ]; then
  echo "公网:   ${PUBURL}"
  echo "  → 必须在云服务器安全组 / 防火墙放行 TCP ${PORT}（ufw: sudo ufw allow ${PORT}/tcp）"
  echo "  → 在服务器上访问自己的公网 IP 经常不通，要从外部设备打开测试"
  echo "  → HTTP 明文，token 和对话不加密；不要在不可信网络上登录"
fi
echo "Access Token: python3 -c \"import json;print(json.load(open('$HOME/.hapi/settings.json'))['cliApiToken'])\""
echo "建议接着跑: bash $(dirname "$0")/verify.sh --spawn"
