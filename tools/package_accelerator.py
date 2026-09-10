"""Assemble a local installable package from the addon and complete built bundle."""
import argparse
import hashlib
import json
from pathlib import Path
import zipfile
from package_preview import audit
from generate_dispatch import ROOT, validate


def assemble(addon,bundle,output):
    d=json.loads((ROOT/'config/network.json').read_text())
    validate(d)
    payload=audit()
    prefix='profiles/automatic/'
    files={'ada-nr.addon64':addon.read_bytes(),'bundle/mode.txt':b'2'}
    if not files['ada-nr.addon64'].startswith(b'MZ'):raise ValueError('Expected a compiled Windows addon')
    for e in d['images']+d['surfaces']:
        data=(bundle/e['filename']).read_bytes()
        if not data.startswith(b'\x7fELF'):raise ValueError('Expected a CUDA ELF image: '+e['filename'])
        files['bundle/'+e['filename']]=data
    # The build receipt binds the compiled adapter to these exact local images.
    identities=json.loads((addon.parent/'generated/bundle-identities.json').read_text())
    receipt=json.loads((addon.parent/'build.json').read_text(encoding='utf-8-sig'))
    if receipt.get('contractSha256')!=hashlib.sha256((ROOT/'config/network.json').read_bytes()).hexdigest():
        raise ValueError('Dispatch contract changed since compiling the addon')
    if receipt.get('bundleIdentitiesSha256')!=hashlib.sha256((addon.parent/'generated/bundle-identities.json').read_bytes()).hexdigest():
        raise ValueError('Bundle identities changed since compiling the addon')
    if not receipt['tailJumpVerified'] or not receipt['routeTestsPassed'] or receipt['addonSha256']!=hashlib.sha256(files['ada-nr.addon64']).hexdigest():
        raise ValueError('Addon build receipt does not match')
    for e in d['images']+d['surfaces']:
        if hashlib.sha256(files['bundle/'+e['filename']]).hexdigest()!=identities[e['filename']]:
            raise ValueError('Bundle changed since compiling the addon')
    manifest=dict(schemaVersion=2,profileId='native-dimension-v1',mode=2,
                  files={name:hashlib.sha256(data).hexdigest() for name,data in files.items()})
    payload.update({prefix+name:data for name,data in files.items()})
    payload[prefix+'manifest.json']=(json.dumps(manifest,indent=2)+'\n').encode()
    output.parent.mkdir(parents=True,exist_ok=True)
    with zipfile.ZipFile(output,'x',zipfile.ZIP_DEFLATED) as z:
        for name,data in sorted(payload.items()):z.writestr(name,data)
    with zipfile.ZipFile(output) as z:
        if z.testzip() or set(z.namelist())!=set(payload):raise ValueError('Package integrity failure')
    digest=hashlib.sha256(output.read_bytes()).hexdigest()
    output.with_suffix(output.suffix+'.sha256').write_text(f'{digest}  {output.name}\n',encoding='ascii')
    return digest


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--addon',type=Path,required=True);p.add_argument('--bundle',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True)
    a=p.parse_args();print('Local package SHA256:',assemble(a.addon,a.bundle,a.output))
