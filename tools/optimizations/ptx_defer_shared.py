"""Delay proven immutable shared A loads to their first contiguous MMA consumer."""
import re
from ptx_module import syntax
from ptx_qkv512 import MMA

REG=re.compile(r'%r\d+\b')
LOAD=re.compile(r'(?m)^ld\.shared::cta\.v4\.u32\s*\{([^}]+)\},\s*\[(%r\d+)\];')
STOP=re.compile(r'\b(?:bra|ret|call|bar\.|mbarrier\.|fence\.|st\.|red\.|atom\.|cp\.)|\$L__\w+:')


def defer(text):
    code=syntax(text);matrices=list(MMA.finditer(code));edits=[];moved=0
    for load in LOAD.finditer(code):
        regs=set(REG.findall(load[1]));address=load[2]
        if len(regs)!=4: raise ValueError('Unexpected A fragment')
        consumer=next((m for m in matrices if m.start()>load.end() and regs & set(REG.findall(m[0]))),None)
        if consumer is None or set(REG.findall(consumer[2]))!=regs: continue
        gap=code[load.end():consumer.start()]
        # No intervening readers, control paths, writes or asynchronous copies.
        # The destination shared storage is immutable throughout this interval.
        if regs & set(REG.findall(gap)) or STOP.search(gap): continue
        if code[:load.start()].count('{')-code[:load.start()].count('}') != code[:consumer.start()].count('{')-code[:consumer.start()].count('}'): continue
        if address in set(REG.findall(gap)): continue
        if not gap.strip(): continue
        edits.append((load.start(),load.end(),''))
        edits.append((consumer.start(),consumer.start(),text[load.start():load.end()]+'\n'))
        moved+=1
    if not moved: raise ValueError('No proven deferred shared loads')
    for start,end,replacement in sorted(edits,reverse=True): text=text[:start]+replacement+text[end:]
    return text,moved
