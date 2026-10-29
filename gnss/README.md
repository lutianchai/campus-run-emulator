# GNSS 测试资产

三个 ARM64 ELF 来自原开发环境的 API 33 Goldfish GNSS 服务：

- `gnss-original`：留存原件。
- `gnss-12sv`：12 星合成状态，默认启动使用。
- `gnss-test-strong`：强信号合成状态，可选调试入口使用。

这些是合成数据，不代表真实卫星接收。仅针对原镜像版本使用；相同文件路径不保证其他镜像 ABI 兼容。重启会解除 bind mount。不要在生产设备替换系统服务。

运行 `python3 gnss/rebuild.py`，根据原件和 `patches.json` 在本地重新产生两个补丁文件；该过程不执行 ELF。运行 `(cd gnss && shasum -a 256 -c SHA256SUMS)` 验证全部文件。

提供了可审阅的字节差异，但尚未取得与这些 ELF 精确对应的源码提交及源码级构建配方。许可证和来源限制见仓库根目录 NOTICE；上游 Apache-2.0 不受本仓库 MIT 覆盖。
