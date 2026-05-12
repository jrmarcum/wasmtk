// Replacing the current process via syscall.Exec is not available in WASI.
// In Go, this would exec ls -a -l -h and replace the current process entirely.

console.log("syscall.Exec is not available in WASI");
