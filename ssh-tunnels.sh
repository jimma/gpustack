#!/usr/bin/env bash
#
# ssh-tunnels.sh — 整理自 ps -ef 输出中的 4 条 SSH 端口转发隧道
#
#   隧道1: 0.0.0.0:8080  -> (经 ubuntu@10.66.3.39 ) -> 127.0.0.1:8080
#   隧道2: 0.0.0.0:9080  -> (经 ubuntu@10.66.3.39 ) -> 127.0.0.1:8080
#   隧道3: 0.0.0.0:7080  -> (经 ubuntu@10.66.1.209) -> 127.0.0.1:9080
#   隧道4: 0.0.0.0:19001 -> (经 ubuntu@10.66.3.38 ) -> 127.0.0.1:9001
#
# 原始命令（供参考）:
#   ssh -fN -L 0.0.0.0:8080:127.0.0.1:8080  ubuntu@10.66.3.39
#   ssh -fN -L 0.0.0.0:9080:127.0.0.1:8080  ubuntu@10.66.3.39
#   ssh -fN -L 0.0.0.0:7080:127.0.0.1:9080  ubuntu@10.66.1.209
#   ssh -fN -L 0.0.0.0:19001:127.0.0.1:9001 ubuntu@10.66.3.38
#
# 用法:
#   ./ssh-tunnels.sh start     建立全部隧道（已在运行的自动跳过）
#   ./ssh-tunnels.sh stop      关闭全部隧道
#   ./ssh-tunnels.sh restart   重启全部隧道
#   ./ssh-tunnels.sh status    查看隧道运行状态
#
set -u

SSH_USER="ubuntu"
SSH_OPTS=(
    -fN
    -o ExitOnForwardFailure=yes
    -o ServerAliveInterval=30
    -o ServerAliveCountMax=3
)

# 格式: 本地端口|跳转主机|目标地址:目标端口
TUNNELS=(
    "8080|10.66.3.39|127.0.0.1:8080"
    "9080|10.66.3.39|127.0.0.1:8080"
    "7080|10.66.1.209|127.0.0.1:9080"
    "19001|10.66.3.38|127.0.0.1:9001"
)

pattern_of() {  # <本地端口> <跳转主机> <目标>
    echo "ssh .*-L 0\.0\.0\.0:$1:$3.*${SSH_USER}@$2"
}

pid_of() {
    pgrep -f "$(pattern_of "$1" "$2" "$3")" 2>/dev/null
}

start_tunnel() {  # <本地端口> <跳转主机> <目标>
    local lp="$1" jump="$2" target="$3"
    if pid_of "$lp" "$jump" "$target" >/dev/null; then
        echo "[跳过] $lp -> $target (经 $jump) 已在运行, PID: $(pid_of "$lp" "$jump" "$target")"
    elif ssh "${SSH_OPTS[@]}" -L "0.0.0.0:${lp}:${target}" "${SSH_USER}@${jump}"; then
        echo "[成功] 0.0.0.0:$lp -> $target (经 $jump)"
    else
        echo "[失败] 0.0.0.0:$lp -> $target (经 $jump)" >&2
    fi
}

stop_tunnel() {
    local lp="$1" jump="$2" target="$3"
    local pids
    pids=$(pid_of "$lp" "$jump" "$target")
    if [ -n "$pids" ]; then
        kill $pids && echo "[停止] $lp (经 $jump), PID: $pids"
    else
        echo "[跳过] $lp (经 $jump) 未在运行"
    fi
}

status_tunnel() {
    local lp="$1" jump="$2" target="$3"
    local pids
    pids=$(pid_of "$lp" "$jump" "$target")
    if [ -n "$pids" ]; then
        echo "[运行中] 0.0.0.0:$lp -> $target (经 $jump), PID: $pids"
    else
        echo "[已停止] 0.0.0.0:$lp -> $target (经 $jump)"
    fi
}

main() {
    local action="${1:-start}"
    case "$action" in
        start|stop|status) ;;
        restart) main stop; sleep 1; main start; return ;;
        *) echo "用法: $0 {start|stop|restart|status}"; exit 1 ;;
    esac

    local t lp jump target
    for t in "${TUNNELS[@]}"; do
        IFS='|' read -r lp jump target <<< "$t"
        "${action}_tunnel" "$lp" "$jump" "$target"
    done
}

main "$@"
