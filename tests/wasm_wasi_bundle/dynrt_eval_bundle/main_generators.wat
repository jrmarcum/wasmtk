(module
  (import "wasi_snapshot_preview1" "proc_exit" (func $proc_exit (param i32)))
  (import "wasi_snapshot_preview1" "fd_write" (func $fd_write (param i32 i32 i32 i32) (result i32)))
  ;; imports from dynrt_lib_modc
  (import "env" "__host_call" (func $dynrt_lib_modc___host_call (param i32 i32) (result i32)))
  (memory (export "memory") 2)
  (global $__heap_ptr (mut i32) (i32.const 2670))
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

  (func $checkRun (param $src_ptr i32) (param $src_len i32) (param $expected f64) 
    (local $e i32)
    (local $r i32)
    (local.set $e (call $dynrt_lib_modc_dynObject ))
    (local.set $r (call $dynrt_lib_modc_dynRun (local.get $src_ptr) (local.get $src_len) (local.get $e)))
    (call $check (if (result i32) (i32.eq (call $dynrt_lib_modc_dynTypeof (local.get $r)) (i32.const 3)) (then (i32.const 1)) (else (i32.const 0))))
    (call $check (if (result i32) (f64.eq (call $dynrt_lib_modc_dynNumberValue (local.get $r)) (local.get $expected)) (then (i32.const 1)) (else (i32.const 0))))
  )
  (func $_start (export "_start")
    (local $__iface_tmp i32)
    (global.set $guard (call $__malloc (i32.const 40)))
      (i32.store (global.get $guard) (i32.const 1))
      (i32.store offset=4 (global.get $guard) (i32.const 8))
      (i32.store offset=8 (global.get $guard) (i32.const 0))
    (call $checkRun (i32.const 260) (i32.const 84) (f64.const 1))
    (call $checkRun (i32.const 344) (i32.const 88) (f64.const 20))
    (call $checkRun (i32.const 432) (i32.const 88) (f64.const 100))
    (call $checkRun (i32.const 520) (i32.const 99) (f64.const 1))
    (call $checkRun (i32.const 619) (i32.const 64) (f64.const 1))
    (call $checkRun (i32.const 683) (i32.const 109) (f64.const 6))
    (call $checkRun (i32.const 792) (i32.const 110) (f64.const 4))
    (call $checkRun (i32.const 902) (i32.const 141) (f64.const 6))
    (call $checkRun (i32.const 1043) (i32.const 150) (f64.const 14))
    (call $checkRun (i32.const 1193) (i32.const 121) (f64.const 14))
    (call $checkRun (i32.const 1314) (i32.const 154) (f64.const 6))
    (call $checkRun (i32.const 1468) (i32.const 167) (f64.const 90))
        (i32.store (i32.const 0) (i32.const 1635))
          (i32.store (i32.const 4) (i32.const 41))
          (drop (call $fd_write
            (i32.const 1)
            (i32.const 0)
            (i32.const 1)
            (i32.const 128)))
    (call $proc_exit (i32.const 0))
  )
  (data (i32.const 260) "\66\75\6e\63\74\69\6f\6e\2a\20\67\28\29\20\7b\20\79\69\65\6c\64\20\31\3b\20\79\69\65\6c\64\20\32\3b\20\79\69\65\6c\64\20\33\3b\20\7d\20\63\6f\6e\73\74\20\69\74\20\3d\20\67\28\29\3b\20\72\65\74\75\72\6e\20\69\74\2e\6e\65\78\74\28\29\2e\76\61\6c\75\65\3b")
  (data (i32.const 344) "\66\75\6e\63\74\69\6f\6e\2a\20\67\28\29\20\7b\20\79\69\65\6c\64\20\31\30\3b\20\79\69\65\6c\64\20\32\30\3b\20\7d\20\63\6f\6e\73\74\20\69\74\20\3d\20\67\28\29\3b\20\69\74\2e\6e\65\78\74\28\29\3b\20\72\65\74\75\72\6e\20\69\74\2e\6e\65\78\74\28\29\2e\76\61\6c\75\65\3b")
  (data (i32.const 432) "\66\75\6e\63\74\69\6f\6e\2a\20\67\28\29\20\7b\20\79\69\65\6c\64\20\31\3b\20\7d\20\63\6f\6e\73\74\20\69\74\20\3d\20\67\28\29\3b\20\69\74\2e\6e\65\78\74\28\29\3b\20\72\65\74\75\72\6e\20\69\74\2e\6e\65\78\74\28\29\2e\64\6f\6e\65\20\3f\20\31\30\30\20\3a\20\32\30\30\3b")
  (data (i32.const 520) "\66\75\6e\63\74\69\6f\6e\2a\20\67\28\29\20\7b\20\79\69\65\6c\64\20\31\3b\20\7d\20\63\6f\6e\73\74\20\69\74\20\3d\20\67\28\29\3b\20\69\74\2e\6e\65\78\74\28\29\3b\20\72\65\74\75\72\6e\20\69\74\2e\6e\65\78\74\28\29\2e\76\61\6c\75\65\20\3d\3d\3d\20\75\6e\64\65\66\69\6e\65\64\20\3f\20\31\20\3a\20\30\3b")
  (data (i32.const 619) "\66\75\6e\63\74\69\6f\6e\2a\20\67\28\29\20\7b\20\7d\20\63\6f\6e\73\74\20\69\74\20\3d\20\67\28\29\3b\20\72\65\74\75\72\6e\20\69\74\2e\6e\65\78\74\28\29\2e\64\6f\6e\65\20\3f\20\31\20\3a\20\30\3b")
  (data (i32.const 683) "\66\75\6e\63\74\69\6f\6e\2a\20\67\28\29\20\7b\20\79\69\65\6c\64\20\31\3b\20\79\69\65\6c\64\20\32\3b\20\79\69\65\6c\64\20\33\3b\20\7d\20\6c\65\74\20\73\75\6d\20\3d\20\30\3b\20\66\6f\72\20\28\63\6f\6e\73\74\20\78\20\6f\66\20\67\28\29\29\20\7b\20\73\75\6d\20\3d\20\73\75\6d\20\2b\20\78\3b\20\7d\20\72\65\74\75\72\6e\20\73\75\6d\3b")
  (data (i32.const 792) "\66\75\6e\63\74\69\6f\6e\2a\20\67\28\29\20\7b\20\79\69\65\6c\64\20\31\3b\20\79\69\65\6c\64\20\32\3b\20\79\69\65\6c\64\20\33\3b\20\79\69\65\6c\64\20\34\3b\20\7d\20\6c\65\74\20\6e\20\3d\20\30\3b\20\66\6f\72\20\28\63\6f\6e\73\74\20\78\20\6f\66\20\67\28\29\29\20\7b\20\6e\20\3d\20\6e\20\2b\20\31\3b\20\7d\20\72\65\74\75\72\6e\20\6e\3b")
  (data (i32.const 902) "\66\75\6e\63\74\69\6f\6e\2a\20\72\61\6e\67\65\28\6e\29\20\7b\20\6c\65\74\20\69\20\3d\20\30\3b\20\77\68\69\6c\65\20\28\69\20\3c\20\6e\29\20\7b\20\79\69\65\6c\64\20\69\3b\20\69\20\3d\20\69\20\2b\20\31\3b\20\7d\20\7d\20\6c\65\74\20\73\75\6d\20\3d\20\30\3b\20\66\6f\72\20\28\63\6f\6e\73\74\20\78\20\6f\66\20\72\61\6e\67\65\28\34\29\29\20\7b\20\73\75\6d\20\3d\20\73\75\6d\20\2b\20\78\3b\20\7d\20\72\65\74\75\72\6e\20\73\75\6d\3b")
  (data (i32.const 1043) "\66\75\6e\63\74\69\6f\6e\2a\20\73\71\75\61\72\65\73\28\6e\29\20\7b\20\6c\65\74\20\69\20\3d\20\31\3b\20\77\68\69\6c\65\20\28\69\20\3c\3d\20\6e\29\20\7b\20\79\69\65\6c\64\20\69\20\2a\20\69\3b\20\69\20\3d\20\69\20\2b\20\31\3b\20\7d\20\7d\20\6c\65\74\20\73\75\6d\20\3d\20\30\3b\20\66\6f\72\20\28\63\6f\6e\73\74\20\78\20\6f\66\20\73\71\75\61\72\65\73\28\33\29\29\20\7b\20\73\75\6d\20\3d\20\73\75\6d\20\2b\20\78\3b\20\7d\20\72\65\74\75\72\6e\20\73\75\6d\3b")
  (data (i32.const 1193) "\66\75\6e\63\74\69\6f\6e\2a\20\67\28\61\2c\20\62\29\20\7b\20\79\69\65\6c\64\20\61\3b\20\79\69\65\6c\64\20\62\3b\20\79\69\65\6c\64\20\61\20\2b\20\62\3b\20\7d\20\6c\65\74\20\73\75\6d\20\3d\20\30\3b\20\66\6f\72\20\28\63\6f\6e\73\74\20\78\20\6f\66\20\67\28\33\2c\20\34\29\29\20\7b\20\73\75\6d\20\3d\20\73\75\6d\20\2b\20\78\3b\20\7d\20\72\65\74\75\72\6e\20\73\75\6d\3b")
  (data (i32.const 1314) "\66\75\6e\63\74\69\6f\6e\2a\20\67\28\6e\29\20\7b\20\6c\65\74\20\69\20\3d\20\30\3b\20\77\68\69\6c\65\20\28\69\20\3c\20\6e\29\20\7b\20\69\66\20\28\69\20\25\20\32\20\3d\3d\3d\20\30\29\20\7b\20\79\69\65\6c\64\20\69\3b\20\7d\20\69\20\3d\20\69\20\2b\20\31\3b\20\7d\20\7d\20\6c\65\74\20\73\75\6d\20\3d\20\30\3b\20\66\6f\72\20\28\63\6f\6e\73\74\20\78\20\6f\66\20\67\28\36\29\29\20\7b\20\73\75\6d\20\3d\20\73\75\6d\20\2b\20\78\3b\20\7d\20\72\65\74\75\72\6e\20\73\75\6d\3b")
  (data (i32.const 1468) "\66\75\6e\63\74\69\6f\6e\2a\20\61\28\29\20\7b\20\79\69\65\6c\64\20\31\3b\20\79\69\65\6c\64\20\32\3b\20\7d\20\66\75\6e\63\74\69\6f\6e\2a\20\62\28\29\20\7b\20\79\69\65\6c\64\20\31\30\3b\20\79\69\65\6c\64\20\32\30\3b\20\7d\20\6c\65\74\20\73\75\6d\20\3d\20\30\3b\20\66\6f\72\20\28\63\6f\6e\73\74\20\78\20\6f\66\20\61\28\29\29\20\7b\20\66\6f\72\20\28\63\6f\6e\73\74\20\79\20\6f\66\20\62\28\29\29\20\7b\20\73\75\6d\20\3d\20\73\75\6d\20\2b\20\78\20\2a\20\79\3b\20\7d\20\7d\20\72\65\74\75\72\6e\20\73\75\6d\3b")
  (data (i32.const 1635) "\64\79\6e\72\74\20\32\65\2e\39\20\67\65\6e\65\72\61\74\6f\72\73\3a\20\61\6c\6c\20\63\68\65\63\6b\73\20\70\61\73\73\65\64\0a")

  ;; globals from dynrt_lib_modc
  (global $dynrt_lib_modc_global1 (mut i32) (i32.const 0))
  (global $dynrt_lib_modc_global2 (mut i32) (i32.const 0))
  (global $dynrt_lib_modc_global3 i32 (i32.const 4))
  (global $dynrt_lib_modc_global4 i32 (i32.const 16))
  (global $dynrt_lib_modc_global5 i32 (i32.const 2188))
  (global $dynrt_lib_modc_global6 (mut i32) (i32.const 0))
  (global $dynrt_lib_modc_global7 (mut i32) (i32.const 0))
  (global $dynrt_lib_modc_global8 (mut i32) (i32.const 0))
  (global $dynrt_lib_modc_global9 (mut i32) (i32.const 0))
  (global $dynrt_lib_modc_global10 (mut i32) (i32.const 0))
  (global $dynrt_lib_modc_global11 (mut i32) (i32.const 0))
  (global $dynrt_lib_modc_global12 (mut i32) (i32.const 0))
  (global $dynrt_lib_modc_global13 (mut i32) (i32.const 2188))
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
  (global $dynrt_lib_modc_global30 (mut i32) (i32.const -1))
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
  (func $dynrt_lib_modc__fn21 (param f64 f64) (result f64)
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
  (func $dynrt_lib_modc__fn22 (param i32 i32) (result f64)
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
    call $dynrt_lib_modc__fn46
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
    call $dynrt_lib_modc__fn46
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
    call $dynrt_lib_modc__fn46
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
    call $dynrt_lib_modc__fn38
    local.set 1
    local.get 1
    i32.const 8
    i32.add
    local.get 0
    f64.store
    call $dynrt_lib_modc__fn46
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
    call $dynrt_lib_modc__fn38
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
    call $dynrt_lib_modc__fn46
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
  (func $dynrt_lib_modc__fn28 (result i32)
    (local i32) (local i32)
    i32.const 8
    global.get $dynrt_lib_modc_global3
    i32.const 2
    i32.add
    i32.const 4
    i32.mul
    i32.add
    call $dynrt_lib_modc__fn38
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
  (func $dynrt_lib_modc__fn29 (param i32) (result i32)
    (local i32)
    local.get 0
    local.set 1
    local.get 1
    i32.const 8
    i32.add
    i32.load
    return)
  (func $dynrt_lib_modc__fn30 (param i32 i32) (result i32)
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
  (func $dynrt_lib_modc__fn31 (param i32 i32 i32)
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
  (func $dynrt_lib_modc__fn32 (param i32 i32) (result i32)
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
        call $dynrt_lib_modc__fn38
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
  (func $dynrt_lib_modc__fn33 (param i32 i32)
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
  (func $dynrt_lib_modc__fn34 (param i32 i32)
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
    call $dynrt_lib_modc__fn33
    global.get $dynrt_lib_modc_global11
    global.get $dynrt_lib_modc_global13
    i32.gt_s
    if  ;; label = @1
      call $dynrt_lib_modc__fn43
    end)
  (func $dynrt_lib_modc__fn35 (param i32 i32)
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
  (func $dynrt_lib_modc__fn36 (param i32) (result i32)
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
    call $dynrt_lib_modc__fn35
    local.get 1
    local.tee 5
    return)
  (func $dynrt_lib_modc__fn37 (param i32) (result i32)
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
                  call $dynrt_lib_modc__fn33
                end
                local.get 1
                local.get 0
                call $dynrt_lib_modc__fn35
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
  (func $dynrt_lib_modc__fn38 (param i32) (result i32)
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
    call $dynrt_lib_modc__fn36
    local.set 2
    local.get 2
    i32.const 0
    i32.ne
    if  ;; label = @1
      local.get 2
      return
    end
    local.get 1
    call $dynrt_lib_modc__fn37
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
        call $dynrt_lib_modc__fn43
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
        local.get 1
        call $dynrt_lib_modc__fn37
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
  (func $dynrt_lib_modc__fn39 (param i32) (result i32)
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
  (func $dynrt_lib_modc__fn40 (param i32 i32) (result i32)
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
  (func $dynrt_lib_modc__fn41 (param i32) (result i32)
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
    call $dynrt_lib_modc__fn39
    local.set 1
    local.get 0
    call $dynrt_lib_modc__fn41
    local.set 2
    local.get 1
    call $dynrt_lib_modc__fn41
    local.set 1
    local.get 2
    local.get 1
    call $dynrt_lib_modc__fn40
    return)
  (func $dynrt_lib_modc__fn42 (param i32 i32) (result i32)
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
  (func $dynrt_lib_modc__fn43
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    i32.const 0
    local.tee 7
    local.set 0
    global.get $dynrt_lib_modc_global6
    local.get 0
    call $dynrt_lib_modc__fn42
    local.set 0
    global.get $dynrt_lib_modc_global7
    local.get 0
    call $dynrt_lib_modc__fn42
    local.set 0
    global.get $dynrt_lib_modc_global8
    local.get 0
    call $dynrt_lib_modc__fn42
    local.set 0
    global.get $dynrt_lib_modc_global9
    local.get 0
    call $dynrt_lib_modc__fn42
    local.set 0
    global.get $dynrt_lib_modc_global10
    local.get 0
    call $dynrt_lib_modc__fn42
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
    call $dynrt_lib_modc__fn41
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
            call $dynrt_lib_modc__fn33
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
  (func $dynrt_lib_modc__fn45 (param i32)
    global.get $dynrt_lib_modc_global15
    i32.eqz
    if  ;; label = @1
      call $dynrt_lib_modc__fn28
      global.set $dynrt_lib_modc_global15
    end
    global.get $dynrt_lib_modc_global15
    local.get 0
    call $dynrt_lib_modc__fn32
    global.set $dynrt_lib_modc_global15)
  (func $dynrt_lib_modc__fn46 (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    i32.const 24
    call $dynrt_lib_modc__fn38
    local.set 0
    global.get $dynrt_lib_modc_global15
    i32.eqz
    if  ;; label = @1
      call $dynrt_lib_modc__fn28
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
        call $dynrt_lib_modc__fn32
        global.set $dynrt_lib_modc_global15
        local.get 2
        local.get 1
        call $dynrt_lib_modc__fn34
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
  (func $dynrt_lib_modc__fn47 (result i32)
    (local i32) (local i32)
    i32.const 28
    call $dynrt_lib_modc__fn38
    local.set 0
    local.get 0
    call $dynrt_lib_modc__fn45
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
    call $dynrt_lib_modc__fn29
    return)
  (func $dynrt_lib_modc__fn49 (param i32) (result i32)
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
  (func $dynrt_lib_modc__fn50 (param i32)
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
    call $dynrt_lib_modc__fn49
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
        call $dynrt_lib_modc__fn29
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
                call $dynrt_lib_modc__fn30
                call $dynrt_lib_modc__fn50
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
          call $dynrt_lib_modc__fn50
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
            call $dynrt_lib_modc__fn50
            local.get 1
            i32.const 8
            i32.add
            i32.const 12
            i32.add
            i32.load
            call $dynrt_lib_modc__fn50
            local.get 1
            i32.const 8
            i32.add
            i32.const 16
            i32.add
            i32.load
            call $dynrt_lib_modc__fn50
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
    call $dynrt_lib_modc__fn29
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
            call $dynrt_lib_modc__fn30
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
    call $dynrt_lib_modc__fn50)
  (func $dynrt_lib_modc_dynGcMarkedCount (result i32)
    (local i32) (local i32) (local i32) (local i32)
    global.get $dynrt_lib_modc_global15
    i32.eqz
    if  ;; label = @1
      i32.const 0
      return
    end
    global.get $dynrt_lib_modc_global15
    call $dynrt_lib_modc__fn29
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
            call $dynrt_lib_modc__fn30
            call $dynrt_lib_modc__fn49
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
  (func $dynrt_lib_modc__fn54 (param i32)
    global.get $dynrt_lib_modc_global17
    i32.eqz
    if  ;; label = @1
      call $dynrt_lib_modc__fn28
      global.set $dynrt_lib_modc_global17
    end
    global.get $dynrt_lib_modc_global17
    local.get 0
    call $dynrt_lib_modc__fn32
    global.set $dynrt_lib_modc_global17)
  (func $dynrt_lib_modc__fn55
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
    call $dynrt_lib_modc__fn54)
  (func $dynrt_lib_modc_dynGcPopRoot
    call $dynrt_lib_modc__fn55)
  (func $dynrt_lib_modc_dynGcRootCount (result i32)
    global.get $dynrt_lib_modc_global17
    i32.eqz
    if  ;; label = @1
      i32.const 0
      return
    end
    global.get $dynrt_lib_modc_global17
    call $dynrt_lib_modc__fn29
    return)
  (func $dynrt_lib_modc_dynGcMarkRoots
    (local i32) (local i32) (local i32) (local i32)
    call $dynrt_lib_modc_dynGcMarkClear
    global.get $dynrt_lib_modc_global20
    call $dynrt_lib_modc__fn50
    global.get $dynrt_lib_modc_global25
    call $dynrt_lib_modc__fn50
    global.get $dynrt_lib_modc_global24
    call $dynrt_lib_modc__fn50
    global.get $dynrt_lib_modc_global17
    i32.eqz
    if  ;; label = @1
      return
    end
    global.get $dynrt_lib_modc_global17
    call $dynrt_lib_modc__fn29
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
            call $dynrt_lib_modc__fn30
            call $dynrt_lib_modc__fn50
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
        call $dynrt_lib_modc__fn29
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
                call $dynrt_lib_modc__fn30
                call $dynrt_lib_modc__fn50
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
      call $dynrt_lib_modc__fn28
      global.set $dynrt_lib_modc_global18
    end
    global.get $dynrt_lib_modc_global18
    call $dynrt_lib_modc__fn29
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
            call $dynrt_lib_modc__fn30
            i32.eqz
            if  ;; label = @5
              block  ;; label = @6
                global.get $dynrt_lib_modc_global18
                local.get 2
                local.get 0
                call $dynrt_lib_modc__fn31
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
    call $dynrt_lib_modc__fn32
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
      call $dynrt_lib_modc__fn29
      i32.ge_s
    end
    if  ;; label = @1
      return
    end
    global.get $dynrt_lib_modc_global18
    local.get 0
    i32.const 0
    call $dynrt_lib_modc__fn31)
  (func $dynrt_lib_modc__fn62 (param i32)
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
    call $dynrt_lib_modc__fn34)
  (func $dynrt_lib_modc__fn63 (param i32)
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
      call $dynrt_lib_modc__fn34
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
        call $dynrt_lib_modc__fn34
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
          call $dynrt_lib_modc__fn62
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
              call $dynrt_lib_modc__fn62
              local.get 1
              i32.const 8
              i32.add
              i32.const 12
              i32.add
              i32.load
              local.set 1
              local.get 1
              call $dynrt_lib_modc__fn29
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
                      call $dynrt_lib_modc__fn30
                      i32.const 8
                      local.get 1
                      local.get 3
                      i32.const 1
                      i32.add
                      call $dynrt_lib_modc__fn30
                      i32.add
                      call $dynrt_lib_modc__fn34
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
              call $dynrt_lib_modc__fn62
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
                call $dynrt_lib_modc__fn63
                local.get 5
                local.get 6
                call $dynrt_lib_modc__fn34
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
  (func $dynrt_lib_modc__fn66
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
    call $dynrt_lib_modc__fn46
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
    call $dynrt_lib_modc__fn28
    i32.store
    local.get 0
    local.tee 1
    return)
  (func $dynrt_lib_modc_dynObject (result i32)
    (local i32) (local i32)
    call $dynrt_lib_modc__fn46
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
    call $dynrt_lib_modc__fn28
    i32.store
    local.get 0
    i32.const 8
    i32.add
    i32.const 12
    i32.add
    call $dynrt_lib_modc__fn28
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
  (func $dynrt_lib_modc__fn78 (param i32)
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
    i32.const 1936
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
  (func $dynrt_lib_modc__fn79 (param i32)
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
        call $dynrt_lib_modc__fn78
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
            i32.const 1936
            local.set 1
            i32.const 5
            local.set 2
          end
        else
          block  ;; label = @4
            i32.const 1941
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
        i32.const 1945
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
        i32.const 1949
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
    i32.const 1936
    local.set 1
    i32.const 0
    local.set 2
    local.get 1
    local.tee 6
    global.set $dynrt_lib_modc_global1
    local.get 2
    global.set $dynrt_lib_modc_global2
    return)
  (func $dynrt_lib_modc__fn80 (param i32 i32 i32) (result i32)
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
    call $dynrt_lib_modc__fn29
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
            call $dynrt_lib_modc__fn30
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
                call $dynrt_lib_modc__fn30
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
    call $dynrt_lib_modc__fn80
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
        call $dynrt_lib_modc__fn31
        return
      end
    end
    local.get 2
    local.tee 10
    local.set 5
    i32.const 8
    local.get 5
    i32.add
    call $dynrt_lib_modc__fn38
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
    call $dynrt_lib_modc__fn32
    local.set 7
    local.get 7
    local.get 5
    call $dynrt_lib_modc__fn32
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
    call $dynrt_lib_modc__fn32
    i32.store)
  (func $dynrt_lib_modc_dynGet (param i32 i32 i32) (result i32)
    (local i32) (local i32) (local i32)
    local.get 0
    local.tee 5
    local.set 3
    local.get 0
    local.get 1
    local.get 2
    call $dynrt_lib_modc__fn80
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
    call $dynrt_lib_modc__fn30
    return)
  (func $dynrt_lib_modc_dynHas (param i32 i32 i32) (result i32)
    local.get 0
    local.get 1
    local.get 2
    call $dynrt_lib_modc__fn80
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
    call $dynrt_lib_modc__fn29
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
    call $dynrt_lib_modc__fn30
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
    call $dynrt_lib_modc__fn30
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
    call $dynrt_lib_modc__fn30
    return)
  (func $dynrt_lib_modc__fn88 (param i32 i32) (result i32)
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
    call $dynrt_lib_modc__fn30
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
    call $dynrt_lib_modc__fn30
    local.set 2
    local.get 3
    local.tee 7
    local.set 3
    i32.const 8
    local.get 2
    i32.add
    call $dynrt_lib_modc__fn38
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
    call $dynrt_lib_modc__fn46
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
    call $dynrt_lib_modc__fn32
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
    call $dynrt_lib_modc__fn29
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
    call $dynrt_lib_modc__fn30
    return)
  (func $dynrt_lib_modc__fn92 (param i32 i32 i32)
    (local i32) (local i32)
    local.get 0
    local.set 3
    local.get 3
    i32.const 8
    i32.add
    i32.const 4
    i32.add
    i32.load
    call $dynrt_lib_modc__fn29
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
      call $dynrt_lib_modc__fn31
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
        call $dynrt_lib_modc__fn32
        i32.store
      end
    end)
  (func $dynrt_lib_modc__fn93 (param i32 i32 i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local f64) (local i32) (local i32) (local i32) (local i32) (local i32) (local f64) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    call $dynrt_lib_modc_dynArrLen
    local.set 4
    local.get 3
    call $dynrt_lib_modc_dynArrLen
    local.set 5
    local.get 1
    local.get 2
    i32.const 1958
    i32.const 4
    call $dynrt_lib_modc__fn159
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
    i32.const 1962
    i32.const 7
    call $dynrt_lib_modc__fn159
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
    i32.const 1969
    i32.const 8
    call $dynrt_lib_modc__fn159
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
    i32.const 1977
    i32.const 4
    call $dynrt_lib_modc__fn159
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        i32.const 1981
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
            call $dynrt_lib_modc__fn79
            global.get $dynrt_lib_modc_global1
            local.set 7
            global.get $dynrt_lib_modc_global2
            local.set 8
          end
        end
        i32.const 1936
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
                call $dynrt_lib_modc__fn79
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
    i32.const 1982
    i32.const 5
    call $dynrt_lib_modc__fn159
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
    i32.const 1987
    i32.const 6
    call $dynrt_lib_modc__fn159
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
    i32.const 1993
    i32.const 7
    call $dynrt_lib_modc__fn159
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
    i32.const 2000
    i32.const 3
    call $dynrt_lib_modc__fn159
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
        call $dynrt_lib_modc__fn30
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
    i32.const 2003
    i32.const 5
    call $dynrt_lib_modc__fn159
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
        call $dynrt_lib_modc__fn30
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
                call $dynrt_lib_modc__fn30
                call $dynrt_lib_modc__fn31
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
    i32.const 2008
    i32.const 7
    call $dynrt_lib_modc__fn159
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
                call $dynrt_lib_modc__fn30
                call $dynrt_lib_modc__fn31
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
                call $dynrt_lib_modc__fn31
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
    i32.const 2015
    i32.const 2
    call $dynrt_lib_modc__fn159
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
    i32.const 2017
    i32.const 11
    call $dynrt_lib_modc__fn159
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
    i32.const 2028
    i32.const 3
    call $dynrt_lib_modc__fn159
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
    i32.const 2031
    i32.const 6
    call $dynrt_lib_modc__fn159
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
    i32.const 2037
    i32.const 7
    call $dynrt_lib_modc__fn159
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
    i32.const 2044
    i32.const 6
    call $dynrt_lib_modc__fn159
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
    i32.const 2050
    i32.const 4
    call $dynrt_lib_modc__fn159
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
    i32.const 2054
    i32.const 9
    call $dynrt_lib_modc__fn159
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
    i32.const 2063
    i32.const 4
    call $dynrt_lib_modc__fn159
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
    i32.const 2067
    i32.const 5
    call $dynrt_lib_modc__fn159
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
    i32.const 2072
    i32.const 4
    call $dynrt_lib_modc__fn159
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
                call $dynrt_lib_modc__fn30
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
                        call $dynrt_lib_modc__fn30
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
                            call $dynrt_lib_modc__fn31
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
                call $dynrt_lib_modc__fn31
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
  (func $dynrt_lib_modc__fn94 (param i32 i32 i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local f64) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    call $dynrt_lib_modc__fn78
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
    i32.const 2076
    i32.const 6
    call $dynrt_lib_modc__fn159
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
    i32.const 2082
    i32.const 10
    call $dynrt_lib_modc__fn159
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
    i32.const 2092
    i32.const 11
    call $dynrt_lib_modc__fn159
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
    i32.const 2103
    i32.const 11
    call $dynrt_lib_modc__fn159
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
    i32.const 2114
    i32.const 4
    call $dynrt_lib_modc__fn159
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
    i32.const 1982
    i32.const 5
    call $dynrt_lib_modc__fn159
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
          i32.const 1936
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
    i32.const 1962
    i32.const 7
    call $dynrt_lib_modc__fn159
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        i32.const 1936
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
            call $dynrt_lib_modc__fn78
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
    i32.const 1969
    i32.const 8
    call $dynrt_lib_modc__fn159
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        i32.const 1936
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
            call $dynrt_lib_modc__fn78
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
    i32.const 2118
    i32.const 10
    call $dynrt_lib_modc__fn159
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        i32.const 1936
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
            call $dynrt_lib_modc__fn78
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
    i32.const 2128
    i32.const 8
    call $dynrt_lib_modc__fn159
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        i32.const 1936
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
            call $dynrt_lib_modc__fn78
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
    i32.const 2136
    i32.const 6
    call $dynrt_lib_modc__fn159
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
    i32.const 2142
    i32.const 8
    call $dynrt_lib_modc__fn159
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
        i32.const 2150
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
            call $dynrt_lib_modc__fn78
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
    i32.const 2151
    i32.const 6
    call $dynrt_lib_modc__fn159
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
        i32.const 2150
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
            call $dynrt_lib_modc__fn78
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
    i32.const 1987
    i32.const 6
    call $dynrt_lib_modc__fn159
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        i32.const 1936
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
            call $dynrt_lib_modc__fn78
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
    i32.const 2157
    i32.const 5
    call $dynrt_lib_modc__fn159
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        i32.const 1936
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
            call $dynrt_lib_modc__fn78
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
    local.get 1
    local.get 2
    i32.const 2162
    i32.const 5
    call $dynrt_lib_modc__fn159
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        i32.const 1936
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
                i32.const 2167
                i32.const 7
                call $dynrt_lib_modc_dynGet
                local.set 7
                local.get 7
                i32.const -1
                i32.ne
                if  ;; label = @7
                  block  ;; label = @8
                    local.get 7
                    call $dynrt_lib_modc__fn78
                    global.get $dynrt_lib_modc_global1
                    local.set 6
                    global.get $dynrt_lib_modc_global2
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
                  call $dynrt_lib_modc__fn78
                  global.get $dynrt_lib_modc_global1
                  local.set 6
                  global.get $dynrt_lib_modc_global2
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
        call $dynrt_lib_modc__fn118
        return
      end
    end
    call $dynrt_lib_modc_dynUndefined
    return)
  (func $dynrt_lib_modc__fn95 (param i32 i32 i32) (result i32)
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
    i32.const 2174
    i32.const 6
    call $dynrt_lib_modc__fn159
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
    i32.const 2180
    i32.const 4
    call $dynrt_lib_modc__fn159
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
                    call $dynrt_lib_modc__fn88
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
    i32.const 2184
    i32.const 6
    call $dynrt_lib_modc__fn159
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
    i32.const 2190
    i32.const 7
    call $dynrt_lib_modc__fn159
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
                    call $dynrt_lib_modc__fn88
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
    i32.const 2197
    i32.const 6
    call $dynrt_lib_modc__fn159
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
                            call $dynrt_lib_modc__fn88
                            call $dynrt_lib_modc__fn78
                            global.get $dynrt_lib_modc_global1
                            local.set 9
                            global.get $dynrt_lib_modc_global2
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
  (func $dynrt_lib_modc__fn96 (param i32 i32 i32) (result i32)
    (local i32) (local f64) (local f64) (local f64) (local f64) (local f64) (local f64) (local f64) (local f64) (local f64)
    local.get 2
    call $dynrt_lib_modc_dynArrLen
    local.set 3
    f64.const 0x0p+0 (;=0;)
    local.tee 11
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
    i32.const 2203
    i32.const 5
    call $dynrt_lib_modc__fn159
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 4
        local.tee 6
        f64.floor
        local.set 4
        local.get 4
        call $dynrt_lib_modc_dynNumber
        return
      end
    end
    local.get 0
    local.get 1
    i32.const 2208
    i32.const 4
    call $dynrt_lib_modc__fn159
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 4
        local.tee 7
        f64.ceil
        local.set 4
        local.get 4
        call $dynrt_lib_modc_dynNumber
        return
      end
    end
    local.get 0
    local.get 1
    i32.const 2212
    i32.const 5
    call $dynrt_lib_modc__fn159
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 4
        local.tee 8
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
    i32.const 2217
    i32.const 3
    call $dynrt_lib_modc__fn159
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 4
        local.tee 9
        f64.abs
        local.set 4
        local.get 4
        call $dynrt_lib_modc_dynNumber
        return
      end
    end
    local.get 0
    local.get 1
    i32.const 2220
    i32.const 4
    call $dynrt_lib_modc__fn159
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 4
        local.tee 10
        f64.sqrt
        local.set 4
        local.get 4
        call $dynrt_lib_modc_dynNumber
        return
      end
    end
    local.get 0
    local.get 1
    i32.const 2224
    i32.const 4
    call $dynrt_lib_modc__fn159
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
    i32.const 2228
    i32.const 5
    call $dynrt_lib_modc__fn159
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
    f64.const 0x0p+0 (;=0;)
    local.tee 12
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
    i32.const 2233
    i32.const 3
    call $dynrt_lib_modc__fn159
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 4
        local.get 5
        f64.gt
        if (result f64)  ;; label = @3
          local.get 4
        else
          local.get 5
        end
        local.set 4
        local.get 4
        call $dynrt_lib_modc_dynNumber
        return
      end
    end
    local.get 0
    local.get 1
    i32.const 2236
    i32.const 3
    call $dynrt_lib_modc__fn159
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 4
        local.get 5
        f64.lt
        if (result f64)  ;; label = @3
          local.get 4
        else
          local.get 5
        end
        local.set 4
        local.get 4
        call $dynrt_lib_modc_dynNumber
        return
      end
    end
    local.get 0
    local.get 1
    i32.const 2239
    i32.const 3
    call $dynrt_lib_modc__fn159
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 4
        local.get 5
        call $dynrt_lib_modc__fn21
        local.set 4
        local.get 4
        call $dynrt_lib_modc_dynNumber
        return
      end
    end
    call $dynrt_lib_modc_dynUndefined
    return)
  (func $dynrt_lib_modc__fn97 (param i32 i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    i32.const 2242
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
            call $dynrt_lib_modc__fn8
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
                i32.const 2243
                i32.const 2
                call $dynrt_lib_modc__fn4
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
                  i32.const 2245
                  i32.const 2
                  call $dynrt_lib_modc__fn4
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
                    i32.const 2247
                    i32.const 2
                    call $dynrt_lib_modc__fn4
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
                      i32.const 2249
                      i32.const 2
                      call $dynrt_lib_modc__fn4
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
                        i32.const 2251
                        i32.const 2
                        call $dynrt_lib_modc__fn4
                        local.set 3
                        nop
                        local.set 2
                      end
                    else
                      block  ;; label = @10
                        local.get 0
                        local.get 1
                        local.get 5
                        call $dynrt_lib_modc__fn9
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
                        call $dynrt_lib_modc__fn4
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
    i32.const 2242
    i32.const 1
    call $dynrt_lib_modc__fn4
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
    global.set $dynrt_lib_modc_global1
    local.get 3
    local.tee 28
    global.set $dynrt_lib_modc_global2
    return)
  (func $dynrt_lib_modc__fn98 (param i32)
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
        i32.const 1945
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
    local.get 1
    i32.eqz
    if  ;; label = @1
      block  ;; label = @2
        i32.const 1945
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
            i32.const 1941
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
        i32.const 1936
        local.set 1
        i32.const 5
        local.set 2
        local.get 1
        global.set $dynrt_lib_modc_global1
        local.get 2
        global.set $dynrt_lib_modc_global2
        return
      end
    end
    local.get 1
    i32.const 3
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 0
        call $dynrt_lib_modc__fn79
        global.get $dynrt_lib_modc_global1
        local.set 1
        global.get $dynrt_lib_modc_global2
        local.set 2
        local.get 1
        local.tee 9
        local.set 1
        local.get 2
        local.tee 10
        local.set 2
        local.get 1
        local.tee 11
        global.set $dynrt_lib_modc_global1
        local.get 2
        local.tee 12
        global.set $dynrt_lib_modc_global2
        return
      end
    end
    local.get 1
    i32.const 4
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 0
        call $dynrt_lib_modc__fn78
        global.get $dynrt_lib_modc_global1
        global.get $dynrt_lib_modc_global2
        call $dynrt_lib_modc__fn97
        global.get $dynrt_lib_modc_global1
        local.tee 13
        local.set 1
        global.get $dynrt_lib_modc_global2
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
        global.set $dynrt_lib_modc_global1
        local.get 2
        local.tee 18
        global.set $dynrt_lib_modc_global2
        return
      end
    end
    local.get 1
    i32.const 5
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        i32.const 2253
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
                    i32.const 1981
                    i32.const 1
                    call $dynrt_lib_modc__fn4
                    local.set 2
                    nop
                    local.set 1
                  end
                end
                local.get 0
                local.get 4
                call $dynrt_lib_modc_dynArrGet
                call $dynrt_lib_modc__fn98
                global.get $dynrt_lib_modc_global1
                local.set 5
                global.get $dynrt_lib_modc_global2
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
                call $dynrt_lib_modc__fn4
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
        i32.const 2254
        i32.const 1
        call $dynrt_lib_modc__fn4
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
        global.set $dynrt_lib_modc_global1
        local.get 2
        local.tee 30
        global.set $dynrt_lib_modc_global2
        return
      end
    end
    local.get 1
    i32.const 6
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        i32.const 2255
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
                    i32.const 1981
                    i32.const 1
                    call $dynrt_lib_modc__fn4
                    local.set 2
                    nop
                    local.set 1
                  end
                end
                local.get 0
                local.get 4
                call $dynrt_lib_modc__fn88
                call $dynrt_lib_modc__fn78
                global.get $dynrt_lib_modc_global1
                global.get $dynrt_lib_modc_global2
                call $dynrt_lib_modc__fn97
                global.get $dynrt_lib_modc_global1
                local.tee 33
                local.set 5
                global.get $dynrt_lib_modc_global2
                local.tee 34
                local.set 6
                local.get 0
                local.get 4
                call $dynrt_lib_modc_dynObjValAt
                call $dynrt_lib_modc__fn98
                global.get $dynrt_lib_modc_global1
                local.tee 35
                local.set 7
                global.get $dynrt_lib_modc_global2
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
                call $dynrt_lib_modc__fn4
                local.set 2
                nop
                local.set 1
                local.get 1
                local.get 2
                i32.const 2256
                i32.const 1
                call $dynrt_lib_modc__fn4
                local.set 2
                nop
                local.set 1
                local.get 1
                local.get 2
                local.get 7
                local.get 8
                call $dynrt_lib_modc__fn4
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
        i32.const 2257
        i32.const 1
        call $dynrt_lib_modc__fn4
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
        global.set $dynrt_lib_modc_global1
        local.get 2
        local.tee 47
        global.set $dynrt_lib_modc_global2
        return
      end
    end
    i32.const 1945
    local.set 1
    i32.const 4
    local.set 2
    local.get 1
    local.tee 48
    global.set $dynrt_lib_modc_global1
    local.get 2
    global.set $dynrt_lib_modc_global2
    return)
  (func $dynrt_lib_modc__fn99 (param i32 i32) (result i32)
    (local i32) (local i32)
    global.get $dynrt_lib_modc_global19
    local.set 2
    i32.const 0
    global.set $dynrt_lib_modc_global19
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn179
    local.set 3
    local.get 2
    global.set $dynrt_lib_modc_global19
    local.get 3
    return)
  (func $dynrt_lib_modc__fn100 (param i32 i32) (result i32)
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
  (func $dynrt_lib_modc__fn101 (param i32) (result i32)
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
  (func $dynrt_lib_modc__fn102 (param i32 i32)
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
            call $dynrt_lib_modc__fn92
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
  (func $dynrt_lib_modc__fn103 (result i32)
    (local i32) (local i32)
    call $dynrt_lib_modc_dynObject
    local.set 0
    local.get 0
    i32.const 2258
    i32.const 6
    call $dynrt_lib_modc_dynArray
    call $dynrt_lib_modc_dynSet
    local.get 0
    i32.const 2264
    i32.const 6
    call $dynrt_lib_modc_dynArray
    call $dynrt_lib_modc_dynSet
    local.get 0
    local.tee 1
    return)
  (func $dynrt_lib_modc__fn104 (param i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    call $dynrt_lib_modc_dynObject
    local.set 1
    call $dynrt_lib_modc_dynArray
    local.set 2
    local.get 1
    i32.const 2270
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
                call $dynrt_lib_modc__fn100
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
  (func $dynrt_lib_modc__fn105 (param i32 i32 i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    i32.const 2258
    i32.const 6
    call $dynrt_lib_modc_dynGet
    local.set 4
    local.get 0
    i32.const 2264
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
    i32.const 2276
    i32.const 3
    call $dynrt_lib_modc__fn159
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
        call $dynrt_lib_modc__fn100
        local.set 6
        local.get 6
        i32.const 0
        i32.ge_s
        if  ;; label = @3
          local.get 5
          local.get 6
          local.get 8
          call $dynrt_lib_modc__fn92
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
    i32.const 2279
    i32.const 3
    call $dynrt_lib_modc__fn159
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 4
        local.get 7
        call $dynrt_lib_modc__fn100
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
    i32.const 2282
    i32.const 3
    call $dynrt_lib_modc__fn159
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 4
        local.get 7
        call $dynrt_lib_modc__fn100
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
    i32.const 2285
    i32.const 6
    call $dynrt_lib_modc__fn159
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 4
        local.get 7
        call $dynrt_lib_modc__fn100
        local.set 6
        local.get 6
        i32.const 0
        i32.ge_s
        if  ;; label = @3
          block  ;; label = @4
            local.get 4
            local.get 6
            call $dynrt_lib_modc__fn102
            local.get 5
            local.get 6
            call $dynrt_lib_modc__fn102
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
    i32.const 2180
    i32.const 4
    call $dynrt_lib_modc__fn159
    i32.const 1
    i32.eq
    if  ;; label = @1
      local.get 4
      call $dynrt_lib_modc__fn101
      return
    end
    local.get 1
    local.get 2
    i32.const 2184
    i32.const 6
    call $dynrt_lib_modc__fn159
    i32.const 1
    i32.eq
    if  ;; label = @1
      local.get 5
      call $dynrt_lib_modc__fn101
      return
    end
    local.get 1
    local.get 2
    i32.const 2037
    i32.const 7
    call $dynrt_lib_modc__fn159
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
  (func $dynrt_lib_modc__fn106 (param i32 i32 i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    i32.const 2270
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
    i32.const 2291
    i32.const 3
    call $dynrt_lib_modc__fn159
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 4
        local.get 6
        call $dynrt_lib_modc__fn100
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
    i32.const 2282
    i32.const 3
    call $dynrt_lib_modc__fn159
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 4
        local.get 6
        call $dynrt_lib_modc__fn100
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
    i32.const 2285
    i32.const 6
    call $dynrt_lib_modc__fn159
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 4
        local.get 6
        call $dynrt_lib_modc__fn100
        local.set 5
        local.get 5
        i32.const 0
        i32.ge_s
        if  ;; label = @3
          block  ;; label = @4
            local.get 4
            local.get 5
            call $dynrt_lib_modc__fn102
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
    i32.const 2184
    i32.const 6
    call $dynrt_lib_modc__fn159
    i32.const 1
    i32.eq
    if  ;; label = @1
      local.get 4
      call $dynrt_lib_modc__fn101
      return
    end
    local.get 1
    local.get 2
    i32.const 2180
    i32.const 4
    call $dynrt_lib_modc__fn159
    i32.const 1
    i32.eq
    if  ;; label = @1
      local.get 4
      call $dynrt_lib_modc__fn101
      return
    end
    local.get 1
    local.get 2
    i32.const 2037
    i32.const 7
    call $dynrt_lib_modc__fn159
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
  (func $dynrt_lib_modc__fn107 (param i32) (result i32)
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
  (func $dynrt_lib_modc__fn108 (param i32) (result i32)
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
  (func $dynrt_lib_modc__fn109 (param i32) (result i32)
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
  (func $dynrt_lib_modc__fn110 (param i32 i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    local.get 2
    call $dynrt_lib_modc__fn8
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
          call $dynrt_lib_modc__fn8
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
          call $dynrt_lib_modc__fn8
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
                call $dynrt_lib_modc__fn8
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
  (func $dynrt_lib_modc__fn111 (param i32 i32 i32 i32) (result i32)
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
      call $dynrt_lib_modc__fn8
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
            call $dynrt_lib_modc__fn8
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
                call $dynrt_lib_modc__fn8
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
                call $dynrt_lib_modc__fn8
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
                  call $dynrt_lib_modc__fn8
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
                    call $dynrt_lib_modc__fn8
                    local.set 8
                    local.get 8
                    i32.const 100
                    i32.eq
                    if (result i32)  ;; label = @9
                      local.get 3
                      call $dynrt_lib_modc__fn107
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
                        call $dynrt_lib_modc__fn108
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
                          call $dynrt_lib_modc__fn109
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
  (func $dynrt_lib_modc__fn112 (param i32 i32 i32 i32) (result i32)
    (local i32)
    local.get 0
    local.get 1
    local.get 2
    call $dynrt_lib_modc__fn8
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
        call $dynrt_lib_modc__fn8
        local.set 4
        local.get 4
        i32.const 100
        i32.eq
        if  ;; label = @3
          local.get 3
          call $dynrt_lib_modc__fn107
          return
        end
        local.get 4
        i32.const 68
        i32.eq
        if  ;; label = @3
          local.get 3
          call $dynrt_lib_modc__fn107
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
          call $dynrt_lib_modc__fn108
          return
        end
        local.get 4
        i32.const 87
        i32.eq
        if  ;; label = @3
          local.get 3
          call $dynrt_lib_modc__fn108
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
          call $dynrt_lib_modc__fn109
          return
        end
        local.get 4
        i32.const 83
        i32.eq
        if  ;; label = @3
          local.get 3
          call $dynrt_lib_modc__fn109
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
      call $dynrt_lib_modc__fn111
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
  (func $dynrt_lib_modc__fn113 (param i32 i32 i32 i32 i32 i32) (result i32)
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
    call $dynrt_lib_modc__fn8
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
    call $dynrt_lib_modc__fn110
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
      call $dynrt_lib_modc__fn8
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
      call $dynrt_lib_modc__fn114
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
      call $dynrt_lib_modc__fn115
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
      call $dynrt_lib_modc__fn116
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
      call $dynrt_lib_modc__fn8
      call $dynrt_lib_modc__fn112
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
      call $dynrt_lib_modc__fn113
      return
    end
    i32.const -1
    return)
  (func $dynrt_lib_modc__fn114 (param i32 i32 i32 i32 i32 i32 i32) (result i32)
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
            call $dynrt_lib_modc__fn8
            call $dynrt_lib_modc__fn112
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
            call $dynrt_lib_modc__fn113
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
  (func $dynrt_lib_modc__fn115 (param i32 i32 i32 i32 i32 i32 i32) (result i32)
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
    call $dynrt_lib_modc__fn8
    call $dynrt_lib_modc__fn112
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
            call $dynrt_lib_modc__fn8
            call $dynrt_lib_modc__fn112
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
            call $dynrt_lib_modc__fn113
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
  (func $dynrt_lib_modc__fn116 (param i32 i32 i32 i32 i32 i32 i32) (result i32)
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
      call $dynrt_lib_modc__fn8
      call $dynrt_lib_modc__fn112
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
        call $dynrt_lib_modc__fn113
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
    call $dynrt_lib_modc__fn113
    return)
  (func $dynrt_lib_modc__fn117 (param i32 i32 i32 i32) (result i32)
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
      call $dynrt_lib_modc__fn8
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
      call $dynrt_lib_modc__fn113
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
            call $dynrt_lib_modc__fn113
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
  (func $dynrt_lib_modc__fn118 (param i32 i32 i32 i32) (result i32)
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
      call $dynrt_lib_modc__fn8
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
            call $dynrt_lib_modc__fn113
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
  (func $dynrt_lib_modc__fn119 (param i32) (result i32)
    (local i32) (local i32)
    call $dynrt_lib_modc_dynObject
    local.set 1
    local.get 1
    i32.const 2167
    i32.const 7
    local.get 0
    call $dynrt_lib_modc_dynSet
    local.get 1
    local.tee 2
    return)
  (func $dynrt_lib_modc__fn120 (param i32 i32 i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    i32.const 2167
    i32.const 7
    call $dynrt_lib_modc_dynGet
    call $dynrt_lib_modc__fn78
    global.get $dynrt_lib_modc_global1
    local.set 4
    global.get $dynrt_lib_modc_global2
    local.set 5
    local.get 3
    call $dynrt_lib_modc_dynArrLen
    local.set 6
    i32.const 1936
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
        call $dynrt_lib_modc__fn78
        global.get $dynrt_lib_modc_global1
        local.set 7
        global.get $dynrt_lib_modc_global2
        local.set 8
      end
    end
    local.get 1
    local.get 2
    i32.const 2294
    i32.const 4
    call $dynrt_lib_modc__fn159
    i32.const 1
    i32.eq
    if  ;; label = @1
      local.get 4
      local.get 5
      local.get 7
      local.get 8
      call $dynrt_lib_modc__fn117
      call $dynrt_lib_modc_dynBool
      return
    end
    local.get 1
    local.get 2
    i32.const 2298
    i32.const 4
    call $dynrt_lib_modc__fn159
    i32.const 1
    i32.eq
    if  ;; label = @1
      local.get 4
      local.get 5
      local.get 7
      local.get 8
      call $dynrt_lib_modc__fn118
      return
    end
    call $dynrt_lib_modc_dynUndefined
    return)
  (func $dynrt_lib_modc__fn121 (param i32 i32 i32 i32) (result i32)
    (local i32) (local i32) (local f64) (local i32) (local i32) (local i32)
    local.get 1
    local.get 2
    i32.const 2302
    i32.const 4
    call $dynrt_lib_modc__fn159
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 0
        i32.const 2306
        i32.const 6
        call $dynrt_lib_modc_dynGet
        local.set 4
        local.get 0
        i32.const 2312
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
            i32.const 2318
            i32.const 5
            local.get 4
            local.get 5
            call $dynrt_lib_modc_dynArrGet
            call $dynrt_lib_modc_dynSet
            local.get 8
            i32.const 2323
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
            i32.const 2312
            i32.const 6
            local.get 4
            f64.convert_i32_s
            call $dynrt_lib_modc_dynNumber
            call $dynrt_lib_modc_dynSet
          end
        else
          block  ;; label = @4
            local.get 8
            i32.const 2318
            i32.const 5
            call $dynrt_lib_modc_dynUndefined
            call $dynrt_lib_modc_dynSet
            local.get 8
            i32.const 2323
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
  (func $dynrt_lib_modc__fn122 (param i32) (result i32)
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
      i32.const 2327
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
    i32.const 2327
    i32.const 7
    local.get 0
    call $dynrt_lib_modc_dynSet
    local.get 1
    i32.const 2334
    i32.const 9
    f64.const 0x0p+0 (;=0;)
    call $dynrt_lib_modc_dynNumber
    call $dynrt_lib_modc_dynSet
    local.get 1
    local.tee 3
    return)
  (func $dynrt_lib_modc__fn123 (param i32) (result i32)
    (local i32) (local i32)
    call $dynrt_lib_modc_dynObject
    local.set 1
    local.get 1
    i32.const 2327
    i32.const 7
    local.get 0
    call $dynrt_lib_modc_dynSet
    local.get 1
    i32.const 2334
    i32.const 9
    f64.const 0x1.0p+0 (;=1;)
    call $dynrt_lib_modc_dynNumber
    call $dynrt_lib_modc_dynSet
    local.get 1
    local.tee 2
    return)
  (func $dynrt_lib_modc__fn124 (param i32) (result i32)
    (local i32)
    local.get 0
    i32.const 2334
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
  (func $dynrt_lib_modc__fn125 (param i32) (result i32)
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
      i32.const 2327
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
        i32.const 2327
        i32.const 7
        call $dynrt_lib_modc_dynGet
        local.set 1
        local.get 0
        call $dynrt_lib_modc__fn124
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            global.get $dynrt_lib_modc_global21
            i32.const 1
            i32.eq
            if  ;; label = @5
              block  ;; label = @6
                i32.const 1
                global.set $dynrt_lib_modc_global28
                local.get 1
                global.set $dynrt_lib_modc_global29
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
  (func $dynrt_lib_modc__fn126 (param i32 i32 i32) (result i32)
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
    i32.const 2343
    i32.const 7
    call $dynrt_lib_modc__fn159
    i32.const 1
    i32.eq
    if  ;; label = @1
      local.get 4
      call $dynrt_lib_modc__fn122
      return
    end
    local.get 0
    local.get 1
    i32.const 2350
    i32.const 6
    call $dynrt_lib_modc__fn159
    i32.const 1
    i32.eq
    if  ;; label = @1
      local.get 4
      call $dynrt_lib_modc__fn123
      return
    end
    local.get 0
    local.get 1
    i32.const 2356
    i32.const 3
    call $dynrt_lib_modc__fn159
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
                      i32.const 2327
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
                        call $dynrt_lib_modc__fn124
                        i32.const 1
                        i32.eq
                        if  ;; label = @11
                          local.get 7
                          return
                        end
                        local.get 5
                        local.get 7
                        i32.const 2327
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
        call $dynrt_lib_modc__fn122
        return
      end
    end
    call $dynrt_lib_modc_dynUndefined
    return)
  (func $dynrt_lib_modc__fn127 (param i32 i32 i32 i32) (result i32)
    (local i32) (local i32) (local i32)
    local.get 3
    call $dynrt_lib_modc_dynArrLen
    local.set 4
    local.get 0
    i32.const 2327
    i32.const 7
    call $dynrt_lib_modc_dynGet
    local.set 5
    local.get 0
    call $dynrt_lib_modc__fn124
    local.set 6
    local.get 1
    local.get 2
    i32.const 2359
    i32.const 4
    call $dynrt_lib_modc__fn159
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
                call $dynrt_lib_modc__fn122
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
            call $dynrt_lib_modc__fn122
            return
          end
        end
        local.get 0
        return
      end
    end
    local.get 1
    local.get 2
    i32.const 2363
    i32.const 5
    call $dynrt_lib_modc__fn159
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
            call $dynrt_lib_modc__fn122
            return
          end
        end
        local.get 0
        return
      end
    end
    local.get 1
    local.get 2
    i32.const 2368
    i32.const 7
    call $dynrt_lib_modc__fn159
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
  (func $dynrt_lib_modc__fn128 (param i32 i32 i32)
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
          call $dynrt_lib_modc__fn92
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
            call $dynrt_lib_modc__fn78
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
        call $dynrt_lib_modc__fn79
        global.get $dynrt_lib_modc_global1
        local.tee 8
        local.set 2
        global.get $dynrt_lib_modc_global2
        local.tee 9
        local.set 3
        local.get 1
        call $dynrt_lib_modc__fn79
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
    local.get 0
    i32.store
    local.get 1
    local.tee 2
    return)
  (func $dynrt_lib_modc__fn142 (param i32 i32 i32) (result i32)
    (local i32) (local i32)
    call $dynrt_lib_modc__fn47
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
    call $dynrt_lib_modc__fn142
    return)
  (func $dynrt_lib_modc_dynMakeHostFn (param i32) (result i32)
    (local i32) (local i32)
    call $dynrt_lib_modc__fn47
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
  (func $dynrt_lib_modc__fn146 (param i32 i32 i32) (result i32)
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
  (func $dynrt_lib_modc__fn147 (param i32) (result i32)
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
  (func $dynrt_lib_modc__fn148 (param i32 i32 i32 i32)
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
  (func $dynrt_lib_modc__fn149 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 1
    call $dynrt_lib_modc__fn147
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
    call $dynrt_lib_modc__fn29
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
            call $dynrt_lib_modc__fn30
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
            call $dynrt_lib_modc__fn30
            local.set 8
            local.get 3
            i32.const 8
            i32.add
            i32.const 4
            i32.add
            i32.load
            local.get 6
            call $dynrt_lib_modc__fn30
            local.set 9
            local.get 7
            local.tee 13
            local.set 7
            i32.const 8
            local.get 8
            i32.add
            call $dynrt_lib_modc__fn38
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
            call $dynrt_lib_modc__fn32
            local.set 7
            local.get 7
            local.get 8
            call $dynrt_lib_modc__fn32
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
            call $dynrt_lib_modc__fn32
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
    call $dynrt_lib_modc__fn151
    return)
  (func $dynrt_lib_modc__fn151 (param i32 i32 i32) (result i32)
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
          i32.const 2375
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
                call $dynrt_lib_modc__fn78
                global.get $dynrt_lib_modc_global1
                local.set 10
                global.get $dynrt_lib_modc_global2
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
        call $dynrt_lib_modc__fn78
        global.get $dynrt_lib_modc_global1
        local.set 3
        global.get $dynrt_lib_modc_global2
        local.set 5
        global.get $dynrt_lib_modc_global30
        local.tee 20
        local.set 6
        local.get 4
        i32.const -3
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            call $dynrt_lib_modc_dynArray
            global.set $dynrt_lib_modc_global30
            global.get $dynrt_lib_modc_global30
            call $dynrt_lib_modc__fn54
          end
        end
        global.get $dynrt_lib_modc_global30
        local.tee 21
        local.set 7
        global.get $dynrt_lib_modc_global19
        local.set 9
        global.get $dynrt_lib_modc_global20
        local.set 10
        global.get $dynrt_lib_modc_global21
        local.set 11
        global.get $dynrt_lib_modc_global23
        local.set 12
        global.get $dynrt_lib_modc_global24
        local.set 13
        global.get $dynrt_lib_modc_global25
        local.set 14
        local.get 3
        local.get 5
        local.get 8
        call $dynrt_lib_modc_dynRun
        local.set 3
        local.get 9
        local.tee 22
        global.set $dynrt_lib_modc_global19
        local.get 10
        global.set $dynrt_lib_modc_global20
        local.get 11
        global.set $dynrt_lib_modc_global21
        local.get 12
        global.set $dynrt_lib_modc_global23
        local.get 13
        global.set $dynrt_lib_modc_global24
        local.get 14
        global.set $dynrt_lib_modc_global25
        local.get 4
        i32.const -3
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            call $dynrt_lib_modc__fn55
            local.get 6
            global.set $dynrt_lib_modc_global30
            call $dynrt_lib_modc_dynObject
            local.set 3
            local.get 3
            i32.const 2306
            i32.const 6
            local.get 7
            call $dynrt_lib_modc_dynSet
            local.get 3
            i32.const 2312
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
            global.get $dynrt_lib_modc_global28
            i32.const 1
            i32.eq
            if  ;; label = @5
              block  ;; label = @6
                global.get $dynrt_lib_modc_global29
                local.set 3
                i32.const 0
                global.set $dynrt_lib_modc_global28
                local.get 3
                call $dynrt_lib_modc__fn123
                return
              end
            end
            local.get 3
            call $dynrt_lib_modc__fn122
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
        global.get $dynrt_lib_modc_global22
        local.tee 24
        i32.const 1
        i32.add
        global.set $dynrt_lib_modc_global22
        global.get $dynrt_lib_modc_global22
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
    i32.const 2217
    i32.const 3
    i32.const 0
    call $dynrt_lib_modc_dynBuiltin
    call $dynrt_lib_modc_dynSet
    local.get 0
    i32.const 2220
    i32.const 4
    i32.const 1
    call $dynrt_lib_modc_dynBuiltin
    call $dynrt_lib_modc_dynSet
    local.get 0
    i32.const 2203
    i32.const 5
    i32.const 2
    call $dynrt_lib_modc_dynBuiltin
    call $dynrt_lib_modc_dynSet
    local.get 0
    i32.const 2208
    i32.const 4
    i32.const 3
    call $dynrt_lib_modc_dynBuiltin
    call $dynrt_lib_modc_dynSet
    local.get 0
    i32.const 2212
    i32.const 5
    i32.const 4
    call $dynrt_lib_modc_dynBuiltin
    call $dynrt_lib_modc_dynSet
    local.get 0
    i32.const 2236
    i32.const 3
    i32.const 5
    call $dynrt_lib_modc_dynBuiltin
    call $dynrt_lib_modc_dynSet
    local.get 0
    i32.const 2233
    i32.const 3
    i32.const 6
    call $dynrt_lib_modc_dynBuiltin
    call $dynrt_lib_modc_dynSet
    local.get 0
    i32.const 2379
    i32.const 3
    i32.const 7
    call $dynrt_lib_modc_dynBuiltin
    call $dynrt_lib_modc_dynSet
    local.get 0
    i32.const 2382
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
  (func $dynrt_lib_modc__fn159 (param i32 i32 i32 i32) (result i32)
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
        local.get 1
        local.get 2
        i32.const 2385
        i32.const 4
        call $dynrt_lib_modc__fn159
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 0
            i32.const 2258
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
            i32.const 2270
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
        i32.const 2389
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
                        call $dynrt_lib_modc__fn151
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
        i32.const 2395
        i32.const 6
        call $dynrt_lib_modc__fn159
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
        i32.const 2395
        i32.const 6
        call $dynrt_lib_modc__fn159
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
  (func $dynrt_lib_modc__fn161 (param i32 i32 i32 i32)
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
        i32.const 2401
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
                        call $dynrt_lib_modc__fn151
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
            call $dynrt_lib_modc__fn78
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
  (func $dynrt_lib_modc__fn163 (param i32 i32) (result i32)
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
  (func $dynrt_lib_modc__fn164 (param i32 i32)
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
  (func $dynrt_lib_modc__fn165 (param i32 i32) (result i32)
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
  (func $dynrt_lib_modc__fn166 (param i32 i32) (result i32)
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
  (func $dynrt_lib_modc__fn167 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32)
    global.get $dynrt_lib_modc_global19
    local.tee 4
    local.set 2
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn165
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
            call $dynrt_lib_modc__fn165
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
        call $dynrt_lib_modc__fn165
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
                call $dynrt_lib_modc__fn165
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
        call $dynrt_lib_modc__fn165
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
            call $dynrt_lib_modc__fn165
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
                call $dynrt_lib_modc__fn165
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
    call $dynrt_lib_modc__fn22
    call $dynrt_lib_modc_dynNumber
    return)
  (func $dynrt_lib_modc__fn168 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn165
    local.set 2
    global.get $dynrt_lib_modc_global19
    i32.const 1
    local.tee 16
    i32.add
    global.set $dynrt_lib_modc_global19
    i32.const 1936
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
  (func $dynrt_lib_modc__fn169 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn164
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn165
    local.set 2
    local.get 2
    i32.const 40
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn200
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn196
            local.set 2
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn164
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn165
            i32.const 61
            i32.eq
            if (result i32)  ;; label = @5
              local.get 0
              local.get 1
              call $dynrt_lib_modc__fn166
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
            call $dynrt_lib_modc__fn198
            global.get $dynrt_lib_modc_global20
            call $dynrt_lib_modc__fn142
            return
          end
        end
        global.get $dynrt_lib_modc_global19
        i32.const 1
        i32.add
        global.set $dynrt_lib_modc_global19
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn179
        local.set 2
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn164
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn165
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
      call $dynrt_lib_modc__fn168
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
        call $dynrt_lib_modc__fn164
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn165
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
                call $dynrt_lib_modc__fn164
                i32.const 0
                local.set 4
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn165
                i32.const 46
                i32.eq
                if (result i32)  ;; label = @7
                  local.get 0
                  local.get 1
                  call $dynrt_lib_modc__fn166
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
                    call $dynrt_lib_modc__fn179
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
                                local.tee 8
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
                  call $dynrt_lib_modc__fn179
                  call $dynrt_lib_modc_dynPush
                end
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn164
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn165
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
                    call $dynrt_lib_modc__fn164
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn165
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
        call $dynrt_lib_modc__fn164
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn165
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
        call $dynrt_lib_modc__fn164
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn165
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
                call $dynrt_lib_modc__fn164
                i32.const 0
                local.tee 9
                drop
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn165
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
                    call $dynrt_lib_modc__fn168
                    call $dynrt_lib_modc__fn78
                    global.get $dynrt_lib_modc_global1
                    local.set 4
                    global.get $dynrt_lib_modc_global2
                    local.set 5
                  end
                else
                  block  ;; label = @8
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn182
                    global.get $dynrt_lib_modc_global1
                    local.set 4
                    global.get $dynrt_lib_modc_global2
                    local.set 5
                  end
                end
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn164
                i32.const 0
                local.tee 10
                drop
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn165
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
                    call $dynrt_lib_modc__fn179
                    local.set 6
                  end
                else
                  local.get 0
                  local.get 1
                  call $dynrt_lib_modc__fn165
                  i32.const 40
                  i32.eq
                  if  ;; label = @8
                    block  ;; label = @9
                      local.get 0
                      local.get 1
                      call $dynrt_lib_modc__fn196
                      local.set 6
                      local.get 0
                      local.get 1
                      call $dynrt_lib_modc__fn164
                      local.get 6
                      local.get 0
                      local.get 1
                      call $dynrt_lib_modc__fn197
                      global.get $dynrt_lib_modc_global20
                      call $dynrt_lib_modc__fn142
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
                        call $dynrt_lib_modc__fn146
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
                call $dynrt_lib_modc__fn164
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn165
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
                    call $dynrt_lib_modc__fn164
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn165
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
        call $dynrt_lib_modc__fn164
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn165
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
        local.tee 14
        i32.const 1
        local.tee 15
        i32.add
        global.set $dynrt_lib_modc_global19
        i32.const 1936
        i32.const 0
        call $dynrt_lib_modc_dynString
        local.set 2
        global.get $dynrt_lib_modc_global19
        local.tee 16
        local.set 3
        i32.const 1
        local.tee 17
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
                call $dynrt_lib_modc__fn165
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
                      local.tee 11
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
                      call $dynrt_lib_modc__fn166
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
                        local.tee 12
                        i32.const 2
                        i32.add
                        global.set $dynrt_lib_modc_global19
                        local.get 0
                        local.get 1
                        call $dynrt_lib_modc__fn179
                        local.set 3
                        local.get 2
                        local.get 3
                        call $dynrt_lib_modc_dynAdd
                        local.set 2
                        local.get 0
                        local.get 1
                        call $dynrt_lib_modc__fn164
                        local.get 0
                        local.get 1
                        call $dynrt_lib_modc__fn165
                        i32.const 125
                        i32.eq
                        if  ;; label = @11
                          global.get $dynrt_lib_modc_global19
                          i32.const 1
                          i32.add
                          global.set $dynrt_lib_modc_global19
                        end
                        global.get $dynrt_lib_modc_global19
                        local.tee 13
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
      call $dynrt_lib_modc__fn167
      return
    end
    local.get 2
    i32.const 46
    i32.eq
    if  ;; label = @1
      local.get 0
      local.get 1
      call $dynrt_lib_modc__fn167
      return
    end
    local.get 2
    i32.const 0
    call $dynrt_lib_modc__fn163
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_lib_modc_global19
        local.tee 19
        local.set 3
        local.get 2
        local.set 2
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 2
              i32.const 1
              call $dynrt_lib_modc__fn163
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
                call $dynrt_lib_modc__fn165
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
        i32.const 2407
        i32.const 8
        call $dynrt_lib_modc__fn159
        i32.const 1
        i32.eq
        if  ;; label = @3
          local.get 0
          local.get 1
          call $dynrt_lib_modc__fn199
          return
        end
        local.get 3
        local.get 4
        i32.const 1941
        i32.const 4
        call $dynrt_lib_modc__fn159
        i32.const 1
        i32.eq
        if  ;; label = @3
          i32.const 1
          call $dynrt_lib_modc_dynBool
          return
        end
        local.get 3
        local.get 4
        i32.const 1936
        i32.const 5
        call $dynrt_lib_modc__fn159
        i32.const 1
        i32.eq
        if  ;; label = @3
          i32.const 0
          call $dynrt_lib_modc_dynBool
          return
        end
        local.get 3
        local.get 4
        i32.const 1945
        i32.const 4
        call $dynrt_lib_modc__fn159
        i32.const 1
        i32.eq
        if  ;; label = @3
          call $dynrt_lib_modc_dynNull
          return
        end
        local.get 3
        local.get 4
        i32.const 1949
        i32.const 9
        call $dynrt_lib_modc__fn159
        i32.const 1
        i32.eq
        if  ;; label = @3
          call $dynrt_lib_modc_dynUndefined
          return
        end
        local.get 3
        local.get 4
        i32.const 2415
        i32.const 5
        call $dynrt_lib_modc__fn159
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn164
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn165
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
              global.get $dynrt_lib_modc_global21
              i32.const 1
              i32.eq
              if (result i32)  ;; label = @6
                global.get $dynrt_lib_modc_global30
                i32.const -1
                i32.ne
              else
                i32.const 0
              end
              if  ;; label = @6
                global.get $dynrt_lib_modc_global30
                call $dynrt_lib_modc_dynUndefined
                call $dynrt_lib_modc_dynPush
              end
            else
              block  ;; label = @6
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn179
                local.set 2
                global.get $dynrt_lib_modc_global21
                i32.const 1
                i32.eq
                if (result i32)  ;; label = @7
                  global.get $dynrt_lib_modc_global30
                  i32.const -1
                  i32.ne
                else
                  i32.const 0
                end
                if  ;; label = @7
                  global.get $dynrt_lib_modc_global30
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
        i32.const 2420
        i32.const 6
        call $dynrt_lib_modc__fn159
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            global.get $dynrt_lib_modc_global19
            local.set 2
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn164
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn165
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
                call $dynrt_lib_modc__fn182
                global.get $dynrt_lib_modc_global1
                local.set 5
                global.get $dynrt_lib_modc_global2
                local.set 6
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn164
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn165
                i32.const 40
                i32.eq
                if  ;; label = @7
                  block  ;; label = @8
                    global.get $dynrt_lib_modc_global19
                    i32.const 1
                    i32.add
                    global.set $dynrt_lib_modc_global19
                    call $dynrt_lib_modc_dynArray
                    local.set 2
                    local.get 2
                    call $dynrt_lib_modc__fn54
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn164
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn165
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
                                call $dynrt_lib_modc__fn179
                                call $dynrt_lib_modc_dynPush
                                local.get 0
                                local.get 1
                                call $dynrt_lib_modc__fn164
                                local.get 0
                                local.get 1
                                call $dynrt_lib_modc__fn165
                                local.set 4
                                local.get 4
                                i32.const 44
                                i32.eq
                                if  ;; label = @15
                                  global.get $dynrt_lib_modc_global19
                                  i32.const 1
                                  i32.add
                                  global.set $dynrt_lib_modc_global19
                                else
                                  block  ;; label = @16
                                    local.get 4
                                    i32.const 41
                                    i32.eq
                                    if  ;; label = @17
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
                              br 1 (;@12;)
                            end
                          end
                        end
                      end
                    end
                    call $dynrt_lib_modc_dynUndefined
                    local.set 3
                    global.get $dynrt_lib_modc_global21
                    i32.const 1
                    i32.eq
                    if  ;; label = @9
                      local.get 5
                      local.get 6
                      local.get 2
                      call $dynrt_lib_modc__fn95
                      local.set 3
                    end
                    call $dynrt_lib_modc__fn55
                    local.get 3
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
        i32.const 2426
        i32.const 4
        call $dynrt_lib_modc__fn159
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            global.get $dynrt_lib_modc_global19
            local.set 2
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn164
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn165
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
                call $dynrt_lib_modc__fn182
                global.get $dynrt_lib_modc_global1
                local.set 5
                global.get $dynrt_lib_modc_global2
                local.set 6
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn164
                local.get 5
                local.get 6
                i32.const 2430
                i32.const 2
                call $dynrt_lib_modc__fn159
                i32.const 1
                i32.eq
                if  ;; label = @7
                  f64.const 0x1.921fb54442d18p+1 (;=3.141592653589793;)
                  call $dynrt_lib_modc_dynNumber
                  return
                end
                local.get 5
                local.get 6
                i32.const 2432
                i32.const 1
                call $dynrt_lib_modc__fn159
                i32.const 1
                i32.eq
                if  ;; label = @7
                  f64.const 0x1.5bf0a8b145769p+1 (;=2.718281828459045;)
                  call $dynrt_lib_modc_dynNumber
                  return
                end
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn165
                i32.const 40
                i32.eq
                if  ;; label = @7
                  block  ;; label = @8
                    global.get $dynrt_lib_modc_global19
                    i32.const 1
                    i32.add
                    global.set $dynrt_lib_modc_global19
                    call $dynrt_lib_modc_dynArray
                    local.set 2
                    local.get 2
                    call $dynrt_lib_modc__fn54
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn164
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn165
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
                                call $dynrt_lib_modc__fn179
                                call $dynrt_lib_modc_dynPush
                                local.get 0
                                local.get 1
                                call $dynrt_lib_modc__fn164
                                local.get 0
                                local.get 1
                                call $dynrt_lib_modc__fn165
                                local.set 4
                                local.get 4
                                i32.const 44
                                i32.eq
                                if  ;; label = @15
                                  global.get $dynrt_lib_modc_global19
                                  i32.const 1
                                  i32.add
                                  global.set $dynrt_lib_modc_global19
                                else
                                  block  ;; label = @16
                                    local.get 4
                                    i32.const 41
                                    i32.eq
                                    if  ;; label = @17
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
                              br 1 (;@12;)
                            end
                          end
                        end
                      end
                    end
                    call $dynrt_lib_modc_dynUndefined
                    local.set 3
                    global.get $dynrt_lib_modc_global21
                    i32.const 1
                    i32.eq
                    if  ;; label = @9
                      local.get 5
                      local.get 6
                      local.get 2
                      call $dynrt_lib_modc__fn96
                      local.set 3
                    end
                    call $dynrt_lib_modc__fn55
                    local.get 3
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
        i32.const 2433
        i32.const 4
        call $dynrt_lib_modc__fn159
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            global.get $dynrt_lib_modc_global19
            local.set 2
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn164
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn165
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
                call $dynrt_lib_modc__fn182
                global.get $dynrt_lib_modc_global1
                local.set 5
                global.get $dynrt_lib_modc_global2
                local.set 6
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn164
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn165
                i32.const 40
                i32.eq
                if  ;; label = @7
                  block  ;; label = @8
                    global.get $dynrt_lib_modc_global19
                    i32.const 1
                    i32.add
                    global.set $dynrt_lib_modc_global19
                    call $dynrt_lib_modc_dynArray
                    local.set 2
                    local.get 2
                    call $dynrt_lib_modc__fn54
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn164
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn165
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
                                call $dynrt_lib_modc__fn179
                                call $dynrt_lib_modc_dynPush
                                local.get 0
                                local.get 1
                                call $dynrt_lib_modc__fn164
                                local.get 0
                                local.get 1
                                call $dynrt_lib_modc__fn165
                                local.set 4
                                local.get 4
                                i32.const 44
                                i32.eq
                                if  ;; label = @15
                                  global.get $dynrt_lib_modc_global19
                                  i32.const 1
                                  i32.add
                                  global.set $dynrt_lib_modc_global19
                                else
                                  block  ;; label = @16
                                    local.get 4
                                    i32.const 41
                                    i32.eq
                                    if  ;; label = @17
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
                              br 1 (;@12;)
                            end
                          end
                        end
                      end
                    end
                    call $dynrt_lib_modc_dynUndefined
                    local.set 3
                    global.get $dynrt_lib_modc_global21
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
                        i32.const 2437
                        i32.const 5
                        call $dynrt_lib_modc__fn159
                        i32.const 1
                        i32.eq
                        if  ;; label = @11
                          block  ;; label = @12
                            local.get 4
                            call $dynrt_lib_modc__fn78
                            global.get $dynrt_lib_modc_global1
                            local.set 2
                            global.get $dynrt_lib_modc_global2
                            local.set 3
                            local.get 2
                            local.get 3
                            call $dynrt_lib_modc__fn99
                            local.set 3
                          end
                        else
                          local.get 5
                          local.get 6
                          i32.const 2442
                          i32.const 9
                          call $dynrt_lib_modc__fn159
                          i32.const 1
                          i32.eq
                          if  ;; label = @12
                            block  ;; label = @13
                              local.get 4
                              call $dynrt_lib_modc__fn98
                              global.get $dynrt_lib_modc_global1
                              local.set 2
                              global.get $dynrt_lib_modc_global2
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
                    call $dynrt_lib_modc__fn55
                    local.get 3
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
        i32.const 2451
        i32.const 7
        call $dynrt_lib_modc__fn159
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            global.get $dynrt_lib_modc_global19
            local.set 2
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn164
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn165
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
                call $dynrt_lib_modc__fn182
                global.get $dynrt_lib_modc_global1
                local.set 5
                global.get $dynrt_lib_modc_global2
                local.set 6
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn164
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn165
                i32.const 40
                i32.eq
                if  ;; label = @7
                  block  ;; label = @8
                    global.get $dynrt_lib_modc_global19
                    i32.const 1
                    i32.add
                    global.set $dynrt_lib_modc_global19
                    call $dynrt_lib_modc_dynArray
                    local.set 2
                    local.get 2
                    call $dynrt_lib_modc__fn54
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn164
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn165
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
                                call $dynrt_lib_modc__fn179
                                call $dynrt_lib_modc_dynPush
                                local.get 0
                                local.get 1
                                call $dynrt_lib_modc__fn164
                                local.get 0
                                local.get 1
                                call $dynrt_lib_modc__fn165
                                local.set 4
                                local.get 4
                                i32.const 44
                                i32.eq
                                if  ;; label = @15
                                  global.get $dynrt_lib_modc_global19
                                  i32.const 1
                                  i32.add
                                  global.set $dynrt_lib_modc_global19
                                else
                                  block  ;; label = @16
                                    local.get 4
                                    i32.const 41
                                    i32.eq
                                    if  ;; label = @17
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
                              br 1 (;@12;)
                            end
                          end
                        end
                      end
                    end
                    call $dynrt_lib_modc_dynUndefined
                    local.set 3
                    global.get $dynrt_lib_modc_global21
                    i32.const 1
                    i32.eq
                    if  ;; label = @9
                      local.get 5
                      local.get 6
                      local.get 2
                      call $dynrt_lib_modc__fn126
                      local.set 3
                    end
                    call $dynrt_lib_modc__fn55
                    local.get 3
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
        i32.const 2458
        i32.const 3
        call $dynrt_lib_modc__fn159
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn164
            global.get $dynrt_lib_modc_global19
            local.tee 18
            local.set 2
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn165
            local.set 3
            block  ;; label = @5
              loop  ;; label = @6
                block  ;; label = @7
                  local.get 3
                  i32.const 1
                  call $dynrt_lib_modc__fn163
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
                    call $dynrt_lib_modc__fn165
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
            local.set 5
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
              local.get 5
              call $dynrt_lib_modc__fn146
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
            call $dynrt_lib_modc__fn54
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn164
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn165
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
                call $dynrt_lib_modc__fn164
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn165
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
                            call $dynrt_lib_modc__fn179
                            local.set 4
                            local.get 7
                            local.get 4
                            call $dynrt_lib_modc_dynPush
                            local.get 0
                            local.get 1
                            call $dynrt_lib_modc__fn164
                            local.get 0
                            local.get 1
                            call $dynrt_lib_modc__fn165
                            local.set 4
                            local.get 4
                            i32.const 44
                            i32.eq
                            if  ;; label = @13
                              global.get $dynrt_lib_modc_global19
                              i32.const 1
                              i32.add
                              global.set $dynrt_lib_modc_global19
                            else
                              block  ;; label = @14
                                local.get 4
                                i32.const 41
                                i32.eq
                                if  ;; label = @15
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
            global.get $dynrt_lib_modc_global21
            i32.const 1
            i32.eq
            if  ;; label = @5
              local.get 2
              local.get 5
              i32.const 2461
              i32.const 3
              call $dynrt_lib_modc__fn159
              i32.const 1
              i32.eq
              if  ;; label = @6
                call $dynrt_lib_modc__fn103
                local.set 3
              else
                local.get 2
                local.get 5
                i32.const 2464
                i32.const 3
                call $dynrt_lib_modc__fn159
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
                    call $dynrt_lib_modc__fn104
                    local.set 3
                  end
                else
                  local.get 2
                  local.get 5
                  i32.const 2467
                  i32.const 6
                  call $dynrt_lib_modc__fn159
                  i32.const 1
                  i32.eq
                  if  ;; label = @8
                    block  ;; label = @9
                      i32.const 1936
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
                      call $dynrt_lib_modc__fn119
                      local.set 3
                    end
                  else
                    local.get 6
                    local.get 7
                    call $dynrt_lib_modc__fn203
                    local.set 3
                  end
                end
              end
            end
            call $dynrt_lib_modc__fn55
            local.get 3
            return
          end
        end
        local.get 3
        local.get 4
        i32.const 2473
        i32.const 5
        call $dynrt_lib_modc__fn159
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn164
            global.get $dynrt_lib_modc_global20
            i32.const -1
            i32.eq
            if (result i32)  ;; label = @5
              i32.const -1
            else
              global.get $dynrt_lib_modc_global20
              i32.const 2375
              i32.const 4
              call $dynrt_lib_modc__fn146
            end
            local.set 2
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn165
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
                local.set 7
                local.get 7
                call $dynrt_lib_modc__fn54
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn164
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn165
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
                            call $dynrt_lib_modc__fn179
                            call $dynrt_lib_modc_dynPush
                            local.get 0
                            local.get 1
                            call $dynrt_lib_modc__fn164
                            local.get 0
                            local.get 1
                            call $dynrt_lib_modc__fn165
                            local.set 4
                            local.get 4
                            i32.const 44
                            i32.eq
                            if  ;; label = @13
                              global.get $dynrt_lib_modc_global19
                              i32.const 1
                              i32.add
                              global.set $dynrt_lib_modc_global19
                            else
                              block  ;; label = @14
                                local.get 4
                                i32.const 41
                                i32.eq
                                if  ;; label = @15
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
                    i32.const 2478
                    i32.const 12
                    call $dynrt_lib_modc__fn146
                    local.set 3
                    local.get 3
                    i32.const -1
                    i32.ne
                    if  ;; label = @9
                      block  ;; label = @10
                        local.get 3
                        i32.const 2490
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
                              call $dynrt_lib_modc__fn151
                              drop
                            end
                          end
                        end
                      end
                    end
                  end
                end
                call $dynrt_lib_modc__fn55
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
                call $dynrt_lib_modc__fn182
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
                  i32.const 2496
                  i32.const 12
                  call $dynrt_lib_modc__fn146
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
                call $dynrt_lib_modc__fn164
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn165
                i32.const 40
                i32.eq
                if  ;; label = @7
                  block  ;; label = @8
                    global.get $dynrt_lib_modc_global19
                    i32.const 1
                    i32.add
                    global.set $dynrt_lib_modc_global19
                    call $dynrt_lib_modc_dynArray
                    local.set 7
                    local.get 7
                    call $dynrt_lib_modc__fn54
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn164
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn165
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
                                call $dynrt_lib_modc__fn179
                                call $dynrt_lib_modc_dynPush
                                local.get 0
                                local.get 1
                                call $dynrt_lib_modc__fn164
                                local.get 0
                                local.get 1
                                call $dynrt_lib_modc__fn165
                                local.set 4
                                local.get 4
                                i32.const 44
                                i32.eq
                                if  ;; label = @15
                                  global.get $dynrt_lib_modc_global19
                                  i32.const 1
                                  i32.add
                                  global.set $dynrt_lib_modc_global19
                                else
                                  block  ;; label = @16
                                    local.get 4
                                    i32.const 41
                                    i32.eq
                                    if  ;; label = @17
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
                              br 1 (;@12;)
                            end
                          end
                        end
                      end
                    end
                    call $dynrt_lib_modc_dynUndefined
                    local.set 3
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
                          call $dynrt_lib_modc__fn151
                          local.set 3
                        end
                      end
                    end
                    call $dynrt_lib_modc__fn55
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
        call $dynrt_lib_modc__fn164
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn165
        i32.const 61
        i32.eq
        if (result i32)  ;; label = @3
          local.get 0
          local.get 1
          call $dynrt_lib_modc__fn166
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
            call $dynrt_lib_modc__fn198
            global.get $dynrt_lib_modc_global20
            call $dynrt_lib_modc__fn142
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
        call $dynrt_lib_modc__fn146
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
  (func $dynrt_lib_modc__fn170 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn169
    local.set 2
    i32.const 1
    local.set 3
    i32.const -1
    local.set 4
    i32.const 1936
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
            call $dynrt_lib_modc__fn164
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn165
            local.set 8
            i32.const 0
            local.set 9
            local.get 8
            i32.const 63
            i32.eq
            if (result i32)  ;; label = @5
              local.get 0
              local.get 1
              call $dynrt_lib_modc__fn166
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
                call $dynrt_lib_modc__fn164
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn165
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
                    call $dynrt_lib_modc__fn179
                    local.set 9
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn164
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn165
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
                    call $dynrt_lib_modc__fn165
                    local.set 5
                    block  ;; label = @9
                      loop  ;; label = @10
                        block  ;; label = @11
                          local.get 5
                          i32.const 1
                          call $dynrt_lib_modc__fn163
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
                            call $dynrt_lib_modc__fn165
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
                  call $dynrt_lib_modc__fn164
                  global.get $dynrt_lib_modc_global19
                  local.tee 14
                  local.set 4
                  local.get 0
                  local.get 1
                  call $dynrt_lib_modc__fn165
                  local.set 5
                  block  ;; label = @8
                    loop  ;; label = @9
                      block  ;; label = @10
                        local.get 5
                        i32.const 1
                        call $dynrt_lib_modc__fn163
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
                          call $dynrt_lib_modc__fn165
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
                    call $dynrt_lib_modc__fn179
                    local.set 8
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn164
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn165
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
                    i32.const 1936
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
                      call $dynrt_lib_modc__fn54
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
                        call $dynrt_lib_modc__fn54
                      end
                      call $dynrt_lib_modc_dynArray
                      local.set 9
                      local.get 9
                      call $dynrt_lib_modc__fn54
                      local.get 0
                      local.get 1
                      call $dynrt_lib_modc__fn164
                      local.get 0
                      local.get 1
                      call $dynrt_lib_modc__fn165
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
                                  call $dynrt_lib_modc__fn179
                                  local.set 11
                                  local.get 9
                                  local.get 11
                                  call $dynrt_lib_modc_dynPush
                                  local.get 0
                                  local.get 1
                                  call $dynrt_lib_modc__fn164
                                  local.get 0
                                  local.get 1
                                  call $dynrt_lib_modc__fn165
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
                              call $dynrt_lib_modc__fn93
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
                                call $dynrt_lib_modc__fn94
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
                                  i32.const 2258
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
                                  call $dynrt_lib_modc__fn105
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
                                    i32.const 2270
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
                                    call $dynrt_lib_modc__fn106
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
                                      i32.const 2167
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
                                      call $dynrt_lib_modc__fn120
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
                                        i32.const 2306
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
                                        call $dynrt_lib_modc__fn121
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
                                          i32.const 2327
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
                                          call $dynrt_lib_modc__fn127
                                          local.set 2
                                        else
                                          local.get 2
                                          local.get 9
                                          local.get 4
                                          call $dynrt_lib_modc__fn151
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
                      call $dynrt_lib_modc__fn55
                      local.get 8
                      i32.const 1
                      i32.eq
                      if  ;; label = @10
                        call $dynrt_lib_modc__fn55
                      end
                      call $dynrt_lib_modc__fn55
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
  (func $dynrt_lib_modc__fn171 (param i32) (result i32)
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
      i32.const 1949
      i32.const 9
      call $dynrt_lib_modc_dynString
      return
    end
    local.get 1
    i32.const 2
    i32.eq
    if  ;; label = @1
      i32.const 2508
      i32.const 7
      call $dynrt_lib_modc_dynString
      return
    end
    local.get 1
    i32.const 3
    i32.eq
    if  ;; label = @1
      i32.const 2515
      i32.const 6
      call $dynrt_lib_modc_dynString
      return
    end
    local.get 1
    i32.const 4
    i32.eq
    if  ;; label = @1
      i32.const 2521
      i32.const 6
      call $dynrt_lib_modc_dynString
      return
    end
    local.get 1
    i32.const 7
    i32.eq
    if  ;; label = @1
      i32.const 2407
      i32.const 8
      call $dynrt_lib_modc_dynString
      return
    end
    i32.const 2527
    i32.const 6
    call $dynrt_lib_modc_dynString
    return)
  (func $dynrt_lib_modc__fn172 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn164
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn165
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
        call $dynrt_lib_modc__fn172
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
        call $dynrt_lib_modc__fn172
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
        call $dynrt_lib_modc__fn172
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
        local.set 3
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn182
        global.get $dynrt_lib_modc_global1
        local.set 4
        global.get $dynrt_lib_modc_global2
        local.set 5
        local.get 4
        local.get 5
        i32.const 2533
        i32.const 6
        call $dynrt_lib_modc__fn159
        i32.const 1
        i32.eq
        if  ;; label = @3
          local.get 0
          local.get 1
          call $dynrt_lib_modc__fn172
          call $dynrt_lib_modc__fn171
          return
        end
        local.get 3
        global.set $dynrt_lib_modc_global19
      end
    end
    local.get 2
    i32.const 97
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_lib_modc_global19
        local.set 3
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn182
        global.get $dynrt_lib_modc_global1
        local.set 4
        global.get $dynrt_lib_modc_global2
        local.set 5
        local.get 4
        local.get 5
        i32.const 2539
        i32.const 5
        call $dynrt_lib_modc__fn159
        i32.const 1
        i32.eq
        if  ;; label = @3
          local.get 0
          local.get 1
          call $dynrt_lib_modc__fn172
          call $dynrt_lib_modc__fn125
          return
        end
        local.get 3
        global.set $dynrt_lib_modc_global19
      end
    end
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn170
    return)
  (func $dynrt_lib_modc__fn173 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn172
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
            call $dynrt_lib_modc__fn164
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn165
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
                call $dynrt_lib_modc__fn54
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn172
                local.set 5
                call $dynrt_lib_modc__fn55
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
  (func $dynrt_lib_modc__fn174 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn173
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
            call $dynrt_lib_modc__fn164
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn165
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
                call $dynrt_lib_modc__fn54
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn173
                local.set 5
                call $dynrt_lib_modc__fn55
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
  (func $dynrt_lib_modc__fn175 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn174
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
            call $dynrt_lib_modc__fn164
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn165
            local.set 4
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn166
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
                call $dynrt_lib_modc__fn54
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn174
                local.set 6
                call $dynrt_lib_modc__fn55
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
  (func $dynrt_lib_modc__fn176 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn175
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
            call $dynrt_lib_modc__fn164
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn165
            local.set 4
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn166
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
                call $dynrt_lib_modc__fn165
                i32.const 61
                i32.eq
                if  ;; label = @7
                  global.get $dynrt_lib_modc_global19
                  i32.const 1
                  i32.add
                  global.set $dynrt_lib_modc_global19
                end
                local.get 2
                call $dynrt_lib_modc__fn54
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn175
                local.set 4
                call $dynrt_lib_modc__fn55
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
                  call $dynrt_lib_modc__fn165
                  i32.const 61
                  i32.eq
                  if  ;; label = @8
                    global.get $dynrt_lib_modc_global19
                    i32.const 1
                    i32.add
                    global.set $dynrt_lib_modc_global19
                  end
                  local.get 2
                  call $dynrt_lib_modc__fn54
                  local.get 0
                  local.get 1
                  call $dynrt_lib_modc__fn175
                  local.set 4
                  call $dynrt_lib_modc__fn55
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
  (func $dynrt_lib_modc__fn177 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn176
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
            call $dynrt_lib_modc__fn164
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn165
            i32.const 38
            i32.eq
            if (result i32)  ;; label = @5
              local.get 0
              local.get 1
              call $dynrt_lib_modc__fn166
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
                call $dynrt_lib_modc__fn54
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn176
                local.set 6
                call $dynrt_lib_modc__fn55
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
  (func $dynrt_lib_modc__fn178 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn177
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
            call $dynrt_lib_modc__fn164
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn165
            i32.const 124
            i32.eq
            if (result i32)  ;; label = @5
              local.get 0
              local.get 1
              call $dynrt_lib_modc__fn166
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
                call $dynrt_lib_modc__fn54
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn177
                local.set 6
                call $dynrt_lib_modc__fn55
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
              call $dynrt_lib_modc__fn165
              i32.const 63
              i32.eq
              if (result i32)  ;; label = @6
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn166
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
                  call $dynrt_lib_modc__fn54
                  local.get 0
                  local.get 1
                  call $dynrt_lib_modc__fn177
                  local.set 6
                  call $dynrt_lib_modc__fn55
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
  (func $dynrt_lib_modc__fn179 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn178
    local.set 2
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn164
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn165
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
        call $dynrt_lib_modc__fn179
        local.set 4
        local.get 3
        local.tee 6
        global.set $dynrt_lib_modc_global21
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn164
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn165
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
        call $dynrt_lib_modc__fn54
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn179
        local.set 5
        call $dynrt_lib_modc__fn55
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
    call $dynrt_lib_modc__fn179
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
    call $dynrt_lib_modc__fn179
    return)
  (func $dynrt_lib_modc__fn182 (param i32 i32)
    (local i32) (local i32) (local i32) (local i32)
    global.get $dynrt_lib_modc_global19
    local.tee 4
    local.set 2
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn165
    local.set 3
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 3
          i32.const 1
          call $dynrt_lib_modc__fn163
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
            call $dynrt_lib_modc__fn165
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
  (func $dynrt_lib_modc__fn183 (param i32 i32)
    (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn164
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn182
    global.get $dynrt_lib_modc_global1
    local.set 2
    global.get $dynrt_lib_modc_global2
    local.set 3
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn164
    call $dynrt_lib_modc_dynUndefined
    local.set 4
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn165
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
        call $dynrt_lib_modc__fn179
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
    call $dynrt_lib_modc__fn164
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn165
    i32.const 59
    i32.eq
    if  ;; label = @1
      global.get $dynrt_lib_modc_global19
      i32.const 1
      i32.add
      global.set $dynrt_lib_modc_global19
    end)
  (func $dynrt_lib_modc__fn184 (param i32 i32)
    (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn164
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn165
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
      call $dynrt_lib_modc__fn179
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
    call $dynrt_lib_modc__fn164
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn165
    i32.const 59
    i32.eq
    if  ;; label = @1
      global.get $dynrt_lib_modc_global19
      i32.const 1
      i32.add
      global.set $dynrt_lib_modc_global19
    end)
  (func $dynrt_lib_modc__fn185 (param i32 i32)
    (local i32) (local i32) (local i32) (local i32) (local i32)
    global.get $dynrt_lib_modc_global21
    local.set 2
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn164
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn165
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
    call $dynrt_lib_modc__fn179
    local.set 3
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn164
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn165
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
    call $dynrt_lib_modc__fn204
    local.get 2
    global.set $dynrt_lib_modc_global21
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn164
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn165
    i32.const 0
    call $dynrt_lib_modc__fn163
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_lib_modc_global19
        local.set 4
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn182
        global.get $dynrt_lib_modc_global1
        local.set 5
        global.get $dynrt_lib_modc_global2
        local.set 6
        local.get 5
        local.get 6
        i32.const 2544
        i32.const 4
        call $dynrt_lib_modc__fn159
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
            call $dynrt_lib_modc__fn204
            local.get 2
            global.set $dynrt_lib_modc_global21
          end
        else
          local.get 4
          global.set $dynrt_lib_modc_global19
        end
      end
    end)
  (func $dynrt_lib_modc__fn186 (param i32 i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    global.get $dynrt_lib_modc_global21
    local.set 2
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn164
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn165
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
            call $dynrt_lib_modc__fn179
            local.set 6
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn164
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn165
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
                call $dynrt_lib_modc__fn204
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
                call $dynrt_lib_modc__fn204
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
  (func $dynrt_lib_modc__fn187 (param i32 i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    global.get $dynrt_lib_modc_global21
    local.set 2
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn164
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
            call $dynrt_lib_modc__fn204
            local.get 2
            local.tee 9
            global.set $dynrt_lib_modc_global21
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn164
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn165
            i32.const 0
            call $dynrt_lib_modc__fn163
            i32.const 1
            i32.eq
            if  ;; label = @5
              local.get 0
              local.get 1
              call $dynrt_lib_modc__fn182
            end
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn164
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn165
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
            call $dynrt_lib_modc__fn179
            local.set 4
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn164
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn165
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
            call $dynrt_lib_modc__fn164
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn165
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
  (func $dynrt_lib_modc__fn188 (param i32 i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    global.get $dynrt_lib_modc_global21
    local.set 2
    global.get $dynrt_lib_modc_global20
    local.set 3
    local.get 3
    call $dynrt_lib_modc__fn147
    local.set 4
    local.get 4
    local.tee 13
    global.set $dynrt_lib_modc_global20
    local.get 4
    call $dynrt_lib_modc__fn54
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn164
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn165
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
    call $dynrt_lib_modc__fn164
    i32.const 0
    local.tee 14
    local.set 5
    i32.const 1936
    local.set 6
    local.get 14
    local.set 7
    local.get 14
    local.set 8
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn165
    i32.const 0
    call $dynrt_lib_modc__fn163
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn182
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
        i32.const 2548
        i32.const 5
        call $dynrt_lib_modc__fn159
        i32.const 1
        i32.eq
        if (result i32)  ;; label = @3
          i32.const 1
        else
          local.get 9
          local.get 10
          i32.const 2553
          i32.const 3
          call $dynrt_lib_modc__fn159
          i32.const 1
          i32.eq
        end
        if (result i32)  ;; label = @3
          i32.const 1
        else
          local.get 9
          local.get 10
          i32.const 2556
          i32.const 3
          call $dynrt_lib_modc__fn159
          i32.const 1
          i32.eq
        end
        if  ;; label = @3
          block  ;; label = @4
            local.get 9
            local.get 10
            i32.const 2556
            i32.const 3
            call $dynrt_lib_modc__fn159
            i32.const 1
            i32.ne
            if  ;; label = @5
              i32.const 1
              local.set 8
            end
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn164
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn182
            global.get $dynrt_lib_modc_global1
            local.set 11
            global.get $dynrt_lib_modc_global2
            local.set 12
          end
        end
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn164
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn165
        i32.const 0
        call $dynrt_lib_modc__fn163
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn182
            global.get $dynrt_lib_modc_global1
            local.set 9
            global.get $dynrt_lib_modc_global2
            local.set 10
            local.get 9
            local.get 10
            i32.const 2559
            i32.const 2
            call $dynrt_lib_modc__fn159
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
              i32.const 2561
              i32.const 2
              call $dynrt_lib_modc__fn159
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
      call $dynrt_lib_modc__fn190
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
        call $dynrt_lib_modc__fn189
      else
        block  ;; label = @3
          local.get 4
          global.set $dynrt_lib_modc_global19
          local.get 0
          local.get 1
          local.get 2
          local.get 8
          call $dynrt_lib_modc__fn191
        end
      end
    end
    call $dynrt_lib_modc__fn55
    local.get 3
    local.tee 15
    global.set $dynrt_lib_modc_global20)
  (func $dynrt_lib_modc__fn189 (param i32 i32 i32 i32 i32 i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    global.get $dynrt_lib_modc_global20
    local.set 6
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn179
    local.set 7
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn164
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn165
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
        call $dynrt_lib_modc__fn204
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
              call $dynrt_lib_modc__fn147
              local.set 12
            end
            local.get 12
            local.get 2
            local.get 3
            local.get 7
            local.get 11
            call $dynrt_lib_modc__fn88
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
            call $dynrt_lib_modc__fn204
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
  (func $dynrt_lib_modc__fn190 (param i32 i32 i32 i32 i32 i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    global.get $dynrt_lib_modc_global20
    local.set 6
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn179
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
        i32.const 2306
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
    call $dynrt_lib_modc__fn164
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn165
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
        global.set $dynrt_lib_modc_global21
        local.get 8
        global.set $dynrt_lib_modc_global19
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn204
        local.get 4
        global.set $dynrt_lib_modc_global21
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
              call $dynrt_lib_modc__fn147
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
            call $dynrt_lib_modc__fn204
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
  (func $dynrt_lib_modc__fn191 (param i32 i32 i32 i32)
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
    call $dynrt_lib_modc__fn204
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
      call $dynrt_lib_modc__fn149
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
            call $dynrt_lib_modc__fn164
            i32.const 1
            local.set 10
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn165
            i32.const 59
            i32.ne
            if  ;; label = @5
              local.get 0
              local.get 1
              call $dynrt_lib_modc__fn179
              call $dynrt_lib_modc_dynToBool
              local.set 10
            end
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn164
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn165
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
            call $dynrt_lib_modc__fn165
            i32.const 41
            i32.ne
            if  ;; label = @5
              local.get 0
              local.get 1
              call $dynrt_lib_modc__fn204
            end
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn164
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn165
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
                call $dynrt_lib_modc__fn204
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
                        call $dynrt_lib_modc__fn149
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
                      call $dynrt_lib_modc__fn165
                      i32.const 41
                      i32.ne
                      if  ;; label = @10
                        local.get 0
                        local.get 1
                        call $dynrt_lib_modc__fn204
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
                call $dynrt_lib_modc__fn204
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
  (func $dynrt_lib_modc__fn192 (param i32 i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    global.get $dynrt_lib_modc_global21
    local.set 2
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn164
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn165
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
    call $dynrt_lib_modc__fn179
    local.set 3
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn164
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn165
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
    call $dynrt_lib_modc__fn164
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn165
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
            call $dynrt_lib_modc__fn164
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn165
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
              call $dynrt_lib_modc__fn163
              i32.const 1
              i32.eq
              if  ;; label = @6
                block  ;; label = @7
                  global.get $dynrt_lib_modc_global19
                  local.set 7
                  local.get 0
                  local.get 1
                  call $dynrt_lib_modc__fn182
                  global.get $dynrt_lib_modc_global1
                  local.set 8
                  global.get $dynrt_lib_modc_global2
                  local.set 9
                  local.get 8
                  local.get 9
                  i32.const 2563
                  i32.const 4
                  call $dynrt_lib_modc__fn159
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
                          call $dynrt_lib_modc__fn179
                          local.set 7
                          local.get 0
                          local.get 1
                          call $dynrt_lib_modc__fn164
                          local.get 0
                          local.get 1
                          call $dynrt_lib_modc__fn165
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
                          call $dynrt_lib_modc__fn179
                          drop
                          local.get 7
                          global.set $dynrt_lib_modc_global21
                          local.get 0
                          local.get 1
                          call $dynrt_lib_modc__fn164
                          local.get 0
                          local.get 1
                          call $dynrt_lib_modc__fn165
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
                      call $dynrt_lib_modc__fn193
                    end
                  else
                    local.get 8
                    local.get 9
                    i32.const 2567
                    i32.const 7
                    call $dynrt_lib_modc__fn159
                    i32.const 1
                    i32.eq
                    if  ;; label = @9
                      block  ;; label = @10
                        local.get 0
                        local.get 1
                        call $dynrt_lib_modc__fn164
                        local.get 0
                        local.get 1
                        call $dynrt_lib_modc__fn165
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
                        call $dynrt_lib_modc__fn193
                      end
                    else
                      block  ;; label = @10
                        local.get 7
                        global.set $dynrt_lib_modc_global19
                        local.get 0
                        local.get 1
                        call $dynrt_lib_modc__fn193
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
        call $dynrt_lib_modc__fn194
        local.get 2
        global.set $dynrt_lib_modc_global21
      end
    end
    local.get 3
    global.set $dynrt_lib_modc_global19
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn164
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn165
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
  (func $dynrt_lib_modc__fn193 (param i32 i32)
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
            call $dynrt_lib_modc__fn164
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn165
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
              call $dynrt_lib_modc__fn163
              i32.const 1
              i32.eq
              if  ;; label = @6
                block  ;; label = @7
                  global.get $dynrt_lib_modc_global19
                  local.set 3
                  local.get 0
                  local.get 1
                  call $dynrt_lib_modc__fn182
                  global.get $dynrt_lib_modc_global1
                  local.set 4
                  global.get $dynrt_lib_modc_global2
                  local.set 5
                  local.get 4
                  local.get 5
                  i32.const 2563
                  i32.const 4
                  call $dynrt_lib_modc__fn159
                  i32.const 1
                  i32.eq
                  if (result i32)  ;; label = @8
                    i32.const 1
                  else
                    local.get 4
                    local.get 5
                    i32.const 2567
                    i32.const 7
                    call $dynrt_lib_modc__fn159
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
                      call $dynrt_lib_modc__fn204
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
                  call $dynrt_lib_modc__fn204
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
  (func $dynrt_lib_modc__fn194 (param i32 i32)
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
            call $dynrt_lib_modc__fn164
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn165
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
              call $dynrt_lib_modc__fn163
              i32.const 1
              i32.eq
              if  ;; label = @6
                block  ;; label = @7
                  global.get $dynrt_lib_modc_global19
                  local.set 3
                  local.get 0
                  local.get 1
                  call $dynrt_lib_modc__fn182
                  global.get $dynrt_lib_modc_global1
                  local.set 4
                  global.get $dynrt_lib_modc_global2
                  local.set 5
                  local.get 4
                  local.get 5
                  i32.const 2563
                  i32.const 4
                  call $dynrt_lib_modc__fn159
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
                      call $dynrt_lib_modc__fn179
                      drop
                      local.get 3
                      global.set $dynrt_lib_modc_global21
                      local.get 0
                      local.get 1
                      call $dynrt_lib_modc__fn164
                      local.get 0
                      local.get 1
                      call $dynrt_lib_modc__fn165
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
                    i32.const 2567
                    i32.const 7
                    call $dynrt_lib_modc__fn159
                    i32.const 1
                    i32.eq
                    if  ;; label = @9
                      block  ;; label = @10
                        local.get 0
                        local.get 1
                        call $dynrt_lib_modc__fn164
                        local.get 0
                        local.get 1
                        call $dynrt_lib_modc__fn165
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
                        call $dynrt_lib_modc__fn204
                      end
                    end
                  end
                end
              else
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn204
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
  (func $dynrt_lib_modc__fn195 (param i32 i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    global.get $dynrt_lib_modc_global21
    local.set 2
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn164
    local.get 2
    local.tee 17
    global.set $dynrt_lib_modc_global21
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn204
    local.get 2
    local.tee 18
    global.set $dynrt_lib_modc_global21
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn164
    i32.const 0
    local.tee 19
    local.set 3
    global.get $dynrt_lib_modc_global19
    local.tee 20
    local.set 4
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn165
    i32.const 0
    call $dynrt_lib_modc__fn163
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn182
        global.get $dynrt_lib_modc_global1
        local.set 5
        global.get $dynrt_lib_modc_global2
        local.set 6
        local.get 5
        local.get 6
        i32.const 2363
        i32.const 5
        call $dynrt_lib_modc__fn159
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
        i32.const 1936
        local.set 3
        i32.const 0
        local.set 4
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn164
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn165
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
            call $dynrt_lib_modc__fn164
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn182
            global.get $dynrt_lib_modc_global1
            local.set 3
            global.get $dynrt_lib_modc_global2
            local.set 4
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn164
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn165
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
        call $dynrt_lib_modc__fn164
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
            call $dynrt_lib_modc__fn147
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
            call $dynrt_lib_modc__fn54
            i32.const 1
            global.set $dynrt_lib_modc_global21
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn204
            call $dynrt_lib_modc__fn55
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
            call $dynrt_lib_modc__fn204
            local.get 2
            global.set $dynrt_lib_modc_global21
          end
        end
      end
    end
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn164
    i32.const 0
    local.tee 21
    local.set 3
    global.get $dynrt_lib_modc_global19
    local.tee 22
    local.set 4
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn165
    i32.const 0
    call $dynrt_lib_modc__fn163
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn182
        global.get $dynrt_lib_modc_global1
        local.set 5
        global.get $dynrt_lib_modc_global2
        local.set 6
        local.get 5
        local.get 6
        i32.const 2368
        i32.const 7
        call $dynrt_lib_modc__fn159
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
        call $dynrt_lib_modc__fn164
        local.get 2
        local.tee 15
        global.set $dynrt_lib_modc_global21
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn204
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
  (func $dynrt_lib_modc__fn196 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32)
    call $dynrt_lib_modc_dynArray
    local.set 2
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn165
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
        call $dynrt_lib_modc__fn164
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn165
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
                    call $dynrt_lib_modc__fn164
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn182
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
                    call $dynrt_lib_modc__fn164
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn165
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
  (func $dynrt_lib_modc__fn197 (param i32 i32) (result i32)
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
    call $dynrt_lib_modc__fn165
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
  (func $dynrt_lib_modc__fn198 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn164
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn165
    i32.const 123
    i32.eq
    if  ;; label = @1
      local.get 0
      local.get 1
      call $dynrt_lib_modc__fn197
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
    call $dynrt_lib_modc__fn179
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
  (func $dynrt_lib_modc__fn199 (param i32 i32) (result i32)
    (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn164
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn165
    i32.const 0
    call $dynrt_lib_modc__fn163
    i32.const 1
    i32.eq
    if  ;; label = @1
      local.get 0
      local.get 1
      call $dynrt_lib_modc__fn182
    end
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn164
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn196
    local.set 2
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn164
    i32.const 1936
    i32.const 0
    call $dynrt_lib_modc_dynString
    local.set 3
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn165
    i32.const 123
    i32.eq
    if  ;; label = @1
      local.get 0
      local.get 1
      call $dynrt_lib_modc__fn197
      local.set 3
    end
    local.get 2
    local.get 3
    global.get $dynrt_lib_modc_global20
    call $dynrt_lib_modc__fn142
    return)
  (func $dynrt_lib_modc__fn200 (param i32 i32) (result i32)
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
    call $dynrt_lib_modc__fn164
    i32.const 0
    local.tee 15
    local.set 3
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn165
    i32.const 61
    i32.eq
    if (result i32)  ;; label = @1
      local.get 0
      local.get 1
      call $dynrt_lib_modc__fn166
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
  (func $dynrt_lib_modc__fn201 (param i32 i32 i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn164
    i32.const 0
    local.tee 10
    local.set 3
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn165
    i32.const 42
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_lib_modc_global19
        i32.const 1
        local.tee 8
        i32.add
        global.set $dynrt_lib_modc_global19
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn164
        i32.const 1
        local.tee 9
        local.set 3
      end
    end
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn182
    global.get $dynrt_lib_modc_global1
    local.set 4
    global.get $dynrt_lib_modc_global2
    local.set 5
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn164
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn196
    local.set 6
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn164
    i32.const 1936
    i32.const 0
    call $dynrt_lib_modc_dynString
    local.set 7
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn165
    i32.const 123
    i32.eq
    if  ;; label = @1
      local.get 0
      local.get 1
      call $dynrt_lib_modc__fn197
      local.set 7
    end
    local.get 6
    local.get 7
    global.get $dynrt_lib_modc_global20
    call $dynrt_lib_modc__fn142
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
    global.get $dynrt_lib_modc_global21
    i32.const 1
    i32.eq
    if  ;; label = @1
      global.get $dynrt_lib_modc_global20
      local.get 4
      local.get 5
      local.get 6
      call $dynrt_lib_modc_dynSet
    end)
  (func $dynrt_lib_modc__fn202 (param i32 i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn164
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn182
    global.get $dynrt_lib_modc_global1
    local.set 2
    global.get $dynrt_lib_modc_global2
    local.set 3
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn164
    i32.const -1
    local.tee 29
    local.set 4
    local.get 29
    local.set 5
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn165
    i32.const 0
    call $dynrt_lib_modc__fn163
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn182
        global.get $dynrt_lib_modc_global1
        local.set 6
        global.get $dynrt_lib_modc_global2
        local.set 7
        local.get 6
        local.get 7
        i32.const 2574
        i32.const 7
        call $dynrt_lib_modc__fn159
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn164
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn182
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
              call $dynrt_lib_modc__fn146
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
                i32.const 2581
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
            call $dynrt_lib_modc__fn164
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
    call $dynrt_lib_modc__fn147
    local.set 8
    local.get 5
    i32.const -1
    i32.ne
    if  ;; label = @1
      local.get 8
      i32.const 2496
      i32.const 12
      local.get 5
      call $dynrt_lib_modc_dynSet
    end
    local.get 4
    i32.const -1
    i32.ne
    if  ;; label = @1
      local.get 8
      i32.const 2478
      i32.const 12
      local.get 4
      call $dynrt_lib_modc_dynSet
    end
    i32.const 1936
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
    call $dynrt_lib_modc__fn165
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
    call $dynrt_lib_modc__fn164
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 0
          local.get 1
          call $dynrt_lib_modc__fn165
          i32.const 125
          i32.ne
          if (result i32)  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn165
            i32.const -1
            i32.ne
          else
            i32.const 0
          end
          i32.eqz
          br_if 2 (;@1;)
          local.get 0
          local.get 1
          call $dynrt_lib_modc__fn165
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
              call $dynrt_lib_modc__fn164
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
              call $dynrt_lib_modc__fn182
              global.get $dynrt_lib_modc_global1
              local.set 15
              global.get $dynrt_lib_modc_global2
              local.set 16
              local.get 0
              local.get 1
              call $dynrt_lib_modc__fn164
              local.get 15
              local.get 16
              i32.const 2588
              i32.const 6
              call $dynrt_lib_modc__fn159
              i32.const 1
              i32.eq
              if (result i32)  ;; label = @6
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn165
                i32.const 0
                call $dynrt_lib_modc__fn163
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
                  call $dynrt_lib_modc__fn182
                  global.get $dynrt_lib_modc_global1
                  local.set 15
                  global.get $dynrt_lib_modc_global2
                  local.set 16
                  local.get 0
                  local.get 1
                  call $dynrt_lib_modc__fn164
                end
              end
              local.get 15
              local.get 16
              i32.const 2279
              i32.const 3
              call $dynrt_lib_modc__fn159
              i32.const 1
              i32.eq
              if (result i32)  ;; label = @6
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn165
                i32.const 0
                call $dynrt_lib_modc__fn163
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
                  call $dynrt_lib_modc__fn182
                  global.get $dynrt_lib_modc_global1
                  local.set 15
                  global.get $dynrt_lib_modc_global2
                  local.set 16
                  local.get 0
                  local.get 1
                  call $dynrt_lib_modc__fn164
                end
              else
                local.get 15
                local.get 16
                i32.const 2276
                i32.const 3
                call $dynrt_lib_modc__fn159
                i32.const 1
                i32.eq
                if (result i32)  ;; label = @7
                  local.get 0
                  local.get 1
                  call $dynrt_lib_modc__fn165
                  i32.const 0
                  call $dynrt_lib_modc__fn163
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
                    call $dynrt_lib_modc__fn182
                    global.get $dynrt_lib_modc_global1
                    local.set 15
                    global.get $dynrt_lib_modc_global2
                    local.set 16
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn164
                  end
                end
              end
              local.get 0
              local.get 1
              call $dynrt_lib_modc__fn165
              local.set 17
              local.get 17
              i32.const 40
              i32.eq
              if  ;; label = @6
                block  ;; label = @7
                  local.get 0
                  local.get 1
                  call $dynrt_lib_modc__fn196
                  local.set 17
                  local.get 0
                  local.get 1
                  call $dynrt_lib_modc__fn164
                  local.get 0
                  local.get 1
                  call $dynrt_lib_modc__fn197
                  local.set 18
                  local.get 15
                  local.get 16
                  i32.const 2594
                  i32.const 11
                  call $dynrt_lib_modc__fn159
                  i32.const 1
                  i32.eq
                  if  ;; label = @8
                    block  ;; label = @9
                      local.get 17
                      local.set 10
                      local.get 18
                      call $dynrt_lib_modc__fn78
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
                      call $dynrt_lib_modc__fn142
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
                          i32.const 2389
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
                            i32.const 2401
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
                          call $dynrt_lib_modc__fn179
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
                      i32.const 1949
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
                          call $dynrt_lib_modc__fn164
                          global.get $dynrt_lib_modc_global19
                          local.tee 22
                          local.set 13
                          global.get $dynrt_lib_modc_global21
                          local.set 14
                          i32.const 0
                          global.set $dynrt_lib_modc_global21
                          local.get 0
                          local.get 1
                          call $dynrt_lib_modc__fn179
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
                      i32.const 2605
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
                      i32.const 2610
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
                      i32.const 2613
                      i32.const 2
                      call $dynrt_lib_modc__fn4
                      local.set 12
                      nop
                      local.set 11
                    end
                  end
                  local.get 0
                  local.get 1
                  call $dynrt_lib_modc__fn164
                  local.get 0
                  local.get 1
                  call $dynrt_lib_modc__fn165
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
              call $dynrt_lib_modc__fn164
            end
          end
          br 1 (;@2;)
        end
      end
    end
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn165
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
        call $dynrt_lib_modc__fn142
        local.set 5
        local.get 7
        i32.const 2490
        i32.const 6
        local.get 5
        call $dynrt_lib_modc_dynSet
      end
    end
    local.get 7
    i32.const 2581
    i32.const 7
    local.get 6
    call $dynrt_lib_modc_dynSet
    local.get 4
    i32.const -1
    i32.ne
    if  ;; label = @1
      local.get 7
      i32.const 2478
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
  (func $dynrt_lib_modc__fn203 (param i32 i32) (result i32)
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
    i32.const 2581
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
    i32.const 2490
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
          call $dynrt_lib_modc__fn151
          drop
        end
      end
    end
    local.get 2
    return)
  (func $dynrt_lib_modc__fn204 (param i32 i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn164
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn165
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
        call $dynrt_lib_modc__fn147
        local.set 3
        local.get 3
        local.tee 14
        global.set $dynrt_lib_modc_global20
        local.get 3
        call $dynrt_lib_modc__fn54
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn205
        call $dynrt_lib_modc__fn55
        local.get 2
        local.tee 15
        global.set $dynrt_lib_modc_global20
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn164
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn165
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
    call $dynrt_lib_modc__fn163
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_lib_modc_global19
        local.set 2
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn182
        global.get $dynrt_lib_modc_global1
        local.set 3
        global.get $dynrt_lib_modc_global2
        local.set 4
        local.get 3
        local.get 4
        i32.const 2553
        i32.const 3
        call $dynrt_lib_modc__fn159
        i32.const 1
        i32.eq
        if (result i32)  ;; label = @3
          i32.const 1
        else
          local.get 3
          local.get 4
          i32.const 2548
          i32.const 5
          call $dynrt_lib_modc__fn159
          i32.const 1
          i32.eq
        end
        if (result i32)  ;; label = @3
          i32.const 1
        else
          local.get 3
          local.get 4
          i32.const 2556
          i32.const 3
          call $dynrt_lib_modc__fn159
          i32.const 1
          i32.eq
        end
        if  ;; label = @3
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn183
            return
          end
        end
        local.get 3
        local.get 4
        i32.const 2615
        i32.const 2
        call $dynrt_lib_modc__fn159
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn185
            return
          end
        end
        local.get 3
        local.get 4
        i32.const 2617
        i32.const 5
        call $dynrt_lib_modc__fn159
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn186
            return
          end
        end
        local.get 3
        local.get 4
        i32.const 2622
        i32.const 2
        call $dynrt_lib_modc__fn159
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn187
            return
          end
        end
        local.get 3
        local.get 4
        i32.const 2624
        i32.const 3
        call $dynrt_lib_modc__fn159
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn188
            return
          end
        end
        local.get 3
        local.get 4
        i32.const 2627
        i32.const 6
        call $dynrt_lib_modc__fn159
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn192
            return
          end
        end
        local.get 3
        local.get 4
        i32.const 2633
        i32.const 3
        call $dynrt_lib_modc__fn159
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
        i32.const 2636
        i32.const 5
        call $dynrt_lib_modc__fn159
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn179
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
            call $dynrt_lib_modc__fn164
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn165
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
        i32.const 2641
        i32.const 6
        call $dynrt_lib_modc__fn159
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn184
            return
          end
        end
        local.get 3
        local.get 4
        i32.const 2407
        i32.const 8
        call $dynrt_lib_modc__fn159
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 0
            local.get 1
            i32.const 0
            call $dynrt_lib_modc__fn201
            return
          end
        end
        local.get 3
        local.get 4
        i32.const 2647
        i32.const 5
        call $dynrt_lib_modc__fn159
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            global.get $dynrt_lib_modc_global19
            local.set 5
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn164
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn165
            i32.const 0
            call $dynrt_lib_modc__fn163
            i32.const 1
            i32.eq
            if  ;; label = @5
              block  ;; label = @6
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn182
                global.get $dynrt_lib_modc_global1
                local.set 6
                global.get $dynrt_lib_modc_global2
                local.set 7
                local.get 6
                local.get 7
                i32.const 2407
                i32.const 8
                call $dynrt_lib_modc__fn159
                i32.const 1
                i32.eq
                if  ;; label = @7
                  block  ;; label = @8
                    local.get 0
                    local.get 1
                    i32.const 1
                    call $dynrt_lib_modc__fn201
                    return
                  end
                end
              end
            end
            local.get 5
            global.set $dynrt_lib_modc_global19
          end
        end
        local.get 3
        local.get 4
        i32.const 2652
        i32.const 5
        call $dynrt_lib_modc__fn159
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
        i32.const 2657
        i32.const 5
        call $dynrt_lib_modc__fn159
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
            call $dynrt_lib_modc__fn164
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn165
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
        i32.const 2662
        i32.const 8
        call $dynrt_lib_modc__fn159
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
            call $dynrt_lib_modc__fn164
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn165
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
        call $dynrt_lib_modc__fn164
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn165
        local.set 5
        local.get 5
        i32.const 61
        i32.eq
        if (result i32)  ;; label = @3
          local.get 0
          local.get 1
          call $dynrt_lib_modc__fn166
          i32.const 61
          i32.ne
        else
          i32.const 0
        end
        if (result i32)  ;; label = @3
          local.get 0
          local.get 1
          call $dynrt_lib_modc__fn166
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
            call $dynrt_lib_modc__fn179
            local.set 2
            global.get $dynrt_lib_modc_global21
            i32.const 1
            i32.eq
            if  ;; label = @5
              global.get $dynrt_lib_modc_global20
              local.get 3
              local.get 4
              local.get 2
              call $dynrt_lib_modc__fn148
            end
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn164
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn165
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
          call $dynrt_lib_modc__fn166
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
                call $dynrt_lib_modc__fn146
                local.set 5
                global.get $dynrt_lib_modc_global20
                local.get 3
                local.get 4
                local.get 5
                f64.const 0x1.0p+0 (;=1;)
                call $dynrt_lib_modc_dynNumber
                call $dynrt_lib_modc_dynAdd
                call $dynrt_lib_modc__fn148
              end
            end
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn164
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn165
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
          call $dynrt_lib_modc__fn166
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
                call $dynrt_lib_modc__fn146
                local.set 5
                global.get $dynrt_lib_modc_global20
                local.get 3
                local.get 4
                local.get 5
                f64.const 0x1.0p+0 (;=1;)
                call $dynrt_lib_modc_dynNumber
                call $dynrt_lib_modc_dynSub
                call $dynrt_lib_modc__fn148
              end
            end
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn164
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn165
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
          call $dynrt_lib_modc__fn166
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
            call $dynrt_lib_modc__fn179
            local.set 6
            global.get $dynrt_lib_modc_global21
            i32.const 1
            i32.eq
            if  ;; label = @5
              block  ;; label = @6
                global.get $dynrt_lib_modc_global20
                local.get 3
                local.get 4
                call $dynrt_lib_modc__fn146
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
                call $dynrt_lib_modc__fn148
              end
            end
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn164
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn165
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
              call $dynrt_lib_modc__fn146
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
                    call $dynrt_lib_modc__fn164
                    local.get 0
                    local.get 1
                    call $dynrt_lib_modc__fn165
                    local.set 6
                    i32.const 0
                    local.tee 19
                    local.set 7
                    i32.const 1936
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
                        call $dynrt_lib_modc__fn182
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
                          call $dynrt_lib_modc__fn179
                          local.set 10
                          local.get 0
                          local.get 1
                          call $dynrt_lib_modc__fn164
                          local.get 0
                          local.get 1
                          call $dynrt_lib_modc__fn165
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
                        call $dynrt_lib_modc__fn164
                        local.get 0
                        local.get 1
                        call $dynrt_lib_modc__fn165
                        local.set 11
                        local.get 0
                        local.get 1
                        call $dynrt_lib_modc__fn166
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
                            call $dynrt_lib_modc__fn179
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
                                  call $dynrt_lib_modc__fn161
                                else
                                  local.get 3
                                  local.get 10
                                  local.get 5
                                  call $dynrt_lib_modc__fn128
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
                call $dynrt_lib_modc__fn164
                local.get 0
                local.get 1
                call $dynrt_lib_modc__fn165
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
            call $dynrt_lib_modc__fn179
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
            call $dynrt_lib_modc__fn164
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn165
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
        call $dynrt_lib_modc__fn179
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
        call $dynrt_lib_modc__fn164
        local.get 0
        local.get 1
        call $dynrt_lib_modc__fn165
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
    call $dynrt_lib_modc__fn179
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
    call $dynrt_lib_modc__fn164
    local.get 0
    local.get 1
    call $dynrt_lib_modc__fn165
    i32.const 59
    i32.eq
    if  ;; label = @1
      global.get $dynrt_lib_modc_global19
      i32.const 1
      i32.add
      global.set $dynrt_lib_modc_global19
    end)
  (func $dynrt_lib_modc__fn205 (param i32 i32)
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
            call $dynrt_lib_modc__fn164
            local.get 0
            local.get 1
            call $dynrt_lib_modc__fn165
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
                call $dynrt_lib_modc__fn66
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
                call $dynrt_lib_modc__fn204
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
    call $dynrt_lib_modc__fn54
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
    call $dynrt_lib_modc__fn205
    global.get $dynrt_lib_modc_global23
    i32.const 1
    i32.eq
    if (result i32)  ;; label = @1
      global.get $dynrt_lib_modc_global24
    else
      global.get $dynrt_lib_modc_global25
    end
    local.set 3
    call $dynrt_lib_modc__fn55
    local.get 3
    return)
  ;; data from dynrt_lib_modc
  (data (;0;) (i32.const 1936) "")
  (data (;1;) (i32.const 1936) "false")
  (data (;2;) (i32.const 1941) "true")
  (data (;3;) (i32.const 1945) "null")
  (data (;4;) (i32.const 1949) "undefined")
  (data (;5;) (i32.const 1958) "push")
  (data (;6;) (i32.const 1962) "indexOf")
  (data (;7;) (i32.const 1969) "includes")
  (data (;8;) (i32.const 1977) "join")
  (data (;9;) (i32.const 1981) ",")
  (data (;10;) (i32.const 1982) "slice")
  (data (;11;) (i32.const 1987) "concat")
  (data (;12;) (i32.const 1993) "reverse")
  (data (;13;) (i32.const 2000) "pop")
  (data (;14;) (i32.const 2003) "shift")
  (data (;15;) (i32.const 2008) "unshift")
  (data (;16;) (i32.const 2015) "at")
  (data (;17;) (i32.const 2017) "lastIndexOf")
  (data (;18;) (i32.const 2028) "map")
  (data (;19;) (i32.const 2031) "filter")
  (data (;20;) (i32.const 2037) "forEach")
  (data (;21;) (i32.const 2044) "reduce")
  (data (;22;) (i32.const 2050) "find")
  (data (;23;) (i32.const 2054) "findIndex")
  (data (;24;) (i32.const 2063) "some")
  (data (;25;) (i32.const 2067) "every")
  (data (;26;) (i32.const 2072) "sort")
  (data (;27;) (i32.const 2076) "charAt")
  (data (;28;) (i32.const 2082) "charCodeAt")
  (data (;29;) (i32.const 2092) "toUpperCase")
  (data (;30;) (i32.const 2103) "toLowerCase")
  (data (;31;) (i32.const 2114) "trim")
  (data (;32;) (i32.const 2118) "startsWith")
  (data (;33;) (i32.const 2128) "endsWith")
  (data (;34;) (i32.const 2136) "repeat")
  (data (;35;) (i32.const 2142) "padStart")
  (data (;36;) (i32.const 2150) " ")
  (data (;37;) (i32.const 2151) "padEnd")
  (data (;38;) (i32.const 2157) "split")
  (data (;39;) (i32.const 2162) "match")
  (data (;40;) (i32.const 2167) "__regex")
  (data (;41;) (i32.const 2174) "create")
  (data (;42;) (i32.const 2180) "keys")
  (data (;43;) (i32.const 2184) "values")
  (data (;44;) (i32.const 2190) "entries")
  (data (;45;) (i32.const 2197) "assign")
  (data (;46;) (i32.const 2203) "floor")
  (data (;47;) (i32.const 2208) "ceil")
  (data (;48;) (i32.const 2212) "round")
  (data (;49;) (i32.const 2217) "abs")
  (data (;50;) (i32.const 2220) "sqrt")
  (data (;51;) (i32.const 2224) "sign")
  (data (;52;) (i32.const 2228) "trunc")
  (data (;53;) (i32.const 2233) "max")
  (data (;54;) (i32.const 2236) "min")
  (data (;55;) (i32.const 2239) "pow")
  (data (;56;) (i32.const 2242) "\22")
  (data (;57;) (i32.const 2243) "\5c\22")
  (data (;58;) (i32.const 2245) "\5c\5c")
  (data (;59;) (i32.const 2247) "\5cn")
  (data (;60;) (i32.const 2249) "\5cr")
  (data (;61;) (i32.const 2251) "\5ct")
  (data (;62;) (i32.const 2253) "[")
  (data (;63;) (i32.const 2254) "]")
  (data (;64;) (i32.const 2255) "{")
  (data (;65;) (i32.const 2256) ":")
  (data (;66;) (i32.const 2257) "}")
  (data (;67;) (i32.const 2258) "__mapk")
  (data (;68;) (i32.const 2264) "__mapv")
  (data (;69;) (i32.const 2270) "__setk")
  (data (;70;) (i32.const 2276) "set")
  (data (;71;) (i32.const 2279) "get")
  (data (;72;) (i32.const 2282) "has")
  (data (;73;) (i32.const 2285) "delete")
  (data (;74;) (i32.const 2291) "add")
  (data (;75;) (i32.const 2294) "test")
  (data (;76;) (i32.const 2298) "exec")
  (data (;77;) (i32.const 2302) "next")
  (data (;78;) (i32.const 2306) "__genv")
  (data (;79;) (i32.const 2312) "__geni")
  (data (;80;) (i32.const 2318) "value")
  (data (;81;) (i32.const 2323) "done")
  (data (;82;) (i32.const 2327) "__promv")
  (data (;83;) (i32.const 2334) "__promrej")
  (data (;84;) (i32.const 2343) "resolve")
  (data (;85;) (i32.const 2350) "reject")
  (data (;86;) (i32.const 2356) "all")
  (data (;87;) (i32.const 2359) "then")
  (data (;88;) (i32.const 2363) "catch")
  (data (;89;) (i32.const 2368) "finally")
  (data (;90;) (i32.const 2375) "this")
  (data (;91;) (i32.const 2379) "len")
  (data (;92;) (i32.const 2382) "inc")
  (data (;93;) (i32.const 2385) "size")
  (data (;94;) (i32.const 2389) "__get_")
  (data (;95;) (i32.const 2395) "length")
  (data (;96;) (i32.const 2401) "__set_")
  (data (;97;) (i32.const 2407) "function")
  (data (;98;) (i32.const 2415) "yield")
  (data (;99;) (i32.const 2420) "Object")
  (data (;100;) (i32.const 2426) "Math")
  (data (;101;) (i32.const 2430) "PI")
  (data (;102;) (i32.const 2432) "E")
  (data (;103;) (i32.const 2433) "JSON")
  (data (;104;) (i32.const 2437) "parse")
  (data (;105;) (i32.const 2442) "stringify")
  (data (;106;) (i32.const 2451) "Promise")
  (data (;107;) (i32.const 2458) "new")
  (data (;108;) (i32.const 2461) "Map")
  (data (;109;) (i32.const 2464) "Set")
  (data (;110;) (i32.const 2467) "RegExp")
  (data (;111;) (i32.const 2473) "super")
  (data (;112;) (i32.const 2478) "__superclass")
  (data (;113;) (i32.const 2490) "__ctor")
  (data (;114;) (i32.const 2496) "__superproto")
  (data (;115;) (i32.const 2508) "boolean")
  (data (;116;) (i32.const 2515) "number")
  (data (;117;) (i32.const 2521) "string")
  (data (;118;) (i32.const 2527) "object")
  (data (;119;) (i32.const 2533) "typeof")
  (data (;120;) (i32.const 2539) "await")
  (data (;121;) (i32.const 2544) "else")
  (data (;122;) (i32.const 2548) "const")
  (data (;123;) (i32.const 2553) "let")
  (data (;124;) (i32.const 2556) "var")
  (data (;125;) (i32.const 2559) "of")
  (data (;126;) (i32.const 2561) "in")
  (data (;127;) (i32.const 2563) "case")
  (data (;128;) (i32.const 2567) "default")
  (data (;129;) (i32.const 2574) "extends")
  (data (;130;) (i32.const 2581) "__proto")
  (data (;131;) (i32.const 2588) "static")
  (data (;132;) (i32.const 2594) "constructor")
  (data (;133;) (i32.const 2605) "this.")
  (data (;134;) (i32.const 2610) " = ")
  (data (;135;) (i32.const 2613) "; ")
  (data (;136;) (i32.const 2615) "if")
  (data (;137;) (i32.const 2617) "while")
  (data (;138;) (i32.const 2622) "do")
  (data (;139;) (i32.const 2624) "for")
  (data (;140;) (i32.const 2627) "switch")
  (data (;141;) (i32.const 2633) "try")
  (data (;142;) (i32.const 2636) "throw")
  (data (;143;) (i32.const 2641) "return")
  (data (;144;) (i32.const 2647) "async")
  (data (;145;) (i32.const 2652) "class")
  (data (;146;) (i32.const 2657) "break")
  (data (;147;) (i32.const 2662) "continue")
)