"""Recompute the published timing tables from exported per-run measurements."""
import json
from pathlib import Path
from statistics import mean

ROOT = Path(__file__).resolve().parents[1]


def calculate(data):
    nr = []
    groups = sorted({(r['resolution'], r['method']) for r in data['nr']})
    for resolution, method in groups:
        rows = [r for r in data['nr'] if (r['resolution'], r['method']) == (resolution, method)]
        a, b = (mean(r[k] for r in rows) for k in ('communityMs', 'optimizedMs'))
        nr.append((resolution, method, a, b, 100 * (1 - b / a)))
    games = []
    for row in data['gameRuns']:
        fps = {k: mean(v) for k, v in row['fps'].items()}
        ms = {k: mean(1000 / f for f in v) for k, v in row['fps'].items()}
        community = ms['community'] - ms['original']
        optimized = ms['optimized'] - ms['original']
        reference = data['externalReference']['renderTimeMs'][row['resolution']]
        games.append(dict(resolution=row['resolution'], **fps,
            fpsGainPercent=100 * (fps['optimized'] / fps['community'] - 1),
            communityAddedMs=community, optimizedAddedMs=optimized,
            savedMs=community-optimized, costReductionPercent=100*(1-optimized/community),
            referenceMs=reference, belowReferencePercent=100*(1-optimized/reference) if reference else None))
    return nr, games


def main():
    data = json.loads((ROOT / 'benchmarks/results-2026-09-10.json').read_text(encoding='utf-8'))
    nr, games = calculate(data)
    print('| Resolution | NR method | Community ms | Optimized ms | Reduction |')
    print('|---|---|---:|---:|---:|')
    for res, method, a, b, reduction in nr:
        print(f'| {res} | {method} | {a:.4f} | {b:.4f} | {reduction:.2f}% |')
    print('\n| Resolution | Original FPS | Community FPS | Optimized FPS | FPS gain |')
    print('|---|---:|---:|---:|---:|')
    for r in games:
        print(f"| {r['resolution']} | {r['original']:.2f} | {r['community']:.2f} | {r['optimized']:.2f} | {r['fpsGainPercent']:.2f}% |")
    print('\n| Resolution | Community added ms | Optimized added ms | Saved ms | Cost reduction | External 5070 Ti ms |')
    print('|---|---:|---:|---:|---:|---:|')
    for r in games:
        ref = '—' if r['referenceMs'] is None else f"{r['referenceMs']:.1f}"
        print(f"| {r['resolution']} | {r['communityAddedMs']:.3f} | {r['optimizedAddedMs']:.3f} | {r['savedMs']:.3f} | {r['costReductionPercent']:.2f}% | {ref} |")
    print('\nExternal reference: different game/integration. Not a controlled cross-GPU comparison.')


if __name__ == '__main__':
    main()
