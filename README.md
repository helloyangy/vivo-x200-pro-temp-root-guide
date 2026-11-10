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

### 5. 可选：启用 Zygisk / Vector

需要 LSPosed / Vector / 任何 Zygisk 模块时，root 恢复后**必须再重启一次 zygote**：

```powershell
adb shell su -c "setprop ctl.restart zygote"
```

约 30 秒后，Vector 管理器从「未激活」变成「已激活」。

原理：Zygisk 只能在 zygote 刚启动的那一瞬间被注入，而 zygote 总是比 root 先起来
（本机实测早 8 分钟以上）。`root.ps1` 的 STAGE8 已经自动执行 `ksud services`，
把 `zygiskd`、`vectord` 拉起来了，但 zygote 已经跑过，所以只差这一步重启。

验证：

```powershell
adb shell "pidof zygote64"
# 例如输出 21566

adb shell su -c "cat /proc/21566/maps" | Select-String zygisk
```

本机实测：重启前 0 处命中，重启后 6 处，包含
`/data/adb/modules/zygisksu/lib64/libzygisk.so` 与
`/data/adb/modules/zygisk_vector/zygisk/arm64-v8a.so`。

Vector 管理器安装（模块目录里自带 APK）：

```powershell
adb shell su -c "pm install -r /data/adb/modules/zygisk_vector/manager.apk"
```

查看框架状态（命令行）：

```powershell
adb shell su -c "/data/adb/modules/zygisk_vector/cli status"
adb shell su -c "/data/adb/modules/zygisk_vector/cli modules ls"
adb shell su -c "/data/adb/modules/zygisk_vector/cli log cat"
```

> 这一步只重启 Android 框架，**内核不重启**：实测 `boot_id` 不变，`su` 仍是 `uid=0`，
> 不需要重跑提权脚本。屏幕会黑几秒到几十秒、所有 App 被关闭，属正常现象。
> 它和 `ksud soft-reboot` 不是一回事，后者会破坏临时 root 会话（见踩坑 5）。

---

## 五、日常使用规则

**每次重启手机后，root 都会失效，必须重跑一次提权脚本。**

建议流程：

1. 开机后等待 1-2 分钟，让系统后台任务稳定
2. 运行 `root.ps1 -Force`
3. 看到 `ALL STAGES PASS` 后再使用需要 root 的功能
4. 需要 Zygisk / Vector 时，再执行 `adb shell su -c "setprop ctl.restart zygote"`

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
| 7 | Vector 管理器显示「未激活」 | root 后必须再执行一次 `setprop ctl.restart zygote`，见第四节第 5 步 |
| 8 | 重启/重跑提权后开屏广告回来了 | 检查 `block.list` 与 hosts 挂载，必要时重跑 `adblock_all.sh --apply` |

---

## 七、可选：全局开屏广告拦截（所有 App）

> 前提：root 已恢复。**hosts 本来就是全局生效的**，所以这一节不再限定趣智校园。

### 0. 为什么原来「只针对趣智校园」

原方案的机制（hosts 拦截）对所有 App 一视同仁，所谓「只针对趣智校园」其实只体现在两处：

1. 域名清单是按趣智校园抓包得到的 90 多个域名；
2. 缓存清理脚本写死了 `com.klcxkj.zqxy`。

所以改成全局**不需要动 root 链、不需要改系统分区、不需要重启**，只需要把清单
换成覆盖主流广告 SDK 的通用集合，并让规则写进模块的规则源。

当前设备实测：StevenBlock 把 7.7 万行的 hosts 以 bind mount 挂到 `/system/etc/hosts`，
文件头写明「手动编辑会被覆盖」，因此**真正的规则源是**
`/data/adb/stevenblock/rules/block.list`。全局版同时做两件事：

| 写入位置 | 作用 |
| --- | --- |
| `/data/adb/stevenblock/rules/block.list` | 规则源，模块重建 hosts 或换列表后依然保留 |
| `/system/etc/hosts`（bind mount，非真实 /system） | 当前会话立即生效，**零重启** |

### 覆盖范围与边界（先读这个）

