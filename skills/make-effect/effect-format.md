# MotionShelf effect format

An effect is a folder inside the project's `effects/` folder. The folder name is lowercase English words joined with `-` (e.g. `wedding-name-card`) and must not clash with an existing folder. Folders starting with `_` (like `_inbox`) are not effects.

```
effects/<name>/
  effect.html   the animation
  effect.json   name, category, length and params
  source.md     where the idea came from, plus notes
  thumb.png     480×270 preview, written by tools/check-effects.mjs
```

`effects/title-card` is a complete example to copy from.

## effect.html

- Expose two functions:
  - `window.seek(t)`: draw the frame at `t` seconds.
  - `window.setParams(params)`: receive an object with some or all param values (keys from effect.json), then redraw the current frame.
- The frame must be a pure function of `t` and the params. No CSS transitions or animations, no `setTimeout` / `setInterval` / `requestAnimationFrame` driving the motion, and no state carried from one frame to the next. MotionShelf seeks to arbitrary times, in any order, when previewing and exporting.
- The background is transparent (`html, body { background: transparent }`). MotionShelf exports ProRes 4444 with alpha, so anything you paint is kept and everything else stays see-through.
- Design for a 1920×1080 frame. The page is rendered at the export size (1920×1080, 1080×1920 or 1440×1440), so either draw on a 1920×1080 canvas scaled to fit the window (keep the aspect ratio and center it; a `<canvas id="c">` sized to the window with a scale transform is the simplest way), or lay out relative to the window as `effects/title-card` does.
- Everything is self-contained: no network requests, no external scripts, fonts or images. Use system fonts through a `font` param. The one exception to "no scripts" is 3D: see [3D and camera moves](#3d-and-camera-moves).
- Call `setParams({})` and `seek(...)` once at the end of the script so the file also shows something when opened on its own.

## 3D and camera moves

For a real 3D camera (an effect that starts flat and then turns, tilts, orbits or dollies) use Three.js. Plain CSS 3D (`perspective` + `rotateX/rotateY`) is enough for flipping a single flat card; use Three.js when there are several objects, depth or an orbiting camera.

MotionShelf is offline, so Three.js must be **inlined** into `effect.html`: copy [vendor/three.min.js](vendor/three.min.js) (Three.js r160, MIT) into a first `<script>` block, e.g. `cat head.html vendor/three.min.js tail.html > effects/<name>/effect.html`, and write your own code in a second `<script>` block. Never use `<script src>`. The file grows by about 650 KB, which is fine. Don't edit the vendored file.

Rules that make it export correctly:

- Create the renderer with `new THREE.WebGLRenderer({ alpha: true, antialias: true, preserveDrawingBuffer: true })` and call `renderer.setClearColor(0x000000, 0)` so the background stays transparent. Don't add `scene.background`, fog colors or a backdrop plane unless it is meant to be visible.
- Drive everything from `t`: in `seek(t)` set the camera position and rotation (and any object transforms) from `t` and the params, then call `renderer.render(scene, camera)` once. No `requestAnimationFrame` loop, no `THREE.Clock`, no OrbitControls, no tweens or state from the previous frame.
- Size the renderer to the window in every `seek` (`renderer.setPixelRatio(1)`, `renderer.setSize(innerWidth, innerHeight)`, update `camera.aspect` and call `camera.updateProjectionMatrix()`), so the export resolution and aspect are right.
- Text and colors: draw text onto a 2D `<canvas>` and use it as a `THREE.CanvasTexture`; set `texture.colorSpace = THREE.SRGBColorSpace`, otherwise colors come out washed out. Use `MeshBasicMaterial` for flat, exact colors; use lit materials only with lights you add yourself. Use `transparent: true` for textures with transparent areas. Don't load images or fonts from files or URLs.
- Camera params to expose (adapt to the effect): a 3D camera on/off select, start angle and end angle (degrees; 0 = flat, front-on), the turn axis (left-right, up-down), the camera distance or field of view, and when the turn starts and how long it lasts. Keep the start frame identical to the flat version when the angle is 0.
- When `t` is 0 the frame must already be a valid image, and the last frame must hold still.
- After the check script, look at frames at the start, middle and end with extreme angles: make sure nothing is cut off at the frame edge while rotated.

## effect.json

```json
{
  "name": "Wedding name card",
  "name_en": "Wedding name card",
  "category": "Titles",
  "duration": 3,
  "fps": 30,
  "params": [
    { "key": "text",  "type": "text",   "label": "Text",  "default": "Hello" },
    { "key": "font",  "type": "font",   "label": "Font",  "default": "Helvetica Neue" },
    { "key": "color", "type": "color",  "label": "Color", "default": "#FFFFFF" },
    { "key": "size",  "type": "number", "label": "Size",  "default": 120, "min": 40, "max": 300, "step": 1 },
    { "key": "style", "type": "select", "label": "Style", "default": "Fade", "options": ["Fade", "Slide"] }
  ],
  "check": { "time": 1.5, "params": { "text": "Changed", "color": "#FF5A36" } }
}
```

- `name`: shown in the effect list. `name_en` (optional) is shown instead when the app is in English.
- `category`: one of `Titles`, `Transitions`, `Particles`, `Collage`, `Split screen`, `UI` (the Chinese names 字卡, 轉場, 粒子, 拼貼, 分割 also work), or a custom category listed in `effects/_categories.json`.
- `duration` in seconds, `fps` is 30.
- `params`: each has `key`, `type`, `label` and `default`. `type` is one of:
  - `text`: a text field (can be multi-line).
  - `font`: a font family picker.
  - `color`: `#RRGGBB`.
  - `number`: a slider; needs `min`, `max` and `step`.
  - `select`: a menu; needs `options`. The selected option string is the value passed to `setParams`.
- Optional translations for the app's English mode: `label_en` on a param, and `options_en` (same order as `options`) for the menu text. The value passed to `setParams` is always the entry from `options`.
- `check` (optional) tells `tools/check-effects.mjs` which time to use for the thumbnail and which param values to switch to when testing that the frame changes. Every key in `check.params` must exist in `params`.

Params should cover everything a video editor would want to change: text, colors, font, sizes, speeds, counts. When params interact, make them work together; for example, when a box gets bigger, the text inside it should grow, move and appear with the box.

## source.md

```markdown
# <name>

## Original prompt
<the prompt or description the effect was made from>

## Source
<link, if any>

## Use it for
<what the effect is for>

## Adjustable params
<what should be adjustable>

## Notes
- <anything worth knowing: timing, how params interact, what was guessed>
```

The headings can also be in Chinese (原始 prompt, 來源, 我想用在, 要能調整的參數, 備註).

## Checking an effect

From the project folder:

```bash
node tools/check-effects.mjs <folder-name>
```

It checks that `seek` and `setParams` exist, there are no JS errors, the background is transparent and changing params changes the frame, then writes `thumb.png`. It needs Node 22+ and Google Chrome.

The script does not look at the picture. After it passes, look at the effect yourself: take screenshots with extreme params (largest and smallest values, very long text) at the start, middle and end of the animation (for example with a short node script driving headless Chrome, or Chrome's `--headless --screenshot`). Make sure nothing is clipped, nothing sticks out of its box and nothing overlaps. Fix and look again.
