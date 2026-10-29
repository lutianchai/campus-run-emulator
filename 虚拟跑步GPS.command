#!/bin/zsh
# 虚拟跑步 GPS：沿操场跑道平滑绕圈，罗盘朝向跟着跑动方向转
#   - 沿 400m 跑道一圈圈跑，弯道是平滑圆弧，没有折线拐角
#   - 半径固定在 1~2 道之间（37.0~38.5 米），保证一直在跑道上
#   - 匀速、纯圆弧：不做前后/左右抖动（有抖动 App 会判异常点丢掉）
#   - 罗盘（orientation 传感器）方位角 = 跑道切线方向
# 默认：通用测试点（0°N, 0°E，不对应个人位置），3.8 m/s 左右（约 13.7 km/h，配速 4'23"/km）
# 用法：双击运行；或 ./虚拟跑步GPS.command [平均速度m/s] [纬度] [经度]
# 发点间隔：环境变量 DSH_GPS_INTERVAL，默认 0.5 秒（= 每步 1.9 米）
#   每步距离 = 速度 × 间隔。想让地图上的点走得更细腻就调小间隔，速度不受影响。
#   例：DSH_GPS_INTERVAL=0.25 ./虚拟跑步GPS.command 3.8   → 每步 0.95 米，仍 3.8 m/s
set -eu
BASE_DIR="${0:A:h}"
EMU_DIR="$BASE_DIR/运行环境"
ADB="$EMU_DIR/sdk/platform-tools/adb"
TOKEN_FILE="$HOME/.emulator_console_auth_token"

SPEED="${1:-3.8}"
LAT="${2:-${DSH_TEST_LAT:-0.0}}"
LON="${3:-${DSH_TEST_LON:-0.0}}"
INTERVAL="${DSH_GPS_INTERVAL:-0.5}"   # 发点间隔（秒）；每步距离 = SPEED × INTERVAL

if ! "$ADB" -e emu avd name >/dev/null 2>&1; then
  echo "模拟器没在运行，请先启动“启动安卓模拟器.command”"
  exit 1
fi
if [[ ! -f "$TOKEN_FILE" ]]; then
  echo "找不到模拟器控制台令牌：$TOKEN_FILE"
  exit 1
fi

STEP=$(awk -v s="$SPEED" -v i="$INTERVAL" 'BEGIN{printf "%.2f", s*i}')
echo "开始虚拟跑步（匀速绕圈）：速度 ${SPEED} m/s，每 ${INTERVAL} 秒一个点（每步约 ${STEP} 米），跑道中心 ${LAT},${LON}"
echo "按 Control-C 停止。"

python3 - "$TOKEN_FILE" "$SPEED" "$LAT" "$LON" "$INTERVAL" <<'PY'
import math, os, random, signal, socket, sys, threading, time

# 单实例
PIDFILE = "/tmp/dsh-virtualrun.pid"
try:
    old = int(open(PIDFILE).read().strip())
    os.kill(old, signal.SIGTERM)
    time.sleep(0.3)
except Exception:
    pass
open(PIDFILE, "w").write(str(os.getpid()))

token_file, base_speed, lat, lon = sys.argv[1], float(sys.argv[2]), float(sys.argv[3]), float(sys.argv[4])
INTERVAL = float(sys.argv[5])           # 发点间隔（秒）；每步距离 = base_speed × INTERVAL

HALF = 42.195                  # 直道半长
R_MIN, R_MAX = 37.0, 38.5      # 只在 1~2 道之间，稳稳在跑道上
SAT_COUNT = 12                 # 与 GNSS 补丁上报的数量保持一致
ALT = 0.0
M_PER_DEG_LAT = 111320.0
M_PER_DEG_LON = 111320.0 * math.cos(math.radians(lat))
KNOT = 1.943844                # 1 m/s = 1.943844 节

def pos_on_track(s, R):
    """沿跑道的里程 s（米）和半径 R，返回局部坐标 (x=东, y=北)"""
    straight = 2 * HALF
    curve = math.pi * R
    lap = 2 * straight + 2 * curve
    s %= lap
    if s < straight:                      # 西直道：由南向北
        return -R, -HALF + s
    s -= straight
    if s < curve:                         # 北弯道（平滑圆弧）
        a = math.pi - s / R
        return R * math.cos(a), HALF + R * math.sin(a)
    s -= curve
    if s < straight:                      # 东直道：由北向南
        return R, HALF - s
    s -= straight
    a = -s / R                            # 南弯道（平滑圆弧）
    return R * math.cos(a), -HALF + R * math.sin(a)

def connect():
    s = socket.create_connection(("127.0.0.1", 5554), timeout=3)
    s.settimeout(2.0)
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
    return s

class Link:
    """控制台连接：发送走阻塞 socket（保证命令完整送达），另起线程把回显读掉。
    注意：auth 后面必须跟令牌内容，写成令牌文件路径会认证失败，
    而认证失败后控制台会静默忽略所有命令（sendall 却仍然成功，很难查）。"""
    def __init__(self):
        self.reconnects = 0
        self._connect()

    def _connect(self):
        while True:
            try:
                self.s = connect()
                threading.Thread(target=self._reader, args=(self.s,), daemon=True).start()
                return
            except Exception:
                time.sleep(3)

    @staticmethod
    def _reader(sock):
        while True:
            try:
                if not sock.recv(8192):
                    return
            except socket.timeout:
                continue
            except Exception:
                return

    def send(self, cmd):
        try:
            self.s.sendall(cmd.encode())
            return True
        except Exception:
            self.reconnects += 1
            print(f"已重连模拟器控制台（第 {self.reconnects} 次）", flush=True)
            self._connect()
            try:
                self.s.sendall(cmd.encode())
                return True
            except Exception:
                return False

