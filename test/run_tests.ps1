<#
.SYNOPSIS
    Test runner for Flutter Ultimate Skill and Static Code Analyzer.
.DESCRIPTION
    Validates SKILL.md specification limits, Claude Code plugin packaging,
    CLI contracts, single-finding JSON array schema, fixtures (positive, negative, suppression),
    and cross-platform Bash <-> PowerShell JSON output parity.
#>

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir

$Passed = 0
$Failed = 0

function Report-Assert($Name, [bool]$Condition, $Details = "") {
    if ($Condition) {
        Write-Host "  [PASS] $Name" -ForegroundColor Green
        $script:Passed++
    } else {
        Write-Host "  [FAIL] $Name" -ForegroundColor Red
        if ($Details) {
            Write-Host "         $Details" -ForegroundColor Yellow
        }
        $script:Failed++
    }
}

Write-Host "=================================================="
Write-Host " Flutter Ultimate Test Suite (PowerShell)"
Write-Host " Project: $ProjectRoot"
Write-Host "=================================================="

# 1. Validate SKILL.md & Plugin Architecture
Write-Host "`n[1/6] Validating SKILL.md & Plugin Architecture..." -ForegroundColor Cyan
$SkillPath = Join-Path $ProjectRoot "SKILL.md"
if (-not (Test-Path $SkillPath)) {
    Report-Assert "SKILL.md exists" $false "File not found at $SkillPath"
} else {
    $SkillLines = Get-Content $SkillPath -Encoding UTF8
    Report-Assert "SKILL.md exists" $true
    Report-Assert "SKILL.md line count < 500 lines" ($SkillLines.Length -lt 500) "Current line count: $($SkillLines.Length)"

    $LongLines = @()
    for ($i = 0; $i -lt $SkillLines.Length; $i++) {
        if ($SkillLines[$i].Length -gt 300) {
            $LongLines += ($i + 1)
        }
    }
    Report-Assert "SKILL.md max line length <= 300 chars" ($LongLines.Count -eq 0) "Lines exceeding 300 chars: $($LongLines -join ', ')"

    $SkillContent = $SkillLines -join "`n"
    $HasFrontmatter = $SkillContent -match "^---\r?\n([\s\S]*?)\r?\n---"
    Report-Assert "SKILL.md contains YAML frontmatter" $HasFrontmatter
    if ($HasFrontmatter) {
        Report-Assert "SKILL.md has name: flutter-ultimate" ($SkillContent -match "name:\s*flutter-ultimate")
        Report-Assert "SKILL.md has description" ($SkillContent -match "description:\s*.+")
        Report-Assert "allowed-tools does not contain PowerShell" (-not ($SkillContent -match "allowed-tools:.*PowerShell"))
    }
}

# Validate Plugin Packaging files
$PluginManifest = Join-Path $ProjectRoot ".claude-plugin\plugin.json"
$MarketplaceManifest = Join-Path $ProjectRoot ".claude-plugin\marketplace.json"
$PluginSkill = Join-Path $ProjectRoot "skills\flutter-ultimate\SKILL.md"
$CmdAudit = Join-Path $ProjectRoot "commands\audit.md"
$CmdReview = Join-Path $ProjectRoot "commands\review.md"

Report-Assert "plugin.json exists" (Test-Path $PluginManifest)
Report-Assert "marketplace.json exists" (Test-Path $MarketplaceManifest)
Report-Assert "skills/flutter-ultimate/SKILL.md exists" (Test-Path $PluginSkill)

if (Test-Path $PluginSkill) {
    $SkillHash = (Get-FileHash $SkillPath -Algorithm SHA256).Hash
    $PluginSkillHash = (Get-FileHash $PluginSkill -Algorithm SHA256).Hash
    Report-Assert "SKILL.md and skills/flutter-ultimate/SKILL.md are synchronized" ($SkillHash -eq $PluginSkillHash)
}

Report-Assert "commands/audit.md exists" (Test-Path $CmdAudit)
if (Test-Path $CmdAudit) {
    $CmdAuditContent = Get-Content $CmdAudit -Raw -Encoding UTF8
    Report-Assert "commands/audit.md has description" ($CmdAuditContent -match "description:\s*.+")
}

