#!/bin/zsh
# 一键启动（V2）：模拟器 → GPS 卫星补丁 → 虚拟跑步 → 步频模拟 → 运动世界 → 自检
#
# 设计原则：每一行 ✓ 都是真的成立，不靠"日志里曾经成功过"这类可能过期的证据。
#   · 模拟器   ：get-state == device 且 sys.boot_completed == 1
#   · GPS 补丁 ：比对设备上 GNSS 二进制的 sha256（补丁是内存挂载，重启即失效，所以每次都验）
#   · 喂点脚本 ：pidfile 活着 + 该 pid 确实是 python + 脚本进程在 + 端口链路可用
#   · 应用     ：pidof 真的取到进程
# 已在跑的组件会自动跳过，不会重复拉起。
#
# 用法：双击运行；或 ./一键启动.command [速度m/s] [步频]
set -u
BASE_DIR="${0:A:h}"
EMU_DIR="$BASE_DIR/运行环境"
ADB="$EMU_DIR/sdk/platform-tools/adb"
LOGS="$EMU_DIR/logs"
SPEED="${1:-3.8}"
CADENCE="${2:-180}"
VR_PID=/tmp/dsh-virtualrun.pid
SS_PID=/tmp/dsh-stepsim.pid
mkdir -p "$LOGS"

say()  { printf '%s\n' "$*" }
step() { printf '\n== %s ==\n' "$*"; }

wait_for() {   # wait_for 次数 间隔秒 描述 命令
  local n=$1 s=$2 desc=$3; shift 3
  local i=1
  while (( i <= n )); do
    if eval "$*" >/dev/null 2>&1; then say "  ✓ $desc"; return 0; fi
    sleep "$s"
    (( i++ ))
  done
  say "  ✗ $desc（超时 ${n}×${s}s）"
  return 1
}

