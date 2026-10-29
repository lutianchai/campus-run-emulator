#!/bin/zsh
# 修复网络
#
# 症状：模拟器"看起来有网"——ICMP 能通、域名能解析，但网页/App 全部连不上（TCP 超时）。
# 原因：模拟器的网络是 qemu 的 slirp 用户态转发，长时间运行后这块会卡死（宿主网络本身没问题）。
#       这和"DNS 假死"是同一类毛病的不同表现，改 DNS 配置没用，只能把模拟器进程重启。
#
# 本脚本：先探测（DNS + TCP 两项），坏了就 全部关闭 → 一键启动 → 再复测。
# 用法：./修复网络.command          探测，坏了才修
#       ./修复网络.command --force  不管好坏都重启一次
set -u
BASE_DIR="${0:A:h}"
EMU_DIR="$BASE_DIR/运行环境"
ADB="$EMU_DIR/sdk/platform-tools/adb"
FORCE=0
[[ "${1:-}" == "--force" ]] && FORCE=1

say()  { printf '%s\n' "$*"; }
step() { printf '\n== %s ==\n' "$*"; }

# macOS 没有 timeout，自己实现：跑一条命令，最多等 N 秒
run_with_timeout() {  # run_with_timeout 秒数 输出文件 命令…
  local t=$1 out=$2; shift 2
  ( "$@" > "$out" 2>&1 ) &
  local pid=$! i=0
  while (( i < t * 4 )); do
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.25
    (( i++ ))
  done
  kill -9 "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
  return 0
}

net_probe() {  # 结果写进全局 DNS_OK / TCP_OK
  DNS_OK=0; TCP_OK=0
  run_with_timeout 20 /tmp/dsh-net-dns.txt \
    "$ADB" -e shell 'ping -c 1 -W 2 www.baidu.com 2>/dev/null | grep -m1 PING'
  grep -q "PING" /tmp/dsh-net-dns.txt 2>/dev/null && DNS_OK=1

  run_with_timeout 25 /tmp/dsh-net-tcp.txt \
    "$ADB" -e shell 'nc -w 6 www.baidu.com 443 < /dev/null; echo rc=$?'
  grep -q "rc=0" /tmp/dsh-net-tcp.txt 2>/dev/null && TCP_OK=1
}

report_probe() {
  if (( DNS_OK )); then
    say "  ✓ DNS 能解析（$(head -1 /tmp/dsh-net-dns.txt | tr -d '\r' | cut -c1-46)）"
  else
    say "  ✗ DNS 解析失败"
  fi
  if (( TCP_OK )); then
    say "  ✓ TCP 能连出去（www.baidu.com:443）"
  else
    say "  ✗ TCP 连不出去（超时）"
  fi
}

step "1/3 探测"
if ! "$ADB" -e get-state >/dev/null 2>&1; then
  say "  模拟器没在运行 —— 直接启动它"
  "$BASE_DIR/一键启动.command" | tail -20
  exit $?
fi
net_probe
report_probe

if (( DNS_OK && TCP_OK && ! FORCE )); then
  say ""
  say "网络是好的，不用修。（要强制重启一遍加 --force）"
  exit 0
fi

step "2/3 重启模拟器（slirp 转发卡死只能重启解决）"
say "  关闭…"
"$BASE_DIR/全部关闭.command" > /tmp/dsh-net-repair.log 2>&1
tail -2 /tmp/dsh-net-repair.log | sed 's/^/  /'
say "  冷启动…"
"$BASE_DIR/一键启动.command" >> /tmp/dsh-net-repair.log 2>&1
grep -E "^  [·✓✗]|^== " /tmp/dsh-net-repair.log | tail -12 | sed 's/^/  /'

step "3/3 复测"
sleep 5
net_probe
report_probe

say ""
if (( DNS_OK && TCP_OK )); then
  say "网络已恢复。"
else
  say "重启后还是不通。下一步建议："
  say "  1) 确认宿主机自己能上网：nc -w 4 www.baidu.com 443 </dev/null"
  say "  2) 若宿主机挂了 VPN/代理，qemu 的 slirp 常会跟着坏；关掉代理再 ./修复网络.command"
  say "  3) 也可以换 DNS 启动：修改 启动安卓模拟器.command，在 emulator 参数里加 -dns-server 223.5.5.5"
  exit 1
fi
