# Phase 1D-1 — AI Response Diagnostics Retention

## Delivered

This slice adds safe persisted diagnostics for AI responses without storing raw student content by default.

Persisted on `AnalysisResult.responseDiagnostics`:

- response length
- short SHA-256 fingerprint
- Markdown-envelope flag
- JSON repair strategy
- capture timestamp
- optional raw response
- optional raw-response retention window

## Default behavior

Raw model output is **not** persisted by default. Newly parsed analysis results store only the safe summary fields above. This keeps the existing privacy posture while making bug reports traceable through a stable fingerprint.

## Controlled raw retention

`AiAnalysisService` recognizes these settings keys:

- `ai_diagnostics_raw_response_enabled`
- `ai_diagnostics_raw_retention_days`

When raw retention is enabled explicitly, the raw response can be attached to diagnostics with a bounded retention window. The current clamp is 1–30 days, defaulting to 7 days.

## Cleanup support

`AiResponseDiagnosticsRetentionService` can:

- strip all raw responses while preserving safe summaries
- expire raw responses based on `capturedAt + retentionDays`
- process main question analysis and candidate analysis snapshots

## Guardrails

- Diagnostics never store API keys, request headers, or provider credentials.
- Default persisted JSON contains no raw model output.
- Raw cleanup does not remove fingerprints, lengths, or repair metadata.
- Legacy records without diagnostics remain valid.

## Deferred

- Settings UI toggle for raw retention
- Data management button to clear diagnostics
- Dedicated diagnostics export screen
- Provider-specific request/response correlation IDs
- Raw extraction diagnostics for OCR responses
