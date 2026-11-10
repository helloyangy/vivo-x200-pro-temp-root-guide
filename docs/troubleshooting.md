# 踩坑与排错记录

> 全部结论均来自 vivo X200 Pro（PD2405，Android 16，固件 16.1.22.2.W10）真机实测。

---

## 1. 脚本提示「机型未精确匹配」并退出（PD2405）

### 现象

```text
[!] 同族模块命中 (family): vivo X200 (PD2415) 未精确匹配, 需重新生成偏移
== GhostLock-X200 机型可行性预检 ==
  [FAIL] 无法识别素材类型 (other)
[X] 机型模块生成失败, 请检查素材/依赖后重试
```

### 原因

GhostLock-X200 v1.3.5 随包机型模块是 **vivo X200（PD2415）**，
而本机是 **vivo X200 Pro（PD2405）**。脚本按 `profile` 精确匹配机型，
匹配失败后会要求重新生成偏移，甚至会把 `root.ps1` 本身当成固件素材。

### 解决

设备内核构建号与随包模块一致（`b57af212129c`），可以直接强制使用随包偏移：

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\root.ps1 -Force
```

`-Force` 会跳过机型匹配，输出：

```text
[!] -Force: 跳过机型匹配, 强制使用 devices\x200_b57\device.json 直接运行
```

### 适用范围

`-Force` 的前提是**内核构建号与随包模块一致**（`6.6.89-…-gb57af212129c`）。

PD2405 还有 Android 15 的 `15.0.21.8.W10`，内核是 `6.6.30`（`g24ffe62b0a0e`），
偏移完全不同，`-Force` 会带着错误的地址跑，属于 panic 风险最高的场景。
这种构建必须按上游流程离线生成自己的 profile，不能套用本教程。

---

## 2. STAGE4 因 `loadavg` 过高中止

### 现象

```text
STAGE4 QUIESCE ABORT: 设备负载过高 (loadavg=22.92), 写链存在 kernel_panic 风险, 已停止
  (STAGE1/2 已做的 permissive/kptr 改动重启即恢复; 请关闭后台应用 (QQ 等) 或等设备空闲后重跑)
