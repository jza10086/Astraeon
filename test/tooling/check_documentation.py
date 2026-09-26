"""Read-only local Markdown link/anchor check for maintained project documentation."""
from pathlib import Path
import re
import unicodedata
from urllib.parse import unquote

ROOT = Path(__file__).resolve().parents[2]


def prose(text: str) -> str:
    return re.sub(r"^\s*(```|~~~).*?^\s*\1\s*$", "", text, flags=re.M | re.S)


def anchors(text: str) -> set[str]:
    found, counts = set(), {}
    for heading in re.findall(r"^#{1,6}\s+(.+?)\s*#*\s*$", prose(text), re.M):
        heading = re.sub(r"\[([^]]+)\]\([^)]*\)", r"\1", heading).replace('`', '').lower()
        slug = ''.join(c for c in heading if c in '-_ ' or unicodedata.category(c)[0] in 'LN').replace(' ', '-')
        number = counts.get(slug, 0)
        counts[slug] = number + 1
        found.add(slug + (f'-{number}' if number else ''))
    found.update(re.findall(r'<a\s+(?:id|name)="([^"]+)"', text))
    return found


def main() -> int:
    files = {ROOT / name for name in ('AGENTS.md', 'README.md', 'total_development.md')}
    for base in ('docs', 'game', 'test', '.agents/skills', 'addons/godot_mcp_toolkit/CompanionSkills'):
        files.update((ROOT / base).rglob('*.md'))
    files.update([ROOT/'benchmarks/voxelgame/README.md', ROOT/'benchmarks/voxelgame/AGENTS.md'])
    errors, checked = [], 0
    for source in sorted(files):
        text = prose(source.read_text(encoding='utf-8-sig'))
        for match in re.finditer(r'\]\(([^\s)]+)\)', text):
            link = unquote(match.group(1))
            if re.match(r'^[a-zA-Z][\w+.-]*:', link) or link.startswith('//'):
                continue
            path, _, anchor = link.partition('#')
            if '<' in path or '>' in path:  # documented template placeholder
                continue
            target = (source.parent / path).resolve() if path else source
            checked += 1
            line = text[:match.start()].count('\n') + 1
            if not target.exists():
                errors.append(f'{source.relative_to(ROOT)}:{line}: missing {link}')
            elif anchor and target.suffix == '.md' and anchor not in anchors(target.read_text(encoding='utf-8-sig')):
                errors.append(f'{source.relative_to(ROOT)}:{line}: missing anchor {link}')
    # The migration record is also a manifest: every destination must exist,
    # and a moved source must not survive as a duplicate or redirect stub.
    manifest = (ROOT/'docs/tooling/tmp/2026-09-26_document_migration.md').read_text(encoding='utf-8')
    moved = {}
    for old, new in re.findall(r'^\| `([^`]+)` \| `([^`]+)` \|', manifest, re.M):
        if not (ROOT/new).is_file():
            errors.append(f'migration destination missing: {new}')
        if old != new:
            moved[old] = new
            if (ROOT/old).exists():
                errors.append(f'obsolete migration source still exists: {old}')
    for source in sorted(files):
        if 'tmp' in source.parts or 'reports' in source.parts:
            continue  # Historical paths in dated evidence are intentional.
        text = source.read_text(encoding='utf-8-sig')
        for old in moved:
            if old in text:
                errors.append(f'{source.relative_to(ROOT)}: obsolete active path {old}')
    for error in errors:
        print(error)
    print(f'DOCUMENTATION links={checked} files={len(files)} errors={len(errors)}')
    return bool(errors)


if __name__ == '__main__':
    raise SystemExit(main())
