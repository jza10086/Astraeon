# Dot-source this helper. It never launches or stops a process.
Set-StrictMode -Version Latest

function ConvertTo-GodotAbsolutePath {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value) -or -not [IO.Path]::IsPathFullyQualified($Value)) { return $null }
    try {
        $normalized = [IO.Path]::GetFullPath($Value).Replace('/', '\').TrimEnd('\')
        if ($normalized.StartsWith('\\?\')) { $normalized = $normalized.Substring(4) }
        return $normalized
    } catch { return $null }
}

function Get-GodotColdImportConflicts {
    param([Parameter(Mandatory)][string]$ProjectPath, [Parameter(Mandatory)][string]$GodotPath,
        [AllowEmptyCollection()][object[]]$Processes = @())
    $target = ConvertTo-GodotAbsolutePath $ProjectPath
    $engine = ConvertTo-GodotAbsolutePath $GodotPath
    if (-not $target -or -not $engine) { throw 'Cold import requires absolute project and engine paths.' }
    foreach ($record in $Processes) {
        $exe = ConvertTo-GodotAbsolutePath ([string]$record.ExecutablePath)
        if ($exe -ne $engine -and [string]$record.Name -notmatch '(?i)^godot.*\.exe$' -and
            [IO.Path]::GetFileName([string]$exe) -notmatch '(?i)^godot.*\.exe$') { continue }
        $reason = $null
        $command = [string]$record.CommandLine
        if (-not $exe -or [string]::IsNullOrWhiteSpace($command)) {
            $reason = 'executable path or command line is unavailable'
        } else {
            $tokens = @([regex]::Matches($command, '(?:[^\s"]+|"[^"]*")+') | ForEach-Object { $_.Value.Replace('"', '') })
            $processProject = $null
            $editor = $false
            $positionalProject = $false
            $badPath = $false
            $pathCount = 0
            for ($i = 1; $i -lt $tokens.Count; $i++) {
                $token = $tokens[$i]
                if ($token -in @('--', '++')) { break }
                if ($token -in @('--editor', '-e', '--import', '--project-manager', '-p')) { $editor = $true }
                if ($token -eq '--path' -or $token.StartsWith('--path=')) {
                    $pathCount++
                    $value = ''
                    if ($token -eq '--path') {
                        if ($i + 1 -lt $tokens.Count) { $i++; $value = $tokens[$i] }
                    } else { $value = $token.Substring(7) }
                    $processProject = ConvertTo-GodotAbsolutePath $value
                    if (-not $processProject) { $badPath = $true }
                } elseif ($token -match '(?i)(^|[\\/])project\.godot$') {
                    $positionalProject = $true
                    $projectFile = ConvertTo-GodotAbsolutePath $token
                    if ($projectFile) {
                        $pathCount++
                        $processProject = ConvertTo-GodotAbsolutePath ([IO.Path]::GetDirectoryName($projectFile))
                    } else { $badPath = $true }
                }
            }
            if ($badPath -or $pathCount -gt 1 -or -not $processProject) {
                $reason = 'project path is missing, relative or ambiguous; process cwd is unknown'
            } elseif ($processProject -eq $target -and ($editor -or $positionalProject)) {
                $reason = 'this checkout is already open for editor/import work'
            }
        }
        if ($reason) { [pscustomobject]@{ ProcessId = $record.ProcessId; Reason = $reason } }
    }
}

function Assert-GodotColdImport {
    param([Parameter(Mandatory)][string]$ProjectPath, [Parameter(Mandatory)][string]$GodotPath)
    try {
        $records = @(Get-CimInstance Win32_Process -ErrorAction Stop | Select-Object ProcessId, Name, ExecutablePath, CommandLine)
    } catch {
        throw "Cold import blocked: process query failed: $($_.Exception.Message). Use a verified editor route; do not elevate or bypass this check."
    }
    $conflicts = @(Get-GodotColdImportConflicts -ProjectPath $ProjectPath -GodotPath $GodotPath -Processes $records)
    if ($conflicts.Count -gt 0) {
        $details = ($conflicts | ForEach-Object { "PID $($_.ProcessId): $($_.Reason)" }) -join '; '
        throw "Cold import blocked: $details. No process was stopped."
    }
}
