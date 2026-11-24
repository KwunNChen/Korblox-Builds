"""Draws the Dark Magic VFX textures (transparent PNGs) into this folder:
   python vfx/make_textures.py
Uploaded to the group as Decals; the image ids live in DarkMagic.server.luau (TEX_*)."""
import math
import os
import random

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

OUT = os.path.dirname(os.path.abspath(__file__))
VIOLET = (150, 45, 230)
PURPLE = (70, 0, 140)
IRON = (28, 22, 36)
rng = random.Random(7)


def save(img, name):
    img.save(os.path.join(OUT, name))
    print(name, img.size)


def glow(base, radius, color, strength=1.0):
    """Soft coloured halo under the opaque shape of `base` (RGBA)."""
    a = base.split()[3].filter(ImageFilter.GaussianBlur(radius))
    a = a.point(lambda v: min(255, int(v * strength)))
    halo = Image.new("RGBA", base.size, color + (0,))
    halo.putalpha(a)
    return Image.alpha_composite(halo, base)


# Chain: two links per tile along x (a Beam repeats it), side link edge-on as a bar.
def chain():
    W, H = 512, 256
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for i in range(2):
        x0 = i * 256
        # face-on link: a long oval filling most of the tile
        d.ellipse([x0 + 8, 52, x0 + 196, 204], outline=IRON + (255,), width=34)
        d.ellipse([x0 + 16, 60, x0 + 188, 196], outline=(66, 54, 80, 255), width=6)  # worn rim
        # edge-on link threading through it into the next one
        d.rounded_rectangle([x0 + 150, 110, x0 + 262, 146], radius=16, fill=IRON + (255,))
        d.line([x0 + 162, 117, x0 + 250, 117], fill=(74, 62, 90, 255), width=4)
    save(glow(img, 10, VIOLET, 1.4), "chain.png")


# Tendril: a wispy streak that tiles along x; ink-black core with violet fringe.
def tendril():
    W, H = 512, 128
    y = np.linspace(-1, 1, H)[:, None]
    x = np.linspace(0, 2 * math.pi, W)[None, :]
    wave = 0.12 * np.sin(x * 2) + 0.06 * np.sin(x * 5 + 1.3)
    dist = np.abs(y - wave)
    core = np.clip(1 - dist / 0.55, 0, 1) ** 1.2
    fringe = np.clip(1 - dist / 0.85, 0, 1) ** 2
    noise = 0.65 + 0.35 * np.sin(x * 9 + y * 6) * np.sin(x * 4 - y * 3)
    a = np.clip((core * 0.95 + fringe * 0.5) * noise, 0, 1)
    rgb = np.zeros((H, W, 3))
    edge = np.clip(fringe - core, 0, 1)[..., None]
    rgb[:] = np.array([8, 0, 14])
    rgb = rgb * (1 - edge) + np.array(VIOLET) * edge
    img = np.dstack([rgb, a * 255]).astype(np.uint8)
    save(Image.fromarray(img, "RGBA"), "tendril.png")


# Ground cracks: jagged fissures out from the centre, violet glowing inside, black rims.
def cracks():
    S = 512
    lines = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(lines)

    def branch(x, y, ang, length, width, depth):
        pts = [(x, y)]
        for _ in range(int(length / 14)):
            ang += rng.uniform(-0.45, 0.45)
            x += math.cos(ang) * 14
            y += math.sin(ang) * 14
            pts.append((x, y))
            if depth < 2 and rng.random() < 0.12:
                branch(x, y, ang + rng.choice([-1, 1]) * rng.uniform(0.5, 1.0), length * 0.45, max(2, width * 0.6), depth + 1)
        d.line(pts, fill=(0, 0, 0, 255), width=int(width), joint="curve")

    for i in range(9):
        a = i / 9 * 2 * math.pi + rng.uniform(-0.2, 0.2)
        branch(S / 2, S / 2, a, rng.uniform(150, 240), rng.uniform(9, 14), 0)
    d.ellipse([S / 2 - 34, S / 2 - 34, S / 2 + 34, S / 2 + 34], fill=(0, 0, 0, 255))
    inner = lines.split()[3].filter(ImageFilter.MinFilter(5))  # thinner copy: the glowing fissure inside
    fissure = Image.new("RGBA", (S, S), VIOLET + (0,))
    fissure.putalpha(inner)
    img = Image.alpha_composite(glow(lines, 6, (20, 0, 30), 1.2), fissure)
    save(glow(img, 4, PURPLE, 0.8), "cracks.png")


