#!/bin/zsh
set -euo pipefail

LAUNCH_AGENT="$HOME/Library/LaunchAgents/tw.panh.FreeVoiceType.plist"

pkill -x FreeVoiceType 2>/dev/null || true
launchctl bootout "gui/$UID" "$LAUNCH_AGENT" 2>/dev/null || true
rm -rf "$HOME/Applications/AI語音輸入.app"
rm -f "$LAUNCH_AGENT"
rm -rf "$HOME/Library/Application Support/AI語音輸入/ClipboardHistory"
defaults delete tw.panh.FreeVoiceType 2>/dev/null || true
security delete-generic-password -s tw.panh.FreeVoiceType.groq -a api-key >/dev/null 2>&1 || true

osascript -e 'display alert "已完整移除 AI 語音輸入" message "App、登入啟動設定、快捷鍵偏好、剪貼簿歷史與鑰匙圈中的 Groq API Key 都已刪除。"'
