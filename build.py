"""Build script for the Doom Runner GZDoom mod.
Generates the few own graphics (PNG), the UDMF map and packs everything into DoomRunner.pk3.
All level textures, monster/item sprites and sounds come from the player's own Doom II
IWAD (or from Brutal Doom when that is loaded) - none of that is shipped in the pk3.
Usage:  python build.py
"""
import math, os, random, struct, zlib, zipfile

ROOT = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(ROOT, "src")
OUT = os.path.join(ROOT, "DoomRunner.pk3")

files = {}  # path inside pk3 -> bytes

# ----------------------------------------------------------------- PNG ----
def png_bytes(w, h, px, grab=None):
    raw = bytearray()
    for y in range(h):
        raw.append(0)
        for x in range(w):
            r, g, b, a = px[y * w + x]
            raw += bytes((clamp8(r), clamp8(g), clamp8(b), clamp8(a)))

    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)

    out = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
    if grab is not None:
        out += chunk(b"grAb", struct.pack(">ii", int(grab[0]), int(grab[1])))
    out += chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b"")
    return out


def clamp8(v):
    return 0 if v < 0 else 255 if v > 255 else int(v)


class Canvas:
    def __init__(self, w, h, fill=(0, 0, 0, 0)):
        self.w, self.h = w, h
        self.px = [list(fill) for _ in range(w * h)]

    def blend(self, x, y, col, cov=1.0):
        if not (0 <= x < self.w and 0 <= y < self.h) or cov <= 0:
            return
        r, g, b = col[:3]
        a = (col[3] / 255.0 if len(col) > 3 else 1.0) * cov
        d = self.px[y * self.w + x]
        da = d[3] / 255.0
        oa = a + da * (1 - a)
        if oa <= 0:
            return
        for i, c in enumerate((r, g, b)):
            d[i] = (c * a + d[i] * da * (1 - a)) / oa
        d[3] = oa * 255

    def shape(self, fn, ss=3):
        """fn(x, y) -> colour tuple or None. Supersampled."""
        for y in range(self.h):
            for x in range(self.w):
                acc = [0.0, 0.0, 0.0, 0.0]
                n = 0
                for sy in range(ss):
                    for sx in range(ss):
                        c = fn(x + (sx + 0.5) / ss, y + (sy + 0.5) / ss)
                        if c is not None:
                            a = c[3] if len(c) > 3 else 255
                            acc[0] += c[0] * a; acc[1] += c[1] * a; acc[2] += c[2] * a; acc[3] += a
                            n += 1
                if n and acc[3] > 0:
                    col = (acc[0] / acc[3], acc[1] / acc[3], acc[2] / acc[3], acc[3] / n)
                    self.blend(x, y, col, n / (ss * ss))

    def png(self, grab=None):
        return png_bytes(self.w, self.h, self.px, grab)


def lerpc(c1, c2, t):
    t = max(0.0, min(1.0, t))
    return tuple(a + (b - a) * t for a, b in zip(c1, c2))


def sd_rrect(x, y, cx, cy, hw, hh, r):
    qx = abs(x - cx) - (hw - r)
    qy = abs(y - cy) - (hh - r)
    return math.hypot(max(qx, 0), max(qy, 0)) + min(max(qx, qy), 0) - r

