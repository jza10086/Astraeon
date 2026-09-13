[CmdletBinding()]
param(
    [ValidateSet('Info','Import','Open','Demo','Benchmark')][string]$Mode = 'Info',
    [switch]$Run,
    [ValidateSet('initial_load','stationary','streaming','editing')][string]$Case = 'stationary',
    [ValidateSet(64,128,256)][int]$Distance = 128,
    [ValidateRange(1,600)][int]$Seconds = 60,
    [ValidateRange(1,300)][int]$Warmup = 15,
    [int]$Seed = 20260913,
    [string]$GodotPath
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$project = Join-Path $root 'benchmarks/voxelgame/project'
if ($Mode -eq 'Info') {
    Write-Host "Project: $project"
    Write-Host 'Prepared only. Import performs no workload; Open shows the editor.'
    Write-Host 'Demo and Benchmark require -Run. Wait for user instruction before running.'
    return
}
if (($Mode -eq 'Benchmark' -or $Mode -eq 'Demo') -and -not $Run) {
    throw 'Explicit -Run is required. Preparation must not launch any workload.'
}
$skill = Join-Path $root '.agents/skills/godot-project-tooling'
$resolve = @{ ProjectPath = $project; ToolchainsFile = (Join-Path $skill 'godot-toolchains.json') }
if ($GodotPath) { $resolve.GodotPath = $GodotPath }
$engine = & (Join-Path $skill 'scripts/resolve_godot.ps1') @resolve | ConvertFrom-Json
$binary = Join-Path $project 'addons/zylann.voxel/bin/libvoxel.windows.editor.x86_64.dll'
if (-not (Test-Path -LiteralPath $binary)) { throw 'Missing native binary. Run tools/restore_voxel_dependency.py first.' }
$logDir = Join-Path $root 'tmp/voxel-bench-results'
[IO.Directory]::CreateDirectory($logDir) | Out-Null
if ($Mode -eq 'Open') {
    Start-Process -FilePath $engine.path -ArgumentList @('--editor','--path',('"{0}"' -f $project)) -WindowStyle Normal
    return
}
$arguments = @('--path',$project)
if ($Mode -eq 'Import') {
    $arguments += @('--headless','--import')
} elseif ($Mode -eq 'Demo') {
    $arguments += 'res://blocky_game/main.tscn'
} else {
    $arguments += @('--resolution','1920x1080','--windowed','res://astraeon_benchmark/benchmark.tscn','--',
        '--run-benchmark',"--case=$Case","--distance=$Distance","--seconds=$Seconds",
        "--warmup=$Warmup","--seed=$Seed","--output=$logDir")
}
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$output = @(& $engine.path @arguments 2>&1 | ForEach-Object { [string]$_ })
$result = $LASTEXITCODE
$log = Join-Path $logDir "$Mode-$stamp.log"
$output | Set-Content -Encoding utf8 $log
if ($Mode -ne 'Import') { $output | Write-Output }
if ($result -ne 0 -or @($output | Where-Object { $_ -match 'SCRIPT ERROR|ERROR:|Parser Error|Parse Error' }).Count -gt 0) {
    $output | Select-Object -Last 30 | Write-Output
    throw "$Mode failed (exit $result). See $log"
}
Write-Host "$Mode passed (exit $result). Log: $log"
