/**
 * @module compiler
 * @description Logic for transforming AssemblyScript and TypeScript into optimized WebAssembly modules.
 */

import { main as asc } from "asc";
import { basename, dirname, join } from "@std/path";

/**
 * Interface for compiler output results.
 */
export interface CompileResult {
  /** True if the compilation succeeded. */
  success: boolean;
  /** Error message if compilation failed. */
  error?: string;
}

/**
 * Low-level wrapper for the AssemblyScript compiler (asc).
 * @param inputPath - Path to the source .ts file.
 * @param outputPath - Path where the .wasm file should be written.
 * @returns A promise resolving to a CompileResult.
 */
export async function runAssemblyScriptCompiler(
  inputPath: string, 
  outputPath: string
): Promise<CompileResult> {
  const { error, stderr } = await asc([
    inputPath,
    "--target", "release",
    "--outFile", outputPath,
    "--optimize",
    "--noAssert",
    "--exportRuntime",
    "--converge"
  ]);

  if (error) {
    return { 
      success: false, 
      error: error.message + (stderr ? `\n${stderr.toString()}` : "") 
    };
  }
  return { success: true };
}

/**
 * Uses Javy to compile a JS bundle into a WASI-compatible WASM module.
 * @param jsPath - Path to the bundled JavaScript file.
 * @param wasmPath - Output path for the generated WASM.
 */
export async function runJavyCompiler(jsPath: string, wasmPath: string): Promise<void> {
  const command = new Deno.Command("javy", {
    args: ["build", jsPath, "-o", wasmPath],
  });

  const { success, stderr } = await command.output();
  if (!success) {
    throw new Error(`Javy compilation failed: ${new TextDecoder().decode(stderr)}`);
  }
}