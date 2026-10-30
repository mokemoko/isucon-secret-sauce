#!/usr/bin/env bash
# ダッシュボードの入口 (EC2 + Caddy)。ダッシュボード本体はオーケストレータの PC に置いたまま、PC から ssh -R で EC2 の 127.0.0.1:9180 に
# 転送し (gateway/tunnel.sh)、EC2 の Caddy が HTTPS と Basic 認証を付けて中継する。Tailscale を入れられないメンバーとの共有用。片付けは down.sh
# usage: USERS="alice bob carol" gateway/up.sh
#   USERS        ダッシュボードに入る人の名前 (空白区切り。必須)。パスワードは生成して $DIR/users.txt に書く (各自に配る。コミット・チャットへの貼り付けをしない)
#                名前はダッシュボードの示唆・判断待ちの回答に、送った人として付く
#   DOMAIN       証明書を取るホスト名。空なら <公開IP をハイフンでつないだもの>.sslip.io (sslip.io は名前に書いた IP を返す公開 DNS)。
#                独自ドメインを使うなら、先に up.sh を DOMAIN 無しで実行して IP を見て A レコードを向け、DOMAIN=<名前> gateway/configure.sh を実行する
#   ALLOW_CIDRS  443 に入れる接続元 (空白区切りの CIDR)。空なら全体 (Basic 認証で守る)。80 は証明書の取得 (HTTP-01) のため常に全体
#   TYPE (t4g.nano) AZ SUBNET TTL_MIN (720。起動から TTL_MIN 分で terminate) DIR (~/isucon/gateway)
# 作るもの: key pair・security group (22 は自 IP だけ)・EC2 1台。全て tag Project=isucon-gateway
set -euo pipefail
cd "$(dirname "$0")"
TAG=isucon-gateway
: "${USERS:?USERS=\"<名前> ...\" を渡す (ダッシュボードに入る人)}"
TYPE=${TYPE:-t4g.nano}
AZ=${AZ:-ap-northeast-1a}
SUBNET=${SUBNET:-}
TTL_MIN=${TTL_MIN:-720}
DIR=${DIR:-$HOME/isucon/gateway}
ALLOW_CIDRS=${ALLOW_CIDRS:-0.0.0.0/0}
AMI=${AMI:-$(aws ssm get-parameter --name /aws/service/canonical/ubuntu/server/24.04/stable/current/arm64/hvm/ebs-gp3/ami-id --query Parameter.Value --output text)}

mkdir -p "$DIR"
myip=$(curl -fsS https://checkip.amazonaws.com)
tag() { echo "ResourceType=$1,Tags=[{Key=Project,Value=$TAG},{Key=Name,Value=$TAG}]"; }

if [ -n "$SUBNET" ]; then
  subnet=$SUBNET
  vpc=$(aws ec2 describe-subnets --subnet-ids $subnet --query 'Subnets[0].VpcId' --output text)
else
  vpc=$(aws ec2 describe-vpcs --filters Name=isDefault,Values=true --query 'Vpcs[0].VpcId' --output text)
  subnet=$(aws ec2 describe-subnets --filters Name=vpc-id,Values=$vpc Name=availability-zone,Values=$AZ Name=default-for-az,Values=true \
    --query 'Subnets[0].SubnetId' --output text)
fi
[ "$vpc" != None ] && [ "$subnet" != None ] || { echo "VPC・サブネットが見つからない (既定 VPC が無ければ SUBNET=<public サブネット> を指定)" >&2; exit 1; }

# key pair が既にあれば失敗する = 二重構築の防止
aws ec2 create-key-pair --key-name $TAG --key-type ed25519 --tag-specifications "$(tag key-pair)" \
  --query KeyMaterial --output text >"$DIR/key.pem"
chmod 600 "$DIR/key.pem"
sg=$(aws ec2 create-security-group --group-name $TAG --description $TAG --vpc-id $vpc \
  --tag-specifications "$(tag security-group)" --query GroupId --output text)
aws ec2 authorize-security-group-ingress --group-id $sg --protocol tcp --port 22 --cidr "$myip/32" >/dev/null
aws ec2 authorize-security-group-ingress --group-id $sg --protocol tcp --port 80 --cidr 0.0.0.0/0 >/dev/null
for c in $ALLOW_CIDRS; do aws ec2 authorize-security-group-ingress --group-id $sg --protocol tcp --port 443 --cidr "$c" >/dev/null; done

id=$(aws ec2 run-instances --image-id $AMI --instance-type $TYPE --key-name $TAG \
  --subnet-id $subnet --security-group-ids $sg --associate-public-ip-address \
  --metadata-options HttpTokens=required \
  --instance-initiated-shutdown-behavior terminate --user-data "#!/bin/sh
shutdown -h +$TTL_MIN" \
  --tag-specifications "$(tag instance)" "$(tag volume)" \
  --query 'Instances[0].InstanceId' --output text)
echo "instance $id 起動待ち..." >&2
aws ec2 wait instance-running --instance-ids "$id"
pub=$(aws ec2 describe-instances --instance-ids "$id" --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
cat >"$DIR/ssh_config" <<C
Host isucon-gateway
  HostName $pub
  User ubuntu
  IdentityFile $DIR/key.pem
  UserKnownHostsFile $DIR/known_hosts
  StrictHostKeyChecking accept-new
  ServerAliveInterval 15
  ServerAliveCountMax 3
C
echo "$pub" >"$DIR/ip"
until ssh -F "$DIR/ssh_config" -o ConnectTimeout=5 isucon-gateway true 2>/dev/null; do sleep 5; done
ssh -F "$DIR/ssh_config" isucon-gateway 'cloud-init status --wait >/dev/null; sudo apt-get -qq update && sudo DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt-get -qq install -y caddy >/dev/null 2>&1 && caddy version'

# パスワードを生成して $DIR/users.txt に (既にあれば使い回す)
touch "$DIR/users.txt"; chmod 600 "$DIR/users.txt"
for u in $USERS; do
  grep -q "^$u " "$DIR/users.txt" || echo "$u $(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 20)" >>"$DIR/users.txt"
done
DOMAIN=${DOMAIN:-} DIR=$DIR ./configure.sh
echo "自動削除: 起動から ${TTL_MIN} 分後。終わったら gateway/down.sh"
