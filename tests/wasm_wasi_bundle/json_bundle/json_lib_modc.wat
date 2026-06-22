(module
  (memory (export "memory") 2)
  (global $__heap_ptr (mut i32) (i32.const 260))
  (global $pos (mut i32) (i32.const 0))
  (global $lastLen (mut i32) (i32.const 0))
  ;; Bump allocator — advances __heap_ptr and returns the old value.
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

  ;; ── str_trim: remove leading and trailing ASCII whitespace ─────────────────
  ;; Whitespace = 0x09 (tab), 0x0a (LF), 0x0d (CR), 0x20 (space).
  ;; Returns (new_ptr, new_len) which is a sub-range of the original buffer.
  (func $__str_trim
    (param $ptr i32) (param $len i32)
    (result i32 i32)
    (local $s i32) (local $e i32) (local $b i32)
    (local.set $s (i32.const 0))
    (local.set $e (local.get $len))
    ;; advance $s past leading whitespace
    (block $done_s
      (loop $loop_s
        (br_if $done_s (i32.ge_u (local.get $s) (local.get $e)))
        (local.set $b (i32.load8_u (i32.add (local.get $ptr) (local.get $s))))
        (br_if $done_s (i32.and
          (i32.and (i32.ne (local.get $b) (i32.const 0x20)) (i32.ne (local.get $b) (i32.const 0x09)))
          (i32.and (i32.ne (local.get $b) (i32.const 0x0a)) (i32.ne (local.get $b) (i32.const 0x0d)))
        ))
        (local.set $s (i32.add (local.get $s) (i32.const 1)))
        (br $loop_s)
      )
    )
    ;; retreat $e past trailing whitespace
    (block $done_e
      (loop $loop_e
        (br_if $done_e (i32.le_u (local.get $e) (local.get $s)))
        (local.set $b (i32.load8_u (i32.add (local.get $ptr) (i32.sub (local.get $e) (i32.const 1)))))
        (br_if $done_e (i32.and
          (i32.and (i32.ne (local.get $b) (i32.const 0x20)) (i32.ne (local.get $b) (i32.const 0x09)))
          (i32.and (i32.ne (local.get $b) (i32.const 0x0a)) (i32.ne (local.get $b) (i32.const 0x0d)))
        ))
        (local.set $e (i32.sub (local.get $e) (i32.const 1)))
        (br $loop_e)
      )
    )
    (i32.add (local.get $ptr) (local.get $s))
    (i32.sub (local.get $e) (local.get $s))
  )

  ;; ── str_trim_start: remove leading ASCII whitespace ──────────────────────────
  (func $__str_trim_start
    (param $ptr i32) (param $len i32)
    (result i32 i32)
    (local $s i32) (local $b i32)
    (block $done
      (loop $loop
        (br_if $done (i32.ge_u (local.get $s) (local.get $len)))
        (local.set $b (i32.load8_u (i32.add (local.get $ptr) (local.get $s))))
        (br_if $done (i32.and
          (i32.and (i32.ne (local.get $b) (i32.const 0x20)) (i32.ne (local.get $b) (i32.const 0x09)))
          (i32.and (i32.ne (local.get $b) (i32.const 0x0a)) (i32.ne (local.get $b) (i32.const 0x0d)))
        ))
        (local.set $s (i32.add (local.get $s) (i32.const 1)))
        (br $loop)
      )
    )
    (i32.add (local.get $ptr) (local.get $s))
    (i32.sub (local.get $len) (local.get $s))
  )

  ;; ── str_trim_end: remove trailing ASCII whitespace ───────────────────────────
  (func $__str_trim_end
    (param $ptr i32) (param $len i32)
    (result i32 i32)
    (local $e i32) (local $b i32)
    (local.set $e (local.get $len))
    (block $done
      (loop $loop
        (br_if $done (i32.eqz (local.get $e)))
        (local.set $b (i32.load8_u (i32.add (local.get $ptr) (i32.sub (local.get $e) (i32.const 1)))))
        (br_if $done (i32.and
          (i32.and (i32.ne (local.get $b) (i32.const 0x20)) (i32.ne (local.get $b) (i32.const 0x09)))
          (i32.and (i32.ne (local.get $b) (i32.const 0x0a)) (i32.ne (local.get $b) (i32.const 0x0d)))
        ))
        (local.set $e (i32.sub (local.get $e) (i32.const 1)))
        (br $loop)
      )
    )
    (local.get $ptr)
    (local.get $e)
  )

  ;; ── str_char_code_at: char code at index i, or -1 if out of bounds ───────────
  (func $__str_char_code_at
    (param $ptr i32) (param $len i32) (param $i i32)
    (result i32)
    (if (i32.lt_s (local.get $i) (i32.const 0)) (then (return (i32.const -1))))
    (if (i32.ge_u (local.get $i) (local.get $len)) (then (return (i32.const -1))))
    (i32.load8_u (i32.add (local.get $ptr) (local.get $i)))
  )

  ;; ── str_char_at: single-char sub-string at index i ───────────────────────────
  ;; Returns (ptr+i, 1) if in bounds, (ptr, 0) if out of bounds.
  (func $__str_char_at
    (param $ptr i32) (param $len i32) (param $i i32)
    (result i32 i32)
    (if (i32.lt_s (local.get $i) (i32.const 0))
      (then (return (local.get $ptr) (i32.const 0)))
    )
    (if (i32.ge_u (local.get $i) (local.get $len))
      (then (return (local.get $ptr) (i32.const 0)))
    )
    (i32.add (local.get $ptr) (local.get $i))
    (i32.const 1)
  )

  ;; ── str_starts_with: true if str begins with sub ─────────────────────────────
  (func $__str_starts_with
    (param $ptr i32) (param $len i32) (param $subptr i32) (param $sublen i32)
    (result i32)
    (local $j i32)
    (if (i32.gt_u (local.get $sublen) (local.get $len)) (then (return (i32.const 0))))
    (block $done
      (loop $loop
        (br_if $done (i32.ge_u (local.get $j) (local.get $sublen)))
        (if (i32.ne
          (i32.load8_u (i32.add (local.get $ptr) (local.get $j)))
          (i32.load8_u (i32.add (local.get $subptr) (local.get $j)))
        ) (then (return (i32.const 0))))
        (local.set $j (i32.add (local.get $j) (i32.const 1)))
        (br $loop)
      )
    )
    (i32.const 1)
  )

  ;; ── str_ends_with: true if str ends with sub ─────────────────────────────────
  (func $__str_ends_with
    (param $ptr i32) (param $len i32) (param $subptr i32) (param $sublen i32)
    (result i32)
    (local $j i32) (local $off i32)
    (if (i32.gt_u (local.get $sublen) (local.get $len)) (then (return (i32.const 0))))
    (local.set $off (i32.sub (local.get $len) (local.get $sublen)))
    (block $done
      (loop $loop
        (br_if $done (i32.ge_u (local.get $j) (local.get $sublen)))
        (if (i32.ne
          (i32.load8_u (i32.add (local.get $ptr) (i32.add (local.get $off) (local.get $j))))
          (i32.load8_u (i32.add (local.get $subptr) (local.get $j)))
        ) (then (return (i32.const 0))))
        (local.set $j (i32.add (local.get $j) (i32.const 1)))
        (br $loop)
      )
    )
    (i32.const 1)
  )

  ;; ── str_to_upper: ASCII uppercase into a new heap buffer ────────────────────
  (func $__str_to_upper
    (param $ptr i32) (param $len i32)
    (result i32 i32)
    (local $newptr i32) (local $i i32) (local $b i32)
    (local.set $newptr (call $__malloc (local.get $len)))
    (block $done
      (loop $loop
        (br_if $done (i32.ge_u (local.get $i) (local.get $len)))
        (local.set $b (i32.load8_u (i32.add (local.get $ptr) (local.get $i))))
        (if (i32.and (i32.ge_u (local.get $b) (i32.const 97)) (i32.le_u (local.get $b) (i32.const 122)))
          (then (local.set $b (i32.sub (local.get $b) (i32.const 32))))
        )
        (i32.store8 (i32.add (local.get $newptr) (local.get $i)) (local.get $b))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $loop)
      )
    )
    (local.get $newptr)
    (local.get $len)
  )

  ;; ── str_to_lower: ASCII lowercase into a new heap buffer ────────────────────
  (func $__str_to_lower
    (param $ptr i32) (param $len i32)
    (result i32 i32)
    (local $newptr i32) (local $i i32) (local $b i32)
    (local.set $newptr (call $__malloc (local.get $len)))
    (block $done
      (loop $loop
        (br_if $done (i32.ge_u (local.get $i) (local.get $len)))
        (local.set $b (i32.load8_u (i32.add (local.get $ptr) (local.get $i))))
        (if (i32.and (i32.ge_u (local.get $b) (i32.const 65)) (i32.le_u (local.get $b) (i32.const 90)))
          (then (local.set $b (i32.add (local.get $b) (i32.const 32))))
        )
        (i32.store8 (i32.add (local.get $newptr) (local.get $i)) (local.get $b))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $loop)
      )
    )
    (local.get $newptr)
    (local.get $len)
  )

  ;; ── str_replace: replace first occurrence of old with new ───────────────────
  ;; Returns new heap string (or original ptr/len if old not found).
  (func $__str_replace
    (param $ptr i32) (param $len i32)
    (param $oldptr i32) (param $oldlen i32)
    (param $newptr i32) (param $newlen i32)
    (result i32 i32)
    (local $pos i32) (local $outlen i32) (local $out i32) (local $wi i32)
    (local.set $pos (call $__str_indexof (local.get $ptr) (local.get $len) (local.get $oldptr) (local.get $oldlen)))
    (if (i32.eq (local.get $pos) (i32.const -1))
      (then (return (local.get $ptr) (local.get $len)))
    )
    (local.set $outlen (i32.add (i32.sub (local.get $len) (local.get $oldlen)) (local.get $newlen)))
    (local.set $out (call $__malloc (local.get $outlen)))
    ;; copy prefix [0, pos)
    (local.set $wi (i32.const 0))
    (block $d0 (loop $l0
      (br_if $d0 (i32.ge_u (local.get $wi) (local.get $pos)))
      (i32.store8 (i32.add (local.get $out) (local.get $wi))
        (i32.load8_u (i32.add (local.get $ptr) (local.get $wi))))
      (local.set $wi (i32.add (local.get $wi) (i32.const 1)))
      (br $l0)
    ))
    ;; copy new string
    (block $d1 (loop $l1
      (br_if $d1 (i32.ge_u (local.get $wi) (i32.add (local.get $pos) (local.get $newlen))))
      (i32.store8 (i32.add (local.get $out) (local.get $wi))
        (i32.load8_u (i32.add (local.get $newptr) (i32.sub (local.get $wi) (local.get $pos)))))
      (local.set $wi (i32.add (local.get $wi) (i32.const 1)))
      (br $l1)
    ))
    ;; copy suffix [pos+oldlen, len)
    (block $d2 (loop $l2
      (br_if $d2 (i32.ge_u (local.get $wi) (local.get $outlen)))
      (i32.store8 (i32.add (local.get $out) (local.get $wi))
        (i32.load8_u (i32.add (local.get $ptr) (i32.sub (i32.add (local.get $wi) (local.get $oldlen)) (local.get $newlen)))))
      (local.set $wi (i32.add (local.get $wi) (i32.const 1)))
      (br $l2)
    ))
    (local.get $out)
    (local.get $outlen)
  )

  ;; ── str_replace_all: replace all occurrences of old with new ────────────────
  (func $__str_replace_all
    (param $ptr i32) (param $len i32)
    (param $oldptr i32) (param $oldlen i32)
    (param $newptr i32) (param $newlen i32)
    (result i32 i32)
    (local $cur i32) (local $pos i32) (local $buf i32) (local $blen i32)
    (local $wi i32) (local $ri i32) (local $seglen i32)
    ;; worst-case capacity: outlen <= len * (newlen/oldlen + 1) — allocate generously
    ;; simple heuristic: (len + 1) * (newlen + 1)
    (local.set $blen (i32.mul (i32.add (local.get $len) (i32.const 1)) (i32.add (local.get $newlen) (i32.const 1))))
    (local.set $buf (call $__malloc (local.get $blen)))
    (local.set $cur (i32.const 0))
    (local.set $wi (i32.const 0))
    (block $done
      (loop $loop
        ;; find next occurrence from $cur
        (local.set $pos (call $__str_indexof
          (i32.add (local.get $ptr) (local.get $cur))
          (i32.sub (local.get $len) (local.get $cur))
          (local.get $oldptr) (local.get $oldlen)
        ))
        (if (i32.eq (local.get $pos) (i32.const -1)) (then (br $done)))
        (local.set $pos (i32.add (local.get $pos) (local.get $cur)))
        ;; copy segment before match
        (local.set $seglen (i32.sub (local.get $pos) (local.get $cur)))
        (local.set $ri (i32.const 0))
        (block $ds (loop $ls
          (br_if $ds (i32.ge_u (local.get $ri) (local.get $seglen)))
          (i32.store8 (i32.add (local.get $buf) (local.get $wi))
            (i32.load8_u (i32.add (local.get $ptr) (i32.add (local.get $cur) (local.get $ri)))))
          (local.set $wi (i32.add (local.get $wi) (i32.const 1)))
          (local.set $ri (i32.add (local.get $ri) (i32.const 1)))
          (br $ls)
        ))
        ;; copy new string
        (local.set $ri (i32.const 0))
        (block $dn (loop $ln
          (br_if $dn (i32.ge_u (local.get $ri) (local.get $newlen)))
          (i32.store8 (i32.add (local.get $buf) (local.get $wi))
            (i32.load8_u (i32.add (local.get $newptr) (local.get $ri))))
          (local.set $wi (i32.add (local.get $wi) (i32.const 1)))
          (local.set $ri (i32.add (local.get $ri) (i32.const 1)))
          (br $ln)
        ))
        (local.set $cur (i32.add (local.get $pos) (i32.add (local.get $oldlen) (i32.const 0))))
        ;; guard against zero-length old (avoid infinite loop)
        (if (i32.eqz (local.get $oldlen))
          (then
            (local.set $cur (i32.add (local.get $cur) (i32.const 1)))
            (if (i32.gt_u (local.get $cur) (local.get $len)) (then (br $done)))
          )
        )
        (br $loop)
      )
    )
    ;; copy remaining tail
    (local.set $ri (local.get $cur))
    (block $dt (loop $lt
      (br_if $dt (i32.ge_u (local.get $ri) (local.get $len)))
      (i32.store8 (i32.add (local.get $buf) (local.get $wi))
        (i32.load8_u (i32.add (local.get $ptr) (local.get $ri))))
      (local.set $wi (i32.add (local.get $wi) (i32.const 1)))
      (local.set $ri (i32.add (local.get $ri) (i32.const 1)))
      (br $lt)
    ))
    (local.get $buf)
    (local.get $wi)
  )

  ;; ── str_pad_start: pad string to targetLen with pad chars on the left ────────
  (func $__str_pad_start
    (param $ptr i32) (param $len i32) (param $target i32) (param $padptr i32) (param $padlen i32)
    (result i32 i32)
    (local $out i32) (local $need i32) (local $wi i32) (local $pi i32)
    (if (i32.le_s (local.get $target) (local.get $len))
      (then (return (local.get $ptr) (local.get $len)))
    )
    (local.set $need (i32.sub (local.get $target) (local.get $len)))
    (local.set $out (call $__malloc (local.get $target)))
    ;; fill pad chars cycling through padstr
    (if (i32.eqz (local.get $padlen)) (then (local.set $padlen (i32.const 1))))
    (block $dp (loop $lp
      (br_if $dp (i32.ge_u (local.get $wi) (local.get $need)))
      (local.set $pi (i32.rem_u (local.get $wi) (local.get $padlen)))
      (i32.store8 (i32.add (local.get $out) (local.get $wi))
        (i32.load8_u (i32.add (local.get $padptr) (local.get $pi))))
      (local.set $wi (i32.add (local.get $wi) (i32.const 1)))
      (br $lp)
    ))
    ;; copy original string
    (local.set $pi (i32.const 0))
    (block $ds (loop $ls
      (br_if $ds (i32.ge_u (local.get $pi) (local.get $len)))
      (i32.store8 (i32.add (local.get $out) (i32.add (local.get $need) (local.get $pi)))
        (i32.load8_u (i32.add (local.get $ptr) (local.get $pi))))
      (local.set $pi (i32.add (local.get $pi) (i32.const 1)))
      (br $ls)
    ))
    (local.get $out)
    (local.get $target)
  )

  ;; ── str_pad_end: pad string to targetLen with pad chars on the right ─────────
  (func $__str_pad_end
    (param $ptr i32) (param $len i32) (param $target i32) (param $padptr i32) (param $padlen i32)
    (result i32 i32)
    (local $out i32) (local $need i32) (local $wi i32) (local $pi i32)
    (if (i32.le_s (local.get $target) (local.get $len))
      (then (return (local.get $ptr) (local.get $len)))
    )
    (local.set $need (i32.sub (local.get $target) (local.get $len)))
    (local.set $out (call $__malloc (local.get $target)))
    ;; copy original string first
    (block $ds (loop $ls
      (br_if $ds (i32.ge_u (local.get $wi) (local.get $len)))
      (i32.store8 (i32.add (local.get $out) (local.get $wi))
        (i32.load8_u (i32.add (local.get $ptr) (local.get $wi))))
      (local.set $wi (i32.add (local.get $wi) (i32.const 1)))
      (br $ls)
    ))
    ;; fill pad chars
    (if (i32.eqz (local.get $padlen)) (then (local.set $padlen (i32.const 1))))
    (block $dp (loop $lp
      (br_if $dp (i32.ge_u (local.get $wi) (local.get $target)))
      (local.set $pi (i32.rem_u (i32.sub (local.get $wi) (local.get $len)) (local.get $padlen)))
      (i32.store8 (i32.add (local.get $out) (local.get $wi))
        (i32.load8_u (i32.add (local.get $padptr) (local.get $pi))))
      (local.set $wi (i32.add (local.get $wi) (i32.const 1)))
      (br $lp)
    ))
    (local.get $out)
    (local.get $target)
  )

  ;; ── str_repeat: concatenate the string n times ───────────────────────────────
  (func $__str_repeat
    (param $ptr i32) (param $len i32) (param $n i32)
    (result i32 i32)
    (local $out i32) (local $outlen i32) (local $i i32) (local $j i32)
    (if (i32.le_s (local.get $n) (i32.const 0))
      (then (return (local.get $ptr) (i32.const 0)))
    )
    (local.set $outlen (i32.mul (local.get $len) (local.get $n)))
    (local.set $out (call $__malloc (local.get $outlen)))
    (block $done
      (loop $outer
        (br_if $done (i32.ge_u (local.get $i) (local.get $n)))
        (local.set $j (i32.const 0))
        (block $di (loop $li
          (br_if $di (i32.ge_u (local.get $j) (local.get $len)))
          (i32.store8
            (i32.add (local.get $out) (i32.add (i32.mul (local.get $i) (local.get $len)) (local.get $j)))
            (i32.load8_u (i32.add (local.get $ptr) (local.get $j)))
          )
          (local.set $j (i32.add (local.get $j) (i32.const 1)))
          (br $li)
        ))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $outer)
      )
    )
    (local.get $out)
    (local.get $outlen)
  )

  ;; ── str_split: split string by delimiter, return string-array ptr ────────────
  ;; String array layout: [count i32][capacity i32][{ptr i32, len i32} × count]
  ;; Each element is 8 bytes. The returned i32 is a pointer to this array.
  (func $__str_split
    (param $ptr i32) (param $len i32) (param $dptr i32) (param $dlen i32)
    (result i32)
    (local $arr i32) (local $cap i32) (local $count i32)
    (local $cur i32) (local $pos i32) (local $segptr i32) (local $seglen i32)
    (local $newarr i32) (local $newsz i32)
    ;; initial capacity 8 parts
    (local.set $cap (i32.const 8))
    (local.set $arr (call $__malloc (i32.add (i32.const 8) (i32.mul (local.get $cap) (i32.const 8)))))
    (i32.store (local.get $arr) (i32.const 0))
    (i32.store offset=4 (local.get $arr) (local.get $cap))
    ;; special case: empty delimiter → each char is a part (not implemented; treat as no-split)
    (if (i32.eqz (local.get $dlen))
      (then
        ;; store the whole string as single part
        (i32.store offset=8 (local.get $arr) (local.get $ptr))
        (i32.store offset=12 (local.get $arr) (local.get $len))
        (i32.store (local.get $arr) (i32.const 1))
        (return (local.get $arr))
      )
    )
    (block $done
      (loop $loop
        ;; find next delimiter from $cur
        (local.set $pos (call $__str_indexof
          (i32.add (local.get $ptr) (local.get $cur))
          (i32.sub (local.get $len) (local.get $cur))
          (local.get $dptr) (local.get $dlen)
        ))
        (if (i32.eq (local.get $pos) (i32.const -1))
          (then
            ;; last segment: from $cur to end
            (local.set $segptr (i32.add (local.get $ptr) (local.get $cur)))
            (local.set $seglen (i32.sub (local.get $len) (local.get $cur)))
            (br $done)
          )
        )
        (local.set $pos (i32.add (local.get $pos) (local.get $cur)))
        (local.set $segptr (i32.add (local.get $ptr) (local.get $cur)))
        (local.set $seglen (i32.sub (local.get $pos) (local.get $cur)))
        ;; grow array if full
        (if (i32.ge_u (local.get $count) (local.get $cap))
          (then
            (local.set $cap (i32.mul (local.get $cap) (i32.const 2)))
            (local.set $newsz (i32.add (i32.const 8) (i32.mul (local.get $cap) (i32.const 8))))
            (local.set $newarr (call $__malloc (local.get $newsz)))
            (call $__str_gather (local.get $arr) (i32.add (i32.const 8) (i32.mul (local.get $count) (i32.const 8))) (local.get $newarr))
            (local.set $arr (local.get $newarr))
            (i32.store offset=4 (local.get $arr) (local.get $cap))
          )
        )
        ;; store segment
        (i32.store
          (i32.add (local.get $arr) (i32.add (i32.const 8) (i32.mul (local.get $count) (i32.const 8))))
          (local.get $segptr)
        )
        (i32.store offset=4
          (i32.add (local.get $arr) (i32.add (i32.const 8) (i32.mul (local.get $count) (i32.const 8))))
          (local.get $seglen)
        )
        (local.set $count (i32.add (local.get $count) (i32.const 1)))
        (local.set $cur (i32.add (local.get $pos) (local.get $dlen)))
        (if (i32.gt_u (local.get $cur) (local.get $len)) (then (br $done)))
        (br $loop)
      )
    )
    ;; store last segment
    (if (i32.ge_u (local.get $count) (local.get $cap))
      (then
        (local.set $cap (i32.mul (local.get $cap) (i32.const 2)))
        (local.set $newsz (i32.add (i32.const 8) (i32.mul (local.get $cap) (i32.const 8))))
        (local.set $newarr (call $__malloc (local.get $newsz)))
        (call $__str_gather (local.get $arr) (i32.add (i32.const 8) (i32.mul (local.get $count) (i32.const 8))) (local.get $newarr))
        (local.set $arr (local.get $newarr))
        (i32.store offset=4 (local.get $arr) (local.get $cap))
      )
    )
    (i32.store
      (i32.add (local.get $arr) (i32.add (i32.const 8) (i32.mul (local.get $count) (i32.const 8))))
      (local.get $segptr)
    )
    (i32.store offset=4
      (i32.add (local.get $arr) (i32.add (i32.const 8) (i32.mul (local.get $count) (i32.const 8))))
      (local.get $seglen)
    )
    (local.set $count (i32.add (local.get $count) (i32.const 1)))
    (i32.store (local.get $arr) (local.get $count))
    (local.get $arr)
  )

  ;; ── str_from_codepoint: UTF-8 encode a single code point into a fresh buffer ──
  ;; Returns (ptr, len). Handles the full U+0000..U+10FFFF range (1–4 bytes).
  (func $__str_from_codepoint (param $cp i32) (result i32 i32)
    (local $p i32)
    (local.set $p (call $__malloc (i32.const 4)))
    (if (i32.lt_u (local.get $cp) (i32.const 0x80))
      (then
        (i32.store8 (local.get $p) (local.get $cp))
        (return (local.get $p) (i32.const 1))))
    (if (i32.lt_u (local.get $cp) (i32.const 0x800))
      (then
        (i32.store8 (local.get $p)
          (i32.or (i32.const 0xC0) (i32.shr_u (local.get $cp) (i32.const 6))))
        (i32.store8 offset=1 (local.get $p)
          (i32.or (i32.const 0x80) (i32.and (local.get $cp) (i32.const 0x3F))))
        (return (local.get $p) (i32.const 2))))
    (if (i32.lt_u (local.get $cp) (i32.const 0x10000))
      (then
        (i32.store8 (local.get $p)
          (i32.or (i32.const 0xE0) (i32.shr_u (local.get $cp) (i32.const 12))))
        (i32.store8 offset=1 (local.get $p)
          (i32.or (i32.const 0x80) (i32.and (i32.shr_u (local.get $cp) (i32.const 6)) (i32.const 0x3F))))
        (i32.store8 offset=2 (local.get $p)
          (i32.or (i32.const 0x80) (i32.and (local.get $cp) (i32.const 0x3F))))
        (return (local.get $p) (i32.const 3))))
    (i32.store8 (local.get $p)
      (i32.or (i32.const 0xF0) (i32.shr_u (local.get $cp) (i32.const 18))))
    (i32.store8 offset=1 (local.get $p)
      (i32.or (i32.const 0x80) (i32.and (i32.shr_u (local.get $cp) (i32.const 12)) (i32.const 0x3F))))
    (i32.store8 offset=2 (local.get $p)
      (i32.or (i32.const 0x80) (i32.and (i32.shr_u (local.get $cp) (i32.const 6)) (i32.const 0x3F))))
    (i32.store8 offset=3 (local.get $p)
      (i32.or (i32.const 0x80) (i32.and (local.get $cp) (i32.const 0x3F))))
    (local.get $p) (i32.const 4)
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
        (local.set $arr (call $__dynarr_grow_i32 (local.get $arr) (i32.shl (local.get $cap) (i32.const 1))))
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
  (func $mkNull  (result i32)
    (local $n i32)
    (local.set $n (call $__malloc (i32.const 24)))
      (i32.store (local.get $n) (i32.const 4))
    (i32.store (i32.add (i32.add (local.get $n) (i32.const 8)) (i32.shl (i32.const 0) (i32.const 2))) (i32.const 0))
    (return (local.get $n))
  )

  (func $mkBool (param $b i32) (result i32)
    (local $n i32)
    (local.set $n (call $__malloc (i32.const 24)))
      (i32.store (local.get $n) (i32.const 4))
    (i32.store (i32.add (i32.add (local.get $n) (i32.const 8)) (i32.shl (i32.const 0) (i32.const 2))) (i32.const 1))
    (i32.store (i32.add (i32.add (local.get $n) (i32.const 8)) (i32.shl (i32.const 1) (i32.const 2))) (local.get $b))
    (return (local.get $n))
  )

  (func $skipWs (param $s_ptr i32) (param $s_len i32) 
    (local $go i32)
    (local $c i32)
    (local $__iface_tmp i32)
    (local.set $go (i32.const 1))
    (block $break_0
      (loop $loop_0
        (br_if $break_0 (i32.eqz (i32.eq (local.get $go) (i32.const 1))))
        (block $cont_0
          (if (i32.ge_s (global.get $pos) (local.get $s_len))
            (then
            (local.set $go (i32.const 0))
            )
            (else
            (local.set $c (call $__str_char_code_at (local.get $s_ptr) (local.get $s_len) (global.get $pos)))
            (if (if (result i32) (if (result i32) (if (result i32) (i32.eq (local.get $c) (i32.const 32)) (then (i32.const 1)) (else (i32.eq (local.get $c) (i32.const 9)))) (then (i32.const 1)) (else (i32.eq (local.get $c) (i32.const 10)))) (then (i32.const 1)) (else (i32.eq (local.get $c) (i32.const 13))))
              (then
              (global.set $pos (i32.add (global.get $pos) (i32.const 1)))
              )
              (else
              (local.set $go (i32.const 0))
              )
            )
            )
          )
        )
        (br $loop_0)
      )
    )
  )

  (func $parseStringRaw (param $s_ptr i32) (param $s_len i32) (result i32)
    (local $contentStart i32)
    (local $scan i32)
    (local $c i32)
    (local $endPos i32)
    (local $rawLen i32)
    (local $buf i32)
    (local $j i32)
    (local $k i32)
    (local $e i32)
    (local $__iface_tmp i32)
    (global.set $pos (i32.add (global.get $pos) (i32.const 1)))
    (local.set $contentStart (global.get $pos))
    (local.set $scan (i32.const 1))
    (block $break_1
      (loop $loop_1
        (br_if $break_1 (i32.eqz (i32.eq (local.get $scan) (i32.const 1))))
        (block $cont_1
          (if (i32.ge_s (global.get $pos) (local.get $s_len))
            (then
            (local.set $scan (i32.const 0))
            )
            (else
            (local.set $c (call $__str_char_code_at (local.get $s_ptr) (local.get $s_len) (global.get $pos)))
            (if (i32.eq (local.get $c) (i32.const 92))
              (then
              (global.set $pos (i32.add (global.get $pos) (i32.const 2)))
              )
              (else
              (if (i32.eq (local.get $c) (i32.const 34))
                (then
                (local.set $scan (i32.const 0))
                )
                (else
                (global.set $pos (i32.add (global.get $pos) (i32.const 1)))
                )
              )
              )
            )
            )
          )
        )
        (br $loop_1)
      )
    )
    (local.set $endPos (global.get $pos))
    (local.set $rawLen (i32.sub (local.get $endPos) (local.get $contentStart)))
    (local.set $buf (call $__malloc (i32.add (i32.const 8) (local.get $rawLen))))
      (i32.store (local.get $buf) (local.get $rawLen))
    (local.set $j (i32.const 0))
    (local.set $k (local.get $contentStart))
    (block $break_2
      (loop $loop_2
        (br_if $break_2 (i32.eqz (i32.lt_s (local.get $k) (local.get $endPos))))
        (block $cont_2
          (local.set $c (call $__str_char_code_at (local.get $s_ptr) (local.get $s_len) (local.get $k)))
          (if (i32.eq (local.get $c) (i32.const 92))
            (then
            (local.set $k (i32.add (local.get $k) (i32.const 1)))
            (local.set $e (call $__str_char_code_at (local.get $s_ptr) (local.get $s_len) (local.get $k)))
            (if (i32.eq (local.get $e) (i32.const 110))
              (then
              (local.set $c (i32.const 10))
              )
              (else
              (if (i32.eq (local.get $e) (i32.const 116))
                (then
                (local.set $c (i32.const 9))
                )
                (else
                (if (i32.eq (local.get $e) (i32.const 114))
                  (then
                  (local.set $c (i32.const 13))
                  )
                  (else
                  (if (i32.eq (local.get $e) (i32.const 98))
                    (then
                    (local.set $c (i32.const 8))
                    )
                    (else
                    (if (i32.eq (local.get $e) (i32.const 102))
                      (then
                      (local.set $c (i32.const 12))
                      )
                      (else
                      (if (i32.eq (local.get $e) (i32.const 34))
                        (then
                        (local.set $c (i32.const 34))
                        )
                        (else
                        (if (i32.eq (local.get $e) (i32.const 92))
                          (then
                          (local.set $c (i32.const 92))
                          )
                          (else
                          (if (i32.eq (local.get $e) (i32.const 47))
                            (then
                            (local.set $c (i32.const 47))
                            )
                            (else
                            (local.set $c (local.get $e))
                            )
                          )
                          )
                        )
                        )
                      )
                      )
                    )
                    )
                  )
                  )
                )
                )
              )
              )
            )
            )
          )
          (i32.store8 (i32.add (i32.add (local.get $buf) (i32.const 8)) (local.get $j)) (local.get $c))
          (local.set $j (i32.add (local.get $j) (i32.const 1)))
          (local.set $k (i32.add (local.get $k) (i32.const 1)))
        )
        (br $loop_2)
      )
    )
    (global.set $pos (i32.add (local.get $endPos) (i32.const 1)))
    (global.set $lastLen (local.get $j))
    (return (local.get $buf))
  )

  (func $parseString (param $s_ptr i32) (param $s_len i32) (result i32)
    (local $ptr i32)
    (local $n i32)
    (local.set $ptr (call $parseStringRaw (local.get $s_ptr) (local.get $s_len)))
    (local.set $n (call $__malloc (i32.const 24)))
      (i32.store (local.get $n) (i32.const 4))
    (i32.store (i32.add (i32.add (local.get $n) (i32.const 8)) (i32.shl (i32.const 0) (i32.const 2))) (i32.const 3))
    (i32.store (i32.add (i32.add (local.get $n) (i32.const 8)) (i32.shl (i32.const 1) (i32.const 2))) (local.get $ptr))
    (i32.store (i32.add (i32.add (local.get $n) (i32.const 8)) (i32.shl (i32.const 2) (i32.const 2))) (global.get $lastLen))
    (return (local.get $n))
  )

  (func $parseNumber (param $s_ptr i32) (param $s_len i32) (result i32)
    (local $neg i32)
    (local $val i32)
    (local $go i32)
    (local $c i32)
    (local $gf i32)
    (local $c2 i32)
    (local $ec i32)
    (local $sgn i32)
    (local $ge i32)
    (local $c3 i32)
    (local $n i32)
    (local $__iface_tmp i32)
    (local.set $neg (i32.const 0))
    (if (i32.eq (call $__str_char_code_at (local.get $s_ptr) (local.get $s_len) (global.get $pos)) (i32.const 45))
      (then
      (local.set $neg (i32.const 1))
      (global.set $pos (i32.add (global.get $pos) (i32.const 1)))
      )
    )
    (local.set $val (i32.const 0))
    (local.set $go (i32.const 1))
    (block $break_3
      (loop $loop_3
        (br_if $break_3 (i32.eqz (i32.eq (local.get $go) (i32.const 1))))
        (block $cont_3
          (if (i32.ge_s (global.get $pos) (local.get $s_len))
            (then
            (local.set $go (i32.const 0))
            )
            (else
            (local.set $c (call $__str_char_code_at (local.get $s_ptr) (local.get $s_len) (global.get $pos)))
            (if (if (result i32) (i32.lt_s (local.get $c) (i32.const 48)) (then (i32.const 1)) (else (i32.gt_s (local.get $c) (i32.const 57))))
              (then
              (local.set $go (i32.const 0))
              )
              (else
              (local.set $val (i32.add (i32.mul (local.get $val) (i32.const 10)) (i32.sub (local.get $c) (i32.const 48))))
              (global.set $pos (i32.add (global.get $pos) (i32.const 1)))
              )
            )
            )
          )
        )
        (br $loop_3)
      )
    )
    (if (if (result i32) (i32.lt_s (global.get $pos) (local.get $s_len)) (then (i32.eq (call $__str_char_code_at (local.get $s_ptr) (local.get $s_len) (global.get $pos)) (i32.const 46))) (else (i32.const 0)))
      (then
      (global.set $pos (i32.add (global.get $pos) (i32.const 1)))
      (local.set $gf (i32.const 1))
      (block $break_4
        (loop $loop_4
          (br_if $break_4 (i32.eqz (i32.eq (local.get $gf) (i32.const 1))))
          (block $cont_4
            (if (i32.ge_s (global.get $pos) (local.get $s_len))
              (then
              (local.set $gf (i32.const 0))
              )
              (else
              (local.set $c2 (call $__str_char_code_at (local.get $s_ptr) (local.get $s_len) (global.get $pos)))
              (if (if (result i32) (i32.lt_s (local.get $c2) (i32.const 48)) (then (i32.const 1)) (else (i32.gt_s (local.get $c2) (i32.const 57))))
                (then
                (local.set $gf (i32.const 0))
                )
                (else
                (global.set $pos (i32.add (global.get $pos) (i32.const 1)))
                )
              )
              )
            )
          )
          (br $loop_4)
        )
      )
      )
    )
    (if (i32.lt_s (global.get $pos) (local.get $s_len))
      (then
      (local.set $ec (call $__str_char_code_at (local.get $s_ptr) (local.get $s_len) (global.get $pos)))
      (if (if (result i32) (i32.eq (local.get $ec) (i32.const 101)) (then (i32.const 1)) (else (i32.eq (local.get $ec) (i32.const 69))))
        (then
        (global.set $pos (i32.add (global.get $pos) (i32.const 1)))
        (if (i32.lt_s (global.get $pos) (local.get $s_len))
          (then
          (local.set $sgn (call $__str_char_code_at (local.get $s_ptr) (local.get $s_len) (global.get $pos)))
          (if (if (result i32) (i32.eq (local.get $sgn) (i32.const 43)) (then (i32.const 1)) (else (i32.eq (local.get $sgn) (i32.const 45))))
            (then
            (global.set $pos (i32.add (global.get $pos) (i32.const 1)))
            )
          )
          )
        )
        (local.set $ge (i32.const 1))
        (block $break_5
          (loop $loop_5
            (br_if $break_5 (i32.eqz (i32.eq (local.get $ge) (i32.const 1))))
            (block $cont_5
              (if (i32.ge_s (global.get $pos) (local.get $s_len))
                (then
                (local.set $ge (i32.const 0))
                )
                (else
                (local.set $c3 (call $__str_char_code_at (local.get $s_ptr) (local.get $s_len) (global.get $pos)))
                (if (if (result i32) (i32.lt_s (local.get $c3) (i32.const 48)) (then (i32.const 1)) (else (i32.gt_s (local.get $c3) (i32.const 57))))
                  (then
                  (local.set $ge (i32.const 0))
                  )
                  (else
                  (global.set $pos (i32.add (global.get $pos) (i32.const 1)))
                  )
                )
                )
              )
            )
            (br $loop_5)
          )
        )
        )
      )
      )
    )
    (if (i32.eq (local.get $neg) (i32.const 1))
      (then
      (local.set $val (i32.sub (i32.const 0) (local.get $val)))
      )
    )
    (local.set $n (call $__malloc (i32.const 24)))
      (i32.store (local.get $n) (i32.const 4))
    (i32.store (i32.add (i32.add (local.get $n) (i32.const 8)) (i32.shl (i32.const 0) (i32.const 2))) (i32.const 2))
    (i32.store (i32.add (i32.add (local.get $n) (i32.const 8)) (i32.shl (i32.const 1) (i32.const 2))) (local.get $val))
    (return (local.get $n))
  )

  (func $parseArray (param $s_ptr i32) (param $s_len i32) (result i32)
    (local $elems i32)
    (local $done i32)
    (local $child i32)
    (local $c i32)
    (local $ePtr i32)
    (local $n i32)
    (local $__iface_tmp i32)
    (global.set $pos (i32.add (global.get $pos) (i32.const 1)))
    (local.set $elems (call $__malloc (i32.const 40)))
      (i32.store (local.get $elems) (i32.const 0))
      (i32.store offset=4 (local.get $elems) (i32.const 8))
    (call $skipWs (local.get $s_ptr) (local.get $s_len))
    (if (i32.eq (call $__str_char_code_at (local.get $s_ptr) (local.get $s_len) (global.get $pos)) (i32.const 93))
      (then
      (global.set $pos (i32.add (global.get $pos) (i32.const 1)))
      )
      (else
      (local.set $done (i32.const 0))
      (block $break_6
        (loop $loop_6
          (br_if $break_6 (i32.eqz (i32.eq (local.get $done) (i32.const 0))))
          (block $cont_6
            (call $skipWs (local.get $s_ptr) (local.get $s_len))
            (local.set $child (call $parseValue (local.get $s_ptr) (local.get $s_len)))
            (local.set $elems (call $__dynarr_push_i32 (local.get $elems) (local.get $child)))
            (call $skipWs (local.get $s_ptr) (local.get $s_len))
            (local.set $c (call $__str_char_code_at (local.get $s_ptr) (local.get $s_len) (global.get $pos)))
            (if (i32.eq (local.get $c) (i32.const 44))
              (then
              (global.set $pos (i32.add (global.get $pos) (i32.const 1)))
              )
              (else
              (if (i32.eq (local.get $c) (i32.const 93))
                (then
                (global.set $pos (i32.add (global.get $pos) (i32.const 1)))
                )
              )
              (local.set $done (i32.const 1))
              )
            )
          )
          (br $loop_6)
        )
      )
      )
    )
    (local.set $ePtr (local.get $elems))
    (local.set $n (call $__malloc (i32.const 24)))
      (i32.store (local.get $n) (i32.const 4))
    (i32.store (i32.add (i32.add (local.get $n) (i32.const 8)) (i32.shl (i32.const 0) (i32.const 2))) (i32.const 4))
    (i32.store (i32.add (i32.add (local.get $n) (i32.const 8)) (i32.shl (i32.const 1) (i32.const 2))) (local.get $ePtr))
    (i32.store (i32.add (i32.add (local.get $n) (i32.const 8)) (i32.shl (i32.const 2) (i32.const 2))) (i32.load (local.get $elems)))
    (return (local.get $n))
  )

  (func $parseObject (param $s_ptr i32) (param $s_len i32) (result i32)
    (local $vals i32)
    (local $keys i32)
    (local $done i32)
    (local $kptr i32)
    (local $klen i32)
    (local $v i32)
    (local $c i32)
    (local $vPtr i32)
    (local $kPtr i32)
    (local $n i32)
    (local $__iface_tmp i32)
    (global.set $pos (i32.add (global.get $pos) (i32.const 1)))
    (local.set $vals (call $__malloc (i32.const 40)))
      (i32.store (local.get $vals) (i32.const 0))
      (i32.store offset=4 (local.get $vals) (i32.const 8))
    (local.set $keys (call $__malloc (i32.const 40)))
      (i32.store (local.get $keys) (i32.const 0))
      (i32.store offset=4 (local.get $keys) (i32.const 8))
    (call $skipWs (local.get $s_ptr) (local.get $s_len))
    (if (i32.eq (call $__str_char_code_at (local.get $s_ptr) (local.get $s_len) (global.get $pos)) (i32.const 125))
      (then
      (global.set $pos (i32.add (global.get $pos) (i32.const 1)))
      )
      (else
      (local.set $done (i32.const 0))
      (block $break_7
        (loop $loop_7
          (br_if $break_7 (i32.eqz (i32.eq (local.get $done) (i32.const 0))))
          (block $cont_7
            (call $skipWs (local.get $s_ptr) (local.get $s_len))
            (local.set $kptr (call $parseStringRaw (local.get $s_ptr) (local.get $s_len)))
            (local.set $klen (global.get $lastLen))
            (local.set $keys (call $__dynarr_push_i32 (local.get $keys) (local.get $kptr)))
            (local.set $keys (call $__dynarr_push_i32 (local.get $keys) (local.get $klen)))
            (call $skipWs (local.get $s_ptr) (local.get $s_len))
            (if (i32.eq (call $__str_char_code_at (local.get $s_ptr) (local.get $s_len) (global.get $pos)) (i32.const 58))
              (then
              (global.set $pos (i32.add (global.get $pos) (i32.const 1)))
              )
            )
            (call $skipWs (local.get $s_ptr) (local.get $s_len))
            (local.set $v (call $parseValue (local.get $s_ptr) (local.get $s_len)))
            (local.set $vals (call $__dynarr_push_i32 (local.get $vals) (local.get $v)))
            (call $skipWs (local.get $s_ptr) (local.get $s_len))
            (local.set $c (call $__str_char_code_at (local.get $s_ptr) (local.get $s_len) (global.get $pos)))
            (if (i32.eq (local.get $c) (i32.const 44))
              (then
              (global.set $pos (i32.add (global.get $pos) (i32.const 1)))
              )
              (else
              (if (i32.eq (local.get $c) (i32.const 125))
                (then
                (global.set $pos (i32.add (global.get $pos) (i32.const 1)))
                )
              )
              (local.set $done (i32.const 1))
              )
            )
          )
          (br $loop_7)
        )
      )
      )
    )
    (local.set $vPtr (local.get $vals))
    (local.set $kPtr (local.get $keys))
    (local.set $n (call $__malloc (i32.const 24)))
      (i32.store (local.get $n) (i32.const 4))
    (i32.store (i32.add (i32.add (local.get $n) (i32.const 8)) (i32.shl (i32.const 0) (i32.const 2))) (i32.const 5))
    (i32.store (i32.add (i32.add (local.get $n) (i32.const 8)) (i32.shl (i32.const 1) (i32.const 2))) (local.get $vPtr))
    (i32.store (i32.add (i32.add (local.get $n) (i32.const 8)) (i32.shl (i32.const 2) (i32.const 2))) (i32.load (local.get $vals)))
    (i32.store (i32.add (i32.add (local.get $n) (i32.const 8)) (i32.shl (i32.const 3) (i32.const 2))) (local.get $kPtr))
    (return (local.get $n))
  )

  (func $parseValue (param $s_ptr i32) (param $s_len i32) (result i32)
    (local $c i32)
    (local $__iface_tmp i32)
    (call $skipWs (local.get $s_ptr) (local.get $s_len))
    (local.set $c (call $__str_char_code_at (local.get $s_ptr) (local.get $s_len) (global.get $pos)))
    (if (i32.eq (local.get $c) (i32.const 123))
      (then
      (return (call $parseObject (local.get $s_ptr) (local.get $s_len)))
      )
    )
    (if (i32.eq (local.get $c) (i32.const 91))
      (then
      (return (call $parseArray (local.get $s_ptr) (local.get $s_len)))
      )
    )
    (if (i32.eq (local.get $c) (i32.const 34))
      (then
      (return (call $parseString (local.get $s_ptr) (local.get $s_len)))
      )
    )
    (if (i32.eq (local.get $c) (i32.const 116))
      (then
      (global.set $pos (i32.add (global.get $pos) (i32.const 4)))
      (return (call $mkBool (i32.const 1)))
      )
    )
    (if (i32.eq (local.get $c) (i32.const 102))
      (then
      (global.set $pos (i32.add (global.get $pos) (i32.const 5)))
      (return (call $mkBool (i32.const 0)))
      )
    )
    (if (i32.eq (local.get $c) (i32.const 110))
      (then
      (global.set $pos (i32.add (global.get $pos) (i32.const 4)))
      (return (call $mkNull ))
      )
    )
    (return (call $parseNumber (local.get $s_ptr) (local.get $s_len)))
  )

  (func $jsonParse (export "jsonParse") (param $s_ptr i32) (param $s_len i32) (result i32)
    (global.set $pos (i32.const 0))
    (return (call $parseValue (local.get $s_ptr) (local.get $s_len)))
  )

  (func $jsonType (export "jsonType") (param $node i32) (result i32)
    (local $n i32)
    (local.set $n (local.get $node))
    (return (i32.load (i32.add (i32.add (local.get $n) (i32.const 8)) (i32.shl (i32.const 0) (i32.const 2)))))
  )

  (func $jsonInt (export "jsonInt") (param $node i32) (result i32)
    (local $n i32)
    (local.set $n (local.get $node))
    (return (i32.load (i32.add (i32.add (local.get $n) (i32.const 8)) (i32.shl (i32.const 1) (i32.const 2)))))
  )

  (func $jsonBool (export "jsonBool") (param $node i32) (result i32)
    (local $n i32)
    (local.set $n (local.get $node))
    (return (i32.load (i32.add (i32.add (local.get $n) (i32.const 8)) (i32.shl (i32.const 1) (i32.const 2)))))
  )

  (func $jsonArrayLen (export "jsonArrayLen") (param $node i32) (result i32)
    (local $n i32)
    (local $p i32)
    (local $a i32)
    (local.set $n (local.get $node))
    (local.set $p (i32.load (i32.add (i32.add (local.get $n) (i32.const 8)) (i32.shl (i32.const 1) (i32.const 2)))))
    (local.set $a (local.get $p))
    (return (i32.load (local.get $a)))
  )

  (func $jsonArrayGet (export "jsonArrayGet") (param $node i32) (param $i i32) (result i32)
    (local $n i32)
    (local $p i32)
    (local $a i32)
    (local.set $n (local.get $node))
    (local.set $p (i32.load (i32.add (i32.add (local.get $n) (i32.const 8)) (i32.shl (i32.const 1) (i32.const 2)))))
    (local.set $a (local.get $p))
    (return (i32.load (i32.add (i32.add (local.get $a) (i32.const 8)) (i32.shl (local.get $i) (i32.const 2)))))
  )

  (func $jsonObjectLen (export "jsonObjectLen") (param $node i32) (result i32)
    (local $n i32)
    (local.set $n (local.get $node))
    (return (i32.load (i32.add (i32.add (local.get $n) (i32.const 8)) (i32.shl (i32.const 2) (i32.const 2)))))
  )

  (func $jsonStrLen (export "jsonStrLen") (param $node i32) (result i32)
    (local $n i32)
    (local.set $n (local.get $node))
    (return (i32.load (i32.add (i32.add (local.get $n) (i32.const 8)) (i32.shl (i32.const 2) (i32.const 2)))))
  )

  (func $jsonStrCharAt (export "jsonStrCharAt") (param $node i32) (param $i i32) (result i32)
    (local $n i32)
    (local $p i32)
    (local $v i32)
    (local.set $n (local.get $node))
    (local.set $p (i32.load (i32.add (i32.add (local.get $n) (i32.const 8)) (i32.shl (i32.const 1) (i32.const 2)))))
    (local.set $v (local.get $p))
    (return (i32.load8_u (i32.add (i32.add (local.get $v) (i32.const 8)) (local.get $i))))
  )

  (func $jsonStrEq (export "jsonStrEq") (param $node i32) (param $t_ptr i32) (param $t_len i32) (result i32)
    (local $n i32)
    (local $len i32)
    (local $p i32)
    (local $v i32)
    (local $i i32)
    (local $__iface_tmp i32)
    (local.set $n (local.get $node))
    (if (i32.ne (i32.load (i32.add (i32.add (local.get $n) (i32.const 8)) (i32.shl (i32.const 0) (i32.const 2)))) (i32.const 3))
      (then
      (return (i32.const 0))
      )
    )
    (local.set $len (i32.load (i32.add (i32.add (local.get $n) (i32.const 8)) (i32.shl (i32.const 2) (i32.const 2)))))
    (if (i32.ne (local.get $len) (local.get $t_len))
      (then
      (return (i32.const 0))
      )
    )
    (local.set $p (i32.load (i32.add (i32.add (local.get $n) (i32.const 8)) (i32.shl (i32.const 1) (i32.const 2)))))
    (local.set $v (local.get $p))
    (local.set $i (i32.const 0))
    (block $break_8
      (loop $loop_8
        (br_if $break_8 (i32.eqz (i32.lt_s (local.get $i) (local.get $len))))
        (block $cont_8
          (if (i32.ne (i32.load8_u (i32.add (i32.add (local.get $v) (i32.const 8)) (local.get $i))) (call $__str_char_code_at (local.get $t_ptr) (local.get $t_len) (local.get $i)))
            (then
            (return (i32.const 0))
            )
          )
          (local.set $i (i32.add (local.get $i) (i32.const 1)))
        )
        (br $loop_8)
      )
    )
    (return (i32.const 1))
  )

  (func $jsonGet (export "jsonGet") (param $node i32) (param $key_ptr i32) (param $key_len i32) (result i32)
    (local $n i32)
    (local $count i32)
    (local $vp i32)
    (local $kp i32)
    (local $vals i32)
    (local $keys i32)
    (local $klen i32)
    (local $i i32)
    (local $kptr i32)
    (local $kl i32)
    (local $kv i32)
    (local $eq i32)
    (local $j i32)
    (local $__iface_tmp i32)
    (local.set $n (local.get $node))
    (if (i32.ne (i32.load (i32.add (i32.add (local.get $n) (i32.const 8)) (i32.shl (i32.const 0) (i32.const 2)))) (i32.const 5))
      (then
      (return (i32.const -1))
      )
    )
    (local.set $count (i32.load (i32.add (i32.add (local.get $n) (i32.const 8)) (i32.shl (i32.const 2) (i32.const 2)))))
    (local.set $vp (i32.load (i32.add (i32.add (local.get $n) (i32.const 8)) (i32.shl (i32.const 1) (i32.const 2)))))
    (local.set $kp (i32.load (i32.add (i32.add (local.get $n) (i32.const 8)) (i32.shl (i32.const 3) (i32.const 2)))))
    (local.set $vals (local.get $vp))
    (local.set $keys (local.get $kp))
    (local.set $klen (local.get $key_len))
    (local.set $i (i32.const 0))
    (block $break_9
      (loop $loop_9
        (br_if $break_9 (i32.eqz (i32.lt_s (local.get $i) (local.get $count))))
        (block $cont_9
          (local.set $kptr (i32.load (i32.add (i32.add (local.get $keys) (i32.const 8)) (i32.shl (i32.mul (local.get $i) (i32.const 2)) (i32.const 2)))))
          (local.set $kl (i32.load (i32.add (i32.add (local.get $keys) (i32.const 8)) (i32.shl (i32.add (i32.mul (local.get $i) (i32.const 2)) (i32.const 1)) (i32.const 2)))))
          (if (i32.eq (local.get $kl) (local.get $klen))
            (then
            (local.set $kv (local.get $kptr))
            (local.set $eq (i32.const 1))
            (local.set $j (i32.const 0))
            (block $break_10
              (loop $loop_10
                (br_if $break_10 (i32.eqz (i32.lt_s (local.get $j) (local.get $kl))))
                (block $cont_10
                  (if (i32.ne (i32.load8_u (i32.add (i32.add (local.get $kv) (i32.const 8)) (local.get $j))) (call $__str_char_code_at (local.get $key_ptr) (local.get $key_len) (local.get $j)))
                    (then
                    (local.set $eq (i32.const 0))
                    (local.set $j (local.get $kl))
                    )
                    (else
                    (local.set $j (i32.add (local.get $j) (i32.const 1)))
                    )
                  )
                )
                (br $loop_10)
              )
            )
            (if (i32.eq (local.get $eq) (i32.const 1))
              (then
              (return (i32.load (i32.add (i32.add (local.get $vals) (i32.const 8)) (i32.shl (local.get $i) (i32.const 2)))))
              )
            )
            )
          )
          (local.set $i (i32.add (local.get $i) (i32.const 1)))
        )
        (br $loop_9)
      )
    )
    (return (i32.const -1))
  )

  (func $jsonHas (export "jsonHas") (param $node i32) (param $key_ptr i32) (param $key_len i32) (result i32)
    (return (if (result i32) (i32.eq (call $jsonGet (local.get $node) (local.get $key_ptr) (local.get $key_len)) (i32.const -1)) (then (i32.const 0)) (else (i32.const 1))))
  )
  (export "cabi_realloc" (func $cabi_realloc))
)