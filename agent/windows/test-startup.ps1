# Validate task definitions without registering tasks, camera access or credentials.
$ErrorActionPreference = 'Stop'
$script = Join-Path $PSScriptRoot 'manage-startup.ps1'
$tokens = $null
$errors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($script,[ref]$tokens,[ref]$errors)
if ($errors.Count -ne 0) { throw ($errors | Out-String) }
$python = (Get-Command python.exe -ErrorAction Stop).Source
$temp = Join-Path $env:RUNNER_TEMP ('guardian startup test ' + [guid]::NewGuid().ToString())
New-Item -ItemType Directory -Path $temp | Out-Null
try {
    $detector = Join-Path $temp 'detector.onnx'
    $recognizer = Join-Path $temp 'recognizer.onnx'
    New-Item -ItemType File -Path $detector,$recognizer | Out-Null
    $params = @{Action='Plan';PythonExe=$python;Detector=$detector;Recognizer=$recognizer}
    $rejected = $false
    try { & $script @params | Out-Null } catch { $rejected = $true }
    if (-not $rejected) { throw 'Consent must be explicit.' }
    $one = @(& $script @params -OwnerConsent)
    if ($one.Count -ne 1) { throw 'Default must not enable optional locked-session monitoring.' }
    $both = @(& $script @params -OwnerConsent -LockedLocation)
    if ($both.Count -ne 2) { throw 'Expected two independent task definitions.' }
    foreach ($entry in $both) {
        $def = $entry.Definition
        if ($def.Settings.Hidden) { throw 'Tasks must not be hidden.' }
        if ($def.Principal.RunLevel.ToString() -ne 'Limited') { throw 'Unexpected elevation.' }
        if ($def.Principal.LogonType.ToString() -ne 'Interactive') { throw 'Expected interactive logon.' }
        if ($def.Settings.RestartCount -ne 3) { throw 'Missing bounded restart policy.' }
        if ($def.Triggers.Count -ne 1) { throw 'Missing logon trigger.' }
    }
    if ($both[0].Definition.Actions[0].Arguments -notmatch '--mode observe') { throw 'Unsafe default mode.' }
    if ($both[1].Definition.Actions[0].Arguments -match '--capture-failed-unlock') { throw 'Photo must be opted in.' }
    $rejected = $false
    try { & $script @params -OwnerConsent -Mode protect | Out-Null } catch { $rejected = $true }
    if (-not $rejected) { throw 'Experimental protection must be explicitly confirmed.' }
    Write-Output 'Guardian startup task definition checks passed.'
} finally {
    Remove-Item -LiteralPath $temp -Recurse -Force
}
