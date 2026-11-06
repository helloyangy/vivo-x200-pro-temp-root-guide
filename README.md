# vivo X200 Pro 临时 Root 教程（GhostLock + KernelSU）

> 面向 **vivo X200 Pro（PD2405）+ Android 16** 的临时 root 实战记录。
> 不解锁 Bootloader、不刷机、不修改系统分区，重启后失效。
> 本文包含完整流程、验证方法以及实际踩过的坑。

---

## 一、适用设备

### 本教程实测（唯一完整验证的构建）

| 项目 | 值 |
| --- | --- |
| 机型 | vivo X200 Pro（PD2405） |
| 系统 | Android 16（API 36） |
| 固件 | `PD2405B_A_16.1.22.2.W10` |
| 内核 | `6.6.89-android15-8-gb57af212129c-abogki457297774-4k` |
| 提权工具 | GhostLock-X200 v1.3.5（`x200_b57` 构建） |
| Root 框架 | KernelSU v3.2.5（LKM / 越狱模式） |

本文的每一步、每个踩坑，都只在这一个构建上验证过。

### 设备范围（上游标称 + 本教程补充）

| 设备 | 系统 / 内核 | 状态 |
| --- | --- | --- |
| vivo X200（PD2415） | 16.1.12.2.W10，b57 | ✅ 上游已实测 |
| vivo X200 Pro（PD2405） | 16.1.22.2.W10，b57 | ✅ 本教程实测（上游表中没有，需 `-Force`） |
| vivo X200（PD2415） | 16.1.12.12.W10，b57 同内核 | ⚠️ 未实测 |
| vivo X200s | 16.1.12.12.W10，b57 同内核 | ⚠️ 未实测，可尝试 |
| vivo X200（PD2415） | 其他 16.1.x，b57 | ⚠️ 未实测 |
| iQOO Neo11 等同 6.6.89 MTK 机型 | 同内核 | ⚠️ 需自行二次适配 |
| 任何内核 ≥ 6.6.140 的构建 | — | ❌ 漏洞已修复，不可用 |

### 判定条件

1. `cat /proc/version` 必须是 `6.6.89-android15-8-gb57af212129c`
2. 漏洞未被厂商回移补丁（部分 6.6.x 厂商构建会 backport 修复，以工具预检结果为准）

> **PD2405 有两个不同的内核，别搞混**：
> - Android 15 的 `15.0.21.8.W10` 是 `6.6.30`（`g24ffe62b0a0e`），与 b57 模块不匹配，
>   `-Force` 无效，必须按上游流程自己生成 profile（上游 issue #2 有该构建的实测记录，
>   且需要走 Shizuku 路径）
> - 本教程覆盖的是 Android 16 的 `16.1.22.2.W10`（`6.6.89` b57）

> 升级系统前先确认内核构建号；b57 消失或被回移修复后，本教程失效。

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

> **PD2405 必须带 `-Force`**（上游机型模块只认 PD2415），原因见「踩坑 1」。
> PD2415 的官方已验证构建不需要加。

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
| 8 | 重启后开屏广告回来了 | 检查 StevenBlock 模块 hosts，必要时重跑 `adblock_zqxy.sh` |

---

## 七、可选：趣智校园去广告

使用前提：root 已恢复。整条链路是「抓包定位域名 → 静态核对 → hosts 拦截 → 清缓存」。

### 1. 抓包定位广告域名

App 不一定走 VPN，直接抓真实网卡（移动流量通常是 `ccmni1`）：

```powershell
adb push scripts\capture_pcap.sh /data/local/tmp/capture_pcap.sh
adb shell su -c "sh /data/local/tmp/capture_pcap.sh 30 /data/local/tmp/capture.pcap ccmni1"
adb pull /data/local/tmp/capture.pcap
```

然后解析 DNS 查询与 TLS SNI：

```powershell
python scripts\pcap_parse.py capture.pcap
```

只抓到了 IP、没有域名时，说明流量走了 QUIC（UDP 443），需要按 IP 反查。

### 2. 静态扫描 APK（辅助）

```powershell
python scripts\apk_scan.py app.apk
```

加固应用的 dex 是加密的，通常扫不到东西，以抓包结果为准。

### 3. 写入拦截规则

```powershell
adb push scripts\adblock_zqxy.sh /data/local/tmp/adblock_zqxy.sh
adb shell su -c "sh /data/local/tmp/adblock_zqxy.sh"
```

脚本会幂等写入三个位置：

| 位置 | 作用 |
| --- | --- |
| `/system/etc/hosts` | 立即生效，全局共享 |
| `/data/adb/modules/stevenblock/system/etc/hosts` | 模块持久化，重启后自动挂载 |
| `/data/adb/stevenblock/rules/block.list` | 模块规则列表 |

注意 hosts 是**按域名精确匹配**，不覆盖子域，子域要逐条写。

### 4. 清理广告素材缓存

```powershell
adb push scripts\clear_ad_cache.sh /data/local/tmp/clear_ad_cache.sh
adb shell su -c "sh /data/local/tmp/clear_ad_cache.sh"
```

