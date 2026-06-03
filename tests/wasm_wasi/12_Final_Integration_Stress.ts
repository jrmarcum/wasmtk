// Final_Integration_Stress.ts
type i32 = number;

interface MatrixManager {
  addRow: (vals: i32[]) => i32;
  getSummary: () => i32[];
}

export function createManager(initialRows: i32[][]): MatrixManager {
  // Capture the multi-dimensional array (Phase 6d)
  const data = initialRows;

  return {
    // Closure capturing 'data' (Phase 5e)
    addRow: (vals: i32[]) => {
      data.push(vals); // Dynamic mutation (Phase 10b)
      return data.length;
    },
    // Returning a complex type (Phase 12)
    getSummary: () => {
      const summary: i32[] = [];
      for (let i = 0; i < data.length; i++) {
        summary.push(data[i].length);
      }
      return summary;
    }
  };
}

export function _start(): void {
  const manager = createManager([[1, 2], [3, 4, 5]]);
  manager.addRow([6]);
  
  const stats = manager.getSummary(); 
  // Expected stats: [2, 3, 1]
  console.log(stats.length); 
}

_start();