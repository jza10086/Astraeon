[CmdletBinding()]
param([ValidateSet('Session','Render')][string]$Mode='Session',[string]$GodotPath,[int]$TimeoutSeconds=90)
$ErrorActionPreference='Stop'
$projectRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$resolver=Join-Path $projectRoot '.agents/skills/godot-project-tooling/scripts/resolve_godot.ps1'
$resolverArgs=@{ProjectPath=$projectRoot;ToolchainsFile=(Join-Path $projectRoot '.agents/skills/godot-project-tooling/godot-toolchains.json')}
if($GodotPath){$resolverArgs.GodotPath=$GodotPath}
$engine=(& $resolver @resolverArgs | ConvertFrom-Json)
$output=Join-Path $projectRoot 'tmp/content'
New-Item -ItemType Directory -Force -Path $output | Out-Null
$script=if($Mode -eq 'Render'){'test_render.gd'}else{'test_session.gd'}
$name='content_editor_'+$Mode.ToLowerInvariant()
$log=Join-Path $output ($name+'.log')
$launchArgs=@('--path',('"'+$projectRoot+'"'),'--log-file',('"'+$log+'"'),'--script',('res://test/content_editor/gdscript/'+$script))
if($Mode -eq 'Session'){$launchArgs=@('--headless')+$launchArgs}
$process=Start-Process -FilePath $engine.path -ArgumentList $launchArgs -WindowStyle Hidden -PassThru
$started=$process.StartTime
@{pid=$process.Id;start=$started.ToString('o');executable=$engine.path;project=$projectRoot;purpose=$name} | ConvertTo-Json | Set-Content (Join-Path $output ($name+'-process.json'))
if(-not $process.WaitForExit($TimeoutSeconds*1000)){
 $owned=Get-Process -Id $process.Id -ErrorAction SilentlyContinue
 if($null -ne $owned -and $owned.StartTime -eq $started -and $owned.Path -eq $engine.path){Stop-Process -Id $process.Id}
 throw "Owned test timed out: $name"
}
$process.Refresh()
$lines=Get-Content -LiteralPath $log
# The sandbox's Windows root-certificate-store diagnostic is independent of these tests.
$errors=@($lines | Where-Object {$_ -match 'SCRIPT ERROR|ERROR:' -and $_ -notmatch '^ERROR: Failed to read the root certificate store\.$'})
$summary=@($lines | Where-Object {$_ -match 'CONTENT_EDITOR_.*_DONE'})
$summary | Write-Output
if($process.ExitCode -ne 0 -or $errors.Count -gt 0 -or $summary.Count -ne 1 -or $summary[0] -notmatch 'failures=0$'){
 $errors | Write-Output
 throw "Test failed. Exit=$($process.ExitCode); log=$log"
}
Write-Output "Log: $log"
