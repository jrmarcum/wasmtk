---
[package]
name = "fibonacci-wasm"
version = "0.1.0"
edition = "2021"

[dependencies]
# No external dependencies needed for this simple test
---

#[no_mangle]
pub extern "C" fn fib(mut num: i32) -> i32 {
    let mut a = 0;
    let mut b = 1;
    let mut temp;

    while num > 0 {
        temp = a;
        a = a + b;
        b = temp;
        num -= 1;
    }

    a
}