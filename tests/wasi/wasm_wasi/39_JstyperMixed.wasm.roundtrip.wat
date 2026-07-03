(module
  (type (;0;) (func (param i32)))
  (type (;1;) (func (param i32 i32 i32 i32) (result i32)))
  (type (;2;) (func (param i32) (result i32)))
  (type (;3;) (func (param i32 i32) (result i32)))
  (type (;4;) (func (param i32) (result f64)))
  (type (;5;) (func (param f64 i32) (result i32)))
  (type (;6;) (func (param i64 i32) (result i32)))
  (type (;7;) (func (param f64 f64 f64) (result f64)))
  (type (;8;) (func (param f64 f64 f64) (result i32)))
  (type (;9;) (func))
  (import "wasi_snapshot_preview1" "proc_exit" (func (;0;) (param i32)))
  (import "wasi_snapshot_preview1" "fd_write" (func (;1;) (param i32 i32 i32 i32) (result i32)))
  (func (;2;) (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 1
    local.tee 16
    local.set 6
    local.get 16
    local.set 2
    local.get 0
    i32.eqz
    if  ;; label = @1
      block  ;; label = @2
        local.get 1
        i32.const 48
        i32.store8
        i32.const 1
        return
      end
    end
    local.get 0
    i32.const 0
    i32.lt_s
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
        i32.const 0
        local.get 0
        i32.sub
        local.set 0
      end
    end
    local.get 1
    local.tee 17
    local.set 3
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 0
          i32.eqz
          br_if 2 (;@1;)
          local.get 3
          i32.const 48
          local.get 0
          i32.const 10
          i32.rem_u
          i32.add
          i32.store8
          local.get 0
          local.tee 10
          i32.const 10
          local.tee 11
          i32.div_u
          local.set 0
          local.get 3
          local.tee 12
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
    local.tee 18
    i32.const 1
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
          local.tee 13
          i32.const 1
          local.tee 14
          i32.add
          local.set 2
          local.get 4
          local.tee 15
          local.get 14
          i32.sub
          local.set 4
          br 1 (;@2;)
        end
      end
    end
    local.get 3
    local.tee 19
    local.get 6
    i32.sub)
  (func (;3;) (param i32) (result f64)
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
  (func (;4;) (param f64 i32) (result i32)
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
    call 5
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
          call 3
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
  (func (;5;) (param i64 i32) (result i32)
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
  (func (;6;) (param f64 f64 f64) (result f64)
    local.get 0
    local.get 1
    f64.lt
    if  ;; label = @1
      local.get 1
      return
    end
    local.get 0
    local.get 2
    f64.gt
    if  ;; label = @1
      local.get 2
      return
    end
    local.get 0
    return)
  (func (;7;) (param i32) (result i32)
    (local i32) (local i32)
    local.get 0
    i32.eqz
    if  ;; label = @1
      i32.const 1
      return
    end
    i32.const 0
    local.set 1
    local.get 0
    i32.const 0
    i32.lt_s
    if (result i32)  ;; label = @1
      i32.const 0
      local.get 0
      i32.sub
    else
      local.get 0
    end
    local.set 2
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 2
          i32.const 0
          i32.gt_s
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 1
            i32.const 1
            i32.add
            local.set 1
            local.get 2
            i32.const 10
            i32.div_s
            local.set 2
          end
          br 1 (;@2;)
        end
      end
    end
    local.get 1
    return)
  (func (;8;) (param f64 f64 f64) (result i32)
    local.get 0
    local.get 1
    f64.ge
    if (result f64)  ;; label = @1
      local.get 0
      local.get 2
      f64.le
    else
      i32.const 0
    end
    return)
  (func (;9;)
    (local i32)
    i32.const 0
    i32.const 132
    i32.store
    i32.const 4
    f64.const 0x1.4p+2 (;=5;)
    f64.const 0x0p+0 (;=0;)
    f64.const 0x1.8p+1 (;=3;)
    call 6
    i32.const 132
    call 4
    i32.store
    i32.const 132
    i32.const 4
    i32.load
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
    call 1
    drop
    i32.const 0
    i32.const 132
    i32.store
    i32.const 4
    f64.const -0x1.0p+0 (;=-1;)
    f64.const 0x0p+0 (;=0;)
    f64.const 0x1.4p+3 (;=10;)
    call 6
    i32.const 132
    call 4
    i32.store
    i32.const 132
    i32.const 4
    i32.load
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
    call 1
    drop
    i32.const 0
    i32.const 132
    i32.store
    i32.const 4
    f64.const 0x1.cp+2 (;=7;)
    f64.const 0x0p+0 (;=0;)
    f64.const 0x1.4p+3 (;=10;)
    call 6
    i32.const 132
    call 4
    i32.store
    i32.const 132
    i32.const 4
    i32.load
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
    call 1
    drop
    i32.const 0
    i32.const 132
    i32.store
    i32.const 4
    i32.const 0
    call 7
    i32.const 132
    call 2
    i32.store
    i32.const 132
    i32.const 4
    i32.load
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
    call 1
    drop
    i32.const 0
    i32.const 132
    i32.store
    i32.const 4
    i32.const 12345
    call 7
    i32.const 132
    call 2
    i32.store
    i32.const 132
    i32.const 4
    i32.load
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
    call 1
    drop
    i32.const 0
    i32.const 132
    i32.store
    i32.const 4
    i32.const 9
    call 7
    i32.const 132
    call 2
    i32.store
    i32.const 132
    i32.const 4
    i32.load
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
    call 1
    drop
    i32.const 0
    f64.const 0x1.4p+2 (;=5;)
    f64.const 0x0p+0 (;=0;)
    f64.const 0x1.4p+3 (;=10;)
    call 8
    if (result i32)  ;; label = @1
      i32.const 260
    else
      i32.const 264
    end
    i32.store
    i32.const 4
    f64.const 0x1.4p+2 (;=5;)
    f64.const 0x0p+0 (;=0;)
    f64.const 0x1.4p+3 (;=10;)
    call 8
    if (result i32)  ;; label = @1
      i32.const 4
    else
      i32.const 5
    end
    i32.store
    i32.const 8
    i32.const 269
    i32.store
    i32.const 12
    i32.const 1
    i32.store
    i32.const 1
    i32.const 0
    i32.const 2
    i32.const 128
    call 1
    drop
    i32.const 0
    f64.const 0x1.ep+3 (;=15;)
    f64.const 0x0p+0 (;=0;)
    f64.const 0x1.4p+3 (;=10;)
    call 8
    if (result i32)  ;; label = @1
      i32.const 260
    else
      i32.const 264
    end
    i32.store
    i32.const 4
    f64.const 0x1.ep+3 (;=15;)
    f64.const 0x0p+0 (;=0;)
    f64.const 0x1.4p+3 (;=10;)
    call 8
    if (result i32)  ;; label = @1
      i32.const 4
    else
      i32.const 5
    end
    i32.store
    i32.const 8
    i32.const 269
    i32.store
    i32.const 12
    i32.const 1
    i32.store
    i32.const 1
    i32.const 0
    i32.const 2
    i32.const 128
    call 1
    drop
    i32.const 0
    call 0)
  (memory (;0;) 2)
  (export "memory" (memory 0))
  (export "_start" (func 9))
  (data (;0;) (i32.const 260) "true")
  (data (;1;) (i32.const 264) "false")
  (data (;2;) (i32.const 269) "\0a"))
