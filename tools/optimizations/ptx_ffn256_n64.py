"""Pair adjacent frozen FFN expansion slices; preserve each K and contract chain."""
import hashlib
import re
from ptx_module import syntax
from ptx_qkv512 import MMA, compact

LABEL = '$L__BB7_35:'
BACKEDGE = '@%p49 bra $L__BB7_35;'
LOOP_SHA = 'da02fdf2627b2dd96e5cbc52dbe7b6ed5f47b3867567cea53839d7274e124814'
REG = re.compile(r'%r(?:s|d)?\d+\b')


def structure(entry):
    code = syntax(entry)
    if '%n64_' in code or '%cut_' in code:
        raise ValueError('Already transformed/instrumented')
    start = code.index(LABEL)
    end = code.index(BACKEDGE, start)+len(BACKEDGE)
    if hashlib.sha256(compact(code[start:end]).encode()).hexdigest() != LOOP_SHA:
        raise ValueError('Frozen FFN loop changed')
    matrices = list(MMA.finditer(code))
    if len(matrices) != 288 or not start < matrices[0].start() < matrices[143].end() < end:
        raise ValueError('FFN matrix boundary changed')
    final = [r for m in matrices[112:128] for r in REG.findall(m[1])]
    if len(set(final)) != 32:
        raise ValueError('Expansion final register inventory changed')
    return code, start, end, matrices, final


def mark_control(entry):
    _, _, end, matrices, _ = structure(entry)
    result = entry[:end]+'\n// FFN_CONTRACT_RESULT\n'+entry[end:]
    offset = matrices[127].end()
    return result[:offset]+'\n// FFN_N32_RESULT_0\n'+result[offset:]


def pair_ffn_n64(entry, prefetch_next=False):
    code, start, end, matrices, final = structure(entry)
    external = {'%rd312': '%n64_next_base', '%rd5': '%rd5', '%r3097': '%r3097'}
    mapping = dict(external)
    pieces = [LABEL, '\nadd.s64 %n64_next_base, %rd312, 1024;\n']
    for stage in range(8):
        first, last = matrices[16*stage], matrices[16*stage+15]
        preparation_start = start+len(LABEL) if not stage else matrices[16*stage-1].end()
        preparation = entry[preparation_start:first.start()]
        # Shared A registers remain live through both adjacent N slices.
        a_regs = {r for m in matrices[16*stage:16*stage+16] for r in REG.findall(m[2])}
        mapping.update({r: r for r in a_regs})
        anchor = 'mov.u32 %r149, %laneid;' if not stage else f'mov.u32 %r{183+66*(stage-1)}, %laneid;'
        b_start = preparation.index(anchor)
        weights = preparation[b_start:]
        if 'ld.shared' in weights or len(re.findall(r'ld\.weak\.global\.ca\.v4', weights)) != 2:
            raise ValueError('Weight preparation no longer isolated')
        mma = entry[first.start():last.end()]
        for r in REG.findall(weights+mma):
            mapping.setdefault(r, r.replace('%', '%n64_'))
        clone = lambda text: REG.sub(lambda m: mapping[m[0]], text)
        # Optional adjacent B prefetch overlaps its latency with the first N32 MMA chain.
        # Each chain's operands and accumulation order remain unchanged.
        pieces += ([preparation, clone(weights), mma, '\n', clone(mma), '\n'] if prefetch_next else
                   [preparation, mma, '\n', clone(weights), clone(mma), '\n'])
    pieces += ['// FFN_N32_RESULT_0\n', '// FFN_N32_RESULT_1\n']
    epilogue = entry[matrices[127].end():matrices[143].end()]
    # Reuse dead epilogue temporaries but feed the second expansion results and
    # the next weight slice. Contract D/C registers are deliberately NOT renamed.
    second_inputs = {r: mapping[r] for r in final} | {'%rd312': '%n64_next_base'}
    second_epilogue = REG.sub(lambda m: second_inputs.get(m[0], m[0]), epilogue)
    pieces += [epilogue, '\n', second_epilogue, '\n',
               'add.s32 %r23, %r4161, 64;\n',
               'add.s64 %rd312, %rd312, 2048;\n',
               'setp.lt.u32 %p49, %r4161, 64;\n',
               'mov.b32 %r4161, %r23;\n', BACKEDGE, '\n// FFN_CONTRACT_RESULT\n']
    result = entry[:start]+''.join(pieces)+entry[end:]
    # Declare only the new virtual registers actually referenced by the clone.
    added = {v: 64 if k.startswith('%rd') else 32 for k, v in mapping.items() if v.startswith('%n64_')}
    declarations = ''.join(f'.reg .b{added[r]} {r};\n' for r in sorted(added))
    opening = syntax(result).index('{')+1
    return result[:opening]+'\n'+declarations+result[opening:]
