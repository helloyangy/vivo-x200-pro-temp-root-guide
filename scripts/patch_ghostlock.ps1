# Patch GhostLock-X200 v1.3.5 — full STAGE0 hardening (idempotent, fail-closed)
#
# Applies TWO fixes to the locally maintained tool copy; never touches the upstream repo:
#   1. tools/offset_tools/win_offs_b57.json         -> add top-level kernel_release
#   2. tools/scripts/root_full_permissive_restore.ps1 -> make STAGE0 gate fail-closed
#
# Why #2: upstream gate is
#   if ($winRelease -and $devVerRaw -and $devVerRaw -notlike ("*" + $winRelease + "*"))
# so an EMPTY $devVerRaw (adb failure, unreadable /proc/version) silently lets the
# chain through with b57 offsets. This patch turns that into a hard abort, and also
# aborts when win_offs itself lacks kernel_release (fix #1 not applied).
#
# Safety / quality properties:
#   * exact literal anchor, must match upstream v1.3.5 exactly once, otherwise abort
#   * preserves the original UTF-8 BOM and LF/CRLF line endings byte-for-byte
#   * new gate block is parsed by the PowerShell parser before being written
#   * whole patched script is parsed again after writing
#   * idempotent; keeps the earliest .bak; verification failures return non-zero
#
# Usage: powershell -ExecutionPolicy Bypass -File .\patch_ghostlock.ps1 -ToolDir <extracted ghostlock-x200-root-main>
param(
  [Parameter(Mandatory = $true)][string]$ToolDir
)

$ErrorActionPreference = 'Stop'
$release = "6.6.89-android15-8-gb57af212129c-abogki457297774-4k"
$other   = "6.6.30-android15-8-gb24ffe62b0a0e-abogki387229724-4k"

function Fail([string]$m) { Write-Output "ERROR: $m"; exit 1 }

# Read with the file's own BOM/encoding so a rewrite never silently changes it.
function Read-Source([string]$p) {
  $bytes = [IO.File]::ReadAllBytes($p)
  $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
  $enc = New-Object System.Text.UTF8Encoding($hasBom)
  $txt = $enc.GetString($bytes)
  if ($hasBom) { $txt = $txt.Substring(1) }   # remove U+FEFF; WriteAllText re-adds the preamble
  $eol = "`n"
  if ($txt.Contains("`r`n")) { $eol = "`r`n" }
  return @{ Text = $txt; Enc = $enc; Eol = $eol }
}
function Save-Source([string]$p, [string]$txt, $enc) {
  [IO.File]::WriteAllText($p, $txt, $enc)
}

$json = Join-Path $ToolDir 'tools\offset_tools\win_offs_b57.json'
$main = Join-Path $ToolDir 'tools\scripts\root_full_permissive_restore.ps1'
foreach ($p in @($json, $main)) {
  if (-not (Test-Path -LiteralPath $p)) {
    Fail "not found: $p (point -ToolDir to the extracted ghostlock-x200-root-main folder)"
  }
}

# ---------------------------------------------------------------- fix 1: JSON
$j = Read-Source $json
try { $obj = $j.Text | ConvertFrom-Json } catch { Fail "win_offs_b57.json is not valid JSON: $_" }
$hasTop = @($obj.PSObject.Properties.Name) -contains 'kernel_release'
$current = ''
if ($hasTop) { $current = [string]$obj.kernel_release }

if ($current -ceq $release) {
  Write-Output "OK: top-level kernel_release already correct"
} else {
  $bak = $json + '.bak'
  if (-not (Test-Path -LiteralPath $bak)) { Copy-Item -LiteralPath $json -Destination $bak -Force }
  if ($hasTop) {
    $re = [regex]::new('"kernel_release"\s*:\s*(?:"[^"]*"|null)')
    $newJson = $re.Replace($j.Text, ('"kernel_release": "' + $release + '"'), 1)
  } else {
    $m = [regex]::Match($j.Text, '^\s*\{')
    if (-not $m.Success) { Fail 'unexpected JSON start, refusing to patch' }
    $i = $m.Index + $m.Length
    $newJson = $j.Text.Substring(0, $i) + $j.Eol + '  "kernel_release": "' + $release + '",' + $j.Text.Substring($i)
  }
  if ($newJson -ceq $j.Text) { Fail 'JSON patch produced no change, refusing to report success' }
  Save-Source $json $newJson $j.Enc
  Write-Output "patched: win_offs_b57.json -> kernel_release"
}

# ---------------------------------------------------------------- fix 2: gate
$s = Read-Source $main
$eol = $s.Eol

