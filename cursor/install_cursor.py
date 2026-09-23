#!/usr/bin/env python3
"""Pack cursor working-state into ~/.local/share/icons/MinecraftPixel (hyprcursor)."""
import zipfile, os, shutil, sys

src = os.path.dirname(os.path.abspath(__file__))
repo = os.path.dirname(src)
work = os.path.join(src, "hyprcursors")
out_dir = os.path.join(os.path.expanduser("~"), ".local/share/icons/MinecraftPixel")

if not os.path.isdir(work):
    sys.exit("working state missing; run generate.py first")

os.makedirs(os.path.dirname(out_dir), exist_ok=True)
shutil.rmtree(out_dir, ignore_errors=True)
os.makedirs(out_dir)
shutil.copy(os.path.join(src, "manifest.toml"), os.path.join(out_dir, "manifest.toml"))

count = 0
for shape in sorted(os.listdir(work)):
    sdir = os.path.join(work, shape)
    if not os.path.isdir(sdir):
        continue
    with zipfile.ZipFile(os.path.join(out_dir, shape + ".hlc"), "w", zipfile.ZIP_DEFLATED) as z:
        for fn in os.listdir(sdir):
            z.write(os.path.join(sdir, fn), fn)
    count += 1

print(f"packed {count} cursor shapes -> {out_dir}")