Report-Assert "commands/review.md exists" (Test-Path $CmdReview)
if (Test-Path $CmdReview) {
    $CmdReviewContent = Get-Content $CmdReview -Raw -Encoding UTF8
    Report-Assert "commands/review.md has description" ($CmdReviewContent -match "description:\s*.+")
}

# Validate and test activate.js hook
$HookActivate = Join-Path $ProjectRoot "hooks\activate.js"
$PositiveDir = Join-Path $ProjectRoot "test\fixtures\positive"
Report-Assert "hooks/activate.js exists" (Test-Path $HookActivate)
if (Test-Path $HookActivate) {
    $ActNonFlutter = (& node $HookActivate 2>&1) -join "`n"
    Report-Assert "activate.js in non-Flutter directory reports namespaced commands" ($ActNonFlutter -match "/flutter-ultimate:review")

    Push-Location $PositiveDir
    try {
        $ActFlutter = (& node $HookActivate 2>&1) -join "`n"
        Report-Assert "activate.js in Flutter workspace activates full mode" ($ActFlutter -match "FLUTTER ULTIMATE MODE ACTIVE")
    } finally {
        Pop-Location
    }
}

# 2. Test CLI Contract & Error Handling
Write-Host "`n[2/6] Testing CLI Contract & Error Handling..." -ForegroundColor Cyan
$AuditPs1 = Join-Path $ProjectRoot "scripts\audit-flutter.ps1"

$NonExistentDir = Join-Path $ProjectRoot "non_existent_directory"
$InvOutput = & $AuditPs1 -Target $NonExistentDir -Json 2>&1
$InvExit = $LASTEXITCODE
Report-Assert "Non-existent target directory exits with code 2" ($InvExit -eq 2) "Actual exit code: $InvExit"

# 3. Test audit-flutter.ps1 on Positive Fixture
Write-Host "`n[3/6] Testing audit-flutter.ps1 Positive Fixture..." -ForegroundColor Cyan
$PositiveDir = Join-Path $ProjectRoot "test\fixtures\positive"

$PosOutput = & $AuditPs1 -Target $PositiveDir -Json 2>&1
$PosExit = $LASTEXITCODE
Report-Assert "Positive fixture returns exit code 1 (violations detected)" ($PosExit -eq 1) "Actual exit code: $PosExit"

try {
    $PosJson = $PosOutput | ConvertFrom-Json
    $DetectedTraps = @($PosJson | ForEach-Object { $_.trapId })

    $ExpectedTraps = @(
        "P03", "P32", "P07", "P12", "P19", "P21", "P26", "P27",
        "K01", "W01", "W03", "W05", "W06", "W14", "W21",
        "LINT-02", "GDPR-01", "GDPR-02", "GDPR-03", "GDPR-04"
    )

    foreach ($trap in $ExpectedTraps) {
        $found = $DetectedTraps -contains $trap
        Report-Assert "Positive fixture detects $trap" $found
    }
} catch {
    Report-Assert "Positive fixture returns valid JSON" $false $_.Exception.Message
}

# 4. Test Single-Finding JSON Array Contract & Strict Mode
Write-Host "`n[4/6] Testing Single-Finding JSON Array Contract & Strict Mode..." -ForegroundColor Cyan
$SingleDir = Join-Path $ProjectRoot "test\fixtures\single"
$SingleOutput = & $AuditPs1 -Target $SingleDir -Json 2>&1
$SingleExit = $LASTEXITCODE
Report-Assert "Single finding (MEDIUM) without -Strict returns exit code 0" ($SingleExit -eq 0) "Actual exit code: $SingleExit"

$SingleStrictOutput = & $AuditPs1 -Target $SingleDir -Json -Strict 2>&1
$SingleStrictExit = $LASTEXITCODE
Report-Assert "Single finding with -Strict returns exit code 1" ($SingleStrictExit -eq 1) "Actual exit code: $SingleStrictExit"

$SingleStr = ($SingleOutput -join "`n").Trim()
$IsArrayFormat = ($SingleStr.StartsWith("[") -and $SingleStr.EndsWith("]"))
Report-Assert "Single finding outputs valid JSON array [{...}]" $IsArrayFormat "Output: $SingleStr"

