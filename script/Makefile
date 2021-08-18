all: rotate restart
	tail -f /var/log/nginx/access.log

initialize: FORCE
	curl -XPOST http://127.0.0.1:8000/initialize -H 'Content-Type: application/json' -d @initialize.json

rotate: FORCE
	logrotate -f /etc/logrotate.d/mysql-slow
	logrotate -f /etc/logrotate.d/nginx

restart: FORCE
	systemctl restart mysql
	systemctl restart isucari.golang.service
	systemctl restart nginx

pt: FORCE
	pt-query-digest /var/log/mysql/slow.log

alp: FORCE
	alp ltsv -c alp.yml

ltsv: FORCE
	cat /var/log/nginx/access.log | lltsv -k time,status,reqtime,uri -K

FORCE:
.PHONY: FORCE
