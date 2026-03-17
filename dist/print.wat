;; print.wat - Native print shim for wasmtk
;; Provides console.log functionality for AssemblyScript modules
;; Works in both browser and WASI environments

(module
  ;; Import host print function
  (import "env" "print" (func $host_print (param i32 i32)))
  
  ;; Export memory
  (memory (export "memory") 1)
  
  ;; Print string without newline
  (func $print (export "print") (param $str_ptr i32) (param $str_len i32)
    (call $host_print (local.get $str_ptr) (local.get $str_len))
  )
  
  ;; Print string with newline
  (func $println (export "println") (param $str_ptr i32) (param $str_len i32)
    ;; Print the string
    (call $host_print (local.get $str_ptr) (local.get $str_len))
    
    ;; Print newline (ASCII 10)
    ;; Store newline in memory at address 0
    (i32.store8 (i32.const 0) (i32.const 10))
    (call $host_print (i32.const 0) (i32.const 1))
  )
  
  ;; Print integer
  (func $print_i32 (export "print_i32") (param $value i32)
    ;; Convert number to string and print
    ;; For now, just print a placeholder
    ;; Full implementation would convert i32 to ASCII digits
    (call $host_print (i32.const 0) (i32.const 0))
  )
)