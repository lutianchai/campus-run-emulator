#!/bin/zsh
# 构建「空间切换」APK（不需要 Gradle / Android Studio）
set -eu
BASE="${0:A:h}"
ROOT="$BASE/.."
SDK="${ANDROID_HOME:-$ROOT/运行环境/sdk}"
JDK="${JAVA_HOME:-}"
if [[ -z "$JDK" ]]; then
  JDK=$(/usr/libexec/java_home -v 21 2>/dev/null) || { print "请安装 JDK 21 并设置 JAVA_HOME"; exit 1; }
fi
BT="${ANDROID_BUILD_TOOLS:-$SDK/build-tools/35.0.0}"
AJ="$SDK/platforms/android-35/android.jar"
OUT="$BASE/build"
KS="$BASE/keystore.jks"

export JAVA_HOME="$JDK"
export PATH="$JDK/bin:$PATH"

[[ -x "$BT/aapt2" ]] || { print "缺少 build-tools: $BT"; exit 1; }
[[ -f "$AJ" ]] || { print "缺少 android.jar: $AJ"; exit 1; }

if [[ ! -f "$KS" ]]; then
  print "生成签名密钥…"
  "$JDK/bin/keytool" -genkeypair -keystore "$KS" -alias space -keyalg RSA -keysize 2048 \
    -validity 10000 -storepass android -keypass android -dname "CN=Space Switcher, O=DSH" >/dev/null 2>&1
fi

rm -rf "$OUT"
mkdir -p "$OUT/gen" "$OUT/classes" "$OUT/dex"

print "① aapt2 compile"
"$BT/aapt2" compile --dir "$BASE/res" -o "$OUT/res.zip"

print "② aapt2 link"
"$BT/aapt2" link -o "$OUT/base.apk" -I "$AJ" \
  --manifest "$BASE/AndroidManifest.xml" \
  -R "$OUT/res.zip" \
  --java "$OUT/gen" \
  --min-sdk-version 30 --target-sdk-version 33 \
  --version-code 1 --version-name 1.0 \
  --auto-add-overlay

print "③ javac"
find "$BASE/src" -name "*.java" > "$OUT/sources.txt"
"$JDK/bin/javac" -source 8 -target 8 -Xlint:-options -encoding UTF-8 \
  -bootclasspath "$AJ:$BT/core-lambda-stubs.jar" -classpath "$AJ" -d "$OUT/classes" @"$OUT/sources.txt"

print "④ d8"
find "$OUT/classes" -name "*.class" > "$OUT/classes.txt"
"$BT/d8" \
  --min-api 30 --lib "$AJ" --output "$OUT/dex" $(cat "$OUT/classes.txt")

print "⑤ 打包 + 签名"
cp "$OUT/base.apk" "$OUT/app.apk"
(cd "$OUT" && zip -q -j app.apk dex/classes.dex)
"$BT/zipalign" -f 4 "$OUT/app.apk" "$OUT/app-aligned.apk"
"$BT/apksigner" sign --ks "$KS" --ks-pass pass:android --key-pass pass:android \
  --min-sdk-version 30 --v1-signing-enabled true --v2-signing-enabled true \
  --out "$ROOT/空间切换.apk" "$OUT/app-aligned.apk"
"$BT/apksigner" verify --print-certs "$ROOT/空间切换.apk" | head -3
print ""
print "✓ 产物：$ROOT/空间切换.apk  ($(du -h "$ROOT/空间切换.apk" | cut -f1))"
