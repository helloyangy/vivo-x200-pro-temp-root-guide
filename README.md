# vivo X200 Pro 临时 Root 教程（GhostLock + KernelSU）

> 面向 **vivo X200 Pro（PD2405）+ Android 16** 的临时 root 实战记录。
> 不解锁 Bootloader、不刷机、不修改系统分区，重启后失效。
> 本文包含完整流程、验证方法以及实际踩过的坑。

---

## 一、适用设备

| 项目 | 值 |
| --- | --- |
| 机型 | vivo X200 Pro（PD2405） |
| 系统 | Android 16（API 36） |
| 固件 | `PD2405B_A_16.1.22.2.W10` |
| 内核 | `6.6.89-android15-8-gb57af212129c-abogki457297774-4k` |
| 提权工具 | GhostLock-X200 v1.3.5（`x200_b57` 构建） |
| Root 框架 | KernelSU v3.2.5（LKM / 越狱模式） |

> 核心条件：内核 `< 6.6.140` 且构建号包含 `b57af212129c`。
> 升级系统后如果内核版本达到 `6.6.140`，漏洞已被修复，本教程失效。

---

## 二、原理简介

GhostLock 利用 **CVE-2026-43499**（futex PI requeue 导致的 use-after-free），
在用户态完成提权，然后加载 KernelSU 的 LKM 内核模块，获得临时 root。

特点：

- 不写 boot / init_boot 分区，不解锁 Bootloader
- 不触发数据清除
- **纯内存会话，冷启动后失效**
- 需要配合 `permissive_restore.ko` 修复 KernelSU 在此设备上的 SELinux 策略缺陷（否则断网、热点异常）

---

## 三、前置条件

### 电脑端

- Windows 10/11
- adb（Android Platform Tools）
- Python 3
- Python 依赖：

```powershell
pip install capstone pyelftools
```

### 手机端

- 开启「开发者选项」和「USB 调试」
- 首次连接时在手机上确认授权弹窗

检查设备：

```powershell
adb devices
# 应显示 <你的设备序列号>    device
```

---

## 四、提权步骤

### 1. 准备工具

将 GhostLock-X200 v1.3.5 解压到任意目录，例如：

```text
ghostlock-x200-root-main\
├── root.ps1
├── run_root.bat
├── devices\x200_b57\
├── modules\
├── prebuilt\
└── tools\
```

### 2. 运行提权

在工具目录打开 PowerShell，执行：

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\root.ps1 -Force
```

> **必须带 `-Force`**。原因见「踩坑 1」。

### 3. 等待完成

脚本会依次执行：

```text
STAGE1 permissive → STAGE2 kptr → STAGE3 base → STAGE3.4 动态偏移
→ STAGE3.5 模块 patch & push → STAGE4/5 提权
→ STAGE6 INSMOD permissive_restore + kernelsu
→ STAGE7 验证 → STAGE8 注册管理器
```

成功标志：

```text
=== ALL STAGES PASS: Permissive + KSU 32525 + permissive_restore Live + 网络通 ===
DONE
```

整个过程约 1-2 分钟。

### 4. 验证 root

```powershell
adb shell su -c id
# uid=0(root) gid=0(root) groups=0(root) context=u:r:ksu:s0

adb shell /data/adb/ksud debug version
# Kernel Version: 32525
```

KernelSU 管理器应显示：

```text
工作中 <LKM>
```

---

## 五、日常使用规则

**每次重启手机后，root 都会失效，必须重跑一次提权脚本。**

建议流程：

1. 开机后等待 1-2 分钟，让系统后台任务稳定
2. 运行 `root.ps1 -Force`
3. 看到 `ALL STAGES PASS` 后再使用需要 root 的功能

不要在开机后立刻运行，系统负载过高会导致脚本在 STAGE4 主动中止。

---

## 六、踩坑与排错

详细内容见 [docs/troubleshooting.md](docs/troubleshooting.md)，摘要如下：

| # | 问题 | 结论 |
| --- | --- | --- |
| 1 | 脚本提示「机型未精确匹配」并退出 | PD2405 与随包 PD2415 不同，必须加 `-Force` |
| 2 | STAGE4 报 `loadavg` 过高后中止 | 关闭后台大 App，等系统空闲后重跑 |
| 3 | 重启后 `su` 消失 | 正常，重跑 GhostLock 即可 |
| 4 | `svc power reboot userspace` 不支持 | vivo 系统禁用了 userspace reboot |
| 5 | `ksud soft-reboot` 后 su/管理器失效 | 软重启同样会让临时 root 会话失效，必须重跑 |
| 6 | 管理器显示「未安装」 | 重装管理器 APK 可修复；`pm clear` 反而会破坏注册状态 |
| 7 | LSPosed / Vector / Zygisk 模块不生效 | 临时 root 与 Zygisk 机制冲突，不可行 |
| 8 | 重启后开屏广告回来了 | 检查 StevenBlock 模块 hosts，必要时重跑 `apply_adblock.sh` |

---

## 七、可选：趣智校园去广告

本仓库附带 `scripts/adblock_zqxy.sh`，通过 hosts 拦截趣智校园的广告 SDK 域名。

使用前提：root 已恢复。

```powershell
adb push scripts\adblock_zqxy.sh /data/local/tmp/adblock_zqxy.sh
adb shell su -c "sh /data/local/tmp/adblock_zqxy.sh"
```

说明：

- 仅拦截第三方广告 SDK 域名（TopOn、Pangle、GDT、Sigmob、YFAds、BeiZi、京东联盟等）
- 不影响 App 核心功能
- App 内自有运营位（横幅、返利频道）由 App 业务接口下发，hosts 无法去除

配合清理广告缓存：

```powershell
adb push scripts\clear_ad_cache.sh /data/local/tmp/clear_ad_cache.sh
adb shell su -c "sh /data/local/tmp/clear_ad_cache.sh"
```

缓存会先备份到 `/data/local/tmp/zqxy_adcache_backup`，需要时可手动恢复。

---

## 八、不要再做的事

以下操作已在真机上验证会导致 root 失效，且无法通过简单操作恢复：

1. **不要执行 `svc power reboot userspace`**：vivo 系统不支持。
2. **不要执行 `ksud soft-reboot`**：会导致 `su`、`ksud` 失效，只能重跑 GhostLock。
3. **不要在临时 root 上安装 LSPosed / Vector**：Zygisk 模块需要 zygote 启动时注入，而每次 zygote 重启都会打断 GhostLock 会话，形成死循环。
4. **不要点 KernelSU 管理器里的「卸载」或「安装」**：可能触发移除 root 或重装内核模块。
5. **不要升级系统**：内核达到 `6.6.140` 后漏洞被修复。

---

## 九、免责声明

本项目仅用于个人设备的安全研究与技术学习。临时 root 会降低设备安全性，
使用前请自行评估风险。因操作导致的设备异常、数据丢失或账号问题，由使用者自行承担。
请遵守当地法律法规与相关服务条款。

---

## 十、参考

- GhostLock（CVE-2026-43499）：用户态提权 + KernelSU LKM
- KernelSU：https://kernelsu.org/
- Zygisk Next：https://github.com/Dr-TSNG/ZygiskNext
