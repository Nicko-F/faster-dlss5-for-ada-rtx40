"""Transfer the proven 256 N64 rewrite only across alpha-equivalent FFN loops."""
import hashlib
import re
from ptx_module import syntax
from ptx_qkv512 import MMA, compact
from ptx_ffn256_n64 import structure, pair_ffn_n64, REG, LABEL, BACKEDGE

TOKEN = re.compile(r'%[a-z]+\d+\b|_ZZ\w+|\$L__BB\w+')


def canonical(text):
    names = {}
    counts = {}
    def replace(match):
        token = match[0]
        kind = re.match(r'%[a-z]+', token)[0] if token.startswith('%') else ('shared' if token.startswith('_ZZ') else 'label')
        if token not in names:
            names[token] = kind + str(counts.get(kind, 0))
            counts[kind] = counts.get(kind, 0) + 1
        return names[token]
    return compact(TOKEN.sub(replace, syntax(text))), names


def pair(entry, reference):
    code = syntax(entry)
    if '%n64_' in code:
        raise ValueError('Already paired')
    _, rs, re_, reference_mma, _ = structure(reference)
    reference_loop = reference[rs:re_]
    expected, reference_names = canonical(reference_loop)
    matches = []
    for branch in re.finditer(r'@%p\d+ bra (\$L__BB\w+);', code):
        start = code.rfind(branch[1] + ':', 0, branch.start())
        if start < 0:
            continue
        loop = entry[start:branch.end()]
        normalized, names = canonical(loop)
        if normalized == expected:
            matches.append((start, branch.end(), loop, names))
    if len(matches) != 1:
        raise ValueError('Expected one alpha-equivalent 256 FFN loop')
    start, end, loop, names = matches[0]
    inverse = {v: k for k, v in names.items()}
    mapping = {k: inverse[v] for k, v in reference_names.items()}
    matrices = list(MMA.finditer(syntax(loop)))
    liveouts = set(REG.findall(loop[:matrices[127].end()])) & set(REG.findall(code[end:]))
    if liveouts != {mapping['%r3097']}:
        raise ValueError('Expansion live-out contract changed')
    paired = pair_ffn_n64(reference)
    a = paired.index(LABEL)
    b = paired.index(BACKEDGE, a) + len(BACKEDGE)
    replacement = TOKEN.sub(lambda m: mapping.get(m[0], m[0]), paired[a:b])
    result = entry[:start] + replacement + entry[end:]
    declarations = '\n'.join(re.findall(r'\.reg \.b\d+ %n64_\w+;', paired))
    opening = syntax(result).index('{') + 1
    result = result[:opening] + '\n' + declarations + '\n' + result[opening:]
    return result, dict(loopSha256=hashlib.sha256(compact(loop).encode()).hexdigest(),
                        canonicalSha256=hashlib.sha256(expected.encode()).hexdigest(),
                        originalExpansionSlices=4, pairedExpansionSlices=2,
                        sharedExpansionLoadsBefore=128, sharedExpansionLoadsAfter=64,
                        expansionMmaPerIterationBefore=128, expansionMmaPerIterationAfter=256)
