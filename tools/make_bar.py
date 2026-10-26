"""Build the grab-escape bar overlays: one 1024x256 DXT5 texture per (key, fill level), shown with r_screenoverlay.

The texture is mapped into the lower middle of the screen with $basetexturetransform; the VTF is clamped and its
border is transparent, so the rest of the screen stays clear. Output goes to build/addon (materials/grab_escape/...),
and with --vpk it is packed into build/grab_escape.vpk with L4D2's own vpk.exe (and --install copies it to addons/).

usage: make_bar.py [--vpk] [--install] [--preview]
"""
import argparse
import io
import os
import shutil
import struct
import subprocess

from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
L4D2 = r"C:\Program Files (x86)\Steam\steamapps\common\Left 4 Dead 2"
FONT = r"C:\Windows\Fonts\impact.ttf"

W, H = 1024, 256
LEVELS = 21  # bar_<key>_00 .. bar_<key>_20
# grab_escape_key value -> (texture key id, label drawn on the key cap); keep in sync with the plugin
KEYS = {"use": "E", "jump": "SPACE", "attack": "LMB", "attack2": "RMB", "reload": "R", "duck": "CTRL"}

# Where the texture lands on screen (fractions of the screen): x 0.18-0.82, y 0.71-0.95 (below the game's own
# "Pummeled! A teammate must help..." line, which sits around y 0.67)
REGION = (0.18, 0.71, 0.82, 0.95)

TEXTUREFLAGS = 0x0004 | 0x0008 | 0x0100 | 0x0200 | 0x2000  # clamp S/T, no mip, no LOD, eight-bit alpha
DXT5 = 15


