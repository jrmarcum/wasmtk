(module
  (import "wasi_snapshot_preview1" "proc_exit" (func $proc_exit (param i32)))
  (import "wasi_snapshot_preview1" "fd_write" (func $fd_write (param i32 i32 i32 i32) (result i32)))
  ;; imports from dynrt_lib_modc
  (import "env" "__host_call" (func $dynrt_lib_modc___host_call (param i32 i32) (result i32)))
  (memory (export "memory") 2)
  (global $__heap_ptr (mut i32) (i32.const 1147))
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

  (func $fib (param $n f64) 
    (if (f64.lt (local.get $n) (f64.const 2))
      (then
      (return)
      )
    )
    (return)
  )
  (func $_start (export "_start")
    (local $e i32)
    (local $r i32)
    (local $__iface_tmp i32)
    (global.set $guard (call $__malloc (i32.const 40)))
      (i32.store (global.get $guard) (i32.const 1))
      (i32.store offset=4 (global.get $guard) (i32.const 8))
      (i32.store offset=8 (global.get $guard) (i32.const 0))
    (local.set $e (call $dynrt_lib_modc_dynObject ))
    (local.set $r (call $dynrt_lib_modc_dynRun (i32.const 260) (i32.const 76) (local.get $e)))
        (i32.store (i32.const 0) (i32.const 132))
          (i32.store (i32.const 4) (i32.const 0))
          (i32.store8 (i32.const 132) (i32.const 102))
          (i32.store8 (i32.const 133) (i32.const 105))
          (i32.store8 (i32.const 134) (i32.const 98))
          (i32.store8 (i32.const 135) (i32.const 40))
          (i32.store8 (i32.const 136) (i32.const 49))
          (i32.store8 (i32.const 137) (i32.const 53))
          (i32.store8 (i32.const 138) (i32.const 41))
          (i32.store8 (i32.const 139) (i32.const 32))
          (i32.store8 (i32.const 140) (i32.const 61))
          (i32.store8 (i32.const 141) (i32.const 32))
          (i32.store (i32.const 4) (i32.add (i32.const 10) (call $__f64_to_str (call $dynrt_lib_modc_dynNumberValue (local.get $r)) (i32.const 142))))
          (i32.store8 (i32.add (i32.const 132) (i32.load (i32.const 4))) (i32.const 10))
          (i32.store (i32.const 4) (i32.add (i32.load (i32.const 4)) (i32.const 1)))
          (drop (call $fd_write
            (i32.const 1)
            (i32.const 0)
            (i32.const 1)
            (i32.const 128)))
    (call $check (if (result i32) (f64.eq (call $dynrt_lib_modc_dynNumberValue (local.get $r)) (f64.const 610)) (then (i32.const 1)) (else (i32.const 0))))
        (i32.store (i32.const 0) (i32.const 336))
          (i32.store (i32.const 4) (i32.const 42))
          (drop (call $fd_write
            (i32.const 1)
            (i32.const 0)
            (i32.const 1)
            (i32.const 128)))
    (call $proc_exit (i32.const 0))
  )
  (data (i32.const 260) "\66\75\6e\63\74\69\6f\6e\20\66\69\62\28\6e\29\7b\69\66\28\6e\3c\32\29\7b\72\65\74\75\72\6e\20\6e\3b\7d\72\65\74\75\72\6e\20\66\69\62\28\6e\2d\31\29\2b\66\69\62\28\6e\2d\32\29\3b\7d\20\72\65\74\75\72\6e\20\66\69\62\28\31\35\29\3b")
  (data (i32.const 336) "\47\43\20\50\61\72\74\31\20\61\75\74\6f\2d\67\72\6f\77\3a\20\64\65\65\70\20\72\65\63\75\72\73\69\6f\6e\20\70\61\73\73\65\64\0a")

  ;; globals from dynrt_lib_modc
  (global $dynrt_lib_modc_global1 (mut i32) (i32.const 0))
  (global $dynrt_lib_modc_global2 (mut i32) (i32.const 0))
  (global $dynrt_lib_modc_global3 i32 (i32.const 4))
  (global $dynrt_lib_modc_global4 i32 (i32.const 16))
  (global $dynrt_lib_modc_global5 i32 (i32.const 890))
  (global $dynrt_lib_modc_global6 (mut i32) (i32.const 0))
  (global $dynrt_lib_modc_global7 (mut i32) (i32.const 0))
  (global $dynrt_lib_modc_global8 (mut i32) (i32.const 0))
  (global $dynrt_lib_modc_global9 (mut i32) (i32.const 0))
  (global $dynrt_lib_modc_global10 (mut i32) (i32.const 0))
  (global $dynrt_lib_modc_global11 (mut i32) (i32.const 0))
  (global $dynrt_lib_modc_global12 (mut i32) (i32.const 0))
  (global $dynrt_lib_modc_global13 (mut i32) (i32.const 890))
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
  (func $dynrt_lib_modc__fn3 (param i32 i32 i32)
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
  (func $dynrt_lib_modc__fn4 (param i32 i32 i32 i32) (result i32 i32)
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
  (func $dynrt_lib_modc__fn5 (param i32 i32 i32 i32) (result i32 i32)
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
  (func $dynrt_lib_modc__fn6 (param i32 i32 i32 i32) (result i32)
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
  (func $dynrt_lib_modc__fn7 (param i32 i32) (result i32 i32)
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
  (func $dynrt_lib_modc__fn8 (param i32 i32 i32) (result i32)
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
  (func $dynrt_lib_modc__fn9 (param i32 i32 i32) (result i32 i32)
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
  (func $dynrt_lib_modc__fn10 (param i32 i32 i32 i32) (result i32)
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
  (func $dynrt_lib_modc__fn11 (param i32 i32 i32 i32) (result i32)
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
  (func $dynrt_lib_modc__fn12 (param i32 i32) (result i32 i32)
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
  (func $dynrt_lib_modc__fn14 (param i32 i32 i32 i32 i32) (result i32 i32)
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
  (func $dynrt_lib_modc__fn15 (param i32 i32 i32 i32 i32) (result i32 i32)
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
  (func $dynrt_lib_modc__fn16 (param i32 i32 i32) (result i32 i32)
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
  (func $dynrt_lib_modc__fn17 (param i32 i32 i32 i32) (result i32)
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
          call $dynrt_lib_modc__fn6
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
              call $dynrt_lib_modc__fn3
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
        call $dynrt_lib_modc__fn3
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
  (func $dynrt_lib_modc__fn18 (param i32) (result f64)
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
  (func $dynrt_lib_modc__fn19 (param f64 i32) (result i32)
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
    call $dynrt_lib_modc__fn20
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
          call $dynrt_lib_modc__fn18
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
  (func $dynrt_lib_modc__fn20 (param i64 i32) (result i32)
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
  (func $dynrt_lib_modc__fn21 (param i32 i32) (result f64)
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
    call $dynrt_lib_modc__fn45
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
    call $dynrt_lib_modc__fn45
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
    call $dynrt_lib_modc__fn45
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
    call $dynrt_lib_modc__fn37
    local.set 1
    local.get 1
    i32.const 8
    i32.add
    local.get 0
    f64.store
    call $dynrt_lib_modc__fn45
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
    call $dynrt_lib_modc__fn37
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
            call $dynrt_lib_modc__fn8
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
    call $dynrt_lib_modc__fn45
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
  (func $dynrt_lib_modc__fn27 (result i32)
    (local i32) (local i32)
    i32.const 8
    global.get $dynrt_lib_modc_global3
    i32.const 2
    i32.add
    i32.const 4
    i32.mul
    i32.add
    call $dynrt_lib_modc__fn37
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
  (func $dynrt_lib_modc__fn28 (param i32) (result i32)
    (local i32)
    local.get 0
    local.set 1
    local.get 1
    i32.const 8
    i32.add
    i32.load
    return)
  (func $dynrt_lib_modc__fn29 (param i32 i32) (result i32)
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
  (func $dynrt_lib_modc__fn30 (param i32 i32 i32)
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
  (func $dynrt_lib_modc__fn31 (param i32 i32) (result i32)
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
        call $dynrt_lib_modc__fn37
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
  (func $dynrt_lib_modc__fn32 (param i32 i32)
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
  (func $dynrt_lib_modc__fn33 (param i32 i32)
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
    call $dynrt_lib_modc__fn32
    global.get $dynrt_lib_modc_global11
    global.get $dynrt_lib_modc_global13
    i32.gt_s
    if  ;; label = @1
      call $dynrt_lib_modc__fn42
    end)
  (func $dynrt_lib_modc__fn34 (param i32 i32)
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
  (func $dynrt_lib_modc__fn35 (param i32) (result i32)
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
    call $dynrt_lib_modc__fn34
    local.get 1
    local.tee 5
    return)
  (func $dynrt_lib_modc__fn36 (param i32) (result i32)
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
                  call $dynrt_lib_modc__fn32
                end
                local.get 1
                local.get 0
                call $dynrt_lib_modc__fn34
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
  (func $dynrt_lib_modc__fn37 (param i32) (result i32)
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
    call $dynrt_lib_modc__fn35
    local.set 2
    local.get 2
    i32.const 0
    i32.ne
    if  ;; label = @1
      local.get 2
      return
    end
    local.get 1
    call $dynrt_lib_modc__fn36
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
        call $dynrt_lib_modc__fn42
        local.get 1
        call $dynrt_lib_modc__fn35
        local.set 2
        local.get 2
        i32.const 0
        i32.ne
        if  ;; label = @3
          local.get 2
          return
        end
        local.get 1
        call $dynrt_lib_modc__fn36
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
  (func $dynrt_lib_modc__fn38 (param i32) (result i32)
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
  (func $dynrt_lib_modc__fn39 (param i32 i32) (result i32)
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
  (func $dynrt_lib_modc__fn40 (param i32) (result i32)
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
    call $dynrt_lib_modc__fn38
    local.set 1
    local.get 0
    call $dynrt_lib_modc__fn40
    local.set 2
    local.get 1
    call $dynrt_lib_modc__fn40
    local.set 1
    local.get 2
    local.get 1
    call $dynrt_lib_modc__fn39
    return)
  (func $dynrt_lib_modc__fn41 (param i32 i32) (result i32)
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
  (func $dynrt_lib_modc__fn42
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    i32.const 0
    local.tee 7
    local.set 0
    global.get $dynrt_lib_modc_global6
    local.get 0
    call $dynrt_lib_modc__fn41
    local.set 0
    global.get $dynrt_lib_modc_global7
    local.get 0
    call $dynrt_lib_modc__fn41
    local.set 0
    global.get $dynrt_lib_modc_global8
    local.get 0
    call $dynrt_lib_modc__fn41
    local.set 0
    global.get $dynrt_lib_modc_global9
    local.get 0
    call $dynrt_lib_modc__fn41
    local.set 0
    global.get $dynrt_lib_modc_global10
    local.get 0
    call $dynrt_lib_modc__fn41
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
    call $dynrt_lib_modc__fn40
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
            call $dynrt_lib_modc__fn32
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
  (func $dynrt_lib_modc__fn44 (param i32)
    global.get $dynrt_lib_modc_global15
    i32.eqz
    if  ;; label = @1
      call $dynrt_lib_modc__fn27
      global.set $dynrt_lib_modc_global15
    end
    global.get $dynrt_lib_modc_global15
    local.get 0
    call $dynrt_lib_modc__fn31
    global.set $dynrt_lib_modc_global15)
  (func $dynrt_lib_modc__fn45 (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    i32.const 24
    call $dynrt_lib_modc__fn37
    local.set 0
    global.get $dynrt_lib_modc_global15
    i32.eqz
    if  ;; label = @1
      call $dynrt_lib_modc__fn27
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
        call $dynrt_lib_modc__fn31
        global.set $dynrt_lib_modc_global15
        local.get 2
        local.get 1
        call $dynrt_lib_modc__fn33
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
  (func $dynrt_lib_modc__fn46 (result i32)
    (local i32) (local i32)
    i32.const 28
    call $dynrt_lib_modc__fn37
    local.set 0
    local.get 0
    call $dynrt_lib_modc__fn44
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
    call $dynrt_lib_modc__fn28
    return)
  (func $dynrt_lib_modc__fn48 (param i32) (result i32)
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
  (func $dynrt_lib_modc__fn49 (param i32)
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
    call $dynrt_lib_modc__fn48
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
        call $dynrt_lib_modc__fn28
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
                call $dynrt_lib_modc__fn29
                call $dynrt_lib_modc__fn49
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
          call $dynrt_lib_modc__fn49
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
            call $dynrt_lib_modc__fn49
            local.get 1
            i32.const 8
            i32.add
            i32.const 12
            i32.add
            i32.load
            call $dynrt_lib_modc__fn49
            local.get 1
            i32.const 8
            i32.add
            i32.const 16
            i32.add
            i32.load
            call $dynrt_lib_modc__fn49
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
    call $dynrt_lib_modc__fn28
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
            call $dynrt_lib_modc__fn29
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
    call $dynrt_lib_modc__fn49)
  (func $dynrt_lib_modc_dynGcMarkedCount (result i32)
    (local i32) (local i32) (local i32) (local i32)
    global.get $dynrt_lib_modc_global15
    i32.eqz
    if  ;; label = @1
      i32.const 0
      return
    end
    global.get $dynrt_lib_modc_global15
    call $dynrt_lib_modc__fn28
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
            call $dynrt_lib_modc__fn29
            call $dynrt_lib_modc__fn48
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
  (func $dynrt_lib_modc__fn53 (param i32)
    global.get $dynrt_lib_modc_global17
    i32.eqz
    if  ;; label = @1
      call $dynrt_lib_modc__fn27
      global.set $dynrt_lib_modc_global17
    end
    global.get $dynrt_lib_modc_global17
    local.get 0
    call $dynrt_lib_modc__fn31
    global.set $dynrt_lib_modc_global17)
  (func $dynrt_lib_modc__fn54
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
    call $dynrt_lib_modc__fn53)
  (func $dynrt_lib_modc_dynGcPopRoot
    call $dynrt_lib_modc__fn54)
  (func $dynrt_lib_modc_dynGcRootCount (result i32)
    global.get $dynrt_lib_modc_global17
    i32.eqz
    if  ;; label = @1
      i32.const 0
      return
    end
    global.get $dynrt_lib_modc_global17
    call $dynrt_lib_modc__fn28
    return)
  (func $dynrt_lib_modc_dynGcMarkRoots
    (local i32) (local i32) (local i32) (local i32)
    call $dynrt_lib_modc_dynGcMarkClear
    global.get $dynrt_lib_modc_global20
    call $dynrt_lib_modc__fn49
    global.get $dynrt_lib_modc_global25
    call $dynrt_lib_modc__fn49
    global.get $dynrt_lib_modc_global24
    call $dynrt_lib_modc__fn49
    global.get $dynrt_lib_modc_global17
    i32.eqz
    if  ;; label = @1
      return
    end
    global.get $dynrt_lib_modc_global17
    call $dynrt_lib_modc__fn28
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
            call $dynrt_lib_modc__fn29
            call $dynrt_lib_modc__fn49
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
        call $dynrt_lib_modc__fn28
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
                call $dynrt_lib_modc__fn29
                call $dynrt_lib_modc__fn49
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
      call $dynrt_lib_modc__fn27
      global.set $dynrt_lib_modc_global18
    end
    global.get $dynrt_lib_modc_global18
    call $dynrt_lib_modc__fn28
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
            call $dynrt_lib_modc__fn29
            i32.eqz
            if  ;; label = @5
              block  ;; label = @6
                global.get $dynrt_lib_modc_global18
                local.get 2
                local.get 0
                call $dynrt_lib_modc__fn30
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
    call $dynrt_lib_modc__fn31
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
      call $dynrt_lib_modc__fn28
      i32.ge_s
    end
    if  ;; label = @1
      return
    end
    global.get $dynrt_lib_modc_global18
    local.get 0
    i32.const 0
    call $dynrt_lib_modc__fn30)
  (func $dynrt_lib_modc__fn61 (param i32)
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
    call $dynrt_lib_modc__fn33)
  (func $dynrt_lib_modc__fn62 (param i32)
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
      call $dynrt_lib_modc__fn33
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
        call $dynrt_lib_modc__fn33
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
          call $dynrt_lib_modc__fn61
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
              call $dynrt_lib_modc__fn61
              local.get 1
              i32.const 8
              i32.add
              i32.const 12
              i32.add
              i32.load
              local.set 1
              local.get 1
              call $dynrt_lib_modc__fn28
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
                      call $dynrt_lib_modc__fn29
                      i32.const 8
                      local.get 1
                      local.get 3
                      i32.const 1
                      i32.add
                      call $dynrt_lib_modc__fn29
                      i32.add
                      call $dynrt_lib_modc__fn33
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
              call $dynrt_lib_modc__fn61
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
                call $dynrt_lib_modc__fn62
                local.get 5
                local.get 6
                call $dynrt_lib_modc__fn33
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
  (func $dynrt_lib_modc__fn65
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
    call $dynrt_lib_modc__fn45
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
    call $dynrt_lib_modc__fn27
    i32.store
    local.get 0
    local.tee 1
    return)
  (func $dynrt_lib_modc_dynObject (result i32)
    (local i32) (local i32)
    call $dynrt_lib_modc__fn45
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
    call $dynrt_lib_modc__fn27
    i32.store
    local.get 0
    i32.const 8
    i32.add
    i32.const 12
    i32.add
    call $dynrt_lib_modc__fn27
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
  (func $dynrt_lib_modc__fn77 (param i32)
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
    i32.const 638
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
            call $dynrt_lib_modc__fn4
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
  (func $dynrt_lib_modc__fn78 (param i32)
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
        call $dynrt_lib_modc__fn77
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
        call $dynrt_lib_modc__fn19
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
            i32.const 638
            local.set 1
            i32.const 5
            local.set 2
          end
        else
          block  ;; label = @4
            i32.const 643
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
        i32.const 647
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
        i32.const 651
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
    i32.const 638
    local.set 1
    i32.const 0
    local.set 2
    local.get 1
    local.tee 6
    global.set $dynrt_lib_modc_global1
    local.get 2
    global.set $dynrt_lib_modc_global2
    return)
  (func $dynrt_lib_modc__fn79 (param i32 i32 i32) (result i32)
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
    call $dynrt_lib_modc__fn28
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
            call $dynrt_lib_modc__fn29
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
                call $dynrt_lib_modc__fn29
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
                      call $dynrt_lib_modc__fn8
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
    call $dynrt_lib_modc__fn79
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
        call $dynrt_lib_modc__fn30
        return
      end
    end
    local.get 2
    local.tee 10
    local.set 5
    i32.const 8
    local.get 5
    i32.add
    call $dynrt_lib_modc__fn37
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
            call $dynrt_lib_modc__fn8
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
    call $dynrt_lib_modc__fn31
    local.set 7
    local.get 7
    local.get 5
    call $dynrt_lib_modc__fn31
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
    call $dynrt_lib_modc__fn31
    i32.store)
  (func $dynrt_lib_modc_dynGet (param i32 i32 i32) (result i32)
    (local i32) (local i32) (local i32)
    local.get 0
    local.tee 5
    local.set 3
    local.get 0
    local.get 1
    local.get 2
    call $dynrt_lib_modc__fn79
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
    call $dynrt_lib_modc__fn29
    return)
  (func $dynrt_lib_modc_dynHas (param i32 i32 i32) (result i32)
    local.get 0
    local.get 1
    local.get 2
    call $dynrt_lib_modc__fn79
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
    call $dynrt_lib_modc__fn28
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
    call $dynrt_lib_modc__fn29
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
    call $dynrt_lib_modc__fn29
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
    call $dynrt_lib_modc__fn29
    return)
  (func $dynrt_lib_modc__fn87 (param i32 i32) (result i32)
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
    call $dynrt_lib_modc__fn29
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
    call $dynrt_lib_modc__fn29
    local.set 2
    local.get 3
    local.tee 7
    local.set 3
    i32.const 8
    local.get 2
    i32.add
    call $dynrt_lib_modc__fn37
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
    call $dynrt_lib_modc__fn45
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
    call $dynrt_lib_modc__fn31
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
    call $dynrt_lib_modc__fn28
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
    call $dynrt_lib_modc__fn29
    return)
  (func $dynrt_lib_modc__fn91 (param i32 i32 i32)
    (local i32) (local i32)
    local.get 0
    local.set 3
    local.get 3
    i32.const 8
    i32.add
    i32.const 4
    i32.add
    i32.load
    call $dynrt_lib_modc__fn28
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
      call $dynrt_lib_modc__fn30
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
        call $dynrt_lib_modc__fn31
        i32.store
      end
    end)
  (func $dynrt_lib_modc__fn92 (param i32 i32 i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local f64) (local i32) (local i32) (local i32) (local i32) (local i32) (local f64) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    call $dynrt_lib_modc_dynArrLen
    local.set 4
    local.get 3
    call $dynrt_lib_modc_dynArrLen
    local.set 5
    local.get 1
    local.get 2
    i32.const 660
    i32.const 4
    call $dynrt_lib_modc__fn125
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
    i32.const 664
    i32.const 7
    call $dynrt_lib_modc__fn125
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
    i32.const 671
    i32.const 8
    call $dynrt_lib_modc__fn125
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
    i32.const 679
    i32.const 4
    call $dynrt_lib_modc__fn125
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        i32.const 683
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
            call $dynrt_lib_modc__fn78
            global.get $dynrt_lib_modc_global1
            local.set 7
            global.get $dynrt_lib_modc_global2
            local.set 8
          end
        end
        i32.const 638
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
                    call $dynrt_lib_modc__fn4
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
                call $dynrt_lib_modc__fn78
                local.get 5
                local.get 9
                global.get $dynrt_lib_modc_global1
                global.get $dynrt_lib_modc_global2
                call $dynrt_lib_modc__fn4
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
    i32.const 684
    i32.const 5
    call $dynrt_lib_modc__fn125
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
    i32.const 689
    i32.const 6
    call $dynrt_lib_modc__fn125
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
    i32.const 695
    i32.const 7
    call $dynrt_lib_modc__fn125
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
    i32.const 702
    i32.const 3
    call $dynrt_lib_modc__fn125
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
        call $dynrt_lib_modc__fn29
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
    i32.const 705
    i32.const 5
    call $dynrt_lib_modc__fn125
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
        call $dynrt_lib_modc__fn29
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
                call $dynrt_lib_modc__fn29
                call $dynrt_lib_modc__fn30
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
    i32.const 710
    i32.const 7
    call $dynrt_lib_modc__fn125
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
                call $dynrt_lib_modc__fn29
                call $dynrt_lib_modc__fn30
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
                call $dynrt_lib_modc__fn30
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
    i32.const 717
    i32.const 2
    call $dynrt_lib_modc__fn125
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
    i32.const 719
    i32.const 11
    call $dynrt_lib_modc__fn125
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
    i32.const 730
    i32.const 3
    call $dynrt_lib_modc__fn125
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
    i32.const 733
    i32.const 6
    call $dynrt_lib_modc__fn125
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
    i32.const 739
    i32.const 7
    call $dynrt_lib_modc__fn125
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
    i32.const 746
    i32.const 6
    call $dynrt_lib_modc__fn125
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
    i32.const 752
    i32.const 4
    call $dynrt_lib_modc__fn125
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
    i32.const 756
    i32.const 9
    call $dynrt_lib_modc__fn125
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
    i32.const 765
    i32.const 4
    call $dynrt_lib_modc__fn125
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
    i32.const 769
    i32.const 5
    call $dynrt_lib_modc__fn125
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
    i32.const 774
    i32.const 4
    call $dynrt_lib_modc__fn125
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
                call $dynrt_lib_modc__fn29
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
                        call $dynrt_lib_modc__fn29
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
                            call $dynrt_lib_modc__fn30
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
                call $dynrt_lib_modc__fn30
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
  (func $dynrt_lib_modc__fn93 (param i32 i32 i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local f64) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    call $dynrt_lib_modc__fn77
    global.get $dynrt_lib_modc_global1
    local.set 4
    global.get $dynrt_lib_modc_global2
    local.set 5
    local.get 5
    local.set 6
    local.get 3
    call $dynrt_lib_modc_dynArrLen
    local.set 7
    local.get 1
    local.get 2
    i32.const 778
    i32.const 6
    call $dynrt_lib_modc__fn125
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
    i32.const 784
    i32.const 10
    call $dynrt_lib_modc__fn125
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
        call $dynrt_lib_modc__fn8
        local.set 4
        local.get 4
        f64.convert_i32_s
        call $dynrt_lib_modc_dynNumber
        return
      end
    end
    local.get 1
    local.get 2
    i32.const 794
    i32.const 11
    call $dynrt_lib_modc__fn125
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 4
        local.get 5
        call $dynrt_lib_modc__fn12
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
    i32.const 805
    i32.const 11
    call $dynrt_lib_modc__fn125
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
    i32.const 816
    i32.const 4
    call $dynrt_lib_modc__fn125
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 4
        local.get 5
        call $dynrt_lib_modc__fn7
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
    i32.const 684
    i32.const 5
    call $dynrt_lib_modc__fn125
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
          i32.const 638
          i32.const 0
          call $dynrt_lib_modc_dynString
          return
        end
        local.get 4
        local.get 5
        local.get 9
        local.get 10
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
    i32.const 664
    i32.const 7
    call $dynrt_lib_modc__fn125
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        i32.const 638
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
            call $dynrt_lib_modc__fn77
            global.get $dynrt_lib_modc_global1
            local.set 6
            global.get $dynrt_lib_modc_global2
            local.set 9
          end
        end
        local.get 4
        local.get 5
        local.get 6
        local.get 9
        call $dynrt_lib_modc__fn6
        local.set 6
        local.get 6
        f64.convert_i32_s
        call $dynrt_lib_modc_dynNumber
        return
      end
    end
    local.get 1
    local.get 2
    i32.const 671
    i32.const 8
    call $dynrt_lib_modc__fn125
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        i32.const 638
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
            call $dynrt_lib_modc__fn77
            global.get $dynrt_lib_modc_global1
            local.set 6
            global.get $dynrt_lib_modc_global2
            local.set 9
          end
        end
        local.get 4
        local.get 5
        local.get 6
        local.get 9
        call $dynrt_lib_modc__fn6
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
    i32.const 820
    i32.const 10
    call $dynrt_lib_modc__fn125
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        i32.const 638
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
            call $dynrt_lib_modc__fn77
            global.get $dynrt_lib_modc_global1
            local.set 6
            global.get $dynrt_lib_modc_global2
            local.set 9
          end
        end
        local.get 4
        local.get 5
        local.get 6
        local.get 9
        call $dynrt_lib_modc__fn10
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
    i32.const 830
    i32.const 8
    call $dynrt_lib_modc__fn125
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        i32.const 638
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
            call $dynrt_lib_modc__fn77
            global.get $dynrt_lib_modc_global1
            local.set 6
            global.get $dynrt_lib_modc_global2
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
    i32.const 838
    i32.const 6
    call $dynrt_lib_modc__fn125
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
    i32.const 844
    i32.const 8
    call $dynrt_lib_modc__fn125
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
        i32.const 852
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
            call $dynrt_lib_modc__fn77
            global.get $dynrt_lib_modc_global1
            local.set 9
            global.get $dynrt_lib_modc_global2
            local.set 10
          end
        end
        local.get 4
        local.get 5
        local.get 6
        local.get 9
        local.get 10
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
    i32.const 853
    i32.const 6
    call $dynrt_lib_modc__fn125
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
        i32.const 852
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
            call $dynrt_lib_modc__fn77
            global.get $dynrt_lib_modc_global1
            local.set 9
            global.get $dynrt_lib_modc_global2
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
    i32.const 689
    i32.const 6
    call $dynrt_lib_modc__fn125
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        i32.const 638
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
            call $dynrt_lib_modc__fn77
            global.get $dynrt_lib_modc_global1
            local.set 6
            global.get $dynrt_lib_modc_global2
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
        call $dynrt_lib_modc__fn4
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
    i32.const 859
    i32.const 5
    call $dynrt_lib_modc__fn125
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        i32.const 638
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
            call $dynrt_lib_modc__fn77
            global.get $dynrt_lib_modc_global1
            local.set 6
            global.get $dynrt_lib_modc_global2
            local.set 9
          end
        end
        local.get 4
        local.get 5
        local.get 6
        local.get 9
        call $dynrt_lib_modc__fn17
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
    call $dynrt_lib_modc_dynUndefined
    return)
  (func $dynrt_lib_modc__fn94 (param i32 i32 i32)
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
          call $dynrt_lib_modc__fn91
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
            call $dynrt_lib_modc__fn77
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
        call $dynrt_lib_modc__fn78
        global.get $dynrt_lib_modc_global1
        local.tee 8
        local.set 2
        global.get $dynrt_lib_modc_global2
        local.tee 9
        local.set 3
        local.get 1
        call $dynrt_lib_modc__fn78
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
        call $dynrt_lib_modc__fn4
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
    call $dynrt_lib_modc__fn45
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
  (func $dynrt_lib_modc__fn108 (param i32 i32 i32) (result i32)
    (local i32) (local i32)
    call $dynrt_lib_modc__fn46
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
    call $dynrt_lib_modc__fn108
    return)
  (func $dynrt_lib_modc_dynMakeHostFn (param i32) (result i32)
    (local i32) (local i32)
    call $dynrt_lib_modc__fn46
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
              call $dynrt_lib_modc__fn8
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
                        call $dynrt_lib_modc__fn8
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
                        call $dynrt_lib_modc__fn8
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
                    call $dynrt_lib_modc__fn5
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
  (func $dynrt_lib_modc__fn112 (param i32 i32 i32) (result i32)
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
  (func $dynrt_lib_modc__fn113 (param i32) (result i32)
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
  (func $dynrt_lib_modc__fn114 (param i32 i32 i32 i32)
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
  (func $dynrt_lib_modc__fn115 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 1
    call $dynrt_lib_modc__fn113
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
    call $dynrt_lib_modc__fn28
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
            call $dynrt_lib_modc__fn29
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
            call $dynrt_lib_modc__fn29
            local.set 8
            local.get 3
            i32.const 8
            i32.add
            i32.const 4
            i32.add
            i32.load
            local.get 6
            call $dynrt_lib_modc__fn29
            local.set 9
            local.get 7
            local.tee 13
            local.set 7
            i32.const 8
            local.get 8
            i32.add
            call $dynrt_lib_modc__fn37
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
            call $dynrt_lib_modc__fn31
            local.set 7
            local.get 7
            local.get 8
            call $dynrt_lib_modc__fn31
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
            call $dynrt_lib_modc__fn31
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
    call $dynrt_lib_modc__fn117
    return)
  (func $dynrt_lib_modc__fn117 (param i32 i32 i32) (result i32)
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
          i32.const 864
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
                call $dynrt_lib_modc__fn77
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
        call $dynrt_lib_modc__fn77
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
    i32.const 868
    i32.const 3
    i32.const 0
    call $dynrt_lib_modc_dynBuiltin
    call $dynrt_lib_modc_dynSet
    local.get 0
    i32.const 871
    i32.const 4
    i32.const 1
    call $dynrt_lib_modc_dynBuiltin
    call $dynrt_lib_modc_dynSet
    local.get 0
    i32.const 875
    i32.const 5
    i32.const 2
    call $dynrt_lib_modc_dynBuiltin
    call $dynrt_lib_modc_dynSet
    local.get 0
    i32.const 880
    i32.const 4
    i32.const 3
    call $dynrt_lib_modc_dynBuiltin
    call $dynrt_lib_modc_dynSet
    local.get 0
    i32.const 884
    i32.const 5
    i32.const 4
    call $dynrt_lib_modc_dynBuiltin
    call $dynrt_lib_modc_dynSet
    local.get 0
    i32.const 889
    i32.const 3
    i32.const 5
    call $dynrt_lib_modc_dynBuiltin
    call $dynrt_lib_modc_dynSet
    local.get 0
    i32.const 892
    i32.const 3
    i32.const 6
    call $dynrt_lib_modc_dynBuiltin
    call $dynrt_lib_modc_dynSet
    local.get 0
    i32.const 895
    i32.const 3
    i32.const 7
    call $dynrt_lib_modc_dynBuiltin
    call $dynrt_lib_modc_dynSet
    local.get 0
    i32.const 898
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
  (func $dynrt_lib_modc__fn125 (param i32 i32 i32 i32) (result i32)
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
            call $dynrt_lib_modc__fn8
            local.get 2
            local.get 3
            local.get 4
            call $dynrt_lib_modc__fn8
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
        i32.const 901
        local.set 3
        i32.const 6
        local.set 4
        local.get 3
        local.get 4
        local.get 1
        local.get 2
        call $dynrt_lib_modc__fn4
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
                        call $dynrt_lib_modc__fn117
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
        i32.const 907
        i32.const 6
        call $dynrt_lib_modc__fn125
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
        i32.const 907
        i32.const 6
        call $dynrt_lib_modc__fn125
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
  (func $dynrt_lib_modc__fn127 (param i32 i32 i32 i32)
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
        i32.const 913
        local.set 4
        i32.const 6
        local.set 5
        local.get 4
        local.get 5
        local.get 1
        local.get 2
        call $dynrt_lib_modc__fn4
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
                        call $dynrt_lib_modc__fn117
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
            call $dynrt_lib_modc__fn77
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
  (func $dynrt_lib_modc__fn129 (param i32 i32) (result i32)
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
  (func $dynrt_lib_modc__fn130 (param i32 i32)
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
              call $dynrt_lib_modc__fn8
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
  (func $dynrt_lib_modc__fn131 (param i32 i32) (result i32)
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
    call $dynrt_lib_modc__fn8
    return)
  (func $dynrt_lib_modc__fn132 (param i32 i32) (result i32)
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
    call $dynrt_lib_modc__fn8
    return)
  (func $dynrt_lib_modc__fn133 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32)
    global.get $dynrt_lib_modc_global19
    local.tee 4
    local.set 2
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn131
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
            call $dynrt_lib_modc__fn131
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
        call $dynrt_lib_modc__fn131
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
                call $dynrt_lib_modc__fn131
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
        call $dynrt_lib_modc__fn131
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
            call $dynrt_lib_modc__fn131
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
                call $dynrt_lib_modc__fn131
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
    call $dynrt_lib_modc__fn5
    local.set 3
    nop
    local.set 2
    local.get 2
    local.get 3
    call $dynrt_lib_modc__fn21
    call $dynrt_lib_modc_dynNumber
    return)
  (func $dynrt_lib_modc__fn134 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn131
    local.set 2
    global.get $dynrt_lib_modc_global19
    i32.const 1
    local.tee 16
    i32.add
    global.set $dynrt_lib_modc_global19
    i32.const 638
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
              call $dynrt_lib_modc__fn8
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
                    call $dynrt_lib_modc__fn8
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
                    call $dynrt_lib_modc__fn4
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
                    call $dynrt_lib_modc__fn4
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
  (func $dynrt_lib_modc__fn135 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn130
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn131
    local.set 2
    local.get 2
    i32.const 40
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn166
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn162
            local.set 2
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn130
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn131
            i32.const 61
            i32.eq
            if (result i32)  ;; label = @5
              local.get 0
              local.get 1
              call $dynrt_lib_modc__fn132
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
            call $dynrt_lib_modc__fn164
            global.get $dynrt_lib_modc_global20
            call $dynrt_lib_modc__fn108
            return
          end
        end
        global.get $dynrt_lib_modc_global19
        i32.const 1
        i32.add
        global.set $dynrt_lib_modc_global19
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn145
        local.set 2
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn130
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn131
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
      call $dynrt_lib_modc__fn134
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
        call $dynrt_lib_modc__fn130
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn131
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
                call $dynrt_lib_modc__fn130
                i32.const 0
                local.set 4
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn131
                i32.const 46
                i32.eq
                if (result i32)  ;; label = @7
                  local.get 0
                  local.get 1
                  call $dynrt_lib_modc__fn132
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
                    call $dynrt_lib_modc__fn8
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
                    call $dynrt_lib_modc__fn145
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
                  call $dynrt_lib_modc__fn145
                  call $dynrt_lib_modc_dynPush
                end
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn130
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn131
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
                    call $dynrt_lib_modc__fn130
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn131
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
        call $dynrt_lib_modc__fn130
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn131
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
        call $dynrt_lib_modc__fn130
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn131
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
                call $dynrt_lib_modc__fn130
                i32.const 0
                local.tee 8
                drop
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn131
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
                    call $dynrt_lib_modc__fn134
                    call $dynrt_lib_modc__fn77
                    global.get $dynrt_lib_modc_global1
                    local.set 4
                    global.get $dynrt_lib_modc_global2
                    local.set 5
                  end
                else
                  block  ;; label = @8
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn148
                    global.get $dynrt_lib_modc_global1
                    local.set 4
                    global.get $dynrt_lib_modc_global2
                    local.set 5
                  end
                end
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn130
                i32.const 0
                local.tee 9
                drop
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn131
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
                    call $dynrt_lib_modc__fn145
                    local.set 6
                  end
                else
                  local.get 0
                  local.get 1
                  call $dynrt_lib_modc__fn131
                  i32.const 40
                  i32.eq
                  if  ;; label = @8
                    block  ;; label = @9
                      local.get 0
                      local.get 1
                      call $dynrt_lib_modc__fn162
                      local.set 6
                      local.get 0
                      local.get 1
                      call $dynrt_lib_modc__fn130
                      local.get 6
                      local.get 0
                      local.get 1
                      call $dynrt_lib_modc__fn163
                      global.get $dynrt_lib_modc_global20
                      call $dynrt_lib_modc__fn108
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
                        call $dynrt_lib_modc__fn112
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
                call $dynrt_lib_modc__fn130
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn131
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
                    call $dynrt_lib_modc__fn130
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn131
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
        call $dynrt_lib_modc__fn130
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn131
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
        i32.const 638
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
                call $dynrt_lib_modc__fn131
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
                      call $dynrt_lib_modc__fn5
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
                      call $dynrt_lib_modc__fn132
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
                        call $dynrt_lib_modc__fn5
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
                        call $dynrt_lib_modc__fn145
                        local.set 3
                        local.get 2
                        local.get 3
                        call $dynrt_lib_modc_dynAdd
                        local.set 2
                        local.get 0
                        local.get 1
                        call $dynrt_lib_modc__fn130
                        local.get 0
                        local.get 1
                        call $dynrt_lib_modc__fn131
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
      call $dynrt_lib_modc__fn133
      return
    end
    local.get 2
    i32.const 46
    i32.eq
    if  ;; label = @1
      local.get 0
      local.get 1
      call $dynrt_lib_modc__fn133
      return
    end
    local.get 2
    i32.const 0
    call $dynrt_lib_modc__fn129
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
              call $dynrt_lib_modc__fn129
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
                call $dynrt_lib_modc__fn131
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
        call $dynrt_lib_modc__fn5
        local.set 4
        nop
        local.set 3
        local.get 3
        local.get 4
        i32.const 919
        i32.const 8
        call $dynrt_lib_modc__fn125
        i32.const 1
        i32.eq
        if  ;; label = @3
          local.get 0
          local.get 1
          call $dynrt_lib_modc__fn165
          return
        end
        local.get 3
        local.get 4
        i32.const 643
        i32.const 4
        call $dynrt_lib_modc__fn125
        i32.const 1
        i32.eq
        if  ;; label = @3
          i32.const 1
          call $dynrt_lib_modc_dynBool
          return
        end
        local.get 3
        local.get 4
        i32.const 638
        i32.const 5
        call $dynrt_lib_modc__fn125
        i32.const 1
        i32.eq
        if  ;; label = @3
          i32.const 0
          call $dynrt_lib_modc_dynBool
          return
        end
        local.get 3
        local.get 4
        i32.const 647
        i32.const 4
        call $dynrt_lib_modc__fn125
        i32.const 1
        i32.eq
        if  ;; label = @3
          call $dynrt_lib_modc_dynNull
          return
        end
        local.get 3
        local.get 4
        i32.const 651
        i32.const 9
        call $dynrt_lib_modc__fn125
        i32.const 1
        i32.eq
        if  ;; label = @3
          call $dynrt_lib_modc_dynUndefined
          return
        end
        local.get 3
        local.get 4
        i32.const 927
        i32.const 6
        call $dynrt_lib_modc__fn125
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            global.get $dynrt_lib_modc_global19
            local.set 2
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn130
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn131
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
                call $dynrt_lib_modc__fn148
                global.get $dynrt_lib_modc_global1
                local.set 5
                global.get $dynrt_lib_modc_global2
                local.set 6
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn130
                local.get 5
                local.get 6
                i32.const 933
                i32.const 6
                call $dynrt_lib_modc__fn125
                i32.const 1
                i32.eq
                if (result i32)  ;; label = @7
                  local.get 0
                  local.get 1
                  call $dynrt_lib_modc__fn131
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
                    call $dynrt_lib_modc__fn145
                    local.set 2
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn130
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn131
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
        i32.const 939
        i32.const 3
        call $dynrt_lib_modc__fn125
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn130
            global.get $dynrt_lib_modc_global19
            local.tee 19
            local.set 2
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn131
            local.set 3
            block  ;; label = @5
              loop  ;; label = @6
                block  ;; label = @7
                  local.get 3
                  i32.const 1
                  call $dynrt_lib_modc__fn129
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
                    call $dynrt_lib_modc__fn131
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
            call $dynrt_lib_modc__fn5
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
              call $dynrt_lib_modc__fn112
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
            call $dynrt_lib_modc__fn53
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn130
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn131
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
                call $dynrt_lib_modc__fn130
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn131
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
                            call $dynrt_lib_modc__fn145
                            local.set 5
                            local.get 3
                            local.get 5
                            call $dynrt_lib_modc_dynPush
                            local.get 0
                            local.get 1
                            call $dynrt_lib_modc__fn130
                            local.get 0
                            local.get 1
                            call $dynrt_lib_modc__fn131
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
              call $dynrt_lib_modc__fn169
              local.set 4
            end
            call $dynrt_lib_modc__fn54
            local.get 4
            return
          end
        end
        local.get 3
        local.get 4
        i32.const 942
        i32.const 5
        call $dynrt_lib_modc__fn125
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn130
            global.get $dynrt_lib_modc_global20
            i32.const -1
            i32.eq
            if (result i32)  ;; label = @5
              i32.const -1
            else
              global.get $dynrt_lib_modc_global20
              i32.const 864
              i32.const 4
              call $dynrt_lib_modc__fn112
            end
            local.set 2
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn131
            local.set 3
            local.get 3
            i32.const 40
            i32.eq
            if  ;; label = @5
              block  ;; label = @6
                global.get $dynrt_lib_modc_global19
                i32.const 1
                i32.add
                global.set $dynrt_lib_modc_global19
                call $dynrt_lib_modc_dynArray
                local.set 3
                local.get 3
                call $dynrt_lib_modc__fn53
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn130
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn131
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
                            local.get 3
                            local.get 0
                            local.get 1
                            call $dynrt_lib_modc__fn145
                            call $dynrt_lib_modc_dynPush
                            local.get 0
                            local.get 1
                            call $dynrt_lib_modc__fn130
                            local.get 0
                            local.get 1
                            call $dynrt_lib_modc__fn131
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
                global.get $dynrt_lib_modc_global21
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
                    global.get $dynrt_lib_modc_global20
                    i32.const 947
                    i32.const 12
                    call $dynrt_lib_modc__fn112
                    local.set 4
                    local.get 4
                    i32.const -1
                    i32.ne
                    if  ;; label = @9
                      block  ;; label = @10
                        local.get 4
                        i32.const 959
                        i32.const 6
                        call $dynrt_lib_modc_dynGet
                        local.set 4
                        local.get 4
                        i32.const -1
                        i32.ne
                        if  ;; label = @11
                          block  ;; label = @12
                            local.get 4
                            local.set 5
                            local.get 5
                            i32.const 8
                            i32.add
                            i32.load
                            i32.const 7
                            i32.eq
                            if  ;; label = @13
                              local.get 4
                              local.get 3
                              local.get 2
                              call $dynrt_lib_modc__fn117
                              drop
                            end
                          end
                        end
                      end
                    end
                  end
                end
                call $dynrt_lib_modc__fn54
                call $dynrt_lib_modc_dynUndefined
                return
              end
            end
            local.get 3
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
                call $dynrt_lib_modc__fn148
                global.get $dynrt_lib_modc_global1
                local.set 3
                global.get $dynrt_lib_modc_global2
                local.set 4
                global.get $dynrt_lib_modc_global20
                i32.const -1
                i32.eq
                if (result i32)  ;; label = @7
                  i32.const -1
                else
                  global.get $dynrt_lib_modc_global20
                  i32.const 965
                  i32.const 12
                  call $dynrt_lib_modc__fn112
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
                call $dynrt_lib_modc__fn130
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn131
                i32.const 40
                i32.eq
                if  ;; label = @7
                  block  ;; label = @8
                    global.get $dynrt_lib_modc_global19
                    i32.const 1
                    i32.add
                    global.set $dynrt_lib_modc_global19
                    call $dynrt_lib_modc_dynArray
                    local.set 3
                    local.get 3
                    call $dynrt_lib_modc__fn53
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn130
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn131
                    i32.const 41
                    i32.eq
                    if  ;; label = @9
                      global.get $dynrt_lib_modc_global19
                      i32.const 1
                      i32.add
                      global.set $dynrt_lib_modc_global19
                    else
                      block  ;; label = @10
                        i32.const 1
                        local.set 4
                        block  ;; label = @11
                          loop  ;; label = @12
                            block  ;; label = @13
                              local.get 4
                              i32.const 1
                              i32.eq
                              i32.eqz
                              br_if 2 (;@11;)
                              block  ;; label = @14
                                local.get 3
                                local.get 0
                                local.get 1
                                call $dynrt_lib_modc__fn145
                                call $dynrt_lib_modc_dynPush
                                local.get 0
                                local.get 1
                                call $dynrt_lib_modc__fn130
                                local.get 0
                                local.get 1
                                call $dynrt_lib_modc__fn131
                                local.set 5
                                local.get 5
                                i32.const 44
                                i32.eq
                                if  ;; label = @15
                                  global.get $dynrt_lib_modc_global19
                                  i32.const 1
                                  i32.add
                                  global.set $dynrt_lib_modc_global19
                                else
                                  block  ;; label = @16
                                    local.get 5
                                    i32.const 41
                                    i32.eq
                                    if  ;; label = @17
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
                              br 1 (;@12;)
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
                        local.set 5
                        local.get 5
                        i32.const 8
                        i32.add
                        i32.load
                        i32.const 7
                        i32.eq
                        if  ;; label = @11
                          local.get 6
                          local.get 3
                          local.get 2
                          call $dynrt_lib_modc__fn117
                          local.set 4
                        end
                      end
                    end
                    call $dynrt_lib_modc__fn54
                    local.get 4
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
        call $dynrt_lib_modc__fn130
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn131
        i32.const 61
        i32.eq
        if (result i32)  ;; label = @3
          local.get 0
          local.get 1
          call $dynrt_lib_modc__fn132
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
            call $dynrt_lib_modc__fn164
            global.get $dynrt_lib_modc_global20
            call $dynrt_lib_modc__fn108
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
        call $dynrt_lib_modc__fn112
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
  (func $dynrt_lib_modc__fn136 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn135
    local.set 2
    i32.const 1
    local.set 3
    i32.const -1
    local.set 4
    i32.const 638
    local.set 5
    i32.const 0
    local.tee 15
    local.set 6
    local.get 15
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
            call $dynrt_lib_modc__fn130
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn131
            local.set 8
            i32.const 0
            local.set 9
            local.get 8
            i32.const 63
            i32.eq
            if (result i32)  ;; label = @5
              local.get 0
              local.get 1
              call $dynrt_lib_modc__fn132
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
                call $dynrt_lib_modc__fn130
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn131
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
                    call $dynrt_lib_modc__fn145
                    local.set 9
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn130
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn131
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
                    global.get $dynrt_lib_modc_global19
                    local.tee 12
                    local.set 4
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn131
                    local.set 5
                    block  ;; label = @9
                      loop  ;; label = @10
                        block  ;; label = @11
                          local.get 5
                          i32.const 1
                          call $dynrt_lib_modc__fn129
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
                            call $dynrt_lib_modc__fn131
                            local.set 5
                          end
                          br 1 (;@10;)
                        end
                      end
                    end
                    local.get 0
                    local.get 1
                    local.get 4
                    global.get $dynrt_lib_modc_global19
                    call $dynrt_lib_modc__fn5
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
                  global.get $dynrt_lib_modc_global19
                  local.tee 13
                  i32.const 1
                  i32.add
                  global.set $dynrt_lib_modc_global19
                  local.get 0
                  local.get 1
                  call $dynrt_lib_modc__fn130
                  global.get $dynrt_lib_modc_global19
                  local.tee 14
                  local.set 4
                  local.get 0
                  local.get 1
                  call $dynrt_lib_modc__fn131
                  local.set 5
                  block  ;; label = @8
                    loop  ;; label = @9
                      block  ;; label = @10
                        local.get 5
                        i32.const 1
                        call $dynrt_lib_modc__fn129
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
                          call $dynrt_lib_modc__fn131
                          local.set 5
                        end
                        br 1 (;@9;)
                      end
                    end
                  end
                  local.get 0
                  local.get 1
                  local.get 4
                  global.get $dynrt_lib_modc_global19
                  call $dynrt_lib_modc__fn5
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
                    global.get $dynrt_lib_modc_global19
                    i32.const 1
                    i32.add
                    global.set $dynrt_lib_modc_global19
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn145
                    local.set 8
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn130
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn131
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
                    i32.const 638
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
                      global.get $dynrt_lib_modc_global19
                      i32.const 1
                      i32.add
                      global.set $dynrt_lib_modc_global19
                      local.get 2
                      call $dynrt_lib_modc__fn53
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
                        call $dynrt_lib_modc__fn53
                      end
                      call $dynrt_lib_modc_dynArray
                      local.set 9
                      local.get 9
                      call $dynrt_lib_modc__fn53
                      local.get 0
                      local.get 1
                      call $dynrt_lib_modc__fn130
                      local.get 0
                      local.get 1
                      call $dynrt_lib_modc__fn131
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
                                  call $dynrt_lib_modc__fn145
                                  local.set 11
                                  local.get 9
                                  local.get 11
                                  call $dynrt_lib_modc_dynPush
                                  local.get 0
                                  local.get 1
                                  call $dynrt_lib_modc__fn130
                                  local.get 0
                                  local.get 1
                                  call $dynrt_lib_modc__fn131
                                  local.set 11
                                  local.get 11
                                  i32.const 44
                                  i32.eq
                                  if  ;; label = @16
                                    global.get $dynrt_lib_modc_global19
                                    i32.const 1
                                    i32.add
                                    global.set $dynrt_lib_modc_global19
                                  else
                                    block  ;; label = @17
                                      local.get 11
                                      i32.const 41
                                      i32.eq
                                      if  ;; label = @18
                                        global.get $dynrt_lib_modc_global19
                                        i32.const 1
                                        i32.add
                                        global.set $dynrt_lib_modc_global19
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
                      global.get $dynrt_lib_modc_global21
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
                              call $dynrt_lib_modc__fn92
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
                                call $dynrt_lib_modc__fn93
                                local.set 2
                              else
                                local.get 2
                                local.get 9
                                local.get 4
                                call $dynrt_lib_modc__fn117
                                local.set 2
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
                      call $dynrt_lib_modc__fn54
                      local.get 8
                      i32.const 1
                      i32.eq
                      if  ;; label = @10
                        call $dynrt_lib_modc__fn54
                      end
                      call $dynrt_lib_modc__fn54
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
  (func $dynrt_lib_modc__fn137 (param i32) (result i32)
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
      i32.const 651
      i32.const 9
      call $dynrt_lib_modc_dynString
      return
    end
    local.get 1
    i32.const 2
    i32.eq
    if  ;; label = @1
      i32.const 977
      i32.const 7
      call $dynrt_lib_modc_dynString
      return
    end
    local.get 1
    i32.const 3
    i32.eq
    if  ;; label = @1
      i32.const 984
      i32.const 6
      call $dynrt_lib_modc_dynString
      return
    end
    local.get 1
    i32.const 4
    i32.eq
    if  ;; label = @1
      i32.const 990
      i32.const 6
      call $dynrt_lib_modc_dynString
      return
    end
    local.get 1
    i32.const 7
    i32.eq
    if  ;; label = @1
      i32.const 919
      i32.const 8
      call $dynrt_lib_modc_dynString
      return
    end
    i32.const 996
    i32.const 6
    call $dynrt_lib_modc_dynString
    return)
  (func $dynrt_lib_modc__fn138 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn130
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn131
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
        call $dynrt_lib_modc__fn138
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
        call $dynrt_lib_modc__fn138
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
        call $dynrt_lib_modc__fn138
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
        call $dynrt_lib_modc__fn148
        global.get $dynrt_lib_modc_global1
        local.set 3
        global.get $dynrt_lib_modc_global2
        local.set 4
        local.get 3
        local.get 4
        i32.const 1002
        i32.const 6
        call $dynrt_lib_modc__fn125
        i32.const 1
        i32.eq
        if  ;; label = @3
          local.get 0
          local.get 1
          call $dynrt_lib_modc__fn138
          call $dynrt_lib_modc__fn137
          return
        end
        local.get 2
        global.set $dynrt_lib_modc_global19
      end
    end
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn136
    return)
  (func $dynrt_lib_modc__fn139 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn138
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
            call $dynrt_lib_modc__fn130
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn131
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
                call $dynrt_lib_modc__fn53
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn138
                local.set 5
                call $dynrt_lib_modc__fn54
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
  (func $dynrt_lib_modc__fn140 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn139
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
            call $dynrt_lib_modc__fn130
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn131
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
                call $dynrt_lib_modc__fn53
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn139
                local.set 5
                call $dynrt_lib_modc__fn54
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
  (func $dynrt_lib_modc__fn141 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn140
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
            call $dynrt_lib_modc__fn130
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn131
            local.set 4
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn132
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
                call $dynrt_lib_modc__fn53
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn140
                local.set 6
                call $dynrt_lib_modc__fn54
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
  (func $dynrt_lib_modc__fn142 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn141
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
            call $dynrt_lib_modc__fn130
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn131
            local.set 4
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn132
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
                call $dynrt_lib_modc__fn131
                i32.const 61
                i32.eq
                if  ;; label = @7
                  global.get $dynrt_lib_modc_global19
                  i32.const 1
                  i32.add
                  global.set $dynrt_lib_modc_global19
                end
                local.get 2
                call $dynrt_lib_modc__fn53
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn141
                local.set 4
                call $dynrt_lib_modc__fn54
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
                  call $dynrt_lib_modc__fn131
                  i32.const 61
                  i32.eq
                  if  ;; label = @8
                    global.get $dynrt_lib_modc_global19
                    i32.const 1
                    i32.add
                    global.set $dynrt_lib_modc_global19
                  end
                  local.get 2
                  call $dynrt_lib_modc__fn53
                  local.get 0
                  local.get 1
                  call $dynrt_lib_modc__fn141
                  local.set 4
                  call $dynrt_lib_modc__fn54
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
  (func $dynrt_lib_modc__fn143 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn142
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
            call $dynrt_lib_modc__fn130
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn131
            i32.const 38
            i32.eq
            if (result i32)  ;; label = @5
              local.get 0
              local.get 1
              call $dynrt_lib_modc__fn132
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
                call $dynrt_lib_modc__fn53
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn142
                local.set 6
                call $dynrt_lib_modc__fn54
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
  (func $dynrt_lib_modc__fn144 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn143
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
            call $dynrt_lib_modc__fn130
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn131
            i32.const 124
            i32.eq
            if (result i32)  ;; label = @5
              local.get 0
              local.get 1
              call $dynrt_lib_modc__fn132
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
                call $dynrt_lib_modc__fn53
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn143
                local.set 6
                call $dynrt_lib_modc__fn54
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
              call $dynrt_lib_modc__fn131
              i32.const 63
              i32.eq
              if (result i32)  ;; label = @6
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn132
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
                  call $dynrt_lib_modc__fn53
                  local.get 0
                  local.get 1
                  call $dynrt_lib_modc__fn143
                  local.set 6
                  call $dynrt_lib_modc__fn54
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
  (func $dynrt_lib_modc__fn145 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn144
    local.set 2
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn130
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn131
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
        call $dynrt_lib_modc__fn145
        local.set 4
        local.get 3
        local.tee 6
        global.set $dynrt_lib_modc_global21
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn130
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn131
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
        call $dynrt_lib_modc__fn53
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn145
        local.set 5
        call $dynrt_lib_modc__fn54
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
    call $dynrt_lib_modc__fn145
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
    call $dynrt_lib_modc__fn145
    return)
  (func $dynrt_lib_modc__fn148 (param i32 i32)
    (local i32) (local i32) (local i32) (local i32)
    global.get $dynrt_lib_modc_global19
    local.tee 4
    local.set 2
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn131
    local.set 3
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 3
          i32.const 1
          call $dynrt_lib_modc__fn129
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
            call $dynrt_lib_modc__fn131
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
    call $dynrt_lib_modc__fn5
    local.set 3
    nop
    local.set 2
    local.get 2
    local.tee 5
    global.set $dynrt_lib_modc_global1
    local.get 3
    global.set $dynrt_lib_modc_global2
    return)
  (func $dynrt_lib_modc__fn149 (param i32 i32)
    (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn130
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn148
    global.get $dynrt_lib_modc_global1
    local.set 2
    global.get $dynrt_lib_modc_global2
    local.set 3
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn130
    call $dynrt_lib_modc_dynUndefined
    local.set 4
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn131
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
        call $dynrt_lib_modc__fn145
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
    call $dynrt_lib_modc__fn130
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn131
    i32.const 59
    i32.eq
    if  ;; label = @1
      global.get $dynrt_lib_modc_global19
      i32.const 1
      i32.add
      global.set $dynrt_lib_modc_global19
    end)
  (func $dynrt_lib_modc__fn150 (param i32 i32)
    (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn130
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn131
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
      call $dynrt_lib_modc__fn145
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
    call $dynrt_lib_modc__fn130
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn131
    i32.const 59
    i32.eq
    if  ;; label = @1
      global.get $dynrt_lib_modc_global19
      i32.const 1
      i32.add
      global.set $dynrt_lib_modc_global19
    end)
  (func $dynrt_lib_modc__fn151 (param i32 i32)
    (local i32) (local i32) (local i32) (local i32) (local i32)
    global.get $dynrt_lib_modc_global21
    local.set 2
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn130
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn131
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
    call $dynrt_lib_modc__fn145
    local.set 3
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn130
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn131
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
    call $dynrt_lib_modc__fn170
    local.get 2
    global.set $dynrt_lib_modc_global21
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn130
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn131
    i32.const 0
    call $dynrt_lib_modc__fn129
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_lib_modc_global19
        local.set 4
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn148
        global.get $dynrt_lib_modc_global1
        local.set 5
        global.get $dynrt_lib_modc_global2
        local.set 6
        local.get 5
        local.get 6
        i32.const 1008
        i32.const 4
        call $dynrt_lib_modc__fn125
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
            call $dynrt_lib_modc__fn170
            local.get 2
            global.set $dynrt_lib_modc_global21
          end
        else
          local.get 4
          global.set $dynrt_lib_modc_global19
        end
      end
    end)
  (func $dynrt_lib_modc__fn152 (param i32 i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    global.get $dynrt_lib_modc_global21
    local.set 2
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn130
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn131
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
            call $dynrt_lib_modc__fn145
            local.set 6
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn130
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn131
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
                call $dynrt_lib_modc__fn170
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
                call $dynrt_lib_modc__fn170
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
  (func $dynrt_lib_modc__fn153 (param i32 i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    global.get $dynrt_lib_modc_global21
    local.set 2
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn130
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
            call $dynrt_lib_modc__fn170
            local.get 2
            local.tee 9
            global.set $dynrt_lib_modc_global21
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn130
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn131
            i32.const 0
            call $dynrt_lib_modc__fn129
            i32.const 1
            i32.eq
            if  ;; label = @5
              local.get 0
              local.get 1
              call $dynrt_lib_modc__fn148
            end
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn130
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn131
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
            call $dynrt_lib_modc__fn145
            local.set 4
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn130
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn131
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
            call $dynrt_lib_modc__fn130
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn131
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
  (func $dynrt_lib_modc__fn154 (param i32 i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    global.get $dynrt_lib_modc_global21
    local.set 2
    global.get $dynrt_lib_modc_global20
    local.set 3
    local.get 3
    call $dynrt_lib_modc__fn113
    local.set 4
    local.get 4
    local.tee 13
    global.set $dynrt_lib_modc_global20
    local.get 4
    call $dynrt_lib_modc__fn53
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn130
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn131
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
    call $dynrt_lib_modc__fn130
    i32.const 0
    local.tee 14
    local.set 5
    i32.const 638
    local.set 6
    local.get 14
    local.set 7
    local.get 14
    local.set 8
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn131
    i32.const 0
    call $dynrt_lib_modc__fn129
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn148
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
        i32.const 1012
        i32.const 5
        call $dynrt_lib_modc__fn125
        i32.const 1
        i32.eq
        if (result i32)  ;; label = @3
          i32.const 1
        else
          local.get 9
          local.get 10
          i32.const 1017
          i32.const 3
          call $dynrt_lib_modc__fn125
          i32.const 1
          i32.eq
        end
        if (result i32)  ;; label = @3
          i32.const 1
        else
          local.get 9
          local.get 10
          i32.const 1020
          i32.const 3
          call $dynrt_lib_modc__fn125
          i32.const 1
          i32.eq
        end
        if  ;; label = @3
          block  ;; label = @4
            local.get 9
            local.get 10
            i32.const 1020
            i32.const 3
            call $dynrt_lib_modc__fn125
            i32.const 1
            i32.ne
            if  ;; label = @5
              i32.const 1
              local.set 8
            end
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn130
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn148
            global.get $dynrt_lib_modc_global1
            local.set 11
            global.get $dynrt_lib_modc_global2
            local.set 12
          end
        end
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn130
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn131
        i32.const 0
        call $dynrt_lib_modc__fn129
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn148
            global.get $dynrt_lib_modc_global1
            local.set 9
            global.get $dynrt_lib_modc_global2
            local.set 10
            local.get 9
            local.get 10
            i32.const 1023
            i32.const 2
            call $dynrt_lib_modc__fn125
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
              i32.const 1025
              i32.const 2
              call $dynrt_lib_modc__fn125
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
      call $dynrt_lib_modc__fn156
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
        call $dynrt_lib_modc__fn155
      else
        block  ;; label = @3
          local.get 4
          global.set $dynrt_lib_modc_global19
          local.get 0
          local.get 1
          local.get 2
          local.get 8
          call $dynrt_lib_modc__fn157
        end
      end
    end
    call $dynrt_lib_modc__fn54
    local.get 3
    local.tee 15
    global.set $dynrt_lib_modc_global20)
  (func $dynrt_lib_modc__fn155 (param i32 i32 i32 i32 i32 i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    global.get $dynrt_lib_modc_global20
    local.set 6
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn145
    local.set 7
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn130
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn131
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
        call $dynrt_lib_modc__fn170
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
              call $dynrt_lib_modc__fn113
              local.set 12
            end
            local.get 12
            local.get 2
            local.get 3
            local.get 7
            local.get 11
            call $dynrt_lib_modc__fn87
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
            call $dynrt_lib_modc__fn170
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
  (func $dynrt_lib_modc__fn156 (param i32 i32 i32 i32 i32 i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    global.get $dynrt_lib_modc_global20
    local.set 6
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn145
    local.set 7
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn130
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn131
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
        call $dynrt_lib_modc__fn170
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
              call $dynrt_lib_modc__fn113
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
            call $dynrt_lib_modc__fn170
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
  (func $dynrt_lib_modc__fn157 (param i32 i32 i32 i32)
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
    call $dynrt_lib_modc__fn170
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
      call $dynrt_lib_modc__fn115
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
            call $dynrt_lib_modc__fn130
            i32.const 1
            local.set 10
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn131
            i32.const 59
            i32.ne
            if  ;; label = @5
              local.get 0
              local.get 1
              call $dynrt_lib_modc__fn145
              call $dynrt_lib_modc_dynToBool
              local.set 10
            end
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn130
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn131
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
            call $dynrt_lib_modc__fn131
            i32.const 41
            i32.ne
            if  ;; label = @5
              local.get 0
              local.get 1
              call $dynrt_lib_modc__fn170
            end
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn130
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn131
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
                call $dynrt_lib_modc__fn170
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
                        call $dynrt_lib_modc__fn115
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
                      call $dynrt_lib_modc__fn131
                      i32.const 41
                      i32.ne
                      if  ;; label = @10
                        local.get 0
                        local.get 1
                        call $dynrt_lib_modc__fn170
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
                call $dynrt_lib_modc__fn170
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
  (func $dynrt_lib_modc__fn158 (param i32 i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    global.get $dynrt_lib_modc_global21
    local.set 2
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn130
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn131
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
    call $dynrt_lib_modc__fn145
    local.set 3
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn130
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn131
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
    call $dynrt_lib_modc__fn130
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn131
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
            call $dynrt_lib_modc__fn130
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn131
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
              call $dynrt_lib_modc__fn129
              i32.const 1
              i32.eq
              if  ;; label = @6
                block  ;; label = @7
                  global.get $dynrt_lib_modc_global19
                  local.set 7
                  local.get 0
                  local.get 1
                  call $dynrt_lib_modc__fn148
                  global.get $dynrt_lib_modc_global1
                  local.set 8
                  global.get $dynrt_lib_modc_global2
                  local.set 9
                  local.get 8
                  local.get 9
                  i32.const 1027
                  i32.const 4
                  call $dynrt_lib_modc__fn125
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
                          call $dynrt_lib_modc__fn145
                          local.set 7
                          local.get 0
                          local.get 1
                          call $dynrt_lib_modc__fn130
                          local.get 0
                          local.get 1
                          call $dynrt_lib_modc__fn131
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
                          call $dynrt_lib_modc__fn145
                          drop
                          local.get 7
                          global.set $dynrt_lib_modc_global21
                          local.get 0
                          local.get 1
                          call $dynrt_lib_modc__fn130
                          local.get 0
                          local.get 1
                          call $dynrt_lib_modc__fn131
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
                      call $dynrt_lib_modc__fn159
                    end
                  else
                    local.get 8
                    local.get 9
                    i32.const 1031
                    i32.const 7
                    call $dynrt_lib_modc__fn125
                    i32.const 1
                    i32.eq
                    if  ;; label = @9
                      block  ;; label = @10
                        local.get 0
                        local.get 1
                        call $dynrt_lib_modc__fn130
                        local.get 0
                        local.get 1
                        call $dynrt_lib_modc__fn131
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
                        call $dynrt_lib_modc__fn159
                      end
                    else
                      block  ;; label = @10
                        local.get 7
                        global.set $dynrt_lib_modc_global19
                        local.get 0
                        local.get 1
                        call $dynrt_lib_modc__fn159
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
        call $dynrt_lib_modc__fn160
        local.get 2
        global.set $dynrt_lib_modc_global21
      end
    end
    local.get 3
    global.set $dynrt_lib_modc_global19
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn130
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn131
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
  (func $dynrt_lib_modc__fn159 (param i32 i32)
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
            call $dynrt_lib_modc__fn130
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn131
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
              call $dynrt_lib_modc__fn129
              i32.const 1
              i32.eq
              if  ;; label = @6
                block  ;; label = @7
                  global.get $dynrt_lib_modc_global19
                  local.set 3
                  local.get 0
                  local.get 1
                  call $dynrt_lib_modc__fn148
                  global.get $dynrt_lib_modc_global1
                  local.set 4
                  global.get $dynrt_lib_modc_global2
                  local.set 5
                  local.get 4
                  local.get 5
                  i32.const 1027
                  i32.const 4
                  call $dynrt_lib_modc__fn125
                  i32.const 1
                  i32.eq
                  if (result i32)  ;; label = @8
                    i32.const 1
                  else
                    local.get 4
                    local.get 5
                    i32.const 1031
                    i32.const 7
                    call $dynrt_lib_modc__fn125
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
                      call $dynrt_lib_modc__fn170
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
                  call $dynrt_lib_modc__fn170
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
  (func $dynrt_lib_modc__fn160 (param i32 i32)
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
            call $dynrt_lib_modc__fn130
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn131
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
              call $dynrt_lib_modc__fn129
              i32.const 1
              i32.eq
              if  ;; label = @6
                block  ;; label = @7
                  global.get $dynrt_lib_modc_global19
                  local.set 3
                  local.get 0
                  local.get 1
                  call $dynrt_lib_modc__fn148
                  global.get $dynrt_lib_modc_global1
                  local.set 4
                  global.get $dynrt_lib_modc_global2
                  local.set 5
                  local.get 4
                  local.get 5
                  i32.const 1027
                  i32.const 4
                  call $dynrt_lib_modc__fn125
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
                      call $dynrt_lib_modc__fn145
                      drop
                      local.get 3
                      global.set $dynrt_lib_modc_global21
                      local.get 0
                      local.get 1
                      call $dynrt_lib_modc__fn130
                      local.get 0
                      local.get 1
                      call $dynrt_lib_modc__fn131
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
                    i32.const 1031
                    i32.const 7
                    call $dynrt_lib_modc__fn125
                    i32.const 1
                    i32.eq
                    if  ;; label = @9
                      block  ;; label = @10
                        local.get 0
                        local.get 1
                        call $dynrt_lib_modc__fn130
                        local.get 0
                        local.get 1
                        call $dynrt_lib_modc__fn131
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
                        call $dynrt_lib_modc__fn170
                      end
                    end
                  end
                end
              else
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn170
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
  (func $dynrt_lib_modc__fn161 (param i32 i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    global.get $dynrt_lib_modc_global21
    local.set 2
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn130
    local.get 2
    local.tee 17
    global.set $dynrt_lib_modc_global21
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn170
    local.get 2
    local.tee 18
    global.set $dynrt_lib_modc_global21
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn130
    i32.const 0
    local.tee 19
    local.set 3
    global.get $dynrt_lib_modc_global19
    local.tee 20
    local.set 4
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn131
    i32.const 0
    call $dynrt_lib_modc__fn129
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn148
        global.get $dynrt_lib_modc_global1
        local.set 5
        global.get $dynrt_lib_modc_global2
        local.set 6
        local.get 5
        local.get 6
        i32.const 1038
        i32.const 5
        call $dynrt_lib_modc__fn125
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
        i32.const 638
        local.set 3
        i32.const 0
        local.set 4
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn130
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn131
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
            call $dynrt_lib_modc__fn130
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn148
            global.get $dynrt_lib_modc_global1
            local.set 3
            global.get $dynrt_lib_modc_global2
            local.set 4
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn130
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn131
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
        call $dynrt_lib_modc__fn130
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
            call $dynrt_lib_modc__fn113
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
            call $dynrt_lib_modc__fn53
            i32.const 1
            global.set $dynrt_lib_modc_global21
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn170
            call $dynrt_lib_modc__fn54
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
            call $dynrt_lib_modc__fn170
            local.get 2
            global.set $dynrt_lib_modc_global21
          end
        end
      end
    end
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn130
    i32.const 0
    local.tee 21
    local.set 3
    global.get $dynrt_lib_modc_global19
    local.tee 22
    local.set 4
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn131
    i32.const 0
    call $dynrt_lib_modc__fn129
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn148
        global.get $dynrt_lib_modc_global1
        local.set 5
        global.get $dynrt_lib_modc_global2
        local.set 6
        local.get 5
        local.get 6
        i32.const 1043
        i32.const 7
        call $dynrt_lib_modc__fn125
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
        call $dynrt_lib_modc__fn130
        local.get 2
        local.tee 15
        global.set $dynrt_lib_modc_global21
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn170
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
  (func $dynrt_lib_modc__fn162 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32)
    call $dynrt_lib_modc_dynArray
    local.set 2
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn131
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
        call $dynrt_lib_modc__fn130
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn131
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
                    call $dynrt_lib_modc__fn130
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn148
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
                    call $dynrt_lib_modc__fn130
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn131
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
  (func $dynrt_lib_modc__fn163 (param i32 i32) (result i32)
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
            call $dynrt_lib_modc__fn8
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
    call $dynrt_lib_modc__fn5
    local.set 3
    nop
    local.set 2
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn131
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
  (func $dynrt_lib_modc__fn164 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn130
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn131
    i32.const 123
    i32.eq
    if  ;; label = @1
      local.get 0
      local.get 1
      call $dynrt_lib_modc__fn163
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
    call $dynrt_lib_modc__fn145
    drop
    local.get 3
    global.set $dynrt_lib_modc_global21
    nop
    local.get 0
    local.get 1
    local.get 2
    global.get $dynrt_lib_modc_global19
    call $dynrt_lib_modc__fn5
    call $dynrt_lib_modc_dynString
    return)
  (func $dynrt_lib_modc__fn165 (param i32 i32) (result i32)
    (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn130
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn131
    i32.const 0
    call $dynrt_lib_modc__fn129
    i32.const 1
    i32.eq
    if  ;; label = @1
      local.get 0
      local.get 1
      call $dynrt_lib_modc__fn148
    end
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn130
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn162
    local.set 2
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn130
    i32.const 638
    i32.const 0
    call $dynrt_lib_modc_dynString
    local.set 3
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn131
    i32.const 123
    i32.eq
    if  ;; label = @1
      local.get 0
      local.get 1
      call $dynrt_lib_modc__fn163
      local.set 3
    end
    local.get 2
    local.get 3
    global.get $dynrt_lib_modc_global20
    call $dynrt_lib_modc__fn108
    return)
  (func $dynrt_lib_modc__fn166 (param i32 i32) (result i32)
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
            call $dynrt_lib_modc__fn8
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
    call $dynrt_lib_modc__fn130
    i32.const 0
    local.tee 15
    local.set 3
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn131
    i32.const 61
    i32.eq
    if (result i32)  ;; label = @1
      local.get 0
      local.get 1
      call $dynrt_lib_modc__fn132
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
  (func $dynrt_lib_modc__fn167 (param i32 i32)
    (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn130
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn148
    global.get $dynrt_lib_modc_global1
    local.set 2
    global.get $dynrt_lib_modc_global2
    local.set 3
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn130
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn162
    local.set 4
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn130
    i32.const 638
    i32.const 0
    call $dynrt_lib_modc_dynString
    local.set 5
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn131
    i32.const 123
    i32.eq
    if  ;; label = @1
      local.get 0
      local.get 1
      call $dynrt_lib_modc__fn163
      local.set 5
    end
    local.get 4
    local.get 5
    global.get $dynrt_lib_modc_global20
    call $dynrt_lib_modc__fn108
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
  (func $dynrt_lib_modc__fn168 (param i32 i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn130
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn148
    global.get $dynrt_lib_modc_global1
    local.set 2
    global.get $dynrt_lib_modc_global2
    local.set 3
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn130
    i32.const -1
    local.tee 29
    local.set 4
    local.get 29
    local.set 5
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn131
    i32.const 0
    call $dynrt_lib_modc__fn129
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn148
        global.get $dynrt_lib_modc_global1
        local.set 6
        global.get $dynrt_lib_modc_global2
        local.set 7
        local.get 6
        local.get 7
        i32.const 1050
        i32.const 7
        call $dynrt_lib_modc__fn125
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn130
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn148
            global.get $dynrt_lib_modc_global1
            local.set 6
            global.get $dynrt_lib_modc_global2
            local.set 7
            global.get $dynrt_lib_modc_global20
            i32.const -1
            i32.eq
            if (result i32)  ;; label = @5
              i32.const -1
            else
              global.get $dynrt_lib_modc_global20
              local.get 6
              local.get 7
              call $dynrt_lib_modc__fn112
            end
            local.set 6
            local.get 6
            i32.const -1
            i32.ne
            if  ;; label = @5
              block  ;; label = @6
                local.get 6
                local.tee 20
                local.set 4
                local.get 6
                i32.const 1057
                i32.const 7
                call $dynrt_lib_modc_dynGet
                local.set 6
                local.get 6
                i32.const -1
                i32.ne
                if  ;; label = @7
                  local.get 6
                  local.set 5
                end
              end
            end
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn130
          end
        end
      end
    end
    call $dynrt_lib_modc_dynObject
    local.set 6
    local.get 5
    i32.const -1
    i32.ne
    if  ;; label = @1
      block  ;; label = @2
        local.get 6
        local.set 7
        local.get 7
        i32.const 8
        i32.add
        i32.const 8
        i32.add
        local.get 5
        i32.store
      end
    end
    call $dynrt_lib_modc_dynObject
    local.set 7
    global.get $dynrt_lib_modc_global20
    call $dynrt_lib_modc__fn113
    local.set 8
    local.get 5
    i32.const -1
    i32.ne
    if  ;; label = @1
      local.get 8
      i32.const 965
      i32.const 12
      local.get 5
      call $dynrt_lib_modc_dynSet
    end
    local.get 4
    i32.const -1
    i32.ne
    if  ;; label = @1
      local.get 8
      i32.const 947
      i32.const 12
      local.get 4
      call $dynrt_lib_modc_dynSet
    end
    i32.const 638
    local.tee 30
    local.set 5
    i32.const 0
    local.tee 31
    local.set 9
    i32.const -1
    local.tee 32
    local.set 10
    local.get 30
    local.set 11
    local.get 31
    local.set 12
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn131
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
    call $dynrt_lib_modc__fn130
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 0
          local.get 1
          call $dynrt_lib_modc__fn131
          i32.const 125
          i32.ne
          if (result i32)  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn131
            i32.const -1
            i32.ne
          else
            i32.const 0
          end
          i32.eqz
          br_if 2 (;@1;)
          local.get 0
          local.get 1
          call $dynrt_lib_modc__fn131
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
              call $dynrt_lib_modc__fn130
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
              call $dynrt_lib_modc__fn148
              global.get $dynrt_lib_modc_global1
              local.set 15
              global.get $dynrt_lib_modc_global2
              local.set 16
              local.get 0
              local.get 1
              call $dynrt_lib_modc__fn130
              local.get 15
              local.get 16
              i32.const 1064
              i32.const 6
              call $dynrt_lib_modc__fn125
              i32.const 1
              i32.eq
              if (result i32)  ;; label = @6
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn131
                i32.const 0
                call $dynrt_lib_modc__fn129
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
                  call $dynrt_lib_modc__fn148
                  global.get $dynrt_lib_modc_global1
                  local.set 15
                  global.get $dynrt_lib_modc_global2
                  local.set 16
                  local.get 0
                  local.get 1
                  call $dynrt_lib_modc__fn130
                end
              end
              local.get 15
              local.get 16
              i32.const 1070
              i32.const 3
              call $dynrt_lib_modc__fn125
              i32.const 1
              i32.eq
              if (result i32)  ;; label = @6
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn131
                i32.const 0
                call $dynrt_lib_modc__fn129
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
                  call $dynrt_lib_modc__fn148
                  global.get $dynrt_lib_modc_global1
                  local.set 15
                  global.get $dynrt_lib_modc_global2
                  local.set 16
                  local.get 0
                  local.get 1
                  call $dynrt_lib_modc__fn130
                end
              else
                local.get 15
                local.get 16
                i32.const 1073
                i32.const 3
                call $dynrt_lib_modc__fn125
                i32.const 1
                i32.eq
                if (result i32)  ;; label = @7
                  local.get 0
                  local.get 1
                  call $dynrt_lib_modc__fn131
                  i32.const 0
                  call $dynrt_lib_modc__fn129
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
                    call $dynrt_lib_modc__fn148
                    global.get $dynrt_lib_modc_global1
                    local.set 15
                    global.get $dynrt_lib_modc_global2
                    local.set 16
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn130
                  end
                end
              end
              local.get 0
              local.get 1
              call $dynrt_lib_modc__fn131
              local.set 17
              local.get 17
              i32.const 40
              i32.eq
              if  ;; label = @6
                block  ;; label = @7
                  local.get 0
                  local.get 1
                  call $dynrt_lib_modc__fn162
                  local.set 17
                  local.get 0
                  local.get 1
                  call $dynrt_lib_modc__fn130
                  local.get 0
                  local.get 1
                  call $dynrt_lib_modc__fn163
                  local.set 18
                  local.get 15
                  local.get 16
                  i32.const 1076
                  i32.const 11
                  call $dynrt_lib_modc__fn125
                  i32.const 1
                  i32.eq
                  if  ;; label = @8
                    block  ;; label = @9
                      local.get 17
                      local.set 10
                      local.get 18
                      call $dynrt_lib_modc__fn77
                      global.get $dynrt_lib_modc_global1
                      local.set 5
                      global.get $dynrt_lib_modc_global2
                      local.set 9
                    end
                  else
                    block  ;; label = @9
                      local.get 17
                      local.get 18
                      local.get 8
                      call $dynrt_lib_modc__fn108
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
                          i32.const 901
                          local.set 18
                          i32.const 6
                          local.set 19
                          local.get 18
                          local.get 19
                          local.get 15
                          local.get 16
                          call $dynrt_lib_modc__fn4
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
                            i32.const 913
                            local.set 18
                            i32.const 6
                            local.set 19
                            local.get 18
                            local.get 19
                            local.get 15
                            local.get 16
                            call $dynrt_lib_modc__fn4
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
                        local.get 7
                        local.get 18
                        local.get 19
                        local.get 17
                        call $dynrt_lib_modc_dynSet
                      else
                        local.get 6
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
                          global.get $dynrt_lib_modc_global19
                          i32.const 1
                          i32.add
                          global.set $dynrt_lib_modc_global19
                          local.get 0
                          local.get 1
                          call $dynrt_lib_modc__fn145
                          local.set 13
                        end
                      end
                      global.get $dynrt_lib_modc_global21
                      i32.const 1
                      i32.eq
                      if  ;; label = @10
                        local.get 7
                        local.get 15
                        local.get 16
                        local.get 13
                        call $dynrt_lib_modc_dynSet
                      end
                    end
                  else
                    block  ;; label = @9
                      i32.const 651
                      local.set 13
                      i32.const 9
                      local.set 14
                      local.get 17
                      i32.const 61
                      i32.eq
                      if  ;; label = @10
                        block  ;; label = @11
                          global.get $dynrt_lib_modc_global19
                          local.tee 21
                          i32.const 1
                          i32.add
                          global.set $dynrt_lib_modc_global19
                          local.get 0
                          local.get 1
                          call $dynrt_lib_modc__fn130
                          global.get $dynrt_lib_modc_global19
                          local.tee 22
                          local.set 13
                          global.get $dynrt_lib_modc_global21
                          local.set 14
                          i32.const 0
                          global.set $dynrt_lib_modc_global21
                          local.get 0
                          local.get 1
                          call $dynrt_lib_modc__fn145
                          drop
                          local.get 14
                          global.set $dynrt_lib_modc_global21
                          local.get 0
                          local.get 1
                          local.get 13
                          global.get $dynrt_lib_modc_global19
                          call $dynrt_lib_modc__fn5
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
                      i32.const 1087
                      i32.const 5
                      call $dynrt_lib_modc__fn4
                      local.set 12
                      nop
                      local.set 11
                      local.get 11
                      local.get 12
                      local.get 15
                      local.get 16
                      call $dynrt_lib_modc__fn4
                      local.set 12
                      nop
                      local.set 11
                      local.get 11
                      local.get 12
                      i32.const 1092
                      i32.const 3
                      call $dynrt_lib_modc__fn4
                      local.set 12
                      nop
                      local.set 11
                      local.get 11
                      local.get 12
                      local.get 13
                      local.get 14
                      call $dynrt_lib_modc__fn4
                      local.set 12
                      nop
                      local.set 11
                      local.get 11
                      local.get 12
                      i32.const 1095
                      i32.const 2
                      call $dynrt_lib_modc__fn4
                      local.set 12
                      nop
                      local.set 11
                    end
                  end
                  local.get 0
                  local.get 1
                  call $dynrt_lib_modc__fn130
                  local.get 0
                  local.get 1
                  call $dynrt_lib_modc__fn131
                  i32.const 59
                  i32.eq
                  if  ;; label = @8
                    global.get $dynrt_lib_modc_global19
                    i32.const 1
                    i32.add
                    global.set $dynrt_lib_modc_global19
                  end
                end
              end
              local.get 0
              local.get 1
              call $dynrt_lib_modc__fn130
            end
          end
          br 1 (;@2;)
        end
      end
    end
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn131
    i32.const 125
    i32.eq
    if  ;; label = @1
      global.get $dynrt_lib_modc_global19
      i32.const 1
      i32.add
      global.set $dynrt_lib_modc_global19
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
        local.get 5
        local.get 9
        call $dynrt_lib_modc__fn4
        local.set 12
        nop
        local.set 11
        local.get 10
        local.get 11
        local.get 12
        call $dynrt_lib_modc_dynString
        local.get 8
        call $dynrt_lib_modc__fn108
        local.set 5
        local.get 7
        i32.const 959
        i32.const 6
        local.get 5
        call $dynrt_lib_modc_dynSet
      end
    end
    local.get 7
    i32.const 1057
    i32.const 7
    local.get 6
    call $dynrt_lib_modc_dynSet
    local.get 4
    i32.const -1
    i32.ne
    if  ;; label = @1
      local.get 7
      i32.const 947
      i32.const 12
      local.get 4
      call $dynrt_lib_modc_dynSet
    end
    global.get $dynrt_lib_modc_global21
    i32.const 1
    i32.eq
    if  ;; label = @1
      global.get $dynrt_lib_modc_global20
      local.get 2
      local.get 3
      local.get 7
      call $dynrt_lib_modc_dynSet
    end)
  (func $dynrt_lib_modc__fn169 (param i32 i32) (result i32)
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
    i32.const 1057
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
    i32.const 959
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
          call $dynrt_lib_modc__fn117
          drop
        end
      end
    end
    local.get 2
    return)
  (func $dynrt_lib_modc__fn170 (param i32 i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn130
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn131
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
        call $dynrt_lib_modc__fn113
        local.set 3
        local.get 3
        local.tee 14
        global.set $dynrt_lib_modc_global20
        local.get 3
        call $dynrt_lib_modc__fn53
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn171
        call $dynrt_lib_modc__fn54
        local.get 2
        local.tee 15
        global.set $dynrt_lib_modc_global20
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn130
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn131
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
    call $dynrt_lib_modc__fn129
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_lib_modc_global19
        local.set 2
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn148
        global.get $dynrt_lib_modc_global1
        local.set 3
        global.get $dynrt_lib_modc_global2
        local.set 4
        local.get 3
        local.get 4
        i32.const 1017
        i32.const 3
        call $dynrt_lib_modc__fn125
        i32.const 1
        i32.eq
        if (result i32)  ;; label = @3
          i32.const 1
        else
          local.get 3
          local.get 4
          i32.const 1012
          i32.const 5
          call $dynrt_lib_modc__fn125
          i32.const 1
          i32.eq
        end
        if (result i32)  ;; label = @3
          i32.const 1
        else
          local.get 3
          local.get 4
          i32.const 1020
          i32.const 3
          call $dynrt_lib_modc__fn125
          i32.const 1
          i32.eq
        end
        if  ;; label = @3
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn149
            return
          end
        end
        local.get 3
        local.get 4
        i32.const 1097
        i32.const 2
        call $dynrt_lib_modc__fn125
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn151
            return
          end
        end
        local.get 3
        local.get 4
        i32.const 1099
        i32.const 5
        call $dynrt_lib_modc__fn125
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
        i32.const 1104
        i32.const 2
        call $dynrt_lib_modc__fn125
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
        i32.const 1106
        i32.const 3
        call $dynrt_lib_modc__fn125
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn154
            return
          end
        end
        local.get 3
        local.get 4
        i32.const 1109
        i32.const 6
        call $dynrt_lib_modc__fn125
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn158
            return
          end
        end
        local.get 3
        local.get 4
        i32.const 1115
        i32.const 3
        call $dynrt_lib_modc__fn125
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn161
            return
          end
        end
        local.get 3
        local.get 4
        i32.const 1118
        i32.const 5
        call $dynrt_lib_modc__fn125
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn145
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
            call $dynrt_lib_modc__fn130
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn131
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
        i32.const 1123
        i32.const 6
        call $dynrt_lib_modc__fn125
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn150
            return
          end
        end
        local.get 3
        local.get 4
        i32.const 919
        i32.const 8
        call $dynrt_lib_modc__fn125
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn167
            return
          end
        end
        local.get 3
        local.get 4
        i32.const 1129
        i32.const 5
        call $dynrt_lib_modc__fn125
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn168
            return
          end
        end
        local.get 3
        local.get 4
        i32.const 1134
        i32.const 5
        call $dynrt_lib_modc__fn125
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
            call $dynrt_lib_modc__fn130
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn131
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
        i32.const 1139
        i32.const 8
        call $dynrt_lib_modc__fn125
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
            call $dynrt_lib_modc__fn130
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn131
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
        call $dynrt_lib_modc__fn130
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn131
        local.set 5
        local.get 5
        i32.const 61
        i32.eq
        if (result i32)  ;; label = @3
          local.get 0
          local.get 1
          call $dynrt_lib_modc__fn132
          i32.const 61
          i32.ne
        else
          i32.const 0
        end
        if (result i32)  ;; label = @3
          local.get 0
          local.get 1
          call $dynrt_lib_modc__fn132
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
            call $dynrt_lib_modc__fn145
            local.set 2
            global.get $dynrt_lib_modc_global21
            i32.const 1
            i32.eq
            if  ;; label = @5
              global.get $dynrt_lib_modc_global20
              local.get 3
              local.get 4
              local.get 2
              call $dynrt_lib_modc__fn114
            end
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn130
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn131
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
          call $dynrt_lib_modc__fn132
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
                call $dynrt_lib_modc__fn112
                local.set 5
                global.get $dynrt_lib_modc_global20
                local.get 3
                local.get 4
                local.get 5
                f64.const 0x1.0p+0 (;=1;)
                call $dynrt_lib_modc_dynNumber
                call $dynrt_lib_modc_dynAdd
                call $dynrt_lib_modc__fn114
              end
            end
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn130
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn131
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
          call $dynrt_lib_modc__fn132
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
                call $dynrt_lib_modc__fn112
                local.set 5
                global.get $dynrt_lib_modc_global20
                local.get 3
                local.get 4
                local.get 5
                f64.const 0x1.0p+0 (;=1;)
                call $dynrt_lib_modc_dynNumber
                call $dynrt_lib_modc_dynSub
                call $dynrt_lib_modc__fn114
              end
            end
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn130
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn131
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
          call $dynrt_lib_modc__fn132
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
            call $dynrt_lib_modc__fn145
            local.set 6
            global.get $dynrt_lib_modc_global21
            i32.const 1
            i32.eq
            if  ;; label = @5
              block  ;; label = @6
                global.get $dynrt_lib_modc_global20
                local.get 3
                local.get 4
                call $dynrt_lib_modc__fn112
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
                call $dynrt_lib_modc__fn114
              end
            end
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn130
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn131
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
              call $dynrt_lib_modc__fn112
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
                    call $dynrt_lib_modc__fn130
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn131
                    local.set 6
                    i32.const 0
                    local.tee 19
                    local.set 7
                    i32.const 638
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
                        call $dynrt_lib_modc__fn148
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
                          call $dynrt_lib_modc__fn145
                          local.set 10
                          local.get 0
                          local.get 1
                          call $dynrt_lib_modc__fn130
                          local.get 0
                          local.get 1
                          call $dynrt_lib_modc__fn131
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
                        call $dynrt_lib_modc__fn130
                        local.get 0
                        local.get 1
                        call $dynrt_lib_modc__fn131
                        local.set 11
                        local.get 0
                        local.get 1
                        call $dynrt_lib_modc__fn132
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
                            call $dynrt_lib_modc__fn145
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
                                  call $dynrt_lib_modc__fn127
                                else
                                  local.get 3
                                  local.get 10
                                  local.get 5
                                  call $dynrt_lib_modc__fn94
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
                call $dynrt_lib_modc__fn130
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn131
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
            call $dynrt_lib_modc__fn145
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
            call $dynrt_lib_modc__fn130
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn131
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
        call $dynrt_lib_modc__fn145
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
        call $dynrt_lib_modc__fn130
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn131
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
    call $dynrt_lib_modc__fn145
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
    call $dynrt_lib_modc__fn130
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn131
    i32.const 59
    i32.eq
    if  ;; label = @1
      global.get $dynrt_lib_modc_global19
      i32.const 1
      i32.add
      global.set $dynrt_lib_modc_global19
    end)
  (func $dynrt_lib_modc__fn171 (param i32 i32)
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
            call $dynrt_lib_modc__fn130
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn131
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
                call $dynrt_lib_modc__fn65
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
                call $dynrt_lib_modc__fn170
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
    call $dynrt_lib_modc__fn53
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
    call $dynrt_lib_modc__fn171
    global.get $dynrt_lib_modc_global23
    i32.const 1
    i32.eq
    if (result i32)  ;; label = @1
      global.get $dynrt_lib_modc_global24
    else
      global.get $dynrt_lib_modc_global25
    end
    local.set 3
    call $dynrt_lib_modc__fn54
    local.get 3
    return)
  ;; data from dynrt_lib_modc
  (data (;0;) (i32.const 638) "")
  (data (;1;) (i32.const 638) "false")
  (data (;2;) (i32.const 643) "true")
  (data (;3;) (i32.const 647) "null")
  (data (;4;) (i32.const 651) "undefined")
  (data (;5;) (i32.const 660) "push")
  (data (;6;) (i32.const 664) "indexOf")
  (data (;7;) (i32.const 671) "includes")
  (data (;8;) (i32.const 679) "join")
  (data (;9;) (i32.const 683) ",")
  (data (;10;) (i32.const 684) "slice")
  (data (;11;) (i32.const 689) "concat")
  (data (;12;) (i32.const 695) "reverse")
  (data (;13;) (i32.const 702) "pop")
  (data (;14;) (i32.const 705) "shift")
  (data (;15;) (i32.const 710) "unshift")
  (data (;16;) (i32.const 717) "at")
  (data (;17;) (i32.const 719) "lastIndexOf")
  (data (;18;) (i32.const 730) "map")
  (data (;19;) (i32.const 733) "filter")
  (data (;20;) (i32.const 739) "forEach")
  (data (;21;) (i32.const 746) "reduce")
  (data (;22;) (i32.const 752) "find")
  (data (;23;) (i32.const 756) "findIndex")
  (data (;24;) (i32.const 765) "some")
  (data (;25;) (i32.const 769) "every")
  (data (;26;) (i32.const 774) "sort")
  (data (;27;) (i32.const 778) "charAt")
  (data (;28;) (i32.const 784) "charCodeAt")
  (data (;29;) (i32.const 794) "toUpperCase")
  (data (;30;) (i32.const 805) "toLowerCase")
  (data (;31;) (i32.const 816) "trim")
  (data (;32;) (i32.const 820) "startsWith")
  (data (;33;) (i32.const 830) "endsWith")
  (data (;34;) (i32.const 838) "repeat")
  (data (;35;) (i32.const 844) "padStart")
  (data (;36;) (i32.const 852) " ")
  (data (;37;) (i32.const 853) "padEnd")
  (data (;38;) (i32.const 859) "split")
  (data (;39;) (i32.const 864) "this")
  (data (;40;) (i32.const 868) "abs")
  (data (;41;) (i32.const 871) "sqrt")
  (data (;42;) (i32.const 875) "floor")
  (data (;43;) (i32.const 880) "ceil")
  (data (;44;) (i32.const 884) "round")
  (data (;45;) (i32.const 889) "min")
  (data (;46;) (i32.const 892) "max")
  (data (;47;) (i32.const 895) "len")
  (data (;48;) (i32.const 898) "inc")
  (data (;49;) (i32.const 901) "__get_")
  (data (;50;) (i32.const 907) "length")
  (data (;51;) (i32.const 913) "__set_")
  (data (;52;) (i32.const 919) "function")
  (data (;53;) (i32.const 927) "Object")
  (data (;54;) (i32.const 933) "create")
  (data (;55;) (i32.const 939) "new")
  (data (;56;) (i32.const 942) "super")
  (data (;57;) (i32.const 947) "__superclass")
  (data (;58;) (i32.const 959) "__ctor")
  (data (;59;) (i32.const 965) "__superproto")
  (data (;60;) (i32.const 977) "boolean")
  (data (;61;) (i32.const 984) "number")
  (data (;62;) (i32.const 990) "string")
  (data (;63;) (i32.const 996) "object")
  (data (;64;) (i32.const 1002) "typeof")
  (data (;65;) (i32.const 1008) "else")
  (data (;66;) (i32.const 1012) "const")
  (data (;67;) (i32.const 1017) "let")
  (data (;68;) (i32.const 1020) "var")
  (data (;69;) (i32.const 1023) "of")
  (data (;70;) (i32.const 1025) "in")
  (data (;71;) (i32.const 1027) "case")
  (data (;72;) (i32.const 1031) "default")
  (data (;73;) (i32.const 1038) "catch")
  (data (;74;) (i32.const 1043) "finally")
  (data (;75;) (i32.const 1050) "extends")
  (data (;76;) (i32.const 1057) "__proto")
  (data (;77;) (i32.const 1064) "static")
  (data (;78;) (i32.const 1070) "get")
  (data (;79;) (i32.const 1073) "set")
  (data (;80;) (i32.const 1076) "constructor")
  (data (;81;) (i32.const 1087) "this.")
  (data (;82;) (i32.const 1092) " = ")
  (data (;83;) (i32.const 1095) "; ")
  (data (;84;) (i32.const 1097) "if")
  (data (;85;) (i32.const 1099) "while")
  (data (;86;) (i32.const 1104) "do")
  (data (;87;) (i32.const 1106) "for")
  (data (;88;) (i32.const 1109) "switch")
  (data (;89;) (i32.const 1115) "try")
  (data (;90;) (i32.const 1118) "throw")
  (data (;91;) (i32.const 1123) "return")
  (data (;92;) (i32.const 1129) "class")
  (data (;93;) (i32.const 1134) "break")
  (data (;94;) (i32.const 1139) "continue")
)