(module
  (import "wasi_snapshot_preview1" "proc_exit" (func $proc_exit (param i32)))
  (import "wasi_snapshot_preview1" "fd_write" (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (memory (export "memory") 3)
  (global $__heap_ptr (mut i32) (i32.const 885))
  (global $__free_list (mut i32) (i32.const 0))
  (tag $__exn_tag (export "__exn_tag") (param i32 i32))
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

  ;; ── str_gather: copy len bytes from src to dst (byte-copy loop, no bulk-memory) ──
  ;; Used by gather-buffer mode in console.log for strvar/boolvar segments.
  (func $__str_gather (param $src i32) (param $slen i32) (param $dst i32)
    (local $i i32)
    (block $done
      (loop $loop
        (br_if $done (i32.ge_u (local.get $i) (local.get $slen)))
        (i32.store8
          (i32.add (local.get $dst) (local.get $i))
          (i32.load8_u (i32.add (local.get $src) (local.get $i)))
        )
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $loop)
      )
    )
  )

  ;; ── str_concat: heap-allocate new string = a ++ b ───────────────────────────
  ;; Copies bytes of a then b into a malloc'd buffer. Returns (ptr, len).
  ;; Old buffers become dead memory (bump allocator has no free).
  (func $__str_concat
    (param $aptr i32) (param $alen i32) (param $bptr i32) (param $blen i32)
    (result i32 i32)
    (local $newptr i32) (local $newlen i32) (local $i i32)
    (local.set $newlen (i32.add (local.get $alen) (local.get $blen)))
    (local.set $newptr (call $__malloc (local.get $newlen)))
    ;; copy a
    (local.set $i (i32.const 0))
    (block $done_a
      (loop $copy_a
        (br_if $done_a (i32.ge_u (local.get $i) (local.get $alen)))
        (i32.store8
          (i32.add (local.get $newptr) (local.get $i))
          (i32.load8_u (i32.add (local.get $aptr) (local.get $i)))
        )
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $copy_a)
      )
    )
    ;; copy b
    (local.set $i (i32.const 0))
    (block $done_b
      (loop $copy_b
        (br_if $done_b (i32.ge_u (local.get $i) (local.get $blen)))
        (i32.store8
          (i32.add (local.get $newptr) (i32.add (local.get $alen) (local.get $i)))
          (i32.load8_u (i32.add (local.get $bptr) (local.get $i)))
        )
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $copy_b)
      )
    )
    (local.get $newptr)
    (local.get $newlen)
  )

  ;; ── str_slice: return sub-range of existing string (no allocation) ───────────
  ;; Clamps start/end to [0, len]. Returns (ptr+start, end-start).
  (func $__str_slice
    (param $ptr i32) (param $len i32) (param $start i32) (param $end i32)
    (result i32 i32)
    (local $cs i32) (local $ce i32)
    ;; clamp start to [0, len]
    (local.set $cs
      (select (i32.const 0) (local.get $start) (i32.lt_s (local.get $start) (i32.const 0)))
    )
    (if (i32.gt_s (local.get $cs) (local.get $len))
      (then (local.set $cs (local.get $len)))
    )
    ;; clamp end to [cs, len]
    (local.set $ce
      (select (local.get $len) (local.get $end) (i32.gt_s (local.get $end) (local.get $len)))
    )
    (if (i32.lt_s (local.get $ce) (local.get $cs))
      (then (local.set $ce (local.get $cs)))
    )
    (i32.add (local.get $ptr) (local.get $cs))
    (i32.sub (local.get $ce) (local.get $cs))
  )

  ;; ── str_indexof: first occurrence of sub in str, or -1 ──────────────────────
  (func $__str_indexof
    (param $ptr i32) (param $len i32) (param $subptr i32) (param $sublen i32)
    (result i32)
    (local $i i32) (local $j i32) (local $max i32) (local $ok i32)
    ;; empty substring always found at position 0
    (if (i32.eqz (local.get $sublen)) (then (return (i32.const 0))))
    ;; if sub is longer than str, impossible
    (local.set $max (i32.sub (local.get $len) (local.get $sublen)))
    (if (i32.lt_s (local.get $max) (i32.const 0)) (then (return (i32.const -1))))
    (block $found_none
      (loop $outer
        (br_if $found_none (i32.gt_s (local.get $i) (local.get $max)))
        (local.set $j (i32.const 0))
        (local.set $ok (i32.const 1))
        (block $inner_done
          (loop $inner
            (br_if $inner_done (i32.ge_u (local.get $j) (local.get $sublen)))
            (if (i32.ne
              (i32.load8_u (i32.add (local.get $ptr) (i32.add (local.get $i) (local.get $j))))
              (i32.load8_u (i32.add (local.get $subptr) (local.get $j)))
            )
              (then
                (local.set $ok (i32.const 0))
                (br $inner_done)
              )
            )
            (local.set $j (i32.add (local.get $j) (i32.const 1)))
            (br $inner)
          )
        )
        (if (local.get $ok) (then (return (local.get $i))))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $outer)
      )
    )
    (i32.const -1)
  )

  ;; ── str_indexof_from: first occurrence of sub in str starting at 'from', or -1 ─
  (func $__str_indexof_from
    (param $ptr i32) (param $len i32) (param $subptr i32) (param $sublen i32) (param $from i32)
    (result i32)
    (local $i i32) (local $j i32) (local $max i32) (local $ok i32)
    (if (i32.eqz (local.get $sublen)) (then (return (local.get $from))))
    (local.set $max (i32.sub (local.get $len) (local.get $sublen)))
    (if (i32.lt_s (local.get $max) (i32.const 0)) (then (return (i32.const -1))))
    (local.set $i (select (i32.const 0) (local.get $from) (i32.lt_s (local.get $from) (i32.const 0))))
    (block $found_none
      (loop $outer
        (br_if $found_none (i32.gt_s (local.get $i) (local.get $max)))
        (local.set $j (i32.const 0))
        (local.set $ok (i32.const 1))
        (block $inner_done
          (loop $inner
            (br_if $inner_done (i32.ge_u (local.get $j) (local.get $sublen)))
            (if (i32.ne
              (i32.load8_u (i32.add (local.get $ptr) (i32.add (local.get $i) (local.get $j))))
              (i32.load8_u (i32.add (local.get $subptr) (local.get $j)))
            )
              (then
                (local.set $ok (i32.const 0))
                (br $inner_done)
              )
            )
            (local.set $j (i32.add (local.get $j) (i32.const 1)))
            (br $inner)
          )
        )
        (if (local.get $ok) (then (return (local.get $i))))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $outer)
      )
    )
    (i32.const -1)
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
  ;; Dynamic array grow_i32: malloc new block of newcap elements, copy data, return new ptr.
  (func $__dynarr_grow_i32 (param $arr i32) (param $newcap i32) (result i32)
    (local $newptr i32)
    (local $len i32)
    (local $i i32)
    (local.set $len (i32.load (local.get $arr)))
    (local.set $newptr (call $__malloc (i32.add (i32.const 8) (i32.shl (local.get $newcap) (i32.const 2)))))
    (i32.store (local.get $newptr) (local.get $len))
    (i32.store offset=4 (local.get $newptr) (local.get $newcap))
    (local.set $i (i32.const 0))
    (block $brk
      (loop $lp
        (br_if $brk (i32.ge_u (local.get $i) (local.get $len)))
        (i32.store
          (i32.add (i32.add (local.get $newptr) (i32.const 8)) (i32.shl (local.get $i) (i32.const 2)))
          (i32.load
            (i32.add (i32.add (local.get $arr) (i32.const 8)) (i32.shl (local.get $i) (i32.const 2)))
          )
        )
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $lp)
      )
    )
    (local.get $newptr)
  )

  ;; Dynamic array push_i32: grow if full, store val at end, increment length, return new arr ptr.
  (func $__dynarr_push_i32 (param $arr i32) (param $val i32) (result i32)
    (local $len i32)
    (local $cap i32)
    (local.set $len (i32.load (local.get $arr)))
    (local.set $cap (i32.load offset=4 (local.get $arr)))
    (if (i32.ge_u (local.get $len) (local.get $cap))
      (then
        (local.set $arr (call $__dynarr_grow_i32 (local.get $arr) (select (i32.const 8) (i32.shl (local.get $cap) (i32.const 1)) (i32.eqz (local.get $cap)))))
      )
    )
    (i32.store
      (i32.add (i32.add (local.get $arr) (i32.const 8)) (i32.shl (local.get $len) (i32.const 2)))
      (local.get $val)
    )
    (local.set $len (i32.add (local.get $len) (i32.const 1)))
    (i32.store (local.get $arr) (local.get $len))
    (local.get $arr)
  )




  (func $runDenoPhase18Test  
    (local $variableRecords i32)
    (local $__rt_struct_ptr i32)
    (local $MAX_DEPTH i32)
    (local $VARS_PER_SCOPE i32)
    (local $currentStringPtr i32)
    (local $__from_n i32)
    (local $__from_i i32)
    (local $nameMatrix i32)
    (local $__2d_tmp i32)
    (local $depth i32)
    (local $v i32)
    (local $namePtr i32)
    (local $typeId f64)
    (local $actualAddr i32)
    (local $shadowedNamePtr i32)
    (local $localShadowAddr i32)
    (local $i i32)
    (local $target i32)
    (local $resolvedAddr i32)
    (local $activeLookupAddr i32)
    (local $error_ptr i32)
    (local $error_len i32)
    (local $__throw_msg_ptr i32)
    (local $__throw_msg_len i32)
    (local $__iface_tmp i32)
    (local $__tmpl_num_ptr i32)
    (local $__tmpl_num_len i32)
        (i32.store (i32.const 0) (i32.const 260))
          (i32.store (i32.const 4) (i32.const 61))
          (drop (call $fd_write
            (i32.const 1)
            (i32.const 0)
            (i32.const 1)
            (i32.const 128)))
    (local.set $variableRecords (call $__malloc (i32.const 40)))
      (i32.store (local.get $variableRecords) (i32.const 0))
      (i32.store offset=4 (local.get $variableRecords) (i32.const 8))
    (local.set $MAX_DEPTH (i32.const 100))
    (local.set $VARS_PER_SCOPE (i32.const 30))
    (local.set $currentStringPtr (i32.const 2000))
    (local.set $__from_n (i32.add (local.get $MAX_DEPTH) (i32.const 1)))
      (local.set $nameMatrix (call $__malloc (i32.add (i32.const 8) (i32.shl (local.get $__from_n) (i32.const 2)))))
      (i32.store (local.get $nameMatrix) (local.get $__from_n))
      (i32.store offset=4 (local.get $nameMatrix) (local.get $__from_n))
      (local.set $__from_i (i32.const 0))
      (block $__from_blk
        (loop $__from_lp
          (br_if $__from_blk (i32.ge_s (local.get $__from_i) (local.get $__from_n)))
          (local.set $__2d_tmp (call $__malloc (i32.const 264)))
          (i32.store (local.get $__2d_tmp) (i32.const 0))
          (i32.store offset=4 (local.get $__2d_tmp) (i32.const 32))
          (i32.store (i32.add (i32.add (local.get $nameMatrix) (i32.const 8)) (i32.shl (local.get $__from_i) (i32.const 2))) (local.get $__2d_tmp))
          (local.set $__from_i (i32.add (local.get $__from_i) (i32.const 1)))
          (br $__from_lp)
        )
      )
    (local.set $depth (i32.const 1))
    (block $break_0
      (loop $loop_0
        (br_if $break_0 (i32.eqz (i32.le_s (local.get $depth) (local.get $MAX_DEPTH))))
        (block $cont_0
          (local.set $v (i32.const 0))
          (block $break_1
            (loop $loop_1
              (br_if $break_1 (i32.eqz (i32.lt_s (local.get $v) (local.get $VARS_PER_SCOPE))))
              (block $cont_1
                (local.set $currentStringPtr (i32.add (local.get $currentStringPtr) (i32.const 4)))
                (f64.store (i32.add (i32.add (i32.load (i32.add (i32.add (local.get $nameMatrix) (i32.const 8)) (i32.shl (local.get $depth) (i32.const 2)))) (i32.const 8)) (i32.shl (local.get $v) (i32.const 3))) (f64.convert_i32_s (local.get $currentStringPtr)))
              )
              (local.set $v (i32.add (local.get $v) (i32.const 1)))
              (br $loop_1)
            )
          )
        )
        (local.set $depth (i32.add (local.get $depth) (i32.const 1)))
        (br $loop_0)
      )
    )
    (try
      (do
        (local.set $depth (i32.const 1))
        (block $break_2
          (loop $loop_2
            (br_if $break_2 (i32.eqz (i32.le_s (local.get $depth) (local.get $MAX_DEPTH))))
            (block $cont_2
              (local.set $v (i32.const 0))
              (block $break_3
                (loop $loop_3
                  (br_if $break_3 (i32.eqz (i32.lt_s (local.get $v) (local.get $VARS_PER_SCOPE))))
                  (block $cont_3
                    (local.set $namePtr (i32.trunc_f64_s (f64.load (i32.add (i32.add (i32.load (i32.add (i32.add (local.get $nameMatrix) (i32.const 8)) (i32.shl (local.get $depth) (i32.const 2)))) (i32.const 8)) (i32.shl (local.get $v) (i32.const 3))))))
                    (local.set $typeId (f64.add (f64.convert_i32_s (i32.rem_s (local.get $v) (i32.const 4))) (f64.const 1)))
                    (local.set $actualAddr (call $18_symbol_table_insert_symbol (local.get $namePtr) (i32.trunc_f64_s (local.get $typeId)) (local.get $depth)))
                    (local.set $variableRecords (call $__dynarr_push_i32 (local.get $variableRecords) (block (result i32)
        (local.set $__rt_struct_ptr (call $__malloc (i32.const 16)))
        (i32.store offset=0 (local.get $__rt_struct_ptr) (local.get $namePtr))
        (i32.store offset=4 (local.get $__rt_struct_ptr) (i32.trunc_f64_s (local.get $typeId)))
        (i32.store offset=8 (local.get $__rt_struct_ptr) (local.get $depth))
        (i32.store offset=12 (local.get $__rt_struct_ptr) (local.get $actualAddr))
        (local.get $__rt_struct_ptr)
      )))
                  )
                  (local.set $v (i32.add (local.get $v) (i32.const 1)))
                  (br $loop_3)
                )
              )
            )
            (local.set $depth (i32.add (local.get $depth) (i32.const 1)))
            (br $loop_2)
          )
        )
            (i32.store (i32.const 0) (i32.const 321))
          (i32.store (i32.const 4) (i32.const 55))
          (drop (call $fd_write
            (i32.const 1)
            (i32.const 0)
            (i32.const 1)
            (i32.const 128)))
            (i32.store (i32.const 0) (i32.const 376))
          (i32.store (i32.const 4) (i32.const 37))
          (drop (call $fd_write
            (i32.const 1)
            (i32.const 0)
            (i32.const 1)
            (i32.const 128)))
        (local.set $shadowedNamePtr (i32.const 9999))
        (local.set $localShadowAddr (call $18_symbol_table_insert_symbol (local.get $shadowedNamePtr) (i32.const 4) (i32.const 100)))
            (i32.store (i32.const 0) (i32.const 413))
          (i32.store (i32.const 4) (i32.const 60))
          (drop (call $fd_write
            (i32.const 1)
            (i32.const 0)
            (i32.const 1)
            (i32.const 128)))
        (local.set $i (i32.const 0))
        (block $break_4
          (loop $loop_4
            (br_if $break_4 (i32.eqz (i32.lt_s (local.get $i) (i32.load (local.get $variableRecords)))))
            (block $cont_4
              (local.set $target (i32.load (i32.add (i32.add (local.get $variableRecords) (i32.const 8)) (i32.shl (local.get $i) (i32.const 2)))))
              (local.set $resolvedAddr (call $18_symbol_table_lookup_symbol (i32.load (i32.add (local.get $target) (i32.const 0)))))
              (if (i32.ne (local.get $resolvedAddr) (i32.load (i32.add (local.get $target) (i32.const 12))))
                (then
                (local.set $__throw_msg_ptr (i32.const 473))
      (local.set $__throw_msg_len (i32.const 33))
      (local.set $__tmpl_num_ptr (call $__malloc (i32.const 32)))
      (local.set $__tmpl_num_len (call $__i32_to_str (i32.load (i32.add (local.get $target) (i32.const 12))) (local.get $__tmpl_num_ptr)))
      (call $__str_concat (local.get $__throw_msg_ptr) (local.get $__throw_msg_len) (local.get $__tmpl_num_ptr) (local.get $__tmpl_num_len))
      (local.set $__throw_msg_len)
      (local.set $__throw_msg_ptr)
      (call $__str_concat (local.get $__throw_msg_ptr) (local.get $__throw_msg_len) (i32.const 506) (i32.const 6))
      (local.set $__throw_msg_len)
      (local.set $__throw_msg_ptr)
      (local.set $__tmpl_num_ptr (call $__malloc (i32.const 32)))
      (local.set $__tmpl_num_len (call $__i32_to_str (local.get $resolvedAddr) (local.get $__tmpl_num_ptr)))
      (call $__str_concat (local.get $__throw_msg_ptr) (local.get $__throw_msg_len) (local.get $__tmpl_num_ptr) (local.get $__tmpl_num_len))
      (local.set $__throw_msg_len)
      (local.set $__throw_msg_ptr)
      (throw $__exn_tag (local.get $__throw_msg_ptr) (local.get $__throw_msg_len))
                )
              )
            )
            (local.set $i (i32.add (local.get $i) (i32.const 13)))
            (br $loop_4)
          )
        )
        (local.set $activeLookupAddr (call $18_symbol_table_lookup_symbol (local.get $shadowedNamePtr)))
        (if (i32.ne (local.get $activeLookupAddr) (local.get $localShadowAddr))
          (then
          (local.set $__throw_msg_ptr (i32.const 512))
      (local.set $__throw_msg_len (i32.const 46))
      (throw $__exn_tag (local.get $__throw_msg_ptr) (local.get $__throw_msg_len))
          )
        )
            (i32.store (i32.const 0) (i32.const 558))
          (i32.store (i32.const 4) (i32.const 63))
          (drop (call $fd_write
            (i32.const 1)
            (i32.const 0)
            (i32.const 1)
            (i32.const 128)))
            (i32.store (i32.const 0) (i32.const 621))
          (i32.store (i32.const 4) (i32.const 52))
          (drop (call $fd_write
            (i32.const 1)
            (i32.const 0)
            (i32.const 1)
            (i32.const 128)))
        (if (i32.ne (call $18_symbol_table_lookup_symbol (i32.const 888888)) (i32.const -1))
          (then
          (local.set $__throw_msg_ptr (i32.const 673))
      (local.set $__throw_msg_len (i32.const 58))
      (throw $__exn_tag (local.get $__throw_msg_ptr) (local.get $__throw_msg_len))
          )
        )
            (i32.store (i32.const 0) (i32.const 731))
          (i32.store (i32.const 4) (i32.const 54))
          (drop (call $fd_write
            (i32.const 1)
            (i32.const 0)
            (i32.const 1)
            (i32.const 128)))
            (i32.store (i32.const 0) (i32.const 785))
          (i32.store (i32.const 4) (i32.const 67))
          (drop (call $fd_write
            (i32.const 1)
            (i32.const 0)
            (i32.const 1)
            (i32.const 128)))
      )
      (catch $__exn_tag
        (local.set $error_len)
        (local.set $error_ptr)
            (i32.store (i32.const 0) (i32.const 852))
          (i32.store (i32.const 4) (i32.const 33))
          (drop (call $fd_write
            (i32.const 2)
            (i32.const 0)
            (i32.const 1)
            (i32.const 128)))
        (if (i32.const 1)
          (then
              (i32.store (i32.const 0) (i32.const 132))
          (i32.store (i32.const 4) (i32.const 0))
          (call $__str_gather (local.get $error_ptr) (local.get $error_len) (i32.const 132))
          (i32.store (i32.const 4) (i32.add (i32.const 0) (local.get $error_len)))
          (i32.store8 (i32.add (i32.const 132) (i32.load (i32.const 4))) (i32.const 10))
          (i32.store (i32.const 4) (i32.add (i32.load (i32.const 4)) (i32.const 1)))
          (drop (call $fd_write
            (i32.const 2)
            (i32.const 0)
            (i32.const 1)
            (i32.const 128)))
          )
          (else
              (i32.store (i32.const 0) (i32.const 132))
          (i32.store (i32.const 4) (i32.const 0))
          (call $__str_gather (local.get $error_ptr) (local.get $error_len) (i32.const 132))
          (i32.store (i32.const 4) (i32.add (i32.const 0) (local.get $error_len)))
          (i32.store8 (i32.add (i32.const 132) (i32.load (i32.const 4))) (i32.const 10))
          (i32.store (i32.const 4) (i32.add (i32.load (i32.const 4)) (i32.const 1)))
          (drop (call $fd_write
            (i32.const 2)
            (i32.const 0)
            (i32.const 1)
            (i32.const 128)))
          )
        )
        (call $proc_exit (i32.const 1))
      )
    )
  )
  (func $_start (export "_start")
    (call $runDenoPhase18Test )
    (call $proc_exit (i32.const 0))
  )
  (data (i32.const 260) "\f0\9f\9a\80\20\49\6e\69\74\69\61\6c\69\7a\69\6e\67\20\4d\6f\64\65\72\6e\20\44\65\6e\6f\20\50\68\61\73\65\20\31\38\20\44\69\72\65\63\74\2d\49\6d\70\6f\72\74\20\54\65\73\74\2e\2e\2e\0a")
  (data (i32.const 321) "\e2\9c\85\20\50\68\61\73\65\20\31\38\41\20\50\61\73\73\65\64\3a\20\4d\65\6d\6f\72\79\20\70\6f\69\6e\74\65\72\20\61\6c\6c\6f\63\61\74\69\6f\6e\20\63\6c\65\61\6e\2e\0a")
  (data (i32.const 376) "\f0\9f\94\a5\20\49\6e\6a\65\63\74\69\6e\67\20\53\68\61\64\6f\77\65\64\20\56\61\72\69\61\62\6c\65\73\2e\2e\2e\0a")
  (data (i32.const 413) "\f0\9f\94\8d\20\52\75\6e\6e\69\6e\67\20\50\68\61\73\65\20\31\38\43\3a\20\43\68\65\63\6b\69\6e\67\20\6c\6f\6f\6b\75\70\20\72\65\73\6f\6c\75\74\69\6f\6e\20\70\61\74\68\73\2e\2e\2e\0a")
  (data (i32.const 473) "\5b\4c\6f\6f\6b\75\70\20\46\61\69\6c\65\64\5d\20\45\78\70\65\63\74\65\64\20\61\64\64\72\65\73\73\20")
  (data (i32.const 506) "\2c\20\67\6f\74\20")
  (data (i32.const 512) "\5b\53\68\61\64\6f\77\69\6e\67\20\46\61\69\6c\75\72\65\5d\20\53\63\6f\70\65\20\70\72\65\63\65\64\65\6e\63\65\20\62\79\70\61\73\73\65\64\21")
  (data (i32.const 558) "\e2\9c\85\20\50\68\61\73\65\20\31\38\43\20\50\61\73\73\65\64\3a\20\53\63\6f\70\65\20\70\72\65\63\65\64\65\6e\63\65\20\61\6e\64\20\6c\6f\6f\6b\75\70\20\6c\6f\67\69\63\20\73\6f\6c\69\64\2e\0a")
  (data (i32.const 621) "\f0\9f\9b\a1\ef\b8\8f\20\52\75\6e\6e\69\6e\67\20\50\68\61\73\65\20\31\38\44\3a\20\43\68\65\63\6b\69\6e\67\20\69\6e\76\61\6c\69\64\20\6b\65\79\73\2e\2e\2e\0a")
  (data (i32.const 673) "\5b\53\65\63\75\72\69\74\79\20\48\6f\6c\65\5d\20\4f\75\74\2d\6f\66\2d\62\6f\75\6e\64\73\20\6b\65\79\20\77\61\73\6e\27\74\20\72\65\6a\65\63\74\65\64\20\77\69\74\68\20\2d\31\2e")
  (data (i32.const 731) "\e2\9c\85\20\50\68\61\73\65\20\31\38\44\20\50\61\73\73\65\64\3a\20\4f\75\74\2d\6f\66\2d\62\6f\75\6e\64\73\20\71\75\65\72\69\65\73\20\72\65\6a\65\63\74\65\64\2e\0a")
  (data (i32.const 785) "\0a\f0\9f\8f\86\20\50\48\41\53\45\20\31\38\20\43\4f\4d\50\4c\45\54\45\20\53\55\49\54\45\20\50\41\53\53\45\44\20\76\69\61\20\64\69\72\65\63\74\20\45\53\20\4d\6f\64\75\6c\65\20\6c\6f\61\64\69\6e\67\21\0a")
  (data (i32.const 852) "\e2\9d\8c\20\50\68\61\73\65\20\31\38\20\53\74\72\65\73\73\20\54\65\73\74\20\46\41\49\4c\45\44\21\0a")

  ;; globals from 18_symbol_table
  (global $18_symbol_table_global0 (mut i32) (i32.const 131072))
  ;; functions from 18_symbol_table
  (func $18_symbol_table_insert_symbol (param i32 i32 i32) (result i32)
    (local i32)
    global.get $18_symbol_table_global0
    local.set 3
    local.get 3
    local.get 0
    i32.store
    local.get 3
    local.get 1
    i32.store offset=4
    local.get 3
    local.get 2
    i32.store offset=8
    local.get 3
    i32.const 12
    i32.add
    global.set $18_symbol_table_global0
    local.get 3)
  (func $18_symbol_table_lookup_symbol (param i32) (result i32)
    (local i32)
    global.get $18_symbol_table_global0
    i32.const 12
    i32.sub
    local.set 1
    block  ;; label = @1
      loop  ;; label = @2
        local.get 1
        i32.const 0
        i32.lt_s
        br_if 1 (;@1;)
        local.get 1
        i32.load
        local.get 0
        i32.eq
        if  ;; label = @3
          local.get 1
          return
        end
        local.get 1
        i32.const 12
        i32.sub
        local.set 1
        br 0 (;@2;)
      end
    end
    i32.const -1)
)