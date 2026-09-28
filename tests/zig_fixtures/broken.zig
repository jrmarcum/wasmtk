// broken.zig — zig_tests.ts failure-path fixture: a deliberate compile error. The build must exit
// non-zero and leave no artifact (the 2026-08-24 audit found the success report unguarded).

export fn add(a: i32, b: i32) i32 {
    return a + undeclared_name;
}