# Rune circle: double ring, jagged runes between, an point-down triangle and an eye inside. Violet lines, no fill.
def runes():
    S = 512
    c = S / 2
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    col = VIOLET + (255,)
    for r, w in ((240, 6), (205, 4), (120, 4)):
        d.ellipse([c - r, c - r, c + r, c + r], outline=col, width=w)
    for i in range(16):  # glyphs in the band between the outer rings
        a = i / 16 * 2 * math.pi
        gx, gy = c + math.cos(a) * 222, c + math.sin(a) * 222
        pts = []
        for _ in range(4):
            pts.append((gx + rng.uniform(-11, 11), gy + rng.uniform(-11, 11)))
        d.line(pts, fill=col, width=4)
    tri = [(c + math.cos(math.pi / 2 + k * 2 * math.pi / 3) * 200, c + math.sin(math.pi / 2 + k * 2 * math.pi / 3) * 200) for k in range(4)]
    d.line(tri, fill=col, width=5)  # point-down triangle (y grows downward)
    d.ellipse([c - 34, c - 18, c + 34, c + 18], outline=col, width=5)  # an eye in the middle
    d.ellipse([c - 10, c - 10, c + 10, c + 10], fill=col)
    save(glow(img, 8, PURPLE, 1.6), "runes.png")


# Shockwave ring: thin hard ring with a dark inner smear.
def ring():
    S = 512
    y, x = np.mgrid[0:S, 0:S]
    r = np.hypot(x - S / 2, y - S / 2) / (S / 2)
    edge = np.exp(-((r - 0.9) / 0.035) ** 2)
    smear = np.clip((r - 0.45) / 0.45, 0, 1) ** 2 * (r < 0.92)
    a = np.clip(edge + smear * 0.45, 0, 1)
    rgb = np.zeros((S, S, 3))
    rgb[:] = np.array([10, 0, 18])
    rgb = rgb + np.array(VIOLET)[None, None, :] * edge[..., None]
    img = np.dstack([np.clip(rgb, 0, 255), a * 255]).astype(np.uint8)
    save(Image.fromarray(img, "RGBA"), "ring.png")


# Skull wisp: a soft dark skull with violet-lit sockets, for the hex crown and the soul's trail.
def skull():
    S = 256
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    bone = (24, 10, 34, 255)
    d.ellipse([48, 24, 208, 176], fill=bone)  # cranium
    d.rounded_rectangle([82, 140, 174, 214], radius=18, fill=bone)  # jaw
    d.ellipse([74, 92, 122, 146], fill=(0, 0, 0, 0))  # sockets cut out
    d.ellipse([134, 92, 182, 146], fill=(0, 0, 0, 0))
    d.polygon([(128, 150), (116, 172), (140, 172)], fill=(0, 0, 0, 0))  # nose
    for i in range(5):  # teeth gaps
        x = 92 + i * 18
        d.rectangle([x, 186, x + 5, 214], fill=(0, 0, 0, 0))
    eyes = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    e = ImageDraw.Draw(eyes)
    e.ellipse([86, 106, 110, 132], fill=VIOLET + (255,))
    e.ellipse([146, 106, 170, 132], fill=VIOLET + (255,))
    img = Image.alpha_composite(img, glow(eyes, 7, VIOLET, 2.0))
    img = glow(img, 6, PURPLE, 1.0).filter(ImageFilter.GaussianBlur(1.2))
    save(img, "skull.png")


for f in (chain, tendril, cracks, runes, ring, skull):
    f()
