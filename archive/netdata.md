## install
```shell
bash <(curl -Ss https://my-netdata.io/kickstart.sh)
```

### 待ち受けポートを変える場合
`/etc/netdata/netdata.conf`
```
[global]
  default port = 8080
```

## use mysql plugin
read: https://learn.netdata.cloud/docs/data-collection/database-servers/mysql-and-mariadb#setup

```mysql
CREATE USER 'netdata'@'localhost';
GRANT USAGE, REPLICATION CLIENT, PROCESS ON *.* TO 'netdata'@'localhost';
FLUSH PRIVILEGES;
```

`/etc/netdata/go.d/mysql.conf`
```yaml
update_every: 1
autodetection_retry: 0
jobs:
  - name: local
    dsn: netdata@tcp(127.0.0.1:3306)/
```