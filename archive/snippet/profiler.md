#### env.sh
```
GOOGLE_APPLICATION_CREDENTIALS=/home/isucon/service-account.json
```

#### app.go
```go
import (
	"cloud.google.com/go/profiler"
)

func initProfiler() {
	if err := profiler.Start(profiler.Config{
		Service:        "isucon",
		ServiceVersion: "1.0.0",
		ProjectID:      "isucon9-final",
	}); err != nil {
		log.Fatal(err)
	}
}

func main() {
	initProfiler()
}
```
