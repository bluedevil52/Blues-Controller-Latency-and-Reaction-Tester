param(
    # Give the path to the standard Godot 4.7.2 editor executable.
    [Parameter(Mandatory = $true)]
    [string]$GodotPath
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$engine = (Resolve-Path -LiteralPath $GodotPath).Path
# A unique folder preserves previous builds rather than cleaning or replacing them.
$buildFolder = Join-Path $projectRoot ('release/build-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
New-Item -ItemType Directory -Path $buildFolder | Out-Null
$exePath = Join-Path $buildFolder 'BluesControllerLatencyAndReactionTester.exe'
$logPath = Join-Path $buildFolder 'export.log'
# Start-Process needs quotes around arguments containing spaces.
$arguments = '--headless --path "{0}" --export-release "Windows Desktop" "{1}" --log-file "{2}"' -f $projectRoot, $exePath, $logPath
$build = Start-Process -FilePath $engine -ArgumentList $arguments -WindowStyle Hidden -Wait -PassThru
if ($build.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $exePath)) {
    throw "Export failed. Read $logPath and check the matching export templates are installed."
}
# Engine processes can report script errors even with an exit code of zero.
$smokeLog = Join-Path $buildFolder 'startup-check.log'
$smokeArgs = '--headless --quit-after 10 --log-file "{0}"' -f $smokeLog
$smoke = Start-Process -FilePath $exePath -ArgumentList $smokeArgs -WorkingDirectory $buildFolder -WindowStyle Hidden -Wait -PassThru
if ($smoke.ExitCode -ne 0 -or -not (Test-Path $smokeLog) -or (Select-String -Path $smokeLog -Pattern 'SCRIPT ERROR:|ERROR:' -Quiet)) {
    throw "Standalone startup failed. Read $smokeLog."
}
Copy-Item -LiteralPath (Join-Path $projectRoot 'START HERE.md'), (Join-Path $projectRoot 'THIRD_PARTY_NOTICES.txt') -Destination $buildFolder
Write-Output "Ready to run: $exePath"
