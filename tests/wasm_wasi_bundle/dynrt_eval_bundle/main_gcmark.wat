(module
  (import "wasi_snapshot_preview1" "proc_exit" (func $proc_exit (param i32)))
  (import "wasi_snapshot_preview1" "fd_write" (func $fd_write (param i32 i32 i32 i32) (result i32)))
  ;; imports from dynrt_lib_modc
  (import "env" "__host_call" (func $dynrt_lib_modc___host_call (param i32 i32) (result i32)))
  (memory (export "memory") 2)
  (global $__heap_ptr (mut i32) (i32.const 805))
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
    (local $n1 i32)
    (local $n2 i32)
    (local $n3 i32)
    (local $arr i32)
    (local $orphan i32)
    (local $obj i32)
    (local $__iface_tmp i32)
    (global.set $guard (call $__malloc (i32.const 40)))
      (i32.store (global.get $guard) (i32.const 1))
      (i32.store offset=4 (global.get $guard) (i32.const 8))
      (i32.store offset=8 (global.get $guard) (i32.const 0))
    (local.set $n1 (call $dynrt_lib_modc_dynNumber (f64.const 1)))
    (local.set $n2 (call $dynrt_lib_modc_dynNumber (f64.const 2)))
    (local.set $n3 (call $dynrt_lib_modc_dynNumber (f64.const 3)))
    (local.set $arr (call $dynrt_lib_modc_dynArray ))
    (call $dynrt_lib_modc_dynPush (local.get $arr) (local.get $n1))
    (call $dynrt_lib_modc_dynPush (local.get $arr) (local.get $n2))
    (call $dynrt_lib_modc_dynPush (local.get $arr) (local.get $n3))
    (call $dynrt_lib_modc_dynGcMarkClear )
    (call $dynrt_lib_modc_dynGcMark (local.get $arr))
    (call $check (if (result i32) (i32.eq (call $dynrt_lib_modc_dynGcMarkedCount ) (i32.const 4)) (then (i32.const 1)) (else (i32.const 0))))
    (local.set $orphan (call $dynrt_lib_modc_dynNumber (f64.const 99)))
    (call $dynrt_lib_modc_dynGcMarkClear )
    (call $dynrt_lib_modc_dynGcMark (local.get $arr))
    (call $check (if (result i32) (i32.eq (call $dynrt_lib_modc_dynGcMarkedCount ) (i32.const 4)) (then (i32.const 1)) (else (i32.const 0))))
    (local.set $obj (call $dynrt_lib_modc_dynObject ))
    (call $dynrt_lib_modc_dynSet (local.get $obj) (i32.const 260) (i32.const 5) (local.get $arr))
    (call $dynrt_lib_modc_dynGcMarkClear )
    (call $dynrt_lib_modc_dynGcMark (local.get $obj))
    (call $check (if (result i32) (i32.eq (call $dynrt_lib_modc_dynGcMarkedCount ) (i32.const 5)) (then (i32.const 1)) (else (i32.const 0))))
    (call $dynrt_lib_modc_dynGcMarkClear )
    (call $dynrt_lib_modc_dynGcMark (local.get $arr))
    (call $check (if (result i32) (i32.eq (call $dynrt_lib_modc_dynGcMarkedCount ) (i32.const 4)) (then (i32.const 1)) (else (i32.const 0))))
    (call $check (if (result i32) (i32.eq (call $dynrt_lib_modc_dynGcCellCount ) (i32.const 6)) (then (i32.const 1)) (else (i32.const 0))))
        (i32.store (i32.const 0) (i32.const 265))
          (i32.store (i32.const 4) (i32.const 38))
          (drop (call $fd_write
            (i32.const 1)
            (i32.const 0)
            (i32.const 1)
            (i32.const 128)))
    (call $proc_exit (i32.const 0))
  )
  (data (i32.const 260) "\69\74\65\6d\73")
  (data (i32.const 265) "\47\43\20\50\61\72\74\34\61\20\6d\61\72\6b\3a\20\72\65\61\63\68\61\62\69\6c\69\74\79\20\76\65\72\69\66\69\65\64\0a")

  ;; globals from dynrt_lib_modc
  (global $dynrt_lib_modc_global1 (mut i32) (i32.const 0))
  (global $dynrt_lib_modc_global2 (mut i32) (i32.const 0))
  (global $dynrt_lib_modc_global3 i32 (i32.const 4))
  (global $dynrt_lib_modc_global4 i32 (i32.const 16))
  (global $dynrt_lib_modc_global5 i32 (i32.const 512))
  (global $dynrt_lib_modc_global6 (mut i32) (i32.const 0))
  (global $dynrt_lib_modc_global7 (mut i32) (i32.const 0))
  (global $dynrt_lib_modc_global8 (mut i32) (i32.const 0))
  (global $dynrt_lib_modc_global9 (mut i32) (i32.const 0))
  (global $dynrt_lib_modc_global10 (mut i32) (i32.const 0))
  (global $dynrt_lib_modc_global11 (mut i32) (i32.const 0))
  (global $dynrt_lib_modc_global12 (mut i32) (i32.const 0))
  (global $dynrt_lib_modc_global13 (mut i32) (i32.const 512))
  (global $dynrt_lib_modc_global14 (mut i32) (i32.const 8192))
  (global $dynrt_lib_modc_global15 (mut i32) (i32.const 0))
  (global $dynrt_lib_modc_global16 i32 (i32.const 256))
  (global $dynrt_lib_modc_global17 (mut i32) (i32.const 0))
  (global $dynrt_lib_modc_global18 (mut i32) (i32.const 0))
  (global $dynrt_lib_modc_global19 (mut i32) (i32.const 0))
  (global $dynrt_lib_modc_global20 (mut i32) (i32.const -1))
  (global $dynrt_lib_modc_global21 (mut i32) (i32.const 1))
  (global $dynrt_lib_modc_global22 (mut i32) (i32.const 0))
  (global $dynrt_lib_modc_global23 (mut i32) (i32.const 0))
  (global $dynrt_lib_modc_global24 (mut i32) (i32.const 0))
  (global $dynrt_lib_modc_global25 (mut i32) (i32.const 0))
  (global $dynrt_lib_modc_global26 (mut i32) (i32.const 0))
  (global $dynrt_lib_modc_global27 (mut i32) (i32.const 0))
  (global $dynrt_lib_modc_global28 (mut i32) (i32.const 0))
  (global $dynrt_lib_modc_global29 (mut i32) (i32.const 0))
  ;; functions from dynrt_lib_modc
  (func $dynrt_lib_modc_cabi_realloc (param i32 i32 i32 i32) (result i32)
    local.get 3
    call $__malloc
    local.get 0
    local.get 0
    i32.eqz
    select)
  (func $dynrt_lib_modc__fn3 (param i32 i32 i32 i32) (result i32 i32)
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
  (func $dynrt_lib_modc__fn4 (param i32 i32 i32 i32) (result i32 i32)
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
  (func $dynrt_lib_modc__fn5 (param i32 i32 i32) (result i32)
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
  (func $dynrt_lib_modc__fn6 (param i32) (result f64)
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
  (func $dynrt_lib_modc__fn7 (param f64 i32) (result i32)
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
    call $dynrt_lib_modc__fn8
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
          call $dynrt_lib_modc__fn6
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
  (func $dynrt_lib_modc__fn8 (param i64 i32) (result i32)
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
  (func $dynrt_lib_modc__fn9 (param i32 i32) (result f64)
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
    call $dynrt_lib_modc__fn33
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
    call $dynrt_lib_modc__fn33
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
    call $dynrt_lib_modc__fn33
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
    call $dynrt_lib_modc__fn25
    local.set 1
    local.get 1
    i32.const 8
    i32.add
    local.get 0
    f64.store
    call $dynrt_lib_modc__fn33
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
    call $dynrt_lib_modc__fn25
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
            call $dynrt_lib_modc__fn5
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
    call $dynrt_lib_modc__fn33
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
  (func $dynrt_lib_modc__fn15 (result i32)
    (local i32) (local i32)
    i32.const 8
    global.get $dynrt_lib_modc_global3
    i32.const 2
    i32.add
    i32.const 4
    i32.mul
    i32.add
    call $dynrt_lib_modc__fn25
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
    global.get $dynrt_lib_modc_global3
    i32.store
    local.get 0
    local.tee 1
    return)
  (func $dynrt_lib_modc__fn16 (param i32) (result i32)
    (local i32)
    local.get 0
    local.set 1
    local.get 1
    i32.const 8
    i32.add
    i32.load
    return)
  (func $dynrt_lib_modc__fn17 (param i32 i32) (result i32)
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
  (func $dynrt_lib_modc__fn18 (param i32 i32 i32)
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
  (func $dynrt_lib_modc__fn19 (param i32 i32) (result i32)
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
        call $dynrt_lib_modc__fn25
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
  (func $dynrt_lib_modc__fn20 (param i32 i32)
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
        global.get $dynrt_lib_modc_global6
        i32.store
        local.get 0
        global.set $dynrt_lib_modc_global6
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
          global.get $dynrt_lib_modc_global7
          i32.store
          local.get 0
          global.set $dynrt_lib_modc_global7
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
            global.get $dynrt_lib_modc_global8
            i32.store
            local.get 0
            global.set $dynrt_lib_modc_global8
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
              global.get $dynrt_lib_modc_global9
              i32.store
              local.get 0
              global.set $dynrt_lib_modc_global9
            end
          else
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
          end
        end
      end
    end
    global.get $dynrt_lib_modc_global11
    i32.const 1
    i32.add
    global.set $dynrt_lib_modc_global11
    global.get $dynrt_lib_modc_global12
    local.get 1
    local.tee 3
    i32.add
    global.set $dynrt_lib_modc_global12)
  (func $dynrt_lib_modc__fn21 (param i32 i32)
    (local i32)
    local.get 1
    global.get $dynrt_lib_modc_global4
    i32.lt_s
    if (result i32)  ;; label = @1
      global.get $dynrt_lib_modc_global4
    else
      local.get 1
    end
    local.set 2
    local.get 0
    local.get 2
    call $dynrt_lib_modc__fn20
    global.get $dynrt_lib_modc_global11
    global.get $dynrt_lib_modc_global13
    i32.gt_s
    if  ;; label = @1
      call $dynrt_lib_modc__fn30
    end)
  (func $dynrt_lib_modc__fn22 (param i32 i32)
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
  (func $dynrt_lib_modc__fn23 (param i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32)
    i32.const 0
    local.set 1
    local.get 0
    i32.const 16
    i32.eq
    if  ;; label = @1
      global.get $dynrt_lib_modc_global6
      local.set 1
    else
      local.get 0
      i32.const 24
      i32.eq
      if  ;; label = @2
        global.get $dynrt_lib_modc_global7
        local.set 1
      else
        local.get 0
        i32.const 28
        i32.eq
        if  ;; label = @3
          global.get $dynrt_lib_modc_global8
          local.set 1
        else
          local.get 0
          i32.const 32
          i32.eq
          if  ;; label = @4
            global.get $dynrt_lib_modc_global9
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
      global.set $dynrt_lib_modc_global6
    else
      local.get 0
      i32.const 24
      i32.eq
      if  ;; label = @2
        local.get 2
        global.set $dynrt_lib_modc_global7
      else
        local.get 0
        i32.const 28
        i32.eq
        if  ;; label = @3
          local.get 2
          global.set $dynrt_lib_modc_global8
        else
          local.get 2
          global.set $dynrt_lib_modc_global9
        end
      end
    end
    global.get $dynrt_lib_modc_global11
    i32.const 1
    i32.sub
    global.set $dynrt_lib_modc_global11
    global.get $dynrt_lib_modc_global12
    local.get 0
    local.tee 4
    i32.sub
    global.set $dynrt_lib_modc_global12
    local.get 1
    local.get 0
    call $dynrt_lib_modc__fn22
    local.get 1
    local.tee 5
    return)
  (func $dynrt_lib_modc__fn24 (param i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    global.get $dynrt_lib_modc_global10
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
                  global.set $dynrt_lib_modc_global10
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
                global.get $dynrt_lib_modc_global11
                i32.const 1
                i32.sub
                global.set $dynrt_lib_modc_global11
                global.get $dynrt_lib_modc_global12
                local.get 4
                local.tee 6
                i32.sub
                global.set $dynrt_lib_modc_global12
                local.get 4
                local.tee 7
                local.get 0
                local.tee 8
                i32.sub
                local.set 2
                local.get 2
                global.get $dynrt_lib_modc_global4
                i32.ge_s
                if  ;; label = @7
                  local.get 1
                  local.get 0
                  i32.add
                  local.get 2
                  call $dynrt_lib_modc__fn20
                end
                local.get 1
                local.get 0
                call $dynrt_lib_modc__fn22
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
  (func $dynrt_lib_modc__fn25 (param i32) (result i32)
    (local i32) (local i32)
    local.get 0
    global.get $dynrt_lib_modc_global4
    i32.lt_s
    if (result i32)  ;; label = @1
      global.get $dynrt_lib_modc_global4
    else
      local.get 0
    end
    local.set 1
    local.get 1
    call $dynrt_lib_modc__fn23
    local.set 2
    local.get 2
    i32.const 0
    i32.ne
    if  ;; label = @1
      local.get 2
      return
    end
    local.get 1
    call $dynrt_lib_modc__fn24
    local.set 2
    local.get 2
    i32.const 0
    i32.ne
    if  ;; label = @1
      local.get 2
      return
    end
    global.get $dynrt_lib_modc_global12
    local.get 1
    i32.ge_s
    if  ;; label = @1
      block  ;; label = @2
        call $dynrt_lib_modc__fn30
        local.get 1
        call $dynrt_lib_modc__fn23
        local.set 2
        local.get 2
        i32.const 0
        i32.ne
        if  ;; label = @3
          local.get 2
          return
        end
        local.get 1
        call $dynrt_lib_modc__fn24
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
  (func $dynrt_lib_modc__fn26 (param i32) (result i32)
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
  (func $dynrt_lib_modc__fn27 (param i32 i32) (result i32)
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
  (func $dynrt_lib_modc__fn28 (param i32) (result i32)
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
    call $dynrt_lib_modc__fn26
    local.set 1
    local.get 0
    call $dynrt_lib_modc__fn28
    local.set 2
    local.get 1
    call $dynrt_lib_modc__fn28
    local.set 1
    local.get 2
    local.get 1
    call $dynrt_lib_modc__fn27
    return)
  (func $dynrt_lib_modc__fn29 (param i32 i32) (result i32)
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
  (func $dynrt_lib_modc__fn30
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    i32.const 0
    local.tee 7
    local.set 0
    global.get $dynrt_lib_modc_global6
    local.get 0
    call $dynrt_lib_modc__fn29
    local.set 0
    global.get $dynrt_lib_modc_global7
    local.get 0
    call $dynrt_lib_modc__fn29
    local.set 0
    global.get $dynrt_lib_modc_global8
    local.get 0
    call $dynrt_lib_modc__fn29
    local.set 0
    global.get $dynrt_lib_modc_global9
    local.get 0
    call $dynrt_lib_modc__fn29
    local.set 0
    global.get $dynrt_lib_modc_global10
    local.get 0
    call $dynrt_lib_modc__fn29
    local.set 0
    i32.const 0
    local.tee 8
    global.set $dynrt_lib_modc_global6
    i32.const 0
    local.tee 9
    global.set $dynrt_lib_modc_global7
    i32.const 0
    local.tee 10
    global.set $dynrt_lib_modc_global8
    i32.const 0
    local.tee 11
    global.set $dynrt_lib_modc_global9
    i32.const 0
    local.tee 12
    global.set $dynrt_lib_modc_global10
    i32.const 0
    local.tee 13
    global.set $dynrt_lib_modc_global11
    i32.const 0
    local.tee 14
    global.set $dynrt_lib_modc_global12
    local.get 0
    call $dynrt_lib_modc__fn28
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
            call $dynrt_lib_modc__fn20
            local.get 2
            local.set 0
          end
          br 1 (;@2;)
        end
      end
    end
    global.get $dynrt_lib_modc_global11
    i32.const 2
    i32.mul
    local.set 0
    local.get 0
    global.get $dynrt_lib_modc_global5
    i32.lt_s
    if  ;; label = @1
      global.get $dynrt_lib_modc_global5
      local.set 0
    end
    local.get 0
    local.tee 17
    global.set $dynrt_lib_modc_global13)
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
              global.get $dynrt_lib_modc_global6
              local.set 4
            else
              local.get 3
              i32.const 1
              i32.eq
              if  ;; label = @6
                global.get $dynrt_lib_modc_global7
                local.set 4
              else
                local.get 3
                i32.const 2
                i32.eq
                if  ;; label = @7
                  global.get $dynrt_lib_modc_global8
                  local.set 4
                else
                  local.get 3
                  i32.const 3
                  i32.eq
                  if  ;; label = @8
                    global.get $dynrt_lib_modc_global9
                    local.set 4
                  else
                    global.get $dynrt_lib_modc_global10
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
                    global.get $dynrt_lib_modc_global4
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
    global.get $dynrt_lib_modc_global11
    i32.ne
    if  ;; label = @1
      i32.const 2
      return
    end
    local.get 1
    global.get $dynrt_lib_modc_global12
    i32.ne
    if  ;; label = @1
      i32.const 3
      return
    end
    local.get 7
    return)
  (func $dynrt_lib_modc__fn32 (param i32)
    global.get $dynrt_lib_modc_global15
    i32.eqz
    if  ;; label = @1
      call $dynrt_lib_modc__fn15
      global.set $dynrt_lib_modc_global15
    end
    global.get $dynrt_lib_modc_global15
    local.get 0
    call $dynrt_lib_modc__fn19
    global.set $dynrt_lib_modc_global15)
  (func $dynrt_lib_modc__fn33 (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    i32.const 24
    call $dynrt_lib_modc__fn25
    local.set 0
    global.get $dynrt_lib_modc_global15
    i32.eqz
    if  ;; label = @1
      call $dynrt_lib_modc__fn15
      global.set $dynrt_lib_modc_global15
    end
    global.get $dynrt_lib_modc_global15
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
        global.get $dynrt_lib_modc_global15
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
        global.get $dynrt_lib_modc_global15
        local.get 0
        call $dynrt_lib_modc__fn19
        global.set $dynrt_lib_modc_global15
        local.get 2
        local.get 1
        call $dynrt_lib_modc__fn21
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
  (func $dynrt_lib_modc__fn34 (result i32)
    (local i32) (local i32)
    i32.const 28
    call $dynrt_lib_modc__fn25
    local.set 0
    local.get 0
    call $dynrt_lib_modc__fn32
    local.get 0
    local.tee 1
    return)
  (func $dynrt_lib_modc_dynGcCellCount (result i32)
    global.get $dynrt_lib_modc_global15
    i32.eqz
    if  ;; label = @1
      i32.const 0
      return
    end
    global.get $dynrt_lib_modc_global15
    call $dynrt_lib_modc__fn16
    return)
  (func $dynrt_lib_modc__fn36 (param i32) (result i32)
    (local i32)
    local.get 0
    local.set 1
    local.get 1
    i32.const 8
    i32.add
    i32.load
    global.get $dynrt_lib_modc_global16
    i32.and
    i32.eqz
    if (result i32)  ;; label = @1
      i32.const 0
    else
      i32.const 1
    end
    return)
  (func $dynrt_lib_modc__fn37 (param i32)
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
    call $dynrt_lib_modc__fn36
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
    global.get $dynrt_lib_modc_global16
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
        call $dynrt_lib_modc__fn16
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
                call $dynrt_lib_modc__fn17
                call $dynrt_lib_modc__fn37
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
          call $dynrt_lib_modc__fn37
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
            call $dynrt_lib_modc__fn37
            local.get 1
            i32.const 8
            i32.add
            i32.const 12
            i32.add
            i32.load
            call $dynrt_lib_modc__fn37
            local.get 1
            i32.const 8
            i32.add
            i32.const 16
            i32.add
            i32.load
            call $dynrt_lib_modc__fn37
          end
        end
      end
    end)
  (func $dynrt_lib_modc_dynGcMarkClear
    (local i32) (local i32) (local i32) (local i32) (local i32)
    global.get $dynrt_lib_modc_global15
    i32.eqz
    if  ;; label = @1
      return
    end
    global.get $dynrt_lib_modc_global15
    call $dynrt_lib_modc__fn16
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
            global.get $dynrt_lib_modc_global15
            local.get 1
            call $dynrt_lib_modc__fn17
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
    call $dynrt_lib_modc__fn37)
  (func $dynrt_lib_modc_dynGcMarkedCount (result i32)
    (local i32) (local i32) (local i32) (local i32)
    global.get $dynrt_lib_modc_global15
    i32.eqz
    if  ;; label = @1
      i32.const 0
      return
    end
    global.get $dynrt_lib_modc_global15
    call $dynrt_lib_modc__fn16
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
            global.get $dynrt_lib_modc_global15
            local.get 2
            call $dynrt_lib_modc__fn17
            call $dynrt_lib_modc__fn36
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
  (func $dynrt_lib_modc__fn41 (param i32)
    global.get $dynrt_lib_modc_global17
    i32.eqz
    if  ;; label = @1
      call $dynrt_lib_modc__fn15
      global.set $dynrt_lib_modc_global17
    end
    global.get $dynrt_lib_modc_global17
    local.get 0
    call $dynrt_lib_modc__fn19
    global.set $dynrt_lib_modc_global17)
  (func $dynrt_lib_modc__fn42
    (local i32)
    global.get $dynrt_lib_modc_global17
    i32.eqz
    if  ;; label = @1
      return
    end
    global.get $dynrt_lib_modc_global17
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
    call $dynrt_lib_modc__fn41)
  (func $dynrt_lib_modc_dynGcPopRoot
    call $dynrt_lib_modc__fn42)
  (func $dynrt_lib_modc_dynGcRootCount (result i32)
    global.get $dynrt_lib_modc_global17
    i32.eqz
    if  ;; label = @1
      i32.const 0
      return
    end
    global.get $dynrt_lib_modc_global17
    call $dynrt_lib_modc__fn16
    return)
  (func $dynrt_lib_modc_dynGcMarkRoots
    (local i32) (local i32) (local i32) (local i32)
    call $dynrt_lib_modc_dynGcMarkClear
    global.get $dynrt_lib_modc_global20
    call $dynrt_lib_modc__fn37
    global.get $dynrt_lib_modc_global25
    call $dynrt_lib_modc__fn37
    global.get $dynrt_lib_modc_global24
    call $dynrt_lib_modc__fn37
    global.get $dynrt_lib_modc_global17
    i32.eqz
    if  ;; label = @1
      return
    end
    global.get $dynrt_lib_modc_global17
    call $dynrt_lib_modc__fn16
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
            global.get $dynrt_lib_modc_global17
            local.get 1
            call $dynrt_lib_modc__fn17
            call $dynrt_lib_modc__fn37
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
    global.get $dynrt_lib_modc_global18
    i32.const 0
    i32.ne
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_lib_modc_global18
        call $dynrt_lib_modc__fn16
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
                global.get $dynrt_lib_modc_global18
                local.get 1
                call $dynrt_lib_modc__fn17
                call $dynrt_lib_modc__fn37
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
    global.get $dynrt_lib_modc_global18
    i32.eqz
    if  ;; label = @1
      call $dynrt_lib_modc__fn15
      global.set $dynrt_lib_modc_global18
    end
    global.get $dynrt_lib_modc_global18
    call $dynrt_lib_modc__fn16
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
            global.get $dynrt_lib_modc_global18
            local.get 2
            call $dynrt_lib_modc__fn17
            i32.eqz
            if  ;; label = @5
              block  ;; label = @6
                global.get $dynrt_lib_modc_global18
                local.get 2
                local.get 0
                call $dynrt_lib_modc__fn18
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
    global.get $dynrt_lib_modc_global18
    local.get 0
    call $dynrt_lib_modc__fn19
    global.set $dynrt_lib_modc_global18
    local.get 1
    return)
  (func $dynrt_lib_modc_dynGcUnpin (param i32)
    global.get $dynrt_lib_modc_global18
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
      global.get $dynrt_lib_modc_global18
      call $dynrt_lib_modc__fn16
      i32.ge_s
    end
    if  ;; label = @1
      return
    end
    global.get $dynrt_lib_modc_global18
    local.get 0
    i32.const 0
    call $dynrt_lib_modc__fn18)
  (func $dynrt_lib_modc__fn49 (param i32)
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
    call $dynrt_lib_modc__fn21)
  (func $dynrt_lib_modc__fn50 (param i32)
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
      call $dynrt_lib_modc__fn21
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
        call $dynrt_lib_modc__fn21
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
          call $dynrt_lib_modc__fn49
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
              call $dynrt_lib_modc__fn49
              local.get 1
              i32.const 8
              i32.add
              i32.const 12
              i32.add
              i32.load
              local.set 1
              local.get 1
              call $dynrt_lib_modc__fn16
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
                      call $dynrt_lib_modc__fn17
                      i32.const 8
                      local.get 1
                      local.get 3
                      i32.const 1
                      i32.add
                      call $dynrt_lib_modc__fn17
                      i32.add
                      call $dynrt_lib_modc__fn21
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
              call $dynrt_lib_modc__fn49
            end
          end
        end
      end
    end)
  (func $dynrt_lib_modc_dynGcCollect (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    call $dynrt_lib_modc_dynGcMarkRoots
    global.get $dynrt_lib_modc_global15
    i32.eqz
    if  ;; label = @1
      i32.const 0
      return
    end
    global.get $dynrt_lib_modc_global15
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
            global.get $dynrt_lib_modc_global16
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
                call $dynrt_lib_modc__fn50
                local.get 5
                local.get 6
                call $dynrt_lib_modc__fn21
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
    global.get $dynrt_lib_modc_global11
    return)
  (func $dynrt_lib_modc__fn53
    (local i32)
    call $dynrt_lib_modc_dynGcCellCount
    global.get $dynrt_lib_modc_global14
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
        global.set $dynrt_lib_modc_global14
      end
    end)
  (func $dynrt_lib_modc_dynArray (result i32)
    (local i32) (local i32)
    call $dynrt_lib_modc__fn33
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
    call $dynrt_lib_modc__fn15
    i32.store
    local.get 0
    local.tee 1
    return)
  (func $dynrt_lib_modc_dynObject (result i32)
    (local i32) (local i32)
    call $dynrt_lib_modc__fn33
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
    call $dynrt_lib_modc__fn15
    i32.store
    local.get 0
    i32.const 8
    i32.add
    i32.const 12
    i32.add
    call $dynrt_lib_modc__fn15
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
  (func $dynrt_lib_modc__fn65 (param i32)
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
    i32.const 563
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
            call $dynrt_lib_modc__fn3
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
    global.set $dynrt_lib_modc_global1
    local.get 2
    global.set $dynrt_lib_modc_global2
    return)
  (func $dynrt_lib_modc__fn66 (param i32)
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
        call $dynrt_lib_modc__fn65
        global.get $dynrt_lib_modc_global1
        local.set 1
        global.get $dynrt_lib_modc_global2
        local.set 2
        local.get 1
        global.set $dynrt_lib_modc_global1
        local.get 2
        global.set $dynrt_lib_modc_global2
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
        call $dynrt_lib_modc__fn7
        local.set 2
        local.get 1
        local.tee 5
        global.set $dynrt_lib_modc_global1
        local.get 2
        global.set $dynrt_lib_modc_global2
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
            i32.const 563
            local.set 1
            i32.const 5
            local.set 2
          end
        else
          block  ;; label = @4
            i32.const 568
            local.set 1
            i32.const 4
            local.set 2
          end
        end
        local.get 1
        global.set $dynrt_lib_modc_global1
        local.get 2
        global.set $dynrt_lib_modc_global2
        return
      end
    end
    local.get 2
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        i32.const 572
        local.set 1
        i32.const 4
        local.set 2
        local.get 1
        global.set $dynrt_lib_modc_global1
        local.get 2
        global.set $dynrt_lib_modc_global2
        return
      end
    end
    local.get 2
    i32.eqz
    if  ;; label = @1
      block  ;; label = @2
        i32.const 576
        local.set 1
        i32.const 9
        local.set 2
        local.get 1
        global.set $dynrt_lib_modc_global1
        local.get 2
        global.set $dynrt_lib_modc_global2
        return
      end
    end
    i32.const 563
    local.set 1
    i32.const 0
    local.set 2
    local.get 1
    local.tee 6
    global.set $dynrt_lib_modc_global1
    local.get 2
    global.set $dynrt_lib_modc_global2
    return)
  (func $dynrt_lib_modc__fn67 (param i32 i32 i32) (result i32)
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
    call $dynrt_lib_modc__fn16
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
            call $dynrt_lib_modc__fn17
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
                call $dynrt_lib_modc__fn17
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
                      call $dynrt_lib_modc__fn5
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
    call $dynrt_lib_modc__fn67
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
        call $dynrt_lib_modc__fn18
        return
      end
    end
    local.get 2
    local.tee 10
    local.set 5
    i32.const 8
    local.get 5
    i32.add
    call $dynrt_lib_modc__fn25
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
            call $dynrt_lib_modc__fn5
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
    call $dynrt_lib_modc__fn19
    local.set 7
    local.get 7
    local.get 5
    call $dynrt_lib_modc__fn19
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
    call $dynrt_lib_modc__fn19
    i32.store)
  (func $dynrt_lib_modc_dynGet (param i32 i32 i32) (result i32)
    (local i32) (local i32) (local i32)
    local.get 0
    local.tee 5
    local.set 3
    local.get 0
    local.get 1
    local.get 2
    call $dynrt_lib_modc__fn67
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
    call $dynrt_lib_modc__fn17
    return)
  (func $dynrt_lib_modc_dynHas (param i32 i32 i32) (result i32)
    local.get 0
    local.get 1
    local.get 2
    call $dynrt_lib_modc__fn67
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
    call $dynrt_lib_modc__fn16
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
    call $dynrt_lib_modc__fn17
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
    call $dynrt_lib_modc__fn17
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
    call $dynrt_lib_modc__fn17
    return)
  (func $dynrt_lib_modc__fn75 (param i32 i32) (result i32)
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
    call $dynrt_lib_modc__fn17
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
    call $dynrt_lib_modc__fn17
    local.set 2
    local.get 3
    local.tee 7
    local.set 3
    i32.const 8
    local.get 2
    i32.add
    call $dynrt_lib_modc__fn25
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
    call $dynrt_lib_modc__fn33
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
    call $dynrt_lib_modc__fn19
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
    call $dynrt_lib_modc__fn16
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
    call $dynrt_lib_modc__fn17
    return)
  (func $dynrt_lib_modc__fn79 (param i32 i32 i32)
    (local i32) (local i32)
    local.get 0
    local.set 3
    local.get 3
    i32.const 8
    i32.add
    i32.const 4
    i32.add
    i32.load
    call $dynrt_lib_modc__fn16
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
      call $dynrt_lib_modc__fn18
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
        call $dynrt_lib_modc__fn19
        i32.store
      end
    end)
  (func $dynrt_lib_modc__fn80 (param i32 i32 i32)
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
          call $dynrt_lib_modc__fn79
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
            call $dynrt_lib_modc__fn65
            global.get $dynrt_lib_modc_global1
            local.set 3
            global.get $dynrt_lib_modc_global2
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
        call $dynrt_lib_modc__fn66
        global.get $dynrt_lib_modc_global1
        local.tee 8
        local.set 2
        global.get $dynrt_lib_modc_global2
        local.tee 9
        local.set 3
        local.get 1
        call $dynrt_lib_modc__fn66
        global.get $dynrt_lib_modc_global1
        local.tee 10
        local.set 4
        global.get $dynrt_lib_modc_global2
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
        call $dynrt_lib_modc__fn3
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
    call $dynrt_lib_modc__fn33
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
  (func $dynrt_lib_modc__fn94 (param i32 i32 i32) (result i32)
    (local i32) (local i32)
    call $dynrt_lib_modc__fn34
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
    call $dynrt_lib_modc__fn94
    return)
  (func $dynrt_lib_modc_dynMakeHostFn (param i32) (result i32)
    (local i32) (local i32)
    call $dynrt_lib_modc__fn34
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
              call $dynrt_lib_modc__fn5
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
                        call $dynrt_lib_modc__fn5
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
                        call $dynrt_lib_modc__fn5
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
                    call $dynrt_lib_modc__fn4
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
  (func $dynrt_lib_modc__fn98 (param i32 i32 i32) (result i32)
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
  (func $dynrt_lib_modc__fn99 (param i32) (result i32)
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
  (func $dynrt_lib_modc__fn100 (param i32 i32 i32 i32)
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
  (func $dynrt_lib_modc__fn101 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 1
    call $dynrt_lib_modc__fn99
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
    call $dynrt_lib_modc__fn16
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
            call $dynrt_lib_modc__fn17
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
            call $dynrt_lib_modc__fn17
            local.set 8
            local.get 3
            i32.const 8
            i32.add
            i32.const 4
            i32.add
            i32.load
            local.get 6
            call $dynrt_lib_modc__fn17
            local.set 9
            local.get 7
            local.tee 13
            local.set 7
            i32.const 8
            local.get 8
            i32.add
            call $dynrt_lib_modc__fn25
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
            call $dynrt_lib_modc__fn19
            local.set 7
            local.get 7
            local.get 8
            call $dynrt_lib_modc__fn19
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
            call $dynrt_lib_modc__fn19
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
    call $dynrt_lib_modc__fn103
    return)
  (func $dynrt_lib_modc__fn103 (param i32 i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local f64) (local f64) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
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
    if  ;; label = @1
      block  ;; label = @2
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
        call $dynrt_lib_modc_dynObject
        local.set 7
        local.get 7
        local.tee 15
        local.set 8
        local.get 8
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
          local.get 7
          i32.const 585
          i32.const 4
          local.get 2
          call $dynrt_lib_modc_dynSet
        end
        local.get 6
        call $dynrt_lib_modc_dynArrLen
        local.set 3
        i32.const 0
        local.set 8
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 8
              local.get 3
              i32.lt_s
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                local.get 6
                local.get 8
                call $dynrt_lib_modc_dynArrGet
                local.set 9
                local.get 9
                call $dynrt_lib_modc__fn65
                global.get $dynrt_lib_modc_global1
                local.set 9
                global.get $dynrt_lib_modc_global2
                local.set 10
                local.get 8
                local.get 5
                i32.lt_s
                if (result i32)  ;; label = @7
                  local.get 1
                  local.get 8
                  call $dynrt_lib_modc_dynArrGet
                else
                  call $dynrt_lib_modc_dynUndefined
                end
                local.set 11
                local.get 7
                local.get 9
                local.get 10
                local.get 11
                call $dynrt_lib_modc_dynSet
                local.get 8
                local.tee 14
                i32.const 1
                i32.add
                local.set 8
              end
              br 1 (;@4;)
            end
          end
        end
        local.get 4
        call $dynrt_lib_modc__fn65
        global.get $dynrt_lib_modc_global1
        local.set 3
        global.get $dynrt_lib_modc_global2
        local.set 4
        global.get $dynrt_lib_modc_global19
        local.set 5
        global.get $dynrt_lib_modc_global20
        local.set 6
        global.get $dynrt_lib_modc_global21
        local.set 8
        global.get $dynrt_lib_modc_global23
        local.set 9
        global.get $dynrt_lib_modc_global24
        local.set 10
        global.get $dynrt_lib_modc_global25
        local.set 11
        local.get 3
        local.get 4
        local.get 7
        call $dynrt_lib_modc_dynRun
        local.set 3
        local.get 5
        global.set $dynrt_lib_modc_global19
        local.get 6
        local.tee 16
        global.set $dynrt_lib_modc_global20
        local.get 8
        local.tee 17
        global.set $dynrt_lib_modc_global21
        local.get 9
        global.set $dynrt_lib_modc_global23
        local.get 10
        global.set $dynrt_lib_modc_global24
        local.get 11
        global.set $dynrt_lib_modc_global25
        local.get 3
        local.tee 18
        return
      end
    end
    local.get 4
    i32.const 8
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_lib_modc_global22
        local.tee 19
        i32.const 1
        i32.add
        global.set $dynrt_lib_modc_global22
        global.get $dynrt_lib_modc_global22
        local.tee 20
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
            local.tee 21
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
    local.set 12
    local.get 4
    i32.eqz
    if  ;; label = @1
      local.get 12
      f64.abs
      call $dynrt_lib_modc_dynNumber
      return
    end
    local.get 4
    i32.const 1
    i32.eq
    if  ;; label = @1
      local.get 12
      f64.sqrt
      call $dynrt_lib_modc_dynNumber
      return
    end
    local.get 4
    i32.const 2
    i32.eq
    if  ;; label = @1
      local.get 12
      f64.floor
      call $dynrt_lib_modc_dynNumber
      return
    end
    local.get 4
    i32.const 3
    i32.eq
    if  ;; label = @1
      local.get 12
      f64.ceil
      call $dynrt_lib_modc_dynNumber
      return
    end
    local.get 4
    i32.const 4
    i32.eq
    if  ;; label = @1
      local.get 12
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
    local.set 13
    local.get 4
    i32.const 5
    i32.eq
    if  ;; label = @1
      local.get 12
      local.get 13
      f64.lt
      if (result f64)  ;; label = @2
        local.get 12
      else
        local.get 13
      end
      call $dynrt_lib_modc_dynNumber
      return
    end
    local.get 4
    i32.const 6
    i32.eq
    if  ;; label = @1
      local.get 12
      local.get 13
      f64.gt
      if (result f64)  ;; label = @2
        local.get 12
      else
        local.get 13
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
    i32.const 589
    i32.const 3
    i32.const 0
    call $dynrt_lib_modc_dynBuiltin
    call $dynrt_lib_modc_dynSet
    local.get 0
    i32.const 592
    i32.const 4
    i32.const 1
    call $dynrt_lib_modc_dynBuiltin
    call $dynrt_lib_modc_dynSet
    local.get 0
    i32.const 596
    i32.const 5
    i32.const 2
    call $dynrt_lib_modc_dynBuiltin
    call $dynrt_lib_modc_dynSet
    local.get 0
    i32.const 601
    i32.const 4
    i32.const 3
    call $dynrt_lib_modc_dynBuiltin
    call $dynrt_lib_modc_dynSet
    local.get 0
    i32.const 605
    i32.const 5
    i32.const 4
    call $dynrt_lib_modc_dynBuiltin
    call $dynrt_lib_modc_dynSet
    local.get 0
    i32.const 610
    i32.const 3
    i32.const 5
    call $dynrt_lib_modc_dynBuiltin
    call $dynrt_lib_modc_dynSet
    local.get 0
    i32.const 613
    i32.const 3
    i32.const 6
    call $dynrt_lib_modc_dynBuiltin
    call $dynrt_lib_modc_dynSet
    local.get 0
    i32.const 616
    i32.const 3
    i32.const 7
    call $dynrt_lib_modc_dynBuiltin
    call $dynrt_lib_modc_dynSet
    local.get 0
    i32.const 619
    i32.const 3
    i32.const 8
    call $dynrt_lib_modc_dynBuiltin
    call $dynrt_lib_modc_dynSet
    local.get 0
    local.tee 1
    return)
  (func $dynrt_lib_modc_dynSideEffectCount (result i32)
    global.get $dynrt_lib_modc_global22
    return)
  (func $dynrt_lib_modc_dynResetSideEffects
    i32.const 0
    global.set $dynrt_lib_modc_global22)
  (func $dynrt_lib_modc__fn111 (param i32 i32 i32 i32) (result i32)
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
            call $dynrt_lib_modc__fn5
            local.get 2
            local.get 3
            local.get 4
            call $dynrt_lib_modc__fn5
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
    (local i32) (local i32) (local i32)
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
                local.tee 5
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
        i32.const 622
        i32.const 6
        call $dynrt_lib_modc__fn111
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
        i32.const 622
        i32.const 6
        call $dynrt_lib_modc__fn111
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
            call $dynrt_lib_modc__fn65
            global.get $dynrt_lib_modc_global1
            local.set 2
            global.get $dynrt_lib_modc_global2
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
  (func $dynrt_lib_modc__fn114 (param i32 i32) (result i32)
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
  (func $dynrt_lib_modc__fn115 (param i32 i32)
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
          global.get $dynrt_lib_modc_global19
          local.get 1
          i32.ge_s
          if  ;; label = @4
            i32.const 0
            local.set 2
          else
            block  ;; label = @5
              local.get 0
              local.get 1
              global.get $dynrt_lib_modc_global19
              call $dynrt_lib_modc__fn5
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
                global.get $dynrt_lib_modc_global19
                i32.const 1
                i32.add
                global.set $dynrt_lib_modc_global19
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
  (func $dynrt_lib_modc__fn116 (param i32 i32) (result i32)
    (local i32)
    global.get $dynrt_lib_modc_global19
    local.get 1
    i32.ge_s
    if  ;; label = @1
      i32.const -1
      return
    end
    local.get 0
    local.get 1
    global.get $dynrt_lib_modc_global19
    call $dynrt_lib_modc__fn5
    return)
  (func $dynrt_lib_modc__fn117 (param i32 i32) (result i32)
    (local i32)
    global.get $dynrt_lib_modc_global19
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
    global.get $dynrt_lib_modc_global19
    i32.const 1
    i32.add
    call $dynrt_lib_modc__fn5
    return)
  (func $dynrt_lib_modc__fn118 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32)
    global.get $dynrt_lib_modc_global19
    local.tee 4
    local.set 2
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn116
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
            global.get $dynrt_lib_modc_global19
            i32.const 1
            i32.add
            global.set $dynrt_lib_modc_global19
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn116
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
        global.get $dynrt_lib_modc_global19
        i32.const 1
        i32.add
        global.set $dynrt_lib_modc_global19
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn116
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
                global.get $dynrt_lib_modc_global19
                i32.const 1
                i32.add
                global.set $dynrt_lib_modc_global19
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn116
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
        global.get $dynrt_lib_modc_global19
        i32.const 1
        i32.add
        global.set $dynrt_lib_modc_global19
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn116
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
            global.get $dynrt_lib_modc_global19
            i32.const 1
            i32.add
            global.set $dynrt_lib_modc_global19
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn116
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
                global.get $dynrt_lib_modc_global19
                i32.const 1
                i32.add
                global.set $dynrt_lib_modc_global19
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn116
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
    global.get $dynrt_lib_modc_global19
    call $dynrt_lib_modc__fn4
    local.set 3
    nop
    local.set 2
    local.get 2
    local.get 3
    call $dynrt_lib_modc__fn9
    call $dynrt_lib_modc_dynNumber
    return)
  (func $dynrt_lib_modc__fn119 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn116
    local.set 2
    global.get $dynrt_lib_modc_global19
    i32.const 1
    local.tee 16
    i32.add
    global.set $dynrt_lib_modc_global19
    i32.const 563
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
          global.get $dynrt_lib_modc_global19
          local.get 1
          i32.ge_s
          if  ;; label = @4
            i32.const 0
            local.set 5
          else
            block  ;; label = @5
              local.get 0
              local.get 1
              global.get $dynrt_lib_modc_global19
              call $dynrt_lib_modc__fn5
              local.set 6
              local.get 6
              local.get 2
              i32.eq
              if  ;; label = @6
                block  ;; label = @7
                  global.get $dynrt_lib_modc_global19
                  i32.const 1
                  i32.add
                  global.set $dynrt_lib_modc_global19
                  i32.const 0
                  local.set 5
                end
              else
                local.get 6
                i32.const 92
                i32.eq
                if  ;; label = @7
                  block  ;; label = @8
                    global.get $dynrt_lib_modc_global19
                    i32.const 1
                    i32.add
                    local.tee 9
                    global.set $dynrt_lib_modc_global19
                    local.get 0
                    local.get 1
                    global.get $dynrt_lib_modc_global19
                    call $dynrt_lib_modc__fn5
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
                    call $dynrt_lib_modc__fn3
                    local.set 4
                    nop
                    local.set 3
                    global.get $dynrt_lib_modc_global19
                    i32.const 1
                    i32.add
                    local.tee 12
                    global.set $dynrt_lib_modc_global19
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
                    call $dynrt_lib_modc__fn3
                    local.set 4
                    nop
                    local.set 3
                    global.get $dynrt_lib_modc_global19
                    i32.const 1
                    local.tee 15
                    i32.add
                    global.set $dynrt_lib_modc_global19
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
  (func $dynrt_lib_modc__fn120 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn115
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn116
    local.set 2
    local.get 2
    i32.const 40
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn151
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn147
            local.set 2
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn115
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn116
            i32.const 61
            i32.eq
            if (result i32)  ;; label = @5
              local.get 0
              local.get 1
              call $dynrt_lib_modc__fn117
              i32.const 62
              i32.eq
            else
              i32.const 0
            end
            if  ;; label = @5
              global.get $dynrt_lib_modc_global19
              i32.const 2
              i32.add
              global.set $dynrt_lib_modc_global19
            end
            local.get 2
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn149
            global.get $dynrt_lib_modc_global20
            call $dynrt_lib_modc__fn94
            return
          end
        end
        global.get $dynrt_lib_modc_global19
        i32.const 1
        i32.add
        global.set $dynrt_lib_modc_global19
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn130
        local.set 2
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn115
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn116
        i32.const 41
        i32.eq
        if  ;; label = @3
          global.get $dynrt_lib_modc_global19
          i32.const 1
          i32.add
          global.set $dynrt_lib_modc_global19
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
      call $dynrt_lib_modc__fn119
      return
    end
    local.get 2
    i32.const 91
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_lib_modc_global19
        i32.const 1
        i32.add
        global.set $dynrt_lib_modc_global19
        call $dynrt_lib_modc_dynArray
        local.set 2
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn115
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn116
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
                call $dynrt_lib_modc__fn115
                i32.const 0
                local.set 4
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn116
                i32.const 46
                i32.eq
                if (result i32)  ;; label = @7
                  local.get 0
                  local.get 1
                  call $dynrt_lib_modc__fn117
                  i32.const 46
                  i32.eq
                else
                  i32.const 0
                end
                if  ;; label = @7
                  global.get $dynrt_lib_modc_global19
                  i32.const 2
                  i32.add
                  local.get 1
                  i32.lt_s
                  if  ;; label = @8
                    local.get 0
                    local.get 1
                    global.get $dynrt_lib_modc_global19
                    i32.const 2
                    i32.add
                    call $dynrt_lib_modc__fn5
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
                    global.get $dynrt_lib_modc_global19
                    i32.const 3
                    i32.add
                    global.set $dynrt_lib_modc_global19
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn130
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
                                local.tee 7
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
                  call $dynrt_lib_modc__fn130
                  call $dynrt_lib_modc_dynPush
                end
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn115
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn116
                i32.const 44
                i32.eq
                if  ;; label = @7
                  block  ;; label = @8
                    global.get $dynrt_lib_modc_global19
                    i32.const 1
                    i32.add
                    global.set $dynrt_lib_modc_global19
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn115
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn116
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
        call $dynrt_lib_modc__fn115
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn116
        i32.const 93
        i32.eq
        if  ;; label = @3
          global.get $dynrt_lib_modc_global19
          i32.const 1
          i32.add
          global.set $dynrt_lib_modc_global19
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
        global.get $dynrt_lib_modc_global19
        i32.const 1
        i32.add
        global.set $dynrt_lib_modc_global19
        call $dynrt_lib_modc_dynObject
        local.set 2
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn115
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn116
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
                call $dynrt_lib_modc__fn115
                i32.const 0
                local.tee 8
                drop
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn116
                local.set 4
                local.get 4
                i32.const 39
                i32.eq
                if (result i32)  ;; label = @7
                  i32.const 1
                else
                  local.get 4
                  i32.const 34
                  i32.eq
                end
                if  ;; label = @7
                  block  ;; label = @8
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn119
                    call $dynrt_lib_modc__fn65
                    global.get $dynrt_lib_modc_global1
                    local.set 4
                    global.get $dynrt_lib_modc_global2
                    local.set 5
                  end
                else
                  block  ;; label = @8
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn133
                    global.get $dynrt_lib_modc_global1
                    local.set 4
                    global.get $dynrt_lib_modc_global2
                    local.set 5
                  end
                end
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn115
                i32.const 0
                local.tee 9
                drop
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn116
                i32.const 58
                i32.eq
                if  ;; label = @7
                  block  ;; label = @8
                    global.get $dynrt_lib_modc_global19
                    i32.const 1
                    i32.add
                    global.set $dynrt_lib_modc_global19
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn130
                    local.set 6
                  end
                else
                  local.get 0
                  local.get 1
                  call $dynrt_lib_modc__fn116
                  i32.const 40
                  i32.eq
                  if  ;; label = @8
                    block  ;; label = @9
                      local.get 0
                      local.get 1
                      call $dynrt_lib_modc__fn147
                      local.set 6
                      local.get 0
                      local.get 1
                      call $dynrt_lib_modc__fn115
                      local.get 6
                      local.get 0
                      local.get 1
                      call $dynrt_lib_modc__fn148
                      global.get $dynrt_lib_modc_global20
                      call $dynrt_lib_modc__fn94
                      local.set 6
                    end
                  else
                    block  ;; label = @9
                      global.get $dynrt_lib_modc_global20
                      i32.const -1
                      i32.eq
                      if (result i32)  ;; label = @10
                        call $dynrt_lib_modc_dynUndefined
                      else
                        global.get $dynrt_lib_modc_global20
                        local.get 4
                        local.get 5
                        call $dynrt_lib_modc__fn98
                      end
                      local.set 6
                      local.get 6
                      i32.const -1
                      i32.eq
                      if  ;; label = @10
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
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn115
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn116
                i32.const 44
                i32.eq
                if  ;; label = @7
                  block  ;; label = @8
                    global.get $dynrt_lib_modc_global19
                    i32.const 1
                    i32.add
                    global.set $dynrt_lib_modc_global19
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn115
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn116
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
        call $dynrt_lib_modc__fn115
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn116
        i32.const 125
        i32.eq
        if  ;; label = @3
          global.get $dynrt_lib_modc_global19
          i32.const 1
          i32.add
          global.set $dynrt_lib_modc_global19
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
        global.get $dynrt_lib_modc_global19
        local.tee 13
        i32.const 1
        local.tee 14
        i32.add
        global.set $dynrt_lib_modc_global19
        i32.const 563
        i32.const 0
        call $dynrt_lib_modc_dynString
        local.set 2
        global.get $dynrt_lib_modc_global19
        local.tee 15
        local.set 3
        i32.const 1
        local.tee 16
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
                call $dynrt_lib_modc__fn116
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
                      global.get $dynrt_lib_modc_global19
                      call $dynrt_lib_modc__fn4
                      call $dynrt_lib_modc_dynString
                      call $dynrt_lib_modc_dynAdd
                      local.set 2
                      global.get $dynrt_lib_modc_global19
                      local.tee 10
                      i32.const 1
                      i32.add
                      global.set $dynrt_lib_modc_global19
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
                      call $dynrt_lib_modc__fn117
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
                        global.get $dynrt_lib_modc_global19
                        call $dynrt_lib_modc__fn4
                        call $dynrt_lib_modc_dynString
                        call $dynrt_lib_modc_dynAdd
                        local.set 2
                        global.get $dynrt_lib_modc_global19
                        local.tee 11
                        i32.const 2
                        i32.add
                        global.set $dynrt_lib_modc_global19
                        local.get 0
                        local.get 1
                        call $dynrt_lib_modc__fn130
                        local.set 3
                        local.get 2
                        local.get 3
                        call $dynrt_lib_modc_dynAdd
                        local.set 2
                        local.get 0
                        local.get 1
                        call $dynrt_lib_modc__fn115
                        local.get 0
                        local.get 1
                        call $dynrt_lib_modc__fn116
                        i32.const 125
                        i32.eq
                        if  ;; label = @11
                          global.get $dynrt_lib_modc_global19
                          i32.const 1
                          i32.add
                          global.set $dynrt_lib_modc_global19
                        end
                        global.get $dynrt_lib_modc_global19
                        local.tee 12
                        local.set 3
                      end
                    else
                      global.get $dynrt_lib_modc_global19
                      i32.const 1
                      i32.add
                      global.set $dynrt_lib_modc_global19
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
      call $dynrt_lib_modc__fn118
      return
    end
    local.get 2
    i32.const 46
    i32.eq
    if  ;; label = @1
      local.get 0
      local.get 1
      call $dynrt_lib_modc__fn118
      return
    end
    local.get 2
    i32.const 0
    call $dynrt_lib_modc__fn114
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_lib_modc_global19
        local.tee 20
        local.set 3
        local.get 2
        local.set 2
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 2
              i32.const 1
              call $dynrt_lib_modc__fn114
              i32.const 1
              i32.eq
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                global.get $dynrt_lib_modc_global19
                i32.const 1
                i32.add
                global.set $dynrt_lib_modc_global19
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn116
                local.set 2
              end
              br 1 (;@4;)
            end
          end
        end
        local.get 0
        local.get 1
        local.get 3
        global.get $dynrt_lib_modc_global19
        call $dynrt_lib_modc__fn4
        local.set 4
        nop
        local.set 3
        local.get 3
        local.get 4
        i32.const 628
        i32.const 8
        call $dynrt_lib_modc__fn111
        i32.const 1
        i32.eq
        if  ;; label = @3
          local.get 0
          local.get 1
          call $dynrt_lib_modc__fn150
          return
        end
        local.get 3
        local.get 4
        i32.const 568
        i32.const 4
        call $dynrt_lib_modc__fn111
        i32.const 1
        i32.eq
        if  ;; label = @3
          i32.const 1
          call $dynrt_lib_modc_dynBool
          return
        end
        local.get 3
        local.get 4
        i32.const 563
        i32.const 5
        call $dynrt_lib_modc__fn111
        i32.const 1
        i32.eq
        if  ;; label = @3
          i32.const 0
          call $dynrt_lib_modc_dynBool
          return
        end
        local.get 3
        local.get 4
        i32.const 572
        i32.const 4
        call $dynrt_lib_modc__fn111
        i32.const 1
        i32.eq
        if  ;; label = @3
          call $dynrt_lib_modc_dynNull
          return
        end
        local.get 3
        local.get 4
        i32.const 576
        i32.const 9
        call $dynrt_lib_modc__fn111
        i32.const 1
        i32.eq
        if  ;; label = @3
          call $dynrt_lib_modc_dynUndefined
          return
        end
        local.get 3
        local.get 4
        i32.const 636
        i32.const 6
        call $dynrt_lib_modc__fn111
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            global.get $dynrt_lib_modc_global19
            local.set 2
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn115
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn116
            i32.const 46
            i32.eq
            if  ;; label = @5
              block  ;; label = @6
                global.get $dynrt_lib_modc_global19
                i32.const 1
                i32.add
                global.set $dynrt_lib_modc_global19
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn133
                global.get $dynrt_lib_modc_global1
                local.set 5
                global.get $dynrt_lib_modc_global2
                local.set 6
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn115
                local.get 5
                local.get 6
                i32.const 642
                i32.const 6
                call $dynrt_lib_modc__fn111
                i32.const 1
                i32.eq
                if (result i32)  ;; label = @7
                  local.get 0
                  local.get 1
                  call $dynrt_lib_modc__fn116
                  i32.const 40
                  i32.eq
                else
                  i32.const 0
                end
                if  ;; label = @7
                  block  ;; label = @8
                    global.get $dynrt_lib_modc_global19
                    i32.const 1
                    i32.add
                    global.set $dynrt_lib_modc_global19
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn130
                    local.set 2
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn115
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn116
                    i32.const 41
                    i32.eq
                    if  ;; label = @9
                      global.get $dynrt_lib_modc_global19
                      i32.const 1
                      i32.add
                      global.set $dynrt_lib_modc_global19
                    end
                    call $dynrt_lib_modc_dynObject
                    local.set 3
                    local.get 3
                    local.tee 17
                    local.set 4
                    local.get 2
                    local.set 5
                    local.get 5
                    i32.const 8
                    i32.add
                    i32.load
                    i32.const 6
                    i32.eq
                    if  ;; label = @9
                      local.get 4
                      i32.const 8
                      i32.add
                      i32.const 8
                      i32.add
                      local.get 2
                      i32.store
                    end
                    local.get 3
                    local.tee 18
                    return
                  end
                end
              end
            end
            local.get 2
            global.set $dynrt_lib_modc_global19
          end
        end
        local.get 3
        local.get 4
        i32.const 648
        i32.const 3
        call $dynrt_lib_modc__fn111
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn115
            global.get $dynrt_lib_modc_global19
            local.tee 19
            local.set 2
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn116
            local.set 3
            block  ;; label = @5
              loop  ;; label = @6
                block  ;; label = @7
                  local.get 3
                  i32.const 1
                  call $dynrt_lib_modc__fn114
                  i32.const 1
                  i32.eq
                  i32.eqz
                  br_if 2 (;@5;)
                  block  ;; label = @8
                    global.get $dynrt_lib_modc_global19
                    i32.const 1
                    i32.add
                    global.set $dynrt_lib_modc_global19
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn116
                    local.set 3
                  end
                  br 1 (;@6;)
                end
              end
            end
            local.get 0
            local.get 1
            local.get 2
            global.get $dynrt_lib_modc_global19
            call $dynrt_lib_modc__fn4
            local.set 3
            nop
            local.set 2
            global.get $dynrt_lib_modc_global20
            i32.const -1
            i32.eq
            if (result i32)  ;; label = @5
              call $dynrt_lib_modc_dynUndefined
            else
              global.get $dynrt_lib_modc_global20
              local.get 2
              local.get 3
              call $dynrt_lib_modc__fn98
            end
            local.set 2
            local.get 2
            i32.const -1
            i32.eq
            if (result i32)  ;; label = @5
              call $dynrt_lib_modc_dynUndefined
            else
              local.get 2
            end
            local.set 2
            call $dynrt_lib_modc_dynArray
            local.set 3
            local.get 3
            call $dynrt_lib_modc__fn41
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn115
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn116
            i32.const 40
            i32.eq
            if  ;; label = @5
              block  ;; label = @6
                global.get $dynrt_lib_modc_global19
                i32.const 1
                i32.add
                global.set $dynrt_lib_modc_global19
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn115
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn116
                i32.const 41
                i32.eq
                if  ;; label = @7
                  global.get $dynrt_lib_modc_global19
                  i32.const 1
                  i32.add
                  global.set $dynrt_lib_modc_global19
                else
                  block  ;; label = @8
                    i32.const 1
                    local.set 4
                    block  ;; label = @9
                      loop  ;; label = @10
                        block  ;; label = @11
                          local.get 4
                          i32.const 1
                          i32.eq
                          i32.eqz
                          br_if 2 (;@9;)
                          block  ;; label = @12
                            local.get 0
                            local.get 1
                            call $dynrt_lib_modc__fn130
                            local.set 5
                            local.get 3
                            local.get 5
                            call $dynrt_lib_modc_dynPush
                            local.get 0
                            local.get 1
                            call $dynrt_lib_modc__fn115
                            local.get 0
                            local.get 1
                            call $dynrt_lib_modc__fn116
                            local.set 5
                            local.get 5
                            i32.const 44
                            i32.eq
                            if  ;; label = @13
                              global.get $dynrt_lib_modc_global19
                              i32.const 1
                              i32.add
                              global.set $dynrt_lib_modc_global19
                            else
                              block  ;; label = @14
                                local.get 5
                                i32.const 41
                                i32.eq
                                if  ;; label = @15
                                  global.get $dynrt_lib_modc_global19
                                  i32.const 1
                                  i32.add
                                  global.set $dynrt_lib_modc_global19
                                end
                                i32.const 0
                                local.set 4
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
            local.set 4
            global.get $dynrt_lib_modc_global21
            i32.const 1
            i32.eq
            if  ;; label = @5
              local.get 2
              local.get 3
              call $dynrt_lib_modc__fn154
              local.set 4
            end
            call $dynrt_lib_modc__fn42
            local.get 4
            return
          end
        end
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn115
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn116
        i32.const 61
        i32.eq
        if (result i32)  ;; label = @3
          local.get 0
          local.get 1
          call $dynrt_lib_modc__fn117
          i32.const 62
          i32.eq
        else
          i32.const 0
        end
        if  ;; label = @3
          block  ;; label = @4
            global.get $dynrt_lib_modc_global19
            i32.const 2
            i32.add
            global.set $dynrt_lib_modc_global19
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
            call $dynrt_lib_modc__fn149
            global.get $dynrt_lib_modc_global20
            call $dynrt_lib_modc__fn94
            return
          end
        end
        global.get $dynrt_lib_modc_global20
        i32.const -1
        i32.eq
        if  ;; label = @3
          call $dynrt_lib_modc_dynUndefined
          return
        end
        global.get $dynrt_lib_modc_global20
        local.get 3
        local.get 4
        call $dynrt_lib_modc__fn98
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
  (func $dynrt_lib_modc__fn121 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn120
    local.set 2
    i32.const 1
    local.set 3
    i32.const -1
    local.set 4
    i32.const 0
    local.set 5
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
            call $dynrt_lib_modc__fn115
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn116
            local.set 6
            i32.const 0
            local.set 7
            local.get 6
            i32.const 63
            i32.eq
            if (result i32)  ;; label = @5
              local.get 0
              local.get 1
              call $dynrt_lib_modc__fn117
              i32.const 46
              i32.eq
            else
              i32.const 0
            end
            if  ;; label = @5
              block  ;; label = @6
                global.get $dynrt_lib_modc_global19
                i32.const 2
                i32.add
                global.set $dynrt_lib_modc_global19
                local.get 5
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
                      local.set 5
                    end
                  end
                end
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn115
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn116
                local.set 4
                local.get 4
                i32.const 91
                i32.eq
                if  ;; label = @7
                  block  ;; label = @8
                    global.get $dynrt_lib_modc_global19
                    i32.const 1
                    i32.add
                    global.set $dynrt_lib_modc_global19
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn130
                    local.set 7
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn115
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn116
                    i32.const 93
                    i32.eq
                    if  ;; label = @9
                      global.get $dynrt_lib_modc_global19
                      i32.const 1
                      i32.add
                      global.set $dynrt_lib_modc_global19
                    end
                    local.get 2
                    local.set 4
                    local.get 5
                    i32.const 1
                    i32.eq
                    if (result i32)  ;; label = @9
                      call $dynrt_lib_modc_dynUndefined
                    else
                      local.get 2
                      local.get 7
                      call $dynrt_lib_modc_dynIndexValue
                    end
                    local.set 2
                  end
                else
                  block  ;; label = @8
                    global.get $dynrt_lib_modc_global19
                    local.tee 10
                    local.set 4
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn116
                    local.set 7
                    block  ;; label = @9
                      loop  ;; label = @10
                        block  ;; label = @11
                          local.get 7
                          i32.const 1
                          call $dynrt_lib_modc__fn114
                          i32.const 1
                          i32.eq
                          i32.eqz
                          br_if 2 (;@9;)
                          block  ;; label = @12
                            global.get $dynrt_lib_modc_global19
                            i32.const 1
                            i32.add
                            global.set $dynrt_lib_modc_global19
                            local.get 0
                            local.get 1
                            call $dynrt_lib_modc__fn116
                            local.set 7
                          end
                          br 1 (;@10;)
                        end
                      end
                    end
                    local.get 0
                    local.get 1
                    local.get 4
                    global.get $dynrt_lib_modc_global19
                    call $dynrt_lib_modc__fn4
                    local.set 8
                    nop
                    local.set 7
                    local.get 2
                    local.set 4
                    local.get 5
                    i32.const 1
                    i32.eq
                    if (result i32)  ;; label = @9
                      call $dynrt_lib_modc_dynUndefined
                    else
                      local.get 2
                      local.get 7
                      local.get 8
                      call $dynrt_lib_modc_dynMember
                    end
                    local.set 2
                  end
                end
                i32.const 1
                local.set 7
              end
            end
            local.get 7
            i32.const 1
            i32.eq
            if  ;; label = @5
              nop
            else
              local.get 6
              i32.const 46
              i32.eq
              if  ;; label = @6
                block  ;; label = @7
                  global.get $dynrt_lib_modc_global19
                  local.tee 11
                  i32.const 1
                  i32.add
                  global.set $dynrt_lib_modc_global19
                  local.get 0
                  local.get 1
                  call $dynrt_lib_modc__fn115
                  global.get $dynrt_lib_modc_global19
                  local.tee 12
                  local.set 4
                  local.get 0
                  local.get 1
                  call $dynrt_lib_modc__fn116
                  local.set 7
                  block  ;; label = @8
                    loop  ;; label = @9
                      block  ;; label = @10
                        local.get 7
                        i32.const 1
                        call $dynrt_lib_modc__fn114
                        i32.const 1
                        i32.eq
                        i32.eqz
                        br_if 2 (;@8;)
                        block  ;; label = @11
                          global.get $dynrt_lib_modc_global19
                          i32.const 1
                          i32.add
                          global.set $dynrt_lib_modc_global19
                          local.get 0
                          local.get 1
                          call $dynrt_lib_modc__fn116
                          local.set 7
                        end
                        br 1 (;@9;)
                      end
                    end
                  end
                  local.get 0
                  local.get 1
                  local.get 4
                  global.get $dynrt_lib_modc_global19
                  call $dynrt_lib_modc__fn4
                  local.set 8
                  nop
                  local.set 7
                  local.get 2
                  local.set 4
                  local.get 5
                  i32.const 1
                  i32.eq
                  if (result i32)  ;; label = @8
                    call $dynrt_lib_modc_dynUndefined
                  else
                    local.get 2
                    local.get 7
                    local.get 8
                    call $dynrt_lib_modc_dynMember
                  end
                  local.set 2
                end
              else
                local.get 6
                i32.const 91
                i32.eq
                if  ;; label = @7
                  block  ;; label = @8
                    global.get $dynrt_lib_modc_global19
                    i32.const 1
                    i32.add
                    global.set $dynrt_lib_modc_global19
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn130
                    local.set 6
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn115
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn116
                    i32.const 93
                    i32.eq
                    if  ;; label = @9
                      global.get $dynrt_lib_modc_global19
                      i32.const 1
                      i32.add
                      global.set $dynrt_lib_modc_global19
                    end
                    local.get 2
                    local.set 4
                    local.get 5
                    i32.const 1
                    i32.eq
                    if (result i32)  ;; label = @9
                      call $dynrt_lib_modc_dynUndefined
                    else
                      local.get 2
                      local.get 6
                      call $dynrt_lib_modc_dynIndexValue
                    end
                    local.set 2
                  end
                else
                  local.get 6
                  i32.const 40
                  i32.eq
                  if  ;; label = @8
                    block  ;; label = @9
                      global.get $dynrt_lib_modc_global19
                      i32.const 1
                      i32.add
                      global.set $dynrt_lib_modc_global19
                      local.get 2
                      call $dynrt_lib_modc__fn41
                      local.get 4
                      i32.const -1
                      i32.ne
                      if (result i32)  ;; label = @10
                        i32.const 1
                      else
                        i32.const 0
                      end
                      local.set 6
                      local.get 6
                      i32.const 1
                      i32.eq
                      if  ;; label = @10
                        local.get 4
                        call $dynrt_lib_modc__fn41
                      end
                      call $dynrt_lib_modc_dynArray
                      local.set 7
                      local.get 7
                      call $dynrt_lib_modc__fn41
                      local.get 0
                      local.get 1
                      call $dynrt_lib_modc__fn115
                      local.get 0
                      local.get 1
                      call $dynrt_lib_modc__fn116
                      i32.const 41
                      i32.eq
                      if  ;; label = @10
                        global.get $dynrt_lib_modc_global19
                        i32.const 1
                        i32.add
                        global.set $dynrt_lib_modc_global19
                      else
                        block  ;; label = @11
                          i32.const 1
                          local.set 8
                          block  ;; label = @12
                            loop  ;; label = @13
                              block  ;; label = @14
                                local.get 8
                                i32.const 1
                                i32.eq
                                i32.eqz
                                br_if 2 (;@12;)
                                block  ;; label = @15
                                  local.get 0
                                  local.get 1
                                  call $dynrt_lib_modc__fn130
                                  local.set 9
                                  local.get 7
                                  local.get 9
                                  call $dynrt_lib_modc_dynPush
                                  local.get 0
                                  local.get 1
                                  call $dynrt_lib_modc__fn115
                                  local.get 0
                                  local.get 1
                                  call $dynrt_lib_modc__fn116
                                  local.set 9
                                  local.get 9
                                  i32.const 44
                                  i32.eq
                                  if  ;; label = @16
                                    global.get $dynrt_lib_modc_global19
                                    i32.const 1
                                    i32.add
                                    global.set $dynrt_lib_modc_global19
                                  else
                                    block  ;; label = @17
                                      local.get 9
                                      i32.const 41
                                      i32.eq
                                      if  ;; label = @18
                                        global.get $dynrt_lib_modc_global19
                                        i32.const 1
                                        i32.add
                                        global.set $dynrt_lib_modc_global19
                                      end
                                      i32.const 0
                                      local.set 8
                                    end
                                  end
                                end
                                br 1 (;@13;)
                              end
                            end
                          end
                        end
                      end
                      global.get $dynrt_lib_modc_global21
                      i32.const 1
                      i32.eq
                      if (result i32)  ;; label = @10
                        local.get 5
                        i32.eqz
                      else
                        i32.const 0
                      end
                      if  ;; label = @10
                        local.get 6
                        i32.const 1
                        i32.eq
                        if  ;; label = @11
                          local.get 2
                          local.get 7
                          local.get 4
                          call $dynrt_lib_modc__fn103
                          local.set 2
                        else
                          local.get 2
                          local.get 7
                          call $dynrt_lib_modc_dynApply
                          local.set 2
                        end
                      else
                        call $dynrt_lib_modc_dynUndefined
                        local.set 2
                      end
                      call $dynrt_lib_modc__fn42
                      local.get 6
                      i32.const 1
                      i32.eq
                      if  ;; label = @10
                        call $dynrt_lib_modc__fn42
                      end
                      call $dynrt_lib_modc__fn42
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
  (func $dynrt_lib_modc__fn122 (param i32) (result i32)
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
      i32.const 576
      i32.const 9
      call $dynrt_lib_modc_dynString
      return
    end
    local.get 1
    i32.const 2
    i32.eq
    if  ;; label = @1
      i32.const 651
      i32.const 7
      call $dynrt_lib_modc_dynString
      return
    end
    local.get 1
    i32.const 3
    i32.eq
    if  ;; label = @1
      i32.const 658
      i32.const 6
      call $dynrt_lib_modc_dynString
      return
    end
    local.get 1
    i32.const 4
    i32.eq
    if  ;; label = @1
      i32.const 664
      i32.const 6
      call $dynrt_lib_modc_dynString
      return
    end
    local.get 1
    i32.const 7
    i32.eq
    if  ;; label = @1
      i32.const 628
      i32.const 8
      call $dynrt_lib_modc_dynString
      return
    end
    i32.const 670
    i32.const 6
    call $dynrt_lib_modc_dynString
    return)
  (func $dynrt_lib_modc__fn123 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn115
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn116
    local.set 2
    local.get 2
    i32.const 45
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_lib_modc_global19
        i32.const 1
        i32.add
        global.set $dynrt_lib_modc_global19
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn123
        call $dynrt_lib_modc_dynNeg
        return
      end
    end
    local.get 2
    i32.const 33
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_lib_modc_global19
        i32.const 1
        i32.add
        global.set $dynrt_lib_modc_global19
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn123
        call $dynrt_lib_modc_dynNot
        return
      end
    end
    local.get 2
    i32.const 43
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_lib_modc_global19
        i32.const 1
        i32.add
        global.set $dynrt_lib_modc_global19
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn123
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
        global.get $dynrt_lib_modc_global19
        local.set 2
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn133
        global.get $dynrt_lib_modc_global1
        local.set 3
        global.get $dynrt_lib_modc_global2
        local.set 4
        local.get 3
        local.get 4
        i32.const 676
        i32.const 6
        call $dynrt_lib_modc__fn111
        i32.const 1
        i32.eq
        if  ;; label = @3
          local.get 0
          local.get 1
          call $dynrt_lib_modc__fn123
          call $dynrt_lib_modc__fn122
          return
        end
        local.get 2
        global.set $dynrt_lib_modc_global19
      end
    end
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn121
    return)
  (func $dynrt_lib_modc__fn124 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn123
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
            call $dynrt_lib_modc__fn115
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn116
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
                global.get $dynrt_lib_modc_global19
                i32.const 1
                i32.add
                global.set $dynrt_lib_modc_global19
                local.get 2
                call $dynrt_lib_modc__fn41
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn123
                local.set 5
                call $dynrt_lib_modc__fn42
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
  (func $dynrt_lib_modc__fn125 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn124
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
            call $dynrt_lib_modc__fn115
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn116
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
                global.get $dynrt_lib_modc_global19
                i32.const 1
                i32.add
                global.set $dynrt_lib_modc_global19
                local.get 2
                call $dynrt_lib_modc__fn41
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn124
                local.set 5
                call $dynrt_lib_modc__fn42
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
  (func $dynrt_lib_modc__fn126 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn125
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
            call $dynrt_lib_modc__fn115
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn116
            local.set 4
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn117
            local.set 5
            local.get 4
            i32.const 60
            i32.eq
            if (result i32)  ;; label = @5
              i32.const 1
            else
              local.get 4
              i32.const 62
              i32.eq
            end
            if  ;; label = @5
              block  ;; label = @6
                local.get 4
                i32.const 60
                i32.eq
                if (result i32)  ;; label = @7
                  i32.const 1
                else
                  i32.const 0
                end
                local.set 4
                local.get 5
                i32.const 61
                i32.eq
                if (result i32)  ;; label = @7
                  i32.const 1
                else
                  i32.const 0
                end
                local.set 5
                local.get 5
                i32.const 1
                i32.eq
                if (result i32)  ;; label = @7
                  global.get $dynrt_lib_modc_global19
                  i32.const 2
                  i32.add
                else
                  global.get $dynrt_lib_modc_global19
                  i32.const 1
                  i32.add
                end
                global.set $dynrt_lib_modc_global19
                local.get 2
                call $dynrt_lib_modc__fn41
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn125
                local.set 6
                call $dynrt_lib_modc__fn42
                local.get 4
                i32.const 1
                i32.eq
                if  ;; label = @7
                  local.get 5
                  i32.const 1
                  i32.eq
                  if (result i32)  ;; label = @8
                    local.get 2
                    local.get 6
                    call $dynrt_lib_modc_dynLe
                  else
                    local.get 2
                    local.get 6
                    call $dynrt_lib_modc_dynLt
                  end
                  local.set 2
                else
                  local.get 5
                  i32.const 1
                  i32.eq
                  if (result i32)  ;; label = @8
                    local.get 2
                    local.get 6
                    call $dynrt_lib_modc_dynGe
                  else
                    local.get 2
                    local.get 6
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
          br 1 (;@2;)
        end
      end
    end
    local.get 2
    return)
  (func $dynrt_lib_modc__fn127 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn126
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
            call $dynrt_lib_modc__fn115
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn116
            local.set 4
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn117
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
                global.get $dynrt_lib_modc_global19
                i32.const 2
                i32.add
                global.set $dynrt_lib_modc_global19
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn116
                i32.const 61
                i32.eq
                if  ;; label = @7
                  global.get $dynrt_lib_modc_global19
                  i32.const 1
                  i32.add
                  global.set $dynrt_lib_modc_global19
                end
                local.get 2
                call $dynrt_lib_modc__fn41
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn126
                local.set 4
                call $dynrt_lib_modc__fn42
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
                  global.get $dynrt_lib_modc_global19
                  i32.const 2
                  i32.add
                  global.set $dynrt_lib_modc_global19
                  local.get 0
                  local.get 1
                  call $dynrt_lib_modc__fn116
                  i32.const 61
                  i32.eq
                  if  ;; label = @8
                    global.get $dynrt_lib_modc_global19
                    i32.const 1
                    i32.add
                    global.set $dynrt_lib_modc_global19
                  end
                  local.get 2
                  call $dynrt_lib_modc__fn41
                  local.get 0
                  local.get 1
                  call $dynrt_lib_modc__fn126
                  local.set 4
                  call $dynrt_lib_modc__fn42
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
  (func $dynrt_lib_modc__fn128 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn127
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
            call $dynrt_lib_modc__fn115
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn116
            i32.const 38
            i32.eq
            if (result i32)  ;; label = @5
              local.get 0
              local.get 1
              call $dynrt_lib_modc__fn117
              i32.const 38
              i32.eq
            else
              i32.const 0
            end
            if  ;; label = @5
              block  ;; label = @6
                global.get $dynrt_lib_modc_global19
                i32.const 2
                i32.add
                global.set $dynrt_lib_modc_global19
                local.get 2
                call $dynrt_lib_modc_dynToBool
                local.set 4
                global.get $dynrt_lib_modc_global21
                local.set 5
                local.get 4
                i32.eqz
                if  ;; label = @7
                  i32.const 0
                  global.set $dynrt_lib_modc_global21
                end
                local.get 2
                call $dynrt_lib_modc__fn41
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn127
                local.set 6
                call $dynrt_lib_modc__fn42
                local.get 5
                global.set $dynrt_lib_modc_global21
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
  (func $dynrt_lib_modc__fn129 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn128
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
            call $dynrt_lib_modc__fn115
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn116
            i32.const 124
            i32.eq
            if (result i32)  ;; label = @5
              local.get 0
              local.get 1
              call $dynrt_lib_modc__fn117
              i32.const 124
              i32.eq
            else
              i32.const 0
            end
            if  ;; label = @5
              block  ;; label = @6
                global.get $dynrt_lib_modc_global19
                i32.const 2
                i32.add
                global.set $dynrt_lib_modc_global19
                local.get 2
                call $dynrt_lib_modc_dynToBool
                local.set 4
                global.get $dynrt_lib_modc_global21
                local.set 5
                local.get 4
                i32.const 1
                i32.eq
                if  ;; label = @7
                  i32.const 0
                  global.set $dynrt_lib_modc_global21
                end
                local.get 2
                call $dynrt_lib_modc__fn41
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn128
                local.set 6
                call $dynrt_lib_modc__fn42
                local.get 5
                global.set $dynrt_lib_modc_global21
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
              call $dynrt_lib_modc__fn116
              i32.const 63
              i32.eq
              if (result i32)  ;; label = @6
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn117
                i32.const 63
                i32.eq
              else
                i32.const 0
              end
              if  ;; label = @6
                block  ;; label = @7
                  global.get $dynrt_lib_modc_global19
                  i32.const 2
                  i32.add
                  global.set $dynrt_lib_modc_global19
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
                  global.get $dynrt_lib_modc_global21
                  local.set 5
                  local.get 4
                  i32.eqz
                  if  ;; label = @8
                    i32.const 0
                    global.set $dynrt_lib_modc_global21
                  end
                  local.get 2
                  call $dynrt_lib_modc__fn41
                  local.get 0
                  local.get 1
                  call $dynrt_lib_modc__fn128
                  local.set 6
                  call $dynrt_lib_modc__fn42
                  local.get 5
                  global.set $dynrt_lib_modc_global21
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
  (func $dynrt_lib_modc__fn130 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn129
    local.set 2
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn115
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn116
    i32.const 63
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_lib_modc_global19
        i32.const 1
        i32.add
        global.set $dynrt_lib_modc_global19
        local.get 2
        call $dynrt_lib_modc_dynToBool
        local.set 2
        global.get $dynrt_lib_modc_global21
        local.set 3
        local.get 2
        i32.eqz
        if  ;; label = @3
          i32.const 0
          global.set $dynrt_lib_modc_global21
        end
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn130
        local.set 4
        local.get 3
        local.tee 6
        global.set $dynrt_lib_modc_global21
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn115
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn116
        i32.const 58
        i32.eq
        if  ;; label = @3
          global.get $dynrt_lib_modc_global19
          i32.const 1
          i32.add
          global.set $dynrt_lib_modc_global19
        end
        local.get 2
        i32.const 1
        i32.eq
        if  ;; label = @3
          i32.const 0
          global.set $dynrt_lib_modc_global21
        end
        local.get 4
        call $dynrt_lib_modc__fn41
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn130
        local.set 5
        call $dynrt_lib_modc__fn42
        local.get 3
        local.tee 7
        global.set $dynrt_lib_modc_global21
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
    global.set $dynrt_lib_modc_global19
    i32.const -1
    global.set $dynrt_lib_modc_global20
    i32.const 1
    global.set $dynrt_lib_modc_global21
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn130
    return)
  (func $dynrt_lib_modc_dynEvalEnv (param i32 i32 i32) (result i32)
    i32.const 0
    global.set $dynrt_lib_modc_global19
    local.get 2
    global.set $dynrt_lib_modc_global20
    i32.const 1
    global.set $dynrt_lib_modc_global21
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn130
    return)
  (func $dynrt_lib_modc__fn133 (param i32 i32)
    (local i32) (local i32) (local i32) (local i32)
    global.get $dynrt_lib_modc_global19
    local.tee 4
    local.set 2
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn116
    local.set 3
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 3
          i32.const 1
          call $dynrt_lib_modc__fn114
          i32.const 1
          i32.eq
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            global.get $dynrt_lib_modc_global19
            i32.const 1
            i32.add
            global.set $dynrt_lib_modc_global19
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn116
            local.set 3
          end
          br 1 (;@2;)
        end
      end
    end
    local.get 0
    local.get 1
    local.get 2
    global.get $dynrt_lib_modc_global19
    call $dynrt_lib_modc__fn4
    local.set 3
    nop
    local.set 2
    local.get 2
    local.tee 5
    global.set $dynrt_lib_modc_global1
    local.get 3
    global.set $dynrt_lib_modc_global2
    return)
  (func $dynrt_lib_modc__fn134 (param i32 i32)
    (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn115
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn133
    global.get $dynrt_lib_modc_global1
    local.set 2
    global.get $dynrt_lib_modc_global2
    local.set 3
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn115
    call $dynrt_lib_modc_dynUndefined
    local.set 4
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn116
    i32.const 61
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_lib_modc_global19
        i32.const 1
        i32.add
        global.set $dynrt_lib_modc_global19
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn130
        local.set 4
      end
    end
    global.get $dynrt_lib_modc_global21
    i32.const 1
    i32.eq
    if  ;; label = @1
      global.get $dynrt_lib_modc_global20
      local.get 2
      local.get 3
      local.get 4
      call $dynrt_lib_modc_dynSet
    end
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn115
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn116
    i32.const 59
    i32.eq
    if  ;; label = @1
      global.get $dynrt_lib_modc_global19
      i32.const 1
      i32.add
      global.set $dynrt_lib_modc_global19
    end)
  (func $dynrt_lib_modc__fn135 (param i32 i32)
    (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn115
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn116
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
      call $dynrt_lib_modc__fn130
      local.set 3
    end
    global.get $dynrt_lib_modc_global21
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 3
        global.set $dynrt_lib_modc_global24
        i32.const 1
        global.set $dynrt_lib_modc_global23
      end
    end
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn115
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn116
    i32.const 59
    i32.eq
    if  ;; label = @1
      global.get $dynrt_lib_modc_global19
      i32.const 1
      i32.add
      global.set $dynrt_lib_modc_global19
    end)
  (func $dynrt_lib_modc__fn136 (param i32 i32)
    (local i32) (local i32) (local i32) (local i32) (local i32)
    global.get $dynrt_lib_modc_global21
    local.set 2
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn115
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn116
    i32.const 40
    i32.eq
    if  ;; label = @1
      global.get $dynrt_lib_modc_global19
      i32.const 1
      i32.add
      global.set $dynrt_lib_modc_global19
    end
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn130
    local.set 3
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn115
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn116
    i32.const 41
    i32.eq
    if  ;; label = @1
      global.get $dynrt_lib_modc_global19
      i32.const 1
      i32.add
      global.set $dynrt_lib_modc_global19
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
    global.set $dynrt_lib_modc_global21
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn155
    local.get 2
    global.set $dynrt_lib_modc_global21
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn115
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn116
    i32.const 0
    call $dynrt_lib_modc__fn114
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_lib_modc_global19
        local.set 4
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn133
        global.get $dynrt_lib_modc_global1
        local.set 5
        global.get $dynrt_lib_modc_global2
        local.set 6
        local.get 5
        local.get 6
        i32.const 682
        i32.const 4
        call $dynrt_lib_modc__fn111
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
            global.set $dynrt_lib_modc_global21
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn155
            local.get 2
            global.set $dynrt_lib_modc_global21
          end
        else
          local.get 4
          global.set $dynrt_lib_modc_global19
        end
      end
    end)
  (func $dynrt_lib_modc__fn137 (param i32 i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    global.get $dynrt_lib_modc_global21
    local.set 2
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn115
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn116
    i32.const 40
    i32.eq
    if  ;; label = @1
      global.get $dynrt_lib_modc_global19
      i32.const 1
      i32.add
      global.set $dynrt_lib_modc_global19
    end
    global.get $dynrt_lib_modc_global19
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
            global.set $dynrt_lib_modc_global19
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn130
            local.set 6
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn115
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn116
            i32.const 41
            i32.eq
            if  ;; label = @5
              global.get $dynrt_lib_modc_global19
              i32.const 1
              i32.add
              global.set $dynrt_lib_modc_global19
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
                global.set $dynrt_lib_modc_global21
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn155
                local.get 2
                global.set $dynrt_lib_modc_global21
                global.get $dynrt_lib_modc_global23
                i32.const 1
                i32.eq
                if (result i32)  ;; label = @7
                  i32.const 1
                else
                  global.get $dynrt_lib_modc_global28
                  i32.const 1
                  i32.eq
                end
                if  ;; label = @7
                  i32.const 0
                  local.set 4
                else
                  global.get $dynrt_lib_modc_global26
                  i32.const 1
                  i32.eq
                  if  ;; label = @8
                    block  ;; label = @9
                      i32.const 0
                      local.tee 7
                      global.set $dynrt_lib_modc_global26
                      i32.const 0
                      local.tee 8
                      local.set 4
                    end
                  else
                    global.get $dynrt_lib_modc_global27
                    i32.const 1
                    i32.eq
                    if  ;; label = @9
                      i32.const 0
                      global.set $dynrt_lib_modc_global27
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
                global.set $dynrt_lib_modc_global21
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn155
                local.get 2
                global.set $dynrt_lib_modc_global21
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
  (func $dynrt_lib_modc__fn138 (param i32 i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    global.get $dynrt_lib_modc_global21
    local.set 2
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn115
    global.get $dynrt_lib_modc_global19
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
            global.set $dynrt_lib_modc_global19
            local.get 2
            local.tee 8
            global.set $dynrt_lib_modc_global21
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn155
            local.get 2
            local.tee 9
            global.set $dynrt_lib_modc_global21
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn115
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn116
            i32.const 0
            call $dynrt_lib_modc__fn114
            i32.const 1
            i32.eq
            if  ;; label = @5
              local.get 0
              local.get 1
              call $dynrt_lib_modc__fn133
            end
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn115
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn116
            i32.const 40
            i32.eq
            if  ;; label = @5
              global.get $dynrt_lib_modc_global19
              i32.const 1
              i32.add
              global.set $dynrt_lib_modc_global19
            end
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn130
            local.set 4
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn115
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn116
            i32.const 41
            i32.eq
            if  ;; label = @5
              global.get $dynrt_lib_modc_global19
              i32.const 1
              i32.add
              global.set $dynrt_lib_modc_global19
            end
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn115
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn116
            i32.const 59
            i32.eq
            if  ;; label = @5
              global.get $dynrt_lib_modc_global19
              i32.const 1
              i32.add
              global.set $dynrt_lib_modc_global19
            end
            local.get 2
            i32.eqz
            if  ;; label = @5
              i32.const 0
              local.set 4
            else
              global.get $dynrt_lib_modc_global23
              i32.const 1
              i32.eq
              if (result i32)  ;; label = @6
                i32.const 1
              else
                global.get $dynrt_lib_modc_global28
                i32.const 1
                i32.eq
              end
              if  ;; label = @6
                i32.const 0
                local.set 4
              else
                global.get $dynrt_lib_modc_global26
                i32.const 1
                i32.eq
                if  ;; label = @7
                  block  ;; label = @8
                    i32.const 0
                    local.tee 6
                    global.set $dynrt_lib_modc_global26
                    i32.const 0
                    local.tee 7
                    local.set 4
                  end
                else
                  block  ;; label = @8
                    global.get $dynrt_lib_modc_global27
                    i32.const 1
                    i32.eq
                    if  ;; label = @9
                      i32.const 0
                      global.set $dynrt_lib_modc_global27
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
  (func $dynrt_lib_modc__fn139 (param i32 i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    global.get $dynrt_lib_modc_global21
    local.set 2
    global.get $dynrt_lib_modc_global20
    local.set 3
    local.get 3
    call $dynrt_lib_modc__fn99
    local.set 4
    local.get 4
    local.tee 13
    global.set $dynrt_lib_modc_global20
    local.get 4
    call $dynrt_lib_modc__fn41
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn115
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn116
    i32.const 40
    i32.eq
    if  ;; label = @1
      global.get $dynrt_lib_modc_global19
      i32.const 1
      i32.add
      global.set $dynrt_lib_modc_global19
    end
    global.get $dynrt_lib_modc_global19
    local.set 4
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn115
    i32.const 0
    local.tee 14
    local.set 5
    i32.const 563
    local.set 6
    local.get 14
    local.set 7
    local.get 14
    local.set 8
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn116
    i32.const 0
    call $dynrt_lib_modc__fn114
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn133
        global.get $dynrt_lib_modc_global1
        local.set 9
        global.get $dynrt_lib_modc_global2
        local.set 10
        local.get 9
        local.set 11
        local.get 10
        local.set 12
        local.get 9
        local.get 10
        i32.const 686
        i32.const 5
        call $dynrt_lib_modc__fn111
        i32.const 1
        i32.eq
        if (result i32)  ;; label = @3
          i32.const 1
        else
          local.get 9
          local.get 10
          i32.const 691
          i32.const 3
          call $dynrt_lib_modc__fn111
          i32.const 1
          i32.eq
        end
        if (result i32)  ;; label = @3
          i32.const 1
        else
          local.get 9
          local.get 10
          i32.const 694
          i32.const 3
          call $dynrt_lib_modc__fn111
          i32.const 1
          i32.eq
        end
        if  ;; label = @3
          block  ;; label = @4
            local.get 9
            local.get 10
            i32.const 694
            i32.const 3
            call $dynrt_lib_modc__fn111
            i32.const 1
            i32.ne
            if  ;; label = @5
              i32.const 1
              local.set 8
            end
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn115
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn133
            global.get $dynrt_lib_modc_global1
            local.set 11
            global.get $dynrt_lib_modc_global2
            local.set 12
          end
        end
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn115
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn116
        i32.const 0
        call $dynrt_lib_modc__fn114
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn133
            global.get $dynrt_lib_modc_global1
            local.set 9
            global.get $dynrt_lib_modc_global2
            local.set 10
            local.get 9
            local.get 10
            i32.const 697
            i32.const 2
            call $dynrt_lib_modc__fn111
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
              i32.const 699
              i32.const 2
              call $dynrt_lib_modc__fn111
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
      call $dynrt_lib_modc__fn141
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
        call $dynrt_lib_modc__fn140
      else
        block  ;; label = @3
          local.get 4
          global.set $dynrt_lib_modc_global19
          local.get 0
          local.get 1
          local.get 2
          local.get 8
          call $dynrt_lib_modc__fn142
        end
      end
    end
    call $dynrt_lib_modc__fn42
    local.get 3
    local.tee 15
    global.set $dynrt_lib_modc_global20)
  (func $dynrt_lib_modc__fn140 (param i32 i32 i32 i32 i32 i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    global.get $dynrt_lib_modc_global20
    local.set 6
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn130
    local.set 7
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn115
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn116
    i32.const 41
    i32.eq
    if  ;; label = @1
      global.get $dynrt_lib_modc_global19
      i32.const 1
      i32.add
      global.set $dynrt_lib_modc_global19
    end
    global.get $dynrt_lib_modc_global19
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
        global.set $dynrt_lib_modc_global21
        local.get 8
        global.set $dynrt_lib_modc_global19
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn155
        local.get 4
        global.set $dynrt_lib_modc_global21
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
              call $dynrt_lib_modc__fn99
              local.set 12
            end
            local.get 12
            local.get 2
            local.get 3
            local.get 7
            local.get 11
            call $dynrt_lib_modc__fn75
            call $dynrt_lib_modc_dynSet
            local.get 12
            local.tee 16
            global.set $dynrt_lib_modc_global20
            local.get 8
            global.set $dynrt_lib_modc_global19
            i32.const 1
            global.set $dynrt_lib_modc_global21
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn155
            local.get 4
            global.set $dynrt_lib_modc_global21
            local.get 6
            local.tee 17
            global.set $dynrt_lib_modc_global20
            global.get $dynrt_lib_modc_global23
            i32.const 1
            i32.eq
            if (result i32)  ;; label = @5
              i32.const 1
            else
              global.get $dynrt_lib_modc_global28
              i32.const 1
              i32.eq
            end
            if  ;; label = @5
              i32.const 0
              local.set 10
            else
              global.get $dynrt_lib_modc_global26
              i32.const 1
              i32.eq
              if  ;; label = @6
                block  ;; label = @7
                  i32.const 0
                  local.tee 13
                  global.set $dynrt_lib_modc_global26
                  i32.const 0
                  local.tee 14
                  local.set 10
                end
              else
                block  ;; label = @7
                  global.get $dynrt_lib_modc_global27
                  i32.const 1
                  i32.eq
                  if  ;; label = @8
                    i32.const 0
                    global.set $dynrt_lib_modc_global27
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
  (func $dynrt_lib_modc__fn141 (param i32 i32 i32 i32 i32 i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    global.get $dynrt_lib_modc_global20
    local.set 6
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn130
    local.set 7
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn115
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn116
    i32.const 41
    i32.eq
    if  ;; label = @1
      global.get $dynrt_lib_modc_global19
      i32.const 1
      i32.add
      global.set $dynrt_lib_modc_global19
    end
    global.get $dynrt_lib_modc_global19
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
        global.set $dynrt_lib_modc_global21
        local.get 8
        global.set $dynrt_lib_modc_global19
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn155
        local.get 4
        global.set $dynrt_lib_modc_global21
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
              call $dynrt_lib_modc__fn99
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
            global.set $dynrt_lib_modc_global20
            local.get 8
            global.set $dynrt_lib_modc_global19
            i32.const 1
            global.set $dynrt_lib_modc_global21
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn155
            local.get 4
            global.set $dynrt_lib_modc_global21
            local.get 6
            local.tee 17
            global.set $dynrt_lib_modc_global20
            global.get $dynrt_lib_modc_global23
            i32.const 1
            i32.eq
            if (result i32)  ;; label = @5
              i32.const 1
            else
              global.get $dynrt_lib_modc_global28
              i32.const 1
              i32.eq
            end
            if  ;; label = @5
              i32.const 0
              local.set 10
            else
              global.get $dynrt_lib_modc_global26
              i32.const 1
              i32.eq
              if  ;; label = @6
                block  ;; label = @7
                  i32.const 0
                  local.tee 13
                  global.set $dynrt_lib_modc_global26
                  i32.const 0
                  local.tee 14
                  local.set 10
                end
              else
                block  ;; label = @7
                  global.get $dynrt_lib_modc_global27
                  i32.const 1
                  i32.eq
                  if  ;; label = @8
                    i32.const 0
                    global.set $dynrt_lib_modc_global27
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
  (func $dynrt_lib_modc__fn142 (param i32 i32 i32 i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    global.get $dynrt_lib_modc_global20
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
    global.set $dynrt_lib_modc_global21
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn155
    global.get $dynrt_lib_modc_global19
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
      call $dynrt_lib_modc__fn101
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
            global.set $dynrt_lib_modc_global20
            local.get 6
            global.set $dynrt_lib_modc_global19
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn115
            i32.const 1
            local.set 10
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn116
            i32.const 59
            i32.ne
            if  ;; label = @5
              local.get 0
              local.get 1
              call $dynrt_lib_modc__fn130
              call $dynrt_lib_modc_dynToBool
              local.set 10
            end
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn115
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn116
            i32.const 59
            i32.eq
            if  ;; label = @5
              global.get $dynrt_lib_modc_global19
              i32.const 1
              i32.add
              global.set $dynrt_lib_modc_global19
            end
            global.get $dynrt_lib_modc_global19
            local.tee 23
            local.set 11
            i32.const 0
            global.set $dynrt_lib_modc_global21
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn116
            i32.const 41
            i32.ne
            if  ;; label = @5
              local.get 0
              local.get 1
              call $dynrt_lib_modc__fn155
            end
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn115
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn116
            i32.const 41
            i32.eq
            if  ;; label = @5
              global.get $dynrt_lib_modc_global19
              i32.const 1
              i32.add
              global.set $dynrt_lib_modc_global19
            end
            global.get $dynrt_lib_modc_global19
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
                global.set $dynrt_lib_modc_global20
                local.get 12
                global.set $dynrt_lib_modc_global19
                i32.const 1
                local.tee 19
                global.set $dynrt_lib_modc_global21
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn155
                local.get 2
                global.set $dynrt_lib_modc_global21
                global.get $dynrt_lib_modc_global23
                i32.const 1
                i32.eq
                if (result i32)  ;; label = @7
                  i32.const 1
                else
                  global.get $dynrt_lib_modc_global28
                  i32.const 1
                  i32.eq
                end
                if  ;; label = @7
                  i32.const 0
                  local.set 8
                else
                  global.get $dynrt_lib_modc_global26
                  i32.const 1
                  i32.eq
                  if  ;; label = @8
                    block  ;; label = @9
                      i32.const 0
                      local.tee 13
                      global.set $dynrt_lib_modc_global26
                      i32.const 0
                      local.tee 14
                      local.set 8
                    end
                  else
                    block  ;; label = @9
                      global.get $dynrt_lib_modc_global27
                      i32.const 1
                      i32.eq
                      if  ;; label = @10
                        i32.const 0
                        global.set $dynrt_lib_modc_global27
                      end
                      local.get 7
                      local.set 10
                      local.get 3
                      i32.const 1
                      i32.eq
                      if  ;; label = @10
                        local.get 7
                        local.get 5
                        call $dynrt_lib_modc__fn101
                        local.set 10
                      end
                      local.get 10
                      local.tee 15
                      global.set $dynrt_lib_modc_global20
                      local.get 11
                      global.set $dynrt_lib_modc_global19
                      local.get 2
                      local.tee 16
                      global.set $dynrt_lib_modc_global21
                      local.get 0
                      local.get 1
                      call $dynrt_lib_modc__fn116
                      i32.const 41
                      i32.ne
                      if  ;; label = @10
                        local.get 0
                        local.get 1
                        call $dynrt_lib_modc__fn155
                      end
                      local.get 2
                      local.tee 17
                      global.set $dynrt_lib_modc_global21
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
                global.set $dynrt_lib_modc_global20
                local.get 12
                global.set $dynrt_lib_modc_global19
                i32.const 0
                local.tee 21
                global.set $dynrt_lib_modc_global21
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn155
                local.get 2
                global.set $dynrt_lib_modc_global21
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
    global.set $dynrt_lib_modc_global20)
  (func $dynrt_lib_modc__fn143 (param i32 i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    global.get $dynrt_lib_modc_global21
    local.set 2
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn115
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn116
    i32.const 40
    i32.eq
    if  ;; label = @1
      global.get $dynrt_lib_modc_global19
      i32.const 1
      i32.add
      global.set $dynrt_lib_modc_global19
    end
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn130
    local.set 3
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn115
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn116
    i32.const 41
    i32.eq
    if  ;; label = @1
      global.get $dynrt_lib_modc_global19
      i32.const 1
      i32.add
      global.set $dynrt_lib_modc_global19
    end
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn115
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn116
    i32.const 123
    i32.eq
    if  ;; label = @1
      global.get $dynrt_lib_modc_global19
      i32.const 1
      i32.add
      global.set $dynrt_lib_modc_global19
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
            call $dynrt_lib_modc__fn115
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn116
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
              call $dynrt_lib_modc__fn114
              i32.const 1
              i32.eq
              if  ;; label = @6
                block  ;; label = @7
                  global.get $dynrt_lib_modc_global19
                  local.set 7
                  local.get 0
                  local.get 1
                  call $dynrt_lib_modc__fn133
                  global.get $dynrt_lib_modc_global1
                  local.set 8
                  global.get $dynrt_lib_modc_global2
                  local.set 9
                  local.get 8
                  local.get 9
                  i32.const 701
                  i32.const 4
                  call $dynrt_lib_modc__fn111
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
                          call $dynrt_lib_modc__fn130
                          local.set 7
                          local.get 0
                          local.get 1
                          call $dynrt_lib_modc__fn115
                          local.get 0
                          local.get 1
                          call $dynrt_lib_modc__fn116
                          i32.const 58
                          i32.eq
                          if  ;; label = @12
                            global.get $dynrt_lib_modc_global19
                            i32.const 1
                            i32.add
                            global.set $dynrt_lib_modc_global19
                          end
                          local.get 3
                          local.get 7
                          call $dynrt_lib_modc_dynStrictEq
                          i32.const 1
                          i32.eq
                          if  ;; label = @12
                            global.get $dynrt_lib_modc_global19
                            local.set 4
                          end
                        end
                      else
                        block  ;; label = @11
                          global.get $dynrt_lib_modc_global21
                          local.set 7
                          i32.const 0
                          global.set $dynrt_lib_modc_global21
                          local.get 0
                          local.get 1
                          call $dynrt_lib_modc__fn130
                          drop
                          local.get 7
                          global.set $dynrt_lib_modc_global21
                          local.get 0
                          local.get 1
                          call $dynrt_lib_modc__fn115
                          local.get 0
                          local.get 1
                          call $dynrt_lib_modc__fn116
                          i32.const 58
                          i32.eq
                          if  ;; label = @12
                            global.get $dynrt_lib_modc_global19
                            i32.const 1
                            i32.add
                            global.set $dynrt_lib_modc_global19
                          end
                        end
                      end
                      local.get 0
                      local.get 1
                      call $dynrt_lib_modc__fn144
                    end
                  else
                    local.get 8
                    local.get 9
                    i32.const 705
                    i32.const 7
                    call $dynrt_lib_modc__fn111
                    i32.const 1
                    i32.eq
                    if  ;; label = @9
                      block  ;; label = @10
                        local.get 0
                        local.get 1
                        call $dynrt_lib_modc__fn115
                        local.get 0
                        local.get 1
                        call $dynrt_lib_modc__fn116
                        i32.const 58
                        i32.eq
                        if  ;; label = @11
                          global.get $dynrt_lib_modc_global19
                          i32.const 1
                          i32.add
                          global.set $dynrt_lib_modc_global19
                        end
                        global.get $dynrt_lib_modc_global19
                        local.set 5
                        local.get 0
                        local.get 1
                        call $dynrt_lib_modc__fn144
                      end
                    else
                      block  ;; label = @10
                        local.get 7
                        global.set $dynrt_lib_modc_global19
                        local.get 0
                        local.get 1
                        call $dynrt_lib_modc__fn144
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
    global.get $dynrt_lib_modc_global19
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
        global.set $dynrt_lib_modc_global19
        i32.const 1
        global.set $dynrt_lib_modc_global21
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn145
        local.get 2
        global.set $dynrt_lib_modc_global21
      end
    end
    local.get 3
    global.set $dynrt_lib_modc_global19
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn115
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn116
    i32.const 125
    i32.eq
    if  ;; label = @1
      global.get $dynrt_lib_modc_global19
      i32.const 1
      i32.add
      global.set $dynrt_lib_modc_global19
    end
    global.get $dynrt_lib_modc_global26
    i32.const 1
    i32.eq
    if  ;; label = @1
      i32.const 0
      global.set $dynrt_lib_modc_global26
    end)
  (func $dynrt_lib_modc__fn144 (param i32 i32)
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
            call $dynrt_lib_modc__fn115
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn116
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
              call $dynrt_lib_modc__fn114
              i32.const 1
              i32.eq
              if  ;; label = @6
                block  ;; label = @7
                  global.get $dynrt_lib_modc_global19
                  local.set 3
                  local.get 0
                  local.get 1
                  call $dynrt_lib_modc__fn133
                  global.get $dynrt_lib_modc_global1
                  local.set 4
                  global.get $dynrt_lib_modc_global2
                  local.set 5
                  local.get 4
                  local.get 5
                  i32.const 701
                  i32.const 4
                  call $dynrt_lib_modc__fn111
                  i32.const 1
                  i32.eq
                  if (result i32)  ;; label = @8
                    i32.const 1
                  else
                    local.get 4
                    local.get 5
                    i32.const 705
                    i32.const 7
                    call $dynrt_lib_modc__fn111
                    i32.const 1
                    i32.eq
                  end
                  if  ;; label = @8
                    block  ;; label = @9
                      local.get 3
                      global.set $dynrt_lib_modc_global19
                      i32.const 0
                      local.set 2
                    end
                  else
                    block  ;; label = @9
                      local.get 3
                      local.tee 6
                      global.set $dynrt_lib_modc_global19
                      global.get $dynrt_lib_modc_global21
                      local.set 3
                      i32.const 0
                      global.set $dynrt_lib_modc_global21
                      local.get 0
                      local.get 1
                      call $dynrt_lib_modc__fn155
                      local.get 3
                      local.tee 7
                      global.set $dynrt_lib_modc_global21
                    end
                  end
                end
              else
                block  ;; label = @7
                  global.get $dynrt_lib_modc_global21
                  local.set 3
                  i32.const 0
                  global.set $dynrt_lib_modc_global21
                  local.get 0
                  local.get 1
                  call $dynrt_lib_modc__fn155
                  local.get 3
                  global.set $dynrt_lib_modc_global21
                end
              end
            end
          end
          br 1 (;@2;)
        end
      end
    end)
  (func $dynrt_lib_modc__fn145 (param i32 i32)
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
            call $dynrt_lib_modc__fn115
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn116
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
              call $dynrt_lib_modc__fn114
              i32.const 1
              i32.eq
              if  ;; label = @6
                block  ;; label = @7
                  global.get $dynrt_lib_modc_global19
                  local.set 3
                  local.get 0
                  local.get 1
                  call $dynrt_lib_modc__fn133
                  global.get $dynrt_lib_modc_global1
                  local.set 4
                  global.get $dynrt_lib_modc_global2
                  local.set 5
                  local.get 4
                  local.get 5
                  i32.const 701
                  i32.const 4
                  call $dynrt_lib_modc__fn111
                  i32.const 1
                  i32.eq
                  if  ;; label = @8
                    block  ;; label = @9
                      global.get $dynrt_lib_modc_global21
                      local.set 3
                      i32.const 0
                      global.set $dynrt_lib_modc_global21
                      local.get 0
                      local.get 1
                      call $dynrt_lib_modc__fn130
                      drop
                      local.get 3
                      global.set $dynrt_lib_modc_global21
                      local.get 0
                      local.get 1
                      call $dynrt_lib_modc__fn115
                      local.get 0
                      local.get 1
                      call $dynrt_lib_modc__fn116
                      i32.const 58
                      i32.eq
                      if  ;; label = @10
                        global.get $dynrt_lib_modc_global19
                        i32.const 1
                        i32.add
                        global.set $dynrt_lib_modc_global19
                      end
                    end
                  else
                    local.get 4
                    local.get 5
                    i32.const 705
                    i32.const 7
                    call $dynrt_lib_modc__fn111
                    i32.const 1
                    i32.eq
                    if  ;; label = @9
                      block  ;; label = @10
                        local.get 0
                        local.get 1
                        call $dynrt_lib_modc__fn115
                        local.get 0
                        local.get 1
                        call $dynrt_lib_modc__fn116
                        i32.const 58
                        i32.eq
                        if  ;; label = @11
                          global.get $dynrt_lib_modc_global19
                          i32.const 1
                          i32.add
                          global.set $dynrt_lib_modc_global19
                        end
                      end
                    else
                      block  ;; label = @10
                        local.get 3
                        global.set $dynrt_lib_modc_global19
                        local.get 0
                        local.get 1
                        call $dynrt_lib_modc__fn155
                      end
                    end
                  end
                end
              else
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn155
              end
            end
            global.get $dynrt_lib_modc_global26
            i32.const 1
            i32.eq
            if  ;; label = @5
              i32.const 0
              local.set 2
            end
            global.get $dynrt_lib_modc_global23
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
            global.get $dynrt_lib_modc_global27
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
  (func $dynrt_lib_modc__fn146 (param i32 i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    global.get $dynrt_lib_modc_global21
    local.set 2
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn115
    local.get 2
    local.tee 17
    global.set $dynrt_lib_modc_global21
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn155
    local.get 2
    local.tee 18
    global.set $dynrt_lib_modc_global21
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn115
    i32.const 0
    local.tee 19
    local.set 3
    global.get $dynrt_lib_modc_global19
    local.tee 20
    local.set 4
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn116
    i32.const 0
    call $dynrt_lib_modc__fn114
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn133
        global.get $dynrt_lib_modc_global1
        local.set 5
        global.get $dynrt_lib_modc_global2
        local.set 6
        local.get 5
        local.get 6
        i32.const 712
        i32.const 5
        call $dynrt_lib_modc__fn111
        i32.const 1
        i32.eq
        if  ;; label = @3
          i32.const 1
          local.set 3
        else
          local.get 4
          global.set $dynrt_lib_modc_global19
        end
      end
    end
    local.get 3
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        i32.const 563
        local.set 3
        i32.const 0
        local.set 4
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn115
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn116
        i32.const 40
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            global.get $dynrt_lib_modc_global19
            i32.const 1
            i32.add
            global.set $dynrt_lib_modc_global19
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn115
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn133
            global.get $dynrt_lib_modc_global1
            local.set 3
            global.get $dynrt_lib_modc_global2
            local.set 4
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn115
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn116
            i32.const 41
            i32.eq
            if  ;; label = @5
              global.get $dynrt_lib_modc_global19
              i32.const 1
              i32.add
              global.set $dynrt_lib_modc_global19
            end
          end
        end
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn115
        global.get $dynrt_lib_modc_global28
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
            global.get $dynrt_lib_modc_global29
            local.set 5
            i32.const 0
            global.set $dynrt_lib_modc_global28
            global.get $dynrt_lib_modc_global20
            local.set 6
            local.get 6
            call $dynrt_lib_modc__fn99
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
            global.set $dynrt_lib_modc_global20
            local.get 7
            call $dynrt_lib_modc__fn41
            i32.const 1
            global.set $dynrt_lib_modc_global21
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn155
            call $dynrt_lib_modc__fn42
            local.get 6
            local.tee 10
            global.set $dynrt_lib_modc_global20
            local.get 2
            global.set $dynrt_lib_modc_global21
          end
        else
          block  ;; label = @4
            i32.const 0
            global.set $dynrt_lib_modc_global21
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn155
            local.get 2
            global.set $dynrt_lib_modc_global21
          end
        end
      end
    end
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn115
    i32.const 0
    local.tee 21
    local.set 3
    global.get $dynrt_lib_modc_global19
    local.tee 22
    local.set 4
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn116
    i32.const 0
    call $dynrt_lib_modc__fn114
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn133
        global.get $dynrt_lib_modc_global1
        local.set 5
        global.get $dynrt_lib_modc_global2
        local.set 6
        local.get 5
        local.get 6
        i32.const 717
        i32.const 7
        call $dynrt_lib_modc__fn111
        i32.const 1
        i32.eq
        if  ;; label = @3
          i32.const 1
          local.set 3
        else
          local.get 4
          global.set $dynrt_lib_modc_global19
        end
      end
    end
    local.get 3
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_lib_modc_global28
        local.set 3
        global.get $dynrt_lib_modc_global29
        local.set 4
        global.get $dynrt_lib_modc_global23
        local.set 5
        global.get $dynrt_lib_modc_global24
        local.set 6
        global.get $dynrt_lib_modc_global26
        local.set 7
        global.get $dynrt_lib_modc_global27
        local.set 8
        i32.const 0
        local.tee 11
        global.set $dynrt_lib_modc_global28
        i32.const 0
        local.tee 12
        global.set $dynrt_lib_modc_global23
        i32.const 0
        local.tee 13
        global.set $dynrt_lib_modc_global26
        i32.const 0
        local.tee 14
        global.set $dynrt_lib_modc_global27
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn115
        local.get 2
        local.tee 15
        global.set $dynrt_lib_modc_global21
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn155
        local.get 2
        local.tee 16
        global.set $dynrt_lib_modc_global21
        global.get $dynrt_lib_modc_global28
        i32.eqz
        if (result i32)  ;; label = @3
          global.get $dynrt_lib_modc_global23
          i32.eqz
        else
          i32.const 0
        end
        if (result i32)  ;; label = @3
          global.get $dynrt_lib_modc_global26
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
        if  ;; label = @3
          block  ;; label = @4
            local.get 3
            global.set $dynrt_lib_modc_global28
            local.get 4
            global.set $dynrt_lib_modc_global29
            local.get 5
            global.set $dynrt_lib_modc_global23
            local.get 6
            global.set $dynrt_lib_modc_global24
            local.get 7
            global.set $dynrt_lib_modc_global26
            local.get 8
            global.set $dynrt_lib_modc_global27
          end
        end
      end
    end)
  (func $dynrt_lib_modc__fn147 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32)
    call $dynrt_lib_modc_dynArray
    local.set 2
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn116
    i32.const 40
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_lib_modc_global19
        i32.const 1
        i32.add
        global.set $dynrt_lib_modc_global19
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn115
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn116
        i32.const 41
        i32.eq
        if  ;; label = @3
          global.get $dynrt_lib_modc_global19
          i32.const 1
          i32.add
          global.set $dynrt_lib_modc_global19
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
                    call $dynrt_lib_modc__fn115
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn133
                    global.get $dynrt_lib_modc_global1
                    local.set 4
                    global.get $dynrt_lib_modc_global2
                    local.set 5
                    local.get 2
                    local.get 4
                    local.get 5
                    call $dynrt_lib_modc_dynString
                    call $dynrt_lib_modc_dynPush
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn115
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn116
                    local.set 4
                    local.get 4
                    i32.const 44
                    i32.eq
                    if  ;; label = @9
                      global.get $dynrt_lib_modc_global19
                      i32.const 1
                      i32.add
                      global.set $dynrt_lib_modc_global19
                    else
                      block  ;; label = @10
                        local.get 4
                        i32.const 41
                        i32.eq
                        if  ;; label = @11
                          global.get $dynrt_lib_modc_global19
                          i32.const 1
                          i32.add
                          global.set $dynrt_lib_modc_global19
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
  (func $dynrt_lib_modc__fn148 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    global.get $dynrt_lib_modc_global19
    local.tee 12
    i32.const 1
    local.tee 13
    i32.add
    global.set $dynrt_lib_modc_global19
    global.get $dynrt_lib_modc_global19
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
            global.get $dynrt_lib_modc_global19
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
            global.get $dynrt_lib_modc_global19
            call $dynrt_lib_modc__fn5
            local.set 7
            local.get 4
            i32.const 1
            i32.eq
            if  ;; label = @5
              local.get 7
              i32.const 92
              i32.eq
              if  ;; label = @6
                global.get $dynrt_lib_modc_global19
                i32.const 2
                i32.add
                global.set $dynrt_lib_modc_global19
              else
                local.get 7
                local.get 5
                i32.eq
                if  ;; label = @7
                  block  ;; label = @8
                    i32.const 0
                    local.set 4
                    global.get $dynrt_lib_modc_global19
                    i32.const 1
                    i32.add
                    global.set $dynrt_lib_modc_global19
                  end
                else
                  global.get $dynrt_lib_modc_global19
                  i32.const 1
                  i32.add
                  global.set $dynrt_lib_modc_global19
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
                  global.get $dynrt_lib_modc_global19
                  i32.const 1
                  local.tee 9
                  i32.add
                  global.set $dynrt_lib_modc_global19
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
                    global.get $dynrt_lib_modc_global19
                    i32.const 1
                    local.tee 11
                    i32.add
                    global.set $dynrt_lib_modc_global19
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
                        global.get $dynrt_lib_modc_global19
                        i32.const 1
                        i32.add
                        global.set $dynrt_lib_modc_global19
                      end
                    end
                  else
                    global.get $dynrt_lib_modc_global19
                    i32.const 1
                    i32.add
                    global.set $dynrt_lib_modc_global19
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
    global.get $dynrt_lib_modc_global19
    call $dynrt_lib_modc__fn4
    local.set 3
    nop
    local.set 2
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn116
    i32.const 125
    i32.eq
    if  ;; label = @1
      global.get $dynrt_lib_modc_global19
      i32.const 1
      i32.add
      global.set $dynrt_lib_modc_global19
    end
    local.get 2
    local.get 3
    call $dynrt_lib_modc_dynString
    return)
  (func $dynrt_lib_modc__fn149 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn115
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn116
    i32.const 123
    i32.eq
    if  ;; label = @1
      local.get 0
      local.get 1
      call $dynrt_lib_modc__fn148
      return
    end
    global.get $dynrt_lib_modc_global19
    local.tee 4
    local.set 2
    global.get $dynrt_lib_modc_global21
    local.set 3
    i32.const 0
    global.set $dynrt_lib_modc_global21
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn130
    drop
    local.get 3
    global.set $dynrt_lib_modc_global21
    nop
    local.get 0
    local.get 1
    local.get 2
    global.get $dynrt_lib_modc_global19
    call $dynrt_lib_modc__fn4
    call $dynrt_lib_modc_dynString
    return)
  (func $dynrt_lib_modc__fn150 (param i32 i32) (result i32)
    (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn115
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn116
    i32.const 0
    call $dynrt_lib_modc__fn114
    i32.const 1
    i32.eq
    if  ;; label = @1
      local.get 0
      local.get 1
      call $dynrt_lib_modc__fn133
    end
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn115
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn147
    local.set 2
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn115
    i32.const 563
    i32.const 0
    call $dynrt_lib_modc_dynString
    local.set 3
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn116
    i32.const 123
    i32.eq
    if  ;; label = @1
      local.get 0
      local.get 1
      call $dynrt_lib_modc__fn148
      local.set 3
    end
    local.get 2
    local.get 3
    global.get $dynrt_lib_modc_global20
    call $dynrt_lib_modc__fn94
    return)
  (func $dynrt_lib_modc__fn151 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    global.get $dynrt_lib_modc_global19
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
            global.get $dynrt_lib_modc_global19
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
            global.get $dynrt_lib_modc_global19
            call $dynrt_lib_modc__fn5
            local.set 7
            local.get 4
            i32.const 1
            i32.eq
            if  ;; label = @5
              local.get 7
              i32.const 92
              i32.eq
              if  ;; label = @6
                global.get $dynrt_lib_modc_global19
                i32.const 2
                i32.add
                global.set $dynrt_lib_modc_global19
              else
                local.get 7
                local.get 5
                i32.eq
                if  ;; label = @7
                  block  ;; label = @8
                    i32.const 0
                    local.set 4
                    global.get $dynrt_lib_modc_global19
                    i32.const 1
                    i32.add
                    global.set $dynrt_lib_modc_global19
                  end
                else
                  global.get $dynrt_lib_modc_global19
                  i32.const 1
                  i32.add
                  global.set $dynrt_lib_modc_global19
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
                  global.get $dynrt_lib_modc_global19
                  i32.const 1
                  local.tee 9
                  i32.add
                  global.set $dynrt_lib_modc_global19
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
                    global.get $dynrt_lib_modc_global19
                    i32.const 1
                    local.tee 11
                    i32.add
                    global.set $dynrt_lib_modc_global19
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
                      global.get $dynrt_lib_modc_global19
                      i32.const 1
                      local.tee 13
                      i32.add
                      global.set $dynrt_lib_modc_global19
                      local.get 3
                      i32.eqz
                      if  ;; label = @10
                        i32.const 0
                        local.set 6
                      end
                    end
                  else
                    global.get $dynrt_lib_modc_global19
                    i32.const 1
                    i32.add
                    global.set $dynrt_lib_modc_global19
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
    call $dynrt_lib_modc__fn115
    i32.const 0
    local.tee 15
    local.set 3
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn116
    i32.const 61
    i32.eq
    if (result i32)  ;; label = @1
      local.get 0
      local.get 1
      call $dynrt_lib_modc__fn117
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
    global.set $dynrt_lib_modc_global19
    local.get 3
    return)
  (func $dynrt_lib_modc__fn152 (param i32 i32)
    (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn115
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn133
    global.get $dynrt_lib_modc_global1
    local.set 2
    global.get $dynrt_lib_modc_global2
    local.set 3
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn115
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn147
    local.set 4
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn115
    i32.const 563
    i32.const 0
    call $dynrt_lib_modc_dynString
    local.set 5
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn116
    i32.const 123
    i32.eq
    if  ;; label = @1
      local.get 0
      local.get 1
      call $dynrt_lib_modc__fn148
      local.set 5
    end
    local.get 4
    local.get 5
    global.get $dynrt_lib_modc_global20
    call $dynrt_lib_modc__fn94
    local.set 4
    global.get $dynrt_lib_modc_global21
    i32.const 1
    i32.eq
    if  ;; label = @1
      global.get $dynrt_lib_modc_global20
      local.get 2
      local.get 3
      local.get 4
      call $dynrt_lib_modc_dynSet
    end)
  (func $dynrt_lib_modc__fn153 (param i32 i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn115
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn133
    global.get $dynrt_lib_modc_global1
    local.set 2
    global.get $dynrt_lib_modc_global2
    local.set 3
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn115
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn116
    i32.const 0
    call $dynrt_lib_modc__fn114
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn133
        global.get $dynrt_lib_modc_global1
        local.set 4
        global.get $dynrt_lib_modc_global2
        local.set 5
        local.get 4
        local.get 5
        i32.const 724
        i32.const 7
        call $dynrt_lib_modc__fn111
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn115
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn133
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn115
          end
        end
      end
    end
    call $dynrt_lib_modc_dynObject
    local.set 4
    i32.const -1
    local.set 5
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn116
    i32.const 123
    i32.eq
    if  ;; label = @1
      global.get $dynrt_lib_modc_global19
      i32.const 1
      i32.add
      global.set $dynrt_lib_modc_global19
    end
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn115
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 0
          local.get 1
          call $dynrt_lib_modc__fn116
          i32.const 125
          i32.ne
          if (result i32)  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn116
            i32.const -1
            i32.ne
          else
            i32.const 0
          end
          i32.eqz
          br_if 2 (;@1;)
          local.get 0
          local.get 1
          call $dynrt_lib_modc__fn116
          i32.const 59
          i32.eq
          if  ;; label = @4
            block  ;; label = @5
              global.get $dynrt_lib_modc_global19
              i32.const 1
              i32.add
              global.set $dynrt_lib_modc_global19
              local.get 0
              local.get 1
              call $dynrt_lib_modc__fn115
            end
          else
            block  ;; label = @5
              local.get 0
              local.get 1
              call $dynrt_lib_modc__fn133
              global.get $dynrt_lib_modc_global1
              local.set 6
              global.get $dynrt_lib_modc_global2
              local.set 7
              local.get 0
              local.get 1
              call $dynrt_lib_modc__fn115
              local.get 0
              local.get 1
              call $dynrt_lib_modc__fn147
              local.set 8
              local.get 0
              local.get 1
              call $dynrt_lib_modc__fn115
              local.get 0
              local.get 1
              call $dynrt_lib_modc__fn148
              local.set 9
              local.get 8
              local.get 9
              global.get $dynrt_lib_modc_global20
              call $dynrt_lib_modc__fn94
              local.set 8
              local.get 6
              local.get 7
              i32.const 731
              i32.const 11
              call $dynrt_lib_modc__fn111
              i32.const 1
              i32.eq
              if  ;; label = @6
                local.get 8
                local.set 5
              else
                local.get 4
                local.get 6
                local.get 7
                local.get 8
                call $dynrt_lib_modc_dynSet
              end
              local.get 0
              local.get 1
              call $dynrt_lib_modc__fn115
            end
          end
          br 1 (;@2;)
        end
      end
    end
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn116
    i32.const 125
    i32.eq
    if  ;; label = @1
      global.get $dynrt_lib_modc_global19
      i32.const 1
      i32.add
      global.set $dynrt_lib_modc_global19
    end
    call $dynrt_lib_modc_dynObject
    local.set 6
    local.get 6
    i32.const 742
    i32.const 7
    local.get 4
    call $dynrt_lib_modc_dynSet
    local.get 5
    i32.const -1
    i32.ne
    if  ;; label = @1
      local.get 6
      i32.const 749
      i32.const 6
      local.get 5
      call $dynrt_lib_modc_dynSet
    end
    global.get $dynrt_lib_modc_global21
    i32.const 1
    i32.eq
    if  ;; label = @1
      global.get $dynrt_lib_modc_global20
      local.get 2
      local.get 3
      local.get 6
      call $dynrt_lib_modc_dynSet
    end)
  (func $dynrt_lib_modc__fn154 (param i32 i32) (result i32)
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
    i32.const 742
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
    i32.const 749
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
          call $dynrt_lib_modc__fn103
          drop
        end
      end
    end
    local.get 2
    return)
  (func $dynrt_lib_modc__fn155 (param i32 i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn115
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn116
    local.set 2
    local.get 2
    i32.const 123
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_lib_modc_global19
        i32.const 1
        i32.add
        global.set $dynrt_lib_modc_global19
        global.get $dynrt_lib_modc_global20
        local.set 2
        local.get 2
        call $dynrt_lib_modc__fn99
        local.set 3
        local.get 3
        local.tee 14
        global.set $dynrt_lib_modc_global20
        local.get 3
        call $dynrt_lib_modc__fn41
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn156
        call $dynrt_lib_modc__fn42
        local.get 2
        local.tee 15
        global.set $dynrt_lib_modc_global20
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn115
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn116
        i32.const 125
        i32.eq
        if  ;; label = @3
          global.get $dynrt_lib_modc_global19
          i32.const 1
          i32.add
          global.set $dynrt_lib_modc_global19
        end
        return
      end
    end
    local.get 2
    i32.const 59
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_lib_modc_global19
        i32.const 1
        i32.add
        global.set $dynrt_lib_modc_global19
        return
      end
    end
    local.get 2
    i32.const 0
    call $dynrt_lib_modc__fn114
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_lib_modc_global19
        local.set 2
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn133
        global.get $dynrt_lib_modc_global1
        local.set 3
        global.get $dynrt_lib_modc_global2
        local.set 4
        local.get 3
        local.get 4
        i32.const 691
        i32.const 3
        call $dynrt_lib_modc__fn111
        i32.const 1
        i32.eq
        if (result i32)  ;; label = @3
          i32.const 1
        else
          local.get 3
          local.get 4
          i32.const 686
          i32.const 5
          call $dynrt_lib_modc__fn111
          i32.const 1
          i32.eq
        end
        if (result i32)  ;; label = @3
          i32.const 1
        else
          local.get 3
          local.get 4
          i32.const 694
          i32.const 3
          call $dynrt_lib_modc__fn111
          i32.const 1
          i32.eq
        end
        if  ;; label = @3
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn134
            return
          end
        end
        local.get 3
        local.get 4
        i32.const 755
        i32.const 2
        call $dynrt_lib_modc__fn111
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn136
            return
          end
        end
        local.get 3
        local.get 4
        i32.const 757
        i32.const 5
        call $dynrt_lib_modc__fn111
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn137
            return
          end
        end
        local.get 3
        local.get 4
        i32.const 762
        i32.const 2
        call $dynrt_lib_modc__fn111
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn138
            return
          end
        end
        local.get 3
        local.get 4
        i32.const 764
        i32.const 3
        call $dynrt_lib_modc__fn111
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn139
            return
          end
        end
        local.get 3
        local.get 4
        i32.const 767
        i32.const 6
        call $dynrt_lib_modc__fn111
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn143
            return
          end
        end
        local.get 3
        local.get 4
        i32.const 773
        i32.const 3
        call $dynrt_lib_modc__fn111
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn146
            return
          end
        end
        local.get 3
        local.get 4
        i32.const 776
        i32.const 5
        call $dynrt_lib_modc__fn111
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn130
            local.set 2
            global.get $dynrt_lib_modc_global21
            i32.const 1
            i32.eq
            if  ;; label = @5
              block  ;; label = @6
                i32.const 1
                global.set $dynrt_lib_modc_global28
                local.get 2
                global.set $dynrt_lib_modc_global29
              end
            end
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn115
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn116
            i32.const 59
            i32.eq
            if  ;; label = @5
              global.get $dynrt_lib_modc_global19
              i32.const 1
              i32.add
              global.set $dynrt_lib_modc_global19
            end
            return
          end
        end
        local.get 3
        local.get 4
        i32.const 781
        i32.const 6
        call $dynrt_lib_modc__fn111
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn135
            return
          end
        end
        local.get 3
        local.get 4
        i32.const 628
        i32.const 8
        call $dynrt_lib_modc__fn111
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn152
            return
          end
        end
        local.get 3
        local.get 4
        i32.const 787
        i32.const 5
        call $dynrt_lib_modc__fn111
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn153
            return
          end
        end
        local.get 3
        local.get 4
        i32.const 792
        i32.const 5
        call $dynrt_lib_modc__fn111
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            global.get $dynrt_lib_modc_global21
            i32.const 1
            i32.eq
            if  ;; label = @5
              i32.const 1
              global.set $dynrt_lib_modc_global26
            end
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn115
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn116
            i32.const 59
            i32.eq
            if  ;; label = @5
              global.get $dynrt_lib_modc_global19
              i32.const 1
              i32.add
              global.set $dynrt_lib_modc_global19
            end
            return
          end
        end
        local.get 3
        local.get 4
        i32.const 797
        i32.const 8
        call $dynrt_lib_modc__fn111
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            global.get $dynrt_lib_modc_global21
            i32.const 1
            i32.eq
            if  ;; label = @5
              i32.const 1
              global.set $dynrt_lib_modc_global27
            end
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn115
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn116
            i32.const 59
            i32.eq
            if  ;; label = @5
              global.get $dynrt_lib_modc_global19
              i32.const 1
              i32.add
              global.set $dynrt_lib_modc_global19
            end
            return
          end
        end
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn115
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn116
        local.set 5
        local.get 5
        i32.const 61
        i32.eq
        if (result i32)  ;; label = @3
          local.get 0
          local.get 1
          call $dynrt_lib_modc__fn117
          i32.const 61
          i32.ne
        else
          i32.const 0
        end
        if (result i32)  ;; label = @3
          local.get 0
          local.get 1
          call $dynrt_lib_modc__fn117
          i32.const 62
          i32.ne
        else
          i32.const 0
        end
        if  ;; label = @3
          block  ;; label = @4
            global.get $dynrt_lib_modc_global19
            i32.const 1
            i32.add
            global.set $dynrt_lib_modc_global19
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn130
            local.set 2
            global.get $dynrt_lib_modc_global21
            i32.const 1
            i32.eq
            if  ;; label = @5
              global.get $dynrt_lib_modc_global20
              local.get 3
              local.get 4
              local.get 2
              call $dynrt_lib_modc__fn100
            end
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn115
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn116
            i32.const 59
            i32.eq
            if  ;; label = @5
              global.get $dynrt_lib_modc_global19
              i32.const 1
              i32.add
              global.set $dynrt_lib_modc_global19
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
          call $dynrt_lib_modc__fn117
          i32.const 43
          i32.eq
        else
          i32.const 0
        end
        if  ;; label = @3
          block  ;; label = @4
            global.get $dynrt_lib_modc_global19
            i32.const 2
            i32.add
            global.set $dynrt_lib_modc_global19
            global.get $dynrt_lib_modc_global21
            i32.const 1
            i32.eq
            if  ;; label = @5
              block  ;; label = @6
                global.get $dynrt_lib_modc_global20
                local.get 3
                local.get 4
                call $dynrt_lib_modc__fn98
                local.set 5
                global.get $dynrt_lib_modc_global20
                local.get 3
                local.get 4
                local.get 5
                f64.const 0x1.0p+0 (;=1;)
                call $dynrt_lib_modc_dynNumber
                call $dynrt_lib_modc_dynAdd
                call $dynrt_lib_modc__fn100
              end
            end
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn115
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn116
            i32.const 59
            i32.eq
            if  ;; label = @5
              global.get $dynrt_lib_modc_global19
              i32.const 1
              i32.add
              global.set $dynrt_lib_modc_global19
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
          call $dynrt_lib_modc__fn117
          i32.const 45
          i32.eq
        else
          i32.const 0
        end
        if  ;; label = @3
          block  ;; label = @4
            global.get $dynrt_lib_modc_global19
            i32.const 2
            i32.add
            global.set $dynrt_lib_modc_global19
            global.get $dynrt_lib_modc_global21
            i32.const 1
            i32.eq
            if  ;; label = @5
              block  ;; label = @6
                global.get $dynrt_lib_modc_global20
                local.get 3
                local.get 4
                call $dynrt_lib_modc__fn98
                local.set 5
                global.get $dynrt_lib_modc_global20
                local.get 3
                local.get 4
                local.get 5
                f64.const 0x1.0p+0 (;=1;)
                call $dynrt_lib_modc_dynNumber
                call $dynrt_lib_modc_dynSub
                call $dynrt_lib_modc__fn100
              end
            end
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn115
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn116
            i32.const 59
            i32.eq
            if  ;; label = @5
              global.get $dynrt_lib_modc_global19
              i32.const 1
              i32.add
              global.set $dynrt_lib_modc_global19
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
          call $dynrt_lib_modc__fn117
          i32.const 61
          i32.eq
        else
          i32.const 0
        end
        if  ;; label = @3
          block  ;; label = @4
            local.get 5
            local.set 2
            global.get $dynrt_lib_modc_global19
            i32.const 2
            i32.add
            global.set $dynrt_lib_modc_global19
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn130
            local.set 6
            global.get $dynrt_lib_modc_global21
            i32.const 1
            i32.eq
            if  ;; label = @5
              block  ;; label = @6
                global.get $dynrt_lib_modc_global20
                local.get 3
                local.get 4
                call $dynrt_lib_modc__fn98
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
                global.get $dynrt_lib_modc_global20
                local.get 3
                local.get 4
                local.get 5
                call $dynrt_lib_modc__fn100
              end
            end
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn115
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn116
            i32.const 59
            i32.eq
            if  ;; label = @5
              global.get $dynrt_lib_modc_global19
              i32.const 1
              i32.add
              global.set $dynrt_lib_modc_global19
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
            global.get $dynrt_lib_modc_global20
            i32.const -1
            i32.eq
            if (result i32)  ;; label = @5
              call $dynrt_lib_modc_dynUndefined
            else
              global.get $dynrt_lib_modc_global20
              local.get 3
              local.get 4
              call $dynrt_lib_modc__fn98
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
                    call $dynrt_lib_modc__fn115
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn116
                    local.set 6
                    i32.const 0
                    local.tee 19
                    local.set 7
                    i32.const 563
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
                        global.get $dynrt_lib_modc_global19
                        i32.const 1
                        local.tee 17
                        i32.add
                        global.set $dynrt_lib_modc_global19
                        local.get 0
                        local.get 1
                        call $dynrt_lib_modc__fn133
                        global.get $dynrt_lib_modc_global1
                        local.set 8
                        global.get $dynrt_lib_modc_global2
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
                          global.get $dynrt_lib_modc_global19
                          i32.const 1
                          i32.add
                          global.set $dynrt_lib_modc_global19
                          local.get 0
                          local.get 1
                          call $dynrt_lib_modc__fn130
                          local.set 10
                          local.get 0
                          local.get 1
                          call $dynrt_lib_modc__fn115
                          local.get 0
                          local.get 1
                          call $dynrt_lib_modc__fn116
                          i32.const 93
                          i32.eq
                          if  ;; label = @12
                            global.get $dynrt_lib_modc_global19
                            i32.const 1
                            i32.add
                            global.set $dynrt_lib_modc_global19
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
                        call $dynrt_lib_modc__fn115
                        local.get 0
                        local.get 1
                        call $dynrt_lib_modc__fn116
                        local.set 11
                        local.get 0
                        local.get 1
                        call $dynrt_lib_modc__fn117
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
                              global.get $dynrt_lib_modc_global19
                              i32.const 1
                              i32.add
                              global.set $dynrt_lib_modc_global19
                            else
                              global.get $dynrt_lib_modc_global19
                              i32.const 2
                              i32.add
                              global.set $dynrt_lib_modc_global19
                            end
                            local.get 0
                            local.get 1
                            call $dynrt_lib_modc__fn130
                            local.set 6
                            global.get $dynrt_lib_modc_global21
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
                                  call $dynrt_lib_modc_dynSet
                                else
                                  local.get 3
                                  local.get 10
                                  local.get 5
                                  call $dynrt_lib_modc__fn80
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
                call $dynrt_lib_modc__fn115
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn116
                i32.const 59
                i32.eq
                if  ;; label = @7
                  global.get $dynrt_lib_modc_global19
                  i32.const 1
                  i32.add
                  global.set $dynrt_lib_modc_global19
                end
                return
              end
            end
            local.get 2
            global.set $dynrt_lib_modc_global19
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn130
            local.set 2
            global.get $dynrt_lib_modc_global21
            i32.const 1
            i32.eq
            if  ;; label = @5
              local.get 2
              global.set $dynrt_lib_modc_global25
            end
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn115
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn116
            i32.const 59
            i32.eq
            if  ;; label = @5
              global.get $dynrt_lib_modc_global19
              i32.const 1
              i32.add
              global.set $dynrt_lib_modc_global19
            end
            return
          end
        end
        local.get 2
        global.set $dynrt_lib_modc_global19
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn130
        local.set 2
        global.get $dynrt_lib_modc_global21
        i32.const 1
        i32.eq
        if  ;; label = @3
          local.get 2
          global.set $dynrt_lib_modc_global25
        end
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn115
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn116
        i32.const 59
        i32.eq
        if  ;; label = @3
          global.get $dynrt_lib_modc_global19
          i32.const 1
          i32.add
          global.set $dynrt_lib_modc_global19
        end
        return
      end
    end
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn130
    local.set 2
    global.get $dynrt_lib_modc_global21
    i32.const 1
    i32.eq
    if  ;; label = @1
      local.get 2
      global.set $dynrt_lib_modc_global25
    end
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn115
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn116
    i32.const 59
    i32.eq
    if  ;; label = @1
      global.get $dynrt_lib_modc_global19
      i32.const 1
      i32.add
      global.set $dynrt_lib_modc_global19
    end)
  (func $dynrt_lib_modc__fn156 (param i32 i32)
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
            call $dynrt_lib_modc__fn115
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn116
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
                call $dynrt_lib_modc__fn53
                global.get $dynrt_lib_modc_global21
                local.set 3
                global.get $dynrt_lib_modc_global23
                i32.const 1
                i32.eq
                if (result i32)  ;; label = @7
                  i32.const 1
                else
                  global.get $dynrt_lib_modc_global26
                  i32.const 1
                  i32.eq
                end
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
                if  ;; label = @7
                  i32.const 0
                  global.set $dynrt_lib_modc_global21
                end
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn155
                local.get 3
                global.set $dynrt_lib_modc_global21
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
    call $dynrt_lib_modc__fn41
    i32.const 0
    local.tee 4
    global.set $dynrt_lib_modc_global19
    local.get 2
    local.tee 5
    global.set $dynrt_lib_modc_global20
    i32.const 1
    global.set $dynrt_lib_modc_global21
    i32.const 0
    local.tee 6
    global.set $dynrt_lib_modc_global23
    call $dynrt_lib_modc_dynUndefined
    global.set $dynrt_lib_modc_global24
    i32.const 0
    local.tee 7
    global.set $dynrt_lib_modc_global28
    call $dynrt_lib_modc_dynUndefined
    global.set $dynrt_lib_modc_global25
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn156
    global.get $dynrt_lib_modc_global23
    i32.const 1
    i32.eq
    if (result i32)  ;; label = @1
      global.get $dynrt_lib_modc_global24
    else
      global.get $dynrt_lib_modc_global25
    end
    local.set 3
    call $dynrt_lib_modc__fn42
    local.get 3
    return)
  ;; data from dynrt_lib_modc
  (data (;0;) (i32.const 563) "")
  (data (;1;) (i32.const 563) "false")
  (data (;2;) (i32.const 568) "true")
  (data (;3;) (i32.const 572) "null")
  (data (;4;) (i32.const 576) "undefined")
  (data (;5;) (i32.const 585) "this")
  (data (;6;) (i32.const 589) "abs")
  (data (;7;) (i32.const 592) "sqrt")
  (data (;8;) (i32.const 596) "floor")
  (data (;9;) (i32.const 601) "ceil")
  (data (;10;) (i32.const 605) "round")
  (data (;11;) (i32.const 610) "min")
  (data (;12;) (i32.const 613) "max")
  (data (;13;) (i32.const 616) "len")
  (data (;14;) (i32.const 619) "inc")
  (data (;15;) (i32.const 622) "length")
  (data (;16;) (i32.const 628) "function")
  (data (;17;) (i32.const 636) "Object")
  (data (;18;) (i32.const 642) "create")
  (data (;19;) (i32.const 648) "new")
  (data (;20;) (i32.const 651) "boolean")
  (data (;21;) (i32.const 658) "number")
  (data (;22;) (i32.const 664) "string")
  (data (;23;) (i32.const 670) "object")
  (data (;24;) (i32.const 676) "typeof")
  (data (;25;) (i32.const 682) "else")
  (data (;26;) (i32.const 686) "const")
  (data (;27;) (i32.const 691) "let")
  (data (;28;) (i32.const 694) "var")
  (data (;29;) (i32.const 697) "of")
  (data (;30;) (i32.const 699) "in")
  (data (;31;) (i32.const 701) "case")
  (data (;32;) (i32.const 705) "default")
  (data (;33;) (i32.const 712) "catch")
  (data (;34;) (i32.const 717) "finally")
  (data (;35;) (i32.const 724) "extends")
  (data (;36;) (i32.const 731) "constructor")
  (data (;37;) (i32.const 742) "__proto")
  (data (;38;) (i32.const 749) "__ctor")
  (data (;39;) (i32.const 755) "if")
  (data (;40;) (i32.const 757) "while")
  (data (;41;) (i32.const 762) "do")
  (data (;42;) (i32.const 764) "for")
  (data (;43;) (i32.const 767) "switch")
  (data (;44;) (i32.const 773) "try")
  (data (;45;) (i32.const 776) "throw")
  (data (;46;) (i32.const 781) "return")
  (data (;47;) (i32.const 787) "class")
  (data (;48;) (i32.const 792) "break")
  (data (;49;) (i32.const 797) "continue")
)