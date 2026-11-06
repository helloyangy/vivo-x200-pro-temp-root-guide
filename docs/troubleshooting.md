# 踩坑与排错记录

> 全部结论均来自 vivo X200 Pro（PD2405，Android 16，固件 16.1.22.2.W10）真机实测。

---

## 1. 脚本提示「机型未精确匹配」并退出

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

## 7. LSPosed / Vector / Zygisk 模块不生效

### 现象

安装了 Zygisk Next（`zygisksu` 1.5.2）、Vector 2.2 后，模块不加载；
或者安装后重启，root 直接失效。

### 原因

这是机制性冲突，不是配置问题：

1. Zygisk 模块必须在 **zygote 启动时**注入。
2. GhostLock 的 root 在 zygote 重启（软重启、整机重启）后失效。
3. 重跑 GhostLock 后，zygote 已经启动完毕，Zygisk 不会再注入。
4. 如果再重启 zygote 来加载 Zygisk，root 又会失效。

形成死循环。

### 结论

在 GhostLock 临时 root 环境下，**不要尝试 LSPosed / Vector / 任何 Zygisk 模块**。
包括 LocationSpoofer、虚拟定位、界面级去广告模块，全部不可行。

需要这类模块，只能使用永久 root（解锁 Bootloader / 官方 KernelSU 刷入）。

---

## 8. 重启后广告拦截失效 / hosts 行为

### 机制

本教程的去广告方案使用两层 hosts：

| 位置 | 说明 | 重启后 |
| --- | --- | --- |
| `/data/adb/modules/stevenblock/system/etc/hosts` | StevenBlock 模块 hosts | 自动挂载，持久 |
| `/system/etc/hosts` | 直接写入的系统 hosts | 可能被还原 |

### 结论

- 正常情况下，StevenBlock 模块会在开机时把广告规则挂载回去，无需重跑。
- 如果开屏广告回来，先检查：

```powershell
adb shell su -c "grep -c yfanads /system/etc/hosts"
adb shell su -c "grep -c yfanads /data/adb/modules/stevenblock/system/etc/hosts"
```

- 缺失时重跑：

```powershell
adb shell su -c "sh /data/local/tmp/adblock_zqxy.sh"
```

### 注意

- hosts 是**按域名精确匹配**，不覆盖子域，必须逐个列子域。
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

清理脚本见 `scripts/clear_ad_cache.sh`。

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

这类内容只能通过 Xposed 类框架做界面级隐藏，
而 Xposed/Zygisk 在本机临时 root 下不可行（见第 7 条）。

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

# 7. 检查广告规则
adb shell su -c "grep -c yfanads /system/etc/hosts"
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
| 广告回来 | 检查 StevenBlock hosts，重跑 adblock 脚本 |
| 需要软重启 | 不要做，直接整机重启 + 重跑 |
| 想装 LSPosed | 不要做，机制冲突 |
