(module
  (import "wasi_snapshot_preview1" "proc_exit" (func $proc_exit (param i32)))
  (import "wasi_snapshot_preview1" "fd_write" (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (memory (export "memory") 2)
  (global $__heap_ptr (mut i32) (i32.const 260))
  (global $__free_list (mut i32) (i32.const 0))
  (global $allInRange (mut i32) (i32.const 1))
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
  (func $_start (export "_start")
    (local $r0 f64)
    (local $r1 f64)
    (local $r2 f64)
    (local $r3 f64)
    (local $r4 f64)
    (local $__iface_tmp i32)
    (local.set $r0 (call $mathlib_random))
    (if (if (result i32) (f64.lt (local.get $r0) (f64.const 0)) (then (i32.const 1)) (else (f64.ge (local.get $r0) (f64.const 1))))
      (then
      (global.set $allInRange (i32.const 0))
      )
    )
    (local.set $r1 (call $mathlib_random))
    (if (if (result i32) (f64.lt (local.get $r1) (f64.const 0)) (then (i32.const 1)) (else (f64.ge (local.get $r1) (f64.const 1))))
      (then
      (global.set $allInRange (i32.const 0))
      )
    )
    (local.set $r2 (call $mathlib_random))
    (if (if (result i32) (f64.lt (local.get $r2) (f64.const 0)) (then (i32.const 1)) (else (f64.ge (local.get $r2) (f64.const 1))))
      (then
      (global.set $allInRange (i32.const 0))
      )
    )
    (local.set $r3 (call $mathlib_random))
    (if (if (result i32) (f64.lt (local.get $r3) (f64.const 0)) (then (i32.const 1)) (else (f64.ge (local.get $r3) (f64.const 1))))
      (then
      (global.set $allInRange (i32.const 0))
      )
    )
    (local.set $r4 (call $mathlib_random))
    (if (if (result i32) (f64.lt (local.get $r4) (f64.const 0)) (then (i32.const 1)) (else (f64.ge (local.get $r4) (f64.const 1))))
      (then
      (global.set $allInRange (i32.const 0))
      )
    )
        (i32.store (i32.const 0) (i32.const 132))
          (i32.store (i32.const 4) (call $__i32_to_str (global.get $allInRange) (i32.const 132)))
          (i32.store8 (i32.add (i32.const 132) (i32.load (i32.const 4))) (i32.const 10))
          (i32.store (i32.const 4) (i32.add (i32.load (i32.const 4)) (i32.const 1)))
          (drop (call $fd_write
            (i32.const 1)
            (i32.const 0)
            (i32.const 1)
            (i32.const 128)))
    (call $proc_exit (i32.const 0))
  )

  ;; globals from mathlib
  (global $mathlib_global0 (mut i64) (i64.const 7809847782465536322))
  ;; functions from mathlib
  (func $mathlib_random (result f64)
    (local i64)
    global.get $mathlib_global0
    local.set 0
    local.get 0
    local.get 0
    i64.const 13
    i64.shl
    i64.xor
    local.set 0
    local.get 0
    local.get 0
    i64.const 7
    i64.shr_u
    i64.xor
    local.set 0
    local.get 0
    local.get 0
    i64.const 17
    i64.shl
    i64.xor
    local.set 0
    local.get 0
    global.set $mathlib_global0
    local.get 0
    i64.const 12
    i64.shr_u
    i64.const 4607182418800017408
    i64.or
    f64.reinterpret_i64
    f64.const 0x1.0p+0 (;=1;)
    f64.sub)
  (func $mathlib_sin (param f64) (result f64)
    (local f64) (local f64) (local f64)
    local.get 0
    f64.const 0x1.45f306dc9c883p-3 (;=0.15915494309189535;)
    f64.mul
    f64.const 0x1.0p-1 (;=0.5;)
    f64.add
    f64.floor
    local.set 3
    local.get 0
    local.get 3
    f64.const 0x1.921fb4p+2 (;=6.283185005187988;)
    f64.mul
    f64.sub
    local.get 3
    f64.const 0x1.4442d18p-22 (;=3.0199159795074593e-7;)
    f64.mul
    f64.sub
    local.get 3
    f64.const 0x1.1a62633145c07p-52 (;=2.4492935982947064e-16;)
    f64.mul
    f64.sub
    local.set 0
    local.get 0
    f64.const 0x1.921fb54442d18p+0 (;=1.5707963267948966;)
    f64.gt
    if  ;; label = @1
      f64.const 0x1.921fb54442d18p+1 (;=3.141592653589793;)
      local.get 0
      f64.sub
      local.set 0
    end
    local.get 0
    f64.const -0x1.921fb54442d18p+0 (;=-1.5707963267948966;)
    f64.lt
    if  ;; label = @1
      f64.const 0x1.921fb54442d18p+1 (;=3.141592653589793;)
      local.get 0
      f64.add
      f64.neg
      local.set 0
    end
    local.get 0
    local.get 0
    f64.mul
    local.set 1
    f64.const 0x1.5d8fd1fd19ccdp-33 (;=1.5896230157654656e-10;)
    local.set 2
    f64.const -0x1.ae6454baa2959p-26 (;=-2.5052106814843123e-8;)
    local.get 1
    local.get 2
    f64.mul
    f64.add
    local.set 2
    f64.const 0x1.71de357b1fe7dp-19 (;=0.0000027557313707070068;)
    local.get 1
    local.get 2
    f64.mul
    f64.add
    local.set 2
    f64.const -0x1.a01a019c161d5p-13 (;=-0.0001984126982985795;)
    local.get 1
    local.get 2
    f64.mul
    f64.add
    local.set 2
    f64.const 0x1.11111110a14d2p-7 (;=0.008333333332539192;)
    local.get 1
    local.get 2
    f64.mul
    f64.add
    local.set 2
    f64.const -0x1.5555555555549p-3 (;=-0.16666666666666632;)
    local.get 1
    local.get 2
    f64.mul
    f64.add
    local.set 2
    f64.const 0x1.0p+0 (;=1;)
    local.get 1
    local.get 2
    f64.mul
    f64.add
    local.set 2
    local.get 0
    local.get 2
    f64.mul)
  (func $mathlib_cos (param f64) (result f64)
    (local f64) (local f64) (local i32) (local f64)
    i32.const 1
    local.set 3
    local.get 0
    f64.const 0x1.45f306dc9c883p-3 (;=0.15915494309189535;)
    f64.mul
    f64.const 0x1.0p-1 (;=0.5;)
    f64.add
    f64.floor
    local.set 4
    local.get 0
    local.get 4
    f64.const 0x1.921fb4p+2 (;=6.283185005187988;)
    f64.mul
    f64.sub
    local.get 4
    f64.const 0x1.4442d18p-22 (;=3.0199159795074593e-7;)
    f64.mul
    f64.sub
    local.get 4
    f64.const 0x1.1a62633145c07p-52 (;=2.4492935982947064e-16;)
    f64.mul
    f64.sub
    local.set 0
    local.get 0
    f64.const 0x1.921fb54442d18p+0 (;=1.5707963267948966;)
    f64.gt
    if  ;; label = @1
      f64.const 0x1.921fb54442d18p+1 (;=3.141592653589793;)
      local.get 0
      f64.sub
      local.set 0
      i32.const -1
      local.set 3
    end
    local.get 0
    f64.const -0x1.921fb54442d18p+0 (;=-1.5707963267948966;)
    f64.lt
    if  ;; label = @1
      f64.const 0x1.921fb54442d18p+1 (;=3.141592653589793;)
      local.get 0
      f64.add
      f64.neg
      local.set 0
      i32.const -1
      local.set 3
    end
    local.get 0
    local.get 0
    f64.mul
    local.set 1
    f64.const 0x1.1eed8eff8d898p-29 (;=2.08767569878681e-9;)
    local.set 2
    f64.const -0x1.27e4fb7789f5cp-22 (;=-2.755731922398589e-7;)
    local.get 1
    local.get 2
    f64.mul
    f64.add
    local.set 2
    f64.const 0x1.a01a01a01a01ap-16 (;=0.0000248015873015873;)
    local.get 1
    local.get 2
    f64.mul
    f64.add
    local.set 2
    f64.const -0x1.6c16c16c16c16p-10 (;=-0.0013888888888888887;)
    local.get 1
    local.get 2
    f64.mul
    f64.add
    local.set 2
    f64.const 0x1.5555555555556p-5 (;=0.04166666666666667;)
    local.get 1
    local.get 2
    f64.mul
    f64.add
    local.set 2
    f64.const -0x1.fffffffffffffp-2 (;=-0.49999999999999994;)
    local.get 1
    local.get 2
    f64.mul
    f64.add
    local.set 2
    f64.const 0x1.0p+0 (;=1;)
    local.get 1
    local.get 2
    f64.mul
    f64.add
    local.set 2
    local.get 3
    i32.const -1
    i32.eq
    if  ;; label = @1
      local.get 2
      f64.neg
      local.set 2
    end
    local.get 2)
  (func $mathlib_tan (param f64) (result f64)
    local.get 0
    call $mathlib_sin
    local.get 0
    call $mathlib_cos
    f64.div)
  (func $mathlib_atan (param f64) (result f64)
    (local i32) (local f64) (local f64) (local f64) (local f64) (local i32) (local i32)
    i32.const 1
    local.set 1
    local.get 0
    local.set 2
    i32.const 0
    local.set 6
    i32.const 0
    local.set 7
    local.get 0
    f64.const 0x0p+0 (;=0;)
    f64.lt
    if  ;; label = @1
      i32.const -1
      local.set 1
      local.get 0
      f64.neg
      local.set 2
    end
    local.get 2
    f64.const 0x1.0p+0 (;=1;)
    f64.gt
    if  ;; label = @1
      f64.const 0x1.0p+0 (;=1;)
      local.get 2
      f64.div
      local.set 2
      i32.const 1
      local.set 6
    end
    local.get 2
    f64.const 0x1.a827999fcef33p-2 (;=0.4142135623730951;)
    f64.gt
    if  ;; label = @1
      local.get 2
      f64.const 0x1.0p+0 (;=1;)
      f64.sub
      local.get 2
      f64.const 0x1.0p+0 (;=1;)
      f64.add
      f64.div
      local.set 2
      i32.const 1
      local.set 7
    end
    local.get 2
    local.get 2
    f64.mul
    local.set 3
    f64.const 0x1.0ad3ae322da11p-6 (;=0.016285820115365782;)
    local.set 5
    f64.const -0x1.2b4442c6a6c2fp-5 (;=-0.036531572744216916;)
    local.get 3
    local.get 5
    f64.mul
    f64.add
    local.set 5
    f64.const 0x1.97b492df83c18p-5 (;=0.049768721448451625;)
    local.get 3
    local.get 5
    f64.mul
    f64.add
    local.set 5
    f64.const -0x1.dde2d52df3df4p-5 (;=-0.058335701338020046;)
    local.get 3
    local.get 5
    f64.mul
    f64.add
    local.set 5
    f64.const 0x1.10d66a0d03d54p-4 (;=0.06661073137387535;)
    local.get 3
    local.get 5
    f64.mul
    f64.add
    local.set 5
    f64.const -0x1.3b0f2af749a6dp-4 (;=-0.0769187620504483;)
    local.get 3
    local.get 5
    f64.mul
    f64.add
    local.set 5
    f64.const 0x1.745cdc54c206ep-4 (;=0.09090887133436507;)
    local.get 3
    local.get 5
    f64.mul
    f64.add
    local.set 5
    f64.const -0x1.c71c6fe231671p-4 (;=-0.11111110405462356;)
    local.get 3
    local.get 5
    f64.mul
    f64.add
    local.set 5
    f64.const 0x1.24924920083ffp-3 (;=0.14285714272503466;)
    local.get 3
    local.get 5
    f64.mul
    f64.add
    local.set 5
    f64.const -0x1.999999998ebc4p-3 (;=-0.19999999999876483;)
    local.get 3
    local.get 5
    f64.mul
    f64.add
    local.set 5
    f64.const 0x1.555555555550dp-2 (;=0.3333333333333293;)
    local.get 3
    local.get 5
    f64.mul
    f64.add
    local.set 5
    local.get 2
    local.get 2
    local.get 3
    f64.mul
    local.get 5
    f64.mul
    f64.sub
    local.set 4
    local.get 6
    local.get 7
    i32.and
    if  ;; label = @1
      f64.const 0x1.921fb54442d18p-1 (;=0.7853981633974483;)
      local.get 4
      f64.sub
      local.set 4
    else
      local.get 6
      if  ;; label = @2
        f64.const 0x1.921fb54442d18p+0 (;=1.5707963267948966;)
        local.get 4
        f64.sub
        local.set 4
      else
        local.get 7
        if  ;; label = @3
          f64.const 0x1.921fb54442d18p-1 (;=0.7853981633974483;)
          local.get 4
          f64.add
          local.set 4
        end
      end
    end
    local.get 1
    i32.const -1
    i32.eq
    if  ;; label = @1
      local.get 4
      f64.neg
      local.set 4
    end
    local.get 4)
  (func $mathlib_atan2 (param f64 f64) (result f64)
    (local f64)
    local.get 1
    f64.const 0x0p+0 (;=0;)
    f64.eq
    if  ;; label = @1
      local.get 0
      f64.const 0x0p+0 (;=0;)
      f64.gt
      if  ;; label = @2
        f64.const 0x1.921fb54442d18p+0 (;=1.5707963267948966;)
        return
      end
      local.get 0
      f64.const 0x0p+0 (;=0;)
      f64.lt
      if  ;; label = @2
        f64.const -0x1.921fb54442d18p+0 (;=-1.5707963267948966;)
        return
      end
      f64.const 0x0p+0 (;=0;)
      return
    end
    local.get 0
    local.get 1
    f64.div
    call $mathlib_atan
    local.set 2
    local.get 1
    f64.const 0x0p+0 (;=0;)
    f64.lt
    if  ;; label = @1
      local.get 0
      f64.const 0x0p+0 (;=0;)
      f64.ge
      if  ;; label = @2
        local.get 2
        f64.const 0x1.921fb54442d18p+1 (;=3.141592653589793;)
        f64.add
        local.set 2
      else
        local.get 2
        f64.const 0x1.921fb54442d18p+1 (;=3.141592653589793;)
        f64.sub
        local.set 2
      end
    end
    local.get 2)
  (func $mathlib_asin (param f64) (result f64)
    (local i32) (local f64) (local f64)
    i32.const 0
    local.set 1
    local.get 0
    local.set 2
    local.get 0
    f64.const 0x0p+0 (;=0;)
    f64.lt
    if  ;; label = @1
      i32.const 1
      local.set 1
      local.get 0
      f64.neg
      local.set 2
    end
    local.get 2
    f64.const 0x1.6666666666666p-1 (;=0.7;)
    f64.le
    if  ;; label = @1
      local.get 2
      f64.const 0x1.0p+0 (;=1;)
      local.get 2
      local.get 2
      f64.mul
      f64.sub
      f64.sqrt
      f64.div
      call $mathlib_atan
      local.set 3
    else
      f64.const 0x1.921fb54442d18p+0 (;=1.5707963267948966;)
      f64.const 0x1.0p+1 (;=2;)
      f64.const 0x1.0p-1 (;=0.5;)
      f64.const 0x1.0p+0 (;=1;)
      local.get 2
      f64.sub
      f64.mul
      f64.sqrt
      call $mathlib_asin
      f64.mul
      f64.sub
      local.set 3
    end
    local.get 1
    i32.const 1
    i32.eq
    if  ;; label = @1
      local.get 3
      f64.neg
      local.set 3
    end
    local.get 3)
  (func $mathlib_acos (param f64) (result f64)
    f64.const 0x1.921fb54442d18p+0 (;=1.5707963267948966;)
    local.get 0
    call $mathlib_asin
    f64.sub)
  (func $mathlib_exp (param f64) (result f64)
    (local i64) (local f64) (local f64)
    local.get 0
    f64.const 0x1.62e42fefa39efp+9 (;=709.782712893384;)
    f64.gt
    if  ;; label = @1
      f64.const 0x1.fffffffffffffp+1023 (;=1.7976931348623157e+308;)
      f64.const 0x1.fffffffffffffp+1023 (;=1.7976931348623157e+308;)
      f64.mul
      return
    end
    local.get 0
    f64.const -0x1.6232bdd7abcd2p+9 (;=-708.3964185322641;)
    f64.lt
    if  ;; label = @1
      f64.const 0x0p+0 (;=0;)
      return
    end
    local.get 0
    f64.const 0x1.71547652b82fep+0 (;=1.4426950408889634;)
    f64.mul
    f64.nearest
    i64.trunc_f64_s
    local.set 1
    local.get 0
    local.get 1
    f64.convert_i64_s
    f64.const 0x1.62e42fefa39efp-1 (;=0.6931471805599453;)
    f64.mul
    f64.sub
    local.get 1
    f64.convert_i64_s
    f64.const 0x1.a39ef35793c76p-33 (;=1.9082149292705877e-10;)
    f64.mul
    f64.sub
    local.set 2
    f64.const 0x1.27e4fb7789f5cp-22 (;=2.755731922398589e-7;)
    local.set 3
    f64.const 0x1.71de3a556c733p-19 (;=0.000002755731922398589;)
    local.get 2
    local.get 3
    f64.mul
    f64.add
    local.set 3
    f64.const 0x1.a01a01a01a01ap-16 (;=0.0000248015873015873;)
    local.get 2
    local.get 3
    f64.mul
    f64.add
    local.set 3
    f64.const 0x1.a01a01a01a01ap-13 (;=0.0001984126984126984;)
    local.get 2
    local.get 3
    f64.mul
    f64.add
    local.set 3
    f64.const 0x1.6c16c16c16c17p-10 (;=0.001388888888888889;)
    local.get 2
    local.get 3
    f64.mul
    f64.add
    local.set 3
    f64.const 0x1.1111111111111p-7 (;=0.008333333333333333;)
    local.get 2
    local.get 3
    f64.mul
    f64.add
    local.set 3
    f64.const 0x1.5555555555555p-5 (;=0.041666666666666664;)
    local.get 2
    local.get 3
    f64.mul
    f64.add
    local.set 3
    f64.const 0x1.5555555555555p-3 (;=0.16666666666666666;)
    local.get 2
    local.get 3
    f64.mul
    f64.add
    local.set 3
    f64.const 0x1.0p-1 (;=0.5;)
    local.get 2
    local.get 3
    f64.mul
    f64.add
    local.set 3
    f64.const 0x1.0p+0 (;=1;)
    local.get 2
    local.get 3
    f64.mul
    f64.add
    local.set 3
    f64.const 0x1.0p+0 (;=1;)
    local.get 2
    local.get 3
    f64.mul
    f64.add
    local.set 3
    local.get 3
    local.get 1
    i64.const 1023
    i64.add
    i64.const 52
    i64.shl
    f64.reinterpret_i64
    f64.mul)
  (func $mathlib_log (param f64) (result f64)
    (local i64) (local i64) (local f64) (local f64) (local f64) (local f64)
    local.get 0
    f64.const 0x0p+0 (;=0;)
    f64.le
    if  ;; label = @1
      local.get 0
      f64.const 0x0p+0 (;=0;)
      f64.eq
      if (result f64)  ;; label = @2
        f64.const -0x1.0p+0 (;=-1;)
        f64.const 0x0p+0 (;=0;)
        f64.div
      else
        f64.const 0x0p+0 (;=0;)
        f64.const 0x0p+0 (;=0;)
        f64.div
      end
      return
    end
    local.get 0
    f64.const 0x1.fffffffffffffp+1023 (;=1.7976931348623157e+308;)
    f64.gt
    if  ;; label = @1
      local.get 0
      return
    end
    local.get 0
    i64.reinterpret_f64
    local.set 1
    local.get 1
    i64.const 9218868437227405312
    i64.and
    i64.const 52
    i64.shr_u
    i64.const 1023
    i64.sub
    local.set 2
    local.get 1
    i64.const 4503599627370495
    i64.and
    i64.const 4607182418800017408
    i64.or
    f64.reinterpret_i64
    local.set 3
    local.get 3
    f64.const 0x1.6a09e667f3bcdp+0 (;=1.4142135623730951;)
    f64.gt
    if  ;; label = @1
      local.get 3
      f64.const 0x1.0p-1 (;=0.5;)
      f64.mul
      local.set 3
      local.get 2
      i64.const 1
      i64.add
      local.set 2
    end
    local.get 3
    f64.const 0x1.0p+0 (;=1;)
    f64.sub
    local.get 3
    f64.const 0x1.0p+0 (;=1;)
    f64.add
    f64.div
    local.set 4
    local.get 4
    local.get 4
    f64.mul
    local.set 5
    f64.const 0x1.1111111111111p-4 (;=0.06666666666666667;)
    local.set 6
    f64.const 0x1.3b13b13b13b13p-4 (;=0.07692307692307691;)
    local.get 5
    local.get 6
    f64.mul
    f64.add
    local.set 6
    f64.const 0x1.745d1745d1746p-4 (;=0.09090909090909091;)
    local.get 5
    local.get 6
    f64.mul
    f64.add
    local.set 6
    f64.const 0x1.c71c71c71c71cp-4 (;=0.1111111111111111;)
    local.get 5
    local.get 6
    f64.mul
    f64.add
    local.set 6
    f64.const 0x1.2492492492492p-3 (;=0.14285714285714285;)
    local.get 5
    local.get 6
    f64.mul
    f64.add
    local.set 6
    f64.const 0x1.999999999999ap-3 (;=0.2;)
    local.get 5
    local.get 6
    f64.mul
    f64.add
    local.set 6
    f64.const 0x1.5555555555555p-2 (;=0.3333333333333333;)
    local.get 5
    local.get 6
    f64.mul
    f64.add
    local.set 6
    f64.const 0x1.0p+0 (;=1;)
    local.get 5
    local.get 6
    f64.mul
    f64.add
    local.set 6
    local.get 2
    f64.convert_i64_s
    f64.const 0x1.62e42fefa39efp-1 (;=0.6931471805599453;)
    f64.mul
    f64.const 0x1.0p+1 (;=2;)
    local.get 4
    local.get 6
    f64.mul
    f64.mul
    f64.add)
  (func $mathlib_log2 (param f64) (result f64)
    local.get 0
    call $mathlib_log
    f64.const 0x1.71547652b82fep+0 (;=1.4426950408889634;)
    f64.mul)
  (func $mathlib_log10 (param f64) (result f64)
    local.get 0
    call $mathlib_log
    f64.const 0x1.bcb7b1526e50ep-2 (;=0.4342944819032518;)
    f64.mul)
  (func $mathlib_cbrt (param f64) (result f64)
    (local i32) (local f64)
    i32.const 0
    local.set 1
    local.get 0
    f64.const 0x0p+0 (;=0;)
    f64.eq
    if  ;; label = @1
      f64.const 0x0p+0 (;=0;)
      return
    end
    local.get 0
    f64.const 0x1.fffffffffffffp+1023 (;=1.7976931348623157e+308;)
    f64.gt
    if  ;; label = @1
      local.get 0
      return
    end
    local.get 0
    f64.const 0x0p+0 (;=0;)
    f64.lt
    if  ;; label = @1
      i32.const 1
      local.set 1
      local.get 0
      f64.neg
      local.set 0
    end
    local.get 0
    call $mathlib_log
    f64.const 0x1.8p+1 (;=3;)
    f64.div
    call $mathlib_exp
    local.set 2
    f64.const 0x1.0p+1 (;=2;)
    local.get 2
    f64.mul
    local.get 0
    local.get 2
    local.get 2
    f64.mul
    f64.div
    f64.add
    f64.const 0x1.8p+1 (;=3;)
    f64.div
    local.set 2
    f64.const 0x1.0p+1 (;=2;)
    local.get 2
    f64.mul
    local.get 0
    local.get 2
    local.get 2
    f64.mul
    f64.div
    f64.add
    f64.const 0x1.8p+1 (;=3;)
    f64.div
    local.set 2
    f64.const 0x1.0p+1 (;=2;)
    local.get 2
    f64.mul
    local.get 0
    local.get 2
    local.get 2
    f64.mul
    f64.div
    f64.add
    f64.const 0x1.8p+1 (;=3;)
    f64.div
    local.set 2
    local.get 1
    i32.const 1
    i32.eq
    if  ;; label = @1
      local.get 2
      f64.neg
      local.set 2
    end
    local.get 2)
  (func $mathlib_sinh (param f64) (result f64)
    (local f64)
    local.get 0
    call $mathlib_exp
    local.set 1
    f64.const 0x1.0p-1 (;=0.5;)
    local.get 1
    f64.const 0x1.0p+0 (;=1;)
    local.get 1
    f64.div
    f64.sub
    f64.mul)
  (func $mathlib_cosh (param f64) (result f64)
    (local f64)
    local.get 0
    call $mathlib_exp
    local.set 1
    f64.const 0x1.0p-1 (;=0.5;)
    local.get 1
    f64.const 0x1.0p+0 (;=1;)
    local.get 1
    f64.div
    f64.add
    f64.mul)
  (func $mathlib_tanh (param f64) (result f64)
    (local f64)
    f64.const 0x1.0p+1 (;=2;)
    local.get 0
    f64.mul
    call $mathlib_exp
    local.set 1
    local.get 1
    f64.const 0x1.0p+0 (;=1;)
    f64.sub
    local.get 1
    f64.const 0x1.0p+0 (;=1;)
    f64.add
    f64.div)
  (func $mathlib_asinh (param f64) (result f64)
    local.get 0
    local.get 0
    local.get 0
    f64.mul
    f64.const 0x1.0p+0 (;=1;)
    f64.add
    f64.sqrt
    f64.add
    call $mathlib_log)
  (func $mathlib_acosh (param f64) (result f64)
    local.get 0
    local.get 0
    local.get 0
    f64.mul
    f64.const 0x1.0p+0 (;=1;)
    f64.sub
    f64.sqrt
    f64.add
    call $mathlib_log)
  (func $mathlib_atanh (param f64) (result f64)
    f64.const 0x1.0p-1 (;=0.5;)
    f64.const 0x1.0p+0 (;=1;)
    local.get 0
    f64.add
    call $mathlib_log
    f64.const 0x1.0p+0 (;=1;)
    local.get 0
    f64.sub
    call $mathlib_log
    f64.sub
    f64.mul)
  (func $mathlib_expm1 (param f64) (result f64)
    (local f64) (local f64)
    local.get 0
    f64.abs
    local.set 1
    local.get 1
    f64.const 0x1.0p-52 (;=2.220446049250313e-16;)
    f64.lt
    if  ;; label = @1
      local.get 0
      return
    end
    local.get 1
    f64.const 0x1.0p+0 (;=1;)
    f64.ge
    if  ;; label = @1
      local.get 0
      call $mathlib_exp
      f64.const 0x1.0p+0 (;=1;)
      f64.sub
      return
    end
    f64.const 0x1.a01a01a01a01ap-13 (;=0.0001984126984126984;)
    local.set 2
    f64.const 0x1.6c16c16c16c17p-10 (;=0.001388888888888889;)
    local.get 0
    local.get 2
    f64.mul
    f64.add
    local.set 2
    f64.const 0x1.1111111111111p-7 (;=0.008333333333333333;)
    local.get 0
    local.get 2
    f64.mul
    f64.add
    local.set 2
    f64.const 0x1.5555555555555p-5 (;=0.041666666666666664;)
    local.get 0
    local.get 2
    f64.mul
    f64.add
    local.set 2
    f64.const 0x1.5555555555555p-3 (;=0.16666666666666666;)
    local.get 0
    local.get 2
    f64.mul
    f64.add
    local.set 2
    f64.const 0x1.0p-1 (;=0.5;)
    local.get 0
    local.get 2
    f64.mul
    f64.add
    local.set 2
    f64.const 0x1.0p+0 (;=1;)
    local.get 0
    local.get 2
    f64.mul
    f64.add
    local.set 2
    local.get 0
    local.get 2
    f64.mul)
  (func $mathlib_log1p (param f64) (result f64)
    local.get 0
    f64.abs
    f64.const 0x1.0p-52 (;=2.220446049250313e-16;)
    f64.lt
    if  ;; label = @1
      local.get 0
      return
    end
    f64.const 0x1.0p+0 (;=1;)
    local.get 0
    f64.add
    call $mathlib_log)
)