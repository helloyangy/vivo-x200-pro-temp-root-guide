# 工具清单

本仓库只分发自己编写的脚本；第三方工具给出官方来源与校验值，不做二次打包（GhostLock 除外，见下）。

| 工具 | 版本 | 用途 | 许可证 | 获取 |
| --- | --- | --- | --- | --- |
| GhostLock-X200 | v1.3.5 + stage0fix v2 | 临时 root 主链（CVE-2026-43499） | Apache-2.0 | [v1.2.0 完整加固版](https://github.com/helloyangy/vivo-x200-pro-temp-root-guide/releases/tag/v1.2.0) / [上游仓库](https://github.com/xiaohj233/ghostlock-x200-root) |
| KernelSU 管理器 | v3.2.5 (32525) | root 管理器（LKM / 越狱模式） | GPL-3.0 | [官方 release](https://github.com/tiann/KernelSU/releases)，本仓库不再分发 |
| StevenBlock | v1.0 | systemless hosts 模块（重启后自动挂载广告规则） | 见上游仓库 | [Magisk-Modules-Alt-Repo/StevenBlock](https://github.com/Magisk-Modules-Alt-Repo/StevenBlock) |
| adb (platform-tools) | 任意近期版本 | 设备连接 | — | [developer.android.com](https://developer.android.com/tools/releases/platform-tools) |
| Python 3 + capstone + pyelftools | ≥ 3.10 | 运行 GhostLock 的偏移工具 | — | [python.org](https://www.python.org)、`pip install capstone pyelftools` |
| Zygisk Next | 1.5.2 | 仅记录：本机不可用（见踩坑 7） | GPL-3.0 | [Dr-TSNG/ZygiskNext](https://github.com/Dr-TSNG/ZygiskNext) |

## GhostLock-X200 v1.3.5

- 上游：[xiaohj233/ghostlock-x200-root](https://github.com/xiaohj233/ghostlock-x200-root)（public，Apache-2.0）
- 对应发布：[v1.3.5 Release](https://github.com/xiaohj233/ghostlock-x200-root/releases/tag/v1.3.5)，资产名 `ghostlock-x200-root-v1.3.5.zip`
- 本仓库提供三个资产：

| 资产 | 说明 | SHA256 |
| --- | --- | --- |
| `ghostlock-x200-root-v1.3.5-stage0fix-v2.zip` | **推荐（v1.2.0）**：完整加固 = 补 `kernel_release` + STAGE0 门禁 fail-closed | `16708CC627B2A00287ED465B0B547780A4A11D1E77CA41232C0DB4ACB93FD6C3` |
| `ghostlock-x200-root-v1.3.5-stage0fix.zip` | v1.1.0 最小修复：只补 `kernel_release` | `2A368F6FF8FAC57ECDCC34ED837273A3C20C9837E061AFDE46471220277E5BF7` |
| `ghostlock-x200-root-v1.3.5.zip` | 上游原样备份，未打补丁 | `0189A9ABBC461E3159C10B0FB6A09C07F415BAD1E5FF57991F7E381648231446` |

- v2 与上游包逐条目比对：100 个条目、顺序一致，只有
  `tools/offset_tools/win_offs_b57.json` 和 `tools/scripts/root_full_permissive_restore.ps1`
  两个文件内容不同；BOM 与原有 LF/CRLF 均保留
- 升级已有工具包：[scripts/patch_ghostlock.ps1](../scripts/patch_ghostlock.ps1)
  （幂等，同时应用两处修复，替换前后做语法解析，验证失败返回非零）
- 可审计补丁：[patches/ghostlock-v1.3.5-stage0-gate.patch](../patches/ghostlock-v1.3.5-stage0-gate.patch)、
  [patches/ghostlock-v1.3.5-stage0-failclosed.patch](../patches/ghostlock-v1.3.5-stage0-failclosed.patch)
  —— 基于上游 Git 的 LF 原文；Release zip 内主链为 CRLF，请用脚本而非 `git apply`
- 问题说明：[docs/upstream-issues.md](../docs/upstream-issues.md)
- 包内自带 `LICENSE`、`NOTICE`、`THIRD_PARTY_NOTICES.md`，分发时请一并保留
- 注意：包内 `README.md` 的标题仍写 `v1.3.4`，目录名与发布名是 `v1.3.5`
- 校验：

```powershell
Get-FileHash .\ghostlock-x200-root-v1.3.5-stage0fix-v2.zip -Algorithm SHA256
```

## KernelSU 管理器 APK

本仓库**不分发 APK**，请从官方 release 下载 v3.2.5 (32525) 的 APK。
需要备份手机上已装好的那一份时：

```powershell
adb shell pm path me.weishu.kernelsu
adb exec-out su -c "cat <上一步输出的路径去掉 package:>" > kernelsu_manager.apk
```

> **不要用「卸载再重装」去修管理器显示「未安装」**：踩坑 6 已确认该现象与 APK 无关，
> 重装原版 32525-2、升级官方 32680 都无法恢复；而卸载会重新分配 uid，
> 反而可能让内核里记录的管理器 uid 失效。正确做法是
> `adb shell su -c "/data/adb/ksud debug mark refresh"` 后重开管理器。

版本注意：管理器版本不要高于内核（本机为 32525）。普通 `adb install -r -d` 降级会被系统拒绝
（`INSTALL_FAILED_VERSION_DOWNGRADE`），root 下 `pm install -r -d` 可以降。

## 隐私说明

本仓库不包含任何来自真机的数据：

- 没有抓包文件（pcap）、日志、截图、UI dump
- 没有设备序列号、IP、账号、手机号
- 脚本中不硬编码设备路径或个人信息
