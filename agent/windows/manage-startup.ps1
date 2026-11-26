# Guardian: startup for the current consenting interactive Windows user.
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('Enable','Disable','Start','Stop','Status','Plan')]
    [string]$Action,
    [string]$PythonExe,
    [string]$Detector,
    [string]$Recognizer,
    [ValidateSet('observe','protect')]
    [string]$Mode = 'observe',
    [switch]$OwnerConsent,
    [switch]$ConfirmExperimentalProtection,
    [switch]$LockedLocation,
    [switch]$LockedPhoto
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
if ($identity.IsSystem -or -not $identity.User) {
    throw 'Ejecuta este comando bajo tu propia cuenta Windows, no como SYSTEM.'
}
$agentDir = $PSScriptRoot
$prefix = 'Guardian-' + $identity.User.Value
$faceName = $prefix + '-Face'
$lockedName = $prefix + '-Locked'
$names = @($faceName,$lockedName)

function Quote-Argument([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value) -or $Value -match '["\r\n]') {
        throw 'Argumento invalido.'
    }
    return '"' + $Value + '"'
}
function Resolve-ExistingFile([string]$Value,[string]$Label) {
    if ([string]::IsNullOrWhiteSpace($Value)) { throw "Define $Label." }
    $item = Get-Item -LiteralPath $Value -ErrorAction Stop
    if ($item.PSIsContainer) { throw "$Label debe apuntar a un archivo." }
    return $item.FullName
}
function Read-Task([string]$Name) {
    return Get-ScheduledTask -TaskName $Name -TaskPath '\' -ErrorAction SilentlyContinue
}
function New-GuardianDefinition([string]$Arguments,[string]$Description) {
    $taskAction = New-ScheduledTaskAction -Execute $resolvedPython -Argument $Arguments -WorkingDirectory $agentDir
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $identity.Name
    $principal = New-ScheduledTaskPrincipal -UserId $identity.Name -LogonType Interactive -RunLevel Limited
    $settingsArgs = @{
        AllowStartIfOnBatteries=$true
        DontStopIfGoingOnBatteries=$true
        StartWhenAvailable=$true
        MultipleInstances='IgnoreNew'
        ExecutionTimeLimit=[TimeSpan]::Zero
        RestartCount=3
        RestartInterval=(New-TimeSpan -Minutes 1)
    }
    $settings = New-ScheduledTaskSettingsSet @settingsArgs
    # No hidden task, SYSTEM account or elevated execution.
    return New-ScheduledTask -Action $taskAction -Trigger $trigger -Principal $principal -Settings $settings -Description $Description
}
if ($Action -eq 'Status') {
    foreach ($name in $names) {
        $task = Read-Task $name
        if ($null -eq $task) {
            [pscustomobject]@{Task=$name; State='NotInstalled'; LastResult=$null}
            continue
        }
        $info = Get-ScheduledTaskInfo -TaskName $name -TaskPath '\'
        [pscustomobject]@{Task=$name; State=$task.State.ToString(); LastResult=$info.LastTaskResult}
    }
    return
}
if ($Action -in @('Stop','Disable','Start')) {
    foreach ($name in $names) {
        $task = Read-Task $name
        if ($null -eq $task) { continue }
        if (-not $PSCmdlet.ShouldProcess($name,$Action)) { continue }
        switch ($Action) {
            'Stop' {
                if ($task.State -eq 'Running') { Stop-ScheduledTask -TaskName $name -TaskPath '\' }
                Disable-ScheduledTask -TaskName $name -TaskPath '\' | Out-Null
            }
            'Start' {
                Enable-ScheduledTask -TaskName $name -TaskPath '\' | Out-Null
                Start-ScheduledTask -TaskName $name -TaskPath '\'
            }
            'Disable' {
                if ($task.State -eq 'Running') { Stop-ScheduledTask -TaskName $name -TaskPath '\' }
                Disable-ScheduledTask -TaskName $name -TaskPath '\' | Out-Null
                Unregister-ScheduledTask -TaskName $name -TaskPath '\' -Confirm:$false
            }
        }
    }
    return
}
if (-not $OwnerConsent) {
    throw 'Se requiere -OwnerConsent tras informar al propietario sobre el inicio automatico y las funciones seleccionadas.'
}
if ($Mode -eq 'protect' -and -not $ConfirmExperimentalProtection) {
    throw 'El bloqueo facial es experimental. Usa observe o confirma expresamente -ConfirmExperimentalProtection en un equipo de pruebas.'
}
if ($LockedPhoto) {
    Write-Warning 'La foto de un intento fallido es opcional y puede no estar disponible si Windows restringe el acceso a la camara o esta ocupada.'
}
$resolvedPython = Resolve-ExistingFile $PythonExe 'PythonExe'
if ([IO.Path]::GetFileName($resolvedPython) -ine 'python.exe') {
    throw 'Selecciona python.exe, no pythonw.exe.'
}
$resolvedDetector = Resolve-ExistingFile $Detector 'Detector'
$resolvedRecognizer = Resolve-ExistingFile $Recognizer 'Recognizer'
$faceScript = Resolve-ExistingFile (Join-Path $agentDir 'guardian_agent.py') 'Agente facial'
$faceArgs = ('{0} monitor --detector {1} --recognizer {2} --mode {3}' -f (Quote-Argument $faceScript),(Quote-Argument $resolvedDetector),(Quote-Argument $resolvedRecognizer),$Mode)
$definitions = [ordered]@{}
$definitions[$faceName] = New-GuardianDefinition $faceArgs 'Guardian: agente facial interactivo autorizado por el propietario.'
if ($LockedLocation -or $LockedPhoto) {
    $lockedScript = Resolve-ExistingFile (Join-Path $agentDir 'guardian_locked_security.py') 'Monitor bloqueado'
    $lockedArgs = (Quote-Argument $lockedScript) + ' --monitor'
    if ($LockedLocation) { $lockedArgs += ' --track-location' }
    if ($LockedPhoto) { $lockedArgs += ' --capture-failed-unlock' }
    $definitions[$lockedName] = New-GuardianDefinition $lockedArgs 'Guardian: observaciones de acceso autorizadas por el propietario.'
}
if ($Action -eq 'Plan') {
    foreach ($entry in $definitions.GetEnumerator()) {
        [pscustomobject]@{Name=$entry.Key; Definition=$entry.Value}
    }
    return
}
$dataDir = Join-Path $env:APPDATA 'Guardian\agent'
foreach ($file in @('config.dat','biometrics.dat')) {
    if (-not (Test-Path -LiteralPath (Join-Path $dataDir $file) -PathType Leaf)) {
        throw 'Completa primero setup y enroll del agente bajo esta misma cuenta Windows.'
    }
}
if (-not $PSCmdlet.ShouldProcess($identity.Name,'Registrar e iniciar las tareas Guardian elegidas')) { return }
foreach ($name in $names) {
    $old = Read-Task $name
    if ($null -ne $old) {
        if ($old.State -eq 'Running') { Stop-ScheduledTask -TaskName $name -TaskPath '\' }
        Disable-ScheduledTask -TaskName $name -TaskPath '\' | Out-Null
        Unregister-ScheduledTask -TaskName $name -TaskPath '\' -Confirm:$false
    }
}
$registered = @()
try {
    foreach ($entry in $definitions.GetEnumerator()) {
        Register-ScheduledTask -TaskName $entry.Key -TaskPath '\' -InputObject $entry.Value -ErrorAction Stop | Out-Null
        $registered += $entry.Key
    }
    foreach ($name in $registered) { Start-ScheduledTask -TaskName $name -TaskPath '\' -ErrorAction Stop }
} catch {
    foreach ($name in $registered) {
        Stop-ScheduledTask -TaskName $name -TaskPath '\' -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $name -TaskPath '\' -Confirm:$false -ErrorAction SilentlyContinue
    }
    throw
}
Write-Output 'Tareas Guardian registradas e inicio solicitado. Usa Status para comprobarlas. Running no certifica que la camara o el bloqueo funcionen.'
