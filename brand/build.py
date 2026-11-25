#!/usr/bin/env python3
"""Every Wain logo asset, built from one traced geometry.

    python3 brand/build.py             # from the repo root: brand/ only
    python3 brand/build.py --install   # and copy into each app, then run
                                       # apps/desktop/scripts/icons.sh
    python3 brand/build.py --check     # self-test only

The source is brand/wain-brand-sheet.png (the brand presentation). The mark and
the wordmark are traced once from it at sub-pixel precision (marching squares
over the anti-aliased edge), and every SVG and PNG below is drawn from those
paths, so no two assets can disagree. Pillow only: no numpy, no potrace.
"""
import math
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
BRAND = ROOT / "brand"
SHEET = BRAND / "wain-brand-sheet.png"

INK = (16, 17, 16)        # the mark's black on the sheet
TILE_DARK = (17, 17, 17)  # the sheet's dark tile
TILE_DEV = (109, 90, 200) # dev builds stay purple, as upstream's did
WHITE = (255, 255, 255)

# Where the big mark and the wordmark sit on the 1254px sheet.
MARK_BOX = (250, 250, 1010, 720)
WORD_BOX = (730, 900, 1200, 1090)


def alpha_of(box):
    """Ink coverage 0..1 per pixel inside box, from the sheet's luminance."""
    crop = Image.open(SHEET).convert("L").crop(box)
    w, h = crop.size
    bg = crop.getextrema()[1]
    ink = 16.6
    px = crop.load()
    return [[max(0.0, min(1.0, (bg - px[x, y]) / (bg - ink))) for x in range(w)] for y in range(h)]


def trace(a, t=0.5):
    """Closed contours of a at level t, with sub-pixel corners (marching squares)."""
    h, w = len(a), len(a[0])
    g = [[0.0] * (w + 2)] + [[0.0] + row + [0.0] for row in a] + [[0.0] * (w + 2)]
    H, W = h + 2, w + 2

    def lerp(p, q):
        return 0.5 if p == q else (t - p) / (q - p)

    point = {}

    def hk(x, y):  # edge from (x,y) to (x+1,y)
        k = ("h", x, y)
        if k not in point:
            point[k] = (x + lerp(g[y][x], g[y][x + 1]), y)
        return k

    def vk(x, y):  # edge from (x,y) to (x,y+1)
        k = ("v", x, y)
        if k not in point:
            point[k] = (x, y + lerp(g[y][x], g[y + 1][x]))
        return k

    nxt = {}
    for y in range(H - 1):
        for x in range(W - 1):
            tl, tr, br, bl = g[y][x] > t, g[y][x + 1] > t, g[y + 1][x + 1] > t, g[y + 1][x] > t
            c = tl << 3 | tr << 2 | br << 1 | bl
            if c in (0, 15):
                continue
            T, R, B, L = (lambda: hk(x, y)), (lambda: vk(x + 1, y)), (lambda: hk(x, y + 1)), (lambda: vk(x, y))
            centre = (g[y][x] + g[y][x + 1] + g[y + 1][x + 1] + g[y + 1][x]) / 4 > t
            # Each pair runs with the filled side on the right, so loops chain one way.
            segs = {
                1: [(L, B)], 2: [(B, R)], 3: [(L, R)], 4: [(R, T)], 6: [(B, T)], 7: [(L, T)],
                8: [(T, L)], 9: [(T, B)], 11: [(T, R)], 12: [(R, L)], 13: [(R, B)], 14: [(B, L)],
                5: [(L, T), (R, B)] if centre else [(L, B), (R, T)],
                10: [(T, R), (B, L)] if centre else [(T, L), (B, R)],
            }[c]
            for p, q in segs:
                nxt[p()] = q()

    loops = []
    while nxt:
        start, k = next(iter(nxt.items()))
        loop = [start]
        cur = nxt.pop(start)
        while cur != start:
            loop.append(cur)
            cur = nxt.pop(cur)
        # Back to sheet coordinates: the padding shifted everything by one.
        loops.append([(point[k][0] - 1, point[k][1] - 1) for k in loop])
    return loops


def simplify(pts, eps):
    """Ramer-Douglas-Peucker on a closed loop."""
    def rdp(seg):
        if len(seg) < 3:
            return seg
        (ax, ay), (bx, by) = seg[0], seg[-1]
        dx, dy = bx - ax, by - ay
        n = math.hypot(dx, dy) or 1e-9
        i, d = max(((i, abs(dy * (px - ax) - dx * (py - ay)) / n) for i, (px, py) in enumerate(seg[1:-1], 1)), key=lambda v: v[1])
        return rdp(seg[: i + 1])[:-1] + rdp(seg[i:]) if d > eps else [seg[0], seg[-1]]
    far = max(range(len(pts)), key=lambda i: (pts[i][0] - pts[0][0]) ** 2 + (pts[i][1] - pts[0][1]) ** 2)
    return rdp(pts[: far + 1])[:-1] + rdp(pts[far:] + [pts[0]])[:-1]


