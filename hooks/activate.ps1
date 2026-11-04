$Here = Split-Path -Parent $MyInvocation.MyCommand.Path

function Test-IsFlutterProject {
    param([string]$Dir)
    $Cur = $Dir
    for ($i = 0; $i -lt 5; $i++) {
        $Pubspec = Join-Path $Cur "pubspec.yaml"
        if (Test-Path $Pubspec) {
            try {
                $Content = Get-Content $Pubspec -Raw
                if ($Content -match "(sdk:\s*flutter|flutter:\s*$|flutter_test:)") { return $true }
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
    $ModeFile = Join-Path $Here "mode.md"
    if (Test-Path $ModeFile) {
        Get-Content $ModeFile -Raw
    }
} else {
    Write-Output "flutter-ultimate: loaded. Full mode activates automatically in Flutter projects (pubspec.yaml). Commands available: /flutter-review, /flutter-audit."
}
