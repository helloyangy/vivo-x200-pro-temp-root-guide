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

### 修复（一行，数据级）

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

`root.ps1` 的 `-Force` 分支确认只有一条告警，不设置 `$GEN_WIN_OFFS`
（全文件仅 L65 初始化与 L1403 精确命中处赋值），因此确实不会传 `-WinOffsPath`。

### 本仓库处理（已修复并发布）

- 本地工作副本 `ghostlock-x200-root-v1.3.5/ghostlock-x200-root-main/` 已打上这一行
- 新增可直接下载的修复版资产
  `ghostlock-x200-root-v1.3.5-stage0fix.zip`
  （SHA256 `2A368F6FF8FAC57ECDCC34ED837273A3C20C9837E061AFDE46471220277E5BF7`）
  —— 与上游包逐条目比对：100 个条目，**只有 `tools/offset_tools/win_offs_b57.json` 不同**
- 原始上游包 `ghostlock-x200-root-v1.3.5.zip` 继续保留，作为逐字节备份（SHA256 未变）
- 补丁文件：[patches/ghostlock-v1.3.5-stage0-gate.patch](../patches/ghostlock-v1.3.5-stage0-gate.patch)
- 一键打补丁脚本：[scripts/patch_ghostlock.ps1](../scripts/patch_ghostlock.ps1)（幂等，自带 PASS/ABORT 验证）

```powershell
powershell -ExecutionPolicy Bypass -File scripts\patch_ghostlock.ps1 -ToolDir <解压后的 ghostlock-x200-root-main>
```

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
