#!/usr/bin/env python3
"""Verify the original and reproduce each patched binary without executing it."""
from pathlib import Path
import hashlib, json
base = Path(__file__).resolve().parent
spec = json.loads((base / 'patches.json').read_text())
original = (base / 'gnss-original').read_bytes()
assert hashlib.sha256(original).hexdigest() == spec['original_sha256'], 'original mismatch'
for name, variant in spec['variants'].items():
    data = bytearray(original)
    for edit in variant['edits']:
        offset = edit['offset']
        before, after = bytes.fromhex(edit['before']), bytes.fromhex(edit['after'])
        assert data[offset:offset+len(before)] == before
        data[offset:offset+len(before)] = after
    assert hashlib.sha256(data).hexdigest() == variant['sha256'], name
    (base / name).write_bytes(data)
    print(name + ': verified and rebuilt')
