#!/usr/bin/env python3
"""Generate original pixel-art cursors for the MinecraftPixel hyprcursor theme.
All shapes drawn from scratch on a 24x24 grid, nearest-neighbor only.
License: CC0 / public domain (original work, no Mojang assets)."""
from PIL import Image
import os

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "hyprcursors")
W = H = 24

# Palette
WHITE = (255, 255, 255, 255)
BLACK = (0, 0, 0, 255)
CLEAR = (0, 0, 0, 0)
RED = (255, 64, 64, 255)
GREY = (160, 160, 160, 255)
DARK = (40, 40, 40, 255)


def canvas():
    return [[CLEAR for _ in range(W)] for _ in range(H)]


def px(img, x, y, c):
    if 0 <= x < W and 0 <= y < H:
        img[y][x] = c


def rect(img, x0, y0, x1, y1, c):
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            px(img, x, y, c)


def outline_shape(img, filled_cells, color=BLACK):
    """Draw 1px black outline around filled_cells (set of (x,y))."""
    for (x, y) in list(filled_cells):
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            n = (x + dx, y + dy)
            if n not in filled_cells:
                px(img, n[0], n[1], BLACK)


def save(img, shape):
    path = os.path.join(OUT, shape, "image.png")
    im = Image.new("RGBA", (W, H), CLEAR)
    for y in range(H):
        for x in range(W):
            if img[y][x] != CLEAR:
                im.putpixel((x, y), img[y][x])
    im.save(path)


def draw_arrow():
    """Classic white pointer arrow, black outline, drawn pixel by pixel."""
    # Arrow body: diagonal wedge from tip (1,1) down-right, with tail
    body = set()
    # main triangle rows: y=1..12, x=1..y
    for y in range(1, 13):
        for x in range(1, y + 1):
            body.add((x, y))
    # stem / tail going down-left then down
    tail = [
        (1, 13), (1, 14), (1, 15), (1, 16), (1, 17), (1, 18), (1, 19),
        (2, 13), (2, 14), (2, 15), (2, 16), (2, 17),
        (3, 14), (3, 15), (3, 16),
        (4, 15), (4, 16),
        (5, 16),
        (2, 18), (3, 18), (2, 19), (3, 19),
        (4, 17), (4, 18), (5, 17), (5, 18), (4, 19), (5, 19),
        (6, 16), (6, 17), (6, 18),
        (7, 17), (7, 18),
        (8, 17),
        (7, 19), (8, 19),
    ]
    body.update(tail)
    img = canvas()
    outline_shape(img, body)
    for (x, y) in body:
        px(img, x, y, WHITE)
    # Inner shadow line for bevel feel (classic GUI style)
    for y in range(2, 13):
        px(img, 2, y, (200, 200, 200, 255))
    save(img, "left_ptr")


def draw_text():
    """I-beam text cursor."""
    img = canvas()
    rect(img, 7, 3, 16, 4, BLACK)
    rect(img, 7, 19, 16, 20, BLACK)
    rect(img, 11, 4, 12, 19, BLACK)
    # white core
    rect(img, 8, 3, 15, 3, WHITE)
    rect(img, 8, 4, 10, 4, WHITE)
    rect(img, 13, 4, 15, 4, WHITE)
    rect(img, 8, 19, 15, 19, WHITE)
    rect(img, 8, 20, 15, 20, WHITE)
    px(img, 11, 5, WHITE)
    px(img, 12, 5, WHITE)
    save(img, "text")


def draw_pointer():
    """Pointing-hand cursor (simplified pixel hand)."""
    img = canvas()
    body = set()
    # palm
    for y in range(10, 20):
        for x in range(7, 16):
            body.add((x, y))
    # index finger
    for y in range(3, 10):
        body.add((9, y))
        body.add((10, y))
    # thumb
    for i, (x, y) in enumerate([(7, 11), (6, 12), (5, 13), (5, 14), (6, 14), (6, 13)]):
        body.add((x, y))
    # other fingers bumps
    for x in range(11, 15):
        body.add((x, 8))
        body.add((x, 9))
    for x in range(12, 15):
        body.add((x, 7))
    outline_shape(img, body)
    for (x, y) in body:
        px(img, x, y, WHITE)
    # knuckle lines
    for x in range(8, 15):
        px(img, x, 13, (180, 180, 180, 255))
    save(img, "pointer")


