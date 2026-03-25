(module
  (import "wasi_snapshot_preview1" "proc_exit" (func $proc_exit (param i32)))
  (import "wasi_snapshot_preview1" "fd_write" (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (memory (export "memory") 1)

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
  (func $add (param $a f64) (param $b f64) (result f64)
    (return (f64.add (local.get $a) (local.get $b)))
  )

  (func $multiply (param $a f64) (param $b f64) (result f64)
    (return (f64.mul (local.get $a) (local.get $b)))
  )

  (func $divide (param $a f64) (param $b f64) (result f64)
    (return (f64.div (local.get $a) (local.get $b)))
  )

  (func $subtract (param $a f64) (param $b f64) (result f64)
    (return (f64.sub (local.get $a) (local.get $b)))
  )

  (func $main  
        (i32.store (i32.const 0) (i32.const 260))
          (i32.store (i32.const 4) (i32.const 5))
          (i32.store (i32.const 8) (i32.const 132))
          (i32.store (i32.const 12) (call $__f64_to_str (call $add (f64.const 5) (f64.const 6)) (i32.const 132)))
          (i32.store (i32.const 16) (i32.const 265))
          (i32.store (i32.const 20) (i32.const 1))
          (drop (call $fd_write
            (i32.const 1)
            (i32.const 0)
            (i32.const 3)
            (i32.const 128)))
        (i32.store (i32.const 0) (i32.const 266))
          (i32.store (i32.const 4) (i32.const 9))
          (i32.store (i32.const 8) (i32.const 132))
          (i32.store (i32.const 12) (call $__f64_to_str (call $multiply (f64.const 4) (f64.const 5)) (i32.const 132)))
          (i32.store (i32.const 16) (i32.const 265))
          (i32.store (i32.const 20) (i32.const 1))
          (drop (call $fd_write
            (i32.const 1)
            (i32.const 0)
            (i32.const 3)
            (i32.const 128)))
        (i32.store (i32.const 0) (i32.const 275))
          (i32.store (i32.const 4) (i32.const 10))
          (i32.store (i32.const 8) (i32.const 132))
          (i32.store (i32.const 12) (call $__f64_to_str (call $divide (f64.const 30) (f64.const 2)) (i32.const 132)))
          (i32.store (i32.const 16) (i32.const 265))
          (i32.store (i32.const 20) (i32.const 1))
          (drop (call $fd_write
            (i32.const 1)
            (i32.const 0)
            (i32.const 3)
            (i32.const 128)))
        (i32.store (i32.const 0) (i32.const 285))
          (i32.store (i32.const 4) (i32.const 12))
          (i32.store (i32.const 8) (i32.const 132))
          (i32.store (i32.const 12) (call $__f64_to_str (call $subtract (f64.const 20) (f64.const 3)) (i32.const 132)))
          (i32.store (i32.const 16) (i32.const 265))
          (i32.store (i32.const 20) (i32.const 1))
          (drop (call $fd_write
            (i32.const 1)
            (i32.const 0)
            (i32.const 3)
            (i32.const 128)))
  )
  (func $_start (export "_start")
    (call $main)
    (call $proc_exit (i32.const 0))
  )
  (data (i32.const 260) "\53\75\6d\3a\20")
  (data (i32.const 265) "\0a")
  (data (i32.const 266) "\50\72\6f\64\75\63\74\3a\20")
  (data (i32.const 275) "\51\75\6f\74\69\65\6e\74\3a\20")
  (data (i32.const 285) "\44\69\66\66\65\72\65\6e\63\65\3a\20")
)