缓存会先备份到 `/data/local/tmp/zqxy_adcache_backup`，需要时可手动恢复。
只拦域名不清缓存，本地已缓存的广告仍会显示。

### 5. 界面定位推广位

```powershell
adb shell uiautomator dump /sdcard/ui.xml
adb pull /sdcard/ui.xml
python scripts\ui_dump.py ui.xml adv
```

用 resource-id 判断内容来源：`task_adv_channel_*`、`item_activity_*` 这类是
App 自有运营位，由业务接口下发，hosts 去不掉。

已知限制：

- 只能拦第三方广告 SDK（TopOn、Pangle、GDT、Sigmob、YFAds、BeiZi、京东联盟等）
- App 内自有运营位（横幅、返利频道）无法通过 hosts 去除，原因见
  [docs/troubleshooting.md 第 9 条](docs/troubleshooting.md)

---

## 八、工具与脚本

完整清单（版本、许可证、官方来源、SHA256）见 [tools/README.md](tools/README.md)。

| 文件 | 说明 |
| --- | --- |
| `scripts/capture_pcap.sh` | 设备端抓包（DNS + TLS/QUIC） |
| `scripts/pcap_parse.py` | 解析 pcap 中的域名 |
| `scripts/apk_scan.py` | 静态扫描 APK 的广告 SDK 与域名 |
| `scripts/ui_dump.py` | 解析 uiautomator dump，定位广告控件 |
| `scripts/adblock_zqxy.sh` | 90+ 广告域名 hosts 拦截 |
| `scripts/clear_ad_cache.sh` | 广告缓存备份清理 |

上游工具自身的代码问题另见 [docs/upstream-issues.md](docs/upstream-issues.md)：
v1.3.5 的 STAGE0 内核门禁在 `-Force` 路径下不生效（默认 `win_offs_b57.json`
缺 `kernel_release` 字段），已修复并发布修复版资产。

### GhostLock-X200 两个资产

| 资产 | 说明 | SHA256 |
| --- | --- | --- |
| `ghostlock-x200-root-v1.3.5-stage0fix.zip` | **推荐**：上游 v1.3.5 + STAGE0 门禁修复（只改一个 JSON 字段） | `2A368F6FF8FAC57ECDCC34ED837273A3C20C9837E061AFDE46471220277E5BF7` |
| `ghostlock-x200-root-v1.3.5.zip` | 上游原样，逐字节备份，未打补丁 | `0189A9ABBC461E3159C10B0FB6A09C07F415BAD1E5FF57991F7E381648231446` |

上游仓库 [xiaohj233/ghostlock-x200-root](https://github.com/xiaohj233/ghostlock-x200-root)
（Apache-2.0）。修复版与上游包逐条目比对：100 个条目，只有
`tools/offset_tools/win_offs_b57.json` 不同（新增 1 行 `kernel_release`）。

```powershell
# 下载后校验
Get-FileHash .\ghostlock-x200-root-v1.3.5-stage0fix.zip -Algorithm SHA256
```

已经有原版包时，也可以直接打补丁（幂等，自带验证）：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\patch_ghostlock.ps1 -ToolDir <解压后的 ghostlock-x200-root-main>
```

本仓库不含任何真机数据：没有 pcap、日志、截图、UI dump，也没有设备序列号、
IP、账号或手机号。

---

## 九、不要再做的事

以下操作已在真机上验证会导致 root 失效，且无法通过简单操作恢复：

1. **不要执行 `svc power reboot userspace`**：vivo 系统不支持。
2. **不要执行 `ksud soft-reboot`**：会导致 `su`、`ksud` 失效，只能重跑 GhostLock。
3. **不要在临时 root 上安装 LSPosed / Vector**：Zygisk 模块需要 zygote 启动时注入，而每次 zygote 重启都会打断 GhostLock 会话，形成死循环。
4. **不要点 KernelSU 管理器里的「卸载」或「安装」**：可能触发移除 root 或重装内核模块。
5. **不要升级系统**：内核达到 `6.6.140` 后漏洞被修复。

---

## 十、免责声明

本项目仅用于个人设备的安全研究与技术学习。临时 root 会降低设备安全性，
使用前请自行评估风险。因操作导致的设备异常、数据丢失或账号问题，由使用者自行承担。
请遵守当地法律法规与相关服务条款。

---

## 十一、参考

- GhostLock-X200 v1.3.5（Apache-2.0）：[上游仓库](https://github.com/xiaohj233/ghostlock-x200-root) / [v1.3.5 Release](https://github.com/xiaohj233/ghostlock-x200-root/releases/tag/v1.3.5)
- CVE-2026-43499 / IonStack：https://nebusec.ai/research/ionstack-part-2
- KernelSU：https://kernelsu.org/
- StevenBlock：https://github.com/Magisk-Modules-Alt-Repo/StevenBlock
- Zygisk Next：https://github.com/Dr-TSNG/ZygiskNext
