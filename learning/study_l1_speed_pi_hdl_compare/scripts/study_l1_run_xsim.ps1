param(
    [Parameter(Mandatory=$true)][string]$GeneratedDirectory,
    [Parameter(Mandatory=$true)][string]$Vectors,
    [Parameter(Mandatory=$true)][string]$RunDirectory
)
$ErrorActionPreference='Stop'
$toolDirectory='E:/AMDDesignTools/2026.1/Vivado/bin'
if (Test-Path -LiteralPath $RunDirectory) { throw 'Use a fresh XSim run directory.' }
New-Item -ItemType Directory -Path $RunDirectory | Out-Null
$scriptDirectory=$PSScriptRoot
Push-Location $RunDirectory
try {
    & "$toolDirectory/xvlog.bat" -sv "$GeneratedDirectory/PI.sv" "$GeneratedDirectory/HDLCore.sv" "$scriptDirectory/study_l1_generated_tb.sv"
    if ($LASTEXITCODE -ne 0) { throw 'xvlog failed' }
    & "$toolDirectory/xelab.bat" study_l1_generated_tb -debug typical -s study_l1_baseline
    if ($LASTEXITCODE -ne 0) { throw 'xelab failed' }
    # Literal quotes preserve '=' through Vivado's Windows .bat loader.
    $vectorArgument='"VECTORS=' + ($Vectors -replace '\\','/') + '"'
    $traceArgument='"TRACE=' + (($RunDirectory + '/trace.csv') -replace '\\','/') + '"'
    & "$toolDirectory/xsim.bat" study_l1_baseline -runall -testplusarg $vectorArgument -testplusarg $traceArgument
    if ($LASTEXITCODE -ne 0) { throw 'xsim failed' }
    $log=Get-Content -LiteralPath 'xsim.log' -Raw
    if ($log -notmatch 'STUDY_L1_XSIM_PASS rows=2580 ticks=258 fields=14 raw_mismatches=0' -or $log -match 'Fatal:|Error:') {
        throw 'XSim did not satisfy the bit-exact gate.'
    }
} finally { Pop-Location }
