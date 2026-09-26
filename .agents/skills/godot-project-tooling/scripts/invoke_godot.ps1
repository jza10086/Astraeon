[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("Version", "Import", "CheckScript", "RunScript")]
    [string]$Mode,
    [string]$ProjectPath = (Get-Location).Path,
    [string]$ScriptPath,
    [string]$GodotPath,
    [string]$ExpectedVersion,
    [string]$ToolchainsFile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ToolchainsFile)) {
    $ToolchainsFile = Join-Path (Split-Path -Parent $PSScriptRoot) "godot-toolchains.json"
}

$resolverPath = Join-Path $PSScriptRoot "resolve_godot.ps1"
$resolverArguments = @{
    ProjectPath = $ProjectPath
    ToolchainsFile = $ToolchainsFile
}
if (-not [string]::IsNullOrWhiteSpace($GodotPath)) {
    $resolverArguments.GodotPath = $GodotPath
}
if (-not [string]::IsNullOrWhiteSpace($ExpectedVersion)) {
    $resolverArguments.ExpectedVersion = $ExpectedVersion
}

$toolchain = (& $resolverPath @resolverArguments | ConvertFrom-Json)
if ($Mode -eq "Version") {
    $toolchain | ConvertTo-Json -Depth 3
    exit 0
}

$projectFile = Join-Path $toolchain.project_path "project.godot"
if (-not (Test-Path -LiteralPath $projectFile -PathType Leaf)) {
    throw "No project.godot was found at '$($toolchain.project_path)'."
}

$arguments = [System.Collections.Generic.List[string]]::new()
$arguments.Add("--headless")
$arguments.Add("--path")
$arguments.Add($toolchain.project_path)

switch ($Mode) {
    "Import" {
        # This project adaptation resolves its guard from this skill's checkout.
        $checkoutRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../../..')).Path
        . (Join-Path $checkoutRoot 'tools/assert_cold_import.ps1')
        Assert-GodotColdImport -ProjectPath $toolchain.project_path -GodotPath $toolchain.path
        $arguments.Add("--import")
    }
    "CheckScript" {
        if ([string]::IsNullOrWhiteSpace($ScriptPath) -or -not $ScriptPath.StartsWith("res://")) {
            throw "CheckScript requires -ScriptPath in res:// form."
        }
        $arguments.Add("--script")
        $arguments.Add($ScriptPath)
        $arguments.Add("--check-only")
    }
    "RunScript" {
        if ([string]::IsNullOrWhiteSpace($ScriptPath) -or -not $ScriptPath.StartsWith("res://")) {
            throw "RunScript requires -ScriptPath in res:// form."
        }
        $arguments.Add("--script")
        $arguments.Add($ScriptPath)
    }
}

Write-Host "Godot: $($toolchain.path)"
Write-Host "Version: $($toolchain.version)"
Write-Host "Mode: $Mode"
Write-Host "Project: $($toolchain.project_path)"

$outputLines = @(& $toolchain.path @arguments 2>&1 | ForEach-Object { [string]$_ })
$exitCode = $LASTEXITCODE
$outputLines | ForEach-Object { Write-Output $_ }

$errorPattern = "SCRIPT ERROR|ERROR:|Parser Error|Parse Error"
$reportedErrors = @($outputLines | Where-Object { $_ -match $errorPattern })
Write-Host "Exit code: $exitCode"

if ($exitCode -ne 0 -or $reportedErrors.Count -gt 0) {
    if ($reportedErrors.Count -gt 0) {
        Write-Error ("Godot reported errors: " + ($reportedErrors -join " | "))
    }
    exit $(if ($exitCode -ne 0) { $exitCode } else { 1 })
}
