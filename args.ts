export interface AppConfig {
  mode: "run" | "modc" | "convert" | "wasic" | "bundle" | "tsrun" | "help" | "version" | "info" | "wasm2js";
  filePath: string;
  functionName: string;
  programArgs: string[];
  output?: string;
  showHelp: boolean;
  showVersion: boolean;
}

export function parseCliArgs(args: string[]): AppConfig {
  const config: AppConfig = {
    mode: "help", filePath: "", functionName: "", programArgs: [],
    showHelp: false, showVersion: false,
  };

  if (args.length === 0) return { ...config, showHelp: true };
  const firstArg = args[0].toLowerCase();

  if (["--version", "-v"].includes(firstArg)) return { ...config, mode: "version", showVersion: true };
  if (["--help", "-h"].includes(firstArg)) return { ...config, mode: "help", showHelp: true };

  config.mode = firstArg as AppConfig["mode"];
  const remaining = args.slice(1);

  switch (config.mode) {
    case "run":
    case "tsrun":
      if (remaining.length < 1) throw new Error("Usage: run <file> [function] [args...]");
      config.filePath = remaining[0];
      if ((config.filePath.endsWith(".wasm") || config.filePath.endsWith(".wat")) && remaining.length > 1) {
        config.functionName = remaining[1];
        config.programArgs = remaining.slice(2);
      } else {
        config.programArgs = remaining.slice(1);
      }
      break;
    default:
      config.filePath = remaining[0] ?? "";
      if (remaining[1] === "-o") config.output = remaining[2];
  }
  return config;
}