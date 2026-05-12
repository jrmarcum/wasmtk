// Spawning external processes via exec.Command is not available in WASI.
// In Go, this would run date, grep, and ls -a -l -h as child processes.

console.log("Spawning processes is not available in WASI");
