#!/usr/bin/env python3
"""
Génération de l'icône ContextWatch — style macOS premium
Concept : arc de progression coloré + oeil stylisé au centre
"""

import math
import os
from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024

def lerp(a, b, t):
    return a + (b - a) * t

def lerp_color(c1, c2, t):
    return tuple(int(lerp(c1[i], c2[i], t)) for i in range(3))

def gradient_color(colors, t):
    """Couleur dans un gradient multi-stops, t dans [0,1]."""
    n = len(colors) - 1
    seg = t * n
    i = min(int(seg), n - 1)
    return lerp_color(colors[i], colors[i + 1], seg - i)

# ─── Canvas principal (RGBA, fond transparent) ────────────────────────────────
img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
draw = ImageDraw.Draw(img)

cx, cy = SIZE // 2, SIZE // 2

# ─── 1. Fond arrondi macOS ────────────────────────────────────────────────────
corner_r = int(SIZE * 0.225)

# Dégradé vertical bleu nuit → bleu profond
for y in range(SIZE):
    t = y / SIZE
    c = lerp_color((14, 16, 30), (20, 24, 48), t)
    # On dessine seulement dans le rectangle arrondi via un mask après
    draw.line([(0, y), (SIZE - 1, y)], fill=c + (255,))

# Appliquer le masque arrondi au fond
bg_mask = Image.new("L", (SIZE, SIZE), 0)
ImageDraw.Draw(bg_mask).rounded_rectangle([0, 0, SIZE - 1, SIZE - 1], radius=corner_r, fill=255)
img.putalpha(bg_mask)

# ─── 2. Lueur ambiante centrale (orangée, style Claude) ───────────────────────
glow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
gd = ImageDraw.Draw(glow)
for r in range(460, 50, -8):
    a = int(22 * (1 - r / 460))
    gd.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(255, 130, 50, a))
glow = glow.filter(ImageFilter.GaussianBlur(30))
img = Image.alpha_composite(img, glow)
draw = ImageDraw.Draw(img)

# ─── 3. Arc de progression (jauge) ────────────────────────────────────────────
ARC_R = int(SIZE * 0.37)
ARC_T = int(SIZE * 0.068)   # épaisseur

ANGLE_START = 145           # degrés (rotation dans le sens horaire depuis droite)
ANGLE_END   = 395           # 250° d'arc total
FILL_PCT    = 0.75          # pour l'icône statique : 75%

GRADIENT = [
    (52, 211, 153),          # vert émeraude
    (250, 204, 21),          # jaune
    (251, 146, 60),          # orange
    (239, 68, 68),           # rouge
]

