"""Conservative PTX entry isolation; keep non-entry declarations and helper functions."""
import re


def syntax(text):
    return re.sub(r'//[^\n]*|/\*.*?\*/|"(?:\\.|[^"\\])*"',
                  lambda m: ''.join('\n' if c == '\n' else ' ' for c in m.group()), text, flags=re.S)


def entry_spans(text):
    masked = syntax(text)
    entries = list(re.finditer(r'(?:\.visible\s+)?\.entry\s+([A-Za-z_$][\w$]*)\s*\(', masked))
    spans = {}
    for i, match in enumerate(entries):
        name = match[1]
        if name in spans:
            raise ValueError('Duplicate PTX entry: ' + name)
        limit = entries[i+1].start() if i+1 < len(entries) else len(masked)
        body = masked.find('{', match.end(), limit)
        if body < 0:
            raise ValueError('Missing PTX entry body: ' + name)
        depth = 0
        for token in re.finditer(r'[{}]', masked[body:limit]):
            depth += 1 if token.group() == '{' else -1
            if depth == 0:
                spans[name] = (match.start(), body + token.end())
                break
        else:
            raise ValueError('Unterminated PTX entry: ' + name)
    return spans


def retarget(text, ptx_version='9.4', target='sm_89'):
    if ptx_version not in ('9.3', '9.4'):
        raise ValueError('Unsupported output PTX version')
    if target not in ('sm_89', 'sm_120'):
        raise ValueError('Unsupported compile-check target')
    for directive, expected, output in (('version', '9.4', ptx_version), ('target', 'sm_120', target),
                                        ('address_size', '64', '64')):
        matches = list(re.finditer(r'(?m)^\s*\.' + directive + r'\s+(\S+)[ \t]*$', syntax(text)))
        if len(matches) != 1 or matches[0][1] != expected:
            raise ValueError('Unexpected PTX directive: ' + directive)
        start, end = matches[0].span(1)
        text = text[:start] + output + text[end:]
    return text


def isolate(text, name, ptx_version='9.4', target='sm_89'):
    spans = entry_spans(text)
    if name not in spans:
        raise ValueError('Missing PTX entry: ' + name)
    pieces, position = [], 0
    for entry, (start, end) in spans.items():
        pieces.append(text[position:start])
        if entry == name:
            pieces.append(text[start:end])
        position = end
    pieces.append(text[position:])
    return retarget(''.join(pieces), ptx_version, target)
