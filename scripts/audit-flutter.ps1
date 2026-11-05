<#
.SYNOPSIS
    Deterministic static code analyzer for Flutter/Dart codebases.
    Enforces 60/120 FPS performance rules, memory disposal pairing,
    BuildContext async gap protections, and GDPR/RODO native consent flags.

.PARAMETER TargetPath
    Path to the Flutter project root (default: current directory).

.PARAMETER Json
    Switch to output findings in machine-readable JSON format for CI/CD.

.PARAMETER Sarif
    Switch to output findings as SARIF 2.1.0 (GitHub code scanning). Mutually exclusive with -Json.

.PARAMETER Strict
    Exit with code 1 on any warning (Medium/Low) in addition to errors (Critical/High).
#>
[CmdletBinding()]
param(
    [Alias("target")]
    [string]$TargetPath = ".",
    [switch]$Json,
    [switch]$Sarif,
    [switch]$Strict,
    [ValidateSet("CRITICAL","HIGH","MEDIUM","LOW")][string]$FailOn = "CRITICAL"
)

$ErrorActionPreference = "Stop"
$ScriptVersion = "1.8.0"
if ($Json -and $Sarif) {
    [Console]::Error.WriteLine("Error: -Json and -Sarif are mutually exclusive")
    exit 2
}

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
    foreach ($existing in $Findings) {
        if ($existing.File -eq $RelativeFile -and $existing.Line -eq $Line -and $existing.TrapId -eq $TrapId -and $existing.Message -eq $Message) { return }
    }
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
    $Rel -notmatch "(?:^|[\\/])(build|\.dart_tool|\.git)(?:[\\/]|`$)" -and $Rel -notmatch "^(test|integration_test)[\\/]" -and $_.Name -notmatch "\.(g|freezed)\.dart`$"
}

