# td-build.ps1 - run the official TangDynasty flow in a TD run directory.
#
# This does NOT use the GUI-generated run.bat: those hard-code the old install
# path (D:\Anlogic\TD_6.2.1_Engineer_6.2.168.116) and end with `pause`, which
# hangs any non-interactive caller. We invoke td_commands_prompt.exe directly.
#
# Success is judged by TD's own step marker files (.STEP.end.f / .STEP.error.f),
# not by the process exit code: the flow script ends with `return -code error`,
# which does not reliably reach the process exit status.
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File td-build.ps1 <run-dir> `
#       [-StartStep <step>] [-EndStep <step>] [-Force] [-DryRun]
#
# <run-dir> must be a TD run directory containing settings.cfg (e.g.
# ...\hdmi_player_Runs\phy_1). Use td-status.ps1 to inspect one first.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)][string]$RunDir,
    [string]$StartStep = '',
    [string]$EndStep   = '',
    [string]$FlowScript = '',
    [string]$LogDir = 'D:\Anlogic\td-ops\logs',
    [switch]$Force,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$StepOrder = @('read_design', 'opt_rtl', 'opt_gate', 'opt_place', 'opt_route', 'bitgen')

# Bad input gets its own exit code (3) so a caller can tell "I passed the wrong
# thing" apart from "the build failed". A bare `throw` would exit 1 and collide
# with the step-error code.
function Fail-Param {
    param([string]$Message)
    Write-Output ('ERROR: ' + $Message)
    exit 3
}

# --- toolchain locations -----------------------------------------------------

$tdHome = $env:TD_HOME
if ([string]::IsNullOrWhiteSpace($tdHome)) { $tdHome = 'D:\Anlogic\TD6.2.1' }

$tdExe = Join-Path $tdHome 'bin\td_commands_prompt.exe'
$flow  = if ($FlowScript -ne '') { $FlowScript } else { Join-Path $tdHome 'doc\scripts\DefaultFlow.tcl' }

# td_commands_prompt.exe hands its argv straight to Tcl, which parses it as a
# LIST word - so a backslash path loses every separator (\A -> A, \T -> T, ...).
# "D:\Anlogic\TD6.2.1\doc\..." arrives as "D:AnlogicTD6.2.1doc...". Forward
# slashes survive, and Windows accepts them. Applies to the flow script arg.
$flow = $flow.Replace('\', '/')

if (-not (Test-Path -LiteralPath $tdExe -PathType Leaf)) { Fail-Param "TD console not found: $tdExe  (set TD_HOME to override)" }
if (-not (Test-Path -LiteralPath $flow  -PathType Leaf)) { Fail-Param "flow script not found: $flow" }

# --- resolve + validate the run directory ------------------------------------

if (-not (Test-Path -LiteralPath $RunDir)) { Fail-Param "run directory not found: $RunDir" }
$RunDir = (Resolve-Path -LiteralPath $RunDir).Path
$cfgPath = Join-Path $RunDir 'settings.cfg'
if (-not (Test-Path -LiteralPath $cfgPath -PathType Leaf)) {
    Fail-Param "$RunDir is not a TD run directory (no settings.cfg). Pass the *_Runs\<run> directory."
}

if ($StartStep -ne '' -and ($StepOrder -notcontains $StartStep)) {
    Fail-Param "unknown start step '$StartStep'. Valid: $($StepOrder -join ', ')"
}
if ($EndStep -ne '' -and ($StepOrder -notcontains $EndStep)) {
    Fail-Param "unknown end step '$EndStep'. Valid: $($StepOrder -join ', ')"
}

# --- settings.cfg read / write ----------------------------------------------

function Read-SettingsMap {
    param([string]$File)
    # Returns key -> value. NOTE: the key MUST be captured before the inner
    # -match calls below, because those overwrite the automatic $matches
    # variable (this bit us once: braced values like {breath_led} turned into
    # the key instead of the value).
    $map = @{}
    foreach ($line in [System.IO.File]::ReadAllLines($File)) {
        if ($line -match '^\s*set\s+([A-Za-z_][A-Za-z0-9_]*)\s+(.*?)\s*$') {
            $k = $matches[1]
            $v = $matches[2]
            if ($v -match '^\{(.*)\}$') { $v = $matches[1] }
            elseif ($v -match '^"(.*)"$') { $v = $matches[1] }
            $map[$k] = $v
        }
    }
    return $map
}

function Set-SettingsValue {
    param([string]$File, [string]$Key, [string]$Value)
    $lines = [System.IO.File]::ReadAllLines($File)
    $found = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match ('^\s*set\s+' + [regex]::Escape($Key) + '\s+')) {
            $lines[$i] = "set $Key $Value"
            $found = $true
        }
    }
    if (-not $found) { $lines += "set $Key $Value" }
    [System.IO.File]::WriteAllLines($File, $lines)   # WriteAllLines emits CRLF on Windows
}

$map = Read-SettingsMap $cfgPath
$prj      = if ($map.ContainsKey('prj_name'))   { $map['prj_name'] }   else { '' }
$curStart = if ($map.ContainsKey('start_step')) { $map['start_step'] } else { '' }
$curEnd   = if ($map.ContainsKey('end_step'))   { $map['end_step'] }   else { '' }

$newStart = if ($StartStep -ne '') { $StartStep } else { $curStart }
$newEnd   = if ($EndStep   -ne '') { $EndStep   } else { $curEnd }

if ($newStart -ne '' -and $newEnd -ne '') {
    $li = [array]::IndexOf($StepOrder, $newStart)
    $ri = [array]::IndexOf($StepOrder, $newEnd)
    if ($li -lt 0 -or $ri -lt 0) { Fail-Param "start/end step not in the known step list" }
    if ($li -gt $ri) { Fail-Param "start_step ($newStart) is after end_step ($newEnd)" }
}

$stepsToRun = @()
if ($newStart -ne '' -and $newEnd -ne '') {
    $li = [array]::IndexOf($StepOrder, $newStart)
    $ri = [array]::IndexOf($StepOrder, $newEnd)
    $stepsToRun = $StepOrder[$li..$ri]
}

# --- report the plan ---------------------------------------------------------

Write-Output '=== TD BUILD ==='
Write-Output ('run_dir     : {0}' -f $RunDir)
Write-Output ('project     : {0}' -f $prj)
Write-Output ('td_home     : {0}' -f $tdHome)
Write-Output ('flow_script : {0}' -f $flow)
Write-Output ('step_range  : {0} -> {1}' -f $newStart, $newEnd)
Write-Output ('steps       : {0}' -f ($stepsToRun -join ' '))
Write-Output ''

if ($curStart -ne $newStart -or $curEnd -ne $newEnd) {
    Write-Output ('settings.cfg will be updated: start_step {0} -> {1}, end_step {2} -> {3}' -f `
                  $curStart, $newStart, $curEnd, $newEnd)
}

