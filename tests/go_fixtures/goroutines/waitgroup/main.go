// sync.WaitGroup + Mutex — concurrent counter with closure capture + defer.
package main

import "sync"

func main() {
	var wg sync.WaitGroup
	var mu sync.Mutex
	counter := 0
	for i := 0; i < 10; i++ {
		wg.Add(1)
		go func(n int) {
			defer wg.Done()
			mu.Lock()
			counter += n
			mu.Unlock()
		}(i)
	}
	wg.Wait()
	println("wg-counter:", counter) // 0+1+...+9 = 45
}
