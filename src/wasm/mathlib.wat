;; mathlib.wat — Phase 38 extended Math library for wasic
;; Exports: sin, cos, tan, asin, acos, atan, atan2,
;;          exp, log, log2, log10, cbrt,
;;          sinh, cosh, tanh, asinh, acosh, atanh,
;;          expm1, log1p, random
;;
;; All functions operate on f64. random() uses a module-level xorshift64 PRNG.
;; This module is compiled to mathlib.wasm and auto-bundled by wasic when any
;; of these Math.* functions appear in the compiled TypeScript source.
;;
;; To regenerate mathlib.wasm:
;;   wasmtk convert src/wasm/mathlib.wat  (output goes to src/wasm/mathlib.wasm)
;; To regenerate mathlib_bytes.ts:
;;   deno run --allow-read --allow-write scripts/gen_mathlib_bytes.ts
(module
  ;; ── RNG state (xorshift64 seed) ─────────────────────────────────────────────
  (global $__rng_state (mut i64) (i64.const 0x6C62272E07BB0142))

  ;; ── Math.random — xorshift64, returns f64 in [0, 1) ────────────────────────
  (func $random (export "random") (result f64)
    (local $s i64)
    (local.set $s (global.get $__rng_state))
    (local.set $s (i64.xor (local.get $s) (i64.shl  (local.get $s) (i64.const 13))))
    (local.set $s (i64.xor (local.get $s) (i64.shr_u (local.get $s) (i64.const 7))))
    (local.set $s (i64.xor (local.get $s) (i64.shl  (local.get $s) (i64.const 17))))
    (global.set $__rng_state (local.get $s))
    (f64.sub
      (f64.reinterpret_i64
        (i64.or (i64.shr_u (local.get $s) (i64.const 12)) (i64.const 0x3FF0000000000000)))
      (f64.const 1.0))
  )

  ;; ── Math.sin — range-reduce to [-pi/2, pi/2], fdlibm S1-S6 Horner ──────────
  (func $sin (export "sin") (param $x f64) (result f64)
    (local $x2 f64)
    (local $t f64)
    (local $k f64)
    ;; Reduce to [-pi, pi] via a 3-term Cody-Waite split of 2*pi. Splitting 2*pi into
    ;; HI (low mantissa bits zeroed, so k*HI is EXACT for |k| < 2^30) + LO1 + LO2 keeps the
    ;; high-order cancellation exact, so large arguments (e.g. sin(5e8)) no longer lose ~7 sig figs.
    (local.set $k (f64.floor (f64.add
      (f64.mul (local.get $x) (f64.const 0.15915494309189535))
      (f64.const 0.5))))
    (local.set $x (f64.sub (f64.sub (f64.sub (local.get $x)
      (f64.mul (local.get $k) (f64.const 6.283185005187988)))
      (f64.mul (local.get $k) (f64.const 3.0199159795074593e-7)))
      (f64.mul (local.get $k) (f64.const 2.4492935982947064e-16))))
    ;; Reduce to [-pi/2, pi/2]
    (if (f64.gt (local.get $x) (f64.const 1.5707963267948966))
      (then (local.set $x (f64.sub (f64.const 3.141592653589793) (local.get $x)))))
    (if (f64.lt (local.get $x) (f64.const -1.5707963267948966))
      (then (local.set $x (f64.neg (f64.add (f64.const 3.141592653589793) (local.get $x))))))
    (local.set $x2 (f64.mul (local.get $x) (local.get $x)))
    ;; Horner from innermost S6 up to S1, then multiply by (1 + x2*poly)
    (local.set $t (f64.const 1.58962301576546568e-10))
    (local.set $t (f64.add (f64.const -2.5052106814843123e-8)  (f64.mul (local.get $x2) (local.get $t))))
    (local.set $t (f64.add (f64.const  2.7557313707070068e-6)  (f64.mul (local.get $x2) (local.get $t))))
    (local.set $t (f64.add (f64.const -1.984126982985795e-4)   (f64.mul (local.get $x2) (local.get $t))))
    (local.set $t (f64.add (f64.const  8.333333332539193e-3)   (f64.mul (local.get $x2) (local.get $t))))
    (local.set $t (f64.add (f64.const -1.6666666666666632e-1)  (f64.mul (local.get $x2) (local.get $t))))
    (local.set $t (f64.add (f64.const  1.0)                    (f64.mul (local.get $x2) (local.get $t))))
    (f64.mul (local.get $x) (local.get $t))
  )

  ;; ── Math.cos — same range reduction, sign flip for quadrants 2/3 ────────────
  (func $cos (export "cos") (param $x f64) (result f64)
    (local $x2 f64)
    (local $t f64)
    (local $sign i32)
    (local $k f64)
    (local.set $sign (i32.const 1))
    ;; Reduce to [-pi, pi] via a 3-term Cody-Waite split of 2*pi (see $sin for the rationale) so
    ;; large arguments keep full accuracy instead of losing ~7 sig figs to the single-constant subtract.
    (local.set $k (f64.floor (f64.add
      (f64.mul (local.get $x) (f64.const 0.15915494309189535))
      (f64.const 0.5))))
    (local.set $x (f64.sub (f64.sub (f64.sub (local.get $x)
      (f64.mul (local.get $k) (f64.const 6.283185005187988)))
      (f64.mul (local.get $k) (f64.const 3.0199159795074593e-7)))
      (f64.mul (local.get $k) (f64.const 2.4492935982947064e-16))))
    ;; Map to [-pi/2, pi/2], flip sign if in quadrant 2 or 3
    (if (f64.gt (local.get $x) (f64.const 1.5707963267948966))
      (then
        (local.set $x (f64.sub (f64.const 3.141592653589793) (local.get $x)))
        (local.set $sign (i32.const -1))))
    (if (f64.lt (local.get $x) (f64.const -1.5707963267948966))
      (then
        (local.set $x (f64.neg (f64.add (f64.const 3.141592653589793) (local.get $x))))
        (local.set $sign (i32.const -1))))
    (local.set $x2 (f64.mul (local.get $x) (local.get $x)))
    ;; Horner from innermost C6 up to C1
    (local.set $t (f64.const 2.08767569878681e-9))
    (local.set $t (f64.add (f64.const -2.7557319223985888e-7) (f64.mul (local.get $x2) (local.get $t))))
    (local.set $t (f64.add (f64.const  2.4801587301587302e-5) (f64.mul (local.get $x2) (local.get $t))))
    (local.set $t (f64.add (f64.const -1.3888888888888887e-3) (f64.mul (local.get $x2) (local.get $t))))
    (local.set $t (f64.add (f64.const  4.166666666666667e-2)  (f64.mul (local.get $x2) (local.get $t))))
    (local.set $t (f64.add (f64.const -4.9999999999999996e-1) (f64.mul (local.get $x2) (local.get $t))))
    (local.set $t (f64.add (f64.const  1.0)                   (f64.mul (local.get $x2) (local.get $t))))
    (if (i32.eq (local.get $sign) (i32.const -1))
      (then (local.set $t (f64.neg (local.get $t)))))
    (local.get $t)
  )

  ;; ── Math.tan ─────────────────────────────────────────────────────────────────
  (func $tan (export "tan") (param $x f64) (result f64)
    (f64.div (call $sin (local.get $x)) (call $cos (local.get $x)))
  )

  ;; ── Math.atan — two-stage range reduction + fdlibm aT[0..10] minimax poly ─────
  (func $atan (export "atan") (param $x f64) (result f64)
    (local $s i32)
    (local $z f64)
    (local $z2 f64)
    (local $r f64)
    (local $t f64)
    (local $comp i32)
    (local $mid i32)
    (local.set $s (i32.const 1))
    (local.set $z (local.get $x))
    (local.set $comp (i32.const 0))
    (local.set $mid (i32.const 0))
    ;; Handle negative input
    (if (f64.lt (local.get $x) (f64.const 0.0))
      (then
        (local.set $s (i32.const -1))
        (local.set $z (f64.neg (local.get $x)))))
    ;; Stage 1: complement reduction for z > 1: atan(z) = pi/2 - atan(1/z)
    (if (f64.gt (local.get $z) (f64.const 1.0))
      (then
        (local.set $z (f64.div (f64.const 1.0) (local.get $z)))
        (local.set $comp (i32.const 1))))
    ;; Stage 2: mid-range reduction for z > tan(pi/8): atan(z) = pi/4 + atan((z-1)/(z+1))
    (if (f64.gt (local.get $z) (f64.const 0.4142135623730951))
      (then
        (local.set $z (f64.div
          (f64.sub (local.get $z) (f64.const 1.0))
          (f64.add (local.get $z) (f64.const 1.0))))
        (local.set $mid (i32.const 1))))
    (local.set $z2 (f64.mul (local.get $z) (local.get $z)))
    ;; Horner from innermost aT[10] to aT[0]
    (local.set $t (f64.const  1.62858201153657823623e-2))
    (local.set $t (f64.add (f64.const -3.65315727442169155270e-2) (f64.mul (local.get $z2) (local.get $t))))
    (local.set $t (f64.add (f64.const  4.97687214484516269815e-2) (f64.mul (local.get $z2) (local.get $t))))
    (local.set $t (f64.add (f64.const -5.83357013380200465019e-2) (f64.mul (local.get $z2) (local.get $t))))
    (local.set $t (f64.add (f64.const  6.66107313738753491996e-2) (f64.mul (local.get $z2) (local.get $t))))
    (local.set $t (f64.add (f64.const -7.69187620504482999330e-2) (f64.mul (local.get $z2) (local.get $t))))
    (local.set $t (f64.add (f64.const  9.09088713343650656196e-2) (f64.mul (local.get $z2) (local.get $t))))
    (local.set $t (f64.add (f64.const -1.11111104054623557880e-1) (f64.mul (local.get $z2) (local.get $t))))
    (local.set $t (f64.add (f64.const  1.42857142725034663711e-1) (f64.mul (local.get $z2) (local.get $t))))
    (local.set $t (f64.add (f64.const -1.99999999998764832476e-1) (f64.mul (local.get $z2) (local.get $t))))
    (local.set $t (f64.add (f64.const  3.33333333333329318027e-1) (f64.mul (local.get $z2) (local.get $t))))
    ;; r = z - z³ * t
    (local.set $r (f64.sub (local.get $z)
      (f64.mul (f64.mul (local.get $z) (local.get $z2)) (local.get $t))))
    ;; Adjust for which reductions were applied
    (if (i32.and (local.get $comp) (local.get $mid))
      (then (local.set $r (f64.sub (f64.const 0.7853981633974483) (local.get $r))))
      (else
        (if (local.get $comp)
          (then (local.set $r (f64.sub (f64.const 1.5707963267948966) (local.get $r))))
          (else
            (if (local.get $mid)
              (then (local.set $r (f64.add (f64.const 0.7853981633974483) (local.get $r)))))))))
    ;; Apply sign
    (if (i32.eq (local.get $s) (i32.const -1))
      (then (local.set $r (f64.neg (local.get $r)))))
    (local.get $r)
  )

  ;; ── Math.atan2(y, x) ─────────────────────────────────────────────────────────
  (func $atan2 (export "atan2") (param $y f64) (param $x f64) (result f64)
    (local $r f64)
    ;; Special case: x = 0
    (if (f64.eq (local.get $x) (f64.const 0.0))
      (then
        (if (f64.gt (local.get $y) (f64.const 0.0))
          (then (return (f64.const 1.5707963267948966))))
        (if (f64.lt (local.get $y) (f64.const 0.0))
          (then (return (f64.const -1.5707963267948966))))
        (return (f64.const 0.0))))
    (local.set $r (call $atan (f64.div (local.get $y) (local.get $x))))
    ;; Adjust for x < 0 quadrants
    (if (f64.lt (local.get $x) (f64.const 0.0))
      (then
        (if (f64.ge (local.get $y) (f64.const 0.0))
          (then (local.set $r (f64.add (local.get $r) (f64.const 3.141592653589793))))
          (else (local.set $r (f64.sub (local.get $r) (f64.const 3.141592653589793)))))))
    (local.get $r)
  )

  ;; ── Math.asin — atan(x/sqrt(1-x²)) for |x|<=0.7, complement otherwise ───────
  (func $asin (export "asin") (param $x f64) (result f64)
    (local $neg i32)
    (local $a f64)
    (local $r f64)
    (local.set $neg (i32.const 0))
    (local.set $a (local.get $x))
    (if (f64.lt (local.get $x) (f64.const 0.0))
      (then
        (local.set $neg (i32.const 1))
        (local.set $a (f64.neg (local.get $x)))))
    (if (f64.le (local.get $a) (f64.const 0.7))
      (then
        (local.set $r (call $atan
          (f64.div (local.get $a)
            (f64.sqrt (f64.sub (f64.const 1.0) (f64.mul (local.get $a) (local.get $a))))))))
      (else
        (local.set $r (f64.sub (f64.const 1.5707963267948966)
          (f64.mul (f64.const 2.0)
            (call $asin
              (f64.sqrt (f64.mul (f64.const 0.5)
                (f64.sub (f64.const 1.0) (local.get $a))))))))))
    (if (i32.eq (local.get $neg) (i32.const 1))
      (then (local.set $r (f64.neg (local.get $r)))))
    (local.get $r)
  )

  ;; ── Math.acos = pi/2 - asin(x) ───────────────────────────────────────────────
  (func $acos (export "acos") (param $x f64) (result f64)
    (f64.sub (f64.const 1.5707963267948966) (call $asin (local.get $x)))
  )

  ;; ── Math.exp — Cody-Waite range reduction + 10-term Taylor + 2^k bit trick ───
  (func $exp (export "exp") (param $x f64) (result f64)
    (local $k i64)
    (local $r f64)
    (local $t f64)
    ;; Clamp overflow / underflow
    (if (f64.gt (local.get $x) (f64.const 709.782712893384))
      (then (return (f64.mul (f64.const 1.7976931348623157e308) (f64.const 1.7976931348623157e308)))))
    (if (f64.lt (local.get $x) (f64.const -708.3964185322641))
      (then (return (f64.const 0.0))))
    ;; k = round(x / ln2)
    (local.set $k
      (i64.trunc_f64_s (f64.nearest (f64.mul (local.get $x) (f64.const 1.4426950408889634)))))
    ;; Cody-Waite reduction: r = x - k*ln2_hi - k*ln2_lo
    (local.set $r
      (f64.sub
        (f64.sub (local.get $x)
          (f64.mul (f64.convert_i64_s (local.get $k)) (f64.const 6.931471805599453e-1)))
        (f64.mul (f64.convert_i64_s (local.get $k)) (f64.const 1.9082149292705877e-10))))
    ;; Horner for e^r: 1 + r + r²/2! + ... + r^10/10! (from innermost)
    (local.set $t (f64.const 2.755731922398589e-7))
    (local.set $t (f64.add (f64.const 2.7557319223985888e-6) (f64.mul (local.get $r) (local.get $t))))
    (local.set $t (f64.add (f64.const 2.4801587301587302e-5) (f64.mul (local.get $r) (local.get $t))))
    (local.set $t (f64.add (f64.const 1.984126984126984e-4)  (f64.mul (local.get $r) (local.get $t))))
    (local.set $t (f64.add (f64.const 1.388888888888889e-3)  (f64.mul (local.get $r) (local.get $t))))
    (local.set $t (f64.add (f64.const 8.333333333333334e-3)  (f64.mul (local.get $r) (local.get $t))))
    (local.set $t (f64.add (f64.const 4.1666666666666664e-2) (f64.mul (local.get $r) (local.get $t))))
    (local.set $t (f64.add (f64.const 1.6666666666666666e-1) (f64.mul (local.get $r) (local.get $t))))
    (local.set $t (f64.add (f64.const 5.0e-1)               (f64.mul (local.get $r) (local.get $t))))
    (local.set $t (f64.add (f64.const 1.0)                  (f64.mul (local.get $r) (local.get $t))))
    (local.set $t (f64.add (f64.const 1.0)                  (f64.mul (local.get $r) (local.get $t))))
    ;; Multiply by 2^k via IEEE exponent bit trick
    (f64.mul (local.get $t)
      (f64.reinterpret_i64
        (i64.shl (i64.add (local.get $k) (i64.const 1023)) (i64.const 52))))
  )

  ;; ── Math.log (natural log) — mantissa/exponent decomposition + atanh series ──
  (func $log (export "log") (param $x f64) (result f64)
    (local $bits i64)
    (local $e i64)
    (local $m f64)
    (local $s f64)
    (local $s2 f64)
    (local $t f64)
    ;; Handle x <= 0
    (if (f64.le (local.get $x) (f64.const 0.0))
      (then (return
        (if (result f64) (f64.eq (local.get $x) (f64.const 0.0))
          (then (f64.div (f64.const -1.0) (f64.const 0.0)))
          (else (f64.div (f64.const  0.0) (f64.const 0.0)))))))
    ;; Handle +Inf
    (if (f64.gt (local.get $x) (f64.const 1.7976931348623157e308))
      (then (return (local.get $x))))
    ;; Decompose into e and m in [1, 2)
    (local.set $bits (i64.reinterpret_f64 (local.get $x)))
    (local.set $e
      (i64.sub
        (i64.shr_u (i64.and (local.get $bits) (i64.const 0x7FF0000000000000)) (i64.const 52))
        (i64.const 1023)))
    (local.set $m
      (f64.reinterpret_i64
        (i64.or (i64.and (local.get $bits) (i64.const 0x000FFFFFFFFFFFFF)) (i64.const 0x3FF0000000000000))))
    ;; Normalize m to [1, sqrt(2)] for better convergence
    (if (f64.gt (local.get $m) (f64.const 1.4142135623730951))
      (then
        (local.set $m (f64.mul (local.get $m) (f64.const 0.5)))
        (local.set $e (i64.add (local.get $e) (i64.const 1)))))
    ;; s = (m-1)/(m+1),  ln(m) = 2*s*(1 + s²/3 + s⁴/5 + ... + s^14/15)
    (local.set $s
      (f64.div (f64.sub (local.get $m) (f64.const 1.0)) (f64.add (local.get $m) (f64.const 1.0))))
    (local.set $s2 (f64.mul (local.get $s) (local.get $s)))
    ;; Horner from 1/15 down to 1/1
    (local.set $t (f64.const 6.666666666666667e-2))
    (local.set $t (f64.add (f64.const 7.692307692307692e-2) (f64.mul (local.get $s2) (local.get $t))))
    (local.set $t (f64.add (f64.const 9.090909090909091e-2) (f64.mul (local.get $s2) (local.get $t))))
    (local.set $t (f64.add (f64.const 1.1111111111111111e-1) (f64.mul (local.get $s2) (local.get $t))))
    (local.set $t (f64.add (f64.const 1.4285714285714285e-1) (f64.mul (local.get $s2) (local.get $t))))
    (local.set $t (f64.add (f64.const 2.0e-1)               (f64.mul (local.get $s2) (local.get $t))))
    (local.set $t (f64.add (f64.const 3.3333333333333333e-1) (f64.mul (local.get $s2) (local.get $t))))
    (local.set $t (f64.add (f64.const 1.0)                  (f64.mul (local.get $s2) (local.get $t))))
    ;; log(x) = e*ln2 + 2*s*poly
    (f64.add
      (f64.mul (f64.convert_i64_s (local.get $e)) (f64.const 6.931471805599453e-1))
      (f64.mul (f64.const 2.0) (f64.mul (local.get $s) (local.get $t))))
  )

  ;; ── Math.log2 / Math.log10 ───────────────────────────────────────────────────
  (func $log2 (export "log2") (param $x f64) (result f64)
    (f64.mul (call $log (local.get $x)) (f64.const 1.4426950408889634))
  )
  (func $log10 (export "log10") (param $x f64) (result f64)
    (f64.mul (call $log (local.get $x)) (f64.const 4.342944819032518e-1))
  )

  ;; ── Math.cbrt — exp(log(x)/3) initial guess + 3 Newton steps ────────────────
  (func $cbrt (export "cbrt") (param $x f64) (result f64)
    (local $neg i32)
    (local $y f64)
    (local.set $neg (i32.const 0))
    (if (f64.eq (local.get $x) (f64.const 0.0)) (then (return (f64.const 0.0))))
    (if (f64.gt (local.get $x) (f64.const 1.7976931348623157e308)) (then (return (local.get $x))))
    (if (f64.lt (local.get $x) (f64.const 0.0))
      (then
        (local.set $neg (i32.const 1))
        (local.set $x (f64.neg (local.get $x)))))
    (local.set $y (call $exp (f64.div (call $log (local.get $x)) (f64.const 3.0))))
    ;; Newton: y = (2y + x/y²) / 3
    (local.set $y (f64.div
      (f64.add (f64.mul (f64.const 2.0) (local.get $y))
               (f64.div (local.get $x) (f64.mul (local.get $y) (local.get $y))))
      (f64.const 3.0)))
    (local.set $y (f64.div
      (f64.add (f64.mul (f64.const 2.0) (local.get $y))
               (f64.div (local.get $x) (f64.mul (local.get $y) (local.get $y))))
      (f64.const 3.0)))
    (local.set $y (f64.div
      (f64.add (f64.mul (f64.const 2.0) (local.get $y))
               (f64.div (local.get $x) (f64.mul (local.get $y) (local.get $y))))
      (f64.const 3.0)))
    (if (i32.eq (local.get $neg) (i32.const 1))
      (then (local.set $y (f64.neg (local.get $y)))))
    (local.get $y)
  )

  ;; ── Math.sinh / cosh / tanh ──────────────────────────────────────────────────
  (func $sinh (export "sinh") (param $x f64) (result f64)
    (local $ep f64)
    (local.set $ep (call $exp (local.get $x)))
    (f64.mul (f64.const 0.5) (f64.sub (local.get $ep) (f64.div (f64.const 1.0) (local.get $ep))))
  )
  (func $cosh (export "cosh") (param $x f64) (result f64)
    (local $ep f64)
    (local.set $ep (call $exp (local.get $x)))
    (f64.mul (f64.const 0.5) (f64.add (local.get $ep) (f64.div (f64.const 1.0) (local.get $ep))))
  )
  (func $tanh (export "tanh") (param $x f64) (result f64)
    (local $e2x f64)
    (local.set $e2x (call $exp (f64.mul (f64.const 2.0) (local.get $x))))
    (f64.div
      (f64.sub (local.get $e2x) (f64.const 1.0))
      (f64.add (local.get $e2x) (f64.const 1.0)))
  )

  ;; ── Math.asinh / acosh / atanh ───────────────────────────────────────────────
  (func $asinh (export "asinh") (param $x f64) (result f64)
    (call $log
      (f64.add (local.get $x)
        (f64.sqrt (f64.add (f64.mul (local.get $x) (local.get $x)) (f64.const 1.0)))))
  )
  (func $acosh (export "acosh") (param $x f64) (result f64)
    (call $log
      (f64.add (local.get $x)
        (f64.sqrt (f64.sub (f64.mul (local.get $x) (local.get $x)) (f64.const 1.0)))))
  )
  (func $atanh (export "atanh") (param $x f64) (result f64)
    (f64.mul (f64.const 0.5)
      (f64.sub
        (call $log (f64.add (f64.const 1.0) (local.get $x)))
        (call $log (f64.sub (f64.const 1.0) (local.get $x)))))
  )

  ;; ── Math.expm1 — Taylor series for |x|<1, exp(x)-1 otherwise ────────────────
  (func $expm1 (export "expm1") (param $x f64) (result f64)
    (local $ax f64)
    (local $t f64)
    (local.set $ax (f64.abs (local.get $x)))
    (if (f64.lt (local.get $ax) (f64.const 2.220446049250313e-16)) (then (return (local.get $x))))
    (if (f64.ge (local.get $ax) (f64.const 1.0))
      (then (return (f64.sub (call $exp (local.get $x)) (f64.const 1.0)))))
    ;; Horner for x*(1 + x/2! + x²/3! + ... + x^7/8!) from innermost
    (local.set $t (f64.const 1.984126984126984e-4))
    (local.set $t (f64.add (f64.const 1.388888888888889e-3)  (f64.mul (local.get $x) (local.get $t))))
    (local.set $t (f64.add (f64.const 8.333333333333333e-3)  (f64.mul (local.get $x) (local.get $t))))
    (local.set $t (f64.add (f64.const 4.1666666666666664e-2) (f64.mul (local.get $x) (local.get $t))))
    (local.set $t (f64.add (f64.const 1.6666666666666666e-1) (f64.mul (local.get $x) (local.get $t))))
    (local.set $t (f64.add (f64.const 5.0e-1)               (f64.mul (local.get $x) (local.get $t))))
    (local.set $t (f64.add (f64.const 1.0)                  (f64.mul (local.get $x) (local.get $t))))
    (f64.mul (local.get $x) (local.get $t))
  )

  ;; ── Math.log1p — accurate log(1+x) for small x ───────────────────────────────
  (func $log1p (export "log1p") (param $x f64) (result f64)
    (if (f64.lt (f64.abs (local.get $x)) (f64.const 2.220446049250313e-16))
      (then (return (local.get $x))))
    (call $log (f64.add (f64.const 1.0) (local.get $x)))
  )
)
