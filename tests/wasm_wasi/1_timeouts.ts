function simulateWork(ms: number, result: string, timeoutMs: number): string {
    if (ms > timeoutMs) {
        return `timeout ${timeoutMs / 100}`;
    }
    return result;
}

const r1: string = simulateWork(200, "result 1", 100);
console.log(r1);

const r2: string = simulateWork(200, "result 2", 300);
console.log(r2);
