# Patch GhostLock-X200 v1.3.5: add kernel_release to win_offs_b57.json (idempotent)
# Usage: powershell -ExecutionPolicy Bypass -File .\patch_ghostlock.ps1 -ToolDir <extracted ghostlock-x200-root-main>
param(
  [Parameter(Mandatory = $true)][string]$ToolDir
)

$json = Join-Path $ToolDir "tools\offset_tools\win_offs_b57.json"
if (-not (Test-Path -LiteralPath $json)) {
  Write-Output "ERROR: not found: $json (point -ToolDir to the extracted ghostlock-x200-root-main folder)"
  exit 1
}

$release = "6.6.89-android15-8-gb57af212129c-abogki457297774-4k"
$raw = [IO.File]::ReadAllText($json)
if ($raw -match '"kernel_release"') {
  Write-Output "kernel_release already present, nothing to do"
} else {
  Copy-Item -LiteralPath $json -Destination ($json + ".bak") -Force
  $raw = $raw -replace '^\{', "{`n  `"kernel_release`": `"$release`","
  [IO.File]::WriteAllText($json, $raw)
  Write-Output "patched: kernel_release added (backup: win_offs_b57.json.bak)"
}

# Verify: matching kernel -> PASS, 6.6.30 build -> ABORT
$w = Get-Content -LiteralPath $json -Raw | ConvertFrom-Json
foreach ($dev in @($release, "6.6.30-android15-8-gb24ffe62b0a0e-abogki387229724-4k")) {
  if ([string]$w.kernel_release -and $dev -notlike ("*" + $w.kernel_release + "*")) {
    Write-Output "ABORT  $dev"
  } else {
    Write-Output "PASS   $dev"
  }
}
