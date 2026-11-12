# Contributing / 參與貢獻

Thanks for your interest in MotionShelf! 謝謝你願意一起讓 MotionShelf 變得更好。

## Ways to help / 可以怎麼幫忙

- **Share an effect / 分享效果**: make an effect (see [effect-format.md](skills/make-effect/effect-format.md)) and share the `.mseffect` file in the community Discord, or open a pull request to add it under `effects/` if you want it to ship with the app.
- **Report a bug / 回報問題**: open an issue with the steps to reproduce, your macOS version and what you expected.
- **Suggest a feature / 功能建議**: open an issue and describe what you want to do, not only the solution.
- **Improve the code or docs / 改程式或文件**: pull requests are welcome.

## Before you open a pull request / 送出 PR 之前

1. Open an issue first for big changes, so we can agree on the direction. 大型改動請先開 issue 討論。
2. Keep the change small and focused: one purpose per pull request. 一個 PR 只做一件事。
3. Build it: `./run.sh`. If you touch effects, run `node tools/check-effects.mjs <folder-name>`. 改動後請確認可以編譯；改到效果請跑檢查腳本。
4. Describe what you changed and how you tested it. 說明你改了什麼、怎麼測的。
5. Don't commit personal data: `agent.json`, API keys, passwords, your own `effects/_inbox/`. 不要提交個人資料或金鑰。

## Effects you contribute / 你貢獻的效果

- Only submit work you made or have the right to share. 只提交你自己做的，或你有權分享的作品。
- No network calls, external scripts or hidden behavior. Effects must draw each frame from `t` alone. 不可連網、不載入外部程式碼，每一幀只由 `t` 決定。
- If you inline a library such as Three.js, keep its license header. 內嵌函式庫（例如 Three.js）時請保留授權標頭。
- By contributing, you agree your contribution is released under the project's [MIT license](LICENSE). 貢獻即表示你同意以專案的 MIT 授權釋出。

## Code of conduct / 行為準則

Please follow our [Code of Conduct](CODE_OF_CONDUCT.md). 請遵守[行為準則](CODE_OF_CONDUCT.md)。
