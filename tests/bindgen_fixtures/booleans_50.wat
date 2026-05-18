(module
  (memory (export "memory") 2)
  (global $__heap_ptr (mut i32) (i32.const 260))
  ;; Bump allocator — advances __heap_ptr and returns the old value
  (func $__malloc (param $size i32) (result i32)
    (local $ptr i32)
    (local.set $ptr (global.get $__heap_ptr))
    (global.set $__heap_ptr (i32.add (local.get $ptr) (local.get $size)))
    (local.get $ptr)
  )
  (func $isPositive (export "isPositive") (param $x f64) (result i32)
    (return (f64.gt (local.get $x) (f64.const 0.0)))
  )

  (func $inRange (export "inRange") (param $v f64) (param $lo f64) (param $hi f64) (result i32)
    (return (i32.and (f64.ge (local.get $v) (local.get $lo)) (f64.le (local.get $v) (local.get $hi))))
  )

  (func $isEven (export "isEven") (param $n i32) (result i32)
    (return (i32.eq (i32.rem_s (local.get $n) (i32.const 2)) (i32.const 0)))
  )
)