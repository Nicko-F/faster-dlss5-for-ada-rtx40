"""Build-contract and transformation tests using synthetic inputs only."""
import copy
import hashlib
import json
from pathlib import Path
import struct
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path[:0] = [str(ROOT/'tools'), str(ROOT/'tools/optimizations')]
from extract_local_ptx import containers
from generate_dispatch import generate, validate
from package_accelerator import assemble
from ptx_ada_semantic import lower
from ptx_defer_shared import defer


class BuildTests(unittest.TestCase):
    def setUp(self):
        self.contract = json.loads((ROOT/'config/network.json').read_text())

    def test_contract_rejects_changed_abi_and_paths(self):
        validate(self.contract)
        changes = [lambda d: d['images'][0].update(filename='../escape.cubin'),
                   lambda d: d['routes'][0].update(gridMultiplier='1; injected'),
                   lambda d: d['routes'][0]['dimensions'][0].update(offset=96),
                   lambda d: d['routes'][0].update(pointerMask=1 << 30)]
        for change in changes:
            with self.subTest(change=change):
                invalid = copy.deepcopy(self.contract)
                change(invalid)
                with self.assertRaises(ValueError):
                    validate(invalid)

    def test_container_scan_skips_truncated_and_invalid_headers(self):
        valid = struct.pack('<IHHQ', 0xBA55ED50, 1, 16, 5) + b'local'
        invalid = struct.pack('<IHHQ', 0xBA55ED50, 2, 16, 5) + b'other'
        raw = b'prefix' + invalid + valid + valid[:12]
        self.assertEqual(list(containers(raw)), [(6 + len(invalid), valid)])

    def test_async_lowering_preserves_mma_and_links_completion(self):
        mma = 'mma.sync.test {%r90}, {%r91}, {%r92}, {%r90};'
        entry = '''mov.b32 %r1, 512;
mov.b32 %r7, 1;
{ .reg .pred P_OUT; elect.sync _|P_OUT, %r2; selp.b32 %r3, 1, 0, P_OUT; }
cp.async.bulk.shared::cta.global.mbarrier::complete_tx::bytes [%r4], [%rd1], %r1, [%r5];
mbarrier.expect_tx.relaxed.cta.shared::cta.b64 [%r5], %r1;
mbarrier.try_wait.shared::cta.b64 %p1, [%r5], %rd3;
mbarrier.try_wait.shared::cta.b64 %p2, [%r5], %rd4;
mbarrier.arrive.shared::cta.b64 %rd3, [%r5], %r7;
mbarrier.arrive.shared::cta.b64 %rd4, [%r5], %r7;
''' + mma
        result = lower(entry, 'async', 1, 0)
        self.assertIn('cp.async.cg.shared.global', result)
        self.assertIn('cp.async.mbarrier.arrive.shared.b64 [%r5]', result)
        self.assertNotIn('cp.async.wait_group', result)
        self.assertIn(mma, result)
        with self.assertRaises(ValueError):
            lower(entry.replace('512;', '256;'), 'async', 1, 0)

    def test_shared_load_moves_only_across_independent_work(self):
        load = 'ld.shared::cta.v4.u32 {%r1,%r2,%r3,%r4}, [%r10];'
        mma = 'mma.sync.aligned.m16n8k32.row.col.f16.e4m3.e4m3.f16 {%r20,%r21}, {%r1,%r2,%r3,%r4}, {%r22,%r23}, {%r20,%r21};'
        independent = 'mov.u32 %r30, 7;'
        result, count = defer(load + '\n' + independent + '\n' + mma)
        self.assertEqual(count, 1)
        self.assertLess(result.index(independent), result.index(load))
        for blocker in ('bar.sync 0;', 'mov.u32 %r10, 0;', 'st.shared.u32 [%r40], %r41;'):
            with self.subTest(blocker=blocker), self.assertRaises(ValueError):
                defer(load + '\n' + blocker + '\n' + mma)

    def test_packaging_binds_addon_contract_and_local_images(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            addon_dir = root/'addon'; addon_dir.mkdir()
            bundle = root/'kernels'; bundle.mkdir()
            addon = addon_dir/'ada-nr.addon64'; addon.write_bytes(b'MZsynthetic-test')
            for e in self.contract['images'] + self.contract['surfaces']:
                (bundle/e['filename']).write_bytes(b'\x7fELFsynthetic-' + e['filename'].encode())
            generate(ROOT/'config/network.json', bundle, addon_dir/'generated')
            identity = addon_dir/'generated/bundle-identities.json'
            digest = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
            receipt = dict(addonSha256=digest(addon), contractSha256=digest(ROOT/'config/network.json'),
                           bundleIdentitiesSha256=digest(identity), tailJumpVerified=True, routeTestsPassed=True)
            (addon_dir/'build.json').write_text(json.dumps(receipt))
            with patch('package_accelerator.audit', return_value={'README.md': b'test'}):
                output = root/'package.zip'
                assemble(addon, bundle, output)
                with zipfile.ZipFile(output) as z:
                    manifest = json.loads(z.read('profiles/automatic/manifest.json'))
                    self.assertEqual(len(manifest['files']), 49)
                image = bundle/self.contract['images'][0]['filename']
                image.write_bytes(b'\x7fELFchanged')
                with self.assertRaisesRegex(ValueError, 'Bundle changed'):
                    assemble(addon, bundle, root/'changed.zip')
                generate(ROOT/'config/network.json', bundle, addon_dir/'generated')
                with self.assertRaisesRegex(ValueError, 'identities changed'):
                    assemble(addon, bundle, root/'stale.zip')


if __name__ == '__main__':
    unittest.main()
