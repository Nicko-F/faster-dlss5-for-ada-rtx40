"""Generate addon tables from public ABI facts and a user-supplied local kernel bundle."""
import argparse
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def validate(d):
    def uint(value, maximum=2**32-1):
        return type(value) is int and 0 <= value <= maximum
    if d['schemaVersion'] != 1 or len(d['images']) != 45 or len(d['routes']) != 145 or len(d['sequence']) != 156:
        raise ValueError('Unexpected network contract inventory')
    for i, image in enumerate(d['images']):
        if image['index'] != i or image['filename'] != f'integrated-{i:02}.cubin':
            raise ValueError('Invalid kernel filename or index')
    if [s['filename'] for s in d['surfaces']] != ['frontback-pre.cubin','frontback-post.cubin']:
        raise ValueError('Invalid surface inventory')
    for name in d['sequence'] + [e['name'] for e in d['images'] + d['surfaces']]:
        if not re.fullmatch(r'[A-Za-z_$][\w$]*', name, re.ASCII):
            raise ValueError('Invalid entry name')
    slots = set()
    for r in d['routes']:
        if (not uint(r['shared'], 102400) or not uint(r['gridMultiplier']) or r['gridMultiplier'] == 0
                or len(r['gridBias']) != 2 or any(not uint(v) for v in r['gridBias'])
                or type(r['oldImage']) is not int or not -1 <= r['oldImage'] < 45):
            raise ValueError('Invalid dispatch numeric field')
        if r['slot'] in slots or not 0 <= r['slot'] < 156 or d['sequence'][r['slot']] != r['name']:
            raise ValueError('Invalid dispatch slot')
        slots.add(r['slot'])
        if not 0 < r['bytes'] <= 96 or len(r['literal']) != r['bytes'] or any(not 0 <= v <= 255 for v in r['literal']):
            raise ValueError('Invalid parameter storage')
        if not 0 <= r['newImage'] < 45 or d['images'][r['newImage']]['name'] != r['name']:
            raise ValueError('Kernel and route disagree')
        if any(len(r[k]) != 3 or any(not 0 < v <= 2**31-1 for v in r[k]) for k in ('block','grid')):
            raise ValueError('Invalid launch dimensions')
        if min(r['pointerMask'],r['unusedMask']) < 0 or (r['pointerMask'] | r['unusedMask']) >> ((r['bytes']+7)//8):
            raise ValueError('Invalid parameter masks')
        mask = r['pointerMask'] | r['unusedMask']
        if any(value and (mask >> (i//8)) & 1 for i,value in enumerate(r['literal'])):
            raise ValueError('Excluded parameters must be zero')
        if not 1 <= len(r['dimensions']) <= 4 or not 0 <= r['level'] < 7 or r['gridKind'] not in (0,1,2):
            raise ValueError('Invalid dimension rule')
        for f in r['dimensions']:
            if f['offset'] % 4 or not 0 <= f['offset'] <= r['bytes']-4 or not 0 <= f['level'] < 7 or f['axis'] not in (0,1):
                raise ValueError('Invalid dimension field')
            if mask >> (f['offset']//8) & 1:
                raise ValueError('Dimension overlaps an excluded parameter')
    for s in d['specializations']:
        if any(not uint(s[k], 100000) or s[k] == 0 for k in ('foldedHeight','foldedWidth')):
            raise ValueError('Invalid folded dimension')
        if s['slot'] not in slots or not 0 <= s['image'] < 45 or d['images'][s['image']]['name'] != d['sequence'][s['slot']]:
            raise ValueError('Invalid specialization')
        if not re.fullmatch(r'[1-9]\d{0,4}x[1-9]\d{0,4}', s['resolution']):
            raise ValueError('Invalid specialization shape')


def render(d):
    arr = lambda v: '{'+','.join(map(str,v))+'}'
    lines = ['// Generated from scalar ABI metadata and local bundle identities.','#pragma once','namespace integrated {',
             'struct Image {const char *name,*filename,*sha;};','inline const Image images[]{']
    lines += ['{'+','.join(json.dumps(e[k]) for k in ('name','filename','sha256'))+'},' for e in d['images']]
    lines += ['};','struct Dim {unsigned offset,level,axis;};',
        'struct Route {const char *name;unsigned slot,bytes,grid[3],block[3],shared,pointerMask,unusedMask;unsigned char literal[96];int oldImage,newImage;',
        'unsigned dimCount;Dim dims[4];unsigned level,gridKind,gridMultiplier;unsigned gridBias[2];};','inline const Route routes[]{']
    for r in d['routes']:
        fields = '{'+','.join(arr([f['offset'],f['level'],f['axis']]) for f in r['dimensions'])+'}'
        values = [json.dumps(r['name']),str(r['slot']),str(r['bytes']),arr(r['grid']),arr(r['block']),str(r['shared']),
            str(r['pointerMask']),str(r['unusedMask']),arr(r['literal']),str(r['oldImage']),str(r['newImage']),
            str(len(r['dimensions'])),fields,str(r['level']),str(r['gridKind']),str(r['gridMultiplier']),arr(r['gridBias'])]
        lines.append('{'+','.join(values)+'},')
    lines += ['};','inline const char *sequence[]{'+','.join(map(json.dumps,d['sequence']))+'};',
        'struct Special {unsigned width,height,slot,image,foldedHeight,foldedWidth;};','inline constexpr Special specializations[]{']
    lines += ['{'+','.join([*s['resolution'].split('x'),str(s['slot']),str(s['image']),str(s['foldedHeight']),str(s['foldedWidth'])])+'},' for s in d['specializations']]
    return '\n'.join(lines+['};','}'])+'\n'


def generate(config, bundle, output):
    d = json.loads(config.read_text(encoding='utf-8-sig'))
    validate(d)
    identities = {}
    for e in d['images'] + d['surfaces']:
        data = (bundle/e['filename']).read_bytes()
        if not data.startswith(b'\x7fELF'):
            raise ValueError('Expected a local CUDA ELF image: '+e['filename'])
        e['sha256'] = hashlib.sha256(data).hexdigest()
        identities[e['filename']] = e['sha256']
    output.mkdir(parents=True, exist_ok=True)
    (output/'dynamic_selection.generated.h').write_text(render(d),encoding='utf-8')
    surfaces = ',\n'.join('{'+','.join(json.dumps(s[k]) for k in ('name','filename','sha256'))+'}' for s in d['surfaces'])
    profile = ('#pragma once\nnamespace nr_compat {\nstruct Surface {const char *name,*filename,*sha;};\n'
        'struct Profile {const char *id;Surface surfaces[2];};\ninline constexpr Profile profile{'+json.dumps(d['profileId'])+', {\n'+surfaces+'\n}};\n}\n')
    (output/'profile.generated.h').write_text(profile,encoding='utf-8')
    (output/'bundle-identities.json').write_text(json.dumps(identities,indent=2)+'\n',encoding='utf-8')
    return identities


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--config',type=Path,default=ROOT/'config/network.json')
    p.add_argument('--bundle',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True)
    a = p.parse_args()
    print('Generated dispatch for',len(generate(a.config,a.bundle,a.output)),'local kernel images.')
