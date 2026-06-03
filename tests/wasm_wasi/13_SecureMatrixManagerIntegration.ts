type i32 = number;

interface SecureMatrix {
  addValue: (row: i32, val: i32) => void;
  getRow: (row: i32) => i32[];
}

export function createSecureMatrix(): SecureMatrix {
  // Phase 6d: Multi-dimensional dynamic array
  const data: i32[][] = [[], []];

  return {
    // Phase 5e: Upward closure capturing 'data'
    addValue: (row: i32, val: i32) => {
      // Phase 13a: Error Guarding
      if (row >= data.length) {
        throw new Error("Index out of bounds");
      }
      // Phase 10b: Dynamic mutation
      data[row].push(val);
    },
    // Phase 12: Returning complex interface types
    getRow: (row: i32) => {
      if (row >= data.length) throw new Error("Invalid Row");
      return data[row];
    }
  };
}

export function _start(): void {
  const sm = createSecureMatrix();
  sm.addValue(0, 42);
  const row0 = sm.getRow(0);
  console.log(row0[0]); // Expected: 42
  
  // This should trigger the Phase 13 throw logic
  sm.addValue(5, 100); 
}

_start();