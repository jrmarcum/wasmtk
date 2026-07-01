(module
  (import "wasi_snapshot_preview1" "proc_exit" (func $proc_exit (param i32)))
  (import "wasi_snapshot_preview1" "fd_write" (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (memory (export "memory") 2)
  (global $__heap_ptr (mut i32) (i32.const 283))
  (global $__free_list (mut i32) (i32.const 0))
  (global $__mt_head (mut i32) (i32.const 0))
  (global $__mt_tail (mut i32) (i32.const 0))
  (tag $__exn_tag (export "__exn_tag") (param i32 i32))
  (type $ftype_i32_i32_i32_r_void (func (param i32) (param i32) (param i32)))
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
  ;; ---- Promise runtime (Phase 13.1, #13 async) ----
  (func $__promise_alloc (result i32)
    (call $__malloc (i32.const 32)))
  (func $__promise_resolve_i32 (param $v i32) (result i32)
    (local $p i32)
    (local.set $p (call $__promise_alloc))
    (i32.store (local.get $p) (i32.const 1))
    (i32.store offset=16 (local.get $p) (local.get $v))
    (local.get $p))
  (func $__promise_resolve_f64 (param $v f64) (result i32)
    (local $p i32)
    (local.set $p (call $__promise_alloc))
    (i32.store (local.get $p) (i32.const 1))
    (i32.store offset=4 (local.get $p) (i32.const 1))
    (f64.store offset=16 (local.get $p) (local.get $v))
    (local.get $p))
  (func $__promise_await_i32 (param $p i32) (result i32)
    (call $__drain_microtasks)
    (if (i32.eqz (i32.load (local.get $p))) (then (call $__on_quiescent)))
    (if (i32.eq (i32.load offset=8 (local.get $p)) (i32.const 1))
      (then (throw $__exn_tag (i32.load offset=16 (local.get $p)) (i32.load offset=24 (local.get $p)))))
    (i32.load offset=16 (local.get $p)))
  (func $__promise_await_f64 (param $p i32) (result f64)
    (call $__drain_microtasks)
    (if (i32.eqz (i32.load (local.get $p))) (then (call $__on_quiescent)))
    (if (i32.eq (i32.load offset=8 (local.get $p)) (i32.const 1))
      (then (throw $__exn_tag (i32.load offset=16 (local.get $p)) (i32.load offset=24 (local.get $p)))))
    (f64.load offset=16 (local.get $p)))
  (func $__on_quiescent (unreachable))
  (func $__promise_reject (param $ptr i32) (param $len i32) (result i32)
    (local $p i32)
    (local.set $p (call $__promise_alloc))
    (i32.store (local.get $p) (i32.const 1))
    (i32.store offset=4 (local.get $p) (i32.const 2))
    (i32.store offset=8 (local.get $p) (i32.const 1))
    (i32.store offset=16 (local.get $p) (local.get $ptr))
    (i32.store offset=24 (local.get $p) (local.get $len))
    (local.get $p))
  ;; ---- Microtask queue (Phase 13.2 / 13.1b) ----
  ;; FIFO linked list of reaction records (20 B): [tramp_idx@0 | env@4 | src@8 | result@12 | next@16].
  ;; env is the capturing-closure struct ptr (0 for a named callback). $__mt_head / $__mt_tail are
  ;; module globals (emitted in the globals section).
  (func $__promise_enqueue (param $tramp i32) (param $env i32) (param $src i32) (param $result i32)
    (local $r i32)
    (local.set $r (call $__malloc (i32.const 20)))
    (i32.store (local.get $r) (local.get $tramp))
    (i32.store offset=4 (local.get $r) (local.get $env))
    (i32.store offset=8 (local.get $r) (local.get $src))
    (i32.store offset=12 (local.get $r) (local.get $result))
    (i32.store offset=16 (local.get $r) (i32.const 0))
    (if (i32.eqz (global.get $__mt_head))
      (then
        (global.set $__mt_head (local.get $r))
        (global.set $__mt_tail (local.get $r)))
      (else
        (i32.store offset=16 (global.get $__mt_tail) (local.get $r))
        (global.set $__mt_tail (local.get $r)))))
  ;; Register a reaction: alloc a pending result promise, enqueue the reaction (src is settled
  ;; under the eager model), and return the result promise. tramp = funcref table index; env =
  ;; closure struct ptr (0 if the callback is a named function).
  (func $__promise_then (param $src i32) (param $tramp i32) (param $env i32) (result i32)
    (local $result i32)
    (local.set $result (call $__promise_alloc))
    (call $__promise_enqueue (local.get $tramp) (local.get $env) (local.get $src) (local.get $result))
    (local.get $result))
  ;; Run queued microtasks FIFO until empty. A reaction may enqueue more (chained .then) — they
  ;; append to the tail and run in this same loop. Each trampoline has type (env,src,result)->void.
  (func $__drain_microtasks
    (local $cur i32)
    (block $done
      (loop $L
        (br_if $done (i32.eqz (global.get $__mt_head)))
        (local.set $cur (global.get $__mt_head))
        (global.set $__mt_head (i32.load offset=16 (local.get $cur)))
        (if (i32.eqz (global.get $__mt_head)) (then (global.set $__mt_tail (i32.const 0))))
        (call_indirect (type $ftype_i32_i32_i32_r_void)
          (i32.load offset=4 (local.get $cur))
          (i32.load offset=8 (local.get $cur))
          (i32.load offset=12 (local.get $cur))
          (i32.load (local.get $cur)))
        (br $L))))
  (func $risky (param $n i32) (result i32)
    (local $__throw_msg_ptr i32)
    (local $__throw_msg_len i32)
    (if (i32.lt_s (local.get $n) (i32.const 0))
      (then
      (throw $__exn_tag (i32.const 260) (i32.const 14))
      )
    )
    (return (call $__promise_resolve_i32 (i32.mul (local.get $n) (i32.const 10))))
  )

  (func $main  
    (local $x i32)
    (local $e_ptr i32)
    (local $e_len i32)
    (local $ok i32)
    (local $bad i32)
    (local $__catch_e_ptr i32)
    (local $__catch_e_len i32)
    (local $__iface_tmp i32)
    (try
      (do
        (local.set $x (call $__promise_await_i32 (call $__promise_reject (i32.const 274) (i32.const 4))))
            (i32.store (i32.const 0) (i32.const 132))
          (i32.store (i32.const 4) (i32.const 0))
          (i32.store8 (i32.const 132) (i32.const 117))
          (i32.store8 (i32.const 133) (i32.const 110))
          (i32.store8 (i32.const 134) (i32.const 114))
          (i32.store8 (i32.const 135) (i32.const 101))
          (i32.store8 (i32.const 136) (i32.const 97))
          (i32.store8 (i32.const 137) (i32.const 99))
          (i32.store8 (i32.const 138) (i32.const 104))
          (i32.store8 (i32.const 139) (i32.const 101))
          (i32.store8 (i32.const 140) (i32.const 100))
          (i32.store8 (i32.const 141) (i32.const 58))
          (i32.store8 (i32.const 142) (i32.const 32))
          (i32.store (i32.const 4) (i32.add (i32.const 11) (call $__i32_to_str (local.get $x) (i32.const 143))))
          (i32.store8 (i32.add (i32.const 132) (i32.load (i32.const 4))) (i32.const 10))
          (i32.store (i32.const 4) (i32.add (i32.load (i32.const 4)) (i32.const 1)))
          (drop (call $fd_write
            (i32.const 1)
            (i32.const 0)
            (i32.const 1)
            (i32.const 128)))
      )
      (catch $__exn_tag
        (local.set $__catch_e_len)
        (local.set $__catch_e_ptr)
            (i32.store (i32.const 0) (i32.const 132))
          (i32.store (i32.const 4) (i32.const 0))
          (i32.store8 (i32.const 132) (i32.const 99))
          (i32.store8 (i32.const 133) (i32.const 97))
          (i32.store8 (i32.const 134) (i32.const 117))
          (i32.store8 (i32.const 135) (i32.const 103))
          (i32.store8 (i32.const 136) (i32.const 104))
          (i32.store8 (i32.const 137) (i32.const 116))
          (i32.store8 (i32.const 138) (i32.const 58))
          (i32.store8 (i32.const 139) (i32.const 32))
          (call $__str_gather (local.get $__catch_e_ptr) (local.get $__catch_e_len) (i32.const 140))
          (i32.store (i32.const 4) (i32.add (i32.const 8) (local.get $__catch_e_len)))
          (i32.store8 (i32.add (i32.const 132) (i32.load (i32.const 4))) (i32.const 10))
          (i32.store (i32.const 4) (i32.add (i32.load (i32.const 4)) (i32.const 1)))
          (drop (call $fd_write
            (i32.const 1)
            (i32.const 0)
            (i32.const 1)
            (i32.const 128)))
      )
    )
    (try
      (do
        (local.set $ok (call $__promise_await_i32 (call $risky (i32.const 3))))
            (i32.store (i32.const 0) (i32.const 132))
          (i32.store (i32.const 4) (i32.const 0))
          (i32.store8 (i32.const 132) (i32.const 111))
          (i32.store8 (i32.const 133) (i32.const 107))
          (i32.store8 (i32.const 134) (i32.const 58))
          (i32.store8 (i32.const 135) (i32.const 32))
          (i32.store (i32.const 4) (i32.add (i32.const 4) (call $__i32_to_str (local.get $ok) (i32.const 136))))
          (i32.store8 (i32.add (i32.const 132) (i32.load (i32.const 4))) (i32.const 10))
          (i32.store (i32.const 4) (i32.add (i32.load (i32.const 4)) (i32.const 1)))
          (drop (call $fd_write
            (i32.const 1)
            (i32.const 0)
            (i32.const 1)
            (i32.const 128)))
        (local.set $bad (call $__promise_await_i32 (call $risky (i32.const -1))))
            (i32.store (i32.const 0) (i32.const 132))
          (i32.store (i32.const 4) (i32.const 0))
          (i32.store8 (i32.const 132) (i32.const 117))
          (i32.store8 (i32.const 133) (i32.const 110))
          (i32.store8 (i32.const 134) (i32.const 114))
          (i32.store8 (i32.const 135) (i32.const 101))
          (i32.store8 (i32.const 136) (i32.const 97))
          (i32.store8 (i32.const 137) (i32.const 99))
          (i32.store8 (i32.const 138) (i32.const 104))
          (i32.store8 (i32.const 139) (i32.const 101))
          (i32.store8 (i32.const 140) (i32.const 100))
          (i32.store8 (i32.const 141) (i32.const 58))
          (i32.store8 (i32.const 142) (i32.const 32))
          (i32.store (i32.const 4) (i32.add (i32.const 11) (call $__i32_to_str (local.get $bad) (i32.const 143))))
          (i32.store8 (i32.add (i32.const 132) (i32.load (i32.const 4))) (i32.const 10))
          (i32.store (i32.const 4) (i32.add (i32.load (i32.const 4)) (i32.const 1)))
          (drop (call $fd_write
            (i32.const 1)
            (i32.const 0)
            (i32.const 1)
            (i32.const 128)))
      )
      (catch $__exn_tag
        (local.set $__catch_e_len)
        (local.set $__catch_e_ptr)
            (i32.store (i32.const 0) (i32.const 132))
          (i32.store (i32.const 4) (i32.const 0))
          (i32.store8 (i32.const 132) (i32.const 99))
          (i32.store8 (i32.const 133) (i32.const 97))
          (i32.store8 (i32.const 134) (i32.const 117))
          (i32.store8 (i32.const 135) (i32.const 103))
          (i32.store8 (i32.const 136) (i32.const 104))
          (i32.store8 (i32.const 137) (i32.const 116))
          (i32.store8 (i32.const 138) (i32.const 58))
          (i32.store8 (i32.const 139) (i32.const 32))
          (call $__str_gather (local.get $__catch_e_ptr) (local.get $__catch_e_len) (i32.const 140))
          (i32.store (i32.const 4) (i32.add (i32.const 8) (local.get $__catch_e_len)))
          (i32.store8 (i32.add (i32.const 132) (i32.load (i32.const 4))) (i32.const 10))
          (i32.store (i32.const 4) (i32.add (i32.load (i32.const 4)) (i32.const 1)))
          (drop (call $fd_write
            (i32.const 1)
            (i32.const 0)
            (i32.const 1)
            (i32.const 128)))
      )
    )
        (i32.store (i32.const 0) (i32.const 278))
          (i32.store (i32.const 4) (i32.const 5))
          (drop (call $fd_write
            (i32.const 1)
            (i32.const 0)
            (i32.const 1)
            (i32.const 128)))
  )
  (func $_start (export "_start")
    (call $main)
    (call $__drain_microtasks)
    (call $proc_exit (i32.const 0))
  )
  (table 1 funcref)
  (data (i32.const 260) "\6e\65\67\61\74\69\76\65\20\69\6e\70\75\74")
  (data (i32.const 274) "\62\6f\6f\6d")
  (data (i32.const 278) "\64\6f\6e\65\0a")
)