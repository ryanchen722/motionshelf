# Security / 資安

## What to know / 先知道的事

An effect is web code that runs inside MotionShelf. MotionShelf checks every imported `.mseffect` file and blocks network access while previewing and exporting, but these checks **cannot guarantee safety**. Only import effects from people you trust.
效果是在 MotionShelf 裡執行的網頁程式碼。App 匯入前會檢查，預覽和輸出時也會封鎖網路，但**不能保證 100% 安全**，只匯入你信任的人給的效果。

## Reporting a vulnerability / 回報漏洞

Please report privately and do not post details in public issues or the Discord:
請私下回報，不要把細節貼在公開的 issue 或 Discord：

- Use GitHub's **Security → Report a vulnerability** on this repository (private reporting).
  使用本專案 GitHub 的 **Security → Report a vulnerability**（私下回報）。
- If that isn't available, open a private conversation with a maintainer on Discord.
  如果無法使用，可以在 Discord 私訊維護者。

Useful details: the MotionShelf version, macOS version, steps to reproduce, and the effect file if it is involved (please don't run it on your main data).
請附上：MotionShelf 版本、macOS 版本、重現步驟，如果和某個效果有關也附上效果檔（請不要在重要資料的環境裡執行它）。

## Reporting a malicious effect / 回報惡意效果

If someone shares an effect that tries to send data out, load remote code or trick users, tell a maintainer privately. It will be removed and the author banned.
如果有人分享會把資料傳出去、載入遠端程式碼或誤導使用者的效果，請私下告訴維護者，我們會移除並將作者永久移出。

## Supported versions / 支援的版本

Only the latest version on the default branch receives fixes. 只修復預設分支上的最新版本。