# Piste de fond (gris très sombre)
track = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
td = ImageDraw.Draw(track)
steps = 600
for i in range(steps):
    t = i / steps
    angle = math.radians(ANGLE_START + (ANGLE_END - ANGLE_START) * t)
    for rr in range(ARC_R - ARC_T // 2, ARC_R + ARC_T // 2 + 1, 3):
        x = cx + rr * math.cos(angle)
        y = cy + rr * math.sin(angle)
        td.ellipse([x - 3, y - 3, x + 3, y + 3], fill=(255, 255, 255, 22))
img = Image.alpha_composite(img, track)

# Arc coloré rempli à FILL_PCT
arc = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
ad = ImageDraw.Draw(arc)
fill_end = ANGLE_START + (ANGLE_END - ANGLE_START) * FILL_PCT
steps_f = 500
for i in range(steps_f):
    t = i / steps_f
    angle = math.radians(ANGLE_START + (fill_end - ANGLE_START) * t)
    col = gradient_color(GRADIENT, t * FILL_PCT)
    for rr in range(ARC_R - ARC_T // 2, ARC_R + ARC_T // 2 + 1, 2):
        x = cx + rr * math.cos(angle)
        y = cy + rr * math.sin(angle)
        ad.ellipse([x - 4, y - 4, x + 4, y + 4], fill=col + (255,))

# Glow de l'arc
arc_glow = arc.filter(ImageFilter.GaussianBlur(10))
img = Image.alpha_composite(img, arc_glow)
img = Image.alpha_composite(img, arc)
draw = ImageDraw.Draw(img)

# Point lumineux à l'extrémité de l'arc
tip_angle_rad = math.radians(fill_end)
tip_x = cx + ARC_R * math.cos(tip_angle_rad)
tip_y = cy + ARC_R * math.sin(tip_angle_rad)
tip_col = gradient_color(GRADIENT, FILL_PCT)

tip_layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
tl = ImageDraw.Draw(tip_layer)
tr = ARC_T // 2 + 6
for offset in range(tr + 35, tr, -3):
    a = int(180 * (1 - (offset - tr) / 35))
    tl.ellipse([tip_x - offset, tip_y - offset, tip_x + offset, tip_y + offset],
               fill=tip_col + (a,))
tip_glow = tip_layer.filter(ImageFilter.GaussianBlur(12))
img = Image.alpha_composite(img, tip_glow)
draw = ImageDraw.Draw(img)
draw.ellipse([tip_x - tr, tip_y - tr, tip_x + tr, tip_y + tr],
             fill=(255, 255, 255, 220))

# ─── 4. Disque sombre central ─────────────────────────────────────────────────
inner_r = ARC_R - ARC_T // 2 - 18
draw.ellipse([cx - inner_r, cy - inner_r, cx + inner_r, cy + inner_r],
             fill=(11, 13, 24, 250))

# ─── 5. Oeil stylisé au centre ────────────────────────────────────────────────
eye_w = int(inner_r * 0.78)   # demi-largeur horizontale
eye_h = int(inner_r * 0.44)   # demi-hauteur verticale

# Dessin de l'oeil via deux arcs (forme d'amande)
# On utilise deux ellipses avec un masque pour ne garder que les arcs visibles

eye_layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
el = ImageDraw.Draw(eye_layer)
eye_col = (210, 218, 235, 255)
lw = 13  # épaisseur du contour

# Arc supérieur : ellipse aplatie, on garde seulement la partie basse
el.ellipse([cx - eye_w, cy - eye_h * 2,
            cx + eye_w, cy + eye_h * 0.3],
           outline=eye_col, width=lw)
# Effacer la moitié haute
el.rectangle([cx - eye_w - 20, cy - eye_h * 3,
              cx + eye_w + 20, cy + 2], fill=(0, 0, 0, 0))

# Arc inférieur : ellipse aplatie, on garde seulement la partie haute
el.ellipse([cx - eye_w, cy - eye_h * 0.3,
            cx + eye_w, cy + eye_h * 2],
           outline=eye_col, width=lw)
# Effacer la moitié basse
el.rectangle([cx - eye_w - 20, cy - 2,
              cx + eye_w + 20, cy + eye_h * 3], fill=(0, 0, 0, 0))

img = Image.alpha_composite(img, eye_layer)
draw = ImageDraw.Draw(img)

# ─── 6. Iris orange ───────────────────────────────────────────────────────────
iris_r = int(inner_r * 0.30)

# Halo iris
halo = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
hd = ImageDraw.Draw(halo)
for r in range(iris_r + 55, iris_r, -4):
    a = int(110 * (1 - (r - iris_r) / 55))
    hd.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(255, 130, 40, a))
halo = halo.filter(ImageFilter.GaussianBlur(18))
img = Image.alpha_composite(img, halo)
draw = ImageDraw.Draw(img)

# Iris (dégradé orange)
for r in range(iris_r, 0, -1):
    t = 1 - r / iris_r
    c = lerp_color((240, 100, 20), (255, 185, 70), t)
    draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=c + (255,))

# Pupille
pupil_r = int(iris_r * 0.40)
draw.ellipse([cx - pupil_r, cy - pupil_r, cx + pupil_r, cy + pupil_r],
             fill=(8, 9, 20, 255))

# Reflet
ref_r = int(iris_r * 0.17)
rx, ry = cx + int(iris_r * 0.30), cy - int(iris_r * 0.30)
draw.ellipse([rx - ref_r, ry - ref_r, rx + ref_r, ry + ref_r],
             fill=(255, 255, 255, 210))

# ─── 7. Brillance subtile en haut (highlight macOS) ───────────────────────────
shine = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
sd = ImageDraw.Draw(shine)
sd.ellipse([int(SIZE * 0.15), int(SIZE * -0.05),
            int(SIZE * 0.85), int(SIZE * 0.50)],
           fill=(255, 255, 255, 14))
shine = shine.filter(ImageFilter.GaussianBlur(25))
img = Image.alpha_composite(img, shine)

# ─── 8. Réappliquer le masque arrondi final ───────────────────────────────────
# (pour que les éléments hors du bord soient bien découpés)
final_mask = Image.new("L", (SIZE, SIZE), 0)
ImageDraw.Draw(final_mask).rounded_rectangle([0, 0, SIZE - 1, SIZE - 1],
                                              radius=corner_r, fill=255)
img.putalpha(final_mask)

# ─── Export ───────────────────────────────────────────────────────────────────
out_dir = "/Users/florianbonin/CosyCosa Dropbox/Flo bip/Files PRO/CLAUDE CODE/App Claude % Context"
out_png = f"{out_dir}/ContextWatch_AppIcon_1024.png"
img.save(out_png)
print(f"Icône sauvegardée : {out_png}")

# Iconset pour conversion .icns
iconset_dir = f"{out_dir}/ContextWatch.iconset"
os.makedirs(iconset_dir, exist_ok=True)
for s in [16, 32, 64, 128, 256, 512, 1024]:
    img.resize((s, s), Image.LANCZOS).save(f"{iconset_dir}/icon_{s}x{s}.png")
    if s <= 512:
        img.resize((s * 2, s * 2), Image.LANCZOS).save(f"{iconset_dir}/icon_{s}x{s}@2x.png")

print("Iconset prêt.")
