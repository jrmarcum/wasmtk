/**
 * compiler.ts
 */
import asc from "asc";

/**
 * Helper to ensure the input file is a TypeScript file.
 */
function validateTs(filePath: string, commandName: string) {
  if (!filePath.endsWith(".ts")) {
    throw new Error(`${commandName} requires a .ts file as input. Received: ${filePath}`);
  }
}

/**
 * Compiles TS to Wasm via AssemblyScript.
 */
export async function compileMod(filePath: string) {
  validateTs(filePath, "modc");
  const outputPath = filePath.replace(/\.ts$/, ".wasm");
  
  const { error, stderr } = await asc.main([
    filePath, 
    "--binaryFile", outputPath, 
    "--optimize",
    "--lowMemoryLimit"
  ]);
  
  if (error) throw new Error(`AssemblyScript Error: ${stderr.toString()}`);
  console.log(`✅ Success: ${outputPath}`);
}

/**
 * Compiles TS to WASI via Javy.
 * LOGIC UPDATE: Now bundles to JS first to ensure clean syntax for Javy.
 */
export async function compileWasi(filePath: string, output?: string) {
  validateTs(filePath, "wasic");
  const target = output || filePath.replace(/\.ts$/, ".wasm");
  
  // 1. Create a temporary JS bundle path
  const tempJs = await Deno.makeTempFile({ suffix: ".js" });

  try {
    // 2. Use our existing bundle logic to pre-process the TS
    console.log(`  > Pre-processing ${filePath}...`);
    await bundleTs(filePath, tempJs);

    // 3. Pass the bundled JS to Javy
    const command = new Deno.Command("javy", { 
      args: ["build", tempJs, "-o", target] 
    });
    
    const { success, stderr } = await command.output();
    if (!success) {
      throw new Error(`Javy Error: ${new TextDecoder().decode(stderr)}`);
    }
    
    console.log(`✅ Compiled WASI: ${target}`);
  } finally {
    // 4. Clean up the temporary bundle
    try { await Deno.remove(tempJs); } catch { /* ignore */ }
  }
}

/**
 * Bundles TS files using Deno's native bundle command.
 */
export async function bundleTs(filePath: string, output?: string) {
  validateTs(filePath, "bundle");
  const target = output || filePath.replace(/\.ts$/, ".js");
  
  const command = new Deno.Command(Deno.execPath(), { 
    args: ["bundle", filePath, "-o", target] 
  });
  
  const { success, stderr } = await command.output();
  if (!success) {
    throw new Error(`Bundling failed: ${new TextDecoder().decode(stderr)}`);
  }
  // Only log if we aren't calling this from another internal function
  if (!output) console.log(`✅ Bundled: ${target}`);
}