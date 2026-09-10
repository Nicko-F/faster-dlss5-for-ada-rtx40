"""Fold only captured non-pointer ABI literals under an explicit shape contract."""
import hashlib
import re
from ptx_module import syntax


def specialize(entry,spec,dynamic_offsets=()):
    code=syntax(entry)
    pname=re.search(r'\.param\s+\.align\s+8\s+\.b8\s+(\w+)\[(\d+)\]',code)
    if not pname or int(pname[2])!=spec['bytes']:raise ValueError('Specialization ABI mismatch')
    pattern=re.compile(r'ld\.param\.(?:(v[24])\.)?([bu])(16|32|64)\s+(\{[^}]+\}|%\w+),\s*\['+re.escape(pname[1])+r'(?:\+(\d+))?\];')
    edits=[];receipts=[];literal=bytes(spec['literal']);excluded=spec['pointerMask']|spec['unusedMask']
    for m in pattern.finditer(code):
        count=int(m[1][1]) if m[1] else 1;size=int(m[3])//8;offset=int(m[5] or 0)
        if offset+count*size>len(literal):raise ValueError('Parameter range')
        if any(offset<=dynamic<offset+count*size for dynamic in dynamic_offsets):continue
        if any(excluded & (1<<(b//8)) for b in range(offset,offset+count*size)):continue
        registers=re.findall(r'%\w+',m[4])
        if len(registers)!=count:raise ValueError('Load register arity')
        text=[]
        for i,register in enumerate(registers):
            bits=int.from_bytes(literal[offset+i*size:offset+(i+1)*size],'little')
            text.append(f'mov.b{size*8} {register}, 0x{bits:0{size*2}x};')
        edits.append((m.start(),m.end(),'\n'.join(text)))
        receipts.append(dict(offset=offset,bytes=count*size,valueHex=literal[offset:offset+count*size].hex()))
    if not edits:raise ValueError('No scalar shape loads to specialize')
    result=entry
    for start,end,text in reversed(edits):result=result[:start]+text+result[end:]
    return result,dict(slot=spec['slot'],resolution=f"{spec['width']}x{spec['height']}",parameterBytes=spec['bytes'],
        literalSha256=hashlib.sha256(literal).hexdigest(),pointerMask=spec['pointerMask'],unusedMask=spec['unusedMask'],foldedLoads=receipts)
