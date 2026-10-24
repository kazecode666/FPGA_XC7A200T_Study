function m3_pr53_inspect(out)
% Read isolated baseline and installed example without running example init.
root=fileparts(fileparts(mfilename('fullpath')));mkdir(out);
b=jsondecode(fileread(fullfile(root,'.runtime/m3_20261024_001/final_build.json')));
folder=fullfile(out,'model');mkdir(folder);copyfile(fullfile(b.model_folder,'*'),folder);
cd(folder);addpath(folder);evalin('base','init_PMLSM_PI_FOC_Float_Baseline;');
m='PMLSM_FOC_FixedPoint';load_system(fullfile(folder,[m '.slx']));
blocks=find_system([m '/FOC_DUT'],'LookUnderMasks','all','Type','Block');
rows=cell(0,8);
for k=1:numel(blocks)
 p=blocks{k};bt=get_param(p,'BlockType');
 if strcmp(bt,'SubSystem')||contains(p,{'InversePark','XYZ Calculate','Sector','T1T2','PI'})
  row={p,get_param(p,'SID'),bt,'','','','',''};
  try,row{4}=get_param(p,'TreatAsAtomicUnit');catch,end
  for j=1:4
   keys={'DistributedPipelining','InputPipeline','OutputPipeline','FlattenHierarchy'};
   try,v=hdlget_param(p,keys{j});if isnumeric(v),v=mat2str(v);end;row{j+4}=v;catch e,row{j+4}=e.identifier;end
  end
  rows(end+1,:)=row; %#ok<AGROW>
 end
end
writetable(cell2table(rows,'VariableNames',{'path','SID','type','atomic','distributed','input_pipeline','output_pipeline','flatten'}),fullfile(out,'block_properties.csv'),'QuoteStrings',true);
fprintf('MODEL_DIST=%s\n',hdlget_param(m,'DistributedPipelining'));
example=which('hdlcoderFocCurrentFixptHdl.slx');fprintf('EXAMPLE_FILE=%s\n',example);
if ~isempty(example),copyfile(example,fullfile(out,'hdlcoderFocCurrentFixptHdl.slx'));end
close_system(m,0);
end
