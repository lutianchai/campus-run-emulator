#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026. Permission is granted to use, copy, modify, publish,
# distribute, sublicense, and/or sell this software, provided this notice
# is included. THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND.
"""Set a test location through the Android Emulator's official geo interface."""
from pathlib import Path
import math
import subprocess

base = Path(__file__).resolve().parent
runtime = base / '运行环境'
if not (runtime / 'sdk').is_dir():
    raise SystemExit('缺少本项目 SDK，请先运行 ./安装环境.command')
adb = runtime / 'sdk/platform-tools/adb'

def dialog(script):
    return subprocess.run(['/usr/bin/osascript', '-e', script], text=True, capture_output=True)

def message(text):
    import json
    dialog('display dialog ' + json.dumps(text, ensure_ascii=False) + ' buttons {"好"} default button "好"')

answer = dialog('text returned of (display dialog "输入测试位置：纬度,经度（WGS84，英文逗号分隔）" default answer "" buttons {"取消", "设置位置"} default button "设置位置" with title "GPS 定位调试")')
if answer.returncode:
    raise SystemExit(0)
try:
    latitude, longitude = map(float, answer.stdout.strip().replace('，', ',').split(','))
    if not (math.isfinite(latitude) and math.isfinite(longitude) and -90 <= latitude <= 90 and -180 <= longitude <= 180):
        raise ValueError()
except ValueError:
    message('坐标格式不正确。请输入“纬度,经度”，纬度范围 -90 到 90，经度范围 -180 到 180。')
    raise SystemExit(1)
probe = subprocess.run([str(adb), '-e', 'emu', 'avd', 'name'], capture_output=True, text=True)
if probe.returncode or 'Campus_Test_ARM64' not in probe.stdout.splitlines():
    message('请先打开“安卓模拟器”，等待安卓主屏幕出现后再设置位置。')
    raise SystemExit(1)
result = subprocess.run([str(adb), '-e', 'emu', 'geo', 'fix', str(longitude), str(latitude)], capture_output=True, text=True)
if result.returncode or 'KO:' in result.stdout:
    message('位置设置失败：' + (result.stderr or result.stdout).strip())
    raise SystemExit(1)
message('测试位置已发送：\n纬度 ' + str(latitude) + '\n经度 ' + str(longitude) + '\n\n应用是否接受定位，需要在应用里实际检查。\n此工具模拟位置数据，不代表真实卫星接收信号。')