| 开屏广告类型 | 能否去除 | 说明 |
| --- | --- | --- |
| 第三方广告 SDK 开屏（穿山甲、优量汇、快手、百度、Sigmob、TopOn、BeiZi、厂商联盟等） | ✅ | hosts 拦截，覆盖绝大多数 App |
| App 自有开屏（与登录、首页等业务接口共用域名） | ❌ | hosts 无法区分广告与业务，拦了会破坏 App |
| 已下载到本地的开屏素材 | ⚠️ | 需按需清一次缓存，之后不再新增 |
| 自带 DoH / QUIC 直连 IP 的请求 | ❌ | 绕过系统 hosts |
| App 内运营位（横幅、返利卡片） | ❌ | 见 [踩坑 9](docs/troubleshooting.md) |

本机实测 `settings get global private_dns_mode` 为 `off`，系统 DNS 走明文查询，
hosts 才能生效。若把「私人 DNS」改成严格模式，或 App / Chrome 自带 DoH，
解析会绕开 hosts，拦截随之失效。

对 **App 自有开屏**，最稳妥的补充方案是**无障碍自动点「跳过」**（李跳跳 / 轻启动 / GKD 一类）：
不需要 root、不改系统文件、不注入 zygote，与临时 root 完全无冲突。本仓库不分发这类 APK。

> 不要用 root 轮询 `uiautomator dump` + `input tap` 来做全局跳过：需要高频调用 `su`、
> 可能误点到广告或支付按钮、Android 16 上 dump 也慢，风险远大于收益。

### 1. 规则清单

`scripts/ad_domains.txt` 是唯一清单，按 SDK 分组，收录 168 个**广告专用域名**，
宁可漏拦也不误拦。刻意不收录：业务接口顶点域名（`qq.com`、`baidu.com`、
`taobao.com`…）、推送通道（极光、个推、TPNS）、支付/登录域名、共享图片 CDN。
清单末尾有一组**默认注释禁用**的高风险域名，不要随手打开。

hosts 按域名**精确匹配**，不覆盖子域，所以子域必须逐条列出。

### 2. 本地静态校验（不连设备）

```powershell
python scripts\check_ad_domains.py scripts\ad_domains.txt
# 可选：先从设备导出 hosts 统计覆盖率
adb exec-out "cat /system/etc/hosts" > hosts.txt
python scripts\check_ad_domains.py scripts\ad_domains.txt --hosts hosts.txt
```

校验格式、重复、危险域名、与 `allow.list` 的冲突；有问题退出码为 1。

### 3. 推送 + dry-run（只读，务必先跑）

```powershell
adb push scripts\ad_domains.txt /data/local/tmp/ad_domains.txt
adb push scripts\adblock_all.sh /data/local/tmp/adblock_all.sh
adb shell su -c "sh /data/local/tmp/adblock_all.sh"
```

预览会打印待新增条数、示例域名、挂载状态、规则上限，**不写入任何文件**。
脚本默认就是 dry-run，只有显式 `--apply` 才写入。

### 4. 应用

```powershell
adb shell su -c "sh /data/local/tmp/adblock_all.sh --apply"
```

脚本的安全边界（针对临时 root 专门设计）：

- 只写 StevenBlock 的 bind mount 文件；若 `/system/etc/hosts` **不是** bind mount，直接中止，绝不写真实系统分区
- 不重启、不软重启、不 force-stop、不 `pm clear`、不动 zygote、不改 App 业务数据
- 写入前整份备份到 `/data/local/tmp/adblock_all_backup/<时间戳>/`
- 幂等：已存在的规则不重复追加；自动补 hosts 尾换行；逐条校验，失败自动还原
- 拒绝拦截业务/推送/支付域名；规则总数超过 StevenBlock 上限 1000 条直接中止

### 5. 验证与回滚

```powershell
# 再跑一次 dry-run，应显示「待新增 0 条」
adb shell su -c "sh /data/local/tmp/adblock_all.sh"

# 一键还原到上一次应用前的状态（备份不会被删除）
adb shell su -c "sh /data/local/tmp/adblock_all.sh --rollback"
```

生效**无需重启**；个别 App 有 DNS 缓存，开关一次飞行模式或重开该 App 即可。
临时 root 下千万不要为了「让规则生效」去重启手机——重启会丢 root，得重跑 GhostLock。

### 6. 清理已缓存的开屏素材（按需）

