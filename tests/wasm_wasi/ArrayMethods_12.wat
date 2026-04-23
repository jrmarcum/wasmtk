(module
  (import "wasi_snapshot_preview1" "proc_exit" (func $proc_exit (param i32)))
  (import "wasi_snapshot_preview1" "fd_write" (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (memory (export "memory") 2)
  (global $__heap_ptr (mut i32) (i32.const 279))
  (global $__nullable_ret_flag (mut i32) (i32.const 0))
  (type $ftype_i32_r_void (func (param i32)))
  (type $ftype_i32_r_i32 (func (param i32) (result i32)))
  (type $ftype_i32_i32_r_i32 (func (param i32) (param i32) (result i32)))
  (type $ftype_f64_r_f64 (func (param f64) (result f64)))
  (type $ftype_f64_f64_r_f64 (func (param f64) (param f64) (result f64)))
  ;; Bump allocator — advances __heap_ptr and returns the old value
  (func $__malloc (param $size i32) (result i32)
    (local $ptr i32)
    (local.set $ptr (global.get $__heap_ptr))
    (global.set $__heap_ptr (i32.add (local.get $ptr) (local.get $size)))
    (local.get $ptr)
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

  ;; ── f64 → decimal string ──────────────────────────────────────────────────
  ;; Writes the decimal representation of $val at $buf, returns byte count.
  ;; Outputs the integer part plus up to 15 significant decimal digits.
  ;; Uses ×1e15 i64 arithmetic: 1e15 < 2^53 so the scaled fractional value
  ;; fits exactly in the representable integer range of f64, and the full
  ;; 15-digit result fits in i64. Trailing zeros are stripped from the output.
  ;; Values outside [-2147483648, 2147483647] for the integer part are clamped.
  (func $__f64_to_str (param $val f64) (param $buf i32) (result i32)
    (local $len i32)
    (local $ipart i32)
    (local $fpart i64)
    (local $flen i32)
    (local $fdigits i64)
    (local $ptr i32)
    (local.set $ptr (local.get $buf))
    ;; Handle negative
    (if (f64.lt (local.get $val) (f64.const 0))
      (then
        (i32.store8 (local.get $ptr) (i32.const 45))
        (local.set $ptr (i32.add (local.get $ptr) (i32.const 1)))
        (local.set $val (f64.neg (local.get $val)))
      )
    )
    ;; Integer part
    (local.set $ipart (i32.trunc_f64_s (local.get $val)))
    (local.set $len (call $__i32_to_str (local.get $ipart) (local.get $ptr)))
    (local.set $ptr (i32.add (local.get $ptr) (local.get $len)))
    ;; Fractional part: multiply remainder by 1e15, round to nearest integer.
    ;; f64.nearest corrects truncation error from f64 values slightly below
    ;; their true decimal (e.g. 3.14159 stored as 3.14158999…).
    (local.set $fpart
      (i64.trunc_f64_s
        (f64.nearest
          (f64.mul
            (f64.sub (local.get $val) (f64.convert_i32_s (local.get $ipart)))
            (f64.const 1000000000000000)
          )
        )
      )
    )
    (if (i64.ne (local.get $fpart) (i64.const 0))
      (then
        ;; Decimal point
        (i32.store8 (local.get $ptr) (i32.const 46))
        (local.set $ptr (i32.add (local.get $ptr) (i32.const 1)))
        ;; Write 15-digit fractional string then strip trailing zeros
        (local.set $fdigits (local.get $fpart))
        (local.set $flen (i32.const 15))
        (block $fdone
          (loop $floop
            (br_if $fdone (i32.eqz (local.get $flen)))
            (i32.store8
              (i32.add (local.get $ptr) (i32.sub (local.get $flen) (i32.const 1)))
              (i32.add (i32.const 48) (i32.wrap_i64 (i64.rem_u (local.get $fdigits) (i64.const 10))))
            )
            (local.set $fdigits (i64.div_u (local.get $fdigits) (i64.const 10)))
            (local.set $flen (i32.sub (local.get $flen) (i32.const 1)))
            (br $floop)
          )
        )
        ;; Strip trailing zeros
        (local.set $flen (i32.const 15))
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
  ;; Dynamic array indexof_i32: linear search, returns index or -1.
  (func $__dynarr_indexof_i32 (param $arr i32) (param $val i32) (result i32)
    (local $i i32)
    (local $len i32)
    (local.set $len (i32.load (local.get $arr)))
    (block $brk
      (loop $lp
        (br_if $brk (i32.ge_u (local.get $i) (local.get $len)))
        (if (i32.eq
              (i32.load (i32.add (i32.add (local.get $arr) (i32.const 8)) (i32.shl (local.get $i) (i32.const 2))))
              (local.get $val))
          (then (return (local.get $i)))
        )
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $lp)
      )
    )
    (i32.const -1)
  )

  ;; Dynamic array slice_i32: alloc new array from [start,end), clamp to bounds.
  (func $__dynarr_slice_i32 (param $arr i32) (param $start i32) (param $end i32) (result i32)
    (local $len i32)
    (local $newlen i32)
    (local $newptr i32)
    (local $i i32)
    (local.set $len (i32.load (local.get $arr)))
    (if (i32.lt_s (local.get $start) (i32.const 0)) (then (local.set $start (i32.const 0))))
    (if (i32.gt_s (local.get $start) (local.get $len)) (then (local.set $start (local.get $len))))
    (if (i32.lt_s (local.get $end) (i32.const 0)) (then (local.set $end (i32.const 0))))
    (if (i32.gt_s (local.get $end) (local.get $len)) (then (local.set $end (local.get $len))))
    (local.set $newlen (i32.sub (local.get $end) (local.get $start)))
    (if (i32.lt_s (local.get $newlen) (i32.const 0)) (then (local.set $newlen (i32.const 0))))
    (local.set $newptr (call $__malloc (i32.add (i32.const 8) (i32.shl (local.get $newlen) (i32.const 2)))))
    (i32.store (local.get $newptr) (local.get $newlen))
    (i32.store offset=4 (local.get $newptr) (local.get $newlen))
    (block $done
      (loop $lp
        (br_if $done (i32.ge_u (local.get $i) (local.get $newlen)))
        (i32.store
          (i32.add (i32.add (local.get $newptr) (i32.const 8)) (i32.shl (local.get $i) (i32.const 2)))
          (i32.load
            (i32.add (i32.add (local.get $arr) (i32.const 8))
              (i32.shl (i32.add (local.get $i) (local.get $start)) (i32.const 2)))))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $lp)
      )
    )
    (local.get $newptr)
  )

  ;; Dynamic array foreach_i32: call fn(elem) for each element.
  (func $__dynarr_foreach_i32 (param $arr i32) (param $fn i32)
    (local $i i32)
    (local $len i32)
    (local.set $len (i32.load (local.get $arr)))
    (block $brk
      (loop $lp
        (br_if $brk (i32.ge_u (local.get $i) (local.get $len)))
        (call_indirect (type $ftype_i32_r_void)
          (i32.load (i32.add (i32.add (local.get $arr) (i32.const 8)) (i32.shl (local.get $i) (i32.const 2))))
          (local.get $fn))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $lp)
      )
    )
  )

  ;; Dynamic array map_i32: alloc new array, fill with fn(elem) results.
  (func $__dynarr_map_i32 (param $arr i32) (param $fn i32) (result i32)
    (local $i i32)
    (local $len i32)
    (local $newptr i32)
    (local.set $len (i32.load (local.get $arr)))
    (local.set $newptr (call $__malloc (i32.add (i32.const 8) (i32.shl (local.get $len) (i32.const 2)))))
    (i32.store (local.get $newptr) (local.get $len))
    (i32.store offset=4 (local.get $newptr) (local.get $len))
    (block $brk
      (loop $lp
        (br_if $brk (i32.ge_u (local.get $i) (local.get $len)))
        (i32.store
          (i32.add (i32.add (local.get $newptr) (i32.const 8)) (i32.shl (local.get $i) (i32.const 2)))
          (call_indirect (type $ftype_i32_r_i32)
            (i32.load (i32.add (i32.add (local.get $arr) (i32.const 8)) (i32.shl (local.get $i) (i32.const 2))))
            (local.get $fn)))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $lp)
      )
    )
    (local.get $newptr)
  )

  ;; Dynamic array filter_i32: alloc new array with elements where fn(elem) is truthy.
  (func $__dynarr_filter_i32 (param $arr i32) (param $fn i32) (result i32)
    (local $i i32)
    (local $len i32)
    (local $newptr i32)
    (local $newlen i32)
    (local $val i32)
    (local.set $len (i32.load (local.get $arr)))
    (local.set $newptr (call $__malloc (i32.add (i32.const 8) (i32.shl (local.get $len) (i32.const 2)))))
    (i32.store offset=4 (local.get $newptr) (local.get $len))
    (block $brk
      (loop $lp
        (br_if $brk (i32.ge_u (local.get $i) (local.get $len)))
        (local.set $val (i32.load (i32.add (i32.add (local.get $arr) (i32.const 8)) (i32.shl (local.get $i) (i32.const 2)))))
        (if (call_indirect (type $ftype_i32_r_i32) (local.get $val) (local.get $fn))
          (then
            (i32.store
              (i32.add (i32.add (local.get $newptr) (i32.const 8)) (i32.shl (local.get $newlen) (i32.const 2)))
              (local.get $val))
            (local.set $newlen (i32.add (local.get $newlen) (i32.const 1)))
          )
        )
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $lp)
      )
    )
    (i32.store (local.get $newptr) (local.get $newlen))
    (local.get $newptr)
  )

  ;; Dynamic array find_i32: return first elem where fn(elem) is truthy, or -1.
  (func $__dynarr_find_i32 (param $arr i32) (param $fn i32) (result i32)
    (local $i i32)
    (local $len i32)
    (local $val i32)
    (local.set $len (i32.load (local.get $arr)))
    (block $brk
      (loop $lp
        (br_if $brk (i32.ge_u (local.get $i) (local.get $len)))
        (local.set $val (i32.load (i32.add (i32.add (local.get $arr) (i32.const 8)) (i32.shl (local.get $i) (i32.const 2)))))
        (if (call_indirect (type $ftype_i32_r_i32) (local.get $val) (local.get $fn))
          (then (return (local.get $val)))
        )
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $lp)
      )
    )
    (i32.const -1)
  )

  ;; Dynamic array reduce_i32: fold array with fn(acc, elem), starting from init.
  (func $__dynarr_reduce_i32 (param $arr i32) (param $fn i32) (param $acc i32) (result i32)
    (local $i i32)
    (local $len i32)
    (local.set $len (i32.load (local.get $arr)))
    (block $brk
      (loop $lp
        (br_if $brk (i32.ge_u (local.get $i) (local.get $len)))
        (local.set $acc
          (call_indirect (type $ftype_i32_i32_r_i32)
            (local.get $acc)
            (i32.load (i32.add (i32.add (local.get $arr) (i32.const 8)) (i32.shl (local.get $i) (i32.const 2))))
            (local.get $fn)))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $lp)
      )
    )
    (local.get $acc)
  )

  ;; Dynamic array map_f64: alloc new array, fill with fn(elem) results.
  (func $__dynarr_map_f64 (param $arr i32) (param $fn i32) (result i32)
    (local $i i32)
    (local $len i32)
    (local $newptr i32)
    (local.set $len (i32.load (local.get $arr)))
    (local.set $newptr (call $__malloc (i32.add (i32.const 8) (i32.shl (local.get $len) (i32.const 3)))))
    (i32.store (local.get $newptr) (local.get $len))
    (i32.store offset=4 (local.get $newptr) (local.get $len))
    (block $brk
      (loop $lp
        (br_if $brk (i32.ge_u (local.get $i) (local.get $len)))
        (f64.store
          (i32.add (i32.add (local.get $newptr) (i32.const 8)) (i32.shl (local.get $i) (i32.const 3)))
          (call_indirect (type $ftype_f64_r_f64)
            (f64.load (i32.add (i32.add (local.get $arr) (i32.const 8)) (i32.shl (local.get $i) (i32.const 3))))
            (local.get $fn)))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $lp)
      )
    )
    (local.get $newptr)
  )

  ;; Dynamic array reduce_f64: fold array with fn(acc, elem), starting from init.
  (func $__dynarr_reduce_f64 (param $arr i32) (param $fn i32) (param $acc f64) (result f64)
    (local $i i32)
    (local $len i32)
    (local.set $len (i32.load (local.get $arr)))
    (block $brk
      (loop $lp
        (br_if $brk (i32.ge_u (local.get $i) (local.get $len)))
        (local.set $acc
          (call_indirect (type $ftype_f64_f64_r_f64)
            (local.get $acc)
            (f64.load (i32.add (i32.add (local.get $arr) (i32.const 8)) (i32.shl (local.get $i) (i32.const 3))))
            (local.get $fn)))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $lp)
      )
    )
    (local.get $acc)
  )
  (func $printElem (param $v i32) 
    (local $__iface_tmp i32)
        (i32.store (i32.const 0) (i32.const 132))
          (i32.store (i32.const 4) (call $__i32_to_str (local.get $v) (i32.const 132)))
          (i32.store8 (i32.add (i32.const 132) (i32.load (i32.const 4))) (i32.const 10))
          (i32.store (i32.const 4) (i32.add (i32.load (i32.const 4)) (i32.const 1)))
          (drop (call $fd_write
            (i32.const 1)
            (i32.const 0)
            (i32.const 1)
            (i32.const 128)))
  )

  (func $doubleIt (param $v i32) (result i32)
    (return (i32.mul (local.get $v) (i32.const 2)))
  )

  (func $isOver25 (param $v i32) (result i32)
    (return (i32.gt_s (local.get $v) (i32.const 25)))
  )

  (func $isOver15 (param $v i32) (result i32)
    (return (i32.gt_s (local.get $v) (i32.const 15)))
  )

  (func $isNeg (param $v i32) (result i32)
    (return (i32.lt_s (local.get $v) (i32.const 0)))
  )

  (func $addUp (param $acc i32) (param $v i32) (result i32)
    (return (i32.add (local.get $acc) (local.get $v)))
  )

  (func $dbl (param $v f64) (result f64)
    (return (f64.mul (local.get $v) (f64.const 2.0)))
  )

  (func $sumF (param $acc f64) (param $v f64) (result f64)
    (return (f64.add (local.get $acc) (local.get $v)))
  )
  (func $_start (export "_start")
    (local $nums i32)
    (local $idx i32)
    (local $miss i32)
    (local $has40 i32)
    (local $has99 i32)
    (local $sliced i32)
    (local $tail i32)
    (local $doubled i32)
    (local $big i32)
    (local $found i32)
    (local $found__null i32)
    (local $notFound i32)
    (local $notFound__null i32)
    (local $total i32)
    (local $fvals i32)
    (local $fmapped i32)
    (local $fsum f64)
    (local $__iface_tmp i32)
    (local.set $nums (call $__malloc (i32.const 48)))
      (i32.store (local.get $nums) (i32.const 5))
      (i32.store offset=4 (local.get $nums) (i32.const 10))
      (i32.store offset=8 (local.get $nums) (i32.const 10))
      (i32.store offset=12 (local.get $nums) (i32.const 20))
      (i32.store offset=16 (local.get $nums) (i32.const 30))
      (i32.store offset=20 (local.get $nums) (i32.const 40))
      (i32.store offset=24 (local.get $nums) (i32.const 50))
    (local.set $idx (call $__dynarr_indexof_i32 (local.get $nums) (i32.const 30)))
        (i32.store (i32.const 0) (i32.const 132))
          (i32.store (i32.const 4) (call $__i32_to_str (local.get $idx) (i32.const 132)))
          (i32.store8 (i32.add (i32.const 132) (i32.load (i32.const 4))) (i32.const 10))
          (i32.store (i32.const 4) (i32.add (i32.load (i32.const 4)) (i32.const 1)))
          (drop (call $fd_write
            (i32.const 1)
            (i32.const 0)
            (i32.const 1)
            (i32.const 128)))
    (local.set $miss (call $__dynarr_indexof_i32 (local.get $nums) (i32.const 99)))
        (i32.store (i32.const 0) (i32.const 132))
          (i32.store (i32.const 4) (call $__i32_to_str (local.get $miss) (i32.const 132)))
          (i32.store8 (i32.add (i32.const 132) (i32.load (i32.const 4))) (i32.const 10))
          (i32.store (i32.const 4) (i32.add (i32.load (i32.const 4)) (i32.const 1)))
          (drop (call $fd_write
            (i32.const 1)
            (i32.const 0)
            (i32.const 1)
            (i32.const 128)))
    (local.set $has40 (i32.ne (call $__dynarr_indexof_i32 (local.get $nums) (i32.const 40)) (i32.const -1)))
        (i32.store (i32.const 0) (i32.const 132))
          (i32.store (i32.const 4) (i32.const 0))
          (call $__str_gather (if (result i32) (local.get $has40) (then (i32.const 260)) (else (i32.const 264))) (if (result i32) (local.get $has40) (then (i32.const 4)) (else (i32.const 5))) (i32.const 132))
          (i32.store (i32.const 4) (i32.add (i32.const 0) (if (result i32) (local.get $has40) (then (i32.const 4)) (else (i32.const 5)))))
          (i32.store8 (i32.add (i32.const 132) (i32.load (i32.const 4))) (i32.const 10))
          (i32.store (i32.const 4) (i32.add (i32.load (i32.const 4)) (i32.const 1)))
          (drop (call $fd_write
            (i32.const 1)
            (i32.const 0)
            (i32.const 1)
            (i32.const 128)))
    (local.set $has99 (i32.ne (call $__dynarr_indexof_i32 (local.get $nums) (i32.const 99)) (i32.const -1)))
        (i32.store (i32.const 0) (i32.const 132))
          (i32.store (i32.const 4) (i32.const 0))
          (call $__str_gather (if (result i32) (local.get $has99) (then (i32.const 260)) (else (i32.const 264))) (if (result i32) (local.get $has99) (then (i32.const 4)) (else (i32.const 5))) (i32.const 132))
          (i32.store (i32.const 4) (i32.add (i32.const 0) (if (result i32) (local.get $has99) (then (i32.const 4)) (else (i32.const 5)))))
          (i32.store8 (i32.add (i32.const 132) (i32.load (i32.const 4))) (i32.const 10))
          (i32.store (i32.const 4) (i32.add (i32.load (i32.const 4)) (i32.const 1)))
          (drop (call $fd_write
            (i32.const 1)
            (i32.const 0)
            (i32.const 1)
            (i32.const 128)))
    (local.set $sliced (call $__dynarr_slice_i32 (local.get $nums) (i32.const 1) (i32.const 4)))
        (i32.store (i32.const 0) (i32.const 132))
          (i32.store (i32.const 4) (call $__i32_to_str (i32.load (local.get $sliced)) (i32.const 132)))
          (i32.store8 (i32.add (i32.const 132) (i32.load (i32.const 4))) (i32.const 10))
          (i32.store (i32.const 4) (i32.add (i32.load (i32.const 4)) (i32.const 1)))
          (drop (call $fd_write
            (i32.const 1)
            (i32.const 0)
            (i32.const 1)
            (i32.const 128)))
        (i32.store (i32.const 0) (i32.const 132))
          (i32.store (i32.const 4) (call $__i32_to_str (i32.load (i32.add (i32.add (local.get $sliced) (i32.const 8)) (i32.shl (i32.const 0) (i32.const 2)))) (i32.const 132)))
          (i32.store8 (i32.add (i32.const 132) (i32.load (i32.const 4))) (i32.const 10))
          (i32.store (i32.const 4) (i32.add (i32.load (i32.const 4)) (i32.const 1)))
          (drop (call $fd_write
            (i32.const 1)
            (i32.const 0)
            (i32.const 1)
            (i32.const 128)))
        (i32.store (i32.const 0) (i32.const 132))
          (i32.store (i32.const 4) (call $__i32_to_str (i32.load (i32.add (i32.add (local.get $sliced) (i32.const 8)) (i32.shl (i32.const 2) (i32.const 2)))) (i32.const 132)))
          (i32.store8 (i32.add (i32.const 132) (i32.load (i32.const 4))) (i32.const 10))
          (i32.store (i32.const 4) (i32.add (i32.load (i32.const 4)) (i32.const 1)))
          (drop (call $fd_write
            (i32.const 1)
            (i32.const 0)
            (i32.const 1)
            (i32.const 128)))
    (local.set $tail (call $__dynarr_slice_i32 (local.get $nums) (i32.const 3) (i32.const 99)))
        (i32.store (i32.const 0) (i32.const 132))
          (i32.store (i32.const 4) (call $__i32_to_str (i32.load (local.get $tail)) (i32.const 132)))
          (i32.store8 (i32.add (i32.const 132) (i32.load (i32.const 4))) (i32.const 10))
          (i32.store (i32.const 4) (i32.add (i32.load (i32.const 4)) (i32.const 1)))
          (drop (call $fd_write
            (i32.const 1)
            (i32.const 0)
            (i32.const 1)
            (i32.const 128)))
        (i32.store (i32.const 0) (i32.const 132))
          (i32.store (i32.const 4) (call $__i32_to_str (i32.load (i32.add (i32.add (local.get $tail) (i32.const 8)) (i32.shl (i32.const 1) (i32.const 2)))) (i32.const 132)))
          (i32.store8 (i32.add (i32.const 132) (i32.load (i32.const 4))) (i32.const 10))
          (i32.store (i32.const 4) (i32.add (i32.load (i32.const 4)) (i32.const 1)))
          (drop (call $fd_write
            (i32.const 1)
            (i32.const 0)
            (i32.const 1)
            (i32.const 128)))
    (call $__dynarr_foreach_i32 (local.get $nums) (i32.const 0))
    (local.set $doubled (call $__dynarr_map_i32 (local.get $nums) (i32.const 1)))
        (i32.store (i32.const 0) (i32.const 132))
          (i32.store (i32.const 4) (call $__i32_to_str (i32.load (local.get $doubled)) (i32.const 132)))
          (i32.store8 (i32.add (i32.const 132) (i32.load (i32.const 4))) (i32.const 10))
          (i32.store (i32.const 4) (i32.add (i32.load (i32.const 4)) (i32.const 1)))
          (drop (call $fd_write
            (i32.const 1)
            (i32.const 0)
            (i32.const 1)
            (i32.const 128)))
        (i32.store (i32.const 0) (i32.const 132))
          (i32.store (i32.const 4) (call $__i32_to_str (i32.load (i32.add (i32.add (local.get $doubled) (i32.const 8)) (i32.shl (i32.const 0) (i32.const 2)))) (i32.const 132)))
          (i32.store8 (i32.add (i32.const 132) (i32.load (i32.const 4))) (i32.const 10))
          (i32.store (i32.const 4) (i32.add (i32.load (i32.const 4)) (i32.const 1)))
          (drop (call $fd_write
            (i32.const 1)
            (i32.const 0)
            (i32.const 1)
            (i32.const 128)))
        (i32.store (i32.const 0) (i32.const 132))
          (i32.store (i32.const 4) (call $__i32_to_str (i32.load (i32.add (i32.add (local.get $doubled) (i32.const 8)) (i32.shl (i32.const 4) (i32.const 2)))) (i32.const 132)))
          (i32.store8 (i32.add (i32.const 132) (i32.load (i32.const 4))) (i32.const 10))
          (i32.store (i32.const 4) (i32.add (i32.load (i32.const 4)) (i32.const 1)))
          (drop (call $fd_write
            (i32.const 1)
            (i32.const 0)
            (i32.const 1)
            (i32.const 128)))
    (local.set $big (call $__dynarr_filter_i32 (local.get $nums) (i32.const 2)))
        (i32.store (i32.const 0) (i32.const 132))
          (i32.store (i32.const 4) (call $__i32_to_str (i32.load (local.get $big)) (i32.const 132)))
          (i32.store8 (i32.add (i32.const 132) (i32.load (i32.const 4))) (i32.const 10))
          (i32.store (i32.const 4) (i32.add (i32.load (i32.const 4)) (i32.const 1)))
          (drop (call $fd_write
            (i32.const 1)
            (i32.const 0)
            (i32.const 1)
            (i32.const 128)))
        (i32.store (i32.const 0) (i32.const 132))
          (i32.store (i32.const 4) (call $__i32_to_str (i32.load (i32.add (i32.add (local.get $big) (i32.const 8)) (i32.shl (i32.const 0) (i32.const 2)))) (i32.const 132)))
          (i32.store8 (i32.add (i32.const 132) (i32.load (i32.const 4))) (i32.const 10))
          (i32.store (i32.const 4) (i32.add (i32.load (i32.const 4)) (i32.const 1)))
          (drop (call $fd_write
            (i32.const 1)
            (i32.const 0)
            (i32.const 1)
            (i32.const 128)))
        (i32.store (i32.const 0) (i32.const 132))
          (i32.store (i32.const 4) (call $__i32_to_str (i32.load (i32.add (i32.add (local.get $big) (i32.const 8)) (i32.shl (i32.const 2) (i32.const 2)))) (i32.const 132)))
          (i32.store8 (i32.add (i32.const 132) (i32.load (i32.const 4))) (i32.const 10))
          (i32.store (i32.const 4) (i32.add (i32.load (i32.const 4)) (i32.const 1)))
          (drop (call $fd_write
            (i32.const 1)
            (i32.const 0)
            (i32.const 1)
            (i32.const 128)))
    (local.set $found (call $__dynarr_find_i32 (local.get $nums) (i32.const 3)))
      (local.set $found__null (i32.const 0))
        (if (i32.eq (local.get $found) (i32.const -1))
      (then
        (i32.store (i32.const 0) (i32.const 269))
        (i32.store (i32.const 4) (i32.const 10))
        (drop (call $fd_write (i32.const 1) (i32.const 0) (i32.const 1) (i32.const 128)))
      )
      (else
        (i32.store (i32.const 0) (i32.const 132))
        (i32.store (i32.const 4) (call $__i32_to_str (local.get $found) (i32.const 132)))
        (i32.store8 (i32.add (i32.const 132) (i32.load (i32.const 4))) (i32.const 10))
        (i32.store (i32.const 4) (i32.add (i32.load (i32.const 4)) (i32.const 1)))
        (drop (call $fd_write
          (i32.const 1)
          (i32.const 0)
          (i32.const 1)
          (i32.const 128)))
      )
    )
    (local.set $notFound (call $__dynarr_find_i32 (local.get $nums) (i32.const 4)))
      (local.set $notFound__null (i32.const 0))
        (if (i32.eq (local.get $notFound) (i32.const -1))
      (then
        (i32.store (i32.const 0) (i32.const 269))
        (i32.store (i32.const 4) (i32.const 10))
        (drop (call $fd_write (i32.const 1) (i32.const 0) (i32.const 1) (i32.const 128)))
      )
      (else
        (i32.store (i32.const 0) (i32.const 132))
        (i32.store (i32.const 4) (call $__i32_to_str (local.get $notFound) (i32.const 132)))
        (i32.store8 (i32.add (i32.const 132) (i32.load (i32.const 4))) (i32.const 10))
        (i32.store (i32.const 4) (i32.add (i32.load (i32.const 4)) (i32.const 1)))
        (drop (call $fd_write
          (i32.const 1)
          (i32.const 0)
          (i32.const 1)
          (i32.const 128)))
      )
    )
    (local.set $total (call $__dynarr_reduce_i32 (local.get $nums) (i32.const 5) (i32.const 0)))
        (i32.store (i32.const 0) (i32.const 132))
          (i32.store (i32.const 4) (call $__i32_to_str (local.get $total) (i32.const 132)))
          (i32.store8 (i32.add (i32.const 132) (i32.load (i32.const 4))) (i32.const 10))
          (i32.store (i32.const 4) (i32.add (i32.load (i32.const 4)) (i32.const 1)))
          (drop (call $fd_write
            (i32.const 1)
            (i32.const 0)
            (i32.const 1)
            (i32.const 128)))
    (local.set $fvals (call $__malloc (i32.const 72)))
      (i32.store (local.get $fvals) (i32.const 3))
      (i32.store offset=4 (local.get $fvals) (i32.const 8))
      (f64.store offset=8 (local.get $fvals) (f64.const 1.5))
      (f64.store offset=16 (local.get $fvals) (f64.const 2.5))
      (f64.store offset=24 (local.get $fvals) (f64.const 3.5))
    (local.set $fmapped (call $__dynarr_map_f64 (local.get $fvals) (i32.const 6)))
        (i32.store (i32.const 0) (i32.const 132))
          (i32.store (i32.const 4) (call $__i32_to_str (i32.load (local.get $fmapped)) (i32.const 132)))
          (i32.store8 (i32.add (i32.const 132) (i32.load (i32.const 4))) (i32.const 10))
          (i32.store (i32.const 4) (i32.add (i32.load (i32.const 4)) (i32.const 1)))
          (drop (call $fd_write
            (i32.const 1)
            (i32.const 0)
            (i32.const 1)
            (i32.const 128)))
        (i32.store (i32.const 0) (i32.const 132))
          (i32.store (i32.const 4) (call $__f64_to_str (f64.load (i32.add (i32.add (local.get $fmapped) (i32.const 8)) (i32.shl (i32.const 1) (i32.const 3)))) (i32.const 132)))
          (i32.store8 (i32.add (i32.const 132) (i32.load (i32.const 4))) (i32.const 10))
          (i32.store (i32.const 4) (i32.add (i32.load (i32.const 4)) (i32.const 1)))
          (drop (call $fd_write
            (i32.const 1)
            (i32.const 0)
            (i32.const 1)
            (i32.const 128)))
    (local.set $fsum (call $__dynarr_reduce_f64 (local.get $fvals) (i32.const 7) (f64.const 0.0)))
        (i32.store (i32.const 0) (i32.const 132))
          (i32.store (i32.const 4) (call $__f64_to_str (local.get $fsum) (i32.const 132)))
          (i32.store8 (i32.add (i32.const 132) (i32.load (i32.const 4))) (i32.const 10))
          (i32.store (i32.const 4) (i32.add (i32.load (i32.const 4)) (i32.const 1)))
          (drop (call $fd_write
            (i32.const 1)
            (i32.const 0)
            (i32.const 1)
            (i32.const 128)))
    (call $proc_exit (i32.const 0))
  )
  (table 8 funcref)
  (elem (i32.const 0) $printElem $doubleIt $isOver25 $isOver15 $isNeg $addUp $dbl $sumF)
  (data (i32.const 260) "\74\72\75\65")
  (data (i32.const 264) "\66\61\6c\73\65")
  (data (i32.const 269) "\75\6e\64\65\66\69\6e\65\64\0a")
)