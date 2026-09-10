"""One locked QKV loop transformation; no math, copy, barrier or launch changes."""
import re

from ptx_module import syntax

FRAGMENTS = (339, 343, 371, 375, 403, 407, 435, 439)
MMA = re.compile(r'mma\.sync\.aligned\.m16n8k32\.row\.col\.f16\.e4m3\.e4m3\.f16\s*'
                 r'\{([^{}]+)\},\s*\{([^{}]+)\},\s*\{([^{}]+)\},\s*\{([^{}]+)\};')


def compact(text):
    return re.sub(r'\s+', '', text)


def valid_load_block(block, index):
    """Validate opcodes and operand dependencies of the local input load block."""
    lane, address, fragment = 323 + 2 * index, 324 + 2 * index, FRAGMENTS[index]
    shift = 487 if index == 0 else 486 + 2 * index
    expected = [('mov.u32', f'%r{lane},%laneid'),
                ('shl.b32', f'%r{shift},%r{lane},4')]
    if index == 0:
        expected.append(('add.s32', f'%r{address},%r486,%r{shift}'))
    else:
        expected.extend([('add.s32', f'%r{shift+1},%r486,%r{shift}'),
                         ('add.s32', f'%r{address},%r{shift+1},{index*512}')])
    operands = '{' + ','.join(f'%r{x}' for x in range(fragment, fragment+4)) + f'}},[%r{address}]'
    expected.append(('ld.shared::cta.v4.u32', operands))
    actual = []
    for instruction in block.strip().split(';'):
        if not instruction.strip():
            continue
        fields = instruction.strip().split(None, 1)
        if len(fields) != 2:
            return False
        actual.append((fields[0], compact(fields[1])))
    return actual == expected


def defer_loop_input_pairs(entry):
    """Keep two A fragments ahead of each 24-MMA group in the repeated loop only."""
    masked = syntax(entry)
    starts = []
    for lane in range(323, 338, 2):
        matches = list(re.finditer(rf'(?m)^mov\.u32 %r{lane}, %laneid;', masked))
        if len(matches) != 1:
            raise ValueError('QKV loop load anchor changed')
        starts.append(matches[0].start())
    if starts != sorted(starts):
        raise ValueError('QKV loop is already reordered or has changed')
    matrices = list(MMA.finditer(masked, starts[0]))[:96]
    if len(matrices) != 96 or re.sub(MMA, '', masked[matrices[0].start():matrices[-1].end()]).strip():
        raise ValueError('Expected 96 contiguous loop MMA instructions without side effects')
    ends = starts[1:] + [matrices[0].start()]
    blocks = [entry[a:b] for a, b in zip(starts, ends)]
    if any(not valid_load_block(masked[a:b], i) for i, (a, b) in enumerate(zip(starts, ends))):
        raise ValueError('QKV load/address contract changed')
    fragment_regs = {f'%r{x}' for first in FRAGMENTS for x in range(first, first+4)}
    address_regs = {f'%r{x}' for x in (*range(323,339), *range(486,502))}
    for i, matrix in enumerate(matrices):
        expected = FRAGMENTS[2*(i//24) + (i % 4 >= 2)]
        if compact(matrix[2]) != ','.join(f'%r{x}' for x in range(expected, expected+4)):
            raise ValueError('QKV A-fragment consumer sequence changed')
        other = set(re.findall(r'%r\d+\b', ','.join(matrix[x] for x in (1,3,4))))
        if other & (fragment_regs | address_regs):
            raise ValueError('QKV MMA modifies or aliases moved load state')
    pieces = []
    for pair in range(4):
        pieces.extend(blocks[2*pair:2*pair+2])
        pieces.append(entry[matrices[24*pair].start():matrices[24*pair+23].end()] + '\n\n')
    return entry[:starts[0]] + ''.join(pieces) + entry[matrices[-1].end():]
