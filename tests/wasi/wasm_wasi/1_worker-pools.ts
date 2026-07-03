function worker(id: number, j: number): void {
    console.log(`worker ${id} started  job ${j}`);
    console.log(`worker ${id} finished job ${j}`);
}

const jobs: number[] = [1, 2, 3, 4, 5];

for (let i: number = 0; i < jobs.length; i++) {
    const workerId: number = (i % 3) + 1;
    worker(workerId, jobs[i]);
}