try {
    $SingleJson = $SingleOutput | ConvertFrom-Json
    Report-Assert "Single finding JSON has exactly 1 element" ($SingleJson.Count -eq 1) "Count: $($SingleJson.Count)"
} catch {
    Report-Assert "Single finding JSON parse" $false $_.Exception.Message
}

# 4b. SARIF output contract
Write-Host "`n[4b/6] Testing SARIF output..." -ForegroundColor Cyan
$PluginVersion = (Get-Content (Join-Path $ProjectRoot ".claude-plugin\plugin.json") -Raw | ConvertFrom-Json).version
$SarifPos = (& $AuditPs1 -Target $PositiveDir -Sarif 2>&1) -join "`n"
try {
    $SarifDoc = $SarifPos | ConvertFrom-Json
    $Run = $SarifDoc.runs[0]
    $RuleIds = @($Run.tool.driver.rules | ForEach-Object { $_.id })
    $AllRuled = $true
    foreach ($r in $Run.results) { if ($RuleIds -notcontains $r.ruleId) { $AllRuled = $false } }
    Report-Assert "Positive fixture -Sarif is SARIF 2.1.0 with one result per JSON finding and rules for every ruleId" ($SarifDoc.version -eq "2.1.0" -and @($Run.results).Count -eq @($PosJson).Count -and $AllRuled) "version=$($SarifDoc.version) results=$(@($Run.results).Count) json=$(@($PosJson).Count)"
    Report-Assert "SARIF driver.version equals plugin.json version" ($Run.tool.driver.version -eq $PluginVersion) "driver=$($Run.tool.driver.version) plugin=$PluginVersion"
} catch {
    Report-Assert "Positive fixture -Sarif parses" $false $_.Exception.Message
}
$SarifNeg = ((& $AuditPs1 -Target (Join-Path $ProjectRoot "test\fixtures\negative") -Sarif 2>&1) -join "`n" | ConvertFrom-Json)
Report-Assert "Negative fixture -Sarif is a valid document with empty results" (@($SarifNeg.runs[0].results).Count -eq 0)
$null = & $AuditPs1 -Target $SingleDir -Json -Sarif 2>&1
$BothModesExit = $LASTEXITCODE
Report-Assert "-Json -Sarif together exit with code 2" ($BothModesExit -eq 2) "Actual exit code: $BothModesExit"

# 5. Test Negative & Suppression Fixtures
Write-Host "`n[5/6] Testing Negative & Suppression Fixtures..." -ForegroundColor Cyan
$NegativeDir = Join-Path $ProjectRoot "test\fixtures\negative"
$NegOutput = & $AuditPs1 -Target $NegativeDir -Json 2>&1
$NegExit = $LASTEXITCODE
Report-Assert "Negative fixture returns exit code 0 (clean code)" ($NegExit -eq 0) "Actual exit code: $NegExit"

$NegStr = ($NegOutput -join "`n").Trim()
Report-Assert "Negative fixture returns strict '[]'" ($NegStr -eq "[]") "Output: $NegStr"

$SuppressionDir = Join-Path $ProjectRoot "test\fixtures\suppression"
$SupOutput = & $AuditPs1 -Target $SuppressionDir -Json 2>&1
$SupExit = $LASTEXITCODE
Report-Assert "Suppression fixture returns exit code 0 (suppressed code)" ($SupExit -eq 0) "Actual exit code: $SupExit"

$SupStr = ($SupOutput -join "`n").Trim()
Report-Assert "Suppression fixture returns strict '[]'" ($SupStr -eq "[]") "Output: $SupStr"

# 6. Test Bash <-> PowerShell Cross-Platform JSON Parity
Write-Host "`n[6/6] Testing Bash <-> PowerShell Cross-Platform Parity..." -ForegroundColor Cyan
$BashExe = if (Get-Command bash -ErrorAction SilentlyContinue) {
    (Get-Command bash).Source
} elseif (Test-Path "C:\Program Files\Git\bin\bash.exe") {
    "C:\Program Files\Git\bin\bash.exe"
} else {
    $null
}

