# 上游 GhostLock-X200 v1.3.5 代码核查

> 只记录**在代码里能直接证实**的问题。核查基于 v1.3.5 原始包（与上游 Release 逐字节相同）。

---

## 1. STAGE0 内核门禁在 `-Force` 路径下失效（重要）

### 代码

`tools/scripts/root_full_permissive_restore.ps1` 在第一次内核写之前有门禁：

```powershell
$winRelease = [string]$win.kernel_release
if ($winRelease -and $devVerRaw -and $devVerRaw -notlike ("*" + $winRelease + "*")) {
  Write-Output "STAGE0 GATE FAIL: 设备内核与 win_offs 不匹配"
  exit 1
}
```

### 问题

门禁依赖 `win_offs.json` 里的 `kernel_release` 字段，但随包的
`tools/offset_tools/win_offs_b57.json` **没有这个字段**：

```json
{
  "physmap_base": "0xffffff8000000000",
  "sym_offs": { ... },
  "w2host": { ... }
}
```

`$winRelease` 为空串 → `if ($winRelease -and ...)` 恒假 → 门禁直接跳过，且没有任何告警。

### 触发条件

`root.ps1 -Force` 不设置 `$GEN_WIN_OFFS`，因此不会向主链传 `-WinOffsPath`，
主链回落到默认的 `tools/offset_tools/win_offs_b57.json`，正好命中这个缺字段的文件。

- `devices/x200_b57/win_offs.json`（精确命中模块时使用）**有** `kernel_release`，门禁正常
- 生成新机型模块时 `offsets_auto.py package` 也会写入该字段，门禁正常
- 只有 `-Force` 这条路是空的

### 后果

`-Force` 的本意就是「跳过机型匹配硬跑」，而 PD2405 恰好有第二个内核构建
（Android 15 `15.0.21.8.W10` → `6.6.30` / `g24ffe62b0a0e`）。这类设备按
`-Force` 运行不会被门禁拦下，会带着 b57 偏移进入写链，属于 panic 风险最高的组合。

### 修复（v1.1.0 的最小修复，一行数据级改动）

在 `tools/offset_tools/win_offs_b57.json` 顶层加：

```json
{
  "kernel_release": "6.6.89-android15-8-gb57af212129c-abogki457297774-4k",
  "physmap_base": "0xffffff8000000000",
  ...
}
```

验证（无需连设备）：

```powershell
$w = Get-Content tools\offset_tools\win_offs_b57.json -Raw | ConvertFrom-Json
foreach ($dev in @(
  "6.6.89-android15-8-gb57af212129c-abogki457297774-4k",
  "6.6.30-android15-8-gb24ffe62b0a0e-abogki387229724-4k")) {
  if ($dev -notlike ("*" + $w.kernel_release + "*")) { "ABORT  $dev" } else { "PASS   $dev" }
}
```

预期：第一个 `PASS`，第二个 `ABORT`。

### 验证记录

用真实文件（不是模拟值）跑门禁表达式，结果：

| `win_offs_b57.json` 来源 | 本机 b57 内核 | PD2405 的 6.6.30 构建 |
| --- | --- | --- |
| 上游原样（`gate_active=False`） | `abort=False`（跳过） | `abort=False`（跳过） |
| 修复后（`gate_active=True`） | `abort=False`（放行） | `abort=True`（中止） |

真机侧核对：`adb shell cat /proc/version` 返回
`Linux version 6.6.89-android15-8-gb57af212129c-abogki457297774-4k ...`，
与写入的 `kernel_release` 完全一致，修复不会影响本机流程。

`root.ps1` 的 `-Force` 分支确认只有一条告警，不设置 `$GEN_WIN_OFFS`。
该变量只在初始化、机型模块精确命中、自动重建偏移这三处被赋值，且都在非 `-Force`
路径上，因此 `-Force` 时唯一的 `-WinOffsPath` 拼装点 `if ($GEN_WIN_OFFS)` 不成立，
主链回落到自带的 `tools/offset_tools/win_offs_b57.json`。

### 本仓库处理

**v1.1.0（最小修复，仅数据级）**

- 资产 `ghostlock-x200-root-v1.3.5-stage0fix.zip`
  （SHA256 `2A368F6FF8FAC57ECDCC34ED837273A3C20C9837E061AFDE46471220277E5BF7`）
  —— 与上游包逐条目比对：100 个条目，只有 `tools/offset_tools/win_offs_b57.json` 不同
- 补丁：[patches/ghostlock-v1.3.5-stage0-gate.patch](../patches/ghostlock-v1.3.5-stage0-gate.patch)
- 原始上游包 `ghostlock-x200-root-v1.3.5.zip` 继续保留作逐字节备份（SHA256 未变）

**v1.2.0（完整加固，见下节）**

- 新资产 `ghostlock-x200-root-v1.3.5-stage0fix-v2.zip`
  （SHA256 `16708CC627B2A00287ED465B0B547780A4A11D1E77CA41232C0DB4ACB93FD6C3`）
  —— 100 个条目、顺序不变，**只有 2 个文件内容不同**：
  `win_offs_b57.json` 与 `tools/scripts/root_full_permissive_restore.ps1`
