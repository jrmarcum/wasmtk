(module
  (import "wasi_snapshot_preview1" "proc_exit" (func $proc_exit (param i32)))
  (import "wasi_snapshot_preview1" "fd_write" (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (memory (export "memory") 2)
  (global $__heap_ptr (mut i32) (i32.const 746))
  (global $__d4s (mut i32) (i32.const 0))
  (global $__free_list (mut i32) (i32.const 0))
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
  (func $_start (export "_start")
    (local $s1 i32)
    (local $s2 i32)
    (local $s3 i32)
    (local $s4 i32)
    (local $__iface_tmp i32)
    (global.set $guard (call $__malloc (i32.const 40)))
      (i32.store (global.get $guard) (i32.const 1))
      (i32.store offset=4 (global.get $guard) (i32.const 8))
      (i32.store offset=8 (global.get $guard) (i32.const 0))
        (i32.store (i32.const 0) (i32.const 132))
          (i32.store (i32.const 4) (i32.const 0))
          (i32.store8 (i32.const 132) (i32.const 97))
          (i32.store8 (i32.const 133) (i32.const 98))
          (i32.store8 (i32.const 134) (i32.const 99))
          (i32.store8 (i32.const 135) (i32.const 32))
          (i32.store8 (i32.const 136) (i32.const 105))
          (i32.store8 (i32.const 137) (i32.const 110))
          (i32.store8 (i32.const 138) (i32.const 32))
          (i32.store8 (i32.const 139) (i32.const 120))
          (i32.store8 (i32.const 140) (i32.const 97))
          (i32.store8 (i32.const 141) (i32.const 98))
          (i32.store8 (i32.const 142) (i32.const 99))
          (i32.store8 (i32.const 143) (i32.const 121))
          (i32.store8 (i32.const 144) (i32.const 58))
          (i32.store8 (i32.const 145) (i32.const 32))
          (i32.store (i32.const 4) (i32.add (i32.const 14) (call $__i32_to_str (call $regex_lib_modc_reTest (i32.const 260) (i32.const 3) (i32.const 263) (i32.const 5)) (i32.const 146))))
          (i32.store8 (i32.add (i32.const 132) (i32.load (i32.const 4))) (i32.const 10))
          (i32.store (i32.const 4) (i32.add (i32.load (i32.const 4)) (i32.const 1)))
          (drop (call $fd_write
            (i32.const 1)
            (i32.const 0)
            (i32.const 1)
            (i32.const 128)))
    (call $check (if (result i32) (i32.eq (call $regex_lib_modc_reTest (i32.const 260) (i32.const 3) (i32.const 263) (i32.const 5)) (i32.const 1)) (then (i32.const 1)) (else (i32.const 0))))
    (call $check (if (result i32) (i32.eq (call $regex_lib_modc_reTest (i32.const 260) (i32.const 3) (i32.const 268) (i32.const 3)) (i32.const 0)) (then (i32.const 1)) (else (i32.const 0))))
    (call $check (if (result i32) (i32.eq (call $regex_lib_modc_reTest (i32.const 260) (i32.const 3) (i32.const 271) (i32.const 2)) (i32.const 0)) (then (i32.const 1)) (else (i32.const 0))))
    (local.set $s1 (call $regex_lib_modc_reSearch (i32.const 273) (i32.const 2) (i32.const 275) (i32.const 6)))
        (i32.store (i32.const 0) (i32.const 132))
          (i32.store (i32.const 4) (i32.const 0))
          (i32.store8 (i32.const 132) (i32.const 115))
          (i32.store8 (i32.const 133) (i32.const 101))
          (i32.store8 (i32.const 134) (i32.const 97))
          (i32.store8 (i32.const 135) (i32.const 114))
          (i32.store8 (i32.const 136) (i32.const 99))
          (i32.store8 (i32.const 137) (i32.const 104))
          (i32.store8 (i32.const 138) (i32.const 32))
          (i32.store8 (i32.const 139) (i32.const 99))
          (i32.store8 (i32.const 140) (i32.const 100))
          (i32.store8 (i32.const 141) (i32.const 58))
          (i32.store8 (i32.const 142) (i32.const 32))
          (i32.store (i32.const 4) (i32.add (i32.const 11) (call $__i32_to_str (local.get $s1) (i32.const 143))))
          (i32.store8 (i32.add (i32.const 132) (i32.add (i32.load (i32.const 4)) (i32.const 0))) (i32.const 32))
          (i32.store8 (i32.add (i32.const 132) (i32.add (i32.load (i32.const 4)) (i32.const 1))) (i32.const 46))
          (i32.store8 (i32.add (i32.const 132) (i32.add (i32.load (i32.const 4)) (i32.const 2))) (i32.const 46))
          (i32.store8 (i32.add (i32.const 132) (i32.add (i32.load (i32.const 4)) (i32.const 3))) (i32.const 32))
          (i32.store (i32.const 4) (i32.add (i32.load (i32.const 4)) (i32.const 4)))
          (i32.store (i32.const 4) (i32.add (i32.load (i32.const 4)) (call $__i32_to_str (call $regex_lib_modc_reEnd) (i32.add (i32.const 132) (i32.load (i32.const 4))))))
          (i32.store8 (i32.add (i32.const 132) (i32.load (i32.const 4))) (i32.const 10))
          (i32.store (i32.const 4) (i32.add (i32.load (i32.const 4)) (i32.const 1)))
          (drop (call $fd_write
            (i32.const 1)
            (i32.const 0)
            (i32.const 1)
            (i32.const 128)))
    (call $check (if (result i32) (i32.eq (local.get $s1) (i32.const 2)) (then (i32.const 1)) (else (i32.const 0))))
    (call $check (if (result i32) (i32.eq (call $regex_lib_modc_reEnd ) (i32.const 4)) (then (i32.const 1)) (else (i32.const 0))))
    (call $check (if (result i32) (i32.eq (call $regex_lib_modc_reSearch (i32.const 281) (i32.const 2) (i32.const 275) (i32.const 6)) (i32.const -1)) (then (i32.const 1)) (else (i32.const 0))))
    (call $check (if (result i32) (i32.eq (call $regex_lib_modc_reTest (i32.const 283) (i32.const 4) (i32.const 275) (i32.const 6)) (i32.const 1)) (then (i32.const 1)) (else (i32.const 0))))
    (call $check (if (result i32) (i32.eq (call $regex_lib_modc_reTest (i32.const 283) (i32.const 4) (i32.const 287) (i32.const 4)) (i32.const 0)) (then (i32.const 1)) (else (i32.const 0))))
    (call $check (if (result i32) (i32.eq (call $regex_lib_modc_reTest (i32.const 291) (i32.const 4) (i32.const 295) (i32.const 5)) (i32.const 1)) (then (i32.const 1)) (else (i32.const 0))))
    (call $check (if (result i32) (i32.eq (call $regex_lib_modc_reTest (i32.const 291) (i32.const 4) (i32.const 300) (i32.const 4)) (i32.const 0)) (then (i32.const 1)) (else (i32.const 0))))
    (call $check (if (result i32) (i32.eq (call $regex_lib_modc_reTest (i32.const 304) (i32.const 5) (i32.const 260) (i32.const 3)) (i32.const 1)) (then (i32.const 1)) (else (i32.const 0))))
    (call $check (if (result i32) (i32.eq (call $regex_lib_modc_reTest (i32.const 304) (i32.const 5) (i32.const 309) (i32.const 4)) (i32.const 0)) (then (i32.const 1)) (else (i32.const 0))))
    (call $check (if (result i32) (i32.eq (call $regex_lib_modc_reTest (i32.const 313) (i32.const 3) (i32.const 316) (i32.const 3)) (i32.const 1)) (then (i32.const 1)) (else (i32.const 0))))
    (call $check (if (result i32) (i32.eq (call $regex_lib_modc_reTest (i32.const 313) (i32.const 3) (i32.const 260) (i32.const 3)) (i32.const 1)) (then (i32.const 1)) (else (i32.const 0))))
    (call $check (if (result i32) (i32.eq (call $regex_lib_modc_reTest (i32.const 313) (i32.const 3) (i32.const 319) (i32.const 2)) (i32.const 0)) (then (i32.const 1)) (else (i32.const 0))))
    (call $check (if (result i32) (i32.eq (call $regex_lib_modc_reTest (i32.const 321) (i32.const 4) (i32.const 319) (i32.const 2)) (i32.const 1)) (then (i32.const 1)) (else (i32.const 0))))
    (call $check (if (result i32) (i32.eq (call $regex_lib_modc_reTest (i32.const 321) (i32.const 4) (i32.const 325) (i32.const 5)) (i32.const 1)) (then (i32.const 1)) (else (i32.const 0))))
    (call $check (if (result i32) (i32.eq (call $regex_lib_modc_reTest (i32.const 330) (i32.const 4) (i32.const 319) (i32.const 2)) (i32.const 0)) (then (i32.const 1)) (else (i32.const 0))))
    (call $check (if (result i32) (i32.eq (call $regex_lib_modc_reTest (i32.const 330) (i32.const 4) (i32.const 260) (i32.const 3)) (i32.const 1)) (then (i32.const 1)) (else (i32.const 0))))
    (call $check (if (result i32) (i32.eq (call $regex_lib_modc_reTest (i32.const 330) (i32.const 4) (i32.const 325) (i32.const 5)) (i32.const 1)) (then (i32.const 1)) (else (i32.const 0))))
    (call $check (if (result i32) (i32.eq (call $regex_lib_modc_reTest (i32.const 334) (i32.const 4) (i32.const 319) (i32.const 2)) (i32.const 1)) (then (i32.const 1)) (else (i32.const 0))))
    (call $check (if (result i32) (i32.eq (call $regex_lib_modc_reTest (i32.const 334) (i32.const 4) (i32.const 260) (i32.const 3)) (i32.const 1)) (then (i32.const 1)) (else (i32.const 0))))
    (call $check (if (result i32) (i32.eq (call $regex_lib_modc_reTest (i32.const 334) (i32.const 4) (i32.const 338) (i32.const 4)) (i32.const 0)) (then (i32.const 1)) (else (i32.const 0))))
    (local.set $s2 (call $regex_lib_modc_reSearch (i32.const 342) (i32.const 6) (i32.const 348) (i32.const 9)))
        (i32.store (i32.const 0) (i32.const 132))
          (i32.store (i32.const 4) (i32.const 0))
          (i32.store8 (i32.const 132) (i32.const 100))
          (i32.store8 (i32.const 133) (i32.const 105))
          (i32.store8 (i32.const 134) (i32.const 103))
          (i32.store8 (i32.const 135) (i32.const 105))
          (i32.store8 (i32.const 136) (i32.const 116))
          (i32.store8 (i32.const 137) (i32.const 115))
          (i32.store8 (i32.const 138) (i32.const 58))
          (i32.store8 (i32.const 139) (i32.const 32))
          (i32.store (i32.const 4) (i32.add (i32.const 8) (call $__i32_to_str (local.get $s2) (i32.const 140))))
          (i32.store8 (i32.add (i32.const 132) (i32.add (i32.load (i32.const 4)) (i32.const 0))) (i32.const 32))
          (i32.store8 (i32.add (i32.const 132) (i32.add (i32.load (i32.const 4)) (i32.const 1))) (i32.const 46))
          (i32.store8 (i32.add (i32.const 132) (i32.add (i32.load (i32.const 4)) (i32.const 2))) (i32.const 46))
          (i32.store8 (i32.add (i32.const 132) (i32.add (i32.load (i32.const 4)) (i32.const 3))) (i32.const 32))
          (i32.store (i32.const 4) (i32.add (i32.load (i32.const 4)) (i32.const 4)))
          (i32.store (i32.const 4) (i32.add (i32.load (i32.const 4)) (call $__i32_to_str (call $regex_lib_modc_reEnd) (i32.add (i32.const 132) (i32.load (i32.const 4))))))
          (i32.store8 (i32.add (i32.const 132) (i32.load (i32.const 4))) (i32.const 10))
          (i32.store (i32.const 4) (i32.add (i32.load (i32.const 4)) (i32.const 1)))
          (drop (call $fd_write
            (i32.const 1)
            (i32.const 0)
            (i32.const 1)
            (i32.const 128)))
    (call $check (if (result i32) (i32.eq (local.get $s2) (i32.const 3)) (then (i32.const 1)) (else (i32.const 0))))
    (call $check (if (result i32) (i32.eq (call $regex_lib_modc_reEnd ) (i32.const 6)) (then (i32.const 1)) (else (i32.const 0))))
    (call $check (if (result i32) (i32.eq (call $regex_lib_modc_reTest (i32.const 357) (i32.const 5) (i32.const 362) (i32.const 5)) (i32.const 0)) (then (i32.const 1)) (else (i32.const 0))))
    (call $check (if (result i32) (i32.eq (call $regex_lib_modc_reTest (i32.const 357) (i32.const 5) (i32.const 367) (i32.const 5)) (i32.const 1)) (then (i32.const 1)) (else (i32.const 0))))
    (call $check (if (result i32) (i32.eq (call $regex_lib_modc_reTest (i32.const 372) (i32.const 6) (i32.const 378) (i32.const 5)) (i32.const 0)) (then (i32.const 1)) (else (i32.const 0))))
    (call $check (if (result i32) (i32.eq (call $regex_lib_modc_reTest (i32.const 372) (i32.const 6) (i32.const 383) (i32.const 5)) (i32.const 1)) (then (i32.const 1)) (else (i32.const 0))))
    (call $check (if (result i32) (i32.eq (call $regex_lib_modc_reTest (i32.const 388) (i32.const 6) (i32.const 394) (i32.const 7)) (i32.const 1)) (then (i32.const 1)) (else (i32.const 0))))
    (local.set $s3 (call $regex_lib_modc_reSearch (i32.const 401) (i32.const 3) (i32.const 404) (i32.const 11)))
        (i32.store (i32.const 0) (i32.const 132))
          (i32.store (i32.const 4) (i32.const 0))
          (i32.store8 (i32.const 132) (i32.const 92))
          (i32.store8 (i32.const 133) (i32.const 100))
          (i32.store8 (i32.const 134) (i32.const 43))
          (i32.store8 (i32.const 135) (i32.const 58))
          (i32.store8 (i32.const 136) (i32.const 32))
          (i32.store (i32.const 4) (i32.add (i32.const 5) (call $__i32_to_str (local.get $s3) (i32.const 137))))
          (i32.store8 (i32.add (i32.const 132) (i32.add (i32.load (i32.const 4)) (i32.const 0))) (i32.const 32))
          (i32.store8 (i32.add (i32.const 132) (i32.add (i32.load (i32.const 4)) (i32.const 1))) (i32.const 46))
          (i32.store8 (i32.add (i32.const 132) (i32.add (i32.load (i32.const 4)) (i32.const 2))) (i32.const 46))
          (i32.store8 (i32.add (i32.const 132) (i32.add (i32.load (i32.const 4)) (i32.const 3))) (i32.const 32))
          (i32.store (i32.const 4) (i32.add (i32.load (i32.const 4)) (i32.const 4)))
          (i32.store (i32.const 4) (i32.add (i32.load (i32.const 4)) (call $__i32_to_str (call $regex_lib_modc_reEnd) (i32.add (i32.const 132) (i32.load (i32.const 4))))))
          (i32.store8 (i32.add (i32.const 132) (i32.load (i32.const 4))) (i32.const 10))
          (i32.store (i32.const 4) (i32.add (i32.load (i32.const 4)) (i32.const 1)))
          (drop (call $fd_write
            (i32.const 1)
            (i32.const 0)
            (i32.const 1)
            (i32.const 128)))
    (call $check (if (result i32) (i32.eq (local.get $s3) (i32.const 6)) (then (i32.const 1)) (else (i32.const 0))))
    (call $check (if (result i32) (i32.eq (call $regex_lib_modc_reEnd ) (i32.const 8)) (then (i32.const 1)) (else (i32.const 0))))
    (call $check (if (result i32) (i32.eq (call $regex_lib_modc_reTest (i32.const 415) (i32.const 2) (i32.const 260) (i32.const 3)) (i32.const 0)) (then (i32.const 1)) (else (i32.const 0))))
    (call $check (if (result i32) (i32.eq (call $regex_lib_modc_reTest (i32.const 417) (i32.const 3) (i32.const 420) (i32.const 11)) (i32.const 1)) (then (i32.const 1)) (else (i32.const 0))))
    (call $check (if (result i32) (i32.eq (call $regex_lib_modc_reSearch (i32.const 431) (i32.const 2) (i32.const 433) (i32.const 5)) (i32.const 2)) (then (i32.const 1)) (else (i32.const 0))))
    (call $check (if (result i32) (i32.eq (call $regex_lib_modc_reTest (i32.const 438) (i32.const 3) (i32.const 441) (i32.const 3)) (i32.const 0)) (then (i32.const 1)) (else (i32.const 0))))
    (local.set $s4 (call $regex_lib_modc_reSearch (i32.const 444) (i32.const 7) (i32.const 451) (i32.const 26)))
        (i32.store (i32.const 0) (i32.const 132))
          (i32.store (i32.const 4) (i32.const 0))
          (i32.store8 (i32.const 132) (i32.const 101))
          (i32.store8 (i32.const 133) (i32.const 109))
          (i32.store8 (i32.const 134) (i32.const 97))
          (i32.store8 (i32.const 135) (i32.const 105))
          (i32.store8 (i32.const 136) (i32.const 108))
          (i32.store8 (i32.const 137) (i32.const 45))
          (i32.store8 (i32.const 138) (i32.const 105))
          (i32.store8 (i32.const 139) (i32.const 115))
          (i32.store8 (i32.const 140) (i32.const 104))
          (i32.store8 (i32.const 141) (i32.const 58))
          (i32.store8 (i32.const 142) (i32.const 32))
          (i32.store (i32.const 4) (i32.add (i32.const 11) (call $__i32_to_str (local.get $s4) (i32.const 143))))
          (i32.store8 (i32.add (i32.const 132) (i32.add (i32.load (i32.const 4)) (i32.const 0))) (i32.const 32))
          (i32.store8 (i32.add (i32.const 132) (i32.add (i32.load (i32.const 4)) (i32.const 1))) (i32.const 46))
          (i32.store8 (i32.add (i32.const 132) (i32.add (i32.load (i32.const 4)) (i32.const 2))) (i32.const 46))
          (i32.store8 (i32.add (i32.const 132) (i32.add (i32.load (i32.const 4)) (i32.const 3))) (i32.const 32))
          (i32.store (i32.const 4) (i32.add (i32.load (i32.const 4)) (i32.const 4)))
          (i32.store (i32.const 4) (i32.add (i32.load (i32.const 4)) (call $__i32_to_str (call $regex_lib_modc_reEnd) (i32.add (i32.const 132) (i32.load (i32.const 4))))))
          (i32.store8 (i32.add (i32.const 132) (i32.load (i32.const 4))) (i32.const 10))
          (i32.store (i32.const 4) (i32.add (i32.load (i32.const 4)) (i32.const 1)))
          (drop (call $fd_write
            (i32.const 1)
            (i32.const 0)
            (i32.const 1)
            (i32.const 128)))
    (call $check (if (result i32) (i32.eq (local.get $s4) (i32.const 14)) (then (i32.const 1)) (else (i32.const 0))))
    (call $check (if (result i32) (i32.eq (call $regex_lib_modc_reEnd ) (i32.const 22)) (then (i32.const 1)) (else (i32.const 0))))
        (i32.store (i32.const 0) (i32.const 477))
          (i32.store (i32.const 4) (i32.const 9))
          (drop (call $fd_write
            (i32.const 1)
            (i32.const 0)
            (i32.const 1)
            (i32.const 128)))
    (call $proc_exit (i32.const 0))
  )
  (data (i32.const 260) "\61\62\63")
  (data (i32.const 263) "\78\61\62\63\79")
  (data (i32.const 268) "\78\79\7a")
  (data (i32.const 271) "\61\62")
  (data (i32.const 273) "\63\64")
  (data (i32.const 275) "\61\62\63\64\65\66")
  (data (i32.const 281) "\7a\7a")
  (data (i32.const 283) "\5e\61\62\63")
  (data (i32.const 287) "\78\61\62\63")
  (data (i32.const 291) "\61\62\63\24")
  (data (i32.const 295) "\78\78\61\62\63")
  (data (i32.const 300) "\61\62\63\78")
  (data (i32.const 304) "\5e\61\62\63\24")
  (data (i32.const 309) "\61\62\63\64")
  (data (i32.const 313) "\61\2e\63")
  (data (i32.const 316) "\61\78\63")
  (data (i32.const 319) "\61\63")
  (data (i32.const 321) "\61\62\2a\63")
  (data (i32.const 325) "\61\62\62\62\63")
  (data (i32.const 330) "\61\62\2b\63")
  (data (i32.const 334) "\61\62\3f\63")
  (data (i32.const 338) "\61\62\62\63")
  (data (i32.const 342) "\5b\30\2d\39\5d\2b")
  (data (i32.const 348) "\61\62\63\31\32\33\64\65\66")
  (data (i32.const 357) "\5b\41\2d\5a\5d")
  (data (i32.const 362) "\68\65\6c\6c\6f")
  (data (i32.const 367) "\68\65\4c\6c\6f")
  (data (i32.const 372) "\5b\5e\30\2d\39\5d")
  (data (i32.const 378) "\31\32\33\34\35")
  (data (i32.const 383) "\31\32\61\34\35")
  (data (i32.const 388) "\5b\61\62\63\5d\2b")
  (data (i32.const 394) "\78\78\63\61\62\62\7a")
  (data (i32.const 401) "\5c\64\2b")
  (data (i32.const 404) "\70\72\69\63\65\3d\34\32\75\73\64")
  (data (i32.const 415) "\5c\64")
  (data (i32.const 417) "\5c\77\2b")
  (data (i32.const 420) "\20\20\68\69\5f\74\68\65\72\65\20")
  (data (i32.const 431) "\5c\73")
  (data (i32.const 433) "\61\62\20\63\64")
  (data (i32.const 438) "\5c\44\2b")
  (data (i32.const 441) "\31\32\33")
  (data (i32.const 444) "\5c\77\2b\40\5c\77\2b")
  (data (i32.const 451) "\63\6f\6e\74\61\63\74\20\6d\65\20\61\74\20\62\6f\62\40\61\63\6d\65\20\6e\6f\77")
  (data (i32.const 477) "\72\65\67\65\78\20\6f\6b\0a")

  ;; globals from regex_lib_modc
  (global $regex_lib_modc_global1 (mut i32) (i32.const 0))
  ;; functions from regex_lib_modc
  (func $regex_lib_modc_cabi_realloc (param i32 i32 i32 i32) (result i32)
    local.get 3
    call $__malloc
    local.get 0
    local.get 0
    i32.eqz
    select)
  (func $regex_lib_modc__fn2 (param i32 i32 i32) (result i32)
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
  (func $regex_lib_modc__fn3 (param i32) (result i32)
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
  (func $regex_lib_modc__fn4 (param i32) (result i32)
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
    if (result i32)  ;; label = @1
      i32.const 1
    else
      local.get 0
      i32.const 12
      i32.eq
    end
    if (result i32)  ;; label = @1
      i32.const 1
    else
      local.get 0
      i32.const 11
      i32.eq
    end
    if  ;; label = @1
      i32.const 1
      return
    end
    i32.const 0
    return)
  (func $regex_lib_modc__fn5 (param i32 i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    local.get 2
    call $regex_lib_modc__fn2
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
        local.tee 5
        i32.const 1
        local.tee 6
        i32.add
        local.set 3
        local.get 3
        local.get 1
        i32.lt_s
        if  ;; label = @3
          local.get 0
          local.get 1
          local.get 3
          call $regex_lib_modc__fn2
          i32.const 94
          i32.eq
          if  ;; label = @4
            local.get 3
            i32.const 1
            i32.add
            local.set 3
          end
        end
        i32.const 1
        local.tee 7
        local.set 4
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 4
              i32.const 1
              i32.eq
              i32.eqz
              br_if 2 (;@3;)
              local.get 3
              local.get 1
              i32.ge_s
              if  ;; label = @6
                i32.const 0
                local.set 4
              else
                local.get 0
                local.get 1
                local.get 3
                call $regex_lib_modc__fn2
                i32.const 93
                i32.eq
                if  ;; label = @7
                  i32.const 0
                  local.set 4
                else
                  local.get 0
                  local.get 1
                  local.get 3
                  call $regex_lib_modc__fn2
                  i32.const 92
                  i32.eq
                  if  ;; label = @8
                    local.get 3
                    i32.const 2
                    i32.add
                    local.set 3
                  else
                    local.get 3
                    i32.const 1
                    i32.add
                    local.set 3
                  end
                end
              end
              br 1 (;@4;)
            end
          end
        end
        local.get 3
        local.get 2
        local.tee 8
        i32.sub
        i32.const 1
        local.tee 9
        i32.add
        return
      end
    end
    i32.const 1
    return)
  (func $regex_lib_modc__fn6 (param i32 i32 i32 i32) (result i32)
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
    if  ;; label = @1
      local.get 0
      local.get 1
      local.get 4
      call $regex_lib_modc__fn2
      i32.const 94
      i32.eq
      if  ;; label = @2
        block  ;; label = @3
          i32.const 1
          local.tee 10
          local.set 5
          local.get 4
          local.get 10
          i32.add
          local.set 4
        end
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
          i32.eqz
          br_if 2 (;@1;)
          local.get 4
          local.get 1
          i32.ge_s
          if  ;; label = @4
            i32.const 0
            local.set 7
          else
            local.get 0
            local.get 1
            local.get 4
            call $regex_lib_modc__fn2
            i32.const 93
            i32.eq
            if  ;; label = @5
              i32.const 0
              local.set 7
            else
              block  ;; label = @6
                local.get 0
                local.get 1
                local.get 4
                call $regex_lib_modc__fn2
                local.set 8
                local.get 8
                i32.const 92
                i32.eq
                if (result i32)  ;; label = @7
                  local.get 4
                  i32.const 1
                  i32.add
                  local.get 1
                  i32.lt_s
                else
                  i32.const 0
                end
                if  ;; label = @7
                  block  ;; label = @8
                    local.get 0
                    local.get 1
                    local.get 4
                    i32.const 1
                    i32.add
                    call $regex_lib_modc__fn2
                    local.set 8
                    local.get 8
                    i32.const 100
                    i32.eq
                    if  ;; label = @9
                      local.get 3
                      i32.const 48
                      i32.ge_s
                      if (result i32)  ;; label = @10
                        local.get 3
                        i32.const 57
                        i32.le_s
                      else
                        i32.const 0
                      end
                      if  ;; label = @10
                        i32.const 1
                        local.set 6
                      end
                    else
                      local.get 8
                      i32.const 119
                      i32.eq
                      if  ;; label = @10
                        local.get 3
                        call $regex_lib_modc__fn3
                        i32.const 1
                        i32.eq
                        if  ;; label = @11
                          i32.const 1
                          local.set 6
                        end
                      else
                        local.get 8
                        i32.const 115
                        i32.eq
                        if  ;; label = @11
                          local.get 3
                          call $regex_lib_modc__fn4
                          i32.const 1
                          i32.eq
                          if  ;; label = @12
                            i32.const 1
                            local.set 6
                          end
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
                    local.tee 11
                    i32.const 2
                    i32.add
                    local.set 4
                  end
                else
                  block  ;; label = @8
                    i32.const 0
                    local.set 9
                    local.get 4
                    i32.const 2
                    i32.add
                    local.get 1
                    i32.lt_s
                    if  ;; label = @9
                      local.get 0
                      local.get 1
                      local.get 4
                      i32.const 1
                      i32.add
                      call $regex_lib_modc__fn2
                      i32.const 45
                      i32.eq
                      if  ;; label = @10
                        local.get 0
                        local.get 1
                        local.get 4
                        i32.const 2
                        i32.add
                        call $regex_lib_modc__fn2
                        i32.const 93
                        i32.ne
                        if  ;; label = @11
                          i32.const 1
                          local.set 9
                        end
                      end
                    end
                    local.get 9
                    i32.const 1
                    i32.eq
                    if  ;; label = @9
                      block  ;; label = @10
                        local.get 0
                        local.get 1
                        local.get 4
                        i32.const 2
                        i32.add
                        call $regex_lib_modc__fn2
                        local.set 9
                        local.get 3
                        local.get 8
                        i32.ge_s
                        if (result i32)  ;; label = @11
                          local.get 3
                          local.get 9
                          i32.le_s
                        else
                          i32.const 0
                        end
                        if  ;; label = @11
                          i32.const 1
                          local.set 6
                        end
                        local.get 4
                        local.tee 12
                        i32.const 3
                        i32.add
                        local.set 4
                      end
                    else
                      block  ;; label = @10
                        local.get 3
                        local.get 8
                        i32.eq
                        if  ;; label = @11
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
  (func $regex_lib_modc__fn7 (param i32 i32 i32 i32) (result i32)
    (local i32)
    local.get 0
    local.get 1
    local.get 2
    call $regex_lib_modc__fn2
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
        call $regex_lib_modc__fn2
        local.set 4
        local.get 4
        i32.const 100
        i32.eq
        if  ;; label = @3
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
          if (result i32)  ;; label = @4
            i32.const 1
          else
            i32.const 0
          end
          return
        end
        local.get 4
        i32.const 68
        i32.eq
        if  ;; label = @3
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
          call $regex_lib_modc__fn3
          return
        end
        local.get 4
        i32.const 87
        i32.eq
        if  ;; label = @3
          local.get 3
          call $regex_lib_modc__fn3
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
          call $regex_lib_modc__fn4
          return
        end
        local.get 4
        i32.const 83
        i32.eq
        if  ;; label = @3
          local.get 3
          call $regex_lib_modc__fn4
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
        local.get 4
        i32.const 114
        i32.eq
        if  ;; label = @3
          local.get 3
          i32.const 13
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
      call $regex_lib_modc__fn6
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
  (func $regex_lib_modc__fn8 (param i32 i32 i32 i32 i32 i32) (result i32)
    (local i32)
    local.get 5
    local.get 3
    i32.lt_s
    if (result i32)  ;; label = @1
      local.get 0
      local.get 1
      local.get 4
      local.get 2
      local.get 3
      local.get 5
      call $regex_lib_modc__fn2
      call $regex_lib_modc__fn7
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
    return)
  (func $regex_lib_modc__fn9 (param i32 i32 i32 i32 i32 i32 i32 i32) (result i32)
    (local i32) (local i32) (local i32)
    i32.const 0
    local.set 8
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 6
          local.get 8
          i32.add
          local.get 3
          i32.lt_s
          if (result i32)  ;; label = @4
            local.get 0
            local.get 1
            local.get 4
            local.get 2
            local.get 3
            local.get 6
            local.get 8
            i32.add
            call $regex_lib_modc__fn2
            call $regex_lib_modc__fn7
            i32.const 1
            i32.eq
          else
            i32.const 0
          end
          i32.eqz
          br_if 2 (;@1;)
          local.get 8
          i32.const 1
          i32.add
          local.set 8
          br 1 (;@2;)
        end
      end
    end
    local.get 8
    local.set 8
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 8
          local.get 7
          i32.ge_s
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 0
            local.get 1
            local.get 2
            local.get 3
            local.get 5
            local.get 6
            local.get 8
            i32.add
            call $regex_lib_modc__fn10
            local.set 9
            local.get 9
            i32.const 0
            i32.ge_s
            if  ;; label = @5
              local.get 9
              return
            end
            local.get 8
            local.tee 10
            i32.const 1
            i32.sub
            local.set 8
          end
          br 1 (;@2;)
        end
      end
    end
    i32.const -1
    return)
  (func $regex_lib_modc__fn10 (param i32 i32 i32 i32 i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32)
    local.get 4
    local.get 1
    i32.ge_s
    if  ;; label = @1
      local.get 5
      return
    end
    local.get 0
    local.get 1
    local.get 4
    call $regex_lib_modc__fn2
    local.set 6
    local.get 6
    i32.const 36
    i32.eq
    if (result i32)  ;; label = @1
      local.get 4
      i32.const 1
      i32.add
      local.get 1
      i32.ge_s
    else
      i32.const 0
    end
    if  ;; label = @1
      local.get 5
      local.get 3
      i32.ge_s
      if (result i32)  ;; label = @2
        local.get 5
      else
        i32.const -1
      end
      return
    end
    local.get 0
    local.get 1
    local.get 4
    call $regex_lib_modc__fn5
    local.set 6
    local.get 4
    local.tee 9
    local.get 6
    i32.add
    local.set 6
    i32.const 0
    local.set 7
    local.get 6
    local.get 1
    i32.lt_s
    if  ;; label = @1
      block  ;; label = @2
        local.get 0
        local.get 1
        local.get 6
        call $regex_lib_modc__fn2
        local.set 8
        local.get 8
        i32.const 42
        i32.eq
        if (result i32)  ;; label = @3
          i32.const 1
        else
          local.get 8
          i32.const 43
          i32.eq
        end
        if (result i32)  ;; label = @3
          i32.const 1
        else
          local.get 8
          i32.const 63
          i32.eq
        end
        if  ;; label = @3
          local.get 8
          local.set 7
        end
      end
    end
    local.get 7
    i32.const 42
    i32.eq
    if  ;; label = @1
      local.get 0
      local.get 1
      local.get 2
      local.get 3
      local.get 4
      local.get 6
      i32.const 1
      i32.add
      local.get 5
      i32.const 0
      call $regex_lib_modc__fn9
      return
    end
    local.get 7
    i32.const 43
    i32.eq
    if  ;; label = @1
      local.get 0
      local.get 1
      local.get 2
      local.get 3
      local.get 4
      local.get 6
      i32.const 1
      i32.add
      local.get 5
      i32.const 1
      call $regex_lib_modc__fn9
      return
    end
    local.get 7
    i32.const 63
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 0
        local.get 1
        local.get 2
        local.get 3
        local.get 4
        local.get 5
        call $regex_lib_modc__fn8
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 0
            local.get 1
            local.get 2
            local.get 3
            local.get 6
            i32.const 1
            i32.add
            local.get 5
            i32.const 1
            i32.add
            call $regex_lib_modc__fn10
            local.set 7
            local.get 7
            i32.const 0
            i32.ge_s
            if  ;; label = @5
              local.get 7
              return
            end
          end
        end
        local.get 0
        local.get 1
        local.get 2
        local.get 3
        local.get 6
        i32.const 1
        i32.add
        local.get 5
        call $regex_lib_modc__fn10
        return
      end
    end
    local.get 0
    local.get 1
    local.get 2
    local.get 3
    local.get 4
    local.get 5
    call $regex_lib_modc__fn8
    i32.const 1
    i32.eq
    if  ;; label = @1
      local.get 0
      local.get 1
      local.get 2
      local.get 3
      local.get 6
      local.get 5
      i32.const 1
      i32.add
      call $regex_lib_modc__fn10
      return
    end
    i32.const -1
    return)
  (func $regex_lib_modc__fn11 (param i32 i32 i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    i32.const 0
    local.tee 11
    local.set 4
    local.get 11
    local.set 5
    local.get 1
    i32.const 0
    i32.gt_s
    if  ;; label = @1
      local.get 0
      local.get 1
      i32.const 0
      call $regex_lib_modc__fn2
      i32.const 94
      i32.eq
      if  ;; label = @2
        block  ;; label = @3
          i32.const 1
          local.tee 10
          local.set 5
          local.get 10
          local.set 4
        end
      end
    end
    i32.const 0
    local.tee 12
    local.set 6
    i32.const -1
    local.set 7
    local.get 12
    local.set 8
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 8
          i32.eqz
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 0
            local.get 1
            local.get 2
            local.get 3
            local.get 4
            local.get 6
            call $regex_lib_modc__fn10
            local.set 9
            local.get 9
            i32.const 0
            i32.ge_s
            if  ;; label = @5
              block  ;; label = @6
                local.get 9
                global.set $regex_lib_modc_global1
                local.get 6
                local.set 7
                i32.const 1
                local.set 8
              end
            else
              local.get 5
              i32.const 1
              i32.eq
              if  ;; label = @6
                i32.const 1
                local.set 8
              else
                local.get 6
                local.get 3
                i32.ge_s
                if  ;; label = @7
                  i32.const 1
                  local.set 8
                else
                  local.get 6
                  i32.const 1
                  i32.add
                  local.set 6
                end
              end
            end
          end
          br 1 (;@2;)
        end
      end
    end
    local.get 7
    return)
  (func $regex_lib_modc_reTest (param i32 i32 i32 i32) (result i32)
    local.get 0
    local.get 1
    local.get 2
    local.get 3
    call $regex_lib_modc__fn11
    i32.const 0
    i32.ge_s
    if (result i32)  ;; label = @1
      i32.const 1
    else
      i32.const 0
    end
    return)
  (func $regex_lib_modc_reSearch (param i32 i32 i32 i32) (result i32)
    local.get 0
    local.get 1
    local.get 2
    local.get 3
    call $regex_lib_modc__fn11
    return)
  (func $regex_lib_modc_reEnd (result i32)
    global.get $regex_lib_modc_global1
    return)
)