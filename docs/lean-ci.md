# Lean CI

This repository uses a lightweight regression guard before changes enter `main`.

The guard intentionally checks only stable contracts:

- critical Admin / Partner / Staff application entry points still exist
- core voucher database contracts remain present
- stale-voucher cleanup still uses the unified cleanup engine
- redemption history remains visibly protected by cleanup
- browser-delivered HTML/JS does not contain an obvious Supabase service-role secret
- critical HTML entry points remain structurally complete

It does **not** lock UI text, layout, voucher types, Partner names, or other normal upgrade surfaces.

Run locally with:

```bash
bash scripts/lean-ci-selfcheck.sh
```

The GitHub Actions workflow runs on pull requests targeting `main` and on pushes to `main`. It does not connect to or mutate Production Supabase.
