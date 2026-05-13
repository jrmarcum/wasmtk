function worker(id: number): void {
    console.log(`Worker ${id} starting`);
    console.log(`Worker ${id} done`);
}

for (let i: number = 1; i <= 5; i++) {
    worker(i);
}
