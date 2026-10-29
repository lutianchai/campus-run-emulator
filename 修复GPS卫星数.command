#!/bin/zsh
# 修复 GPS 卫星数
#
# 原因：模拟器自带的 GNSS HAL 只解析 $GPGGA / $GPRMC，从来不上报卫星状态，
# 所以系统里卫星数一直是 0，运动世界校园就会显示“信号差 / GPS信号弱 无法开始”。
# 这里把打过补丁的 HAL（固定上报 12 颗卫星）bind mount 覆盖进去，并重启 GNSS 服务。
#
# 补丁是内存挂载，模拟器重启就失效，所以启动脚本会自动调用本脚本。
set -eu
BASE_DIR="${0:A:h}"
EMU_DIR="$BASE_DIR/运行环境"
ADB="$EMU_DIR/sdk/platform-tools/adb"
SRC="$BASE_DIR/gnss/gnss-12sv"
DST=/vendor/bin/hw/android.hardware.gnss@2.0-service.ranchu
PATCHED=31fa9cf6d7dee4493e7987db5278b77165d8ce6b1f4eef46ea8cc9afc603b522

if [[ ! -f "$SRC" ]]; then
  echo "缺少补丁文件：$SRC"
  exit 1
fi

# 加锁：启动脚本会在后台也调一次本脚本，两个同时跑会抢 remount
LOCK=/tmp/dsh-gpsfix.lock
for i in {1..120}; do
  mkdir "$LOCK" 2>/dev/null && break
  echo "另一个 GPS 补丁进程在跑，等它结束…"
  sleep 1
done
trap 'rmdir "$LOCK" 2>/dev/null' EXIT INT TERM

echo "等待模拟器启动…"
"$ADB" wait-for-device
for i in {1..60}; do
  if [[ "$("$ADB" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == "1" ]]; then
    break
  fi
  sleep 2
done

"$ADB" root >/dev/null 2>&1 || true
sleep 2
"$ADB" wait-for-device

H=$("$ADB" shell "sha256sum $DST 2>/dev/null" | awk '{print $1}' | tr -d '\r')
if [[ "$H" == "$PATCHED" ]]; then
  echo "GPS 卫星数补丁已经在生效，跳过。"
  exit 0
fi

echo "挂载 GNSS 补丁…"
"$ADB" push "$SRC" /data/local/tmp/gnss-12sv >/dev/null
"$ADB" shell "chmod 755 /data/local/tmp/gnss-12sv"
"$ADB" shell "chcon u:object_r:hal_gnss_default_exec:s0 /data/local/tmp/gnss-12sv"
"$ADB" shell "mount --bind /data/local/tmp/gnss-12sv $DST"
"$ADB" shell "mount -o remount,bind,suid $DST" || true
"$ADB" shell "setprop ctl.restart vendor.gnss-2-0"

sleep 6
H2=$("$ADB" shell "sha256sum $DST 2>/dev/null" | awk '{print $1}' | tr -d '\r')
if [[ "$H2" == "$PATCHED" ]]; then
  echo "GPS 卫星数补丁已生效（上报 12 颗卫星）。"
else
  echo "补丁没挂上，请手动执行本脚本重试。"
  exit 1
fi
