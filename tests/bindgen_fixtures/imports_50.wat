(module
  (import "env" "env_mul" (func $env_mul (param f64) (param f64) (result f64)))
  (import "env" "env_add" (func $env_add (param i32) (param i32) (result i32)))
  (memory (export "memory") 2)
  (global $__heap_ptr (mut i32) (i32.const 260))
  ;; Bump allocator — advances __heap_ptr and returns the old value
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
  (func $scale (export "scale") (param $x f64) (param $factor f64) (result f64)
    (local $__iface_tmp i32)
    (return (call $env_mul (local.get $x) (local.get $factor)))
  )

  (func $combine (export "combine") (param $a i32) (param $b i32) (result i32)
    (local $__iface_tmp i32)
    (return (call $env_add (local.get $a) (local.get $b)))
  )
)