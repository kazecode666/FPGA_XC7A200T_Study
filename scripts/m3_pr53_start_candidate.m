function m3_pr53_start_candidate(id)
% Each call freezes latest local source and uses a new isolated generation.
root=fileparts(fileparts(mfilename('fullpath')));runDir=fullfile(root,'.runtime','pr53_20261025',id);
assert(~isfolder(runDir),'M3:EVIDENCE_EXISTS','Preserve the existing candidate.');mkdir(runDir);
settings=struct('SID',{},'property',{},'value',{},'reason',{});
add(1,'DistributedPipelining','on','Distribute local supplied pipeline budgets across combinational transform chain');
piDistributed='off';if ~strcmp(id,'p1'),piDistributed='on';end
add(23,'DistributedPipelining',piDistributed,'Protect p1 PI region; p2 splits the measured exposed PI path');
add(52,'DistributedPipelining',piDistributed,'Symmetric PI treatment');
for sid=[184 95 154 119 134]
 add(sid,'DistributedPipelining','on','R1 traced limiter to modulation chain');
end
for pair=[184 4;51 6;154 4;119 1;134 4]'
 add(pair(1),'OutputPipeline',pair(2),'Supply fast-clock registers at identified arithmetic boundaries; HDL Coder balances bypass');
end
if ~strcmp(id,'p1')
 if strcmp(id,'p2')
  for sid=[47 78 213 214 215]
   add(sid,'AllowDelayDistribution','off','p2 hypothesis: preserve physical algorithm state boundaries; generation must reject if this blocks balancing');
  end
 end
 add(83,'OutputPipeline',12,'p1 worst path crosses unsegmented Park including lookup/projection before PI and sqrt');
 add(10,'DistributedPipelining','on','Clark bypass must be balanced with newly segmented Park path');
 add(10,'OutputPipeline',3,'Local front transform registers');
 for sid=[23 52]
  add(sid,'OutputPipeline',6,'Split PI constant multiply saturated sum and feedforward path before limiter sqrt');
 end
end
candidate=struct('candidate_id',id,'hypothesis','segment limiter inversePark XYZ sector and time numerator preserving numerical model','settings',settings);
fid=fopen(fullfile(runDir,'candidate.json'),'w');fprintf(fid,'%s',jsonencode(candidate,PrettyPrint=true));fclose(fid);
r=m3_foc_hdl('preflight',runDir);assert(strcmp(r.status,'PASS'),'M3:PREFLIGHT','Candidate preflight failed.');
r=m3_foc_hdl('generate',runDir);assert(strcmp(r.status,'PASS'),'M3:GENERATION','Candidate generation failed; see stage evidence.');
    function add(sid,property,value,reason)
        settings(end+1)=struct('SID',sid,'property',property,'value',value,'reason',reason);
    end
end
