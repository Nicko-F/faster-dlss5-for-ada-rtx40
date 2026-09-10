"""Locked bulk-copy/arrival adaptation; preserve matrix and component-reduction order."""
import re
from ptx_module import syntax


def substitute(text, pattern, replacement, count):
    output, found = re.subn(pattern, replacement, text, flags=re.S)
    if found != count:
        raise ValueError(f'Expected {count} sites, found {found}: {pattern[:70]}')
    return output


def lower(entry, mode, expected_copies, expected_reductions):
    if mode not in ('wait', 'async'):
        raise ValueError('Unknown completion mode')
    original = entry
    election = (r'\{\s*\.reg \.pred P_OUT;\s*elect\.sync _\|P_OUT, %r\d+;\s*'
                r'selp\.b32 (%r\d+), 1, 0, P_OUT;\s*\}')
    entry = substitute(entry, election, lambda m: f'mov.b32 {m[1]}, 1;', expected_copies)
    bulk = (r'cp\.async\.bulk\.shared::cta\.global\.mbarrier::complete_tx::bytes '
            r'\[(%r\d+)\], \[(%rd\d+)\], (%r\d+), \[(%r\d+)\];\s*'
            r'mbarrier\.expect_tx\.relaxed\.cta\.shared::cta\.b64 \[\4\], \3;')
    def copy(match):
        destination, source, size_register, barrier = match.groups()
        sizes = re.findall(r'mov\.b32 '+re.escape(size_register)+r', (\d+);', original)
        if len(sizes) != 1 or int(sizes[0]) not in (512, 1024):
            raise ValueError('Ambiguous copy-size definition')
        code = ('{\n.reg .b32 copy_lane, copy_offset, copy_dst;\n.reg .b64 copy_src;\n'
                'mov.u32 copy_lane, %laneid;\nshl.b32 copy_offset, copy_lane, 4;\n'
                f'add.u32 copy_dst, {destination}, copy_offset;\n'
                'cvt.u64.u32 copy_src, copy_offset;\n'
                f'add.u64 copy_src, {source}, copy_src;\n'
                'cp.async.cg.shared.global [copy_dst], [copy_src], 16;\n')
        if sizes[0] == '1024':
            code += ('add.u32 copy_dst, copy_dst, 512;\nadd.u64 copy_src, copy_src, 512;\n'
                     'cp.async.cg.shared.global [copy_dst], [copy_src], 16;\n')
        code += ('cp.async.commit_group;\ncp.async.wait_group 0;\n' if mode == 'wait' else
                 f'cp.async.mbarrier.arrive.shared.b64 [{barrier}];\n')
        return code+'}'
    entry = substitute(entry, bulk, copy, expected_copies)
    entry = substitute(entry, r'mbarrier\.try_wait\.shared::cta\.b64',
                       'mbarrier.test_wait.shared::cta.b64', 2)
    arrival = r'mbarrier\.arrive\.shared::cta\.b64 (%rd\d+), \[(%r\d+)\], (%r\d+);'
    def arrive(match):
        state, barrier, count = match.groups()
        values = re.findall(r'mov\.b32 '+re.escape(count)+r', (\d+);', original)
        if values != ['1']:
            raise ValueError('Unproven single-arrival count')
        return f'mbarrier.arrive.shared::cta.b64 {state}, [{barrier}];'
    entry = substitute(entry, arrival, arrive, 2)
    reduction = r'red\.global\.v4\.f16x2\.add\.noftz\s+\[(%rd\d+)\],\s*\{([^{}]+)\};'
    def components(match):
        registers = [r.strip() for r in match[2].split(',')]
        if len(registers) != 4 or any(not re.fullmatch(r'%r\d+', r) for r in registers):
            raise ValueError('Unexpected vector reduction layout')
        return '{\n.reg .b64 red_addr;\n'+ '\n'.join(
            f'add.u64 red_addr, {match[1]}, {4*i};\nred.global.add.noftz.f16x2 [red_addr], {r};'
            for i, r in enumerate(registers))+'\n}'
    entry = substitute(entry, reduction, components, expected_reductions)
    # SM89 lacks release-only fence encoding. Acq_rel retains release ordering
    # at the same GPU scope; never drop the publication fence.
    fences = re.findall(r'\bfence[^;]*;', entry)
    if fences:
        if fences != ['fence.release.gpu;']:
            raise ValueError('Unreviewed fence adaptation')
        entry = entry.replace('fence.release.gpu;', 'fence.acq_rel.gpu;')
    if re.search(r'elect\.sync|cp\.async\.bulk|mbarrier\.(?:expect_tx|try_wait)|red\.global\.v4', syntax(entry)):
        raise ValueError('Unconverted architecture feature')
    matrices = lambda text: re.findall(r'mma\.[^;]+;', syntax(text))
    if matrices(entry) != matrices(original):
        raise ValueError('Matrix instruction order changed')
    return '.version 9.3\n.target sm_89\n.address_size 64\n\n'+entry+'\n'
