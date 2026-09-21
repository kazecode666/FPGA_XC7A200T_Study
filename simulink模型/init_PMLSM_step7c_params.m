% Static backend; independent Step7C configuration only.
CONTROL_BACKEND=0;
FPGA_Reference_Mode=0;
V_Backend_Legacy=Simulink.Variant('CONTROL_BACKEND == 0');
V_Backend_FPGA=Simulink.Variant('CONTROL_BACKEND == 1');
STEP7C_Comm_Ts_s=1e-6;
STEP7C_Convergence_Ts_s=0.5e-6;
STEP7C_StopTime_s=31e-3;
STEP7C_Id_Ref_A=0;
STEP7C_Iq_Profile_Time_s=[0 1e-3 11e-3 16e-3 26e-3 31e-3]';
STEP7C_Iq_Profile_A=[0 0.5 0 -0.5 0 0]';
STEP7C_Vdc_V=48;
STEP7C_Load_N=0;
STEP7C_PI_PROFILE=0;
