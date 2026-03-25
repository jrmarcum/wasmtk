(module
  (type (;0;) (func))
  (type (;1;) (func (param i32 i32 i32 i32) (result i32)))
  (type (;2;) (func (param i32 i32) (result i32)))
  (type (;3;) (func (param i32 i32 i32)))
  (import "wasi_snapshot_preview1" "fd_write" (func (;0;) (type 1)))
  (func (;1;) (type 2) (param i32 i32) (result i32)
    local.get 0
    local.get 1
    i32.mul)
  (func (;2;) (type 3) (param i32 i32 i32)
    local.get 2
    local.get 0
    i32.load
    local.get 1
    i32.load
    i32.add
    i32.store)
  (func (;3;) (type 2) (param i32 i32) (result i32)
    (local i32 i32 i32 i32 i32)
    local.get 1
    i32.const 0
    i32.store
    local.get 1
    i32.const 4
    i32.add
    i32.const 0
    i32.store
    local.get 0
    i32.eqz
    if  ;; label = @1
      local.get 1
      i32.const 48
      i32.store8
      local.get 1
      i32.const 1
      i32.add
      i32.const 0
      i32.store8
      i32.const 1
      return
    end
    i32.const 0
    local.set 4
    block  ;; label = @1
      loop  ;; label = @2
        local.get 0
        i32.eqz
        if  ;; label = @3
          br 2 (;@1;)
        end
        local.get 0
        i32.const 10
        i32.rem_u
        local.set 3
        local.get 1
        local.get 4
        i32.add
        local.get 3
        i32.const 48
        i32.add
        i32.store8
        local.get 0
        i32.const 10
        i32.div_u
        local.set 0
        local.get 4
        i32.const 1
        i32.add
        local.set 4
        local.get 1
        local.get 4
        i32.add
        i32.const 308
        i32.ge_u
        if  ;; label = @3
          local.get 4
          return
        end
        br 0 (;@2;)
      end
      unreachable
    end
    local.get 1
    local.get 4
    i32.add
    i32.const 0
    i32.store8
    i32.const 0
    local.set 5
    local.get 4
    i32.const 1
    i32.sub
    local.set 6
    block  ;; label = @1
      loop  ;; label = @2
        local.get 5
        local.get 6
        i32.ge_s
        if  ;; label = @3
          br 2 (;@1;)
        end
        local.get 1
        local.get 5
        i32.add
        i32.load8_u
        local.set 2
        local.get 1
        local.get 5
        i32.add
        local.get 1
        local.get 6
        i32.add
        i32.load8_u
        i32.store8
        local.get 1
        local.get 6
        i32.add
        local.get 2
        i32.store8
        local.get 5
        i32.const 1
        i32.add
        local.set 5
        local.get 6
        i32.const 1
        i32.sub
        local.set 6
        br 0 (;@2;)
      end
      unreachable
    end
    local.get 4
    return)
  (func (;4;) (type 0)
    (local i32 i32 i32 i32 i32 i32)
    i32.const 1000
    local.set 2
    i32.const 0
    local.set 3
    block  ;; label = @1
      loop  ;; label = @2
        local.get 3
        i32.const 22
        i32.ge_u
        br_if 1 (;@1;)
        local.get 2
        i32.const 100
        local.get 3
        i32.add
        i32.load8_u
        i32.store8
        local.get 2
        i32.const 1
        i32.add
        local.set 2
        local.get 3
        i32.const 1
        i32.add
        local.set 3
        br 0 (;@2;)
      end
      unreachable
    end
    i32.const 12
    i32.const 3
    call 1
    local.set 0
    local.get 0
    i32.const 300
    call 3
    local.set 1
    block  ;; label = @1
      i32.const 0
      local.set 3
      loop  ;; label = @2
        local.get 3
        local.get 1
        i32.ge_u
        br_if 1 (;@1;)
        local.get 2
        i32.const 300
        local.get 3
        i32.add
        i32.load8_u
        i32.store8
        local.get 2
        i32.const 1
        i32.add
        local.set 2
        local.get 3
        i32.const 1
        i32.add
        local.set 3
        br 0 (;@2;)
      end
      unreachable
    end
    local.get 2
    i32.const 160
    i32.load8_u
    i32.store8
    local.get 2
    i32.const 1
    i32.add
    local.set 2
    i32.const 200
    i32.const 1000
    i32.store
    i32.const 204
    local.get 2
    i32.const 1000
    i32.sub
    i32.store
    i32.const 1
    i32.const 200
    i32.const 1
    i32.const 220
    call 0
    drop
    i32.const 1000
    local.set 4
    i32.const 0
    local.set 5
    block  ;; label = @1
      loop  ;; label = @2
        local.get 5
        i32.const 17
        i32.ge_u
        br_if 1 (;@1;)
        local.get 4
        i32.const 130
        local.get 5
        i32.add
        i32.load8_u
        i32.store8
        local.get 4
        i32.const 1
        i32.add
        local.set 4
        local.get 5
        i32.const 1
        i32.add
        local.set 5
        br 0 (;@2;)
      end
      unreachable
    end
    i32.const 0
    i32.const 5
    i32.store
    i32.const 4
    i32.const 7
    i32.store
    i32.const 0
    i32.const 4
    i32.const 8
    call 2
    i32.const 8
    i32.load
    i32.const 300
    call 3
    local.set 1
    block  ;; label = @1
      i32.const 0
      local.set 5
      loop  ;; label = @2
        local.get 5
        local.get 1
        i32.ge_u
        br_if 1 (;@1;)
        local.get 4
        i32.const 300
        local.get 5
        i32.add
        i32.load8_u
        i32.store8
        local.get 4
        i32.const 1
        i32.add
        local.set 4
        local.get 5
        i32.const 1
        i32.add
        local.set 5
        br 0 (;@2;)
      end
      unreachable
    end
    local.get 4
    i32.const 160
    i32.load8_u
    i32.store8
    local.get 4
    i32.const 1
    i32.add
    local.set 4
    i32.const 200
    i32.const 1000
    i32.store
    i32.const 204
    local.get 4
    i32.const 1000
    i32.sub
    i32.store
    i32.const 1
    i32.const 200
    i32.const 1
    i32.const 220
    call 0
    drop)
  (memory (;0;) 1)
  (export "memory" (memory 0))
  (export "_start" (func 4))
  (data (;0;) (i32.const 100) "Multiplication result: ")
  (data (;1;) (i32.const 130) "Addition result: ")
  (data (;2;) (i32.const 160) "\0a")
  (data (;3;) (i32.const 300) "\00\00\00\00\00\00\00\00")
  (data (;4;) (i32.const 1000) "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00"))
