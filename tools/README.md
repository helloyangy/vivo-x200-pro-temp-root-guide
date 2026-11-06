# 工具清单

本仓库只分发自己编写的脚本；第三方工具给出官方来源与校验值，不做二次打包（GhostLock 除外，见下）。

| 工具 | 版本 | 用途 | 许可证 | 获取 |
| --- | --- | --- | --- | --- |
| GhostLock-X200 | v1.3.5 | 临时 root 主链（CVE-2026-43499） | Apache-2.0 | [上游仓库](https://github.com/xiaohj233/ghostlock-x200-root) / [v1.3.5 Release](https://github.com/xiaohj233/ghostlock-x200-root/releases/tag/v1.3.5) |
| KernelSU 管理器 | v3.2.5 (32525) | root 管理器（LKM / 越狱模式） | GPL-3.0 | [官方 release](https://github.com/tiann/KernelSU/releases)，本仓库不再分发 |
| StevenBlock | v1.0 | systemless hosts 模块（重启后自动挂载广告规则） | 见上游仓库 | [Magisk-Modules-Alt-Repo/StevenBlock](https://github.com/Magisk-Modules-Alt-Repo/StevenBlock) |
| adb (platform-tools) | 任意近期版本 | 设备连接 | — | [developer.android.com](https://developer.android.com/tools/releases/platform-tools) |
| Python 3 + capstone + pyelftools | ≥ 3.10 | 运行 GhostLock 的偏移工具 | — | [python.org](https://www.python.org)、`pip install capstone pyelftools` |
| Zygisk Next | 1.5.2 | 仅记录：本机不可用（见踩坑 7） | GPL-3.0 | [Dr-TSNG/ZygiskNext](https://github.com/Dr-TSNG/ZygiskNext) |

## GhostLock-X200 v1.3.5

- 上游：[xiaohj233/ghostlock-x200-root](https://github.com/xiaohj233/ghostlock-x200-root)（public，Apache-2.0）
- 对应发布：[v1.3.5 Release](https://github.com/xiaohj233/ghostlock-x200-root/releases/tag/v1.3.5)，资产名 `ghostlock-x200-root-v1.3.5.zip`
- 本仓库 Release 资产与上游发布**逐字节相同**（大小 6,738,802 字节，SHA256 与上游 release digest 一致）：
  `0189A9ABBC461E3159C10B0FB6A09C07F415BAD1E5FF57991F7E381648231446`
- 备份目的：上游仓库若被删除或改动，本仓库仍可复现教程；优先使用上游链接
- 包内自带 `LICENSE`、`NOTICE`、`THIRD_PARTY_NOTICES.md`，分发时请一并保留
- 注意：包内 `README.md` 的标题仍写 `v1.3.4`，目录名与发布名是 `v1.3.5`
- 校验：

```powershell
Get-FileHash .\ghostlock-x200-root-v1.3.5.zip -Algorithm SHA256
```

## KernelSU 管理器 APK

本仓库**不分发 APK**，请从官方 release 下载 v3.2.5 (32525) 的 APK。

踩坑 6 提到的「提取 / 卸载 / 重装管理器」流程，用的就是你手机上当前安装的那一份：

```powershell
adb shell pm path me.weishu.kernelsu
adb exec-out su -c "cat <上一步输出的路径去掉 package:>" > kernelsu_manager.apk
adb shell pm uninstall me.weishu.kernelsu
adb install kernelsu_manager.apk
```

## 隐私说明

本仓库不包含任何来自真机的数据：

- 没有抓包文件（pcap）、日志、截图、UI dump
- 没有设备序列号、IP、账号、手机号
- 脚本中不硬编码设备路径或个人信息
