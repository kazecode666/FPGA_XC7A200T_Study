"""Fail closed on candidate identity, scheduled phase, and state-event drift."""
import argparse
import json
from pathlib import Path

def validate(contract, identity):
    for key in ('candidate_id','configuration_sha256'):
        if contract.get(key)!=identity.get(key) or not contract.get(key):
            raise ValueError('candidate contract identity mismatch: '+key)
    phase=contract.get('output_phase_cycles')
    if not isinstance(phase,int) or not 0<phase<=2498:
        raise ValueError('candidate phase exceeds unchanged PWM budget')
    if 'output_phase_cycles' in identity and phase!=identity['output_phase_cycles']:
        raise ValueError('candidate output schedule mismatch')
    events=contract.get('state_events',{})
    if events!={'pi_consume':5000,'pi_commit':5000,'aw_commit':1}:
        raise ValueError('missing or changed state mapping requires explicit requalification')
    if set(contract.get('state_mapping',{}))!={'x_d_old','x_q_old','aw_d_old','aw_q_old'}:
        raise ValueError('missing explicit state signal mapping')
    if contract.get('frame_cycles')!=5000 or not contract.get('schedule_evidence'):
        raise ValueError('missing generated schedule or frame contract')
    return contract

def main():
    p=argparse.ArgumentParser();p.add_argument('--manifest',required=True);p.add_argument('--contract',required=True)
    a=p.parse_args();m=json.loads(Path(a.manifest).read_text(encoding='utf-8-sig'))
    c=json.loads(Path(a.contract).read_text(encoding='utf-8-sig'))
    import hashlib
    if hashlib.sha256(Path(a.contract).read_bytes()).hexdigest()!=m['candidate_contract']['sha256']:
        raise ValueError('candidate contract hash mismatch')
    validate(c,{'candidate_id':m['candidate_id'],'configuration_sha256':m['build_identity']['configuration_sha256']})
    print(json.dumps(c))
if __name__=='__main__':main()