token = open(token_file).read().strip()
# 可选：DSH_GPS_TRACE=/path 时把每次发出的坐标写盘，用于离线校验轨迹平滑度（默认不写）
TRACE = None
_trace_path = os.environ.get("DSH_GPS_TRACE", "")
if _trace_path:
    TRACE = open(_trace_path, "w", buffering=1)
link = Link()

random.seed()
R = (R_MIN + R_MAX) / 2.0      # 固定半径（1~2 道正中），不做随机漂移
STATE = "/tmp/dsh-virtualrun.state"     # 记住里程，重启后接着跑，避免坐标瞬间跳到跑道别处
try:
    s_pos = float(open(STATE).read().strip())
except Exception:
    s_pos = random.uniform(0, 400)
speed = base_speed
dist = 0.0
hx, hy = 0.0, 1.0          # 朝向的向量表示，避免 0/360 跳变
tick = 0
i = 0
last_print = time.monotonic()
TICK = 0.1                 # 循环轮询粒度；比 INTERVAL 小一个量级，发点才不会量化到整 0.2 秒
next_t = time.monotonic()
last_upd = time.monotonic()   # 上次位置更新的真实时刻（里程按真实 dt 积分，避免循环追赶导致超速）
# 抖动用一阶自回归（OU 过程）而不是每次独立采样：相邻两次坐标的偏移是相关的，
# 轨迹是一条缓慢起伏的线；独立白噪声则会让轨迹变成锯齿，看起来"乱颤"
j_lat = 0.0                # 横向偏移（米）
j_lon = 0.0                # 沿跑道偏移（米）
J_TAU = 0.25               # 记忆系数：越小越平滑（0.25 ≈ 4 秒相关时间）
J_SIG = 0.10               # 噪声强度
print("平滑绕圈：半径固定为 37.75 米，坐标不抖动，罗盘跟随运动方向")
try:
    while True:
        now = time.monotonic()
        if now < next_t:
            time.sleep(min(next_t - now, TICK))
            continue
        next_t += TICK
        if now - next_t > 0.5:
            next_t = now + TICK

        # 位置按真实时间发送（不要用 tick 计数：循环追赶积压时 tick 会连跳）
        # 间隔 = INTERVAL（默认 0.5 秒）。速度不变，间隔越小每步越短、地图上越细腻。
        if now - last_upd >= INTERVAL:
            # 速度恒定：加减速会让 App 把该段判成"超速/异常"而不计入里程
            speed = base_speed
            # 半径必须恒定！pos_on_track 用 s % lap 求相位，而 lap 随半径变化，
            # s_pos 是累计里程（几十圈后 s/lap 很大），半径只要动 0.05 米，
            # 相位就会被圈数放大成每步十几米的跳动 → 前后抽动 + App 判超速。
            # 早期版本每步随机漂移半径，跑得越久越抖，原因就在这里。
            # 里程按真实经过时间积分；上限 1.3×间隔——控制台万一卡住几秒，
            # 宁可让轨迹慢一点，也不要一次跳很远（跳远必被 App 判超速、整段不计）
            dt = min(INTERVAL * 1.3, now - last_upd)
            last_upd = now
            step = speed * dt
            s_pos += step
            dist += step

            # 不做任何前后/左右抖动：坐标只沿跑道圆弧单调前进。
            # 一旦有随机偏移，相邻两点就会出现"倒退"，App 侧会当异常点丢弃
            j_lat = 0.0
            j_lon = 0.0
            x, y = pos_on_track(s_pos, R)

            la = lat + y / M_PER_DEG_LAT
            lo = lon + x / M_PER_DEG_LON
            link.send(f"geo fix {lo:.6f} {la:.6f} {ALT} {SAT_COUNT} {speed * KNOT:.2f}\n")
            if TRACE:
                TRACE.write(f"{now:.3f} {s_pos:.2f} {la:.6f} {lo:.6f} {R:.3f} {j_lat:.3f} {j_lon:.3f} {x:.2f} {y:.2f}\n")

            # 朝向 = 跑道切线方向（用干净坐标算，避免抖动带偏）
            x1, y1 = pos_on_track(s_pos, R)
            x2, y2 = pos_on_track(s_pos + 0.5, R)
            hd = math.degrees(math.atan2(x2 - x1, y2 - y1)) % 360.0
            hx = 0.6 * hx + 0.4 * math.sin(math.radians(hd))
            hy = 0.6 * hy + 0.4 * math.cos(math.radians(hd))

            i += 1
            # 每个点都存进度：重启后从这里接着跑，坐标不会突然跳回跑道别处
            try:
                open(STATE, "w").write(f"{s_pos:.2f}")
            except Exception:
                pass
            if now - last_print >= 30:
                last_print = now
                az_now = math.degrees(math.atan2(hx, hy)) % 360
                print(f"已跑 {dist/base_speed:.0f} 秒，{dist:.0f} 米（{dist/400:.2f} 圈），"
                      f"半径 {R:.1f} 米，朝向 {az_now:.0f}°", flush=True)

        # 5Hz：喂罗盘。注意字段顺序是 (方位角, 俯仰, 横滚)，方位角必须放第一个，
        # 写成 0:az:pitch 会让 APP 收到的方位角恒为 0（箭头永远指北）
        az = (math.degrees(math.atan2(hx, hy)) + random.gauss(0, 1.2)) % 360.0
        pitch = 28.0 + random.gauss(0, 2.0)
        link.send(f"sensor set orientation {az:.1f}:{pitch:.1f}:0\n")
        tick += 1
except KeyboardInterrupt:
    print("\n已停止。")
PY
