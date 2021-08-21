# tools
apt update && apt install -y build-essential curl unzip screen
# optional tools
apt install -y redis-server graphviz goaccess
# golang
curl -L https://dl.google.com/go/go1.16.7.linux-amd64.tar.gz \
  | tar xz -C /usr/local/
echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
# alp
curl -LO https://github.com/tkuchiki/alp/releases/download/v1.0.7/alp_linux_amd64.zip
unzip alp_linux_amd64.zip -d /usr/local/bin/
rm alp_linux_amd64.zip
# lltsv
wget https://github.com/sonots/lltsv/releases/download/v0.3.0/lltsv_linux_amd64 -O lltsv
chmod a+x lltsv
mv lltsv /usr/local/bin/
# netdata
bash <(curl -Ss https://my-netdata.io/kickstart.sh)
# add mysql chatt
apt install -y python-mysqldb
# edit /etc/netdata/python.d/mysql.conf if need

# pt-query-digest
curl -LO https://www.percona.com/downloads/percona-toolkit/3.3.1/binary/debian/bionic/x86_64/percona-toolkit_3.3.1-1.bionic_amd64.deb
dpkg -i percona-toolkit_3.3.1-1.bionic_amd64.deb
apt --fix-broken install
rm percona-toolkit_3.3.1-1.bionic_amd64.deb

# notify_slack
curl -L https://github.com/catatsuy/notify_slack/releases/download/v0.4.4/notify_slack-linux-amd64.tar.gz \
  | tar xz -C /usr/local/bin/