`clear_ad_cache.sh` 已改为可指定任意包名，默认 dry-run，只移动白名单里的
广告 SDK 缓存目录到带时间戳的备份，绝不 `rm -rf`：

```powershell
adb push scripts\clear_ad_cache.sh /data/local/tmp/clear_ad_cache.sh
adb shell su -c "sh /data/local/tmp/clear_ad_cache.sh"                       # 预览趣智校园
adb shell su -c "sh /data/local/tmp/clear_ad_cache.sh --apply"               # 执行趣智校园
adb shell su -c "sh /data/local/tmp/clear_ad_cache.sh --apply com.xxx.yyy"   # 指定其他 App
```

一次只传确实需要的包，不要对全部 App 批量 `force-stop`。

### 7. 发现某个 App 还有开屏广告

整条链路仍是「抓包定位 → 静态核对 → 补清单 → dry-run → apply」：

```powershell
adb push scripts\capture_pcap.sh /data/local/tmp/capture_pcap.sh
# 第 4 个参数传包名：脚本会先 force-stop 再显式启动，专门抓冷启动头几秒的请求
adb shell su -c "sh /data/local/tmp/capture_pcap.sh 25 /data/local/tmp/xhs.pcap ccmni1 com.xingin.xhs"
adb exec-out "su -c 'cat /data/local/tmp/xhs.pcap'" > xhs.pcap
python scripts\pcap_parse.py xhs.pcap --top 30

python scripts\apk_scan.py app.apk          # 加固应用通常扫不到，以抓包为准
adb shell uiautomator dump /sdcard/ui.xml  # 界面定位：区分第三方 SDK 与自有运营位
adb pull /sdcard/ui.xml
python scripts\ui_dump.py ui.xml adv
```

解析器会同时打印 IPv4/IPv6 包数、DNS 查询数和 UDP 443 数。
若「UDP 443 远多于 DNS 查询」，说明流量走 QUIC/HTTP3 或 App 内置 DNS，
域名不可见且可能绕过 hosts；只抓到 IP 时按 IP 反查。
确认是广告专用子域后追加到 `ad_domains.txt` 对应分组，重新校验并 apply。

> 冷启动抓包会 `force-stop` 指定 App（只结束进程、不删数据、不重启），
> 脚本会校验进程是否真的起来了，失败会明确提示，不会悄悄产出一份空 pcap。

> 旧版 `scripts/adblock_zqxy.sh`（趣智校园专用、90+ 域名）**保留不动**，
> 作为最小可用回退路径，不推荐使用。

已知限制：

- 只能拦第三方广告 SDK（TopOn、Pangle、GDT、Sigmob、YFAds、BeiZi、京东联盟等）
- App 内自有运营位（横幅、返利频道）无法通过 hosts 去除，原因见
  [docs/troubleshooting.md 第 9 条](docs/troubleshooting.md)；
  激活 Vector 后可用界面隐藏类模块处理（见第四节第 5 步）

---

## 八、工具与脚本

完整清单（版本、许可证、官方来源、SHA256）见 [tools/README.md](tools/README.md)。

| 文件 | 说明 |
| --- | --- |
| `scripts/ad_domains.txt` | **全局**广告 SDK 域名清单（168 条，按平台分组，含默认禁用的高风险项） |
| `scripts/check_ad_domains.py` | 本地静态校验：格式、重复、危险域名、allow.list 冲突 |
| `scripts/adblock_all.sh` | **全局**拦截主脚本：dry-run / `--apply` / `--rollback`，带备份与校验 |
| `scripts/clear_ad_cache.sh` | 指定包名的广告素材缓存备份清理（默认 dry-run，只移动不删除） |
| `scripts/capture_pcap.sh` | 设备端抓包（DNS + TLS/QUIC）；第 4 个参数可传包名做**冷启动抓包** |
| `scripts/pcap_parse.py` | 解析 pcap 中的域名；支持 IPv4/IPv6、修正 TLS SNI 扩展解析 |
| `scripts/apk_scan.py` | 静态扫描 APK 的广告 SDK 与域名 |
| `scripts/ui_dump.py` | 解析 uiautomator dump，定位广告控件 |
| `scripts/adblock_zqxy.sh` | 旧版：趣智校园专用 90+ 域名拦截，仅作回退保留 |
| `scripts/patch_ghostlock.ps1` | 工具包统一加固入口：补 `kernel_release` + 门禁 fail-closed，幂等、保留编码、验证失败返回非零 |
| `patches/ghostlock-v1.3.5-stage0-*.patch` | 两个可审计补丁（面向上游 Git 的 LF 原文） |

