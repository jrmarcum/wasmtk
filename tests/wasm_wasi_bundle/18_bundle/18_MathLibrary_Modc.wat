(module
  (import "wasi_snapshot_preview1" "fd_write" (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (memory (export "memory") 2)
  (global $__heap_ptr (mut i32) (i32.const 289))
  (global $libraryMultiplier i32 (i32.const 3))
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
  (func $computeScaledArea (export "computeScaledArea") (param $base i32) (param $height i32) (result i32)
    (local $area i32)
    (local.set $area (i32.shr_s (i32.mul (local.get $base) (local.get $height)) (i32.const 1)))
    (return (i32.mul (local.get $area) (global.get $libraryMultiplier)))
  )

  (func $logLibraryVersion (export "logLibraryVersion")  
    (local $__iface_tmp i32)
        (i32.store (i32.const 0) (i32.const 260))
          (i32.store (i32.const 4) (i32.const 29))
          (drop (call $fd_write
            (i32.const 1)
            (i32.const 0)
            (i32.const 1)
            (i32.const 128)))
  )
  (data (i32.const 260) "\4c\69\62\72\61\72\79\20\56\65\72\73\69\6f\6e\3a\20\76\31\2e\38\2e\30\2d\63\6f\72\65\0a")
)