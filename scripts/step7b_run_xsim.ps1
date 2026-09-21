param([ValidateSet('red','wrapper','d6p0','d6p1','e6','all')][string]$Mode='all')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$bin='E:/AMDDesignTools/2026.1/Vivado/bin'
$names='mc_fxp_pkg mc_clarke mc_sincos_lut mc_park mc_inv_park mc_current_transform mc_pi_fxp_pkg mc_isqrt_u80 mc_udiv_u72_u41 mc_pi_dq_eval mc_dq_limiter mc_pi_dq_core mc_svpwm_pkg mc_svpwm_sector_xyz mc_sector_svpwm mc_foc_current_core'.Split(' ')
$sources=@($names | ForEach-Object {Join-Path $root "motor_control_ip/foc/rtl/$_.sv"})
$sources+=@('motor_control_ip/pwm/rtl/motor_pwm_core.sv','motor_control_ip/integration/rtl/mc_duty_to_cmp.sv','motor_control_ip/integration/rtl/mc_foc_pwm_top.sv') | ForEach-Object {Join-Path $root $_}
function Invoke-Test([string]$test){
 $work=Join-Path $root ('.Xil/step7b_'+$test+'_'+[guid]::NewGuid().ToString('N').Substring(0,8))
 New-Item -ItemType Directory $work | Out-Null
 Copy-Item -LiteralPath (Join-Path $root 'motor_control_ip/foc/rom/sin_qw_4096x18.mem') -Destination $work
 Copy-Item -LiteralPath (Join-Path $root 'motor_control_ip/integration/tb/vectors/step6d_pwm_vectors.txt') -Destination $work
 $files=@($sources); $generic=@()
 if($test -in @('wrapper','red')){
  $top='mc_foc_cosim_top_tb';$marker='STEP7B_FOC_WRAPPER_PASS';$log='foc_wrapper_xsim.txt'
  if($test -ne 'red'){$files+=Join-Path $root 'motor_control_ip/integration/rtl/mc_foc_cosim_top.sv'}
 }elseif($test -eq 'e6'){
  $top='mc_foc_gate_top_tb';$marker='ALL STEP 6E';$log='step6e_regression.txt'
  $files+=Join-Path $root 'motor_control_ip/pwm/rtl/mc_pwm_deadtime_leg.sv'
  $files+=Join-Path $root 'motor_control_ip/integration/rtl/mc_foc_gate_top.sv'
  $generic=@('-generic_top','"PI_PROFILE=0"','-generic_top','"DEMO=0"')
 }else{
  $profile=if($test -eq 'd6p0'){0}else{1}
  $top='mc_foc_pwm_top_tb';$marker="ALL STEP 6D FOC PWM TESTS PASSED profile=$profile";$log="step6d_profile$profile.txt"
  $generic=@('-generic_top',('"PI_PROFILE='+$profile+'"'),'-generic_top','"DEMO=0"')
 }
 $files+=Join-Path $root "motor_control_ip/integration/tb/$top.sv"
 Push-Location $work
 try {
  $output=@(& "$bin/xvlog.bat" -sv @files 2>&1); $rc=$LASTEXITCODE
  if($rc -eq 0){$output+=& "$bin/xelab.bat" $top -s step7b_snapshot @generic 2>&1;$rc=$LASTEXITCODE}
  if($test -eq 'red'){
   $output | Set-Content (Join-Path $root '.superpowers/sdd/step7b_simulink_hdl_cosim_local_integration/task3_red.txt')
   if($rc -eq 0 -or ($output -join "`n") -notmatch 'ERROR:.*mc_foc_cosim_top'){throw 'Expected missing wrapper failure'}
   Write-Output 'EXPECTED_RED missing mc_foc_cosim_top';return
  }
  if($rc -eq 0){$output+=& "$bin/xsim.bat" step7b_snapshot -runall 2>&1;$rc=$LASTEXITCODE}
  $output | ForEach-Object {$_.ToString().TrimEnd()} | Set-Content (Join-Path $root "docs/reports/step7b/$log")
  if($rc -ne 0 -or ($output -join "`n") -notmatch [regex]::Escape($marker) -or ($output -join "`n") -match '(?m)^(ERROR|Fatal|FATAL)') {throw "$test failed; inspect $log"}
  $output | Select-String $marker
 }finally{Pop-Location}
}
if($Mode -eq 'all'){foreach($test in @('wrapper','d6p0','d6p1','e6')){Invoke-Test $test}}
else{Invoke-Test $Mode}
