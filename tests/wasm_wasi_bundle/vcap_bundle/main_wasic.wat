(module
  (import "wasi_snapshot_preview1" "proc_exit" (func $proc_exit (param i32)))
  (import "wasi_snapshot_preview1" "fd_write" (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (memory (export "memory") 3)
  (global $__heap_ptr (mut i32) (i32.const 1618))
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
    (local $s i32)
    (local $m i32)
    (local $obj i32)
    (local $n i32)
    (local $__iface_tmp i32)
    (global.set $guard (call $__malloc (i32.const 40)))
      (i32.store (global.get $guard) (i32.const 1))
      (i32.store offset=4 (global.get $guard) (i32.const 8))
      (i32.store offset=8 (global.get $guard) (i32.const 0))
    (local.set $s (call $set_setNew ))
    (call $set_setAdd (local.get $s) (i32.const 10))
    (call $set_setAdd (local.get $s) (i32.const 20))
    (call $set_setAdd (local.get $s) (i32.const 10))
    (call $check (if (result i32) (i32.eq (call $set_setSize (local.get $s)) (i32.const 2)) (then (i32.const 1)) (else (i32.const 0))))
    (call $check (call $set_setHas (local.get $s) (i32.const 10)))
    (call $check (if (result i32) (i32.eq (call $set_setHas (local.get $s) (i32.const 99)) (i32.const 0)) (then (i32.const 1)) (else (i32.const 0))))
    (local.set $m (call $map_mapNew ))
    (call $map_mapSet (local.get $m) (i32.const 1) (i32.const 100))
    (call $map_mapSet (local.get $m) (i32.const 2) (i32.const 200))
    (call $check (if (result i32) (i32.eq (call $map_mapGet (local.get $m) (i32.const 1) (i32.const -1)) (i32.const 100)) (then (i32.const 1)) (else (i32.const 0))))
    (call $check (if (result i32) (i32.eq (call $map_mapGet (local.get $m) (i32.const 9) (i32.const -1)) (i32.const -1)) (then (i32.const 1)) (else (i32.const 0))))
    (call $check (call $map_mapHas (local.get $m) (i32.const 2)))
    (call $check (call $date_isLeapYear (i32.const 2024)))
    (call $check (if (result i32) (i32.eq (call $date_isLeapYear (i32.const 2023)) (i32.const 0)) (then (i32.const 1)) (else (i32.const 0))))
    (call $check (if (result i32) (i32.eq (call $date_daysInMonth (i32.const 2024) (i32.const 2)) (i32.const 29)) (then (i32.const 1)) (else (i32.const 0))))
    (local.set $obj (call $json_jsonParse (i32.const 260) (i32.const 11)))
    (call $check (if (result i32) (i32.eq (call $json_jsonType (local.get $obj)) (i32.const 5)) (then (i32.const 1)) (else (i32.const 0))))
    (local.set $n (call $json_jsonGet (local.get $obj) (i32.const 271) (i32.const 1)))
    (call $check (if (result i32) (i32.eq (call $json_jsonInt (local.get $n)) (i32.const 42)) (then (i32.const 1)) (else (i32.const 0))))
    (call $check (call $regex_reTest (i32.const 272) (i32.const 3) (i32.const 275) (i32.const 3)))
    (call $check (if (result i32) (i32.eq (call $regex_reTest (i32.const 272) (i32.const 3) (i32.const 278) (i32.const 3)) (i32.const 0)) (then (i32.const 1)) (else (i32.const 0))))
        (i32.store (i32.const 0) (i32.const 281))
          (i32.store (i32.const 4) (i32.const 37))
          (drop (call $fd_write
            (i32.const 1)
            (i32.const 0)
            (i32.const 1)
            (i32.const 128)))
    (call $proc_exit (i32.const 0))
  )
  (data (i32.const 260) "\7b\20\22\6e\22\3a\20\34\32\20\7d")
  (data (i32.const 271) "\6e")
  (data (i32.const 272) "\61\2e\63")
  (data (i32.const 275) "\61\62\63")
  (data (i32.const 278) "\61\78\64")
  (data (i32.const 281) "\61\6c\6c\20\76\69\72\74\75\61\6c\2d\63\61\70\61\62\69\6c\69\74\79\20\63\68\65\63\6b\73\20\70\61\73\73\65\64\0a")

  ;; globals from set
  (global $set_global1 i32 (i32.const 8))
  ;; functions from set
  (func $set__fn1 (param i32) (result i32)
    (local i32) (local i32)
    i32.const 8
    local.get 0
    i32.const 2
    i32.shl
    i32.add
    call $__malloc
    local.set 1
    local.get 1
    local.get 0
    i32.store
    local.get 1
    local.tee 2
    return)
  (func $set_setNew (result i32)
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
    i32.const 8
    i32.add
    i32.const 4
    i32.add
    global.get $set_global1
    i32.store
    local.get 0
    i32.const 8
    i32.add
    i32.const 8
    i32.add
    global.get $set_global1
    call $set__fn1
    i32.store
    local.get 0
    i32.const 8
    i32.add
    i32.const 12
    i32.add
    global.get $set_global1
    call $set__fn1
    i32.store
    local.get 0
    local.tee 1
    return)
  (func $set__fn3 (param i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
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
    i32.const 8
    i32.add
    i32.load
    local.set 3
    local.get 1
    i32.const 8
    i32.add
    i32.const 12
    i32.add
    i32.load
    local.set 4
    local.get 2
    i32.const 2
    i32.mul
    local.set 5
    local.get 5
    call $set__fn1
    local.set 6
    local.get 5
    call $set__fn1
    local.set 7
    local.get 6
    local.tee 15
    local.set 8
    local.get 7
    local.tee 16
    local.set 9
    local.get 5
    local.tee 17
    i32.const 1
    i32.sub
    local.set 10
    i32.const 0
    local.set 11
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 11
          local.get 2
          i32.lt_s
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 4
            i32.const 8
            i32.add
            local.get 11
            i32.const 2
            i32.shl
            i32.add
            i32.load
            i32.const 0
            i32.ne
            if  ;; label = @5
              block  ;; label = @6
                local.get 3
                i32.const 8
                i32.add
                local.get 11
                i32.const 2
                i32.shl
                i32.add
                i32.load
                local.set 12
                local.get 12
                local.tee 14
                local.get 10
                i32.and
                local.set 13
                block  ;; label = @7
                  loop  ;; label = @8
                    block  ;; label = @9
                      local.get 9
                      i32.const 8
                      i32.add
                      local.get 13
                      i32.const 2
                      i32.shl
                      i32.add
                      i32.load
                      i32.const 0
                      i32.ne
                      i32.eqz
                      br_if 2 (;@7;)
                      local.get 13
                      i32.const 1
                      i32.add
                      local.get 10
                      i32.and
                      local.set 13
                      br 1 (;@8;)
                    end
                  end
                end
                local.get 8
                i32.const 8
                i32.add
                local.get 13
                i32.const 2
                i32.shl
                i32.add
                local.get 12
                i32.store
                local.get 9
                i32.const 8
                i32.add
                local.get 13
                i32.const 2
                i32.shl
                i32.add
                i32.const 1
                i32.store
              end
            end
            local.get 11
            i32.const 1
            i32.add
            local.set 11
          end
          br 1 (;@2;)
        end
      end
    end
    local.get 1
    i32.const 8
    i32.add
    i32.const 4
    i32.add
    local.get 5
    i32.store
    local.get 1
    i32.const 8
    i32.add
    i32.const 8
    i32.add
    local.get 6
    i32.store
    local.get 1
    i32.const 8
    i32.add
    i32.const 12
    i32.add
    local.get 7
    i32.store)
  (func $set_setAdd (param i32 i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.tee 7
    local.set 2
    local.get 2
    i32.const 8
    i32.add
    i32.load
    i32.const 1
    i32.add
    i32.const 2
    i32.mul
    local.get 2
    i32.const 8
    i32.add
    i32.const 4
    i32.add
    i32.load
    i32.gt_s
    if  ;; label = @1
      local.get 0
      call $set__fn3
    end
    local.get 0
    local.tee 8
    local.set 2
    local.get 2
    i32.const 8
    i32.add
    i32.const 4
    i32.add
    i32.load
    local.set 3
    local.get 2
    i32.const 8
    i32.add
    i32.const 8
    i32.add
    i32.load
    local.set 4
    local.get 2
    i32.const 8
    i32.add
    i32.const 12
    i32.add
    i32.load
    local.set 5
    local.get 3
    local.tee 9
    i32.const 1
    local.tee 10
    i32.sub
    local.set 3
    local.get 1
    local.tee 11
    local.get 3
    local.tee 12
    i32.and
    local.set 6
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 5
          i32.const 8
          i32.add
          local.get 6
          i32.const 2
          i32.shl
          i32.add
          i32.load
          i32.const 0
          i32.ne
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 4
            i32.const 8
            i32.add
            local.get 6
            i32.const 2
            i32.shl
            i32.add
            i32.load
            local.get 1
            i32.eq
            if  ;; label = @5
              return
            end
            local.get 6
            i32.const 1
            i32.add
            local.get 3
            i32.and
            local.set 6
          end
          br 1 (;@2;)
        end
      end
    end
    local.get 4
    i32.const 8
    i32.add
    local.get 6
    i32.const 2
    i32.shl
    i32.add
    local.get 1
    i32.store
    local.get 5
    i32.const 8
    i32.add
    local.get 6
    i32.const 2
    i32.shl
    i32.add
    i32.const 1
    i32.store
    local.get 2
    i32.const 8
    i32.add
    local.get 2
    i32.const 8
    i32.add
    i32.load
    i32.const 1
    i32.add
    i32.store)
  (func $set_setHas (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.set 2
    local.get 2
    i32.const 8
    i32.add
    i32.const 4
    i32.add
    i32.load
    local.set 3
    local.get 2
    i32.const 8
    i32.add
    i32.const 8
    i32.add
    i32.load
    local.set 4
    local.get 2
    i32.const 8
    i32.add
    i32.const 12
    i32.add
    i32.load
    local.set 2
    local.get 3
    local.tee 6
    i32.const 1
    i32.sub
    local.set 3
    local.get 1
    local.get 3
    local.tee 7
    i32.and
    local.set 5
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 2
          i32.const 8
          i32.add
          local.get 5
          i32.const 2
          i32.shl
          i32.add
          i32.load
          i32.const 0
          i32.ne
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 4
            i32.const 8
            i32.add
            local.get 5
            i32.const 2
            i32.shl
            i32.add
            i32.load
            local.get 1
            i32.eq
            if  ;; label = @5
              i32.const 1
              return
            end
            local.get 5
            i32.const 1
            i32.add
            local.get 3
            i32.and
            local.set 5
          end
          br 1 (;@2;)
        end
      end
    end
    i32.const 0
    return)
  (func $set_setSize (param i32) (result i32)
    (local i32)
    local.get 0
    local.set 1
    local.get 1
    i32.const 8
    i32.add
    i32.load
    return)

  ;; globals from map
  (global $map_global1 i32 (i32.const 8))
  ;; functions from map
  (func $map__fn1 (param i32) (result i32)
    (local i32) (local i32)
    i32.const 8
    local.get 0
    i32.const 2
    i32.shl
    i32.add
    call $__malloc
    local.set 1
    local.get 1
    local.get 0
    i32.store
    local.get 1
    local.tee 2
    return)
  (func $map_mapNew (result i32)
    (local i32) (local i32)
    i32.const 28
    call $__malloc
    local.set 0
    local.get 0
    i32.const 5
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
    global.get $map_global1
    i32.store
    local.get 0
    i32.const 8
    i32.add
    i32.const 8
    i32.add
    global.get $map_global1
    call $map__fn1
    i32.store
    local.get 0
    i32.const 8
    i32.add
    i32.const 12
    i32.add
    global.get $map_global1
    call $map__fn1
    i32.store
    local.get 0
    i32.const 8
    i32.add
    i32.const 16
    i32.add
    global.get $map_global1
    call $map__fn1
    i32.store
    local.get 0
    local.tee 1
    return)
  (func $map__fn3 (param i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
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
    i32.const 8
    i32.add
    i32.load
    local.set 3
    local.get 1
    i32.const 8
    i32.add
    i32.const 12
    i32.add
    i32.load
    local.set 4
    local.get 1
    i32.const 8
    i32.add
    i32.const 16
    i32.add
    i32.load
    local.set 5
    local.get 2
    i32.const 2
    i32.mul
    local.set 6
    local.get 6
    call $map__fn1
    local.set 7
    local.get 6
    call $map__fn1
    local.set 8
    local.get 6
    call $map__fn1
    local.set 9
    local.get 7
    local.tee 19
    local.set 10
    local.get 8
    local.tee 20
    local.set 11
    local.get 9
    local.tee 21
    local.set 12
    local.get 6
    local.tee 22
    i32.const 1
    i32.sub
    local.set 13
    i32.const 0
    local.set 14
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 14
          local.get 2
          i32.lt_s
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 5
            i32.const 8
            i32.add
            local.get 14
            i32.const 2
            i32.shl
            i32.add
            i32.load
            i32.const 0
            i32.ne
            if  ;; label = @5
              block  ;; label = @6
                local.get 3
                i32.const 8
                i32.add
                local.get 14
                i32.const 2
                i32.shl
                i32.add
                i32.load
                local.set 15
                local.get 4
                i32.const 8
                i32.add
                local.get 14
                i32.const 2
                i32.shl
                i32.add
                i32.load
                local.set 16
                local.get 15
                local.tee 18
                local.get 13
                i32.and
                local.set 17
                block  ;; label = @7
                  loop  ;; label = @8
                    block  ;; label = @9
                      local.get 12
                      i32.const 8
                      i32.add
                      local.get 17
                      i32.const 2
                      i32.shl
                      i32.add
                      i32.load
                      i32.const 0
                      i32.ne
                      i32.eqz
                      br_if 2 (;@7;)
                      local.get 17
                      i32.const 1
                      i32.add
                      local.get 13
                      i32.and
                      local.set 17
                      br 1 (;@8;)
                    end
                  end
                end
                local.get 10
                i32.const 8
                i32.add
                local.get 17
                i32.const 2
                i32.shl
                i32.add
                local.get 15
                i32.store
                local.get 11
                i32.const 8
                i32.add
                local.get 17
                i32.const 2
                i32.shl
                i32.add
                local.get 16
                i32.store
                local.get 12
                i32.const 8
                i32.add
                local.get 17
                i32.const 2
                i32.shl
                i32.add
                i32.const 1
                i32.store
              end
            end
            local.get 14
            i32.const 1
            i32.add
            local.set 14
          end
          br 1 (;@2;)
        end
      end
    end
    local.get 1
    i32.const 8
    i32.add
    i32.const 4
    i32.add
    local.get 6
    i32.store
    local.get 1
    i32.const 8
    i32.add
    i32.const 8
    i32.add
    local.get 7
    i32.store
    local.get 1
    i32.const 8
    i32.add
    i32.const 12
    i32.add
    local.get 8
    i32.store
    local.get 1
    i32.const 8
    i32.add
    i32.const 16
    i32.add
    local.get 9
    i32.store)
  (func $map_mapSet (param i32 i32 i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.tee 9
    local.set 3
    local.get 3
    i32.const 8
    i32.add
    i32.load
    i32.const 1
    i32.add
    i32.const 2
    i32.mul
    local.get 3
    i32.const 8
    i32.add
    i32.const 4
    i32.add
    i32.load
    i32.gt_s
    if  ;; label = @1
      local.get 0
      call $map__fn3
    end
    local.get 0
    local.tee 10
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
    i32.const 8
    i32.add
    i32.load
    local.set 5
    local.get 3
    i32.const 8
    i32.add
    i32.const 12
    i32.add
    i32.load
    local.set 6
    local.get 3
    i32.const 8
    i32.add
    i32.const 16
    i32.add
    i32.load
    local.set 7
    local.get 4
    local.tee 11
    i32.const 1
    local.tee 12
    i32.sub
    local.set 4
    local.get 1
    local.tee 13
    local.get 4
    local.tee 14
    i32.and
    local.set 8
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 7
          i32.const 8
          i32.add
          local.get 8
          i32.const 2
          i32.shl
          i32.add
          i32.load
          i32.const 0
          i32.ne
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 5
            i32.const 8
            i32.add
            local.get 8
            i32.const 2
            i32.shl
            i32.add
            i32.load
            local.get 1
            i32.eq
            if  ;; label = @5
              block  ;; label = @6
                local.get 6
                i32.const 8
                i32.add
                local.get 8
                i32.const 2
                i32.shl
                i32.add
                local.get 2
                i32.store
                return
              end
            end
            local.get 8
            i32.const 1
            i32.add
            local.get 4
            i32.and
            local.set 8
          end
          br 1 (;@2;)
        end
      end
    end
    local.get 5
    i32.const 8
    i32.add
    local.get 8
    i32.const 2
    i32.shl
    i32.add
    local.get 1
    i32.store
    local.get 6
    i32.const 8
    i32.add
    local.get 8
    i32.const 2
    i32.shl
    i32.add
    local.get 2
    i32.store
    local.get 7
    i32.const 8
    i32.add
    local.get 8
    i32.const 2
    i32.shl
    i32.add
    i32.const 1
    i32.store
    local.get 3
    i32.const 8
    i32.add
    local.get 3
    i32.const 8
    i32.add
    i32.load
    i32.const 1
    i32.add
    i32.store)
  (func $map_mapGet (param i32 i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
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
    i32.const 8
    i32.add
    i32.load
    local.set 5
    local.get 3
    i32.const 8
    i32.add
    i32.const 12
    i32.add
    i32.load
    local.set 6
    local.get 3
    i32.const 8
    i32.add
    i32.const 16
    i32.add
    i32.load
    local.set 3
    local.get 4
    local.tee 8
    i32.const 1
    i32.sub
    local.set 4
    local.get 1
    local.get 4
    local.tee 9
    i32.and
    local.set 7
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 3
          i32.const 8
          i32.add
          local.get 7
          i32.const 2
          i32.shl
          i32.add
          i32.load
          i32.const 0
          i32.ne
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 5
            i32.const 8
            i32.add
            local.get 7
            i32.const 2
            i32.shl
            i32.add
            i32.load
            local.get 1
            i32.eq
            if  ;; label = @5
              local.get 6
              i32.const 8
              i32.add
              local.get 7
              i32.const 2
              i32.shl
              i32.add
              i32.load
              return
            end
            local.get 7
            i32.const 1
            i32.add
            local.get 4
            i32.and
            local.set 7
          end
          br 1 (;@2;)
        end
      end
    end
    local.get 2
    return)
  (func $map_mapHas (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.set 2
    local.get 2
    i32.const 8
    i32.add
    i32.const 4
    i32.add
    i32.load
    local.set 3
    local.get 2
    i32.const 8
    i32.add
    i32.const 8
    i32.add
    i32.load
    local.set 4
    local.get 2
    i32.const 8
    i32.add
    i32.const 16
    i32.add
    i32.load
    local.set 2
    local.get 3
    local.tee 6
    i32.const 1
    i32.sub
    local.set 3
    local.get 1
    local.get 3
    local.tee 7
    i32.and
    local.set 5
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 2
          i32.const 8
          i32.add
          local.get 5
          i32.const 2
          i32.shl
          i32.add
          i32.load
          i32.const 0
          i32.ne
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 4
            i32.const 8
            i32.add
            local.get 5
            i32.const 2
            i32.shl
            i32.add
            i32.load
            local.get 1
            i32.eq
            if  ;; label = @5
              i32.const 1
              return
            end
            local.get 5
            i32.const 1
            i32.add
            local.get 3
            i32.and
            local.set 5
          end
          br 1 (;@2;)
        end
      end
    end
    i32.const 0
    return)
  (func $map_mapSize (param i32) (result i32)
    (local i32)
    local.get 0
    local.set 1
    local.get 1
    i32.const 8
    i32.add
    i32.load
    return)

  ;; functions from date
  (func $date_isLeapYear (param i32) (result i32)
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
  (func $date_daysInMonth (param i32 i32) (result i32)
    local.get 1
    i32.const 2
    i32.eq
    if  ;; label = @1
      local.get 0
      call $date_isLeapYear
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
    if (result i32)  ;; label = @1
      i32.const 1
    else
      local.get 1
      i32.const 6
      i32.eq
    end
    if (result i32)  ;; label = @1
      i32.const 1
    else
      local.get 1
      i32.const 9
      i32.eq
    end
    if (result i32)  ;; label = @1
      i32.const 1
    else
      local.get 1
      i32.const 11
      i32.eq
    end
    if  ;; label = @1
      i32.const 30
      return
    end
    i32.const 31
    return)
  (func $date_daysFromCivil (param i32 i32 i32) (result i32)
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
  (func $date_weekdayFromDays (param i32) (result i32)
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
  (func $date_yearFromDays (param i32) (result i32)
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
  (func $date_monthFromDays (param i32) (result i32)
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
  (func $date_dayFromDays (param i32) (result i32)
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

  ;; globals from json
  (global $json_global1 (mut i32) (i32.const 131072))
  (global $json_global2 (mut i32) (i32.const 131072))
  ;; functions from json
  (func $json_cabi_realloc (param i32 i32 i32 i32) (result i32)
    local.get 3
    call $__malloc
    local.get 0
    local.get 0
    i32.eqz
    select)
  (func $json__fn2 (param i32 i32 i32) (result i32)
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
  (func $json__fn3 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    i32.load
    local.set 3
    i32.const 8
    local.get 1
    i32.const 2
    i32.shl
    i32.add
    call $__malloc
    local.set 2
    local.get 2
    local.get 3
    i32.store
    local.get 2
    local.get 1
    i32.store offset=4
    i32.const 0
    local.set 4
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 4
          local.get 3
          i32.ge_u
          br_if 2 (;@1;)
          local.get 2
          i32.const 8
          i32.add
          local.get 4
          i32.const 2
          i32.shl
          i32.add
          local.get 0
          i32.const 8
          i32.add
          local.get 4
          i32.const 2
          i32.shl
          i32.add
          i32.load
          i32.store
          local.get 4
          local.tee 5
          i32.const 1
          i32.add
          local.set 4
          br 1 (;@2;)
        end
      end
    end
    local.get 2
    local.tee 6)
  (func $json__fn4 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32)
    local.get 0
    i32.load
    local.set 2
    local.get 0
    i32.load offset=4
    local.set 3
    local.get 2
    local.get 3
    i32.ge_u
    if  ;; label = @1
      local.get 0
      local.get 3
      i32.const 1
      i32.shl
      call $json__fn3
      local.set 0
    end
    local.get 0
    i32.const 8
    i32.add
    local.get 2
    i32.const 2
    i32.shl
    i32.add
    local.get 1
    i32.store
    local.get 2
    local.tee 4
    i32.const 1
    i32.add
    local.set 2
    local.get 0
    local.get 2
    i32.store
    local.get 0
    local.tee 5)
  (func $json__fn5 (result i32)
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
  (func $json__fn6 (param i32) (result i32)
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
    i32.const 1
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
  (func $json__fn7 (param i32 i32)
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
          global.get $json_global1
          local.get 1
          i32.ge_s
          if  ;; label = @4
            i32.const 0
            local.set 2
          else
            block  ;; label = @5
              local.get 0
              local.get 1
              global.get $json_global1
              call $json__fn2
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
                global.get $json_global1
                i32.const 1
                i32.add
                global.set $json_global1
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
  (func $json__fn8 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    global.get $json_global1
    local.tee 11
    i32.const 1
    local.tee 12
    i32.add
    global.set $json_global1
    global.get $json_global1
    local.tee 13
    local.set 2
    i32.const 1
    local.tee 14
    local.set 3
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 3
          i32.const 1
          i32.eq
          i32.eqz
          br_if 2 (;@1;)
          global.get $json_global1
          local.get 1
          i32.ge_s
          if  ;; label = @4
            i32.const 0
            local.set 3
          else
            block  ;; label = @5
              local.get 0
              local.get 1
              global.get $json_global1
              call $json__fn2
              local.set 4
              local.get 4
              i32.const 92
              i32.eq
              if  ;; label = @6
                global.get $json_global1
                i32.const 2
                i32.add
                global.set $json_global1
              else
                local.get 4
                i32.const 34
                i32.eq
                if  ;; label = @7
                  i32.const 0
                  local.set 3
                else
                  global.get $json_global1
                  i32.const 1
                  i32.add
                  global.set $json_global1
                end
              end
            end
          end
          br 1 (;@2;)
        end
      end
    end
    global.get $json_global1
    local.tee 15
    local.set 3
    local.get 3
    local.tee 16
    local.get 2
    local.tee 17
    i32.sub
    local.set 4
    i32.const 8
    local.get 4
    i32.add
    call $__malloc
    local.set 5
    local.get 5
    local.get 4
    i32.store
    i32.const 0
    local.set 6
    local.get 2
    local.tee 18
    local.set 2
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 2
          local.get 3
          i32.lt_s
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 0
            local.get 1
            local.get 2
            call $json__fn2
            local.set 4
            local.get 4
            i32.const 92
            i32.eq
            if  ;; label = @5
              block  ;; label = @6
                local.get 2
                local.tee 7
                i32.const 1
                i32.add
                local.set 2
                local.get 0
                local.get 1
                local.get 2
                call $json__fn2
                local.set 4
                local.get 4
                i32.const 110
                i32.eq
                if  ;; label = @7
                  i32.const 10
                  local.set 4
                else
                  local.get 4
                  i32.const 116
                  i32.eq
                  if  ;; label = @8
                    i32.const 9
                    local.set 4
                  else
                    local.get 4
                    i32.const 114
                    i32.eq
                    if  ;; label = @9
                      i32.const 13
                      local.set 4
                    else
                      local.get 4
                      i32.const 98
                      i32.eq
                      if  ;; label = @10
                        i32.const 8
                        local.set 4
                      else
                        local.get 4
                        i32.const 102
                        i32.eq
                        if  ;; label = @11
                          i32.const 12
                          local.set 4
                        else
                          local.get 4
                          i32.const 34
                          i32.eq
                          if  ;; label = @12
                            i32.const 34
                            local.set 4
                          else
                            local.get 4
                            i32.const 92
                            i32.eq
                            if  ;; label = @13
                              i32.const 92
                              local.set 4
                            else
                              local.get 4
                              i32.const 47
                              i32.eq
                              if  ;; label = @14
                                i32.const 47
                                local.set 4
                              else
                                local.get 4
                                local.set 4
                              end
                            end
                          end
                        end
                      end
                    end
                  end
                end
              end
            end
            local.get 5
            i32.const 8
            i32.add
            local.get 6
            i32.add
            local.get 4
            i32.store8
            local.get 6
            local.tee 8
            i32.const 1
            local.tee 9
            i32.add
            local.set 6
            local.get 2
            local.tee 10
            local.get 9
            i32.add
            local.set 2
          end
          br 1 (;@2;)
        end
      end
    end
    local.get 3
    local.tee 19
    i32.const 1
    local.tee 20
    i32.add
    global.set $json_global1
    local.get 6
    global.set $json_global2
    local.get 5
    local.tee 21
    return)
  (func $json__fn9 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $json__fn8
    local.set 2
    i32.const 24
    call $__malloc
    local.set 3
    local.get 3
    i32.const 4
    i32.store
    local.get 3
    i32.const 8
    i32.add
    i32.const 3
    i32.store
    local.get 3
    i32.const 8
    i32.add
    i32.const 4
    i32.add
    local.get 2
    i32.store
    local.get 3
    i32.const 8
    i32.add
    i32.const 8
    i32.add
    global.get $json_global2
    i32.store
    local.get 3
    local.tee 4
    return)
  (func $json__fn10 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    i32.const 0
    local.tee 12
    local.set 2
    local.get 0
    local.get 1
    global.get $json_global1
    call $json__fn2
    i32.const 45
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        i32.const 1
        local.tee 6
        local.set 2
        global.get $json_global1
        i32.const 1
        local.tee 7
        i32.add
        global.set $json_global1
      end
    end
    i32.const 0
    local.tee 13
    local.set 3
    i32.const 1
    local.set 4
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 4
          i32.const 1
          i32.eq
          i32.eqz
          br_if 2 (;@1;)
          global.get $json_global1
          local.get 1
          i32.ge_s
          if  ;; label = @4
            i32.const 0
            local.set 4
          else
            block  ;; label = @5
              local.get 0
              local.get 1
              global.get $json_global1
              call $json__fn2
              local.set 5
              local.get 5
              i32.const 48
              i32.lt_s
              if (result i32)  ;; label = @6
                i32.const 1
              else
                local.get 5
                i32.const 57
                i32.gt_s
              end
              if  ;; label = @6
                i32.const 0
                local.set 4
              else
                block  ;; label = @7
                  local.get 3
                  i32.const 10
                  i32.mul
                  local.get 5
                  i32.const 48
                  i32.sub
                  i32.add
                  local.set 3
                  global.get $json_global1
                  i32.const 1
                  i32.add
                  global.set $json_global1
                end
              end
            end
          end
          br 1 (;@2;)
        end
      end
    end
    global.get $json_global1
    local.get 1
    i32.lt_s
    if (result i32)  ;; label = @1
      local.get 0
      local.get 1
      global.get $json_global1
      call $json__fn2
      i32.const 46
      i32.eq
    else
      i32.const 0
    end
    if  ;; label = @1
      block  ;; label = @2
        global.get $json_global1
        i32.const 1
        local.tee 8
        i32.add
        global.set $json_global1
        i32.const 1
        local.tee 9
        local.set 4
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 4
              i32.const 1
              i32.eq
              i32.eqz
              br_if 2 (;@3;)
              global.get $json_global1
              local.get 1
              i32.ge_s
              if  ;; label = @6
                i32.const 0
                local.set 4
              else
                block  ;; label = @7
                  local.get 0
                  local.get 1
                  global.get $json_global1
                  call $json__fn2
                  local.set 5
                  local.get 5
                  i32.const 48
                  i32.lt_s
                  if (result i32)  ;; label = @8
                    i32.const 1
                  else
                    local.get 5
                    i32.const 57
                    i32.gt_s
                  end
                  if  ;; label = @8
                    i32.const 0
                    local.set 4
                  else
                    global.get $json_global1
                    i32.const 1
                    i32.add
                    global.set $json_global1
                  end
                end
              end
              br 1 (;@4;)
            end
          end
        end
      end
    end
    global.get $json_global1
    local.get 1
    i32.lt_s
    if  ;; label = @1
      block  ;; label = @2
        local.get 0
        local.get 1
        global.get $json_global1
        call $json__fn2
        local.set 4
        local.get 4
        i32.const 101
        i32.eq
        if (result i32)  ;; label = @3
          i32.const 1
        else
          local.get 4
          i32.const 69
          i32.eq
        end
        if  ;; label = @3
          block  ;; label = @4
            global.get $json_global1
            i32.const 1
            local.tee 10
            i32.add
            global.set $json_global1
            global.get $json_global1
            local.get 1
            i32.lt_s
            if  ;; label = @5
              block  ;; label = @6
                local.get 0
                local.get 1
                global.get $json_global1
                call $json__fn2
                local.set 4
                local.get 4
                i32.const 43
                i32.eq
                if (result i32)  ;; label = @7
                  i32.const 1
                else
                  local.get 4
                  i32.const 45
                  i32.eq
                end
                if  ;; label = @7
                  global.get $json_global1
                  i32.const 1
                  i32.add
                  global.set $json_global1
                end
              end
            end
            i32.const 1
            local.tee 11
            local.set 4
            block  ;; label = @5
              loop  ;; label = @6
                block  ;; label = @7
                  local.get 4
                  i32.const 1
                  i32.eq
                  i32.eqz
                  br_if 2 (;@5;)
                  global.get $json_global1
                  local.get 1
                  i32.ge_s
                  if  ;; label = @8
                    i32.const 0
                    local.set 4
                  else
                    block  ;; label = @9
                      local.get 0
                      local.get 1
                      global.get $json_global1
                      call $json__fn2
                      local.set 5
                      local.get 5
                      i32.const 48
                      i32.lt_s
                      if (result i32)  ;; label = @10
                        i32.const 1
                      else
                        local.get 5
                        i32.const 57
                        i32.gt_s
                      end
                      if  ;; label = @10
                        i32.const 0
                        local.set 4
                      else
                        global.get $json_global1
                        i32.const 1
                        i32.add
                        global.set $json_global1
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
    i32.const 1
    i32.eq
    if  ;; label = @1
      i32.const 0
      local.get 3
      i32.sub
      local.set 3
    end
    i32.const 24
    call $__malloc
    local.set 2
    local.get 2
    i32.const 4
    i32.store
    local.get 2
    i32.const 8
    i32.add
    i32.const 2
    i32.store
    local.get 2
    i32.const 8
    i32.add
    i32.const 4
    i32.add
    local.get 3
    i32.store
    local.get 2
    local.tee 14
    return)
  (func $json__fn11 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32)
    global.get $json_global1
    i32.const 1
    i32.add
    global.set $json_global1
    i32.const 40
    call $__malloc
    local.set 2
    local.get 2
    i32.const 0
    i32.store
    local.get 2
    i32.const 8
    i32.store offset=4
    local.get 0
    local.get 1
    call $json__fn7
    local.get 0
    local.get 1
    global.get $json_global1
    call $json__fn2
    i32.const 93
    i32.eq
    if  ;; label = @1
      global.get $json_global1
      i32.const 1
      i32.add
      global.set $json_global1
    else
      block  ;; label = @2
        i32.const 0
        local.set 3
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 3
              i32.eqz
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                local.get 0
                local.get 1
                call $json__fn7
                local.get 0
                local.get 1
                call $json__fn13
                local.set 4
                local.get 2
                local.get 4
                call $json__fn4
                local.set 2
                local.get 0
                local.get 1
                call $json__fn7
                local.get 0
                local.get 1
                global.get $json_global1
                call $json__fn2
                local.set 4
                local.get 4
                i32.const 44
                i32.eq
                if  ;; label = @7
                  global.get $json_global1
                  i32.const 1
                  i32.add
                  global.set $json_global1
                else
                  block  ;; label = @8
                    local.get 4
                    i32.const 93
                    i32.eq
                    if  ;; label = @9
                      global.get $json_global1
                      i32.const 1
                      i32.add
                      global.set $json_global1
                    end
                    i32.const 1
                    local.set 3
                  end
                end
              end
              br 1 (;@4;)
            end
          end
        end
      end
    end
    local.get 2
    local.tee 5
    local.set 3
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
    i32.load
    i32.store
    local.get 4
    local.tee 6
    return)
  (func $json__fn12 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    global.get $json_global1
    i32.const 1
    i32.add
    global.set $json_global1
    i32.const 40
    call $__malloc
    local.set 2
    local.get 2
    i32.const 0
    i32.store
    local.get 2
    i32.const 8
    i32.store offset=4
    i32.const 40
    call $__malloc
    local.set 3
    local.get 3
    i32.const 0
    i32.store
    local.get 3
    i32.const 8
    i32.store offset=4
    local.get 0
    local.get 1
    call $json__fn7
    local.get 0
    local.get 1
    global.get $json_global1
    call $json__fn2
    i32.const 125
    i32.eq
    if  ;; label = @1
      global.get $json_global1
      i32.const 1
      i32.add
      global.set $json_global1
    else
      block  ;; label = @2
        i32.const 0
        local.set 4
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 4
              i32.eqz
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                local.get 0
                local.get 1
                call $json__fn7
                local.get 0
                local.get 1
                call $json__fn8
                local.set 5
                global.get $json_global2
                local.set 6
                local.get 3
                local.get 5
                call $json__fn4
                local.set 3
                local.get 3
                local.get 6
                call $json__fn4
                local.set 3
                local.get 0
                local.get 1
                call $json__fn7
                local.get 0
                local.get 1
                global.get $json_global1
                call $json__fn2
                i32.const 58
                i32.eq
                if  ;; label = @7
                  global.get $json_global1
                  i32.const 1
                  i32.add
                  global.set $json_global1
                end
                local.get 0
                local.get 1
                call $json__fn7
                local.get 0
                local.get 1
                call $json__fn13
                local.set 5
                local.get 2
                local.get 5
                call $json__fn4
                local.set 2
                local.get 0
                local.get 1
                call $json__fn7
                local.get 0
                local.get 1
                global.get $json_global1
                call $json__fn2
                local.set 5
                local.get 5
                i32.const 44
                i32.eq
                if  ;; label = @7
                  global.get $json_global1
                  i32.const 1
                  i32.add
                  global.set $json_global1
                else
                  block  ;; label = @8
                    local.get 5
                    i32.const 125
                    i32.eq
                    if  ;; label = @9
                      global.get $json_global1
                      i32.const 1
                      i32.add
                      global.set $json_global1
                    end
                    i32.const 1
                    local.set 4
                  end
                end
              end
              br 1 (;@4;)
            end
          end
        end
      end
    end
    local.get 2
    local.tee 7
    local.set 4
    local.get 3
    local.tee 8
    local.set 3
    i32.const 24
    call $__malloc
    local.set 5
    local.get 5
    i32.const 4
    i32.store
    local.get 5
    i32.const 8
    i32.add
    i32.const 5
    i32.store
    local.get 5
    i32.const 8
    i32.add
    i32.const 4
    i32.add
    local.get 4
    i32.store
    local.get 5
    i32.const 8
    i32.add
    i32.const 8
    i32.add
    local.get 2
    i32.load
    i32.store
    local.get 5
    i32.const 8
    i32.add
    i32.const 12
    i32.add
    local.get 3
    i32.store
    local.get 5
    local.tee 9
    return)
  (func $json__fn13 (param i32 i32) (result i32)
    (local i32)
    local.get 0
    local.get 1
    call $json__fn7
    local.get 0
    local.get 1
    global.get $json_global1
    call $json__fn2
    local.set 2
    local.get 2
    i32.const 123
    i32.eq
    if  ;; label = @1
      local.get 0
      local.get 1
      call $json__fn12
      return
    end
    local.get 2
    i32.const 91
    i32.eq
    if  ;; label = @1
      local.get 0
      local.get 1
      call $json__fn11
      return
    end
    local.get 2
    i32.const 34
    i32.eq
    if  ;; label = @1
      local.get 0
      local.get 1
      call $json__fn9
      return
    end
    local.get 2
    i32.const 116
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        global.get $json_global1
        i32.const 4
        i32.add
        global.set $json_global1
        i32.const 1
        call $json__fn6
        return
      end
    end
    local.get 2
    i32.const 102
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        global.get $json_global1
        i32.const 5
        i32.add
        global.set $json_global1
        i32.const 0
        call $json__fn6
        return
      end
    end
    local.get 2
    i32.const 110
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        global.get $json_global1
        i32.const 4
        i32.add
        global.set $json_global1
        call $json__fn5
        return
      end
    end
    local.get 0
    local.get 1
    call $json__fn10
    return)
  (func $json_jsonParse (param i32 i32) (result i32)
    i32.const 0
    global.set $json_global1
    local.get 0
    local.get 1
    call $json__fn13
    return)
  (func $json_jsonType (param i32) (result i32)
    (local i32)
    local.get 0
    local.set 1
    local.get 1
    i32.const 8
    i32.add
    i32.load
    return)
  (func $json_jsonInt (param i32) (result i32)
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
  (func $json_jsonBool (param i32) (result i32)
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
  (func $json_jsonArrayLen (param i32) (result i32)
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
    i32.load
    return)
  (func $json_jsonArrayGet (param i32 i32) (result i32)
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
    i32.const 2
    i32.shl
    i32.add
    i32.load
    return)
  (func $json_jsonObjectLen (param i32) (result i32)
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
  (func $json_jsonStrLen (param i32) (result i32)
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
  (func $json_jsonStrCharAt (param i32 i32) (result i32)
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
  (func $json_jsonStrEq (param i32 i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.set 3
    local.get 3
    i32.const 8
    i32.add
    i32.load
    i32.const 3
    i32.ne
    if  ;; label = @1
      i32.const 0
      return
    end
    local.get 3
    i32.const 8
    i32.add
    i32.const 8
    i32.add
    i32.load
    local.set 4
    local.get 4
    local.get 2
    i32.ne
    if  ;; label = @1
      i32.const 0
      return
    end
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
            local.get 3
            i32.const 8
            i32.add
            local.get 5
            i32.add
            i32.load8_u
            local.get 1
            local.get 2
            local.get 5
            call $json__fn2
            i32.ne
            if  ;; label = @5
              i32.const 0
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
    i32.const 1
    return)
  (func $json_jsonGet (param i32 i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.set 3
    local.get 3
    i32.const 8
    i32.add
    i32.load
    i32.const 5
    i32.ne
    if  ;; label = @1
      i32.const -1
      return
    end
    local.get 3
    i32.const 8
    i32.add
    i32.const 8
    i32.add
    i32.load
    local.set 4
    local.get 3
    i32.const 8
    i32.add
    i32.const 4
    i32.add
    i32.load
    local.set 5
    local.get 3
    i32.const 8
    i32.add
    i32.const 12
    i32.add
    i32.load
    local.set 3
    local.get 5
    local.set 5
    local.get 3
    local.tee 14
    local.set 3
    local.get 2
    local.set 6
    i32.const 0
    local.set 7
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 7
          local.get 4
          i32.lt_s
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 3
            i32.const 8
            i32.add
            local.get 7
            i32.const 2
            i32.mul
            i32.const 2
            i32.shl
            i32.add
            i32.load
            local.set 8
            local.get 3
            i32.const 8
            i32.add
            local.get 7
            i32.const 2
            i32.mul
            i32.const 1
            i32.add
            i32.const 2
            i32.shl
            i32.add
            i32.load
            local.set 9
            local.get 9
            local.get 6
            i32.eq
            if  ;; label = @5
              block  ;; label = @6
                local.get 8
                local.set 8
                i32.const 1
                local.set 10
                i32.const 0
                local.set 11
                block  ;; label = @7
                  loop  ;; label = @8
                    block  ;; label = @9
                      local.get 11
                      local.get 9
                      i32.lt_s
                      i32.eqz
                      br_if 2 (;@7;)
                      local.get 8
                      i32.const 8
                      i32.add
                      local.get 11
                      i32.add
                      i32.load8_u
                      local.get 1
                      local.get 2
                      local.get 11
                      call $json__fn2
                      i32.ne
                      if  ;; label = @10
                        block  ;; label = @11
                          i32.const 0
                          local.set 10
                          local.get 9
                          local.set 11
                        end
                      else
                        local.get 11
                        i32.const 1
                        i32.add
                        local.set 11
                      end
                      br 1 (;@8;)
                    end
                  end
                end
                local.get 10
                i32.const 1
                i32.eq
                if  ;; label = @7
                  local.get 5
                  i32.const 8
                  i32.add
                  local.get 7
                  i32.const 2
                  i32.shl
                  i32.add
                  i32.load
                  return
                end
              end
            end
            local.get 7
            local.tee 12
            i32.const 1
            local.tee 13
            i32.add
            local.set 7
          end
          br 1 (;@2;)
        end
      end
    end
    i32.const -1
    return)
  (func $json_jsonHas (param i32 i32 i32) (result i32)
    local.get 0
    local.get 1
    local.get 2
    call $json_jsonGet
    i32.const -1
    i32.eq
    if (result i32)  ;; label = @1
      i32.const 0
    else
      i32.const 1
    end
    return)

  ;; globals from regex
  (global $regex_global1 (mut i32) (i32.const 131072))
  ;; functions from regex
  (func $regex_cabi_realloc (param i32 i32 i32 i32) (result i32)
    local.get 3
    call $__malloc
    local.get 0
    local.get 0
    i32.eqz
    select)
  (func $regex__fn2 (param i32 i32 i32) (result i32)
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
  (func $regex__fn3 (param i32) (result i32)
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
  (func $regex__fn4 (param i32) (result i32)
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
  (func $regex__fn5 (param i32 i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    local.get 2
    call $regex__fn2
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
          call $regex__fn2
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
                call $regex__fn2
                i32.const 93
                i32.eq
                if  ;; label = @7
                  i32.const 0
                  local.set 4
                else
                  local.get 0
                  local.get 1
                  local.get 3
                  call $regex__fn2
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
  (func $regex__fn6 (param i32 i32 i32 i32) (result i32)
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
      call $regex__fn2
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
            call $regex__fn2
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
                call $regex__fn2
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
                    call $regex__fn2
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
                        call $regex__fn3
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
                          call $regex__fn4
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
                      call $regex__fn2
                      i32.const 45
                      i32.eq
                      if  ;; label = @10
                        local.get 0
                        local.get 1
                        local.get 4
                        i32.const 2
                        i32.add
                        call $regex__fn2
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
                        call $regex__fn2
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
  (func $regex__fn7 (param i32 i32 i32 i32) (result i32)
    (local i32)
    local.get 0
    local.get 1
    local.get 2
    call $regex__fn2
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
        call $regex__fn2
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
          call $regex__fn3
          return
        end
        local.get 4
        i32.const 87
        i32.eq
        if  ;; label = @3
          local.get 3
          call $regex__fn3
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
          call $regex__fn4
          return
        end
        local.get 4
        i32.const 83
        i32.eq
        if  ;; label = @3
          local.get 3
          call $regex__fn4
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
      call $regex__fn6
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
  (func $regex__fn8 (param i32 i32 i32 i32 i32 i32) (result i32)
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
      call $regex__fn2
      call $regex__fn7
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
  (func $regex__fn9 (param i32 i32 i32 i32 i32 i32 i32 i32) (result i32)
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
            call $regex__fn2
            call $regex__fn7
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
            call $regex__fn10
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
  (func $regex__fn10 (param i32 i32 i32 i32 i32 i32) (result i32)
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
    call $regex__fn2
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
    call $regex__fn5
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
        call $regex__fn2
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
      call $regex__fn9
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
      call $regex__fn9
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
        call $regex__fn8
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
            call $regex__fn10
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
        call $regex__fn10
        return
      end
    end
    local.get 0
    local.get 1
    local.get 2
    local.get 3
    local.get 4
    local.get 5
    call $regex__fn8
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
      call $regex__fn10
      return
    end
    i32.const -1
    return)
  (func $regex__fn11 (param i32 i32 i32 i32) (result i32)
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
      call $regex__fn2
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
            call $regex__fn10
            local.set 9
            local.get 9
            i32.const 0
            i32.ge_s
            if  ;; label = @5
              block  ;; label = @6
                local.get 9
                global.set $regex_global1
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
  (func $regex_reTest (param i32 i32 i32 i32) (result i32)
    local.get 0
    local.get 1
    local.get 2
    local.get 3
    call $regex__fn11
    i32.const 0
    i32.ge_s
    if (result i32)  ;; label = @1
      i32.const 1
    else
      i32.const 0
    end
    return)
  (func $regex_reSearch (param i32 i32 i32 i32) (result i32)
    local.get 0
    local.get 1
    local.get 2
    local.get 3
    call $regex__fn11
    return)
  (func $regex_reEnd (result i32)
    global.get $regex_global1
    return)
)