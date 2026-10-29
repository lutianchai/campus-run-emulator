#!/bin/zsh
# 步频模拟：给模拟器喂加速度计波形，让运动世界校园能“数出”步频
# 模拟器没有计步器硬件（无 step counter / step detector），只能用加速度计
# 波形刻意做得不规则：每步的时长/力度都单独采样，步频本身还会慢漂移，
# 偶尔出现拖沓步、轻重步，不是一条干净的等幅正弦
# 模拟器重启后会自动重连
# 用法：双击运行；或 ./步频模拟.command [基准步频 步/分]
set -eu
BASE_DIR="${0:A:h}"
EMU_DIR="$BASE_DIR/运行环境"
ADB="$EMU_DIR/sdk/platform-tools/adb"
TOKEN_FILE="$HOME/.emulator_console_auth_token"

CADENCE="${1:-180}"

if ! "$ADB" -e emu avd name >/dev/null 2>&1; then
  echo "模拟器没在运行，请先启动“启动安卓模拟器.command”"
  exit 1
fi
if [[ ! -f "$TOKEN_FILE" ]]; then
  echo "找不到模拟器控制台令牌：$TOKEN_FILE"
  exit 1
fi

echo "开始模拟步频：基准 ${CADENCE} 步/分（不规则波形，会自然漂移）"
echo "按 Control-C 停止。"

python3 - "$TOKEN_FILE" "$CADENCE" <<'PY'
import math, os, random, signal, socket, sys, time

# 单实例
PIDFILE = "/tmp/dsh-stepsim.pid"
try:
    old = int(open(PIDFILE).read().strip())
    os.kill(old, signal.SIGTERM)
    time.sleep(0.3)
except Exception:
    pass
open(PIDFILE, "w").write(str(os.getpid()))

token = open(sys.argv[1]).read().strip()
base = float(sys.argv[2])
RATE = 100.0
G = 9.8

def connect():
    s = socket.create_connection(("127.0.0.1", 5554), timeout=3)
    s.settimeout(1.0)
    try:
        s.recv(4096)
    except socket.timeout:
        pass
    s.sendall(f"auth {token}\n".encode())
    time.sleep(0.2)
    try:
        s.recv(4096)
    except socket.timeout:
        pass
    s.setblocking(False)
    return s

# ---- 每一步单独采样一组参数，避免“等幅等周期”的机器味 ----
drift = 0.0          # 步频的慢漂移（步/分）
def new_step():
    global drift
    # 慢漂移：平时小幅游走，偶尔一次较大变化（上下坡、避让、疲劳）
    if random.random() < 0.015:
        drift += random.gauss(0, 3.5)
    drift = max(-9.0, min(9.0, drift * 0.997 + random.gauss(0, 0.28)))
    cad = base + drift + random.gauss(0, 1.3)
    cad = max(120.0, cad)
    dur = 60.0 / cad
    if random.random() < 0.03:                 # 3% 拖沓步（系鞋带、看路）
        dur *= random.uniform(1.12, 1.45)
    amp = 3.0 * (1 + random.gauss(0, 0.18))    # 每步力度不同
    if random.random() < 0.07:                 # 偶尔明显轻/重的一步
        amp *= random.uniform(0.6, 1.35)
    amp = max(1.4, min(4.8, amp))
    return {
        "dur": dur, "amp": amp,
        "h2": random.uniform(0.12, 0.48), "h2ph": random.uniform(0, 2 * math.pi),
        "h3": random.uniform(0.04, 0.18), "h3ph": random.uniform(0, 2 * math.pi),
        "lat": random.gauss(0, 0.22), "latph": random.uniform(0, 2 * math.pi),
        "fwd": random.gauss(0, 0.14), "fwdph": random.uniform(0, 2 * math.pi),
        "wob": random.uniform(0.7, 1.15),
    }

s = connect()
t0 = time.monotonic()
sent = 0
skipped = 0
reconnects = 0
next_t = t0
step = new_step()
phase = 0.0
steps = 0
try:
    while True:
        now = time.monotonic()
        if now < next_t:
            time.sleep(next_t - now)
            continue
        next_t += 1.0 / RATE
        if now - next_t > 0.2:
            next_t = now + 1.0 / RATE

        phase += (1.0 / RATE) / step["dur"]
        if phase >= 1.0:
            phase -= 1.0
            steps += 1
            step = new_step()

        ph = 2 * math.pi * phase
        # 不对称波形：落地冲击快、离地慢，再叠两个随机相位的谐波
        s_wave = (math.sin(ph)
                  + step["h2"] * math.sin(2 * ph + step["h2ph"])
                  + step["h3"] * math.sin(3 * ph + step["h3ph"]))
        z = G + step["amp"] * s_wave + random.gauss(0, 0.10)
        x = step["wob"] * 0.85 * math.sin(ph + step["latph"]) + step["lat"] + random.gauss(0, 0.05)
        y = 0.45 * math.sin(0.5 * ph + step["fwdph"]) + step["fwd"] + random.gauss(0, 0.05)

        cmd = f"sensor set acceleration {x:.3f}:{y:.3f}:{z:.3f}\n"
        try:
            s.sendall(cmd.encode())
            sent += 1
        except (BlockingIOError,):
            skipped += 1
        except (BrokenPipeError, ConnectionError, OSError):
            # 模拟器重启了，重连后继续
            try:
                s.close()
            except Exception:
                pass
            time.sleep(2)
            while True:
                try:
                    s = connect()
                    reconnects += 1
                    print(f"已重连模拟器控制台（第 {reconnects} 次）", flush=True)
                    break
                except Exception:
                    time.sleep(3)
        if sent % (int(RATE) * 30) == 0 and sent:
            print(f"已模拟 {sent // int(RATE)} 秒，当前约 {60.0/step['dur']:.0f} 步/分"
                  f"（基准 {base:.0f}，漂移 {drift:+.1f}，丢弃 {skipped}，重连 {reconnects}）", flush=True)
except KeyboardInterrupt:
    print("\n已停止。")
finally:
    try:
        s.close()
    except Exception:
        pass
PY
