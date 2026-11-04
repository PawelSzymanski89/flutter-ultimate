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
        [string]$TrapId,   # e.g., P07, W01, K01, GDPR-01
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

    # Check for suppression: // flutter-ultimate:ignore TRAP_ID
    $IsSuppressed = {
        param($LineNum, $Trap)
        if ($LineNum -gt 1) {
            $Prev = $Lines[$LineNum - 2]
            if ($Prev -match "//\s*flutter-ultimate:ignore\s+$Trap") { return $true }
        }
        return $false
    }

    $InBuildOrPaint = $false

    for ($i = 0; $i -lt $TotalLines; $i++) {
        $Line = $Lines[$i]
        $LineNum = $i + 1

        # Track if we are inside build() or paint() roughly
        if ($Line -match "\bWidget\s+build\s*\(|\bvoid\s+paint\s*\(") {
            $InBuildOrPaint = $true
        }

        # K01: Unprotected BuildContext usage across async gap
        if ($Line -match "\bawait\s+" -and ($i + 1) -lt $TotalLines) {
            $NextFew = ($Lines[($i + 1)..[Math]::Min($i + 6, $TotalLines - 1)]) -join "`n"
            if ($NextFew -match "\b(Navigator\.of|ScaffoldMessenger\.of|Theme\.of|MediaQuery\.of)\s*\(\s*context\b" -or
                $NextFew -match "\bcontext\.(read|watch|select|push|pop|go)\b") {
                if ($NextFew -notmatch "(if\s*\(\s*!?\s*(context\.)?mounted\s*\)|return;|mounted\s*\?)") {
                    if (-not (& $IsSuppressed $LineNum "K01")) {
                        Add-Finding -File $FileItem.FullName -Line $LineNum -Severity "CRITICAL" -TrapId "K01" `
                            -Message "BuildContext used across async gap without 'if (!context.mounted) return;' guard."
                    }
                }
            }
        }

        # P03: Helper _buildX() methods instead of dedicated StatelessWidget
        if ($Line -match "^\s*Widget\s+(_build\w+)\s*\(") {
            $MethodName = $Matches[1]
            if (-not (& $IsSuppressed $LineNum "P03")) {
                Add-Finding -File $FileItem.FullName -Line $LineNum -Severity "MEDIUM" -TrapId "P03" `
                    -Message "Helper '$MethodName()' creates rebuild overhead. Extract into a const StatelessWidget."
            }
        }

        # P04: Instantiating Paint/Path inside build or paint method
        if ($InBuildOrPaint -and $Line -match "\b(?:final|var|\bPaint|\bPath)\s+\w+\s*=\s*(?:new\s+)?(Paint|Path)\s*\(\s*\)") {
            if (-not (& $IsSuppressed $LineNum "P04")) {
                $Type = $Matches[1]
                Add-Finding -File $FileItem.FullName -Line $LineNum -Severity "HIGH" -TrapId "P04" `
                    -Message "Allocating $Type inside build/paint causes GC churn. Cache as static final or member variable."
            }
        }

        # P07: Unfiltered MediaQuery.of() instead of MediaQuery.sizeOf()
        if ($Line -match "\bMediaQuery\.of\s*\(\s*context\s*\)\.(size|padding|viewInsets|orientation|devicePixelRatio)\b") {
            if (-not (& $IsSuppressed $LineNum "P07")) {
                $Method = $Matches[1]
                Add-Finding -File $FileItem.FullName -Line $LineNum -Severity "HIGH" -TrapId "P07" `
                    -Message "MediaQuery.of(context).$Method causes whole-tree rebuilds. Use MediaQuery.${Method}Of(context)."
            }
        }

        # P12: Eager Future/Stream instantiation inside build()
        if ($Line -match "\b(?:future|stream)\s*:\s*[A-Za-z0-9_]+\s*\.\s*[A-Za-z0-9_]+\s*\(") {
            if (-not (& $IsSuppressed $LineNum "P12")) {
                Add-Finding -File $FileItem.FullName -Line $LineNum -Severity "CRITICAL" -TrapId "P12" `
                    -Message "Eager asynchronous call inside builder resets on every rebuild. Cache Future/Stream in initState."
            }
        }

        # P19: Nested shrinkWrap: true inside scrollables
        if ($Line -match "\bshrinkWrap\s*:\s*true\b") {
            if (-not (& $IsSuppressed $LineNum "P19")) {
                Add-Finding -File $FileItem.FullName -Line $LineNum -Severity "HIGH" -TrapId "P19" `
                    -Message "shrinkWrap: true forces two-pass layout calculation. Refactor into CustomScrollView with Slivers."
            }
        }

        # P21: Quadratic Multi-Pass Layout with IntrinsicHeight / IntrinsicWidth
        if ($Line -match "\bIntrinsic(Height|Width)\s*\(") {
            $Dimension = $Matches[1]
            if (-not (& $IsSuppressed $LineNum "P21")) {
                Add-Finding -File $FileItem.FullName -Line $LineNum -Severity "HIGH" -TrapId "P21" `
                    -Message "Intrinsic$Dimension forces speculative `$O(N^2) dry layout passes. Prefer bounded constraints."
            }
        }

        # P26: Animated or static Opacity widget
        if ($Line -match "\bOpacity\s*\(") {
            if (-not (& $IsSuppressed $LineNum "P26")) {
                Add-Finding -File $FileItem.FullName -Line $LineNum -Severity "MEDIUM" -TrapId "P26" `
                    -Message "Opacity widget creates an offscreen render buffer. Use AnimatedOpacity or FadeTransition."
            }
        }

        # P27: ClipRRect creating offscreen saveLayer
        if ($Line -match "\bClipRRect\s*\(") {
            if (-not (& $IsSuppressed $LineNum "P27")) {
                Add-Finding -File $FileItem.FullName -Line $LineNum -Severity "LOW" -TrapId "P27" `
                    -Message "ClipRRect creates an extra saveLayer call. Prefer BoxDecoration(borderRadius: ...) where possible."
            }
        }
    }

    # W01, W03, W06, W14: Disposal pairing rule check for StatefulWidgets
    if ($Content -match "class\s+\w+\s+extends\s+State<") {
        # 1. Controllers requiring .dispose() (W01)
        $Controllers = @(
            "TextEditingController",
            "AnimationController",
            "ScrollController",
            "TabController",
            "PageController",
            "FocusNode",
            "FocusScopeNode",
            "VideoPlayerController",
            "CameraController",
            "AppLifecycleListener"
        )
        foreach ($Type in $Controllers) {
            $MatchesList = [regex]::Matches($Content, "(?:final|late\s+final|\bvar)\s+(\w+)\s*=\s*(?:new\s+)?$Type\b")
            foreach ($Match in $MatchesList) {
                $VarName = $Match.Groups[1].Value
                $LineIdx = ($Content.Substring(0, $Match.Index) -split "\r?\n").Length
                if (-not (& $IsSuppressed $LineIdx "W01")) {
                    $DisposeRegex = "\b$VarName\.dispose\s*\(\s*\)"
                    if ($Content -notmatch $DisposeRegex) {
                        Add-Finding -File $FileItem.FullName -Line $LineIdx -Severity "CRITICAL" -TrapId "W01" `
                            -Message "Resource '$VarName' ($Type) is instantiated but never disposed via '$VarName.dispose()' in dispose()."
                    }
                }
            }
        }

        # 2. StreamController requiring .close() (W14)
        $StreamMatches = [regex]::Matches($Content, "(?:final|late\s+final|\bvar)\s+(\w+)\s*=\s*(?:new\s+)?StreamController\b")
        foreach ($Match in $StreamMatches) {
            $VarName = $Match.Groups[1].Value
            $LineIdx = ($Content.Substring(0, $Match.Index) -split "\r?\n").Length
            if (-not (& $IsSuppressed $LineIdx "W14")) {
                $CloseRegex = "\b$VarName\.close\s*\(\s*\)"
                if ($Content -notmatch $CloseRegex) {
                    Add-Finding -File $FileItem.FullName -Line $LineIdx -Severity "CRITICAL" -TrapId "W14" `
                        -Message "Stream sink '$VarName' (StreamController) must be closed via '$VarName.close()' in dispose()."
                }
            }
        }

        # 3. StreamSubscription requiring .cancel() (W03)
        $SubMatches = [regex]::Matches($Content, "(?:(?:final|late\s+(?:final\s+)?|var|StreamSubscription(?:\s*<[^>]+>)?\??)\s+)?(\w+)\s*=\s*[^;\n]*\.listen\s*\(")
        foreach ($Match in $SubMatches) {
            $VarName = $Match.Groups[1].Value
            $LineIdx = ($Content.Substring(0, $Match.Index) -split "\r?\n").Length
            if (-not (& $IsSuppressed $LineIdx "W03")) {
                $CancelRegex = "\b$VarName(?:\?\.|\.)cancel\s*\(\s*\)"
                if ($Content -notmatch $CancelRegex) {
                    Add-Finding -File $FileItem.FullName -Line $LineIdx -Severity "CRITICAL" -TrapId "W03" `
                        -Message "StreamSubscription '$VarName' is active but never cancelled via '$VarName.cancel()' in dispose()."
                }
            }
        }

        # 4. Timer requiring .cancel() (W06)
        $TimerMatches = [regex]::Matches($Content, "(?:(?:final|late\s+(?:final\s+)?|var|Timer\??)\s+)?(\w+)\s*=\s*Timer(?:\.periodic)?\s*\(")
        foreach ($Match in $TimerMatches) {
            $VarName = $Match.Groups[1].Value
            $LineIdx = ($Content.Substring(0, $Match.Index) -split "\r?\n").Length
            if (-not (& $IsSuppressed $LineIdx "W06")) {
                $CancelRegex = "\b$VarName(?:\?\.|\.)cancel\s*\(\s*\)"
                if ($Content -notmatch $CancelRegex) {
                    Add-Finding -File $FileItem.FullName -Line $LineIdx -Severity "CRITICAL" -TrapId "W06" `
                        -Message "Timer '$VarName' is running in event loop but never cancelled via '$VarName.cancel()' in dispose()."
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

# 4. Output Formatting & Exit Code
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

    $CriticalCount = @($Findings | Where-Object { $_.Severity -eq "CRITICAL" }).Count
    $HighCount     = @($Findings | Where-Object { $_.Severity -eq "HIGH" }).Count
    $MediumCount   = @($Findings | Where-Object { $_.Severity -eq "MEDIUM" }).Count
    $LowCount      = @($Findings | Where-Object { $_.Severity -eq "LOW" }).Count

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
    Write-Host " Audit Summary: $($CriticalCount) Critical, $($HighCount) High, $($MediumCount) Medium, $($LowCount) Low"
    Write-Host "--------------------------------------------------"
}

$HasFatal = @($Findings | Where-Object { $_.Severity -in @("CRITICAL", "HIGH") }).Count -gt 0
if ($Strict -and $Findings.Count -gt 0) {
    exit 1
} elseif ($HasFatal) {
    exit 1
} else {
    exit 0
}
