(module
  (type (;0;) (func (param f64) (result f64)))
  (func (;0;) (type 0) (param f64) (result f64)
    (local f64 f64 f64)
    f64.const 0x1p+0 (;=1;)
    local.set 3
    loop  ;; label = @1
      local.get 0
      f64.const 0x0p+0 (;=0;)
      f64.gt
      if  ;; label = @2
        local.get 2
        local.tee 1
        local.get 3
        f64.add
        local.set 2
        local.get 1
        local.set 3
        local.get 0
        f64.const -0x1p+0 (;=-1;)
        f64.add
        local.set 0
        br 1 (;@1;)
      end
    end
    local.get 2)
  (memory (;0;) 0)
  (export "fib" (func 0))
  (export "memory" (memory 0)))
