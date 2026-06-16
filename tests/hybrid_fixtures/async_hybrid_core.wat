(module
  (memory (export "memory") 2)
  (global $__heap_ptr (mut i32) (i32.const 260))
  (global $__mt_head (mut i32) (i32.const 0))
  (global $__mt_tail (mut i32) (i32.const 0))
  (type $ftype_i32_i32_i32_r_void (func (param i32) (param i32) (param i32)))
  ;; Bump allocator — advances __heap_ptr and returns the old value
  (func $__malloc (param $size i32) (result i32)
    (local $ptr i32)
    (local.set $ptr (global.get $__heap_ptr))
    (global.set $__heap_ptr (i32.add (local.get $ptr) (local.get $size)))
    (local.get $ptr)
  )
  ;; Canonical ABI allocator — fresh allocation (ptr==0) delegates to $__malloc;
  ;; realloc requests (ptr!=0) return ptr unchanged (bump allocator has no free).
  (func $cabi_realloc (param $ptr i32) (param $old_size i32) (param $align i32) (param $new_size i32) (result i32)
    (select
      (call $__malloc (local.get $new_size))
      (local.get $ptr)
      (i32.eqz (local.get $ptr))
    )
  )
  ;; ---- Promise runtime (Phase 13.1, #13 async) ----
  (func $__promise_alloc (result i32)
    (call $__malloc (i32.const 32)))
  (func $__promise_resolve_i32 (param $v i32) (result i32)
    (local $p i32)
    (local.set $p (call $__promise_alloc))
    (i32.store (local.get $p) (i32.const 1))
    (i32.store offset=16 (local.get $p) (local.get $v))
    (local.get $p))
  (func $__promise_resolve_f64 (param $v f64) (result i32)
    (local $p i32)
    (local.set $p (call $__promise_alloc))
    (i32.store (local.get $p) (i32.const 1))
    (i32.store offset=4 (local.get $p) (i32.const 1))
    (f64.store offset=16 (local.get $p) (local.get $v))
    (local.get $p))
  (func $__promise_await_i32 (param $p i32) (result i32)
    (call $__drain_microtasks)
    (if (i32.eqz (i32.load (local.get $p))) (then (call $__on_quiescent)))
    (i32.load offset=16 (local.get $p)))
  (func $__promise_await_f64 (param $p i32) (result f64)
    (call $__drain_microtasks)
    (if (i32.eqz (i32.load (local.get $p))) (then (call $__on_quiescent)))
    (f64.load offset=16 (local.get $p)))
  (func $__on_quiescent (unreachable))
  ;; ---- Microtask queue (Phase 13.2 / 13.1b) ----
  ;; FIFO linked list of reaction records (20 B): [tramp_idx@0 | env@4 | src@8 | result@12 | next@16].
  ;; env is the capturing-closure struct ptr (0 for a named callback). $__mt_head / $__mt_tail are
  ;; module globals (emitted in the globals section).
  (func $__promise_enqueue (param $tramp i32) (param $env i32) (param $src i32) (param $result i32)
    (local $r i32)
    (local.set $r (call $__malloc (i32.const 20)))
    (i32.store (local.get $r) (local.get $tramp))
    (i32.store offset=4 (local.get $r) (local.get $env))
    (i32.store offset=8 (local.get $r) (local.get $src))
    (i32.store offset=12 (local.get $r) (local.get $result))
    (i32.store offset=16 (local.get $r) (i32.const 0))
    (if (i32.eqz (global.get $__mt_head))
      (then
        (global.set $__mt_head (local.get $r))
        (global.set $__mt_tail (local.get $r)))
      (else
        (i32.store offset=16 (global.get $__mt_tail) (local.get $r))
        (global.set $__mt_tail (local.get $r)))))
  ;; Register a reaction: alloc a pending result promise, enqueue the reaction (src is settled
  ;; under the eager model), and return the result promise. tramp = funcref table index; env =
  ;; closure struct ptr (0 if the callback is a named function).
  (func $__promise_then (param $src i32) (param $tramp i32) (param $env i32) (result i32)
    (local $result i32)
    (local.set $result (call $__promise_alloc))
    (call $__promise_enqueue (local.get $tramp) (local.get $env) (local.get $src) (local.get $result))
    (local.get $result))
  ;; Run queued microtasks FIFO until empty. A reaction may enqueue more (chained .then) — they
  ;; append to the tail and run in this same loop. Each trampoline has type (env,src,result)->void.
  (func $__drain_microtasks
    (local $cur i32)
    (block $done
      (loop $L
        (br_if $done (i32.eqz (global.get $__mt_head)))
        (local.set $cur (global.get $__mt_head))
        (global.set $__mt_head (i32.load offset=16 (local.get $cur)))
        (if (i32.eqz (global.get $__mt_head)) (then (global.set $__mt_tail (i32.const 0))))
        (call_indirect (type $ftype_i32_i32_i32_r_void)
          (i32.load offset=4 (local.get $cur))
          (i32.load offset=8 (local.get $cur))
          (i32.load offset=12 (local.get $cur))
          (i32.load (local.get $cur)))
        (br $L))))
  (func $step1__impl (param $x i32) (result i32)
    (return (call $__promise_resolve_i32 (i32.add (local.get $x) (i32.const 1))))
  )

  (func $step1 (export "step1") (param $x i32) (result i32)
    (return (call $__promise_await_i32 (call $step1__impl (local.get $x))))
  )

  (func $process__impl (param $data i32) (result i32)
    (local $a i32)
    (local.set $a (call $__promise_await_i32 (call $step1__impl (local.get $data))))
    (return (call $__promise_resolve_i32 (i32.mul (local.get $a) (i32.const 10))))
  )

  (func $process (export "process") (param $data i32) (result i32)
    (return (call $__promise_await_i32 (call $process__impl (local.get $data))))
  )

  (func $scale__impl (param $x f64) (result i32)
    (return (call $__promise_resolve_f64 (f64.mul (local.get $x) (f64.const 2.5))))
  )

  (func $scale (export "scale") (param $x f64) (result f64)
    (return (call $__promise_await_f64 (call $scale__impl (local.get $x))))
  )
  (table 1 funcref)
)