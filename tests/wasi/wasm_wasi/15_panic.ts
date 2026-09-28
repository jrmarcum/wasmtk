// @expect-exit: 1  (dies on an uncaught throw by design; exit 1 at parity with wasmtime)
function mustPositive(n: number): number {
    if (n <= 0) {
        throw new Error(`expected positive, got ${n}`);
    }
    return n;
}

console.log(mustPositive(5));

mustPositive(-1);
