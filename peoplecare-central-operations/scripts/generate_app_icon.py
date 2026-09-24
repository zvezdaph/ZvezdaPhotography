#!/usr/bin/env python3
"""Genera l'icona Windows dell'applicazione (windows/runner/resources/app_icon.ico).

Riproduce il marchio disegnato in BrandMark (lib/src/presentation/shell/sidebar.dart):
quadrato arrotondato con gradiente teal, cuore bianco e badge "+".

Uso (richiede Pillow):  python3 scripts/generate_app_icon.py
"""
import math
import os

from PIL import Image, ImageDraw

MASTER = 1024
SIZES = [16, 20, 24, 32, 40, 48, 64, 128, 256]
TOP_LEFT = (0x3C, 0xC7, 0xC9)
BOTTOM_RIGHT = (0x0B, 0x6E, 0x79)
BADGE = (0x0B, 0x6E, 0x79)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUTPUT = os.path.join(ROOT, 'windows', 'runner', 'resources', 'app_icon.ico')


def gradient(size):
    """Gradiente diagonale dall'angolo in alto a sinistra a quello in basso a destra."""
    img = Image.new('RGBA', (size, size))
    px = img.load()
    for y in range(size):
        for x in range(size):
            t = (x + y) / (2 * (size - 1))
            px[x, y] = tuple(
                round(a + (b - a) * t) for a, b in zip(TOP_LEFT, BOTTOM_RIGHT)
            ) + (255,)
    return img


def heart_points(cx, cy, scale, steps=720):
    points = []
    for i in range(steps):
        t = 2 * math.pi * i / steps
        x = 16 * math.sin(t) ** 3
        y = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)
        points.append((cx + x * scale, cy - y * scale))
    return points


def master(with_badge=True):
    size = MASTER
    margin = round(size * 0.04)
    radius = round((size - 2 * margin) * 0.28)

    mask = Image.new('L', (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (margin, margin, size - margin - 1, size - margin - 1), radius, fill=255
    )
    icon = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    icon.paste(gradient(size), (0, 0), mask)

    draw = ImageDraw.Draw(icon)
    # Il cuore occupa circa il 58% del lato, come nel widget.
    draw.polygon(heart_points(size * 0.5, size * 0.47, size * 0.58 / 34), fill='white')

    if with_badge:
        r = size * 0.15
        cx, cy = size - margin - size * 0.14 - r, size - margin - size * 0.12 - r
        draw.ellipse((cx - r - size * 0.025, cy - r - size * 0.025,
                      cx + r + size * 0.025, cy + r + size * 0.025), fill='white')
        draw.ellipse((cx - r, cy - r, cx + r, cy + r), fill=BADGE)
        arm, thick = r * 0.55, r * 0.2
        draw.rectangle((cx - arm, cy - thick, cx + arm, cy + thick), fill='white')
        draw.rectangle((cx - thick, cy - arm, cx + thick, cy + arm), fill='white')
    return icon


def main():
    full = master(with_badge=True)
    # Sotto i 32 px il badge diventa rumore: solo cuore.
    simple = master(with_badge=False)
    frames = [
        (full if s >= 32 else simple).resize((s, s), Image.LANCZOS) for s in SIZES
    ]
    frames[-1].save(OUTPUT, format='ICO', sizes=[(s, s) for s in SIZES],
                    append_images=frames[:-1])
    print('scritto', OUTPUT)


if __name__ == '__main__':
    main()
