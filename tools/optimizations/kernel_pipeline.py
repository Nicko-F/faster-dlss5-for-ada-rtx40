"""Apply the selected Ada recipes to locally supplied PTX entries."""
import re
from ptx_module import entry_spans, syntax
from ptx_ada_semantic import lower
from ptx_qkv512 import defer_loop_input_pairs
from ptx_projection_pairs import defer_projection_pairs
from ptx_defer_shared import defer
from ptx_ffn256_n64 import pair_ffn_n64
from ptx_boundary_n64 import pair
from ptx_shape_specialize import specialize

REFERENCE='cc_tinlayout_fused_swin_8h_256_8_chained_fp8'


def source_entries(directory):
    entries={}
    for path in sorted(directory.rglob('*.ptx')):
        text=path.read_text(encoding='utf-8-sig').replace('\r','')
        if not re.search(r'(?m)^\s*\.address_size\s+64\s*$',syntax(text)):
            raise ValueError('Expected 64-bit PTX: '+path.name)
        for name,(a,b) in entry_spans(text).items():
            entry=text[a:b]
            if name in entries and entries[name]!=entry:
                raise ValueError('Different definitions of '+name+'; select a single source PTX directory')
            entries[name]=entry
    if not entries:raise ValueError('No PTX entries found in the local input directory')
    return entries


def apply_recipe(entries, recipe):
    text=entries[recipe['entry']]
    masked=syntax(text)
    parameter=re.search(r'\.param\s+\.align\s+8\s+\.b8\s+\w+\[(\d+)\]',masked)
    if not parameter or int(parameter[1])!=recipe['parameterBytes']:
        raise ValueError('Entry parameter ABI changed: '+recipe['entry'])
    if re.search(r'\.(?:reqntid|maxntid)\b',masked):
        raise ValueError('Source already contains a compilation block bound')
    if recipe.get('specialization'):
        s=recipe['specialization'];literal=bytearray(s['parameterBytes'])
        for f in s['foldedLoads']:
            data=bytes.fromhex(f['valueHex'])
            if len(data)!=f['bytes'] or f['offset']<0 or f['offset']+len(data)>len(literal):
                raise ValueError('Invalid scalar fold')
            literal[f['offset']:f['offset']+len(data)]=data
        width,height=map(int,s['resolution'].split('x'))
        spec=dict(bytes=len(literal),literal=list(literal),pointerMask=s['pointerMask'],unusedMask=s['unusedMask'],slot=s['slot'],width=width,height=height)
        text,proof=specialize(text,spec,s['dynamicOffsets'])
        if proof['foldedLoads']!=s['foldedLoads']:raise ValueError('Scalar load layout changed')
    pairing=recipe['pairing']
    if pairing=='qkv':text=defer_loop_input_pairs(text)
    elif pairing in ('InpProj512','OutProj512'):text=defer_projection_pairs(text,pairing)
    elif pairing=='ffn256':text=pair_ffn_n64(text)
    elif pairing=='boundary256':text,_=pair(text,entries[REFERENCE])
    elif pairing is not None:raise ValueError('Unknown pairing recipe')
    if recipe['lowering']=='async':
        text=lower(text,'async',recipe['copies'],recipe['reductions'])
    elif recipe['lowering']=='retarget':
        text='.version 9.3\n.target sm_89\n.address_size 64\n\n'+text+'\n'
    else:raise ValueError('Unknown lowering')
    if recipe['deferredSharedLoads']:
        text,count=defer(text)
        if count!=recipe['deferredSharedLoads']:raise ValueError('Shared-load dependency structure changed')
    if not 1<=recipe['registers']<=255:raise ValueError('Invalid register budget')
    text,count=re.subn(r'\.maxnreg\s+\d+',f'.maxnreg {recipe["registers"]}',text)
    if count!=1:raise ValueError('Expected one register budget directive')
    if recipe['bound']:
        block=recipe['block']
        if recipe['bound'] not in ('reqntid','maxntid') or len(block)!=3 or any(x<1 for x in block) or block[0]*block[1]*block[2]>1024:
            raise ValueError('Invalid block bound')
        pos=syntax(text).index('{')
        text=text[:pos]+'.'+recipe['bound']+' '+', '.join(map(str,block))+'\n'+text[pos:]
    if recipe['sharedSpilling']:
        if not recipe['bound'] or re.search(r'\.extern\s+\.shared|\bcall(?:\.uni)?\b|\bsetmaxnreg\b',syntax(text)):
            raise ValueError('Unsupported shared-spilling compilation input')
        pos=syntax(text).index('{')+1
        text=text[:pos]+'\n.pragma "enable_smem_spilling";\n'+text[pos:]
    if recipe['mmaThroughput']:
        pos=syntax(text).index('ld.param')
        text=text[:pos]+'.pragma "mma_throughput";\n'+text[pos:]
    return text
