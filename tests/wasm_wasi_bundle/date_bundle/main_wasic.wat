(module
  (import "wasi_snapshot_preview1" "proc_exit" (func $proc_exit (param i32)))
  (import "wasi_snapshot_preview1" "fd_write" (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (memory (export "memory") 2)
  (global $__heap_ptr (mut i32) (i32.const 528))
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
    (local $__iface_tmp i32)
    (global.set $guard (call $__malloc (i32.const 40)))
      (i32.store (global.get $guard) (i32.const 1))
      (i32.store offset=4 (global.get $guard) (i32.const 8))
      (i32.store offset=8 (global.get $guard) (i32.const 0))
        (i32.store (i32.const 0) (i32.const 132))
          (i32.store (i32.const 4) (i32.const 0))
          (i32.store8 (i32.const 132) (i32.const 108))
          (i32.store8 (i32.const 133) (i32.const 101))
          (i32.store8 (i32.const 134) (i32.const 97))
          (i32.store8 (i32.const 135) (i32.const 112))
          (i32.store8 (i32.const 136) (i32.const 32))
          (i32.store8 (i32.const 137) (i32.const 50))
          (i32.store8 (i32.const 138) (i32.const 48))
          (i32.store8 (i32.const 139) (i32.const 50))
          (i32.store8 (i32.const 140) (i32.const 52))
          (i32.store8 (i32.const 141) (i32.const 58))
          (i32.store8 (i32.const 142) (i32.const 32))
          (i32.store (i32.const 4) (i32.add (i32.const 11) (call $__i32_to_str (call $date_lib_modc_isLeapYear (i32.const 2024)) (i32.const 143))))
          (i32.store8 (i32.add (i32.const 132) (i32.load (i32.const 4))) (i32.const 10))
          (i32.store (i32.const 4) (i32.add (i32.load (i32.const 4)) (i32.const 1)))
          (drop (call $fd_write
            (i32.const 1)
            (i32.const 0)
            (i32.const 1)
            (i32.const 128)))
        (i32.store (i32.const 0) (i32.const 132))
          (i32.store (i32.const 4) (i32.const 0))
          (i32.store8 (i32.const 132) (i32.const 108))
          (i32.store8 (i32.const 133) (i32.const 101))
          (i32.store8 (i32.const 134) (i32.const 97))
          (i32.store8 (i32.const 135) (i32.const 112))
          (i32.store8 (i32.const 136) (i32.const 32))
          (i32.store8 (i32.const 137) (i32.const 50))
          (i32.store8 (i32.const 138) (i32.const 48))
          (i32.store8 (i32.const 139) (i32.const 50))
          (i32.store8 (i32.const 140) (i32.const 51))
          (i32.store8 (i32.const 141) (i32.const 58))
          (i32.store8 (i32.const 142) (i32.const 32))
          (i32.store (i32.const 4) (i32.add (i32.const 11) (call $__i32_to_str (call $date_lib_modc_isLeapYear (i32.const 2023)) (i32.const 143))))
          (i32.store8 (i32.add (i32.const 132) (i32.load (i32.const 4))) (i32.const 10))
          (i32.store (i32.const 4) (i32.add (i32.load (i32.const 4)) (i32.const 1)))
          (drop (call $fd_write
            (i32.const 1)
            (i32.const 0)
            (i32.const 1)
            (i32.const 128)))
        (i32.store (i32.const 0) (i32.const 132))
          (i32.store (i32.const 4) (i32.const 0))
          (i32.store8 (i32.const 132) (i32.const 108))
          (i32.store8 (i32.const 133) (i32.const 101))
          (i32.store8 (i32.const 134) (i32.const 97))
          (i32.store8 (i32.const 135) (i32.const 112))
          (i32.store8 (i32.const 136) (i32.const 32))
          (i32.store8 (i32.const 137) (i32.const 50))
          (i32.store8 (i32.const 138) (i32.const 48))
          (i32.store8 (i32.const 139) (i32.const 48))
          (i32.store8 (i32.const 140) (i32.const 48))
          (i32.store8 (i32.const 141) (i32.const 58))
          (i32.store8 (i32.const 142) (i32.const 32))
          (i32.store (i32.const 4) (i32.add (i32.const 11) (call $__i32_to_str (call $date_lib_modc_isLeapYear (i32.const 2000)) (i32.const 143))))
          (i32.store8 (i32.add (i32.const 132) (i32.load (i32.const 4))) (i32.const 10))
          (i32.store (i32.const 4) (i32.add (i32.load (i32.const 4)) (i32.const 1)))
          (drop (call $fd_write
            (i32.const 1)
            (i32.const 0)
            (i32.const 1)
            (i32.const 128)))
        (i32.store (i32.const 0) (i32.const 132))
          (i32.store (i32.const 4) (i32.const 0))
          (i32.store8 (i32.const 132) (i32.const 108))
          (i32.store8 (i32.const 133) (i32.const 101))
          (i32.store8 (i32.const 134) (i32.const 97))
          (i32.store8 (i32.const 135) (i32.const 112))
          (i32.store8 (i32.const 136) (i32.const 32))
          (i32.store8 (i32.const 137) (i32.const 49))
          (i32.store8 (i32.const 138) (i32.const 57))
          (i32.store8 (i32.const 139) (i32.const 48))
          (i32.store8 (i32.const 140) (i32.const 48))
          (i32.store8 (i32.const 141) (i32.const 58))
          (i32.store8 (i32.const 142) (i32.const 32))
          (i32.store (i32.const 4) (i32.add (i32.const 11) (call $__i32_to_str (call $date_lib_modc_isLeapYear (i32.const 1900)) (i32.const 143))))
          (i32.store8 (i32.add (i32.const 132) (i32.load (i32.const 4))) (i32.const 10))
          (i32.store (i32.const 4) (i32.add (i32.load (i32.const 4)) (i32.const 1)))
          (drop (call $fd_write
            (i32.const 1)
            (i32.const 0)
            (i32.const 1)
            (i32.const 128)))
    (call $check (if (result i32) (i32.eq (call $date_lib_modc_isLeapYear (i32.const 2024)) (i32.const 1)) (then (i32.const 1)) (else (i32.const 0))))
    (call $check (if (result i32) (i32.eq (call $date_lib_modc_isLeapYear (i32.const 2023)) (i32.const 0)) (then (i32.const 1)) (else (i32.const 0))))
    (call $check (if (result i32) (i32.eq (call $date_lib_modc_isLeapYear (i32.const 2000)) (i32.const 1)) (then (i32.const 1)) (else (i32.const 0))))
    (call $check (if (result i32) (i32.eq (call $date_lib_modc_isLeapYear (i32.const 1900)) (i32.const 0)) (then (i32.const 1)) (else (i32.const 0))))
    (call $check (if (result i32) (i32.eq (call $date_lib_modc_daysInMonth (i32.const 2024) (i32.const 2)) (i32.const 29)) (then (i32.const 1)) (else (i32.const 0))))
    (call $check (if (result i32) (i32.eq (call $date_lib_modc_daysInMonth (i32.const 2023) (i32.const 2)) (i32.const 28)) (then (i32.const 1)) (else (i32.const 0))))
    (call $check (if (result i32) (i32.eq (call $date_lib_modc_daysInMonth (i32.const 2024) (i32.const 4)) (i32.const 30)) (then (i32.const 1)) (else (i32.const 0))))
    (call $check (if (result i32) (i32.eq (call $date_lib_modc_daysInMonth (i32.const 2024) (i32.const 12)) (i32.const 31)) (then (i32.const 1)) (else (i32.const 0))))
        (i32.store (i32.const 0) (i32.const 132))
          (i32.store (i32.const 4) (i32.const 0))
          (i32.store8 (i32.const 132) (i32.const 100))
          (i32.store8 (i32.const 133) (i32.const 97))
          (i32.store8 (i32.const 134) (i32.const 121))
          (i32.store8 (i32.const 135) (i32.const 115))
          (i32.store8 (i32.const 136) (i32.const 32))
          (i32.store8 (i32.const 137) (i32.const 49))
          (i32.store8 (i32.const 138) (i32.const 57))
          (i32.store8 (i32.const 139) (i32.const 55))
          (i32.store8 (i32.const 140) (i32.const 48))
          (i32.store8 (i32.const 141) (i32.const 45))
          (i32.store8 (i32.const 142) (i32.const 48))
          (i32.store8 (i32.const 143) (i32.const 49))
          (i32.store8 (i32.const 144) (i32.const 45))
          (i32.store8 (i32.const 145) (i32.const 48))
          (i32.store8 (i32.const 146) (i32.const 49))
          (i32.store8 (i32.const 147) (i32.const 58))
          (i32.store8 (i32.const 148) (i32.const 32))
          (i32.store (i32.const 4) (i32.add (i32.const 17) (call $__i32_to_str (call $date_lib_modc_daysFromCivil (i32.const 1970) (i32.const 1) (i32.const 1)) (i32.const 149))))
          (i32.store8 (i32.add (i32.const 132) (i32.load (i32.const 4))) (i32.const 10))
          (i32.store (i32.const 4) (i32.add (i32.load (i32.const 4)) (i32.const 1)))
          (drop (call $fd_write
            (i32.const 1)
            (i32.const 0)
            (i32.const 1)
            (i32.const 128)))
        (i32.store (i32.const 0) (i32.const 132))
          (i32.store (i32.const 4) (i32.const 0))
          (i32.store8 (i32.const 132) (i32.const 100))
          (i32.store8 (i32.const 133) (i32.const 97))
          (i32.store8 (i32.const 134) (i32.const 121))
          (i32.store8 (i32.const 135) (i32.const 115))
          (i32.store8 (i32.const 136) (i32.const 32))
          (i32.store8 (i32.const 137) (i32.const 50))
          (i32.store8 (i32.const 138) (i32.const 48))
          (i32.store8 (i32.const 139) (i32.const 48))
          (i32.store8 (i32.const 140) (i32.const 48))
          (i32.store8 (i32.const 141) (i32.const 45))
          (i32.store8 (i32.const 142) (i32.const 48))
          (i32.store8 (i32.const 143) (i32.const 49))
          (i32.store8 (i32.const 144) (i32.const 45))
          (i32.store8 (i32.const 145) (i32.const 48))
          (i32.store8 (i32.const 146) (i32.const 49))
          (i32.store8 (i32.const 147) (i32.const 58))
          (i32.store8 (i32.const 148) (i32.const 32))
          (i32.store (i32.const 4) (i32.add (i32.const 17) (call $__i32_to_str (call $date_lib_modc_daysFromCivil (i32.const 2000) (i32.const 1) (i32.const 1)) (i32.const 149))))
          (i32.store8 (i32.add (i32.const 132) (i32.load (i32.const 4))) (i32.const 10))
          (i32.store (i32.const 4) (i32.add (i32.load (i32.const 4)) (i32.const 1)))
          (drop (call $fd_write
            (i32.const 1)
            (i32.const 0)
            (i32.const 1)
            (i32.const 128)))
        (i32.store (i32.const 0) (i32.const 132))
          (i32.store (i32.const 4) (i32.const 0))
          (i32.store8 (i32.const 132) (i32.const 100))
          (i32.store8 (i32.const 133) (i32.const 97))
          (i32.store8 (i32.const 134) (i32.const 121))
          (i32.store8 (i32.const 135) (i32.const 115))
          (i32.store8 (i32.const 136) (i32.const 32))
          (i32.store8 (i32.const 137) (i32.const 50))
          (i32.store8 (i32.const 138) (i32.const 48))
          (i32.store8 (i32.const 139) (i32.const 50))
          (i32.store8 (i32.const 140) (i32.const 52))
          (i32.store8 (i32.const 141) (i32.const 45))
          (i32.store8 (i32.const 142) (i32.const 48))
          (i32.store8 (i32.const 143) (i32.const 50))
          (i32.store8 (i32.const 144) (i32.const 45))
          (i32.store8 (i32.const 145) (i32.const 50))
          (i32.store8 (i32.const 146) (i32.const 57))
          (i32.store8 (i32.const 147) (i32.const 58))
          (i32.store8 (i32.const 148) (i32.const 32))
          (i32.store (i32.const 4) (i32.add (i32.const 17) (call $__i32_to_str (call $date_lib_modc_daysFromCivil (i32.const 2024) (i32.const 2) (i32.const 29)) (i32.const 149))))
          (i32.store8 (i32.add (i32.const 132) (i32.load (i32.const 4))) (i32.const 10))
          (i32.store (i32.const 4) (i32.add (i32.load (i32.const 4)) (i32.const 1)))
          (drop (call $fd_write
            (i32.const 1)
            (i32.const 0)
            (i32.const 1)
            (i32.const 128)))
        (i32.store (i32.const 0) (i32.const 132))
          (i32.store (i32.const 4) (i32.const 0))
          (i32.store8 (i32.const 132) (i32.const 100))
          (i32.store8 (i32.const 133) (i32.const 97))
          (i32.store8 (i32.const 134) (i32.const 121))
          (i32.store8 (i32.const 135) (i32.const 115))
          (i32.store8 (i32.const 136) (i32.const 32))
          (i32.store8 (i32.const 137) (i32.const 49))
          (i32.store8 (i32.const 138) (i32.const 57))
          (i32.store8 (i32.const 139) (i32.const 54))
          (i32.store8 (i32.const 140) (i32.const 57))
          (i32.store8 (i32.const 141) (i32.const 45))
          (i32.store8 (i32.const 142) (i32.const 49))
          (i32.store8 (i32.const 143) (i32.const 50))
          (i32.store8 (i32.const 144) (i32.const 45))
          (i32.store8 (i32.const 145) (i32.const 51))
          (i32.store8 (i32.const 146) (i32.const 49))
          (i32.store8 (i32.const 147) (i32.const 58))
          (i32.store8 (i32.const 148) (i32.const 32))
          (i32.store (i32.const 4) (i32.add (i32.const 17) (call $__i32_to_str (call $date_lib_modc_daysFromCivil (i32.const 1969) (i32.const 12) (i32.const 31)) (i32.const 149))))
          (i32.store8 (i32.add (i32.const 132) (i32.load (i32.const 4))) (i32.const 10))
          (i32.store (i32.const 4) (i32.add (i32.load (i32.const 4)) (i32.const 1)))
          (drop (call $fd_write
            (i32.const 1)
            (i32.const 0)
            (i32.const 1)
            (i32.const 128)))
    (call $check (if (result i32) (i32.eq (call $date_lib_modc_daysFromCivil (i32.const 1970) (i32.const 1) (i32.const 1)) (i32.const 0)) (then (i32.const 1)) (else (i32.const 0))))
    (call $check (if (result i32) (i32.eq (call $date_lib_modc_daysFromCivil (i32.const 2000) (i32.const 1) (i32.const 1)) (i32.const 10957)) (then (i32.const 1)) (else (i32.const 0))))
    (call $check (if (result i32) (i32.eq (call $date_lib_modc_daysFromCivil (i32.const 2024) (i32.const 2) (i32.const 29)) (i32.const 19782)) (then (i32.const 1)) (else (i32.const 0))))
    (call $check (if (result i32) (i32.eq (call $date_lib_modc_daysFromCivil (i32.const 1969) (i32.const 12) (i32.const 31)) (i32.const -1)) (then (i32.const 1)) (else (i32.const 0))))
        (i32.store (i32.const 0) (i32.const 132))
          (i32.store (i32.const 4) (i32.const 0))
          (i32.store8 (i32.const 132) (i32.const 119))
          (i32.store8 (i32.const 133) (i32.const 100))
          (i32.store8 (i32.const 134) (i32.const 97))
          (i32.store8 (i32.const 135) (i32.const 121))
          (i32.store8 (i32.const 136) (i32.const 32))
          (i32.store8 (i32.const 137) (i32.const 101))
          (i32.store8 (i32.const 138) (i32.const 112))
          (i32.store8 (i32.const 139) (i32.const 111))
          (i32.store8 (i32.const 140) (i32.const 99))
          (i32.store8 (i32.const 141) (i32.const 104))
          (i32.store8 (i32.const 142) (i32.const 58))
          (i32.store8 (i32.const 143) (i32.const 32))
          (i32.store (i32.const 4) (i32.add (i32.const 12) (call $__i32_to_str (call $date_lib_modc_weekdayFromDays (i32.const 0)) (i32.const 144))))
          (i32.store8 (i32.add (i32.const 132) (i32.load (i32.const 4))) (i32.const 10))
          (i32.store (i32.const 4) (i32.add (i32.load (i32.const 4)) (i32.const 1)))
          (drop (call $fd_write
            (i32.const 1)
            (i32.const 0)
            (i32.const 1)
            (i32.const 128)))
        (i32.store (i32.const 0) (i32.const 132))
          (i32.store (i32.const 4) (i32.const 0))
          (i32.store8 (i32.const 132) (i32.const 119))
          (i32.store8 (i32.const 133) (i32.const 100))
          (i32.store8 (i32.const 134) (i32.const 97))
          (i32.store8 (i32.const 135) (i32.const 121))
          (i32.store8 (i32.const 136) (i32.const 32))
          (i32.store8 (i32.const 137) (i32.const 50))
          (i32.store8 (i32.const 138) (i32.const 48))
          (i32.store8 (i32.const 139) (i32.const 48))
          (i32.store8 (i32.const 140) (i32.const 48))
          (i32.store8 (i32.const 141) (i32.const 45))
          (i32.store8 (i32.const 142) (i32.const 48))
          (i32.store8 (i32.const 143) (i32.const 49))
          (i32.store8 (i32.const 144) (i32.const 45))
          (i32.store8 (i32.const 145) (i32.const 48))
          (i32.store8 (i32.const 146) (i32.const 49))
          (i32.store8 (i32.const 147) (i32.const 58))
          (i32.store8 (i32.const 148) (i32.const 32))
          (i32.store (i32.const 4) (i32.add (i32.const 17) (call $__i32_to_str (call $date_lib_modc_weekdayFromDays (i32.const 10957)) (i32.const 149))))
          (i32.store8 (i32.add (i32.const 132) (i32.load (i32.const 4))) (i32.const 10))
          (i32.store (i32.const 4) (i32.add (i32.load (i32.const 4)) (i32.const 1)))
          (drop (call $fd_write
            (i32.const 1)
            (i32.const 0)
            (i32.const 1)
            (i32.const 128)))
        (i32.store (i32.const 0) (i32.const 132))
          (i32.store (i32.const 4) (i32.const 0))
          (i32.store8 (i32.const 132) (i32.const 119))
          (i32.store8 (i32.const 133) (i32.const 100))
          (i32.store8 (i32.const 134) (i32.const 97))
          (i32.store8 (i32.const 135) (i32.const 121))
          (i32.store8 (i32.const 136) (i32.const 32))
          (i32.store8 (i32.const 137) (i32.const 49))
          (i32.store8 (i32.const 138) (i32.const 57))
          (i32.store8 (i32.const 139) (i32.const 54))
          (i32.store8 (i32.const 140) (i32.const 57))
          (i32.store8 (i32.const 141) (i32.const 45))
          (i32.store8 (i32.const 142) (i32.const 49))
          (i32.store8 (i32.const 143) (i32.const 50))
          (i32.store8 (i32.const 144) (i32.const 45))
          (i32.store8 (i32.const 145) (i32.const 51))
          (i32.store8 (i32.const 146) (i32.const 49))
          (i32.store8 (i32.const 147) (i32.const 58))
          (i32.store8 (i32.const 148) (i32.const 32))
          (i32.store (i32.const 4) (i32.add (i32.const 17) (call $__i32_to_str (call $date_lib_modc_weekdayFromDays (i32.const -1)) (i32.const 149))))
          (i32.store8 (i32.add (i32.const 132) (i32.load (i32.const 4))) (i32.const 10))
          (i32.store (i32.const 4) (i32.add (i32.load (i32.const 4)) (i32.const 1)))
          (drop (call $fd_write
            (i32.const 1)
            (i32.const 0)
            (i32.const 1)
            (i32.const 128)))
    (call $check (if (result i32) (i32.eq (call $date_lib_modc_weekdayFromDays (i32.const 0)) (i32.const 4)) (then (i32.const 1)) (else (i32.const 0))))
    (call $check (if (result i32) (i32.eq (call $date_lib_modc_weekdayFromDays (i32.const 10957)) (i32.const 6)) (then (i32.const 1)) (else (i32.const 0))))
    (call $check (if (result i32) (i32.eq (call $date_lib_modc_weekdayFromDays (i32.const -1)) (i32.const 3)) (then (i32.const 1)) (else (i32.const 0))))
    (call $check (if (result i32) (i32.eq (call $date_lib_modc_yearFromDays (i32.const 10957)) (i32.const 2000)) (then (i32.const 1)) (else (i32.const 0))))
    (call $check (if (result i32) (i32.eq (call $date_lib_modc_monthFromDays (i32.const 10957)) (i32.const 1)) (then (i32.const 1)) (else (i32.const 0))))
    (call $check (if (result i32) (i32.eq (call $date_lib_modc_dayFromDays (i32.const 10957)) (i32.const 1)) (then (i32.const 1)) (else (i32.const 0))))
    (call $check (if (result i32) (i32.eq (call $date_lib_modc_yearFromDays (i32.const 19782)) (i32.const 2024)) (then (i32.const 1)) (else (i32.const 0))))
    (call $check (if (result i32) (i32.eq (call $date_lib_modc_monthFromDays (i32.const 19782)) (i32.const 2)) (then (i32.const 1)) (else (i32.const 0))))
    (call $check (if (result i32) (i32.eq (call $date_lib_modc_dayFromDays (i32.const 19782)) (i32.const 29)) (then (i32.const 1)) (else (i32.const 0))))
    (call $check (if (result i32) (i32.eq (call $date_lib_modc_yearFromDays (i32.const -1)) (i32.const 1969)) (then (i32.const 1)) (else (i32.const 0))))
    (call $check (if (result i32) (i32.eq (call $date_lib_modc_monthFromDays (i32.const -1)) (i32.const 12)) (then (i32.const 1)) (else (i32.const 0))))
    (call $check (if (result i32) (i32.eq (call $date_lib_modc_dayFromDays (i32.const -1)) (i32.const 31)) (then (i32.const 1)) (else (i32.const 0))))
        (i32.store (i32.const 0) (i32.const 132))
          (i32.store (i32.const 4) (i32.const 0))
          (i32.store8 (i32.const 132) (i32.const 121))
          (i32.store8 (i32.const 133) (i32.const 109))
          (i32.store8 (i32.const 134) (i32.const 100))
          (i32.store8 (i32.const 135) (i32.const 32))
          (i32.store8 (i32.const 136) (i32.const 49))
          (i32.store8 (i32.const 137) (i32.const 57))
          (i32.store8 (i32.const 138) (i32.const 55))
          (i32.store8 (i32.const 139) (i32.const 56))
          (i32.store8 (i32.const 140) (i32.const 50))
          (i32.store8 (i32.const 141) (i32.const 58))
          (i32.store8 (i32.const 142) (i32.const 32))
          (i32.store (i32.const 4) (i32.add (i32.const 11) (call $__i32_to_str (call $date_lib_modc_yearFromDays (i32.const 19782)) (i32.const 143))))
          (i32.store8 (i32.add (i32.const 132) (i32.add (i32.load (i32.const 4)) (i32.const 0))) (i32.const 32))
          (i32.store (i32.const 4) (i32.add (i32.load (i32.const 4)) (i32.const 1)))
          (i32.store (i32.const 4) (i32.add (i32.load (i32.const 4)) (call $__i32_to_str (call $date_lib_modc_monthFromDays (i32.const 19782)) (i32.add (i32.const 132) (i32.load (i32.const 4))))))
          (i32.store8 (i32.add (i32.const 132) (i32.add (i32.load (i32.const 4)) (i32.const 0))) (i32.const 32))
          (i32.store (i32.const 4) (i32.add (i32.load (i32.const 4)) (i32.const 1)))
          (i32.store (i32.const 4) (i32.add (i32.load (i32.const 4)) (call $__i32_to_str (call $date_lib_modc_dayFromDays (i32.const 19782)) (i32.add (i32.const 132) (i32.load (i32.const 4))))))
          (i32.store8 (i32.add (i32.const 132) (i32.load (i32.const 4))) (i32.const 10))
          (i32.store (i32.const 4) (i32.add (i32.load (i32.const 4)) (i32.const 1)))
          (drop (call $fd_write
            (i32.const 1)
            (i32.const 0)
            (i32.const 1)
            (i32.const 128)))
        (i32.store (i32.const 0) (i32.const 260))
          (i32.store (i32.const 4) (i32.const 8))
          (drop (call $fd_write
            (i32.const 1)
            (i32.const 0)
            (i32.const 1)
            (i32.const 128)))
    (call $proc_exit (i32.const 0))
  )
  (data (i32.const 260) "\64\61\74\65\20\6f\6b\0a")

  ;; functions from date_lib_modc
  (func $date_lib_modc_isLeapYear (param i32) (result i32)
    local.get 0
    i32.const 4
    i32.rem_s
    i32.const 0
    i32.ne
    if  ;; label = @1
      i32.const 0
      return
    end
    local.get 0
    i32.const 100
    i32.rem_s
    i32.const 0
    i32.ne
    if  ;; label = @1
      i32.const 1
      return
    end
    local.get 0
    i32.const 400
    i32.rem_s
    i32.eqz
    if (result i32)  ;; label = @1
      i32.const 1
    else
      i32.const 0
    end
    return)
  (func $date_lib_modc_daysInMonth (param i32 i32) (result i32)
    local.get 1
    i32.const 2
    i32.eq
    if  ;; label = @1
      local.get 0
      call $date_lib_modc_isLeapYear
      i32.const 1
      i32.eq
      if (result i32)  ;; label = @2
        i32.const 29
      else
        i32.const 28
      end
      return
    end
    local.get 1
    i32.const 4
    i32.eq
    local.get 1
    i32.const 6
    i32.eq
    i32.or
    local.get 1
    i32.const 9
    i32.eq
    i32.or
    local.get 1
    i32.const 11
    i32.eq
    i32.or
    if  ;; label = @1
      i32.const 30
      return
    end
    i32.const 31
    return)
  (func $date_lib_modc_daysFromCivil (param i32 i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 1
    i32.const 2
    i32.le_s
    if (result i32)  ;; label = @1
      local.get 0
      i32.const 1
      i32.sub
    else
      local.get 0
    end
    local.set 3
    local.get 3
    i32.const 0
    i32.ge_s
    if (result i32)  ;; label = @1
      local.get 3
    else
      local.get 3
      i32.const 399
      i32.sub
    end
    i32.const 400
    local.tee 6
    i32.div_s
    local.set 4
    local.get 3
    local.tee 7
    local.get 4
    local.tee 8
    local.get 6
    i32.mul
    i32.sub
    local.set 3
    local.get 1
    i32.const 2
    i32.gt_s
    if (result i32)  ;; label = @1
      local.get 1
      i32.const 3
      i32.sub
    else
      local.get 1
      i32.const 9
      i32.add
    end
    local.set 5
    i32.const 153
    local.get 5
    local.tee 9
    i32.mul
    i32.const 2
    i32.add
    i32.const 5
    i32.div_s
    local.get 2
    i32.const 1
    i32.sub
    i32.add
    local.set 5
    local.get 3
    local.tee 10
    i32.const 365
    i32.mul
    local.get 10
    i32.const 4
    i32.div_s
    local.get 10
    i32.const 100
    i32.div_s
    i32.sub
    i32.add
    local.get 5
    local.tee 11
    i32.add
    local.set 3
    local.get 8
    i32.const 146097
    i32.mul
    local.get 3
    local.tee 12
    i32.const 719468
    i32.sub
    i32.add
    return)
  (func $date_lib_modc_weekdayFromDays (param i32) (result i32)
    local.get 0
    i32.const -4
    i32.ge_s
    if (result i32)  ;; label = @1
      local.get 0
      i32.const 4
      i32.add
      i32.const 7
      i32.rem_s
    else
      local.get 0
      i32.const 5
      i32.add
      i32.const 7
      i32.rem_s
      i32.const 6
      i32.add
    end
    return)
  (func $date_lib_modc_yearFromDays (param i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    i32.const 719468
    i32.add
    local.set 1
    local.get 1
    i32.const 0
    i32.ge_s
    if (result i32)  ;; label = @1
      local.get 1
    else
      local.get 1
      i32.const 146096
      i32.sub
    end
    i32.const 146097
    local.tee 6
    i32.div_s
    local.set 2
    local.get 1
    local.tee 7
    local.get 2
    local.tee 8
    local.get 6
    i32.mul
    i32.sub
    local.set 1
    local.get 1
    local.tee 9
    i32.const 1460
    i32.div_s
    local.set 3
    local.get 9
    i32.const 36524
    i32.div_s
    local.set 4
    local.get 9
    i32.const 146096
    i32.div_s
    local.set 5
    local.get 9
    local.get 3
    local.tee 10
    i32.sub
    local.get 4
    local.get 5
    i32.sub
    i32.add
    i32.const 365
    local.tee 11
    i32.div_s
    local.set 3
    local.get 3
    local.tee 12
    local.get 2
    local.tee 13
    i32.const 400
    i32.mul
    i32.add
    local.set 2
    local.get 1
    local.tee 14
    local.get 11
    local.get 12
    i32.mul
    local.get 12
    i32.const 4
    i32.div_s
    local.get 12
    i32.const 100
    i32.div_s
    i32.sub
    i32.add
    i32.sub
    local.set 1
    i32.const 5
    local.get 1
    local.tee 15
    i32.mul
    i32.const 2
    i32.add
    i32.const 153
    i32.div_s
    local.set 1
    local.get 1
    i32.const 10
    i32.lt_s
    if (result i32)  ;; label = @1
      local.get 1
      i32.const 3
      i32.add
    else
      local.get 1
      i32.const 9
      i32.sub
    end
    local.set 1
    local.get 1
    i32.const 2
    i32.le_s
    if (result i32)  ;; label = @1
      local.get 2
      i32.const 1
      i32.add
    else
      local.get 2
    end
    return)
  (func $date_lib_modc_monthFromDays (param i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    i32.const 719468
    i32.add
    local.set 1
    local.get 1
    i32.const 0
    i32.ge_s
    if (result i32)  ;; label = @1
      local.get 1
    else
      local.get 1
      i32.const 146096
      i32.sub
    end
    i32.const 146097
    local.tee 5
    i32.div_s
    local.set 2
    local.get 1
    local.tee 6
    local.get 2
    local.tee 7
    local.get 5
    i32.mul
    i32.sub
    local.set 1
    local.get 1
    local.tee 8
    i32.const 1460
    i32.div_s
    local.set 2
    local.get 8
    i32.const 36524
    i32.div_s
    local.set 3
    local.get 8
    i32.const 146096
    i32.div_s
    local.set 4
    local.get 8
    local.get 2
    local.tee 9
    i32.sub
    local.get 3
    local.get 4
    i32.sub
    i32.add
    i32.const 365
    local.tee 10
    i32.div_s
    local.set 2
    local.get 1
    local.tee 11
    local.get 10
    local.get 2
    local.tee 12
    i32.mul
    local.get 12
    i32.const 4
    i32.div_s
    local.get 12
    i32.const 100
    i32.div_s
    i32.sub
    i32.add
    i32.sub
    local.set 1
    i32.const 5
    local.get 1
    local.tee 13
    i32.mul
    i32.const 2
    i32.add
    i32.const 153
    i32.div_s
    local.set 1
    local.get 1
    i32.const 10
    i32.lt_s
    if (result i32)  ;; label = @1
      local.get 1
      i32.const 3
      i32.add
    else
      local.get 1
      i32.const 9
      i32.sub
    end
    return)
  (func $date_lib_modc_dayFromDays (param i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    i32.const 719468
    i32.add
    local.set 1
    local.get 1
    i32.const 0
    i32.ge_s
    if (result i32)  ;; label = @1
      local.get 1
    else
      local.get 1
      i32.const 146096
      i32.sub
    end
    i32.const 146097
    local.tee 5
    i32.div_s
    local.set 2
    local.get 1
    local.tee 6
    local.get 2
    local.tee 7
    local.get 5
    i32.mul
    i32.sub
    local.set 1
    local.get 1
    local.tee 8
    i32.const 1460
    i32.div_s
    local.set 2
    local.get 8
    i32.const 36524
    i32.div_s
    local.set 3
    local.get 8
    i32.const 146096
    i32.div_s
    local.set 4
    local.get 8
    local.get 2
    local.tee 9
    i32.sub
    local.get 3
    local.get 4
    i32.sub
    i32.add
    i32.const 365
    local.tee 10
    i32.div_s
    local.set 2
    local.get 1
    local.tee 11
    local.get 10
    local.get 2
    local.tee 12
    i32.mul
    local.get 12
    i32.const 4
    i32.div_s
    local.get 12
    i32.const 100
    i32.div_s
    i32.sub
    i32.add
    i32.sub
    local.set 1
    i32.const 5
    local.tee 13
    local.get 1
    local.tee 14
    i32.mul
    i32.const 2
    local.tee 15
    i32.add
    i32.const 153
    local.tee 16
    i32.div_s
    local.set 2
    local.get 14
    local.get 16
    local.get 2
    local.tee 17
    i32.mul
    local.get 15
    i32.add
    local.get 13
    i32.div_s
    i32.sub
    i32.const 1
    i32.add
    return)
)