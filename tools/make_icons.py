#!/usr/bin/env python3
"""Draws the four Nox app icons (1024x1024 PNG) into Nox/Assets.xcassets.

Pure Python (zlib + struct), no dependencies. Same geometry and colours as
Design/AppIconArt.swift: ring diameter 0.48*size, stroke 0.085*size, dot 0.16*size.
"""
import math, os, struct, sys, zlib

SPECS = {
    "AppIcon":      dict(top=0x1F5A40, bottom=0x0D2A1D, ring=0xA6EFC6),
    "AppIconDark":  dict(top=0x141515, bottom=0x050505, ring=0x4FD08D),
    "AppIconLight": dict(top=0xF4F5F4, bottom=0xBEC3C1, ring=0x1C1D1D),
    "AppIconNeon":  dict(top=0x08150F, bottom=0x030806, ring=0xB5F5D2, glow=0x4FD08D, border=0x4FD08D),
}

def rgb(v):
    return ((v >> 16) & 255) / 255.0, ((v >> 8) & 255) / 255.0, (v & 255) / 255.0

def clamp01(x):
    return 0.0 if x < 0 else 1.0 if x > 1 else x

def mix(c, d, a):
    return (c[0] + (d[0] - c[0]) * a, c[1] + (d[1] - c[1]) * a, c[2] + (d[2] - c[2]) * a)

def phi(x):
    return 0.5 * (1.0 + math.erf(x / math.sqrt(2.0)))

def render(spec, S=1024):
    top, bottom, ring = rgb(spec["top"]), rgb(spec["bottom"]), rgb(spec["ring"])
    glow = rgb(spec["glow"]) if "glow" in spec else None
    border = rgb(spec["border"]) if "border" in spec else None
    c = (S - 1) / 2.0
    ro = 0.24 * S                 # outer ring radius
    ri = ro - 0.085 * S           # inner ring radius
    rd = 0.08 * S                 # centre dot radius
    R = 0.45 * S                  # glow radius
    sigma = 0.04 * S              # halo softness
    inset, bw = 0.03 * S, 0.012 * S
    half = S / 2.0 - inset
    rr = 0.2237 * S - inset
    rows = []
    for y in range(S):
        base = mix(top, bottom, y / (S - 1))
        dy = y - c
        row = bytearray([0])      # PNG filter: none
        for x in range(S):
            dx = x - c
            col = base
            r = math.hypot(dx, dy)
            if glow is not None:
                if r < R:
                    col = mix(col, glow, 0.5 * (1 - r / R))
                halo = (phi((ro - r) / sigma) - phi((ri - r) / sigma)) * (150 / 255.0)
                if halo > 0.002:
                    col = mix(col, glow, halo)
            if r < ro + 1:
                a = clamp01(ro - r + 0.5) * clamp01(r - ri + 0.5)
                a = max(a, clamp01(rd - r + 0.5))
                if a > 0:
                    col = mix(col, ring, a)
            if border is not None:
                qx = abs(x + 0.5 - S / 2.0) - (half - rr)
                qy = abs(y + 0.5 - S / 2.0) - (half - rr)
                sd = math.hypot(max(qx, 0), max(qy, 0)) + min(max(qx, qy), 0) - rr
                if -bw - 1 < sd < 1:
                    a = clamp01(0.5 - sd) * clamp01(sd + bw + 0.5) * (230 / 255.0)
                    if a > 0:
                        col = mix(col, border, a)
            row += bytes((int(col[0] * 255 + 0.5), int(col[1] * 255 + 0.5), int(col[2] * 255 + 0.5)))
        rows.append(bytes(row))
    return b"".join(rows)

def png(raw, S):
    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", S, S, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))

def main():
    root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Nox", "Assets.xcassets")
    force = "--force" in sys.argv
    for name, spec in SPECS.items():
        path = os.path.join(root, name + ".appiconset", name + ".png")
        if os.path.exists(path) and not force:
            print("skip", name)
            continue
        with open(path, "wb") as f:
            f.write(png(render(spec), 1024))
        print("wrote", path)

if __name__ == "__main__":
    main()
