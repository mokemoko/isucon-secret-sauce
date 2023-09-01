### for nginx

#### app.go
```go
listener, err := net.Listen("unix", "/var/run/isucon/go.sock")
if err != nil {
  log.Fatalf("error: %v", err)
}
defer func() {
  if err := listener.Close(); err != nil {
    log.Printf("error: %v", err)
  }
}()
if err := http.Serve(listener, r); err != nil {
  log.Fatalf("error: %v", err)
}

// echo
e = echo.New()
e.Listener = listener
```

#### nginx.conf
```
user isucon;

http {
    upstream api_service {
       server unix:/var/run/isucon/go.sock;
    }
}
```

### for mysql

#### app.go
```go
mysql.Config{
		Net:                  "unix",
		Addr:                 "/var/run/mysqld/mysqld.sock",
		...
	})
```