```

或者告警后继续：

```text
STAGE4 QUIESCE WARN: loadavg=17.42 60s 内未静默 (设备后台负载, 如 QQ MSF), 继续
```

### 原因

脚本的 STAGE4/5 写链在设备忙时容易 miss，极端负载下可能触发 kernel panic。
脚本注释写明：**loadavg <= 16 时 7/7 通过**。

### 解决

1. 关闭后台大应用：

```powershell
adb shell "am force-stop com.tencent.mm; am force-stop com.tencent.mobileqq; am force-stop com.ss.android.ugc.aweme; am force-stop com.taobao.taobao"
```

2. 等待负载下降：

```powershell
adb shell cat /proc/loadavg
```

3. 重新运行 `root.ps1 -Force`。

注意：MTK 平台有大量常驻 D 状态内核线程（`hang_detect`、`wdtk-*`、`ccci_poll` 等），
load 可能长期停在 17-18，脚本会告警但继续，一般仍能成功。

---

## 3. 重启后 `su` 消失，root 不可用

### 现象

```text
/system/bin/sh: su: inaccessible or not found
```

KernelSU 管理器显示「未安装」。

### 原因

GhostLock 是**会话级临时 root**，root 只存在于当前内核内存中。
任何形式的冷启动都会让它失效，这是设计行为，不是故障。

### 解决

重跑一次 `root.ps1 -Force` 即可恢复，约 1-2 分钟。

---

## 4. `svc power reboot userspace` 不支持

### 现象

```text
Failed to reboot: Attempted userspace reboot on a device that doesn't support it
```

### 原因

vivo 系统禁用了 Android 的 userspace reboot 功能。

### 结论

不要尝试。直接整机重启，然后重跑 GhostLock。

---

## 5. `ksud soft-reboot` 后 root 会话失效（重要）

### 背景

网上有资料说「软重启（soft reboot）不会丢 root，因为不重启内核」。
这条对 Magisk 永久 root 成立，但**对 GhostLock 临时 root 不成立**。

### 实测过程

```powershell
adb shell su -c "/data/adb/ksud soft-reboot"
```

重启后：

- `/proc/uptime` 连续（内核确实没重启）
- `/proc/modules` 中 `kernelsu` 仍是 `Live`
- 但 `/system/bin/su` 消失
- `ksud` 变成僵尸进程 `Z [ksud]`
- KernelSU 管理器显示「未安装」
- 用 `ksud` 的 `late-load`、`post-fs-data`、`services` 都无法恢复
- 点击管理器的「越狱」按钮也无法恢复

### 原因

GhostLock 的提权链在冷启动（包括软重启的 userspace 初始化）时依赖完整的 boot 流程。
软重启不是完整 boot，KernelSU 的 userspace 服务和挂载没有重新建立，
即使内核模块还在，root 通道也不可用。

### 结论

**不要执行 `ksud soft-reboot`。** 需要重启时直接整机重启，然后重跑 GhostLock。

---

## 6. KernelSU 管理器显示「未安装」

### 现象

`su -c id` 返回 `uid=0(root)`，内核模块 `Live`，但管理器主页显示「未安装」。

### 原因

管理器的「管理器身份」是通过签名验证注册到内核模块的，不写在 `.allowlist` 里。
以下操作会破坏这个注册状态：

- `pm clear me.weishu.kernelsu`（清除管理器数据）
- 软重启
- 某些情况下重跑提权链

`.allowlist` 里只有被授权的普通 App（例如 `com.termux`、`com.zacharee1.systemuituner`），
**管理器自己不在这个列表里**，这是正常的。

### 解决

不要点管理器里的「卸载」或「安装」。用重装管理器 APK 的方式修复：

```powershell
# 1. 提取原版 APK（root 可用时）
adb exec-out su -c "cat $(adb shell pm path me.weishu.kernelsu | sed 's/package:/ /')" > kernelsu_manager.apk

# 2. 卸载（只删管理器 App，不影响 /data/adb/ksu、模块和 root）
adb shell pm uninstall me.weishu.kernelsu

# 3. 重装
adb install kernelsu_manager.apk
```

重装后打开管理器，通常会恢复显示「工作中 <LKM>」。

### 不推荐

- 不要执行 `pm clear me.weishu.kernelsu`，它会清除管理器的注册状态。
- 不要用 `ksud debug set-manager`：本机内核未启用 `CONFIG_KSU_DEBUG`，会报错：

```text
Error: CONFIG_KSU_DEBUG is not enabled
```

---

## 7. Vector 管理器显示「未激活」/ Zygisk 模块不生效（重要，已解决）

### 现象

Zygisk Next（`zygisksu` 1.5.2）与 Vector 2.2 都装好了，
`zygiskd status` 也能连上服务、能识别 `zygisk_vector`，但：

- Vector 管理器主页显示「未激活」
- Vector 日志为空
- 装了 Xposed 模块也不生效

### 早期误判

最初把这条记成「机制性冲突、不可行」，这是错的。
实际只要多执行一步 `setprop ctl.restart zygote` 就能解决，且不会掉 root。

### 真实原因

Zygisk 只能在 **zygote 刚被 exec 出来的那一瞬间**注入，这个窗口过期就没有第二次。

本机实测时间线：

| 时刻 | 事件 |
| --- | --- |
| 13:46 | 设备重启 |
| ~13:47 | zygote64 启动 |
| 13:55 | root 脚本成功 |
| 13:58 | `ksud services` 拉起 `zygiskd` / `vectord` |

zygote 比 root 早 8 分钟以上。`zygiskd` 就绪时注入窗口早已关闭。

判断方法（重启前）：

```powershell
adb shell "pidof zygote64"
adb shell su -c "cat /proc/<上面的PID>/maps" | Select-String zygisk
```

命中 0 处 = 没有注入；此时管理器必然显示「未激活」。

### 解决

root 恢复后，再重启一次 zygote：

```powershell
adb shell su -c "setprop ctl.restart zygote"
```

约 30 秒后重新打开 Vector 管理器，状态变为「已激活」。

### 实测验证

```text
执行前：zygote64 PID 1060，maps 3241 行，zygisk 命中 0
执行后：zygote64 PID 21566，zygote 已重启
        maps zygisk 命中 6 处：
          /data/adb/modules/zygisksu/lib64/libzygisk.so
          /data/adb/modules/zygisk_vector/zygisk/arm64-v8a.so
        新增进程 zn-nsdaemon-zygote
