(module
  (import "wasi_snapshot_preview1" "proc_exit" (func $proc_exit (param i32)))
  (import "wasi_snapshot_preview1" "fd_write" (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (memory (export "memory") 2)
  (global $__heap_ptr (mut i32) (i32.const 260))
  (type $ftype_i32_i32_r_i32 (func (param i32) (param i32) (result i32)))
  ;; Bump allocator — advances __heap_ptr and returns the old value
  (func $__malloc (param $size i32) (result i32)
    (local $ptr i32)
    (local.set $ptr (global.get $__heap_ptr))
    (global.set $__heap_ptr (i32.add (local.get $ptr) (local.get $size)))
    (local.get $ptr)
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
  ;; Outputs the integer part plus up to 6 significant decimal digits.
  ;; Values outside [-2147483648, 2147483647] for the integer part are clamped.
  (func $__f64_to_str (param $val f64) (param $buf i32) (result i32)
    (local $len i32)
    (local $ipart i32)
    (local $fpart i64)
    (local $flen i32)
    (local $fdigits i32)
    (local $ptr i32)
    (local $zeros i32)
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
    ;; Fractional part: multiply remainder by 1 000 000, take integer
    (local.set $fpart
      (i64.trunc_f64_s
        (f64.mul
          (f64.sub (local.get $val) (f64.convert_i32_s (local.get $ipart)))
          (f64.const 1000000)
        )
      )
    )
    (if (i64.ne (local.get $fpart) (i64.const 0))
      (then
        ;; Decimal point
        (i32.store8 (local.get $ptr) (i32.const 46))
        (local.set $ptr (i32.add (local.get $ptr) (i32.const 1)))
        ;; Write 6-digit fractional string then strip trailing zeros
        (local.set $fdigits (i32.wrap_i64 (local.get $fpart)))
        ;; Write fractional digits in reverse into a 6-byte window
        (local.set $flen (i32.const 6))
        (block $fdone
          (loop $floop
            (br_if $fdone (i32.eqz (local.get $flen)))
            (i32.store8
              (i32.add (local.get $ptr) (i32.sub (local.get $flen) (i32.const 1)))
              (i32.add (i32.const 48) (i32.rem_u (local.get $fdigits) (i32.const 10)))
            )
            (local.set $fdigits (i32.div_u (local.get $fdigits) (i32.const 10)))
            (local.set $flen (i32.sub (local.get $flen) (i32.const 1)))
            (br $floop)
          )
        )
        ;; Count non-zero trailing digits to strip
        (local.set $flen (i32.const 6))
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
  (func $testClosurePassing (export "testClosurePassing") (param $initialMultiplier i32) (result i32)
    (local $baseScaler i32)
    (local $doubleScaler i32)
    (local.set $baseScaler (call $__anon_0__factory (local.get $initialMultiplier)))
    (local.set $doubleScaler (call $createDoubleScaler (local.get $baseScaler)))
    (return (call_indirect (type $ftype_i32_i32_r_i32) (local.get $doubleScaler) (i32.const 10) (i32.load (local.get $doubleScaler))))
  )

  (func $createDoubleScaler__inner (param $val i32) (param $original i32) (result i32)
    (return (i32.mul (call_indirect (type $ftype_i32_i32_r_i32) (local.get $original) (local.get $val) (i32.load (local.get $original))) (i32.const 2)))
  )

  (func $createDoubleScaler (param $original i32) (result i32)
    (local $__closure_ptr i32)
    (local.set $__closure_ptr (call $__malloc (i32.const 8)))
    (i32.store (local.get $__closure_ptr) (i32.const 0))
    (i32.store offset=4 (local.get $__closure_ptr) (local.get $original))
    (local.get $__closure_ptr)
  )

  (func $createDoubleScaler__trampoline (param $__closure_ptr i32) (param $val i32) (result i32)
    (local $__cap_original i32)
    (local.set $__cap_original (i32.load offset=4 (local.get $__closure_ptr)))
    (call $createDoubleScaler__inner (local.get $val) (local.get $__cap_original))
  )

  (func $__anon_0 (param $n i32) (param $initialMultiplier i32) (result i32)
    (return (i32.mul (local.get $n) (local.get $initialMultiplier)))
  )

  (func $__anon_0__factory (param $initialMultiplier i32) (result i32)
    (local $__closure_ptr i32)
    (local.set $__closure_ptr (call $__malloc (i32.const 8)))
    (i32.store (local.get $__closure_ptr) (i32.const 1))
    (i32.store offset=4 (local.get $__closure_ptr) (local.get $initialMultiplier))
    (local.get $__closure_ptr)
  )

  (func $__anon_0__factory__trampoline (param $__closure_ptr i32) (param $n i32) (result i32)
    (local $__cap_initialMultiplier i32)
    (local.set $__cap_initialMultiplier (i32.load offset=4 (local.get $__closure_ptr)))
    (call $__anon_0 (local.get $n) (local.get $__cap_initialMultiplier))
  )
  (func $_start (export "_start")
        (i32.store (i32.const 0) (i32.const 132))
          (i32.store (i32.const 4) (call $__i32_to_str (call $testClosurePassing (i32.const 5)) (i32.const 132)))
          (i32.store8 (i32.add (i32.const 132) (i32.load (i32.const 4))) (i32.const 10))
          (i32.store (i32.const 4) (i32.add (i32.load (i32.const 4)) (i32.const 1)))
          (drop (call $fd_write
            (i32.const 1)
            (i32.const 0)
            (i32.const 1)
            (i32.const 128)))
    (call $proc_exit (i32.const 0))
  )
  (table 2 funcref)
  (elem (i32.const 0) $createDoubleScaler__trampoline $__anon_0__factory__trampoline)
)