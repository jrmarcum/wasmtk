const requests: number[] = [1, 2, 3, 4, 5];

for (let i: number = 0; i < requests.length; i++) {
    console.log("request", requests[i], "2009-11-10T23:00:00.000Z");
}

const burstyRequests: number[] = [1, 2, 3, 4, 5];
let tokens: number = 3;

for (let i: number = 0; i < burstyRequests.length; i++) {
    if (tokens > 0) {
        tokens--;
        console.log("request", burstyRequests[i], "2009-11-10T23:00:00.000Z");
    } else {
        console.log("request", burstyRequests[i], "2009-11-10T23:00:00.020Z");
    }
}
