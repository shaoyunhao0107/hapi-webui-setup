#!/usr/bin/env bash
# HAPI 验证：健康检查 + 接口登录 + 机器 / agent 是否可用；加 --spawn 时从网页 API 新建会话真跑工具。
set -euo pipefail
PORT=${HAPI_LISTEN_PORT:-3006}; B="http://127.0.0.1:$PORT"; SPAWN=0
[ "${1:-}" = "--spawn" ] && SPAWN=1

echo "health: $(curl -fsS $B/health)"
grep -o '"listenHost": *"[^"]*"' "$HOME/.hapi/settings.json" || echo "listenHost 没设置（默认 127.0.0.1，局域网访问不了）"
TOK=$(python3 -c "import json;print(json.load(open('$HOME/.hapi/settings.json'))['cliApiToken'])")
JWT=$(curl -s -X POST $B/api/auth -H 'content-type: application/json' -d "{\"accessToken\":\"$TOK\"}" | python3 -c "import sys,json;print(json.load(sys.stdin)['token'])")
H="Authorization: Bearer $JWT"
MID=$(curl -s $B/api/machines -H "$H" | python3 -c "
import sys,json
ms=json.load(sys.stdin)['machines']
if not ms: sys.exit('没有在线机器：runner 没在跑？')
print(ms[0]['id'])")
echo "machine: $MID"
curl -s $B/api/machines/$MID/agent-availability -H "$H" | python3 -c "
import sys,json
a={x['agent']:x['available'] for x in json.load(sys.stdin)['agents']}
print('claude 可用' if a.get('claude') else '!! claude 不可用（runner 的 PATH 里找不到 claude）')"

[ "$SPAWN" = 1 ] || exit 0

T=$(mktemp -d)/hapi_test.txt
DIR=$(curl -s -X POST $B/api/machines/$MID/paths/exists -H "$H" -H 'content-type: application/json' -d "{\"paths\":[\"$HOME/projectai\"]}" | python3 -c "import sys,json,os;d=json.load(sys.stdin);print(os.path.expanduser('~/projectai') if d['exists'].get(os.path.expanduser('~/projectai')) and not d.get('outsideWorkspaceRoots') else os.path.expanduser('~'))")
S=$(curl -s -X POST $B/api/machines/$MID/spawn -H "$H" -H 'content-type: application/json' \
  -d "{\"directory\":\"$DIR\",\"agent\":\"claude\",\"startingMode\":\"remote\",\"permissionMode\":\"bypassPermissions\"}" \
  | python3 -c "import sys,json;r=json.load(sys.stdin);print(r.get('sessionId') or sys.exit(str(r)))")
echo "spawned session $S (dir $DIR)"
curl -s -X POST $B/api/sessions/$S/messages -H "$H" -H 'content-type: application/json' \
  -d "{\"localId\":\"verify1\",\"text\":\"HAPI 功能测试：用 Bash 运行 uname -a；用 Write 在 $T 写入 hello-from-hapi；再用 Read 读回。只做这些，用一句中文汇报结果。\"}" >/dev/null
for i in $(seq 1 36); do [ -f "$T" ] && break; sleep 5; done
sleep 8
if [ -f "$T" ]; then echo "✅ 网页会话已真实执行工具，文件内容: $(cat "$T")"; else echo "❌ 3 分钟内没看到测试文件，运行 hapi runner logs 排查"; fi
F=$(grep -l "HAPI 功能测试" "$HOME"/.claude/projects/*/*.jsonl 2>/dev/null | xargs ls -t 2>/dev/null | head -1 || true)
[ -n "$F" ] && python3 -c "
import json,sys
for l in open(sys.argv[1]):
  x=json.loads(l)
  if x.get('type')!='assistant': continue
  print('  model', x['message'].get('model'), '| claude', x.get('version')); break" "$F"
curl -s -X POST $B/api/sessions/$S/abort -H "$H" -H 'content-type: application/json' -d '{}' >/dev/null || true
curl -s -X POST $B/api/sessions/$S/archive -H "$H" -H 'content-type: application/json' -d '{}' >/dev/null && echo "测试会话已归档"
rm -rf "$(dirname "$T")"
