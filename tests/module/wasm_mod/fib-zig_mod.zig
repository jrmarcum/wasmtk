export fn fib(n: u32) u32 {
    var num: u32 = n;
    var a: u32 = 0;
    var b: u32 = 1;
    var temp: u32 = 0;
    while (num > 0) {
        temp = a;
        a = a + b;
        b = temp;
        num -= 1;
    }
    return a;
}
