(module
  (memory (export "memory") 2)
  (global $__heap_ptr (mut i32) (i32.const 260))
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
  (func $makeBufferB (export "makeBufferB") (param $size i32) (result i32)
    (local $buf i32)
    (local $i i32)
    (local $__iface_tmp i32)
    (local.set $buf (call $__malloc (i32.const 40)))
      (i32.store (local.get $buf) (i32.const 0))
      (i32.store offset=4 (local.get $buf) (i32.const 8))
    (local.set $i (i32.const 0))
    (block $break_0
      (loop $loop_0
        (br_if $break_0 (i32.eqz (i32.lt_s (local.get $i) (local.get $size))))
        (block $cont_0
          (local.set $buf (call $__dynarr_push_i32 (local.get $buf) (i32.add (i32.const 187) (local.get $i))))
          (local.set $i (i32.add (local.get $i) (i32.const 1)))
        )
        (br $loop_0)
      )
    )
    (return (i32.load (local.get $buf)))
  )
)