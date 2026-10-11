"""Fail before invoking export if compiled content is absent, changed or stale."""
import json, hashlib
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
def verify():
    package=ROOT/'game/data/content/packages/astraeon.aebpack'
    receipt=Path(str(package)+'.receipt.json')
    if not package.is_file() or not receipt.is_file():raise ValueError('Missing compiled content; run tools/content/build_builtin.gd')
    data=json.loads(receipt.read_text(encoding='utf-8-sig'))
    if hashlib.sha256(package.read_bytes()).hexdigest()!=data['pack_sha256']:raise ValueError('Compiled package checksum differs from build receipt')
    for name,digest in data['sources'].items():
        if name.startswith('res://'):
            source=(ROOT/name[6:]).resolve()
            if not source.is_relative_to(ROOT):raise ValueError('Invalid build receipt path: '+name)
        elif Path(name).is_absolute():
            source=Path(name)  # Explicit offline image dependency; never placed in the package.
        else:raise ValueError('Invalid build receipt path: '+name)
        if not source.is_file() or hashlib.sha256(source.read_bytes()).hexdigest()!=digest:raise ValueError('Stale content: '+name)
    return {'verified_package':str(package),'sources':len(data['sources'])}
if __name__=='__main__':print(json.dumps(verify()))
