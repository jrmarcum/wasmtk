(module
  (import "wasi_snapshot_preview1" "proc_exit" (func $proc_exit (param i32)))
  (import "wasi_snapshot_preview1" "fd_write" (func $fd_write (param i32 i32 i32 i32) (result i32)))
  ;; imports from dynrt_lib_modc
  (import "env" "__host_call" (func $dynrt_lib_modc___host_call (param i32 i32) (result i32)))
  (import "env" "__host_print" (func $dynrt_lib_modc___host_print (param i32 i32)))
  (memory (export "memory") 2)
  (global $__heap_ptr (mut i32) (i32.const 1294))
  (global $__d4s (mut i32) (i32.const 0))
  (global $__free_list (mut i32) (i32.const 0))
  (global $c (mut i32) (i32.const 0))
  (global $ok (mut i32) (i32.const 1))
  (global $guard (mut i32) (i32.const 0))
  ;; Free-list + bump allocator (auto-grows). GC Part 1+2.
  (func $__malloc (param $size i32) (result i32)
    (local $ptr i32)
    (local $cur i32)
    (local $prev i32)
    (local.set $cur (global.get $__free_list))
    (local.set $prev (i32.const 0))
    (block $done
      (loop $scan
        (br_if $done (i32.eqz (local.get $cur)))
        (if (i32.ge_u (i32.load (local.get $cur)) (local.get $size))
          (then
            (if (i32.eqz (local.get $prev))
              (then (global.set $__free_list (i32.load offset=4 (local.get $cur))))
              (else (i32.store offset=4 (local.get $prev) (i32.load offset=4 (local.get $cur)))))
            (return (local.get $cur))))
        (local.set $prev (local.get $cur))
        (local.set $cur (i32.load offset=4 (local.get $cur)))
        (br $scan)))
    (local.set $ptr (global.get $__heap_ptr))
    (global.set $__heap_ptr (i32.add (local.get $ptr) (local.get $size)))
    (if (i32.gt_u (global.get $__heap_ptr) (i32.shl (memory.size) (i32.const 16)))
      (then
        (drop (memory.grow
          (i32.shr_u
            (i32.add
              (i32.sub (global.get $__heap_ptr) (i32.shl (memory.size) (i32.const 16)))
              (i32.const 65535))
            (i32.const 16))))))
    (local.get $ptr)
  )
  ;; Return a block (>= 8 bytes) to the free list. Smaller blocks are leaked (can't hold the header).
  (func $__free (param $ptr i32) (param $size i32)
    (if (i32.ge_u (local.get $size) (i32.const 8))
      (then
        (i32.store (local.get $ptr) (local.get $size))
        (i32.store offset=4 (local.get $ptr) (global.get $__free_list))
        (global.set $__free_list (local.get $ptr))))
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

  ;; ── i32 → decimal string ──────────────────────────────────────────────────
  ;; Writes the decimal representation of $val at $buf, returns byte count.
  (func $__i32_to_str (param $val i32) (param $buf i32) (result i32)
    (local $start i32)
    (local $end i32)
    (local $tmp i32)
    (local $ch i32)
    (local $neg i32)
    (local $orig i32)
    (local.set $orig (local.get $buf))
    (local.set $start (local.get $buf))
    ;; Zero
    (if (i32.eqz (local.get $val))
      (then
        (i32.store8 (local.get $buf) (i32.const 48))
        (return (i32.const 1))
      )
    )
    ;; Negative
    (if (i32.lt_s (local.get $val) (i32.const 0))
      (then
        (i32.store8 (local.get $buf) (i32.const 45))
        (local.set $buf (i32.add (local.get $buf) (i32.const 1)))
        (local.set $start (local.get $buf))
        (local.set $neg (i32.const 1))
        (local.set $val (i32.sub (i32.const 0) (local.get $val)))
      )
    )
    (local.set $end (local.get $buf))
    ;; Write digits in reverse
    (block $done
      (loop $loop
        (br_if $done (i32.eqz (local.get $val)))
        (i32.store8
          (local.get $end)
          (i32.add (i32.const 48) (i32.rem_u (local.get $val) (i32.const 10)))
        )
        (local.set $val (i32.div_u (local.get $val) (i32.const 10)))
        (local.set $end (i32.add (local.get $end) (i32.const 1)))
        (br $loop)
      )
    )
    ;; Reverse digit bytes in-place
    (local.set $tmp (local.get $start))
    (local.set $ch (i32.sub (local.get $end) (i32.const 1)))
    (block $rdone
      (loop $rloop
        (br_if $rdone (i32.ge_u (local.get $tmp) (local.get $ch)))
        (local.set $neg (i32.load8_u (local.get $tmp)))
        (i32.store8 (local.get $tmp) (i32.load8_u (local.get $ch)))
        (i32.store8 (local.get $ch) (local.get $neg))
        (local.set $tmp (i32.add (local.get $tmp) (i32.const 1)))
        (local.set $ch (i32.sub (local.get $ch) (i32.const 1)))
        (br $rloop)
      )
    )
    ;; Return total length (including leading '-' if any)
    (i32.sub (local.get $end) (local.get $orig))
  )

  ;; ── i32 → string in an arbitrary radix (2..36), e.g. (14).toString(2) = "1110" ──
  ;; Mirrors $__i32_to_str but with a parameterised base + digit→char (0-9→'0'+d, 10-35→'a'+d-10).
  ;; Negative values get a leading '-' and unsigned magnitude digits (JS sign-magnitude semantics).
  (func $__i32_to_str_radix (param $val i32) (param $radix i32) (param $buf i32) (result i32)
    (local $start i32)
    (local $end i32)
    (local $tmp i32)
    (local $ch i32)
    (local $swap i32)
    (local $orig i32)
    (local $d i32)
    (local.set $orig (local.get $buf))
    (local.set $start (local.get $buf))
    ;; clamp radix to [2,36] (JS RangeError otherwise; fall back to base 10)
    (if (i32.or (i32.lt_s (local.get $radix) (i32.const 2)) (i32.gt_s (local.get $radix) (i32.const 36)))
      (then (local.set $radix (i32.const 10)))
    )
    ;; Zero
    (if (i32.eqz (local.get $val))
      (then
        (i32.store8 (local.get $buf) (i32.const 48))
        (return (i32.const 1))
      )
    )
    ;; Negative → leading '-' then magnitude
    (if (i32.lt_s (local.get $val) (i32.const 0))
      (then
        (i32.store8 (local.get $buf) (i32.const 45))
        (local.set $buf (i32.add (local.get $buf) (i32.const 1)))
        (local.set $start (local.get $buf))
        (local.set $val (i32.sub (i32.const 0) (local.get $val)))
      )
    )
    (local.set $end (local.get $buf))
    ;; Write digits in reverse
    (block $done
      (loop $loop
        (br_if $done (i32.eqz (local.get $val)))
        (local.set $d (i32.rem_u (local.get $val) (local.get $radix)))
        (i32.store8
          (local.get $end)
          (if (result i32) (i32.lt_u (local.get $d) (i32.const 10))
            (then (i32.add (i32.const 48) (local.get $d)))
            (else (i32.add (i32.const 87) (local.get $d)))
          )
        )
        (local.set $val (i32.div_u (local.get $val) (local.get $radix)))
        (local.set $end (i32.add (local.get $end) (i32.const 1)))
        (br $loop)
      )
    )
    ;; Reverse digit bytes in-place
    (local.set $tmp (local.get $start))
    (local.set $ch (i32.sub (local.get $end) (i32.const 1)))
    (block $rdone
      (loop $rloop
        (br_if $rdone (i32.ge_u (local.get $tmp) (local.get $ch)))
        (local.set $swap (i32.load8_u (local.get $tmp)))
        (i32.store8 (local.get $tmp) (i32.load8_u (local.get $ch)))
        (i32.store8 (local.get $ch) (local.get $swap))
        (local.set $tmp (i32.add (local.get $tmp) (i32.const 1)))
        (local.set $ch (i32.sub (local.get $ch) (i32.const 1)))
        (br $rloop)
      )
    )
    (i32.sub (local.get $end) (local.get $orig))
  )

  ;; -- Dragon4 (Burger-Dybvig) shortest + correctly-rounded f64 -> decimal ------
  ;; Fixed-size limb bignums (48 x u32 = 1536 bits) in a lazily-malloc'd scratch
  ;; region ($__d4s). Produces the shortest decimal digit string that round-trips
  ;; to the exact f64 (round-to-even ties), then formats per ECMAScript
  ;; Number.prototype.toString rules (fixed-point for pointPos in (-6,21], else
  ;; scientific). 100% byte-exact parity with V8 across normal + subnormal range.
  (func $__bz (param $p i32)
    (local $i i32)
    (loop $l
      (i32.store (i32.add (local.get $p) (i32.shl (local.get $i) (i32.const 2))) (i32.const 0))
      (local.set $i (i32.add (local.get $i) (i32.const 1)))
      (br_if $l (i32.lt_u (local.get $i) (i32.const 48)))
    )
  )
  (func $__bset64 (param $p i32) (param $v i64)
    (call $__bz (local.get $p))
    (i32.store (local.get $p) (i32.wrap_i64 (i64.and (local.get $v) (i64.const 0xffffffff))))
    (i32.store offset=4 (local.get $p) (i32.wrap_i64 (i64.shr_u (local.get $v) (i64.const 32))))
  )
  (func $__bmul_u32 (param $p i32) (param $m i32)
    (local $i i32) (local $carry i64) (local $prod i64) (local $addr i32)
    (loop $l
      (local.set $addr (i32.add (local.get $p) (i32.shl (local.get $i) (i32.const 2))))
      (local.set $prod
        (i64.add
          (i64.mul (i64.extend_i32_u (i32.load (local.get $addr))) (i64.extend_i32_u (local.get $m)))
          (local.get $carry)))
      (i32.store (local.get $addr) (i32.wrap_i64 (i64.and (local.get $prod) (i64.const 0xffffffff))))
      (local.set $carry (i64.shr_u (local.get $prod) (i64.const 32)))
      (local.set $i (i32.add (local.get $i) (i32.const 1)))
      (br_if $l (i32.lt_u (local.get $i) (i32.const 48)))
    )
  )
  (func $__bshl (param $p i32) (param $bits i32)
    (local $limbShift i32) (local $bitShift i32) (local $i i32) (local $src i32)
    (local $lo i32) (local $hi i32) (local $val i32)
    (local.set $limbShift (i32.div_u (local.get $bits) (i32.const 32)))
    (local.set $bitShift  (i32.rem_u (local.get $bits) (i32.const 32)))
    (local.set $i (i32.const 47))
    (loop $l
      (local.set $src (i32.sub (local.get $i) (local.get $limbShift)))
      (local.set $val (i32.const 0))
      (if (i32.ge_s (local.get $src) (i32.const 0))
        (then
          (local.set $lo (i32.load (i32.add (local.get $p) (i32.shl (local.get $src) (i32.const 2)))))
          (if (i32.eqz (local.get $bitShift))
            (then (local.set $val (local.get $lo)))
            (else
              (local.set $val (i32.shl (local.get $lo) (local.get $bitShift)))
              (if (i32.gt_s (local.get $src) (i32.const 0))
                (then
                  (local.set $hi (i32.load (i32.add (local.get $p) (i32.shl (i32.sub (local.get $src) (i32.const 1)) (i32.const 2)))))
                  (local.set $val (i32.or (local.get $val)
                    (i32.shr_u (local.get $hi) (i32.sub (i32.const 32) (local.get $bitShift)))))
                ))
            ))
        ))
      (i32.store (i32.add (local.get $p) (i32.shl (local.get $i) (i32.const 2))) (local.get $val))
      (local.set $i (i32.sub (local.get $i) (i32.const 1)))
      (br_if $l (i32.ge_s (local.get $i) (i32.const 0)))
    )
  )
  (func $__bcmp (param $a i32) (param $b i32) (result i32)
    (local $i i32) (local $va i32) (local $vb i32)
    (local.set $i (i32.const 47))
    (loop $l
      (local.set $va (i32.load (i32.add (local.get $a) (i32.shl (local.get $i) (i32.const 2)))))
      (local.set $vb (i32.load (i32.add (local.get $b) (i32.shl (local.get $i) (i32.const 2)))))
      (if (i32.ne (local.get $va) (local.get $vb))
        (then (return (select (i32.const 1) (i32.const -1) (i32.gt_u (local.get $va) (local.get $vb))))))
      (local.set $i (i32.sub (local.get $i) (i32.const 1)))
      (br_if $l (i32.ge_s (local.get $i) (i32.const 0)))
    )
    (i32.const 0)
  )
  (func $__badd (param $d i32) (param $a i32) (param $b i32)
    (local $i i32) (local $carry i64) (local $sum i64)
    (loop $l
      (local.set $sum
        (i64.add
          (i64.add
            (i64.extend_i32_u (i32.load (i32.add (local.get $a) (i32.shl (local.get $i) (i32.const 2)))))
            (i64.extend_i32_u (i32.load (i32.add (local.get $b) (i32.shl (local.get $i) (i32.const 2))))))
          (local.get $carry)))
      (i32.store (i32.add (local.get $d) (i32.shl (local.get $i) (i32.const 2)))
        (i32.wrap_i64 (i64.and (local.get $sum) (i64.const 0xffffffff))))
      (local.set $carry (i64.shr_u (local.get $sum) (i64.const 32)))
      (local.set $i (i32.add (local.get $i) (i32.const 1)))
      (br_if $l (i32.lt_u (local.get $i) (i32.const 48)))
    )
  )
  (func $__bsub (param $d i32) (param $a i32) (param $b i32)
    (local $i i32) (local $borrow i64) (local $diff i64)
    (loop $l
      (local.set $diff
        (i64.sub
          (i64.sub
            (i64.extend_i32_u (i32.load (i32.add (local.get $a) (i32.shl (local.get $i) (i32.const 2)))))
            (i64.extend_i32_u (i32.load (i32.add (local.get $b) (i32.shl (local.get $i) (i32.const 2))))))
          (local.get $borrow)))
      (i32.store (i32.add (local.get $d) (i32.shl (local.get $i) (i32.const 2)))
        (i32.wrap_i64 (i64.and (local.get $diff) (i64.const 0xffffffff))))
      (local.set $borrow (i64.and (i64.shr_u (local.get $diff) (i64.const 63)) (i64.const 1)))
      (local.set $i (i32.add (local.get $i) (i32.const 1)))
      (br_if $l (i32.lt_u (local.get $i) (i32.const 48)))
    )
  )
  (func $__f64_to_str (param $val f64) (param $buf i32) (result i32)
    (local $bits i64) (local $e i32) (local $f i64)
    (local $even i32) (local $isMin i32)
    (local $R i32) (local $S i32) (local $MP i32) (local $MM i32) (local $TMP i32) (local $DIG i32)
    (local $k i32) (local $ndig i32) (local $i i32) (local $dg i32)
    (local $ptr i32) (local $sign i32) (local $cmp i32) (local $low i32) (local $high i32)
    (local $pp i32)
    (local.set $ptr (local.get $buf))
    ;; NaN
    (if (f64.ne (local.get $val) (local.get $val))
      (then
        (i32.store8 (local.get $ptr) (i32.const 78))
        (i32.store8 offset=1 (local.get $ptr) (i32.const 97))
        (i32.store8 offset=2 (local.get $ptr) (i32.const 78))
        (return (i32.const 3))))
    ;; sign (-0 -> lt is false -> prints "0")
    (if (f64.lt (local.get $val) (f64.const 0))
      (then
        (i32.store8 (local.get $ptr) (i32.const 45))
        (local.set $ptr (i32.add (local.get $ptr) (i32.const 1)))
        (local.set $val (f64.neg (local.get $val)))
        (local.set $sign (i32.const 1))))
    ;; Infinity
    (if (f64.eq (local.get $val) (f64.const inf))
      (then
        (i32.store8 (local.get $ptr) (i32.const 73))
        (i32.store8 offset=1 (local.get $ptr) (i32.const 110))
        (i32.store8 offset=2 (local.get $ptr) (i32.const 102))
        (i32.store8 offset=3 (local.get $ptr) (i32.const 105))
        (i32.store8 offset=4 (local.get $ptr) (i32.const 110))
        (i32.store8 offset=5 (local.get $ptr) (i32.const 105))
        (i32.store8 offset=6 (local.get $ptr) (i32.const 116))
        (i32.store8 offset=7 (local.get $ptr) (i32.const 121))
        (return (i32.add (i32.sub (local.get $ptr) (local.get $buf)) (i32.const 8)))))
    ;; zero
    (if (f64.eq (local.get $val) (f64.const 0))
      (then
        (i32.store8 (local.get $ptr) (i32.const 48))
        (return (i32.add (i32.sub (local.get $ptr) (local.get $buf)) (i32.const 1)))))
    ;; lazily allocate bignum scratch
    (if (i32.eqz (global.get $__d4s))
      (then (global.set $__d4s (call $__malloc (i32.const 1024)))))
    (local.set $R   (global.get $__d4s))
    (local.set $S   (i32.add (global.get $__d4s) (i32.const 192)))
    (local.set $MP  (i32.add (global.get $__d4s) (i32.const 384)))
    (local.set $MM  (i32.add (global.get $__d4s) (i32.const 576)))
    (local.set $TMP (i32.add (global.get $__d4s) (i32.const 768)))
    (local.set $DIG (i32.add (global.get $__d4s) (i32.const 960)))
    ;; decompose f64 -> f (mantissa integer) x 2^e
    (local.set $bits (i64.reinterpret_f64 (local.get $val)))
    (local.set $e (i32.wrap_i64 (i64.and (i64.shr_u (local.get $bits) (i64.const 52)) (i64.const 0x7ff))))
    (local.set $f (i64.and (local.get $bits) (i64.const 0xfffffffffffff)))
    (if (i32.eqz (local.get $e))
      (then (local.set $e (i32.const -1074)))
      (else
        (local.set $f (i64.or (local.get $f) (i64.shl (i64.const 1) (i64.const 52))))
        (local.set $e (i32.sub (local.get $e) (i32.const 1075)))))
    (local.set $even (i32.eqz (i32.wrap_i64 (i64.and (local.get $f) (i64.const 1)))))
    (local.set $isMin (i64.eq (local.get $f) (i64.shl (i64.const 1) (i64.const 52))))
    ;; build R, S, m+, m-
    (if (i32.ge_s (local.get $e) (i32.const 0))
      (then
        (call $__bset64 (local.get $TMP) (i64.const 1))
        (call $__bshl (local.get $TMP) (local.get $e))
        (if (i32.eqz (local.get $isMin))
          (then
            (call $__bset64 (local.get $R) (local.get $f))
            (call $__bshl (local.get $R) (i32.add (local.get $e) (i32.const 1)))
            (call $__bset64 (local.get $S) (i64.const 2))
            (memory.copy (local.get $MP) (local.get $TMP) (i32.const 192))
            (memory.copy (local.get $MM) (local.get $TMP) (i32.const 192)))
          (else
            (call $__bset64 (local.get $R) (local.get $f))
            (call $__bshl (local.get $R) (i32.add (local.get $e) (i32.const 2)))
            (call $__bset64 (local.get $S) (i64.const 4))
            (memory.copy (local.get $MP) (local.get $TMP) (i32.const 192))
            (call $__bshl (local.get $MP) (i32.const 1))
            (memory.copy (local.get $MM) (local.get $TMP) (i32.const 192)))))
      (else
        (if (i32.or (i32.eq (local.get $e) (i32.const -1074)) (i32.eqz (local.get $isMin)))
          (then
            (call $__bset64 (local.get $R) (local.get $f))
            (call $__bshl (local.get $R) (i32.const 1))
            (call $__bset64 (local.get $S) (i64.const 1))
            (call $__bshl (local.get $S) (i32.add (i32.sub (i32.const 0) (local.get $e)) (i32.const 1)))
            (call $__bset64 (local.get $MP) (i64.const 1))
            (call $__bset64 (local.get $MM) (i64.const 1)))
          (else
            (call $__bset64 (local.get $R) (local.get $f))
            (call $__bshl (local.get $R) (i32.const 2))
            (call $__bset64 (local.get $S) (i64.const 1))
            (call $__bshl (local.get $S) (i32.add (i32.sub (i32.const 0) (local.get $e)) (i32.const 2)))
            (call $__bset64 (local.get $MP) (i64.const 2))
            (call $__bset64 (local.get $MM) (i64.const 1))))))
    ;; k estimate from binary magnitude (bidirectional fixup corrects any error)
    (local.set $k
      (i32.trunc_f64_s
        (f64.ceil
          (f64.mul (f64.convert_i32_s (i32.add (local.get $e) (i32.const 52)))
                   (f64.const 0.30102999566398114)))))
    ;; initial scale by 10^k
    (if (i32.ge_s (local.get $k) (i32.const 0))
      (then
        (local.set $i (i32.const 0))
        (block $se (loop $sl
          (br_if $se (i32.ge_s (local.get $i) (local.get $k)))
          (call $__bmul_u32 (local.get $S) (i32.const 10))
          (local.set $i (i32.add (local.get $i) (i32.const 1)))
          (br $sl))))
      (else
        (local.set $i (local.get $k))
        (block $re (loop $rl
          (br_if $re (i32.ge_s (local.get $i) (i32.const 0)))
          (call $__bmul_u32 (local.get $R)  (i32.const 10))
          (call $__bmul_u32 (local.get $MP) (i32.const 10))
          (call $__bmul_u32 (local.get $MM) (i32.const 10))
          (local.set $i (i32.add (local.get $i) (i32.const 1)))
          (br $rl)))))
    ;; too-small fixup: while high(R+m+, S) -> S*=10; k++
    (block $fse (loop $fsl
      (call $__badd (local.get $TMP) (local.get $R) (local.get $MP))
      (local.set $cmp (call $__bcmp (local.get $TMP) (local.get $S)))
      (br_if $fse (i32.eqz
        (select (i32.ge_s (local.get $cmp) (i32.const 0))
                (i32.gt_s (local.get $cmp) (i32.const 0))
                (local.get $even))))
      (call $__bmul_u32 (local.get $S) (i32.const 10))
      (local.set $k (i32.add (local.get $k) (i32.const 1)))
      (br $fsl)))
    ;; too-big fixup: while NOT high(10*(R+m+), S) -> R,m+,m- *=10; k--
    (block $fbe (loop $fbl
      (call $__badd (local.get $TMP) (local.get $R) (local.get $MP))
      (call $__bmul_u32 (local.get $TMP) (i32.const 10))
      (local.set $cmp (call $__bcmp (local.get $TMP) (local.get $S)))
      (br_if $fbe (i32.eqz
        (select (i32.lt_s (local.get $cmp) (i32.const 0))
                (i32.le_s (local.get $cmp) (i32.const 0))
                (local.get $even))))
      (call $__bmul_u32 (local.get $R)  (i32.const 10))
      (call $__bmul_u32 (local.get $MP) (i32.const 10))
      (call $__bmul_u32 (local.get $MM) (i32.const 10))
      (local.set $k (i32.sub (local.get $k) (i32.const 1)))
      (br $fbl)))
    ;; digit generation
    (local.set $ndig (i32.const 0))
    (loop $dl
      (call $__bmul_u32 (local.get $R)  (i32.const 10))
      (call $__bmul_u32 (local.get $MP) (i32.const 10))
      (call $__bmul_u32 (local.get $MM) (i32.const 10))
      ;; dg = R/S ; R = R%S  (repeated subtract, dg in [0,9])
      (local.set $dg (i32.const 0))
      (block $sube (loop $subl
        (br_if $sube (i32.lt_s (call $__bcmp (local.get $R) (local.get $S)) (i32.const 0)))
        (call $__bsub (local.get $R) (local.get $R) (local.get $S))
        (local.set $dg (i32.add (local.get $dg) (i32.const 1)))
        (br $subl)))
      ;; low
      (local.set $cmp (call $__bcmp (local.get $R) (local.get $MM)))
      (local.set $low
        (select (i32.le_s (local.get $cmp) (i32.const 0))
                (i32.lt_s (local.get $cmp) (i32.const 0))
                (local.get $even)))
      ;; high
      (call $__badd (local.get $TMP) (local.get $R) (local.get $MP))
      (local.set $cmp (call $__bcmp (local.get $TMP) (local.get $S)))
      (local.set $high
        (select (i32.ge_s (local.get $cmp) (i32.const 0))
                (i32.gt_s (local.get $cmp) (i32.const 0))
                (local.get $even)))
      ;; continue when neither boundary reached
      (if (i32.and (i32.eqz (local.get $low)) (i32.eqz (local.get $high)))
        (then
          (i32.store8 (i32.add (local.get $DIG) (local.get $ndig)) (i32.add (i32.const 48) (local.get $dg)))
          (local.set $ndig (i32.add (local.get $ndig) (i32.const 1)))
          (br $dl)))
      ;; terminate: choose final digit (default keep dg)
      (if (i32.and (local.get $high) (i32.eqz (local.get $low)))
        (then (local.set $dg (i32.add (local.get $dg) (i32.const 1))))
        (else
          (if (i32.and (local.get $high) (local.get $low))
            (then
              (call $__badd (local.get $TMP) (local.get $R) (local.get $R))
              (local.set $cmp (call $__bcmp (local.get $TMP) (local.get $S)))
              (if (i32.gt_s (local.get $cmp) (i32.const 0))
                (then (local.set $dg (i32.add (local.get $dg) (i32.const 1))))
                (else
                  (if (i32.eqz (local.get $cmp))
                    (then (if (i32.and (local.get $dg) (i32.const 1))
                            (then (local.set $dg (i32.add (local.get $dg) (i32.const 1)))))))))))))
      (i32.store8 (i32.add (local.get $DIG) (local.get $ndig)) (i32.add (i32.const 48) (local.get $dg)))
      (local.set $ndig (i32.add (local.get $ndig) (i32.const 1)))
    )
    ;; format per ECMAScript Number.prototype.toString (pointPos == k)
    (local.set $pp (local.get $k))
    ;; pp > 21 -> scientific "d[.ddd]e+E"
    (if (i32.gt_s (local.get $pp) (i32.const 21))
      (then
        (i32.store8 (local.get $ptr) (i32.load8_u (local.get $DIG)))
        (local.set $ptr (i32.add (local.get $ptr) (i32.const 1)))
        (if (i32.gt_s (local.get $ndig) (i32.const 1))
          (then
            (i32.store8 (local.get $ptr) (i32.const 46))
            (local.set $ptr (i32.add (local.get $ptr) (i32.const 1)))
            (memory.copy (local.get $ptr) (i32.add (local.get $DIG) (i32.const 1)) (i32.sub (local.get $ndig) (i32.const 1)))
            (local.set $ptr (i32.add (local.get $ptr) (i32.sub (local.get $ndig) (i32.const 1))))))
        (i32.store8 (local.get $ptr) (i32.const 101))
        (i32.store8 offset=1 (local.get $ptr) (i32.const 43))
        (local.set $ptr (i32.add (local.get $ptr) (i32.const 2)))
        (local.set $ptr (i32.add (local.get $ptr) (call $__i32_to_str (i32.sub (local.get $pp) (i32.const 1)) (local.get $ptr))))
        (return (i32.sub (local.get $ptr) (local.get $buf)))))
    ;; pp <= -6 -> scientific "d[.ddd]e-E"
    (if (i32.le_s (local.get $pp) (i32.const -6))
      (then
        (i32.store8 (local.get $ptr) (i32.load8_u (local.get $DIG)))
        (local.set $ptr (i32.add (local.get $ptr) (i32.const 1)))
        (if (i32.gt_s (local.get $ndig) (i32.const 1))
          (then
            (i32.store8 (local.get $ptr) (i32.const 46))
            (local.set $ptr (i32.add (local.get $ptr) (i32.const 1)))
            (memory.copy (local.get $ptr) (i32.add (local.get $DIG) (i32.const 1)) (i32.sub (local.get $ndig) (i32.const 1)))
            (local.set $ptr (i32.add (local.get $ptr) (i32.sub (local.get $ndig) (i32.const 1))))))
        (i32.store8 (local.get $ptr) (i32.const 101))
        (i32.store8 offset=1 (local.get $ptr) (i32.const 45))
        (local.set $ptr (i32.add (local.get $ptr) (i32.const 2)))
        (local.set $ptr (i32.add (local.get $ptr) (call $__i32_to_str (i32.sub (i32.const 1) (local.get $pp)) (local.get $ptr))))
        (return (i32.sub (local.get $ptr) (local.get $buf)))))
    ;; pp <= 0 -> "0." + (-pp) zeros + digits
    (if (i32.le_s (local.get $pp) (i32.const 0))
      (then
        (i32.store8 (local.get $ptr) (i32.const 48))
        (i32.store8 offset=1 (local.get $ptr) (i32.const 46))
        (local.set $ptr (i32.add (local.get $ptr) (i32.const 2)))
        (local.set $i (i32.const 0))
        (block $ze (loop $zl
          (br_if $ze (i32.ge_s (local.get $i) (i32.sub (i32.const 0) (local.get $pp))))
          (i32.store8 (local.get $ptr) (i32.const 48))
          (local.set $ptr (i32.add (local.get $ptr) (i32.const 1)))
          (local.set $i (i32.add (local.get $i) (i32.const 1)))
          (br $zl)))
        (memory.copy (local.get $ptr) (local.get $DIG) (local.get $ndig))
        (local.set $ptr (i32.add (local.get $ptr) (local.get $ndig)))
        (return (i32.sub (local.get $ptr) (local.get $buf)))))
    ;; pp >= ndig -> digits + (pp-ndig) zeros
    (if (i32.ge_s (local.get $pp) (local.get $ndig))
      (then
        (memory.copy (local.get $ptr) (local.get $DIG) (local.get $ndig))
        (local.set $ptr (i32.add (local.get $ptr) (local.get $ndig)))
        (local.set $i (i32.const 0))
        (block $ze2 (loop $zl2
          (br_if $ze2 (i32.ge_s (local.get $i) (i32.sub (local.get $pp) (local.get $ndig))))
          (i32.store8 (local.get $ptr) (i32.const 48))
          (local.set $ptr (i32.add (local.get $ptr) (i32.const 1)))
          (local.set $i (i32.add (local.get $i) (i32.const 1)))
          (br $zl2)))
        (return (i32.sub (local.get $ptr) (local.get $buf)))))
    ;; else split at pp: digits[0..pp) "." digits[pp..]
    (memory.copy (local.get $ptr) (local.get $DIG) (local.get $pp))
    (local.set $ptr (i32.add (local.get $ptr) (local.get $pp)))
    (i32.store8 (local.get $ptr) (i32.const 46))
    (local.set $ptr (i32.add (local.get $ptr) (i32.const 1)))
    (memory.copy (local.get $ptr) (i32.add (local.get $DIG) (local.get $pp)) (i32.sub (local.get $ndig) (local.get $pp)))
    (local.set $ptr (i32.add (local.get $ptr) (i32.sub (local.get $ndig) (local.get $pp))))
    (i32.sub (local.get $ptr) (local.get $buf))
  )

  ;; ── i64 → decimal string ──────────────────────────────────────────────────
  ;; Writes the decimal representation of $val at $buf, returns byte count.
  (func $__i64_to_str (param $val i64) (param $buf i32) (result i32)
    (local $start i32)
    (local $end i32)
    (local $tmp i32)
    (local $ch i32)
    (local $neg i32)
    (local $digit i32)
    (local $orig i32)
    (local.set $orig (local.get $buf))
    (local.set $start (local.get $buf))
    ;; Zero
    (if (i64.eqz (local.get $val))
      (then
        (i32.store8 (local.get $buf) (i32.const 48))
        (i32.store8 (i32.add (local.get $buf) (i32.const 1)) (i32.const 110))
        (return (i32.const 2))
      )
    )
    ;; Negative
    (if (i64.lt_s (local.get $val) (i64.const 0))
      (then
        (i32.store8 (local.get $buf) (i32.const 45))
        (local.set $buf (i32.add (local.get $buf) (i32.const 1)))
        (local.set $start (local.get $buf))
        (local.set $neg (i32.const 1))
        (local.set $val (i64.sub (i64.const 0) (local.get $val)))
      )
    )
    (local.set $end (local.get $buf))
    ;; Write digits in reverse
    (block $done
      (loop $loop
        (br_if $done (i64.eqz (local.get $val)))
        (local.set $digit (i32.wrap_i64 (i64.rem_u (local.get $val) (i64.const 10))))
        (i32.store8
          (local.get $end)
          (i32.add (i32.const 48) (local.get $digit))
        )
        (local.set $val (i64.div_u (local.get $val) (i64.const 10)))
        (local.set $end (i32.add (local.get $end) (i32.const 1)))
        (br $loop)
      )
    )
    ;; Reverse digit bytes in-place
    (local.set $tmp (local.get $start))
    (local.set $ch (i32.sub (local.get $end) (i32.const 1)))
    (block $rdone
      (loop $rloop
        (br_if $rdone (i32.ge_u (local.get $tmp) (local.get $ch)))
        (local.set $neg (i32.load8_u (local.get $tmp)))
        (i32.store8 (local.get $tmp) (i32.load8_u (local.get $ch)))
        (i32.store8 (local.get $ch) (local.get $neg))
        (local.set $tmp (i32.add (local.get $tmp) (i32.const 1)))
        (local.set $ch (i32.sub (local.get $ch) (i32.const 1)))
        (br $rloop)
      )
    )
    ;; Append 'n' suffix for bigint display
    (i32.store8 (local.get $end) (i32.const 110))
    (local.set $end (i32.add (local.get $end) (i32.const 1)))
    ;; Return total length (including leading '-' and trailing 'n')
    (i32.sub (local.get $end) (local.get $orig))
  )












































































































































  (func $check (param $cond i32) 
    (local $x i32)
    (local $__iface_tmp i32)
    (if (i32.eq (local.get $cond) (i32.const 0))
      (then
      (local.set $x (i32.load (i32.add (i32.add (global.get $guard) (i32.const 8)) (i32.shl (i32.const 5000000) (i32.const 2)))))
          (i32.store (i32.const 0) (i32.const 132))
          (i32.store (i32.const 4) (call $__i32_to_str (local.get $x) (i32.const 132)))
          (i32.store8 (i32.add (i32.const 132) (i32.load (i32.const 4))) (i32.const 10))
          (i32.store (i32.const 4) (i32.add (i32.load (i32.const 4)) (i32.const 1)))
          (drop (call $fd_write
            (i32.const 1)
            (i32.const 0)
            (i32.const 1)
            (i32.const 128)))
      )
    )
  )

  (func $buildCheck (param $n i32) (result i32)
    (local $a i32)
    (local $i i32)
    (local $lenOk i32)
    (local $first f64)
    (local $last f64)
    (local $lastExp f64)
    (local $valOk i32)
    (local.set $a (call $dynrt_lib_modc_dynArray ))
    (local.set $i (i32.const 0))
    (block $break_0
      (loop $loop_0
        (br_if $break_0 (i32.eqz (i32.lt_s (local.get $i) (local.get $n))))
        (block $cont_0
          (call $dynrt_lib_modc_dynPush (local.get $a) (call $dynrt_lib_modc_dynNumber (f64.convert_i32_s (local.get $i))))
          (local.set $i (i32.add (local.get $i) (i32.const 1)))
        )
        (br $loop_0)
      )
    )
    (local.set $lenOk (if (result i32) (i32.eq (call $dynrt_lib_modc_dynArrLen (local.get $a)) (local.get $n)) (then (i32.const 1)) (else (i32.const 0))))
    (local.set $first (call $dynrt_lib_modc_dynNumberValue (call $dynrt_lib_modc_dynArrGet (local.get $a) (i32.const 0))))
    (local.set $last (call $dynrt_lib_modc_dynNumberValue (call $dynrt_lib_modc_dynArrGet (local.get $a) (i32.sub (local.get $n) (i32.const 1)))))
    (local.set $lastExp (f64.convert_i32_s (i32.sub (local.get $n) (i32.const 1))))
    (local.set $valOk (if (result i32) (f64.eq (local.get $first) (f64.const 0.0)) (then (if (result i32) (f64.eq (local.get $last) (local.get $lastExp)) (then (i32.const 1)) (else (i32.const 0)))) (else (i32.const 0))))
    (return (if (result i32) (i32.eq (local.get $lenOk) (i32.const 1)) (then (local.get $valOk)) (else (i32.const 0))))
  )
  (func $_start (export "_start")
    (local $__iface_tmp i32)
    (global.set $guard (call $__malloc (i32.const 40)))
      (i32.store (global.get $guard) (i32.const 1))
      (i32.store offset=4 (global.get $guard) (i32.const 8))
      (i32.store offset=8 (global.get $guard) (i32.const 0))
    (call $check (if (result i32) (i32.eq (call $buildCheck (i32.const 100)) (i32.const 1)) (then (i32.const 1)) (else (i32.const 0))))
    (drop (call $dynrt_lib_modc_dynGcCollect ))
    (block $break_1
      (loop $loop_1
        (br_if $break_1 (i32.eqz (i32.lt_s (global.get $c) (i32.const 30))))
        (block $cont_1
          (if (i32.ne (call $buildCheck (i32.const 100)) (i32.const 1))
            (then
            (global.set $ok (i32.const 0))
            )
          )
          (drop (call $dynrt_lib_modc_dynGcCollect ))
          (global.set $c (i32.add (global.get $c) (i32.const 1)))
        )
        (br $loop_1)
      )
    )
    (call $check (global.get $ok))
    (call $check (if (result i32) (i32.lt_s (call $dynrt_lib_modc_dynGcCellCount ) (i32.const 50)) (then (i32.const 1)) (else (i32.const 0))))
        (i32.store (i32.const 0) (i32.const 132))
          (i32.store (i32.const 4) (i32.const 0))
          (i32.store8 (i32.const 132) (i32.const 71))
          (i32.store8 (i32.const 133) (i32.const 67))
          (i32.store8 (i32.const 134) (i32.const 32))
          (i32.store8 (i32.const 135) (i32.const 115))
          (i32.store8 (i32.const 136) (i32.const 112))
          (i32.store8 (i32.const 137) (i32.const 108))
          (i32.store8 (i32.const 138) (i32.const 105))
          (i32.store8 (i32.const 139) (i32.const 116))
          (i32.store8 (i32.const 140) (i32.const 58))
          (i32.store8 (i32.const 141) (i32.const 32))
          (i32.store8 (i32.const 142) (i32.const 99))
          (i32.store8 (i32.const 143) (i32.const 111))
          (i32.store8 (i32.const 144) (i32.const 114))
          (i32.store8 (i32.const 145) (i32.const 114))
          (i32.store8 (i32.const 146) (i32.const 101))
          (i32.store8 (i32.const 147) (i32.const 99))
          (i32.store8 (i32.const 148) (i32.const 116))
          (i32.store8 (i32.const 149) (i32.const 110))
          (i32.store8 (i32.const 150) (i32.const 101))
          (i32.store8 (i32.const 151) (i32.const 115))
          (i32.store8 (i32.const 152) (i32.const 115))
          (i32.store8 (i32.const 153) (i32.const 32))
          (i32.store8 (i32.const 154) (i32.const 43))
          (i32.store8 (i32.const 155) (i32.const 32))
          (i32.store8 (i32.const 156) (i32.const 98))
          (i32.store8 (i32.const 157) (i32.const 111))
          (i32.store8 (i32.const 158) (i32.const 117))
          (i32.store8 (i32.const 159) (i32.const 110))
          (i32.store8 (i32.const 160) (i32.const 100))
          (i32.store8 (i32.const 161) (i32.const 101))
          (i32.store8 (i32.const 162) (i32.const 100))
          (i32.store8 (i32.const 163) (i32.const 32))
          (i32.store8 (i32.const 164) (i32.const 117))
          (i32.store8 (i32.const 165) (i32.const 110))
          (i32.store8 (i32.const 166) (i32.const 100))
          (i32.store8 (i32.const 167) (i32.const 101))
          (i32.store8 (i32.const 168) (i32.const 114))
          (i32.store8 (i32.const 169) (i32.const 32))
          (i32.store8 (i32.const 170) (i32.const 109))
          (i32.store8 (i32.const 171) (i32.const 105))
          (i32.store8 (i32.const 172) (i32.const 120))
          (i32.store8 (i32.const 173) (i32.const 101))
          (i32.store8 (i32.const 174) (i32.const 100))
          (i32.store8 (i32.const 175) (i32.const 45))
          (i32.store8 (i32.const 176) (i32.const 115))
          (i32.store8 (i32.const 177) (i32.const 105))
          (i32.store8 (i32.const 178) (i32.const 122))
          (i32.store8 (i32.const 179) (i32.const 101))
          (i32.store8 (i32.const 180) (i32.const 32))
          (i32.store8 (i32.const 181) (i32.const 114))
          (i32.store8 (i32.const 182) (i32.const 101))
          (i32.store8 (i32.const 183) (i32.const 117))
          (i32.store8 (i32.const 184) (i32.const 115))
          (i32.store8 (i32.const 185) (i32.const 101))
          (i32.store8 (i32.const 186) (i32.const 59))
          (i32.store8 (i32.const 187) (i32.const 32))
          (i32.store8 (i32.const 188) (i32.const 108))
          (i32.store8 (i32.const 189) (i32.const 105))
          (i32.store8 (i32.const 190) (i32.const 118))
          (i32.store8 (i32.const 191) (i32.const 101))
          (i32.store8 (i32.const 192) (i32.const 32))
          (i32.store8 (i32.const 193) (i32.const 99))
          (i32.store8 (i32.const 194) (i32.const 101))
          (i32.store8 (i32.const 195) (i32.const 108))
          (i32.store8 (i32.const 196) (i32.const 108))
          (i32.store8 (i32.const 197) (i32.const 115))
          (i32.store8 (i32.const 198) (i32.const 32))
          (i32.store8 (i32.const 199) (i32.const 61))
          (i32.store8 (i32.const 200) (i32.const 32))
          (i32.store (i32.const 4) (i32.add (i32.const 69) (call $__i32_to_str (call $dynrt_lib_modc_dynGcCellCount) (i32.const 201))))
          (i32.store8 (i32.add (i32.const 132) (i32.load (i32.const 4))) (i32.const 10))
          (i32.store (i32.const 4) (i32.add (i32.load (i32.const 4)) (i32.const 1)))
          (drop (call $fd_write
            (i32.const 1)
            (i32.const 0)
            (i32.const 1)
            (i32.const 128)))
    (call $proc_exit (i32.const 0))
  )

  ;; globals from dynrt_lib_modc
  (global $dynrt_lib_modc_global1 (mut i32) (i32.const 0))
  (global $dynrt_lib_modc_global2 (mut i32) (i32.const 0))
  (global $dynrt_lib_modc_global3 (mut i32) (i32.const 0))
  (global $dynrt_lib_modc_global4 i32 (i32.const 4))
  (global $dynrt_lib_modc_global5 i32 (i32.const 16))
  (global $dynrt_lib_modc_global6 i32 (i32.const 772))
  (global $dynrt_lib_modc_global7 (mut i32) (i32.const 0))
  (global $dynrt_lib_modc_global8 (mut i32) (i32.const 0))
  (global $dynrt_lib_modc_global9 (mut i32) (i32.const 0))
  (global $dynrt_lib_modc_global10 (mut i32) (i32.const 0))
  (global $dynrt_lib_modc_global11 (mut i32) (i32.const 0))
  (global $dynrt_lib_modc_global12 (mut i32) (i32.const 0))
  (global $dynrt_lib_modc_global13 (mut i32) (i32.const 0))
  (global $dynrt_lib_modc_global14 (mut i32) (i32.const 772))
  (global $dynrt_lib_modc_global15 (mut i32) (i32.const 8192))
  (global $dynrt_lib_modc_global16 (mut i32) (i32.const 0))
  (global $dynrt_lib_modc_global17 i32 (i32.const 256))
  (global $dynrt_lib_modc_global18 (mut i32) (i32.const 0))
  (global $dynrt_lib_modc_global19 (mut i32) (i32.const 0))
  (global $dynrt_lib_modc_global20 (mut i32) (i32.const 0))
  (global $dynrt_lib_modc_global21 (mut i32) (i32.const -1))
  (global $dynrt_lib_modc_global22 (mut i32) (i32.const 1))
  (global $dynrt_lib_modc_global23 (mut i32) (i32.const 0))
  (global $dynrt_lib_modc_global24 (mut i32) (i32.const 0))
  (global $dynrt_lib_modc_global25 (mut i32) (i32.const 0))
  (global $dynrt_lib_modc_global26 (mut i32) (i32.const 0))
  (global $dynrt_lib_modc_global27 (mut i32) (i32.const 0))
  (global $dynrt_lib_modc_global28 (mut i32) (i32.const 0))
  (global $dynrt_lib_modc_global29 (mut i32) (i32.const 0))
  (global $dynrt_lib_modc_global30 (mut i32) (i32.const 0))
  (global $dynrt_lib_modc_global31 (mut i32) (i32.const -1))
  ;; functions from dynrt_lib_modc
  (func $dynrt_lib_modc_cabi_realloc (param i32 i32 i32 i32) (result i32)
    local.get 3
    call $__malloc
    local.get 0
    local.get 0
    i32.eqz
    select)
  (func $dynrt_lib_modc__fn4 (param i32 i32 i32)
    (local i32) (local i32)
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 3
          local.get 1
          i32.ge_u
          br_if 2 (;@1;)
          local.get 2
          local.get 3
          i32.add
          local.get 0
          local.get 3
          i32.add
          i32.load8_u
          i32.store8
          local.get 3
          local.tee 4
          i32.const 1
          i32.add
          local.set 3
          br 1 (;@2;)
        end
      end
    end)
  (func $dynrt_lib_modc__fn5 (param i32 i32 i32 i32) (result i32 i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 1
    local.get 3
    i32.add
    local.set 5
    local.get 5
    call $__malloc
    local.set 4
    i32.const 0
    local.tee 9
    local.set 6
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 6
          local.get 1
          i32.ge_u
          br_if 2 (;@1;)
          local.get 4
          local.get 6
          i32.add
          local.get 0
          local.get 6
          i32.add
          i32.load8_u
          i32.store8
          local.get 6
          local.tee 7
          i32.const 1
          i32.add
          local.set 6
          br 1 (;@2;)
        end
      end
    end
    i32.const 0
    local.tee 10
    local.set 6
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 6
          local.get 3
          i32.ge_u
          br_if 2 (;@1;)
          local.get 4
          local.get 1
          local.get 6
          i32.add
          i32.add
          local.get 2
          local.get 6
          i32.add
          i32.load8_u
          i32.store8
          local.get 6
          local.tee 8
          i32.const 1
          i32.add
          local.set 6
          br 1 (;@2;)
        end
      end
    end
    local.get 4
    local.get 5
    local.tee 11)
  (func $dynrt_lib_modc__fn6 (param i32 i32 i32 i32) (result i32 i32)
    (local i32) (local i32) (local i32)
    i32.const 0
    local.get 2
    local.get 2
    i32.const 0
    i32.lt_s
    select
    local.set 4
    local.get 4
    local.get 1
    i32.gt_s
    if  ;; label = @1
      local.get 1
      local.set 4
    end
    local.get 1
    local.get 3
    local.get 3
    local.get 1
    i32.gt_s
    select
    local.set 5
    local.get 5
    local.get 4
    i32.lt_s
    if  ;; label = @1
      local.get 4
      local.set 5
    end
    local.get 0
    local.get 4
    local.tee 6
    i32.add
    local.get 5
    local.get 6
    i32.sub)
  (func $dynrt_lib_modc__fn7 (param i32 i32 i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 3
    i32.eqz
    if  ;; label = @1
      i32.const 0
      return
    end
    local.get 1
    local.get 3
    i32.sub
    local.set 6
    local.get 6
    i32.const 0
    i32.lt_s
    if  ;; label = @1
      i32.const -1
      return
    end
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 4
          local.get 6
          i32.gt_s
          br_if 2 (;@1;)
          i32.const 0
          local.set 5
          i32.const 1
          local.tee 8
          local.set 7
          block  ;; label = @4
            loop  ;; label = @5
              block  ;; label = @6
                local.get 5
                local.get 3
                i32.ge_u
                br_if 2 (;@4;)
                local.get 0
                local.get 4
                local.get 5
                i32.add
                i32.add
                i32.load8_u
                local.get 2
                local.get 5
                i32.add
                i32.load8_u
                i32.ne
                if  ;; label = @7
                  block  ;; label = @8
                    i32.const 0
                    local.set 7
                    br 4 (;@4;)
                  end
                end
                local.get 5
                i32.const 1
                i32.add
                local.set 5
                br 1 (;@5;)
              end
            end
          end
          local.get 7
          if  ;; label = @4
            local.get 4
            return
          end
          local.get 4
          local.get 8
          i32.add
          local.set 4
          br 1 (;@2;)
        end
      end
    end
    i32.const -1)
  (func $dynrt_lib_modc__fn8 (param i32 i32) (result i32 i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    i32.const 0
    local.set 2
    local.get 1
    local.set 3
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 2
          local.get 3
          i32.ge_u
          br_if 2 (;@1;)
          local.get 0
          local.get 2
          i32.add
          i32.load8_u
          local.set 4
          local.get 4
          i32.const 32
          i32.ne
          local.get 4
          i32.const 9
          i32.ne
          i32.and
          local.get 4
          i32.const 10
          i32.ne
          local.get 4
          i32.const 13
          i32.ne
          i32.and
          i32.and
          br_if 2 (;@1;)
          local.get 2
          local.tee 5
          i32.const 1
          i32.add
          local.set 2
          br 1 (;@2;)
        end
      end
    end
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 3
          local.get 2
          i32.le_u
          br_if 2 (;@1;)
          local.get 0
          local.get 3
          i32.const 1
          i32.sub
          i32.add
          i32.load8_u
          local.set 4
          local.get 4
          i32.const 32
          i32.ne
          local.get 4
          i32.const 9
          i32.ne
          i32.and
          local.get 4
          i32.const 10
          i32.ne
          local.get 4
          i32.const 13
          i32.ne
          i32.and
          i32.and
          br_if 2 (;@1;)
          local.get 3
          i32.const 1
          i32.sub
          local.tee 6
          local.set 3
          br 1 (;@2;)
        end
      end
    end
    local.get 0
    local.get 2
    local.tee 7
    i32.add
    local.get 3
    local.get 7
    i32.sub)
  (func $dynrt_lib_modc__fn9 (param i32 i32 i32) (result i32)
    local.get 2
    i32.const 0
    i32.lt_s
    if  ;; label = @1
      i32.const -1
      return
    end
    local.get 2
    local.get 1
    i32.ge_u
    if  ;; label = @1
      i32.const -1
      return
    end
    local.get 0
    local.get 2
    i32.add
    i32.load8_u)
  (func $dynrt_lib_modc__fn10 (param i32 i32 i32) (result i32 i32)
    local.get 2
    i32.const 0
    i32.lt_s
    if  ;; label = @1
      block  ;; label = @2
        local.get 0
        i32.const 0
        return
      end
    end
    local.get 2
    local.get 1
    i32.ge_u
    if  ;; label = @1
      block  ;; label = @2
        local.get 0
        i32.const 0
        return
      end
    end
    local.get 0
    local.get 2
    i32.add
    i32.const 1)
  (func $dynrt_lib_modc__fn11 (param i32 i32 i32 i32) (result i32)
    (local i32)
    local.get 3
    local.get 1
    i32.gt_u
    if  ;; label = @1
      i32.const 0
      return
    end
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 4
          local.get 3
          i32.ge_u
          br_if 2 (;@1;)
          local.get 0
          local.get 4
          i32.add
          i32.load8_u
          local.get 2
          local.get 4
          i32.add
          i32.load8_u
          i32.ne
          if  ;; label = @4
            i32.const 0
            return
          end
          local.get 4
          i32.const 1
          i32.add
          local.set 4
          br 1 (;@2;)
        end
      end
    end
    i32.const 1)
  (func $dynrt_lib_modc__fn12 (param i32 i32 i32 i32) (result i32)
    (local i32) (local i32)
    local.get 3
    local.get 1
    i32.gt_u
    if  ;; label = @1
      i32.const 0
      return
    end
    local.get 1
    local.get 3
    i32.sub
    local.set 5
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 4
          local.get 3
          i32.ge_u
          br_if 2 (;@1;)
          local.get 0
          local.get 5
          local.get 4
          i32.add
          i32.add
          i32.load8_u
          local.get 2
          local.get 4
          i32.add
          i32.load8_u
          i32.ne
          if  ;; label = @4
            i32.const 0
            return
          end
          local.get 4
          i32.const 1
          i32.add
          local.set 4
          br 1 (;@2;)
        end
      end
    end
    i32.const 1)
  (func $dynrt_lib_modc__fn13 (param i32 i32) (result i32 i32)
    (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 1
    call $__malloc
    local.set 2
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 3
          local.get 1
          i32.ge_u
          br_if 2 (;@1;)
          local.get 0
          local.get 3
          i32.add
          i32.load8_u
          local.set 4
          local.get 4
          i32.const 97
          i32.ge_u
          local.get 4
          i32.const 122
          i32.le_u
          i32.and
          if  ;; label = @4
            local.get 4
            i32.const 32
            i32.sub
            local.set 4
          end
          local.get 2
          local.get 3
          i32.add
          local.get 4
          i32.store8
          local.get 3
          local.tee 5
          i32.const 1
          i32.add
          local.set 3
          br 1 (;@2;)
        end
      end
    end
    local.get 2
    local.get 1
    local.tee 6)
  (func $dynrt_lib_modc__fn14 (param i32 i32) (result i32 i32)
    (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 1
    call $__malloc
    local.set 2
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 3
          local.get 1
          i32.ge_u
          br_if 2 (;@1;)
          local.get 0
          local.get 3
          i32.add
          i32.load8_u
          local.set 4
          local.get 4
          i32.const 65
          i32.ge_u
          local.get 4
          i32.const 90
          i32.le_u
          i32.and
          if  ;; label = @4
            local.get 4
            i32.const 32
            i32.add
            local.set 4
          end
          local.get 2
          local.get 3
          i32.add
          local.get 4
          i32.store8
          local.get 3
          local.tee 5
          i32.const 1
          i32.add
          local.set 3
          br 1 (;@2;)
        end
      end
    end
    local.get 2
    local.get 1
    local.tee 6)
  (func $dynrt_lib_modc__fn15 (param i32 i32 i32 i32 i32) (result i32 i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 2
    local.get 1
    i32.le_s
    if  ;; label = @1
      block  ;; label = @2
        local.get 0
        local.get 1
        return
      end
    end
    local.get 2
    local.tee 12
    local.get 1
    i32.sub
    local.set 6
    local.get 2
    call $__malloc
    local.set 5
    local.get 4
    i32.eqz
    if  ;; label = @1
      i32.const 1
      local.set 4
    end
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 7
          local.get 6
          i32.ge_u
          br_if 2 (;@1;)
          local.get 7
          local.tee 9
          local.get 4
          i32.rem_u
          local.set 8
          local.get 5
          local.get 7
          i32.add
          local.get 3
          local.get 8
          i32.add
          i32.load8_u
          i32.store8
          local.get 7
          local.tee 10
          i32.const 1
          i32.add
          local.set 7
          br 1 (;@2;)
        end
      end
    end
    i32.const 0
    local.set 8
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 8
          local.get 1
          i32.ge_u
          br_if 2 (;@1;)
          local.get 5
          local.get 6
          local.get 8
          i32.add
          i32.add
          local.get 0
          local.get 8
          i32.add
          i32.load8_u
          i32.store8
          local.get 8
          local.tee 11
          i32.const 1
          i32.add
          local.set 8
          br 1 (;@2;)
        end
      end
    end
    local.get 5
    local.get 2
    local.tee 13)
  (func $dynrt_lib_modc__fn16 (param i32 i32 i32 i32 i32) (result i32 i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 2
    local.get 1
    i32.le_s
    if  ;; label = @1
      block  ;; label = @2
        local.get 0
        local.get 1
        return
      end
    end
    local.get 2
    local.tee 11
    local.get 1
    i32.sub
    drop
    local.get 2
    call $__malloc
    local.set 5
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 6
          local.get 1
          i32.ge_u
          br_if 2 (;@1;)
          local.get 5
          local.get 6
          i32.add
          local.get 0
          local.get 6
          i32.add
          i32.load8_u
          i32.store8
          local.get 6
          local.tee 8
          i32.const 1
          i32.add
          local.set 6
          br 1 (;@2;)
        end
      end
    end
    local.get 4
    i32.eqz
    if  ;; label = @1
      i32.const 1
      local.set 4
    end
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 6
          local.get 2
          i32.ge_u
          br_if 2 (;@1;)
          local.get 6
          local.tee 9
          local.get 1
          i32.sub
          local.get 4
          i32.rem_u
          local.set 7
          local.get 5
          local.get 6
          i32.add
          local.get 3
          local.get 7
          i32.add
          i32.load8_u
          i32.store8
          local.get 6
          local.tee 10
          i32.const 1
          i32.add
          local.set 6
          br 1 (;@2;)
        end
      end
    end
    local.get 5
    local.get 2
    local.tee 12)
  (func $dynrt_lib_modc__fn17 (param i32 i32 i32) (result i32 i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 2
    i32.const 0
    i32.le_s
    if  ;; label = @1
      block  ;; label = @2
        local.get 0
        i32.const 0
        return
      end
    end
    local.get 1
    local.get 2
    i32.mul
    local.set 4
    local.get 4
    call $__malloc
    local.set 3
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 5
          local.get 2
          i32.ge_u
          br_if 2 (;@1;)
          i32.const 0
          local.set 6
          block  ;; label = @4
            loop  ;; label = @5
              block  ;; label = @6
                local.get 6
                local.get 1
                i32.ge_u
                br_if 2 (;@4;)
                local.get 3
                local.get 5
                local.get 1
                i32.mul
                local.get 6
                i32.add
                i32.add
                local.get 0
                local.get 6
                i32.add
                i32.load8_u
                i32.store8
                local.get 6
                local.tee 7
                i32.const 1
                i32.add
                local.set 6
                br 1 (;@5;)
              end
            end
          end
          local.get 5
          i32.const 1
          i32.add
          local.set 5
          br 1 (;@2;)
        end
      end
    end
    local.get 3
    local.get 4
    local.tee 8)
  (func $dynrt_lib_modc__fn18 (param i32 i32 i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    i32.const 8
    local.tee 28
    local.set 5
    i32.const 8
    local.get 5
    i32.const 8
    i32.mul
    i32.add
    call $__malloc
    local.set 4
    local.get 4
    i32.const 0
    i32.store
    local.get 4
    local.get 5
    i32.store offset=4
    local.get 3
    i32.eqz
    if  ;; label = @1
      block  ;; label = @2
        local.get 4
        local.get 0
        i32.store offset=8
        local.get 4
        local.get 1
        i32.store offset=12
        local.get 4
        i32.const 1
        i32.store
        local.get 4
        local.tee 11
        return
      end
    end
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 0
          local.get 7
          i32.add
          local.get 1
          local.get 7
          i32.sub
          local.get 2
          local.get 3
          call $dynrt_lib_modc__fn7
          local.set 8
          local.get 8
          i32.const -1
          i32.eq
          if  ;; label = @4
            block  ;; label = @5
              local.get 0
              local.get 7
              local.tee 12
              i32.add
              local.set 9
              local.get 1
              local.get 12
              i32.sub
              local.set 10
              br 4 (;@1;)
            end
          end
          local.get 8
          local.tee 17
          local.get 7
          local.tee 18
          i32.add
          local.set 8
          local.get 0
          local.get 7
          i32.add
          local.tee 19
          local.set 9
          local.get 8
          local.tee 20
          local.get 18
          i32.sub
          local.set 10
          local.get 6
          local.get 5
          i32.ge_u
          if  ;; label = @4
            block  ;; label = @5
              local.get 5
              local.tee 13
              i32.const 2
              i32.mul
              local.set 5
              i32.const 8
              local.tee 14
              local.get 5
              local.tee 15
              local.get 14
              i32.mul
              i32.add
              local.set 7
              local.get 7
              call $__malloc
              local.set 7
              local.get 4
              i32.const 8
              local.get 6
              i32.const 8
              i32.mul
              i32.add
              local.get 7
              call $dynrt_lib_modc__fn4
              local.get 7
              local.tee 16
              local.set 4
              local.get 4
              local.get 5
              i32.store offset=4
            end
          end
          local.get 4
          i32.const 8
          local.get 6
          i32.const 8
          i32.mul
          i32.add
          i32.add
          local.get 9
          i32.store
          local.get 4
          i32.const 8
          local.get 6
          i32.const 8
          i32.mul
          i32.add
          i32.add
          local.get 10
          i32.store offset=4
          local.get 6
          local.tee 21
          i32.const 1
          i32.add
          local.set 6
          local.get 8
          local.tee 22
          local.get 3
          local.tee 23
          i32.add
          local.set 7
          local.get 7
          local.get 1
          i32.gt_u
          if  ;; label = @4
            br 3 (;@1;)
          end
          br 1 (;@2;)
        end
      end
    end
    local.get 6
    local.get 5
    i32.ge_u
    if  ;; label = @1
      block  ;; label = @2
        local.get 5
        local.tee 24
        i32.const 2
        i32.mul
        local.set 5
        i32.const 8
        local.tee 25
        local.get 5
        local.tee 26
        local.get 25
        i32.mul
        i32.add
        local.set 7
        local.get 7
        call $__malloc
        local.set 7
        local.get 4
        i32.const 8
        local.get 6
        i32.const 8
        i32.mul
        i32.add
        local.get 7
        call $dynrt_lib_modc__fn4
        local.get 7
        local.tee 27
        local.set 4
        local.get 4
        local.get 5
        i32.store offset=4
      end
    end
    local.get 4
    i32.const 8
    local.get 6
    i32.const 8
    i32.mul
    i32.add
    i32.add
    local.get 9
    i32.store
    local.get 4
    i32.const 8
    local.get 6
    i32.const 8
    i32.mul
    i32.add
    i32.add
    local.get 10
    i32.store offset=4
    local.get 6
    local.tee 29
    i32.const 1
    i32.add
    local.set 6
    local.get 4
    local.get 6
    i32.store
    local.get 4
    local.tee 30)
  (func $dynrt_lib_modc__fn19 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 1
    local.tee 16
    local.set 6
    local.get 16
    local.set 2
    local.get 0
    i32.eqz
    if  ;; label = @1
      block  ;; label = @2
        local.get 1
        i32.const 48
        i32.store8
        i32.const 1
        return
      end
    end
    local.get 0
    i32.const 0
    i32.lt_s
    if  ;; label = @1
      block  ;; label = @2
        local.get 1
        i32.const 45
        i32.store8
        local.get 1
        local.tee 7
        i32.const 1
        local.tee 8
        i32.add
        local.set 1
        local.get 1
        local.tee 9
        local.set 2
        i32.const 0
        local.get 0
        i32.sub
        local.set 0
      end
    end
    local.get 1
    local.tee 17
    local.set 3
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 0
          i32.eqz
          br_if 2 (;@1;)
          local.get 3
          i32.const 48
          local.get 0
          i32.const 10
          i32.rem_u
          i32.add
          i32.store8
          local.get 0
          local.tee 10
          i32.const 10
          local.tee 11
          i32.div_u
          local.set 0
          local.get 3
          local.tee 12
          i32.const 1
          i32.add
          local.set 3
          br 1 (;@2;)
        end
      end
    end
    local.get 2
    local.set 2
    local.get 3
    local.tee 18
    i32.const 1
    i32.sub
    local.set 4
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 2
          local.get 4
          i32.ge_u
          br_if 2 (;@1;)
          local.get 2
          i32.load8_u
          local.set 5
          local.get 2
          local.get 4
          i32.load8_u
          i32.store8
          local.get 4
          local.get 5
          i32.store8
          local.get 2
          local.tee 13
          i32.const 1
          local.tee 14
          i32.add
          local.set 2
          local.get 4
          local.tee 15
          local.get 14
          i32.sub
          local.set 4
          br 1 (;@2;)
        end
      end
    end
    local.get 3
    local.tee 19
    local.get 6
    i32.sub)
  (func $dynrt_lib_modc__fn20 (param i32)
    (local i32) (local i32)
    loop  ;; label = @1
      block  ;; label = @2
        local.get 0
        local.get 1
        i32.const 2
        i32.shl
        i32.add
        i32.const 0
        i32.store
        local.get 1
        local.tee 2
        i32.const 1
        i32.add
        local.set 1
        local.get 1
        i32.const 48
        i32.lt_u
        br_if 1 (;@1;)
      end
    end)
  (func $dynrt_lib_modc__fn21 (param i32 i64)
    local.get 0
    call $dynrt_lib_modc__fn20
    local.get 0
    local.get 1
    i64.const 4294967295
    i64.and
    i32.wrap_i64
    i32.store
    local.get 0
    local.get 1
    i64.const 32
    i64.shr_u
    i32.wrap_i64
    i32.store offset=4)
  (func $dynrt_lib_modc__fn22 (param i32 i32)
    (local i32) (local i64) (local i32) (local i32) (local i64) (local i64) (local i32)
    loop  ;; label = @1
      block  ;; label = @2
        local.get 0
        local.get 2
        local.tee 5
        i32.const 2
        i32.shl
        i32.add
        local.set 4
        local.get 4
        i32.load
        i64.extend_i32_u
        local.get 1
        i64.extend_i32_u
        i64.mul
        local.get 3
        local.tee 6
        i64.add
        local.set 3
        local.get 4
        local.get 3
        i64.const 4294967295
        i64.and
        i32.wrap_i64
        i32.store
        local.get 3
        local.tee 7
        i64.const 32
        i64.shr_u
        local.set 3
        local.get 2
        local.tee 8
        i32.const 1
        i32.add
        local.set 2
        local.get 2
        i32.const 48
        i32.lt_u
        br_if 1 (;@1;)
      end
    end)
  (func $dynrt_lib_modc__fn23 (param i32 i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 1
    local.tee 10
    i32.const 32
    local.tee 11
    i32.div_u
    local.set 2
    local.get 10
    local.get 11
    i32.rem_u
    local.set 3
    i32.const 47
    local.set 4
    loop  ;; label = @1
      block  ;; label = @2
        local.get 4
        local.tee 8
        local.get 2
        i32.sub
        local.set 5
        i32.const 0
        local.set 6
        local.get 5
        i32.const 0
        i32.ge_s
        if  ;; label = @3
          block  ;; label = @4
            local.get 0
            local.get 5
            i32.const 2
            i32.shl
            i32.add
            i32.load
            local.set 6
            local.get 3
            i32.eqz
            if  ;; label = @5
              local.get 6
              local.set 6
            else
              block  ;; label = @6
                local.get 6
                local.get 3
                i32.shl
                local.set 6
                local.get 5
                i32.const 0
                i32.gt_s
                if  ;; label = @7
                  block  ;; label = @8
                    local.get 0
                    local.get 5
                    i32.const 1
                    i32.sub
                    i32.const 2
                    i32.shl
                    i32.add
                    i32.load
                    local.set 5
                    local.get 6
                    local.get 5
                    local.tee 7
                    i32.const 32
                    local.get 3
                    i32.sub
                    i32.shr_u
                    i32.or
                    local.set 6
                  end
                end
              end
            end
          end
        end
        local.get 0
        local.get 4
        i32.const 2
        i32.shl
        i32.add
        local.get 6
        i32.store
        local.get 4
        local.tee 9
        i32.const 1
        i32.sub
        local.set 4
        local.get 4
        i32.const 0
        i32.ge_s
        br_if 1 (;@1;)
      end
    end)
  (func $dynrt_lib_modc__fn24 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32)
    i32.const 47
    local.set 2
    loop  ;; label = @1
      block  ;; label = @2
        local.get 0
        local.get 2
        i32.const 2
        i32.shl
        i32.add
        i32.load
        local.set 3
        local.get 1
        local.get 2
        i32.const 2
        i32.shl
        i32.add
        i32.load
        local.set 4
        local.get 3
        local.get 4
        i32.ne
        if  ;; label = @3
          i32.const 1
          i32.const -1
          local.get 3
          local.get 4
          i32.gt_u
          select
          return
        end
        local.get 2
        local.tee 5
        i32.const 1
        i32.sub
        local.set 2
        local.get 2
        i32.const 0
        i32.ge_s
        br_if 1 (;@1;)
      end
    end
    i32.const 0)
  (func $dynrt_lib_modc__fn25 (param i32 i32 i32)
    (local i32) (local i64) (local i64) (local i64) (local i32)
    loop  ;; label = @1
      block  ;; label = @2
        local.get 1
        local.get 3
        i32.const 2
        i32.shl
        i32.add
        i32.load
        i64.extend_i32_u
        local.get 2
        local.get 3
        i32.const 2
        i32.shl
        i32.add
        i32.load
        i64.extend_i32_u
        i64.add
        local.get 4
        local.tee 5
        i64.add
        local.set 4
        local.get 0
        local.get 3
        i32.const 2
        i32.shl
        i32.add
        local.get 4
        i64.const 4294967295
        i64.and
        i32.wrap_i64
        i32.store
        local.get 4
        local.tee 6
        i64.const 32
        i64.shr_u
        local.set 4
        local.get 3
        local.tee 7
        i32.const 1
        i32.add
        local.set 3
        local.get 3
        i32.const 48
        i32.lt_u
        br_if 1 (;@1;)
      end
    end)
  (func $dynrt_lib_modc__fn26 (param i32 i32 i32)
    (local i32) (local i64) (local i64) (local i64) (local i32)
    loop  ;; label = @1
      block  ;; label = @2
        local.get 1
        local.get 3
        i32.const 2
        i32.shl
        i32.add
        i32.load
        i64.extend_i32_u
        local.get 2
        local.get 3
        i32.const 2
        i32.shl
        i32.add
        i32.load
        i64.extend_i32_u
        i64.sub
        local.get 4
        local.tee 5
        i64.sub
        local.set 4
        local.get 0
        local.get 3
        i32.const 2
        i32.shl
        i32.add
        local.get 4
        i64.const 4294967295
        i64.and
        i32.wrap_i64
        i32.store
        local.get 4
        local.tee 6
        i64.const 63
        i64.shr_u
        i64.const 1
        i64.and
        local.set 4
        local.get 3
        local.tee 7
        i32.const 1
        i32.add
        local.set 3
        local.get 3
        i32.const 48
        i32.lt_u
        br_if 1 (;@1;)
      end
    end)
  (func $dynrt_lib_modc__fn27 (param f64 i32) (result i32)
    (local i64) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i64) (local i64) (local i64) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 1
    local.tee 49
    local.set 13
    local.get 0
    local.get 0
    f64.ne
    if  ;; label = @1
      block  ;; label = @2
        local.get 13
        i32.const 78
        i32.store8
        local.get 13
        i32.const 97
        i32.store8 offset=1
        local.get 13
        i32.const 78
        i32.store8 offset=2
        i32.const 3
        return
      end
    end
    local.get 0
    f64.const 0x0p+0 (;=0;)
    f64.lt
    if  ;; label = @1
      block  ;; label = @2
        local.get 13
        i32.const 45
        i32.store8
        local.get 13
        local.tee 16
        i32.const 1
        local.tee 17
        i32.add
        local.set 13
        local.get 0
        f64.neg
        local.set 0
      end
    end
    local.get 0
    f64.const inf (;=Infinity;)
    f64.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 13
        i32.const 73
        i32.store8
        local.get 13
        i32.const 110
        i32.store8 offset=1
        local.get 13
        i32.const 102
        i32.store8 offset=2
        local.get 13
        i32.const 105
        i32.store8 offset=3
        local.get 13
        i32.const 110
        i32.store8 offset=4
        local.get 13
        i32.const 105
        i32.store8 offset=5
        local.get 13
        i32.const 116
        i32.store8 offset=6
        local.get 13
        i32.const 121
        i32.store8 offset=7
        local.get 13
        local.tee 18
        local.get 1
        i32.sub
        i32.const 8
        i32.add
        return
      end
    end
    local.get 0
    f64.const 0x0p+0 (;=0;)
    f64.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 13
        i32.const 48
        i32.store8
        local.get 13
        local.tee 19
        local.get 1
        i32.sub
        i32.const 1
        i32.add
        return
      end
    end
    global.get $dynrt_lib_modc_global1
    i32.eqz
    if  ;; label = @1
      i32.const 1284
      call $__malloc
      global.set $dynrt_lib_modc_global1
    end
    global.get $dynrt_lib_modc_global1
    local.tee 50
    local.set 6
    local.get 50
    i32.const 192
    i32.add
    local.set 7
    local.get 50
    i32.const 644
    i32.add
    local.set 8
    local.get 50
    i32.const 836
    i32.add
    local.set 9
    local.get 50
    i32.const 1028
    i32.add
    local.set 10
    local.get 50
    i32.const 1220
    i32.add
    local.set 11
    local.get 0
    i64.reinterpret_f64
    local.set 2
    local.get 2
    local.tee 51
    i64.const 52
    i64.shr_u
    i64.const 2047
    i64.and
    i32.wrap_i64
    local.set 3
    local.get 2
    local.tee 52
    i64.const 4503599627370495
    i64.and
    local.set 2
    local.get 3
    i32.eqz
    if  ;; label = @1
      i32.const -1074
      local.set 3
    else
      block  ;; label = @2
        local.get 2
        i64.const 4503599627370496
        i64.or
        local.set 2
        local.get 3
        i32.const 1075
        i32.sub
        local.set 3
      end
    end
    local.get 2
    local.tee 53
    i64.const 1
    i64.and
    i32.wrap_i64
    i32.eqz
    local.set 4
    local.get 53
    i64.const 4503599627370496
    i64.eq
    local.set 5
    local.get 3
    i32.const 0
    i32.ge_s
    if  ;; label = @1
      block  ;; label = @2
        local.get 10
        i64.const 1
        call $dynrt_lib_modc__fn21
        local.get 10
        local.get 3
        call $dynrt_lib_modc__fn23
        local.get 5
        i32.eqz
        if  ;; label = @3
          block  ;; label = @4
            local.get 6
            local.get 2
            call $dynrt_lib_modc__fn21
            local.get 6
            local.get 3
            i32.const 1
            i32.add
            call $dynrt_lib_modc__fn23
            local.get 7
            i64.const 2
            call $dynrt_lib_modc__fn21
            local.get 8
            local.get 10
            i32.const 192
            memory.copy
            local.get 9
            local.get 10
            i32.const 192
            memory.copy
          end
        else
          block  ;; label = @4
            local.get 6
            local.get 2
            call $dynrt_lib_modc__fn21
            local.get 6
            local.get 3
            i32.const 2
            i32.add
            call $dynrt_lib_modc__fn23
            local.get 7
            i64.const 4
            call $dynrt_lib_modc__fn21
            local.get 8
            local.get 10
            i32.const 192
            memory.copy
            local.get 8
            i32.const 1
            call $dynrt_lib_modc__fn23
            local.get 9
            local.get 10
            i32.const 192
            memory.copy
          end
        end
      end
    else
      local.get 3
      i32.const -1074
      i32.eq
      local.get 5
      i32.eqz
      i32.or
      if  ;; label = @2
        block  ;; label = @3
          local.get 6
          local.get 2
          call $dynrt_lib_modc__fn21
          local.get 6
          i32.const 1
          call $dynrt_lib_modc__fn23
          local.get 7
          i64.const 1
          call $dynrt_lib_modc__fn21
          local.get 7
          i32.const 0
          local.get 3
          i32.sub
          i32.const 1
          i32.add
          call $dynrt_lib_modc__fn23
          local.get 8
          i64.const 1
          call $dynrt_lib_modc__fn21
          local.get 9
          i64.const 1
          call $dynrt_lib_modc__fn21
        end
      else
        block  ;; label = @3
          local.get 6
          local.get 2
          call $dynrt_lib_modc__fn21
          local.get 6
          i32.const 2
          call $dynrt_lib_modc__fn23
          local.get 7
          i64.const 1
          call $dynrt_lib_modc__fn21
          local.get 7
          i32.const 0
          local.get 3
          i32.sub
          i32.const 2
          i32.add
          call $dynrt_lib_modc__fn23
          local.get 8
          i64.const 2
          call $dynrt_lib_modc__fn21
          local.get 9
          i64.const 1
          call $dynrt_lib_modc__fn21
        end
      end
    end
    local.get 3
    local.tee 54
    i32.const 52
    i32.add
    f64.convert_i32_s
    f64.const 0x1.34413509f79fep-2 (;=0.30102999566398114;)
    f64.mul
    f64.ceil
    i32.trunc_f64_s
    local.set 3
    local.get 3
    i32.const 0
    i32.ge_s
    if  ;; label = @1
      block  ;; label = @2
        i32.const 0
        local.set 12
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 12
              local.get 3
              i32.ge_s
              br_if 2 (;@3;)
              local.get 7
              i32.const 10
              call $dynrt_lib_modc__fn22
              local.get 12
              i32.const 1
              i32.add
              local.set 12
              br 1 (;@4;)
            end
          end
        end
      end
    else
      block  ;; label = @2
        local.get 3
        local.set 12
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 12
              i32.const 0
              i32.ge_s
              br_if 2 (;@3;)
              local.get 6
              i32.const 10
              call $dynrt_lib_modc__fn22
              local.get 8
              i32.const 10
              call $dynrt_lib_modc__fn22
              local.get 9
              i32.const 10
              call $dynrt_lib_modc__fn22
              local.get 12
              i32.const 1
              i32.add
              local.set 12
              br 1 (;@4;)
            end
          end
        end
      end
    end
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 10
          local.get 6
          local.get 8
          call $dynrt_lib_modc__fn25
          local.get 10
          local.get 7
          call $dynrt_lib_modc__fn24
          local.set 14
          local.get 14
          i32.const 0
          i32.ge_s
          local.get 14
          i32.const 0
          i32.gt_s
          local.get 4
          select
          i32.eqz
          br_if 2 (;@1;)
          local.get 7
          i32.const 10
          call $dynrt_lib_modc__fn22
          local.get 3
          i32.const 1
          i32.add
          local.set 3
          br 1 (;@2;)
        end
      end
    end
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 10
          local.get 6
          local.get 8
          call $dynrt_lib_modc__fn25
          local.get 10
          i32.const 10
          call $dynrt_lib_modc__fn22
          local.get 10
          local.get 7
          call $dynrt_lib_modc__fn24
          local.set 14
          local.get 14
          i32.const 0
          i32.lt_s
          local.get 14
          i32.const 0
          i32.le_s
          local.get 4
          select
          i32.eqz
          br_if 2 (;@1;)
          local.get 6
          i32.const 10
          call $dynrt_lib_modc__fn22
          local.get 8
          i32.const 10
          call $dynrt_lib_modc__fn22
          local.get 9
          i32.const 10
          call $dynrt_lib_modc__fn22
          local.get 3
          i32.const 1
          i32.sub
          local.set 3
          br 1 (;@2;)
        end
      end
    end
    i32.const 0
    local.set 5
    loop  ;; label = @1
      block  ;; label = @2
        local.get 6
        i32.const 10
        call $dynrt_lib_modc__fn22
        local.get 8
        i32.const 10
        call $dynrt_lib_modc__fn22
        local.get 9
        i32.const 10
        call $dynrt_lib_modc__fn22
        i32.const 0
        local.set 12
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 6
              local.get 7
              call $dynrt_lib_modc__fn24
              i32.const 0
              i32.lt_s
              br_if 2 (;@3;)
              local.get 6
              local.get 6
              local.get 7
              call $dynrt_lib_modc__fn26
              local.get 12
              i32.const 1
              i32.add
              local.set 12
              br 1 (;@4;)
            end
          end
        end
        local.get 6
        local.get 9
        call $dynrt_lib_modc__fn24
        local.set 14
        local.get 14
        i32.const 0
        i32.le_s
        local.get 14
        i32.const 0
        i32.lt_s
        local.get 4
        select
        local.set 15
        local.get 10
        local.get 6
        local.get 8
        call $dynrt_lib_modc__fn25
        local.get 10
        local.get 7
        call $dynrt_lib_modc__fn24
        local.set 14
        local.get 14
        i32.const 0
        i32.ge_s
        local.get 14
        i32.const 0
        i32.gt_s
        local.get 4
        select
        local.set 14
        local.get 15
        i32.eqz
        local.get 14
        i32.eqz
        i32.and
        if  ;; label = @3
          block  ;; label = @4
            local.get 11
            local.get 5
            i32.add
            i32.const 48
            local.get 12
            i32.add
            i32.store8
            local.get 5
            local.tee 20
            i32.const 1
            i32.add
            local.set 5
            br 3 (;@1;)
          end
        end
        local.get 14
        local.get 15
        i32.eqz
        i32.and
        if  ;; label = @3
          local.get 12
          i32.const 1
          i32.add
          local.set 12
        else
          local.get 14
          local.get 15
          i32.and
          if  ;; label = @4
            block  ;; label = @5
              local.get 10
              local.get 6
              local.get 6
              call $dynrt_lib_modc__fn25
              local.get 10
              local.get 7
              call $dynrt_lib_modc__fn24
              local.set 14
              local.get 14
              i32.const 0
              i32.gt_s
              if  ;; label = @6
                local.get 12
                i32.const 1
                i32.add
                local.set 12
              else
                local.get 14
                i32.eqz
                if  ;; label = @7
                  local.get 12
                  i32.const 1
                  i32.and
                  if  ;; label = @8
                    local.get 12
                    i32.const 1
                    i32.add
                    local.set 12
                  end
                end
              end
            end
          end
        end
        local.get 11
        local.get 5
        i32.add
        i32.const 48
        local.get 12
        i32.add
        i32.store8
        local.get 5
        local.tee 21
        i32.const 1
        i32.add
        local.set 5
      end
    end
    local.get 3
    local.tee 55
    local.set 3
    local.get 3
    i32.const 21
    i32.gt_s
    if  ;; label = @1
      block  ;; label = @2
        local.get 13
        local.get 11
        i32.load8_u
        i32.store8
        local.get 13
        local.tee 26
        i32.const 1
        local.tee 27
        i32.add
        local.set 13
        local.get 5
        i32.const 1
        i32.gt_s
        if  ;; label = @3
          block  ;; label = @4
            local.get 13
            i32.const 46
            i32.store8
            local.get 13
            local.tee 22
            i32.const 1
            local.tee 23
            i32.add
            local.set 13
            local.get 13
            local.get 11
            i32.const 1
            i32.add
            local.get 5
            i32.const 1
            i32.sub
            memory.copy
            local.get 13
            local.tee 24
            local.get 5
            i32.const 1
            local.tee 25
            i32.sub
            i32.add
            local.set 13
          end
        end
        local.get 13
        i32.const 101
        i32.store8
        local.get 13
        i32.const 43
        i32.store8 offset=1
        local.get 13
        local.tee 28
        i32.const 2
        i32.add
        local.set 13
        local.get 13
        local.tee 29
        local.get 3
        i32.const 1
        i32.sub
        local.get 13
        call $dynrt_lib_modc__fn19
        i32.add
        local.set 13
        local.get 13
        local.tee 30
        local.get 1
        i32.sub
        return
      end
    end
    local.get 3
    i32.const -6
    i32.le_s
    if  ;; label = @1
      block  ;; label = @2
        local.get 13
        local.get 11
        i32.load8_u
        i32.store8
        local.get 13
        local.tee 35
        i32.const 1
        local.tee 36
        i32.add
        local.set 13
        local.get 5
        i32.const 1
        i32.gt_s
        if  ;; label = @3
          block  ;; label = @4
            local.get 13
            i32.const 46
            i32.store8
            local.get 13
            local.tee 31
            i32.const 1
            local.tee 32
            i32.add
            local.set 13
            local.get 13
            local.get 11
            i32.const 1
            i32.add
            local.get 5
            i32.const 1
            i32.sub
            memory.copy
            local.get 13
            local.tee 33
            local.get 5
            i32.const 1
            local.tee 34
            i32.sub
            i32.add
            local.set 13
          end
        end
        local.get 13
        i32.const 101
        i32.store8
        local.get 13
        i32.const 45
        i32.store8 offset=1
        local.get 13
        local.tee 37
        i32.const 2
        i32.add
        local.set 13
        local.get 13
        local.tee 38
        i32.const 1
        local.get 3
        i32.sub
        local.get 13
        call $dynrt_lib_modc__fn19
        i32.add
        local.set 13
        local.get 13
        local.tee 39
        local.get 1
        i32.sub
        return
      end
    end
    local.get 3
    i32.const 0
    i32.le_s
    if  ;; label = @1
      block  ;; label = @2
        local.get 13
        i32.const 48
        i32.store8
        local.get 13
        i32.const 46
        i32.store8 offset=1
        local.get 13
        local.tee 42
        i32.const 2
        i32.add
        local.set 13
        i32.const 0
        local.set 12
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 12
              i32.const 0
              local.get 3
              i32.sub
              i32.ge_s
              br_if 2 (;@3;)
              local.get 13
              i32.const 48
              i32.store8
              local.get 13
              local.tee 40
              i32.const 1
              local.tee 41
              i32.add
              local.set 13
              local.get 12
              local.get 41
              i32.add
              local.set 12
              br 1 (;@4;)
            end
          end
        end
        local.get 13
        local.get 11
        local.get 5
        memory.copy
        local.get 13
        local.tee 43
        local.get 5
        i32.add
        local.set 13
        local.get 13
        local.tee 44
        local.get 1
        i32.sub
        return
      end
    end
    local.get 3
    local.get 5
    i32.ge_s
    if  ;; label = @1
      block  ;; label = @2
        local.get 13
        local.get 11
        local.get 5
        memory.copy
        local.get 13
        local.tee 47
        local.get 5
        i32.add
        local.set 13
        i32.const 0
        local.set 12
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 12
              local.get 3
              local.get 5
              i32.sub
              i32.ge_s
              br_if 2 (;@3;)
              local.get 13
              i32.const 48
              i32.store8
              local.get 13
              local.tee 45
              i32.const 1
              local.tee 46
              i32.add
              local.set 13
              local.get 12
              local.get 46
              i32.add
              local.set 12
              br 1 (;@4;)
            end
          end
        end
        local.get 13
        local.tee 48
        local.get 1
        i32.sub
        return
      end
    end
    local.get 13
    local.get 11
    local.get 3
    memory.copy
    local.get 13
    local.tee 56
    local.get 3
    local.tee 57
    i32.add
    local.set 13
    local.get 13
    i32.const 46
    i32.store8
    local.get 13
    local.tee 58
    i32.const 1
    i32.add
    local.set 13
    local.get 13
    local.get 11
    local.get 3
    i32.add
    local.get 5
    local.get 3
    i32.sub
    memory.copy
    local.get 13
    local.tee 59
    local.get 5
    local.get 3
    local.tee 60
    i32.sub
    i32.add
    local.set 13
    local.get 13
    local.tee 61
    local.get 1
    local.tee 62
    i32.sub)
  (func $dynrt_lib_modc__fn28 (param f64 f64) (result f64)
    (local f64) (local i32)
    local.get 1
    f64.const 0x1.0p-1 (;=0.5;)
    f64.eq
    if  ;; label = @1
      local.get 0
      f64.sqrt
      return
    end
    local.get 1
    f64.const -0x1.0p-1 (;=-0.5;)
    f64.eq
    if  ;; label = @1
      f64.const 0x1.0p+0 (;=1;)
      local.get 0
      f64.sqrt
      f64.div
      return
    end
    f64.const 0x1.0p+0 (;=1;)
    local.set 2
    local.get 1
    i32.trunc_f64_s
    local.set 3
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 3
          i32.const 0
          i32.le_s
          br_if 2 (;@1;)
          local.get 2
          local.get 0
          f64.mul
          local.set 2
          local.get 3
          i32.const 1
          i32.sub
          local.set 3
          br 1 (;@2;)
        end
      end
    end
    local.get 2)
  (func $dynrt_lib_modc__fn29 (param i32 i32) (result f64)
    (local i32) (local i32) (local i32) (local f64) (local f64) (local f64) (local i32) (local i32) (local i32) (local i32) (local i32) (local f64) (local f64) (local i32) (local i32) (local i32) (local f64) (local f64) (local f64)
    f64.const 0x1.0p+0 (;=1;)
    local.tee 20
    local.set 5
    f64.const 0x0p+0 (;=0;)
    local.set 6
    local.get 20
    local.set 7
    i32.const 1
    local.set 8
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 2
          local.get 1
          i32.ge_u
          br_if 2 (;@1;)
          local.get 0
          local.get 2
          i32.add
          i32.load8_u
          local.set 3
          local.get 3
          i32.const 32
          i32.eq
          local.get 3
          i32.const 9
          i32.eq
          local.get 3
          i32.const 10
          i32.eq
          local.get 3
          i32.const 13
          i32.eq
          i32.or
          i32.or
          i32.or
          i32.eqz
          br_if 2 (;@1;)
          local.get 2
          local.tee 10
          i32.const 1
          i32.add
          local.set 2
          br 1 (;@2;)
        end
      end
    end
    local.get 2
    local.get 1
    i32.lt_u
    if  ;; label = @1
      block  ;; label = @2
        local.get 0
        local.get 2
        i32.add
        i32.load8_u
        local.set 3
        local.get 3
        i32.const 45
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            f64.const -0x1.0p+0 (;=-1;)
            local.set 5
            local.get 2
            i32.const 1
            i32.add
            local.set 2
          end
        else
          local.get 3
          i32.const 43
          i32.eq
          if  ;; label = @4
            local.get 2
            i32.const 1
            i32.add
            local.set 2
          end
        end
      end
    end
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 2
          local.get 1
          i32.ge_u
          br_if 2 (;@1;)
          local.get 0
          local.get 2
          i32.add
          i32.load8_u
          local.set 3
          local.get 3
          i32.const 48
          i32.lt_u
          local.get 3
          i32.const 57
          i32.gt_u
          i32.or
          br_if 2 (;@1;)
          local.get 6
          f64.const 0x1.4p+3 (;=10;)
          f64.mul
          local.get 3
          i32.const 48
          i32.sub
          f64.convert_i32_s
          f64.add
          local.set 6
          local.get 4
          i32.const 1
          local.tee 11
          i32.add
          local.set 4
          local.get 2
          local.tee 12
          local.get 11
          i32.add
          local.set 2
          br 1 (;@2;)
        end
      end
    end
    local.get 2
    local.get 1
    i32.lt_u
    if  ;; label = @1
      local.get 0
      local.get 2
      i32.add
      i32.load8_u
      i32.const 46
      i32.eq
      if  ;; label = @2
        block  ;; label = @3
          local.get 2
          i32.const 1
          i32.add
          local.set 2
          block  ;; label = @4
            loop  ;; label = @5
              block  ;; label = @6
                local.get 2
                local.get 1
                i32.ge_u
                br_if 2 (;@4;)
                local.get 0
                local.get 2
                i32.add
                i32.load8_u
                local.set 3
                local.get 3
                i32.const 48
                i32.lt_u
                local.get 3
                i32.const 57
                i32.gt_u
                i32.or
                br_if 2 (;@4;)
                local.get 7
                local.tee 13
                f64.const 0x1.4p+3 (;=10;)
                f64.mul
                local.set 7
                local.get 6
                local.get 3
                i32.const 48
                i32.sub
                f64.convert_i32_s
                local.get 7
                local.tee 14
                f64.div
                f64.add
                local.set 6
                local.get 4
                i32.const 1
                local.tee 15
                i32.add
                local.set 4
                local.get 2
                local.tee 16
                local.get 15
                i32.add
                local.set 2
                br 1 (;@5;)
              end
            end
          end
        end
      end
    end
    local.get 4
    i32.const 0
    i32.gt_s
    local.get 2
    local.get 1
    i32.lt_u
    i32.and
    if  ;; label = @1
      block  ;; label = @2
        local.get 0
        local.get 2
        i32.add
        i32.load8_u
        local.set 3
        local.get 3
        i32.const 101
        i32.eq
        local.get 3
        i32.const 69
        i32.eq
        i32.or
        if  ;; label = @3
          block  ;; label = @4
            local.get 2
            i32.const 1
            i32.add
            local.set 2
            local.get 2
            local.get 1
            i32.lt_u
            if  ;; label = @5
              block  ;; label = @6
                local.get 0
                local.get 2
                i32.add
                i32.load8_u
                local.set 3
                local.get 3
                i32.const 45
                i32.eq
                if  ;; label = @7
                  block  ;; label = @8
                    i32.const -1
                    local.set 8
                    local.get 2
                    i32.const 1
                    i32.add
                    local.set 2
                  end
                else
                  local.get 3
                  i32.const 43
                  i32.eq
                  if  ;; label = @8
                    local.get 2
                    i32.const 1
                    i32.add
                    local.set 2
                  end
                end
              end
            end
            block  ;; label = @5
              loop  ;; label = @6
                block  ;; label = @7
                  local.get 2
                  local.get 1
                  i32.ge_u
                  br_if 2 (;@5;)
                  local.get 0
                  local.get 2
                  i32.add
                  i32.load8_u
                  local.set 3
                  local.get 3
                  i32.const 48
                  i32.lt_u
                  local.get 3
                  i32.const 57
                  i32.gt_u
                  i32.or
                  br_if 2 (;@5;)
                  local.get 9
                  i32.const 10
                  i32.mul
                  local.get 3
                  i32.const 48
                  i32.sub
                  i32.add
                  local.set 9
                  local.get 2
                  local.tee 17
                  i32.const 1
                  i32.add
                  local.set 2
                  br 1 (;@6;)
                end
              end
            end
          end
        end
      end
    end
    local.get 4
    i32.eqz
    if (result f64)  ;; label = @1
      f64.const nan (;=NaN;)
    else
      block (result f64)  ;; label = @2
        local.get 5
        local.get 6
        local.tee 18
        f64.mul
        local.set 6
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 9
              i32.eqz
              br_if 2 (;@3;)
              local.get 8
              i32.const 0
              i32.gt_s
              if  ;; label = @6
                local.get 6
                f64.const 0x1.4p+3 (;=10;)
                f64.mul
                local.set 6
              else
                local.get 6
                f64.const 0x1.4p+3 (;=10;)
                f64.div
                local.set 6
              end
              local.get 9
              i32.const 1
              i32.sub
              local.set 9
              br 1 (;@4;)
            end
          end
        end
        local.get 6
        local.tee 19
      end
    end)
  (func $dynrt_lib_modc_dynUndefined (result i32)
    (local i32) (local i32)
    call $dynrt_lib_modc__fn53
    local.set 0
    local.get 0
    i32.const 8
    i32.add
    i32.const 0
    i32.store
    local.get 0
    local.tee 1
    return)
  (func $dynrt_lib_modc_dynNull (result i32)
    (local i32) (local i32)
    call $dynrt_lib_modc__fn53
    local.set 0
    local.get 0
    i32.const 8
    i32.add
    i32.const 1
    i32.store
    local.get 0
    local.tee 1
    return)
  (func $dynrt_lib_modc_dynBool (param i32) (result i32)
    (local i32) (local i32)
    call $dynrt_lib_modc__fn53
    local.set 1
    local.get 1
    i32.const 8
    i32.add
    i32.const 2
    i32.store
    local.get 1
    i32.const 8
    i32.add
    i32.const 4
    i32.add
    local.get 0
    i32.eqz
    if (result i32)  ;; label = @1
      i32.const 0
    else
      i32.const 1
    end
    i32.store
    local.get 1
    local.tee 2
    return)
  (func $dynrt_lib_modc_dynNumber (param f64) (result i32)
    (local i32) (local i32) (local i32)
    i32.const 16
    call $dynrt_lib_modc__fn45
    local.set 1
    local.get 1
    i32.const 8
    i32.add
    local.get 0
    f64.store
    call $dynrt_lib_modc__fn53
    local.set 2
    local.get 2
    i32.const 8
    i32.add
    i32.const 3
    i32.store
    local.get 2
    i32.const 8
    i32.add
    i32.const 4
    i32.add
    local.get 1
    i32.store
    local.get 2
    local.tee 3
    return)
  (func $dynrt_lib_modc_dynString (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 1
    local.set 2
    i32.const 8
    local.get 2
    i32.add
    call $dynrt_lib_modc__fn45
    local.set 3
    i32.const 0
    local.set 4
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 4
          local.get 2
          i32.lt_s
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 3
            i32.const 8
            i32.add
            local.get 4
            i32.add
            local.get 0
            local.get 1
            local.get 4
            call $dynrt_lib_modc__fn9
            i32.store8
            local.get 4
            local.tee 5
            i32.const 1
            i32.add
            local.set 4
          end
          br 1 (;@2;)
        end
      end
    end
    call $dynrt_lib_modc__fn53
    local.set 4
    local.get 4
    i32.const 8
    i32.add
    i32.const 4
    i32.store
    local.get 4
    i32.const 8
    i32.add
    i32.const 4
    i32.add
    local.get 3
    i32.store
    local.get 4
    i32.const 8
    i32.add
    i32.const 8
    i32.add
    local.get 2
    i32.store
    local.get 4
    local.tee 6
    return)
  (func $dynrt_lib_modc__fn35 (result i32)
    (local i32) (local i32)
    i32.const 8
    global.get $dynrt_lib_modc_global4
    i32.const 2
    i32.add
    i32.const 4
    i32.mul
    i32.add
    call $dynrt_lib_modc__fn45
    local.set 0
    local.get 0
    i32.const 8
    i32.add
    i32.const 0
    i32.store
    local.get 0
    i32.const 8
    i32.add
    i32.const 4
    i32.add
    global.get $dynrt_lib_modc_global4
    i32.store
    local.get 0
    local.tee 1
    return)
  (func $dynrt_lib_modc__fn36 (param i32) (result i32)
    (local i32)
    local.get 0
    local.set 1
    local.get 1
    i32.const 8
    i32.add
    i32.load
    return)
  (func $dynrt_lib_modc__fn37 (param i32 i32) (result i32)
    (local i32)
    local.get 0
    local.set 2
    local.get 2
    i32.const 8
    i32.add
    local.get 1
    i32.const 2
    i32.add
    i32.const 2
    i32.shl
    i32.add
    i32.load
    return)
  (func $dynrt_lib_modc__fn38 (param i32 i32 i32)
    (local i32)
    local.get 0
    local.set 3
    local.get 3
    i32.const 8
    i32.add
    local.get 1
    i32.const 2
    i32.add
    i32.const 2
    i32.shl
    i32.add
    local.get 2
    i32.store)
  (func $dynrt_lib_modc__fn39 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.tee 10
    local.set 2
    local.get 2
    i32.const 8
    i32.add
    i32.load
    local.set 3
    local.get 2
    i32.const 8
    i32.add
    i32.const 4
    i32.add
    i32.load
    local.set 4
    local.get 3
    local.get 4
    i32.ge_s
    if  ;; label = @1
      block  ;; label = @2
        local.get 4
        local.tee 7
        i32.const 2
        local.tee 8
        i32.mul
        local.set 4
        i32.const 8
        local.get 4
        i32.const 2
        i32.add
        i32.const 4
        i32.mul
        i32.add
        call $dynrt_lib_modc__fn45
        local.set 5
        local.get 5
        i32.const 8
        i32.add
        i32.const 4
        i32.add
        local.get 4
        i32.store
        i32.const 0
        local.set 4
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 4
              local.get 3
              i32.lt_s
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                local.get 5
                i32.const 8
                i32.add
                local.get 4
                i32.const 2
                i32.add
                i32.const 2
                i32.shl
                i32.add
                local.get 2
                i32.const 8
                i32.add
                local.get 4
                i32.const 2
                i32.add
                i32.const 2
                i32.shl
                i32.add
                i32.load
                i32.store
                local.get 4
                local.tee 6
                i32.const 1
                i32.add
                local.set 4
              end
              br 1 (;@4;)
            end
          end
        end
        local.get 5
        i32.const 8
        i32.add
        local.get 3
        i32.const 2
        i32.add
        i32.const 2
        i32.shl
        i32.add
        local.get 1
        i32.store
        local.get 5
        i32.const 8
        i32.add
        local.get 3
        i32.const 1
        i32.add
        i32.store
        local.get 5
        local.tee 9
        return
      end
    end
    local.get 2
    i32.const 8
    i32.add
    local.get 3
    i32.const 2
    i32.add
    i32.const 2
    i32.shl
    i32.add
    local.get 1
    i32.store
    local.get 2
    i32.const 8
    i32.add
    local.get 3
    i32.const 1
    i32.add
    i32.store
    local.get 0
    local.tee 11
    return)
  (func $dynrt_lib_modc__fn40 (param i32 i32)
    (local i32) (local i32)
    local.get 0
    local.set 2
    local.get 2
    i32.const 8
    i32.add
    local.get 1
    i32.store
    local.get 1
    i32.const 16
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 2
        i32.const 8
        i32.add
        i32.const 4
        i32.add
        global.get $dynrt_lib_modc_global7
        i32.store
        local.get 0
        global.set $dynrt_lib_modc_global7
      end
    else
      local.get 1
      i32.const 24
      i32.eq
      if  ;; label = @2
        block  ;; label = @3
          local.get 2
          i32.const 8
          i32.add
          i32.const 4
          i32.add
          global.get $dynrt_lib_modc_global8
          i32.store
          local.get 0
          global.set $dynrt_lib_modc_global8
        end
      else
        local.get 1
        i32.const 28
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 2
            i32.const 8
            i32.add
            i32.const 4
            i32.add
            global.get $dynrt_lib_modc_global9
            i32.store
            local.get 0
            global.set $dynrt_lib_modc_global9
          end
        else
          local.get 1
          i32.const 32
          i32.eq
          if  ;; label = @4
            block  ;; label = @5
              local.get 2
              i32.const 8
              i32.add
              i32.const 4
              i32.add
              global.get $dynrt_lib_modc_global10
              i32.store
              local.get 0
              global.set $dynrt_lib_modc_global10
            end
          else
            block  ;; label = @5
              local.get 2
              i32.const 8
              i32.add
              i32.const 4
              i32.add
              global.get $dynrt_lib_modc_global11
              i32.store
              local.get 0
              global.set $dynrt_lib_modc_global11
            end
          end
        end
      end
    end
    global.get $dynrt_lib_modc_global12
    i32.const 1
    i32.add
    global.set $dynrt_lib_modc_global12
    global.get $dynrt_lib_modc_global13
    local.get 1
    local.tee 3
    i32.add
    global.set $dynrt_lib_modc_global13)
  (func $dynrt_lib_modc__fn41 (param i32 i32)
    (local i32)
    local.get 1
    global.get $dynrt_lib_modc_global5
    i32.lt_s
    if (result i32)  ;; label = @1
      global.get $dynrt_lib_modc_global5
    else
      local.get 1
    end
    local.set 2
    local.get 0
    local.get 2
    call $dynrt_lib_modc__fn40
    global.get $dynrt_lib_modc_global12
    global.get $dynrt_lib_modc_global14
    i32.gt_s
    if  ;; label = @1
      call $dynrt_lib_modc__fn50
    end)
  (func $dynrt_lib_modc__fn42 (param i32 i32)
    (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.set 2
    local.get 1
    i32.const 8
    i32.sub
    i32.const 2
    i32.shr_s
    local.set 3
    i32.const 0
    local.set 4
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 4
          local.get 3
          i32.lt_s
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 2
            i32.const 8
            i32.add
            local.get 4
            i32.const 2
            i32.shl
            i32.add
            i32.const 0
            i32.store
            local.get 4
            local.tee 5
            i32.const 1
            i32.add
            local.set 4
          end
          br 1 (;@2;)
        end
      end
    end)
  (func $dynrt_lib_modc__fn43 (param i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32)
    i32.const 0
    local.set 1
    local.get 0
    i32.const 16
    i32.eq
    if  ;; label = @1
      global.get $dynrt_lib_modc_global7
      local.set 1
    else
      local.get 0
      i32.const 24
      i32.eq
      if  ;; label = @2
        global.get $dynrt_lib_modc_global8
        local.set 1
      else
        local.get 0
        i32.const 28
        i32.eq
        if  ;; label = @3
          global.get $dynrt_lib_modc_global9
          local.set 1
        else
          local.get 0
          i32.const 32
          i32.eq
          if  ;; label = @4
            global.get $dynrt_lib_modc_global10
            local.set 1
          end
        end
      end
    end
    local.get 1
    i32.eqz
    if  ;; label = @1
      i32.const 0
      return
    end
    local.get 1
    local.tee 3
    local.set 2
    local.get 2
    i32.const 8
    i32.add
    i32.const 4
    i32.add
    i32.load
    local.set 2
    local.get 0
    i32.const 16
    i32.eq
    if  ;; label = @1
      local.get 2
      global.set $dynrt_lib_modc_global7
    else
      local.get 0
      i32.const 24
      i32.eq
      if  ;; label = @2
        local.get 2
        global.set $dynrt_lib_modc_global8
      else
        local.get 0
        i32.const 28
        i32.eq
        if  ;; label = @3
          local.get 2
          global.set $dynrt_lib_modc_global9
        else
          local.get 2
          global.set $dynrt_lib_modc_global10
        end
      end
    end
    global.get $dynrt_lib_modc_global12
    i32.const 1
    i32.sub
    global.set $dynrt_lib_modc_global12
    global.get $dynrt_lib_modc_global13
    local.get 0
    local.tee 4
    i32.sub
    global.set $dynrt_lib_modc_global13
    local.get 1
    local.get 0
    call $dynrt_lib_modc__fn42
    local.get 1
    local.tee 5
    return)
  (func $dynrt_lib_modc__fn44 (param i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    global.get $dynrt_lib_modc_global11
    local.set 1
    i32.const 0
    local.tee 12
    local.set 2
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 1
          i32.const 0
          i32.ne
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 1
            local.tee 10
            local.set 3
            local.get 3
            i32.const 8
            i32.add
            i32.load
            local.set 4
            local.get 4
            local.get 0
            i32.ge_s
            if  ;; label = @5
              block  ;; label = @6
                local.get 3
                i32.const 8
                i32.add
                i32.const 4
                i32.add
                i32.load
                local.set 3
                local.get 2
                i32.eqz
                if  ;; label = @7
                  local.get 3
                  global.set $dynrt_lib_modc_global11
                else
                  block  ;; label = @8
                    local.get 2
                    local.tee 5
                    local.set 2
                    local.get 2
                    i32.const 8
                    i32.add
                    i32.const 4
                    i32.add
                    local.get 3
                    i32.store
                  end
                end
                global.get $dynrt_lib_modc_global12
                i32.const 1
                i32.sub
                global.set $dynrt_lib_modc_global12
                global.get $dynrt_lib_modc_global13
                local.get 4
                local.tee 6
                i32.sub
                global.set $dynrt_lib_modc_global13
                local.get 4
                local.tee 7
                local.get 0
                local.tee 8
                i32.sub
                local.set 2
                local.get 2
                global.get $dynrt_lib_modc_global5
                i32.ge_s
                if  ;; label = @7
                  local.get 1
                  local.get 0
                  i32.add
                  local.get 2
                  call $dynrt_lib_modc__fn40
                end
                local.get 1
                local.get 0
                call $dynrt_lib_modc__fn42
                local.get 1
                local.tee 9
                return
              end
            end
            local.get 1
            local.tee 11
            local.set 2
            local.get 3
            i32.const 8
            i32.add
            i32.const 4
            i32.add
            i32.load
            local.set 1
          end
          br 1 (;@2;)
        end
      end
    end
    i32.const 0
    local.tee 13
    return)
  (func $dynrt_lib_modc__fn45 (param i32) (result i32)
    (local i32) (local i32)
    local.get 0
    global.get $dynrt_lib_modc_global5
    i32.lt_s
    if (result i32)  ;; label = @1
      global.get $dynrt_lib_modc_global5
    else
      local.get 0
    end
    local.set 1
    local.get 1
    call $dynrt_lib_modc__fn43
    local.set 2
    local.get 2
    i32.const 0
    i32.ne
    if  ;; label = @1
      local.get 2
      return
    end
    local.get 1
    call $dynrt_lib_modc__fn44
    local.set 2
    local.get 2
    i32.const 0
    i32.ne
    if  ;; label = @1
      local.get 2
      return
    end
    global.get $dynrt_lib_modc_global13
    local.get 1
    i32.ge_s
    if  ;; label = @1
      block  ;; label = @2
        call $dynrt_lib_modc__fn50
        local.get 1
        call $dynrt_lib_modc__fn43
        local.set 2
        local.get 2
        i32.const 0
        i32.ne
        if  ;; label = @3
          local.get 2
          return
        end
        local.get 1
        call $dynrt_lib_modc__fn44
        local.set 2
        local.get 2
        i32.const 0
        i32.ne
        if  ;; label = @3
          local.get 2
          return
        end
      end
    end
    local.get 1
    call $__malloc
    return)
  (func $dynrt_lib_modc__fn46 (param i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.tee 6
    local.set 1
    local.get 6
    local.set 2
    local.get 2
    i32.const 8
    i32.add
    i32.const 4
    i32.add
    i32.load
    local.set 2
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 2
          i32.const 0
          i32.ne
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 2
            local.tee 5
            local.set 2
            local.get 2
            i32.const 8
            i32.add
            i32.const 4
            i32.add
            i32.load
            local.set 2
            local.get 2
            i32.const 0
            i32.ne
            if  ;; label = @5
              block  ;; label = @6
                local.get 1
                local.tee 3
                local.set 1
                local.get 1
                i32.const 8
                i32.add
                i32.const 4
                i32.add
                i32.load
                local.set 1
                local.get 2
                local.tee 4
                local.set 2
                local.get 2
                i32.const 8
                i32.add
                i32.const 4
                i32.add
                i32.load
                local.set 2
              end
            end
          end
          br 1 (;@2;)
        end
      end
    end
    local.get 1
    local.tee 7
    local.set 1
    local.get 1
    i32.const 8
    i32.add
    i32.const 4
    i32.add
    i32.load
    local.set 2
    local.get 1
    i32.const 8
    i32.add
    i32.const 4
    i32.add
    i32.const 0
    i32.store
    local.get 2
    local.tee 8
    return)
  (func $dynrt_lib_modc__fn47 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    i32.const 0
    local.tee 11
    local.set 2
    local.get 11
    local.set 3
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 0
          i32.const 0
          i32.ne
          if (result i32)  ;; label = @4
            local.get 1
            i32.const 0
            i32.ne
          else
            i32.const 0
          end
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 0
            local.get 1
            i32.lt_s
            if  ;; label = @5
              block  ;; label = @6
                local.get 0
                local.tee 6
                local.set 4
                local.get 6
                local.set 5
                local.get 5
                i32.const 8
                i32.add
                i32.const 4
                i32.add
                i32.load
                local.set 0
              end
            else
              block  ;; label = @6
                local.get 1
                local.tee 7
                local.set 4
                local.get 7
                local.set 5
                local.get 5
                i32.const 8
                i32.add
                i32.const 4
                i32.add
                i32.load
                local.set 1
              end
            end
            local.get 2
            i32.eqz
            if  ;; label = @5
              block  ;; label = @6
                local.get 4
                local.tee 8
                local.set 2
                local.get 8
                local.set 3
              end
            else
              block  ;; label = @6
                local.get 3
                local.tee 9
                local.set 3
                local.get 3
                i32.const 8
                i32.add
                i32.const 4
                i32.add
                local.get 4
                i32.store
                local.get 4
                local.tee 10
                local.set 3
              end
            end
          end
          br 1 (;@2;)
        end
      end
    end
    local.get 0
    local.set 4
    local.get 0
    i32.eqz
    if  ;; label = @1
      local.get 1
      local.set 4
    end
    local.get 2
    i32.eqz
    if  ;; label = @1
      local.get 4
      return
    end
    local.get 3
    local.tee 12
    local.set 3
    local.get 3
    i32.const 8
    i32.add
    i32.const 4
    i32.add
    local.get 4
    i32.store
    local.get 2
    return)
  (func $dynrt_lib_modc__fn48 (param i32) (result i32)
    (local i32) (local i32) (local i32)
    local.get 0
    i32.eqz
    if  ;; label = @1
      i32.const 0
      return
    end
    local.get 0
    local.tee 3
    local.set 1
    local.get 1
    i32.const 8
    i32.add
    i32.const 4
    i32.add
    i32.load
    i32.eqz
    if  ;; label = @1
      local.get 0
      return
    end
    local.get 0
    call $dynrt_lib_modc__fn46
    local.set 1
    local.get 0
    call $dynrt_lib_modc__fn48
    local.set 2
    local.get 1
    call $dynrt_lib_modc__fn48
    local.set 1
    local.get 2
    local.get 1
    call $dynrt_lib_modc__fn47
    return)
  (func $dynrt_lib_modc__fn49 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.set 2
    local.get 1
    local.set 3
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 2
          i32.const 0
          i32.ne
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 2
            local.tee 6
            local.set 4
            local.get 4
            i32.const 8
            i32.add
            i32.const 4
            i32.add
            i32.load
            local.set 5
            local.get 4
            i32.const 8
            i32.add
            i32.const 4
            i32.add
            local.get 3
            i32.store
            local.get 2
            local.tee 7
            local.set 3
            local.get 5
            local.set 2
          end
          br 1 (;@2;)
        end
      end
    end
    local.get 3
    return)
  (func $dynrt_lib_modc__fn50
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    i32.const 0
    local.tee 7
    local.set 0
    global.get $dynrt_lib_modc_global7
    local.get 0
    call $dynrt_lib_modc__fn49
    local.set 0
    global.get $dynrt_lib_modc_global8
    local.get 0
    call $dynrt_lib_modc__fn49
    local.set 0
    global.get $dynrt_lib_modc_global9
    local.get 0
    call $dynrt_lib_modc__fn49
    local.set 0
    global.get $dynrt_lib_modc_global10
    local.get 0
    call $dynrt_lib_modc__fn49
    local.set 0
    global.get $dynrt_lib_modc_global11
    local.get 0
    call $dynrt_lib_modc__fn49
    local.set 0
    i32.const 0
    local.tee 8
    global.set $dynrt_lib_modc_global7
    i32.const 0
    local.tee 9
    global.set $dynrt_lib_modc_global8
    i32.const 0
    local.tee 10
    global.set $dynrt_lib_modc_global9
    i32.const 0
    local.tee 11
    global.set $dynrt_lib_modc_global10
    i32.const 0
    local.tee 12
    global.set $dynrt_lib_modc_global11
    i32.const 0
    local.tee 13
    global.set $dynrt_lib_modc_global12
    i32.const 0
    local.tee 14
    global.set $dynrt_lib_modc_global13
    local.get 0
    call $dynrt_lib_modc__fn48
    local.set 0
    local.get 0
    local.tee 15
    local.set 1
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 1
          i32.const 0
          i32.ne
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 1
            local.set 2
            local.get 2
            i32.const 8
            i32.add
            i32.const 4
            i32.add
            i32.load
            local.set 3
            i32.const 1
            local.set 4
            block  ;; label = @5
              loop  ;; label = @6
                block  ;; label = @7
                  local.get 4
                  i32.const 1
                  i32.eq
                  if (result i32)  ;; label = @8
                    local.get 3
                    i32.const 0
                    i32.ne
                  else
                    i32.const 0
                  end
                  i32.eqz
                  br_if 2 (;@5;)
                  block  ;; label = @8
                    local.get 3
                    local.set 5
                    local.get 1
                    local.get 2
                    i32.const 8
                    i32.add
                    i32.load
                    i32.add
                    local.get 3
                    i32.eq
                    if  ;; label = @9
                      block  ;; label = @10
                        local.get 2
                        i32.const 8
                        i32.add
                        local.get 2
                        i32.const 8
                        i32.add
                        i32.load
                        local.get 5
                        i32.const 8
                        i32.add
                        i32.load
                        i32.add
                        i32.store
                        local.get 2
                        i32.const 8
                        i32.add
                        i32.const 4
                        i32.add
                        local.get 5
                        i32.const 8
                        i32.add
                        i32.const 4
                        i32.add
                        i32.load
                        i32.store
                        local.get 2
                        i32.const 8
                        i32.add
                        i32.const 4
                        i32.add
                        i32.load
                        local.set 3
                      end
                    else
                      i32.const 0
                      local.set 4
                    end
                  end
                  br 1 (;@6;)
                end
              end
            end
            local.get 2
            i32.const 8
            i32.add
            i32.const 4
            i32.add
            i32.load
            local.set 1
          end
          br 1 (;@2;)
        end
      end
    end
    local.get 0
    local.tee 16
    local.set 0
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 0
          i32.const 0
          i32.ne
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 0
            local.tee 6
            local.set 1
            local.get 1
            i32.const 8
            i32.add
            i32.const 4
            i32.add
            i32.load
            local.set 2
            local.get 1
            i32.const 8
            i32.add
            i32.load
            local.set 1
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn40
            local.get 2
            local.set 0
          end
          br 1 (;@2;)
        end
      end
    end
    global.get $dynrt_lib_modc_global12
    i32.const 2
    i32.mul
    local.set 0
    local.get 0
    global.get $dynrt_lib_modc_global6
    i32.lt_s
    if  ;; label = @1
      global.get $dynrt_lib_modc_global6
      local.set 0
    end
    local.get 0
    local.tee 17
    global.set $dynrt_lib_modc_global14)
  (func $dynrt_lib_modc_dynGcCheckHeap (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    i32.const 0
    local.tee 7
    local.set 0
    local.get 7
    local.set 1
    i32.const 100000000
    local.set 2
    local.get 7
    local.set 3
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 3
          i32.const 5
          i32.lt_s
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 3
            i32.eqz
            if  ;; label = @5
              global.get $dynrt_lib_modc_global7
              local.set 4
            else
              local.get 3
              i32.const 1
              i32.eq
              if  ;; label = @6
                global.get $dynrt_lib_modc_global8
                local.set 4
              else
                local.get 3
                i32.const 2
                i32.eq
                if  ;; label = @7
                  global.get $dynrt_lib_modc_global9
                  local.set 4
                else
                  local.get 3
                  i32.const 3
                  i32.eq
                  if  ;; label = @8
                    global.get $dynrt_lib_modc_global10
                    local.set 4
                  else
                    global.get $dynrt_lib_modc_global11
                    local.set 4
                  end
                end
              end
            end
            block  ;; label = @5
              loop  ;; label = @6
                block  ;; label = @7
                  local.get 4
                  i32.const 0
                  i32.ne
                  i32.eqz
                  br_if 2 (;@5;)
                  block  ;; label = @8
                    local.get 2
                    i32.const 0
                    i32.le_s
                    if  ;; label = @9
                      i32.const 1
                      return
                    end
                    local.get 2
                    i32.const 1
                    local.tee 5
                    i32.sub
                    local.set 2
                    local.get 4
                    local.tee 6
                    local.set 4
                    local.get 4
                    i32.const 8
                    i32.add
                    i32.load
                    global.get $dynrt_lib_modc_global5
                    i32.lt_s
                    if  ;; label = @9
                      i32.const 4
                      return
                    end
                    local.get 1
                    local.get 4
                    i32.const 8
                    i32.add
                    i32.load
                    i32.add
                    local.set 1
                    local.get 0
                    local.get 5
                    i32.add
                    local.set 0
                    local.get 4
                    i32.const 8
                    i32.add
                    i32.const 4
                    i32.add
                    i32.load
                    local.set 4
                  end
                  br 1 (;@6;)
                end
              end
            end
            local.get 3
            i32.const 1
            i32.add
            local.set 3
          end
          br 1 (;@2;)
        end
      end
    end
    local.get 0
    global.get $dynrt_lib_modc_global12
    i32.ne
    if  ;; label = @1
      i32.const 2
      return
    end
    local.get 1
    global.get $dynrt_lib_modc_global13
    i32.ne
    if  ;; label = @1
      i32.const 3
      return
    end
    local.get 7
    return)
  (func $dynrt_lib_modc__fn52 (param i32)
    global.get $dynrt_lib_modc_global16
    i32.eqz
    if  ;; label = @1
      call $dynrt_lib_modc__fn35
      global.set $dynrt_lib_modc_global16
    end
    global.get $dynrt_lib_modc_global16
    local.get 0
    call $dynrt_lib_modc__fn39
    global.set $dynrt_lib_modc_global16)
  (func $dynrt_lib_modc__fn53 (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    i32.const 24
    call $dynrt_lib_modc__fn45
    local.set 0
    global.get $dynrt_lib_modc_global16
    i32.eqz
    if  ;; label = @1
      call $dynrt_lib_modc__fn35
      global.set $dynrt_lib_modc_global16
    end
    global.get $dynrt_lib_modc_global16
    local.set 1
    local.get 1
    i32.const 8
    i32.add
    i32.load
    local.set 2
    local.get 2
    local.get 1
    i32.const 8
    i32.add
    i32.const 4
    i32.add
    i32.load
    i32.ge_s
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_lib_modc_global16
        local.tee 3
        local.set 2
        i32.const 8
        local.tee 4
        local.get 1
        i32.const 8
        i32.add
        i32.const 4
        i32.add
        i32.load
        i32.const 2
        i32.add
        i32.const 4
        local.tee 5
        i32.mul
        i32.add
        local.set 1
        global.get $dynrt_lib_modc_global16
        local.get 0
        call $dynrt_lib_modc__fn39
        global.set $dynrt_lib_modc_global16
        local.get 2
        local.get 1
        call $dynrt_lib_modc__fn41
      end
    else
      block  ;; label = @2
        local.get 1
        i32.const 8
        i32.add
        local.get 2
        i32.const 2
        i32.add
        i32.const 2
        i32.shl
        i32.add
        local.get 0
        i32.store
        local.get 1
        i32.const 8
        i32.add
        local.get 2
        i32.const 1
        i32.add
        i32.store
      end
    end
    local.get 0
    return)
  (func $dynrt_lib_modc__fn54 (result i32)
    (local i32) (local i32)
    i32.const 28
    call $dynrt_lib_modc__fn45
    local.set 0
    local.get 0
    call $dynrt_lib_modc__fn52
    local.get 0
    local.tee 1
    return)
  (func $dynrt_lib_modc_dynGcCellCount (result i32)
    global.get $dynrt_lib_modc_global16
    i32.eqz
    if  ;; label = @1
      i32.const 0
      return
    end
    global.get $dynrt_lib_modc_global16
    call $dynrt_lib_modc__fn36
    return)
  (func $dynrt_lib_modc__fn56 (param i32) (result i32)
    (local i32)
    local.get 0
    local.set 1
    local.get 1
    i32.const 8
    i32.add
    i32.load
    global.get $dynrt_lib_modc_global17
    i32.and
    i32.eqz
    if (result i32)  ;; label = @1
      i32.const 0
    else
      i32.const 1
    end
    return)
  (func $dynrt_lib_modc__fn57 (param i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    i32.eqz
    if (result i32)  ;; label = @1
      i32.const 1
    else
      local.get 0
      i32.const -1
      i32.eq
    end
    if  ;; label = @1
      return
    end
    local.get 0
    call $dynrt_lib_modc__fn56
    i32.const 1
    i32.eq
    if  ;; label = @1
      return
    end
    local.get 0
    local.set 1
    local.get 1
    i32.const 8
    i32.add
    local.get 1
    i32.const 8
    i32.add
    i32.load
    global.get $dynrt_lib_modc_global17
    i32.or
    i32.store
    local.get 1
    i32.const 8
    i32.add
    i32.load
    i32.const 255
    i32.and
    local.set 2
    local.get 2
    i32.const 5
    i32.eq
    if (result i32)  ;; label = @1
      i32.const 1
    else
      local.get 2
      i32.const 6
      i32.eq
    end
    if  ;; label = @1
      block  ;; label = @2
        local.get 1
        i32.const 8
        i32.add
        i32.const 4
        i32.add
        i32.load
        local.set 3
        local.get 3
        call $dynrt_lib_modc__fn36
        local.set 4
        i32.const 0
        local.set 5
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 5
              local.get 4
              i32.lt_s
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                local.get 3
                local.get 5
                call $dynrt_lib_modc__fn37
                call $dynrt_lib_modc__fn57
                local.get 5
                local.tee 6
                i32.const 1
                i32.add
                local.set 5
              end
              br 1 (;@4;)
            end
          end
        end
        local.get 2
        i32.const 6
        i32.eq
        if  ;; label = @3
          local.get 1
          i32.const 8
          i32.add
          i32.const 8
          i32.add
          i32.load
          call $dynrt_lib_modc__fn57
        end
      end
    else
      local.get 2
      i32.const 7
      i32.eq
      if  ;; label = @2
        local.get 1
        i32.const 8
        i32.add
        i32.const 4
        i32.add
        i32.load
        i32.const -1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 1
            i32.const 8
            i32.add
            i32.const 8
            i32.add
            i32.load
            call $dynrt_lib_modc__fn57
            local.get 1
            i32.const 8
            i32.add
            i32.const 12
            i32.add
            i32.load
            call $dynrt_lib_modc__fn57
            local.get 1
            i32.const 8
            i32.add
            i32.const 16
            i32.add
            i32.load
            call $dynrt_lib_modc__fn57
          end
        end
      end
    end)
  (func $dynrt_lib_modc_dynGcMarkClear
    (local i32) (local i32) (local i32) (local i32) (local i32)
    global.get $dynrt_lib_modc_global16
    i32.eqz
    if  ;; label = @1
      return
    end
    global.get $dynrt_lib_modc_global16
    call $dynrt_lib_modc__fn36
    local.set 0
    i32.const 0
    local.set 1
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 1
          local.get 0
          i32.lt_s
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            global.get $dynrt_lib_modc_global16
            local.get 1
            call $dynrt_lib_modc__fn37
            local.set 2
            local.get 2
            local.tee 3
            local.set 2
            local.get 2
            i32.const 8
            i32.add
            local.get 2
            i32.const 8
            i32.add
            i32.load
            i32.const 255
            i32.and
            i32.store
            local.get 1
            local.tee 4
            i32.const 1
            i32.add
            local.set 1
          end
          br 1 (;@2;)
        end
      end
    end)
  (func $dynrt_lib_modc_dynGcMark (param i32)
    local.get 0
    call $dynrt_lib_modc__fn57)
  (func $dynrt_lib_modc_dynGcMarkedCount (result i32)
    (local i32) (local i32) (local i32) (local i32)
    global.get $dynrt_lib_modc_global16
    i32.eqz
    if  ;; label = @1
      i32.const 0
      return
    end
    global.get $dynrt_lib_modc_global16
    call $dynrt_lib_modc__fn36
    local.set 0
    i32.const 0
    local.tee 3
    local.set 1
    local.get 3
    local.set 2
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 2
          local.get 0
          i32.lt_s
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            global.get $dynrt_lib_modc_global16
            local.get 2
            call $dynrt_lib_modc__fn37
            call $dynrt_lib_modc__fn56
            i32.const 1
            i32.eq
            if  ;; label = @5
              local.get 1
              i32.const 1
              i32.add
              local.set 1
            end
            local.get 2
            i32.const 1
            i32.add
            local.set 2
          end
          br 1 (;@2;)
        end
      end
    end
    local.get 1
    return)
  (func $dynrt_lib_modc__fn61 (param i32)
    global.get $dynrt_lib_modc_global18
    i32.eqz
    if  ;; label = @1
      call $dynrt_lib_modc__fn35
      global.set $dynrt_lib_modc_global18
    end
    global.get $dynrt_lib_modc_global18
    local.get 0
    call $dynrt_lib_modc__fn39
    global.set $dynrt_lib_modc_global18)
  (func $dynrt_lib_modc__fn62
    (local i32)
    global.get $dynrt_lib_modc_global18
    i32.eqz
    if  ;; label = @1
      return
    end
    global.get $dynrt_lib_modc_global18
    local.set 0
    local.get 0
    i32.const 8
    i32.add
    i32.load
    i32.const 0
    i32.gt_s
    if  ;; label = @1
      local.get 0
      i32.const 8
      i32.add
      local.get 0
      i32.const 8
      i32.add
      i32.load
      i32.const 1
      i32.sub
      i32.store
    end)
  (func $dynrt_lib_modc_dynGcPushRoot (param i32)
    local.get 0
    call $dynrt_lib_modc__fn61)
  (func $dynrt_lib_modc_dynGcPopRoot
    call $dynrt_lib_modc__fn62)
  (func $dynrt_lib_modc_dynGcRootCount (result i32)
    global.get $dynrt_lib_modc_global18
    i32.eqz
    if  ;; label = @1
      i32.const 0
      return
    end
    global.get $dynrt_lib_modc_global18
    call $dynrt_lib_modc__fn36
    return)
  (func $dynrt_lib_modc_dynGcMarkRoots
    (local i32) (local i32) (local i32) (local i32)
    call $dynrt_lib_modc_dynGcMarkClear
    global.get $dynrt_lib_modc_global21
    call $dynrt_lib_modc__fn57
    global.get $dynrt_lib_modc_global26
    call $dynrt_lib_modc__fn57
    global.get $dynrt_lib_modc_global25
    call $dynrt_lib_modc__fn57
    global.get $dynrt_lib_modc_global18
    i32.eqz
    if  ;; label = @1
      return
    end
    global.get $dynrt_lib_modc_global18
    call $dynrt_lib_modc__fn36
    local.set 0
    i32.const 0
    local.set 1
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 1
          local.get 0
          i32.lt_s
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            global.get $dynrt_lib_modc_global18
            local.get 1
            call $dynrt_lib_modc__fn37
            call $dynrt_lib_modc__fn57
            local.get 1
            local.tee 2
            i32.const 1
            i32.add
            local.set 1
          end
          br 1 (;@2;)
        end
      end
    end
    global.get $dynrt_lib_modc_global19
    i32.const 0
    i32.ne
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_lib_modc_global19
        call $dynrt_lib_modc__fn36
        local.set 0
        i32.const 0
        local.set 1
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 1
              local.get 0
              i32.lt_s
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                global.get $dynrt_lib_modc_global19
                local.get 1
                call $dynrt_lib_modc__fn37
                call $dynrt_lib_modc__fn57
                local.get 1
                local.tee 3
                i32.const 1
                i32.add
                local.set 1
              end
              br 1 (;@4;)
            end
          end
        end
      end
    end)
  (func $dynrt_lib_modc_dynGcPin (param i32) (result i32)
    (local i32) (local i32) (local i32)
    global.get $dynrt_lib_modc_global19
    i32.eqz
    if  ;; label = @1
      call $dynrt_lib_modc__fn35
      global.set $dynrt_lib_modc_global19
    end
    global.get $dynrt_lib_modc_global19
    call $dynrt_lib_modc__fn36
    local.set 1
    i32.const 0
    local.set 2
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 2
          local.get 1
          i32.lt_s
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            global.get $dynrt_lib_modc_global19
            local.get 2
            call $dynrt_lib_modc__fn37
            i32.eqz
            if  ;; label = @5
              block  ;; label = @6
                global.get $dynrt_lib_modc_global19
                local.get 2
                local.get 0
                call $dynrt_lib_modc__fn38
                local.get 2
                local.tee 3
                return
              end
            end
            local.get 2
            i32.const 1
            i32.add
            local.set 2
          end
          br 1 (;@2;)
        end
      end
    end
    global.get $dynrt_lib_modc_global19
    local.get 0
    call $dynrt_lib_modc__fn39
    global.set $dynrt_lib_modc_global19
    local.get 1
    return)
  (func $dynrt_lib_modc_dynGcUnpin (param i32)
    global.get $dynrt_lib_modc_global19
    i32.eqz
    if  ;; label = @1
      return
    end
    local.get 0
    i32.const 0
    i32.lt_s
    if (result i32)  ;; label = @1
      i32.const 1
    else
      local.get 0
      global.get $dynrt_lib_modc_global19
      call $dynrt_lib_modc__fn36
      i32.ge_s
    end
    if  ;; label = @1
      return
    end
    global.get $dynrt_lib_modc_global19
    local.get 0
    i32.const 0
    call $dynrt_lib_modc__fn38)
  (func $dynrt_lib_modc__fn69 (param i32)
    (local i32) (local i32)
    local.get 0
    local.tee 2
    local.set 1
    local.get 0
    i32.const 8
    local.get 1
    i32.const 8
    i32.add
    i32.const 4
    i32.add
    i32.load
    i32.const 2
    i32.add
    i32.const 4
    i32.mul
    i32.add
    call $dynrt_lib_modc__fn41)
  (func $dynrt_lib_modc__fn70 (param i32)
    (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.set 1
    local.get 1
    i32.const 8
    i32.add
    i32.load
    i32.const 255
    i32.and
    local.set 2
    local.get 2
    i32.const 3
    i32.eq
    if  ;; label = @1
      local.get 1
      i32.const 8
      i32.add
      i32.const 4
      i32.add
      i32.load
      i32.const 16
      call $dynrt_lib_modc__fn41
    else
      local.get 2
      i32.const 4
      i32.eq
      if  ;; label = @2
        local.get 1
        i32.const 8
        i32.add
        i32.const 4
        i32.add
        i32.load
        i32.const 8
        local.get 1
        i32.const 8
        i32.add
        i32.const 8
        i32.add
        i32.load
        i32.add
        call $dynrt_lib_modc__fn41
      else
        local.get 2
        i32.const 5
        i32.eq
        if  ;; label = @3
          local.get 1
          i32.const 8
          i32.add
          i32.const 4
          i32.add
          i32.load
          call $dynrt_lib_modc__fn69
        else
          local.get 2
          i32.const 6
          i32.eq
          if  ;; label = @4
            block  ;; label = @5
              local.get 1
              i32.const 8
              i32.add
              i32.const 4
              i32.add
              i32.load
              call $dynrt_lib_modc__fn69
              local.get 1
              i32.const 8
              i32.add
              i32.const 12
              i32.add
              i32.load
              local.set 1
              local.get 1
              call $dynrt_lib_modc__fn36
              local.set 2
              i32.const 0
              local.set 3
              block  ;; label = @6
                loop  ;; label = @7
                  block  ;; label = @8
                    local.get 3
                    local.get 2
                    i32.lt_s
                    i32.eqz
                    br_if 2 (;@6;)
                    block  ;; label = @9
                      local.get 1
                      local.get 3
                      call $dynrt_lib_modc__fn37
                      i32.const 8
                      local.get 1
                      local.get 3
                      i32.const 1
                      i32.add
                      call $dynrt_lib_modc__fn37
                      i32.add
                      call $dynrt_lib_modc__fn41
                      local.get 3
                      local.tee 4
                      i32.const 2
                      i32.add
                      local.set 3
                    end
                    br 1 (;@7;)
                  end
                end
              end
              local.get 1
              call $dynrt_lib_modc__fn69
            end
          end
        end
      end
    end)
  (func $dynrt_lib_modc_dynGcCollect (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    call $dynrt_lib_modc_dynGcMarkRoots
    global.get $dynrt_lib_modc_global16
    i32.eqz
    if  ;; label = @1
      i32.const 0
      return
    end
    global.get $dynrt_lib_modc_global16
    local.set 0
    local.get 0
    i32.const 8
    i32.add
    i32.load
    local.set 1
    i32.const 0
    local.tee 9
    local.set 2
    local.get 9
    local.set 3
    local.get 9
    local.set 4
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 3
          local.get 1
          i32.lt_s
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 0
            i32.const 8
            i32.add
            local.get 3
            i32.const 2
            i32.add
            i32.const 2
            i32.shl
            i32.add
            i32.load
            local.set 5
            local.get 5
            local.set 6
            local.get 6
            i32.const 8
            i32.add
            i32.load
            global.get $dynrt_lib_modc_global17
            i32.and
            i32.const 0
            i32.ne
            if  ;; label = @5
              block  ;; label = @6
                local.get 6
                i32.const 8
                i32.add
                local.get 6
                i32.const 8
                i32.add
                i32.load
                i32.const 255
                i32.and
                i32.store
                local.get 0
                i32.const 8
                i32.add
                local.get 2
                i32.const 2
                i32.add
                i32.const 2
                i32.shl
                i32.add
                local.get 5
                i32.store
                local.get 2
                local.tee 7
                i32.const 1
                i32.add
                local.set 2
              end
            else
              block  ;; label = @6
                local.get 6
                i32.const 8
                i32.add
                i32.load
                i32.const 255
                i32.and
                i32.const 7
                i32.eq
                if (result i32)  ;; label = @7
                  local.get 6
                  i32.const 8
                  i32.add
                  i32.const 4
                  i32.add
                  i32.load
                  i32.const -1
                  i32.eq
                else
                  i32.const 0
                end
                if (result i32)  ;; label = @7
                  i32.const 28
                else
                  i32.const 24
                end
                local.set 6
                local.get 5
                call $dynrt_lib_modc__fn70
                local.get 5
                local.get 6
                call $dynrt_lib_modc__fn41
                local.get 4
                i32.const 1
                i32.add
                local.set 4
              end
            end
            local.get 3
            local.tee 8
            i32.const 1
            i32.add
            local.set 3
          end
          br 1 (;@2;)
        end
      end
    end
    local.get 0
    i32.const 8
    i32.add
    local.get 2
    i32.store
    local.get 4
    return)
  (func $dynrt_lib_modc_dynGcFreeCount (result i32)
    global.get $dynrt_lib_modc_global12
    return)
  (func $dynrt_lib_modc__fn73
    (local i32)
    call $dynrt_lib_modc_dynGcCellCount
    global.get $dynrt_lib_modc_global15
    i32.gt_s
    if  ;; label = @1
      block  ;; label = @2
        call $dynrt_lib_modc_dynGcCollect
        drop
        call $dynrt_lib_modc_dynGcCellCount
        local.set 0
        local.get 0
        i32.const 2
        i32.mul
        local.set 0
        local.get 0
        i32.const 8192
        i32.gt_s
        if (result i32)  ;; label = @3
          local.get 0
        else
          i32.const 8192
        end
        global.set $dynrt_lib_modc_global15
      end
    end)
  (func $dynrt_lib_modc_dynArray (result i32)
    (local i32) (local i32)
    call $dynrt_lib_modc__fn53
    local.set 0
    local.get 0
    i32.const 8
    i32.add
    i32.const 5
    i32.store
    local.get 0
    i32.const 8
    i32.add
    i32.const 4
    i32.add
    call $dynrt_lib_modc__fn35
    i32.store
    local.get 0
    local.tee 1
    return)
  (func $dynrt_lib_modc_dynObject (result i32)
    (local i32) (local i32)
    call $dynrt_lib_modc__fn53
    local.set 0
    local.get 0
    i32.const 8
    i32.add
    i32.const 6
    i32.store
    local.get 0
    i32.const 8
    i32.add
    i32.const 4
    i32.add
    call $dynrt_lib_modc__fn35
    i32.store
    local.get 0
    i32.const 8
    i32.add
    i32.const 12
    i32.add
    call $dynrt_lib_modc__fn35
    i32.store
    local.get 0
    local.tee 1
    return)
  (func $dynrt_lib_modc_dynTag (param i32) (result i32)
    (local i32)
    local.get 0
    local.set 1
    local.get 1
    i32.const 8
    i32.add
    i32.load
    return)
  (func $dynrt_lib_modc_dynTypeof (param i32) (result i32)
    (local i32)
    local.get 0
    local.set 1
    local.get 1
    i32.const 8
    i32.add
    i32.load
    local.set 1
    local.get 1
    i32.eqz
    if  ;; label = @1
      i32.const 0
      return
    end
    local.get 1
    i32.const 2
    i32.eq
    if  ;; label = @1
      i32.const 2
      return
    end
    local.get 1
    i32.const 3
    i32.eq
    if  ;; label = @1
      i32.const 3
      return
    end
    local.get 1
    i32.const 4
    i32.eq
    if  ;; label = @1
      i32.const 4
      return
    end
    local.get 1
    i32.const 7
    i32.eq
    if  ;; label = @1
      i32.const 5
      return
    end
    i32.const 1
    return)
  (func $dynrt_lib_modc_dynNumberValue (param i32) (result f64)
    (local i32) (local i32)
    local.get 0
    local.set 1
    local.get 1
    i32.const 8
    i32.add
    i32.const 4
    i32.add
    i32.load
    local.set 1
    local.get 1
    local.tee 2
    local.set 1
    local.get 1
    i32.const 8
    i32.add
    f64.load
    return)
  (func $dynrt_lib_modc_dynBoolValue (param i32) (result i32)
    (local i32)
    local.get 0
    local.set 1
    local.get 1
    i32.const 8
    i32.add
    i32.const 4
    i32.add
    i32.load
    return)
  (func $dynrt_lib_modc_dynStrLen (param i32) (result i32)
    (local i32)
    local.get 0
    local.set 1
    local.get 1
    i32.const 8
    i32.add
    i32.const 8
    i32.add
    i32.load
    return)
  (func $dynrt_lib_modc_dynStrBytes (param i32) (result i32)
    (local i32) (local i32)
    local.get 0
    local.set 1
    local.get 1
    i32.const 8
    i32.add
    i32.const 4
    i32.add
    i32.load
    local.set 1
    local.get 1
    i32.const 8
    i32.add
    local.tee 2
    return)
  (func $dynrt_lib_modc_dynStrCharAt (param i32 i32) (result i32)
    (local i32) (local i32)
    local.get 0
    local.set 2
    local.get 2
    i32.const 8
    i32.add
    i32.const 4
    i32.add
    i32.load
    local.set 2
    local.get 2
    local.tee 3
    local.set 2
    local.get 2
    i32.const 8
    i32.add
    local.get 1
    i32.add
    i32.load8_u
    return)
  (func $dynrt_lib_modc_dynToBool (param i32) (result i32)
    (local i32) (local i32) (local f64) (local i32)
    local.get 0
    local.set 1
    local.get 1
    i32.const 8
    i32.add
    i32.load
    local.set 2
    local.get 2
    i32.eqz
    if  ;; label = @1
      i32.const 0
      return
    end
    local.get 2
    i32.const 1
    i32.eq
    if  ;; label = @1
      i32.const 0
      return
    end
    local.get 2
    i32.const 2
    i32.eq
    if  ;; label = @1
      local.get 1
      i32.const 8
      i32.add
      i32.const 4
      i32.add
      i32.load
      return
    end
    local.get 2
    i32.const 3
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 1
        i32.const 8
        i32.add
        i32.const 4
        i32.add
        i32.load
        local.set 1
        local.get 1
        local.tee 4
        local.set 1
        local.get 1
        i32.const 8
        i32.add
        f64.load
        local.set 3
        local.get 3
        local.get 3
        f64.ne
        if  ;; label = @3
          i32.const 0
          return
        end
        local.get 3
        f64.const 0x0p+0 (;=0;)
        f64.eq
        if (result i32)  ;; label = @3
          i32.const 0
        else
          i32.const 1
        end
        return
      end
    end
    local.get 2
    i32.const 4
    i32.eq
    if  ;; label = @1
      local.get 1
      i32.const 8
      i32.add
      i32.const 8
      i32.add
      i32.load
      i32.eqz
      if (result i32)  ;; label = @2
        i32.const 0
      else
        i32.const 1
      end
      return
    end
    i32.const 1
    return)
  (func $dynrt_lib_modc_dynToNumber (param i32) (result f64)
    (local i32) (local i32) (local i32)
    local.get 0
    local.set 1
    local.get 1
    i32.const 8
    i32.add
    i32.load
    local.set 2
    local.get 2
    i32.const 1
    i32.eq
    if  ;; label = @1
      f64.const 0x0p+0 (;=0;)
      return
    end
    local.get 2
    i32.const 2
    i32.eq
    if  ;; label = @1
      local.get 1
      i32.const 8
      i32.add
      i32.const 4
      i32.add
      i32.load
      i32.eqz
      if (result f64)  ;; label = @2
        f64.const 0x0p+0 (;=0;)
      else
        f64.const 0x1.0p+0 (;=1;)
      end
      return
    end
    local.get 2
    i32.const 3
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 1
        i32.const 8
        i32.add
        i32.const 4
        i32.add
        i32.load
        local.set 1
        local.get 1
        local.tee 3
        local.set 1
        local.get 1
        i32.const 8
        i32.add
        f64.load
        return
      end
    end
    f64.const nan (;=NaN;)
    return)
  (func $dynrt_lib_modc__fn85 (param i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.set 1
    local.get 1
    i32.const 8
    i32.add
    i32.const 8
    i32.add
    i32.load
    local.set 2
    local.get 1
    i32.const 8
    i32.add
    i32.const 4
    i32.add
    i32.load
    local.set 1
    local.get 1
    local.tee 11
    local.set 1
    i32.const 520
    local.set 3
    i32.const 0
    local.tee 12
    local.set 4
    local.get 12
    local.set 5
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 5
          local.get 2
          i32.lt_s
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 3
            local.tee 7
            local.set 3
            local.get 4
            local.tee 8
            local.set 4
            i32.const 1
            call $__malloc
            local.set 6
            local.get 6
            local.get 1
            i32.const 8
            i32.add
            local.get 5
            i32.add
            i32.load8_u
            i32.store8
            local.get 3
            local.get 4
            local.get 6
            i32.const 1
            call $dynrt_lib_modc__fn5
            local.set 4
            nop
            local.set 3
            local.get 5
            local.tee 9
            i32.const 1
            local.tee 10
            i32.add
            local.set 5
          end
          br 1 (;@2;)
        end
      end
    end
    local.get 3
    local.set 1
    local.get 4
    local.set 2
    local.get 1
    local.tee 13
    global.set $dynrt_lib_modc_global2
    local.get 2
    global.set $dynrt_lib_modc_global3
    return)
  (func $dynrt_lib_modc__fn86 (param i32)
    (local i32) (local i32) (local f64) (local i32) (local i32) (local i32)
    local.get 0
    local.set 1
    local.get 1
    i32.const 8
    i32.add
    i32.load
    local.set 2
    local.get 2
    i32.const 4
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 0
        call $dynrt_lib_modc__fn85
        global.get $dynrt_lib_modc_global2
        local.set 1
        global.get $dynrt_lib_modc_global3
        local.set 2
        local.get 1
        global.set $dynrt_lib_modc_global2
        local.get 2
        global.set $dynrt_lib_modc_global3
        return
      end
    end
    local.get 2
    i32.const 3
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 1
        i32.const 8
        i32.add
        i32.const 4
        i32.add
        i32.load
        local.set 1
        local.get 1
        local.tee 4
        local.set 1
        local.get 1
        i32.const 8
        i32.add
        f64.load
        local.set 3
        i32.const 32
        call $__malloc
        local.set 1
        local.get 3
        local.get 1
        call $dynrt_lib_modc__fn27
        local.set 2
        local.get 1
        local.tee 5
        global.set $dynrt_lib_modc_global2
        local.get 2
        global.set $dynrt_lib_modc_global3
        return
      end
    end
    local.get 2
    i32.const 2
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 1
        i32.const 8
        i32.add
        i32.const 4
        i32.add
        i32.load
        i32.eqz
        if  ;; label = @3
          block  ;; label = @4
            i32.const 520
            local.set 1
            i32.const 5
            local.set 2
          end
        else
          block  ;; label = @4
            i32.const 525
            local.set 1
            i32.const 4
            local.set 2
          end
        end
        local.get 1
        global.set $dynrt_lib_modc_global2
        local.get 2
        global.set $dynrt_lib_modc_global3
        return
      end
    end
    local.get 2
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        i32.const 529
        local.set 1
        i32.const 4
        local.set 2
        local.get 1
        global.set $dynrt_lib_modc_global2
        local.get 2
        global.set $dynrt_lib_modc_global3
        return
      end
    end
    local.get 2
    i32.eqz
    if  ;; label = @1
      block  ;; label = @2
        i32.const 533
        local.set 1
        i32.const 9
        local.set 2
        local.get 1
        global.set $dynrt_lib_modc_global2
        local.get 2
        global.set $dynrt_lib_modc_global3
        return
      end
    end
    i32.const 520
    local.set 1
    i32.const 0
    local.set 2
    local.get 1
    local.tee 6
    global.set $dynrt_lib_modc_global2
    local.get 2
    global.set $dynrt_lib_modc_global3
    return)
  (func $dynrt_lib_modc__fn87 (param i32 i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.set 3
    local.get 3
    i32.const 8
    i32.add
    i32.const 4
    i32.add
    i32.load
    local.set 4
    local.get 3
    i32.const 8
    i32.add
    i32.const 12
    i32.add
    i32.load
    local.set 3
    local.get 4
    call $dynrt_lib_modc__fn36
    local.set 4
    local.get 2
    local.set 5
    i32.const 0
    local.set 6
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 6
          local.get 4
          i32.lt_s
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 3
            local.get 6
            i32.const 2
            i32.mul
            i32.const 1
            i32.add
            call $dynrt_lib_modc__fn37
            local.set 7
            local.get 7
            local.get 5
            i32.eq
            if  ;; label = @5
              block  ;; label = @6
                local.get 3
                local.get 6
                i32.const 2
                i32.mul
                call $dynrt_lib_modc__fn37
                local.set 8
                local.get 8
                local.set 8
                i32.const 1
                local.set 9
                i32.const 0
                local.set 10
                block  ;; label = @7
                  loop  ;; label = @8
                    block  ;; label = @9
                      local.get 10
                      local.get 7
                      i32.lt_s
                      i32.eqz
                      br_if 2 (;@7;)
                      local.get 8
                      i32.const 8
                      i32.add
                      local.get 10
                      i32.add
                      i32.load8_u
                      local.get 1
                      local.get 2
                      local.get 10
                      call $dynrt_lib_modc__fn9
                      i32.ne
                      if  ;; label = @10
                        block  ;; label = @11
                          i32.const 0
                          local.set 9
                          local.get 7
                          local.set 10
                        end
                      else
                        local.get 10
                        i32.const 1
                        i32.add
                        local.set 10
                      end
                      br 1 (;@8;)
                    end
                  end
                end
                local.get 9
                i32.const 1
                i32.eq
                if  ;; label = @7
                  local.get 6
                  return
                end
              end
            end
            local.get 6
            local.tee 11
            i32.const 1
            local.tee 12
            i32.add
            local.set 6
          end
          br 1 (;@2;)
        end
      end
    end
    i32.const -1
    return)
  (func $dynrt_lib_modc_dynSet (param i32 i32 i32 i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.tee 9
    local.set 4
    local.get 0
    local.get 1
    local.get 2
    call $dynrt_lib_modc__fn87
    local.set 5
    local.get 5
    i32.const -1
    i32.ne
    if  ;; label = @1
      block  ;; label = @2
        local.get 4
        i32.const 8
        i32.add
        i32.const 4
        i32.add
        i32.load
        local.get 5
        local.get 3
        call $dynrt_lib_modc__fn38
        return
      end
    end
    local.get 2
    local.tee 10
    local.set 5
    i32.const 8
    local.get 5
    i32.add
    call $dynrt_lib_modc__fn45
    local.set 6
    i32.const 0
    local.set 7
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 7
          local.get 5
          i32.lt_s
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 6
            i32.const 8
            i32.add
            local.get 7
            i32.add
            local.get 1
            local.get 2
            local.get 7
            call $dynrt_lib_modc__fn9
            i32.store8
            local.get 7
            local.tee 8
            i32.const 1
            i32.add
            local.set 7
          end
          br 1 (;@2;)
        end
      end
    end
    local.get 6
    local.tee 11
    local.set 6
    local.get 4
    i32.const 8
    i32.add
    i32.const 12
    i32.add
    i32.load
    local.set 7
    local.get 7
    local.get 6
    call $dynrt_lib_modc__fn39
    local.set 7
    local.get 7
    local.get 5
    call $dynrt_lib_modc__fn39
    local.set 7
    local.get 4
    i32.const 8
    i32.add
    i32.const 12
    i32.add
    local.get 7
    i32.store
    local.get 4
    i32.const 8
    i32.add
    i32.const 4
    i32.add
    local.get 4
    i32.const 8
    i32.add
    i32.const 4
    i32.add
    i32.load
    local.get 3
    call $dynrt_lib_modc__fn39
    i32.store)
  (func $dynrt_lib_modc_dynGet (param i32 i32 i32) (result i32)
    (local i32) (local i32) (local i32)
    local.get 0
    local.tee 5
    local.set 3
    local.get 0
    local.get 1
    local.get 2
    call $dynrt_lib_modc__fn87
    local.set 4
    local.get 4
    i32.const -1
    i32.eq
    if  ;; label = @1
      i32.const -1
      return
    end
    local.get 3
    i32.const 8
    i32.add
    i32.const 4
    i32.add
    i32.load
    local.get 4
    call $dynrt_lib_modc__fn37
    return)
  (func $dynrt_lib_modc_dynHas (param i32 i32 i32) (result i32)
    local.get 0
    local.get 1
    local.get 2
    call $dynrt_lib_modc__fn87
    i32.const -1
    i32.eq
    if (result i32)  ;; label = @1
      i32.const 0
    else
      i32.const 1
    end
    return)
  (func $dynrt_lib_modc_dynObjLen (param i32) (result i32)
    (local i32)
    local.get 0
    local.set 1
    local.get 1
    i32.const 8
    i32.add
    i32.const 4
    i32.add
    i32.load
    call $dynrt_lib_modc__fn36
    return)
  (func $dynrt_lib_modc_dynObjKeyPtr (param i32 i32) (result i32)
    (local i32) (local i32)
    local.get 0
    local.set 2
    local.get 2
    i32.const 8
    i32.add
    i32.const 12
    i32.add
    i32.load
    local.get 1
    i32.const 2
    i32.mul
    call $dynrt_lib_modc__fn37
    local.set 2
    local.get 2
    i32.const 8
    i32.add
    local.tee 3
    return)
  (func $dynrt_lib_modc_dynObjKeyLen (param i32 i32) (result i32)
    (local i32)
    local.get 0
    local.set 2
    local.get 2
    i32.const 8
    i32.add
    i32.const 12
    i32.add
    i32.load
    local.get 1
    i32.const 2
    i32.mul
    i32.const 1
    i32.add
    call $dynrt_lib_modc__fn37
    return)
  (func $dynrt_lib_modc_dynObjValAt (param i32 i32) (result i32)
    (local i32)
    local.get 0
    local.set 2
    local.get 2
    i32.const 8
    i32.add
    i32.const 4
    i32.add
    i32.load
    local.get 1
    call $dynrt_lib_modc__fn37
    return)
  (func $dynrt_lib_modc__fn95 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.set 2
    local.get 2
    i32.const 8
    i32.add
    i32.const 12
    i32.add
    i32.load
    local.get 1
    i32.const 2
    i32.mul
    call $dynrt_lib_modc__fn37
    local.set 3
    local.get 2
    i32.const 8
    i32.add
    i32.const 12
    i32.add
    i32.load
    local.get 1
    i32.const 2
    i32.mul
    i32.const 1
    i32.add
    call $dynrt_lib_modc__fn37
    local.set 2
    local.get 3
    local.tee 7
    local.set 3
    i32.const 8
    local.get 2
    i32.add
    call $dynrt_lib_modc__fn45
    local.set 4
    i32.const 0
    local.set 5
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 5
          local.get 2
          i32.lt_s
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 4
            i32.const 8
            i32.add
            local.get 5
            i32.add
            local.get 3
            i32.const 8
            i32.add
            local.get 5
            i32.add
            i32.load8_u
            i32.store8
            local.get 5
            local.tee 6
            i32.const 1
            i32.add
            local.set 5
          end
          br 1 (;@2;)
        end
      end
    end
    call $dynrt_lib_modc__fn53
    local.set 3
    local.get 3
    i32.const 8
    i32.add
    i32.const 4
    i32.store
    local.get 3
    i32.const 8
    i32.add
    i32.const 4
    i32.add
    local.get 4
    i32.store
    local.get 3
    i32.const 8
    i32.add
    i32.const 8
    i32.add
    local.get 2
    i32.store
    local.get 3
    local.tee 8
    return)
  (func $dynrt_lib_modc_dynPush (param i32 i32)
    (local i32)
    local.get 0
    local.set 2
    local.get 2
    i32.const 8
    i32.add
    i32.const 4
    i32.add
    local.get 2
    i32.const 8
    i32.add
    i32.const 4
    i32.add
    i32.load
    local.get 1
    call $dynrt_lib_modc__fn39
    i32.store)
  (func $dynrt_lib_modc_dynArrLen (param i32) (result i32)
    (local i32)
    local.get 0
    local.set 1
    local.get 1
    i32.const 8
    i32.add
    i32.const 4
    i32.add
    i32.load
    call $dynrt_lib_modc__fn36
    return)
  (func $dynrt_lib_modc_dynArrGet (param i32 i32) (result i32)
    (local i32)
    local.get 0
    local.set 2
    local.get 2
    i32.const 8
    i32.add
    i32.const 4
    i32.add
    i32.load
    local.get 1
    call $dynrt_lib_modc__fn37
    return)
  (func $dynrt_lib_modc__fn99 (param i32 i32 i32)
    (local i32) (local i32)
    local.get 0
    local.set 3
    local.get 3
    i32.const 8
    i32.add
    i32.const 4
    i32.add
    i32.load
    call $dynrt_lib_modc__fn36
    local.set 4
    local.get 1
    i32.const 0
    i32.ge_s
    if (result i32)  ;; label = @1
      local.get 1
      local.get 4
      i32.lt_s
    else
      i32.const 0
    end
    if  ;; label = @1
      local.get 3
      i32.const 8
      i32.add
      i32.const 4
      i32.add
      i32.load
      local.get 1
      local.get 2
      call $dynrt_lib_modc__fn38
    else
      local.get 1
      local.get 4
      i32.eq
      if  ;; label = @2
        local.get 3
        i32.const 8
        i32.add
        i32.const 4
        i32.add
        local.get 3
        i32.const 8
        i32.add
        i32.const 4
        i32.add
        i32.load
        local.get 2
        call $dynrt_lib_modc__fn39
        i32.store
      end
    end)
  (func $dynrt_lib_modc__fn100 (param i32 i32 i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local f64) (local i32) (local i32) (local i32) (local i32) (local i32) (local f64) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    call $dynrt_lib_modc_dynArrLen
    local.set 4
    local.get 3
    call $dynrt_lib_modc_dynArrLen
    local.set 5
    local.get 1
    local.get 2
    i32.const 542
    i32.const 4
    call $dynrt_lib_modc__fn169
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        i32.const 0
        local.set 6
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 6
              local.get 5
              i32.lt_s
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                local.get 0
                local.get 3
                local.get 6
                call $dynrt_lib_modc_dynArrGet
                call $dynrt_lib_modc_dynPush
                local.get 6
                local.tee 17
                i32.const 1
                i32.add
                local.set 6
              end
              br 1 (;@4;)
            end
          end
        end
        local.get 0
        call $dynrt_lib_modc_dynArrLen
        local.set 4
        local.get 4
        f64.convert_i32_s
        call $dynrt_lib_modc_dynNumber
        return
      end
    end
    local.get 1
    local.get 2
    i32.const 546
    i32.const 7
    call $dynrt_lib_modc__fn169
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        call $dynrt_lib_modc_dynUndefined
        local.set 7
        local.get 5
        i32.const 0
        i32.gt_s
        if  ;; label = @3
          local.get 3
          i32.const 0
          call $dynrt_lib_modc_dynArrGet
          local.set 7
        end
        i32.const 0
        local.set 6
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 6
              local.get 4
              i32.lt_s
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                local.get 0
                local.get 6
                call $dynrt_lib_modc_dynArrGet
                local.get 7
                call $dynrt_lib_modc_dynStrictEq
                i32.const 1
                i32.eq
                if  ;; label = @7
                  local.get 6
                  f64.convert_i32_s
                  call $dynrt_lib_modc_dynNumber
                  return
                end
                local.get 6
                i32.const 1
                i32.add
                local.set 6
              end
              br 1 (;@4;)
            end
          end
        end
        f64.const 0x0p+0 (;=0;)
        f64.const 0x1.0p+0 (;=1;)
        f64.sub
        call $dynrt_lib_modc_dynNumber
        return
      end
    end
    local.get 1
    local.get 2
    i32.const 553
    i32.const 8
    call $dynrt_lib_modc__fn169
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        call $dynrt_lib_modc_dynUndefined
        local.set 7
        local.get 5
        i32.const 0
        i32.gt_s
        if  ;; label = @3
          local.get 3
          i32.const 0
          call $dynrt_lib_modc_dynArrGet
          local.set 7
        end
        i32.const 0
        local.tee 18
        local.set 6
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 6
              local.get 4
              i32.lt_s
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                local.get 0
                local.get 6
                call $dynrt_lib_modc_dynArrGet
                local.get 7
                call $dynrt_lib_modc_dynStrictEq
                i32.const 1
                i32.eq
                if  ;; label = @7
                  i32.const 1
                  call $dynrt_lib_modc_dynBool
                  return
                end
                local.get 6
                i32.const 1
                i32.add
                local.set 6
              end
              br 1 (;@4;)
            end
          end
        end
        i32.const 0
        call $dynrt_lib_modc_dynBool
        return
      end
    end
    local.get 1
    local.get 2
    i32.const 561
    i32.const 4
    call $dynrt_lib_modc__fn169
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        i32.const 565
        local.set 7
        i32.const 1
        local.set 8
        local.get 5
        i32.const 0
        i32.gt_s
        if  ;; label = @3
          block  ;; label = @4
            local.get 3
            i32.const 0
            call $dynrt_lib_modc_dynArrGet
            call $dynrt_lib_modc__fn86
            global.get $dynrt_lib_modc_global2
            local.set 7
            global.get $dynrt_lib_modc_global3
            local.set 8
          end
        end
        i32.const 520
        local.set 5
        i32.const 0
        local.tee 24
        local.set 9
        local.get 24
        local.set 6
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 6
              local.get 4
              i32.lt_s
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                local.get 6
                i32.const 0
                i32.gt_s
                if  ;; label = @7
                  block  ;; label = @8
                    local.get 5
                    local.tee 19
                    local.set 5
                    local.get 9
                    local.tee 20
                    local.set 9
                    local.get 5
                    local.get 9
                    local.get 7
                    local.get 8
                    call $dynrt_lib_modc__fn5
                    local.set 9
                    nop
                    local.set 5
                  end
                end
                local.get 5
                local.tee 21
                local.set 5
                local.get 9
                local.tee 22
                local.set 9
                local.get 0
                local.get 6
                call $dynrt_lib_modc_dynArrGet
                call $dynrt_lib_modc__fn86
                local.get 5
                local.get 9
                global.get $dynrt_lib_modc_global2
                global.get $dynrt_lib_modc_global3
                call $dynrt_lib_modc__fn5
                local.set 9
                nop
                local.set 5
                local.get 6
                local.tee 23
                i32.const 1
                i32.add
                local.set 6
              end
              br 1 (;@4;)
            end
          end
        end
        local.get 5
        local.get 9
        call $dynrt_lib_modc_dynString
        return
      end
    end
    local.get 1
    local.get 2
    i32.const 566
    i32.const 5
    call $dynrt_lib_modc__fn169
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        i32.const 0
        local.set 6
        local.get 4
        local.set 7
        local.get 5
        i32.const 0
        i32.gt_s
        if  ;; label = @3
          block  ;; label = @4
            local.get 3
            i32.const 0
            call $dynrt_lib_modc_dynArrGet
            call $dynrt_lib_modc_dynToNumber
            local.set 10
            local.get 10
            i32.trunc_f64_s
            local.set 6
          end
        end
        local.get 5
        i32.const 1
        i32.gt_s
        if  ;; label = @3
          block  ;; label = @4
            local.get 3
            i32.const 1
            call $dynrt_lib_modc_dynArrGet
            call $dynrt_lib_modc_dynToNumber
            local.set 10
            local.get 10
            i32.trunc_f64_s
            local.set 7
          end
        end
        local.get 6
        i32.const 0
        i32.lt_s
        if  ;; label = @3
          local.get 4
          local.get 6
          i32.add
          local.set 6
        end
        local.get 7
        i32.const 0
        i32.lt_s
        if  ;; label = @3
          local.get 4
          local.get 7
          i32.add
          local.set 7
        end
        local.get 6
        i32.const 0
        i32.lt_s
        if  ;; label = @3
          i32.const 0
          local.set 6
        end
        local.get 7
        local.get 4
        i32.gt_s
        if  ;; label = @3
          local.get 4
          local.set 7
        end
        call $dynrt_lib_modc_dynArray
        local.set 8
        local.get 6
        local.set 6
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 6
              local.get 7
              i32.lt_s
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                local.get 8
                local.get 0
                local.get 6
                call $dynrt_lib_modc_dynArrGet
                call $dynrt_lib_modc_dynPush
                local.get 6
                local.tee 25
                i32.const 1
                i32.add
                local.set 6
              end
              br 1 (;@4;)
            end
          end
        end
        local.get 8
        return
      end
    end
    local.get 1
    local.get 2
    i32.const 571
    i32.const 6
    call $dynrt_lib_modc__fn169
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        call $dynrt_lib_modc_dynArray
        local.set 8
        i32.const 0
        local.tee 29
        local.set 6
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 6
              local.get 4
              i32.lt_s
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                local.get 8
                local.get 0
                local.get 6
                call $dynrt_lib_modc_dynArrGet
                call $dynrt_lib_modc_dynPush
                local.get 6
                local.tee 26
                i32.const 1
                i32.add
                local.set 6
              end
              br 1 (;@4;)
            end
          end
        end
        i32.const 0
        local.tee 30
        local.set 4
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 4
              local.get 5
              i32.lt_s
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                local.get 3
                local.get 4
                call $dynrt_lib_modc_dynArrGet
                local.set 6
                local.get 6
                local.set 7
                local.get 7
                i32.const 8
                i32.add
                i32.load
                i32.const 5
                i32.eq
                if  ;; label = @7
                  block  ;; label = @8
                    local.get 6
                    call $dynrt_lib_modc_dynArrLen
                    local.set 7
                    i32.const 0
                    local.set 9
                    block  ;; label = @9
                      loop  ;; label = @10
                        block  ;; label = @11
                          local.get 9
                          local.get 7
                          i32.lt_s
                          i32.eqz
                          br_if 2 (;@9;)
                          block  ;; label = @12
                            local.get 8
                            local.get 6
                            local.get 9
                            call $dynrt_lib_modc_dynArrGet
                            call $dynrt_lib_modc_dynPush
                            local.get 9
                            local.tee 27
                            i32.const 1
                            i32.add
                            local.set 9
                          end
                          br 1 (;@10;)
                        end
                      end
                    end
                  end
                else
                  local.get 8
                  local.get 6
                  call $dynrt_lib_modc_dynPush
                end
                local.get 4
                local.tee 28
                i32.const 1
                i32.add
                local.set 4
              end
              br 1 (;@4;)
            end
          end
        end
        local.get 8
        return
      end
    end
    local.get 1
    local.get 2
    i32.const 577
    i32.const 7
    call $dynrt_lib_modc__fn169
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        call $dynrt_lib_modc_dynArray
        local.set 8
        local.get 4
        i32.const 1
        i32.sub
        local.set 6
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 6
              i32.const 0
              i32.ge_s
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                local.get 8
                local.get 0
                local.get 6
                call $dynrt_lib_modc_dynArrGet
                call $dynrt_lib_modc_dynPush
                local.get 6
                local.tee 31
                i32.const 1
                i32.sub
                local.set 6
              end
              br 1 (;@4;)
            end
          end
        end
        local.get 8
        return
      end
    end
    local.get 1
    local.get 2
    i32.const 584
    i32.const 3
    call $dynrt_lib_modc__fn169
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 4
        i32.eqz
        if  ;; label = @3
          call $dynrt_lib_modc_dynUndefined
          return
        end
        local.get 0
        local.set 6
        local.get 6
        i32.const 8
        i32.add
        i32.const 4
        i32.add
        i32.load
        local.set 7
        local.get 7
        local.get 4
        i32.const 1
        i32.sub
        call $dynrt_lib_modc__fn37
        local.set 5
        local.get 7
        local.tee 32
        local.set 6
        local.get 6
        i32.const 8
        i32.add
        local.get 4
        i32.const 1
        i32.sub
        i32.store
        local.get 5
        return
      end
    end
    local.get 1
    local.get 2
    i32.const 587
    i32.const 5
    call $dynrt_lib_modc__fn169
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 4
        i32.eqz
        if  ;; label = @3
          call $dynrt_lib_modc_dynUndefined
          return
        end
        local.get 0
        local.set 6
        local.get 6
        i32.const 8
        i32.add
        i32.const 4
        i32.add
        i32.load
        local.set 7
        local.get 7
        i32.const 0
        call $dynrt_lib_modc__fn37
        local.set 5
        i32.const 1
        local.tee 35
        local.set 6
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 6
              local.get 4
              i32.lt_s
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                local.get 7
                local.get 6
                i32.const 1
                i32.sub
                local.get 7
                local.get 6
                call $dynrt_lib_modc__fn37
                call $dynrt_lib_modc__fn38
                local.get 6
                local.tee 33
                i32.const 1
                local.tee 34
                i32.add
                local.set 6
              end
              br 1 (;@4;)
            end
          end
        end
        local.get 7
        local.tee 36
        local.set 6
        local.get 6
        i32.const 8
        i32.add
        local.get 4
        i32.const 1
        i32.sub
        i32.store
        local.get 5
        return
      end
    end
    local.get 1
    local.get 2
    i32.const 592
    i32.const 7
    call $dynrt_lib_modc__fn169
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        i32.const 0
        local.tee 39
        local.set 6
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 6
              local.get 5
              i32.lt_s
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                local.get 0
                call $dynrt_lib_modc_dynUndefined
                call $dynrt_lib_modc_dynPush
                local.get 6
                i32.const 1
                i32.add
                local.set 6
              end
              br 1 (;@4;)
            end
          end
        end
        local.get 0
        local.set 6
        local.get 6
        i32.const 8
        i32.add
        i32.const 4
        i32.add
        i32.load
        local.set 7
        local.get 4
        local.tee 40
        i32.const 1
        i32.sub
        local.set 6
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 6
              i32.const 0
              i32.ge_s
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                local.get 7
                local.get 6
                local.get 5
                i32.add
                local.get 7
                local.get 6
                call $dynrt_lib_modc__fn37
                call $dynrt_lib_modc__fn38
                local.get 6
                local.tee 37
                i32.const 1
                i32.sub
                local.set 6
              end
              br 1 (;@4;)
            end
          end
        end
        i32.const 0
        local.tee 41
        local.set 6
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 6
              local.get 5
              i32.lt_s
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                local.get 7
                local.get 6
                local.get 3
                local.get 6
                call $dynrt_lib_modc_dynArrGet
                call $dynrt_lib_modc__fn38
                local.get 6
                local.tee 38
                i32.const 1
                i32.add
                local.set 6
              end
              br 1 (;@4;)
            end
          end
        end
        local.get 4
        local.tee 42
        local.get 5
        i32.add
        local.set 4
        local.get 4
        f64.convert_i32_s
        call $dynrt_lib_modc_dynNumber
        return
      end
    end
    local.get 1
    local.get 2
    i32.const 599
    i32.const 2
    call $dynrt_lib_modc__fn169
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        i32.const 0
        local.set 6
        local.get 5
        i32.const 0
        i32.gt_s
        if  ;; label = @3
          block  ;; label = @4
            local.get 3
            i32.const 0
            call $dynrt_lib_modc_dynArrGet
            call $dynrt_lib_modc_dynToNumber
            local.set 10
            local.get 10
            i32.trunc_f64_s
            local.set 6
          end
        end
        local.get 6
        i32.const 0
        i32.lt_s
        if  ;; label = @3
          local.get 4
          local.get 6
          i32.add
          local.set 6
        end
        local.get 6
        i32.const 0
        i32.lt_s
        if (result i32)  ;; label = @3
          i32.const 1
        else
          local.get 6
          local.get 4
          i32.ge_s
        end
        if  ;; label = @3
          call $dynrt_lib_modc_dynUndefined
          return
        end
        local.get 0
        local.get 6
        call $dynrt_lib_modc_dynArrGet
        return
      end
    end
    local.get 1
    local.get 2
    i32.const 601
    i32.const 11
    call $dynrt_lib_modc__fn169
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        call $dynrt_lib_modc_dynUndefined
        local.set 7
        local.get 5
        i32.const 0
        i32.gt_s
        if  ;; label = @3
          local.get 3
          i32.const 0
          call $dynrt_lib_modc_dynArrGet
          local.set 7
        end
        local.get 4
        i32.const 1
        i32.sub
        local.set 6
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 6
              i32.const 0
              i32.ge_s
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                local.get 0
                local.get 6
                call $dynrt_lib_modc_dynArrGet
                local.get 7
                call $dynrt_lib_modc_dynStrictEq
                i32.const 1
                i32.eq
                if  ;; label = @7
                  local.get 6
                  f64.convert_i32_s
                  call $dynrt_lib_modc_dynNumber
                  return
                end
                local.get 6
                i32.const 1
                i32.sub
                local.set 6
              end
              br 1 (;@4;)
            end
          end
        end
        f64.const 0x0p+0 (;=0;)
        f64.const 0x1.0p+0 (;=1;)
        f64.sub
        call $dynrt_lib_modc_dynNumber
        return
      end
    end
    call $dynrt_lib_modc_dynUndefined
    local.set 11
    local.get 5
    i32.const 0
    i32.gt_s
    if  ;; label = @1
      local.get 3
      i32.const 0
      call $dynrt_lib_modc_dynArrGet
      local.set 11
    end
    local.get 1
    local.get 2
    i32.const 612
    i32.const 3
    call $dynrt_lib_modc__fn169
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        call $dynrt_lib_modc_dynArray
        local.set 8
        i32.const 0
        local.set 6
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 6
              local.get 4
              i32.lt_s
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                call $dynrt_lib_modc_dynArray
                local.set 12
                local.get 12
                local.get 0
                local.get 6
                call $dynrt_lib_modc_dynArrGet
                call $dynrt_lib_modc_dynPush
                local.get 12
                local.get 6
                f64.convert_i32_s
                call $dynrt_lib_modc_dynNumber
                call $dynrt_lib_modc_dynPush
                local.get 8
                local.get 11
                local.get 12
                call $dynrt_lib_modc_dynApply
                call $dynrt_lib_modc_dynPush
                local.get 6
                local.tee 43
                i32.const 1
                i32.add
                local.set 6
              end
              br 1 (;@4;)
            end
          end
        end
        local.get 8
        return
      end
    end
    local.get 1
    local.get 2
    i32.const 615
    i32.const 6
    call $dynrt_lib_modc__fn169
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        call $dynrt_lib_modc_dynArray
        local.set 8
        i32.const 0
        local.set 6
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 6
              local.get 4
              i32.lt_s
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                local.get 0
                local.get 6
                call $dynrt_lib_modc_dynArrGet
                local.set 5
                call $dynrt_lib_modc_dynArray
                local.set 12
                local.get 12
                local.get 5
                call $dynrt_lib_modc_dynPush
                local.get 12
                local.get 6
                f64.convert_i32_s
                call $dynrt_lib_modc_dynNumber
                call $dynrt_lib_modc_dynPush
                local.get 11
                local.get 12
                call $dynrt_lib_modc_dynApply
                call $dynrt_lib_modc_dynToBool
                i32.const 1
                i32.eq
                if  ;; label = @7
                  local.get 8
                  local.get 5
                  call $dynrt_lib_modc_dynPush
                end
                local.get 6
                local.tee 44
                i32.const 1
                i32.add
                local.set 6
              end
              br 1 (;@4;)
            end
          end
        end
        local.get 8
        return
      end
    end
    local.get 1
    local.get 2
    i32.const 621
    i32.const 7
    call $dynrt_lib_modc__fn169
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        i32.const 0
        local.set 6
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 6
              local.get 4
              i32.lt_s
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                call $dynrt_lib_modc_dynArray
                local.set 12
                local.get 12
                local.get 0
                local.get 6
                call $dynrt_lib_modc_dynArrGet
                call $dynrt_lib_modc_dynPush
                local.get 12
                local.get 6
                f64.convert_i32_s
                call $dynrt_lib_modc_dynNumber
                call $dynrt_lib_modc_dynPush
                local.get 11
                local.get 12
                call $dynrt_lib_modc_dynApply
                drop
                local.get 6
                local.tee 45
                i32.const 1
                i32.add
                local.set 6
              end
              br 1 (;@4;)
            end
          end
        end
        call $dynrt_lib_modc_dynUndefined
        return
      end
    end
    local.get 1
    local.get 2
    i32.const 628
    i32.const 6
    call $dynrt_lib_modc__fn169
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        call $dynrt_lib_modc_dynUndefined
        local.set 7
        i32.const 0
        local.set 6
        local.get 5
        i32.const 1
        i32.gt_s
        if  ;; label = @3
          local.get 3
          i32.const 1
          call $dynrt_lib_modc_dynArrGet
          local.set 7
        else
          local.get 4
          i32.const 0
          i32.gt_s
          if  ;; label = @4
            block  ;; label = @5
              local.get 0
              i32.const 0
              call $dynrt_lib_modc_dynArrGet
              local.set 7
              i32.const 1
              local.set 6
            end
          end
        end
        local.get 6
        local.set 6
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 6
              local.get 4
              i32.lt_s
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                call $dynrt_lib_modc_dynArray
                local.set 12
                local.get 12
                local.get 7
                call $dynrt_lib_modc_dynPush
                local.get 12
                local.get 0
                local.get 6
                call $dynrt_lib_modc_dynArrGet
                call $dynrt_lib_modc_dynPush
                local.get 12
                local.get 6
                f64.convert_i32_s
                call $dynrt_lib_modc_dynNumber
                call $dynrt_lib_modc_dynPush
                local.get 11
                local.get 12
                call $dynrt_lib_modc_dynApply
                local.set 7
                local.get 6
                local.tee 46
                i32.const 1
                i32.add
                local.set 6
              end
              br 1 (;@4;)
            end
          end
        end
        local.get 7
        return
      end
    end
    local.get 1
    local.get 2
    i32.const 634
    i32.const 4
    call $dynrt_lib_modc__fn169
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        i32.const 0
        local.set 6
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 6
              local.get 4
              i32.lt_s
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                local.get 0
                local.get 6
                call $dynrt_lib_modc_dynArrGet
                local.set 5
                call $dynrt_lib_modc_dynArray
                local.set 12
                local.get 12
                local.get 5
                call $dynrt_lib_modc_dynPush
                local.get 12
                local.get 6
                f64.convert_i32_s
                call $dynrt_lib_modc_dynNumber
                call $dynrt_lib_modc_dynPush
                local.get 11
                local.get 12
                call $dynrt_lib_modc_dynApply
                call $dynrt_lib_modc_dynToBool
                i32.const 1
                i32.eq
                if  ;; label = @7
                  local.get 5
                  return
                end
                local.get 6
                local.tee 47
                i32.const 1
                i32.add
                local.set 6
              end
              br 1 (;@4;)
            end
          end
        end
        call $dynrt_lib_modc_dynUndefined
        return
      end
    end
    local.get 1
    local.get 2
    i32.const 638
    i32.const 9
    call $dynrt_lib_modc__fn169
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        i32.const 0
        local.set 6
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 6
              local.get 4
              i32.lt_s
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                call $dynrt_lib_modc_dynArray
                local.set 12
                local.get 12
                local.get 0
                local.get 6
                call $dynrt_lib_modc_dynArrGet
                call $dynrt_lib_modc_dynPush
                local.get 12
                local.get 6
                f64.convert_i32_s
                call $dynrt_lib_modc_dynNumber
                call $dynrt_lib_modc_dynPush
                local.get 11
                local.get 12
                call $dynrt_lib_modc_dynApply
                call $dynrt_lib_modc_dynToBool
                i32.const 1
                i32.eq
                if  ;; label = @7
                  local.get 6
                  f64.convert_i32_s
                  call $dynrt_lib_modc_dynNumber
                  return
                end
                local.get 6
                local.tee 48
                i32.const 1
                i32.add
                local.set 6
              end
              br 1 (;@4;)
            end
          end
        end
        f64.const 0x0p+0 (;=0;)
        f64.const 0x1.0p+0 (;=1;)
        f64.sub
        call $dynrt_lib_modc_dynNumber
        return
      end
    end
    local.get 1
    local.get 2
    i32.const 647
    i32.const 4
    call $dynrt_lib_modc__fn169
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        i32.const 0
        local.tee 50
        local.set 6
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 6
              local.get 4
              i32.lt_s
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                call $dynrt_lib_modc_dynArray
                local.set 12
                local.get 12
                local.get 0
                local.get 6
                call $dynrt_lib_modc_dynArrGet
                call $dynrt_lib_modc_dynPush
                local.get 12
                local.get 6
                f64.convert_i32_s
                call $dynrt_lib_modc_dynNumber
                call $dynrt_lib_modc_dynPush
                local.get 11
                local.get 12
                call $dynrt_lib_modc_dynApply
                call $dynrt_lib_modc_dynToBool
                i32.const 1
                i32.eq
                if  ;; label = @7
                  i32.const 1
                  call $dynrt_lib_modc_dynBool
                  return
                end
                local.get 6
                local.tee 49
                i32.const 1
                i32.add
                local.set 6
              end
              br 1 (;@4;)
            end
          end
        end
        i32.const 0
        call $dynrt_lib_modc_dynBool
        return
      end
    end
    local.get 1
    local.get 2
    i32.const 651
    i32.const 5
    call $dynrt_lib_modc__fn169
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        i32.const 0
        local.set 6
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 6
              local.get 4
              i32.lt_s
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                call $dynrt_lib_modc_dynArray
                local.set 12
                local.get 12
                local.get 0
                local.get 6
                call $dynrt_lib_modc_dynArrGet
                call $dynrt_lib_modc_dynPush
                local.get 12
                local.get 6
                f64.convert_i32_s
                call $dynrt_lib_modc_dynNumber
                call $dynrt_lib_modc_dynPush
                local.get 11
                local.get 12
                call $dynrt_lib_modc_dynApply
                call $dynrt_lib_modc_dynToBool
                i32.eqz
                if  ;; label = @7
                  i32.const 0
                  call $dynrt_lib_modc_dynBool
                  return
                end
                local.get 6
                local.tee 51
                i32.const 1
                i32.add
                local.set 6
              end
              br 1 (;@4;)
            end
          end
        end
        i32.const 1
        call $dynrt_lib_modc_dynBool
        return
      end
    end
    local.get 1
    local.get 2
    i32.const 656
    i32.const 4
    call $dynrt_lib_modc__fn169
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 0
        local.tee 58
        local.set 6
        local.get 6
        i32.const 8
        i32.add
        i32.const 4
        i32.add
        i32.load
        local.set 7
        i32.const 1
        local.set 6
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 6
              local.get 4
              i32.lt_s
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                local.get 7
                local.get 6
                call $dynrt_lib_modc__fn37
                local.set 8
                local.get 6
                local.tee 54
                i32.const 1
                local.tee 55
                i32.sub
                local.set 9
                local.get 55
                local.set 13
                block  ;; label = @7
                  loop  ;; label = @8
                    block  ;; label = @9
                      local.get 9
                      i32.const 0
                      i32.ge_s
                      if (result i32)  ;; label = @10
                        local.get 13
                        i32.const 1
                        i32.eq
                      else
                        i32.const 0
                      end
                      i32.eqz
                      br_if 2 (;@7;)
                      block  ;; label = @10
                        local.get 7
                        local.get 9
                        call $dynrt_lib_modc__fn37
                        local.set 14
                        i32.const 0
                        local.set 15
                        local.get 5
                        i32.const 0
                        i32.gt_s
                        if  ;; label = @11
                          block  ;; label = @12
                            call $dynrt_lib_modc_dynArray
                            local.set 12
                            local.get 12
                            local.get 14
                            call $dynrt_lib_modc_dynPush
                            local.get 12
                            local.get 8
                            call $dynrt_lib_modc_dynPush
                            local.get 11
                            local.get 12
                            call $dynrt_lib_modc_dynApply
                            call $dynrt_lib_modc_dynToNumber
                            local.set 10
                            local.get 10
                            f64.const 0x0p+0 (;=0;)
                            f64.gt
                            if  ;; label = @13
                              i32.const 1
                              local.set 15
                            end
                          end
                        else
                          block  ;; label = @12
                            local.get 14
                            call $dynrt_lib_modc_dynToNumber
                            local.set 10
                            local.get 8
                            call $dynrt_lib_modc_dynToNumber
                            local.set 16
                            local.get 10
                            local.get 16
                            f64.gt
                            if  ;; label = @13
                              i32.const 1
                              local.set 15
                            end
                          end
                        end
                        local.get 15
                        i32.const 1
                        i32.eq
                        if  ;; label = @11
                          block  ;; label = @12
                            local.get 7
                            local.get 9
                            i32.const 1
                            i32.add
                            local.get 14
                            call $dynrt_lib_modc__fn38
                            local.get 9
                            local.tee 52
                            i32.const 1
                            local.tee 53
                            i32.sub
                            local.set 9
                          end
                        else
                          i32.const 0
                          local.set 13
                        end
                      end
                      br 1 (;@8;)
                    end
                  end
                end
                local.get 7
                local.get 9
                i32.const 1
                i32.add
                local.get 8
                call $dynrt_lib_modc__fn38
                local.get 6
                local.tee 56
                i32.const 1
                local.tee 57
                i32.add
                local.set 6
              end
              br 1 (;@4;)
            end
          end
        end
        local.get 0
        local.tee 59
        return
      end
    end
    call $dynrt_lib_modc_dynUndefined
    return)
  (func $dynrt_lib_modc__fn101 (param i32 i32 i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local f64) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    call $dynrt_lib_modc__fn85
    global.get $dynrt_lib_modc_global2
    local.set 4
    global.get $dynrt_lib_modc_global3
    local.set 5
    local.get 5
    local.set 6
    local.get 3
    call $dynrt_lib_modc_dynArrLen
    local.set 7
    local.get 1
    local.get 2
    i32.const 660
    i32.const 6
    call $dynrt_lib_modc__fn169
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        i32.const 0
        local.set 6
        local.get 7
        i32.const 0
        i32.gt_s
        if  ;; label = @3
          block  ;; label = @4
            local.get 3
            i32.const 0
            call $dynrt_lib_modc_dynArrGet
            call $dynrt_lib_modc_dynToNumber
            local.set 8
            local.get 8
            i32.trunc_f64_s
            local.set 6
          end
        end
        local.get 4
        local.get 5
        local.get 6
        call $dynrt_lib_modc__fn10
        local.set 5
        nop
        local.set 4
        local.get 4
        local.get 5
        call $dynrt_lib_modc_dynString
        return
      end
    end
    local.get 1
    local.get 2
    i32.const 666
    i32.const 10
    call $dynrt_lib_modc__fn169
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        i32.const 0
        local.set 6
        local.get 7
        i32.const 0
        i32.gt_s
        if  ;; label = @3
          block  ;; label = @4
            local.get 3
            i32.const 0
            call $dynrt_lib_modc_dynArrGet
            call $dynrt_lib_modc_dynToNumber
            local.set 8
            local.get 8
            i32.trunc_f64_s
            local.set 6
          end
        end
        local.get 4
        local.get 5
        local.get 6
        call $dynrt_lib_modc__fn9
        local.set 4
        local.get 4
        f64.convert_i32_s
        call $dynrt_lib_modc_dynNumber
        return
      end
    end
    local.get 1
    local.get 2
    i32.const 676
    i32.const 11
    call $dynrt_lib_modc__fn169
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 4
        local.get 5
        call $dynrt_lib_modc__fn13
        local.set 5
        nop
        local.set 4
        local.get 4
        local.get 5
        call $dynrt_lib_modc_dynString
        return
      end
    end
    local.get 1
    local.get 2
    i32.const 687
    i32.const 11
    call $dynrt_lib_modc__fn169
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 4
        local.get 5
        call $dynrt_lib_modc__fn14
        local.set 5
        nop
        local.set 4
        local.get 4
        local.get 5
        call $dynrt_lib_modc_dynString
        return
      end
    end
    local.get 1
    local.get 2
    i32.const 698
    i32.const 4
    call $dynrt_lib_modc__fn169
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 4
        local.get 5
        call $dynrt_lib_modc__fn8
        local.set 5
        nop
        local.set 4
        local.get 4
        local.get 5
        call $dynrt_lib_modc_dynString
        return
      end
    end
    local.get 1
    local.get 2
    i32.const 566
    i32.const 5
    call $dynrt_lib_modc__fn169
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        i32.const 0
        local.set 9
        local.get 6
        local.set 10
        local.get 7
        i32.const 0
        i32.gt_s
        if  ;; label = @3
          block  ;; label = @4
            local.get 3
            i32.const 0
            call $dynrt_lib_modc_dynArrGet
            call $dynrt_lib_modc_dynToNumber
            local.set 8
            local.get 8
            i32.trunc_f64_s
            local.set 9
          end
        end
        local.get 7
        i32.const 1
        i32.gt_s
        if  ;; label = @3
          block  ;; label = @4
            local.get 3
            i32.const 1
            call $dynrt_lib_modc_dynArrGet
            call $dynrt_lib_modc_dynToNumber
            local.set 8
            local.get 8
            i32.trunc_f64_s
            local.set 10
          end
        end
        local.get 9
        i32.const 0
        i32.lt_s
        if  ;; label = @3
          local.get 6
          local.get 9
          i32.add
          local.set 9
        end
        local.get 10
        i32.const 0
        i32.lt_s
        if  ;; label = @3
          local.get 6
          local.get 10
          i32.add
          local.set 10
        end
        local.get 9
        i32.const 0
        i32.lt_s
        if  ;; label = @3
          i32.const 0
          local.set 9
        end
        local.get 10
        local.get 6
        i32.gt_s
        if  ;; label = @3
          local.get 6
          local.set 10
        end
        local.get 9
        local.get 10
        i32.ge_s
        if  ;; label = @3
          i32.const 520
          i32.const 0
          call $dynrt_lib_modc_dynString
          return
        end
        local.get 4
        local.get 5
        local.get 9
        local.get 10
        call $dynrt_lib_modc__fn6
        local.set 5
        nop
        local.set 4
        local.get 4
        local.get 5
        call $dynrt_lib_modc_dynString
        return
      end
    end
    local.get 1
    local.get 2
    i32.const 546
    i32.const 7
    call $dynrt_lib_modc__fn169
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        i32.const 520
        local.set 6
        i32.const 0
        local.set 9
        local.get 7
        i32.const 0
        i32.gt_s
        if  ;; label = @3
          block  ;; label = @4
            local.get 3
            i32.const 0
            call $dynrt_lib_modc_dynArrGet
            call $dynrt_lib_modc__fn85
            global.get $dynrt_lib_modc_global2
            local.set 6
            global.get $dynrt_lib_modc_global3
            local.set 9
          end
        end
        local.get 4
        local.get 5
        local.get 6
        local.get 9
        call $dynrt_lib_modc__fn7
        local.set 6
        local.get 6
        f64.convert_i32_s
        call $dynrt_lib_modc_dynNumber
        return
      end
    end
    local.get 1
    local.get 2
    i32.const 553
    i32.const 8
    call $dynrt_lib_modc__fn169
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        i32.const 520
        local.set 6
        i32.const 0
        local.set 9
        local.get 7
        i32.const 0
        i32.gt_s
        if  ;; label = @3
          block  ;; label = @4
            local.get 3
            i32.const 0
            call $dynrt_lib_modc_dynArrGet
            call $dynrt_lib_modc__fn85
            global.get $dynrt_lib_modc_global2
            local.set 6
            global.get $dynrt_lib_modc_global3
            local.set 9
          end
        end
        local.get 4
        local.get 5
        local.get 6
        local.get 9
        call $dynrt_lib_modc__fn7
        i32.const -1
        i32.ne
        i32.const 1
        i32.eq
        if (result i32)  ;; label = @3
          i32.const 1
        else
          i32.const 0
        end
        call $dynrt_lib_modc_dynBool
        return
      end
    end
    local.get 1
    local.get 2
    i32.const 702
    i32.const 10
    call $dynrt_lib_modc__fn169
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        i32.const 520
        local.set 6
        i32.const 0
        local.set 9
        local.get 7
        i32.const 0
        i32.gt_s
        if  ;; label = @3
          block  ;; label = @4
            local.get 3
            i32.const 0
            call $dynrt_lib_modc_dynArrGet
            call $dynrt_lib_modc__fn85
            global.get $dynrt_lib_modc_global2
            local.set 6
            global.get $dynrt_lib_modc_global3
            local.set 9
          end
        end
        local.get 4
        local.get 5
        local.get 6
        local.get 9
        call $dynrt_lib_modc__fn11
        i32.const 1
        i32.eq
        if (result i32)  ;; label = @3
          i32.const 1
        else
          i32.const 0
        end
        call $dynrt_lib_modc_dynBool
        return
      end
    end
    local.get 1
    local.get 2
    i32.const 712
    i32.const 8
    call $dynrt_lib_modc__fn169
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        i32.const 520
        local.set 6
        i32.const 0
        local.set 9
        local.get 7
        i32.const 0
        i32.gt_s
        if  ;; label = @3
          block  ;; label = @4
            local.get 3
            i32.const 0
            call $dynrt_lib_modc_dynArrGet
            call $dynrt_lib_modc__fn85
            global.get $dynrt_lib_modc_global2
            local.set 6
            global.get $dynrt_lib_modc_global3
            local.set 9
          end
        end
        local.get 4
        local.get 5
        local.get 6
        local.get 9
        call $dynrt_lib_modc__fn12
        i32.const 1
        i32.eq
        if (result i32)  ;; label = @3
          i32.const 1
        else
          i32.const 0
        end
        call $dynrt_lib_modc_dynBool
        return
      end
    end
    local.get 1
    local.get 2
    i32.const 720
    i32.const 6
    call $dynrt_lib_modc__fn169
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        i32.const 0
        local.set 6
        local.get 7
        i32.const 0
        i32.gt_s
        if  ;; label = @3
          block  ;; label = @4
            local.get 3
            i32.const 0
            call $dynrt_lib_modc_dynArrGet
            call $dynrt_lib_modc_dynToNumber
            local.set 8
            local.get 8
            i32.trunc_f64_s
            local.set 6
          end
        end
        local.get 4
        local.get 5
        local.get 6
        call $dynrt_lib_modc__fn17
        local.set 5
        nop
        local.set 4
        local.get 4
        local.get 5
        call $dynrt_lib_modc_dynString
        return
      end
    end
    local.get 1
    local.get 2
    i32.const 726
    i32.const 8
    call $dynrt_lib_modc__fn169
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        i32.const 0
        local.set 6
        local.get 7
        i32.const 0
        i32.gt_s
        if  ;; label = @3
          block  ;; label = @4
            local.get 3
            i32.const 0
            call $dynrt_lib_modc_dynArrGet
            call $dynrt_lib_modc_dynToNumber
            local.set 8
            local.get 8
            i32.trunc_f64_s
            local.set 6
          end
        end
        i32.const 734
        local.set 9
        i32.const 1
        local.set 10
        local.get 7
        i32.const 1
        i32.gt_s
        if  ;; label = @3
          block  ;; label = @4
            local.get 3
            i32.const 1
            call $dynrt_lib_modc_dynArrGet
            call $dynrt_lib_modc__fn85
            global.get $dynrt_lib_modc_global2
            local.set 9
            global.get $dynrt_lib_modc_global3
            local.set 10
          end
        end
        local.get 4
        local.get 5
        local.get 6
        local.get 9
        local.get 10
        call $dynrt_lib_modc__fn15
        local.set 5
        nop
        local.set 4
        local.get 4
        local.get 5
        call $dynrt_lib_modc_dynString
        return
      end
    end
    local.get 1
    local.get 2
    i32.const 735
    i32.const 6
    call $dynrt_lib_modc__fn169
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        i32.const 0
        local.set 6
        local.get 7
        i32.const 0
        i32.gt_s
        if  ;; label = @3
          block  ;; label = @4
            local.get 3
            i32.const 0
            call $dynrt_lib_modc_dynArrGet
            call $dynrt_lib_modc_dynToNumber
            local.set 8
            local.get 8
            i32.trunc_f64_s
            local.set 6
          end
        end
        i32.const 734
        local.set 9
        i32.const 1
        local.set 10
        local.get 7
        i32.const 1
        i32.gt_s
        if  ;; label = @3
          block  ;; label = @4
            local.get 3
            i32.const 1
            call $dynrt_lib_modc_dynArrGet
            call $dynrt_lib_modc__fn85
            global.get $dynrt_lib_modc_global2
            local.set 9
            global.get $dynrt_lib_modc_global3
            local.set 10
          end
        end
        local.get 4
        local.get 5
        local.get 6
        local.get 9
        local.get 10
        call $dynrt_lib_modc__fn16
        local.set 5
        nop
        local.set 4
        local.get 4
        local.get 5
        call $dynrt_lib_modc_dynString
        return
      end
    end
    local.get 1
    local.get 2
    i32.const 571
    i32.const 6
    call $dynrt_lib_modc__fn169
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        i32.const 520
        local.set 6
        i32.const 0
        local.set 9
        local.get 7
        i32.const 0
        i32.gt_s
        if  ;; label = @3
          block  ;; label = @4
            local.get 3
            i32.const 0
            call $dynrt_lib_modc_dynArrGet
            call $dynrt_lib_modc__fn85
            global.get $dynrt_lib_modc_global2
            local.set 6
            global.get $dynrt_lib_modc_global3
            local.set 9
          end
        end
        local.get 4
        local.tee 11
        local.set 4
        local.get 5
        local.tee 12
        local.set 5
        local.get 4
        local.get 5
        local.get 6
        local.get 9
        call $dynrt_lib_modc__fn5
        local.set 5
        nop
        local.set 4
        local.get 4
        local.get 5
        call $dynrt_lib_modc_dynString
        return
      end
    end
    local.get 1
    local.get 2
    i32.const 741
    i32.const 5
    call $dynrt_lib_modc__fn169
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        i32.const 520
        local.set 6
        i32.const 0
        local.tee 14
        local.set 9
        local.get 7
        i32.const 0
        i32.gt_s
        if  ;; label = @3
          block  ;; label = @4
            local.get 3
            i32.const 0
            call $dynrt_lib_modc_dynArrGet
            call $dynrt_lib_modc__fn85
            global.get $dynrt_lib_modc_global2
            local.set 6
            global.get $dynrt_lib_modc_global3
            local.set 9
          end
        end
        local.get 4
        local.get 5
        local.get 6
        local.get 9
        call $dynrt_lib_modc__fn18
        local.set 4
        call $dynrt_lib_modc_dynArray
        local.set 5
        local.get 4
        i32.load
        local.set 6
        i32.const 0
        local.tee 15
        local.set 7
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 7
              local.get 6
              i32.lt_s
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                local.get 4
                i32.const 8
                i32.add
                local.get 7
                i32.const 3
                i32.shl
                i32.add
                i32.load
                local.set 9
                local.get 4
                i32.const 8
                i32.add
                local.get 7
                i32.const 3
                i32.shl
                i32.add
                i32.load offset=4
                local.set 10
                local.get 5
                local.get 9
                local.get 10
                call $dynrt_lib_modc_dynString
                call $dynrt_lib_modc_dynPush
                local.get 7
                local.tee 13
                i32.const 1
                i32.add
                local.set 7
              end
              br 1 (;@4;)
            end
          end
        end
        local.get 5
        local.tee 16
        return
      end
    end
    local.get 1
    local.get 2
    i32.const 746
    i32.const 5
    call $dynrt_lib_modc__fn169
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        i32.const 520
        local.set 6
        i32.const 0
        local.set 9
        local.get 7
        i32.const 0
        i32.gt_s
        if  ;; label = @3
          block  ;; label = @4
            local.get 3
            i32.const 0
            call $dynrt_lib_modc_dynArrGet
            local.set 7
            local.get 7
            local.set 10
            local.get 10
            i32.const 8
            i32.add
            i32.load
            i32.const 6
            i32.eq
            if  ;; label = @5
              block  ;; label = @6
                local.get 7
                i32.const 751
                i32.const 7
                call $dynrt_lib_modc_dynGet
                local.set 7
                local.get 7
                i32.const -1
                i32.ne
                if  ;; label = @7
                  block  ;; label = @8
                    local.get 7
                    call $dynrt_lib_modc__fn85
                    global.get $dynrt_lib_modc_global2
                    local.set 6
                    global.get $dynrt_lib_modc_global3
                    local.set 9
                  end
                end
              end
            else
              local.get 10
              i32.const 8
              i32.add
              i32.load
              i32.const 4
              i32.eq
              if  ;; label = @6
                block  ;; label = @7
                  local.get 7
                  call $dynrt_lib_modc__fn85
                  global.get $dynrt_lib_modc_global2
                  local.set 6
                  global.get $dynrt_lib_modc_global3
                  local.set 9
                end
              end
            end
          end
        end
        local.get 6
        local.get 9
        local.get 4
        local.get 5
        call $dynrt_lib_modc__fn127
        return
      end
    end
    call $dynrt_lib_modc_dynUndefined
    return)
  (func $dynrt_lib_modc__fn102 (param i32 i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 2
    call $dynrt_lib_modc_dynArrLen
    local.set 3
    call $dynrt_lib_modc_dynUndefined
    local.set 4
    local.get 3
    i32.const 0
    i32.gt_s
    if  ;; label = @1
      local.get 2
      i32.const 0
      call $dynrt_lib_modc_dynArrGet
      local.set 4
    end
    local.get 4
    local.set 5
    local.get 0
    local.get 1
    i32.const 758
    i32.const 6
    call $dynrt_lib_modc__fn169
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        call $dynrt_lib_modc_dynObject
        local.set 3
        local.get 3
        local.tee 11
        local.set 6
        local.get 5
        i32.const 8
        i32.add
        i32.load
        i32.const 6
        i32.eq
        if  ;; label = @3
          local.get 6
          i32.const 8
          i32.add
          i32.const 8
          i32.add
          local.get 4
          i32.store
        end
        local.get 3
        local.tee 12
        return
      end
    end
    local.get 0
    local.get 1
    i32.const 764
    i32.const 4
    call $dynrt_lib_modc__fn169
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        call $dynrt_lib_modc_dynArray
        local.set 3
        local.get 5
        i32.const 8
        i32.add
        i32.load
        i32.const 6
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 4
            call $dynrt_lib_modc_dynObjLen
            local.set 5
            i32.const 0
            local.set 6
            block  ;; label = @5
              loop  ;; label = @6
                block  ;; label = @7
                  local.get 6
                  local.get 5
                  i32.lt_s
                  i32.eqz
                  br_if 2 (;@5;)
                  block  ;; label = @8
                    local.get 3
                    local.get 4
                    local.get 6
                    call $dynrt_lib_modc__fn95
                    call $dynrt_lib_modc_dynPush
                    local.get 6
                    local.tee 13
                    i32.const 1
                    i32.add
                    local.set 6
                  end
                  br 1 (;@6;)
                end
              end
            end
          end
        end
        local.get 3
        return
      end
    end
    local.get 0
    local.get 1
    i32.const 768
    i32.const 6
    call $dynrt_lib_modc__fn169
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        call $dynrt_lib_modc_dynArray
        local.set 3
        local.get 5
        i32.const 8
        i32.add
        i32.load
        i32.const 6
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 4
            call $dynrt_lib_modc_dynObjLen
            local.set 5
            i32.const 0
            local.set 6
            block  ;; label = @5
              loop  ;; label = @6
                block  ;; label = @7
                  local.get 6
                  local.get 5
                  i32.lt_s
                  i32.eqz
                  br_if 2 (;@5;)
                  block  ;; label = @8
                    local.get 3
                    local.get 4
                    local.get 6
                    call $dynrt_lib_modc_dynObjValAt
                    call $dynrt_lib_modc_dynPush
                    local.get 6
                    local.tee 14
                    i32.const 1
                    i32.add
                    local.set 6
                  end
                  br 1 (;@6;)
                end
              end
            end
          end
        end
        local.get 3
        return
      end
    end
    local.get 0
    local.get 1
    i32.const 774
    i32.const 7
    call $dynrt_lib_modc__fn169
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        call $dynrt_lib_modc_dynArray
        local.set 3
        local.get 5
        i32.const 8
        i32.add
        i32.load
        i32.const 6
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 4
            call $dynrt_lib_modc_dynObjLen
            local.set 5
            i32.const 0
            local.set 6
            block  ;; label = @5
              loop  ;; label = @6
                block  ;; label = @7
                  local.get 6
                  local.get 5
                  i32.lt_s
                  i32.eqz
                  br_if 2 (;@5;)
                  block  ;; label = @8
                    call $dynrt_lib_modc_dynArray
                    local.set 7
                    local.get 7
                    local.get 4
                    local.get 6
                    call $dynrt_lib_modc__fn95
                    call $dynrt_lib_modc_dynPush
                    local.get 7
                    local.get 4
                    local.get 6
                    call $dynrt_lib_modc_dynObjValAt
                    call $dynrt_lib_modc_dynPush
                    local.get 3
                    local.get 7
                    call $dynrt_lib_modc_dynPush
                    local.get 6
                    local.tee 15
                    i32.const 1
                    i32.add
                    local.set 6
                  end
                  br 1 (;@6;)
                end
              end
            end
          end
        end
        local.get 3
        return
      end
    end
    local.get 0
    local.get 1
    i32.const 781
    i32.const 6
    call $dynrt_lib_modc__fn169
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        i32.const 1
        local.set 7
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 7
              local.get 3
              i32.lt_s
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                local.get 2
                local.get 7
                call $dynrt_lib_modc_dynArrGet
                local.set 8
                local.get 8
                local.set 5
                local.get 5
                i32.const 8
                i32.add
                i32.load
                i32.const 6
                i32.eq
                if  ;; label = @7
                  block  ;; label = @8
                    local.get 8
                    call $dynrt_lib_modc_dynObjLen
                    local.set 5
                    i32.const 0
                    local.set 6
                    block  ;; label = @9
                      loop  ;; label = @10
                        block  ;; label = @11
                          local.get 6
                          local.get 5
                          i32.lt_s
                          i32.eqz
                          br_if 2 (;@9;)
                          block  ;; label = @12
                            local.get 8
                            local.get 6
                            call $dynrt_lib_modc__fn95
                            call $dynrt_lib_modc__fn85
                            global.get $dynrt_lib_modc_global2
                            local.set 9
                            global.get $dynrt_lib_modc_global3
                            local.set 10
                            local.get 4
                            local.get 9
                            local.get 10
                            local.get 8
                            local.get 6
                            call $dynrt_lib_modc_dynObjValAt
                            call $dynrt_lib_modc_dynSet
                            local.get 6
                            local.tee 16
                            i32.const 1
                            i32.add
                            local.set 6
                          end
                          br 1 (;@10;)
                        end
                      end
                    end
                  end
                end
                local.get 7
                local.tee 17
                i32.const 1
                i32.add
                local.set 7
              end
              br 1 (;@4;)
            end
          end
        end
        local.get 4
        return
      end
    end
    call $dynrt_lib_modc_dynUndefined
    return)
  (func $dynrt_lib_modc__fn103 (param i32 i32 i32) (result i32)
    (local i32) (local f64) (local f64) (local i32) (local f64) (local f64) (local f64) (local f64) (local f64) (local i32) (local f64) (local i32) (local f64) (local f64) (local f64)
    local.get 2
    call $dynrt_lib_modc_dynArrLen
    local.set 3
    f64.const 0x0p+0 (;=0;)
    local.tee 16
    local.set 4
    local.get 3
    i32.const 0
    i32.gt_s
    if  ;; label = @1
      local.get 2
      i32.const 0
      call $dynrt_lib_modc_dynArrGet
      call $dynrt_lib_modc_dynToNumber
      local.set 4
    end
    local.get 0
    local.get 1
    i32.const 787
    i32.const 5
    call $dynrt_lib_modc__fn169
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 4
        local.tee 7
        f64.floor
        local.set 4
        local.get 4
        call $dynrt_lib_modc_dynNumber
        return
      end
    end
    local.get 0
    local.get 1
    i32.const 792
    i32.const 4
    call $dynrt_lib_modc__fn169
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 4
        local.tee 8
        f64.ceil
        local.set 4
        local.get 4
        call $dynrt_lib_modc_dynNumber
        return
      end
    end
    local.get 0
    local.get 1
    i32.const 796
    i32.const 5
    call $dynrt_lib_modc__fn169
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 4
        local.tee 9
        f64.const 0x1.0p-1 (;=0.5;)
        f64.add
        f64.floor
        local.set 4
        local.get 4
        call $dynrt_lib_modc_dynNumber
        return
      end
    end
    local.get 0
    local.get 1
    i32.const 801
    i32.const 3
    call $dynrt_lib_modc__fn169
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 4
        local.tee 10
        f64.abs
        local.set 4
        local.get 4
        call $dynrt_lib_modc_dynNumber
        return
      end
    end
    local.get 0
    local.get 1
    i32.const 804
    i32.const 4
    call $dynrt_lib_modc__fn169
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 4
        local.tee 11
        f64.sqrt
        local.set 4
        local.get 4
        call $dynrt_lib_modc_dynNumber
        return
      end
    end
    local.get 0
    local.get 1
    i32.const 808
    i32.const 4
    call $dynrt_lib_modc__fn169
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        f64.const 0x0p+0 (;=0;)
        local.set 5
        local.get 4
        f64.const 0x0p+0 (;=0;)
        f64.gt
        if  ;; label = @3
          f64.const 0x1.0p+0 (;=1;)
          local.set 5
        end
        local.get 4
        f64.const 0x0p+0 (;=0;)
        f64.lt
        if  ;; label = @3
          f64.const 0x0p+0 (;=0;)
          f64.const 0x1.0p+0 (;=1;)
          f64.sub
          local.set 5
        end
        local.get 5
        call $dynrt_lib_modc_dynNumber
        return
      end
    end
    local.get 0
    local.get 1
    i32.const 812
    i32.const 5
    call $dynrt_lib_modc__fn169
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 4
        f64.floor
        local.set 5
        local.get 4
        f64.const 0x0p+0 (;=0;)
        f64.lt
        if  ;; label = @3
          local.get 4
          f64.ceil
          local.set 5
        end
        local.get 5
        call $dynrt_lib_modc_dynNumber
        return
      end
    end
    local.get 0
    local.get 1
    i32.const 817
    i32.const 3
    call $dynrt_lib_modc__fn169
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 4
        local.tee 13
        local.set 4
        i32.const 1
        local.set 6
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 6
              local.get 3
              i32.lt_s
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                local.get 2
                local.get 6
                call $dynrt_lib_modc_dynArrGet
                call $dynrt_lib_modc_dynToNumber
                local.set 5
                local.get 5
                local.get 4
                f64.gt
                if  ;; label = @7
                  local.get 5
                  local.set 4
                end
                local.get 6
                local.tee 12
                i32.const 1
                i32.add
                local.set 6
              end
              br 1 (;@4;)
            end
          end
        end
        local.get 4
        call $dynrt_lib_modc_dynNumber
        return
      end
    end
    local.get 0
    local.get 1
    i32.const 820
    i32.const 3
    call $dynrt_lib_modc__fn169
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 4
        local.tee 15
        local.set 4
        i32.const 1
        local.set 6
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 6
              local.get 3
              i32.lt_s
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                local.get 2
                local.get 6
                call $dynrt_lib_modc_dynArrGet
                call $dynrt_lib_modc_dynToNumber
                local.set 5
                local.get 5
                local.get 4
                f64.lt
                if  ;; label = @7
                  local.get 5
                  local.set 4
                end
                local.get 6
                local.tee 14
                i32.const 1
                i32.add
                local.set 6
              end
              br 1 (;@4;)
            end
          end
        end
        local.get 4
        call $dynrt_lib_modc_dynNumber
        return
      end
    end
    f64.const 0x0p+0 (;=0;)
    local.tee 17
    local.set 5
    local.get 3
    i32.const 1
    i32.gt_s
    if  ;; label = @1
      local.get 2
      i32.const 1
      call $dynrt_lib_modc_dynArrGet
      call $dynrt_lib_modc_dynToNumber
      local.set 5
    end
    local.get 0
    local.get 1
    i32.const 823
    i32.const 3
    call $dynrt_lib_modc__fn169
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 4
        local.get 5
        call $dynrt_lib_modc__fn28
        local.set 4
        local.get 4
        call $dynrt_lib_modc_dynNumber
        return
      end
    end
    call $dynrt_lib_modc_dynUndefined
    return)
  (func $dynrt_lib_modc__fn104 (param i32 i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    i32.const 826
    local.tee 21
    local.set 2
    i32.const 1
    local.tee 22
    local.set 3
    local.get 1
    local.set 4
    i32.const 0
    local.set 5
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 5
          local.get 4
          i32.lt_s
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 0
            local.get 1
            local.get 5
            call $dynrt_lib_modc__fn9
            local.set 6
            local.get 6
            i32.const 34
            i32.eq
            if  ;; label = @5
              block  ;; label = @6
                local.get 2
                local.tee 8
                local.set 2
                local.get 3
                local.tee 9
                local.set 3
                local.get 2
                local.get 3
                i32.const 827
                i32.const 2
                call $dynrt_lib_modc__fn5
                local.set 3
                nop
                local.set 2
              end
            else
              local.get 6
              i32.const 92
              i32.eq
              if  ;; label = @6
                block  ;; label = @7
                  local.get 2
                  local.tee 10
                  local.set 2
                  local.get 3
                  local.tee 11
                  local.set 3
                  local.get 2
                  local.get 3
                  i32.const 829
                  i32.const 2
                  call $dynrt_lib_modc__fn5
                  local.set 3
                  nop
                  local.set 2
                end
              else
                local.get 6
                i32.const 10
                i32.eq
                if  ;; label = @7
                  block  ;; label = @8
                    local.get 2
                    local.tee 12
                    local.set 2
                    local.get 3
                    local.tee 13
                    local.set 3
                    local.get 2
                    local.get 3
                    i32.const 831
                    i32.const 2
                    call $dynrt_lib_modc__fn5
                    local.set 3
                    nop
                    local.set 2
                  end
                else
                  local.get 6
                  i32.const 13
                  i32.eq
                  if  ;; label = @8
                    block  ;; label = @9
                      local.get 2
                      local.tee 14
                      local.set 2
                      local.get 3
                      local.tee 15
                      local.set 3
                      local.get 2
                      local.get 3
                      i32.const 833
                      i32.const 2
                      call $dynrt_lib_modc__fn5
                      local.set 3
                      nop
                      local.set 2
                    end
                  else
                    local.get 6
                    i32.const 9
                    i32.eq
                    if  ;; label = @9
                      block  ;; label = @10
                        local.get 2
                        local.tee 16
                        local.set 2
                        local.get 3
                        local.tee 17
                        local.set 3
                        local.get 2
                        local.get 3
                        i32.const 835
                        i32.const 2
                        call $dynrt_lib_modc__fn5
                        local.set 3
                        nop
                        local.set 2
                      end
                    else
                      block  ;; label = @10
                        local.get 0
                        local.get 1
                        local.get 5
                        call $dynrt_lib_modc__fn10
                        local.set 7
                        nop
                        local.set 6
                        local.get 2
                        local.tee 18
                        local.set 2
                        local.get 3
                        local.tee 19
                        local.set 3
                        local.get 2
                        local.get 3
                        local.get 6
                        local.get 7
                        call $dynrt_lib_modc__fn5
                        local.set 3
                        nop
                        local.set 2
                      end
                    end
                  end
                end
              end
            end
            local.get 5
            local.tee 20
            i32.const 1
            i32.add
            local.set 5
          end
          br 1 (;@2;)
        end
      end
    end
    local.get 2
    local.tee 23
    local.set 2
    local.get 3
    local.tee 24
    local.set 3
    local.get 2
    local.get 3
    i32.const 826
    i32.const 1
    call $dynrt_lib_modc__fn5
    local.set 3
    nop
    local.set 2
    local.get 2
    local.tee 25
    local.set 2
    local.get 3
    local.tee 26
    local.set 3
    local.get 2
    local.tee 27
    global.set $dynrt_lib_modc_global2
    local.get 3
    local.tee 28
    global.set $dynrt_lib_modc_global3
    return)
  (func $dynrt_lib_modc__fn105 (param i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.set 1
    local.get 1
    i32.const 8
    i32.add
    i32.load
    local.set 1
    local.get 1
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        i32.const 529
        local.set 1
        i32.const 4
        local.set 2
        local.get 1
        global.set $dynrt_lib_modc_global2
        local.get 2
        global.set $dynrt_lib_modc_global3
        return
      end
    end
    local.get 1
    i32.eqz
    if  ;; label = @1
      block  ;; label = @2
        i32.const 529
        local.set 1
        i32.const 4
        local.set 2
        local.get 1
        global.set $dynrt_lib_modc_global2
        local.get 2
        global.set $dynrt_lib_modc_global3
        return
      end
    end
    local.get 1
    i32.const 2
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 0
        call $dynrt_lib_modc_dynToBool
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            i32.const 525
            local.set 1
            i32.const 4
            local.set 2
            local.get 1
            global.set $dynrt_lib_modc_global2
            local.get 2
            global.set $dynrt_lib_modc_global3
            return
          end
        end
        i32.const 520
        local.set 1
        i32.const 5
        local.set 2
        local.get 1
        global.set $dynrt_lib_modc_global2
        local.get 2
        global.set $dynrt_lib_modc_global3
        return
      end
    end
    local.get 1
    i32.const 3
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 0
        call $dynrt_lib_modc__fn86
        global.get $dynrt_lib_modc_global2
        local.set 1
        global.get $dynrt_lib_modc_global3
        local.set 2
        local.get 1
        local.tee 9
        local.set 1
        local.get 2
        local.tee 10
        local.set 2
        local.get 1
        local.tee 11
        global.set $dynrt_lib_modc_global2
        local.get 2
        local.tee 12
        global.set $dynrt_lib_modc_global3
        return
      end
    end
    local.get 1
    i32.const 4
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 0
        call $dynrt_lib_modc__fn85
        global.get $dynrt_lib_modc_global2
        global.get $dynrt_lib_modc_global3
        call $dynrt_lib_modc__fn104
        global.get $dynrt_lib_modc_global2
        local.tee 13
        local.set 1
        global.get $dynrt_lib_modc_global3
        local.tee 14
        local.set 2
        local.get 1
        local.tee 15
        local.set 1
        local.get 2
        local.tee 16
        local.set 2
        local.get 1
        local.tee 17
        global.set $dynrt_lib_modc_global2
        local.get 2
        local.tee 18
        global.set $dynrt_lib_modc_global3
        return
      end
    end
    local.get 1
    i32.const 5
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        i32.const 837
        local.set 1
        i32.const 1
        local.tee 24
        local.set 2
        local.get 0
        call $dynrt_lib_modc_dynArrLen
        local.set 3
        i32.const 0
        local.set 4
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 4
              local.get 3
              i32.lt_s
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                local.get 4
                i32.const 0
                i32.gt_s
                if  ;; label = @7
                  block  ;; label = @8
                    local.get 1
                    local.tee 19
                    local.set 1
                    local.get 2
                    local.tee 20
                    local.set 2
                    local.get 1
                    local.get 2
                    i32.const 565
                    i32.const 1
                    call $dynrt_lib_modc__fn5
                    local.set 2
                    nop
                    local.set 1
                  end
                end
                local.get 0
                local.get 4
                call $dynrt_lib_modc_dynArrGet
                call $dynrt_lib_modc__fn105
                global.get $dynrt_lib_modc_global2
                local.set 5
                global.get $dynrt_lib_modc_global3
                local.set 6
                local.get 1
                local.tee 21
                local.set 1
                local.get 2
                local.tee 22
                local.set 2
                local.get 1
                local.get 2
                local.get 5
                local.get 6
                call $dynrt_lib_modc__fn5
                local.set 2
                nop
                local.set 1
                local.get 4
                local.tee 23
                i32.const 1
                i32.add
                local.set 4
              end
              br 1 (;@4;)
            end
          end
        end
        local.get 1
        local.tee 25
        local.set 1
        local.get 2
        local.tee 26
        local.set 2
        local.get 1
        local.get 2
        i32.const 838
        i32.const 1
        call $dynrt_lib_modc__fn5
        local.set 2
        nop
        local.set 1
        local.get 1
        local.tee 27
        local.set 1
        local.get 2
        local.tee 28
        local.set 2
        local.get 1
        local.tee 29
        global.set $dynrt_lib_modc_global2
        local.get 2
        local.tee 30
        global.set $dynrt_lib_modc_global3
        return
      end
    end
    local.get 1
    i32.const 6
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        i32.const 839
        local.set 1
        i32.const 1
        local.tee 41
        local.set 2
        local.get 0
        call $dynrt_lib_modc_dynObjLen
        local.set 3
        i32.const 0
        local.set 4
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 4
              local.get 3
              i32.lt_s
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                local.get 4
                i32.const 0
                i32.gt_s
                if  ;; label = @7
                  block  ;; label = @8
                    local.get 1
                    local.tee 31
                    local.set 1
                    local.get 2
                    local.tee 32
                    local.set 2
                    local.get 1
                    local.get 2
                    i32.const 565
                    i32.const 1
                    call $dynrt_lib_modc__fn5
                    local.set 2
                    nop
                    local.set 1
                  end
                end
                local.get 0
                local.get 4
                call $dynrt_lib_modc__fn95
                call $dynrt_lib_modc__fn85
                global.get $dynrt_lib_modc_global2
                global.get $dynrt_lib_modc_global3
                call $dynrt_lib_modc__fn104
                global.get $dynrt_lib_modc_global2
                local.tee 33
                local.set 5
                global.get $dynrt_lib_modc_global3
                local.tee 34
                local.set 6
                local.get 0
                local.get 4
                call $dynrt_lib_modc_dynObjValAt
                call $dynrt_lib_modc__fn105
                global.get $dynrt_lib_modc_global2
                local.tee 35
                local.set 7
                global.get $dynrt_lib_modc_global3
                local.tee 36
                local.set 8
                local.get 1
                local.tee 37
                local.set 1
                local.get 2
                local.tee 38
                local.set 2
                local.get 1
                local.get 2
                local.get 5
                local.get 6
                call $dynrt_lib_modc__fn5
                local.set 2
                nop
                local.set 1
                local.get 1
                local.get 2
                i32.const 840
                i32.const 1
                call $dynrt_lib_modc__fn5
                local.set 2
                nop
                local.set 1
                local.get 1
                local.get 2
                local.get 7
                local.get 8
                call $dynrt_lib_modc__fn5
                local.set 2
                nop
                local.set 1
                local.get 4
                local.tee 39
                i32.const 1
                local.tee 40
                i32.add
                local.set 4
              end
              br 1 (;@4;)
            end
          end
        end
        local.get 1
        local.tee 42
        local.set 1
        local.get 2
        local.tee 43
        local.set 2
        local.get 1
        local.get 2
        i32.const 841
        i32.const 1
        call $dynrt_lib_modc__fn5
        local.set 2
        nop
        local.set 1
        local.get 1
        local.tee 44
        local.set 1
        local.get 2
        local.tee 45
        local.set 2
        local.get 1
        local.tee 46
        global.set $dynrt_lib_modc_global2
        local.get 2
        local.tee 47
        global.set $dynrt_lib_modc_global3
        return
      end
    end
    i32.const 529
    local.set 1
    i32.const 4
    local.set 2
    local.get 1
    local.tee 48
    global.set $dynrt_lib_modc_global2
    local.get 2
    global.set $dynrt_lib_modc_global3
    return)
  (func $dynrt_lib_modc__fn106 (param i32 i32) (result i32)
    (local i32) (local i32)
    global.get $dynrt_lib_modc_global20
    local.set 2
    i32.const 0
    global.set $dynrt_lib_modc_global20
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn189
    local.set 3
    local.get 2
    global.set $dynrt_lib_modc_global20
    local.get 3
    return)
  (func $dynrt_lib_modc__fn107 (param i32)
    (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.tee 3
    local.set 1
    local.get 1
    i32.const 8
    i32.add
    i32.load
    local.set 1
    local.get 1
    i32.const 4
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 0
        call $dynrt_lib_modc__fn85
        global.get $dynrt_lib_modc_global2
        local.set 1
        global.get $dynrt_lib_modc_global3
        local.set 2
        local.get 1
        global.set $dynrt_lib_modc_global2
        local.get 2
        global.set $dynrt_lib_modc_global3
        return
      end
    end
    local.get 1
    i32.eqz
    if  ;; label = @1
      block  ;; label = @2
        i32.const 533
        local.set 1
        i32.const 9
        local.set 2
        local.get 1
        global.set $dynrt_lib_modc_global2
        local.get 2
        global.set $dynrt_lib_modc_global3
        return
      end
    end
    local.get 0
    call $dynrt_lib_modc__fn105
    global.get $dynrt_lib_modc_global2
    local.set 1
    global.get $dynrt_lib_modc_global3
    local.set 2
    local.get 1
    local.tee 4
    global.set $dynrt_lib_modc_global2
    local.get 2
    global.set $dynrt_lib_modc_global3
    return)
  (func $dynrt_lib_modc__fn108 (param i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    i32.const 520
    local.set 1
    i32.const 0
    local.tee 12
    local.set 2
    local.get 0
    call $dynrt_lib_modc_dynArrLen
    local.set 3
    i32.const 0
    local.tee 13
    local.set 4
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 4
          local.get 3
          i32.lt_s
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 4
            i32.const 0
            i32.gt_s
            if  ;; label = @5
              block  ;; label = @6
                local.get 1
                local.tee 7
                local.set 1
                local.get 2
                local.tee 8
                local.set 2
                local.get 1
                local.get 2
                i32.const 734
                i32.const 1
                call $dynrt_lib_modc__fn5
                local.set 2
                nop
                local.set 1
              end
            end
            local.get 0
            local.get 4
            call $dynrt_lib_modc_dynArrGet
            call $dynrt_lib_modc__fn107
            global.get $dynrt_lib_modc_global2
            local.set 5
            global.get $dynrt_lib_modc_global3
            local.set 6
            local.get 1
            local.tee 9
            local.set 1
            local.get 2
            local.tee 10
            local.set 2
            local.get 1
            local.get 2
            local.get 5
            local.get 6
            call $dynrt_lib_modc__fn5
            local.set 2
            nop
            local.set 1
            local.get 4
            local.tee 11
            i32.const 1
            i32.add
            local.set 4
          end
          br 1 (;@2;)
        end
      end
    end
    local.get 1
    local.tee 14
    local.set 1
    local.get 2
    local.tee 15
    local.set 2
    local.get 1
    local.tee 16
    global.set $dynrt_lib_modc_global2
    local.get 2
    local.tee 17
    global.set $dynrt_lib_modc_global3
    return)
  (func $dynrt_lib_modc__fn109 (param i32 i32) (result i32)
    (local i32) (local i32)
    local.get 0
    call $dynrt_lib_modc_dynArrLen
    local.set 2
    i32.const 0
    local.set 3
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 3
          local.get 2
          i32.lt_s
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 0
            local.get 3
            call $dynrt_lib_modc_dynArrGet
            local.get 1
            call $dynrt_lib_modc_dynStrictEq
            i32.const 1
            i32.eq
            if  ;; label = @5
              local.get 3
              return
            end
            local.get 3
            i32.const 1
            i32.add
            local.set 3
          end
          br 1 (;@2;)
        end
      end
    end
    i32.const -1
    return)
  (func $dynrt_lib_modc__fn110 (param i32) (result i32)
    (local i32) (local i32) (local i32) (local i32)
    call $dynrt_lib_modc_dynArray
    local.set 1
    local.get 0
    call $dynrt_lib_modc_dynArrLen
    local.set 2
    i32.const 0
    local.set 3
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 3
          local.get 2
          i32.lt_s
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 1
            local.get 0
            local.get 3
            call $dynrt_lib_modc_dynArrGet
            call $dynrt_lib_modc_dynPush
            local.get 3
            local.tee 4
            i32.const 1
            i32.add
            local.set 3
          end
          br 1 (;@2;)
        end
      end
    end
    local.get 1
    return)
  (func $dynrt_lib_modc__fn111 (param i32 i32)
    (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    call $dynrt_lib_modc_dynArrLen
    local.set 2
    local.get 1
    local.set 3
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 3
          local.get 2
          i32.const 1
          i32.sub
          i32.lt_s
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 0
            local.get 3
            local.get 0
            local.get 3
            i32.const 1
            i32.add
            call $dynrt_lib_modc_dynArrGet
            call $dynrt_lib_modc__fn99
            local.get 3
            i32.const 1
            i32.add
            local.tee 4
            local.set 3
          end
          br 1 (;@2;)
        end
      end
    end
    local.get 0
    local.tee 5
    local.set 3
    local.get 3
    i32.const 8
    i32.add
    i32.const 4
    i32.add
    i32.load
    local.set 3
    local.get 3
    local.tee 6
    local.set 3
    local.get 3
    i32.const 8
    i32.add
    local.get 2
    i32.const 1
    i32.sub
    i32.store)
  (func $dynrt_lib_modc__fn112 (result i32)
    (local i32) (local i32)
    call $dynrt_lib_modc_dynObject
    local.set 0
    local.get 0
    i32.const 842
    i32.const 6
    call $dynrt_lib_modc_dynArray
    call $dynrt_lib_modc_dynSet
    local.get 0
    i32.const 848
    i32.const 6
    call $dynrt_lib_modc_dynArray
    call $dynrt_lib_modc_dynSet
    local.get 0
    local.tee 1
    return)
  (func $dynrt_lib_modc__fn113 (param i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    call $dynrt_lib_modc_dynObject
    local.set 1
    call $dynrt_lib_modc_dynArray
    local.set 2
    local.get 1
    i32.const 854
    i32.const 6
    local.get 2
    call $dynrt_lib_modc_dynSet
    local.get 0
    local.set 3
    local.get 3
    i32.const 8
    i32.add
    i32.load
    i32.const 5
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 0
        call $dynrt_lib_modc_dynArrLen
        local.set 3
        i32.const 0
        local.set 4
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 4
              local.get 3
              i32.lt_s
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                local.get 0
                local.get 4
                call $dynrt_lib_modc_dynArrGet
                local.set 5
                local.get 2
                local.get 5
                call $dynrt_lib_modc__fn109
                i32.const 0
                i32.lt_s
                if  ;; label = @7
                  local.get 2
                  local.get 5
                  call $dynrt_lib_modc_dynPush
                end
                local.get 4
                local.tee 6
                i32.const 1
                i32.add
                local.set 4
              end
              br 1 (;@4;)
            end
          end
        end
      end
    end
    local.get 1
    local.tee 7
    return)
  (func $dynrt_lib_modc__fn114 (param i32 i32 i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    i32.const 842
    i32.const 6
    call $dynrt_lib_modc_dynGet
    local.set 4
    local.get 0
    i32.const 848
    i32.const 6
    call $dynrt_lib_modc_dynGet
    local.set 5
    local.get 3
    call $dynrt_lib_modc_dynArrLen
    local.set 6
    call $dynrt_lib_modc_dynUndefined
    local.set 7
    local.get 6
    i32.const 0
    i32.gt_s
    if  ;; label = @1
      local.get 3
      i32.const 0
      call $dynrt_lib_modc_dynArrGet
      local.set 7
    end
    local.get 1
    local.get 2
    i32.const 860
    i32.const 3
    call $dynrt_lib_modc__fn169
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        call $dynrt_lib_modc_dynUndefined
        local.set 8
        local.get 6
        i32.const 1
        i32.gt_s
        if  ;; label = @3
          local.get 3
          i32.const 1
          call $dynrt_lib_modc_dynArrGet
          local.set 8
        end
        local.get 4
        local.get 7
        call $dynrt_lib_modc__fn109
        local.set 6
        local.get 6
        i32.const 0
        i32.ge_s
        if  ;; label = @3
          local.get 5
          local.get 6
          local.get 8
          call $dynrt_lib_modc__fn99
        else
          block  ;; label = @4
            local.get 4
            local.get 7
            call $dynrt_lib_modc_dynPush
            local.get 5
            local.get 8
            call $dynrt_lib_modc_dynPush
          end
        end
        local.get 0
        return
      end
    end
    local.get 1
    local.get 2
    i32.const 863
    i32.const 3
    call $dynrt_lib_modc__fn169
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 4
        local.get 7
        call $dynrt_lib_modc__fn109
        local.set 6
        local.get 6
        i32.const 0
        i32.ge_s
        if  ;; label = @3
          local.get 5
          local.get 6
          call $dynrt_lib_modc_dynArrGet
          return
        end
        call $dynrt_lib_modc_dynUndefined
        return
      end
    end
    local.get 1
    local.get 2
    i32.const 866
    i32.const 3
    call $dynrt_lib_modc__fn169
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 4
        local.get 7
        call $dynrt_lib_modc__fn109
        i32.const 0
        i32.ge_s
        if  ;; label = @3
          i32.const 1
          call $dynrt_lib_modc_dynBool
          return
        end
        i32.const 0
        call $dynrt_lib_modc_dynBool
        return
      end
    end
    local.get 1
    local.get 2
    i32.const 869
    i32.const 6
    call $dynrt_lib_modc__fn169
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 4
        local.get 7
        call $dynrt_lib_modc__fn109
        local.set 6
        local.get 6
        i32.const 0
        i32.ge_s
        if  ;; label = @3
          block  ;; label = @4
            local.get 4
            local.get 6
            call $dynrt_lib_modc__fn111
            local.get 5
            local.get 6
            call $dynrt_lib_modc__fn111
            i32.const 1
            call $dynrt_lib_modc_dynBool
            return
          end
        end
        i32.const 0
        call $dynrt_lib_modc_dynBool
        return
      end
    end
    local.get 1
    local.get 2
    i32.const 764
    i32.const 4
    call $dynrt_lib_modc__fn169
    i32.const 1
    i32.eq
    if  ;; label = @1
      local.get 4
      call $dynrt_lib_modc__fn110
      return
    end
    local.get 1
    local.get 2
    i32.const 768
    i32.const 6
    call $dynrt_lib_modc__fn169
    i32.const 1
    i32.eq
    if  ;; label = @1
      local.get 5
      call $dynrt_lib_modc__fn110
      return
    end
    local.get 1
    local.get 2
    i32.const 621
    i32.const 7
    call $dynrt_lib_modc__fn169
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        call $dynrt_lib_modc_dynUndefined
        local.set 7
        local.get 6
        i32.const 0
        i32.gt_s
        if  ;; label = @3
          local.get 3
          i32.const 0
          call $dynrt_lib_modc_dynArrGet
          local.set 7
        end
        local.get 4
        call $dynrt_lib_modc_dynArrLen
        local.set 6
        i32.const 0
        local.set 8
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 8
              local.get 6
              i32.lt_s
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                call $dynrt_lib_modc_dynArray
                local.set 9
                local.get 9
                local.get 5
                local.get 8
                call $dynrt_lib_modc_dynArrGet
                call $dynrt_lib_modc_dynPush
                local.get 9
                local.get 4
                local.get 8
                call $dynrt_lib_modc_dynArrGet
                call $dynrt_lib_modc_dynPush
                local.get 7
                local.get 9
                call $dynrt_lib_modc_dynApply
                drop
                local.get 8
                local.tee 10
                i32.const 1
                i32.add
                local.set 8
              end
              br 1 (;@4;)
            end
          end
        end
        call $dynrt_lib_modc_dynUndefined
        return
      end
    end
    call $dynrt_lib_modc_dynUndefined
    return)
  (func $dynrt_lib_modc__fn115 (param i32 i32 i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    i32.const 854
    i32.const 6
    call $dynrt_lib_modc_dynGet
    local.set 4
    local.get 3
    call $dynrt_lib_modc_dynArrLen
    local.set 5
    call $dynrt_lib_modc_dynUndefined
    local.set 6
    local.get 5
    i32.const 0
    i32.gt_s
    if  ;; label = @1
      local.get 3
      i32.const 0
      call $dynrt_lib_modc_dynArrGet
      local.set 6
    end
    local.get 1
    local.get 2
    i32.const 875
    i32.const 3
    call $dynrt_lib_modc__fn169
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 4
        local.get 6
        call $dynrt_lib_modc__fn109
        i32.const 0
        i32.lt_s
        if  ;; label = @3
          local.get 4
          local.get 6
          call $dynrt_lib_modc_dynPush
        end
        local.get 0
        return
      end
    end
    local.get 1
    local.get 2
    i32.const 866
    i32.const 3
    call $dynrt_lib_modc__fn169
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 4
        local.get 6
        call $dynrt_lib_modc__fn109
        i32.const 0
        i32.ge_s
        if  ;; label = @3
          i32.const 1
          call $dynrt_lib_modc_dynBool
          return
        end
        i32.const 0
        call $dynrt_lib_modc_dynBool
        return
      end
    end
    local.get 1
    local.get 2
    i32.const 869
    i32.const 6
    call $dynrt_lib_modc__fn169
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 4
        local.get 6
        call $dynrt_lib_modc__fn109
        local.set 5
        local.get 5
        i32.const 0
        i32.ge_s
        if  ;; label = @3
          block  ;; label = @4
            local.get 4
            local.get 5
            call $dynrt_lib_modc__fn111
            i32.const 1
            call $dynrt_lib_modc_dynBool
            return
          end
        end
        i32.const 0
        call $dynrt_lib_modc_dynBool
        return
      end
    end
    local.get 1
    local.get 2
    i32.const 768
    i32.const 6
    call $dynrt_lib_modc__fn169
    i32.const 1
    i32.eq
    if  ;; label = @1
      local.get 4
      call $dynrt_lib_modc__fn110
      return
    end
    local.get 1
    local.get 2
    i32.const 764
    i32.const 4
    call $dynrt_lib_modc__fn169
    i32.const 1
    i32.eq
    if  ;; label = @1
      local.get 4
      call $dynrt_lib_modc__fn110
      return
    end
    local.get 1
    local.get 2
    i32.const 621
    i32.const 7
    call $dynrt_lib_modc__fn169
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        call $dynrt_lib_modc_dynUndefined
        local.set 6
        local.get 5
        i32.const 0
        i32.gt_s
        if  ;; label = @3
          local.get 3
          i32.const 0
          call $dynrt_lib_modc_dynArrGet
          local.set 6
        end
        local.get 4
        call $dynrt_lib_modc_dynArrLen
        local.set 5
        i32.const 0
        local.set 7
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 7
              local.get 5
              i32.lt_s
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                call $dynrt_lib_modc_dynArray
                local.set 8
                local.get 8
                local.get 4
                local.get 7
                call $dynrt_lib_modc_dynArrGet
                call $dynrt_lib_modc_dynPush
                local.get 6
                local.get 8
                call $dynrt_lib_modc_dynApply
                drop
                local.get 7
                local.tee 9
                i32.const 1
                i32.add
                local.set 7
              end
              br 1 (;@4;)
            end
          end
        end
        call $dynrt_lib_modc_dynUndefined
        return
      end
    end
    call $dynrt_lib_modc_dynUndefined
    return)
  (func $dynrt_lib_modc__fn116 (param i32) (result i32)
    local.get 0
    i32.const 48
    i32.ge_s
    if (result i32)  ;; label = @1
      local.get 0
      i32.const 57
      i32.le_s
    else
      i32.const 0
    end
    if (result i32)  ;; label = @1
      i32.const 1
    else
      i32.const 0
    end
    return)
  (func $dynrt_lib_modc__fn117 (param i32) (result i32)
    local.get 0
    i32.const 48
    i32.ge_s
    if (result i32)  ;; label = @1
      local.get 0
      i32.const 57
      i32.le_s
    else
      i32.const 0
    end
    if  ;; label = @1
      i32.const 1
      return
    end
    local.get 0
    i32.const 65
    i32.ge_s
    if (result i32)  ;; label = @1
      local.get 0
      i32.const 90
      i32.le_s
    else
      i32.const 0
    end
    if  ;; label = @1
      i32.const 1
      return
    end
    local.get 0
    i32.const 97
    i32.ge_s
    if (result i32)  ;; label = @1
      local.get 0
      i32.const 122
      i32.le_s
    else
      i32.const 0
    end
    if  ;; label = @1
      i32.const 1
      return
    end
    local.get 0
    i32.const 95
    i32.eq
    if  ;; label = @1
      i32.const 1
      return
    end
    i32.const 0
    return)
  (func $dynrt_lib_modc__fn118 (param i32) (result i32)
    local.get 0
    i32.const 32
    i32.eq
    if (result i32)  ;; label = @1
      i32.const 1
    else
      local.get 0
      i32.const 9
      i32.eq
    end
    if (result i32)  ;; label = @1
      i32.const 1
    else
      local.get 0
      i32.const 10
      i32.eq
    end
    if (result i32)  ;; label = @1
      i32.const 1
    else
      local.get 0
      i32.const 13
      i32.eq
    end
    if  ;; label = @1
      i32.const 1
      return
    end
    i32.const 0
    return)
  (func $dynrt_lib_modc__fn119 (param i32 i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    local.get 2
    call $dynrt_lib_modc__fn9
    local.set 3
    local.get 3
    i32.const 92
    i32.eq
    if  ;; label = @1
      i32.const 2
      return
    end
    local.get 3
    i32.const 91
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 2
        local.tee 4
        i32.const 1
        local.tee 5
        i32.add
        local.set 3
        local.get 3
        local.get 1
        i32.lt_s
        if (result i32)  ;; label = @3
          local.get 0
          local.get 1
          local.get 3
          call $dynrt_lib_modc__fn9
          i32.const 94
          i32.eq
        else
          i32.const 0
        end
        if  ;; label = @3
          local.get 3
          i32.const 1
          i32.add
          local.set 3
        end
        local.get 3
        local.get 1
        i32.lt_s
        if (result i32)  ;; label = @3
          local.get 0
          local.get 1
          local.get 3
          call $dynrt_lib_modc__fn9
          i32.const 93
          i32.eq
        else
          i32.const 0
        end
        if  ;; label = @3
          local.get 3
          i32.const 1
          i32.add
          local.set 3
        end
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 3
              local.get 1
              i32.lt_s
              if (result i32)  ;; label = @6
                local.get 0
                local.get 1
                local.get 3
                call $dynrt_lib_modc__fn9
                i32.const 93
                i32.ne
              else
                i32.const 0
              end
              i32.eqz
              br_if 2 (;@3;)
              local.get 3
              i32.const 1
              i32.add
              local.set 3
              br 1 (;@4;)
            end
          end
        end
        local.get 3
        local.get 2
        local.tee 6
        i32.sub
        i32.const 1
        local.tee 7
        i32.add
        return
      end
    end
    i32.const 1
    return)
  (func $dynrt_lib_modc__fn120 (param i32 i32 i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 2
    i32.const 1
    local.tee 13
    i32.add
    local.set 4
    i32.const 0
    local.tee 14
    local.set 5
    local.get 4
    local.get 1
    i32.lt_s
    if (result i32)  ;; label = @1
      local.get 0
      local.get 1
      local.get 4
      call $dynrt_lib_modc__fn9
      i32.const 94
      i32.eq
    else
      i32.const 0
    end
    if  ;; label = @1
      block  ;; label = @2
        i32.const 1
        local.tee 10
        local.set 5
        local.get 4
        local.get 10
        i32.add
        local.set 4
      end
    end
    i32.const 0
    local.tee 15
    local.set 6
    i32.const 1
    local.tee 16
    local.set 7
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 7
          i32.const 1
          i32.eq
          if (result i32)  ;; label = @4
            local.get 4
            local.get 1
            i32.lt_s
          else
            i32.const 0
          end
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 0
            local.get 1
            local.get 4
            call $dynrt_lib_modc__fn9
            local.set 8
            local.get 8
            i32.const 93
            i32.eq
            if  ;; label = @5
              i32.const 0
              local.set 7
            else
              local.get 4
              i32.const 2
              i32.add
              local.get 1
              i32.lt_s
              if (result i32)  ;; label = @6
                local.get 0
                local.get 1
                local.get 4
                i32.const 1
                i32.add
                call $dynrt_lib_modc__fn9
                i32.const 45
                i32.eq
              else
                i32.const 0
              end
              if (result i32)  ;; label = @6
                local.get 0
                local.get 1
                local.get 4
                i32.const 2
                i32.add
                call $dynrt_lib_modc__fn9
                i32.const 93
                i32.ne
              else
                i32.const 0
              end
              if  ;; label = @6
                block  ;; label = @7
                  local.get 0
                  local.get 1
                  local.get 4
                  i32.const 2
                  i32.add
                  call $dynrt_lib_modc__fn9
                  local.set 9
                  local.get 3
                  local.get 8
                  i32.ge_s
                  if (result i32)  ;; label = @8
                    local.get 3
                    local.get 9
                    i32.le_s
                  else
                    i32.const 0
                  end
                  if  ;; label = @8
                    i32.const 1
                    local.set 6
                  end
                  local.get 4
                  local.tee 11
                  i32.const 3
                  i32.add
                  local.set 4
                end
              else
                local.get 8
                i32.const 92
                i32.eq
                if  ;; label = @7
                  block  ;; label = @8
                    local.get 0
                    local.get 1
                    local.get 4
                    i32.const 1
                    i32.add
                    call $dynrt_lib_modc__fn9
                    local.set 8
                    local.get 8
                    i32.const 100
                    i32.eq
                    if (result i32)  ;; label = @9
                      local.get 3
                      call $dynrt_lib_modc__fn116
                      i32.const 1
                      i32.eq
                    else
                      i32.const 0
                    end
                    if  ;; label = @9
                      i32.const 1
                      local.set 6
                    else
                      local.get 8
                      i32.const 119
                      i32.eq
                      if (result i32)  ;; label = @10
                        local.get 3
                        call $dynrt_lib_modc__fn117
                        i32.const 1
                        i32.eq
                      else
                        i32.const 0
                      end
                      if  ;; label = @10
                        i32.const 1
                        local.set 6
                      else
                        local.get 8
                        i32.const 115
                        i32.eq
                        if (result i32)  ;; label = @11
                          local.get 3
                          call $dynrt_lib_modc__fn118
                          i32.const 1
                          i32.eq
                        else
                          i32.const 0
                        end
                        if  ;; label = @11
                          i32.const 1
                          local.set 6
                        else
                          local.get 3
                          local.get 8
                          i32.eq
                          if  ;; label = @12
                            i32.const 1
                            local.set 6
                          end
                        end
                      end
                    end
                    local.get 4
                    local.tee 12
                    i32.const 2
                    i32.add
                    local.set 4
                  end
                else
                  block  ;; label = @8
                    local.get 3
                    local.get 8
                    i32.eq
                    if  ;; label = @9
                      i32.const 1
                      local.set 6
                    end
                    local.get 4
                    i32.const 1
                    i32.add
                    local.set 4
                  end
                end
              end
            end
          end
          br 1 (;@2;)
        end
      end
    end
    local.get 5
    i32.const 1
    i32.eq
    if  ;; label = @1
      local.get 6
      i32.const 1
      i32.eq
      if (result i32)  ;; label = @2
        i32.const 0
      else
        i32.const 1
      end
      return
    end
    local.get 6
    return)
  (func $dynrt_lib_modc__fn121 (param i32 i32 i32 i32) (result i32)
    (local i32)
    local.get 0
    local.get 1
    local.get 2
    call $dynrt_lib_modc__fn9
    local.set 4
    local.get 4
    i32.const 46
    i32.eq
    if  ;; label = @1
      i32.const 1
      return
    end
    local.get 4
    i32.const 92
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 0
        local.get 1
        local.get 2
        i32.const 1
        i32.add
        call $dynrt_lib_modc__fn9
        local.set 4
        local.get 4
        i32.const 100
        i32.eq
        if  ;; label = @3
          local.get 3
          call $dynrt_lib_modc__fn116
          return
        end
        local.get 4
        i32.const 68
        i32.eq
        if  ;; label = @3
          local.get 3
          call $dynrt_lib_modc__fn116
          i32.const 1
          i32.eq
          if (result i32)  ;; label = @4
            i32.const 0
          else
            i32.const 1
          end
          return
        end
        local.get 4
        i32.const 119
        i32.eq
        if  ;; label = @3
          local.get 3
          call $dynrt_lib_modc__fn117
          return
        end
        local.get 4
        i32.const 87
        i32.eq
        if  ;; label = @3
          local.get 3
          call $dynrt_lib_modc__fn117
          i32.const 1
          i32.eq
          if (result i32)  ;; label = @4
            i32.const 0
          else
            i32.const 1
          end
          return
        end
        local.get 4
        i32.const 115
        i32.eq
        if  ;; label = @3
          local.get 3
          call $dynrt_lib_modc__fn118
          return
        end
        local.get 4
        i32.const 83
        i32.eq
        if  ;; label = @3
          local.get 3
          call $dynrt_lib_modc__fn118
          i32.const 1
          i32.eq
          if (result i32)  ;; label = @4
            i32.const 0
          else
            i32.const 1
          end
          return
        end
        local.get 4
        i32.const 110
        i32.eq
        if  ;; label = @3
          local.get 3
          i32.const 10
          i32.eq
          if (result i32)  ;; label = @4
            i32.const 1
          else
            i32.const 0
          end
          return
        end
        local.get 4
        i32.const 116
        i32.eq
        if  ;; label = @3
          local.get 3
          i32.const 9
          i32.eq
          if (result i32)  ;; label = @4
            i32.const 1
          else
            i32.const 0
          end
          return
        end
        local.get 3
        local.get 4
        i32.eq
        if (result i32)  ;; label = @3
          i32.const 1
        else
          i32.const 0
        end
        return
      end
    end
    local.get 4
    i32.const 91
    i32.eq
    if  ;; label = @1
      local.get 0
      local.get 1
      local.get 2
      local.get 3
      call $dynrt_lib_modc__fn120
      return
    end
    local.get 3
    local.get 4
    i32.eq
    if (result i32)  ;; label = @1
      i32.const 1
    else
      i32.const 0
    end
    return)
  (func $dynrt_lib_modc__fn122 (param i32 i32 i32 i32 i32 i32) (result i32)
    (local i32) (local i32)
    local.get 2
    local.get 1
    i32.ge_s
    if  ;; label = @1
      local.get 5
      return
    end
    local.get 0
    local.get 1
    local.get 2
    call $dynrt_lib_modc__fn9
    i32.const 36
    i32.eq
    if (result i32)  ;; label = @1
      local.get 2
      local.get 1
      i32.const 1
      i32.sub
      i32.eq
    else
      i32.const 0
    end
    if  ;; label = @1
      local.get 5
      local.get 4
      i32.eq
      if (result i32)  ;; label = @2
        local.get 5
      else
        i32.const -1
      end
      return
    end
    local.get 0
    local.get 1
    local.get 2
    call $dynrt_lib_modc__fn119
    local.set 6
    i32.const 0
    local.set 7
    local.get 2
    local.get 6
    i32.add
    local.get 1
    i32.lt_s
    if  ;; label = @1
      local.get 0
      local.get 1
      local.get 2
      local.get 6
      i32.add
      call $dynrt_lib_modc__fn9
      local.set 7
    end
    local.get 7
    i32.const 42
    i32.eq
    if  ;; label = @1
      local.get 0
      local.get 1
      local.get 2
      local.get 6
      local.get 3
      local.get 4
      local.get 5
      call $dynrt_lib_modc__fn123
      return
    end
    local.get 7
    i32.const 43
    i32.eq
    if  ;; label = @1
      local.get 0
      local.get 1
      local.get 2
      local.get 6
      local.get 3
      local.get 4
      local.get 5
      call $dynrt_lib_modc__fn124
      return
    end
    local.get 7
    i32.const 63
    i32.eq
    if  ;; label = @1
      local.get 0
      local.get 1
      local.get 2
      local.get 6
      local.get 3
      local.get 4
      local.get 5
      call $dynrt_lib_modc__fn125
      return
    end
    local.get 5
    local.get 4
    i32.lt_s
    if (result i32)  ;; label = @1
      local.get 0
      local.get 1
      local.get 2
      local.get 3
      local.get 4
      local.get 5
      call $dynrt_lib_modc__fn9
      call $dynrt_lib_modc__fn121
      i32.const 1
      i32.eq
    else
      i32.const 0
    end
    if  ;; label = @1
      local.get 0
      local.get 1
      local.get 2
      local.get 6
      i32.add
      local.get 3
      local.get 4
      local.get 5
      i32.const 1
      i32.add
      call $dynrt_lib_modc__fn122
      return
    end
    i32.const -1
    return)
  (func $dynrt_lib_modc__fn123 (param i32 i32 i32 i32 i32 i32 i32) (result i32)
    (local i32) (local i32) (local i32)
    local.get 6
    local.set 7
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 7
          local.get 5
          i32.lt_s
          if (result i32)  ;; label = @4
            local.get 0
            local.get 1
            local.get 2
            local.get 4
            local.get 5
            local.get 7
            call $dynrt_lib_modc__fn9
            call $dynrt_lib_modc__fn121
            i32.const 1
            i32.eq
          else
            i32.const 0
          end
          i32.eqz
          br_if 2 (;@1;)
          local.get 7
          i32.const 1
          i32.add
          local.set 7
          br 1 (;@2;)
        end
      end
    end
    local.get 7
    local.set 7
    i32.const 1
    local.set 8
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 8
          i32.const 1
          i32.eq
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 0
            local.get 1
            local.get 2
            local.get 3
            i32.add
            i32.const 1
            i32.add
            local.get 4
            local.get 5
            local.get 7
            call $dynrt_lib_modc__fn122
            local.set 9
            local.get 9
            i32.const 0
            i32.ge_s
            if  ;; label = @5
              local.get 9
              return
            end
            local.get 7
            local.get 6
            i32.eq
            if  ;; label = @5
              i32.const 0
              local.set 8
            else
              local.get 7
              i32.const 1
              i32.sub
              local.set 7
            end
          end
          br 1 (;@2;)
        end
      end
    end
    i32.const -1
    return)
  (func $dynrt_lib_modc__fn124 (param i32 i32 i32 i32 i32 i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 6
    local.get 5
    i32.ge_s
    if  ;; label = @1
      i32.const -1
      return
    end
    local.get 0
    local.get 1
    local.get 2
    local.get 4
    local.get 5
    local.get 6
    call $dynrt_lib_modc__fn9
    call $dynrt_lib_modc__fn121
    i32.eqz
    if  ;; label = @1
      i32.const -1
      return
    end
    local.get 6
    i32.const 1
    local.tee 10
    i32.add
    local.set 7
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 7
          local.get 5
          i32.lt_s
          if (result i32)  ;; label = @4
            local.get 0
            local.get 1
            local.get 2
            local.get 4
            local.get 5
            local.get 7
            call $dynrt_lib_modc__fn9
            call $dynrt_lib_modc__fn121
            i32.const 1
            i32.eq
          else
            i32.const 0
          end
          i32.eqz
          br_if 2 (;@1;)
          local.get 7
          i32.const 1
          i32.add
          local.set 7
          br 1 (;@2;)
        end
      end
    end
    local.get 7
    local.set 7
    i32.const 1
    local.tee 11
    local.set 8
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 8
          i32.const 1
          i32.eq
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 0
            local.get 1
            local.get 2
            local.get 3
            i32.add
            i32.const 1
            i32.add
            local.get 4
            local.get 5
            local.get 7
            call $dynrt_lib_modc__fn122
            local.set 9
            local.get 9
            i32.const 0
            i32.ge_s
            if  ;; label = @5
              local.get 9
              return
            end
            local.get 7
            local.get 6
            i32.const 1
            i32.add
            i32.eq
            if  ;; label = @5
              i32.const 0
              local.set 8
            else
              local.get 7
              i32.const 1
              i32.sub
              local.set 7
            end
          end
          br 1 (;@2;)
        end
      end
    end
    i32.const -1
    return)
  (func $dynrt_lib_modc__fn125 (param i32 i32 i32 i32 i32 i32 i32) (result i32)
    (local i32)
    local.get 6
    local.get 5
    i32.lt_s
    if (result i32)  ;; label = @1
      local.get 0
      local.get 1
      local.get 2
      local.get 4
      local.get 5
      local.get 6
      call $dynrt_lib_modc__fn9
      call $dynrt_lib_modc__fn121
      i32.const 1
      i32.eq
    else
      i32.const 0
    end
    if  ;; label = @1
      block  ;; label = @2
        local.get 0
        local.get 1
        local.get 2
        local.get 3
        i32.add
        i32.const 1
        i32.add
        local.get 4
        local.get 5
        local.get 6
        i32.const 1
        i32.add
        call $dynrt_lib_modc__fn122
        local.set 7
        local.get 7
        i32.const 0
        i32.ge_s
        if  ;; label = @3
          local.get 7
          return
        end
      end
    end
    local.get 0
    local.get 1
    local.get 2
    local.get 3
    i32.add
    i32.const 1
    i32.add
    local.get 4
    local.get 5
    local.get 6
    call $dynrt_lib_modc__fn122
    return)
  (func $dynrt_lib_modc__fn126 (param i32 i32 i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    i32.const 0
    local.tee 7
    local.set 4
    local.get 7
    local.set 5
    local.get 1
    i32.const 0
    i32.gt_s
    if (result i32)  ;; label = @1
      local.get 0
      local.get 1
      i32.const 0
      call $dynrt_lib_modc__fn9
      i32.const 94
      i32.eq
    else
      i32.const 0
    end
    if  ;; label = @1
      block  ;; label = @2
        i32.const 1
        local.tee 6
        local.set 5
        local.get 6
        local.set 4
      end
    end
    local.get 5
    i32.const 1
    i32.eq
    if  ;; label = @1
      local.get 0
      local.get 1
      local.get 4
      local.get 2
      local.get 3
      i32.const 0
      call $dynrt_lib_modc__fn122
      i32.const 0
      i32.ge_s
      if (result i32)  ;; label = @2
        i32.const 1
      else
        i32.const 0
      end
      return
    end
    i32.const 0
    local.tee 8
    local.set 5
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 5
          local.get 3
          i32.le_s
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 0
            local.get 1
            local.get 4
            local.get 2
            local.get 3
            local.get 5
            call $dynrt_lib_modc__fn122
            i32.const 0
            i32.ge_s
            if  ;; label = @5
              i32.const 1
              return
            end
            local.get 5
            i32.const 1
            i32.add
            local.set 5
          end
          br 1 (;@2;)
        end
      end
    end
    i32.const 0
    local.tee 9
    return)
  (func $dynrt_lib_modc__fn127 (param i32 i32 i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    i32.const 0
    local.tee 10
    local.set 4
    local.get 10
    local.set 5
    local.get 1
    i32.const 0
    i32.gt_s
    if (result i32)  ;; label = @1
      local.get 0
      local.get 1
      i32.const 0
      call $dynrt_lib_modc__fn9
      i32.const 94
      i32.eq
    else
      i32.const 0
    end
    if  ;; label = @1
      block  ;; label = @2
        i32.const 1
        local.tee 9
        local.set 5
        local.get 9
        local.set 4
      end
    end
    i32.const 0
    local.tee 11
    local.set 6
    i32.const 1
    local.set 7
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 7
          i32.const 1
          i32.eq
          if (result i32)  ;; label = @4
            local.get 6
            local.get 3
            i32.le_s
          else
            i32.const 0
          end
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 0
            local.get 1
            local.get 4
            local.get 2
            local.get 3
            local.get 6
            call $dynrt_lib_modc__fn122
            local.set 8
            local.get 8
            i32.const 0
            i32.ge_s
            if  ;; label = @5
              block  ;; label = @6
                local.get 2
                local.get 3
                local.get 6
                local.get 8
                call $dynrt_lib_modc__fn6
                local.set 5
                nop
                local.set 4
                local.get 4
                local.get 5
                call $dynrt_lib_modc_dynString
                return
              end
            end
            local.get 5
            i32.const 1
            i32.eq
            if  ;; label = @5
              i32.const 0
              local.set 7
            else
              local.get 6
              i32.const 1
              i32.add
              local.set 6
            end
          end
          br 1 (;@2;)
        end
      end
    end
    call $dynrt_lib_modc_dynNull
    return)
  (func $dynrt_lib_modc__fn128 (param i32) (result i32)
    (local i32) (local i32)
    call $dynrt_lib_modc_dynObject
    local.set 1
    local.get 1
    i32.const 751
    i32.const 7
    local.get 0
    call $dynrt_lib_modc_dynSet
    local.get 1
    local.tee 2
    return)
  (func $dynrt_lib_modc__fn129 (param i32 i32 i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    i32.const 751
    i32.const 7
    call $dynrt_lib_modc_dynGet
    call $dynrt_lib_modc__fn85
    global.get $dynrt_lib_modc_global2
    local.set 4
    global.get $dynrt_lib_modc_global3
    local.set 5
    local.get 3
    call $dynrt_lib_modc_dynArrLen
    local.set 6
    i32.const 520
    local.set 7
    i32.const 0
    local.set 8
    local.get 6
    i32.const 0
    i32.gt_s
    if  ;; label = @1
      block  ;; label = @2
        local.get 3
        i32.const 0
        call $dynrt_lib_modc_dynArrGet
        call $dynrt_lib_modc__fn85
        global.get $dynrt_lib_modc_global2
        local.set 7
        global.get $dynrt_lib_modc_global3
        local.set 8
      end
    end
    local.get 1
    local.get 2
    i32.const 878
    i32.const 4
    call $dynrt_lib_modc__fn169
    i32.const 1
    i32.eq
    if  ;; label = @1
      local.get 4
      local.get 5
      local.get 7
      local.get 8
      call $dynrt_lib_modc__fn126
      call $dynrt_lib_modc_dynBool
      return
    end
    local.get 1
    local.get 2
    i32.const 882
    i32.const 4
    call $dynrt_lib_modc__fn169
    i32.const 1
    i32.eq
    if  ;; label = @1
      local.get 4
      local.get 5
      local.get 7
      local.get 8
      call $dynrt_lib_modc__fn127
      return
    end
    call $dynrt_lib_modc_dynUndefined
    return)
  (func $dynrt_lib_modc__fn130 (param i32 i32 i32 i32) (result i32)
    (local i32) (local i32) (local f64) (local i32) (local i32) (local i32)
    local.get 1
    local.get 2
    i32.const 886
    i32.const 4
    call $dynrt_lib_modc__fn169
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 0
        i32.const 890
        i32.const 6
        call $dynrt_lib_modc_dynGet
        local.set 4
        local.get 0
        i32.const 896
        i32.const 6
        call $dynrt_lib_modc_dynGet
        local.set 5
        local.get 5
        call $dynrt_lib_modc_dynNumberValue
        local.set 6
        local.get 6
        i32.trunc_f64_s
        local.set 5
        local.get 4
        call $dynrt_lib_modc_dynArrLen
        local.set 7
        call $dynrt_lib_modc_dynObject
        local.set 8
        local.get 5
        local.get 7
        i32.lt_s
        if  ;; label = @3
          block  ;; label = @4
            local.get 8
            i32.const 902
            i32.const 5
            local.get 4
            local.get 5
            call $dynrt_lib_modc_dynArrGet
            call $dynrt_lib_modc_dynSet
            local.get 8
            i32.const 907
            i32.const 4
            i32.const 0
            call $dynrt_lib_modc_dynBool
            call $dynrt_lib_modc_dynSet
            local.get 5
            local.tee 9
            i32.const 1
            i32.add
            local.set 4
            local.get 0
            i32.const 896
            i32.const 6
            local.get 4
            f64.convert_i32_s
            call $dynrt_lib_modc_dynNumber
            call $dynrt_lib_modc_dynSet
          end
        else
          block  ;; label = @4
            local.get 8
            i32.const 902
            i32.const 5
            call $dynrt_lib_modc_dynUndefined
            call $dynrt_lib_modc_dynSet
            local.get 8
            i32.const 907
            i32.const 4
            i32.const 1
            call $dynrt_lib_modc_dynBool
            call $dynrt_lib_modc_dynSet
          end
        end
        local.get 8
        return
      end
    end
    call $dynrt_lib_modc_dynUndefined
    return)
  (func $dynrt_lib_modc__fn131 (param i32) (result i32)
    (local i32) (local i32) (local i32)
    local.get 0
    local.tee 2
    local.set 1
    local.get 1
    i32.const 8
    i32.add
    i32.load
    i32.const 6
    i32.eq
    if (result i32)  ;; label = @1
      local.get 0
      i32.const 911
      i32.const 7
      call $dynrt_lib_modc_dynHas
      i32.const 1
      i32.eq
    else
      i32.const 0
    end
    if  ;; label = @1
      local.get 0
      return
    end
    call $dynrt_lib_modc_dynObject
    local.set 1
    local.get 1
    i32.const 911
    i32.const 7
    local.get 0
    call $dynrt_lib_modc_dynSet
    local.get 1
    i32.const 918
    i32.const 9
    f64.const 0x0p+0 (;=0;)
    call $dynrt_lib_modc_dynNumber
    call $dynrt_lib_modc_dynSet
    local.get 1
    local.tee 3
    return)
  (func $dynrt_lib_modc__fn132 (param i32) (result i32)
    (local i32) (local i32)
    call $dynrt_lib_modc_dynObject
    local.set 1
    local.get 1
    i32.const 911
    i32.const 7
    local.get 0
    call $dynrt_lib_modc_dynSet
    local.get 1
    i32.const 918
    i32.const 9
    f64.const 0x1.0p+0 (;=1;)
    call $dynrt_lib_modc_dynNumber
    call $dynrt_lib_modc_dynSet
    local.get 1
    local.tee 2
    return)
  (func $dynrt_lib_modc__fn133 (param i32) (result i32)
    (local i32)
    local.get 0
    i32.const 918
    i32.const 9
    call $dynrt_lib_modc_dynGet
    local.set 1
    local.get 1
    i32.const -1
    i32.eq
    if  ;; label = @1
      i32.const 0
      return
    end
    local.get 1
    call $dynrt_lib_modc_dynNumberValue
    f64.const 0x1.0p+0 (;=1;)
    f64.eq
    if (result i32)  ;; label = @1
      i32.const 1
    else
      i32.const 0
    end
    return)
  (func $dynrt_lib_modc__fn134 (param i32) (result i32)
    (local i32) (local i32) (local i32)
    local.get 0
    local.tee 2
    local.set 1
    local.get 1
    i32.const 8
    i32.add
    i32.load
    i32.const 6
    i32.eq
    if (result i32)  ;; label = @1
      local.get 0
      i32.const 911
      i32.const 7
      call $dynrt_lib_modc_dynHas
      i32.const 1
      i32.eq
    else
      i32.const 0
    end
    if  ;; label = @1
      block  ;; label = @2
        local.get 0
        i32.const 911
        i32.const 7
        call $dynrt_lib_modc_dynGet
        local.set 1
        local.get 0
        call $dynrt_lib_modc__fn133
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            global.get $dynrt_lib_modc_global22
            i32.const 1
            i32.eq
            if  ;; label = @5
              block  ;; label = @6
                i32.const 1
                global.set $dynrt_lib_modc_global29
                local.get 1
                global.set $dynrt_lib_modc_global30
              end
            end
            call $dynrt_lib_modc_dynUndefined
            return
          end
        end
        local.get 1
        return
      end
    end
    local.get 0
    local.tee 3
    return)
  (func $dynrt_lib_modc__fn135 (param i32 i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 2
    call $dynrt_lib_modc_dynArrLen
    local.set 3
    call $dynrt_lib_modc_dynUndefined
    local.set 4
    local.get 3
    i32.const 0
    i32.gt_s
    if  ;; label = @1
      local.get 2
      i32.const 0
      call $dynrt_lib_modc_dynArrGet
      local.set 4
    end
    local.get 0
    local.get 1
    i32.const 927
    i32.const 7
    call $dynrt_lib_modc__fn169
    i32.const 1
    i32.eq
    if  ;; label = @1
      local.get 4
      call $dynrt_lib_modc__fn131
      return
    end
    local.get 0
    local.get 1
    i32.const 934
    i32.const 6
    call $dynrt_lib_modc__fn169
    i32.const 1
    i32.eq
    if  ;; label = @1
      local.get 4
      call $dynrt_lib_modc__fn132
      return
    end
    local.get 0
    local.get 1
    i32.const 940
    i32.const 3
    call $dynrt_lib_modc__fn169
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 4
        local.set 3
        call $dynrt_lib_modc_dynArray
        local.set 5
        local.get 3
        i32.const 8
        i32.add
        i32.load
        i32.const 5
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 4
            call $dynrt_lib_modc_dynArrLen
            local.set 3
            i32.const 0
            local.set 6
            block  ;; label = @5
              loop  ;; label = @6
                block  ;; label = @7
                  local.get 6
                  local.get 3
                  i32.lt_s
                  i32.eqz
                  br_if 2 (;@5;)
                  block  ;; label = @8
                    local.get 4
                    local.get 6
                    call $dynrt_lib_modc_dynArrGet
                    local.set 7
                    local.get 7
                    local.set 8
                    local.get 8
                    i32.const 8
                    i32.add
                    i32.load
                    i32.const 6
                    i32.eq
                    if (result i32)  ;; label = @9
                      local.get 7
                      i32.const 911
                      i32.const 7
                      call $dynrt_lib_modc_dynHas
                      i32.const 1
                      i32.eq
                    else
                      i32.const 0
                    end
                    if  ;; label = @9
                      block  ;; label = @10
                        local.get 7
                        call $dynrt_lib_modc__fn133
                        i32.const 1
                        i32.eq
                        if  ;; label = @11
                          local.get 7
                          return
                        end
                        local.get 5
                        local.get 7
                        i32.const 911
                        i32.const 7
                        call $dynrt_lib_modc_dynGet
                        call $dynrt_lib_modc_dynPush
                      end
                    else
                      local.get 5
                      local.get 7
                      call $dynrt_lib_modc_dynPush
                    end
                    local.get 6
                    local.tee 9
                    i32.const 1
                    i32.add
                    local.set 6
                  end
                  br 1 (;@6;)
                end
              end
            end
          end
        end
        local.get 5
        call $dynrt_lib_modc__fn131
        return
      end
    end
    call $dynrt_lib_modc_dynUndefined
    return)
  (func $dynrt_lib_modc__fn136 (param i32 i32 i32 i32) (result i32)
    (local i32) (local i32) (local i32)
    local.get 3
    call $dynrt_lib_modc_dynArrLen
    local.set 4
    local.get 0
    i32.const 911
    i32.const 7
    call $dynrt_lib_modc_dynGet
    local.set 5
    local.get 0
    call $dynrt_lib_modc__fn133
    local.set 6
    local.get 1
    local.get 2
    i32.const 943
    i32.const 4
    call $dynrt_lib_modc__fn169
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 6
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 4
            i32.const 1
            i32.gt_s
            if  ;; label = @5
              block  ;; label = @6
                local.get 3
                i32.const 1
                call $dynrt_lib_modc_dynArrGet
                local.set 4
                call $dynrt_lib_modc_dynArray
                local.set 6
                local.get 6
                local.get 5
                call $dynrt_lib_modc_dynPush
                local.get 4
                local.get 6
                call $dynrt_lib_modc_dynApply
                call $dynrt_lib_modc__fn131
                return
              end
            end
            local.get 0
            return
          end
        end
        local.get 4
        i32.const 0
        i32.gt_s
        if  ;; label = @3
          block  ;; label = @4
            local.get 3
            i32.const 0
            call $dynrt_lib_modc_dynArrGet
            local.set 4
            call $dynrt_lib_modc_dynArray
            local.set 6
            local.get 6
            local.get 5
            call $dynrt_lib_modc_dynPush
            local.get 4
            local.get 6
            call $dynrt_lib_modc_dynApply
            call $dynrt_lib_modc__fn131
            return
          end
        end
        local.get 0
        return
      end
    end
    local.get 1
    local.get 2
    i32.const 947
    i32.const 5
    call $dynrt_lib_modc__fn169
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 6
        i32.const 1
        i32.eq
        if (result i32)  ;; label = @3
          local.get 4
          i32.const 0
          i32.gt_s
        else
          i32.const 0
        end
        if  ;; label = @3
          block  ;; label = @4
            local.get 3
            i32.const 0
            call $dynrt_lib_modc_dynArrGet
            local.set 4
            call $dynrt_lib_modc_dynArray
            local.set 6
            local.get 6
            local.get 5
            call $dynrt_lib_modc_dynPush
            local.get 4
            local.get 6
            call $dynrt_lib_modc_dynApply
            call $dynrt_lib_modc__fn131
            return
          end
        end
        local.get 0
        return
      end
    end
    local.get 1
    local.get 2
    i32.const 952
    i32.const 7
    call $dynrt_lib_modc__fn169
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 4
        i32.const 0
        i32.gt_s
        if  ;; label = @3
          block  ;; label = @4
            local.get 3
            i32.const 0
            call $dynrt_lib_modc_dynArrGet
            local.set 4
            call $dynrt_lib_modc_dynArray
            local.set 6
            local.get 4
            local.get 6
            call $dynrt_lib_modc_dynApply
            drop
          end
        end
        local.get 0
        return
      end
    end
    call $dynrt_lib_modc_dynUndefined
    return)
  (func $dynrt_lib_modc__fn137 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.set 2
    local.get 2
    i32.const 8
    i32.add
    i32.load
    i32.const 6
    i32.ne
    if  ;; label = @1
      i32.const 0
      return
    end
    local.get 1
    local.tee 5
    local.set 3
    local.get 3
    i32.const 8
    i32.add
    i32.load
    i32.const 6
    i32.ne
    if  ;; label = @1
      i32.const 0
      return
    end
    local.get 1
    i32.const 959
    i32.const 7
    call $dynrt_lib_modc_dynGet
    local.set 3
    local.get 3
    i32.const -1
    i32.eq
    if  ;; label = @1
      i32.const 0
      return
    end
    local.get 2
    i32.const 8
    i32.add
    i32.const 8
    i32.add
    i32.load
    local.set 2
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 2
          i32.const 0
          i32.ne
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 2
            local.get 3
            i32.eq
            if  ;; label = @5
              i32.const 1
              return
            end
            local.get 2
            local.tee 4
            local.set 2
            local.get 2
            i32.const 8
            i32.add
            i32.load
            i32.const 6
            i32.ne
            if  ;; label = @5
              br 4 (;@1;)
            end
            local.get 2
            i32.const 8
            i32.add
            i32.const 8
            i32.add
            i32.load
            local.set 2
          end
          br 1 (;@2;)
        end
      end
    end
    i32.const 0
    return)
  (func $dynrt_lib_modc__fn138 (param i32 i32 i32)
    (local i32) (local i32) (local f64)
    local.get 0
    local.set 3
    local.get 3
    i32.const 8
    i32.add
    i32.load
    local.set 3
    local.get 1
    call $dynrt_lib_modc_dynTag
    local.set 4
    local.get 3
    i32.const 5
    i32.eq
    if  ;; label = @1
      local.get 4
      i32.const 3
      i32.eq
      if  ;; label = @2
        block  ;; label = @3
          local.get 1
          call $dynrt_lib_modc_dynNumberValue
          local.set 5
          local.get 5
          i32.trunc_f64_s
          local.set 3
          local.get 0
          local.get 3
          local.get 2
          call $dynrt_lib_modc__fn99
        end
      end
    else
      local.get 3
      i32.const 6
      i32.eq
      if  ;; label = @2
        local.get 4
        i32.const 4
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 1
            call $dynrt_lib_modc__fn85
            global.get $dynrt_lib_modc_global2
            local.set 3
            global.get $dynrt_lib_modc_global3
            local.set 4
            local.get 0
            local.get 3
            local.get 4
            local.get 2
            call $dynrt_lib_modc_dynSet
          end
        end
      end
    end)
  (func $dynrt_lib_modc_dynStrictEq (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local f64) (local f64) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.set 2
    local.get 1
    local.set 3
    local.get 2
    i32.const 8
    i32.add
    i32.load
    local.set 4
    local.get 3
    i32.const 8
    i32.add
    i32.load
    local.set 5
    local.get 4
    local.get 5
    i32.ne
    if  ;; label = @1
      i32.const 0
      return
    end
    local.get 4
    i32.eqz
    if  ;; label = @1
      i32.const 1
      return
    end
    local.get 4
    i32.const 1
    i32.eq
    if  ;; label = @1
      i32.const 1
      return
    end
    local.get 4
    i32.const 2
    i32.eq
    if  ;; label = @1
      local.get 2
      i32.const 8
      i32.add
      i32.const 4
      i32.add
      i32.load
      local.get 3
      i32.const 8
      i32.add
      i32.const 4
      i32.add
      i32.load
      i32.eq
      if (result i32)  ;; label = @2
        i32.const 1
      else
        i32.const 0
      end
      return
    end
    local.get 4
    i32.const 3
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 2
        i32.const 8
        i32.add
        i32.const 4
        i32.add
        i32.load
        local.set 2
        local.get 3
        i32.const 8
        i32.add
        i32.const 4
        i32.add
        i32.load
        local.set 3
        local.get 2
        local.tee 8
        local.set 2
        local.get 3
        local.tee 9
        local.set 3
        local.get 2
        i32.const 8
        i32.add
        f64.load
        local.set 6
        local.get 3
        i32.const 8
        i32.add
        f64.load
        local.set 7
        local.get 6
        local.get 7
        f64.eq
        if (result i32)  ;; label = @3
          i32.const 1
        else
          i32.const 0
        end
        return
      end
    end
    local.get 4
    i32.const 4
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 2
        i32.const 8
        i32.add
        i32.const 8
        i32.add
        i32.load
        local.set 4
        local.get 4
        local.get 3
        i32.const 8
        i32.add
        i32.const 8
        i32.add
        i32.load
        i32.ne
        if  ;; label = @3
          i32.const 0
          return
        end
        local.get 2
        i32.const 8
        i32.add
        i32.const 4
        i32.add
        i32.load
        local.set 2
        local.get 3
        i32.const 8
        i32.add
        i32.const 4
        i32.add
        i32.load
        local.set 3
        local.get 2
        local.tee 10
        local.set 2
        local.get 3
        local.tee 11
        local.set 3
        i32.const 0
        local.set 5
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 5
              local.get 4
              i32.lt_s
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                local.get 2
                i32.const 8
                i32.add
                local.get 5
                i32.add
                i32.load8_u
                local.get 3
                i32.const 8
                i32.add
                local.get 5
                i32.add
                i32.load8_u
                i32.ne
                if  ;; label = @7
                  i32.const 0
                  return
                end
                local.get 5
                i32.const 1
                i32.add
                local.set 5
              end
              br 1 (;@4;)
            end
          end
        end
        i32.const 1
        return
      end
    end
    local.get 0
    local.get 1
    i32.eq
    if (result i32)  ;; label = @1
      i32.const 1
    else
      i32.const 0
    end
    return)
  (func $dynrt_lib_modc_dynAdd (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local f64) (local f64) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.tee 14
    local.set 2
    local.get 1
    local.tee 15
    local.set 3
    local.get 2
    i32.const 8
    i32.add
    i32.load
    i32.const 4
    i32.eq
    if (result i32)  ;; label = @1
      i32.const 1
    else
      local.get 3
      i32.const 8
      i32.add
      i32.load
      i32.const 4
      i32.eq
    end
    if  ;; label = @1
      block  ;; label = @2
        local.get 0
        call $dynrt_lib_modc__fn86
        global.get $dynrt_lib_modc_global2
        local.tee 8
        local.set 2
        global.get $dynrt_lib_modc_global3
        local.tee 9
        local.set 3
        local.get 1
        call $dynrt_lib_modc__fn86
        global.get $dynrt_lib_modc_global2
        local.tee 10
        local.set 4
        global.get $dynrt_lib_modc_global3
        local.tee 11
        local.set 5
        local.get 2
        local.tee 12
        local.set 2
        local.get 3
        local.tee 13
        local.set 3
        local.get 2
        local.get 3
        local.get 4
        local.get 5
        call $dynrt_lib_modc__fn5
        local.set 3
        nop
        local.set 2
        local.get 2
        local.get 3
        call $dynrt_lib_modc_dynString
        return
      end
    end
    local.get 0
    call $dynrt_lib_modc_dynToNumber
    local.set 6
    local.get 1
    call $dynrt_lib_modc_dynToNumber
    local.set 7
    local.get 6
    local.get 7
    f64.add
    call $dynrt_lib_modc_dynNumber
    return)
  (func $dynrt_lib_modc_dynNeg (param i32) (result i32)
    (local f64)
    local.get 0
    call $dynrt_lib_modc_dynToNumber
    local.set 1
    f64.const 0x0p+0 (;=0;)
    local.get 1
    f64.sub
    call $dynrt_lib_modc_dynNumber
    return)
  (func $dynrt_lib_modc_dynNot (param i32) (result i32)
    local.get 0
    call $dynrt_lib_modc_dynToBool
    i32.eqz
    if (result i32)  ;; label = @1
      i32.const 1
    else
      i32.const 0
    end
    call $dynrt_lib_modc_dynBool
    return)
  (func $dynrt_lib_modc_dynSub (param i32 i32) (result i32)
    (local f64) (local f64)
    local.get 0
    call $dynrt_lib_modc_dynToNumber
    local.set 2
    local.get 1
    call $dynrt_lib_modc_dynToNumber
    local.set 3
    local.get 2
    local.get 3
    f64.sub
    call $dynrt_lib_modc_dynNumber
    return)
  (func $dynrt_lib_modc_dynMul (param i32 i32) (result i32)
    (local f64) (local f64)
    local.get 0
    call $dynrt_lib_modc_dynToNumber
    local.set 2
    local.get 1
    call $dynrt_lib_modc_dynToNumber
    local.set 3
    local.get 2
    local.get 3
    f64.mul
    call $dynrt_lib_modc_dynNumber
    return)
  (func $dynrt_lib_modc_dynDiv (param i32 i32) (result i32)
    (local f64) (local f64)
    local.get 0
    call $dynrt_lib_modc_dynToNumber
    local.set 2
    local.get 1
    call $dynrt_lib_modc_dynToNumber
    local.set 3
    local.get 2
    local.get 3
    f64.div
    call $dynrt_lib_modc_dynNumber
    return)
  (func $dynrt_lib_modc_dynMod (param i32 i32) (result i32)
    (local f64) (local f64) (local f64) (local i32) (local f64) (local f64)
    local.get 0
    call $dynrt_lib_modc_dynToNumber
    local.set 2
    local.get 1
    call $dynrt_lib_modc_dynToNumber
    local.set 3
    local.get 2
    local.tee 6
    local.get 3
    local.tee 7
    f64.div
    local.set 4
    local.get 4
    f64.const 0x0p+0 (;=0;)
    f64.lt
    if (result f64)  ;; label = @1
      local.get 4
      f64.ceil
    else
      local.get 4
      f64.floor
    end
    local.set 4
    local.get 2
    local.get 3
    local.get 4
    f64.mul
    f64.sub
    call $dynrt_lib_modc_dynNumber
    return)
  (func $dynrt_lib_modc_dynLt (param i32 i32) (result i32)
    (local f64) (local f64)
    local.get 0
    call $dynrt_lib_modc_dynToNumber
    local.set 2
    local.get 1
    call $dynrt_lib_modc_dynToNumber
    local.set 3
    local.get 2
    local.get 3
    f64.lt
    if (result i32)  ;; label = @1
      i32.const 1
    else
      i32.const 0
    end
    call $dynrt_lib_modc_dynBool
    return)
  (func $dynrt_lib_modc_dynGt (param i32 i32) (result i32)
    (local f64) (local f64)
    local.get 0
    call $dynrt_lib_modc_dynToNumber
    local.set 2
    local.get 1
    call $dynrt_lib_modc_dynToNumber
    local.set 3
    local.get 2
    local.get 3
    f64.gt
    if (result i32)  ;; label = @1
      i32.const 1
    else
      i32.const 0
    end
    call $dynrt_lib_modc_dynBool
    return)
  (func $dynrt_lib_modc_dynLe (param i32 i32) (result i32)
    (local f64) (local f64)
    local.get 0
    call $dynrt_lib_modc_dynToNumber
    local.set 2
    local.get 1
    call $dynrt_lib_modc_dynToNumber
    local.set 3
    local.get 2
    local.get 3
    f64.le
    if (result i32)  ;; label = @1
      i32.const 1
    else
      i32.const 0
    end
    call $dynrt_lib_modc_dynBool
    return)
  (func $dynrt_lib_modc_dynGe (param i32 i32) (result i32)
    (local f64) (local f64)
    local.get 0
    call $dynrt_lib_modc_dynToNumber
    local.set 2
    local.get 1
    call $dynrt_lib_modc_dynToNumber
    local.set 3
    local.get 2
    local.get 3
    f64.ge
    if (result i32)  ;; label = @1
      i32.const 1
    else
      i32.const 0
    end
    call $dynrt_lib_modc_dynBool
    return)
  (func $dynrt_lib_modc_dynBuiltin (param i32) (result i32)
    (local i32) (local i32)
    call $dynrt_lib_modc__fn53
    local.set 1
    local.get 1
    i32.const 8
    i32.add
    i32.const 7
    i32.store
    local.get 1
    i32.const 8
    i32.add
    i32.const 4
    i32.add
    local.get 0
    i32.store
    local.get 1
    local.tee 2
    return)
  (func $dynrt_lib_modc__fn152 (param i32 i32 i32) (result i32)
    (local i32) (local i32)
    call $dynrt_lib_modc__fn54
    local.set 3
    local.get 3
    i32.const 8
    i32.add
    i32.const 7
    i32.store
    local.get 3
    i32.const 8
    i32.add
    i32.const 4
    i32.add
    i32.const -1
    i32.store
    local.get 3
    i32.const 8
    i32.add
    i32.const 8
    i32.add
    local.get 1
    i32.store
    local.get 3
    i32.const 8
    i32.add
    i32.const 12
    i32.add
    local.get 0
    i32.store
    local.get 3
    i32.const 8
    i32.add
    i32.const 16
    i32.add
    local.get 2
    i32.store
    local.get 3
    local.tee 4
    return)
  (func $dynrt_lib_modc_dynMakeFunc (param i32 i32 i32 i32) (result i32)
    (local i32)
    local.get 1
    local.get 2
    call $dynrt_lib_modc_dynString
    local.set 4
    local.get 0
    local.get 4
    local.get 3
    call $dynrt_lib_modc__fn152
    return)
  (func $dynrt_lib_modc_dynMakeHostFn (param i32) (result i32)
    (local i32) (local i32)
    call $dynrt_lib_modc__fn54
    local.set 1
    local.get 1
    i32.const 8
    i32.add
    i32.const 7
    i32.store
    local.get 1
    i32.const 8
    i32.add
    i32.const 4
    i32.add
    i32.const -2
    i32.store
    local.get 1
    i32.const 8
    i32.add
    i32.const 8
    i32.add
    local.get 0
    i32.store
    local.get 1
    i32.const 8
    i32.add
    i32.const 12
    i32.add
    i32.const 0
    i32.store
    local.get 1
    i32.const 8
    i32.add
    i32.const 16
    i32.add
    i32.const 0
    i32.store
    local.get 1
    local.tee 2
    return)
  (func $dynrt_lib_modc_dynMakeFn (param i32 i32 i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    call $dynrt_lib_modc_dynArray
    local.set 4
    local.get 1
    local.set 5
    i32.const 0
    local.tee 11
    local.set 6
    local.get 11
    local.set 7
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 7
          local.get 5
          i32.le_s
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 7
            local.get 5
            i32.eq
            if (result i32)  ;; label = @5
              i32.const 1
            else
              local.get 0
              local.get 1
              local.get 7
              call $dynrt_lib_modc__fn9
              i32.const 44
              i32.eq
            end
            if  ;; label = @5
              block  ;; label = @6
                local.get 6
                local.set 6
                local.get 7
                local.tee 9
                local.set 8
                block  ;; label = @7
                  loop  ;; label = @8
                    block  ;; label = @9
                      local.get 6
                      local.get 8
                      i32.lt_s
                      if (result i32)  ;; label = @10
                        local.get 0
                        local.get 1
                        local.get 6
                        call $dynrt_lib_modc__fn9
                        i32.const 32
                        i32.eq
                      else
                        i32.const 0
                      end
                      i32.eqz
                      br_if 2 (;@7;)
                      local.get 6
                      i32.const 1
                      i32.add
                      local.set 6
                      br 1 (;@8;)
                    end
                  end
                end
                block  ;; label = @7
                  loop  ;; label = @8
                    block  ;; label = @9
                      local.get 8
                      local.get 6
                      i32.gt_s
                      if (result i32)  ;; label = @10
                        local.get 0
                        local.get 1
                        local.get 8
                        i32.const 1
                        i32.sub
                        call $dynrt_lib_modc__fn9
                        i32.const 32
                        i32.eq
                      else
                        i32.const 0
                      end
                      i32.eqz
                      br_if 2 (;@7;)
                      local.get 8
                      i32.const 1
                      i32.sub
                      local.set 8
                      br 1 (;@8;)
                    end
                  end
                end
                local.get 8
                local.get 6
                i32.gt_s
                if  ;; label = @7
                  block  ;; label = @8
                    local.get 0
                    local.get 1
                    local.get 6
                    local.get 8
                    call $dynrt_lib_modc__fn6
                    local.set 8
                    nop
                    local.set 6
                    local.get 4
                    local.get 6
                    local.get 8
                    call $dynrt_lib_modc_dynString
                    call $dynrt_lib_modc_dynPush
                  end
                end
                local.get 7
                local.tee 10
                i32.const 1
                i32.add
                local.set 6
              end
            end
            local.get 7
            i32.const 1
            i32.add
            local.set 7
          end
          br 1 (;@2;)
        end
      end
    end
    call $dynrt_lib_modc_dynObject
    local.set 5
    local.get 4
    local.get 2
    local.get 3
    local.get 5
    call $dynrt_lib_modc_dynMakeFunc
    return)
  (func $dynrt_lib_modc__fn156 (param i32 i32 i32) (result i32)
    (local i32) (local i32) (local i32)
    local.get 0
    local.set 3
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 3
          i32.const -1
          i32.ne
          if (result i32)  ;; label = @4
            local.get 3
            i32.const 0
            i32.ne
          else
            i32.const 0
          end
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 3
            local.get 1
            local.get 2
            call $dynrt_lib_modc_dynGet
            local.set 4
            local.get 4
            i32.const -1
            i32.ne
            if  ;; label = @5
              local.get 4
              return
            end
            local.get 3
            local.tee 5
            local.set 3
            local.get 3
            i32.const 8
            i32.add
            i32.const 8
            i32.add
            i32.load
            local.set 3
          end
          br 1 (;@2;)
        end
      end
    end
    i32.const -1
    return)
  (func $dynrt_lib_modc__fn157 (param i32) (result i32)
    (local i32) (local i32) (local i32) (local i32)
    call $dynrt_lib_modc_dynObject
    local.set 1
    local.get 1
    local.tee 3
    local.set 2
    local.get 2
    i32.const 8
    i32.add
    i32.const 8
    i32.add
    local.get 0
    i32.store
    local.get 1
    local.tee 4
    return)
  (func $dynrt_lib_modc__fn158 (param i32 i32 i32 i32)
    (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.tee 8
    local.set 4
    local.get 8
    local.set 5
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 4
          i32.const -1
          i32.ne
          if (result i32)  ;; label = @4
            local.get 4
            i32.const 0
            i32.ne
          else
            i32.const 0
          end
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 4
            local.get 1
            local.get 2
            call $dynrt_lib_modc_dynGet
            i32.const -1
            i32.ne
            if  ;; label = @5
              block  ;; label = @6
                local.get 4
                local.get 1
                local.get 2
                local.get 3
                call $dynrt_lib_modc_dynSet
                return
              end
            end
            local.get 4
            local.tee 6
            local.set 5
            local.get 4
            local.tee 7
            local.set 4
            local.get 4
            i32.const 8
            i32.add
            i32.const 8
            i32.add
            i32.load
            local.set 4
          end
          br 1 (;@2;)
        end
      end
    end
    local.get 5
    i32.const -1
    i32.ne
    if (result i32)  ;; label = @1
      local.get 5
      i32.const 0
      i32.ne
    else
      i32.const 0
    end
    if  ;; label = @1
      local.get 5
      local.get 1
      local.get 2
      local.get 3
      call $dynrt_lib_modc_dynSet
    end)
  (func $dynrt_lib_modc__fn159 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 1
    call $dynrt_lib_modc__fn157
    local.set 2
    local.get 0
    local.set 3
    local.get 2
    local.tee 16
    local.set 4
    local.get 3
    i32.const 8
    i32.add
    i32.const 4
    i32.add
    i32.load
    call $dynrt_lib_modc__fn36
    local.set 5
    i32.const 0
    local.set 6
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 6
          local.get 5
          i32.lt_s
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 3
            i32.const 8
            i32.add
            i32.const 12
            i32.add
            i32.load
            local.get 6
            i32.const 2
            i32.mul
            call $dynrt_lib_modc__fn37
            local.set 7
            local.get 3
            i32.const 8
            i32.add
            i32.const 12
            i32.add
            i32.load
            local.get 6
            i32.const 2
            i32.mul
            i32.const 1
            i32.add
            call $dynrt_lib_modc__fn37
            local.set 8
            local.get 3
            i32.const 8
            i32.add
            i32.const 4
            i32.add
            i32.load
            local.get 6
            call $dynrt_lib_modc__fn37
            local.set 9
            local.get 7
            local.tee 13
            local.set 7
            i32.const 8
            local.get 8
            i32.add
            call $dynrt_lib_modc__fn45
            local.set 10
            i32.const 0
            local.set 11
            block  ;; label = @5
              loop  ;; label = @6
                block  ;; label = @7
                  local.get 11
                  local.get 8
                  i32.lt_s
                  i32.eqz
                  br_if 2 (;@5;)
                  block  ;; label = @8
                    local.get 10
                    i32.const 8
                    i32.add
                    local.get 11
                    i32.add
                    local.get 7
                    i32.const 8
                    i32.add
                    local.get 11
                    i32.add
                    i32.load8_u
                    i32.store8
                    local.get 11
                    local.tee 12
                    i32.const 1
                    i32.add
                    local.set 11
                  end
                  br 1 (;@6;)
                end
              end
            end
            local.get 4
            i32.const 8
            i32.add
            i32.const 12
            i32.add
            i32.load
            local.set 7
            local.get 7
            local.get 10
            call $dynrt_lib_modc__fn39
            local.set 7
            local.get 7
            local.get 8
            call $dynrt_lib_modc__fn39
            local.set 7
            local.get 4
            i32.const 8
            i32.add
            i32.const 12
            i32.add
            local.get 7
            i32.store
            local.get 4
            i32.const 8
            i32.add
            i32.const 4
            i32.add
            local.get 4
            i32.const 8
            i32.add
            i32.const 4
            i32.add
            i32.load
            local.get 9
            call $dynrt_lib_modc__fn39
            i32.store
            local.get 6
            local.tee 14
            i32.const 1
            local.tee 15
            i32.add
            local.set 6
          end
          br 1 (;@2;)
        end
      end
    end
    local.get 2
    local.tee 17
    return)
  (func $dynrt_lib_modc_dynApply (param i32 i32) (result i32)
    local.get 0
    local.get 1
    i32.const -1
    call $dynrt_lib_modc__fn161
    return)
  (func $dynrt_lib_modc__fn161 (param i32 i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local f64) (local f64) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.set 3
    local.get 3
    i32.const 8
    i32.add
    i32.load
    i32.const 7
    i32.ne
    if  ;; label = @1
      call $dynrt_lib_modc_dynUndefined
      return
    end
    local.get 3
    i32.const 8
    i32.add
    i32.const 4
    i32.add
    i32.load
    local.set 4
    local.get 4
    i32.const -2
    i32.eq
    if  ;; label = @1
      local.get 3
      i32.const 8
      i32.add
      i32.const 8
      i32.add
      i32.load
      local.get 1
      call $dynrt_lib_modc___host_call
      return
    end
    local.get 1
    call $dynrt_lib_modc_dynArrLen
    local.set 5
    local.get 4
    i32.const -1
    i32.eq
    if (result i32)  ;; label = @1
      i32.const 1
    else
      local.get 4
      i32.const -3
      i32.eq
    end
    if (result i32)  ;; label = @1
      i32.const 1
    else
      local.get 4
      i32.const -4
      i32.eq
    end
    if  ;; label = @1
      block  ;; label = @2
        local.get 3
        i32.const 8
        i32.add
        i32.const 8
        i32.add
        i32.load
        local.set 6
        local.get 3
        i32.const 8
        i32.add
        i32.const 12
        i32.add
        i32.load
        local.set 7
        local.get 3
        i32.const 8
        i32.add
        i32.const 16
        i32.add
        i32.load
        local.set 3
        call $dynrt_lib_modc_dynObject
        local.set 8
        local.get 8
        local.tee 19
        local.set 9
        local.get 9
        i32.const 8
        i32.add
        i32.const 8
        i32.add
        local.get 3
        i32.store
        local.get 2
        i32.const -1
        i32.ne
        if  ;; label = @3
          local.get 8
          i32.const 966
          i32.const 4
          local.get 2
          call $dynrt_lib_modc_dynSet
        end
        local.get 7
        call $dynrt_lib_modc_dynArrLen
        local.set 3
        i32.const 0
        local.set 9
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 9
              local.get 3
              i32.lt_s
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                local.get 7
                local.get 9
                call $dynrt_lib_modc_dynArrGet
                local.set 10
                local.get 10
                call $dynrt_lib_modc__fn85
                global.get $dynrt_lib_modc_global2
                local.set 10
                global.get $dynrt_lib_modc_global3
                local.set 11
                local.get 9
                local.get 5
                i32.lt_s
                if (result i32)  ;; label = @7
                  local.get 1
                  local.get 9
                  call $dynrt_lib_modc_dynArrGet
                else
                  call $dynrt_lib_modc_dynUndefined
                end
                local.set 12
                local.get 8
                local.get 10
                local.get 11
                local.get 12
                call $dynrt_lib_modc_dynSet
                local.get 9
                local.tee 17
                i32.const 1
                i32.add
                local.set 9
              end
              br 1 (;@4;)
            end
          end
        end
        local.get 6
        call $dynrt_lib_modc__fn85
        global.get $dynrt_lib_modc_global2
        local.set 3
        global.get $dynrt_lib_modc_global3
        local.set 5
        global.get $dynrt_lib_modc_global31
        local.tee 20
        local.set 6
        local.get 4
        i32.const -3
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            call $dynrt_lib_modc_dynArray
            global.set $dynrt_lib_modc_global31
            global.get $dynrt_lib_modc_global31
            call $dynrt_lib_modc__fn61
          end
        end
        global.get $dynrt_lib_modc_global31
        local.tee 21
        local.set 7
        global.get $dynrt_lib_modc_global20
        local.set 9
        global.get $dynrt_lib_modc_global21
        local.set 10
        global.get $dynrt_lib_modc_global22
        local.set 11
        global.get $dynrt_lib_modc_global24
        local.set 12
        global.get $dynrt_lib_modc_global25
        local.set 13
        global.get $dynrt_lib_modc_global26
        local.set 14
        local.get 3
        local.get 5
        local.get 8
        call $dynrt_lib_modc_dynRun
        local.set 3
        local.get 9
        local.tee 22
        global.set $dynrt_lib_modc_global20
        local.get 10
        global.set $dynrt_lib_modc_global21
        local.get 11
        global.set $dynrt_lib_modc_global22
        local.get 12
        global.set $dynrt_lib_modc_global24
        local.get 13
        global.set $dynrt_lib_modc_global25
        local.get 14
        global.set $dynrt_lib_modc_global26
        local.get 4
        i32.const -3
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            call $dynrt_lib_modc__fn62
            local.get 6
            global.set $dynrt_lib_modc_global31
            call $dynrt_lib_modc_dynObject
            local.set 3
            local.get 3
            i32.const 890
            i32.const 6
            local.get 7
            call $dynrt_lib_modc_dynSet
            local.get 3
            i32.const 896
            i32.const 6
            f64.const 0x0p+0 (;=0;)
            call $dynrt_lib_modc_dynNumber
            call $dynrt_lib_modc_dynSet
            local.get 3
            local.tee 18
            return
          end
        end
        local.get 4
        i32.const -4
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            global.get $dynrt_lib_modc_global29
            i32.const 1
            i32.eq
            if  ;; label = @5
              block  ;; label = @6
                global.get $dynrt_lib_modc_global30
                local.set 3
                i32.const 0
                global.set $dynrt_lib_modc_global29
                local.get 3
                call $dynrt_lib_modc__fn132
                return
              end
            end
            local.get 3
            call $dynrt_lib_modc__fn131
            return
          end
        end
        local.get 3
        local.tee 23
        return
      end
    end
    local.get 4
    i32.const 8
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_lib_modc_global23
        local.tee 24
        i32.const 1
        i32.add
        global.set $dynrt_lib_modc_global23
        global.get $dynrt_lib_modc_global23
        local.tee 25
        local.set 3
        local.get 3
        f64.convert_i32_s
        call $dynrt_lib_modc_dynNumber
        return
      end
    end
    local.get 5
    i32.const 0
    i32.gt_s
    if (result i32)  ;; label = @1
      local.get 1
      i32.const 0
      call $dynrt_lib_modc_dynArrGet
    else
      call $dynrt_lib_modc_dynUndefined
    end
    local.set 3
    local.get 4
    i32.const 7
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 3
        call $dynrt_lib_modc_dynTag
        local.set 4
        local.get 4
        i32.const 4
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 3
            local.tee 26
            local.set 3
            local.get 3
            i32.const 8
            i32.add
            i32.const 8
            i32.add
            i32.load
            local.set 3
            local.get 3
            f64.convert_i32_s
            call $dynrt_lib_modc_dynNumber
            return
          end
        end
        local.get 4
        i32.const 5
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 3
            call $dynrt_lib_modc_dynArrLen
            local.set 3
            local.get 3
            f64.convert_i32_s
            call $dynrt_lib_modc_dynNumber
            return
          end
        end
        f64.const 0x0p+0 (;=0;)
        call $dynrt_lib_modc_dynNumber
        return
      end
    end
    local.get 3
    call $dynrt_lib_modc_dynToNumber
    local.set 15
    local.get 4
    i32.eqz
    if  ;; label = @1
      local.get 15
      f64.abs
      call $dynrt_lib_modc_dynNumber
      return
    end
    local.get 4
    i32.const 1
    i32.eq
    if  ;; label = @1
      local.get 15
      f64.sqrt
      call $dynrt_lib_modc_dynNumber
      return
    end
    local.get 4
    i32.const 2
    i32.eq
    if  ;; label = @1
      local.get 15
      f64.floor
      call $dynrt_lib_modc_dynNumber
      return
    end
    local.get 4
    i32.const 3
    i32.eq
    if  ;; label = @1
      local.get 15
      f64.ceil
      call $dynrt_lib_modc_dynNumber
      return
    end
    local.get 4
    i32.const 4
    i32.eq
    if  ;; label = @1
      local.get 15
      f64.const 0x1.0p-1 (;=0.5;)
      f64.add
      f64.floor
      call $dynrt_lib_modc_dynNumber
      return
    end
    local.get 5
    i32.const 1
    i32.gt_s
    if (result i32)  ;; label = @1
      local.get 1
      i32.const 1
      call $dynrt_lib_modc_dynArrGet
    else
      call $dynrt_lib_modc_dynUndefined
    end
    local.set 3
    local.get 3
    call $dynrt_lib_modc_dynToNumber
    local.set 16
    local.get 4
    i32.const 5
    i32.eq
    if  ;; label = @1
      local.get 15
      local.get 16
      f64.lt
      if (result f64)  ;; label = @2
        local.get 15
      else
        local.get 16
      end
      call $dynrt_lib_modc_dynNumber
      return
    end
    local.get 4
    i32.const 6
    i32.eq
    if  ;; label = @1
      local.get 15
      local.get 16
      f64.gt
      if (result f64)  ;; label = @2
        local.get 15
      else
        local.get 16
      end
      call $dynrt_lib_modc_dynNumber
      return
    end
    call $dynrt_lib_modc_dynUndefined
    return)
  (func $dynrt_lib_modc_dynCall0 (param i32) (result i32)
    (local i32)
    call $dynrt_lib_modc_dynArray
    local.set 1
    local.get 0
    local.get 1
    call $dynrt_lib_modc_dynApply
    return)
  (func $dynrt_lib_modc_dynCall1 (param i32 i32) (result i32)
    (local i32)
    call $dynrt_lib_modc_dynArray
    local.set 2
    local.get 2
    local.get 1
    call $dynrt_lib_modc_dynPush
    local.get 0
    local.get 2
    call $dynrt_lib_modc_dynApply
    return)
  (func $dynrt_lib_modc_dynCall2 (param i32 i32 i32) (result i32)
    (local i32)
    call $dynrt_lib_modc_dynArray
    local.set 3
    local.get 3
    local.get 1
    call $dynrt_lib_modc_dynPush
    local.get 3
    local.get 2
    call $dynrt_lib_modc_dynPush
    local.get 0
    local.get 3
    call $dynrt_lib_modc_dynApply
    return)
  (func $dynrt_lib_modc_dynCall3 (param i32 i32 i32 i32) (result i32)
    (local i32)
    call $dynrt_lib_modc_dynArray
    local.set 4
    local.get 4
    local.get 1
    call $dynrt_lib_modc_dynPush
    local.get 4
    local.get 2
    call $dynrt_lib_modc_dynPush
    local.get 4
    local.get 3
    call $dynrt_lib_modc_dynPush
    local.get 0
    local.get 4
    call $dynrt_lib_modc_dynApply
    return)
  (func $dynrt_lib_modc_dynStdEnv (result i32)
    (local i32) (local i32)
    call $dynrt_lib_modc_dynObject
    local.set 0
    local.get 0
    i32.const 801
    i32.const 3
    i32.const 0
    call $dynrt_lib_modc_dynBuiltin
    call $dynrt_lib_modc_dynSet
    local.get 0
    i32.const 804
    i32.const 4
    i32.const 1
    call $dynrt_lib_modc_dynBuiltin
    call $dynrt_lib_modc_dynSet
    local.get 0
    i32.const 787
    i32.const 5
    i32.const 2
    call $dynrt_lib_modc_dynBuiltin
    call $dynrt_lib_modc_dynSet
    local.get 0
    i32.const 792
    i32.const 4
    i32.const 3
    call $dynrt_lib_modc_dynBuiltin
    call $dynrt_lib_modc_dynSet
    local.get 0
    i32.const 796
    i32.const 5
    i32.const 4
    call $dynrt_lib_modc_dynBuiltin
    call $dynrt_lib_modc_dynSet
    local.get 0
    i32.const 820
    i32.const 3
    i32.const 5
    call $dynrt_lib_modc_dynBuiltin
    call $dynrt_lib_modc_dynSet
    local.get 0
    i32.const 817
    i32.const 3
    i32.const 6
    call $dynrt_lib_modc_dynBuiltin
    call $dynrt_lib_modc_dynSet
    local.get 0
    i32.const 970
    i32.const 3
    i32.const 7
    call $dynrt_lib_modc_dynBuiltin
    call $dynrt_lib_modc_dynSet
    local.get 0
    i32.const 973
    i32.const 3
    i32.const 8
    call $dynrt_lib_modc_dynBuiltin
    call $dynrt_lib_modc_dynSet
    local.get 0
    local.tee 1
    return)
  (func $dynrt_lib_modc_dynSideEffectCount (result i32)
    global.get $dynrt_lib_modc_global23
    return)
  (func $dynrt_lib_modc_dynResetSideEffects
    i32.const 0
    global.set $dynrt_lib_modc_global23)
  (func $dynrt_lib_modc__fn169 (param i32 i32 i32 i32) (result i32)
    (local i32)
    local.get 1
    local.get 3
    i32.ne
    if  ;; label = @1
      i32.const 0
      return
    end
    i32.const 0
    local.set 4
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 4
          local.get 1
          i32.lt_s
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 0
            local.get 1
            local.get 4
            call $dynrt_lib_modc__fn9
            local.get 2
            local.get 3
            local.get 4
            call $dynrt_lib_modc__fn9
            i32.ne
            if  ;; label = @5
              i32.const 0
              return
            end
            local.get 4
            i32.const 1
            i32.add
            local.set 4
          end
          br 1 (;@2;)
        end
      end
    end
    i32.const 1
    return)
  (func $dynrt_lib_modc_dynMember (param i32 i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.set 3
    local.get 3
    i32.const 8
    i32.add
    i32.load
    local.set 4
    local.get 4
    i32.const 6
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 0
        local.tee 10
        local.set 3
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 3
              i32.const 0
              i32.ne
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                local.get 3
                local.tee 8
                local.set 4
                local.get 4
                i32.const 8
                i32.add
                i32.load
                i32.const 6
                i32.ne
                if  ;; label = @7
                  br 4 (;@3;)
                end
                local.get 3
                local.get 1
                local.get 2
                call $dynrt_lib_modc_dynGet
                local.set 3
                local.get 3
                i32.const -1
                i32.ne
                if  ;; label = @7
                  local.get 3
                  return
                end
                local.get 4
                i32.const 8
                i32.add
                i32.const 8
                i32.add
                i32.load
                local.set 3
              end
              br 1 (;@4;)
            end
          end
        end
        local.get 1
        local.get 2
        i32.const 976
        i32.const 4
        call $dynrt_lib_modc__fn169
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 0
            i32.const 842
            i32.const 6
            call $dynrt_lib_modc_dynGet
            local.set 3
            local.get 3
            i32.const -1
            i32.ne
            if  ;; label = @5
              block  ;; label = @6
                local.get 3
                call $dynrt_lib_modc_dynArrLen
                local.set 3
                local.get 3
                f64.convert_i32_s
                call $dynrt_lib_modc_dynNumber
                return
              end
            end
            local.get 0
            i32.const 854
            i32.const 6
            call $dynrt_lib_modc_dynGet
            local.set 3
            local.get 3
            i32.const -1
            i32.ne
            if  ;; label = @5
              block  ;; label = @6
                local.get 3
                call $dynrt_lib_modc_dynArrLen
                local.set 3
                local.get 3
                f64.convert_i32_s
                call $dynrt_lib_modc_dynNumber
                return
              end
            end
          end
        end
        i32.const 980
        local.set 3
        i32.const 6
        local.set 4
        local.get 3
        local.get 4
        local.get 1
        local.get 2
        call $dynrt_lib_modc__fn5
        local.set 4
        nop
        local.set 3
        local.get 0
        local.tee 11
        local.set 5
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 5
              i32.const 0
              i32.ne
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                local.get 5
                local.tee 9
                local.set 6
                local.get 6
                i32.const 8
                i32.add
                i32.load
                i32.const 6
                i32.ne
                if  ;; label = @7
                  br 4 (;@3;)
                end
                local.get 5
                local.get 3
                local.get 4
                call $dynrt_lib_modc_dynGet
                local.set 5
                local.get 5
                i32.const -1
                i32.ne
                if  ;; label = @7
                  block  ;; label = @8
                    local.get 5
                    local.set 7
                    local.get 7
                    i32.const 8
                    i32.add
                    i32.load
                    i32.const 7
                    i32.eq
                    if  ;; label = @9
                      block  ;; label = @10
                        call $dynrt_lib_modc_dynArray
                        local.set 3
                        local.get 5
                        local.get 3
                        local.get 0
                        call $dynrt_lib_modc__fn161
                        return
                      end
                    end
                  end
                end
                local.get 6
                i32.const 8
                i32.add
                i32.const 8
                i32.add
                i32.load
                local.set 5
              end
              br 1 (;@4;)
            end
          end
        end
        call $dynrt_lib_modc_dynUndefined
        return
      end
    end
    local.get 4
    i32.const 5
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 1
        local.get 2
        i32.const 986
        i32.const 6
        call $dynrt_lib_modc__fn169
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 0
            call $dynrt_lib_modc_dynArrLen
            local.set 3
            local.get 3
            f64.convert_i32_s
            call $dynrt_lib_modc_dynNumber
            return
          end
        end
        call $dynrt_lib_modc_dynUndefined
        return
      end
    end
    local.get 4
    i32.const 4
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 1
        local.get 2
        i32.const 986
        i32.const 6
        call $dynrt_lib_modc__fn169
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 3
            i32.const 8
            i32.add
            i32.const 8
            i32.add
            i32.load
            local.set 3
            local.get 3
            f64.convert_i32_s
            call $dynrt_lib_modc_dynNumber
            return
          end
        end
        call $dynrt_lib_modc_dynUndefined
        return
      end
    end
    call $dynrt_lib_modc_dynUndefined
    return)
  (func $dynrt_lib_modc__fn171 (param i32 i32 i32 i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.tee 10
    local.set 4
    local.get 4
    i32.const 8
    i32.add
    i32.load
    i32.const 6
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        i32.const 992
        local.set 4
        i32.const 6
        local.set 5
        local.get 4
        local.get 5
        local.get 1
        local.get 2
        call $dynrt_lib_modc__fn5
        local.set 5
        nop
        local.set 4
        local.get 0
        local.set 6
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 6
              i32.const 0
              i32.ne
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                local.get 6
                local.tee 9
                local.set 7
                local.get 7
                i32.const 8
                i32.add
                i32.load
                i32.const 6
                i32.ne
                if  ;; label = @7
                  br 4 (;@3;)
                end
                local.get 6
                local.get 4
                local.get 5
                call $dynrt_lib_modc_dynGet
                local.set 6
                local.get 6
                i32.const -1
                i32.ne
                if  ;; label = @7
                  block  ;; label = @8
                    local.get 6
                    local.set 8
                    local.get 8
                    i32.const 8
                    i32.add
                    i32.load
                    i32.const 7
                    i32.eq
                    if  ;; label = @9
                      block  ;; label = @10
                        call $dynrt_lib_modc_dynArray
                        local.set 4
                        local.get 4
                        local.get 3
                        call $dynrt_lib_modc_dynPush
                        local.get 6
                        local.get 4
                        local.get 0
                        call $dynrt_lib_modc__fn161
                        drop
                        return
                      end
                    end
                  end
                end
                local.get 7
                i32.const 8
                i32.add
                i32.const 8
                i32.add
                i32.load
                local.set 6
              end
              br 1 (;@4;)
            end
          end
        end
      end
    end
    local.get 0
    local.get 1
    local.get 2
    local.get 3
    call $dynrt_lib_modc_dynSet)
  (func $dynrt_lib_modc_dynIndexValue (param i32 i32) (result i32)
    (local i32) (local i32) (local f64)
    local.get 0
    local.set 2
    local.get 2
    i32.const 8
    i32.add
    i32.load
    local.set 2
    local.get 1
    call $dynrt_lib_modc_dynTag
    local.set 3
    local.get 2
    i32.const 5
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 3
        i32.const 3
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 1
            call $dynrt_lib_modc_dynNumberValue
            local.set 4
            local.get 4
            i32.trunc_f64_s
            local.set 2
            local.get 0
            call $dynrt_lib_modc_dynArrLen
            local.set 3
            local.get 2
            i32.const 0
            i32.lt_s
            if (result i32)  ;; label = @5
              i32.const 1
            else
              local.get 2
              local.get 3
              i32.ge_s
            end
            if  ;; label = @5
              call $dynrt_lib_modc_dynUndefined
              return
            end
            local.get 0
            local.get 2
            call $dynrt_lib_modc_dynArrGet
            return
          end
        end
        call $dynrt_lib_modc_dynUndefined
        return
      end
    end
    local.get 2
    i32.const 6
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 3
        i32.const 4
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 1
            call $dynrt_lib_modc__fn85
            global.get $dynrt_lib_modc_global2
            local.set 2
            global.get $dynrt_lib_modc_global3
            local.set 3
            local.get 0
            local.get 2
            local.get 3
            call $dynrt_lib_modc_dynGet
            local.set 2
            local.get 2
            i32.const -1
            i32.eq
            if (result i32)  ;; label = @5
              call $dynrt_lib_modc_dynUndefined
            else
              local.get 2
            end
            return
          end
        end
        call $dynrt_lib_modc_dynUndefined
        return
      end
    end
    call $dynrt_lib_modc_dynUndefined
    return)
  (func $dynrt_lib_modc__fn173 (param i32 i32) (result i32)
    local.get 0
    i32.const 65
    i32.ge_s
    if (result i32)  ;; label = @1
      local.get 0
      i32.const 90
      i32.le_s
    else
      i32.const 0
    end
    if  ;; label = @1
      i32.const 1
      return
    end
    local.get 0
    i32.const 97
    i32.ge_s
    if (result i32)  ;; label = @1
      local.get 0
      i32.const 122
      i32.le_s
    else
      i32.const 0
    end
    if  ;; label = @1
      i32.const 1
      return
    end
    local.get 0
    i32.const 95
    i32.eq
    if (result i32)  ;; label = @1
      i32.const 1
    else
      local.get 0
      i32.const 36
      i32.eq
    end
    if  ;; label = @1
      i32.const 1
      return
    end
    local.get 1
    i32.const 1
    i32.eq
    if (result i32)  ;; label = @1
      local.get 0
      i32.const 48
      i32.ge_s
    else
      i32.const 0
    end
    if (result i32)  ;; label = @1
      local.get 0
      i32.const 57
      i32.le_s
    else
      i32.const 0
    end
    if  ;; label = @1
      i32.const 1
      return
    end
    i32.const 0
    return)
  (func $dynrt_lib_modc__fn174 (param i32 i32)
    (local i32) (local i32) (local i32)
    local.get 1
    local.set 2
    i32.const 1
    local.set 3
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 3
          i32.const 1
          i32.eq
          i32.eqz
          br_if 2 (;@1;)
          global.get $dynrt_lib_modc_global20
          local.get 2
          i32.ge_s
          if  ;; label = @4
            i32.const 0
            local.set 3
          else
            block  ;; label = @5
              local.get 0
              local.get 1
              global.get $dynrt_lib_modc_global20
              call $dynrt_lib_modc__fn9
              local.set 4
              local.get 4
              i32.const 32
              i32.eq
              if (result i32)  ;; label = @6
                i32.const 1
              else
                local.get 4
                i32.const 9
                i32.eq
              end
              if (result i32)  ;; label = @6
                i32.const 1
              else
                local.get 4
                i32.const 10
                i32.eq
              end
              if (result i32)  ;; label = @6
                i32.const 1
              else
                local.get 4
                i32.const 13
                i32.eq
              end
              if  ;; label = @6
                global.get $dynrt_lib_modc_global20
                i32.const 1
                i32.add
                global.set $dynrt_lib_modc_global20
              else
                local.get 4
                i32.const 47
                i32.eq
                if (result i32)  ;; label = @7
                  global.get $dynrt_lib_modc_global20
                  i32.const 1
                  i32.add
                  local.get 2
                  i32.lt_s
                else
                  i32.const 0
                end
                if (result i32)  ;; label = @7
                  local.get 0
                  local.get 1
                  global.get $dynrt_lib_modc_global20
                  i32.const 1
                  i32.add
                  call $dynrt_lib_modc__fn9
                  i32.const 47
                  i32.eq
                else
                  i32.const 0
                end
                if  ;; label = @7
                  block  ;; label = @8
                    global.get $dynrt_lib_modc_global20
                    i32.const 2
                    i32.add
                    global.set $dynrt_lib_modc_global20
                    block  ;; label = @9
                      loop  ;; label = @10
                        block  ;; label = @11
                          global.get $dynrt_lib_modc_global20
                          local.get 2
                          i32.lt_s
                          if (result i32)  ;; label = @12
                            local.get 0
                            local.get 1
                            global.get $dynrt_lib_modc_global20
                            call $dynrt_lib_modc__fn9
                            i32.const 10
                            i32.ne
                          else
                            i32.const 0
                          end
                          i32.eqz
                          br_if 2 (;@9;)
                          global.get $dynrt_lib_modc_global20
                          i32.const 1
                          i32.add
                          global.set $dynrt_lib_modc_global20
                          br 1 (;@10;)
                        end
                      end
                    end
                  end
                else
                  local.get 4
                  i32.const 47
                  i32.eq
                  if (result i32)  ;; label = @8
                    global.get $dynrt_lib_modc_global20
                    i32.const 1
                    i32.add
                    local.get 2
                    i32.lt_s
                  else
                    i32.const 0
                  end
                  if (result i32)  ;; label = @8
                    local.get 0
                    local.get 1
                    global.get $dynrt_lib_modc_global20
                    i32.const 1
                    i32.add
                    call $dynrt_lib_modc__fn9
                    i32.const 42
                    i32.eq
                  else
                    i32.const 0
                  end
                  if  ;; label = @8
                    block  ;; label = @9
                      global.get $dynrt_lib_modc_global20
                      i32.const 2
                      i32.add
                      global.set $dynrt_lib_modc_global20
                      i32.const 0
                      local.set 4
                      block  ;; label = @10
                        loop  ;; label = @11
                          block  ;; label = @12
                            local.get 4
                            i32.eqz
                            if (result i32)  ;; label = @13
                              global.get $dynrt_lib_modc_global20
                              local.get 2
                              i32.lt_s
                            else
                              i32.const 0
                            end
                            i32.eqz
                            br_if 2 (;@10;)
                            local.get 0
                            local.get 1
                            global.get $dynrt_lib_modc_global20
                            call $dynrt_lib_modc__fn9
                            i32.const 42
                            i32.eq
                            if (result i32)  ;; label = @13
                              global.get $dynrt_lib_modc_global20
                              i32.const 1
                              i32.add
                              local.get 2
                              i32.lt_s
                            else
                              i32.const 0
                            end
                            if (result i32)  ;; label = @13
                              local.get 0
                              local.get 1
                              global.get $dynrt_lib_modc_global20
                              i32.const 1
                              i32.add
                              call $dynrt_lib_modc__fn9
                              i32.const 47
                              i32.eq
                            else
                              i32.const 0
                            end
                            if  ;; label = @13
                              block  ;; label = @14
                                global.get $dynrt_lib_modc_global20
                                i32.const 2
                                i32.add
                                global.set $dynrt_lib_modc_global20
                                i32.const 1
                                local.set 4
                              end
                            else
                              global.get $dynrt_lib_modc_global20
                              i32.const 1
                              i32.add
                              global.set $dynrt_lib_modc_global20
                            end
                            br 1 (;@11;)
                          end
                        end
                      end
                    end
                  else
                    i32.const 0
                    local.set 3
                  end
                end
              end
            end
          end
          br 1 (;@2;)
        end
      end
    end)
  (func $dynrt_lib_modc__fn175 (param i32 i32) (result i32)
    (local i32)
    global.get $dynrt_lib_modc_global20
    local.get 1
    i32.ge_s
    if  ;; label = @1
      i32.const -1
      return
    end
    local.get 0
    local.get 1
    global.get $dynrt_lib_modc_global20
    call $dynrt_lib_modc__fn9
    return)
  (func $dynrt_lib_modc__fn176 (param i32 i32) (result i32)
    (local i32)
    global.get $dynrt_lib_modc_global20
    i32.const 1
    i32.add
    local.get 1
    i32.ge_s
    if  ;; label = @1
      i32.const -1
      return
    end
    local.get 0
    local.get 1
    global.get $dynrt_lib_modc_global20
    i32.const 1
    i32.add
    call $dynrt_lib_modc__fn9
    return)
  (func $dynrt_lib_modc__fn177 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32)
    global.get $dynrt_lib_modc_global20
    local.tee 4
    local.set 2
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn175
    local.set 3
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 3
          i32.const 48
          i32.ge_s
          if (result i32)  ;; label = @4
            local.get 3
            i32.const 57
            i32.le_s
          else
            i32.const 0
          end
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            global.get $dynrt_lib_modc_global20
            i32.const 1
            i32.add
            global.set $dynrt_lib_modc_global20
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn175
            local.set 3
          end
          br 1 (;@2;)
        end
      end
    end
    local.get 3
    i32.const 46
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_lib_modc_global20
        i32.const 1
        i32.add
        global.set $dynrt_lib_modc_global20
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn175
        local.set 3
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 3
              i32.const 48
              i32.ge_s
              if (result i32)  ;; label = @6
                local.get 3
                i32.const 57
                i32.le_s
              else
                i32.const 0
              end
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                global.get $dynrt_lib_modc_global20
                i32.const 1
                i32.add
                global.set $dynrt_lib_modc_global20
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn175
                local.set 3
              end
              br 1 (;@4;)
            end
          end
        end
      end
    end
    local.get 3
    i32.const 101
    i32.eq
    if (result i32)  ;; label = @1
      i32.const 1
    else
      local.get 3
      i32.const 69
      i32.eq
    end
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_lib_modc_global20
        i32.const 1
        i32.add
        global.set $dynrt_lib_modc_global20
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn175
        local.set 3
        local.get 3
        i32.const 43
        i32.eq
        if (result i32)  ;; label = @3
          i32.const 1
        else
          local.get 3
          i32.const 45
          i32.eq
        end
        if  ;; label = @3
          block  ;; label = @4
            global.get $dynrt_lib_modc_global20
            i32.const 1
            i32.add
            global.set $dynrt_lib_modc_global20
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn175
            local.set 3
          end
        end
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 3
              i32.const 48
              i32.ge_s
              if (result i32)  ;; label = @6
                local.get 3
                i32.const 57
                i32.le_s
              else
                i32.const 0
              end
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                global.get $dynrt_lib_modc_global20
                i32.const 1
                i32.add
                global.set $dynrt_lib_modc_global20
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn175
                local.set 3
              end
              br 1 (;@4;)
            end
          end
        end
      end
    end
    local.get 0
    local.get 1
    local.get 2
    global.get $dynrt_lib_modc_global20
    call $dynrt_lib_modc__fn6
    local.set 3
    nop
    local.set 2
    local.get 2
    local.get 3
    call $dynrt_lib_modc__fn29
    call $dynrt_lib_modc_dynNumber
    return)
  (func $dynrt_lib_modc__fn178 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn175
    local.set 2
    global.get $dynrt_lib_modc_global20
    i32.const 1
    local.tee 16
    i32.add
    global.set $dynrt_lib_modc_global20
    i32.const 520
    local.set 3
    i32.const 0
    local.set 4
    i32.const 1
    local.tee 17
    local.set 5
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 5
          i32.const 1
          i32.eq
          i32.eqz
          br_if 2 (;@1;)
          global.get $dynrt_lib_modc_global20
          local.get 1
          i32.ge_s
          if  ;; label = @4
            i32.const 0
            local.set 5
          else
            block  ;; label = @5
              local.get 0
              local.get 1
              global.get $dynrt_lib_modc_global20
              call $dynrt_lib_modc__fn9
              local.set 6
              local.get 6
              local.get 2
              i32.eq
              if  ;; label = @6
                block  ;; label = @7
                  global.get $dynrt_lib_modc_global20
                  i32.const 1
                  i32.add
                  global.set $dynrt_lib_modc_global20
                  i32.const 0
                  local.set 5
                end
              else
                local.get 6
                i32.const 92
                i32.eq
                if  ;; label = @7
                  block  ;; label = @8
                    global.get $dynrt_lib_modc_global20
                    i32.const 1
                    i32.add
                    local.tee 9
                    global.set $dynrt_lib_modc_global20
                    local.get 0
                    local.get 1
                    global.get $dynrt_lib_modc_global20
                    call $dynrt_lib_modc__fn9
                    local.set 6
                    local.get 6
                    local.set 7
                    local.get 6
                    i32.const 110
                    i32.eq
                    if  ;; label = @9
                      i32.const 10
                      local.set 7
                    else
                      local.get 6
                      i32.const 116
                      i32.eq
                      if  ;; label = @10
                        i32.const 9
                        local.set 7
                      else
                        local.get 6
                        i32.const 114
                        i32.eq
                        if  ;; label = @11
                          i32.const 13
                          local.set 7
                        end
                      end
                    end
                    local.get 3
                    local.tee 10
                    local.set 3
                    local.get 4
                    local.tee 11
                    local.set 4
                    i32.const 1
                    call $__malloc
                    local.set 8
                    local.get 8
                    local.get 7
                    i32.store8
                    local.get 3
                    local.get 4
                    local.get 8
                    i32.const 1
                    call $dynrt_lib_modc__fn5
                    local.set 4
                    nop
                    local.set 3
                    global.get $dynrt_lib_modc_global20
                    i32.const 1
                    i32.add
                    local.tee 12
                    global.set $dynrt_lib_modc_global20
                  end
                else
                  block  ;; label = @8
                    local.get 3
                    local.tee 13
                    local.set 3
                    local.get 4
                    local.tee 14
                    local.set 4
                    i32.const 1
                    call $__malloc
                    local.set 8
                    local.get 8
                    local.get 6
                    i32.store8
                    local.get 3
                    local.get 4
                    local.get 8
                    i32.const 1
                    call $dynrt_lib_modc__fn5
                    local.set 4
                    nop
                    local.set 3
                    global.get $dynrt_lib_modc_global20
                    i32.const 1
                    local.tee 15
                    i32.add
                    global.set $dynrt_lib_modc_global20
                  end
                end
              end
            end
          end
          br 1 (;@2;)
        end
      end
    end
    local.get 3
    local.get 4
    call $dynrt_lib_modc_dynString
    return)
  (func $dynrt_lib_modc__fn179 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn174
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn175
    local.set 2
    local.get 2
    i32.const 40
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn210
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn206
            local.set 2
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn174
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn175
            i32.const 61
            i32.eq
            if (result i32)  ;; label = @5
              local.get 0
              local.get 1
              call $dynrt_lib_modc__fn176
              i32.const 62
              i32.eq
            else
              i32.const 0
            end
            if  ;; label = @5
              global.get $dynrt_lib_modc_global20
              i32.const 2
              i32.add
              global.set $dynrt_lib_modc_global20
            end
            local.get 2
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn208
            global.get $dynrt_lib_modc_global21
            call $dynrt_lib_modc__fn152
            return
          end
        end
        global.get $dynrt_lib_modc_global20
        i32.const 1
        i32.add
        global.set $dynrt_lib_modc_global20
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn189
        local.set 2
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn174
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn175
        i32.const 41
        i32.eq
        if  ;; label = @3
          global.get $dynrt_lib_modc_global20
          i32.const 1
          i32.add
          global.set $dynrt_lib_modc_global20
        end
        local.get 2
        return
      end
    end
    local.get 2
    i32.const 39
    i32.eq
    if (result i32)  ;; label = @1
      i32.const 1
    else
      local.get 2
      i32.const 34
      i32.eq
    end
    if  ;; label = @1
      local.get 0
      local.get 1
      call $dynrt_lib_modc__fn178
      return
    end
    local.get 2
    i32.const 91
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_lib_modc_global20
        i32.const 1
        i32.add
        global.set $dynrt_lib_modc_global20
        call $dynrt_lib_modc_dynArray
        local.set 2
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn174
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn175
        i32.const 93
        i32.eq
        if (result i32)  ;; label = @3
          i32.const 0
        else
          i32.const 1
        end
        local.set 3
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 3
              i32.const 1
              i32.eq
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn174
                i32.const 0
                local.set 4
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn175
                i32.const 46
                i32.eq
                if (result i32)  ;; label = @7
                  local.get 0
                  local.get 1
                  call $dynrt_lib_modc__fn176
                  i32.const 46
                  i32.eq
                else
                  i32.const 0
                end
                if  ;; label = @7
                  global.get $dynrt_lib_modc_global20
                  i32.const 2
                  i32.add
                  local.get 1
                  i32.lt_s
                  if  ;; label = @8
                    local.get 0
                    local.get 1
                    global.get $dynrt_lib_modc_global20
                    i32.const 2
                    i32.add
                    call $dynrt_lib_modc__fn9
                    i32.const 46
                    i32.eq
                    if  ;; label = @9
                      i32.const 1
                      local.set 4
                    end
                  end
                end
                local.get 4
                i32.const 1
                i32.eq
                if  ;; label = @7
                  block  ;; label = @8
                    global.get $dynrt_lib_modc_global20
                    i32.const 3
                    i32.add
                    global.set $dynrt_lib_modc_global20
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn189
                    local.set 4
                    local.get 4
                    local.set 5
                    local.get 5
                    i32.const 8
                    i32.add
                    i32.load
                    i32.const 5
                    i32.eq
                    if  ;; label = @9
                      block  ;; label = @10
                        local.get 4
                        call $dynrt_lib_modc_dynArrLen
                        local.set 5
                        i32.const 0
                        local.set 6
                        block  ;; label = @11
                          loop  ;; label = @12
                            block  ;; label = @13
                              local.get 6
                              local.get 5
                              i32.lt_s
                              i32.eqz
                              br_if 2 (;@11;)
                              block  ;; label = @14
                                local.get 2
                                local.get 4
                                local.get 6
                                call $dynrt_lib_modc_dynArrGet
                                call $dynrt_lib_modc_dynPush
                                local.get 6
                                local.tee 9
                                i32.const 1
                                i32.add
                                local.set 6
                              end
                              br 1 (;@12;)
                            end
                          end
                        end
                      end
                    end
                  end
                else
                  local.get 2
                  local.get 0
                  local.get 1
                  call $dynrt_lib_modc__fn189
                  call $dynrt_lib_modc_dynPush
                end
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn174
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn175
                i32.const 44
                i32.eq
                if  ;; label = @7
                  block  ;; label = @8
                    global.get $dynrt_lib_modc_global20
                    i32.const 1
                    i32.add
                    global.set $dynrt_lib_modc_global20
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn174
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn175
                    i32.const 93
                    i32.eq
                    if  ;; label = @9
                      i32.const 0
                      local.set 3
                    end
                  end
                else
                  i32.const 0
                  local.set 3
                end
              end
              br 1 (;@4;)
            end
          end
        end
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn174
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn175
        i32.const 93
        i32.eq
        if  ;; label = @3
          global.get $dynrt_lib_modc_global20
          i32.const 1
          i32.add
          global.set $dynrt_lib_modc_global20
        end
        local.get 2
        return
      end
    end
    local.get 2
    i32.const 123
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_lib_modc_global20
        i32.const 1
        i32.add
        global.set $dynrt_lib_modc_global20
        call $dynrt_lib_modc_dynObject
        local.set 2
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn174
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn175
        i32.const 125
        i32.eq
        if (result i32)  ;; label = @3
          i32.const 0
        else
          i32.const 1
        end
        local.set 3
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 3
              i32.const 1
              i32.eq
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn174
                i32.const 0
                local.set 4
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn175
                i32.const 46
                i32.eq
                if (result i32)  ;; label = @7
                  local.get 0
                  local.get 1
                  call $dynrt_lib_modc__fn176
                  i32.const 46
                  i32.eq
                else
                  i32.const 0
                end
                if  ;; label = @7
                  global.get $dynrt_lib_modc_global20
                  i32.const 2
                  i32.add
                  local.get 1
                  i32.lt_s
                  if (result i32)  ;; label = @8
                    local.get 0
                    local.get 1
                    global.get $dynrt_lib_modc_global20
                    i32.const 2
                    i32.add
                    call $dynrt_lib_modc__fn9
                    i32.const 46
                    i32.eq
                  else
                    i32.const 0
                  end
                  if  ;; label = @8
                    i32.const 1
                    local.set 4
                  end
                end
                local.get 4
                i32.const 1
                i32.eq
                if  ;; label = @7
                  block  ;; label = @8
                    global.get $dynrt_lib_modc_global20
                    i32.const 3
                    i32.add
                    global.set $dynrt_lib_modc_global20
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn189
                    local.set 4
                    local.get 4
                    local.set 5
                    local.get 5
                    i32.const 8
                    i32.add
                    i32.load
                    i32.const 6
                    i32.eq
                    if  ;; label = @9
                      block  ;; label = @10
                        local.get 4
                        call $dynrt_lib_modc_dynObjLen
                        local.set 5
                        i32.const 0
                        local.set 6
                        block  ;; label = @11
                          loop  ;; label = @12
                            block  ;; label = @13
                              local.get 6
                              local.get 5
                              i32.lt_s
                              i32.eqz
                              br_if 2 (;@11;)
                              block  ;; label = @14
                                local.get 4
                                local.get 6
                                call $dynrt_lib_modc__fn95
                                call $dynrt_lib_modc__fn85
                                global.get $dynrt_lib_modc_global2
                                local.set 7
                                global.get $dynrt_lib_modc_global3
                                local.set 8
                                local.get 2
                                local.get 7
                                local.get 8
                                local.get 4
                                local.get 6
                                call $dynrt_lib_modc_dynObjValAt
                                call $dynrt_lib_modc_dynSet
                                local.get 6
                                local.tee 10
                                i32.const 1
                                i32.add
                                local.set 6
                              end
                              br 1 (;@12;)
                            end
                          end
                        end
                      end
                    end
                  end
                else
                  block  ;; label = @8
                    i32.const 0
                    local.tee 11
                    drop
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn175
                    local.set 4
                    local.get 4
                    i32.const 39
                    i32.eq
                    if (result i32)  ;; label = @9
                      i32.const 1
                    else
                      local.get 4
                      i32.const 34
                      i32.eq
                    end
                    if  ;; label = @9
                      block  ;; label = @10
                        local.get 0
                        local.get 1
                        call $dynrt_lib_modc__fn178
                        call $dynrt_lib_modc__fn85
                        global.get $dynrt_lib_modc_global2
                        local.set 4
                        global.get $dynrt_lib_modc_global3
                        local.set 5
                      end
                    else
                      block  ;; label = @10
                        local.get 0
                        local.get 1
                        call $dynrt_lib_modc__fn192
                        global.get $dynrt_lib_modc_global2
                        local.set 4
                        global.get $dynrt_lib_modc_global3
                        local.set 5
                      end
                    end
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn174
                    i32.const 0
                    local.tee 12
                    drop
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn175
                    i32.const 58
                    i32.eq
                    if  ;; label = @9
                      block  ;; label = @10
                        global.get $dynrt_lib_modc_global20
                        i32.const 1
                        i32.add
                        global.set $dynrt_lib_modc_global20
                        local.get 0
                        local.get 1
                        call $dynrt_lib_modc__fn189
                        local.set 6
                      end
                    else
                      local.get 0
                      local.get 1
                      call $dynrt_lib_modc__fn175
                      i32.const 40
                      i32.eq
                      if  ;; label = @10
                        block  ;; label = @11
                          local.get 0
                          local.get 1
                          call $dynrt_lib_modc__fn206
                          local.set 6
                          local.get 0
                          local.get 1
                          call $dynrt_lib_modc__fn174
                          local.get 6
                          local.get 0
                          local.get 1
                          call $dynrt_lib_modc__fn207
                          global.get $dynrt_lib_modc_global21
                          call $dynrt_lib_modc__fn152
                          local.set 6
                        end
                      else
                        block  ;; label = @11
                          global.get $dynrt_lib_modc_global21
                          i32.const -1
                          i32.eq
                          if (result i32)  ;; label = @12
                            call $dynrt_lib_modc_dynUndefined
                          else
                            global.get $dynrt_lib_modc_global21
                            local.get 4
                            local.get 5
                            call $dynrt_lib_modc__fn156
                          end
                          local.set 6
                          local.get 6
                          i32.const -1
                          i32.eq
                          if  ;; label = @12
                            call $dynrt_lib_modc_dynUndefined
                            local.set 6
                          end
                        end
                      end
                    end
                    local.get 2
                    local.get 4
                    local.get 5
                    local.get 6
                    call $dynrt_lib_modc_dynSet
                  end
                end
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn174
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn175
                i32.const 44
                i32.eq
                if  ;; label = @7
                  block  ;; label = @8
                    global.get $dynrt_lib_modc_global20
                    i32.const 1
                    i32.add
                    global.set $dynrt_lib_modc_global20
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn174
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn175
                    i32.const 125
                    i32.eq
                    if  ;; label = @9
                      i32.const 0
                      local.set 3
                    end
                  end
                else
                  i32.const 0
                  local.set 3
                end
              end
              br 1 (;@4;)
            end
          end
        end
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn174
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn175
        i32.const 125
        i32.eq
        if  ;; label = @3
          global.get $dynrt_lib_modc_global20
          i32.const 1
          i32.add
          global.set $dynrt_lib_modc_global20
        end
        local.get 2
        return
      end
    end
    local.get 2
    i32.const 96
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_lib_modc_global20
        local.tee 16
        i32.const 1
        local.tee 17
        i32.add
        global.set $dynrt_lib_modc_global20
        i32.const 520
        i32.const 0
        call $dynrt_lib_modc_dynString
        local.set 2
        global.get $dynrt_lib_modc_global20
        local.tee 18
        local.set 3
        i32.const 1
        local.tee 19
        local.set 4
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 4
              i32.const 1
              i32.eq
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn175
                local.set 5
                local.get 5
                i32.const -1
                i32.eq
                if  ;; label = @7
                  i32.const 0
                  local.set 4
                else
                  local.get 5
                  i32.const 96
                  i32.eq
                  if  ;; label = @8
                    block  ;; label = @9
                      nop
                      local.get 2
                      local.get 0
                      local.get 1
                      local.get 3
                      global.get $dynrt_lib_modc_global20
                      call $dynrt_lib_modc__fn6
                      call $dynrt_lib_modc_dynString
                      call $dynrt_lib_modc_dynAdd
                      local.set 2
                      global.get $dynrt_lib_modc_global20
                      local.tee 13
                      i32.const 1
                      i32.add
                      global.set $dynrt_lib_modc_global20
                      i32.const 0
                      local.set 4
                    end
                  else
                    local.get 5
                    i32.const 36
                    i32.eq
                    if (result i32)  ;; label = @9
                      local.get 0
                      local.get 1
                      call $dynrt_lib_modc__fn176
                      i32.const 123
                      i32.eq
                    else
                      i32.const 0
                    end
                    if  ;; label = @9
                      block  ;; label = @10
                        nop
                        local.get 2
                        local.get 0
                        local.get 1
                        local.get 3
                        global.get $dynrt_lib_modc_global20
                        call $dynrt_lib_modc__fn6
                        call $dynrt_lib_modc_dynString
                        call $dynrt_lib_modc_dynAdd
                        local.set 2
                        global.get $dynrt_lib_modc_global20
                        local.tee 14
                        i32.const 2
                        i32.add
                        global.set $dynrt_lib_modc_global20
                        local.get 0
                        local.get 1
                        call $dynrt_lib_modc__fn189
                        local.set 3
                        local.get 2
                        local.get 3
                        call $dynrt_lib_modc_dynAdd
                        local.set 2
                        local.get 0
                        local.get 1
                        call $dynrt_lib_modc__fn174
                        local.get 0
                        local.get 1
                        call $dynrt_lib_modc__fn175
                        i32.const 125
                        i32.eq
                        if  ;; label = @11
                          global.get $dynrt_lib_modc_global20
                          i32.const 1
                          i32.add
                          global.set $dynrt_lib_modc_global20
                        end
                        global.get $dynrt_lib_modc_global20
                        local.tee 15
                        local.set 3
                      end
                    else
                      global.get $dynrt_lib_modc_global20
                      i32.const 1
                      i32.add
                      global.set $dynrt_lib_modc_global20
                    end
                  end
                end
              end
              br 1 (;@4;)
            end
          end
        end
        local.get 2
        return
      end
    end
    local.get 2
    i32.const 48
    i32.ge_s
    if (result i32)  ;; label = @1
      local.get 2
      i32.const 57
      i32.le_s
    else
      i32.const 0
    end
    if  ;; label = @1
      local.get 0
      local.get 1
      call $dynrt_lib_modc__fn177
      return
    end
    local.get 2
    i32.const 46
    i32.eq
    if  ;; label = @1
      local.get 0
      local.get 1
      call $dynrt_lib_modc__fn177
      return
    end
    local.get 2
    i32.const 0
    call $dynrt_lib_modc__fn173
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_lib_modc_global20
        local.tee 23
        local.set 3
        local.get 2
        local.set 2
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 2
              i32.const 1
              call $dynrt_lib_modc__fn173
              i32.const 1
              i32.eq
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                global.get $dynrt_lib_modc_global20
                i32.const 1
                i32.add
                global.set $dynrt_lib_modc_global20
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn175
                local.set 2
              end
              br 1 (;@4;)
            end
          end
        end
        local.get 0
        local.get 1
        local.get 3
        global.get $dynrt_lib_modc_global20
        call $dynrt_lib_modc__fn6
        local.set 4
        nop
        local.set 3
        local.get 3
        local.get 4
        i32.const 998
        i32.const 8
        call $dynrt_lib_modc__fn169
        i32.const 1
        i32.eq
        if  ;; label = @3
          local.get 0
          local.get 1
          call $dynrt_lib_modc__fn209
          return
        end
        local.get 3
        local.get 4
        i32.const 1006
        i32.const 5
        call $dynrt_lib_modc__fn169
        i32.const 1
        i32.eq
        if  ;; label = @3
          local.get 0
          local.get 1
          call $dynrt_lib_modc__fn212
          return
        end
        local.get 3
        local.get 4
        i32.const 525
        i32.const 4
        call $dynrt_lib_modc__fn169
        i32.const 1
        i32.eq
        if  ;; label = @3
          i32.const 1
          call $dynrt_lib_modc_dynBool
          return
        end
        local.get 3
        local.get 4
        i32.const 520
        i32.const 5
        call $dynrt_lib_modc__fn169
        i32.const 1
        i32.eq
        if  ;; label = @3
          i32.const 0
          call $dynrt_lib_modc_dynBool
          return
        end
        local.get 3
        local.get 4
        i32.const 529
        i32.const 4
        call $dynrt_lib_modc__fn169
        i32.const 1
        i32.eq
        if  ;; label = @3
          call $dynrt_lib_modc_dynNull
          return
        end
        local.get 3
        local.get 4
        i32.const 533
        i32.const 9
        call $dynrt_lib_modc__fn169
        i32.const 1
        i32.eq
        if  ;; label = @3
          call $dynrt_lib_modc_dynUndefined
          return
        end
        local.get 3
        local.get 4
        i32.const 1011
        i32.const 5
        call $dynrt_lib_modc__fn169
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn174
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn175
            local.set 2
            local.get 2
            i32.const 59
            i32.eq
            if (result i32)  ;; label = @5
              i32.const 1
            else
              local.get 2
              i32.const 41
              i32.eq
            end
            if (result i32)  ;; label = @5
              i32.const 1
            else
              local.get 2
              i32.const 125
              i32.eq
            end
            if (result i32)  ;; label = @5
              i32.const 1
            else
              local.get 2
              i32.const 93
              i32.eq
            end
            if (result i32)  ;; label = @5
              i32.const 1
            else
              local.get 2
              i32.const -1
              i32.eq
            end
            if  ;; label = @5
              global.get $dynrt_lib_modc_global22
              i32.const 1
              i32.eq
              if (result i32)  ;; label = @6
                global.get $dynrt_lib_modc_global31
                i32.const -1
                i32.ne
              else
                i32.const 0
              end
              if  ;; label = @6
                global.get $dynrt_lib_modc_global31
                call $dynrt_lib_modc_dynUndefined
                call $dynrt_lib_modc_dynPush
              end
            else
              block  ;; label = @6
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn189
                local.set 2
                global.get $dynrt_lib_modc_global22
                i32.const 1
                i32.eq
                if (result i32)  ;; label = @7
                  global.get $dynrt_lib_modc_global31
                  i32.const -1
                  i32.ne
                else
                  i32.const 0
                end
                if  ;; label = @7
                  global.get $dynrt_lib_modc_global31
                  local.get 2
                  call $dynrt_lib_modc_dynPush
                end
              end
            end
            call $dynrt_lib_modc_dynUndefined
            return
          end
        end
        local.get 3
        local.get 4
        i32.const 1016
        i32.const 6
        call $dynrt_lib_modc__fn169
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            global.get $dynrt_lib_modc_global20
            local.set 2
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn174
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn175
            i32.const 46
            i32.eq
            if  ;; label = @5
              block  ;; label = @6
                global.get $dynrt_lib_modc_global20
                i32.const 1
                i32.add
                global.set $dynrt_lib_modc_global20
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn192
                global.get $dynrt_lib_modc_global2
                local.set 5
                global.get $dynrt_lib_modc_global3
                local.set 6
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn174
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn175
                i32.const 40
                i32.eq
                if  ;; label = @7
                  block  ;; label = @8
                    global.get $dynrt_lib_modc_global20
                    i32.const 1
                    i32.add
                    global.set $dynrt_lib_modc_global20
                    call $dynrt_lib_modc_dynArray
                    local.set 2
                    local.get 2
                    call $dynrt_lib_modc__fn61
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn174
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn175
                    i32.const 41
                    i32.eq
                    if  ;; label = @9
                      global.get $dynrt_lib_modc_global20
                      i32.const 1
                      i32.add
                      global.set $dynrt_lib_modc_global20
                    else
                      block  ;; label = @10
                        i32.const 1
                        local.set 3
                        block  ;; label = @11
                          loop  ;; label = @12
                            block  ;; label = @13
                              local.get 3
                              i32.const 1
                              i32.eq
                              i32.eqz
                              br_if 2 (;@11;)
                              block  ;; label = @14
                                local.get 2
                                local.get 0
                                local.get 1
                                call $dynrt_lib_modc__fn189
                                call $dynrt_lib_modc_dynPush
                                local.get 0
                                local.get 1
                                call $dynrt_lib_modc__fn174
                                local.get 0
                                local.get 1
                                call $dynrt_lib_modc__fn175
                                local.set 4
                                local.get 4
                                i32.const 44
                                i32.eq
                                if  ;; label = @15
                                  global.get $dynrt_lib_modc_global20
                                  i32.const 1
                                  i32.add
                                  global.set $dynrt_lib_modc_global20
                                else
                                  block  ;; label = @16
                                    local.get 4
                                    i32.const 41
                                    i32.eq
                                    if  ;; label = @17
                                      global.get $dynrt_lib_modc_global20
                                      i32.const 1
                                      i32.add
                                      global.set $dynrt_lib_modc_global20
                                    end
                                    i32.const 0
                                    local.set 3
                                  end
                                end
                              end
                              br 1 (;@12;)
                            end
                          end
                        end
                      end
                    end
                    call $dynrt_lib_modc_dynUndefined
                    local.set 3
                    global.get $dynrt_lib_modc_global22
                    i32.const 1
                    i32.eq
                    if  ;; label = @9
                      local.get 5
                      local.get 6
                      local.get 2
                      call $dynrt_lib_modc__fn102
                      local.set 3
                    end
                    call $dynrt_lib_modc__fn62
                    local.get 3
                    return
                  end
                end
              end
            end
            local.get 2
            global.set $dynrt_lib_modc_global20
          end
        end
        local.get 3
        local.get 4
        i32.const 1022
        i32.const 7
        call $dynrt_lib_modc__fn169
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            global.get $dynrt_lib_modc_global20
            local.set 2
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn174
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn175
            i32.const 46
            i32.eq
            if  ;; label = @5
              block  ;; label = @6
                global.get $dynrt_lib_modc_global20
                i32.const 1
                i32.add
                global.set $dynrt_lib_modc_global20
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn192
                global.get $dynrt_lib_modc_global2
                local.set 5
                global.get $dynrt_lib_modc_global3
                local.set 6
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn174
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn175
                i32.const 40
                i32.eq
                if  ;; label = @7
                  block  ;; label = @8
                    global.get $dynrt_lib_modc_global20
                    i32.const 1
                    i32.add
                    global.set $dynrt_lib_modc_global20
                    call $dynrt_lib_modc_dynArray
                    local.set 2
                    local.get 2
                    call $dynrt_lib_modc__fn61
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn174
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn175
                    i32.const 41
                    i32.eq
                    if  ;; label = @9
                      global.get $dynrt_lib_modc_global20
                      i32.const 1
                      i32.add
                      global.set $dynrt_lib_modc_global20
                    else
                      block  ;; label = @10
                        i32.const 1
                        local.set 3
                        block  ;; label = @11
                          loop  ;; label = @12
                            block  ;; label = @13
                              local.get 3
                              i32.const 1
                              i32.eq
                              i32.eqz
                              br_if 2 (;@11;)
                              block  ;; label = @14
                                local.get 2
                                local.get 0
                                local.get 1
                                call $dynrt_lib_modc__fn189
                                call $dynrt_lib_modc_dynPush
                                local.get 0
                                local.get 1
                                call $dynrt_lib_modc__fn174
                                local.get 0
                                local.get 1
                                call $dynrt_lib_modc__fn175
                                local.set 4
                                local.get 4
                                i32.const 44
                                i32.eq
                                if  ;; label = @15
                                  global.get $dynrt_lib_modc_global20
                                  i32.const 1
                                  i32.add
                                  global.set $dynrt_lib_modc_global20
                                else
                                  block  ;; label = @16
                                    local.get 4
                                    i32.const 41
                                    i32.eq
                                    if  ;; label = @17
                                      global.get $dynrt_lib_modc_global20
                                      i32.const 1
                                      i32.add
                                      global.set $dynrt_lib_modc_global20
                                    end
                                    i32.const 0
                                    local.set 3
                                  end
                                end
                              end
                              br 1 (;@12;)
                            end
                          end
                        end
                      end
                    end
                    global.get $dynrt_lib_modc_global22
                    i32.const 1
                    i32.eq
                    if  ;; label = @9
                      block  ;; label = @10
                        i32.const 0
                        local.set 3
                        local.get 5
                        local.get 6
                        i32.const 1029
                        i32.const 3
                        call $dynrt_lib_modc__fn169
                        i32.const 1
                        i32.eq
                        if  ;; label = @11
                          i32.const 1
                          local.set 3
                        end
                        local.get 5
                        local.get 6
                        i32.const 1032
                        i32.const 5
                        call $dynrt_lib_modc__fn169
                        i32.const 1
                        i32.eq
                        if  ;; label = @11
                          i32.const 1
                          local.set 3
                        end
                        local.get 5
                        local.get 6
                        i32.const 1037
                        i32.const 4
                        call $dynrt_lib_modc__fn169
                        i32.const 1
                        i32.eq
                        if  ;; label = @11
                          i32.const 1
                          local.set 3
                        end
                        local.get 5
                        local.get 6
                        i32.const 1041
                        i32.const 4
                        call $dynrt_lib_modc__fn169
                        i32.const 1
                        i32.eq
                        if  ;; label = @11
                          i32.const 1
                          local.set 3
                        end
                        local.get 3
                        i32.const 1
                        i32.eq
                        if  ;; label = @11
                          block  ;; label = @12
                            local.get 2
                            call $dynrt_lib_modc__fn108
                            global.get $dynrt_lib_modc_global2
                            local.set 2
                            global.get $dynrt_lib_modc_global3
                            local.set 3
                            local.get 2
                            local.tee 20
                            local.set 2
                            local.get 3
                            local.tee 21
                            local.set 3
                            local.get 2
                            local.get 3
                            i32.const 1045
                            i32.const 1
                            call $dynrt_lib_modc__fn5
                            local.set 3
                            nop
                            local.set 2
                            local.get 2
                            local.get 3
                            call $dynrt_lib_modc_dynString
                            local.set 2
                            local.get 2
                            call $dynrt_lib_modc_dynStrBytes
                            local.set 3
                            local.get 2
                            call $dynrt_lib_modc_dynStrLen
                            local.set 2
                            local.get 3
                            local.get 2
                            call $dynrt_lib_modc___host_print
                          end
                        end
                      end
                    end
                    call $dynrt_lib_modc__fn62
                    call $dynrt_lib_modc_dynUndefined
                    return
                  end
                end
              end
            end
            local.get 2
            global.set $dynrt_lib_modc_global20
          end
        end
        local.get 3
        local.get 4
        i32.const 1046
        i32.const 4
        call $dynrt_lib_modc__fn169
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            global.get $dynrt_lib_modc_global20
            local.set 2
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn174
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn175
            i32.const 46
            i32.eq
            if  ;; label = @5
              block  ;; label = @6
                global.get $dynrt_lib_modc_global20
                i32.const 1
                i32.add
                global.set $dynrt_lib_modc_global20
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn192
                global.get $dynrt_lib_modc_global2
                local.set 5
                global.get $dynrt_lib_modc_global3
                local.set 6
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn174
                local.get 5
                local.get 6
                i32.const 1050
                i32.const 2
                call $dynrt_lib_modc__fn169
                i32.const 1
                i32.eq
                if  ;; label = @7
                  f64.const 0x1.921fb54442d18p+1 (;=3.141592653589793;)
                  call $dynrt_lib_modc_dynNumber
                  return
                end
                local.get 5
                local.get 6
                i32.const 1052
                i32.const 1
                call $dynrt_lib_modc__fn169
                i32.const 1
                i32.eq
                if  ;; label = @7
                  f64.const 0x1.5bf0a8b145769p+1 (;=2.718281828459045;)
                  call $dynrt_lib_modc_dynNumber
                  return
                end
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn175
                i32.const 40
                i32.eq
                if  ;; label = @7
                  block  ;; label = @8
                    global.get $dynrt_lib_modc_global20
                    i32.const 1
                    i32.add
                    global.set $dynrt_lib_modc_global20
                    call $dynrt_lib_modc_dynArray
                    local.set 2
                    local.get 2
                    call $dynrt_lib_modc__fn61
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn174
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn175
                    i32.const 41
                    i32.eq
                    if  ;; label = @9
                      global.get $dynrt_lib_modc_global20
                      i32.const 1
                      i32.add
                      global.set $dynrt_lib_modc_global20
                    else
                      block  ;; label = @10
                        i32.const 1
                        local.set 3
                        block  ;; label = @11
                          loop  ;; label = @12
                            block  ;; label = @13
                              local.get 3
                              i32.const 1
                              i32.eq
                              i32.eqz
                              br_if 2 (;@11;)
                              block  ;; label = @14
                                local.get 2
                                local.get 0
                                local.get 1
                                call $dynrt_lib_modc__fn189
                                call $dynrt_lib_modc_dynPush
                                local.get 0
                                local.get 1
                                call $dynrt_lib_modc__fn174
                                local.get 0
                                local.get 1
                                call $dynrt_lib_modc__fn175
                                local.set 4
                                local.get 4
                                i32.const 44
                                i32.eq
                                if  ;; label = @15
                                  global.get $dynrt_lib_modc_global20
                                  i32.const 1
                                  i32.add
                                  global.set $dynrt_lib_modc_global20
                                else
                                  block  ;; label = @16
                                    local.get 4
                                    i32.const 41
                                    i32.eq
                                    if  ;; label = @17
                                      global.get $dynrt_lib_modc_global20
                                      i32.const 1
                                      i32.add
                                      global.set $dynrt_lib_modc_global20
                                    end
                                    i32.const 0
                                    local.set 3
                                  end
                                end
                              end
                              br 1 (;@12;)
                            end
                          end
                        end
                      end
                    end
                    call $dynrt_lib_modc_dynUndefined
                    local.set 3
                    global.get $dynrt_lib_modc_global22
                    i32.const 1
                    i32.eq
                    if  ;; label = @9
                      local.get 5
                      local.get 6
                      local.get 2
                      call $dynrt_lib_modc__fn103
                      local.set 3
                    end
                    call $dynrt_lib_modc__fn62
                    local.get 3
                    return
                  end
                end
              end
            end
            local.get 2
            global.set $dynrt_lib_modc_global20
          end
        end
        local.get 3
        local.get 4
        i32.const 1053
        i32.const 4
        call $dynrt_lib_modc__fn169
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            global.get $dynrt_lib_modc_global20
            local.set 2
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn174
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn175
            i32.const 46
            i32.eq
            if  ;; label = @5
              block  ;; label = @6
                global.get $dynrt_lib_modc_global20
                i32.const 1
                i32.add
                global.set $dynrt_lib_modc_global20
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn192
                global.get $dynrt_lib_modc_global2
                local.set 5
                global.get $dynrt_lib_modc_global3
                local.set 6
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn174
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn175
                i32.const 40
                i32.eq
                if  ;; label = @7
                  block  ;; label = @8
                    global.get $dynrt_lib_modc_global20
                    i32.const 1
                    i32.add
                    global.set $dynrt_lib_modc_global20
                    call $dynrt_lib_modc_dynArray
                    local.set 2
                    local.get 2
                    call $dynrt_lib_modc__fn61
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn174
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn175
                    i32.const 41
                    i32.eq
                    if  ;; label = @9
                      global.get $dynrt_lib_modc_global20
                      i32.const 1
                      i32.add
                      global.set $dynrt_lib_modc_global20
                    else
                      block  ;; label = @10
                        i32.const 1
                        local.set 3
                        block  ;; label = @11
                          loop  ;; label = @12
                            block  ;; label = @13
                              local.get 3
                              i32.const 1
                              i32.eq
                              i32.eqz
                              br_if 2 (;@11;)
                              block  ;; label = @14
                                local.get 2
                                local.get 0
                                local.get 1
                                call $dynrt_lib_modc__fn189
                                call $dynrt_lib_modc_dynPush
                                local.get 0
                                local.get 1
                                call $dynrt_lib_modc__fn174
                                local.get 0
                                local.get 1
                                call $dynrt_lib_modc__fn175
                                local.set 4
                                local.get 4
                                i32.const 44
                                i32.eq
                                if  ;; label = @15
                                  global.get $dynrt_lib_modc_global20
                                  i32.const 1
                                  i32.add
                                  global.set $dynrt_lib_modc_global20
                                else
                                  block  ;; label = @16
                                    local.get 4
                                    i32.const 41
                                    i32.eq
                                    if  ;; label = @17
                                      global.get $dynrt_lib_modc_global20
                                      i32.const 1
                                      i32.add
                                      global.set $dynrt_lib_modc_global20
                                    end
                                    i32.const 0
                                    local.set 3
                                  end
                                end
                              end
                              br 1 (;@12;)
                            end
                          end
                        end
                      end
                    end
                    call $dynrt_lib_modc_dynUndefined
                    local.set 3
                    global.get $dynrt_lib_modc_global22
                    i32.const 1
                    i32.eq
                    if  ;; label = @9
                      block  ;; label = @10
                        call $dynrt_lib_modc_dynUndefined
                        local.set 4
                        local.get 2
                        call $dynrt_lib_modc_dynArrLen
                        i32.const 0
                        i32.gt_s
                        if  ;; label = @11
                          local.get 2
                          i32.const 0
                          call $dynrt_lib_modc_dynArrGet
                          local.set 4
                        end
                        local.get 5
                        local.get 6
                        i32.const 1057
                        i32.const 5
                        call $dynrt_lib_modc__fn169
                        i32.const 1
                        i32.eq
                        if  ;; label = @11
                          block  ;; label = @12
                            local.get 4
                            call $dynrt_lib_modc__fn85
                            global.get $dynrt_lib_modc_global2
                            local.set 2
                            global.get $dynrt_lib_modc_global3
                            local.set 3
                            local.get 2
                            local.get 3
                            call $dynrt_lib_modc__fn106
                            local.set 3
                          end
                        else
                          local.get 5
                          local.get 6
                          i32.const 1062
                          i32.const 9
                          call $dynrt_lib_modc__fn169
                          i32.const 1
                          i32.eq
                          if  ;; label = @12
                            block  ;; label = @13
                              local.get 4
                              call $dynrt_lib_modc__fn105
                              global.get $dynrt_lib_modc_global2
                              local.set 2
                              global.get $dynrt_lib_modc_global3
                              local.set 3
                              local.get 2
                              local.get 3
                              call $dynrt_lib_modc_dynString
                              local.set 3
                            end
                          end
                        end
                      end
                    end
                    call $dynrt_lib_modc__fn62
                    local.get 3
                    return
                  end
                end
              end
            end
            local.get 2
            global.set $dynrt_lib_modc_global20
          end
        end
        local.get 3
        local.get 4
        i32.const 1071
        i32.const 7
        call $dynrt_lib_modc__fn169
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            global.get $dynrt_lib_modc_global20
            local.set 2
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn174
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn175
            i32.const 46
            i32.eq
            if  ;; label = @5
              block  ;; label = @6
                global.get $dynrt_lib_modc_global20
                i32.const 1
                i32.add
                global.set $dynrt_lib_modc_global20
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn192
                global.get $dynrt_lib_modc_global2
                local.set 5
                global.get $dynrt_lib_modc_global3
                local.set 6
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn174
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn175
                i32.const 40
                i32.eq
                if  ;; label = @7
                  block  ;; label = @8
                    global.get $dynrt_lib_modc_global20
                    i32.const 1
                    i32.add
                    global.set $dynrt_lib_modc_global20
                    call $dynrt_lib_modc_dynArray
                    local.set 2
                    local.get 2
                    call $dynrt_lib_modc__fn61
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn174
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn175
                    i32.const 41
                    i32.eq
                    if  ;; label = @9
                      global.get $dynrt_lib_modc_global20
                      i32.const 1
                      i32.add
                      global.set $dynrt_lib_modc_global20
                    else
                      block  ;; label = @10
                        i32.const 1
                        local.set 3
                        block  ;; label = @11
                          loop  ;; label = @12
                            block  ;; label = @13
                              local.get 3
                              i32.const 1
                              i32.eq
                              i32.eqz
                              br_if 2 (;@11;)
                              block  ;; label = @14
                                local.get 2
                                local.get 0
                                local.get 1
                                call $dynrt_lib_modc__fn189
                                call $dynrt_lib_modc_dynPush
                                local.get 0
                                local.get 1
                                call $dynrt_lib_modc__fn174
                                local.get 0
                                local.get 1
                                call $dynrt_lib_modc__fn175
                                local.set 4
                                local.get 4
                                i32.const 44
                                i32.eq
                                if  ;; label = @15
                                  global.get $dynrt_lib_modc_global20
                                  i32.const 1
                                  i32.add
                                  global.set $dynrt_lib_modc_global20
                                else
                                  block  ;; label = @16
                                    local.get 4
                                    i32.const 41
                                    i32.eq
                                    if  ;; label = @17
                                      global.get $dynrt_lib_modc_global20
                                      i32.const 1
                                      i32.add
                                      global.set $dynrt_lib_modc_global20
                                    end
                                    i32.const 0
                                    local.set 3
                                  end
                                end
                              end
                              br 1 (;@12;)
                            end
                          end
                        end
                      end
                    end
                    call $dynrt_lib_modc_dynUndefined
                    local.set 3
                    global.get $dynrt_lib_modc_global22
                    i32.const 1
                    i32.eq
                    if  ;; label = @9
                      local.get 5
                      local.get 6
                      local.get 2
                      call $dynrt_lib_modc__fn135
                      local.set 3
                    end
                    call $dynrt_lib_modc__fn62
                    local.get 3
                    return
                  end
                end
              end
            end
            local.get 2
            global.set $dynrt_lib_modc_global20
          end
        end
        local.get 3
        local.get 4
        i32.const 1078
        i32.const 3
        call $dynrt_lib_modc__fn169
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn174
            global.get $dynrt_lib_modc_global20
            local.tee 22
            local.set 2
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn175
            local.set 3
            block  ;; label = @5
              loop  ;; label = @6
                block  ;; label = @7
                  local.get 3
                  i32.const 1
                  call $dynrt_lib_modc__fn173
                  i32.const 1
                  i32.eq
                  i32.eqz
                  br_if 2 (;@5;)
                  block  ;; label = @8
                    global.get $dynrt_lib_modc_global20
                    i32.const 1
                    i32.add
                    global.set $dynrt_lib_modc_global20
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn175
                    local.set 3
                  end
                  br 1 (;@6;)
                end
              end
            end
            local.get 0
            local.get 1
            local.get 2
            global.get $dynrt_lib_modc_global20
            call $dynrt_lib_modc__fn6
            local.set 5
            nop
            local.set 2
            global.get $dynrt_lib_modc_global21
            i32.const -1
            i32.eq
            if (result i32)  ;; label = @5
              call $dynrt_lib_modc_dynUndefined
            else
              global.get $dynrt_lib_modc_global21
              local.get 2
              local.get 5
              call $dynrt_lib_modc__fn156
            end
            local.set 3
            local.get 3
            i32.const -1
            i32.eq
            if (result i32)  ;; label = @5
              call $dynrt_lib_modc_dynUndefined
            else
              local.get 3
            end
            local.set 6
            call $dynrt_lib_modc_dynArray
            local.set 7
            local.get 7
            call $dynrt_lib_modc__fn61
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn174
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn175
            i32.const 40
            i32.eq
            if  ;; label = @5
              block  ;; label = @6
                global.get $dynrt_lib_modc_global20
                i32.const 1
                i32.add
                global.set $dynrt_lib_modc_global20
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn174
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn175
                i32.const 41
                i32.eq
                if  ;; label = @7
                  global.get $dynrt_lib_modc_global20
                  i32.const 1
                  i32.add
                  global.set $dynrt_lib_modc_global20
                else
                  block  ;; label = @8
                    i32.const 1
                    local.set 3
                    block  ;; label = @9
                      loop  ;; label = @10
                        block  ;; label = @11
                          local.get 3
                          i32.const 1
                          i32.eq
                          i32.eqz
                          br_if 2 (;@9;)
                          block  ;; label = @12
                            local.get 0
                            local.get 1
                            call $dynrt_lib_modc__fn189
                            local.set 4
                            local.get 7
                            local.get 4
                            call $dynrt_lib_modc_dynPush
                            local.get 0
                            local.get 1
                            call $dynrt_lib_modc__fn174
                            local.get 0
                            local.get 1
                            call $dynrt_lib_modc__fn175
                            local.set 4
                            local.get 4
                            i32.const 44
                            i32.eq
                            if  ;; label = @13
                              global.get $dynrt_lib_modc_global20
                              i32.const 1
                              i32.add
                              global.set $dynrt_lib_modc_global20
                            else
                              block  ;; label = @14
                                local.get 4
                                i32.const 41
                                i32.eq
                                if  ;; label = @15
                                  global.get $dynrt_lib_modc_global20
                                  i32.const 1
                                  i32.add
                                  global.set $dynrt_lib_modc_global20
                                end
                                i32.const 0
                                local.set 3
                              end
                            end
                          end
                          br 1 (;@10;)
                        end
                      end
                    end
                  end
                end
              end
            end
            call $dynrt_lib_modc_dynUndefined
            local.set 3
            global.get $dynrt_lib_modc_global22
            i32.const 1
            i32.eq
            if  ;; label = @5
              local.get 2
              local.get 5
              i32.const 1081
              i32.const 3
              call $dynrt_lib_modc__fn169
              i32.const 1
              i32.eq
              if  ;; label = @6
                call $dynrt_lib_modc__fn112
                local.set 3
              else
                local.get 2
                local.get 5
                i32.const 1084
                i32.const 3
                call $dynrt_lib_modc__fn169
                i32.const 1
                i32.eq
                if  ;; label = @7
                  block  ;; label = @8
                    call $dynrt_lib_modc_dynUndefined
                    local.set 2
                    local.get 7
                    call $dynrt_lib_modc_dynArrLen
                    i32.const 0
                    i32.gt_s
                    if  ;; label = @9
                      local.get 7
                      i32.const 0
                      call $dynrt_lib_modc_dynArrGet
                      local.set 2
                    end
                    local.get 2
                    call $dynrt_lib_modc__fn113
                    local.set 3
                  end
                else
                  local.get 2
                  local.get 5
                  i32.const 1087
                  i32.const 6
                  call $dynrt_lib_modc__fn169
                  i32.const 1
                  i32.eq
                  if  ;; label = @8
                    block  ;; label = @9
                      i32.const 520
                      i32.const 0
                      call $dynrt_lib_modc_dynString
                      local.set 2
                      local.get 7
                      call $dynrt_lib_modc_dynArrLen
                      i32.const 0
                      i32.gt_s
                      if  ;; label = @10
                        local.get 7
                        i32.const 0
                        call $dynrt_lib_modc_dynArrGet
                        local.set 2
                      end
                      local.get 2
                      call $dynrt_lib_modc__fn128
                      local.set 3
                    end
                  else
                    local.get 6
                    local.get 7
                    call $dynrt_lib_modc__fn214
                    local.set 3
                  end
                end
              end
            end
            call $dynrt_lib_modc__fn62
            local.get 3
            return
          end
        end
        local.get 3
        local.get 4
        i32.const 1093
        i32.const 5
        call $dynrt_lib_modc__fn169
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn174
            global.get $dynrt_lib_modc_global21
            i32.const -1
            i32.eq
            if (result i32)  ;; label = @5
              i32.const -1
            else
              global.get $dynrt_lib_modc_global21
              i32.const 966
              i32.const 4
              call $dynrt_lib_modc__fn156
            end
            local.set 2
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn175
            local.set 3
            local.get 3
            i32.const 40
            i32.eq
            if  ;; label = @5
              block  ;; label = @6
                global.get $dynrt_lib_modc_global20
                i32.const 1
                i32.add
                global.set $dynrt_lib_modc_global20
                call $dynrt_lib_modc_dynArray
                local.set 7
                local.get 7
                call $dynrt_lib_modc__fn61
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn174
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn175
                i32.const 41
                i32.eq
                if  ;; label = @7
                  global.get $dynrt_lib_modc_global20
                  i32.const 1
                  i32.add
                  global.set $dynrt_lib_modc_global20
                else
                  block  ;; label = @8
                    i32.const 1
                    local.set 3
                    block  ;; label = @9
                      loop  ;; label = @10
                        block  ;; label = @11
                          local.get 3
                          i32.const 1
                          i32.eq
                          i32.eqz
                          br_if 2 (;@9;)
                          block  ;; label = @12
                            local.get 7
                            local.get 0
                            local.get 1
                            call $dynrt_lib_modc__fn189
                            call $dynrt_lib_modc_dynPush
                            local.get 0
                            local.get 1
                            call $dynrt_lib_modc__fn174
                            local.get 0
                            local.get 1
                            call $dynrt_lib_modc__fn175
                            local.set 4
                            local.get 4
                            i32.const 44
                            i32.eq
                            if  ;; label = @13
                              global.get $dynrt_lib_modc_global20
                              i32.const 1
                              i32.add
                              global.set $dynrt_lib_modc_global20
                            else
                              block  ;; label = @14
                                local.get 4
                                i32.const 41
                                i32.eq
                                if  ;; label = @15
                                  global.get $dynrt_lib_modc_global20
                                  i32.const 1
                                  i32.add
                                  global.set $dynrt_lib_modc_global20
                                end
                                i32.const 0
                                local.set 3
                              end
                            end
                          end
                          br 1 (;@10;)
                        end
                      end
                    end
                  end
                end
                global.get $dynrt_lib_modc_global22
                i32.const 1
                i32.eq
                if (result i32)  ;; label = @7
                  local.get 2
                  i32.const -1
                  i32.ne
                else
                  i32.const 0
                end
                if  ;; label = @7
                  block  ;; label = @8
                    global.get $dynrt_lib_modc_global21
                    i32.const 1098
                    i32.const 12
                    call $dynrt_lib_modc__fn156
                    local.set 3
                    local.get 3
                    i32.const -1
                    i32.ne
                    if  ;; label = @9
                      block  ;; label = @10
                        local.get 3
                        i32.const 1110
                        i32.const 6
                        call $dynrt_lib_modc_dynGet
                        local.set 3
                        local.get 3
                        i32.const -1
                        i32.ne
                        if  ;; label = @11
                          block  ;; label = @12
                            local.get 3
                            local.set 4
                            local.get 4
                            i32.const 8
                            i32.add
                            i32.load
                            i32.const 7
                            i32.eq
                            if  ;; label = @13
                              local.get 3
                              local.get 7
                              local.get 2
                              call $dynrt_lib_modc__fn161
                              drop
                            end
                          end
                        end
                      end
                    end
                  end
                end
                call $dynrt_lib_modc__fn62
                call $dynrt_lib_modc_dynUndefined
                return
              end
            end
            local.get 3
            i32.const 46
            i32.eq
            if  ;; label = @5
              block  ;; label = @6
                global.get $dynrt_lib_modc_global20
                i32.const 1
                i32.add
                global.set $dynrt_lib_modc_global20
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn192
                global.get $dynrt_lib_modc_global2
                local.set 3
                global.get $dynrt_lib_modc_global3
                local.set 4
                global.get $dynrt_lib_modc_global21
                i32.const -1
                i32.eq
                if (result i32)  ;; label = @7
                  i32.const -1
                else
                  global.get $dynrt_lib_modc_global21
                  i32.const 1116
                  i32.const 12
                  call $dynrt_lib_modc__fn156
                end
                local.set 5
                call $dynrt_lib_modc_dynUndefined
                local.set 6
                local.get 5
                i32.const -1
                i32.ne
                if  ;; label = @7
                  local.get 5
                  local.get 3
                  local.get 4
                  call $dynrt_lib_modc_dynMember
                  local.set 6
                end
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn174
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn175
                i32.const 40
                i32.eq
                if  ;; label = @7
                  block  ;; label = @8
                    global.get $dynrt_lib_modc_global20
                    i32.const 1
                    i32.add
                    global.set $dynrt_lib_modc_global20
                    call $dynrt_lib_modc_dynArray
                    local.set 7
                    local.get 7
                    call $dynrt_lib_modc__fn61
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn174
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn175
                    i32.const 41
                    i32.eq
                    if  ;; label = @9
                      global.get $dynrt_lib_modc_global20
                      i32.const 1
                      i32.add
                      global.set $dynrt_lib_modc_global20
                    else
                      block  ;; label = @10
                        i32.const 1
                        local.set 3
                        block  ;; label = @11
                          loop  ;; label = @12
                            block  ;; label = @13
                              local.get 3
                              i32.const 1
                              i32.eq
                              i32.eqz
                              br_if 2 (;@11;)
                              block  ;; label = @14
                                local.get 7
                                local.get 0
                                local.get 1
                                call $dynrt_lib_modc__fn189
                                call $dynrt_lib_modc_dynPush
                                local.get 0
                                local.get 1
                                call $dynrt_lib_modc__fn174
                                local.get 0
                                local.get 1
                                call $dynrt_lib_modc__fn175
                                local.set 4
                                local.get 4
                                i32.const 44
                                i32.eq
                                if  ;; label = @15
                                  global.get $dynrt_lib_modc_global20
                                  i32.const 1
                                  i32.add
                                  global.set $dynrt_lib_modc_global20
                                else
                                  block  ;; label = @16
                                    local.get 4
                                    i32.const 41
                                    i32.eq
                                    if  ;; label = @17
                                      global.get $dynrt_lib_modc_global20
                                      i32.const 1
                                      i32.add
                                      global.set $dynrt_lib_modc_global20
                                    end
                                    i32.const 0
                                    local.set 3
                                  end
                                end
                              end
                              br 1 (;@12;)
                            end
                          end
                        end
                      end
                    end
                    call $dynrt_lib_modc_dynUndefined
                    local.set 3
                    global.get $dynrt_lib_modc_global22
                    i32.const 1
                    i32.eq
                    if (result i32)  ;; label = @9
                      local.get 2
                      i32.const -1
                      i32.ne
                    else
                      i32.const 0
                    end
                    if  ;; label = @9
                      block  ;; label = @10
                        local.get 6
                        local.set 4
                        local.get 4
                        i32.const 8
                        i32.add
                        i32.load
                        i32.const 7
                        i32.eq
                        if  ;; label = @11
                          local.get 6
                          local.get 7
                          local.get 2
                          call $dynrt_lib_modc__fn161
                          local.set 3
                        end
                      end
                    end
                    call $dynrt_lib_modc__fn62
                    local.get 3
                    return
                  end
                end
                local.get 6
                return
              end
            end
            call $dynrt_lib_modc_dynUndefined
            return
          end
        end
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn174
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn175
        i32.const 61
        i32.eq
        if (result i32)  ;; label = @3
          local.get 0
          local.get 1
          call $dynrt_lib_modc__fn176
          i32.const 62
          i32.eq
        else
          i32.const 0
        end
        if  ;; label = @3
          block  ;; label = @4
            global.get $dynrt_lib_modc_global20
            i32.const 2
            i32.add
            global.set $dynrt_lib_modc_global20
            call $dynrt_lib_modc_dynArray
            local.set 2
            local.get 2
            local.get 3
            local.get 4
            call $dynrt_lib_modc_dynString
            call $dynrt_lib_modc_dynPush
            local.get 2
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn208
            global.get $dynrt_lib_modc_global21
            call $dynrt_lib_modc__fn152
            return
          end
        end
        global.get $dynrt_lib_modc_global21
        i32.const -1
        i32.eq
        if  ;; label = @3
          call $dynrt_lib_modc_dynUndefined
          return
        end
        global.get $dynrt_lib_modc_global21
        local.get 3
        local.get 4
        call $dynrt_lib_modc__fn156
        local.set 2
        local.get 2
        i32.const -1
        i32.eq
        if (result i32)  ;; label = @3
          call $dynrt_lib_modc_dynUndefined
        else
          local.get 2
        end
        return
      end
    end
    call $dynrt_lib_modc_dynUndefined
    return)
  (func $dynrt_lib_modc__fn180 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn179
    local.set 2
    i32.const 1
    local.set 3
    i32.const -1
    local.set 4
    i32.const 520
    local.set 5
    i32.const 0
    local.tee 18
    local.set 6
    local.get 18
    local.set 7
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 3
          i32.const 1
          i32.eq
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn174
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn175
            local.set 8
            i32.const 0
            local.set 9
            local.get 8
            i32.const 63
            i32.eq
            if (result i32)  ;; label = @5
              local.get 0
              local.get 1
              call $dynrt_lib_modc__fn176
              i32.const 46
              i32.eq
            else
              i32.const 0
            end
            if  ;; label = @5
              block  ;; label = @6
                global.get $dynrt_lib_modc_global20
                i32.const 2
                i32.add
                global.set $dynrt_lib_modc_global20
                local.get 7
                i32.eqz
                if  ;; label = @7
                  block  ;; label = @8
                    local.get 2
                    local.set 4
                    local.get 4
                    i32.const 8
                    i32.add
                    i32.load
                    local.set 4
                    local.get 4
                    i32.eqz
                    if (result i32)  ;; label = @9
                      i32.const 1
                    else
                      local.get 4
                      i32.const 1
                      i32.eq
                    end
                    if  ;; label = @9
                      i32.const 1
                      local.set 7
                    end
                  end
                end
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn174
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn175
                local.set 4
                local.get 4
                i32.const 91
                i32.eq
                if  ;; label = @7
                  block  ;; label = @8
                    global.get $dynrt_lib_modc_global20
                    i32.const 1
                    i32.add
                    global.set $dynrt_lib_modc_global20
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn189
                    local.set 9
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn174
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn175
                    i32.const 93
                    i32.eq
                    if  ;; label = @9
                      global.get $dynrt_lib_modc_global20
                      i32.const 1
                      i32.add
                      global.set $dynrt_lib_modc_global20
                    end
                    local.get 2
                    local.set 4
                    local.get 7
                    i32.const 1
                    i32.eq
                    if (result i32)  ;; label = @9
                      call $dynrt_lib_modc_dynUndefined
                    else
                      local.get 2
                      local.get 9
                      call $dynrt_lib_modc_dynIndexValue
                    end
                    local.set 2
                  end
                else
                  block  ;; label = @8
                    global.get $dynrt_lib_modc_global20
                    local.tee 14
                    local.set 4
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn175
                    local.set 5
                    block  ;; label = @9
                      loop  ;; label = @10
                        block  ;; label = @11
                          local.get 5
                          i32.const 1
                          call $dynrt_lib_modc__fn173
                          i32.const 1
                          i32.eq
                          i32.eqz
                          br_if 2 (;@9;)
                          block  ;; label = @12
                            global.get $dynrt_lib_modc_global20
                            i32.const 1
                            i32.add
                            global.set $dynrt_lib_modc_global20
                            local.get 0
                            local.get 1
                            call $dynrt_lib_modc__fn175
                            local.set 5
                          end
                          br 1 (;@10;)
                        end
                      end
                    end
                    local.get 0
                    local.get 1
                    local.get 4
                    global.get $dynrt_lib_modc_global20
                    call $dynrt_lib_modc__fn6
                    local.set 10
                    nop
                    local.set 9
                    local.get 2
                    local.set 4
                    local.get 9
                    local.set 5
                    local.get 10
                    local.set 6
                    local.get 7
                    i32.const 1
                    i32.eq
                    if (result i32)  ;; label = @9
                      call $dynrt_lib_modc_dynUndefined
                    else
                      local.get 2
                      local.get 9
                      local.get 10
                      call $dynrt_lib_modc_dynMember
                    end
                    local.set 2
                  end
                end
                i32.const 1
                local.set 9
              end
            end
            local.get 9
            i32.const 1
            i32.eq
            if  ;; label = @5
              nop
            else
              local.get 8
              i32.const 46
              i32.eq
              if  ;; label = @6
                block  ;; label = @7
                  global.get $dynrt_lib_modc_global20
                  local.tee 15
                  i32.const 1
                  i32.add
                  global.set $dynrt_lib_modc_global20
                  local.get 0
                  local.get 1
                  call $dynrt_lib_modc__fn174
                  global.get $dynrt_lib_modc_global20
                  local.tee 16
                  local.set 4
                  local.get 0
                  local.get 1
                  call $dynrt_lib_modc__fn175
                  local.set 5
                  block  ;; label = @8
                    loop  ;; label = @9
                      block  ;; label = @10
                        local.get 5
                        i32.const 1
                        call $dynrt_lib_modc__fn173
                        i32.const 1
                        i32.eq
                        i32.eqz
                        br_if 2 (;@8;)
                        block  ;; label = @11
                          global.get $dynrt_lib_modc_global20
                          i32.const 1
                          i32.add
                          global.set $dynrt_lib_modc_global20
                          local.get 0
                          local.get 1
                          call $dynrt_lib_modc__fn175
                          local.set 5
                        end
                        br 1 (;@9;)
                      end
                    end
                  end
                  local.get 0
                  local.get 1
                  local.get 4
                  global.get $dynrt_lib_modc_global20
                  call $dynrt_lib_modc__fn6
                  local.set 10
                  nop
                  local.set 9
                  local.get 2
                  local.set 4
                  local.get 9
                  local.set 5
                  local.get 10
                  local.set 6
                  local.get 7
                  i32.const 1
                  i32.eq
                  if (result i32)  ;; label = @8
                    call $dynrt_lib_modc_dynUndefined
                  else
                    local.get 2
                    local.get 9
                    local.get 10
                    call $dynrt_lib_modc_dynMember
                  end
                  local.set 2
                end
              else
                local.get 8
                i32.const 91
                i32.eq
                if  ;; label = @7
                  block  ;; label = @8
                    global.get $dynrt_lib_modc_global20
                    i32.const 1
                    i32.add
                    global.set $dynrt_lib_modc_global20
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn189
                    local.set 8
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn174
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn175
                    i32.const 93
                    i32.eq
                    if  ;; label = @9
                      global.get $dynrt_lib_modc_global20
                      i32.const 1
                      i32.add
                      global.set $dynrt_lib_modc_global20
                    end
                    local.get 2
                    local.set 4
                    i32.const 520
                    local.set 5
                    i32.const 0
                    local.set 6
                    local.get 7
                    i32.const 1
                    i32.eq
                    if (result i32)  ;; label = @9
                      call $dynrt_lib_modc_dynUndefined
                    else
                      local.get 2
                      local.get 8
                      call $dynrt_lib_modc_dynIndexValue
                    end
                    local.set 2
                  end
                else
                  local.get 8
                  i32.const 40
                  i32.eq
                  if  ;; label = @8
                    block  ;; label = @9
                      global.get $dynrt_lib_modc_global20
                      i32.const 1
                      i32.add
                      global.set $dynrt_lib_modc_global20
                      local.get 2
                      call $dynrt_lib_modc__fn61
                      local.get 4
                      i32.const -1
                      i32.ne
                      if (result i32)  ;; label = @10
                        i32.const 1
                      else
                        i32.const 0
                      end
                      local.set 8
                      local.get 8
                      i32.const 1
                      i32.eq
                      if  ;; label = @10
                        local.get 4
                        call $dynrt_lib_modc__fn61
                      end
                      call $dynrt_lib_modc_dynArray
                      local.set 9
                      local.get 9
                      call $dynrt_lib_modc__fn61
                      local.get 0
                      local.get 1
                      call $dynrt_lib_modc__fn174
                      local.get 0
                      local.get 1
                      call $dynrt_lib_modc__fn175
                      i32.const 41
                      i32.eq
                      if  ;; label = @10
                        global.get $dynrt_lib_modc_global20
                        i32.const 1
                        i32.add
                        global.set $dynrt_lib_modc_global20
                      else
                        block  ;; label = @11
                          i32.const 1
                          local.set 10
                          block  ;; label = @12
                            loop  ;; label = @13
                              block  ;; label = @14
                                local.get 10
                                i32.const 1
                                i32.eq
                                i32.eqz
                                br_if 2 (;@12;)
                                block  ;; label = @15
                                  local.get 0
                                  local.get 1
                                  call $dynrt_lib_modc__fn174
                                  i32.const 0
                                  local.set 11
                                  local.get 0
                                  local.get 1
                                  call $dynrt_lib_modc__fn175
                                  i32.const 46
                                  i32.eq
                                  if (result i32)  ;; label = @16
                                    local.get 0
                                    local.get 1
                                    call $dynrt_lib_modc__fn176
                                    i32.const 46
                                    i32.eq
                                  else
                                    i32.const 0
                                  end
                                  if  ;; label = @16
                                    global.get $dynrt_lib_modc_global20
                                    i32.const 2
                                    i32.add
                                    local.get 1
                                    i32.lt_s
                                    if (result i32)  ;; label = @17
                                      local.get 0
                                      local.get 1
                                      global.get $dynrt_lib_modc_global20
                                      i32.const 2
                                      i32.add
                                      call $dynrt_lib_modc__fn9
                                      i32.const 46
                                      i32.eq
                                    else
                                      i32.const 0
                                    end
                                    if  ;; label = @17
                                      i32.const 1
                                      local.set 11
                                    end
                                  end
                                  local.get 11
                                  i32.const 1
                                  i32.eq
                                  if  ;; label = @16
                                    block  ;; label = @17
                                      global.get $dynrt_lib_modc_global20
                                      i32.const 3
                                      i32.add
                                      global.set $dynrt_lib_modc_global20
                                      local.get 0
                                      local.get 1
                                      call $dynrt_lib_modc__fn189
                                      local.set 11
                                      local.get 11
                                      local.set 12
                                      local.get 12
                                      i32.const 8
                                      i32.add
                                      i32.load
                                      i32.const 5
                                      i32.eq
                                      if  ;; label = @18
                                        block  ;; label = @19
                                          local.get 11
                                          call $dynrt_lib_modc_dynArrLen
                                          local.set 12
                                          i32.const 0
                                          local.set 13
                                          block  ;; label = @20
                                            loop  ;; label = @21
                                              block  ;; label = @22
                                                local.get 13
                                                local.get 12
                                                i32.lt_s
                                                i32.eqz
                                                br_if 2 (;@20;)
                                                block  ;; label = @23
                                                  local.get 9
                                                  local.get 11
                                                  local.get 13
                                                  call $dynrt_lib_modc_dynArrGet
                                                  call $dynrt_lib_modc_dynPush
                                                  local.get 13
                                                  local.tee 17
                                                  i32.const 1
                                                  i32.add
                                                  local.set 13
                                                end
                                                br 1 (;@21;)
                                              end
                                            end
                                          end
                                        end
                                      end
                                    end
                                  else
                                    block  ;; label = @17
                                      local.get 0
                                      local.get 1
                                      call $dynrt_lib_modc__fn189
                                      local.set 11
                                      local.get 9
                                      local.get 11
                                      call $dynrt_lib_modc_dynPush
                                    end
                                  end
                                  local.get 0
                                  local.get 1
                                  call $dynrt_lib_modc__fn174
                                  local.get 0
                                  local.get 1
                                  call $dynrt_lib_modc__fn175
                                  local.set 11
                                  local.get 11
                                  i32.const 44
                                  i32.eq
                                  if  ;; label = @16
                                    global.get $dynrt_lib_modc_global20
                                    i32.const 1
                                    i32.add
                                    global.set $dynrt_lib_modc_global20
                                  else
                                    block  ;; label = @17
                                      local.get 11
                                      i32.const 41
                                      i32.eq
                                      if  ;; label = @18
                                        global.get $dynrt_lib_modc_global20
                                        i32.const 1
                                        i32.add
                                        global.set $dynrt_lib_modc_global20
                                      end
                                      i32.const 0
                                      local.set 10
                                    end
                                  end
                                end
                                br 1 (;@13;)
                              end
                            end
                          end
                        end
                      end
                      global.get $dynrt_lib_modc_global22
                      i32.const 1
                      i32.eq
                      if (result i32)  ;; label = @10
                        local.get 7
                        i32.eqz
                      else
                        i32.const 0
                      end
                      if  ;; label = @10
                        local.get 8
                        i32.const 1
                        i32.eq
                        if  ;; label = @11
                          block  ;; label = @12
                            local.get 4
                            local.set 10
                            local.get 2
                            local.set 11
                            local.get 10
                            i32.const 8
                            i32.add
                            i32.load
                            i32.const 5
                            i32.eq
                            if (result i32)  ;; label = @13
                              local.get 11
                              i32.const 8
                              i32.add
                              i32.load
                              i32.const 7
                              i32.ne
                            else
                              i32.const 0
                            end
                            if  ;; label = @13
                              local.get 4
                              local.get 5
                              local.get 6
                              local.get 9
                              call $dynrt_lib_modc__fn100
                              local.set 2
                            else
                              local.get 10
                              i32.const 8
                              i32.add
                              i32.load
                              i32.const 4
                              i32.eq
                              if (result i32)  ;; label = @14
                                local.get 11
                                i32.const 8
                                i32.add
                                i32.load
                                i32.const 7
                                i32.ne
                              else
                                i32.const 0
                              end
                              if  ;; label = @14
                                local.get 4
                                local.get 5
                                local.get 6
                                local.get 9
                                call $dynrt_lib_modc__fn101
                                local.set 2
                              else
                                local.get 10
                                i32.const 8
                                i32.add
                                i32.load
                                i32.const 6
                                i32.eq
                                if (result i32)  ;; label = @15
                                  local.get 11
                                  i32.const 8
                                  i32.add
                                  i32.load
                                  i32.const 7
                                  i32.ne
                                else
                                  i32.const 0
                                end
                                if (result i32)  ;; label = @15
                                  local.get 4
                                  i32.const 842
                                  i32.const 6
                                  call $dynrt_lib_modc_dynHas
                                  i32.const 1
                                  i32.eq
                                else
                                  i32.const 0
                                end
                                if  ;; label = @15
                                  local.get 4
                                  local.get 5
                                  local.get 6
                                  local.get 9
                                  call $dynrt_lib_modc__fn114
                                  local.set 2
                                else
                                  local.get 10
                                  i32.const 8
                                  i32.add
                                  i32.load
                                  i32.const 6
                                  i32.eq
                                  if (result i32)  ;; label = @16
                                    local.get 11
                                    i32.const 8
                                    i32.add
                                    i32.load
                                    i32.const 7
                                    i32.ne
                                  else
                                    i32.const 0
                                  end
                                  if (result i32)  ;; label = @16
                                    local.get 4
                                    i32.const 854
                                    i32.const 6
                                    call $dynrt_lib_modc_dynHas
                                    i32.const 1
                                    i32.eq
                                  else
                                    i32.const 0
                                  end
                                  if  ;; label = @16
                                    local.get 4
                                    local.get 5
                                    local.get 6
                                    local.get 9
                                    call $dynrt_lib_modc__fn115
                                    local.set 2
                                  else
                                    local.get 10
                                    i32.const 8
                                    i32.add
                                    i32.load
                                    i32.const 6
                                    i32.eq
                                    if (result i32)  ;; label = @17
                                      local.get 11
                                      i32.const 8
                                      i32.add
                                      i32.load
                                      i32.const 7
                                      i32.ne
                                    else
                                      i32.const 0
                                    end
                                    if (result i32)  ;; label = @17
                                      local.get 4
                                      i32.const 751
                                      i32.const 7
                                      call $dynrt_lib_modc_dynHas
                                      i32.const 1
                                      i32.eq
                                    else
                                      i32.const 0
                                    end
                                    if  ;; label = @17
                                      local.get 4
                                      local.get 5
                                      local.get 6
                                      local.get 9
                                      call $dynrt_lib_modc__fn129
                                      local.set 2
                                    else
                                      local.get 10
                                      i32.const 8
                                      i32.add
                                      i32.load
                                      i32.const 6
                                      i32.eq
                                      if (result i32)  ;; label = @18
                                        local.get 11
                                        i32.const 8
                                        i32.add
                                        i32.load
                                        i32.const 7
                                        i32.ne
                                      else
                                        i32.const 0
                                      end
                                      if (result i32)  ;; label = @18
                                        local.get 4
                                        i32.const 890
                                        i32.const 6
                                        call $dynrt_lib_modc_dynHas
                                        i32.const 1
                                        i32.eq
                                      else
                                        i32.const 0
                                      end
                                      if  ;; label = @18
                                        local.get 4
                                        local.get 5
                                        local.get 6
                                        local.get 9
                                        call $dynrt_lib_modc__fn130
                                        local.set 2
                                      else
                                        local.get 10
                                        i32.const 8
                                        i32.add
                                        i32.load
                                        i32.const 6
                                        i32.eq
                                        if (result i32)  ;; label = @19
                                          local.get 11
                                          i32.const 8
                                          i32.add
                                          i32.load
                                          i32.const 7
                                          i32.ne
                                        else
                                          i32.const 0
                                        end
                                        if (result i32)  ;; label = @19
                                          local.get 4
                                          i32.const 911
                                          i32.const 7
                                          call $dynrt_lib_modc_dynHas
                                          i32.const 1
                                          i32.eq
                                        else
                                          i32.const 0
                                        end
                                        if  ;; label = @19
                                          local.get 4
                                          local.get 5
                                          local.get 6
                                          local.get 9
                                          call $dynrt_lib_modc__fn136
                                          local.set 2
                                        else
                                          local.get 2
                                          local.get 9
                                          local.get 4
                                          call $dynrt_lib_modc__fn161
                                          local.set 2
                                        end
                                      end
                                    end
                                  end
                                end
                              end
                            end
                          end
                        else
                          local.get 2
                          local.get 9
                          call $dynrt_lib_modc_dynApply
                          local.set 2
                        end
                      else
                        call $dynrt_lib_modc_dynUndefined
                        local.set 2
                      end
                      call $dynrt_lib_modc__fn62
                      local.get 8
                      i32.const 1
                      i32.eq
                      if  ;; label = @10
                        call $dynrt_lib_modc__fn62
                      end
                      call $dynrt_lib_modc__fn62
                      i32.const -1
                      local.set 4
                    end
                  else
                    i32.const 0
                    local.set 3
                  end
                end
              end
            end
          end
          br 1 (;@2;)
        end
      end
    end
    local.get 2
    return)
  (func $dynrt_lib_modc__fn181 (param i32) (result i32)
    (local i32)
    local.get 0
    local.set 1
    local.get 1
    i32.const 8
    i32.add
    i32.load
    local.set 1
    local.get 1
    i32.eqz
    if  ;; label = @1
      i32.const 533
      i32.const 9
      call $dynrt_lib_modc_dynString
      return
    end
    local.get 1
    i32.const 2
    i32.eq
    if  ;; label = @1
      i32.const 1128
      i32.const 7
      call $dynrt_lib_modc_dynString
      return
    end
    local.get 1
    i32.const 3
    i32.eq
    if  ;; label = @1
      i32.const 1135
      i32.const 6
      call $dynrt_lib_modc_dynString
      return
    end
    local.get 1
    i32.const 4
    i32.eq
    if  ;; label = @1
      i32.const 1141
      i32.const 6
      call $dynrt_lib_modc_dynString
      return
    end
    local.get 1
    i32.const 7
    i32.eq
    if  ;; label = @1
      i32.const 998
      i32.const 8
      call $dynrt_lib_modc_dynString
      return
    end
    i32.const 1147
    i32.const 6
    call $dynrt_lib_modc_dynString
    return)
  (func $dynrt_lib_modc__fn182 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn174
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn175
    local.set 2
    local.get 2
    i32.const 45
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_lib_modc_global20
        i32.const 1
        i32.add
        global.set $dynrt_lib_modc_global20
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn182
        call $dynrt_lib_modc_dynNeg
        return
      end
    end
    local.get 2
    i32.const 33
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_lib_modc_global20
        i32.const 1
        i32.add
        global.set $dynrt_lib_modc_global20
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn182
        call $dynrt_lib_modc_dynNot
        return
      end
    end
    local.get 2
    i32.const 43
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_lib_modc_global20
        i32.const 1
        i32.add
        global.set $dynrt_lib_modc_global20
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn182
        local.set 2
        local.get 2
        call $dynrt_lib_modc_dynToNumber
        call $dynrt_lib_modc_dynNumber
        return
      end
    end
    local.get 2
    i32.const 116
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_lib_modc_global20
        local.set 3
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn192
        global.get $dynrt_lib_modc_global2
        local.set 4
        global.get $dynrt_lib_modc_global3
        local.set 5
        local.get 4
        local.get 5
        i32.const 1153
        i32.const 6
        call $dynrt_lib_modc__fn169
        i32.const 1
        i32.eq
        if  ;; label = @3
          local.get 0
          local.get 1
          call $dynrt_lib_modc__fn182
          call $dynrt_lib_modc__fn181
          return
        end
        local.get 3
        global.set $dynrt_lib_modc_global20
      end
    end
    local.get 2
    i32.const 97
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_lib_modc_global20
        local.set 3
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn192
        global.get $dynrt_lib_modc_global2
        local.set 4
        global.get $dynrt_lib_modc_global3
        local.set 5
        local.get 4
        local.get 5
        i32.const 1159
        i32.const 5
        call $dynrt_lib_modc__fn169
        i32.const 1
        i32.eq
        if  ;; label = @3
          local.get 0
          local.get 1
          call $dynrt_lib_modc__fn182
          call $dynrt_lib_modc__fn134
          return
        end
        local.get 3
        global.set $dynrt_lib_modc_global20
      end
    end
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn180
    return)
  (func $dynrt_lib_modc__fn183 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn182
    local.set 2
    i32.const 1
    local.set 3
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 3
          i32.const 1
          i32.eq
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn174
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn175
            local.set 4
            local.get 4
            i32.const 42
            i32.eq
            if (result i32)  ;; label = @5
              i32.const 1
            else
              local.get 4
              i32.const 47
              i32.eq
            end
            if (result i32)  ;; label = @5
              i32.const 1
            else
              local.get 4
              i32.const 37
              i32.eq
            end
            if  ;; label = @5
              block  ;; label = @6
                global.get $dynrt_lib_modc_global20
                i32.const 1
                i32.add
                global.set $dynrt_lib_modc_global20
                local.get 2
                call $dynrt_lib_modc__fn61
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn182
                local.set 5
                call $dynrt_lib_modc__fn62
                local.get 4
                i32.const 42
                i32.eq
                if  ;; label = @7
                  local.get 2
                  local.get 5
                  call $dynrt_lib_modc_dynMul
                  local.set 2
                else
                  local.get 4
                  i32.const 47
                  i32.eq
                  if  ;; label = @8
                    local.get 2
                    local.get 5
                    call $dynrt_lib_modc_dynDiv
                    local.set 2
                  else
                    local.get 2
                    local.get 5
                    call $dynrt_lib_modc_dynMod
                    local.set 2
                  end
                end
              end
            else
              i32.const 0
              local.set 3
            end
          end
          br 1 (;@2;)
        end
      end
    end
    local.get 2
    return)
  (func $dynrt_lib_modc__fn184 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn183
    local.set 2
    i32.const 1
    local.set 3
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 3
          i32.const 1
          i32.eq
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn174
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn175
            local.set 4
            local.get 4
            i32.const 43
            i32.eq
            if (result i32)  ;; label = @5
              i32.const 1
            else
              local.get 4
              i32.const 45
              i32.eq
            end
            if  ;; label = @5
              block  ;; label = @6
                global.get $dynrt_lib_modc_global20
                i32.const 1
                i32.add
                global.set $dynrt_lib_modc_global20
                local.get 2
                call $dynrt_lib_modc__fn61
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn183
                local.set 5
                call $dynrt_lib_modc__fn62
                local.get 4
                i32.const 43
                i32.eq
                if  ;; label = @7
                  local.get 2
                  local.get 5
                  call $dynrt_lib_modc_dynAdd
                  local.set 2
                else
                  local.get 2
                  local.get 5
                  call $dynrt_lib_modc_dynSub
                  local.set 2
                end
              end
            else
              i32.const 0
              local.set 3
            end
          end
          br 1 (;@2;)
        end
      end
    end
    local.get 2
    return)
  (func $dynrt_lib_modc__fn185 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn184
    local.set 2
    i32.const 1
    local.set 3
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 3
          i32.const 1
          i32.eq
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn174
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn175
            local.set 4
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn176
            local.set 5
            local.get 4
            i32.const 105
            i32.eq
            if  ;; label = @5
              block  ;; label = @6
                global.get $dynrt_lib_modc_global20
                local.set 4
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn192
                global.get $dynrt_lib_modc_global2
                local.set 5
                global.get $dynrt_lib_modc_global3
                local.set 6
                local.get 5
                local.get 6
                i32.const 1164
                i32.const 10
                call $dynrt_lib_modc__fn169
                i32.const 1
                i32.eq
                if  ;; label = @7
                  block  ;; label = @8
                    local.get 2
                    call $dynrt_lib_modc__fn61
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn184
                    local.set 4
                    call $dynrt_lib_modc__fn62
                    local.get 2
                    local.get 4
                    call $dynrt_lib_modc__fn137
                    call $dynrt_lib_modc_dynBool
                    local.set 2
                  end
                else
                  block  ;; label = @8
                    local.get 4
                    global.set $dynrt_lib_modc_global20
                    i32.const 0
                    local.set 3
                  end
                end
              end
            else
              local.get 4
              i32.const 60
              i32.eq
              if (result i32)  ;; label = @6
                i32.const 1
              else
                local.get 4
                i32.const 62
                i32.eq
              end
              if  ;; label = @6
                block  ;; label = @7
                  local.get 4
                  i32.const 60
                  i32.eq
                  if (result i32)  ;; label = @8
                    i32.const 1
                  else
                    i32.const 0
                  end
                  local.set 6
                  local.get 5
                  i32.const 61
                  i32.eq
                  if (result i32)  ;; label = @8
                    i32.const 1
                  else
                    i32.const 0
                  end
                  local.set 5
                  local.get 5
                  i32.const 1
                  i32.eq
                  if (result i32)  ;; label = @8
                    global.get $dynrt_lib_modc_global20
                    i32.const 2
                    i32.add
                  else
                    global.get $dynrt_lib_modc_global20
                    i32.const 1
                    i32.add
                  end
                  global.set $dynrt_lib_modc_global20
                  local.get 2
                  call $dynrt_lib_modc__fn61
                  local.get 0
                  local.get 1
                  call $dynrt_lib_modc__fn184
                  local.set 4
                  call $dynrt_lib_modc__fn62
                  local.get 6
                  i32.const 1
                  i32.eq
                  if  ;; label = @8
                    local.get 5
                    i32.const 1
                    i32.eq
                    if (result i32)  ;; label = @9
                      local.get 2
                      local.get 4
                      call $dynrt_lib_modc_dynLe
                    else
                      local.get 2
                      local.get 4
                      call $dynrt_lib_modc_dynLt
                    end
                    local.set 2
                  else
                    local.get 5
                    i32.const 1
                    i32.eq
                    if (result i32)  ;; label = @9
                      local.get 2
                      local.get 4
                      call $dynrt_lib_modc_dynGe
                    else
                      local.get 2
                      local.get 4
                      call $dynrt_lib_modc_dynGt
                    end
                    local.set 2
                  end
                end
              else
                i32.const 0
                local.set 3
              end
            end
          end
          br 1 (;@2;)
        end
      end
    end
    local.get 2
    return)
  (func $dynrt_lib_modc__fn186 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn185
    local.set 2
    i32.const 1
    local.set 3
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 3
          i32.const 1
          i32.eq
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn174
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn175
            local.set 4
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn176
            local.set 5
            local.get 4
            i32.const 61
            i32.eq
            if (result i32)  ;; label = @5
              local.get 5
              i32.const 61
              i32.eq
            else
              i32.const 0
            end
            if  ;; label = @5
              block  ;; label = @6
                global.get $dynrt_lib_modc_global20
                i32.const 2
                i32.add
                global.set $dynrt_lib_modc_global20
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn175
                i32.const 61
                i32.eq
                if  ;; label = @7
                  global.get $dynrt_lib_modc_global20
                  i32.const 1
                  i32.add
                  global.set $dynrt_lib_modc_global20
                end
                local.get 2
                call $dynrt_lib_modc__fn61
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn185
                local.set 4
                call $dynrt_lib_modc__fn62
                local.get 2
                local.get 4
                call $dynrt_lib_modc_dynStrictEq
                call $dynrt_lib_modc_dynBool
                local.set 2
              end
            else
              local.get 4
              i32.const 33
              i32.eq
              if (result i32)  ;; label = @6
                local.get 5
                i32.const 61
                i32.eq
              else
                i32.const 0
              end
              if  ;; label = @6
                block  ;; label = @7
                  global.get $dynrt_lib_modc_global20
                  i32.const 2
                  i32.add
                  global.set $dynrt_lib_modc_global20
                  local.get 0
                  local.get 1
                  call $dynrt_lib_modc__fn175
                  i32.const 61
                  i32.eq
                  if  ;; label = @8
                    global.get $dynrt_lib_modc_global20
                    i32.const 1
                    i32.add
                    global.set $dynrt_lib_modc_global20
                  end
                  local.get 2
                  call $dynrt_lib_modc__fn61
                  local.get 0
                  local.get 1
                  call $dynrt_lib_modc__fn185
                  local.set 4
                  call $dynrt_lib_modc__fn62
                  local.get 2
                  local.get 4
                  call $dynrt_lib_modc_dynStrictEq
                  i32.eqz
                  if (result i32)  ;; label = @8
                    i32.const 1
                  else
                    i32.const 0
                  end
                  call $dynrt_lib_modc_dynBool
                  local.set 2
                end
              else
                i32.const 0
                local.set 3
              end
            end
          end
          br 1 (;@2;)
        end
      end
    end
    local.get 2
    return)
  (func $dynrt_lib_modc__fn187 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn186
    local.set 2
    i32.const 1
    local.set 3
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 3
          i32.const 1
          i32.eq
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn174
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn175
            i32.const 38
            i32.eq
            if (result i32)  ;; label = @5
              local.get 0
              local.get 1
              call $dynrt_lib_modc__fn176
              i32.const 38
              i32.eq
            else
              i32.const 0
            end
            if  ;; label = @5
              block  ;; label = @6
                global.get $dynrt_lib_modc_global20
                i32.const 2
                i32.add
                global.set $dynrt_lib_modc_global20
                local.get 2
                call $dynrt_lib_modc_dynToBool
                local.set 4
                global.get $dynrt_lib_modc_global22
                local.set 5
                local.get 4
                i32.eqz
                if  ;; label = @7
                  i32.const 0
                  global.set $dynrt_lib_modc_global22
                end
                local.get 2
                call $dynrt_lib_modc__fn61
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn186
                local.set 6
                call $dynrt_lib_modc__fn62
                local.get 5
                global.set $dynrt_lib_modc_global22
                local.get 4
                i32.const 1
                i32.eq
                if  ;; label = @7
                  local.get 6
                  local.set 2
                end
              end
            else
              i32.const 0
              local.set 3
            end
          end
          br 1 (;@2;)
        end
      end
    end
    local.get 2
    return)
  (func $dynrt_lib_modc__fn188 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn187
    local.set 2
    i32.const 1
    local.set 3
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 3
          i32.const 1
          i32.eq
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn174
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn175
            i32.const 124
            i32.eq
            if (result i32)  ;; label = @5
              local.get 0
              local.get 1
              call $dynrt_lib_modc__fn176
              i32.const 124
              i32.eq
            else
              i32.const 0
            end
            if  ;; label = @5
              block  ;; label = @6
                global.get $dynrt_lib_modc_global20
                i32.const 2
                i32.add
                global.set $dynrt_lib_modc_global20
                local.get 2
                call $dynrt_lib_modc_dynToBool
                local.set 4
                global.get $dynrt_lib_modc_global22
                local.set 5
                local.get 4
                i32.const 1
                i32.eq
                if  ;; label = @7
                  i32.const 0
                  global.set $dynrt_lib_modc_global22
                end
                local.get 2
                call $dynrt_lib_modc__fn61
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn187
                local.set 6
                call $dynrt_lib_modc__fn62
                local.get 5
                global.set $dynrt_lib_modc_global22
                local.get 4
                i32.eqz
                if  ;; label = @7
                  local.get 6
                  local.set 2
                end
              end
            else
              local.get 0
              local.get 1
              call $dynrt_lib_modc__fn175
              i32.const 63
              i32.eq
              if (result i32)  ;; label = @6
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn176
                i32.const 63
                i32.eq
              else
                i32.const 0
              end
              if  ;; label = @6
                block  ;; label = @7
                  global.get $dynrt_lib_modc_global20
                  i32.const 2
                  i32.add
                  global.set $dynrt_lib_modc_global20
                  local.get 2
                  local.tee 7
                  local.set 4
                  local.get 4
                  i32.const 8
                  i32.add
                  i32.load
                  local.set 4
                  local.get 4
                  i32.eqz
                  if (result i32)  ;; label = @8
                    i32.const 1
                  else
                    local.get 4
                    i32.const 1
                    i32.eq
                  end
                  if (result i32)  ;; label = @8
                    i32.const 1
                  else
                    i32.const 0
                  end
                  local.set 4
                  global.get $dynrt_lib_modc_global22
                  local.set 5
                  local.get 4
                  i32.eqz
                  if  ;; label = @8
                    i32.const 0
                    global.set $dynrt_lib_modc_global22
                  end
                  local.get 2
                  call $dynrt_lib_modc__fn61
                  local.get 0
                  local.get 1
                  call $dynrt_lib_modc__fn187
                  local.set 6
                  call $dynrt_lib_modc__fn62
                  local.get 5
                  global.set $dynrt_lib_modc_global22
                  local.get 4
                  i32.const 1
                  i32.eq
                  if  ;; label = @8
                    local.get 6
                    local.set 2
                  end
                end
              else
                i32.const 0
                local.set 3
              end
            end
          end
          br 1 (;@2;)
        end
      end
    end
    local.get 2
    return)
  (func $dynrt_lib_modc__fn189 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn188
    local.set 2
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn174
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn175
    i32.const 63
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_lib_modc_global20
        i32.const 1
        i32.add
        global.set $dynrt_lib_modc_global20
        local.get 2
        call $dynrt_lib_modc_dynToBool
        local.set 2
        global.get $dynrt_lib_modc_global22
        local.set 3
        local.get 2
        i32.eqz
        if  ;; label = @3
          i32.const 0
          global.set $dynrt_lib_modc_global22
        end
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn189
        local.set 4
        local.get 3
        local.tee 6
        global.set $dynrt_lib_modc_global22
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn174
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn175
        i32.const 58
        i32.eq
        if  ;; label = @3
          global.get $dynrt_lib_modc_global20
          i32.const 1
          i32.add
          global.set $dynrt_lib_modc_global20
        end
        local.get 2
        i32.const 1
        i32.eq
        if  ;; label = @3
          i32.const 0
          global.set $dynrt_lib_modc_global22
        end
        local.get 4
        call $dynrt_lib_modc__fn61
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn189
        local.set 5
        call $dynrt_lib_modc__fn62
        local.get 3
        local.tee 7
        global.set $dynrt_lib_modc_global22
        local.get 2
        i32.const 1
        i32.eq
        if (result i32)  ;; label = @3
          local.get 4
        else
          local.get 5
        end
        return
      end
    end
    local.get 2
    return)
  (func $dynrt_lib_modc_dynEval (param i32 i32) (result i32)
    i32.const 0
    global.set $dynrt_lib_modc_global20
    i32.const -1
    global.set $dynrt_lib_modc_global21
    i32.const 1
    global.set $dynrt_lib_modc_global22
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn189
    return)
  (func $dynrt_lib_modc_dynEvalEnv (param i32 i32 i32) (result i32)
    i32.const 0
    global.set $dynrt_lib_modc_global20
    local.get 2
    global.set $dynrt_lib_modc_global21
    i32.const 1
    global.set $dynrt_lib_modc_global22
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn189
    return)
  (func $dynrt_lib_modc__fn192 (param i32 i32)
    (local i32) (local i32) (local i32) (local i32)
    global.get $dynrt_lib_modc_global20
    local.tee 4
    local.set 2
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn175
    local.set 3
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 3
          i32.const 1
          call $dynrt_lib_modc__fn173
          i32.const 1
          i32.eq
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            global.get $dynrt_lib_modc_global20
            i32.const 1
            i32.add
            global.set $dynrt_lib_modc_global20
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn175
            local.set 3
          end
          br 1 (;@2;)
        end
      end
    end
    local.get 0
    local.get 1
    local.get 2
    global.get $dynrt_lib_modc_global20
    call $dynrt_lib_modc__fn6
    local.set 3
    nop
    local.set 2
    local.get 2
    local.tee 5
    global.set $dynrt_lib_modc_global2
    local.get 3
    global.set $dynrt_lib_modc_global3
    return)
  (func $dynrt_lib_modc__fn193 (param i32 i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn174
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn175
    local.set 2
    local.get 2
    i32.const 91
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_lib_modc_global20
        i32.const 1
        local.tee 14
        i32.add
        global.set $dynrt_lib_modc_global20
        call $dynrt_lib_modc_dynArray
        local.set 2
        i32.const 1
        local.tee 15
        local.set 3
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 3
              i32.const 1
              i32.eq
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn174
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn175
                local.set 4
                local.get 4
                i32.const 93
                i32.eq
                if (result i32)  ;; label = @7
                  i32.const 1
                else
                  local.get 4
                  i32.const -1
                  i32.eq
                end
                if  ;; label = @7
                  i32.const 0
                  local.set 3
                else
                  local.get 4
                  i32.const 44
                  i32.eq
                  if  ;; label = @8
                    block  ;; label = @9
                      local.get 2
                      i32.const 520
                      i32.const 0
                      call $dynrt_lib_modc_dynString
                      call $dynrt_lib_modc_dynPush
                      global.get $dynrt_lib_modc_global20
                      i32.const 1
                      i32.add
                      global.set $dynrt_lib_modc_global20
                    end
                  else
                    block  ;; label = @9
                      local.get 0
                      local.get 1
                      call $dynrt_lib_modc__fn192
                      local.get 2
                      global.get $dynrt_lib_modc_global2
                      global.get $dynrt_lib_modc_global3
                      call $dynrt_lib_modc_dynString
                      call $dynrt_lib_modc_dynPush
                      local.get 0
                      local.get 1
                      call $dynrt_lib_modc__fn174
                      local.get 0
                      local.get 1
                      call $dynrt_lib_modc__fn175
                      i32.const 44
                      i32.eq
                      if  ;; label = @10
                        global.get $dynrt_lib_modc_global20
                        i32.const 1
                        i32.add
                        global.set $dynrt_lib_modc_global20
                      end
                    end
                  end
                end
              end
              br 1 (;@4;)
            end
          end
        end
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn175
        i32.const 93
        i32.eq
        if  ;; label = @3
          global.get $dynrt_lib_modc_global20
          i32.const 1
          i32.add
          global.set $dynrt_lib_modc_global20
        end
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn174
        call $dynrt_lib_modc_dynUndefined
        local.set 3
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn175
        i32.const 61
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            global.get $dynrt_lib_modc_global20
            i32.const 1
            i32.add
            global.set $dynrt_lib_modc_global20
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn189
            local.set 3
          end
        end
        global.get $dynrt_lib_modc_global22
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 3
            local.set 4
            i32.const 0
            local.tee 12
            local.set 5
            local.get 4
            i32.const 8
            i32.add
            i32.load
            i32.const 5
            i32.eq
            if  ;; label = @5
              local.get 3
              call $dynrt_lib_modc_dynArrLen
              local.set 5
            end
            local.get 2
            call $dynrt_lib_modc_dynArrLen
            local.set 4
            i32.const 0
            local.tee 13
            local.set 6
            block  ;; label = @5
              loop  ;; label = @6
                block  ;; label = @7
                  local.get 6
                  local.get 4
                  i32.lt_s
                  i32.eqz
                  br_if 2 (;@5;)
                  block  ;; label = @8
                    local.get 2
                    local.get 6
                    call $dynrt_lib_modc_dynArrGet
                    call $dynrt_lib_modc__fn85
                    global.get $dynrt_lib_modc_global2
                    local.set 7
                    global.get $dynrt_lib_modc_global3
                    local.set 8
                    local.get 8
                    i32.const 0
                    i32.gt_s
                    if  ;; label = @9
                      block  ;; label = @10
                        call $dynrt_lib_modc_dynUndefined
                        local.set 9
                        local.get 6
                        local.get 5
                        i32.lt_s
                        if  ;; label = @11
                          local.get 3
                          local.get 6
                          call $dynrt_lib_modc_dynArrGet
                          local.set 9
                        end
                        global.get $dynrt_lib_modc_global21
                        local.get 7
                        local.get 8
                        local.get 9
                        call $dynrt_lib_modc_dynSet
                      end
                    end
                    local.get 6
                    local.tee 11
                    i32.const 1
                    i32.add
                    local.set 6
                  end
                  br 1 (;@6;)
                end
              end
            end
          end
        end
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn174
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn175
        i32.const 59
        i32.eq
        if  ;; label = @3
          global.get $dynrt_lib_modc_global20
          i32.const 1
          i32.add
          global.set $dynrt_lib_modc_global20
        end
        return
      end
    end
    local.get 2
    i32.const 123
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_lib_modc_global20
        i32.const 1
        local.tee 23
        i32.add
        global.set $dynrt_lib_modc_global20
        call $dynrt_lib_modc_dynArray
        local.set 2
        call $dynrt_lib_modc_dynArray
        local.set 5
        i32.const 1
        local.tee 24
        local.set 3
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 3
              i32.const 1
              i32.eq
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn174
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn175
                local.set 4
                local.get 4
                i32.const 125
                i32.eq
                if (result i32)  ;; label = @7
                  i32.const 1
                else
                  local.get 4
                  i32.const -1
                  i32.eq
                end
                if  ;; label = @7
                  i32.const 0
                  local.set 3
                else
                  local.get 4
                  i32.const 44
                  i32.eq
                  if  ;; label = @8
                    global.get $dynrt_lib_modc_global20
                    i32.const 1
                    i32.add
                    global.set $dynrt_lib_modc_global20
                  else
                    block  ;; label = @9
                      local.get 0
                      local.get 1
                      call $dynrt_lib_modc__fn192
                      global.get $dynrt_lib_modc_global2
                      local.set 4
                      global.get $dynrt_lib_modc_global3
                      local.set 6
                      local.get 4
                      local.tee 16
                      local.set 7
                      local.get 6
                      local.tee 17
                      local.set 8
                      local.get 0
                      local.get 1
                      call $dynrt_lib_modc__fn174
                      local.get 0
                      local.get 1
                      call $dynrt_lib_modc__fn175
                      i32.const 58
                      i32.eq
                      if  ;; label = @10
                        block  ;; label = @11
                          global.get $dynrt_lib_modc_global20
                          i32.const 1
                          i32.add
                          global.set $dynrt_lib_modc_global20
                          local.get 0
                          local.get 1
                          call $dynrt_lib_modc__fn174
                          local.get 0
                          local.get 1
                          call $dynrt_lib_modc__fn192
                          global.get $dynrt_lib_modc_global2
                          local.set 7
                          global.get $dynrt_lib_modc_global3
                          local.set 8
                        end
                      end
                      local.get 2
                      local.get 4
                      local.get 6
                      call $dynrt_lib_modc_dynString
                      call $dynrt_lib_modc_dynPush
                      local.get 5
                      local.get 7
                      local.get 8
                      call $dynrt_lib_modc_dynString
                      call $dynrt_lib_modc_dynPush
                      local.get 0
                      local.get 1
                      call $dynrt_lib_modc__fn174
                      local.get 0
                      local.get 1
                      call $dynrt_lib_modc__fn175
                      i32.const 44
                      i32.eq
                      if  ;; label = @10
                        global.get $dynrt_lib_modc_global20
                        i32.const 1
                        i32.add
                        global.set $dynrt_lib_modc_global20
                      end
                    end
                  end
                end
              end
              br 1 (;@4;)
            end
          end
        end
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn175
        i32.const 125
        i32.eq
        if  ;; label = @3
          global.get $dynrt_lib_modc_global20
          i32.const 1
          i32.add
          global.set $dynrt_lib_modc_global20
        end
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn174
        call $dynrt_lib_modc_dynUndefined
        local.set 3
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn175
        i32.const 61
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            global.get $dynrt_lib_modc_global20
            i32.const 1
            i32.add
            global.set $dynrt_lib_modc_global20
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn189
            local.set 3
          end
        end
        global.get $dynrt_lib_modc_global22
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 2
            call $dynrt_lib_modc_dynArrLen
            local.set 4
            i32.const 0
            local.set 6
            block  ;; label = @5
              loop  ;; label = @6
                block  ;; label = @7
                  local.get 6
                  local.get 4
                  i32.lt_s
                  i32.eqz
                  br_if 2 (;@5;)
                  block  ;; label = @8
                    local.get 2
                    local.get 6
                    call $dynrt_lib_modc_dynArrGet
                    call $dynrt_lib_modc__fn85
                    global.get $dynrt_lib_modc_global2
                    local.tee 18
                    local.set 7
                    global.get $dynrt_lib_modc_global3
                    local.tee 19
                    local.set 8
                    local.get 5
                    local.get 6
                    call $dynrt_lib_modc_dynArrGet
                    call $dynrt_lib_modc__fn85
                    global.get $dynrt_lib_modc_global2
                    local.tee 20
                    local.set 9
                    global.get $dynrt_lib_modc_global3
                    local.tee 21
                    local.set 10
                    global.get $dynrt_lib_modc_global21
                    local.get 9
                    local.get 10
                    local.get 3
                    local.get 7
                    local.get 8
                    call $dynrt_lib_modc_dynMember
                    call $dynrt_lib_modc_dynSet
                    local.get 6
                    local.tee 22
                    i32.const 1
                    i32.add
                    local.set 6
                  end
                  br 1 (;@6;)
                end
              end
            end
          end
        end
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn174
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn175
        i32.const 59
        i32.eq
        if  ;; label = @3
          global.get $dynrt_lib_modc_global20
          i32.const 1
          i32.add
          global.set $dynrt_lib_modc_global20
        end
        return
      end
    end
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn192
    global.get $dynrt_lib_modc_global2
    local.set 2
    global.get $dynrt_lib_modc_global3
    local.set 3
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn174
    call $dynrt_lib_modc_dynUndefined
    local.set 4
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn175
    i32.const 61
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_lib_modc_global20
        i32.const 1
        i32.add
        global.set $dynrt_lib_modc_global20
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn189
        local.set 4
      end
    end
    global.get $dynrt_lib_modc_global22
    i32.const 1
    i32.eq
    if  ;; label = @1
      global.get $dynrt_lib_modc_global21
      local.get 2
      local.get 3
      local.get 4
      call $dynrt_lib_modc_dynSet
    end
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn174
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn175
    i32.const 59
    i32.eq
    if  ;; label = @1
      global.get $dynrt_lib_modc_global20
      i32.const 1
      i32.add
      global.set $dynrt_lib_modc_global20
    end)
  (func $dynrt_lib_modc__fn194 (param i32 i32)
    (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn174
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn175
    local.set 2
    call $dynrt_lib_modc_dynUndefined
    local.set 3
    local.get 2
    i32.const 59
    i32.ne
    if (result i32)  ;; label = @1
      local.get 2
      i32.const 125
      i32.ne
    else
      i32.const 0
    end
    if (result i32)  ;; label = @1
      local.get 2
      i32.const -1
      i32.ne
    else
      i32.const 0
    end
    if  ;; label = @1
      local.get 0
      local.get 1
      call $dynrt_lib_modc__fn189
      local.set 3
    end
    global.get $dynrt_lib_modc_global22
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 3
        global.set $dynrt_lib_modc_global25
        i32.const 1
        global.set $dynrt_lib_modc_global24
      end
    end
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn174
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn175
    i32.const 59
    i32.eq
    if  ;; label = @1
      global.get $dynrt_lib_modc_global20
      i32.const 1
      i32.add
      global.set $dynrt_lib_modc_global20
    end)
  (func $dynrt_lib_modc__fn195 (param i32 i32)
    (local i32) (local i32) (local i32) (local i32) (local i32)
    global.get $dynrt_lib_modc_global22
    local.set 2
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn174
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn175
    i32.const 40
    i32.eq
    if  ;; label = @1
      global.get $dynrt_lib_modc_global20
      i32.const 1
      i32.add
      global.set $dynrt_lib_modc_global20
    end
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn189
    local.set 3
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn174
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn175
    i32.const 41
    i32.eq
    if  ;; label = @1
      global.get $dynrt_lib_modc_global20
      i32.const 1
      i32.add
      global.set $dynrt_lib_modc_global20
    end
    local.get 2
    i32.const 1
    i32.eq
    if (result i32)  ;; label = @1
      local.get 3
      call $dynrt_lib_modc_dynToBool
      i32.const 1
      i32.eq
    else
      i32.const 0
    end
    if (result i32)  ;; label = @1
      i32.const 1
    else
      i32.const 0
    end
    local.set 3
    local.get 2
    i32.const 1
    i32.eq
    if (result i32)  ;; label = @1
      local.get 3
      i32.const 1
      i32.eq
    else
      i32.const 0
    end
    if (result i32)  ;; label = @1
      i32.const 1
    else
      i32.const 0
    end
    global.set $dynrt_lib_modc_global22
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn215
    local.get 2
    global.set $dynrt_lib_modc_global22
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn174
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn175
    i32.const 0
    call $dynrt_lib_modc__fn173
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_lib_modc_global20
        local.set 4
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn192
        global.get $dynrt_lib_modc_global2
        local.set 5
        global.get $dynrt_lib_modc_global3
        local.set 6
        local.get 5
        local.get 6
        i32.const 1174
        i32.const 4
        call $dynrt_lib_modc__fn169
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 2
            i32.const 1
            i32.eq
            if (result i32)  ;; label = @5
              local.get 3
              i32.eqz
            else
              i32.const 0
            end
            if (result i32)  ;; label = @5
              i32.const 1
            else
              i32.const 0
            end
            global.set $dynrt_lib_modc_global22
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn215
            local.get 2
            global.set $dynrt_lib_modc_global22
          end
        else
          local.get 4
          global.set $dynrt_lib_modc_global20
        end
      end
    end)
  (func $dynrt_lib_modc__fn196 (param i32 i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    global.get $dynrt_lib_modc_global22
    local.set 2
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn174
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn175
    i32.const 40
    i32.eq
    if  ;; label = @1
      global.get $dynrt_lib_modc_global20
      i32.const 1
      i32.add
      global.set $dynrt_lib_modc_global20
    end
    global.get $dynrt_lib_modc_global20
    local.set 3
    i32.const 1
    local.set 4
    i32.const 0
    local.set 5
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 4
          i32.const 1
          i32.eq
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 3
            global.set $dynrt_lib_modc_global20
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn189
            local.set 6
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn174
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn175
            i32.const 41
            i32.eq
            if  ;; label = @5
              global.get $dynrt_lib_modc_global20
              i32.const 1
              i32.add
              global.set $dynrt_lib_modc_global20
            end
            local.get 2
            i32.const 1
            i32.eq
            if (result i32)  ;; label = @5
              local.get 6
              call $dynrt_lib_modc_dynToBool
              i32.const 1
              i32.eq
            else
              i32.const 0
            end
            if (result i32)  ;; label = @5
              i32.const 1
            else
              i32.const 0
            end
            local.set 6
            local.get 6
            i32.const 1
            i32.eq
            if  ;; label = @5
              block  ;; label = @6
                i32.const 1
                local.tee 9
                global.set $dynrt_lib_modc_global22
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn215
                local.get 2
                global.set $dynrt_lib_modc_global22
                global.get $dynrt_lib_modc_global24
                i32.const 1
                i32.eq
                if (result i32)  ;; label = @7
                  i32.const 1
                else
                  global.get $dynrt_lib_modc_global29
                  i32.const 1
                  i32.eq
                end
                if  ;; label = @7
                  i32.const 0
                  local.set 4
                else
                  global.get $dynrt_lib_modc_global27
                  i32.const 1
                  i32.eq
                  if  ;; label = @8
                    block  ;; label = @9
                      i32.const 0
                      local.tee 7
                      global.set $dynrt_lib_modc_global27
                      i32.const 0
                      local.tee 8
                      local.set 4
                    end
                  else
                    global.get $dynrt_lib_modc_global28
                    i32.const 1
                    i32.eq
                    if  ;; label = @9
                      i32.const 0
                      global.set $dynrt_lib_modc_global28
                    end
                  end
                end
                local.get 5
                i32.const 1
                local.tee 10
                i32.add
                local.set 5
                local.get 5
                i32.const 100000000
                i32.gt_s
                if  ;; label = @7
                  i32.const 0
                  local.set 4
                end
              end
            else
              block  ;; label = @6
                i32.const 0
                local.tee 11
                global.set $dynrt_lib_modc_global22
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn215
                local.get 2
                global.set $dynrt_lib_modc_global22
                i32.const 0
                local.tee 12
                local.set 4
              end
            end
          end
          br 1 (;@2;)
        end
      end
    end)
  (func $dynrt_lib_modc__fn197 (param i32 i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    global.get $dynrt_lib_modc_global22
    local.set 2
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn174
    global.get $dynrt_lib_modc_global20
    local.set 3
    i32.const 1
    local.set 4
    i32.const 0
    local.set 5
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 4
          i32.const 1
          i32.eq
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 3
            global.set $dynrt_lib_modc_global20
            local.get 2
            local.tee 8
            global.set $dynrt_lib_modc_global22
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn215
            local.get 2
            local.tee 9
            global.set $dynrt_lib_modc_global22
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn174
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn175
            i32.const 0
            call $dynrt_lib_modc__fn173
            i32.const 1
            i32.eq
            if  ;; label = @5
              local.get 0
              local.get 1
              call $dynrt_lib_modc__fn192
            end
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn174
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn175
            i32.const 40
            i32.eq
            if  ;; label = @5
              global.get $dynrt_lib_modc_global20
              i32.const 1
              i32.add
              global.set $dynrt_lib_modc_global20
            end
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn189
            local.set 4
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn174
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn175
            i32.const 41
            i32.eq
            if  ;; label = @5
              global.get $dynrt_lib_modc_global20
              i32.const 1
              i32.add
              global.set $dynrt_lib_modc_global20
            end
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn174
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn175
            i32.const 59
            i32.eq
            if  ;; label = @5
              global.get $dynrt_lib_modc_global20
              i32.const 1
              i32.add
              global.set $dynrt_lib_modc_global20
            end
            local.get 2
            i32.eqz
            if  ;; label = @5
              i32.const 0
              local.set 4
            else
              global.get $dynrt_lib_modc_global24
              i32.const 1
              i32.eq
              if (result i32)  ;; label = @6
                i32.const 1
              else
                global.get $dynrt_lib_modc_global29
                i32.const 1
                i32.eq
              end
              if  ;; label = @6
                i32.const 0
                local.set 4
              else
                global.get $dynrt_lib_modc_global27
                i32.const 1
                i32.eq
                if  ;; label = @7
                  block  ;; label = @8
                    i32.const 0
                    local.tee 6
                    global.set $dynrt_lib_modc_global27
                    i32.const 0
                    local.tee 7
                    local.set 4
                  end
                else
                  block  ;; label = @8
                    global.get $dynrt_lib_modc_global28
                    i32.const 1
                    i32.eq
                    if  ;; label = @9
                      i32.const 0
                      global.set $dynrt_lib_modc_global28
                    end
                    local.get 4
                    call $dynrt_lib_modc_dynToBool
                    i32.const 1
                    i32.eq
                    if (result i32)  ;; label = @9
                      i32.const 1
                    else
                      i32.const 0
                    end
                    local.set 4
                  end
                end
              end
            end
            local.get 5
            i32.const 1
            i32.add
            local.set 5
            local.get 5
            i32.const 100000000
            i32.gt_s
            if  ;; label = @5
              i32.const 0
              local.set 4
            end
          end
          br 1 (;@2;)
        end
      end
    end)
  (func $dynrt_lib_modc__fn198 (param i32 i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    global.get $dynrt_lib_modc_global22
    local.set 2
    global.get $dynrt_lib_modc_global21
    local.set 3
    local.get 3
    call $dynrt_lib_modc__fn157
    local.set 4
    local.get 4
    local.tee 13
    global.set $dynrt_lib_modc_global21
    local.get 4
    call $dynrt_lib_modc__fn61
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn174
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn175
    i32.const 40
    i32.eq
    if  ;; label = @1
      global.get $dynrt_lib_modc_global20
      i32.const 1
      i32.add
      global.set $dynrt_lib_modc_global20
    end
    global.get $dynrt_lib_modc_global20
    local.set 4
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn174
    i32.const 0
    local.tee 14
    local.set 5
    i32.const 520
    local.set 6
    local.get 14
    local.set 7
    local.get 14
    local.set 8
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn175
    i32.const 0
    call $dynrt_lib_modc__fn173
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn192
        global.get $dynrt_lib_modc_global2
        local.set 9
        global.get $dynrt_lib_modc_global3
        local.set 10
        local.get 9
        local.set 11
        local.get 10
        local.set 12
        local.get 9
        local.get 10
        i32.const 1178
        i32.const 5
        call $dynrt_lib_modc__fn169
        i32.const 1
        i32.eq
        if (result i32)  ;; label = @3
          i32.const 1
        else
          local.get 9
          local.get 10
          i32.const 1183
          i32.const 3
          call $dynrt_lib_modc__fn169
          i32.const 1
          i32.eq
        end
        if (result i32)  ;; label = @3
          i32.const 1
        else
          local.get 9
          local.get 10
          i32.const 1186
          i32.const 3
          call $dynrt_lib_modc__fn169
          i32.const 1
          i32.eq
        end
        if  ;; label = @3
          block  ;; label = @4
            local.get 9
            local.get 10
            i32.const 1186
            i32.const 3
            call $dynrt_lib_modc__fn169
            i32.const 1
            i32.ne
            if  ;; label = @5
              i32.const 1
              local.set 8
            end
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn174
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn192
            global.get $dynrt_lib_modc_global2
            local.set 11
            global.get $dynrt_lib_modc_global3
            local.set 12
          end
        end
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn174
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn175
        i32.const 0
        call $dynrt_lib_modc__fn173
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn192
            global.get $dynrt_lib_modc_global2
            local.set 9
            global.get $dynrt_lib_modc_global3
            local.set 10
            local.get 9
            local.get 10
            i32.const 1189
            i32.const 2
            call $dynrt_lib_modc__fn169
            i32.const 1
            i32.eq
            if  ;; label = @5
              block  ;; label = @6
                i32.const 1
                local.set 5
                local.get 11
                local.set 6
                local.get 12
                local.set 7
              end
            else
              local.get 9
              local.get 10
              i32.const 1191
              i32.const 2
              call $dynrt_lib_modc__fn169
              i32.const 1
              i32.eq
              if  ;; label = @6
                block  ;; label = @7
                  i32.const 2
                  local.set 5
                  local.get 11
                  local.set 6
                  local.get 12
                  local.set 7
                end
              end
            end
          end
        end
      end
    end
    local.get 5
    i32.const 1
    i32.eq
    if  ;; label = @1
      local.get 0
      local.get 1
      local.get 6
      local.get 7
      local.get 2
      local.get 8
      call $dynrt_lib_modc__fn200
    else
      local.get 5
      i32.const 2
      i32.eq
      if  ;; label = @2
        local.get 0
        local.get 1
        local.get 6
        local.get 7
        local.get 2
        local.get 8
        call $dynrt_lib_modc__fn199
      else
        block  ;; label = @3
          local.get 4
          global.set $dynrt_lib_modc_global20
          local.get 0
          local.get 1
          local.get 2
          local.get 8
          call $dynrt_lib_modc__fn201
        end
      end
    end
    call $dynrt_lib_modc__fn62
    local.get 3
    local.tee 15
    global.set $dynrt_lib_modc_global21)
  (func $dynrt_lib_modc__fn199 (param i32 i32 i32 i32 i32 i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    global.get $dynrt_lib_modc_global21
    local.set 6
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn189
    local.set 7
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn174
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn175
    i32.const 41
    i32.eq
    if  ;; label = @1
      global.get $dynrt_lib_modc_global20
      i32.const 1
      i32.add
      global.set $dynrt_lib_modc_global20
    end
    global.get $dynrt_lib_modc_global20
    local.set 8
    i32.const 0
    local.tee 18
    local.set 9
    local.get 7
    local.set 10
    local.get 4
    i32.const 1
    i32.eq
    if (result i32)  ;; label = @1
      local.get 10
      i32.const 8
      i32.add
      i32.load
      i32.const 6
      i32.eq
    else
      i32.const 0
    end
    if  ;; label = @1
      local.get 7
      call $dynrt_lib_modc_dynObjLen
      local.set 9
    end
    local.get 4
    i32.const 1
    i32.eq
    if (result i32)  ;; label = @1
      local.get 9
      i32.const 0
      i32.gt_s
    else
      i32.const 0
    end
    if (result i32)  ;; label = @1
      i32.const 1
    else
      i32.const 0
    end
    local.set 10
    local.get 10
    i32.eqz
    if  ;; label = @1
      block  ;; label = @2
        i32.const 0
        global.set $dynrt_lib_modc_global22
        local.get 8
        global.set $dynrt_lib_modc_global20
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn215
        local.get 4
        global.set $dynrt_lib_modc_global22
        return
      end
    end
    i32.const 0
    local.tee 19
    local.set 11
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 10
          i32.const 1
          i32.eq
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 6
            local.tee 15
            local.set 12
            local.get 5
            i32.const 1
            i32.eq
            if  ;; label = @5
              local.get 6
              call $dynrt_lib_modc__fn157
              local.set 12
            end
            local.get 12
            local.get 2
            local.get 3
            local.get 7
            local.get 11
            call $dynrt_lib_modc__fn95
            call $dynrt_lib_modc_dynSet
            local.get 12
            local.tee 16
            global.set $dynrt_lib_modc_global21
            local.get 8
            global.set $dynrt_lib_modc_global20
            i32.const 1
            global.set $dynrt_lib_modc_global22
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn215
            local.get 4
            global.set $dynrt_lib_modc_global22
            local.get 6
            local.tee 17
            global.set $dynrt_lib_modc_global21
            global.get $dynrt_lib_modc_global24
            i32.const 1
            i32.eq
            if (result i32)  ;; label = @5
              i32.const 1
            else
              global.get $dynrt_lib_modc_global29
              i32.const 1
              i32.eq
            end
            if  ;; label = @5
              i32.const 0
              local.set 10
            else
              global.get $dynrt_lib_modc_global27
              i32.const 1
              i32.eq
              if  ;; label = @6
                block  ;; label = @7
                  i32.const 0
                  local.tee 13
                  global.set $dynrt_lib_modc_global27
                  i32.const 0
                  local.tee 14
                  local.set 10
                end
              else
                block  ;; label = @7
                  global.get $dynrt_lib_modc_global28
                  i32.const 1
                  i32.eq
                  if  ;; label = @8
                    i32.const 0
                    global.set $dynrt_lib_modc_global28
                  end
                  local.get 11
                  i32.const 1
                  i32.add
                  local.set 11
                  local.get 11
                  local.get 9
                  i32.ge_s
                  if  ;; label = @8
                    i32.const 0
                    local.set 10
                  end
                end
              end
            end
          end
          br 1 (;@2;)
        end
      end
    end)
  (func $dynrt_lib_modc__fn200 (param i32 i32 i32 i32 i32 i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    global.get $dynrt_lib_modc_global21
    local.set 6
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn189
    local.set 7
    local.get 7
    local.tee 18
    local.set 8
    local.get 8
    i32.const 8
    i32.add
    i32.load
    i32.const 6
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 7
        i32.const 890
        i32.const 6
        call $dynrt_lib_modc_dynGet
        local.set 8
        local.get 8
        i32.const -1
        i32.ne
        if  ;; label = @3
          local.get 8
          local.set 7
        end
      end
    end
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn174
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn175
    i32.const 41
    i32.eq
    if  ;; label = @1
      global.get $dynrt_lib_modc_global20
      i32.const 1
      i32.add
      global.set $dynrt_lib_modc_global20
    end
    global.get $dynrt_lib_modc_global20
    local.set 8
    i32.const 0
    local.tee 19
    local.set 9
    local.get 7
    local.tee 20
    local.set 10
    local.get 4
    i32.const 1
    i32.eq
    if (result i32)  ;; label = @1
      local.get 10
      i32.const 8
      i32.add
      i32.load
      i32.const 5
      i32.eq
    else
      i32.const 0
    end
    if  ;; label = @1
      local.get 7
      call $dynrt_lib_modc_dynArrLen
      local.set 9
    end
    local.get 4
    i32.const 1
    i32.eq
    if (result i32)  ;; label = @1
      local.get 9
      i32.const 0
      i32.gt_s
    else
      i32.const 0
    end
    if (result i32)  ;; label = @1
      i32.const 1
    else
      i32.const 0
    end
    local.set 10
    local.get 10
    i32.eqz
    if  ;; label = @1
      block  ;; label = @2
        i32.const 0
        global.set $dynrt_lib_modc_global22
        local.get 8
        global.set $dynrt_lib_modc_global20
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn215
        local.get 4
        global.set $dynrt_lib_modc_global22
        return
      end
    end
    i32.const 0
    local.tee 21
    local.set 11
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 10
          i32.const 1
          i32.eq
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 6
            local.tee 15
            local.set 12
            local.get 5
            i32.const 1
            i32.eq
            if  ;; label = @5
              local.get 6
              call $dynrt_lib_modc__fn157
              local.set 12
            end
            local.get 12
            local.get 2
            local.get 3
            local.get 7
            local.get 11
            call $dynrt_lib_modc_dynArrGet
            call $dynrt_lib_modc_dynSet
            local.get 12
            local.tee 16
            global.set $dynrt_lib_modc_global21
            local.get 8
            global.set $dynrt_lib_modc_global20
            i32.const 1
            global.set $dynrt_lib_modc_global22
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn215
            local.get 4
            global.set $dynrt_lib_modc_global22
            local.get 6
            local.tee 17
            global.set $dynrt_lib_modc_global21
            global.get $dynrt_lib_modc_global24
            i32.const 1
            i32.eq
            if (result i32)  ;; label = @5
              i32.const 1
            else
              global.get $dynrt_lib_modc_global29
              i32.const 1
              i32.eq
            end
            if  ;; label = @5
              i32.const 0
              local.set 10
            else
              global.get $dynrt_lib_modc_global27
              i32.const 1
              i32.eq
              if  ;; label = @6
                block  ;; label = @7
                  i32.const 0
                  local.tee 13
                  global.set $dynrt_lib_modc_global27
                  i32.const 0
                  local.tee 14
                  local.set 10
                end
              else
                block  ;; label = @7
                  global.get $dynrt_lib_modc_global28
                  i32.const 1
                  i32.eq
                  if  ;; label = @8
                    i32.const 0
                    global.set $dynrt_lib_modc_global28
                  end
                  local.get 11
                  i32.const 1
                  i32.add
                  local.set 11
                  local.get 11
                  local.get 9
                  i32.ge_s
                  if  ;; label = @8
                    i32.const 0
                    local.set 10
                  end
                end
              end
            end
          end
          br 1 (;@2;)
        end
      end
    end)
  (func $dynrt_lib_modc__fn201 (param i32 i32 i32 i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    global.get $dynrt_lib_modc_global21
    local.set 4
    local.get 4
    local.tee 25
    local.set 5
    local.get 5
    i32.const 8
    i32.add
    i32.const 8
    i32.add
    i32.load
    local.set 5
    local.get 2
    global.set $dynrt_lib_modc_global22
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn215
    global.get $dynrt_lib_modc_global20
    local.set 6
    local.get 4
    local.tee 26
    local.set 7
    local.get 3
    i32.const 1
    i32.eq
    if  ;; label = @1
      local.get 4
      local.get 5
      call $dynrt_lib_modc__fn159
      local.set 7
    end
    i32.const 1
    local.set 8
    i32.const 0
    local.set 9
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 8
          i32.const 1
          i32.eq
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 7
            global.set $dynrt_lib_modc_global21
            local.get 6
            global.set $dynrt_lib_modc_global20
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn174
            i32.const 1
            local.set 10
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn175
            i32.const 59
            i32.ne
            if  ;; label = @5
              local.get 0
              local.get 1
              call $dynrt_lib_modc__fn189
              call $dynrt_lib_modc_dynToBool
              local.set 10
            end
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn174
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn175
            i32.const 59
            i32.eq
            if  ;; label = @5
              global.get $dynrt_lib_modc_global20
              i32.const 1
              i32.add
              global.set $dynrt_lib_modc_global20
            end
            global.get $dynrt_lib_modc_global20
            local.tee 23
            local.set 11
            i32.const 0
            global.set $dynrt_lib_modc_global22
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn175
            i32.const 41
            i32.ne
            if  ;; label = @5
              local.get 0
              local.get 1
              call $dynrt_lib_modc__fn215
            end
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn174
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn175
            i32.const 41
            i32.eq
            if  ;; label = @5
              global.get $dynrt_lib_modc_global20
              i32.const 1
              i32.add
              global.set $dynrt_lib_modc_global20
            end
            global.get $dynrt_lib_modc_global20
            local.tee 24
            local.set 12
            local.get 2
            i32.const 1
            i32.eq
            if (result i32)  ;; label = @5
              local.get 10
              i32.const 1
              i32.eq
            else
              i32.const 0
            end
            if (result i32)  ;; label = @5
              i32.const 1
            else
              i32.const 0
            end
            local.set 10
            local.get 10
            i32.const 1
            i32.eq
            if  ;; label = @5
              block  ;; label = @6
                local.get 7
                global.set $dynrt_lib_modc_global21
                local.get 12
                global.set $dynrt_lib_modc_global20
                i32.const 1
                local.tee 19
                global.set $dynrt_lib_modc_global22
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn215
                local.get 2
                global.set $dynrt_lib_modc_global22
                global.get $dynrt_lib_modc_global24
                i32.const 1
                i32.eq
                if (result i32)  ;; label = @7
                  i32.const 1
                else
                  global.get $dynrt_lib_modc_global29
                  i32.const 1
                  i32.eq
                end
                if  ;; label = @7
                  i32.const 0
                  local.set 8
                else
                  global.get $dynrt_lib_modc_global27
                  i32.const 1
                  i32.eq
                  if  ;; label = @8
                    block  ;; label = @9
                      i32.const 0
                      local.tee 13
                      global.set $dynrt_lib_modc_global27
                      i32.const 0
                      local.tee 14
                      local.set 8
                    end
                  else
                    block  ;; label = @9
                      global.get $dynrt_lib_modc_global28
                      i32.const 1
                      i32.eq
                      if  ;; label = @10
                        i32.const 0
                        global.set $dynrt_lib_modc_global28
                      end
                      local.get 7
                      local.set 10
                      local.get 3
                      i32.const 1
                      i32.eq
                      if  ;; label = @10
                        local.get 7
                        local.get 5
                        call $dynrt_lib_modc__fn159
                        local.set 10
                      end
                      local.get 10
                      local.tee 15
                      global.set $dynrt_lib_modc_global21
                      local.get 11
                      global.set $dynrt_lib_modc_global20
                      local.get 2
                      local.tee 16
                      global.set $dynrt_lib_modc_global22
                      local.get 0
                      local.get 1
                      call $dynrt_lib_modc__fn175
                      i32.const 41
                      i32.ne
                      if  ;; label = @10
                        local.get 0
                        local.get 1
                        call $dynrt_lib_modc__fn215
                      end
                      local.get 2
                      local.tee 17
                      global.set $dynrt_lib_modc_global22
                      local.get 10
                      local.tee 18
                      local.set 7
                    end
                  end
                end
                local.get 9
                i32.const 1
                local.tee 20
                i32.add
                local.set 9
                local.get 9
                i32.const 100000000
                i32.gt_s
                if  ;; label = @7
                  i32.const 0
                  local.set 8
                end
              end
            else
              block  ;; label = @6
                local.get 7
                global.set $dynrt_lib_modc_global21
                local.get 12
                global.set $dynrt_lib_modc_global20
                i32.const 0
                local.tee 21
                global.set $dynrt_lib_modc_global22
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn215
                local.get 2
                global.set $dynrt_lib_modc_global22
                i32.const 0
                local.tee 22
                local.set 8
              end
            end
          end
          br 1 (;@2;)
        end
      end
    end
    local.get 4
    local.tee 27
    global.set $dynrt_lib_modc_global21)
  (func $dynrt_lib_modc__fn202 (param i32 i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    global.get $dynrt_lib_modc_global22
    local.set 2
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn174
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn175
    i32.const 40
    i32.eq
    if  ;; label = @1
      global.get $dynrt_lib_modc_global20
      i32.const 1
      i32.add
      global.set $dynrt_lib_modc_global20
    end
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn189
    local.set 3
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn174
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn175
    i32.const 41
    i32.eq
    if  ;; label = @1
      global.get $dynrt_lib_modc_global20
      i32.const 1
      i32.add
      global.set $dynrt_lib_modc_global20
    end
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn174
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn175
    i32.const 123
    i32.eq
    if  ;; label = @1
      global.get $dynrt_lib_modc_global20
      i32.const 1
      i32.add
      global.set $dynrt_lib_modc_global20
    end
    i32.const -1
    local.tee 10
    local.set 4
    local.get 10
    local.set 5
    i32.const 1
    local.set 6
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 6
          i32.const 1
          i32.eq
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn174
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn175
            local.set 7
            local.get 7
            i32.const 125
            i32.eq
            if (result i32)  ;; label = @5
              i32.const 1
            else
              local.get 7
              i32.const -1
              i32.eq
            end
            if  ;; label = @5
              i32.const 0
              local.set 6
            else
              local.get 7
              i32.const 0
              call $dynrt_lib_modc__fn173
              i32.const 1
              i32.eq
              if  ;; label = @6
                block  ;; label = @7
                  global.get $dynrt_lib_modc_global20
                  local.set 7
                  local.get 0
                  local.get 1
                  call $dynrt_lib_modc__fn192
                  global.get $dynrt_lib_modc_global2
                  local.set 8
                  global.get $dynrt_lib_modc_global3
                  local.set 9
                  local.get 8
                  local.get 9
                  i32.const 1193
                  i32.const 4
                  call $dynrt_lib_modc__fn169
                  i32.const 1
                  i32.eq
                  if  ;; label = @8
                    block  ;; label = @9
                      local.get 4
                      i32.const -1
                      i32.eq
                      if  ;; label = @10
                        block  ;; label = @11
                          local.get 0
                          local.get 1
                          call $dynrt_lib_modc__fn189
                          local.set 7
                          local.get 0
                          local.get 1
                          call $dynrt_lib_modc__fn174
                          local.get 0
                          local.get 1
                          call $dynrt_lib_modc__fn175
                          i32.const 58
                          i32.eq
                          if  ;; label = @12
                            global.get $dynrt_lib_modc_global20
                            i32.const 1
                            i32.add
                            global.set $dynrt_lib_modc_global20
                          end
                          local.get 3
                          local.get 7
                          call $dynrt_lib_modc_dynStrictEq
                          i32.const 1
                          i32.eq
                          if  ;; label = @12
                            global.get $dynrt_lib_modc_global20
                            local.set 4
                          end
                        end
                      else
                        block  ;; label = @11
                          global.get $dynrt_lib_modc_global22
                          local.set 7
                          i32.const 0
                          global.set $dynrt_lib_modc_global22
                          local.get 0
                          local.get 1
                          call $dynrt_lib_modc__fn189
                          drop
                          local.get 7
                          global.set $dynrt_lib_modc_global22
                          local.get 0
                          local.get 1
                          call $dynrt_lib_modc__fn174
                          local.get 0
                          local.get 1
                          call $dynrt_lib_modc__fn175
                          i32.const 58
                          i32.eq
                          if  ;; label = @12
                            global.get $dynrt_lib_modc_global20
                            i32.const 1
                            i32.add
                            global.set $dynrt_lib_modc_global20
                          end
                        end
                      end
                      local.get 0
                      local.get 1
                      call $dynrt_lib_modc__fn203
                    end
                  else
                    local.get 8
                    local.get 9
                    i32.const 1197
                    i32.const 7
                    call $dynrt_lib_modc__fn169
                    i32.const 1
                    i32.eq
                    if  ;; label = @9
                      block  ;; label = @10
                        local.get 0
                        local.get 1
                        call $dynrt_lib_modc__fn174
                        local.get 0
                        local.get 1
                        call $dynrt_lib_modc__fn175
                        i32.const 58
                        i32.eq
                        if  ;; label = @11
                          global.get $dynrt_lib_modc_global20
                          i32.const 1
                          i32.add
                          global.set $dynrt_lib_modc_global20
                        end
                        global.get $dynrt_lib_modc_global20
                        local.set 5
                        local.get 0
                        local.get 1
                        call $dynrt_lib_modc__fn203
                      end
                    else
                      block  ;; label = @10
                        local.get 7
                        global.set $dynrt_lib_modc_global20
                        local.get 0
                        local.get 1
                        call $dynrt_lib_modc__fn203
                      end
                    end
                  end
                end
              else
                i32.const 0
                local.set 6
              end
            end
          end
          br 1 (;@2;)
        end
      end
    end
    global.get $dynrt_lib_modc_global20
    local.set 3
    local.get 4
    local.set 4
    local.get 4
    i32.const -1
    i32.eq
    if  ;; label = @1
      local.get 5
      local.set 4
    end
    local.get 2
    i32.const 1
    i32.eq
    if (result i32)  ;; label = @1
      local.get 4
      i32.const -1
      i32.ne
    else
      i32.const 0
    end
    if  ;; label = @1
      block  ;; label = @2
        local.get 4
        global.set $dynrt_lib_modc_global20
        i32.const 1
        global.set $dynrt_lib_modc_global22
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn204
        local.get 2
        global.set $dynrt_lib_modc_global22
      end
    end
    local.get 3
    global.set $dynrt_lib_modc_global20
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn174
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn175
    i32.const 125
    i32.eq
    if  ;; label = @1
      global.get $dynrt_lib_modc_global20
      i32.const 1
      i32.add
      global.set $dynrt_lib_modc_global20
    end
    global.get $dynrt_lib_modc_global27
    i32.const 1
    i32.eq
    if  ;; label = @1
      i32.const 0
      global.set $dynrt_lib_modc_global27
    end)
  (func $dynrt_lib_modc__fn203 (param i32 i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    i32.const 1
    local.set 2
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 2
          i32.const 1
          i32.eq
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn174
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn175
            local.set 3
            local.get 3
            i32.const 125
            i32.eq
            if (result i32)  ;; label = @5
              i32.const 1
            else
              local.get 3
              i32.const -1
              i32.eq
            end
            if  ;; label = @5
              i32.const 0
              local.set 2
            else
              local.get 3
              i32.const 0
              call $dynrt_lib_modc__fn173
              i32.const 1
              i32.eq
              if  ;; label = @6
                block  ;; label = @7
                  global.get $dynrt_lib_modc_global20
                  local.set 3
                  local.get 0
                  local.get 1
                  call $dynrt_lib_modc__fn192
                  global.get $dynrt_lib_modc_global2
                  local.set 4
                  global.get $dynrt_lib_modc_global3
                  local.set 5
                  local.get 4
                  local.get 5
                  i32.const 1193
                  i32.const 4
                  call $dynrt_lib_modc__fn169
                  i32.const 1
                  i32.eq
                  if (result i32)  ;; label = @8
                    i32.const 1
                  else
                    local.get 4
                    local.get 5
                    i32.const 1197
                    i32.const 7
                    call $dynrt_lib_modc__fn169
                    i32.const 1
                    i32.eq
                  end
                  if  ;; label = @8
                    block  ;; label = @9
                      local.get 3
                      global.set $dynrt_lib_modc_global20
                      i32.const 0
                      local.set 2
                    end
                  else
                    block  ;; label = @9
                      local.get 3
                      local.tee 6
                      global.set $dynrt_lib_modc_global20
                      global.get $dynrt_lib_modc_global22
                      local.set 3
                      i32.const 0
                      global.set $dynrt_lib_modc_global22
                      local.get 0
                      local.get 1
                      call $dynrt_lib_modc__fn215
                      local.get 3
                      local.tee 7
                      global.set $dynrt_lib_modc_global22
                    end
                  end
                end
              else
                block  ;; label = @7
                  global.get $dynrt_lib_modc_global22
                  local.set 3
                  i32.const 0
                  global.set $dynrt_lib_modc_global22
                  local.get 0
                  local.get 1
                  call $dynrt_lib_modc__fn215
                  local.get 3
                  global.set $dynrt_lib_modc_global22
                end
              end
            end
          end
          br 1 (;@2;)
        end
      end
    end)
  (func $dynrt_lib_modc__fn204 (param i32 i32)
    (local i32) (local i32) (local i32) (local i32)
    i32.const 1
    local.set 2
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 2
          i32.const 1
          i32.eq
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn174
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn175
            local.set 3
            local.get 3
            i32.const 125
            i32.eq
            if (result i32)  ;; label = @5
              i32.const 1
            else
              local.get 3
              i32.const -1
              i32.eq
            end
            if  ;; label = @5
              i32.const 0
              local.set 2
            else
              local.get 3
              i32.const 0
              call $dynrt_lib_modc__fn173
              i32.const 1
              i32.eq
              if  ;; label = @6
                block  ;; label = @7
                  global.get $dynrt_lib_modc_global20
                  local.set 3
                  local.get 0
                  local.get 1
                  call $dynrt_lib_modc__fn192
                  global.get $dynrt_lib_modc_global2
                  local.set 4
                  global.get $dynrt_lib_modc_global3
                  local.set 5
                  local.get 4
                  local.get 5
                  i32.const 1193
                  i32.const 4
                  call $dynrt_lib_modc__fn169
                  i32.const 1
                  i32.eq
                  if  ;; label = @8
                    block  ;; label = @9
                      global.get $dynrt_lib_modc_global22
                      local.set 3
                      i32.const 0
                      global.set $dynrt_lib_modc_global22
                      local.get 0
                      local.get 1
                      call $dynrt_lib_modc__fn189
                      drop
                      local.get 3
                      global.set $dynrt_lib_modc_global22
                      local.get 0
                      local.get 1
                      call $dynrt_lib_modc__fn174
                      local.get 0
                      local.get 1
                      call $dynrt_lib_modc__fn175
                      i32.const 58
                      i32.eq
                      if  ;; label = @10
                        global.get $dynrt_lib_modc_global20
                        i32.const 1
                        i32.add
                        global.set $dynrt_lib_modc_global20
                      end
                    end
                  else
                    local.get 4
                    local.get 5
                    i32.const 1197
                    i32.const 7
                    call $dynrt_lib_modc__fn169
                    i32.const 1
                    i32.eq
                    if  ;; label = @9
                      block  ;; label = @10
                        local.get 0
                        local.get 1
                        call $dynrt_lib_modc__fn174
                        local.get 0
                        local.get 1
                        call $dynrt_lib_modc__fn175
                        i32.const 58
                        i32.eq
                        if  ;; label = @11
                          global.get $dynrt_lib_modc_global20
                          i32.const 1
                          i32.add
                          global.set $dynrt_lib_modc_global20
                        end
                      end
                    else
                      block  ;; label = @10
                        local.get 3
                        global.set $dynrt_lib_modc_global20
                        local.get 0
                        local.get 1
                        call $dynrt_lib_modc__fn215
                      end
                    end
                  end
                end
              else
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn215
              end
            end
            global.get $dynrt_lib_modc_global27
            i32.const 1
            i32.eq
            if  ;; label = @5
              i32.const 0
              local.set 2
            end
            global.get $dynrt_lib_modc_global24
            i32.const 1
            i32.eq
            if  ;; label = @5
              i32.const 0
              local.set 2
            end
            global.get $dynrt_lib_modc_global29
            i32.const 1
            i32.eq
            if  ;; label = @5
              i32.const 0
              local.set 2
            end
            global.get $dynrt_lib_modc_global28
            i32.const 1
            i32.eq
            if  ;; label = @5
              i32.const 0
              local.set 2
            end
          end
          br 1 (;@2;)
        end
      end
    end)
  (func $dynrt_lib_modc__fn205 (param i32 i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    global.get $dynrt_lib_modc_global22
    local.set 2
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn174
    local.get 2
    local.tee 17
    global.set $dynrt_lib_modc_global22
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn215
    local.get 2
    local.tee 18
    global.set $dynrt_lib_modc_global22
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn174
    i32.const 0
    local.tee 19
    local.set 3
    global.get $dynrt_lib_modc_global20
    local.tee 20
    local.set 4
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn175
    i32.const 0
    call $dynrt_lib_modc__fn173
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn192
        global.get $dynrt_lib_modc_global2
        local.set 5
        global.get $dynrt_lib_modc_global3
        local.set 6
        local.get 5
        local.get 6
        i32.const 947
        i32.const 5
        call $dynrt_lib_modc__fn169
        i32.const 1
        i32.eq
        if  ;; label = @3
          i32.const 1
          local.set 3
        else
          local.get 4
          global.set $dynrt_lib_modc_global20
        end
      end
    end
    local.get 3
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        i32.const 520
        local.set 3
        i32.const 0
        local.set 4
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn174
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn175
        i32.const 40
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            global.get $dynrt_lib_modc_global20
            i32.const 1
            i32.add
            global.set $dynrt_lib_modc_global20
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn174
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn192
            global.get $dynrt_lib_modc_global2
            local.set 3
            global.get $dynrt_lib_modc_global3
            local.set 4
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn174
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn175
            i32.const 41
            i32.eq
            if  ;; label = @5
              global.get $dynrt_lib_modc_global20
              i32.const 1
              i32.add
              global.set $dynrt_lib_modc_global20
            end
          end
        end
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn174
        global.get $dynrt_lib_modc_global29
        i32.const 1
        i32.eq
        if (result i32)  ;; label = @3
          local.get 2
          i32.const 1
          i32.eq
        else
          i32.const 0
        end
        if  ;; label = @3
          block  ;; label = @4
            global.get $dynrt_lib_modc_global30
            local.set 5
            i32.const 0
            global.set $dynrt_lib_modc_global29
            global.get $dynrt_lib_modc_global21
            local.set 6
            local.get 6
            call $dynrt_lib_modc__fn157
            local.set 7
            local.get 4
            i32.const 0
            i32.gt_s
            if  ;; label = @5
              local.get 7
              local.get 3
              local.get 4
              local.get 5
              call $dynrt_lib_modc_dynSet
            end
            local.get 7
            local.tee 9
            global.set $dynrt_lib_modc_global21
            local.get 7
            call $dynrt_lib_modc__fn61
            i32.const 1
            global.set $dynrt_lib_modc_global22
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn215
            call $dynrt_lib_modc__fn62
            local.get 6
            local.tee 10
            global.set $dynrt_lib_modc_global21
            local.get 2
            global.set $dynrt_lib_modc_global22
          end
        else
          block  ;; label = @4
            i32.const 0
            global.set $dynrt_lib_modc_global22
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn215
            local.get 2
            global.set $dynrt_lib_modc_global22
          end
        end
      end
    end
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn174
    i32.const 0
    local.tee 21
    local.set 3
    global.get $dynrt_lib_modc_global20
    local.tee 22
    local.set 4
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn175
    i32.const 0
    call $dynrt_lib_modc__fn173
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn192
        global.get $dynrt_lib_modc_global2
        local.set 5
        global.get $dynrt_lib_modc_global3
        local.set 6
        local.get 5
        local.get 6
        i32.const 952
        i32.const 7
        call $dynrt_lib_modc__fn169
        i32.const 1
        i32.eq
        if  ;; label = @3
          i32.const 1
          local.set 3
        else
          local.get 4
          global.set $dynrt_lib_modc_global20
        end
      end
    end
    local.get 3
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_lib_modc_global29
        local.set 3
        global.get $dynrt_lib_modc_global30
        local.set 4
        global.get $dynrt_lib_modc_global24
        local.set 5
        global.get $dynrt_lib_modc_global25
        local.set 6
        global.get $dynrt_lib_modc_global27
        local.set 7
        global.get $dynrt_lib_modc_global28
        local.set 8
        i32.const 0
        local.tee 11
        global.set $dynrt_lib_modc_global29
        i32.const 0
        local.tee 12
        global.set $dynrt_lib_modc_global24
        i32.const 0
        local.tee 13
        global.set $dynrt_lib_modc_global27
        i32.const 0
        local.tee 14
        global.set $dynrt_lib_modc_global28
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn174
        local.get 2
        local.tee 15
        global.set $dynrt_lib_modc_global22
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn215
        local.get 2
        local.tee 16
        global.set $dynrt_lib_modc_global22
        global.get $dynrt_lib_modc_global29
        i32.eqz
        if (result i32)  ;; label = @3
          global.get $dynrt_lib_modc_global24
          i32.eqz
        else
          i32.const 0
        end
        if (result i32)  ;; label = @3
          global.get $dynrt_lib_modc_global27
          i32.eqz
        else
          i32.const 0
        end
        if (result i32)  ;; label = @3
          global.get $dynrt_lib_modc_global28
          i32.eqz
        else
          i32.const 0
        end
        if  ;; label = @3
          block  ;; label = @4
            local.get 3
            global.set $dynrt_lib_modc_global29
            local.get 4
            global.set $dynrt_lib_modc_global30
            local.get 5
            global.set $dynrt_lib_modc_global24
            local.get 6
            global.set $dynrt_lib_modc_global25
            local.get 7
            global.set $dynrt_lib_modc_global27
            local.get 8
            global.set $dynrt_lib_modc_global28
          end
        end
      end
    end)
  (func $dynrt_lib_modc__fn206 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32)
    call $dynrt_lib_modc_dynArray
    local.set 2
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn175
    i32.const 40
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_lib_modc_global20
        i32.const 1
        i32.add
        global.set $dynrt_lib_modc_global20
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn174
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn175
        i32.const 41
        i32.eq
        if  ;; label = @3
          global.get $dynrt_lib_modc_global20
          i32.const 1
          i32.add
          global.set $dynrt_lib_modc_global20
        else
          block  ;; label = @4
            i32.const 1
            local.set 3
            block  ;; label = @5
              loop  ;; label = @6
                block  ;; label = @7
                  local.get 3
                  i32.const 1
                  i32.eq
                  i32.eqz
                  br_if 2 (;@5;)
                  block  ;; label = @8
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn174
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn192
                    global.get $dynrt_lib_modc_global2
                    local.set 4
                    global.get $dynrt_lib_modc_global3
                    local.set 5
                    local.get 2
                    local.get 4
                    local.get 5
                    call $dynrt_lib_modc_dynString
                    call $dynrt_lib_modc_dynPush
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn174
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn175
                    local.set 4
                    local.get 4
                    i32.const 44
                    i32.eq
                    if  ;; label = @9
                      global.get $dynrt_lib_modc_global20
                      i32.const 1
                      i32.add
                      global.set $dynrt_lib_modc_global20
                    else
                      block  ;; label = @10
                        local.get 4
                        i32.const 41
                        i32.eq
                        if  ;; label = @11
                          global.get $dynrt_lib_modc_global20
                          i32.const 1
                          i32.add
                          global.set $dynrt_lib_modc_global20
                        end
                        i32.const 0
                        local.set 3
                      end
                    end
                  end
                  br 1 (;@6;)
                end
              end
            end
          end
        end
      end
    end
    local.get 2
    return)
  (func $dynrt_lib_modc__fn207 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    global.get $dynrt_lib_modc_global20
    local.tee 12
    i32.const 1
    local.tee 13
    i32.add
    global.set $dynrt_lib_modc_global20
    global.get $dynrt_lib_modc_global20
    local.tee 14
    local.set 2
    i32.const 1
    local.tee 15
    local.set 3
    i32.const 0
    local.tee 16
    local.set 4
    local.get 16
    local.set 5
    local.get 15
    local.set 6
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 6
          i32.const 1
          i32.eq
          if (result i32)  ;; label = @4
            global.get $dynrt_lib_modc_global20
            local.get 1
            i32.lt_s
          else
            i32.const 0
          end
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 0
            local.get 1
            global.get $dynrt_lib_modc_global20
            call $dynrt_lib_modc__fn9
            local.set 7
            local.get 4
            i32.const 1
            i32.eq
            if  ;; label = @5
              local.get 7
              i32.const 92
              i32.eq
              if  ;; label = @6
                global.get $dynrt_lib_modc_global20
                i32.const 2
                i32.add
                global.set $dynrt_lib_modc_global20
              else
                local.get 7
                local.get 5
                i32.eq
                if  ;; label = @7
                  block  ;; label = @8
                    i32.const 0
                    local.set 4
                    global.get $dynrt_lib_modc_global20
                    i32.const 1
                    i32.add
                    global.set $dynrt_lib_modc_global20
                  end
                else
                  global.get $dynrt_lib_modc_global20
                  i32.const 1
                  i32.add
                  global.set $dynrt_lib_modc_global20
                end
              end
            else
              local.get 7
              i32.const 39
              i32.eq
              if (result i32)  ;; label = @6
                i32.const 1
              else
                local.get 7
                i32.const 34
                i32.eq
              end
              if  ;; label = @6
                block  ;; label = @7
                  i32.const 1
                  local.tee 8
                  local.set 4
                  local.get 7
                  local.set 5
                  global.get $dynrt_lib_modc_global20
                  i32.const 1
                  local.tee 9
                  i32.add
                  global.set $dynrt_lib_modc_global20
                end
              else
                local.get 7
                i32.const 123
                i32.eq
                if  ;; label = @7
                  block  ;; label = @8
                    local.get 3
                    i32.const 1
                    local.tee 10
                    i32.add
                    local.set 3
                    global.get $dynrt_lib_modc_global20
                    i32.const 1
                    local.tee 11
                    i32.add
                    global.set $dynrt_lib_modc_global20
                  end
                else
                  local.get 7
                  i32.const 125
                  i32.eq
                  if  ;; label = @8
                    block  ;; label = @9
                      local.get 3
                      i32.const 1
                      i32.sub
                      local.set 3
                      local.get 3
                      i32.eqz
                      if  ;; label = @10
                        i32.const 0
                        local.set 6
                      else
                        global.get $dynrt_lib_modc_global20
                        i32.const 1
                        i32.add
                        global.set $dynrt_lib_modc_global20
                      end
                    end
                  else
                    global.get $dynrt_lib_modc_global20
                    i32.const 1
                    i32.add
                    global.set $dynrt_lib_modc_global20
                  end
                end
              end
            end
          end
          br 1 (;@2;)
        end
      end
    end
    local.get 0
    local.get 1
    local.get 2
    global.get $dynrt_lib_modc_global20
    call $dynrt_lib_modc__fn6
    local.set 3
    nop
    local.set 2
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn175
    i32.const 125
    i32.eq
    if  ;; label = @1
      global.get $dynrt_lib_modc_global20
      i32.const 1
      i32.add
      global.set $dynrt_lib_modc_global20
    end
    local.get 2
    local.get 3
    call $dynrt_lib_modc_dynString
    return)
  (func $dynrt_lib_modc__fn208 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn174
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn175
    i32.const 123
    i32.eq
    if  ;; label = @1
      local.get 0
      local.get 1
      call $dynrt_lib_modc__fn207
      return
    end
    global.get $dynrt_lib_modc_global20
    local.tee 4
    local.set 2
    global.get $dynrt_lib_modc_global22
    local.set 3
    i32.const 0
    global.set $dynrt_lib_modc_global22
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn189
    drop
    local.get 3
    global.set $dynrt_lib_modc_global22
    nop
    local.get 0
    local.get 1
    local.get 2
    global.get $dynrt_lib_modc_global20
    call $dynrt_lib_modc__fn6
    call $dynrt_lib_modc_dynString
    return)
  (func $dynrt_lib_modc__fn209 (param i32 i32) (result i32)
    (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn174
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn175
    i32.const 0
    call $dynrt_lib_modc__fn173
    i32.const 1
    i32.eq
    if  ;; label = @1
      local.get 0
      local.get 1
      call $dynrt_lib_modc__fn192
    end
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn174
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn206
    local.set 2
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn174
    i32.const 520
    i32.const 0
    call $dynrt_lib_modc_dynString
    local.set 3
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn175
    i32.const 123
    i32.eq
    if  ;; label = @1
      local.get 0
      local.get 1
      call $dynrt_lib_modc__fn207
      local.set 3
    end
    local.get 2
    local.get 3
    global.get $dynrt_lib_modc_global21
    call $dynrt_lib_modc__fn152
    return)
  (func $dynrt_lib_modc__fn210 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    global.get $dynrt_lib_modc_global20
    local.set 2
    i32.const 0
    local.tee 14
    local.set 3
    local.get 14
    local.set 4
    local.get 14
    local.set 5
    i32.const 1
    local.set 6
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 6
          i32.const 1
          i32.eq
          if (result i32)  ;; label = @4
            global.get $dynrt_lib_modc_global20
            local.get 1
            i32.lt_s
          else
            i32.const 0
          end
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 0
            local.get 1
            global.get $dynrt_lib_modc_global20
            call $dynrt_lib_modc__fn9
            local.set 7
            local.get 4
            i32.const 1
            i32.eq
            if  ;; label = @5
              local.get 7
              i32.const 92
              i32.eq
              if  ;; label = @6
                global.get $dynrt_lib_modc_global20
                i32.const 2
                i32.add
                global.set $dynrt_lib_modc_global20
              else
                local.get 7
                local.get 5
                i32.eq
                if  ;; label = @7
                  block  ;; label = @8
                    i32.const 0
                    local.set 4
                    global.get $dynrt_lib_modc_global20
                    i32.const 1
                    i32.add
                    global.set $dynrt_lib_modc_global20
                  end
                else
                  global.get $dynrt_lib_modc_global20
                  i32.const 1
                  i32.add
                  global.set $dynrt_lib_modc_global20
                end
              end
            else
              local.get 7
              i32.const 39
              i32.eq
              if (result i32)  ;; label = @6
                i32.const 1
              else
                local.get 7
                i32.const 34
                i32.eq
              end
              if  ;; label = @6
                block  ;; label = @7
                  i32.const 1
                  local.tee 8
                  local.set 4
                  local.get 7
                  local.set 5
                  global.get $dynrt_lib_modc_global20
                  i32.const 1
                  local.tee 9
                  i32.add
                  global.set $dynrt_lib_modc_global20
                end
              else
                local.get 7
                i32.const 40
                i32.eq
                if  ;; label = @7
                  block  ;; label = @8
                    local.get 3
                    i32.const 1
                    local.tee 10
                    i32.add
                    local.set 3
                    global.get $dynrt_lib_modc_global20
                    i32.const 1
                    local.tee 11
                    i32.add
                    global.set $dynrt_lib_modc_global20
                  end
                else
                  local.get 7
                  i32.const 41
                  i32.eq
                  if  ;; label = @8
                    block  ;; label = @9
                      local.get 3
                      i32.const 1
                      local.tee 12
                      i32.sub
                      local.set 3
                      global.get $dynrt_lib_modc_global20
                      i32.const 1
                      local.tee 13
                      i32.add
                      global.set $dynrt_lib_modc_global20
                      local.get 3
                      i32.eqz
                      if  ;; label = @10
                        i32.const 0
                        local.set 6
                      end
                    end
                  else
                    global.get $dynrt_lib_modc_global20
                    i32.const 1
                    i32.add
                    global.set $dynrt_lib_modc_global20
                  end
                end
              end
            end
          end
          br 1 (;@2;)
        end
      end
    end
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn174
    i32.const 0
    local.tee 15
    local.set 3
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn175
    i32.const 61
    i32.eq
    if (result i32)  ;; label = @1
      local.get 0
      local.get 1
      call $dynrt_lib_modc__fn176
      i32.const 62
      i32.eq
    else
      i32.const 0
    end
    if  ;; label = @1
      i32.const 1
      local.set 3
    end
    local.get 2
    global.set $dynrt_lib_modc_global20
    local.get 3
    return)
  (func $dynrt_lib_modc__fn211 (param i32 i32 i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn174
    i32.const 0
    local.tee 10
    local.set 3
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn175
    i32.const 42
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_lib_modc_global20
        i32.const 1
        local.tee 8
        i32.add
        global.set $dynrt_lib_modc_global20
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn174
        i32.const 1
        local.tee 9
        local.set 3
      end
    end
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn192
    global.get $dynrt_lib_modc_global2
    local.set 4
    global.get $dynrt_lib_modc_global3
    local.set 5
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn174
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn206
    local.set 6
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn174
    i32.const 520
    i32.const 0
    call $dynrt_lib_modc_dynString
    local.set 7
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn175
    i32.const 123
    i32.eq
    if  ;; label = @1
      local.get 0
      local.get 1
      call $dynrt_lib_modc__fn207
      local.set 7
    end
    local.get 6
    local.get 7
    global.get $dynrt_lib_modc_global21
    call $dynrt_lib_modc__fn152
    local.set 6
    local.get 3
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 6
        local.set 3
        local.get 3
        i32.const 8
        i32.add
        i32.const 4
        i32.add
        i32.const -3
        i32.store
      end
    else
      local.get 2
      i32.const 1
      i32.eq
      if  ;; label = @2
        block  ;; label = @3
          local.get 6
          local.set 3
          local.get 3
          i32.const 8
          i32.add
          i32.const 4
          i32.add
          i32.const -4
          i32.store
        end
      end
    end
    global.get $dynrt_lib_modc_global22
    i32.const 1
    i32.eq
    if  ;; label = @1
      global.get $dynrt_lib_modc_global21
      local.get 4
      local.get 5
      local.get 6
      call $dynrt_lib_modc_dynSet
    end)
  (func $dynrt_lib_modc__fn212 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn174
    i32.const 520
    local.tee 29
    local.set 2
    i32.const 0
    local.tee 30
    local.set 3
    local.get 29
    local.set 4
    local.get 30
    local.set 5
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn175
    i32.const 0
    call $dynrt_lib_modc__fn173
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn192
        global.get $dynrt_lib_modc_global2
        local.set 6
        global.get $dynrt_lib_modc_global3
        local.set 7
        local.get 6
        local.get 7
        i32.const 1204
        i32.const 7
        call $dynrt_lib_modc__fn169
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn174
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn192
            global.get $dynrt_lib_modc_global2
            local.set 4
            global.get $dynrt_lib_modc_global3
            local.set 5
          end
        else
          block  ;; label = @4
            local.get 6
            local.set 2
            local.get 7
            local.set 3
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn174
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn175
            i32.const 0
            call $dynrt_lib_modc__fn173
            i32.const 1
            i32.eq
            if  ;; label = @5
              block  ;; label = @6
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn192
                global.get $dynrt_lib_modc_global2
                local.set 6
                global.get $dynrt_lib_modc_global3
                local.set 7
                local.get 6
                local.get 7
                i32.const 1204
                i32.const 7
                call $dynrt_lib_modc__fn169
                i32.const 1
                i32.eq
                if  ;; label = @7
                  block  ;; label = @8
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn174
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn192
                    global.get $dynrt_lib_modc_global2
                    local.set 4
                    global.get $dynrt_lib_modc_global3
                    local.set 5
                  end
                end
              end
            end
          end
        end
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn174
      end
    end
    i32.const -1
    local.tee 31
    local.set 6
    local.get 31
    local.set 7
    local.get 5
    i32.const 0
    i32.gt_s
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_lib_modc_global21
        i32.const -1
        i32.eq
        if (result i32)  ;; label = @3
          i32.const -1
        else
          global.get $dynrt_lib_modc_global21
          local.get 4
          local.get 5
          call $dynrt_lib_modc__fn156
        end
        local.set 4
        local.get 4
        i32.const -1
        i32.ne
        if  ;; label = @3
          block  ;; label = @4
            local.get 4
            local.tee 20
            local.set 6
            local.get 4
            i32.const 959
            i32.const 7
            call $dynrt_lib_modc_dynGet
            local.set 4
            local.get 4
            i32.const -1
            i32.ne
            if  ;; label = @5
              local.get 4
              local.set 7
            end
          end
        end
      end
    end
    call $dynrt_lib_modc_dynObject
    local.set 4
    local.get 7
    i32.const -1
    i32.ne
    if  ;; label = @1
      block  ;; label = @2
        local.get 4
        local.set 5
        local.get 5
        i32.const 8
        i32.add
        i32.const 8
        i32.add
        local.get 7
        i32.store
      end
    end
    call $dynrt_lib_modc_dynObject
    local.set 5
    global.get $dynrt_lib_modc_global21
    call $dynrt_lib_modc__fn157
    local.set 8
    local.get 7
    i32.const -1
    i32.ne
    if  ;; label = @1
      local.get 8
      i32.const 1116
      i32.const 12
      local.get 7
      call $dynrt_lib_modc_dynSet
    end
    local.get 6
    i32.const -1
    i32.ne
    if  ;; label = @1
      local.get 8
      i32.const 1098
      i32.const 12
      local.get 6
      call $dynrt_lib_modc_dynSet
    end
    i32.const 520
    local.tee 32
    local.set 7
    i32.const 0
    local.tee 33
    local.set 9
    i32.const -1
    local.tee 34
    local.set 10
    local.get 32
    local.set 11
    local.get 33
    local.set 12
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn175
    i32.const 123
    i32.eq
    if  ;; label = @1
      global.get $dynrt_lib_modc_global20
      i32.const 1
      i32.add
      global.set $dynrt_lib_modc_global20
    end
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn174
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 0
          local.get 1
          call $dynrt_lib_modc__fn175
          i32.const 125
          i32.ne
          if (result i32)  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn175
            i32.const -1
            i32.ne
          else
            i32.const 0
          end
          i32.eqz
          br_if 2 (;@1;)
          local.get 0
          local.get 1
          call $dynrt_lib_modc__fn175
          i32.const 59
          i32.eq
          if  ;; label = @4
            block  ;; label = @5
              global.get $dynrt_lib_modc_global20
              i32.const 1
              i32.add
              global.set $dynrt_lib_modc_global20
              local.get 0
              local.get 1
              call $dynrt_lib_modc__fn174
            end
          else
            block  ;; label = @5
              i32.const 0
              local.tee 25
              local.set 13
              local.get 25
              local.set 14
              local.get 0
              local.get 1
              call $dynrt_lib_modc__fn192
              global.get $dynrt_lib_modc_global2
              local.set 15
              global.get $dynrt_lib_modc_global3
              local.set 16
              local.get 0
              local.get 1
              call $dynrt_lib_modc__fn174
              local.get 15
              local.get 16
              i32.const 1211
              i32.const 6
              call $dynrt_lib_modc__fn169
              i32.const 1
              i32.eq
              if (result i32)  ;; label = @6
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn175
                i32.const 0
                call $dynrt_lib_modc__fn173
                i32.const 1
                i32.eq
              else
                i32.const 0
              end
              if  ;; label = @6
                block  ;; label = @7
                  i32.const 1
                  local.set 13
                  local.get 0
                  local.get 1
                  call $dynrt_lib_modc__fn192
                  global.get $dynrt_lib_modc_global2
                  local.set 15
                  global.get $dynrt_lib_modc_global3
                  local.set 16
                  local.get 0
                  local.get 1
                  call $dynrt_lib_modc__fn174
                end
              end
              local.get 15
              local.get 16
              i32.const 863
              i32.const 3
              call $dynrt_lib_modc__fn169
              i32.const 1
              i32.eq
              if (result i32)  ;; label = @6
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn175
                i32.const 0
                call $dynrt_lib_modc__fn173
                i32.const 1
                i32.eq
              else
                i32.const 0
              end
              if  ;; label = @6
                block  ;; label = @7
                  i32.const 1
                  local.set 14
                  local.get 0
                  local.get 1
                  call $dynrt_lib_modc__fn192
                  global.get $dynrt_lib_modc_global2
                  local.set 15
                  global.get $dynrt_lib_modc_global3
                  local.set 16
                  local.get 0
                  local.get 1
                  call $dynrt_lib_modc__fn174
                end
              else
                local.get 15
                local.get 16
                i32.const 860
                i32.const 3
                call $dynrt_lib_modc__fn169
                i32.const 1
                i32.eq
                if (result i32)  ;; label = @7
                  local.get 0
                  local.get 1
                  call $dynrt_lib_modc__fn175
                  i32.const 0
                  call $dynrt_lib_modc__fn173
                  i32.const 1
                  i32.eq
                else
                  i32.const 0
                end
                if  ;; label = @7
                  block  ;; label = @8
                    i32.const 2
                    local.set 14
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn192
                    global.get $dynrt_lib_modc_global2
                    local.set 15
                    global.get $dynrt_lib_modc_global3
                    local.set 16
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn174
                  end
                end
              end
              local.get 0
              local.get 1
              call $dynrt_lib_modc__fn175
              local.set 17
              local.get 17
              i32.const 40
              i32.eq
              if  ;; label = @6
                block  ;; label = @7
                  local.get 0
                  local.get 1
                  call $dynrt_lib_modc__fn206
                  local.set 17
                  local.get 0
                  local.get 1
                  call $dynrt_lib_modc__fn174
                  local.get 0
                  local.get 1
                  call $dynrt_lib_modc__fn207
                  local.set 18
                  local.get 15
                  local.get 16
                  i32.const 1217
                  i32.const 11
                  call $dynrt_lib_modc__fn169
                  i32.const 1
                  i32.eq
                  if  ;; label = @8
                    block  ;; label = @9
                      local.get 17
                      local.set 10
                      local.get 18
                      call $dynrt_lib_modc__fn85
                      global.get $dynrt_lib_modc_global2
                      local.set 7
                      global.get $dynrt_lib_modc_global3
                      local.set 9
                    end
                  else
                    block  ;; label = @9
                      local.get 17
                      local.get 18
                      local.get 8
                      call $dynrt_lib_modc__fn152
                      local.set 17
                      local.get 15
                      local.set 18
                      local.get 16
                      local.set 19
                      local.get 14
                      i32.const 1
                      i32.eq
                      if  ;; label = @10
                        block  ;; label = @11
                          i32.const 980
                          local.set 18
                          i32.const 6
                          local.set 19
                          local.get 18
                          local.get 19
                          local.get 15
                          local.get 16
                          call $dynrt_lib_modc__fn5
                          local.set 19
                          nop
                          local.set 18
                        end
                      else
                        local.get 14
                        i32.const 2
                        i32.eq
                        if  ;; label = @11
                          block  ;; label = @12
                            i32.const 992
                            local.set 18
                            i32.const 6
                            local.set 19
                            local.get 18
                            local.get 19
                            local.get 15
                            local.get 16
                            call $dynrt_lib_modc__fn5
                            local.set 19
                            nop
                            local.set 18
                          end
                        end
                      end
                      local.get 13
                      i32.const 1
                      i32.eq
                      if  ;; label = @10
                        local.get 5
                        local.get 18
                        local.get 19
                        local.get 17
                        call $dynrt_lib_modc_dynSet
                      else
                        local.get 4
                        local.get 18
                        local.get 19
                        local.get 17
                        call $dynrt_lib_modc_dynSet
                      end
                    end
                  end
                end
              else
                block  ;; label = @7
                  local.get 13
                  i32.const 1
                  i32.eq
                  if  ;; label = @8
                    block  ;; label = @9
                      call $dynrt_lib_modc_dynUndefined
                      local.set 13
                      local.get 17
                      i32.const 61
                      i32.eq
                      if  ;; label = @10
                        block  ;; label = @11
                          global.get $dynrt_lib_modc_global20
                          i32.const 1
                          i32.add
                          global.set $dynrt_lib_modc_global20
                          local.get 0
                          local.get 1
                          call $dynrt_lib_modc__fn189
                          local.set 13
                        end
                      end
                      global.get $dynrt_lib_modc_global22
                      i32.const 1
                      i32.eq
                      if  ;; label = @10
                        local.get 5
                        local.get 15
                        local.get 16
                        local.get 13
                        call $dynrt_lib_modc_dynSet
                      end
                    end
                  else
                    block  ;; label = @9
                      i32.const 533
                      local.set 13
                      i32.const 9
                      local.set 14
                      local.get 17
                      i32.const 61
                      i32.eq
                      if  ;; label = @10
                        block  ;; label = @11
                          global.get $dynrt_lib_modc_global20
                          local.tee 21
                          i32.const 1
                          i32.add
                          global.set $dynrt_lib_modc_global20
                          local.get 0
                          local.get 1
                          call $dynrt_lib_modc__fn174
                          global.get $dynrt_lib_modc_global20
                          local.tee 22
                          local.set 13
                          global.get $dynrt_lib_modc_global22
                          local.set 14
                          i32.const 0
                          global.set $dynrt_lib_modc_global22
                          local.get 0
                          local.get 1
                          call $dynrt_lib_modc__fn189
                          drop
                          local.get 14
                          global.set $dynrt_lib_modc_global22
                          local.get 0
                          local.get 1
                          local.get 13
                          global.get $dynrt_lib_modc_global20
                          call $dynrt_lib_modc__fn6
                          local.set 14
                          nop
                          local.set 13
                        end
                      end
                      local.get 11
                      local.tee 23
                      local.set 11
                      local.get 12
                      local.tee 24
                      local.set 12
                      local.get 11
                      local.get 12
                      i32.const 1228
                      i32.const 5
                      call $dynrt_lib_modc__fn5
                      local.set 12
                      nop
                      local.set 11
                      local.get 11
                      local.get 12
                      local.get 15
                      local.get 16
                      call $dynrt_lib_modc__fn5
                      local.set 12
                      nop
                      local.set 11
                      local.get 11
                      local.get 12
                      i32.const 1233
                      i32.const 3
                      call $dynrt_lib_modc__fn5
                      local.set 12
                      nop
                      local.set 11
                      local.get 11
                      local.get 12
                      local.get 13
                      local.get 14
                      call $dynrt_lib_modc__fn5
                      local.set 12
                      nop
                      local.set 11
                      local.get 11
                      local.get 12
                      i32.const 1236
                      i32.const 2
                      call $dynrt_lib_modc__fn5
                      local.set 12
                      nop
                      local.set 11
                    end
                  end
                  local.get 0
                  local.get 1
                  call $dynrt_lib_modc__fn174
                  local.get 0
                  local.get 1
                  call $dynrt_lib_modc__fn175
                  i32.const 59
                  i32.eq
                  if  ;; label = @8
                    global.get $dynrt_lib_modc_global20
                    i32.const 1
                    i32.add
                    global.set $dynrt_lib_modc_global20
                  end
                end
              end
              local.get 0
              local.get 1
              call $dynrt_lib_modc__fn174
            end
          end
          br 1 (;@2;)
        end
      end
    end
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn175
    i32.const 125
    i32.eq
    if  ;; label = @1
      global.get $dynrt_lib_modc_global20
      i32.const 1
      i32.add
      global.set $dynrt_lib_modc_global20
    end
    local.get 12
    i32.const 0
    i32.gt_s
    if (result i32)  ;; label = @1
      i32.const 1
    else
      local.get 9
      i32.const 0
      i32.gt_s
    end
    if (result i32)  ;; label = @1
      i32.const 1
    else
      local.get 10
      i32.const -1
      i32.ne
    end
    if  ;; label = @1
      block  ;; label = @2
        local.get 10
        local.tee 26
        local.set 10
        local.get 10
        i32.const -1
        i32.eq
        if  ;; label = @3
          call $dynrt_lib_modc_dynArray
          local.set 10
        end
        local.get 11
        local.tee 27
        local.set 11
        local.get 12
        local.tee 28
        local.set 12
        local.get 11
        local.get 12
        local.get 7
        local.get 9
        call $dynrt_lib_modc__fn5
        local.set 12
        nop
        local.set 11
        local.get 10
        local.get 11
        local.get 12
        call $dynrt_lib_modc_dynString
        local.get 8
        call $dynrt_lib_modc__fn152
        local.set 7
        local.get 5
        i32.const 1110
        i32.const 6
        local.get 7
        call $dynrt_lib_modc_dynSet
      end
    end
    local.get 5
    i32.const 959
    i32.const 7
    local.get 4
    call $dynrt_lib_modc_dynSet
    local.get 6
    i32.const -1
    i32.ne
    if  ;; label = @1
      local.get 5
      i32.const 1098
      i32.const 12
      local.get 6
      call $dynrt_lib_modc_dynSet
    end
    local.get 3
    i32.const 0
    i32.gt_s
    if  ;; label = @1
      local.get 5
      i32.const 1238
      i32.const 6
      local.get 2
      local.get 3
      call $dynrt_lib_modc_dynString
      call $dynrt_lib_modc_dynSet
    end
    local.get 5
    local.tee 35
    return)
  (func $dynrt_lib_modc__fn213 (param i32 i32)
    (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn212
    local.set 2
    local.get 2
    i32.const 1238
    i32.const 6
    call $dynrt_lib_modc_dynGet
    local.set 3
    local.get 3
    i32.const -1
    i32.ne
    if (result i32)  ;; label = @1
      global.get $dynrt_lib_modc_global22
      i32.const 1
      i32.eq
    else
      i32.const 0
    end
    if  ;; label = @1
      block  ;; label = @2
        local.get 3
        call $dynrt_lib_modc__fn85
        global.get $dynrt_lib_modc_global2
        local.set 3
        global.get $dynrt_lib_modc_global3
        local.set 4
        local.get 4
        i32.const 0
        i32.gt_s
        if  ;; label = @3
          global.get $dynrt_lib_modc_global21
          local.get 3
          local.get 4
          local.get 2
          call $dynrt_lib_modc_dynSet
        end
      end
    end)
  (func $dynrt_lib_modc__fn214 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.tee 5
    local.set 2
    local.get 2
    i32.const 8
    i32.add
    i32.load
    i32.const 6
    i32.ne
    if  ;; label = @1
      call $dynrt_lib_modc_dynUndefined
      return
    end
    call $dynrt_lib_modc_dynObject
    local.set 2
    local.get 0
    i32.const 959
    i32.const 7
    call $dynrt_lib_modc_dynGet
    local.set 3
    local.get 3
    i32.const -1
    i32.ne
    if  ;; label = @1
      block  ;; label = @2
        local.get 2
        local.set 4
        local.get 4
        i32.const 8
        i32.add
        i32.const 8
        i32.add
        local.get 3
        i32.store
      end
    end
    local.get 0
    i32.const 1110
    i32.const 6
    call $dynrt_lib_modc_dynGet
    local.set 3
    local.get 3
    i32.const -1
    i32.ne
    if  ;; label = @1
      block  ;; label = @2
        local.get 3
        local.set 4
        local.get 4
        i32.const 8
        i32.add
        i32.load
        i32.const 7
        i32.eq
        if  ;; label = @3
          local.get 3
          local.get 1
          local.get 2
          call $dynrt_lib_modc__fn161
          drop
        end
      end
    end
    local.get 2
    return)
  (func $dynrt_lib_modc__fn215 (param i32 i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn174
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn175
    local.set 2
    local.get 2
    i32.const 123
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_lib_modc_global20
        i32.const 1
        i32.add
        global.set $dynrt_lib_modc_global20
        global.get $dynrt_lib_modc_global21
        local.set 2
        local.get 2
        call $dynrt_lib_modc__fn157
        local.set 3
        local.get 3
        local.tee 14
        global.set $dynrt_lib_modc_global21
        local.get 3
        call $dynrt_lib_modc__fn61
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn216
        call $dynrt_lib_modc__fn62
        local.get 2
        local.tee 15
        global.set $dynrt_lib_modc_global21
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn174
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn175
        i32.const 125
        i32.eq
        if  ;; label = @3
          global.get $dynrt_lib_modc_global20
          i32.const 1
          i32.add
          global.set $dynrt_lib_modc_global20
        end
        return
      end
    end
    local.get 2
    i32.const 59
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_lib_modc_global20
        i32.const 1
        i32.add
        global.set $dynrt_lib_modc_global20
        return
      end
    end
    local.get 2
    i32.const 0
    call $dynrt_lib_modc__fn173
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_lib_modc_global20
        local.set 2
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn192
        global.get $dynrt_lib_modc_global2
        local.set 3
        global.get $dynrt_lib_modc_global3
        local.set 4
        local.get 3
        local.get 4
        i32.const 1183
        i32.const 3
        call $dynrt_lib_modc__fn169
        i32.const 1
        i32.eq
        if (result i32)  ;; label = @3
          i32.const 1
        else
          local.get 3
          local.get 4
          i32.const 1178
          i32.const 5
          call $dynrt_lib_modc__fn169
          i32.const 1
          i32.eq
        end
        if (result i32)  ;; label = @3
          i32.const 1
        else
          local.get 3
          local.get 4
          i32.const 1186
          i32.const 3
          call $dynrt_lib_modc__fn169
          i32.const 1
          i32.eq
        end
        if  ;; label = @3
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn193
            return
          end
        end
        local.get 3
        local.get 4
        i32.const 1244
        i32.const 2
        call $dynrt_lib_modc__fn169
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn195
            return
          end
        end
        local.get 3
        local.get 4
        i32.const 1246
        i32.const 5
        call $dynrt_lib_modc__fn169
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn196
            return
          end
        end
        local.get 3
        local.get 4
        i32.const 1251
        i32.const 2
        call $dynrt_lib_modc__fn169
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn197
            return
          end
        end
        local.get 3
        local.get 4
        i32.const 1253
        i32.const 3
        call $dynrt_lib_modc__fn169
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn198
            return
          end
        end
        local.get 3
        local.get 4
        i32.const 1256
        i32.const 6
        call $dynrt_lib_modc__fn169
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn202
            return
          end
        end
        local.get 3
        local.get 4
        i32.const 1262
        i32.const 3
        call $dynrt_lib_modc__fn169
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn205
            return
          end
        end
        local.get 3
        local.get 4
        i32.const 1265
        i32.const 5
        call $dynrt_lib_modc__fn169
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn189
            local.set 2
            global.get $dynrt_lib_modc_global22
            i32.const 1
            i32.eq
            if  ;; label = @5
              block  ;; label = @6
                i32.const 1
                global.set $dynrt_lib_modc_global29
                local.get 2
                global.set $dynrt_lib_modc_global30
              end
            end
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn174
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn175
            i32.const 59
            i32.eq
            if  ;; label = @5
              global.get $dynrt_lib_modc_global20
              i32.const 1
              i32.add
              global.set $dynrt_lib_modc_global20
            end
            return
          end
        end
        local.get 3
        local.get 4
        i32.const 1270
        i32.const 6
        call $dynrt_lib_modc__fn169
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn194
            return
          end
        end
        local.get 3
        local.get 4
        i32.const 998
        i32.const 8
        call $dynrt_lib_modc__fn169
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 0
            local.get 1
            i32.const 0
            call $dynrt_lib_modc__fn211
            return
          end
        end
        local.get 3
        local.get 4
        i32.const 1276
        i32.const 5
        call $dynrt_lib_modc__fn169
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            global.get $dynrt_lib_modc_global20
            local.set 5
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn174
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn175
            i32.const 0
            call $dynrt_lib_modc__fn173
            i32.const 1
            i32.eq
            if  ;; label = @5
              block  ;; label = @6
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn192
                global.get $dynrt_lib_modc_global2
                local.set 6
                global.get $dynrt_lib_modc_global3
                local.set 7
                local.get 6
                local.get 7
                i32.const 998
                i32.const 8
                call $dynrt_lib_modc__fn169
                i32.const 1
                i32.eq
                if  ;; label = @7
                  block  ;; label = @8
                    local.get 0
                    local.get 1
                    i32.const 1
                    call $dynrt_lib_modc__fn211
                    return
                  end
                end
              end
            end
            local.get 5
            global.set $dynrt_lib_modc_global20
          end
        end
        local.get 3
        local.get 4
        i32.const 1006
        i32.const 5
        call $dynrt_lib_modc__fn169
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn213
            return
          end
        end
        local.get 3
        local.get 4
        i32.const 1281
        i32.const 5
        call $dynrt_lib_modc__fn169
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            global.get $dynrt_lib_modc_global22
            i32.const 1
            i32.eq
            if  ;; label = @5
              i32.const 1
              global.set $dynrt_lib_modc_global27
            end
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn174
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn175
            i32.const 59
            i32.eq
            if  ;; label = @5
              global.get $dynrt_lib_modc_global20
              i32.const 1
              i32.add
              global.set $dynrt_lib_modc_global20
            end
            return
          end
        end
        local.get 3
        local.get 4
        i32.const 1286
        i32.const 8
        call $dynrt_lib_modc__fn169
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            global.get $dynrt_lib_modc_global22
            i32.const 1
            i32.eq
            if  ;; label = @5
              i32.const 1
              global.set $dynrt_lib_modc_global28
            end
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn174
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn175
            i32.const 59
            i32.eq
            if  ;; label = @5
              global.get $dynrt_lib_modc_global20
              i32.const 1
              i32.add
              global.set $dynrt_lib_modc_global20
            end
            return
          end
        end
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn174
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn175
        local.set 5
        local.get 5
        i32.const 61
        i32.eq
        if (result i32)  ;; label = @3
          local.get 0
          local.get 1
          call $dynrt_lib_modc__fn176
          i32.const 61
          i32.ne
        else
          i32.const 0
        end
        if (result i32)  ;; label = @3
          local.get 0
          local.get 1
          call $dynrt_lib_modc__fn176
          i32.const 62
          i32.ne
        else
          i32.const 0
        end
        if  ;; label = @3
          block  ;; label = @4
            global.get $dynrt_lib_modc_global20
            i32.const 1
            i32.add
            global.set $dynrt_lib_modc_global20
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn189
            local.set 2
            global.get $dynrt_lib_modc_global22
            i32.const 1
            i32.eq
            if  ;; label = @5
              global.get $dynrt_lib_modc_global21
              local.get 3
              local.get 4
              local.get 2
              call $dynrt_lib_modc__fn158
            end
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn174
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn175
            i32.const 59
            i32.eq
            if  ;; label = @5
              global.get $dynrt_lib_modc_global20
              i32.const 1
              i32.add
              global.set $dynrt_lib_modc_global20
            end
            return
          end
        end
        local.get 5
        i32.const 43
        i32.eq
        if (result i32)  ;; label = @3
          local.get 0
          local.get 1
          call $dynrt_lib_modc__fn176
          i32.const 43
          i32.eq
        else
          i32.const 0
        end
        if  ;; label = @3
          block  ;; label = @4
            global.get $dynrt_lib_modc_global20
            i32.const 2
            i32.add
            global.set $dynrt_lib_modc_global20
            global.get $dynrt_lib_modc_global22
            i32.const 1
            i32.eq
            if  ;; label = @5
              block  ;; label = @6
                global.get $dynrt_lib_modc_global21
                local.get 3
                local.get 4
                call $dynrt_lib_modc__fn156
                local.set 5
                global.get $dynrt_lib_modc_global21
                local.get 3
                local.get 4
                local.get 5
                f64.const 0x1.0p+0 (;=1;)
                call $dynrt_lib_modc_dynNumber
                call $dynrt_lib_modc_dynAdd
                call $dynrt_lib_modc__fn158
              end
            end
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn174
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn175
            i32.const 59
            i32.eq
            if  ;; label = @5
              global.get $dynrt_lib_modc_global20
              i32.const 1
              i32.add
              global.set $dynrt_lib_modc_global20
            end
            return
          end
        end
        local.get 5
        i32.const 45
        i32.eq
        if (result i32)  ;; label = @3
          local.get 0
          local.get 1
          call $dynrt_lib_modc__fn176
          i32.const 45
          i32.eq
        else
          i32.const 0
        end
        if  ;; label = @3
          block  ;; label = @4
            global.get $dynrt_lib_modc_global20
            i32.const 2
            i32.add
            global.set $dynrt_lib_modc_global20
            global.get $dynrt_lib_modc_global22
            i32.const 1
            i32.eq
            if  ;; label = @5
              block  ;; label = @6
                global.get $dynrt_lib_modc_global21
                local.get 3
                local.get 4
                call $dynrt_lib_modc__fn156
                local.set 5
                global.get $dynrt_lib_modc_global21
                local.get 3
                local.get 4
                local.get 5
                f64.const 0x1.0p+0 (;=1;)
                call $dynrt_lib_modc_dynNumber
                call $dynrt_lib_modc_dynSub
                call $dynrt_lib_modc__fn158
              end
            end
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn174
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn175
            i32.const 59
            i32.eq
            if  ;; label = @5
              global.get $dynrt_lib_modc_global20
              i32.const 1
              i32.add
              global.set $dynrt_lib_modc_global20
            end
            return
          end
        end
        local.get 5
        i32.const 43
        i32.eq
        if (result i32)  ;; label = @3
          i32.const 1
        else
          local.get 5
          i32.const 45
          i32.eq
        end
        if (result i32)  ;; label = @3
          i32.const 1
        else
          local.get 5
          i32.const 42
          i32.eq
        end
        if (result i32)  ;; label = @3
          i32.const 1
        else
          local.get 5
          i32.const 47
          i32.eq
        end
        if (result i32)  ;; label = @3
          local.get 0
          local.get 1
          call $dynrt_lib_modc__fn176
          i32.const 61
          i32.eq
        else
          i32.const 0
        end
        if  ;; label = @3
          block  ;; label = @4
            local.get 5
            local.set 2
            global.get $dynrt_lib_modc_global20
            i32.const 2
            i32.add
            global.set $dynrt_lib_modc_global20
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn189
            local.set 6
            global.get $dynrt_lib_modc_global22
            i32.const 1
            i32.eq
            if  ;; label = @5
              block  ;; label = @6
                global.get $dynrt_lib_modc_global21
                local.get 3
                local.get 4
                call $dynrt_lib_modc__fn156
                local.set 5
                local.get 5
                local.tee 16
                drop
                local.get 2
                i32.const 43
                i32.eq
                if  ;; label = @7
                  local.get 5
                  local.get 6
                  call $dynrt_lib_modc_dynAdd
                  local.set 5
                else
                  local.get 2
                  i32.const 45
                  i32.eq
                  if  ;; label = @8
                    local.get 5
                    local.get 6
                    call $dynrt_lib_modc_dynSub
                    local.set 5
                  else
                    local.get 2
                    i32.const 42
                    i32.eq
                    if  ;; label = @9
                      local.get 5
                      local.get 6
                      call $dynrt_lib_modc_dynMul
                      local.set 5
                    else
                      local.get 5
                      local.get 6
                      call $dynrt_lib_modc_dynDiv
                      local.set 5
                    end
                  end
                end
                global.get $dynrt_lib_modc_global21
                local.get 3
                local.get 4
                local.get 5
                call $dynrt_lib_modc__fn158
              end
            end
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn174
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn175
            i32.const 59
            i32.eq
            if  ;; label = @5
              global.get $dynrt_lib_modc_global20
              i32.const 1
              i32.add
              global.set $dynrt_lib_modc_global20
            end
            return
          end
        end
        local.get 5
        i32.const 46
        i32.eq
        if (result i32)  ;; label = @3
          i32.const 1
        else
          local.get 5
          i32.const 91
          i32.eq
        end
        if  ;; label = @3
          block  ;; label = @4
            global.get $dynrt_lib_modc_global21
            i32.const -1
            i32.eq
            if (result i32)  ;; label = @5
              call $dynrt_lib_modc_dynUndefined
            else
              global.get $dynrt_lib_modc_global21
              local.get 3
              local.get 4
              call $dynrt_lib_modc__fn156
            end
            local.set 3
            local.get 3
            i32.const -1
            i32.eq
            if  ;; label = @5
              call $dynrt_lib_modc_dynUndefined
              local.set 3
            end
            i32.const 0
            local.set 4
            i32.const 1
            local.set 5
            block  ;; label = @5
              loop  ;; label = @6
                block  ;; label = @7
                  local.get 5
                  i32.const 1
                  i32.eq
                  i32.eqz
                  br_if 2 (;@5;)
                  block  ;; label = @8
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn174
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn175
                    local.set 6
                    i32.const 0
                    local.tee 19
                    local.set 7
                    i32.const 520
                    local.set 8
                    local.get 19
                    local.set 9
                    local.get 19
                    local.set 10
                    local.get 6
                    i32.const 46
                    i32.eq
                    if  ;; label = @9
                      block  ;; label = @10
                        global.get $dynrt_lib_modc_global20
                        i32.const 1
                        local.tee 17
                        i32.add
                        global.set $dynrt_lib_modc_global20
                        local.get 0
                        local.get 1
                        call $dynrt_lib_modc__fn192
                        global.get $dynrt_lib_modc_global2
                        local.set 8
                        global.get $dynrt_lib_modc_global3
                        local.set 9
                        i32.const 1
                        local.tee 18
                        local.set 7
                      end
                    else
                      local.get 6
                      i32.const 91
                      i32.eq
                      if  ;; label = @10
                        block  ;; label = @11
                          global.get $dynrt_lib_modc_global20
                          i32.const 1
                          i32.add
                          global.set $dynrt_lib_modc_global20
                          local.get 0
                          local.get 1
                          call $dynrt_lib_modc__fn189
                          local.set 10
                          local.get 0
                          local.get 1
                          call $dynrt_lib_modc__fn174
                          local.get 0
                          local.get 1
                          call $dynrt_lib_modc__fn175
                          i32.const 93
                          i32.eq
                          if  ;; label = @12
                            global.get $dynrt_lib_modc_global20
                            i32.const 1
                            i32.add
                            global.set $dynrt_lib_modc_global20
                          end
                        end
                      else
                        i32.const 0
                        local.set 5
                      end
                    end
                    local.get 5
                    i32.const 1
                    i32.eq
                    if  ;; label = @9
                      block  ;; label = @10
                        local.get 0
                        local.get 1
                        call $dynrt_lib_modc__fn174
                        local.get 0
                        local.get 1
                        call $dynrt_lib_modc__fn175
                        local.set 11
                        local.get 0
                        local.get 1
                        call $dynrt_lib_modc__fn176
                        local.set 6
                        local.get 11
                        i32.const 61
                        i32.eq
                        if (result i32)  ;; label = @11
                          local.get 6
                          i32.const 61
                          i32.ne
                        else
                          i32.const 0
                        end
                        if (result i32)  ;; label = @11
                          local.get 6
                          i32.const 62
                          i32.ne
                        else
                          i32.const 0
                        end
                        if (result i32)  ;; label = @11
                          i32.const 1
                        else
                          i32.const 0
                        end
                        local.set 12
                        i32.const 0
                        local.set 13
                        local.get 11
                        i32.const 43
                        i32.eq
                        if (result i32)  ;; label = @11
                          i32.const 1
                        else
                          local.get 11
                          i32.const 45
                          i32.eq
                        end
                        if (result i32)  ;; label = @11
                          i32.const 1
                        else
                          local.get 11
                          i32.const 42
                          i32.eq
                        end
                        if (result i32)  ;; label = @11
                          i32.const 1
                        else
                          local.get 11
                          i32.const 47
                          i32.eq
                        end
                        if (result i32)  ;; label = @11
                          local.get 6
                          i32.const 61
                          i32.eq
                        else
                          i32.const 0
                        end
                        if  ;; label = @11
                          i32.const 1
                          local.set 13
                        end
                        local.get 12
                        i32.const 1
                        i32.eq
                        if (result i32)  ;; label = @11
                          i32.const 1
                        else
                          local.get 13
                          i32.const 1
                          i32.eq
                        end
                        if  ;; label = @11
                          block  ;; label = @12
                            local.get 12
                            i32.const 1
                            i32.eq
                            if  ;; label = @13
                              global.get $dynrt_lib_modc_global20
                              i32.const 1
                              i32.add
                              global.set $dynrt_lib_modc_global20
                            else
                              global.get $dynrt_lib_modc_global20
                              i32.const 2
                              i32.add
                              global.set $dynrt_lib_modc_global20
                            end
                            local.get 0
                            local.get 1
                            call $dynrt_lib_modc__fn189
                            local.set 6
                            global.get $dynrt_lib_modc_global22
                            i32.const 1
                            i32.eq
                            if  ;; label = @13
                              block  ;; label = @14
                                local.get 6
                                local.set 5
                                local.get 13
                                i32.const 1
                                i32.eq
                                if  ;; label = @15
                                  block  ;; label = @16
                                    local.get 7
                                    i32.const 1
                                    i32.eq
                                    if  ;; label = @17
                                      local.get 3
                                      local.get 8
                                      local.get 9
                                      call $dynrt_lib_modc_dynMember
                                      local.set 5
                                    else
                                      local.get 3
                                      local.get 10
                                      call $dynrt_lib_modc_dynIndexValue
                                      local.set 5
                                    end
                                    local.get 11
                                    i32.const 43
                                    i32.eq
                                    if  ;; label = @17
                                      local.get 5
                                      local.get 6
                                      call $dynrt_lib_modc_dynAdd
                                      local.set 5
                                    else
                                      local.get 11
                                      i32.const 45
                                      i32.eq
                                      if  ;; label = @18
                                        local.get 5
                                        local.get 6
                                        call $dynrt_lib_modc_dynSub
                                        local.set 5
                                      else
                                        local.get 11
                                        i32.const 42
                                        i32.eq
                                        if  ;; label = @19
                                          local.get 5
                                          local.get 6
                                          call $dynrt_lib_modc_dynMul
                                          local.set 5
                                        else
                                          local.get 5
                                          local.get 6
                                          call $dynrt_lib_modc_dynDiv
                                          local.set 5
                                        end
                                      end
                                    end
                                  end
                                end
                                local.get 7
                                i32.const 1
                                i32.eq
                                if  ;; label = @15
                                  local.get 3
                                  local.get 8
                                  local.get 9
                                  local.get 5
                                  call $dynrt_lib_modc__fn171
                                else
                                  local.get 3
                                  local.get 10
                                  local.get 5
                                  call $dynrt_lib_modc__fn138
                                end
                              end
                            end
                            i32.const 1
                            local.set 4
                            i32.const 0
                            local.set 5
                          end
                        else
                          local.get 7
                          i32.const 1
                          i32.eq
                          if  ;; label = @12
                            local.get 3
                            local.get 8
                            local.get 9
                            call $dynrt_lib_modc_dynMember
                            local.set 3
                          else
                            local.get 3
                            local.get 10
                            call $dynrt_lib_modc_dynIndexValue
                            local.set 3
                          end
                        end
                      end
                    end
                  end
                  br 1 (;@6;)
                end
              end
            end
            local.get 4
            i32.const 1
            i32.eq
            if  ;; label = @5
              block  ;; label = @6
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn174
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn175
                i32.const 59
                i32.eq
                if  ;; label = @7
                  global.get $dynrt_lib_modc_global20
                  i32.const 1
                  i32.add
                  global.set $dynrt_lib_modc_global20
                end
                return
              end
            end
            local.get 2
            global.set $dynrt_lib_modc_global20
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn189
            local.set 2
            global.get $dynrt_lib_modc_global22
            i32.const 1
            i32.eq
            if  ;; label = @5
              local.get 2
              global.set $dynrt_lib_modc_global26
            end
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn174
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn175
            i32.const 59
            i32.eq
            if  ;; label = @5
              global.get $dynrt_lib_modc_global20
              i32.const 1
              i32.add
              global.set $dynrt_lib_modc_global20
            end
            return
          end
        end
        local.get 2
        global.set $dynrt_lib_modc_global20
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn189
        local.set 2
        global.get $dynrt_lib_modc_global22
        i32.const 1
        i32.eq
        if  ;; label = @3
          local.get 2
          global.set $dynrt_lib_modc_global26
        end
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn174
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn175
        i32.const 59
        i32.eq
        if  ;; label = @3
          global.get $dynrt_lib_modc_global20
          i32.const 1
          i32.add
          global.set $dynrt_lib_modc_global20
        end
        return
      end
    end
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn189
    local.set 2
    global.get $dynrt_lib_modc_global22
    i32.const 1
    i32.eq
    if  ;; label = @1
      local.get 2
      global.set $dynrt_lib_modc_global26
    end
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn174
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn175
    i32.const 59
    i32.eq
    if  ;; label = @1
      global.get $dynrt_lib_modc_global20
      i32.const 1
      i32.add
      global.set $dynrt_lib_modc_global20
    end)
  (func $dynrt_lib_modc__fn216 (param i32 i32)
    (local i32) (local i32)
    i32.const 1
    local.set 2
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 2
          i32.const 1
          i32.eq
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn174
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn175
            local.set 3
            local.get 3
            i32.const -1
            i32.eq
            if (result i32)  ;; label = @5
              i32.const 1
            else
              local.get 3
              i32.const 125
              i32.eq
            end
            if  ;; label = @5
              i32.const 0
              local.set 2
            else
              block  ;; label = @6
                call $dynrt_lib_modc__fn73
                global.get $dynrt_lib_modc_global22
                local.set 3
                global.get $dynrt_lib_modc_global24
                i32.const 1
                i32.eq
                if (result i32)  ;; label = @7
                  i32.const 1
                else
                  global.get $dynrt_lib_modc_global27
                  i32.const 1
                  i32.eq
                end
                if (result i32)  ;; label = @7
                  i32.const 1
                else
                  global.get $dynrt_lib_modc_global28
                  i32.const 1
                  i32.eq
                end
                if (result i32)  ;; label = @7
                  i32.const 1
                else
                  global.get $dynrt_lib_modc_global29
                  i32.const 1
                  i32.eq
                end
                if  ;; label = @7
                  i32.const 0
                  global.set $dynrt_lib_modc_global22
                end
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn215
                local.get 3
                global.set $dynrt_lib_modc_global22
              end
            end
          end
          br 1 (;@2;)
        end
      end
    end)
  (func $dynrt_lib_modc_dynRun (param i32 i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 2
    call $dynrt_lib_modc__fn61
    i32.const 0
    local.tee 4
    global.set $dynrt_lib_modc_global20
    local.get 2
    local.tee 5
    global.set $dynrt_lib_modc_global21
    i32.const 1
    global.set $dynrt_lib_modc_global22
    i32.const 0
    local.tee 6
    global.set $dynrt_lib_modc_global24
    call $dynrt_lib_modc_dynUndefined
    global.set $dynrt_lib_modc_global25
    i32.const 0
    local.tee 7
    global.set $dynrt_lib_modc_global29
    call $dynrt_lib_modc_dynUndefined
    global.set $dynrt_lib_modc_global26
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn216
    global.get $dynrt_lib_modc_global24
    i32.const 1
    i32.eq
    if (result i32)  ;; label = @1
      global.get $dynrt_lib_modc_global25
    else
      global.get $dynrt_lib_modc_global26
    end
    local.set 3
    call $dynrt_lib_modc__fn62
    local.get 3
    return)
  (func $dynrt_lib_modc__fn218 (param i32) (result i32)
    local.get 0
    i32.const 65
    i32.ge_s
    if (result i32)  ;; label = @1
      local.get 0
      i32.const 90
      i32.le_s
    else
      i32.const 0
    end
    if  ;; label = @1
      local.get 0
      i32.const 65
      i32.sub
      return
    end
    local.get 0
    i32.const 97
    i32.ge_s
    if (result i32)  ;; label = @1
      local.get 0
      i32.const 122
      i32.le_s
    else
      i32.const 0
    end
    if  ;; label = @1
      local.get 0
      i32.const 71
      i32.sub
      return
    end
    local.get 0
    i32.const 48
    i32.ge_s
    if (result i32)  ;; label = @1
      local.get 0
      i32.const 57
      i32.le_s
    else
      i32.const 0
    end
    if  ;; label = @1
      local.get 0
      i32.const 4
      i32.add
      return
    end
    local.get 0
    i32.const 43
    i32.eq
    if  ;; label = @1
      i32.const 62
      return
    end
    local.get 0
    i32.const 47
    i32.eq
    if  ;; label = @1
      i32.const 63
      return
    end
    i32.const -1
    return)
  (func $dynrt_lib_modc_dynRunB64 (param i32 i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 1
    local.set 3
    i32.const 8
    local.get 3
    i32.add
    i32.const 4
    i32.add
    call $dynrt_lib_modc__fn45
    local.set 4
    i32.const 0
    local.tee 16
    local.set 5
    local.get 16
    local.set 6
    local.get 16
    local.set 7
    local.get 16
    local.set 8
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 8
          local.get 3
          i32.lt_s
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 0
            local.get 1
            local.get 8
            call $dynrt_lib_modc__fn9
            call $dynrt_lib_modc__fn218
            local.set 9
            local.get 8
            local.tee 15
            i32.const 1
            i32.add
            local.set 8
            local.get 9
            i32.const 0
            i32.ge_s
            if  ;; label = @5
              block  ;; label = @6
                local.get 5
                i32.const 6
                local.tee 14
                i32.shl
                local.get 9
                i32.or
                local.set 5
                local.get 6
                local.get 14
                i32.add
                local.set 6
                local.get 6
                i32.const 8
                i32.ge_s
                if  ;; label = @7
                  block  ;; label = @8
                    local.get 6
                    local.tee 10
                    i32.const 8
                    local.tee 11
                    i32.sub
                    local.set 6
                    local.get 5
                    local.get 6
                    local.tee 12
                    i32.shr_s
                    i32.const 255
                    i32.and
                    local.set 9
                    local.get 4
                    i32.const 8
                    i32.add
                    local.get 7
                    i32.add
                    local.get 9
                    i32.store8
                    local.get 7
                    local.tee 13
                    i32.const 1
                    i32.add
                    local.set 7
                  end
                end
              end
            end
          end
          br 1 (;@2;)
        end
      end
    end
    call $dynrt_lib_modc__fn53
    local.set 3
    local.get 3
    i32.const 8
    i32.add
    i32.const 4
    i32.store
    local.get 3
    i32.const 8
    i32.add
    i32.const 4
    i32.add
    local.get 4
    i32.store
    local.get 3
    i32.const 8
    i32.add
    i32.const 8
    i32.add
    local.get 7
    i32.store
    local.get 3
    local.tee 17
    local.set 3
    local.get 3
    call $dynrt_lib_modc__fn85
    global.get $dynrt_lib_modc_global2
    local.set 3
    global.get $dynrt_lib_modc_global3
    local.set 4
    local.get 3
    local.get 4
    local.get 2
    call $dynrt_lib_modc_dynRun
    return)
  ;; data from dynrt_lib_modc
  (data (;0;) (i32.const 520) "")
  (data (;1;) (i32.const 520) "false")
  (data (;2;) (i32.const 525) "true")
  (data (;3;) (i32.const 529) "null")
  (data (;4;) (i32.const 533) "undefined")
  (data (;5;) (i32.const 542) "push")
  (data (;6;) (i32.const 546) "indexOf")
  (data (;7;) (i32.const 553) "includes")
  (data (;8;) (i32.const 561) "join")
  (data (;9;) (i32.const 565) ",")
  (data (;10;) (i32.const 566) "slice")
  (data (;11;) (i32.const 571) "concat")
  (data (;12;) (i32.const 577) "reverse")
  (data (;13;) (i32.const 584) "pop")
  (data (;14;) (i32.const 587) "shift")
  (data (;15;) (i32.const 592) "unshift")
  (data (;16;) (i32.const 599) "at")
  (data (;17;) (i32.const 601) "lastIndexOf")
  (data (;18;) (i32.const 612) "map")
  (data (;19;) (i32.const 615) "filter")
  (data (;20;) (i32.const 621) "forEach")
  (data (;21;) (i32.const 628) "reduce")
  (data (;22;) (i32.const 634) "find")
  (data (;23;) (i32.const 638) "findIndex")
  (data (;24;) (i32.const 647) "some")
  (data (;25;) (i32.const 651) "every")
  (data (;26;) (i32.const 656) "sort")
  (data (;27;) (i32.const 660) "charAt")
  (data (;28;) (i32.const 666) "charCodeAt")
  (data (;29;) (i32.const 676) "toUpperCase")
  (data (;30;) (i32.const 687) "toLowerCase")
  (data (;31;) (i32.const 698) "trim")
  (data (;32;) (i32.const 702) "startsWith")
  (data (;33;) (i32.const 712) "endsWith")
  (data (;34;) (i32.const 720) "repeat")
  (data (;35;) (i32.const 726) "padStart")
  (data (;36;) (i32.const 734) " ")
  (data (;37;) (i32.const 735) "padEnd")
  (data (;38;) (i32.const 741) "split")
  (data (;39;) (i32.const 746) "match")
  (data (;40;) (i32.const 751) "__regex")
  (data (;41;) (i32.const 758) "create")
  (data (;42;) (i32.const 764) "keys")
  (data (;43;) (i32.const 768) "values")
  (data (;44;) (i32.const 774) "entries")
  (data (;45;) (i32.const 781) "assign")
  (data (;46;) (i32.const 787) "floor")
  (data (;47;) (i32.const 792) "ceil")
  (data (;48;) (i32.const 796) "round")
  (data (;49;) (i32.const 801) "abs")
  (data (;50;) (i32.const 804) "sqrt")
  (data (;51;) (i32.const 808) "sign")
  (data (;52;) (i32.const 812) "trunc")
  (data (;53;) (i32.const 817) "max")
  (data (;54;) (i32.const 820) "min")
  (data (;55;) (i32.const 823) "pow")
  (data (;56;) (i32.const 826) "\22")
  (data (;57;) (i32.const 827) "\5c\22")
  (data (;58;) (i32.const 829) "\5c\5c")
  (data (;59;) (i32.const 831) "\5cn")
  (data (;60;) (i32.const 833) "\5cr")
  (data (;61;) (i32.const 835) "\5ct")
  (data (;62;) (i32.const 837) "[")
  (data (;63;) (i32.const 838) "]")
  (data (;64;) (i32.const 839) "{")
  (data (;65;) (i32.const 840) ":")
  (data (;66;) (i32.const 841) "}")
  (data (;67;) (i32.const 842) "__mapk")
  (data (;68;) (i32.const 848) "__mapv")
  (data (;69;) (i32.const 854) "__setk")
  (data (;70;) (i32.const 860) "set")
  (data (;71;) (i32.const 863) "get")
  (data (;72;) (i32.const 866) "has")
  (data (;73;) (i32.const 869) "delete")
  (data (;74;) (i32.const 875) "add")
  (data (;75;) (i32.const 878) "test")
  (data (;76;) (i32.const 882) "exec")
  (data (;77;) (i32.const 886) "next")
  (data (;78;) (i32.const 890) "__genv")
  (data (;79;) (i32.const 896) "__geni")
  (data (;80;) (i32.const 902) "value")
  (data (;81;) (i32.const 907) "done")
  (data (;82;) (i32.const 911) "__promv")
  (data (;83;) (i32.const 918) "__promrej")
  (data (;84;) (i32.const 927) "resolve")
  (data (;85;) (i32.const 934) "reject")
  (data (;86;) (i32.const 940) "all")
  (data (;87;) (i32.const 943) "then")
  (data (;88;) (i32.const 947) "catch")
  (data (;89;) (i32.const 952) "finally")
  (data (;90;) (i32.const 959) "__proto")
  (data (;91;) (i32.const 966) "this")
  (data (;92;) (i32.const 970) "len")
  (data (;93;) (i32.const 973) "inc")
  (data (;94;) (i32.const 976) "size")
  (data (;95;) (i32.const 980) "__get_")
  (data (;96;) (i32.const 986) "length")
  (data (;97;) (i32.const 992) "__set_")
  (data (;98;) (i32.const 998) "function")
  (data (;99;) (i32.const 1006) "class")
  (data (;100;) (i32.const 1011) "yield")
  (data (;101;) (i32.const 1016) "Object")
  (data (;102;) (i32.const 1022) "console")
  (data (;103;) (i32.const 1029) "log")
  (data (;104;) (i32.const 1032) "error")
  (data (;105;) (i32.const 1037) "warn")
  (data (;106;) (i32.const 1041) "info")
  (data (;107;) (i32.const 1045) "\0a")
  (data (;108;) (i32.const 1046) "Math")
  (data (;109;) (i32.const 1050) "PI")
  (data (;110;) (i32.const 1052) "E")
  (data (;111;) (i32.const 1053) "JSON")
  (data (;112;) (i32.const 1057) "parse")
  (data (;113;) (i32.const 1062) "stringify")
  (data (;114;) (i32.const 1071) "Promise")
  (data (;115;) (i32.const 1078) "new")
  (data (;116;) (i32.const 1081) "Map")
  (data (;117;) (i32.const 1084) "Set")
  (data (;118;) (i32.const 1087) "RegExp")
  (data (;119;) (i32.const 1093) "super")
  (data (;120;) (i32.const 1098) "__superclass")
  (data (;121;) (i32.const 1110) "__ctor")
  (data (;122;) (i32.const 1116) "__superproto")
  (data (;123;) (i32.const 1128) "boolean")
  (data (;124;) (i32.const 1135) "number")
  (data (;125;) (i32.const 1141) "string")
  (data (;126;) (i32.const 1147) "object")
  (data (;127;) (i32.const 1153) "typeof")
  (data (;128;) (i32.const 1159) "await")
  (data (;129;) (i32.const 1164) "instanceof")
  (data (;130;) (i32.const 1174) "else")
  (data (;131;) (i32.const 1178) "const")
  (data (;132;) (i32.const 1183) "let")
  (data (;133;) (i32.const 1186) "var")
  (data (;134;) (i32.const 1189) "of")
  (data (;135;) (i32.const 1191) "in")
  (data (;136;) (i32.const 1193) "case")
  (data (;137;) (i32.const 1197) "default")
  (data (;138;) (i32.const 1204) "extends")
  (data (;139;) (i32.const 1211) "static")
  (data (;140;) (i32.const 1217) "constructor")
  (data (;141;) (i32.const 1228) "this.")
  (data (;142;) (i32.const 1233) " = ")
  (data (;143;) (i32.const 1236) "; ")
  (data (;144;) (i32.const 1238) "__name")
  (data (;145;) (i32.const 1244) "if")
  (data (;146;) (i32.const 1246) "while")
  (data (;147;) (i32.const 1251) "do")
  (data (;148;) (i32.const 1253) "for")
  (data (;149;) (i32.const 1256) "switch")
  (data (;150;) (i32.const 1262) "try")
  (data (;151;) (i32.const 1265) "throw")
  (data (;152;) (i32.const 1270) "return")
  (data (;153;) (i32.const 1276) "async")
  (data (;154;) (i32.const 1281) "break")
  (data (;155;) (i32.const 1286) "continue")
)