root：   uid=0 保持不变
boot_id：a2ca9406-... 未变化（内核没有重启）
Vector： 「未激活」→「已激活」
```

### 与 `ksud soft-reboot` 的区别

| 操作 | 内核 | root | Zygisk |
| --- | --- | --- | --- |
| `setprop ctl.restart zygote` | 不重启（`boot_id` 不变） | 保留 | 可注入 |
| `ksud soft-reboot` | 不重启 | **失效** | — |

所以只有前者可用（见第 5 条）。

### 每次开机都要重做

zygote 永远比 root 先启动，所以每次冷启动后都要：

```text
root.ps1 -Force  →  setprop ctl.restart zygote
```

`root.ps1` 的 STAGE8 会自动跑 `ksud services`，`zygiskd` / `vectord` 不需要手动启动。

### 查看 Vector 的两种方式

命令行：

```powershell
adb shell su -c "/data/adb/modules/zygisk_vector/cli status"
adb shell su -c "/data/adb/modules/zygisk_vector/cli modules ls"
adb shell su -c "/data/adb/modules/zygisk_vector/cli scope"
adb shell su -c "/data/adb/modules/zygisk_vector/cli log cat"
```

管理器 App（模块目录自带 APK）：

```powershell
adb shell su -c "pm install -r /data/adb/modules/zygisk_vector/manager.apk"
```

---

## 8. 重启后广告拦截失效 / hosts 行为

### 机制（真机实测，v1.0 模块与旧理解不同）

StevenBlock v1.0 不是简单往 hosts 里追加几行，它是一个完整的 hosts 管理器：

| 位置 | 说明 | 重启后 |
| --- | --- | --- |
| `/data/adb/stevenblock/rules/block.list` | **规则源**，自定义域名都在这里 | 保留，模块重建 hosts 时会重新编入 |
| `/data/adb/modules/stevenblock/system/etc/hosts` | 模块编译出的 7.7 万行 hosts | 保留 |
| `/system/etc/hosts` | 上述文件被 **bind mount** 到这个路径 | 依赖模块挂载 |

实测 `/proc/mounts` 中 `/system/etc/hosts` 是 `/dev/block/dm-63` 的 f2fs 文件挂载，
两个路径**指向同一个 inode**（`stat -Lc %d:%i` 可验证）。模块 hosts 文件头明确写着
`Managed by StevenBlock. Manual edits are overwritten.`，所以只往 hosts 追加、
不写 `block.list` 的规则，在模块重建或换列表后会丢失。

临时 root 还要注意：冷启动后 KernelSU LKM 未加载，模块的 `post-mount.sh` /
`service.sh` 不会自动跑，所以重跑 GhostLock 后需要确认 hosts 挂载是否恢复。

### 结论

- 全局规则以 `block.list` 为准，当前会话的即时生效靠写 bind mount 的 hosts：
  见 `scripts/adblock_all.sh`（默认 dry-run，`--apply` 才写入，`--rollback` 还原）。
- 如果开屏广告回来，按顺序检查：

```powershell
adb shell su -c "grep -c ' /system/etc/hosts ' /proc/mounts"   # 是否还是 bind mount
adb shell su -c "grep -c '^0.0.0.0 pangle.cn' /system/etc/hosts"
adb shell su -c "grep -cx 'pangle.cn' /data/adb/stevenblock/rules/block.list"
adb shell su -c "sh /data/local/tmp/adblock_all.sh"              # 预览，应显示待新增 0 条
```

- 挂载在但规则缺失，重跑一次即可，**不要重启**：

```powershell
adb shell su -c "sh /data/local/tmp/adblock_all.sh --apply"
```

- 若 `/system/etc/hosts` 不是 bind mount，脚本会主动中止，拒绝写真实系统分区；
  此时先重跑 GhostLock 让模块重新挂载，或临时用 `--rules-only` 只更新规则源。

### 注意

- hosts 是**按域名精确匹配**，不覆盖子域，必须逐个列子域。
- Android 16 上 `ndc resolver` 的 DNS 缓存刷新不可用，改 hosts 后个别已运行的 App
  可能仍用旧解析结果；开关一次飞行模式或重开 App 即可，无需重启。
- 广告 SDK 会缓存素材。只拦域名不清缓存，本地缓存的广告仍会展示。
- 缓存位置包括：

```text
cache/wind（实际是 Sigmob SDK 的缓存）
cache/beizi
cache/pangle_com.byted.pangle/tt_ad
cache/image_manager_disk_cache
files/tktp
files/anythink
files/BeiZi
files/sdm
```

清理脚本见 `scripts/clear_ad_cache.sh`（可指定包名，默认 dry-run，只移动不删除）。

---

## 9. App 内推广位无法用 hosts 去除

### 现象

开屏广告已去除，但主页仍有横幅、「每天赚点要花钱」返利卡片、活动卡片。

### 原因

抓包和 UI dump 确认这些内容由 App 自己的业务接口（`v3-api.china-qzxy.cn`）下发，
控件资源名是 `task_adv_channel_*`、`item_activity_*`，属于 App 自有运营位，
不是第三方广告 SDK。

hosts 按域名拦截，无法区分同一域名下的「广告接口」和「业务接口」；
拦掉整个域名会导致 App 无法使用。

### 结论

这类内容只能通过 Xposed 类框架做界面级隐藏。
按第 7 条激活 Vector 后，可以用界面隐藏类模块处理。

### 推广到「全部 App 的自有开屏」

同样的道理适用于微博、知乎、视频类 App 的自有开屏：素材常与登录、首页等业务接口
共用同一个域名，hosts 无法区分「广告接口」和「业务接口」，拦掉整个域名 App 就不能用了。
`scripts/ad_domains.txt` 因此只收录广告平台专用域名，绝不收录业务顶点域名。

对这类开屏，可行且不伤手机的方案是**无障碍服务自动点「跳过」**
（李跳跳 / 轻启动 / GKD 一类）：不需要 root、不改系统文件、不注入 zygote，
与 GhostLock 临时 root 没有机制冲突。本仓库不分发这类 APK。

不建议用 root 自己写「轮询 `uiautomator dump` 找『跳过』再 `input tap`」的守护脚本：

- 需要高频调用 `su`，与第 11 条的建议冲突；
- `uiautomator dump` 在 Android 16 上慢且不稳定，容易点到已经变化的界面；
- 文本匹配不严谨时可能误点「立即打开」「授权」「支付」等按钮，风险不可控。

### 实例：小红书 9.50.0（2026-11-07 真机抓包）

用 `capture_pcap.sh 25 ... ccmni1 com.xingin.xhs` 抓冷启动，2,221 个包
（IPv4 1,917 / IPv6 304），解析出 24 个 TLS SNI 域名、0 个可见 DNS 查询、
1,001 个 UDP 443 包（其中 977 个去往同一个 IP，是 QUIC/HTTP3 长连接）。

- **没有任何第三方广告 SDK 域名**（Pangle / GDT / Sigmob / TopOn 全都没出现）
- 配置走业务接口：`edith.xiaohongshu.com`、`fe.xiaohongshu.com`、`as.xiaohongshu.com`
- 素材走自有 CDN：`ads-img-al.xhscdn.com`、`sns-na-i*.xhscdn.com`、`sns-avatar-qc.xhscdn.com`
- 同一份抓包里还有 `b-gtc.getui.net`、`sdk-open-phone.getui.com`（个推推送）和
  `nrt-stsdk.vivo.com.cn`（vivo SDK）——**这些绝不能拦**，否则通知会挂
- 本地还有开屏缓存：`files/splashAds`、`files/splashCptAdsConfig`、`files/ads_static_res`、
  `app_ads_splash_btn_bg/ads_splash_btn_res.zip`

所以这是典型的 App 自有开屏：配置与业务 API 共用域名，hosts 无法区分；
素材 CDN 的兄弟子域还承担着笔记和头像图片，拦了会破坏正常浏览。
即便只试探性地拦 `ads-img-al.xhscdn.com`（已作为**注释禁用**项记在清单末尾），
最多让图片加载失败变成「空白开屏」，配置仍然下发，开屏倒计时也不会消失；
而且主力流量走 QUIC 长连接，hosts 未必拦得到。清缓存同样无效——域名没被拦，
素材下次冷启动会重新下载。

结论：**hosts 管第三方 SDK 开屏，无障碍管自有开屏**，两者叠加才是「全部 App」的完整解，
而 hosts 这部分在本机临时 root 下已经可以零重启、可回滚地完成。
小红书这类 App 只能交给无障碍「跳过」工具，不要为了它去动业务域名。

---

## 10. 提权过程中 App 被关闭

### 现象

跑完脚本后发现微信、QQ、抖音等被关闭。

### 原因

为降低 loadavg，脚本运行前会执行 `am force-stop` 关闭大应用。

### 结论

数据不受影响，重新打开即可。

---

## 11. `su` 可能触发 vivo 检测

### 说明

GhostLock-X200 的文档提到：KernelSU 的 `su` 在某些场景可能触发 vivo 检测导致 panic，
因此工具默认提供 `rootcmd` 通道，不依赖 `su`。

但在本机实测中：

- `adb shell su -c` 正常可用
- `su -c id` 返回 `uid=0`
- 未观察到因 `su` 导致的 panic

如果遇到异常，优先使用工具自带命令，不要频繁高强度调用 `su`。

---

## 12. 推荐的完整恢复流程

手机重启后：

```powershell
# 1. 等待 1-2 分钟