- 新补丁：[patches/ghostlock-v1.3.5-stage0-failclosed.patch](../patches/ghostlock-v1.3.5-stage0-failclosed.patch)
- 统一入口 [scripts/patch_ghostlock.ps1](../scripts/patch_ghostlock.ps1) 同时应用两处修复

```powershell
powershell -ExecutionPolicy Bypass -File scripts\patch_ghostlock.ps1 -ToolDir <解压后的 ghostlock-x200-root-main>
```

### 脚本审查记录（v1.1.0 之后）

复查一键脚本时发现并已修掉三个会导致「假成功」的缺陷（均可复现）：

| 输入 | 旧脚本行为 | 后果 |
| --- | --- | --- |
| 文件首行有前导空白 | `-replace '^\{'` 不匹配，却仍打印 `patched` | 门禁仍失效，用户以为已修好 |
| 顶层 `kernel_release` 为空串 / 字段只在嵌套对象里 | 字符串匹配命中 → `already present, nothing to do` | 顶层仍为空，门禁跳过 |
| 顶层值写错 | 打印 `ABORT <正确内核> / PASS <错误内核>`，仍退出 0 | 结果反了却没有任何失败信号 |

根因是「用 `$raw -match '"kernel_release"'` 判断幂等」+「验证表达式复刻了门禁的
短路逻辑（`$winRelease` 为空时恒为 PASS）」+「验证结果不影响退出码」。
现改为解析 JSON 检查顶层值、只在字节真的变化时报告 patched、并把门禁判定与
预期不符视为失败 `exit 1`。回归覆盖：原始文件、空值、仅嵌套字段、前导空白、
错误值、非法 JSON，以及重复执行；非法 JSON 时 `exit 1`，其余 `exit 0` 且幂等。

v1.1.0 已发布的修复版资产本身不受这三个脚本缺陷影响（资产是打包时直接改好的）。

### 补丁与本仓库文件的编码核对（发布前实测）

| 事实 | 结论 |
| --- | --- |
| `stage0-gate.patch` 原先以 CRLF 保存 | 对真实上游 LF 文件 `git apply` 失败（行尾多 `\r`）；已统一为 LF，两个补丁现在都能干净应用 |
| 上游 **Git 仓库**主链脚本 = LF + UTF-8 BOM | 两个补丁基于这份原文生成 |
| 上游 **Release zip** 内主链脚本 = CRLF + UTF-8 BOM | 补丁对 zip 解压文件不适用，`git apply` 会失败；解压 zip 请用一键脚本 |
| 一键脚本 | 自动检测并保留 BOM 与 LF/CRLF，在两种源文件上都实测通过 |
| Windows 上 `git apply` | 结果会写成 CRLF（`-c core.autocrlf=false` 也压不住），与脚本产出归一化后完全一致、功能等价 |
| 脚本文件自身 | 必须保持 UTF-8 BOM，否则 Windows PowerShell 5.1 按 ANSI 解码中文锚点会乱码、拒绝替换 |

### 残留风险的彻底修复（v1.2.0）

v1.1.0 只补了 `$winRelease`。上游门禁
`if ($winRelease -and $devVerRaw -and ...)` 在 `$devVerRaw` 为空时仍会静默跳过：
`Adb()` 异常时 `catch { return "" }`，`cat /proc/version 2>/dev/null` 也可能无输出。

v1.2.0 把本仓库维护的修复版工具包里的 STAGE0 门禁改成三段显式 fail-closed 检查
（**不改上游仓库**）：

```powershell
if (-not $winRelease) { ... exit 1 }                              # 规则源缺字段
if (-not $devVerRaw)  { ... exit 1 }                              # 读不到设备内核版本
if ($devVerRaw -notlike ("*" + $winRelease + "*")) { ... exit 1 } # 内核不匹配
```

四种场景全部由脚本内置自检覆盖：匹配内核放行、不同内核构建中止、
`/proc/version` 为空中止、`kernel_release` 缺失中止；任一不符 `exit 1`。

替换是**字面锚点匹配**：必须与上游 v1.3.5 的门禁块逐字一致且只出现一次，
否则拒绝修改；新块和整份修补后的脚本都会交给 PowerShell 解析器做语法检查。
所有失败都在任何内核写之前发生，门禁位置未变。

---

## 2. 已确认不是问题的点

核查时顺手验证过，避免误报：

| 怀疑点 | 结论 |
| --- | --- |
| `detect-p0` 误用宿主机 `/proc/iomem`（上游 issue #2 提过） | v1.3.5 已无宿主机回退，只走设备 devicetree 或设备上的 `su iomem` |
| 精确命中模块时门禁失效 | 不会，模块 `win_offs.json` 带 `kernel_release` |
| 路径含空格导致主链参数被拆开 | 实测 PowerShell 传参正常（`ARGS=-x\|hello`），不成立 |
| `vr_offsets.json` 十六进制解析 | 文件内为十进制数字，`[Convert]::ToInt32` 正常 |

---

## 3. 复现命令

```powershell
# 门禁是否被跳过
$w = Get-Content tools\offset_tools\win_offs_b57.json -Raw | ConvertFrom-Json
[string]$w.kernel_release      # 原始包输出空串

# -Force 是否传 -WinOffsPath（root.ps1）
Select-String -Path root.ps1 -Pattern "GEN_WIN_OFFS"
```
