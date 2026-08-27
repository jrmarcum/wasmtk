;; eh_try_table_live_local_fixture.wat — the gate for LIFTING the binaryen `-Oz` skip.
;;
;; WHY THIS EXISTS, AND WHY THE OTHER FIXTURE IS NOT ENOUGH.
;; `eh_try_table_fixture.wat` proves the pipeline PRESERVES try_table (it exits 34 through full
;; `-Oz`). It cannot see the optimiser bug that matters, because it keeps **no local live across a
;; catch edge** — and that is the only thing the bug touches. On 2026-08-25 that fixture was green
;; while `15_Exceptions` and `15_LexicalShadowing_Stress` were both silently wrong, and it was
;; trusted to authorise removing the skip. A fixture that proves a FEATURE works does not prove an
;; OPTIMISER is safe.
;;
;; THE BUG IT REPRODUCES. binaryen's EH-aware CFG models legacy `try`/`catch` INLINE handlers. In
;; `try_table` a catch clause is a BRANCH TARGET, so the edge into the handler is an ordinary branch
;; edge the legacy-shaped CFG may not walk. A local live into the handler then looks dead, and `-Oz`
;; CoalesceLocals merges it with another — which is how an inner `catch (e)` came to overwrite an
;; outer `e`.
;;
;; TWO locals must survive the edge, mirroring the two real symptoms:
;;   $keep — set BEFORE the try_table, read AFTER the catch   (the 15_LexicalShadowing shape)
;;   $il   — bound FROM the tag payload by the handler        (the 15_Exceptions shape)
;; Exit = $keep + ($il - 32) = 41 + 1 = **42**. Both operands are load-bearing: clobber either and
;; the exit code moves, so this cannot pass by accident the way a validate-only fixture can.
;;
;; HOW TO USE IT — run `deno run -A scripts/check_try_table_oz.ts`. It assembles this module once and
;; runs it BOTH pre- and post-`-Oz`; the skip in `src/wasic.ts` may be lifted only when both exit 42.
;; A pre-`-Oz` failure means the fixture or assembler broke, NOT that the optimiser is fixed.
;;
;; STATUS 2026-08-27 (binaryang 1.5.1): pre-Oz **42** ✅ / post-Oz **1** ❌ — reproduces, skip STAYS.
;; Exit 1 is the predicted signature: `$result + 1` with the 41 initialisation dropped, i.e. 0 + 1.
;; 161 bytes -> 151 after -Oz. Running `vacuum` or `dce` alone is SAFE; the offending pass is not
;; identified from our side because the compat surface does not expose `listPasses()`.

(module
  (import "wasi_snapshot_preview1" "proc_exit" (func $exit (param i32)))
  (tag $__exn_tag (param i32 i32))
  (memory (export "memory") 1)

  ;; Never returns — stands in for `divide(a, 0)`. Typed (result i32) so the caller's
  ;; `local.set` is a real assignment the optimiser can reason about.
  (func $mayThrow (result i32)
    (throw $__exn_tag (i32.const 7) (i32.const 33)))

  (func (export "_start")
    (local $result i32) (local $ip i32) (local $il i32)
    ;; pre-try initialisation — the store that must NOT be eliminated
    (local.set $result (i32.const 41))
    (block $done
      (block $h (result i32 i32)
        (try_table (catch $__exn_tag $h)
          ;; assigned INSIDE the try by a call that throws: the assignment never lands,
          ;; so the value read after the handler must still be the pre-try 41
          (local.set $result (call $mayThrow)))
        (br $done))
      ;; ---- catch edge: bind the tag payload, leave $result alone ----
      (local.set $il)
      (local.set $ip))
    (call $exit (i32.add (local.get $result) (i32.const 1)))))
