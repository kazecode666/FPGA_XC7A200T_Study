param(
    [Parameter(Mandatory=$true)][ValidateSet('hand','baseline','csd')][string]$Variant,
    [Parameter(Mandatory=$true)][string]$GoldenDirectory,
    [Parameter(Mandatory=$true)][string]$RunDirectory,
    [string]$CoderDirectory
)
$ErrorActionPreference='Stop'
$toolDirectory='E:/AMDDesignTools/2026.1/Vivado/bin'
$study=Split-Path $PSScriptRoot -Parent
if (Test-Path -LiteralPath $RunDirectory) { throw 'Fresh directory required' }
New-Item -ItemType Directory -Path $RunDirectory | Out-Null
$sourceFiles=@()
$defines=@()
if ($Variant -eq 'hand') {
    $sourceFiles+= "$study/handwritten/speed_pi_sv.sv"
    $defines=@('-d','HAND_SV')
} else {
    if (-not $CoderDirectory) { $CoderDirectory="$study/generated_hdl/baseline" }
    $sourceFiles+=@("$CoderDirectory/PI.sv","$CoderDirectory/HDLCore.sv")
}
$sourceFiles+=@("$study/handwritten/speed_pi_compare.sv","$PSScriptRoot/study_l1_c_tb.sv")
Push-Location $RunDirectory
try {
    & "$toolDirectory/xvlog.bat" -sv @defines @sourceFiles
    if ($LASTEXITCODE -ne 0) { throw 'xvlog failed' }
    & "$toolDirectory/xelab.bat" study_l1_c_tb -debug typical -s study_l1_c
    if ($LASTEXITCODE -ne 0) { throw 'xelab failed' }
    $normal='"NORMAL=' + (($GoldenDirectory+'/normal_vectors.txt') -replace '\\','/') + '"'
    $stress='"STRESS=' + (($GoldenDirectory+'/stress_vectors.txt') -replace '\\','/') + '"'
    $trace='"TRACE=' + (($RunDirectory+'/trace.csv') -replace '\\','/') + '"'
    & "$toolDirectory/xsim.bat" study_l1_c -runall -testplusarg $normal -testplusarg $stress -testplusarg $trace
    if ($LASTEXITCODE -ne 0) { throw 'xsim failed' }
    $log=Get-Content -LiteralPath xsim.log -Raw
    if ($log -notmatch 'STUDY_L1_C_XSIM_PASS .*raw_mismatches=0' -or $log -match 'Fatal:|Error:') { throw 'Bit-exact gate failed' }
} finally { Pop-Location }
