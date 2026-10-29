#!/bin/zsh
# 使用用户从 Android 官方获得的命令行工具安装独立、干净的运行环境。
set -eu
BASE="${0:A:h}"
RUNTIME="$BASE/运行环境"
export ANDROID_HOME="$RUNTIME/sdk"
export ANDROID_USER_HOME="$RUNTIME/user"
export ANDROID_EMULATOR_HOME="$RUNTIME/user"
export ANDROID_AVD_HOME="$RUNTIME/avd"
export JAVA_HOME="${JAVA_HOME:-$(/usr/libexec/java_home -v 21 2>/dev/null || true)}"
[[ -x "$JAVA_HOME/bin/java" ]] || { print "请先安装 JDK 21 并设置 JAVA_HOME，详见 README.md"; exit 1; }
export PATH="$JAVA_HOME/bin:$PATH"
mkdir -p "$ANDROID_HOME" "$ANDROID_USER_HOME" "$ANDROID_AVD_HOME"
SDKMANAGER="$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager"
AVDMANAGER="$ANDROID_HOME/cmdline-tools/latest/bin/avdmanager"
[[ -x "$SDKMANAGER" && -x "$AVDMANAGER" ]] || {
  print "请从 https://developer.android.com/studio#command-tools 下载 Mac 命令行工具。"
  print "把解压后的 cmdline-tools 内容放到：$ANDROID_HOME/cmdline-tools/latest/"
  print "确认 latest/bin/sdkmanager 存在后再运行本脚本。"
  exit 1
}
print "Android SDK 许可由你阅读、决定是否接受。"
"$SDKMANAGER" --sdk_root="$ANDROID_HOME" --licenses
"$SDKMANAGER" --sdk_root="$ANDROID_HOME" 'platform-tools' 'emulator' 'build-tools;35.0.0' 'platforms;android-35' 'system-images;android-33;google_apis;arm64-v8a'
if [[ -d "$ANDROID_AVD_HOME/Campus_Test_ARM64.avd" || -f "$ANDROID_AVD_HOME/Campus_Test_ARM64.ini" ]]; then
  print "已有 Campus_Test_ARM64，保留设备及其数据。"
else
  print 'no' | "$AVDMANAGER" create avd --name Campus_Test_ARM64 --package 'system-images;android-33;google_apis;arm64-v8a' --device pixel_5
  cat >> "$ANDROID_AVD_HOME/Campus_Test_ARM64.avd/config.ini" <<'INI'
hw.lcd.width=720
hw.lcd.height=1560
hw.lcd.density=294
hw.ramSize=3072
hw.cpu.ncore=4
PlayStore.enabled=no
INI
fi
print "✓ SDK 与干净设备已准备；第三方应用需要自行合法安装。"