def draw_wait():
    """Hourglass / busy cursor."""
    img = canvas()
    body = set()
    # top bar
    for x in range(6, 18):
        body.add((x, 4))
    # bottom bar
    for x in range(6, 18):
        body.add((x, 19))
    # funnel
    for y in range(5, 12):
        inset = y - 5
        for x in range(6 + inset, 18 - inset):
            body.add((x, y))
    for y in range(12, 19):
        inset = 18 - y
        for x in range(6 + inset, 18 - inset):
            body.add((x, y))
    outline_shape(img, body)
    for (x, y) in body:
        px(img, x, y, WHITE)
    # sand (yellow) in top and bottom
    SAND = (255, 220, 80, 255)
    for y in range(6, 11):
        inset = y - 5
        for x in range(7 + inset, 17 - inset):
            px(img, x, y, SAND)
    for y in range(14, 18):
        inset = 18 - y
        for x in range(7 + inset, 17 - inset):
            px(img, x, y, SAND)
    save(img, "wait")


def draw_crosshair():
    """Crosshair precision cursor."""
    img = canvas()
    rect(img, 11, 3, 12, 20, BLACK)
    rect(img, 3, 11, 20, 12, BLACK)
    px(img, 11, 11, CLEAR)
    px(img, 12, 12, CLEAR)
    # white cores
    rect(img, 11, 4, 11, 10, WHITE)
    rect(img, 12, 4, 12, 10, WHITE)
    rect(img, 11, 13, 11, 19, WHITE)
    rect(img, 12, 13, 12, 19, WHITE)
    rect(img, 4, 11, 10, 11, WHITE)
    rect(img, 4, 12, 10, 12, WHITE)
    rect(img, 13, 11, 19, 11, WHITE)
    rect(img, 13, 12, 19, 12, WHITE)
    save(img, "crosshair")


def draw_not_allowed():
    """Circle-slash forbidden cursor."""
    img = canvas()
    import math
    body = set()
    cx, cy, r = 11.5, 11.5, 8.5
    for y in range(H):
        for x in range(W):
            d = math.hypot(x - cx, y - cy)
            if 6.5 <= d <= 8.5:
                body.add((x, y))
    # slash
    for i in range(-7, 8):
        body.add((int(cx + i), int(cy + i)))
        body.add((int(cx + i) + 1, int(cy + i)))
    outline_shape(img, body, DARK)
    for (x, y) in body:
        px(img, x, y, RED)
    save(img, "not-allowed")


META_COMMON = """[General]
resize_algorithm = "nearest"
nominal_size = 1.0
"""

OVERRIDES = {
    "left_ptr": 'define_override = "default;arrow;pointer;left_ptr;top_left_arrow;left-arrow"',
    "text": 'define_override = "text;ibeam;xterm"',
    "pointer": 'define_override = "hand2;hand1;grab;pointer;pointing_hand;link"',
    "wait": 'define_override = "wait;busy;progress;hourglass;start"',
    "crosshair": 'define_override = "crosshair;cross;plus;tcross;target"',
    "not-allowed": 'define_override = "not-allowed;forbidden;no;circle"',
}


def write_meta(shape):
    path = os.path.join(OUT, shape, "meta.toml")
    with open(path, "w") as f:
        f.write(META_COMMON)
        f.write(OVERRIDES[shape] + "\n")
        if shape == "left_ptr":
            f.write("hotspot_x = 0.0\nhotspot_y = 0.0\n")
        elif shape == "text":
            f.write("hotspot_x = 0.5\nhotspot_y = 0.5\n")
        elif shape == "crosshair":
            f.write("hotspot_x = 0.5\nhotspot_y = 0.5\n")
        elif shape == "pointer":
            f.write("hotspot_x = 0.3\nhotspot_y = 0.1\n")
        else:
            f.write("hotspot_x = 0.5\nhotspot_y = 0.5\n")


if __name__ == "__main__":
    draw_arrow()
    draw_text()
    draw_pointer()
    draw_wait()
    draw_crosshair()
    draw_not_allowed()
    for s in OVERRIDES:
        write_meta(s)
    print("Cursor shapes written to", OUT)
