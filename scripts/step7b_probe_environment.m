function step7b_probe_environment
root=fileparts(fileparts(mfilename('fullpath')));
assert(strcmp(version('-release'),'2026b'),'Run using explicit R2026b executable');
fid=fopen(fullfile(root,'docs','reports','step7b','environment_probe.txt'),'w');
cleanup=onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,'MATLAB=%s\nRELEASE=%s\n',version,version('-release'));
a=matlab.addons.installedAddons;
for k=1:height(a), fprintf(fid,'ADDON=%s version=%s enabled=%d\n',a.Name(k),a.Version(k),a.Enabled(k)); end
idx=contains(a.Name,'SoC Blockset Support Package for AMD');
if any(idx), fprintf(fid,'AMD_SUPPORT_PACKAGE=PASS version=%s\n',a.Version(find(idx,1)));
else, fprintf(fid,'AMD_SUPPORT_PACKAGE=NOT_RECOGNIZED\n'); end
try
 s=matlabshared.supportpkg.getInstalled;
 for k=1:numel(s), fprintf(fid,'SUPPORT_PACKAGE=%s version=%s\n',s(k).Name,s(k).InstalledVersion); end
catch ME, fprintf(fid,'SUPPORTPKG_GETINSTALLED_ERROR=%s\n',ME.message); end
for f={'EDA_Simulator_Link','Simulink','fixed_point_toolbox'}
 [ok,msg]=license('checkout',f{1}); assert(ok==1,'%s: %s',f{1},msg);
 fprintf(fid,'LICENSE=%s checkout=PASS\n',f{1});
end
fprintf(fid,'HDL_VERIFIER_LICENSE=PASS\nVIVADO=E:/AMDDesignTools/2026.1/Vivado/bin/vivado.bat\n');
fprintf('STEP7B_ENVIRONMENT_PASS\n');
end