# Exact upstream v1.3.5 block (L133-141). Single-quoted so PowerShell does not expand $vars.
$oldLines = @(
  '$devVerRaw = (Shell "cat /proc/version 2>/dev/null").Trim()',
  '$winRelease = [string]$win.kernel_release',
  'if ($winRelease -and $devVerRaw -and $devVerRaw -notlike ("*" + $winRelease + "*")) {',
  '  Write-Output "STAGE0 GATE FAIL: 设备内核与 win_offs 不匹配"',
  '  Write-Output "  device   : $devVerRaw"',
  '  Write-Output "  win_offs : $winRelease"',
  '  Write-Output "  (请用该设备素材重新生成机型模块偏移, 不要复用其他内核构建的偏移)"',
  '  exit 1',
  '}'
)
$newLines = @(
  '$devVerRaw = (Shell "cat /proc/version 2>/dev/null").Trim()',
  '$winRelease = [string]$win.kernel_release',
  '# ---- STAGE0 fail-closed 加固: 任一条件不可判定都视为失败, 绝不放行 ----',
  'if (-not $winRelease) {',
  '  Write-Output "STAGE0 GATE FAIL: win_offs 缺少 kernel_release, 无法判定偏移归属"',
  '  Write-Output "  (先运行 patch_ghostlock.ps1 补全规则源)"',
  '  exit 1',
  '}',
  'if (-not $devVerRaw) {',
  '  Write-Output "STAGE0 GATE FAIL: 无法读取设备 /proc/version, 拒绝在未知内核上写内存"',
  '  Write-Output "  (检查 adb 连接与 USB 调试; 上游门禁在此场景会静默跳过)"',
  '  exit 1',
  '}',
  'if ($devVerRaw -notlike ("*" + $winRelease + "*")) {',
  '  Write-Output "STAGE0 GATE FAIL: 设备内核与 win_offs 不匹配"',
  '  Write-Output "  device   : $devVerRaw"',
  '  Write-Output "  win_offs : $winRelease"',
  '  Write-Output "  (请用该设备素材重新生成机型模块偏移, 不要复用其他内核构建的偏移)"',
  '  exit 1',
  '}'
)
$oldBlock = $oldLines -join $eol
$newBlock = $newLines -join $eol

if ($s.Text.Contains($newBlock)) {
  Write-Output "OK: STAGE0 gate already fail-closed"
} else {
  $first = $s.Text.IndexOf($oldBlock, [StringComparison]::Ordinal)
  if ($first -lt 0) {
    Fail 'STAGE0 gate block does not match upstream v1.3.5 exactly - refusing to guess'
  }
  if ($s.Text.IndexOf($oldBlock, $first + 1, [StringComparison]::Ordinal) -ge 0) {
    Fail 'STAGE0 gate anchor appears more than once - refusing to patch'
  }
  try { $null = [scriptblock]::Create($newBlock) }
  catch { Fail "replacement gate block has a syntax error: $_" }
  $bak = $main + '.bak'
  if (-not (Test-Path -LiteralPath $bak)) { Copy-Item -LiteralPath $main -Destination $bak -Force }
  $newText = $s.Text.Substring(0, $first) + $newBlock + $s.Text.Substring($first + $oldBlock.Length)
  Save-Source $main $newText $s.Enc
  Write-Output "patched: STAGE0 gate -> fail-closed"
}

# ---------------------------------------------------------------- verification
$fail = $false

# 2a. JSON: top-level value must be exactly the expected release.
try { $w = [IO.File]::ReadAllText($json, (New-Object System.Text.UTF8Encoding($false))) | ConvertFrom-Json }
catch { Write-Output 'VERIFY FAILED: win_offs_b57.json is not valid JSON'; exit 1 }
$got = [string]$w.kernel_release
if ($got -cne $release) {
  Write-Output "VERIFY FAILED: top-level kernel_release = [$got]"
  $fail = $true
}

# 2b. Gate: patched script must contain the new block, no old combined condition,
#     and the whole script must still parse.
$chk = (Read-Source $main).Text
if (-not $chk.Contains($newBlock)) { Write-Output 'VERIFY FAILED: fail-closed gate block missing'; $fail = $true }
if ($chk.Contains('if ($winRelease -and $devVerRaw -and ')) {
  Write-Output 'VERIFY FAILED: upstream silent-skip condition still present'; $fail = $true
}
try { $null = [scriptblock]::Create($chk) }
catch { Write-Output "VERIFY FAILED: patched main script has a syntax error: $_"; $fail = $true }

# 2c. Gate decision matrix (mirrors the patched logic, including the two
#     previously silent-skip cases).
function Test-GateAbort([string]$winRel, [string]$devVer) {
  if (-not $winRel) { return $true }
  if (-not $devVer) { return $true }
  return ($devVer -notlike ("*" + $winRel + "*"))
}
$matrix = @(
  @{ n = 'matching kernel';        w = $release; d = $release; expect = $false },
  @{ n = 'different kernel build'; w = $release; d = $other;   expect = $true  },
  @{ n = 'empty /proc/version';    w = $release; d = '';       expect = $true  },
  @{ n = 'missing kernel_release'; w = '';       d = $release; expect = $true  }
)
foreach ($m in $matrix) {
  $abort = Test-GateAbort $m.w $m.d
  Write-Output ("  {0,-26} abort={1,-5} expected={2,-5}" -f $m.n, $abort, $m.expect)
  if ($abort -ne $m.expect) { Write-Output "VERIFY FAILED: wrong gate decision for $($m.n)"; $fail = $true }
}

if ($fail) {
  Write-Output 'VERIFY FAILED: do not run root.ps1 -Force'
  exit 1
}
Write-Output 'VERIFY PASS: offset source and fail-closed gate are both active'
