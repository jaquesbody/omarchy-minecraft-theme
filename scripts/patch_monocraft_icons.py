#!/usr/bin/env python3
"""Scale Monocraft Nerd's PUA (Nerd Font) glyph outlines to match
JetBrains Mono Nerd's ink size at the same ppem.

Monocraft's Nerd patch renders icons ~30-40% smaller than JBM, which makes
bar status icons shrink when the theme sets font=Monocraft. This rewrites
only Private-Use-Area outlines (ASCII/pixel glyphs untouched) so icons match
the JBM sizing the rest of Omarchy expects.

Idempotent: skips when already scaled (or when JBM has no matching glyph).
Run:  uv run --with fonttools python3 scripts/patch_monocraft_icons.py
"""

from __future__ import annotations

import shutil
import sys
from pathlib import Path

from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.recordingPen import RecordingPen, DecomposingRecordingPen
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.pens.transformPen import TransformPen
from fontTools.misc.transform import Transform
from fontTools.ttLib import TTCollection, TTFont

MONO_TTC = Path.home() / ".local/share/fonts/MonocraftNerd/TTF/MonocraftNerdFont.ttc"
JBM_TTF = Path("/usr/share/fonts/TTF/JetBrainsMonoNerdFont-Regular.ttf")
BACKUP = Path.home() / "font-backup/MonocraftNerdFont.ttc.orig"

PUA_RANGES = (
    (0xE000, 0xF8FF),
    (0xF0000, 0xFFFFD),
    (0x100000, 0x10FFFD),
)
SCALE_MIN, SCALE_MAX = 0.5, 2.5
ALREADY_SCALED_RATIO = 1.15  # mono/jbm width ratio => treat as patched


def is_pua(cp: int) -> bool:
    return any(lo <= cp <= hi for lo, hi in PUA_RANGES)


def ink_bounds(font: TTFont, glyph_set, name: str):
    pen = BoundsPen(glyph_set)
    glyph_set[name].draw(pen)
    return pen.bounds  # (xMin, yMin, xMax, yMax) or None


def ink_size(bounds) -> tuple[float, float]:
    if not bounds:
        return 0.0, 0.0
    return bounds[2] - bounds[0], bounds[3] - bounds[1]


def main() -> int:
    if not MONO_TTC.is_file():
        print(f"missing {MONO_TTC}", file=sys.stderr)
        return 1
    if not JBM_TTF.is_file():
        print(f"missing {JBM_TTF}", file=sys.stderr)
        return 1

    jbm = TTFont(str(JBM_TTF))
    jbm_cmap = jbm.getBestCmap()
    jbm_gs = jbm.getGlyphSet()

    # Precompute JBM ink size per PUA codepoint.
    jbm_ink: dict[int, tuple[float, float]] = {}
    for cp, gname in jbm_cmap.items():
        if is_pua(cp):
            jbm_ink[cp] = ink_size(ink_bounds(jbm, jbm_gs, gname))

    coll = TTCollection(str(MONO_TTC))
    patched = 0
    skipped_already = 0
    skipped_no_jbm = 0

    for face_idx, face in enumerate(coll.fonts):
        cmap = face.getBestCmap()
        gs = face.getGlyphSet()
        glyf = face["glyf"]
        # hmtx = face["hmtx"]

        # Per-codepoint scale from this face's ink vs JBM ink.
        scales: dict[str, tuple[float, float]] = {}
        for cp, gname in cmap.items():
            if not is_pua(cp) or gname in scales:
                continue
            jw, jh = jbm_ink.get(cp, (0.0, 0.0))
            if jw <= 0 or jh <= 0:
                skipped_no_jbm += 1
                continue
            mw, mh = ink_size(ink_bounds(face, gs, gname))
            if mw <= 0 or mh <= 0:
                continue
            ratio = mw / jw
            if ratio >= ALREADY_SCALED_RATIO:
                skipped_already += 1
                continue
            sx = min(max(jw / mw, SCALE_MIN), SCALE_MAX)
            sy = min(max(jh / mh, SCALE_MIN), SCALE_MAX)
            if abs(sx - 1) < 0.02 and abs(sy - 1) < 0.02:
                continue
            scales[gname] = (sx, sy)

        for gname, (sx, sy) in scales.items():
            bounds = ink_bounds(face, gs, gname)
            if not bounds:
                continue
            cx = (bounds[0] + bounds[2]) / 2.0
            cy = (bounds[1] + bounds[3]) / 2.0
            # Scale about ink center: T(cx,cy) * S(sx,sy) * T(-cx,-cy)
            transform = (
                Transform()
                .translate(cx, cy)
                .scale(sx, sy)
                .translate(-cx, -cy)
            )
            # Decompose composites so component transforms survive the rewrite.
            rec = DecomposingRecordingPen(gs)
            gs[gname].draw(rec)
            out_pen = TTGlyphPen(gs)
            rec.replay(TransformPen(out_pen, transform))
            new_glyph = out_pen.glyph()
            # Keep advance width (icons may overflow slightly; bar clips anyway).
            glyf[gname] = new_glyph
            patched += 1
        print(f"face {face_idx}: patched {len(scales)} glyphs")

    if patched == 0:
        print("nothing to do (already scaled or no matching glyphs)")
        return 0

    if not BACKUP.is_file():
        BACKUP.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(MONO_TTC, BACKUP)
        print(f"backup -> {BACKUP}")

    coll.save(str(MONO_TTC))
    print(f"saved {MONO_TTC} ({patched} glyph transforms, "
          f"already={skipped_already}, no-jbm={skipped_no_jbm})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
