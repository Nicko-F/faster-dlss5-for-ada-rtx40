"""Shorten two locked 512 projection input lifetimes without changing MMA order."""
import re
from ptx_module import syntax
from ptx_qkv512 import MMA, compact

LAYOUTS = {
    'InpProj512': (1849, 1964, 106, (1865,1869,1889,1893,1913,1917,1937,1941)),
    'OutProj512': (1184, 1299, 51, (1200,1204,1224,1228,1248,1252,1272,1276)),
}


def defer_projection_pairs(entry, target):
    lane0, base_reg, base, fragments = LAYOUTS[target]
    masked = syntax(entry)
    starts = []
    for lane in range(lane0, lane0+16, 2):
        hits = list(re.finditer(rf'(?m)^mov\.u32 %r{lane}, %laneid;', masked))
        if len(hits) != 1:
            raise ValueError('Projection load anchor changed')
        starts.append(hits[0].start())
    if starts != sorted(starts):
        raise ValueError('Projection loads are already reordered')
    matrices = list(MMA.finditer(masked, starts[0]))[:64]
    if len(matrices) != 64 or re.sub(MMA, '', masked[matrices[0].start():matrices[-1].end()]).strip():
        raise ValueError('Expected 64 contiguous projection MMA instructions')
    ends = starts[1:] + [matrices[0].start()]
    blocks = [entry[a:b] for a,b in zip(starts,ends)]
    for i,(a,b) in enumerate(zip(starts,ends)):
        lane, address, fragment = lane0+2*i, lane0+2*i+1, fragments[i]
        shift = base_reg+1 if i == 0 else base_reg+2*i
        expected = rf'mov\.u32 %r{lane}, %laneid;\s*'
        if i == 0:
            expected += (rf'mov\.b32 %r{base_reg}, [_A-Za-z0-9]+shared_input_storage;\s*'
                         rf'add\.s32 %r{base}, %r{base_reg}, %r{base_reg-1};\s*')
        expected += rf'shl\.b32 %r{shift}, %r{lane}, 4;\s*'
        if i == 0:
            expected += rf'add\.s32 %r{address}, %r{base}, %r{shift};\s*'
        else:
            expected += (rf'add\.s32 %r{shift+1}, %r{base}, %r{shift};\s*'
                         rf'add\.s32 %r{address}, %r{shift+1}, {i*512};\s*')
        expected += (r'ld\.shared::cta\.v4\.u32\s*\{\s*' +
                     r'\s*,\s*'.join(f'%r{x}' for x in range(fragment,fragment+4)) +
                     rf'\s*\}},\s*\[%r{address}\];\s*')
        if not re.fullmatch(expected, masked[a:b]):
            raise ValueError('Projection load/address contract changed')
    moved = {f'%r{x}' for start in fragments for x in range(start,start+4)}
    moved |= {f'%r{x}' for x in (*range(lane0,lane0+16), *range(base_reg,base_reg+16),base)}
    for i,m in enumerate(matrices):
        fragment = fragments[2*(i//16)+(i%4 >= 2)]
        if compact(m[2]) != ','.join(f'%r{x}' for x in range(fragment,fragment+4)):
            raise ValueError('Projection A-fragment consumer sequence changed')
        if set(re.findall(r'%r\d+\b', ','.join(m[x] for x in (1,3,4)))) & moved:
            raise ValueError('Projection MMA aliases moved load state')
    pieces = []
    for pair in range(4):
        pieces.extend(blocks[2*pair:2*pair+2])
        pieces.append(entry[matrices[16*pair].start():matrices[16*pair+15].end()]+'\n\n')
    result = entry[:starts[0]] + ''.join(pieces) + entry[matrices[-1].end():]
    if re.findall(r'mma\.[^;]+;', syntax(result)) != re.findall(r'mma\.[^;]+;', masked):
        raise ValueError('Projection matrix order changed')
    return result
