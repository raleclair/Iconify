# Iconify Roadmap

## Phase 1: Stability and Safety (Implemented)
- Rewrite CLI parsing with strict value checks and optional `--restore-backup` file argument support.
- Validate output format and icon sizes before running conversions.
- Add dependency preflight checks for ImageMagick and icon-cache tools.
- Make privilege checks conditional (only required when destination is not writable and not in dry-run mode).
- Improve logging initialization and add custom `--log-file` support.

## Phase 2: UX and Documentation
- Reorganize help output by functional sections (input/output/processing/cache/localization).
- Expand README with consistent fenced command examples and troubleshooting guidance.
- Add richer run summaries (counts for generated, skipped, failed files).

## Phase 3: Versatility

- Add icon selection controls (specific names or `all`) and installed-icon verification output.
- Add import/export workflows for icon repositories and generated icon groups.
- Add destination/profile controls for choosing installation targets without requiring script edits.
- Add recursive source scanning and optional directory structure preservation.
- Support selectable icon categories and theme names.
- Add an optional interactive wizard mode while preserving non-interactive CLI behavior.

## Phase 4: Quality and Automation
- Add `shellcheck`, `shfmt`, and unit/integration tests (e.g., `bats`).
- Add CI to enforce lint/tests on pull requests.
- Add locale consistency checks to ensure all translation keys exist.
