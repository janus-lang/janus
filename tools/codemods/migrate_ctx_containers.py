#!/usr/bin/env python3
# SPDX-License-Identifier: LUL-1.0
# Copyright (c) 2026 Self Sovereign Society Foundation

#!/usr/bin/env python3
#!/usr/bin/env python3
#!/usr/bin/env python3
import os, re, sys, argparse, shutil, json
from pathlib import Path

ARRAYLIST_DECL = re.compile(
    r"""(?P<indent>\s*)var\s+
        (?P<name>[A-Za-z_]\w*)\s*=\s*
        std\.ArrayList\(\s*(?P<type>[^)]+?)\s*\)\s*\{\s*\}\s*;
        (?P<tail>.*?)?
        defer\s+\2\.deinit\(\s*(?P<alloc>[A-Za-z_]\w*)\s*\)\s*;
    """,
    re.VERBOSE | re.DOTALL
)

def rewrite_file(path: Path, dry_run: bool=False) -> dict:
    text = path.read_text(encoding='utf-8', errors='ignore')
    changed = False
    rewrites = []

    # Iterative scan and rebuild
    pos = 0
    out = []
    while pos < len(text):
        m = ARRAYLIST_DECL.search(text, pos)
        if not m:
            out.append(text[pos:])
            break

        out.append(text[pos:m.start()])

        indent = m.group('indent')
        name = m.group('name')
        typ  = m.group('type')
        alloc = m.group('alloc')

        decl = f"{indent}var {name} = List({typ}).with({alloc});\n"
        defer = f"{indent}defer {name}.deinit();\n"
        out.append(decl + defer)

        pos = m.end()
        changed = True
        rewrites.append({"var": name, "type": typ, "alloc": alloc, "span": [m.start(), m.end()]})

    new_text = "".join(out)

    # Method-call rewrites for each var/alloc pair
    if rewrites:
        for r in rewrites:
            name = r["var"]
            alloc = r["alloc"]
            patterns = [
                (rf"{re.escape(name)}\.append\(\s*{re.escape(alloc)}\s*,", f"{name}.append("),
                (rf"{re.escape(name)}\.appendSlice\(\s*{re.escape(alloc)}\s*,", f"{name}.appendSlice("),
                (rf"{re.escape(name)}\.writer\(\s*{re.escape(alloc)}\s*\)", f"{name}.writer()"),
                (rf"{re.escape(name)}\.toOwnedSlice\(\s*{re.escape(alloc)}\s*\)", f"{name}.toOwnedSlice()"),
                (rf"{re.escape(name)}\.deinit\(\s*{re.escape(alloc)}\s*\)", f"{name}.deinit()"),
            ]
            for pat, repl in patterns:
                new_text2, n = re.subn(pat, repl, new_text)
                if n > 0:
                    changed = True
                new_text = new_text2

    if changed:
        if not dry_run:
            backup = path.with_suffix(path.suffix + ".bak")
            try:
                shutil.copyfile(path, backup)
            except Exception:
                pass
            path.write_text(new_text, encoding='utf-8')

    return {"file": str(path), "changed": changed, "rewrites": rewrites}

def main():
    ap = argparse.ArgumentParser(description="Migrate Zig ArrayList usage to context-bound List(T) wrapper.")
    ap.add_argument("paths", nargs="+", help="Files or directories to process")
    ap.add_argument("--dry-run", action="store_true", help="Do not modify files; print planned changes")
    args = ap.parse_args()

    results = []
    for p in args.paths:
        pth = Path(p)
        if pth.is_dir():
            for fp in pth.rglob("*.zig"):
                results.append(rewrite_file(fp, dry_run=args.dry_run))
        elif pth.is_file() and pth.suffix == ".zig":
            results.append(rewrite_file(pth, dry_run=args.dry_run))
    print(json.dumps(results, indent=2))

if __name__ == "__main__":
    main()
