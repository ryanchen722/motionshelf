# Draws the MotionShelf window frame: writes a-skin.png (-> Support/skin.png) and a-back.png (-> Support/skin_back.png).
# Usage: cd tools/skin && python3 final_a.py   (needs Pillow and NumPy)
import numpy as np, os
from PIL import Image, ImageDraw
import styles as st
from styles import Canvas, W
# 頂部留白縮短 26、底部不放螺絲：整張圖變成 1423×1422，所有元件往上移 26
SH = 26; H = 1422
st.H = H; st.yy, st.xx = np.mgrid[0:H, 0:W].astype(np.float32)
def up(d): return {k: (x, y - SH, w, h) for k, (x, y, w, h) in d.items()}
# 版面：左右邊距都是 6，欄與欄、列與列之間都是 8
HOLES = up({'sidebar': (16, 195, 380, 1078), 'footer': (16, 1280, 380, 145),
         'params': (428, 196, 977, 499), 'preview': (508, 745, 818, 460), 'transport': (428, 1210, 977, 93), 'bottom': (428, 1338, 977, 88)})
PANELS = [(6, 66, 1411, 109),            # 標題列：一整條，左右對齊下面兩欄的外緣
          (6, 183, 402, 1255), (416, 183, 1001, 524), (416, 715, 1001, 598), (416, 1321, 1001, 117)]
PANELS = [(x, y - SH, w, h) for x, y, w, h in PANELS]
c = Canvas((226, 212, 186), seed=1)
for p in PANELS: c.panel(*p, color=(245, 235, 214))
c.groove(16, 1277 - SH, 396, 1277 - SH); c.groove(428, 1207 - SH, 1405, 1207 - SH)
for row in range(4):                                          # 喇叭孔：置中在標題列的高度裡
    for col in range(12): c.slot(596 + col * 50, 91 - SH + row * 19, 34, 8)
c.rect(0, 22, W, 7, (232, 122, 58), 0); c.rect(0, 29, W, 2, (150, 70, 30), 0)
st.HOLES = HOLES
for k, (x0, y0, w, h) in HOLES.items(): c.recess(x0 - 2, y0 - 2, w + 4, h + 4, 14, 1.15 if k == 'preview' else 1.0)
c.save('a-full.png')
img = np.array(Image.open('a-full.png').convert('RGBA'))
SS = 3; big = Image.new('L', (W * SS, H * SS), 0); d = ImageDraw.Draw(big)
for k, (x, y, w, h) in HOLES.items(): d.rounded_rectangle((x * SS, y * SS, (x + w) * SS - 1, (y + h) * SS - 1), radius=(3 if k == 'preview' else 12) * SS, fill=255)
cut = np.array(big.resize((W, H), Image.LANCZOS)).astype(np.float32) / 255
skin = img.copy(); skin[:, :, 3] = np.clip(img[:, :, 3] * (1 - cut), 0, 255).astype(np.uint8)
Image.fromarray(skin, 'RGBA').save('a-skin.png', optimize=True)
# 洞後面的底：面板的奶油色，上亮下暗一點點
back = np.zeros((H, W, 4), np.uint8)
for k, (x, y, w, h) in HOLES.items():
    t = np.linspace(1.02, 0.97, h + 28)[:, None, None]
    back[y - 14:y + h + 14, x - 14:x + w + 14, :3] = np.clip(np.array((245, 235, 214), np.float32) * t, 0, 255)
    back[y - 14:y + h + 14, x - 14:x + w + 14, 3] = 255
Image.fromarray(back, 'RGBA').save('a-back.png', optimize=True)
print(os.path.getsize('a-skin.png') // 1024, 'KB', os.path.getsize('a-back.png') // 1024, 'KB')
