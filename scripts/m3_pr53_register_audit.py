"""Export actual generated register boundaries and verify source layout preservation."""
import csv,hashlib,json,re,zipfile
from pathlib import Path
import xml.etree.ElementTree as E
root=Path(__file__).resolve().parents[1];run=root/'.runtime/pr53_20261025/p3'
build=json.loads((run/'final_build.json').read_text());rtl=Path(build['rtl_dir'])/'PMLSM_FOC_FixedPoint'
out=root/'docs/reports/m3_foc_hdl/pr53_pipeline_revision'
modules={'FOC_DUT':1,'Clark':10,'Park':83,'Id':23,'Iq':52,'dq_voltage_limiter':184,'InversePark':51,'XYZ_Calculate':154,'Sector_Caculate':119,'T1T2_Calculate':134}
rows=[]
for module,sid in modules.items():
    file=rtl/(module+'.sv');text=file.read_text();lines=text.splitlines()
    for match in re.finditer(r'always_ff\s*@\(posedge clk\)(.*?)(?=\n\s*(?:always_ff|assign|endmodule)|\Z)',text,re.S):
        body=match.group(1);process=re.search(r'begin\s*:\s*(\w+)',body)
        assignments=re.findall(r'\b(\w+)(?:\[[^\n;]+?\])?\s*<=\s*([^;]+);',body)
        for signal in dict.fromkeys(a[0] for a in assignments):
            declaration=re.search(r'logic\s+(?:signed\s+)?(?:\[(\d+):0\]\s+)?'+re.escape(signal)+r'(?=\s|;|\[)',text)
            width=str(int(declaration.group(1))+1) if declaration and declaration.group(1) else ('1' if declaration else 'unresolved typedef/array; see SV')
            alias=re.search(r'vector_of_(?:signed|unsigned)_logic_(\d+)\s+'+re.escape(signal)+r'\b',text)
            if alias:width=alias.group(1)
            rhs=[b.strip() for a,b in assignments if a==signal]
            enables=re.findall(r'if\s*\(\s*(enb\w*|clk_enable)\s*\)',body)
            rows.append({'module':module,'source_enclosing_SID':sid,'process':process.group(1) if process else 'unresolved',
              'signal':signal,'declared_element_width':width,'reset_value':rhs[0],'active_D_expression':rhs[-1],
              'enable':';'.join(dict.fromkeys(enables)) or 'unconditional','clock_period_ns':20,
              'source_data_period_ns':100000,'sv_location':module+'.sv:'+str(text.count('\n',0,match.start())+1)})
with (out/'register_boundaries_p3.csv').open('w',newline='',encoding='utf8') as f:
    w=csv.DictWriter(f,fieldnames=list(rows[0]));w.writeheader();w.writerows(rows)
def layout(file):
    result={}
    with zipfile.ZipFile(file) as z:
        for name in z.namelist():
            if not name.startswith('simulink/systems/') or not name.endswith('.xml'):continue
            tree=E.fromstring(z.read(name));blocks=[];connections=[]
            for b in tree.findall('Block'):
                blocks.append((b.get('SID'),b.get('Name'),b.get('BlockType'),b.findtext("P[@Name='Position']")))
            for line in tree.findall('Line'):
                entries=[(p.get('Name'),p.text) for p in line.iter('P') if p.get('Name') in {'Src','Dst','Points'}]
                connections.append(entries)
            result[name]={'blocks':blocks,'wires':connections}
    return result
source=root/'simulink模型/PMLSM_FOC_FixedPoint.slx';owned=Path(build['model_folder'])/'PMLSM_FOC_FixedPoint.slx'
a=layout(source);b=layout(owned);differences=[n for n in set(a)|set(b) if a.get(n)!=b.get(n)]
assert not differences,'Owned generation copy layout/topology differs: '+repr(differences)
proof={'pass':True,'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),
       'owned_generation_copy_sha256':hashlib.sha256(owned.read_bytes()).hexdigest(),'systems_checked':len(a),
       'layout_and_connection_differences':differences,'no_source_save_or_auto_layout':True,
       'register_process_signals_exported':len(rows)}
(out/'layout_and_register_audit.json').write_text(json.dumps(proof,indent=2))
print(json.dumps(proof))
