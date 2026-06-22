(module
  (import "wasi_snapshot_preview1" "fd_write" (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (memory (export "memory") 2)
  (global $__heap_ptr (mut i32) (i32.const 302))
  (global $extra i32 (i32.const 7))
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
  (func $modByInRange (export "modByInRange") (param $x i32) (result i32)
    (return (i32.add (i32.rem_s (local.get $x) (i32.const 271)) (global.get $extra)))
  )

  (func $banner (export "banner")  
    (local $__iface_tmp i32)
        (i32.store (i32.const 0) (i32.const 260))
          (i32.store (i32.const 4) (i32.const 42))
          (drop (call $fd_write
            (i32.const 1)
            (i32.const 0)
            (i32.const 1)
            (i32.const 128)))
  )
  (data (i32.const 260) "\52\65\6c\6f\63\20\63\61\70\61\62\69\6c\69\74\79\20\6c\69\62\72\61\72\79\20\62\61\6e\6e\65\72\20\73\74\72\69\6e\67\20\76\31\0a")
)