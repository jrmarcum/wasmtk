(module
    (memory 4096)
    (export "memory" (memory 0))

    (func $sieve (export "sieve") (param $n i32) (result i32)
        (local $i i32)
        (local $j i32)
        (local $count i32)
        (local $prime_index i32)

        ;; Initialize memory: mark all numbers from 0 to n-1 as potential primes (1)
        (local.set $i (i32.const 0))
        (block $endLoop
            (loop $loop
                (br_if $endLoop (i32.ge_s (local.get $i) (local.get $n)))
                (i32.store8 (local.get $i) (i32.const 1))
                (local.set $i (i32.add (local.get $i) (i32.const 1)))
                (br $loop)
            )
        )

        ;; Mark multiples of each prime as non-prime (0)
        (local.set $i (i32.const 2))
        (block $endLoop
            (loop $loop
                (br_if $endLoop
                    (i32.ge_s
                        (i32.mul
                            (local.get $i)
                            (local.get $i)
                        ) 
                        (local.get $n)
                    )
                )
                (if (i32.eq (i32.load8_s (local.get $i)) (i32.const 1))
                    (then
                        (local.set $j
                            (i32.mul
                                (local.get $i)
                                (local.get $i)
                            )
                        )
                        (block $endInnerLoop
                            (loop $innerLoop
                                (i32.store8 (local.get $j) (i32.const 0))
                                (local.set $j
                                    (i32.add
                                        (local.get $j)
                                        (local.get $i)
                                    )
                                )
                                (br_if $endInnerLoop (i32.ge_s (local.get $j) (local.get $n)))
                                (br $innerLoop)
                            )
                        )
                    )
                )
                (local.set $i
                    (i32.add
                        (local.get $i)
                        (i32.const 1)
                    )
                )
                (br $loop)
            )
        )
            
        ;; Count primes and store them in memory starting at offset 4096
        (local.set $i (i32.const 2))
        (local.set $count (i32.const 0))
        (local.set $prime_index (i32.const 4096)) ;; Store primes in memory after n
        (block $endLoop
            (loop $loop
                (if (i32.eq (i32.load8_s (local.get $i)) (i32.const 1))
                    (then
                        ;; Store prime number in memory
                        (i32.store (local.get $prime_index) (local.get $i))
                        (local.set $prime_index
                            (i32.add
                                (local.get $prime_index)
                                (i32.const 4)
                            )
                        )
                        (local.set $count
                            (i32.add
                                (local.get $count)
                                (i32.const 1)
                            )
                        )
                    )
                )
                (local.set $i
                    (i32.add
                        (local.get $i)
                        (i32.const 1)
                    )
                )
                (br_if $endLoop
                    (i32.ge_s
                        (local.get $i)
                        (local.get $n)
                    )
                )
                (br $loop)
            )
        )
        
        ;; Return the count of primes
        (local.get $count)
    )
)