foreach ($FileItem in $DartFiles) {
    $Content = Get-Content $FileItem.FullName -Raw -Encoding UTF8
    $Lines = $Content -split "\r?\n"
    $TotalLines = $Lines.Length

    # Brace depth before/after every line (comment-only lines ignored); shared by K01 and the W pass
    $DepthBefore = New-Object int[] $TotalLines
    $DepthAfter = New-Object int[] $TotalLines
    $CurD = 0
    for ($q = 0; $q -lt $TotalLines; $q++) {
        $DepthBefore[$q] = $CurD
        if ($Lines[$q] -notmatch "^\s*//") {
            $CurD += ($Lines[$q].Split('{').Count - 1) - ($Lines[$q].Split('}').Count - 1)
        }
        $DepthAfter[$q] = $CurD
    }

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
        if ($Line -match "(?:^|\s)await\s+" -and $Line -notmatch "=>.*(?:^|\s)await\s") {
            # Enclosing function body = nearest preceding block opener that is not control flow
            # and sits shallower than the await. The scan stops where that body closes.
            $AwaitDepth = $DepthBefore[$i]
            $BodyDepth = -1
            for ($h = $i; $h -ge 0; $h--) {
                if ($DepthAfter[$h] -gt $DepthBefore[$h] -and $DepthBefore[$h] -lt $AwaitDepth) {
                    if ($Lines[$h] -notmatch "^\s*(?:if|else|for|while|do|switch|try|catch|finally|case|default|\})(?:[^A-Za-z0-9_]|$)") {
                        $BodyDepth = $DepthBefore[$h] + 1
                        break
                    }
                }
            }
            if ($BodyDepth -lt 0) { $BodyDepth = 0 }

            # Skip the rest of the awaited statement: a multi-line argument list holds
            # callbacks (dialog builders, onPressed) that run inside the call, not after it.
            $ScanFrom = $i + 1
            $Paren = ($Line.Split('(').Count - 1) - ($Line.Split(')').Count - 1)
            if ($Paren -gt 0) {
                for ($j = $i + 1; $j -lt $TotalLines; $j++) {
                    $Paren += ($Lines[$j].Split('(').Count - 1) - ($Lines[$j].Split(')').Count - 1)
                    if ($Paren -le 0) { $ScanFrom = $j + 1; break }
                }
            }

            $InMountedIf = $false
            $MountedIfDepth = 0
            $PendingNegMountedGuard = $false
            $PendingNegDepth = 0
            $Guarded = $false

            for ($j = $ScanFrom; $j -lt $TotalLines; $j++) {
                $FLine = $Lines[$j]
                $FLineNum = $j + 1
                $FBefore = $DepthBefore[$j]
                $FAfter = $DepthAfter[$j]

                if ($FBefore -lt $BodyDepth) { break }
                if ($FLine -match "^\s*//") { continue }
                # Leaving the block that holds the await into its "else" / "else if" sibling: that branch never
                # runs after this await. Handles both "} else {" on one line and "else {" on its own line.
                if ($FLine -match "(?:^|[^A-Za-z0-9_])else(?:[^A-Za-z0-9_]|$)" -and $FLine.Contains("{") -and
                    ($FBefore -lt $AwaitDepth -or $FLine -match "^\s*\}")) {
                    $ElseTarget = $FAfter - 1
                    for ($e = $j + 1; $e -lt $TotalLines; $e++) {
                        if ($DepthAfter[$e] -le $ElseTarget) { $j = $e; break }
                    }
                    continue
                }

                if ($InMountedIf -and $FBefore -lt $MountedIfDepth) { $InMountedIf = $false }
                if ($PendingNegMountedGuard -and $FBefore -lt $PendingNegDepth) { $PendingNegMountedGuard = $false }

                if ($FLine -match "if\s*\(.*!\s*(?:context\.)?mounted.*\)\s*(\{\s*)?(return|throw)") {
                    $Guarded = $true
                    break
                }

                if ($FLine -match "if\s*\(.*!\s*(?:context\.)?mounted.*\)\s*\{" -and $FAfter -gt $FBefore) {
                    $PendingNegMountedGuard = $true
                    $PendingNegDepth = $FAfter
                } elseif ($PendingNegMountedGuard -and $FLine -match "(?:^|[^A-Za-z0-9_])(?:return|throw)(?:[^A-Za-z0-9_]|$)") {
                    $Guarded = $true
                    break
                }

                $LineGuarded = $false
                if ($FLine -match "if\s*\((?:.*[^A-Za-z0-9_.!])?(?:context\.)?mounted(?:[^A-Za-z0-9_]|$)") {
                    $LineGuarded = $true
                    if ($FAfter -gt $FBefore) {
                        $InMountedIf = $true
                        $MountedIfDepth = $FAfter
                    }
                }

                $DangerOp = ""
                if ($FLine -match "(?:^|[^A-Za-z0-9_.])setState\s*\(") {
                    $DangerOp = "setState()"
                } elseif ($FLine -match "Navigator\.(?:push|pop|of|maybePop|pushNamed|pushReplacement|popUntil)\s*\(") {
                    $DangerOp = "Navigator"
                } elseif ($FLine -match "(?:showDialog|showModalBottomSheet|showBottomSheet|showMenu|showDatePicker|showTimePicker)(?:<[^>]*>)?\s*\(") {
                    $DangerOp = "Dialog"
                } elseif ($FLine -match "(?:ScaffoldMessenger\.of|Theme\.of|MediaQuery\.of)\s*\(\s*context") {
                    $DangerOp = "Context theme/messenger lookup"
                } elseif ($FLine -match "(?:^|[^A-Za-z0-9_.])context\.(?:read|watch|select|push|pop|go)[A-Za-z0-9_]*\s*[<(]") {
                    $DangerOp = "context extension method"
                }

                if ($DangerOp -ne "" -and -not $Guarded -and -not $InMountedIf -and -not $LineGuarded) {
                    if (-not (& $IsSuppressed $FLineNum "K01")) {
                        Add-Finding -File $FileItem.FullName -Line $FLineNum -Severity "CRITICAL" -TrapId "K01" `
                            -Message "BuildContext ($DangerOp) used after an await in the same function with no mounted guard in between (static heuristic: scans this function body only)."
                    }
                    break
                }

                if ($FAfter -lt $BodyDepth) { break }
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
                $StateClassEnd = $TotalLines - 1
                $ClassBase = $DepthBefore[$s]
                for ($k = $s + 1; $k -lt $TotalLines; $k++) {
                    if ($DepthAfter[$k] -le $ClassBase) { $StateClassEnd = $k; break }
                }

                # Pass 1: field declarations, calls made from dispose(), and every release call with its enclosing method
                $FieldDecls = @{}
                $DisposeCalls = @{}
                $ReleaseIndex = @{}   # "var:action" -> hashtable of method names
                $CurMethod = ""
                for ($m = $StateClassStart + 1; $m -le $StateClassEnd; $m++) {
                    $MLine = $Lines[$m]
                    if ($MLine -match "^\s*//") { continue }
                    if ($DepthBefore[$m] -eq ($ClassBase + 1)) {
                        if ($MLine -match "([A-Za-z_][A-Za-z0-9_]*)\s*\(") { $CurMethod = $Matches[1] }
                        foreach ($fm in [regex]::Matches($MLine, "([A-Za-z_][A-Za-z0-9_]*)\s*(?:=|;)")) { $FieldDecls[$fm.Groups[1].Value] = $true }
                    }
                    if ($CurMethod -eq "dispose") {
                        foreach ($cm in [regex]::Matches($MLine, "([A-Za-z_][A-Za-z0-9_]*)\s*\(")) { $DisposeCalls[$cm.Groups[1].Value] = $true }
                    }
                    foreach ($rm in [regex]::Matches($MLine, "([A-Za-z_][A-Za-z0-9_]*)(?:\?\.|\.)(dispose|cancel|close)\s*\(")) {
                        $key = $rm.Groups[1].Value + ":" + $rm.Groups[2].Value
                        if (-not $ReleaseIndex.ContainsKey($key)) { $ReleaseIndex[$key] = @{} }
                        $ReleaseIndex[$key][$CurMethod] = $true
                    }
                }

                $StateOwned = {
                    param($VarName, $AtFieldLevel)
                    if ($AtFieldLevel) { return $true }
                    return $FieldDecls.ContainsKey($VarName)
                }
                $ReleasedWhere = {
                    param($VarName, $Action)
                    $key = "${VarName}:${Action}"
                    if ($ReleaseIndex.ContainsKey($key)) { return @($ReleaseIndex[$key].Keys | Sort-Object) }
                    return @()
                }
                $ReachableFromDispose = {
                    param($Methods)
                    foreach ($mm in $Methods) {
                        if ($mm -eq "dispose") { return $true }
                        if ($DisposeCalls.ContainsKey($mm)) { return $true }
                    }
                    return $false
                }
                $ReleaseMsg = {
                    param($VarName, $Kind, $Action, $Where)
                    if ($Where.Count -gt 0) {
                        $list = ($Where -join "(), ")
                        return "Resource '$VarName' ($Kind) is created by this State; '$VarName.$Action()' exists only in $list(), which dispose() never calls (static heuristic: verify ownership and cleanup path)."
                    }
                    return "Resource '$VarName' ($Kind) is created by this State but '$VarName.$Action()' was not found in dispose() or in any method dispose() calls (static heuristic: verify ownership and cleanup path)."
                }

                # Pass 2: resources created by this State (field initializer, or assignment to a declared field)
                for ($m = $StateClassStart + 1; $m -le $StateClassEnd; $m++) {
                    $MLine = $Lines[$m]
                    $MLineNum = $m + 1
                    if ($MLine -match "^\s*//") { continue }
                    $AtFieldLevel = ($DepthBefore[$m] -eq ($ClassBase + 1))

                    foreach ($ctrl in $Controllers) {
                        if ($MLine -match "(?:^|[^A-Za-z0-9_])([A-Za-z0-9_]+)\s*=\s*(?:new\s+)?$ctrl(?:$|[^A-Za-z0-9_])") {
                            $VarName = $Matches[1]
                            if ($VarName -and $VarName -ne "new" -and (& $StateOwned $VarName $AtFieldLevel)) {
                                $Where = @(& $ReleasedWhere $VarName "dispose")
                                if (-not (& $ReachableFromDispose $Where)) {
                                    if (-not (& $IsSuppressed $MLineNum "W01")) {
                                        Add-Finding -File $FileItem.FullName -Line $MLineNum -Severity "CRITICAL" -TrapId "W01" -Message (& $ReleaseMsg $VarName $ctrl "dispose" $Where)
                                    }
                                }
                            }
                        }
                    }

                    if ($MLine -match "(?:^|[^A-Za-z0-9_])([A-Za-z0-9_]+)\s*=\s*(?:new\s+)?StreamController(?:$|[^A-Za-z0-9_])") {
                        $VarName = $Matches[1]
                        if ($VarName -and $VarName -ne "new" -and (& $StateOwned $VarName $AtFieldLevel)) {
                            $Where = @(& $ReleasedWhere $VarName "close")
                            if (-not (& $ReachableFromDispose $Where)) {
                                if (-not (& $IsSuppressed $MLineNum "W14")) {
                                    Add-Finding -File $FileItem.FullName -Line $MLineNum -Severity "CRITICAL" -TrapId "W14" -Message (& $ReleaseMsg $VarName "StreamController" "close" $Where)
                                }
                            }
                        }
                    }

                    if ($MLine -match "(?:^|[^A-Za-z0-9_])([A-Za-z0-9_]+)\s*=[^;\n]*\.listen\s*\(") {
                        $VarName = $Matches[1]
                        if ($VarName -and (& $StateOwned $VarName $AtFieldLevel)) {
                            $Where = @(& $ReleasedWhere $VarName "cancel")
                            if (-not (& $ReachableFromDispose $Where)) {
                                if (-not (& $IsSuppressed $MLineNum "W03")) {
                                    Add-Finding -File $FileItem.FullName -Line $MLineNum -Severity "CRITICAL" -TrapId "W03" -Message (& $ReleaseMsg $VarName "StreamSubscription" "cancel" $Where)
                                }
                            }
                        }
                    }

                    if ($MLine -match "(?:^|[^A-Za-z0-9_])([A-Za-z0-9_]+)\s*=\s*Timer(?:\.periodic)?\s*\(") {
                        $VarName = $Matches[1]
                        if ($VarName -and (& $StateOwned $VarName $AtFieldLevel)) {
                            $Where = @(& $ReleasedWhere $VarName "cancel")
                            if (-not (& $ReachableFromDispose $Where)) {
                                if (-not (& $IsSuppressed $MLineNum "W06")) {
                                    Add-Finding -File $FileItem.FullName -Line $MLineNum -Severity "CRITICAL" -TrapId "W06" -Message (& $ReleaseMsg $VarName "Timer" "cancel" $Where)
                                }
                            }
                        }
                    }
                }

                # W21: SingleTickerProviderStateMixin vends exactly one Ticker. The class header may wrap, so read it up to its "{".
                $ClassHeader = ""
                for ($h = $StateClassStart; $h -le $StateClassEnd; $h++) {
                    $ClassHeader += $Lines[$h] + " "
                    if ($Lines[$h] -match "\{") { break }
                }
                if ($ClassHeader -match "(?:^|[^A-Za-z0-9_])SingleTickerProviderStateMixin(?:$|[^A-Za-z0-9_])") {
                    $VsyncLines = @()
                    for ($m = $StateClassStart + 1; $m -le $StateClassEnd; $m++) {
                        $MLine = $Lines[$m]
                        if ($MLine -match "^\s*//") { continue }
                        if ($MLine -match "(?:^|[^A-Za-z0-9_])vsync:\s*this(?:$|[^A-Za-z0-9_])") { $VsyncLines += ($m + 1) }
                    }
                    if ($VsyncLines.Count -ge 2) {
                        $SecondVsync = $VsyncLines[1]
                        if (-not (& $IsSuppressed $SecondVsync "W21")) {
                            Add-Finding -File $FileItem.FullName -Line $SecondVsync -Severity "CRITICAL" -TrapId "W21" `
                                -Message "State mixes in SingleTickerProviderStateMixin but passes 'vsync: this' $($VsyncLines.Count) times (lines $($VsyncLines -join ' ')). The second Ticker throws 'multiple tickers were created' in debug and silently replaces the first in release. Use TickerProviderStateMixin."
                        }
                    }
                }

                # W05: listen()/addListener() in didChangeDependencies() re-registers on every dependency change unless the previous registration is torn down in the same method.
                $DdcStart = -1
                $DdcEnd = -1
                for ($m = $StateClassStart + 1; $m -le $StateClassEnd; $m++) {
                    if ($DepthBefore[$m] -eq ($ClassBase + 1) -and $Lines[$m] -match "(?:^|[^A-Za-z0-9_])didChangeDependencies\s*\(") {
                        $DdcStart = $m
                        $DdcEnd = $StateClassEnd
                        for ($k = $m; $k -le $StateClassEnd; $k++) {
                            if ($k -gt $m -and $DepthAfter[$k] -le ($ClassBase + 1)) { $DdcEnd = $k; break }
                        }
                        break
                    }
                }
                if ($DdcStart -ge 0) {
                    $DdcBodyLines = @()
                    for ($m = $DdcStart; $m -le $DdcEnd; $m++) {
                        if ($Lines[$m] -match "^\s*//") { continue }
                        $DdcBodyLines += $Lines[$m]
                    }
                    $DdcBody = ($DdcBodyLines -join "`n")
                    # A run-once guard (if (!_done) { _done = true; ... } or if (_first) { _first = false; ... }) makes the method body execute once.
                    $DdcOnce = $false
                    if ($DdcBody -match "if\s*\(\s*!\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)") {
                        $Flag = $Matches[1]
                        if ($DdcBody -match "(?:^|[^A-Za-z0-9_])$Flag\s*=\s*true") { $DdcOnce = $true }
                    }
                    if ($DdcBody -match "if\s*\(\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)") {
                        $Flag = $Matches[1]
                        if ($DdcBody -match "(?:^|[^A-Za-z0-9_])$Flag\s*=\s*false") { $DdcOnce = $true }
                    }
                    if ($DdcOnce) { $DdcEnd = $DdcStart - 1 }
                    for ($m = $DdcStart; $m -le $DdcEnd; $m++) {
                        $MLine = $Lines[$m]
                        $MLineNum = $m + 1
                        if ($MLine -match "^\s*//") { continue }
                        if ($MLine -match "(?:^|[^A-Za-z0-9_])([A-Za-z0-9_]+)\s*=[^;\n]*\.listen\s*\(") {
                            $VarName = $Matches[1]
                            if ($VarName -and (& $StateOwned $VarName $false)) {
                                $ReCancel = "(?:^|[^A-Za-z0-9_])" + [regex]::Escape($VarName) + "(?:\?\.|!\.|\.)cancel\s*\("
                                $ReNull = "(?:^|[^A-Za-z0-9_])" + [regex]::Escape($VarName) + "\s*[!=]=\s*null|null\s*[!=]=\s*" + [regex]::Escape($VarName) + "(?:$|[^A-Za-z0-9_])"
                                if (-not ($DdcBody -match $ReCancel) -and -not ($DdcBody -match $ReNull)) {
                                    if (-not (& $IsSuppressed $MLineNum "W05")) {
                                        Add-Finding -File $FileItem.FullName -Line $MLineNum -Severity "HIGH" -TrapId "W05" `
                                            -Message "Subscription '$VarName' is opened in didChangeDependencies() without cancelling the previous one in the same method; didChangeDependencies() runs again on every dependency change, so the listener is registered repeatedly (static heuristic: cancel first, or use ??= / a null check)."
                                    }
                                }
                            }
                        }
                        if ($MLine -match "\)\s*\.addListener\s*\(") {
                            # Receiver is a call result (context.read<T>().addListener, Listenable.merge([...]).addListener): nothing to pair a removeListener() with.
                            if (-not (& $IsSuppressed $MLineNum "W05")) {
                                Add-Finding -File $FileItem.FullName -Line $MLineNum -Severity "HIGH" -TrapId "W05" `
                                    -Message "addListener() is called on a call result in didChangeDependencies(); the previous listener cannot be removed because the receiver is not kept, and didChangeDependencies() runs again on every dependency change (static heuristic: keep the notifier in a field, remove the old listener, then add)."
                            }
                        } elseif ($MLine -match "(?:^|[^A-Za-z0-9_])([A-Za-z0-9_.]+)\.addListener\s*\(") {
                            $Recv = $Matches[1]
                            $ReRemove = "(?:^|[^A-Za-z0-9_])" + [regex]::Escape($Recv) + "\.removeListener\s*\("
                            if (-not ($DdcBody -match $ReRemove)) {
                                if (-not (& $IsSuppressed $MLineNum "W05")) {
                                    Add-Finding -File $FileItem.FullName -Line $MLineNum -Severity "HIGH" -TrapId "W05" `
                                        -Message "'$Recv.addListener()' is called in didChangeDependencies() without a matching removeListener() in the same method; didChangeDependencies() runs again on every dependency change, so the listener is added repeatedly (static heuristic: remove the previous listener first)."
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
$RuleDesc = @{
    "K01" = "BuildContext used after an await with no mounted guard in between"
    "W01" = "Controller created by a State without dispose() reachable from dispose()"
    "W03" = "StreamSubscription without cancel() reachable from dispose()"
    "W05" = "listen()/addListener() in didChangeDependencies() without tearing down the previous registration"
    "W06" = "Timer without cancel() reachable from dispose()"
    "W14" = "StreamController without close() reachable from dispose()"
    "W21" = "SingleTickerProviderStateMixin used for more than one Ticker"
    "P03" = "Helper _buildX() method instead of a StatelessWidget"
    "P07" = "Broad MediaQuery.of(context) dependency"
    "P12" = "Future/Stream created inline in FutureBuilder/StreamBuilder inside build()"
    "P19" = "shrinkWrap: true"
    "P21" = "IntrinsicHeight/IntrinsicWidth speculative layout"
    "P26" = "Opacity with a fractional value"
    "P27" = "ClipRRect"
    "P32" = "Paint or Path allocated inside build()/paint()"
    "LINT-01" = "No linter package and no analysis_options.yaml include"
    "LINT-02" = "Outdated flutter_lints"
    "GDPR-01" = "AndroidManifest: firebase_analytics_collection_enabled not false"
    "GDPR-02" = "AndroidManifest: firebase_crashlytics_collection_enabled not false"
    "GDPR-03" = "Info.plist: FIREBASE_ANALYTICS_COLLECTION_ENABLED not false"
    "GDPR-04" = "Info.plist: FirebaseCrashlyticsCollectionEnabled not false"
}
$SarifLevel = @{ CRITICAL = "error"; HIGH = "warning"; MEDIUM = "warning"; LOW = "note" }

if ($Sarif) {
    # SARIF 2.1.0 (GitHub code scanning): one run, rules = the trap ids that occurred, results in scan order.
    $RuleIds = @()
    foreach ($f in $Findings) { if ($RuleIds -notcontains $f.TrapId) { $RuleIds += $f.TrapId } }
    $Rules = @()
    foreach ($r in $RuleIds) {
        $d = if ($RuleDesc.ContainsKey($r)) { $RuleDesc[$r] } else { $r }
        $Rules += [ordered]@{ id = $r; shortDescription = [ordered]@{ text = $d } }
    }
    $Results = @()
    foreach ($f in $Findings) {
        $Results += [ordered]@{
            ruleId = $f.TrapId
            level = $SarifLevel[$f.Severity]
            message = [ordered]@{ text = $f.Message }
            locations = @([ordered]@{ physicalLocation = [ordered]@{ artifactLocation = [ordered]@{ uri = ($f.File -replace "\\", "/") }; region = [ordered]@{ startLine = [int]$f.Line } } })
        }
    }
    $Doc = [ordered]@{
        version = "2.1.0"
        '$schema' = "https://json.schemastore.org/sarif-2.1.0.json"
        runs = @([ordered]@{
            tool = [ordered]@{ driver = [ordered]@{ name = "flutter-ultimate"; version = $ScriptVersion; informationUri = "https://github.com/PawelSzymanski89/flutter-ultimate"; rules = @($Rules) } }
            results = @($Results)
        })
    }
    ConvertTo-Json -InputObject $Doc -Depth 12 -Compress
} elseif ($Json) {
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

# Exit code: 1 when any finding is at or above -FailOn (default CRITICAL); -Strict fails on any finding.
$Rank = @{ CRITICAL = 4; HIGH = 3; MEDIUM = 2; LOW = 1 }
$Threshold = if ($Strict) { 1 } else { $Rank[$FailOn] }
$Fail = @($Findings | Where-Object { $Rank[$_.Severity] -ge $Threshold }).Count -gt 0
if ($Fail) { exit 1 } else { exit 0 }