if ($BashExe) {
    $AuditSh = Join-Path $ProjectRoot "scripts\audit-flutter.sh"
    $BashAuditShPath = ($AuditSh -replace '\\', '/')
    $BashPosPath = ($PositiveDir -replace '\\', '/')

    $BashOutput = & $BashExe $BashAuditShPath --target $BashPosPath --json 2>&1

    try {
        $BashJson = $BashOutput | ConvertFrom-Json
        $PsNorm = $PosJson | ForEach-Object {
            [PSCustomObject]@{
                severity = $_.severity
                trapId = $_.trapId
                file = ($_.file -replace '\\', '/')
                line = [int]$_.line
                message = $_.message
            }
        } | Sort-Object trapId, file, line

        $BashNorm = $BashJson | ForEach-Object {
            [PSCustomObject]@{
                severity = $_.severity
                trapId = $_.trapId
                file = ($_.file -replace '\\', '/')
                line = [int]$_.line
                message = $_.message
            }
        } | Sort-Object trapId, file, line

        Report-Assert "Both scanners report identical findings count (31)" ($PsNorm.Count -eq $BashNorm.Count -and $PsNorm.Count -eq 31) "PS: $($PsNorm.Count), Bash: $($BashNorm.Count)"

        $Diff = Compare-Object $PsNorm $BashNorm -Property severity, trapId, file, line, message
        Report-Assert "Zero discrepancies in severity, trapId, file, line, message" ($null -eq $Diff)

        $BashNeg = & $BashExe $BashAuditShPath --target ($NegativeDir -replace '\\', '/') --json 2>&1
        Report-Assert "Negative fixture parity: both return strict '[]'" (($NegStr -eq "[]") -and (($BashNeg -join "`n").Trim() -eq "[]"))

        $BashSup = & $BashExe $BashAuditShPath --target ($SuppressionDir -replace '\\', '/') --json 2>&1
        Report-Assert "Suppression fixture parity: both return strict '[]'" (($SupStr -eq "[]") -and (($BashSup -join "`n").Trim() -eq "[]"))

        $BashSingle = & $BashExe $BashAuditShPath --target ((Join-Path $ProjectRoot "test\fixtures\single") -replace '\\', '/') --json 2>&1
        $BashSingleJson = $BashSingle | ConvertFrom-Json
        Report-Assert "Single finding fixture parity: exactly 1 matching record" ($SingleJson.Count -eq 1 -and $BashSingleJson.Count -eq 1 -and $SingleJson[0].trapId -eq $BashSingleJson[0].trapId)

        $BashSarif = ((& $BashExe $BashAuditShPath --target $BashPosPath --sarif 2>&1) -join "`n" | ConvertFrom-Json)
        $PsSarifDoc = $SarifPos | ConvertFrom-Json
        $SarifNormalize = {
            param($Doc)
            @($Doc.runs[0].results | ForEach-Object {
                [PSCustomObject]@{
                    ruleId = $_.ruleId; level = $_.level; message = $_.message.text
                    uri = ($_.locations[0].physicalLocation.artifactLocation.uri -replace '\\', '/')
                    line = [int]$_.locations[0].physicalLocation.region.startLine
                }
            })
        }
        $PsSarifNorm = & $SarifNormalize $PsSarifDoc
        $BashSarifNorm = & $SarifNormalize $BashSarif
        $SarifDiff = Compare-Object $PsSarifNorm $BashSarifNorm -Property ruleId, level, message, uri, line
        $RulesSame = (($PsSarifDoc.runs[0].tool.driver.rules | ForEach-Object { $_.id }) -join ",") -eq (($BashSarif.runs[0].tool.driver.rules | ForEach-Object { $_.id }) -join ",")
        Report-Assert "Positive fixture SARIF parity: identical results and rules" ($null -eq $SarifDiff -and $RulesSame -and $PsSarifNorm.Count -eq $BashSarifNorm.Count)
    } catch {
        Report-Assert "Bash JSON output parsing" $false $_.Exception.Message
    }
} else {
    Write-Host "  [SKIP] Bash executable not found; skipping cross-platform parity assertion" -ForegroundColor Yellow
}

# Summary
Write-Host "`n=================================================="
Write-Host " Test Summary: $Passed Passed, $Failed Failed" -ForegroundColor $(if ($Failed -eq 0) { "Green" } else { "Red" })
Write-Host "=================================================="

if ($Failed -gt 0) {
    exit 1
}
exit 0
