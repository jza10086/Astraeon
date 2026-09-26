[CmdletBinding()]
param([string]$GodotPath)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$skillRoot = Join-Path $projectRoot '.agents/skills/godot-project-tooling'
$resolveArgs = @{ ProjectPath = $projectRoot; ToolchainsFile = (Join-Path $skillRoot 'godot-toolchains.json') }
if ($GodotPath) { $resolveArgs.GodotPath = $GodotPath }
$engine = & (Join-Path $skillRoot 'scripts/resolve_godot.ps1') @resolveArgs | ConvertFrom-Json
. (Join-Path $PSScriptRoot 'assert_cold_import.ps1')
Assert-GodotColdImport -ProjectPath $engine.project_path -GodotPath $engine.path
Write-Host "Godot $($engine.version) | $($engine.path)"
[System.IO.Directory]::CreateDirectory((Join-Path $projectRoot 'tmp')) | Out-Null
foreach ($mode in @('import', 'startup')) {
    $engineArgs = @('--headless', '--path', $projectRoot)
    if ($mode -eq 'import') { $engineArgs += '--import' }
    else { $engineArgs += @('--quit-after', '3') }
    $output = @(& $engine.path @engineArgs 2>&1 | ForEach-Object { [string]$_ })
    $result = $LASTEXITCODE
    $output | Set-Content -Encoding utf8 (Join-Path $projectRoot "tmp/$mode.log")
    $errors = @($output | Where-Object { $_ -match 'SCRIPT ERROR|ERROR:|Parser Error|Parse Error' })
    if ($result -ne 0 -or $errors.Count -gt 0) {
        $output | Write-Output
        throw "$mode failed (exit $result). See tmp/$mode.log"
    }
    Write-Host "$mode PASS (exit $result)"
}
& (Join-Path $skillRoot 'scripts/audit_godot_vcs.ps1') -ProjectPath $projectRoot
if ($LASTEXITCODE -ne 0) { throw 'VCS audit failed' }
