# Cloud development pilot implementation

Status: preparing; no cloud Codex execution yet. API credential entry is deferred by the user.

Scope: additive cloud runner and GitHub integration. Current app behavior, version, release scripts, credentials and cat assets remain outside generated-task scope.

Plan:
1. Pin Codex and its official API proxy. Keep the real API key in a root-only proxy; run Codex unprivileged with workspace-write sandbox and no automatic fallback.
2. Save immutable task requests, status and patches in the private GCS bucket. Enforce exact allowed paths for the pilot.
3. Run the GCP task from a GitHub workflow through workload identity. A separate credential scope publishes a Draft PR.
4. Verify that PR commit on macOS and attach a commit-specific check.
5. Use a docs-only Neko task; compare source SHA, changed paths, PR, and macOS result.

Baseline: 12 original starter fixture tests passed before integration edits. Existing macOS Build is the regression verification entry point (scripts/build.sh and scripts/test-all.sh). The additive runner/publisher currently has 22 passing offline tests; actionlint 1.7.12 reports no workflow errors.

Risk: high at the authentication/workflow boundary, within the user's requested integration scope. GitHub write credentials never enter the model job; publisher never executes generated code. No main merge or release is part of this pilot.

Unverified: Cloud Run sandbox support and proxy runtime, GCP billing and IAM, actual model execution and shutdown continuation. These require the staged cloud run; a local fixture is not a substitute.

New local tooling is confined to ignored tools/cloud-agent/.dependencies/: npm Codex/proxy 0.163.0 for CLI inspection and the official actionlint 1.7.12 Darwin ARM64 release with its published SHA-256 verified. They are not uploaded in the cloud build context.