# --- halt flag ---------------------------------------------------------------

$haltF = Join-Path $RunDir '.stop.f'
if (Test-Path -LiteralPath $haltF) {
    if (-not $Force) {
        Write-Output 'ABORT: .stop.f is present - the flow would halt immediately.'
        Write-Output '       Remove it yourself, or re-run with -Force to have it deleted.'
        exit 4
    }
    Write-Output 'NOTE: deleting .stop.f (halt flag) because -Force was given.'
    if (-not $DryRun) { Remove-Item -LiteralPath $haltF -Force }
}

if ($DryRun) {
    Write-Output ''
    Write-Output 'DRY RUN - nothing was executed.'
    exit 0
}

# --- apply the step override -------------------------------------------------

if ($curStart -ne $newStart -or $curEnd -ne $newEnd) {
    $bak = $cfgPath + '.bak-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
    Copy-Item -LiteralPath $cfgPath -Destination $bak -Force
    Write-Output ('backup      : {0}' -f $bak)
    Set-SettingsValue $cfgPath 'start_step' $newStart
    Set-SettingsValue $cfgPath 'end_step'   $newEnd
}

# --- clear stale error markers for the steps we are about to re-run ----------

foreach ($step in $stepsToRun) {
    $errF = Join-Path $RunDir ('.' + $step + '.error.f')
    if (Test-Path -LiteralPath $errF) {
        Remove-Item -LiteralPath $errF -Force
        Write-Output ('cleared stale error marker: .{0}.error.f' -f $step)
    }
}

