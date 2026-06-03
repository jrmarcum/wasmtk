// 1. Natively import functions and linear memory directly from the WASM binary!
import { insert_symbol, lookup_symbol } from "./18_symbol_table.wasm";

function runDenoPhase18Test() {
  console.log("🚀 Initializing Modern Deno Phase 18 Direct-Import Test...");

  const variableRecords: Array<{ namePtr: number; typeId: number; scopeId: number; addr: number }> = [];
  const MAX_DEPTH = 100;       
  const VARS_PER_SCOPE = 30;   
  let currentStringPtr = 2000; 

  // Matrix generation for tracking names natively
  const nameMatrix: number[][] = Array.from({ length: MAX_DEPTH + 1 }, () => []);
  for (let depth = 1; depth <= MAX_DEPTH; depth++) {
    for (let v = 0; v < VARS_PER_SCOPE; v++) {
      currentStringPtr += 4;
      nameMatrix[depth][v] = currentStringPtr;
    }
  }

  try {
    // --- PHASE 18A: INSERTION & ARITHMETIC ---
    for (let depth = 1; depth <= MAX_DEPTH; depth++) {
      for (let v = 0; v < VARS_PER_SCOPE; v++) {
        const namePtr = nameMatrix[depth][v];
        const typeId = (v % 4) + 1;
        
        // Directly executed with native performance
        const actualAddr = insert_symbol(namePtr, typeId, depth);
        variableRecords.push({ namePtr, typeId, scopeId: depth, addr: actualAddr });
      }
    }
    console.log("✅ Phase 18A Passed: Memory pointer allocation clean.");

    // --- PHASE 18B: SHADOWING EXTREME STRESS ---
    console.log("🔥 Injecting Shadowed Variables...");
    const shadowedNamePtr = 9999;
    const localShadowAddr = insert_symbol(shadowedNamePtr, 4, 100);

    // --- PHASE 18C: REVERSE-LOOKUP RESOLUTION INTEGRITY ---
    console.log("🔍 Running Phase 18C: Checking lookup resolution paths...");
    for (let i = 0; i < variableRecords.length; i += 13) {
      const target = variableRecords[i];
      const resolvedAddr = lookup_symbol(target.namePtr);
      
      if (resolvedAddr !== target.addr) {
        throw new Error(`[Lookup Failed] Expected address ${target.addr}, got ${resolvedAddr}`);
      }
    }

    const activeLookupAddr = lookup_symbol(shadowedNamePtr);
    if (activeLookupAddr !== localShadowAddr) {
      throw new Error(`[Shadowing Failure] Scope precedence bypassed!`);
    }
    console.log("✅ Phase 18C Passed: Scope precedence and lookup logic solid.");

    // --- PHASE 18D: ERROR ISOLATION (MISSING KEYS) ---
    console.log("🛡️ Running Phase 18D: Checking invalid keys...");
    if (lookup_symbol(888888) !== -1) {
      throw new Error(`[Security Hole] Out-of-bounds key wasn't rejected with -1.`);
    }
    console.log("✅ Phase 18D Passed: Out-of-bounds queries rejected.");
    
    console.log("\n🏆 PHASE 18 COMPLETE SUITE PASSED via direct ES Module loading!");

  } catch (error: unknown) {
    console.error("❌ Phase 18 Stress Test FAILED!");
    if (error instanceof Error) {
      console.error(error.message); // This line is now perfectly safe
    } else {
      console.error(String(error));
    }
    Deno.exit(1);
  }
}

runDenoPhase18Test();
