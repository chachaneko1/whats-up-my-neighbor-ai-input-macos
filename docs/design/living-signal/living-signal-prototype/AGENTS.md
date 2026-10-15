# Prototype Instructions

## Confirmed visual decisions

- 2026-10-14: The user wants clear hover feedback on the cat's eye controls: soft red for left/cancel and mint green for right/finish. Keep the X/check and hit areas fixed; reveal a colored tint, outline, soft glow, and concise action label on hover or keyboard focus. Only enabled controls receive this feedback. Finish means ending recording and starting recognition, not approving the transcript. Reduced motion removes the color-fade transitions.
- 2026-10-14: The user wants a flat forehead between the cat ears while quiet, without comb-like teeth or small idle waveform bars. Draw waveform bars only while listening with a nonzero signal; zero volume, ready, processing, cancelled, completion, and error states use the smooth base silhouette. Apply the same rule to state previews and exported animation.
- The selected Living Signal image establishes the overall silhouette, but this explicit quiet-state correction takes precedence over the idle bars in that earlier concept board.

Run the local server yourself and open the preview in the browser available to this environment. Do not give the user server-start instructions when you can run it.

Before making substantial visual changes, use the Product Design plugin's `get-context` skill when the visual source is unclear or no longer matches the current goal. When the user gives durable prototype-specific design feedback, preferences, or decisions, record them in `AGENTS.md`.

When implementing from a selected generated mock, treat that image as the source of truth for layout, component anatomy, density, spacing, color, typography, visible content, and hierarchy.

Build app UI in `src/`. Keep `.openai/hosting.json`, `worker/index.js`, `scripts/prepare-sites-build.mjs`, and `tests/sites-worker.test.mjs` intact so the same local prototype can be handed to Sites. Before a Sites handoff, run `npm run build` and `npm run test:sites`; the build must leave `dist/client/index.html`, `dist/server/index.js`, and `dist/.openai/hosting.json`.
