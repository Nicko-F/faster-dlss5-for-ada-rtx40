"""Build selected Ada kernels from local PTX; source inputs are never modified."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(Path(__file__).parent/'optimizations'))
from kernel_pipeline import source_entries, apply_recipe


def build(ptx_dir,output,compiler,only=(),jobs=4):
    ptx_dir=ptx_dir.resolve(strict=True);output=output.resolve()
    if output.is_relative_to(ptx_dir) or ptx_dir.is_relative_to(output):
        raise ValueError('Keep the build output separate from the PTX input directory')
    if not 1<=jobs<=16:raise ValueError('Use between 1 and 16 compiler jobs')
    compiler=Path(compiler).resolve(strict=True)
    recipes=json.loads((ROOT/'config/kernel-recipes.json').read_text())['kernels']
    if only:
        missing=set(only)-{r['filename'] for r in recipes}
        if missing:raise ValueError('Unknown kernel selection: '+', '.join(sorted(missing)))
        recipes=[r for r in recipes if r['filename'] in only]
    entries=source_entries(ptx_dir)
    generated={}
    for r in recipes:
        if not re.fullmatch(r'(?:integrated-\d{2}|frontback-(?:pre|post))\.cubin',r['filename']):
            raise ValueError('Invalid output filename')
        generated[r['filename']]=apply_recipe(entries,r)
    # All transforms must succeed before creating an output directory.
    output.mkdir(parents=True,exist_ok=False)
    version=subprocess.run([str(compiler),'--version'],capture_output=True,text=True,check=True,timeout=30).stdout.strip()
    receipt=dict(schemaVersion=1,status='building',compilerVersion=version,
        compilerSha256=hashlib.sha256(compiler.read_bytes()).hexdigest(),kernels=[])
    def compile_one(r):
        name=r['filename'];ptx=output/Path(name).with_suffix('.ptx');cubin=output/name
        text=generated[name];ptx.write_text(text,encoding='utf-8',newline='\n')
        command=[str(compiler),'-arch=sm_89','-O3','-v',str(ptx),'-o',str(cubin)]
        result=subprocess.run(command,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=300)
        (output/Path(name).with_suffix('.compiler.log')).write_text(result.stdout+result.stderr,encoding='utf-8')
        if result.returncode:raise RuntimeError('Compiler failed for '+name+'; see its compiler.log')
        print('Built '+name,flush=True)
        return dict(filename=name,entry=r['entry'],sha256=hashlib.sha256(cubin.read_bytes()).hexdigest(),
            sourceEntrySha256=hashlib.sha256(entries[r['entry']].encode()).hexdigest(),
            generatedPtxSha256=hashlib.sha256(ptx.read_bytes()).hexdigest())
    try:
        with ThreadPoolExecutor(max_workers=jobs) as pool:
            receipt['kernels']=list(pool.map(compile_one,recipes))
        receipt['status']='compiled'
    except Exception as error:
        receipt.update(status='failed',error=str(error));raise
    finally:
        (output/'build.json').write_text(json.dumps(receipt,indent=2)+'\n',encoding='utf-8')
    return receipt


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--ptx-dir',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True)
    p.add_argument('--ptxas',default=shutil.which('ptxas') or str(Path(os.environ.get('CUDA_PATH',''))/'bin/ptxas.exe'))
    p.add_argument('--only',action='append',default=[],help='Optional output filename, e.g. integrated-12.cubin; repeatable')
    p.add_argument('--jobs',type=int,default=4)
    a=p.parse_args()
    print('Compiled',len(build(a.ptx_dir,a.output,a.ptxas,a.only,a.jobs)['kernels']),'kernel images.')
