param([Parameter(Mandatory=$true)][string]$Preset,[Parameter(Mandatory=$true)][string]$Output,[string]$GodotPath)
$ErrorActionPreference='Stop'
$projectRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$skillRoot=Join-Path $projectRoot '.agents/skills/godot-project-tooling'
$resolveArgs=@{ProjectPath=$projectRoot;ToolchainsFile=(Join-Path $skillRoot 'godot-toolchains.json')}
if($GodotPath){$resolveArgs.GodotPath=$GodotPath}
$engine=& (Join-Path $skillRoot 'scripts/resolve_godot.ps1') @resolveArgs | ConvertFrom-Json
python (Join-Path $PSScriptRoot 'verify_deployment.py')
if($LASTEXITCODE -ne 0){throw 'Content preflight failed; export was not started'}
. (Join-Path $PSScriptRoot '../assert_cold_import.ps1')
Assert-GodotColdImport -ProjectPath $projectRoot -GodotPath $engine.path
& $engine.path --headless --path $projectRoot --export-release $Preset $Output
if($LASTEXITCODE -ne 0){throw 'Godot export failed'}
