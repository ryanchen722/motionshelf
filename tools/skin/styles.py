# Drawing helpers for the MotionShelf window frame. See final_a.py.
import numpy as np
from PIL import Image
W, H = 1423, 1472
yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
HOLES = {'header': (23, 84, 486, 104), 'sidebar': (16, 195, 380, 1078), 'footer': (22, 1280, 364, 145),
         'params': (428, 196, 956, 499), 'preview': (498, 745, 818, 460), 'transport': (426, 1210, 958, 93), 'bottom': (426, 1338, 958, 88)}
PANELS = [(8, 72, 520, 128), (1212, 72, 200, 128), (6, 183, 402, 1255), (416, 184, 980, 523), (416, 719, 980, 594), (416, 1326, 980, 112)]
def smooth(e0, e1, x): t = np.clip((x - e0) / (e1 - e0), 0, 1); return t * t * (3 - 2 * t)
def _box(a, r, axis):
    pad = [(0, 0)] * a.ndim; pad[axis] = (r + 1, r)
    c = np.cumsum(np.pad(a, pad, mode='edge'), axis=axis); n = a.shape[axis]
    return (np.take(c, np.arange(2 * r + 1, 2 * r + 1 + n), axis=axis) - np.take(c, np.arange(0, n), axis=axis)) / (2 * r + 1)
def blur(a, s):
    a = a.astype(np.float32); r = max(1, int(round(s * 0.9)))
    for _ in range(3): a = _box(_box(a, r, 0), r, 1)
    return a
def sdf(x0, y0, w, h, r, dx=0, dy=0):
    cx, cy = x0 + w / 2 + dx, y0 + h / 2 + dy
    qx, qy = np.abs(xx - cx) - (w / 2 - r), np.abs(yy - cy) - (h / 2 - r)
    return np.hypot(np.maximum(qx, 0), np.maximum(qy, 0)) + np.minimum(np.maximum(qx, qy), 0) - r
def cover(s): return smooth(0.8, -0.8, s)

class Canvas:
    def __init__(self, body, seed=3, grad=0.08, radius=26):
        self.rng = np.random.default_rng(seed)
        self.base = np.zeros((H, W, 3), np.float32)
        self.base[:] = np.array(body, np.float32) * (1 + grad / 2 - grad * (yy / H))[..., None]
        self.base += self.rng.normal(0, 1.1, (H, W, 1))
        s = sdf(0, 0, W, H, radius); self.alpha = cover(s) * 255
        # 機身外緣的斜角
        B = blur(cover(s), 3); gy, gx = np.gradient(B); lit = 0.707 * (gx + gy); lit /= max(np.abs(lit).max(), 1e-6)
        self.base += (np.clip(lit, 0, 1) * 45 - np.clip(-lit, 0, 1) * 45)[..., None]
    def panel(self, x0, y0, w, h, color, r=18, shadow=0.42, hi=70, lo=55, drop=(3, 8), soft=7, ring=0.12, grad=0.07):
        s = sdf(x0, y0, w, h, r); M = cover(s)
        sh = blur(cover(sdf(x0, y0, w, h, r, *drop)), soft) * shadow
        self.base *= (1 - sh * (1 - M))[..., None]
        col = np.array(color, np.float32)[None, None, :] * (1 + grad / 2 - grad * ((yy - y0) / h))[..., None] + self.rng.normal(0, 1.0, (H, W, 1))
        self.base = self.base * (1 - M[..., None]) + col * M[..., None]
        B = blur(M, 2.4); gy, gx = np.gradient(B); lit = 0.707 * (gx + gy); lit /= max(np.abs(lit).max(), 1e-6)
        self.base += ((np.clip(lit, 0, 1) * hi - np.clip(-lit, 0, 1) * lo) * M)[..., None]
        self.base *= (1 - np.exp(-np.abs(s) * 1.1) * ring)[..., None]
    def recess(self, x0, y0, w, h, r=14, strength=1.0):
        s = sdf(x0, y0, w, h, r); M = cover(s); out = 1 - M
        B = blur(M, 2.6); gy, gx = np.gradient(B); lit = 0.707 * (gx + gy); lit /= max(np.abs(lit).max(), 1e-6)
        self.base += (np.clip(-lit, 0, 1) * 55 * strength * out)[..., None]
        self.base -= (np.clip(lit, 0, 1) * 75 * strength * out)[..., None]
        self.base *= (1 - np.exp(-np.maximum(s, 0) / 9.0) * 0.22 * strength * out)[..., None]
    def groove(self, x0, y0, x1, y1, width=1.6, dark=0.30, light=55):
        vx, vy = x1 - x0, y1 - y0; L = max(np.hypot(vx, vy), 1); px, py = xx - x0, yy - y0
        t = np.clip((px * vx + py * vy) / (L * L), 0, 1)
        d = np.hypot(px - t * vx, py - t * vy); d2 = np.hypot(px - t * vx - 1.8, py - t * vy - 1.8)
        self.base *= (1 - np.exp(-(d / width) ** 2) * dark)[..., None]; self.base += (np.exp(-(d2 / width) ** 2) * light)[..., None]
    def slot(self, x0, y0, w, h, color=(60, 50, 40)):          # 凹進去的深色長條（喇叭孔、散熱孔）
        M = cover(sdf(x0, y0, w, h, h / 2))
        self.base = self.base * (1 - M[..., None]) + np.array(color, np.float32) * M[..., None]
        M2 = cover(sdf(x0, y0 + 1.5, w, h, h / 2)); self.base += ((M2 - M).clip(0, 1) * 60)[..., None]
    def screw(self, cx, cy, r=9, color=(205, 198, 186)):
        d = np.hypot(xx - cx, yy - cy); M = smooth(r + 0.7, r - 0.7, d)
        sh = smooth(r + 5, r, np.hypot(xx - cx - 1, yy - cy - 2)) * 0.35
        self.base *= (1 - sh * (1 - M))[..., None]
        col = np.array(color, np.float32)[None, None, :] * (1.12 - 0.25 * ((xx - cx + yy - cy) / (2 * r) + 0.5).clip(0, 1))[..., None]
        self.base = self.base * (1 - M[..., None]) + col * M[..., None]
        line = np.exp(-((xx - cx) - (yy - cy)) ** 2 / 3.0) * M * 0.5
        self.base *= (1 - line)[..., None]
    def dot(self, cx, cy, r, color, glow=0.0):
        d = np.hypot(xx - cx, yy - cy); M = smooth(r + 0.7, r - 0.7, d)
        if glow: self.base += (np.exp(-(d / (r * 2.2)) ** 2) * glow)[..., None] * np.array(color, np.float32)[None, None, :] / 255
        col = np.array(color, np.float32)[None, None, :] * (1.25 - 0.5 * (d / r).clip(0, 1) ** 2)[..., None]
        self.base = self.base * (1 - M[..., None]) + col * M[..., None]
    def rect(self, x0, y0, w, h, color, r=3):
        M = cover(sdf(x0, y0, w, h, r)); self.base = self.base * (1 - M[..., None]) + np.array(color, np.float32) * M[..., None]
    def holes(self, strength=1.0):
        for k, (x0, y0, w, h) in HOLES.items(): self.recess(x0 - 2, y0 - 2, w + 4, h + 4, 14, strength * (1.15 if k == 'preview' else 1.0))
    def save(self, name):
        Image.fromarray(np.dstack([np.clip(self.base, 0, 255), self.alpha]).astype(np.uint8), 'RGBA').save(name)