class Shape:
    """Traced loops plus their bounding box, in sheet pixels."""

    def __init__(self, box, min_area=30):
        loops = [simplify(l, 0.18) for l in trace(alpha_of(box))]
        self.loops = [l for l in loops if abs(area(l)) > min_area]
        xs = [x for l in self.loops for x, _ in l]
        ys = [y for l in self.loops for _, y in l]
        self.x0, self.y0, self.x1, self.y1 = min(xs), min(ys), max(xs), max(ys)
        self.w, self.h = self.x1 - self.x0, self.y1 - self.y0

    def path(self, scale, dx=0.0, dy=0.0):
        out = []
        for l in self.loops:
            pts = [f"{(x - self.x0) * scale + dx:.2f} {(y - self.y0) * scale + dy:.2f}" for x, y in l]
            out.append("M" + "L".join(pts) + "Z")
        return "".join(out)

    def mask(self, size, scale, dx, dy, ss=8):
        """An anti-aliased L mask of this shape on a size canvas, holes even-odd."""
        W, H = size
        acc = Image.new("1", (W * ss, H * ss), 0)
        for l in self.loops:
            m = Image.new("1", acc.size, 0)
            ImageDraw.Draw(m).polygon([(((x - self.x0) * scale + dx) * ss, ((y - self.y0) * scale + dy) * ss) for x, y in l], fill=1)
            acc = ImageChops.logical_xor(acc, m)
        return acc.convert("L").resize(size, Image.LANCZOS)


def area(l):
    return sum(x0 * y1 - x1 * y0 for (x0, y0), (x1, y1) in zip(l, l[1:] + l[:1])) / 2


def svg(viewbox_w, viewbox_h, body, label):
    return (f'<svg viewBox="0 0 {viewbox_w:g} {viewbox_h:g}" fill="none" xmlns="http://www.w3.org/2000/svg" '
            f'role="img" aria-label="{label}">\n{body}\n</svg>\n')


def squircle(size, ss=4):
    """Apple's continuous-corner tile, as a superellipse (n=5), full-bleed."""
    n, S = 5.0, size * ss
    r = S / 2
    im = Image.new("L", (S, S), 0)
    px = im.load()
    for y in range(S):
        v = abs((y + 0.5 - r) / r) ** n
        if v >= 1:
            continue
        half = r * (1 - v) ** (1 / n)
        for x in range(int(r - half), int(r + half) + 1):
            px[min(x, S - 1), y] = 255
    return im.resize((size, size), Image.LANCZOS)


def tile_icon(mark, size, fill, ink, glyph=0.64, rounded=True):
    """The mark centred on a filled tile: rounded for app icons, square for OAuth logos."""
    gw = size * glyph
    scale = gw / mark.w
    gh = mark.h * scale
    icon = Image.new("RGBA", (size, size), fill + (255,))
    glyph_layer = Image.new("RGBA", (size, size), ink + (255,))
    icon = Image.composite(glyph_layer, icon, mark.mask((size, size), scale, (size - gw) / 2, (size - gh) / 2))
    if rounded:
        icon.putalpha(squircle(size))
    return icon


def lockup(mark, word, height=96):
    """Mark plus wordmark in one row, mark full height, as the 466x96 Dray lockup was laid out."""
    ms = height / mark.h
    cap = height * 0.75
    ws = cap / word.h
    gap = height * 0.30
    mw = mark.w * ms
    width = mw + gap + word.w * ws
    body = (f'<path d="{mark.path(ms)}" fill="currentColor" fill-rule="evenodd"/>\n'
            f'<path d="{word.path(ws, mw + gap, (height - cap) / 2)}" fill="currentColor" fill-rule="evenodd"/>')
    return round(width, 2), height, body


def og_image(mark, word, out):
    W, H = 1200, 630
    img = Image.new("RGB", (W, H), (10, 10, 10))
    white = Image.new("RGB", (W, H), WHITE)
    mh = 120
    ms = mh / mark.h
    img = Image.composite(white, img, mark.mask((W, H), ms, 96, 120))
    wh = 84
    ws = wh / word.h
    img = Image.composite(white, img, word.mask((W, H), ws, 96 + mark.w * ms + 40, 120 + (mh - wh) / 2))
    fonts = ROOT / "apps/gpui/assets/fonts"
    draw = ImageDraw.Draw(img)
    draw.text((96, 340), "Run every coding agent in one app.", font=ImageFont.truetype(str(fonts / "Geist-Medium.ttf"), 56), fill=WHITE)
    draw.text((96, 430), "Claude Code · Codex · Grok · pi · fx · OpenCode", font=ImageFont.truetype(str(fonts / "Geist-Regular.ttf"), 32), fill=(140, 140, 140))
    draw.text((96, 520), "Free and open source · wainhq.com", font=ImageFont.truetype(str(fonts / "Geist-Regular.ttf"), 28), fill=(110, 110, 110))
    img.save(out)


