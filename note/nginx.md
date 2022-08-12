## use sticky

### with oss module
https://github.com/Refinitiv/nginx-sticky-module-ng

### with nginx plus
http://nginx.org/en/docs/http/ngx_http_upstream_module.html

```
map $request_uri $route {
 default default;
  ~\/users\/ path1;
}
upsrream {
  sticky route $route;  # assign with route
  sticky cookie srv_id; # use sticky session
}
```
