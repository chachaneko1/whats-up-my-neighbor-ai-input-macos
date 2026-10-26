# MVP validation — 2026-10-27

Base: `f2e3e49`. Independent branch `codex/nekochat-windows-lite`. Existing macOS checkout edits preserved; no changes to existing Swift app, Office, VPS configuration, release or production deployment.

## Local evidence (macOS arm64)

- Existing remote protocol suite: passed.
- Existing appearance suite: **1,056 checks passed**, nine coats and existing native renders.
- Existing transcription client suite: passed.
- New C# core: **48 behavior checks passed** (protocol rejection, Unicode limits, endpoint restrictions, nine original JSON appearances, overrides, Groq request/response using a mock HTTP handler).
- New Python Relay: **26 tests passed**, including real TCP WebSocket round-trip/reconnect and actual C# transport ↔ FastAPI delivery/ack (**50** C# checks in that integrated run). No real Groq API call or key used.
- WPF cross-build with .NET 10: passed, zero warnings/errors. This proves compile/XAML generation only, not Windows runtime behavior.
- Native assets generated using original Swift renderer, anatomy and tabby masks. No source artwork edits.

Windows CI and interactive QA results will be recorded after the first PR run. Interactive Windows microphone/focus/DPI/LAN tests are pending. macOS NekoChat App integration is not implemented; the existing macOS app is unchanged. No VPS Relay deployment has been performed.

One local dependency warning: Starlette TestClient deprecates httpx in favor of httpx2; the tested compatibility path still passes. Live WebSocket tests use Uvicorn websockets-sansio.