def check():
    # A 3x3 square with a 1x1 hole traces to an outer loop and a hole loop.
    a = [[0] * 7 for _ in range(7)]
    for y in range(2, 5):
        for x in range(2, 5):
            a[y][x] = 1.0
    a[3][3] = 0.0
    loops = trace(a)
    assert len(loops) == 2, loops
    areas = sorted(abs(area(l)) for l in loops)
    assert 0.4 < areas[0] < 1.6 and 7 < areas[1] < 11, areas
    assert len(simplify([(0, 0), (1, 0.01), (2, 0), (2, 2), (0, 2)], 0.1)) == 4
    print("check: tracing and simplifying pass")


def main():
    check()
    if "--check" in sys.argv:
        return
    mark = Shape(MARK_BOX)
    word = Shape(WORD_BOX, min_area=10)
    print(f"mark: {len(mark.loops)} loops, {mark.w:.0f}x{mark.h:.0f}px; wordmark: {len(word.loops)} loops")

    (BRAND / "wain-mark.svg").write_text(svg(round(mark.w * 96 / mark.h, 2), 96, f'<path d="{mark.path(96 / mark.h)}" fill="currentColor" fill-rule="evenodd"/>', "Wain"))
    (BRAND / "wain-wordmark.svg").write_text(svg(round(word.w * 72 / word.h, 2), 72, f'<path d="{word.path(72 / word.h)}" fill="currentColor" fill-rule="evenodd"/>', "Wain"))
    lw, lh, body = lockup(mark, word)
    (BRAND / "wain-lockup.svg").write_text(svg(lw, lh, body, "Wain"))

    out = BRAND / "png"
    out.mkdir(exist_ok=True)
    tile_icon(mark, 1024, TILE_DARK, WHITE).save(out / "icon-dark-1024.png")
    tile_icon(mark, 1024, WHITE, INK).save(out / "icon-light-1024.png")
    tile_icon(mark, 1024, TILE_DEV, WHITE).save(out / "icon-dev-1024.png")
    tile_icon(mark, 256, TILE_DARK, WHITE).save(out / "icon-256.png")
    tile_icon(mark, 180, TILE_DARK, WHITE, rounded=False).convert("RGB").save(out / "apple-touch-180.png")
    tile_icon(mark, 120, TILE_DARK, WHITE, rounded=False).convert("RGB").save(out / "oauth-google-120.png")
    tile_icon(mark, 512, TILE_DARK, WHITE, rounded=False).convert("RGB").save(out / "oauth-github-512.png")
    for px in (16, 32):
        tile_icon(mark, px, TILE_DARK, WHITE, glyph=0.72).save(out / f"favicon-{px}.png")
    og_image(mark, word, out / "opengraph-1200x630.png")
    print(f"wrote brand/wain-{{mark,wordmark,lockup}}.svg and {len(list(out.glob('*.png')))} PNGs in brand/png")
    if "--install" in sys.argv:
        install(out, lw, lh, body)


def install(out, lw, lh, body):
    """Copy the assets to where each app reads them. The inline lockups in apps/web's
    Wordmark.tsx and apps/desktop's onboarding Welcome.tsx are edited by hand from
    brand/wain-lockup.svg; afterwards apps/desktop/scripts/icons.sh rebuilds icns/ico."""
    import shutil
    icons = ROOT / "apps/desktop/src-tauri/icons/src"
    # Dark is the app icon in both slots: the light tile (black glyph on white)
    # is the pattern Dray's own icon uses, so Wain does not lead with it.
    shutil.copy(out / "icon-dark-1024.png", icons / "icon-1024.png")
    shutil.copy(out / "icon-dark-1024.png", icons / "icon-dark-1024.png")
    shutil.copy(out / "icon-dev-1024.png", icons / "icon-dev-1024.png")
    web = ROOT / "apps/web/src/app"
    shutil.copy(out / "icon-256.png", web / "icon.png")
    shutil.copy(out / "apple-touch-180.png", web / "apple-icon.png")
    shutil.copy(out / "opengraph-1200x630.png", web / "opengraph-image.png")
    docs = ROOT / "apps/docs/public"
    shutil.copy(out / "icon-256.png", docs / "icon.png")
    (docs / "logo.svg").write_text(svg(lw, lh, body, "Wain"))
    # The composer's mask and GPUI paint the file as it is; black reads as full alpha.
    black = body.replace('fill="currentColor"', 'fill="black"')
    sized = f'<svg width="{lw:g}" height="{lh:g}" viewBox="0 0 {lw:g} {lh:g}" fill="none" xmlns="http://www.w3.org/2000/svg">\n{black}\n</svg>\n'
    (ROOT / "apps/desktop/public/assets/wain-logo.svg").write_text(sized)
    (ROOT / "apps/gpui/assets/icons/wain-logo.svg").write_text(sized)
    print("installed into apps/desktop, apps/web, apps/docs and apps/gpui")


if __name__ == "__main__":
    main()
