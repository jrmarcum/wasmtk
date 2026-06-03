(module
    (func $fib (param $n i32) (result i32)
        ;; Declare local registers
        (local $i i32)
        (local $a i32)
        (local $b i32)
        (local $temp i32)

        ;; Handle first two numbers as special cases
        (if (i32.eq (local.get $n) (i32.const 0))
            (then
                (return (i32.const 0))
            )
        )
        (if (i32.eq (local.get $n) (i32.const 1))
            (then
                (return (i32.const 1))
            )
        )

        ;; Initialize first two values
        (local.set $a (i32.const 0))
        (local.set $b (i32.const 1))
        (local.set $i (i32.const 2))

        ;; Loop to compute Fibonacci number
        (block
            (loop
                ;; Exit loop if i > n
                (br_if 1 (i32.gt_u (local.get $i) (local.get $n)))

                ;; Compute next Fibonacci number
                (local.set $temp (i32.add (local.get $a) (local.get $b)))
                (local.set $a (local.get $b))
                (local.set $b (local.get $temp))

                ;; Increment counter
                (local.set $i
                    (i32.add
                        (local.get $i)
                        (i32.const 1)
                    )
                )

                ;; Continue loop
                (br 0)
            )
        )

        ;; Return result
        (local.get $b)
    )
    (export "fib" (func $fib))
)