// fib-zig.zig
const number = u64;

// Maximum safe input for Fibonacci to avoid u64 overflow (F(93) fits, F(94) does not)
const MAX_SAFE_FIB: u64 = 93;

fn fib(n: number) number {
    // Input validation to prevent overflow and invalid inputs
    if (n > MAX_SAFE_FIB) {
        @panic("Input exceeds maximum safe value (93) for u64 Fibonacci");
    }
    if (n == 0) {
        return 0;
    }
    if (n == 1) {
        return 1;
    }

    var a: number = 1;
    var b: number = 1;
    var temp: number = 0;
    var i: number = n - 1;

    while (i > 0) {
        temp = a;
        a = a + b;
        b = temp;
        i -= 1;
    }

    return b;
}

// Main function for testing (optional, not used in WASM)
const std = @import("std");
pub fn main() !void {
    const result = fib(10);
    std.debug.print("Fibonacci(10) = {d}\n", .{result});
}
