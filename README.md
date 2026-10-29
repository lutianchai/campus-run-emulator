# campus-run-emulator

macOS Apple silicon 上的 Android 模拟器自动化工具箱：系统定位注入、合成 GNSS 卫星状态、加速度传感器输入、多用户空间管理、一键启停和运行检查。包含适配“运动世界校园”包名的启动入口，属于非官方技术实践。

本项目不附带第三方应用、登录账号、虚拟设备数据或 Android SDK。定位经模拟器控制台注入，不修改目标应用；卫星状态补丁会临时替换模拟器的 GNSS HAL。

## 环境要求

- macOS Apple silicon、zsh、Python 3、JDK 21、zip、Git。
- Android SDK：platform-tools、emulator、build-tools 35.0.0、platforms android-35。
- AVD：`Campus_Test_ARM64`，Pixel 5 profile，API 33 Google APIs ARM64 **userdebug** 镜像。
- 原开发环境：Emulator 37.2.12.0、API 33 镜像 revision 17。安装脚本取得的当前版本可能不同；尤其 GNSS 二进制仅针对原镜像验证，其他版本兼容性需实测。
- 空间切换依赖设备本机 adbd 的 root 权限和 `ro.adb.secure=0`；普通真机及 Google Play 镜像通常不满足。

## 快速开始

1. 安装 Python 3 和 JDK 21，确保 `python3` 可执行、`JAVA_HOME` 指向 JDK 21。
2. 从 [Android 官方页面](https://developer.android.com/studio#command-tools) 下载 Mac ARM 命令行工具。解压到下列结构：

   ```text
   运行环境/sdk/cmdline-tools/latest/bin/sdkmanager
   运行环境/sdk/cmdline-tools/latest/bin/avdmanager
   ```

3. 在仓库目录运行（会下载 SDK 和系统镜像，可能占用十余 GB；许可需自行阅读确认）：

   ```sh
   ./安装环境.command
   ./空间切换App/构建.sh
   ./启动安卓模拟器.command
   ./安装空间切换.command
   ```

4. 如需测试第三方应用，请自行从合法渠道安装。项目默认启动包为 `com.zjwh.android_wh_physicalfitness`，不含该应用的 APK 或数据。
5. 一键启用全部组件：

   ```sh
   ./一键启动.command
   ./全部关闭.command
   ```

   一键启动会启动定位和传感器模拟，并拉起适配应用。默认坐标为 **0°N, 0°E 的通用测试点**。测试其他地点时可在本机临时设置 `DSH_TEST_LAT`、`DSH_TEST_LON`，或直接向 GPS 脚本传参；不要将私人坐标写入提交。

完整环境尚未配置时，启动失败是预期行为。安装脚本不会读取、复制原开发者的设备或账号。

## 命令

| 入口 | 功能 |
|---|---|
| `安装环境.command` | 安装独立 SDK、创建干净 AVD；已有 AVD 不覆盖 |
| `一键启动.command [速度m/s] [步频]` | 模拟器、卫星补丁、轨迹、加速度输入、应用、自检 |
| `全部关闭.command` | 停止模拟、关闭模拟器、清理状态并校验 |
| `启动安卓模拟器.command` | 启动 AVD，使用 `-gpu swangle`，安排 GNSS 补丁 |
| `虚拟跑步GPS.command [速度m/s] [纬度] [经度]` | 固定跑道几何的匀速轨迹；默认 3.8 m/s、0.5 秒一个点 |
| `步频模拟.command [步频]` | 加速度波形；默认基准 180 步/分 |
| `修复GPS卫星数.command` | 挂载 12 星测试 HAL，校验目标文件 SHA-256 |
| `修复网络.command [--force]` | DNS/TCP 探测，故障时重启整套工具 |
| `安装空间切换.command` | 安装自有 APK 并同步到已有用户 |
| `GPS定位调试.py` | macOS 对话框输入单点 WGS84 坐标 |
| `启用GPS测试模式.py` | 可选强信号测试 HAL；版本不匹配时拒绝替换 |

`DSH_GPS_INTERVAL` 控制发点间隔；每步距离约为速度乘间隔。`DSH_GPS_TRACE` 可将坐标写入本机指定文件，轨迹可能包含私人位置，不要公开。

## 检查方式与局限

脚本设计目标是用即时证据报告状态：开机属性、GNSS 文件哈希、进程与日志新鲜度、应用进程/前台活动、客机 TCP 实测，而非“命令没有报错就是成功”。冷启动探测包含重试。

部分提示仍只是中间状态，例如“模拟器已上线”不等于开机完成、应用有进程不等于进入目标页面。网络和定位提示可能是警告而不影响总退出码；每项结果需结合自检输出理解。整理发布时完成了静态检查和 APK 构建验证，未对包含私人登录态的原设备运行一键启停回归。

## 目录与资料

- 根目录：入口脚本、MIT 许可、自有空间切换 APK。
- `空间切换App/`：Java 源码、图标和无 Gradle 构建脚本。
- `gnss/`：原始及修改后的测试 HAL、哈希、可复现字节补丁。
- `docs/`：架构、排障、开发注意事项和发布隐私边界。
- `运行环境/`：本机生成，始终忽略。

## 使用边界

用于隔离测试环境中的 Android 自动化、定位与传感器研究。合成位置、卫星信号和步频均不代表真实运动数据，不保证应用接受、不保证通过检测。请遵守学校规定和平台条款，不使用本项目伪造考勤、成绩或运动记录。与第三方应用及其运营方无关联。

空间切换工具在满足条件的模拟器里可执行 root 命令，且包含删除 Android 用户的功能；只在隔离测试 AVD 使用，不要将无认证 adbd 暴露到外部网络。每个空间隔离应用数据，但不提供对宿主机或 root 的隔离。

项目代码使用 [MIT](LICENSE)；GNSS 文件另受 [Apache-2.0](LICENSES/Apache-2.0.txt) 约束，见 [NOTICE](NOTICE)。SDK 和系统镜像需从官方单独获取并遵守各自许可。

## English summary

An experimental Android Emulator automation toolkit for macOS Apple silicon: location injection, synthetic GNSS status, accelerometer input, Android user switching, and startup diagnostics. Includes an independently developed companion app, but no third-party app, SDK, AVD data, credentials, or personal test coordinates. Use only in isolated, authorized test environments. MIT for project code; Apache-2.0 for the Goldfish-derived GNSS assets. No guarantee of compatibility or acceptance by third-party apps.
