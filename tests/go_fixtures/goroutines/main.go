// Goroutine worker-pool fixture for the in-house asyncify path (no external
// binaryen). Exercises `go`, buffered channels, and channel range/close — all
// of which require TinyGo's asyncify transform. wasmtk resolves the resulting
// in-wasm `asyncify.*` control imports via binaryen-ts's Asyncify pass.
package main

func worker(jobs <-chan int, results chan<- int) {
	for j := range jobs {
		results <- j * 2
	}
}

func main() {
	jobs := make(chan int, 5)
	results := make(chan int, 5)
	for w := 0; w < 3; w++ {
		go worker(jobs, results)
	}
	for j := 1; j <= 5; j++ {
		jobs <- j
	}
	close(jobs)
	sum := 0
	for a := 0; a < 5; a++ {
		sum += <-results
	}
	println("sum:", sum) // 2+4+6+8+10 = 30
}
