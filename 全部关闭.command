#!/bin/zsh
# 全部关闭：停喂点脚本 → 关模拟器 → 清 pid/锁/残留，最后逐项校验
#
# 设计原则：每个进程都在"确认它确实是我们的进程"之后才 kill，避免误杀
# （pidfile 里的 pid 可能已被系统回收给别的进程）。
# 幂等：本来就没在跑也返回成功。
set -u
BASE_DIR="${0:A:h}"
EMU_DIR="$BASE_DIR/运行环境"
ADB="$EMU_DIR/sdk/platform-tools/adb"
AVD=Campus_Test_ARM64
VR_PID=/tmp/dsh-virtualrun.pid
SS_PID=/tmp/dsh-stepsim.pid
GPS_LOCK=/tmp/dsh-gpsfix.lock

say()  { printf '%s\n' "$*"; }
step() { printf '\n== %s ==\n' "$*"; }
FAIL=0

# 停一个喂点脚本：pidfile 里的 pid 确认是 python 才 kill，再连壳进程一起收
stop_feeder() {  # stop_feeder pidfile 脚本名关键字 名称
  local pidfile=$1 key=$2 name=$3 pid cmd
  if [[ -f "$pidfile" ]]; then
    pid=$(cat "$pidfile" 2>/dev/null)
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      # 确认这个 pid 确实是我们喂点脚本的 python 子进程（不用 ps，受限环境里 ps 会被拒）
      if pgrep -f "emulator_console_auth_token" 2>/dev/null | grep -qx "$pid"; then
        kill -TERM "$pid" 2>/dev/null
        for i in {1..20}; do kill -0 "$pid" 2>/dev/null || break; sleep 0.1; done
        kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null
        say "  ✓ $name 已停止（pid $pid）"
      else
        say "  · $name 的 pidfile 指向别的进程（pid $pid 已不是喂点进程），只清 pidfile"
      fi
    else
      say "  · $name 本来就没在跑（清掉旧 pidfile）"
    fi
    rm -f "$pidfile"
  else
    say "  · $name 没有 pidfile（本来就没在跑）"
  fi
  # 兜底：把壳进程和 python 子进程都收干净
  pkill -f "$key" >/dev/null 2>&1
}

step "1/4 喂点脚本"
stop_feeder "$VR_PID" "虚拟跑步GPS.command" "虚拟跑步"
stop_feeder "$SS_PID" "步频模拟.command" "步频模拟"
# 两个脚本的 python 子进程 argv 里都带控制台令牌路径；正常情况下上面已经收掉，这里只是保险
pkill -f "emulator_console_auth_token" >/dev/null 2>&1
sleep 1
LEFT=$(pgrep -f "虚拟跑步GPS.command|步频模拟.command" | wc -l | tr -d ' ')
if [[ "$LEFT" == "0" ]]; then say "  ✓ 没有喂点脚本残留"; else say "  ✗ 还有 $LEFT 个喂点进程"; (( FAIL++ )); fi

step "2/4 模拟器"
if "$ADB" -e get-state >/dev/null 2>&1; then
  "$ADB" -e emu kill >/dev/null 2>&1
  say "  已发送关机指令"
fi
for i in {1..20}; do
  pgrep -f "qemu-system-aarch64.*$AVD" >/dev/null 2>&1 || break
  sleep 1
done
if pgrep -f "qemu-system-aarch64.*$AVD" >/dev/null 2>&1; then
  say "  模拟器没在 20 秒内退出，强制结束"
  pkill -f "qemu-system-aarch64.*$AVD" >/dev/null 2>&1
  sleep 3
fi
if pgrep -f "qemu-system-aarch64.*$AVD" >/dev/null 2>&1; then
  say "  ✗ 模拟器还在跑"; (( FAIL++ ))
else
  say "  ✓ 模拟器已退出"
fi

step "3/4 收尾"
rm -f "$GPS_LOCK"; rmdir "$GPS_LOCK" 2>/dev/null
rm -f "$VR_PID" "$SS_PID"
"$ADB" kill-server >/dev/null 2>&1
say "  ✓ 已清理 pidfile / 补丁锁 / adb 服务"

step "4/4 校验"
pgrep -fl "qemu-system-aarch64" 2>/dev/null | head -3
"$ADB" devices 2>/dev/null | tail -n +2 | /usr/bin/grep -q "device$" && { say "  ✗ 还能看到设备"; (( FAIL++ )); } || say "  ✓ 没有在线设备"

say ""
if (( FAIL == 0 )); then
  say "已全部关闭。下次 ./一键启动.command 一条命令就全起来。"
else
  say "有 $FAIL 项没收干净，见上面 ✗。"
  exit 1
fi
