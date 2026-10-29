#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# This script is provided under LICENSE (MIT).
# The GNSS service it temporarily mounts is derived from AOSP (Apache-2.0).
from pathlib import Path
import subprocess, hashlib, json, time

base = Path(__file__).resolve().parent
runtime = base / '运行环境'
if not (runtime / 'sdk').is_dir():
    raise SystemExit('缺少本项目 SDK，请先运行 ./安装环境.command')
adb = str(runtime / 'sdk/platform-tools/adb')
asset = base / 'gnss/gnss-test-strong'
target = '/vendor/bin/hw/android.hardware.gnss@2.0-service.ranchu'
remote = '/data/local/tmp/gnss-test-strong'
original = '760fbd0000f82a5c69c8c1e397467038f267f1ee392cd755f511ddbb1f2086e2'
patched = 'ebac7f0c207eacf44dff84175ea00165dcff539a77758eb929fc23e77a896b6b'

def run(*args):
    r = subprocess.run([adb, '-e', *args], text=True, capture_output=True, timeout=30)
    if r.returncode:
        raise RuntimeError((r.stderr or r.stdout).strip())
    return r.stdout.strip()

def show(text):
    subprocess.run(['/usr/bin/osascript', '-e', 'display dialog ' + json.dumps(text, ensure_ascii=False) + ' buttons {"好"} default button "好" with title "GPS 测试模式"'], capture_output=True)

mounted = False
root_requested = False
try:
    if 'Campus_Test_ARM64' not in run('emu', 'avd', 'name').splitlines():
        raise RuntimeError('请先启动本文件夹内的安卓模拟器。')
    if hashlib.sha256(asset.read_bytes()).hexdigest() != patched:
        raise RuntimeError('测试驱动校验失败，未做修改。')
    root_requested = True
    run('root')
    run('wait-for-device')
    current = run('shell', 'sha256sum', target).split()[0]
    if current not in (original, patched):
        raise RuntimeError('当前系统驱动版本不匹配，未做修改。')
    if current == original:
        run('push', str(asset), remote)
        run('shell', 'chmod', '755', remote)
        run('shell', 'chcon', 'u:object_r:hal_gnss_default_exec:s0', remote)
        run('shell', 'mount', '-o', 'bind', remote, target)
        mounted = True
        run('shell', 'mount', '-o', 'remount,bind,suid', target)
        run('shell', 'setprop', 'ctl.restart', 'vendor.gnss-2-0')
        for _ in range(10):
            if run('shell', 'getprop', 'init.svc.vendor.gnss-2-0') == 'running':
                break
            time.sleep(1)
        else:
            raise RuntimeError('GNSS测试服务未正常启动。')
    run('unroot')
    root_requested = False
    show('GPS 测试模式已启用。\n\n它使用42 dB-Hz、45度仰角的合成卫星测试数据；这不是实际接收到的卫星信号。坐标请用“GPS定位调试”设置。启用后请重新打开运动世界。\n\n重启模拟器会恢复原驱动；下次需要时再次打开本工具即可。')
except Exception as exc:
    if mounted:
        try:
            run('shell', 'umount', target)
            run('shell', 'setprop', 'ctl.start', 'vendor.gnss-2-0')
        except Exception:
            pass
    show('未能启用：' + str(exc) + '\n如需完全恢复原状态，请重启模拟器。')
    raise SystemExit(1)
finally:
    if root_requested:
        try:
            run('unroot')
        except Exception:
            pass
