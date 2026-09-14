[CmdletBinding()]
param([switch]$Run, [string]$GodotPath)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$project = Join-Path $root 'benchmarks/voxelgame/project'
if (-not $Run) {
    Write-Host 'P0 lighting sample is prepared. Use ./tools/lighting_sample.ps1 -Run to open it, then click Create.'
    return
}
$skill = Join-Path $root '.agents/skills/godot-project-tooling'
$resolve = @{
    ProjectPath = $project
    ToolchainsFile = (Join-Path $skill 'godot-toolchains.json')
    ExpectedVersion = '4.7.stable'
}
if ($GodotPath) { $resolve.GodotPath = $GodotPath }
$engine = & (Join-Path $skill 'scripts/resolve_godot.ps1') @resolve | ConvertFrom-Json
$binary = Join-Path $project 'addons/zylann.voxel/bin/libvoxel.windows.editor.x86_64.dll'
if (-not (Test-Path -LiteralPath $binary)) { throw 'Missing Voxel Tools editor binary.' }
& $engine.path --path $project 'res://astraeon_lighting/lighting_sample.tscn'
exit $LASTEXITCODE
