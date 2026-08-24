;; eh_try_table_fixture.wat — the EH migration's acceptance test.
;;
;; This is the exact shape wasic must emit once the legacy `try` migration lands. It is NESTED and
;; exercises BOTH required forms in one module:
;;   - (catch $__exn_tag $h)              — the try/catch shape; tag params arrive as block results
;;   - (catch_all_ref $h) + (throw_ref)   — the try/finally shape, replacing legacy (rethrow 0)
;;
;; WHY IT EXITS 34, and why that number is the whole point: 33 is the thrown tag's second param,
;; caught by the OUTER handler; 1 is the global set by the inner `finally` body. Exit 34 therefore
;; proves the catch handler bound the tag params correctly AND the finally body ran BEFORE the
;; exception propagated outward. A fixture that merely *validates* proves nothing — that is the trap
;; the binaryen-ts team hit with a malformed hand-built fixture (see scripts/binaryen-ts-report.md).
;;
;; STATUS 2026-08-24:
;;   wasmtime 47.0.3, no -W flags ........ exit 34  ✅ (target shape confirmed good)
;;   wasmtime -W exceptions=y ............ exit 34  ✅
;;   through wasic's own pipeline ........ ⛔ BLOCKED — wabt-ts 1.3.5 cannot ENCODE any try_table
;;                                          with a handler clause (parses fine, dies in the binary
;;                                          writer). See cmem/compiler-bugs.md.
;;
;; RECHECK WHEN **wabt-ts 1.4.0** SHIPS (owner, 2026-08-24) — the gate on the whole migration:
;;   wasmtime scripts/eh_try_table_fixture.wat            # expect exit 34 (sanity)
;;   then assemble it through wabt-ts + binaryen -Oz (wasic's watToOptimisedWasm path) and run the
;;   RESULT under wasmtime. Exit 34 there means the pipeline preserves try_table end-to-end and the
;;   migration is unblocked. Anything else means it is not, regardless of what the release notes say.

(module
  (import "wasi_snapshot_preview1" "proc_exit" (func $exit (param i32)))
  (tag $__exn_tag (param i32 i32))
  (global $ran (mut i32) (i32.const 0))
  (memory (export "memory") 1)
  (func $mayThrow
    (throw $__exn_tag (i32.const 7) (i32.const 33)))
  (func (export "_start")
    (local $p i32) (local $l i32)
    (block $outer_done
      (block $outer_h (result i32 i32)
        (try_table (catch $__exn_tag $outer_h)
          (block $inner_done
            (block $inner_h (result exnref)
              (try_table (catch_all_ref $inner_h)
                (call $mayThrow))
              (br $inner_done))
            (global.set $ran (i32.const 1))
            (throw_ref)))
        (br $outer_done))
      (local.set $l)
      (local.set $p)
      (call $exit (i32.add (local.get $l) (global.get $ran))))))