# --- run ---------------------------------------------------------------------

if (-not (Test-Path -LiteralPath $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
$logPath = Join-Path $LogDir ('td-build_{0}_{1}.log' -f $prj, (Get-Date -Format 'yyyyMMdd-HHmmss'))

Write-Output ''
Write-Output ('launching  : {0}' -f $tdExe)
Write-Output ('cwd        : {0}' -f $RunDir)
Write-Output ('log        : {0}' -f $logPath)
Write-Output '----------------------------------------'

$startedAt = Get-Date
$exitCode  = 0
Push-Location -LiteralPath $RunDir
# Stream to console AND to the log, but write the log as UTF-8. Tee-Object on
# PS 5.1 writes UTF-16LE, which every normal tool (grep, tail) then sees as
# "l i k e   t h i s".
$sw = New-Object System.IO.StreamWriter($logPath, $false, (New-Object System.Text.UTF8Encoding($false)))
try {
    & $tdExe $flow 2>&1 | ForEach-Object {
        Write-Output $_
        $sw.WriteLine([string]$_)
    }
    if ($null -ne $LASTEXITCODE) { $exitCode = $LASTEXITCODE }
}
finally {
    $sw.Close()
    Pop-Location
}
$finishedAt = Get-Date
$elapsed = $finishedAt - $startedAt

Write-Output '----------------------------------------'
Write-Output ('process exit code : {0}' -f $exitCode)
Write-Output ('elapsed           : {0:hh\:mm\:ss}' -f $elapsed)
Write-Output ''

# --- verdict from the step markers -------------------------------------------

$done  = @()
$errs  = @()
$miss  = @()
foreach ($step in $stepsToRun) {
    $endF = Join-Path $RunDir ('.' + $step + '.end.f')
    $errF = Join-Path $RunDir ('.' + $step + '.error.f')
    $endFresh = (Test-Path -LiteralPath $endF) -and ((Get-Item -LiteralPath $endF).LastWriteTime -ge $startedAt)
    $errFresh = (Test-Path -LiteralPath $errF) -and ((Get-Item -LiteralPath $errF).LastWriteTime -ge $startedAt)
    if ($errFresh)     { $errs += $step }
    elseif ($endFresh) { $done += $step }
    else               { $miss += $step }
}

Write-Output '--- STEP RESULTS ---'
foreach ($step in $stepsToRun) {
    $state = 'not-reached'
    if ($errs -contains $step)      { $state = 'ERROR' }
    elseif ($done -contains $step)  { $state = 'done' }
    $endF = Join-Path $RunDir ('.' + $step + '.end.f')
    $when = ''
    if (Test-Path -LiteralPath $endF) { $when = (Get-Item -LiteralPath $endF).LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss') }
    Write-Output ('{0,-14} {1,-12} {2}' -f $step, $state, $when)
}
Write-Output ''

if ($errs.Count -gt 0) {
    Write-Output ('FAILED: {0}' -f ($errs -join ', '))
    Write-Output ('see log: {0}' -f $logPath)
    exit 1
}
if ($miss.Count -gt 0) {
    Write-Output ('INCOMPLETE: these steps produced no marker: {0}' -f ($miss -join ', '))
    Write-Output ('see log: {0}' -f $logPath)
    exit 2
}

Write-Output 'OK: every step in the requested range completed.'

$statusScript = Join-Path $PSScriptRoot 'td-status.ps1'
if (Test-Path -LiteralPath $statusScript -PathType Leaf) {
    Write-Output ''
    & $statusScript $RunDir
}

exit 0
