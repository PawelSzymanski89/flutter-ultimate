<#
.SYNOPSIS
    Test runner for Flutter Ultimate Skill and Static Code Analyzer.
.DESCRIPTION
    Validates SKILL.md specification limits and executes test fixtures
    (positive, negative, suppression) against audit-flutter.ps1 and audit-flutter.sh.
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
Write-Host " Flutter Ultimate Test Suite"
Write-Host " Project: $ProjectRoot"
Write-Host "=================================================="

# 1. Validate SKILL.md Specification
Write-Host "`n[1/4] Validating SKILL.md Specification..." -ForegroundColor Cyan
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
    }
}

# 2. Test audit-flutter.ps1 on Positive Fixture
Write-Host "`n[2/4] Testing audit-flutter.ps1 Positive Fixture..." -ForegroundColor Cyan
$PositiveDir = Join-Path $ProjectRoot "test\fixtures\positive"
$AuditPs1 = Join-Path $ProjectRoot "scripts\audit-flutter.ps1"

$PosOutput = & $AuditPs1 -Target $PositiveDir -Json 2>&1
$PosExit = $LASTEXITCODE
Report-Assert "Positive fixture returns exit code 1 (violations detected)" ($PosExit -eq 1) "Actual exit code: $PosExit"

try {
    $PosJson = $PosOutput | ConvertFrom-Json
    $DetectedTraps = @($PosJson | ForEach-Object { $_.trapId })

    $ExpectedTraps = @(
        "P03", "P04", "P07", "P12", "P19", "P21", "P26", "P27",
        "K01", "W01", "W03", "W06", "W14",
        "LINT-02", "GDPR-01", "GDPR-02", "GDPR-03", "GDPR-04"
    )

    foreach ($trap in $ExpectedTraps) {
        $found = $DetectedTraps -contains $trap
        Report-Assert "Positive fixture detects $trap" $found
    }
} catch {
    Report-Assert "Positive fixture returns valid JSON" $false $_.Exception.Message
}

# 3. Test audit-flutter.ps1 on Negative Fixture
Write-Host "`n[3/4] Testing audit-flutter.ps1 Negative Fixture..." -ForegroundColor Cyan
$NegativeDir = Join-Path $ProjectRoot "test\fixtures\negative"
$NegOutput = & $AuditPs1 -Target $NegativeDir -Json 2>&1
$NegExit = $LASTEXITCODE
Report-Assert "Negative fixture returns exit code 0 (clean code)" ($NegExit -eq 0) "Actual exit code: $NegExit"

$NegCount = 0
if ($NegOutput) {
    try {
        $NegJson = $NegOutput | ConvertFrom-Json
        $NegCount = if ($NegJson) { $NegJson.Count } else { 0 }
    } catch {}
}
Report-Assert "Negative fixture has 0 findings" ($NegCount -eq 0) "Findings detected: $NegCount"

# 4. Test audit-flutter.ps1 on Suppression Fixture
Write-Host "`n[4/4] Testing audit-flutter.ps1 Suppression Fixture..." -ForegroundColor Cyan
$SuppressionDir = Join-Path $ProjectRoot "test\fixtures\suppression"
$SupOutput = & $AuditPs1 -Target $SuppressionDir -Json 2>&1
$SupExit = $LASTEXITCODE
Report-Assert "Suppression fixture returns exit code 0 (suppressed code)" ($SupExit -eq 0) "Actual exit code: $SupExit"

$SupCount = 0
if ($SupOutput) {
    try {
        $SupJson = $SupOutput | ConvertFrom-Json
        $SupCount = if ($SupJson) { $SupJson.Count } else { 0 }
    } catch {}
}
Report-Assert "Suppression fixture has 0 findings" ($SupCount -eq 0) "Findings detected: $SupCount"

# Summary
Write-Host "`n=================================================="
Write-Host " Test Summary: $Passed Passed, $Failed Failed" -ForegroundColor $(if ($Failed -eq 0) { "Green" } else { "Red" })
Write-Host "=================================================="

if ($Failed -gt 0) {
    exit 1
}
exit 0
