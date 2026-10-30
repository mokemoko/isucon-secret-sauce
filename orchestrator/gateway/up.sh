#!/usr/bin/env bash
# ダッシュボードの入口 (EC2 + Caddy)。ダッシュボード本体はオーケストレータの PC に置いたまま、PC から ssh -R で EC2 の 127.0.0.1:9180 に
# 転送し (gateway/tunnel.sh)、EC2 の Caddy が HTTPS を付けて中継する。入れるのは ALLOW_CIDRS からだけ (認証は無い。全員が同じネットワークから使う前提)。片付けは down.sh
# usage: [ALLOW_CIDRS="<CIDR> ..."] gateway/up.sh
#   DOMAIN       証明書を取るホスト名。空なら <公開IP をハイフンでつないだもの>.sslip.io (sslip.io は名前に書いた IP を返す公開 DNS)。
#                独自ドメインを使うなら、up.sh の後で A レコードを公開 IP に向け、DOMAIN=<名前> gateway/configure.sh を実行する
#   ALLOW_CIDRS  入口 (443) と ssh (22) に入れる接続元 (空白区切りの CIDR)。既定は up.sh を実行した PC の IP/32 (全員が同じネットワークから使う前提)。
#                出口の IP が複数ある NAT の内側なら、その範囲 (例 203.0.113.0/25) を渡す。後から足すときは gateway/allow.sh
#                80 は証明書の取得 (Let's Encrypt の HTTP-01。検証元の IP は決まっていない) の間だけ全体に開け、取れたら閉じる (configure.sh)
#   TYPE (t4g.nano) AZ SUBNET TTL_MIN (720。起動から TTL_MIN 分で terminate) DIR (~/isucon/gateway)
# 作るもの: key pair・security group (ALLOW_CIDRS からの 22・443 だけ)・EC2 1台。全て tag Project=isucon-gateway
set -euo pipefail
cd "$(dirname "$0")"
TAG=isucon-gateway
TYPE=${TYPE:-t4g.nano}
AZ=${AZ:-ap-northeast-1a}
SUBNET=${SUBNET:-}
TTL_MIN=${TTL_MIN:-720}
DIR=${DIR:-$HOME/isucon/gateway}
AMI=${AMI:-$(aws ssm get-parameter --name /aws/service/canonical/ubuntu/server/24.04/stable/current/arm64/hvm/ebs-gp3/ami-id --query Parameter.Value --output text)}

mkdir -p "$DIR"
myip=$(curl -fsS https://checkip.amazonaws.com)
ALLOW_CIDRS=${ALLOW_CIDRS:-$myip/32}
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
echo "$sg" >"$DIR/sg"
for c in $ALLOW_CIDRS; do
  case $c in 0.0.0.0/0|::/0) echo "ALLOW_CIDRS に全体 ($c) は渡せない (問題・計測情報の入口になる)" >&2; exit 1 ;; esac
done
ALLOW_CIDRS=$ALLOW_CIDRS DIR=$DIR ./allow.sh

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

DOMAIN=${DOMAIN:-} DIR=$DIR ./configure.sh
echo "自動削除: 起動から ${TTL_MIN} 分後。終わったら gateway/down.sh"
