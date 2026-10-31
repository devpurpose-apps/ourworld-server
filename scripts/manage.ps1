[CmdletBinding()]
param(
    [Parameter(Mandatory, Position=0)]
    [ValidateSet('start', 'stop', 'restart', 'status', 'logs', 'backup', 'restore', 'deploy')]
    [string]$Action,
    [switch]$Production,
    [string]$Archive
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Push-Location $projectRoot
try {
    if ($Action -in @('backup', 'restore', 'deploy')) {
        $linuxRoot = & wsl.exe --exec wslpath -a -u $projectRoot
        if ($LASTEXITCODE -ne 0) { throw 'WSL path conversion failed. Enable Docker Desktop integration for your default WSL distro.' }
        $scriptArgs = @('--exec', 'bash', "$linuxRoot/scripts/$Action.sh")
        if ($Production) { $scriptArgs += '--prod' }
        if ($Action -eq 'restore') {
            if (!$Archive) { throw '-Archive is required for restore.' }
            $fullArchive = (Resolve-Path -LiteralPath $Archive).Path
            $linuxArchive = & wsl.exe --exec wslpath -a -u $fullArchive
            if ($LASTEXITCODE -ne 0) { throw 'Could not convert backup path.' }
            $scriptArgs += $linuxArchive
        }
        & wsl.exe @scriptArgs
    } else {
        $composeArgs = @('compose', '--env-file', '.env', '-f', 'compose.yml')
        if ($Production) { $composeArgs += @('-f', 'compose.prod.yml') }
        switch ($Action) {
            start { $composeArgs += @('up', '-d', '--wait', '--wait-timeout', '600') }
            stop { $composeArgs += 'stop' }
            restart { $composeArgs += 'restart' }
            status { $composeArgs += 'ps' }
            logs { $composeArgs += @('logs', '-f', '--tail', '100') }
        }
        & docker @composeArgs
    }
    if ($LASTEXITCODE -ne 0) { throw "$Action failed (exit $LASTEXITCODE)." }
} finally {
    Pop-Location
}
