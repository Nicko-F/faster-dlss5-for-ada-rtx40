"""Read CUDA containers from a local runtime and let cuobjdump extract their PTX."""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import subprocess


def containers(raw):
    cursor=0
    while True:
        offset=raw.find(b'\x50\xed\x55\xba',cursor)
        if offset<0:return
        cursor=offset+4
        if offset+16>len(raw):continue
        magic,version,header,size=struct.unpack_from('<IHHQ',raw,offset)
        end=offset+header+size
        if version!=1 or header!=16 or not size or end>len(raw):continue
        yield offset,raw[offset:end]
        cursor=end


def extract(runtime,output,cuobjdump):
    raw=runtime.read_bytes()
    parts=list(containers(raw))
    if not parts:raise ValueError('No supported CUDA containers found in the local runtime')
    output=output.resolve();output.mkdir(parents=True,exist_ok=False)
    records=[]
    for i,(offset,data) in enumerate(parts):
        folder=output/f'module-{i:02d}';folder.mkdir()
        fatbin=folder/'module.fatbin';fatbin.write_bytes(data)
        result=subprocess.run([str(cuobjdump.resolve(strict=True)),'--extract-ptx','all',str(fatbin)],cwd=folder,
            capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=120)
        (folder/'extract.log').write_text(result.stdout+result.stderr,encoding='utf-8')
        if result.returncode:raise RuntimeError(f'cuobjdump failed for module {i}; see extract.log')
        records.append(dict(offset=offset,ptxFiles=len(list(folder.glob('*.ptx')))))
    if not any(r['ptxFiles'] for r in records):raise ValueError('The selected runtime contains no extractable PTX')
    (output/'extraction.json').write_text(json.dumps(dict(runtimeSha256=hashlib.sha256(raw).hexdigest(),modules=records),indent=2)+'\n',encoding='utf-8')
    return sum(r['ptxFiles'] for r in records)


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--runtime',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True)
    p.add_argument('--cuobjdump',type=Path,required=True)
    a=p.parse_args();print('Extracted',extract(a.runtime,a.output,a.cuobjdump),'local PTX modules.')