# 喂点脚本是否真的在跑：pidfile 有效 + pid 活着 + 壳进程在 + 日志近 3 分钟内更新过
# （不用 ps：沙箱/受限环境里 ps 可能被拒，会让判定假阴性；日志每 30 秒写一行，最可靠）
feeder_alive() {  # feeder_alive pidfile 脚本名关键字 日志文件
  local pidfile=$1 key=$2 log=$3 pid mt now
  [[ -f "$pidfile" ]] || return 1
  pid=$(cat "$pidfile" 2>/dev/null)
  [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null || return 1
  pgrep -f "$key" >/dev/null 2>&1 || return 1
  [[ -f "$log" ]] || return 1
  mt=$(stat -f %m "$log" 2>/dev/null || echo 0)
  now=$(date +%s)
  (( now - mt < 180 )) || return 1
  return 0
}

start_feeder() {  # start_feeder pidfile 脚本名关键字 日志 参数…
  local pidfile=$1 key=$2 log=$3; shift 3
  nohup "$BASE_DIR/$key" "$@" > "$LOGS/$log" 2>&1 < /dev/null &
  local i=1
  while (( i <= 15 )); do
    if feeder_alive "$pidfile" "$key" "$LOGS/$log"; then
      say "  ✓ 已启动（pid $(cat "$pidfile")）"
      return 0
    fi
    sleep 1
    (( i++ ))
  done
  say "  ✗ 启动失败，看日志：$LOGS/$log"
  return 1
}

FAIL=0

# ---------------------------------------------------------------- 1/6 模拟器
step "1/6 模拟器"
BOOTED=$("$ADB" -e shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')
if "$ADB" -e get-state >/dev/null 2>&1 && [[ "$BOOTED" == "1" ]]; then
  say "  ✓ 模拟器已在运行（已开机）"
elif "$ADB" -e get-state >/dev/null 2>&1; then
  say "  · 模拟器进程在，但还没开完机，等它…"
  wait_for 40 5 "开机完成（sys.boot_completed=1）" \
    "[ \"\$(\"$ADB\" -e shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')\" = 1 ]" || { say "  模拟器卡住了，看 $LOGS/emulator.log"; exit 1; }
else
  say "  启动中…（-gpu swangle，首次约 20~90 秒）"
  nohup "$BASE_DIR/启动安卓模拟器.command" > "$LOGS/模拟器-启动.log" 2>&1 < /dev/null &
  wait_for 60 5 "开机完成（sys.boot_completed=1）" \
    "[ \"\$(\"$ADB\" -e shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')\" = 1 ]" || { say "  模拟器没起来，看 $LOGS/emulator.log"; exit 1; }
fi

# ------------------------------------------------------------ 2/6 GPS 卫星补丁
step "2/6 GPS 卫星补丁"
if "$BASE_DIR/修复GPS卫星数.command" > "$LOGS/gps-fix.log" 2>&1; then
  say "  ✓ $(grep -a '补丁' "$LOGS/gps-fix.log" | tail -1 | sed 's/^GPS 卫星数//')"
else
  say "  ✗ 补丁失败：$(tail -2 "$LOGS/gps-fix.log" | tr '\n' ' ')"; (( FAIL++ ))
fi

# ------------------------------------------------------------- 3/6 虚拟跑步
step "3/6 虚拟跑步（${SPEED} m/s）"
if feeder_alive "$VR_PID" "虚拟跑步GPS.command" "$LOGS/虚拟跑步.log"; then
  say "  ✓ 已在运行（pid $(cat "$VR_PID")），跳过"
else
  start_feeder "$VR_PID" "虚拟跑步GPS.command" "虚拟跑步.log" "$SPEED" || (( FAIL++ ))
fi

# ------------------------------------------------------------- 4/6 步频模拟
step "4/6 步频模拟（基准 ${CADENCE}）"
if feeder_alive "$SS_PID" "步频模拟.command" "$LOGS/步频模拟.log"; then
  say "  ✓ 已在运行（pid $(cat "$SS_PID")），跳过"
else
  start_feeder "$SS_PID" "步频模拟.command" "步频模拟.log" "$CADENCE" || (( FAIL++ ))
fi

# --------------------------------------------------------------- 5/6 应用
step "5/6 运动世界"
PKG=com.zjwh.android_wh_physicalfitness
if [[ -n "$("$ADB" -e shell pidof $PKG 2>/dev/null | tr -d '\r')" ]]; then
  say "  ✓ 应用已在运行（pid $("$ADB" -e shell pidof $PKG | tr -d '\r')）"
else
  "$ADB" -e shell am start -n $PKG/.mvi.splash.SplashActivity >/dev/null 2>&1
  wait_for 15 2 "应用已启动" "[ -n \"\$(\"$ADB\" -e shell pidof $PKG 2>/dev/null | tr -d '\r')\" ]" || (( FAIL++ ))
fi

# --------------------------------------------------------------- 6/6 自检
step "6/6 自检"
sleep 2

# GPS 补丁：直接比 sha（脚本里退出码就是结论，这里再取一次给人看）
H=$("$ADB" -e shell "sha256sum /vendor/bin/hw/android.hardware.gnss@2.0-service.ranchu 2>/dev/null" | awk '{print $1}' | tr -d '\r')
if [[ "$H" == "31fa9cf6d7dee4493e7987db5278b77165d8ce6b1f4eef46ea8cc9afc603b522" ]]; then
  say "  ✓ GPS 补丁在生效（GNSS 二进制已替换）"
else
  say "  ✗ GPS 补丁未生效"; (( FAIL++ ))
fi

feeder_alive "$VR_PID" "虚拟跑步GPS.command" "$LOGS/虚拟跑步.log" && say "  ✓ 虚拟跑步运行中（pid $(cat "$VR_PID")）" || { say "  ✗ 虚拟跑步没在跑"; (( FAIL++ )); }
feeder_alive "$SS_PID" "步频模拟.command" "$LOGS/步频模拟.log"      && say "  ✓ 步频模拟运行中（pid $(cat "$SS_PID")）" || { say "  ✗ 步频模拟没在跑"; (( FAIL++ )); }

# 定位：只有真有应用申请时 GPS 才开着；没人申请时"关闭"是正常状态。
# dumpsys 里会有多条 Location[gps（不同请求/不同时刻），必须挑 et 最大的那条，
# 否则会把几分钟前、甚至卫星数 0 的旧点当成当前结果。刚开机时头几秒可能还没有点，所以重试 3 次。
newest_loc() {
  "$ADB" -e shell 'dumpsys location | grep -o "Location\[gps [0-9.,]*[^]]*"' 2>/dev/null | awk '
    { if (match($0, /et=\+[0-9]+m[0-9.]+s/)) {
        t = substr($0, RSTART+4, RLENGTH-5); split(t, a, "m"); v = a[1]*60 + a[2];
        if (v > best) { best = v; line = $0 } } }
    END { print line }'
}
loc_age() {  # $1=定位行；输出"客机 uptime - et"的秒数
  local et up
  et=$(printf '%s' "$1" | /usr/bin/sed -n 's/.*et=+\([0-9]*\)m\([0-9.]*\)s.*/\1 \2/p')
  up=$("$ADB" -e shell 'cut -d" " -f1 /proc/uptime' 2>/dev/null | tr -d '\r')
  [[ -z "$et" || -z "$up" ]] && { echo ""; return; }
  awk -v up="$up" -v et="$et" 'BEGIN{split(et,a," "); printf "%d", up-(a[1]*60+a[2])}'
}
LOC=""; AGE=""
for try in 1 2 3 4 5; do
  LOC=$(newest_loc)
  AGE=$(loc_age "$LOC")
  [[ -n "$AGE" ]] && (( AGE <= 120 )) && break
  sleep 4
done
REQ=$("$ADB" -e shell dumpsys location 2>/dev/null | grep -c "mStarted=true")   # GPS provider 真的在跑才算有人申请
if [[ -n "$AGE" ]] && (( AGE <= 120 )); then
  say "  ✓ 定位：$(printf '%s' "$LOC" | /usr/bin/sed -E 's/Location\[gps ([0-9.]+),([0-9.]+) .*vel=([0-9.]+).*satellites=([0-9]+).*/\1,\2 速度\3 星\4/')  （${AGE} 秒前的点）"
elif (( REQ > 0 )); then
  if [[ -n "$AGE" ]]; then
    say "  · 应用在申请定位，但最新点已是 ${AGE} 秒前（GNSS 刚起来时会这样，过几秒重跑自检即可）"
  else
    say "  · 应用在申请定位，但还没拿到第一个点（GNSS 刚起来时会这样，过几秒重跑自检即可）"
  fi
else
  say "  · 当前没人申请定位，GPS 关闭属正常（运动世界进跑步/地图页会自动打开）"
fi

# 空间切换 App 是否在两个空间都装了（切账号用）
MISS=""
for u in $("$ADB" -e shell pm list users 2>/dev/null | grep -oE 'UserInfo\{[0-9]+' | grep -oE '[0-9]+'); do
  "$ADB" -e shell "pm list packages --user $u" 2>/dev/null | grep -q com.dsh.space || MISS="$MISS $u"
done
if [[ -z "$MISS" ]]; then
  say "  ✓ 空间切换 App 在所有空间都已安装"
else
  say "  · 空间切换 App 在 user$MISS 里没装，可跑 ./安装空间切换.command 补上"
fi

# 网络：模拟器走 qemu slirp 转发，卡死时 ICMP/DNS 还通但 TCP 全超时，只能重启模拟器解决
TCPFILE=/tmp/dsh-boot-tcp.txt
NET_OK=0
for ntry in 1 2 3; do
  rm -f "$TCPFILE"
  ( "$ADB" -e shell 'nc -w 5 www.baidu.com 443 < /dev/null; echo rc=$?' > "$TCPFILE" 2>&1 ) &
  NPID=$!; NI=0
  while (( NI < 48 )); do
    kill -0 "$NPID" 2>/dev/null || break
    sleep 0.25
    (( NI++ ))
  done
  kill -9 "$NPID" 2>/dev/null
  grep -q "rc=0" "$TCPFILE" 2>/dev/null && { NET_OK=1; break }
  (( ntry < 3 )) && sleep 4
done
if (( NET_OK )); then
  say "  ✓ 网络正常（TCP 能连出去）"
else
  say "  · 网络不通（TCP 超时）→ 跑 ./修复网络.command 会自动重启修复"
fi

say ""
if (( FAIL == 0 )); then
  say "全部就绪。关闭一切：./全部关闭.command"
else
  say "有 $FAIL 项没起来，看上面 ✗ 那几行。"
  exit 1
fi
