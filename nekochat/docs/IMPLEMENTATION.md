# Windows Lite MVP implementation

Baseline: main `f2e3e49` (2026-10-27). The original macOS checkout has unrelated uncommitted edits; work uses a separate branch and checkout.

## Impact and guardrails

High risk at the new authentication and global text-insertion boundaries. All changes are additive under `nekochat/`, `windows-lite/`, and a new CI workflow. Existing Swift app, Office, VPS desktop, signing, release workflows and credentials remain untouched. No import or dispatch path to Agent/remote-control messages is allowed. Incoming chat is display-only; it can never trigger recording, text insertion or commands.

## Reviewable steps

1. Versioned JSON schema and isolated FastAPI Relay, with auth/authorization/protocol and real socket tests.
2. Transparent draggable WPF cat and chat window using existing artwork/JSON; authenticated LAN/VPS settings and live delivery status.
3. Replaceable STT provider, Credential Manager, explicit global hotkey recording, guarded foreground text insertion and voice-to-chat draft. Add Windows build/package CI and manual QA instructions.

## Visual direction

Use the approved sitting black-cat silhouette at about 180px. Show a bounded plain-text bubble above its head. Clicking the bubble opens the sender's conversation; dragging moves the cat. Right click exposes chat/settings, nine coats, and exit. Connection and recording controls live in a separate normal window. Voice chat always creates an editable draft before Send. No redesign of existing macOS UI.

## Verification

Run existing appearance, remote protocol and transcription suites before changes. Verify Relay schema and authorization with TestClient plus real localhost WebSockets. Compile Windows application with .NET and run platform-independent protocol/provider tests locally; run Windows build and smoke tests on GitHub Actions. Hardware microphone, foreground insertion and visual behavior require interactive Windows QA even if CI passes.
