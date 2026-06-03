(module
  ;; function isOdd: returns 1 if its argument is odd, 0 if it is even.
  (func $isOdd (export "isOdd") (param $n i32) (result i32)
    local.get $n
    i32.const 1
    i32.and   ;; computes (n & 1), returns 1 if odd, 0 if even
  )
  ;; function isEven: returns 1 if its argument is even, 0 if it is odd.
  (func $isEven (export "isEven") (param $n i32) (result i32)
    local.get $n
    i32.const 1
    i32.and   ;; computes (n & 1), returns 1 if odd, 0 if even
    i32.eqz   ;; inverts the result, returns 1 if even, 0 if odd
  )
)