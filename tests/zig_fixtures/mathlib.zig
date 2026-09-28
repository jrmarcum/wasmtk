// mathlib.zig — zig_tests.ts library fixture: `export fn`s become wasm exports under
// `wasmtk modc --lang=zig` (wasm32-freestanding, no _start).

export fn add(a: i32, b: i32) i32 {
    return a + b;
}

export fn fib(n: u32) u32 {
    if (n < 2) return n;
    var a: u32 = 0;
    var b: u32 = 1;
    var i: u32 = 1;
    while (i < n) : (i += 1) {
        const t = a + b;
        a = b;
        b = t;
    }
    return b;
}
