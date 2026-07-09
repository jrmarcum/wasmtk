// Nested goroutines — each outer goroutine spawns a batch of inner goroutines.
package main

import "sync"

func main() {
	var wg sync.WaitGroup
	results := make(chan int, 9)
	for i := 0; i < 3; i++ {
		wg.Add(1)
		go func(base int) {
			defer wg.Done()
			var inner sync.WaitGroup
			for j := 0; j < 3; j++ {
				inner.Add(1)
				go func(v int) {
					defer inner.Done()
					results <- v
				}(base*3 + j)
			}
			inner.Wait()
		}(i)
	}
	wg.Wait()
	close(results)
	sum := 0
	for v := range results {
		sum += v
	}
	println("nested-sum:", sum) // 0+1+...+8 = 36
}
