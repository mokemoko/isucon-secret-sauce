#!/usr/bin/env bash
# リハーサル用の過去問を構築する。後片付けは down.sh
# 例: AMI=ami-006d211cb716fe8a0 APP_COUNT=2 TYPE=c6a.large BENCH_TYPE=c6a.large BLACKBOX_DIR= rehearsal/up.sh   (ISUCON13)
#     既定は private-isu を1台 (ベンチは同居)
# 作るもの: key pair / security group (自IPから22,80,443、グループ内は全通信) / EC2 (isu1..isuN と、BENCH_TYPE があれば bench)。
#   全て tag Project=isucon-rehearsal、Name=<isu1|bench>。$DIR/ssh_config と $DIR/hosts.tsv (名前 公開IP プライベートIP) を書く
set -euo pipefail
TAG=isucon-rehearsal
AMI=${AMI:-ami-09201e964bee13733}   # catatsuy_private_isu_amd64_20260524
TYPE=${TYPE:-t3a.medium}            # アプリのホスト
APP_COUNT=${APP_COUNT:-1}
BENCH_TYPE=${BENCH_TYPE:-}          # 空ならベンチ専用ホストを作らない (アプリのホストで同居実行)
AZ=${AZ:-ap-northeast-1a}
SUBNET=${SUBNET:-}                  # 既定 VPC が無いアカウントでは、インターネットゲートウェイへの経路がある public サブネットを指定する (VPC はそこから決まる)
TTL_MIN=${TTL_MIN:-600}             # 消し忘れ対策: 起動から TTL_MIN 分で OS shutdown → terminate
DIR=${DIR:-$HOME/isucon/rehearsal}
VOL_GB=${VOL_GB:-}                  # 空なら AMI の容量のまま
# AMI にベンチマーカーのソースが同梱される問題で、起動時に bin/ と userdata/ 以外を消すディレクトリ。空なら何もしない
BLACKBOX_DIR=${BLACKBOX_DIR-/home/isucon/private_isu/benchmarker}

mkdir -p "$DIR"
myip=$(curl -fsS https://checkip.amazonaws.com)
tag() { echo "ResourceType=$1,Tags=[{Key=Project,Value=$TAG},{Key=Name,Value=${2:-$TAG}}]"; }

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
for p in 22 80 443; do
  aws ec2 authorize-security-group-ingress --group-id $sg --protocol tcp --port $p --cidr "$myip/32" >/dev/null
done
aws ec2 authorize-security-group-ingress --group-id $sg --protocol -1 --source-group $sg >/dev/null

# isucon ユーザーでも同じ鍵で入れるようにする
userdata=$(cat <<EOF
#!/bin/sh
shutdown -h +$TTL_MIN
install -d -m 700 -o isucon -g isucon /home/isucon/.ssh
install -m 600 -o isucon -g isucon /home/ubuntu/.ssh/authorized_keys /home/isucon/.ssh/authorized_keys
# 本番同様ベンチマーカーをブラックボックスにする: 実行に要る bin/ と userdata/ 以外 (ソース) を消す
b=$BLACKBOX_DIR
[ -n "\$b" ] && [ -d \$b/bin ] && find \$b -mindepth 1 -maxdepth 1 ! -name bin ! -name userdata -exec rm -rf {} +
EOF
)
bdm=
if [ -n "$VOL_GB" ]; then
  bdm="DeviceName=$(aws ec2 describe-images --image-ids $AMI --query 'Images[0].RootDeviceName' --output text),Ebs={VolumeSize=$VOL_GB,VolumeType=gp3,DeleteOnTermination=true}"
fi
launch() { # name type
  aws ec2 run-instances --image-id $AMI --instance-type $2 --key-name $TAG \
    --subnet-id $subnet --security-group-ids $sg --associate-public-ip-address \
    ${bdm:+--block-device-mappings "$bdm"} \
    --instance-initiated-shutdown-behavior terminate --user-data "$userdata" \
    --tag-specifications "$(tag instance $1)" "$(tag volume $1)" \
    --query 'Instances[0].InstanceId' --output text
}
names=(); ids=()
for i in $(seq 1 "$APP_COUNT"); do names+=(isu$i); ids+=("$(launch isu$i "$TYPE")"); done
[ -z "$BENCH_TYPE" ] || { names+=(bench); ids+=("$(launch bench "$BENCH_TYPE")"); }
echo "instance ${ids[*]} 起動待ち..." >&2
aws ec2 wait instance-running --instance-ids "${ids[@]}"

: >"$DIR/ssh_config"; : >"$DIR/hosts.tsv"
for k in "${!ids[@]}"; do
  read -r pub priv < <(aws ec2 describe-instances --instance-ids "${ids[$k]}" \
    --query 'Reservations[0].Instances[0].[PublicIpAddress,PrivateIpAddress]' --output text)
  printf '%s\t%s\t%s\n' "${names[$k]}" "$pub" "$priv" >>"$DIR/hosts.tsv"
  cat >>"$DIR/ssh_config" <<EOF
Host ${names[$k]}
  HostName $pub
  User isucon
  IdentityFile $DIR/key.pem
  UserKnownHostsFile $DIR/known_hosts
  StrictHostKeyChecking accept-new
EOF
done
cat "$DIR/hosts.tsv"
echo "ok: (ssh -F $DIR/ssh_config isu1)  自動削除: 起動から ${TTL_MIN} 分後"
