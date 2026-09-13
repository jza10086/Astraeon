[CmdletBinding()]
param(
    [string]$GodotPath,
    [string]$ExpectedVersion,
    [string]$ProjectPath = (Get-Location).Path,
    [string]$ToolchainsFile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ToolchainsFile)) {
    $ToolchainsFile = Join-Path (Split-Path -Parent $PSScriptRoot) "godot-toolchains.json"
}

function Add-Candidate {
    param(
        [System.Collections.Generic.List[object]]$Candidates,
        [string]$Source,
        [string]$Value,
        [bool]$Required = $false
    )

    if (-not [string]::IsNullOrWhiteSpace($Value)) {
        $Candidates.Add([pscustomobject]@{
            source = $Source
            value = $Value
            required = $Required
        })
    }
}

function Resolve-CandidatePath {
    param([string]$Candidate)

    if (Test-Path -LiteralPath $Candidate -PathType Leaf) {
        return (Resolve-Path -LiteralPath $Candidate).Path
    }

    $command = Get-Command $Candidate -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $command) {
        return $command.Source
    }

    return $null
}

$resolvedProjectPath = (Resolve-Path -LiteralPath $ProjectPath).Path
$toolchains = $null
if (Test-Path -LiteralPath $ToolchainsFile -PathType Leaf) {
    $toolchains = Get-Content -LiteralPath $ToolchainsFile -Raw | ConvertFrom-Json
}

$effectiveExpectedVersion = $ExpectedVersion
if ([string]::IsNullOrWhiteSpace($effectiveExpectedVersion)) {
    $versionFile = Join-Path $resolvedProjectPath ".godot-version"
    if (Test-Path -LiteralPath $versionFile -PathType Leaf) {
        $effectiveExpectedVersion = (Get-Content -LiteralPath $versionFile | Select-Object -First 1).Trim()
    }
}
if ([string]::IsNullOrWhiteSpace($effectiveExpectedVersion) -and $null -ne $toolchains -and $null -ne $toolchains.default) {
    $effectiveExpectedVersion = [string]$toolchains.default
}

$candidates = [System.Collections.Generic.List[object]]::new()
Add-Candidate -Candidates $candidates -Source "explicit" -Value $GodotPath -Required (-not [string]::IsNullOrWhiteSpace($GodotPath))
Add-Candidate -Candidates $candidates -Source "GODOT_BIN" -Value $env:GODOT_BIN

if ($null -ne $toolchains -and $null -ne $toolchains.versions) {
    $selectedToolchainVersion = $effectiveExpectedVersion
    if ([string]::IsNullOrWhiteSpace($selectedToolchainVersion) -and $null -ne $toolchains.default) {
        $selectedToolchainVersion = [string]$toolchains.default
    }
    if (-not [string]::IsNullOrWhiteSpace($selectedToolchainVersion)) {
        $toolchainProperty = $toolchains.versions.PSObject.Properties[$selectedToolchainVersion]
        if ($null -ne $toolchainProperty) {
            Add-Candidate -Candidates $candidates -Source "toolchains:$selectedToolchainVersion" -Value ([string]$toolchainProperty.Value)
        }
    }
}

Add-Candidate -Candidates $candidates -Source "PATH:godot" -Value "godot"
Add-Candidate -Candidates $candidates -Source "PATH:godot4" -Value "godot4"
Add-Candidate -Candidates $candidates -Source "PATH:godot_console" -Value "godot_console"

$attempts = [System.Collections.Generic.List[string]]::new()
foreach ($candidate in $candidates) {
    $resolvedPath = Resolve-CandidatePath -Candidate $candidate.value
    if ($null -eq $resolvedPath) {
        $attempts.Add("$($candidate.source): not found")
        if ($candidate.required) {
            throw "The explicitly selected Godot executable was not found: $($candidate.value)"
        }
        continue
    }

    $versionOutput = (& $resolvedPath --version 2>&1 | Out-String).Trim()
    $versionExitCode = $LASTEXITCODE
    if ($versionExitCode -ne 0) {
        $attempts.Add("$($candidate.source): --version exited $versionExitCode")
        if ($candidate.required) {
            throw "The explicitly selected Godot executable could not report its version: $resolvedPath"
        }
        continue
    }

    if (-not [string]::IsNullOrWhiteSpace($effectiveExpectedVersion)) {
        $escapedVersion = [regex]::Escape($effectiveExpectedVersion)
        if ($versionOutput -notmatch "^$escapedVersion(?:\.|$)") {
            $attempts.Add("$($candidate.source): version '$versionOutput' does not match '$effectiveExpectedVersion'")
            if ($candidate.required) {
                throw "Godot version mismatch. Expected '$effectiveExpectedVersion', got '$versionOutput' from '$resolvedPath'."
            }
            continue
        }
    }

    [pscustomobject]@{
        path = $resolvedPath
        version = $versionOutput
        expected_version = $effectiveExpectedVersion
        source = $candidate.source
        project_path = $resolvedProjectPath
    } | ConvertTo-Json -Depth 3
    exit 0
}

$attemptSummary = if ($attempts.Count -gt 0) { $attempts -join "; " } else { "no candidates were configured" }
throw "No compatible Godot executable was found. Attempts: $attemptSummary"
