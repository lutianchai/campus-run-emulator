#!/bin/zsh
# 安装/更新「空间切换」App（一次性，之后全部在模拟器里点）
set -eu
BASE="${0:A:h}"
EMU="$BASE/运行环境"
ADB="$EMU/sdk/platform-tools/adb"
APK="$BASE/空间切换.apk"

[[ -f "$APK" ]] || { print "✗ 找不到 $APK"; print "  先在 空间切换App/构建.sh 里构建一次"; exit 1 }

if ! "$ADB" -e get-state >/dev/null 2>&1; then
  print "✗ 模拟器没在运行。先跑 一键启动.command，或 启动安卓模拟器.command"
  exit 1
fi

print "① 安装到主空间"
"$ADB" -e install -r -g "$APK" | tail -1

print "② 同步到其它已有空间"
for u in $("$ADB" -e shell pm list users | grep -oE 'UserInfo\{[0-9]+' | grep -oE '[0-9]+'); do
  [[ "$u" == "0" ]] && continue
  if "$ADB" -e shell pm install-existing --user "$u" com.dsh.space >/dev/null 2>&1; then
    print "   user $u ✓"
  else
    print "   user $u ✗"
  fi
done

print "③ 防止屏幕自动熄灭"
"$ADB" -e shell settings put system screen_off_timeout 2147483647 >/dev/null 2>&1 || true
"$ADB" -e shell svc power stayon true >/dev/null 2>&1 || true

print "④ 打开应用"
"$ADB" -e shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
"$ADB" -e shell am start -n com.dsh.space/.MainActivity >/dev/null 2>&1 || true

print ""
print "✓ 装好了。模拟器里点「空间切换」图标即可；长按标题可自检。"
