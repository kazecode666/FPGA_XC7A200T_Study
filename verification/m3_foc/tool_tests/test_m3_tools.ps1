#Requires -Version 7.0
[CmdletBinding()]
param([switch]$RunXsim)
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$runner = Join-Path $repo 'scripts/m3_run_xsim.ps1'
$area = Join-Path $repo ('.runtime/m3_tool_tests_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $area | Out-Null
function Assert-True($value, $message) { if (-not $value) { throw $message } }
function Run-Case([string]$label, [string]$manifest, [int]$expected) {
    $dir = Join-Path $area $label
    & (Join-Path $PSHOME 'pwsh.exe') -NoProfile -File $runner -Manifest $manifest -RunDir $dir *> (Join-Path $area ($label + '.console.txt'))
    $code = $LASTEXITCODE
    Assert-True ($code -eq $expected) "$label exit=$code expected=$expected"
    $reportFile = Join-Path $dir 'result.json'
    Assert-True (Test-Path -LiteralPath $reportFile -PathType Leaf) "$label missing result.json"
    return (Get-Content -LiteralPath $reportFile -Raw | ConvertFrom-Json)
}
$r = Run-Case 'missing_manifest' (Join-Path $area 'does_not_exist.json') 2
Assert-True ($r.status -eq 'FAIL') 'Missing manifest was not FAIL'
$base = [ordered]@{ schema_version = 1; root_dir = $area; dut_top = 'm3_tool_fixture'; tb_top = 'm3_tool_fixture_tb'; clock_port = 'clk'; part = 'xc7a200tfbg484-2'; clock_period_ns = 20; design_files = @(@{path='does_not_exist.sv';sha256=('0'*64)}); testbench_files = @(@{path='also_missing_tb.sv';sha256=('0'*64)}); data_files = @(); simulation = @{expected_frames=4; expected_checks=12; timeout_seconds=60} }
$m = Join-Path $area 'missing_artifact.json'; $base | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $m -Encoding utf8NoBOM
$r = Run-Case 'missing_artifact' $m 2
Assert-True ($r.failures[0] -match 'missing') 'Missing artifact reason absent'
$tamperedPath = Join-Path $area 'tampered_fixture.sv'
'module tampered_fixture; endmodule' | Set-Content -LiteralPath $tamperedPath -Encoding utf8NoBOM
$tampered = $base | ConvertTo-Json -Depth 10 | ConvertFrom-Json
$tampered.design_files = @(@{path='tampered_fixture.sv';sha256=('0'*64)})
$m = Join-Path $area 'tampered_artifact.json'; $tampered | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $m -Encoding utf8NoBOM
$r = Run-Case 'tampered_artifact' $m 2
Assert-True ($r.failures[0] -match 'hash mismatch') 'Changed artifact was not rejected before execution'
if ($RunXsim) {
    $design = Join-Path $area 'm3_tool_fixture.sv'
    $tb = Join-Path $area 'm3_tool_fixture_tb.sv'
    'module m3_tool_fixture(input logic clk, output logic q); always_ff @(posedge clk) q <= ~q; endmodule' | Set-Content -LiteralPath $design -Encoding utf8NoBOM
    @'
`timescale 1ns/1ps
module m3_tool_fixture_tb;
  logic clk=0; wire q; m3_tool_fixture d(clk,q); always #10 clk=~clk;
  string vector_path, result_path; integer input_file, output_file;
  initial begin
    if (!$value$plusargs("vectors=%s",vector_path)) $fatal(1,"M3_RTL_FAIL missing vectors plusarg");
    input_file=$fopen(vector_path,"r");
    if (!input_file) $fatal(1,"M3_RTL_FAIL staged input path could not be opened");
    $fclose(input_file);
    if (!$value$plusargs("result=%s",result_path)) $fatal(1,"M3_RTL_FAIL missing result plusarg");
    output_file=$fopen(result_path,"w");
    if (!output_file) $fatal(1,"M3_RTL_FAIL result path could not be opened");
    $fwrite(output_file,"fixture_path_roundtrip_pass\n"); $fclose(output_file);
    #100;
`ifdef M3_TOOL_ZERO
    $display("M3_RTL_PASS frames=0 checks=0 bit_mismatch=0 protocol_errors=0 deadline_errors=0");
`elsif M3_TOOL_FAIL
    $fatal(1,"M3_RTL_FAIL intentional fixture failure");
`else
    $display("M3_RTL_PASS frames=4 checks=12 bit_mismatch=0 protocol_errors=0 deadline_errors=0");
`endif
    $finish;
  end
endmodule
'@ | Set-Content -LiteralPath $tb -Encoding utf8NoBOM
    $base.design_files = @(@{path='m3_tool_fixture.sv';sha256=(Get-FileHash -LiteralPath $design -Algorithm SHA256).Hash.ToLowerInvariant()})
    $base.testbench_files = @(@{path='m3_tool_fixture_tb.sv';sha256=(Get-FileHash -LiteralPath $tb -Algorithm SHA256).Hash.ToLowerInvariant()})
    $vector = Join-Path $area 'fixture_data.mem'
    '0123456789abcdef' | Set-Content -LiteralPath $vector -Encoding utf8NoBOM
    $base.data_files = @(@{path='fixture_data.mem';sha256=(Get-FileHash -LiteralPath $vector -Algorithm SHA256).Hash.ToLowerInvariant()})
    $base.simulation.plusarg_files = @{vectors='fixture_data.mem'}
    $base.simulation.plusarg_outputs = @{result='fixture_result.txt'}
    $m = Join-Path $area 'valid_fixture.json'; $base | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $m -Encoding utf8NoBOM
    $r = Run-Case 'valid_fixture' $m 0
    Assert-True ($r.observed_frames -eq 4 -and $r.observed_checks -eq 12) 'Fixture counts absent'
    Assert-True ((Get-Content -LiteralPath (Join-Path $area 'valid_fixture/fixture_result.txt') -Raw).Trim() -eq 'fixture_path_roundtrip_pass') 'Forward-slash input/output plusarg roundtrip failed'
    $base.defines = @('M3_TOOL_ZERO')
    $m = Join-Path $area 'zero_fixture.json'; $base | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $m -Encoding utf8NoBOM
    $r = Run-Case 'zero_fixture' $m 2
    Assert-True ($r.failures[0] -match 'count|zero|frames') 'Zero-count rejection absent'
    $base.defines = @('M3_TOOL_FAIL')
    $m = Join-Path $area 'fatal_fixture.json'; $base | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $m -Encoding utf8NoBOM
    $r = Run-Case 'fatal_fixture' $m 2
    Assert-True ($r.status -eq 'FAIL') 'Fatal fixture accepted'
}
Write-Output "M3_TOOL_TESTS_PASS scope=runner_only actual_FOC_not_tested evidence=$area xsim=$RunXsim"
