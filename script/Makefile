all: rotate restart
	sudo tail -f /var/log/nginx/access.log

initialize: FORCE
	curl -XPOST http://127.0.0.1:8000/initialize -H 'Content-Type: application/json' -d @initialize.json

rotate: FORCE
	sudo logrotate -f /etc/logrotate.d/mysql-server
	sudo logrotate -f /etc/logrotate.d/nginx

restart: FORCE
	sudo systemctl restart mysql
	sudo systemctl restart isucari.golang.service
	sudo systemctl restart nginx

pt: FORCE
	sudo pt-query-digest /var/log/mysql/slow.log

alp: FORCE
	sudo alp ltsv -c alp.yml

ltsv: FORCE
	sudo cat /var/log/nginx/access.log | lltsv -k time,status,reqtime,uri -K

pprof: FORCE
	go tool pprof -http="0.0.0.0:8081" http://localhost:5000/debug/pprof/profile

FORCE:
.PHONY: FORCE
