export const enum Threshold {
  Low = 10,
  High = 100
}

export function _start(): void {
  const bigVal: bigint = 150n;
  const multiplier: bigint = 2n;
  
  const result: bigint = bigVal * multiplier; // 300n

  if (result > BigInt(Threshold.High)) {
    console.log(result); 
  } else {
    console.log(0n);
  }
}

_start();