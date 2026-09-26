Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $root 'tools/assert_cold_import.ps1')
$project = 'F:\Godot Projects\Astraeon'
$engine = 'F:\Engine\Godot_console.exe'
$script:checks = 0
function Check {
    param([string]$Label, [object[]]$Records, [int]$Expected)
    $actual = @(Get-GodotColdImportConflicts -ProjectPath $project -GodotPath $engine -Processes $Records)
    if ($actual.Count -ne $Expected) { throw "$Label expected $Expected conflicts, got $($actual.Count)" }
    foreach ($item in $actual) {
        if (-not $item.ProcessId -or -not $item.Reason) { throw "$Label missing diagnostic" }
    }
    $script:checks++
}
function Record {
    param([string]$Command, [string]$Executable = $engine, [string]$Name = 'Godot_console.exe')
    return [pscustomobject]@{ ProcessId = 42; Name = $Name; ExecutablePath = $Executable; CommandLine = $Command }
}
Check 'no engine' @() 0
Check 'same project editor quoted spaces' @((Record 'Godot_console.exe --editor --path "F:\Godot Projects\Astraeon"')) 1
Check 'case slash and trailing slash' @((Record 'Godot_console.exe -e --path "f:/godot projects/ASTRAEON/"')) 1
Check 'other project editor' @((Record 'Godot_console.exe -e --path F:\Other')) 0
Check 'game' @((Record 'Godot_console.exe --path "F:\Godot Projects\Astraeon"')) 0
Check 'script test' @((Record 'Godot_console.exe --headless --path "F:\Godot Projects\Astraeon" --script res://test.gd')) 0
Check 'import' @((Record 'Godot_console.exe --import --path="F:\Godot Projects\Astraeon"')) 1
Check 'positional project' @((Record 'Godot_console.exe "F:\Godot Projects\Astraeon\project.godot"')) 1
Check 'relative path' @((Record 'Godot_console.exe -e --path .')) 1
Check 'missing command line' @((Record '')) 1
Check 'missing executable' @((Record 'Godot_console.exe --path F:\Other' '')) 1
Check 'unknown project' @((Record 'Godot_console.exe --editor')) 1
Check 'duplicate project' @((Record 'Godot_console.exe --path F:\Other --path "F:\Godot Projects\Astraeon"')) 1
Check 'unrelated process' @((Record 'other.exe' 'F:\other.exe' 'other.exe')) 0
Check 'renamed known engine' @((Record 'custom.exe -e --path "F:\Godot Projects\Astraeon"' $engine 'custom.exe')) 1
Check 'user arguments not editor flags' @((Record 'Godot_console.exe --path "F:\Godot Projects\Astraeon" -- --editor')) 0
function Get-CimInstance { param($ClassName, $ErrorAction) throw 'simulated access denied' }
$caught = $false
try { Assert-GodotColdImport -ProjectPath $project -GodotPath $engine } catch {
    $caught = $_.Exception.Message -like '*process query failed*simulated access denied*'
}
if (-not $caught) { throw 'Query failure was not preserved and blocked.' }
$script:checks++
Write-Output "COLD_IMPORT_PREFLIGHT PASS checks=$script:checks"
