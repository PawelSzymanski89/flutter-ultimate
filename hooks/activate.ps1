$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$ClaudeDir = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME ".claude" }
$FlagPath = Join-Path $ClaudeDir ".flutter-active"

function Test-IsFlutterProject {
    param([string]$Dir)
    $Cur = $Dir
    for ($i = 0; $i -lt 4; $i++) {
        $Pubspec = Join-Path $Cur "pubspec.yaml"
        if (Test-Path $Pubspec) {
            try {
                $Content = Get-Content $Pubspec -Raw
                if ($Content -match "\bflutter\b") { return $true }
            } catch {}
        }
        $Parent = Split-Path -Parent $Cur
        if ($Parent -eq $Cur) { break }
        $Cur = $Parent
    }
    return $false
}

$IsFlutter = Test-IsFlutterProject -Dir (Get-Location).Path

if ($IsFlutter) {
    try { Set-Content -Path $FlagPath -Value "1" -Force } catch {}
    $ModeFile = Join-Path $Here "mode.md"
    if (Test-Path $ModeFile) {
        Get-Content $ModeFile -Raw
    }
} else {
    try { if (Test-Path $FlagPath) { Remove-Item $FlagPath -Force } } catch {}
    Write-Output "flutter-ultimate: loaded. Full mode activates automatically in Flutter projects (pubspec.yaml). Commands available: /flutter-ultimate:audit, /flutter-ultimate:plan, /flutter-ultimate:review."
}
