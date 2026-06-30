(module
  ;; imports from dynrt
  (import "env" "__host_call" (func $dynrt___host_call (param i32 i32) (result i32)))
  (memory (export "memory") 2)
  (global $__heap_ptr (mut i32) (i32.const 1159))
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










































































































































  (func $getDoubler (export "getDoubler")  (result i32)
    (return (call $dynrt_dynMakeFn (i32.const 260) (i32.const 1) (i32.const 261) (i32.const 13)))
  )
  (data (i32.const 260) "\78")
  (data (i32.const 261) "\72\65\74\75\72\6e\20\78\20\2a\20\32\3b")

  ;; globals from dynrt
  (global $dynrt_global1 (mut i32) (i32.const 0))
  (global $dynrt_global2 (mut i32) (i32.const 0))
  (global $dynrt_global3 i32 (i32.const 4))
  (global $dynrt_global4 i32 (i32.const 16))
  (global $dynrt_global5 i32 (i32.const 786))
  (global $dynrt_global6 (mut i32) (i32.const 0))
  (global $dynrt_global7 (mut i32) (i32.const 0))
  (global $dynrt_global8 (mut i32) (i32.const 0))
  (global $dynrt_global9 (mut i32) (i32.const 0))
  (global $dynrt_global10 (mut i32) (i32.const 0))
  (global $dynrt_global11 (mut i32) (i32.const 0))
  (global $dynrt_global12 (mut i32) (i32.const 0))
  (global $dynrt_global13 (mut i32) (i32.const 786))
  (global $dynrt_global14 (mut i32) (i32.const 8192))
  (global $dynrt_global15 (mut i32) (i32.const 0))
  (global $dynrt_global16 i32 (i32.const 256))
  (global $dynrt_global17 (mut i32) (i32.const 0))
  (global $dynrt_global18 (mut i32) (i32.const 0))
  (global $dynrt_global19 (mut i32) (i32.const 0))
  (global $dynrt_global20 (mut i32) (i32.const -1))
  (global $dynrt_global21 (mut i32) (i32.const 1))
  (global $dynrt_global22 (mut i32) (i32.const 0))
  (global $dynrt_global23 (mut i32) (i32.const 0))
  (global $dynrt_global24 (mut i32) (i32.const 0))
  (global $dynrt_global25 (mut i32) (i32.const 0))
  (global $dynrt_global26 (mut i32) (i32.const 0))
  (global $dynrt_global27 (mut i32) (i32.const 0))
  (global $dynrt_global28 (mut i32) (i32.const 0))
  (global $dynrt_global29 (mut i32) (i32.const 0))
  ;; functions from dynrt
  (func $dynrt_cabi_realloc (param i32 i32 i32 i32) (result i32)
    local.get 3
    call $__malloc
    local.get 0
    local.get 0
    i32.eqz
    select)
  (func $dynrt__fn3 (param i32 i32 i32)
    (local i32) (local i32)
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 3
          local.get 1
          i32.ge_u
          br_if 2 (;@1;)
          local.get 2
          local.get 3
          i32.add
          local.get 0
          local.get 3
          i32.add
          i32.load8_u
          i32.store8
          local.get 3
          local.tee 4
          i32.const 1
          i32.add
          local.set 3
          br 1 (;@2;)
        end
      end
    end)
  (func $dynrt__fn4 (param i32 i32 i32 i32) (result i32 i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 1
    local.get 3
    i32.add
    local.set 5
    local.get 5
    call $__malloc
    local.set 4
    i32.const 0
    local.tee 9
    local.set 6
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 6
          local.get 1
          i32.ge_u
          br_if 2 (;@1;)
          local.get 4
          local.get 6
          i32.add
          local.get 0
          local.get 6
          i32.add
          i32.load8_u
          i32.store8
          local.get 6
          local.tee 7
          i32.const 1
          i32.add
          local.set 6
          br 1 (;@2;)
        end
      end
    end
    i32.const 0
    local.tee 10
    local.set 6
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 6
          local.get 3
          i32.ge_u
          br_if 2 (;@1;)
          local.get 4
          local.get 1
          local.get 6
          i32.add
          i32.add
          local.get 2
          local.get 6
          i32.add
          i32.load8_u
          i32.store8
          local.get 6
          local.tee 8
          i32.const 1
          i32.add
          local.set 6
          br 1 (;@2;)
        end
      end
    end
    local.get 4
    local.get 5
    local.tee 11)
  (func $dynrt__fn5 (param i32 i32 i32 i32) (result i32 i32)
    (local i32) (local i32) (local i32)
    i32.const 0
    local.get 2
    local.get 2
    i32.const 0
    i32.lt_s
    select
    local.set 4
    local.get 4
    local.get 1
    i32.gt_s
    if  ;; label = @1
      local.get 1
      local.set 4
    end
    local.get 1
    local.get 3
    local.get 3
    local.get 1
    i32.gt_s
    select
    local.set 5
    local.get 5
    local.get 4
    i32.lt_s
    if  ;; label = @1
      local.get 4
      local.set 5
    end
    local.get 0
    local.get 4
    local.tee 6
    i32.add
    local.get 5
    local.get 6
    i32.sub)
  (func $dynrt__fn6 (param i32 i32 i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 3
    i32.eqz
    if  ;; label = @1
      i32.const 0
      return
    end
    local.get 1
    local.get 3
    i32.sub
    local.set 6
    local.get 6
    i32.const 0
    i32.lt_s
    if  ;; label = @1
      i32.const -1
      return
    end
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 4
          local.get 6
          i32.gt_s
          br_if 2 (;@1;)
          i32.const 0
          local.set 5
          i32.const 1
          local.tee 8
          local.set 7
          block  ;; label = @4
            loop  ;; label = @5
              block  ;; label = @6
                local.get 5
                local.get 3
                i32.ge_u
                br_if 2 (;@4;)
                local.get 0
                local.get 4
                local.get 5
                i32.add
                i32.add
                i32.load8_u
                local.get 2
                local.get 5
                i32.add
                i32.load8_u
                i32.ne
                if  ;; label = @7
                  block  ;; label = @8
                    i32.const 0
                    local.set 7
                    br 4 (;@4;)
                  end
                end
                local.get 5
                i32.const 1
                i32.add
                local.set 5
                br 1 (;@5;)
              end
            end
          end
          local.get 7
          if  ;; label = @4
            local.get 4
            return
          end
          local.get 4
          local.get 8
          i32.add
          local.set 4
          br 1 (;@2;)
        end
      end
    end
    i32.const -1)
  (func $dynrt__fn7 (param i32 i32) (result i32 i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    i32.const 0
    local.set 2
    local.get 1
    local.set 3
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 2
          local.get 3
          i32.ge_u
          br_if 2 (;@1;)
          local.get 0
          local.get 2
          i32.add
          i32.load8_u
          local.set 4
          local.get 4
          i32.const 32
          i32.ne
          local.get 4
          i32.const 9
          i32.ne
          i32.and
          local.get 4
          i32.const 10
          i32.ne
          local.get 4
          i32.const 13
          i32.ne
          i32.and
          i32.and
          br_if 2 (;@1;)
          local.get 2
          local.tee 5
          i32.const 1
          i32.add
          local.set 2
          br 1 (;@2;)
        end
      end
    end
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 3
          local.get 2
          i32.le_u
          br_if 2 (;@1;)
          local.get 0
          local.get 3
          i32.const 1
          i32.sub
          i32.add
          i32.load8_u
          local.set 4
          local.get 4
          i32.const 32
          i32.ne
          local.get 4
          i32.const 9
          i32.ne
          i32.and
          local.get 4
          i32.const 10
          i32.ne
          local.get 4
          i32.const 13
          i32.ne
          i32.and
          i32.and
          br_if 2 (;@1;)
          local.get 3
          i32.const 1
          i32.sub
          local.tee 6
          local.set 3
          br 1 (;@2;)
        end
      end
    end
    local.get 0
    local.get 2
    local.tee 7
    i32.add
    local.get 3
    local.get 7
    i32.sub)
  (func $dynrt__fn8 (param i32 i32 i32) (result i32)
    local.get 2
    i32.const 0
    i32.lt_s
    if  ;; label = @1
      i32.const -1
      return
    end
    local.get 2
    local.get 1
    i32.ge_u
    if  ;; label = @1
      i32.const -1
      return
    end
    local.get 0
    local.get 2
    i32.add
    i32.load8_u)
  (func $dynrt__fn9 (param i32 i32 i32) (result i32 i32)
    local.get 2
    i32.const 0
    i32.lt_s
    if  ;; label = @1
      block  ;; label = @2
        local.get 0
        i32.const 0
        return
      end
    end
    local.get 2
    local.get 1
    i32.ge_u
    if  ;; label = @1
      block  ;; label = @2
        local.get 0
        i32.const 0
        return
      end
    end
    local.get 0
    local.get 2
    i32.add
    i32.const 1)
  (func $dynrt__fn10 (param i32 i32 i32 i32) (result i32)
    (local i32)
    local.get 3
    local.get 1
    i32.gt_u
    if  ;; label = @1
      i32.const 0
      return
    end
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 4
          local.get 3
          i32.ge_u
          br_if 2 (;@1;)
          local.get 0
          local.get 4
          i32.add
          i32.load8_u
          local.get 2
          local.get 4
          i32.add
          i32.load8_u
          i32.ne
          if  ;; label = @4
            i32.const 0
            return
          end
          local.get 4
          i32.const 1
          i32.add
          local.set 4
          br 1 (;@2;)
        end
      end
    end
    i32.const 1)
  (func $dynrt__fn11 (param i32 i32 i32 i32) (result i32)
    (local i32) (local i32)
    local.get 3
    local.get 1
    i32.gt_u
    if  ;; label = @1
      i32.const 0
      return
    end
    local.get 1
    local.get 3
    i32.sub
    local.set 5
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 4
          local.get 3
          i32.ge_u
          br_if 2 (;@1;)
          local.get 0
          local.get 5
          local.get 4
          i32.add
          i32.add
          i32.load8_u
          local.get 2
          local.get 4
          i32.add
          i32.load8_u
          i32.ne
          if  ;; label = @4
            i32.const 0
            return
          end
          local.get 4
          i32.const 1
          i32.add
          local.set 4
          br 1 (;@2;)
        end
      end
    end
    i32.const 1)
  (func $dynrt__fn12 (param i32 i32) (result i32 i32)
    (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 1
    call $__malloc
    local.set 2
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 3
          local.get 1
          i32.ge_u
          br_if 2 (;@1;)
          local.get 0
          local.get 3
          i32.add
          i32.load8_u
          local.set 4
          local.get 4
          i32.const 97
          i32.ge_u
          local.get 4
          i32.const 122
          i32.le_u
          i32.and
          if  ;; label = @4
            local.get 4
            i32.const 32
            i32.sub
            local.set 4
          end
          local.get 2
          local.get 3
          i32.add
          local.get 4
          i32.store8
          local.get 3
          local.tee 5
          i32.const 1
          i32.add
          local.set 3
          br 1 (;@2;)
        end
      end
    end
    local.get 2
    local.get 1
    local.tee 6)
  (func $dynrt__fn13 (param i32 i32) (result i32 i32)
    (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 1
    call $__malloc
    local.set 2
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 3
          local.get 1
          i32.ge_u
          br_if 2 (;@1;)
          local.get 0
          local.get 3
          i32.add
          i32.load8_u
          local.set 4
          local.get 4
          i32.const 65
          i32.ge_u
          local.get 4
          i32.const 90
          i32.le_u
          i32.and
          if  ;; label = @4
            local.get 4
            i32.const 32
            i32.add
            local.set 4
          end
          local.get 2
          local.get 3
          i32.add
          local.get 4
          i32.store8
          local.get 3
          local.tee 5
          i32.const 1
          i32.add
          local.set 3
          br 1 (;@2;)
        end
      end
    end
    local.get 2
    local.get 1
    local.tee 6)
  (func $dynrt__fn14 (param i32 i32 i32 i32 i32) (result i32 i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 2
    local.get 1
    i32.le_s
    if  ;; label = @1
      block  ;; label = @2
        local.get 0
        local.get 1
        return
      end
    end
    local.get 2
    local.tee 12
    local.get 1
    i32.sub
    local.set 6
    local.get 2
    call $__malloc
    local.set 5
    local.get 4
    i32.eqz
    if  ;; label = @1
      i32.const 1
      local.set 4
    end
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 7
          local.get 6
          i32.ge_u
          br_if 2 (;@1;)
          local.get 7
          local.tee 9
          local.get 4
          i32.rem_u
          local.set 8
          local.get 5
          local.get 7
          i32.add
          local.get 3
          local.get 8
          i32.add
          i32.load8_u
          i32.store8
          local.get 7
          local.tee 10
          i32.const 1
          i32.add
          local.set 7
          br 1 (;@2;)
        end
      end
    end
    i32.const 0
    local.set 8
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 8
          local.get 1
          i32.ge_u
          br_if 2 (;@1;)
          local.get 5
          local.get 6
          local.get 8
          i32.add
          i32.add
          local.get 0
          local.get 8
          i32.add
          i32.load8_u
          i32.store8
          local.get 8
          local.tee 11
          i32.const 1
          i32.add
          local.set 8
          br 1 (;@2;)
        end
      end
    end
    local.get 5
    local.get 2
    local.tee 13)
  (func $dynrt__fn15 (param i32 i32 i32 i32 i32) (result i32 i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 2
    local.get 1
    i32.le_s
    if  ;; label = @1
      block  ;; label = @2
        local.get 0
        local.get 1
        return
      end
    end
    local.get 2
    local.tee 11
    local.get 1
    i32.sub
    drop
    local.get 2
    call $__malloc
    local.set 5
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 6
          local.get 1
          i32.ge_u
          br_if 2 (;@1;)
          local.get 5
          local.get 6
          i32.add
          local.get 0
          local.get 6
          i32.add
          i32.load8_u
          i32.store8
          local.get 6
          local.tee 8
          i32.const 1
          i32.add
          local.set 6
          br 1 (;@2;)
        end
      end
    end
    local.get 4
    i32.eqz
    if  ;; label = @1
      i32.const 1
      local.set 4
    end
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 6
          local.get 2
          i32.ge_u
          br_if 2 (;@1;)
          local.get 6
          local.tee 9
          local.get 1
          i32.sub
          local.get 4
          i32.rem_u
          local.set 7
          local.get 5
          local.get 6
          i32.add
          local.get 3
          local.get 7
          i32.add
          i32.load8_u
          i32.store8
          local.get 6
          local.tee 10
          i32.const 1
          i32.add
          local.set 6
          br 1 (;@2;)
        end
      end
    end
    local.get 5
    local.get 2
    local.tee 12)
  (func $dynrt__fn16 (param i32 i32 i32) (result i32 i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 2
    i32.const 0
    i32.le_s
    if  ;; label = @1
      block  ;; label = @2
        local.get 0
        i32.const 0
        return
      end
    end
    local.get 1
    local.get 2
    i32.mul
    local.set 4
    local.get 4
    call $__malloc
    local.set 3
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 5
          local.get 2
          i32.ge_u
          br_if 2 (;@1;)
          i32.const 0
          local.set 6
          block  ;; label = @4
            loop  ;; label = @5
              block  ;; label = @6
                local.get 6
                local.get 1
                i32.ge_u
                br_if 2 (;@4;)
                local.get 3
                local.get 5
                local.get 1
                i32.mul
                local.get 6
                i32.add
                i32.add
                local.get 0
                local.get 6
                i32.add
                i32.load8_u
                i32.store8
                local.get 6
                local.tee 7
                i32.const 1
                i32.add
                local.set 6
                br 1 (;@5;)
              end
            end
          end
          local.get 5
          i32.const 1
          i32.add
          local.set 5
          br 1 (;@2;)
        end
      end
    end
    local.get 3
    local.get 4
    local.tee 8)
  (func $dynrt__fn17 (param i32 i32 i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    i32.const 8
    local.tee 28
    local.set 5
    i32.const 8
    local.get 5
    i32.const 8
    i32.mul
    i32.add
    call $__malloc
    local.set 4
    local.get 4
    i32.const 0
    i32.store
    local.get 4
    local.get 5
    i32.store offset=4
    local.get 3
    i32.eqz
    if  ;; label = @1
      block  ;; label = @2
        local.get 4
        local.get 0
        i32.store offset=8
        local.get 4
        local.get 1
        i32.store offset=12
        local.get 4
        i32.const 1
        i32.store
        local.get 4
        local.tee 11
        return
      end
    end
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 0
          local.get 7
          i32.add
          local.get 1
          local.get 7
          i32.sub
          local.get 2
          local.get 3
          call $dynrt__fn6
          local.set 8
          local.get 8
          i32.const -1
          i32.eq
          if  ;; label = @4
            block  ;; label = @5
              local.get 0
              local.get 7
              local.tee 12
              i32.add
              local.set 9
              local.get 1
              local.get 12
              i32.sub
              local.set 10
              br 4 (;@1;)
            end
          end
          local.get 8
          local.tee 17
          local.get 7
          local.tee 18
          i32.add
          local.set 8
          local.get 0
          local.get 7
          i32.add
          local.tee 19
          local.set 9
          local.get 8
          local.tee 20
          local.get 18
          i32.sub
          local.set 10
          local.get 6
          local.get 5
          i32.ge_u
          if  ;; label = @4
            block  ;; label = @5
              local.get 5
              local.tee 13
              i32.const 2
              i32.mul
              local.set 5
              i32.const 8
              local.tee 14
              local.get 5
              local.tee 15
              local.get 14
              i32.mul
              i32.add
              local.set 7
              local.get 7
              call $__malloc
              local.set 7
              local.get 4
              i32.const 8
              local.get 6
              i32.const 8
              i32.mul
              i32.add
              local.get 7
              call $dynrt__fn3
              local.get 7
              local.tee 16
              local.set 4
              local.get 4
              local.get 5
              i32.store offset=4
            end
          end
          local.get 4
          i32.const 8
          local.get 6
          i32.const 8
          i32.mul
          i32.add
          i32.add
          local.get 9
          i32.store
          local.get 4
          i32.const 8
          local.get 6
          i32.const 8
          i32.mul
          i32.add
          i32.add
          local.get 10
          i32.store offset=4
          local.get 6
          local.tee 21
          i32.const 1
          i32.add
          local.set 6
          local.get 8
          local.tee 22
          local.get 3
          local.tee 23
          i32.add
          local.set 7
          local.get 7
          local.get 1
          i32.gt_u
          if  ;; label = @4
            br 3 (;@1;)
          end
          br 1 (;@2;)
        end
      end
    end
    local.get 6
    local.get 5
    i32.ge_u
    if  ;; label = @1
      block  ;; label = @2
        local.get 5
        local.tee 24
        i32.const 2
        i32.mul
        local.set 5
        i32.const 8
        local.tee 25
        local.get 5
        local.tee 26
        local.get 25
        i32.mul
        i32.add
        local.set 7
        local.get 7
        call $__malloc
        local.set 7
        local.get 4
        i32.const 8
        local.get 6
        i32.const 8
        i32.mul
        i32.add
        local.get 7
        call $dynrt__fn3
        local.get 7
        local.tee 27
        local.set 4
        local.get 4
        local.get 5
        i32.store offset=4
      end
    end
    local.get 4
    i32.const 8
    local.get 6
    i32.const 8
    i32.mul
    i32.add
    i32.add
    local.get 9
    i32.store
    local.get 4
    i32.const 8
    local.get 6
    i32.const 8
    i32.mul
    i32.add
    i32.add
    local.get 10
    i32.store offset=4
    local.get 6
    local.tee 29
    i32.const 1
    i32.add
    local.set 6
    local.get 4
    local.get 6
    i32.store
    local.get 4
    local.tee 30)
  (func $dynrt__fn18 (param i32) (result f64)
    local.get 0
    i32.const 0
    i32.le_s
    if  ;; label = @1
      f64.const 0x1.0p+0 (;=1;)
      return
    end
    local.get 0
    i32.const 1
    i32.eq
    if  ;; label = @1
      f64.const 0x1.4p+3 (;=10;)
      return
    end
    local.get 0
    i32.const 2
    i32.eq
    if  ;; label = @1
      f64.const 0x1.9p+6 (;=100;)
      return
    end
    local.get 0
    i32.const 3
    i32.eq
    if  ;; label = @1
      f64.const 0x1.f4p+9 (;=1000;)
      return
    end
    local.get 0
    i32.const 4
    i32.eq
    if  ;; label = @1
      f64.const 0x1.388p+13 (;=10000;)
      return
    end
    local.get 0
    i32.const 5
    i32.eq
    if  ;; label = @1
      f64.const 0x1.86ap+16 (;=100000;)
      return
    end
    local.get 0
    i32.const 6
    i32.eq
    if  ;; label = @1
      f64.const 0x1.e848p+19 (;=1000000;)
      return
    end
    local.get 0
    i32.const 7
    i32.eq
    if  ;; label = @1
      f64.const 0x1.312dp+23 (;=10000000;)
      return
    end
    local.get 0
    i32.const 8
    i32.eq
    if  ;; label = @1
      f64.const 0x1.7d784p+26 (;=100000000;)
      return
    end
    local.get 0
    i32.const 9
    i32.eq
    if  ;; label = @1
      f64.const 0x1.dcd65p+29 (;=1000000000;)
      return
    end
    local.get 0
    i32.const 10
    i32.eq
    if  ;; label = @1
      f64.const 0x1.2a05f2p+33 (;=10000000000;)
      return
    end
    local.get 0
    i32.const 11
    i32.eq
    if  ;; label = @1
      f64.const 0x1.74876e8p+36 (;=100000000000;)
      return
    end
    local.get 0
    i32.const 12
    i32.eq
    if  ;; label = @1
      f64.const 0x1.d1a94a2p+39 (;=1000000000000;)
      return
    end
    local.get 0
    i32.const 13
    i32.eq
    if  ;; label = @1
      f64.const 0x1.2309ce54p+43 (;=10000000000000;)
      return
    end
    local.get 0
    i32.const 14
    i32.eq
    if  ;; label = @1
      f64.const 0x1.6bcc41e9p+46 (;=100000000000000;)
      return
    end
    f64.const 0x1.c6bf52634p+49 (;=1000000000000000;))
  (func $dynrt__fn19 (param f64 i32) (result i32)
    (local i32) (local i64) (local i64) (local i32) (local i32) (local i64) (local f64) (local i32) (local i64) (local i64) (local i32) (local i64) (local i64) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local f64) (local i32) (local f64) (local i64) (local i64) (local i64) (local i32) (local i32)
    local.get 1
    local.tee 20
    local.set 5
    local.get 0
    f64.const 0x0p+0 (;=0;)
    f64.lt
    if  ;; label = @1
      block  ;; label = @2
        local.get 5
        i32.const 45
        i32.store8
        local.get 5
        local.tee 9
        i32.const 1
        i32.add
        local.set 5
        local.get 0
        f64.neg
        local.set 0
      end
    end
    local.get 0
    local.tee 21
    i64.trunc_f64_s
    local.set 3
    local.get 3
    local.get 5
    call $dynrt__fn20
    i32.const 1
    i32.sub
    local.set 2
    local.get 5
    local.tee 22
    local.get 2
    i32.add
    local.set 5
    local.get 0
    local.tee 23
    local.get 3
    local.tee 24
    f64.convert_i64_s
    f64.sub
    f64.const 0x1.c6bf52634p+49 (;=1000000000000000;)
    f64.mul
    f64.nearest
    i64.trunc_f64_s
    local.set 4
    local.get 4
    local.tee 25
    local.set 4
    i32.const 15
    local.set 6
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 6
          i32.const 1
          i32.le_s
          br_if 2 (;@1;)
          local.get 4
          i64.const 10
          i64.div_u
          local.set 7
          local.get 3
          f64.convert_i64_s
          local.get 7
          local.tee 10
          f64.convert_i64_s
          local.get 6
          i32.const 1
          i32.sub
          call $dynrt__fn18
          f64.div
          f64.add
          local.set 8
          local.get 8
          local.get 0
          f64.ne
          if  ;; label = @4
            br 3 (;@1;)
          end
          local.get 7
          local.tee 11
          local.set 4
          local.get 6
          i32.const 1
          i32.sub
          local.tee 12
          local.set 6
          br 1 (;@2;)
        end
      end
    end
    local.get 4
    local.tee 26
    local.set 4
    local.get 4
    i64.const 0
    i64.ne
    if  ;; label = @1
      block  ;; label = @2
        local.get 5
        i32.const 46
        i32.store8
        local.get 5
        local.tee 16
        i32.const 1
        i32.add
        local.set 5
        local.get 4
        local.set 3
        local.get 6
        local.tee 17
        local.set 2
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 2
              i32.eqz
              br_if 2 (;@3;)
              local.get 5
              local.get 2
              i32.const 1
              i32.sub
              i32.add
              i32.const 48
              local.get 3
              i64.const 10
              i64.rem_u
              i32.wrap_i64
              i32.add
              i32.store8
              local.get 3
              local.tee 13
              i64.const 10
              local.tee 14
              i64.div_u
              local.set 3
              local.get 2
              i32.const 1
              i32.sub
              local.tee 15
              local.set 2
              br 1 (;@4;)
            end
          end
        end
        local.get 6
        local.tee 18
        local.set 2
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 2
              i32.eqz
              br_if 2 (;@3;)
              local.get 5
              local.get 2
              i32.const 1
              i32.sub
              i32.add
              i32.load8_u
              i32.const 48
              i32.ne
              br_if 2 (;@3;)
              local.get 2
              i32.const 1
              i32.sub
              local.set 2
              br 1 (;@4;)
            end
          end
        end
        local.get 5
        local.tee 19
        local.get 2
        i32.add
        local.set 5
      end
    end
    local.get 5
    local.tee 27
    local.get 1
    local.tee 28
    i32.sub)
  (func $dynrt__fn20 (param i64 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i64) (local i64) (local i64) (local i64) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 1
    local.tee 18
    local.set 6
    local.get 18
    local.set 2
    local.get 0
    i64.eqz
    if  ;; label = @1
      block  ;; label = @2
        local.get 1
        i32.const 48
        i32.store8
        local.get 1
        i32.const 1
        i32.add
        i32.const 110
        i32.store8
        i32.const 2
        return
      end
    end
    local.get 0
    i64.const 0
    i64.lt_s
    if  ;; label = @1
      block  ;; label = @2
        local.get 1
        i32.const 45
        i32.store8
        local.get 1
        local.tee 7
        i32.const 1
        local.tee 8
        i32.add
        local.set 1
        local.get 1
        local.tee 9
        local.set 2
        i64.const 0
        local.get 0
        i64.sub
        local.set 0
      end
    end
    local.get 1
    local.tee 19
    local.set 3
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 0
          i64.eqz
          br_if 2 (;@1;)
          local.get 0
          local.tee 10
          i64.const 10
          local.tee 11
          i64.rem_u
          i32.wrap_i64
          local.set 4
          local.get 3
          i32.const 48
          local.get 4
          i32.add
          i32.store8
          local.get 0
          local.tee 12
          i64.const 10
          local.tee 13
          i64.div_u
          local.set 0
          local.get 3
          local.tee 14
          i32.const 1
          i32.add
          local.set 3
          br 1 (;@2;)
        end
      end
    end
    local.get 2
    local.set 2
    local.get 3
    local.tee 20
    i32.const 1
    local.tee 21
    i32.sub
    local.set 4
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 2
          local.get 4
          i32.ge_u
          br_if 2 (;@1;)
          local.get 2
          i32.load8_u
          local.set 5
          local.get 2
          local.get 4
          i32.load8_u
          i32.store8
          local.get 4
          local.get 5
          i32.store8
          local.get 2
          local.tee 15
          i32.const 1
          local.tee 16
          i32.add
          local.set 2
          local.get 4
          local.tee 17
          local.get 16
          i32.sub
          local.set 4
          br 1 (;@2;)
        end
      end
    end
    local.get 3
    i32.const 110
    i32.store8
    local.get 3
    local.tee 22
    i32.const 1
    local.tee 23
    i32.add
    local.set 3
    local.get 3
    local.tee 24
    local.get 6
    i32.sub)
  (func $dynrt__fn21 (param f64 f64) (result f64)
    (local f64) (local i32)
    local.get 1
    f64.const 0x1.0p-1 (;=0.5;)
    f64.eq
    if  ;; label = @1
      local.get 0
      f64.sqrt
      return
    end
    local.get 1
    f64.const -0x1.0p-1 (;=-0.5;)
    f64.eq
    if  ;; label = @1
      f64.const 0x1.0p+0 (;=1;)
      local.get 0
      f64.sqrt
      f64.div
      return
    end
    f64.const 0x1.0p+0 (;=1;)
    local.set 2
    local.get 1
    i32.trunc_f64_s
    local.set 3
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 3
          i32.const 0
          i32.le_s
          br_if 2 (;@1;)
          local.get 2
          local.get 0
          f64.mul
          local.set 2
          local.get 3
          i32.const 1
          i32.sub
          local.set 3
          br 1 (;@2;)
        end
      end
    end
    local.get 2)
  (func $dynrt__fn22 (param i32 i32) (result f64)
    (local i32) (local i32) (local i32) (local f64) (local f64) (local f64) (local i32) (local i32) (local i32) (local i32) (local i32) (local f64) (local f64) (local i32) (local i32) (local i32) (local f64) (local f64) (local f64)
    f64.const 0x1.0p+0 (;=1;)
    local.tee 20
    local.set 5
    f64.const 0x0p+0 (;=0;)
    local.set 6
    local.get 20
    local.set 7
    i32.const 1
    local.set 8
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 2
          local.get 1
          i32.ge_u
          br_if 2 (;@1;)
          local.get 0
          local.get 2
          i32.add
          i32.load8_u
          local.set 3
          local.get 3
          i32.const 32
          i32.eq
          local.get 3
          i32.const 9
          i32.eq
          local.get 3
          i32.const 10
          i32.eq
          local.get 3
          i32.const 13
          i32.eq
          i32.or
          i32.or
          i32.or
          i32.eqz
          br_if 2 (;@1;)
          local.get 2
          local.tee 10
          i32.const 1
          i32.add
          local.set 2
          br 1 (;@2;)
        end
      end
    end
    local.get 2
    local.get 1
    i32.lt_u
    if  ;; label = @1
      block  ;; label = @2
        local.get 0
        local.get 2
        i32.add
        i32.load8_u
        local.set 3
        local.get 3
        i32.const 45
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            f64.const -0x1.0p+0 (;=-1;)
            local.set 5
            local.get 2
            i32.const 1
            i32.add
            local.set 2
          end
        else
          local.get 3
          i32.const 43
          i32.eq
          if  ;; label = @4
            local.get 2
            i32.const 1
            i32.add
            local.set 2
          end
        end
      end
    end
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 2
          local.get 1
          i32.ge_u
          br_if 2 (;@1;)
          local.get 0
          local.get 2
          i32.add
          i32.load8_u
          local.set 3
          local.get 3
          i32.const 48
          i32.lt_u
          local.get 3
          i32.const 57
          i32.gt_u
          i32.or
          br_if 2 (;@1;)
          local.get 6
          f64.const 0x1.4p+3 (;=10;)
          f64.mul
          local.get 3
          i32.const 48
          i32.sub
          f64.convert_i32_s
          f64.add
          local.set 6
          local.get 4
          i32.const 1
          local.tee 11
          i32.add
          local.set 4
          local.get 2
          local.tee 12
          local.get 11
          i32.add
          local.set 2
          br 1 (;@2;)
        end
      end
    end
    local.get 2
    local.get 1
    i32.lt_u
    if  ;; label = @1
      local.get 0
      local.get 2
      i32.add
      i32.load8_u
      i32.const 46
      i32.eq
      if  ;; label = @2
        block  ;; label = @3
          local.get 2
          i32.const 1
          i32.add
          local.set 2
          block  ;; label = @4
            loop  ;; label = @5
              block  ;; label = @6
                local.get 2
                local.get 1
                i32.ge_u
                br_if 2 (;@4;)
                local.get 0
                local.get 2
                i32.add
                i32.load8_u
                local.set 3
                local.get 3
                i32.const 48
                i32.lt_u
                local.get 3
                i32.const 57
                i32.gt_u
                i32.or
                br_if 2 (;@4;)
                local.get 7
                local.tee 13
                f64.const 0x1.4p+3 (;=10;)
                f64.mul
                local.set 7
                local.get 6
                local.get 3
                i32.const 48
                i32.sub
                f64.convert_i32_s
                local.get 7
                local.tee 14
                f64.div
                f64.add
                local.set 6
                local.get 4
                i32.const 1
                local.tee 15
                i32.add
                local.set 4
                local.get 2
                local.tee 16
                local.get 15
                i32.add
                local.set 2
                br 1 (;@5;)
              end
            end
          end
        end
      end
    end
    local.get 4
    i32.const 0
    i32.gt_s
    local.get 2
    local.get 1
    i32.lt_u
    i32.and
    if  ;; label = @1
      block  ;; label = @2
        local.get 0
        local.get 2
        i32.add
        i32.load8_u
        local.set 3
        local.get 3
        i32.const 101
        i32.eq
        local.get 3
        i32.const 69
        i32.eq
        i32.or
        if  ;; label = @3
          block  ;; label = @4
            local.get 2
            i32.const 1
            i32.add
            local.set 2
            local.get 2
            local.get 1
            i32.lt_u
            if  ;; label = @5
              block  ;; label = @6
                local.get 0
                local.get 2
                i32.add
                i32.load8_u
                local.set 3
                local.get 3
                i32.const 45
                i32.eq
                if  ;; label = @7
                  block  ;; label = @8
                    i32.const -1
                    local.set 8
                    local.get 2
                    i32.const 1
                    i32.add
                    local.set 2
                  end
                else
                  local.get 3
                  i32.const 43
                  i32.eq
                  if  ;; label = @8
                    local.get 2
                    i32.const 1
                    i32.add
                    local.set 2
                  end
                end
              end
            end
            block  ;; label = @5
              loop  ;; label = @6
                block  ;; label = @7
                  local.get 2
                  local.get 1
                  i32.ge_u
                  br_if 2 (;@5;)
                  local.get 0
                  local.get 2
                  i32.add
                  i32.load8_u
                  local.set 3
                  local.get 3
                  i32.const 48
                  i32.lt_u
                  local.get 3
                  i32.const 57
                  i32.gt_u
                  i32.or
                  br_if 2 (;@5;)
                  local.get 9
                  i32.const 10
                  i32.mul
                  local.get 3
                  i32.const 48
                  i32.sub
                  i32.add
                  local.set 9
                  local.get 2
                  local.tee 17
                  i32.const 1
                  i32.add
                  local.set 2
                  br 1 (;@6;)
                end
              end
            end
          end
        end
      end
    end
    local.get 4
    i32.eqz
    if (result f64)  ;; label = @1
      f64.const nan (;=NaN;)
    else
      block (result f64)  ;; label = @2
        local.get 5
        local.get 6
        local.tee 18
        f64.mul
        local.set 6
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 9
              i32.eqz
              br_if 2 (;@3;)
              local.get 8
              i32.const 0
              i32.gt_s
              if  ;; label = @6
                local.get 6
                f64.const 0x1.4p+3 (;=10;)
                f64.mul
                local.set 6
              else
                local.get 6
                f64.const 0x1.4p+3 (;=10;)
                f64.div
                local.set 6
              end
              local.get 9
              i32.const 1
              i32.sub
              local.set 9
              br 1 (;@4;)
            end
          end
        end
        local.get 6
        local.tee 19
      end
    end)
  (func $dynrt_dynUndefined (result i32)
    (local i32) (local i32)
    call $dynrt__fn46
    local.set 0
    local.get 0
    i32.const 8
    i32.add
    i32.const 0
    i32.store
    local.get 0
    local.tee 1
    return)
  (func $dynrt_dynNull (result i32)
    (local i32) (local i32)
    call $dynrt__fn46
    local.set 0
    local.get 0
    i32.const 8
    i32.add
    i32.const 1
    i32.store
    local.get 0
    local.tee 1
    return)
  (func $dynrt_dynBool (param i32) (result i32)
    (local i32) (local i32)
    call $dynrt__fn46
    local.set 1
    local.get 1
    i32.const 8
    i32.add
    i32.const 2
    i32.store
    local.get 1
    i32.const 8
    i32.add
    i32.const 4
    i32.add
    local.get 0
    i32.eqz
    if (result i32)  ;; label = @1
      i32.const 0
    else
      i32.const 1
    end
    i32.store
    local.get 1
    local.tee 2
    return)
  (func $dynrt_dynNumber (param f64) (result i32)
    (local i32) (local i32) (local i32)
    i32.const 16
    call $dynrt__fn38
    local.set 1
    local.get 1
    i32.const 8
    i32.add
    local.get 0
    f64.store
    call $dynrt__fn46
    local.set 2
    local.get 2
    i32.const 8
    i32.add
    i32.const 3
    i32.store
    local.get 2
    i32.const 8
    i32.add
    i32.const 4
    i32.add
    local.get 1
    i32.store
    local.get 2
    local.tee 3
    return)
  (func $dynrt_dynString (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 1
    local.set 2
    i32.const 8
    local.get 2
    i32.add
    call $dynrt__fn38
    local.set 3
    i32.const 0
    local.set 4
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 4
          local.get 2
          i32.lt_s
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 3
            i32.const 8
            i32.add
            local.get 4
            i32.add
            local.get 0
            local.get 1
            local.get 4
            call $dynrt__fn8
            i32.store8
            local.get 4
            local.tee 5
            i32.const 1
            i32.add
            local.set 4
          end
          br 1 (;@2;)
        end
      end
    end
    call $dynrt__fn46
    local.set 4
    local.get 4
    i32.const 8
    i32.add
    i32.const 4
    i32.store
    local.get 4
    i32.const 8
    i32.add
    i32.const 4
    i32.add
    local.get 3
    i32.store
    local.get 4
    i32.const 8
    i32.add
    i32.const 8
    i32.add
    local.get 2
    i32.store
    local.get 4
    local.tee 6
    return)
  (func $dynrt__fn28 (result i32)
    (local i32) (local i32)
    i32.const 8
    global.get $dynrt_global3
    i32.const 2
    i32.add
    i32.const 4
    i32.mul
    i32.add
    call $dynrt__fn38
    local.set 0
    local.get 0
    i32.const 8
    i32.add
    i32.const 0
    i32.store
    local.get 0
    i32.const 8
    i32.add
    i32.const 4
    i32.add
    global.get $dynrt_global3
    i32.store
    local.get 0
    local.tee 1
    return)
  (func $dynrt__fn29 (param i32) (result i32)
    (local i32)
    local.get 0
    local.set 1
    local.get 1
    i32.const 8
    i32.add
    i32.load
    return)
  (func $dynrt__fn30 (param i32 i32) (result i32)
    (local i32)
    local.get 0
    local.set 2
    local.get 2
    i32.const 8
    i32.add
    local.get 1
    i32.const 2
    i32.add
    i32.const 2
    i32.shl
    i32.add
    i32.load
    return)
  (func $dynrt__fn31 (param i32 i32 i32)
    (local i32)
    local.get 0
    local.set 3
    local.get 3
    i32.const 8
    i32.add
    local.get 1
    i32.const 2
    i32.add
    i32.const 2
    i32.shl
    i32.add
    local.get 2
    i32.store)
  (func $dynrt__fn32 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.tee 10
    local.set 2
    local.get 2
    i32.const 8
    i32.add
    i32.load
    local.set 3
    local.get 2
    i32.const 8
    i32.add
    i32.const 4
    i32.add
    i32.load
    local.set 4
    local.get 3
    local.get 4
    i32.ge_s
    if  ;; label = @1
      block  ;; label = @2
        local.get 4
        local.tee 7
        i32.const 2
        local.tee 8
        i32.mul
        local.set 4
        i32.const 8
        local.get 4
        i32.const 2
        i32.add
        i32.const 4
        i32.mul
        i32.add
        call $dynrt__fn38
        local.set 5
        local.get 5
        i32.const 8
        i32.add
        i32.const 4
        i32.add
        local.get 4
        i32.store
        i32.const 0
        local.set 4
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 4
              local.get 3
              i32.lt_s
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                local.get 5
                i32.const 8
                i32.add
                local.get 4
                i32.const 2
                i32.add
                i32.const 2
                i32.shl
                i32.add
                local.get 2
                i32.const 8
                i32.add
                local.get 4
                i32.const 2
                i32.add
                i32.const 2
                i32.shl
                i32.add
                i32.load
                i32.store
                local.get 4
                local.tee 6
                i32.const 1
                i32.add
                local.set 4
              end
              br 1 (;@4;)
            end
          end
        end
        local.get 5
        i32.const 8
        i32.add
        local.get 3
        i32.const 2
        i32.add
        i32.const 2
        i32.shl
        i32.add
        local.get 1
        i32.store
        local.get 5
        i32.const 8
        i32.add
        local.get 3
        i32.const 1
        i32.add
        i32.store
        local.get 5
        local.tee 9
        return
      end
    end
    local.get 2
    i32.const 8
    i32.add
    local.get 3
    i32.const 2
    i32.add
    i32.const 2
    i32.shl
    i32.add
    local.get 1
    i32.store
    local.get 2
    i32.const 8
    i32.add
    local.get 3
    i32.const 1
    i32.add
    i32.store
    local.get 0
    local.tee 11
    return)
  (func $dynrt__fn33 (param i32 i32)
    (local i32) (local i32)
    local.get 0
    local.set 2
    local.get 2
    i32.const 8
    i32.add
    local.get 1
    i32.store
    local.get 1
    i32.const 16
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 2
        i32.const 8
        i32.add
        i32.const 4
        i32.add
        global.get $dynrt_global6
        i32.store
        local.get 0
        global.set $dynrt_global6
      end
    else
      local.get 1
      i32.const 24
      i32.eq
      if  ;; label = @2
        block  ;; label = @3
          local.get 2
          i32.const 8
          i32.add
          i32.const 4
          i32.add
          global.get $dynrt_global7
          i32.store
          local.get 0
          global.set $dynrt_global7
        end
      else
        local.get 1
        i32.const 28
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 2
            i32.const 8
            i32.add
            i32.const 4
            i32.add
            global.get $dynrt_global8
            i32.store
            local.get 0
            global.set $dynrt_global8
          end
        else
          local.get 1
          i32.const 32
          i32.eq
          if  ;; label = @4
            block  ;; label = @5
              local.get 2
              i32.const 8
              i32.add
              i32.const 4
              i32.add
              global.get $dynrt_global9
              i32.store
              local.get 0
              global.set $dynrt_global9
            end
          else
            block  ;; label = @5
              local.get 2
              i32.const 8
              i32.add
              i32.const 4
              i32.add
              global.get $dynrt_global10
              i32.store
              local.get 0
              global.set $dynrt_global10
            end
          end
        end
      end
    end
    global.get $dynrt_global11
    i32.const 1
    i32.add
    global.set $dynrt_global11
    global.get $dynrt_global12
    local.get 1
    local.tee 3
    i32.add
    global.set $dynrt_global12)
  (func $dynrt__fn34 (param i32 i32)
    (local i32)
    local.get 1
    global.get $dynrt_global4
    i32.lt_s
    if (result i32)  ;; label = @1
      global.get $dynrt_global4
    else
      local.get 1
    end
    local.set 2
    local.get 0
    local.get 2
    call $dynrt__fn33
    global.get $dynrt_global11
    global.get $dynrt_global13
    i32.gt_s
    if  ;; label = @1
      call $dynrt__fn43
    end)
  (func $dynrt__fn35 (param i32 i32)
    (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.set 2
    local.get 1
    i32.const 8
    i32.sub
    i32.const 2
    i32.shr_s
    local.set 3
    i32.const 0
    local.set 4
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 4
          local.get 3
          i32.lt_s
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 2
            i32.const 8
            i32.add
            local.get 4
            i32.const 2
            i32.shl
            i32.add
            i32.const 0
            i32.store
            local.get 4
            local.tee 5
            i32.const 1
            i32.add
            local.set 4
          end
          br 1 (;@2;)
        end
      end
    end)
  (func $dynrt__fn36 (param i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32)
    i32.const 0
    local.set 1
    local.get 0
    i32.const 16
    i32.eq
    if  ;; label = @1
      global.get $dynrt_global6
      local.set 1
    else
      local.get 0
      i32.const 24
      i32.eq
      if  ;; label = @2
        global.get $dynrt_global7
        local.set 1
      else
        local.get 0
        i32.const 28
        i32.eq
        if  ;; label = @3
          global.get $dynrt_global8
          local.set 1
        else
          local.get 0
          i32.const 32
          i32.eq
          if  ;; label = @4
            global.get $dynrt_global9
            local.set 1
          end
        end
      end
    end
    local.get 1
    i32.eqz
    if  ;; label = @1
      i32.const 0
      return
    end
    local.get 1
    local.tee 3
    local.set 2
    local.get 2
    i32.const 8
    i32.add
    i32.const 4
    i32.add
    i32.load
    local.set 2
    local.get 0
    i32.const 16
    i32.eq
    if  ;; label = @1
      local.get 2
      global.set $dynrt_global6
    else
      local.get 0
      i32.const 24
      i32.eq
      if  ;; label = @2
        local.get 2
        global.set $dynrt_global7
      else
        local.get 0
        i32.const 28
        i32.eq
        if  ;; label = @3
          local.get 2
          global.set $dynrt_global8
        else
          local.get 2
          global.set $dynrt_global9
        end
      end
    end
    global.get $dynrt_global11
    i32.const 1
    i32.sub
    global.set $dynrt_global11
    global.get $dynrt_global12
    local.get 0
    local.tee 4
    i32.sub
    global.set $dynrt_global12
    local.get 1
    local.get 0
    call $dynrt__fn35
    local.get 1
    local.tee 5
    return)
  (func $dynrt__fn37 (param i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    global.get $dynrt_global10
    local.set 1
    i32.const 0
    local.tee 12
    local.set 2
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 1
          i32.const 0
          i32.ne
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 1
            local.tee 10
            local.set 3
            local.get 3
            i32.const 8
            i32.add
            i32.load
            local.set 4
            local.get 4
            local.get 0
            i32.ge_s
            if  ;; label = @5
              block  ;; label = @6
                local.get 3
                i32.const 8
                i32.add
                i32.const 4
                i32.add
                i32.load
                local.set 3
                local.get 2
                i32.eqz
                if  ;; label = @7
                  local.get 3
                  global.set $dynrt_global10
                else
                  block  ;; label = @8
                    local.get 2
                    local.tee 5
                    local.set 2
                    local.get 2
                    i32.const 8
                    i32.add
                    i32.const 4
                    i32.add
                    local.get 3
                    i32.store
                  end
                end
                global.get $dynrt_global11
                i32.const 1
                i32.sub
                global.set $dynrt_global11
                global.get $dynrt_global12
                local.get 4
                local.tee 6
                i32.sub
                global.set $dynrt_global12
                local.get 4
                local.tee 7
                local.get 0
                local.tee 8
                i32.sub
                local.set 2
                local.get 2
                global.get $dynrt_global4
                i32.ge_s
                if  ;; label = @7
                  local.get 1
                  local.get 0
                  i32.add
                  local.get 2
                  call $dynrt__fn33
                end
                local.get 1
                local.get 0
                call $dynrt__fn35
                local.get 1
                local.tee 9
                return
              end
            end
            local.get 1
            local.tee 11
            local.set 2
            local.get 3
            i32.const 8
            i32.add
            i32.const 4
            i32.add
            i32.load
            local.set 1
          end
          br 1 (;@2;)
        end
      end
    end
    i32.const 0
    local.tee 13
    return)
  (func $dynrt__fn38 (param i32) (result i32)
    (local i32) (local i32)
    local.get 0
    global.get $dynrt_global4
    i32.lt_s
    if (result i32)  ;; label = @1
      global.get $dynrt_global4
    else
      local.get 0
    end
    local.set 1
    local.get 1
    call $dynrt__fn36
    local.set 2
    local.get 2
    i32.const 0
    i32.ne
    if  ;; label = @1
      local.get 2
      return
    end
    local.get 1
    call $dynrt__fn37
    local.set 2
    local.get 2
    i32.const 0
    i32.ne
    if  ;; label = @1
      local.get 2
      return
    end
    global.get $dynrt_global12
    local.get 1
    i32.ge_s
    if  ;; label = @1
      block  ;; label = @2
        call $dynrt__fn43
        local.get 1
        call $dynrt__fn36
        local.set 2
        local.get 2
        i32.const 0
        i32.ne
        if  ;; label = @3
          local.get 2
          return
        end
        local.get 1
        call $dynrt__fn37
        local.set 2
        local.get 2
        i32.const 0
        i32.ne
        if  ;; label = @3
          local.get 2
          return
        end
      end
    end
    local.get 1
    call $__malloc
    return)
  (func $dynrt__fn39 (param i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.tee 6
    local.set 1
    local.get 6
    local.set 2
    local.get 2
    i32.const 8
    i32.add
    i32.const 4
    i32.add
    i32.load
    local.set 2
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 2
          i32.const 0
          i32.ne
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 2
            local.tee 5
            local.set 2
            local.get 2
            i32.const 8
            i32.add
            i32.const 4
            i32.add
            i32.load
            local.set 2
            local.get 2
            i32.const 0
            i32.ne
            if  ;; label = @5
              block  ;; label = @6
                local.get 1
                local.tee 3
                local.set 1
                local.get 1
                i32.const 8
                i32.add
                i32.const 4
                i32.add
                i32.load
                local.set 1
                local.get 2
                local.tee 4
                local.set 2
                local.get 2
                i32.const 8
                i32.add
                i32.const 4
                i32.add
                i32.load
                local.set 2
              end
            end
          end
          br 1 (;@2;)
        end
      end
    end
    local.get 1
    local.tee 7
    local.set 1
    local.get 1
    i32.const 8
    i32.add
    i32.const 4
    i32.add
    i32.load
    local.set 2
    local.get 1
    i32.const 8
    i32.add
    i32.const 4
    i32.add
    i32.const 0
    i32.store
    local.get 2
    local.tee 8
    return)
  (func $dynrt__fn40 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    i32.const 0
    local.tee 11
    local.set 2
    local.get 11
    local.set 3
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 0
          i32.const 0
          i32.ne
          if (result i32)  ;; label = @4
            local.get 1
            i32.const 0
            i32.ne
          else
            i32.const 0
          end
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 0
            local.get 1
            i32.lt_s
            if  ;; label = @5
              block  ;; label = @6
                local.get 0
                local.tee 6
                local.set 4
                local.get 6
                local.set 5
                local.get 5
                i32.const 8
                i32.add
                i32.const 4
                i32.add
                i32.load
                local.set 0
              end
            else
              block  ;; label = @6
                local.get 1
                local.tee 7
                local.set 4
                local.get 7
                local.set 5
                local.get 5
                i32.const 8
                i32.add
                i32.const 4
                i32.add
                i32.load
                local.set 1
              end
            end
            local.get 2
            i32.eqz
            if  ;; label = @5
              block  ;; label = @6
                local.get 4
                local.tee 8
                local.set 2
                local.get 8
                local.set 3
              end
            else
              block  ;; label = @6
                local.get 3
                local.tee 9
                local.set 3
                local.get 3
                i32.const 8
                i32.add
                i32.const 4
                i32.add
                local.get 4
                i32.store
                local.get 4
                local.tee 10
                local.set 3
              end
            end
          end
          br 1 (;@2;)
        end
      end
    end
    local.get 0
    local.set 4
    local.get 0
    i32.eqz
    if  ;; label = @1
      local.get 1
      local.set 4
    end
    local.get 2
    i32.eqz
    if  ;; label = @1
      local.get 4
      return
    end
    local.get 3
    local.tee 12
    local.set 3
    local.get 3
    i32.const 8
    i32.add
    i32.const 4
    i32.add
    local.get 4
    i32.store
    local.get 2
    return)
  (func $dynrt__fn41 (param i32) (result i32)
    (local i32) (local i32) (local i32)
    local.get 0
    i32.eqz
    if  ;; label = @1
      i32.const 0
      return
    end
    local.get 0
    local.tee 3
    local.set 1
    local.get 1
    i32.const 8
    i32.add
    i32.const 4
    i32.add
    i32.load
    i32.eqz
    if  ;; label = @1
      local.get 0
      return
    end
    local.get 0
    call $dynrt__fn39
    local.set 1
    local.get 0
    call $dynrt__fn41
    local.set 2
    local.get 1
    call $dynrt__fn41
    local.set 1
    local.get 2
    local.get 1
    call $dynrt__fn40
    return)
  (func $dynrt__fn42 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.set 2
    local.get 1
    local.set 3
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 2
          i32.const 0
          i32.ne
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 2
            local.tee 6
            local.set 4
            local.get 4
            i32.const 8
            i32.add
            i32.const 4
            i32.add
            i32.load
            local.set 5
            local.get 4
            i32.const 8
            i32.add
            i32.const 4
            i32.add
            local.get 3
            i32.store
            local.get 2
            local.tee 7
            local.set 3
            local.get 5
            local.set 2
          end
          br 1 (;@2;)
        end
      end
    end
    local.get 3
    return)
  (func $dynrt__fn43
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    i32.const 0
    local.tee 7
    local.set 0
    global.get $dynrt_global6
    local.get 0
    call $dynrt__fn42
    local.set 0
    global.get $dynrt_global7
    local.get 0
    call $dynrt__fn42
    local.set 0
    global.get $dynrt_global8
    local.get 0
    call $dynrt__fn42
    local.set 0
    global.get $dynrt_global9
    local.get 0
    call $dynrt__fn42
    local.set 0
    global.get $dynrt_global10
    local.get 0
    call $dynrt__fn42
    local.set 0
    i32.const 0
    local.tee 8
    global.set $dynrt_global6
    i32.const 0
    local.tee 9
    global.set $dynrt_global7
    i32.const 0
    local.tee 10
    global.set $dynrt_global8
    i32.const 0
    local.tee 11
    global.set $dynrt_global9
    i32.const 0
    local.tee 12
    global.set $dynrt_global10
    i32.const 0
    local.tee 13
    global.set $dynrt_global11
    i32.const 0
    local.tee 14
    global.set $dynrt_global12
    local.get 0
    call $dynrt__fn41
    local.set 0
    local.get 0
    local.tee 15
    local.set 1
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 1
          i32.const 0
          i32.ne
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 1
            local.set 2
            local.get 2
            i32.const 8
            i32.add
            i32.const 4
            i32.add
            i32.load
            local.set 3
            i32.const 1
            local.set 4
            block  ;; label = @5
              loop  ;; label = @6
                block  ;; label = @7
                  local.get 4
                  i32.const 1
                  i32.eq
                  if (result i32)  ;; label = @8
                    local.get 3
                    i32.const 0
                    i32.ne
                  else
                    i32.const 0
                  end
                  i32.eqz
                  br_if 2 (;@5;)
                  block  ;; label = @8
                    local.get 3
                    local.set 5
                    local.get 1
                    local.get 2
                    i32.const 8
                    i32.add
                    i32.load
                    i32.add
                    local.get 3
                    i32.eq
                    if  ;; label = @9
                      block  ;; label = @10
                        local.get 2
                        i32.const 8
                        i32.add
                        local.get 2
                        i32.const 8
                        i32.add
                        i32.load
                        local.get 5
                        i32.const 8
                        i32.add
                        i32.load
                        i32.add
                        i32.store
                        local.get 2
                        i32.const 8
                        i32.add
                        i32.const 4
                        i32.add
                        local.get 5
                        i32.const 8
                        i32.add
                        i32.const 4
                        i32.add
                        i32.load
                        i32.store
                        local.get 2
                        i32.const 8
                        i32.add
                        i32.const 4
                        i32.add
                        i32.load
                        local.set 3
                      end
                    else
                      i32.const 0
                      local.set 4
                    end
                  end
                  br 1 (;@6;)
                end
              end
            end
            local.get 2
            i32.const 8
            i32.add
            i32.const 4
            i32.add
            i32.load
            local.set 1
          end
          br 1 (;@2;)
        end
      end
    end
    local.get 0
    local.tee 16
    local.set 0
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 0
          i32.const 0
          i32.ne
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 0
            local.tee 6
            local.set 1
            local.get 1
            i32.const 8
            i32.add
            i32.const 4
            i32.add
            i32.load
            local.set 2
            local.get 1
            i32.const 8
            i32.add
            i32.load
            local.set 1
            local.get 0
            local.get 1
            call $dynrt__fn33
            local.get 2
            local.set 0
          end
          br 1 (;@2;)
        end
      end
    end
    global.get $dynrt_global11
    i32.const 2
    i32.mul
    local.set 0
    local.get 0
    global.get $dynrt_global5
    i32.lt_s
    if  ;; label = @1
      global.get $dynrt_global5
      local.set 0
    end
    local.get 0
    local.tee 17
    global.set $dynrt_global13)
  (func $dynrt_dynGcCheckHeap (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    i32.const 0
    local.tee 7
    local.set 0
    local.get 7
    local.set 1
    i32.const 100000000
    local.set 2
    local.get 7
    local.set 3
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 3
          i32.const 5
          i32.lt_s
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 3
            i32.eqz
            if  ;; label = @5
              global.get $dynrt_global6
              local.set 4
            else
              local.get 3
              i32.const 1
              i32.eq
              if  ;; label = @6
                global.get $dynrt_global7
                local.set 4
              else
                local.get 3
                i32.const 2
                i32.eq
                if  ;; label = @7
                  global.get $dynrt_global8
                  local.set 4
                else
                  local.get 3
                  i32.const 3
                  i32.eq
                  if  ;; label = @8
                    global.get $dynrt_global9
                    local.set 4
                  else
                    global.get $dynrt_global10
                    local.set 4
                  end
                end
              end
            end
            block  ;; label = @5
              loop  ;; label = @6
                block  ;; label = @7
                  local.get 4
                  i32.const 0
                  i32.ne
                  i32.eqz
                  br_if 2 (;@5;)
                  block  ;; label = @8
                    local.get 2
                    i32.const 0
                    i32.le_s
                    if  ;; label = @9
                      i32.const 1
                      return
                    end
                    local.get 2
                    i32.const 1
                    local.tee 5
                    i32.sub
                    local.set 2
                    local.get 4
                    local.tee 6
                    local.set 4
                    local.get 4
                    i32.const 8
                    i32.add
                    i32.load
                    global.get $dynrt_global4
                    i32.lt_s
                    if  ;; label = @9
                      i32.const 4
                      return
                    end
                    local.get 1
                    local.get 4
                    i32.const 8
                    i32.add
                    i32.load
                    i32.add
                    local.set 1
                    local.get 0
                    local.get 5
                    i32.add
                    local.set 0
                    local.get 4
                    i32.const 8
                    i32.add
                    i32.const 4
                    i32.add
                    i32.load
                    local.set 4
                  end
                  br 1 (;@6;)
                end
              end
            end
            local.get 3
            i32.const 1
            i32.add
            local.set 3
          end
          br 1 (;@2;)
        end
      end
    end
    local.get 0
    global.get $dynrt_global11
    i32.ne
    if  ;; label = @1
      i32.const 2
      return
    end
    local.get 1
    global.get $dynrt_global12
    i32.ne
    if  ;; label = @1
      i32.const 3
      return
    end
    local.get 7
    return)
  (func $dynrt__fn45 (param i32)
    global.get $dynrt_global15
    i32.eqz
    if  ;; label = @1
      call $dynrt__fn28
      global.set $dynrt_global15
    end
    global.get $dynrt_global15
    local.get 0
    call $dynrt__fn32
    global.set $dynrt_global15)
  (func $dynrt__fn46 (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    i32.const 24
    call $dynrt__fn38
    local.set 0
    global.get $dynrt_global15
    i32.eqz
    if  ;; label = @1
      call $dynrt__fn28
      global.set $dynrt_global15
    end
    global.get $dynrt_global15
    local.set 1
    local.get 1
    i32.const 8
    i32.add
    i32.load
    local.set 2
    local.get 2
    local.get 1
    i32.const 8
    i32.add
    i32.const 4
    i32.add
    i32.load
    i32.ge_s
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_global15
        local.tee 3
        local.set 2
        i32.const 8
        local.tee 4
        local.get 1
        i32.const 8
        i32.add
        i32.const 4
        i32.add
        i32.load
        i32.const 2
        i32.add
        i32.const 4
        local.tee 5
        i32.mul
        i32.add
        local.set 1
        global.get $dynrt_global15
        local.get 0
        call $dynrt__fn32
        global.set $dynrt_global15
        local.get 2
        local.get 1
        call $dynrt__fn34
      end
    else
      block  ;; label = @2
        local.get 1
        i32.const 8
        i32.add
        local.get 2
        i32.const 2
        i32.add
        i32.const 2
        i32.shl
        i32.add
        local.get 0
        i32.store
        local.get 1
        i32.const 8
        i32.add
        local.get 2
        i32.const 1
        i32.add
        i32.store
      end
    end
    local.get 0
    return)
  (func $dynrt__fn47 (result i32)
    (local i32) (local i32)
    i32.const 28
    call $dynrt__fn38
    local.set 0
    local.get 0
    call $dynrt__fn45
    local.get 0
    local.tee 1
    return)
  (func $dynrt_dynGcCellCount (result i32)
    global.get $dynrt_global15
    i32.eqz
    if  ;; label = @1
      i32.const 0
      return
    end
    global.get $dynrt_global15
    call $dynrt__fn29
    return)
  (func $dynrt__fn49 (param i32) (result i32)
    (local i32)
    local.get 0
    local.set 1
    local.get 1
    i32.const 8
    i32.add
    i32.load
    global.get $dynrt_global16
    i32.and
    i32.eqz
    if (result i32)  ;; label = @1
      i32.const 0
    else
      i32.const 1
    end
    return)
  (func $dynrt__fn50 (param i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    i32.eqz
    if (result i32)  ;; label = @1
      i32.const 1
    else
      local.get 0
      i32.const -1
      i32.eq
    end
    if  ;; label = @1
      return
    end
    local.get 0
    call $dynrt__fn49
    i32.const 1
    i32.eq
    if  ;; label = @1
      return
    end
    local.get 0
    local.set 1
    local.get 1
    i32.const 8
    i32.add
    local.get 1
    i32.const 8
    i32.add
    i32.load
    global.get $dynrt_global16
    i32.or
    i32.store
    local.get 1
    i32.const 8
    i32.add
    i32.load
    i32.const 255
    i32.and
    local.set 2
    local.get 2
    i32.const 5
    i32.eq
    if (result i32)  ;; label = @1
      i32.const 1
    else
      local.get 2
      i32.const 6
      i32.eq
    end
    if  ;; label = @1
      block  ;; label = @2
        local.get 1
        i32.const 8
        i32.add
        i32.const 4
        i32.add
        i32.load
        local.set 3
        local.get 3
        call $dynrt__fn29
        local.set 4
        i32.const 0
        local.set 5
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 5
              local.get 4
              i32.lt_s
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                local.get 3
                local.get 5
                call $dynrt__fn30
                call $dynrt__fn50
                local.get 5
                local.tee 6
                i32.const 1
                i32.add
                local.set 5
              end
              br 1 (;@4;)
            end
          end
        end
        local.get 2
        i32.const 6
        i32.eq
        if  ;; label = @3
          local.get 1
          i32.const 8
          i32.add
          i32.const 8
          i32.add
          i32.load
          call $dynrt__fn50
        end
      end
    else
      local.get 2
      i32.const 7
      i32.eq
      if  ;; label = @2
        local.get 1
        i32.const 8
        i32.add
        i32.const 4
        i32.add
        i32.load
        i32.const -1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 1
            i32.const 8
            i32.add
            i32.const 8
            i32.add
            i32.load
            call $dynrt__fn50
            local.get 1
            i32.const 8
            i32.add
            i32.const 12
            i32.add
            i32.load
            call $dynrt__fn50
            local.get 1
            i32.const 8
            i32.add
            i32.const 16
            i32.add
            i32.load
            call $dynrt__fn50
          end
        end
      end
    end)
  (func $dynrt_dynGcMarkClear
    (local i32) (local i32) (local i32) (local i32) (local i32)
    global.get $dynrt_global15
    i32.eqz
    if  ;; label = @1
      return
    end
    global.get $dynrt_global15
    call $dynrt__fn29
    local.set 0
    i32.const 0
    local.set 1
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 1
          local.get 0
          i32.lt_s
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            global.get $dynrt_global15
            local.get 1
            call $dynrt__fn30
            local.set 2
            local.get 2
            local.tee 3
            local.set 2
            local.get 2
            i32.const 8
            i32.add
            local.get 2
            i32.const 8
            i32.add
            i32.load
            i32.const 255
            i32.and
            i32.store
            local.get 1
            local.tee 4
            i32.const 1
            i32.add
            local.set 1
          end
          br 1 (;@2;)
        end
      end
    end)
  (func $dynrt_dynGcMark (param i32)
    local.get 0
    call $dynrt__fn50)
  (func $dynrt_dynGcMarkedCount (result i32)
    (local i32) (local i32) (local i32) (local i32)
    global.get $dynrt_global15
    i32.eqz
    if  ;; label = @1
      i32.const 0
      return
    end
    global.get $dynrt_global15
    call $dynrt__fn29
    local.set 0
    i32.const 0
    local.tee 3
    local.set 1
    local.get 3
    local.set 2
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 2
          local.get 0
          i32.lt_s
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            global.get $dynrt_global15
            local.get 2
            call $dynrt__fn30
            call $dynrt__fn49
            i32.const 1
            i32.eq
            if  ;; label = @5
              local.get 1
              i32.const 1
              i32.add
              local.set 1
            end
            local.get 2
            i32.const 1
            i32.add
            local.set 2
          end
          br 1 (;@2;)
        end
      end
    end
    local.get 1
    return)
  (func $dynrt__fn54 (param i32)
    global.get $dynrt_global17
    i32.eqz
    if  ;; label = @1
      call $dynrt__fn28
      global.set $dynrt_global17
    end
    global.get $dynrt_global17
    local.get 0
    call $dynrt__fn32
    global.set $dynrt_global17)
  (func $dynrt__fn55
    (local i32)
    global.get $dynrt_global17
    i32.eqz
    if  ;; label = @1
      return
    end
    global.get $dynrt_global17
    local.set 0
    local.get 0
    i32.const 8
    i32.add
    i32.load
    i32.const 0
    i32.gt_s
    if  ;; label = @1
      local.get 0
      i32.const 8
      i32.add
      local.get 0
      i32.const 8
      i32.add
      i32.load
      i32.const 1
      i32.sub
      i32.store
    end)
  (func $dynrt_dynGcPushRoot (param i32)
    local.get 0
    call $dynrt__fn54)
  (func $dynrt_dynGcPopRoot
    call $dynrt__fn55)
  (func $dynrt_dynGcRootCount (result i32)
    global.get $dynrt_global17
    i32.eqz
    if  ;; label = @1
      i32.const 0
      return
    end
    global.get $dynrt_global17
    call $dynrt__fn29
    return)
  (func $dynrt_dynGcMarkRoots
    (local i32) (local i32) (local i32) (local i32)
    call $dynrt_dynGcMarkClear
    global.get $dynrt_global20
    call $dynrt__fn50
    global.get $dynrt_global25
    call $dynrt__fn50
    global.get $dynrt_global24
    call $dynrt__fn50
    global.get $dynrt_global17
    i32.eqz
    if  ;; label = @1
      return
    end
    global.get $dynrt_global17
    call $dynrt__fn29
    local.set 0
    i32.const 0
    local.set 1
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 1
          local.get 0
          i32.lt_s
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            global.get $dynrt_global17
            local.get 1
            call $dynrt__fn30
            call $dynrt__fn50
            local.get 1
            local.tee 2
            i32.const 1
            i32.add
            local.set 1
          end
          br 1 (;@2;)
        end
      end
    end
    global.get $dynrt_global18
    i32.const 0
    i32.ne
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_global18
        call $dynrt__fn29
        local.set 0
        i32.const 0
        local.set 1
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 1
              local.get 0
              i32.lt_s
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                global.get $dynrt_global18
                local.get 1
                call $dynrt__fn30
                call $dynrt__fn50
                local.get 1
                local.tee 3
                i32.const 1
                i32.add
                local.set 1
              end
              br 1 (;@4;)
            end
          end
        end
      end
    end)
  (func $dynrt_dynGcPin (param i32) (result i32)
    (local i32) (local i32) (local i32)
    global.get $dynrt_global18
    i32.eqz
    if  ;; label = @1
      call $dynrt__fn28
      global.set $dynrt_global18
    end
    global.get $dynrt_global18
    call $dynrt__fn29
    local.set 1
    i32.const 0
    local.set 2
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 2
          local.get 1
          i32.lt_s
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            global.get $dynrt_global18
            local.get 2
            call $dynrt__fn30
            i32.eqz
            if  ;; label = @5
              block  ;; label = @6
                global.get $dynrt_global18
                local.get 2
                local.get 0
                call $dynrt__fn31
                local.get 2
                local.tee 3
                return
              end
            end
            local.get 2
            i32.const 1
            i32.add
            local.set 2
          end
          br 1 (;@2;)
        end
      end
    end
    global.get $dynrt_global18
    local.get 0
    call $dynrt__fn32
    global.set $dynrt_global18
    local.get 1
    return)
  (func $dynrt_dynGcUnpin (param i32)
    global.get $dynrt_global18
    i32.eqz
    if  ;; label = @1
      return
    end
    local.get 0
    i32.const 0
    i32.lt_s
    if (result i32)  ;; label = @1
      i32.const 1
    else
      local.get 0
      global.get $dynrt_global18
      call $dynrt__fn29
      i32.ge_s
    end
    if  ;; label = @1
      return
    end
    global.get $dynrt_global18
    local.get 0
    i32.const 0
    call $dynrt__fn31)
  (func $dynrt__fn62 (param i32)
    (local i32) (local i32)
    local.get 0
    local.tee 2
    local.set 1
    local.get 0
    i32.const 8
    local.get 1
    i32.const 8
    i32.add
    i32.const 4
    i32.add
    i32.load
    i32.const 2
    i32.add
    i32.const 4
    i32.mul
    i32.add
    call $dynrt__fn34)
  (func $dynrt__fn63 (param i32)
    (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.set 1
    local.get 1
    i32.const 8
    i32.add
    i32.load
    i32.const 255
    i32.and
    local.set 2
    local.get 2
    i32.const 3
    i32.eq
    if  ;; label = @1
      local.get 1
      i32.const 8
      i32.add
      i32.const 4
      i32.add
      i32.load
      i32.const 16
      call $dynrt__fn34
    else
      local.get 2
      i32.const 4
      i32.eq
      if  ;; label = @2
        local.get 1
        i32.const 8
        i32.add
        i32.const 4
        i32.add
        i32.load
        i32.const 8
        local.get 1
        i32.const 8
        i32.add
        i32.const 8
        i32.add
        i32.load
        i32.add
        call $dynrt__fn34
      else
        local.get 2
        i32.const 5
        i32.eq
        if  ;; label = @3
          local.get 1
          i32.const 8
          i32.add
          i32.const 4
          i32.add
          i32.load
          call $dynrt__fn62
        else
          local.get 2
          i32.const 6
          i32.eq
          if  ;; label = @4
            block  ;; label = @5
              local.get 1
              i32.const 8
              i32.add
              i32.const 4
              i32.add
              i32.load
              call $dynrt__fn62
              local.get 1
              i32.const 8
              i32.add
              i32.const 12
              i32.add
              i32.load
              local.set 1
              local.get 1
              call $dynrt__fn29
              local.set 2
              i32.const 0
              local.set 3
              block  ;; label = @6
                loop  ;; label = @7
                  block  ;; label = @8
                    local.get 3
                    local.get 2
                    i32.lt_s
                    i32.eqz
                    br_if 2 (;@6;)
                    block  ;; label = @9
                      local.get 1
                      local.get 3
                      call $dynrt__fn30
                      i32.const 8
                      local.get 1
                      local.get 3
                      i32.const 1
                      i32.add
                      call $dynrt__fn30
                      i32.add
                      call $dynrt__fn34
                      local.get 3
                      local.tee 4
                      i32.const 2
                      i32.add
                      local.set 3
                    end
                    br 1 (;@7;)
                  end
                end
              end
              local.get 1
              call $dynrt__fn62
            end
          end
        end
      end
    end)
  (func $dynrt_dynGcCollect (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    call $dynrt_dynGcMarkRoots
    global.get $dynrt_global15
    i32.eqz
    if  ;; label = @1
      i32.const 0
      return
    end
    global.get $dynrt_global15
    local.set 0
    local.get 0
    i32.const 8
    i32.add
    i32.load
    local.set 1
    i32.const 0
    local.tee 9
    local.set 2
    local.get 9
    local.set 3
    local.get 9
    local.set 4
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 3
          local.get 1
          i32.lt_s
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 0
            i32.const 8
            i32.add
            local.get 3
            i32.const 2
            i32.add
            i32.const 2
            i32.shl
            i32.add
            i32.load
            local.set 5
            local.get 5
            local.set 6
            local.get 6
            i32.const 8
            i32.add
            i32.load
            global.get $dynrt_global16
            i32.and
            i32.const 0
            i32.ne
            if  ;; label = @5
              block  ;; label = @6
                local.get 6
                i32.const 8
                i32.add
                local.get 6
                i32.const 8
                i32.add
                i32.load
                i32.const 255
                i32.and
                i32.store
                local.get 0
                i32.const 8
                i32.add
                local.get 2
                i32.const 2
                i32.add
                i32.const 2
                i32.shl
                i32.add
                local.get 5
                i32.store
                local.get 2
                local.tee 7
                i32.const 1
                i32.add
                local.set 2
              end
            else
              block  ;; label = @6
                local.get 6
                i32.const 8
                i32.add
                i32.load
                i32.const 255
                i32.and
                i32.const 7
                i32.eq
                if (result i32)  ;; label = @7
                  local.get 6
                  i32.const 8
                  i32.add
                  i32.const 4
                  i32.add
                  i32.load
                  i32.const -1
                  i32.eq
                else
                  i32.const 0
                end
                if (result i32)  ;; label = @7
                  i32.const 28
                else
                  i32.const 24
                end
                local.set 6
                local.get 5
                call $dynrt__fn63
                local.get 5
                local.get 6
                call $dynrt__fn34
                local.get 4
                i32.const 1
                i32.add
                local.set 4
              end
            end
            local.get 3
            local.tee 8
            i32.const 1
            i32.add
            local.set 3
          end
          br 1 (;@2;)
        end
      end
    end
    local.get 0
    i32.const 8
    i32.add
    local.get 2
    i32.store
    local.get 4
    return)
  (func $dynrt_dynGcFreeCount (result i32)
    global.get $dynrt_global11
    return)
  (func $dynrt__fn66
    (local i32)
    call $dynrt_dynGcCellCount
    global.get $dynrt_global14
    i32.gt_s
    if  ;; label = @1
      block  ;; label = @2
        call $dynrt_dynGcCollect
        drop
        call $dynrt_dynGcCellCount
        local.set 0
        local.get 0
        i32.const 2
        i32.mul
        local.set 0
        local.get 0
        i32.const 8192
        i32.gt_s
        if (result i32)  ;; label = @3
          local.get 0
        else
          i32.const 8192
        end
        global.set $dynrt_global14
      end
    end)
  (func $dynrt_dynArray (result i32)
    (local i32) (local i32)
    call $dynrt__fn46
    local.set 0
    local.get 0
    i32.const 8
    i32.add
    i32.const 5
    i32.store
    local.get 0
    i32.const 8
    i32.add
    i32.const 4
    i32.add
    call $dynrt__fn28
    i32.store
    local.get 0
    local.tee 1
    return)
  (func $dynrt_dynObject (result i32)
    (local i32) (local i32)
    call $dynrt__fn46
    local.set 0
    local.get 0
    i32.const 8
    i32.add
    i32.const 6
    i32.store
    local.get 0
    i32.const 8
    i32.add
    i32.const 4
    i32.add
    call $dynrt__fn28
    i32.store
    local.get 0
    i32.const 8
    i32.add
    i32.const 12
    i32.add
    call $dynrt__fn28
    i32.store
    local.get 0
    local.tee 1
    return)
  (func $dynrt_dynTag (param i32) (result i32)
    (local i32)
    local.get 0
    local.set 1
    local.get 1
    i32.const 8
    i32.add
    i32.load
    return)
  (func $dynrt_dynTypeof (param i32) (result i32)
    (local i32)
    local.get 0
    local.set 1
    local.get 1
    i32.const 8
    i32.add
    i32.load
    local.set 1
    local.get 1
    i32.eqz
    if  ;; label = @1
      i32.const 0
      return
    end
    local.get 1
    i32.const 2
    i32.eq
    if  ;; label = @1
      i32.const 2
      return
    end
    local.get 1
    i32.const 3
    i32.eq
    if  ;; label = @1
      i32.const 3
      return
    end
    local.get 1
    i32.const 4
    i32.eq
    if  ;; label = @1
      i32.const 4
      return
    end
    local.get 1
    i32.const 7
    i32.eq
    if  ;; label = @1
      i32.const 5
      return
    end
    i32.const 1
    return)
  (func $dynrt_dynNumberValue (param i32) (result f64)
    (local i32) (local i32)
    local.get 0
    local.set 1
    local.get 1
    i32.const 8
    i32.add
    i32.const 4
    i32.add
    i32.load
    local.set 1
    local.get 1
    local.tee 2
    local.set 1
    local.get 1
    i32.const 8
    i32.add
    f64.load
    return)
  (func $dynrt_dynBoolValue (param i32) (result i32)
    (local i32)
    local.get 0
    local.set 1
    local.get 1
    i32.const 8
    i32.add
    i32.const 4
    i32.add
    i32.load
    return)
  (func $dynrt_dynStrLen (param i32) (result i32)
    (local i32)
    local.get 0
    local.set 1
    local.get 1
    i32.const 8
    i32.add
    i32.const 8
    i32.add
    i32.load
    return)
  (func $dynrt_dynStrBytes (param i32) (result i32)
    (local i32) (local i32)
    local.get 0
    local.set 1
    local.get 1
    i32.const 8
    i32.add
    i32.const 4
    i32.add
    i32.load
    local.set 1
    local.get 1
    i32.const 8
    i32.add
    local.tee 2
    return)
  (func $dynrt_dynStrCharAt (param i32 i32) (result i32)
    (local i32) (local i32)
    local.get 0
    local.set 2
    local.get 2
    i32.const 8
    i32.add
    i32.const 4
    i32.add
    i32.load
    local.set 2
    local.get 2
    local.tee 3
    local.set 2
    local.get 2
    i32.const 8
    i32.add
    local.get 1
    i32.add
    i32.load8_u
    return)
  (func $dynrt_dynToBool (param i32) (result i32)
    (local i32) (local i32) (local f64) (local i32)
    local.get 0
    local.set 1
    local.get 1
    i32.const 8
    i32.add
    i32.load
    local.set 2
    local.get 2
    i32.eqz
    if  ;; label = @1
      i32.const 0
      return
    end
    local.get 2
    i32.const 1
    i32.eq
    if  ;; label = @1
      i32.const 0
      return
    end
    local.get 2
    i32.const 2
    i32.eq
    if  ;; label = @1
      local.get 1
      i32.const 8
      i32.add
      i32.const 4
      i32.add
      i32.load
      return
    end
    local.get 2
    i32.const 3
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 1
        i32.const 8
        i32.add
        i32.const 4
        i32.add
        i32.load
        local.set 1
        local.get 1
        local.tee 4
        local.set 1
        local.get 1
        i32.const 8
        i32.add
        f64.load
        local.set 3
        local.get 3
        local.get 3
        f64.ne
        if  ;; label = @3
          i32.const 0
          return
        end
        local.get 3
        f64.const 0x0p+0 (;=0;)
        f64.eq
        if (result i32)  ;; label = @3
          i32.const 0
        else
          i32.const 1
        end
        return
      end
    end
    local.get 2
    i32.const 4
    i32.eq
    if  ;; label = @1
      local.get 1
      i32.const 8
      i32.add
      i32.const 8
      i32.add
      i32.load
      i32.eqz
      if (result i32)  ;; label = @2
        i32.const 0
      else
        i32.const 1
      end
      return
    end
    i32.const 1
    return)
  (func $dynrt_dynToNumber (param i32) (result f64)
    (local i32) (local i32) (local i32)
    local.get 0
    local.set 1
    local.get 1
    i32.const 8
    i32.add
    i32.load
    local.set 2
    local.get 2
    i32.const 1
    i32.eq
    if  ;; label = @1
      f64.const 0x0p+0 (;=0;)
      return
    end
    local.get 2
    i32.const 2
    i32.eq
    if  ;; label = @1
      local.get 1
      i32.const 8
      i32.add
      i32.const 4
      i32.add
      i32.load
      i32.eqz
      if (result f64)  ;; label = @2
        f64.const 0x0p+0 (;=0;)
      else
        f64.const 0x1.0p+0 (;=1;)
      end
      return
    end
    local.get 2
    i32.const 3
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 1
        i32.const 8
        i32.add
        i32.const 4
        i32.add
        i32.load
        local.set 1
        local.get 1
        local.tee 3
        local.set 1
        local.get 1
        i32.const 8
        i32.add
        f64.load
        return
      end
    end
    f64.const nan (;=NaN;)
    return)
  (func $dynrt__fn78 (param i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.set 1
    local.get 1
    i32.const 8
    i32.add
    i32.const 8
    i32.add
    i32.load
    local.set 2
    local.get 1
    i32.const 8
    i32.add
    i32.const 4
    i32.add
    i32.load
    local.set 1
    local.get 1
    local.tee 11
    local.set 1
    i32.const 534
    local.set 3
    i32.const 0
    local.tee 12
    local.set 4
    local.get 12
    local.set 5
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 5
          local.get 2
          i32.lt_s
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 3
            local.tee 7
            local.set 3
            local.get 4
            local.tee 8
            local.set 4
            i32.const 1
            call $__malloc
            local.set 6
            local.get 6
            local.get 1
            i32.const 8
            i32.add
            local.get 5
            i32.add
            i32.load8_u
            i32.store8
            local.get 3
            local.get 4
            local.get 6
            i32.const 1
            call $dynrt__fn4
            local.set 4
            nop
            local.set 3
            local.get 5
            local.tee 9
            i32.const 1
            local.tee 10
            i32.add
            local.set 5
          end
          br 1 (;@2;)
        end
      end
    end
    local.get 3
    local.set 1
    local.get 4
    local.set 2
    local.get 1
    local.tee 13
    global.set $dynrt_global1
    local.get 2
    global.set $dynrt_global2
    return)
  (func $dynrt__fn79 (param i32)
    (local i32) (local i32) (local f64) (local i32) (local i32) (local i32)
    local.get 0
    local.set 1
    local.get 1
    i32.const 8
    i32.add
    i32.load
    local.set 2
    local.get 2
    i32.const 4
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 0
        call $dynrt__fn78
        global.get $dynrt_global1
        local.set 1
        global.get $dynrt_global2
        local.set 2
        local.get 1
        global.set $dynrt_global1
        local.get 2
        global.set $dynrt_global2
        return
      end
    end
    local.get 2
    i32.const 3
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 1
        i32.const 8
        i32.add
        i32.const 4
        i32.add
        i32.load
        local.set 1
        local.get 1
        local.tee 4
        local.set 1
        local.get 1
        i32.const 8
        i32.add
        f64.load
        local.set 3
        i32.const 32
        call $__malloc
        local.set 1
        local.get 3
        local.get 1
        call $dynrt__fn19
        local.set 2
        local.get 1
        local.tee 5
        global.set $dynrt_global1
        local.get 2
        global.set $dynrt_global2
        return
      end
    end
    local.get 2
    i32.const 2
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 1
        i32.const 8
        i32.add
        i32.const 4
        i32.add
        i32.load
        i32.eqz
        if  ;; label = @3
          block  ;; label = @4
            i32.const 534
            local.set 1
            i32.const 5
            local.set 2
          end
        else
          block  ;; label = @4
            i32.const 539
            local.set 1
            i32.const 4
            local.set 2
          end
        end
        local.get 1
        global.set $dynrt_global1
        local.get 2
        global.set $dynrt_global2
        return
      end
    end
    local.get 2
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        i32.const 543
        local.set 1
        i32.const 4
        local.set 2
        local.get 1
        global.set $dynrt_global1
        local.get 2
        global.set $dynrt_global2
        return
      end
    end
    local.get 2
    i32.eqz
    if  ;; label = @1
      block  ;; label = @2
        i32.const 547
        local.set 1
        i32.const 9
        local.set 2
        local.get 1
        global.set $dynrt_global1
        local.get 2
        global.set $dynrt_global2
        return
      end
    end
    i32.const 534
    local.set 1
    i32.const 0
    local.set 2
    local.get 1
    local.tee 6
    global.set $dynrt_global1
    local.get 2
    global.set $dynrt_global2
    return)
  (func $dynrt__fn80 (param i32 i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.set 3
    local.get 3
    i32.const 8
    i32.add
    i32.const 4
    i32.add
    i32.load
    local.set 4
    local.get 3
    i32.const 8
    i32.add
    i32.const 12
    i32.add
    i32.load
    local.set 3
    local.get 4
    call $dynrt__fn29
    local.set 4
    local.get 2
    local.set 5
    i32.const 0
    local.set 6
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 6
          local.get 4
          i32.lt_s
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 3
            local.get 6
            i32.const 2
            i32.mul
            i32.const 1
            i32.add
            call $dynrt__fn30
            local.set 7
            local.get 7
            local.get 5
            i32.eq
            if  ;; label = @5
              block  ;; label = @6
                local.get 3
                local.get 6
                i32.const 2
                i32.mul
                call $dynrt__fn30
                local.set 8
                local.get 8
                local.set 8
                i32.const 1
                local.set 9
                i32.const 0
                local.set 10
                block  ;; label = @7
                  loop  ;; label = @8
                    block  ;; label = @9
                      local.get 10
                      local.get 7
                      i32.lt_s
                      i32.eqz
                      br_if 2 (;@7;)
                      local.get 8
                      i32.const 8
                      i32.add
                      local.get 10
                      i32.add
                      i32.load8_u
                      local.get 1
                      local.get 2
                      local.get 10
                      call $dynrt__fn8
                      i32.ne
                      if  ;; label = @10
                        block  ;; label = @11
                          i32.const 0
                          local.set 9
                          local.get 7
                          local.set 10
                        end
                      else
                        local.get 10
                        i32.const 1
                        i32.add
                        local.set 10
                      end
                      br 1 (;@8;)
                    end
                  end
                end
                local.get 9
                i32.const 1
                i32.eq
                if  ;; label = @7
                  local.get 6
                  return
                end
              end
            end
            local.get 6
            local.tee 11
            i32.const 1
            local.tee 12
            i32.add
            local.set 6
          end
          br 1 (;@2;)
        end
      end
    end
    i32.const -1
    return)
  (func $dynrt_dynSet (param i32 i32 i32 i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.tee 9
    local.set 4
    local.get 0
    local.get 1
    local.get 2
    call $dynrt__fn80
    local.set 5
    local.get 5
    i32.const -1
    i32.ne
    if  ;; label = @1
      block  ;; label = @2
        local.get 4
        i32.const 8
        i32.add
        i32.const 4
        i32.add
        i32.load
        local.get 5
        local.get 3
        call $dynrt__fn31
        return
      end
    end
    local.get 2
    local.tee 10
    local.set 5
    i32.const 8
    local.get 5
    i32.add
    call $dynrt__fn38
    local.set 6
    i32.const 0
    local.set 7
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 7
          local.get 5
          i32.lt_s
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 6
            i32.const 8
            i32.add
            local.get 7
            i32.add
            local.get 1
            local.get 2
            local.get 7
            call $dynrt__fn8
            i32.store8
            local.get 7
            local.tee 8
            i32.const 1
            i32.add
            local.set 7
          end
          br 1 (;@2;)
        end
      end
    end
    local.get 6
    local.tee 11
    local.set 6
    local.get 4
    i32.const 8
    i32.add
    i32.const 12
    i32.add
    i32.load
    local.set 7
    local.get 7
    local.get 6
    call $dynrt__fn32
    local.set 7
    local.get 7
    local.get 5
    call $dynrt__fn32
    local.set 7
    local.get 4
    i32.const 8
    i32.add
    i32.const 12
    i32.add
    local.get 7
    i32.store
    local.get 4
    i32.const 8
    i32.add
    i32.const 4
    i32.add
    local.get 4
    i32.const 8
    i32.add
    i32.const 4
    i32.add
    i32.load
    local.get 3
    call $dynrt__fn32
    i32.store)
  (func $dynrt_dynGet (param i32 i32 i32) (result i32)
    (local i32) (local i32) (local i32)
    local.get 0
    local.tee 5
    local.set 3
    local.get 0
    local.get 1
    local.get 2
    call $dynrt__fn80
    local.set 4
    local.get 4
    i32.const -1
    i32.eq
    if  ;; label = @1
      i32.const -1
      return
    end
    local.get 3
    i32.const 8
    i32.add
    i32.const 4
    i32.add
    i32.load
    local.get 4
    call $dynrt__fn30
    return)
  (func $dynrt_dynHas (param i32 i32 i32) (result i32)
    local.get 0
    local.get 1
    local.get 2
    call $dynrt__fn80
    i32.const -1
    i32.eq
    if (result i32)  ;; label = @1
      i32.const 0
    else
      i32.const 1
    end
    return)
  (func $dynrt_dynObjLen (param i32) (result i32)
    (local i32)
    local.get 0
    local.set 1
    local.get 1
    i32.const 8
    i32.add
    i32.const 4
    i32.add
    i32.load
    call $dynrt__fn29
    return)
  (func $dynrt_dynObjKeyPtr (param i32 i32) (result i32)
    (local i32) (local i32)
    local.get 0
    local.set 2
    local.get 2
    i32.const 8
    i32.add
    i32.const 12
    i32.add
    i32.load
    local.get 1
    i32.const 2
    i32.mul
    call $dynrt__fn30
    local.set 2
    local.get 2
    i32.const 8
    i32.add
    local.tee 3
    return)
  (func $dynrt_dynObjKeyLen (param i32 i32) (result i32)
    (local i32)
    local.get 0
    local.set 2
    local.get 2
    i32.const 8
    i32.add
    i32.const 12
    i32.add
    i32.load
    local.get 1
    i32.const 2
    i32.mul
    i32.const 1
    i32.add
    call $dynrt__fn30
    return)
  (func $dynrt_dynObjValAt (param i32 i32) (result i32)
    (local i32)
    local.get 0
    local.set 2
    local.get 2
    i32.const 8
    i32.add
    i32.const 4
    i32.add
    i32.load
    local.get 1
    call $dynrt__fn30
    return)
  (func $dynrt__fn88 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.set 2
    local.get 2
    i32.const 8
    i32.add
    i32.const 12
    i32.add
    i32.load
    local.get 1
    i32.const 2
    i32.mul
    call $dynrt__fn30
    local.set 3
    local.get 2
    i32.const 8
    i32.add
    i32.const 12
    i32.add
    i32.load
    local.get 1
    i32.const 2
    i32.mul
    i32.const 1
    i32.add
    call $dynrt__fn30
    local.set 2
    local.get 3
    local.tee 7
    local.set 3
    i32.const 8
    local.get 2
    i32.add
    call $dynrt__fn38
    local.set 4
    i32.const 0
    local.set 5
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 5
          local.get 2
          i32.lt_s
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 4
            i32.const 8
            i32.add
            local.get 5
            i32.add
            local.get 3
            i32.const 8
            i32.add
            local.get 5
            i32.add
            i32.load8_u
            i32.store8
            local.get 5
            local.tee 6
            i32.const 1
            i32.add
            local.set 5
          end
          br 1 (;@2;)
        end
      end
    end
    call $dynrt__fn46
    local.set 3
    local.get 3
    i32.const 8
    i32.add
    i32.const 4
    i32.store
    local.get 3
    i32.const 8
    i32.add
    i32.const 4
    i32.add
    local.get 4
    i32.store
    local.get 3
    i32.const 8
    i32.add
    i32.const 8
    i32.add
    local.get 2
    i32.store
    local.get 3
    local.tee 8
    return)
  (func $dynrt_dynPush (param i32 i32)
    (local i32)
    local.get 0
    local.set 2
    local.get 2
    i32.const 8
    i32.add
    i32.const 4
    i32.add
    local.get 2
    i32.const 8
    i32.add
    i32.const 4
    i32.add
    i32.load
    local.get 1
    call $dynrt__fn32
    i32.store)
  (func $dynrt_dynArrLen (param i32) (result i32)
    (local i32)
    local.get 0
    local.set 1
    local.get 1
    i32.const 8
    i32.add
    i32.const 4
    i32.add
    i32.load
    call $dynrt__fn29
    return)
  (func $dynrt_dynArrGet (param i32 i32) (result i32)
    (local i32)
    local.get 0
    local.set 2
    local.get 2
    i32.const 8
    i32.add
    i32.const 4
    i32.add
    i32.load
    local.get 1
    call $dynrt__fn30
    return)
  (func $dynrt__fn92 (param i32 i32 i32)
    (local i32) (local i32)
    local.get 0
    local.set 3
    local.get 3
    i32.const 8
    i32.add
    i32.const 4
    i32.add
    i32.load
    call $dynrt__fn29
    local.set 4
    local.get 1
    i32.const 0
    i32.ge_s
    if (result i32)  ;; label = @1
      local.get 1
      local.get 4
      i32.lt_s
    else
      i32.const 0
    end
    if  ;; label = @1
      local.get 3
      i32.const 8
      i32.add
      i32.const 4
      i32.add
      i32.load
      local.get 1
      local.get 2
      call $dynrt__fn31
    else
      local.get 1
      local.get 4
      i32.eq
      if  ;; label = @2
        local.get 3
        i32.const 8
        i32.add
        i32.const 4
        i32.add
        local.get 3
        i32.const 8
        i32.add
        i32.const 4
        i32.add
        i32.load
        local.get 2
        call $dynrt__fn32
        i32.store
      end
    end)
  (func $dynrt__fn93 (param i32 i32 i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local f64) (local i32) (local i32) (local i32) (local i32) (local i32) (local f64) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    call $dynrt_dynArrLen
    local.set 4
    local.get 3
    call $dynrt_dynArrLen
    local.set 5
    local.get 1
    local.get 2
    i32.const 556
    i32.const 4
    call $dynrt__fn138
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        i32.const 0
        local.set 6
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 6
              local.get 5
              i32.lt_s
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                local.get 0
                local.get 3
                local.get 6
                call $dynrt_dynArrGet
                call $dynrt_dynPush
                local.get 6
                local.tee 17
                i32.const 1
                i32.add
                local.set 6
              end
              br 1 (;@4;)
            end
          end
        end
        local.get 0
        call $dynrt_dynArrLen
        local.set 4
        local.get 4
        f64.convert_i32_s
        call $dynrt_dynNumber
        return
      end
    end
    local.get 1
    local.get 2
    i32.const 560
    i32.const 7
    call $dynrt__fn138
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        call $dynrt_dynUndefined
        local.set 7
        local.get 5
        i32.const 0
        i32.gt_s
        if  ;; label = @3
          local.get 3
          i32.const 0
          call $dynrt_dynArrGet
          local.set 7
        end
        i32.const 0
        local.set 6
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 6
              local.get 4
              i32.lt_s
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                local.get 0
                local.get 6
                call $dynrt_dynArrGet
                local.get 7
                call $dynrt_dynStrictEq
                i32.const 1
                i32.eq
                if  ;; label = @7
                  local.get 6
                  f64.convert_i32_s
                  call $dynrt_dynNumber
                  return
                end
                local.get 6
                i32.const 1
                i32.add
                local.set 6
              end
              br 1 (;@4;)
            end
          end
        end
        f64.const 0x0p+0 (;=0;)
        f64.const 0x1.0p+0 (;=1;)
        f64.sub
        call $dynrt_dynNumber
        return
      end
    end
    local.get 1
    local.get 2
    i32.const 567
    i32.const 8
    call $dynrt__fn138
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        call $dynrt_dynUndefined
        local.set 7
        local.get 5
        i32.const 0
        i32.gt_s
        if  ;; label = @3
          local.get 3
          i32.const 0
          call $dynrt_dynArrGet
          local.set 7
        end
        i32.const 0
        local.tee 18
        local.set 6
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 6
              local.get 4
              i32.lt_s
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                local.get 0
                local.get 6
                call $dynrt_dynArrGet
                local.get 7
                call $dynrt_dynStrictEq
                i32.const 1
                i32.eq
                if  ;; label = @7
                  i32.const 1
                  call $dynrt_dynBool
                  return
                end
                local.get 6
                i32.const 1
                i32.add
                local.set 6
              end
              br 1 (;@4;)
            end
          end
        end
        i32.const 0
        call $dynrt_dynBool
        return
      end
    end
    local.get 1
    local.get 2
    i32.const 575
    i32.const 4
    call $dynrt__fn138
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        i32.const 579
        local.set 7
        i32.const 1
        local.set 8
        local.get 5
        i32.const 0
        i32.gt_s
        if  ;; label = @3
          block  ;; label = @4
            local.get 3
            i32.const 0
            call $dynrt_dynArrGet
            call $dynrt__fn79
            global.get $dynrt_global1
            local.set 7
            global.get $dynrt_global2
            local.set 8
          end
        end
        i32.const 534
        local.set 5
        i32.const 0
        local.tee 24
        local.set 9
        local.get 24
        local.set 6
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 6
              local.get 4
              i32.lt_s
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                local.get 6
                i32.const 0
                i32.gt_s
                if  ;; label = @7
                  block  ;; label = @8
                    local.get 5
                    local.tee 19
                    local.set 5
                    local.get 9
                    local.tee 20
                    local.set 9
                    local.get 5
                    local.get 9
                    local.get 7
                    local.get 8
                    call $dynrt__fn4
                    local.set 9
                    nop
                    local.set 5
                  end
                end
                local.get 5
                local.tee 21
                local.set 5
                local.get 9
                local.tee 22
                local.set 9
                local.get 0
                local.get 6
                call $dynrt_dynArrGet
                call $dynrt__fn79
                local.get 5
                local.get 9
                global.get $dynrt_global1
                global.get $dynrt_global2
                call $dynrt__fn4
                local.set 9
                nop
                local.set 5
                local.get 6
                local.tee 23
                i32.const 1
                i32.add
                local.set 6
              end
              br 1 (;@4;)
            end
          end
        end
        local.get 5
        local.get 9
        call $dynrt_dynString
        return
      end
    end
    local.get 1
    local.get 2
    i32.const 580
    i32.const 5
    call $dynrt__fn138
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        i32.const 0
        local.set 6
        local.get 4
        local.set 7
        local.get 5
        i32.const 0
        i32.gt_s
        if  ;; label = @3
          block  ;; label = @4
            local.get 3
            i32.const 0
            call $dynrt_dynArrGet
            call $dynrt_dynToNumber
            local.set 10
            local.get 10
            i32.trunc_f64_s
            local.set 6
          end
        end
        local.get 5
        i32.const 1
        i32.gt_s
        if  ;; label = @3
          block  ;; label = @4
            local.get 3
            i32.const 1
            call $dynrt_dynArrGet
            call $dynrt_dynToNumber
            local.set 10
            local.get 10
            i32.trunc_f64_s
            local.set 7
          end
        end
        local.get 6
        i32.const 0
        i32.lt_s
        if  ;; label = @3
          local.get 4
          local.get 6
          i32.add
          local.set 6
        end
        local.get 7
        i32.const 0
        i32.lt_s
        if  ;; label = @3
          local.get 4
          local.get 7
          i32.add
          local.set 7
        end
        local.get 6
        i32.const 0
        i32.lt_s
        if  ;; label = @3
          i32.const 0
          local.set 6
        end
        local.get 7
        local.get 4
        i32.gt_s
        if  ;; label = @3
          local.get 4
          local.set 7
        end
        call $dynrt_dynArray
        local.set 8
        local.get 6
        local.set 6
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 6
              local.get 7
              i32.lt_s
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                local.get 8
                local.get 0
                local.get 6
                call $dynrt_dynArrGet
                call $dynrt_dynPush
                local.get 6
                local.tee 25
                i32.const 1
                i32.add
                local.set 6
              end
              br 1 (;@4;)
            end
          end
        end
        local.get 8
        return
      end
    end
    local.get 1
    local.get 2
    i32.const 585
    i32.const 6
    call $dynrt__fn138
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        call $dynrt_dynArray
        local.set 8
        i32.const 0
        local.tee 29
        local.set 6
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 6
              local.get 4
              i32.lt_s
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                local.get 8
                local.get 0
                local.get 6
                call $dynrt_dynArrGet
                call $dynrt_dynPush
                local.get 6
                local.tee 26
                i32.const 1
                i32.add
                local.set 6
              end
              br 1 (;@4;)
            end
          end
        end
        i32.const 0
        local.tee 30
        local.set 4
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 4
              local.get 5
              i32.lt_s
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                local.get 3
                local.get 4
                call $dynrt_dynArrGet
                local.set 6
                local.get 6
                local.set 7
                local.get 7
                i32.const 8
                i32.add
                i32.load
                i32.const 5
                i32.eq
                if  ;; label = @7
                  block  ;; label = @8
                    local.get 6
                    call $dynrt_dynArrLen
                    local.set 7
                    i32.const 0
                    local.set 9
                    block  ;; label = @9
                      loop  ;; label = @10
                        block  ;; label = @11
                          local.get 9
                          local.get 7
                          i32.lt_s
                          i32.eqz
                          br_if 2 (;@9;)
                          block  ;; label = @12
                            local.get 8
                            local.get 6
                            local.get 9
                            call $dynrt_dynArrGet
                            call $dynrt_dynPush
                            local.get 9
                            local.tee 27
                            i32.const 1
                            i32.add
                            local.set 9
                          end
                          br 1 (;@10;)
                        end
                      end
                    end
                  end
                else
                  local.get 8
                  local.get 6
                  call $dynrt_dynPush
                end
                local.get 4
                local.tee 28
                i32.const 1
                i32.add
                local.set 4
              end
              br 1 (;@4;)
            end
          end
        end
        local.get 8
        return
      end
    end
    local.get 1
    local.get 2
    i32.const 591
    i32.const 7
    call $dynrt__fn138
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        call $dynrt_dynArray
        local.set 8
        local.get 4
        i32.const 1
        i32.sub
        local.set 6
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 6
              i32.const 0
              i32.ge_s
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                local.get 8
                local.get 0
                local.get 6
                call $dynrt_dynArrGet
                call $dynrt_dynPush
                local.get 6
                local.tee 31
                i32.const 1
                i32.sub
                local.set 6
              end
              br 1 (;@4;)
            end
          end
        end
        local.get 8
        return
      end
    end
    local.get 1
    local.get 2
    i32.const 598
    i32.const 3
    call $dynrt__fn138
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 4
        i32.eqz
        if  ;; label = @3
          call $dynrt_dynUndefined
          return
        end
        local.get 0
        local.set 6
        local.get 6
        i32.const 8
        i32.add
        i32.const 4
        i32.add
        i32.load
        local.set 7
        local.get 7
        local.get 4
        i32.const 1
        i32.sub
        call $dynrt__fn30
        local.set 5
        local.get 7
        local.tee 32
        local.set 6
        local.get 6
        i32.const 8
        i32.add
        local.get 4
        i32.const 1
        i32.sub
        i32.store
        local.get 5
        return
      end
    end
    local.get 1
    local.get 2
    i32.const 601
    i32.const 5
    call $dynrt__fn138
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 4
        i32.eqz
        if  ;; label = @3
          call $dynrt_dynUndefined
          return
        end
        local.get 0
        local.set 6
        local.get 6
        i32.const 8
        i32.add
        i32.const 4
        i32.add
        i32.load
        local.set 7
        local.get 7
        i32.const 0
        call $dynrt__fn30
        local.set 5
        i32.const 1
        local.tee 35
        local.set 6
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 6
              local.get 4
              i32.lt_s
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                local.get 7
                local.get 6
                i32.const 1
                i32.sub
                local.get 7
                local.get 6
                call $dynrt__fn30
                call $dynrt__fn31
                local.get 6
                local.tee 33
                i32.const 1
                local.tee 34
                i32.add
                local.set 6
              end
              br 1 (;@4;)
            end
          end
        end
        local.get 7
        local.tee 36
        local.set 6
        local.get 6
        i32.const 8
        i32.add
        local.get 4
        i32.const 1
        i32.sub
        i32.store
        local.get 5
        return
      end
    end
    local.get 1
    local.get 2
    i32.const 606
    i32.const 7
    call $dynrt__fn138
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        i32.const 0
        local.tee 39
        local.set 6
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 6
              local.get 5
              i32.lt_s
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                local.get 0
                call $dynrt_dynUndefined
                call $dynrt_dynPush
                local.get 6
                i32.const 1
                i32.add
                local.set 6
              end
              br 1 (;@4;)
            end
          end
        end
        local.get 0
        local.set 6
        local.get 6
        i32.const 8
        i32.add
        i32.const 4
        i32.add
        i32.load
        local.set 7
        local.get 4
        local.tee 40
        i32.const 1
        i32.sub
        local.set 6
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 6
              i32.const 0
              i32.ge_s
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                local.get 7
                local.get 6
                local.get 5
                i32.add
                local.get 7
                local.get 6
                call $dynrt__fn30
                call $dynrt__fn31
                local.get 6
                local.tee 37
                i32.const 1
                i32.sub
                local.set 6
              end
              br 1 (;@4;)
            end
          end
        end
        i32.const 0
        local.tee 41
        local.set 6
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 6
              local.get 5
              i32.lt_s
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                local.get 7
                local.get 6
                local.get 3
                local.get 6
                call $dynrt_dynArrGet
                call $dynrt__fn31
                local.get 6
                local.tee 38
                i32.const 1
                i32.add
                local.set 6
              end
              br 1 (;@4;)
            end
          end
        end
        local.get 4
        local.tee 42
        local.get 5
        i32.add
        local.set 4
        local.get 4
        f64.convert_i32_s
        call $dynrt_dynNumber
        return
      end
    end
    local.get 1
    local.get 2
    i32.const 613
    i32.const 2
    call $dynrt__fn138
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        i32.const 0
        local.set 6
        local.get 5
        i32.const 0
        i32.gt_s
        if  ;; label = @3
          block  ;; label = @4
            local.get 3
            i32.const 0
            call $dynrt_dynArrGet
            call $dynrt_dynToNumber
            local.set 10
            local.get 10
            i32.trunc_f64_s
            local.set 6
          end
        end
        local.get 6
        i32.const 0
        i32.lt_s
        if  ;; label = @3
          local.get 4
          local.get 6
          i32.add
          local.set 6
        end
        local.get 6
        i32.const 0
        i32.lt_s
        if (result i32)  ;; label = @3
          i32.const 1
        else
          local.get 6
          local.get 4
          i32.ge_s
        end
        if  ;; label = @3
          call $dynrt_dynUndefined
          return
        end
        local.get 0
        local.get 6
        call $dynrt_dynArrGet
        return
      end
    end
    local.get 1
    local.get 2
    i32.const 615
    i32.const 11
    call $dynrt__fn138
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        call $dynrt_dynUndefined
        local.set 7
        local.get 5
        i32.const 0
        i32.gt_s
        if  ;; label = @3
          local.get 3
          i32.const 0
          call $dynrt_dynArrGet
          local.set 7
        end
        local.get 4
        i32.const 1
        i32.sub
        local.set 6
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 6
              i32.const 0
              i32.ge_s
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                local.get 0
                local.get 6
                call $dynrt_dynArrGet
                local.get 7
                call $dynrt_dynStrictEq
                i32.const 1
                i32.eq
                if  ;; label = @7
                  local.get 6
                  f64.convert_i32_s
                  call $dynrt_dynNumber
                  return
                end
                local.get 6
                i32.const 1
                i32.sub
                local.set 6
              end
              br 1 (;@4;)
            end
          end
        end
        f64.const 0x0p+0 (;=0;)
        f64.const 0x1.0p+0 (;=1;)
        f64.sub
        call $dynrt_dynNumber
        return
      end
    end
    call $dynrt_dynUndefined
    local.set 11
    local.get 5
    i32.const 0
    i32.gt_s
    if  ;; label = @1
      local.get 3
      i32.const 0
      call $dynrt_dynArrGet
      local.set 11
    end
    local.get 1
    local.get 2
    i32.const 626
    i32.const 3
    call $dynrt__fn138
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        call $dynrt_dynArray
        local.set 8
        i32.const 0
        local.set 6
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 6
              local.get 4
              i32.lt_s
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                call $dynrt_dynArray
                local.set 12
                local.get 12
                local.get 0
                local.get 6
                call $dynrt_dynArrGet
                call $dynrt_dynPush
                local.get 12
                local.get 6
                f64.convert_i32_s
                call $dynrt_dynNumber
                call $dynrt_dynPush
                local.get 8
                local.get 11
                local.get 12
                call $dynrt_dynApply
                call $dynrt_dynPush
                local.get 6
                local.tee 43
                i32.const 1
                i32.add
                local.set 6
              end
              br 1 (;@4;)
            end
          end
        end
        local.get 8
        return
      end
    end
    local.get 1
    local.get 2
    i32.const 629
    i32.const 6
    call $dynrt__fn138
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        call $dynrt_dynArray
        local.set 8
        i32.const 0
        local.set 6
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 6
              local.get 4
              i32.lt_s
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                local.get 0
                local.get 6
                call $dynrt_dynArrGet
                local.set 5
                call $dynrt_dynArray
                local.set 12
                local.get 12
                local.get 5
                call $dynrt_dynPush
                local.get 12
                local.get 6
                f64.convert_i32_s
                call $dynrt_dynNumber
                call $dynrt_dynPush
                local.get 11
                local.get 12
                call $dynrt_dynApply
                call $dynrt_dynToBool
                i32.const 1
                i32.eq
                if  ;; label = @7
                  local.get 8
                  local.get 5
                  call $dynrt_dynPush
                end
                local.get 6
                local.tee 44
                i32.const 1
                i32.add
                local.set 6
              end
              br 1 (;@4;)
            end
          end
        end
        local.get 8
        return
      end
    end
    local.get 1
    local.get 2
    i32.const 635
    i32.const 7
    call $dynrt__fn138
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        i32.const 0
        local.set 6
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 6
              local.get 4
              i32.lt_s
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                call $dynrt_dynArray
                local.set 12
                local.get 12
                local.get 0
                local.get 6
                call $dynrt_dynArrGet
                call $dynrt_dynPush
                local.get 12
                local.get 6
                f64.convert_i32_s
                call $dynrt_dynNumber
                call $dynrt_dynPush
                local.get 11
                local.get 12
                call $dynrt_dynApply
                drop
                local.get 6
                local.tee 45
                i32.const 1
                i32.add
                local.set 6
              end
              br 1 (;@4;)
            end
          end
        end
        call $dynrt_dynUndefined
        return
      end
    end
    local.get 1
    local.get 2
    i32.const 642
    i32.const 6
    call $dynrt__fn138
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        call $dynrt_dynUndefined
        local.set 7
        i32.const 0
        local.set 6
        local.get 5
        i32.const 1
        i32.gt_s
        if  ;; label = @3
          local.get 3
          i32.const 1
          call $dynrt_dynArrGet
          local.set 7
        else
          local.get 4
          i32.const 0
          i32.gt_s
          if  ;; label = @4
            block  ;; label = @5
              local.get 0
              i32.const 0
              call $dynrt_dynArrGet
              local.set 7
              i32.const 1
              local.set 6
            end
          end
        end
        local.get 6
        local.set 6
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 6
              local.get 4
              i32.lt_s
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                call $dynrt_dynArray
                local.set 12
                local.get 12
                local.get 7
                call $dynrt_dynPush
                local.get 12
                local.get 0
                local.get 6
                call $dynrt_dynArrGet
                call $dynrt_dynPush
                local.get 12
                local.get 6
                f64.convert_i32_s
                call $dynrt_dynNumber
                call $dynrt_dynPush
                local.get 11
                local.get 12
                call $dynrt_dynApply
                local.set 7
                local.get 6
                local.tee 46
                i32.const 1
                i32.add
                local.set 6
              end
              br 1 (;@4;)
            end
          end
        end
        local.get 7
        return
      end
    end
    local.get 1
    local.get 2
    i32.const 648
    i32.const 4
    call $dynrt__fn138
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        i32.const 0
        local.set 6
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 6
              local.get 4
              i32.lt_s
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                local.get 0
                local.get 6
                call $dynrt_dynArrGet
                local.set 5
                call $dynrt_dynArray
                local.set 12
                local.get 12
                local.get 5
                call $dynrt_dynPush
                local.get 12
                local.get 6
                f64.convert_i32_s
                call $dynrt_dynNumber
                call $dynrt_dynPush
                local.get 11
                local.get 12
                call $dynrt_dynApply
                call $dynrt_dynToBool
                i32.const 1
                i32.eq
                if  ;; label = @7
                  local.get 5
                  return
                end
                local.get 6
                local.tee 47
                i32.const 1
                i32.add
                local.set 6
              end
              br 1 (;@4;)
            end
          end
        end
        call $dynrt_dynUndefined
        return
      end
    end
    local.get 1
    local.get 2
    i32.const 652
    i32.const 9
    call $dynrt__fn138
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        i32.const 0
        local.set 6
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 6
              local.get 4
              i32.lt_s
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                call $dynrt_dynArray
                local.set 12
                local.get 12
                local.get 0
                local.get 6
                call $dynrt_dynArrGet
                call $dynrt_dynPush
                local.get 12
                local.get 6
                f64.convert_i32_s
                call $dynrt_dynNumber
                call $dynrt_dynPush
                local.get 11
                local.get 12
                call $dynrt_dynApply
                call $dynrt_dynToBool
                i32.const 1
                i32.eq
                if  ;; label = @7
                  local.get 6
                  f64.convert_i32_s
                  call $dynrt_dynNumber
                  return
                end
                local.get 6
                local.tee 48
                i32.const 1
                i32.add
                local.set 6
              end
              br 1 (;@4;)
            end
          end
        end
        f64.const 0x0p+0 (;=0;)
        f64.const 0x1.0p+0 (;=1;)
        f64.sub
        call $dynrt_dynNumber
        return
      end
    end
    local.get 1
    local.get 2
    i32.const 661
    i32.const 4
    call $dynrt__fn138
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        i32.const 0
        local.tee 50
        local.set 6
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 6
              local.get 4
              i32.lt_s
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                call $dynrt_dynArray
                local.set 12
                local.get 12
                local.get 0
                local.get 6
                call $dynrt_dynArrGet
                call $dynrt_dynPush
                local.get 12
                local.get 6
                f64.convert_i32_s
                call $dynrt_dynNumber
                call $dynrt_dynPush
                local.get 11
                local.get 12
                call $dynrt_dynApply
                call $dynrt_dynToBool
                i32.const 1
                i32.eq
                if  ;; label = @7
                  i32.const 1
                  call $dynrt_dynBool
                  return
                end
                local.get 6
                local.tee 49
                i32.const 1
                i32.add
                local.set 6
              end
              br 1 (;@4;)
            end
          end
        end
        i32.const 0
        call $dynrt_dynBool
        return
      end
    end
    local.get 1
    local.get 2
    i32.const 665
    i32.const 5
    call $dynrt__fn138
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        i32.const 0
        local.set 6
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 6
              local.get 4
              i32.lt_s
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                call $dynrt_dynArray
                local.set 12
                local.get 12
                local.get 0
                local.get 6
                call $dynrt_dynArrGet
                call $dynrt_dynPush
                local.get 12
                local.get 6
                f64.convert_i32_s
                call $dynrt_dynNumber
                call $dynrt_dynPush
                local.get 11
                local.get 12
                call $dynrt_dynApply
                call $dynrt_dynToBool
                i32.eqz
                if  ;; label = @7
                  i32.const 0
                  call $dynrt_dynBool
                  return
                end
                local.get 6
                local.tee 51
                i32.const 1
                i32.add
                local.set 6
              end
              br 1 (;@4;)
            end
          end
        end
        i32.const 1
        call $dynrt_dynBool
        return
      end
    end
    local.get 1
    local.get 2
    i32.const 670
    i32.const 4
    call $dynrt__fn138
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 0
        local.tee 58
        local.set 6
        local.get 6
        i32.const 8
        i32.add
        i32.const 4
        i32.add
        i32.load
        local.set 7
        i32.const 1
        local.set 6
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 6
              local.get 4
              i32.lt_s
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                local.get 7
                local.get 6
                call $dynrt__fn30
                local.set 8
                local.get 6
                local.tee 54
                i32.const 1
                local.tee 55
                i32.sub
                local.set 9
                local.get 55
                local.set 13
                block  ;; label = @7
                  loop  ;; label = @8
                    block  ;; label = @9
                      local.get 9
                      i32.const 0
                      i32.ge_s
                      if (result i32)  ;; label = @10
                        local.get 13
                        i32.const 1
                        i32.eq
                      else
                        i32.const 0
                      end
                      i32.eqz
                      br_if 2 (;@7;)
                      block  ;; label = @10
                        local.get 7
                        local.get 9
                        call $dynrt__fn30
                        local.set 14
                        i32.const 0
                        local.set 15
                        local.get 5
                        i32.const 0
                        i32.gt_s
                        if  ;; label = @11
                          block  ;; label = @12
                            call $dynrt_dynArray
                            local.set 12
                            local.get 12
                            local.get 14
                            call $dynrt_dynPush
                            local.get 12
                            local.get 8
                            call $dynrt_dynPush
                            local.get 11
                            local.get 12
                            call $dynrt_dynApply
                            call $dynrt_dynToNumber
                            local.set 10
                            local.get 10
                            f64.const 0x0p+0 (;=0;)
                            f64.gt
                            if  ;; label = @13
                              i32.const 1
                              local.set 15
                            end
                          end
                        else
                          block  ;; label = @12
                            local.get 14
                            call $dynrt_dynToNumber
                            local.set 10
                            local.get 8
                            call $dynrt_dynToNumber
                            local.set 16
                            local.get 10
                            local.get 16
                            f64.gt
                            if  ;; label = @13
                              i32.const 1
                              local.set 15
                            end
                          end
                        end
                        local.get 15
                        i32.const 1
                        i32.eq
                        if  ;; label = @11
                          block  ;; label = @12
                            local.get 7
                            local.get 9
                            i32.const 1
                            i32.add
                            local.get 14
                            call $dynrt__fn31
                            local.get 9
                            local.tee 52
                            i32.const 1
                            local.tee 53
                            i32.sub
                            local.set 9
                          end
                        else
                          i32.const 0
                          local.set 13
                        end
                      end
                      br 1 (;@8;)
                    end
                  end
                end
                local.get 7
                local.get 9
                i32.const 1
                i32.add
                local.get 8
                call $dynrt__fn31
                local.get 6
                local.tee 56
                i32.const 1
                local.tee 57
                i32.add
                local.set 6
              end
              br 1 (;@4;)
            end
          end
        end
        local.get 0
        local.tee 59
        return
      end
    end
    call $dynrt_dynUndefined
    return)
  (func $dynrt__fn94 (param i32 i32 i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local f64) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    call $dynrt__fn78
    global.get $dynrt_global1
    local.set 4
    global.get $dynrt_global2
    local.set 5
    local.get 5
    local.set 6
    local.get 3
    call $dynrt_dynArrLen
    local.set 7
    local.get 1
    local.get 2
    i32.const 674
    i32.const 6
    call $dynrt__fn138
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        i32.const 0
        local.set 6
        local.get 7
        i32.const 0
        i32.gt_s
        if  ;; label = @3
          block  ;; label = @4
            local.get 3
            i32.const 0
            call $dynrt_dynArrGet
            call $dynrt_dynToNumber
            local.set 8
            local.get 8
            i32.trunc_f64_s
            local.set 6
          end
        end
        local.get 4
        local.get 5
        local.get 6
        call $dynrt__fn9
        local.set 5
        nop
        local.set 4
        local.get 4
        local.get 5
        call $dynrt_dynString
        return
      end
    end
    local.get 1
    local.get 2
    i32.const 680
    i32.const 10
    call $dynrt__fn138
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        i32.const 0
        local.set 6
        local.get 7
        i32.const 0
        i32.gt_s
        if  ;; label = @3
          block  ;; label = @4
            local.get 3
            i32.const 0
            call $dynrt_dynArrGet
            call $dynrt_dynToNumber
            local.set 8
            local.get 8
            i32.trunc_f64_s
            local.set 6
          end
        end
        local.get 4
        local.get 5
        local.get 6
        call $dynrt__fn8
        local.set 4
        local.get 4
        f64.convert_i32_s
        call $dynrt_dynNumber
        return
      end
    end
    local.get 1
    local.get 2
    i32.const 690
    i32.const 11
    call $dynrt__fn138
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 4
        local.get 5
        call $dynrt__fn12
        local.set 5
        nop
        local.set 4
        local.get 4
        local.get 5
        call $dynrt_dynString
        return
      end
    end
    local.get 1
    local.get 2
    i32.const 701
    i32.const 11
    call $dynrt__fn138
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 4
        local.get 5
        call $dynrt__fn13
        local.set 5
        nop
        local.set 4
        local.get 4
        local.get 5
        call $dynrt_dynString
        return
      end
    end
    local.get 1
    local.get 2
    i32.const 712
    i32.const 4
    call $dynrt__fn138
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 4
        local.get 5
        call $dynrt__fn7
        local.set 5
        nop
        local.set 4
        local.get 4
        local.get 5
        call $dynrt_dynString
        return
      end
    end
    local.get 1
    local.get 2
    i32.const 580
    i32.const 5
    call $dynrt__fn138
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        i32.const 0
        local.set 9
        local.get 6
        local.set 10
        local.get 7
        i32.const 0
        i32.gt_s
        if  ;; label = @3
          block  ;; label = @4
            local.get 3
            i32.const 0
            call $dynrt_dynArrGet
            call $dynrt_dynToNumber
            local.set 8
            local.get 8
            i32.trunc_f64_s
            local.set 9
          end
        end
        local.get 7
        i32.const 1
        i32.gt_s
        if  ;; label = @3
          block  ;; label = @4
            local.get 3
            i32.const 1
            call $dynrt_dynArrGet
            call $dynrt_dynToNumber
            local.set 8
            local.get 8
            i32.trunc_f64_s
            local.set 10
          end
        end
        local.get 9
        i32.const 0
        i32.lt_s
        if  ;; label = @3
          local.get 6
          local.get 9
          i32.add
          local.set 9
        end
        local.get 10
        i32.const 0
        i32.lt_s
        if  ;; label = @3
          local.get 6
          local.get 10
          i32.add
          local.set 10
        end
        local.get 9
        i32.const 0
        i32.lt_s
        if  ;; label = @3
          i32.const 0
          local.set 9
        end
        local.get 10
        local.get 6
        i32.gt_s
        if  ;; label = @3
          local.get 6
          local.set 10
        end
        local.get 9
        local.get 10
        i32.ge_s
        if  ;; label = @3
          i32.const 534
          i32.const 0
          call $dynrt_dynString
          return
        end
        local.get 4
        local.get 5
        local.get 9
        local.get 10
        call $dynrt__fn5
        local.set 5
        nop
        local.set 4
        local.get 4
        local.get 5
        call $dynrt_dynString
        return
      end
    end
    local.get 1
    local.get 2
    i32.const 560
    i32.const 7
    call $dynrt__fn138
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        i32.const 534
        local.set 6
        i32.const 0
        local.set 9
        local.get 7
        i32.const 0
        i32.gt_s
        if  ;; label = @3
          block  ;; label = @4
            local.get 3
            i32.const 0
            call $dynrt_dynArrGet
            call $dynrt__fn78
            global.get $dynrt_global1
            local.set 6
            global.get $dynrt_global2
            local.set 9
          end
        end
        local.get 4
        local.get 5
        local.get 6
        local.get 9
        call $dynrt__fn6
        local.set 6
        local.get 6
        f64.convert_i32_s
        call $dynrt_dynNumber
        return
      end
    end
    local.get 1
    local.get 2
    i32.const 567
    i32.const 8
    call $dynrt__fn138
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        i32.const 534
        local.set 6
        i32.const 0
        local.set 9
        local.get 7
        i32.const 0
        i32.gt_s
        if  ;; label = @3
          block  ;; label = @4
            local.get 3
            i32.const 0
            call $dynrt_dynArrGet
            call $dynrt__fn78
            global.get $dynrt_global1
            local.set 6
            global.get $dynrt_global2
            local.set 9
          end
        end
        local.get 4
        local.get 5
        local.get 6
        local.get 9
        call $dynrt__fn6
        i32.const -1
        i32.ne
        i32.const 1
        i32.eq
        if (result i32)  ;; label = @3
          i32.const 1
        else
          i32.const 0
        end
        call $dynrt_dynBool
        return
      end
    end
    local.get 1
    local.get 2
    i32.const 716
    i32.const 10
    call $dynrt__fn138
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        i32.const 534
        local.set 6
        i32.const 0
        local.set 9
        local.get 7
        i32.const 0
        i32.gt_s
        if  ;; label = @3
          block  ;; label = @4
            local.get 3
            i32.const 0
            call $dynrt_dynArrGet
            call $dynrt__fn78
            global.get $dynrt_global1
            local.set 6
            global.get $dynrt_global2
            local.set 9
          end
        end
        local.get 4
        local.get 5
        local.get 6
        local.get 9
        call $dynrt__fn10
        i32.const 1
        i32.eq
        if (result i32)  ;; label = @3
          i32.const 1
        else
          i32.const 0
        end
        call $dynrt_dynBool
        return
      end
    end
    local.get 1
    local.get 2
    i32.const 726
    i32.const 8
    call $dynrt__fn138
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        i32.const 534
        local.set 6
        i32.const 0
        local.set 9
        local.get 7
        i32.const 0
        i32.gt_s
        if  ;; label = @3
          block  ;; label = @4
            local.get 3
            i32.const 0
            call $dynrt_dynArrGet
            call $dynrt__fn78
            global.get $dynrt_global1
            local.set 6
            global.get $dynrt_global2
            local.set 9
          end
        end
        local.get 4
        local.get 5
        local.get 6
        local.get 9
        call $dynrt__fn11
        i32.const 1
        i32.eq
        if (result i32)  ;; label = @3
          i32.const 1
        else
          i32.const 0
        end
        call $dynrt_dynBool
        return
      end
    end
    local.get 1
    local.get 2
    i32.const 734
    i32.const 6
    call $dynrt__fn138
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        i32.const 0
        local.set 6
        local.get 7
        i32.const 0
        i32.gt_s
        if  ;; label = @3
          block  ;; label = @4
            local.get 3
            i32.const 0
            call $dynrt_dynArrGet
            call $dynrt_dynToNumber
            local.set 8
            local.get 8
            i32.trunc_f64_s
            local.set 6
          end
        end
        local.get 4
        local.get 5
        local.get 6
        call $dynrt__fn16
        local.set 5
        nop
        local.set 4
        local.get 4
        local.get 5
        call $dynrt_dynString
        return
      end
    end
    local.get 1
    local.get 2
    i32.const 740
    i32.const 8
    call $dynrt__fn138
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        i32.const 0
        local.set 6
        local.get 7
        i32.const 0
        i32.gt_s
        if  ;; label = @3
          block  ;; label = @4
            local.get 3
            i32.const 0
            call $dynrt_dynArrGet
            call $dynrt_dynToNumber
            local.set 8
            local.get 8
            i32.trunc_f64_s
            local.set 6
          end
        end
        i32.const 748
        local.set 9
        i32.const 1
        local.set 10
        local.get 7
        i32.const 1
        i32.gt_s
        if  ;; label = @3
          block  ;; label = @4
            local.get 3
            i32.const 1
            call $dynrt_dynArrGet
            call $dynrt__fn78
            global.get $dynrt_global1
            local.set 9
            global.get $dynrt_global2
            local.set 10
          end
        end
        local.get 4
        local.get 5
        local.get 6
        local.get 9
        local.get 10
        call $dynrt__fn14
        local.set 5
        nop
        local.set 4
        local.get 4
        local.get 5
        call $dynrt_dynString
        return
      end
    end
    local.get 1
    local.get 2
    i32.const 749
    i32.const 6
    call $dynrt__fn138
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        i32.const 0
        local.set 6
        local.get 7
        i32.const 0
        i32.gt_s
        if  ;; label = @3
          block  ;; label = @4
            local.get 3
            i32.const 0
            call $dynrt_dynArrGet
            call $dynrt_dynToNumber
            local.set 8
            local.get 8
            i32.trunc_f64_s
            local.set 6
          end
        end
        i32.const 748
        local.set 9
        i32.const 1
        local.set 10
        local.get 7
        i32.const 1
        i32.gt_s
        if  ;; label = @3
          block  ;; label = @4
            local.get 3
            i32.const 1
            call $dynrt_dynArrGet
            call $dynrt__fn78
            global.get $dynrt_global1
            local.set 9
            global.get $dynrt_global2
            local.set 10
          end
        end
        local.get 4
        local.get 5
        local.get 6
        local.get 9
        local.get 10
        call $dynrt__fn15
        local.set 5
        nop
        local.set 4
        local.get 4
        local.get 5
        call $dynrt_dynString
        return
      end
    end
    local.get 1
    local.get 2
    i32.const 585
    i32.const 6
    call $dynrt__fn138
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        i32.const 534
        local.set 6
        i32.const 0
        local.set 9
        local.get 7
        i32.const 0
        i32.gt_s
        if  ;; label = @3
          block  ;; label = @4
            local.get 3
            i32.const 0
            call $dynrt_dynArrGet
            call $dynrt__fn78
            global.get $dynrt_global1
            local.set 6
            global.get $dynrt_global2
            local.set 9
          end
        end
        local.get 4
        local.tee 11
        local.set 4
        local.get 5
        local.tee 12
        local.set 5
        local.get 4
        local.get 5
        local.get 6
        local.get 9
        call $dynrt__fn4
        local.set 5
        nop
        local.set 4
        local.get 4
        local.get 5
        call $dynrt_dynString
        return
      end
    end
    local.get 1
    local.get 2
    i32.const 755
    i32.const 5
    call $dynrt__fn138
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        i32.const 534
        local.set 6
        i32.const 0
        local.tee 14
        local.set 9
        local.get 7
        i32.const 0
        i32.gt_s
        if  ;; label = @3
          block  ;; label = @4
            local.get 3
            i32.const 0
            call $dynrt_dynArrGet
            call $dynrt__fn78
            global.get $dynrt_global1
            local.set 6
            global.get $dynrt_global2
            local.set 9
          end
        end
        local.get 4
        local.get 5
        local.get 6
        local.get 9
        call $dynrt__fn17
        local.set 4
        call $dynrt_dynArray
        local.set 5
        local.get 4
        i32.load
        local.set 6
        i32.const 0
        local.tee 15
        local.set 7
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 7
              local.get 6
              i32.lt_s
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                local.get 4
                i32.const 8
                i32.add
                local.get 7
                i32.const 3
                i32.shl
                i32.add
                i32.load
                local.set 9
                local.get 4
                i32.const 8
                i32.add
                local.get 7
                i32.const 3
                i32.shl
                i32.add
                i32.load offset=4
                local.set 10
                local.get 5
                local.get 9
                local.get 10
                call $dynrt_dynString
                call $dynrt_dynPush
                local.get 7
                local.tee 13
                i32.const 1
                i32.add
                local.set 7
              end
              br 1 (;@4;)
            end
          end
        end
        local.get 5
        local.tee 16
        return
      end
    end
    call $dynrt_dynUndefined
    return)
  (func $dynrt__fn95 (param i32 i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 2
    call $dynrt_dynArrLen
    local.set 3
    call $dynrt_dynUndefined
    local.set 4
    local.get 3
    i32.const 0
    i32.gt_s
    if  ;; label = @1
      local.get 2
      i32.const 0
      call $dynrt_dynArrGet
      local.set 4
    end
    local.get 4
    local.set 5
    local.get 0
    local.get 1
    i32.const 760
    i32.const 6
    call $dynrt__fn138
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        call $dynrt_dynObject
        local.set 3
        local.get 3
        local.tee 11
        local.set 6
        local.get 5
        i32.const 8
        i32.add
        i32.load
        i32.const 6
        i32.eq
        if  ;; label = @3
          local.get 6
          i32.const 8
          i32.add
          i32.const 8
          i32.add
          local.get 4
          i32.store
        end
        local.get 3
        local.tee 12
        return
      end
    end
    local.get 0
    local.get 1
    i32.const 766
    i32.const 4
    call $dynrt__fn138
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        call $dynrt_dynArray
        local.set 3
        local.get 5
        i32.const 8
        i32.add
        i32.load
        i32.const 6
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 4
            call $dynrt_dynObjLen
            local.set 5
            i32.const 0
            local.set 6
            block  ;; label = @5
              loop  ;; label = @6
                block  ;; label = @7
                  local.get 6
                  local.get 5
                  i32.lt_s
                  i32.eqz
                  br_if 2 (;@5;)
                  block  ;; label = @8
                    local.get 3
                    local.get 4
                    local.get 6
                    call $dynrt__fn88
                    call $dynrt_dynPush
                    local.get 6
                    local.tee 13
                    i32.const 1
                    i32.add
                    local.set 6
                  end
                  br 1 (;@6;)
                end
              end
            end
          end
        end
        local.get 3
        return
      end
    end
    local.get 0
    local.get 1
    i32.const 770
    i32.const 6
    call $dynrt__fn138
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        call $dynrt_dynArray
        local.set 3
        local.get 5
        i32.const 8
        i32.add
        i32.load
        i32.const 6
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 4
            call $dynrt_dynObjLen
            local.set 5
            i32.const 0
            local.set 6
            block  ;; label = @5
              loop  ;; label = @6
                block  ;; label = @7
                  local.get 6
                  local.get 5
                  i32.lt_s
                  i32.eqz
                  br_if 2 (;@5;)
                  block  ;; label = @8
                    local.get 3
                    local.get 4
                    local.get 6
                    call $dynrt_dynObjValAt
                    call $dynrt_dynPush
                    local.get 6
                    local.tee 14
                    i32.const 1
                    i32.add
                    local.set 6
                  end
                  br 1 (;@6;)
                end
              end
            end
          end
        end
        local.get 3
        return
      end
    end
    local.get 0
    local.get 1
    i32.const 776
    i32.const 7
    call $dynrt__fn138
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        call $dynrt_dynArray
        local.set 3
        local.get 5
        i32.const 8
        i32.add
        i32.load
        i32.const 6
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 4
            call $dynrt_dynObjLen
            local.set 5
            i32.const 0
            local.set 6
            block  ;; label = @5
              loop  ;; label = @6
                block  ;; label = @7
                  local.get 6
                  local.get 5
                  i32.lt_s
                  i32.eqz
                  br_if 2 (;@5;)
                  block  ;; label = @8
                    call $dynrt_dynArray
                    local.set 7
                    local.get 7
                    local.get 4
                    local.get 6
                    call $dynrt__fn88
                    call $dynrt_dynPush
                    local.get 7
                    local.get 4
                    local.get 6
                    call $dynrt_dynObjValAt
                    call $dynrt_dynPush
                    local.get 3
                    local.get 7
                    call $dynrt_dynPush
                    local.get 6
                    local.tee 15
                    i32.const 1
                    i32.add
                    local.set 6
                  end
                  br 1 (;@6;)
                end
              end
            end
          end
        end
        local.get 3
        return
      end
    end
    local.get 0
    local.get 1
    i32.const 783
    i32.const 6
    call $dynrt__fn138
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        i32.const 1
        local.set 7
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 7
              local.get 3
              i32.lt_s
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                local.get 2
                local.get 7
                call $dynrt_dynArrGet
                local.set 8
                local.get 8
                local.set 5
                local.get 5
                i32.const 8
                i32.add
                i32.load
                i32.const 6
                i32.eq
                if  ;; label = @7
                  block  ;; label = @8
                    local.get 8
                    call $dynrt_dynObjLen
                    local.set 5
                    i32.const 0
                    local.set 6
                    block  ;; label = @9
                      loop  ;; label = @10
                        block  ;; label = @11
                          local.get 6
                          local.get 5
                          i32.lt_s
                          i32.eqz
                          br_if 2 (;@9;)
                          block  ;; label = @12
                            local.get 8
                            local.get 6
                            call $dynrt__fn88
                            call $dynrt__fn78
                            global.get $dynrt_global1
                            local.set 9
                            global.get $dynrt_global2
                            local.set 10
                            local.get 4
                            local.get 9
                            local.get 10
                            local.get 8
                            local.get 6
                            call $dynrt_dynObjValAt
                            call $dynrt_dynSet
                            local.get 6
                            local.tee 16
                            i32.const 1
                            i32.add
                            local.set 6
                          end
                          br 1 (;@10;)
                        end
                      end
                    end
                  end
                end
                local.get 7
                local.tee 17
                i32.const 1
                i32.add
                local.set 7
              end
              br 1 (;@4;)
            end
          end
        end
        local.get 4
        return
      end
    end
    call $dynrt_dynUndefined
    return)
  (func $dynrt__fn96 (param i32 i32 i32) (result i32)
    (local i32) (local f64) (local f64) (local f64) (local f64) (local f64) (local f64) (local f64) (local f64) (local f64)
    local.get 2
    call $dynrt_dynArrLen
    local.set 3
    f64.const 0x0p+0 (;=0;)
    local.tee 11
    local.set 4
    local.get 3
    i32.const 0
    i32.gt_s
    if  ;; label = @1
      local.get 2
      i32.const 0
      call $dynrt_dynArrGet
      call $dynrt_dynToNumber
      local.set 4
    end
    local.get 0
    local.get 1
    i32.const 789
    i32.const 5
    call $dynrt__fn138
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 4
        local.tee 6
        f64.floor
        local.set 4
        local.get 4
        call $dynrt_dynNumber
        return
      end
    end
    local.get 0
    local.get 1
    i32.const 794
    i32.const 4
    call $dynrt__fn138
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 4
        local.tee 7
        f64.ceil
        local.set 4
        local.get 4
        call $dynrt_dynNumber
        return
      end
    end
    local.get 0
    local.get 1
    i32.const 798
    i32.const 5
    call $dynrt__fn138
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 4
        local.tee 8
        f64.const 0x1.0p-1 (;=0.5;)
        f64.add
        f64.floor
        local.set 4
        local.get 4
        call $dynrt_dynNumber
        return
      end
    end
    local.get 0
    local.get 1
    i32.const 803
    i32.const 3
    call $dynrt__fn138
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 4
        local.tee 9
        f64.abs
        local.set 4
        local.get 4
        call $dynrt_dynNumber
        return
      end
    end
    local.get 0
    local.get 1
    i32.const 806
    i32.const 4
    call $dynrt__fn138
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 4
        local.tee 10
        f64.sqrt
        local.set 4
        local.get 4
        call $dynrt_dynNumber
        return
      end
    end
    local.get 0
    local.get 1
    i32.const 810
    i32.const 4
    call $dynrt__fn138
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        f64.const 0x0p+0 (;=0;)
        local.set 5
        local.get 4
        f64.const 0x0p+0 (;=0;)
        f64.gt
        if  ;; label = @3
          f64.const 0x1.0p+0 (;=1;)
          local.set 5
        end
        local.get 4
        f64.const 0x0p+0 (;=0;)
        f64.lt
        if  ;; label = @3
          f64.const 0x0p+0 (;=0;)
          f64.const 0x1.0p+0 (;=1;)
          f64.sub
          local.set 5
        end
        local.get 5
        call $dynrt_dynNumber
        return
      end
    end
    local.get 0
    local.get 1
    i32.const 814
    i32.const 5
    call $dynrt__fn138
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 4
        f64.floor
        local.set 5
        local.get 4
        f64.const 0x0p+0 (;=0;)
        f64.lt
        if  ;; label = @3
          local.get 4
          f64.ceil
          local.set 5
        end
        local.get 5
        call $dynrt_dynNumber
        return
      end
    end
    f64.const 0x0p+0 (;=0;)
    local.tee 12
    local.set 5
    local.get 3
    i32.const 1
    i32.gt_s
    if  ;; label = @1
      local.get 2
      i32.const 1
      call $dynrt_dynArrGet
      call $dynrt_dynToNumber
      local.set 5
    end
    local.get 0
    local.get 1
    i32.const 819
    i32.const 3
    call $dynrt__fn138
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 4
        local.get 5
        f64.gt
        if (result f64)  ;; label = @3
          local.get 4
        else
          local.get 5
        end
        local.set 4
        local.get 4
        call $dynrt_dynNumber
        return
      end
    end
    local.get 0
    local.get 1
    i32.const 822
    i32.const 3
    call $dynrt__fn138
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 4
        local.get 5
        f64.lt
        if (result f64)  ;; label = @3
          local.get 4
        else
          local.get 5
        end
        local.set 4
        local.get 4
        call $dynrt_dynNumber
        return
      end
    end
    local.get 0
    local.get 1
    i32.const 825
    i32.const 3
    call $dynrt__fn138
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 4
        local.get 5
        call $dynrt__fn21
        local.set 4
        local.get 4
        call $dynrt_dynNumber
        return
      end
    end
    call $dynrt_dynUndefined
    return)
  (func $dynrt__fn97 (param i32 i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    i32.const 828
    local.tee 21
    local.set 2
    i32.const 1
    local.tee 22
    local.set 3
    local.get 1
    local.set 4
    i32.const 0
    local.set 5
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 5
          local.get 4
          i32.lt_s
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 0
            local.get 1
            local.get 5
            call $dynrt__fn8
            local.set 6
            local.get 6
            i32.const 34
            i32.eq
            if  ;; label = @5
              block  ;; label = @6
                local.get 2
                local.tee 8
                local.set 2
                local.get 3
                local.tee 9
                local.set 3
                local.get 2
                local.get 3
                i32.const 829
                i32.const 2
                call $dynrt__fn4
                local.set 3
                nop
                local.set 2
              end
            else
              local.get 6
              i32.const 92
              i32.eq
              if  ;; label = @6
                block  ;; label = @7
                  local.get 2
                  local.tee 10
                  local.set 2
                  local.get 3
                  local.tee 11
                  local.set 3
                  local.get 2
                  local.get 3
                  i32.const 831
                  i32.const 2
                  call $dynrt__fn4
                  local.set 3
                  nop
                  local.set 2
                end
              else
                local.get 6
                i32.const 10
                i32.eq
                if  ;; label = @7
                  block  ;; label = @8
                    local.get 2
                    local.tee 12
                    local.set 2
                    local.get 3
                    local.tee 13
                    local.set 3
                    local.get 2
                    local.get 3
                    i32.const 833
                    i32.const 2
                    call $dynrt__fn4
                    local.set 3
                    nop
                    local.set 2
                  end
                else
                  local.get 6
                  i32.const 13
                  i32.eq
                  if  ;; label = @8
                    block  ;; label = @9
                      local.get 2
                      local.tee 14
                      local.set 2
                      local.get 3
                      local.tee 15
                      local.set 3
                      local.get 2
                      local.get 3
                      i32.const 835
                      i32.const 2
                      call $dynrt__fn4
                      local.set 3
                      nop
                      local.set 2
                    end
                  else
                    local.get 6
                    i32.const 9
                    i32.eq
                    if  ;; label = @9
                      block  ;; label = @10
                        local.get 2
                        local.tee 16
                        local.set 2
                        local.get 3
                        local.tee 17
                        local.set 3
                        local.get 2
                        local.get 3
                        i32.const 837
                        i32.const 2
                        call $dynrt__fn4
                        local.set 3
                        nop
                        local.set 2
                      end
                    else
                      block  ;; label = @10
                        local.get 0
                        local.get 1
                        local.get 5
                        call $dynrt__fn9
                        local.set 7
                        nop
                        local.set 6
                        local.get 2
                        local.tee 18
                        local.set 2
                        local.get 3
                        local.tee 19
                        local.set 3
                        local.get 2
                        local.get 3
                        local.get 6
                        local.get 7
                        call $dynrt__fn4
                        local.set 3
                        nop
                        local.set 2
                      end
                    end
                  end
                end
              end
            end
            local.get 5
            local.tee 20
            i32.const 1
            i32.add
            local.set 5
          end
          br 1 (;@2;)
        end
      end
    end
    local.get 2
    local.tee 23
    local.set 2
    local.get 3
    local.tee 24
    local.set 3
    local.get 2
    local.get 3
    i32.const 828
    i32.const 1
    call $dynrt__fn4
    local.set 3
    nop
    local.set 2
    local.get 2
    local.tee 25
    local.set 2
    local.get 3
    local.tee 26
    local.set 3
    local.get 2
    local.tee 27
    global.set $dynrt_global1
    local.get 3
    local.tee 28
    global.set $dynrt_global2
    return)
  (func $dynrt__fn98 (param i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.set 1
    local.get 1
    i32.const 8
    i32.add
    i32.load
    local.set 1
    local.get 1
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        i32.const 543
        local.set 1
        i32.const 4
        local.set 2
        local.get 1
        global.set $dynrt_global1
        local.get 2
        global.set $dynrt_global2
        return
      end
    end
    local.get 1
    i32.eqz
    if  ;; label = @1
      block  ;; label = @2
        i32.const 543
        local.set 1
        i32.const 4
        local.set 2
        local.get 1
        global.set $dynrt_global1
        local.get 2
        global.set $dynrt_global2
        return
      end
    end
    local.get 1
    i32.const 2
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 0
        call $dynrt_dynToBool
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            i32.const 539
            local.set 1
            i32.const 4
            local.set 2
            local.get 1
            global.set $dynrt_global1
            local.get 2
            global.set $dynrt_global2
            return
          end
        end
        i32.const 534
        local.set 1
        i32.const 5
        local.set 2
        local.get 1
        global.set $dynrt_global1
        local.get 2
        global.set $dynrt_global2
        return
      end
    end
    local.get 1
    i32.const 3
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 0
        call $dynrt__fn79
        global.get $dynrt_global1
        local.set 1
        global.get $dynrt_global2
        local.set 2
        local.get 1
        local.tee 9
        local.set 1
        local.get 2
        local.tee 10
        local.set 2
        local.get 1
        local.tee 11
        global.set $dynrt_global1
        local.get 2
        local.tee 12
        global.set $dynrt_global2
        return
      end
    end
    local.get 1
    i32.const 4
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 0
        call $dynrt__fn78
        global.get $dynrt_global1
        global.get $dynrt_global2
        call $dynrt__fn97
        global.get $dynrt_global1
        local.tee 13
        local.set 1
        global.get $dynrt_global2
        local.tee 14
        local.set 2
        local.get 1
        local.tee 15
        local.set 1
        local.get 2
        local.tee 16
        local.set 2
        local.get 1
        local.tee 17
        global.set $dynrt_global1
        local.get 2
        local.tee 18
        global.set $dynrt_global2
        return
      end
    end
    local.get 1
    i32.const 5
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        i32.const 839
        local.set 1
        i32.const 1
        local.tee 24
        local.set 2
        local.get 0
        call $dynrt_dynArrLen
        local.set 3
        i32.const 0
        local.set 4
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 4
              local.get 3
              i32.lt_s
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                local.get 4
                i32.const 0
                i32.gt_s
                if  ;; label = @7
                  block  ;; label = @8
                    local.get 1
                    local.tee 19
                    local.set 1
                    local.get 2
                    local.tee 20
                    local.set 2
                    local.get 1
                    local.get 2
                    i32.const 579
                    i32.const 1
                    call $dynrt__fn4
                    local.set 2
                    nop
                    local.set 1
                  end
                end
                local.get 0
                local.get 4
                call $dynrt_dynArrGet
                call $dynrt__fn98
                global.get $dynrt_global1
                local.set 5
                global.get $dynrt_global2
                local.set 6
                local.get 1
                local.tee 21
                local.set 1
                local.get 2
                local.tee 22
                local.set 2
                local.get 1
                local.get 2
                local.get 5
                local.get 6
                call $dynrt__fn4
                local.set 2
                nop
                local.set 1
                local.get 4
                local.tee 23
                i32.const 1
                i32.add
                local.set 4
              end
              br 1 (;@4;)
            end
          end
        end
        local.get 1
        local.tee 25
        local.set 1
        local.get 2
        local.tee 26
        local.set 2
        local.get 1
        local.get 2
        i32.const 840
        i32.const 1
        call $dynrt__fn4
        local.set 2
        nop
        local.set 1
        local.get 1
        local.tee 27
        local.set 1
        local.get 2
        local.tee 28
        local.set 2
        local.get 1
        local.tee 29
        global.set $dynrt_global1
        local.get 2
        local.tee 30
        global.set $dynrt_global2
        return
      end
    end
    local.get 1
    i32.const 6
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        i32.const 841
        local.set 1
        i32.const 1
        local.tee 41
        local.set 2
        local.get 0
        call $dynrt_dynObjLen
        local.set 3
        i32.const 0
        local.set 4
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 4
              local.get 3
              i32.lt_s
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                local.get 4
                i32.const 0
                i32.gt_s
                if  ;; label = @7
                  block  ;; label = @8
                    local.get 1
                    local.tee 31
                    local.set 1
                    local.get 2
                    local.tee 32
                    local.set 2
                    local.get 1
                    local.get 2
                    i32.const 579
                    i32.const 1
                    call $dynrt__fn4
                    local.set 2
                    nop
                    local.set 1
                  end
                end
                local.get 0
                local.get 4
                call $dynrt__fn88
                call $dynrt__fn78
                global.get $dynrt_global1
                global.get $dynrt_global2
                call $dynrt__fn97
                global.get $dynrt_global1
                local.tee 33
                local.set 5
                global.get $dynrt_global2
                local.tee 34
                local.set 6
                local.get 0
                local.get 4
                call $dynrt_dynObjValAt
                call $dynrt__fn98
                global.get $dynrt_global1
                local.tee 35
                local.set 7
                global.get $dynrt_global2
                local.tee 36
                local.set 8
                local.get 1
                local.tee 37
                local.set 1
                local.get 2
                local.tee 38
                local.set 2
                local.get 1
                local.get 2
                local.get 5
                local.get 6
                call $dynrt__fn4
                local.set 2
                nop
                local.set 1
                local.get 1
                local.get 2
                i32.const 842
                i32.const 1
                call $dynrt__fn4
                local.set 2
                nop
                local.set 1
                local.get 1
                local.get 2
                local.get 7
                local.get 8
                call $dynrt__fn4
                local.set 2
                nop
                local.set 1
                local.get 4
                local.tee 39
                i32.const 1
                local.tee 40
                i32.add
                local.set 4
              end
              br 1 (;@4;)
            end
          end
        end
        local.get 1
        local.tee 42
        local.set 1
        local.get 2
        local.tee 43
        local.set 2
        local.get 1
        local.get 2
        i32.const 843
        i32.const 1
        call $dynrt__fn4
        local.set 2
        nop
        local.set 1
        local.get 1
        local.tee 44
        local.set 1
        local.get 2
        local.tee 45
        local.set 2
        local.get 1
        local.tee 46
        global.set $dynrt_global1
        local.get 2
        local.tee 47
        global.set $dynrt_global2
        return
      end
    end
    i32.const 543
    local.set 1
    i32.const 4
    local.set 2
    local.get 1
    local.tee 48
    global.set $dynrt_global1
    local.get 2
    global.set $dynrt_global2
    return)
  (func $dynrt__fn99 (param i32 i32) (result i32)
    (local i32) (local i32)
    global.get $dynrt_global19
    local.set 2
    i32.const 0
    global.set $dynrt_global19
    local.get 0
    local.get 1
    call $dynrt__fn158
    local.set 3
    local.get 2
    global.set $dynrt_global19
    local.get 3
    return)
  (func $dynrt__fn100 (param i32 i32) (result i32)
    (local i32) (local i32)
    local.get 0
    call $dynrt_dynArrLen
    local.set 2
    i32.const 0
    local.set 3
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 3
          local.get 2
          i32.lt_s
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 0
            local.get 3
            call $dynrt_dynArrGet
            local.get 1
            call $dynrt_dynStrictEq
            i32.const 1
            i32.eq
            if  ;; label = @5
              local.get 3
              return
            end
            local.get 3
            i32.const 1
            i32.add
            local.set 3
          end
          br 1 (;@2;)
        end
      end
    end
    i32.const -1
    return)
  (func $dynrt__fn101 (param i32) (result i32)
    (local i32) (local i32) (local i32) (local i32)
    call $dynrt_dynArray
    local.set 1
    local.get 0
    call $dynrt_dynArrLen
    local.set 2
    i32.const 0
    local.set 3
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 3
          local.get 2
          i32.lt_s
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 1
            local.get 0
            local.get 3
            call $dynrt_dynArrGet
            call $dynrt_dynPush
            local.get 3
            local.tee 4
            i32.const 1
            i32.add
            local.set 3
          end
          br 1 (;@2;)
        end
      end
    end
    local.get 1
    return)
  (func $dynrt__fn102 (param i32 i32)
    (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    call $dynrt_dynArrLen
    local.set 2
    local.get 1
    local.set 3
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 3
          local.get 2
          i32.const 1
          i32.sub
          i32.lt_s
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 0
            local.get 3
            local.get 0
            local.get 3
            i32.const 1
            i32.add
            call $dynrt_dynArrGet
            call $dynrt__fn92
            local.get 3
            i32.const 1
            i32.add
            local.tee 4
            local.set 3
          end
          br 1 (;@2;)
        end
      end
    end
    local.get 0
    local.tee 5
    local.set 3
    local.get 3
    i32.const 8
    i32.add
    i32.const 4
    i32.add
    i32.load
    local.set 3
    local.get 3
    local.tee 6
    local.set 3
    local.get 3
    i32.const 8
    i32.add
    local.get 2
    i32.const 1
    i32.sub
    i32.store)
  (func $dynrt__fn103 (result i32)
    (local i32) (local i32)
    call $dynrt_dynObject
    local.set 0
    local.get 0
    i32.const 844
    i32.const 6
    call $dynrt_dynArray
    call $dynrt_dynSet
    local.get 0
    i32.const 850
    i32.const 6
    call $dynrt_dynArray
    call $dynrt_dynSet
    local.get 0
    local.tee 1
    return)
  (func $dynrt__fn104 (param i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    call $dynrt_dynObject
    local.set 1
    call $dynrt_dynArray
    local.set 2
    local.get 1
    i32.const 856
    i32.const 6
    local.get 2
    call $dynrt_dynSet
    local.get 0
    local.set 3
    local.get 3
    i32.const 8
    i32.add
    i32.load
    i32.const 5
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 0
        call $dynrt_dynArrLen
        local.set 3
        i32.const 0
        local.set 4
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 4
              local.get 3
              i32.lt_s
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                local.get 0
                local.get 4
                call $dynrt_dynArrGet
                local.set 5
                local.get 2
                local.get 5
                call $dynrt__fn100
                i32.const 0
                i32.lt_s
                if  ;; label = @7
                  local.get 2
                  local.get 5
                  call $dynrt_dynPush
                end
                local.get 4
                local.tee 6
                i32.const 1
                i32.add
                local.set 4
              end
              br 1 (;@4;)
            end
          end
        end
      end
    end
    local.get 1
    local.tee 7
    return)
  (func $dynrt__fn105 (param i32 i32 i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    i32.const 844
    i32.const 6
    call $dynrt_dynGet
    local.set 4
    local.get 0
    i32.const 850
    i32.const 6
    call $dynrt_dynGet
    local.set 5
    local.get 3
    call $dynrt_dynArrLen
    local.set 6
    call $dynrt_dynUndefined
    local.set 7
    local.get 6
    i32.const 0
    i32.gt_s
    if  ;; label = @1
      local.get 3
      i32.const 0
      call $dynrt_dynArrGet
      local.set 7
    end
    local.get 1
    local.get 2
    i32.const 862
    i32.const 3
    call $dynrt__fn138
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        call $dynrt_dynUndefined
        local.set 8
        local.get 6
        i32.const 1
        i32.gt_s
        if  ;; label = @3
          local.get 3
          i32.const 1
          call $dynrt_dynArrGet
          local.set 8
        end
        local.get 4
        local.get 7
        call $dynrt__fn100
        local.set 6
        local.get 6
        i32.const 0
        i32.ge_s
        if  ;; label = @3
          local.get 5
          local.get 6
          local.get 8
          call $dynrt__fn92
        else
          block  ;; label = @4
            local.get 4
            local.get 7
            call $dynrt_dynPush
            local.get 5
            local.get 8
            call $dynrt_dynPush
          end
        end
        local.get 0
        return
      end
    end
    local.get 1
    local.get 2
    i32.const 865
    i32.const 3
    call $dynrt__fn138
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 4
        local.get 7
        call $dynrt__fn100
        local.set 6
        local.get 6
        i32.const 0
        i32.ge_s
        if  ;; label = @3
          local.get 5
          local.get 6
          call $dynrt_dynArrGet
          return
        end
        call $dynrt_dynUndefined
        return
      end
    end
    local.get 1
    local.get 2
    i32.const 868
    i32.const 3
    call $dynrt__fn138
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 4
        local.get 7
        call $dynrt__fn100
        i32.const 0
        i32.ge_s
        if  ;; label = @3
          i32.const 1
          call $dynrt_dynBool
          return
        end
        i32.const 0
        call $dynrt_dynBool
        return
      end
    end
    local.get 1
    local.get 2
    i32.const 871
    i32.const 6
    call $dynrt__fn138
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 4
        local.get 7
        call $dynrt__fn100
        local.set 6
        local.get 6
        i32.const 0
        i32.ge_s
        if  ;; label = @3
          block  ;; label = @4
            local.get 4
            local.get 6
            call $dynrt__fn102
            local.get 5
            local.get 6
            call $dynrt__fn102
            i32.const 1
            call $dynrt_dynBool
            return
          end
        end
        i32.const 0
        call $dynrt_dynBool
        return
      end
    end
    local.get 1
    local.get 2
    i32.const 766
    i32.const 4
    call $dynrt__fn138
    i32.const 1
    i32.eq
    if  ;; label = @1
      local.get 4
      call $dynrt__fn101
      return
    end
    local.get 1
    local.get 2
    i32.const 770
    i32.const 6
    call $dynrt__fn138
    i32.const 1
    i32.eq
    if  ;; label = @1
      local.get 5
      call $dynrt__fn101
      return
    end
    local.get 1
    local.get 2
    i32.const 635
    i32.const 7
    call $dynrt__fn138
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        call $dynrt_dynUndefined
        local.set 7
        local.get 6
        i32.const 0
        i32.gt_s
        if  ;; label = @3
          local.get 3
          i32.const 0
          call $dynrt_dynArrGet
          local.set 7
        end
        local.get 4
        call $dynrt_dynArrLen
        local.set 6
        i32.const 0
        local.set 8
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 8
              local.get 6
              i32.lt_s
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                call $dynrt_dynArray
                local.set 9
                local.get 9
                local.get 5
                local.get 8
                call $dynrt_dynArrGet
                call $dynrt_dynPush
                local.get 9
                local.get 4
                local.get 8
                call $dynrt_dynArrGet
                call $dynrt_dynPush
                local.get 7
                local.get 9
                call $dynrt_dynApply
                drop
                local.get 8
                local.tee 10
                i32.const 1
                i32.add
                local.set 8
              end
              br 1 (;@4;)
            end
          end
        end
        call $dynrt_dynUndefined
        return
      end
    end
    call $dynrt_dynUndefined
    return)
  (func $dynrt__fn106 (param i32 i32 i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    i32.const 856
    i32.const 6
    call $dynrt_dynGet
    local.set 4
    local.get 3
    call $dynrt_dynArrLen
    local.set 5
    call $dynrt_dynUndefined
    local.set 6
    local.get 5
    i32.const 0
    i32.gt_s
    if  ;; label = @1
      local.get 3
      i32.const 0
      call $dynrt_dynArrGet
      local.set 6
    end
    local.get 1
    local.get 2
    i32.const 877
    i32.const 3
    call $dynrt__fn138
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 4
        local.get 6
        call $dynrt__fn100
        i32.const 0
        i32.lt_s
        if  ;; label = @3
          local.get 4
          local.get 6
          call $dynrt_dynPush
        end
        local.get 0
        return
      end
    end
    local.get 1
    local.get 2
    i32.const 868
    i32.const 3
    call $dynrt__fn138
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 4
        local.get 6
        call $dynrt__fn100
        i32.const 0
        i32.ge_s
        if  ;; label = @3
          i32.const 1
          call $dynrt_dynBool
          return
        end
        i32.const 0
        call $dynrt_dynBool
        return
      end
    end
    local.get 1
    local.get 2
    i32.const 871
    i32.const 6
    call $dynrt__fn138
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 4
        local.get 6
        call $dynrt__fn100
        local.set 5
        local.get 5
        i32.const 0
        i32.ge_s
        if  ;; label = @3
          block  ;; label = @4
            local.get 4
            local.get 5
            call $dynrt__fn102
            i32.const 1
            call $dynrt_dynBool
            return
          end
        end
        i32.const 0
        call $dynrt_dynBool
        return
      end
    end
    local.get 1
    local.get 2
    i32.const 770
    i32.const 6
    call $dynrt__fn138
    i32.const 1
    i32.eq
    if  ;; label = @1
      local.get 4
      call $dynrt__fn101
      return
    end
    local.get 1
    local.get 2
    i32.const 766
    i32.const 4
    call $dynrt__fn138
    i32.const 1
    i32.eq
    if  ;; label = @1
      local.get 4
      call $dynrt__fn101
      return
    end
    local.get 1
    local.get 2
    i32.const 635
    i32.const 7
    call $dynrt__fn138
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        call $dynrt_dynUndefined
        local.set 6
        local.get 5
        i32.const 0
        i32.gt_s
        if  ;; label = @3
          local.get 3
          i32.const 0
          call $dynrt_dynArrGet
          local.set 6
        end
        local.get 4
        call $dynrt_dynArrLen
        local.set 5
        i32.const 0
        local.set 7
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 7
              local.get 5
              i32.lt_s
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                call $dynrt_dynArray
                local.set 8
                local.get 8
                local.get 4
                local.get 7
                call $dynrt_dynArrGet
                call $dynrt_dynPush
                local.get 6
                local.get 8
                call $dynrt_dynApply
                drop
                local.get 7
                local.tee 9
                i32.const 1
                i32.add
                local.set 7
              end
              br 1 (;@4;)
            end
          end
        end
        call $dynrt_dynUndefined
        return
      end
    end
    call $dynrt_dynUndefined
    return)
  (func $dynrt__fn107 (param i32 i32 i32)
    (local i32) (local i32) (local f64)
    local.get 0
    local.set 3
    local.get 3
    i32.const 8
    i32.add
    i32.load
    local.set 3
    local.get 1
    call $dynrt_dynTag
    local.set 4
    local.get 3
    i32.const 5
    i32.eq
    if  ;; label = @1
      local.get 4
      i32.const 3
      i32.eq
      if  ;; label = @2
        block  ;; label = @3
          local.get 1
          call $dynrt_dynNumberValue
          local.set 5
          local.get 5
          i32.trunc_f64_s
          local.set 3
          local.get 0
          local.get 3
          local.get 2
          call $dynrt__fn92
        end
      end
    else
      local.get 3
      i32.const 6
      i32.eq
      if  ;; label = @2
        local.get 4
        i32.const 4
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 1
            call $dynrt__fn78
            global.get $dynrt_global1
            local.set 3
            global.get $dynrt_global2
            local.set 4
            local.get 0
            local.get 3
            local.get 4
            local.get 2
            call $dynrt_dynSet
          end
        end
      end
    end)
  (func $dynrt_dynStrictEq (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local f64) (local f64) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.set 2
    local.get 1
    local.set 3
    local.get 2
    i32.const 8
    i32.add
    i32.load
    local.set 4
    local.get 3
    i32.const 8
    i32.add
    i32.load
    local.set 5
    local.get 4
    local.get 5
    i32.ne
    if  ;; label = @1
      i32.const 0
      return
    end
    local.get 4
    i32.eqz
    if  ;; label = @1
      i32.const 1
      return
    end
    local.get 4
    i32.const 1
    i32.eq
    if  ;; label = @1
      i32.const 1
      return
    end
    local.get 4
    i32.const 2
    i32.eq
    if  ;; label = @1
      local.get 2
      i32.const 8
      i32.add
      i32.const 4
      i32.add
      i32.load
      local.get 3
      i32.const 8
      i32.add
      i32.const 4
      i32.add
      i32.load
      i32.eq
      if (result i32)  ;; label = @2
        i32.const 1
      else
        i32.const 0
      end
      return
    end
    local.get 4
    i32.const 3
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 2
        i32.const 8
        i32.add
        i32.const 4
        i32.add
        i32.load
        local.set 2
        local.get 3
        i32.const 8
        i32.add
        i32.const 4
        i32.add
        i32.load
        local.set 3
        local.get 2
        local.tee 8
        local.set 2
        local.get 3
        local.tee 9
        local.set 3
        local.get 2
        i32.const 8
        i32.add
        f64.load
        local.set 6
        local.get 3
        i32.const 8
        i32.add
        f64.load
        local.set 7
        local.get 6
        local.get 7
        f64.eq
        if (result i32)  ;; label = @3
          i32.const 1
        else
          i32.const 0
        end
        return
      end
    end
    local.get 4
    i32.const 4
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 2
        i32.const 8
        i32.add
        i32.const 8
        i32.add
        i32.load
        local.set 4
        local.get 4
        local.get 3
        i32.const 8
        i32.add
        i32.const 8
        i32.add
        i32.load
        i32.ne
        if  ;; label = @3
          i32.const 0
          return
        end
        local.get 2
        i32.const 8
        i32.add
        i32.const 4
        i32.add
        i32.load
        local.set 2
        local.get 3
        i32.const 8
        i32.add
        i32.const 4
        i32.add
        i32.load
        local.set 3
        local.get 2
        local.tee 10
        local.set 2
        local.get 3
        local.tee 11
        local.set 3
        i32.const 0
        local.set 5
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 5
              local.get 4
              i32.lt_s
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                local.get 2
                i32.const 8
                i32.add
                local.get 5
                i32.add
                i32.load8_u
                local.get 3
                i32.const 8
                i32.add
                local.get 5
                i32.add
                i32.load8_u
                i32.ne
                if  ;; label = @7
                  i32.const 0
                  return
                end
                local.get 5
                i32.const 1
                i32.add
                local.set 5
              end
              br 1 (;@4;)
            end
          end
        end
        i32.const 1
        return
      end
    end
    local.get 0
    local.get 1
    i32.eq
    if (result i32)  ;; label = @1
      i32.const 1
    else
      i32.const 0
    end
    return)
  (func $dynrt_dynAdd (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local f64) (local f64) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.tee 14
    local.set 2
    local.get 1
    local.tee 15
    local.set 3
    local.get 2
    i32.const 8
    i32.add
    i32.load
    i32.const 4
    i32.eq
    if (result i32)  ;; label = @1
      i32.const 1
    else
      local.get 3
      i32.const 8
      i32.add
      i32.load
      i32.const 4
      i32.eq
    end
    if  ;; label = @1
      block  ;; label = @2
        local.get 0
        call $dynrt__fn79
        global.get $dynrt_global1
        local.tee 8
        local.set 2
        global.get $dynrt_global2
        local.tee 9
        local.set 3
        local.get 1
        call $dynrt__fn79
        global.get $dynrt_global1
        local.tee 10
        local.set 4
        global.get $dynrt_global2
        local.tee 11
        local.set 5
        local.get 2
        local.tee 12
        local.set 2
        local.get 3
        local.tee 13
        local.set 3
        local.get 2
        local.get 3
        local.get 4
        local.get 5
        call $dynrt__fn4
        local.set 3
        nop
        local.set 2
        local.get 2
        local.get 3
        call $dynrt_dynString
        return
      end
    end
    local.get 0
    call $dynrt_dynToNumber
    local.set 6
    local.get 1
    call $dynrt_dynToNumber
    local.set 7
    local.get 6
    local.get 7
    f64.add
    call $dynrt_dynNumber
    return)
  (func $dynrt_dynNeg (param i32) (result i32)
    (local f64)
    local.get 0
    call $dynrt_dynToNumber
    local.set 1
    f64.const 0x0p+0 (;=0;)
    local.get 1
    f64.sub
    call $dynrt_dynNumber
    return)
  (func $dynrt_dynNot (param i32) (result i32)
    local.get 0
    call $dynrt_dynToBool
    i32.eqz
    if (result i32)  ;; label = @1
      i32.const 1
    else
      i32.const 0
    end
    call $dynrt_dynBool
    return)
  (func $dynrt_dynSub (param i32 i32) (result i32)
    (local f64) (local f64)
    local.get 0
    call $dynrt_dynToNumber
    local.set 2
    local.get 1
    call $dynrt_dynToNumber
    local.set 3
    local.get 2
    local.get 3
    f64.sub
    call $dynrt_dynNumber
    return)
  (func $dynrt_dynMul (param i32 i32) (result i32)
    (local f64) (local f64)
    local.get 0
    call $dynrt_dynToNumber
    local.set 2
    local.get 1
    call $dynrt_dynToNumber
    local.set 3
    local.get 2
    local.get 3
    f64.mul
    call $dynrt_dynNumber
    return)
  (func $dynrt_dynDiv (param i32 i32) (result i32)
    (local f64) (local f64)
    local.get 0
    call $dynrt_dynToNumber
    local.set 2
    local.get 1
    call $dynrt_dynToNumber
    local.set 3
    local.get 2
    local.get 3
    f64.div
    call $dynrt_dynNumber
    return)
  (func $dynrt_dynMod (param i32 i32) (result i32)
    (local f64) (local f64) (local f64) (local i32) (local f64) (local f64)
    local.get 0
    call $dynrt_dynToNumber
    local.set 2
    local.get 1
    call $dynrt_dynToNumber
    local.set 3
    local.get 2
    local.tee 6
    local.get 3
    local.tee 7
    f64.div
    local.set 4
    local.get 4
    f64.const 0x0p+0 (;=0;)
    f64.lt
    if (result f64)  ;; label = @1
      local.get 4
      f64.ceil
    else
      local.get 4
      f64.floor
    end
    local.set 4
    local.get 2
    local.get 3
    local.get 4
    f64.mul
    f64.sub
    call $dynrt_dynNumber
    return)
  (func $dynrt_dynLt (param i32 i32) (result i32)
    (local f64) (local f64)
    local.get 0
    call $dynrt_dynToNumber
    local.set 2
    local.get 1
    call $dynrt_dynToNumber
    local.set 3
    local.get 2
    local.get 3
    f64.lt
    if (result i32)  ;; label = @1
      i32.const 1
    else
      i32.const 0
    end
    call $dynrt_dynBool
    return)
  (func $dynrt_dynGt (param i32 i32) (result i32)
    (local f64) (local f64)
    local.get 0
    call $dynrt_dynToNumber
    local.set 2
    local.get 1
    call $dynrt_dynToNumber
    local.set 3
    local.get 2
    local.get 3
    f64.gt
    if (result i32)  ;; label = @1
      i32.const 1
    else
      i32.const 0
    end
    call $dynrt_dynBool
    return)
  (func $dynrt_dynLe (param i32 i32) (result i32)
    (local f64) (local f64)
    local.get 0
    call $dynrt_dynToNumber
    local.set 2
    local.get 1
    call $dynrt_dynToNumber
    local.set 3
    local.get 2
    local.get 3
    f64.le
    if (result i32)  ;; label = @1
      i32.const 1
    else
      i32.const 0
    end
    call $dynrt_dynBool
    return)
  (func $dynrt_dynGe (param i32 i32) (result i32)
    (local f64) (local f64)
    local.get 0
    call $dynrt_dynToNumber
    local.set 2
    local.get 1
    call $dynrt_dynToNumber
    local.set 3
    local.get 2
    local.get 3
    f64.ge
    if (result i32)  ;; label = @1
      i32.const 1
    else
      i32.const 0
    end
    call $dynrt_dynBool
    return)
  (func $dynrt_dynBuiltin (param i32) (result i32)
    (local i32) (local i32)
    call $dynrt__fn46
    local.set 1
    local.get 1
    i32.const 8
    i32.add
    i32.const 7
    i32.store
    local.get 1
    i32.const 8
    i32.add
    i32.const 4
    i32.add
    local.get 0
    i32.store
    local.get 1
    local.tee 2
    return)
  (func $dynrt__fn121 (param i32 i32 i32) (result i32)
    (local i32) (local i32)
    call $dynrt__fn47
    local.set 3
    local.get 3
    i32.const 8
    i32.add
    i32.const 7
    i32.store
    local.get 3
    i32.const 8
    i32.add
    i32.const 4
    i32.add
    i32.const -1
    i32.store
    local.get 3
    i32.const 8
    i32.add
    i32.const 8
    i32.add
    local.get 1
    i32.store
    local.get 3
    i32.const 8
    i32.add
    i32.const 12
    i32.add
    local.get 0
    i32.store
    local.get 3
    i32.const 8
    i32.add
    i32.const 16
    i32.add
    local.get 2
    i32.store
    local.get 3
    local.tee 4
    return)
  (func $dynrt_dynMakeFunc (param i32 i32 i32 i32) (result i32)
    (local i32)
    local.get 1
    local.get 2
    call $dynrt_dynString
    local.set 4
    local.get 0
    local.get 4
    local.get 3
    call $dynrt__fn121
    return)
  (func $dynrt_dynMakeHostFn (param i32) (result i32)
    (local i32) (local i32)
    call $dynrt__fn47
    local.set 1
    local.get 1
    i32.const 8
    i32.add
    i32.const 7
    i32.store
    local.get 1
    i32.const 8
    i32.add
    i32.const 4
    i32.add
    i32.const -2
    i32.store
    local.get 1
    i32.const 8
    i32.add
    i32.const 8
    i32.add
    local.get 0
    i32.store
    local.get 1
    i32.const 8
    i32.add
    i32.const 12
    i32.add
    i32.const 0
    i32.store
    local.get 1
    i32.const 8
    i32.add
    i32.const 16
    i32.add
    i32.const 0
    i32.store
    local.get 1
    local.tee 2
    return)
  (func $dynrt_dynMakeFn (param i32 i32 i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    call $dynrt_dynArray
    local.set 4
    local.get 1
    local.set 5
    i32.const 0
    local.tee 11
    local.set 6
    local.get 11
    local.set 7
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 7
          local.get 5
          i32.le_s
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 7
            local.get 5
            i32.eq
            if (result i32)  ;; label = @5
              i32.const 1
            else
              local.get 0
              local.get 1
              local.get 7
              call $dynrt__fn8
              i32.const 44
              i32.eq
            end
            if  ;; label = @5
              block  ;; label = @6
                local.get 6
                local.set 6
                local.get 7
                local.tee 9
                local.set 8
                block  ;; label = @7
                  loop  ;; label = @8
                    block  ;; label = @9
                      local.get 6
                      local.get 8
                      i32.lt_s
                      if (result i32)  ;; label = @10
                        local.get 0
                        local.get 1
                        local.get 6
                        call $dynrt__fn8
                        i32.const 32
                        i32.eq
                      else
                        i32.const 0
                      end
                      i32.eqz
                      br_if 2 (;@7;)
                      local.get 6
                      i32.const 1
                      i32.add
                      local.set 6
                      br 1 (;@8;)
                    end
                  end
                end
                block  ;; label = @7
                  loop  ;; label = @8
                    block  ;; label = @9
                      local.get 8
                      local.get 6
                      i32.gt_s
                      if (result i32)  ;; label = @10
                        local.get 0
                        local.get 1
                        local.get 8
                        i32.const 1
                        i32.sub
                        call $dynrt__fn8
                        i32.const 32
                        i32.eq
                      else
                        i32.const 0
                      end
                      i32.eqz
                      br_if 2 (;@7;)
                      local.get 8
                      i32.const 1
                      i32.sub
                      local.set 8
                      br 1 (;@8;)
                    end
                  end
                end
                local.get 8
                local.get 6
                i32.gt_s
                if  ;; label = @7
                  block  ;; label = @8
                    local.get 0
                    local.get 1
                    local.get 6
                    local.get 8
                    call $dynrt__fn5
                    local.set 8
                    nop
                    local.set 6
                    local.get 4
                    local.get 6
                    local.get 8
                    call $dynrt_dynString
                    call $dynrt_dynPush
                  end
                end
                local.get 7
                local.tee 10
                i32.const 1
                i32.add
                local.set 6
              end
            end
            local.get 7
            i32.const 1
            i32.add
            local.set 7
          end
          br 1 (;@2;)
        end
      end
    end
    call $dynrt_dynObject
    local.set 5
    local.get 4
    local.get 2
    local.get 3
    local.get 5
    call $dynrt_dynMakeFunc
    return)
  (func $dynrt__fn125 (param i32 i32 i32) (result i32)
    (local i32) (local i32) (local i32)
    local.get 0
    local.set 3
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 3
          i32.const -1
          i32.ne
          if (result i32)  ;; label = @4
            local.get 3
            i32.const 0
            i32.ne
          else
            i32.const 0
          end
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 3
            local.get 1
            local.get 2
            call $dynrt_dynGet
            local.set 4
            local.get 4
            i32.const -1
            i32.ne
            if  ;; label = @5
              local.get 4
              return
            end
            local.get 3
            local.tee 5
            local.set 3
            local.get 3
            i32.const 8
            i32.add
            i32.const 8
            i32.add
            i32.load
            local.set 3
          end
          br 1 (;@2;)
        end
      end
    end
    i32.const -1
    return)
  (func $dynrt__fn126 (param i32) (result i32)
    (local i32) (local i32) (local i32) (local i32)
    call $dynrt_dynObject
    local.set 1
    local.get 1
    local.tee 3
    local.set 2
    local.get 2
    i32.const 8
    i32.add
    i32.const 8
    i32.add
    local.get 0
    i32.store
    local.get 1
    local.tee 4
    return)
  (func $dynrt__fn127 (param i32 i32 i32 i32)
    (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.tee 8
    local.set 4
    local.get 8
    local.set 5
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 4
          i32.const -1
          i32.ne
          if (result i32)  ;; label = @4
            local.get 4
            i32.const 0
            i32.ne
          else
            i32.const 0
          end
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 4
            local.get 1
            local.get 2
            call $dynrt_dynGet
            i32.const -1
            i32.ne
            if  ;; label = @5
              block  ;; label = @6
                local.get 4
                local.get 1
                local.get 2
                local.get 3
                call $dynrt_dynSet
                return
              end
            end
            local.get 4
            local.tee 6
            local.set 5
            local.get 4
            local.tee 7
            local.set 4
            local.get 4
            i32.const 8
            i32.add
            i32.const 8
            i32.add
            i32.load
            local.set 4
          end
          br 1 (;@2;)
        end
      end
    end
    local.get 5
    i32.const -1
    i32.ne
    if (result i32)  ;; label = @1
      local.get 5
      i32.const 0
      i32.ne
    else
      i32.const 0
    end
    if  ;; label = @1
      local.get 5
      local.get 1
      local.get 2
      local.get 3
      call $dynrt_dynSet
    end)
  (func $dynrt__fn128 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 1
    call $dynrt__fn126
    local.set 2
    local.get 0
    local.set 3
    local.get 2
    local.tee 16
    local.set 4
    local.get 3
    i32.const 8
    i32.add
    i32.const 4
    i32.add
    i32.load
    call $dynrt__fn29
    local.set 5
    i32.const 0
    local.set 6
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 6
          local.get 5
          i32.lt_s
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 3
            i32.const 8
            i32.add
            i32.const 12
            i32.add
            i32.load
            local.get 6
            i32.const 2
            i32.mul
            call $dynrt__fn30
            local.set 7
            local.get 3
            i32.const 8
            i32.add
            i32.const 12
            i32.add
            i32.load
            local.get 6
            i32.const 2
            i32.mul
            i32.const 1
            i32.add
            call $dynrt__fn30
            local.set 8
            local.get 3
            i32.const 8
            i32.add
            i32.const 4
            i32.add
            i32.load
            local.get 6
            call $dynrt__fn30
            local.set 9
            local.get 7
            local.tee 13
            local.set 7
            i32.const 8
            local.get 8
            i32.add
            call $dynrt__fn38
            local.set 10
            i32.const 0
            local.set 11
            block  ;; label = @5
              loop  ;; label = @6
                block  ;; label = @7
                  local.get 11
                  local.get 8
                  i32.lt_s
                  i32.eqz
                  br_if 2 (;@5;)
                  block  ;; label = @8
                    local.get 10
                    i32.const 8
                    i32.add
                    local.get 11
                    i32.add
                    local.get 7
                    i32.const 8
                    i32.add
                    local.get 11
                    i32.add
                    i32.load8_u
                    i32.store8
                    local.get 11
                    local.tee 12
                    i32.const 1
                    i32.add
                    local.set 11
                  end
                  br 1 (;@6;)
                end
              end
            end
            local.get 4
            i32.const 8
            i32.add
            i32.const 12
            i32.add
            i32.load
            local.set 7
            local.get 7
            local.get 10
            call $dynrt__fn32
            local.set 7
            local.get 7
            local.get 8
            call $dynrt__fn32
            local.set 7
            local.get 4
            i32.const 8
            i32.add
            i32.const 12
            i32.add
            local.get 7
            i32.store
            local.get 4
            i32.const 8
            i32.add
            i32.const 4
            i32.add
            local.get 4
            i32.const 8
            i32.add
            i32.const 4
            i32.add
            i32.load
            local.get 9
            call $dynrt__fn32
            i32.store
            local.get 6
            local.tee 14
            i32.const 1
            local.tee 15
            i32.add
            local.set 6
          end
          br 1 (;@2;)
        end
      end
    end
    local.get 2
    local.tee 17
    return)
  (func $dynrt_dynApply (param i32 i32) (result i32)
    local.get 0
    local.get 1
    i32.const -1
    call $dynrt__fn130
    return)
  (func $dynrt__fn130 (param i32 i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local f64) (local f64) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.set 3
    local.get 3
    i32.const 8
    i32.add
    i32.load
    i32.const 7
    i32.ne
    if  ;; label = @1
      call $dynrt_dynUndefined
      return
    end
    local.get 3
    i32.const 8
    i32.add
    i32.const 4
    i32.add
    i32.load
    local.set 4
    local.get 4
    i32.const -2
    i32.eq
    if  ;; label = @1
      local.get 3
      i32.const 8
      i32.add
      i32.const 8
      i32.add
      i32.load
      local.get 1
      call $dynrt___host_call
      return
    end
    local.get 1
    call $dynrt_dynArrLen
    local.set 5
    local.get 4
    i32.const -1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 3
        i32.const 8
        i32.add
        i32.const 8
        i32.add
        i32.load
        local.set 4
        local.get 3
        i32.const 8
        i32.add
        i32.const 12
        i32.add
        i32.load
        local.set 6
        local.get 3
        i32.const 8
        i32.add
        i32.const 16
        i32.add
        i32.load
        local.set 3
        call $dynrt_dynObject
        local.set 7
        local.get 7
        local.tee 15
        local.set 8
        local.get 8
        i32.const 8
        i32.add
        i32.const 8
        i32.add
        local.get 3
        i32.store
        local.get 2
        i32.const -1
        i32.ne
        if  ;; label = @3
          local.get 7
          i32.const 880
          i32.const 4
          local.get 2
          call $dynrt_dynSet
        end
        local.get 6
        call $dynrt_dynArrLen
        local.set 3
        i32.const 0
        local.set 8
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 8
              local.get 3
              i32.lt_s
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                local.get 6
                local.get 8
                call $dynrt_dynArrGet
                local.set 9
                local.get 9
                call $dynrt__fn78
                global.get $dynrt_global1
                local.set 9
                global.get $dynrt_global2
                local.set 10
                local.get 8
                local.get 5
                i32.lt_s
                if (result i32)  ;; label = @7
                  local.get 1
                  local.get 8
                  call $dynrt_dynArrGet
                else
                  call $dynrt_dynUndefined
                end
                local.set 11
                local.get 7
                local.get 9
                local.get 10
                local.get 11
                call $dynrt_dynSet
                local.get 8
                local.tee 14
                i32.const 1
                i32.add
                local.set 8
              end
              br 1 (;@4;)
            end
          end
        end
        local.get 4
        call $dynrt__fn78
        global.get $dynrt_global1
        local.set 3
        global.get $dynrt_global2
        local.set 4
        global.get $dynrt_global19
        local.set 5
        global.get $dynrt_global20
        local.set 6
        global.get $dynrt_global21
        local.set 8
        global.get $dynrt_global23
        local.set 9
        global.get $dynrt_global24
        local.set 10
        global.get $dynrt_global25
        local.set 11
        local.get 3
        local.get 4
        local.get 7
        call $dynrt_dynRun
        local.set 3
        local.get 5
        global.set $dynrt_global19
        local.get 6
        local.tee 16
        global.set $dynrt_global20
        local.get 8
        local.tee 17
        global.set $dynrt_global21
        local.get 9
        global.set $dynrt_global23
        local.get 10
        global.set $dynrt_global24
        local.get 11
        global.set $dynrt_global25
        local.get 3
        local.tee 18
        return
      end
    end
    local.get 4
    i32.const 8
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_global22
        local.tee 19
        i32.const 1
        i32.add
        global.set $dynrt_global22
        global.get $dynrt_global22
        local.tee 20
        local.set 3
        local.get 3
        f64.convert_i32_s
        call $dynrt_dynNumber
        return
      end
    end
    local.get 5
    i32.const 0
    i32.gt_s
    if (result i32)  ;; label = @1
      local.get 1
      i32.const 0
      call $dynrt_dynArrGet
    else
      call $dynrt_dynUndefined
    end
    local.set 3
    local.get 4
    i32.const 7
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 3
        call $dynrt_dynTag
        local.set 4
        local.get 4
        i32.const 4
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 3
            local.tee 21
            local.set 3
            local.get 3
            i32.const 8
            i32.add
            i32.const 8
            i32.add
            i32.load
            local.set 3
            local.get 3
            f64.convert_i32_s
            call $dynrt_dynNumber
            return
          end
        end
        local.get 4
        i32.const 5
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 3
            call $dynrt_dynArrLen
            local.set 3
            local.get 3
            f64.convert_i32_s
            call $dynrt_dynNumber
            return
          end
        end
        f64.const 0x0p+0 (;=0;)
        call $dynrt_dynNumber
        return
      end
    end
    local.get 3
    call $dynrt_dynToNumber
    local.set 12
    local.get 4
    i32.eqz
    if  ;; label = @1
      local.get 12
      f64.abs
      call $dynrt_dynNumber
      return
    end
    local.get 4
    i32.const 1
    i32.eq
    if  ;; label = @1
      local.get 12
      f64.sqrt
      call $dynrt_dynNumber
      return
    end
    local.get 4
    i32.const 2
    i32.eq
    if  ;; label = @1
      local.get 12
      f64.floor
      call $dynrt_dynNumber
      return
    end
    local.get 4
    i32.const 3
    i32.eq
    if  ;; label = @1
      local.get 12
      f64.ceil
      call $dynrt_dynNumber
      return
    end
    local.get 4
    i32.const 4
    i32.eq
    if  ;; label = @1
      local.get 12
      f64.const 0x1.0p-1 (;=0.5;)
      f64.add
      f64.floor
      call $dynrt_dynNumber
      return
    end
    local.get 5
    i32.const 1
    i32.gt_s
    if (result i32)  ;; label = @1
      local.get 1
      i32.const 1
      call $dynrt_dynArrGet
    else
      call $dynrt_dynUndefined
    end
    local.set 3
    local.get 3
    call $dynrt_dynToNumber
    local.set 13
    local.get 4
    i32.const 5
    i32.eq
    if  ;; label = @1
      local.get 12
      local.get 13
      f64.lt
      if (result f64)  ;; label = @2
        local.get 12
      else
        local.get 13
      end
      call $dynrt_dynNumber
      return
    end
    local.get 4
    i32.const 6
    i32.eq
    if  ;; label = @1
      local.get 12
      local.get 13
      f64.gt
      if (result f64)  ;; label = @2
        local.get 12
      else
        local.get 13
      end
      call $dynrt_dynNumber
      return
    end
    call $dynrt_dynUndefined
    return)
  (func $dynrt_dynCall0 (param i32) (result i32)
    (local i32)
    call $dynrt_dynArray
    local.set 1
    local.get 0
    local.get 1
    call $dynrt_dynApply
    return)
  (func $dynrt_dynCall1 (param i32 i32) (result i32)
    (local i32)
    call $dynrt_dynArray
    local.set 2
    local.get 2
    local.get 1
    call $dynrt_dynPush
    local.get 0
    local.get 2
    call $dynrt_dynApply
    return)
  (func $dynrt_dynCall2 (param i32 i32 i32) (result i32)
    (local i32)
    call $dynrt_dynArray
    local.set 3
    local.get 3
    local.get 1
    call $dynrt_dynPush
    local.get 3
    local.get 2
    call $dynrt_dynPush
    local.get 0
    local.get 3
    call $dynrt_dynApply
    return)
  (func $dynrt_dynCall3 (param i32 i32 i32 i32) (result i32)
    (local i32)
    call $dynrt_dynArray
    local.set 4
    local.get 4
    local.get 1
    call $dynrt_dynPush
    local.get 4
    local.get 2
    call $dynrt_dynPush
    local.get 4
    local.get 3
    call $dynrt_dynPush
    local.get 0
    local.get 4
    call $dynrt_dynApply
    return)
  (func $dynrt_dynStdEnv (result i32)
    (local i32) (local i32)
    call $dynrt_dynObject
    local.set 0
    local.get 0
    i32.const 803
    i32.const 3
    i32.const 0
    call $dynrt_dynBuiltin
    call $dynrt_dynSet
    local.get 0
    i32.const 806
    i32.const 4
    i32.const 1
    call $dynrt_dynBuiltin
    call $dynrt_dynSet
    local.get 0
    i32.const 789
    i32.const 5
    i32.const 2
    call $dynrt_dynBuiltin
    call $dynrt_dynSet
    local.get 0
    i32.const 794
    i32.const 4
    i32.const 3
    call $dynrt_dynBuiltin
    call $dynrt_dynSet
    local.get 0
    i32.const 798
    i32.const 5
    i32.const 4
    call $dynrt_dynBuiltin
    call $dynrt_dynSet
    local.get 0
    i32.const 822
    i32.const 3
    i32.const 5
    call $dynrt_dynBuiltin
    call $dynrt_dynSet
    local.get 0
    i32.const 819
    i32.const 3
    i32.const 6
    call $dynrt_dynBuiltin
    call $dynrt_dynSet
    local.get 0
    i32.const 884
    i32.const 3
    i32.const 7
    call $dynrt_dynBuiltin
    call $dynrt_dynSet
    local.get 0
    i32.const 887
    i32.const 3
    i32.const 8
    call $dynrt_dynBuiltin
    call $dynrt_dynSet
    local.get 0
    local.tee 1
    return)
  (func $dynrt_dynSideEffectCount (result i32)
    global.get $dynrt_global22
    return)
  (func $dynrt_dynResetSideEffects
    i32.const 0
    global.set $dynrt_global22)
  (func $dynrt__fn138 (param i32 i32 i32 i32) (result i32)
    (local i32)
    local.get 1
    local.get 3
    i32.ne
    if  ;; label = @1
      i32.const 0
      return
    end
    i32.const 0
    local.set 4
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 4
          local.get 1
          i32.lt_s
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 0
            local.get 1
            local.get 4
            call $dynrt__fn8
            local.get 2
            local.get 3
            local.get 4
            call $dynrt__fn8
            i32.ne
            if  ;; label = @5
              i32.const 0
              return
            end
            local.get 4
            i32.const 1
            i32.add
            local.set 4
          end
          br 1 (;@2;)
        end
      end
    end
    i32.const 1
    return)
  (func $dynrt_dynMember (param i32 i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.set 3
    local.get 3
    i32.const 8
    i32.add
    i32.load
    local.set 4
    local.get 4
    i32.const 6
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 0
        local.tee 10
        local.set 3
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 3
              i32.const 0
              i32.ne
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                local.get 3
                local.tee 8
                local.set 4
                local.get 4
                i32.const 8
                i32.add
                i32.load
                i32.const 6
                i32.ne
                if  ;; label = @7
                  br 4 (;@3;)
                end
                local.get 3
                local.get 1
                local.get 2
                call $dynrt_dynGet
                local.set 3
                local.get 3
                i32.const -1
                i32.ne
                if  ;; label = @7
                  local.get 3
                  return
                end
                local.get 4
                i32.const 8
                i32.add
                i32.const 8
                i32.add
                i32.load
                local.set 3
              end
              br 1 (;@4;)
            end
          end
        end
        local.get 1
        local.get 2
        i32.const 890
        i32.const 4
        call $dynrt__fn138
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 0
            i32.const 844
            i32.const 6
            call $dynrt_dynGet
            local.set 3
            local.get 3
            i32.const -1
            i32.ne
            if  ;; label = @5
              block  ;; label = @6
                local.get 3
                call $dynrt_dynArrLen
                local.set 3
                local.get 3
                f64.convert_i32_s
                call $dynrt_dynNumber
                return
              end
            end
            local.get 0
            i32.const 856
            i32.const 6
            call $dynrt_dynGet
            local.set 3
            local.get 3
            i32.const -1
            i32.ne
            if  ;; label = @5
              block  ;; label = @6
                local.get 3
                call $dynrt_dynArrLen
                local.set 3
                local.get 3
                f64.convert_i32_s
                call $dynrt_dynNumber
                return
              end
            end
          end
        end
        i32.const 894
        local.set 3
        i32.const 6
        local.set 4
        local.get 3
        local.get 4
        local.get 1
        local.get 2
        call $dynrt__fn4
        local.set 4
        nop
        local.set 3
        local.get 0
        local.tee 11
        local.set 5
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 5
              i32.const 0
              i32.ne
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                local.get 5
                local.tee 9
                local.set 6
                local.get 6
                i32.const 8
                i32.add
                i32.load
                i32.const 6
                i32.ne
                if  ;; label = @7
                  br 4 (;@3;)
                end
                local.get 5
                local.get 3
                local.get 4
                call $dynrt_dynGet
                local.set 5
                local.get 5
                i32.const -1
                i32.ne
                if  ;; label = @7
                  block  ;; label = @8
                    local.get 5
                    local.set 7
                    local.get 7
                    i32.const 8
                    i32.add
                    i32.load
                    i32.const 7
                    i32.eq
                    if  ;; label = @9
                      block  ;; label = @10
                        call $dynrt_dynArray
                        local.set 3
                        local.get 5
                        local.get 3
                        local.get 0
                        call $dynrt__fn130
                        return
                      end
                    end
                  end
                end
                local.get 6
                i32.const 8
                i32.add
                i32.const 8
                i32.add
                i32.load
                local.set 5
              end
              br 1 (;@4;)
            end
          end
        end
        call $dynrt_dynUndefined
        return
      end
    end
    local.get 4
    i32.const 5
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 1
        local.get 2
        i32.const 900
        i32.const 6
        call $dynrt__fn138
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 0
            call $dynrt_dynArrLen
            local.set 3
            local.get 3
            f64.convert_i32_s
            call $dynrt_dynNumber
            return
          end
        end
        call $dynrt_dynUndefined
        return
      end
    end
    local.get 4
    i32.const 4
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 1
        local.get 2
        i32.const 900
        i32.const 6
        call $dynrt__fn138
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 3
            i32.const 8
            i32.add
            i32.const 8
            i32.add
            i32.load
            local.set 3
            local.get 3
            f64.convert_i32_s
            call $dynrt_dynNumber
            return
          end
        end
        call $dynrt_dynUndefined
        return
      end
    end
    call $dynrt_dynUndefined
    return)
  (func $dynrt__fn140 (param i32 i32 i32 i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.tee 10
    local.set 4
    local.get 4
    i32.const 8
    i32.add
    i32.load
    i32.const 6
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        i32.const 906
        local.set 4
        i32.const 6
        local.set 5
        local.get 4
        local.get 5
        local.get 1
        local.get 2
        call $dynrt__fn4
        local.set 5
        nop
        local.set 4
        local.get 0
        local.set 6
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 6
              i32.const 0
              i32.ne
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                local.get 6
                local.tee 9
                local.set 7
                local.get 7
                i32.const 8
                i32.add
                i32.load
                i32.const 6
                i32.ne
                if  ;; label = @7
                  br 4 (;@3;)
                end
                local.get 6
                local.get 4
                local.get 5
                call $dynrt_dynGet
                local.set 6
                local.get 6
                i32.const -1
                i32.ne
                if  ;; label = @7
                  block  ;; label = @8
                    local.get 6
                    local.set 8
                    local.get 8
                    i32.const 8
                    i32.add
                    i32.load
                    i32.const 7
                    i32.eq
                    if  ;; label = @9
                      block  ;; label = @10
                        call $dynrt_dynArray
                        local.set 4
                        local.get 4
                        local.get 3
                        call $dynrt_dynPush
                        local.get 6
                        local.get 4
                        local.get 0
                        call $dynrt__fn130
                        drop
                        return
                      end
                    end
                  end
                end
                local.get 7
                i32.const 8
                i32.add
                i32.const 8
                i32.add
                i32.load
                local.set 6
              end
              br 1 (;@4;)
            end
          end
        end
      end
    end
    local.get 0
    local.get 1
    local.get 2
    local.get 3
    call $dynrt_dynSet)
  (func $dynrt_dynIndexValue (param i32 i32) (result i32)
    (local i32) (local i32) (local f64)
    local.get 0
    local.set 2
    local.get 2
    i32.const 8
    i32.add
    i32.load
    local.set 2
    local.get 1
    call $dynrt_dynTag
    local.set 3
    local.get 2
    i32.const 5
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 3
        i32.const 3
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 1
            call $dynrt_dynNumberValue
            local.set 4
            local.get 4
            i32.trunc_f64_s
            local.set 2
            local.get 0
            call $dynrt_dynArrLen
            local.set 3
            local.get 2
            i32.const 0
            i32.lt_s
            if (result i32)  ;; label = @5
              i32.const 1
            else
              local.get 2
              local.get 3
              i32.ge_s
            end
            if  ;; label = @5
              call $dynrt_dynUndefined
              return
            end
            local.get 0
            local.get 2
            call $dynrt_dynArrGet
            return
          end
        end
        call $dynrt_dynUndefined
        return
      end
    end
    local.get 2
    i32.const 6
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 3
        i32.const 4
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 1
            call $dynrt__fn78
            global.get $dynrt_global1
            local.set 2
            global.get $dynrt_global2
            local.set 3
            local.get 0
            local.get 2
            local.get 3
            call $dynrt_dynGet
            local.set 2
            local.get 2
            i32.const -1
            i32.eq
            if (result i32)  ;; label = @5
              call $dynrt_dynUndefined
            else
              local.get 2
            end
            return
          end
        end
        call $dynrt_dynUndefined
        return
      end
    end
    call $dynrt_dynUndefined
    return)
  (func $dynrt__fn142 (param i32 i32) (result i32)
    local.get 0
    i32.const 65
    i32.ge_s
    if (result i32)  ;; label = @1
      local.get 0
      i32.const 90
      i32.le_s
    else
      i32.const 0
    end
    if  ;; label = @1
      i32.const 1
      return
    end
    local.get 0
    i32.const 97
    i32.ge_s
    if (result i32)  ;; label = @1
      local.get 0
      i32.const 122
      i32.le_s
    else
      i32.const 0
    end
    if  ;; label = @1
      i32.const 1
      return
    end
    local.get 0
    i32.const 95
    i32.eq
    if (result i32)  ;; label = @1
      i32.const 1
    else
      local.get 0
      i32.const 36
      i32.eq
    end
    if  ;; label = @1
      i32.const 1
      return
    end
    local.get 1
    i32.const 1
    i32.eq
    if (result i32)  ;; label = @1
      local.get 0
      i32.const 48
      i32.ge_s
    else
      i32.const 0
    end
    if (result i32)  ;; label = @1
      local.get 0
      i32.const 57
      i32.le_s
    else
      i32.const 0
    end
    if  ;; label = @1
      i32.const 1
      return
    end
    i32.const 0
    return)
  (func $dynrt__fn143 (param i32 i32)
    (local i32) (local i32)
    i32.const 1
    local.set 2
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 2
          i32.const 1
          i32.eq
          i32.eqz
          br_if 2 (;@1;)
          global.get $dynrt_global19
          local.get 1
          i32.ge_s
          if  ;; label = @4
            i32.const 0
            local.set 2
          else
            block  ;; label = @5
              local.get 0
              local.get 1
              global.get $dynrt_global19
              call $dynrt__fn8
              local.set 3
              local.get 3
              i32.const 32
              i32.eq
              if (result i32)  ;; label = @6
                i32.const 1
              else
                local.get 3
                i32.const 9
                i32.eq
              end
              if (result i32)  ;; label = @6
                i32.const 1
              else
                local.get 3
                i32.const 10
                i32.eq
              end
              if (result i32)  ;; label = @6
                i32.const 1
              else
                local.get 3
                i32.const 13
                i32.eq
              end
              if  ;; label = @6
                global.get $dynrt_global19
                i32.const 1
                i32.add
                global.set $dynrt_global19
              else
                i32.const 0
                local.set 2
              end
            end
          end
          br 1 (;@2;)
        end
      end
    end)
  (func $dynrt__fn144 (param i32 i32) (result i32)
    (local i32)
    global.get $dynrt_global19
    local.get 1
    i32.ge_s
    if  ;; label = @1
      i32.const -1
      return
    end
    local.get 0
    local.get 1
    global.get $dynrt_global19
    call $dynrt__fn8
    return)
  (func $dynrt__fn145 (param i32 i32) (result i32)
    (local i32)
    global.get $dynrt_global19
    i32.const 1
    i32.add
    local.get 1
    i32.ge_s
    if  ;; label = @1
      i32.const -1
      return
    end
    local.get 0
    local.get 1
    global.get $dynrt_global19
    i32.const 1
    i32.add
    call $dynrt__fn8
    return)
  (func $dynrt__fn146 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32)
    global.get $dynrt_global19
    local.tee 4
    local.set 2
    local.get 0
    local.get 1
    call $dynrt__fn144
    local.set 3
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 3
          i32.const 48
          i32.ge_s
          if (result i32)  ;; label = @4
            local.get 3
            i32.const 57
            i32.le_s
          else
            i32.const 0
          end
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            global.get $dynrt_global19
            i32.const 1
            i32.add
            global.set $dynrt_global19
            local.get 0
            local.get 1
            call $dynrt__fn144
            local.set 3
          end
          br 1 (;@2;)
        end
      end
    end
    local.get 3
    i32.const 46
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_global19
        i32.const 1
        i32.add
        global.set $dynrt_global19
        local.get 0
        local.get 1
        call $dynrt__fn144
        local.set 3
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 3
              i32.const 48
              i32.ge_s
              if (result i32)  ;; label = @6
                local.get 3
                i32.const 57
                i32.le_s
              else
                i32.const 0
              end
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                global.get $dynrt_global19
                i32.const 1
                i32.add
                global.set $dynrt_global19
                local.get 0
                local.get 1
                call $dynrt__fn144
                local.set 3
              end
              br 1 (;@4;)
            end
          end
        end
      end
    end
    local.get 3
    i32.const 101
    i32.eq
    if (result i32)  ;; label = @1
      i32.const 1
    else
      local.get 3
      i32.const 69
      i32.eq
    end
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_global19
        i32.const 1
        i32.add
        global.set $dynrt_global19
        local.get 0
        local.get 1
        call $dynrt__fn144
        local.set 3
        local.get 3
        i32.const 43
        i32.eq
        if (result i32)  ;; label = @3
          i32.const 1
        else
          local.get 3
          i32.const 45
          i32.eq
        end
        if  ;; label = @3
          block  ;; label = @4
            global.get $dynrt_global19
            i32.const 1
            i32.add
            global.set $dynrt_global19
            local.get 0
            local.get 1
            call $dynrt__fn144
            local.set 3
          end
        end
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 3
              i32.const 48
              i32.ge_s
              if (result i32)  ;; label = @6
                local.get 3
                i32.const 57
                i32.le_s
              else
                i32.const 0
              end
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                global.get $dynrt_global19
                i32.const 1
                i32.add
                global.set $dynrt_global19
                local.get 0
                local.get 1
                call $dynrt__fn144
                local.set 3
              end
              br 1 (;@4;)
            end
          end
        end
      end
    end
    local.get 0
    local.get 1
    local.get 2
    global.get $dynrt_global19
    call $dynrt__fn5
    local.set 3
    nop
    local.set 2
    local.get 2
    local.get 3
    call $dynrt__fn22
    call $dynrt_dynNumber
    return)
  (func $dynrt__fn147 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt__fn144
    local.set 2
    global.get $dynrt_global19
    i32.const 1
    local.tee 16
    i32.add
    global.set $dynrt_global19
    i32.const 534
    local.set 3
    i32.const 0
    local.set 4
    i32.const 1
    local.tee 17
    local.set 5
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 5
          i32.const 1
          i32.eq
          i32.eqz
          br_if 2 (;@1;)
          global.get $dynrt_global19
          local.get 1
          i32.ge_s
          if  ;; label = @4
            i32.const 0
            local.set 5
          else
            block  ;; label = @5
              local.get 0
              local.get 1
              global.get $dynrt_global19
              call $dynrt__fn8
              local.set 6
              local.get 6
              local.get 2
              i32.eq
              if  ;; label = @6
                block  ;; label = @7
                  global.get $dynrt_global19
                  i32.const 1
                  i32.add
                  global.set $dynrt_global19
                  i32.const 0
                  local.set 5
                end
              else
                local.get 6
                i32.const 92
                i32.eq
                if  ;; label = @7
                  block  ;; label = @8
                    global.get $dynrt_global19
                    i32.const 1
                    i32.add
                    local.tee 9
                    global.set $dynrt_global19
                    local.get 0
                    local.get 1
                    global.get $dynrt_global19
                    call $dynrt__fn8
                    local.set 6
                    local.get 6
                    local.set 7
                    local.get 6
                    i32.const 110
                    i32.eq
                    if  ;; label = @9
                      i32.const 10
                      local.set 7
                    else
                      local.get 6
                      i32.const 116
                      i32.eq
                      if  ;; label = @10
                        i32.const 9
                        local.set 7
                      else
                        local.get 6
                        i32.const 114
                        i32.eq
                        if  ;; label = @11
                          i32.const 13
                          local.set 7
                        end
                      end
                    end
                    local.get 3
                    local.tee 10
                    local.set 3
                    local.get 4
                    local.tee 11
                    local.set 4
                    i32.const 1
                    call $__malloc
                    local.set 8
                    local.get 8
                    local.get 7
                    i32.store8
                    local.get 3
                    local.get 4
                    local.get 8
                    i32.const 1
                    call $dynrt__fn4
                    local.set 4
                    nop
                    local.set 3
                    global.get $dynrt_global19
                    i32.const 1
                    i32.add
                    local.tee 12
                    global.set $dynrt_global19
                  end
                else
                  block  ;; label = @8
                    local.get 3
                    local.tee 13
                    local.set 3
                    local.get 4
                    local.tee 14
                    local.set 4
                    i32.const 1
                    call $__malloc
                    local.set 8
                    local.get 8
                    local.get 6
                    i32.store8
                    local.get 3
                    local.get 4
                    local.get 8
                    i32.const 1
                    call $dynrt__fn4
                    local.set 4
                    nop
                    local.set 3
                    global.get $dynrt_global19
                    i32.const 1
                    local.tee 15
                    i32.add
                    global.set $dynrt_global19
                  end
                end
              end
            end
          end
          br 1 (;@2;)
        end
      end
    end
    local.get 3
    local.get 4
    call $dynrt_dynString
    return)
  (func $dynrt__fn148 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt__fn143
    local.get 0
    local.get 1
    call $dynrt__fn144
    local.set 2
    local.get 2
    i32.const 40
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 0
        local.get 1
        call $dynrt__fn179
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt__fn175
            local.set 2
            local.get 0
            local.get 1
            call $dynrt__fn143
            local.get 0
            local.get 1
            call $dynrt__fn144
            i32.const 61
            i32.eq
            if (result i32)  ;; label = @5
              local.get 0
              local.get 1
              call $dynrt__fn145
              i32.const 62
              i32.eq
            else
              i32.const 0
            end
            if  ;; label = @5
              global.get $dynrt_global19
              i32.const 2
              i32.add
              global.set $dynrt_global19
            end
            local.get 2
            local.get 0
            local.get 1
            call $dynrt__fn177
            global.get $dynrt_global20
            call $dynrt__fn121
            return
          end
        end
        global.get $dynrt_global19
        i32.const 1
        i32.add
        global.set $dynrt_global19
        local.get 0
        local.get 1
        call $dynrt__fn158
        local.set 2
        local.get 0
        local.get 1
        call $dynrt__fn143
        local.get 0
        local.get 1
        call $dynrt__fn144
        i32.const 41
        i32.eq
        if  ;; label = @3
          global.get $dynrt_global19
          i32.const 1
          i32.add
          global.set $dynrt_global19
        end
        local.get 2
        return
      end
    end
    local.get 2
    i32.const 39
    i32.eq
    if (result i32)  ;; label = @1
      i32.const 1
    else
      local.get 2
      i32.const 34
      i32.eq
    end
    if  ;; label = @1
      local.get 0
      local.get 1
      call $dynrt__fn147
      return
    end
    local.get 2
    i32.const 91
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_global19
        i32.const 1
        i32.add
        global.set $dynrt_global19
        call $dynrt_dynArray
        local.set 2
        local.get 0
        local.get 1
        call $dynrt__fn143
        local.get 0
        local.get 1
        call $dynrt__fn144
        i32.const 93
        i32.eq
        if (result i32)  ;; label = @3
          i32.const 0
        else
          i32.const 1
        end
        local.set 3
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 3
              i32.const 1
              i32.eq
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                local.get 0
                local.get 1
                call $dynrt__fn143
                i32.const 0
                local.set 4
                local.get 0
                local.get 1
                call $dynrt__fn144
                i32.const 46
                i32.eq
                if (result i32)  ;; label = @7
                  local.get 0
                  local.get 1
                  call $dynrt__fn145
                  i32.const 46
                  i32.eq
                else
                  i32.const 0
                end
                if  ;; label = @7
                  global.get $dynrt_global19
                  i32.const 2
                  i32.add
                  local.get 1
                  i32.lt_s
                  if  ;; label = @8
                    local.get 0
                    local.get 1
                    global.get $dynrt_global19
                    i32.const 2
                    i32.add
                    call $dynrt__fn8
                    i32.const 46
                    i32.eq
                    if  ;; label = @9
                      i32.const 1
                      local.set 4
                    end
                  end
                end
                local.get 4
                i32.const 1
                i32.eq
                if  ;; label = @7
                  block  ;; label = @8
                    global.get $dynrt_global19
                    i32.const 3
                    i32.add
                    global.set $dynrt_global19
                    local.get 0
                    local.get 1
                    call $dynrt__fn158
                    local.set 4
                    local.get 4
                    local.set 5
                    local.get 5
                    i32.const 8
                    i32.add
                    i32.load
                    i32.const 5
                    i32.eq
                    if  ;; label = @9
                      block  ;; label = @10
                        local.get 4
                        call $dynrt_dynArrLen
                        local.set 5
                        i32.const 0
                        local.set 6
                        block  ;; label = @11
                          loop  ;; label = @12
                            block  ;; label = @13
                              local.get 6
                              local.get 5
                              i32.lt_s
                              i32.eqz
                              br_if 2 (;@11;)
                              block  ;; label = @14
                                local.get 2
                                local.get 4
                                local.get 6
                                call $dynrt_dynArrGet
                                call $dynrt_dynPush
                                local.get 6
                                local.tee 8
                                i32.const 1
                                i32.add
                                local.set 6
                              end
                              br 1 (;@12;)
                            end
                          end
                        end
                      end
                    end
                  end
                else
                  local.get 2
                  local.get 0
                  local.get 1
                  call $dynrt__fn158
                  call $dynrt_dynPush
                end
                local.get 0
                local.get 1
                call $dynrt__fn143
                local.get 0
                local.get 1
                call $dynrt__fn144
                i32.const 44
                i32.eq
                if  ;; label = @7
                  block  ;; label = @8
                    global.get $dynrt_global19
                    i32.const 1
                    i32.add
                    global.set $dynrt_global19
                    local.get 0
                    local.get 1
                    call $dynrt__fn143
                    local.get 0
                    local.get 1
                    call $dynrt__fn144
                    i32.const 93
                    i32.eq
                    if  ;; label = @9
                      i32.const 0
                      local.set 3
                    end
                  end
                else
                  i32.const 0
                  local.set 3
                end
              end
              br 1 (;@4;)
            end
          end
        end
        local.get 0
        local.get 1
        call $dynrt__fn143
        local.get 0
        local.get 1
        call $dynrt__fn144
        i32.const 93
        i32.eq
        if  ;; label = @3
          global.get $dynrt_global19
          i32.const 1
          i32.add
          global.set $dynrt_global19
        end
        local.get 2
        return
      end
    end
    local.get 2
    i32.const 123
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_global19
        i32.const 1
        i32.add
        global.set $dynrt_global19
        call $dynrt_dynObject
        local.set 2
        local.get 0
        local.get 1
        call $dynrt__fn143
        local.get 0
        local.get 1
        call $dynrt__fn144
        i32.const 125
        i32.eq
        if (result i32)  ;; label = @3
          i32.const 0
        else
          i32.const 1
        end
        local.set 3
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 3
              i32.const 1
              i32.eq
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                local.get 0
                local.get 1
                call $dynrt__fn143
                i32.const 0
                local.tee 9
                drop
                local.get 0
                local.get 1
                call $dynrt__fn144
                local.set 4
                local.get 4
                i32.const 39
                i32.eq
                if (result i32)  ;; label = @7
                  i32.const 1
                else
                  local.get 4
                  i32.const 34
                  i32.eq
                end
                if  ;; label = @7
                  block  ;; label = @8
                    local.get 0
                    local.get 1
                    call $dynrt__fn147
                    call $dynrt__fn78
                    global.get $dynrt_global1
                    local.set 4
                    global.get $dynrt_global2
                    local.set 5
                  end
                else
                  block  ;; label = @8
                    local.get 0
                    local.get 1
                    call $dynrt__fn161
                    global.get $dynrt_global1
                    local.set 4
                    global.get $dynrt_global2
                    local.set 5
                  end
                end
                local.get 0
                local.get 1
                call $dynrt__fn143
                i32.const 0
                local.tee 10
                drop
                local.get 0
                local.get 1
                call $dynrt__fn144
                i32.const 58
                i32.eq
                if  ;; label = @7
                  block  ;; label = @8
                    global.get $dynrt_global19
                    i32.const 1
                    i32.add
                    global.set $dynrt_global19
                    local.get 0
                    local.get 1
                    call $dynrt__fn158
                    local.set 6
                  end
                else
                  local.get 0
                  local.get 1
                  call $dynrt__fn144
                  i32.const 40
                  i32.eq
                  if  ;; label = @8
                    block  ;; label = @9
                      local.get 0
                      local.get 1
                      call $dynrt__fn175
                      local.set 6
                      local.get 0
                      local.get 1
                      call $dynrt__fn143
                      local.get 6
                      local.get 0
                      local.get 1
                      call $dynrt__fn176
                      global.get $dynrt_global20
                      call $dynrt__fn121
                      local.set 6
                    end
                  else
                    block  ;; label = @9
                      global.get $dynrt_global20
                      i32.const -1
                      i32.eq
                      if (result i32)  ;; label = @10
                        call $dynrt_dynUndefined
                      else
                        global.get $dynrt_global20
                        local.get 4
                        local.get 5
                        call $dynrt__fn125
                      end
                      local.set 6
                      local.get 6
                      i32.const -1
                      i32.eq
                      if  ;; label = @10
                        call $dynrt_dynUndefined
                        local.set 6
                      end
                    end
                  end
                end
                local.get 2
                local.get 4
                local.get 5
                local.get 6
                call $dynrt_dynSet
                local.get 0
                local.get 1
                call $dynrt__fn143
                local.get 0
                local.get 1
                call $dynrt__fn144
                i32.const 44
                i32.eq
                if  ;; label = @7
                  block  ;; label = @8
                    global.get $dynrt_global19
                    i32.const 1
                    i32.add
                    global.set $dynrt_global19
                    local.get 0
                    local.get 1
                    call $dynrt__fn143
                    local.get 0
                    local.get 1
                    call $dynrt__fn144
                    i32.const 125
                    i32.eq
                    if  ;; label = @9
                      i32.const 0
                      local.set 3
                    end
                  end
                else
                  i32.const 0
                  local.set 3
                end
              end
              br 1 (;@4;)
            end
          end
        end
        local.get 0
        local.get 1
        call $dynrt__fn143
        local.get 0
        local.get 1
        call $dynrt__fn144
        i32.const 125
        i32.eq
        if  ;; label = @3
          global.get $dynrt_global19
          i32.const 1
          i32.add
          global.set $dynrt_global19
        end
        local.get 2
        return
      end
    end
    local.get 2
    i32.const 96
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_global19
        local.tee 14
        i32.const 1
        local.tee 15
        i32.add
        global.set $dynrt_global19
        i32.const 534
        i32.const 0
        call $dynrt_dynString
        local.set 2
        global.get $dynrt_global19
        local.tee 16
        local.set 3
        i32.const 1
        local.tee 17
        local.set 4
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 4
              i32.const 1
              i32.eq
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                local.get 0
                local.get 1
                call $dynrt__fn144
                local.set 5
                local.get 5
                i32.const -1
                i32.eq
                if  ;; label = @7
                  i32.const 0
                  local.set 4
                else
                  local.get 5
                  i32.const 96
                  i32.eq
                  if  ;; label = @8
                    block  ;; label = @9
                      nop
                      local.get 2
                      local.get 0
                      local.get 1
                      local.get 3
                      global.get $dynrt_global19
                      call $dynrt__fn5
                      call $dynrt_dynString
                      call $dynrt_dynAdd
                      local.set 2
                      global.get $dynrt_global19
                      local.tee 11
                      i32.const 1
                      i32.add
                      global.set $dynrt_global19
                      i32.const 0
                      local.set 4
                    end
                  else
                    local.get 5
                    i32.const 36
                    i32.eq
                    if (result i32)  ;; label = @9
                      local.get 0
                      local.get 1
                      call $dynrt__fn145
                      i32.const 123
                      i32.eq
                    else
                      i32.const 0
                    end
                    if  ;; label = @9
                      block  ;; label = @10
                        nop
                        local.get 2
                        local.get 0
                        local.get 1
                        local.get 3
                        global.get $dynrt_global19
                        call $dynrt__fn5
                        call $dynrt_dynString
                        call $dynrt_dynAdd
                        local.set 2
                        global.get $dynrt_global19
                        local.tee 12
                        i32.const 2
                        i32.add
                        global.set $dynrt_global19
                        local.get 0
                        local.get 1
                        call $dynrt__fn158
                        local.set 3
                        local.get 2
                        local.get 3
                        call $dynrt_dynAdd
                        local.set 2
                        local.get 0
                        local.get 1
                        call $dynrt__fn143
                        local.get 0
                        local.get 1
                        call $dynrt__fn144
                        i32.const 125
                        i32.eq
                        if  ;; label = @11
                          global.get $dynrt_global19
                          i32.const 1
                          i32.add
                          global.set $dynrt_global19
                        end
                        global.get $dynrt_global19
                        local.tee 13
                        local.set 3
                      end
                    else
                      global.get $dynrt_global19
                      i32.const 1
                      i32.add
                      global.set $dynrt_global19
                    end
                  end
                end
              end
              br 1 (;@4;)
            end
          end
        end
        local.get 2
        return
      end
    end
    local.get 2
    i32.const 48
    i32.ge_s
    if (result i32)  ;; label = @1
      local.get 2
      i32.const 57
      i32.le_s
    else
      i32.const 0
    end
    if  ;; label = @1
      local.get 0
      local.get 1
      call $dynrt__fn146
      return
    end
    local.get 2
    i32.const 46
    i32.eq
    if  ;; label = @1
      local.get 0
      local.get 1
      call $dynrt__fn146
      return
    end
    local.get 2
    i32.const 0
    call $dynrt__fn142
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_global19
        local.tee 19
        local.set 3
        local.get 2
        local.set 2
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 2
              i32.const 1
              call $dynrt__fn142
              i32.const 1
              i32.eq
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                global.get $dynrt_global19
                i32.const 1
                i32.add
                global.set $dynrt_global19
                local.get 0
                local.get 1
                call $dynrt__fn144
                local.set 2
              end
              br 1 (;@4;)
            end
          end
        end
        local.get 0
        local.get 1
        local.get 3
        global.get $dynrt_global19
        call $dynrt__fn5
        local.set 4
        nop
        local.set 3
        local.get 3
        local.get 4
        i32.const 912
        i32.const 8
        call $dynrt__fn138
        i32.const 1
        i32.eq
        if  ;; label = @3
          local.get 0
          local.get 1
          call $dynrt__fn178
          return
        end
        local.get 3
        local.get 4
        i32.const 539
        i32.const 4
        call $dynrt__fn138
        i32.const 1
        i32.eq
        if  ;; label = @3
          i32.const 1
          call $dynrt_dynBool
          return
        end
        local.get 3
        local.get 4
        i32.const 534
        i32.const 5
        call $dynrt__fn138
        i32.const 1
        i32.eq
        if  ;; label = @3
          i32.const 0
          call $dynrt_dynBool
          return
        end
        local.get 3
        local.get 4
        i32.const 543
        i32.const 4
        call $dynrt__fn138
        i32.const 1
        i32.eq
        if  ;; label = @3
          call $dynrt_dynNull
          return
        end
        local.get 3
        local.get 4
        i32.const 547
        i32.const 9
        call $dynrt__fn138
        i32.const 1
        i32.eq
        if  ;; label = @3
          call $dynrt_dynUndefined
          return
        end
        local.get 3
        local.get 4
        i32.const 920
        i32.const 6
        call $dynrt__fn138
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            global.get $dynrt_global19
            local.set 2
            local.get 0
            local.get 1
            call $dynrt__fn143
            local.get 0
            local.get 1
            call $dynrt__fn144
            i32.const 46
            i32.eq
            if  ;; label = @5
              block  ;; label = @6
                global.get $dynrt_global19
                i32.const 1
                i32.add
                global.set $dynrt_global19
                local.get 0
                local.get 1
                call $dynrt__fn161
                global.get $dynrt_global1
                local.set 5
                global.get $dynrt_global2
                local.set 6
                local.get 0
                local.get 1
                call $dynrt__fn143
                local.get 0
                local.get 1
                call $dynrt__fn144
                i32.const 40
                i32.eq
                if  ;; label = @7
                  block  ;; label = @8
                    global.get $dynrt_global19
                    i32.const 1
                    i32.add
                    global.set $dynrt_global19
                    call $dynrt_dynArray
                    local.set 2
                    local.get 2
                    call $dynrt__fn54
                    local.get 0
                    local.get 1
                    call $dynrt__fn143
                    local.get 0
                    local.get 1
                    call $dynrt__fn144
                    i32.const 41
                    i32.eq
                    if  ;; label = @9
                      global.get $dynrt_global19
                      i32.const 1
                      i32.add
                      global.set $dynrt_global19
                    else
                      block  ;; label = @10
                        i32.const 1
                        local.set 3
                        block  ;; label = @11
                          loop  ;; label = @12
                            block  ;; label = @13
                              local.get 3
                              i32.const 1
                              i32.eq
                              i32.eqz
                              br_if 2 (;@11;)
                              block  ;; label = @14
                                local.get 2
                                local.get 0
                                local.get 1
                                call $dynrt__fn158
                                call $dynrt_dynPush
                                local.get 0
                                local.get 1
                                call $dynrt__fn143
                                local.get 0
                                local.get 1
                                call $dynrt__fn144
                                local.set 4
                                local.get 4
                                i32.const 44
                                i32.eq
                                if  ;; label = @15
                                  global.get $dynrt_global19
                                  i32.const 1
                                  i32.add
                                  global.set $dynrt_global19
                                else
                                  block  ;; label = @16
                                    local.get 4
                                    i32.const 41
                                    i32.eq
                                    if  ;; label = @17
                                      global.get $dynrt_global19
                                      i32.const 1
                                      i32.add
                                      global.set $dynrt_global19
                                    end
                                    i32.const 0
                                    local.set 3
                                  end
                                end
                              end
                              br 1 (;@12;)
                            end
                          end
                        end
                      end
                    end
                    call $dynrt_dynUndefined
                    local.set 3
                    global.get $dynrt_global21
                    i32.const 1
                    i32.eq
                    if  ;; label = @9
                      local.get 5
                      local.get 6
                      local.get 2
                      call $dynrt__fn95
                      local.set 3
                    end
                    call $dynrt__fn55
                    local.get 3
                    return
                  end
                end
              end
            end
            local.get 2
            global.set $dynrt_global19
          end
        end
        local.get 3
        local.get 4
        i32.const 926
        i32.const 4
        call $dynrt__fn138
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            global.get $dynrt_global19
            local.set 2
            local.get 0
            local.get 1
            call $dynrt__fn143
            local.get 0
            local.get 1
            call $dynrt__fn144
            i32.const 46
            i32.eq
            if  ;; label = @5
              block  ;; label = @6
                global.get $dynrt_global19
                i32.const 1
                i32.add
                global.set $dynrt_global19
                local.get 0
                local.get 1
                call $dynrt__fn161
                global.get $dynrt_global1
                local.set 5
                global.get $dynrt_global2
                local.set 6
                local.get 0
                local.get 1
                call $dynrt__fn143
                local.get 5
                local.get 6
                i32.const 930
                i32.const 2
                call $dynrt__fn138
                i32.const 1
                i32.eq
                if  ;; label = @7
                  f64.const 0x1.921fb54442d18p+1 (;=3.141592653589793;)
                  call $dynrt_dynNumber
                  return
                end
                local.get 5
                local.get 6
                i32.const 932
                i32.const 1
                call $dynrt__fn138
                i32.const 1
                i32.eq
                if  ;; label = @7
                  f64.const 0x1.5bf0a8b145769p+1 (;=2.718281828459045;)
                  call $dynrt_dynNumber
                  return
                end
                local.get 0
                local.get 1
                call $dynrt__fn144
                i32.const 40
                i32.eq
                if  ;; label = @7
                  block  ;; label = @8
                    global.get $dynrt_global19
                    i32.const 1
                    i32.add
                    global.set $dynrt_global19
                    call $dynrt_dynArray
                    local.set 2
                    local.get 2
                    call $dynrt__fn54
                    local.get 0
                    local.get 1
                    call $dynrt__fn143
                    local.get 0
                    local.get 1
                    call $dynrt__fn144
                    i32.const 41
                    i32.eq
                    if  ;; label = @9
                      global.get $dynrt_global19
                      i32.const 1
                      i32.add
                      global.set $dynrt_global19
                    else
                      block  ;; label = @10
                        i32.const 1
                        local.set 3
                        block  ;; label = @11
                          loop  ;; label = @12
                            block  ;; label = @13
                              local.get 3
                              i32.const 1
                              i32.eq
                              i32.eqz
                              br_if 2 (;@11;)
                              block  ;; label = @14
                                local.get 2
                                local.get 0
                                local.get 1
                                call $dynrt__fn158
                                call $dynrt_dynPush
                                local.get 0
                                local.get 1
                                call $dynrt__fn143
                                local.get 0
                                local.get 1
                                call $dynrt__fn144
                                local.set 4
                                local.get 4
                                i32.const 44
                                i32.eq
                                if  ;; label = @15
                                  global.get $dynrt_global19
                                  i32.const 1
                                  i32.add
                                  global.set $dynrt_global19
                                else
                                  block  ;; label = @16
                                    local.get 4
                                    i32.const 41
                                    i32.eq
                                    if  ;; label = @17
                                      global.get $dynrt_global19
                                      i32.const 1
                                      i32.add
                                      global.set $dynrt_global19
                                    end
                                    i32.const 0
                                    local.set 3
                                  end
                                end
                              end
                              br 1 (;@12;)
                            end
                          end
                        end
                      end
                    end
                    call $dynrt_dynUndefined
                    local.set 3
                    global.get $dynrt_global21
                    i32.const 1
                    i32.eq
                    if  ;; label = @9
                      local.get 5
                      local.get 6
                      local.get 2
                      call $dynrt__fn96
                      local.set 3
                    end
                    call $dynrt__fn55
                    local.get 3
                    return
                  end
                end
              end
            end
            local.get 2
            global.set $dynrt_global19
          end
        end
        local.get 3
        local.get 4
        i32.const 933
        i32.const 4
        call $dynrt__fn138
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            global.get $dynrt_global19
            local.set 2
            local.get 0
            local.get 1
            call $dynrt__fn143
            local.get 0
            local.get 1
            call $dynrt__fn144
            i32.const 46
            i32.eq
            if  ;; label = @5
              block  ;; label = @6
                global.get $dynrt_global19
                i32.const 1
                i32.add
                global.set $dynrt_global19
                local.get 0
                local.get 1
                call $dynrt__fn161
                global.get $dynrt_global1
                local.set 5
                global.get $dynrt_global2
                local.set 6
                local.get 0
                local.get 1
                call $dynrt__fn143
                local.get 0
                local.get 1
                call $dynrt__fn144
                i32.const 40
                i32.eq
                if  ;; label = @7
                  block  ;; label = @8
                    global.get $dynrt_global19
                    i32.const 1
                    i32.add
                    global.set $dynrt_global19
                    call $dynrt_dynArray
                    local.set 2
                    local.get 2
                    call $dynrt__fn54
                    local.get 0
                    local.get 1
                    call $dynrt__fn143
                    local.get 0
                    local.get 1
                    call $dynrt__fn144
                    i32.const 41
                    i32.eq
                    if  ;; label = @9
                      global.get $dynrt_global19
                      i32.const 1
                      i32.add
                      global.set $dynrt_global19
                    else
                      block  ;; label = @10
                        i32.const 1
                        local.set 3
                        block  ;; label = @11
                          loop  ;; label = @12
                            block  ;; label = @13
                              local.get 3
                              i32.const 1
                              i32.eq
                              i32.eqz
                              br_if 2 (;@11;)
                              block  ;; label = @14
                                local.get 2
                                local.get 0
                                local.get 1
                                call $dynrt__fn158
                                call $dynrt_dynPush
                                local.get 0
                                local.get 1
                                call $dynrt__fn143
                                local.get 0
                                local.get 1
                                call $dynrt__fn144
                                local.set 4
                                local.get 4
                                i32.const 44
                                i32.eq
                                if  ;; label = @15
                                  global.get $dynrt_global19
                                  i32.const 1
                                  i32.add
                                  global.set $dynrt_global19
                                else
                                  block  ;; label = @16
                                    local.get 4
                                    i32.const 41
                                    i32.eq
                                    if  ;; label = @17
                                      global.get $dynrt_global19
                                      i32.const 1
                                      i32.add
                                      global.set $dynrt_global19
                                    end
                                    i32.const 0
                                    local.set 3
                                  end
                                end
                              end
                              br 1 (;@12;)
                            end
                          end
                        end
                      end
                    end
                    call $dynrt_dynUndefined
                    local.set 3
                    global.get $dynrt_global21
                    i32.const 1
                    i32.eq
                    if  ;; label = @9
                      block  ;; label = @10
                        call $dynrt_dynUndefined
                        local.set 4
                        local.get 2
                        call $dynrt_dynArrLen
                        i32.const 0
                        i32.gt_s
                        if  ;; label = @11
                          local.get 2
                          i32.const 0
                          call $dynrt_dynArrGet
                          local.set 4
                        end
                        local.get 5
                        local.get 6
                        i32.const 937
                        i32.const 5
                        call $dynrt__fn138
                        i32.const 1
                        i32.eq
                        if  ;; label = @11
                          block  ;; label = @12
                            local.get 4
                            call $dynrt__fn78
                            global.get $dynrt_global1
                            local.set 2
                            global.get $dynrt_global2
                            local.set 3
                            local.get 2
                            local.get 3
                            call $dynrt__fn99
                            local.set 3
                          end
                        else
                          local.get 5
                          local.get 6
                          i32.const 942
                          i32.const 9
                          call $dynrt__fn138
                          i32.const 1
                          i32.eq
                          if  ;; label = @12
                            block  ;; label = @13
                              local.get 4
                              call $dynrt__fn98
                              global.get $dynrt_global1
                              local.set 2
                              global.get $dynrt_global2
                              local.set 3
                              local.get 2
                              local.get 3
                              call $dynrt_dynString
                              local.set 3
                            end
                          end
                        end
                      end
                    end
                    call $dynrt__fn55
                    local.get 3
                    return
                  end
                end
              end
            end
            local.get 2
            global.set $dynrt_global19
          end
        end
        local.get 3
        local.get 4
        i32.const 951
        i32.const 3
        call $dynrt__fn138
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt__fn143
            global.get $dynrt_global19
            local.tee 18
            local.set 2
            local.get 0
            local.get 1
            call $dynrt__fn144
            local.set 3
            block  ;; label = @5
              loop  ;; label = @6
                block  ;; label = @7
                  local.get 3
                  i32.const 1
                  call $dynrt__fn142
                  i32.const 1
                  i32.eq
                  i32.eqz
                  br_if 2 (;@5;)
                  block  ;; label = @8
                    global.get $dynrt_global19
                    i32.const 1
                    i32.add
                    global.set $dynrt_global19
                    local.get 0
                    local.get 1
                    call $dynrt__fn144
                    local.set 3
                  end
                  br 1 (;@6;)
                end
              end
            end
            local.get 0
            local.get 1
            local.get 2
            global.get $dynrt_global19
            call $dynrt__fn5
            local.set 5
            nop
            local.set 2
            global.get $dynrt_global20
            i32.const -1
            i32.eq
            if (result i32)  ;; label = @5
              call $dynrt_dynUndefined
            else
              global.get $dynrt_global20
              local.get 2
              local.get 5
              call $dynrt__fn125
            end
            local.set 3
            local.get 3
            i32.const -1
            i32.eq
            if (result i32)  ;; label = @5
              call $dynrt_dynUndefined
            else
              local.get 3
            end
            local.set 6
            call $dynrt_dynArray
            local.set 7
            local.get 7
            call $dynrt__fn54
            local.get 0
            local.get 1
            call $dynrt__fn143
            local.get 0
            local.get 1
            call $dynrt__fn144
            i32.const 40
            i32.eq
            if  ;; label = @5
              block  ;; label = @6
                global.get $dynrt_global19
                i32.const 1
                i32.add
                global.set $dynrt_global19
                local.get 0
                local.get 1
                call $dynrt__fn143
                local.get 0
                local.get 1
                call $dynrt__fn144
                i32.const 41
                i32.eq
                if  ;; label = @7
                  global.get $dynrt_global19
                  i32.const 1
                  i32.add
                  global.set $dynrt_global19
                else
                  block  ;; label = @8
                    i32.const 1
                    local.set 3
                    block  ;; label = @9
                      loop  ;; label = @10
                        block  ;; label = @11
                          local.get 3
                          i32.const 1
                          i32.eq
                          i32.eqz
                          br_if 2 (;@9;)
                          block  ;; label = @12
                            local.get 0
                            local.get 1
                            call $dynrt__fn158
                            local.set 4
                            local.get 7
                            local.get 4
                            call $dynrt_dynPush
                            local.get 0
                            local.get 1
                            call $dynrt__fn143
                            local.get 0
                            local.get 1
                            call $dynrt__fn144
                            local.set 4
                            local.get 4
                            i32.const 44
                            i32.eq
                            if  ;; label = @13
                              global.get $dynrt_global19
                              i32.const 1
                              i32.add
                              global.set $dynrt_global19
                            else
                              block  ;; label = @14
                                local.get 4
                                i32.const 41
                                i32.eq
                                if  ;; label = @15
                                  global.get $dynrt_global19
                                  i32.const 1
                                  i32.add
                                  global.set $dynrt_global19
                                end
                                i32.const 0
                                local.set 3
                              end
                            end
                          end
                          br 1 (;@10;)
                        end
                      end
                    end
                  end
                end
              end
            end
            call $dynrt_dynUndefined
            local.set 3
            global.get $dynrt_global21
            i32.const 1
            i32.eq
            if  ;; label = @5
              local.get 2
              local.get 5
              i32.const 954
              i32.const 3
              call $dynrt__fn138
              i32.const 1
              i32.eq
              if  ;; label = @6
                call $dynrt__fn103
                local.set 3
              else
                local.get 2
                local.get 5
                i32.const 957
                i32.const 3
                call $dynrt__fn138
                i32.const 1
                i32.eq
                if  ;; label = @7
                  block  ;; label = @8
                    call $dynrt_dynUndefined
                    local.set 2
                    local.get 7
                    call $dynrt_dynArrLen
                    i32.const 0
                    i32.gt_s
                    if  ;; label = @9
                      local.get 7
                      i32.const 0
                      call $dynrt_dynArrGet
                      local.set 2
                    end
                    local.get 2
                    call $dynrt__fn104
                    local.set 3
                  end
                else
                  local.get 6
                  local.get 7
                  call $dynrt__fn182
                  local.set 3
                end
              end
            end
            call $dynrt__fn55
            local.get 3
            return
          end
        end
        local.get 3
        local.get 4
        i32.const 960
        i32.const 5
        call $dynrt__fn138
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt__fn143
            global.get $dynrt_global20
            i32.const -1
            i32.eq
            if (result i32)  ;; label = @5
              i32.const -1
            else
              global.get $dynrt_global20
              i32.const 880
              i32.const 4
              call $dynrt__fn125
            end
            local.set 2
            local.get 0
            local.get 1
            call $dynrt__fn144
            local.set 3
            local.get 3
            i32.const 40
            i32.eq
            if  ;; label = @5
              block  ;; label = @6
                global.get $dynrt_global19
                i32.const 1
                i32.add
                global.set $dynrt_global19
                call $dynrt_dynArray
                local.set 7
                local.get 7
                call $dynrt__fn54
                local.get 0
                local.get 1
                call $dynrt__fn143
                local.get 0
                local.get 1
                call $dynrt__fn144
                i32.const 41
                i32.eq
                if  ;; label = @7
                  global.get $dynrt_global19
                  i32.const 1
                  i32.add
                  global.set $dynrt_global19
                else
                  block  ;; label = @8
                    i32.const 1
                    local.set 3
                    block  ;; label = @9
                      loop  ;; label = @10
                        block  ;; label = @11
                          local.get 3
                          i32.const 1
                          i32.eq
                          i32.eqz
                          br_if 2 (;@9;)
                          block  ;; label = @12
                            local.get 7
                            local.get 0
                            local.get 1
                            call $dynrt__fn158
                            call $dynrt_dynPush
                            local.get 0
                            local.get 1
                            call $dynrt__fn143
                            local.get 0
                            local.get 1
                            call $dynrt__fn144
                            local.set 4
                            local.get 4
                            i32.const 44
                            i32.eq
                            if  ;; label = @13
                              global.get $dynrt_global19
                              i32.const 1
                              i32.add
                              global.set $dynrt_global19
                            else
                              block  ;; label = @14
                                local.get 4
                                i32.const 41
                                i32.eq
                                if  ;; label = @15
                                  global.get $dynrt_global19
                                  i32.const 1
                                  i32.add
                                  global.set $dynrt_global19
                                end
                                i32.const 0
                                local.set 3
                              end
                            end
                          end
                          br 1 (;@10;)
                        end
                      end
                    end
                  end
                end
                global.get $dynrt_global21
                i32.const 1
                i32.eq
                if (result i32)  ;; label = @7
                  local.get 2
                  i32.const -1
                  i32.ne
                else
                  i32.const 0
                end
                if  ;; label = @7
                  block  ;; label = @8
                    global.get $dynrt_global20
                    i32.const 965
                    i32.const 12
                    call $dynrt__fn125
                    local.set 3
                    local.get 3
                    i32.const -1
                    i32.ne
                    if  ;; label = @9
                      block  ;; label = @10
                        local.get 3
                        i32.const 977
                        i32.const 6
                        call $dynrt_dynGet
                        local.set 3
                        local.get 3
                        i32.const -1
                        i32.ne
                        if  ;; label = @11
                          block  ;; label = @12
                            local.get 3
                            local.set 4
                            local.get 4
                            i32.const 8
                            i32.add
                            i32.load
                            i32.const 7
                            i32.eq
                            if  ;; label = @13
                              local.get 3
                              local.get 7
                              local.get 2
                              call $dynrt__fn130
                              drop
                            end
                          end
                        end
                      end
                    end
                  end
                end
                call $dynrt__fn55
                call $dynrt_dynUndefined
                return
              end
            end
            local.get 3
            i32.const 46
            i32.eq
            if  ;; label = @5
              block  ;; label = @6
                global.get $dynrt_global19
                i32.const 1
                i32.add
                global.set $dynrt_global19
                local.get 0
                local.get 1
                call $dynrt__fn161
                global.get $dynrt_global1
                local.set 3
                global.get $dynrt_global2
                local.set 4
                global.get $dynrt_global20
                i32.const -1
                i32.eq
                if (result i32)  ;; label = @7
                  i32.const -1
                else
                  global.get $dynrt_global20
                  i32.const 983
                  i32.const 12
                  call $dynrt__fn125
                end
                local.set 5
                call $dynrt_dynUndefined
                local.set 6
                local.get 5
                i32.const -1
                i32.ne
                if  ;; label = @7
                  local.get 5
                  local.get 3
                  local.get 4
                  call $dynrt_dynMember
                  local.set 6
                end
                local.get 0
                local.get 1
                call $dynrt__fn143
                local.get 0
                local.get 1
                call $dynrt__fn144
                i32.const 40
                i32.eq
                if  ;; label = @7
                  block  ;; label = @8
                    global.get $dynrt_global19
                    i32.const 1
                    i32.add
                    global.set $dynrt_global19
                    call $dynrt_dynArray
                    local.set 7
                    local.get 7
                    call $dynrt__fn54
                    local.get 0
                    local.get 1
                    call $dynrt__fn143
                    local.get 0
                    local.get 1
                    call $dynrt__fn144
                    i32.const 41
                    i32.eq
                    if  ;; label = @9
                      global.get $dynrt_global19
                      i32.const 1
                      i32.add
                      global.set $dynrt_global19
                    else
                      block  ;; label = @10
                        i32.const 1
                        local.set 3
                        block  ;; label = @11
                          loop  ;; label = @12
                            block  ;; label = @13
                              local.get 3
                              i32.const 1
                              i32.eq
                              i32.eqz
                              br_if 2 (;@11;)
                              block  ;; label = @14
                                local.get 7
                                local.get 0
                                local.get 1
                                call $dynrt__fn158
                                call $dynrt_dynPush
                                local.get 0
                                local.get 1
                                call $dynrt__fn143
                                local.get 0
                                local.get 1
                                call $dynrt__fn144
                                local.set 4
                                local.get 4
                                i32.const 44
                                i32.eq
                                if  ;; label = @15
                                  global.get $dynrt_global19
                                  i32.const 1
                                  i32.add
                                  global.set $dynrt_global19
                                else
                                  block  ;; label = @16
                                    local.get 4
                                    i32.const 41
                                    i32.eq
                                    if  ;; label = @17
                                      global.get $dynrt_global19
                                      i32.const 1
                                      i32.add
                                      global.set $dynrt_global19
                                    end
                                    i32.const 0
                                    local.set 3
                                  end
                                end
                              end
                              br 1 (;@12;)
                            end
                          end
                        end
                      end
                    end
                    call $dynrt_dynUndefined
                    local.set 3
                    global.get $dynrt_global21
                    i32.const 1
                    i32.eq
                    if (result i32)  ;; label = @9
                      local.get 2
                      i32.const -1
                      i32.ne
                    else
                      i32.const 0
                    end
                    if  ;; label = @9
                      block  ;; label = @10
                        local.get 6
                        local.set 4
                        local.get 4
                        i32.const 8
                        i32.add
                        i32.load
                        i32.const 7
                        i32.eq
                        if  ;; label = @11
                          local.get 6
                          local.get 7
                          local.get 2
                          call $dynrt__fn130
                          local.set 3
                        end
                      end
                    end
                    call $dynrt__fn55
                    local.get 3
                    return
                  end
                end
                local.get 6
                return
              end
            end
            call $dynrt_dynUndefined
            return
          end
        end
        local.get 0
        local.get 1
        call $dynrt__fn143
        local.get 0
        local.get 1
        call $dynrt__fn144
        i32.const 61
        i32.eq
        if (result i32)  ;; label = @3
          local.get 0
          local.get 1
          call $dynrt__fn145
          i32.const 62
          i32.eq
        else
          i32.const 0
        end
        if  ;; label = @3
          block  ;; label = @4
            global.get $dynrt_global19
            i32.const 2
            i32.add
            global.set $dynrt_global19
            call $dynrt_dynArray
            local.set 2
            local.get 2
            local.get 3
            local.get 4
            call $dynrt_dynString
            call $dynrt_dynPush
            local.get 2
            local.get 0
            local.get 1
            call $dynrt__fn177
            global.get $dynrt_global20
            call $dynrt__fn121
            return
          end
        end
        global.get $dynrt_global20
        i32.const -1
        i32.eq
        if  ;; label = @3
          call $dynrt_dynUndefined
          return
        end
        global.get $dynrt_global20
        local.get 3
        local.get 4
        call $dynrt__fn125
        local.set 2
        local.get 2
        i32.const -1
        i32.eq
        if (result i32)  ;; label = @3
          call $dynrt_dynUndefined
        else
          local.get 2
        end
        return
      end
    end
    call $dynrt_dynUndefined
    return)
  (func $dynrt__fn149 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt__fn148
    local.set 2
    i32.const 1
    local.set 3
    i32.const -1
    local.set 4
    i32.const 534
    local.set 5
    i32.const 0
    local.tee 15
    local.set 6
    local.get 15
    local.set 7
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 3
          i32.const 1
          i32.eq
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt__fn143
            local.get 0
            local.get 1
            call $dynrt__fn144
            local.set 8
            i32.const 0
            local.set 9
            local.get 8
            i32.const 63
            i32.eq
            if (result i32)  ;; label = @5
              local.get 0
              local.get 1
              call $dynrt__fn145
              i32.const 46
              i32.eq
            else
              i32.const 0
            end
            if  ;; label = @5
              block  ;; label = @6
                global.get $dynrt_global19
                i32.const 2
                i32.add
                global.set $dynrt_global19
                local.get 7
                i32.eqz
                if  ;; label = @7
                  block  ;; label = @8
                    local.get 2
                    local.set 4
                    local.get 4
                    i32.const 8
                    i32.add
                    i32.load
                    local.set 4
                    local.get 4
                    i32.eqz
                    if (result i32)  ;; label = @9
                      i32.const 1
                    else
                      local.get 4
                      i32.const 1
                      i32.eq
                    end
                    if  ;; label = @9
                      i32.const 1
                      local.set 7
                    end
                  end
                end
                local.get 0
                local.get 1
                call $dynrt__fn143
                local.get 0
                local.get 1
                call $dynrt__fn144
                local.set 4
                local.get 4
                i32.const 91
                i32.eq
                if  ;; label = @7
                  block  ;; label = @8
                    global.get $dynrt_global19
                    i32.const 1
                    i32.add
                    global.set $dynrt_global19
                    local.get 0
                    local.get 1
                    call $dynrt__fn158
                    local.set 9
                    local.get 0
                    local.get 1
                    call $dynrt__fn143
                    local.get 0
                    local.get 1
                    call $dynrt__fn144
                    i32.const 93
                    i32.eq
                    if  ;; label = @9
                      global.get $dynrt_global19
                      i32.const 1
                      i32.add
                      global.set $dynrt_global19
                    end
                    local.get 2
                    local.set 4
                    local.get 7
                    i32.const 1
                    i32.eq
                    if (result i32)  ;; label = @9
                      call $dynrt_dynUndefined
                    else
                      local.get 2
                      local.get 9
                      call $dynrt_dynIndexValue
                    end
                    local.set 2
                  end
                else
                  block  ;; label = @8
                    global.get $dynrt_global19
                    local.tee 12
                    local.set 4
                    local.get 0
                    local.get 1
                    call $dynrt__fn144
                    local.set 5
                    block  ;; label = @9
                      loop  ;; label = @10
                        block  ;; label = @11
                          local.get 5
                          i32.const 1
                          call $dynrt__fn142
                          i32.const 1
                          i32.eq
                          i32.eqz
                          br_if 2 (;@9;)
                          block  ;; label = @12
                            global.get $dynrt_global19
                            i32.const 1
                            i32.add
                            global.set $dynrt_global19
                            local.get 0
                            local.get 1
                            call $dynrt__fn144
                            local.set 5
                          end
                          br 1 (;@10;)
                        end
                      end
                    end
                    local.get 0
                    local.get 1
                    local.get 4
                    global.get $dynrt_global19
                    call $dynrt__fn5
                    local.set 10
                    nop
                    local.set 9
                    local.get 2
                    local.set 4
                    local.get 9
                    local.set 5
                    local.get 10
                    local.set 6
                    local.get 7
                    i32.const 1
                    i32.eq
                    if (result i32)  ;; label = @9
                      call $dynrt_dynUndefined
                    else
                      local.get 2
                      local.get 9
                      local.get 10
                      call $dynrt_dynMember
                    end
                    local.set 2
                  end
                end
                i32.const 1
                local.set 9
              end
            end
            local.get 9
            i32.const 1
            i32.eq
            if  ;; label = @5
              nop
            else
              local.get 8
              i32.const 46
              i32.eq
              if  ;; label = @6
                block  ;; label = @7
                  global.get $dynrt_global19
                  local.tee 13
                  i32.const 1
                  i32.add
                  global.set $dynrt_global19
                  local.get 0
                  local.get 1
                  call $dynrt__fn143
                  global.get $dynrt_global19
                  local.tee 14
                  local.set 4
                  local.get 0
                  local.get 1
                  call $dynrt__fn144
                  local.set 5
                  block  ;; label = @8
                    loop  ;; label = @9
                      block  ;; label = @10
                        local.get 5
                        i32.const 1
                        call $dynrt__fn142
                        i32.const 1
                        i32.eq
                        i32.eqz
                        br_if 2 (;@8;)
                        block  ;; label = @11
                          global.get $dynrt_global19
                          i32.const 1
                          i32.add
                          global.set $dynrt_global19
                          local.get 0
                          local.get 1
                          call $dynrt__fn144
                          local.set 5
                        end
                        br 1 (;@9;)
                      end
                    end
                  end
                  local.get 0
                  local.get 1
                  local.get 4
                  global.get $dynrt_global19
                  call $dynrt__fn5
                  local.set 10
                  nop
                  local.set 9
                  local.get 2
                  local.set 4
                  local.get 9
                  local.set 5
                  local.get 10
                  local.set 6
                  local.get 7
                  i32.const 1
                  i32.eq
                  if (result i32)  ;; label = @8
                    call $dynrt_dynUndefined
                  else
                    local.get 2
                    local.get 9
                    local.get 10
                    call $dynrt_dynMember
                  end
                  local.set 2
                end
              else
                local.get 8
                i32.const 91
                i32.eq
                if  ;; label = @7
                  block  ;; label = @8
                    global.get $dynrt_global19
                    i32.const 1
                    i32.add
                    global.set $dynrt_global19
                    local.get 0
                    local.get 1
                    call $dynrt__fn158
                    local.set 8
                    local.get 0
                    local.get 1
                    call $dynrt__fn143
                    local.get 0
                    local.get 1
                    call $dynrt__fn144
                    i32.const 93
                    i32.eq
                    if  ;; label = @9
                      global.get $dynrt_global19
                      i32.const 1
                      i32.add
                      global.set $dynrt_global19
                    end
                    local.get 2
                    local.set 4
                    i32.const 534
                    local.set 5
                    i32.const 0
                    local.set 6
                    local.get 7
                    i32.const 1
                    i32.eq
                    if (result i32)  ;; label = @9
                      call $dynrt_dynUndefined
                    else
                      local.get 2
                      local.get 8
                      call $dynrt_dynIndexValue
                    end
                    local.set 2
                  end
                else
                  local.get 8
                  i32.const 40
                  i32.eq
                  if  ;; label = @8
                    block  ;; label = @9
                      global.get $dynrt_global19
                      i32.const 1
                      i32.add
                      global.set $dynrt_global19
                      local.get 2
                      call $dynrt__fn54
                      local.get 4
                      i32.const -1
                      i32.ne
                      if (result i32)  ;; label = @10
                        i32.const 1
                      else
                        i32.const 0
                      end
                      local.set 8
                      local.get 8
                      i32.const 1
                      i32.eq
                      if  ;; label = @10
                        local.get 4
                        call $dynrt__fn54
                      end
                      call $dynrt_dynArray
                      local.set 9
                      local.get 9
                      call $dynrt__fn54
                      local.get 0
                      local.get 1
                      call $dynrt__fn143
                      local.get 0
                      local.get 1
                      call $dynrt__fn144
                      i32.const 41
                      i32.eq
                      if  ;; label = @10
                        global.get $dynrt_global19
                        i32.const 1
                        i32.add
                        global.set $dynrt_global19
                      else
                        block  ;; label = @11
                          i32.const 1
                          local.set 10
                          block  ;; label = @12
                            loop  ;; label = @13
                              block  ;; label = @14
                                local.get 10
                                i32.const 1
                                i32.eq
                                i32.eqz
                                br_if 2 (;@12;)
                                block  ;; label = @15
                                  local.get 0
                                  local.get 1
                                  call $dynrt__fn158
                                  local.set 11
                                  local.get 9
                                  local.get 11
                                  call $dynrt_dynPush
                                  local.get 0
                                  local.get 1
                                  call $dynrt__fn143
                                  local.get 0
                                  local.get 1
                                  call $dynrt__fn144
                                  local.set 11
                                  local.get 11
                                  i32.const 44
                                  i32.eq
                                  if  ;; label = @16
                                    global.get $dynrt_global19
                                    i32.const 1
                                    i32.add
                                    global.set $dynrt_global19
                                  else
                                    block  ;; label = @17
                                      local.get 11
                                      i32.const 41
                                      i32.eq
                                      if  ;; label = @18
                                        global.get $dynrt_global19
                                        i32.const 1
                                        i32.add
                                        global.set $dynrt_global19
                                      end
                                      i32.const 0
                                      local.set 10
                                    end
                                  end
                                end
                                br 1 (;@13;)
                              end
                            end
                          end
                        end
                      end
                      global.get $dynrt_global21
                      i32.const 1
                      i32.eq
                      if (result i32)  ;; label = @10
                        local.get 7
                        i32.eqz
                      else
                        i32.const 0
                      end
                      if  ;; label = @10
                        local.get 8
                        i32.const 1
                        i32.eq
                        if  ;; label = @11
                          block  ;; label = @12
                            local.get 4
                            local.set 10
                            local.get 2
                            local.set 11
                            local.get 10
                            i32.const 8
                            i32.add
                            i32.load
                            i32.const 5
                            i32.eq
                            if (result i32)  ;; label = @13
                              local.get 11
                              i32.const 8
                              i32.add
                              i32.load
                              i32.const 7
                              i32.ne
                            else
                              i32.const 0
                            end
                            if  ;; label = @13
                              local.get 4
                              local.get 5
                              local.get 6
                              local.get 9
                              call $dynrt__fn93
                              local.set 2
                            else
                              local.get 10
                              i32.const 8
                              i32.add
                              i32.load
                              i32.const 4
                              i32.eq
                              if (result i32)  ;; label = @14
                                local.get 11
                                i32.const 8
                                i32.add
                                i32.load
                                i32.const 7
                                i32.ne
                              else
                                i32.const 0
                              end
                              if  ;; label = @14
                                local.get 4
                                local.get 5
                                local.get 6
                                local.get 9
                                call $dynrt__fn94
                                local.set 2
                              else
                                local.get 10
                                i32.const 8
                                i32.add
                                i32.load
                                i32.const 6
                                i32.eq
                                if (result i32)  ;; label = @15
                                  local.get 11
                                  i32.const 8
                                  i32.add
                                  i32.load
                                  i32.const 7
                                  i32.ne
                                else
                                  i32.const 0
                                end
                                if (result i32)  ;; label = @15
                                  local.get 4
                                  i32.const 844
                                  i32.const 6
                                  call $dynrt_dynHas
                                  i32.const 1
                                  i32.eq
                                else
                                  i32.const 0
                                end
                                if  ;; label = @15
                                  local.get 4
                                  local.get 5
                                  local.get 6
                                  local.get 9
                                  call $dynrt__fn105
                                  local.set 2
                                else
                                  local.get 10
                                  i32.const 8
                                  i32.add
                                  i32.load
                                  i32.const 6
                                  i32.eq
                                  if (result i32)  ;; label = @16
                                    local.get 11
                                    i32.const 8
                                    i32.add
                                    i32.load
                                    i32.const 7
                                    i32.ne
                                  else
                                    i32.const 0
                                  end
                                  if (result i32)  ;; label = @16
                                    local.get 4
                                    i32.const 856
                                    i32.const 6
                                    call $dynrt_dynHas
                                    i32.const 1
                                    i32.eq
                                  else
                                    i32.const 0
                                  end
                                  if  ;; label = @16
                                    local.get 4
                                    local.get 5
                                    local.get 6
                                    local.get 9
                                    call $dynrt__fn106
                                    local.set 2
                                  else
                                    local.get 2
                                    local.get 9
                                    local.get 4
                                    call $dynrt__fn130
                                    local.set 2
                                  end
                                end
                              end
                            end
                          end
                        else
                          local.get 2
                          local.get 9
                          call $dynrt_dynApply
                          local.set 2
                        end
                      else
                        call $dynrt_dynUndefined
                        local.set 2
                      end
                      call $dynrt__fn55
                      local.get 8
                      i32.const 1
                      i32.eq
                      if  ;; label = @10
                        call $dynrt__fn55
                      end
                      call $dynrt__fn55
                      i32.const -1
                      local.set 4
                    end
                  else
                    i32.const 0
                    local.set 3
                  end
                end
              end
            end
          end
          br 1 (;@2;)
        end
      end
    end
    local.get 2
    return)
  (func $dynrt__fn150 (param i32) (result i32)
    (local i32)
    local.get 0
    local.set 1
    local.get 1
    i32.const 8
    i32.add
    i32.load
    local.set 1
    local.get 1
    i32.eqz
    if  ;; label = @1
      i32.const 547
      i32.const 9
      call $dynrt_dynString
      return
    end
    local.get 1
    i32.const 2
    i32.eq
    if  ;; label = @1
      i32.const 995
      i32.const 7
      call $dynrt_dynString
      return
    end
    local.get 1
    i32.const 3
    i32.eq
    if  ;; label = @1
      i32.const 1002
      i32.const 6
      call $dynrt_dynString
      return
    end
    local.get 1
    i32.const 4
    i32.eq
    if  ;; label = @1
      i32.const 1008
      i32.const 6
      call $dynrt_dynString
      return
    end
    local.get 1
    i32.const 7
    i32.eq
    if  ;; label = @1
      i32.const 912
      i32.const 8
      call $dynrt_dynString
      return
    end
    i32.const 1014
    i32.const 6
    call $dynrt_dynString
    return)
  (func $dynrt__fn151 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt__fn143
    local.get 0
    local.get 1
    call $dynrt__fn144
    local.set 2
    local.get 2
    i32.const 45
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_global19
        i32.const 1
        i32.add
        global.set $dynrt_global19
        local.get 0
        local.get 1
        call $dynrt__fn151
        call $dynrt_dynNeg
        return
      end
    end
    local.get 2
    i32.const 33
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_global19
        i32.const 1
        i32.add
        global.set $dynrt_global19
        local.get 0
        local.get 1
        call $dynrt__fn151
        call $dynrt_dynNot
        return
      end
    end
    local.get 2
    i32.const 43
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_global19
        i32.const 1
        i32.add
        global.set $dynrt_global19
        local.get 0
        local.get 1
        call $dynrt__fn151
        local.set 2
        local.get 2
        call $dynrt_dynToNumber
        call $dynrt_dynNumber
        return
      end
    end
    local.get 2
    i32.const 116
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_global19
        local.set 2
        local.get 0
        local.get 1
        call $dynrt__fn161
        global.get $dynrt_global1
        local.set 3
        global.get $dynrt_global2
        local.set 4
        local.get 3
        local.get 4
        i32.const 1020
        i32.const 6
        call $dynrt__fn138
        i32.const 1
        i32.eq
        if  ;; label = @3
          local.get 0
          local.get 1
          call $dynrt__fn151
          call $dynrt__fn150
          return
        end
        local.get 2
        global.set $dynrt_global19
      end
    end
    local.get 0
    local.get 1
    call $dynrt__fn149
    return)
  (func $dynrt__fn152 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt__fn151
    local.set 2
    i32.const 1
    local.set 3
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 3
          i32.const 1
          i32.eq
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt__fn143
            local.get 0
            local.get 1
            call $dynrt__fn144
            local.set 4
            local.get 4
            i32.const 42
            i32.eq
            if (result i32)  ;; label = @5
              i32.const 1
            else
              local.get 4
              i32.const 47
              i32.eq
            end
            if (result i32)  ;; label = @5
              i32.const 1
            else
              local.get 4
              i32.const 37
              i32.eq
            end
            if  ;; label = @5
              block  ;; label = @6
                global.get $dynrt_global19
                i32.const 1
                i32.add
                global.set $dynrt_global19
                local.get 2
                call $dynrt__fn54
                local.get 0
                local.get 1
                call $dynrt__fn151
                local.set 5
                call $dynrt__fn55
                local.get 4
                i32.const 42
                i32.eq
                if  ;; label = @7
                  local.get 2
                  local.get 5
                  call $dynrt_dynMul
                  local.set 2
                else
                  local.get 4
                  i32.const 47
                  i32.eq
                  if  ;; label = @8
                    local.get 2
                    local.get 5
                    call $dynrt_dynDiv
                    local.set 2
                  else
                    local.get 2
                    local.get 5
                    call $dynrt_dynMod
                    local.set 2
                  end
                end
              end
            else
              i32.const 0
              local.set 3
            end
          end
          br 1 (;@2;)
        end
      end
    end
    local.get 2
    return)
  (func $dynrt__fn153 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt__fn152
    local.set 2
    i32.const 1
    local.set 3
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 3
          i32.const 1
          i32.eq
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt__fn143
            local.get 0
            local.get 1
            call $dynrt__fn144
            local.set 4
            local.get 4
            i32.const 43
            i32.eq
            if (result i32)  ;; label = @5
              i32.const 1
            else
              local.get 4
              i32.const 45
              i32.eq
            end
            if  ;; label = @5
              block  ;; label = @6
                global.get $dynrt_global19
                i32.const 1
                i32.add
                global.set $dynrt_global19
                local.get 2
                call $dynrt__fn54
                local.get 0
                local.get 1
                call $dynrt__fn152
                local.set 5
                call $dynrt__fn55
                local.get 4
                i32.const 43
                i32.eq
                if  ;; label = @7
                  local.get 2
                  local.get 5
                  call $dynrt_dynAdd
                  local.set 2
                else
                  local.get 2
                  local.get 5
                  call $dynrt_dynSub
                  local.set 2
                end
              end
            else
              i32.const 0
              local.set 3
            end
          end
          br 1 (;@2;)
        end
      end
    end
    local.get 2
    return)
  (func $dynrt__fn154 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt__fn153
    local.set 2
    i32.const 1
    local.set 3
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 3
          i32.const 1
          i32.eq
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt__fn143
            local.get 0
            local.get 1
            call $dynrt__fn144
            local.set 4
            local.get 0
            local.get 1
            call $dynrt__fn145
            local.set 5
            local.get 4
            i32.const 60
            i32.eq
            if (result i32)  ;; label = @5
              i32.const 1
            else
              local.get 4
              i32.const 62
              i32.eq
            end
            if  ;; label = @5
              block  ;; label = @6
                local.get 4
                i32.const 60
                i32.eq
                if (result i32)  ;; label = @7
                  i32.const 1
                else
                  i32.const 0
                end
                local.set 4
                local.get 5
                i32.const 61
                i32.eq
                if (result i32)  ;; label = @7
                  i32.const 1
                else
                  i32.const 0
                end
                local.set 5
                local.get 5
                i32.const 1
                i32.eq
                if (result i32)  ;; label = @7
                  global.get $dynrt_global19
                  i32.const 2
                  i32.add
                else
                  global.get $dynrt_global19
                  i32.const 1
                  i32.add
                end
                global.set $dynrt_global19
                local.get 2
                call $dynrt__fn54
                local.get 0
                local.get 1
                call $dynrt__fn153
                local.set 6
                call $dynrt__fn55
                local.get 4
                i32.const 1
                i32.eq
                if  ;; label = @7
                  local.get 5
                  i32.const 1
                  i32.eq
                  if (result i32)  ;; label = @8
                    local.get 2
                    local.get 6
                    call $dynrt_dynLe
                  else
                    local.get 2
                    local.get 6
                    call $dynrt_dynLt
                  end
                  local.set 2
                else
                  local.get 5
                  i32.const 1
                  i32.eq
                  if (result i32)  ;; label = @8
                    local.get 2
                    local.get 6
                    call $dynrt_dynGe
                  else
                    local.get 2
                    local.get 6
                    call $dynrt_dynGt
                  end
                  local.set 2
                end
              end
            else
              i32.const 0
              local.set 3
            end
          end
          br 1 (;@2;)
        end
      end
    end
    local.get 2
    return)
  (func $dynrt__fn155 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt__fn154
    local.set 2
    i32.const 1
    local.set 3
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 3
          i32.const 1
          i32.eq
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt__fn143
            local.get 0
            local.get 1
            call $dynrt__fn144
            local.set 4
            local.get 0
            local.get 1
            call $dynrt__fn145
            local.set 5
            local.get 4
            i32.const 61
            i32.eq
            if (result i32)  ;; label = @5
              local.get 5
              i32.const 61
              i32.eq
            else
              i32.const 0
            end
            if  ;; label = @5
              block  ;; label = @6
                global.get $dynrt_global19
                i32.const 2
                i32.add
                global.set $dynrt_global19
                local.get 0
                local.get 1
                call $dynrt__fn144
                i32.const 61
                i32.eq
                if  ;; label = @7
                  global.get $dynrt_global19
                  i32.const 1
                  i32.add
                  global.set $dynrt_global19
                end
                local.get 2
                call $dynrt__fn54
                local.get 0
                local.get 1
                call $dynrt__fn154
                local.set 4
                call $dynrt__fn55
                local.get 2
                local.get 4
                call $dynrt_dynStrictEq
                call $dynrt_dynBool
                local.set 2
              end
            else
              local.get 4
              i32.const 33
              i32.eq
              if (result i32)  ;; label = @6
                local.get 5
                i32.const 61
                i32.eq
              else
                i32.const 0
              end
              if  ;; label = @6
                block  ;; label = @7
                  global.get $dynrt_global19
                  i32.const 2
                  i32.add
                  global.set $dynrt_global19
                  local.get 0
                  local.get 1
                  call $dynrt__fn144
                  i32.const 61
                  i32.eq
                  if  ;; label = @8
                    global.get $dynrt_global19
                    i32.const 1
                    i32.add
                    global.set $dynrt_global19
                  end
                  local.get 2
                  call $dynrt__fn54
                  local.get 0
                  local.get 1
                  call $dynrt__fn154
                  local.set 4
                  call $dynrt__fn55
                  local.get 2
                  local.get 4
                  call $dynrt_dynStrictEq
                  i32.eqz
                  if (result i32)  ;; label = @8
                    i32.const 1
                  else
                    i32.const 0
                  end
                  call $dynrt_dynBool
                  local.set 2
                end
              else
                i32.const 0
                local.set 3
              end
            end
          end
          br 1 (;@2;)
        end
      end
    end
    local.get 2
    return)
  (func $dynrt__fn156 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt__fn155
    local.set 2
    i32.const 1
    local.set 3
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 3
          i32.const 1
          i32.eq
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt__fn143
            local.get 0
            local.get 1
            call $dynrt__fn144
            i32.const 38
            i32.eq
            if (result i32)  ;; label = @5
              local.get 0
              local.get 1
              call $dynrt__fn145
              i32.const 38
              i32.eq
            else
              i32.const 0
            end
            if  ;; label = @5
              block  ;; label = @6
                global.get $dynrt_global19
                i32.const 2
                i32.add
                global.set $dynrt_global19
                local.get 2
                call $dynrt_dynToBool
                local.set 4
                global.get $dynrt_global21
                local.set 5
                local.get 4
                i32.eqz
                if  ;; label = @7
                  i32.const 0
                  global.set $dynrt_global21
                end
                local.get 2
                call $dynrt__fn54
                local.get 0
                local.get 1
                call $dynrt__fn155
                local.set 6
                call $dynrt__fn55
                local.get 5
                global.set $dynrt_global21
                local.get 4
                i32.const 1
                i32.eq
                if  ;; label = @7
                  local.get 6
                  local.set 2
                end
              end
            else
              i32.const 0
              local.set 3
            end
          end
          br 1 (;@2;)
        end
      end
    end
    local.get 2
    return)
  (func $dynrt__fn157 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt__fn156
    local.set 2
    i32.const 1
    local.set 3
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 3
          i32.const 1
          i32.eq
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt__fn143
            local.get 0
            local.get 1
            call $dynrt__fn144
            i32.const 124
            i32.eq
            if (result i32)  ;; label = @5
              local.get 0
              local.get 1
              call $dynrt__fn145
              i32.const 124
              i32.eq
            else
              i32.const 0
            end
            if  ;; label = @5
              block  ;; label = @6
                global.get $dynrt_global19
                i32.const 2
                i32.add
                global.set $dynrt_global19
                local.get 2
                call $dynrt_dynToBool
                local.set 4
                global.get $dynrt_global21
                local.set 5
                local.get 4
                i32.const 1
                i32.eq
                if  ;; label = @7
                  i32.const 0
                  global.set $dynrt_global21
                end
                local.get 2
                call $dynrt__fn54
                local.get 0
                local.get 1
                call $dynrt__fn156
                local.set 6
                call $dynrt__fn55
                local.get 5
                global.set $dynrt_global21
                local.get 4
                i32.eqz
                if  ;; label = @7
                  local.get 6
                  local.set 2
                end
              end
            else
              local.get 0
              local.get 1
              call $dynrt__fn144
              i32.const 63
              i32.eq
              if (result i32)  ;; label = @6
                local.get 0
                local.get 1
                call $dynrt__fn145
                i32.const 63
                i32.eq
              else
                i32.const 0
              end
              if  ;; label = @6
                block  ;; label = @7
                  global.get $dynrt_global19
                  i32.const 2
                  i32.add
                  global.set $dynrt_global19
                  local.get 2
                  local.tee 7
                  local.set 4
                  local.get 4
                  i32.const 8
                  i32.add
                  i32.load
                  local.set 4
                  local.get 4
                  i32.eqz
                  if (result i32)  ;; label = @8
                    i32.const 1
                  else
                    local.get 4
                    i32.const 1
                    i32.eq
                  end
                  if (result i32)  ;; label = @8
                    i32.const 1
                  else
                    i32.const 0
                  end
                  local.set 4
                  global.get $dynrt_global21
                  local.set 5
                  local.get 4
                  i32.eqz
                  if  ;; label = @8
                    i32.const 0
                    global.set $dynrt_global21
                  end
                  local.get 2
                  call $dynrt__fn54
                  local.get 0
                  local.get 1
                  call $dynrt__fn156
                  local.set 6
                  call $dynrt__fn55
                  local.get 5
                  global.set $dynrt_global21
                  local.get 4
                  i32.const 1
                  i32.eq
                  if  ;; label = @8
                    local.get 6
                    local.set 2
                  end
                end
              else
                i32.const 0
                local.set 3
              end
            end
          end
          br 1 (;@2;)
        end
      end
    end
    local.get 2
    return)
  (func $dynrt__fn158 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt__fn157
    local.set 2
    local.get 0
    local.get 1
    call $dynrt__fn143
    local.get 0
    local.get 1
    call $dynrt__fn144
    i32.const 63
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_global19
        i32.const 1
        i32.add
        global.set $dynrt_global19
        local.get 2
        call $dynrt_dynToBool
        local.set 2
        global.get $dynrt_global21
        local.set 3
        local.get 2
        i32.eqz
        if  ;; label = @3
          i32.const 0
          global.set $dynrt_global21
        end
        local.get 0
        local.get 1
        call $dynrt__fn158
        local.set 4
        local.get 3
        local.tee 6
        global.set $dynrt_global21
        local.get 0
        local.get 1
        call $dynrt__fn143
        local.get 0
        local.get 1
        call $dynrt__fn144
        i32.const 58
        i32.eq
        if  ;; label = @3
          global.get $dynrt_global19
          i32.const 1
          i32.add
          global.set $dynrt_global19
        end
        local.get 2
        i32.const 1
        i32.eq
        if  ;; label = @3
          i32.const 0
          global.set $dynrt_global21
        end
        local.get 4
        call $dynrt__fn54
        local.get 0
        local.get 1
        call $dynrt__fn158
        local.set 5
        call $dynrt__fn55
        local.get 3
        local.tee 7
        global.set $dynrt_global21
        local.get 2
        i32.const 1
        i32.eq
        if (result i32)  ;; label = @3
          local.get 4
        else
          local.get 5
        end
        return
      end
    end
    local.get 2
    return)
  (func $dynrt_dynEval (param i32 i32) (result i32)
    i32.const 0
    global.set $dynrt_global19
    i32.const -1
    global.set $dynrt_global20
    i32.const 1
    global.set $dynrt_global21
    local.get 0
    local.get 1
    call $dynrt__fn158
    return)
  (func $dynrt_dynEvalEnv (param i32 i32 i32) (result i32)
    i32.const 0
    global.set $dynrt_global19
    local.get 2
    global.set $dynrt_global20
    i32.const 1
    global.set $dynrt_global21
    local.get 0
    local.get 1
    call $dynrt__fn158
    return)
  (func $dynrt__fn161 (param i32 i32)
    (local i32) (local i32) (local i32) (local i32)
    global.get $dynrt_global19
    local.tee 4
    local.set 2
    local.get 0
    local.get 1
    call $dynrt__fn144
    local.set 3
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 3
          i32.const 1
          call $dynrt__fn142
          i32.const 1
          i32.eq
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            global.get $dynrt_global19
            i32.const 1
            i32.add
            global.set $dynrt_global19
            local.get 0
            local.get 1
            call $dynrt__fn144
            local.set 3
          end
          br 1 (;@2;)
        end
      end
    end
    local.get 0
    local.get 1
    local.get 2
    global.get $dynrt_global19
    call $dynrt__fn5
    local.set 3
    nop
    local.set 2
    local.get 2
    local.tee 5
    global.set $dynrt_global1
    local.get 3
    global.set $dynrt_global2
    return)
  (func $dynrt__fn162 (param i32 i32)
    (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt__fn143
    local.get 0
    local.get 1
    call $dynrt__fn161
    global.get $dynrt_global1
    local.set 2
    global.get $dynrt_global2
    local.set 3
    local.get 0
    local.get 1
    call $dynrt__fn143
    call $dynrt_dynUndefined
    local.set 4
    local.get 0
    local.get 1
    call $dynrt__fn144
    i32.const 61
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_global19
        i32.const 1
        i32.add
        global.set $dynrt_global19
        local.get 0
        local.get 1
        call $dynrt__fn158
        local.set 4
      end
    end
    global.get $dynrt_global21
    i32.const 1
    i32.eq
    if  ;; label = @1
      global.get $dynrt_global20
      local.get 2
      local.get 3
      local.get 4
      call $dynrt_dynSet
    end
    local.get 0
    local.get 1
    call $dynrt__fn143
    local.get 0
    local.get 1
    call $dynrt__fn144
    i32.const 59
    i32.eq
    if  ;; label = @1
      global.get $dynrt_global19
      i32.const 1
      i32.add
      global.set $dynrt_global19
    end)
  (func $dynrt__fn163 (param i32 i32)
    (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt__fn143
    local.get 0
    local.get 1
    call $dynrt__fn144
    local.set 2
    call $dynrt_dynUndefined
    local.set 3
    local.get 2
    i32.const 59
    i32.ne
    if (result i32)  ;; label = @1
      local.get 2
      i32.const 125
      i32.ne
    else
      i32.const 0
    end
    if (result i32)  ;; label = @1
      local.get 2
      i32.const -1
      i32.ne
    else
      i32.const 0
    end
    if  ;; label = @1
      local.get 0
      local.get 1
      call $dynrt__fn158
      local.set 3
    end
    global.get $dynrt_global21
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 3
        global.set $dynrt_global24
        i32.const 1
        global.set $dynrt_global23
      end
    end
    local.get 0
    local.get 1
    call $dynrt__fn143
    local.get 0
    local.get 1
    call $dynrt__fn144
    i32.const 59
    i32.eq
    if  ;; label = @1
      global.get $dynrt_global19
      i32.const 1
      i32.add
      global.set $dynrt_global19
    end)
  (func $dynrt__fn164 (param i32 i32)
    (local i32) (local i32) (local i32) (local i32) (local i32)
    global.get $dynrt_global21
    local.set 2
    local.get 0
    local.get 1
    call $dynrt__fn143
    local.get 0
    local.get 1
    call $dynrt__fn144
    i32.const 40
    i32.eq
    if  ;; label = @1
      global.get $dynrt_global19
      i32.const 1
      i32.add
      global.set $dynrt_global19
    end
    local.get 0
    local.get 1
    call $dynrt__fn158
    local.set 3
    local.get 0
    local.get 1
    call $dynrt__fn143
    local.get 0
    local.get 1
    call $dynrt__fn144
    i32.const 41
    i32.eq
    if  ;; label = @1
      global.get $dynrt_global19
      i32.const 1
      i32.add
      global.set $dynrt_global19
    end
    local.get 2
    i32.const 1
    i32.eq
    if (result i32)  ;; label = @1
      local.get 3
      call $dynrt_dynToBool
      i32.const 1
      i32.eq
    else
      i32.const 0
    end
    if (result i32)  ;; label = @1
      i32.const 1
    else
      i32.const 0
    end
    local.set 3
    local.get 2
    i32.const 1
    i32.eq
    if (result i32)  ;; label = @1
      local.get 3
      i32.const 1
      i32.eq
    else
      i32.const 0
    end
    if (result i32)  ;; label = @1
      i32.const 1
    else
      i32.const 0
    end
    global.set $dynrt_global21
    local.get 0
    local.get 1
    call $dynrt__fn183
    local.get 2
    global.set $dynrt_global21
    local.get 0
    local.get 1
    call $dynrt__fn143
    local.get 0
    local.get 1
    call $dynrt__fn144
    i32.const 0
    call $dynrt__fn142
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_global19
        local.set 4
        local.get 0
        local.get 1
        call $dynrt__fn161
        global.get $dynrt_global1
        local.set 5
        global.get $dynrt_global2
        local.set 6
        local.get 5
        local.get 6
        i32.const 1026
        i32.const 4
        call $dynrt__fn138
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 2
            i32.const 1
            i32.eq
            if (result i32)  ;; label = @5
              local.get 3
              i32.eqz
            else
              i32.const 0
            end
            if (result i32)  ;; label = @5
              i32.const 1
            else
              i32.const 0
            end
            global.set $dynrt_global21
            local.get 0
            local.get 1
            call $dynrt__fn183
            local.get 2
            global.set $dynrt_global21
          end
        else
          local.get 4
          global.set $dynrt_global19
        end
      end
    end)
  (func $dynrt__fn165 (param i32 i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    global.get $dynrt_global21
    local.set 2
    local.get 0
    local.get 1
    call $dynrt__fn143
    local.get 0
    local.get 1
    call $dynrt__fn144
    i32.const 40
    i32.eq
    if  ;; label = @1
      global.get $dynrt_global19
      i32.const 1
      i32.add
      global.set $dynrt_global19
    end
    global.get $dynrt_global19
    local.set 3
    i32.const 1
    local.set 4
    i32.const 0
    local.set 5
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 4
          i32.const 1
          i32.eq
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 3
            global.set $dynrt_global19
            local.get 0
            local.get 1
            call $dynrt__fn158
            local.set 6
            local.get 0
            local.get 1
            call $dynrt__fn143
            local.get 0
            local.get 1
            call $dynrt__fn144
            i32.const 41
            i32.eq
            if  ;; label = @5
              global.get $dynrt_global19
              i32.const 1
              i32.add
              global.set $dynrt_global19
            end
            local.get 2
            i32.const 1
            i32.eq
            if (result i32)  ;; label = @5
              local.get 6
              call $dynrt_dynToBool
              i32.const 1
              i32.eq
            else
              i32.const 0
            end
            if (result i32)  ;; label = @5
              i32.const 1
            else
              i32.const 0
            end
            local.set 6
            local.get 6
            i32.const 1
            i32.eq
            if  ;; label = @5
              block  ;; label = @6
                i32.const 1
                local.tee 9
                global.set $dynrt_global21
                local.get 0
                local.get 1
                call $dynrt__fn183
                local.get 2
                global.set $dynrt_global21
                global.get $dynrt_global23
                i32.const 1
                i32.eq
                if (result i32)  ;; label = @7
                  i32.const 1
                else
                  global.get $dynrt_global28
                  i32.const 1
                  i32.eq
                end
                if  ;; label = @7
                  i32.const 0
                  local.set 4
                else
                  global.get $dynrt_global26
                  i32.const 1
                  i32.eq
                  if  ;; label = @8
                    block  ;; label = @9
                      i32.const 0
                      local.tee 7
                      global.set $dynrt_global26
                      i32.const 0
                      local.tee 8
                      local.set 4
                    end
                  else
                    global.get $dynrt_global27
                    i32.const 1
                    i32.eq
                    if  ;; label = @9
                      i32.const 0
                      global.set $dynrt_global27
                    end
                  end
                end
                local.get 5
                i32.const 1
                local.tee 10
                i32.add
                local.set 5
                local.get 5
                i32.const 100000000
                i32.gt_s
                if  ;; label = @7
                  i32.const 0
                  local.set 4
                end
              end
            else
              block  ;; label = @6
                i32.const 0
                local.tee 11
                global.set $dynrt_global21
                local.get 0
                local.get 1
                call $dynrt__fn183
                local.get 2
                global.set $dynrt_global21
                i32.const 0
                local.tee 12
                local.set 4
              end
            end
          end
          br 1 (;@2;)
        end
      end
    end)
  (func $dynrt__fn166 (param i32 i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    global.get $dynrt_global21
    local.set 2
    local.get 0
    local.get 1
    call $dynrt__fn143
    global.get $dynrt_global19
    local.set 3
    i32.const 1
    local.set 4
    i32.const 0
    local.set 5
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 4
          i32.const 1
          i32.eq
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 3
            global.set $dynrt_global19
            local.get 2
            local.tee 8
            global.set $dynrt_global21
            local.get 0
            local.get 1
            call $dynrt__fn183
            local.get 2
            local.tee 9
            global.set $dynrt_global21
            local.get 0
            local.get 1
            call $dynrt__fn143
            local.get 0
            local.get 1
            call $dynrt__fn144
            i32.const 0
            call $dynrt__fn142
            i32.const 1
            i32.eq
            if  ;; label = @5
              local.get 0
              local.get 1
              call $dynrt__fn161
            end
            local.get 0
            local.get 1
            call $dynrt__fn143
            local.get 0
            local.get 1
            call $dynrt__fn144
            i32.const 40
            i32.eq
            if  ;; label = @5
              global.get $dynrt_global19
              i32.const 1
              i32.add
              global.set $dynrt_global19
            end
            local.get 0
            local.get 1
            call $dynrt__fn158
            local.set 4
            local.get 0
            local.get 1
            call $dynrt__fn143
            local.get 0
            local.get 1
            call $dynrt__fn144
            i32.const 41
            i32.eq
            if  ;; label = @5
              global.get $dynrt_global19
              i32.const 1
              i32.add
              global.set $dynrt_global19
            end
            local.get 0
            local.get 1
            call $dynrt__fn143
            local.get 0
            local.get 1
            call $dynrt__fn144
            i32.const 59
            i32.eq
            if  ;; label = @5
              global.get $dynrt_global19
              i32.const 1
              i32.add
              global.set $dynrt_global19
            end
            local.get 2
            i32.eqz
            if  ;; label = @5
              i32.const 0
              local.set 4
            else
              global.get $dynrt_global23
              i32.const 1
              i32.eq
              if (result i32)  ;; label = @6
                i32.const 1
              else
                global.get $dynrt_global28
                i32.const 1
                i32.eq
              end
              if  ;; label = @6
                i32.const 0
                local.set 4
              else
                global.get $dynrt_global26
                i32.const 1
                i32.eq
                if  ;; label = @7
                  block  ;; label = @8
                    i32.const 0
                    local.tee 6
                    global.set $dynrt_global26
                    i32.const 0
                    local.tee 7
                    local.set 4
                  end
                else
                  block  ;; label = @8
                    global.get $dynrt_global27
                    i32.const 1
                    i32.eq
                    if  ;; label = @9
                      i32.const 0
                      global.set $dynrt_global27
                    end
                    local.get 4
                    call $dynrt_dynToBool
                    i32.const 1
                    i32.eq
                    if (result i32)  ;; label = @9
                      i32.const 1
                    else
                      i32.const 0
                    end
                    local.set 4
                  end
                end
              end
            end
            local.get 5
            i32.const 1
            i32.add
            local.set 5
            local.get 5
            i32.const 100000000
            i32.gt_s
            if  ;; label = @5
              i32.const 0
              local.set 4
            end
          end
          br 1 (;@2;)
        end
      end
    end)
  (func $dynrt__fn167 (param i32 i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    global.get $dynrt_global21
    local.set 2
    global.get $dynrt_global20
    local.set 3
    local.get 3
    call $dynrt__fn126
    local.set 4
    local.get 4
    local.tee 13
    global.set $dynrt_global20
    local.get 4
    call $dynrt__fn54
    local.get 0
    local.get 1
    call $dynrt__fn143
    local.get 0
    local.get 1
    call $dynrt__fn144
    i32.const 40
    i32.eq
    if  ;; label = @1
      global.get $dynrt_global19
      i32.const 1
      i32.add
      global.set $dynrt_global19
    end
    global.get $dynrt_global19
    local.set 4
    local.get 0
    local.get 1
    call $dynrt__fn143
    i32.const 0
    local.tee 14
    local.set 5
    i32.const 534
    local.set 6
    local.get 14
    local.set 7
    local.get 14
    local.set 8
    local.get 0
    local.get 1
    call $dynrt__fn144
    i32.const 0
    call $dynrt__fn142
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 0
        local.get 1
        call $dynrt__fn161
        global.get $dynrt_global1
        local.set 9
        global.get $dynrt_global2
        local.set 10
        local.get 9
        local.set 11
        local.get 10
        local.set 12
        local.get 9
        local.get 10
        i32.const 1030
        i32.const 5
        call $dynrt__fn138
        i32.const 1
        i32.eq
        if (result i32)  ;; label = @3
          i32.const 1
        else
          local.get 9
          local.get 10
          i32.const 1035
          i32.const 3
          call $dynrt__fn138
          i32.const 1
          i32.eq
        end
        if (result i32)  ;; label = @3
          i32.const 1
        else
          local.get 9
          local.get 10
          i32.const 1038
          i32.const 3
          call $dynrt__fn138
          i32.const 1
          i32.eq
        end
        if  ;; label = @3
          block  ;; label = @4
            local.get 9
            local.get 10
            i32.const 1038
            i32.const 3
            call $dynrt__fn138
            i32.const 1
            i32.ne
            if  ;; label = @5
              i32.const 1
              local.set 8
            end
            local.get 0
            local.get 1
            call $dynrt__fn143
            local.get 0
            local.get 1
            call $dynrt__fn161
            global.get $dynrt_global1
            local.set 11
            global.get $dynrt_global2
            local.set 12
          end
        end
        local.get 0
        local.get 1
        call $dynrt__fn143
        local.get 0
        local.get 1
        call $dynrt__fn144
        i32.const 0
        call $dynrt__fn142
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt__fn161
            global.get $dynrt_global1
            local.set 9
            global.get $dynrt_global2
            local.set 10
            local.get 9
            local.get 10
            i32.const 1041
            i32.const 2
            call $dynrt__fn138
            i32.const 1
            i32.eq
            if  ;; label = @5
              block  ;; label = @6
                i32.const 1
                local.set 5
                local.get 11
                local.set 6
                local.get 12
                local.set 7
              end
            else
              local.get 9
              local.get 10
              i32.const 1043
              i32.const 2
              call $dynrt__fn138
              i32.const 1
              i32.eq
              if  ;; label = @6
                block  ;; label = @7
                  i32.const 2
                  local.set 5
                  local.get 11
                  local.set 6
                  local.get 12
                  local.set 7
                end
              end
            end
          end
        end
      end
    end
    local.get 5
    i32.const 1
    i32.eq
    if  ;; label = @1
      local.get 0
      local.get 1
      local.get 6
      local.get 7
      local.get 2
      local.get 8
      call $dynrt__fn169
    else
      local.get 5
      i32.const 2
      i32.eq
      if  ;; label = @2
        local.get 0
        local.get 1
        local.get 6
        local.get 7
        local.get 2
        local.get 8
        call $dynrt__fn168
      else
        block  ;; label = @3
          local.get 4
          global.set $dynrt_global19
          local.get 0
          local.get 1
          local.get 2
          local.get 8
          call $dynrt__fn170
        end
      end
    end
    call $dynrt__fn55
    local.get 3
    local.tee 15
    global.set $dynrt_global20)
  (func $dynrt__fn168 (param i32 i32 i32 i32 i32 i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    global.get $dynrt_global20
    local.set 6
    local.get 0
    local.get 1
    call $dynrt__fn158
    local.set 7
    local.get 0
    local.get 1
    call $dynrt__fn143
    local.get 0
    local.get 1
    call $dynrt__fn144
    i32.const 41
    i32.eq
    if  ;; label = @1
      global.get $dynrt_global19
      i32.const 1
      i32.add
      global.set $dynrt_global19
    end
    global.get $dynrt_global19
    local.set 8
    i32.const 0
    local.tee 18
    local.set 9
    local.get 7
    local.set 10
    local.get 4
    i32.const 1
    i32.eq
    if (result i32)  ;; label = @1
      local.get 10
      i32.const 8
      i32.add
      i32.load
      i32.const 6
      i32.eq
    else
      i32.const 0
    end
    if  ;; label = @1
      local.get 7
      call $dynrt_dynObjLen
      local.set 9
    end
    local.get 4
    i32.const 1
    i32.eq
    if (result i32)  ;; label = @1
      local.get 9
      i32.const 0
      i32.gt_s
    else
      i32.const 0
    end
    if (result i32)  ;; label = @1
      i32.const 1
    else
      i32.const 0
    end
    local.set 10
    local.get 10
    i32.eqz
    if  ;; label = @1
      block  ;; label = @2
        i32.const 0
        global.set $dynrt_global21
        local.get 8
        global.set $dynrt_global19
        local.get 0
        local.get 1
        call $dynrt__fn183
        local.get 4
        global.set $dynrt_global21
        return
      end
    end
    i32.const 0
    local.tee 19
    local.set 11
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 10
          i32.const 1
          i32.eq
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 6
            local.tee 15
            local.set 12
            local.get 5
            i32.const 1
            i32.eq
            if  ;; label = @5
              local.get 6
              call $dynrt__fn126
              local.set 12
            end
            local.get 12
            local.get 2
            local.get 3
            local.get 7
            local.get 11
            call $dynrt__fn88
            call $dynrt_dynSet
            local.get 12
            local.tee 16
            global.set $dynrt_global20
            local.get 8
            global.set $dynrt_global19
            i32.const 1
            global.set $dynrt_global21
            local.get 0
            local.get 1
            call $dynrt__fn183
            local.get 4
            global.set $dynrt_global21
            local.get 6
            local.tee 17
            global.set $dynrt_global20
            global.get $dynrt_global23
            i32.const 1
            i32.eq
            if (result i32)  ;; label = @5
              i32.const 1
            else
              global.get $dynrt_global28
              i32.const 1
              i32.eq
            end
            if  ;; label = @5
              i32.const 0
              local.set 10
            else
              global.get $dynrt_global26
              i32.const 1
              i32.eq
              if  ;; label = @6
                block  ;; label = @7
                  i32.const 0
                  local.tee 13
                  global.set $dynrt_global26
                  i32.const 0
                  local.tee 14
                  local.set 10
                end
              else
                block  ;; label = @7
                  global.get $dynrt_global27
                  i32.const 1
                  i32.eq
                  if  ;; label = @8
                    i32.const 0
                    global.set $dynrt_global27
                  end
                  local.get 11
                  i32.const 1
                  i32.add
                  local.set 11
                  local.get 11
                  local.get 9
                  i32.ge_s
                  if  ;; label = @8
                    i32.const 0
                    local.set 10
                  end
                end
              end
            end
          end
          br 1 (;@2;)
        end
      end
    end)
  (func $dynrt__fn169 (param i32 i32 i32 i32 i32 i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    global.get $dynrt_global20
    local.set 6
    local.get 0
    local.get 1
    call $dynrt__fn158
    local.set 7
    local.get 0
    local.get 1
    call $dynrt__fn143
    local.get 0
    local.get 1
    call $dynrt__fn144
    i32.const 41
    i32.eq
    if  ;; label = @1
      global.get $dynrt_global19
      i32.const 1
      i32.add
      global.set $dynrt_global19
    end
    global.get $dynrt_global19
    local.set 8
    i32.const 0
    local.tee 18
    local.set 9
    local.get 7
    local.set 10
    local.get 4
    i32.const 1
    i32.eq
    if (result i32)  ;; label = @1
      local.get 10
      i32.const 8
      i32.add
      i32.load
      i32.const 5
      i32.eq
    else
      i32.const 0
    end
    if  ;; label = @1
      local.get 7
      call $dynrt_dynArrLen
      local.set 9
    end
    local.get 4
    i32.const 1
    i32.eq
    if (result i32)  ;; label = @1
      local.get 9
      i32.const 0
      i32.gt_s
    else
      i32.const 0
    end
    if (result i32)  ;; label = @1
      i32.const 1
    else
      i32.const 0
    end
    local.set 10
    local.get 10
    i32.eqz
    if  ;; label = @1
      block  ;; label = @2
        i32.const 0
        global.set $dynrt_global21
        local.get 8
        global.set $dynrt_global19
        local.get 0
        local.get 1
        call $dynrt__fn183
        local.get 4
        global.set $dynrt_global21
        return
      end
    end
    i32.const 0
    local.tee 19
    local.set 11
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 10
          i32.const 1
          i32.eq
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 6
            local.tee 15
            local.set 12
            local.get 5
            i32.const 1
            i32.eq
            if  ;; label = @5
              local.get 6
              call $dynrt__fn126
              local.set 12
            end
            local.get 12
            local.get 2
            local.get 3
            local.get 7
            local.get 11
            call $dynrt_dynArrGet
            call $dynrt_dynSet
            local.get 12
            local.tee 16
            global.set $dynrt_global20
            local.get 8
            global.set $dynrt_global19
            i32.const 1
            global.set $dynrt_global21
            local.get 0
            local.get 1
            call $dynrt__fn183
            local.get 4
            global.set $dynrt_global21
            local.get 6
            local.tee 17
            global.set $dynrt_global20
            global.get $dynrt_global23
            i32.const 1
            i32.eq
            if (result i32)  ;; label = @5
              i32.const 1
            else
              global.get $dynrt_global28
              i32.const 1
              i32.eq
            end
            if  ;; label = @5
              i32.const 0
              local.set 10
            else
              global.get $dynrt_global26
              i32.const 1
              i32.eq
              if  ;; label = @6
                block  ;; label = @7
                  i32.const 0
                  local.tee 13
                  global.set $dynrt_global26
                  i32.const 0
                  local.tee 14
                  local.set 10
                end
              else
                block  ;; label = @7
                  global.get $dynrt_global27
                  i32.const 1
                  i32.eq
                  if  ;; label = @8
                    i32.const 0
                    global.set $dynrt_global27
                  end
                  local.get 11
                  i32.const 1
                  i32.add
                  local.set 11
                  local.get 11
                  local.get 9
                  i32.ge_s
                  if  ;; label = @8
                    i32.const 0
                    local.set 10
                  end
                end
              end
            end
          end
          br 1 (;@2;)
        end
      end
    end)
  (func $dynrt__fn170 (param i32 i32 i32 i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    global.get $dynrt_global20
    local.set 4
    local.get 4
    local.tee 25
    local.set 5
    local.get 5
    i32.const 8
    i32.add
    i32.const 8
    i32.add
    i32.load
    local.set 5
    local.get 2
    global.set $dynrt_global21
    local.get 0
    local.get 1
    call $dynrt__fn183
    global.get $dynrt_global19
    local.set 6
    local.get 4
    local.tee 26
    local.set 7
    local.get 3
    i32.const 1
    i32.eq
    if  ;; label = @1
      local.get 4
      local.get 5
      call $dynrt__fn128
      local.set 7
    end
    i32.const 1
    local.set 8
    i32.const 0
    local.set 9
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 8
          i32.const 1
          i32.eq
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 7
            global.set $dynrt_global20
            local.get 6
            global.set $dynrt_global19
            local.get 0
            local.get 1
            call $dynrt__fn143
            i32.const 1
            local.set 10
            local.get 0
            local.get 1
            call $dynrt__fn144
            i32.const 59
            i32.ne
            if  ;; label = @5
              local.get 0
              local.get 1
              call $dynrt__fn158
              call $dynrt_dynToBool
              local.set 10
            end
            local.get 0
            local.get 1
            call $dynrt__fn143
            local.get 0
            local.get 1
            call $dynrt__fn144
            i32.const 59
            i32.eq
            if  ;; label = @5
              global.get $dynrt_global19
              i32.const 1
              i32.add
              global.set $dynrt_global19
            end
            global.get $dynrt_global19
            local.tee 23
            local.set 11
            i32.const 0
            global.set $dynrt_global21
            local.get 0
            local.get 1
            call $dynrt__fn144
            i32.const 41
            i32.ne
            if  ;; label = @5
              local.get 0
              local.get 1
              call $dynrt__fn183
            end
            local.get 0
            local.get 1
            call $dynrt__fn143
            local.get 0
            local.get 1
            call $dynrt__fn144
            i32.const 41
            i32.eq
            if  ;; label = @5
              global.get $dynrt_global19
              i32.const 1
              i32.add
              global.set $dynrt_global19
            end
            global.get $dynrt_global19
            local.tee 24
            local.set 12
            local.get 2
            i32.const 1
            i32.eq
            if (result i32)  ;; label = @5
              local.get 10
              i32.const 1
              i32.eq
            else
              i32.const 0
            end
            if (result i32)  ;; label = @5
              i32.const 1
            else
              i32.const 0
            end
            local.set 10
            local.get 10
            i32.const 1
            i32.eq
            if  ;; label = @5
              block  ;; label = @6
                local.get 7
                global.set $dynrt_global20
                local.get 12
                global.set $dynrt_global19
                i32.const 1
                local.tee 19
                global.set $dynrt_global21
                local.get 0
                local.get 1
                call $dynrt__fn183
                local.get 2
                global.set $dynrt_global21
                global.get $dynrt_global23
                i32.const 1
                i32.eq
                if (result i32)  ;; label = @7
                  i32.const 1
                else
                  global.get $dynrt_global28
                  i32.const 1
                  i32.eq
                end
                if  ;; label = @7
                  i32.const 0
                  local.set 8
                else
                  global.get $dynrt_global26
                  i32.const 1
                  i32.eq
                  if  ;; label = @8
                    block  ;; label = @9
                      i32.const 0
                      local.tee 13
                      global.set $dynrt_global26
                      i32.const 0
                      local.tee 14
                      local.set 8
                    end
                  else
                    block  ;; label = @9
                      global.get $dynrt_global27
                      i32.const 1
                      i32.eq
                      if  ;; label = @10
                        i32.const 0
                        global.set $dynrt_global27
                      end
                      local.get 7
                      local.set 10
                      local.get 3
                      i32.const 1
                      i32.eq
                      if  ;; label = @10
                        local.get 7
                        local.get 5
                        call $dynrt__fn128
                        local.set 10
                      end
                      local.get 10
                      local.tee 15
                      global.set $dynrt_global20
                      local.get 11
                      global.set $dynrt_global19
                      local.get 2
                      local.tee 16
                      global.set $dynrt_global21
                      local.get 0
                      local.get 1
                      call $dynrt__fn144
                      i32.const 41
                      i32.ne
                      if  ;; label = @10
                        local.get 0
                        local.get 1
                        call $dynrt__fn183
                      end
                      local.get 2
                      local.tee 17
                      global.set $dynrt_global21
                      local.get 10
                      local.tee 18
                      local.set 7
                    end
                  end
                end
                local.get 9
                i32.const 1
                local.tee 20
                i32.add
                local.set 9
                local.get 9
                i32.const 100000000
                i32.gt_s
                if  ;; label = @7
                  i32.const 0
                  local.set 8
                end
              end
            else
              block  ;; label = @6
                local.get 7
                global.set $dynrt_global20
                local.get 12
                global.set $dynrt_global19
                i32.const 0
                local.tee 21
                global.set $dynrt_global21
                local.get 0
                local.get 1
                call $dynrt__fn183
                local.get 2
                global.set $dynrt_global21
                i32.const 0
                local.tee 22
                local.set 8
              end
            end
          end
          br 1 (;@2;)
        end
      end
    end
    local.get 4
    local.tee 27
    global.set $dynrt_global20)
  (func $dynrt__fn171 (param i32 i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    global.get $dynrt_global21
    local.set 2
    local.get 0
    local.get 1
    call $dynrt__fn143
    local.get 0
    local.get 1
    call $dynrt__fn144
    i32.const 40
    i32.eq
    if  ;; label = @1
      global.get $dynrt_global19
      i32.const 1
      i32.add
      global.set $dynrt_global19
    end
    local.get 0
    local.get 1
    call $dynrt__fn158
    local.set 3
    local.get 0
    local.get 1
    call $dynrt__fn143
    local.get 0
    local.get 1
    call $dynrt__fn144
    i32.const 41
    i32.eq
    if  ;; label = @1
      global.get $dynrt_global19
      i32.const 1
      i32.add
      global.set $dynrt_global19
    end
    local.get 0
    local.get 1
    call $dynrt__fn143
    local.get 0
    local.get 1
    call $dynrt__fn144
    i32.const 123
    i32.eq
    if  ;; label = @1
      global.get $dynrt_global19
      i32.const 1
      i32.add
      global.set $dynrt_global19
    end
    i32.const -1
    local.tee 10
    local.set 4
    local.get 10
    local.set 5
    i32.const 1
    local.set 6
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 6
          i32.const 1
          i32.eq
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt__fn143
            local.get 0
            local.get 1
            call $dynrt__fn144
            local.set 7
            local.get 7
            i32.const 125
            i32.eq
            if (result i32)  ;; label = @5
              i32.const 1
            else
              local.get 7
              i32.const -1
              i32.eq
            end
            if  ;; label = @5
              i32.const 0
              local.set 6
            else
              local.get 7
              i32.const 0
              call $dynrt__fn142
              i32.const 1
              i32.eq
              if  ;; label = @6
                block  ;; label = @7
                  global.get $dynrt_global19
                  local.set 7
                  local.get 0
                  local.get 1
                  call $dynrt__fn161
                  global.get $dynrt_global1
                  local.set 8
                  global.get $dynrt_global2
                  local.set 9
                  local.get 8
                  local.get 9
                  i32.const 1045
                  i32.const 4
                  call $dynrt__fn138
                  i32.const 1
                  i32.eq
                  if  ;; label = @8
                    block  ;; label = @9
                      local.get 4
                      i32.const -1
                      i32.eq
                      if  ;; label = @10
                        block  ;; label = @11
                          local.get 0
                          local.get 1
                          call $dynrt__fn158
                          local.set 7
                          local.get 0
                          local.get 1
                          call $dynrt__fn143
                          local.get 0
                          local.get 1
                          call $dynrt__fn144
                          i32.const 58
                          i32.eq
                          if  ;; label = @12
                            global.get $dynrt_global19
                            i32.const 1
                            i32.add
                            global.set $dynrt_global19
                          end
                          local.get 3
                          local.get 7
                          call $dynrt_dynStrictEq
                          i32.const 1
                          i32.eq
                          if  ;; label = @12
                            global.get $dynrt_global19
                            local.set 4
                          end
                        end
                      else
                        block  ;; label = @11
                          global.get $dynrt_global21
                          local.set 7
                          i32.const 0
                          global.set $dynrt_global21
                          local.get 0
                          local.get 1
                          call $dynrt__fn158
                          drop
                          local.get 7
                          global.set $dynrt_global21
                          local.get 0
                          local.get 1
                          call $dynrt__fn143
                          local.get 0
                          local.get 1
                          call $dynrt__fn144
                          i32.const 58
                          i32.eq
                          if  ;; label = @12
                            global.get $dynrt_global19
                            i32.const 1
                            i32.add
                            global.set $dynrt_global19
                          end
                        end
                      end
                      local.get 0
                      local.get 1
                      call $dynrt__fn172
                    end
                  else
                    local.get 8
                    local.get 9
                    i32.const 1049
                    i32.const 7
                    call $dynrt__fn138
                    i32.const 1
                    i32.eq
                    if  ;; label = @9
                      block  ;; label = @10
                        local.get 0
                        local.get 1
                        call $dynrt__fn143
                        local.get 0
                        local.get 1
                        call $dynrt__fn144
                        i32.const 58
                        i32.eq
                        if  ;; label = @11
                          global.get $dynrt_global19
                          i32.const 1
                          i32.add
                          global.set $dynrt_global19
                        end
                        global.get $dynrt_global19
                        local.set 5
                        local.get 0
                        local.get 1
                        call $dynrt__fn172
                      end
                    else
                      block  ;; label = @10
                        local.get 7
                        global.set $dynrt_global19
                        local.get 0
                        local.get 1
                        call $dynrt__fn172
                      end
                    end
                  end
                end
              else
                i32.const 0
                local.set 6
              end
            end
          end
          br 1 (;@2;)
        end
      end
    end
    global.get $dynrt_global19
    local.set 3
    local.get 4
    local.set 4
    local.get 4
    i32.const -1
    i32.eq
    if  ;; label = @1
      local.get 5
      local.set 4
    end
    local.get 2
    i32.const 1
    i32.eq
    if (result i32)  ;; label = @1
      local.get 4
      i32.const -1
      i32.ne
    else
      i32.const 0
    end
    if  ;; label = @1
      block  ;; label = @2
        local.get 4
        global.set $dynrt_global19
        i32.const 1
        global.set $dynrt_global21
        local.get 0
        local.get 1
        call $dynrt__fn173
        local.get 2
        global.set $dynrt_global21
      end
    end
    local.get 3
    global.set $dynrt_global19
    local.get 0
    local.get 1
    call $dynrt__fn143
    local.get 0
    local.get 1
    call $dynrt__fn144
    i32.const 125
    i32.eq
    if  ;; label = @1
      global.get $dynrt_global19
      i32.const 1
      i32.add
      global.set $dynrt_global19
    end
    global.get $dynrt_global26
    i32.const 1
    i32.eq
    if  ;; label = @1
      i32.const 0
      global.set $dynrt_global26
    end)
  (func $dynrt__fn172 (param i32 i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    i32.const 1
    local.set 2
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 2
          i32.const 1
          i32.eq
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt__fn143
            local.get 0
            local.get 1
            call $dynrt__fn144
            local.set 3
            local.get 3
            i32.const 125
            i32.eq
            if (result i32)  ;; label = @5
              i32.const 1
            else
              local.get 3
              i32.const -1
              i32.eq
            end
            if  ;; label = @5
              i32.const 0
              local.set 2
            else
              local.get 3
              i32.const 0
              call $dynrt__fn142
              i32.const 1
              i32.eq
              if  ;; label = @6
                block  ;; label = @7
                  global.get $dynrt_global19
                  local.set 3
                  local.get 0
                  local.get 1
                  call $dynrt__fn161
                  global.get $dynrt_global1
                  local.set 4
                  global.get $dynrt_global2
                  local.set 5
                  local.get 4
                  local.get 5
                  i32.const 1045
                  i32.const 4
                  call $dynrt__fn138
                  i32.const 1
                  i32.eq
                  if (result i32)  ;; label = @8
                    i32.const 1
                  else
                    local.get 4
                    local.get 5
                    i32.const 1049
                    i32.const 7
                    call $dynrt__fn138
                    i32.const 1
                    i32.eq
                  end
                  if  ;; label = @8
                    block  ;; label = @9
                      local.get 3
                      global.set $dynrt_global19
                      i32.const 0
                      local.set 2
                    end
                  else
                    block  ;; label = @9
                      local.get 3
                      local.tee 6
                      global.set $dynrt_global19
                      global.get $dynrt_global21
                      local.set 3
                      i32.const 0
                      global.set $dynrt_global21
                      local.get 0
                      local.get 1
                      call $dynrt__fn183
                      local.get 3
                      local.tee 7
                      global.set $dynrt_global21
                    end
                  end
                end
              else
                block  ;; label = @7
                  global.get $dynrt_global21
                  local.set 3
                  i32.const 0
                  global.set $dynrt_global21
                  local.get 0
                  local.get 1
                  call $dynrt__fn183
                  local.get 3
                  global.set $dynrt_global21
                end
              end
            end
          end
          br 1 (;@2;)
        end
      end
    end)
  (func $dynrt__fn173 (param i32 i32)
    (local i32) (local i32) (local i32) (local i32)
    i32.const 1
    local.set 2
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 2
          i32.const 1
          i32.eq
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt__fn143
            local.get 0
            local.get 1
            call $dynrt__fn144
            local.set 3
            local.get 3
            i32.const 125
            i32.eq
            if (result i32)  ;; label = @5
              i32.const 1
            else
              local.get 3
              i32.const -1
              i32.eq
            end
            if  ;; label = @5
              i32.const 0
              local.set 2
            else
              local.get 3
              i32.const 0
              call $dynrt__fn142
              i32.const 1
              i32.eq
              if  ;; label = @6
                block  ;; label = @7
                  global.get $dynrt_global19
                  local.set 3
                  local.get 0
                  local.get 1
                  call $dynrt__fn161
                  global.get $dynrt_global1
                  local.set 4
                  global.get $dynrt_global2
                  local.set 5
                  local.get 4
                  local.get 5
                  i32.const 1045
                  i32.const 4
                  call $dynrt__fn138
                  i32.const 1
                  i32.eq
                  if  ;; label = @8
                    block  ;; label = @9
                      global.get $dynrt_global21
                      local.set 3
                      i32.const 0
                      global.set $dynrt_global21
                      local.get 0
                      local.get 1
                      call $dynrt__fn158
                      drop
                      local.get 3
                      global.set $dynrt_global21
                      local.get 0
                      local.get 1
                      call $dynrt__fn143
                      local.get 0
                      local.get 1
                      call $dynrt__fn144
                      i32.const 58
                      i32.eq
                      if  ;; label = @10
                        global.get $dynrt_global19
                        i32.const 1
                        i32.add
                        global.set $dynrt_global19
                      end
                    end
                  else
                    local.get 4
                    local.get 5
                    i32.const 1049
                    i32.const 7
                    call $dynrt__fn138
                    i32.const 1
                    i32.eq
                    if  ;; label = @9
                      block  ;; label = @10
                        local.get 0
                        local.get 1
                        call $dynrt__fn143
                        local.get 0
                        local.get 1
                        call $dynrt__fn144
                        i32.const 58
                        i32.eq
                        if  ;; label = @11
                          global.get $dynrt_global19
                          i32.const 1
                          i32.add
                          global.set $dynrt_global19
                        end
                      end
                    else
                      block  ;; label = @10
                        local.get 3
                        global.set $dynrt_global19
                        local.get 0
                        local.get 1
                        call $dynrt__fn183
                      end
                    end
                  end
                end
              else
                local.get 0
                local.get 1
                call $dynrt__fn183
              end
            end
            global.get $dynrt_global26
            i32.const 1
            i32.eq
            if  ;; label = @5
              i32.const 0
              local.set 2
            end
            global.get $dynrt_global23
            i32.const 1
            i32.eq
            if  ;; label = @5
              i32.const 0
              local.set 2
            end
            global.get $dynrt_global28
            i32.const 1
            i32.eq
            if  ;; label = @5
              i32.const 0
              local.set 2
            end
            global.get $dynrt_global27
            i32.const 1
            i32.eq
            if  ;; label = @5
              i32.const 0
              local.set 2
            end
          end
          br 1 (;@2;)
        end
      end
    end)
  (func $dynrt__fn174 (param i32 i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    global.get $dynrt_global21
    local.set 2
    local.get 0
    local.get 1
    call $dynrt__fn143
    local.get 2
    local.tee 17
    global.set $dynrt_global21
    local.get 0
    local.get 1
    call $dynrt__fn183
    local.get 2
    local.tee 18
    global.set $dynrt_global21
    local.get 0
    local.get 1
    call $dynrt__fn143
    i32.const 0
    local.tee 19
    local.set 3
    global.get $dynrt_global19
    local.tee 20
    local.set 4
    local.get 0
    local.get 1
    call $dynrt__fn144
    i32.const 0
    call $dynrt__fn142
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 0
        local.get 1
        call $dynrt__fn161
        global.get $dynrt_global1
        local.set 5
        global.get $dynrt_global2
        local.set 6
        local.get 5
        local.get 6
        i32.const 1056
        i32.const 5
        call $dynrt__fn138
        i32.const 1
        i32.eq
        if  ;; label = @3
          i32.const 1
          local.set 3
        else
          local.get 4
          global.set $dynrt_global19
        end
      end
    end
    local.get 3
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        i32.const 534
        local.set 3
        i32.const 0
        local.set 4
        local.get 0
        local.get 1
        call $dynrt__fn143
        local.get 0
        local.get 1
        call $dynrt__fn144
        i32.const 40
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            global.get $dynrt_global19
            i32.const 1
            i32.add
            global.set $dynrt_global19
            local.get 0
            local.get 1
            call $dynrt__fn143
            local.get 0
            local.get 1
            call $dynrt__fn161
            global.get $dynrt_global1
            local.set 3
            global.get $dynrt_global2
            local.set 4
            local.get 0
            local.get 1
            call $dynrt__fn143
            local.get 0
            local.get 1
            call $dynrt__fn144
            i32.const 41
            i32.eq
            if  ;; label = @5
              global.get $dynrt_global19
              i32.const 1
              i32.add
              global.set $dynrt_global19
            end
          end
        end
        local.get 0
        local.get 1
        call $dynrt__fn143
        global.get $dynrt_global28
        i32.const 1
        i32.eq
        if (result i32)  ;; label = @3
          local.get 2
          i32.const 1
          i32.eq
        else
          i32.const 0
        end
        if  ;; label = @3
          block  ;; label = @4
            global.get $dynrt_global29
            local.set 5
            i32.const 0
            global.set $dynrt_global28
            global.get $dynrt_global20
            local.set 6
            local.get 6
            call $dynrt__fn126
            local.set 7
            local.get 4
            i32.const 0
            i32.gt_s
            if  ;; label = @5
              local.get 7
              local.get 3
              local.get 4
              local.get 5
              call $dynrt_dynSet
            end
            local.get 7
            local.tee 9
            global.set $dynrt_global20
            local.get 7
            call $dynrt__fn54
            i32.const 1
            global.set $dynrt_global21
            local.get 0
            local.get 1
            call $dynrt__fn183
            call $dynrt__fn55
            local.get 6
            local.tee 10
            global.set $dynrt_global20
            local.get 2
            global.set $dynrt_global21
          end
        else
          block  ;; label = @4
            i32.const 0
            global.set $dynrt_global21
            local.get 0
            local.get 1
            call $dynrt__fn183
            local.get 2
            global.set $dynrt_global21
          end
        end
      end
    end
    local.get 0
    local.get 1
    call $dynrt__fn143
    i32.const 0
    local.tee 21
    local.set 3
    global.get $dynrt_global19
    local.tee 22
    local.set 4
    local.get 0
    local.get 1
    call $dynrt__fn144
    i32.const 0
    call $dynrt__fn142
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 0
        local.get 1
        call $dynrt__fn161
        global.get $dynrt_global1
        local.set 5
        global.get $dynrt_global2
        local.set 6
        local.get 5
        local.get 6
        i32.const 1061
        i32.const 7
        call $dynrt__fn138
        i32.const 1
        i32.eq
        if  ;; label = @3
          i32.const 1
          local.set 3
        else
          local.get 4
          global.set $dynrt_global19
        end
      end
    end
    local.get 3
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_global28
        local.set 3
        global.get $dynrt_global29
        local.set 4
        global.get $dynrt_global23
        local.set 5
        global.get $dynrt_global24
        local.set 6
        global.get $dynrt_global26
        local.set 7
        global.get $dynrt_global27
        local.set 8
        i32.const 0
        local.tee 11
        global.set $dynrt_global28
        i32.const 0
        local.tee 12
        global.set $dynrt_global23
        i32.const 0
        local.tee 13
        global.set $dynrt_global26
        i32.const 0
        local.tee 14
        global.set $dynrt_global27
        local.get 0
        local.get 1
        call $dynrt__fn143
        local.get 2
        local.tee 15
        global.set $dynrt_global21
        local.get 0
        local.get 1
        call $dynrt__fn183
        local.get 2
        local.tee 16
        global.set $dynrt_global21
        global.get $dynrt_global28
        i32.eqz
        if (result i32)  ;; label = @3
          global.get $dynrt_global23
          i32.eqz
        else
          i32.const 0
        end
        if (result i32)  ;; label = @3
          global.get $dynrt_global26
          i32.eqz
        else
          i32.const 0
        end
        if (result i32)  ;; label = @3
          global.get $dynrt_global27
          i32.eqz
        else
          i32.const 0
        end
        if  ;; label = @3
          block  ;; label = @4
            local.get 3
            global.set $dynrt_global28
            local.get 4
            global.set $dynrt_global29
            local.get 5
            global.set $dynrt_global23
            local.get 6
            global.set $dynrt_global24
            local.get 7
            global.set $dynrt_global26
            local.get 8
            global.set $dynrt_global27
          end
        end
      end
    end)
  (func $dynrt__fn175 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32)
    call $dynrt_dynArray
    local.set 2
    local.get 0
    local.get 1
    call $dynrt__fn144
    i32.const 40
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_global19
        i32.const 1
        i32.add
        global.set $dynrt_global19
        local.get 0
        local.get 1
        call $dynrt__fn143
        local.get 0
        local.get 1
        call $dynrt__fn144
        i32.const 41
        i32.eq
        if  ;; label = @3
          global.get $dynrt_global19
          i32.const 1
          i32.add
          global.set $dynrt_global19
        else
          block  ;; label = @4
            i32.const 1
            local.set 3
            block  ;; label = @5
              loop  ;; label = @6
                block  ;; label = @7
                  local.get 3
                  i32.const 1
                  i32.eq
                  i32.eqz
                  br_if 2 (;@5;)
                  block  ;; label = @8
                    local.get 0
                    local.get 1
                    call $dynrt__fn143
                    local.get 0
                    local.get 1
                    call $dynrt__fn161
                    global.get $dynrt_global1
                    local.set 4
                    global.get $dynrt_global2
                    local.set 5
                    local.get 2
                    local.get 4
                    local.get 5
                    call $dynrt_dynString
                    call $dynrt_dynPush
                    local.get 0
                    local.get 1
                    call $dynrt__fn143
                    local.get 0
                    local.get 1
                    call $dynrt__fn144
                    local.set 4
                    local.get 4
                    i32.const 44
                    i32.eq
                    if  ;; label = @9
                      global.get $dynrt_global19
                      i32.const 1
                      i32.add
                      global.set $dynrt_global19
                    else
                      block  ;; label = @10
                        local.get 4
                        i32.const 41
                        i32.eq
                        if  ;; label = @11
                          global.get $dynrt_global19
                          i32.const 1
                          i32.add
                          global.set $dynrt_global19
                        end
                        i32.const 0
                        local.set 3
                      end
                    end
                  end
                  br 1 (;@6;)
                end
              end
            end
          end
        end
      end
    end
    local.get 2
    return)
  (func $dynrt__fn176 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    global.get $dynrt_global19
    local.tee 12
    i32.const 1
    local.tee 13
    i32.add
    global.set $dynrt_global19
    global.get $dynrt_global19
    local.tee 14
    local.set 2
    i32.const 1
    local.tee 15
    local.set 3
    i32.const 0
    local.tee 16
    local.set 4
    local.get 16
    local.set 5
    local.get 15
    local.set 6
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 6
          i32.const 1
          i32.eq
          if (result i32)  ;; label = @4
            global.get $dynrt_global19
            local.get 1
            i32.lt_s
          else
            i32.const 0
          end
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 0
            local.get 1
            global.get $dynrt_global19
            call $dynrt__fn8
            local.set 7
            local.get 4
            i32.const 1
            i32.eq
            if  ;; label = @5
              local.get 7
              i32.const 92
              i32.eq
              if  ;; label = @6
                global.get $dynrt_global19
                i32.const 2
                i32.add
                global.set $dynrt_global19
              else
                local.get 7
                local.get 5
                i32.eq
                if  ;; label = @7
                  block  ;; label = @8
                    i32.const 0
                    local.set 4
                    global.get $dynrt_global19
                    i32.const 1
                    i32.add
                    global.set $dynrt_global19
                  end
                else
                  global.get $dynrt_global19
                  i32.const 1
                  i32.add
                  global.set $dynrt_global19
                end
              end
            else
              local.get 7
              i32.const 39
              i32.eq
              if (result i32)  ;; label = @6
                i32.const 1
              else
                local.get 7
                i32.const 34
                i32.eq
              end
              if  ;; label = @6
                block  ;; label = @7
                  i32.const 1
                  local.tee 8
                  local.set 4
                  local.get 7
                  local.set 5
                  global.get $dynrt_global19
                  i32.const 1
                  local.tee 9
                  i32.add
                  global.set $dynrt_global19
                end
              else
                local.get 7
                i32.const 123
                i32.eq
                if  ;; label = @7
                  block  ;; label = @8
                    local.get 3
                    i32.const 1
                    local.tee 10
                    i32.add
                    local.set 3
                    global.get $dynrt_global19
                    i32.const 1
                    local.tee 11
                    i32.add
                    global.set $dynrt_global19
                  end
                else
                  local.get 7
                  i32.const 125
                  i32.eq
                  if  ;; label = @8
                    block  ;; label = @9
                      local.get 3
                      i32.const 1
                      i32.sub
                      local.set 3
                      local.get 3
                      i32.eqz
                      if  ;; label = @10
                        i32.const 0
                        local.set 6
                      else
                        global.get $dynrt_global19
                        i32.const 1
                        i32.add
                        global.set $dynrt_global19
                      end
                    end
                  else
                    global.get $dynrt_global19
                    i32.const 1
                    i32.add
                    global.set $dynrt_global19
                  end
                end
              end
            end
          end
          br 1 (;@2;)
        end
      end
    end
    local.get 0
    local.get 1
    local.get 2
    global.get $dynrt_global19
    call $dynrt__fn5
    local.set 3
    nop
    local.set 2
    local.get 0
    local.get 1
    call $dynrt__fn144
    i32.const 125
    i32.eq
    if  ;; label = @1
      global.get $dynrt_global19
      i32.const 1
      i32.add
      global.set $dynrt_global19
    end
    local.get 2
    local.get 3
    call $dynrt_dynString
    return)
  (func $dynrt__fn177 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt__fn143
    local.get 0
    local.get 1
    call $dynrt__fn144
    i32.const 123
    i32.eq
    if  ;; label = @1
      local.get 0
      local.get 1
      call $dynrt__fn176
      return
    end
    global.get $dynrt_global19
    local.tee 4
    local.set 2
    global.get $dynrt_global21
    local.set 3
    i32.const 0
    global.set $dynrt_global21
    local.get 0
    local.get 1
    call $dynrt__fn158
    drop
    local.get 3
    global.set $dynrt_global21
    nop
    local.get 0
    local.get 1
    local.get 2
    global.get $dynrt_global19
    call $dynrt__fn5
    call $dynrt_dynString
    return)
  (func $dynrt__fn178 (param i32 i32) (result i32)
    (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt__fn143
    local.get 0
    local.get 1
    call $dynrt__fn144
    i32.const 0
    call $dynrt__fn142
    i32.const 1
    i32.eq
    if  ;; label = @1
      local.get 0
      local.get 1
      call $dynrt__fn161
    end
    local.get 0
    local.get 1
    call $dynrt__fn143
    local.get 0
    local.get 1
    call $dynrt__fn175
    local.set 2
    local.get 0
    local.get 1
    call $dynrt__fn143
    i32.const 534
    i32.const 0
    call $dynrt_dynString
    local.set 3
    local.get 0
    local.get 1
    call $dynrt__fn144
    i32.const 123
    i32.eq
    if  ;; label = @1
      local.get 0
      local.get 1
      call $dynrt__fn176
      local.set 3
    end
    local.get 2
    local.get 3
    global.get $dynrt_global20
    call $dynrt__fn121
    return)
  (func $dynrt__fn179 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    global.get $dynrt_global19
    local.set 2
    i32.const 0
    local.tee 14
    local.set 3
    local.get 14
    local.set 4
    local.get 14
    local.set 5
    i32.const 1
    local.set 6
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 6
          i32.const 1
          i32.eq
          if (result i32)  ;; label = @4
            global.get $dynrt_global19
            local.get 1
            i32.lt_s
          else
            i32.const 0
          end
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 0
            local.get 1
            global.get $dynrt_global19
            call $dynrt__fn8
            local.set 7
            local.get 4
            i32.const 1
            i32.eq
            if  ;; label = @5
              local.get 7
              i32.const 92
              i32.eq
              if  ;; label = @6
                global.get $dynrt_global19
                i32.const 2
                i32.add
                global.set $dynrt_global19
              else
                local.get 7
                local.get 5
                i32.eq
                if  ;; label = @7
                  block  ;; label = @8
                    i32.const 0
                    local.set 4
                    global.get $dynrt_global19
                    i32.const 1
                    i32.add
                    global.set $dynrt_global19
                  end
                else
                  global.get $dynrt_global19
                  i32.const 1
                  i32.add
                  global.set $dynrt_global19
                end
              end
            else
              local.get 7
              i32.const 39
              i32.eq
              if (result i32)  ;; label = @6
                i32.const 1
              else
                local.get 7
                i32.const 34
                i32.eq
              end
              if  ;; label = @6
                block  ;; label = @7
                  i32.const 1
                  local.tee 8
                  local.set 4
                  local.get 7
                  local.set 5
                  global.get $dynrt_global19
                  i32.const 1
                  local.tee 9
                  i32.add
                  global.set $dynrt_global19
                end
              else
                local.get 7
                i32.const 40
                i32.eq
                if  ;; label = @7
                  block  ;; label = @8
                    local.get 3
                    i32.const 1
                    local.tee 10
                    i32.add
                    local.set 3
                    global.get $dynrt_global19
                    i32.const 1
                    local.tee 11
                    i32.add
                    global.set $dynrt_global19
                  end
                else
                  local.get 7
                  i32.const 41
                  i32.eq
                  if  ;; label = @8
                    block  ;; label = @9
                      local.get 3
                      i32.const 1
                      local.tee 12
                      i32.sub
                      local.set 3
                      global.get $dynrt_global19
                      i32.const 1
                      local.tee 13
                      i32.add
                      global.set $dynrt_global19
                      local.get 3
                      i32.eqz
                      if  ;; label = @10
                        i32.const 0
                        local.set 6
                      end
                    end
                  else
                    global.get $dynrt_global19
                    i32.const 1
                    i32.add
                    global.set $dynrt_global19
                  end
                end
              end
            end
          end
          br 1 (;@2;)
        end
      end
    end
    local.get 0
    local.get 1
    call $dynrt__fn143
    i32.const 0
    local.tee 15
    local.set 3
    local.get 0
    local.get 1
    call $dynrt__fn144
    i32.const 61
    i32.eq
    if (result i32)  ;; label = @1
      local.get 0
      local.get 1
      call $dynrt__fn145
      i32.const 62
      i32.eq
    else
      i32.const 0
    end
    if  ;; label = @1
      i32.const 1
      local.set 3
    end
    local.get 2
    global.set $dynrt_global19
    local.get 3
    return)
  (func $dynrt__fn180 (param i32 i32)
    (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt__fn143
    local.get 0
    local.get 1
    call $dynrt__fn161
    global.get $dynrt_global1
    local.set 2
    global.get $dynrt_global2
    local.set 3
    local.get 0
    local.get 1
    call $dynrt__fn143
    local.get 0
    local.get 1
    call $dynrt__fn175
    local.set 4
    local.get 0
    local.get 1
    call $dynrt__fn143
    i32.const 534
    i32.const 0
    call $dynrt_dynString
    local.set 5
    local.get 0
    local.get 1
    call $dynrt__fn144
    i32.const 123
    i32.eq
    if  ;; label = @1
      local.get 0
      local.get 1
      call $dynrt__fn176
      local.set 5
    end
    local.get 4
    local.get 5
    global.get $dynrt_global20
    call $dynrt__fn121
    local.set 4
    global.get $dynrt_global21
    i32.const 1
    i32.eq
    if  ;; label = @1
      global.get $dynrt_global20
      local.get 2
      local.get 3
      local.get 4
      call $dynrt_dynSet
    end)
  (func $dynrt__fn181 (param i32 i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt__fn143
    local.get 0
    local.get 1
    call $dynrt__fn161
    global.get $dynrt_global1
    local.set 2
    global.get $dynrt_global2
    local.set 3
    local.get 0
    local.get 1
    call $dynrt__fn143
    i32.const -1
    local.tee 29
    local.set 4
    local.get 29
    local.set 5
    local.get 0
    local.get 1
    call $dynrt__fn144
    i32.const 0
    call $dynrt__fn142
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 0
        local.get 1
        call $dynrt__fn161
        global.get $dynrt_global1
        local.set 6
        global.get $dynrt_global2
        local.set 7
        local.get 6
        local.get 7
        i32.const 1068
        i32.const 7
        call $dynrt__fn138
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt__fn143
            local.get 0
            local.get 1
            call $dynrt__fn161
            global.get $dynrt_global1
            local.set 6
            global.get $dynrt_global2
            local.set 7
            global.get $dynrt_global20
            i32.const -1
            i32.eq
            if (result i32)  ;; label = @5
              i32.const -1
            else
              global.get $dynrt_global20
              local.get 6
              local.get 7
              call $dynrt__fn125
            end
            local.set 6
            local.get 6
            i32.const -1
            i32.ne
            if  ;; label = @5
              block  ;; label = @6
                local.get 6
                local.tee 20
                local.set 4
                local.get 6
                i32.const 1075
                i32.const 7
                call $dynrt_dynGet
                local.set 6
                local.get 6
                i32.const -1
                i32.ne
                if  ;; label = @7
                  local.get 6
                  local.set 5
                end
              end
            end
            local.get 0
            local.get 1
            call $dynrt__fn143
          end
        end
      end
    end
    call $dynrt_dynObject
    local.set 6
    local.get 5
    i32.const -1
    i32.ne
    if  ;; label = @1
      block  ;; label = @2
        local.get 6
        local.set 7
        local.get 7
        i32.const 8
        i32.add
        i32.const 8
        i32.add
        local.get 5
        i32.store
      end
    end
    call $dynrt_dynObject
    local.set 7
    global.get $dynrt_global20
    call $dynrt__fn126
    local.set 8
    local.get 5
    i32.const -1
    i32.ne
    if  ;; label = @1
      local.get 8
      i32.const 983
      i32.const 12
      local.get 5
      call $dynrt_dynSet
    end
    local.get 4
    i32.const -1
    i32.ne
    if  ;; label = @1
      local.get 8
      i32.const 965
      i32.const 12
      local.get 4
      call $dynrt_dynSet
    end
    i32.const 534
    local.tee 30
    local.set 5
    i32.const 0
    local.tee 31
    local.set 9
    i32.const -1
    local.tee 32
    local.set 10
    local.get 30
    local.set 11
    local.get 31
    local.set 12
    local.get 0
    local.get 1
    call $dynrt__fn144
    i32.const 123
    i32.eq
    if  ;; label = @1
      global.get $dynrt_global19
      i32.const 1
      i32.add
      global.set $dynrt_global19
    end
    local.get 0
    local.get 1
    call $dynrt__fn143
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 0
          local.get 1
          call $dynrt__fn144
          i32.const 125
          i32.ne
          if (result i32)  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt__fn144
            i32.const -1
            i32.ne
          else
            i32.const 0
          end
          i32.eqz
          br_if 2 (;@1;)
          local.get 0
          local.get 1
          call $dynrt__fn144
          i32.const 59
          i32.eq
          if  ;; label = @4
            block  ;; label = @5
              global.get $dynrt_global19
              i32.const 1
              i32.add
              global.set $dynrt_global19
              local.get 0
              local.get 1
              call $dynrt__fn143
            end
          else
            block  ;; label = @5
              i32.const 0
              local.tee 25
              local.set 13
              local.get 25
              local.set 14
              local.get 0
              local.get 1
              call $dynrt__fn161
              global.get $dynrt_global1
              local.set 15
              global.get $dynrt_global2
              local.set 16
              local.get 0
              local.get 1
              call $dynrt__fn143
              local.get 15
              local.get 16
              i32.const 1082
              i32.const 6
              call $dynrt__fn138
              i32.const 1
              i32.eq
              if (result i32)  ;; label = @6
                local.get 0
                local.get 1
                call $dynrt__fn144
                i32.const 0
                call $dynrt__fn142
                i32.const 1
                i32.eq
              else
                i32.const 0
              end
              if  ;; label = @6
                block  ;; label = @7
                  i32.const 1
                  local.set 13
                  local.get 0
                  local.get 1
                  call $dynrt__fn161
                  global.get $dynrt_global1
                  local.set 15
                  global.get $dynrt_global2
                  local.set 16
                  local.get 0
                  local.get 1
                  call $dynrt__fn143
                end
              end
              local.get 15
              local.get 16
              i32.const 865
              i32.const 3
              call $dynrt__fn138
              i32.const 1
              i32.eq
              if (result i32)  ;; label = @6
                local.get 0
                local.get 1
                call $dynrt__fn144
                i32.const 0
                call $dynrt__fn142
                i32.const 1
                i32.eq
              else
                i32.const 0
              end
              if  ;; label = @6
                block  ;; label = @7
                  i32.const 1
                  local.set 14
                  local.get 0
                  local.get 1
                  call $dynrt__fn161
                  global.get $dynrt_global1
                  local.set 15
                  global.get $dynrt_global2
                  local.set 16
                  local.get 0
                  local.get 1
                  call $dynrt__fn143
                end
              else
                local.get 15
                local.get 16
                i32.const 862
                i32.const 3
                call $dynrt__fn138
                i32.const 1
                i32.eq
                if (result i32)  ;; label = @7
                  local.get 0
                  local.get 1
                  call $dynrt__fn144
                  i32.const 0
                  call $dynrt__fn142
                  i32.const 1
                  i32.eq
                else
                  i32.const 0
                end
                if  ;; label = @7
                  block  ;; label = @8
                    i32.const 2
                    local.set 14
                    local.get 0
                    local.get 1
                    call $dynrt__fn161
                    global.get $dynrt_global1
                    local.set 15
                    global.get $dynrt_global2
                    local.set 16
                    local.get 0
                    local.get 1
                    call $dynrt__fn143
                  end
                end
              end
              local.get 0
              local.get 1
              call $dynrt__fn144
              local.set 17
              local.get 17
              i32.const 40
              i32.eq
              if  ;; label = @6
                block  ;; label = @7
                  local.get 0
                  local.get 1
                  call $dynrt__fn175
                  local.set 17
                  local.get 0
                  local.get 1
                  call $dynrt__fn143
                  local.get 0
                  local.get 1
                  call $dynrt__fn176
                  local.set 18
                  local.get 15
                  local.get 16
                  i32.const 1088
                  i32.const 11
                  call $dynrt__fn138
                  i32.const 1
                  i32.eq
                  if  ;; label = @8
                    block  ;; label = @9
                      local.get 17
                      local.set 10
                      local.get 18
                      call $dynrt__fn78
                      global.get $dynrt_global1
                      local.set 5
                      global.get $dynrt_global2
                      local.set 9
                    end
                  else
                    block  ;; label = @9
                      local.get 17
                      local.get 18
                      local.get 8
                      call $dynrt__fn121
                      local.set 17
                      local.get 15
                      local.set 18
                      local.get 16
                      local.set 19
                      local.get 14
                      i32.const 1
                      i32.eq
                      if  ;; label = @10
                        block  ;; label = @11
                          i32.const 894
                          local.set 18
                          i32.const 6
                          local.set 19
                          local.get 18
                          local.get 19
                          local.get 15
                          local.get 16
                          call $dynrt__fn4
                          local.set 19
                          nop
                          local.set 18
                        end
                      else
                        local.get 14
                        i32.const 2
                        i32.eq
                        if  ;; label = @11
                          block  ;; label = @12
                            i32.const 906
                            local.set 18
                            i32.const 6
                            local.set 19
                            local.get 18
                            local.get 19
                            local.get 15
                            local.get 16
                            call $dynrt__fn4
                            local.set 19
                            nop
                            local.set 18
                          end
                        end
                      end
                      local.get 13
                      i32.const 1
                      i32.eq
                      if  ;; label = @10
                        local.get 7
                        local.get 18
                        local.get 19
                        local.get 17
                        call $dynrt_dynSet
                      else
                        local.get 6
                        local.get 18
                        local.get 19
                        local.get 17
                        call $dynrt_dynSet
                      end
                    end
                  end
                end
              else
                block  ;; label = @7
                  local.get 13
                  i32.const 1
                  i32.eq
                  if  ;; label = @8
                    block  ;; label = @9
                      call $dynrt_dynUndefined
                      local.set 13
                      local.get 17
                      i32.const 61
                      i32.eq
                      if  ;; label = @10
                        block  ;; label = @11
                          global.get $dynrt_global19
                          i32.const 1
                          i32.add
                          global.set $dynrt_global19
                          local.get 0
                          local.get 1
                          call $dynrt__fn158
                          local.set 13
                        end
                      end
                      global.get $dynrt_global21
                      i32.const 1
                      i32.eq
                      if  ;; label = @10
                        local.get 7
                        local.get 15
                        local.get 16
                        local.get 13
                        call $dynrt_dynSet
                      end
                    end
                  else
                    block  ;; label = @9
                      i32.const 547
                      local.set 13
                      i32.const 9
                      local.set 14
                      local.get 17
                      i32.const 61
                      i32.eq
                      if  ;; label = @10
                        block  ;; label = @11
                          global.get $dynrt_global19
                          local.tee 21
                          i32.const 1
                          i32.add
                          global.set $dynrt_global19
                          local.get 0
                          local.get 1
                          call $dynrt__fn143
                          global.get $dynrt_global19
                          local.tee 22
                          local.set 13
                          global.get $dynrt_global21
                          local.set 14
                          i32.const 0
                          global.set $dynrt_global21
                          local.get 0
                          local.get 1
                          call $dynrt__fn158
                          drop
                          local.get 14
                          global.set $dynrt_global21
                          local.get 0
                          local.get 1
                          local.get 13
                          global.get $dynrt_global19
                          call $dynrt__fn5
                          local.set 14
                          nop
                          local.set 13
                        end
                      end
                      local.get 11
                      local.tee 23
                      local.set 11
                      local.get 12
                      local.tee 24
                      local.set 12
                      local.get 11
                      local.get 12
                      i32.const 1099
                      i32.const 5
                      call $dynrt__fn4
                      local.set 12
                      nop
                      local.set 11
                      local.get 11
                      local.get 12
                      local.get 15
                      local.get 16
                      call $dynrt__fn4
                      local.set 12
                      nop
                      local.set 11
                      local.get 11
                      local.get 12
                      i32.const 1104
                      i32.const 3
                      call $dynrt__fn4
                      local.set 12
                      nop
                      local.set 11
                      local.get 11
                      local.get 12
                      local.get 13
                      local.get 14
                      call $dynrt__fn4
                      local.set 12
                      nop
                      local.set 11
                      local.get 11
                      local.get 12
                      i32.const 1107
                      i32.const 2
                      call $dynrt__fn4
                      local.set 12
                      nop
                      local.set 11
                    end
                  end
                  local.get 0
                  local.get 1
                  call $dynrt__fn143
                  local.get 0
                  local.get 1
                  call $dynrt__fn144
                  i32.const 59
                  i32.eq
                  if  ;; label = @8
                    global.get $dynrt_global19
                    i32.const 1
                    i32.add
                    global.set $dynrt_global19
                  end
                end
              end
              local.get 0
              local.get 1
              call $dynrt__fn143
            end
          end
          br 1 (;@2;)
        end
      end
    end
    local.get 0
    local.get 1
    call $dynrt__fn144
    i32.const 125
    i32.eq
    if  ;; label = @1
      global.get $dynrt_global19
      i32.const 1
      i32.add
      global.set $dynrt_global19
    end
    local.get 12
    i32.const 0
    i32.gt_s
    if (result i32)  ;; label = @1
      i32.const 1
    else
      local.get 9
      i32.const 0
      i32.gt_s
    end
    if (result i32)  ;; label = @1
      i32.const 1
    else
      local.get 10
      i32.const -1
      i32.ne
    end
    if  ;; label = @1
      block  ;; label = @2
        local.get 10
        local.tee 26
        local.set 10
        local.get 10
        i32.const -1
        i32.eq
        if  ;; label = @3
          call $dynrt_dynArray
          local.set 10
        end
        local.get 11
        local.tee 27
        local.set 11
        local.get 12
        local.tee 28
        local.set 12
        local.get 11
        local.get 12
        local.get 5
        local.get 9
        call $dynrt__fn4
        local.set 12
        nop
        local.set 11
        local.get 10
        local.get 11
        local.get 12
        call $dynrt_dynString
        local.get 8
        call $dynrt__fn121
        local.set 5
        local.get 7
        i32.const 977
        i32.const 6
        local.get 5
        call $dynrt_dynSet
      end
    end
    local.get 7
    i32.const 1075
    i32.const 7
    local.get 6
    call $dynrt_dynSet
    local.get 4
    i32.const -1
    i32.ne
    if  ;; label = @1
      local.get 7
      i32.const 965
      i32.const 12
      local.get 4
      call $dynrt_dynSet
    end
    global.get $dynrt_global21
    i32.const 1
    i32.eq
    if  ;; label = @1
      global.get $dynrt_global20
      local.get 2
      local.get 3
      local.get 7
      call $dynrt_dynSet
    end)
  (func $dynrt__fn182 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.tee 5
    local.set 2
    local.get 2
    i32.const 8
    i32.add
    i32.load
    i32.const 6
    i32.ne
    if  ;; label = @1
      call $dynrt_dynUndefined
      return
    end
    call $dynrt_dynObject
    local.set 2
    local.get 0
    i32.const 1075
    i32.const 7
    call $dynrt_dynGet
    local.set 3
    local.get 3
    i32.const -1
    i32.ne
    if  ;; label = @1
      block  ;; label = @2
        local.get 2
        local.set 4
        local.get 4
        i32.const 8
        i32.add
        i32.const 8
        i32.add
        local.get 3
        i32.store
      end
    end
    local.get 0
    i32.const 977
    i32.const 6
    call $dynrt_dynGet
    local.set 3
    local.get 3
    i32.const -1
    i32.ne
    if  ;; label = @1
      block  ;; label = @2
        local.get 3
        local.set 4
        local.get 4
        i32.const 8
        i32.add
        i32.load
        i32.const 7
        i32.eq
        if  ;; label = @3
          local.get 3
          local.get 1
          local.get 2
          call $dynrt__fn130
          drop
        end
      end
    end
    local.get 2
    return)
  (func $dynrt__fn183 (param i32 i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt__fn143
    local.get 0
    local.get 1
    call $dynrt__fn144
    local.set 2
    local.get 2
    i32.const 123
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_global19
        i32.const 1
        i32.add
        global.set $dynrt_global19
        global.get $dynrt_global20
        local.set 2
        local.get 2
        call $dynrt__fn126
        local.set 3
        local.get 3
        local.tee 14
        global.set $dynrt_global20
        local.get 3
        call $dynrt__fn54
        local.get 0
        local.get 1
        call $dynrt__fn184
        call $dynrt__fn55
        local.get 2
        local.tee 15
        global.set $dynrt_global20
        local.get 0
        local.get 1
        call $dynrt__fn143
        local.get 0
        local.get 1
        call $dynrt__fn144
        i32.const 125
        i32.eq
        if  ;; label = @3
          global.get $dynrt_global19
          i32.const 1
          i32.add
          global.set $dynrt_global19
        end
        return
      end
    end
    local.get 2
    i32.const 59
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_global19
        i32.const 1
        i32.add
        global.set $dynrt_global19
        return
      end
    end
    local.get 2
    i32.const 0
    call $dynrt__fn142
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_global19
        local.set 2
        local.get 0
        local.get 1
        call $dynrt__fn161
        global.get $dynrt_global1
        local.set 3
        global.get $dynrt_global2
        local.set 4
        local.get 3
        local.get 4
        i32.const 1035
        i32.const 3
        call $dynrt__fn138
        i32.const 1
        i32.eq
        if (result i32)  ;; label = @3
          i32.const 1
        else
          local.get 3
          local.get 4
          i32.const 1030
          i32.const 5
          call $dynrt__fn138
          i32.const 1
          i32.eq
        end
        if (result i32)  ;; label = @3
          i32.const 1
        else
          local.get 3
          local.get 4
          i32.const 1038
          i32.const 3
          call $dynrt__fn138
          i32.const 1
          i32.eq
        end
        if  ;; label = @3
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt__fn162
            return
          end
        end
        local.get 3
        local.get 4
        i32.const 1109
        i32.const 2
        call $dynrt__fn138
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt__fn164
            return
          end
        end
        local.get 3
        local.get 4
        i32.const 1111
        i32.const 5
        call $dynrt__fn138
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt__fn165
            return
          end
        end
        local.get 3
        local.get 4
        i32.const 1116
        i32.const 2
        call $dynrt__fn138
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt__fn166
            return
          end
        end
        local.get 3
        local.get 4
        i32.const 1118
        i32.const 3
        call $dynrt__fn138
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt__fn167
            return
          end
        end
        local.get 3
        local.get 4
        i32.const 1121
        i32.const 6
        call $dynrt__fn138
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt__fn171
            return
          end
        end
        local.get 3
        local.get 4
        i32.const 1127
        i32.const 3
        call $dynrt__fn138
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt__fn174
            return
          end
        end
        local.get 3
        local.get 4
        i32.const 1130
        i32.const 5
        call $dynrt__fn138
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt__fn158
            local.set 2
            global.get $dynrt_global21
            i32.const 1
            i32.eq
            if  ;; label = @5
              block  ;; label = @6
                i32.const 1
                global.set $dynrt_global28
                local.get 2
                global.set $dynrt_global29
              end
            end
            local.get 0
            local.get 1
            call $dynrt__fn143
            local.get 0
            local.get 1
            call $dynrt__fn144
            i32.const 59
            i32.eq
            if  ;; label = @5
              global.get $dynrt_global19
              i32.const 1
              i32.add
              global.set $dynrt_global19
            end
            return
          end
        end
        local.get 3
        local.get 4
        i32.const 1135
        i32.const 6
        call $dynrt__fn138
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt__fn163
            return
          end
        end
        local.get 3
        local.get 4
        i32.const 912
        i32.const 8
        call $dynrt__fn138
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt__fn180
            return
          end
        end
        local.get 3
        local.get 4
        i32.const 1141
        i32.const 5
        call $dynrt__fn138
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt__fn181
            return
          end
        end
        local.get 3
        local.get 4
        i32.const 1146
        i32.const 5
        call $dynrt__fn138
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            global.get $dynrt_global21
            i32.const 1
            i32.eq
            if  ;; label = @5
              i32.const 1
              global.set $dynrt_global26
            end
            local.get 0
            local.get 1
            call $dynrt__fn143
            local.get 0
            local.get 1
            call $dynrt__fn144
            i32.const 59
            i32.eq
            if  ;; label = @5
              global.get $dynrt_global19
              i32.const 1
              i32.add
              global.set $dynrt_global19
            end
            return
          end
        end
        local.get 3
        local.get 4
        i32.const 1151
        i32.const 8
        call $dynrt__fn138
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            global.get $dynrt_global21
            i32.const 1
            i32.eq
            if  ;; label = @5
              i32.const 1
              global.set $dynrt_global27
            end
            local.get 0
            local.get 1
            call $dynrt__fn143
            local.get 0
            local.get 1
            call $dynrt__fn144
            i32.const 59
            i32.eq
            if  ;; label = @5
              global.get $dynrt_global19
              i32.const 1
              i32.add
              global.set $dynrt_global19
            end
            return
          end
        end
        local.get 0
        local.get 1
        call $dynrt__fn143
        local.get 0
        local.get 1
        call $dynrt__fn144
        local.set 5
        local.get 5
        i32.const 61
        i32.eq
        if (result i32)  ;; label = @3
          local.get 0
          local.get 1
          call $dynrt__fn145
          i32.const 61
          i32.ne
        else
          i32.const 0
        end
        if (result i32)  ;; label = @3
          local.get 0
          local.get 1
          call $dynrt__fn145
          i32.const 62
          i32.ne
        else
          i32.const 0
        end
        if  ;; label = @3
          block  ;; label = @4
            global.get $dynrt_global19
            i32.const 1
            i32.add
            global.set $dynrt_global19
            local.get 0
            local.get 1
            call $dynrt__fn158
            local.set 2
            global.get $dynrt_global21
            i32.const 1
            i32.eq
            if  ;; label = @5
              global.get $dynrt_global20
              local.get 3
              local.get 4
              local.get 2
              call $dynrt__fn127
            end
            local.get 0
            local.get 1
            call $dynrt__fn143
            local.get 0
            local.get 1
            call $dynrt__fn144
            i32.const 59
            i32.eq
            if  ;; label = @5
              global.get $dynrt_global19
              i32.const 1
              i32.add
              global.set $dynrt_global19
            end
            return
          end
        end
        local.get 5
        i32.const 43
        i32.eq
        if (result i32)  ;; label = @3
          local.get 0
          local.get 1
          call $dynrt__fn145
          i32.const 43
          i32.eq
        else
          i32.const 0
        end
        if  ;; label = @3
          block  ;; label = @4
            global.get $dynrt_global19
            i32.const 2
            i32.add
            global.set $dynrt_global19
            global.get $dynrt_global21
            i32.const 1
            i32.eq
            if  ;; label = @5
              block  ;; label = @6
                global.get $dynrt_global20
                local.get 3
                local.get 4
                call $dynrt__fn125
                local.set 5
                global.get $dynrt_global20
                local.get 3
                local.get 4
                local.get 5
                f64.const 0x1.0p+0 (;=1;)
                call $dynrt_dynNumber
                call $dynrt_dynAdd
                call $dynrt__fn127
              end
            end
            local.get 0
            local.get 1
            call $dynrt__fn143
            local.get 0
            local.get 1
            call $dynrt__fn144
            i32.const 59
            i32.eq
            if  ;; label = @5
              global.get $dynrt_global19
              i32.const 1
              i32.add
              global.set $dynrt_global19
            end
            return
          end
        end
        local.get 5
        i32.const 45
        i32.eq
        if (result i32)  ;; label = @3
          local.get 0
          local.get 1
          call $dynrt__fn145
          i32.const 45
          i32.eq
        else
          i32.const 0
        end
        if  ;; label = @3
          block  ;; label = @4
            global.get $dynrt_global19
            i32.const 2
            i32.add
            global.set $dynrt_global19
            global.get $dynrt_global21
            i32.const 1
            i32.eq
            if  ;; label = @5
              block  ;; label = @6
                global.get $dynrt_global20
                local.get 3
                local.get 4
                call $dynrt__fn125
                local.set 5
                global.get $dynrt_global20
                local.get 3
                local.get 4
                local.get 5
                f64.const 0x1.0p+0 (;=1;)
                call $dynrt_dynNumber
                call $dynrt_dynSub
                call $dynrt__fn127
              end
            end
            local.get 0
            local.get 1
            call $dynrt__fn143
            local.get 0
            local.get 1
            call $dynrt__fn144
            i32.const 59
            i32.eq
            if  ;; label = @5
              global.get $dynrt_global19
              i32.const 1
              i32.add
              global.set $dynrt_global19
            end
            return
          end
        end
        local.get 5
        i32.const 43
        i32.eq
        if (result i32)  ;; label = @3
          i32.const 1
        else
          local.get 5
          i32.const 45
          i32.eq
        end
        if (result i32)  ;; label = @3
          i32.const 1
        else
          local.get 5
          i32.const 42
          i32.eq
        end
        if (result i32)  ;; label = @3
          i32.const 1
        else
          local.get 5
          i32.const 47
          i32.eq
        end
        if (result i32)  ;; label = @3
          local.get 0
          local.get 1
          call $dynrt__fn145
          i32.const 61
          i32.eq
        else
          i32.const 0
        end
        if  ;; label = @3
          block  ;; label = @4
            local.get 5
            local.set 2
            global.get $dynrt_global19
            i32.const 2
            i32.add
            global.set $dynrt_global19
            local.get 0
            local.get 1
            call $dynrt__fn158
            local.set 6
            global.get $dynrt_global21
            i32.const 1
            i32.eq
            if  ;; label = @5
              block  ;; label = @6
                global.get $dynrt_global20
                local.get 3
                local.get 4
                call $dynrt__fn125
                local.set 5
                local.get 5
                local.tee 16
                drop
                local.get 2
                i32.const 43
                i32.eq
                if  ;; label = @7
                  local.get 5
                  local.get 6
                  call $dynrt_dynAdd
                  local.set 5
                else
                  local.get 2
                  i32.const 45
                  i32.eq
                  if  ;; label = @8
                    local.get 5
                    local.get 6
                    call $dynrt_dynSub
                    local.set 5
                  else
                    local.get 2
                    i32.const 42
                    i32.eq
                    if  ;; label = @9
                      local.get 5
                      local.get 6
                      call $dynrt_dynMul
                      local.set 5
                    else
                      local.get 5
                      local.get 6
                      call $dynrt_dynDiv
                      local.set 5
                    end
                  end
                end
                global.get $dynrt_global20
                local.get 3
                local.get 4
                local.get 5
                call $dynrt__fn127
              end
            end
            local.get 0
            local.get 1
            call $dynrt__fn143
            local.get 0
            local.get 1
            call $dynrt__fn144
            i32.const 59
            i32.eq
            if  ;; label = @5
              global.get $dynrt_global19
              i32.const 1
              i32.add
              global.set $dynrt_global19
            end
            return
          end
        end
        local.get 5
        i32.const 46
        i32.eq
        if (result i32)  ;; label = @3
          i32.const 1
        else
          local.get 5
          i32.const 91
          i32.eq
        end
        if  ;; label = @3
          block  ;; label = @4
            global.get $dynrt_global20
            i32.const -1
            i32.eq
            if (result i32)  ;; label = @5
              call $dynrt_dynUndefined
            else
              global.get $dynrt_global20
              local.get 3
              local.get 4
              call $dynrt__fn125
            end
            local.set 3
            local.get 3
            i32.const -1
            i32.eq
            if  ;; label = @5
              call $dynrt_dynUndefined
              local.set 3
            end
            i32.const 0
            local.set 4
            i32.const 1
            local.set 5
            block  ;; label = @5
              loop  ;; label = @6
                block  ;; label = @7
                  local.get 5
                  i32.const 1
                  i32.eq
                  i32.eqz
                  br_if 2 (;@5;)
                  block  ;; label = @8
                    local.get 0
                    local.get 1
                    call $dynrt__fn143
                    local.get 0
                    local.get 1
                    call $dynrt__fn144
                    local.set 6
                    i32.const 0
                    local.tee 19
                    local.set 7
                    i32.const 534
                    local.set 8
                    local.get 19
                    local.set 9
                    local.get 19
                    local.set 10
                    local.get 6
                    i32.const 46
                    i32.eq
                    if  ;; label = @9
                      block  ;; label = @10
                        global.get $dynrt_global19
                        i32.const 1
                        local.tee 17
                        i32.add
                        global.set $dynrt_global19
                        local.get 0
                        local.get 1
                        call $dynrt__fn161
                        global.get $dynrt_global1
                        local.set 8
                        global.get $dynrt_global2
                        local.set 9
                        i32.const 1
                        local.tee 18
                        local.set 7
                      end
                    else
                      local.get 6
                      i32.const 91
                      i32.eq
                      if  ;; label = @10
                        block  ;; label = @11
                          global.get $dynrt_global19
                          i32.const 1
                          i32.add
                          global.set $dynrt_global19
                          local.get 0
                          local.get 1
                          call $dynrt__fn158
                          local.set 10
                          local.get 0
                          local.get 1
                          call $dynrt__fn143
                          local.get 0
                          local.get 1
                          call $dynrt__fn144
                          i32.const 93
                          i32.eq
                          if  ;; label = @12
                            global.get $dynrt_global19
                            i32.const 1
                            i32.add
                            global.set $dynrt_global19
                          end
                        end
                      else
                        i32.const 0
                        local.set 5
                      end
                    end
                    local.get 5
                    i32.const 1
                    i32.eq
                    if  ;; label = @9
                      block  ;; label = @10
                        local.get 0
                        local.get 1
                        call $dynrt__fn143
                        local.get 0
                        local.get 1
                        call $dynrt__fn144
                        local.set 11
                        local.get 0
                        local.get 1
                        call $dynrt__fn145
                        local.set 6
                        local.get 11
                        i32.const 61
                        i32.eq
                        if (result i32)  ;; label = @11
                          local.get 6
                          i32.const 61
                          i32.ne
                        else
                          i32.const 0
                        end
                        if (result i32)  ;; label = @11
                          local.get 6
                          i32.const 62
                          i32.ne
                        else
                          i32.const 0
                        end
                        if (result i32)  ;; label = @11
                          i32.const 1
                        else
                          i32.const 0
                        end
                        local.set 12
                        i32.const 0
                        local.set 13
                        local.get 11
                        i32.const 43
                        i32.eq
                        if (result i32)  ;; label = @11
                          i32.const 1
                        else
                          local.get 11
                          i32.const 45
                          i32.eq
                        end
                        if (result i32)  ;; label = @11
                          i32.const 1
                        else
                          local.get 11
                          i32.const 42
                          i32.eq
                        end
                        if (result i32)  ;; label = @11
                          i32.const 1
                        else
                          local.get 11
                          i32.const 47
                          i32.eq
                        end
                        if (result i32)  ;; label = @11
                          local.get 6
                          i32.const 61
                          i32.eq
                        else
                          i32.const 0
                        end
                        if  ;; label = @11
                          i32.const 1
                          local.set 13
                        end
                        local.get 12
                        i32.const 1
                        i32.eq
                        if (result i32)  ;; label = @11
                          i32.const 1
                        else
                          local.get 13
                          i32.const 1
                          i32.eq
                        end
                        if  ;; label = @11
                          block  ;; label = @12
                            local.get 12
                            i32.const 1
                            i32.eq
                            if  ;; label = @13
                              global.get $dynrt_global19
                              i32.const 1
                              i32.add
                              global.set $dynrt_global19
                            else
                              global.get $dynrt_global19
                              i32.const 2
                              i32.add
                              global.set $dynrt_global19
                            end
                            local.get 0
                            local.get 1
                            call $dynrt__fn158
                            local.set 6
                            global.get $dynrt_global21
                            i32.const 1
                            i32.eq
                            if  ;; label = @13
                              block  ;; label = @14
                                local.get 6
                                local.set 5
                                local.get 13
                                i32.const 1
                                i32.eq
                                if  ;; label = @15
                                  block  ;; label = @16
                                    local.get 7
                                    i32.const 1
                                    i32.eq
                                    if  ;; label = @17
                                      local.get 3
                                      local.get 8
                                      local.get 9
                                      call $dynrt_dynMember
                                      local.set 5
                                    else
                                      local.get 3
                                      local.get 10
                                      call $dynrt_dynIndexValue
                                      local.set 5
                                    end
                                    local.get 11
                                    i32.const 43
                                    i32.eq
                                    if  ;; label = @17
                                      local.get 5
                                      local.get 6
                                      call $dynrt_dynAdd
                                      local.set 5
                                    else
                                      local.get 11
                                      i32.const 45
                                      i32.eq
                                      if  ;; label = @18
                                        local.get 5
                                        local.get 6
                                        call $dynrt_dynSub
                                        local.set 5
                                      else
                                        local.get 11
                                        i32.const 42
                                        i32.eq
                                        if  ;; label = @19
                                          local.get 5
                                          local.get 6
                                          call $dynrt_dynMul
                                          local.set 5
                                        else
                                          local.get 5
                                          local.get 6
                                          call $dynrt_dynDiv
                                          local.set 5
                                        end
                                      end
                                    end
                                  end
                                end
                                local.get 7
                                i32.const 1
                                i32.eq
                                if  ;; label = @15
                                  local.get 3
                                  local.get 8
                                  local.get 9
                                  local.get 5
                                  call $dynrt__fn140
                                else
                                  local.get 3
                                  local.get 10
                                  local.get 5
                                  call $dynrt__fn107
                                end
                              end
                            end
                            i32.const 1
                            local.set 4
                            i32.const 0
                            local.set 5
                          end
                        else
                          local.get 7
                          i32.const 1
                          i32.eq
                          if  ;; label = @12
                            local.get 3
                            local.get 8
                            local.get 9
                            call $dynrt_dynMember
                            local.set 3
                          else
                            local.get 3
                            local.get 10
                            call $dynrt_dynIndexValue
                            local.set 3
                          end
                        end
                      end
                    end
                  end
                  br 1 (;@6;)
                end
              end
            end
            local.get 4
            i32.const 1
            i32.eq
            if  ;; label = @5
              block  ;; label = @6
                local.get 0
                local.get 1
                call $dynrt__fn143
                local.get 0
                local.get 1
                call $dynrt__fn144
                i32.const 59
                i32.eq
                if  ;; label = @7
                  global.get $dynrt_global19
                  i32.const 1
                  i32.add
                  global.set $dynrt_global19
                end
                return
              end
            end
            local.get 2
            global.set $dynrt_global19
            local.get 0
            local.get 1
            call $dynrt__fn158
            local.set 2
            global.get $dynrt_global21
            i32.const 1
            i32.eq
            if  ;; label = @5
              local.get 2
              global.set $dynrt_global25
            end
            local.get 0
            local.get 1
            call $dynrt__fn143
            local.get 0
            local.get 1
            call $dynrt__fn144
            i32.const 59
            i32.eq
            if  ;; label = @5
              global.get $dynrt_global19
              i32.const 1
              i32.add
              global.set $dynrt_global19
            end
            return
          end
        end
        local.get 2
        global.set $dynrt_global19
        local.get 0
        local.get 1
        call $dynrt__fn158
        local.set 2
        global.get $dynrt_global21
        i32.const 1
        i32.eq
        if  ;; label = @3
          local.get 2
          global.set $dynrt_global25
        end
        local.get 0
        local.get 1
        call $dynrt__fn143
        local.get 0
        local.get 1
        call $dynrt__fn144
        i32.const 59
        i32.eq
        if  ;; label = @3
          global.get $dynrt_global19
          i32.const 1
          i32.add
          global.set $dynrt_global19
        end
        return
      end
    end
    local.get 0
    local.get 1
    call $dynrt__fn158
    local.set 2
    global.get $dynrt_global21
    i32.const 1
    i32.eq
    if  ;; label = @1
      local.get 2
      global.set $dynrt_global25
    end
    local.get 0
    local.get 1
    call $dynrt__fn143
    local.get 0
    local.get 1
    call $dynrt__fn144
    i32.const 59
    i32.eq
    if  ;; label = @1
      global.get $dynrt_global19
      i32.const 1
      i32.add
      global.set $dynrt_global19
    end)
  (func $dynrt__fn184 (param i32 i32)
    (local i32) (local i32)
    i32.const 1
    local.set 2
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 2
          i32.const 1
          i32.eq
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt__fn143
            local.get 0
            local.get 1
            call $dynrt__fn144
            local.set 3
            local.get 3
            i32.const -1
            i32.eq
            if (result i32)  ;; label = @5
              i32.const 1
            else
              local.get 3
              i32.const 125
              i32.eq
            end
            if  ;; label = @5
              i32.const 0
              local.set 2
            else
              block  ;; label = @6
                call $dynrt__fn66
                global.get $dynrt_global21
                local.set 3
                global.get $dynrt_global23
                i32.const 1
                i32.eq
                if (result i32)  ;; label = @7
                  i32.const 1
                else
                  global.get $dynrt_global26
                  i32.const 1
                  i32.eq
                end
                if (result i32)  ;; label = @7
                  i32.const 1
                else
                  global.get $dynrt_global27
                  i32.const 1
                  i32.eq
                end
                if (result i32)  ;; label = @7
                  i32.const 1
                else
                  global.get $dynrt_global28
                  i32.const 1
                  i32.eq
                end
                if  ;; label = @7
                  i32.const 0
                  global.set $dynrt_global21
                end
                local.get 0
                local.get 1
                call $dynrt__fn183
                local.get 3
                global.set $dynrt_global21
              end
            end
          end
          br 1 (;@2;)
        end
      end
    end)
  (func $dynrt_dynRun (param i32 i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 2
    call $dynrt__fn54
    i32.const 0
    local.tee 4
    global.set $dynrt_global19
    local.get 2
    local.tee 5
    global.set $dynrt_global20
    i32.const 1
    global.set $dynrt_global21
    i32.const 0
    local.tee 6
    global.set $dynrt_global23
    call $dynrt_dynUndefined
    global.set $dynrt_global24
    i32.const 0
    local.tee 7
    global.set $dynrt_global28
    call $dynrt_dynUndefined
    global.set $dynrt_global25
    local.get 0
    local.get 1
    call $dynrt__fn184
    global.get $dynrt_global23
    i32.const 1
    i32.eq
    if (result i32)  ;; label = @1
      global.get $dynrt_global24
    else
      global.get $dynrt_global25
    end
    local.set 3
    call $dynrt__fn55
    local.get 3
    return)
  ;; data from dynrt
  (data (;0;) (i32.const 534) "")
  (data (;1;) (i32.const 534) "false")
  (data (;2;) (i32.const 539) "true")
  (data (;3;) (i32.const 543) "null")
  (data (;4;) (i32.const 547) "undefined")
  (data (;5;) (i32.const 556) "push")
  (data (;6;) (i32.const 560) "indexOf")
  (data (;7;) (i32.const 567) "includes")
  (data (;8;) (i32.const 575) "join")
  (data (;9;) (i32.const 579) ",")
  (data (;10;) (i32.const 580) "slice")
  (data (;11;) (i32.const 585) "concat")
  (data (;12;) (i32.const 591) "reverse")
  (data (;13;) (i32.const 598) "pop")
  (data (;14;) (i32.const 601) "shift")
  (data (;15;) (i32.const 606) "unshift")
  (data (;16;) (i32.const 613) "at")
  (data (;17;) (i32.const 615) "lastIndexOf")
  (data (;18;) (i32.const 626) "map")
  (data (;19;) (i32.const 629) "filter")
  (data (;20;) (i32.const 635) "forEach")
  (data (;21;) (i32.const 642) "reduce")
  (data (;22;) (i32.const 648) "find")
  (data (;23;) (i32.const 652) "findIndex")
  (data (;24;) (i32.const 661) "some")
  (data (;25;) (i32.const 665) "every")
  (data (;26;) (i32.const 670) "sort")
  (data (;27;) (i32.const 674) "charAt")
  (data (;28;) (i32.const 680) "charCodeAt")
  (data (;29;) (i32.const 690) "toUpperCase")
  (data (;30;) (i32.const 701) "toLowerCase")
  (data (;31;) (i32.const 712) "trim")
  (data (;32;) (i32.const 716) "startsWith")
  (data (;33;) (i32.const 726) "endsWith")
  (data (;34;) (i32.const 734) "repeat")
  (data (;35;) (i32.const 740) "padStart")
  (data (;36;) (i32.const 748) " ")
  (data (;37;) (i32.const 749) "padEnd")
  (data (;38;) (i32.const 755) "split")
  (data (;39;) (i32.const 760) "create")
  (data (;40;) (i32.const 766) "keys")
  (data (;41;) (i32.const 770) "values")
  (data (;42;) (i32.const 776) "entries")
  (data (;43;) (i32.const 783) "assign")
  (data (;44;) (i32.const 789) "floor")
  (data (;45;) (i32.const 794) "ceil")
  (data (;46;) (i32.const 798) "round")
  (data (;47;) (i32.const 803) "abs")
  (data (;48;) (i32.const 806) "sqrt")
  (data (;49;) (i32.const 810) "sign")
  (data (;50;) (i32.const 814) "trunc")
  (data (;51;) (i32.const 819) "max")
  (data (;52;) (i32.const 822) "min")
  (data (;53;) (i32.const 825) "pow")
  (data (;54;) (i32.const 828) "\22")
  (data (;55;) (i32.const 829) "\5c\22")
  (data (;56;) (i32.const 831) "\5c\5c")
  (data (;57;) (i32.const 833) "\5cn")
  (data (;58;) (i32.const 835) "\5cr")
  (data (;59;) (i32.const 837) "\5ct")
  (data (;60;) (i32.const 839) "[")
  (data (;61;) (i32.const 840) "]")
  (data (;62;) (i32.const 841) "{")
  (data (;63;) (i32.const 842) ":")
  (data (;64;) (i32.const 843) "}")
  (data (;65;) (i32.const 844) "__mapk")
  (data (;66;) (i32.const 850) "__mapv")
  (data (;67;) (i32.const 856) "__setk")
  (data (;68;) (i32.const 862) "set")
  (data (;69;) (i32.const 865) "get")
  (data (;70;) (i32.const 868) "has")
  (data (;71;) (i32.const 871) "delete")
  (data (;72;) (i32.const 877) "add")
  (data (;73;) (i32.const 880) "this")
  (data (;74;) (i32.const 884) "len")
  (data (;75;) (i32.const 887) "inc")
  (data (;76;) (i32.const 890) "size")
  (data (;77;) (i32.const 894) "__get_")
  (data (;78;) (i32.const 900) "length")
  (data (;79;) (i32.const 906) "__set_")
  (data (;80;) (i32.const 912) "function")
  (data (;81;) (i32.const 920) "Object")
  (data (;82;) (i32.const 926) "Math")
  (data (;83;) (i32.const 930) "PI")
  (data (;84;) (i32.const 932) "E")
  (data (;85;) (i32.const 933) "JSON")
  (data (;86;) (i32.const 937) "parse")
  (data (;87;) (i32.const 942) "stringify")
  (data (;88;) (i32.const 951) "new")
  (data (;89;) (i32.const 954) "Map")
  (data (;90;) (i32.const 957) "Set")
  (data (;91;) (i32.const 960) "super")
  (data (;92;) (i32.const 965) "__superclass")
  (data (;93;) (i32.const 977) "__ctor")
  (data (;94;) (i32.const 983) "__superproto")
  (data (;95;) (i32.const 995) "boolean")
  (data (;96;) (i32.const 1002) "number")
  (data (;97;) (i32.const 1008) "string")
  (data (;98;) (i32.const 1014) "object")
  (data (;99;) (i32.const 1020) "typeof")
  (data (;100;) (i32.const 1026) "else")
  (data (;101;) (i32.const 1030) "const")
  (data (;102;) (i32.const 1035) "let")
  (data (;103;) (i32.const 1038) "var")
  (data (;104;) (i32.const 1041) "of")
  (data (;105;) (i32.const 1043) "in")
  (data (;106;) (i32.const 1045) "case")
  (data (;107;) (i32.const 1049) "default")
  (data (;108;) (i32.const 1056) "catch")
  (data (;109;) (i32.const 1061) "finally")
  (data (;110;) (i32.const 1068) "extends")
  (data (;111;) (i32.const 1075) "__proto")
  (data (;112;) (i32.const 1082) "static")
  (data (;113;) (i32.const 1088) "constructor")
  (data (;114;) (i32.const 1099) "this.")
  (data (;115;) (i32.const 1104) " = ")
  (data (;116;) (i32.const 1107) "; ")
  (data (;117;) (i32.const 1109) "if")
  (data (;118;) (i32.const 1111) "while")
  (data (;119;) (i32.const 1116) "do")
  (data (;120;) (i32.const 1118) "for")
  (data (;121;) (i32.const 1121) "switch")
  (data (;122;) (i32.const 1127) "try")
  (data (;123;) (i32.const 1130) "throw")
  (data (;124;) (i32.const 1135) "return")
  (data (;125;) (i32.const 1141) "class")
  (data (;126;) (i32.const 1146) "break")
  (data (;127;) (i32.const 1151) "continue")
  (export "dynNumber" (func $dynrt_dynNumber))
  (export "dynNumberValue" (func $dynrt_dynNumberValue))
  (export "dynString" (func $dynrt_dynString))
  (export "dynStrBytes" (func $dynrt_dynStrBytes))
  (export "dynStrLen" (func $dynrt_dynStrLen))
  (export "dynBool" (func $dynrt_dynBool))
  (export "dynToBool" (func $dynrt_dynToBool))
  (export "dynTypeof" (func $dynrt_dynTypeof))
  (export "dynTag" (func $dynrt_dynTag))
  (export "dynNull" (func $dynrt_dynNull))
  (export "dynUndefined" (func $dynrt_dynUndefined))
  (export "dynArray" (func $dynrt_dynArray))
  (export "dynArrLen" (func $dynrt_dynArrLen))
  (export "dynArrGet" (func $dynrt_dynArrGet))
  (export "dynPush" (func $dynrt_dynPush))
  (export "dynObject" (func $dynrt_dynObject))
  (export "dynObjLen" (func $dynrt_dynObjLen))
  (export "dynObjKeyPtr" (func $dynrt_dynObjKeyPtr))
  (export "dynObjKeyLen" (func $dynrt_dynObjKeyLen))
  (export "dynObjValAt" (func $dynrt_dynObjValAt))
  (export "dynSet" (func $dynrt_dynSet))
  (export "dynApply" (func $dynrt_dynApply))
  (export "dynGcPin" (func $dynrt_dynGcPin))
  (export "dynGcUnpin" (func $dynrt_dynGcUnpin))
  (export "dynMakeHostFn" (func $dynrt_dynMakeHostFn))
  (export "cabi_realloc" (func $cabi_realloc))
)