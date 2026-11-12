---
name: make-effect
description: Turn a motion prompt, a description or a reference animation into a MotionShelf effect (a parameterized HTML animation with a transparent background that MotionShelf previews and exports as ProRes 4444). Use when the user wants a new MotionShelf effect, wants to split a long motion prompt into several effects, or wants to change or add params to an existing effect.
---

# Make a MotionShelf effect

MotionShelf is a macOS app that lists the effects in its project's `effects/` folder, lets you tweak their params, previews them and exports transparent ProRes 4444 clips for video editors such as DaVinci Resolve.

## 1. Find the project folder

Work in the MotionShelf project folder: the one that contains `effects/`, `tools/check-effects.mjs` and `Package.swift`. If the current directory isn't it, look for `~/MotionShelf`, otherwise ask the user where their MotionShelf folder is.

## 2. Read the format

Read [effect-format.md](effect-format.md) in this skill's folder before writing anything. `effects/title-card` in the project is a complete example.

## 3. Decide how many effects

A long prompt often describes several animations. Split it into effects that can each be layered over a video on their own: every UI element, every transition and every title card is one effect; consecutive moves of the same element (a button pressing down and springing back) stay together. Tell the user the list before building if it's longer than three.

If the prompt asks for research, real product screens, music or a final MP4, build only the visual effects: MotionShelf can't go online and exports silent clips. Use generic, editable content and make every text, color and logo a param, then say so in `source.md` and in your report.

## 4. Build each effect

For each effect:

1. Create `effects/<folder-name>/` with `effect.html`, `effect.json` and `source.md` following the format. Put the original prompt in `source.md`; when the effect is one item of a split, note which item it is, quoting that item's text.
2. Run `node tools/check-effects.mjs <folder-name>` from the project folder. Fix and rerun until it passes. If the same effect fails twice, stop and explain why in your report.
3. Look at the frames yourself as described at the end of the format, with extreme params, and fix anything clipped, overlapping or sticking out.

Only touch the new effect folders (or the one effect you were asked to change). Don't install packages or go online.

## 5. Report

List each effect: folder name, name, category and length, plus anything that failed and why, and anything you had to guess.
