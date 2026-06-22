(module
  (memory (export "memory") 2)
  (global $__heap_ptr (mut i32) (i32.const 644))
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












































































































  (func $identity (export "identity") (param $x i32) (result i32)
    (return (local.get $x))
  )

  (func $addOne (export "addOne") (param $x i32) (result i32)
    (local $n f64)
    (local.set $n (call $dynrt_dynNumberValue (local.get $x)))
    (return (call $dynrt_dynNumber (f64.add (local.get $n) (f64.const 1))))
  )

  (func $typeName (export "typeName") (param $x i32) (result i32)
    (local $t i32)
    (local.set $t (call $dynrt_dynTypeof (local.get $x)))
    (if (i32.eq (local.get $t) (i32.const 3))
      (then
      (return (call $dynrt_dynString (i32.const 260) (i32.const 6)))
      )
    )
    (if (i32.eq (local.get $t) (i32.const 4))
      (then
      (return (call $dynrt_dynString (i32.const 266) (i32.const 6)))
      )
    )
    (if (i32.eq (local.get $t) (i32.const 2))
      (then
      (return (call $dynrt_dynString (i32.const 272) (i32.const 7)))
      )
    )
    (return (call $dynrt_dynString (i32.const 279) (i32.const 5)))
  )

  (func $exclaim (export "exclaim") (param $s i32) (result i32)
    (return (call $dynrt_dynAdd (local.get $s) (call $dynrt_dynString (i32.const 284) (i32.const 1))))
  )

  (func $makePoint (export "makePoint") (param $a f64) (param $b f64) (result i32)
    (local $o i32)
    (local.set $o (call $dynrt_dynObject ))
    (call $dynrt_dynSet (local.get $o) (i32.const 285) (i32.const 1) (call $dynrt_dynNumber (local.get $a)))
    (call $dynrt_dynSet (local.get $o) (i32.const 286) (i32.const 1) (call $dynrt_dynNumber (local.get $b)))
    (return (local.get $o))
  )

  (func $triple (export "triple") (param $a f64) (param $b f64) (param $c f64) (result i32)
    (local $arr i32)
    (local.set $arr (call $dynrt_dynArray ))
    (call $dynrt_dynPush (local.get $arr) (call $dynrt_dynNumber (local.get $a)))
    (call $dynrt_dynPush (local.get $arr) (call $dynrt_dynNumber (local.get $b)))
    (call $dynrt_dynPush (local.get $arr) (call $dynrt_dynNumber (local.get $c)))
    (return (local.get $arr))
  )

  (func $sumArr (export "sumArr") (param $arr i32) (result i32)
    (local $len i32)
    (local $s f64)
    (local $i i32)
    (local $e i32)
    (local.set $len (call $dynrt_dynArrLen (local.get $arr)))
    (local.set $s (f64.const 0))
    (local.set $i (i32.const 0))
    (block $break_0
      (loop $loop_0
        (br_if $break_0 (i32.eqz (i32.lt_s (local.get $i) (local.get $len))))
        (block $cont_0
          (local.set $e (call $dynrt_dynArrGet (local.get $arr) (local.get $i)))
          (local.set $s (f64.add (local.get $s) (call $dynrt_dynNumberValue (local.get $e))))
          (local.set $i (i32.add (local.get $i) (i32.const 1)))
        )
        (br $loop_0)
      )
    )
    (return (call $dynrt_dynNumber (local.get $s)))
  )

  (func $getX (export "getX") (param $o i32) (result i32)
    (return (call $dynrt_dynMember (local.get $o) (i32.const 285) (i32.const 1)))
  )
  (data (i32.const 260) "\6e\75\6d\62\65\72")
  (data (i32.const 266) "\73\74\72\69\6e\67")
  (data (i32.const 272) "\62\6f\6f\6c\65\61\6e")
  (data (i32.const 279) "\6f\74\68\65\72")
  (data (i32.const 284) "\21")
  (data (i32.const 285) "\78")
  (data (i32.const 286) "\79")

  ;; globals from dynrt
  (global $dynrt_global1 (mut i32) (i32.const 131072))
  (global $dynrt_global2 (mut i32) (i32.const 131072))
  (global $dynrt_global3 i32 (i32.const 4))
  (global $dynrt_global4 (mut i32) (i32.const 131072))
  (global $dynrt_global5 (mut i32) (i32.const -1))
  (global $dynrt_global6 (mut i32) (i32.const 131072))
  (global $dynrt_global7 (mut i32) (i32.const 131072))
  (global $dynrt_global8 (mut i32) (i32.const 131072))
  (global $dynrt_global9 (mut i32) (i32.const 131072))
  (global $dynrt_global10 (mut i32) (i32.const 131072))
  ;; functions from dynrt
  (func $dynrt_cabi_realloc (param i32 i32 i32 i32) (result i32)
    local.get 3
    call $__malloc
    local.get 0
    local.get 0
    i32.eqz
    select)
  (func $dynrt__fn2 (param i32 i32 i32 i32) (result i32 i32)
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
  (func $dynrt__fn3 (param i32 i32 i32 i32) (result i32 i32)
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
  (func $dynrt__fn4 (param i32 i32 i32) (result i32)
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
  (func $dynrt__fn5 (param i32) (result f64)
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
  (func $dynrt__fn6 (param f64 i32) (result i32)
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
    call $dynrt__fn7
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
          call $dynrt__fn5
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
  (func $dynrt__fn7 (param i64 i32) (result i32)
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
  (func $dynrt__fn8 (param i32 i32) (result f64)
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
    i32.const 24
    call $__malloc
    local.set 0
    local.get 0
    i32.const 4
    i32.store
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
    i32.const 24
    call $__malloc
    local.set 0
    local.get 0
    i32.const 4
    i32.store
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
    i32.const 24
    call $__malloc
    local.set 1
    local.get 1
    i32.const 4
    i32.store
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
    call $__malloc
    local.set 1
    local.get 1
    i32.const 1
    i32.store
    local.get 1
    i32.const 8
    i32.add
    local.get 0
    f64.store
    i32.const 24
    call $__malloc
    local.set 2
    local.get 2
    i32.const 4
    i32.store
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
    call $__malloc
    local.set 3
    local.get 3
    local.get 2
    i32.store
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
            call $dynrt__fn4
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
    i32.const 24
    call $__malloc
    local.set 4
    local.get 4
    i32.const 4
    i32.store
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
  (func $dynrt__fn14 (result i32)
    (local i32) (local i32)
    i32.const 8
    global.get $dynrt_global3
    i32.const 2
    i32.add
    i32.const 2
    i32.shl
    i32.add
    call $__malloc
    local.set 0
    local.get 0
    global.get $dynrt_global3
    i32.const 2
    i32.add
    i32.store
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
  (func $dynrt__fn15 (param i32) (result i32)
    (local i32)
    local.get 0
    local.set 1
    local.get 1
    i32.const 8
    i32.add
    i32.load
    return)
  (func $dynrt__fn16 (param i32 i32) (result i32)
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
  (func $dynrt__fn17 (param i32 i32 i32)
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
  (func $dynrt__fn18 (param i32 i32) (result i32)
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
        i32.const 2
        i32.shl
        i32.add
        call $__malloc
        local.set 5
        local.get 5
        local.get 4
        i32.const 2
        i32.add
        i32.store
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
  (func $dynrt_dynArray (result i32)
    (local i32) (local i32)
    i32.const 24
    call $__malloc
    local.set 0
    local.get 0
    i32.const 4
    i32.store
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
    call $dynrt__fn14
    i32.store
    local.get 0
    local.tee 1
    return)
  (func $dynrt_dynObject (result i32)
    (local i32) (local i32)
    i32.const 24
    call $__malloc
    local.set 0
    local.get 0
    i32.const 4
    i32.store
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
    call $dynrt__fn14
    i32.store
    local.get 0
    i32.const 8
    i32.add
    i32.const 12
    i32.add
    call $dynrt__fn14
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
  (func $dynrt__fn30 (param i32)
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
    i32.const 547
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
            call $dynrt__fn2
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
  (func $dynrt__fn31 (param i32)
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
        call $dynrt__fn30
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
        call $dynrt__fn6
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
            i32.const 547
            local.set 1
            i32.const 5
            local.set 2
          end
        else
          block  ;; label = @4
            i32.const 552
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
        i32.const 556
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
        i32.const 560
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
    i32.const 547
    local.set 1
    i32.const 0
    local.set 2
    local.get 1
    local.tee 6
    global.set $dynrt_global1
    local.get 2
    global.set $dynrt_global2
    return)
  (func $dynrt__fn32 (param i32 i32 i32) (result i32)
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
    call $dynrt__fn15
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
            call $dynrt__fn16
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
                call $dynrt__fn16
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
                      call $dynrt__fn4
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
    call $dynrt__fn32
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
        call $dynrt__fn17
        return
      end
    end
    local.get 2
    local.tee 10
    local.set 5
    i32.const 8
    local.get 5
    i32.add
    call $__malloc
    local.set 6
    local.get 6
    local.get 5
    i32.store
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
            call $dynrt__fn4
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
    call $dynrt__fn18
    local.set 7
    local.get 7
    local.get 5
    call $dynrt__fn18
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
    call $dynrt__fn18
    i32.store)
  (func $dynrt_dynGet (param i32 i32 i32) (result i32)
    (local i32) (local i32) (local i32)
    local.get 0
    local.tee 5
    local.set 3
    local.get 0
    local.get 1
    local.get 2
    call $dynrt__fn32
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
    call $dynrt__fn16
    return)
  (func $dynrt_dynHas (param i32 i32 i32) (result i32)
    local.get 0
    local.get 1
    local.get 2
    call $dynrt__fn32
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
    call $dynrt__fn15
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
    call $dynrt__fn16
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
    call $dynrt__fn16
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
    call $dynrt__fn16
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
    call $dynrt__fn18
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
    call $dynrt__fn15
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
    call $dynrt__fn16
    return)
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
        call $dynrt__fn31
        global.get $dynrt_global1
        local.tee 8
        local.set 2
        global.get $dynrt_global2
        local.tee 9
        local.set 3
        local.get 1
        call $dynrt__fn31
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
        call $dynrt__fn2
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
    i32.const 24
    call $__malloc
    local.set 1
    local.get 1
    i32.const 4
    i32.store
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
  (func $dynrt__fn56 (param i32 i32 i32) (result i32)
    (local i32) (local i32)
    i32.const 28
    call $__malloc
    local.set 3
    local.get 3
    i32.const 5
    i32.store
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
    call $dynrt__fn56
    return)
  (func $dynrt__fn58 (param i32 i32 i32) (result i32)
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
  (func $dynrt_dynApply (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local f64) (local f64) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.set 2
    local.get 2
    i32.const 8
    i32.add
    i32.load
    i32.const 7
    i32.ne
    if  ;; label = @1
      call $dynrt_dynUndefined
      return
    end
    local.get 2
    i32.const 8
    i32.add
    i32.const 4
    i32.add
    i32.load
    local.set 3
    local.get 1
    call $dynrt_dynArrLen
    local.set 4
    local.get 3
    i32.const -1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 2
        i32.const 8
        i32.add
        i32.const 8
        i32.add
        i32.load
        local.set 3
        local.get 2
        i32.const 8
        i32.add
        i32.const 12
        i32.add
        i32.load
        local.set 5
        local.get 2
        i32.const 8
        i32.add
        i32.const 16
        i32.add
        i32.load
        local.set 2
        call $dynrt_dynObject
        local.set 6
        local.get 6
        local.tee 14
        local.set 7
        local.get 7
        i32.const 8
        i32.add
        i32.const 8
        i32.add
        local.get 2
        i32.store
        local.get 5
        call $dynrt_dynArrLen
        local.set 2
        i32.const 0
        local.set 7
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 7
              local.get 2
              i32.lt_s
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                local.get 5
                local.get 7
                call $dynrt_dynArrGet
                local.set 8
                local.get 8
                call $dynrt__fn30
                global.get $dynrt_global1
                local.set 8
                global.get $dynrt_global2
                local.set 9
                local.get 7
                local.get 4
                i32.lt_s
                if (result i32)  ;; label = @7
                  local.get 1
                  local.get 7
                  call $dynrt_dynArrGet
                else
                  call $dynrt_dynUndefined
                end
                local.set 10
                local.get 6
                local.get 8
                local.get 9
                local.get 10
                call $dynrt_dynSet
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
        local.get 3
        call $dynrt__fn30
        global.get $dynrt_global1
        local.set 2
        global.get $dynrt_global2
        local.set 3
        global.get $dynrt_global4
        local.set 4
        global.get $dynrt_global5
        local.set 5
        global.get $dynrt_global6
        local.set 7
        global.get $dynrt_global8
        local.set 8
        global.get $dynrt_global9
        local.set 9
        global.get $dynrt_global10
        local.set 10
        local.get 2
        local.get 3
        local.get 6
        call $dynrt_dynRun
        local.set 2
        local.get 4
        global.set $dynrt_global4
        local.get 5
        local.tee 15
        global.set $dynrt_global5
        local.get 7
        local.tee 16
        global.set $dynrt_global6
        local.get 8
        global.set $dynrt_global8
        local.get 9
        global.set $dynrt_global9
        local.get 10
        global.set $dynrt_global10
        local.get 2
        local.tee 17
        return
      end
    end
    local.get 3
    i32.const 8
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_global7
        local.tee 18
        i32.const 1
        i32.add
        global.set $dynrt_global7
        global.get $dynrt_global7
        local.tee 19
        local.set 2
        local.get 2
        f64.convert_i32_s
        call $dynrt_dynNumber
        return
      end
    end
    local.get 4
    i32.const 0
    i32.gt_s
    if (result i32)  ;; label = @1
      local.get 1
      i32.const 0
      call $dynrt_dynArrGet
    else
      call $dynrt_dynUndefined
    end
    local.set 2
    local.get 3
    i32.const 7
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 2
        call $dynrt_dynTag
        local.set 3
        local.get 3
        i32.const 4
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 2
            local.tee 20
            local.set 2
            local.get 2
            i32.const 8
            i32.add
            i32.const 8
            i32.add
            i32.load
            local.set 2
            local.get 2
            f64.convert_i32_s
            call $dynrt_dynNumber
            return
          end
        end
        local.get 3
        i32.const 5
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 2
            call $dynrt_dynArrLen
            local.set 2
            local.get 2
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
    local.get 2
    call $dynrt_dynToNumber
    local.set 11
    local.get 3
    i32.eqz
    if  ;; label = @1
      local.get 11
      f64.abs
      call $dynrt_dynNumber
      return
    end
    local.get 3
    i32.const 1
    i32.eq
    if  ;; label = @1
      local.get 11
      f64.sqrt
      call $dynrt_dynNumber
      return
    end
    local.get 3
    i32.const 2
    i32.eq
    if  ;; label = @1
      local.get 11
      f64.floor
      call $dynrt_dynNumber
      return
    end
    local.get 3
    i32.const 3
    i32.eq
    if  ;; label = @1
      local.get 11
      f64.ceil
      call $dynrt_dynNumber
      return
    end
    local.get 3
    i32.const 4
    i32.eq
    if  ;; label = @1
      local.get 11
      f64.const 0x1.0p-1 (;=0.5;)
      f64.add
      f64.floor
      call $dynrt_dynNumber
      return
    end
    local.get 4
    i32.const 1
    i32.gt_s
    if (result i32)  ;; label = @1
      local.get 1
      i32.const 1
      call $dynrt_dynArrGet
    else
      call $dynrt_dynUndefined
    end
    local.set 2
    local.get 2
    call $dynrt_dynToNumber
    local.set 12
    local.get 3
    i32.const 5
    i32.eq
    if  ;; label = @1
      local.get 11
      local.get 12
      f64.lt
      if (result f64)  ;; label = @2
        local.get 11
      else
        local.get 12
      end
      call $dynrt_dynNumber
      return
    end
    local.get 3
    i32.const 6
    i32.eq
    if  ;; label = @1
      local.get 11
      local.get 12
      f64.gt
      if (result f64)  ;; label = @2
        local.get 11
      else
        local.get 12
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
    i32.const 569
    i32.const 3
    i32.const 0
    call $dynrt_dynBuiltin
    call $dynrt_dynSet
    local.get 0
    i32.const 572
    i32.const 4
    i32.const 1
    call $dynrt_dynBuiltin
    call $dynrt_dynSet
    local.get 0
    i32.const 576
    i32.const 5
    i32.const 2
    call $dynrt_dynBuiltin
    call $dynrt_dynSet
    local.get 0
    i32.const 581
    i32.const 4
    i32.const 3
    call $dynrt_dynBuiltin
    call $dynrt_dynSet
    local.get 0
    i32.const 585
    i32.const 5
    i32.const 4
    call $dynrt_dynBuiltin
    call $dynrt_dynSet
    local.get 0
    i32.const 590
    i32.const 3
    i32.const 5
    call $dynrt_dynBuiltin
    call $dynrt_dynSet
    local.get 0
    i32.const 593
    i32.const 3
    i32.const 6
    call $dynrt_dynBuiltin
    call $dynrt_dynSet
    local.get 0
    i32.const 596
    i32.const 3
    i32.const 7
    call $dynrt_dynBuiltin
    call $dynrt_dynSet
    local.get 0
    i32.const 599
    i32.const 3
    i32.const 8
    call $dynrt_dynBuiltin
    call $dynrt_dynSet
    local.get 0
    local.tee 1
    return)
  (func $dynrt_dynSideEffectCount (result i32)
    global.get $dynrt_global7
    return)
  (func $dynrt_dynResetSideEffects
    i32.const 0
    global.set $dynrt_global7)
  (func $dynrt__fn67 (param i32 i32 i32 i32) (result i32)
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
            call $dynrt__fn4
            local.get 2
            local.get 3
            local.get 4
            call $dynrt__fn4
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
    (local i32) (local i32)
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
        local.get 1
        local.get 2
        call $dynrt_dynGet
        local.set 3
        local.get 3
        i32.const -1
        i32.eq
        if (result i32)  ;; label = @3
          call $dynrt_dynUndefined
        else
          local.get 3
        end
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
        i32.const 602
        i32.const 6
        call $dynrt__fn67
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
        i32.const 602
        i32.const 6
        call $dynrt__fn67
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
            call $dynrt__fn30
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
  (func $dynrt__fn70 (param i32 i32) (result i32)
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
  (func $dynrt__fn71 (param i32 i32)
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
          global.get $dynrt_global4
          local.get 1
          i32.ge_s
          if  ;; label = @4
            i32.const 0
            local.set 2
          else
            block  ;; label = @5
              local.get 0
              local.get 1
              global.get $dynrt_global4
              call $dynrt__fn4
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
                global.get $dynrt_global4
                i32.const 1
                i32.add
                global.set $dynrt_global4
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
  (func $dynrt__fn72 (param i32 i32) (result i32)
    (local i32)
    global.get $dynrt_global4
    local.get 1
    i32.ge_s
    if  ;; label = @1
      i32.const -1
      return
    end
    local.get 0
    local.get 1
    global.get $dynrt_global4
    call $dynrt__fn4
    return)
  (func $dynrt__fn73 (param i32 i32) (result i32)
    (local i32)
    global.get $dynrt_global4
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
    global.get $dynrt_global4
    i32.const 1
    i32.add
    call $dynrt__fn4
    return)
  (func $dynrt__fn74 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32)
    global.get $dynrt_global4
    local.tee 4
    local.set 2
    local.get 0
    local.get 1
    call $dynrt__fn72
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
            global.get $dynrt_global4
            i32.const 1
            i32.add
            global.set $dynrt_global4
            local.get 0
            local.get 1
            call $dynrt__fn72
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
        global.get $dynrt_global4
        i32.const 1
        i32.add
        global.set $dynrt_global4
        local.get 0
        local.get 1
        call $dynrt__fn72
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
                global.get $dynrt_global4
                i32.const 1
                i32.add
                global.set $dynrt_global4
                local.get 0
                local.get 1
                call $dynrt__fn72
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
        global.get $dynrt_global4
        i32.const 1
        i32.add
        global.set $dynrt_global4
        local.get 0
        local.get 1
        call $dynrt__fn72
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
            global.get $dynrt_global4
            i32.const 1
            i32.add
            global.set $dynrt_global4
            local.get 0
            local.get 1
            call $dynrt__fn72
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
                global.get $dynrt_global4
                i32.const 1
                i32.add
                global.set $dynrt_global4
                local.get 0
                local.get 1
                call $dynrt__fn72
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
    global.get $dynrt_global4
    call $dynrt__fn3
    local.set 3
    nop
    local.set 2
    local.get 2
    local.get 3
    call $dynrt__fn8
    call $dynrt_dynNumber
    return)
  (func $dynrt__fn75 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt__fn72
    local.set 2
    global.get $dynrt_global4
    i32.const 1
    local.tee 16
    i32.add
    global.set $dynrt_global4
    i32.const 547
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
          global.get $dynrt_global4
          local.get 1
          i32.ge_s
          if  ;; label = @4
            i32.const 0
            local.set 5
          else
            block  ;; label = @5
              local.get 0
              local.get 1
              global.get $dynrt_global4
              call $dynrt__fn4
              local.set 6
              local.get 6
              local.get 2
              i32.eq
              if  ;; label = @6
                block  ;; label = @7
                  global.get $dynrt_global4
                  i32.const 1
                  i32.add
                  global.set $dynrt_global4
                  i32.const 0
                  local.set 5
                end
              else
                local.get 6
                i32.const 92
                i32.eq
                if  ;; label = @7
                  block  ;; label = @8
                    global.get $dynrt_global4
                    i32.const 1
                    i32.add
                    local.tee 9
                    global.set $dynrt_global4
                    local.get 0
                    local.get 1
                    global.get $dynrt_global4
                    call $dynrt__fn4
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
                    call $dynrt__fn2
                    local.set 4
                    nop
                    local.set 3
                    global.get $dynrt_global4
                    i32.const 1
                    i32.add
                    local.tee 12
                    global.set $dynrt_global4
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
                    call $dynrt__fn2
                    local.set 4
                    nop
                    local.set 3
                    global.get $dynrt_global4
                    i32.const 1
                    local.tee 15
                    i32.add
                    global.set $dynrt_global4
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
  (func $dynrt__fn76 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt__fn71
    local.get 0
    local.get 1
    call $dynrt__fn72
    local.set 2
    local.get 2
    i32.const 40
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_global4
        i32.const 1
        i32.add
        global.set $dynrt_global4
        local.get 0
        local.get 1
        call $dynrt__fn85
        local.set 2
        local.get 0
        local.get 1
        call $dynrt__fn71
        local.get 0
        local.get 1
        call $dynrt__fn72
        i32.const 41
        i32.eq
        if  ;; label = @3
          global.get $dynrt_global4
          i32.const 1
          i32.add
          global.set $dynrt_global4
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
      call $dynrt__fn75
      return
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
      call $dynrt__fn74
      return
    end
    local.get 2
    i32.const 46
    i32.eq
    if  ;; label = @1
      local.get 0
      local.get 1
      call $dynrt__fn74
      return
    end
    local.get 2
    i32.const 0
    call $dynrt__fn70
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_global4
        local.tee 4
        local.set 3
        local.get 2
        local.tee 5
        local.set 2
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 2
              i32.const 1
              call $dynrt__fn70
              i32.const 1
              i32.eq
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                global.get $dynrt_global4
                i32.const 1
                i32.add
                global.set $dynrt_global4
                local.get 0
                local.get 1
                call $dynrt__fn72
                local.set 2
              end
              br 1 (;@4;)
            end
          end
        end
        local.get 0
        local.get 1
        local.get 3
        global.get $dynrt_global4
        call $dynrt__fn3
        local.set 3
        nop
        local.set 2
        local.get 2
        local.get 3
        i32.const 552
        i32.const 4
        call $dynrt__fn67
        i32.const 1
        i32.eq
        if  ;; label = @3
          i32.const 1
          call $dynrt_dynBool
          return
        end
        local.get 2
        local.get 3
        i32.const 547
        i32.const 5
        call $dynrt__fn67
        i32.const 1
        i32.eq
        if  ;; label = @3
          i32.const 0
          call $dynrt_dynBool
          return
        end
        local.get 2
        local.get 3
        i32.const 556
        i32.const 4
        call $dynrt__fn67
        i32.const 1
        i32.eq
        if  ;; label = @3
          call $dynrt_dynNull
          return
        end
        local.get 2
        local.get 3
        i32.const 560
        i32.const 9
        call $dynrt__fn67
        i32.const 1
        i32.eq
        if  ;; label = @3
          call $dynrt_dynUndefined
          return
        end
        global.get $dynrt_global5
        i32.const -1
        i32.eq
        if  ;; label = @3
          call $dynrt_dynUndefined
          return
        end
        global.get $dynrt_global5
        local.get 2
        local.get 3
        call $dynrt__fn58
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
  (func $dynrt__fn77 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt__fn76
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
            call $dynrt__fn71
            local.get 0
            local.get 1
            call $dynrt__fn72
            local.set 4
            local.get 4
            i32.const 46
            i32.eq
            if  ;; label = @5
              block  ;; label = @6
                global.get $dynrt_global4
                local.tee 7
                i32.const 1
                i32.add
                global.set $dynrt_global4
                local.get 0
                local.get 1
                call $dynrt__fn71
                global.get $dynrt_global4
                local.tee 8
                local.set 4
                local.get 0
                local.get 1
                call $dynrt__fn72
                local.set 5
                block  ;; label = @7
                  loop  ;; label = @8
                    block  ;; label = @9
                      local.get 5
                      i32.const 1
                      call $dynrt__fn70
                      i32.const 1
                      i32.eq
                      i32.eqz
                      br_if 2 (;@7;)
                      block  ;; label = @10
                        global.get $dynrt_global4
                        i32.const 1
                        i32.add
                        global.set $dynrt_global4
                        local.get 0
                        local.get 1
                        call $dynrt__fn72
                        local.set 5
                      end
                      br 1 (;@8;)
                    end
                  end
                end
                local.get 0
                local.get 1
                local.get 4
                global.get $dynrt_global4
                call $dynrt__fn3
                local.set 5
                nop
                local.set 4
                local.get 2
                local.get 4
                local.get 5
                call $dynrt_dynMember
                local.set 2
              end
            else
              local.get 4
              i32.const 91
              i32.eq
              if  ;; label = @6
                block  ;; label = @7
                  global.get $dynrt_global4
                  i32.const 1
                  i32.add
                  global.set $dynrt_global4
                  local.get 0
                  local.get 1
                  call $dynrt__fn85
                  local.set 4
                  local.get 0
                  local.get 1
                  call $dynrt__fn71
                  local.get 0
                  local.get 1
                  call $dynrt__fn72
                  i32.const 93
                  i32.eq
                  if  ;; label = @8
                    global.get $dynrt_global4
                    i32.const 1
                    i32.add
                    global.set $dynrt_global4
                  end
                  local.get 2
                  local.get 4
                  call $dynrt_dynIndexValue
                  local.set 2
                end
              else
                local.get 4
                i32.const 40
                i32.eq
                if  ;; label = @7
                  block  ;; label = @8
                    global.get $dynrt_global4
                    i32.const 1
                    i32.add
                    global.set $dynrt_global4
                    call $dynrt_dynArray
                    local.set 4
                    local.get 0
                    local.get 1
                    call $dynrt__fn71
                    local.get 0
                    local.get 1
                    call $dynrt__fn72
                    i32.const 41
                    i32.eq
                    if  ;; label = @9
                      global.get $dynrt_global4
                      i32.const 1
                      i32.add
                      global.set $dynrt_global4
                    else
                      block  ;; label = @10
                        i32.const 1
                        local.set 5
                        block  ;; label = @11
                          loop  ;; label = @12
                            block  ;; label = @13
                              local.get 5
                              i32.const 1
                              i32.eq
                              i32.eqz
                              br_if 2 (;@11;)
                              block  ;; label = @14
                                local.get 0
                                local.get 1
                                call $dynrt__fn85
                                local.set 6
                                local.get 4
                                local.get 6
                                call $dynrt_dynPush
                                local.get 0
                                local.get 1
                                call $dynrt__fn71
                                local.get 0
                                local.get 1
                                call $dynrt__fn72
                                local.set 6
                                local.get 6
                                i32.const 44
                                i32.eq
                                if  ;; label = @15
                                  global.get $dynrt_global4
                                  i32.const 1
                                  i32.add
                                  global.set $dynrt_global4
                                else
                                  block  ;; label = @16
                                    local.get 6
                                    i32.const 41
                                    i32.eq
                                    if  ;; label = @17
                                      global.get $dynrt_global4
                                      i32.const 1
                                      i32.add
                                      global.set $dynrt_global4
                                    end
                                    i32.const 0
                                    local.set 5
                                  end
                                end
                              end
                              br 1 (;@12;)
                            end
                          end
                        end
                      end
                    end
                    global.get $dynrt_global6
                    i32.const 1
                    i32.eq
                    if  ;; label = @9
                      local.get 2
                      local.get 4
                      call $dynrt_dynApply
                      local.set 2
                    else
                      call $dynrt_dynUndefined
                      local.set 2
                    end
                  end
                else
                  i32.const 0
                  local.set 3
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
  (func $dynrt__fn78 (param i32 i32) (result i32)
    (local i32)
    local.get 0
    local.get 1
    call $dynrt__fn71
    local.get 0
    local.get 1
    call $dynrt__fn72
    local.set 2
    local.get 2
    i32.const 45
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_global4
        i32.const 1
        i32.add
        global.set $dynrt_global4
        local.get 0
        local.get 1
        call $dynrt__fn78
        call $dynrt_dynNeg
        return
      end
    end
    local.get 2
    i32.const 33
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_global4
        i32.const 1
        i32.add
        global.set $dynrt_global4
        local.get 0
        local.get 1
        call $dynrt__fn78
        call $dynrt_dynNot
        return
      end
    end
    local.get 2
    i32.const 43
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_global4
        i32.const 1
        i32.add
        global.set $dynrt_global4
        local.get 0
        local.get 1
        call $dynrt__fn78
        local.set 2
        local.get 2
        call $dynrt_dynToNumber
        call $dynrt_dynNumber
        return
      end
    end
    local.get 0
    local.get 1
    call $dynrt__fn77
    return)
  (func $dynrt__fn79 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt__fn78
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
            call $dynrt__fn71
            local.get 0
            local.get 1
            call $dynrt__fn72
            local.set 4
            local.get 4
            i32.const 42
            i32.eq
            if  ;; label = @5
              block  ;; label = @6
                global.get $dynrt_global4
                i32.const 1
                i32.add
                global.set $dynrt_global4
                local.get 2
                local.get 0
                local.get 1
                call $dynrt__fn78
                call $dynrt_dynMul
                local.set 2
              end
            else
              local.get 4
              i32.const 47
              i32.eq
              if  ;; label = @6
                block  ;; label = @7
                  global.get $dynrt_global4
                  i32.const 1
                  i32.add
                  global.set $dynrt_global4
                  local.get 2
                  local.get 0
                  local.get 1
                  call $dynrt__fn78
                  call $dynrt_dynDiv
                  local.set 2
                end
              else
                local.get 4
                i32.const 37
                i32.eq
                if  ;; label = @7
                  block  ;; label = @8
                    global.get $dynrt_global4
                    i32.const 1
                    i32.add
                    global.set $dynrt_global4
                    local.get 2
                    local.get 0
                    local.get 1
                    call $dynrt__fn78
                    call $dynrt_dynMod
                    local.set 2
                  end
                else
                  i32.const 0
                  local.set 3
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
  (func $dynrt__fn80 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt__fn79
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
            call $dynrt__fn71
            local.get 0
            local.get 1
            call $dynrt__fn72
            local.set 4
            local.get 4
            i32.const 43
            i32.eq
            if  ;; label = @5
              block  ;; label = @6
                global.get $dynrt_global4
                i32.const 1
                i32.add
                global.set $dynrt_global4
                local.get 2
                local.get 0
                local.get 1
                call $dynrt__fn79
                call $dynrt_dynAdd
                local.set 2
              end
            else
              local.get 4
              i32.const 45
              i32.eq
              if  ;; label = @6
                block  ;; label = @7
                  global.get $dynrt_global4
                  i32.const 1
                  i32.add
                  global.set $dynrt_global4
                  local.get 2
                  local.get 0
                  local.get 1
                  call $dynrt__fn79
                  call $dynrt_dynSub
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
  (func $dynrt__fn81 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt__fn80
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
            call $dynrt__fn71
            local.get 0
            local.get 1
            call $dynrt__fn72
            local.set 4
            local.get 0
            local.get 1
            call $dynrt__fn73
            local.set 5
            local.get 4
            i32.const 60
            i32.eq
            if  ;; label = @5
              local.get 5
              i32.const 61
              i32.eq
              if  ;; label = @6
                block  ;; label = @7
                  global.get $dynrt_global4
                  i32.const 2
                  i32.add
                  global.set $dynrt_global4
                  local.get 2
                  local.get 0
                  local.get 1
                  call $dynrt__fn80
                  call $dynrt_dynLe
                  local.set 2
                end
              else
                block  ;; label = @7
                  global.get $dynrt_global4
                  i32.const 1
                  i32.add
                  global.set $dynrt_global4
                  local.get 2
                  local.get 0
                  local.get 1
                  call $dynrt__fn80
                  call $dynrt_dynLt
                  local.set 2
                end
              end
            else
              local.get 4
              i32.const 62
              i32.eq
              if  ;; label = @6
                local.get 5
                i32.const 61
                i32.eq
                if  ;; label = @7
                  block  ;; label = @8
                    global.get $dynrt_global4
                    i32.const 2
                    i32.add
                    global.set $dynrt_global4
                    local.get 2
                    local.get 0
                    local.get 1
                    call $dynrt__fn80
                    call $dynrt_dynGe
                    local.set 2
                  end
                else
                  block  ;; label = @8
                    global.get $dynrt_global4
                    i32.const 1
                    i32.add
                    global.set $dynrt_global4
                    local.get 2
                    local.get 0
                    local.get 1
                    call $dynrt__fn80
                    call $dynrt_dynGt
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
  (func $dynrt__fn82 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt__fn81
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
            call $dynrt__fn71
            local.get 0
            local.get 1
            call $dynrt__fn72
            local.set 4
            local.get 0
            local.get 1
            call $dynrt__fn73
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
                global.get $dynrt_global4
                i32.const 2
                i32.add
                global.set $dynrt_global4
                local.get 0
                local.get 1
                call $dynrt__fn72
                i32.const 61
                i32.eq
                if  ;; label = @7
                  global.get $dynrt_global4
                  i32.const 1
                  i32.add
                  global.set $dynrt_global4
                end
                local.get 0
                local.get 1
                call $dynrt__fn81
                local.set 4
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
                  global.get $dynrt_global4
                  i32.const 2
                  i32.add
                  global.set $dynrt_global4
                  local.get 0
                  local.get 1
                  call $dynrt__fn72
                  i32.const 61
                  i32.eq
                  if  ;; label = @8
                    global.get $dynrt_global4
                    i32.const 1
                    i32.add
                    global.set $dynrt_global4
                  end
                  local.get 0
                  local.get 1
                  call $dynrt__fn81
                  local.set 4
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
  (func $dynrt__fn83 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt__fn82
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
            call $dynrt__fn71
            local.get 0
            local.get 1
            call $dynrt__fn72
            i32.const 38
            i32.eq
            if (result i32)  ;; label = @5
              local.get 0
              local.get 1
              call $dynrt__fn73
              i32.const 38
              i32.eq
            else
              i32.const 0
            end
            if  ;; label = @5
              block  ;; label = @6
                global.get $dynrt_global4
                i32.const 2
                i32.add
                global.set $dynrt_global4
                local.get 2
                call $dynrt_dynToBool
                local.set 4
                global.get $dynrt_global6
                local.set 5
                local.get 4
                i32.eqz
                if  ;; label = @7
                  i32.const 0
                  global.set $dynrt_global6
                end
                local.get 0
                local.get 1
                call $dynrt__fn82
                local.set 6
                local.get 5
                global.set $dynrt_global6
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
  (func $dynrt__fn84 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt__fn83
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
            call $dynrt__fn71
            local.get 0
            local.get 1
            call $dynrt__fn72
            i32.const 124
            i32.eq
            if (result i32)  ;; label = @5
              local.get 0
              local.get 1
              call $dynrt__fn73
              i32.const 124
              i32.eq
            else
              i32.const 0
            end
            if  ;; label = @5
              block  ;; label = @6
                global.get $dynrt_global4
                i32.const 2
                i32.add
                global.set $dynrt_global4
                local.get 2
                call $dynrt_dynToBool
                local.set 4
                global.get $dynrt_global6
                local.set 5
                local.get 4
                i32.const 1
                i32.eq
                if  ;; label = @7
                  i32.const 0
                  global.set $dynrt_global6
                end
                local.get 0
                local.get 1
                call $dynrt__fn83
                local.set 6
                local.get 5
                global.set $dynrt_global6
                local.get 4
                i32.eqz
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
  (func $dynrt__fn85 (param i32 i32) (result i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt__fn84
    local.set 2
    local.get 0
    local.get 1
    call $dynrt__fn71
    local.get 0
    local.get 1
    call $dynrt__fn72
    i32.const 63
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_global4
        i32.const 1
        i32.add
        global.set $dynrt_global4
        local.get 2
        call $dynrt_dynToBool
        local.set 2
        global.get $dynrt_global6
        local.set 3
        local.get 2
        i32.eqz
        if  ;; label = @3
          i32.const 0
          global.set $dynrt_global6
        end
        local.get 0
        local.get 1
        call $dynrt__fn85
        local.set 4
        local.get 3
        local.tee 6
        global.set $dynrt_global6
        local.get 0
        local.get 1
        call $dynrt__fn71
        local.get 0
        local.get 1
        call $dynrt__fn72
        i32.const 58
        i32.eq
        if  ;; label = @3
          global.get $dynrt_global4
          i32.const 1
          i32.add
          global.set $dynrt_global4
        end
        local.get 2
        i32.const 1
        i32.eq
        if  ;; label = @3
          i32.const 0
          global.set $dynrt_global6
        end
        local.get 0
        local.get 1
        call $dynrt__fn85
        local.set 5
        local.get 3
        local.tee 7
        global.set $dynrt_global6
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
    global.set $dynrt_global4
    i32.const -1
    global.set $dynrt_global5
    i32.const 1
    global.set $dynrt_global6
    local.get 0
    local.get 1
    call $dynrt__fn85
    return)
  (func $dynrt_dynEvalEnv (param i32 i32 i32) (result i32)
    i32.const 0
    global.set $dynrt_global4
    local.get 2
    global.set $dynrt_global5
    i32.const 1
    global.set $dynrt_global6
    local.get 0
    local.get 1
    call $dynrt__fn85
    return)
  (func $dynrt__fn88 (param i32 i32)
    (local i32) (local i32) (local i32) (local i32)
    global.get $dynrt_global4
    local.tee 4
    local.set 2
    local.get 0
    local.get 1
    call $dynrt__fn72
    local.set 3
    block  ;; label = @1
      loop  ;; label = @2
        block  ;; label = @3
          local.get 3
          i32.const 1
          call $dynrt__fn70
          i32.const 1
          i32.eq
          i32.eqz
          br_if 2 (;@1;)
          block  ;; label = @4
            global.get $dynrt_global4
            i32.const 1
            i32.add
            global.set $dynrt_global4
            local.get 0
            local.get 1
            call $dynrt__fn72
            local.set 3
          end
          br 1 (;@2;)
        end
      end
    end
    local.get 0
    local.get 1
    local.get 2
    global.get $dynrt_global4
    call $dynrt__fn3
    local.set 3
    nop
    local.set 2
    local.get 2
    local.tee 5
    global.set $dynrt_global1
    local.get 3
    global.set $dynrt_global2
    return)
  (func $dynrt__fn89 (param i32 i32)
    (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt__fn71
    local.get 0
    local.get 1
    call $dynrt__fn88
    global.get $dynrt_global1
    local.set 2
    global.get $dynrt_global2
    local.set 3
    local.get 0
    local.get 1
    call $dynrt__fn71
    call $dynrt_dynUndefined
    local.set 4
    local.get 0
    local.get 1
    call $dynrt__fn72
    i32.const 61
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_global4
        i32.const 1
        i32.add
        global.set $dynrt_global4
        local.get 0
        local.get 1
        call $dynrt__fn85
        local.set 4
      end
    end
    global.get $dynrt_global6
    i32.const 1
    i32.eq
    if  ;; label = @1
      global.get $dynrt_global5
      local.get 2
      local.get 3
      local.get 4
      call $dynrt_dynSet
    end
    local.get 0
    local.get 1
    call $dynrt__fn71
    local.get 0
    local.get 1
    call $dynrt__fn72
    i32.const 59
    i32.eq
    if  ;; label = @1
      global.get $dynrt_global4
      i32.const 1
      i32.add
      global.set $dynrt_global4
    end)
  (func $dynrt__fn90 (param i32 i32)
    (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt__fn71
    local.get 0
    local.get 1
    call $dynrt__fn72
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
      call $dynrt__fn85
      local.set 3
    end
    global.get $dynrt_global6
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        local.get 3
        global.set $dynrt_global9
        i32.const 1
        global.set $dynrt_global8
      end
    end
    local.get 0
    local.get 1
    call $dynrt__fn71
    local.get 0
    local.get 1
    call $dynrt__fn72
    i32.const 59
    i32.eq
    if  ;; label = @1
      global.get $dynrt_global4
      i32.const 1
      i32.add
      global.set $dynrt_global4
    end)
  (func $dynrt__fn91 (param i32 i32)
    (local i32) (local i32) (local i32) (local i32) (local i32)
    global.get $dynrt_global6
    local.set 2
    local.get 0
    local.get 1
    call $dynrt__fn71
    local.get 0
    local.get 1
    call $dynrt__fn72
    i32.const 40
    i32.eq
    if  ;; label = @1
      global.get $dynrt_global4
      i32.const 1
      i32.add
      global.set $dynrt_global4
    end
    local.get 0
    local.get 1
    call $dynrt__fn85
    local.set 3
    local.get 0
    local.get 1
    call $dynrt__fn71
    local.get 0
    local.get 1
    call $dynrt__fn72
    i32.const 41
    i32.eq
    if  ;; label = @1
      global.get $dynrt_global4
      i32.const 1
      i32.add
      global.set $dynrt_global4
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
    global.set $dynrt_global6
    local.get 0
    local.get 1
    call $dynrt__fn94
    local.get 2
    global.set $dynrt_global6
    local.get 0
    local.get 1
    call $dynrt__fn71
    local.get 0
    local.get 1
    call $dynrt__fn72
    i32.const 0
    call $dynrt__fn70
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_global4
        local.set 4
        local.get 0
        local.get 1
        call $dynrt__fn88
        global.get $dynrt_global1
        local.set 5
        global.get $dynrt_global2
        local.set 6
        local.get 5
        local.get 6
        i32.const 608
        i32.const 4
        call $dynrt__fn67
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
            global.set $dynrt_global6
            local.get 0
            local.get 1
            call $dynrt__fn94
            local.get 2
            global.set $dynrt_global6
          end
        else
          local.get 4
          global.set $dynrt_global4
        end
      end
    end)
  (func $dynrt__fn92 (param i32 i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    global.get $dynrt_global6
    local.set 2
    local.get 0
    local.get 1
    call $dynrt__fn71
    local.get 0
    local.get 1
    call $dynrt__fn72
    i32.const 40
    i32.eq
    if  ;; label = @1
      global.get $dynrt_global4
      i32.const 1
      i32.add
      global.set $dynrt_global4
    end
    global.get $dynrt_global4
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
            global.set $dynrt_global4
            local.get 0
            local.get 1
            call $dynrt__fn85
            local.set 6
            local.get 0
            local.get 1
            call $dynrt__fn71
            local.get 0
            local.get 1
            call $dynrt__fn72
            i32.const 41
            i32.eq
            if  ;; label = @5
              global.get $dynrt_global4
              i32.const 1
              i32.add
              global.set $dynrt_global4
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
                local.tee 7
                global.set $dynrt_global6
                local.get 0
                local.get 1
                call $dynrt__fn94
                local.get 2
                global.set $dynrt_global6
                global.get $dynrt_global8
                i32.const 1
                i32.eq
                if  ;; label = @7
                  i32.const 0
                  local.set 4
                end
                local.get 5
                i32.const 1
                local.tee 8
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
                local.tee 9
                global.set $dynrt_global6
                local.get 0
                local.get 1
                call $dynrt__fn94
                local.get 2
                global.set $dynrt_global6
                i32.const 0
                local.tee 10
                local.set 4
              end
            end
          end
          br 1 (;@2;)
        end
      end
    end)
  (func $dynrt__fn93 (param i32 i32)
    (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt__fn71
    local.get 0
    local.get 1
    call $dynrt__fn88
    global.get $dynrt_global1
    local.set 2
    global.get $dynrt_global2
    local.set 3
    local.get 0
    local.get 1
    call $dynrt__fn71
    call $dynrt_dynArray
    local.set 4
    local.get 0
    local.get 1
    call $dynrt__fn72
    i32.const 40
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_global4
        i32.const 1
        i32.add
        global.set $dynrt_global4
        local.get 0
        local.get 1
        call $dynrt__fn71
        local.get 0
        local.get 1
        call $dynrt__fn72
        i32.const 41
        i32.eq
        if  ;; label = @3
          global.get $dynrt_global4
          i32.const 1
          i32.add
          global.set $dynrt_global4
        else
          block  ;; label = @4
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
                    call $dynrt__fn71
                    local.get 0
                    local.get 1
                    call $dynrt__fn88
                    global.get $dynrt_global1
                    local.set 6
                    global.get $dynrt_global2
                    local.set 7
                    local.get 4
                    local.get 6
                    local.get 7
                    call $dynrt_dynString
                    call $dynrt_dynPush
                    local.get 0
                    local.get 1
                    call $dynrt__fn71
                    local.get 0
                    local.get 1
                    call $dynrt__fn72
                    local.set 6
                    local.get 6
                    i32.const 44
                    i32.eq
                    if  ;; label = @9
                      global.get $dynrt_global4
                      i32.const 1
                      i32.add
                      global.set $dynrt_global4
                    else
                      block  ;; label = @10
                        local.get 6
                        i32.const 41
                        i32.eq
                        if  ;; label = @11
                          global.get $dynrt_global4
                          i32.const 1
                          i32.add
                          global.set $dynrt_global4
                        end
                        i32.const 0
                        local.set 5
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
    local.get 0
    local.get 1
    call $dynrt__fn71
    i32.const 547
    i32.const 0
    call $dynrt_dynString
    local.set 5
    local.get 0
    local.get 1
    call $dynrt__fn72
    i32.const 123
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_global4
        local.tee 15
        i32.const 1
        local.tee 16
        i32.add
        global.set $dynrt_global4
        global.get $dynrt_global4
        local.tee 17
        local.set 5
        i32.const 1
        local.tee 18
        local.set 6
        i32.const 0
        local.tee 19
        local.set 7
        local.get 19
        local.set 8
        local.get 18
        local.set 9
        block  ;; label = @3
          loop  ;; label = @4
            block  ;; label = @5
              local.get 9
              i32.const 1
              i32.eq
              if (result i32)  ;; label = @6
                global.get $dynrt_global4
                local.get 1
                i32.lt_s
              else
                i32.const 0
              end
              i32.eqz
              br_if 2 (;@3;)
              block  ;; label = @6
                local.get 0
                local.get 1
                global.get $dynrt_global4
                call $dynrt__fn4
                local.set 10
                local.get 7
                i32.const 1
                i32.eq
                if  ;; label = @7
                  local.get 10
                  i32.const 92
                  i32.eq
                  if  ;; label = @8
                    global.get $dynrt_global4
                    i32.const 2
                    i32.add
                    global.set $dynrt_global4
                  else
                    local.get 10
                    local.get 8
                    i32.eq
                    if  ;; label = @9
                      block  ;; label = @10
                        i32.const 0
                        local.set 7
                        global.get $dynrt_global4
                        i32.const 1
                        i32.add
                        global.set $dynrt_global4
                      end
                    else
                      global.get $dynrt_global4
                      i32.const 1
                      i32.add
                      global.set $dynrt_global4
                    end
                  end
                else
                  local.get 10
                  i32.const 39
                  i32.eq
                  if (result i32)  ;; label = @8
                    i32.const 1
                  else
                    local.get 10
                    i32.const 34
                    i32.eq
                  end
                  if  ;; label = @8
                    block  ;; label = @9
                      i32.const 1
                      local.tee 11
                      local.set 7
                      local.get 10
                      local.set 8
                      global.get $dynrt_global4
                      i32.const 1
                      local.tee 12
                      i32.add
                      global.set $dynrt_global4
                    end
                  else
                    local.get 10
                    i32.const 123
                    i32.eq
                    if  ;; label = @9
                      block  ;; label = @10
                        local.get 6
                        i32.const 1
                        local.tee 13
                        i32.add
                        local.set 6
                        global.get $dynrt_global4
                        i32.const 1
                        local.tee 14
                        i32.add
                        global.set $dynrt_global4
                      end
                    else
                      local.get 10
                      i32.const 125
                      i32.eq
                      if  ;; label = @10
                        block  ;; label = @11
                          local.get 6
                          i32.const 1
                          i32.sub
                          local.set 6
                          local.get 6
                          i32.eqz
                          if  ;; label = @12
                            i32.const 0
                            local.set 9
                          else
                            global.get $dynrt_global4
                            i32.const 1
                            i32.add
                            global.set $dynrt_global4
                          end
                        end
                      else
                        global.get $dynrt_global4
                        i32.const 1
                        i32.add
                        global.set $dynrt_global4
                      end
                    end
                  end
                end
              end
              br 1 (;@4;)
            end
          end
        end
        local.get 0
        local.get 1
        local.get 5
        global.get $dynrt_global4
        call $dynrt__fn3
        local.set 6
        nop
        local.set 5
        local.get 5
        local.get 6
        call $dynrt_dynString
        local.set 5
        local.get 0
        local.get 1
        call $dynrt__fn72
        i32.const 125
        i32.eq
        if  ;; label = @3
          global.get $dynrt_global4
          i32.const 1
          i32.add
          global.set $dynrt_global4
        end
      end
    end
    local.get 4
    local.get 5
    global.get $dynrt_global5
    call $dynrt__fn56
    local.set 4
    global.get $dynrt_global6
    i32.const 1
    i32.eq
    if  ;; label = @1
      global.get $dynrt_global5
      local.get 2
      local.get 3
      local.get 4
      call $dynrt_dynSet
    end)
  (func $dynrt__fn94 (param i32 i32)
    (local i32) (local i32) (local i32) (local i32)
    local.get 0
    local.get 1
    call $dynrt__fn71
    local.get 0
    local.get 1
    call $dynrt__fn72
    local.set 2
    local.get 2
    i32.const 123
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_global4
        i32.const 1
        i32.add
        global.set $dynrt_global4
        local.get 0
        local.get 1
        call $dynrt__fn95
        local.get 0
        local.get 1
        call $dynrt__fn71
        local.get 0
        local.get 1
        call $dynrt__fn72
        i32.const 125
        i32.eq
        if  ;; label = @3
          global.get $dynrt_global4
          i32.const 1
          i32.add
          global.set $dynrt_global4
        end
        return
      end
    end
    local.get 2
    i32.const 59
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_global4
        i32.const 1
        i32.add
        global.set $dynrt_global4
        return
      end
    end
    local.get 2
    i32.const 0
    call $dynrt__fn70
    i32.const 1
    i32.eq
    if  ;; label = @1
      block  ;; label = @2
        global.get $dynrt_global4
        local.set 2
        local.get 0
        local.get 1
        call $dynrt__fn88
        global.get $dynrt_global1
        local.set 3
        global.get $dynrt_global2
        local.set 4
        local.get 3
        local.get 4
        i32.const 612
        i32.const 3
        call $dynrt__fn67
        i32.const 1
        i32.eq
        if (result i32)  ;; label = @3
          i32.const 1
        else
          local.get 3
          local.get 4
          i32.const 615
          i32.const 5
          call $dynrt__fn67
          i32.const 1
          i32.eq
        end
        if (result i32)  ;; label = @3
          i32.const 1
        else
          local.get 3
          local.get 4
          i32.const 620
          i32.const 3
          call $dynrt__fn67
          i32.const 1
          i32.eq
        end
        if  ;; label = @3
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt__fn89
            return
          end
        end
        local.get 3
        local.get 4
        i32.const 623
        i32.const 2
        call $dynrt__fn67
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt__fn91
            return
          end
        end
        local.get 3
        local.get 4
        i32.const 625
        i32.const 5
        call $dynrt__fn67
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt__fn92
            return
          end
        end
        local.get 3
        local.get 4
        i32.const 630
        i32.const 6
        call $dynrt__fn67
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt__fn90
            return
          end
        end
        local.get 3
        local.get 4
        i32.const 636
        i32.const 8
        call $dynrt__fn67
        i32.const 1
        i32.eq
        if  ;; label = @3
          block  ;; label = @4
            local.get 0
            local.get 1
            call $dynrt__fn93
            return
          end
        end
        local.get 0
        local.get 1
        call $dynrt__fn71
        local.get 0
        local.get 1
        call $dynrt__fn72
        local.set 5
        local.get 5
        i32.const 61
        i32.eq
        if (result i32)  ;; label = @3
          local.get 0
          local.get 1
          call $dynrt__fn73
          i32.const 61
          i32.ne
        else
          i32.const 0
        end
        if  ;; label = @3
          block  ;; label = @4
            global.get $dynrt_global4
            i32.const 1
            i32.add
            global.set $dynrt_global4
            local.get 0
            local.get 1
            call $dynrt__fn85
            local.set 2
            global.get $dynrt_global6
            i32.const 1
            i32.eq
            if  ;; label = @5
              global.get $dynrt_global5
              local.get 3
              local.get 4
              local.get 2
              call $dynrt_dynSet
            end
            local.get 0
            local.get 1
            call $dynrt__fn71
            local.get 0
            local.get 1
            call $dynrt__fn72
            i32.const 59
            i32.eq
            if  ;; label = @5
              global.get $dynrt_global4
              i32.const 1
              i32.add
              global.set $dynrt_global4
            end
            return
          end
        end
        local.get 2
        global.set $dynrt_global4
        local.get 0
        local.get 1
        call $dynrt__fn85
        local.set 2
        global.get $dynrt_global6
        i32.const 1
        i32.eq
        if  ;; label = @3
          local.get 2
          global.set $dynrt_global10
        end
        local.get 0
        local.get 1
        call $dynrt__fn71
        local.get 0
        local.get 1
        call $dynrt__fn72
        i32.const 59
        i32.eq
        if  ;; label = @3
          global.get $dynrt_global4
          i32.const 1
          i32.add
          global.set $dynrt_global4
        end
        return
      end
    end
    local.get 0
    local.get 1
    call $dynrt__fn85
    local.set 2
    global.get $dynrt_global6
    i32.const 1
    i32.eq
    if  ;; label = @1
      local.get 2
      global.set $dynrt_global10
    end
    local.get 0
    local.get 1
    call $dynrt__fn71
    local.get 0
    local.get 1
    call $dynrt__fn72
    i32.const 59
    i32.eq
    if  ;; label = @1
      global.get $dynrt_global4
      i32.const 1
      i32.add
      global.set $dynrt_global4
    end)
  (func $dynrt__fn95 (param i32 i32)
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
            call $dynrt__fn71
            local.get 0
            local.get 1
            call $dynrt__fn72
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
                global.get $dynrt_global6
                local.set 3
                global.get $dynrt_global8
                i32.const 1
                i32.eq
                if  ;; label = @7
                  i32.const 0
                  global.set $dynrt_global6
                end
                local.get 0
                local.get 1
                call $dynrt__fn94
                local.get 3
                global.set $dynrt_global6
              end
            end
          end
          br 1 (;@2;)
        end
      end
    end)
  (func $dynrt_dynRun (param i32 i32 i32) (result i32)
    (local i32) (local i32)
    i32.const 0
    local.tee 3
    global.set $dynrt_global4
    local.get 2
    global.set $dynrt_global5
    i32.const 1
    global.set $dynrt_global6
    i32.const 0
    local.tee 4
    global.set $dynrt_global8
    call $dynrt_dynUndefined
    global.set $dynrt_global9
    call $dynrt_dynUndefined
    global.set $dynrt_global10
    local.get 0
    local.get 1
    call $dynrt__fn95
    global.get $dynrt_global8
    i32.const 1
    i32.eq
    if (result i32)  ;; label = @1
      global.get $dynrt_global9
    else
      global.get $dynrt_global10
    end
    return)
  ;; data from dynrt
  (data (;0;) (i32.const 547) "")
  (data (;1;) (i32.const 547) "false")
  (data (;2;) (i32.const 552) "true")
  (data (;3;) (i32.const 556) "null")
  (data (;4;) (i32.const 560) "undefined")
  (data (;5;) (i32.const 569) "abs")
  (data (;6;) (i32.const 572) "sqrt")
  (data (;7;) (i32.const 576) "floor")
  (data (;8;) (i32.const 581) "ceil")
  (data (;9;) (i32.const 585) "round")
  (data (;10;) (i32.const 590) "min")
  (data (;11;) (i32.const 593) "max")
  (data (;12;) (i32.const 596) "len")
  (data (;13;) (i32.const 599) "inc")
  (data (;14;) (i32.const 602) "length")
  (data (;15;) (i32.const 608) "else")
  (data (;16;) (i32.const 612) "let")
  (data (;17;) (i32.const 615) "const")
  (data (;18;) (i32.const 620) "var")
  (data (;19;) (i32.const 623) "if")
  (data (;20;) (i32.const 625) "while")
  (data (;21;) (i32.const 630) "return")
  (data (;22;) (i32.const 636) "function")
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
  (export "cabi_realloc" (func $cabi_realloc))
)