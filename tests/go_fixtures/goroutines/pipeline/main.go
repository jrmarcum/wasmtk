// Larger program — a 3-stage fan-out pipeline: generate -> square (3 workers) -> sum,
// with a WaitGroup-driven close of the intermediate channel.
package main

import "sync"

func main() {
	nums := make(chan int, 10)
	squares := make(chan int, 10)

	go func() {
		for i := 1; i <= 5; i++ {
			nums <- i
		}
		close(nums)
	}()

	var wg sync.WaitGroup
	for w := 0; w < 3; w++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for n := range nums {
				squares <- n * n
			}
		}()
	}
	go func() {
		wg.Wait()
		close(squares)
	}()

	total := 0
	for s := range squares {
		total += s
	}
	println("pipeline-total:", total) // 1+4+9+16+25 = 55
}
