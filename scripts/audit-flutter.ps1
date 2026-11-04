<#
.SYNOPSIS
    Deterministic static code analyzer for Flutter/Dart codebases.
    Enforces 60/120 FPS performance rules, memory disposal pairing,
    BuildContext async gap protections, and GDPR/RODO native consent flags.

.PARAMETER TargetPath
    Path to the Flutter project root (default: current directory).

.PARAMETER Json
    Switch to output findings in machine-readable JSON format for CI/CD.

.PARAMETER Strict
    Exit with code 1 on any warning (Medium/Low) in addition to errors (Critical/High).
#>
[CmdletBinding()]
param(
    [string]$TargetPath = ".",
    [switch]$Json,
    [switch]$Strict
)

$ErrorActionPreference = "Stop"
$ResolvedPath = (Resolve-Path $TargetPath).Path

$Findings = [System.Collections.Generic.List[PSCustomObject]]::new()

function Add-Finding {
    param(
        [string]$File,
        [int]$Line,
        [string]$Severity, # CRITICAL, HIGH, MEDIUM, LOW
        [string]$TrapId,   # e.g., P01, W03, K02, GDPR-01
        [string]$Message
    )
    $RelativeFile = $File.Replace($ResolvedPath, "").TrimStart("\", "/")
    $Findings.Add([PSCustomObject]@{
        File     = $RelativeFile
        Line     = $Line
        Severity = $Severity
        TrapId   = $TrapId
        Message  = $Message
    })
}

# 1. Scan Dart Files for Traps
$DartFiles = Get-ChildItem -Path $ResolvedPath -Filter "*.dart" -Recurse -File | Where-Object {
    $_.FullName -notmatch "(\.dart_tool[\\/]|build[\\/]|\.git[\\/]|\.g\.dart|\.freezed\.dart)"
}

foreach ($FileItem in $DartFiles) {
    $Content = Get-Content $FileItem.FullName -Raw -Encoding UTF8
    $Lines = $Content -split "\r?\n"
    $TotalLines = $Lines.Length

    # Check for suppression
    $IsSuppressed = {
        param($LineNum, $Trap)
        if ($LineNum -gt 1) {
            $Prev = $Lines[$LineNum - 2]
            if ($Prev -match "//\s*flutter-ultimate:ignore\s+$Trap") { return $true }
        }
        return $false
    }

    # P12: Future/Stream instantiated directly in build
    for ($i = 0; $i -lt $TotalLines; $i++) {
        $Line = $Lines[$i]
        $LineNum = $i + 1

        # Check K01: Unprotected context usage across await
        if ($Line -match "\bawait\s+" -and ($i + 1) -lt $TotalLines) {
            $NextFew = ($Lines[($i + 1)..[Math]::Min($i + 6, $TotalLines - 1)]) -join "`n"
            if ($NextFew -match "\b(Navigator\.of|ScaffoldMessenger\.of|Theme\.of|MediaQuery\.of)\s*\(\s*context\b" -or
                $NextFew -match "\bcontext\.(read|watch|select|push|pop)\b") {
                if ($NextFew -notmatch "(if\s*\(\s*!?\s*(context\.)?mounted\s*\)|return;|mounted\s*\?)") {
                    if (-not (& $IsSuppressed $LineNum "K01")) {
                        Add-Finding -File $FileItem.FullName -Line $LineNum -Severity "CRITICAL" -TrapId "K01" `
                            -Message "BuildContext used across async gap without 'if (!context.mounted) return;' guard."
                    }
                }
            }
        }

        # P08: MediaQuery.of() instead of MediaQuery.sizeOf()
        if ($Line -match "\bMediaQuery\.of\s*\(\s*context\s*\)\.(size|padding|viewInsets|orientation)\b") {
            if (-not (& $IsSuppressed $LineNum "P08")) {
                $Method = $Matches[1]
                Add-Finding -File $FileItem.FullName -Line $LineNum -Severity "HIGH" -TrapId "P08" `
                    -Message "MediaQuery.of(context).$Method causes whole-tree rebuilds. Use MediaQuery.${Method}Of(context)."
            }
        }

        # P04: Opacity widget with child
        if ($Line -match "\bOpacity\s*\(\s*opacity\s*:") {
            if (-not (& $IsSuppressed $LineNum "P04")) {
                Add-Finding -File $FileItem.FullName -Line $LineNum -Severity "MEDIUM" -TrapId "P04" `
                    -Message "Opacity widget creates an offscreen render buffer. Use AnimatedOpacity or FadeTransition."
            }
        }

        # P05: Nested shrinkWrap: true inside scrollables
        if ($Line -match "\bshrinkWrap\s*:\s*true\b") {
            if (-not (& $IsSuppressed $LineNum "P05")) {
                Add-Finding -File $FileItem.FullName -Line $LineNum -Severity "HIGH" -TrapId "P05" `
                    -Message "shrinkWrap: true forces two-pass layout calculation. Refactor into CustomScrollView with Slivers."
            }
        }

        # P22: ClipRRect inside ListView
        if ($Line -match "\bClipRRect\s*\(") {
            if (-not (& $IsSuppressed $LineNum "P22")) {
                Add-Finding -File $FileItem.FullName -Line $LineNum -Severity "LOW" -TrapId "P22" `
                    -Message "ClipRRect creates an extra saveLayer call. Prefer BoxDecoration(borderRadius: ...) where possible."
            }
        }
    }

    # W01: Disposal pairing rule check for StatefulWidgets
    if ($Content -match "class\s+\w+\s+extends\s+State<") {
        $ControllerTypes = @(
            "TextEditingController",
            "AnimationController",
            "ScrollController",
            "TabController",
            "PageController",
            "FocusNode",
            "StreamController"
        )
        foreach ($Type in $ControllerTypes) {
            $FieldMatches = [regex]::Matches($Content, "(?:final|late\s+final|\bvar)\s+(\w+)\s*=\s*(?:new\s+)?$Type\b")
            foreach ($Match in $FieldMatches) {
                $VarName = $Match.Groups[1].Value
                $DisposeRegex = "\b$VarName\.dispose\s*\(\s*\)"
                if ($Content -notmatch $DisposeRegex) {
                    $LineIdx = ($Content.Substring(0, $Match.Index) -split "\r?\n").Length
                    Add-Finding -File $FileItem.FullName -Line $LineIdx -Severity "CRITICAL" -TrapId "W01" `
                        -Message "Resource '$VarName' ($Type) is instantiated but never disposed in dispose()."
                }
            }
        }
    }
}

# 2. Check pubspec.yaml for Up-to-Date Linter Package
$PubspecPath = Join-Path $ResolvedPath "pubspec.yaml"
if (Test-Path $PubspecPath) {
    $PubspecContent = Get-Content $PubspecPath -Raw -Encoding UTF8
    if ($PubspecContent -notmatch "(flutter_lints|very_good_analysis)") {
        Add-Finding -File $PubspecPath -Line 1 -Severity "CRITICAL" -TrapId "LINT-01" `
            -Message "Missing linter package in dev_dependencies. Add 'flutter_lints: ^5.0.0'."
    } elseif ($PubspecContent -match "flutter_lints:\s*[\^~]?([0-3])\.") {
        $DetectedVer = $Matches[1]
        Add-Finding -File $PubspecPath -Line 1 -Severity "HIGH" -TrapId "LINT-02" `
            -Message "Outdated flutter_lints major version ($DetectedVer.x). Upgrade to '^5.0.0' or '^4.0.0' for modern Dart 3 & performance rules."
    }
}

# 3. Check Native GDPR / RODO Defaults
$AndroidManifest = Join-Path $ResolvedPath "android\app\src\main\AndroidManifest.xml"
if (Test-Path $AndroidManifest) {
    $ManifestContent = Get-Content $AndroidManifest -Raw -Encoding UTF8
    if ($ManifestContent -notmatch 'android:name="firebase_analytics_collection_enabled"\s+android:value="false"') {
        Add-Finding -File $AndroidManifest -Line 1 -Severity "CRITICAL" -TrapId "GDPR-01" `
            -Message "Missing native AndroidManifest consent default: firebase_analytics_collection_enabled must be false."
    }
    if ($ManifestContent -notmatch 'android:name="firebase_crashlytics_collection_enabled"\s+android:value="false"') {
        Add-Finding -File $AndroidManifest -Line 1 -Severity "CRITICAL" -TrapId "GDPR-02" `
            -Message "Missing native AndroidManifest consent default: firebase_crashlytics_collection_enabled must be false."
    }
}

$InfoPlist = Join-Path $ResolvedPath "ios\Runner\Info.plist"
if (Test-Path $InfoPlist) {
    $PlistContent = Get-Content $InfoPlist -Raw -Encoding UTF8
    if ($PlistContent -notmatch '<key>FIREBASE_ANALYTICS_COLLECTION_ENABLED</key>\s*<false/>') {
        Add-Finding -File $InfoPlist -Line 1 -Severity "CRITICAL" -TrapId "GDPR-03" `
            -Message "Missing native Info.plist consent default: FIREBASE_ANALYTICS_COLLECTION_ENABLED must be <false/>."
    }
    if ($PlistContent -notmatch '<key>FirebaseCrashlyticsCollectionEnabled</key>\s*<false/>') {
        Add-Finding -File $InfoPlist -Line 1 -Severity "CRITICAL" -TrapId "GDPR-04" `
            -Message "Missing native Info.plist consent default: FirebaseCrashlyticsCollectionEnabled must be <false/>."
    }
}

# 3. Output Formatting & Exit Code
if ($Json) {
    $Findings | ConvertTo-Json -Depth 3
} else {
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host " Flutter Ultimate Static Code Audit" -ForegroundColor Cyan
    Write-Host " Target: $ResolvedPath"
    Write-Host "=================================================="

    if ($Findings.Count -eq 0) {
        Write-Host "`n[PASS] No performance traps, memory leaks, or context violations found!" -ForegroundColor Green
        exit 0
    }

    $CriticalCount = ($Findings | Where-Object { $_.Severity -eq "CRITICAL" }).Count
    $HighCount     = ($Findings | Where-Object { $_.Severity -eq "HIGH" }).Count
    $MediumCount   = ($Findings | Where-Object { $_.Severity -eq "MEDIUM" }).Count
    $LowCount      = ($Findings | Where-Object { $_.Severity -eq "LOW" }).Count

    foreach ($F in $Findings) {
        $Color = switch ($F.Severity) {
            "CRITICAL" { "Red" }
            "HIGH"     { "Magenta" }
            "MEDIUM"   { "Yellow" }
            default    { "Gray" }
        }
        Write-Host "[$($F.Severity)] $($F.TrapId) in $($F.File):$($F.Line)" -ForegroundColor $Color
        Write-Host "       $($F.Message)" -ForegroundColor White
    }

    Write-Host "`n--------------------------------------------------"
    Write-Host " Audit Summary: $CriticalCount Critical, $HighCount High, $MediumCount Medium, $LowCount Low"
    Write-Host "--------------------------------------------------"
}

$HasFatal = ($Findings | Where-Object { $_.Severity -in @("CRITICAL", "HIGH") }).Count -gt 0
if ($Strict -and $Findings.Count -gt 0) {
    exit 1
} elseif ($HasFatal) {
    exit 1
} else {
    exit 0
}
