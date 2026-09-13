[CmdletBinding()]
param(
    [string]$ProjectPath = (Get-Location).Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$resolvedProjectPath = (Resolve-Path -LiteralPath $ProjectPath).Path
$gitignorePath = Join-Path $resolvedProjectPath ".gitignore"
$gitattributesPath = Join-Path $resolvedProjectPath ".gitattributes"
$gitignoreLines = @()
$gitattributesLines = @()

if (Test-Path -LiteralPath $gitignorePath -PathType Leaf) {
    $gitignoreLines = @(Get-Content -LiteralPath $gitignorePath)
}
if (Test-Path -LiteralPath $gitattributesPath -PathType Leaf) {
    $gitattributesLines = @(Get-Content -LiteralPath $gitattributesPath)
}

$effectiveIgnoreLines = @($gitignoreLines | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith("#") })
$missingIgnorePatterns = [System.Collections.Generic.List[string]]::new()
if ($effectiveIgnoreLines -notcontains ".godot/") {
    $missingIgnorePatterns.Add(".godot/")
}
if ($effectiveIgnoreLines -notcontains "*.translation") {
    $missingIgnorePatterns.Add("*.translation")
}

$uidIgnorePatterns = @($effectiveIgnoreLines | Where-Object { $_ -match "(^|/)\*?\.uid(/|$)" -or $_ -eq "*.uid" })
$hasLfRule = @($gitattributesLines | Where-Object { $_ -match "^\s*\*\s+text=auto\s+eol=lf(?:\s|$)" }).Count -gt 0
$trackedGeneratedFiles = @()
$trackedUidFiles = @()
$gitDirectory = Join-Path $resolvedProjectPath ".git"

if (Test-Path -LiteralPath $gitDirectory) {
    $trackedGeneratedFiles = @(& git -C $resolvedProjectPath ls-files -- ".godot" ".godot/*" "*.translation")
    if ($LASTEXITCODE -ne 0) {
        throw "git ls-files failed while auditing generated files."
    }
    $trackedUidFiles = @(& git -C $resolvedProjectPath ls-files -- "*.uid")
    if ($LASTEXITCODE -ne 0) {
        throw "git ls-files failed while auditing UID files."
    }
}

[pscustomobject]@{
    project_path = $resolvedProjectPath
    project_file_exists = Test-Path -LiteralPath (Join-Path $resolvedProjectPath "project.godot") -PathType Leaf
    git_repository = Test-Path -LiteralPath $gitDirectory
    gitignore_exists = Test-Path -LiteralPath $gitignorePath -PathType Leaf
    missing_ignore_patterns = @($missingIgnorePatterns)
    uid_ignore_patterns = @($uidIgnorePatterns)
    gitattributes_exists = Test-Path -LiteralPath $gitattributesPath -PathType Leaf
    has_lf_normalization = $hasLfRule
    tracked_generated_files = @($trackedGeneratedFiles)
    tracked_uid_files = @($trackedUidFiles)
} | ConvertTo-Json -Depth 4
