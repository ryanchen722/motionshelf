---
name: process-inbox
description: Process the MotionShelf inbox — turn every saved motion prompt in effects/_inbox/ into MotionShelf effects, then mark each one done. Use when the user asks to process, generate or build the MotionShelf inbox. MotionShelf's "Generate All" button runs this too.
---

# Process the MotionShelf inbox

The MotionShelf app saves motion prompts the user collects into `effects/_inbox/<item>/source.md`. Your job is to turn every item into one or more effects.

## Steps

1. Work in the MotionShelf project folder (the one that contains `effects/`, `tools/check-effects.mjs` and `Package.swift`). If the current directory isn't it, look for `~/MotionShelf`, otherwise ask the user.
2. Read [effect-format.md](../make-effect/effect-format.md) and follow the steps in [make-effect](../make-effect/SKILL.md) for building and checking effects.
3. For each folder in `effects/_inbox/` that has no `DONE` file:
   - Read its `source.md`: the original prompt, source, what it's for, which params should be adjustable, and maybe a breakdown list (`## Breakdown` or `## 拆分清單`).
   - With a breakdown list, make one effect per item in the list and nothing else. Without one, decide how to split the prompt yourself.
   - Every point under "Adjustable params" (`## Adjustable params` / `## 要能調整的參數`) becomes a param.
   - Copy the inbox `source.md` into each new effect's folder and add a note that it was made by MotionShelf. For a split item, add `This is item N of the breakdown: <that item's text, copied from the breakdown list>`. Only copy text from the breakdown list, not from other numbered parts of the prompt.
4. When every effect from an item is built and passes the check, create a `DONE` file in that inbox folder listing the effect folder names, one per line. MotionShelf moves finished items to the Trash itself, so don't move or delete inbox folders. Don't create `DONE` for an item that failed.

## Limits

Only create new effect folders and `DONE` files. Don't change existing effects or the app's source code, don't install packages and don't go online.

## Report

A few lines: how many effects each item became, each effect's folder name, name, category and length, and anything that failed and why.
