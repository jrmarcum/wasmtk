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
  (func $add (export "add") (param $a i32) (param $b i32) (result i32)
    (return (i32.add (local.get $a) (local.get $b)))
  )

  (func $multiply (export "multiply") (param $a f64) (param $b f64) (result f64)
    (return (f64.mul (local.get $a) (local.get $b)))
  )

  (func $square (export "square") (param $x i32) (result i32)
    (return (i32.mul (local.get $x) (local.get $x)))
  )
)