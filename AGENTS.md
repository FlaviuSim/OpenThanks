# AGENTS.md

## Cursor Cloud specific instructions

This repo is primarily a **native Apple app** (iOS/watchOS SwiftUI + widget/share
extensions) generated from `project.yml` via XcodeGen, plus a **Supabase backend**
(SQL migrations + one Deno edge function), a Python asset generator, and static
Store/AASA assets. See `README.md` for the product overview and the macOS build flow.

### Platform reality (important)

- The Cloud VM is **Linux with no macOS/Xcode/iOS SDK**. The Swift targets
  (`OpenThanks`, `OpenThanksWidget`, `OpenThanksShare`, `OpenThanksWatch`,
  `OpenThanksWatchWidgets`, `OpenThanksShared`) **cannot be built, run, or
  simulated here** — that requires a Mac with Xcode 16+ (`xcodebuild` /
  `xcrun simctl`) as documented in `README.md`. Do not attempt to build the
  `.xcodeproj` on the VM.
- Only the **backend + tooling** components run on Linux (details below).

### What runs on Linux

Component | How to run | Notes
--- | --- | ---
`scripts/generate_appstore_assets.py` | `.venv/bin/python scripts/generate_appstore_assets.py` (run from repo root) | Regenerates App Store icons + screenshots into `OpenThanks/Assets.xcassets/...` and `AppStore/...`. Pillow is installed into `.venv` by the update script. On Linux the font loader falls back to a bundled default font (the macOS Georgia/Arial paths it prefers don't exist), so generated text is thinner/smaller than the committed macOS assets — **do not commit Linux-regenerated assets** unless intended.
`supabase/functions/send-apns/index.ts` | Serve: `SUPABASE_SERVICE_ROLE_KEY=... deno run --allow-net --allow-env supabase/functions/send-apns/index.ts` (listens on `:8000`). Lint: `deno lint supabase/functions/send-apns/`. | Deno is installed to `~/.deno` by the update script; invoke it as `~/.deno/bin/deno` (the installer also adds it to PATH in `~/.bashrc` for new login shells). Full push delivery needs real APNs `.p8` secrets (`APNS_KEY`, `APNS_KEY_ID`, `APNS_TEAM_ID`) + a live device token, so it can't be end-to-end verified without Apple infra; the auth/target/compose logic paths run fine locally.

### Gotchas

- `deno check supabase/functions/send-apns/index.ts` reports a **`TS2345` type
  error** (`"public"` vs `never`) coming from the pinned `esm.sh` `supabase-js`
  generics — this is a third-party typings mismatch, **not** a bug in this repo.
  Supabase's `functions deploy` / Deno Deploy runtime does not run this strict
  `tsc` check, and `deno lint` passes. Don't "fix" it by editing the function.
- **Local full Supabase stack is not reproducible from this repo alone.** The
  migrations in `supabase/migrations/` are **incremental against the live
  schema** — they `alter table public.gratitudes ...`, `references
  public.profiles(id)`, etc. The base tables (`profiles`, `gratitudes`,
  `hearts`, `notifications`) are defined in the separate web-app / live Supabase
  project (see `README.md` "Related repos"), **not here**, so `supabase db
  reset` cannot apply these migrations cleanly without that base schema first.
- The Supabase MCP server (`.cursor/settings.json`) is the intended way to
  inspect/query the live `open-thanks` project rather than standing up a local DB.
