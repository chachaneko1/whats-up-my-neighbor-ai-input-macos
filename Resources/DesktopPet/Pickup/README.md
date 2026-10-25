# Grab / release drawings

36 complete local PNGs copied from the existing `codex/neko-mouse-interaction-preview` R6 preview (`b667869`). `timing.json` records each original source, SHA-256 and display time. 31 original drawings remain byte-identical; five Gemini drawings replace only source 09 between 08 and 10. Playback uses one complete drawing at a time, with no pixel interpolation, runtime generation or network access.

The model uses `DesktopPetLift.framePositions` / `frameTimes` for this exact sequence. Pickup takes 0.85 seconds, full release 0.80 seconds; interrupted release and re-grab retain the current drawing. The renderer decodes on demand with a 16-image / 12 MiB cache limit.

Active native playback keeps the 850ms pickup (source00..19), then plays source20..26 and the original native resting source35 for an 800ms landing (100ms per selected drawing). Source27..34 remain bundled for provenance but are excluded from playback because they add a rebound after the cat has crouched. Resting source35 keeps its original point size. Partial pickup returns and re-grabs preserve the current drawing. `playback` in timing.json defines the active sequence; the original top-level records describe all 36 unchanged source PNGs.
