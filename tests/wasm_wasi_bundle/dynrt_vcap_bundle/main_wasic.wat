(module
  (import "wasi_snapshot_preview1" "proc_exit" (func $proc_exit (param i32)))
  (import "wasi_snapshot_preview1" "fd_write" (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (memory (export "memory") 3)
  (global $__heap_ptr (mut i32) (i32.const 667))
  (global $i (mut i32) (i32.const 0))
  (global $guard (mut i32) (i32.const 0))
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

  ;; ── f64 powers of 10 helper (used by $__f64_to_str shortening loop) ─────────
  (func $__pow10_f64 (param $n i32) (result f64)
    (if (i32.le_s (local.get $n) (i32.const 0))  (then (return (f64.const 1))))
    (if (i32.eq  (local.get $n) (i32.const 1))   (then (return (f64.const 10))))
    (if (i32.eq  (local.get $n) (i32.const 2))   (then (return (f64.const 100))))
    (if (i32.eq  (local.get $n) (i32.const 3))   (then (return (f64.const 1000))))
    (if (i32.eq  (local.get $n) (i32.const 4))   (then (return (f64.const 10000))))
    (if (i32.eq  (local.get $n) (i32.const 5))   (then (return (f64.const 100000))))
    (if (i32.eq  (local.get $n) (i32.const 6))   (then (return (f64.const 1000000))))
    (if (i32.eq  (local.get $n) (i32.const 7))   (then (return (f64.const 10000000))))
    (if (i32.eq  (local.get $n) (i32.const 8))   (then (return (f64.const 100000000))))
    (if (i32.eq  (local.get $n) (i32.const 9))   (then (return (f64.const 1000000000))))
    (if (i32.eq  (local.get $n) (i32.const 10))  (then (return (f64.const 10000000000))))
    (if (i32.eq  (local.get $n) (i32.const 11))  (then (return (f64.const 100000000000))))
    (if (i32.eq  (local.get $n) (i32.const 12))  (then (return (f64.const 1000000000000))))
    (if (i32.eq  (local.get $n) (i32.const 13))  (then (return (f64.const 10000000000000))))
    (if (i32.eq  (local.get $n) (i32.const 14))  (then (return (f64.const 100000000000000))))
    (f64.const 1000000000000000)
  )

  ;; ── f64 → decimal string ──────────────────────────────────────────────────
  ;; Writes the shortest decimal representation of $val at $buf, returns byte count.
  ;; Step 1: ×1e15 + f64.nearest gives up to 15 fractional digits.
  ;; Step 2: "shortest round-trip" loop strips any digit whose removal still
  ;;         reconstructs the exact same f64 via f64(ipart)+f64(trial)/f64(10^k).
  ;;         This eliminates spurious trailing digits caused by ×1e15 rounding.
  ;; Values outside [-2147483648, 2147483647] for the integer part are clamped.
  (func $__f64_to_str (param $val f64) (param $buf i32) (result i32)
    (local $len i32)
    (local $ipart i64)
    (local $fpart i64)
    (local $flen i32)
    (local $fdigits i64)
    (local $ptr i32)
    (local $cur_fpart i64)
    (local $cur_len i32)
    (local $trial i64)
    (local $recon f64)
    (local.set $ptr (local.get $buf))
    ;; Handle negative
    (if (f64.lt (local.get $val) (f64.const 0))
      (then
        (i32.store8 (local.get $ptr) (i32.const 45))
        (local.set $ptr (i32.add (local.get $ptr) (i32.const 1)))
        (local.set $val (f64.neg (local.get $val)))
      )
    )
    ;; Integer part — use i64 to support values beyond i32 range (up to ~9.2e18)
    ;; Subtract 1 from i64_to_str result to exclude the 'n' bigint suffix it appends.
    (local.set $ipart (i64.trunc_f64_s (local.get $val)))
    (local.set $len (i32.sub (call $__i64_to_str (local.get $ipart) (local.get $ptr)) (i32.const 1)))
    (local.set $ptr (i32.add (local.get $ptr) (local.get $len)))
    ;; Step 1: ×1e15, round to nearest integer → up to 15 fractional digits.
    (local.set $fpart
      (i64.trunc_f64_s
        (f64.nearest
          (f64.mul
            (f64.sub (local.get $val) (f64.convert_i64_s (local.get $ipart)))
            (f64.const 1000000000000000)
          )
        )
      )
    )
    ;; Step 2: shorten — strip digits from the right as long as the decimal
    ;; still round-trips to the original f64.  Powers of 10 in [1,1e15] are
    ;; exact in f64 (≤50 significant bits), so the reconstruction arithmetic
    ;; is reliable and the loop never produces a false positive.
    (local.set $cur_fpart (local.get $fpart))
    (local.set $cur_len   (i32.const 15))
    (block $shorten_done
      (loop $shorten_loop
        (br_if $shorten_done (i32.le_s (local.get $cur_len) (i32.const 1)))
        (local.set $trial (i64.div_u (local.get $cur_fpart) (i64.const 10)))
        (local.set $recon
          (f64.add
            (f64.convert_i64_s (local.get $ipart))
            (f64.div
              (f64.convert_i64_s (local.get $trial))
              (call $__pow10_f64 (i32.sub (local.get $cur_len) (i32.const 1)))
            )
          )
        )
        (if (f64.ne (local.get $recon) (local.get $val))
          (then (br $shorten_done))
        )
        (local.set $cur_fpart (local.get $trial))
        (local.set $cur_len   (i32.sub (local.get $cur_len) (i32.const 1)))
        (br $shorten_loop)
      )
    )
    (local.set $fpart (local.get $cur_fpart))
    (if (i64.ne (local.get $fpart) (i64.const 0))
      (then
        ;; Decimal point
        (i32.store8 (local.get $ptr) (i32.const 46))
        (local.set $ptr (i32.add (local.get $ptr) (i32.const 1)))
        ;; Write $cur_len-digit fractional string (least significant digit first)
        (local.set $fdigits (local.get $fpart))
        (local.set $flen    (local.get $cur_len))
        (block $fdone
          (loop $floop
            (br_if $fdone (i32.eqz (local.get $flen)))
            (i32.store8
              (i32.add (local.get $ptr) (i32.sub (local.get $flen) (i32.const 1)))
              (i32.add (i32.const 48) (i32.wrap_i64 (i64.rem_u (local.get $fdigits) (i64.const 10))))
            )
            (local.set $fdigits (i64.div_u (local.get $fdigits) (i64.const 10)))
            (local.set $flen    (i32.sub   (local.get $flen)    (i32.const 1)))
            (br $floop)
          )
        )
        ;; Strip trailing zeros
        (local.set $flen (local.get $cur_len))
        (block $strip
          (loop $striploop
            (br_if $strip (i32.eqz (local.get $flen)))
            (br_if $strip
              (i32.ne
                (i32.load8_u (i32.add (local.get $ptr) (i32.sub (local.get $flen) (i32.const 1))))
                (i32.const 48)
              )
            )
            (local.set $flen (i32.sub (local.get $flen) (i32.const 1)))
            (br $striploop)
          )
        )
        (local.set $ptr (i32.add (local.get $ptr) (local.get $flen)))
      )
    )
    ;; Return total length written
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
      (local.set $x (i32.load (i32.add (i32.add (i32.const -2) (i32.const 8)) (i32.shl (i32.const 5000000) (i32.const 2)))))
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
    (local $num i32)
    (local $obj i32)
    (local $arr i32)
    (local $sum i32)
    (local $cat i32)
    (local $__iface_tmp i32)
    (global.set $guard (call $__malloc (i32.const 40)))
      (i32.store (global.get $guard) (i32.const 1))
      (i32.store offset=4 (global.get $guard) (i32.const 8))
      (i32.store offset=8 (global.get $guard) (i32.const 0))
    (call $check (if (result i32) (i32.eq (call $dynrt_dynTypeof (call $dynrt_dynUndefined )) (i32.const 0)) (then (i32.const 1)) (else (i32.const 0))))
    (call $check (if (result i32) (i32.eq (call $dynrt_dynTypeof (call $dynrt_dynNull )) (i32.const 1)) (then (i32.const 1)) (else (i32.const 0))))
    (call $check (if (result i32) (i32.eq (call $dynrt_dynTypeof (call $dynrt_dynBool (i32.const 1))) (i32.const 2)) (then (i32.const 1)) (else (i32.const 0))))
    (call $check (if (result i32) (i32.eq (call $dynrt_dynToBool (call $dynrt_dynBool (i32.const 0))) (i32.const 0)) (then (i32.const 1)) (else (i32.const 0))))
    (local.set $num (call $dynrt_dynNumber (f64.const 6.25)))
    (call $check (if (result i32) (i32.eq (call $dynrt_dynTypeof (local.get $num)) (i32.const 3)) (then (i32.const 1)) (else (i32.const 0))))
    (call $check (if (result i32) (f64.eq (call $dynrt_dynNumberValue (local.get $num)) (f64.const 6.25)) (then (i32.const 1)) (else (i32.const 0))))
    (local.set $obj (call $dynrt_dynObject ))
    (call $dynrt_dynSet (local.get $obj) (i32.const 260) (i32.const 1) (call $dynrt_dynNumber (f64.const 1)))
    (call $dynrt_dynSet (local.get $obj) (i32.const 261) (i32.const 1) (call $dynrt_dynString (i32.const 262) (i32.const 3)))
    (call $check (if (result i32) (i32.eq (call $dynrt_dynObjLen (local.get $obj)) (i32.const 2)) (then (i32.const 1)) (else (i32.const 0))))
    (call $check (if (result i32) (i32.eq (call $dynrt_dynHas (local.get $obj) (i32.const 260) (i32.const 1)) (i32.const 1)) (then (i32.const 1)) (else (i32.const 0))))
    (call $check (if (result i32) (i32.eq (call $dynrt_dynHas (local.get $obj) (i32.const 265) (i32.const 1)) (i32.const 0)) (then (i32.const 1)) (else (i32.const 0))))
    (call $check (if (result i32) (f64.eq (call $dynrt_dynNumberValue (call $dynrt_dynGet (local.get $obj) (i32.const 260) (i32.const 1))) (f64.const 1)) (then (i32.const 1)) (else (i32.const 0))))
    (call $dynrt_dynSet (local.get $obj) (i32.const 260) (i32.const 1) (call $dynrt_dynNumber (f64.const 42)))
    (call $check (if (result i32) (i32.eq (call $dynrt_dynObjLen (local.get $obj)) (i32.const 2)) (then (i32.const 1)) (else (i32.const 0))))
    (call $check (if (result i32) (f64.eq (call $dynrt_dynNumberValue (call $dynrt_dynGet (local.get $obj) (i32.const 260) (i32.const 1))) (f64.const 42)) (then (i32.const 1)) (else (i32.const 0))))
    (local.set $arr (call $dynrt_dynArray ))
    (block $break_0
      (loop $loop_0
        (br_if $break_0 (i32.eqz (i32.lt_s (global.get $i) (i32.const 8))))
        (block $cont_0
          (call $dynrt_dynPush (local.get $arr) (call $dynrt_dynNumber (f64.convert_i32_s (i32.add (global.get $i) (i32.const 1)))))
          (global.set $i (i32.add (global.get $i) (i32.const 1)))
        )
        (br $loop_0)
      )
    )
        (i32.store (i32.const 0) (i32.const 132))
          (i32.store (i32.const 4) (i32.const 0))
          (i32.store8 (i32.const 132) (i32.const 97))
          (i32.store8 (i32.const 133) (i32.const 114))
          (i32.store8 (i32.const 134) (i32.const 114))
          (i32.store8 (i32.const 135) (i32.const 32))
          (i32.store8 (i32.const 136) (i32.const 108))
          (i32.store8 (i32.const 137) (i32.const 101))
          (i32.store8 (i32.const 138) (i32.const 110))
          (i32.store8 (i32.const 139) (i32.const 58))
          (i32.store8 (i32.const 140) (i32.const 32))
          (i32.store (i32.const 4) (i32.add (i32.const 9) (call $__i32_to_str (call $dynrt_dynArrLen (local.get $arr)) (i32.const 141))))
          (i32.store8 (i32.add (i32.const 132) (i32.load (i32.const 4))) (i32.const 10))
          (i32.store (i32.const 4) (i32.add (i32.load (i32.const 4)) (i32.const 1)))
          (drop (call $fd_write
            (i32.const 1)
            (i32.const 0)
            (i32.const 1)
            (i32.const 128)))
    (call $check (if (result i32) (i32.eq (call $dynrt_dynArrLen (local.get $arr)) (i32.const 8)) (then (i32.const 1)) (else (i32.const 0))))
    (call $check (if (result i32) (f64.eq (call $dynrt_dynNumberValue (call $dynrt_dynArrGet (local.get $arr) (i32.const 0))) (f64.const 1)) (then (i32.const 1)) (else (i32.const 0))))
    (call $check (if (result i32) (f64.eq (call $dynrt_dynNumberValue (call $dynrt_dynArrGet (local.get $arr) (i32.const 7))) (f64.const 8)) (then (i32.const 1)) (else (i32.const 0))))
    (call $check (if (result i32) (i32.eq (call $dynrt_dynStrictEq (call $dynrt_dynNumber (f64.const 5)) (call $dynrt_dynNumber (f64.const 5))) (i32.const 1)) (then (i32.const 1)) (else (i32.const 0))))
    (call $check (if (result i32) (i32.eq (call $dynrt_dynStrictEq (call $dynrt_dynString (i32.const 266) (i32.const 2)) (call $dynrt_dynString (i32.const 266) (i32.const 2))) (i32.const 1)) (then (i32.const 1)) (else (i32.const 0))))
    (call $check (if (result i32) (i32.eq (call $dynrt_dynStrictEq (call $dynrt_dynNull ) (call $dynrt_dynUndefined )) (i32.const 0)) (then (i32.const 1)) (else (i32.const 0))))
    (local.set $sum (call $dynrt_dynAdd (call $dynrt_dynNumber (f64.const 10)) (call $dynrt_dynNumber (f64.const 20))))
        (i32.store (i32.const 0) (i32.const 132))
          (i32.store (i32.const 4) (i32.const 0))
          (i32.store8 (i32.const 132) (i32.const 49))
          (i32.store8 (i32.const 133) (i32.const 48))
          (i32.store8 (i32.const 134) (i32.const 32))
          (i32.store8 (i32.const 135) (i32.const 43))
          (i32.store8 (i32.const 136) (i32.const 32))
          (i32.store8 (i32.const 137) (i32.const 50))
          (i32.store8 (i32.const 138) (i32.const 48))
          (i32.store8 (i32.const 139) (i32.const 32))
          (i32.store8 (i32.const 140) (i32.const 61))
          (i32.store8 (i32.const 141) (i32.const 32))
          (i32.store (i32.const 4) (i32.add (i32.const 10) (call $__f64_to_str (call $dynrt_dynNumberValue (local.get $sum)) (i32.const 142))))
          (i32.store8 (i32.add (i32.const 132) (i32.load (i32.const 4))) (i32.const 10))
          (i32.store (i32.const 4) (i32.add (i32.load (i32.const 4)) (i32.const 1)))
          (drop (call $fd_write
            (i32.const 1)
            (i32.const 0)
            (i32.const 1)
            (i32.const 128)))
    (call $check (if (result i32) (f64.eq (call $dynrt_dynNumberValue (local.get $sum)) (f64.const 30)) (then (i32.const 1)) (else (i32.const 0))))
    (local.set $cat (call $dynrt_dynAdd (call $dynrt_dynString (i32.const 266) (i32.const 2)) (call $dynrt_dynString (i32.const 268) (i32.const 2))))
    (call $check (if (result i32) (i32.eq (call $dynrt_dynStrLen (local.get $cat)) (i32.const 4)) (then (i32.const 1)) (else (i32.const 0))))
    (call $check (if (result i32) (i32.eq (call $dynrt_dynStrCharAt (local.get $cat) (i32.const 2)) (i32.const 99)) (then (i32.const 1)) (else (i32.const 0))))
        (i32.store (i32.const 0) (i32.const 270))
          (i32.store (i32.const 4) (i32.const 40))
          (drop (call $fd_write
            (i32.const 1)
            (i32.const 0)
            (i32.const 1)
            (i32.const 128)))
    (call $proc_exit (i32.const 0))
  )
  (data (i32.const 260) "\61")
  (data (i32.const 261) "\62")
  (data (i32.const 262) "\74\77\6f")
  (data (i32.const 265) "\7a")
  (data (i32.const 266) "\61\62")
  (data (i32.const 268) "\63\64")
  (data (i32.const 270) "\64\79\6e\72\74\20\76\69\72\74\75\61\6c\2d\69\6d\70\6f\72\74\3a\20\61\6c\6c\20\63\68\65\63\6b\73\20\70\61\73\73\65\64\0a")

  ;; globals from dynrt
  (global $dynrt_global1 (mut i32) (i32.const 131072))
  (global $dynrt_global2 (mut i32) (i32.const 131072))
  (global $dynrt_global3 i32 (i32.const 4))
  (global $dynrt_global4 (mut i32) (i32.const 131072))
  (global $dynrt_global5 (mut i32) (i32.const -1))
  (global $dynrt_global6 (mut i32) (i32.const 131072))
  (global $dynrt_global7 (mut i32) (i32.const 131072))
  (global $dynrt_global8 (mut i32) (i32.const 131072))
  (global $dynrt_global9 (mut i32) (i32.const 131072))
  (global $dynrt_global10 (mut i32) (i32.const 131072))
  ;; functions from dynrt
  (func $dynrt_cabi_realloc (param i32 i32 i32 i32) (result i32)
    local.get 3
    call $__malloc
    local.get 0
    local.get 0
    i32.eqz
    select)
  (func $dynrt__fn2 (param i32 i32 i32 i32) (result i32 i32)
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
  (func $dynrt__fn3 (param i32 i32 i32 i32) (result i32 i32)
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
  (func $dynrt__fn4 (param i32 i32 i32) (result i32)
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
  (func $dynrt__fn5 (param i32) (result f64)
    local.get 0
    i32.const 0
    i32.le_s
    if  ;; label = @1
      f64.const 0x1.0p+0 (;=1;)
      return
    end
    local.get 0
    i32.const 1
    i32.eq
    if  ;; label = @1
      f64.const 0x1.4p+3 (;=10;)
      return
    end
    local.get 0
    i32.const 2
    i32.eq
    if  ;; label = @1
      f64.const 0x1.9p+6 (;=100;)
      return
    end
    local.get 0
    i32.const 3
    i32.eq
    if  ;; label = @1
      f64.const 0x1.f4p+9 (;=1000;)
      return
    end
    local.get 0
    i32.const 4
    i32.eq
    if  ;; label = @1
      f64.const 0x1.388p+13 (;=10000;)
      return
    end
    local.get 0
    i32.const 5
    i32.eq
    if  ;; label = @1
      f64.const 0x1.86ap+16 (;=100000;)
      return
    end
    local.get 0
    i32.const 6
    i32.eq
    if  ;; label = @1
      f64.const 0x1.e848p+19 (;=1000000;)
      return
    end
    local.get 0
    i32.const 7
    i32.eq
    if  ;; label = @1
      f64.const 0x1.312dp+23 (;=10000000;)
      return
    end
    local.get 0
    i32.const 8
    i32.eq
    if  ;; label = @1
      f64.const 0x1.7d784p+26 (;=100000000;)
      return
    end
    local.get 0
    i32.const 9
    i32.eq
    if  ;; label = @1
      f64.const 0x1.dcd65p+29 (;=1000000000;)
      return
    end
    local.get 0
    i32.const 10
    i32.eq
    if  ;; label = @1
      f64.const 0x1.2a05f2p+33 (;=10000000000;)
      return
    end
    local.get 0
    i32.const 11
    i32.eq
    if  ;; label = @1
      f64.const 0x1.74876e8p+36 (;=100000000000;)
      return
    end
    local.get 0
    i32.const 12
    i32.eq
    if  ;; label = @1
      f64.const 0x1.d1a94a2p+39 (;=1000000000000;)
      return
    end
    local.get 0
    i32.const 13
    i32.eq
    if  ;; label = @1
      f64.const 0x1.2309ce54p+43 (;=10000000000000;)
      return
    end
    local.get 0
    i32.const 14
    i32.eq
    if  ;; label = @1
      f64.const 0x1.6bcc41e9p+46 (;=100000000000000;)
      return
    end
    f64.const 0x1.c6bf52634p+49 (;=1000000000000000;))
  (func $dynrt__fn6 (param f64 i32) (result i32)
    (local i32) (local i64) (local i64) (local i32) (local i32) (local i64) (local f64) (local i32) (local i64) (local i64) (local i32) (local i64) (local i64) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local f64) (local i32) (local f64) (local i64) (local i64) (local i64) (local i32) (local i32)
    local.get 1
    local.tee 20
    local.set 5
    local.get 0
    f64.const 0x0p+0 (;=0;)
    f64.lt
    if  ;; label = @1
      block  ;; label = @2
        local.get 5
        i32.const 45
        i32.store8
        local.get 5
        local.tee 9
        i32.const 1
        i32.add
        local.set 5
        local.get 0
        f64.neg
        local.set 0
      end
    end
    local.get 0
    local.tee 21
    i64.trunc_f64_s
    local.set 3
    local.get 3
    local.get 5
    call $dynrt__fn7
    i32.const 1
    i32.sub
    local.set 2
    local.get 5
    local.tee 22
    local.get 2
    i32.add
    local.set 5
    local.get 0
    local.tee 23
    local.get 3
    local.tee 24
    f64.convert_i64_s
    f64.sub
    f64.const 0x1.c6bf52634p+49 (;=1000000000000000;)
    f64.mul
    f64.nearest
    i64.trunc_f64_s
    local.set 4
    local.get 4
    local.tee 25
    local.set 4
    i32.const 15
    local.set 6
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 6
          i32.const 1
          i32.le_s
          br_if 2 (;@1;)
          local.get 4
          i64.const 10
          i64.div_u
          local.set 7
          local.get 3
          f64.convert_i64_s
          local.get 7
          local.tee 10
          f64.convert_i64_s
          local.get 6
          i32.const 1
          i32.sub
          call $dynrt__fn5
          f64.div
          f64.add
          local.set 8
          local.get 8
          local.get 0
          f64.ne
          if  ;; label = @4
            br 3 (;@1;)
          end
          local.get 7
          local.tee 11
          local.set 4
          local.get 6
          i32.const 1
          i32.sub
          local.tee 12
          local.set 6
          br 1 (;@2;)
        end
      end
    end
    local.get 4
    local.tee 26
    local.set 4
    local.get 4
    i64.const 0
    i64.ne
    if  ;; label = @1
      block  ;; label = @2
        local.get 5
        i32.const 46
        i32.store8
        local.get 5
        local.tee 16
        i32.const 1
        i32.add
        local.set 5
        local.get 4
        local.set 3
        local.get 6
        local.tee 17
        local.set 2
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 2
              i32.eqz
              br_if 2 (;@3;)
              local.get 5
              local.get 2
              i32.const 1
              i32.sub
              i32.add
              i32.const 48
              local.get 3
              i64.const 10
              i64.rem_u
              i32.wrap_i64
              i32.add
              i32.store8
              local.get 3
              local.tee 13
              i64.const 10
              local.tee 14
              i64.div_u
              local.set 3
              local.get 2
              i32.const 1
              i32.sub
              local.tee 15
              local.set 2
              br 1 (;@4;)
            end
          end
        end
        local.get 6
        local.tee 18
        local.set 2
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 2
              i32.eqz
              br_if 2 (;@3;)
              local.get 5
              local.get 2
              i32.const 1
              i32.sub
              i32.add
              i32.load8_u
              i32.const 48
              i32.ne
              br_if 2 (;@3;)
              local.get 2
              i32.const 1
              i32.sub
              local.set 2
              br 1 (;@4;)
            end
          end
        end
        local.get 5
        local.tee 19
        local.get 2
        i32.add
        local.set 5
      end
    end
    local.get 5
    local.tee 27
    local.get 1
    local.tee 28
    i32.sub)
  (func $dynrt__fn7 (param i64 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i64) (local i64) (local i64) (local i64) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 1
    local.tee 18
    local.set 6
    local.get 18
    local.set 2
    local.get 0
    i64.eqz
    if  ;; label = @1
      block  ;; label = @2
        local.get 1
        i32.const 48
        i32.store8
        local.get 1
        i32.const 1
        i32.add
        i32.const 110
        i32.store8
        i32.const 2
        return
      end
    end
    local.get 0
    i64.const 0
    i64.lt_s
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
        i64.const 0
        local.get 0
        i64.sub
        local.set 0
      end
    end
    local.get 1
    local.tee 19
    local.set 3
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 0
          i64.eqz
          br_if 2 (;@1;)
          local.get 0
          local.tee 10
          i64.const 10
          local.tee 11
          i64.rem_u
          i32.wrap_i64
          local.set 4
          local.get 3
          i32.const 48
          local.get 4
          i32.add
          i32.store8
          local.get 0
          local.tee 12
          i64.const 10
          local.tee 13
          i64.div_u
          local.set 0
          local.get 3
          local.tee 14
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
    local.tee 20
    i32.const 1
    local.tee 21
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
          local.tee 15
          i32.const 1
          local.tee 16
          i32.add
          local.set 2
          local.get 4
          local.tee 17
          local.get 16
          i32.sub
          local.set 4
          br 1 (;@2;)
        end
      end
    end
    local.get 3
    i32.const 110
    i32.store8
    local.get 3
    local.tee 22
    i32.const 1
    local.tee 23
    i32.add
    local.set 3
    local.get 3
    local.tee 24
    local.get 6
    i32.sub)
  (func $dynrt__fn8 (param i32 i32) (result f64)
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
  (func $dynrt_dynUndefined (result i32)
    (local i32) (local i32)
    i32.const 24
    call $__malloc
    local.set 0
    local.get 0
    i32.const 4
    i32.store
    local.get 0
    i32.const 8
    i32.add
    i32.const 0
    i32.store
    local.get 0
    local.tee 1
    return)
  (func $dynrt_dynNull (result i32)
    (local i32) (local i32)
    i32.const 24
    call $__malloc
    local.set 0
    local.get 0
    i32.const 4
    i32.store
    local.get 0
    i32.const 8
    i32.add
    i32.const 1
    i32.store
    local.get 0
    local.tee 1
    return)
  (func $dynrt_dynBool (param i32) (result i32)
    (local i32) (local i32)
    i32.const 24
    call $__malloc
    local.set 1
    local.get 1
    i32.const 4
    i32.store
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
  (func $dynrt_dynNumber (param f64) (result i32)
    (local i32) (local i32) (local i32)
    i32.const 16
    call $__malloc
    local.set 1
    local.get 1
    i32.const 1
    i32.store
    local.get 1
    i32.const 8
    i32.add
    local.get 0
    f64.store
    i32.const 24
    call $__malloc
    local.set 2
    local.get 2
    i32.const 4
    i32.store
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
  (func $dynrt_dynString (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 1
    local.set 2
    i32.const 8
    local.get 2
    i32.add
    call $__malloc
    local.set 3
    local.get 3
    local.get 2
    i32.store
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
            call $dynrt__fn4
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
    i32.const 24
    call $__malloc
    local.set 4
    local.get 4
    i32.const 4
    i32.store
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
  (func $dynrt__fn14 (result i32)
    (local i32) (local i32)
    i32.const 8
    global.get $dynrt_global3
    i32.const 2
    i32.add
    i32.const 2
    i32.shl
    i32.add
    call $__malloc
    local.set 0
    local.get 0
    global.get $dynrt_global3
    i32.const 2
    i32.add
    i32.store
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
    global.get $dynrt_global3
    i32.store
    local.get 0
    local.tee 1
    return)
  (func $dynrt__fn15 (param i32) (result i32)
    (local i32)
    local.get 0
    local.set 1
    local.get 1
    i32.const 8
    i32.add
    i32.load
    return)
  (func $dynrt__fn16 (param i32 i32) (result i32)
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
  (func $dynrt__fn17 (param i32 i32 i32)
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
  (func $dynrt__fn18 (param i32 i32) (result i32)
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
        i32.const 2
        i32.shl
        i32.add
        call $__malloc
        local.set 5
        local.get 5
        local.get 4
        i32.const 2
        i32.add
        i32.store
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
  (func $dynrt_dynArray (result i32)
    (local i32) (local i32)
    i32.const 24
    call $__malloc
    local.set 0
    local.get 0
    i32.const 4
    i32.store
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
    call $dynrt__fn14
    i32.store
    local.get 0
    local.tee 1
    return)
  (func $dynrt_dynObject (result i32)
    (local i32) (local i32)
    i32.const 24
    call $__malloc
    local.set 0
    local.get 0
    i32.const 4
    i32.store
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
    call $dynrt__fn14
    i32.store
    local.get 0
    i32.const 8
    i32.add
    i32.const 12
    i32.add
    call $dynrt__fn14
    i32.store
    local.get 0
    local.tee 1
    return)
  (func $dynrt_dynTag (param i32) (result i32)
    (local i32)
    local.get 0
    local.set 1
    local.get 1
    i32.const 8
    i32.add
    i32.load
    return)
  (func $dynrt_dynTypeof (param i32) (result i32)
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
  (func $dynrt_dynNumberValue (param i32) (result f64)
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
  (func $dynrt_dynBoolValue (param i32) (result i32)
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
  (func $dynrt_dynStrLen (param i32) (result i32)
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
  (func $dynrt_dynStrBytes (param i32) (result i32)
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
  (func $dynrt_dynStrCharAt (param i32 i32) (result i32)
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
  (func $dynrt_dynToBool (param i32) (result i32)
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
  (func $dynrt_dynToNumber (param i32) (result f64)
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
  (func $dynrt__fn30 (param i32)
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
    i32.const 570
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
            call $dynrt__fn2
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
    global.set $dynrt_global1
    local.get 2
    global.set $dynrt_global2
    return)
  (func $dynrt__fn31 (param i32)
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
        call $dynrt__fn30
        global.get $dynrt_global1
        local.set 1
        global.get $dynrt_global2
        local.set 2
        local.get 1
        global.set $dynrt_global1
        local.get 2
        global.set $dynrt_global2
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
        call $dynrt__fn6
        local.set 2
        local.get 1
        local.tee 5
        global.set $dynrt_global1
        local.get 2
        global.set $dynrt_global2
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
            i32.const 570
            local.set 1
            i32.const 5
            local.set 2
          end
        else
          block  ;; label = @4
            i32.const 575
            local.set 1
            i32.const 4
            local.set 2
          end
        end
        local.get 1
        global.set $dynrt_global1
        local.get 2
        global.set $dynrt_global2
        return
      end
    end
    local.get 2
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        i32.const 579
        local.set 1
        i32.const 4
        local.set 2
        local.get 1
        global.set $dynrt_global1
        local.get 2
        global.set $dynrt_global2
        return
      end
    end
    local.get 2
    i32.eqz
    if  ;; label = @1
      block  ;; label = @2
        i32.const 583
        local.set 1
        i32.const 9
        local.set 2
        local.get 1
        global.set $dynrt_global1
        local.get 2
        global.set $dynrt_global2
        return
      end
    end
    i32.const 570
    local.set 1
    i32.const 0
    local.set 2
    local.get 1
    local.tee 6
    global.set $dynrt_global1
    local.get 2
    global.set $dynrt_global2
    return)
  (func $dynrt__fn32 (param i32 i32 i32) (result i32)
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
    call $dynrt__fn15
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
            call $dynrt__fn16
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
                call $dynrt__fn16
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
                      call $dynrt__fn4
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
  (func $dynrt_dynSet (param i32 i32 i32 i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.tee 9
    local.set 4
    local.get 0
    local.get 1
    local.get 2
    call $dynrt__fn32
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
        call $dynrt__fn17
        return
      end
    end
    local.get 2
    local.tee 10
    local.set 5
    i32.const 8
    local.get 5
    i32.add
    call $__malloc
    local.set 6
    local.get 6
    local.get 5
    i32.store
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
            call $dynrt__fn4
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
    call $dynrt__fn18
    local.set 7
    local.get 7
    local.get 5
    call $dynrt__fn18
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
    call $dynrt__fn18
    i32.store)
  (func $dynrt_dynGet (param i32 i32 i32) (result i32)
    (local i32) (local i32) (local i32)
    local.get 0
    local.tee 5
    local.set 3
    local.get 0
    local.get 1
    local.get 2
    call $dynrt__fn32
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
    call $dynrt__fn16
    return)
  (func $dynrt_dynHas (param i32 i32 i32) (result i32)
    local.get 0
    local.get 1
    local.get 2
    call $dynrt__fn32
    i32.const -1
    i32.eq
    if (result i32)  ;; label = @1
      i32.const 0
    else
      i32.const 1
    end
    return)
  (func $dynrt_dynObjLen (param i32) (result i32)
    (local i32)
    local.get 0
    local.set 1
    local.get 1
    i32.const 8
    i32.add
    i32.const 4
    i32.add
    i32.load
    call $dynrt__fn15
    return)
  (func $dynrt_dynObjKeyPtr (param i32 i32) (result i32)
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
    call $dynrt__fn16
    local.set 2
    local.get 2
    i32.const 8
    i32.add
    local.tee 3
    return)
  (func $dynrt_dynObjKeyLen (param i32 i32) (result i32)
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
    call $dynrt__fn16
    return)
  (func $dynrt_dynObjValAt (param i32 i32) (result i32)
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
    call $dynrt__fn16
    return)
  (func $dynrt_dynPush (param i32 i32)
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
    call $dynrt__fn18
    i32.store)
  (func $dynrt_dynArrLen (param i32) (result i32)
    (local i32)
    local.get 0
    local.set 1
    local.get 1
    i32.const 8
    i32.add
    i32.const 4
    i32.add
    i32.load
    call $dynrt__fn15
    return)
  (func $dynrt_dynArrGet (param i32 i32) (result i32)
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
    call $dynrt__fn16
    return)
  (func $dynrt_dynStrictEq (param i32 i32) (result i32)
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
  (func $dynrt_dynAdd (param i32 i32) (result i32)
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
        call $dynrt__fn31
        global.get $dynrt_global1
        local.tee 8
        local.set 2
        global.get $dynrt_global2
        local.tee 9
        local.set 3
        local.get 1
        call $dynrt__fn31
        global.get $dynrt_global1
        local.tee 10
        local.set 4
        global.get $dynrt_global2
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
        call $dynrt__fn2
        local.set 3
        nop
        local.set 2
        local.get 2
        local.get 3
        call $dynrt_dynString
        return
      end
    end
    local.get 0
    call $dynrt_dynToNumber
    local.set 6
    local.get 1
    call $dynrt_dynToNumber
    local.set 7
    local.get 6
    local.get 7
    f64.add
    call $dynrt_dynNumber
    return)
  (func $dynrt_dynNeg (param i32) (result i32)
    (local f64)
    local.get 0
    call $dynrt_dynToNumber
    local.set 1
    f64.const 0x0p+0 (;=0;)
    local.get 1
    f64.sub
    call $dynrt_dynNumber
    return)
  (func $dynrt_dynNot (param i32) (result i32)
    local.get 0
    call $dynrt_dynToBool
    i32.eqz
    if (result i32)  ;; label = @1
      i32.const 1
    else
      i32.const 0
    end
    call $dynrt_dynBool
    return)
  (func $dynrt_dynSub (param i32 i32) (result i32)
    (local f64) (local f64)
    local.get 0
    call $dynrt_dynToNumber
    local.set 2
    local.get 1
    call $dynrt_dynToNumber
    local.set 3
    local.get 2
    local.get 3
    f64.sub
    call $dynrt_dynNumber
    return)
  (func $dynrt_dynMul (param i32 i32) (result i32)
    (local f64) (local f64)
    local.get 0
    call $dynrt_dynToNumber
    local.set 2
    local.get 1
    call $dynrt_dynToNumber
    local.set 3
    local.get 2
    local.get 3
    f64.mul
    call $dynrt_dynNumber
    return)
  (func $dynrt_dynDiv (param i32 i32) (result i32)
    (local f64) (local f64)
    local.get 0
    call $dynrt_dynToNumber
    local.set 2
    local.get 1
    call $dynrt_dynToNumber
    local.set 3
    local.get 2
    local.get 3
    f64.div
    call $dynrt_dynNumber
    return)
  (func $dynrt_dynMod (param i32 i32) (result i32)
    (local f64) (local f64) (local f64) (local i32) (local f64) (local f64)
    local.get 0
    call $dynrt_dynToNumber
    local.set 2
    local.get 1
    call $dynrt_dynToNumber
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
    call $dynrt_dynNumber
    return)
  (func $dynrt_dynLt (param i32 i32) (result i32)
    (local f64) (local f64)
    local.get 0
    call $dynrt_dynToNumber
    local.set 2
    local.get 1
    call $dynrt_dynToNumber
    local.set 3
    local.get 2
    local.get 3
    f64.lt
    if (result i32)  ;; label = @1
      i32.const 1
    else
      i32.const 0
    end
    call $dynrt_dynBool
    return)
  (func $dynrt_dynGt (param i32 i32) (result i32)
    (local f64) (local f64)
    local.get 0
    call $dynrt_dynToNumber
    local.set 2
    local.get 1
    call $dynrt_dynToNumber
    local.set 3
    local.get 2
    local.get 3
    f64.gt
    if (result i32)  ;; label = @1
      i32.const 1
    else
      i32.const 0
    end
    call $dynrt_dynBool
    return)
  (func $dynrt_dynLe (param i32 i32) (result i32)
    (local f64) (local f64)
    local.get 0
    call $dynrt_dynToNumber
    local.set 2
    local.get 1
    call $dynrt_dynToNumber
    local.set 3
    local.get 2
    local.get 3
    f64.le
    if (result i32)  ;; label = @1
      i32.const 1
    else
      i32.const 0
    end
    call $dynrt_dynBool
    return)
  (func $dynrt_dynGe (param i32 i32) (result i32)
    (local f64) (local f64)
    local.get 0
    call $dynrt_dynToNumber
    local.set 2
    local.get 1
    call $dynrt_dynToNumber
    local.set 3
    local.get 2
    local.get 3
    f64.ge
    if (result i32)  ;; label = @1
      i32.const 1
    else
      i32.const 0
    end
    call $dynrt_dynBool
    return)
  (func $dynrt_dynBuiltin (param i32) (result i32)
    (local i32) (local i32)
    i32.const 24
    call $__malloc
    local.set 1
    local.get 1
    i32.const 4
    i32.store
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
  (func $dynrt__fn56 (param i32 i32 i32) (result i32)
    (local i32) (local i32)
    i32.const 28
    call $__malloc
    local.set 3
    local.get 3
    i32.const 5
    i32.store
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
  (func $dynrt_dynMakeFunc (param i32 i32 i32 i32) (result i32)
    (local i32)
    local.get 1
    local.get 2
    call $dynrt_dynString
    local.set 4
    local.get 0
    local.get 4
    local.get 3
    call $dynrt__fn56
    return)
  (func $dynrt__fn58 (param i32 i32 i32) (result i32)
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
            call $dynrt_dynGet
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
  (func $dynrt_dynApply (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local f64) (local f64) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.set 2
    local.get 2
    i32.const 8
    i32.add
    i32.load
    i32.const 7
    i32.ne
    if  ;; label = @1
      call $dynrt_dynUndefined
      return
    end
    local.get 2
    i32.const 8
    i32.add
    i32.const 4
    i32.add
    i32.load
    local.set 3
    local.get 1
    call $dynrt_dynArrLen
    local.set 4
    local.get 3
    i32.const -1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 2
        i32.const 8
        i32.add
        i32.const 8
        i32.add
        i32.load
        local.set 3
        local.get 2
        i32.const 8
        i32.add
        i32.const 12
        i32.add
        i32.load
        local.set 5
        local.get 2
        i32.const 8
        i32.add
        i32.const 16
        i32.add
        i32.load
        local.set 2
        call $dynrt_dynObject
        local.set 6
        local.get 6
        local.tee 14
        local.set 7
        local.get 7
        i32.const 8
        i32.add
        i32.const 8
        i32.add
        local.get 2
        i32.store
        local.get 5
        call $dynrt_dynArrLen
        local.set 2
        i32.const 0
        local.set 7
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 7
              local.get 2
              i32.lt_s
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                local.get 5
                local.get 7
                call $dynrt_dynArrGet
                local.set 8
                local.get 8
                call $dynrt__fn30
                global.get $dynrt_global1
                local.set 8
                global.get $dynrt_global2
                local.set 9
                local.get 7
                local.get 4
                i32.lt_s
                if (result i32)  ;; label = @7
                  local.get 1
                  local.get 7
                  call $dynrt_dynArrGet
                else
                  call $dynrt_dynUndefined
                end
                local.set 10
                local.get 6
                local.get 8
                local.get 9
                local.get 10
                call $dynrt_dynSet
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
        local.get 3
        call $dynrt__fn30
        global.get $dynrt_global1
        local.set 2
        global.get $dynrt_global2
        local.set 3
        global.get $dynrt_global4
        local.set 4
        global.get $dynrt_global5
        local.set 5
        global.get $dynrt_global6
        local.set 7
        global.get $dynrt_global8
        local.set 8
        global.get $dynrt_global9
        local.set 9
        global.get $dynrt_global10
        local.set 10
        local.get 2
        local.get 3
        local.get 6
        call $dynrt_dynRun
        local.set 2
        local.get 4
        global.set $dynrt_global4
        local.get 5
        local.tee 15
        global.set $dynrt_global5
        local.get 7
        local.tee 16
        global.set $dynrt_global6
        local.get 8
        global.set $dynrt_global8
        local.get 9
        global.set $dynrt_global9
        local.get 10
        global.set $dynrt_global10
        local.get 2
        local.tee 17
        return
      end
    end
    local.get 3
    i32.const 8
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_global7
        local.tee 18
        i32.const 1
        i32.add
        global.set $dynrt_global7
        global.get $dynrt_global7
        local.tee 19
        local.set 2
        local.get 2
        f64.convert_i32_s
        call $dynrt_dynNumber
        return
      end
    end
    local.get 4
    i32.const 0
    i32.gt_s
    if (result i32)  ;; label = @1
      local.get 1
      i32.const 0
      call $dynrt_dynArrGet
    else
      call $dynrt_dynUndefined
    end
    local.set 2
    local.get 3
    i32.const 7
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 2
        call $dynrt_dynTag
        local.set 3
        local.get 3
        i32.const 4
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 2
            local.tee 20
            local.set 2
            local.get 2
            i32.const 8
            i32.add
            i32.const 8
            i32.add
            i32.load
            local.set 2
            local.get 2
            f64.convert_i32_s
            call $dynrt_dynNumber
            return
          end
        end
        local.get 3
        i32.const 5
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 2
            call $dynrt_dynArrLen
            local.set 2
            local.get 2
            f64.convert_i32_s
            call $dynrt_dynNumber
            return
          end
        end
        f64.const 0x0p+0 (;=0;)
        call $dynrt_dynNumber
        return
      end
    end
    local.get 2
    call $dynrt_dynToNumber
    local.set 11
    local.get 3
    i32.eqz
    if  ;; label = @1
      local.get 11
      f64.abs
      call $dynrt_dynNumber
      return
    end
    local.get 3
    i32.const 1
    i32.eq
    if  ;; label = @1
      local.get 11
      f64.sqrt
      call $dynrt_dynNumber
      return
    end
    local.get 3
    i32.const 2
    i32.eq
    if  ;; label = @1
      local.get 11
      f64.floor
      call $dynrt_dynNumber
      return
    end
    local.get 3
    i32.const 3
    i32.eq
    if  ;; label = @1
      local.get 11
      f64.ceil
      call $dynrt_dynNumber
      return
    end
    local.get 3
    i32.const 4
    i32.eq
    if  ;; label = @1
      local.get 11
      f64.const 0x1.0p-1 (;=0.5;)
      f64.add
      f64.floor
      call $dynrt_dynNumber
      return
    end
    local.get 4
    i32.const 1
    i32.gt_s
    if (result i32)  ;; label = @1
      local.get 1
      i32.const 1
      call $dynrt_dynArrGet
    else
      call $dynrt_dynUndefined
    end
    local.set 2
    local.get 2
    call $dynrt_dynToNumber
    local.set 12
    local.get 3
    i32.const 5
    i32.eq
    if  ;; label = @1
      local.get 11
      local.get 12
      f64.lt
      if (result f64)  ;; label = @2
        local.get 11
      else
        local.get 12
      end
      call $dynrt_dynNumber
      return
    end
    local.get 3
    i32.const 6
    i32.eq
    if  ;; label = @1
      local.get 11
      local.get 12
      f64.gt
      if (result f64)  ;; label = @2
        local.get 11
      else
        local.get 12
      end
      call $dynrt_dynNumber
      return
    end
    call $dynrt_dynUndefined
    return)
  (func $dynrt_dynCall0 (param i32) (result i32)
    (local i32)
    call $dynrt_dynArray
    local.set 1
    local.get 0
    local.get 1
    call $dynrt_dynApply
    return)
  (func $dynrt_dynCall1 (param i32 i32) (result i32)
    (local i32)
    call $dynrt_dynArray
    local.set 2
    local.get 2
    local.get 1
    call $dynrt_dynPush
    local.get 0
    local.get 2
    call $dynrt_dynApply
    return)
  (func $dynrt_dynCall2 (param i32 i32 i32) (result i32)
    (local i32)
    call $dynrt_dynArray
    local.set 3
    local.get 3
    local.get 1
    call $dynrt_dynPush
    local.get 3
    local.get 2
    call $dynrt_dynPush
    local.get 0
    local.get 3
    call $dynrt_dynApply
    return)
  (func $dynrt_dynCall3 (param i32 i32 i32 i32) (result i32)
    (local i32)
    call $dynrt_dynArray
    local.set 4
    local.get 4
    local.get 1
    call $dynrt_dynPush
    local.get 4
    local.get 2
    call $dynrt_dynPush
    local.get 4
    local.get 3
    call $dynrt_dynPush
    local.get 0
    local.get 4
    call $dynrt_dynApply
    return)
  (func $dynrt_dynStdEnv (result i32)
    (local i32) (local i32)
    call $dynrt_dynObject
    local.set 0
    local.get 0
    i32.const 592
    i32.const 3
    i32.const 0
    call $dynrt_dynBuiltin
    call $dynrt_dynSet
    local.get 0
    i32.const 595
    i32.const 4
    i32.const 1
    call $dynrt_dynBuiltin
    call $dynrt_dynSet
    local.get 0
    i32.const 599
    i32.const 5
    i32.const 2
    call $dynrt_dynBuiltin
    call $dynrt_dynSet
    local.get 0
    i32.const 604
    i32.const 4
    i32.const 3
    call $dynrt_dynBuiltin
    call $dynrt_dynSet
    local.get 0
    i32.const 608
    i32.const 5
    i32.const 4
    call $dynrt_dynBuiltin
    call $dynrt_dynSet
    local.get 0
    i32.const 613
    i32.const 3
    i32.const 5
    call $dynrt_dynBuiltin
    call $dynrt_dynSet
    local.get 0
    i32.const 616
    i32.const 3
    i32.const 6
    call $dynrt_dynBuiltin
    call $dynrt_dynSet
    local.get 0
    i32.const 619
    i32.const 3
    i32.const 7
    call $dynrt_dynBuiltin
    call $dynrt_dynSet
    local.get 0
    i32.const 622
    i32.const 3
    i32.const 8
    call $dynrt_dynBuiltin
    call $dynrt_dynSet
    local.get 0
    local.tee 1
    return)
  (func $dynrt_dynSideEffectCount (result i32)
    global.get $dynrt_global7
    return)
  (func $dynrt_dynResetSideEffects
    i32.const 0
    global.set $dynrt_global7)
  (func $dynrt__fn67 (param i32 i32 i32 i32) (result i32)
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
            call $dynrt__fn4
            local.get 2
            local.get 3
            local.get 4
            call $dynrt__fn4
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
  (func $dynrt_dynMember (param i32 i32 i32) (result i32)
    (local i32) (local i32)
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
        local.get 1
        local.get 2
        call $dynrt_dynGet
        local.set 3
        local.get 3
        i32.const -1
        i32.eq
        if (result i32)  ;; label = @3
          call $dynrt_dynUndefined
        else
          local.get 3
        end
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
        i32.const 625
        i32.const 6
        call $dynrt__fn67
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 0
            call $dynrt_dynArrLen
            local.set 3
            local.get 3
            f64.convert_i32_s
            call $dynrt_dynNumber
            return
          end
        end
        call $dynrt_dynUndefined
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
        i32.const 625
        i32.const 6
        call $dynrt__fn67
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
            call $dynrt_dynNumber
            return
          end
        end
        call $dynrt_dynUndefined
        return
      end
    end
    call $dynrt_dynUndefined
    return)
  (func $dynrt_dynIndexValue (param i32 i32) (result i32)
    (local i32) (local i32) (local f64)
    local.get 0
    local.set 2
    local.get 2
    i32.const 8
    i32.add
    i32.load
    local.set 2
    local.get 1
    call $dynrt_dynTag
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
            call $dynrt_dynNumberValue
            local.set 4
            local.get 4
            i32.trunc_f64_s
            local.set 2
            local.get 0
            call $dynrt_dynArrLen
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
              call $dynrt_dynUndefined
              return
            end
            local.get 0
            local.get 2
            call $dynrt_dynArrGet
            return
          end
        end
        call $dynrt_dynUndefined
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
            call $dynrt__fn30
            global.get $dynrt_global1
            local.set 2
            global.get $dynrt_global2
            local.set 3
            local.get 0
            local.get 2
            local.get 3
            call $dynrt_dynGet
            local.set 2
            local.get 2
            i32.const -1
            i32.eq
            if (result i32)  ;; label = @5
              call $dynrt_dynUndefined
            else
              local.get 2
            end
            return
          end
        end
        call $dynrt_dynUndefined
        return
      end
    end
    call $dynrt_dynUndefined
    return)
  (func $dynrt__fn70 (param i32 i32) (result i32)
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
  (func $dynrt__fn71 (param i32 i32)
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
          global.get $dynrt_global4
          local.get 1
          i32.ge_s
          if  ;; label = @4
            i32.const 0
            local.set 2
          else
            block  ;; label = @5
              local.get 0
              local.get 1
              global.get $dynrt_global4
              call $dynrt__fn4
              local.set 3
              local.get 3
              i32.const 32
              i32.eq
              if (result i32)  ;; label = @6
                i32.const 1
              else
                local.get 3
                i32.const 9
                i32.eq
              end
              if (result i32)  ;; label = @6
                i32.const 1
              else
                local.get 3
                i32.const 10
                i32.eq
              end
              if (result i32)  ;; label = @6
                i32.const 1
              else
                local.get 3
                i32.const 13
                i32.eq
              end
              if  ;; label = @6
                global.get $dynrt_global4
                i32.const 1
                i32.add
                global.set $dynrt_global4
              else
                i32.const 0
                local.set 2
              end
            end
          end
          br 1 (;@2;)
        end
      end
    end)
  (func $dynrt__fn72 (param i32 i32) (result i32)
    (local i32)
    global.get $dynrt_global4
    local.get 1
    i32.ge_s
    if  ;; label = @1
      i32.const -1
      return
    end
    local.get 0
    local.get 1
    global.get $dynrt_global4
    call $dynrt__fn4
    return)
  (func $dynrt__fn73 (param i32 i32) (result i32)
    (local i32)
    global.get $dynrt_global4
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
    global.get $dynrt_global4
    i32.const 1
    i32.add
    call $dynrt__fn4
    return)
  (func $dynrt__fn74 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32)
    global.get $dynrt_global4
    local.tee 4
    local.set 2
    local.get 0
    local.get 1
    call $dynrt__fn72
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
            global.get $dynrt_global4
            i32.const 1
            i32.add
            global.set $dynrt_global4
            local.get 0
            local.get 1
            call $dynrt__fn72
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
        global.get $dynrt_global4
        i32.const 1
        i32.add
        global.set $dynrt_global4
        local.get 0
        local.get 1
        call $dynrt__fn72
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
                global.get $dynrt_global4
                i32.const 1
                i32.add
                global.set $dynrt_global4
                local.get 0
                local.get 1
                call $dynrt__fn72
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
        global.get $dynrt_global4
        i32.const 1
        i32.add
        global.set $dynrt_global4
        local.get 0
        local.get 1
        call $dynrt__fn72
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
            global.get $dynrt_global4
            i32.const 1
            i32.add
            global.set $dynrt_global4
            local.get 0
            local.get 1
            call $dynrt__fn72
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
                global.get $dynrt_global4
                i32.const 1
                i32.add
                global.set $dynrt_global4
                local.get 0
                local.get 1
                call $dynrt__fn72
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
    global.get $dynrt_global4
    call $dynrt__fn3
    local.set 3
    nop
    local.set 2
    local.get 2
    local.get 3
    call $dynrt__fn8
    call $dynrt_dynNumber
    return)
  (func $dynrt__fn75 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt__fn72
    local.set 2
    global.get $dynrt_global4
    i32.const 1
    local.tee 16
    i32.add
    global.set $dynrt_global4
    i32.const 570
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
          global.get $dynrt_global4
          local.get 1
          i32.ge_s
          if  ;; label = @4
            i32.const 0
            local.set 5
          else
            block  ;; label = @5
              local.get 0
              local.get 1
              global.get $dynrt_global4
              call $dynrt__fn4
              local.set 6
              local.get 6
              local.get 2
              i32.eq
              if  ;; label = @6
                block  ;; label = @7
                  global.get $dynrt_global4
                  i32.const 1
                  i32.add
                  global.set $dynrt_global4
                  i32.const 0
                  local.set 5
                end
              else
                local.get 6
                i32.const 92
                i32.eq
                if  ;; label = @7
                  block  ;; label = @8
                    global.get $dynrt_global4
                    i32.const 1
                    i32.add
                    local.tee 9
                    global.set $dynrt_global4
                    local.get 0
                    local.get 1
                    global.get $dynrt_global4
                    call $dynrt__fn4
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
                    call $dynrt__fn2
                    local.set 4
                    nop
                    local.set 3
                    global.get $dynrt_global4
                    i32.const 1
                    i32.add
                    local.tee 12
                    global.set $dynrt_global4
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
                    call $dynrt__fn2
                    local.set 4
                    nop
                    local.set 3
                    global.get $dynrt_global4
                    i32.const 1
                    local.tee 15
                    i32.add
                    global.set $dynrt_global4
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
    call $dynrt_dynString
    return)
  (func $dynrt__fn76 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt__fn71
    local.get 0
    local.get 1
    call $dynrt__fn72
    local.set 2
    local.get 2
    i32.const 40
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_global4
        i32.const 1
        i32.add
        global.set $dynrt_global4
        local.get 0
        local.get 1
        call $dynrt__fn85
        local.set 2
        local.get 0
        local.get 1
        call $dynrt__fn71
        local.get 0
        local.get 1
        call $dynrt__fn72
        i32.const 41
        i32.eq
        if  ;; label = @3
          global.get $dynrt_global4
          i32.const 1
          i32.add
          global.set $dynrt_global4
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
      call $dynrt__fn75
      return
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
      call $dynrt__fn74
      return
    end
    local.get 2
    i32.const 46
    i32.eq
    if  ;; label = @1
      local.get 0
      local.get 1
      call $dynrt__fn74
      return
    end
    local.get 2
    i32.const 0
    call $dynrt__fn70
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_global4
        local.tee 4
        local.set 3
        local.get 2
        local.tee 5
        local.set 2
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 2
              i32.const 1
              call $dynrt__fn70
              i32.const 1
              i32.eq
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                global.get $dynrt_global4
                i32.const 1
                i32.add
                global.set $dynrt_global4
                local.get 0
                local.get 1
                call $dynrt__fn72
                local.set 2
              end
              br 1 (;@4;)
            end
          end
        end
        local.get 0
        local.get 1
        local.get 3
        global.get $dynrt_global4
        call $dynrt__fn3
        local.set 3
        nop
        local.set 2
        local.get 2
        local.get 3
        i32.const 575
        i32.const 4
        call $dynrt__fn67
        i32.const 1
        i32.eq
        if  ;; label = @3
          i32.const 1
          call $dynrt_dynBool
          return
        end
        local.get 2
        local.get 3
        i32.const 570
        i32.const 5
        call $dynrt__fn67
        i32.const 1
        i32.eq
        if  ;; label = @3
          i32.const 0
          call $dynrt_dynBool
          return
        end
        local.get 2
        local.get 3
        i32.const 579
        i32.const 4
        call $dynrt__fn67
        i32.const 1
        i32.eq
        if  ;; label = @3
          call $dynrt_dynNull
          return
        end
        local.get 2
        local.get 3
        i32.const 583
        i32.const 9
        call $dynrt__fn67
        i32.const 1
        i32.eq
        if  ;; label = @3
          call $dynrt_dynUndefined
          return
        end
        global.get $dynrt_global5
        i32.const -1
        i32.eq
        if  ;; label = @3
          call $dynrt_dynUndefined
          return
        end
        global.get $dynrt_global5
        local.get 2
        local.get 3
        call $dynrt__fn58
        local.set 2
        local.get 2
        i32.const -1
        i32.eq
        if (result i32)  ;; label = @3
          call $dynrt_dynUndefined
        else
          local.get 2
        end
        return
      end
    end
    call $dynrt_dynUndefined
    return)
  (func $dynrt__fn77 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt__fn76
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
            call $dynrt__fn71
            local.get 0
            local.get 1
            call $dynrt__fn72
            local.set 4
            local.get 4
            i32.const 46
            i32.eq
            if  ;; label = @5
              block  ;; label = @6
                global.get $dynrt_global4
                local.tee 7
                i32.const 1
                i32.add
                global.set $dynrt_global4
                local.get 0
                local.get 1
                call $dynrt__fn71
                global.get $dynrt_global4
                local.tee 8
                local.set 4
                local.get 0
                local.get 1
                call $dynrt__fn72
                local.set 5
                block  ;; label = @7
                  loop  ;; label = @8
                    block  ;; label = @9
                      local.get 5
                      i32.const 1
                      call $dynrt__fn70
                      i32.const 1
                      i32.eq
                      i32.eqz
                      br_if 2 (;@7;)
                      block  ;; label = @10
                        global.get $dynrt_global4
                        i32.const 1
                        i32.add
                        global.set $dynrt_global4
                        local.get 0
                        local.get 1
                        call $dynrt__fn72
                        local.set 5
                      end
                      br 1 (;@8;)
                    end
                  end
                end
                local.get 0
                local.get 1
                local.get 4
                global.get $dynrt_global4
                call $dynrt__fn3
                local.set 5
                nop
                local.set 4
                local.get 2
                local.get 4
                local.get 5
                call $dynrt_dynMember
                local.set 2
              end
            else
              local.get 4
              i32.const 91
              i32.eq
              if  ;; label = @6
                block  ;; label = @7
                  global.get $dynrt_global4
                  i32.const 1
                  i32.add
                  global.set $dynrt_global4
                  local.get 0
                  local.get 1
                  call $dynrt__fn85
                  local.set 4
                  local.get 0
                  local.get 1
                  call $dynrt__fn71
                  local.get 0
                  local.get 1
                  call $dynrt__fn72
                  i32.const 93
                  i32.eq
                  if  ;; label = @8
                    global.get $dynrt_global4
                    i32.const 1
                    i32.add
                    global.set $dynrt_global4
                  end
                  local.get 2
                  local.get 4
                  call $dynrt_dynIndexValue
                  local.set 2
                end
              else
                local.get 4
                i32.const 40
                i32.eq
                if  ;; label = @7
                  block  ;; label = @8
                    global.get $dynrt_global4
                    i32.const 1
                    i32.add
                    global.set $dynrt_global4
                    call $dynrt_dynArray
                    local.set 4
                    local.get 0
                    local.get 1
                    call $dynrt__fn71
                    local.get 0
                    local.get 1
                    call $dynrt__fn72
                    i32.const 41
                    i32.eq
                    if  ;; label = @9
                      global.get $dynrt_global4
                      i32.const 1
                      i32.add
                      global.set $dynrt_global4
                    else
                      block  ;; label = @10
                        i32.const 1
                        local.set 5
                        block  ;; label = @11
                          loop  ;; label = @12
                            block  ;; label = @13
                              local.get 5
                              i32.const 1
                              i32.eq
                              i32.eqz
                              br_if 2 (;@11;)
                              block  ;; label = @14
                                local.get 0
                                local.get 1
                                call $dynrt__fn85
                                local.set 6
                                local.get 4
                                local.get 6
                                call $dynrt_dynPush
                                local.get 0
                                local.get 1
                                call $dynrt__fn71
                                local.get 0
                                local.get 1
                                call $dynrt__fn72
                                local.set 6
                                local.get 6
                                i32.const 44
                                i32.eq
                                if  ;; label = @15
                                  global.get $dynrt_global4
                                  i32.const 1
                                  i32.add
                                  global.set $dynrt_global4
                                else
                                  block  ;; label = @16
                                    local.get 6
                                    i32.const 41
                                    i32.eq
                                    if  ;; label = @17
                                      global.get $dynrt_global4
                                      i32.const 1
                                      i32.add
                                      global.set $dynrt_global4
                                    end
                                    i32.const 0
                                    local.set 5
                                  end
                                end
                              end
                              br 1 (;@12;)
                            end
                          end
                        end
                      end
                    end
                    global.get $dynrt_global6
                    i32.const 1
                    i32.eq
                    if  ;; label = @9
                      local.get 2
                      local.get 4
                      call $dynrt_dynApply
                      local.set 2
                    else
                      call $dynrt_dynUndefined
                      local.set 2
                    end
                  end
                else
                  i32.const 0
                  local.set 3
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
  (func $dynrt__fn78 (param i32 i32) (result i32)
    (local i32)
    local.get 0
    local.get 1
    call $dynrt__fn71
    local.get 0
    local.get 1
    call $dynrt__fn72
    local.set 2
    local.get 2
    i32.const 45
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_global4
        i32.const 1
        i32.add
        global.set $dynrt_global4
        local.get 0
        local.get 1
        call $dynrt__fn78
        call $dynrt_dynNeg
        return
      end
    end
    local.get 2
    i32.const 33
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_global4
        i32.const 1
        i32.add
        global.set $dynrt_global4
        local.get 0
        local.get 1
        call $dynrt__fn78
        call $dynrt_dynNot
        return
      end
    end
    local.get 2
    i32.const 43
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_global4
        i32.const 1
        i32.add
        global.set $dynrt_global4
        local.get 0
        local.get 1
        call $dynrt__fn78
        local.set 2
        local.get 2
        call $dynrt_dynToNumber
        call $dynrt_dynNumber
        return
      end
    end
    local.get 0
    local.get 1
    call $dynrt__fn77
    return)
  (func $dynrt__fn79 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt__fn78
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
            call $dynrt__fn71
            local.get 0
            local.get 1
            call $dynrt__fn72
            local.set 4
            local.get 4
            i32.const 42
            i32.eq
            if  ;; label = @5
              block  ;; label = @6
                global.get $dynrt_global4
                i32.const 1
                i32.add
                global.set $dynrt_global4
                local.get 2
                local.get 0
                local.get 1
                call $dynrt__fn78
                call $dynrt_dynMul
                local.set 2
              end
            else
              local.get 4
              i32.const 47
              i32.eq
              if  ;; label = @6
                block  ;; label = @7
                  global.get $dynrt_global4
                  i32.const 1
                  i32.add
                  global.set $dynrt_global4
                  local.get 2
                  local.get 0
                  local.get 1
                  call $dynrt__fn78
                  call $dynrt_dynDiv
                  local.set 2
                end
              else
                local.get 4
                i32.const 37
                i32.eq
                if  ;; label = @7
                  block  ;; label = @8
                    global.get $dynrt_global4
                    i32.const 1
                    i32.add
                    global.set $dynrt_global4
                    local.get 2
                    local.get 0
                    local.get 1
                    call $dynrt__fn78
                    call $dynrt_dynMod
                    local.set 2
                  end
                else
                  i32.const 0
                  local.set 3
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
  (func $dynrt__fn80 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt__fn79
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
            call $dynrt__fn71
            local.get 0
            local.get 1
            call $dynrt__fn72
            local.set 4
            local.get 4
            i32.const 43
            i32.eq
            if  ;; label = @5
              block  ;; label = @6
                global.get $dynrt_global4
                i32.const 1
                i32.add
                global.set $dynrt_global4
                local.get 2
                local.get 0
                local.get 1
                call $dynrt__fn79
                call $dynrt_dynAdd
                local.set 2
              end
            else
              local.get 4
              i32.const 45
              i32.eq
              if  ;; label = @6
                block  ;; label = @7
                  global.get $dynrt_global4
                  i32.const 1
                  i32.add
                  global.set $dynrt_global4
                  local.get 2
                  local.get 0
                  local.get 1
                  call $dynrt__fn79
                  call $dynrt_dynSub
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
  (func $dynrt__fn81 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt__fn80
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
            call $dynrt__fn71
            local.get 0
            local.get 1
            call $dynrt__fn72
            local.set 4
            local.get 0
            local.get 1
            call $dynrt__fn73
            local.set 5
            local.get 4
            i32.const 60
            i32.eq
            if  ;; label = @5
              local.get 5
              i32.const 61
              i32.eq
              if  ;; label = @6
                block  ;; label = @7
                  global.get $dynrt_global4
                  i32.const 2
                  i32.add
                  global.set $dynrt_global4
                  local.get 2
                  local.get 0
                  local.get 1
                  call $dynrt__fn80
                  call $dynrt_dynLe
                  local.set 2
                end
              else
                block  ;; label = @7
                  global.get $dynrt_global4
                  i32.const 1
                  i32.add
                  global.set $dynrt_global4
                  local.get 2
                  local.get 0
                  local.get 1
                  call $dynrt__fn80
                  call $dynrt_dynLt
                  local.set 2
                end
              end
            else
              local.get 4
              i32.const 62
              i32.eq
              if  ;; label = @6
                local.get 5
                i32.const 61
                i32.eq
                if  ;; label = @7
                  block  ;; label = @8
                    global.get $dynrt_global4
                    i32.const 2
                    i32.add
                    global.set $dynrt_global4
                    local.get 2
                    local.get 0
                    local.get 1
                    call $dynrt__fn80
                    call $dynrt_dynGe
                    local.set 2
                  end
                else
                  block  ;; label = @8
                    global.get $dynrt_global4
                    i32.const 1
                    i32.add
                    global.set $dynrt_global4
                    local.get 2
                    local.get 0
                    local.get 1
                    call $dynrt__fn80
                    call $dynrt_dynGt
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
  (func $dynrt__fn82 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt__fn81
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
            call $dynrt__fn71
            local.get 0
            local.get 1
            call $dynrt__fn72
            local.set 4
            local.get 0
            local.get 1
            call $dynrt__fn73
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
                global.get $dynrt_global4
                i32.const 2
                i32.add
                global.set $dynrt_global4
                local.get 0
                local.get 1
                call $dynrt__fn72
                i32.const 61
                i32.eq
                if  ;; label = @7
                  global.get $dynrt_global4
                  i32.const 1
                  i32.add
                  global.set $dynrt_global4
                end
                local.get 0
                local.get 1
                call $dynrt__fn81
                local.set 4
                local.get 2
                local.get 4
                call $dynrt_dynStrictEq
                call $dynrt_dynBool
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
                  global.get $dynrt_global4
                  i32.const 2
                  i32.add
                  global.set $dynrt_global4
                  local.get 0
                  local.get 1
                  call $dynrt__fn72
                  i32.const 61
                  i32.eq
                  if  ;; label = @8
                    global.get $dynrt_global4
                    i32.const 1
                    i32.add
                    global.set $dynrt_global4
                  end
                  local.get 0
                  local.get 1
                  call $dynrt__fn81
                  local.set 4
                  local.get 2
                  local.get 4
                  call $dynrt_dynStrictEq
                  i32.eqz
                  if (result i32)  ;; label = @8
                    i32.const 1
                  else
                    i32.const 0
                  end
                  call $dynrt_dynBool
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
  (func $dynrt__fn83 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt__fn82
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
            call $dynrt__fn71
            local.get 0
            local.get 1
            call $dynrt__fn72
            i32.const 38
            i32.eq
            if (result i32)  ;; label = @5
              local.get 0
              local.get 1
              call $dynrt__fn73
              i32.const 38
              i32.eq
            else
              i32.const 0
            end
            if  ;; label = @5
              block  ;; label = @6
                global.get $dynrt_global4
                i32.const 2
                i32.add
                global.set $dynrt_global4
                local.get 2
                call $dynrt_dynToBool
                local.set 4
                global.get $dynrt_global6
                local.set 5
                local.get 4
                i32.eqz
                if  ;; label = @7
                  i32.const 0
                  global.set $dynrt_global6
                end
                local.get 0
                local.get 1
                call $dynrt__fn82
                local.set 6
                local.get 5
                global.set $dynrt_global6
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
  (func $dynrt__fn84 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt__fn83
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
            call $dynrt__fn71
            local.get 0
            local.get 1
            call $dynrt__fn72
            i32.const 124
            i32.eq
            if (result i32)  ;; label = @5
              local.get 0
              local.get 1
              call $dynrt__fn73
              i32.const 124
              i32.eq
            else
              i32.const 0
            end
            if  ;; label = @5
              block  ;; label = @6
                global.get $dynrt_global4
                i32.const 2
                i32.add
                global.set $dynrt_global4
                local.get 2
                call $dynrt_dynToBool
                local.set 4
                global.get $dynrt_global6
                local.set 5
                local.get 4
                i32.const 1
                i32.eq
                if  ;; label = @7
                  i32.const 0
                  global.set $dynrt_global6
                end
                local.get 0
                local.get 1
                call $dynrt__fn83
                local.set 6
                local.get 5
                global.set $dynrt_global6
                local.get 4
                i32.eqz
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
  (func $dynrt__fn85 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt__fn84
    local.set 2
    local.get 0
    local.get 1
    call $dynrt__fn71
    local.get 0
    local.get 1
    call $dynrt__fn72
    i32.const 63
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_global4
        i32.const 1
        i32.add
        global.set $dynrt_global4
        local.get 2
        call $dynrt_dynToBool
        local.set 2
        global.get $dynrt_global6
        local.set 3
        local.get 2
        i32.eqz
        if  ;; label = @3
          i32.const 0
          global.set $dynrt_global6
        end
        local.get 0
        local.get 1
        call $dynrt__fn85
        local.set 4
        local.get 3
        local.tee 6
        global.set $dynrt_global6
        local.get 0
        local.get 1
        call $dynrt__fn71
        local.get 0
        local.get 1
        call $dynrt__fn72
        i32.const 58
        i32.eq
        if  ;; label = @3
          global.get $dynrt_global4
          i32.const 1
          i32.add
          global.set $dynrt_global4
        end
        local.get 2
        i32.const 1
        i32.eq
        if  ;; label = @3
          i32.const 0
          global.set $dynrt_global6
        end
        local.get 0
        local.get 1
        call $dynrt__fn85
        local.set 5
        local.get 3
        local.tee 7
        global.set $dynrt_global6
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
  (func $dynrt_dynEval (param i32 i32) (result i32)
    i32.const 0
    global.set $dynrt_global4
    i32.const -1
    global.set $dynrt_global5
    i32.const 1
    global.set $dynrt_global6
    local.get 0
    local.get 1
    call $dynrt__fn85
    return)
  (func $dynrt_dynEvalEnv (param i32 i32 i32) (result i32)
    i32.const 0
    global.set $dynrt_global4
    local.get 2
    global.set $dynrt_global5
    i32.const 1
    global.set $dynrt_global6
    local.get 0
    local.get 1
    call $dynrt__fn85
    return)
  (func $dynrt__fn88 (param i32 i32)
    (local i32) (local i32) (local i32) (local i32)
    global.get $dynrt_global4
    local.tee 4
    local.set 2
    local.get 0
    local.get 1
    call $dynrt__fn72
    local.set 3
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 3
          i32.const 1
          call $dynrt__fn70
          i32.const 1
          i32.eq
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            global.get $dynrt_global4
            i32.const 1
            i32.add
            global.set $dynrt_global4
            local.get 0
            local.get 1
            call $dynrt__fn72
            local.set 3
          end
          br 1 (;@2;)
        end
      end
    end
    local.get 0
    local.get 1
    local.get 2
    global.get $dynrt_global4
    call $dynrt__fn3
    local.set 3
    nop
    local.set 2
    local.get 2
    local.tee 5
    global.set $dynrt_global1
    local.get 3
    global.set $dynrt_global2
    return)
  (func $dynrt__fn89 (param i32 i32)
    (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt__fn71
    local.get 0
    local.get 1
    call $dynrt__fn88
    global.get $dynrt_global1
    local.set 2
    global.get $dynrt_global2
    local.set 3
    local.get 0
    local.get 1
    call $dynrt__fn71
    call $dynrt_dynUndefined
    local.set 4
    local.get 0
    local.get 1
    call $dynrt__fn72
    i32.const 61
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_global4
        i32.const 1
        i32.add
        global.set $dynrt_global4
        local.get 0
        local.get 1
        call $dynrt__fn85
        local.set 4
      end
    end
    global.get $dynrt_global6
    i32.const 1
    i32.eq
    if  ;; label = @1
      global.get $dynrt_global5
      local.get 2
      local.get 3
      local.get 4
      call $dynrt_dynSet
    end
    local.get 0
    local.get 1
    call $dynrt__fn71
    local.get 0
    local.get 1
    call $dynrt__fn72
    i32.const 59
    i32.eq
    if  ;; label = @1
      global.get $dynrt_global4
      i32.const 1
      i32.add
      global.set $dynrt_global4
    end)
  (func $dynrt__fn90 (param i32 i32)
    (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt__fn71
    local.get 0
    local.get 1
    call $dynrt__fn72
    local.set 2
    call $dynrt_dynUndefined
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
      call $dynrt__fn85
      local.set 3
    end
    global.get $dynrt_global6
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 3
        global.set $dynrt_global9
        i32.const 1
        global.set $dynrt_global8
      end
    end
    local.get 0
    local.get 1
    call $dynrt__fn71
    local.get 0
    local.get 1
    call $dynrt__fn72
    i32.const 59
    i32.eq
    if  ;; label = @1
      global.get $dynrt_global4
      i32.const 1
      i32.add
      global.set $dynrt_global4
    end)
  (func $dynrt__fn91 (param i32 i32)
    (local i32) (local i32) (local i32) (local i32) (local i32)
    global.get $dynrt_global6
    local.set 2
    local.get 0
    local.get 1
    call $dynrt__fn71
    local.get 0
    local.get 1
    call $dynrt__fn72
    i32.const 40
    i32.eq
    if  ;; label = @1
      global.get $dynrt_global4
      i32.const 1
      i32.add
      global.set $dynrt_global4
    end
    local.get 0
    local.get 1
    call $dynrt__fn85
    local.set 3
    local.get 0
    local.get 1
    call $dynrt__fn71
    local.get 0
    local.get 1
    call $dynrt__fn72
    i32.const 41
    i32.eq
    if  ;; label = @1
      global.get $dynrt_global4
      i32.const 1
      i32.add
      global.set $dynrt_global4
    end
    local.get 2
    i32.const 1
    i32.eq
    if (result i32)  ;; label = @1
      local.get 3
      call $dynrt_dynToBool
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
    global.set $dynrt_global6
    local.get 0
    local.get 1
    call $dynrt__fn94
    local.get 2
    global.set $dynrt_global6
    local.get 0
    local.get 1
    call $dynrt__fn71
    local.get 0
    local.get 1
    call $dynrt__fn72
    i32.const 0
    call $dynrt__fn70
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_global4
        local.set 4
        local.get 0
        local.get 1
        call $dynrt__fn88
        global.get $dynrt_global1
        local.set 5
        global.get $dynrt_global2
        local.set 6
        local.get 5
        local.get 6
        i32.const 631
        i32.const 4
        call $dynrt__fn67
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
            global.set $dynrt_global6
            local.get 0
            local.get 1
            call $dynrt__fn94
            local.get 2
            global.set $dynrt_global6
          end
        else
          local.get 4
          global.set $dynrt_global4
        end
      end
    end)
  (func $dynrt__fn92 (param i32 i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    global.get $dynrt_global6
    local.set 2
    local.get 0
    local.get 1
    call $dynrt__fn71
    local.get 0
    local.get 1
    call $dynrt__fn72
    i32.const 40
    i32.eq
    if  ;; label = @1
      global.get $dynrt_global4
      i32.const 1
      i32.add
      global.set $dynrt_global4
    end
    global.get $dynrt_global4
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
            global.set $dynrt_global4
            local.get 0
            local.get 1
            call $dynrt__fn85
            local.set 6
            local.get 0
            local.get 1
            call $dynrt__fn71
            local.get 0
            local.get 1
            call $dynrt__fn72
            i32.const 41
            i32.eq
            if  ;; label = @5
              global.get $dynrt_global4
              i32.const 1
              i32.add
              global.set $dynrt_global4
            end
            local.get 2
            i32.const 1
            i32.eq
            if (result i32)  ;; label = @5
              local.get 6
              call $dynrt_dynToBool
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
                local.tee 7
                global.set $dynrt_global6
                local.get 0
                local.get 1
                call $dynrt__fn94
                local.get 2
                global.set $dynrt_global6
                global.get $dynrt_global8
                i32.const 1
                i32.eq
                if  ;; label = @7
                  i32.const 0
                  local.set 4
                end
                local.get 5
                i32.const 1
                local.tee 8
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
                local.tee 9
                global.set $dynrt_global6
                local.get 0
                local.get 1
                call $dynrt__fn94
                local.get 2
                global.set $dynrt_global6
                i32.const 0
                local.tee 10
                local.set 4
              end
            end
          end
          br 1 (;@2;)
        end
      end
    end)
  (func $dynrt__fn93 (param i32 i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt__fn71
    local.get 0
    local.get 1
    call $dynrt__fn88
    global.get $dynrt_global1
    local.set 2
    global.get $dynrt_global2
    local.set 3
    local.get 0
    local.get 1
    call $dynrt__fn71
    call $dynrt_dynArray
    local.set 4
    local.get 0
    local.get 1
    call $dynrt__fn72
    i32.const 40
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_global4
        i32.const 1
        i32.add
        global.set $dynrt_global4
        local.get 0
        local.get 1
        call $dynrt__fn71
        local.get 0
        local.get 1
        call $dynrt__fn72
        i32.const 41
        i32.eq
        if  ;; label = @3
          global.get $dynrt_global4
          i32.const 1
          i32.add
          global.set $dynrt_global4
        else
          block  ;; label = @4
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
                    call $dynrt__fn71
                    local.get 0
                    local.get 1
                    call $dynrt__fn88
                    global.get $dynrt_global1
                    local.set 6
                    global.get $dynrt_global2
                    local.set 7
                    local.get 4
                    local.get 6
                    local.get 7
                    call $dynrt_dynString
                    call $dynrt_dynPush
                    local.get 0
                    local.get 1
                    call $dynrt__fn71
                    local.get 0
                    local.get 1
                    call $dynrt__fn72
                    local.set 6
                    local.get 6
                    i32.const 44
                    i32.eq
                    if  ;; label = @9
                      global.get $dynrt_global4
                      i32.const 1
                      i32.add
                      global.set $dynrt_global4
                    else
                      block  ;; label = @10
                        local.get 6
                        i32.const 41
                        i32.eq
                        if  ;; label = @11
                          global.get $dynrt_global4
                          i32.const 1
                          i32.add
                          global.set $dynrt_global4
                        end
                        i32.const 0
                        local.set 5
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
    local.get 0
    local.get 1
    call $dynrt__fn71
    i32.const 570
    i32.const 0
    call $dynrt_dynString
    local.set 5
    local.get 0
    local.get 1
    call $dynrt__fn72
    i32.const 123
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_global4
        local.tee 15
        i32.const 1
        local.tee 16
        i32.add
        global.set $dynrt_global4
        global.get $dynrt_global4
        local.tee 17
        local.set 5
        i32.const 1
        local.tee 18
        local.set 6
        i32.const 0
        local.tee 19
        local.set 7
        local.get 19
        local.set 8
        local.get 18
        local.set 9
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 9
              i32.const 1
              i32.eq
              if (result i32)  ;; label = @6
                global.get $dynrt_global4
                local.get 1
                i32.lt_s
              else
                i32.const 0
              end
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                local.get 0
                local.get 1
                global.get $dynrt_global4
                call $dynrt__fn4
                local.set 10
                local.get 7
                i32.const 1
                i32.eq
                if  ;; label = @7
                  local.get 10
                  i32.const 92
                  i32.eq
                  if  ;; label = @8
                    global.get $dynrt_global4
                    i32.const 2
                    i32.add
                    global.set $dynrt_global4
                  else
                    local.get 10
                    local.get 8
                    i32.eq
                    if  ;; label = @9
                      block  ;; label = @10
                        i32.const 0
                        local.set 7
                        global.get $dynrt_global4
                        i32.const 1
                        i32.add
                        global.set $dynrt_global4
                      end
                    else
                      global.get $dynrt_global4
                      i32.const 1
                      i32.add
                      global.set $dynrt_global4
                    end
                  end
                else
                  local.get 10
                  i32.const 39
                  i32.eq
                  if (result i32)  ;; label = @8
                    i32.const 1
                  else
                    local.get 10
                    i32.const 34
                    i32.eq
                  end
                  if  ;; label = @8
                    block  ;; label = @9
                      i32.const 1
                      local.tee 11
                      local.set 7
                      local.get 10
                      local.set 8
                      global.get $dynrt_global4
                      i32.const 1
                      local.tee 12
                      i32.add
                      global.set $dynrt_global4
                    end
                  else
                    local.get 10
                    i32.const 123
                    i32.eq
                    if  ;; label = @9
                      block  ;; label = @10
                        local.get 6
                        i32.const 1
                        local.tee 13
                        i32.add
                        local.set 6
                        global.get $dynrt_global4
                        i32.const 1
                        local.tee 14
                        i32.add
                        global.set $dynrt_global4
                      end
                    else
                      local.get 10
                      i32.const 125
                      i32.eq
                      if  ;; label = @10
                        block  ;; label = @11
                          local.get 6
                          i32.const 1
                          i32.sub
                          local.set 6
                          local.get 6
                          i32.eqz
                          if  ;; label = @12
                            i32.const 0
                            local.set 9
                          else
                            global.get $dynrt_global4
                            i32.const 1
                            i32.add
                            global.set $dynrt_global4
                          end
                        end
                      else
                        global.get $dynrt_global4
                        i32.const 1
                        i32.add
                        global.set $dynrt_global4
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
        local.get 5
        global.get $dynrt_global4
        call $dynrt__fn3
        local.set 6
        nop
        local.set 5
        local.get 5
        local.get 6
        call $dynrt_dynString
        local.set 5
        local.get 0
        local.get 1
        call $dynrt__fn72
        i32.const 125
        i32.eq
        if  ;; label = @3
          global.get $dynrt_global4
          i32.const 1
          i32.add
          global.set $dynrt_global4
        end
      end
    end
    local.get 4
    local.get 5
    global.get $dynrt_global5
    call $dynrt__fn56
    local.set 4
    global.get $dynrt_global6
    i32.const 1
    i32.eq
    if  ;; label = @1
      global.get $dynrt_global5
      local.get 2
      local.get 3
      local.get 4
      call $dynrt_dynSet
    end)
  (func $dynrt__fn94 (param i32 i32)
    (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt__fn71
    local.get 0
    local.get 1
    call $dynrt__fn72
    local.set 2
    local.get 2
    i32.const 123
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_global4
        i32.const 1
        i32.add
        global.set $dynrt_global4
        local.get 0
        local.get 1
        call $dynrt__fn95
        local.get 0
        local.get 1
        call $dynrt__fn71
        local.get 0
        local.get 1
        call $dynrt__fn72
        i32.const 125
        i32.eq
        if  ;; label = @3
          global.get $dynrt_global4
          i32.const 1
          i32.add
          global.set $dynrt_global4
        end
        return
      end
    end
    local.get 2
    i32.const 59
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_global4
        i32.const 1
        i32.add
        global.set $dynrt_global4
        return
      end
    end
    local.get 2
    i32.const 0
    call $dynrt__fn70
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_global4
        local.set 2
        local.get 0
        local.get 1
        call $dynrt__fn88
        global.get $dynrt_global1
        local.set 3
        global.get $dynrt_global2
        local.set 4
        local.get 3
        local.get 4
        i32.const 635
        i32.const 3
        call $dynrt__fn67
        i32.const 1
        i32.eq
        if (result i32)  ;; label = @3
          i32.const 1
        else
          local.get 3
          local.get 4
          i32.const 638
          i32.const 5
          call $dynrt__fn67
          i32.const 1
          i32.eq
        end
        if (result i32)  ;; label = @3
          i32.const 1
        else
          local.get 3
          local.get 4
          i32.const 643
          i32.const 3
          call $dynrt__fn67
          i32.const 1
          i32.eq
        end
        if  ;; label = @3
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt__fn89
            return
          end
        end
        local.get 3
        local.get 4
        i32.const 646
        i32.const 2
        call $dynrt__fn67
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt__fn91
            return
          end
        end
        local.get 3
        local.get 4
        i32.const 648
        i32.const 5
        call $dynrt__fn67
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt__fn92
            return
          end
        end
        local.get 3
        local.get 4
        i32.const 653
        i32.const 6
        call $dynrt__fn67
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt__fn90
            return
          end
        end
        local.get 3
        local.get 4
        i32.const 659
        i32.const 8
        call $dynrt__fn67
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt__fn93
            return
          end
        end
        local.get 0
        local.get 1
        call $dynrt__fn71
        local.get 0
        local.get 1
        call $dynrt__fn72
        local.set 5
        local.get 5
        i32.const 61
        i32.eq
        if (result i32)  ;; label = @3
          local.get 0
          local.get 1
          call $dynrt__fn73
          i32.const 61
          i32.ne
        else
          i32.const 0
        end
        if  ;; label = @3
          block  ;; label = @4
            global.get $dynrt_global4
            i32.const 1
            i32.add
            global.set $dynrt_global4
            local.get 0
            local.get 1
            call $dynrt__fn85
            local.set 2
            global.get $dynrt_global6
            i32.const 1
            i32.eq
            if  ;; label = @5
              global.get $dynrt_global5
              local.get 3
              local.get 4
              local.get 2
              call $dynrt_dynSet
            end
            local.get 0
            local.get 1
            call $dynrt__fn71
            local.get 0
            local.get 1
            call $dynrt__fn72
            i32.const 59
            i32.eq
            if  ;; label = @5
              global.get $dynrt_global4
              i32.const 1
              i32.add
              global.set $dynrt_global4
            end
            return
          end
        end
        local.get 2
        global.set $dynrt_global4
        local.get 0
        local.get 1
        call $dynrt__fn85
        local.set 2
        global.get $dynrt_global6
        i32.const 1
        i32.eq
        if  ;; label = @3
          local.get 2
          global.set $dynrt_global10
        end
        local.get 0
        local.get 1
        call $dynrt__fn71
        local.get 0
        local.get 1
        call $dynrt__fn72
        i32.const 59
        i32.eq
        if  ;; label = @3
          global.get $dynrt_global4
          i32.const 1
          i32.add
          global.set $dynrt_global4
        end
        return
      end
    end
    local.get 0
    local.get 1
    call $dynrt__fn85
    local.set 2
    global.get $dynrt_global6
    i32.const 1
    i32.eq
    if  ;; label = @1
      local.get 2
      global.set $dynrt_global10
    end
    local.get 0
    local.get 1
    call $dynrt__fn71
    local.get 0
    local.get 1
    call $dynrt__fn72
    i32.const 59
    i32.eq
    if  ;; label = @1
      global.get $dynrt_global4
      i32.const 1
      i32.add
      global.set $dynrt_global4
    end)
  (func $dynrt__fn95 (param i32 i32)
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
            call $dynrt__fn71
            local.get 0
            local.get 1
            call $dynrt__fn72
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
                global.get $dynrt_global6
                local.set 3
                global.get $dynrt_global8
                i32.const 1
                i32.eq
                if  ;; label = @7
                  i32.const 0
                  global.set $dynrt_global6
                end
                local.get 0
                local.get 1
                call $dynrt__fn94
                local.get 3
                global.set $dynrt_global6
              end
            end
          end
          br 1 (;@2;)
        end
      end
    end)
  (func $dynrt_dynRun (param i32 i32 i32) (result i32)
    (local i32) (local i32)
    i32.const 0
    local.tee 3
    global.set $dynrt_global4
    local.get 2
    global.set $dynrt_global5
    i32.const 1
    global.set $dynrt_global6
    i32.const 0
    local.tee 4
    global.set $dynrt_global8
    call $dynrt_dynUndefined
    global.set $dynrt_global9
    call $dynrt_dynUndefined
    global.set $dynrt_global10
    local.get 0
    local.get 1
    call $dynrt__fn95
    global.get $dynrt_global8
    i32.const 1
    i32.eq
    if (result i32)  ;; label = @1
      global.get $dynrt_global9
    else
      global.get $dynrt_global10
    end
    return)
  ;; data from dynrt
  (data (;0;) (i32.const 570) "")
  (data (;1;) (i32.const 570) "false")
  (data (;2;) (i32.const 575) "true")
  (data (;3;) (i32.const 579) "null")
  (data (;4;) (i32.const 583) "undefined")
  (data (;5;) (i32.const 592) "abs")
  (data (;6;) (i32.const 595) "sqrt")
  (data (;7;) (i32.const 599) "floor")
  (data (;8;) (i32.const 604) "ceil")
  (data (;9;) (i32.const 608) "round")
  (data (;10;) (i32.const 613) "min")
  (data (;11;) (i32.const 616) "max")
  (data (;12;) (i32.const 619) "len")
  (data (;13;) (i32.const 622) "inc")
  (data (;14;) (i32.const 625) "length")
  (data (;15;) (i32.const 631) "else")
  (data (;16;) (i32.const 635) "let")
  (data (;17;) (i32.const 638) "const")
  (data (;18;) (i32.const 643) "var")
  (data (;19;) (i32.const 646) "if")
  (data (;20;) (i32.const 648) "while")
  (data (;21;) (i32.const 653) "return")
  (data (;22;) (i32.const 659) "function")
)