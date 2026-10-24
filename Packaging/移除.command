#!/bin/zsh
set -euo pipefail

PROFILE_ROOT="$HOME"
TEST_MODE=0
if [[ -n "${NEKO_UNINSTALL_TEST_PROFILE:-}" ]]; then
  # Disposable-profile regression tests never stop apps, change login jobs,
  # touch preferences or Keychain, display UI or use the real user's profile.
  [[ "$NEKO_UNINSTALL_TEST_PROFILE" == /* && "${NEKO_UNINSTALL_TEST_PROFILE:A}" != "${HOME:A}" ]] || exit 1
  PROFILE_ROOT="$NEKO_UNINSTALL_TEST_PROFILE"
  TEST_MODE=1
fi
SHOW_DIALOGS=1
if (( TEST_MODE )) || [[ "${NEKO_INSTALL_NO_DIALOG:-}" == 1 ]]; then SHOW_DIALOGS=0; fi
LABEL="tw.panh.FreeVoiceType"
LAUNCH_AGENT="$PROFILE_ROOT/Library/LaunchAgents/$LABEL.plist"
# Clipboard history (ClipboardHistory/) and installer backups live next to the
# early-version app here; only the app itself is removed.
APP_DATA="$PROFILE_ROOT/Library/Application Support/AI語音輸入"
CAT_SETTINGS="$PROFILE_ROOT/Library/Application Support/$LABEL"

is_neighbor_app() {
  [[ -d "$1" && "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$1/Contents/Info.plist" 2>/dev/null)" == "$LABEL" ]]
}

# Same locations, in the same order, as 安裝.command. Unlike the installer,
# every copy found is removed, and only after its bundle ID matches.
typeset -aU CANDIDATES
if [[ -f "$LAUNCH_AGENT" ]]; then
  REGISTERED="$(/usr/libexec/PlistBuddy -c 'Print :ProgramArguments:2' "$LAUNCH_AGENT" 2>/dev/null || true)"
  if [[ "$REGISTERED" == /*.app && ( "$TEST_MODE" == 0 || "$REGISTERED" == "$PROFILE_ROOT"/* ) ]]; then
    CANDIDATES+=("$REGISTERED")
  fi
fi
CANDIDATES+=("$PROFILE_ROOT/Applications/AI語音輸入.app" "$APP_DATA/AI語音輸入.app")
if (( ! TEST_MODE )); then CANDIDATES+=("/Applications/AI語音輸入.app"); fi

if (( ! TEST_MODE )); then
  pkill -x FreeVoiceType 2>/dev/null || true
  launchctl bootout "gui/$UID" "$LAUNCH_AGENT" 2>/dev/null || true
fi
REMOVED=()
SKIPPED=()
FAILED=()
for app in "${CANDIDATES[@]}"; do
  [[ -e "$app" ]] || continue
  if ! is_neighbor_app "$app"; then
    SKIPPED+=("$app")
  elif rm -rf "$app"; then
    REMOVED+=("$app")
  else
    FAILED+=("$app")
  fi
done
rm -f "$LAUNCH_AGENT"
if (( ! TEST_MODE )); then
  defaults delete "$LABEL" 2>/dev/null || true
  security delete-generic-password -s "$LABEL.groq" -a api-key >/dev/null 2>&1 || true
fi

# User data and the previous-version backups made by 安裝.command are listed
# but kept; deleting them is the user's call.
typeset -aU KEPT
if [[ -e "$APP_DATA/ClipboardHistory" ]]; then KEPT+=("$APP_DATA/ClipboardHistory"); fi
if [[ -e "$CAT_SETTINGS" ]]; then KEPT+=("$CAT_SETTINGS"); fi
for app in "${CANDIDATES[@]}"; do KEPT+=("${app:h}"/.neighbor-update.*(N)); done

for app in "${REMOVED[@]}"; do print -r -- "已刪除 App：$app"; done
for app in "${SKIPPED[@]}"; do print -r -- "略過（Bundle ID 不是 $LABEL）：$app"; done
for app in "${FAILED[@]}"; do print -u2 -r -- "無法刪除，請手動移到垃圾桶：$app"; done
if (( ! ${#REMOVED[@]} && ! ${#FAILED[@]} )); then print -r -- "沒有找到已安裝的 App。"; fi
for item in "${KEPT[@]}"; do print -r -- "保留（需要時請手動刪除）：$item"; done

if (( ${#FAILED[@]} )); then
  TITLE="移除未完成"
  MESSAGE="有 App 無法刪除，請照終端機視窗列出的位置手動移到垃圾桶。"
else
  TITLE="已移除 AI 語音輸入"
  MESSAGE="App、登入啟動設定、偏好設定（含快捷鍵與本機詞典）與鑰匙圈中的 Groq API Key 都已刪除。"
fi
if (( ${#KEPT[@]} )); then MESSAGE+=$'\n\n剪貼簿歷史、貓咪設定與舊版備份沒有刪除，位置列在終端機視窗。'; fi
if (( SHOW_DIALOGS )); then
  osascript -e 'on run argv' -e 'display alert (item 1 of argv) message (item 2 of argv) giving up after 120' -e 'end run' "$TITLE" "$MESSAGE" >/dev/null || true
fi
if (( ${#FAILED[@]} )); then exit 1; fi