# ----------------------------------------------------------------- Sprites
def make_sprites():
    # Gates: Doom-style force fields (A = green / good, B = red / bad)
    for frame, core, glow in (("A", (40, 230, 70), (170, 255, 160)),
                              ("B", (235, 30, 20), (255, 160, 100))):
        W, H = 128, 96
        c = Canvas(W, H)

        def gate(x, y, core=core, glow=glow):
            xi, yi = int(x), int(y)
            if xi < 9 or xi >= W - 9:  # metal posts
                if (xi % 9) in (0, 8):
                    return (40, 38, 36, 255)
                shade = 0.75 + 0.25 * math.cos(((xi % 9) - 4) / 4)
                return (95 * shade, 92 * shade, 88 * shade, 255)
            if yi < 12:  # top bar with hazard stripes
                if yi < 2 or yi > 9:
                    return (40, 38, 36, 255)
                return (230, 190, 30, 255) if ((xi + yi) // 7) % 2 == 0 else (30, 30, 30, 255)
            if yi > H - 4:
                return (60, 58, 55, 255)
            ex = min(x - 9, W - 9 - x) / 12.0
            edge = max(0.0, 1 - min(ex, (y - 12) / 10.0))
            scan = 0.15 if (yi // 3) % 2 == 0 else 0.0
            col = lerpc(core, glow, min(1, edge * 0.9 + scan))
            return (*col, 110 + 120 * edge + scan * 150)

        c.shape(gate, ss=1)
        files[f"sprites/RGAT{frame}0.png"] = c.png((W // 2, H - 1))

    # bullets
    def glow(size, core, edge, rim, name):
        c = Canvas(size, size)
        r = size / 2

        def f(x, y):
            d = math.hypot(x - r, y - r) / r
            if d > 1:
                return None
            if d > 0.78:
                return (*rim, 255)
            return (*lerpc(core, edge, d / 0.78), 255)

        c.shape(f)
        files[name] = c.png((size // 2, size // 2))

    glow(14, (255, 255, 220), (255, 190, 40), (90, 40, 10), "sprites/RBULA0.png")
    glow(26, (255, 255, 230), (255, 160, 30), (90, 40, 10), "sprites/RBULB0.png")
    glow(18, (255, 230, 160), (255, 120, 20), (90, 40, 10), "sprites/RBULC0.png")
    glow(16, (255, 230, 220), (255, 40, 40), (90, 0, 0), "sprites/REBUA0.png")
    glow(26, (255, 220, 200), (255, 50, 30), (90, 0, 0), "sprites/REBUB0.png")

    # wooden splinters (crates)
    for fr, col in (("A", (150, 100, 50)), ("B", (105, 68, 32))):
        c = Canvas(8, 6, (*col, 255))
        files[f"sprites/RCHK{fr}0.png"] = c.png((4, 6))

    # Exit arch: metal posts + red banner with checker border
    W, H = 256, 150
    c = Canvas(W, H)
    for y in range(H):
        for x in range(W):
            p = c.px[y * W + x]
            if x < 12 or x >= W - 12:
                edge = (x % 12) in (0, 11)
                p[:] = [40, 38, 36, 255] if edge else [100, 96, 90, 255]
                if y % 24 == 4 and (x % 12) in (3, 8):
                    p[:] = [170, 165, 155, 255]
            elif y < 46:
                if y < 3 or y > 42:
                    p[:] = [30, 10, 8, 255]
                elif y < 9 or y > 36:
                    chk = ((x - 12) // 6 + (y // 6)) % 2
                    p[:] = [235, 235, 235, 255] if chk else [25, 25, 25, 255]
                else:
                    p[:] = [150 + 30 * math.sin(x / 9), 18, 12, 255]
    files["sprites/RFINA0.png"] = c.png((W // 2, H - 1))

# ------------------------------------------------------------ HUD graphics
def metal_panel(W, H, r, top, bot, border, rivets=True, lip=None):
    c = Canvas(W, H)

    def f(x, y):
        d = sd_rrect(x, y, W / 2, H / 2, W / 2 - 1, H / 2 - 1, r)
        if d > 0:
            return None
        if d > -5:
            return border
        if d > -8:
            return tuple(min(255, v * 1.35) for v in top)
        if lip and y > H - lip:
            return tuple(v * 0.7 for v in bot)
        if rivets:
            for rx, ry in ((15, 15), (W - 15, 15), (15, H - 15), (W - 15, H - 15)):
                dd = math.hypot(x - rx, y - ry)
                if dd < 4.5:
                    return (40, 38, 36) if dd > 3.2 else (175, 170, 160)
        n = ((int(x) * 7 + int(y) * 13) % 11) / 11.0 * 8 - 4
        return tuple(v + n for v in lerpc(top, bot, y / H))

    c.shape(f, ss=2)
    return c.png()


def make_hud():
    files["graphics/RCARD.png"] = metal_panel(240, 350, 14, (82, 78, 74), (36, 34, 34), (120, 30, 18))
    files["graphics/RBTN.png"] = metal_panel(400, 136, 22, (215, 45, 30), (140, 18, 10), (40, 8, 4), lip=18)
    files["graphics/RCOST.png"] = metal_panel(208, 76, 12, (190, 140, 60), (120, 82, 30), (50, 30, 10), rivets=False, lip=10)
    files["graphics/RPILL.png"] = metal_panel(320, 80, 14, (66, 62, 60), (30, 28, 28), (120, 30, 18), rivets=False)


# mouse cursor in three sizes (menus pick one by screen height, the in-game cursor scales freely)
CURSOR_POLY = [(0, 0), (0, 0.78), (0.2, 0.6), (0.34, 0.92), (0.47, 0.86), (0.33, 0.55), (0.58, 0.55)]


def seg_dist(px, py, ax, ay, bx, by):
    dx, dy = bx - ax, by - ay
    l2 = dx * dx + dy * dy
    k = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / l2)) if l2 else 0.0
    return math.hypot(px - ax - k * dx, py - ay - k * dy)


def make_cursors():
    for name, size in (("RCURS1", 32), ("RCURS2", 48), ("RCURS3", 64)):
        s = size - 3
        poly = [(1 + x * s, 1 + y * s) for x, y in CURSOR_POLY]
        border = max(1.6, size / 16.0)
        c = Canvas(size, size)

        def f(x, y, poly=poly, border=border):
            inside = False
            n = len(poly)
            for i in range(n):
                (ax, ay), (bx, by) = poly[i], poly[(i + 1) % n]
                if (ay > y) != (by > y) and x < ax + (y - ay) * (bx - ax) / (by - ay):
                    inside = not inside
            d = min(seg_dist(x, y, *poly[i], *poly[(i + 1) % len(poly)]) for i in range(len(poly)))
            if inside and d > border:
                return (*lerpc((255, 220, 90), (200, 30, 10), min(1.0, (x + y) / (size * 0.9))), 255)
            if inside or d < border * 0.6:
                return (25, 6, 0, 255)
            return None

        c.shape(f)
        files[f"graphics/{name}.png"] = c.png((0, 0))
    files["graphics/RCURSX.png"] = Canvas(32, 32).png((0, 0))   # invisible system cursor

# --------------------------------------------------------------------- Map
class MapBuilder:
    def __init__(self):
        self.verts, self.lines, self.sides, self.sectors = [], [], [], []
        self.vidx = {}

    def V(self, x, y):
        k = (x, y)
        if k not in self.vidx:
            self.vidx[k] = len(self.verts)
            self.verts.append(k)
        return self.vidx[k]

    def S(self, floor, ceil, ftex, light=176, ctex="F_SKY1"):
        self.sectors.append((floor, ceil, ftex, ctex, light))
        return len(self.sectors) - 1

    def SD(self, sec, mid="-", bot="-", top="-"):
        self.sides.append((sec, mid, bot, top))
        return len(self.sides) - 1

    def line(self, a, b, front, back=None, mid="-", backbot="-", blocking=False):
        f = self.SD(front, mid=mid if back is None else "-")
        bk = self.SD(back, bot=backbot) if back is not None else None
        self.lines.append((self.V(*a), self.V(*b), f, bk, blocking))

    def rect(self, x1, y1, x2, y2, front, back=None, mid="-", backbot="-", blocking=False):
        pts = [(x1, y1), (x1, y2), (x2, y2), (x2, y1)]  # clockwise -> right side inside
        for i in range(4):
            self.line(pts[i], pts[(i + 1) % 4], front, back, mid, backbot, blocking)

    def wad(self, mapname):
        out = ['namespace = "zdoom";']
        out.append('thing { x = 0.0; y = 0.0; angle = 90; type = 1; skill1 = true; skill2 = true; skill3 = true; '
                   'skill4 = true; skill5 = true; single = true; coop = true; dm = true; }')
        for x, yv in self.verts:
            out.append(f"vertex {{ x = {x:.1f}; y = {yv:.1f}; }}")
        for v1, v2, f, b, blk in self.lines:
            s = f"linedef {{ v1 = {v1}; v2 = {v2}; sidefront = {f};"
            if b is not None:
                s += f" sideback = {b}; twosided = true;"
            else:
                s += " blocking = true;"
            if blk:
                s += " blocking = true;"
            out.append(s + " }")
        for sec, mid, bot, top in self.sides:
            out.append(f'sidedef {{ sector = {sec}; texturemiddle = "{mid}"; texturebottom = "{bot}"; texturetop = "{top}"; }}')
        for fl, ce, ft, ct, li in self.sectors:
            out.append(f'sector {{ heightfloor = {fl}; heightceiling = {ce}; texturefloor = "{ft}"; '
                       f'textureceiling = "{ct}"; lightlevel = {li}; }}')
        textmap = "\n".join(out).encode("ascii")
        lumps = [(mapname, b""), ("TEXTMAP", textmap), ("ENDMAP", b"")]
        data = bytearray()
        directory = bytearray()
        pos = 12
        for name, d in lumps:
            directory += struct.pack("<ii8s", pos, len(d), name.encode("ascii"))
            data += d
            pos += len(d)
        files[f"maps/{mapname}.wad"] = b"PWAD" + struct.pack("<ii", len(lumps), 12 + len(data)) + bytes(data) + bytes(directory)
        print(f"{mapname}: {len(self.verts)} vertices, {len(self.lines)} lines, {len(self.sectors)} sectors")


Y0, Y1 = -1200, 24576


def make_base(mapname):
    """Episode 1 style: a long indoor corridor of a tech base."""
    m = MapBuilder()
    W = 176
    step = 128
    ys = list(range(Y0, Y1 + 1, step))
    secs = []
    for i in range(len(ys) - 1):
        lightseg = i % 4 == 0
        floor = "FLOOR0_3" if (i // 2) % 2 == 0 else "FLOOR0_6"
        secs.append(m.S(0, 320, floor, light=224 if lightseg else 176, ctex="FLAT2" if lightseg else "CEIL3_5"))
    for i in range(len(ys) - 1):
        y0, y1 = ys[i], ys[i + 1]
        k = i % 8
        wall = "COMPSTA1" if k == 0 else "COMPSTA2" if k == 4 else "SUPPORT2" if k in (2, 6) else "STARTAN3"
        m.line((-W, y0), (-W, y1), secs[i], mid=wall)          # left wall
        m.line((W, y1), (W, y0), secs[i], mid=wall)            # right wall
        if i + 1 < len(secs):
            m.line((W, y1), (-W, y1), secs[i + 1], secs[i])    # open cross line
    m.line((W, ys[0]), (-W, ys[0]), secs[0], mid="STARTAN3")    # start cap
    m.line((-W, ys[-1]), (W, ys[-1]), secs[-1], mid="STARTAN3")  # end cap
    m.wad(mapname)


def make_outdoor(mapname, pit_floor, pit_flat, pit_light, run_flat, run_light, side_tex, outer_tex,
                 cols, near_h, far_h, near_styles, far_styles, cell=(340, 460), bld_light=160, skip=0.22):
    m = MapBuilder()
    CEIL = 2400
    # closed border sector with sky ceiling: the outer edge shows sky instead of a giant wall
    border = m.S(pit_floor, pit_floor, pit_flat, light=pit_light)
    m.rect(-3000, -3400, 3000, 27700, border, mid=outer_tex)
    pit = m.S(pit_floor, CEIL, pit_flat, light=pit_light)
    m.rect(-2800, -3200, 2800, 27500, pit, border)
    run = m.S(0, CEIL, run_flat, light=run_light)
    m.rect(-152, Y0, 152, Y1, run, pit, backbot=side_tex, blocking=True)

    rnd = random.Random(1234)
    y = -2800
    while y < 27000:
        cell_h = rnd.randint(*cell)
        for side in (-1, 1):
            for (cx1, cx2) in cols:
                if rnd.random() < skip:
                    continue
                w = cx2 - cx1
                bw = rnd.randint(int(w * 0.5), w - 30)
                bx1 = cx1 + rnd.randint(0, w - bw)
                bh = rnd.randint(int(cell_h * 0.45), cell_h - 60)
                by1 = y + rnd.randint(0, cell_h - bh - 30)
                near = cx1 == cols[0][0]
                height = rnd.randint(*near_h) if near else rnd.randint(*far_h)
                wall, flat = rnd.choice(near_styles if near else far_styles)
                x1, x2 = (bx1, bx1 + bw) if side > 0 else (-(bx1 + bw), -bx1)
                b = m.S(height, CEIL, flat, light=bld_light)
                m.rect(x1, by1, x2, by1 + bh, b, pit, backbot=wall)
        y += cell_h
    m.wad(mapname)


def make_maps():
    make_base("MAP01")
    # Episode 2 style: city street between brick buildings
    city_styles = [("BRICK1", "FLAT23"), ("BRICK7", "FLAT5_4"), ("BRICK10", "FLAT23"), ("STUCCO", "FLAT5_4"),
                   ("BIGBRIK1", "FLAT23"), ("BRWINDOW", "FLAT5_4"), ("MODWALL3", "FLAT23"), ("BRONZE1", "FLAT5_4")]
    make_outdoor("MAP02", pit_floor=-16, pit_flat="FLAT1_1", pit_light=176, run_flat="FLOOR6_2", run_light=200,
                 side_tex="BSTONE2", outer_tex="BRICK1",
                 cols=[(200, 520), (600, 980), (1060, 1540), (1620, 2500)],
                 near_h=(120, 520), far_h=(200, 900), near_styles=city_styles, far_styles=city_styles,
                 cell=(300, 420), bld_light=168, skip=0.12)
    # Episode 3 style: hell, a bridge over lava
    hell_styles = [("ROCKRED1", "RROCK05"), ("ROCKRED1", "RROCK09"), ("ASHWALL2", "RROCK03"),
                   ("SP_HOT1", "RROCK05"), ("MARBLE1", "FLAT5_7"), ("SUPPORT3", "FLOOR5_1")]
    for name in ("MAP03", "TITLEMAP"):
        make_outdoor(name, pit_floor=-420, pit_flat="LAVA1", pit_light=255, run_flat="FLOOR4_8", run_light=200,
                     side_tex="SUPPORT3", outer_tex="ROCKRED1",
                     cols=[(290, 620), (700, 1080), (1160, 1640), (1720, 2600)],
                     near_h=(-340, -50), far_h=(-250, 460), near_styles=hell_styles, far_styles=hell_styles[:4])


def main():
    random.seed(42)
    make_sprites()
    make_hud()
    make_cursors()
    make_maps()
    with zipfile.ZipFile(OUT, "w", zipfile.ZIP_DEFLATED) as z:
        for base, _, names in os.walk(SRC):
            for n in names:
                full = os.path.join(base, n)
                z.write(full, os.path.relpath(full, SRC).replace("\\", "/"))
        for path, data in sorted(files.items()):
            z.writestr(path, data)
    print("written", OUT)


if __name__ == "__main__":
    main()