def draw(label, frac):
    big = 2  # supersample, then downscale for smooth edges
    im = Image.new("RGBA", (W * big, H * big), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    s = lambda v: int(v * big)

    # --- headline: [key cap] MASH TO BREAK FREE!
    font = ImageFont.truetype(FONT, s(92))
    capfont = ImageFont.truetype(FONT, s(70 if len(label) <= 2 else 52))
    words = "BREAK FREE!"
    mash = "MASH"
    capw = s(96) if len(label) <= 2 else s(40) + d.textlength(label, font=capfont)
    gap = s(22)
    total = d.textlength(mash, font=font) + gap + capw + gap + d.textlength(words, font=font)
    x = (W * big - total) / 2
    y = s(12)

    shadow = Image.new("RGBA", im.size, (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)

    def text(xx, t, f, fill):
        sd.text((xx + s(5), y + s(6)), t, font=f, fill=(0, 0, 0, 200))
        d.text((xx, y), t, font=f, fill=fill, stroke_width=s(6), stroke_fill=(0, 0, 0, 255))

    text(x, mash, font, (255, 255, 255, 255))
    x += d.textlength(mash, font=font) + gap
    # key cap
    cy0, cy1 = y + s(10), y + s(104)
    sd.rounded_rectangle((x + s(5), cy0 + s(6), x + capw + s(5), cy1 + s(6)), radius=s(16), fill=(0, 0, 0, 200))
    d.rounded_rectangle((x, cy0, x + capw, cy1), radius=s(16), fill=(245, 245, 245, 255), outline=(0, 0, 0, 255), width=s(6))
    d.rounded_rectangle((x + s(10), cy0 + s(10), x + capw - s(10), cy1 - s(18)), radius=s(10), outline=(190, 190, 190, 255), width=s(3))
    lw = d.textlength(label, font=capfont)
    lb = d.textbbox((0, 0), label, font=capfont)
    d.text((x + (capw - lw) / 2, (cy0 + cy1) / 2 - (lb[1] + lb[3]) / 2 - s(4)), label, font=capfont, fill=(20, 20, 20, 255))
    x += capw + gap
    text(x, words, font, (255, 40, 30, 255))

    # --- the bar
    bx0, by0, bx1, by1 = s(40), s(140), W * big - s(40), s(226)
    sd.rounded_rectangle((bx0 + s(6), by0 + s(8), bx1 + s(6), by1 + s(8)), radius=s(18), fill=(0, 0, 0, 170))
    d.rounded_rectangle((bx0, by0, bx1, by1), radius=s(18), fill=(25, 4, 4, 215), outline=(0, 0, 0, 255), width=s(7))
    ix0, iy0, ix1, iy1 = bx0 + s(12), by0 + s(12), bx1 - s(12), by1 - s(12)
    fw = (ix1 - ix0) * frac
    if fw > s(4):
        fill = Image.new("RGBA", (int(fw), iy1 - iy0))
        fd = ImageDraw.Draw(fill)
        h = iy1 - iy0
        for row in range(h):  # vertical gradient: bright top, deep red bottom
            t = row / max(1, h - 1)
            r = int(255 - 95 * t)
            g = int(60 - 55 * t)
            fd.line((0, row, fill.width, row), fill=(r, g, max(0, g - 10), 255))
        fd.rectangle((0, int(h * 0.08), fill.width, int(h * 0.30)), fill=(255, 150, 140, 90))  # gloss
        mask = Image.new("L", fill.size, 0)
        ImageDraw.Draw(mask).rounded_rectangle((0, 0, fill.width - 1, h - 1), radius=s(10), fill=255)
        im.paste(fill, (ix0, iy0), mask)
    # segment ticks
    for i in range(1, 10):
        tx = ix0 + (ix1 - ix0) * i / 10
        d.line((tx, iy0 + s(4), tx, iy1 - s(4)), fill=(0, 0, 0, 110), width=s(3))

    shadow = shadow.filter(ImageFilter.GaussianBlur(s(4)))
    out = Image.alpha_composite(shadow, im).resize((W, H), Image.LANCZOS)
    # 4 px transparent border: the texture is clamped, so its edge texels repeat across the whole screen
    clear = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    clear.paste(out.crop((4, 4, W - 4, H - 4)), (4, 4))
    return clear


def dxt5_bytes(img):
    buf = io.BytesIO()
    img.save(buf, format="DDS", pixel_format="DXT5")
    data = buf.getvalue()
    assert data[84:88] == b"DXT5"
    return data[128:128 + (W // 4) * (H // 4) * 16]


def write_vtf(path, data):
    header = struct.pack("<4sII", b"VTF\0", 7, 2) + struct.pack("<I", 80)
    header += struct.pack("<HHI", W, H, TEXTUREFLAGS) + struct.pack("<HH", 1, 0) + b"\0" * 4
    header += struct.pack("<3f", 0.5, 0.5, 0.5) + b"\0" * 4 + struct.pack("<f", 1.0)
    header += struct.pack("<i", DXT5) + struct.pack("<B", 1) + struct.pack("<i", -1)
    header += struct.pack("<BB", 0, 0) + struct.pack("<H", 1)
    header += b"\0" * (80 - len(header))
    with open(path, "wb") as f:
        f.write(header + data)


def vmt(texture):
    x0, y0, x1, y1 = REGION
    sx, sy = 1 / (x1 - x0), 1 / (y1 - y0)
    # texcoord = (screen - center) * scale + center + translate, with center .5 .5
    tx = 0.5 - ((x0 + x1) / 2 - 0.5) * sx - 0.5
    ty = 0.5 - ((y0 + y1) / 2 - 0.5) * sy - 0.5
    return (
        'UnlitGeneric\n{\n'
        f'\t"$basetexture" "{texture}"\n'
        '\t"$translucent" "1"\n\t"$ignorez" "1"\n\t"$nofog" "1"\n'
        f'\t"$basetexturetransform" "center .5 .5 scale {sx:.4f} {sy:.4f} rotate 0 translate {tx:.4f} {ty:.4f}"\n'
        '}\n'
    )


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--vpk", action="store_true")
    ap.add_argument("--install", action="store_true")
    ap.add_argument("--preview", action="store_true", help="also write PNGs to build/preview")
    a = ap.parse_args()

    stage = os.path.join(ROOT, "build", "grab_escape")
    if os.path.isdir(stage):
        shutil.rmtree(stage)
    mat = os.path.join(stage, "materials", "grab_escape")
    os.makedirs(mat)
    prev = os.path.join(ROOT, "build", "preview")
    if a.preview:
        os.makedirs(prev, exist_ok=True)
    with open(os.path.join(stage, "addoninfo.txt"), "w") as f:
        f.write('"AddonInfo"\n{\n\taddontitle "Grab Escape bar"\n\taddonauthor "mariokinsmanjr"\n'
                '\taddonContent_Script 0\n\taddonDescription "Overlay textures for the Grab Escape SourceMod plugin"\n}\n')
    for key, label in KEYS.items():
        for lvl in range(LEVELS):
            name = f"bar_{key}_{lvl:02d}"
            img = draw(label, lvl / (LEVELS - 1))
            write_vtf(os.path.join(mat, name + ".vtf"), dxt5_bytes(img))
            with open(os.path.join(mat, name + ".vmt"), "w") as f:
                f.write(vmt("grab_escape/" + name))
            if a.preview and key == "use" and lvl in (0, 7, 14, 20):
                img.save(os.path.join(prev, name + ".png"))
    print("textures:", len(KEYS) * LEVELS)

    if a.vpk:
        r = subprocess.run([os.path.join(L4D2, "bin", "vpk.exe"), stage], capture_output=True, text=True)
        print(r.stdout[-400:], r.stderr[-400:])
        vpk = stage + ".vpk"
        assert os.path.isfile(vpk), "vpk.exe made no vpk"
        print(vpk, os.path.getsize(vpk))
        if a.install:
            shutil.copy(vpk, os.path.join(L4D2, "left4dead2", "addons", "grab_escape.vpk"))
            print("installed")


if __name__ == "__main__":
    main()
