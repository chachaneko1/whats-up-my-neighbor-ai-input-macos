# docs/media

README 與 [完整使用指南](../GUIDE.md) 用的圖片。

## 示範動畫

兩張都是 1.4.4 原始碼在離線測試中輸出的實際繪圖（`./scripts/test-cat.sh`、`./scripts/test-desktop-pet.sh` 產生於 `build/cat-render/`），用 ffmpeg 轉成 GIF，不是螢幕錄影。

| 檔案 | 來源 |
|---|---|
| `greeting.gif` | `build/cat-render/greeting-frame-00…29.png`，10 fps，寬 440px |
| `desktop-pet-walking.gif` | `build/cat-render/desktop-pet/walking-cycle/right-0…15.png`，12 fps，放大到 256px |

貓咪造型改版時，重跑上述測試並重新產生 GIF。

## 品牌標誌（`brand/`）

從官方網站 repo `yuipan0611/nekonode-site` 的 `55653c822c52d2c7b04364eb72ff3ec42ab020e8` 原檔複製，未修改。

| 檔案 | 網站原路徑 | 用途 | SHA-256 |
|---|---|---|---|
| `neko-round-face.svg` | `public/images/neko-round-face.svg` | 官網頁首的品牌標誌，README 淺色模式 Logo | `849015a6e378c31337abf5b235d94b3e915ea18137d88d4052e8bc173120abfd` |
| `app-icon.svg` | `public/favicon.svg` | 核准的白底 App 圖示，README 深色模式 Logo（黑貓臉在深色背景看不見） | `c47124e3f4fccea1a0b81f83490946c31b826c5201327902c5036b97150d1b4e` |

兩者都來自 macOS 圖示分支 `dd434cc` 的 `Resources/AppIcon.svg`，詳見網站 repo 的 `public/images/brands/README.md`。不要修改圖形；官網換標誌時一起更新。

## 操作畫面（`screenshots/`）

| 檔案 | 來源 | SHA-256 |
|---|---|---|
| `recording-hud.png` | 網站 `public/images/guide/recording-hud.png`（同一 commit） | `929c7d89202586be84ea474c6b6754998dde650963947b52bc979b923d8aa698` |
| `desktop-pet-poses.png` | 網站 `public/images/guide/desktop-pet-poses.png` | `fead2039a29328304523abf94ec07fed1d3b78e0a3d9889a0c8385a9524973bd` |
| `desktop-pet-interaction.png` | 網站 `public/images/guide/desktop-pet-interaction.png` | `fd2637eaf444ce19eaec367f8e6bade404ec793a8aed48c1036dc0f7bfe2278b` |

App 改版讓畫面不同時，網站與這裡一起更新。
