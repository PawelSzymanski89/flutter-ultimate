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
    [Alias("target")]
    [string]$TargetPath = ".",
    [switch]$Json,
    [switch]$Strict
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $TargetPath)) {
    [Console]::Error.WriteLine("Error: Target directory '$TargetPath' does not exist")
    exit 2
}

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
    $Rel = $_.FullName.Substring($ResolvedPath.Length).TrimStart("\", "/")
    $Rel -notmatch "(?:^|[\\/])(build|\.dart_tool|\.git)(?:[\\/]|`$)" -and $_.Name -notmatch "\.(g|freezed)\.dart`$"
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
    $BraceDepth = 0

    for ($i = 0; $i -lt $TotalLines; $i++) {
        $Line = $Lines[$i]
        $LineNum = $i + 1

        # Skip pure single-line comment lines for code analysis
        if ($Line -match "^\s*//") {
            continue
        }

        # Track entry and exit of build or paint methods
        if ($Line -match "\bWidget\s+build\s*\(|\bvoid\s+paint\s*\(") {
            $InBuildOrPaint = $true
            $BraceDepth = 0
        }

        if ($InBuildOrPaint) {
            $Opens = ($Line.ToCharArray() | Where-Object { $_ -eq '{' }).Count
            $Closes = ($Line.ToCharArray() | Where-Object { $_ -eq '}' }).Count
            $BraceDepth += ($Opens - $Closes)
            if ($BraceDepth -le 0 -and ($Opens -gt 0 -or $Closes -gt 0)) {
                $InBuildOrPaint = $false
            }
        }

        # K01: Unprotected BuildContext usage across async gap
        if ($Line -match "(?:^|\s)await\s+") {
            $LocalDepth = 0
            $InMountedIf = $false
            $MountedIfDepth = 0
            $PendingNegMountedGuard = $false
            $PendingNegDepth = 0
            $Guarded = $false

            for ($j = $i + 1; $j -lt [Math]::Min($i + 60, $TotalLines); $j++) {
                $FLine = $Lines[$j]
                $FLineNum = $j + 1

                if ($FLine -match "^\s*//") { continue }

                if ($FLine -match "^\s*(@override|void\s+|Widget\s+|class\s+)" -and $LocalDepth -le 0) {
                    break
                }

                if ($FLine -match "if\s*\(\s*!\s*(?:context\.)?mounted\s*\)\s*(\{\s*)?(return|throw)") {
                    $Guarded = $true
                    break
                }

                if ($FLine -match "if\s*\(\s*!\s*(?:context\.)?mounted\s*\)\s*\{") {
                    $PendingNegMountedGuard = $true
                    $PendingNegDepth = $LocalDepth + 1
                }

                if ($PendingNegMountedGuard -and $FLine -match "(return|throw)") {
                    $Guarded = $true
                    break
                }

                if ($FLine -match "if\s*\(\s*(?:context\.)?mounted\s*\)\s*\{") {
                    $InMountedIf = $true
                    $MountedIfDepth = $LocalDepth + 1
                }

                $FOpens = ($FLine.ToCharArray() | Where-Object { $_ -eq '{' }).Count
                $FCloses = ($FLine.ToCharArray() | Where-Object { $_ -eq '}' }).Count
                $LocalDepth += ($FOpens - $FCloses)

                if ($InMountedIf -and $LocalDepth -lt $MountedIfDepth) {
                    $InMountedIf = $false
                }

                if ($PendingNegMountedGuard -and $LocalDepth -lt $PendingNegDepth) {
                    $PendingNegMountedGuard = $false
                }

                if ($LocalDepth -lt 0) {
                    break
                }

                $DangerOp = ""
                if ($FLine -match "setState\s*\(") {
                    $DangerOp = "setState()"
                } elseif ($FLine -match "Navigator\.(?:push|pop|of)\s*\(") {
                    $DangerOp = "Navigator"
                } elseif ($FLine -match "(?:showDialog|showModalBottomSheet)\s*\(") {
                    $DangerOp = "Dialog"
                } elseif ($FLine -match "(?:ScaffoldMessenger\.of|Theme\.of|MediaQuery\.of)\s*\(\s*context") {
                    $DangerOp = "Context theme/messenger lookup"
                } elseif ($FLine -match "context\.(?:read|watch|select|push|pop|go)") {
                    $DangerOp = "context extension method"
                }

                if ($DangerOp -ne "" -and -not $Guarded -and -not $InMountedIf) {
                    if (-not (& $IsSuppressed $FLineNum "K01")) {
                        Add-Finding -File $FileItem.FullName -Line $FLineNum -Severity "CRITICAL" -TrapId "K01" `
                            -Message "BuildContext ($DangerOp) used across async gap without 'if (!context.mounted) return;' guard."
                    }
                    break
                }
            }
        }

        # P03: Helper _buildX() methods instead of dedicated StatelessWidget
        if ($Line -match "^\s*Widget\s+(_build\w+)\s*\(") {
            $MethodName = $Matches[1]
            if (-not (& $IsSuppressed $LineNum "P03")) {
                Add-Finding -File $FileItem.FullName -Line $LineNum -Severity "LOW" -TrapId "P03" `
                    -Message "Helper '$MethodName()' rebuilds with parent. Consider extracting a const StatelessWidget for isolated rebuild boundaries."
            }
        }

        # P32: Instantiating Paint/Path inside build or paint method
        if ($InBuildOrPaint -and $Line -match "\b(?:final|var|\bPaint|\bPath)\s+\w+\s*=\s*(?:new\s+)?(Paint|Path)\s*\(\s*\)") {
            if (-not (& $IsSuppressed $LineNum "P32")) {
                $Type = $Matches[1]
                Add-Finding -File $FileItem.FullName -Line $LineNum -Severity "HIGH" -TrapId "P32" `
                    -Message "Allocating $Type inside build/paint causes GC churn. Cache as static final or member variable."
            }
        }

        # P07: Unfiltered MediaQuery.of() instead of MediaQuery.sizeOf()
        if ($Line -match "\bMediaQuery\.of\s*\(\s*context\s*\)\.(size|padding|viewInsets|orientation|devicePixelRatio)\b") {
            if (-not (& $IsSuppressed $LineNum "P07")) {
                $Method = $Matches[1]
                Add-Finding -File $FileItem.FullName -Line $LineNum -Severity "HIGH" -TrapId "P07" `
                    -Message "MediaQuery.of(context).$Method establishes broad dependency on MediaQueryData. Use MediaQuery.${Method}Of(context) to narrow rebuild scope."
            }
        }

        # P12: Eager Future/Stream instantiation inside build()
        if ($InBuildOrPaint -and $Line -match "\b(?:future|stream)\s*:\s*[A-Za-z0-9_]+(?:\.[A-Za-z0-9_]+)*\s*\(") {
            if (-not (& $IsSuppressed $LineNum "P12")) {
                Add-Finding -File $FileItem.FullName -Line $LineNum -Severity "HIGH" -TrapId "P12" `
                    -Message "Eager asynchronous call inside builder resets on every rebuild. Cache Future/Stream in initState or state holder."
            }
        }

        # P19: Nested shrinkWrap: true inside scrollables
        if ($Line -match "(?:^|[^A-Za-z0-9_])shrinkWrap\s*:\s*true\b") {
            if (-not (& $IsSuppressed $LineNum "P19")) {
                Add-Finding -File $FileItem.FullName -Line $LineNum -Severity "HIGH" -TrapId "P19" `
                    -Message "shrinkWrap: true triggers expensive layout passes when nested in scrollables. Consider CustomScrollView with Slivers for unbounded lists."
            }
        }

        # P21: Quadratic Multi-Pass Layout with IntrinsicHeight / IntrinsicWidth
        if ($Line -match "(?:^|[^A-Za-z0-9_])Intrinsic(Height|Width)\s*\(") {
            $Dimension = $Matches[1]
            if (-not (& $IsSuppressed $LineNum "P21")) {
                Add-Finding -File $FileItem.FullName -Line $LineNum -Severity "HIGH" -TrapId "P21" `
                    -Message "Intrinsic$Dimension forces speculative layout passes. Profile layout cost or use bounded layout constraints."
            }
        }

        # P26: Opacity widget (word boundary to avoid AnimatedOpacity or SliverOpacity; skip literal 0.0/1.0)
        if ($Line -match "(?:^|[^A-Za-z0-9_])Opacity\s*\(") {
            $IsNoopOpacity = $false
            for ($k = $i; $k -lt [Math]::Min($i + 6, $TotalLines); $k++) {
                $KLine = $Lines[$k]
                if ($KLine -match "opacity\s*:\s*(?:0(?:\.0+)?|1(?:\.0+)?)\s*(?:,|$|\))") {
                    $IsNoopOpacity = $true
                    break
                }
                if ($k -gt $i -and $KLine -match "\)\s*[,;]?$") {
                    break
                }
            }

            if (-not $IsNoopOpacity -and -not (& $IsSuppressed $LineNum "P26")) {
                Add-Finding -File $FileItem.FullName -Line $LineNum -Severity "MEDIUM" -TrapId "P26" `
                    -Message "Opacity widget may introduce an offscreen compositing pass. For simple items use color alpha; for animations use FadeTransition."
            }
        }

        # P27: ClipRRect creating offscreen saveLayer
        if ($Line -match "(?:^|[^A-Za-z0-9_])ClipRRect\s*\(") {
            if (-not (& $IsSuppressed $LineNum "P27")) {
                Add-Finding -File $FileItem.FullName -Line $LineNum -Severity "LOW" -TrapId "P27" `
                    -Message "ClipRRect introduces clipping overhead. Prefer BoxDecoration(borderRadius: ...) where clipping child content is not required."
            }
        }
    }

    # W01, W03, W06, W14: Disposal pairing checks scoped to State classes & their dispose() methods
    if ($Content -match "class\s+\w+\s+extends\s+State<") {
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

        for ($s = 0; $s -lt $TotalLines; $s++) {
            $SLine = $Lines[$s]
            if ($SLine -match "class\s+([A-Za-z0-9_]+)\s+extends\s+State<") {
                $StateClassStart = $s
                $StateDepth = 0
                $StateClassEnd = $TotalLines
                $ClassBody = ""

                # Find the end of this State class and collect its body (release calls are searched in the whole class)
                for ($k = $s; $k -lt $TotalLines; $k++) {
                    $KLine = $Lines[$k]
                    $KOpens = ($KLine.ToCharArray() | Where-Object { $_ -eq '{' }).Count
                    $KCloses = ($KLine.ToCharArray() | Where-Object { $_ -eq '}' }).Count
                    $ClassBody += $KLine + "`n"
                    $StateDepth += ($KOpens - $KCloses)
                    if ($StateDepth -eq 0 -and $KLine -match "\}") {
                        $StateClassEnd = $k
                        break
                    }
                }

                # Scan for resources created anywhere in this State class (fields, initState, didChangeDependencies, methods)
                for ($m = $StateClassStart; $m -le $StateClassEnd; $m++) {
                    $MLine = $Lines[$m]
                    $MLineNum = $m + 1

                    if ($MLine -match "^\s*//") { continue }

                    # W01: Controllers
                    foreach ($ctrl in $Controllers) {
                        if ($MLine -match "(?:^|[^A-Za-z0-9_])([A-Za-z0-9_]+)\s*=\s*(?:new\s+)?$ctrl(?:$|[^A-Za-z0-9_])") {
                            $VarName = $Matches[1]
                            if ($VarName -and $VarName -ne "new") {
                                $DisposeRegex = "(?:^|[^A-Za-z0-9_])$VarName\.dispose\s*\("
                                if ($ClassBody -notmatch $DisposeRegex) {
                                    if (-not (& $IsSuppressed $MLineNum "W01")) {
                                        Add-Finding -File $FileItem.FullName -Line $MLineNum -Severity "CRITICAL" -TrapId "W01" `
                                            -Message "Resource '$VarName' ($ctrl) is instantiated in State but never disposed via '$VarName.dispose()' in dispose()."
                                    }
                                }
                            }
                        }
                    }

                    # W14: StreamController
                    if ($MLine -match "(?:^|[^A-Za-z0-9_])([A-Za-z0-9_]+)\s*=\s*(?:new\s+)?StreamController(?:$|[^A-Za-z0-9_])") {
                        $VarName = $Matches[1]
                        if ($VarName -and $VarName -ne "new") {
                            $CloseRegex = "(?:^|[^A-Za-z0-9_])$VarName\.close\s*\("
                            if ($ClassBody -notmatch $CloseRegex) {
                                if (-not (& $IsSuppressed $MLineNum "W14")) {
                                    Add-Finding -File $FileItem.FullName -Line $MLineNum -Severity "CRITICAL" -TrapId "W14" `
                                        -Message "Stream sink '$VarName' (StreamController) must be closed via '$VarName.close()' in dispose()."
                                }
                            }
                        }
                    }

                    # W03: StreamSubscription
                    if ($MLine -match "(?:^|[^A-Za-z0-9_])([A-Za-z0-9_]+)\s*=[^;\n]*\.listen\s*\(") {
                        $VarName = $Matches[1]
                        if ($VarName) {
                            $CancelRegex = "(?:^|[^A-Za-z0-9_])$VarName(?:\?\.|\.)cancel\s*\("
                            if ($ClassBody -notmatch $CancelRegex) {
                                if (-not (& $IsSuppressed $MLineNum "W03")) {
                                    Add-Finding -File $FileItem.FullName -Line $MLineNum -Severity "CRITICAL" -TrapId "W03" `
                                        -Message "StreamSubscription '$VarName' is active but never cancelled via '$VarName.cancel()' in dispose()."
                                }
                            }
                        }
                    }

                    # W06: Timer
                    if ($MLine -match "(?:^|[^A-Za-z0-9_])([A-Za-z0-9_]+)\s*=\s*Timer(?:\.periodic)?\s*\(") {
                        $VarName = $Matches[1]
                        if ($VarName) {
                            $CancelRegex = "(?:^|[^A-Za-z0-9_])$VarName(?:\?\.|\.)cancel\s*\("
                            if ($ClassBody -notmatch $CancelRegex) {
                                if (-not (& $IsSuppressed $MLineNum "W06")) {
                                    Add-Finding -File $FileItem.FullName -Line $MLineNum -Severity "CRITICAL" -TrapId "W06" `
                                        -Message "Timer '$VarName' is running in event loop but never cancelled via '$VarName.cancel()' in dispose()."
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

# 2. Check pubspec.yaml for Up-to-Date Linter Package
$PubspecPath = Join-Path $ResolvedPath "pubspec.yaml"
$AnalysisPath = Join-Path $ResolvedPath "analysis_options.yaml"

$HasLinter = $false
$PubspecContent = ""
if (Test-Path $PubspecPath) {
    $PubspecContent = Get-Content $PubspecPath -Raw -Encoding UTF8
    if ($PubspecContent -match "(flutter_lints|very_good_analysis|lints|solid_lints)") {
        $HasLinter = $true
    }
}
if (-not $HasLinter -and (Test-Path $AnalysisPath)) {
    $AnalysisContent = Get-Content $AnalysisPath -Raw -Encoding UTF8
    if ($AnalysisContent -match "^\s*include:\s*") {
        $HasLinter = $true
    }
}

if (Test-Path $PubspecPath) {
    if (-not $HasLinter) {
        Add-Finding -File $PubspecPath -Line 1 -Severity "MEDIUM" -TrapId "LINT-01" `
            -Message "No standard linter package (flutter_lints, very_good_analysis, lints, solid_lints) or analysis_options.yaml include detected. Add a linter package to dev_dependencies."
    } elseif ($PubspecContent -match "flutter_lints:\s*[\^~]?[0-3]\.") {
        Add-Finding -File $PubspecPath -Line 1 -Severity "HIGH" -TrapId "LINT-02" `
            -Message "Outdated flutter_lints version (legacy 1.x-3.x). Upgrade to a current release (e.g., ^5.0.0 or ^6.0.0) matching your Dart SDK."
    }
}

# 3. Check Native Privacy Manifest Flags (strictly conditioned on Firebase dependencies)
$HasFirebaseAnalytics = $false
$HasFirebaseCrashlytics = $false
if ($PubspecContent) {
    if ($PubspecContent -match "(?:^|\s)firebase_analytics:") {
        $HasFirebaseAnalytics = $true
    }
    if ($PubspecContent -match "(?:^|\s)firebase_crashlytics:") {
        $HasFirebaseCrashlytics = $true
    }
}

$AndroidManifest = Join-Path $ResolvedPath "android\app\src\main\AndroidManifest.xml"
if (Test-Path $AndroidManifest) {
    $ManifestContent = Get-Content $AndroidManifest -Raw -Encoding UTF8
    if ($HasFirebaseAnalytics -and $ManifestContent -notmatch 'android:name="firebase_analytics_collection_enabled"\s*android:value="false"') {
        Add-Finding -File $AndroidManifest -Line 1 -Severity "CRITICAL" -TrapId "GDPR-01" `
            -Message "Missing native AndroidManifest default: firebase_analytics_collection_enabled must be false."
    }
    if ($HasFirebaseCrashlytics -and $ManifestContent -notmatch 'android:name="firebase_crashlytics_collection_enabled"\s*android:value="false"') {
        Add-Finding -File $AndroidManifest -Line 1 -Severity "CRITICAL" -TrapId "GDPR-02" `
            -Message "Missing native AndroidManifest default: firebase_crashlytics_collection_enabled must be false."
    }
}

$IosPlist = Join-Path $ResolvedPath "ios\Runner\Info.plist"
if (Test-Path $IosPlist) {
    $PlistContent = Get-Content $IosPlist -Raw -Encoding UTF8
    if ($HasFirebaseAnalytics -and $PlistContent -notmatch '<key>FIREBASE_ANALYTICS_COLLECTION_ENABLED</key>\s*<false/>') {
        Add-Finding -File $IosPlist -Line 1 -Severity "CRITICAL" -TrapId "GDPR-03" `
            -Message "Missing native Info.plist default: FIREBASE_ANALYTICS_COLLECTION_ENABLED must be <false/>."
    }
    if ($HasFirebaseCrashlytics -and $PlistContent -notmatch '<key>FirebaseCrashlyticsCollectionEnabled</key>\s*<false/>') {
        Add-Finding -File $IosPlist -Line 1 -Severity "CRITICAL" -TrapId "GDPR-04" `
            -Message "Missing native Info.plist default: FirebaseCrashlyticsCollectionEnabled must be <false/>."
    }
}

# 4. Output Results
if ($Json) {
    if ($Findings.Count -eq 0) {
        "[]"
    } else {
        $OutputObj = @()
        foreach ($f in $Findings) {
            $OutputObj += [PSCustomObject]@{
                severity = $f.Severity
                trapId   = $f.TrapId
                file     = $f.File
                line     = $f.Line
                message  = $f.Message
            }
        }
        $JsonStr = $OutputObj | ConvertTo-Json -Depth 3
        if ($OutputObj.Count -eq 1) {
            "[$JsonStr]"
        } else {
            $JsonStr
        }
    }
} else {
    Write-Host "=================================================="
    Write-Host " Flutter Ultimate Static Code Audit"
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

    foreach ($f in $Findings) {
        $Color = switch ($f.Severity) {
            "CRITICAL" { "Red" }
            "HIGH"     { "Magenta" }
            "MEDIUM"   { "Yellow" }
            "LOW"      { "Cyan" }
            Default    { "White" }
        }
        Write-Host "[$($f.Severity)] $($f.TrapId) in $($f.File):$($f.Line)" -ForegroundColor $Color
        Write-Host "       $($f.Message)"
    }

    Write-Host "--------------------------------------------------"
    Write-Host " Audit Summary: $CriticalCount Critical, $HighCount High, $MediumCount Medium, $LowCount Low"
    Write-Host "--------------------------------------------------"
}

$HasCritical = ($Findings | Where-Object { $_.Severity -in @("CRITICAL", "HIGH") }).Count -gt 0

if ($Strict -and $Findings.Count -gt 0) {
    exit 1
} elseif ($HasCritical) {
    exit 1
} else {
    exit 0
}
