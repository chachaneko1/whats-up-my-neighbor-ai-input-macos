#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
SOURCE_APP="$SCRIPT_DIR/AI語音輸入.app"
INSTALL_DIR="$HOME/Applications"
TARGET_APP="$INSTALL_DIR/AI語音輸入.app"
LAUNCH_AGENT="$HOME/Library/LaunchAgents/tw.panh.FreeVoiceType.plist"
LABEL="tw.panh.FreeVoiceType"

if [[ ! -d "$SOURCE_APP" ]]; then
  osascript -e 'display alert "找不到 AI語音輸入.app" message "請保留解壓縮後的資料夾結構，再重新執行安裝.command。" as critical'
  exit 1
fi

mkdir -p "$INSTALL_DIR" "$HOME/Library/LaunchAgents"
pkill -x FreeVoiceType 2>/dev/null || true
launchctl bootout "gui/$UID" "$LAUNCH_AGENT" 2>/dev/null || true
rm -rf "$TARGET_APP"
ditto "$SOURCE_APP" "$TARGET_APP"

/usr/libexec/PlistBuddy -c 'Clear dict' "$LAUNCH_AGENT" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :Label string $LABEL" "$LAUNCH_AGENT"
/usr/libexec/PlistBuddy -c 'Add :ProgramArguments array' "$LAUNCH_AGENT"
/usr/libexec/PlistBuddy -c 'Add :ProgramArguments:0 string /usr/bin/open' "$LAUNCH_AGENT"
/usr/libexec/PlistBuddy -c 'Add :ProgramArguments:1 string -gj' "$LAUNCH_AGENT"
/usr/libexec/PlistBuddy -c "Add :ProgramArguments:2 string $TARGET_APP" "$LAUNCH_AGENT"
/usr/libexec/PlistBuddy -c 'Add :RunAtLoad bool true' "$LAUNCH_AGENT"
plutil -lint "$LAUNCH_AGENT"
launchctl bootstrap "gui/$UID" "$LAUNCH_AGENT" 2>/dev/null || true

open "$TARGET_APP" || true
osascript -e 'display dialog "安裝完成！\n\n接下來：\n1. 依畫面建立並貼上自己的 Groq API Key\n2. 允許麥克風與輔助使用權限\n3. 預設按 ⌥↑ 開始／停止錄音\n4. 可從選單列選『設定快捷鍵…』更改" buttons {"好"} default button "好" with title "AI 語音輸入"'
