(module
  (type (;0;) (func))
  (type (;1;) (func (param i32 i32 i32 i32) (result i32)))
  (type (;2;) (func (param i32)))
  (type (;3;) (func (param i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_write" (func (;0;) (type 1)))
  (import "wasi_snapshot_preview1" "proc_exit" (func (;1;) (type 2)))
  (func (;2;) (type 3) (param i32 i32) (result i32)
    local.get 0
    local.get 1
    i32.mul
    i32.const 1
    i32.shr_s
    i32.const 3
    i32.mul)
  (func (;3;) (type 0)
    i32.const 0
    i32.const 260
    i32.store
    i32.const 4
    i32.const 29
    i32.store
    i32.const 1
    i32.const 0
    i32.const 1
    i32.const 128
    call 0
    drop)
  (func (;4;) (type 0)
    (local i32 i32 i32 i32)
    i32.const 0
    i32.const 550
    i32.store
    i32.const 4
    i32.const 40
    i32.store
    i32.const 1
    i32.const 0
    i32.const 1
    i32.const 128
    call 0
    drop
    i32.const 0
    i32.const 132
    i32.store
    i32.const 4
    i32.const 0
    i32.store
    i32.const 132
    i32.const 83
    i32.store8
    i32.const 133
    i32.const 99
    i32.store8
    i32.const 134
    i32.const 97
    i32.store8
    i32.const 135
    i32.const 108
    i32.store8
    i32.const 136
    i32.const 101
    i32.store8
    i32.const 137
    i32.const 100
    i32.store8
    i32.const 138
    i32.const 32
    i32.store8
    i32.const 139
    i32.const 65
    i32.store8
    i32.const 140
    i32.const 114
    i32.store8
    i32.const 141
    i32.const 101
    i32.store8
    i32.const 142
    i32.const 97
    i32.store8
    i32.const 143
    i32.const 32
    i32.store8
    i32.const 144
    i32.const 82
    i32.store8
    i32.const 145
    i32.const 101
    i32.store8
    i32.const 146
    i32.const 115
    i32.store8
    i32.const 147
    i32.const 117
    i32.store8
    i32.const 148
    i32.const 108
    i32.store8
    i32.const 149
    i32.const 116
    i32.store8
    i32.const 150
    i32.const 58
    i32.store8
    i32.const 151
    i32.const 32
    i32.store8
    i32.const 60
    local.set 0
    i32.const 152
    local.set 1
    i32.const 152
    local.set 2
    loop  ;; label = @1
      local.get 0
      if  ;; label = @2
        local.get 2
        local.get 0
        i32.const 10
        i32.rem_u
        i32.const 48
        i32.add
        i32.store8
        local.get 0
        i32.const 10
        i32.div_u
        local.set 0
        local.get 2
        i32.const 1
        i32.add
        local.set 2
        br 1 (;@1;)
      end
    end
    local.get 2
    i32.const 1
    i32.sub
    local.set 0
    loop  ;; label = @1
      local.get 0
      local.get 1
      i32.gt_u
      if  ;; label = @2
        local.get 1
        i32.load8_u
        local.set 3
        local.get 1
        local.get 0
        i32.load8_u
        i32.store8
        local.get 0
        local.get 3
        i32.store8
        local.get 1
        i32.const 1
        i32.add
        local.set 1
        local.get 0
        i32.const 1
        i32.sub
        local.set 0
        br 1 (;@1;)
      end
    end
    i32.const 4
    local.get 2
    i32.const 132
    i32.sub
    i32.store
    i32.const 4
    i32.load
    i32.const 132
    i32.add
    i32.const 10
    i32.store8
    i32.const 4
    i32.const 4
    i32.load
    i32.const 1
    i32.add
    i32.store
    i32.const 1
    i32.const 0
    i32.const 1
    i32.const 128
    call 0
    drop
    i32.const 0
    i32.const 590
    i32.store
    i32.const 4
    i32.const 46
    i32.store
    i32.const 1
    i32.const 0
    i32.const 1
    i32.const 128
    call 0
    drop
    i32.const 0
    i32.const 896
    i32.store
    i32.const 4
    i32.const 29
    i32.store
    i32.const 1
    i32.const 0
    i32.const 1
    i32.const 128
    call 0
    drop
    i32.const 0
    call 1)
  (memory (;0;) 1)
  (export "computeScaledArea" (func 2))
  (export "logLibraryVersion" (func 3))
  (export "_start" (func 4))
  (data (;0;) (i32.const 260) "Library Version: v1.8.0-core\0a")
  (data (;1;) (i32.const 550) "--- Test 1: Static Function Linkage ---\0a")
  (data (;2;) (i32.const 590) "--- Test 2: Shifted Data Segment Pointers ---\0a")
  (data (;3;) (i32.const 896) "Library Version: v1.8.0-core\0a"))
