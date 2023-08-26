package main

import (
	"sync"
	"time"
)

var (
	queue Queue
)

type Queue struct {
	mutex sync.Mutex
	que   []interface{}
}

func tick(interval time.Duration) {
	ticker := time.NewTicker(interval)
	defer ticker.Stop()
	process()
	for {
		select {
		case <-ticker.C:
			process()
		}
	}
}

func process() {
	queue.mutex.Lock()
	// do anything
	queue.mutex.Unlock()
}

func main() {
	go tick(100 * time.Millisecond)
}
