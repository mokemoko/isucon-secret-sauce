#!/usr/bin/env bash
# リハーサル用 private-isu を1台構築する (ベンチマーカーは同居実行)。後片付けは down.sh
# 作るもの: key pair / security group (自IPから22,80のみ) / EC2 1台。全て tag Project=isucon-rehearsal
set -euo pipefail
TAG=isucon-rehearsal
AMI=${AMI:-ami-09201e964bee13733}   # catatsuy_private_isu_amd64_20260524
TYPE=${TYPE:-t3a.medium}
AZ=${AZ:-ap-northeast-1a}
TTL_MIN=${TTL_MIN:-600}             # 消し忘れ対策: 起動から TTL_MIN 分で OS shutdown → terminate
DIR=${DIR:-$HOME/isucon/rehearsal}

mkdir -p "$DIR"
myip=$(curl -fsS https://checkip.amazonaws.com)
tag() { echo "ResourceType=$1,Tags=[{Key=Project,Value=$TAG},{Key=Name,Value=$TAG}]"; }

# key pair が既にあれば失敗する = 二重構築の防止
aws ec2 create-key-pair --key-name $TAG --key-type ed25519 --tag-specifications "$(tag key-pair)" \
  --query KeyMaterial --output text >"$DIR/key.pem"
chmod 600 "$DIR/key.pem"

vpc=$(aws ec2 describe-vpcs --filters Name=isDefault,Values=true --query 'Vpcs[0].VpcId' --output text)
subnet=$(aws ec2 describe-subnets --filters Name=vpc-id,Values=$vpc Name=availability-zone,Values=$AZ Name=default-for-az,Values=true \
  --query 'Subnets[0].SubnetId' --output text)
sg=$(aws ec2 create-security-group --group-name $TAG --description $TAG --vpc-id $vpc \
  --tag-specifications "$(tag security-group)" --query GroupId --output text)
for p in 22 80; do
  aws ec2 authorize-security-group-ingress --group-id $sg --protocol tcp --port $p --cidr "$myip/32" >/dev/null
done

# isucon ユーザーでも同じ鍵で入れるようにする
userdata=$(cat <<EOF
#!/bin/sh
shutdown -h +$TTL_MIN
install -d -m 700 -o isucon -g isucon /home/isucon/.ssh
install -m 600 -o isucon -g isucon /home/ubuntu/.ssh/authorized_keys /home/isucon/.ssh/authorized_keys
EOF
)
id=$(aws ec2 run-instances --image-id $AMI --instance-type $TYPE --key-name $TAG \
  --subnet-id $subnet --security-group-ids $sg --associate-public-ip-address \
  --instance-initiated-shutdown-behavior terminate --user-data "$userdata" \
  --tag-specifications "$(tag instance)" "$(tag volume)" \
  --query 'Instances[0].InstanceId' --output text)
echo "instance $id 起動待ち..." >&2
aws ec2 wait instance-running --instance-ids $id
ip=$(aws ec2 describe-instances --instance-ids $id --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)

cat >"$DIR/ssh_config" <<EOF
Host isu1
  HostName $ip
  User isucon
  IdentityFile $DIR/key.pem
  UserKnownHostsFile $DIR/known_hosts
  StrictHostKeyChecking accept-new
EOF
echo "ok: $id $ip  (ssh -F $DIR/ssh_config isu1)  自動削除: 起動から ${TTL_MIN} 分後"