上游工具自身的代码问题另见 [docs/upstream-issues.md](docs/upstream-issues.md)：
v1.3.5 的 STAGE0 内核门禁在 `-Force` 路径下有**两处**静默失效
（默认 `win_offs_b57.json` 缺 `kernel_release`；`/proc/version` 读取失败时
门禁因短路被跳过），均已在本仓库维护的修复版工具包中彻底修复。

### GhostLock-X200 三个资产

| 资产 | 说明 | SHA256 |
| --- | --- | --- |
| `ghostlock-x200-root-v1.3.5-stage0fix-v2.zip` | **推荐（v1.2.0 起）**：完整加固 = 补 `kernel_release` + STAGE0 门禁改为 fail-closed | `16708CC627B2A00287ED465B0B547780A4A11D1E77CA41232C0DB4ACB93FD6C3` |
| `ghostlock-x200-root-v1.3.5-stage0fix.zip` | v1.1.0 最小修复：只补 `kernel_release`，读不到内核版本时门禁仍会静默跳过 | `2A368F6FF8FAC57ECDCC34ED837273A3C20C9837E061AFDE46471220277E5BF7` |
| `ghostlock-x200-root-v1.3.5.zip` | 上游原样，逐字节备份，未打补丁 | `0189A9ABBC461E3159C10B0FB6A09C07F415BAD1E5FF57991F7E381648231446` |

- v2 资产：[v1.2.0 Release](https://github.com/helloyangy/vivo-x200-pro-temp-root-guide/releases/tag/v1.2.0)；
  最小修复版见 [v1.1.0](https://github.com/helloyangy/vivo-x200-pro-temp-root-guide/releases/tag/v1.1.0)，
  原版见 [tools-v1.3.5](https://github.com/helloyangy/vivo-x200-pro-temp-root-guide/releases/tag/tools-v1.3.5)
- 上游仓库 [xiaohj233/ghostlock-x200-root](https://github.com/xiaohj233/ghostlock-x200-root)（Apache-2.0）
- v2 与上游包逐条目比对：100 个条目、顺序一致，**只有 2 个文件内容不同**：
  `tools/offset_tools/win_offs_b57.json` 与 `tools/scripts/root_full_permissive_restore.ps1`

```powershell
# 下载后校验
Get-FileHash .\ghostlock-x200-root-v1.3.5-stage0fix-v2.zip -Algorithm SHA256
```

已有原版包或 v1.1.0 修复包时，用统一入口升级（幂等；自动保持源文件的
UTF-8 BOM 与 LF/CRLF，替换前后都做语法解析，验证失败返回非零）：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\patch_ghostlock.ps1 -ToolDir <解压后的 ghostlock-x200-root-main>
```

`patches/` 下两个补丁面向**上游 Git 仓库的 LF 原文**，用于审计或 clone 后应用；
Release zip 里的主链脚本是 CRLF，直接 `git apply` 会失败 —— 解压 zip 的场景请用上面的脚本。

本仓库不含任何真机数据：没有 pcap、日志、截图、UI dump，也没有设备序列号、
IP、账号或手机号。

---

## 九、不要再做的事

以下做法已在真机上验证有问题或会让 root 失效，务必避开：

1. **不要执行 `svc power reboot userspace`**：vivo 系统不支持。
2. **不要执行 `ksud soft-reboot`**：会导致 `su`、`ksud` 失效，只能重跑 GhostLock。
3. **不要在装完 Zygisk / Vector 后跳过重启 zygote**：模块装了不等于生效。root 恢复后必须执行一次 `setprop ctl.restart zygote`，否则管理器一直显示「未激活」。这一步只重启框架，不会掉 root（已实测）。
4. **不要点 KernelSU 管理器里的「卸载」或「安装」**：可能触发移除 root 或重装内核模块。
5. **不要升级系统**：内核达到 `6.6.140` 后漏洞被修复。
6. **不要为了让广告规则生效而重启**：hosts 改动当场生效，重启只会白白丢掉临时 root。

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
