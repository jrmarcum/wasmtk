// time.Sleep in a goroutine — the scheduler yields via asyncify while sleeping.
package main

import "time"

func main() {
	done := make(chan int)
	go func() {
		time.Sleep(1 * time.Millisecond)
		done <- 42
	}()
	v := <-done
	println("sleep-result:", v) // 42
}
