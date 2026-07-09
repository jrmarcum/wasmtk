// select over two unbuffered channels fed by goroutines — exercises `select`
// + unbuffered-channel blocking (both require TinyGo's asyncify transform).
package main

func producer(c chan<- int, val int) { c <- val }

func main() {
	c1 := make(chan int)
	c2 := make(chan int)
	go producer(c1, 100)
	go producer(c2, 200)
	total := 0
	for i := 0; i < 2; i++ {
		select {
		case v := <-c1:
			total += v
		case v := <-c2:
			total += v
		}
	}
	println("select-total:", total) // 300, regardless of order
}
