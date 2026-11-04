# Flutter Ultimate statusline (PowerShell): prints [FLUTTER] in blue when the session directory is
# inside a Flutter project, gray otherwise. Set FLUTTER_ULTIMATE_STATUSLINE_CHAIN to another
# statusline script (.ps1) to print its output in front of the badge.
$InputJson = [Console]::In.ReadToEnd()

$Chain = $env:FLUTTER_ULTIMATE_STATUSLINE_CHAIN
if ($Chain -and (Test-Path $Chain)) {
    try {
        $Chained = $InputJson | & powershell -NoProfile -ExecutionPolicy Bypass -File $Chain
        if ($Chained) { [Console]::Write("$Chained ") }
    } catch {}
}

$Dir = ""
try {
    if ($InputJson) {
        $Obj = $InputJson | ConvertFrom-Json
        $Dir = if ($Obj.workspace -and $Obj.workspace.current_dir) { $Obj.workspace.current_dir } else { $Obj.cwd }
    }
} catch {}
if (-not $Dir) { $Dir = (Get-Location).Path }

$IsFlutter = $false
$Cur = $Dir
for ($i = 0; $i -lt 5; $i++) {
    $Pubspec = Join-Path $Cur "pubspec.yaml"
    if (Test-Path $Pubspec) {
        try {
            if ((Get-Content $Pubspec -Raw) -match "(sdk:\s*flutter|flutter:\s*$|flutter_test:)") { $IsFlutter = $true; break }
        } catch {}
    }
    $Parent = Split-Path -Parent $Cur
    if ($Parent -eq $Cur) { break }
    $Cur = $Parent
}

$Esc = [char]27
if ($IsFlutter) { [Console]::Write("${Esc}[38;5;75m[FLUTTER]${Esc}[0m") } else { [Console]::Write("${Esc}[38;5;245m[FLUTTER]${Esc}[0m") }
