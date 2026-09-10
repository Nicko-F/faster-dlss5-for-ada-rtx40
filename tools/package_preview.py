"""Build an audited source-preview archive from an explicit allowlist."""
import hashlib
import json
import re
import zipfile
from pathlib import Path, PurePosixPath

ROOT = Path(__file__).resolve().parents[1]
DENIED = {'.ptx', '.sass', '.cubin', '.fatbin', '.dll', '.exe', '.lib', '.addon64',
          '.bin', '.zip', '.7z', '.pdb', '.obj', '.csv'}
PRIVATE = re.compile(r'C:[/\\]+Users[/\\]+|E:[/\\]+SteamLibrary[/\\]+|gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}', re.I)


def audit(root=ROOT):
    names = json.loads((root/'public-files.json').read_text(encoding='utf-8'))['files']
    if len(names) != len(set(names)):
        raise ValueError('Duplicate allowlist entry')
    payload = {}
    for name in names:
        path = PurePosixPath(name)
        if (path.is_absolute() or '..' in path.parts or '\\' in name or ':' in name or
            path.suffix.lower() in DENIED or any(p in {'.git','.cache','profiles','references','experiments'} for p in path.parts) or
            name.endswith('.generated.h')):
            raise ValueError('Disallowed public path: '+name)
        source = root.joinpath(*path.parts)
        if source.is_symlink() or not source.resolve().is_relative_to(root.resolve()):
            raise ValueError('Linked file outside source tree: '+name)
        data = source.read_bytes()
        if data.startswith((b'MZ',b'\x7fELF')):
            raise ValueError('Executable payload: '+name)
        text = data.decode('utf-8-sig')
        if PRIVATE.search(text):
            raise ValueError('Private path or credential pattern: '+name)
        payload[name] = data
    return payload


def main():
    payload = audit()
    target = ROOT/'dist/Faster-DLSS5-Ada-SOURCE-PREVIEW-2026-09-10.zip'
    target.parent.mkdir(exist_ok=True)
    hashes = {k: hashlib.sha256(v).hexdigest() for k,v in payload.items()}
    payload['SOURCE-MANIFEST.json'] = (json.dumps(dict(schemaVersion=1,
        status='source-preview-no-acceleration-payload', files=hashes),indent=2)+'\n').encode()
    with zipfile.ZipFile(target,'w',zipfile.ZIP_DEFLATED) as z:
        for name,data in sorted(payload.items()):
            info=zipfile.ZipInfo(name,(2026,9,10,0,0,0))
            info.compress_type=zipfile.ZIP_DEFLATED
            z.writestr(info,data)
    with zipfile.ZipFile(target) as z:
        if z.testzip() or set(z.namelist()) != set(payload):
            raise ValueError('Archive integrity failed')
        for name,data in payload.items():
            if z.read(name) != data:
                raise ValueError('Archive bytes differ: '+name)
    digest = hashlib.sha256(target.read_bytes()).hexdigest()
    target.with_suffix('.zip.sha256').write_text(f'{digest}  {target.name}\n',encoding='ascii')
    print(json.dumps(dict(file=target.name,bytes=target.stat().st_size,sha256=digest,files=len(payload))))


if __name__ == '__main__':
    main()
