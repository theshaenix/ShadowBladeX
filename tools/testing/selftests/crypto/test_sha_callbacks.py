#!/usr/bin/env python3
"""Check ARM64 SHA assembly callback types against the shared hash API."""
import pathlib
import re
import subprocess

root = pathlib.Path(__file__).resolve().parents[4]
for filename, bits, names in (
    ('sha512-glue.c', 512, ('sha512_block_data_order',)),
    ('sha256-glue.c', 256, ('sha256_block_data_order', 'sha256_block_neon')),
    ('sha2-ce-glue.c', 256, ('sha256_block_data_order',)),
):
    source = (root / 'arch/arm64/crypto' / filename).read_text()
    base = (root / f'include/crypto/sha{bits}_base.h').read_text()
    callback = re.search(rf'typedef void \(sha{bits}_block_fn\)\([^;]+;', base).group()
    code = ('#define asmlinkage\ntypedef unsigned int u32; typedef unsigned char u8;\n'
            f'struct sha{bits}_state;\n' + callback + '\n')
    for name in names:
        code += re.search(rf'asmlinkage void {name}\([^;]+;', source).group() + '\n'
        code += (f'_Static_assert(__builtin_types_compatible_p(__typeof__({name}), '
                 f'sha{bits}_block_fn), "{filename}: {name} callback mismatch");\n')
    subprocess.run(['cc', '-x', 'c', '-std=c11', '-fsyntax-only', '-'],
                   input=code, text=True, check=True)
print('PASS: SHA-256/SHA-512 callback declarations match the hash API')
