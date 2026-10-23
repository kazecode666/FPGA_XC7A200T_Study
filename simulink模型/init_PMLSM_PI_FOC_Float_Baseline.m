% Explicit M1A defaults. Execute this script in Base Workspace before Run.
% Re-execution resets all public defaults; no MAT or automatic callback load.

% Motor: phase quantities, A peak, mechanical SI internally.
PMLSM_Rs_ohm=2.37;
PMLSM_Ld_H=1.745e-3; PMLSM_Lq_H=PMLSM_Ld_H;
PMLSM_psi_f_Wb=0.141; PMLSM_M_kg=0.91;
PMLSM_Kf_peak_N_per_Apeak=31.4/sqrt(2);
PMLSM_tau_NN_m=0.06; PMLSM_theta_offset_rad=0;
PMLSM_Bv_N_per_mps=0; PMLSM_Fc_N=0; PMLSM_v_eps_mps=1e-3;
Udc=48;

% Single timebase; plant refinement must not change any control period.
T_pwm=1e-4; Ts_ACR=T_pwm; Ts=Ts_ACR;
Ts_ASR=10*Ts_ACR; Ts_POS=10*Ts_ASR;
Ts_Plant=1e-6; PMLSM_Ts_s=Ts_Plant;
M1A_PWM_Update_Delay_s=T_pwm/2;
M1A_StopTime_s=1.2;

% Original tuning family; no retuning or DSP/MIL overrides.
Tuning_Current_Xi=1/sqrt(2); Tuning_Speed_h=10; Tuning_Position_Separation=20;
Tuning_Gains=design_PMLSM_three_loop(PMLSM_Rs_ohm,PMLSM_Ld_H, ...
    PMLSM_M_kg,PMLSM_Kf_peak_N_per_Apeak,Ts_ACR,Ts_ASR,Ts_POS, ...
    Tuning_Current_Xi,Tuning_Speed_h,Tuning_Position_Separation);
Kp_ACR=Tuning_Gains.Kp_ACR; Ki_ACR=Tuning_Gains.Ki_ACR;
Kaw_d=Tuning_Gains.Kaw_d; Kaw_q=Tuning_Gains.Kaw_q;
Kp_ASR=Tuning_Gains.Kp_ASR; Ki_ASR=Tuning_Gains.Ki_ASR;
Kaw_s=Tuning_Gains.Kaw_s; Kp_pos=Tuning_Gains.Kp_pos;
assert(abs(Kp_ACR-8.725)<1e-12 && abs(Ki_ACR-11850)<1e-9);
Iq_int_limit=0.5; Speed_loop_Iq_Limit=1;
Pos_deadband=0.02; V_pos_max_mmps=20;
v_ff_eps=0.5; v_over_eps=3; v_ref_max=20;
v_ref_set_rate_dn=50; v_ref_set_rate_up=50;
v_ref_set_step_dn=v_ref_set_rate_dn*Ts_ACR;
v_ref_set_step_up=v_ref_set_rate_up*Ts_ACR;
v_ref_zero_eps=0;

% Average inverter: one deadtime effect; ideal comparison sets deadtime to 0.
PMLSM_deadtime_s=1e-6;
PMLSM_deadtime_ratio=PMLSM_deadtime_s/T_pwm;
PMLSM_deadtime_current_eps_A=1e-4;

% Default position scene: 1 mm / 1.2 s / zero load; host units mm and mm/s.
Host_Enable_Schedule=[0 1 1 1];
Host_Id_A=0; Host_Iq_A=0; Host_Iq_Test_Mode=0; Host_PI_Reset_EN=0;
Host_Speed_Ramp_s=0.1; Host_Speed_mmps=0;
Host_Start_s=0.05; Host_Target_mm=1;
Host_Traj_Amax=50; Host_Traj_Jmax=1000; Host_Traj_Vmax=5;
Host_Load_N=0;
M1A_Load_ts=timeseries([0;0],[0;M1A_StopTime_s]);
M1A_LoadStep_ts=timeseries([0;0.5;0;0],[0;0.8;1.0;M1A_StopTime_s]);
M1A_PWM_ts=timeseries([1;1],[0;M1A_StopTime_s]);
M1A_Reset_ts=timeseries([0;0],[0;M1A_StopTime_s]);
M1A_Speed_ts=timeseries([0;0],[0;M1A_StopTime_s]);
M1A_Load_ts=setinterpmethod(M1A_Load_ts,'zoh');
M1A_LoadStep_ts=setinterpmethod(M1A_LoadStep_ts,'zoh');
M1A_PWM_ts=setinterpmethod(M1A_PWM_ts,'zoh');
M1A_Reset_ts=setinterpmethod(M1A_Reset_ts,'zoh');
M1A_Speed_ts=setinterpmethod(M1A_Speed_ts,'zoh');

% Written last. Other models' old Kp/Udc values cannot satisfy this contract.
PMLSM_M1A_InitVersion=20261023;
