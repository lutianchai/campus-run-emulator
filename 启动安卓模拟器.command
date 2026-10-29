#!/bin/zsh
# 只启动安卓模拟器（不含喂点脚本）。日常用「一键启动.command」即可。
# 已开机会直接返回；启动后会等设备上线，并在后台自动打 GPS 卫星补丁。
set -u
BASE_DIR="${0:A:h}"
EMU_DIR="$BASE_DIR/运行环境"
ADB="$EMU_DIR/sdk/platform-tools/adb"
if [[ ! -d "$EMU_DIR/sdk" ]]; then
  echo "缺少本项目 SDK，请先运行 ./安装环境.command"
  exit 1
fi
export ANDROID_HOME="$EMU_DIR/sdk"
export ANDROID_USER_HOME="$EMU_DIR/user"
export ANDROID_EMULATOR_HOME="$EMU_DIR/user"
export ANDROID_AVD_HOME="$EMU_DIR/avd"
mkdir -p "$EMU_DIR/logs"

# 判断"我们这个 AVD"是否已经在跑：get-state 是 device，且控制台回报的 AVD 名对得上
# （adb 的输出是 CRLF，必须去掉 \r，否则永远匹配不上，会重复拉起第二个实例）
is_running() {
  "$ADB" -e get-state 2>/dev/null | tr -d '\r' | /usr/bin/grep -qx 'device' || return 1
  "$ADB" -e emu avd name 2>/dev/null | tr -d '\r' | /usr/bin/grep -qx 'Campus_Test_ARM64' || return 1
  return 0
}

if is_running; then
  echo "模拟器已经在运行（Campus_Test_ARM64），无需重复启动。"
  exit 0
fi

nohup "$ANDROID_HOME/emulator/emulator" -avd Campus_Test_ARM64 -no-snapshot -no-boot-anim \
  -writable-system -memory 3072 -cores 4 -gpu swangle \
  > "$EMU_DIR/logs/emulator.log" 2>&1 < /dev/null &
EMU_PID=$!
echo '安卓模拟器正在启动…'

# 等设备上线（最多 150 秒）；起不来就把日志尾巴打出来，别假装成功
for i in {1..75}; do
  if is_running; then
    echo "模拟器已上线（约 $((i * 2)) 秒）。"
    break
  fi
  # 模拟器进程没了就别再等（比如沙箱权限不足、镜像被占用）
  if ! kill -0 "$EMU_PID" 2>/dev/null; then
    echo '✗ 模拟器进程已退出，最后 15 行日志：'
    tail -15 "$EMU_DIR/logs/emulator.log" 2>/dev/null
    exit 1
  fi
  sleep 2
  if (( i == 75 )); then
    echo '✗ 150 秒内没连上模拟器，最后 10 行日志：'
    tail -10 "$EMU_DIR/logs/emulator.log" 2>/dev/null
    exit 1
  fi
done

# 开机后自动修复 GPS 卫星数（模拟器自带 GNSS 不上报卫星，应用会显示"信号差"）
nohup "$BASE_DIR/修复GPS卫星数.command" > "$EMU_DIR/logs/gps-fix.log" 2>&1 < /dev/null &
echo '已安排：开机完成后自动修复 GPS 卫星数。'
