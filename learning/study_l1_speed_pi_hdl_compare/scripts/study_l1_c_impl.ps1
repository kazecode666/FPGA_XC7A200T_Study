param(
    [Parameter(Mandatory=$true)][ValidateSet('hand','baseline','csd')][string]$Variant,
    [Parameter(Mandatory=$true)][string]$RunDirectory,
    [string]$CoderDirectory
)
$ErrorActionPreference='Stop'
if (Test-Path -LiteralPath $RunDirectory) { throw 'Fresh directory required' }
New-Item -ItemType Directory -Path $RunDirectory | Out-Null
$study=Split-Path $PSScriptRoot -Parent
if (-not $CoderDirectory) { $CoderDirectory="$study/generated_hdl/baseline" }
Push-Location $RunDirectory
try {
    & 'E:/AMDDesignTools/2026.1/Vivado/bin/vivado.bat' -mode batch -source "$PSScriptRoot/study_l1_c_vivado.tcl" -tclargs $Variant $CoderDirectory "$RunDirectory/reports" xc7a200tfbg484-2
    if ($LASTEXITCODE -ne 0) { throw 'Vivado failed' }
    $log=Get-Content -LiteralPath vivado.log -Raw
    if ($log -notmatch 'STUDY_L1_C_IMPLEMENTATION_COMPLETE' -or $log -match 'ERROR:') { throw 'Implementation gate failed' }
} finally { Pop-Location }
