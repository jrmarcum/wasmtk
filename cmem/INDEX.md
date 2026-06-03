# cmem — Portable Project Memory for wasmtk

This folder is the **authoritative, portable project memory** for `wasmtk`. It lives inside
the project tree, so it travels with the project on the USB drive (and is committed to git,
unlike the legacy `CLAUDE.md`, which is `.gitignore`d and therefore machine-local only).

**Format:** plain Markdown — one focused topic file per domain, so any single concern can be
reviewed and revised without wading through one giant file. Keep files small and single-topic.

## Policy (durable — set by the project owner 2026-05-31)

- **`cmem/` is the single home for ALL project memory.** When the owner (or anyone) says
  "**update the project memory**," that means: update the matching `cmem/` topic file with the
  latest decisions, found bugs, design changes, and current state — then add/refresh its one-line
  pointer in the table below. Convert relative dates to absolute; update existing entries rather
  than duplicating.
- **`VISION.md` and `wasmtk-stdlib-bundling-brief.md` were merged into `cmem/`** (now `vision.md`
  and `stdlib-bundling-brief.md`, 2026-05-31) so nothing authoritative lives outside this folder.
- **`README.md` is NOT project memory.** It is the public, user-facing document shipped to GitHub
  and JSR — a concise-but-complete guide to *using* the wasmtk module system (what it is, install,
  per-tool usage, capability surface, worked examples). Keep it as descriptive/verbose as a user
  needs to get full benefit; do NOT mix internal decision logs / bug post-mortems into it.
- The legacy `CLAUDE.md` (repo root, gitignored, machine-local) is the auto-loaded historical
  archive only; `cmem/` supersedes it as the source of truth.

### The "update the project memory" trigger (binding on every agent)

When the owner says **"update the project memory"** (or any clear synonym — "update memory",
"record this", "remember this for the project"), the required action is BOTH of:

1. **Revise all relevant `cmem/` files** — fold the latest decisions, found bugs, design changes,
   and current state into the matching topic file(s); refresh the one-line pointer in the Files
   table; convert relative dates to absolute; update existing entries instead of duplicating.
2. **Sync `README.md` where, and only where, the change is user-relevant** — i.e. update the
   user-facing capability surface, install/usage, examples, and status so the README *matches* the
   new reality. Keep README user-facing: do NOT copy internal decision logs / bug post-mortems into
   it (those live in `cmem/` only). README "matches" the memory on the user-visible facts, not by
   absorbing the internal detail.

This is the durable contract for this repo. Any agent reading this file is expected to honor it.

## Files

| File | What it holds |
| --- | --- |
| [overview.md](overview.md) | What wasmtk is, repo layout, the key source files |
| [architecture.md](architecture.md) | wasic / modc / bindgen / hybrid; pluggable wabt+binaryen backends; build & merge pipeline; Canonical ABI **partial-alignment** accuracy note |
| [polyglot-producers.md](polyglot-producers.md) | **Goal — one congruent polyglot wasm capability** (TS/JS+C+C+++Rust+Zig producers → shared P1-core/bindgen/binaryen-ts/wasmmerge/host back end); WASI-P1 scope pin (componentize as terminal wrap); **VERIFIED 2026-06-03 wasmtk is NOT a P2 producer** (P1 core + sidecar WIT + host-side ABI); **DECISION: forward-align the ABI to canonical while staying P1**; path to a real P2 producer; **ADR — C/C++ via the Zig toolchain, not a TS emscripten reimpl** |
| [capabilities.md](capabilities.md) | Stage 0.7 Tier-1 stdlib capability libraries: Set, Map, Date, JSON, RegExp (shared-heap / leaf via wasmbundle); + virtual `wasmtk:<cap>` imports & feature-level tree-shake (brief §7-#4) |
| [compiler-bugs.md](compiler-bugs.md) | Live bug log — **no open bugs**; the single-physical-line brace `if {…}` form fixed 2026-06-03 (split single-line bodies + string-aware `splitStmts`; suite now 279/279), the 7 long-standing failures fixed 2026-06-02 (value-fallthru + wabt-ts 1.3.1 hex-float), the merge OOB-charCodeAt trap fixed 2026-06-02 (short-circuit `&&`/`||`) |
| [design-decisions.md](design-decisions.md) | Load-bearing invariants and codegen rules that must not be silently reverted |
| [testing.md](testing.md) | How to run the suites, the test populations, current pass counts, the CI / pre-publish gate (`deno publish` + fmt/lint/tests), naming conventions |
| [roadmap.md](roadmap.md) | Phase status + **prioritized execution order (set 2026-06-03)**: Phase 51 language hardening (`instanceof` → object spread → param/nested destructuring → utility types) gates the #5 async + own-runtime tracks; Phase 52 leaf conveniences + Phase 53 standalone built-ins are ungated; ecosystem loader is orthogonal. Links to the two long-form docs below |
| [vision.md](vision.md) | **Full** polyglot ecosystem vision + "TypeScript as a DLL" vision: guiding decisions, layer diagram, language-support matrix, staged roadmap, repo map (moved from root `VISION.md`, 2026-05-31) |
| [stdlib-bundling-brief.md](stdlib-bundling-brief.md) | **Full** on-demand stdlib bundling design brief (§1–§7d): rationale, allocator unification, the two linking regimes, feature tiering, Javy-independence verdict, work items, per-capability + merge-bug post-mortems (moved from root, 2026-05-31) |

## Long-form docs are now inside cmem

`vision.md` and `stdlib-bundling-brief.md` were full design documents at the repo root; they were
moved into `cmem/` (2026-05-31) so all project memory has a single home. `roadmap.md` summarizes
both and links to them.

## Related files outside cmem

- `README.md` — the **public, user-facing** doc shipped to GitHub/JSR (install, per-tool usage,
  capability surface, examples). NOT project memory; curated for end users — keep internal
  decision logs / bug post-mortems out of it (those belong here).
- `CLAUDE.md` — legacy exhaustive memory archive (repo root, gitignored, machine-local; auto-loaded
  by Claude Code). Superseded by cmem as the source of truth.