# 2. 确认设备
adb devices

# 3. 关闭后台大应用（可选，降低负载）
adb shell "am force-stop com.tencent.mm; am force-stop com.tencent.mobileqq"

# 4. 跑提权
powershell.exe -ExecutionPolicy Bypass -File .\root.ps1 -Force

# 5. 验证
adb shell su -c id
adb shell /data/adb/ksud debug version

# 6. 检查 KernelSU 管理器是否显示「工作中 <LKM>」

# 7. 检查广告规则（预览，应显示待新增 0 条；必要时 --apply）
adb shell su -c "sh /data/local/tmp/adblock_all.sh"

# 8. 需要 Zygisk / Vector 时，再重启一次框架
adb shell su -c "setprop ctl.restart zygote"
```

---

## 13. 故障速查表

| 现象 | 处理 |
| --- | --- |
| 脚本退出在「机型未精确匹配」 | 加 `-Force` |
| STAGE4 ABORT loadavg | 关后台 App，等 1-2 分钟，重跑 |
| `su: inaccessible or not found` | 重启后正常现象，重跑 GhostLock |
| 管理器显示「未安装」 | 重装管理器 APK |
| 管理器点「安装」后异常 | 不要点，重跑 GhostLock |
| 广告回来 | 检查 hosts 挂载与 `block.list`，重跑 `adblock_all.sh --apply` |
| 想撤销全局拦截 | `adblock_all.sh --rollback`（自动还原到最近一次备份） |
| App 自带开屏仍在 | 属自有业务接口，hosts 去不掉，改用无障碍「跳过」类工具 |
| 需要软重启 | 不要做，直接整机重启 + 重跑 |
| 想装 LSPosed / Vector | 装完再执行 `setprop ctl.restart zygote` |
| Vector 显示「未激活」 | root 后执行 `setprop ctl.restart zygote`，重启前 maps 里 zygisk 为 0 |
