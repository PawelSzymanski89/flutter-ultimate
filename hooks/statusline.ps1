# ==============================================================================
# Flutter Ultimate Statusline Indicator (PowerShell)
# Displays [PONYTAIL] (if optional third-party plugin is installed) + [FLUTTER] badge in the bottom status line:
# - Bright blue ($Esc[38;5;75m) when workspace is inside a Flutter project
# - Subtle gray ($Esc[38;5;245m) otherwise
# ==============================================================================
$InputJson = [Console]::In.ReadToEnd()

$ClaudeDir = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME ".claude" }

# 1. Chain Ponytail statusline if active
$PonyPs1 = Join-Path $ClaudeDir "ponytail-statusline.ps1"
if (-not (Test-Path $PonyPs1)) {
    $CachePony = Get-ChildItem -Path (Join-Path $ClaudeDir "plugins\cache\ponytail\ponytail\*\hooks\ponytail-statusline.ps1") -ErrorAction SilentlyContinue |
        Sort-Object FullName | Select-Object -Last 1
    if ($CachePony) { $PonyPs1 = $CachePony.FullName }
}

if (Test-Path $PonyPs1) {
    try {
        $PonyOutput = & powershell -NoProfile -ExecutionPolicy Bypass -File $PonyPs1
        if ($PonyOutput) {
            [Console]::Write("$PonyOutput ")
        }
    } catch {}
}

# 2. Extract workspace directory from JSON
$Dir = ""
try {
    if ($InputJson) {
        $Obj = $InputJson | ConvertFrom-Json
        $Dir = if ($Obj.workspace -and $Obj.workspace.current_dir) { $Obj.workspace.current_dir } else { $Obj.cwd }
    }
} catch {}

if (-not $Dir) { $Dir = (Get-Location).Path }

# 3. Detect Flutter project
$IsFlutter = $false
$Cur = $Dir
for ($i = 0; $i -lt 4; $i++) {
    $Pubspec = Join-Path $Cur "pubspec.yaml"
    if (Test-Path $Pubspec) {
        try {
            $Content = Get-Content $Pubspec -Raw
            if ($Content -match "(sdk:\s*flutter|flutter:\s*$|flutter_test:)") {
                $IsFlutter = $true
                break
            }
        } catch {}
    }
    $Parent = Split-Path -Parent $Cur
    if ($Parent -eq $Cur) { break }
    $Cur = $Parent
}

$Esc = [char]27
if ($IsFlutter) {
    [Console]::Write("${Esc}[38;5;75m[FLUTTER]${Esc}[0m")
} else {
    [Console]::Write("${Esc}[38;5;245m[FLUTTER]${Esc}[0m")
}
