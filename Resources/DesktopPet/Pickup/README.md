# Grab / release drawings

36 complete local PNGs copied from the existing `codex/neko-mouse-interaction-preview` R6 preview (`b667869`). `timing.json` records each original source, SHA-256 and display time. 31 original drawings remain byte-identical; five Gemini drawings replace only source 09 between 08 and 10. Playback uses one complete drawing at a time, with no pixel interpolation, runtime generation or network access.

The model uses `DesktopPetLift.framePositions` / `frameTimes` for this exact sequence. Pickup takes 0.85 seconds, full release 0.80 seconds; interrupted release and re-grab retain the current drawing. The renderer decodes on demand with a 16-image / 12 MiB cache limit.
